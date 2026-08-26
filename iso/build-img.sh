#!/bin/sh
# Builds a self-installing OpenBSD install image based on install79.img -
# a raw, dd-able USB disk image - not install79.iso.
#
# Use THIS for anything going on a USB stick / real hardware. OpenBSD's
# own docs (openbsd.org/faq/faq4.html) are explicit that .iso is for
# optical media and .img is "a disk image that can be written to a USB
# flash drive" - and this was confirmed as a real, practical failure,
# not just a documentation nuance: an ISO-based build (build-iso.sh)
# booted fine as a virtual CD-ROM in every VM test done during
# development, but failed to boot on 3 different real laptops from 2
# different USB sticks written with dd.
#
# Structurally much simpler than the ISO approach, too. install79.img
# already has a working MBR partition table, EFI System Partition, and
# bootable OpenBSD (FFS) partition, built and tested by the OpenBSD
# project itself - none of that gets touched or regenerated here. This
# just mounts the existing FFS partition read-write and copies two
# things into it in place (the site set, and a re-injected bsd.rd)
# rather than extracting everything and rebuilding a brand new image
# from scratch the way the ISO approach (via mkhybrid) did. That
# extract-and-rebuild step is also what caused the ISO approach's own
# UEFI boot bug: mkhybrid reassigns fresh LBA/sector offsets to every
# file when it rebuilds an image, which silently broke a boot-critical
# file position (the UEFI boot catalog entry) that was only valid for
# the original file layout. Editing in place instead of rebuilding means
# the boot mechanism itself - MBR, EFI partition, disklabel - is never
# touched, so there's nothing to go stale.
#
# MUST run on an OpenBSD machine (needs vnd(4)/vnconfig, disklabel, and
# ffs mount support - not available on Linux). Needs root (mounting the
# vnd device).
set -e

REL=7.9
RELNUM=$(echo "$REL" | tr -d .)   # "7.9" -> "79", for filenames like site79.tgz.
ARCH=amd64
# Capture absolute paths BEFORE we cd into the scratch workdir below -
# see build-iso.sh's own comment on this same gotcha.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ORIG_DIR=$(pwd)

# Not /tmp, and not $HOME under doas - see build-iso.sh's own comment on
# this same gotcha (root's home is on a small base-OS partition).
WORKDIR_BASE="${1:-/tmp}"
mkdir -p "$WORKDIR_BASE"
WORKDIR=$(mktemp -d "$WORKDIR_BASE/openbsd-btw-img.XXXXXXXX")
IMG_URL="https://cdn.openbsd.org/pub/OpenBSD/${REL}/${ARCH}/install${RELNUM}.img"
OUT_IMG="$ORIG_DIR/openbsd-btw-${REL}.img"

cleanup() {
	exit_code=$?
	umount "$WORKDIR/img_mnt" 2>/dev/null || true
	umount "$WORKDIR/ramdisk_mnt" 2>/dev/null || true
	vnconfig -u vnd1 2>/dev/null || true
	vnconfig -u vnd2 2>/dev/null || true
	cd /
	if [ "$exit_code" -eq 0 ]; then
		rm -rf "$WORKDIR"
	else
		echo "==> Failed - scratch dir left at $WORKDIR for inspection"
	fi
}
trap cleanup EXIT

# In case a previous crashed run left these configured/mounted.
umount /dev/vnd1a 2>/dev/null || true
umount /dev/vnd2a 2>/dev/null || true
vnconfig -u vnd1 2>/dev/null || true
vnconfig -u vnd2 2>/dev/null || true

echo "==> Working in $WORKDIR"
cd "$WORKDIR"

CACHE_DIR="$WORKDIR_BASE/.openbsd-btw-cache"
CACHED_IMG="$CACHE_DIR/install${RELNUM}.img"
mkdir -p "$CACHE_DIR"
if [ -f "$CACHED_IMG" ]; then
	echo "==> Using cached base image: $CACHED_IMG"
	cp "$CACHED_IMG" base.img
else
	echo "==> Fetching base install image"
	ftp -o base.img "$IMG_URL"
	cp base.img "$CACHED_IMG"
fi

echo "==> Building site set (site79.tgz) with install.site + firstboot.sh + onetime-account-setup.sh"
mkdir site_root
cp "$SCRIPT_DIR/install.site" site_root/install.site
cp "$SCRIPT_DIR/firstboot.sh" site_root/firstboot.sh
cp "$SCRIPT_DIR/onetime-account-setup.sh" site_root/onetime-account-setup.sh
chmod +x site_root/install.site site_root/firstboot.sh site_root/onetime-account-setup.sh
( cd site_root && tar -czf ../site${RELNUM}.tgz install.site firstboot.sh onetime-account-setup.sh )

echo "==> Mounting base image's OpenBSD partition (read-write)"
# Work directly on the final output file from here on - editing in
# place, no separate "rebuild" step at the end like the ISO approach.
cp base.img "$OUT_IMG"
vnconfig vnd1 "$OUT_IMG"
mkdir img_mnt
mount -t ffs /dev/vnd1a img_mnt

echo "==> Copying in site set"
cp site${RELNUM}.tgz img_mnt/${REL}/${ARCH}/site${RELNUM}.tgz

# /etc/boot.conf on this image explicitly says
# "set image /7.9/amd64/bsd.rd" (checked directly) - that's the one
# that matters, not the root-level /bsd.rd (a separate file, different
# inode, not a hardlink of this one despite the similar name).
echo "==> Injecting auto_install.conf into bsd.rd's embedded ramdisk"
cp img_mnt/${REL}/${ARCH}/bsd.rd bsd.rd.new
# Base tar has no -J - see build-iso.sh's own comment on this same
# gzip-detection dance.
was_gzipped=false
if file bsd.rd.new | grep -q gzip; then
	was_gzipped=true
	mv bsd.rd.new bsd.rd.new.gz
	gunzip bsd.rd.new.gz
fi
rdsetroot -x bsd.rd.new ramdisk.fs
vnconfig vnd2 ramdisk.fs
mkdir ramdisk_mnt
mount /dev/vnd2a ramdisk_mnt
cp "$SCRIPT_DIR/install-img.conf" ramdisk_mnt/auto_install.conf
umount ramdisk_mnt
vnconfig -u vnd2
rdsetroot bsd.rd.new ramdisk.fs
if $was_gzipped; then
	gzip bsd.rd.new
	mv bsd.rd.new.gz bsd.rd.new
fi
cp bsd.rd.new img_mnt/${REL}/${ARCH}/bsd.rd

echo "==> Unmounting"
umount img_mnt
vnconfig -u vnd1

echo "==> Done: $OUT_IMG"
echo "    Test it in a scratch VM before relying on it - and this one"
echo "    actually needs a *disk*-attached boot test, not just --cdrom,"
echo "    to mean anything (that's exactly what the ISO approach's bug"
echo "    slipped through undetected)."
