#!/bin/bash
# Version 1.0.0
# Author Gerhard <gerhard@tinned-software.net>

CONF_DIR="/etc/nictool"


# Check if nt_vars exists
if [ ! -f "${CONF_DIR}/nt_vars" ]; then
	cp /usr/local/nictool/dist/docker/debian/web/conf/nt_vars ${CONF_DIR}/nt_vars
fi


if [ ! -f "${CONF_DIR}/nictoolclient.conf" ]; then
	cp -v /usr/local/nictool/client/lib/nictoolclient.conf.dist ${CONF_DIR}/nictoolclient.conf
fi
if [ ! -L "/usr/local/nictool/client/lib/nictoolclient.conf" ]; then 
	ln -s -T ${CONF_DIR}/nictoolclient.conf /usr/local/nictool/client/lib/nictoolclient.conf
fi


if [ ! -f "${CONF_DIR}/nictoolserver.conf" ]; then
	cp -v /usr/local/nictool/server/lib/nictoolserver.conf.dist ${CONF_DIR}/nictoolserver.conf
fi
if [ ! -L "/usr/local/nictool/server/lib/nictoolserver.conf" ]; then 
	ln -s -T ${CONF_DIR}/nictoolserver.conf /usr/local/nictool/server/lib/nictoolserver.conf
fi


if [ ! -f "${CONF_DIR}/nictool.conf" ]; then
	cp -v /usr/local/nictool/dist/docker/debian/web/conf/nictool.conf ${CONF_DIR}/nictool.conf
fi
if [ ! -L "/etc/apache2/sites-enabled/nictool.conf" ]; then 
	ln -s -T ${CONF_DIR}/nictool.conf /etc/apache2/sites-enabled/nictool.conf 
fi

# Lead the nt_vars environment variables
. ${CONF_DIR}/nt_vars

# Test database connection
SQL_OUT=$(mysql -h ${DB_HOSTNAME} -u ${NICTOOL_DB_USER} --password=${NICTOOL_DB_USER_PASSWORD} --connect-timeout=10 -e "SELECT option_value FROM ${NICTOOL_DB_NAME}.nt_options WHERE option_name='db_version';" | head -n 1 2>&1)
if [[ "$?" -eq "0" ]]; then
	if [[ "${SQL_OUT}" == "option_value" ]]; then
		echo "OK - Database accessible, table schema present."
	else
		SQLPING_ROOT_OUT=$(mysqladmin ping -h ${DB_HOSTNAME} -u root --password=${DB_ROOT_PASSWORD} --connect-timeout=10 2>&1 1>/dev/null)
		if [[ "$?" -eq "0" ]] && [[ "${SQLPING_ROOT_OUT}" == "" ]]; then
			cd /usr/local/nictool/server/sql; ./create_tables.pl --environment
		else
			echo "Database connection failed. (RC=$?, root)"
			echo ""
			echo "${SQLPING_ROOT_OUT}"
			exit 1
		fi
	fi
else
	echo "Database connection failed. (RC=$?)"
	echo ""
	echo "${SQL_OUT}"
	exit 1
fi


if [ ! -f "${CONF_DIR}/server.crt" ]; then
		openssl req -x509 -nodes -days 2190 -newkey rsa:2048 \
		-keyout ${CONF_DIR}/server.key -out ${CONF_DIR}/server.crt \
		-subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORG/OU=$CERT_OU/CN=$CERT_CN/emailAddress=$CERT_EMAIL";
fi
if [ ! -L "/etc/ssl/private/server.key" ]; then 
	ln -s -T ${CONF_DIR}/server.key /etc/ssl/private/server.key 
fi
if [ ! -L "/etc/ssl/certs/server.crt" ]; then 
	ln -s -T ${CONF_DIR}/server.crt /etc/ssl/certs/server.crt
fi



# Start the webserver
. /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND

