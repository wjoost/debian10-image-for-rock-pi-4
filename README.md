# Debian 10 image for Raxda ROCK Pi 4

This repo contains a Makefile which will create a debian 10 image for
Raxda ROCK Pi 4 boards.

## State

Not finished yet. Known issues:

* USB OTG port does not work in bootloader

Not implemented:

* HDMI out (does not work reliable, might even break hw)
* SATA (adapt kernel config when needed)

Not checked:

* Audio
* GPIO / SPI / I2C
* PCIe seems to work
* Bluetooth (wip)

## Build

You need a debian 10 build machine with root rights.

* Configure a normal user
* Allow this user using sudo without password
* Install native and cross compiler gcc-aarch64-linux-gnu and gcc-arm-none-eabi
* Install qemu-user-static and debootstrap
* Install make
* Start make

The resulting image rockpi4.img.gz can be flashed to an emmc module or a sd
card. However, the bootloader wants to load its environment from emmc. If you
want to boot from sd, change the setting CONFIG_SYS_MMC_ENV_DEV to 1 in
include/configs/evb_rk3399.h and update /etc/fw_env.config in
configure_debian.sh.

## Rescue USB

The image can be copied to an USB stick as well. The bootloader has been
configured to look for a linux system on an usb stick first. This way a
non-working system can be started from USB as long as the bootloader is still
intact. However, you should build an extra image for USB.
Remove rockpi4.img.gz and call `make VGNAME=vgusbrescue rockpi4.img.gz`.
Otherwise, you get duplicate uuids and volume group names.

## Login

You can login with user _root_ and password _changeme_ using the serial console
or, when it works, using hdmi and an usb keyboard. root login via network
won't work.

## Configure MAC address

Please configure a unique mac address using the command

`fw_setenv ethaddr x2:xx:xx:xx:xx:xx`

Replace _x_ with any hexadecimal digit.

## Filesystem size

The created filesystems are probably too small. However, the can be easily
expanded. To e.g. add 128MiB to the /var filesystem, use the following
commands:

```bash
lvresize -L +128M /dev/vgsystem/lvvar
resize2fs /dev/vgsystem/lvvar
```

That's all.

## Device tree overlays

To activate a device tree overlay, put it to the /boot filesystem and add
statements like the following to /boot/boot.cmd:

```
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} ${prefix}/sample-overlay.dtbo
fdt apply ${ramdisk_addr_r}
```
Add these statements after the `fdt resize` command.
After any change of /boot/boot.cmd, invoke _/usr/local/sbin/create-boot-scr.sh_
to recreate /boot/boot.scr.

## Network configuration

Network configuration is done using systemd. See contents of directory
_/etc/systemd/network_ and _man systemd.network_. WLAN credentials must be
configured using _/etc/wpa_supplicant/wpa_supplicant-wlan0.conf_.
