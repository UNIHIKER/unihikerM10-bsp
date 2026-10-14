#!/bin/bash -e
# Bring up RTL8723DS Bluetooth on RK3308BS (aligned with post-wifibt application-level bring-up).

BT_TTY=$(/usr/bin/bt-tty 2>/dev/null || echo ttyS4)

# Wait for UART device (e.g. ttyS4) to appear
for i in $(seq 1 30); do
	[ -c "/dev/${BT_TTY}" ] && break
	sleep 0.2
done
if [ ! -c "/dev/${BT_TTY}" ]; then
	echo "bluetooth-start: /dev/${BT_TTY} not found" >&2
	exit 1
fi

# Power-cycle Bluetooth via rfkill and btwrite (if present)
if [ -w /sys/class/rfkill/rfkill0/state ]; then
	echo 0 > /sys/class/rfkill/rfkill0/state || true
fi
if [ -w /proc/bluetooth/sleep/btwrite ]; then
	echo 0 > /proc/bluetooth/sleep/btwrite || true
fi
sleep 0.5
if [ -w /sys/class/rfkill/rfkill0/state ]; then
	echo 1 > /sys/class/rfkill/rfkill0/state || true
fi
if [ -w /proc/bluetooth/sleep/btwrite ]; then
	echo 1 > /proc/bluetooth/sleep/btwrite || true
fi
sleep 0.5

# Load hci_uart (from kernel or from overlay extra/)
if ! lsmod | grep -qi '^hci_uart'; then
	if command -v modprobe >/dev/null 2>&1; then
		modprobe hci_uart || true
	fi
	if ! lsmod | grep -qi '^hci_uart'; then
		EXTRA="/lib/modules/$(uname -r)/extra/hci_uart.ko"
		[ -f "$EXTRA" ] && insmod "$EXTRA" || true
	fi
	if ! lsmod | grep -qi '^hci_uart'; then
		KERN="/lib/modules/$(uname -r)/kernel/drivers/bluetooth/hci_uart.ko"
		[ -f "$KERN" ] && insmod "$KERN" || true
	fi
fi

# Attach Realtek H5; firmware from /lib/firmware/rtl_bt (filled by 92-rtl8723ds-modules / post-wifibt style)
if command -v rtk_hciattach >/dev/null 2>&1; then
	exec rtk_hciattach -n -s 115200 "/dev/${BT_TTY}" rtk_h5
else
	echo "rtk_hciattach not found, cannot bring up BT HCI" >&2
	exit 1
fi

