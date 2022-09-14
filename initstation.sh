#!/bin/bash
##########################################################################
#
# Fix error: too many login attempts, by removing station locks.
#    Copyright (C) 2022  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Name:       initstation.sh
# Purpose:    This script will find and remove the lock file for a staff machine. It is meant
#             to be used when they get a 'too many tries' while trying to log into a station
#             with WF.
# Method:     The algorithm comes from the Sirsi-Dynix support site; solution 33525. Manually:
#             We receive a communication failure error or are unable to connect to WorkFlows using a named workstation.
#             We can log in using a floating workstation, e.g., PCGUI-DISP.
#
#             SOLUTION DETAILS:
#
#             For a UNIX server:
#
#             1. Log onto the server as the sirsi user and identify the locked workstation.
#             a. cd `gpn config`
#             b. grep ^STAT admin
#             c. identify the problem named station and note the key of that station in the second piped field of the line, e.g.,
#
#             STAT|36|MAINCIRC|wsgui|PC Graphical User Interface|1|1|2|2|1||0|2|0|
#
#             2. Go to the cd Unicorn/Locks/Stations directory.
#             3. In the Unicorn/Locks directory you will find a file called '.MAINCIRC.36'.
#             4. Kill the process that matches the PID found in the file in step 3, it is an mserver listener.
#             5. Remove the lock file for the station (it will be the key you obtained from the admin file), e.g.,
#             rm 36
# This is equivalent to:
#             1. Log onto the unicornadmin utility by typing either "gosirsi" or "sirsi `gpn config`/environ vt100",
#              and then entering the PIN for the sirsi user at the prompt.
#             2. Select Unicornadmin from the main menu.
#             3. Select Initialize, then Stations, then Symphony stations.
#             4. Find the workstation policy in the list, e.g., MAINCIRC, and initialize it.
#
#             Users should now be able to use the named workstation.
#
# Notes: 
# Station locks are simply a file that contains '1' and is named after the station ID number.
# For example, station ILS002 has an ID number of 1806 in Config/admin.
# sirsi@edpl:~/Unicorn/Locks$ cat Stations/2307
#    1
# sirsi@edpl:~/Unicorn/Locks$ cat Stations/2307 | od -xa
# 0000000    2020    2020    0a31
#          sp  sp  sp  sp   1  nl
#
# Lock locks are dot files '.' of the user login name, and the station ID number and contain the process ID
# Here is how they are listed:
#       UserLogin.StationID (from Stations/*)
# ls -a .HIGCIRC.2584  .MEACIRC.2423  .MBENNET.2907 .SIPCHK.2885 .SMTCHT.2830
#       .HIGCIRC.2590  .MEACIRC.2424  .SIPCHK.17    .SIPCHK.2887 .SMTCHT.2831
#       .HIGCIRC.2591  .MEACIRC.2425  .SIPCHK.22    .SIPCHK.2888 .SMTCHT.2832
#       .HIGCIRC.2592  .MEACIRC.2426  ... etc.
#
# sirsi@edpl:~/Unicorn/Locks/Users$ cat ../.MBENNETT.2907
# 60944
# sirsi@edpl:~/Unicorn/Locks/Users$ ps aux | grep 60944 | grep mserver
# sirsi     60944  0.0  0.0 273396 16716 ?        S    08:15   0:00 mserver 4 198.161.203.39
# sirsi@edpl:~/Unicorn/Locks/Users$ grep 2907 ~/Unicorn/Config/admin
# 
# Some stations are logged in and have station locks, but are not found in ~/Unicorn/Config/admin
# 
#
# User locks are:
# User ID                 How Many Logged In
# -------                 ------------------
# ABBCIRC                     4
# ADMIN                       2
# CALCIRC                     5
# CLVCIRC                     3
# CPLCIRC                     3
# CSDCIRC                     5
# HIGCIRC                     6 
# lock file name uses the "encoded user key", which can be looked up by "seluser -iJ", e.g.,
# echo b26 | seluser  -iJ -oBUD
# ABBCIRC|126|EPLABB CIRC User|
# They look like: -rw-r--r-- 1 sirsi staff 6 Aug 18 10:51 f51609
# Essentially, the first character is based on the first digit where b is 1, c is 2, d is 3...... j is 9,
# then all the other digits are just the same value. For example, b26 would be for user key 126 or f728
# would be for user key 5728
#
# There seems to be 2 ways to update the User keys, 
# 1) decrement the value and overwrite the file.
# 2) audit the running processes and determine which locks can be deleted.
# sudo-code:
# func decr(string):
#    local loginId = $1
#    local whichUserLock = $(echo loginId | seluser -iB -oJ)
#    Users/whichUserLock--
#    if Users/whichUserLock < 1:
#        rm Users/whichUserLock
#    return
# func clean_station(string):
#    local stationId = $1
#    local userId = LOGINNAME
#    rm Locks/.LOGINNAME.stationId
#    rm Stations/stationId
#    decr(LOGINNAME)
# for each station_lock in Stations/*:
#    process = cat Locks/.LOGINNAME.station_lock
#    if process exists:
#        if kill process:
#            clean_station(station_lock)
#        else:
#            show warning.
#            continue
#    else:
#         clean_station(station_lock)
# end
#
# Author:     Andrew Nisbet
# Date:       December 30, 2013
# Rev date:   September 14, 2022
#
############################################################################################

