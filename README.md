# Loki StreamOS

Minimal Linux gaming-streaming appliance for the AYN Loki Zero.

**Purpose**: Power on → Wi-Fi → controller-driven UI → Moonlight → game.

Not a general-purpose desktop. No GNOME/KDE, minimal background services.

---

## Quick Start

### Building the Image (Local or CI)

```bash
# Install dependencies (Arch Linux)
sudo pacman -S arch-install-scripts mtools dosfstools squashfs-tools

# Build minimal root filesystem
./scripts/build-rootfs.sh

# Generate bootable .img
./scripts/build-image.sh

# Output: build-artifacts/loki-streamos-YYYYMMDD.img
```

### Writing to USB/SD Card

```bash
# List disks
lsblk

# Write image (replace sdX with your USB device)
sudo dd if=build-artifacts/loki-streamos-YYYYMMDD.img of=/dev/sdX bs=4M status=progress
sudo sync

# Eject
sudo eject /dev/sdX
```

### Boot on Loki Zero

1. Insert USB into Loki's USB-C port
2. Power on while holding **Volume Down** (enters boot menu)
3. Select USB device
4. Wait for boot to launcher
5. Connect to Wi-Fi
6. Launch Moonlight or Steam

---

## Project Structure

```
loki-streamos/
├── base/
│   ├── pacman.conf          # Arch package config (minimal repos)
│   ├── systemd/             # systemd units
│   └── udev/                # Hardware-specific rules
├── hardware/ayn-loki-zero/
│   ├── kernel.config        # Minimal kernel options
│   └── quirks.sh            # Loki-specific hardware tweaks
├── launcher/
│   ├── src/                 # Minimal Wayland launcher
│   └── assets/              # 720p UI assets
├── installer/
│   ├── partition-schema.txt # Future: internal SSD install
│   └── DESIGN.md            # Installer architecture (not yet implemented)
├── scripts/
│   ├── build-rootfs.sh      # Generate /etc, /usr, /var
│   ├── build-image.sh       # Create .img from rootfs
│   └── diagnostics.sh       # Hardware testing script
├── docs/
│   ├── HARDWARE.md          # Research & verification status
│   ├── ADR-001-BASE-OS.md   # Arch Linux decision
│   ├── ARCHITECTURE.md      # Boot flow & system design
│   └── TESTING.md           # Physical hardware checklist
├── .github/workflows/
│   └── build-image.yml      # CI pipeline
├── build-artifacts/         # Generated .img, checksums
├── .gitignore
├── README.md
└── LICENSE
```

---

## Development Phases

### Phase 1: Research ✅
- [x] Identify Loki Zero hardware support
- [x] Evaluate base OS candidates
- [x] Document findings in HARDWARE.md

### Phase 2: Architecture (IN PROGRESS)
- [ ] Design boot flow (UEFI → systemd-boot → Gamescope)
- [ ] Define systemd service graph
- [ ] Plan launcher architecture
- [ ] Loki-specific udev rules

### Phase 3: Build System (STARTING)
- [ ] pacman.conf for minimal packages
- [ ] rootfs generation script
- [ ] Image creation (dd-able .img)
- [ ] Checksum/signing

### Phase 4: First Bootable Prototype (NEXT)
- [ ] Gamescope rendering test
- [ ] Controller input working
- [ ] Wi-Fi connection screen
- [ ] Boot to launcher (no X11, no keyboard needed)

### Phase 5: Diagnostics
- [ ] Hardware detection script
- [ ] Collect logs & device info
- [ ] Package results for feedback loop

### Phase 6: Installer (Deferred)
- [ ] Design internal SSD install
- [ ] A/B partition scheme for updates
- [ ] Documentation only (not implemented in v1)

---

## Target Specs

| Metric | Target |
|--------|--------|
| RAM after boot | <1 GB |
| Boot to launcher | <10 seconds |
| Video decode | Hardware-accelerated (H.264/HEVC) |
| Streaming resolution | 720p60 |
| Unnecessary services | 0 (systemd only) |

---

## Hardware Support Status

See [docs/HARDWARE.md](docs/HARDWARE.md) for detailed research.

**Verified Working** (from Bazzite/ChimeraOS):
- ✅ AMDGPU + Mesa (Vega decode)
- ✅ Integrated controller
- ✅ Wi-Fi 6 (802.11ax)
- ✅ Bluetooth 5.2
- ✅ Audio (3.5mm + speakers)
- ✅ Suspend/resume

**Needs Physical Test**:
- NEEDS_PHYSICAL_TEST: Display detection
- NEEDS_PHYSICAL_TEST: Power/volume buttons
- NEEDS_PHYSICAL_TEST: Battery reporting
- NEEDS_PHYSICAL_TEST: microSD card slot

---

## Key Design Decisions

1. **Arch Linux Base**: Rolling updates, minimal, GPU driver currency
2. **systemd-boot**: Lightweight UEFI bootloader
3. **systemd (init only)**: No systemd-journald overhead; syslog if needed
4. **Gamescope**: GPU-accelerated display server + input handling
5. **Minimal Launcher**: Controller-first Wayland app, no X11
6. **Removable Media First**: USB boot before internal SSD modification
7. **No Desktop Environment**: Every KB matters on 6GB device

See [docs/ADR-001-BASE-OS.md](docs/ADR-001-BASE-OS.md) for rationale.

---

## Testing

### Cloud-Based Build Verification
- [ ] Build script runs without errors
- [ ] .img file generates and checksums match
- [ ] Image is dd-able

### Physical Hardware Testing (After Flashing USB)
- [ ] Loki boots from USB
- [ ] Controller detected
- [ ] Wi-Fi scan available
- [ ] Moonlight connects to test server
- See [docs/TESTING.md](docs/TESTING.md) for full checklist

---

## Contributing

1. Add hardware findings to `docs/HARDWARE.md`
2. Test on physical Loki Zero; report results
3. Propose changes via ADR (architecture decision records)

---

## License

TBD (likely GPL-2.0 for kernel compatibility)

---

## Status

**Current**: Phase 2 (Architecture) — Building out systemd units and launcher framework
**Next Milestone**: Bootable .img artifact (Phase 4)
**ETA**: Testing on physical hardware when Phase 4 complete

See [GitHub Projects](#) for live progress.
