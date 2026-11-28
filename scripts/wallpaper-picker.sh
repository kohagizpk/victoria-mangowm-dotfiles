#!/usr/bin/env bash
# Toggle the hyprquickpaper wallpaper picker (Super + F, Control Center).
# Wallpapers live in ~/Pictures/Wallpapers; drop images there and they show up.
#
# The picker opens on the focused monitor and applies the wallpaper only there,
# so each monitor can get its own image (open it again on the other one).
dir="$HOME/.config/mango/hyprquickpaper"
mkdir -p "$HOME/Pictures/Wallpapers"

# Remember the monitor the picker was opened on; commands.sh hands it to awww.
output="$(mmsg get all-monitors 2>/dev/null | jq -r '.monitors[] | select(.active == true) | .name' 2>/dev/null | head -n1)"
export VICTORIA_WALLPAPER_OUTPUT="$output"

# Launched from the bar, we would inherit its software renderer, under which the
# picker's graphical effects draw nothing. Use the normal GPU renderer.
unset QT_QUICK_BACKEND QT_QUICK_CONTROLS_STYLE

exec bash "$dir/toggle.sh" "$dir/shell.qml"
