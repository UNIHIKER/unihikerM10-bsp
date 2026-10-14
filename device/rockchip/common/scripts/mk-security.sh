#!/bin/bash -e

# TODO: Almost product have enabled bl32.
# AVB Config should be set in AVB tools dir.
#     include keys / product id / efuse

# For flash device, encryption-system remain space should be config
###################################################
RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_SDK_DIR="${RK_SDK_DIR:-$RK_SCRIPTS_DIR/../../../..}"
UBOOT=$RK_SDK_DIR/u-boot
KERNEL=$RK_SDK_DIR/kernel
BUILDROOT=$RK_SDK_DIR/buildroot
RK_SIGN_TOOL=$RK_SDK_DIR/rkbin/tools/rk_sign_tool
RK_SIGN_INI=$RK_SDK_DIR/rkbin/tools/setting.ini
RK_AVB_TOOL_DIR=$RK_SDK_DIR/tools/linux/Linux_SecurityAVB/
RK_AVB_TOOL=$RK_AVB_TOOL_DIR/avb_user_tool.sh
###################################################
# 1 -> input misc	# 2 -> output misc
# 3 -> size		# 4 -> enc_key

check_var_in_list()
{
	echo $2 | fgrep -wq $1 && return 0 || return 1
}

assert_var_in_list()
{
	if ! check_var_in_list "$@" ; then
		echo -e "\e[41;1;37m$1 not in List \"$2\" -- $(basename "${BASH_SOURCE[1]}") - ${FUNCNAME[1]}\e[0m"
		return 1
	fi
}

rk_security_setup_misc()
{
	SRC=$1
	DST=$2
	size=$3
	buf=$4
	echo buf=$buf

	big_end=$[size / 256]
	lit_end=$[size - (big_end * 256)]
	big_end=$(echo "ibase=10;obase=16;$big_end" | bc)
	lit_end=$(echo "ibase=10;obase=16;$lit_end" | bc)

	IMAGE_DIR="${RK_OUTDIR:-$UBOOT}/security"
	mkdir -p "$IMAGE_DIR"
	IMAGE="$IMAGE_DIR/misc-security.img"
	rm -rf "$IMAGE"

	ln -rsLf "$SRC" "$IMAGE_DIR/misc.img"
	dd if="$IMAGE_DIR/misc.img" of="$IMAGE" bs=1k count=10
	echo -en "\x$lit_end\x$big_end" >> "$IMAGE"
	echo -n "$buf" >> "$IMAGE"
	skip=$[10 * 1024 + size + 2]
	dd if="$IMAGE_DIR/misc.img" of="$IMAGE" seek=$skip skip=$skip bs=1
	ln -rsf "$IMAGE" "$DST"
}

rk_security_setup_createkeys()
{
	mkdir -p $UBOOT/keys
	cd $UBOOT/keys

	$RK_SIGN_TOOL kk --bits 2048 --out ./

	ln -rsf private_key.pem dev.key
	ln -rsf public_key.pem dev.pubkey
	# TODO: Some rk_sign_tool may create privateKey.pem / publicKey.pem

	openssl req -batch -new -x509 -key $UBOOT/keys/dev.key \
		-out $UBOOT/keys/dev.crt

	if [ "$1" == "system-encryption" ]; then
		openssl rand -out $UBOOT/keys/system_enc_key -hex 32
	fi

	openssl rand -out $UBOOT/keys/aes128.key -hex 16
}

rk_security_setup_system_verity()
{
	target_image=$(readlink -f $1)
	outdir=$(cd $(dirname $target_image);pwd)
	security_system=$outdir/security_system.img

	if [ -f "$outdir/security.info" ]; then
		source $outdir/security.info
		if [ "$(ls -l --time-style=long-iso $target_image | cut -d ' ' -f 6,7)" == "$touch" ]; then
			echo "security_system.img not be updated!!!"
			return 0
		fi
	fi

	sectors=$(ls -l "$target_image" | awk '{printf $5}')
	hash_offset=$[(sectors / 1024 / 1024 + 2) * 1024 * 1024]
	tmp_file=$(mktemp)
	cp "$target_image" "$security_system"
	veritysetup --hash-offset=$hash_offset format "$security_system" "$security_system" > $tmp_file

	echo "touch=\"$(ls -l --time-style=long-iso $target_image | cut -d ' ' -f 6,7)\"" > $outdir/security.info
	echo "hash_offset=$hash_offset" >> $outdir/security.info
	root_hash=$(cat $tmp_file)
	echo "root_hash=$(echo ${root_hash##*:})" >> $outdir/security.info
	# cat "$tmp_file" >> $outdir/info
	rm $tmp_file
}

