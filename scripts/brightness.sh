#!/bin/sh
# Brightness keys. Usage: brightness.sh up|down
if pgrep -x swayosd-server >/dev/null; then
    case "$1" in
        up)   swayosd-client --brightness +2 ;;
        down) swayosd-client --brightness -2 ;;
    esac
    exit 0
fi
command -v brightnessctl >/dev/null || exit 0
case "$1" in
    up)   brightnessctl -q set 2%+ ;;
    down) brightnessctl -q set 2%- ;;
    *)    exit 2 ;;
esac
# Show the Quickshell OSD with the new level (0..1).
level=$(brightnessctl -m | awk -F, '{gsub("%","",$4); print $4/100}')
quickshell ipc -p "$HOME/.config/mango/quickshell" call bar osd brightness "$level" >/dev/null 2>&1
