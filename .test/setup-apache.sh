#!/bin/sh

. .test/base.sh || exit

for _f in apache.conf nictoolclient.conf nictoolserver.conf;
do
    if ! grep -q NT_HOME ".test/$_f"; then
        echo "skip .test/$_f"
        continue
    fi

    echo "updating NT_HOME in .test/$_f"
    if echo "$OSTYPE" | grep -q darwin; then
        sed -i '' -e "s|NT_HOME|$NICTOOL_HOME|g" ".test/$_f"
    else
        sed -i -e "s|NT_HOME|$NICTOOL_HOME|g" ".test/$_f"
    fi
done

echo "installing /etc/apache2/sites-enabled/nictool.conf"
sudo cp .test/apache.conf /etc/apache2/sites-enabled/nictool.conf

if [ -e "/etc/apache2/sites-enabled/000-default.conf" ]; then
    rm /etc/apache2/sites-enabled/000-default.conf
fi

if [ -n "$TRAVIS" ]; then
    echo "enabling SSL module"
    sudo a2enmod ssl
    sudo a2dismod mpm_event
    sudo a2dismod mpm_worker
    sudo a2enmod mpm_prefork
    # sudo service apache2 restart || sudo cat /var/log/apache2/error.log
elif [ -n "$GITHUB_ACTIONS" ]; then
    sudo apt-get install -y apache2 libapache2-mod-perl2 libapache2-mod-perl2-dev libapache-dbi-perl
    echo "enabling SSL module"
    sudo a2enmod ssl
    sudo a2dismod mpm_event
    sudo a2dismod mpm_worker
    sudo a2enmod mpm_prefork
    sudo cpanm --notest Apache::DBI
    sudo systemctl restart apache2 || sudo cat /var/log/apache2/error.log
else
    sudo apt-get install -y apache2 libapache2-mod-perl2 libapache2-mod-perl2-dev libapache-dbi-perl
    echo "enabling SSL module"
    sudo a2enmod ssl
    sudo a2dismod mpm_event
    sudo a2dismod mpm_worker
    sudo a2enmod mpm_prefork
    sudo cpanm --notest Apache::DBI
    sudo systemctl restart apache2 || sudo cat /var/log/apache2/error.log
fi
