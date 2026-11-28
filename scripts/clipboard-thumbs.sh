#!/usr/bin/env bash
# Decode image entries from cliphist into small cached thumbnails for the
# Quickshell clipboard panel. Reads "ID<TAB>preview" lines on stdin and prints
# "ID<TAB>/path/to/thumb.png" for every image it could render.
set -u
cache="${XDG_CACHE_HOME:-$HOME/.cache}/victoria/clipboard-thumbs"
mkdir -p "$cache"
while IFS= read -r line; do
    id="${line%%$'\t'*}"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    case "$line" in *"[[ binary data"*png*|*"[[ binary data"*jpeg*|*"[[ binary data"*jpg*|*"[[ binary data"*webp*|*"[[ binary data"*bmp*) ;; *) continue ;; esac
    out="$cache/$id.png"
    if [[ ! -s "$out" ]]; then
        printf '%s\n' "$line" | cliphist decode 2>/dev/null \
            | magick - -thumbnail 160x100 -strip "$out" 2>/dev/null || { rm -f "$out"; continue; }
    fi
    printf '%s\t%s\n' "$id" "$out"
done
# Drop thumbnails for entries that left the history.
find "$cache" -name '*.png' -mtime +14 -delete 2>/dev/null
exit 0
