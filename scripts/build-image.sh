#!/bin/bash
#
# build-image.sh: Generate bootable Loki StreamOS .img for USB/SD card
#
# This script:
# 1. Creates a minimal Arch Linux rootfs
# 2. Installs GPU drivers, Gamescope, Moonlight
# 3. Configures systemd boot flow
# 4. Generates a raw disk image (dd-able to USB)
#
# Usage: sudo ./scripts/build-image.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build-artifacts"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
BUILD_DATE="$(date +%Y%m%d)"
IMG_FILE="${BUILD_DIR}/loki-streamos-${BUILD_DATE}.img"
CHECKSUM_FILE="${BUILD_DIR}/loki-streamos-${BUILD_DATE}.sha256"
IMG_SIZE_GB=8
BOOT_SIZE_MB=512

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

cleanup() {
    if [[ -n "${MNT_BOOT:-}" && -d "$MNT_BOOT" ]]; then
        umount -R "$MNT_BOOT" 2>/dev/null || true
        rmdir "$MNT_BOOT" 2>/dev/null || true
    fi
    if [[ -n "${MNT_SYSTEM:-}" && -d "$MNT_SYSTEM" ]]; then
        umount -R "$MNT_SYSTEM" 2>/dev/null || true
        rmdir "$MNT_SYSTEM" 2>/dev/null || true
    fi
    if [[ -n "${LOOP_DEV:-}" ]]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Sanity checks
[[ $EUID -eq 0 ]] || log_error "Must run as root (sudo ./scripts/build-image.sh)"
command -v pacstrap &>/dev/null || log_error "pacstrap not found. Install arch-install-scripts."
command -v arch-chroot &>/dev/null || log_error "arch-chroot not found. Install arch-install-scripts."
command -v mkfs.fat &>/dev/null || log_error "mkfs.fat not found. Install dosfstools."
command -v parted &>/dev/null || log_error "parted not found. Install parted."
command -v losetup &>/dev/null || log_error "losetup not found. Install util-linux."

log_info "Building Loki StreamOS image..."
log_info "Output: $IMG_FILE"
log_info "Size: ${IMG_SIZE_GB} GB"

# Clean up old builds
log_info "Cleaning previous build artifacts..."
rm -rf "$ROOTFS_DIR" "$IMG_FILE" "$CHECKSUM_FILE"
mkdir -p "$BUILD_DIR" "$ROOTFS_DIR"

# Ensure pacstrap can resolve mirrors inside the target rootfs
mkdir -p "$ROOTFS_DIR/etc/pacman.d"
if [[ -f /etc/pacman.d/mirrorlist ]]; then
    cp /etc/pacman.d/mirrorlist "$ROOTFS_DIR/etc/pacman.d/mirrorlist"
else
    cat > "$ROOTFS_DIR/etc/pacman.d/mirrorlist" <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
fi

# ============================================================================
# Step 1: Bootstrap minimal Arch Linux
# ============================================================================

log_info "Step 1/6: Bootstrapping minimal Arch Linux..."

pacstrap -C "${PROJECT_ROOT}/base/pacman.conf" -K "$ROOTFS_DIR" \
  base linux-lts linux-firmware linux-firmware-amdgpu \
  mesa vulkan-radeon lib32-vulkan-radeon \
  networkmanager iwd wpa_supplicant wireless-regdb \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  gamescope \
  systemd systemd-boot systemd-resolved \
  glibc gcc binutils less vim nano \
  curl wget git openssh sudo \
  squashfs-tools efibootmgr \
  mkinitcpio \
  --needed

log_info "Rootfs installed to: $ROOTFS_DIR"

# ============================================================================
# Step 2: Base system configuration
# ============================================================================

log_info "Step 2/6: Configuring base system..."

cat > "$ROOTFS_DIR/etc/fstab" <<'EOF'
# Loki StreamOS fstab
LABEL=LOKI_BOOT             /boot           vfat    defaults,nodev,nosuid   0       2
LABEL=LOKI_SYSTEM           /               ext4    defaults,nodev          0       1
tmpfs                       /tmp            tmpfs   defaults,size=256M,nosuid,nodev  0  0
tmpfs                       /run            tmpfs   defaults,size=256M,nosuid,nodev  0  0
EOF

echo "loki-streamos" > "$ROOTFS_DIR/etc/hostname"

cat > "$ROOTFS_DIR/etc/locale.conf" <<'EOF'
LANG=en_US.UTF-8
EOF

cat > "$ROOTFS_DIR/etc/locale.gen" <<'EOF'
en_US.UTF-8 UTF-8
EOF

ln -sf /usr/share/zoneinfo/UTC "$ROOTFS_DIR/etc/localtime"

arch-chroot "$ROOTFS_DIR" locale-gen
arch-chroot "$ROOTFS_DIR" mkinitcpio -P

# ============================================================================
# Step 3: Loki-specific hardware configuration
# ============================================================================

log_info "Step 3/6: Installing Loki-specific hardware configuration..."

mkdir -p "$ROOTFS_DIR/etc/udev/rules.d"
cat > "$ROOTFS_DIR/etc/udev/rules.d/50-loki-input.rules" <<'EOF'
# Loki Zero integrated controller
SUBSYSTEM=="input", ATTRS{name}=="*Loki*", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="*GamepadXInput*", TAG+="uaccess"

# Common gamepads
SUBSYSTEM=="input", ATTRS{id/vendor}=="0x045e", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{id/vendor}=="0x054c", TAG+="uaccess"
EOF

mkdir -p "$ROOTFS_DIR/etc/systemd"
cat > "$ROOTFS_DIR/etc/systemd/logind.conf" <<'EOF'
[Login]
HandlePowerKey=suspend
HandleLidSwitch=suspend
IdleAction=suspend
IdleActionSec=600
PowerKeyIgnoreInhibited=false
EOF

mkdir -p "$ROOTFS_DIR/etc/modprobe.d"
cat > "$ROOTFS_DIR/etc/modprobe.d/amdgpu.conf" <<'EOF'
options amdgpu exp_hw_support=1
options amdgpu gpu_recovery=1
options amdgpu ppfeaturemask=0xffffffff
EOF

# ============================================================================
# Step 4: Launcher framework
# ============================================================================

log_info "Step 4/6: Installing launcher framework..."

mkdir -p "$ROOTFS_DIR/opt/moonlight" "$ROOTFS_DIR/opt/launcher"

cat > "$ROOTFS_DIR/opt/launcher/run.sh" <<'EOF'
#!/bin/bash
# Loki StreamOS Launcher (placeholder — controller UI in Phase 6)
exec gamescope -W 1280 -H 720 --immediate-mode -- true
EOF
chmod +x "$ROOTFS_DIR/opt/launcher/run.sh"

# Install diagnostics script into the image
install -Dm755 "${PROJECT_ROOT}/scripts/diagnostics.sh" "$ROOTFS_DIR/usr/local/bin/loki-diagnostics"

# ============================================================================
# Step 5: Bootloader configuration
# ============================================================================

log_info "Step 5/6: Configuring systemd-boot..."

mkdir -p "$ROOTFS_DIR/boot/loader/entries"
cat > "$ROOTFS_DIR/boot/loader/entries/loki-streamos.conf" <<'EOF'
title   Loki StreamOS
linux   /vmlinuz-linux-lts
initrd  /initramfs-linux-lts.img
options root=LABEL=LOKI_SYSTEM rw quiet splash vt.handoff=7
EOF

cat > "$ROOTFS_DIR/boot/loader/loader.conf" <<'EOF'
default loki-streamos
timeout 3
console-mode keep
EOF

arch-chroot "$ROOTFS_DIR" systemctl enable systemd-networkd.service
arch-chroot "$ROOTFS_DIR" systemctl enable systemd-resolved.service
arch-chroot "$ROOTFS_DIR" systemctl enable systemd-logind.service
arch-chroot "$ROOTFS_DIR" systemctl enable iwd.service

# NetworkManager conflicts with iwd/systemd-networkd — keep iwd for appliance mode
arch-chroot "$ROOTFS_DIR" systemctl disable NetworkManager.service 2>/dev/null || true
arch-chroot "$ROOTFS_DIR" systemctl disable bluetooth.service 2>/dev/null || true

# ============================================================================
# Step 6: Create bootable raw disk image
# ============================================================================

log_info "Step 6/6: Creating bootable disk image..."

dd if=/dev/zero of="$IMG_FILE" bs=1M count=$((IMG_SIZE_GB * 1024)) status=progress 2>/dev/null

parted -s "$IMG_FILE" mklabel gpt
parted -s "$IMG_FILE" mkpart primary fat32 1MiB "${BOOT_SIZE_MB}MiB"
parted -s "$IMG_FILE" mkpart primary ext4 "${BOOT_SIZE_MB}MiB" 100%
parted -s "$IMG_FILE" set 1 esp on

LOOP_DEV="$(losetup -fP --show "$IMG_FILE")"
partprobe "$LOOP_DEV" 2>/dev/null || true
sleep 1

BOOT_PART="${LOOP_DEV}p1"
SYSTEM_PART="${LOOP_DEV}p2"
[[ -b "$BOOT_PART" ]] || BOOT_PART="${LOOP_DEV}1"
[[ -b "$SYSTEM_PART" ]] || SYSTEM_PART="${LOOP_DEV}2"
[[ -b "$BOOT_PART" && -b "$SYSTEM_PART" ]] || log_error "Loopback partitions not found on $LOOP_DEV"

mkfs.fat -F 32 -n LOKI_BOOT "$BOOT_PART"
mkfs.ext4 -F -L LOKI_SYSTEM "$SYSTEM_PART"

MNT_BOOT="$(mktemp -d)"
MNT_SYSTEM="$(mktemp -d)"

mount "$BOOT_PART" "$MNT_BOOT"
mount "$SYSTEM_PART" "$MNT_SYSTEM"

# Root filesystem on ext4 partition
cp -a "$ROOTFS_DIR"/. "$MNT_SYSTEM/"

# Boot artifacts on EFI partition (vfat — kernel + systemd-boot)
mkdir -p "$MNT_BOOT/loader/entries"
cp -a "$ROOTFS_DIR/boot"/vmlinuz-* "$MNT_BOOT/" 2>/dev/null || true
cp -a "$ROOTFS_DIR/boot"/initramfs-* "$MNT_BOOT/" 2>/dev/null || true
cp -a "$ROOTFS_DIR/boot/loader"/* "$MNT_BOOT/loader/" 2>/dev/null || true

bootctl --esp-path="$MNT_BOOT" install

sync
umount "$MNT_BOOT" "$MNT_SYSTEM"
losetup -d "$LOOP_DEV"
LOOP_DEV=""
rmdir "$MNT_BOOT" "$MNT_SYSTEM"
MNT_BOOT=""
MNT_SYSTEM=""

log_info "Image created: $IMG_FILE"

# ============================================================================
# Generate checksums
# ============================================================================

log_info "Generating checksums..."
(
    cd "$BUILD_DIR"
    sha256sum "$(basename "$IMG_FILE")" > "$(basename "$CHECKSUM_FILE")"
)
log_info "Checksum: $(cat "$CHECKSUM_FILE")"

log_info ""
log_info "╔════════════════════════════════════════════════════════════╗"
log_info "║  Loki StreamOS Image Ready for Testing                     ║"
log_info "╠════════════════════════════════════════════════════════════╣"
log_info "║  Image: $IMG_FILE"
log_info "║  Size:  ${IMG_SIZE_GB} GB (bootable on USB/SD card)"
log_info "║                                                            ║"
log_info "║  Write to USB:                                             ║"
log_info "║  sudo dd if=$IMG_FILE of=/dev/sdX bs=4M status=progress    ║"
log_info "║  sync && sudo eject /dev/sdX                               ║"
log_info "║                                                            ║"
log_info "║  Boot Loki Zero (hold Volume Down for menu)                ║"
log_info "╚════════════════════════════════════════════════════════════╝"
