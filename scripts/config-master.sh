#!/bin/bash

LOG_FILE=/var/log/odai-startup.log
# Functions useful for the script
function log()
{
    message="$@"
    echo $message
	echo "$(date +&#37;c) $message" >>$LOG_FILE
}

function getPwd(){
	log "Change root password for $1 [using azAZ09]"
	while true
	do
		read -s pwd

		b=$(echo $pwd | egrep "^.{8,255}" | egrep "[ABCDEFGHIJKLMNOPQRSTUVXYZ]" | egrep "[abcdefghijklmnopqrstuvxyz"] | egrep "[0-9]")

		#if the result string is empty, one of the conditions has failed
		if [ -z $b ]
		  then
			echo "Not good password"
		  else
			echo "Conditions match"
		fi
		echo "Password again: "
		read -s pwd2
		if [ $b=$pwd2 ]
		  then 
		    	break
		  else
			echo "Please try again"
		fi
	done
	eval $2="'$pwd'"
}

function config-opendai {
	log "config-opendai"
	
	# SET the user local time
	PS3="Your choice: "
	service ntpd stop
	rm -f /etc/localtime
	echo "select the timezone"
	select TIMEZONE in "Rome" "Madrid" "Instambul" "Stockholm"
	do
        case $TIMEZONE in
                "Rome")
                        ln -s /usr/share/zoneinfo/Europe/Rome /etc/localtime
						augtool defnode date.timezone /files/etc/php.ini/Date/date.timezone "Europe/Rome" -s
                        break;;
                *) exit;;
        esac
	done
	ntpdate 1.centos.pool.ntp.org
	service ntpd start
	
	
	# Postgresql
	postgres_pwd_orig=pgopendai
	getPwd "Postgresql" postgres_pwd
	echo $postgres_pwd
	sudo -u postgres PGPASSWORD=$postgres_pwd_orig  psql -c "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	log "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	service postgresql restart
	
	
	# Configure MCollective
	getPwd "MCollective" mc_pwd
	sed -i "s/plugin.psk = unset/plugin.psk = $mc_pwd/g" /etc/mcollective/client.cfg
	
	getPwd "MCollective" mc_stomp_pwd
	sed -i "s/plugin.stomp.password = secret/plugin.stomp.password = $mc_stomp_pwd/g" /etc/mcollective/client.cfg
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/plugins/simpleAuthenticationPlugin/users/authenticationUser[2]/#attribute/password $mc_stomp_pwd"|augtool -s
	

	#ConfigureINSTALL Zabbix
	log "Configureing Zabbix passwords"
	
	getPwd "ZabbixDB" zabbixDBpwd
	zabbixDBuser=zabbix

	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "ALTER USER $zabbixDBuser WITH PASSWORD '$zabbixDBpwd';"
	augtool defnode DBPassword /files/etc/zabbix/zabbix_server.conf/DBPassword $zabbixDBpwd -s

	#Setting the Zabbix Web config file
	log "Zabbix web config file"
(
cat << EOF
<?php
// Zabbix GUI configuration file
global \$DB;

\$DB['TYPE']     = 'POSTGRESQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = '$zabbixDBuser';
\$DB['PASSWORD'] = '$zabbixDBpwd';

// SCHEMA is relevant only for IBM_DB2 database
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
?>
EOF
) > /etc/zabbix/web/zabbix.conf.php
	service httpd restart

	getPwd "Zabbix Web Admin" zabbixWEBpwd
	sudo -u $zabbixDBuser PGPASSWORD=$postgres_pwd psql -c "update users set passwd=md5('$zabbixWEBpwd') where alias='Admin';"
	

	
}

#execute the tasks
config-opendai | tee /root/config-open-dai.log