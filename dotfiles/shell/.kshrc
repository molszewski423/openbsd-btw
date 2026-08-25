case $- in
  *i*) ;;
  *) return ;;
esac

clear
fastfetch

cat <<TIPS

Tips:
  set-wm cwm | oxwm   switch default window manager (takes effect next login)
  doas rcctl restart xenodm   restart the X session (drops to login screen)
  pkg_add <name>      install a package (no need for "doas" -- wrapper handles it,
                       and syncs the cwm app menu automatically afterward)
  sync-cwm-menu       manually resync the cwm app menu from installed apps
  oxwm: Mod4+Return terminal, Mod4+Q close, Mod4+Shift+Q quit wm,
        Mod4+Shift+R reload config, Mod4+Shift+/ show all keybinds

TIPS
