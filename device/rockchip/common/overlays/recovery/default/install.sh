#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

# Redirect log output to serial console
if [ "$RK_RECOVERY_CONSOLE_LOG" ]; then
	message "Enabling serial console logging..."
	touch "$TARGET_DIR/.rkdebug"
fi

$RK_RSYNC "$OVERLAY_DIR/" "$TARGET_DIR/"
