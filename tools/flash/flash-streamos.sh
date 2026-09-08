#!/usr/bin/env bash
# flash-streamos.sh — safe CLI flasher for Loki StreamOS raw .img artifacts
# Linux and macOS. Does NOT run on the Loki device.
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"
DRY_RUN=0
VERIFY=0
FORCE_NON_REMOVABLE=0
CHECKSUM_FILE=""
IMAGE=""
DEVICE=""
OS="linux"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] IMAGE [DEVICE]

Write a Loki StreamOS raw disk image to a USB drive or SD card.

Options:
  --dry-run                 Inspect and plan only; never write
  --verify                  Extra post-write partition/filesystem checks
  --checksum FILE           SHA-256 sum file (default: IMAGE.sha256)
  --force-non-removable     Allow non-removable targets (never system disk)
  -h, --help                Show this help

Examples:
  $SCRIPT_NAME loki-streamos-20260908.img
  $SCRIPT_NAME --dry-run loki-streamos-20260908.img /dev/sdb
  $SCRIPT_NAME --verify loki-streamos-20260908.img /dev/sdb

Confirmation: type exactly  FLASH <device>  to proceed.
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

detect_os() {
    case "$(uname -s)" in
        Linux) OS="linux" ;;
        Darwin) OS="macos" ;;
        *) die "Unsupported OS: $(uname -s). Use Linux or macOS." ;;
    esac
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --verify) VERIFY=1; shift ;;
            --force-non-removable) FORCE_NON_REMOVABLE=1; shift ;;
            --checksum) CHECKSUM_FILE="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            -*) die "Unknown option: $1" ;;
            *)
                if [[ -z "$IMAGE" ]]; then IMAGE="$1"
                elif [[ -z "$DEVICE" ]]; then DEVICE="$1"
                else die "Too many arguments"
                fi
                shift
                ;;
        esac
    done
    [[ -n "$IMAGE" ]] || { usage; exit 1; }
}

resolve_image() {
    [[ -f "$IMAGE" ]] || die "Image not found: $IMAGE"
    case "$IMAGE" in
        *.img) IMAGE_TYPE="raw" ;;
        *.img.zst)
            IMAGE_TYPE="zst"
            require_cmd zstd
            ;;
        *) die "Unsupported image type (expected .img or .img.zst): $IMAGE" ;;
    esac
}

verify_checksum() {
    local sum_file="${CHECKSUM_FILE:-${IMAGE}.sha256}"
    if [[ -f "$sum_file" ]]; then
        log "Verifying SHA-256 from $sum_file ..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "[dry-run] would verify checksum using $sum_file"
            CHECKSUM_STATUS="VERIFIED (dry-run)"
            return
        fi
        if [[ "$OS" == "macos" ]]; then
            (cd "$(dirname "$sum_file")" && shasum -a 256 -c "$(basename "$sum_file")") \
                || die "SHA-256 verification FAILED"
        else
            (cd "$(dirname "$sum_file")" && sha256sum -c "$(basename "$sum_file")") \
                || die "SHA-256 verification FAILED"
        fi
        CHECKSUM_STATUS="VERIFIED"
    else
        log "WARNING: No checksum file at $sum_file"
        log "The image has NOT been cryptographically verified."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            CHECKSUM_STATUS="SKIPPED (dry-run, no checksum)"
            return
        fi
        read -r -p "Continue without checksum verification? Type YES to proceed: " ans
        [[ "$ans" == "YES" ]] || die "Aborted (no checksum verification)"
        CHECKSUM_STATUS="NOT VERIFIED"
    fi
}

# --- device helpers ---

whole_disk() {
    local dev="$1"
    if [[ "$OS" == "macos" ]]; then
        dev="${dev#/dev/}"
        dev="${dev#r}"   # rdiskN -> diskN
        printf '/dev/%s' "$dev"
        return
    fi
    if [[ "$dev" =~ [0-9]$ ]] && lsblk -ndo PKNAME "$dev" 2>/dev/null | grep -q .; then
        lsblk -ndo PKNAME "$dev"
    else
        printf '%s' "$dev"
    fi
}

is_partition_path() {
    local dev="$1"
    if [[ "$OS" == "macos" ]]; then
        [[ "$dev" =~ disk[0-9]+s[0-9]+$ ]]
        return
    fi
    [[ "$dev" =~ [0-9]+$ ]] && lsblk -ndo PKNAME "$dev" 2>/dev/null | grep -q .
}

protected_system_disks() {
    PROTECTED=()
    if [[ "$OS" == "linux" ]]; then
        local src
        for mp in / /boot /boot/efi; do
            src="$(findmnt -n -o SOURCE --target "$mp" 2>/dev/null || true)"
            [[ -n "$src" ]] || continue
            src="$(whole_disk "$src")"
            PROTECTED+=("$src")
        done
    elif [[ "$OS" == "macos" ]]; then
        local boot
        boot="$(diskutil info / 2>/dev/null | awk -F': *' '/Device Node/{print $2; exit}')"
        [[ -n "$boot" ]] && PROTECTED+=("$(whole_disk "$boot")")
    fi
}

