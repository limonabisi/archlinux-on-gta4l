# Arch Linux ARM on the Galaxy Tab A7 10.4 2020 (SM-T500, gta4l)

Builds an Arch Linux ARM userdata image for the tablet: the official Arch Linux
ARM rootfs plus the gta4l parts of the postmarketOS port
([limonabisi/pmaports-gta4l](https://github.com/limonabisi/pmaports-gta4l),
kernel [limonabisi/linux-gta4l](https://github.com/limonabisi/linux-gta4l/tree/gta4l-7.2-clean)).

## Contents

- `gta4l-arch-kur.sh`: builds the image.
- `gta4l-parts.tar.gz`: the gta4l parts, unpacked over the rootfs:
  - kernel modules (7.2.0, with Bluetooth RFCOMM/BNEP)
  - firmware from linux-firmware, the touch firmware of every panel variant,
    the speaker tuning and the GPU zap shader
  - udev rules, systemd units, ALSA UCM, sensor data
  - the Qualcomm services rmtfs, tqftpserv, hexagonrpcd and iio-sensor-proxy,
    built for musl. They run from `/usr/lib/gta4l-musl` through small wrappers,
    next to Arch's glibc.
- `gta4l-ayarlar.sh`: system settings, used by the build and by `gta4l-duzelt.sh`.
- `gta4l-duzelt.sh`: brings an image made with an older version up to date.
- `gta4l-tani.sh`: collects a debug report.
- `tools/gta4l-overlay.py`: how `gta4l-parts.tar.gz` is made from a working
  postmarketOS rootfs (musl programs moved aside and wrapped).

Samsung's own firmware (ADSP, CDSP, Venus, Wi-Fi DSP) is not in this
repository: `gta4l-firmware-import` copies it from the tablet's firmware
partitions at boot, read with mtools, never mounted.

## Requirements

- The tablet already runs postmarketOS from the pmaports-gta4l image. Its
  `boot` (U-Boot) and `cache` (kernel, initramfs) stay; only `userdata` is
  replaced.
- A Linux PC, or WSL, with:

```sh
sudo apt install qemu-user-static binfmt-support libarchive-tools android-sdk-libsparse-utils
```

## Use

```sh
wget http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
sudo sh gta4l-arch-kur.sh ArchLinuxARM-aarch64-latest.tar.gz
```

The script asks for the password of the `alarm` user. `root` is locked; use
`sudo`. Installing the packages under qemu takes 30 to 60 minutes. The result
is `arch-userdata.tar`; flash it with Odin as AP.

## What you get

- Plasma (Wayland) with the SDDM login screen and the on-screen keyboard.
- NetworkManager, Bluetooth, PipeWire (kept at 16 bit: 24 bit plays far too
  quietly), Firefox, power profiles (tuned-ppd).
- Screen rotation and the light sensor through the ADSP.
- `ssh alarm@172.16.42.1` over the USB cable (the PC gets an address by DHCP).
- No swap or zram; Baloo, KWallet, kaccess, at-spi and the X11 tray/menu
  bridges are off to save RAM; glibc keeps two malloc arenas.
- Wi-Fi power saving off, weekly TRIM, a 64 MB journal.

## Known problems

- Venus (hardware video) is blacklisted: encoding crashes the tablet.
- USB OTG and charging at the same time is not possible: the PMI632 has no
  USB PD PHY, so a hub cannot swap the power role.
- Headphones: only the left channel plays.
- No camera.

## Reporting problems

Run `sudo sh gta4l-tani.sh > report.txt` on the tablet and send report.txt
(serial numbers and MAC addresses are hidden).
