#!/usr/bin/env bash

# Shared runtime helpers. This file is sourced by the management commands in
# /usr/local/sbin and intentionally contains no code with side effects.

: "${ALEXANDRIE_APP_DIR:=/opt/alexandrie}"
: "${ALEXANDRIE_CONFIG_DIR:=/etc/alexandrie}"
: "${ALEXANDRIE_BACKUP_DIR:=${ALEXANDRIE_APP_DIR}/backups}"
: "${ALEXANDRIE_ENV_FILE:=${ALEXANDRIE_APP_DIR}/.env}"
: "${ALEXANDRIE_COMPOSE_FILE:=${ALEXANDRIE_APP_DIR}/compose.yaml}"
: "${ALEXANDRIE_LOCK_FILE:=/run/lock/alexandrie.lock}"

log_info() {
    printf '[INFO] %s\n' "$*"
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Dieser Befehl muss als root ausgeführt werden.'
}

require_stack_files() {
    [[ -f "$ALEXANDRIE_ENV_FILE" ]] || die "Fehlende Konfiguration: $ALEXANDRIE_ENV_FILE"
    [[ -f "$ALEXANDRIE_COMPOSE_FILE" ]] || die "Fehlende Compose-Datei: $ALEXANDRIE_COMPOSE_FILE"
}

