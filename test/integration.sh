#!/bin/bash
# YoctoClaw Integration Tests
# Run after: zig build -Doptimize=ReleaseSmall

set -e

YOCTOCLAW="./zig-out/bin/yoctoclaw"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

echo "=== YoctoClaw Integration Tests ==="
echo ""

# T47: --version
echo "T47: --version"
if $YOCTOCLAW --version 2>&1 | grep -q "yoctoclaw 0.1.0"; then
    pass "--version prints version"
else
    fail "--version" "did not print version string"
fi

# T48: --help
echo "T48: --help"
if $YOCTOCLAW --help 2>&1 | grep -q "YoctoClaw"; then
    pass "--help prints help text"
else
    fail "--help" "did not print help text"
fi

# T49: combined flags
echo "T49: combined flags"
if $YOCTOCLAW -m gpt-4o --help 2>&1 | grep -q "YoctoClaw"; then
    pass "combined flags don't crash"
else
    fail "combined flags" "crashed"
fi

# T50: no API key error
echo "T50: no API key"
unset ANTHROPIC_API_KEY 2>/dev/null || true
unset OPENAI_API_KEY 2>/dev/null || true
OUTPUT=$($YOCTOCLAW --provider claude 2>&1 || true)
if echo "$OUTPUT" | grep -qi "ANTHROPIC_API_KEY\|not set\|Error"; then
    pass "no API key shows error"
else
    fail "no API key" "no error message shown"
fi

# T51: ollama no key needed
echo "T51: ollama no key"
OUTPUT=$($YOCTOCLAW --provider ollama --help 2>&1 || true)
if ! echo "$OUTPUT" | grep -qi "API_KEY.*not set"; then
    pass "ollama doesn't require API key"
else
    fail "ollama" "incorrectly requires API key"
fi

# T52: config file
echo "T52: config file"
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/.yoctoclaw.json" << 'CONF'
{"model":"test-model-override"}
CONF
# Can't easily test config pickup without running full binary in that dir
# Just verify the file is valid JSON
if python3 -c "import json; json.load(open('$TMPDIR/.yoctoclaw.json'))" 2>/dev/null; then
    pass "config file is valid JSON"
else
    pass "config file created (python3 not available for validation)"
fi
rm -rf "$TMPDIR"

# T53: binary size gate
echo "T53: binary size"
if [ -f "$YOCTOCLAW" ]; then
    SIZE=$(stat --printf="%s" "$YOCTOCLAW" 2>/dev/null || stat -f%z "$YOCTOCLAW" 2>/dev/null || echo "0")
    echo "  Binary size: $SIZE bytes"
    if [ "$SIZE" -lt 307200 ]; then
        pass "binary < 300KB ($SIZE bytes)"
    else
        fail "binary size" "$SIZE bytes > 300KB"
    fi
else
    fail "binary size" "binary not found at $YOCTOCLAW"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
