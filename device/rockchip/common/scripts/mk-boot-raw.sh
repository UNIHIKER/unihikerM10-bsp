#!/bin/bash -e
# Build boot partition as FAT image with boot.scr + Image + DTB (no FIT).

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"
RK_CHIP_DIR="${RK_CHIP_DIR:-$RK_SCRIPTS_DIR/../../.chips/$RK_CHIP}"
BOOT_CMD="${1:-$RK_CHIP_DIR/boot.cmd}"
KERNEL_IMG="${2:-$RK_SDK_DIR/$RK_KERNEL_IMG}"
KERNEL_DTB="${3:-$RK_SDK_DIR/$RK_KERNEL_DTB}"
OUT_IMG="${4:-$RK_SDK_DIR/kernel/$RK_BOOT_IMG}"
BOOT_SIZE_MB="${BOOT_SIZE_MB:-32}"

[ -f "$BOOT_CMD" ] || { echo "boot.cmd not found: $BOOT_CMD"; exit 1; }
[ -f "$KERNEL_IMG" ] || { echo "Kernel Image not found: $KERNEL_IMG"; exit 1; }
[ -f "$KERNEL_DTB" ] || { echo "DTB not found: $KERNEL_DTB"; exit 1; }

cd "$RK_SDK_DIR"
MKIMAGE="${RK_SDK_DIR}/rkbin/tools/mkimage"
[ -x "$MKIMAGE" ] || { echo "mkimage not found: $MKIMAGE"; exit 1; }

BOOT_DIR=$(mktemp -d)
trap "rm -rf $BOOT_DIR" EXIT

# Build boot.scr
"$MKIMAGE" -C none -A arm64 -T script -d "$BOOT_CMD" "$BOOT_DIR/boot.scr"
cp "$KERNEL_IMG" "$BOOT_DIR/Image"
cp "$KERNEL_DTB" "$BOOT_DIR/$(basename "$KERNEL_DTB")"

# Build FAT image
BOOT_SIZE_BYTES=$((BOOT_SIZE_MB * 1024 * 1024))
OUT_TMP="${OUT_IMG}.fat"
dd if=/dev/zero of="$OUT_TMP" bs=$BOOT_SIZE_BYTES count=1 2>/dev/null
mkfs.vfat -n "boot" -S 512 "$OUT_TMP" >/dev/null 2>&1 || { echo "mkfs.vfat not found, try: sudo apt install dosfstools"; exit 1; }
mcopy -i "$OUT_TMP" "$BOOT_DIR/boot.scr" ::boot.scr 2>/dev/null || { echo "mcopy not found, try: sudo apt install mtools"; exit 1; }
mcopy -i "$OUT_TMP" "$BOOT_DIR/Image" ::Image 2>/dev/null || true
mcopy -i "$OUT_TMP" "$BOOT_DIR/$(basename "$KERNEL_DTB")" "::$(basename "$KERNEL_DTB")" 2>/dev/null || true
mv "$OUT_TMP" "$OUT_IMG"
echo "  Image: $(basename "$OUT_IMG") (FAT ${BOOT_SIZE_MB}MB, boot.scr + Image + $(basename "$KERNEL_DTB")) is ready"
