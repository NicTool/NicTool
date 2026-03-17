#!/bin/sh

#perl .test/create_tables.pl \
cd client \
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
