#!/bin/bash -e
# RK3308BS: bookworm + arm64 only

RELEASE="${RELEASE:-bookworm}"
ARCH="${ARCH:-arm64}"
TARGET="${TARGET:-base}"

[ "$RELEASE" != "bookworm" ] && { echo "Only bookworm is supported."; exit 1; }
[ "$ARCH" != "arm64" ] && { echo "Only arm64 is supported for RK3308BS."; exit 1; }
[ "$TARGET" != "base" ] && { echo "Only base (minimal) rootfs is supported."; exit 1; }

if [ -e unihiker-$RELEASE-*.tar.gz ]; then
	rm unihiker-$RELEASE-*.tar.gz
fi

cd ubuntu-build-service/$RELEASE-$TARGET-$ARCH

echo -e "\033[36m Staring Download...... \033[0m"

make clean
./configure
make

if [ -e unihiker-$RELEASE-*.tar.gz ]; then
	sudo chmod 0666 unihiker-$RELEASE-*.tar.gz
	mv unihiker-$RELEASE-*.tar.gz  ../../
	cd ../..
	mv unihiker-$RELEASE-*.tar.gz  unihiker-$RELEASE-base-$ARCH.tar.gz
else
	echo -e "\e[31m Failed to run livebuild, please check your network connection. \e[0m"
	#exit 1
fi
