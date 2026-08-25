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
- `iso/` — builds a custom install ISO that runs the Ansible playbook
  automatically on first boot via OpenBSD's `rc.firsttime` hook.

## Switching window managers

Once installed: `set-wm cwm` or `set-wm oxwm`, then log out (or
`doas rcctl restart xenodm`) to switch. Default is cwm.

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

1. **Sound**: QEMU's default `ich6` (Intel HDA) emulated sound device
   wasn't detected by OpenBSD's `azalia` driver (`No codecs found`).
   Fixed on the **host** side via `virt-xml <vm> --edit --sound model=ac97`
   — an emulated AC97 device works reliably with OpenBSD's `auich` driver.
   Not applicable to real hardware, which has a real sound chip.

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

- **Knowing when automation should say no.** The three VM-only fixes
  documented above were deliberately *excluded* from the Ansible role
  rather than blindly encoded — because they're artifacts of the
  specific virtualization environment, not the target system, and
  automating them unconditionally would silently do the wrong thing on
  real hardware. Recognizing what *shouldn't* be automated is as much a
  platform-engineering skill as automating what should.
