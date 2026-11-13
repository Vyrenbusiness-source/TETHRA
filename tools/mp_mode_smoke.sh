#!/usr/bin/env bash
# Modus-Multiplayer-Smoke (MODE=mania|orbit|rally|dirigent|trace|rebound; jede Spielszene gibt
# die Zeilen "MPORBIT start:" und "MPORBIT final ... live_seen=" wie orbit_game aus).
# MODS=NF (oder SV,NF): Raum-Mods der ersten Runde (--mp-mods), geprueft auf beiden Seiten.
# RELAY=1: derselbe Ablauf ueber einen echten Relay-Prozess (ws://127.0.0.1:$PORT/mp)
#   statt direkt (ENet); so ruft ihn tools/mp_relay_smoke.sh MODE=<modus> auf.
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
# MODE=trace prueft zusaetzlich Versus-Live-Leiste, Miss-Bitfeld und Versus-Bilder im Raum.
#
#   tools/mp_mode_smoke.sh            (Exit 0 = gruen)
#   GODOT=<exe> PORT=11110 CUT=8 MAPS_SRC=<ordner> KEEP=1 MODS=NF RELAY=1 VERBOSE=1 tools/mp_mode_smoke.sh
set -u
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
MODE=${MODE:-orbit}
LABEL=${LABEL:-$(echo "${MODE:0:1}" | tr a-z A-Z)${MODE:1}}
VIEW=$LABEL
[ "$MODE" = mania ] && VIEW="(2D|3D)"
MODS=${MODS:-}
RELAY=${RELAY:-0}
PORT=${PORT:-11110}
CUT=${CUT:-8}
LIMIT=${LIMIT:-300}
MAPS_SRC=${MAPS_SRC:-/c/Users/Gexanx/Desktop/rhyg/maps}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mp_mode.XXXXXX")
mkdir -p "$WORK/maps" "$WORK/host" "$WORK/client" "$WORK/relay"

# 4 kleinste Sets (je 1 Diff reicht fuer 4 Pool-Eintraege).
ls -S "$MAPS_SRC"/*.osz 2>/dev/null | tail -4 | while read -r f; do cp "$f" "$WORK/maps/"; done
if [ "$(ls "$WORK/maps" | wc -l)" -lt 4 ]; then
	echo "FAIL: zu wenig Maps in $MAPS_SRC"; exit 2
fi
MAPS_W=$(cygpath -m "$WORK/maps" 2>/dev/null || echo "$WORK/maps")

COMMON=(--headless --path . res://scenes/mp_lobby.tscn --mp-port="$PORT"
	--maps-dir="$MAPS_W" --mp-maps="$MAPS_W" --mp-bot --mp-cut="$CUT")
[ -n "$MODS" ] && COMMON+=(--mp-mods="$MODS")
# VERBOSE=1: Godot --verbose (nennt beim Beenden jede uebrige ObjectDB-Instanz).
[ "${VERBOSE:-0}" = 1 ] && COMMON+=(--verbose)
CODE_ARG=()
RP=""
if [ "$RELAY" = 1 ]; then
	APPDATA=$(cygpath -w "$WORK/relay" 2>/dev/null || echo "$WORK/relay") \
		timeout "$LIMIT" "$G" --headless --path . --mp-relay --port "$PORT" > "$WORK/relay.log" 2>&1 &
	RP=$!
	for _ in $(seq 1 100); do
		grep -q "Relay lauscht" "$WORK/relay.log" 2>/dev/null && break
		sleep 0.2
	done
	COMMON+=(--relay-url="ws://127.0.0.1:$PORT/mp" --mp-via-relay)
fi

APPDATA=$(cygpath -w "$WORK/host" 2>/dev/null || echo "$WORK/host") \
	timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-orbit-host --mp-mode="$MODE" --auto-seed=1 \
	> "$WORK/host.log" 2>&1 &
HP=$!
sleep 2
if [ "$RELAY" = 1 ]; then
	CODE=""
	for _ in $(seq 1 150); do
		CODE=$(sed -n 's/^MPRELAY code=\([A-Z0-9]*\).*/\1/p' "$WORK/host.log" 2>/dev/null | head -1)
		[ -n "$CODE" ] && break
		sleep 0.2
	done
	[ -n "$CODE" ] || echo "FAIL: kein Raum-Code vom Relay"
	CODE_ARG=(--mp-relay-code="$CODE")
fi
APPDATA=$(cygpath -w "$WORK/client" 2>/dev/null || echo "$WORK/client") \
	timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-orbit-client --mp-mode="$MODE" --auto-seed=7 --auto-miss=6 --mp-back=10 ${CODE_ARG[@]+"${CODE_ARG[@]}"} \
	> "$WORK/client.log" 2>&1 &
CP=$!
wait $HP; HRC=$?
wait $CP; CRC=$?
[ -n "$RP" ] && { kill $RP 2>/dev/null; wait $RP 2>/dev/null; }

grep -hE "^MP(ORBIT|RALLY|TRACE versus)" "$WORK/host.log" | sed 's/^/H| /'
grep -hE "^MP(ORBIT|RALLY|TRACE versus)" "$WORK/client.log" | sed 's/^/C| /'

