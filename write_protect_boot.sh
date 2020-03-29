#!/bin/bash
#
# Power on write protection for boot blocks
#

# Get device name
bootpart=$(grep '/boot ' /proc/mounts | cut -d\  -f 1)
if [ "${bootpart:0:11}" != "/dev/mmcblk" ]; then
	echo "Boot partition unknown or not an mmc"
	exit 0
fi
device="${bootpart:0:-2}"

# Get block size and write protect group size
wpgs=$(/usr/bin/mmc writeprotect user get ${device}|awk -F: '/Write Protect Group size/ {print $2}')
write_protect_group_size_blocks=$(cut -d/ -f1 <<< "${wpgs}" | tr -d ' ')
write_protect_group_size_bytes=$(cut -d/ -f2 <<< "${wpgs}" | tr -d ' ')

# Calculate block size
write_protect_block_size=$((write_protect_group_size_bytes / write_protect_group_size_blocks))

# Get beginning of boot partition
start_block=$(cat /sys/class/block/${bootpart##*/}/start)

# Get block size
block_size=$(blockdev --getss ${device})

# Start iof boot partition in bytes
start_byte=$((start_block * block_size))

# Number of blocks to protect
protect_blocks=$((start_byte / write_protect_block_size))

# Round down to protect group size
protect_blocks=$((protect_blocks / write_protect_group_size_blocks))
protect_blocks=$((protect_blocks * write_protect_group_size_blocks))

# Do write protect
echo "Write protecting ${protect_blocks} on device ${device}"
/usr/bin/mmc writeprotect user set pwron 0 ${protect_blocks} ${device}
