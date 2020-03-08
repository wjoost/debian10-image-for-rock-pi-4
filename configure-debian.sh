#!/bin/bash
mirror="http://mirror.wtnet.de/debian/"
#mirror="http://debian.mirror.iphh.net/debian/"
set -e
set -x

# Clean up language environment variables
env | egrep '^LC_|^LANG' | cut -d '=' -f1 > variables.$$
while read v; do
	unset ${v}
done < variables.$$
export LC_ALL=C
rm variables.$$

# No interactive configuration
export DEBIAN_FRONTEND=noninteractive

# Configure package sources
cat > /etc/apt/sources.list << EOF
deb ${mirror} buster main non-free
deb-src ${mirror} buster main non-free

deb http://ftp.de.debian.org/debian-security/ buster/updates main non-free
deb-src http://ftp.de.debian.org/debian-security/ buster/updates main non-free

deb ${mirror} buster-updates main non-free
deb-src ${mirror} buster-updates main non-free
EOF
chmod 0644 /etc/apt/sources.list

# Update
/usr/bin/apt-get -y update
/usr/bin/apt-get -y dist-upgrade
/usr/bin/apt-get -y update
/usr/bin/apt-get -y autoremove
/usr/bin/apt-get -y clean
find /var/lib/apt/lists -name 'mirror.wtnet.de**' -delete
find /var/lib/apt/lists -name 'artfiles.org**' -delete
find /var/lib/apt/lists -name 'deb.debian.org*' -delete

# Set root password
/usr/sbin/chpasswd <<< "root:changeme"

# Configure u-boot tools
cat > /etc/fw_env.config << EOF
/dev/mmcblk1	0x3F8000	0x8000
EOF
chmod 0644 /etc/fw_env.config

# Put settings in debian db
/usr/bin/debconf-set-selections << EOF
tzdata		tzdata/Areas				select		Europe
tzdata		tzdata/Zones/Europe			select		Berlin
locales		locales/default_environment_locale	select		C.UTF-8
locales		locales/locales_to_be_generated		multiselect	de_DE ISO-8859-1, de_DE.UTF-8 UTF-8, en_US ISO-8859-1, en_US.UTF-8 UTF-8
EOF

# Set hostname
echo 'rockpi4' > /etc/hostname

# Timezone
echo 'Europe/Berlin' > /etc/timezone
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# Locales
sed -i             -e '/^# de_DE ISO-8859-1/ c\
de_DE ISO-8859-1'  -e '/^# de_DE.UTF-8 UTF-8/ c\
de_DE.UTF-8 UTF-8' -e '/^# en_US ISO-8859-1/ c\
en_US ISO-8859-1'  -e '/^# en_US.UTF-8 UTF-8/ c\
en_US.UTF-8 UTF-8' /etc/locale.gen
/usr/sbin/update-locale LANG=C.UTF-8

# Keyboard layout
sed -i            -e '/XKBMODEL/ c\
XKBMODEL="pc105"' -e '/XKBLAYOUT/ c\
XKBLAYOUT="de"' /etc/default/keyboard

# Enhance WLAN stability
echo 'options r8188eu rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=1' > /etc/modprobe.d/8188eu.conf
chmod 0644 /etc/modprobe.d/8188eu.conf

# No persistent nscd cache
sed -i -E -e 's/(^\s*persistent\s*\w*\s*)(yes$)/\1no/g' /etc/nscd.conf

# No syslog installed
sed -i -e '/ForwardToSyslog/ c\
ForwardToSyslog=no' /etc/systemd/journald.conf

# fstrim
cat > /etc/systemd/system/fstrim.service << EOF
[Unit]
Description=Trim filesystems

[Service]
Type=oneshot
ExecStart=/sbin/fstrim -a
IOSchedulingClass=idle
EOF

cat > /etc/systemd/system/fstrim.timer << EOF
[Unit]
Description=Weekly trimming of all filesystems

[Timer]
OnBootSec=15min
OnUnitActiveSec=1w

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/fstrim.service /etc/systemd/system/fstrim.timer
/bin/systemctl enable fstrim.timer

