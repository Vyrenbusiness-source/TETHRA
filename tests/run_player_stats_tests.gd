extends SceneTree

## Tests fuer PlayerStatsCard (Paket, Summen, Karte) und Screenshot-Harness:
## mit --shot-out=<Praefix> (nach "--") entstehen Bilder des MP-Results-Screens
## (2 und 5 Spieler) und des Turnier-Endes (Bild + Detail), sonst nur Tests.

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	await process_frame
	var out := ""
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			out = a.substr(11)
	if out != "":
		await _shots(out)
		quit(0)
		return
	_pack_tests()
	_merge_tests()
	_duel_tests()
	await _card_tests()
	print("FAILED: %d" % _failed)
	quit(1 if _failed > 0 else 0)


func _pack_tests() -> void:
	var offs := PackedFloat32Array([-10.0, -5.0, 0.0, 5.0, 10.0, 200.0])
	var trace := PackedFloat32Array()
	for i in 100:
		trace.append(1.0 - float(i) * 0.001)
	var s := { "score": 900000, "accuracy": 0.9, "grade": "A", "max_combo": 321,
		"n_max": 50, "n300": 30, "n200": 10, "n100": 5, "n50": 2, "n_miss": 3, "mods": ["SV"] }
	var d := PlayerStatsCard.pack(s, offs, trace, 7, 2, false)
	_check(int(d.score) == 900000 and int(d.combo) == 321 and d.grade == "A", "Kennzahlen uebernommen")
	_check(int(d.early) == 2 and int(d.late) == 3, "frueh/spaet gezaehlt (0 ms neutral)")
	var bsum := 0
	for b in d.bins:
		bsum += int(b)
	_check(bsum == 6 and int(d.bins[PlayerStatsCard.BINS - 1]) == 1, "Histogramm: alle Treffer, Ausreisser im Randbin")
	# 100 Werte > 2 * TRACE: die ersten 4 % (Index 0..3) fallen weg, Start bei trace[4] = 0.996.
	_check(d.trace.size() == PlayerStatsCard.TRACE and int(d.trace[0]) == 996 and int(d.trace[39]) == 901, "Verlauf verdichtet, Start uebersprungen, Endstand erhalten")
	var short := PlayerStatsCard.resample(trace.slice(0, 60), PlayerStatsCard.TRACE)
	_check(short.size() == PlayerStatsCard.TRACE and int(short[0]) == 1000 and int(short[39]) == 941, "kurzer Verlauf ohne Start-Sprung")
	_check(absf(float(d.mean) - 200.0 / 6.0) < 0.01, "mittlere Abweichung")
	_check(float(d.ur) > 0.0 and int(d.h_ok) == 7 and int(d.h_drop) == 2, "UR + Holds")
	var f := PlayerStatsCard.pack(s, offs, trace, 0, 0, true)
	_check(f.grade == "F" and bool(f.failed), "Fail -> F")
	var e := PlayerStatsCard.pack(s, PackedFloat32Array(), PackedFloat32Array(), 0, 0, false)
	_check(float(e.ur) == 0.0 and e.trace.is_empty(), "ohne Treffer kein Absturz")


func _merge_tests() -> void:
	var a := PlayerStatsCard.fake(1, 0.9, 500)
	var b := PlayerStatsCard.fake(2, 0.4, 700)
	var m := PlayerStatsCard.merge([a, {}, b])
	_check(int(m.rounds) == 2 and m.trace.size() == 2, "leere Runde zaehlt nicht")
	_check(int(m.score) == int(a.score) + int(b.score), "Score summiert")
	_check(int(m.n_miss) == int(a.n_miss) + int(b.n_miss) and PlayerStatsCard.total_of(m) == 1200, "Zaehler summiert")
	_check(int(m.combo) == maxi(int(a.combo), int(b.combo)), "Kombo = Maximum")
	var lo := minf(float(a.ur), float(b.ur))
	var hi := maxf(float(a.ur), float(b.ur))
	_check(float(m.ur) >= lo and float(m.ur) <= hi, "UR gewichtet zwischen den Runden")
	var tot := PlayerStatsCard.total_of(m)
	var acc := float(300 * (int(m.n_max) + int(m.n300)) + 200 * int(m.n200) + 100 * int(m.n100) + 50 * int(m.n50)) / float(300 * tot)
	_check(absf(float(m.acc) - acc) < 0.0001, "Acc aus Summen")
	var short := PlayerStatsCard.merge([{ "score": 10, "acc": 0.5, "combo": 3, "failed": true }])
	_check(not short.has("ur") and int(short.fails) == 1, "alte Kurz-Pakete ohne Timing")


