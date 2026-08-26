export PATH=$HOME/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin:/usr/local/bin:/usr/local/sbin
export ENV=$HOME/.kshrc
xrdb -merge ~/.Xdefaults

# xenodm spawns xconsole by default for whichever display is set up as
# "the console" (see /etc/X11/xenodm/xenodm-config's DisplayManager._0.*
# directives) - shows up as a stray window on login regardless of window
# manager (confirmed happening under cwm too, not an oxwm-specific bug).
# Not useful for a desktop distro; killed here rather than touching the
# system-wide xenodm config.
pkill xconsole 2>/dev/null
feh --bg-fill ~/Pictures/wallpaper.png
picom --backend xrender --xrender-sync-fence --no-use-damage -b
dunst &
WM=$(cat ~/.wm_choice 2>/dev/null)
case "$WM" in
  oxwm) exec ~/.local/bin/oxwm ;;
  *) urxvt & exec cwm ;;
esac
