#!/usr/bin/env bash
# mv-tempo: Uebungsmodus + Turbo echt spielen (tests/mv_tempo_play.gd), mit Screenshots.
# Zwei Godot-Prozesse: Bot (Uebung 3D/2D, Turbo 3D) und echte Tasten (Turbo 2D + Replay).
# Eigenes APPDATA: Nutzer-Einstellungen/Scores bleiben unberuehrt.
#   tests/mv_tempo_play.sh            beide Laeufe
#   tests/mv_tempo_play.sh bot|keys   nur einer
#   OUT=<ordner> GODOT=<exe> MAPS_SRC=<ordner> tests/mv_tempo_play.sh
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
MAPS_SRC=${MAPS_SRC:-/c/Users/Gexanx/Desktop/rhyg/maps}
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/mv_tempo.XXXXXX")}
mkdir -p "$OUT/appdata"
# Audiospur mit mindestens ~50 s: mittelgrosse Map.
SRC=$(ls -S "$MAPS_SRC"/*.osz 2>/dev/null | sed -n '20p')
[ -n "$SRC" ] || SRC=$(ls -S "$MAPS_SRC"/*.osz 2>/dev/null | head -1)
[ -n "$SRC" ] || { echo "FAIL: keine Map in $MAPS_SRC"; exit 2; }
OUT_W=$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")
SRC_W=$(cygpath -m "$SRC" 2>/dev/null || echo "$SRC")
ONLY=${1:-}

had_override=0
[ -f override.cfg ] && had_override=1
[ $had_override -eq 1 ] || cp tools/test_override.cfg override.cfg
cleanup() { [ $had_override -eq 1 ] || rm -f override.cfg; }
trap cleanup EXIT

rc=0
run() {  # run <name> <faelle> [extra-flags...]
	local name=$1 cases=$2; shift 2
	[ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || return 0
	local log="$OUT/tempo_${name}.log"
	APPDATA=$(cygpath -w "$OUT/appdata_$name" 2>/dev/null || echo "$OUT/appdata_$name") \
		timeout 150 "$G" --path . --position -1920,0 --audio-driver Dummy \
		--script res://tests/mv_tempo_play.gd --live-qa --tempo-cases="$cases" \
		--qa-src="$SRC_W" --qa-out="$OUT_W" "$@" > "$log" 2>&1
	local r=$?
	grep -E "^QA |^PRACTICE " "$log" | sed "s/^/  /"
	local errs
	errs=$(grep -cE "SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid access|Watchdog" "$log")
	echo "== $name rc=$r log-fehler=$errs"
	if [ "$errs" -gt 0 ]; then
		grep -E -A2 "SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid access|Watchdog" "$log" \
			| grep -v "^--" | sort | uniq -c | sort -rn | head -12 | cut -c1-260
	fi
	{ [ $r -eq 0 ] && [ "$errs" -eq 0 ]; } || rc=1
}

run bot "practice3d,practice2d,turbo3d" --autoplay
run keys "turbo2d"

echo "MV-TEMPO-PLAY $([ $rc -eq 0 ] && echo OK || echo FAIL) (logs + Bilder: $OUT)"
exit $rc
