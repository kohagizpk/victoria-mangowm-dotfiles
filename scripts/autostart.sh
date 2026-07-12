#!/bin/sh

export XCURSOR_THEME=Animated-Mew-Cursor
export XCURSOR_SIZE=24
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_TYPE=wayland


dbus-update-activation-environment \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    XCURSOR_THEME \
    XCURSOR_SIZE

sleep 0.5

pgrep -x pipewire >/dev/null || pipewire &
pgrep -x wireplumber >/dev/null || wireplumber &
pgrep -x pipewire-pulse >/dev/null || pipewire-pulse &
sleep 0.5

pkill -x xdg-desktop-portal-wlr 2>/dev/null
pkill -x xdg-desktop-portal 2>/dev/null
sleep 0.3

/usr/lib/xdg-desktop-portal-wlr &
sleep 0.8
/usr/lib/xdg-desktop-portal --replace &
sleep 0.8

waybar -c ~/.config/mango/waybar/config.jsonc -s ~/.config/mango/waybar/style.css >/dev/null 2>&1 &
waypaper --restore &
kanshi &
swaync &
discord &
spotify &
helium-browser &
wl-clip-persist --clipboard regular --reconnect-tries 0 &
wl-paste --watch cliphist store &
swayosd-server &

echo "Xft.dpi: 140" | xrdb -merge