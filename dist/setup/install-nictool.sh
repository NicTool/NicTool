#!/bin/sh
set -e

# Parse --nt-dir flag or use NT_DIR env var
NT_DIR="${NT_DIR:-/usr/local/nictool}"
for arg in "$@"; do
    case "$arg" in
        --nt-dir=*) NT_DIR="${arg#--nt-dir=}" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Installing NicTool configs (NT_DIR=$NT_DIR)"

# Copy .dist → .conf if .conf doesn't exist yet
for conf in server/lib/nictoolserver client/lib/nictoolclient; do
    src="$NT_DIR/${conf}.conf.dist"
    dst="$NT_DIR/${conf}.conf"
    if [ ! -f "$dst" ]; then
        echo "    cp $src -> $dst"
        cp "$src" "$dst"
    fi
done

# mod_perl requires prefork MPM (not event/worker)
echo "==> Configuring Apache MPM"
if command -v a2dismod >/dev/null 2>&1; then
    a2dismod mpm_event 2>/dev/null || true
    a2dismod mpm_worker 2>/dev/null || true
    a2enmod mpm_prefork 2>/dev/null || true
fi

# Generate Apache config from template
echo "==> Generating Apache config"
sed "s|%%NT_DIR%%|${NT_DIR}|g" "$SCRIPT_DIR/apache.conf.in" \
    > "/etc/apache2/sites-enabled/nictool.conf"

# Export NicTool env vars into Apache's envvars so mod_perl can see them
echo "==> Injecting NicTool env vars into Apache envvars"
ENVVARS="/etc/apache2/envvars"
if [ -f "$ENVVARS" ]; then
    for var in DB_ENGINE DB_HOSTNAME DB_PORT DB_SSL \
               NICTOOL_DB_NAME NICTOOL_DB_USER NICTOOL_DB_USER_PASSWORD \
               NICTOOL_CLIENT_DIR NICTOOL_SERVER_HOST NICTOOL_SERVER_PORT \
               NICTOOL_SERVER_PROTOCOL NICTOOL_DATA_PROTOCOL; do
        val=$(eval printf %s "\"\${$var:-}\"")
        if [ -n "$val" ]; then
            # Escape single quotes for safe inclusion in single-quoted shell:
            # close-quote, escaped quote, re-open-quote.
            esc=$(printf %s "$val" | sed "s/'/'\\\\''/g")
            printf "export %s='%s'\n" "$var" "$esc" >> "$ENVVARS"
        fi
    done
fi

# Set up TLS certificates
echo "==> Setting up TLS"
"$SCRIPT_DIR/tls-setup.sh"
