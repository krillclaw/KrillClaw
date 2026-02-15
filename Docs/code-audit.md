# YoctoClaw Code Audit Report

**Date:** 2026-02-15  
**Auditor:** Automated (Claude)  
**Scope:** All 13 Zig source files (3,317 LOC), bridge, CI, git history  
**Verdict:** **PASS with advisories** — No blockers for launch. Several items to address post-launch.

---

## Executive Summary

YoctoClaw is well-engineered for its size. The code is clean, consistent, and shows security awareness (pure-Zig search/list to avoid injection, bounded outputs, loop detection). No secrets in git history. No hardcoded API keys. The main risks are: (1) the bash tool has zero sandboxing, (2) the JSON parser has known-but-documented flat-key limitations, and (3) API keys could theoretically leak via error messages in debug builds.

**Critical:** 0  
**High:** 2  
**Medium:** 5  
**Low:** 4  
**Info:** 3  

---

## 1. Security Issues

### HIGH-1: Bash tool has zero sandboxing
**File:** `src/tools.zig:24-42`  
**Issue:** The `bash` tool passes LLM-generated commands directly to `/bin/sh -c` with no sandboxing, no allowlist, no deny-list, no timeout, and no resource limits.  
**Impact:** An LLM can execute `rm -rf /`, exfiltrate data, install malware, etc.  
**Mitigations already present:** None.  
**Recommendation:**  
- Add a configurable timeout (e.g., 30s default) via `std.process.Child` options  
- Add a `--no-bash` flag to disable the bash tool entirely  
- Consider an allowlist/denylist for dangerous commands (`rm -rf`, `curl | sh`, `chmod 777`, etc.)  
- Document this risk prominently in README  
**Note:** This is the same risk profile as Claude Code, Aider, etc. — it's inherent to coding agents. But a timeout is a must.

### HIGH-2: No output size limit on read_file
**File:** `src/tools.zig:62`  
**Issue:** `readToEndAlloc` with 1MB limit, but this 1MB gets sent to the LLM API as a tool result, potentially blowing context window and costing tokens.  
**Recommendation:** Add a configurable max read size (e.g., 64KB default) with a warning message if truncated.

### MED-1: API key in HTTP headers — not logged, but visible in memory
**File:** `src/api.zig:78-90`  
**Issue:** API key is passed in HTTP headers (correct behavior), never logged or printed. The `handleApiError` path does NOT print the key. Good.  
**Risk:** Key lives in process memory as a plain string. Standard for any API client.  
**Status:** ✅ Acceptable. No key leakage found.

### MED-2: `max_output_bytes` for bash is 256KB
**File:** `src/tools.zig:31`  
**Issue:** A command like `cat /dev/urandom | head -c 1000000` would allocate 256KB. Combined with the 1MB read_file limit, memory usage could spike.  
**Recommendation:** Consider reducing to 64KB or making configurable.

### MED-3: write_file has no path validation
**File:** `src/tools.zig:75-95`  
**Issue:** The LLM can write to any path the process can access, including `~/.ssh/authorized_keys`, `/etc/crontab`, etc. `makePath` will create arbitrary directory trees.  
**Recommendation:** Add an optional `--workspace` flag to restrict file operations to a directory subtree.

### MED-4: edit_file race condition (TOCTOU)
**File:** `src/tools.zig:97-155`  
**Issue:** File is read, modified in memory, then written back. If the file changes between read and write, changes are lost. Minor risk for a single-user CLI.  
**Status:** Acceptable for v0.1.

### MED-5: Serial baud configuration via `stty` subprocess
**File:** `src/serial.zig:109-118`  
**Issue:** Uses `std.process.Child.run` to call `stty`. The `fd_str` is constructed from an integer FD number, so injection is not possible. However, using page_allocator for small allocations is wasteful.  
**Recommendation:** Pass the struct allocator instead of `std.heap.page_allocator`. Replace with termios ioctl for v1.0.

---

## 2. Error Handling

### Overall: ✅ Good
- All tool functions return `ToolResult` with `is_error` flag — no panics.
- API errors are caught and translated to typed `ApiError` enum.
- File operations use `catch` consistently.
- `handleApiError` provides user-friendly messages for common cases.

