# Flash StreamOS — CLI image writer

Write a Loki StreamOS raw `.img` to USB/SD without Rufus or Etcher.

**Status:** IMPLEMENTED · TESTED WITH LOOPBACK (dry-run) · NEEDS_PHYSICAL_TEST (real removable media)

## Linux / macOS

```bash
chmod +x tools/flash/flash-streamos.sh

# Interactive device selection
./tools/flash/flash-streamos.sh loki-streamos-20260908.img

# Explicit device
./tools/flash/flash-streamos.sh loki-streamos-20260908.img /dev/sdb

# Plan only (no writes)
./tools/flash/flash-streamos.sh --dry-run loki-streamos-20260908.img /dev/sdb
```

Place `loki-streamos-20260908.img.sha256` beside the image for automatic verification.

Optional: `loki-streamos-20260908.img.bmap` — uses `bmaptool copy` when installed.

Confirmation requires typing exactly: `FLASH /dev/sdb`

## Windows (Administrator PowerShell)

```powershell
.\tools\flash\flash-streamos.ps1 -Image .\loki-streamos-20260908.img

.\tools\flash\flash-streamos.ps1 -Image .\loki-streamos-20260908.img -Disk 3 -DryRun
```

Confirmation requires typing exactly: `FLASH DISK 3`

Windows writes via native `\\.\PhysicalDiskN` streaming (no downloaded tools). Administrator required.

## Safety

- Never guesses the target disk
- Refuses system/boot/root disks (no override)
- `--force-non-removable` allows internal-looking targets except system disk
- Unmounts target partitions before writing
- `sync` + partition re-read after write

## Options

| Flag | Shell | PowerShell |
|------|-------|------------|
| Dry run | `--dry-run` | `-DryRun` |
| Extra checks | `--verify` | `-Verify` |
| Non-removable OK | `--force-non-removable` | `-ForceNonRemovable` |
| Checksum file | `--checksum FILE` | `-Checksum FILE` |

## Tests (non-destructive)

```bash
./tools/flash/tests/run-dry-run-tests.sh
```

Uses loopback files only — never touches host disks.

## Future artifact names

CI may adopt:

```
loki-streamos-live-v<VERSION>.img
loki-streamos-live-v<VERSION>.img.sha256
loki-streamos-live-v<VERSION>.bmap
```

Current Phase 4 artifacts use `loki-streamos-YYYYMMDD.img` — this tool accepts both.
