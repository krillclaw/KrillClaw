#!/bin/sh
BINARY="$1"
BUDGET="$2"
PROFILE="$3"
SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat -c%s "$BINARY" 2>/dev/null)
echo "$PROFILE binary size: $SIZE bytes (budget: $BUDGET)"
if [ "$SIZE" -gt "$BUDGET" ]; then
    if [ "$PROFILE" = "lite" ]; then
        echo "FAIL: $PROFILE binary $SIZE exceeds $BUDGET byte budget"
        exit 1
    else
        echo "WARN: $PROFILE binary $SIZE exceeds $BUDGET byte budget (macOS binaries are ~2x Linux-musl)"
    fi
else
    echo "PASS: $PROFILE within budget"
fi
