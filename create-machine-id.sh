#!/bin/sh
PREREQ=""
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

. /scripts/functions

if [ ! -e "${rootmnt}/etc/machine-id" ]; then
	log_begin_msg "Creating new machine id."
	LD_LIBRARY_PATH=${rootmnt}/lib:${rootmnt}/lib/aarch64-linux-gnu:${rootmnt}/lib/systemd:${rootmnt}/usr/lib/aarch64-linux-gnu ${rootmnt}/bin/systemd-machine-id-setup --root ${rootmnt}
	log_success_msg "New machine id created."
	log_begin_msg "Changeing UUID of boot filesystem."
	while read MNT_FSNAME MNT_DIR MNT_REST; do
		if [ "${MNT_DIR}" = "/boot" ]; then
			break
		fi
	done < "${rootmnt}/etc/fstab"
	if [ "${MNT_DIR}" = "/boot" ]; then
		uuid="${MNT_FSNAME#*=}"
		bootdev=$(blkid --uuid ${uuid})
		/usr/bin/yes | /sbin/tune2fs -f -U random "${bootdev}"
		new_uuid=$(blkid -o value -s UUID ${bootdev})
		/usr/bin/sed -i -e "s/${uuid}/${new_uuid}/g" "${rootmnt}/etc/fstab"
		log_success_msg "Changed UUID of /boot"
	else
		log_failure_msg "Cannot find /boot filesystem"
	fi
fi
