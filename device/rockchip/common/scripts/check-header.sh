#!/bin/bash -e

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"

HEADER="$1"
APT_PACKAGE="$2"

if echo | gcc -E -include "$HEADER" - &>/dev/null; then
	exit 0
fi

echo -e "\e[35m"
echo "Your $HEADER is missing"
echo "Please install it:"
echo "sudo apt-get install $APT_PACKAGE"
echo -e "\e[0m"
exit 1
