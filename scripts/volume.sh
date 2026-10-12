#!/bin/sh
# Volume com OSD do swayosd. Uso: volume.sh up|down|mute
case "$1" in
    up)   swayosd-client --output-volume 5 ;;
    down) swayosd-client --output-volume -5 ;;
    mute) swayosd-client --output-volume mute-toggle ;;
esac