# No daily regeneration of man-db
mv /etc/cron.daily/man-db /etc/cron.monthly
touch /etc/cron.daily/man-db

# Timeserver
sed -i -e '/^#FallbackNTP=/ c\
FallbackNTP=0.de.pool.ntp.org 1.de.pool.ntp.org 2.de.pool.ntp.org 3.de.pool.ntp.org
' /etc/systemd/timesyncd.conf

# Serial terminals root can login
sed -i -E -e 's/^[^#]/#\0/g' -e 's/^#console/console/g' -e 's/^#ttyS2/ttyS2/g' -e 's/(^#)(tty[[:digit:]])/\2/g' /etc/securetty

# Fixed BPS on ttyS2
sed -e "/^ExecStart/ c\
ExecStart=-/sbin/agetty -o '-p -- \\\\\\\\u' 1500000 %I \$TERM" /lib/systemd/system/serial-getty@.service >  /etc/systemd/system/serial-getty@ttyS2.service
chmod 0644 /etc/systemd/system/serial-getty@ttyS2.service

# Disable ctrl-alt-delete
ln -sf /dev/null /etc/systemd/system/ctrl-alt-del.target

# Configure kernel settings
sed -i -e 's/^#kernel\.printk/kernel.printk/g' -e 's/^#net\.ipv4\.conf\.default\.rp_filter/net.ipv4.conf.default.rp_filter/g' -e 's/^#net\.ipv4\.conf\.all\.rp_filter/net.ipv4.conf.all.rp_filter/g' -e 's/^#net\.ipv4\.tcp_syncookies/net.ipv4.tcp_syncookies/g' -e 's/^#net\.ipv4\.conf\.all\.accept_redirects/net.ipv4.conf.all.accept_redirects/g' -e 's/^#net\.ipv6\.conf\.all\.accept_redirects/net.ipv6.conf.all.accept_redirects/g' -e 's/^#net\.ipv4\.conf\.all\.send_redirects/net.ipv4.conf.all.send_redirects/g' -e 's/^#net\.ipv4\.conf\.all\.accept_source_route/net.ipv4.conf.all.accept_source_route/g' -e 's/^#net\.ipv6\.conf\.all\.accept_source_route/net.ipv6.conf.all.accept_source_route/g' -e 's/^#kernel\.sysrq=438/kernel.sysrq = 0/g' /etc/sysctl.conf
cat >> /etc/sysctl.conf << EOF

###################################################################
# Additional network security
#
# Reply to received ARP requests only if the target IP address to be
# resolved is a local address configured on the incoming interface
# (no cross-interface resolution)
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1


###################################################################
#
# Protect symlinks
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

# Configure SSH
sed -i -e '/^#UseDNS/ c\
UseDNS no
'      -e '/^#PermitRootLogin/ c\
PermitRootLogin without-password
'      -e '/^#AllowAgentForwarding/ c\
AllowAgentForwarding no
'      -e '/^#MaxAuthTries/ c\
MaxAuthTries 4
'      -e '/^# Ciphers/ a\
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256\
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr\
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
'      -e '/^#ClientAliveInterval/ c\
ClientAliveInterval 120
' /etc/ssh/sshd_config

sed -i -e '/ man page.$/ a\
\
# Some security settings\
HashKnownHosts yes\
Protocol 2\
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256\
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr\
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com\
' /etc/ssh/ssh_config

# Secure nscd
mkdir -m 0755 /etc/systemd/system/nscd.service.d
cat > /etc/systemd/system/nscd.service.d/90-security.conf << EOF
[Service]
CapabilityBoundingSet=CAP_SETGID CAP_SETUID CAP_AUDIT_WRITE
SecureBits=noroot-locked noroot
EOF
chmod 0644 /etc/systemd/system/nscd.service.d/90-security.conf

# Secure cron directories
chmod 0700 /etc/{cron.d,cron.daily,cron.hourly,cron.monthly,cron.weekly}
chmod 0600 /etc/crontab

# IO is busy for ondemand scheduler
echo "w	/sys/devices/system/cpu/cpufreq/ondemand/io_is_busy	-	-	-	-	1" > /etc/tmpfiles.d/io_is_busy.conf

