# openbsd-btw

A full OpenBSD 7.9 desktop setup: cwm + oxwm (dwm-style tiling WM, built from
source) as swappable window managers, fish shell, Tokyo Night theming
throughout, JetBrainsMono Nerd Font, and a small set of quality-of-life
scripts (`set-wm`, a `pkg_add` wrapper that auto-syncs the cwm app menu,
`sync-cwm-menu`).

## The full walkthrough

This started as an interactively-configured OpenBSD desktop (cwm/oxwm,
theming, fonts, package installs — all done by hand, one command at a
time, over a single long session) and was then turned into reusable
infrastructure in three deliberate phases:

1. **Capture the live state as dotfiles.** Rather than writing config
   from scratch, every file (`~/.cwmrc`, `~/.config/oxwm/config.lua`,
   `~/.xsession`, etc.) was pulled directly off the already-configured
   machine into `dotfiles/`, so what's in the repo is provably identical
   to what was actually running — no risk of "looks right" drift between
   documentation and reality.

2. **Codify the setup as an Ansible playbook.** Every manual step from
   the original session — package installs, building `oxwm` from source,
   installing fonts, generating the custom icon theme, wiring up
   `tailscaled` — became an idempotent role in `ansible/`. This is the
   layer that turns "I remember how I did this" into "anyone (including
   future me) can reproduce this exactly."

3. **Build a self-installing ISO.** `iso/` respins OpenBSD's official
   install media with an `autoinstall(8)` response file and an
   `/etc/rc.firsttime` hook (installed via a custom `siteXX.tgz` set) that
   fetches and runs the Ansible playbook automatically on first boot
   against a temporary bootstrap account, then hands off to a small
   graphical (X11) prompt that collects the real username/password and
   renames the account into place — no babysitting the installer beyond
   that one prompt, no manual `ansible-playbook` invocation after the fact,
   and no hardcoded account baked into the ISO, so the same image works for
   anyone who installs it. Account creation happens graphically rather than
   at the raw text console because raw console keyboard input proved
   unreliable in testing; X11's own input path didn't have that problem.

Each phase was tested against the actual mechanism it depends on before
moving to the next — the dotfiles were diffed against the live machine,
the Ansible playbook was dry-run and reviewed for idempotency, and the
ISO was genuinely booted (multiple times, wiping the scratch disk clean
each time) until a real fresh install completed unattended end-to-end.

## Layout

- `dotfiles/` — the actual config files, one subdirectory per concern
  (`cwm/`, `oxwm/`, `shell/`, `x11/`, `gtk/`, `rofi/`, `dunst/`, `picom/`,
  `bin/`). Each mirrors its target path under `$HOME`.
- `ansible/` — playbook that provisions a fresh OpenBSD install into this
  setup. Idempotent, safe to re-run.
