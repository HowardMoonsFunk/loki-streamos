#!/bin/bash
#
# diagnostics.sh: Loki StreamOS hardware diagnostics collector
#
# Run this on physical Loki Zero to test hardware support
# and collect debug information for the cloud build loop
#
# Usage: ./scripts/diagnostics.sh
#
# Output: loki-diagnostics-YYYYMMDD.tar.gz
#

set -e

DIAG_DIR=$(mktemp -d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="loki-diagnostics-${TIMESTAMP}.tar.gz"

trap "rm -rf $DIAG_DIR" EXIT

log() { echo "[$(date +'%H:%M:%S')] $*"; }

log "Loki StreamOS Hardware Diagnostics"
log "Output directory: $DIAG_DIR"

# ============================================================================
# System Information
# ============================================================================

log "Collecting system information..."
mkdir -p "$DIAG_DIR/system"

uname -a > "$DIAG_DIR/system/uname.txt"
cat /proc/cpuinfo > "$DIAG_DIR/system/cpuinfo.txt" 2>/dev/null || echo "N/A" > "$DIAG_DIR/system/cpuinfo.txt"
cat /proc/meminfo > "$DIAG_DIR/system/meminfo.txt" 2>/dev/null || echo "N/A" > "$DIAG_DIR/system/meminfo.txt"

# ============================================================================
# GPU / Display
# ============================================================================

log "Collecting GPU and display information..."
mkdir -p "$DIAG_DIR/gpu"

lspci -nnk | grep -A3 "VGA\|Display" > "$DIAG_DIR/gpu/lspci-vga.txt" 2>/dev/null || echo "N/A" > "$DIAG_DIR/gpu/lspci-vga.txt"
lspci -nnk > "$DIAG_DIR/gpu/lspci-all.txt" 2>/dev/null
lsmod | grep -i amdgpu > "$DIAG_DIR/gpu/amdgpu-modules.txt" 2>/dev/null || echo "amdgpu module not loaded" > "$DIAG_DIR/gpu/amdgpu-modules.txt"

# GPU device files
ls -la /dev/dri/ > "$DIAG_DIR/gpu/dev-dri.txt" 2>/dev/null || echo "No /dev/dri" > "$DIAG_DIR/gpu/dev-dri.txt"

# Mesa information
glxinfo 2>/dev/null > "$DIAG_DIR/gpu/glxinfo.txt" || echo "glxinfo not available" > "$DIAG_DIR/gpu/glxinfo.txt"
vulkaninfo 2>/dev/null > "$DIAG_DIR/gpu/vulkaninfo.txt" || echo "vulkaninfo not available" > "$DIAG_DIR/gpu/vulkaninfo.txt"

# Display information
cat /sys/class/drm/*/edid 2>/dev/null | strings > "$DIAG_DIR/gpu/edid-info.txt" 2>/dev/null || echo "No EDID available" > "$DIAG_DIR/gpu/edid-info.txt"

# Backlight
if [[ -d /sys/class/backlight ]]; then
    ls -la /sys/class/backlight/ > "$DIAG_DIR/gpu/backlight.txt"
    find /sys/class/backlight -name "brightness" -exec sh -c 'echo "{}: $(cat {})"' \; >> "$DIAG_DIR/gpu/backlight.txt"
else
    echo "No backlight device" > "$DIAG_DIR/gpu/backlight.txt"
fi

# ============================================================================
# Input Devices
# ============================================================================

log "Collecting input device information..."
mkdir -p "$DIAG_DIR/input"

cat /proc/bus/input/devices > "$DIAG_DIR/input/devices.txt" 2>/dev/null || echo "N/A" > "$DIAG_DIR/input/devices.txt"
ls -la /dev/input/ > "$DIAG_DIR/input/dev-input.txt" 2>/dev/null

# Test controller presence
if command -v evtest &>/dev/null; then
    echo "=== Gamepad/Controller Detection ===" > "$DIAG_DIR/input/controller-status.txt"
    evtest --query /dev/input/event0 BTN_START 2>/dev/null && echo "Gamepad detected!" >> "$DIAG_DIR/input/controller-status.txt" || echo "No gamepad at event0" >> "$DIAG_DIR/input/controller-status.txt"
else
    echo "evtest not installed" > "$DIAG_DIR/input/controller-status.txt"
fi

# Touchscreen identification (libinput, udev, I2C/HID — no calibration applied)
log "Collecting touchscreen / input path information..."
mkdir -p "$DIAG_DIR/input/touchscreen"
if [[ -x /usr/local/bin/streamos-input-test ]]; then
    /usr/local/bin/streamos-input-test --collect --output "$DIAG_DIR/input/touchscreen" || true
elif [[ -f "${BASH_SOURCE[0]%/*}/streamos-input-test.sh" ]]; then
    bash "${BASH_SOURCE[0]%/*}/streamos-input-test.sh" --collect --output "$DIAG_DIR/input/touchscreen" || true
else
    echo "streamos-input-test not found" > "$DIAG_DIR/input/touchscreen/missing.txt"
fi

grep -i -E "touch|Touch|multitouch|hid-multitouch|goodix|ft5" /proc/bus/input/devices \
    > "$DIAG_DIR/input/touchscreen-proc-filter.txt" 2>/dev/null \
    || echo "No touch-related entries in /proc/bus/input/devices" > "$DIAG_DIR/input/touchscreen-proc-filter.txt"

if command -v libinput &>/dev/null; then
    libinput list-devices > "$DIAG_DIR/input/libinput-list-devices.txt" 2>/dev/null \
        || echo "libinput list-devices failed" > "$DIAG_DIR/input/libinput-list-devices.txt"
fi

# ============================================================================
# Networking (Wi-Fi & Bluetooth)
# ============================================================================

log "Collecting network device information..."
mkdir -p "$DIAG_DIR/network"

lspci -nnk | grep -i "network\|wifi\|wireless\|bluetooth" > "$DIAG_DIR/network/lspci-network.txt" 2>/dev/null
lsusb > "$DIAG_DIR/network/lsusb.txt" 2>/dev/null

ip link show > "$DIAG_DIR/network/ip-link.txt" 2>/dev/null || echo "ip command not available" > "$DIAG_DIR/network/ip-link.txt"
iwconfig 2>/dev/null > "$DIAG_DIR/network/iwconfig.txt" || echo "iwconfig not available" > "$DIAG_DIR/network/iwconfig.txt"

# Wi-Fi scan (non-destructive)
if command -v iw &>/dev/null && [[ -d /sys/class/net/wlan0 ]]; then
    iw dev wlan0 link > "$DIAG_DIR/network/wifi-link.txt" 2>/dev/null || echo "Not connected" > "$DIAG_DIR/network/wifi-link.txt"
    iw dev wlan0 info > "$DIAG_DIR/network/wifi-info.txt" 2>/dev/null || echo "Wi-Fi info not available" > "$DIAG_DIR/network/wifi-info.txt"
else
    echo "iw command or wlan0 not available" > "$DIAG_DIR/network/wifi-status.txt"
fi

# Bluetooth
if command -v bluetoothctl &>/dev/null; then
    bluetoothctl show > "$DIAG_DIR/network/bluetooth-status.txt" 2>/dev/null || echo "Bluetooth not available" > "$DIAG_DIR/network/bluetooth-status.txt"
else
    echo "bluetoothctl not installed" > "$DIAG_DIR/network/bluetooth-status.txt"
fi

# ============================================================================
# Audio
# ============================================================================

log "Collecting audio information..."
mkdir -p "$DIAG_DIR/audio"

aplay -l > "$DIAG_DIR/audio/aplay-list.txt" 2>/dev/null || echo "aplay not available" > "$DIAG_DIR/audio/aplay-list.txt"
pactl list short sinks 2>/dev/null > "$DIAG_DIR/audio/pulseaudio-sinks.txt" || echo "PulseAudio not available" > "$DIAG_DIR/audio/pulseaudio-sinks.txt"

if command -v pactl &>/dev/null; then
    pactl info > "$DIAG_DIR/audio/pulseaudio-info.txt" 2>/dev/null
fi

lsmod | grep -i "audio\|snd\|hda" > "$DIAG_DIR/audio/audio-modules.txt" 2>/dev/null || echo "No audio modules loaded" > "$DIAG_DIR/audio/audio-modules.txt"

# ============================================================================
# Power & Battery
# ============================================================================

log "Collecting power and battery information..."
mkdir -p "$DIAG_DIR/power"

if [[ -d /sys/class/power_supply ]]; then
    for ps in /sys/class/power_supply/*/; do
        name=$(basename "$ps")
        cat "$ps/uevent" > "$DIAG_DIR/power/power_supply_${name}.txt" 2>/dev/null || true
    done
else
    echo "No power supply sysfs" > "$DIAG_DIR/power/power-status.txt"
fi

# Battery percentage
if [[ -f /sys/class/power_supply/BAT0/capacity ]]; then
    echo "Battery: $(cat /sys/class/power_supply/BAT0/capacity)%" > "$DIAG_DIR/power/battery-quick.txt"
elif [[ -f /sys/class/power_supply/BAT1/capacity ]]; then
    echo "Battery: $(cat /sys/class/power_supply/BAT1/capacity)%" > "$DIAG_DIR/power/battery-quick.txt"
else
    echo "Battery info not available" > "$DIAG_DIR/power/battery-quick.txt"
fi

# ============================================================================
# System Logs
# ============================================================================

log "Collecting system logs..."
mkdir -p "$DIAG_DIR/logs"

journalctl -b > "$DIAG_DIR/logs/journal-boot.txt" 2>/dev/null || echo "journalctl not available" > "$DIAG_DIR/logs/journal-boot.txt"
dmesg > "$DIAG_DIR/logs/dmesg.txt" 2>/dev/null || echo "dmesg not available" > "$DIAG_DIR/logs/dmesg.txt"

# ============================================================================
# Kernel & Modules
# ============================================================================

log "Collecting kernel information..."
mkdir -p "$DIAG_DIR/kernel"

uname -a > "$DIAG_DIR/kernel/uname.txt"
lsmod > "$DIAG_DIR/kernel/lsmod.txt"
cat /proc/cmdline > "$DIAG_DIR/kernel/cmdline.txt" 2>/dev/null

# ============================================================================
# Environment
# ============================================================================

log "Collecting environment information..."
mkdir -p "$DIAG_DIR/environment"

env > "$DIAG_DIR/environment/env.txt"
which bash git python python3 2>/dev/null > "$DIAG_DIR/environment/tools.txt" || true

# ============================================================================
# Package Information
# ============================================================================

log "Collecting package information..."
mkdir -p "$DIAG_DIR/packages"

if command -v pacman &>/dev/null; then
    pacman -Q > "$DIAG_DIR/packages/pacman-list.txt" 2>/dev/null || echo "pacman-Q failed" > "$DIAG_DIR/packages/pacman-list.txt"
    pacman -Q | grep -E "amdgpu|mesa|gamescope|moonlight|pipewire" > "$DIAG_DIR/packages/gaming-packages.txt" 2>/dev/null || echo "No gaming packages installed" > "$DIAG_DIR/packages/gaming-packages.txt"
else
    echo "pacman not available" > "$DIAG_DIR/packages/pacman-list.txt"
fi

# ============================================================================
# Gamescope / Moonlight Status (if installed)
# ============================================================================

log "Checking Gamescope and Moonlight..."
mkdir -p "$DIAG_DIR/applications"

if command -v gamescope &>/dev/null; then
    gamescope --version > "$DIAG_DIR/applications/gamescope-version.txt" 2>/dev/null || echo "Gamescope not responding" > "$DIAG_DIR/applications/gamescope-version.txt"
else
    echo "Gamescope not installed" > "$DIAG_DIR/applications/gamescope-version.txt"
fi

if command -v moonlight &>/dev/null; then
    moonlight --version > "$DIAG_DIR/applications/moonlight-version.txt" 2>/dev/null || echo "Moonlight not responding" > "$DIAG_DIR/applications/moonlight-version.txt"
else
    echo "Moonlight not installed" > "$DIAG_DIR/applications/moonlight-version.txt"
fi

# ============================================================================
# Summary & Verification
# ============================================================================

log "Creating summary..."

cat > "$DIAG_DIR/SUMMARY.md" <<'EOF'
# Loki StreamOS Diagnostics Report

## Quick Hardware Checklist

Run this after booting the Loki StreamOS image on physical hardware.
Results should be included in `loki-diagnostics-YYYYMMDD.tar.gz`.

### Display & Graphics
- [ ] Display boots at 1280×720
- [ ] GPU drivers loaded: `grep amdgpu /proc/modules`
- [ ] Backlight controllable: `cat /sys/class/backlight/*/brightness`

### Input
- [ ] Controller detected: `cat /proc/bus/input/devices | grep -i gamepad`
- [ ] Touchscreen detected and reports input events
- [ ] Touchscreen coordinates/orientation correct in launcher and after resume
- [ ] D-pad works
- [ ] Analog sticks work
- [ ] Shoulder buttons (L1/R1, L2/R2) work
- [ ] Start/Select work

### Networking
- [ ] Wi-Fi visible: `iw dev wlan0 link` or `iwconfig`
- [ ] Can connect to SSID
- [ ] IP address obtained (DHCP)
- [ ] Internet connectivity: `ping 8.8.8.8`

### Bluetooth (Future)
- [ ] Bluetooth adapter visible: `bluetoothctl list`
- [ ] Can pair controller/headphones

### Audio
- [ ] Headphone jack detected: `aplay -l`
- [ ] Speaker test: `aplay /usr/share/sounds/freedesktop/stereo/complete.oga`
- [ ] Volume control works (keyboard/buttons)

### Battery & Power
- [ ] Battery percentage shows: `cat /sys/class/power_supply/BAT*/capacity`
- [ ] Power button suspends system
- [ ] Wake from suspend works

### Streaming
- [ ] Gamescope renders: Try `gamescope -W 1280 -H 720 -- true`
- [ ] Moonlight connects to test server
- [ ] Video streaming at 720p60

---

## File Manifest

```
loki-diagnostics-YYYYMMDD/
├── SUMMARY.md (this file)
├── system/
│   ├── uname.txt
│   ├── cpuinfo.txt
│   └── meminfo.txt
├── gpu/
│   ├── lspci-vga.txt
│   ├── lspci-all.txt
│   ├── glxinfo.txt
│   └── amdgpu-modules.txt
├── input/
│   ├── devices.txt
│   ├── libinput-list-devices.txt
│   ├── touchscreen-proc-filter.txt
│   ├── touchscreen/          (streamos-input-test --collect output)
│   └── controller-status.txt
├── network/
│   ├── lspci-network.txt
│   ├── wifi-link.txt
│   └── bluetooth-status.txt
├── audio/
│   ├── aplay-list.txt
│   └── pulseaudio-info.txt
├── power/
│   ├── battery-quick.txt
│   └── power_supply_*.txt
├── logs/
│   ├── journal-boot.txt
│   ├── dmesg.txt
├── kernel/
│   ├── lsmod.txt
│   └── cmdline.txt
└── packages/
    └── gaming-packages.txt
```

---

## Next Steps

1. Extract this tarball on your build system
2. Compare against expected values in HARDWARE.md
3. Report any NEEDS_PHYSICAL_TEST items that fail
4. Provide this bundle back to the build system for iteration

EOF

log "Compressing diagnostics..."
tar -czf "/tmp/$OUTPUT_FILE" -C "$(dirname "$DIAG_DIR")" "$(basename "$DIAG_DIR")"

log ""
log "✅ Diagnostics complete!"
log "📦 Output: $OUTPUT_FILE"
log ""
log "To send back to cloud build system:"
log "  $ cat /tmp/$OUTPUT_FILE | base64 | pbcopy"
log ""
log "Or attach to GitHub issue as .tar.gz"
log ""

# Copy to /tmp for easy access
cp "/tmp/$OUTPUT_FILE" .
log "Saved to: $(pwd)/$OUTPUT_FILE"
