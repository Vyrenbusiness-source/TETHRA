extends SceneTree

## Headless-Tests fuer Rally: Chart aus Standard- und 4K-Map, Flugbahn (Ball exakt
## zur Notenzeit beim Spieler, Gegnerschlag in der Mitte), Tastenregel, Schmetterball,
## Aufladen, Zusammenfassen, Wertung (ScoreV1), Replay deterministisch, Autoplay = SS,
## Sterne-Skala.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_rally_tests.gd

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	quit(1 if _failed > 0 else 0)
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _near(a: float, b: float, label: String, eps: float = 0.0001) -> void:
	_ok(absf(a - b) <= eps, "%s (erwartet %f, war %f)" % [label, b, a])


func _beatmap(mode: int, objects: String, cs: int = 4) -> Beatmap:
	var txt := "osu file format v14\n\n[General]\nMode: %d\n\n[Metadata]\nTitle:T\nArtist:A\nVersion:V\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: %d\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n%s" % [mode, cs, objects]
	var res := OsuParser.parse(txt)
	assert(res.ok)
	return res.beatmap


## Einfache Kette von Schlaegen: [t, key] oder [t, key, end] oder [t, key, end, smash].
func _shots(list: Array) -> Array[RallyChart.Shot]:
	var out: Array[RallyChart.Shot] = []
	for e in list:
		var s := RallyChart.Shot.new()
		s.t = float(e[0])
		s.key = int(e[1])
		s.end = float(e[2]) if e.size() > 2 else s.t
		s.smash = e.size() > 3 and bool(e[3])
		out.append(s)
	RallyChart.finalize(out)
	return out


func _core(list: Array, mods: Dictionary = {}) -> RallyCore:
	var c := RallyCore.new()
	c.setup(_shots(list), 5.0, 5.0, mods)
	return c


func _run() -> void:
	print("=== TETHRA Rally-Tests ===")
	_test_chart_std()
	_test_chart_mania()
	_test_merge()
	_test_flight()
	_test_key_rule()
	_test_smash()
	_test_charge()
	_test_scoring()
	_test_replay()
	_test_autoplay()
	_test_stars()
	print("Ergebnis: %d ok, %d fehlgeschlagen" % [_passed, _failed])


func _test_chart_std() -> void:
	print("- Chart aus osu!standard")
	var bm := _beatmap(0,
		"100,100,1000,1,0,0:0:0:0:\n" +        # A
		"100,100,2000,1,2,0:0:0:0:\n" +        # Whistle -> B
		"100,100,3000,1,8,0:0:0:0:\n" +        # Clap -> B
		"100,100,4000,1,4,0:0:0:0:\n" +        # Finish -> Schmetterball
		"100,100,5000,2,0,L|300:100,1,140,0|0,0:0|0:0,0:0:0:0:\n")   # Slider -> Aufladen
	var shots := RallyChart.build(bm)
	_ok(shots.size() == 5, "5 Schlaege")
	_ok(shots[0].key == 0 and not shots[0].smash and not shots[0].is_charge(), "normal = Taste A")
	_ok(shots[1].key == 1, "Whistle = Taste B")
	_ok(shots[2].key == 1, "Clap = Taste B")
	_ok(shots[3].smash, "Finish = Schmetterball")
	_ok(shots[4].is_charge() and shots[4].end > shots[4].t + 200.0, "Slider = Aufladen")
	_ok(shots[0].serve and shots[0].m == shots[0].t - RallyChart.SERVE_LEAD_MS, "erster Schlag = Aufschlag")


func _test_chart_mania() -> void:
	print("- Chart aus Mania 4K")
	var bm := _beatmap(3,
		"64,192,1000,1,0,0:0:0:0:\n" +          # Spalte 1 -> A
		"192,192,2000,1,0,0:0:0:0:\n" +         # Spalte 2 -> A
		"320,192,3000,1,0,0:0:0:0:\n" +         # Spalte 3 -> B
		"448,192,4000,1,0,0:0:0:0:\n" +         # Spalte 4 -> B
		"64,192,5000,1,0,0:0:0:0:\n448,192,5000,1,0,0:0:0:0:\n" +   # Akkord beide Seiten
		"192,192,6000,1,0,0:0:0:0:\n320,192,6000,1,0,0:0:0:0:\n" + # Akkord A+B
		"448,192,7000,128,0,7800:0:0:0:0:\n")  # Hold -> Aufladen
	var shots := RallyChart.build(bm)
	_ok(shots.size() == 7, "7 Schlaege (Akkorde zusammengefasst), war %d" % shots.size())
	_ok(shots[0].key == 0 and shots[1].key == 0, "Spalten 1-2 = A")
	_ok(shots[2].key == 1 and shots[3].key == 1, "Spalten 3-4 = B")
	_ok(shots[4].smash and shots[5].smash, "Akkord ueber beide Seiten = Schmetterball")
	_ok(shots[6].is_charge() and shots[6].key == 1 and is_equal_approx(shots[6].end, 7800.0), "Hold = Aufladen bis zum Ende")