func _duel_tests() -> void:
	var a := { "score": 950000, "acc": 0.99, "combo": 500, "n_max": 900, "n300": 90, "n_miss": 2, "ur": 110.0 }
	var b := { "score": 900000, "acc": 0.97, "combo": 600, "n_max": 700, "n300": 280, "n_miss": 8, "ur": 140.0 }
	var rows := PlayerStatsCard.duel_rows(a, b)
	_check(rows.size() == 6, "Direktvergleich: 6 Kennzahlen mit UR")
	var w := {}
	for r in rows:
		w[str(r.cap)] = int(r.win)
		_check(float(r.share) >= 0.06 and float(r.share) <= 0.94, "Anteil begrenzt: " + str(r.cap))
	_check(w["Score"] == 1 and w["Max. Kombo"] == -1, "hoeher besser")
	_check(w["UR"] == 1 and w["Miss"] == 1, "UR und Miss: niedriger besser")
	_check(float(rows[0].share) > 0.5, "Balken zur Seite des Fuehrenden")
	var same := PlayerStatsCard.duel_rows(a, a)
	_check(int(same[0].win) == 0 and is_equal_approx(float(same[0].share), 0.5), "Gleichstand mittig")
	_check(PlayerStatsCard.duel_rows({ "score": 1 }, { "score": 2 }).size() == 5, "ohne Timing keine UR-Zeile")
	var box := PlayerStatsCard.duel("A", a, "B", b)
	root.add_child(box)
	_check(box.find_children("*", "Label", true, false).size() >= 20, "Direktvergleich gebaut")
	box.queue_free()


func _card_tests() -> void:
	var c := PlayerStatsCard.new()
	root.add_child(c)
	var a := PlayerStatsCard.fake(3, 0.7)
	c.setup({ "name": "Aria", "place": 2, "side": "B", "ref": PlayerStatsCard.fake(4, 0.9) }, a)
	await process_frame
	_check(c.get_child_count() == 1, "grosse Karte gebaut")
	var labels := c.find_children("*", "Label", true, false)
	var texts: Array = []
	for l in labels:
		texts.append((l as Label).text)
	_check(texts.has("Aria") and texts.has(UiTheme.fmt_score(int(a.score))), "Name + Score sichtbar")
	c.setup({ "name": "Ben", "pending": true, "live": 12345 }, {})
	await process_frame
	_check(c.find_children("*", "Label", true, false).size() >= 3, "wartende Karte")
	c.setup({ "name": "Cleo" }, PlayerStatsCard.sanitize({ "score": 5, "acc": 0.5, "combo": 1 }), true)
	await process_frame
	_check(c.get_child_count() == 1, "Kurz-Paket ohne Timing: kompakt ohne Fehler")
	c.queue_free()


# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------

## Neue Texte aus translations/stats.csv laden (Registrierung macht der Hauptagent).
func _load_csv() -> void:
	var f := FileAccess.open("res://translations/stats.csv", FileAccess.READ)
	if f == null:
		return
	var de := Translation.new()
	de.locale = "de"
	var en := Translation.new()
	en.locale = "en"
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0] != "":
			de.add_message(row[0], row[1])
			en.add_message(row[0], row[2])
	TranslationServer.add_translation(de)
	TranslationServer.add_translation(en)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT " + path)


func _board(n: int) -> Array:
	var who := ["Kenji", "Aria", "Mara", "Tobi", "Lena"]
	var skill := [0.93, 0.85, 0.72, 0.6, 0.45]
	var out: Array = []
	for i in n:
		var st := PlayerStatsCard.fake(11 + i * 5, skill[i], 1250)
		var e := { "id": i + 2, "name": who[i], "final": st, "score": int(st.score) }
		if n == 5 and i == 4:
			e.final = {}
			e.score = 612340
		out.append(e)
	return out


