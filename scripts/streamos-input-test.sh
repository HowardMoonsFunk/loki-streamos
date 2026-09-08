#!/bin/bash
#
# streamos-input-test.sh: Touchscreen and input verification for Loki StreamOS
#
# Identifies the touchscreen via libinput, /proc/bus/input/devices, udevadm,
# lsusb, and I2C/HID sysfs. Captures evidence for diagnostics; interactive
# mode guides physical tap/drag/resume/launcher/Moonlight checks.
#
# Usage:
#   streamos-input-test.sh              # interactive physical test
#   streamos-input-test.sh --collect    # non-interactive capture only
#   streamos-input-test.sh --output DIR # write capture to DIR
#
# Do not apply calibration transforms here — only report what the kernel
# and compositor expose. Add calibration only if physical testing proves it.
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
COLLECT_ONLY=0
OUTPUT_DIR=""
DISPLAY_SIZE="1280x720"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--collect] [--output DIR]

  --collect     Capture device identification only (for diagnostics tarball)
  --output DIR  Write capture files to DIR (default: ./streamos-input-test-\$TIMESTAMP)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collect) COLLECT_ONLY=1; shift ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="./streamos-input-test-${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
section() { log "=== $* ==="; }

write_or_echo() {
    local file="$1"
    shift
    if [[ -n "$OUTPUT_DIR" ]]; then
        "$@" > "$OUTPUT_DIR/$file" 2>&1 || echo "(command failed: $*)" > "$OUTPUT_DIR/$file"
    fi
}

# ============================================================================
# Device identification (always run)
# ============================================================================

section "Touchscreen device identification"

write_or_echo "libinput-list-devices.txt" libinput list-devices
write_or_echo "proc-bus-input-devices.txt" cat /proc/bus/input/devices
write_or_echo "proc-bus-input-devices-touch.txt" \
    sh -c 'grep -i -E "touch|Touch|TOUCH|hid-multitouch|goodix|ft5|edt|ili|synaptics" /proc/bus/input/devices || echo "No touch-related names in /proc/bus/input/devices"'

write_or_echo "lsusb.txt" lsusb
write_or_echo "lsusb-t.txt" lsusb -t

# I2C buses and HID-over-I2C hints
if [[ -d /sys/bus/i2c/devices ]]; then
    write_or_echo "i2c-devices.txt" ls -la /sys/bus/i2c/devices/
    if command -v i2cdetect &>/dev/null; then
        for bus in /dev/i2c-*; do
            [[ -c "$bus" ]] || continue
            bn="$(basename "$bus")"
            write_or_echo "i2cdetect-${bn}.txt" i2cdetect -y "${bn#i2c-}"
        done
    else
        echo "i2cdetect not installed" > "$OUTPUT_DIR/i2cdetect.txt"
    fi
else
    echo "No /sys/bus/i2c/devices" > "$OUTPUT_DIR/i2c-devices.txt"
fi

# HID raw and input sysfs
if [[ -d /sys/class/hidraw ]]; then
    write_or_echo "hidraw-ls.txt" ls -la /sys/class/hidraw/
fi
write_or_echo "input-by-path.txt" ls -la /dev/input/by-path/ 2>/dev/null || true
write_or_echo "input-by-id.txt" ls -la /dev/input/by-id/ 2>/dev/null || true