VERSION="1.03.00"
CONFIG_DIR=`getpathname config`
ADMIN_FILE=$CONFIG_DIR/admin
LOCKS_DIR=~/Unicorn/Locks
STATION_LOCKS_DIR=$LOCKS_DIR/Stations
WORKING_DIR=/software/EDPL/Unicorn/EPLwork/Initstations
APP=$(basename -s .sh $0)
DEBUG=false
LOG=$WORKING_DIR/$APP.log
CALLER_LOG="/dev/null"
STATION_LOCK_FILES=()
SHOW_VARS=false
SHOW_LOCKED_STATIONS=false
TRUE=0
FALSE=1
FORCE=false
###############################################################################
# Display usage message.
# param:  none
# return: none
usage()
{
    cat << EOFU!
Usage: $APP [-option]
 
 -d, --debug turn on debug logging and preserves temp files.
 -f, --force Kill any existing station processes if running.
 -h, --help: display usage message and exit.
 -l, --log_file={/foo/bar.log}: Log transactions to an additional log, like the caller's log file.
     After this is set, all additional messages from $APP will ALSO be written to \$CALLER_LOG which
     is $CALLER_LOG by default.
 -L, --List: Display all stations currently logged in.
 -r, --remove_all_locks: Removes all orphaned lock files. Stations that are connected cannot have 
     their lock files removed.
 -s, --station={WMC004}: Unlock the station with the given name, partial names are allowed.
     For example, --station=WMC will try and unlock all stations at that branch.
 -v, --version: display application version and exit.
 -V, --VARS: Display all set variables.
 -x, --xhelp: display usage message and exit.

Examples:
# Run $APP on Production
# List stations that are logged in.
initstations.sh -L (or --List)

EOFU!
	exit 1
}

# Logs messages to STDOUT and $LOG file.
# param:  Message to put in the file.
# param:  (Optional) name of a operation that called this function.
logit()
{
    local message="$1"
    local time=$(date +"%Y-%m-%d %H:%M:%S")
    # If run from an interactive shell message STDOUT and LOG.
    echo -e "[$time] $message" | tee -a $LOG -a $CALLER_LOG
}
# Logs messages with special error prefix.
logerr()
{
    local message="$1"
    local time=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$time] **error: $message" | tee -a $LOG -a $CALLER_LOG
    exit 1
}
# Display the variables that are set.
show_vars()
{
	logit "\$APP=$APP"
	logit "\$CONFIG_DIR=$CONFIG_DIR"
	logit "\$ADMIN_FILE=$ADMIN_FILE"
	logit "\$LOCKS_DIR=$LOCKS_DIR"
	logit "\$STATION_LOCKS_DIR=$STATION_LOCKS_DIR"
	logit "\$WORKING_DIR=$WORKING_DIR"
	logit "\$VERSION=$VERSION"
	logit "\$DEBUG=$DEBUG"
	logit "\$LOG=$LOG"
	logit "\$CALLER_LOG=$CALLER_LOG"
	logit "\$SHOW_LOCKED_STATIONS=$SHOW_LOCKED_STATIONS"
	logit "\$STATION_LOCK_FILES[]=${STATION_LOCK_FILES[@]}"
	logit "\$FORCE=$FORCE"
}

