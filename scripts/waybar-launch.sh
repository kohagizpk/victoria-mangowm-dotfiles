#!/usr/bin/env bash
# One supervisor per user. flock avoids stale PID reuse and concurrent launches.
set -u
CONFIG_SRC="$HOME/.config/mango/waybar/config.jsonc"
STYLE_SRC="$HOME/.config/mango/waybar/style.css"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${XDG_RUNTIME_DIR:-$CACHE_DIR}/victoria-waybar"
umask 077
mkdir -p "$CACHE_DIR" "$STATE_DIR" || exit 1
LOG="$CACHE_DIR/waybar.log"
exec 9>"$STATE_DIR/launcher.lock"
if ! flock -n 9; then
    # Waybar's SIGUSR2 reloads its configuration/style without another supervisor.
    pkill -USR2 -u "$(id -u)" -x waybar 2>/dev/null || true
    exit 0
fi
CONFIG_RUN="$(mktemp "$STATE_DIR/config.XXXXXXXX.jsonc")" || exit 1
child=""
cleanup() {
    if [[ -n "$child" ]]; then
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    rm -f "$CONFIG_RUN"
}
trap cleanup EXIT
trap 'exit 0' INT TERM
cp "$CONFIG_SRC" "$CONFIG_RUN" || exit 1
for battery in /sys/class/power_supply/BAT*; do
    if [[ -d "$battery" ]]; then
        sed -i 's/"temperature",/"temperature",\n        "battery",/' "$CONFIG_RUN"
        break
    fi
done
for ((attempt=1; attempt<=5; attempt++)); do
    start=$SECONDS
    # The child must not inherit the supervisor's lock.
    waybar -c "$CONFIG_RUN" -s "$STYLE_SRC" 9>&- >>"$LOG" 2>&1 &
    child=$!
    wait "$child"
    code=$?
    child=""
    elapsed=$((SECONDS - start))
    printf '%s -- waybar exit=%s after %ss, attempt=%s\n' "$(date '+%F %T')" "$code" "$elapsed" "$attempt" >>"$LOG"
    [[ "$code" -eq 0 || "$code" -ge 128 || "$elapsed" -ge 5 ]] && break
    [[ "$attempt" -lt 5 ]] && sleep 1
done
exit "$code"