rk_security_setup_system_encryption()
{
	target_image=$(readlink -f $1)
	outdir=$(cd $(dirname $target_image);pwd)
	security_system=$outdir/security_system.img

	key=$(cat $UBOOT/keys/system_enc_key)
	cipher=aes-cbc-plain

	if [ -f "$outdir/security.info" ]; then
		source $outdir/security.info
		if [ "$(ls -l --time-style=long-iso $target_image | cut -d ' ' -f 6,7)" == "$touch" ]; then
			echo "security_system.img not be updated!!!"
			return 0
		fi
	fi

	sectors=$(ls -l "$target_image" | awk '{printf $5}')
	sectors=$[(sectors + (1 * 1024 * 1024) - 1) / 1024 / 1024 * 2048] # Align 1M / unit: 512 bytes

	loopdevice=$(sudo -S losetup -f < $UBOOT/keys/root_passwd)
	mappername=encfs-$(shuf -i 1-10000000000000000000 -n 1)
	dd if=/dev/null of="$security_system" seek=$sectors bs=512

	sudo -S losetup $loopdevice "$security_system" < $UBOOT/keys/root_passwd
	sudo -S dmsetup create $mappername --table "0 $sectors crypt $cipher $key 0 $loopdevice 0 1 allow_discards" < $UBOOT/keys/root_passwd
	sudo -S dd if="$target_image" of=/dev/mapper/$mappername conv=fsync < $UBOOT/keys/root_passwd
	if sync; then
		cnt=1
		while true; do
			if [ -b "/dev/mapper/$mappername" ]; then
				if [ "$cnt" -lt 10 ]; then
					echo "Try to remove mapper ... $cnt"
					sudo -S dmsetup remove $mappername < $UBOOT/keys/root_passwd || true
					cnt=$((cnt + 1))
					sleep 1
				else
					echo "Timeout for remove mapper:$mappername"
					echo "Please remove mapper manually"
					echo "    sudo dmsetup remove $mappername"
					echo "    sudo losetup -d $loopdevice"
					return -1;
				fi
			else
				echo "Removed mapper"
				break;
			fi
		done
	fi
	sudo -S losetup -d $loopdevice < $UBOOT/keys/root_passwd

	echo "touch=\"$(ls -l --time-style=long-iso $target_image | cut -d ' ' -f 6,7)\"" > $outdir/security.info
	echo "sectors=$sectors" >> $outdir/security.info
	echo "cipher=$cipher" >> $outdir/security.info
	echo "key=$key" >> $outdir/security.info
}

rk_security_setup_system_encryption_by_openssl()
{
	target_image=$(readlink -f $1)
	echo "target_image=$target_image"
	outdir=$(cd $(dirname $target_image);pwd)
	security_system=$outdir/security_system.img

	key_path=$UBOOT/keys/system_enc_key
	if [ ! -f "$key_path" ]; then
		echo "key file not found"
		exit -1
	fi

	split -b 1M -d -a 3 $target_image $outdir/rootfs_part_
	for part in $outdir/rootfs_part_*; do
		openssl enc -aes-256-ecb \
			-in "$part" \
			-out "${part}_enc" \
			-K $(xxd -p -c 32 $key_path | tr -d '\n') \
			-nopad
	done
	cat $outdir/rootfs_part_*_enc > $security_system
	rm -rf $outdir/rootfs_part_*
}

rk_security_setup_system()
{
	case $1 in
		system-verity) shift; rk_security_setup_system_verity $@ ;;
		system-encryption) shift; rk_security_setup_system_encryption $@ ;;
		system-encryption-by-openssl) shift; rk_security_setup_system_encryption_by_openssl $@ ;;
		base) ;;
		*) exit -1;;
	esac
}

