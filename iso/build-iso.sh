#!/bin/sh
# Respins the base OpenBSD install ISO into a self-provisioning one.
#
# MUST run on an OpenBSD machine (needs vnd(4)/vnconfig to mount bsd.rd's
# embedded ramdisk filesystem - not available on Linux). Run this from
# openbsd-btw itself, or any other OpenBSD box.
#
# Tested end-to-end 2026-08-25: respin, unattended autoinstall, the
# rc.firsttime hook, and firstboot.sh's fetch/provision all confirmed
# working against a real install. Needs root (mounting the vnd device).
set -e

REL=7.9
RELNUM=$(echo "$REL" | tr -d .)   # "7.9" -> "79", for filenames like site79.tgz.
                                  # The directory on the ISO keeps the dot
                                  # ("7.9/amd64/...") - use $REL for that,
                                  # $RELNUM only for version-in-filename.
ARCH=amd64
# Capture absolute paths BEFORE we cd into the scratch workdir below -
# "$(dirname "$0")" and "./..." are only valid relative to the directory
# we're in *right now*, and everything after this point runs from deep
# inside a temp dir that gets deleted on exit. Getting this wrong means
# either "install.site: No such file" (looked for it in the wrong place)
# or silently deleting the finished ISO along with the scratch dir
# (wrote it to the wrong place) - both happened testing this.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ORIG_DIR=$(pwd)

# /tmp is usually too small for a full ISO respin, and since this needs to
# run under doas (root), a TMPDIR=... env var prefix won't work either -
# doas strips environment variables by default, it doesn't pass them
# through to the target command. Pass the scratch dir as an argument
# instead (tilde-expanded by your shell before doas ever runs), e.g.:
#   doas ./build-iso.sh ~/iso-build-tmp
WORKDIR_BASE="${1:-/tmp}"
mkdir -p "$WORKDIR_BASE"
WORKDIR=$(mktemp -d "$WORKDIR_BASE/openbsd-btw-iso.XXXXXXXX")
ISO_URL="https://cdn.openbsd.org/pub/OpenBSD/${REL}/${ARCH}/install${RELNUM}.iso"
OUT_ISO="$ORIG_DIR/openbsd-btw-${REL}.iso"

# set -e means a mid-script failure skips the cleanup at the bottom of this
# file entirely, leaving mounts/vnd devices/scratch dirs stuck for the next
# run (exactly what happened testing this). Trap EXIT instead so cleanup
# always runs, success or failure - best-effort, errors ignored since half
# these may already be torn down depending on how far the script got.
cleanup() {
	exit_code=$?
	umount "$WORKDIR/iso_mnt" 2>/dev/null || true
	umount "$WORKDIR/ramdisk_mnt" 2>/dev/null || true
	vnconfig -u vnd1 2>/dev/null || true
	vnconfig -u vnd2 2>/dev/null || true
	cd /
	# Only remove the workdir on success - on failure, leave it so the
	# intermediate files (bsd.rd.new, ramdisk.fs, etc.) can be inspected
	# instead of forcing a full re-download to debug.
	if [ "$exit_code" -eq 0 ]; then
		rm -rf "$WORKDIR"
	else
		echo "==> Failed - scratch dir left at $WORKDIR for inspection"
	fi
}
trap cleanup EXIT

# In case a previous crashed run left these configured/mounted from a
# different $WORKDIR, clear them defensively before we start.
umount /dev/vnd1c 2>/dev/null || true
umount /dev/vnd2a 2>/dev/null || true
vnconfig -u vnd1 2>/dev/null || true
vnconfig -u vnd2 2>/dev/null || true

echo "==> Working in $WORKDIR"
cd "$WORKDIR"