func _shots(out: String) -> void:
	_load_csv()
	root.theme = UiTheme.build_theme()
	var lang := "de" if TranslationServer.get_locale().begins_with("de") else "en"
	var res := "%dx%d" % [root.size.x, root.size.y]
	var tag := "%s_%s_%s" % [out, lang, res]
	for n in [2, 5]:
		var b := _board(n)
		var me: Dictionary = b[1]
		var rs: Control = load("res://scripts/ui/results_screen.gd").new()
		root.add_child(rs)
		rs.show_results({ "is_fail": false, "s": { "score": me.final.score, "accuracy": me.final.acc,
				"grade": me.final.grade, "max_combo": me.final.combo, "n_miss": me.final.n_miss },
			"pp": -1.0, "title": "Neon Skyline", "artist": "Kairo", "version": "4K Hard",
			"player": me.name, "date": "2026-11-07T20:15:00", "lobby": true, "allow_retry": false,
			"can_replay": true, "my_id": me.id, "final": me.final })
		await create_timer(0.3).timeout
		rs.set_board(b, int(me.id), "SV")
		rs.set_placement(tr("PLATZ %d VON %d") % [2, n], false)
		await create_timer(1.6).timeout
		await _snap("%s_results%d.png" % [tag, n])
		rs.queue_free()
		await process_frame
	# Turnier-Ende mit Detail-Stats (Fake-Runden).
	var TourS: GDScript = load("res://scripts/net/tournament.gd")
	var t = TourS.new()
	var names := { 2: "Aria", 3: "Kenji", 4: "Mara", 5: "Tobi", 6: "Lena" }
	t.config = { "maps": 6, "stars_lo": 3.0, "stars_hi": 5.0, "mods": { "SV": true, "NF": false } }
	t.player_names = names
	var titles := ["Neon Skyline", "Gravity Bloom", "Echoes of Tomorrow", "Paper Planes", "Nightdrive", "Crystal Rain"]
	for i in 6:
		t.pool.append({ "set_id": 900000 + i, "file": "", "version": "Insane", "title": titles[i],
			"artist": "Kairo", "stars": 3.2 + i * 0.3 })
	t.order = [0, 1, 2, 3, 4, 5]
	var base := { 2: 0.95, 3: 0.97, 4: 0.92, 5: 0.9, 6: 0.86 }
	for r in 6:
		t.phase = TourS.Phase.PLAY
		t.current_round = r
		var res_r := {}
		for peer in names:
			var acc: float = base[peer] - 0.012 * float((r * 3 + int(peer)) % 4)
			var st := PlayerStatsCard.fake(int(peer) * 31 + r * 7, clampf((acc - 0.8) / 0.2, 0.0, 1.0), 900 + r * 60, r == 2 and peer == 6)
			res_r[peer] = { "score": int(st.score), "accuracy": float(st.acc), "max_combo": int(st.combo),
				"failed": bool(st.failed), "name": names[peer], "absent": r == 5 and peer == 5 }
			if not res_r[peer].absent:
				res_r[peer]["stats"] = st
		t.record_round(res_r)
		# record_round kopiert nur die Grundwerte: Stats wie Lobby._tour_check_round nachtragen.
		var saved: Dictionary = t.rounds.back().results
		for peer in res_r:
			if res_r[peer].has("stats"):
				saved[peer]["stats"] = res_r[peer].stats
	var end: Control = load("res://scripts/ui/tournament_end.gd").new(t, "Turnier · Freitagsrunde")
	end.harness = true
	end.my_id = 3
	root.add_child(end)
	await create_timer(1.2).timeout
	await _snap("%s_tend.png" % tag)
	end.save_png("%s_tend_image.png" % tag)
	var st0: Array = t.standings()
	end.open_detail(int(st0[1].peer))
	await create_timer(0.6).timeout
	await _snap("%s_tdetail.png" % tag)
	end.open_detail(int(st0[1].peer), 2)
	await create_timer(0.4).timeout
	await _snap("%s_tdetail_map.png" % tag)
	end.queue_free()