rk_security_setup_ramboot_prebuild()
{
	check_method=$1
	shift
	init_in=$1
	shift
	security_file=$1
	shift
	optee_storage=$1

	ROOTFS_IMG=rootfs.${RK_ROOTFS_TYPE}
	ROOTFS_DIR="$RK_OUTDIR/$ROOTFS"
	IMAGE_DIR="$ROOTFS_DIR/images"

	case $check_method in
		system-encryption) echo encryption ;;
		system-encryption-by-openssl) echo encryption-by-openssl ;;
		system-verity) echo verity ;;
		base) return ;;
		*) exit -1;;
	esac

	if [ ! -f "$init_in" ]; then
		echo -e "\e[41;1;37minit_in is missed\e[0m"
		exit -1
	elif [ "$check_method" != "system-encryption-by-openssl" ] && [ ! -f "$security_file" ]; then
		echo -e "\e[41;1;37msecurity_file is missed\e[0m"
		exit -1
	fi

	init_file="$(dirname $init_in)/init"
	cp $init_in $init_file

	if [ "$check_method" == "system-encryption" ]; then
		source "$security_file"
		sed -i "s/ENC_EN=/ENC_EN=true/" "$init_file"
		sed -i "s/CIPHER=/CIPHER=$cipher/" "$init_file"
		sed -i "s/SECURITY_STORAGE=RPMB/SECURITY_STORAGE=$optee_storage/" "$init_file"
	elif [ "$check_method" == "system-encryption-by-openssl" ]; then
		sed -i "s/ENC_EN_BY_OPENSSL=/ENC_EN_BY_OPENSSL=true/" "$init_file"
		system_size=$(ls -l "$(realpath $RK_FIRMWARE_DIR/rootfs.img)" | awk '{printf $5}')
		sed -i "s/SYSTEM_SIZE=/SYSTEM_SIZE=$system_size/" "$init_file"
	else
		source "$security_file"
		sed -i "s/ENC_EN=/ENC_EN=false/" "$init_file"
		sed -i "s/^OFFSET=/OFFSET=$hash_offset/" "$init_file"
		sed -i "s/HASH=/HASH=$root_hash/" "$init_file"
	fi

	sed -i "s/# exec busybox switch_root/exec busybox switch_root/" "$init_file"
	echo "Generate ramdisk init for security"
}

rk_security_setup_sign_tool()
{
	CHIP=${1: 2: 4}

	${RK_SIGN_TOOL} cc --chip $CHIP
	${RK_SIGN_TOOL} lk --key $UBOOT/keys/dev.key --pubkey $UBOOT/keys/dev.pubkey

	if [ "$2" != "--burn-key-hash" ]; then
		sed -i "/sign_flag=/s/.*/sign_flag=/" ${RK_SIGN_INI}
	else
		sed -i "/sign_flag=/s/.*/sign_flag=0x20/" ${RK_SIGN_INI}
	fi
}

rk_security_setup_uboot_avb_sign()
{
	assert_var_in_list $1 "loader uboot trust"

	if [ "$3" ]; then
		cp $2 $3
		DST=$3
	else
		DST=$2
	fi

	case $1 in
		loader) ${RK_SIGN_TOOL} sl --loader $DST;;
		uboot|trust) ${RK_SIGN_TOOL} si --img $DST;;
	esac
}

rk_security_setup_avb_sign()
{
	assert_var_in_list $1 "boot recovery"

	STAGE=$1
	SRC=$(realpath $2)
	DST_DIR=$3

	IMAGE_DIR="${RK_OUTDIR:-$UBOOT}/security"
	mkdir -p "$IMAGE_DIR"
	IMAGE="$IMAGE_DIR/$STAGE-security.img"
	rm -rf "$IMAGE"

	cd $RK_AVB_TOOL_DIR
	$RK_AVB_TOOL -s -${STAGE} $SRC

	cp ${RK_AVB_TOOL_DIR}/out/${STAGE}.img ${IMAGE_DIR}/${STAGE}-security.img
	[ "$STAGE" != "boot" ] || \
		cp ${RK_AVB_TOOL_DIR}/out/vbmeta.img ${IMAGE_DIR}/vbmeta.img

	if [ "$DST_DIR" ]; then
		DST_DIR=$(realpath $DST_DIR)
		ln -rsf ${IMAGE} $DST_DIR/${STAGE}.img
		[ "$STAGE" != "boot" ] || \
			cp ${IMAGE_DIR}/vbmeta.img $DST_DIR/vbmeta.img
	fi

	cd -
}