fail=0
check() {  # check <log> <regex> <text>
	if ! grep -Eq "$2" "$WORK/$1.log"; then
		echo "FAIL $1: $3"; fail=1
	fi
}
[ $HRC -eq 0 ] || { echo "FAIL host rc=$HRC"; fail=1; }
[ $CRC -eq 0 ] || { echo "FAIL client rc=$CRC"; fail=1; }
for side in host client; do
	check $side "MPORBIT [A-Z]+ s0 all ready, views $VIEW/$VIEW" "Raum + bereit"
	check $side "MPORBIT [A-Z]+ s1 room finals \[[0-9]+:[^]]* score=[1-9][0-9]*[^]]*, [0-9]+:[^]]* score=[1-9]" "Endergebnisse beider im Raum"
	check $side "MPORBIT [A-Z]+ s1 ranking ok=true \[1\.[^]]*, 2\." "Platzierung = absteigende Endergebnisse"
	if [ -n "$MODS" ]; then
		want=$(echo "$MODS" | tr a-z A-Z | tr ',' '\n' | sort -r | tr '\n' ' ' | sed 's/ $//')
		check $side "^MPLOBBY round mods=\[$want\]" "Raum-Mods $want in Runde 1"
	fi
	if grep -q "ObjectDB instances leaked" "$WORK/$side.log"; then
		echo "FAIL $side: ObjectDB instances leaked at exit"; fail=1
	fi
	check $side "MPORBIT [A-Z]+ s1 back in room: in_game=false play_mode=$MODE" "Rueckkehr in den Raum"
	check $side "MPORBIT [A-Z]+ s2 tour rounds=1 " "Turnierrunde 1 gewertet"
	n=$(grep -Ec "^MP(ORBIT|RALLY) start:" "$WORK/$side.log")
	[ "$n" -eq 3 ] || { echo "FAIL $side: $n statt 3 Orbit-Runden gestartet"; fail=1; }
	check $side "MPORBIT [A-Z]+ s3 tour rounds=2 " "2 Turnierrunden gewertet"
	check $side "MPORBIT [A-Z]+ s3 DONE" "Ende"
	# Live-Score des anderen kam waehrend der Runde an (> 0, vor dessen Finale).
	n=$(grep -Ec "^MP(ORBIT|RALLY) final .*live_seen=\{ ?[0-9]+: [1-9]" "$WORK/$side.log")
	[ "$n" -ge 3 ] || { echo "FAIL $side: Live-Scores nur in $n von 3 Runden"; fail=1; }
	if grep -qE "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Watchdog" "$WORK/$side.log"; then
		grep -E -A2 "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Watchdog" "$WORK/$side.log" | head -12
		echo "FAIL $side: Skriptfehler"; fail=1
	fi
done
# Client spielt mit Fehlern (--auto-miss): Genauigkeit unter 100 %.
# Trace: nur, sobald trace_game --auto-miss kennt (sonst Hinweis statt Fehler).
AUTO_MISS=1
if [ "$MODE" = trace ] && ! grep -q -- "--auto-miss" scripts/trace/trace_game.gd; then
	AUTO_MISS=0
	echo "SKIP client misses: trace_game.gd kennt --auto-miss noch nicht"
fi
if [ $AUTO_MISS -eq 1 ]; then
	grep -Eq "^MP(ORBIT|RALLY) final .*acc=0\.[0-9]+ .*failed=" "$WORK/client.log" \
		|| { echo "FAIL client: keine Fehler gespielt"; fail=1; }
fi
if [ "$MODE" = trace ]; then
	for side in host client; do
		check $side "^MPTRACE versus bar players=2" "Versus-Live-Leiste in der Trace-Runde"
		check $side "MPORBIT [A-Z]+ s1 room finals \[[0-9]+:[^]]* miss=[0-9]+ bits=[0-9]+/[1-9][0-9]*, [0-9]+:[^]]* miss=[0-9]+ bits=[0-9]+/[1-9]" "Miss-Bitfeld in beiden Endergebnissen"
		check $side "MPORBIT [A-Z]+ s1 versus pictures n=2" "Versus-Bilder im Raum"
		# Gezaehlte Misses = Bits im Feld (das Feld traegt genau die verfehlten Noten).
		if ! grep -E "s1 room finals" "$WORK/$side.log" | grep -Eo "miss=[0-9]+ bits=[0-9]+" \
				| awk -F'[= ]' '$2 != $4 { bad = 1 } END { exit bad }'; then
			echo "FAIL $side: Misses und Bitfeld passen nicht"; fail=1
		fi
	done
	if [ $AUTO_MISS -eq 1 ]; then
		check host "s1 room finals .*miss=[1-9][0-9]* bits=[1-9]" "Client-Misses im Bitfeld beim Host"
	fi
fi

if [ $fail -eq 0 ]; then
	echo "MP-ORBIT-SMOKE OK mode=$MODE relay=$RELAY mods=[$MODS] (logs: $WORK)"
	[ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
	exit 0
fi
echo "MP-ORBIT-SMOKE FAIL (logs: $WORK)"
exit 1
