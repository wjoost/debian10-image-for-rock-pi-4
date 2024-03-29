ATF_VERSION=v2.5
UBOOT_VERSION=v2021.07
CROSS_COMPILE=aarch64-linux-gnu-
M0_CROSS_COMPILE=arm-none-eabi-
KERNEL_MAJOR=5.10
KERNEL_MINOR=54
PARALLEL=5
MIRROR="http://mirror.wtnet.de/debian/"
#MIRROR="http://debian.mirror.iphh.net/debian/"
VGNAME?=vgsysrckpi64
BRCMFIRMWAREURL="https://github.com/radxa/apt/raw/gh-pages/stretch/pool/main/b/broadcom-wifibt-firmware/broadcom-wifibt-firmware_0.5_all.deb"

all: rockpi4.img.gz
atf-source-$(ATF_VERSION):
	git clone -b $(ATF_VERSION) --depth=1 https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git atf-source-$(ATF_VERSION)
	sed -i -E -e 's/(^#define RK3399_BAUDRATE)(.)*$$/#define RK3399_BAUDRATE			1500000/' atf-source-$(ATF_VERSION)/plat/rockchip/rk3399/rk3399_def.h
	set -e && for p in atf-$(ATF_VERSION)-patches/*.patch; do echo $${p}; patch -d atf-source-$(ATF_VERSION) -p1 -i ../$${p}; done

bl31-$(ATF_VERSION).elf: atf-source-$(ATF_VERSION)
	make -C atf-source-$(ATF_VERSION) realclean
	make -C atf-source-$(ATF_VERSION) CROSS_COMPILE=$(CROSS_COMPILE) M0_CROSS_COMPILE=$(M0_CROSS_COMPILE) DEBUG=0 PLAT=rk3399 bl31
	cp atf-source-$(ATF_VERSION)/build/rk3399/release/bl31/bl31.elf bl31-$(ATF_VERSION).elf || cp atf-source/build/rk3399/debug/bl31/bl31.elf bl31-$(ATF_VERSION).elf

u-boot-source-$(UBOOT_VERSION): u-boot-extra-config
	rm -rf u-boot-source-$(UBOOT_VERSION)
	git clone -b $(UBOOT_VERSION) --depth=1 https://gitlab.denx.de/u-boot/u-boot.git/ u-boot-source-$(UBOOT_VERSION)
	sed -i -e '/i2s1/,+5d' u-boot-source-$(UBOOT_VERSION)/arch/arm/dts/rk3399-rock-pi-4.dtsi
	set -e && for p in u-boot-$(UBOOT_VERSION)-patches/*.patch; do echo $${p}; patch -d u-boot-source-$(UBOOT_VERSION) -p1 -i ../$${p}; done
	set -e && cut -d= -f1 u-boot-extra-config | while read option; do sed -i -e "/^$${option}=/ d" u-boot-source-$(UBOOT_VERSION)/configs/rock-pi-4-rk3399_defconfig; done
	cat u-boot-extra-config >> u-boot-source-$(UBOOT_VERSION)/configs/rock-pi-4-rk3399_defconfig

u-boot.itb: u-boot-source-$(UBOOT_VERSION) bl31-$(ATF_VERSION).elf
	make -C u-boot-source-$(UBOOT_VERSION) distclean
	make -C u-boot-source-$(UBOOT_VERSION) CROSS_COMPILE=$(CROSS_COMPILE) BL31=$(CURDIR)/bl31-$(ATF_VERSION).elf rock-pi-4-rk3399_defconfig
	make -C u-boot-source-$(UBOOT_VERSION) CROSS_COMPILE=$(CROSS_COMPILE) BL31=$(CURDIR)/bl31-$(ATF_VERSION).elf
	cp u-boot-source-$(UBOOT_VERSION)/env/common.o u-boot-source-$(UBOOT_VERSION)/env_common.o
	$(CROSS_COMPILE)objcopy -O binary -j ".rodata.default_environment" u-boot-source-$(UBOOT_VERSION)/env_common.o
	tr '\0' '\n' < u-boot-source-$(UBOOT_VERSION)/env_common.o | sort -u > u-boot-default-env.txt
	rm u-boot-source-$(UBOOT_VERSION)/env_common.o
	cp u-boot-source-$(UBOOT_VERSION)/idbloader.img u-boot-source-$(UBOOT_VERSION)/u-boot.itb u-boot-source-$(UBOOT_VERSION)/tools/mkenvimage u-boot-source-$(UBOOT_VERSION)/tools/mkimage .

linux-$(KERNEL_MAJOR).tar.xz:
	wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$(KERNEL_MAJOR).tar.xz

linux-patch-$(KERNEL_MAJOR).$(KERNEL_MINOR).xz:
	wget -O linux-patch-$(KERNEL_MAJOR).$(KERNEL_MINOR).xz https://cdn.kernel.org/pub/linux/kernel/v5.x/patch-$(KERNEL_MAJOR).$(KERNEL_MINOR).xz

linux-$(KERNEL_MAJOR).$(KERNEL_MINOR): linux-$(KERNEL_MAJOR).tar.xz linux-patch-$(KERNEL_MAJOR).$(KERNEL_MINOR).xz
	mkdir linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	tar -C linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) --strip-components=1 --no-same-owner --no-same-permissions -x -J -f linux-$(KERNEL_MAJOR).tar.xz
	xz -cd linux-patch-$(KERNEL_MAJOR).$(KERNEL_MINOR).xz | patch -d linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) -p1
	set -e && for p in linux-patches-$(KERNEL_MAJOR)/*.patch; do echo $${p}; patch -d linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) -p1 -i ../$${p}; done
	find linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) -name '*.orig' -delete
	make -C linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) mrproper

Image-$(KERNEL_MAJOR).$(KERNEL_MINOR): linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) linux-config-$(KERNEL_MAJOR)
	cp linux-config-$(KERNEL_MAJOR) linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)/.config
	rm -rf linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	mkdir linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	make -C linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- oldconfig
	make -C linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) -j${PARALLEL} ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DTC_FLAGS=-@ Image dtbs modules
	make -C linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=$(CURDIR)/linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR) modules_install
	tar -C linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR)/lib/modules -c -z --exclude=$(KERNEL_MAJOR).$(KERNEL_MINOR)/source --exclude=$(KERNEL_MAJOR).$(KERNEL_MINOR)/build -f linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR).tar.gz $(KERNEL_MAJOR).$(KERNEL_MINOR)
	rm -rf linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	cp linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)/System.map System.map-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	cp linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)/.config config-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	cp linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)/arch/arm64/boot/dts/rockchip/rk3399-rock-pi-4a.dtb dtb-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	cp linux-$(KERNEL_MAJOR).$(KERNEL_MINOR)/arch/arm64/boot/Image Image-$(KERNEL_MAJOR).$(KERNEL_MINOR)

resize_gpt_disk: resize_gpt_disk.c
	gcc -Wall -O2 -pedantic -s -o resize_gpt_disk resize_gpt_disk.c

resize_gpt_disk.aarch64: resize_gpt_disk.c
	$(CROSS_COMPILE)gcc -Wall -O2 -pedantic -s -o resize_gpt_disk.aarch64 resize_gpt_disk.c

brcm_patchram_plus: brcm_patchram_plus.c
	$(CROSS_COMPILE)gcc -Wall -O2 -pedantic -s -o brcm_patchram_plus brcm_patchram_plus.c

broadcom-firmware:
	rm -rf broadcom-firmware broadcom-firmware-tmp
	test -e broadcom-wifibt-firmware.deb || curl -L -o broadcom-wifibt-firmware.deb "$(BRCMFIRMWAREURL)"
	mkdir broadcom-firmware-tmp
	cd broadcom-firmware-tmp && ar x ../broadcom-wifibt-firmware.deb data.tar.xz && tar -x -J --no-same-owner --no-same-permissions -f data.tar.xz && rm data.tar.xz && cd .. && mv broadcom-firmware-tmp broadcom-firmware

si2168-firmware:
	rm -rf si2168-firmware-tmp
	mkdir si2168-firmware-tmp
	curl -L -o si2168-firmware-tmp/dvb-demod-si2168-02.fw  'https://github.com/OpenELEC/dvb-firmware/raw/master/firmware/dvb-demod-si2168-02.fw'
	curl -L -o si2168-firmware-tmp/dvb-demod-si2168-a20-01.fw 'https://github.com/OpenELEC/dvb-firmware/raw/master/firmware/dvb-demod-si2168-a20-01.fw'
	curl -L -o si2168-firmware-tmp/dvb-demod-si2168-b40-01.fw 'https://github.com/OpenELEC/dvb-firmware/raw/master/firmware/dvb-demod-si2168-b40-01.fw'
	mv si2168-firmware-tmp si2168-firmware

debian-rootfs: configure-debian.sh resize_gpt_disk.aarch64 brcm_patchram_plus broadcom-firmware si2168-firmware
	sudo rm -rf debian-rootfs
	sudo mkdir -m 0755 debian-rootfs debian-rootfs/lib debian-rootfs/lib/firmware debian-rootfs/lib/firmware/brcm debian-rootfs/etc debian-rootfs/etc/udev debian-rootfs/etc/udev/rules.d
	DEBIAN_FRONTEND=noninteractive sudo --preserve-env=DEBIAN_FRONTEND qemu-debootstrap --arch=arm64 --keyring /usr/share/keyrings/debian-archive-keyring.gpg --variant=minbase --exclude=debfoster,exim4-base,exim4-config,exim4-daemon-light --components main,non-free --include=openssh-server,u-boot-tools,parted,kpartx,initramfs-tools,mmc-utils,cron,curl,nscd,ssh,usbutils,vlan,wget,xz-utils,bzip2,systemd,init,init-system-helpers,iputils-ping,ca-certificates,dc,file,htop,less,openssl,vim-tiny,man-db,locales,keyboard-configuration,fake-hwclock,kbd,lvm2,make,bison,flex,libssl-dev,bc,pkg-config,patch,apt-transport-https,dbus,netbase,rfkill,dialog,apt-utils,ethtool,tcpdump,lsb-base,lsb-release,gcc,libncurses-dev,strace,pciutils,screen,lvm2,bluetooth,wpasupplicant,wireless-tools,crda,wireless-regdb,mtd-utils buster debian-rootfs ${mirror}
	sudo cp configure-debian.sh debian-rootfs/
	sudo cp resize_gpt_disk.aarch64 debian-rootfs/usr/local/sbin/resize_gpt_disk
	sudo cp brcm_patchram_plus write_protect_boot.sh debian-rootfs/usr/local/sbin
	sudo cp write_protect_boot.service debian-rootfs/etc/systemd/system/
	sudo chmod 0744 debian-rootfs/configure-debian.sh debian-rootfs/usr/local/sbin/resize_gpt_disk debian-rootfs/usr/local/sbin/write_protect_boot.sh
	sudo chmod 0755 debian-rootfs/usr/local/sbin/brcm_patchram_plus
	sudo chroot debian-rootfs /configure-debian.sh
	sudo rm debian-rootfs/configure-debian.sh
	sudo cp broadcom-firmware/system/etc/firmware/BCM4345C5.hcd debian-rootfs/lib/firmware/brcm/
	sudo cp broadcom-firmware/system/etc/firmware/fw_bcm43456c5_ag.bin debian-rootfs/lib/firmware/brcm/brcmfmac43456-sdio.bin
	sudo cp broadcom-firmware/system/etc/firmware/nvram_ap6256.txt debian-rootfs/lib/firmware/brcm/brcmfmac43456-sdio.radxa,rockpi4.txt
	sudo cp si2168-firmware/dvb-demod-si2168-02.fw si2168-firmware/dvb-demod-si2168-a20-01.fw si2168-firmware/dvb-demod-si2168-b40-01.fw debian-rootfs/lib/firmware/
	sudo chmod 0644 debian-rootfs/lib/firmware/brcm/* debian-rootfs/lib/firmware/*.fw

rockpi4.img.gz: debian-rootfs resize_gpt_disk Image-$(KERNEL_MAJOR).$(KERNEL_MINOR) u-boot.itb partitions.txt
	/sbin/losetup -l|awk '/rockpi4.img/ { print $$1 }' | while read lodevice; do sudo /sbin/kpartx -d $${lodevice}; sudo /sbin/losetup -d $${lodevice}; done
	rm -f rockpi4.img rockpi4.img.gz
	sudo rm -rf debian-rootfs/lib/modules
	sudo mkdir -m 0755 debian-rootfs/lib/modules
	sudo tar -C debian-rootfs/lib/modules --no-same-owner -x -f linux-modules-$(KERNEL_MAJOR).$(KERNEL_MINOR).tar.gz
	sudo chown -R 0:0 debian-rootfs/lib/modules/$(KERNEL_MAJOR).$(KERNEL_MINOR)
	fallocate -l 1073741824 rockpi4.img
	/sbin/sfdisk --no-reread --no-tell-kernel rockpi4.img < partitions.txt
	./resize_gpt_disk rockpi4.img
	sed -e '/^partitions/ d' -e '/^boot_targets/ d' u-boot-default-env.txt > u-boot-env.txt
	echo "partitions=uuid_disk=\$${uuid_gpt_disk};name=loader1,start=32K,size=3552K,uuid=\$${uuid_gpt_loader1};name=ubootenv,start=4064K,size=32K,uuid=\$${uuid_gpt_ubootenv};name=loader2,start=8MB,size=4MB,uuid=\$${uuid_gpt_loader2};name=boot,start=12M,size=128M,bootable,uuid=\$${uuid_gpt_boot};name=lvm,start=140M,size=-,uuid=\$${uuid_gpt_lvm};" >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/^label-id:/ { print "uuid_gpt_disk=" $$2 }' >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/"loader1"/ { print "uuid_gpt_loader1=" substr($$8,6,36) }' >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/"ubootenv"/ { print "uuid_gpt_ubootenv=" substr($$8,6,36) }' >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/"loader2"/ { print "uuid_gpt_loader2=" substr($$8,6,36) }' >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/"boot"/ { print "uuid_gpt_boot=" substr($$8,6,36) }' >> u-boot-env.txt
	/sbin/sfdisk -d rockpi4.img|awk '/"lvm"/ { print "uuid_gpt_lvm=" substr($$8,6,36) }' >> u-boot-env.txt
	echo "boot_targets=usb0 mmc1 mmc0" >> u-boot-env.txt
	rm -f u-boot-env.bin
	sort -u < u-boot-env.txt | ./mkenvimage -s 32768 -o u-boot-env.bin
	dd if=idbloader.img of=rockpi4.img obs=512 seek=64 conv=notrunc,sparse
	dd if=u-boot-env.bin of=rockpi4.img obs=512 seek=8128 conv=notrunc,sparse
	dd if=u-boot.itb of=rockpi4.img obs=512 seek=16384 conv=notrunc,sparse
	$(eval rootid := $(shell uuid -v 1 -F STR))
	$(eval bootid := $(shell uuid -v 1 -F STR))
	$(eval varid := $(shell uuid -v 1 -F STR))
	$(eval homeid := $(shell uuid -v 1 -F STR))
	sudo bash -c "echo '/dev/$(VGNAME)/lvroot                      /               ext4     noatime                          1 1' > debian-rootfs/etc/fstab"
	sudo bash -c "echo 'UUID=$(bootid) /boot           ext2     noatime                          1 2' >> debian-rootfs/etc/fstab"
	sudo bash -c "echo '/dev/$(VGNAME)/lvvar                       /var            ext4     noatime                          1 3' >> debian-rootfs/etc/fstab"
	sudo bash -c "echo '/dev/$(VGNAME)/lvhome                      /home           ext4     noatime                          1 4' >> debian-rootfs/etc/fstab"
	sudo bash -c "echo 'tmpfs                                     /tmp            tmpfs    size=256M,mode=1777,nodev,nosuid 0 0' >> debian-rootfs/etc/fstab"
	sudo bash -c "echo '/tmp                                      /var/tmp        none     bind                             0 0' >> debian-rootfs/etc/fstab"
	sudo chmod 0644 debian-rootfs/etc/fstab
	sudo bash -c "echo ROOT=/dev/$(VGNAME)/lvroot > debian-rootfs/etc/initramfs-tools/conf.d/root"
	sudo bash -c 'echo readonly=n > debian-rootfs/etc/initramfs-tools/conf.d/readwrite'
	sudo cp resize-hook.sh debian-rootfs/etc/initramfs-tools/hooks/
	sudo cp resize-boot.sh debian-rootfs/etc/initramfs-tools/scripts/local-premount/
	sudo sed -i -e 's/vgsystem/$(VGNAME)/g' debian-rootfs/etc/initramfs-tools/scripts/local-premount/resize-boot.sh
	sudo cp create-machine-id.sh debian-rootfs/etc/initramfs-tools/scripts/init-bottom/
	test -e debian-rootfs/usr/bin/qemu-aarch64-static || sudo cp -p /usr/bin/qemu-aarch64-static debian-rootfs/usr/bin/
	sudo chroot debian-rootfs /usr/sbin/mkinitramfs -r UUID=$(rootid) -o /boot/initrd.img-$(KERNEL_MAJOR).$(KERNEL_MINOR) $(KERNEL_MAJOR).$(KERNEL_MINOR)
	sudo rm -rf debian-bootfs
	mkdir -m 0755 debian-bootfs
	sudo mv debian-rootfs/boot/* debian-bootfs
	sudo ln -sf uInitrd-$(KERNEL_MAJOR).$(KERNEL_MINOR) debian-bootfs/uInitrd
	sudo rm -f debian-rootfs/etc/initramfs-tools/conf.d/readwrite debian-rootfs/etc/initramfs-tools/hooks/resize-hook.sh debian-rootfs/etc/initramfs-tools/scripts/local-premount/resize-boot.sh debian-rootfs//etc/initramfs-tools/scripts/init-bottom/create-machine-id.sh
	sudo bash -c "echo '# Linux cmdline' > debian-bootfs/boot.cmd"
	sudo bash -c "echo 'setenv bootargs \"console=ttyS2,1500000n81\"' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Load FTD' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'load \$${devtype} \$${devnum}:\$${distro_bootpart} \$${fdt_addr_r} \$${prefix}dtb' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Prepare modification of device tree' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'fdt addr \$${fdt_addr_r}' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'fdt resize 4096' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Enable SPI1' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '#fdt set /spi@ff1d0000 status okay' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Enable SPI flash' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '#fdt set /spi@ff1d0000/spi-flash@0 status okay' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Enable bluetooth' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '#fdt set /serial@ff180000 status ok' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Enable wlan' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '#fdt set /mmc@fe310000 status ok' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Disable SD card reader' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '#fdt set /mmc@fe320000 status disabled' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Load initrd' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'load \$${devtype} \$${devnum}:\$${distro_bootpart} \$${ramdisk_addr_r} \$${prefix}uInitrd' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Load kernel' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'load \$${devtype} \$${devnum}:\$${distro_bootpart} \$${kernel_addr_r} \$${prefix}Image' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo '# Start kernel' >> debian-bootfs/boot.cmd"
	sudo bash -c "echo 'booti \$${kernel_addr_r} \$${ramdisk_addr_r} \$${fdt_addr_r}' >> debian-bootfs/boot.cmd"
	sudo ./mkimage -C none -A arm64 -T script  -d debian-bootfs/boot.cmd debian-bootfs/boot.scr
	sudo ./mkimage -C none -A arm64 -T ramdisk -d debian-bootfs/initrd.img-$(KERNEL_MAJOR).$(KERNEL_MINOR) debian-bootfs/uInitrd-$(KERNEL_MAJOR).$(KERNEL_MINOR)
	sudo cp Image-$(KERNEL_MAJOR).$(KERNEL_MINOR) System.map-$(KERNEL_MAJOR).$(KERNEL_MINOR) config-$(KERNEL_MAJOR).$(KERNEL_MINOR) dtb-$(KERNEL_MAJOR).$(KERNEL_MINOR) debian-bootfs/
	sudo ln -sf Image-$(KERNEL_MAJOR).$(KERNEL_MINOR) debian-bootfs/Image
	sudo ln -sf dtb-$(KERNEL_MAJOR).$(KERNEL_MINOR) debian-bootfs/dtb
	rm -f boot.ext2 root.ext4
	sudo /sbin/losetup -f rockpi4.img
	set -e; \
      	lodevice=$$(/sbin/losetup -l|awk '/rockpi4.img/ { print substr($$1,6) }'); \
	sudo /sbin/kpartx -s -a /dev/$${lodevice}; \
	sudo pvcreate /dev/mapper/$${lodevice}p5; \
	sudo vgcreate -s 64M $(VGNAME) /dev/mapper/$${lodevice}p5; \
	sudo mkfs.ext2 -U $(bootid) -L /boot -b 4096 -e remount-ro -I 256 -N 1024 -O ^resize_inode -M /boot -d debian-bootfs /dev/mapper/$${lodevice}p4; \
	sudo /sbin/tune2fs -c 4 -i 0 /dev/mapper/$${lodevice}p4
	sudo rm -rf debian-bootfs
	sudo lvcreate -n lvroot -L 512M $(VGNAME)
	sudo lvcreate -n lvhome -L 64M $(VGNAME)
	sudo lvcreate -n lvvar  -L 256M $(VGNAME)
	sudo mkfs.ext4 -U $(varid) -L /var -b 4096 -e remount-ro -E lazy_itable_init=0 -I 256 -i 16384 -O ^has_journal -M /var -d debian-rootfs/var /dev/mapper/$(VGNAME)-lvvar
	sudo /sbin/tune2fs -c 4 -i 0 /dev/mapper/$(VGNAME)-lvvar
	sudo mkfs.ext4 -U $(homeid) -L /home -b 4096 -e remount-ro -E lazy_itable_init=0 -I 256 -i 16384 -O ^has_journal -M /home -d debian-rootfs/home /dev/mapper/$(VGNAME)-lvhome
	sudo /sbin/tune2fs -c 4 -i 0 /dev/mapper/$(VGNAME)-lvhome
	sudo rm -rf debian-onlyroot
	mkdir debian-onlyroot
	sudo tar -C debian-rootfs -c -f - -S --exclude ./tmp --exclude ./var --exclude ./home --exclude ./boot .| sudo tar -C debian-onlyroot -x -f - -S
	sudo mkdir -m0 debian-onlyroot/boot debian-onlyroot/tmp debian-onlyroot/home debian-onlyroot/var
	sudo bash -c "date -u '+%Y-%m-%d %H:%M:%S' > debian-onlyroot/etc/fake-hwclock.data"
	sudo mkfs.ext4 -U $(rootid) -L / -b 4096 -e remount-ro -E lazy_itable_init=0 -I 256 -i 16384 -O ^has_journal -M / -d debian-onlyroot /dev/mapper/$(VGNAME)-lvroot
	sudo /sbin/tune2fs -c 4 -i 0 /dev/mapper/$(VGNAME)-lvroot
	sudo rm -rf debian-onlyroot
	sudo /sbin/vgchange -an $(VGNAME)
	set -e; lodevice=$$(/sbin/losetup -l|awk '/rockpi4.img/ { print substr($$1,6) }'); sudo /sbin/kpartx -d /dev/$${lodevice}; sudo /sbin/losetup -d /dev/$${lodevice}
	gzip -9 rockpi4.img

kernelclean:
	rm -rf linux-$(KERNEL_MAJOR).$(KERNEL_MINOR) Image-$(KERNEL_MAJOR).$(KERNEL_MINOR) System.map-$(KERNEL_MAJOR).$(KERNEL_MINOR) config-$(KERNEL_MAJOR).$(KERNEL_MINOR) dtb-$(KERNEL_MAJOR).$(KERNEL_MINOR) Image-$(KERNEL_MAJOR).$(KERNEL_MINOR) linux-modules*.gz

clean: kernelclean
	rm -rf bl31-$(ATF_VERSION).elf atf-source-$(ATF_VERSION)/build u-boot-default-env.txt idbloader.img u-boot.itb resize_gpt_disk resize_gpt_disk.aarch64 rockpi4.img.gz rockpi4.img u-boot-env.txt mkenvimage mkimage u-boot-env.bin root.ext4 boot.ext2 linux-modules*.gz broadcom-firmware brcm_patchram_plus
	sudo rm -rf debian-bootfs debian-rootfs
	test -d u-boot-source-$(UBOOT_VERSION) && make -C u-boot-source-$(UBOOT_VERSION) distclean || true

distclean: clean
	rm -rf atf-source-$(ATF_VERSION) u-boot-source-$(UBOOT_VERSION) linux-*.xz broadcom-wifibt-firmware_0.5_all.deb si2168-firmware

.PHONY: clean distclean kernelclean
