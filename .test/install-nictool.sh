#!/bin/sh

NT_INSTALL_DIR=${NT_INSTALL_DIR:="/usr/local/nictool"}

if [ ! -d "$NT_INSTALL_DIR" ]; then
    mkdir -p "$NT_INSTALL_DIR" || exit
fi

cp .test/nictoolserver.conf server/lib/nictoolserver.conf
cp .test/nictoolclient.conf client/lib/nictoolclient.conf

cp -r server "$NT_INSTALL_DIR/"
cp -r client "$NT_INSTALL_DIR/"
