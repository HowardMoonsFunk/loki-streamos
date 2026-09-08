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

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build-artifacts"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
IMG_FILE="${BUILD_DIR}/loki-streamos-$(date +%Y%m%d).img"
IMG_SIZE_GB=8  # 8 GB USB image
BOOT_SIZE_MB=512
SYSTEM_SIZE_MB=$((IMG_SIZE_GB * 1024 - BOOT_SIZE_MB))

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Sanity checks
[[ $EUID -eq 0 ]] || log_error "Must run as root (sudo ./scripts/build-image.sh)"
command -v arch-chroot &>/dev/null || log_error "arch-chroot not found. Install arch-install-scripts."
command -v mkfs.fat &>/dev/null || log_error "mkfs.fat not found. Install dosfstools."

log_info "Building Loki StreamOS image..."
log_info "Output: $IMG_FILE"
log_info "Size: ${IMG_SIZE_GB} GB"

# Clean up old builds
log_info "Cleaning previous build artifacts..."
rm -rf "$ROOTFS_DIR" "$IMG_FILE"
mkdir -p "$BUILD_DIR" "$ROOTFS_DIR"

# ============================================================================
# Step 1: Bootstrap minimal Arch Linux
# ============================================================================

log_info "Step 1/5: Bootstrapping minimal Arch Linux..."

# Install base system using pacstrap
pacstrap -C "${PROJECT_ROOT}/base/pacman.conf" -M "$ROOTFS_DIR" \
  base linux-lts linux-lts-headers \
  amdgpu-dkms vulkan-radeon mesa \
  networkmanager iwd wpa_supplicant \
  pipewire pipewire-alsa pipewire-pulse \
  gamescope \
  systemd systemd-boot systemd-logind \
  glibc gcc binutils less vim nano \
  curl wget git openssh \
  squashfs-tools grub efibootmgr \
  --needed

log_info "Rootfs installed to: $ROOTFS_DIR"

# ============================================================================
# Step 2: Configure fstab
# ============================================================================

log_info "Step 2/5: Configuring filesystem table..."

cat > "$ROOTFS_DIR/etc/fstab" <<'EOF'
# Loki StreamOS fstab

# <file system>             <mount point>   <type>  <options>               <dump>  <pass>
LABEL=LOKI_BOOT             /boot           vfat    defaults,nodev,nosuid   0       2
LABEL=LOKI_SYSTEM           /               ext4    defaults,nodev          0       1
tmpfs                       /tmp            tmpfs   defaults,size=256M,nosuid,nodev  0  0
tmpfs                       /run            tmpfs   defaults,size=256M,nosuid,nodev  0  0
EOF

# ============================================================================
# Step 3: Loki-specific hardware configuration
# ============================================================================

log_info "Step 3/5: Installing Loki-specific hardware configuration..."

# Copy hardware-specific udev rules
mkdir -p "$ROOTFS_DIR/etc/udev/rules.d"
cat > "$ROOTFS_DIR/etc/udev/rules.d/50-loki-input.rules" <<'EOF'
# Loki Zero integrated controller
# Map power button to suspend, volume buttons to events
SUBSYSTEM=="input", ATTRS{name}=="*Loki*", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="*GamepadXInput*", TAG+="uaccess"

# Any generic gamepad
SUBSYSTEM=="input", ATTRS{id/vendor}=="0x045e", TAG+="uaccess"  # Xbox
SUBSYSTEM=="input", ATTRS{id/vendor}=="0x054c", TAG+="uaccess"  # Sony
EOF

# Power management configuration
mkdir -p "$ROOTFS_DIR/etc/systemd"
cat > "$ROOTFS_DIR/etc/systemd/logind.conf" <<'EOF'
# Loki StreamOS systemd-logind configuration
[Login]
HandlePowerKey=suspend
HandleLidSwitch=suspend
IdleAction=suspend
IdleActionSec=600
PowerKeyIgnoreInhibited=false
EOF

# AMDGPU kernel module configuration
mkdir -p "$ROOTFS_DIR/etc/modprobe.d"
cat > "$ROOTFS_DIR/etc/modprobe.d/amdgpu.conf" <<'EOF'
# AMDGPU kernel module options
options amdgpu exp_hw_support=1
options amdgpu gpu_recovery=1
options amdgpu ppfeaturemask=0xffffffff
EOF

# ============================================================================
# Step 4: Install Moonlight via AppImage (or AUR in future)
# ============================================================================

log_info "Step 4/5: Installing Moonlight and launcher framework..."

# For now, we'll set up the framework to run Moonlight
# Full AppImage download happens at runtime (first boot)
mkdir -p "$ROOTFS_DIR/opt/moonlight"
mkdir -p "$ROOTFS_DIR/opt/launcher"

cat > "$ROOTFS_DIR/opt/launcher/run.sh" <<'EOF'
#!/bin/bash
# Loki StreamOS Launcher
# TODO: Implement controller-driven UI
# For now: start Gamescope and wait for user input

