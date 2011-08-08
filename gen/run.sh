#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: gen.sh

BLKSZ=4096
SRC=${1-"./ch_gentoo"}
if [ ! -d "${SRC}" ];
then
	echo "\$SRC: '$SRC' not exists, exit"
	exit 1
fi
SRC=$(realpath "${SRC}")
CDI=$(realpath "${0}")
CDI=$(dirname "${CDI}")
TRG=$(dirname "${SRC}")
TRG="${TRG}/root"

xno=$(echo $* | grep no2gis)
if [ -z "$xno" ];
then
	echo "## update 2gis"
	"${CDI}/2gis_upd.sh" "${SRC}" "/usr/local/wine-exec"
fi

xno=$(echo $* | grep noroot)
if [ -z "$xno" ];
then
	echo "## create root"
	LIST=$(tempfile)
	(
		echo "# generate list: '${LIST}'"
		# mkdir -p /tmp /var/tmp /var/db/pkg /proc /sys
		# ln -s /var/tmp /usr/tmp
		# chmod 1777 /tmp /var/tmp
		(
			cd "${SRC}"
			find ./ \( -path './proc' -o -path './sys' -o -path './boot'\
				-o -path './usr/src' -o -path './usr/include' -o -path './dev'\
				-o -path './usr/portage' -o -path './var/lib/layman'\
				-o -path './tmp' -o -path './var/tmp' -o -path './var/db/pkg'\
				-o -path './usr/share/doc' -o -path './usr/share/man'\
				-o -path './root' -o -path './usr/share/gtk-doc'\
				-o -name '*.a' -o -name '*.la' -o -name '*.pc'\
				-o -name '*.h' -o -name '*.hpp' \)\
				-prune -o -name '*' -print 2>/dev/null
			find ./usr/include -name 'pyconfig.h' -print 2>/dev/null
		) | pv > "${LIST}"
		echo "# generate directory list: '${LIST}.dir'"
		(
			cd "${SRC}"
			find "./boot" "./var/tmp"\
				\( -path './var/tmp/ccache' -o -path './var/tmp/portage' \)\
				-prune -o -type d 2>/dev/null
		) | pv > "${LIST}.dir"
		echo "# calc size"
		S=$("${CDI}/size3.py" "${SRC}" "${LIST}" "$BLKSZ")
		echo "@ need '${S}' blocks with size at '${BLKSZ}', make dirs"
		rm -rf "$TRG"
		mkdir -p "$TRG"
		echo "@ create image"
		dd if=/dev/zero "of=${TRG}.fs" "seek=${S}" "bs=${BLKSZ}" count=1
		#mkfs -t btrfs "${TRG}.fs"
		echo "y" | mkfs -t ext2 "${TRG}.fs"
		tune2fs -c 0 -i 0 "${TRG}.fs"
		#mount -o loop,compress=zlib "${TRG}.fs" "${TRG}"
		mount -o loop "${TRG}.fs" "${TRG}"
		echo "@ update dirs"
		(
			cd "${TRG}"
			while read line;
			do
				mkdir -p "${line}"
				touch "${line}/.keep"
			done <"${LIST}.dir"
			for q in "tmp" "var/tmp"\
				"var/db/pkg" "proc" "sys" "mnt" "media" "root" "dev";
			do
				mkdir -p "$q"
			done
		)
		echo "@ make base /dev"
		(
			for q in console null zero stdin stdout;
			do
				cp -a "/dev/$q" "${TRG}/dev/"
			done
		)
		echo "@ make copy"
		(
			cd "${SRC}"
			LNA=$(wc -l "${LIST}" | awk '{print $1}')
			LN=0
			echo -ne "0/${LNA}:"
			while read line;
			do
				LN=$(expr $LN + 1)
				echo -ne "\r${LN}/${LNA}: "
				if ( [ -d "${line}" ] && [ ! -L "${line}" ] );
				then
					echo -n "* ${line}"
					mkdir -p "${TRG}/${line}"
				else
					(
						SD=$(dirname "${line}")
						[ ! -e "${TRG}/${SD}" ] && mkdir -p "${TRG}/${SD}"
						echo -n $(cp -av "${line}" "${TRG}/${SD}" | sed -e "s/\`\([^' ]*\).*\|.*/\1/")
					)
				fi
			done <"${LIST}"
			echo "*"
		)
		echo "@ create squash"
		rm -f "${TRG}.squashfs"
		mksquashfs "$TRG" "${TRG}.squashfs"
		echo "@ umount"
		umount "${TRG}"
	)
	echo "# remove '${LIST}'"
	rm "${LIST}"
	rm ${LIST}\.*
