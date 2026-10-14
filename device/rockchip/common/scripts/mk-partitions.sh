#!/bin/bash -e

# Hooks

usage_hook()
{
	usage_oneline "print-parts" "print partitions"
	usage_oneline "list-parts" "alias of print-parts"
	usage_oneline "edit-parts" "edit raw partitions"
}

PRE_BUILD_CMDS="print-parts list-parts edit-parts"
pre_build_hook()
{
	check_config RK_PARAMETER || false

	CMD=$1
	shift

	case "$CMD" in
		print-parts | list-parts) rk_partition_print $@ ;;
		edit-parts) rk_partition_edit $@ ;;
		*)
			normalized_usage
			exit 1
			;;
	esac

	finish_build $CMD $@
}

source "${RK_BUILD_HELPER:-$(dirname "$(realpath "$0")")/build-helper}"

pre_build_hook $@
