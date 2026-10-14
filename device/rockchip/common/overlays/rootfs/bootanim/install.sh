#!/bin/bash -e

[ "$RK_ROOTFS_BOOTANIM" ] || exit 0

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

message "Installing bootanim service..."

$RK_RSYNC "$OVERLAY_DIR/usr" "$TARGET_DIR/"
sed -i "s/^\(TIMEOUT=\).*/\1$RK_ROOTFS_BOOTANIM_TIMEOUT/" \
	"$TARGET_DIR/usr/bin/bootanim"

install_sysv_service "$OVERLAY_DIR/S31bootanim.sh" S
install_busybox_service "$OVERLAY_DIR/S31bootanim.sh"
install_systemd_service "$OVERLAY_DIR/bootanim.service" \
	"$OVERLAY_DIR/S31bootanim.sh" /etc/init.d/bootanim

rm -rf "$TARGET_DIR/etc/bootanim.d"
$RK_RSYNC "$OVERLAY_DIR/etc" "$TARGET_DIR/"
