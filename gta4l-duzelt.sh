#!/bin/sh
# Fixes for an already installed gta4l Arch Linux ARM, run on the tablet:
#   sudo sh gta4l-duzelt.sh
# Safe to run more than once. Needs internet for the packages.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo sh $0"; exit 1; }
u=$(id -un 1000 2>/dev/null || echo alarm)
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== sensors: hexagonrpcd runs as the 'fastrpc' user"
getent group fastrpc >/dev/null || groupadd -r fastrpc
getent passwd fastrpc >/dev/null || useradd -r -g fastrpc -d / -s /usr/bin/nologin fastrpc
systemctl reset-failed hexagonrpcd-adsp-rootpd hexagonrpcd-adsp-sensorspd 2>/dev/null || true
systemctl restart hexagonrpcd-adsp-rootpd hexagonrpcd-adsp-sensorspd 2>/dev/null || true

echo "== DNS: resolv.conf points to systemd-resolved"
systemctl enable --now systemd-resolved

echo "== packages: Plasma complete, power profiles (tuned-ppd), iw"
pacman -Syu --noconfirm --needed plasma-desktop plasma-workspace libplasma \
	plasma-nm plasma-pa powerdevil kscreen kde-cli-tools iw qt6-sensors || \
	echo "pacman failed (network?): run the script again"
if pacman -S --noconfirm --needed tuned tuned-ppd; then
	systemctl enable --now tuned tuned-ppd
elif pacman -S --noconfirm --needed power-profiles-daemon; then
	systemctl enable --now power-profiles-daemon
fi

echo "== Venus: hardware video decode is safe with the current modules"
rm -f /etc/modprobe.d/gta4l-venus.conf

echo "== system settings"
sh "$HERE/gta4l-ayarlar.sh"

echo "== zram off now"
swapoff -a 2>/dev/null || true
systemctl stop systemd-zram-setup@zram0 2>/dev/null || true

echo "== brightness now"
chgrp video /sys/class/backlight/*/brightness
chmod g+w /sys/class/backlight/*/brightness

echo "== sound: unmute the speakers"
uid=$(id -u $u)
if [ -S /run/user/$uid/pipewire-0 ]; then
	sudo -u $u XDG_RUNTIME_DIR=/run/user/$uid wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 || true
fi

echo "DONE. Reboot."