func _test_merge() -> void:
	print("- Zusammenfassen")
	var bm := _beatmap(0,
		"100,100,1000,1,0,0:0:0:0:\n100,100,1050,1,0,0:0:0:0:\n100,100,1100,1,0,0:0:0:0:\n" +
		"100,100,1500,1,0,0:0:0:0:\n")
	var shots := RallyChart.build(bm)
	# Leichte Map (< 2,5 Schlaege/s): Mindestabstand 1/4 Beat (500 ms -> 124 ms).
	_ok(shots.size() == 2, "Streichung unter 1/4 Beat bei leichter Map, war %d" % shots.size())
	# Dichte Map: nur Abstaende unter 90 ms fallen weg.
	var dense := ""
	for i in 40:
		dense += "100,100,%d,1,0,0:0:0:0:\n" % (1000 + i * 70)
	var d := RallyChart.build(_beatmap(0, dense))
	for i in range(1, d.size()):
		_ok(d[i].t - d[i - 1].end >= RallyChart.MERGE_MS, "Abstand >= 90 ms (%d)" % i)
	_ok(d.size() >= 15 and d.size() < 40, "Stream ausgeduennt (%d)" % d.size())


func _test_flight() -> void:
	print("- Flugbahn")
	var sh := _shots([[1000, 0], [1600, 1], [2000, 0], [2090, 1], [9000, 0]])
	for j in sh.size():
		var pos := RallyChart.pos_in(sh, j, sh[j].t)
		_near(pos.x, RallyChart.X_PLAYER, "Ball bei Spieler x (%d)" % j)
		_near(pos.y, RallyChart.hit_y(sh[j].key), "Ball in Trefferhoehe der Taste (%d)" % j)
		var at_m := RallyChart.pos_in(sh, j, sh[j].m)
		_near(at_m.x, RallyChart.X_OPP, "Ball beim Gegner zur Mitte (%d)" % j)
	_near(sh[1].m, (sh[0].end + sh[1].t) * 0.5, "Gegnerschlag in der Mitte")
	_near(sh[3].m, (sh[2].end + sh[3].t) * 0.5, "Gegnerschlag in der Mitte (Stream)")
	_ok(sh[4].serve and sh[0].exit_after == false and sh[3].exit_after, "Pause: Neuaufschlag, Ball verschwindet")
	# Aufprall auf dem Tisch: richtige Haelfte, Hoehe = Tischkante.
	var tb := RallyChart.bounce_me_time(sh, 1)
	var pb := RallyChart.pos_in(sh, 1, tb)
	_near(pb.y, RallyChart.Y_TABLE, "Aufprall auf Tischhoehe")
	_ok(pb.x > RallyChart.X_TABLE_L and pb.x < 0.5, "Aufprall auf der Spielerhaelfte")
	var to := RallyChart.bounce_opp_time(sh, 0)
	var po := RallyChart.pos_out(sh, 0, to)
	_near(po.y, RallyChart.Y_TABLE, "Aufprall beim Gegner auf Tischhoehe")
	_ok(po.x > 0.5 and po.x < RallyChart.X_TABLE_R, "Aufprall auf der Gegnerhaelfte")
	_near(RallyChart.pos_out(sh, 0, sh[0].end).x, RallyChart.X_PLAYER, "Rueckschlag startet beim Spieler")
	_near(RallyChart.pos_out(sh, 0, RallyChart.out_end(sh, 0)).x, RallyChart.X_OPP, "Rueckschlag endet beim Gegner")
	# Lob (grosser Abstand) hoeher als Stream; Hoechstpunkt ueber dem Netz bei Lob.
	_ok(RallyChart.arc_for(3000.0) > RallyChart.arc_for(200.0) * 3.0, "Lob hoeher als Stream")
	var lob := _shots([[1000, 0], [4000, 0]])
	var apex := 1.0
	for i in 100:
		var tt := lob[1].m + (lob[1].t - lob[1].m) * float(i) / 100.0
		apex = minf(apex, RallyChart.pos_in(lob, 1, tt).y)
	_ok(apex < RallyChart.Y_TABLE - 0.25, "Lob steigt deutlich (Scheitel %f)" % apex)
	# Ball waehrend Aufprall nie unter dem Tisch.
	for j in sh.size():
		for i in 60:
			var tt2 := sh[j].m + (sh[j].t - sh[j].m) * float(i) / 59.0
			_ok(RallyChart.pos_in(sh, j, tt2).y <= RallyChart.Y_TABLE + 0.0001, "Ball nicht unter dem Tisch")


