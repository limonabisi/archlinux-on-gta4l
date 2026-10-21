# Arch Linux ARM on the Galaxy Tab A7 10.4 2020 (SM-T500, gta4l)

Builds an Arch Linux ARM userdata image for the tablet: the official Arch Linux
ARM rootfs plus the gta4l parts of the postmarketOS port
([limonabisi/pmaports-gta4l](https://github.com/limonabisi/pmaports-gta4l),
kernel [limonabisi/linux-gta4l](https://github.com/limonabisi/linux-gta4l/tree/gta4l-7.2-clean)).

## Quick install (prebuilt image)

The [Releases](https://github.com/limonabisi/archlinux-on-gta4l/releases) page has
a ready image for the SM-T500 (Wi-Fi). It holds the whole system: U-Boot and the
kernel (`boot`), `dtbo`, the kernel and initramfs on `cache`, and Arch Linux ARM on
`userdata`.

**This erases everything on the tablet.** You need an unlocked bootloader:
Settings → Developer options → OEM unlocking, then in Download mode hold
Volume Up to unlock.

1. Download `gta4l-arch.tar.xz` (about 1 GB) and `SHA256SUMS`.
2. Unpack it into `gta4l-arch.tar` (4.4 GB):
   - Windows: extract it with [7-Zip](https://www.7-zip.org).
   - Linux: `xz -dk gta4l-arch.tar.xz`
3. Power the tablet off, hold Volume Up + Volume Down and plug in the USB
   cable: Download mode.
4. In Odin, put `gta4l-arch.tar` in **AP** and press Start.
5. The first boot takes a few minutes: the firmware is copied from the
   tablet's own partitions, the root filesystem grows to fill `userdata`
   and pacman gets its keyring.

Log in as **`alarm`**, password **`1234`**. The **tablet setup** opens by
itself (the on-screen keyboard works in it) and asks for:

- your user name and full name (a new name replaces `alarm`, which is
  removed on the next boot),
- your password, which is also your `sudo` password,
- the tablet's name, the time zone, the language and the keyboard layout,
- whether SSH should be on.

"Apply and restart" makes the changes and restarts the tablet. "Later" closes
it until the next login; run it again any time with `gta4l-setup` or from the
application menu ("Tablet setup").

`root` is locked; use `sudo`. SSH stays off unless you turn it on in the setup.

Over the USB cable the tablet is `alarm@172.16.42.1`.

Updates: `sudo pacman -Syu`. The kernel lives on the `cache` partition, so
pacman does not touch it.

Back to Android: flash Samsung's stock firmware with Odin.

## Contents

- `gta4l-arch-kur.sh`: builds the image.
- `gta4l-parts.tar.gz`: the gta4l parts, unpacked over the rootfs:
  - kernel modules (7.2.0, with Bluetooth RFCOMM/BNEP and the Venus fix for
    Samsung's firmware)
  - firmware from linux-firmware, the touch firmware of every panel variant,
    the speaker tuning and the GPU zap shader
  - udev rules, systemd units, ALSA UCM, sensor data
  - the Qualcomm services rmtfs, tqftpserv, hexagonrpcd and iio-sensor-proxy,
    built for musl. They run from `/usr/lib/gta4l-musl` through small wrappers,
    next to Arch's glibc.
- `gta4l-ayarlar.sh`: system settings, used by the build and by `gta4l-duzelt.sh`.
- `gta4l-duzelt.sh`: brings an image made with an older version up to date.
- `gta4l-tani.sh`: collects a debug report.
- `firstboot/`: the tablet setup shown on the first login.
- `tools/gta4l-overlay.py`: how `gta4l-parts.tar.gz` is made from a working
  postmarketOS rootfs (musl programs moved aside and wrapped).

Samsung's own firmware (ADSP, CDSP, Venus, Wi-Fi DSP) is not in this
repository: `gta4l-firmware-import` copies it from the tablet's firmware
partitions at boot, read with mtools, never mounted.

## Build the image yourself

### Requirements

- The tablet already runs postmarketOS from the pmaports-gta4l image. Its
  `boot` (U-Boot) and `cache` (kernel, initramfs) stay; only `userdata` is
  replaced.
- A Linux PC, or WSL, with:

```sh
sudo apt install qemu-user-static binfmt-support libarchive-tools android-sdk-libsparse-utils
```

### Build

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

- Hardware video: only H.264 and HEVC decoding. Samsung's Venus firmware
  (6.0.49) predates the fixes of 6.0.55, so encoding and VP9 are off.
- USB OTG and charging at the same time is not possible: the PMI632 has no
  USB PD PHY, so a hub cannot swap the power role.
- Headphones: only the left channel plays.
- No camera.

## Reporting problems

Run `sudo sh gta4l-tani.sh > report.txt` on the tablet and send report.txt
(serial numbers and MAC addresses are hidden).

## Status

✅ works · ⚠️ partial · ❌ broken · ❔ untested on Arch

| Feature | Status | Notes |
|---|:---:|---|
| Boot (U-Boot + pmOS kernel 7.2) | ✅ | Arch root on `userdata` |
| Display | ✅ | 1200x2000, brightness control |
| Touchscreen | ✅ | NT36523 (lide-hsd panel) tested |
| GPU acceleration | ✅ | Adreno 610: freedreno (OpenGL), Turnip (Vulkan) |
| Plasma (Wayland) + SDDM | ✅ | |
| On-screen keyboard | ✅ | plasma-keyboard |
| Wi-Fi | ✅ | WCN3990, power saving off |
| Bluetooth | ✅ | RFCOMM and BNEP modules included |
| Speakers | ✅ | Kept at 16 bit; volume above 100 % allowed |
| Microphone | ✅ | |
| Headphones | ⚠️ | Only the left channel plays |
| Screen rotation | ✅ | Accelerometer through the ADSP |
| Ambient light / compass | ❔ | Work on postmarketOS |
| Battery level | ⚠️ | The percentage can drift |
| Charging | ✅ | |
| Offline charging | ✅ | In U-Boot, with the percentage |
| Power profiles | ✅ | tuned-ppd |
| USB networking | ✅ | `ssh alarm@172.16.42.1`, DHCP for the PC |
| USB OTG (host) | ✅ | Keyboard, mouse, storage, Ethernet |
| USB OTG while charging | ❌ | No USB PD on the PMI632 |
| Suspend (s2idle) | ❔ | Works on postmarketOS |
| Hardware video decode (Venus) | ⚠️ | H.264 and HEVC up to 1080p; VP9 off (firmware crash) |
| Hardware video encode | ❌ | Samsung firmware 6.0.49 is too old |
| Camera | ❌ | No driver |
| GPS | ❌ | No position (NMEA times out) |
| Mobile data / calls | — | SM-T500 is Wi-Fi only |
