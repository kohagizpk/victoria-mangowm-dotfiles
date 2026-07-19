#!/bin/bash

CONFIG_SRC="$HOME/.config/mango/waybar/config.jsonc"
STYLE_SRC="$HOME/.config/mango/waybar/style.css"
CONFIG_RUN="/tmp/waybar-config-$USER.jsonc"

cp "$CONFIG_SRC" "$CONFIG_RUN"

has_battery=false
for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] && has_battery=true && break
done

if $has_battery; then
    # injeta "battery" logo depois de "temperature" no modules-right
    sed -i 's/"temperature",/"temperature",\n        "battery",/' "$CONFIG_RUN"
fi

exec waybar -c "$CONFIG_RUN" -s "$STYLE_SRC"
