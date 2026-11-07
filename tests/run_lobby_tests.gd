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

	# Mods: Sync, Ready-Reset, Rechte, spaeter Beitritt
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna") }
	L.crown_id = 1
	L.sel_map = map_a
	for id in [1, 2]:
		L.players[id].ready = true
	_check(L.mods == { "SV": false, "NF": false }, "Mods starten aus")
	L.pick_mods({ "SV": true })
	_check(bool(L.mods.SV) and not bool(L.mods.NF), "Host setzt SV")
	_check(not L.all_ready() and not bool(L.players[1].ready) and not bool(L.players[2].ready),
		"Mod-Wechsel setzt Ready zurueck")
	L.players[1].ready = true
	L.players[2].ready = true
	L.pick_mods({ "SV": true, "NF": false })
	_check(L.all_ready(), "gleiche Mods: Ready bleibt")
	L.give_crown(2)
	L.pick_mods({ "SV": false, "NF": true })
	_check(bool(L.mods.SV), "alter Host kann Mods nicht mehr aendern")
	L.crown_id = 1
	# Client-Sicht / spaeter Beitritt: cl_state liefert die Mods mit
	var snap: Dictionary = L.mods.duplicate()
	L.mods = { "SV": false, "NF": false }
	L.cl_state(L.players, 1, map_a, "R", [], snap)
	_check(bool(L.mods.SV) and not bool(L.mods.NF), "cl_state uebernimmt Mods (Beitritt)")
	L.cl_state(L.players, 1, map_a, "R", [], {})
	_check(L.mods == { "SV": false, "NF": false }, "fehlende Mods -> aus")
	_check(L.mods_text({ "SV": true, "NF": true }) == "SV NF" and L.mods_text({}) == "", "mods_text")
	L.mods = { "SV": true, "NF": false }
	L._reset()
	_check(L.mods == { "SV": false, "NF": false }, "Reset loescht Mods")

	# Disconnect waehrend des Spiels: Spieler faellt raus, Krone wandert, Board laeuft weiter
	L.active = true
	L.is_host = true
	L.in_game = true
	L.crown_id = 1
	L.players = { 1: L._new_player("H"), 2: L._new_player("B"), 3: L._new_player("C") }
	L.players[1].score = 100
	L.players[2].score = 900
	L.players[3].score = 500
	var upd := [0]
	L.scores_changed.connect(func(): upd[0] += 1)
	L.give_crown(2)
	L._on_peer_disconnected(2)
	_check(not L.players.has(2) and L.in_game, "Disconnect im Spiel: Spieler weg, Runde laeuft")
	_check(L.crown_id == 1, "Disconnect im Spiel: Krone wandert")
	_check(upd[0] >= 1, "Disconnect im Spiel: Board wird aktualisiert")
	var rk: Array = L.ranked_players()
	_check(rk.size() == 2 and int(rk[0].id) == 3, "Ranking ohne Gegangenen")
	L.send_final({ "score": 100, "acc": 0.9 })
	L._on_peer_disconnected(3)
	_check(L.players.size() == 1 and L.ranked_players().size() == 1, "letzter Gegner weg: Rest bleibt")
	L.in_game = false

	# Score-Paket validieren
	var backup := ""
	if FileAccess.file_exists(ScoreStore.PATH):
		backup = FileAccess.get_file_as_string(ScoreStore.PATH)
		DirAccess.remove_absolute(ScoreStore.PATH)
	L._reset()
	L.active = true
	L.is_host = true
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna") }
	L.sel_map = { "set_id": 11, "file": "11 a.osz", "version": "Hard", "stars": 4.0 }
	var ok_e := { "score": 5000, "accuracy": 0.9, "grade": "A", "max_combo": 50, "pp": 10.0, "mods": [], "date": "2026-01-01T10:00:00" }
	_check(L.accept_scores(2, 11, "Hard", [ok_e]) == 1, "gueltiges Paket gespeichert")
	_check(L.accept_scores(2, 11, "Hard", [ok_e]) == 0, "Duplikat abgewiesen")
	_check(L.accept_scores(2, 99, "Hard", [ok_e]) == 0, "falsche Map abgewiesen")
	_check(L.accept_scores(2, 11, "Easy", [ok_e]) == 0, "falsche Diff abgewiesen")
	_check(L.accept_scores(7, 11, "Hard", [ok_e]) == 0, "unbekannter Sender abgewiesen")
	var big: Array = []
	for i in 11:
		big.append(ok_e.merged({ "score": 6000 + i }, true))
	_check(L.accept_scores(2, 11, "Hard", big) == 0, "mehr als 10 abgewiesen")
	var bad: Array = [
		ok_e.merged({ "score": "x" }, true), ok_e.merged({ "score": -5 }, true),
		ok_e.merged({ "accuracy": 3.0 }, true), ok_e.merged({ "grade": "ZZ" }, true),
		ok_e.merged({ "mods": "SV" }, true), ok_e.merged({ "pp": 1e12 }, true), 5, "str",
		ok_e.merged({ "failed": true }, true),
	]
	_check(L.accept_scores(2, 11, "Hard", bad) == 0, "ungueltige Eintraege abgewiesen")
	L.players[2].name = "N".repeat(40)
	L.accept_scores(2, 11, "Hard", [ok_e.merged({ "score": 7000 }, true)])
	var all: Array = ScoreStore.top_scores_all("11 a.osz", "Hard", 10)
	_check(all.size() == 2 and str(all[0].player).length() == 24, "Name auf 24 gekappt")
	L.players[2].name = "Anna"
	_check(L._store_final(2, { "score": 9000, "acc": 0.95, "grade": "S", "combo": 80, "failed": true }) == 0, "Fail nicht gespeichert")
	_check(L._store_final(2, { "score": 9000, "acc": 0.95, "grade": "S", "combo": 80, "failed": false }) == 1, "Endergebnis gespeichert")
	_check(ScoreStore.best("11 a.osz", "Hard").is_empty(), "eigener Bestwert unberuehrt")
	DirAccess.remove_absolute(ScoreStore.PATH)
	if backup != "":
		var f := FileAccess.open(ScoreStore.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()

	L._reset()
	print("FAILED: %d" % _failed)
	quit(1 if _failed > 0 else 0)
