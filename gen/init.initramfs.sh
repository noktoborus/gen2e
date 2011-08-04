#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: init.initramfs.sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin

pre_mount ()
{
	A=${1-"M"}
	if [ x"$A" = x"M" ];
	then
		mount -t sysfs none /sys
		mount -t proc none /proc
	elif [ x"$A" = x"U" ];
	then
		umount /proc
		umount /sys
	fi
}

echo "*** mount base"
touch /etc/mtab
pre_mount M

echo "*** get root path"
NBD_ROOT=$(cat /proc/cmdline | sed 's/.*kznbd=\([a-zA-Z0-9.]*\).*\|.*/\1/')
[ -z "$NBD_ROOT" ] && exit 1
NBD_PORT=$(echo "$NBD_ROOT" | sed 's/.*:\([0-9]*\)\|.*/\1/')

if [ ! -z "$NBD_PORT" ];
then
	NBD_ROOT=$(echo "$NBD_ROOT" | sed 's/\(.*\):[0-9]*\|.*/\1/')
else
	NBD_PORT="1023"
fi
echo "# pointer at '$NBD_ROOT', port '$NBD_PORT'"

echo "*** generate /dev"
mdev -s

echo "*** modprobe aufs"
insmod /lib/modules/`uname -r`/misc/aufs.ko
[ $? -ne 0 ] && exit 1

echo "*** configure network"
udhcpc -s /sbin/udhcpc-script.sh -i eth0
[ $? -ne 0 ] && exit 1

echo "*** configure nbd"
nbd-client "$NBD_ROOT" "$NBD_PORT" /dev/nbd0 -p
[ $? -ne 0 ] && exit 1

echo "*** mount nbd"
mount /dev/nbd0 /mnt
[ $? -ne 0 ] && exit 1

echo "*** killall"
killall -9 udhcpc

echo "*** umount base"
pre_mount U

echo "*** starting new root"
exec switch_root /mnt /sbin/init

echo "@@@ FAIL"
