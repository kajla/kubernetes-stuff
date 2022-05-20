#!/bin/bash
# This script restart services after patch, create signal file if needed for KURED.
# Tested OS: SUSE Linux Enterprise Server 15 SP3
# Author: Adam Radovits
#
# Changelog:
#	2022.02.04. @ RA - first version
#	2022.02.11. @ RA - small fix
#	2022.05.20. @ RA - security check added

# Signal file (for KURED sentinel file option)
SIGNALFILE=/var/run/reboot-required

# After boot, how many seconds we do nothing
WAITAFTERBOOT=600

# System reboot signal file
SYSTEMSIGNALFILE=/boot/do_purge_kernels

# If the system is booted up in WAITAFTERBOOT, we have nothing to do
read -d. MUPTIME < /proc/uptime
if [ ${MUPTIME} -lt ${WAITAFTERBOOT} ]; then
	echo "Fresh boot, removing ${SIGNALFILE}. Boot time: ${MUPTIME}"
	test -f ${SIGNALFILE} && unlink ${SIGNALFILE}
	exit 0
fi

# If zypper running, nothing to do now, we need to wait next cycle
if [ $(ps aux | grep -v grep | grep -c zypper) -ne 0 ]; then
	echo "zypper is already running, so we need to wait them"
	exit 0
fi

# If SIGNALFILE is already exists, counting starts
if [ -f ${SIGNALFILE} ]; then
	echo "${SIGNALFILE} already exists, nothing to do"
	COUNT=$(cat ${SIGNALFILE})
	if [ -z ${COUNT} ]; then
		echo "we are waiting for the first time"
		echo 1 > ${SIGNALFILE}
	else
		let "COUNT=COUNT+1"
		echo "we are waiting for ${COUNT} times"
		echo ${COUNT} > ${SIGNALFILE}
	fi
else
	# If SYSTEMSIGNALFILE exists, do reboot
	if [ -f ${SYSTEMSIGNALFILE} ]; then
		echo "System reboot signal exists: ${SYSTEMSIGNALFILE}, create signal file: ${SIGNALFILE}"
		touch ${SIGNALFILE}
	else
		# Is reboot suggested?
		if [ $(zypper ps | grep -c "Reboot is suggested") -ne 0 ]; then
			echo "Reboot is suggested, create signal file: ${SIGNALFILE}"
			touch ${SIGNALFILE}
		else
			ZYPPERSTATUS=$(zypper ps -sss)
			# Is zypper ps -sss is empty?
			if [ -z "${ZYPPERSTATUS}" ]; then
				echo "zypper ps -sss is empty, so there is no need to restart any service"
			else
				# If dbus upgraded, we recommend to reboot
				if [ $(echo ${ZYPPERSTATUS} | grep -c dbus) -ne 0 ]; then
					echo "dbus is upgraded, so we recommend reboot, create signal file: ${SIGNALFILE}"
					touch ${SIGNALFILE}
				else
					# We need to restart these services
					echo "Restart services: ${ZYPPERSTATUS}"
					/usr/bin/systemctl restart ${ZYPPERSTATUS}
					RET=$?
					if [ ${RET} -ne 0 ]; then
						echo "Oh no! Something went wrong!"
					else
						echo "Seems to have succeeded"
					fi
				fi
			fi
			# Check if something can't restart, so we need to reboot node
			CANTRES=$(zypper ps | grep '^[0-9]' | grep -v calico-node)
			if [ ! -z "${CANTRES}" ]; then
				echo "Something can't restart:"
				echo "${CANTRES}"
				echo "Let's try again in 1 minute later..."
				sleep 60
				CANTRES=$(zypper ps | grep '^[0-9]' | grep -v calico-node)
		    		if [ ! -z "${CANTRES}" ]; then
		    	    		echo "We are sure now, something can't restart:"
					echo "${CANTRES}"
					echo "So create signal file: ${SIGNALFILE}"
				 	touch ${SIGNALFILE}
				fi
			else
				echo "zypper ps is empty, nothing to do"
			fi
		fi
	fi
fi
exit 0
