# openbsd-btw

A full OpenBSD 7.9 desktop setup: cwm + oxwm (dwm-style tiling WM, built from
source) as swappable window managers, fish shell, Tokyo Night theming
throughout, JetBrainsMono Nerd Font, and a small set of quality-of-life
scripts (`set-wm`, a `pkg_add` wrapper that auto-syncs the cwm app menu,
`sync-cwm-menu`).

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
