#!/bin/bash -e

source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

RK_RSYNC="rsync -av --chmod=u=rwX,go=rX --copy-unsafe-links --keep-dirlinks --exclude .empty --exclude .git --exclude /install.sh"
RK_OVERLAY_ALLOWED="$@"

[ "$RK_OVERLAY" ] || exit 0

do_install_overlay()
{
	[ -d "$1" ] || return 0

	OVERLAY="$(realpath "$1")"
	if [ -x "$OVERLAY/install.sh" ]; then
		notice "Handling overlay: $OVERLAY)..."
		RK_RSYNC="$RK_RSYNC" \
			"$OVERLAY/install.sh" "$TARGET_DIR" "$POST_OS"
	else
		notice "Installing overlay: $OVERLAY to $TARGET_DIR..."
		$RK_RSYNC "$OVERLAY/" "$TARGET_DIR/"
	fi
}

install_overlay()
{
	# For debugging only
	if [ "$RK_OVERLAY_ALLOWED" ]; then
		for d in $RK_OVERLAY_ALLOWED; do
			basename "$d"
		done | grep -wq "$(basename "$1")" || return 0
	fi

	case "$1" in
		/*) do_install_overlay "$1" ;;
		*)
			# Install common and chip overlays
			for d in "$RK_COMMON_DIR" "$RK_CHIP_DIR"; do
				do_install_overlay "$d/overlays/$1"
			done
			;;
	esac
}

install_overlays()
{
	for d in "$RK_COMMON_DIR" "$RK_CHIP_DIR"; do
		[ -d "$d/overlays/$1" ] || continue
		for overlay in "$d/overlays/$1/"*; do
			install_overlay "$overlay"
		done
	done
}

# Install common overlays
install_overlays common

# Install overlays for recovery, ramboot, etc.
if [ -z "$POST_ROOTFS" ]; then
	install_overlays $POST_OS
	exit 0
fi

# No overlays for rootfs without RK_ROOTFS_OVERLAY
[ "$RK_ROOTFS_OVERLAY" ] || exit 0

# Install basic rootfs overlays
install_overlays rootfs

# Install OS-specific overlays
install_overlays $POST_OS

# Install extra rootfs overlays
for overlay in $RK_ROOTFS_EXTRA_OVERLAY_DIRS; do
	install_overlay "$overlay"
done
