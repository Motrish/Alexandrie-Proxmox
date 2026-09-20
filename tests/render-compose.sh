#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/assets/alexandrie/compose.yaml"
temporary_env=$(mktemp)
trap 'rm -f -- "$temporary_env"' EXIT

cat > "$temporary_env" <<'EOF'
FRONTEND_URL=https://alexandrie.example.org
API_URL=https://alexandrie-api.example.org
CDN_URL=https://alexandrie-cdn.example.org
CDN_ENDPOINT=/alexandrie/
MINIO_PUBLIC_URL=https://alexandrie-cdn.example.org
COOKIE_DOMAIN=example.org
ALLOW_UNSECURE=false
CONFIG_DISABLE_LANDING=false
CONFIG_DISABLE_SIGNUP=false
CONFIG_DISABLE_NATIVE_LOGIN=false
CONFIG_HIDE_NATIVE_LOGIN=false
CONFIG_HIDE_NATIVE_LOGIN_FORM=false
CONFIG_OIDC_PROVIDER_AUTO_REDIRECT=
ADMIN_ACCOUNTS=
MYSQL_IMAGE=mysql:8.0
MYSQL_DATABASE=alexandrie
MYSQL_USER=alexandrie
MYSQL_PASSWORD="synthetic$$mysql# password"
MYSQL_ROOT_PASSWORD="synthetic$$root# password"
RUSTFS_IMAGE=rustfs/rustfs:latest
RUSTFS_ACCESS_KEY=synthetic-access
RUSTFS_SECRET_KEY=synthetic-rustfs-secret
RUSTFS_CONSOLE_ENABLE=false
RUSTFS_LOG_LEVEL=info
MINIO_BUCKET=alexandrie
MINIO_SECURE=false
MINIO_INSECURE_TLS=false
ALEXANDRIE_BACKEND_IMAGE=ghcr.io/smaug6739/alexandrie-backend:latest
ALEXANDRIE_FRONTEND_IMAGE=ghcr.io/smaug6739/alexandrie-frontend:latest
FRONTEND_BIND=0.0.0.0
BACKEND_BIND=0.0.0.0
RUSTFS_BIND=0.0.0.0
SMTP_HOST=
SMTP_MAIL=
SMTP_MAIL_FROM=
SMTP_PASSWORD=
OIDC_1_CONFIG_URL=https://auth.example.org/application/o/alexandrie/.well-known/openid-configuration
OIDC_1_CLIENT_ID=synthetic-client
OIDC_1_CLIENT_SECRET="synthetic$$client# secret"
OIDC_1_PROVIDER_NAME=Authentik
EOF

if ! command -v docker >/dev/null 2>&1; then
    printf 'docker compose: lokal nicht installiert; CI führt den Render-Test aus.\n'
    exit 0
fi

docker compose --env-file "$temporary_env" --file "$COMPOSE_FILE" config --quiet

if grep -nE '3306:3306|down[[:space:]]+-v' "$COMPOSE_FILE"; then
    printf 'Compose-Sicherheitsprüfung fehlgeschlagen.\n' >&2
    exit 1
fi
printf 'docker compose config: erfolgreich.\n'