# udevadm for each candidate touch event node
{
    echo "=== Touchscreen udevadm probe ==="
    while IFS= read -r line; do
        [[ "$line" =~ ^H: ]] || continue
        handler="$(echo "$line" | awk '{print $2}')"
        dev="/dev/input/${handler#Handlers=}"
        [[ -e "$dev" ]] || continue
        echo "--- $dev ---"
        udevadm info --query=all --name="$dev" 2>/dev/null || true
        echo ""
    done < /proc/bus/input/devices

    # Also probe nodes libinput labels as touch
    if command -v libinput &>/dev/null; then
        while IFS= read -r path; do
            [[ -n "$path" && -e "$path" ]] || continue
            echo "--- libinput touch: $path ---"
            udevadm info --query=all --name="$path" 2>/dev/null || true
            echo ""
        done < <(libinput list-devices 2>/dev/null | awk '
            /^Device:/ { dev="" }
            /Kernel:/ { dev=$2 }
            /Capabilities:/ && /touch/ { if (dev) print dev }
        ')
    fi
} > "$OUTPUT_DIR/udevadm-touch.txt" 2>&1

# Summarize detected touch event devices
{
    echo "# Touchscreen candidate summary"
    echo "# Expected display: ${DISPLAY_SIZE} (6\" handheld, portrait/landscape TBD on hardware)"
    echo ""
    if command -v libinput &>/dev/null; then
        echo "## libinput devices with touch capability"
        libinput list-devices 2>/dev/null | awk '
            /^Device:/ { block=$0; has_touch=0 }
            /Capabilities:/ { if ($0 ~ /touch/) has_touch=1 }
            /^$/ { if (has_touch) print block; block="" }
            END { if (has_touch) print block }
        ' || echo "(libinput list-devices failed)"
        echo ""
    fi
    echo "## /proc/bus/input/devices (touch-related handlers)"
    awk '
        /^N:/ { name=$0 }
        /^H:/ { handlers=$0 }
        /^B:/ && ($0 ~ /EV_ABS/ || $0 ~ /EV_KEY/) {
            if (name ~ /[Tt]ouch/ || name ~ /[Mm]ultitouch/ || name ~ /[Hh][Ii][Dd]/) {
                print name
                print handlers
                print $0
                print ""
            }
        }
    ' /proc/bus/input/devices 2>/dev/null || true
} > "$OUTPUT_DIR/touchscreen-summary.txt"

# Wayland / Gamescope environment snapshot (non-fatal)
{
    echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
    echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
    echo "GAMESCOPE_WAYLAND_DISPLAY=${GAMESCOPE_WAYLAND_DISPLAY:-unset}"
    if command -v gamescope &>/dev/null; then
        gamescope --version 2>/dev/null || true
    fi
} > "$OUTPUT_DIR/compositor-env.txt" 2>&1

log "Capture written to: $OUTPUT_DIR"

if [[ "$COLLECT_ONLY" -eq 1 ]]; then
    log "Collect-only mode complete."
    exit 0
fi

# ============================================================================
# Interactive physical verification (requires operator on device)
# ============================================================================

section "Physical verification checklist"
cat <<'EOF'

Run these checks on the Loki with the display active. Mark pass/fail manually
or re-run after suspend/resume and in the launcher.

1. Touch events reach the compositor
   - With Gamescope/launcher running, tap the display.
   - In another VT or SSH session:
       libinput debug-events --device=<touch-event-node>
     Confirm BTN_TOUCH / ABS_MT_* events when tapping.

2. Coordinates match 1280×720 orientation
   - Tap top-left: ABS_MT_POSITION_X/Y near (0, 0).
   - Tap bottom-right: values near max (check ABS_MT ABS ranges in evtest).
   - If X/Y appear swapped or inverted, record it — do NOT apply calibration
     in software until physical testing confirms a consistent transform is needed.

3. Gestures (if driver exposes multi-touch)
   - [ ] Single tap registers
   - [ ] Drag/swipe registers continuous motion
   - [ ] Long-press (if supported by driver)
   - [ ] Two-finger gesture (if ABS_MT_SLOT / multi-finger events appear)

4. Suspend/resume
   - systemctl suspend → wake → repeat step 1–3.

5. Launcher
   - [ ] Touch works for Wi-Fi list scroll/tap (when UI exists)
   - [ ] Touch works for on-screen keyboard / text entry fallback
   - [ ] Touch works for emergency diagnostics launch

6. Moonlight (test separately from launcher shell)
   Moonlight touch behavior varies by client build and host settings:
   - Mouse emulation: touch → cursor move + click
   - Native touch injection: host receives touch events (Sunshine-dependent)
   - No touch: controller/mouse only
   Record observed behavior; explicit Moonlight touch config may be needed later.

EOF

if command -v libinput &>/dev/null; then
    section "Live touch event monitor (10s sample — tap the screen now)"
    timeout 10 libinput debug-events 2>/dev/null | tee "$OUTPUT_DIR/libinput-debug-events-sample.txt" || \
        log "No libinput events captured in 10s (device may need --device= filter)"
fi

log "Done. Include $OUTPUT_DIR in diagnostics or attach alongside loki-diagnostics tarball."
