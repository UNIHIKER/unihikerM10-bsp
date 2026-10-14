#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

[ "$RK_ROOTFS_LOG_GUARDIAN" ] || exit 0

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

message "Installing log-guardian service..."

$RK_RSYNC "$OVERLAY_DIR/usr" "$TARGET_DIR/"

sed -i -e "s/^\(INTERVAL=\).*/\1\"$RK_ROOTFS_LOG_GUARDIAN_INTERVAL\"/" \
	-e "s/^\(MIN_AVAIL_SIZE=\).*/\1\"$RK_ROOTFS_LOG_GUARDIAN_MIN_SIZE\"/" \
	-e "s#^\(LOG_DIRS=\).*#\1\"$RK_ROOTFS_LOG_GUARDIAN_LOG_DIRS\"#" \
	"$TARGET_DIR/usr/bin/log-guardian"

install_sysv_service "$OVERLAY_DIR/S01log-guardian.sh" S
install_busybox_service "$OVERLAY_DIR/S01log-guardian.sh"
install_systemd_service "$OVERLAY_DIR/log-guardian.service"
