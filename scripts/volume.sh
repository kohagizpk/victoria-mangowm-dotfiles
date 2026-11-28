#!/bin/sh
# Volume keys. Usage: volume.sh up|down|mute
# With the Quickshell bar the OSD reacts to PipeWire by itself; swayosd is the Waybar fallback.
if pgrep -x swayosd-server >/dev/null; then
    case "$1" in
        up)   swayosd-client --output-volume 5 ;;
        down) swayosd-client --output-volume -5 ;;
        mute) swayosd-client --output-volume mute-toggle ;;
    esac
else
    case "$1" in
        up)   wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
        down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac
fi
