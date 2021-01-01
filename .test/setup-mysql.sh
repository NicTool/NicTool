#!/bin/sh

install_mysqld()
{
    sudo apt-get install -y mysql-server mysql-client
}

install_mysql_perl()
{
    sudo apt-get install -y libmysqlclient-dev libdbi-perl libdbd-mysql-perl libdbix-simple-perl
    # sudo cpanm --notest DBD::mysql
}

configure_mysqld()
{
    echo 'sql_mode=""' | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf
}

if [ -n "$TRAVIS" ]; then
    #configure_mysqld
    #sudo service mysql restart
    mysql -u root -e 'SET GLOBAL sql_mode = "";'

elif [ -n "$GITHUB_ACTIONS" ]; then

    # install_mysql_perl
    configure_mysqld
    sudo service mysql start
    mysql -u root -proot -e 'SET GLOBAL sql_mode = "";'

else

    # install_mysqld
    # install_mysql_perl
    configure_mysqld
    sudo service mysql start
    sudo mysql -e 'SET GLOBAL sql_mode = "";'

fi

perl .test/create_tables.pl