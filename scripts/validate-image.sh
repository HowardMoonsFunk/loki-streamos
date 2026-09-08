#!/bin/bash
# validate-image.sh — structural checks on a built .img (CI and local)
set -euo pipefail

IMG="${1:-}"
[[ -n "$IMG" && -f "$IMG" ]] || { echo "Usage: validate-image.sh path/to/loki-streamos-*.img" >&2; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Must run as root" >&2; exit 1; }

BOOT_SIZE_MB=512
BOOT_OFFSET=$((1024 * 1024))
SYSTEM_OFFSET=$((BOOT_SIZE_MB * 1024 * 1024))
BOOT_SIZE_BYTES=$((SYSTEM_OFFSET - BOOT_OFFSET))

MNT_BOOT="$(mktemp -d)"
MNT_SYS="$(mktemp -d)"
LOOP_DEV=""

cleanup() {
    umount "$MNT_BOOT" "$MNT_SYS" 2>/dev/null || true
    for d in $LOOP_DEV; do losetup -d "$d" 2>/dev/null || true; done
    rmdir "$MNT_BOOT" "$MNT_SYS" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Image file ==="
ls -lh "$IMG"
file "$IMG"

echo "=== Partition table ==="
parted -s "$IMG" unit MiB print

LOOP_DEV="$(losetup -fP --show "$IMG")"
partx -a "$LOOP_DEV" 2>/dev/null || true
sleep 1

BOOT="${LOOP_DEV}p1"
SYS="${LOOP_DEV}p2"
[[ -b "$BOOT" ]] || BOOT="${LOOP_DEV}1"
[[ -b "$SYS" ]] || SYS="${LOOP_DEV}2"

if [[ -b "$BOOT" && -b "$SYS" ]]; then
    mount "$BOOT" "$MNT_BOOT"
    mount "$SYS" "$MNT_SYS"
else
    BOOT_L="$(losetup -f --show -o "$BOOT_OFFSET" --sizelimit "$BOOT_SIZE_BYTES" "$IMG")"
    SYS_L="$(losetup -f --show -o "$SYSTEM_OFFSET" "$IMG")"
    LOOP_DEV="$BOOT_L $SYS_L"
    mount "$BOOT_L" "$MNT_BOOT"
    mount "$SYS_L" "$MNT_SYS"
fi

check() { [[ -e "$1" ]] || { echo "MISSING: $1" >&2; exit 1; }; echo "OK: $1"; }

echo "=== EFI / boot ==="
check "$MNT_BOOT/loader/loader.conf"
check "$MNT_BOOT/loader/entries/loki-streamos.conf"
check "$MNT_BOOT/vmlinuz-linux-lts"
check "$MNT_BOOT/initramfs-linux-lts.img"
ls -la "$MNT_BOOT/EFI/systemd/" 2>/dev/null || ls -la "$MNT_BOOT/EFI/" || { echo "MISSING: EFI bootloader" >&2; exit 1; }

echo "=== Root filesystem ==="
check "$MNT_SYS/etc/streamos-release"
check "$MNT_SYS/etc/fstab"
check "$MNT_SYS/opt/launcher/run.sh"
check "$MNT_SYS/opt/launcher/menu.sh"
check "$MNT_SYS/usr/local/bin/loki-diagnostics"
check "$MNT_SYS/usr/local/bin/streamos-input-test"
check "$MNT_SYS/usr/local/bin/streamos-storage-status"
check "$MNT_SYS/usr/bin/wvkbd-mobintl"
check "$MNT_SYS/etc/udev/rules.d/60-streamos-storage.rules"

echo "=== streamos-release ==="
cat "$MNT_SYS/etc/streamos-release"

echo "=== Enabled services ==="
for svc in systemd-networkd systemd-resolved systemd-logind iwd; do
    [[ -L "$MNT_SYS/etc/systemd/system/multi-user.target.wants/${svc}.service" ]] \
        || [[ -L "$MNT_SYS/etc/systemd/system/sysinit.target.wants/${svc}.service" ]] \
        || { echo "WARN: ${svc}.service not enabled" >&2; }
done

echo "=== Internal storage safety (fstab must not reference nvme/mmcblk) ==="
if grep -qE 'nvme|mmcblk' "$MNT_SYS/etc/fstab"; then
    echo "FAIL: fstab references internal block device" >&2
    exit 1
fi
echo "OK: fstab has no internal NVMe/eMMC entries"

echo "=== All structural checks passed ==="