# Takes the users login name and decrements the number of logged in users in the file.
# param: user login name like MBENNETT or CMACIRC.
_decr_user_lock()
{
	local user_id=$1
	# Find the user's 'encoded' ID
	local user_lock_file_name=$(echo $user_id | seluser -iB -oJ 2>/dev/null | pipe.pl -oc0)
	# echo "   16" >test
	# ilsdev@ilsdev1:~/projects/initstation$ cat test | pipe.pl -3c0:-1 -pc0:5.\\s >tmp
	# ilsdev@ilsdev1:~/projects/initstation$ mv tmp test
	# ilsdev@ilsdev1:~/projects/initstation$ cat test
	#    15
	# ilsdev@ilsdev1:~/projects/initstation$ cat test | od -ax
	# 0000000  sp  sp  sp   1   5  nl
	# 		2020    3120    0a35
	local user_lock_file=$LOCKS_DIR/Users/$user_lock_file_name
	if [ -f "$user_lock_file" ]; then
		tmp=$WORKING_DIR/tmp.$$
		cat $user_lock_file | pipe.pl -3c0:-1 -pc0:5.\\s >$tmp
		local user_count=$(cat $tmp | pipe.pl -tc0)
		[ "$DEBUG" == true ] && logit "user count for user lock file now: $user_count"
		if (( $user_count < 1 )); then
			[ "$DEBUG" == true ] && logit "removing the user lock $user_lock_file"
			rm $tmp $user_lock_file
		else
			[ "$DEBUG" == true ] && logit "updating the user lock $user_lock_file"
			mv $tmp $user_lock_file
		fi
	else
		logit "$user_id doesn't have a User lock"
	fi
}

# Inits a station by a given name provided as a parameter.
# param:  station id as read from the file name of the station lock.
#         Looks like: 1806 for station 1806 (ILS002)
init_station()
{
	local station_id_file=$1
	# Find the station name from the admin file.
	local station_name=`grep $station_id_file $ADMIN_FILE | cut -d\| -f3 2>/dev/null`
	# Check for the lock in the lock directory.
	if [[ -e "$STATION_LOCKS_DIR/$station_id_file" ]]; then
		# Find the process id (2207) from a matching file in ~/Unicorn/Locks directory, like .CMATMP.2207
		local mserver_file=$(ls -a -C1 $LOCKS_DIR | grep $station_id_file 2>/dev/null)
		if [ -z "$mserver_file" ]; then
			logit "couldn't find the process id file for $station_name, but cleaning up the station lock."
			rm $STATION_LOCKS_DIR/$station_id_file
			# Nothing else to do since we aren't sure if the User locks contains a count for a process that doesn't exist.
			return
		fi
		local which_user=$(echo $mserver_file | pipe.pl -W'\.' -oc1)
		mserver_file=$LOCKS_DIR/$mserver_file
		# The process ID can be found in that file.
		local process_id=$(cat $mserver_file)
		if [ -z "$process_id" ]; then
			logit "couldn't find the process id in $mserver_file so cleaning up the file."
			[ "$DEBUG" == true ] && logit "removing $mserver_file"
			rm -f $mserver_file
			[ "$DEBUG" == true ] && logit "removing $STATION_LOCKS_DIR/$station_pid"
			rm $STATION_LOCKS_DIR/$station_pid 2>/dev/null
			return
		fi
		# If there was a process running, kill it only if --force 
		# is used. Without it the mserver file will remain with the process
		# running but the rest of the files will be cleaned up.
		if [ "$FORCE" == true ]; then
			[ "$DEBUG" == true ] && logit "killing $process_id"
			kill $process_id
			[ "$DEBUG" == true ] && logit "removing $mserver_file"
			rm -f $mserver_file 2>/dev/null
		fi
		# Clean up.
		[ "$DEBUG" == true ] && logit "removing $STATION_LOCKS_DIR/$station_pid"
		rm $STATION_LOCKS_DIR/$station_pid 2>/dev/null
		# Decrement user count in Users/lock file.
		_decr_user_lock $which_user
	else
		logit "No lock file found for '$station_name'"
	fi
}

