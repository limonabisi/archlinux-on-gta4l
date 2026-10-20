#!/bin/sh
# gta4l system settings for Arch Linux ARM. Used by gta4l-arch-kur.sh (on
# the image being built: sh gta4l-ayarlar.sh <root>) and by gta4l-duzelt.sh
# (on the tablet: sh gta4l-ayarlar.sh). Only writes configuration files.
set -e
R=${1:-}

# Brightness: the video group (the desktop user) may write it
mkdir -p $R/etc/udev/rules.d
cat > $R/etc/udev/rules.d/90-gta4l-backlight.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/usr/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="/usr/bin/chmod g+w /sys/class/backlight/%k/brightness"
EOF

# Sensors: Arch's iio-sensor-proxy rules only offer the light sensor and the
# compass of the ADSP; the accelerometer (screen rotation) is there too
cat > $R/etc/udev/rules.d/81-gta4l-ssc.rules <<'EOF'
SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel"
EOF

# SDDM: Wayland greeter with Plasma's Breeze theme
mkdir -p $R/etc/sddm.conf.d
cat > $R/etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1

[Theme]
Current=breeze
EOF

# Wi-Fi: power saving makes the WCN3990 miss networks and drop range
mkdir -p $R/etc/NetworkManager/conf.d
cat > $R/etc/NetworkManager/conf.d/90-gta4l-wifi.conf <<'EOF'
[connection]
wifi.powersave=2
EOF

# USB network: the initramfs makes the tablet a USB network device (NCM,
# "Samsung Galaxy Tab A7 10.4 2020") with 172.16.42.1; hand the computer an
# address on it, so "ssh alarm@172.16.42.1" works over the cable.
cat > $R/etc/NetworkManager/conf.d/90-gta4l-usb0.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:usb0
EOF
mkdir -p $R/etc/systemd/network
cat > $R/etc/systemd/network/50-gta4l-usb0.network <<'EOF'
[Match]
Name=usb0

[Network]
Address=172.16.42.1/24
DHCPServer=yes
ConfigureWithoutCarrier=yes
LinkLocalAddressing=no

[DHCPServer]
PoolOffset=2
PoolSize=1
EmitDNS=no
EmitRouter=no
EOF
if [ -n "$R" ]; then
	ln -sf /usr/lib/systemd/system/systemd-networkd.service \
		$R/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
	ln -sf /dev/null $R/etc/systemd/system/systemd-networkd-wait-online.service
else
	systemctl mask systemd-networkd-wait-online.service
	systemctl enable --now systemd-networkd
fi

# Plasma: allow the volume above 100 %; the speaker amplifiers are at their
# maximum and 100 % (0 dB) is quiet on this tablet
mkdir -p $R/etc/xdg
cat > $R/etc/xdg/plasmaparc <<'EOF'
[General]
RaiseMaximumVolume=true
EOF

# Sound: PipeWire picks S24_LE for the card, which the DSP plays about 48 dB
# too quietly; pmOS's PulseAudio used S16_LE. Keep the card at 16 bit.
mkdir -p $R/etc/wireplumber/wireplumber.conf.d
cat > $R/etc/wireplumber/wireplumber.conf.d/50-gta4l-s16.conf <<'EOF'
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_(output|input).platform-sound.*" } ]
    actions = { update-props = { audio.format = "S16LE" } }
  }
]
EOF

# eMMC wear: weekly TRIM, and a small journal
mkdir -p $R/etc/systemd/journald.conf.d $R/etc/systemd/system/timers.target.wants
printf '[Journal]\nSystemMaxUse=64M\n' > $R/etc/systemd/journald.conf.d/90-gta4l.conf
if [ -n "$R" ]; then
	ln -sf /usr/lib/systemd/system/fstrim.timer $R/etc/systemd/system/timers.target.wants/fstrim.timer
else
	systemctl enable --now fstrim.timer
fi

# Memory: no zram swap
mkdir -p $R/etc/systemd
printf '# gta4l: no zram swap\n' > $R/etc/systemd/zram-generator.conf

# Memory: Plasma services this tablet does not need
#  - Baloo file indexer (also keeps the eMMC busy)
#  - kaccess (accessibility), the X11 tray and menu bridges (with them gone,
#    Xwayland only starts for an X11 application)
cat > $R/etc/xdg/baloofilerc <<'EOF'
[Basic Settings]
Indexing-Enabled=false
EOF
mkdir -p $R/etc/systemd/user
#  - the accessibility bus (at-spi) and KWallet
for u in plasma-kaccess plasma-xembedsniproxy plasma-gmenudbusmenuproxy at-spi-dbus-bus; do
	ln -sf /dev/null $R/etc/systemd/user/$u.service
done
cat > $R/etc/xdg/kwalletrc <<'EOF'
[Wallet]
Enabled=false
First Use=false
EOF
#  - the headphone jack refresher (headphones are not used)
mkdir -p $R/etc/systemd/system
ln -sf /dev/null $R/etc/systemd/system/gta4l-jack-yenile.service
#  - PowerDevil probing for external monitors over DDC/CI (i2c errors at login)
mkdir -p $R/etc/environment.d
#  - glibc gives every thread its own malloc arena; Plasma's many threads
#    then keep far more memory than on musl (postmarketOS). Two arenas.
printf 'POWERDEVIL_NO_DDCUTIL=1\nNO_AT_BRIDGE=1\nMALLOC_ARENA_MAX=2\n' > $R/etc/environment.d/90-gta4l.conf

# Microphones: give the WCD937x ADCs some gain (0 = silent, max 20)
U=$R/usr/share/alsa/ucm2/Samsung/gta4l/HiFi.conf
if [ -f $U ] && ! grep -q "ADC1 Volume" $U; then
	sed -i -e "s/^\(\t\tcset \"name='ADC1 Switch' 1\"\)$/\1\n\t\tcset \"name='ADC1 Volume' 12\"/" \
	       -e "s/^\(\t\tcset \"name='ADC2 Switch' 1\"\)$/\1\n\t\tcset \"name='ADC2 Volume' 12\"/" $U
fi
grep -c "ADC[12] Volume" $U 2>/dev/null || true
