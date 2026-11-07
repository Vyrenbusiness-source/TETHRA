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

	# Turnier: Server validiert Rechte, Phasen, Werte
	L._reset()
	L.active = true
	L.is_host = true
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna"), 3: L._new_player("Ben") }
	var tm := func(n: int, st: float = 4.0) -> Dictionary:
		return { "set_id": 500 + n, "file": "%d t.osz" % n, "version": "Hard", "title": "T", "artist": "A", "stars": st }
	L.tour_add_map(tm.call(1))
	_check(L.tournament == null, "ohne Turnier kein Pick")
	L.tour_create({ "maps": 5, "stars_lo": 3.0, "stars_hi": 5.0, "mods": { "NF": true } })
	_check(L.tournament != null and L.tournament.config.maps == 5, "Host legt Turnier an")
	L.tour_create({ "maps": 15 })
	_check(L.tournament.config.maps == 5, "zweites tour_create ignoriert")
	_check(L._srv_tour_add(9, tm.call(1)) != "", "Pick von Unbekanntem abgelehnt")
	_check(L._srv_tour_add(2, tm.call(1, 9.0)) != "", "Sterne ausserhalb abgelehnt")
	_check(L._srv_tour_add(2, { "set_id": "x", "file": "a", "version": "b", "stars": 4.0 }) != "", "Muellpaket abgelehnt")
	_check(L._srv_tour_add(2, tm.call(1)) == "" and L.tournament.pool.size() == 1, "gueltiger Pick")
	_check(L._srv_tour_add(3, tm.call(1)) != "", "Duplikat abgelehnt")
	_check(L._srv_tour_add(2, tm.call(2)) == "" and L._srv_tour_add(2, tm.call(3)) != "", "Pick-Limit ceil(5/3)=2")
	_check(L._srv_tour_ban(2, 0) != "", "Ban in PICK abgelehnt")
	_check(L._srv_tour_remove(3, 0) != "", "fremden Pick entfernen abgelehnt")
	L.tour_start_bans()
	_check(L.tournament.phase == Tournament.Phase.PICK, "Bans erst mit vollem Pool")
	L._srv_tour_add(3, tm.call(4))
	L._srv_tour_add(3, tm.call(5))
	L._srv_tour_add(1, tm.call(6))
	_check(L.tournament.is_pool_full(), "Pool voll")
	L.tour_start_bans()
	_check(L.tournament.phase == Tournament.Phase.BAN, "Host startet Bans")
	_check(L._srv_tour_add(1, tm.call(7)) != "", "Pick in BAN abgelehnt")
	L.is_host = false
	L.tour_begin()
	L.tour_cancel()
	L.is_host = true
	_check(L.tournament != null and L.tournament.phase == Tournament.Phase.BAN, "Nicht-Host kann nicht steuern")
	L.tour_begin()
	_check(L.tournament.phase == Tournament.Phase.BAN, "Start vor allen Bans abgelehnt")
	_check(L._srv_tour_ban(2, 99) != "" and L._srv_tour_ban(9, 0) != "", "Ban: Index/Sender geprueft")
	_check(L._srv_tour_ban(1, 0) == "" and L._srv_tour_ban(2, 0) != "", "Ban doppelt abgelehnt")
	L.pick_mods({ "SV": true })
	L.pick_map(tm.call(8))
	_check(L.sel_map.is_empty() and not bool(L.mods.SV), "im Turnier keine freie Map/Mods")
	L._srv_tour_ban(2, 1)
	L._srv_tour_ban(3, 2)
	L.tour_begin()
	_check(L.tournament.phase == Tournament.Phase.PLAY and not L.sel_map.is_empty(), "Runde 1: sel_map gesetzt")
	_check(bool(L.mods.NF) and not bool(L.mods.SV), "Mods aus Config")
	_check(not L.sel_map.has("by") and not L.sel_map.has("banned"), "sel_map ohne Turnier-Felder")
	# Runde: Spieler 3 geht, Rest meldet Finale
	for id in [1, 2, 3]:
		L.players[id].ready = true
	L.in_game = true
	L._tour_peers = [1, 2, 3]
	L.players[1].final = { "score": 500, "acc": 0.9, "combo": 10, "failed": false }
	L._tour_check_round()
	_check(L.tournament.rounds.is_empty(), "Runde offen bis alle fertig")
	L._on_peer_disconnected(3)
	L.players[2].final = { "score": 700, "acc": 0.8, "combo": 12, "failed": false }
	L._tour_check_round()
	_check(L.tournament.rounds.size() == 1 and L.tournament.phase == Tournament.Phase.BETWEEN, "Runde gewertet")
	var res1: Dictionary = L.tournament.rounds[0].results
	_check(res1[3].points == 0 and res1[2].points == 3 and res1[1].points == 2, "Gegangener 0 Punkte, Rest 3/2")
	_check(L.tournament.standings().size() == 3, "Gegangener bleibt in Tabelle")
	L.tour_next()
	_check(L.tournament.phase == Tournament.Phase.BETWEEN, "tour_next waehrend Runde ignoriert")
	L.in_game = false
	L.tour_next()
	_check(L.tournament.phase == Tournament.Phase.PLAY, "tour_next startet Runde 2")
	L.tour_cancel()
	_check(L.tournament == null, "Host bricht ab")
	L.in_game = false

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

	_modes(L)
	_nearest(L)

	L._reset()
	print("FAILED: %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _fin(sc: int, failed: bool = false) -> Dictionary:
	return { "score": sc, "acc": 0.9, "combo": 50, "failed": failed, "grade": "A" }


## Raum-Modi: Teams + Royale ueber die Lobby-API (Host-Zustand direkt).
func _modes(L) -> void:
	L._reset()
	L.active = true
	L.is_host = true
	L.crown_id = 1
	L.players = { 1: L._new_player("Host"), 2: L._new_player("Anna"), 3: L._new_player("Ben"), 4: L._new_player("Cleo") }
	L.sel_map = { "set_id": 11, "file": "11 a.osz", "version": "Hard", "stars": 4.0 }
	for id in L.players:
		L.players[id].ready = true
	L._mm_refresh()
	_check(L.room_kind() == MatchMode.Kind.FREE and L.mode_blocker() == "", "Modus startet Frei")
	# Teams
	L.set_room_mode(MatchMode.Kind.TEAMS)
	_check(L.room_kind() == MatchMode.Kind.TEAMS and L.mm.team_sizes() == [2, 2], "Teams: 2v2 automatisch")
	L.set_team(4, 0)
	L.set_team(3, 0)
	_check(L.mm.team_of[4] == 0 and L.mm.team_of[3] == 0, "Krone verschiebt Spieler")
	L.auto_balance_teams()
	_check(L.mm.team_sizes() == [2, 2], "Auto-Ausgleich 2v2")
	L.crown_id = 2
	var before: int = L.mm.team_of[4]
	L._srv_set_team(3, 4, 1 - before)
	_check(L.mm.team_of[4] == before, "Sender 3 ohne Krone: Wechsel von 4 abgewiesen")
	L._srv_set_team(4, 4, 1 - before)
	_check(L.mm.team_of[4] == 1 - before, "Spieler wechselt selbst")
	L.crown_id = 1
	for id in L.mm.order:
		L.mm.team_of[id] = 0
	_check(L.mode_blocker() != "" and not L.can_start(), "ein leeres Team blockiert den Start")
	L.auto_balance_teams()
	_check(L.mode_blocker() == "", "ausgeglichen: Start frei")
	# Runde: Teams werten nach Summe, Serie laeuft
	L.in_game = true
	L._mm_peers = L._mode_participants()
	for id in L.players:
		L.players[id].final = {}
	for id in [1, 2, 3]:
		L.players[id].final = _fin(1000 * id)
		L._mode_check_round()
		_check(L.mm.rounds_played == 0, "Runde wartet auf alle (%d)" % id)
	L.players[4].final = _fin(500)
	L._mode_check_round()
	_check(L.mm.rounds_played == 1 and L.mm.history.size() == 1, "Teams: Runde ausgewertet")
	_check(L._mm_peers.is_empty(), "Teilnehmerliste geleert")
	_check(L.mm.team_totals(L.live_results()) == L.mm.history[0].totals, "live_results = Endsumme")
	var rt := MatchMode.from_dict(L.mm.to_dict())
	_check(rt.history == L.mm.history, "Teamstand ueberlebt Sync")
	L.in_game = false
	# Serie beenden -> naechster Start beginnt frisch
	L.mm.team_wins = [2, 0]
	L.mm.rounds_played = 2
	_check(L.mm.series_over(), "Serie entschieden")
	L._mode_prepare_round()
	_check(L.mm.rounds_played == 0 and L.mm.team_wins == [0, 0] and L.mm.team_sizes() == [2, 2], "neue Serie behaelt Teams")
	# Royale
	L.set_room_mode(MatchMode.Kind.ROYALE)
	_check(L.mm.alive().size() == 4, "Royale: alle leben")
	L.in_game = true
	L._mm_peers = L._mode_participants()
	for id in L.players:
		L.players[id].final = _fin(5000 * id)
	L._mode_check_round()
	_check(L.mm.alive().size() == 3 and L.mm.is_spectator(1) and L.mm.out_order == [1], "Royale: Schwaechster fliegt")
	_check(L.mm.round_no == 2, "Royale: Runde 2")
	L.in_game = false
	L.players[1].ready = false
	_check(L.all_ready(), "Ausgeschiedener muss nicht bereit sein")
	for id in L.players:
		L.players[id].final = {}
	_check(L.ranked_players().size() == 3, "Ausgeschiedene Vorrunden-Spieler nicht in der Rangliste")
	# Spieler geht mitten in der Runde: zaehlt als Leaver
	L.in_game = true
	L._mm_peers = L._mode_participants()
	L.players[2].final = _fin(100)
	L.players[3].final = _fin(900)
	L._on_peer_disconnected(4)
	_check(L.mm.alive() == [2, 3] and L.mm.is_spectator(4) and L.mm.out_order == [1, 4], "Royale: Leaver fliegt, Schwaecherer bleibt")
	L._mm_peers = L._mode_participants()
	_check(L._mm_peers == [2, 3], "Teilnehmer: nur Lebende")
	L.players[2].final = _fin(100)
	L.players[3].final = _fin(900)
	L._mode_check_round()
	_check(L.mm.is_over() and L.mm.winner_peer in [2, 3], "Royale: Sieger steht fest")
	L.in_game = false
	L._mode_prepare_round()
	_check(not L.mm.is_over() and L.mm.alive().size() == L.players.size(), "Royale: neue Serie mit allen")
	# Wechsel zurueck + Turnier-Ausschluss
	L.set_room_mode(MatchMode.Kind.FREE)
	_check(L.room_kind() == MatchMode.Kind.FREE, "zurueck auf Frei")
	L.set_room_mode(MatchMode.Kind.TEAMS)
	L.tour_create({ "maps": 5, "stars_lo": 2.0, "stars_hi": 6.0 })
	_check(L.tournament != null and L.room_kind() == MatchMode.Kind.FREE, "Turnier setzt Raum-Modus auf Frei")
	L.set_room_mode(MatchMode.Kind.ROYALE)
	_check(L.room_kind() == MatchMode.Kind.FREE, "im Turnier kein Moduswechsel")
	# Ban-Sicht: Fremde Bans erst nach Aufdecken
	var t: Tournament = L.tournament
	for i in 5:
		t.pool.append({ "set_id": i, "file": "x%d.osz" % i, "version": "v", "title": "T%d" % i,
			"artist": "A", "stars": 3.0 + i, "by": 1, "online": false, "banned": false })
	t.set_players(L.players.keys(), {})
	_check(t.start_bans(), "Ban-Phase")
	t.ban(2, 0)
	var v1 := t.to_dict_for(1)
	_check(v1.get("hidden", false) and v1.bans.is_empty() and not v1.pool[0].banned, "Host sieht fremden Ban nicht")
	_check(Tournament.from_dict(v1).has_voted(2) and not Tournament.from_dict(v1).has_voted(3), "nur 'hat gewaehlt' sichtbar")
	var v2 := t.to_dict_for(2)
	_check(v2.pool[0].banned and v2.bans.size() == 1 and v2.bans[2] == 0, "Eigener Ban sichtbar")
	var msg: String = t.ban(3, 0)
	_check(msg.contains("gestrichen") or msg.to_lower().contains("already"), "Doppel-Ban: klare Meldung")
	t.ban(1, 4)
	t.ban(3, 1)
	_check(not t.to_dict_for(1).get("hidden", false) and t.to_dict_for(1).bans.size() == 3, "nach allen Bans aufgedeckt")


## Online-Pick ohne Diff-Name: ueberspringt Nicht-4K-Mania.
func _nearest(L) -> void:
	var mk := func(mode: int, cs: float) -> Dictionary:
		var b := Beatmap.new()
		b.general = { "Mode": mode }
		b.difficulty = { "CircleSize": cs }
		return { "osu_filename": "x%d_%d.osu" % [mode, int(cs)], "beatmap": b }
	var imp := { "ok": true, "difficulties": [mk.call(3, 7.0), mk.call(3, 4.0), mk.call(0, 4.0)] }
	var i: int = L._nearest_4k("res://nonexistent.osz", imp, 4.0)
	_check(i == 1, "Fallback-Diff ist 4K (nicht 7K)")
	var none := { "ok": true, "difficulties": [mk.call(3, 7.0)] }
	_check(L._nearest_4k("res://nonexistent.osz", none, 4.0) == -1, "nur 7K -> keine Diff")
