#!/bin/bash

CONFIG_SRC="$HOME/.config/mango/waybar/config.jsonc"
STYLE_SRC="$HOME/.config/mango/waybar/style.css"
CONFIG_RUN="/tmp/waybar-config-$USER.jsonc"
LOG="$HOME/.cache/waybar.log"
LOCK="/tmp/waybar-launch-$USER.pid"

# Só um supervisor (este script) vivo por vez. Se já tinha um rodando
# de uma chamada anterior (boot, ou o wallust-reload.sh disparando de
# novo), mata ELE primeiro - senão o loop de retry antigo fica
# competindo com essa chamada nova e sobe waybar em dobro/triplo.
if [ -f "$LOCK" ]; then
    old_pid="$(cat "$LOCK" 2>/dev/null)"
    [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null
fi
echo $$ > "$LOCK"
pkill -x waybar 2>/dev/null

cp "$CONFIG_SRC" "$CONFIG_RUN"

has_battery=false
for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] && has_battery=true && break
done

if $has_battery; then
    # injeta "battery" logo depois de "temperature" no modules-right
    sed -i 's/"temperature",/"temperature",\n        "battery",/' "$CONFIG_RUN"
fi

# Se o waybar morrer rápido no boot (corrida com monitor/tray/etc
# ainda subindo), tenta de novo em vez de ficar fora pro resto da
# sessão. Se ficar de pé mais de 5s, para de insistir - não é mais
# boot-race, é outra coisa (e o log abaixo mostra o que foi). Código
# >=128 = morto por sinal (SIGTERM/SIGKILL de um pkill em outro
# lugar) - nesse caso NÃO retenta, foi morte de propósito.
attempts=0
max_attempts=5
while [ $attempts -lt $max_attempts ]; do
    start=$(date +%s)
    waybar -c "$CONFIG_RUN" -s "$STYLE_SRC" >>"$LOG" 2>&1
    code=$?
    elapsed=$(( $(date +%s) - start ))
    echo "$(date '+%F %T') -- waybar saiu (codigo $code) depois de ${elapsed}s, tentativa $((attempts+1))" >>"$LOG"

    if [ "$code" -ge 128 ]; then
        echo "$(date '+%F %T') -- morto por sinal, nao vou tentar de novo" >>"$LOG"
        break
    fi
    [ "$elapsed" -ge 5 ] && break
    attempts=$((attempts+1))
    sleep 1
done

rm -f "$LOCK"