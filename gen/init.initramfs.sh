#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: init.initramfs.sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin
BD_FLAG_STR="UNCOMPLETED"
BD_FLAG_LEN=$(echo -n "$BD_FLAG_STR" | wc -c)


# possible variables in /proc/cmdline:
# kzdebug		:use debug mode
# eif_<ifname>	:set up interface with name <ifname>, allow values: dhcp, ipaddr/CID
# kroot_addr	:address on nbd server, in format: address:port
# kroot_addr_lo	:address of local device, for storage, format: address (/dev/sda1, UUID=..., etc)

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
	export INITRD_NORUN=1
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

get_addr ()
{
	ID="$1"
	[ -z "$ID" ] && return 1
	cat /proc/cmdline | sed -e 's/ /\n/g' | sed -e 's/.*'"$ID"'=\([^ ]*\).*\|.*/\1/' -e '/^$/d'
}

split_addr ()
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

get_last_bytes ()
{
	IN="$1"
	INSZ="$2"
	BCOUNT="$3"
	if [ -z "$IN" -o -z "$INSZ" -o -z "$BCOUNT" ];
	then
		echo "args not completed: IN='$IN', INSZ='$INSZ', BCOUNT='$BCOUNT'" >&2
		return 1
	fi
	if [ $BCOUNT -gt $INSZ ];
	then
		echo "BCOUNT is greater then INSZ ('$BCOUNT' > '$INSZ')" >&2
		return 2
	fi
	T=$(expr $INSZ - $BCOUNT)
	echo "T+$T, I:$INSZ, $BCOUNT" >&2
	dd "if=$IN" bs=1 "skip=$T" "count=$BCOUNT"
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

	# fix fstab
	echo >> /etc/fstab

	LSKEY=""
	LADDR=$(get_addr kroot_addr_lo)
	RSKEY=""
	RADDR=$(get_addr kroot_addr)
	RPORT=0
	echo "*** remote '$RADDR', local '$LADDR'"
	# local storage
	if [ ! -z "$LADDR" ];
	then
		echo "*** mount local storage"
		echo "$LADDR /mnt auto defaults,rw,errors=continue 0 0" >> /etc/fstab
		mount "$LADDR"
		if [ $? -ne 0 ];
		then
			echo "!! local storage mount fail"
			LADDR=""
		else
			if [ -e "/mnt/swap" ];
			then
				echo "*** swapon /mnt/swap"
				swapon /mnt/swap
			fi
			if [ -r "/mnt/image" ];
			then
				echo "*** get local serial key"
				LSKEY=$(/bin/blkid /mnt/image | sed -e 's/.*UUID=["]\{0,1\}\([^ "]*\).*/\1/' -e '/^$/d')
				[ -z "$LSKEY" ] && echo "*** local serial not present"
				CHECKFL=$(get_last_bytes /mnt/image "`stat -c%s /mnt/image`" "$BD_FLAG_LEN")
				if [ "$CHECKFL" = "$BD_FLAG_STR" ];
				then
					echo "*** flag setted, set image to fail state"
					LSKEY=""
				fi
			else
				echo "*** image not present, skip lskey get"
			fi
		fi # mount try
	else
		echo "*** local storage not defined, skipped"
	fi
	# remote storage
	if [ ! -z "$RADDR" ];
	then
		RPORT=$(echo "$RADDR" | split_addr rv)
		[ -z "$RPORT" ] && RPORT=1023
		RADDR=$(echo "$RADDR" | split_addr lv)
		RADDR=$(resolv_host "$RADDR")
		echo "*** setup nbd ($RADDR:$RPORT)"
		RSZ=$(/bin/nbd-client "$RADDR" "$RPORT" /dev/nbd0 2>&1)
		RSZ=$(echo "$RSZ" | sed -e 's/.*sz=\([0-9]*\)[[:space:]]bytes.*\|.*/\1/' -e '/^$/d')
		if [ -z "$RSZ" ];
		then
			echo "!!! nbd-client return no size (may be nbd-server can't work)"
			RADDR=""
		else
			# test sizes with local image
			if [ ! -z "$LADDR" ];
			then
				RSKEY=$(/bin/blkid /dev/nbd0 | sed -e 's/.*UUID=["]\{0,1\}\([^ "]*\).*/\1/' -e '/^$/d')
				echo "*** check skeys L:'$LSKEY', R:'$RSKEY'"
				if [ x"$LSKEY" != x"$RSKEY" -o ! -r "/mnt/image" ];
				then
					echo "*** check space for image"
					rm -f /mnt/image >/dev/null 2>&1
					LSZ=$(df -B 1 | grep '/mnt$' | awk '{print $4}')
					if [ -z "$LSZ" ];
					then
						echo "!! can't gen free space info for /mnt, fail local"
						LADDR=""
					elif [ ${LSZ} -lt ${RSZ} ];
					then
						echo "!! space on local not enough for store image ('$LSZ' less than '$RSZ')"
						LADDR=""
					else
						echo "*** grow local image to ${RSZ}"
						dd if=/dev/zero of=/mnt/image bs=1 "seek=$RSZ" count=0
						RSZ=$(expr $RSZ - $BD_FLAG_LEN)
						echo -n "$BD_FLAG_STR" | dd of=/mnt/image bs=1 "seek=$RSZ"
						[ $? -ne 0 ] && give_shell
					fi
				else
					echo "*** local image is ready, close remote"
					RADDR=""
					/bin/nbd-client -d /dev/nbd0
				fi
			else
				echo "*** local not present, skip sync"
			fi
		fi # test nbd setup
	else
		echo "*** remote not defined, skipped"
	fi
	# attach local image
	if [ ! -z "$LADDR" ];
	then
		echo "*** setup local image '/mnt/image'"
		/bin/losetup /dev/loop1 /mnt/image || give_shell
	fi
	# setup raid1
	if [ ! -z "$RADDR" ];
	then
		echo "*** setup raid1 with remote as master"
		echo y | mdadm --build /dev/md1 --run --level=1 --force --raid-devices=1 /dev/nbd0
		[ $? -ne 0 ] && give_shell
		if [ ! -z "$LADDR" ];
		then
			echo "*** attach to raid local image"
			(
				mdadm --manage /dev/md1 --add /dev/loop1 &&\
				mdadm --grow /dev/md1 --raid-devices=2
			) || give_shell
		fi
	elif [ ! -z "$LADDR" ];
	then
		echo "*** setup raid1 with local-only image"
		echo y | mdadm --build /dev/md1 --run --level=1 --force --raid-devices=1 /dev/loop1
		[ $? -ne 0 ] && give_shell
	fi
	# end prepare
	(
		echo "*** mount /dev/md1 as newroot"
		mkdir -p /mnt/_root
		echo "/dev/md1 /mnt/_root auto defaults,noatime,nodiratime,ro 0 0" >> /etc/fstab
		mount /dev/md1
	) || give_shell
	# switch
	echo "*** killall"
	killall -9 udhcpc

	echo "*** umount base"
	pre_mount U

	echo "*** starting new root"
	exec switch_root "/mnt/_root" /sbin/init

	echo "@@@ FAIL, exec sh"
	exec sh
fi