fi


TRG=$(dirname "$TRG")
TRG="${TRG}/initrd"
xno=$(echo $* | grep noinitrd)
if [ -z "$xno" ];
then
	LIST=$(tempfile)
	echo "## create initrd"
	(
		rm -rf "$TRG"
		echo "# create dirs"
		for q in "etc" "bin" "sbin" "proc" "sys" "dev" "tmp" "mnt" "lib" "var/log" "var/run" "initrd";
		do
			mkdir -p "${TRG}/${q}"
		done
		echo "# copy /dev"
		cp -a /dev/null "${TRG}/dev"
		cp -a /dev/zero "${TRG}/dev"
		cp -a /dev/console "${TRG}/dev"
		echo "# copy programs"
		cp "${SRC}/bin/busybox" "${TRG}/bin/"
		cp "${SRC}/usr/sbin/nbd-client" "${TRG}/bin"
		cp "${CDI}/udhcpc-script.sh" "${TRG}/sbin"
		cp "${CDI}/init.initramfs.sh" "${TRG}/init"
		(
			cd "${TRG}"
			ln -s /bin/busybox ./bin/sh
			ln -s /lib ./lib64
			chmod -R +x-w "./bin"
			chmod -R +x-w "./sbin"
			chmod +x-w "./init"
		)
		echo >"$LIST"
		echo "# generate library list for /bin /sbin"
		(
			cd "${SRC}"
			mkdir -p ./mnt/initrd
			mount --bind "${TRG}" "./mnt/initrd"
			(
				linux32 chroot . find /mnt/initrd/bin /mnt/initrd/sbin -type f -exec ldd {} \; | sed 's/.*[[:space:]]\(\/lib.*\)[[:space:]].*\|.*/\1/' | grep -v '^$' >> "${LIST}"
				linux32 chroot . find /mnt/initrd/bin /mnt/initrd/sbin -type f -exec ldd {} \; | sed 's/.*[[:space:]]\(\/usr\/lib.*\)[[:space:]].*\|.*/\1/' | grep -v '^$' >> "${LIST}"
			)
			umount -f "./mnt/initrd"
		)
		echo "# generate library list for /lib"
		(
			cd "${SRC}"
			while read line;
			do
				[ -z "$line" ] && continue
				linux32 chroot . ldd "$line" | sed 's/.*[[:space:]]\(\/lib.*\)[[:space:]].*\|.*/\1/' | grep -v '^$' >> "${LIST}"
				linux32 chroot . ldd "$line" | sed 's/.*[[:space:]]\(\/usr\/lib.*\)[[:space:]].*\|.*/\1/' | grep -v '^$' >> "${LIST}"
			done <"$LIST"
		)
		echo "# sort list"
		cat "$LIST" | sort -n | uniq > "${LIST}.t"
		mv "${LIST}.t" "${LIST}"
		echo "# copy libs"
		(
			cd "${SRC}"
			while read line;
			do
				[ -z "$line" ] && continue
				cp "./$line" "${TRG}/lib"
			done <"$LIST"
		)
		echo "# copy aufs module"
		{
			cd "${TRG}"
			F=$(linux32 chroot "${SRC}" qlist aufs2 | grep 'aufs\.ko')
			if [ -z "$F" ];
			then
				echo "aufs2 can't find in gentoo installed, abort"
				exit 1
			fi
			FD=$(dirname "$F")
			mkdir -p "./$FD"
			cp "${SRC}/$F" "./${FD}"
			#FD=$(dirname "$FD")
			#cp -a "${SRC}/${FD}"/*\.* "./$FD"
		}
		echo "# make archive"
		(
			cd "${TRG}"
			find . | cpio -H newc -vo | gzip -9v > "${TRG}.gz"
			#mksquashfs "$TRG" "${TRG}.squashfs"
			#cat "${TRG}.squashfs" | gzip -9v - > "${TRG}.gz"
			#rm -f "${TRG}.squashfs"
		)
	)
	echo "# remove '$LIST'"
	rm -rf "$LIST"
fi

