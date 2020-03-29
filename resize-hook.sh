#!/bin/sh
PREREQ="lvm2"
prereqs()
{
	echo "$PREREQ"
}

case $1 in
prereqs)
	prereqs
	exit 0
	;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /usr/local/sbin/resize_gpt_disk /sbin
copy_exec /sbin/parted /sbin
copy_exec /sbin/tune2fs /sbin
copy_exec /usr/bin/sed /usr/bin
copy_exec /usr/bin/yes /usr/bin
copy_exec /usr/bin/awk /usr/bin
ln -sf lvm ${DESTDIR}/sbin/pvs
ln -sf lvm ${DESTDIR}/sbin/pvresize
ln -sf lvm ${DESTDIR}/sbin/pvchange
