#!/bin/sh
### BEGIN INIT INFO
# Provides:       usbdevice
# Required-Start: $local_fs $syslog
# Required-Stop:  $local_fs
# Default-Start:  S
# Default-Stop:   K
# Description:    Manage USB device functions
### END INIT INFO

TAG_FILE=/var/run/.usbdevice

case "$1" in
	start|restart)
		touch $TAG_FILE
		while ! /usr/bin/usbdevice restart; do
			sleep 1

			if ! [ -e $TAG_FILE ]; then
				break
			fi
			echo "Retry ${1}ing usbdevice service"
		done&
		;;
	stop)
		rm -f $TAG_FILE
		/usr/bin/usbdevice stop
		;;
	*)
		echo "Usage: [start|stop|restart]" >&2
		exit 3
		;;
esac

:
