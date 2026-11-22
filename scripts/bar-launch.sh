#!/usr/bin/env bash
# Choose the bar explicitly; keep the original Waybar launcher as fallback.
set -eu
root="$HOME/.config/mango"
choice="$(cat "$root/local/bar-backend" 2>/dev/null || echo quickshell)"
if [[ "$choice" == waybar ]] || ! command -v quickshell >/dev/null; then
    exec bash "$root/scripts/waybar-launch.sh"
fi
export QT_QUICK_CONTROLS_STYLE=Basic
exec quickshell --no-duplicate -p "$root/quickshell" --no-color
