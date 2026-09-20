# Alexandrie als Proxmox-LXC mit Authentik-OIDC

Dieses Repository installiert [Alexandrie](https://github.com/Smaug6739/Alexandrie) als unprivilegierten Debian-13-LXC auf Proxmox VE. Der Stack läuft im LXC mit Docker Compose und besteht aus MySQL, RustFS, Alexandrie-Backend und Alexandrie-Frontend.

Der primäre Zielpfad ist Proxmox VE 9 auf `amd64`. Proxmox VE 8 kann nur ausdrücklich mit `--allow-pve8` freigegeben werden und ist vor dem produktiven Einsatz separat zu testen.

## Installation

Vor dem ersten Release muss in `ct/alexandrie.sh` die Konstante `REPO_RAW_URL` auf das eigene GitHub-Repository und den Release-Tag angepasst werden. Danach wird der Installer vom Proxmox-Host als root gestartet:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Motrish/Alexandrie-Proxmox/v1.0.0/ct/alexandrie.sh)"
```

Das Skript fragt CTID, Rootdir-Storage, Template-Storage, Bridge, Netzwerk, CPU, RAM, Swap und Diskgröße ab. Es erstellt niemals einen vorhandenen Container neu, stoppt ihn nicht und löscht ihn nicht.

Der Standard erzeugt:

| Einstellung | Wert |
|---|---|
| Container | unprivilegiert |
| Betriebssystem | Debian 13 / amd64 |
| CPU | 2 vCPU |
| RAM | 4096 MiB |
| Swap | 512 MiB |
| Root-Disk | 16 GiB |
| LXC-Features | `nesting=1`, `keyctl=1` |
| Startverhalten | on boot |
| Tags | `knowledge;wiki;docker` |

Beispiel für eine nicht-interaktive Installation:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Motrish/Alexandrie-Proxmox/v1.0.0/ct/alexandrie.sh)" -- \
  --ctid 120 --hostname alexandrie --storage local-lvm \
  --template-storage local --bridge vmbr0 --ip dhcp \
  --non-interactive
```

Während der Installation wird die Authentik-Discovery geprüft. Die öffentliche Frontend-URL wird vor der Client-ID abgefragt, damit die exakte Redirect-URI in Authentik angelegt werden kann:

```text
https://<FRONTEND-FQDN>/login/oidc/callback
```

## Authentik konfigurieren

In Authentik wird manuell ein OAuth2/OpenID-Provider vom Typ `Confidential` und eine Anwendung angelegt:

1. Provider und Anwendung mit einem eindeutigen Slug, zum Beispiel `alexandrie`, anlegen.
2. Als Redirect-URI exakt `https://<FRONTEND-FQDN>/login/oidc/callback` eintragen.
3. Die Scopes `openid`, `profile` und `email` freigeben.
4. `preferred_username`, `email`, `given_name` und `family_name` über UserInfo bereitstellen.
5. Discovery-URL, Client-ID und Client-Secret im LXC über `alexandrie-config` hinterlegen.

Der Installer verändert Authentik nicht automatisch und benötigt keinen Authentik-API-Token.

Der Standardmodus ist `staged`: OIDC ist verfügbar, die lokale Anmeldung bleibt als Reparaturpfad aktiviert. Nach einem erfolgreichen OIDC-Test:

```bash
alexandrie-config --enforce-sso
```

Das aktiviert `CONFIG_DISABLE_NATIVE_LOGIN`, blendet das lokale Formular aus und aktiviert den automatischen Redirect. Für Reparaturen:

```bash
alexandrie-config --relax-sso
```

Alexandrie legt OIDC-Benutzer beim ersten erfolgreichen Login an. Die Administratorrolle wird über die interne Alexandrie-ID gesetzt:

```bash
alexandrie-admin list
alexandrie-admin add user@example.org
alexandrie-admin remove user@example.org
```

Das Kommando sucht die eindeutige E-Mail-Adresse in der Tabelle `users`, ändert `ADMIN_ACCOUNTS` atomar und erstellt ausschließlich das Backend neu. Eine Authentik-Gruppen-zu-Rollen-Zuordnung ist nicht Bestandteil dieser Lösung, weil Alexandrie dafür keine dokumentierte Standardkonfiguration bereitstellt.

## Reverse Proxy und DNS

Es werden drei getrennte Proxy Hosts benötigt:

| Öffentliche Adresse | Ziel im LXC |
|---|---|
| `alexandrie.<domain>` | `http://<LXC-IP>:8200` |
| `alexandrie-api.<domain>` | `http://<LXC-IP>:8201` |
| `alexandrie-cdn.<domain>` | `http://<LXC-IP>:9000` |

