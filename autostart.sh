#!/bin/sh
# ~/.config/mango/autostart.sh — chamado pelo exec_once do config.conf

# ---------- Ambiente ----------
export QT_QPA_PLATFORMTHEME=gtk3
export XCURSOR_THEME=Samuel-Noticias-Cursor
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

# ---------- Áudio ----------
pgrep -x pipewire >/dev/null || pipewire &
pgrep -x wireplumber >/dev/null || wireplumber &
pgrep -x pipewire-pulse >/dev/null || pipewire-pulse &
sleep 0.5

# ---------- Portais (screenshare, file picker...) ----------
pkill -x xdg-desktop-portal-wlr 2>/dev/null
pkill -x xdg-desktop-portal 2>/dev/null
sleep 0.3

/usr/lib/xdg-desktop-portal-wlr >/dev/null 2>&1 &
sleep 0.8
/usr/lib/xdg-desktop-portal --replace >/dev/null 2>&1 &
sleep 0.8

# ---------- Script pessoal (opcional) ----------
[ -f "$HOME/.local/bin/fix-volume.sh" ] && bash "$HOME/.local/bin/fix-volume.sh"

# ---------- Wallpaper (awww + waypaper; o wallust roda via post_command) ----------
awww-daemon &
sleep 0.5
waypaper --restore &
sleep 1

# ---------- Barra, notificações e OSD ----------
bash ~/.config/mango/scripts/waybar-launch.sh &
swaync &
swayosd-server &

# ---------- Clipboard ----------
wl-clip-persist --clipboard regular --reconnect-tries 0 >/dev/null 2>&1 &
wl-paste --watch cliphist store >/dev/null 2>&1 &

# ---------- Serviços auxiliares ----------
# autenticação gráfica (pkexec etc.)
if command -v xfce-polkit >/dev/null 2>&1; then
    pgrep -x xfce-polkit >/dev/null || xfce-polkit >/dev/null 2>&1 &
elif [ -x /usr/lib/xfce-polkit/xfce-polkit ]; then
    pgrep -f xfce-polkit >/dev/null || /usr/lib/xfce-polkit/xfce-polkit >/dev/null 2>&1 &
fi
# não suspende enquanto toca áudio
sway-audio-idle-inhibit >/dev/null 2>&1 &

# ---------- DPI do XWayland ----------
echo "Xft.dpi: 140" | xrdb -merge

# ---------- Apps ----------
discord --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer --ozone-platform=wayland &
spicetify restore backup apply &
spotify &
helium-browser &
