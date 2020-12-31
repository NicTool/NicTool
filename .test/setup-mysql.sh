#!/bin/sh


if [ -n "$TRAVIS" ]; then
    sudo service mysql restart
    # mysql -e 'SET GLOBAL sql_mode = "";'

elif [ -n "$GITHUB_ACTIONS" ]; then
    echo 'sql_mode=""' | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo apt-get install -y libmysqlclient-dev libdbi-perl libdbd-mysql-perl libdbix-simple-perl
    sudo cpanm --notest DBD::mysql
    sudo service mysql start
    mysql -u root -proot -e 'SET GLOBAL sql_mode = "";'
else
    echo 'sql_mode=""' | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo apt-get install -y mysql-server mysql-client libmysqlclient-dev libdbi-perl libdbd-mysql-perl libdbix-simple-perl
    sudo cpanm --notest DBD::mysql
    sudo service mysql start
    mysql -u root -e 'SET GLOBAL sql_mode = "";'
fi
