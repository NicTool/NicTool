#!/bin/sh

TLS_DIR=${TLS_DIR:="/home/travis/build/msimerson/NicTool/ssl"}
if [ -n "$GITHUB_ACTIONS" ]; then
    TLS_DIR="/home/runner/work/NicTool/NicTool/tls"
fi

env

mkdir -p "$TLS_DIR"
chmod 755 "$TLS_DIR"

# If installed openssl supports Elliptical Curve...
# -newkey rsa:2048 \

openssl req \
    -new \
    -newkey ec \
    -days 2190 \
    -nodes \
    -x509 \
    -subj "/C=US/ST=Washington/L=Seattle/O=TNPI/CN=travis.tnpi.net" \
    -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$TLS_DIR/server.key" \
    -out "$TLS_DIR/server.crt"

sudo a2enmod ssl
sudo systemctl restart apache2