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
# Author:     Andrew Nisbet
# Date:       December 30, 2013
# Rev date:   August 11, 2022
#
############################################################################################

CONFIG_DIR=`getpathname config`
ADMIN_FILE=$CONFIG_DIR/admin
STATION_LOCKS_DIR=~/Unicorn/Locks/Stations
WORKING_DIR=/software/EDPL/Unicorn/EPLwork/Initstations
VERSION="1.00.05"
APP=$(basename -s .sh $0)
DEBUG=false
LOG=$WORKING_DIR/$APP.log
CALLER_LOG="/dev/null"
STATION_LOCK_FILES=()
SHOW_VARS=false
SHOW_LOCKED_STATIONS=false
TRUE=0
FALSE=1
###############################################################################
# Display usage message.
# param:  none
# return: none
usage()
{
    cat << EOFU!
Usage: $APP [-option]
 
 -d, --debug turn on debug logging and preserves temp files.
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
	logit "\$CONFIG_DIR=$CONFIG_DIR"
	logit "\$STATION_LOCKS_DIR=$STATION_LOCKS_DIR"
	logit "\$WORKING_DIR=$WORKING_DIR"
	logit "\$VERSION=$VERSION"
	logit "\$APP=$APP"
	logit "\$DEBUG=$DEBUG"
	logit "\$LOG=$LOG"
	logit "\$CALLER_LOG=$CALLER_LOG"
}

# Asks if user would like to do what the message says.
# param:  message string.
# return: 0 if the answer was yes and 1 otherwise.
confirm()
{
	if [ -z "$1" ]; then
		echo "** error, confirm_yes requires a message." >&2
		exit $FALSE
	fi
	local message="$1"
	read -p "$message? y/[n]: " answer < /dev/tty
	case "$answer" in
		[yY])
			echo "yes selected." >&2
			echo $TRUE
			;;
		*)
			echo "no selected." >&2
			echo $FALSE
			;;
	esac
}

# Inits a station by a given name provided as a parameter.
# param:  station id as read from field 2 of Config/admin file.
init_station()
{
	local station_id_file=$1
	# Find the station name from the admin file.
	local station_name=`grep $station_id_file $ADMIN_FILE | cut -d\| -f3 2>/dev/null`
	if [[ ! "$station_name" ]]; then
		logit "*warn: no '$station_name' listed in '$ADMIN_FILE'."
		# Doesn't mean we can't try to remove any lock any way.
	fi
	# Check for the lock in the lock directory.
	if [[ -e "$STATION_LOCKS_DIR/$station_id_file" ]]; then
		# Find the process id (2207) from a matching file in ~/Unicorn/Locks directory, like .CMATMP.2207
		local mserver_file=$(ls -a -C1 ~/Unicorn/Locks | grep $station_id_file 2>/dev/null)
		[ -z "$mserver_file" ] && { logit "couldn't find the process id file for $station_name"; return; }
		mserver_file=~/Unicorn/Locks/$mserver_file
		# The process ID can be found in that file.
		local process_id=$(cat $mserver_file)
		[ -z "$process_id" ] && { logit "couldn't find the process id in $mserver_file"; return; }
		local running_process=$(ps aux | pipe.pl -W'\s+' -oc1 | grep "$process_id" 2>/dev/null)
		if [ -z "$running_process" ]; then
			logit "the ${station_name}'s mserver is not running."
			# on to clean up.
		else
			logit "the ${station_name}'s mserver session is still running!"
			local answer=$(confirm "kill the process ")
			if [ "$answer" == "$TRUE" ]; then
				logit "killing process $running_process"
				kill -9 "$running_process"
			else
				logit "not touching $running_process"
				# and exit before anthing else gets done.
				return
			fi
		fi
		# Clean up.
		rm -f $STATION_LOCKS_DIR/$station_pid 2>/dev/null
		logit "clean up complete."
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
options=$(getopt -l "debug,help,log:,List,remove_all_locks,station:,VARS,version,xhelp" -o "dhl:Lrs:Vvx" -a -- "$@")
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
		STATION_LOCK_FILES=( $(ls -C1 --ignore='?????*' $STATION_LOCKS_DIR) )
		logit "there are ${#STATION_LOCK_FILES[@]} station locks"
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
	logit "the ILS thinks the following stations are connected:"
	for some_pid in $(ls -C1 --ignore='?????*' $STATION_LOCKS_DIR); do
		grep $some_pid $ADMIN_FILE | cut -d\| -f3 2>/dev/null
	done
fi
(( ${#STATION_LOCK_FILES[@]} > 0 )) || { logit "nothing to do."; exit 0; }
for station_id in ${STATION_LOCK_FILES[@]}
do
	init_station $station_id
done
