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
start_line=$(grep -n -F 'pct start "$CTID"' "$ROOT_DIR/ct/alexandrie.sh" | cut -d: -f1)
push_line=$(grep -n -F 'pct push "$CTID"' "$ROOT_DIR/ct/alexandrie.sh" | cut -d: -f1)
(( start_line < push_line ))
bootstrap_line=$(grep -n -F 'apt-get install --yes ca-certificates curl' "$ROOT_DIR/install/alexandrie-install.sh" | cut -d: -f1)
network_check_line=$(grep -n -F 'check_network' "$ROOT_DIR/install/alexandrie-install.sh" | tail -n 1 | cut -d: -f1)
(( bootstrap_line < network_check_line ))
grep -q 'ALEXANDRIE_ASSET_BASE_URL' "$ROOT_DIR/install/alexandrie-install.sh"
printf 'Release-Assets: erfolgreich geprüft.\n'
