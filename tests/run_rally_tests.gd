extends SceneTree

## Headless-Tests fuer Rally v2: Chart aus Standard- und 4K-Map (4 Zonen, Schmetterball,
## Aufladen, Flugzeit), Zonenregel (kein Notelock zwischen Zonen), Schmetterball,
## Aufladen, Fenster, Zusammenfassen, Wertung (ScoreV1), Replay (rules 2) deterministisch,
## Autoplay = SS, Sterne-Skala.
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


## Einfache Kette von Baellen: [t, zone] oder [t, zone, end] oder [t, zone, end, smash];
## zone kann ein Array sein (Schmetterball: 2 Zonen, smash wird dann gesetzt).
func _shots(list: Array) -> Array[RallyChart.Shot]:
	var out: Array[RallyChart.Shot] = []
	for e in list:
		var s := RallyChart.Shot.new()
		s.t = float(e[0])
		if e[1] is Array:
			s.zones = PackedInt32Array(e[1])
			s.smash = e[1].size() > 1
		else:
			s.zones = PackedInt32Array([int(e[1])])
		s.key = 0 if s.zones[0] < 2 else 1
		s.end = float(e[2]) if e.size() > 2 else s.t
		s.smash = s.smash or (e.size() > 3 and bool(e[3]))
		if s.smash and s.zones.size() < 2:
			s.zones = PackedInt32Array([s.zones[0], mini(s.zones[0] + 1, 3) if s.zones[0] < 3 else 2])
			s.zones.sort()
		s.launch = s.t - 800.0
		out.append(s)
	RallyChart.finalize(out)
	return out


func _core(list: Array, mods: Dictionary = {}) -> RallyCore:
	var c := RallyCore.new()
	c.setup(_shots(list), 5.0, 5.0, mods)
	return c


func _run() -> void:
	print("=== TETHRA Rally-Tests (v2, 4 Zonen) ===")
	_test_chart_std()
	_test_chart_mania()
	_test_merge()
	_test_flight_time()
	_test_zone_rule()
	_test_smash()
	_test_charge()
	_test_windows()
	_test_scoring()
	_test_replay()
	_test_autoplay()
	_test_stars()
	print("Ergebnis: %d ok, %d fehlgeschlagen" % [_passed, _failed])


