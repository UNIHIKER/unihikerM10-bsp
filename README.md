# RK3308BS UNIHIKER M10 Linux SDK

[中文版](README_CN.md)

A trimmed, customized **RK3308BS + Debian 12 (bookworm)** SDK based on the Rockchip Linux SDK, targeting the DFRobot UNIHIKER M10 board:

- Boot chain: `MiniLoaderAll.bin` → U-Boot → Linux 6.1 → Debian rootfs
- Partition layout: **GPT only** (boot + rootfs), no oem/userdata partitions
- Rootfs: Debian bookworm minimal (console only, no GUI)

---
## Install

**Recommended (clone with all submodules in one step):**

```bash
git clone --recursive https://github.com/fary99/unihikerM10-bsp.git
cd unihikerM10-bsp
```

**If you cloned without `--recursive`, initialize submodules manually:**

```bash
git clone https://github.com/fary99/unihikerM10-bsp.git
cd unihikerM10-bsp
git submodule update --init --recursive
```


## Directory layout

- `kernel/` — Linux 6.1 kernel source (`unihikerM10_linux_defconfig`, `rk3308bs-unihikerM10.dts`)
- `u-boot/` — U-Boot and loader outputs (`MiniLoaderAll.bin`, `uboot.img`, `trust.img`)
- `debian/` — Debian rootfs scripts and overlay
- `device/rockchip/.chips/rk3308/` — Board config
  - `dfrobot_unihikerM10_defconfig` — SDK defconfig
  - `parameter-64bit-debian.txt` — **GPT partition table** (uboot/trust/misc/boot/rootfs)
- `device/rockchip/common/` — Shared build scripts and hooks
  - `build-hooks/` — Top-level build entry (`99-all.sh` runs loader → kernel → rootfs → firmware)
  - `post-hooks/` — Post-rootfs steps
  - `scripts/` — `mk-kernel.sh`, `mk-rootfs.sh`, `mk-firmware.sh`, etc.

---

## Build environment and dependencies

Recommended: Ubuntu 20.04/22.04 x86_64.

### Required packages

```bash
sudo apt-get update
sudo apt-get install git ssh make gcc libssl-dev \
     liblz4-tool expect expect-dev g++ patchelf chrpath gawk texinfo chrpath \
     diffstat binfmt-support qemu-user-static live-build bison flex fakeroot \
     cmake gcc-multilib g++-multilib unzip device-tree-compiler ncurses-dev \
     libgucharmap-2-90-dev bzip2 expat gpgv2 cpp-aarch64-linux-gnu libgmp-dev \
     libmpc-dev bc python-is-python3 python2
```

> Debian rootfs packages are installed inside chroot by `mk-rootfs-bookworm.sh` via `apt-get`.

### Cross-compiler toolchain (download separately)

This repository **does not ship** a prebuilt cross toolchain. Download it from Arm:

- **Arm GNU Toolchain 10.3-2021.07** (AArch64 bare-metal)
- Download page (check current URL): `https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads`

Extract it under:

- `prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/`

The directory must contain `bin/aarch64-none-linux-gnu-gcc` (and siblings). `build.sh` will pick the toolchain from this path. Expected layout:

```
prebuilts/
└── gcc
    └── linux-x86
        ├── aarch64
        │   └── gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
        │       ├── bin
        │       │   ├── aarch64-none-linux-gnu-gcc
        │       │   └── ...
        │       ├── aarch64-none-linux-gnu/
        │       ├── readme.txt
        │       └── ...
        └── arm
            └── gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf
                └── ...
```

---

## Build

### 1. Full build (recommended)

```bash
./build.sh           # same as ./build.sh all
```

### 2. Build individual parts

- **U-Boot + Loader only:**

```bash
./build.sh uboot
```

- **Kernel only:**

```bash
./build.sh kernel
```

- **Debian rootfs (bookworm) only:**

```bash
./build.sh debian
```

After a full or partial build:

- Kernel: `kernel/boot.img`, `kernel/arch/arm64/boot/dts/rockchip/rk3308bs-unihikerM10.dtb`
- Rootfs: `debian/unihiker-rootfs.img`

Full build runs in order:

1. Loader / U-Boot (`mk-loader.sh`)
2. Kernel (`mk-kernel.sh` → `boot.img`)
3. Debian rootfs (`mk-rootfs.sh` → `mk-rootfs-bookworm.sh`)
4. Firmware packaging (`mk-firmware.sh`)
5. Update image packaging (`mk-updateimg.sh` → `update.img`)

Output images:

```
output/firmware/   (also linked as rockdev/)
```

Typical contents:

- `MiniLoaderAll.bin` — Loader
- `uboot.img` — U-Boot
- `trust.img` — Trust firmware
- `boot.img` — Kernel (+ initramfs if used)
- `rootfs.img` — Debian rootfs
- `misc.img` — Misc partition
- `parameter.txt` — Partition table (GPT, from `parameter-64bit-debian.txt`)
- `update.img` — Rockchip full flash image (contains all partitions above)

