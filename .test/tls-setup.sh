#!/bin/sh

TLS_DIR=${TLS_DIR:="/etc/ssl"}

for _d in "$TLS_DIR/certs" "$TLS_DIR/private"; do
    if [ ! -d "$_d" ]; then
        mkdir "$_d"
    fi
done

chmod o-r "$TLS_DIR/private"
# If installed openssl supports Elliptical Curve...
#   -newkey ec \
#   -pkeyopt ec_paramgen_curve:prime256v1 \
openssl req \
    -new \
    -newkey rsa:2048 \
    -days 2190 \
    -nodes \
    -x509 \
    -subj "/C=US/ST=Washington/L=Seattle/O=TNPI/CN=travis.tnpi.net" \
    -keyout "$TLS_DIR/private/server.key" \
    -out "$TLS_DIR/certs/server.crt"

a2enmod ssl
