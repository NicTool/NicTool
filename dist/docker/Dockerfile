FROM debian:8.8
MAINTAINER John Jensen <jensenja@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8

RUN apt-get -q update

# take care of OS stuff
RUN apt-get install -qy --force-yes \
      perl \
      cpanminus \
      libdbix-simple-perl \
      libdbd-mysql-perl \
      apache2 \
      libapache2-mod-perl2 \
      libapache2-mod-perl2-dev \
      libapache-dbi-perl \
      ssh \
      git \
      curl \
      gcc \
      make \
      gettext \
      rsync \
      libxml2 \
      libnet-ip-perl \
      libxml-parser-perl \
      libxml-libxml-perl \
      libdigest-hmac-perl \
      libjson-perl \
      librpc-xml-perl \
      libsoap-lite-perl \
      libmodule-build-perl \
      libmime-base32-perl \
      libbind-confparser-perl \
      libssl-dev \
      libcrypt-openssl-rsa-perl \
      libcrypt-openssl-dsa-perl \
      libshell-perl \
      libnet-dns-perl \
      libyaml-perl \
      expat \
      libexpat1-dev \
      bind9utils
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# install leftover perl required perl modules.
RUN cpanm Crypt::KeyDerivation Crypt::Mac::HMAC CryptX Time::TAI64

RUN git clone https://github.com/msimerson/NicTool.git /usr/local/nictool

RUN cd /usr/local/nictool/server \
      && git checkout travis-more-testing; \
      cd /usr/local/nictool/server; perl Makefile.PL; cpanm -n . \
      && cd /usr/local/nictool/server; perl Makefile.PL; cpanm -n .

# set up/install additional perl dependencies...
RUN cd /usr/local/nictool/server \
      && perl bin/nt_install_deps.pl; \
      cd /usr/local/nictool/client \
      && perl bin/install_deps.pl

COPY ./nt_vars /root/nt_vars

RUN . /root/nt_vars; \
      cd /usr/local/nictool/server/sql; \
      ./create_tables.pl --environment

RUN . /root/nt_vars; \
      chmod o-r /etc/ssl/private; \
      openssl req \
      -x509 \
      -nodes \
      -days 2190 \
      -newkey rsa:2048 \
      -keyout /etc/ssl/private/server.key \
      -out /etc/ssl/certs/server.crt \
      -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/OU=$CERT_OU/CN=$CERT_CN/emailAddress=$CERT_EMAIL"

RUN rm -rf /root/nt_vars

COPY ./nictoolclient.conf /usr/local/nictool/client/lib/nictoolclient.conf
COPY ./nictoolserver.conf /usr/local/nictool/server/lib/nictoolserver.conf

RUN rm -rf /etc/apache2/sites-enabled/*
RUN rm -rf /etc/apache2/sites-available/*
COPY ./nictool.conf /etc/apache2/sites-available/nictool.conf

RUN cd /etc/apache2/sites-enabled; \
      ln -s ../sites-available/nictool.conf nictool.conf

RUN a2enmod ssl

RUN export NTE_USER=nictool; \
      adduser --system $NTE_USER

USER nictool
WORKDIR /home/nictool
RUN ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -N ''; \
      >&2 echo "================================================================================="; \
      >&2 echo "| Below is your public key for your DNS servers. COPY THIS SOMEWHERE!!!         |"; \
      >&2 echo "================================================================================="; \
      >&2 cat .ssh/id_rsa.pub; \
      >&2 echo "=================================================================================";

USER root
WORKDIR /root

EXPOSE 80 443

CMD . /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND
