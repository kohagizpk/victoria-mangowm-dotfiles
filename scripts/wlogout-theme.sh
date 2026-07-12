#!/bin/bash

BASE="$HOME/.config/mango/kohagi_personal_configs/wlogout"
TARGET="$HOME/.config/wlogout"

mkdir -p "$TARGET"

cp -r "$BASE/"* "$TARGET/"

pkill wlogout 2>/dev/null

wlogout -l "$TARGET/layout"