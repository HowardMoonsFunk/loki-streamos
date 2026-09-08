#!/usr/bin/env bash
# Non-destructive dry-run tests for flash-streamos.sh (Linux only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLASH="$ROOT/flash-streamos.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

run_test() {
    local name="$1"; shift
    printf 'TEST %s ... ' "$name"
    if "$@" >/dev/null 2>&1; then
        echo PASS; pass=$((pass+1))
    else
        echo FAIL; fail=$((fail+1))
    fi
}

[[ -x "$FLASH" ]] || chmod +x "$FLASH"

# Minimal fake image + checksum
echo 'test' > "$TMP/fake.img"
sha256sum "$TMP/fake.img" > "$TMP/fake.img.sha256"

# Loopback "disk"
truncate -s 32M "$TMP/loop.img"
losetup -fP --show "$TMP/loop.img" > "$TMP/loopdev"
LOOP="$(cat "$TMP/loopdev")"
parted -s "$LOOP" mklabel gpt
partx -a "$LOOP" 2>/dev/null || true

run_test "help" "$FLASH" --help
run_test "dry-run-with-checksum" "$FLASH" --dry-run --force-non-removable "$TMP/fake.img" "$LOOP"
run_test "reject-partition" bash -c "! $FLASH --dry-run --force-non-removable $TMP/fake.img ${LOOP}p1 2>/dev/null"

losetup -d "$LOOP" 2>/dev/null || true

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
