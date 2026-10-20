#!/bin/sh
# Collects what is needed to debug the Arch port on the tablet.
#   sudo sh gta4l-tani.sh > tani.txt
# The output has no serial numbers or MAC addresses.
u=$(id -un 1000 2>/dev/null || echo alarm)
hide() { sed -E -e 's/(serialno|androidboot\.un|ap_serial|em\.did)=[^ ]*/\1=HIDDEN/g' \
	-e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/XX:XX:XX:XX:XX:XX/g'; }
s() { echo; echo "===== $*"; sh -c "$*" 2>&1 | hide | tail -n 60; }

s uname -a
s 'systemctl --failed --no-legend'
s 'journalctl -b -p err --no-pager | tail -40'
echo; echo "===== desktop"
s 'journalctl -b -u sddm --no-pager | tail -30'
s "journalctl -b _UID=\$(id -u $u) --no-pager | grep -i -E 'plasma|kwin|startplasma|error|fail' | tail -40"
s 'ls -la /home/*/.local/share/sddm/*.log 2>/dev/null; tail -30 /home/*/.local/share/sddm/wayland-session.log 2>/dev/null'
echo; echo "===== sound"
s 'cat /proc/asound/cards'
s 'ls /usr/share/alsa/ucm2/conf.d/sm4250/ /usr/share/alsa/ucm2/Samsung/gta4l/ 2>&1'
s 'alsaucm -c 0 list _verbs 2>&1'
s "sudo -u $u XDG_RUNTIME_DIR=/run/user/\$(id -u $u) wpctl status 2>&1 | head -40"
s "systemctl --user -M $u@ status gta4l-ses-kontrol pipewire wireplumber --no-pager 2>&1 | head -30"
echo; echo "===== brightness"
s 'for b in /sys/class/backlight/*; do echo $b; ls -la $b/brightness; cat $b/brightness $b/max_brightness; done'
s "id $u"
echo; echo "===== battery"
s 'for p in /sys/class/power_supply/*; do echo "$p: $(cat $p/type 2>/dev/null) cap=$(cat $p/capacity 2>/dev/null) st=$(cat $p/status 2>/dev/null) uv=$(cat $p/voltage_now 2>/dev/null)"; done'
s 'upower -d | grep -E "native-path|percentage|state|energy-full|model" | head -20'
s 'systemctl status gta4l-battery-count --no-pager | head -10'
echo; echo "===== qualcomm"
s 'systemctl status rmtfs tqftpserv hexagonrpcd-adsp-rootpd hexagonrpcd-adsp-sensorspd iio-sensor-proxy --no-pager | grep -E "●|Active:|Main PID|error" '
