#!/bin/sh
# Brilho com OSD do swayosd. Uso: brightness.sh up|down
case "$1" in
    up)   swayosd-client --brightness +2 ;;
    down) swayosd-client --brightness -2 ;;
esac
