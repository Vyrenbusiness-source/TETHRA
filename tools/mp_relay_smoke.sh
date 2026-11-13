#!/usr/bin/env bash
# Relay-Smoke: echter Relay-Prozess (--mp-relay) + Host + Client (je ein
# headless Godot-Prozess) ueber ws://127.0.0.1. Prueft Raum-Code, Beitritt,
# Live-Score und Endergebnis in beide Richtungen sowie GET /rooms.
# Jeder Prozess hat ein eigenes APPDATA (user://). Kein Fenster, kein Audio.
#
#   tools/mp_relay_smoke.sh            (Exit 0 = gruen)
#   GODOT=<exe> PORT=47911 tools/mp_relay_smoke.sh
#   MODE=<mania|orbit|rally|dirigent|trace|rebound> tools/mp_relay_smoke.sh
#     ganze Runde + Turnier im Modus ueber den Relay (Ablauf von tools/mp_mode_smoke.sh).
set -u
cd "$(dirname "$0")/.."
if [ -n "${MODE:-}" ]; then
	RELAY=1 PORT=${PORT:-47911} exec bash tools/mp_mode_smoke.sh
fi
G=${GODOT:-/c/Users/Gexanx/Desktop/rhyg/Godot_v4.7-stable_win64_console.exe}
PORT=${PORT:-47911}
LIMIT=${LIMIT:-90}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mp_relay.XXXXXX")
mkdir -p "$WORK/relay" "$WORK/host" "$WORK/client"
URL="ws://127.0.0.1:$PORT/mp"
wp() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

APPDATA=$(wp "$WORK/relay") timeout "$LIMIT" "$G" --headless --path . --mp-relay --port "$PORT" \
	> "$WORK/relay.log" 2>&1 &
RP=$!
for _ in $(seq 1 100); do
	grep -q "Relay lauscht" "$WORK/relay.log" 2>/dev/null && break
	sleep 0.2
done

COMMON=(--headless --path . res://scenes/mp_lobby.tscn --relay-url="$URL")
APPDATA=$(wp "$WORK/host") timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-relay-host \
	> "$WORK/host.log" 2>&1 &
HP=$!
CODE=""
for _ in $(seq 1 100); do
	CODE=$(sed -n 's/^MPRELAY code=\([A-Z0-9]*\).*/\1/p' "$WORK/host.log" 2>/dev/null | head -1)
	[ -n "$CODE" ] && break
	sleep 0.2
done
ROOMS=""
if [ -n "$CODE" ]; then
	ROOMS=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/rooms" || true)
	APPDATA=$(wp "$WORK/client") timeout "$LIMIT" "$G" "${COMMON[@]}" --mp-relay-client --mp-relay-code="$CODE" \
		> "$WORK/client.log" 2>&1 &
	CP=$!
	wait $CP; CRC=$?
else
	CRC=99
fi
wait $HP; HRC=$?
kill $RP 2>/dev/null; wait $RP 2>/dev/null

grep -h "^MPRELAY" "$WORK/host.log" | sed 's/^/H| /'
grep -h "^MPRELAY" "$WORK/client.log" 2>/dev/null | sed 's/^/C| /'
echo "rooms: $ROOMS"

fail=0
[ -n "$CODE" ] || { echo "FAIL: kein Raum-Code"; fail=1; }
[ $HRC -eq 0 ] || { echo "FAIL host rc=$HRC"; fail=1; }
[ $CRC -eq 0 ] || { echo "FAIL client rc=$CRC"; fail=1; }
case "$ROOMS" in *"\"code\":\"$CODE\""*) ;; *) echo "FAIL: /rooms ohne Raum $CODE"; fail=1;; esac
for side in host client; do
	grep -Eq "MPRELAY [A-Z]+ players=2 " "$WORK/$side.log" || { echo "FAIL $side: 2 Spieler"; fail=1; }
	grep -Eq "MPRELAY [A-Z]+ live score" "$WORK/$side.log" || { echo "FAIL $side: Live-Score"; fail=1; }
	grep -Eq "MPRELAY [A-Z]+ final score" "$WORK/$side.log" || { echo "FAIL $side: Endergebnis"; fail=1; }
	grep -Eq "MPRELAY [A-Z]+ DONE" "$WORK/$side.log" || { echo "FAIL $side: nicht fertig"; fail=1; }
	if grep -qE "SCRIPT ERROR|Parse Error|Invalid call|Invalid access" "$WORK/$side.log"; then
		grep -E -A2 "SCRIPT ERROR|Parse Error|Invalid call|Invalid access" "$WORK/$side.log" | head -12
		echo "FAIL $side: Skriptfehler"; fail=1
	fi
done
if grep -qE "SCRIPT ERROR|Parse Error" "$WORK/relay.log"; then
	grep -E -A2 "SCRIPT ERROR|Parse Error" "$WORK/relay.log" | head; echo "FAIL relay: Skriptfehler"; fail=1
fi
if [ $fail -eq 0 ]; then
	echo "MP-RELAY-SMOKE OK"
	[ "${KEEP:-0}" = 1 ] || rm -rf "$WORK"
	exit 0
fi
echo "MP-RELAY-SMOKE FAIL (logs: $WORK)"
exit 1
