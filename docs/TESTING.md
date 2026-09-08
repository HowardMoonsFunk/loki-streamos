# Loki StreamOS Physical Testing Checklist

This document guides testing the bootable .img on actual Loki Zero hardware.

---

## Pre-Test Setup

### Prerequisites
- AYN Loki Zero device
- USB 3.0+ drive (8GB+)
- Linux machine or Mac with `dd` command
- USB adapter/hub if needed
- Access to test gaming PC (for Sunshine/Steam Remote Play)

### Image Preparation

```bash
# Download image
wget https://github.com/yourusername/loki-streamos/releases/download/v0.1.0/loki-streamos-20240908.img.gz

# Verify checksum
sha256sum loki-streamos-20240908.img.gz
# Compare against loki-streamos-20240908.sha256

# Decompress
gunzip loki-streamos-20240908.img.gz

# Write to USB
lsblk  # Identify USB device (e.g., /dev/sdX)
sudo dd if=loki-streamos-20240908.img of=/dev/sdX bs=4M status=progress
sudo sync
sudo eject /dev/sdX
```

---

## Boot Test

### Objective
Verify Loki boots from USB and reaches the launcher.

**Steps:**
1. Power off Loki Zero completely
2. Insert USB into USB-C port using adapter
3. Power on Loki
4. Hold **Volume Down** to access boot menu (may need to try multiple times)
5. Select USB device from boot menu

**Expected Result:**
- Loki boots (Arch Linux kernel logs appear)
- Reaches launcher within ~15 seconds
- Controller is responsive
- Display shows 1280×720 native resolution

**If fails:**
- Check USB is fully inserted
- Try different USB port adapter
- Verify image write with `sudo dd if=/dev/sdX of=test.img bs=4M count=100`
- Collect: Run `sudo ./scripts/diagnostics.sh` and save output

---

## Hardware Detection & Configuration

### Display / Graphics

**Objective:** Verify GPU drivers and display output

**Test:**
```bash
# SSH into Loki (or run locally)
lspci -nnk | grep -A2 "VGA\|Display"
# Should show: VGA compatible controller: AMD/ATI [device ID]

lsmod | grep amdgpu
# Should show: amdgpu module loaded

xrandr  # or use Wayland equivalent
# Should report: 1280x720 60Hz
```

**Checklist:**
- [ ] AMDGPU kernel module loads (dmesg shows no errors)
- [ ] Display detected as 1280×720
- [ ] Backlight is adjustable (brightness control works)
- [ ] Gamescope can render at 720p

**If fails:**
- Check `/sys/class/backlight/*/brightness` exists
- Verify kernel module: `modprobe amdgpu`
- Collect diagnostics: `./scripts/diagnostics.sh`

---

### Input (Controller)

**Objective:** Verify integrated gamepad works

**Test:**
```bash
# Check input devices
cat /proc/bus/input/devices | grep -i gamepad

# Test D-pad / sticks
evtest /dev/input/event0  # May vary; find the right event device
# Press D-pad, analog sticks, buttons
# Should see EV_KEY and EV_ABS events

# Or use libinput test
sudo libinput debug-events
```

**Checklist:**
- [ ] Controller appears in `/proc/bus/input/devices`
- [ ] D-pad reports: ABS_HAT0X, ABS_HAT0Y
- [ ] Left stick: ABS_X, ABS_Y
- [ ] Right stick: ABS_RX, ABS_RY
- [ ] Shoulder buttons: BTN_TL, BTN_TL2, BTN_TR, BTN_TR2
- [ ] Face buttons: BTN_SOUTH, BTN_WEST, BTN_NORTH, BTN_EAST
- [ ] Start/Select: BTN_START, BTN_SELECT

**If fails:**
- Reboot and check again (driver may not load immediately)
- Check `/dev/input/event*` permissions
- Verify udev rules: `cat /etc/udev/rules.d/50-loki-input.rules`
- Collect diagnostics: `./scripts/diagnostics.sh`

---

### Touchscreen

**Objective:** Verify capacitive touch is detected, oriented correctly for 1280×720, and usable as a first-class fallback (Wi-Fi/BT pairing, text entry, diagnostics) alongside the controller.

