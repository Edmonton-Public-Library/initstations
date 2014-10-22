####################################################
# Makefile for project initstation 
# Created: Wed Oct 22 10:06:19 MDT 2014
# Copyright (c) Edmonton Public Library Wed Oct 22 10:06:19 MDT 2014
#
#<one line to give the program's name and a brief idea of what it does.>
#    Copyright (C) 2013  Andrew Nisbet
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
# Written by Andrew Nisbet at Edmonton Public Library
# Rev: 
#      0.0 - Dev. 
####################################################
# Change comment below for appropriate server.
PRODUCTION_SERVER=eplapp.library.ualberta.ca
TEST_SERVER=edpl-t.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/EPLwork/anisbet/
LOCAL=~/projects/initstation/
APP=initstation.sh
ARGS=CMA02 EPLPMR01 EPLPMR02

test:
	scp ${LOCAL}${APP} ${USER}@${TEST_SERVER}:${REMOTE}
	ssh ${USER}@${TEST_SERVER} '${REMOTE}${APP} ${ARGS}'
production: test
	scp ${LOCAL}${APP} ${USER}@${PRODUCTION_SERVER}:${REMOTE}

