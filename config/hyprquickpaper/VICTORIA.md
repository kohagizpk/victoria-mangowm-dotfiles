# hyprquickpaper (vendored)

Upstream: https://github.com/ujjalsigdel/hyprquickpaper (MIT, see LICENSE), commit 7e6c702.

Victoria changes:
- `config.json`: wallpapers in `~/Pictures/Wallpapers`, awww with a grow transition,
  and a post-apply hook that runs `scripts/wallust-reload.sh` so every color
  (Mango, bar, notifications, Rofi, Fish, wlogout, Spotifast) follows the pick.
  `border_color` is rewritten by `scripts/theme.py` from the wallust palette.
- Per-monitor: `scripts/wallpaper-picker.sh` exports `VICTORIA_WALLPAPER_OUTPUT` (the focused
  monitor when the picker opens); `custom_command` passes it to `awww img --outputs`, and
  `common.sh` uses it for video wallpapers (falling back to asking Mango via `mmsg`).
- `install.sh` removed: dependencies are handled by the Victoria installer.

Open it with `scripts/wallpaper-picker.sh` (Super + F), or from the Control Center.
