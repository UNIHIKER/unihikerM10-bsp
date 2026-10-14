# Rockchip Linux SDK

Rockchip Linux SDK for Rockchip SoC boards
  - wiki <http://opensource.rock-chips.com/wiki_Main_Page>.

## Quick Start

1. Check supported targets:
```shell
   ~$ make help
```
2. Cleanup
```shell
   ~$ make cleanall
```
. Choose SDK defconfig:
```shell
   ~$ make defconfig
```
4. Modify SDK configurations:
```shell
   ~$ make config
```
5. Modify kernel configurations:
```shell
   ~$ make kconfig
```
6. Modify partition table:
```shell
   ~$ make edit-parts
```
7. Modify the firmware packaging manifest file:
```shell
   ~$ make edit-package-file
```
8. Place custom rootfs files in `device/rockchip/common/overlays/rootfs/default`.
9. Run `make` to build the images. Logs are saved in `output/log/latest`.
10. Flash the generated `output/firmware/update.img` to your device.
11. Boot your device and enjoy.
