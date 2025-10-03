FROM debian
MAINTAINER Gerhard <gerhard@tinned-software.net>

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
      libmariadb-dev \
      expat \
      libexpat-dev \
      gettext \
      git \
      bind9utils \
      mariadb-client \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# clone the NicTool repo
RUN git clone https://github.com/nictool/NicTool.git /usr/local/nictool

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

# install Perl module for LDAP authentication
RUN cpanm Net::LDAP

# set up apache
RUN rm -rf /etc/apache2/sites-enabled/* \
      && rm -rf /etc/apache2/sites-available/*

# ensure exposed 
RUN mkdir -p /etc/nictool/ && mkdir -p /var/lib/nictool/

RUN a2enmod ssl && a2dismod mpm_event && a2enmod mpm_prefork

ADD startup.sh /startup.sh

EXPOSE 80 443

VOLUME /etc/nictool/ /var/lib/nictool/

CMD /bin/bash /startup.sh
