#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

if [ "$RK_ROOTFS_INSTALL_MODULES" ]; then
	message "Installing kernel modules..."

	# Ensure current user owns existing modules in rootfs so 'make modules_install'
	# (run as non-root via sudo -u) can safely remove/overwrite old .ko files.
	if [ -d "$TARGET_DIR/lib/modules" ]; then
		chown -R "$RK_OWNER_UID":"$RK_OWNER" "$TARGET_DIR/lib/modules" 2>/dev/null || true
	fi

	"$RK_SCRIPTS_DIR/mk-kernel.sh" modules "$TARGET_DIR/"
fi

if [ "$RK_ROOTFS_STRIP_MODULES" ]; then
	message "Strip kernel modules..."

	source "$RK_SCRIPTS_DIR/kernel-helper"

	find "$TARGET_DIR" -name "*.ko" \
		-exec ${RK_KERNEL_TOOLCHAIN}strip --strip-unneeded -v {} \;
fi