func _press(core: RallyCore, key: int, t: float, hold_ms: float = 40.0) -> void:
	core.key_down(key, t)
	core.key_up(key, t + hold_ms)


func _test_key_rule() -> void:
	print("- Tastenregel")
	var c := _core([[1000, 0], [2000, 1]])
	c.key_down(1, 1000.0)       # falsche Taste (hoher Ball waere B, hier A verlangt)
	c.key_up(1, 1005.0)
	_ok(c.judged_count == 0, "falsche Taste trifft nicht")
	_press(c, 0, 1010.0)
	_ok(c.is_judged(0) and int(c.result_of(0).quality) == ManiaCore.Quality.MAX, "richtige Taste: MAX bei 10 ms")
	_press(c, 0, 2000.0)        # A auf B-Schlag
	c.update(2200.0)
	_ok(int(c.result_of(1).get("quality", 0)) == ManiaCore.Quality.MISS, "A auf B-Schlag: Fehlschlag nach Fenster")
	var c2 := _core([[1000, 0]])
	_press(c2, 0, 1000.0 - 160.0)   # sehr frueh (nach Miss-Fenster 173,5 aber vor 50er 136,5)
	_ok(int(c2.result_of(0).get("quality", 0)) == ManiaCore.Quality.MISS, "zu frueh frisst den Schlag")
	var c3 := _core([[1000, 0]])
	_press(c3, 0, 1000.0 - 300.0)
	_ok(c3.judged_count == 0, "weit vor dem Fenster: kein Effekt")
	var c4 := _core([[1000, 0]])
	_press(c4, 0, 1000.0 + 60.0)
	_ok(int(c4.result_of(0).quality) == ManiaCore.Quality.GOOD, "60 ms spaet = 200 (OD5: 49,5 < 60 <= 82,5)")
	# Fenster aus OD wie Mania.
	_near(c.w300, DifficultyCalc.mania_window_300(5.0), "300er-Fenster wie Mania")
	_near(c.w_max, 16.5, "MAX-Fenster wie Mania")


func _test_smash() -> void:
	print("- Schmetterball")
	var c := _core([[1000, 0, 1000, true], [2000, 0, 2000, true], [3000, 1, 3000, true]])
	c.key_down(0, 1000.0)
	c.key_down(1, 1012.0)
	_ok(c.is_judged(0) and int(c.result_of(0).quality) == ManiaCore.Quality.MAX, "beide Tasten in 12 ms = MAX")
	_ok(bool(c.result_of(0).smash), "Ergebnis ist Schmetterball")
	c.key_up(0, 1050.0)
	c.key_up(1, 1050.0)
	c.key_down(0, 2000.0)      # nur eine Taste
	c.key_up(0, 2030.0)
	_ok(not c.is_judged(1), "eine Taste: noch offen")
	c.update(2045.0)
	_ok(c.is_judged(1) and int(c.result_of(1).quality) >= ManiaCore.Quality.MEH - 0 and int(c.result_of(1).quality) != ManiaCore.Quality.MISS,
			"nur eine Taste: hoechstens 50, kein Miss")
	_ok(int(c.result_of(1).quality) == ManiaCore.Quality.MEH, "nur eine Taste = MEH")
	var q_before := c.combo
	c.key_down(1, 3000.0)
	c.key_down(0, 3100.0)      # zweite Taste nach 100 ms: zu spaet fuer das Fenster
	c.update(3200.0)
	_ok(int(c.result_of(2).quality) == ManiaCore.Quality.MEH and c.combo >= q_before, "zweite Taste nach 100 ms zaehlt nicht")


