#!/bin/sh
# Turns an Arch Linux ARM aarch64 rootfs into one for the Samsung Galaxy Tab A7
# 10.4 2020 (SM-T500, gta4l) and makes an Odin userdata image of it.
#
#   sudo sh gta4l-arch-kur.sh <ArchLinuxARM-aarch64-latest.tar.gz | rootfs-dir>
#
# Needs: bsdtar, mke2fs, img2simg; on a non-ARM PC also qemu-user-static with
# binfmt (Debian/Ubuntu: apt install qemu-user-static binfmt-support
# libarchive-tools android-sdk-libsparse-utils).
#
# The tablet keeps the postmarketOS boot (U-Boot) and cache (/boot: kernel,
# initramfs); this image replaces only userdata. It carries the pmOS root UUID,
# so the pmOS initramfs mounts it.
set -e
[ "$(id -u)" = 0 ] || { echo "run as root: sudo sh $0 <rootfs>"; exit 1; }
[ -n "$1" ] || { echo "usage: sudo sh $0 <ArchLinuxARM-aarch64-latest.tar.gz | rootfs-dir>"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(realpath "$1")
W=${WORK:-$HERE/work}
R=$W/root
ROOT_UUID=e40846ad-f8b5-43f9-b679-e54043c5dc7b

printf "Password for the 'alarm' user: "
stty -echo; read PW; stty echo; echo
[ -n "$PW" ] || { echo "empty password"; exit 1; }

for t in bsdtar mke2fs img2simg; do
	command -v $t >/dev/null || { echo "missing: $t"; exit 1; }
done
if [ "$(uname -m)" != aarch64 ]; then
	[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || update-binfmts --enable qemu-aarch64 2>/dev/null || true
	[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || { echo "qemu-aarch64 binfmt is not registered (install qemu-user-static)"; exit 1; }
fi

cleanup() {
	for m in $R/var/cache/pacman/pkg $R/dev $R/proc $R/sys $R/run; do
		mountpoint -q $m 2>/dev/null && umount -l $m
	done
	return 0
}
trap cleanup EXIT INT TERM
cleanup

echo "== 1) rootfs"
rm -rf $R; mkdir -p $R
if [ -d "$SRC" ]; then
	cp -a "$SRC/." $R/
else
	bsdtar -xpf "$SRC" -C $R
fi
[ -x $R/usr/bin/pacman ] || { echo "this is not an Arch Linux ARM rootfs"; exit 1; }

echo "== 2) packages (slow under qemu)"
mount -t proc proc $R/proc
# rslave: unmounting these later must not take /dev/shm, /dev/pts etc. off the host
mount --rbind /sys $R/sys
mount --make-rslave $R/sys
mount --rbind /dev $R/dev
mount --make-rslave $R/dev
mount -t tmpfs tmpfs $R/run
# Keep downloaded packages outside the rootfs, so a rerun does not fetch them again
mkdir -p $W/pkgcache $R/var/cache/pacman/pkg
mount --bind $W/pkgcache $R/var/cache/pacman/pkg
rm -f $R/etc/resolv.conf
cp -L /etc/resolv.conf $R/etc/resolv.conf
sed -i -e 's/^CheckSpace/#CheckSpace/' $R/etc/pacman.conf
grep -q '^DisableSandbox' $R/etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' $R/etc/pacman.conf
# Our iio-sensor-proxy (with the Qualcomm sensor backend) replaces Arch's
grep -q 'usr/libexec/iio-sensor-proxy' $R/etc/pacman.conf || \
	sed -i '/^\[options\]/a NoExtract = usr/libexec/iio-sensor-proxy usr/bin/monitor-sensor' $R/etc/pacman.conf

# mirror.archlinuxarm.org redirects to a random mirror, which often times out:
# try several fixed mirrors in turn
cat > $R/etc/pacman.d/mirrorlist <<'EOF'
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
EOF
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 3/' $R/etc/pacman.conf

cat > $R/root/gta4l-pkgs.sh <<'EOF'
set -e
# Downloads time out now and then: retry
retry() {
	for i in 1 2 3 4 5; do
		"$@" && return 0
		echo "retry $i: $*"; sleep 5
	done
	return 1
}
pacman-key --init
pacman-key --populate archlinuxarm
# The tablet boots the kernel and initramfs from its cache partition, and
# gta4l-parts carries the firmware: drop the generic kernel and the
# linux-firmware packages before the upgrade, so they are not downloaded
pacman -Rdd --noconfirm $(pacman -Qq | grep -E '^(linux-aarch64|linux-firmware.*|mkinitcpio.*)$') || true
retry pacman -Syu --noconfirm
retry pacman -S --noconfirm --needed \
	sudo mtools dosfstools e2fsprogs \
	plasma-desktop plasma-nm plasma-pa powerdevil bluedevil kscreen kinfocenter \
	systemsettings breeze-gtk xdg-desktop-portal-kde sddm sddm-kcm \
	konsole dolphin ark spectacle firefox fastfetch \
	networkmanager wpa_supplicant bluez bluez-utils \
	pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils alsa-ucm-conf \
	mesa vulkan-freedreno iio-sensor-proxy upower polkit \
	noto-fonts breeze-icons iw qt6-sensors
retry pacman -S --noconfirm --needed plasma-keyboard || retry pacman -S --noconfirm --needed maliit-keyboard
# Power profiles in Plasma (tuned, with its power-profiles-daemon API)
retry pacman -S --noconfirm --needed tuned tuned-ppd || retry pacman -S --noconfirm --needed power-profiles-daemon || true
EOF
chroot $R /bin/bash /root/gta4l-pkgs.sh
rm -f $R/root/gta4l-pkgs.sh

echo "== 3) gta4l parts"
# Kernel modules, firmware, udev/systemd/audio files, sensor data, and the
# Qualcomm services built for musl (in /usr/lib/gta4l-musl, run by wrappers)
bsdtar -xpf $HERE/gta4l-parts.tar.gz -C $R

echo "== 4) settings"
echo "UUID=$ROOT_UUID / ext4 defaults,x-systemd.growfs 0 1" > $R/etc/fstab
echo gta4l > $R/etc/hostname
ln -sf /usr/share/zoneinfo/Europe/Istanbul $R/etc/localtime
sed -i -e 's/^#tr_TR.UTF-8/tr_TR.UTF-8/' -e 's/^#en_US.UTF-8/en_US.UTF-8/' $R/etc/locale.gen
echo LANG=en_US.UTF-8 > $R/etc/locale.conf
# Venus (video decode) resets the tablet; keep it off for now
printf 'blacklist venus_core\nblacklist venus_dec\nblacklist venus_enc\n' > $R/etc/modprobe.d/gta4l-venus.conf
mkdir -p $R/etc/sudoers.d
cp $HERE/gta4l-tani.sh $R/usr/local/bin/gta4l-tani
chmod 755 $R/usr/local/bin/gta4l-tani
echo '%wheel ALL=(ALL:ALL) ALL' > $R/etc/sudoers.d/10-wheel
chmod 440 $R/etc/sudoers.d/10-wheel
cat > $R/root/gta4l-setup.sh <<'EOF'
set -e
locale-gen
depmod -a $(ls /usr/lib/modules | grep postmarketos | head -1)
usermod -aG wheel,audio,video,input alarm
# hexagonrpcd (sensors) runs as this user
getent group fastrpc >/dev/null || groupadd -r fastrpc
getent passwd fastrpc >/dev/null || useradd -r -g fastrpc -d / -s /usr/bin/nologin fastrpc
# A cut-short download leaves packages half installed: check the desktop is complete
pacman -Q libplasma plasma-workspace kwin sddm >/dev/null
chpasswd < /root/pw
passwd -l root
# resolv.conf points to the systemd-resolved stub, so resolved must run
systemctl enable NetworkManager systemd-resolved bluetooth sddm rmtfs tqftpserv
systemctl enable tuned tuned-ppd 2>/dev/null || systemctl enable power-profiles-daemon 2>/dev/null || true
for u in $(ls /usr/lib/systemd/system | grep -E '^(gta4l|hexagonrpcd)-.*\.service$'); do
	systemctl preset $u 2>/dev/null || true
done
systemctl --global preset gta4l-ses-kontrol.service 2>/dev/null || true
EOF
printf 'alarm:%s\n' "$PW" > $R/root/pw
chroot $R /bin/bash /root/gta4l-setup.sh
rm -f $R/root/gta4l-setup.sh $R/root/pw
# Brightness, SDDM (Breeze), Wi-Fi power saving off, USB network with DHCP,
# volume above 100 %, microphone gain
sh $HERE/gta4l-ayarlar.sh $R
rm -f $R/etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf $R/etc/resolv.conf
cleanup

echo "== 5) image"
SIZE=$(du -sm $R | cut -f1)
SIZE=$((SIZE + SIZE / 5 + 512))
rm -f $W/root.img
mke2fs -q -t ext4 -U $ROOT_UUID -L arch_root -d $R $W/root.img ${SIZE}M
e2fsck -fn $W/root.img >/dev/null && echo "fsck clean"
mkdir -p $W/odin
img2simg $W/root.img $W/odin/userdata.img
rm -f $W/root.img
(cd $W/odin && tar -H ustar -cf $HERE/arch-userdata.tar userdata.img)
ls -la $HERE/arch-userdata.tar
echo "DONE: flash arch-userdata.tar with Odin (AP). Keep the postmarketOS boot and cache."
