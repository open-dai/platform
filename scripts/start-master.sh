function package_installed (){
    name=$1
    if `rpm -q $name 1>/dev/null`; then
	return 0
    else
	return 1
    fi
}

function install_package (){
    `yum install --quiet -y $1 1>/dev/null`
    RET=$?
    if [ $RET == 0 ]; then
	return 0
    else
	echo "ERROR: Could not install package $1"
	log "ERROR: Could not install package $1"
	exit 1
    fi
}

function ensure_package_installed (){
    if ! package_installed $1 ; then
	echo "Installing ${1}"
	log "Installing ${1}"
	install_package $1
    fi
}


function start-opendai {
	log "start-opendai"
	
	log "fixing Vagrant keys"
	chmod 600 /home/vagrant/.ssh/authorized_keys
	chown -R vagrant:vagrant /home/vagrant/.ssh

	# Installing repositories
	log "adding repos"
	#add puppet repository
	rpm --import https://fedoraproject.org/static/0608B895.txt
	rpm -ivh http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-10.noarch.rpm
	#add RPMFORGE repository
	rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.2-2.el6.rf.x86_64.rpm
	#add EPEL repository
	rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
	#zabbix repos
	rpm -ivh http://repo.zabbix.com/zabbix/2.2/rhel/6/x86_64/zabbix-release-2.2-1.el6.noarch.rpm
	log $(yum check-update)
	
	log "Cloudstack stuff"
	#First cloudstack recover virtual router IP
	server_ip=$(cat /var/lib/dhclient/dhclient-eth0.leases | grep dhcp-server-identifier | tail -1| awk '{print $NF}' | tr '\;' ' ')
	server_ip2=${server_ip:0:${#server_ip}-1}
	log "Cloudstsack virtual router" $server_ip2
	userdata=$(curl http://$server_ip2/latest/user-data)
	log "userdata:" $userdata

	#transform userdata in env vars
	eval $userdata
	
	# CHECK ENV VARS
	# could be from Cloudstack or have to have a default value
	if [[ -z "$timezone" ]]; then timezone='Rome'; fi
#	if [[ -z "$environment" ]]; then environment='production'; fi
	
	
	#install ntp  
	ensure_package_installed "ntp"
	rm -f /etc/localtime
	ln -s /usr/share/zoneinfo/Europe/$timezone /etc/localtime
	ntpdate 1.centos.pool.ntp.org
	service ntpd start
	chkconfig --levels 235 ntpd on
	log "started ntp" $(service ntpd status)

	#install bind since it is needed by some puppet/facter plugin and cannot be installed by puppet itself
	ensure_package_installed "bind-utils"
	
	# Fail2ban for security
	ensure_package_installed fail2ban
	service fail2ban start
	chkconfig fail2ban on

	# Configuration tool Augeas
	ensure_package_installed "augeas"
	# Editor nano
	ensure_package_installed "nano"

	# Apache
	ensure_package_installed "httpd"
	chkconfig --levels 235 httpd on
	service httpd start
	log "started httpd" $(service httpd status)
	
	# Postgresql
	log "Install Postgresql"
	ensure_package_installed "postgresql-server"
	service postgresql initdb
	service postgresql start
	chkconfig --levels 235 postgresql on
	log "setting the access to postgres with md5"
	postgres_pwd=pgopendai
	sudo -u postgres psql -c "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	log "ALTER USER Postgres WITH PASSWORD '$postgres_pwd';"
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/1/method md5 -s
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/2/method md5 -s
	augtool set /files/var/lib/pgsql/data/pg_hba.conf/3/method md5 -s
	service postgresql restart
	
	# PHP
	ensure_package_installed "php"
	augtool set /files/etc/php.ini/PHP/max_execution_time 600 -s
	augtool set /files/etc/php.ini/PHP/memory_limit 256M -s
	augtool set /files/etc/php.ini/PHP/post_max_size 32M -s
	augtool set /files/etc/php.ini/PHP/upload_max_filesize 16M -s
	augtool set /files/etc/php.ini/PHP/max_input_time 600 -s
	augtool set /files/etc/php.ini/PHP/expose_php off -s
	augtool defnode date.timezone /files/etc/php.ini/Date/date.timezone "Europe/$timezone" -s
	service httpd restart

	# -------------------- PUPPET STUFF
	# Puppet Master
	ensure_package_installed "puppet-server"
	
	#Puppet, PuppetDb, Dashboard and MCollective settings
	myHostname=$(facter fqdn)
	myIP=$(facter ipaddress)
	myDomain=$(facter domain)
puppetDB=mgmtdb.$myDomain
	mc_pwd=mcopwd
	mc_stomp_pwd=mcopwd
dash_db_pwd=dashboard
	log "hostname" $myHostname
	log "IP" $myIP
	log "domain" $myDomain
	log "mc_pwd" $mc_pwd
	log "mc_stomp_pwd" $mc_stomp_pwd
log "dash_db_pwd" $dash_db_pwd
	
	
	# Configuration of puppet.conf
	augtool ins confdir before /files/etc/puppet/puppet.conf/main/logdir -s
	augtool set /files/etc/puppet/puppet.conf/main/confdir /etc/puppet -s
	augtool ins vardir before /files/etc/puppet/puppet.conf/main/logdir -s
	augtool set /files/etc/puppet/puppet.conf/main/vardir /var/lib/puppet -s
	
	res=$(augtool defnode certname /files/etc/puppet/puppet.conf/main/certname $(if [[ -z "$(facter fqdn)" ]]; then echo "localhost"; else $(facter fqdn);fi) -s)
	log $res
	augtool defnode storeconfigs /files/etc/puppet/puppet.conf/master/storeconfigs true -s
	augtool defnode storeconfigs_backend /files/etc/puppet/puppet.conf/master/storeconfigs_backend puppetdb -s
#augtool defnode dbadapter /files/etc/puppet/puppet.conf/master/dbadapter mysql -s
#augtool defnode dbname /files/etc/puppet/puppet.conf/master/dbname puppet -s
#augtool defnode dbuser /files/etc/puppet/puppet.conf/master/dbuser puppet -s
#augtool defnode dbpassword /files/etc/puppet/puppet.conf/master/dbpassword puppet -s
#augtool defnode dbsocket /files/etc/puppet/puppet.conf/master/dbsocket /var/lib/mysql/mysql.sock -s
#augtool defnode dbserver /files/etc/puppet/puppet.conf/master/dbserver $puppetDB -s
	augtool defnode reports /files/etc/puppet/puppet.conf/master/reports "store,puppetdb" -s
#	augtool defnode reports /files/etc/puppet/puppet.conf/master/reports "store,http" -s
#	augtool defnode reporturl /files/etc/puppet/puppet.conf/master/reporturl "http://${myIP,,}:3000/reports/upload" -s
#augtool defnode node_terminus /files/etc/puppet/puppet.conf/master/node_terminus exec -s
#echo -e "defnode external_nodes /files/etc/puppet/puppet.conf/master/external_nodes '/usr/bin/env PUPPET_DASHBOARD_URL=http://${myIP,,}:3000 /usr/share/puppet-dashboard/bin/external_node'"|augtool -s
#augtool defnode fact_terminus /files/etc/puppet/puppet.conf/master/fact_terminus inventory_active_record -s
	augtool defnode environmentpath /files/etc/puppet/puppet.conf/master/environmentpath \$confdir/environments -s
#	augtool defnode modulepath /files/etc/puppet/puppet.conf/master/modulepath \$confdir/environments/\$environment/modules -s
#	augtool defnode manifest /files/etc/puppet/puppet.conf/master/manifest \$confdir/environments/\$environment/manifests/unknown_environment.pp -s
#	augtool defnode manifest /files/etc/puppet/puppet.conf/production/manifest \$confdir/environments/\$environment/manifests/site.pp -s
#	augtool defnode manifest /files/etc/puppet/puppet.conf/dev/manifest \$confdir/manifests/site.pp -s
	
	augtool defnode hiera_config /files/etc/puppet/puppet.conf/master/hiera_config \$confdir/environments/\$environment/hiera.yaml -s

	mkdir $confdir/environments
	mkdir $confdir/environments/production

	#create autosign.conf in /etc/puppet/
	echo -e "*.$(if [[ -z "$(facter domain)" ]]; then echo "*"; else $(facter domain);fi)" > /etc/puppet/autosign.conf
	log "edited autosign.conf"

	# append in file /etc/puppet/auth.conf
	############## GOES BEFORE last 2 rows
	echo -e "path /facts\nauth any\nmethod find, search\nallow *" >> /etc/puppet/auth.conf
	log "appended stuff in puppet/auth.conf"

	#### START PUPPET MASTER NOW
	service puppetmaster start
	chkconfig puppetmaster on
	
	# Install PUPPETDB
	log "puppetDB"
	puppet resource package puppetdb ensure=latest
	puppet resource service puppetdb ensure=running enable=true
	puppet resource package puppetdb-terminus ensure=latest
		
	# set puppetdb.conf
	echo -e "[main]\nserver = $(facter fqdn)\nport = 8081" > /etc/puppet/puppetdb.conf 
	# set Routes.yaml
	echo -e "master:\n  facts:\n    terminus: puppetdb\n    cache: yaml" > /etc/puppet/routes.yaml

	#Will have to restart puppet master
	service puppetmaster restart
	
	#Setting the environments
	log "setting puppet's environments"
	#recovering the r10k file
	curl -L https://github.com/open-dai/platform/raw/master/scripts/r10k_installation.pp >> /var/tmp/r10k_installation.pp
	#installing git
	ensure_package_installed "git"
#	puppet apply /var/tmp/r10k_installation.pp
	
	
	#INSTALL Mcollective client
	log "Installing MCollective"
	ensure_package_installed "mcollective-client"
	ensure_package_installed "activemq"
	sed -i "s/plugin.psk = unset/plugin.psk = $mc_pwd/g" /etc/mcollective/client.cfg
	sed -i "s/plugin.stomp.host = localhost/plugin.stomp.host = puppet.courtyard.cloudlabcsi.eu/g" /etc/mcollective/client.cfg
	sed -i "s/plugin.stomp.port = 61613/plugin.stomp.port = 6163/g" /etc/mcollective/client.cfg
	sed -i "s/plugin.stomp.password = secret/plugin.stomp.password = $mc_stomp_pwd/g" /etc/mcollective/client.cfg

	#Modify /etc/activemq/activemq.xml
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/transportConnectors/transportConnector[2]/#attribute/uri stomp+nio://0.0.0.0:6163"|augtool -s
	echo -e "set /augeas/load/activemq/lens Xml.lns\nset /augeas/load/activemq/incl /etc/activemq/activemq.xml\nload\nset /files/etc/activemq/activemq.xml/beans/broker/plugins/simpleAuthenticationPlugin/users/authenticationUser[2]/#attribute/password $mc_stomp_pwd"|augtool -s


	#INSTALL Zabbix
	log "Installing Zabbix server"
	ensure_package_installed "zabbix-server-pgsql"
	ensure_package_installed "zabbix-web-pgsql"
	zabbixDBuser=zabbix
	zabbixBDpwd=zabbix
	
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE USER $zabbixDBuser WITH PASSWORD '$zabbixBDpwd';"
	sudo -u postgres PGPASSWORD=$postgres_pwd psql -c "CREATE DATABASE zabbix OWNER $zabbixDBuser;"
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/schema.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/images.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	cat /usr/share/doc/$(rpm -qa --qf "%{NAME}-%{VERSION}" zabbix-server-pgsql)/create/data.sql | sudo -u postgres PGPASSWORD=$zabbixBDpwd psql -U zabbix zabbix
	
	augtool defnode DBHost /files/etc/zabbix/zabbix_server.conf/DBHost '' -s
	augtool set /files/etc/zabbix/zabbix_server.conf/DBName zabbix -s
	augtool set /files/etc/zabbix/zabbix_server.conf/DBUser $zabbixDBuser -s
	augtool defnode DBPassword /files/etc/zabbix/zabbix_server.conf/DBPassword $zabbixBDpwd -s
	
}

#execute the tasks
start-opendai | tee /root/all.log