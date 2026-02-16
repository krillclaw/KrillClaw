#!/bin/bash
# Create minimal initramfs with yoctoclaw as init
ARCH=$1
BINARY=$2
OUTFILE=$3

TMPDIR=$(mktemp -d)
mkdir -p $TMPDIR/{bin,dev,proc,sys,tmp}

# Copy binary
cp $BINARY $TMPDIR/bin/yoctoclaw
chmod +x $TMPDIR/bin/yoctoclaw

# Create init script
cat > $TMPDIR/init << EOF
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
echo "=== QEMU Boot OK ==="
/bin/yoctoclaw --version
echo "=== Exit code: \$? ==="
echo "=== QEMU Test Complete ==="
poweroff -f
EOF
chmod +x $TMPDIR/init

# Create initramfs
cd $TMPDIR
find . | cpio -o -H newc 2>/dev/null | gzip > $OUTFILE
rm -rf $TMPDIR
echo "Created $OUTFILE"
