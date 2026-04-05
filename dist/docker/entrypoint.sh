#!/bin/bash
set -e

NT_DIR="${NT_DIR:-/usr/local/nictool}"

echo "==> Running NicTool setup"
"$NT_DIR/dist/setup/install-nictool.sh" --nt-dir="$NT_DIR"

echo "==> Waiting for database"
for attempt in $(seq 1 30); do
    if mysqladmin ping -h "${DB_HOSTNAME:-127.0.0.1}" -u "${NICTOOL_DB_USER}" --password="${NICTOOL_DB_USER_PASSWORD}" --silent 2>/dev/null; then
        echo "    Database is ready."
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "ERROR: Database not available after 30 attempts" >&2
        exit 1
    fi
    sleep 2
done

echo "==> Checking database schema"
SQL_OUT=$(mysql -h "${DB_HOSTNAME:-127.0.0.1}" -u "${NICTOOL_DB_USER}" --password="${NICTOOL_DB_USER_PASSWORD}" \
    -e "SELECT option_value FROM ${NICTOOL_DB_NAME:-nictool}.nt_options WHERE option_name='db_version';" 2>&1 | head -n 1) || true

if [ "$SQL_OUT" != "option_value" ]; then
    echo "==> Initializing database schema"
    cd "$NT_DIR/server/sql" || exit 1
    echo "" | perl create_tables.pl --environment
fi

echo "==> Setting up test environment"
perl "$NT_DIR/dist/setup/setup-test-env.pl"

echo "==> Starting Apache"
. /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND
