#!/bin/bash -e

# Install rtk_hciattach binary into target rootfs so Bluetooth bring-up script can use it.

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

# SDK-side path of the aarch64 rtk_hciattach tool
RTK_HCIATTACH_SRC="$RK_COMMON_DIR/tools/aarch64/rtk_hciattach"

[ -x "$RTK_HCIATTACH_SRC" ] || {
	warning "rtk_hciattach not found at $RTK_HCIATTACH_SRC, skip installing."
	exit 0
}

message "Installing rtk_hciattach into target /usr/bin/"
mkdir -p "$TARGET_DIR/usr/bin"
cp -f "$RTK_HCIATTACH_SRC" "$TARGET_DIR/usr/bin/rtk_hciattach"
chmod 0755 "$TARGET_DIR/usr/bin/rtk_hciattach"