load_env() {
    require_stack_files
    local line key raw value
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || continue
        key=${line%%=*}
        raw=${line#*=}
        [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Ungültiger Schlüssel in .env: $key"
        value=$(decode_dotenv_value "$raw")
        export "$key=$value"
    done < "$ALEXANDRIE_ENV_FILE"
}

decode_dotenv_value() {
    local raw=${1-} out='' char next
    local index=0 length

    if [[ ${raw:0:1} == '"' && ${raw: -1} == '"' && ${#raw} -ge 2 ]]; then
        raw=${raw:1:${#raw}-2}
    fi
    length=${#raw}
    while (( index < length )); do
        char=${raw:index:1}
        if [[ $char == $'\\' && $((index + 1)) -lt $length ]]; then
            next=${raw:index+1:1}
            case $next in
                \\|\") out+=$next; index=$((index + 2)); continue ;;
                n) out+=$'\n'; index=$((index + 2)); continue ;;
            esac
        fi
        if [[ $char == '$' && ${raw:index+1:1} == '$' ]]; then
            out+='$'
            index=$((index + 2))
            continue
        fi
        out+=$char
        index=$((index + 1))
    done
    printf '%s' "$out"
}

dotenv_quote() {
    local value=${1-}

    [[ $value != *$'\n'* ]] || die 'Konfigurationswerte dürfen keine Zeilenumbrüche enthalten.'
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//\$/\$\$}
    printf '"%s"' "$value"
}

set_env_value() {
    local key=$1
    local value=$2
    local file=${3:-$ALEXANDRIE_ENV_FILE}
    local quoted tmp replacement_file

    [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Ungültiger Konfigurationsschlüssel: $key"
    [[ -f $file ]] || die "Konfigurationsdatei fehlt: $file"
    quoted=$(dotenv_quote "$value")
    tmp=$(mktemp "${file}.tmp.XXXXXX")
    replacement_file=$(mktemp "${file}.replacement.XXXXXX")
    chmod 600 "$tmp"
    chmod 600 "$replacement_file"
    printf '%s=%s\n' "$key" "$quoted" > "$replacement_file"
    awk -v key="$key" -v replacement_file="$replacement_file" '
        BEGIN {
            expression = "^[[:space:]]*" key "="
            found = 0
            getline replacement < replacement_file
            close(replacement_file)
        }
        $0 ~ expression { print replacement; found = 1; next }
        { print }
        END { if (!found) print replacement }
    ' "$file" > "$tmp"
    rm -f -- "$replacement_file"
    chown --reference="$file" "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$file"
    chmod 600 "$file"
}

backup_env_file() {
    local stamp backup
    [[ -f $ALEXANDRIE_ENV_FILE ]] || return 0
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup="${ALEXANDRIE_ENV_FILE}.bak.${stamp}"
    install -o root -g root -m 600 "$ALEXANDRIE_ENV_FILE" "$backup"
    log_info "Vorherige Konfiguration gesichert: $backup"
}

compose() {
    docker compose \
        --project-name alexandrie \
        --env-file "$ALEXANDRIE_ENV_FILE" \
        --file "$ALEXANDRIE_COMPOSE_FILE" \
        "$@"
}

compose_config_check() {
    compose config --quiet
}

normalise_public_url() {
    local value=${1-}
    while [[ $value == */ ]]; do
        value=${value%/}
    done
    printf '%s' "$value"
}

validate_public_url() {
    local value
    value=$(normalise_public_url "${1-}")
    [[ $value =~ ^https://[^[:space:]/]+([:/][^[:space:]]*)?$ ]] || return 1
    [[ $value != *'?'* && $value != *'#'* ]] || return 1
}

validate_cookie_domain() {
    local value=${1-}
    [[ $value != *://* && $value != */* && $value != *:* && $value != *[[:space:]]* ]] || return 1
    [[ $value =~ ^\.?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
    [[ $value != .*..* && $value != *..* ]] || return 1
}

validate_ipv4_cidr() {
    local value=${1-} address prefix octet
    local -a octets

    [[ $value == */* ]] || return 1
    address=${value%/*}
    prefix=${value#*/}
    [[ $prefix =~ ^[0-9]+$ && $prefix -le 32 ]] || return 1
    IFS=. read -r -a octets <<< "$address"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        [[ $octet =~ ^[0-9]+$ && $octet -le 255 ]] || return 1
    done
}

validate_email() {
    [[ ${1-} =~ ^[^[:space:]@]+@[^[:space:]@.]+(\.[^[:space:]@.]+)+$ ]]
}

sql_escape_string() {
    local value=${1-}
    value=${value//\\/\\\\}
    value=${value//\'/\'\'}
    printf '%s' "$value"
}

mask_text() {
    local text=${1-} secret
    local -a secrets=()

    for secret in "${MYSQL_ROOT_PASSWORD-}" "${MYSQL_PASSWORD-}" \
        "${RUSTFS_SECRET_KEY-}" "${JWT_SECRET-}" "${OIDC_1_CLIENT_SECRET-}" \
        "${SMTP_PASSWORD-}"; do
        [[ -n $secret ]] && secrets+=("$secret")
    done
    for secret in "${secrets[@]}"; do
        text=${text//"$secret"/'[REDACTED]'}
    done
    printf '%s' "$text"
}

mask_stream() {
    local line
    while IFS= read -r line; do
        mask_text "$line"
        printf '\n'
    done
}

is_stack_running() {
    compose ps --status running --services 2>/dev/null | grep -qx 'frontend'
}

restart_application() {
    compose_config_check
    compose up -d --force-recreate backend frontend >/dev/null
}

container_digest() {
    local container=$1
    docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$container" 2>/dev/null | head -n 1
}

wait_for_http() {
    local url=$1
    local timeout=${2:-180}
    local start now status

    start=$(date +%s)
    while :; do
        status=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 8 "$url" || true)
        if [[ $status =~ ^[23][0-9][0-9]$ ]]; then
            return 0
        fi
        now=$(date +%s)
        (( now - start >= timeout )) && return 1
        sleep 3
    done
}

ensure_lock() {
    install -d -o root -g root -m 755 "$(dirname "$ALEXANDRIE_LOCK_FILE")"
    # shellcheck disable=SC2086
    exec 9>"$ALEXANDRIE_LOCK_FILE"
    flock -n 9 || die 'Ein anderer Alexandrie-Verwaltungsvorgang läuft bereits.'
}
