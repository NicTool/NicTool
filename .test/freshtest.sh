#!/bin/sh

cd server/sql \
  && echo "" | perl create_tables.pl --environment \
  && cd ../.. \
  && perl dist/setup/setup-test-env.pl \
  && cd client \
  && perl Makefile.PL \
  && sudo make install \
  && cd ../server \
  && perl Makefile.PL \
  && sudo make install \
  && sudo /opt/local/sbin/apachectl restart \
  && make test \
  && cd ../client \
  && make test \
  && cd ..
