#!/usr/bin/env bash
# Screenshots: screenshot.sh region|window|screen [--edit]
# Saved to ~/Pictures/Screenshots and copied to the clipboard; --edit opens swappy.
set -u
mode="${1:-region}"; edit="${2:-}"
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
file="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S-%3N).png"
case "$mode" in
    region) geometry="$(slurp)" || exit 0 ;;
    window)
        # Focused client geometry from Mango (global layout coordinates).
        geometry="$(mmsg get focusing-client | jq -r '"\(.x),\(.y) \(.width)x\(.height)"')"
        [[ "$geometry" =~ ^-?[0-9]+,-?[0-9]+\ [0-9]+x[0-9]+$ ]] || { notify-send -a Screenshot "No focused window"; exit 1; } ;;
    screen) geometry="" ;;
    *) echo "usage: screenshot.sh region|window|screen [--edit]" >&2; exit 2 ;;
esac
if [[ "$mode" == screen ]]; then
    output="$(mmsg get all-monitors | jq -r '.monitors[] | select(.active == true) | .name' | head -n1)"
    grim ${output:+-o "$output"} "$file" || exit 1
else
    grim -g "$geometry" "$file" || exit 1
fi
wl-copy --type image/png < "$file"
if [[ "$edit" == --edit ]] && command -v swappy >/dev/null; then
    exec swappy -f "$file" -o "$file"
fi
notify-send -a Screenshot -i "$file" "Screenshot saved" "Copied to the clipboard · ${file/#$HOME/\~}"
