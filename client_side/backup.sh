#!/bin/bash

################################################################################
##                    "Old school" Backup over rsync script                   ##
################################################################################
## This script needs some configuration files to know what, how and where     ##
## Backups are done.                                                          ##
## TO AVOID RIGHT ISSUES ON FILES TO BACKUP THIS SCRIPT MUST BE RUN AS ROOT.  ##
################################################################################

show_usage() {
	
	cat <<EOF
usage : $0 [options]

This script backups defined files and/or mysql files and/or dump

OPTIONS :
	-h		: Show this message
	-a 		: backup all datas defined in the configuration file (default if no option)
	-f 		: backup only files defined in backup.include-files file
	-F		: same as -fM
	-m		: backup mysql file and dump
	-M		: backup mysql files (path for this files must be 
			  registered in the configuration file)
	-D		: create and backup a dump of the entire mysql databases
			  (on some linux distrubution or for personnal reason
			  you may have to enter mysql credentials in config file)
	-d		: activate debug 
	-R		: report results on remote server as empty BKP_OK file if the backup
			  has finished properly and a BKP_WARN file containing messages if some
			  non critical issues appends during the backup.

Default options set if no options are specified (use for automatic backups) are -aR.
If only -d debug option is specified, options -aR are automatically added
EOF
	exit 0
}

test_connection(){
	if [[ $(nc -z ${rsyncserver} 873; echo $?) -ne 0 ]] ; then
		fatal_error "Unable to connect to backup server. Backup aborted"
	fi
}

fatal_error(){
	logger -s -p local1.err -t backup -- $@
	exit 1
}

debugger() {
	if [[ $debug -eq "1" ]]; then
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
	rsync -avPAXWR --password-file ${rsyncsecretfile} --delete-after \
	--files-from=${files2backup} --exclude-from=${exclusions} \
	/ ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
	result=$?
	if [[ ${result} -ne 0 ]] ; then
		msg="${host} files have not been properly backuped. See logs on remote server" 
		echo ${msg} >> /tmp/BKP_WARN
		log_warn "cannot backup files on server. rsync error = ${result}"
		unset msg
		unset result
		return 1
		else log_info "files backup finished properly"
		return 0
	fi	
}

mysql_backup() {
	if [[ ${makedump} -eq 1 ]] ; then
		mysql_dump
		if [[ $? -ne 0 ]] ; then
		mysqlresult="${host} dump backup failed. See logs on remote server"
		fi
	fi
	if [[ ${backupfiles} -eq 1 ]] ; then 
		mysql_files
		if [[ $? -ne 0 ]] ; then
		mysqlresult="${host} file backup failed. See logs on remote server\n${mysqlresult}"
		fi
	fi
	if [[ -z ${mysqlresult} ]] ; then
		return 0
	else
		echo -e ${mysqlresult} >> /tmp/BKP_WARN
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
		log_warn ${msg}
		return 1
	fi
	mysqldump -AYciae --add-drop-database --add-drop-table --flush-privileges \
	--user=${mysqluser} --password=${mysqlpassword} > ${dumpfile}
	if [[ $? -eq 0 ]] ; then 
		log_info "mysql dump file created at ${dumpfile}"
		rsync -avP --password-file ${rsyncsecretfile} ${dumpfile} \
		${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
		tmpresult=$?
		if [[ ${tmpresult} -eq 0 ]] ; then
			log_info "mysql dump file successfully backuped"
			rm ${dumpfile}
			unset tmpresult
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
		return 0
	else
		log_warn "cannot backup mysql files. rsync error = ${tmpresult}"
		unset tmpresult
		return 1
	fi
}

report_result() {
	if [[ -e /tmp/BKP_WARN ]] ; then 
		lasttransfert="1"
		while [[ ${lasttransfert} -ne 0 ]] ; do
			rsync -avP --password-file ${rsyncsecretfile} /tmp/BKP_WARN ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
			lasttransfert=$?
		done
		rm /tmp/BKP_WARN
		exit 42
	else 
		touch /tmp/BKP_OK
		lasttransfert="1"
		while [[ ${lasttransfert} -ne 0 ]] ; do
			rsync -avP --password-file ${rsyncsecretfile} /tmp/BKP_OK ${rsyncuser}@${rsyncserver}::${rsyncmodule}/${backup_dir}
			lasttransfert=$?
		done
		rm /tmp/BKP_OK
		exit 0
	fi
}

################################################################################
##                        SCRIPT CORE BEGINNING                               ##
################################################################################

local_path=$(pwd)
if [[ -e ${local_path}/backup.conf ]] ; then
	source ${local_path}/backup.conf
	echo "source ${local_path}/backup.conf"
else 
	fatal_error "configuration file is missing"
fi

# Setting default requested backup to backup all datas configured in configuration file.
requested_backup="default"

while getopts ${optchars} options ; do
	case ${options} in
		h) 
			show_usage 
		;;
		a) 
			requested_backup="all" 
		;;
		f) 
			requested_backup="data" 
		;;
		F) 
			requested_backup="allfiles" 
		;;
		m) 
			requested_backup="allmysql"
		;;
		M) 
			requested_backup="mysqlfiles"
		;;
		D) 
			requested_backup="mysqldump"
		;;
		d)
			if [[ debug -ne 1 ]] ; then 
				debug=1
			fi
		;;
		R)
			report=1
		;;
		\?) 
			show_usage
		;;
	esac
done

if [[ $debug -eq 1 ]] ; then 
	set -x
fi

case $requested_backup in
	all)
		file_backup
		mysql_backup
	;;
	default)
		file_backup
		mysql_backup
		report=1
	;;
	data)
		file_backup
	;;
	allfiles)
		file_backup
		mysql_files
	;;
	allmysql)
		mysql_backup
	;;
	mysqlfiles)
		mysql_files
	;;
	mysqldump)
		mysql_dump
	;;
esac

if [[ ${report} -eq 1 ]] ; then
	report_result
fi
