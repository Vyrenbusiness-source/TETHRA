#!/usr/bin/env bash
# Live-QA: echte Spielszenen mit echten Eingaben (tests/live_qa.gd), ein Godot-Prozess
# je Zeile, nacheinander. Eigenes APPDATA: Nutzer-Einstellungen/Scores bleiben unberuehrt.
#   tests/live_qa.sh                 alle Modi, alle Faelle
#   tests/live_qa.sh rebound flow    ein Modus, eine Fallgruppe (flow|mods|fail)
#   OUT=<ordner> GODOT=<exe> MAPS_SRC=<ordner> tests/live_qa.sh
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
MAPS_SRC=${MAPS_SRC:-/c/Users/Gexanx/Desktop/rhyg/maps}
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/live_qa.XXXXXX")}
mkdir -p "$OUT/appdata"
SRC=$(ls -S "$MAPS_SRC"/*.osz 2>/dev/null | tail -1)
[ -n "$SRC" ] || { echo "FAIL: keine Map in $MAPS_SRC"; exit 2; }
OUT_W=$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")
SRC_W=$(cygpath -m "$SRC" 2>/dev/null || echo "$SRC")
ONLY_MODE=${1:-}
ONLY_GROUP=${2:-}
BOT="--autoplay --auto-jitter=10 --auto-aim=0.5 --auto-seed=3"

had_override=0
[ -f override.cfg ] && had_override=1
[ $had_override -eq 1 ] || cp tools/test_override.cfg override.cfg
cleanup() { [ $had_override -eq 1 ] || rm -f override.cfg; }
trap cleanup EXIT

rc=0
run() {  # run <modus> <gruppe> <faelle> [extra-flags...]
	local mode=$1 group=$2 cases=$3; shift 3
	[ -z "$ONLY_MODE" ] || [ "$ONLY_MODE" = "$mode" ] || return 0
	[ -z "$ONLY_GROUP" ] || [ "$ONLY_GROUP" = "$group" ] || return 0
	local log="$OUT/${mode}_${group}.log"
	APPDATA=$(cygpath -w "$OUT/appdata" 2>/dev/null || echo "$OUT/appdata") \
		timeout 150 "$G" --path . --position -1920,0 --audio-driver Dummy \
		--script res://tests/live_qa.gd --live-qa --qa-mode="$mode" --qa-cases="$cases" \
		--qa-src="$SRC_W" --qa-out="$OUT_W" "$@" > "$log" 2>&1
	local r=$?
	grep -E "^QA " "$log" | grep -vE " (OK|INFO) " | sed "s/^/  /"
	grep -E "^QA .* INFO " "$log" | sed "s/^/  /"
	local done_line
	done_line=$(grep -E "^QA DONE" "$log" || echo "QA DONE fehlt (rc=$r)")
	local errs
	errs=$(grep -cE "SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid access|Watchdog" "$log")
	echo "== $mode/$group rc=$r $done_line log-fehler=$errs"
	if [ "$errs" -gt 0 ]; then
		grep -E -A2 "SCRIPT ERROR|ERROR:|WARNING:|Parse Error|Invalid call|Invalid access|Watchdog" "$log" \
			| grep -v "^--" | sort | uniq -c | sort -rn | head -12 | cut -c1-260
	fi
	{ [ $r -eq 0 ] && [ "$errs" -eq 0 ]; } || rc=1
}

run mania2d flow "flow,retry" --2d
run mania2d mods "mod:,mod:NF,mod:SV,mod:HD,mod:FI" --2d
run mania2d fail "fail,nfidle,mod:CS" --2d
run mania3d flow "flow,retry" --3d
run mania3d mods "mod:,mod:NF,mod:SV,mod:CS,fail" --3d
run rebound flow "flow,retry"
run rebound mods "mod:,mod:NF,mod:SV,fail,nfidle"
run trace flow "flow,retry"
run trace mods "mod:,mod:NF,mod:MR,mod:HD,mod:SS"
run trace fail "fail,nfidle"
run orbit flow "flow,retry" $BOT
run orbit mods "mod:,mod:NF,mod:HD,mod:FI,mod:PR" $BOT --auto-miss=6
run orbit fail "fail,nfidle"
run rally flow "flow,retry" $BOT
run rally mods "mod:,mod:NF" $BOT --auto-miss=6
run rally fail "fail,nfidle"
run dirigent flow "flow,retry" $BOT
run dirigent mods "mod:,mod:NF" $BOT --auto-miss=6
run dirigent fail "fail,nfidle"

echo "LIVE-QA $([ $rc -eq 0 ] && echo OK || echo FAIL) (logs: $OUT)"
exit $rc
