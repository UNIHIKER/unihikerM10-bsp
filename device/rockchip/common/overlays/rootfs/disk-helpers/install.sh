#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

if [ "$RK_DISK_HELPERS_DISABLED" ]; then
	notice "Disabling disk-helpers..."
	find "$TARGET_DIR/etc" "$TARGET_DIR/lib" "$TARGET_DIR/usr/" \
		-name "*mountall*" -print0 -o -name "*mount-all*" -print0 -o \
		-name "*resizeall*" -print0 -o -name "*resize-all*" -print0 \
		2>/dev/null | xargs -0 rm -rf
	exit 0
fi

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

if [ "$RK_DISK_HELPERS_MOUNTALL" ]; then
	DISK_HELPER_TYPE=mount
elif [ "$RK_DISK_HELPERS_RESIZEALL" ]; then
	DISK_HELPER_TYPE=resize
else
	if [ "$POST_OS" = buildroot ]; then
		DISK_HELPER_TYPE=mount
	else
		DISK_HELPER_TYPE=resize
	fi
fi

message "Installing $DISK_HELPER_TYPE service..."

$RK_RSYNC "$OVERLAY_DIR/usr" "$TARGET_DIR/"

SCRIPT=$(ls "$OVERLAY_DIR" | grep ${DISK_HELPER_TYPE}all.sh)

install_busybox_service "$OVERLAY_DIR/$SCRIPT"

if [ "$DISK_HELPER_TYPE" = mount ]; then
	if [ "$RK_DISK_AUTO_FORMAT" ]; then
		message "Enabling auto formatting..."
		touch "$TARGET_DIR/.auto_mkfs"
	else
		rm -f "$TARGET_DIR/.auto_mkfs"
	fi

	if [ "$RK_DISK_SKIP_FSCK" ]; then
		message "Disabling boot time fsck..."
		touch "$TARGET_DIR/.skip_fsck"
	else
		rm -f "$TARGET_DIR/.skip_fsck"
	fi
	exit 0
fi

install_sysv_service "$OVERLAY_DIR/$SCRIPT" S
install_systemd_service "$OVERLAY_DIR/$DISK_HELPER_TYPE-all.service"
