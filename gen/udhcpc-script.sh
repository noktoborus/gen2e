#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: gen/udhcpc-script.sh


case "$1" in
	deconfig)
		ip link set down dev "$interface"
		ip addr flush dev "$interface"
		ip link set up dev "$interface"
		;;
	bound)
		ip addr add "$ip/$mask" dev "$interface"
		touch /etc/resolv.conf
		if [ $? -eq 0 ];
		then
			[ ! -z "domain" ] && echo "domain $domain" >> /etc/resolv.conf
			if [ ! -z "$dns" ];
			then
				for q in $dns;
				do
					echo "nameserver $q" >> /etc/resolv.conf
				done
			fi
		fi
		;;
esac

