extends SceneTree

## Headless-Tests fuer die Turnier-Logik (Pick-Regeln, Bans, Punkte, Tabelle, Sync)
## und die Auto-Auswahl-Filter (Long Notes, Laenge, BPM; lokal und online).

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
	var gone: Dictionary = t.pool[0].duplicate()
	_check(t.remove_map(0, 1) and t.pool.size() == 4, "eigenen Pick entfernen")
	_check(t.remove_map(t.pool.size() - 1, 1), "Host darf fremden Pick entfernen")
	# Entfernte Maps merken (Auto-Fill nimmt sie nicht wieder)
	_check(t.is_removed(gone) and not t.is_removed(_map(77)), "entfernte Map gemerkt")
	_check(Tournament.from_dict(t.to_dict()).is_removed(gone), "entfernte Map ueberlebt Sync")
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
	_check(tb.ban(1, 99) != "" and tb.ban(1, -2) != "", "Ban-Index ausserhalb abgewiesen")
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

	# --- Kein Ban (Skip)
	var ts := _tour(5, [1, 2, 3])
	_fill(ts, [1, 2, 3])
	ts.start_bans()
	_check(ts.ban(1, -1) == "" and ts.has_voted(1) and ts.remaining() == 5, "Skip zaehlt als gewaehlt, keine Map weg")
	_check(not ts.all_banned([1, 2, 3]), "Skip: noch nicht alle")
	var sv2 := Tournament.from_dict(ts.to_dict_for(2))
	_check(sv2.hidden and sv2.has_voted(1) and not sv2.has_voted(2), "Skip: Sicht zeigt nur 'hat gewaehlt'")
	var sv1 := Tournament.from_dict(ts.to_dict_for(1))
	_check(sv1.bans.get(1, 0) == -1, "Skip: eigene Sicht kennt den Skip")
	_check(ts.ban(1, 2) == "" and ts.pool[2].banned, "Skip -> Ban aendern")
	_check(ts.ban(1, -1) == "" and not ts.pool[2].banned and ts.remaining() == 5, "Ban -> Skip gibt Map frei")
	ts.ban(2, 0)
	ts.ban(3, -1)
	_check(ts.all_banned([1, 2, 3]), "gemischt: alle gewaehlt")
	_check(ts.remaining() == 4 and ts.play_order().size() == 4, "gemischt: 1 Ban, 4 spielbar")
	_check(ts.ban(1, 3) != "" and ts.ban(1, -1) != "" , "nach allen: Skip nicht mehr aenderbar")
	var tn := _tour(5, [1, 2])
	_fill(tn, [1, 2])
	tn.start_bans()
	tn.ban(1, -1)
	tn.ban(2, -1)
	_check(tn.all_banned([1, 2]) and tn.remaining() == 5, "alle skippen: alle 5 Maps")
	_check(tn.play_order().size() == 5, "alle skippen: alle Maps spielbar")
	var first_n := tn.next_map()
	_check(not first_n.is_empty() and tn.order.size() == 5 and tn.phase == Tournament.Phase.PLAY, "alle skippen: Turnier startet")
	var tn2 := Tournament.from_dict(tn.to_dict())
	_check(tn2.order == tn.order and tn2.bans == tn.bans, "Skip ueberlebt Netzformat")

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

	# --- Auto-Auswahl-Filter: Validierung
	var f0 := Tournament.clean_filters({})
	_check(f0 == { "ln_lo": 0, "ln_hi": 100, "len_max": 0, "bpm_lo": 0, "bpm_hi": 0 }, "Filter: Standard = keine Filter")
	_check(not Tournament.filters_active(f0) and Tournament.ln_preset(f0) == "any", "Filter: Standard inaktiv, Stufe any")
	var fj := Tournament.clean_filters({ "ln_lo": 80, "ln_hi": 20, "len_max": 99999, "bpm_lo": "x", "bpm_hi": -5 })
	_check(fj.ln_lo == 20 and fj.ln_hi == 80 and fj.len_max == Tournament.LEN_MAX_S and fj.bpm_lo == 0 and fj.bpm_hi == 0,
		"Filter: Bereich getauscht, Laenge geklemmt, Muell -> 0")
	var fsw := Tournament.clean_filters({ "bpm_lo": 220, "bpm_hi": 150, "ln_lo": 0.4, "ln_hi": NAN })
	_check(fsw.bpm_lo == 150 and fsw.bpm_hi == 220 and fsw.ln_lo == 0 and fsw.ln_hi == 100, "Filter: BPM getauscht, NaN -> Standard")
	var fopen := Tournament.clean_filters({ "bpm_lo": 180, "bpm_hi": 0 })
	_check(fopen.bpm_lo == 180 and fopen.bpm_hi == 0, "Filter: BPM nach oben offen bleibt offen")
	var tfl := Tournament.create({ "maps": 5, "filters": { "ln_lo": 0, "ln_hi": 15, "len_max": 180, "bpm_lo": 120, "bpm_hi": 200 } })
	_check(Tournament.ln_preset(tfl.config.filters) == "few" and Tournament.filters_active(tfl.config.filters), "Filter in config, Stufe few")
	var tfb := Tournament.from_dict(tfl.to_dict())
	_check(tfb.config.filters == tfl.config.filters and tfb.to_dict() == tfl.to_dict(), "Filter: Netz-Roundtrip identisch")
	_check(Tournament.from_dict({ "config": { "filters": "kaputt" } }).config.filters == f0, "Filter: kaputtes Netzformat -> Standard")
	var tm2 := Tournament.create({ "filters": { "ln_hi": 15 } })
	_check(tm2.config.maps == 10 and tm2.config.filters.ln_hi == 15, "Filter: Teil-Angabe ergaenzt")

	# --- Filter wirken (Rang 0 passt, 1 = keine Daten, -1 = passt nicht)
	var ff: Dictionary = tfl.config.filters
	_check(Tournament.filter_rank(ff, { "ln": 10, "len_s": 150, "bpm": 170 }) == 0, "Filter: passende Map")
	_check(Tournament.filter_rank(ff, { "ln": 40, "len_s": 150, "bpm": 170 }) == -1, "Filter: zu viele Long Notes")
	_check(Tournament.filter_rank(ff, { "ln": 10, "len_s": 240, "bpm": 170 }) == -1, "Filter: zu lang")
	_check(Tournament.filter_rank(ff, { "ln": 10, "len_s": 150, "bpm": 230 }) == -1, "Filter: zu schnell")
	_check(Tournament.filter_rank(ff, { "ln": 10, "len_s": 150, "bpm": 100 }) == -1, "Filter: zu langsam")
	_check(Tournament.filter_rank(ff, { "ln": -1, "len_s": 150, "bpm": 170 }) == 1, "Filter: LN unbekannt -> nachrangig")
	_check(Tournament.filter_rank(ff, {}) == 1, "Filter: keine Daten -> nachrangig")
	_check(Tournament.filter_rank(ff, { "ln": -1, "len_s": 999, "bpm": 170 }) == -1, "Filter: unbekannt + zu lang -> raus")
	_check(Tournament.filter_rank(f0, {}) == 0, "Ohne Filter passt alles")
	var fmany := Tournament.clean_filters({ "ln_lo": 45, "ln_hi": 100 })
	_check(Tournament.filter_rank(fmany, { "ln": 60 }) == 0 and Tournament.filter_rank(fmany, { "ln": 10 }) == -1, "Filter: viele LN")

	# --- Online: rohe Mirror-Antwort (osu!-API-v2-Format)
	var item := { "id": 4242, "title": "Song", "artist": "Band", "status": "ranked", "bpm": 175,
		"beatmaps": [
			{ "mode_int": 3, "cs": 4, "difficulty_rating": 3.6, "version": "Hard", "count_circles": 900, "count_sliders": 100, "total_length": 150, "bpm": 175 },
			{ "mode_int": 3, "cs": 4, "difficulty_rating": 4.4, "version": "LN Insane", "count_circles": 500, "count_sliders": 500, "total_length": 150, "bpm": 175 },
			{ "mode_int": 3, "cs": 4, "difficulty_rating": 5.9, "version": "Expert", "count_circles": 1500, "count_sliders": 10, "total_length": 150, "bpm": 175 },
			{ "mode_int": 3, "cs": 7, "difficulty_rating": 4.0, "version": "7K", "count_circles": 900, "count_sliders": 0, "total_length": 150, "bpm": 175 },
		] }
	var op := Tournament.online_pick(item, 3.0, 5.0, ff)
	_check(op.get("version", "") == "Hard" and int(op.get("rank", -1)) == 0 and op.get("ln", -1) == 10,
		"Online: wenig LN waehlt die passende 4K-Diff im Sternbereich")
	_check(op.get("set_id", 0) == 4242 and op.get("file", "") == "mirror_4242.osz" and op.get("online", false) and op.get("len_s", 0) == 150 and op.get("bpm", 0) == 175,
		"Online: sel_map-Daten mit Kennwerten")
	var op_any := Tournament.online_pick(item, 3.0, 5.0, f0)
	_check(op_any.get("version", "") == "LN Insane", "Online: ohne Filter hoechste Diff im Bereich")
	_check(Tournament.online_pick(item, 3.0, 5.0, fmany).get("version", "") == "LN Insane", "Online: viele LN")
	_check(Tournament.online_pick(item, 6.5, 8.0, f0).is_empty(), "Online: nichts im Sternbereich -> leer")
	var bare := { "id": 7, "title": "X", "artist": "Y", "beatmaps": [ { "mode_int": 3, "cs": 4, "difficulty_rating": 4.0, "version": "N" } ] }
	var opb := Tournament.online_pick(bare, 3.0, 5.0, ff)
	_check(int(opb.get("rank", -1)) == 1 and not opb.has("ln"), "Online: API ohne Kennwerte -> nachrangig, keine erfundenen Werte")
	var tadd := _tour(5, [1, 2], 2.0, 6.0)
	var od := op.duplicate()
	od.erase("rank")
	_check(tadd.add_map(od, 1) == "" and tadd.pool[0].ln == 10 and tadd.pool[0].bpm == 175, "add_map uebernimmt Kennwerte")
	var junkm := _map(50)
	junkm["ln"] = "viel"
	junkm["bpm"] = -3
	junkm["len_s"] = 1e9
	_check(tadd.add_map(junkm, 2) == "" and not tadd.pool[1].has("ln") and not tadd.pool[1].has("bpm")
		and tadd.pool[1].len_s == Tournament.LEN_MAX_S * 4, "add_map: Muell-Kennwerte verworfen/geklemmt")

	# --- Bibliothek: Long Notes + BPM je Diff
	var bm := Beatmap.new()
	var tp1 := TimingPoint.new()
	tp1.time = 0.0
	tp1.beat_length = 500.0
	tp1.uninherited = true
	var tp2 := TimingPoint.new()
	tp2.time = 10000.0
	tp2.beat_length = 300.0
	tp2.uninherited = true
	bm.timing_points.append(tp1)
	bm.timing_points.append(tp2)
	for k in 9:
		var nn := ManiaNote.new()
		nn.time = float(k) * 5000.0
		nn.is_hold = k % 3 == 0
		nn.hold_end = nn.time + 400.0
		bm.hit_objects.append(nn)
	_check(MapLibrary.hold_count(bm) == 3, "Bibliothek: Long Notes gezaehlt")
	_check(absf(MapLibrary.main_bpm(bm) - 200.0) < 0.01, "Bibliothek: vorherrschendes Tempo")
	var ms := MapSet.from_dict("x/1 a.osz", { "title": "A", "diffs": [
		{ "version": "Old", "osu_filename": "o.osu", "stars": 3.5, "mode": 3, "notes": 1000, "duration_ms": 150000.0 },
		{ "version": "New", "osu_filename": "n.osu", "stars": 4.5, "mode": 3, "notes": 1000, "duration_ms": 200000.0, "holds": 420, "bpm": 180.0 } ] })
	_check(ms.needs_stats() and ms.stats_at(0).ln == -1 and ms.stats_at(0).len_s == 150, "MapSet: alter Eintrag ohne LN -> unbekannt")
	_check(ms.stats_at(1) == { "ln": 42, "len_s": 200, "bpm": 180 }, "MapSet: Kennwerte je Diff")
	ms.apply_sv({ "o.osu": { "sv": true, "holds": 50, "bpm": 150.0 }, "n.osu": false })
	_check(not ms.needs_stats() and ms.stats_at(0).ln == 5 and ms.has_sv() and ms.stats_at(1).ln == 42, "MapSet: Nachlauf ergaenzt Kennwerte")
	var lib := MapLibrary.new("Z:/gibt/es/nicht")
	lib.mapsets.append(ms)
	var lc := Tournament.local_candidates(lib, 3.0, 5.0, ff, Callable())
	_check(lc.size() == 1 and lc[0][1].version == "Old" and int(lc[0][0]) == 0, "Lokal: Filter wirkt (LN + Laenge)")
	var lc2 := Tournament.local_candidates(lib, 3.0, 5.0, f0, func(d): return d.version == "Old")
	_check(lc2.size() == 1 and lc2[0][1].version == "New" and lc2[0][1].ln == 42, "Lokal: ohne Filter + Skip, Daten mit Kennwerten")

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

