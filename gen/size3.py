#!/usr/bin/env python3

import os
import sys

listf = "./list"
rootd = "./ch_gentoo"
blksize = 4096

print (sys.argv, file=sys.stderr)

if len (sys.argv) > 1:
	rootd = sys.argv[1]

if len (sys.argv) > 2:
	listf = sys.argv[2]

if len (sys.argv) > 3:
	blksize = int (sys.argv[3])

f = open (listf, 'r')
l = f.read ().split ('\n')
f.close ()

s = 0
for q in l:
	p = rootd + "/" + q
	if os.path.isfile (p) and not os.path.islink (p):
		s += os.path.getsize (p)

#print (s)
if s:
	print (int (blksize + ((s * 2) / blksize)))
else:
	print (0)

