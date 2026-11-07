extends SceneTree

## Headless-Tests fuer die Lobby-Logik (Krone, Ready, Map-Sync, Ranking).
## Der Host-Zustand wird direkt aufgebaut (kein Netz noetig).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	await process_frame
	var L = root.get_node("Lobby")
	L._reset()
	L.active = true
	L.is_host = true
	L.crown_id = 1
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna"), 3: L._new_player("Ben") }
	L.players[1].ready = true

	var map_a := { "set_id": 11, "file": "11 a.osz", "version": "Hard", "stars": 4.0 }
	var map_b := { "set_id": 22, "file": "22 b.osz", "version": "Insane", "stars": 5.0 }

	# Map-Sync + Ready-Reset
	_check(not L.all_ready(), "ohne Map nicht bereit")
	L.pick_map(map_a)
	_check(L.sel_map == map_a, "Host waehlt Map")
	_check(not bool(L.players[1].ready), "Kartenwechsel setzt Ready zurueck")
	for id in [1, 2, 3]:
		L.players[id].ready = true
	_check(L.all_ready(), "alle bereit")
	L.players[3].ready = false
	_check(not L.all_ready(), "einer wartet -> kein Start")
	L.players[3].ready = true
	L.pick_map(map_a)
	_check(L.all_ready(), "gleiche Map erneut: Ready bleibt")
	L.pick_map(map_b)
	_check(not L.all_ready() and not bool(L.players[2].ready), "andere Map: alle unready")

	# Krone: Host gibt an 2; Host darf nicht mehr waehlen
	L.give_crown(2)
	_check(L.crown_id == 2, "Krone an Spieler 2")
	L.pick_map(map_a)
	_check(L.sel_map == map_b, "alter Host kann keine Map mehr waehlen")
	# Server-RPC-Pfad: Sender-Pruefung (Offline-Sender = 0)
	_check(not L.can_start(), "alter Host darf nicht starten")
	# Kronentraeger verlaesst Raum -> Krone zurueck an Host
	L._on_peer_disconnected(2)
	_check(L.crown_id == 1 and not L.players.has(2), "Krone-Traeger geht -> Host")
	L.give_crown(3)
	L._on_peer_disconnected(3)
	_check(L.crown_id == 1, "Krone faellt an Host zurueck")
	_check(L._next_crown() == 1, "naechste Krone: Host")
	L.players.erase(1)
	L.players[5] = L._new_player("Eva")
	L.players[4] = L._new_player("Dan")
	_check(L._next_crown() == 4, "ohne Host: kleinster Peer")

	# Ranking
	L.players = { 1: L._new_player("A"), 2: L._new_player("B"), 3: L._new_player("C") }
	L.players[1].score = 1000
	L.players[2].score = 5000
	L.players[3].score = 5000
	L.players[3].acc = 0.9
	L.players[2].acc = 0.8
	var r: Array = L.ranked_players()
	_check(int(r[0].id) == 3 and int(r[1].id) == 2 and int(r[2].id) == 1,
		"Ranking: Score, dann Genauigkeit")

	# Skip-Abstimmung: Disconnect eines Nicht-Voters loest Skip aus
	var skipped := [false]
	L.skip_now.connect(func(): skipped[0] = true)
	L.is_host = true
	L.in_game = true
	L.skip_votes = { 1: true, 2: true }
	L._on_peer_disconnected(3)
	_check(skipped[0], "Skip: Disconnect des letzten Nicht-Voters")
	L.in_game = false

	# round_done behaelt Ready
	L.players = { 1: L._new_player("A") }
	L.players[1].ready = true
	L.round_done()
	_check(bool(L.players[1].ready) and not L.in_game, "round_done behaelt Ready")

	# Gleiche Namen -> eindeutig, Genauigkeit begrenzt
	L.players = { 1: L._new_player("Gex") }
	_check(L._unique_name("Gex", 2) == "Gex (2)", "doppelter Name -> Gex (2)")
	L.players[2] = L._new_player("Gex (2)")
	_check(L._unique_name("Gex", 3) == "Gex (3)", "dritter Name -> Gex (3)")
	L.in_game = true
	L.send_score(100, 5, 1.0084)
	_check(float(L.players[L.multiplayer.get_unique_id()].acc) <= 1.0 if L.players.has(L.multiplayer.get_unique_id()) else true, "acc <= 100 %")
	L.in_game = false

	# Raum-Code Roundtrip
	var code: String = L._encode_code("192.168.1.20", 47810)
	var dec: Dictionary = L._decode_code(code)
	_check(dec.get("ip", "") == "192.168.1.20" and int(dec.get("port", 0)) == 47810,
		"Raum-Code Roundtrip")

	L._reset()
	print("FAILED: %d" % _failed)
	quit(1 if _failed > 0 else 0)
