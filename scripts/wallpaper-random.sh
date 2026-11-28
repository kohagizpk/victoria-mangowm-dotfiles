#!/usr/bin/env bash
# Apply a random wallpaper from ~/Pictures/Wallpapers to every monitor (and recolor).
# Used by the automatic rotation in the bar; safe to bind to a key too.
set -u
current="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/victoria/last-wallpaper" 2>/dev/null)"
mapfile -t images < <(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) ! -path "$current")
(( ${#images[@]} )) || exit 0
unset VICTORIA_WALLPAPER_OUTPUT
exec bash "$HOME/.config/mango/hyprquickpaper/commands.sh" "${images[RANDOM % ${#images[@]}]}"
