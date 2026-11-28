#!/usr/bin/env bash
# Open a Victoria panel in the Quickshell bar; fall back to the GTK/Rofi tools on Waybar.
# Usage: victoria-open.sh settings [page] | control | shortcuts | setup | launcher | clipboard
set -u
root="$HOME/.config/mango"
ipc() { quickshell ipc -p "$root/quickshell" call bar "$@" >/dev/null 2>&1; }
case "${1:-settings}" in
    launcher)  ipc launcher || exec rofi -show drun -theme "$root/config/rofi/theme.rasi" ;;
    clipboard) ipc clipboard || exec python3 "$root/scripts/clipboard-picker.py" ;;
    control)   ipc controlCenter || exec python3 "$root/scripts/control-center.py" --gtk ;;
    shortcuts) ipc settings shortcuts || exec python3 "$root/scripts/victoria-controls.py" --shortcuts --gtk ;;
    setup)     ipc settings setup || exec python3 "$root/scripts/victoria-controls.py" --setup --gtk ;;
    settings)  ipc settings "${2:-appearance}" || exec python3 "$root/scripts/victoria-controls.py" --gtk ;;
    *) echo "usage: victoria-open.sh settings [page]|control|shortcuts|setup" >&2; exit 2 ;;
esac