func _test_charge() -> void:
	print("- Aufladen")
	var c := _core([[1000, 0, 1800], [3000, 1, 3500]])
	c.key_down(0, 1005.0)
	_ok(c.charging == 0 and not c.is_judged(0), "Aufladen laeuft")
	_ok(c.combo == 1, "Kopf zaehlt zur Serie")
	c.key_up(0, 1800.0)
	_ok(c.is_judged(0) and int(c.result_of(0).quality) == ManiaCore.Quality.MAX and bool(c.result_of(0).held), "bis zum Ende gehalten = MAX")
	c.key_down(1, 3000.0)
	c.key_up(1, 3200.0)        # viel zu frueh losgelassen
	_ok(int(c.result_of(1).quality) == ManiaCore.Quality.MISS and c.combo == 0, "zu frueh loslassen = Fehlschlag")
	var c2 := _core([[1000, 0, 1800]])
	c2.key_down(0, 1000.0)
	c2.update(1800.0 + c2.w100 + 5.0)
	_ok(c2.is_judged(0) and int(c2.result_of(0).quality) != ManiaCore.Quality.MISS, "Taste nie losgelassen: Wertung nach OK-Fenster")


func _test_scoring() -> void:
	print("- Wertung (ScoreV1)")
	var list: Array = []
	for i in 20:
		list.append([1000 + i * 400, i % 2])
	var c := _core(list)
	for i in 20:
		_press(c, i % 2, 1000.0 + i * 400.0)
	c.update(20000.0)
	_ok(c.score >= 999990 and c.score <= 1000000, "alles MAX = ~1.000.000 (war %d)" % c.score)
	_ok(c.grade() == "SS" and is_equal_approx(c.accuracy(), 1.0), "SS und 100 %")
	var c2 := _core(list)
	for i in 20:
		if i % 4 != 3:
			_press(c2, i % 2, 1000.0 + i * 400.0 + 30.0)
	c2.update(20000.0)
	var s := c2.stats()
	_ok(int(s.n_miss) == 5 and int(s.n300) == 15, "Zaehler 15x300, 5 Miss (%s)" % str([s.n300, s.n_miss]))
	_ok(str(s.mode) == "rally", "stats mode rally")
	_ok(s.has("n_max") and s.has("max_combo") and s.has("accuracy") and s.has("grade") and s.has("score"), "stats-Felder wie Mania")
	_ok(int(s.max_combo) == 3, "max_combo")
	var nf := _core(list, {"NF": true})
	for i in 20:
		_press(nf, i % 2, 1000.0 + i * 400.0)
	nf.update(20000.0)
	_ok(nf.score <= 500000 and nf.score >= 499990, "NF halbiert (war %d)" % nf.score)
	# Scheitern: Dauer-Fehlschlaege.
	var f := _core(list)
	f.update(20000.0)
	_ok(f.failed, "alles verpasst = gescheitert")
	var f2 := _core(list, {"NF": true})
	f2.update(20000.0)
	_ok(not f2.failed, "NF scheitert nicht")


func _play(core: RallyCore, plan: Array, frame_ms: float, end_ms: float) -> void:
	var i := 0
	var t := 0.0
	while t <= end_ms:
		while i < plan.size() and float(plan[i][0]) <= t:
			core.feed(plan[i])
			i += 1
		core.update(t)
		t += frame_ms


func _mixed_shots() -> Array[RallyChart.Shot]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var list: Array = []
	var t := 1500.0
	for i in 120:
		t += 120.0 + float(rng.randi_range(0, 4)) * 110.0
		var kind := rng.randi_range(0, 9)
		if kind == 0:
			list.append([t, rng.randi_range(0, 1), t + 400.0 + float(rng.randi_range(0, 3)) * 100.0])
			t += 600.0
		elif kind == 1:
			list.append([t, 0, t, true])
		else:
			list.append([t, rng.randi_range(0, 1)])
	return _shots(list)