func _test_chart_std() -> void:
	print("- Chart aus osu!standard")
	var bm := _beatmap(0,
		"60,100,1000,1,0,0:0:0:0:
" +        # x < 128 -> Zone 0
		"200,100,2000,1,0,0:0:0:0:
" +       # 128..255 -> Zone 1
		"300,100,3000,1,0,0:0:0:0:
" +       # 256..383 -> Zone 2
		"500,100,4000,1,0,0:0:0:0:
" +       # >= 384 -> Zone 3
		"60,100,5000,1,0,0:0:0:0:
500,100,5000,1,0,0:0:0:0:
" +   # gleichzeitig -> Schmetterball
		"300,100,6000,2,0,L|400:100,1,140,0|0,0:0|0:0,0:0:0:0:
")   # Slider -> Aufladen
	var shots := RallyChart.build(bm, 800.0)
	_ok(shots.size() == 6, "6 Baelle (Akkord zusammengefasst), war %d" % shots.size())
	_ok(shots[0].zones == PackedInt32Array([0]) and not shots[0].smash, "x 60 = Zone 0")
	_ok(shots[1].zones == PackedInt32Array([1]), "x 200 = Zone 1")
	_ok(shots[2].zones == PackedInt32Array([2]), "x 300 = Zone 2")
	_ok(shots[3].zones == PackedInt32Array([3]), "x 500 = Zone 3")
	_ok(shots[4].smash and shots[4].zones == PackedInt32Array([0, 3]), "Akkord = Schmetterball mit 2 Zonen")
	_ok(shots[5].is_charge() and shots[5].end > shots[5].t + 200.0 and shots[5].zones == PackedInt32Array([2]), "Slider = Aufladen")
	_ok(shots[0].serve and shots[0].m == shots[0].t - RallyChart.SERVE_LEAD_MS, "erster Ball = Aufschlag")


func _test_chart_mania() -> void:
	print("- Chart aus Mania 4K")
	var bm := _beatmap(3,
		"64,192,1000,1,0,0:0:0:0:
" +          # Spalte 1 -> Zone 0
		"192,192,2000,1,0,0:0:0:0:
" +         # Spalte 2 -> Zone 1
		"320,192,3000,1,0,0:0:0:0:
" +         # Spalte 3 -> Zone 2
		"448,192,4000,1,0,0:0:0:0:
" +         # Spalte 4 -> Zone 3
		"64,192,5000,1,0,0:0:0:0:
448,192,5000,1,0,0:0:0:0:
" +   # Akkord aussen
		"192,192,6000,1,0,0:0:0:0:
320,192,6000,1,0,0:0:0:0:
" +  # Akkord Mitte
		"64,192,7000,1,0,0:0:0:0:
192,192,7000,1,0,0:0:0:0:
320,192,7000,1,0,0:0:0:0:
" + # 3 Noten
		"448,192,8000,128,0,8800:0:0:0:0:
")  # Hold -> Aufladen
	var shots := RallyChart.build(bm, 800.0)
	_ok(shots.size() == 8, "8 Baelle (Akkorde zusammengefasst), war %d" % shots.size())
	for i in 4:
		_ok(shots[i].zones == PackedInt32Array([i]) and not shots[i].smash, "Spalte %d = Zone %d" % [i + 1, i])
	_ok(shots[4].smash and shots[4].zones == PackedInt32Array([0, 3]), "Akkord aussen = Schmetterball 0+3")
	_ok(shots[5].smash and shots[5].zones == PackedInt32Array([1, 2]), "Akkord Mitte = Schmetterball 1+2")
	_ok(shots[6].smash and shots[6].zones == PackedInt32Array([0, 2]), "3 Noten = die 2 aeussersten Zonen")
	_ok(shots[7].is_charge() and shots[7].zones == PackedInt32Array([3]) and is_equal_approx(shots[7].end, 8800.0), "Hold = Aufladen bis zum Ende")


func _test_merge() -> void:
	print("- Zusammenfassen")
	var bm := _beatmap(0,
		"100,100,1000,1,0,0:0:0:0:
100,100,1050,1,0,0:0:0:0:
100,100,1100,1,0,0:0:0:0:
" +
		"100,100,1500,1,0,0:0:0:0:
100,100,4000,1,0,0:0:0:0:
100,100,7000,1,0,0:0:0:0:
")
	var shots := RallyChart.build(bm, 800.0)
	# Leichte Map (< 2,5 Baelle/s): Mindestabstand 1/4 Beat (500 ms -> 124 ms).
	_ok(shots.size() == 4, "Streichung unter 1/4 Beat bei leichter Map, war %d" % shots.size())
	# Dichte Map: nur Abstaende unter 90 ms fallen weg.
	var dense := ""
	for i in 40:
		dense += "100,100,%d,1,0,0:0:0:0:
" % (1000 + i * 70)
	var d := RallyChart.build(_beatmap(0, dense), 800.0)
	for i in range(1, d.size()):
		_ok(d[i].t - d[i - 1].end >= RallyChart.MERGE_MS, "Abstand >= 90 ms (%d)" % i)
	_ok(d.size() >= 15 and d.size() < 40, "Stream ausgeduennt (%d)" % d.size())


func _test_flight_time() -> void:
	print("- Flugzeit")
	var bm := _beatmap(3, "64,192,1000,1,0,0:0:0:0:
192,192,2000,1,0,0:0:0:0:
")
	for ms in [450.0, 800.0, 1400.0]:
		var sh := RallyChart.build(bm, ms)
		for s in sh:
			_near(s.t - s.launch, ms, "launch = t - %d ms" % int(ms), 0.5)
	_near(RallyChart.DEFAULT_FLIGHT_MS, 800.0, "Standard-Flugzeit 800 ms")


func _press(core: RallyCore, key: int, t: float, hold_ms: float = 40.0) -> void:
	core.key_down(key, t)
	core.key_up(key, t + hold_ms)


func _test_zone_rule() -> void:
	print("- Zonenregel")
	var c := _core([[1000, 0], [2000, 3]])
	var ign := []
	c.press_ignored.connect(func(z, r): ign.append([z, r]))
	c.key_down(3, 1000.0)       # falsche Zone (verlangt: Zone 0)
	c.key_up(3, 1005.0)
	_ok(c.judged_count == 0, "falsche Zone trifft nicht")
	_ok(ign.size() == 1 and ign[0][1] == "KEY", "falsche Zone mit Ball in Reichweite: Hinweis KEY")
	_press(c, 0, 1010.0)
	_ok(c.is_judged(0) and int(c.result_of(0).quality) == ManiaCore.Quality.MAX, "richtige Zone: MAX bei 10 ms")
	_press(c, 1, 2000.0)        # Zone 1 auf Ball in Zone 3
	c.update(2200.0)
	_ok(int(c.result_of(1).get("quality", 0)) == ManiaCore.Quality.MISS, "falsche Zone: Fehlschlag nach Fenster")
	# Taste ohne Ball in der Zone und in Reichweite: ignoriert (FREE).
	var cf := _core([[5000, 2]])
	var ign2 := []
	cf.press_ignored.connect(func(z, r): ign2.append([z, r]))
	_press(cf, 1, 1000.0)
	_ok(cf.judged_count == 0 and ign2.size() == 1 and ign2[0][1] == "FREE", "Taste ohne Ball: ignoriert")
	# Kein Notelock: zwei Baelle fast gleichzeitig in verschiedenen Zonen, Reihenfolge egal.
	var c5 := _core([[1000, 0], [1010, 2]])
	_press(c5, 2, 1008.0)
	_ok(c5.is_judged(1) and not c5.is_judged(0), "spaeterer Ball in anderer Zone zuerst getroffen")
	_press(c5, 0, 1001.0)
	_ok(c5.is_judged(0) and int(c5.result_of(0).quality) == ManiaCore.Quality.MAX, "erster Ball danach ebenfalls")
	# Ein offener Ball in Zone 0 blockiert Zone 1 nicht.
	var c6 := _core([[1000, 0], [1100, 1]])
	_press(c6, 1, 1100.0)
	_ok(c6.is_judged(1) and int(c6.result_of(1).quality) == ManiaCore.Quality.MAX, "Zone 1 unabhaengig von offenem Ball in Zone 0")
	# Zwei Baelle derselben Zone: der aeltere zuerst.
	var c7 := _core([[1000, 1], [1100, 1]])
	_press(c7, 1, 1050.0)
	_ok(c7.is_judged(0) and not c7.is_judged(1), "gleiche Zone: aelterer Ball zuerst")
	var c2 := _core([[1000, 0]])
	_press(c2, 0, 1000.0 - 160.0)   # sehr frueh (nach Miss-Fenster 173,5 aber vor 50er 136,5)
	_ok(int(c2.result_of(0).get("quality", 0)) == ManiaCore.Quality.MISS, "zu frueh frisst den Ball")
	var c3 := _core([[1000, 0]])
	_press(c3, 0, 1000.0 - 300.0)
	_ok(c3.judged_count == 0, "weit vor dem Fenster: kein Effekt")
	var c4 := _core([[1000, 0]])
	_press(c4, 0, 1000.0 + 60.0)
	_ok(int(c4.result_of(0).quality) == ManiaCore.Quality.GOOD, "60 ms spaet = 200 (OD5: 49,5 < 60 <= 82,5)")


func _test_windows() -> void:
	print("- OD-Fenster wie Mania")
	for od in [0.0, 5.0, 8.0, 10.0]:
		var c := RallyCore.new()
		c.setup(_shots([[1000, 0]]), od, 5.0, {})
		_near(c.w_max, DifficultyCalc.mania_window_max(od), "MAX-Fenster OD %d" % int(od))
		_near(c.w300, DifficultyCalc.mania_window_300(od), "300er-Fenster OD %d" % int(od))
		_near(c.w100, DifficultyCalc.mania_window_100(od), "100er-Fenster OD %d" % int(od))
		_near(c.w50, DifficultyCalc.mania_window_50(od), "50er-Fenster OD %d" % int(od))
	var c2 := _core([[1000, 0], [2000, 1], [3000, 2], [4000, 3]])
	_press(c2, 0, 1000.0 + c2.w300 - 1.0)
	_press(c2, 1, 2000.0 - c2.w100 + 1.0)
	_press(c2, 2, 3000.0 + c2.w50 - 1.0)
	_press(c2, 3, 4000.0 + c2.w50 + 5.0)    # nach 50er-Fenster: Ball schon verpasst
	c2.update(4500.0)
	_ok(int(c2.result_of(0).quality) == ManiaCore.Quality.PERFECT, "knapp im 300er-Fenster = 300")
	_ok(int(c2.result_of(1).quality) == ManiaCore.Quality.OK, "knapp im 100er-Fenster = 100")
	_ok(int(c2.result_of(2).quality) == ManiaCore.Quality.MEH, "knapp im 50er-Fenster = 50")
	_ok(int(c2.result_of(3).quality) == ManiaCore.Quality.MISS, "nach dem 50er-Fenster = Miss")


func _test_smash() -> void:
	print("- Schmetterball")
	var c := _core([[1000, [0, 3]], [2000, [1, 2]], [3000, [0, 3]], [4000, [0, 3]]])
	c.key_down(0, 1000.0)
	c.key_down(3, 1012.0)
	_ok(c.is_judged(0) and int(c.result_of(0).quality) == ManiaCore.Quality.MAX, "beide Zonentasten in 12 ms = MAX")
	_ok(bool(c.result_of(0).smash), "Ergebnis ist Schmetterball")
	c.key_up(0, 1050.0)
	c.key_up(3, 1050.0)
	c.key_down(1, 2000.0)      # nur eine Taste
	c.key_up(1, 2030.0)
	_ok(not c.is_judged(1), "eine Taste: noch offen")
	c.update(2045.0)
	_ok(c.is_judged(1) and int(c.result_of(1).quality) == ManiaCore.Quality.MEH, "nur eine Taste = MEH (hoechstens 50), kein Miss")
	var q_before := c.combo
	c.key_down(0, 3000.0)
	c.key_down(3, 3100.0)      # zweite Taste nach 100 ms: zu spaet fuer das Fenster
	c.update(3200.0)
	_ok(int(c.result_of(2).quality) == ManiaCore.Quality.MEH and c.combo >= q_before, "zweite Taste nach 100 ms zaehlt nicht")
	# Falsche Zonen (beide in der Mitte statt aussen) treffen nicht.
	c.key_down(1, 4000.0)
	c.key_down(2, 4010.0)
	c.update(4200.0)
	_ok(int(c.result_of(3).quality) == ManiaCore.Quality.MISS, "Schmetterball mit falschen Zonen = Fehlschlag")
	# Dieselbe Zone zweimal zaehlt nicht als zweite Taste.
	var c2 := _core([[1000, [0, 3]]])
	c2.key_down(0, 1000.0)
	c2.key_up(0, 1005.0)
	c2.key_down(0, 1010.0)
	_ok(not c2.is_judged(0), "zweimal dieselbe Zone: noch offen")
	c2.update(1100.0)
	_ok(int(c2.result_of(0).quality) == ManiaCore.Quality.MEH, "zweimal dieselbe Zone = nur eine Taste")


func _test_charge() -> void:
	print("- Aufladen")
	var c := _core([[1000, 0, 1800], [3000, 1, 3500]])
	c.key_down(0, 1005.0)
	_ok(c.charging == 0 and c.is_charging(0) and not c.is_judged(0), "Aufladen laeuft")
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
	# Hold-Wertung wie osu!mania stable (Kopf- und Endfehler).
	var c3 := _core([[1000, 2, 1800]])
	c3.key_down(2, 1000.0 + c3.w300 - 5.0)
	c3.key_up(2, 1800.0 + c3.w300 - 5.0)
	_ok(int(c3.result_of(0).quality) == c3._tally.hold_quality(c3.w300 - 5.0, c3.w300 - 5.0), "Aufladen = Mania-Hold-Qualitaet")
	# Waehrend des Aufladens in Zone 0 laufen Baelle in anderen Zonen weiter (+ zweite Aufladung).
	var c4 := _core([[1000, 0, 2000], [1200, 1], [1500, 2, 1900], [1700, 3]])
	c4.key_down(0, 1000.0)
	_press(c4, 1, 1200.0)
	c4.key_down(2, 1500.0)
	_press(c4, 3, 1700.0)
	_ok(c4.is_judged(1) and c4.is_judged(3), "andere Zonen waehrend des Aufladens spielbar")
	c4.key_up(2, 1900.0)
	c4.key_up(0, 2000.0)
	_ok(c4.judged_count == 4 and c4.combo == 4 and int(c4.stats().n_miss) == 0, "zwei Aufladungen parallel: alles gewertet")


func _test_scoring() -> void:
	print("- Wertung (ScoreV1)")
	var list: Array = []
	for i in 20:
		list.append([1000 + i * 400, i % 4])
	var c := _core(list)
	for i in 20:
		_press(c, i % 4, 1000.0 + i * 400.0)
	c.update(20000.0)
	_ok(c.score >= 999990 and c.score <= 1000000, "alles MAX = ~1.000.000 (war %d)" % c.score)
	_ok(c.grade() == "SS" and is_equal_approx(c.accuracy(), 1.0), "SS und 100 %")
	var c2 := _core(list)
	for i in 20:
		if i % 4 != 3:
			_press(c2, i % 4, 1000.0 + i * 400.0 + 30.0)
	c2.update(20000.0)
	var s := c2.stats()
	_ok(int(s.n_miss) == 5 and int(s.n300) == 15, "Zaehler 15x300, 5 Miss (%s)" % str([s.n300, s.n_miss]))
	_ok(str(s.mode) == "rally", "stats mode rally")
	_ok(s.has("n_max") and s.has("max_combo") and s.has("accuracy") and s.has("grade") and s.has("score"), "stats-Felder wie Mania")
	_ok(int(s.max_combo) == 3, "max_combo")
	var cs := c.stats()
	_ok(int(cs.n_max) + int(cs.n300) + int(cs.n200) + int(cs.n100) + int(cs.n50) + int(cs.n_miss) == list.size(), "Zaehlersumme = Zahl der Baelle")
	var nf := _core(list, {"NF": true})
	for i in 20:
		_press(nf, i % 4, 1000.0 + i * 400.0)
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
			list.append([t, rng.randi_range(0, 3), t + 400.0 + float(rng.randi_range(0, 3)) * 100.0])
			t += 600.0
		elif kind == 1:
			list.append([t, [0, 3]])
		elif kind == 2:
			list.append([t, [1, 2]])
		else:
			list.append([t, rng.randi_range(0, 3)])
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
	_ok(RallyCore.REPLAY_RULES == 2 and int(a.replay_log[0][2]) == 2, "Replay-Regel-Marke = 2")
	_ok(not RallyCore.replay_ok([[0, RallyCore.EV_RULES, 1], [100, 1]]), "altes Replay (rules 1) wird abgelehnt")
	_ok(RallyCore.replay_ok([[0, RallyCore.EV_RULES, 2], [100, 1]]), "Replay rules 2 wird akzeptiert")
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
		mid.append([1000 + i * 250, i % 4])
	var fast: Array = []
	for i in 600:
		fast.append([1000 + i * 100, i % 4])
	var heavy: Array = []
	for i in 600:
		heavy.append([1000 + i * 100, [0, 3] if i % 3 == 0 else (i * 3) % 4])
	var s0 := RallyChart.stars(_shots(slow))
	var s1 := RallyChart.stars(_shots(mid))
	var s2 := RallyChart.stars(_shots(fast))
	var s3 := RallyChart.stars(_shots(heavy))
	_ok(s0 >= 0.0 and s0 < s1 and s1 < s2 and s2 < s3, "Sterne steigen mit Dichte und Schmetterbaellen (%s)" % str([s0, s1, s2, s3]))
	_ok(s3 <= RallyChart.STAR_MAX and s0 >= 0.0, "Sterne in 0..15")
	# Zonenspruenge sind schwerer als derselbe Takt in einer Zone.
	var same: Array = []
	var jump: Array = []
	for i in 300:
		same.append([1000 + i * 200, 1])
		jump.append([1000 + i * 200, 0 if i % 2 == 0 else 3])
	_ok(RallyChart.stars(_shots(jump)) > RallyChart.stars(_shots(same)), "Zonenspruenge > gleiche Zone")
	var plain: Array = []
	var charged: Array = []
	for i in 100:
		plain.append([1000 + i * 600, i % 4])
		charged.append([1000 + i * 600, i % 4, 1000 + i * 600 + 400])
	_ok(RallyChart.stars(_shots(charged)) > RallyChart.stars(_shots(plain)), "Aufladen > normale Baelle")
	_near(RallyChart.stars([] as Array[RallyChart.Shot]), 0.0, "leer = 0")