**Identify the device:**
```bash
# Full capture (included in diagnostics tarball)
sudo streamos-input-test --collect

# Or manually:
libinput list-devices
cat /proc/bus/input/devices
lsusb
ls -la /dev/input/by-path/ /dev/input/by-id/
udevadm info --query=all --name=/dev/input/eventN   # replace N with touch node

# I2C-HID path (if present)
ls /sys/bus/i2c/devices/
i2cdetect -y 0   # repeat for each /dev/i2c-* bus
ls /sys/class/hidraw/
```

**Verify events reach Wayland/Gamescope:**
```bash
# Find touch event node from libinput list-devices (Kernel: /dev/input/eventN)
libinput debug-events --device=/dev/input/eventN
# Tap display — expect BTN_TOUCH, ABS_X/Y or ABS_MT_POSITION_X/Y

# With Gamescope/launcher running, repeat taps and confirm events correlate
gamescope -W 1280 -H 720 --immediate-mode -- true &
libinput debug-events --device=/dev/input/eventN
```

**Coordinate / orientation (1280×720):**
```bash
evtest /dev/input/eventN
# Tap top-left → low X/Y; bottom-right → high X/Y (check ABS max values)
# Record swap/invert if present — do NOT add calibration until confirmed on hardware
```

**Gesture checklist:**
- [ ] Single tap registers
- [ ] Drag/swipe registers continuous motion
- [ ] Long-press (if driver exposes it)
- [ ] Multi-touch (if ABS_MT_SLOT / second finger events appear)

**Suspend/resume:**
```bash
systemctl suspend
# Wake, then re-run libinput debug-events — touch must still work
```

**Launcher:**
- [ ] Touchscreen detected and reports input events
- [ ] Touchscreen coordinates/orientation correct in launcher and after resume
- [ ] Touch usable for menu navigation when launcher UI exists (scroll, tap)
- [ ] On-screen text entry fallback works for Wi-Fi password / pairing PIN

**Moonlight (separate from launcher shell):**
```bash
# After Wi-Fi connected — observe touch during stream; record behavior:
# - Mouse emulation (touch moves cursor / click)
# - Native touch injection (host receives touch — Sunshine-dependent)
# - No touch support (controller only)
# Explicit Moonlight touch config may be needed; document observed mode.
```

**If fails:**
- Check udev: `udevadm info --query=all --name=/dev/input/eventN | grep ID_INPUT_TOUCHSCREEN`
- Check module: `dmesg | grep -iE 'hid|i2c|goodix|ft5|touch'`
- Run `sudo streamos-input-test` (interactive) and attach output with diagnostics tarball
- Do not add calibration udev/libinput quirks until physical testing proves they are required

---

### Wi-Fi Connectivity

**Objective:** Verify Wi-Fi adapter and connectivity

**Test:**
```bash
# List network interfaces
ip link show
# Should show: wlan0 or similar UP

# Scan for networks
iw dev wlan0 scan
# Should list SSIDs

# Connect to known SSID
nmcli dev wifi connect "MySSID" password "password"

# Check IP
ip addr show wlan0
# Should have inet 192.168.x.x or similar

# Test connectivity
ping 8.8.8.8
```

**Checklist:**
- [ ] Wi-Fi chipset detected (lspci shows Qualcomm/MediaTek/Intel)
- [ ] wlan0 interface exists and is UP
- [ ] Can scan for available networks
- [ ] Can connect to test SSID
- [ ] DHCP obtains IP address
- [ ] Internet connectivity works (ping succeeds)
- [ ] Signal strength reported accurately

**If fails:**
- Check kernel module: `lsmod | grep -i ath11k`
- Verify firmware: Check `/lib/firmware/` for relevant vendor
- Collect diagnostics and kernel logs: `journalctl -b --no-pager`

---

### Bluetooth (Future)

**Objective:** Verify Bluetooth adapter (may not be used immediately)

**Test:**
```bash
# Check Bluetooth controller
bluetoothctl list
# Should show: hci0 [MAC]

# Enable Bluetooth
bluetoothctl power on

# Scan for devices
bluetoothctl scan on
# Keep controller pairing button held, should appear
```

