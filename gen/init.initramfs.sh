#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: init.initramfs.sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin
ROOT_FROM="/mnt"

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

get_bd_addr ()
{
	cat /proc/cmdline | sed -e 's/.*rzbd_addr=\([^ ]*\).*\|.*/\1/' -e '/^$/d'
}

split_bd_addr ()
{
	case "$1" in
		lv)
			sed -e 's/\(.*\):.*\|.*/\1/' -e '/^$/d'
			;;
		rv)
			sed -e 's/.*:\(.*\)\|.*/\1/' -e '/^$/d'
			;;
	esac
}

get_bd_type ()
{
	cat /proc/cmdline | sed -e 's/.*rzbd_type=\([^ ]*\).*/\1/' -e '/^$/d'
}

resolv_host ()
{
	ADDR=
	TYPE=${2-"A"}
	ADDR=$(echo "$1" | sed -e 's/^\([^\/:]*\).*\|.*/\1/' -e '/^$/d')
	[ -z "$ADDR" ] && return 1
	ADDR=$(dig "$ADDR" | sed -e 's/.*IN[[:space:]]*'"$TYPE"'[[:space:]]*\(.*\)\|.*/\1/' -e '/^$/d' | head -n 1)
	if [ -z "$ADDR" ];
	then
		echo "$1"
	else
		echo -n $ADDR
		echo "$1" | sed -e 's/^[^\/:]*\(.*\)\|.*/\1/'
	fi
	return 0
}

_is_debug ()
{
	echo " `cat /proc/cmdline` " | grep ' kzdebug '
}

if [ -z "$INITRD_NORUN" ];
then
	echo "*** mount base"
	touch /etc/mtab
	pre_mount M

	_is_debug && give_shell

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

	RADDR=$(get_bd_addr)
	if [ -z "$RADDR" ];
	then
		echo "*** root address is null"
		give_shell
	else
		echo "*** root address is '$RADDR'"
	fi

	BD_TYPE=$(get_bd_type)
	case "$BD_TYPE" in
		nbd)
			echo "*** get nbd root"
			NBD_ROOT=$(echo "$RADDR" | split_bd_addr lv)
			NBD_ROOT=$(resolv_host "$NBD_ROOT")
			if [ -z "$NBD_ROOT" ];
			then
				echo "!! unknown nbd root addr"
				give_shell
			fi
			NBD_PORT=$(echo "$RADDR" | split_bd_addr rv)
			echo "# pointer at '$NBD_ROOT', port '$NBD_PORT'"
			echo "*** configure nbd"
			nbd-client "$NBD_ROOT" "$NBD_PORT" /dev/nbd0 -p
			[ $? -ne 0 ] && give_shell
			echo >> /etc/fstab
			echo "/dev/nbd0 /mnt auto defaults 0 0" >> /etc/fstab
			;;
		local)
			LOCAL_ADDR=$(echo "$RADDR" | split_bd_addr lv)
			REMOTE_ADDR=$(echo "$RADDR" | split_bd_addr rv)
			REMOTE_ADDR=$(resolv_host "$REMOTE_ADDR")
			echo "*** use '$LOCAL_ADDR' as storage, '$REMOTE_ADDR' as remote"
			ROOT_FROM="/mnt/newroot"
			if [ -z "$LOCAL_ADDR" -o -z "$REMOTE_ADDR" ];
			then
				echo "!! use null as address?"
				give_shell
			else
				echo >> /etc/fstab
				echo "$LOCAL_ADDR /mnt auto defaults 0 0" >> /etc/fstab
			fi
	esac

	echo "*** mount root"
	mount /mnt
	[ $? -ne 0 ] && give_shell

	if [ x"$BD_TYPE" = x"local" ];
	then
		echo "*** use root as storage"
		(
			cd /mnt
			RADDR=$(get_bd_addr)
			REMOTE_ADDR=$(echo "$RADDR" | split_bd_addr rv)
			REMOTE_ADDR=$(resolv_host "$REMOTE_ADDR")
			R=0
			CUR=$(wget -O /dev/stdout "http://$REMOTE_ADDR/current")
			if [ ! -f "$CUR" ];
			then
				wget "http://$REMOTE_ADDR/$CUR"
				R=$?
			fi
			if [ $R -eq 0 ];
			then
				mkdir -p "$ROOT_FROM"
				mount "$CUR" "$ROOT_FROM"
				R=$?
			fi
			return $R
		) || give_shell
	fi

	echo "*** killall"
	killall -9 udhcpc

	echo "*** umount base"
	pre_mount U

	echo "*** starting new root"
	exec switch_root "$ROOT_FROM" /sbin/init

	echo "@@@ FAIL, exec sh"
	exec sh
fi

