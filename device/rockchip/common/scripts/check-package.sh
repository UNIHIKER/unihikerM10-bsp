#!/bin/bash -e

COMMAND="$1"
APT_PACKAGE="${2:-$COMMAND}"

if ! which "$COMMAND" >/dev/null; then
	echo -e "\e[35m"
	echo "Your $COMMAND is missing"
	echo "Please install it:"
	echo "sudo apt-get install $APT_PACKAGE"
	echo -e "\e[0m"
	exit 1
fi