**Checklist:**
- [ ] Bluetooth adapter visible in `bluetoothctl`
- [ ] Power can be toggled on/off
- [ ] Can scan for peer devices
- [ ] Can pair with gamepad/headphones

**Note:** Bluetooth may be optional for v1; document NEEDS_PHYSICAL_TEST if not critical.

---

### Audio

**Objective:** Verify audio output (speakers + 3.5mm jack)

**Test:**
```bash
# List audio devices
aplay -l
# Should show: card 0, device 0 (speakers) and/or 3.5mm device

# Test audio output
speaker-test -c 2 -r 48000 -t wav
# Or play a sound file
aplay /usr/share/sounds/freedesktop/stereo/complete.oga

# Check volume
alsamixer
# Adjust Master volume

# Check PipeWire status
pw-top
```

**Checklist:**
- [ ] Internal speaker detected
- [ ] 3.5mm jack detected (may appear when plugged)
- [ ] Audio plays through speaker
- [ ] Audio plays through headphones (when plugged)
- [ ] Volume control works (buttons or GUI)
- [ ] Mute works

**If fails:**
- Verify ALSA/PipeWire daemon running: `systemctl status pipewire`
- Check ALSA mixer: `alsamixer`
- Collect audio diagnostics: `aplay -l` output

---

### Power / Battery

**Objective:** Verify battery reporting and power management

**Test:**
```bash
# Check battery capacity
cat /sys/class/power_supply/BAT0/capacity  # or BAT1
# Should show: 50 (for 50%)

# Check charge status
cat /sys/class/power_supply/BAT0/status
# Should show: Charging, Discharging, Not charging, or Full

# Check power button
# Press power button → system should suspend
sleep 5 && systemctl suspend

# Wake from suspend
# Press power button again → system should resume
```

**Checklist:**
- [ ] Battery capacity shows percentage (0-100)
- [ ] Battery status correctly reports charging/discharging
- [ ] Power button enters suspend (screen goes dark, CPU idles)
- [ ] System wakes from suspend (power button or network wake)
- [ ] Battery voltage reported correctly
- [ ] Thermal zones show reasonable temperatures

**If fails:**
- Check ACPI battery interface: `ls -la /sys/class/power_supply/BAT*/`
- Verify power button event: `evtest` and press power button
- Check kernel support: `grep -i acpi /boot/config-*`

---

### Volume Buttons

**Objective:** Verify volume button mapping

**Test:**
```bash
# Monitor input events
evtest /dev/input/event0  # Find event device for keys

# Press volume up/down
# Should see: EV_KEY BTN_? or KEY_VOLUMEUP / KEY_VOLUMEDOWN
```

**Checklist:**
- [ ] Volume Up button detected as KEY_VOLUMEUP or custom event
- [ ] Volume Down button detected as KEY_VOLUMEDOWN or custom event
- [ ] Events reach ALSA/PipeWire (volume adjusts when pressed)

**Note:** NEEDS_PHYSICAL_TEST - mapping may be different on hardware

---

### Suspend / Resume

**Objective:** Verify power management and session persistence

**Test:**
```bash
# Trigger suspend
systemctl suspend

# Wait 10 seconds
sleep 10

# Wake by pressing power button
# Screen should come back on immediately

# Check logs
journalctl -b --no-pager | tail -50
# Look for: "Entering sleep state", "Leaving sleep state"
```

**Checklist:**
- [ ] Suspend enters low-power mode (screen off, minimal CPU activity)
- [ ] Resume from suspend is quick (<2 seconds)
- [ ] No errors in kernel logs after resume
- [ ] Hardware state preserved (Wi-Fi connection, etc.)
- [ ] Touchscreen still works after suspend/resume (re-test with `libinput debug-events`)

**If fails:**
- Check ACPI support: `dmesg | grep -i acpi`
- Verify S3 support: `grep -i "suspend state" /proc/acpi/wakeup`

---

## Gamescope & Display Server Test

### Objective
Verify Gamescope can render and handle input

**Test:**
```bash
# Start minimal Gamescope session
gamescope -W 1280 -H 720 --immediate-mode -- true

# Should show:
# - Gamescope window at 1280×720
# - Accepts gamepad input
# - Exits cleanly on button press

# Or test with a simple application
gamescope -W 1280 -H 720 -- bash -c "echo 'Hello from Gamescope'; sleep 10"
```