is_protected_disk() {
    local dev="$1"
    local p
    dev="$(whole_disk "$dev")"
    for p in "${PROTECTED[@]}"; do
        [[ "$dev" == "$p" ]] && return 0
    done
    return 1
}

list_candidates_linux() {
    while read -r name model size rm tran type; do
        [[ "$type" == "disk" ]] || continue
        is_protected_disk "$name" && continue
        if [[ "$FORCE_NON_REMOVABLE" -eq 0 && "$rm" != "1" ]]; then continue; fi
        printf '%s  model=%s  size=%s  rm=%s  tran=%s\n' "$name" "$model" "$size" "$rm" "$tran"
    done < <(lsblk -dpno NAME,MODEL,SIZE,RM,TRAN,TYPE 2>/dev/null)
}

list_candidates_macos() {
    diskutil list | awk '/^\/dev\//{print $1}' | while read -r d; do
        is_protected_disk "$d" && continue
        diskutil info "$d" 2>/dev/null | awk -v d="$d" '
            /Device \/ Media Name/ {model=$0}
            /Disk Size/ {size=$0}
            /Removable Media/ {rem=$0}
            END { printf "%s  %s  %s  %s\n", d, model, size, rem }'
    done
}

select_device_interactive() {
    log "Candidate removable disks:"
    if [[ "$OS" == "linux" ]]; then list_candidates_linux
    else list_candidates_macos
    fi
    log ""
    read -r -p "Enter target whole-disk device (e.g. /dev/sdb): " DEVICE
    [[ -n "$DEVICE" ]] || die "No device selected"
}

show_device_info() {
    log ""
    log "STREAMOS FLASH TARGET"
    log ""
    if [[ "$OS" == "linux" ]]; then
        local vendor model serial size rm tran
        vendor="$(udevadm info --query=property --name="$DEVICE" 2>/dev/null | awk -F= '/^ID_VENDOR=/{print $2; exit}')"
        model="$(lsblk -ndo MODEL "$DEVICE" 2>/dev/null | xargs)"
        serial="$(udevadm info --query=property --name="$DEVICE" 2>/dev/null | awk -F= '/^ID_SERIAL=/{print $2; exit}')"
        size="$(lsblk -ndo SIZE "$DEVICE" 2>/dev/null)"
        rm="$(lsblk -ndo RM "$DEVICE" 2>/dev/null)"
        tran="$(lsblk -ndo TRAN "$DEVICE" 2>/dev/null)"
        log "Device:     $DEVICE"
        log "Vendor:     ${vendor:-unknown}"
        log "Model:      ${model:-unknown}"
        log "Serial:     ${serial:-unknown}"
        log "Capacity:   ${size:-unknown}"
        log "Transport:  ${tran:-unknown}"
        log "Removable:  ${rm:-unknown}"
        log ""
        log "Partitions:"
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DEVICE" 2>/dev/null | tail -n +2 || true
    else
        diskutil info "$DEVICE" 2>/dev/null | awk -F': ' '
            /Device Node/{d=$2}
            /Device \/ Media Name/{m=$2}
            /Disk Size/{s=$2}
            /Protocol/{p=$2}
            /Removable Media/{r=$2}
            END {
                print "Device:     " d
                print "Model:      " m
                print "Capacity:   " s
                print "Protocol:   " p
                print "Removable:  " r
            }'
        log ""
        log "Partitions:"
        diskutil list "$DEVICE" 2>/dev/null || true
    fi
    log ""
    log "ALL DATA ON $DEVICE WILL BE DESTROYED."
    log ""
}

validate_target() {
    local input="$1" part rm
    is_partition_path "$input" && die "Whole disk required, not a partition: $input"
    DEVICE="$(whole_disk "$input")"
    if [[ "$OS" == "linux" ]]; then
        [[ -b "$DEVICE" ]] || die "Not a block device: $DEVICE"
    elif [[ ! -e "$DEVICE" ]]; then
        die "Device not found: $DEVICE"
    fi
    is_protected_disk "$DEVICE" && die "Refusing to write system/boot disk: $DEVICE"
    if [[ "$OS" == "linux" ]]; then
        rm="$(lsblk -ndo RM "$DEVICE" 2>/dev/null || echo 0)"
        if [[ "$FORCE_NON_REMOVABLE" -eq 0 && "$rm" != "1" ]]; then
            die "Target is not removable. Use --force-non-removable if you are certain."
        fi
        while read -r part; do
            [[ -z "$part" ]] && continue
            findmnt -rn --source "/dev/$part" >/dev/null 2>&1 &&
                die "Target has mounted partition: /dev/$part"
        done < <(lsblk -ln -o NAME "$DEVICE" | tail -n +2)
    elif [[ "$OS" == "macos" ]]; then
        local internal
        internal="$(diskutil info "$DEVICE" 2>/dev/null | awk -F': *' '/Internal/{print $2; exit}')"
        if [[ "$FORCE_NON_REMOVABLE" -eq 0 && "$internal" == "Yes" ]]; then
            die "Target appears internal. Use --force-non-removable if you are certain."
        fi
    fi
}

