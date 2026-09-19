#!/usr/bin/env bash
# ~/.config/mango/scripts/wallust-reload.sh
#
# Chamado pelo post_command do Waypaper toda vez que ele troca o
# wallpaper de QUALQUER saída. O Waypaper restaura HDMI-A-1 e DP-1
# em chamadas separadas e só manda o caminho da imagem ($1) — não
# manda o nome do monitor. Então quem chamasse por último vencia a
# corrida e sobrescrevia o colors.css (por isso a cor ficava presa
# no DP-1, que restaura depois do HDMI).
#
# Fix: ignora o $1 e pergunta pro awww-daemon (fonte de verdade de
# qual imagem tá em cada saída agora) qual é o wallpaper ATUAL do
# HDMI-A-1, sempre — não importa qual monitor disparou essa chamada.
#
# Configurar em ~/.config/waypaper/config.ini, na seção [Settings]:
#   post_command = ~/.config/mango/scripts/wallust-reload.sh

set -euo pipefail

MONITOR="HDMI-A-1"
LOG="$HOME/.cache/wallust-reload.log"

WALLPAPER="$(awww query 2>/dev/null | grep "$MONITOR:" | sed -n 's/.*currently displaying: image: //p' | head -n1)"

if [[ -z "$WALLPAPER" ]]; then
    echo "$(date '+%F %T') -- nao achei o wallpaper atual de $MONITOR via 'awww query'" >>"$LOG"
    exit 1
fi

# 1. gera ~/.config/mango/waybar/colors.css a partir da imagem do HDMI
{
    echo "---- $(date '+%F %T') ----"
    echo "monitor fixo: $MONITOR"
    echo "wallpaper usado: $WALLPAPER"
    echo -n "wallust: "; which wallust || echo "NAO ENCONTRADO"
    wallust run "$WALLPAPER"
    echo -n "color5 gerado: "; grep '^@define-color color5' "$HOME/.config/mango/waybar/colors.css"
} >>"$LOG" 2>&1

# 2. reinicia o waybar via waybar-launch.sh — NÃO chamar `waybar`
#    direto aqui, porque esse script cuida da detecção de bateria
#    (injeta o módulo #battery no config.jsonc via sed quando
#    encontra /sys/class/power_supply/BAT*). Chamar waybar na mão
#    perderia essa lógica a cada troca de wallpaper.
bash "$HOME/.config/mango/scripts/waybar-launch.sh" &
disown