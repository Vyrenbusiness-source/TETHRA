#!/usr/bin/env bash
# Modus-Multiplayer-Smoke (MODE=orbit|rally|dirigent; Rally/Dirigent-Szene muss die
# Zeilen "MPORBIT start:" und "MPORBIT final ... live_seen=" wie orbit_game ausgeben).
# Orbit-Multiplayer-Smoke: zwei echte Godot-Prozesse (Host + Client, headless)
# ueber 127.0.0.1. Ablauf (scripts/ui/mp_lobby.gd _mp_orbit):
#   Raum -> Modus Orbit -> Map -> beide bereit -> Runde (Bots, Client mit
#   Fehlern) -> Live-Scores + Endergebnisse -> zurueck im Raum -> Orbit-Turnier
#   (4 Maps, je 1 Ban, 2 Runden) -> Endstand.
# Client bleibt 10 s im Endscreen (laenger als der Turnier-Autoablauf bis zur
# naechsten Map): prueft das Bereit-Melden bei der Rueckkehr in den Raum.
# Jeder Prozess hat ein eigenes APPDATA (user://), Scores/Settings des Nutzers
# bleiben unberuehrt. Maps: die N kleinsten .osz aus MAPS_SRC in einen Testordner.
#
#   tools/mp_mode_smoke.sh            (Exit 0 = gruen)
#   GODOT=<exe> PORT=11110 CUT=8 MAPS_SRC=<ordner> KEEP=1 tools/mp_mode_smoke.sh
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
MODE=${MODE:-orbit}
LABEL=${LABEL:-$(echo "${MODE:0:1}" | tr a-z A-Z)${MODE:1}}
PORT=${PORT:-11110}
CUT=${CUT:-8}
LIMIT=${LIMIT:-300}
MAPS_SRC=${MAPS_SRC:-/c/Users/Gexanx/Desktop/rhyg/maps}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mp_mode.XXXXXX")
mkdir -p "$WORK/maps" "$WORK/host" "$WORK/client"

# 4 kleinste Sets (je 1 Diff reicht fuer 4 Pool-Eintraege).
ls -S "$MAPS_SRC"/*.osz 2>/dev/null | tail -4 | while read -r f; do cp "$f" "$WORK/maps/"; done
if [ "$(ls "$WORK/maps" | wc -l)" -lt 4 ]; then
	echo "FAIL: zu wenig Maps in $MAPS_SRC"; exit 2
fi
MAPS_W=$(cygpath -m "$WORK/maps" 2>/dev/null || echo "$WORK/maps")

COMMON=(--headless --path . res://scenes/mp_lobby.tscn --mp-port="$PORT"
	--maps-dir="$MAPS_W" --mp-maps="$MAPS_W" --mp-bot --mp-cut="$CUT")

APPDATA=$(cygpath -w "$WORK/host" 2>/dev/null || echo "$WORK/host") \
	timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-orbit-host --mp-mode="$MODE" --auto-seed=1 \
	> "$WORK/host.log" 2>&1 &
HP=$!
sleep 2
APPDATA=$(cygpath -w "$WORK/client" 2>/dev/null || echo "$WORK/client") \
	timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-orbit-client --mp-mode="$MODE" --auto-seed=7 --auto-miss=6 --mp-back=10 \
	> "$WORK/client.log" 2>&1 &
CP=$!
wait $HP; HRC=$?
wait $CP; CRC=$?

grep -h "^MPORBIT" "$WORK/host.log" | sed 's/^/H| /'
grep -h "^MPORBIT" "$WORK/client.log" | sed 's/^/C| /'

fail=0
check() {  # check <log> <regex> <text>
	if ! grep -Eq "$2" "$WORK/$1.log"; then
		echo "FAIL $1: $3"; fail=1
	fi
}
[ $HRC -eq 0 ] || { echo "FAIL host rc=$HRC"; fail=1; }
[ $CRC -eq 0 ] || { echo "FAIL client rc=$CRC"; fail=1; }
for side in host client; do
	check $side "MPORBIT [A-Z]+ s0 all ready, views $LABEL/$LABEL" "Raum Orbit + bereit"
	check $side "MPORBIT [A-Z]+ s1 room finals \[[0-9]+:[^]]* score=[1-9][0-9]*[^]]*, [0-9]+:[^]]* score=[1-9]" "Endergebnisse beider im Raum"
	check $side "MPORBIT [A-Z]+ s1 back in room: in_game=false play_mode=$MODE" "Rueckkehr in den Raum"
	check $side "MPORBIT [A-Z]+ s2 tour rounds=1 " "Turnierrunde 1 gewertet"
	n=$(grep -c "^MPORBIT start:" "$WORK/$side.log")
	[ "$n" -eq 3 ] || { echo "FAIL $side: $n statt 3 Orbit-Runden gestartet"; fail=1; }
	check $side "MPORBIT [A-Z]+ s3 tour rounds=2 " "2 Turnierrunden gewertet"
	check $side "MPORBIT [A-Z]+ s3 DONE" "Ende"
	# Live-Score des anderen kam waehrend der Runde an (> 0, vor dessen Finale).
	n=$(grep -Ec "^MPORBIT final .*live_seen=\{ ?[0-9]+: [1-9]" "$WORK/$side.log")
	[ "$n" -ge 3 ] || { echo "FAIL $side: Live-Scores nur in $n von 3 Runden"; fail=1; }
	if grep -qE "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Watchdog" "$WORK/$side.log"; then
		grep -E -A2 "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Watchdog" "$WORK/$side.log" | head -12
		echo "FAIL $side: Skriptfehler"; fail=1
	fi
done
# Client spielt mit Fehlern (--auto-miss): Genauigkeit unter 100 %.
grep -Eq "^MPORBIT final .*acc=0\.[0-9]+ .*failed=" "$WORK/client.log" \
	|| { echo "FAIL client: keine Fehler gespielt"; fail=1; }

if [ $fail -eq 0 ]; then
	echo "MP-ORBIT-SMOKE OK (logs: $WORK)"
	[ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
	exit 0
fi
echo "MP-ORBIT-SMOKE FAIL (logs: $WORK)"
exit 1
