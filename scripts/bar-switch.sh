#!/usr/bin/env bash
set -eu
root="$HOME/.config/mango"
case "${1:-}" in quickshell|waybar) ;; *) echo 'Usage: bar-switch.sh quickshell|waybar' >&2; exit 2;; esac
# Check the target binary before removing the currently working bar.
if [[ "$1" == waybar ]]; then
    waybar --version >/dev/null || { echo 'Waybar cannot start; repair its packages first. Current bar preserved.' >&2; exit 1; }
else
    quickshell --version >/dev/null
fi
mkdir -p "$root/local" "$HOME/.cache"
printf '%s\n' "$1" > "$root/local/bar-backend"
quickshell -p "$root/quickshell" kill 2>/dev/null || true
pkill -u "$(id -u)" -x waybar || true
# Let the Waybar supervisor release its lock before starting another bar.
for _ in {1..20}; do
    pgrep -u "$(id -u)" -x waybar >/dev/null || break
    sleep 0.1
done
if [[ "$1" == quickshell ]]; then
    pkill -x swaync 2>/dev/null || true
    pkill -x dunst 2>/dev/null || true
    pkill -x mako 2>/dev/null || true
    pkill -x swayosd-server 2>/dev/null || true
    QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software quickshell --no-duplicate -p "$root/quickshell" -d --no-color
else
    pgrep -x swaync >/dev/null || (GSK_RENDERER=cairo setsid -f swaync >/dev/null 2>&1)
    pgrep -x swayosd-server >/dev/null || (setsid -f swayosd-server >/dev/null 2>&1)
    python3 - <<'PYLAUNCH'
from pathlib import Path
import subprocess
home = Path.home()
with (home / '.cache/victoria-bar.log').open('ab') as log:
    subprocess.Popen(['bash', str(home / '.config/mango/scripts/waybar-launch.sh')],
                     stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
PYLAUNCH
fi
