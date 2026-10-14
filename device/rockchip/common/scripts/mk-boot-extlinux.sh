#!/bin/bash -e
# Build boot partition as FAT image with extlinux.conf + zboot.img for distro_bootcmd.

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"
RK_CHIP_DIR="${RK_CHIP_DIR:-$RK_SCRIPTS_DIR/../../.chips/$RK_CHIP}"
FIT_IMG="${1:-$RK_SDK_DIR/kernel/$RK_BOOT_IMG}"
OUT_IMG="${2:-$RK_SDK_DIR/kernel/$RK_BOOT_IMG}"
BOOT_SIZE_MB="${BOOT_SIZE_MB:-8}"
EXTLINUX_DIR="${RK_CHIP_DIR}/extlinux"

[ -f "$FIT_IMG" ] || { echo "FIT image not found: $FIT_IMG"; exit 1; }
[ -d "$EXTLINUX_DIR" ] || { echo "extlinux dir not found: $EXTLINUX_DIR"; exit 1; }

cd "$RK_SDK_DIR"
BOOT_DIR=$(mktemp -d)
trap "rm -rf $BOOT_DIR" EXIT

mkdir -p "$BOOT_DIR/extlinux"
cp -a "$EXTLINUX_DIR"/* "$BOOT_DIR/extlinux/" 2>/dev/null || cp "$EXTLINUX_DIR/extlinux.conf" "$BOOT_DIR/extlinux/"
cp -a "$FIT_IMG" "$BOOT_DIR/zboot.img"

# Build FAT image (use genext2fs or mkfs.vfat + loop)
BOOT_SIZE_BYTES=$((BOOT_SIZE_MB * 1024 * 1024))
OUT_TMP="${OUT_IMG}.fat"
dd if=/dev/zero of="$OUT_TMP" bs=$BOOT_SIZE_BYTES count=1 2>/dev/null
mkfs.vfat -n "boot" -S 512 "$OUT_TMP" >/dev/null 2>&1 || { echo "mkfs.vfat not found, try: sudo apt install dosfstools"; exit 1; }
mcopy -i "$OUT_TMP" -s "$BOOT_DIR/extlinux" ::extlinux 2>/dev/null || true
mcopy -i "$OUT_TMP" "$BOOT_DIR/zboot.img" ::zboot.img 2>/dev/null || { echo "mcopy not found, try: sudo apt install mtools"; exit 1; }
mv "$OUT_TMP" "$OUT_IMG"
echo "  Image: $(basename "$OUT_IMG") (FAT ${BOOT_SIZE_MB}MB, extlinux + zboot.img) is ready"
