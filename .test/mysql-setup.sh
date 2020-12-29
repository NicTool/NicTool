#!/bin/sh

mysql -e 'SET GLOBAL sql_mode = "";'
echo 'sql_mode=""' | tee -a /etc/mysql/mysql.conf.d/mysqld.cnf

service mysql restart
