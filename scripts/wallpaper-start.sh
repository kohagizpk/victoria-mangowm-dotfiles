#!/usr/bin/env bash
# Wait for the wallpaper daemon, restore Waypaper, then synchronize the palette.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! awww query >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
fi
ready=0
for ((attempt=0; attempt<30; attempt++)); do
    if awww query >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.1
done
[[ "$ready" -eq 1 ]] || { echo 'awww did not become ready' >&2; exit 1; }
waypaper --restore || true
if ! python3 "$SCRIPT_DIR/theme.py" active-wallpaper >/dev/null; then
    wallpaper="$(python3 "$SCRIPT_DIR/theme.py" wallpaper)"
    awww img "$wallpaper"
fi
bash "$SCRIPT_DIR/wallust-reload.sh"
