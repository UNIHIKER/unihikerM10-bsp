#!/bin/bash -e

SITE="${1:-www.baidu.com}"
SITE_NAME="${2:-$SITE}"
EXTRA_MSG="$3"

case "$(curl -I -s -m 3 -w "%{http_code}" -o /dev/null "http://${SITE#*://}")" in
	2*|3*|4*) exit 0;;
	*)
		if ping "$SITE" -c 1 -W 1 &>/dev/null; then
			exit 0
		fi
		;;
esac

echo -e "\e[35m"
echo -e "Your network is not able to access $SITE_NAME!"
echo -e "$EXTRA_MSG"

echo -e "Enter any thing within 5 seconds to continue..."
echo -e "\e[0m"

read -t 5 -r || exit 1
