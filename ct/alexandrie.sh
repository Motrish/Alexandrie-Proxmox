#!/usr/bin/env bash
set -Eeuo pipefail

# Alexandrie Proxmox LXC installer
#
# Keep REPO_RAW_URL on the release tag. The host wrapper and every asset that
# it downloads must come from the same tag; this prevents a mixed release.
REPO_RAW_URL="${ALEXANDRIE_REPO_RAW_URL:-https://raw.githubusercontent.com/OWNER/REPOSITORY/v1.0.0}"

TAGS='knowledge;wiki;docker'
CTID=''
HOSTNAME='alexandrie'
STORAGE=''
TEMPLATE_STORAGE=''
BRIDGE='vmbr0'
VLAN=''
IPV4='dhcp'
GATEWAY=''
DNS=''
CORES='2'
MEMORY='4096'
SWAP='512'
DISK='16'
ONBOOT='1'
ALLOW_PVE8='0'
NONINTERACTIVE='0'
DRY_RUN='0'
CT_CREATED='0'
INSTALLER_TMP=''
PHASE='initialization'

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_BLUE=$'\033[1;34m'
else
    C_RESET=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_BLUE=''
fi

log_info() { printf '%s[INFO]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_step() { printf '\n%s== %s ==%s\n' "$C_BLUE" "$*" "$C_RESET"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

cleanup() {
    [[ -n $INSTALLER_TMP && -f $INSTALLER_TMP ]] && rm -f -- "$INSTALLER_TMP"
}
trap cleanup EXIT

rollback_prompt() {
    [[ $CT_CREATED == 1 ]] || return 0
    log_error "Der neue LXC $CTID wurde erstellt, die Installation ist jedoch fehlgeschlagen."
    if [[ $NONINTERACTIVE == 1 ]]; then
        log_warn 'Nicht-interaktiver Modus: Container bleibt zur Diagnose erhalten.'
        return 0
    fi
    local answer
    read -r -p 'Fehlerhaften LXC zur Diagnose behalten? [J/n] ' answer
    if [[ ${answer,,} == n || ${answer,,} == nein ]]; then
        log_info "Entferne ausschließlich den in diesem Lauf erstellten CT $CTID."
        pct stop "$CTID" >/dev/null 2>&1 || true
        pct destroy "$CTID" --purge 1
    else
        log_info "Container $CTID bleibt erhalten."
    fi
}

on_error() {
    local exit_code=$?
    trap - ERR
    log_error "Phase '$PHASE' ist fehlgeschlagen (Zeile $1)."
    rollback_prompt
    exit "$exit_code"
}
trap 'on_error "$LINENO"' ERR

usage() {
    cat <<'EOF'
Alexandrie als unprivilegierten Debian-13-LXC installieren.

Optionen:
  --ctid ID                 Feste, noch freie Container-ID
  --hostname NAME          Hostname (Standard: alexandrie)
  --storage NAME           Rootdir-Storage
  --template-storage NAME  Storage für Debian-13-Templates
  --bridge NAME            Netzwerk-Bridge (Standard: vmbr0)
  --vlan ID                 VLAN-Tag
  --ip dhcp|CIDR           IPv4-Konfiguration (Standard: dhcp)
  --gateway IPv4           Gateway bei statischer IPv4
  --dns SERVER[,SERVER]    DNS-Server
  --cores N                vCPU (Standard: 2)
  --memory MiB             RAM (Standard: 4096)
  --swap MiB               Swap (Standard: 512)
  --disk GiB               Root-Disk (Standard: 16)
  --allow-pve8             PVE 8 ausdrücklich zulassen
  --non-interactive        Nur Werte/Defaults verwenden
  --dry-run                Nur Prüfungen durchführen
  -h, --help               Hilfe anzeigen

Die Release-URL kann über ALEXANDRIE_REPO_RAW_URL überschrieben werden.
EOF
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || { log_error "Benötigter Befehl fehlt: $1"; return 1; }
}

prompt_value() {
    local label=$1 default_value=${2-} value
    if [[ $NONINTERACTIVE == 1 ]]; then
        REPLY=$default_value
        return
    fi
    read -r -p "$label${default_value:+ [$default_value]}: " value
    REPLY=${value:-$default_value}
}

valid_ipv4() {
    local address=$1 octet
    local -a values
    IFS=. read -r -a values <<< "$address"
    [[ ${#values[@]} -eq 4 ]] || return 1
    for octet in "${values[@]}"; do
        [[ $octet =~ ^[0-9]+$ && $octet -le 255 ]] || return 1
    done
}

valid_ipv4_cidr() {
    local value=$1 address prefix
    [[ $value == */* ]] || return 1
    address=${value%/*}
    prefix=${value#*/}
    [[ $prefix =~ ^[0-9]+$ && $prefix -le 32 ]] || return 1
    valid_ipv4 "$address"
}

validate_numeric_options() {
    [[ $CTID =~ ^[0-9]+$ && $CTID -ge 100 && $CTID -le 999999999 ]] || { log_error 'CTID muss zwischen 100 und 999999999 liegen.'; return 1; }
    [[ $CORES =~ ^[1-9][0-9]*$ ]] || { log_error 'CPU-Anzahl ist ungültig.'; return 1; }
    [[ $MEMORY =~ ^[1-9][0-9]*$ ]] || { log_error 'RAM-Größe ist ungültig.'; return 1; }
    [[ $SWAP =~ ^[0-9]+$ ]] || { log_error 'Swap-Größe ist ungültig.'; return 1; }
    [[ $DISK =~ ^[1-9][0-9]*$ ]] || { log_error 'Disk-Größe ist ungültig.'; return 1; }
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ctid) CTID=$2; shift 2 ;;
            --hostname) HOSTNAME=$2; shift 2 ;;
            --storage) STORAGE=$2; shift 2 ;;
            --template-storage) TEMPLATE_STORAGE=$2; shift 2 ;;
            --bridge) BRIDGE=$2; shift 2 ;;
            --vlan) VLAN=$2; shift 2 ;;
            --ip) IPV4=$2; shift 2 ;;
            --gateway) GATEWAY=$2; shift 2 ;;
            --dns) DNS=$2; shift 2 ;;
            --cores) CORES=$2; shift 2 ;;
            --memory) MEMORY=$2; shift 2 ;;
            --swap) SWAP=$2; shift 2 ;;
            --disk) DISK=$2; shift 2 ;;
            --allow-pve8) ALLOW_PVE8='1'; shift ;;
            --non-interactive) NONINTERACTIVE='1'; shift ;;
            --dry-run) DRY_RUN='1'; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unbekannte Option: $1"; usage >&2; return 2 ;;
        esac
    done
}

check_host() {
    local pve_version architecture
    [[ ${EUID:-$(id -u)} -eq 0 ]] || { log_error 'Das Skript muss direkt als root auf einem Proxmox-VE-Node laufen.'; return 1; }
    [[ -d /etc/pve ]] && command -v pct >/dev/null 2>&1 && command -v pveam >/dev/null 2>&1 && \
        command -v pvesm >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || {
        log_error 'Proxmox-VE-Werkzeuge wurden nicht gefunden.'
        return 1
    }
    architecture=$(dpkg --print-architecture 2>/dev/null || true)
    [[ $architecture == amd64 ]] || { log_error "Architektur $architecture ist nicht freigegeben; erwartet wird amd64."; return 1; }
    pve_version=$(pveversion 2>/dev/null | sed -n 's/.*pve-manager\/\([0-9][0-9]*\)\..*/\1/p' | head -n 1)
    [[ $pve_version == 9 ]] || {
        if [[ $pve_version == 8 && $ALLOW_PVE8 == 1 ]]; then
            log_warn 'PVE 8 wurde ausdrücklich freigegeben, ist aber nicht der primäre Testpfad.'
        else
            log_error "PVE-Version ${pve_version:-unbekannt} nicht freigegeben. Primärziel ist PVE 9; für PVE 8 --allow-pve8 verwenden."
            return 1
        fi
    }
    [[ $REPO_RAW_URL == https://raw.githubusercontent.com/* ]] || {
        log_error 'REPO_RAW_URL muss auf raw.githubusercontent.com zeigen.'
        return 1
    }
    [[ $REPO_RAW_URL != *OWNER* && $REPO_RAW_URL != *REPOSITORY* ]] || {
        log_error 'REPO_RAW_URL im Release-Skript wurde noch nicht auf das GitHub-Repository angepasst.'
        return 1
    }
}

find_free_ctid() {
    local candidate
    if command -v pvesh >/dev/null 2>&1; then
        candidate=$(pvesh get /cluster/nextid 2>/dev/null | tr -d '[:space:]' || true)
        if [[ $candidate =~ ^[0-9]+$ ]] && ! pct config "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    fi
    for candidate in $(seq 100 999); do
        if ! pct config "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

choose_storage() {
    local content=$1 selected=$2 first
    first=$(pvesm status --content "$content" 2>/dev/null | awk 'NR > 1 && $3 == "active" { print $1; exit }')
    [[ -n $first ]] || { log_error "Kein aktiver Storage mit Content '$content' gefunden."; return 1; }
    if [[ -n $selected ]]; then
        pvesm status --content "$content" 2>/dev/null | awk -v name="$selected" 'NR > 1 && $1 == name && $3 == "active" { found=1 } END { exit !found }' || {
            log_error "Storage '$selected' ist nicht aktiv oder unterstützt '$content' nicht."
            return 1
        }
        REPLY=$selected
        return 0
    fi
    if [[ $NONINTERACTIVE == 1 ]]; then
        REPLY=$first
        return 0
    fi
    printf 'Aktive Storages für %s:\n' "$content"
    pvesm status --content "$content" | awk 'NR > 1 && $3 == "active" { print "  " $1 " (" $2 ")" }'
    prompt_value "Storage für $content" "$first"
    pvesm status --content "$content" 2>/dev/null | awk -v name="$REPLY" 'NR > 1 && $1 == name && $3 == "active" { found=1 } END { exit !found }' || {
        log_error "Ungültige Storage-Auswahl: $REPLY"
        return 1
    }
}

ensure_template() {
    local existing available
    existing=$(pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk '$0 ~ /debian-13-standard.*amd64/ { print $1 }' | tail -n 1 || true)
    if [[ -n $existing ]]; then
        TEMPLATE=$existing
        log_info "Verwende vorhandenes Debian-13-Template: $TEMPLATE"
        return 0
    fi
    available=$(pveam available --section system 2>/dev/null | awk '$2 ~ /^debian-13-standard_.*_amd64\.tar\.(zst|gz|xz)$/ { print $2 }' | sort -V | tail -n 1)
    [[ -n $available ]] || { log_error 'Kein Debian-13-amd64-Template verfügbar.'; return 1; }
    log_info "Lade Debian-13-Template $available nach $TEMPLATE_STORAGE."
    pveam download "$TEMPLATE_STORAGE" "$available"
    TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$available"
}

check_storage_space() {
    local line available required
    line=$(pvesm status --content rootdir --bytes 2>/dev/null | awk -v name="$STORAGE" '$1 == name { print $6; exit }' || true)
    required=$((DISK * 1024 * 1024 * 1024))
    if [[ $line =~ ^[0-9]+$ ]]; then
        (( line >= required )) || { log_error "Zu wenig freier Speicher auf $STORAGE (verfügbar: $line Bytes, benötigt: mindestens $required Bytes)."; return 1; }
    else
        log_warn "Freier Speicher von $STORAGE konnte nicht maschinenlesbar geprüft werden; pct create übernimmt die abschließende Prüfung."
    fi
}

configure_network() {
    local mode
    if [[ $NONINTERACTIVE == 1 ]]; then
        [[ $IPV4 == dhcp || $IPV4 == */* ]] || { log_error 'Im nicht-interaktiven Modus muss --ip dhcp oder ein CIDR angegeben werden.'; return 1; }
    else
        prompt_value 'Netzwerkmodus (dhcp/static)' "$([[ $IPV4 == dhcp ]] && printf dhcp || printf static)"
        mode=${REPLY,,}
        if [[ $mode == dhcp ]]; then
            IPV4='dhcp'
            GATEWAY=''
        else
            prompt_value 'Statische IPv4 mit Präfix' "${IPV4#static:}"
            IPV4=$REPLY
            prompt_value 'Gateway' "$GATEWAY"
            GATEWAY=$REPLY
        fi
    fi
    if [[ $IPV4 != dhcp ]]; then
        valid_ipv4_cidr "$IPV4" || { log_error 'Ungültige IPv4-CIDR-Angabe.'; return 1; }
        valid_ipv4 "$GATEWAY" || { log_error 'Ungültige Gateway-Adresse.'; return 1; }
    fi
    if [[ -z $DNS ]]; then DNS='1.1.1.1'; fi
    [[ $DNS =~ ^[0-9.]+(,[0-9.]+)*$ ]] || { log_error 'DNS muss eine durch Komma getrennte IPv4-Liste sein.'; return 1; }
}

check_network_host() {
    ip link show "$BRIDGE" >/dev/null 2>&1 || { log_error "Netzwerk-Bridge nicht gefunden: $BRIDGE"; return 1; }
    if [[ -n $VLAN ]]; then
        [[ $VLAN =~ ^[1-9][0-9]{0,3}$ && $VLAN -le 4094 ]] || { log_error 'VLAN-Tag muss zwischen 1 und 4094 liegen.'; return 1; }
    fi
}

build_net0() {
    local network="name=eth0,bridge=$BRIDGE,ip=$IPV4,ip6=auto,firewall=1"
    [[ -n $VLAN ]] && network+=",tag=$VLAN"
    printf '%s' "$network"
}

prepare_defaults() {
    [[ -n $CTID ]] || CTID=$(find_free_ctid)
    choose_storage rootdir "$STORAGE"
    STORAGE=$REPLY
    choose_storage vztmpl "$TEMPLATE_STORAGE"
    TEMPLATE_STORAGE=$REPLY
    if [[ $NONINTERACTIVE != 1 ]]; then
        prompt_value 'Hostname' "$HOSTNAME"; HOSTNAME=$REPLY
        prompt_value 'vCPU' "$CORES"; CORES=$REPLY
        prompt_value 'RAM MiB' "$MEMORY"; MEMORY=$REPLY
        prompt_value 'Swap MiB' "$SWAP"; SWAP=$REPLY
        prompt_value 'Root-Disk GiB' "$DISK"; DISK=$REPLY
    fi
    configure_network
    validate_numeric_options
    [[ $HOSTNAME =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || { log_error 'Hostname ist ungültig.'; return 1; }
    check_network_host
    check_storage_space
}

install_container() {
    local net0 installer_url
    net0=$(build_net0)
    installer_url="$REPO_RAW_URL/install/alexandrie-install.sh"
    INSTALLER_TMP=$(mktemp)
    log_info "Lade Installer aus dem Release: $installer_url"
    curl --fail --silent --show-error --location --connect-timeout 15 --max-time 120 \
        "$installer_url" -o "$INSTALLER_TMP"
    chmod 700 "$INSTALLER_TMP"
    pct push "$CTID" "$INSTALLER_TMP" /root/alexandrie-install.sh --perms 0700
    pct start "$CTID"
    for _ in $(seq 1 30); do
        pct exec "$CTID" -- true >/dev/null 2>&1 && break
        sleep 2
    done
    pct exec "$CTID" -- env \
        ALEXANDRIE_ASSET_BASE_URL="$REPO_RAW_URL" \
        ALEXANDRIE_RELEASE_VERSION="${REPO_RAW_URL##*/}" \
        bash /root/alexandrie-install.sh
    pct exec "$CTID" -- rm -f /root/alexandrie-install.sh
    pct set "$CTID" --onboot 1 >/dev/null
}

create_container() {
    local net0
    net0=$(build_net0)
    if [[ $DRY_RUN == 1 ]]; then
        log_info 'Dry-Run: kein LXC wird erstellt.'
        printf 'pct create %s %s --hostname %s --cores %s --memory %s --swap %s --rootfs %s:%sG --net0 %s\n' \
            "$CTID" "$TEMPLATE" "$HOSTNAME" "$CORES" "$MEMORY" "$SWAP" "$STORAGE" "$DISK" "$net0"
        return 0
    fi
    ! pct config "$CTID" >/dev/null 2>&1 || { log_error "CTID $CTID existiert bereits; nichts wird überschrieben."; return 1; }
    pct create "$CTID" "$TEMPLATE" \
        --hostname "$HOSTNAME" \
        --ostype debian \
        --arch amd64 \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --cores "$CORES" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --rootfs "$STORAGE:${DISK}G" \
        --net0 "$net0" \
        --onboot "$ONBOOT" \
        --tags "$TAGS" \
        --nameserver "${DNS//, /,}" \
        --description 'Alexandrie: offline-first knowledge platform with Authentik OIDC'
    CT_CREATED='1'
}

main() {
    parse_args "$@"
    PHASE='host validation'
    check_host
    PHASE='interactive/default configuration'
    prepare_defaults
    PHASE='Debian template validation/download'
    ensure_template
    PHASE='LXC creation'
    create_container
    [[ $DRY_RUN == 1 ]] && return 0
    PHASE='Alexandrie installation inside LXC'
    install_container
    log_info "Alexandrie wurde in CT $CTID installiert."
}

main "$@"
