#!/bin/bash
##########################################################################
#
# Fix error: too many login attempts, by removing station locks.
#    Copyright (C) 2014  Andrew Nisbet
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
#
############################################################################################

CONFIG=`getpathname config`
LOCKS=~/Unicorn/Locks/Stations
VERSION=0.3

# Make sure the user enters at least a partial station name.
if [ $# -lt 1 ]
then
        echo "$0 version $VERSION"
        echo "usage: $0 <station_01 station_02 ... station_nn>"
        ls -a ~/Unicorn/Locks/ | egrep -e '^\.[A-Z]' # List all the stations logged in.
        exit 1
fi

for stationName in "$@"
do
	if [[ ! -s $CONFIG/admin ]]
	then
		echo "Can't find the configuration file in '$CONFIG/admin'"
		exit 1
	else
		# Find the station number from the admin file.
		STATION=`grep $stationName $CONFIG/admin | cut -d\| -f2`
		if [[ ! $STATION ]]
		then
			echo "Can't find '$stationName' in '$CONFIG/admin'."
			continue
		fi
		# Check for the lock in the lock directory.
		if [[ -e $LOCKS/$STATION ]]
		then
			echo -n "do you want to remove the station's lock? y/n[n]: "
			read answer
			if [ $answer = "y" ] || [ $answer = "Y" ]
			then
				PID_FILE=`ls -a $LOCKS/ | grep $STATION`
				PID=`cat $LOCKS/$PID_FILE`
				echo "$STATION has process ID of $PID"
				if rm $LOCKS/$STATION 2>/dev/null
				then
					echo "lock removed from station $STATION"
					if [ $PID ] # && [ kill -9 $PID ] # Commented for testing.
					then
						echo "$PID killed. (Pretending for testing)"
					else
						echo "$PID no such process ID."
					fi
				else
					echo "no lock on station, nothing to do."
				fi
			else
				echo "the station number is $STATION, but I am not going to remove the lock."
			fi
		else
			echo "No such station lock file found for '$STATION'."
		fi
	fi
done
# EOF
