# Changelog

## [1.0.0] - 2026-09-19

### Added

- eigenständiger Proxmox-VE-Host-Wrapper für unprivilegierte Debian-13-LXCs;
- Docker-Compose-Stack mit MySQL, RustFS, Alexandrie-Backend und Frontend;
- interaktiver Authentik-OIDC-Konfigurator mit Discovery- und CA-Prüfung;
- staged/strict SSO-Modus mit Reparaturpfad;
- `alexandrie-admin`, `alexandrie-update`, `alexandrie-backup`, `alexandrie-restore` und `alexandrie-health`;
- atomare Konfigurationsänderungen, Locking und systemd-Startintegration;
- GitHub-Action für Syntax-, ShellCheck-, shfmt-, Compose-, YAML- und Bats-Tests.

### Fixed

- Proxmox-Rootfs-Größe ohne `G`-Suffix an `pct create` übergeben; Directory- und LVM-Thin-Storages akzeptieren hier die Form `storage:size`.
