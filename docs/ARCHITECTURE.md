# Loki StreamOS Architecture

## Boot Flow

```
┌─────────────────────────────────────────────────────┐
│  Loki Zero Powers On                                │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  UEFI Firmware (BIOS)                               │
│  • Detects USB (or internal SSD)                    │
│  • Loads systemd-boot from EFI partition           │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  systemd-boot (UEFI Bootloader)                     │
│  • Reads boot entry: loki-streamos.conf            │
│  • Loads linux-lts kernel + initramfs              │
│  • Passes kernel parameters (root=LABEL=LOKI_...)  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  Linux Kernel (linux-lts 6.1+)                      │
│  • Initializes CPU, RAM, peripherals               │
│  • Loads: amdgpu, input drivers, networkmanager    │
│  • Root filesystem mounts (ext4 LOKI_SYSTEM)       │
│  • Hands off to systemd                            │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  systemd (init system)                              │
│  • Mounts filesystems (/boot, /tmp, /run)         │
│  • Starts services (in dependency order):          │
│    - systemd-logind (power, session mgmt)          │
│    - NetworkManager (Wi-Fi/Bluetooth)              │
│    - bluetoothd (if enabled)                       │
│    - PipeWire (audio server)                       │
│    - udev (device management)                      │
│  • Targets: multi-user → (graphical if graphics)  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  User login (auto-login as user 'loki')            │
│  • No password required (appliance mode)            │
│  • Shell: /bin/bash or /bin/sh                     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  Loki Launcher Session (~.xinitrc or systemd-user) │
│  • Start Gamescope (display server + GPU accel)    │
│  • Load controller input devices                    │
│  • Display UI (Moonlight launcher, Wi-Fi menu)     │
│  • Wait for user interaction                       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  User selects: Connect to Gaming PC                │
│  • Establish Wi-Fi connection                      │
│  • Launch Moonlight → Sunshine server             │
│  • Stream game to Loki display                     │
└─────────────────────────────────────────────────────┘
```

---

## Key System Components

### 1. Bootloader
- **systemd-boot** (UEFI)
- Minimal, fast, standard on Arch Linux
- Configuration: `/boot/loader/loader.conf` and `entries/*.conf`
- Supports multiple boot entries (future: recovery mode)

### 2. Kernel
- **linux-lts** (Long Term Support, 6.1+)
- Minimal, custom UEFI-x86_64 config
- Key modules: amdgpu, amdgpu-vcn, drm, input
- Parameters: `root=LABEL=LOKI_SYSTEM ro quiet`

### 3. Init System
- **systemd** (only, no syslog or other inits)
- Lightweight service manager
- User services via ~/.config/systemd/user/
- Target: multi-user (no graphical.target overhead)