**Checklist:**
- [ ] Gamescope starts without errors
- [ ] Display scales correctly to 1280×720
- [ ] Gamepad input is recognized
- [ ] Touch input reaches compositor (if panel present)
- [ ] No GPU crashes or validation errors
- [ ] Exits cleanly on signal

**If fails:**
- Check Mesa/Vulkan: `vulkaninfo | grep VK_LAYER`
- Verify GPU drivers: `glxinfo | grep "Renderer"`
- Collect GPU diagnostics: `dmesg | grep -i amdgpu`

---

## Streaming Test (Optional for v1)

### Objective
Verify Moonlight can connect and stream video

**Prerequisites:**
- Sunshine server running on test gaming PC (same network)
- Or Steam Remote Play configured

**Test:**
```bash
# Ensure Wi-Fi connected
ip addr show wlan0

# Start Moonlight launcher (or CLI test)
moonlight list  # Discover servers

# Connect to server
moonlight stream -app "Desktop" -1080p -60fps

# Should see:
# - Server discovered via mDNS/Bluetooth
# - Connection established (streaming window opens)
# - Video at 1280×720 (or lower if bandwidth constrained)
# - Controller input sent to server
```

**Checklist:**
- [ ] Moonlight can discover Sunshine server
- [ ] Can authenticate with PIN
- [ ] Streaming video appears (any resolution)
- [ ] Frame rate stable at 60 FPS
- [ ] Controller input sent to game
- [ ] Touch behavior documented (mouse emulation / native touch / none)
- [ ] Audio plays from remote game
- [ ] Can exit stream cleanly

**If fails:**
- Verify server is reachable: `ping <server-ip>`
- Check firewall: Port 47989, 47990, 48010 (Sunshine defaults)
- Verify Moonlight dependencies: `ldd $(which moonlight)`
- Check codec support: `vainfo | grep H264`

---

## Collected Diagnostics

After each test phase, run diagnostics and save output:

```bash
sudo ./scripts/diagnostics.sh
# Creates: loki-diagnostics-YYYYMMDD-HHMMSS.tar.gz

# Optional: interactive touch verification + extra capture
sudo streamos-input-test
# Creates: streamos-input-test-YYYYMMDD-HHMMSS/ (attach alongside tarball)
```

**Contents:**
- System info (CPU, RAM, kernel)
- GPU driver status
- Input device listing (controller + touchscreen via `streamos-input-test --collect`)
- Network interface status
- Audio configuration
- Battery/power status
- Kernel logs (dmesg, journalctl)
- Loaded modules

**Return to cloud build system:**
- Copy diagnostics tarball
- Create GitHub issue with output
- Report which NEEDS_PHYSICAL_TEST items passed/failed

---

## Test Matrix

| Component | Status | Notes |
|-----------|--------|-------|
| Display (1280×720) | ? | TBD on hardware |
| GPU Drivers (AMDGPU) | ? | TBD on hardware |
| Controller Input | ? | TBD on hardware |
| Touchscreen | ? | NEEDS_PHYSICAL_TEST — I2C-HID vs USB HID, orientation |
| Wi-Fi Connectivity | ? | TBD on hardware |
| Audio Output | ? | TBD on hardware |
| Power Button | ? | TBD on hardware |
| Volume Buttons | ? | TBD on hardware |
| Battery Reporting | ? | TBD on hardware |
| Suspend/Resume | ? | TBD on hardware |
| Gamescope Rendering | ? | TBD on hardware |
| Moonlight Streaming | ? | TBD on hardware |

---

## Notes

- **Cloud Build:** This image was generated in a cloud environment without physical hardware. All hardware-specific functionality is validated in this phase.
- **Feedback Loop:** Results feed directly back to `loki-streamos` repository for iteration.
- **Non-Destructive:** USB boot does NOT modify internal Windows SSD. Safe to test.

---

## Contact

Report issues at: [GitHub Issues](https://github.com/yourusername/loki-streamos/issues)

Attach diagnostics tarball with your report for faster debugging.
