#!/bin/bash

################################################################################
##                    "Old school" Backup over rsync script                   ##
################################################################################
## This script needs some configuration files to know what, how and where     ##
## Backups are done.                                                          ##
## TO AVOID RIGHT ISSUES ON FILES TO BACKUP THIS SCRIPT MUST BE RUN AS ROOT.  ##
## This version of script is to use only is rsync server have a mot du jour   ##
## configured.                                                                ##
################################################################################

source ./backup.conf
fatal_error(){
	logger -p local1.err -t backup -- $@
	exit 1
}

debugger() {
	if [[ $debug == "1" ]]; then
		logger -p local1.debug -t backup -- $@
	fi
}

log_info() {
	logger -p local1.info -t backup -- $@
}

create_host_dir() {
	# function to create the main backup directory.
	mkdir /tmp/${host}
	rsync -a --password-file ${rsyncsecretfile} /tmp/${hosts}/ ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${host}
	if [ $? -eq "0" ] ; then
		rm -R /tmp/${host}
	else
		fatal_error "can't create main backup directory for host $host. Exiting"
	fi
}

pre_backup() {
	rsync --list-only --password-file ${rsyncsecretfile} ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${host}
	host_dir_exist=$?
	if [[ first_time_backup -eq 1 ]] ; then 
		create_host_dir
		sed -i 's/first_time_backup=1/first_time_backup=0'
	elif [[ ${host_dir_exist} -ne 0 ]] ; then
		create_host_dir
	fi
	unset host_dir_exist
	log_info "Remote directory for backups has been successfully created"
}

backup_rotate() {
	# First we verify if there is a backup to rotate
	rsync --list-only --password-file ${rsyncsecretfile} ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${dir2remove}/
}

backup() {
	
}

mysql_backup() {
	
}
