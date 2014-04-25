#!/bin/bash

################################################################################
##                    "Old school" Backup over rsync script                   ##
################################################################################
## This script needs some configuration files to know what, how and where     ##
## Backups are done.                                                          ##
## TO AVOID RIGHT ISSUES ON FILES TO BACKUP THIS SCRIPT MUST BE RUN AS ROOT.  ##
################################################################################

local_path=$(pwd)
source ${local_path}/backup.conf

usage() {
	
	cat <<EOF
	
usage : $0 options

This script backups defined files and/or mysql files and/or dump

OPTIONS :
	-h		: Show this message
	-a 		: backup all datas defined in the configuration file
	-f 		: backup only files defined in backup.include-files file
	-F		: same as -fn
	-m		: backup mysql file and dump
	-n		: backup mysql files (path for this files must be 
			  registered in the configuration file)
	-o		: create and backup a dump of the entire mysql databases
			  (on some linux distrubution or for personnal reason
			  you may have to enter mysql credentials in config file)
	-d 		: run script in debug mode"
EOF
}

if [[ $debug -eq 1 ]] ; then 
	set -nx
fi

backup

if [[ $debug -eq 1 ]] ; then 
	set +nx
fi

fatal_error(){
	logger -s -p local1.err -t backup -- $@
	exit 1
}

debugger() {
	if [[ $debug == "1" ]]; then
		logger -s -p local1.debug -t backup -- $@
	fi
}

log_warn() {
	logger -s -p local1.warn -t backup -- $@
}

log_info() {
	logger -s -p local1.info -t backup -- $@
}

file_backup() {
	if [[ $(nc -z ${rsyncserver} 873; echo $?) -ne 0 ]] ; then
		fatal_error "Unable to connect to backup server. Backup aborted"
	fi
	rsync -avPAXWR --password-file ${rsyncsecretfile} --delete-after \
	--from-file=${files2backup} --exclude-from=${exclusions} \
	${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
	if [[ $? -ne 0 ]] ; then
		msg="files have not been properly backuped" 
		echo ${msg} >> /tmp/BKP_WRN
		log_warn ${msg}
		unset msg
		return 1
		else loginfo "files backup finished properly"
		return 0
	fi	
}

mysql_backup() {
	if [[ ${makedump} -eq 1 ]] ; then
		mysql_dump
		if [[ $? -ne 0 ]] ; then
		mysqlresult="dump backup failed"
		fi
	fi
	if [[ ${backupfiles} -eq 1 ]] ; then 
		mysql_files
		if [[ $? -ne 0 ]] ; then
		mysqlresult="file backup failed\n${mysqlresult}"
		fi
	fi
	if [[ -z ${mysqlresult} ]] ; then
		return 0
	else
		echo -e ${mysqlresult} >> /tmp/BKP_WRN
		unset mysqlresult
		return 1
	fi
}

mysql_dump() {
	if [[ -e /etc/mysql/debian.cnf ]] && [[ ${force_mycredentials} -eq 0 ]] ; then
		mysqluser=$(grep user /etc/mysql/debian.cnf | head -n 1 | awk '{print $3}')
		mysqlpassword=$(grep password /etc/mysql/debian.cnf | head -n 1 | awk '{print $3}')
	fi
	if [[ -z ${mysqluser} ]] || [[ -z ${mysqlpassword} ]] ; then
		msg="no valid credentials for mysql db connection msyqldump stopped"
		log_warn ${$msg}
		return 1
	fi
	mysqldump -AYciae --add-drop-database --add-drop-table --flush-privileges \
	-u ${mysqluser} -p ${mysqlpassword} > ${dumpfile}
	if [[ $? -eq 0 ]] ; then 
		log_info "mysql dump file created at ${dumpfile}"
		rsync -avP --password-file ${rsyncsecretfile} ${dumpfile} \
		${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
		tmpresult=$?
		if [[ ${tmpresult} -eq 0 ]] ; then
			log_info "mysql dump file successfully backuped"
			rm ${dumpfile}
			return 0
		else
			log_warn "cannot upload mysql dump file. rsync error = ${tmpresult}"
			unset tmpresult
			return 1
		fi
	else 
		log_warn "can't create dumpfile"
		return 1
	fi
}

mysql_files() {
	if [[ -z ${mysqlpath} ]] ; then
# put /var/lib/mysql as default mysql path because this is true for most package installation in most distributions
		mysqlpath="/var/lib/mysql" 
	fi
	rsync -avPAXWR --password-file ${rsyncsecretfile} --delete-after ${mysqlpath}\
	${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
	tmpresult=$?
	if [[ ${tmpresult} -eq 0 ]] ; then
		log_info "mysql files successfully backuped"
		rm ${dumpfile}
		return 0
	else
		log_warn "cannot backup mysql files. rsync error = ${tmpresult}"
		unset tmpresult
		return 1
	fi
}

touch /tmp/BKP_OK
rsync -avP --password-file ${rsyncsecretfile} /tmp/BKP_OK ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}

