#!/bin/bash
# Phase 1 launcher menu — pointer/touch via wmenu; keyboard/controller via arrow keys + Enter
set -euo pipefail

OSK_PID=""

cleanup_osk() {
    [[ -n "${OSK_PID}" ]] && kill "${OSK_PID}" 2>/dev/null || true
    OSK_PID=""
}

run_menu() {
    printf '%s\n' \
        "Run diagnostics" \
        "Touchscreen / input test" \
        "Wi-Fi scan" \
        "On-screen keyboard" \
        "Gamescope tap test" \
        "Exit menu"
}

handle_choice() {
    case "$1" in
        "Run diagnostics")
            loki-diagnostics
            ;;
        "Touchscreen / input test")
            streamos-input-test
            ;;
        "Wi-Fi scan")
            iw dev wlan0 scan 2>&1 | head -80 | wmenu -i -s "Wi-Fi" -p "Networks:" || true
            ;;
        "On-screen keyboard")
            cleanup_osk
            wvkbd-mobintl -L 280 &
            OSK_PID=$!
            ;;
        "Gamescope tap test")
            printf '%s\n' "Top-left" "Center" "Bottom-right" "Cancel" \
                | wmenu -i -s "Tap test (1280×720)" -p "Tap an item:" || true
            ;;
        "Exit menu")
            cleanup_osk
            exit 0
            ;;
    esac
}

trap cleanup_osk EXIT

while true; do
    choice="$(run_menu | wmenu -i -s "Loki StreamOS" -p "Select:")" || continue
    handle_choice "$choice"
done