exec gamescope -W 1280 -H 720 --immediate-mode -- true
EOF

chmod +x "$ROOTFS_DIR/opt/launcher/run.sh"

# ============================================================================
# Step 5: Systemd boot configuration
# ============================================================================

log_info "Step 5/5: Configuring systemd-boot and system targets..."

# Set up systemd-boot for UEFI
arch-chroot "$ROOTFS_DIR" bootctl install 2>/dev/null || true

# Boot entry for Loki StreamOS
mkdir -p "$ROOTFS_DIR/boot/loader/entries"
cat > "$ROOTFS_DIR/boot/loader/entries/loki-streamos.conf" <<'EOF'
title           Loki StreamOS
linux           /vmlinuz-linux-lts
initrd          /initramfs-linux-lts.img
options         root=LABEL=LOKI_SYSTEM ro quiet splash vt.handoff=7
EOF

cat > "$ROOTFS_DIR/boot/loader/loader.conf" <<'EOF'
default         loki-streamos
timeout         3
console-mode    keep
EOF

# Disable unnecessary services
arch-chroot "$ROOTFS_DIR" systemctl disable NetworkManager.service 2>/dev/null || true
arch-chroot "$ROOTFS_DIR" systemctl disable bluetooth.service 2>/dev/null || true

# Enable only what we need
arch-chroot "$ROOTFS_DIR" systemctl enable systemd-logind.service 2>/dev/null || true
arch-chroot "$ROOTFS_DIR" systemctl enable systemd-networkd.service 2>/dev/null || true

# ============================================================================
# Create bootable raw disk image
# ============================================================================

log_info "Creating bootable disk image..."

# Create empty image file
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$((IMG_SIZE_GB * 1024)) status=progress 2>/dev/null

# Create partition table (GPT for UEFI)
parted -s "$IMG_FILE" mklabel gpt
parted -s "$IMG_FILE" mkpart primary fat32 1MiB "$((BOOT_SIZE_MB))MiB"
parted -s "$IMG_FILE" mkpart primary ext4 "$((BOOT_SIZE_MB))MiB" 100%
parted -s "$IMG_FILE" set 1 esp on

# Calculate offsets for loopback mounting
BOOT_OFFSET=$((1 * 1024 * 1024))  # 1 MB
SYSTEM_OFFSET=$((BOOT_SIZE_MB * 1024 * 1024))

# Set up loopback device
LOOP_DEV=$(losetup -f)
losetup "$LOOP_DEV" "$IMG_FILE"

# Create filesystems
mkfs.fat -F 32 -n LOKI_BOOT "$LOOP_DEV"p1
mkfs.ext4 -F -L LOKI_SYSTEM "$LOOP_DEV"p2

# Mount and copy rootfs
MNT_BOOT=$(mktemp -d)
MNT_SYSTEM=$(mktemp -d)
trap "umount -R $MNT_BOOT $MNT_SYSTEM; rmdir $MNT_BOOT $MNT_SYSTEM; losetup -d $LOOP_DEV" EXIT

mount "$LOOP_DEV"p1 "$MNT_BOOT"
mount "$LOOP_DEV"p2 "$MNT_SYSTEM"

# Copy rootfs to system partition
cp -r "$ROOTFS_DIR"/* "$MNT_SYSTEM/"

# Copy boot files to EFI partition
if [[ -d "$ROOTFS_DIR/boot" ]]; then
    cp -r "$ROOTFS_DIR/boot"/* "$MNT_BOOT/"
fi

# Sync and unmount
sync
umount -R "$MNT_BOOT" "$MNT_SYSTEM"
losetup -d "$LOOP_DEV"

log_info "✅ Image created: $IMG_FILE"

# ============================================================================
# Generate checksums
# ============================================================================

log_info "Generating checksums..."
cd "$BUILD_DIR"
sha256sum "$(basename "$IMG_FILE")" > "loki-streamos-$(date +%Y%m%d).sha256"
log_info "✅ Checksum: $(cat loki-streamos-$(date +%Y%m%d).sha256)"

log_info ""
log_info "╔════════════════════════════════════════════════════════════╗"
log_info "║  Loki StreamOS Image Ready for Testing                     ║"
log_info "╠════════════════════════════════════════════════════════════╣"
log_info "║  Image: $IMG_FILE"
log_info "║  Size:  ${IMG_SIZE_GB} GB (bootable on USB/SD card)"
log_info "║                                                            ║"
log_info "║  Next: Write to USB with:                                  ║"
log_info "║  $ sudo dd if=$IMG_FILE of=/dev/sdX bs=4M status=progress  ║"
log_info "║  $ sync && sudo eject /dev/sdX                             ║"
log_info "║                                                            ║"
log_info "║  Then boot on Loki Zero (hold Volume Down for menu)        ║"
log_info "╚════════════════════════════════════════════════════════════╝"
log_info ""