rk_security_setup_sign()
{
	assert_var_in_list $1 "boot recovery"

	STAGE=$1
	SRC=$(realpath $2)
	DST_DIR=$3

	IMAGE_DIR="${RK_OUTDIR:-$UBOOT}/security"
	mkdir -p "$IMAGE_DIR"
	IMAGE="$IMAGE_DIR/$STAGE-security.img"
	rm -rf "$IMAGE"

	cd $UBOOT
	ln -rsLf "$SRC" "$IMAGE_DIR/$STAGE.img"
	./scripts/fit.sh --${STAGE}_img "$(realpath $IMAGE_DIR/$STAGE.img)"
	mv $STAGE.img "$IMAGE"
	ln -rsf ${IMAGE} $DST_DIR/${STAGE}.img
	cd "${RK_SDK_DIR:-..}"
}

# -----------------------------------
# For SDK
# -----------------------------------
build_security_system()
{
	if [ -z "$1" ]; then
		[ "$RK_ROOTFS_SYSTEM_BUILDROOT" ] || warning "rootfs is not buildroot!"
		"$RK_SCRIPTS_DIR/mk-rootfs.sh"
	else
		image=$(readlink -f $(pwd)/$1)
		if [ ! -f "$image" ]; then
			error "No found $image"
			return -1
		fi

		"$RK_SCRIPTS_DIR/mk-security.sh" system $RK_SECURITY_CHECK_METHOD $image
	fi

	[ -z "$RK_SECURITY_CHECK_SYSTEM_VERITY" ] ||
		"$RK_SCRIPTS_DIR/mk-security.sh" security-ramboot $@

	notice "Security system has updated"
	finish_build $@
}

build_security_ramboot()
{
	check_config RK_SECURITY_INITRD_CFG || false

	message "=========================================="
	message "          Start building security ramboot(buildroot) $1"
	message "=========================================="

	if [ -z "$1" ]; then
		if [ ! -r "$RK_FIRMWARE_DIR/rootfs.img" ]; then
			notice "Rootfs is not ready, building it for security..."
			"$RK_SCRIPTS_DIR/mk-rootfs.sh"
		fi
		security_info=$RK_OUTDIR/buildroot/images/security.info
	else
		image=$(readlink -f $(pwd)/$1)
		if [ ! -f "$image" ]; then
			error "No found $image"
			return -1
		fi
		security_info=$(dirname "$image")/security.info
	fi

	if [ "$RK_SECURITY_OPTEE_STORAGE_SECURITY" ]; then
		OPTEE_STORAGE=SECURITY
	else
		OPTEE_STORAGE=RPMB
	fi

	"$RK_SCRIPTS_DIR/mk-security.sh" ramboot_prebuild \
		$RK_SECURITY_CHECK_METHOD \
		$RK_SDK_DIR/buildroot/board/rockchip/common/security-ramdisk-overlay/init.in \
		$security_info $OPTEE_STORAGE

	DST_DIR="$RK_OUTDIR/security-ramboot"
	IMAGE_DIR="$DST_DIR/images"

	"$RK_SCRIPTS_DIR/mk-buildroot.sh" $RK_SECURITY_INITRD_CFG "$IMAGE_DIR"

	if [ "$RK_USE_FIT_IMG" ]; then
		"$RK_SCRIPTS_DIR/mk-ramboot.sh" "$DST_DIR" \
			"$IMAGE_DIR/rootfs.$RK_SECURITY_INITRD_TYPE" \
			"$RK_SECURITY_FIT_ITS"
	else
		"$RK_SCRIPTS_DIR/mk-ramboot.sh" "$DST_DIR" \
			"$IMAGE_DIR/rootfs.$RK_SECURITY_INITRD_TYPE"
	fi

	if [ "$RK_SECURITY_REMOTE_SIGN" ]; then
		ln -rsf $DST_DIR/ramboot.img $RK_FIRMWARE_DIR/boot.img
		notice "Non-security boot.img has update in output/firmware/boot.img"
	else
		"$RK_SCRIPTS_DIR/mk-security.sh" sign boot \
			$DST_DIR/ramboot.img $RK_FIRMWARE_DIR/
		notice "Security boot.img has update in output/firmware/boot.img"
	fi

	finish_build $@
}