# Run dpkg-reconfigure
/usr/sbin/dpkg-reconfigure tzdata locales keyboard-configuration

# Configure default target
/bin/systemctl set-default multi-user.target

# Disable apt timers
/bin/systemctl disable apt-daily-upgrade.timer apt-daily.timer
/bin/systemctl mask apt-daily-upgrade.timer apt-daily.timer

# Configure network
cat > /etc/systemd/network/eth0.network << EOF
[Match]
Name=eth0

[Link]
RequiredForOnline=yes

[Network]
DHCP=ipv4
LLMNR=no
LLDP=no
EmitLLDP=no
IPv6PrivacyExtensions=yes
IPv6AcceptRA=yes

[DHCP]
SendHostname=no
UseDomains=yes

[IPV6ACCEPTRA]
UseDNS=no
EOF
/bin/systemctl enable systemd-networkd.service

# /etc/hosts
cat > /etc/hosts << EOF
127.0.0.1	localhost.localdomain	localhost
127.0.1.1	rockpi4.wojo.home	rockpi4
::1		localhost.localdomain	localhost
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

# Remove machine-id
rm -f /etc/machine-id

# Remove ssh keys
rm /etc/ssh/ssh_host*

# Script for initrd rebuild after first boot
cat > /usr/local/sbin/firstboot.sh << EOF
#!/bin/sh
set -e
kver=\$(uname -r)
mkinitramfs -o /boot/initrd.img-\${kver} \${kver}
sha1sum /boot/initrd.img-\${kver} > /var/lib/initramfs-tools/\${kver}
mkimage -A arm64 -T ramdisk -C none -n uInitrd -d /boot/initrd.img-\${kver} /boot/uInitrd-\${kver}

test -e /etc/ssh/ssh_host_rsa_key     || ssh-keygen -q -f /etc/ssh/ssh_host_rsa_key     -N '' -t rsa -b 2048
test -e /etc/ssh/ssh_host_ecdsa_key   || ssh-keygen -q -f /etc/ssh/ssh_host_ecdsa_key   -N '' -t ecdsa
test -e /etc/ssh/ssh_host_ed25519_key || ssh-keygen -q -f /etc/ssh/ssh_host_ed25519_key -N '' -t ed25519

rm -f /etc/systemd/system/multi-user.target.wants/firstboot.service /etc/systemd/system/firstboot.service /usr/local/sbin/firstboot.sh
fstrim /boot
exit 0
EOF
chmod 0744 /usr/local/sbin/firstboot.sh

cat > /etc/systemd/system/firstboot.service << EOF
[Unit]
Description=Starts script for system initialization at first start
Before=ssh.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/firstboot.sh

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/firstboot.service

/bin/systemctl enable firstboot.service

# Scripts to recreate boot.scr and initrd
cat > /usr/local/sbin/create-boot-scr.sh << EOF
#!/bin/sh
mkimage -C none -A arm64 -T script -d /boot/boot.cmd /boot/boot.scr
EOF

cat > /usr/local/sbin/create-uinitrd.sh << EOF
#!/bin/sh
if [ -z "\$1" -o -z "\$2" ]; then
	echo "Usage: create-uinitrd.sh source-initrd uimage-initrd"
	exit 1
fi
mkimage -A arm64 -T ramdisk -C none -n uInitrd -d \$1 \$2
EOF

mkdir -m 755 -p /etc/initramfs/post-update.d
cat > /etc/initramfs/post-update.d/10-uImage << EOF
#!/bin/sh
mkimage -A arm64 -T ramdisk -C none -n "uInitrd \$1" -d \$2 /boot/uInitrd-\$1
EOF

chmod 744 /usr/local/sbin/create-boot-scr.sh /usr/local/sbin/create-uinitrd.sh /etc/initramfs/post-update.d/10-uImage

# No resume
echo RESUME=none > /etc/initramfs-tools/conf.d/resume
chmod 0644 /etc/initramfs-tools/conf.d/resume

# Clean up run directory
rm -rf /run /boot
mkdir -m 0755 /run /boot

# Clean up log directory
> /var/log/dpkg.log
> /var/log/alternatives.log
> /var/log/bootstrap.log
