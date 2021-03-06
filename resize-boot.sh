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
. /scripts/local

eval $(/sbin/pvs --noheadings -o pv_name --nameprefixes --select vg_name=vgsystem)
retry=8
while [ -z "${LVM2_PV_NAME}" -a ${retry} -gt 0 ]; do
	sleep 1
	retry=$((retry - 1))
	eval $(/sbin/pvs --noheadings -o pv_name --nameprefixes --select vg_name=vgsystem)
done

if [ -z "${LVM2_PV_NAME}" ]; then
	log_failure_msg "Cannot find pv of vgsystem"
else
	if [ $(echo "${LVM2_PV_NAME}" | awk '{ print substr($0, 0, 8) }') = "/dev/sd" ]; then
		mmcdev=$(echo "${LVM2_PV_NAME}" | awk '{ print substr($0, 0, 9) }')
		partno="${LVM2_PV_NAME#${mmcdev}}"
	elif [ $(echo "${LVM2_PV_NAME}" | awk '{ print substr($0, 0, 12) }') = "/dev/mmcblk" ]; then
		mmcdev="${LVM2_PV_NAME%p*}"
		partno="${LVM2_PV_NAME#${mmcdev}p}"
	fi
	if [ ! -b "${mmcdev}" ]; then
		log_failure_msg "Cannot access block device with vgsystem."
	else
		log_begin_msg "Resizing vgsystem"
		/sbin/resize_gpt_disk "${mmcdev}" > /dev/null 2>&1
		/sbin/parted -s "${mmcdev}" "resizepart ${partno} -65s" > /dev/null 2>&1
		/sbin/pvresize ${LVM2_PV_NAME}
		/sbin/pvchange -u ${LVM2_PV_NAME}
		/sbin/vgchange -u vgsystem
		/sbin/vgchange -ay vgsystem
		log_success_msg "Resized vgsystem"
		log_begin_msg "Generating new UUID for file systems"
		/usr/bin/yes | /sbin/tune2fs -U random /dev/mapper/vgsystem-lvroot
		/usr/bin/yes | /sbin/tune2fs -U random /dev/mapper/vgsystem-lvvar
		/usr/bin/yes | /sbin/tune2fs -U random /dev/mapper/vgsystem-lvhome
		log_success_msg "New UUIDs generated"
	fi
fi