---

## Debian rootfs defaults

`debian/mk-rootfs-bookworm.sh` customizes the rootfs in chroot:

- **Default user**
  - Username: `unihiker`
  - Password: `dfrobot`
  - Groups: `root`, `sudo`, `audio`, `video`, `plugdev`, `netdev`, `dialout`, `tty`, `gpio`
- **Hostname / network**
  - Hostname: `unihiker`
  - `/etc/hosts`: `127.0.1.1    unihiker`
  - APT source: Official Debian (`deb.debian.org`)
  - DNS: `8.8.8.8`
- **Preinstalled**
  - SSH: `openssh-server`, `openssh-client`
  - WiFi/BT: `wpasupplicant`, `iw`, `network-manager`, `bluez`
  - Network tools: `net-tools` (e.g. ifconfig)
  - Touch debugging: `evtest`
- **Other**
  - User PATH includes `/sbin`, `/usr/sbin`
  - USB RNDIS/ECM gadget (`usb-rndis-ether.service`)
  - System sleep disabled via `/etc/systemd/logind.conf.d/disable-sleep.conf`

---

## Partitions and flashing (GPT)

Partition definition: `device/rockchip/.chips/rk3308/parameter-64bit-debian.txt`

- Partitions: `uboot`, `trust`, `misc`, `boot`, `rootfs (grow)`
- GPT only, no oem/userdata
- rootfs can grow to fill remaining space

Flashing tool: **upgrade_tool** (Rockchip command-line development tool), bundled with the SDK:

```
tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool
```

> See the user manual in the same directory for detailed usage.

**Install upgrade_tool to system PATH (recommended, one-time setup):**

```bash
sudo cp tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool /usr/local/bin/
sudo chmod +x /usr/local/bin/upgrade_tool
```

After installation, you can use `sudo upgrade_tool` from any directory.

### Method 1: Full image flashing (update.img, recommended)

`update.img` contains the loader, parameter, and all partition images. A single command flashes the entire system.

**Build update.img separately:**

```bash
./build.sh updateimg
```

> `./build.sh all` automatically generates `update.img` at the end; no need to run this separately.

**Flashing steps:**

```bash
# 1. Enter Maskrom mode (hold Maskrom button while powering on)
# 2. Check if the device is detected
sudo upgrade_tool ld

# 3. Flash entire image (auto-downloads Boot + writes all partitions)
sudo upgrade_tool uf output/firmware/update.img
```

### Method 2: Flash individual partitions

Suitable for development/debugging when only updating a specific partition.

```bash
# Enter Maskrom mode, download Boot
sudo upgrade_tool db output/firmware/MiniLoaderAll.bin

# Flash Loader (writes IDBlock)
sudo upgrade_tool ul output/firmware/MiniLoaderAll.bin

# Flash partition table
sudo upgrade_tool di -p output/firmware/parameter.txt

# Flash partition images (-u/-t/-m/-b are built-in shortcuts; rootfs uses partition name)
sudo upgrade_tool di -u output/firmware/uboot.img
sudo upgrade_tool di -t output/firmware/trust.img
sudo upgrade_tool di -m output/firmware/misc.img
sudo upgrade_tool di -b output/firmware/boot.img
sudo upgrade_tool di -rootfs output/firmware/rootfs.img
```

**Common partition shortcuts:**

| Shortcut | Partition |
|----------|-----------|
| `-u` | uboot |
| `-t` | trust |
| `-m` | misc |
| `-b` | boot |
| `-k` | kernel |
| `-r` | recovery |

> For partitions without a built-in shortcut (e.g. rootfs), use the `-partitionname` format: `-rootfs rootfs.img`.

---

## FAQ

- **Q: What is the difference between full image flashing and individual partition flashing?**
  A: `update.img` is the standard Rockchip package format containing all partitions. A single command flashes the entire system, ideal for mass production and first-time flashing. Individual partition flashing is useful during development when only a specific partition needs updating (e.g. just `boot.img` or `rootfs.img`).

- **Q: How to regenerate update.img without recompiling everything?**
  A: Make sure all partition images are present in `output/firmware/`, then run `./build.sh updateimg`.

---

## Feedback and contributions

This SDK is a customized subset of the Rockchip Linux SDK for the UNIHIKER M10. For issues or improvements:

- Open an issue or PR in the project repo, or
- Contact the hardware vendor (DFRobot) for support.

---

## License

This SDK contains components under different licenses:

- **Linux Kernel** (`kernel/`) — [GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) with Linux-syscall-note exception
- **U-Boot** (`u-boot/`) — [GPL-2.0+](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- **Build scripts and board configuration** (`device/`, `debian/`, etc.) — [GPL-2.0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

This project as a whole is distributed under the terms of the **GNU General Public License v2.0**. See [LICENSE](LICENSE) for the full license text.

```
SPDX-License-Identifier: GPL-2.0
```
