#!/bin/sh
# Respins the base OpenBSD install ISO into a self-provisioning one.
#
# MUST run on an OpenBSD machine (needs vnd(4)/vnconfig to mount bsd.rd's
# embedded ramdisk filesystem - not available on Linux). Run this from
# openbsd-btw itself, or any other OpenBSD box.
#
# NOT YET TESTED END-TO-END - this is a solid first draft of the right
# sequence of operations, not a proven working script. Expect to iterate:
# ISO respinning/ramdisk mount details are exactly the kind of thing that
# needs a real run to shake out. Needs root (mounting the vnd device).
set -e

REL=7.9
ARCH=amd64
WORKDIR=$(mktemp -d)
ISO_URL="https://cdn.openbsd.org/pub/OpenBSD/${REL}/${ARCH}/install${REL%.*}${REL#*.}.iso"
OUT_ISO="./openbsd-btw-${REL}.iso"

echo "==> Working in $WORKDIR"
cd "$WORKDIR"

echo "==> Fetching base install ISO"
ftp -o base.iso "$ISO_URL"

echo "==> Extracting ISO contents"
mkdir iso_root
vnconfig vnd1 base.iso
mount -t cd9660 -o ro /dev/vnd1c iso_mnt 2>/dev/null || { mkdir iso_mnt; mount -t cd9660 -o ro /dev/vnd1c iso_mnt; }
cp -Rp iso_mnt/* iso_root/
umount iso_mnt
vnconfig -u vnd1

echo "==> Building site set (site79.tgz) with install.site"
mkdir site_root
cp "$(dirname "$0")/install.site" site_root/install.site
chmod +x site_root/install.site
( cd site_root && tar -czf ../iso_root/${REL%.*}${REL#*.}/${ARCH}/site${REL%.*}${REL#*.}.tgz install.site )

echo "==> Injecting auto_install.conf into bsd.rd's embedded ramdisk"
cp iso_root/${REL%.*}${REL#*.}/${ARCH}/bsd.rd bsd.rd.orig
cp bsd.rd.orig bsd.rd.new
# bsd.rd carries an embedded rd(4) filesystem image as part of the kernel;
# rdsetroot(8) extracts/replaces it directly - this is the OpenBSD-native
# way to do this (no vnd mount needed for the ramdisk itself, only for
# reading the ISO above).
rdsetroot -x bsd.rd.new ramdisk.fs
vnconfig vnd2 ramdisk.fs
mount /dev/vnd2a ramdisk_mnt 2>/dev/null || { mkdir ramdisk_mnt; mount /dev/vnd2a ramdisk_mnt; }
cp "$(dirname "$0")/install.conf" ramdisk_mnt/auto_install.conf
umount ramdisk_mnt
vnconfig -u vnd2
rdsetroot bsd.rd.new ramdisk.fs
cp bsd.rd.new iso_root/${REL%.*}${REL#*.}/${ARCH}/bsd.rd

echo "==> Rebuilding hybrid ISO"
mkhybrid -a -R -T -L -l -d -D -N \
	-o "$OUT_ISO" \
	-b ${REL%.*}${REL#*.}/${ARCH}/cdbr \
	-c ${REL%.*}${REL#*.}/${ARCH}/boot.catalog \
	iso_root

echo "==> Done: $OUT_ISO"
echo "    Test it in a scratch VM before relying on it."

cd /
rm -rf "$WORKDIR"
