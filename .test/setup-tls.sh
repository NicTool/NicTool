#!/bin/sh

. .test/base.sh

mkdir "$NICTOOL_HOME/tls"
chmod 755 "$NICTOOL_HOME/tls"

if [ -n "$TRAVIS" ]; then

    # doesn't support Elliptical Curve
    openssl req \
        -new \
        -newkey rsa:2048 \
        -days 2190 \
        -nodes \
        -x509 \
        -subj "/C=US/ST=Washington/L=Seattle/O=TNPI/CN=ci.tnpi.net" \
        -keyout "$NICTOOL_HOME/tls/server.key" \
        -out "$NICTOOL_HOME/tls/server.crt"

else

    openssl req \
        -new \
        -newkey ec \
        -days 2190 \
        -nodes \
        -x509 \
        -subj "/C=US/ST=Washington/L=Seattle/O=TNPI/CN=ci.tnpi.net" \
        -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$NICTOOL_HOME/tls/server.key" \
        -out "$NICTOOL_HOME/tls/server.crt"

fi

a2enmod ssl