- `iso/` — builds self-installing media that runs the Ansible playbook
  automatically on first boot via OpenBSD's `rc.firsttime` hook.
  `build-img.sh` (the real deliverable, `dd`'d to a USB stick) and
  `build-iso.sh` (a fast virtual-CD-ROM testing convenience only — see
  "Distribution format" below) share the same `install*.conf` /
  `firstboot.sh` / `onetime-account-setup.sh` payload.

## Switching window managers

`xenodm` (graphical login) is enabled automatically, and boots straight
into **oxwm** by default. To switch: `set-wm cwm` or `set-wm oxwm`, then
log out (or `doas rcctl restart xenodm`) to take effect.

## oxwm keybinds (Mod4 = Super key)

`Mod4+Return` terminal · `Mod4+Q` close window · `Mod4+Shift+Q` quit wm ·
`Mod4+Shift+R` reload config · `Mod4+Shift+/` show all keybinds ·
`Mod4+D` app launcher (rofi) · `Mod4+Shift+B` browser · `Mod4+1-9` switch tag

## Known VM-only fixes — intentionally NOT automated here

These three things were needed to get this exact setup working inside a
QEMU/libvirt VM. They are artifacts of virtualization, not of the OpenBSD
desktop config itself, so they're documented here rather than baked into
the Ansible playbook or ISO — applying them unconditionally on real
hardware would be wrong or unnecessary.

1. **Sound**: which emulated sound device actually works is *host QEMU
   build*-dependent, not a single universal fix. On one host, QEMU's
   default `ich6` (Intel HDA) wasn't detected by OpenBSD's `azalia` driver
   (`No codecs found`); switching to an emulated AC97 device via
   `virt-xml <vm> --edit --sound model=ac97` fixed it (works with
   OpenBSD's `auich` driver). On a different host (a Rocky Linux
   `qemu-kvm` build), AC97/ES1370 weren't compiled in as device models at
   all — only Intel HDA (`ich6`/`ich9`) — and `ich6` worked fine there once
   the QEMU **audio backend** was also explicitly set (`virt-xml --edit
   --audio type=pulseaudio`; a sound *device* alone doesn't imply a
   working audio backend — it defaults to silent `type='none'`). Check
   what your own QEMU build actually supports (`qemu-system-x86_64
   -device help | grep -i hda`) rather than assuming either fix applies.
   None of this is applicable to real hardware, which has a real sound
   chip that OpenBSD's `azalia(4)` detects automatically.

2. **Disk layout**: OpenBSD's installer auto-partitioning gave `/usr/local`
   only ~1.8GB on a 20GB virtual disk (most of the space went to an unused
   `/usr/obj`, which is only needed for building the OS/ports from source).
   Fixed by moving `/usr/local` onto the `/usr/obj` partition instead.
   Real hardware disk layouts will vary — check `df -h /usr/local` after
   any fresh install before assuming you need this; don't blindly repeat
   the partition swap without checking your actual layout first.

3. **Display resolution**: QEMU's virtual display (via SPICE/QXL) doesn't
   advertise real monitor EDID, so Xorg's `vesa` driver defaulted to
   1280x768 instead of the VM's actual configured resolution. Fixed with
   an `xorg.conf.d` snippet forcing 1920x1080 (see git history / the VM
   itself for the exact file if you need it for another VM). A real
   monitor advertises its own EDID correctly — not needed on real hardware.
   Applies to *any* scratch VM used to test this, not just the reference
   machine - a freshly-provisioned VM without this fix ran at the low
   resolution and masqueraded as an oxwm tiling/status-bar bug for a
   while before the actual cause (missing `xorg.conf.d`, not WM code) got
   traced down.

4. **Multi-disk boot order/enumeration**: testing the `.img` in a VM
   properly requires two virtual disks — the boot/source image plus a
   separate empty target disk to install onto, so autoinstall doesn't try
   to use the same disk as both the install target and the source of the
   site set (real hardware has this naturally: the USB stick plus an
   internal drive). But QEMU/firmware boot-order handling across two
   disks of different types has been genuinely flaky in a way real
   hardware wasn't: a legacy-BIOS (SeaBIOS) test hung indefinitely at
   `Loading......` regardless of which bus types were used, and a
   UEFI/OVMF test loaded the bootloader fine but then had OpenBSD's own
   `hd0`/`hd1` disk numbering not match which disk actually had the boot
   data, again regardless of bus-type swapping. Two separate real
   laptops (USB stick + internal drive both present) booted the exact
   same `.img` correctly in both legacy and UEFI mode with no such issue.
   Treat this as a QEMU/firmware testing artifact, not a sign the `.img`
   is broken — if a VM's multi-disk boot misbehaves this way, prefer
   trusting a real-hardware test over continuing to fight the VM.

## Distribution format: use the `.img`, not the `.iso`

**`iso/build-img.sh` is the real deliverable.** It builds
`openbsd-btw-X.Y.img` from OpenBSD's own `installXX.img` and is what
should actually be `dd`'d to a USB stick:

```
dd if=openbsd-btw-7.9.img of=/dev/rsdN bs=1M
```

This was learned the hard way: OpenBSD's own FAQ (openbsd.org/faq/faq4.html)
says plainly that `installXX.iso` is for optical media only and
`installXX.img` is the disk image meant for a USB flash drive — but this
project didn't take that at face value until it became a real, practical
failure. A respun `.iso` (`iso/build-iso.sh`, described below) booted
fine as a virtual CD-ROM in *every* VM test done during development, then
failed to boot at all on 3 different real laptops from 2 different USB
sticks written with `dd`. Only after actually trying `install79.img`
instead did real hardware boot correctly.

`build-img.sh` works by mounting the base `.img`'s existing OpenBSD (FFS)
partition read-write and copying in the site set plus a modified
`bsd.rd` **in place** — it never rebuilds the image from scratch the way
the ISO approach does, so the existing MBR partition table, EFI System
Partition, and boot blocks are never touched or reassigned. That
sidesteps an entire class of bug the `.iso` approach hit (below).

**Verified on real hardware, both boot modes:** a Lenovo Z50-75 installed
end-to-end via UEFI and reached a fully working oxwm desktop
(confirmed via `fastfetch`: correct theme, fonts, packages, window
manager). A second laptop (Acer) also installed successfully via UEFI
and is what surfaced the DHCP-timeout autoinstall bug documented below.
Legacy BIOS boot of the `.img` is also supported (same MBR/boot-block
mechanism OpenBSD ships) but hasn't yet been the *primary* path tested
on real hardware — UEFI has.

`iso/build-iso.sh` (the `.iso` builder) is kept only as a fast
virtual-CD-ROM testing convenience — e.g. attached via `--cdrom` in a
scratch VM, where a virtual optical drive is a faster dev loop than
writing a real USB stick every iteration. **Do not `dd` the `.iso` to a
USB stick** — it isn't structured for that and won't boot. Its own UEFI
boot catalog needed a real fix along the way: building it requires an
explicit `-e <eficdboot>` passed to `mkhybrid` (see `build-iso.sh`),
because the official install ISO's own boot catalog (copied in
unmodified) hardcodes an LBA for its EFI entry that's only valid for its
*original* file layout, and every respin reassigns fresh LBAs to every
file — without `-e`, the inherited EFI entry goes stale and points at
unrelated file data. Caught by actually booting a respun ISO under real
UEFI firmware (QEMU+OVMF) and watching it drop to a UEFI shell instead
of the installer.

