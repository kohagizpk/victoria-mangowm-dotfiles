#!/bin/sh
# Print de uma região da tela direto para o clipboard (grim + slurp).
region="$(slurp)" || exit 0
grim -g "$region" - | wl-copy --type image/png
