#!/bin/bash
# Version 1.0.0
# Author Gerhard <gerhard@tinned-software.net>

CONF_DIR="/etc/nictool"

echo ""
echo -e "***\n*** Ensure the required configfiles are distributed in the container\n***\n"

if [ ! -f "${CONF_DIR}/nt_vars" ]; then
	cp -v /usr/local/nictool/dist/docker/debian/web/conf/nt_vars ${CONF_DIR}/nt_vars
fi


if [ ! -f "${CONF_DIR}/nictoolclient.conf" ]; then
	cp -v /usr/local/nictool/client/lib/nictoolclient.conf.dist ${CONF_DIR}/nictoolclient.conf
fi
if [ ! -L "/usr/local/nictool/client/lib/nictoolclient.conf" ]; then 
	ln -v -s -T ${CONF_DIR}/nictoolclient.conf /usr/local/nictool/client/lib/nictoolclient.conf
fi


if [ ! -f "${CONF_DIR}/nictoolserver.conf" ]; then
	cp -v /usr/local/nictool/server/lib/nictoolserver.conf.dist ${CONF_DIR}/nictoolserver.conf
fi
if [ ! -L "/usr/local/nictool/server/lib/nictoolserver.conf" ]; then 
	ln -v -s -T ${CONF_DIR}/nictoolserver.conf /usr/local/nictool/server/lib/nictoolserver.conf
fi


if [ ! -f "${CONF_DIR}/nictool.conf" ]; then
	cp -v /usr/local/nictool/dist/docker/debian/web/conf/nictool.conf ${CONF_DIR}/nictool.conf
fi
if [ ! -L "/etc/apache2/sites-enabled/nictool.conf" ]; then 
	ln -v -s -T ${CONF_DIR}/nictool.conf /etc/apache2/sites-enabled/nictool.conf 
fi


echo ""
echo -e "***\n*** Load the nt_vars environment variables\n***\n"
. ${CONF_DIR}/nt_vars


echo ""
echo -e "***\n*** Check the Database ...\n***\n"
# Test database connection
SQL_OUT=$(mysql -h ${DB_HOSTNAME} -u ${NICTOOL_DB_USER} --password=${NICTOOL_DB_USER_PASSWORD} --connect-timeout=10 -e "SELECT option_value FROM ${NICTOOL_DB_NAME}.nt_options WHERE option_name='db_version';" 2>&1 | head -n 1 )
if [[ "$?" -eq "0" ]]; then
	if [[ "${SQL_OUT}" == "option_value" ]]; then
		echo "OK - Database accessible, table schema present."
	else
		echo "WARN - Database check was not successful. Database empty?"
		SQLPING_ROOT_OUT=$(mysqladmin ping -h ${DB_HOSTNAME} -u root --password=${DB_ROOT_PASSWORD} --connect-timeout=10 2>&1 1>/dev/null)
		if [[ "$?" -eq "0" ]] && [[ "${SQLPING_ROOT_OUT}" == "" ]]; then
			echo "INIT - Initialise the database ..."
			cd /usr/local/nictool/server/sql; ./create_tables.pl --environment
		else
			echo "ERR - Database connection failed. (RC=$?, root)"
			echo ""
			echo "${SQLPING_ROOT_OUT}"
			exit 1
		fi
	fi
else
	echo "ERR - Database connection failed. (RC=$?)"
	echo ""
	echo "${SQL_OUT}"
	exit 1
fi


echo ""
echo -e "***\n*** Checking the Certificate files\n***\n"
if [ ! -f "${CONF_DIR}/server.crt" ]; then
	echo "INIT - Create TLS Key and CSR ..."
	openssl req -x509 -nodes -days 2190 -newkey rsa:2048 \
	-keyout ${CONF_DIR}/server.key -out ${CONF_DIR}/server.crt \
	-subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/OU=$CERT_OU/CN=$CERT_CN/emailAddress=$CERT_EMAIL";
fi
if [ ! -L "/etc/ssl/private/server.key" ]; then 
	ln -v -s -T ${CONF_DIR}/server.key /etc/ssl/private/server.key 
fi
if [ ! -L "/etc/ssl/certs/server.crt" ]; then 
	ln -v -s -T ${CONF_DIR}/server.crt /etc/ssl/certs/server.crt
fi


echo ""
echo -e "***\n*** Start the Apache webserver\n***\n"
. /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND

