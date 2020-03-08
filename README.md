# Debian 10 image for Raxda ROCK Pi 4

This repo contains a Makefile which will create a debian 10 image for
Raxda ROCK Pi 4 boards.

## State

Not finished yet. Known issues:

* USB OTG port does not work in bootloader
* HDMI out unreliable
* Slow boot from eMMC. Might be caused by bad eMMC module, maybe patch 0002-emmc-no-modeswitch.patch can be removed
* No USB keyboard in bootloader

Not implemented:

* Bluetooth (I have an A-board)
* WLAN
* SATA

Not checked:

* Audio
* GPIO / SPI / I2C
* PCIe seems to work

## Build

You need a debian 10 build machine with root rights.

* Configure a normal user
* Allow this user using sudo without password
* Install native and cross compiler
* Install make
* Start make

The resulting image rockpi4.img.gz can be flashed to an emmc module or a sd
card. However, the bootloader wants to load its environment from emmc.
