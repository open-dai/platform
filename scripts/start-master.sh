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
	
	if [[ -z "$timezone" ]]; then timezone='Rome'; fi
	
	
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

	# Apache
	ensure_package_installed "httpd"
	chkconfig --levels 235 httpd on
	service httpd start
	log "started httpd" $(service httpd status)
	
	# Postgresql
	ensure_package_installed "postgresql-server"
	service postgresql initdb
	service postgresql start
	chkconfig --levels 235 postgresql on
	
	# PHP
	ensure_package_installed "php"

	# Configuration tool Augeas
	ensure_package_installed "augeas"
	

	# Puppet Master
	ensure_package_installed "puppet-server"
	
	
	#Puppet, Dashboard and MCollective
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

	res=$(augtool defnode certname /files/etc/puppet/puppet.conf/main/certname ${myHostname,,} -s)
	log $res
	augtool defnode certname /files/etc/puppet/puppet.conf/main/certname $(facter fqdn) -s
	augtool defnode modulepath /files/etc/puppet/puppet.conf/master/modulepath \$confdir/environments/\$environment/modules -s
	augtool defnode manifest /files/etc/puppet/puppet.conf/master/manifest \$confdir/environments/\$environment/manifests/unknown_environment.pp -s
	augtool defnode hiera_config /files/etc/puppet/puppet.conf/master/hiera_config \$confdir/environments/\$environment/hiera.yaml -s
	augtool defnode manifest /files/etc/puppet/puppet.conf/production/manifest \$confdir/environments/\$environment/manifests/site.pp -s
	augtool defnode manifest /files/etc/puppet/puppet.conf/dev/manifest \$confdir/manifests/site.pp -s
	

	
}

#execute the tasks
start-opendai