#!/bin/bash
# version: 3 date: giovedì 13. set.2012

if [ -f /etc/odailock.lck ];
  then
    exit
  else
#Script variables
LOG_FILE=/var/log/odai-startup.log

# Functions useful for the script
function log()
{
    message="$@"
    echo $message
    echo $message >> $LOG_FILE
}

log "Starting the configuration of the Open-DAI Master Machine"
#proper script actions
sleep 20






#create the lock file so this script will not be executed each time at startup
touch /etc/odailock.lck
fi