### 4. Display & Graphics
- **Gamescope** (Valve's GPU-accelerated display server)
- Replaces X11/Wayland for appliance use
- Native 1280×720 rendering, vsync, input passthrough
- Uses: AMDGPU + Mesa + Vulkan
- Runs as unprivileged user service

### 5. GPU Driver Stack

```
Application (Moonlight)
        │
        ▼
    Vulkan / OpenGL
        │
        ▼
    Mesa (libgl, libvulkan)
        │
        ▼
    AMDGPU Kernel Driver
        │
        ▼
    Radeon Vega GPU
        │
        ├─ H.264/HEVC decode (VCN)
        ├─ 3D rendering (GCN cores)
        └─ Display output (HDMI/eDP)
```

**Key Packages:**
- `amdgpu-dkms`: Kernel driver + DKMS auto-rebuild
- `mesa`: OpenGL, Vulkan, VAAPI, display driver
- `vulkan-radeon`: Vulkan driver for Radeon
- `lib32-mesa`: (optional) 32-bit libs for Steam Runtime

### 6. Audio
- **PipeWire** (modern audio server)
- Replaces PulseAudio/ALSA for lower latency
- Routes:
  - Speaker (internal, always available)
  - 3.5mm headphone jack (auto-detected when plugged)
- Configuration: `/etc/pipewire/pipewire.conf`

### 7. Networking
- **NetworkManager** (or iwd lightweight)
- Wi-Fi scanning, connection, DHCP
- Bluetooth integration
- systemd-resolved for DNS
- No Internet-heavy services (no updates over network by default)

### 8. Controller Input
- **systemd-logind** + HID drivers
- Standard Linux `/dev/input/event*` stack
- Gamepad input reaches Gamescope → Moonlight

### 8b. Touchscreen Input
- Capacitive panel on 6" 1280×720 display (USB HID and/or I2C-HID — TBD on hardware)
- **libinput** + evdev; udev `ID_INPUT_TOUCHSCREEN` grants user access
- First-class fallback alongside controller: Wi-Fi/BT pairing, text entry, diagnostics
- No calibration layer in v1 — apply transforms only if physical testing proves they are needed
- **Moonlight touch** tested separately (mouse emulation vs native touch injection varies by client/host)

### 9. Power Management
- **systemd-logind** 
- Power button → suspend (S3)
- Resume button (power button again)
- Battery reporting via ACPI `/sys/class/power_supply/`
- Lid switch (if available) → suspend

---

## Systemd Service Graph

**Minimal set of services:**

```
System start
    │
    ├─► systemd-logind.service [login, power button]
    │
    ├─► systemd-networkd.service [basic networking]
    │
    ├─► NetworkManager.service [Wi-Fi, Bluetooth]
    │
    ├─► bluetoothd.service [Bluetooth daemon]
    │
    ├─► pipewire.service [Audio server]
    │   └─► pipewire-pulse.service [PulseAudio compat]
    │
    ├─► udev [device management]
    │
    └─► [multi-user.target reached]
        │
        └─► [User login as 'loki']
            │
            └─► User session start
                │
                └─► gamescope --launcher-mode [Display + UI]
```

**NOT started by default:**
- X11, Xvfb (not needed)
- systemd-journald (journalctl still available, but minimal)
- avahi (mDNS discovery optional for Moonlight)
- SSH daemon (disabled by default for appliance)

---

## File System Layout

```
Partition 1 (EFI_SYSTEM, vfat, 512MB)
    /boot/
    ├── EFI/
    │   └── BOOT/
    │       └── BOOTX64.EFI (systemd-boot)
    ├── loader/
    │   ├── loader.conf
    │   └── entries/
    │       └── loki-streamos.conf
    ├── vmlinuz-linux-lts
    └── initramfs-linux-lts.img

Partition 2 (ROOT, ext4, ~7.5GB)
    /
    ├── /boot (bind mount to part 1, or symlink)
    ├── /bin, /lib, /usr (OS files, ~1-1.5 GB)
    ├── /opt/launcher (Loki UI, <100 MB)
    ├── /opt/moonlight (Moonlight + deps, <200 MB)
    ├── /etc (config, ~50 MB)
    ├── /var/log (logs, minimal, ~100 MB)
    ├── /var/cache (package cache if pacman used)
    ├── /home/loki (user home, <100 MB)
    ├── /root (root home, empty)
    ├── /tmp (tmpfs, 256 MB RAM)
    └── /run (tmpfs, 256 MB RAM)
```

**Total on-disk:** ~2-3 GB (before user data)
**RAM after boot:** <1 GB (target)

---

## Device Hardware Mapping

### Input Events
```
/dev/input/event0+   → Controller / touch / keyboard events
    ├─ Integrated gamepad: BTN_*, ABS_HAT0X, ABS_X, ABS_Y, etc.
    └─ Touchscreen: BTN_TOUCH, ABS_MT_* (identify via libinput list-devices)

/dev/input/mice      → Mouse events (if attached, not common on Loki)
```

### Display
```
/dev/dri/card0       → AMD GPU (DRM)
/dev/dri/renderD128  → GPU render node (for Vulkan)

/sys/class/backlight/ → Brightness control (PWM or AMDGPU)
```

### Audio
```
/dev/snd/card0       → Realtek audio codec (speakers)
/dev/snd/hwC0D0      → Hardware device
```

### Network
```
/dev/wlan0           → Wi-Fi adapter
    └─ Driver: ath11k / mt7921 / iwlwifi (TBD on hardware)
```

### Bluetooth
```
/dev/ttyACM0         → Bluetooth serial (if present)
    └─ Driver: btusb / hci_uart (TBD on hardware)
```

### Battery / Power
```
/sys/class/power_supply/BAT0/  → Battery 0
/sys/class/power_supply/AC0/   → AC power status
```

---

## Filesystem Mounting Strategy

**At Boot:**
1. UEFI loads initramfs
2. Initramfs mounts root partition (LABEL=LOKI_SYSTEM)
3. systemd takes over, mounts everything via `/etc/fstab`:
   - `/boot` → EFI partition (vfat)
   - `/tmp` → tmpfs (256 MB)
   - `/run` → tmpfs (256 MB)
4. Read-only overlay potential (future): System partition read-only, overlay for updates

---

## Security Considerations

**Enabled (by design):**
- Secure Boot (UEFI, if available) — not required but supported
- File permissions (ext4 default)
- SELinux / AppArmor (optional, not included in v1)

**Disabled (for appliance simplicity):**
- Password authentication (auto-login as 'loki' user)
- SSH (disabled by default)
- USB mass storage restrictions (USB is trusted)
- Firewall (assumes home network)

**Future improvements:**
- Signed kernel/modules
- Immutable system partition (A/B updates)
- Encrypted user partition
- Pin/biometric auth for Moonlight connections

---

## Performance Tuning

### CPU
- CPU frequency scaling: `acpi-cpufreq` or `amd-pstate` (dynamically scales 1.5-3.2 GHz)
- Power profiles: `power-profiles-daemon` (optional) or systemd defaults
- Core pinning: Not used (2 cores only, let kernel decide)

### GPU
- AMDGPU clock scaling: Automatic, Mesa handles
- GPU frequency: Adaptive based on load
- Power saving: Enabled (automatic)

### Memory
- No swap (6 GB sufficient)
- Mem pressure: Minimal (typical: 300-500 MB after boot)

### Disk I/O
- ext4 defaults: Good balance of speed/safety
- No need for custom I/O scheduler

---

## Future Architecture Changes

### Phase 5: Installer
- Internal SSD partitioning (EFI, SYSTEM, DATA)
- A/B SYSTEM partitions for atomic updates
- Encrypted DATA partition (user configs, game saves)

### Phase 6: Remote Play
- VPN / WireGuard support (for playing away from home)
- Launcher integrates network-aware routing

### Phase 7: Updates
- Immutable system partition (signed kernel + rootfs)
- Atomic updates: Swap A/B partition, reboot
- User data preserved across updates

---

## Debugging & Diagnostics

### Boot Logs
```bash
# View kernel boot
dmesg | less

# View systemd boot process
journalctl -b -e --no-pager

# Watch services starting
systemctl status    # Current state
systemctl list-units --type=service
```

### Performance Monitoring
```bash
# CPU/Memory
top -b

# GPU
lspci -nnk | grep -A2 VGA
glxinfo | grep "Renderer"

# Disk I/O
iostat -x 1

# Temperature
sensors
```

### Hardware Discovery
```bash
# Full device list
lspci -nnk
lsusb -vv

# Partition table
fdisk -l
parted -l

# Filesystems
mount | grep loki
df -h
```

---

## References

- [Arch Linux Wiki](https://wiki.archlinux.org)
- [systemd Documentation](https://www.freedesktop.org/software/systemd/man/)
- [AMDGPU Kernel Documentation](https://www.kernel.org/doc/html/latest/gpu/amdgpu.html)
- [Gamescope Repository](https://github.com/ValveSoftware/gamescope)
- [Moonlight Project](https://moonlight-stream.org)

---

**Last Updated**: 2024-09-08  
**Status**: Initial architecture, pending Phase 4 (bootable prototype)
