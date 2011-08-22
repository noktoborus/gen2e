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

give_shell ()
{
	echo "## start shell"
	sh
	return 1
}

get_if_cfg ()
{
	[ -z "$eif" ] && return 1
	cat /proc/cmdline | sed 's/ /\n/g' | sed 's/.*eif_'$eif'=\([^ ]*\).*\|.*/\1/'
	return 0
}

get_ifs ()
{
	ip link show | sed -e 's/[0-9]*: \([^ :]*\).*\|.*/\1/' -e '/^$/d'
}

_is_debug ()
{
	echo " `cat /proc/cmdline` " | grep ' kzdebug '
}

echo "*** mount base"
touch /etc/mtab
pre_mount M

_is_debug && give_shell

echo "*** get root path"
NBD_ROOT=$(cat /proc/cmdline | sed 's/.*kznbd=\([a-zA-Z0-9.]*\).*\|.*/\1/')
[ -z "$NBD_ROOT" ] && give_shell
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
[ $? -ne 0 ] && give_shell

echo "*** configure network"
get_ifs | while read eif;
do
	[ -z "$eif" ] && continue
	echo "** configure $eif"
	get_if_cfg "$eif" | while read cfg;
	do
		[ -z "$cfg" ] && continue
		echo "**	$cfg"
		if [ "$cfg" = "dhcp" ];
		then
			udhcpc -s /sbin/udhcpc-script.sh -i eth0
		else
			ip link set up dev "$eif"
			ip address add $cfg dev "$eif"
		fi
	done
done
[ $? -ne 0 ] && give_shell

echo "*** configure nbd"
nbd-client "$NBD_ROOT" "$NBD_PORT" /dev/nbd0 -p
[ $? -ne 0 ] && give_shell

echo "*** mount nbd"
mount /dev/nbd0 /mnt
[ $? -ne 0 ] && give_shell

echo "*** killall"
killall -9 udhcpc

echo "*** umount base"
pre_mount U

echo "*** starting new root"
exec switch_root /mnt /sbin/init

echo "@@@ FAIL"
exec sh
