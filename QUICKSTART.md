# Loki StreamOS Quick Start

**You are here**: Cloud development environment with buildable image sources.

---

## 📦 What You Have

A **complete, reproducible Linux appliance for AYN Loki Zero** designed to stream games via Moonlight or Steam Remote Play.

**Status**: Ready for first bootable image generation.

### Files & Directories
```
loki-streamos/
├── scripts/build-image.sh       ← Main build script
├── base/pacman.conf             ← Minimal Arch config
├── .github/workflows/           ← CI/CD pipeline
├── docs/                        ← Complete documentation
│   ├── HARDWARE.md              ← Hardware research
│   ├── ARCHITECTURE.md          ← System design
│   ├── TESTING.md               ← Physical test checklist
│   └── ADR-001-BASE-OS.md       ← Arch decision record
└── README.md, STATUS.md         ← Project overview
```

---

## 🚀 Next Steps

### Option 1: Run Locally (if you have Arch Linux)

```bash
# Clone the repo to your machine
git clone /home/claude/loki-streamos
cd loki-streamos

# Build the image (requires sudo, ~30 min, 8 GB disk space)
sudo bash scripts/build-image.sh

# Output: build-artifacts/loki-streamos-YYYYMMDD.img
```

### Option 2: Run in GitHub Actions (Recommended)

1. **Push to GitHub**
   ```bash
   cd loki-streamos
   git remote add origin https://github.com/YOUR_USERNAME/loki-streamos
   git push -u origin main
   ```

2. **GitHub Actions builds automatically**
   - Go to: `https://github.com/YOUR_USERNAME/loki-streamos/actions`
   - Watch the workflow: `.github/workflows/build-image.yml`
   - Download artifact: `loki-streamos-image`

3. **Output**: `loki-streamos-YYYYMMDD.img` (~8 GB)

### Option 3: Cloud Build

Available cloud platforms:
- **GitHub Actions**: Free tier (included in repo)
- **GitLab CI**: Similar free tier
- **DigitalOcean / AWS**: For persistent runners

---

## 🔌 Writing Image to USB

Once you have `loki-streamos-YYYYMMDD.img`:

```bash
# 1. Identify your USB device
lsblk
# Look for: /dev/sdX (NOT /dev/sda if that's your main disk!)

# 2. Unmount if already mounted
sudo umount /dev/sdX*

# 3. Write image to USB
sudo dd if=loki-streamos-YYYYMMDD.img of=/dev/sdX bs=4M status=progress
sudo sync

# 4. Eject
sudo eject /dev/sdX

# ✅ USB is now bootable!
```

---

## 💻 Testing on Loki Zero

1. **Insert USB** into Loki's USB-C port (with adapter if needed)
2. **Power on** while holding **Volume Down** (boot menu)
3. **Select USB device** from boot menu
4. **Wait** ~15 seconds for boot to launcher
5. **Test hardware**:
   - Try D-pad and buttons (controller should work)
   - Look for Wi-Fi networks
   - Check display resolution

### Run Diagnostics

Once booted on Loki:
```bash
sudo ./scripts/diagnostics.sh

# Creates: loki-diagnostics-YYYYMMDD-HHMMSS.tar.gz
# Contains: Hardware detection, logs, device info
```

**Send diagnostics back to cloud build system** for iteration.

---

## 📚 Key Documentation

Start here based on your interests:

| Document | Purpose |
|----------|---------|
| **README.md** | Overview & usage |
| **docs/HARDWARE.md** | What hardware is supported |
| **docs/ARCHITECTURE.md** | How the system boots & works |
| **docs/TESTING.md** | Physical test checklist |
| **STATUS.md** | Project roadmap & progress |

---

## 🎯 Success Criteria (Phase 4)

**Image is ready when:**
- ✅ Build script generates .img without errors
- ✅ Image is ~8 GB (compressed ~1-2 GB)
- ✅ SHA-256 checksums match
- ✅ Image boots on Loki Zero
- ✅ Controller detected
- ✅ Display shows 1280×720
- ✅ Wi-Fi scan works
- ✅ Gamescope renders
- ✅ Moonlight connects to test server

**Phases 5+** (after hardware testing):
- Fix hardware-specific issues
- Implement launcher UI
- Optimize performance
- Release v0.1.0-beta

---

## ❓ FAQ

### Q: Do I need physical Loki hardware to build?
**A**: No! Build runs in cloud (Arch Linux container). Physical hardware needed only for testing.

### Q: Will this destroy my Loki's Windows installation?
**A**: No! USB boot is non-destructive. Internal SSD never touched. See `docs/TESTING.md`.

### Q: Can I use this on other devices?
**A**: Yes, eventually. Currently optimized for Loki Zero. AMD Athlon + Vega GPU + 6" 720p screen. Extending to other handhelds is future work.

### Q: What if hardware doesn't work?
**A**: Run `diagnostics.sh`, send results back. We iterate on drivers/config until it works.

### Q: When can I actually play games?
**A**: Phase 4 (bootable image): 1-2 weeks. Phase 5 (hardware testing): depends on your Loki. Phase 6 (launcher): 2-4 weeks after hardware testing passes.

### Q: What's the performance like?
**A**: **Target**: 720p60 H.264/HEVC streaming, <1 GB RAM, <10 second boot. Actual performance TBD on hardware.

### Q: Can I help?
**A**: Yes! Test on physical Loki → run diagnostics → report results. That's the critical path.

---

## 🔗 Key Files to Know

| File | Purpose |
|------|---------|
| `scripts/build-image.sh` | Generates bootable .img (runs as root) |
| `scripts/diagnostics.sh` | Collects hardware info on Loki |
| `.github/workflows/build-image.yml` | Automated CI/CD on GitHub |
| `base/pacman.conf` | Arch Linux minimal package set |
| `docs/HARDWARE.md` | All hardware research |

---

## 📞 Getting Help

1. **Check documentation**: `docs/` folder
2. **Review STATUS.md**: Current progress & roadmap
3. **Look at TESTING.md**: Physical hardware issues
4. **Check build logs**: GitHub Actions workflow output

---

## ⚡ One-Liner Summary

**Loki StreamOS**: Minimal Linux for AYN Loki Zero that boots from USB, detects hardware, and streams games from your PC via Moonlight.

**Status**: Ready to build first bootable image. Awaiting physical Loki for hardware testing.

**Next**: Generate .img → Write to USB → Boot Loki → Run diagnostics → Iterate.

---

**See also**: `README.md` (project overview), `STATUS.md` (detailed roadmap)
