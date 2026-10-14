#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

# RK3308BS: arm64 only
ARCH=arm64

echo -e "\033[36m Building for $ARCH (RK3308BS) \033[0m"

if [ ! $VERSION ]; then
	VERSION="release"
fi

echo -e "\033[36m Building for $VERSION \033[0m"

BASE_TARBALL="unihiker-bookworm-base-arm64.tar.gz"
if [ ! -e "$BASE_TARBALL" ]; then
	echo -e "\033[31m Run mk-base-debian.sh (via build.sh rootfs) first \033[0m"
	exit 1
fi

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf "$BASE_TARBALL"

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder (optional; skip if empty to avoid cp conflict with binary/lib etc.)
if compgen -G "overlay-firmware/*" > /dev/null; then
	sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/
fi

# overlay-debug folder
# adb, video, camera test files (optional, may not exist)
if [ "$VERSION" = "debug" ] && compgen -G "overlay-debug/*" > /dev/null; then
	sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/ 2>/dev/null || true
fi

echo -e "\033[36m Change root.....................\033[0m"

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

# RK3308BS: minimal rootfs (no GUI)
echo -e "\033[36m Minimal rootfs: serial/SSH + WiFi/BT (no GUI) \033[0m"
cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

# Fixup owners
if [ "$ID" -ne 0 ]; then
       find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/ 2>/dev/null); do
	chown -h -R \$u:\$u /home/\$u
done

# Ensure standard system groups exist (superset of audio/video/netdev etc.)
DEFGROUPS="adm,dialout,cdrom,audio,dip,video,plugdev,bluetooth,pulse-access,sudo,systemd-journal,netdev,staff,tty,gpio"
IFS=','
for grp in \$DEFGROUPS; do
	getent group "\$grp" >/dev/null || groupadd "\$grp"
done
unset IFS

# Create default user 'unihiker' if missing, with password 'dfrobot'
if ! id -u unihiker >/dev/null 2>&1; then
	echo "I: create unihiker user"
	adduser --gecos unihiker --disabled-password unihiker
	echo "I: set unihiker user password"
	echo "unihiker:dfrobot" | chpasswd
fi

# Add unihiker to default groups
echo "I: add unihiker to (\$DEFGROUPS) groups"
usermod -a -G \$DEFGROUPS unihiker


# Resolver configuration: link /etc/resolv.conf to resolvconf if present,
# and set a fallback DNS. Also ensure basic resolv.conf content exists.
if [ -d /run/resolvconf ]; then
	echo "I: Create /etc/resolv.conf link"
	ln -sf /run/resolvconf/resolv.conf /etc/resolv.conf
	mkdir -p /etc/resolvconf/resolv.conf.d
	echo "I: Install fallback DNS to 8.8.8.8"
	echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/head
else
	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	echo "nameserver 114.114.114.114" >> /etc/resolv.conf
fi

apt-get update
apt-get upgrade -y

# Make systemd less spammy (log level / target)
sed -i 's/#LogLevel=info/LogLevel=warning/' /etc/systemd/system.conf
sed -i 's/#LogTarget=journal-or-kmsg/LogTarget=journal/' /etc/systemd/system.conf

# Serial console: root login without password
sed -i "s~\(^ExecStart=.*\)~# \1\nExecStart=-/bin/sh -c '/bin/bash -l </dev/%I >/dev/%I 2>\&1'~" /usr/lib/systemd/system/serial-getty@.service 2>/dev/null || true

# SSH + editor + sudo (unihiker needs sudo for ifconfig, etc.)
apt-get install -fy --allow-downgrades openssh-server openssh-client vim sudo
echo 'unihiker ALL=(ALL:ALL) ALL' > /etc/sudoers.d/99-unihiker
chmod 440 /etc/sudoers.d/99-unihiker

# WiFi/BT tools
apt-get install -fy --allow-downgrades wpasupplicant iw network-manager bluez pulseaudio-module-bluetooth 

# Network tools (ifconfig, etc.)
apt-get install -fy --allow-downgrades net-tools

# Add /sbin and /usr/sbin to PATH for normal users to run ifconfig directly
echo 'export PATH="$PATH:/sbin:/usr/sbin"' > /etc/profile.d/unihiker-path.sh

# USB RNDIS/ECM gadget (br0 10.1.2.3 + DHCP)
apt-get install -fy --allow-downgrades bridge-utils isc-dhcp-server
chmod +x /usr/lib/rk3308bs/usb-rndis-ether.sh
# Enable USB RNDIS gadget service (manual symlink; systemctl enable unreliable in chroot)
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/usb-rndis-ether.service /etc/systemd/system/multi-user.target.wants/usb-rndis-ether.service
# Disable legacy usbdevice service to avoid long boot retries
systemctl disable usbdevice.service 2>/dev/null || true
systemctl mask usbdevice.service 2>/dev/null || true
rm -f /etc/systemd/system/sysinit.target.wants/usbdevice.service 2>/dev/null || true

# Disable network wait-online and wpa_supplicant instances to avoid boot delays
services=(NetworkManager systemd-networkd)
for service in \${services[@]}; do
  systemctl mask \${service}-wait-online.service 2>/dev/null || true
done
systemctl mask wpa_supplicant-wired@ 2>/dev/null || true
systemctl mask wpa_supplicant-nl80211@ 2>/dev/null || true
systemctl mask wpa_supplicant@ 2>/dev/null || true

# Enable Bluetooth bring-up service (uses bluetooth-start.sh + rtk_hciattach)
# systemctl enable in chroot is unreliable (systemd not running), create symlink directly
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/bluetooth-start.service /etc/systemd/system/multi-user.target.wants/bluetooth-start.service

# Optional: evtest for touchscreen debugging
apt-get install -fy --allow-downgrades evtest || true

# WiFi/BT: firmware copied via overlay

apt list --installed 2>/dev/null | grep -v oldstable | cut -d/ -f1 | xargs -r apt-mark hold

# Ensure default target is multi-user (no display manager by default)
if command -v systemctl >/dev/null 2>&1; then
	systemctl disable lightdm 2>/dev/null || true
	if [ -e /lib/systemd/system/multi-user.target ]; then
		ln -sf /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
	fi
fi

# Remove oem/userdata from fstab (simplified partition layout: boot+rootfs only)
sed -i '/by-partlabel\/oem/d; /by-partlabel\/userdata/d' /etc/fstab 2>/dev/null || true

# systemd-logind STATE_DIRECTORY: tmpfiles.d/logind-dirs.conf in overlay creates at boot
mkdir -p /var/lib/systemd/state
chmod 755 /var/lib/systemd/state

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/

EOF
