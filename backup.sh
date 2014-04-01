#!/bin/bash

################################################################################
##                    "Old school" Backup over rsync script                   ##
################################################################################
## This script needs some configuration files to know what, how and where     ##
## Backups are done.                                                          ##
## TO AVOID RIGHT ISSUES ON FILES TO BACKUP THIS SCRIPT MUST BE RUN AS ROOT.  ##
################################################################################

source ./backups.conf

function debugger() {
	if [[ $debug == 1 ]]; then
		logger -p local1.debug -t backups -- $@
	}

function create_dest_dir() {
	# function to create unexisting directory on backup server.
	if [[ $@ >> 1 ]] ; then
		
	rsync /dev/null rsync@msvc-bkp::BACKUPS/$1
	}

function pre_backup() {
	
	}

function backup_rotate() {
	# First we verify if there is a backup to rotate
	
	}

function backup() {
	
	}

function mysql_backup() {
	
	}
