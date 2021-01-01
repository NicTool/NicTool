#!/bin/sh

. .test/base.sh || exit

install_apache2()
{
    sudo apt-get install -y apache2 libapache2-mod-perl2 libapache2-mod-perl2-dev libapache-dbi-perl
    sudo cpanm --notest Apache::DBI
}

config_modules()
{
    echo "enabling SSL module"
    sudo a2enmod ssl

    echo "switching to prefork"
    sudo a2dismod mpm_event
    sudo a2dismod mpm_worker
    sudo a2enmod mpm_prefork
}

config_apache_site()
{
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
        echo "deleting 000-default.conf"
        sudo rm /etc/apache2/sites-enabled/000-default.conf
    fi
}

if [ -n "$TRAVIS" ]; then

    echo "enabling SSL module"
    sudo a2enmod ssl
    config_apache_site
    # config_modules
    sudo service apache2 restart || sudo cat /var/log/apache2/error.log

#elif [ -n "$GITHUB_ACTIONS" ]; then
else

    install_apache2
    config_modules
    config_apache_site
    sudo systemctl restart apache2 || sudo cat /var/log/apache2/error.log
fi
