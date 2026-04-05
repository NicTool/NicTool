#!/bin/bash
set -e

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"

if [ -f "$ENV_FILE" ]; then
    echo ".env already exists, not overwriting." >&2
    exit 0
fi

DB_ROOT_PW=$(openssl rand -base64 24)
NT_DB_PW=$(openssl rand -base64 24)
NT_ROOT_PW=$(openssl rand -base64 24)

cat > "$ENV_FILE" <<EOF
DB_ROOT_PASSWORD=$DB_ROOT_PW
NICTOOL_DB_NAME=nictool
NICTOOL_DB_USER=nictool
NICTOOL_DB_USER_PASSWORD=$NT_DB_PW
ROOT_USER_EMAIL=admin@example.com
ROOT_USER_PASSWORD=$NT_ROOT_PW
EOF

echo "Generated $ENV_FILE with random passwords."
