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

# Per-device report: event node, bus, vendor/product, capabilities, multitouch, axis ranges
{
    echo "# Touchscreen device report (NEEDS_PHYSICAL_TEST)"
    echo "# Display reference: ${DISPLAY_SIZE}"
    echo ""

    touch_nodes=()
    if command -v libinput &>/dev/null; then
        while IFS= read -r node; do
            [[ -n "$node" && -e "$node" ]] && touch_nodes+=("$node")
        done < <(libinput list-devices 2>/dev/null | awk '
            /^Device:/ { dev="" }
            /Kernel:/ { dev=$2 }
            /Capabilities:/ && /touch/ { if (dev) print dev }
        ')
    fi

    if [[ ${#touch_nodes[@]} -eq 0 ]]; then
        while IFS= read -r handler; do
            handler="${handler#Handlers=}"
            handler="${handler%% *}"
            [[ -e "/dev/input/${handler}" ]] && touch_nodes+=("/dev/input/${handler}")
        done < <(awk '/^N:.*[Tt]ouch|^N:.*[Mm]ultitouch/ { getline; if ($1=="H:") print $2 }' /proc/bus/input/devices 2>/dev/null)
    fi

    if [[ ${#touch_nodes[@]} -eq 0 ]]; then
        echo "STATUS: no touchscreen event node identified (NEEDS_PHYSICAL_TEST on device)"
    else
    for dev in "${touch_nodes[@]}"; do
        echo "=== event_node: $dev ==="
        if command -v udevadm &>/dev/null; then
            udevadm info --query=property --name="$dev" 2>/dev/null \
                | grep -E '^ID_(BUS|VENDOR_ID|MODEL_ID|INPUT_|NAME|PATH|DEVNAME)=' || true
        fi
        echo ""
        echo "-- libinput --"
        libinput list-devices 2>/dev/null | awk -v d="$dev" '
            /^Device:/ { show=0; block="" }
            /Kernel:/ && $2==d { show=1 }
            { block=block $0 "\n" }
            /^$/ { if (show) printf "%s", block; block="" }
            END { if (show) printf "%s", block }
        ' || true
        echo ""
        echo "-- capabilities / axes (evtest) --"
        if command -v evtest &>/dev/null; then
            for code in ABS_X ABS_Y ABS_MT_POSITION_X ABS_MT_POSITION_Y ABS_MT_SLOT ABS_MT_TRACKING_ID; do
                if evtest --query "$dev" EV_ABS "$code" &>/dev/null; then
                    echo -n "$code: "
                    evtest --query "$dev" EV_ABS "$code" 2>/dev/null || echo "query failed"
                fi
            done
            if evtest --query "$dev" EV_KEY BTN_TOUCH &>/dev/null; then
                echo -n "BTN_TOUCH: "
                evtest --query "$dev" EV_KEY BTN_TOUCH 2>/dev/null || true
            fi
            if evtest --query "$dev" EV_ABS ABS_MT_SLOT &>/dev/null; then
                echo "multitouch: ABS_MT_SLOT present (multi-finger capable)"
            else
                echo "multitouch: ABS_MT_SLOT not reported (single-touch or driver limitation)"
            fi
        else
            echo "evtest not installed"
        fi
        echo ""
    done

    echo "-- kernel (dmesg touch/HID/I2C) --"
    dmesg 2>/dev/null | grep -iE 'touch|hid-multitouch|i2c-hid|goodix|ft5|edt|ili|input:' | tail -40 || true
    fi
} > "$OUTPUT_DIR/touchscreen-device-report.txt" 2>&1

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

section "Physical verification checklist (Phase 1 — NEEDS_PHYSICAL_TEST)"
cat <<'EOF'

Record pass/fail for each item. Do not add calibration unless a consistent
transform is proven on hardware.

[ ] touchscreen detected (event node in touchscreen-device-report.txt)
[ ] tap works (BTN_TOUCH / ABS_MT events in libinput debug-events)
[ ] drag works (continuous ABS_MT_POSITION or ABS_X/Y while moving finger)
[ ] coordinates correspond to 1280×720 orientation (top-left low, bottom-right high)
[ ] multitouch reported/tested if ABS_MT_SLOT present in device report
[ ] touch works under Gamescope (launcher wmenu responds to tap)
[ ] touch works after suspend/resume (systemctl suspend, wake, re-test)

Gamescope / launcher:
  - Boot to launcher; tap menu items (touch/pointer via wmenu)
  - Optional: arrow keys + Enter if controller maps to keyboard
  - "On-screen keyboard" menu item starts wvkbd for Wi-Fi password entry

Moonlight (separate test):
  - Record whether touch maps to mouse, native touch injection, or neither

EOF

if command -v libinput &>/dev/null; then
    section "Live touch event monitor (10s sample — tap the screen now)"
    timeout 10 libinput debug-events 2>/dev/null | tee "$OUTPUT_DIR/libinput-debug-events-sample.txt" || \
        log "No libinput events captured in 10s (device may need --device= filter)"
fi

log "Done. Include $OUTPUT_DIR in diagnostics or attach alongside loki-diagnostics tarball."
