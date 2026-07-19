#!/usr/bin/env bash

set -euo pipefail

CONFIG="$HOME/.config/mango/config.conf"
MARK_BEGIN="# BEGIN AUTO-MONITORS (gerado por auto-monitors.sh, não editar à mão)"
MARK_END="# END AUTO-MONITORS"

log() { echo "[auto-monitors] $*" >&2; }

apply_layout() {
	if [ -z "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
		log "MANGO_INSTANCE_SIGNATURE não setado nesse processo, pulando"
		return 1
	fi

	local monitors
	monitors=$(mmsg get all-monitors 2>/dev/null) || {
		log "mmsg get all-monitors falhou"
		return 1
	}

	local detected
	detected=$(echo "$monitors" | jq -r '.[] | "\(.name) \(.width) \(.height)"')

	if [ -z "$detected" ]; then
		log "nenhum monitor retornado pelo mmsg"
		return 1
	fi

	# ordem: usa MONITOR_ORDER se foi passado, senão ordena por nome
	local ordered
	if [ -n "${MONITOR_ORDER:-}" ]; then
		ordered=""
		for name in $MONITOR_ORDER; do
			line=$(echo "$detected" | awk -v n="$name" '$1==n')
			[ -n "$line" ] && ordered="$ordered
$line"
		done
		# qualquer monitor detectado que não esteja no MONITOR_ORDER vai pro final
		while read -r name width height; do
			[ -z "$name" ] && continue
			echo "$MONITOR_ORDER" | grep -qw "$name" || ordered="$ordered
$name $width $height"
		done <<<"$detected"
		ordered=$(echo "$ordered" | sed '/^$/d')
	else
		ordered=$(echo "$detected" | sort)
	fi

	local block="$MARK_BEGIN"
	local x=0
	while read -r name width height; do
		[ -z "$name" ] && continue
		block="$block
monitorrule=name:${name},x:${x},y:0,width:${width},height:${height},scale:1"
		x=$((x + width))
	done <<<"$ordered"
	block="$block
$MARK_END"

	if grep -qF "$MARK_BEGIN" "$CONFIG" 2>/dev/null; then
		awk -v block="$block" -v mbegin="$MARK_BEGIN" -v mend="$MARK_END" '
			$0 == mbegin { print block; skip=1; next }
			$0 == mend   { skip=0; next }
			skip==1      { next }
			{ print }
		' "$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
	else
		awk -v block="$block" '
			/^exec-once=/ && !done { print; print block; done=1; next }
			{ print }
			END { if (!done) print block }
		' "$CONFIG" >"$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
	fi

	mmsg dispatch reload_config
	log "layout aplicado:"
	echo "$ordered" | sed 's/^/  /' >&2
}

apply_layout || log "primeira aplicação falhou, vai tentar de novo se --watch"

if [ "${1:-}" = "--watch" ]; then
	log "modo watch ligado, esperando mudança de monitor..."
	mmsg watch all-monitors 2>/dev/null | while read -r _; do
		sleep 1 # debounce: dá tempo do hotplug terminar de negociar antes de reaplicar
		apply_layout || true
	done
fi
