#!/bin/bash

LOG_FILE=/var/log/odai-startup.log
# Functions useful for the script
function log()
{
    message="$@"
    echo $message
	echo "$message" >>$LOG_FILE
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
	
	echo "Change the root password"
	getPwd "root" root_pwd
	# ignores any line containing the word passwd, so it doesn’t get added to the bash history file
	export HISTIGNORE="*passwd*"
	echo $root_pwd | passwd --stdin root
	
	# TODO move other pwd here
	echo "Do you want to use the same password for all the services?"
	select SAMEPWD in "Yes" "No"
	do
        case $SAMEPWD in
                "Yes")
                    getPwd "Unique password" unique_pwd
					postgres_pwd=$unique_pwd
					mc_pwd=$unique_pwd
					mc_stomp_pwd=$unique_pwd
					zabbixDBpwd=$unique_pwd
                    break;;
				"No")
					getPwd "Postgresql" postgres_pwd
					getPwd "MCollective" mc_pwd
					getPwd "MCollective Stomp" mc_stomp_pwd
					getPwd "ZabbixDB" zabbixDBpwd
					break;;
                *) exit;;
        esac
	done
	
	# Postgresql
	postgres_pwd_orig=pgopendai
	echo $postgres_pwd
	sudo -u postgres PGPASSWORD=$postgres_pwd_orig  psql -c "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	log "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	service postgresql restart
	
	
	# Configure MCollective
	sed -i "s/plugin.psk = unset/plugin.psk = $mc_pwd/g" /etc/mcollective/client.cfg
	sed -i "s/plugin.stomp.password = secret/plugin.stomp.password = $mc_stomp_pwd/g" /etc/mcollective/client.cfg
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/plugins/simpleAuthenticationPlugin/users/authenticationUser[2]/#attribute/password $mc_stomp_pwd"|augtool -s
	

	#ConfigureINSTALL Zabbix
	log "Configuring Zabbix passwords"
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
	sudo -u $zabbixDBuser PGPASSWORD=$zabbixDBpwd psql <<EOF
update users set passwd=md5('$zabbixWEBpwd') where alias='Admin';
EOF
	

	getPwd "Jboss master admin" jboss_master_admin
	getPwd "Jboss slave admin" jboss_slave_admin
	getPwd "API Manager DB" api_db
	getPwd "Registry admin" greg
	getPwd "BAM admin" bam_admin
	getPwd "BAM DB" bam_db
	getPwd "BPS Admin" bps_admin
	getPwd "BPS DB" bps_db
	getPwd "ESB Admin" esb_admin
	getPwd "ESB DB" esb_db
	
(
cat << EOF
# Governance Registry data
greg:
  db_password: "odaigreg1"
  admin_pwd: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $greg)

# BAM data
bam:
  db_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $bam_db)
  admin_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $bam_admin)

# API Manager data
am:
  db_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $api_db)

# BPS data
bps:
  db_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $bps_db)
  admin_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $bps_admin)

# ESB data
esb:
  db_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $esb_db)
  admin_password: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $esb_admin)

  
stomp_passwd: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $mc_stomp_pwd)
mc_security_psk: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $mc_pwd)
mysqlsoapwd: "odaipass01soa"
jbossadminpwdbb: $(eyaml encrypt -o string -s --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem $jboss_master_admin)
jbossadminslavepwdbb: $(eyaml encrypt -o string --pkcs7-public-key /etc/puppet/secure/keys/public_key.pkcs7.pem --pkcs7-private-key /etc/puppet/secure/keys/private_key.pkcs7.pem -s $jboss_slave_admin)
EOF
) > /etc/puppet/secure/common.eyaml	
	
	
	
}

#execute the tasks
config-opendai | tee /root/config-open-dai.log