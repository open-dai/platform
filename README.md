platform repository
========

This repository hosts 

* The scripts needed to create the ISO of the Open-DAI project.
* The scripts used during the installation to do the initial configurations.

# ISO generation
There are two folder to be able to generate the Open-DAI master machine and the Open-DAI node machine.
These ISO images will be imported into the CloudStack environment to be used as "template" to create the new VMs and to recreate the Open-DAI environment as explained in [the dedicated page to the project web site](http://open-dai.eu/open-dai-platform-installation/ "platform installation page")

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
mkdir /tmp/odaiisonew
```
Copy the source media to the working directory.
```
cp -r /tmp/mntiso/* /tmp/odaiisonew/
```
Unmount the source ISO and remove the directory.
```
umount /tmp/mntiso && rmdir /tmp/mntiso
```


# Installation flow
As can be seen in the kickstarter files at some point it download the configuration script for the appropriate machine that will be executed at first boot.
In this way is possible to customize and modify the first configuration by just modifying the script in GitHub without having to generate a new ISO image or to import something new in the cloud environment.

``` 
curl -L https://github.com/open-dai/platform/raw/master/scripts/start-master.sh >> /root/bootstrap.sh
``` 
