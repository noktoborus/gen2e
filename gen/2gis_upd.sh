#!/bin/sh
# vim: ft=sh ff=unix fenc=utf-8
# file: 2gis_upd.sh

TRG_R=${1-""}
TRG=${2-""}

if [ -z "$TRG_R" -o -z "$TRG" ];
then
	echo "target can't set"
	echo "usage: $0 <target_root> <target>"
	exit 1
fi

wget -O /dev/stdout "http://vladivostok.2gis.ru/how-get/linux/"\
	| sed 's/.*\(http\:\/\/download\.2gis\.ru\/arhives\/2GIS.*\.zip\).*\|.*/\1/'\
	| while read url;
do
	[ -z "$url" ] && continue
	wget -c "$url"
	SD=$(realpath .)
	FN=$(basename "$url")
	(
		mkdir -p "${TRG_R}/${TRG}"
		cd "${TRG_R}/${TRG}"
		echo "# unzip to '${TRG_R}/${TRG}' from '${SD}/${FN}'"
		unzip -o "${SD}/${FN}"
	)
done

pa=$(cd "${TRG_R}"; find "./${TRG}" -name 'grym.exe' | tail -n1 | sed 's/^\.\///')
di=$(dirname "$pa")

mkdir -p "${TRG_R}/usr/share/applications"
cat > "${TRG_R}/usr/share/applications/2gis.desktop" <<!
[Desktop Entry]
Name=2GIS
Comment=Browse the city
GenericName=2GIS
Exec=/bin/sh -c "cd '$di'; wine '$pa'"
Icon=d1f7_grym.png
Terminal=false
StartupNotify=true
Type=Application
Categories=Office;

# vi:set encoding=UTF-8:
!

mkdir -p "${TRG_R}/usr/share/icons"
cat > "${TRG_R}/usr/share/icons/d1f7_grym.png" <<!
QlpoOTFBWSZTWaZS1xwAAETfgAAwfvPwXz+rng6/79/+QAH91lnJsIiR6g/VHppAGNQeoaG1NqBk
A0AZBqEZJjEU9onqD1NI2kPKGDQCMmQ0CIwkZJgKeTTKHo0T1AGJoaGgD1PUGmiUybQ1Jp6nqBpo
NDRp5Q9NQMRoPU00KIShBR0heSdBGmocD/Ty2+2LFCIzVj9y55YpdbTuhu8xEvAN73xev0+qgpiM
wzFvZl8GPvc8BwcEKFeDrnJiwZEA5624k+7+Dzu1d4zACPxVKBOBnDMAocoDKctVdRisc5QDdAmE
QmKQHTxQ/K90uAqktmxmCNTUSGvynlzHtJqziXCBkgZQb3AnWMiII5HfAixsnruxlMj4v8J3DI1G
PRB4Ngc18ixO1XW5L4oFqKqRkUosdNrbnO2TYI0Q3JCElGyftcTeQoEQjJOXl865t2cl7dncDEzw
SqtbJ73FqA9I3hbhGYe0CiXizCYQ/GaYXbZ7BDQgGlzjxyLgp4FkCVHU2bKMx7tZCgREDw+JxAkQ
mdRijSv0vcbTkiBSZVoWqtYulB1NHyJ6SjSTFKFFBQg9IdZ4NEzYHArI8KNAegyuwRHH4HnExzIS
e/VFdlVXHYAaAqFqNWVYqc21iLRgiJXAsDWRcZniiRyBbNPlde03x5JHmVUt6GwrfdCx0RjEXTUH
9Qp6ugnariADNyht23tYwDlmswyMS9scH2LL0dxfItOFnCZ6iciHYsZzaRobCWM0vrDufCNLQyTv
GNgKQwfrQ7cJGXpbiaFQBBkTJO8H2WXFhvdW2oSOYQkg5Ti0edvD/F3JFOFCQplLXHA=
!

