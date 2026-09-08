# Loki StreamOS Project Status

**Date**: September 8, 2026  
**Current Phase**: 4 complete in CI — **Phase 5 blocked on physical Loki Zero**  
**Next Milestone**: Boot image on hardware, run diagnostics

**Validation legend**
- **Implemented in repo** — code exists on `dev`
- **Validated in CI** — GitHub Actions built and structurally verified artifact
- **Validated on hardware** — tested on physical AYN Loki Zero (not yet)

---

## Project Goal (Phase 1)

Minimal Arch-based live streaming OS for AYN Loki Zero:

`UEFI → systemd-boot → Linux → Gamescope → minimal launcher`

| In scope | Out of scope (Phase 1) |
|----------|------------------------|
| Moonlight (primary) | Dual-boot installer |
| Steam (secondary, future) | Media caching, Tailscale |
| Touch + controller first | Plasma / Phosh / KDE / GNOME |
| Live USB — internal Windows/NVMe untouched | Polished launcher shell |

---

## ✅ Completed

### Phase 1: Hardware Research — COMPLETE (repo)
### Phase 2: Architecture — COMPLETE (repo)
### Phase 3: Build System — COMPLETE (repo)

### Phase 1 Amendment: Touchscreen — IMPLEMENTED IN REPO / NEEDS_PHYSICAL_TEST on hardware

### Phase 4: First Bootable Prototype — **VALIDATED IN CI** ✅

**Successful build (2026-09-08)**

| Field | Value |
|-------|-------|
| Commit | `b9958ea1697fe18adc5bfc3f44fb3b72eade9ab1` |
| CI run | [34244570703](https://github.com/HowardMoonsFunk/loki-streamos/actions/runs/34244570703) |
| Image | `loki-streamos-20260908.img` |
| Nominal size | 8.0 GiB (sparse; ~2.1 GiB on disk after build) |
| Checksum file | `loki-streamos-20260908.sha256` |
| SHA-256 | `7ca396292a56996b5836a30d9c0a8fcd91cffdaa2fdcd2e07b55bff56e262b9a` |
| Artifacts | [image](https://github.com/HowardMoonsFunk/loki-streamos/actions/runs/34244570703) · checksums uploaded |

**CI validated:**
- [x] pacstrap rootfs, partitions (EFI 512 MiB + ext4), sparse `.img`
- [x] systemd-boot, kernel, initramfs on ESP
- [x] `/etc/streamos-release`, launcher, diagnostics, `streamos-input-test`, `streamos-storage-status`
- [x] `wvkbd-mobintl` (built from pinned tag `v0.14.1` via Makefile on build host)
- [x] `validate-image.sh` structural checks
- [x] SHA-256 checksum verifies in build job
- [x] Artifact upload

**Not yet validated:**
- [ ] Boots on Loki Zero (**NEEDS_PHYSICAL_TEST**)
- [ ] Secondary verify job (artifact path fix pending in next commit)

---

## ⏳ Next: Phase 5 (Physical Hardware Testing)

All hardware items remain **NEEDS_PHYSICAL_TEST** until Loki Zero is booted from USB.

### Known Unknowns
1. Panel / eDP detection  
2. Power/volume button ACPI  
3. Wi-Fi chipset (ath11k vs mt7921)  
4. Bluetooth chipset/firmware  
5. Battery interface (BAT0 vs BAT1)  
6. Suspend (S3 vs S4)  
7. Touchscreen driver path (USB HID vs I2C-HID) and 1280×720 orientation  

---

## Phase 6: Launcher

**Current:** minimal Phase 1 launcher exists (`launcher/menu.sh` + Gamescope + `wmenu`).  
**Future:** polished controller-driven shell — not started.

---

## Flash instructions

**Status:** IMPLEMENTED · TESTED WITH LOOPBACK (dry-run in CI) · NEEDS_PHYSICAL_TEST

```bash
# Download loki-streamos-20260908.img + .sha256 from GitHub Actions artifacts
sudo ./tools/flash/flash-streamos.sh loki-streamos-20260908.img
# Type exactly: FLASH /dev/sdX
```

Windows (Administrator PowerShell):
```powershell
.\tools\flash\flash-streamos.ps1 -Image .\loki-streamos-20260908.img
```

See `tools/flash/README.md` for `--dry-run`, `--verify`, and safety details.

Boot Loki Zero: hold **Volume Down** at power-on → select USB.

On device:
```bash
streamos-storage-status   # confirm internal NVMe/eMMC not mounted
loki-diagnostics
streamos-input-test
```

---

## Build notes (for maintainers)

- `wvkbd` is **not** in Arch repos; built from GitHub tag `v0.14.1` (Makefile) on CI host, not in chroot
- Image uses `truncate` (sparse) to save runner disk space
- `.gitattributes` enforces LF on shell scripts
- Internal storage: `60-streamos-storage.rules` + fstab has no nvme/mmcblk entries

---

**Last Updated**: 2026-09-08  
**Phase 4 CI green commit**: `b9958ea`
