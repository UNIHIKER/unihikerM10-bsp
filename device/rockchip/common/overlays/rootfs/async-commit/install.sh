#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

rm -f etc/init.d/S*_commit.sh \
	etc/systemd/system/multi-user.target.wants/async.service \
	usr/lib/systemd/system/async.service

[ "$RK_ROOTFS_ASYNC_COMMIT" ] || exit 0

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

message "Installing async-commit service..."

$RK_RSYNC "$OVERLAY_DIR/usr" "$TARGET_DIR/"

ensure_tools "$TARGET_DIR/usr/bin/modetest"

install_sysv_service "$OVERLAY_DIR/S05async-commit.sh" S
install_busybox_service "$OVERLAY_DIR/S05async-commit.sh"
install_systemd_service "$OVERLAY_DIR/async-commit.service"
