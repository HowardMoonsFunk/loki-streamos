# ADR-001: Base Operating System Selection

## Decision
**Chosen**: Arch Linux (custom build for Loki Zero)

## Context
Loki StreamOS needs a minimal, maintainable base that:
1. Keeps system RAM footprint <1 GB post-boot
2. Provides current GPU drivers (Mesa, AMDGPU)
3. Avoids unnecessary background services
4. Allows hardware-specific customization without forking a distro

Candidates evaluated:
- **Arch Linux**: Rolling, minimal, package-first
- **Fedora Minimal**: Stable, enterprise-backed, similar minimalism
- **Alpine Linux**: Extremely minimal, but musl libc breaks some gaming libraries
- **Gentoo**: Too complex for appliance use

## Decision Rationale

### Why Arch?
1. **GPU Driver Currency**: Arch packages Mesa within days of release. Vega hardware decode fixes get deployed quickly.
2. **Minimal by Default**: Base install is ~800 MB, pacman is lightweight, no systemd overhead we don't use.
3. **AUR Access**: Moonlight AppImage, specialized audio tools, Loki-specific udev rules can be sourced/packaged.
4. **Rolling Updates**: Critical for appliance (GPU driver fixes ship without waiting for release cycles).
5. **Reproducibility**: pacman.conf pinning + makepkg ensures builds are repeatable.
6. **Precedent**: ChimeraOS and similar projects use Arch-based systems successfully.

### Why Not Fedora?
- Fedora Minimal is ~400 MB larger than Arch
- Release cycle (every 6 months) delays GPU driver backports
- Less flexible for appliance customization
- DNF is heavier than pacman for CI/cloud builds

### Why Not Alpine?
- musl libc incompatibility with Steam Runtime, Moonlight
- Fewer gaming-relevant packages
- Not worth the complexity for 100 MB savings

## Implementation

### Bootstrap Method
1. Use `archiso` to create custom live ISO
2. Bootstrap minimal Arch in CI environment
3. Install only:
   - systemd (init)
   - linux (6.1+ LTS kernel)
   - amdgpu drivers + Mesa
   - NetworkManager or iwd (Wi-Fi)
   - Gamescope
   - Moonlight (via AppImage or AUR)
   - Custom launcher (minimal Wayland app)
4. Strip: documentation, locale files, unused firmware
5. Generate raw disk image (.img)

### Package Strategy
```
# Core system (~300 MB)
base base-devel linux linux-headers

# GPU/Display (~200 MB)
mesa amdgpu-dkms vulkan-radeon

# Networking
networkmanager iwd wpa_supplicant

# Audio
pipewire pipewire-alsa pipewire-pulse

# Gaming/Streaming
gamescope moonlight-qt (or AppImage)

# System tools
systemd-boot systemd-logind

# Development only (removed for final image)
git vim base-devel
```

### Minimal Kernel Config
Build custom kernel or use Arch's `linux-zen` with minimal modules:
- Disable: SCSI, FC, Infiniband, IB support (not on Loki)
- Enable: AMDGPU, GPU scheduler, VAAPI, hwmon
- Result: ~6-8 MB compressed kernel

## Risks & Mitigation

| Risk | Mitigation |
|------|---|
| Rolling updates break streaming | Test before release; pin kernel/Mesa versions if needed |
| AUR package quality | Maintain our own PKGBUILD for critical packages (Moonlight) |
| Arch support lifecycle | Choose 6.1 LTS kernel (supported until 2026) |

## Alternatives Reconsidered

### NixOS
- **Pro**: Declarative, reproducible
- **Con**: Learning curve, overkill for single-device appliance
- **Decision**: Rejected for initial MVP

### Buildroot
- **Pro**: Extreme minimalism
- **Con**: Requires compiling everything; slow CI builds
- **Decision**: Rejected; we want binary packages for iteration speed

## Consequences

1. ✅ Fast builds in CI (binary packages vs. compilation)
2. ✅ Easy GPU driver updates (Mesa hotfixes ship in days)
3. ✅ Access to gaming-focused packages (Steam Runtime, Proton)
4. ⚠️ Must monitor Arch breaking changes (rare, but possible)
5. ⚠️ No LTS support commitment (community-driven)

## Approval
- **Proposed**: 2024-09-08
- **Status**: Approved (initial implementation)
- **Revisit**: If Fedora Minimal GPU driver lag becomes problematic

---

## Next ADR: Boot Flow & Systemd Units

We'll define:
- UEFI → systemd-boot → Linux
- Target: multi-user (no graphical.target overhead)
- Gamescope as display server
- Launcher as primary user-facing service
