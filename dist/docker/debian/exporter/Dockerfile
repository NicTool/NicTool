FROM debian:8.8
MAINTAINER John Jensen <jensenja@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en_US.UTF-8

# take care of OS stuff
RUN apt-get -q update && apt-get install -qy --force-yes \
      perl \
      cpanminus \
      build-essential \
      libxml2 \
      libssl-dev \
      libmysqld-dev \
      expat \
      libexpat-dev \
      gettext \
      ssh-client \
      git \
      rsync \
      bind9utils \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone https://github.com/msimerson/NicTool.git /usr/local/nictool

RUN cd /usr/local/nictool/server \
      && git checkout travis-more-testing; \
      cd /usr/local/nictool/server; perl Makefile.PL; cpanm -n . \
      && cd /usr/local/nictool/client; perl Makefile.PL; cpanm -n .

# set up/install additional perl dependencies...
RUN cd /usr/local/nictool/server \
      && perl bin/nt_install_deps.pl; \
      cd /usr/local/nictool/client \
      && perl bin/install_deps.pl

#COPY ./nt_vars /root/nt_vars

#RUN rm -rf /root/nt_vars

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
