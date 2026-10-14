#!/bin/bash -e
### BEGIN INIT INFO
# Provides:          rockchip
# Required-Start:
# Required-Stop:
# Default-Start:
# Default-Stop:
# Short-Description:
# Description:       Setup RK3308BS platform environment
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

compatible=$(cat /proc/device-tree/compatible)
if ! echo "$compatible" | grep -q rk3308; then
    echo "This script is for RK3308BS only."
    exit 1
fi

setup_default_capture_volume() {
    # Apply only once to provide sane factory recording volume defaults.
    local flag_file="/usr/local/audio_default_flag"
    echo "[rockchip] setup_default_capture_volume() start"
    [ -e "$flag_file" ] && return 0
    echo "[rockchip] audio_default_flag not present, will apply defaults"
    command -v amixer >/dev/null 2>&1 || return 0

    # This device uses card index 1 (rk3308-acodec). Hardcode it to avoid
    # fragile parsing differences across build/boot environments.
    local card=1

    # Wait a bit for ALSA controls to appear.
    echo "[rockchip] using alsa card=$card, waiting for scontrols..."
    for _ in 1 2 3 4 5; do
        amixer -c "$card" scontrols >/dev/null 2>&1 && break
        sleep 0.2
    done
    if ! amixer -c "$card" scontrols >/dev/null 2>&1; then
        echo "[rockchip] amixer scontrols still not ready, skip"
        return 0
    fi
    echo "[rockchip] amixer scontrols ready"

    local updated=0

    # Retry a few times in case the codec/controls appear slightly later.
    for _ in 1 2 3 4 5; do
        set_ctl() {
            local name="$1"
            shift
            echo "[rockchip] set '$name' = $* ..."
            if amixer -c "$card" sset "$name" "$@" >/dev/null 2>&1; then
                updated=1
                echo "[rockchip]   ok"
            else
                echo "[rockchip]   FAIL"
            fi
        }

        set_ctl "Main Mic" on
        set_ctl "Headset Mic" off
        set_ctl "ADC Main MICBIAS" on
        set_ctl "ADC MICBIAS1" on

        set_ctl "ADC MIC Group 0 Left" on
        set_ctl "ADC MIC Group 0 Right" on

        # These controls are very low-resolution on this codec (0..3).
        # Use the maximum to get a noticeable recording level.
        set_ctl "ADC MIC Group 0 Left Gain" 3
        set_ctl "ADC MIC Group 0 Right Gain" 3

        # ALC range is 0..31; increase moderately to avoid distortion.
        set_ctl "ADC ALC Group 0 Left" 16
        set_ctl "ADC ALC Group 0 Right" 16

        [ "$updated" -eq 1 ] && break
        sleep 0.2
    done

    # Only mark "done" when we successfully applied at least one control.
    if [ "$updated" -eq 1 ]; then
        command -v alsactl >/dev/null 2>&1 && alsactl store >/dev/null 2>&1 || true
        touch "$flag_file"
        echo "[rockchip] defaults applied, flag touched: $flag_file"
    fi
}

# RK3308BS: no GPU, use software rendering
[ -e /etc/X11/xorg.conf.d/20-modesetting.conf ] && \
    sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf

# first boot configure
if [ ! -e "/usr/local/first_boot_flag" ]; then
    echo "It's the first time booting. The rootfs will be configured."

    mount -o remount,sync /

    if [ -e "/dev/rfkill" ]; then
        rm /dev/rfkill
    fi

    rm -rf /*.deb /*.tar

    touch /usr/local/first_boot_flag

    sync
    shutdown -r now
fi

# setup default mic capture gain for rk3308-acodec
setup_default_capture_volume

# sync system time
hwclock --systohc


