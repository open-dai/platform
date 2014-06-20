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
	rpm -ivh http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-7.noarch.rpm
	#add RPMFORGE repository
	rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.2-2.el6.rf.x86_64.rpm
	#add EPEL repository
	rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
	#zabbix repos
	rpm -ivh http://repo.zabbix.com/zabbix/2.2/rhel/6/x86_64/zabbix-release-2.2-1.el6.noarch.rpm
	log $(yum check-update)
	
	log "Cloudstack stuff"
	#First cloudstack recover virtual router IP
	server_ip=$(cat /var/lib/dhclient/dhclient-eth0.leases | grep dhcp-server-identi
	fier | tail -1| awk '{print $NF}' | tr '\;' ' ')
	server_ip2=${server_ip:0:${#server_ip}-1}
	log "Cloudstsack virtual router" $server_ip2
	userdata=$(curl http://$server_ip2/latest/user-data)
	log "userdata:" $userdata

	#transform userdata in env vars
	eval $userdata
	
	if [[ -z "$timezione" ]]; then timezione='Rome'; fi
	
	
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

	
}

#execute the tasks
start-opendai