### Check input parameters.
# $@ is all command line parameters passed to the script.
# -o is for short options like -v
# -l is for long options with double dash like --version
# the comma separates different long options
# -a is for long options with single dash like -version
options=$(getopt -l "debug,force,help,log:,List,remove_all_locks,station:,VARS,version,xhelp" -o "dfhl:Lrs:Vvx" -a -- "$@")
if [ $? != 0 ] ; then logit "Failed to parse options...exiting." >&2 ; exit 1 ; fi
# set --:
# If no arguments follow this option, then the positional parameters are unset. Otherwise, the positional parameters
# are set to the arguments, even if some of them begin with a ‘-’.
eval set -- "$options"
while true
do
    case $1 in
    -d|--debug)
        logit "turning on debugging"
		DEBUG=true
		;;
    -f|--force)
		[ "$DEBUG" == true ] && logit "forcing removal of locks"
        FORCE=true
        ;;
	-h|--help)
        usage
        ;;
    -l|--log_file)
		shift
        [ "$DEBUG" == true ] && logit "adding logging to '$1'"
        if [ -f "$1" ]; then
		    APP_LOG="$1"
        else
            # Doesn't exist but try to create it.
            if touch $1; then
                logit "$1 added as a logging destination."
                APP_LOG="$1"
            else # Otherwise just keep settings as they are and report issue.
                logerr "file '$1' not found, and failed to create it. Logging unchanged."
            fi
        fi
		;;
	-L|--List)
		[ "$DEBUG" == true ] && logit "listing all stations reported connected to the ILS."
		SHOW_LOCKED_STATIONS=true
		;;
	-r|--remove_all_locks)
		[ "$DEBUG" == true ] && logit "request to remove all un-used locks."
		# Ignore files that have names longer than 4 characters. They may be someone else's.
		count=$(ls -C1 --ignore='?????*' $STATION_LOCKS_DIR | wc -l)
		STATION_LOCK_FILES=$(ls -C1 --ignore='?????*' $STATION_LOCKS_DIR)
		logit "there are $count station locks"
		;;
	-s|--station)
		shift
		[ "$DEBUG" == true ] && logit "checking station '$1'"
		if (( $(grep $1 $ADMIN_FILE | wc -l) > 1 )); then
			logit "multiple station matches for $1: "
			for station_details in $(grep $1 $ADMIN_FILE | cut -d\| -f3); do
				logit "  $station_details"
			done
		fi
		station_id=$(grep $1 $ADMIN_FILE | cut -d\| -f2)
		if [ -z "$station_id" ]; then
			logit "'$1', no such station registered in the ILS."
		else
			STATION_LOCK_FILES+=$station_id
		fi
		;;
    -v|--version)
        logit "$0 version: $VERSION"
		exit 0
        ;;
	-V|--VARS)
		[ "$DEBUG" == true ] && logit "var display turned on"
        SHOW_VARS=true
        ;;
    -x|--xhelp)
        usage
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
logit "== starting $APP version: $VERSION"
# : ${INPUT_FILE:?Missing -i,--input}
[ -s "$ADMIN_FILE" ] || { logerr "can't find the configuration file in '$ADMIN_FILE'"; exit 1; }
[ "$SHOW_VARS" == true ] && show_vars
if [ "$SHOW_LOCKED_STATIONS" == true ]; then
	logit "the following station locks are lingering:"
	for some_pid in $(ls -C1 --ignore='?????*' $STATION_LOCKS_DIR); do
		grep $some_pid $ADMIN_FILE | cut -d\| -f3 2>/dev/null
	done
fi
(( ${#STATION_LOCK_FILES[@]} > 0 )) || { logit "nothing to do."; exit 0; }
for station_id in ${STATION_LOCK_FILES[@]}; do
	init_station $station_id
done
# EOF
