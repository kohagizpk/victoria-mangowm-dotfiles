#!/usr/bin/env bash
# Screen recording with wf-recorder: record.sh start region|screen [audio] | stop | toggle | status
# The bar watches $XDG_RUNTIME_DIR/victoria-recording (start time + file) to show a timer.
set -u
state="${XDG_RUNTIME_DIR:-/tmp}/victoria-recording"
dir="$HOME/Videos/Recordings"
bar() { quickshell ipc -p "$HOME/.config/mango/quickshell" call bar recording "$1" >/dev/null 2>&1 || true; }
running() { [[ -f "$state" ]] && kill -0 "$(sed -n 1p "$state")" 2>/dev/null; }
stop() {
    running || { rm -f "$state"; return 0; }
    pid="$(sed -n 1p "$state")"; file="$(sed -n 3p "$state")"
    kill -INT "$pid"
    for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    rm -f "$state"
    bar false
    notify-send -a Recorder "Recording saved" "${file/#$HOME/\~}"
}
start() {
    command -v wf-recorder >/dev/null || { notify-send -a Recorder -u critical "wf-recorder is not installed" "Install it with: sudo pacman -S wf-recorder"; exit 1; }
    running && exit 0
    mkdir -p "$dir"
    file="$dir/Recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
    args=(-f "$file")
    case "${1:-screen}" in
        region) geometry="$(slurp)" || exit 0; args+=(-g "$geometry") ;;
        screen) output="$(mmsg get all-monitors | jq -r '.monitors[] | select(.active == true) | .name' | head -n1)"; [[ -n "$output" ]] && args+=(-o "$output") ;;
    esac
    # Desktop audio: the default sink's monitor.
    [[ "${2:-}" == audio ]] && args+=(--audio="$(pactl get-default-sink).monitor")
    setsid wf-recorder "${args[@]}" >/dev/null 2>&1 &
    printf '%s\n%s\n%s\n' "$!" "$(date +%s)" "$file" > "$state"
    bar true
}
case "${1:-toggle}" in
    start) shift; start "$@" ;;
    stop) stop ;;
    toggle) if running; then stop; else start screen; fi ;;
    status) running && echo recording || echo idle ;;
    *) echo "usage: record.sh start region|screen [audio] | stop | toggle | status" >&2; exit 2 ;;
esac