func _test_replay() -> void:
	print("- Replay deterministisch")
	var sh := _mixed_shots()
	var plan := RallyCore.bot_plan(sh, 11, 70.0, 7)
	var end_ms := sh[-1].end + 500.0
	var a := RallyCore.new()
	a.setup(sh, 7.0, 5.0, {})
	_play(a, plan, 16.0, end_ms)
	var b := RallyCore.new()
	b.setup(sh, 7.0, 5.0, {})
	_play(b, plan, 1.0, end_ms)        # andere Bildrate
	var c := RallyCore.new()
	c.setup(sh, 7.0, 5.0, {})
	_play(c, plan, 250.0, end_ms)     # sehr grobe Bildrate
	_ok(a.stats() == b.stats() and a.stats() == c.stats(), "gleiche Wertung bei 1/16/250 ms Bildabstand")
	_ok(a.event_log == b.event_log and a.event_log == c.event_log, "gleiches Ereignis-Log")
	_ok(int(a.stats().n_miss) > 0 and int(a.stats().n_max) + int(a.stats().n300) > 20, "Lauf mit Treffern und Fehlern")
	# Aufzeichnung -> JSON -> Wiedergabe.
	var parsed = JSON.parse_string(JSON.stringify({"events": a.replay_log}))
	var events: Array = parsed.events
	_ok(RallyCore.replay_ok(events), "Replay hat Regel-Marke")
	var r := RallyCore.new()
	r.set_replay_mode(false)
	r.setup(sh, 7.0, 5.0, {})
	r.recording = false
	var i := 0
	var t := 0.0
	while t <= end_ms:
		while i < events.size() and float(events[i][0]) <= t:
			r.apply_event(events[i])
			i += 1
		r.update(t)
		t += 33.0
	_ok(r.stats() == a.stats(), "Replay-Wiedergabe = Original (Score %d)" % a.score)
	_ok(not RallyCore.replay_ok([[0, 1]]), "Replay ohne Regel-Marke ist ungueltig")
	# Live-Eingabe schreibt dasselbe wie der Bot.
	var live := RallyCore.new()
	live.setup(sh, 7.0, 5.0, {})
	var j := 0
	var tt := 0.0
	while tt <= end_ms:
		while j < plan.size() and float(plan[j][0]) <= tt:
			if int(plan[j][1]) >= RallyCore.EV_UP:
				live.key_up(int(plan[j][1]) - RallyCore.EV_UP, float(plan[j][0]))
			else:
				live.key_down(int(plan[j][1]) - RallyCore.EV_DOWN, float(plan[j][0]))
			j += 1
		live.update(tt)
		tt += 16.0
	_ok(live.stats() == a.stats(), "key_down/key_up = feed")


func _test_autoplay() -> void:
	print("- Autoplay = SS")
	var sh := _mixed_shots()
	var c := RallyCore.new()
	c.setup(sh, 8.0, 5.0, {})
	_play(c, RallyCore.bot_plan(sh), 16.0, sh[-1].end + 500.0)
	var s := c.stats()
	_ok(str(s.grade) == "SS" and int(s.n_miss) == 0 and is_equal_approx(float(s.accuracy), 1.0), "Bot: SS ohne Fehler")
	_ok(int(s.max_combo) == sh.size(), "Bot: volle Serie")
	_ok(c.score >= 999990, "Bot: ~1.000.000 Punkte (%d)" % c.score)
	var fin := [false]
	var c2 := RallyCore.new()
	c2.setup(sh, 8.0, 5.0, {})
	c2.finished.connect(func(_s): fin[0] = true)
	_play(c2, RallyCore.bot_plan(sh), 16.0, sh[-1].end + 500.0)
	_ok(fin[0], "finished kommt")


func _test_stars() -> void:
	print("- Sterne-Skala")
	var slow: Array = []
	for i in 60:
		slow.append([1000 + i * 900, 0])
	var mid: Array = []
	for i in 300:
		mid.append([1000 + i * 250, i % 2])
	var fast: Array = []
	for i in 600:
		fast.append([1000 + i * 100, i % 2])
	var heavy: Array = []
	for i in 600:
		heavy.append([1000 + i * 100, i % 2, 1000 + i * 100, i % 3 == 0])
	var s0 := RallyChart.stars(_shots(slow))
	var s1 := RallyChart.stars(_shots(mid))
	var s2 := RallyChart.stars(_shots(fast))
	var s3 := RallyChart.stars(_shots(heavy))
	_ok(s0 >= 0.0 and s0 < s1 and s1 < s2 and s2 < s3, "Sterne steigen mit Dichte und Schmetterbaellen (%s)" % str([s0, s1, s2, s3]))
	_ok(s3 <= RallyChart.STAR_MAX and s0 >= 0.0, "Sterne in 0..15")
	_near(RallyChart.stars([] as Array[RallyChart.Shot]), 0.0, "leer = 0")
