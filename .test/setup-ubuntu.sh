#!/bin/sh

. .test/base.sh || exit

sudo apt-get install -y $(cat .test/ubuntu-18-apts)

sudo cpanm --notest CGI MIME::Base64::Perl RPC::XML CryptX Crypt::Mac::HMAC Crypt::KeyDerivation
cpanm --notest Net::DNS Test::More Test::HTML::Lint Test::Output Test::Pod Time::TAI64

for _d in client server; do
    cd "$NICTOOL_HOME/$_d" && perl Makefile.PL && cpanm -n .
done

cd "$NICTOOL_HOME" || echo "oops, cd failed"