## Known limitations

- **Wired ethernet is required for the actual install.** `install.conf`
  hasn't been tested against (and doesn't answer) a wireless-only
  network setup - `autoinstall(8)` needs an answer for every question it
  actually asks, and configuring Wi-Fi means additional, genuinely
  per-deployment questions (SSID, WPA passphrase) that can't be baked
  into a public response file the same way hostname/timezone can.
  `firstboot.sh` also needs real network access of its own (cloning the
  Ansible repo, package installs, font/Zig downloads), so this isn't
  optional even after the base OS is on disk. On hardware with no
  built-in ethernet (common on modern laptops), use a USB-to-ethernet
  adapter for the install; Wi-Fi can be configured normally afterward
  once at a working desktop.

- **A slow DHCP response can hard-fail the whole autoinstall if
  unanswered.** `autoinstall(8)` has no interactive fallback for any
  question it actually asks — every question needs a scripted answer, or
  it aborts with "Question has no answer in the response file" and drops
  back to the Install/Upgrade/Autoinstall/Shell menu. One follow-up
  question, "Default IPv4 route?", only appears when DHCP doesn't respond
  within the installer's own ~30-second window (a switch without
  portfast/spanning-tree fast-forwarding is a common real-world cause,
  and this was hit on real hardware, not just theorized) and — unlike the
  interface/address questions before it — has no built-in default. Both
  `install.conf` and `install-img.conf` now answer
  `Default IPv4 route = none`, which lets the base install complete even
  without a route; if you hit this anyway (e.g. on an even slower
  network), drop to the installer's shell, bring the interface up
  manually (`ifconfig <if> up; dhclient <if>`), then return to the menu
  and choose Autoinstall again.

## Troubleshooting a USB write that "succeeded" but won't boot

If a `dd` write reports success and a checksum read-back even matches,
but the stick still won't boot on real hardware, verify the target
device node is actually real before suspecting the image: run
`stat /dev/sdX` and confirm it says `block special file`, not
`regular file`. Some environments (containers/sandboxes without a udev
daemon creating device nodes for hot-plugged USB storage) will silently
let `dd` create a **plain file** at `/dev/sdX` if no real device node
exists there yet — every subsequent checksum then "verifies" correctly
because it's just comparing that fake file to itself, never touching the
physical stick at all. If `stat` shows a regular file, find the real
kernel device (`grep -w sdX /proc/partitions` for its major/minor), then
`rm` the fake file and `mknod /dev/sdX b <major> <minor>` to restore the
real block device node before writing again.

## oxwm build notes

`tonybanters/oxwm` needs Zig 0.16+ (its `master` branch), but OpenBSD's
packaged Zig is 0.15.x. The Ansible `oxwm-build` role downloads the
official Zig 0.16.0 OpenBSD prebuilt binary directly from
`ziglang.org/download/0.16.0/zig-x86_64-openbsd-0.16.0.tar.xz` rather than
relying on the package repo.

