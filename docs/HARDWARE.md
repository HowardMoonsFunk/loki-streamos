# Loki Zero Hardware Support Research

## Device Specs
- **CPU**: AMD Athlon Silver 3050e (Zen+, 2 cores / 2 threads @ 1.5-3.2 GHz)
- **GPU**: Radeon Vega iGPU (Vega 3, 3 CUs)
- **RAM**: 6 GB LPDDR4
- **Display**: 6" 1280×720 IPS (161 PPI)
- **Storage**: 128 GB eMMC (internal Windows SSD - do not touch)
- **Input**: Built-in gamepad/controller, capacitive touchscreen (6" panel)
- **Connectivity**: Wi-Fi 6 (802.11ax), Bluetooth 5.2
- **Audio**: 3.5mm jack, onboard stereo speakers
- **Battery**: 4000 mAh
- **Ports**: USB-C (power/data), microSD card slot

---

## Hardware Component Support Status

### CPU / Chipset
- **Model**: AMD Athlon Silver 3050e (Picasso APU)
- **Upstream Support**: Full in Linux 5.10+
- **Status**: ✅ Well-supported, no custom drivers needed
- **Notes**: Standard x86-64, CPUID detection works fine

### GPU / AMDGPU Driver
- **Model**: Radeon Vega (Vega 3)
- **Driver**: AMDGPU (open-source, mainline Linux)
- **Status**: ✅ Excellent upstream support
- **Kernel Module**: amdgpu (load with `amdgpu.exp_hw_support=1` for older kernels)
- **Mesa Version**: 23.0+ recommended for best H.264/HEVC decode
- **Hardware Video Decode**: 
  - H.264: Supported via VCN (Video Core Next)
  - HEVC: Supported via VCN
  - VP9: Not supported on Vega
- **Notes**: 
  - Vega iGPU is well-supported for streaming decode
  - Enable VAAPI/VA-GL for hardware acceleration in Moonlight/VLC
  - Reference: https://www.kernel.org/doc/html/latest/gpu/amdgpu.html

### Display / Backlight
- **Panel**: 1280×720, likely eDP over DSI or MIPI
- **AMDGPU DC Support**: ✅ Should work automatically
- **Backlight**: Likely ACP (AMD Common Platform) or PWM-based
- **Status**: NEEDS_PHYSICAL_TEST (panel detection should be automatic)
- **Reference**: Check `cat /sys/class/backlight/*/brightness`

### Integrated Controller / Input
- **Type**: Built-in gamepad (likely USB HID over internal connection)
- **Bazzite/ChimeraOS Status**: ✅ Fully working
- **Driver Stack**: Standard Linux HID, evdev
- **Testing**: `cat /dev/input/event*` should report button presses
- **Reference**: Bazzite images confirm D-pad, analog sticks, triggers, bumpers all work
- **Notes**: May need custom keymap for power/volume buttons

### Touchscreen
- **Type**: Capacitive panel on 6" 1280×720 display
- **Likely Interface**: USB HID and/or I2C-HID (NEEDS_PHYSICAL_TEST)
- **Status**: NEEDS_PHYSICAL_TEST — driver path and coordinate orientation unknown
- **Driver Stack**: `hid-multitouch`, `goodix`, `ft5x06`, or similar mainline driver (TBD)
- **Testing**:
  - Identify: `libinput list-devices`, `/proc/bus/input/devices`, `udevadm info`, `lsusb`, I2C scan
  - Events: `libinput debug-events --device=<node>` or `evtest`
  - Full capture: `streamos-input-test --collect` (included in diagnostics tarball)
- **UX role**: First-class fallback control path on a 6" handheld — Wi-Fi/BT pairing, text entry, and emergency diagnostics should work via touch even when controller-driven UI is primary
- **Calibration**: Do **not** hard-code transforms until physical testing proves X/Y swap, invert, or offset is required
- **Moonlight**: Touch behavior is client-dependent (mouse emulation vs native touch injection); verify separately from launcher shell
- **Reference**: Compare against Bazzite/ChimeraOS touch behavior on Loki Zero

### Power Button / Volume Buttons
- **Integration**: Likely mapped to ACPI or GPIO events
- **Bazzite Status**: ✅ Power button works in Bazzite
- **Status**: NEEDS_PHYSICAL_TEST (volume button mapping)
- **Implementation**: systemd-logind can handle power button → suspend/shutdown
- **Reference**: `/etc/systemd/logind.conf` and `HandlePowerKey`, `HandleVolumeKey`

### Wi-Fi
- **Standard**: 802.11ax (Wi-Fi 6)
- **Likely Chipset**: Qualcomm or MediaTek (common in Picasso era)
- **Status**: NEEDS_PHYSICAL_TEST (exact chipset TBD)
- **Bazzite/ChimeraOS**: ✅ Works out of box
- **Driver**: Likely ath11k (Qualcomm) or mt7921 (MediaTek)
- **Connection**: NetworkManager or iwd recommended
- **Reference**: `lspci -nnk` and `lsmod | grep -E "ath|mt7|iwl"` will identify

### Bluetooth
- **Version**: Bluetooth 5.2
- **Likely Chipset**: Same as Wi-Fi (integrated combo module)
- **Status**: NEEDS_PHYSICAL_TEST
- **Bazzite/ChimeraOS**: ✅ Works
- **Daemon**: bluetoothd (BlueZ)
- **Testing**: `bluetoothctl scan on` should find devices
- **Reference**: Will identify from `lspci`/`lsusb`

### Audio
- **Output**: 3.5mm headphone jack + internal stereo speakers
- **Likely Codec**: Realtek ALC (common on AMD boards)
- **Server**: PipeWire (modern) or ALSA directly
- **Status**: ✅ Should work with standard drivers
- **Bazzite/ChimeraOS**: ✅ Confirmed working
- **Testing**: `pactl list short sinks` / `aplay -l`
- **Notes**: Volume buttons may need mapping to ALSA controls

### Battery / Power Supply
- **Capacity**: 4000 mAh
- **Reporting**: ACPI battery interface
- **Status**: ✅ Standard Linux support
- **Testing**: `cat /sys/class/power_supply/BAT*/uevent`
- **Display**: Can show in launcher via /sys/class/power_supply/

### Suspend / Resume
- **ACPI S3/S4 Support**: ✅ Should work (Picasso supports modern ACPI)
- **Status**: NEEDS_PHYSICAL_TEST
- **Implementation**: systemd-sleep handles via `/etc/systemd/sleep.conf`
- **Bazzite/ChimeraOS**: ✅ Confirmed
- **Notes**: May need `acpi=force` kernel parameter on older BIOS

### USB-C Port
- **Type**: USB 3.1 Gen 1 (5 Gbps) likely
- **Charging**: Yes (5V/2A or higher expected)
- **Data**: Yes (mass storage, fastboot)
- **Status**: ✅ Standard, no special handling needed

### microSD Card Slot
- **Interface**: SDHCI (SD Host Controller)
- **Status**: ✅ Standard, auto-detected by kernel
- **Testing**: `lsblk` should show `/dev/mmcblk*`

---

## Existing Reference Implementations

### Bazzite (KDE Plasma-based)
- **Status**: ✅ Runs on Loki Zero
- **Repo**: https://github.com/ublue-os/bazzite
- **Relevant Code**: 
  - Hardware detection: `https://github.com/ublue-os/bazzite/tree/main/system_files/usr/share/ublue-os/firstboot`
  - Power management: Already integrated
  - Controller support: Full
- **Lessons Learned**: All hardware *is* detected and working; Bazzite's overhead is the desktop environment, not the drivers

### ChimeraOS
- **Status**: ✅ Also runs on Loki Zero
- **Repo**: https://github.com/ChimeraOS/chimeraos
- **Minimal Approach**: More streamlined than Bazzite, closer to what we want
- **Relevant**: Uses similar hardware detection but with lighter UI

### Batocera
- **Status**: Emulation-focused, less relevant for streaming
- **Note**: Confirms Loki Zero hardware is well-supported on Linux

---

## Kernel Configuration

### Minimum Kernel Version: 5.15 LTS (5.10 acceptable, 6.1+ recommended)

### Key Modules Required:
```
amdgpu              # GPU driver
amdgpu_vcn          # Video decode
drm_amd_sched       # GPU scheduler
acpi_cpufreq        # CPU frequency scaling
radeon (legacy)     # NOT needed for Vega
```

### Recommended Kernel Parameters:
```
amdgpu.exp_hw_support=1     # Enable experimental features (pre-5.13)
amdgpu.gpu_recovery=1       # GPU hang recovery
video.allow_duplicates=1    # Multiple displays (if needed)
```

### Performance Tuning (Post-Boot):
```
echo 7 > /sys/class/graphics/fb0/state  # Framebuffer acceleration
```

---

## Architecture Decision: Arch vs Fedora

| Factor | Arch | Fedora Minimal |
|--------|------|---|
| **Package Recency** | Cutting edge | Conservative (stable) |
| **Reproducibility** | Good (AUR) | Excellent (DNF locks) |
| **Minimal Size** | ~800 MB | ~1.2 GB |
| **Driver Support** | First-class | First-class |
| **ARM Variants** | Yes (for future) | Limited |
| **Maintenance Burden** | Rolling (constant) | Stable releases (predictable) |
| **Community Size** | Smaller, enthusiast | Larger, enterprise |

**Recommendation**: **Arch Linux** with custom pacman.conf
- Rolling updates keep Mesa/AMDGPU current (critical for GPU fixes)
- Minimal by default, add only what's needed
- Better for appliance use case (version pinning possible)
- AUR access for niche packages (Moonlight, specialized tools)

---

## Next Steps (Phase 2)

1. Confirm Arch Linux as base
2. Define minimal package set
3. Design boot flow: UEFI → systemd-boot → Linux → systemd → Gamescope → Launcher
4. Identify critical udev rules (controller, power button)
5. Plan Moonlight integration (AppImage or source build)

---

## Testing Checklist (Physical Hardware)

After image boots on Loki Zero:

- [ ] Display works, 1280×720 detected
- [ ] Controller detected: `cat /proc/bus/input/devices`
- [ ] Touchscreen detected and reports input events
- [ ] Touchscreen coordinates/orientation correct in launcher and after resume
- [ ] Wi-Fi scan: `iw dev wlan0 scan`
- [ ] Bluetooth scan: `bluetoothctl scan on`
- [ ] Audio out: `aplay /usr/share/sounds/freedesktop/stereo/complete.oga`
- [ ] Power button suspends system
- [ ] Volume buttons work
- [ ] Battery status shows: `cat /sys/class/power_supply/BAT*/capacity`
- [ ] Gamescope renders test pattern
- [ ] Moonlight connects to test server

---

**Last Updated**: 2026-09-08
**Status**: Phase 1 Complete (research), Phase 4+ physical validation pending
