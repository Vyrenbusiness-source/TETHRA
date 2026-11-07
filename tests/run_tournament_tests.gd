extends SceneTree

## Headless-Tests fuer die Turnier-Logik (Pick-Regeln, Bans, Punkte, Tabelle, Sync).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _map(n: int, stars: float = 4.0) -> Dictionary:
	return { "set_id": 100 + n, "file": "%d m.osz" % n, "version": "Hard", "title": "T%d" % n,
		"artist": "A", "stars": stars }


func _tour(maps: int, ids: Array, lo: float = 2.0, hi: float = 6.0) -> Tournament:
	var t := Tournament.create({ "maps": maps, "stars_lo": lo, "stars_hi": hi, "seed": 7 })
	var names := {}
	for id in ids:
		names[id] = "P%d" % id
	t.set_players(ids, names)
	return t


func _fill(t: Tournament, ids: Array) -> void:
	var n := 0
	while not t.is_pool_full():
		var by: int = ids[n % ids.size()]
		var e := t.add_map(_map(n), by)
		if e != "":
			print("fill err ", e)
			return
		n += 1


func _init() -> void:
	# --- Konfiguration
	var c := Tournament.clean_config({ "maps": 7, "stars_lo": 9.0, "stars_hi": 3.0 })
	_check(c.maps == 10 and c.stars_lo == 3.0 and c.stars_hi == 9.0, "Config: ungueltige Mapzahl -> 10, lo/hi getauscht")
	_check(Tournament.clean_config({ "maps": 5 }).maps == 5 and Tournament.clean_config({ "maps": 15 }).maps == 15, "Config: 5 und 15 erlaubt")

	# --- Pick-Regeln
	var t := _tour(10, [1, 2, 3])
	_check(t.add_map(_map(1), 1) == "", "Pick ok")
	_check(t.add_map(_map(1), 2) != "", "Duplikat set_id+version abgewiesen")
	_check(t.add_map(_map(2, 1.0), 2) != "", "Sterne zu niedrig abgewiesen")
	_check(t.add_map(_map(2, 7.5), 2) != "", "Sterne zu hoch abgewiesen")
	_check(t.add_map({ "set_id": 5, "file": "x", "version": "v" }, 2) != "", "Sterne fehlen abgewiesen")
	_check(t.add_map({ "set_id": 5, "file": 3, "version": "v", "stars": 4.0 }, 2) != "", "falscher Typ abgewiesen")
	var other_ver := _map(1)
	other_ver.version = "Insane"
	_check(t.add_map(other_ver, 1) == "", "gleiche set_id, andere Version ok")
	# 10 Maps / 3 Spieler -> ceil = 4 pro Spieler
	_check(t.max_per_player() == 4, "Limit ceil(10/3) = 4")
	t.add_map(_map(3), 1)
	t.add_map(_map(4), 1)
	_check(t.picks_of(1) == 4 and t.add_map(_map(5), 1) != "", "5. Pick von Spieler 1 abgewiesen")
	_check(t.add_map(_map(5), 2) == "", "Spieler 2 darf noch")
	_check(not t.remove_map(0, 2), "fremden Pick nicht entfernen")
	_check(t.remove_map(0, 1) and t.pool.size() == 4, "eigenen Pick entfernen")
	_check(t.remove_map(t.pool.size() - 1, 1), "Host darf fremden Pick entfernen")
	# Pool nicht ueber maps
	var t5 := _tour(5, [1])
	_fill(t5, [1])
	_check(t5.is_pool_full() and t5.add_map(_map(99), 1) != "", "Pool nicht ueber maps")
	# Auto-fill: Host ueber Limit
	var t2 := _tour(5, [1, 2])
	t2.add_map(_map(1), 2)
	t2.add_map(_map(2), 2)
	t2.add_map(_map(3), 2)
	_check(t2.add_map(_map(4), 2) != "", "Limit 3 bei 5 Maps / 2 Spielern")
	t2.add_map(_map(4), 1)
	t2.add_map(_map(5), 1)
	_check(t2.is_pool_full(), "Pool voll")

	# --- Phasen: Pick nur in PICK, Ban nur in BAN
	var tb := _tour(5, [1, 2, 3])
	_check(tb.ban(1, 0) != "", "Ban in PICK abgewiesen")
	_fill(tb, [1, 2, 3])
	_check(tb.start_bans() and tb.phase == Tournament.Phase.BAN, "Ban-Phase gestartet")
	_check(tb.add_map(_map(50), 1) != "", "Pick in BAN abgewiesen")
	_check(tb.ban(9, 0) != "", "Nicht-Spieler kann nicht bannen")
	_check(tb.ban(1, 99) != "" and tb.ban(1, -1) != "", "Ban-Index ausserhalb abgewiesen")
	_check(tb.ban(1, 0) == "" and tb.pool[0].banned, "Ban gesetzt")
	_check(tb.ban(2, 0) != "", "bereits gebannte Map nicht nochmal")
	_check(tb.ban(2, 0).contains("gestrichen") and tb.ban(2, 0).contains("andere"), "Doppel-Ban: klare deutsche Meldung")
	var hv := tb.to_dict_for(2)
	_check(hv.hidden and hv.bans.is_empty() and not hv.pool[0].banned, "Sicht: fremder Ban verdeckt")
	var hv1 := Tournament.from_dict(tb.to_dict_for(2))
	_check(hv1.hidden and hv1.has_voted(1) and not hv1.has_voted(2) and hv1.remaining() == tb.pool.size(), "Sicht: nur 'hat gewaehlt'")
	_check(tb.ban(1, 1) == "" and not tb.pool[0].banned and tb.pool[1].banned, "Ban aendern gibt alte Map frei")
	_check(tb.ban(1, 1) == "", "gleichen Ban wiederholen ok")
	_check(not tb.all_banned([1, 2, 3]), "noch nicht alle gebannt")
	tb.ban(2, 2)
	tb.ban(3, 3)
	_check(tb.all_banned([1, 2, 3]), "alle gebannt")
	var rv := tb.to_dict_for(2)
	_check(not rv.has("hidden") and rv.pool[3].banned and rv.bans.size() == 3, "nach allen Bans: volle Sicht")
	_check(tb.ban(1, 0) != "", "nach allen Bans keine Aenderung")
	_check(tb.remaining() == 2, "2 Maps uebrig")

	# --- Grenzfall: 1 Map bleibt uebrig (5 Maps, 8 Spieler)
	var ids8 := [1, 2, 3, 4, 5, 6, 7, 8]
	var t8 := _tour(5, ids8)
	_fill(t8, ids8)
	t8.start_bans()
	var ok_cnt := 0
	for k in 8:
		if t8.ban(ids8[k], k % 5) == "":
			ok_cnt += 1
	_check(t8.remaining() >= 1, "8 Spieler / 5 Maps: mindestens 1 Map bleibt")
	var t8b := _tour(5, ids8)
	_fill(t8b, ids8)
	t8b.start_bans()
	for k in 4:
		_check(t8b.ban(ids8[k], k) == "", "Ban %d ok" % k)
	_check(t8b.remaining() == 1, "genau 1 Map uebrig")
	_check(t8b.ban(5, 4) != "", "5. Ban abgewiesen (letzte Map)")
	_check(t8b.all_banned(ids8), "Bans fertig, wenn nur 1 Map uebrig")
	_check(t8b.play_order().size() == 1, "Reihenfolge hat 1 Map")
	var first := t8b.next_map()
	_check(not first.is_empty() and t8b.phase == Tournament.Phase.PLAY, "next_map startet Runde")

	# --- Reihenfolge deterministisch
	var ta := _tour(10, [1, 2])
	_fill(ta, [1, 2])
	ta.start_bans()
	ta.ban(1, 0)
	ta.ban(2, 1)
	var o1 := ta.play_order()
	var o2 := Tournament.from_dict(ta.to_dict()).play_order()
	_check(o1 == o2 and o1.size() == 8, "play_order deterministisch, 8 Maps")
	_check(not o1.has(0) and not o1.has(1), "gebannte nicht in der Reihenfolge")
	var sorted := o1.duplicate()
	sorted.sort()
	_check(sorted == [2, 3, 4, 5, 6, 7, 8, 9], "Reihenfolge = Permutation der freien Maps")

	# --- Runden + Punkte
	var tr := _tour(5, [1, 2, 3, 4])
	_fill(tr, [1, 2, 3, 4])
	tr.start_bans()
	tr.ban(1, 0)
	tr.ban(2, 1)
	tr.ban(3, 2)
	tr.ban(4, 3)
	_check(tr.next_map().has("file") and tr.current_round == 0, "Runde 0")
	tr.record_round({
		1: { "score": 900, "accuracy": 0.9, "max_combo": 10, "failed": false, "name": "P1" },
		2: { "score": 800, "accuracy": 0.8, "max_combo": 10, "failed": false, "name": "P2" },
		3: { "score": 800, "accuracy": 0.7, "max_combo": 10, "failed": false, "name": "P3" },
		4: { "score": 9999, "accuracy": 0.1, "max_combo": 1, "failed": true, "name": "P4" } })
	var rr: Dictionary = tr.rounds[0].results
	_check(rr[1].points == 4 and rr[1].place == 1, "Platz 1 = Spielerzahl Punkte")
	_check(rr[2].points == 3 and rr[3].points == 3 and rr[2].place == 2 and rr[3].place == 2, "Gleichstand: gleicher Platz, gleiche Punkte")
	_check(rr[4].points == 0, "failed = 0 Punkte")
	_check(tr.phase == Tournament.Phase.END, "letzte Runde -> END")
	_check(tr.next_map().is_empty(), "keine Map mehr")

	# 2 Runden: mehrere Maps
	var tm := _tour(5, [1, 2, 3])
	_fill(tm, [1, 2, 3])
	tm.start_bans()
	tm.ban(1, 0)
	tm.ban(2, 1)
	tm.ban(3, 2)
	tm.next_map()
	tm.record_round({
		1: { "score": 500, "accuracy": 0.5, "max_combo": 5, "failed": false, "name": "P1" },
		2: { "score": 700, "accuracy": 0.7, "max_combo": 5, "failed": false, "name": "P2" },
		3: { "score": 100, "accuracy": 0.1, "max_combo": 5, "failed": false, "name": "P3" } })
	_check(tm.phase == Tournament.Phase.BETWEEN, "nach Runde 1 BETWEEN")
	tm.record_round({ 1: { "score": 1, "name": "X" } })
	_check(tm.rounds.size() == 1, "record_round nur in PLAY")
	tm.next_map()
	# P3 ist gegangen: 0 Punkte, bleibt in der Tabelle
	tm.record_round({
		1: { "score": 600, "accuracy": 0.6, "max_combo": 5, "failed": false, "name": "P1" },
		2: { "score": 600, "accuracy": 0.6, "max_combo": 5, "failed": false, "name": "P2" },
		3: { "score": 0, "accuracy": 0.0, "max_combo": 0, "failed": true, "name": "P3" } })
	var st := tm.standings()
	# P1: 2+3=5, P2: 3+3=6, P3: 1+0=1
	_check(st.size() == 3 and st[0].peer == 2 and st[0].points == 6 and st[0].rank == 1, "Tabelle: P2 vorn (6)")
	_check(st[1].peer == 1 and st[1].points == 5 and st[1].rank == 2, "Tabelle: P1 zweiter (5)")
	_check(st[2].peer == 3 and st[2].points == 1 and st[2].rank == 3, "Tabelle: P3 letzter (1)")
	_check(st[0].wins == 2 and st[1].wins == 1 and st[1].total_score == 1100, "wins und total_score")
	_check(absf(st[0].avg_acc - 0.65) < 0.001, "avg_acc")
	var mw := tm.map_winners()
	_check(mw.size() == 2 and mw[0].winner_name == "P2" and mw[0].score == 700 and mw[0].map.has("file"), "map_winners")

	# Tie-Break per total_score, gleiche Werte -> gleicher Rang
	var tt := _tour(5, [1, 2, 3])
	_fill(tt, [1, 2, 3])
	tt.start_bans()
	tt.ban(1, 0)
	tt.ban(2, 1)
	tt.ban(3, 2)
	tt.next_map()
	tt.record_round({
		1: { "score": 100, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P1" },
		2: { "score": 100, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P2" },
		3: { "score": 50, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P3" } })
	var s2 := tt.standings()
	_check(s2[0].rank == 1 and s2[1].rank == 1 and s2[2].rank == 3, "Gleichstand: gleicher Rang, dann 3")
	var t4 := _tour(5, [1, 2, 3])
	_fill(t4, [1, 2, 3])
	t4.start_bans()
	t4.ban(1, 0)
	t4.ban(2, 1)
	t4.ban(3, 2)
	t4.next_map()
	t4.record_round({
		1: { "score": 1000, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P1" },
		2: { "score": 900, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P2" },
		3: { "score": 10, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P3" } })
	t4.next_map()
	t4.record_round({
		1: { "score": 100, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P1" },
		2: { "score": 2000, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P2" },
		3: { "score": 10, "accuracy": 1.0, "max_combo": 5, "failed": false, "name": "P3" } })
	var s3 := t4.standings()
	_check(s3[0].points == 5 and s3[1].points == 5 and s3[0].peer == 2 and s3[1].peer == 1, "Tie-Break: gleiche Punkte -> Gesamtscore")

	# Regression Endbild: alle Spieler durchgefallen -> Score entscheidet, Sieger ist immer ein Name
	var tf := _tour(5, [1, 2])
	_fill(tf, [1, 2])
	tf.start_bans()
	tf.ban(1, 0)
	tf.ban(2, 1)
	tf.next_map()
	tf.record_round({
		1: { "score": 500, "accuracy": 0.8, "max_combo": 5, "failed": false, "name": "A" },
		2: { "score": 400, "accuracy": 0.7, "max_combo": 5, "failed": false, "name": "B" } })
	tf.next_map()
	tf.record_round({
		1: { "score": 100, "accuracy": 0.4, "max_combo": 5, "failed": true, "name": "A" },
		2: { "score": 300, "accuracy": 0.5, "max_combo": 5, "failed": true, "name": "B" } })
	var fw := tf.map_winners()
	_check(fw[1].winner_name == "B" and fw[1].score == 300, "alle failed: Sieger nach Score, nie leer")
	var fs := tf.standings()
	_check(fs[0].points == 3 and fs[0].wins == 1 and fs[1].points == 3 and fs[1].wins == 1, "alle failed: Punkte nach Score")
	_check(absf(fs[0].avg_acc - 0.6) < 0.001, "Fail zaehlt mit echter Acc")
	# Gegangene Spieler: keine Acc-Wertung, kein Sieg, keine Punkte
	var tg := _tour(5, [1, 2])
	_fill(tg, [1, 2])
	tg.start_bans()
	tg.ban(1, 0)
	tg.ban(2, 1)
	tg.next_map()
	tg.record_round({
		1: { "score": 0, "accuracy": 0.0, "max_combo": 0, "failed": true, "absent": true, "name": "A" },
		2: { "score": 0, "accuracy": 0.0, "max_combo": 0, "failed": true, "absent": true, "name": "B" } })
	var sg := tg.standings()
	_check(sg[0].points == 0 and sg[0].avg_acc == 0.0 and sg[0].wins == 0, "Gegangene: keine Punkte/Siege")

	# --- to_dict-Roundtrip
	var d := tm.to_dict()
	var back := Tournament.from_dict(d)
	_check(back.to_dict() == d, "to_dict/from_dict Roundtrip identisch")
	_check(back.standings() == tm.standings() and back.map_winners() == tm.map_winners(), "Roundtrip: Tabelle und Sieger gleich")
	var back2 := Tournament.from_dict({})
	_check(back2.phase == Tournament.Phase.PICK and back2.pool.is_empty(), "from_dict({}) = leeres Turnier")
	var junk := Tournament.from_dict({ "phase": 99, "config": { "maps": 3 } })
	_check(junk.phase == Tournament.Phase.END and junk.config.maps == 10, "from_dict klemmt Werte")

	print("Tournament-Tests: ", "OK" if _failed == 0 else "%d FEHLER" % _failed)
	quit(1 if _failed > 0 else 0)