confirm_target() {
    local expected="FLASH $DEVICE"
    log "Type exactly:"
    log ""
    log "  $expected"
    log ""
    read -r -p "> " ans
    [[ "$ans" == "$expected" ]] || die "Confirmation mismatch — aborted"
}

unmount_target() {
    log "Unmounting partitions on $DEVICE ..."
    if [[ "$OS" == "linux" ]]; then
        while read -r part; do
            [[ -z "$part" ]] && continue
            findmnt -rn --source "$part" >/dev/null 2>&1 || continue
            log "  umount $part"
            [[ "$DRY_RUN" -eq 1 ]] && continue
            umount "$part" || die "Failed to umount $part"
        done < <(lsblk -ln -o NAME "$DEVICE" | tail -n +2 | sed 's|^|/dev/|')
    else
        [[ "$DRY_RUN" -eq 1 ]] && log "[dry-run] would run: diskutil unmountDisk force $DEVICE" && return
        diskutil unmountDisk force "$DEVICE" || die "diskutil unmountDisk failed"
    fi
}

bmap_path_for_image() {
    case "$IMAGE" in
        *.img.zst) printf '%s' "${IMAGE%.img.zst}.img.bmap" ;;
        *.img)     printf '%s' "${IMAGE}.bmap" ;;
    esac
}

write_image() {
    local bmap write_src="$IMAGE"
    bmap="$(bmap_path_for_image)"

    if [[ -f "$bmap" ]] && command -v bmaptool >/dev/null 2>&1 && [[ "$IMAGE_TYPE" == "raw" ]]; then
        WRITER="bmaptool"
        log "Writing with bmaptool ..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "[dry-run] bmaptool copy --bmap $bmap $IMAGE $DEVICE"
            return
        fi
        bmaptool copy --bmap "$bmap" "$IMAGE" "$DEVICE"
        return
    fi

    WRITER="dd"
    local dd_out="$DEVICE"
    [[ "$OS" == "macos" && "$dd_out" =~ ^/dev/disk ]] && dd_out="/dev/r${dd_out#/dev/}"

    log "Writing with dd ..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$IMAGE_TYPE" == "zst" ]]; then
            log "[dry-run] zstd -dc $IMAGE | dd of=$dd_out bs=16M status=progress conv=fsync"
        else
            log "[dry-run] dd if=$IMAGE of=$dd_out bs=16M status=progress conv=fsync"
        fi
        return
    fi

    if [[ "$IMAGE_TYPE" == "zst" ]]; then
        zstd -dc "$IMAGE" | dd of="$dd_out" bs=16M status=progress conv=fsync
    else
        dd if="$IMAGE" of="$dd_out" bs=16M status=progress conv=fsync
    fi
}

post_write_checks() {
    [[ "$DRY_RUN" -eq 1 ]] && log "[dry-run] would sync and inspect partition table" && return
    sync
    log "Synchronized buffers."
    if [[ "$OS" == "linux" ]]; then
        blockdev --flushbufs "$DEVICE" 2>/dev/null || true
        partprobe "$DEVICE" 2>/dev/null || true
        sleep 2
        log ""
        log "Resulting partition table:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEVICE" 2>/dev/null || true
        if [[ "$VERIFY" -eq 1 ]]; then
            log ""
            log "Verification (partition/filesystem signatures only):"
            while read -r part fst; do
                [[ -z "$part" ]] && continue
                blkid "/dev/$part" 2>/dev/null || true
            done < <(lsblk -ln -o NAME,FSTYPE "$DEVICE" | tail -n +2)
        fi
    else
        diskutil list "$DEVICE" 2>/dev/null || true
    fi
}

print_success() {
    log ""
    log "StreamOS image written successfully."
    log ""
    log "Image:"
    log "  $IMAGE"
    log ""
    log "Target:"
    log "  $DEVICE"
    log ""
    log "SHA-256:"
    log "  $CHECKSUM_STATUS"
    log ""
    log "Writer:"
    log "  ${WRITER:-unknown}"
    log ""
    log "Write completed and buffers synchronized."
    log ""
    log "Safe to remove media."
}

main() {
    detect_os
    parse_args "$@"
    resolve_image
    protected_system_disks

    if [[ "$DRY_RUN" -eq 0 && "$EUID" -ne 0 ]]; then
        die "Root privileges required. Re-run with sudo."
    fi

    if [[ "$OS" == "linux" ]]; then
        require_cmd lsblk
        require_cmd findmnt
        require_cmd sync
        command -v sha256sum >/dev/null || die "Required command not found: sha256sum"
    else
        require_cmd diskutil
        require_cmd shasum
        require_cmd sync
    fi

    [[ -n "$DEVICE" ]] || select_device_interactive
    validate_target "$DEVICE"
    show_device_info
    verify_checksum

    if [[ "$DRY_RUN" -eq 0 ]]; then
        confirm_target
    fi

    unmount_target
    write_image
    post_write_checks
    [[ "$DRY_RUN" -eq 1 ]] && log "[dry-run] complete — no changes made" && exit 0
    print_success
}

main "$@"
