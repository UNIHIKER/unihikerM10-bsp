#!/bin/bash -e
# Install overlay RTL8723DS .ko into /lib/modules/$(KERNELRELEASE)/extra/ and run depmod
# so modprobe can load them (no insmod service needed).

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

# Overlay prebuilt modules are stored in /usr/lib/rk3308bs/modules inside rootfs
[ -d "$TARGET_DIR/usr/lib/rk3308bs/modules" ] || exit 0

# Find KERNELRELEASE: from existing lib/modules subdir (e.g. from 91-modules) or from kernel build
KERNELRELEASE=""
if [ -d "$TARGET_DIR/lib/modules" ]; then
	KERNELRELEASE=$(ls -1 "$TARGET_DIR/lib/modules" 2>/dev/null | head -1)
fi
if [ -z "$KERNELRELEASE" ]; then
	RK_SDK_DIR="${RK_SDK_DIR:-$(realpath "$RK_SCRIPTS_DIR/../../../..")}"
	if [ -d "$RK_SDK_DIR/kernel" ] && [ -f "$RK_SDK_DIR/kernel/Makefile" ]; then
		KERNELRELEASE=$(make -s -C "$RK_SDK_DIR/kernel" --no-print-directory kernelrelease 2>/dev/null) || true
	fi
fi
if [ -z "$KERNELRELEASE" ]; then
	notice "RTL8723DS overlay: no KERNELRELEASE, skip installing .ko into lib/modules"
	exit 0
fi

message "Installing RTL8723DS overlay modules into /lib/modules/$KERNELRELEASE/extra/"
mkdir -p "$TARGET_DIR/lib/modules/$KERNELRELEASE/extra"
cp -n "$TARGET_DIR/usr/lib/rk3308bs/modules"/*.ko "$TARGET_DIR/lib/modules/$KERNELRELEASE/extra/" 2>/dev/null || true
depmod -b "$TARGET_DIR" "$KERNELRELEASE" 2>/dev/null || true

# RTL8723DS Bluetooth: ensure firmware in /lib/firmware/rtl_bt for rtk_hciattach (same layout as post-wifibt prebuilt path)
if [ -d "$TARGET_DIR/usr/lib/firmware/rtlbt" ]; then
	message "Installing RTL8723DS BT firmware into /lib/firmware/rtl_bt/"
	mkdir -p "$TARGET_DIR/lib/firmware/rtl_bt"
	cp -n "$TARGET_DIR/usr/lib/firmware/rtlbt"/* "$TARGET_DIR/lib/firmware/rtl_bt/" 2>/dev/null || true
fi
if [ -d "$TARGET_DIR/usr/lib/rk3308bs/wifi-firmware" ]; then
	message "Installing RTL8723DS firmware from wifi-firmware into /lib/firmware/rtl_bt/"
	mkdir -p "$TARGET_DIR/lib/firmware/rtl_bt"
	cp -n "$TARGET_DIR/usr/lib/rk3308bs/wifi-firmware"/* "$TARGET_DIR/lib/firmware/rtl_bt/" 2>/dev/null || true
fi

