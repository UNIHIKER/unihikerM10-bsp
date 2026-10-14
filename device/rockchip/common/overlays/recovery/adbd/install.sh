#!/bin/bash -e

TARGET_DIR="$1"
[ "$TARGET_DIR" ] || exit 1

OVERLAY_DIR="$(dirname "$(realpath "$0")")"

install_adbd()
{
	mkdir -p "$TARGET_DIR/etc/profile.d"
	{
		echo "export USB_FUNCS=adb"
		echo "export USB_VENDOR_ID=\"$RK_RECOVERY_ADBD_VID\""
		if echo "$RK_RECOVERY_ADBD_PID" | grep -iq '^0x'; then
			echo "export USB_PRODUCT_ID=\"$RK_RECOVERY_ADBD_PID\""
		fi
		echo "export USB_FW_VERSION=\"$RK_RECOVERY_ADBD_FW_VER\""
		echo "export USB_MANUFACTURER=\"$RK_RECOVERY_ADBD_MANUFACTURER\""
		echo "export USB_PRODUCT=\"$RK_RECOVERY_ADBD_PRODUCT\""
	} > "$TARGET_DIR/etc/profile.d/usbdevice.sh"

	$RK_RSYNC "$OVERLAY_DIR/usr" "$OVERLAY_DIR/lib" "$OVERLAY_DIR/etc" \
		"$TARGET_DIR/"

	if [ -e "$TARGET_DIR/usr/bin/adbd" ] && \
		! grep -q ADBD_SHELL "$TARGET_DIR/usr/bin/adbd"; then
		message "Found incompatible adbd, removing it..."
		rm -f "$TARGET_DIR/usr/bin/adbd"
	fi

	ensure_tools "$TARGET_DIR/usr/bin/adbd"

	if [ "$RK_RECOVERY_ADBD_TCP_PORT" -ne 0 ]; then
		echo "export ADB_TCP_PORT=$RK_RECOVERY_ADBD_TCP_PORT" >> \
			"$TARGET_DIR/etc/profile.d/adbd.sh"
	fi

	if [ -n "$RK_RECOVERY_ADBD_SHELL" ]; then
		echo "export ADBD_SHELL=$RK_RECOVERY_ADBD_SHELL" >> \
			"$TARGET_DIR/etc/profile.d/adbd.sh"
	fi

	[ -n "$RK_RECOVERY_ADBD_SECURE" ] || return 0

	echo "export ADB_SECURE=1" >> "$TARGET_DIR/etc/profile.d/adbd.sh"

	if [ -n "$RK_RECOVERY_ADBD_PASSWORD" ]; then
		echo "export ADBD_AUTH_COMMAND=/usr/bin/adbd-auth.sh" >> \
			"$TARGET_DIR/etc/profile.d/adbd.sh"
		ADBD_PASSWORD_MD5="$(echo $RK_RECOVERY_ADBD_PASSWORD | md5sum)"
		install -m 0755 "$OVERLAY_DIR/adbd-auth.sh" \
			"$TARGET_DIR/usr/bin/adbd-auth.sh"
		sed -i "s/ADBD_PASSWORD_MD5/$ADBD_PASSWORD_MD5/g" \
			"$TARGET_DIR/usr/bin/adbd-auth.sh"
	fi

	[ "$RK_RECOVERY_ADBD_KEYS" ] || return 0

	sudo -u "#$RK_OWNER_UID" sh -c "cat $RK_RECOVERY_ADBD_KEYS" > \
		"$TARGET_DIR/adb_keys"
}

if [ ! "$RK_RECOVERY_ADBD" ]; then
	notice "ADBD disabled..."

	find "$TARGET_DIR/etc" "$TARGET_DIR/lib" "$TARGET_DIR/usr/bin" \
		-name "*usbdevice*" -print0 -o -name ".usb_config" -print0 \
		2>/dev/null | xargs -0 rm -rf
else
	message "Installing ADBD service..."
	install_adbd
fi
