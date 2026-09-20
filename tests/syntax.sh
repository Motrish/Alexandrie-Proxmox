#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mapfile -t shell_files < <(find "$ROOT_DIR/ct" "$ROOT_DIR/install" "$ROOT_DIR/assets" -type f -print | sort)

for file in "${shell_files[@]}"; do
    bash -n "$file"
done
printf 'bash -n: %s Dateien erfolgreich geprüft.\n' "${#shell_files[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --shell=bash --severity=warning "${shell_files[@]}"
    printf 'shellcheck: erfolgreich.\n'
else
    printf 'shellcheck: lokal nicht installiert; CI führt die Prüfung aus.\n'
fi

if command -v shfmt >/dev/null 2>&1; then
    shfmt -d -i 4 -ci -bn "${shell_files[@]}"
    printf 'shfmt: erfolgreich.\n'
else
    printf 'shfmt: lokal nicht installiert; CI führt die Prüfung aus.\n'
fi
