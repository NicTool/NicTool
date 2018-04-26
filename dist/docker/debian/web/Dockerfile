FROM debian:8.8
MAINTAINER John Jensen <jensenja@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8

# take care of OS stuff
RUN apt-get -q update && apt-get install -qy --force-yes \
      perl \
      cpanminus \
      build-essential \
      apache2 \
      libapache2-mod-perl2 \
      libapache2-mod-perl2-dev \
      libxml2 \
      libssl-dev \
      libmysqld-dev \
      expat \
      libexpat-dev \
      gettext \
      git \
      bind9utils \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# clone the NicTool repo
RUN git clone https://github.com/msimerson/NicTool.git /usr/local/nictool

# install Perl dependencies
RUN cd /usr/local/nictool/server \
      && git checkout travis-more-testing; \
      cd /usr/local/nictool/server; perl Makefile.PL; cpanm -n . \
      && cd /usr/local/nictool/client; perl Makefile.PL; cpanm -n .

# set up/install any additional Perl dependencies
RUN cd /usr/local/nictool/server \
      && perl bin/nt_install_deps.pl; \
      cd /usr/local/nictool/client \
      && perl bin/install_deps.pl

# source environment variables
COPY ./nt_vars /root/nt_vars

# set up the database, generate self-signed cert
RUN . /root/nt_vars; \
      cd /usr/local/nictool/server/sql; \
      ./create_tables.pl --environment \
      && chmod o-r /etc/ssl/private; \
      openssl req \
      -x509 \
      -nodes \
      -days 2190 \
      -newkey rsa:2048 \
      -keyout /etc/ssl/private/server.key \
      -out /etc/ssl/certs/server.crt \
      -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/OU=$CERT_OU/CN=$CERT_CN/emailAddress=$CERT_EMAIL"; \
      rm -rf /root/nt_vars

# copy configuration files
COPY ./nictoolclient.conf /usr/local/nictool/client/lib/nictoolclient.conf
COPY ./nictoolserver.conf /usr/local/nictool/server/lib/nictoolserver.conf

# set up apache
RUN rm -rf /etc/apache2/sites-enabled/* \
      && rm -rf /etc/apache2/sites-available/*
COPY ./nictool.conf /etc/apache2/sites-available/nictool.conf

RUN cd /etc/apache2/sites-enabled; \
      ln -s ../sites-available/nictool.conf nictool.conf; \
      a2enmod ssl

EXPOSE 80 443

CMD . /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND
