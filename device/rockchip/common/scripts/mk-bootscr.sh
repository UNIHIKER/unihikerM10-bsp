#!/bin/bash -e
# Build boot.scr from boot.cmd and optionally prepend to boot image (FIT).
# When prepending: boot partition layout becomes [0, 32K) boot.scr; [32K, end) FIT.

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"
BOOT_CMD="${1:-$RK_CHIP_DIR/boot.cmd}"
BOOT_SCR="${2:-$RK_SDK_DIR/kernel/boot.scr}"
TARGET_IMG="${3:-$RK_SDK_DIR/kernel/$RK_BOOT_IMG}"
BOOT_SCR_PAD_SECTORS=64
BOOT_SCR_PAD_BYTES=$((BOOT_SCR_PAD_SECTORS * 512))

[ -f "$BOOT_CMD" ] || { echo "boot.cmd not found: $BOOT_CMD"; exit 1; }

cd "$RK_SDK_DIR"
MKIMAGE="${RK_SDK_DIR}/rkbin/tools/mkimage"
[ -x "$MKIMAGE" ] || { echo "mkimage not found: $MKIMAGE"; exit 1; }

# Build boot.scr (U-Boot script image)
"$MKIMAGE" -C none -A arm64 -T script -d "$BOOT_CMD" "$BOOT_SCR"
echo "  Image: boot.scr (from $(basename "$BOOT_CMD")) is ready"

# Prepend to boot image: [padded boot.scr][FIT]
if [ -n "$TARGET_IMG" ] && [ -f "$TARGET_IMG" ]; then
	pad_scr=$(mktemp)
	dd if=/dev/zero of="$pad_scr" bs=512 count=$BOOT_SCR_PAD_SECTORS 2>/dev/null
	dd if="$BOOT_SCR" of="$pad_scr" conv=notrunc 2>/dev/null
	cat "$pad_scr" "$TARGET_IMG" > "${TARGET_IMG}.new"
	mv "${TARGET_IMG}.new" "$TARGET_IMG"
	rm -f "$pad_scr"
	echo "  Prepend boot.scr (${BOOT_SCR_PAD_BYTES} bytes) to $(basename "$TARGET_IMG")"
fi