Für alle drei Hosts TLS aktivieren, HTTP auf HTTPS umleiten und mindestens diese Header durchreichen:

```text
Host              $host
X-Forwarded-For   $proxy_add_x_forwarded_for
X-Forwarded-Proto $scheme
```

MySQL wird nicht veröffentlicht und besitzt keinen Host-Port. Die RustFS-Konsole bleibt deaktiviert. `MINIO_SECURE=false` ist korrekt, weil das Backend RustFS intern über `rustfs:9000` per HTTP erreicht; HTTPS wird am Reverse Proxy für die öffentliche CDN-URL terminiert.

## Verwaltung im LXC

```bash
alexandrie-health              # Status und lokale HTTP-Prüfungen
alexandrie-health --verbose    # zusätzlich maskierte Logs
alexandrie-config              # URL/OIDC-Konfiguration ändern
alexandrie-update               # Backup, Pull, Neustart, Healthcheck
alexandrie-backup               # konsistentes lokales Backup
alexandrie-restore <Backupdir>  # Restore nach Bestätigung RESTORE
```

Die systemd-Unit `alexandrie.service` startet den Compose-Stack nach einem Neustart des LXC automatisch. Alle Verwaltungsoperationen verwenden ein exklusives `flock`-Lock.

### Backups

Ein Backup enthält:

- MySQL-Dump aller Datenbanken inklusive Routinen und Triggern;
- RustFS-Datenarchiv;
- restriktiv geschützte Kopie von `.env` und `compose.yaml`;
- Manifest mit Zeitstempeln, Docker-Version, Image-Digests und Prüfsummen.

Standardmäßig werden sieben Backups im LXC behalten. Vor jedem Update und vor jedem Restore wird automatisch ein Backup erstellt. Zusätzlich wird ein tägliches Proxmox-`vzdump`-Backup des gesamten LXC empfohlen.

Ein Restore stoppt den Stack kontrolliert, prüft zuerst Manifest und Prüfsummen, erstellt ein Sicherheitsbackup und stellt anschließend MySQL und RustFS wieder her. `docker compose down -v` wird nicht verwendet.

## Sicherheit

- `.env`, Backups und Datenbank-Dumps sind root-eigentümergeschützt.
- Secrets werden mit `openssl rand` erzeugt und nicht als Prozessargument übergeben.
- MySQL ist ausschließlich im internen Compose-Netz erreichbar.
- Der Docker-Socket wird nicht in Alexandrie-Container gemountet.
- Es werden keine privilegierten LXC-, Host-Network- oder unnötigen Capabilities verwendet.
- Eine private CA kann über `alexandrie-config` eingebunden werden; die TLS-Prüfung wird nicht global deaktiviert.
- Der Installer lädt den Installer und alle Assets aus derselben Release-URL.

## Entwicklung und Tests

Lokale Prüfungen:

```bash
tests/syntax.sh
tests/render-compose.sh
```

Mit Bats:

```bash
bats tests/test-input-validation.bats
```

Die GitHub-Action `.github/workflows/validate.yml` führt `bash -n`, ShellCheck, shfmt, Compose-Rendering, YAML-Validierung, Bats und Secret-Checks aus.

Vor einer Veröffentlichung auf einem Testnode prüfen:

- DHCP und statische IPv4 mit VLAN;
- Abbruch vor und nach `pct create`;
- PVE-Neustart;
- erster OIDC-Login;
- `staged`, `--enforce-sso` und `--relax-sso`;
- Admin-Zuweisung per E-Mail;
- Update, Backup und Restore;
- fehlerhafte Discovery-URL, private CA und voller Datenträger.

## Quellen

- [Alexandrie Repository](https://github.com/Smaug6739/Alexandrie)
- [Offizielle Alexandrie Compose-Datei](https://github.com/Smaug6739/Alexandrie/blob/main/docker-compose.yml)
- [Alexandrie Deployment-Dokumentation](https://github.com/Smaug6739/Alexandrie/blob/main/docs/README.md)
- [Alexandrie OIDC-Dokumentation](https://github.com/Smaug6739/Alexandrie/blob/main/docs/content/6.deploy/5.oidc-and-ldap.md)
- [Proxmox VE Container Administration](https://pve.proxmox.com/pve-docs/chapter-pct.html)
- [Docker Engine auf Debian](https://docs.docker.com/engine/install/debian/)
- [Authentik OAuth2/OIDC Provider](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
