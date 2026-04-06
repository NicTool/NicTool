FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8

RUN apt-get -q update && apt-get install -qy \
      perl \
      cpanminus \
      build-essential \
      apache2 \
      libapache2-mod-perl2 \
      libapache2-mod-perl2-dev \
      libxml2 \
      libssl-dev \
      libmariadb-dev \
      expat \
      libexpat-dev \
      gettext \
      bind9utils \
      mariadb-client \
      openssl \
      libdbix-simple-perl \
      libdbd-mysql-perl \
      libapache-dbi-perl \
      libnet-ip-perl \
      libxml-libxml-perl \
      libxml-parser-perl \
      libdigest-hmac-perl \
      libjson-perl \
      librpc-xml-perl \
      libsoap-lite-perl \
      libmodule-build-perl \
      libmime-base32-perl \
      libmime-base64-perl \
      libbind-confparser-perl \
      libcrypt-openssl-rsa-perl \
      libcrypt-openssl-dsa-perl \
      libnet-dns-perl \
      libyaml-perl \
      libwww-perl \
      liburi-perl \
      libmime-tools-perl \
      libmailtools-perl \
      libfile-sharedir-perl \
      libdbi-perl \
      libcgi-pm-perl \
      libtest-pod-perl \
      libtest-output-perl \
      libtest-simple-perl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy only Makefile.PL files first for dependency caching
COPY server/Makefile.PL /usr/local/nictool/server/Makefile.PL
COPY client/Makefile.PL /usr/local/nictool/client/Makefile.PL

# Install Perl dependencies (cached unless Makefile.PL changes)
RUN cd /usr/local/nictool/server && perl Makefile.PL && cpanm -n . \
    && cd /usr/local/nictool/client && perl Makefile.PL && cpanm -n .

# Additional Perl modules not in Makefile.PL
RUN cpanm --notest \
    CryptX Crypt::Mac::HMAC Crypt::KeyDerivation \
    Test::HTML::Lint Time::TAI64 DBD::MariaDB \
    Net::LDAP Test::Output

# Set up Apache modules
RUN a2dismod mpm_event && a2enmod mpm_prefork && a2enmod ssl \
    && rm -rf /etc/apache2/sites-enabled/* /etc/apache2/sites-available/*

# Now copy the full source (only this layer invalidates on code changes)
COPY server/ /usr/local/nictool/server/
COPY client/ /usr/local/nictool/client/
COPY dist/   /usr/local/nictool/dist/

# Install the actual NicTool modules (deps are cached above)
RUN cd /usr/local/nictool/server && perl Makefile.PL && make install \
    && cd /usr/local/nictool/client && perl Makefile.PL && make install

COPY dist/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

CMD ["/entrypoint.sh"]