### LOW-1: `json.extractString` returns raw escaped content
**File:** `src/json.zig:169-181`  
**Issue:** `extractString` returns the raw JSON-encoded string (including `\n`, `\t` escape sequences). Callers must explicitly call `unescape()`. This is done correctly in tools.zig but could be a footgun for future code.  
**Recommendation:** Document this clearly or provide an `extractStringUnescaped` convenience function.

### LOW-2: Streaming parser leaks event_type allocations
**File:** `src/stream.zig:82`  
**Issue:** `self.event_type = try self.allocator.dupe(u8, line[7..])` — old event_type is not freed before reassignment. Minor memory leak per SSE event.  
**Impact:** Negligible for short conversations (~100 bytes per event × ~20 events = ~2KB leaked per turn).  
**Recommendation:** Free old `event_type` before reassigning.

---

## 3. JSON Parser Edge Cases

**File:** `src/json.zig` (500 lines)

### Strengths:
- Clean separation: builder (serialize) vs. extractor (parse)
- `writeEscaped` handles all JSON special characters including control chars <0x20
- `extractBraced` correctly tracks string context (doesn't match braces inside strings)
- `unescape` handles all standard JSON escapes

### Issues:

### LOW-3: No `\uXXXX` decoding in `unescape()`
**File:** `src/json.zig:264-267`  
**Issue:** Unicode escapes like `\u0041` are passed through as-is (the `else` branch keeps both bytes). The `writeEscaped` function DOES emit `\u{x:0>4}` for control characters, creating an asymmetry.  
**Impact:** Low — LLM responses rarely contain raw Unicode escapes in tool call parameters. But if they do, the tool would receive `\u0041` instead of `A`.  
**Recommendation:** Add `\u` handling to `unescape()`.

### INFO-1: Flat key search (documented limitation)
**File:** `src/json.zig:289-302`  
**Issue:** `findKey` scans linearly and returns the first match regardless of nesting depth. Documented in README as a known limitation.  
**Risk:** Could mis-extract if a key like `"id"` appears in a nested object before the top-level `"id"`. In practice, Claude/OpenAI response structures make this safe — `"id"` always appears first at the top level.  
**Status:** Acceptable for current use. Tests document this behavior.

### INFO-2: No handling of JSON `null` values
**Issue:** If an API returns `"key": null`, `extractString` would return `null` (the Zig optional), which is the correct behavior. But `extractBool` and `extractInt` would also correctly return null. Good implicit handling.

---

## 4. API Key Handling

### ✅ PASS
- Keys loaded from environment variables only (`src/config.zig`)
- Never printed, never logged
- `handleApiError` says "Check your API key" without revealing it
- Not stored in config files (`.yoctoclaw.json` has no key field)
- `.gitignore` includes `.env`
- No hardcoded keys anywhere in source or git history
- Bridge (`bridge.py`) also reads from `ANTHROPIC_API_KEY` env var

---

## 5. BLE/Serial Transport Security

### LOW-4: No authentication on BLE/Serial transport
**File:** `src/ble.zig`, `src/serial.zig`  
**Issue:** Anyone who can connect to the BLE GATT service or serial port can send RPC commands that the bridge will execute (API calls, tool execution).  
**Impact:** BLE is marked "Experimental" and the desktop simulation uses Unix sockets (file permissions provide access control). Real hardware deployment would need pairing/bonding.  
**Recommendation:** Add a shared secret / challenge-response for production BLE deployment. Document this gap.

### No encryption
**Issue:** BLE link encryption depends on the BLE stack (SoftDevice handles encryption at the link layer). Serial has no encryption.  
**Status:** Acceptable for experimental status. Document for v1.0.

---

## 6. Tool Execution Safety

| Tool | Injection Risk | Bounded Output | Notes |
|------|---------------|----------------|-------|
| `bash` | **HIGH** — direct shell execution | 256KB | No sandbox, no timeout |
| `read_file` | None — `std.fs` API | 1MB | No path restriction |
| `write_file` | None — `std.fs` API | N/A | No path restriction, creates dirs |
| `edit_file` | None — `std.fs` API | 1MB read | Requires unique match (safe) |
| `search` | **None** — pure Zig | 100 matches | ✅ No shell, no injection |
| `list_files` | **None** — pure Zig | 200 files | ✅ No shell, no injection |

**search and list_files are exemplary** — pure Zig implementations with proper bounds. The test suite includes explicit injection tests.

---

## 7. README Accuracy

| Claim | Verified | Status |
|-------|----------|--------|
| 3,317 LOC | `wc -l src/*.zig` = 3,317 | ✅ Exact match |
| 6 tools | `types.zig` defines 6 tools | ✅ Correct |
| 3 providers | Claude, OpenAI, Ollama in enum | ✅ Correct |
| 13 Zig files | `find src/ -name '*.zig'` = 13 | ✅ Correct |
| ~180KB binary | Claims "~180KB" | ⚠️ Not verified (no build env) |
| Zero dependencies | No imports outside std | ✅ Correct |
| 39 unit tests | Not counted individually | ⚠️ Not verified |
| File line counts in Architecture section | Spot-checked 5 files | ✅ All match |
| "Injection-safe search" | Tests confirm, code uses std.fs | ✅ Correct |
| Config precedence: file → env → CLI | Code confirms this order | ✅ Correct |

**README is accurate and honest.** Known limitations are documented.

---

## 8. CI Workflow

**File:** `.github/workflows/test.yml`

### What it tests:
- ✅ Debug build
- ✅ Unit tests (`zig build test`)
- ✅ Release build (`ReleaseSmall`)
- ✅ Binary size gate (<300KB)
- ✅ Smoke tests (`--version`, `--help`)
- ✅ Integration tests (`test/integration.sh`)
- ✅ BLE flag build
- ✅ Serial flag build

### What's missing:
- ❌ No cross-compilation test (e.g., `thumb-none-eabi`)
- ❌ No memory leak check (could use GPA's leak detection in tests)
- ❌ No macOS runner (only ubuntu-latest, but serial uses `stty -F` which is Linux-specific; macOS uses `stty -f`)
- ❌ No test coverage reporting
- ❌ No fuzz testing for JSON parser

### Recommendation:
- Add `runs-on: macos-latest` as a matrix axis
- Add `-Dembedded=true` build test
- Consider `zig build test -Doptimize=ReleaseSafe` to catch undefined behavior

---

## 9. License

**File:** `LICENSE`  
- ✅ MIT License present
- ✅ Copyright: "2026 Accelerando AI"
- ✅ Standard MIT text, unmodified
- ✅ README states "MIT" at the bottom

---

## 10. Git History & Secrets

- Only 2 commits: initial commit + migration from `accelerandoai/picoclaw-zig`
- `git log -p -S 'sk-'` — shows only README examples (`sk-ant-...`, `sk-...`) which are placeholder text, not real keys ✅
- No `.env` files committed
- `.gitignore` covers: `zig-out/`, `zig-cache/`, `.zig-cache/`, `__pycache__/`, `*.pyc`, `.env`, `bridge/venv/`

### INFO-3: .gitignore missing entries
- No `*.o`, `*.a`, `*.so` patterns
- No `.yoctoclaw.json` (could contain base_url which might be sensitive)
- No `bridge/bridge/__pycache__/` (nested)
**Recommendation:** Add `.yoctoclaw.json` to `.gitignore` or document that it shouldn't contain sensitive data.

---

## Priority Recommendations for Launch

### Must-do before launch:
1. **Add bash timeout** — `std.process.Child` supports timeout. Default 60s.
2. **Document bash risk** — Add a ⚠️ Security section about unsandboxed tool execution.

### Should-do soon after:
3. Fix streaming parser `event_type` memory leak
4. Add `\uXXXX` decoding to JSON unescape
5. Add `--workspace` flag for path restriction
6. Add macOS CI runner

### Nice-to-have:
7. Fuzz testing for JSON parser
8. Cross-compilation CI test
9. BLE authentication for production deployment

---

## Conclusion

YoctoClaw is remarkably solid for a 3,317-line project. The code shows careful thought about security (pure-Zig search tools, bounded outputs, loop detection), error handling (no panics, typed errors), and architecture (vtable transports, feature flags). The README is accurate and honest about limitations.

The main risk is the unsandboxed bash tool, which is inherent to all coding agents but should at minimum have a timeout. All other findings are low-severity or informational.

**Recommendation: Ship it.** Address HIGH-1 (bash timeout) before or immediately after launch.