oxwm's own `build.zig` also doesn't link everything OpenBSD's static
X11/font libraries transitively need (`libxcb`, `libXau`, `libXdmcp`,
`libXext`, `libXrender`, `libexpat`, `libpng`, `libz`), and its default
`use_lld = false` produces a binary missing the `.note.openbsd.ident`
segment OpenBSD's kernel requires to exec anything directly (fails with
"Exec format error" otherwise). The playbook installs a patched
`build.zig` with the correct linking and `use_lld = true`.

**The clone is pinned to a specific commit, not the default branch.**
The original hand-built reference machine's oxwm was built from a commit
dated 2026-07-08 and works correctly. A fresh clone of whatever was
newest as of this testing hit a real, reproducible bug not present on
the reference machine: the status bar's height wasn't subtracted from
tiled window sizes (the bottom of every tiled window, including the live
shell prompt, rendered just off-screen), plus the bar's visibility not
reliably toggling back on. Checked upstream GitHub issues and recent
commit history first — not a known or already-fixed problem, and there's
real churn in that range (monitor-handling rewrites, a new dwindle
layout, systray) that could plausibly have introduced a regression.
Pinned to the known-good commit instead of chasing a moving target;
worth periodically checking if a newer commit resolves it and lifting
the pin.

## Why this project, specifically

This wasn't chosen as a generic "learn Ansible" exercise — it's real
platform-engineering work, just scoped to a personal machine instead of
a fleet, and OpenBSD instead of the usual Linux/cloud stack most job
postings name-check. The specific skills exercised map directly:

- **Infrastructure as code, not tribal knowledge.** The whole point of
  `ansible/` is that a from-scratch environment can be reproduced by
  running a playbook instead of by someone remembering (or re-Googling)
  forty individual steps. That's the entire premise of IaC, on any stack.

- **Golden-image / immutable provisioning.** `iso/` is a small-scale
  version of what platform teams do with Packer images, cloud-init, or
  PXE/kickstart pipelines: bake a base image, hand it a declarative
  answer file, let it provision itself unattended. `autoinstall(8)` +
  `rc.firsttime` here plays the same role kickstart/preseed/cloud-init
  plays elsewhere.

- **Debugging build and packaging systems, not just app code.** Getting
  `oxwm` to actually run meant tracing a linker failure down to a missing
  ELF section (`.note.openbsd.ident`) that the kernel's exec() path
  checks for, and separately reasoning about *why* `-fuse-ld=lld` vs the
  system linker changes what gets emitted. That's the same category of
  skill as debugging a broken container base image or a cross-compiled
  binary that "works on my machine."

- **Treating infrastructure changes like code changes.** Every fix in
  this repo's git history exists because something was actually run and
  actually failed first — wrong package names, a `set -e` script that
  silently ate its own error handling, a hardcoded `TMPDIR` that doas
  quietly stripped, boot-order/media-attachment state that didn't
  survive a VM restart. None of that was caught by reasoning about the
  code in the abstract; it came from a real test-fix-retest loop against
  disposable scratch VMs — the same discipline as running a change
  through a CI environment before it touches anything real.

- **Operating close to the OS/kernel boundary.** Manipulating a bootable
  ISO's embedded ramdisk (`vnd(4)`, `rdsetroot(8)`), understanding disk
  partitioning trade-offs, and diagnosing a device driver mismatch
  (QEMU's emulated sound/display hardware vs. what a guest OS actually
  detects) are the kind of systems fundamentals that separate "can run
  the tools" from "understands what the tools are actually doing."

- **Security-conscious defaults, not an afterthought.** `install.conf`
  ships as a template with explicit `CHANGEME` placeholders rather than
  a real (or fake-but-plausible) credential; passwords are documented as
  bcrypt hashes generated locally, never committed in the clear; and the
  repo's public/private visibility was a deliberate decision (made once
  it was confirmed nothing sensitive lived in it) rather than a default
  left unexamined.

- **Knowing when automation should say no.** The VM-only fixes
  documented above were deliberately *excluded* from the Ansible role
  rather than blindly encoded — because they're artifacts of the
  specific virtualization environment, not the target system, and
  automating them unconditionally would silently do the wrong thing on
  real hardware. Recognizing what *shouldn't* be automated is as much a
  platform-engineering skill as automating what should.