build_security_remote_sign()
{
	if [ "$RK_SECURITY_REMOTE_SIGN" ]; then
		rm -rf $RK_OUTDIR/security-remote
		mkdir -p $RK_OUTDIR/security-remote/src
		cp -rf u-boot/fit/fit_signcfg $RK_OUTDIR/security-remote/src/
		cp -rf rkbin/tools $RK_OUTDIR/security-remote
		loader_file=$(realpath "$RK_FIRMWARE_DIR/MiniLoaderAll.bin")
		cp -rf "$loader_file" "$RK_OUTDIR/security-remote/src/$(basename "$loader_file")"
		uboot_file=$(realpath "$RK_FIRMWARE_DIR/uboot.img")
		cp -rf "$uboot_file" "$RK_OUTDIR/security-remote/src/$(basename "$uboot_file")"
		recovery_file=$(realpath "$RK_FIRMWARE_DIR/recovery.img")
		cp -rf "$recovery_file" "$RK_OUTDIR/security-remote/src/$(basename "$recovery_file")"
		boot_file=$(realpath "$RK_FIRMWARE_DIR/boot.img")
		cp -rf "$boot_file" "$RK_OUTDIR/security-remote/src/$(basename "$boot_file")"
		userdata_file=$(realpath "$RK_FIRMWARE_DIR/userdata.img")
		cd $RK_OUTDIR/security-remote/tools
		"./fit-sign.sh" --key-dir $RK_SDK_DIR/u-boot/keys \
			--src-dir $RK_OUTDIR/security-remote/src \
			--out-dir $RK_OUTDIR/security-remote
		cd -
		mv "$RK_OUTDIR/security-remote/$(basename "$loader_file")" $RK_OUTDIR/security-remote/MiniLoaderAll.bin
	fi

	finish_build $@
}

# Hooks

BUILD_CMDS="security-createkeys security-misc security-ramboot security-system security-remote-sign"
HID_CMDS="createkeys misc system ramboot_prebuild sign"

build_avb_sign()
{
	case $1 in
		loader|uboot|trust)
			rk_security_setup_sign_tool $RK_CHIP \
				"$(test $RK_SECURITY_BURN_KEY && \
					echo --burn-key-hash || \
					echo --debug-key-hash)"
			rk_security_setup_uboot_avb_sign $@ ;;
		recovery)
			rk_security_setup_avb_sign $@ \
				$[ $(rk_partition_size_kb recovery) * 1024 ];;
		*)
			rk_security_setup_avb_sign $@;;
	esac
}

build_hook()
{
	item=$1
	shift

	case $item in
		security-createkeys)
			rk_security_setup_createkeys $RK_SECURITY_CHECK_METHOD;;
		security-misc)
			if [ "$RK_SECURITY_CHECK_SYSTEM_ENCRYPTION" ]; then
				"$RK_SCRIPTS_DIR/mk-misc.sh"
			fi
			;;
		security-ramboot) build_security_ramboot $@;;
		security-system) build_security_system $@;;
		security-remote-sign) build_security_remote_sign $@;;
	esac

	echo $HID_CMDS | fgrep "$item" -wq || return 0
	append=$item

	case $append in
		sign)
			test "$RK_SECUREBOOT_AVB" && \
				build_avb_sign $@ || \
				rk_security_setup_$append $@
			;;
		*) rk_security_setup_$append $@ ;;
	esac
}

usage_hook()
{
	usage_oneline "security-createkeys" "create keys for security"
	usage_oneline "security-misc" "build misc with system encryption key"
	usage_oneline "security-ramboot[:system_image]" "build security ramboot"
	usage_oneline "security-system[:system_image]" "build security system"
	usage_oneline "security-remote-sign" "build remote signed image"
}

clean_hook()
{
	rm -rf $RK_OUTDIR/security*
}

[ -z "$RK_SESSION" ] || \
	source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/build-helper}"

[ -z "$1" ] || build_hook $@
