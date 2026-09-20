#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for asset in compose.yaml lib.sh alexandrie-config alexandrie-update alexandrie-backup alexandrie-restore alexandrie-admin alexandrie-health alexandrie.service; do
    [[ -f "$ROOT_DIR/assets/alexandrie/$asset" ]] || { printf 'Fehlendes Asset: %s\n' "$asset" >&2; exit 1; }
done
grep -q 'ALEXANDRIE_ASSET_BASE_URL="\$REPO_RAW_URL"' "$ROOT_DIR/ct/alexandrie.sh"
grep -Fq -- '--rootfs "$STORAGE:$DISK"' "$ROOT_DIR/ct/alexandrie.sh"
! grep -Fq -- '--rootfs "$STORAGE:${DISK}G"' "$ROOT_DIR/ct/alexandrie.sh"
! grep -Fq -- '--rootfs %s:%sG' "$ROOT_DIR/ct/alexandrie.sh"
grep -q 'ALEXANDRIE_ASSET_BASE_URL' "$ROOT_DIR/install/alexandrie-install.sh"
printf 'Release-Assets: erfolgreich geprüft.\n'
