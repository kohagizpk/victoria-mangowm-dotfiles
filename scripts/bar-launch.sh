#!/usr/bin/env bash
# Choose the bar explicitly; keep the original Waybar launcher as fallback.
set -eu
root="$HOME/.config/mango"
choice="$(cat "$root/local/bar-backend" 2>/dev/null || echo quickshell)"
if [[ "$choice" == waybar ]] || ! command -v quickshell >/dev/null; then
    # Waybar has no notification daemon or OSD of its own.
    pgrep -x swaync >/dev/null || GSK_RENDERER=cairo swaync >/dev/null 2>&1 &
    pgrep -x swayosd-server >/dev/null || swayosd-server >/dev/null 2>&1 &
    exec bash "$root/scripts/waybar-launch.sh"
fi
# Quickshell serves notifications and the OSD; free the D-Bus name for it.
pkill -x swaync 2>/dev/null || true
pkill -x swayosd-server 2>/dev/null || true
export QT_QUICK_CONTROLS_STYLE=Basic
# Software scene graph: ~100 MB less RAM than OpenGL for a mostly static bar.
export QT_QUICK_BACKEND=software
exec quickshell --no-duplicate -p "$root/quickshell" --no-color
