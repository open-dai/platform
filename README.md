platform repository
========

This repository hosts 

* The scripts needed to create the ISO of the Open-DAI project.
* The scripts used during the installation to do the initial configurations.

# ISO generation
There are two folder to be able to generate the Open-DAI master machine and the Open-DAI node machine.
These ISO images will be imported into the CloudStack environment to be used as "template" to create the new VMs and to recreate the Open-DAI environment as explained in [the dedicated page to the project web site](http://open-dai.eu/open-dai-platform-installation/ "platform installation page")
The project started with a CentOS 6.5 minimal.

Steps taken to generate the ISO from the kickstarter file are as follow:

Create a directory to mount your source.
```
mkdir /tmp/mntiso
```
Loop mount the source ISO you are modifying. (Download from Red Hat / CentOS.)
```
mount -o loop /path/to/centos.iso /tmp/mntiso
```
Create a working directory for your customized media.
```
mkdir /tmp/isobuild
```
Copy the source media to the working directory.
```
cd /tmp/isobuild
rsync -av /tmp/mntiso/ .
```
Unmount the source ISO and remove the directory.
```
umount /tmp/mntiso && rmdir /tmp/mntiso
```
Now we cleanup some stuff
```
find . -name TRANS.TBL -exec rm -f {} \; -print
```

Add any package you want to add in the ISO

Prepare the comps.xml file
```
cd repodata
mv 34bae2d3c9c78e04ed2429923bc095005af1b166d1a354422c4c04274bae0f59-c6-minimal-x86_64.xml comps.xml
ls | grep -v comps.xml | xargs rm -rf
ls
comps.xml
```

Recreate the repos
```
cd /tmp/isobuild
export discinfo=$(head -1 .discinfo)
createrepo -u "media://$discinfo" -g repodata/comps.xml /tmp/isobuild
```

Now add the kickstart taken from here
```
cd /tmp/isobuild
mkdir ks
cp /path/to/master/ks.cfg ks.cfg
```

Inside the isolinux directory is a file named “isolinux.cfg”, edit it and change as follows
```
append initrd=initrd.img
to
append initrd=initrd.img ks=cdrom:/ks/ks.cfg
```

Create the ISO
```
cd /tmp/isobuild
mkisofs -r -R -J -T -v -no-emul-boot \
-boot-load-size 4 \
-boot-info-table \
-V "CentOS 6.5 x86_64 Open-DAI Master" \
-p "YOUR NAME HERE" \
-A "CentOS 6.5 x86_64 Custom - 2014/04/21" \
-b isolinux/isolinux.bin \
-c isolinux/boot.cat \
-x "lost+found" \
--joliet-long \
-o CentOS-6.5-x86_64-Odai-Master .

implantisomd5 CentOS-6.5-x86_64-Odai-Master
```
# Installation flow
As can be seen in the kickstarter files at some point it download the configuration script for the appropriate machine that will be executed at first boot.
In this way is possible to customize and modify the first configuration by just modifying the script in GitHub without having to generate a new ISO image or to import something new in the cloud environment.

``` 
curl -L https://github.com/open-dai/platform/raw/master/scripts/start-master.sh >> /root/bootstrap.sh
``` 

This file will be executed only at the first boot of the machine and will:
* for the Master machine
	* setup some basic packages
	* setup Puppet and all the needed software (PuppetDB, the PostgreSQL, Apache the console etc.
* for the node machine
	* setup some basic packages
	* setup the puppet agent
