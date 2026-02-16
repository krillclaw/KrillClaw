#!/bin/bash
# YoctoClaw Embedded/QEMU Test Script
# Tests cross-compilation for embedded targets and documents QEMU testing.
#
# Prerequisites:
#   - Zig (with cross-compilation support built-in)
#   - QEMU (optional, for simulated execution)
#     macOS: brew install qemu
#     Linux: apt install qemu-system-arm qemu-user-static

set -o pipefail

PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
skip() { echo "  ⏭  SKIP: $1 — $2"; SKIP=$((SKIP + 1)); }

cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)

echo "═══════════════════════════════════════"
echo "  YoctoClaw Embedded / QEMU Tests"
echo "═══════════════════════════════════════"
echo ""

# ─────────────────────────────────────────
# 1. Cross-compile for ARM Linux (user-space, not bare-metal)
#    This is the most practical embedded target — runs on RPi, etc.
# ─────────────────────────────────────────
echo "--- ARM Linux (aarch64) ---"

if zig build -Dtarget=aarch64-linux -Dprofile=iot -Doptimize=ReleaseSmall 2>&1; then
    BINARY="./zig-out/bin/yoctoclaw"
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat --printf="%s" "$BINARY" 2>/dev/null || echo 0)
    echo "  aarch64-linux IoT binary: $SIZE bytes ($(( SIZE / 1024 ))KB)"
    pass "cross-compile aarch64-linux IoT"

    # Verify it's actually an ARM ELF
    if file "$BINARY" | grep -q "aarch64\|ARM"; then
        pass "binary is ARM ELF"
    else
        fail "binary architecture" "$(file "$BINARY")"
    fi
else
    fail "cross-compile aarch64-linux IoT" "build failed"
fi

echo ""
echo "--- ARM Linux (armv7, 32-bit — e.g. RPi Zero) ---"
if zig build -Dtarget=arm-linux -Dprofile=iot -Doptimize=ReleaseSmall 2>&1; then
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat --printf="%s" "$BINARY" 2>/dev/null || echo 0)
    echo "  arm-linux IoT binary: $SIZE bytes ($(( SIZE / 1024 ))KB)"
    pass "cross-compile arm-linux (32-bit) IoT"
else
    fail "cross-compile arm-linux IoT" "build failed"
fi

echo ""
echo "--- RISC-V Linux ---"
if zig build -Dtarget=riscv64-linux -Dprofile=iot -Doptimize=ReleaseSmall 2>&1; then
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat --printf="%s" "$BINARY" 2>/dev/null || echo 0)
    echo "  riscv64-linux IoT binary: $SIZE bytes ($(( SIZE / 1024 ))KB)"
    pass "cross-compile riscv64-linux IoT"
else
    fail "cross-compile riscv64-linux IoT" "build failed"
fi

echo ""
echo "--- x86_64 Linux (robotics profile) ---"
if zig build -Dtarget=x86_64-linux -Dprofile=robotics -Doptimize=ReleaseSmall 2>&1; then
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat --printf="%s" "$BINARY" 2>/dev/null || echo 0)
    echo "  x86_64-linux robotics binary: $SIZE bytes ($(( SIZE / 1024 ))KB)"
    pass "cross-compile x86_64-linux robotics"
else
    fail "cross-compile x86_64-linux robotics" "build failed"
fi

# ─────────────────────────────────────────
# 2. Embedded/freestanding build (if supported)
# ─────────────────────────────────────────
echo ""
echo "--- Freestanding ARM (bare-metal attempt) ---"
echo "  NOTE: Freestanding builds require no OS syscalls."
echo "  YoctoClaw uses std.http and std.fs, so true bare-metal"
echo "  requires a HAL abstraction layer (future work)."

if zig build -Dtarget=aarch64-freestanding -Dembedded=true -Dprofile=iot -Doptimize=ReleaseSmall 2>&1; then
    pass "cross-compile aarch64-freestanding"
else
    skip "aarch64-freestanding" "expected — requires OS-free abstractions"
fi

# ─────────────────────────────────────────
# 3. QEMU Execution Tests
# ─────────────────────────────────────────
echo ""
echo "--- QEMU Tests ---"

if command -v qemu-aarch64 &>/dev/null || command -v qemu-aarch64-static &>/dev/null; then
    QEMU=$(command -v qemu-aarch64 || command -v qemu-aarch64-static)

    # Rebuild for aarch64-linux
    zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSmall 2>/dev/null

    # Test --version via QEMU user-mode emulation
    OUTPUT=$($QEMU "$BINARY" --version 2>&1 || true)
    if echo "$OUTPUT" | grep -q "yoctoclaw"; then
        pass "QEMU aarch64: --version works"
    else
        fail "QEMU aarch64: --version" "$OUTPUT"
    fi

    # Test --help
    OUTPUT=$($QEMU "$BINARY" --help 2>&1 || true)
    if echo "$OUTPUT" | grep -q "YoctoClaw"; then
        pass "QEMU aarch64: --help works"
    else
        fail "QEMU aarch64: --help" "no output"
    fi
else
    skip "QEMU user-mode tests" "qemu-aarch64 not installed"
    echo ""
    echo "  To install QEMU for user-mode emulation:"
    echo "    macOS:  brew install qemu"
    echo "    Ubuntu: sudo apt install qemu-user-static"
    echo ""
    echo "  Then run ARM binaries directly:"
    echo "    qemu-aarch64 ./zig-out/bin/yoctoclaw --version"
    echo "    qemu-aarch64 ./zig-out/bin/yoctoclaw --help"
fi

# ─────────────────────────────────────────
# 4. Documentation: Real Hardware Testing
# ─────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  HARDWARE TESTING GUIDE"
echo "═══════════════════════════════════════"
cat << 'GUIDE'

  For real hardware testing, you need:

  Raspberry Pi (ARM64):
    1. Cross-compile: zig build -Dtarget=aarch64-linux -Dprofile=iot -Doptimize=ReleaseSmall
    2. Copy: scp zig-out/bin/yoctoclaw pi@<ip>:~/
    3. Run: ssh pi@<ip> './yoctoclaw --version'

  ESP32 / STM32 (future — requires HAL):
    - Zig can target these via: -Dtarget=thumb-freestanding
    - But YoctoClaw needs HTTP stack replacement (no std.http)
    - Would need: embedded HTTP client, flash filesystem, UART transport
    - The -Dembedded=true flag + -Dtransport=serial is the starting point

  QEMU System Emulation (full VM):
    # ARM virt machine with Linux kernel
    qemu-system-aarch64 \
      -M virt -cpu cortex-a57 -m 256M \
      -kernel <linux-kernel-image> \
      -initrd <initramfs-with-yoctoclaw> \
      -nographic -append "console=ttyAMA0"

    # For quick tests, user-mode is much simpler:
    qemu-aarch64 ./zig-out/bin/yoctoclaw --help

  RISC-V:
    qemu-riscv64 ./zig-out/bin/yoctoclaw --help

GUIDE

# ─────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo "  Total:   $TOTAL"
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
echo "  Skipped: $SKIP"
echo ""
[ "$FAIL" -eq 0 ] && echo "  🎉 ALL TESTS PASSED" || echo "  ⚠️  $FAIL TEST(S) FAILED"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
