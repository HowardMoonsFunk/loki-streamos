# Loki StreamOS Project Status

**Date**: September 8, 2026  
**Current Phase**: 4 (First Bootable Image) — **IN PROGRESS**  
**Next Milestone**: Phase 5 (Physical Hardware Testing) — blocked on green CI + Loki hardware

**Validation legend**
- **Implemented in repo** — code/docs exist locally on `dev`
- **Validated in CI** — GitHub Actions produced and structurally verified artifact
- **Validated on hardware** — tested on physical AYN Loki Zero

---

## Project Goal (Phase 1)

Minimal Arch-based live streaming OS for AYN Loki Zero:

`UEFI → systemd-boot → Linux → Gamescope → minimal launcher`

| In scope | Out of scope (Phase 1) |
|----------|------------------------|
| Moonlight (primary app target) | Dual-boot installer |
| Steam (secondary, future) | Media caching |
| Touchscreen + controller first | Tailscale |
| Live USB — internal Windows/NVMe untouched | Plasma / Phosh / KDE / GNOME |
| | Polished launcher shell |

---

## ✅ Completed

### Phase 1: Hardware Research — COMPLETE
- [x] AYN Loki Zero specs documented (`docs/HARDWARE.md`)
- [x] Upstream Linux support researched
- [x] NEEDS_PHYSICAL_TEST items identified (touchscreen is first-class)

### Phase 2: Architecture — COMPLETE
- [x] ADR-001: Arch Linux base
- [x] Boot flow, service graph, filesystem layout (`docs/ARCHITECTURE.md`)

### Phase 3: Build System — COMPLETE *(implemented in repo; CI not yet green)*
- [x] `scripts/build-image.sh` — pacstrap, rootfs, partitioning, raw `.img`, checksum
- [x] `scripts/diagnostics.sh`, `scripts/streamos-input-test.sh`, `scripts/streamos-storage-status.sh`
- [x] `scripts/validate-image.sh` — structural CI validation
- [x] `.github/workflows/build-image.yml`
- [x] `base/pacman.conf`, `.gitattributes` (LF for shell scripts)
- [x] Internal storage udev guard (`60-streamos-storage.rules`)
- [x] `/etc/streamos-release` written at build time

### Phase 1 Amendment: Touchscreen Readiness — IMPLEMENTED IN REPO
- [x] Mainline HID/I2C-HID modules + libinput in image recipe
- [x] `streamos-input-test` — device/event node, bus/vendor/product, capabilities, multitouch, axis ranges
- [x] Minimal Phase 1 launcher (`launcher/menu.sh` + Gamescope + `wmenu`) — touch/pointer + keyboard/controller arrows
- [x] `wvkbd` **0.14.1** built from pinned upstream source on build host (not an Arch repo package)
- [ ] **Validated on hardware** — all touch items remain NEEDS_PHYSICAL_TEST

---

## ⏳ In Progress

### Phase 4: First Bootable Prototype — IN PROGRESS

**Latest CI status:** ❌ **FAILED** (as of 2026-09-08)

| Run | Commit | Failure |
|-----|--------|---------|
| [34241965895](https://github.com/HowardMoonsFunk/loki-streamos/actions/runs/34241965895) | `887f7d6` | Disk full installing wvkbd build-deps **inside chroot** |

**Fix in progress (local, not yet CI-green):**
- Build wvkbd on CI **host**, not inside chroot (`DESTDIR` into rootfs)
- `truncate` sparse image instead of `dd` zero-fill
- Purge pacman cache in rootfs; delete staging rootfs after copy
- Structural validation via `validate-image.sh`

**Phase 4 tasks**

| Task | Repo | CI | Hardware |
|------|------|----|----------|
| Fix build-image.sh (packages, loopback, systemd-boot) | ✅ | — | — |
| `dev` branch Actions trigger | ✅ | — | — |
| Image builds without fatal errors | ✅ impl | ❌ | — |
| Partitions/filesystems correct | ✅ impl | ❌ | — |
| SHA-256 checksum generated | ✅ impl | ❌ | — |
| Structural validation passes | ✅ impl | ❌ | — |
| Artifact uploaded | — | ❌ | — |
| Image boots on Loki Zero | — | — | ❌ NEEDS_PHYSICAL_TEST |

**Previous CI failures (fixed in repo):**
- invalid `amdgpu-dkms` package
- loopback partition nodes missing in container
- `sudo` in root container
- CRLF line endings breaking `i2c-tools`
- `wvkbd` assumed to be official Arch package
- `arch` command in env step

---

## 📋 Planned (not started)

### Phase 5: Physical Hardware Testing
Blocked on: green CI artifact + physical Loki Zero

### Phase 6: Launcher
**Current reality:** minimal Phase 1 launcher exists (`menu.sh`); polished controller-driven shell remains future work.

### Phase 7: Installer — deferred

---

## 🚨 Blockers

| Blocker | Status |
|---------|--------|
| CI produces bootable `.img` artifact | ❌ Active — disk space / build layout |
| Physical Loki Zero for validation | ⏳ Waiting on artifact |

### Known Unknowns (NEEDS_PHYSICAL_TEST)
1. Panel type and eDP detection
2. Power/volume button ACPI events
3. Wi-Fi chipset (ath11k vs mt7921)
4. Bluetooth chipset/firmware
5. Battery interface (BAT0 vs BAT1)
6. Suspend state (S3 vs S4)
7. Touchscreen driver path (USB HID vs I2C-HID) and 1280×720 orientation

---

## 🎯 Success Criteria (honest)

### Phase 4 — Image Generation
- [ ] CI build passes end-to-end **(not yet)**
- [ ] `.img` artifact uploaded **(not yet)**
- [ ] Checksum verifies **(not yet)**
- [ ] `validate-image.sh` passes in CI **(not yet)**
- [ ] Image boots on Loki Zero **(NEEDS_PHYSICAL_TEST)**

### Phase 5 — Hardware (unchanged — all unchecked until hardware)
- [ ] GPU, controller, Wi-Fi, touchscreen detected
- [ ] Touchscreen events + orientation + post-suspend
- [ ] Gamescope renders; Moonlight connects

### Overall v0.1.0
- [ ] Reproducible CI/CD **(not yet — do not claim)**
- [ ] Boots on Loki Zero **(NEEDS_PHYSICAL_TEST)**

---

## 💾 Repository Structure

```
loki-streamos/
├── .github/workflows/build-image.yml
├── base/pacman.conf
├── launcher/menu.sh              # Phase 1 minimal launcher
├── scripts/
│   ├── build-image.sh
│   ├── validate-image.sh         # CI structural checks
│   ├── diagnostics.sh
│   ├── streamos-input-test.sh
│   └── streamos-storage-status.sh
├── docs/                         # Architecture & testing (reference)
├── STATUS.md                     # This file
└── build-artifacts/              # CI output (gitignored)
```

---

## 🔗 Next Actions

1. Push build fixes → trigger CI
2. Confirm green run: artifact + checksum + `validate-image.sh`
3. Document successful commit SHA and artifact name in this file
4. **Stop** — hand off for physical Loki testing (Phase 5)

**Flash command (after CI green):**
```bash
sudo dd if=loki-streamos-YYYYMMDD.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

---

**Last Updated**: 2026-09-08  
**Maintained By**: Cursor agent (continuing Phase 4 from prior handoff)
