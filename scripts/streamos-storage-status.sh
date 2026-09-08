#!/bin/bash
# streamos-storage-status — confirm live image did not mount internal storage
set -euo pipefail

echo "=== Loki StreamOS Storage Status ==="
echo "Release: $(grep PRETTY_NAME /etc/streamos-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo unknown)"
echo ""

echo "-- Mounted filesystems (live image only expected) --"
findmnt -lo TARGET,SOURCE,FSTYPE,LABEL | grep -E 'TARGET|/$|/boot|LOKI_' || findmnt -lo TARGET,SOURCE,FSTYPE

echo ""
echo "-- Internal fixed disks (must NOT be mounted) --"
FAIL=0
for dev in /dev/nvme*n1 /dev/mmcblk*; do
    [[ -e "$dev" ]] || continue
    if findmnt -n "$dev" &>/dev/null; then
        echo "FAIL: $dev is mounted"
        findmnt "$dev"
        FAIL=1
    else
        echo "OK:   $dev not mounted"
    fi
done

echo ""
echo "-- Block devices --"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS 2>/dev/null || lsblk

if [[ "$FAIL" -ne 0 ]]; then
    echo ""
    echo "RESULT: UNSAFE — internal storage is mounted"
    exit 1
fi

echo ""
echo "RESULT: OK — internal storage not mounted by StreamOS"
