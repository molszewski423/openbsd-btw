if status is-interactive
    clear
    fastfetch

    echo ""
    echo "Tips:"
    echo "  set-wm cwm | oxwm   switch default window manager (takes effect next login)"
    echo "  doas rcctl restart xenodm   restart the X session (drops to login screen)"
    echo "  pkg_add <name>      install a package (no need for \"doas\" -- wrapper handles it,"
    echo "                       and syncs the cwm app menu automatically afterward)"
    echo "  sync-cwm-menu       manually resync the cwm app menu from installed apps"
    echo "  oxwm: Mod4+Return terminal, Mod4+Q close, Mod4+Shift+Q quit wm,"
    echo "        Mod4+Shift+R reload config, Mod4+Shift+/ show all keybinds"
    echo ""
end
