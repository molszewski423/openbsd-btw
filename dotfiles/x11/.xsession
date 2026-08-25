export PATH=$HOME/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R6/bin:/usr/local/bin:/usr/local/sbin
export ENV=$HOME/.kshrc
xrdb -merge ~/.Xdefaults
feh --bg-fill ~/Pictures/wallpaper.png
picom --backend xrender --xrender-sync-fence --no-use-damage -b
dunst &
WM=$(cat ~/.wm_choice 2>/dev/null)
case "$WM" in
  oxwm) exec ~/.local/bin/oxwm ;;
  *) urxvt & exec cwm ;;
esac
