#!/bin/sh
# USB RNDIS + ECM gadget for Unihiker (from upgrade.sh).
# Creates usb0 (RNDIS, Windows) + usb1 (ECM, Linux), bridge br0 @ 10.1.2.3, DHCP server.

set -e
GADGET_PATH="/sys/kernel/config/usb_gadget/g1"
MAC_CONF="/etc/rk3308bs/usb-ether-mac.conf"

get_base_mac() {
	if [ -s "$MAC_CONF" ]; then
		cat "$MAC_CONF"
		return
	fi
	for iface in wlan0 eth0; do
		if ip link show "$iface" 2>/dev/null | grep -q "link/ether"; then
			ip addr show "$iface" | awk '/link\/ether/{print $2; exit}'
			return
		fi
	done
	# Fallback: fixed MAC (POSIX sh, no bash substring)
	echo "02:00:00:00:00:01"
}

# Ensure configfs is mounted (usb_gadget lives under it)
if ! [ -d /sys/kernel/config/usb_gadget ]; then
	mkdir -p /sys/kernel/config
	mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config 2>/dev/null || true
fi

# Load modules if not built-in (libcomposite creates usb_gadget dir)
for m in libcomposite usb_f_rndis usb_f_ecm; do
	modprobe "$m" 2>/dev/null || true
done

# Wait for configfs and UDC (USB device controller may appear late), but do not
# block boot for too long. If UDC is not ready within a short window, skip
# gadget setup and exit successfully to avoid delaying boot.
MAX_WAIT=20  # 20 * 0.5s = 10s
for i in $(seq 1 "$MAX_WAIT"); do
	[ -d /sys/kernel/config/usb_gadget ] && UDC=$(ls /sys/class/udc 2>/dev/null | head -n1) && [ -n "$UDC" ] && break
	sleep 0.5
done
if ! [ -d /sys/kernel/config/usb_gadget ]; then
	echo "usb_gadget configfs not available, skipping USB gadget setup"
	exit 0
fi
UDC=$(ls /sys/class/udc 2>/dev/null | head -n1)
if [ -z "$UDC" ]; then
	echo "No UDC controller, skipping USB gadget setup (check CONFIG_USB_DWC2/gadget, DTS usb dr_mode)"
	exit 0
fi

# Persist MAC
mkdir -p "$(dirname "$MAC_CONF")"
MAC=$(get_base_mac)
if ! [ -s "$MAC_CONF" ]; then
	echo "$MAC" > "$MAC_CONF"
fi
MAC=$(cat "$MAC_CONF")

# Derive MACs (same logic as upgrade.sh)
echo "$MAC" | grep -qE "[0-7]$" && MAC_WIN_HOST="${MAC%?}8" || MAC_WIN_HOST="${MAC%?}0"
echo "$MAC" | grep -qE "[0-7]$" && MAC_WIN_DEV="${MAC%?}9"  || MAC_WIN_DEV="${MAC%?}1"
echo "$MAC" | grep -qE "[0-7]$" && MAC_LINUX_HOST="${MAC%?}a" || MAC_LINUX_HOST="${MAC%?}2"
echo "$MAC" | grep -qE "[0-7]$" && MAC_LINUX_DEV="${MAC%?}b"  || MAC_LINUX_DEV="${MAC%?}3"

# Tear down existing gadget if present
if [ -d "$GADGET_PATH" ]; then
	[ -f "$GADGET_PATH/UDC" ] && echo "" > "$GADGET_PATH/UDC" 2>/dev/null || true
	rm -rf "$GADGET_PATH"
fi

cd /sys/kernel/config/usb_gadget
mkdir g1
cd g1
echo 0x0525 > idVendor
echo 0xa4a2 > idProduct
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol
mkdir -p strings/0x409
echo "dfrobot20200928" > strings/0x409/serialnumber
echo "dfrobot" > strings/0x409/manufacturer
echo "unihiker" > strings/0x409/product

# Config 1: RNDIS (Windows)
mkdir -p configs/c.2/strings/0x409
echo "Config 1: RNDIS network" > configs/c.2/strings/0x409/configuration
echo 250 > configs/c.2/MaxPower
echo 0x80 > configs/c.2/bmAttributes
mkdir -p functions/rndis.usb0
echo "$MAC_WIN_HOST" > functions/rndis.usb0/host_addr
echo "$MAC_WIN_DEV" > functions/rndis.usb0/dev_addr
mkdir -p os_desc
echo 1 > os_desc/use
echo 0xbc > os_desc/b_vendor_code
echo MSFT100 > os_desc/qw_sign
mkdir -p functions/rndis.usb0/os_desc/interface.rndis
echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
ln -sf functions/rndis.usb0 configs/c.2/
ln -sf configs/c.2/ os_desc

# Config 2: ECM (Linux/macOS)
mkdir -p configs/c.1
echo 250 > configs/c.1/MaxPower
mkdir -p configs/c.1/strings/0x409
echo "ECM" > configs/c.1/strings/0x409/configuration
mkdir -p functions/ecm.usb1
echo "$MAC_LINUX_HOST" > functions/ecm.usb1/host_addr
echo "$MAC_LINUX_DEV" > functions/ecm.usb1/dev_addr
ln -sf functions/ecm.usb1 configs/c.1

echo "$UDC" > UDC

# Bring up interfaces and bridge
sleep 1
ip link set usb0 up 2>/dev/null || true
ip link set usb1 up 2>/dev/null || true
ip addr flush dev usb0 2>/dev/null || true
ip addr flush dev usb1 2>/dev/null || true

if ! ip link show br0 >/dev/null 2>&1; then
	ip link add name br0 type bridge
	ip addr add 10.1.2.3/24 dev br0
	ip link set br0 up
	ip link set usb0 master br0
	ip link set usb1 master br0
fi

# Restart DHCP server in background to avoid blocking this oneshot service
( sleep 1; systemctl restart isc-dhcp-server 2>/dev/null || true ) &
exit 0
