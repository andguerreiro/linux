#!/usr/bin/env bash

# Change this path to the mount point of the external storage
MOUNT_POINT="/media/and/6EFC-6EC4"

# Test file size in MiB
TEST_SIZE_MB=1024

TEST_FILE="$MOUNT_POINT/speed-test.bin"

if [ ! -d "$MOUNT_POINT" ]; then
    echo "Error: mount point does not exist:"
    echo "  $MOUNT_POINT"
    exit 1
fi

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "Error: this path is not a mounted filesystem:"
    echo "  $MOUNT_POINT"
    exit 1
fi

if [ ! -w "$MOUNT_POINT" ]; then
    echo "Error: mount point is not writable:"
    echo "  $MOUNT_POINT"
    exit 1
fi

if [ -e "$TEST_FILE" ]; then
    echo "Error: test file already exists:"
    echo "  $TEST_FILE"
    echo "Remove it manually or choose another file name."
    exit 1
fi

cleanup() {
    if [ -f "$TEST_FILE" ]; then
        echo
        echo "Removing test file..."
        rm -f "$TEST_FILE"
    fi
}

trap cleanup EXIT

echo "Storage mount point: $MOUNT_POINT"
echo "Test file size:      ${TEST_SIZE_MB} MiB"
echo

echo "=== Sequential write test ==="

dd if=/dev/zero \
    of="$TEST_FILE" \
    bs=1M \
    count="$TEST_SIZE_MB" \
    oflag=direct \
    status=progress

if [ $? -ne 0 ]; then
    echo "Write test failed."
    exit 1
fi

echo
echo "=== Sequential read test ==="

dd if="$TEST_FILE" \
    of=/dev/null \
    bs=1M \
    iflag=direct \
    status=progress

if [ $? -ne 0 ]; then
    echo "Read test failed."
    exit 1
fi

echo
echo "Tests completed successfully."