# Cached alongside WORKDIR_BASE rather than under $HOME: this runs under
# doas, which resets HOME to root's (/root) - and root's home is on the
# small base OS partition, not wherever the caller pointed WORKDIR_BASE for
# actually having room to build (hit a real disk-full death from this
# exact mistake, caching to /root on a 430M partition).
CACHE_DIR="$WORKDIR_BASE/.openbsd-btw-cache"
CACHED_ISO="$CACHE_DIR/install${RELNUM}.iso"
mkdir -p "$CACHE_DIR"
if [ -f "$CACHED_ISO" ]; then
	echo "==> Using cached base ISO: $CACHED_ISO"
	cp "$CACHED_ISO" base.iso
else
	echo "==> Fetching base install ISO"
	ftp -o base.iso "$ISO_URL"
	cp base.iso "$CACHED_ISO"
fi

echo "==> Extracting ISO contents"
mkdir iso_root
vnconfig vnd1 base.iso
mount -t cd9660 -o ro /dev/vnd1c iso_mnt 2>/dev/null || { mkdir iso_mnt; mount -t cd9660 -o ro /dev/vnd1c iso_mnt; }
cp -Rp iso_mnt/* iso_root/
umount iso_mnt
vnconfig -u vnd1

echo "==> Building site set (site79.tgz) with install.site + firstboot.sh + onetime-account-setup.sh"
mkdir site_root
cp "$SCRIPT_DIR/install.site" site_root/install.site
cp "$SCRIPT_DIR/firstboot.sh" site_root/firstboot.sh
cp "$SCRIPT_DIR/onetime-account-setup.sh" site_root/onetime-account-setup.sh
chmod +x site_root/install.site site_root/firstboot.sh site_root/onetime-account-setup.sh
# All three go in at the tar root so they land at /firstboot.sh and
# /onetime-account-setup.sh on the installed system - install.site (also in
# this same tarball) references firstboot.sh directly, and firstboot.sh in
# turn references onetime-account-setup.sh directly, no network fetch
# needed to get any of this onto the machine.
( cd site_root && tar -czf ../iso_root/${REL}/${ARCH}/site${RELNUM}.tgz install.site firstboot.sh onetime-account-setup.sh )

echo "==> Injecting auto_install.conf into bsd.rd's embedded ramdisk"
cp iso_root/${REL}/${ARCH}/bsd.rd bsd.rd.orig
cp bsd.rd.orig bsd.rd.new
# bsd.rd on the install media is gzip-compressed, not a raw ELF -
# rdsetroot needs the decompressed kernel to find/replace the embedded
# rd(4) filesystem image, so gunzip first and regzip after (bsd.rd is
# still bootable in either compressed or plain form, but match how it
# shipped, since other tooling on the image may assume it's compressed).
was_gzipped=false
if file bsd.rd.new | grep -q gzip; then
	was_gzipped=true
	mv bsd.rd.new bsd.rd.new.gz
	gunzip bsd.rd.new.gz
fi
rdsetroot -x bsd.rd.new ramdisk.fs
vnconfig vnd2 ramdisk.fs
mount /dev/vnd2a ramdisk_mnt 2>/dev/null || { mkdir ramdisk_mnt; mount /dev/vnd2a ramdisk_mnt; }
cp "$SCRIPT_DIR/install.conf" ramdisk_mnt/auto_install.conf
umount ramdisk_mnt
vnconfig -u vnd2
rdsetroot bsd.rd.new ramdisk.fs
if $was_gzipped; then
	gzip bsd.rd.new
	mv bsd.rd.new.gz bsd.rd.new
fi
cp bsd.rd.new iso_root/${REL}/${ARCH}/bsd.rd

echo "==> Rebuilding hybrid ISO"
mkhybrid -a -R -T -L -l -d -D -N \
	-o "$OUT_ISO" \
	-b ${REL}/${ARCH}/cdbr \
	-c ${REL}/${ARCH}/boot.catalog \
	iso_root

echo "==> Done: $OUT_ISO"
echo "    Test it in a scratch VM before relying on it."
