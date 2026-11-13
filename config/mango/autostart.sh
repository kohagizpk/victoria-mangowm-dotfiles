#!/bin/sh
# ~/.config/mango/autostart.sh — chamado pelo exec_once do config.conf

# ---------- Ambiente ----------
export LANGUAGE=en
export LC_MESSAGES=C.UTF-8
export LC_TIME=C.UTF-8
export GTK_THEME=Materia-dark-compact
export QT_STYLE_OVERRIDE=kvantum
export XCURSOR_THEME=Animated-Mew-Cursor
export XCURSOR_SIZE=24
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SESSION_TYPE=wayland

dbus-update-activation-environment \
    LANGUAGE LC_MESSAGES LC_TIME \
    GTK_THEME \
    QT_STYLE_OVERRIDE \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    XCURSOR_THEME \
    XCURSOR_SIZE


# ---------- Áudio ----------
pgrep -x pipewire >/dev/null || pipewire &
pgrep -x wireplumber >/dev/null || wireplumber &
pgrep -x pipewire-pulse >/dev/null || pipewire-pulse &

# ---------- Desktop portals ----------
# D-Bus activates portals on demand with the environment imported above.
# Do not kill/restart them or block login with fixed sleeps.

# ---------- Script pessoal (opcional) ----------
[ -f "$HOME/.local/bin/fix-volume.sh" ] && bash "$HOME/.local/bin/fix-volume.sh" &

# ---------- Wallpaper (awww + waypaper; o wallust roda via post_command) ----------
(
    bash "$HOME/.config/mango/scripts/wallpaper-start.sh"
    bash "$HOME/.config/mango/scripts/waybar-launch.sh"
) &

# ---------- Barra, notificações e OSD ----------
swaync &
swayosd-server &

# ---------- Clipboard ----------
wl-clip-persist --clipboard regular --reconnect-tries 0 >/dev/null 2>&1 &
wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
wl-paste --type image --watch cliphist store >/dev/null 2>&1 &

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
# Scale 1 is the portable default; customize DPI if needed.
echo "Xft.dpi: 96" | xrdb -merge

# ---------- Apps (chosen by install.sh) ----------
if [ -r "$HOME/.config/mango/apps.conf" ]; then
    . "$HOME/.config/mango/apps.conf"
    [ "${START_DISCORD:-0}" = 1 ] && discord --ozone-platform=wayland &
    [ "${START_SPOTIFY:-0}" = 1 ] && spotify &
    if [ "${START_BROWSER:-0}" = 1 ]; then
        case "${BROWSER_COMMAND:-}" in
            helium-browser|firefox|brave) "$BROWSER_COMMAND" & ;;
        esac
    fi
fi
# Spicetify is intentionally applied manually after Spotify updates.

# Personal startup commands stay outside managed files.
[ ! -r "$HOME/.config/mango/local/autostart.sh" ] || sh "$HOME/.config/mango/local/autostart.sh" &
