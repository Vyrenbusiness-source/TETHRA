extends SceneTree

## Headless-Tests fuer den Dirigent-Modus: Figuren je Taktart, volle Figur mit
## groesserem Zeitfenster bei schnellen Schlaegen (Handtempo begrenzt), Kiai-Groesse, Schlag-Wertung (Zielfaktor), Einsatz-Wertung,
## Gewichtung 40/60, Replay deterministisch, Autoplay = SS, Sterne. Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_dirigent_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Dirigent-Tests ===")
	_test_figures()
	_test_half_bars()
	_test_meter_change()
	_test_kiai_scale()
	_test_beat_scoring()
	_test_cue_scoring()
	_test_cue_keys()
	_test_weights()
	_test_replay()
	_test_autoplay_ss()
	_test_stars()
	_test_breaks()
	_test_anti_mash()
	_test_rules_3()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


# --- Hilfen ---

func _tp(bm: Beatmap, t: float, bpm: float, meter: int = 4) -> void:
	var tp := TimingPoint.new()
	tp.time = t
	tp.beat_length = 60000.0 / bpm
	tp.meter = meter
	tp.uninherited = true
	bm.timing_points.append(tp)


func _std(bpm: float = 120.0, meter: int = 4) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "0"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5", "ApproachRate": "9"}
	_tp(bm, 0.0, bpm, meter)
	return bm


func _circle(bm: Beatmap, t: float, hs: int = 0) -> void:
	var c := HitCircle.new()
	c.time = t
	c.x = 100.0
	c.y = 100.0
	c.hit_sound = hs
	bm.hit_objects.append(c)


## Map mit einem Kreis je Beat ueber n_beats Beats ab t0, Whistle auf jedem zweiten.
func _map(bpm: float, meter: int, n_beats: int, t0: float = 1000.0) -> Beatmap:
	var bm := _std(bpm, meter)
	var bl := 60000.0 / bpm
	for i in n_beats:
		_circle(bm, t0 + float(i) * bl, 2 if i % 2 == 1 else 0)
	return bm


func _bars_of(c: DirigentChart) -> Array:
	var out: Array = []
	for b in c.bars:
		out.append("%s:%d" % [b.label, b.n])
	return out


func _core(c: DirigentChart, od: float = 8.0) -> DirigentCore:
	var core := DirigentCore.new()
	core.setup(c, od)
	return core


# --- Tests ---

func _test_figures() -> void:
	print("-- Figuren je Taktart")
	var f4 := DirigentChart.build(_map(120.0, 4, 16))
	_ok(f4.bars.size() >= 3 and int(f4.bars[1].n) == 4, "4/4: 4 Punkte je Takt")
	var p := DirigentChart.figure_points("44", 4)
	_ok(p[0].y > 0.0 and absf(p[0].x) < 0.001, "4/4: 1 unten")
	_ok(p[1].x < 0.0 and p[2].x > 0.0, "4/4: 2 links, 3 rechts")
	_ok(p[3].y < 0.0 and absf(p[3].x) < 0.001, "4/4: 4 oben")
	var f3 := DirigentChart.build(_map(120.0, 3, 12))
	_ok(int(f3.bars[1].n) == 3 and f3.bars[1].kind == "34", "3/4: Dreieck mit 3 Punkten")
	var t := DirigentChart.figure_points("34", 3)
	_ok(t[0].y > 0.0 and t[1].x > 0.0 and t[2].y < 0.0, "3/4: unten, rechts, oben")
	var f2 := DirigentChart.build(_map(120.0, 2, 8))
	_ok(int(f2.bars[1].n) == 2 and f2.bars[1].kind == "24", "2/4: unten, oben")
	var f6 := DirigentChart.build(_map(120.0, 6, 24))
	_ok(int(f6.bars[1].n) == 2 and int(f6.bars[1].count) == 2, "6/8: 2 Hauptschlaege je Takt")
	var t6 := float(f6.beats[1].t) - float(f6.beats[0].t)
	_ok(is_equal_approx(t6, 1500.0), "6/8: Hauptschlaege im Abstand von 3 Beats")
	var f5 := DirigentChart.build(_map(120.0, 5, 15))
	_ok(int(f5.bars[1].n) == 5 and f5.bars[1].kind == "circle", "5/4: Kreis mit 5 Punkten")
	var f7 := DirigentChart.build(_map(120.0, 7, 21))
	_ok(int(f7.bars[1].n) == 7, "7/4: Kreis mit 7 Punkten")
	var circ := DirigentChart.figure_points("circle", 5)
	_ok(circ.size() == 5 and absf(circ[0].length() - DirigentChart.FIG) < 0.001, "Kreispunkte auf dem Figur-Radius")
	_ok(circ[0].y > 0.0, "Kreis beginnt unten")


func _test_half_bars() -> void:
	print("-- Schnelle Songs: volle Figur, groesseres Zeitfenster")
	var fast := DirigentChart.build(_map(240.0, 4, 32))  # 250 ms
	_ok(fast.bars.size() >= 2 and int(fast.bars[1].count) == 4, "250 ms: volle 4-Punkt-Figur")
	_ok(fast.bars[1].kind == "44" and int(fast.bars[1].step) == 2, "250 ms: 4/4, 2 Beats je Punkt")
	_ok(is_equal_approx(float(fast.beats[1].t) - float(fast.beats[0].t), 500.0), "Punktabstand 500 ms")
	var slow := DirigentChart.build(_map(120.0, 4, 32))
	_ok(int(slow.bars[1].count) == 4 and int(slow.bars[1].step) == 1, "500 ms: alle 4 Schlaege, 1 Beat je Punkt")
	var fast3 := DirigentChart.build(_map(240.0, 3, 24))
	_ok(int(fast3.bars[1].n) == 3 and fast3.bars[1].kind == "34", "schnell 3/4: volles Dreieck")
	# Nie hektisch: Punktabstand und mittleres Handtempo ueber viele BPM / Taktarten.
	var worst := 0.0
	var min_dt := INF
	for bl in [120.0, 160.0, 200.0, 250.0, 300.0, 333.0, 400.0, 600.0]:
		for meter in [2, 3, 4, 5, 7]:
			var c := DirigentChart.build(_map(bl, meter, meter * 12))
			for i in range(0, c.beats.size() - 1):
				if c.is_gap(i):
					continue
				var dt := float(c.beats[i + 1].t) - float(c.beats[i].t)
				min_dt = minf(min_dt, dt)
				worst = maxf(worst, (c.beats[i + 1].pos - c.beats[i].pos).length() / (dt / 1000.0))
	_ok(min_dt >= DirigentChart.FAST_BEAT_MS - 1.0, "Punktabstand >= ~Beat-Grenze: %.0f ms" % min_dt)
	_ok(worst <= DirigentChart.MAX_SPEED, "Sprung-Tempo <= %.1f E/s (gemessen %.2f)" % [DirigentChart.MAX_SPEED, worst])
	# Bot-Messung: Spitzentempo der Ideal-Hand (Ease: bis 1,5 x Mittel) in schneller Kiai-Map.
	var fk := _map(150.0, 4, 64)  # 400 ms
	fk.kiai_intervals = [{"start": 0.0, "end": 100000.0}]
	var fc := DirigentChart.build(fk)
	var peak := 0.0
	var tt := float(fc.beats[0].t)
	var last := fc.ideal_at(tt)
	while tt < float(fc.beats[-1].t):
		tt += 10.0
		var np := fc.ideal_at(tt)
		peak = maxf(peak, (np - last).length() / 0.010)
		last = np
	_ok(peak <= DirigentChart.MAX_SPEED * 1.7, "Bot: Spitzentempo %.2f E/s <= %.1f" % [peak, DirigentChart.MAX_SPEED * 1.7])
	# Kiai: erweiterte Figur, weiteres Ausholen, nie schneller als MAX_SPEED.
	var plain := DirigentChart.figure_points("44", 4)
	var ext := DirigentChart.figure_points("44", 4, true)
	_ok(ext[1].x < plain[1].x and ext[2].x > plain[2].x, "erweiterte Figur holt weiter aus")
	_ok(ext[0] == plain[0] and ext[3] == plain[3], "erweiterte Figur: Unten/Oben gleich")
	var spd := (ext[2] - ext[1]).length() * DirigentChart.KIAI_SCALE / (DirigentChart.FAST_BEAT_MS / 1000.0)
	_ok(spd <= DirigentChart.MAX_SPEED, "Kiai-Figur auch im schnellsten Fenster <= MAX_SPEED (%.2f)" % spd)


func _test_meter_change() -> void:
	print("-- Taktwechsel")
	var bm := _map(120.0, 4, 16)
	_tp(bm, 9000.0, 120.0, 3)
	for i in 9:
		_circle(bm, 9000.0 + float(i) * 500.0)
	var c := DirigentChart.build(bm)
	var labels := _bars_of(c)
	_ok("4/4:4" in labels and "3/4:3" in labels, "Taktwechsel 4/4 -> 3/4 liefert beide Figuren: " + str(labels))
	var k := -1
	for i in c.bars.size():
		if c.bars[i].label == "3/4":
			k = i
			break
	_ok(k > 0 and c.bars[k - 1].label == "4/4", "Takt davor kennt den Wechsel (Ankuendigung moeglich)")
	_ok(k > 0 and absf(float(c.bars[k].t) - 9000.0) < 1.0, "Wechsel auf Takt-Eins des roten Punkts")


func _test_kiai_scale() -> void:
	print("-- Kiai-Groesse")
	var bm := _map(120.0, 4, 32)
	bm.kiai_intervals = [{"start": 10000.0, "end": 16000.0}]
	var c := DirigentChart.build(bm)
	var in_kiai := -1
	var out_kiai := -1
	for i in c.beats.size():
		if bool(c.beats[i].kiai) and in_kiai < 0:
			in_kiai = i
		if not bool(c.beats[i].kiai) and i > 6 and out_kiai < 0:
			out_kiai = i
	_ok(in_kiai >= 0, "Kiai-Schlaege vorhanden")
	if in_kiai >= 0:
		var ratio: float = (c.beats[in_kiai].pos as Vector2).length() / (c.beats[in_kiai].unit as Vector2).length()
		_ok(absf(ratio - DirigentChart.KIAI_SCALE) < 0.001, "Kiai: Figur groesser (%.3f)" % ratio)
		_ok(bool(c.bars[int(c.beats[in_kiai].bar)].ext), "Kiai: erweiterte Figur im Takt")
		_ok(not bool(c.bars[int(c.beats[maxi(out_kiai, 0)].bar)].ext) if out_kiai >= 0 else true, "ohne Kiai: klassische Figur")
	if out_kiai >= 0:
		_ok(float(c.beats[out_kiai].scale) <= 1.0, "ohne Kiai nicht groesser")


func _test_beat_scoring() -> void:
	print("-- Schlag-Wertung mit Zielfaktor")
	var c := DirigentChart.build(_map(120.0, 4, 8))
	var core := _core(c)
	var b: Dictionary = c.beats[0]
	core.cursor_moved(b.pos, float(b.t) - 100.0)
	core.update(float(b.t) + 1.0)
	_ok(core.beats_hit == 1 and is_equal_approx(core.beat_acc(), 1.0), "Mitte: Zielfaktor 1,0")
	var b2: Dictionary = c.beats[1]
	var rim: Vector2 = b2.pos + Vector2(DirigentCore.HIT_R * 0.99, 0.0)
	core.cursor_moved(rim, float(b2.t) - 100.0)
	core.update(float(b2.t) + 1.0)
	var v: float = core.beat_log[1][2]
	_ok(core.beats_hit == 2 and v >= 0.88 and v < 0.89, "Rand: Zielfaktor ~0,88 (%.3f)" % v)
	var b3: Dictionary = c.beats[2]
	core.cursor_moved(b3.pos + Vector2(DirigentCore.HIT_R * 0.5 + DirigentCore.INNER_R * 0.5, 0), float(b3.t) - 100.0)
	core.update(float(b3.t) + 1.0)
	var mid: float = core.beat_log[2][2]
	_ok(mid > 0.88 and mid < 1.0, "dazwischen interpoliert (%.3f)" % mid)
	var b4: Dictionary = c.beats[3]
	core.cursor_moved(b4.pos + Vector2(DirigentCore.HIT_R * 1.2, 0), float(b4.t) - 100.0)
	core.update(float(b4.t) + 1.0)
	_ok(core.beats_hit == 3 and float(core.beat_log[3][2]) == 0.0 and core.combo == 0, "daneben: Schlag verfehlt, Kombo weg")
	_ok(DirigentCore.beat_value(DirigentCore.INNER_R) == 1.0, "innerer Halbradius = 1,0")
	# Wertung nutzt den Cursor ZUM Schlag, nicht danach.
	var core2 := _core(c)
	core2.cursor_moved(c.beats[0].pos, float(c.beats[0].t) - 50.0)
	core2.cursor_moved(Vector2(5, 5), float(c.beats[0].t) + 30.0)
	core2.update(float(c.beats[0].t) + 40.0)
	_ok(core2.beats_hit == 1, "Cursor wird zum Schlagzeitpunkt gelesen")


func _test_cue_scoring() -> void:
	print("-- Einsatz-Wertung")
	var c := DirigentChart.build(_map(120.0, 4, 8))
	_ok(c.cues.size() == 8, "8 Einsaetze aus 8 Noten (%d)" % c.cues.size())
	var core := _core(c)
	core.key_down(0, float(c.cues[0].t))
	_ok(core.n_max == 1, "Taste A auf Zeit = MAX")
	core.key_down(1, float(c.cues[1].t) + core.w300 - 1.0)
	_ok(core.n300 == 1, "Taste B knapp = 300")
	core.key_down(0, float(c.cues[2].t) + core.w100 - 2.0)
	_ok(core.n100 == 1, "Taste A spaet = 100")
	core.update(float(c.cues[3].t) + core.w50 + 5.0)
	_ok(core.n_miss == 1 and core.combo == 0, "nicht gedrueckt = Miss, Kombo weg")
	# Gemeinsame Kombo: Schlaege und Einsaetze zaehlen in einer Reihe.
	var cc := _core(c)
	var plan := DirigentCore.bot_plan(c, 3, 0.0, 0.0, 0)
	_drive(cc, plan, 4500.0)
	_ok(cc.max_combo == cc.beats_hit + cc.n_max and cc.max_combo > 8, "gemeinsame Kombo aus Schlaegen und Einsaetzen (%d)" % cc.max_combo)
	var acc_exp := float(300 * 1 + 300 * 1 + 100) / float(300 * 4)
	_ok(absf(core.cue_acc() - acc_exp) < 1e-6, "Einsatz-Acc nach Mania-Formel")


func _test_cue_keys() -> void:
	print("-- Tasten A/B, Akkord")
	var bm := _std()
	_circle(bm, 1000.0, 0)    # A
	_circle(bm, 1500.0, 2)    # Whistle = B
	_circle(bm, 2000.0, 4)    # Finish = beide
	_circle(bm, 2500.0, 0)
	_circle(bm, 2540.0, 8)    # Clap 40 ms spaeter: zusammengefasst, beide
	var c := DirigentChart.build(bm)
	_ok(c.cues.size() == 4, "Noten < 90 ms zusammengefasst (%d)" % c.cues.size())
	_ok(int(c.cues[0].mask) == 1 and int(c.cues[1].mask) == 2, "ohne Whistle = A, Whistle = B")
	_ok(int(c.cues[2].mask) == 3, "Finish = beide Tasten")
	_ok(int(c.cues[3].mask) == 3, "zusammengefasste Noten verschiedener Tasten = beide")
	var core := _core(c)
	core.key_down(1, 1000.0)   # falsche Taste
	_ok(core.n_max == 0, "falsche Taste zaehlt nicht")
	core.update(1200.0)
	_ok(core.n_miss == 1, "Einsatz mit falscher Taste verfehlt")
	core.key_down(1, 1500.0)
	core.key_down(0, 2000.0)
	_ok(core.n_max == 1, "Akkord: eine Taste allein wertet noch nicht")
	core.key_down(1, 2005.0)
	_ok(core.n_max == 2, "Akkord: beide Tasten wertet")
	# Mania: Spalten 1-2 = A, 3-4 = B
	var mm := Beatmap.new()
	mm.general = {"Mode": "3"}
	mm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5"}
	_tp(mm, 0.0, 120.0)
	for col in 4:
		var n := ManiaNote.new()
		n.time = 1000.0 + 500.0 * col
		n.column = col
		mm.hit_objects.append(n)
	var cm := DirigentChart.build(mm)
	_ok(cm.cues.size() == 4 and int(cm.cues[0].mask) == 1 and int(cm.cues[1].mask) == 1 \
			and int(cm.cues[2].mask) == 2 and int(cm.cues[3].mask) == 2, "Mania: Spalten 1-2 = A, 3-4 = B")


func _test_weights() -> void:
	print("-- Gewichtung 40/60")
	var c := DirigentChart.build(_map(120.0, 4, 16))
	# Nur Schlaege perfekt, Einsaetze verpasst.
	var a := _core(c)
	for b in c.beats:
		a.cursor_moved(b.pos, float(b.t) - 60.0)
	_run_idle(a, c, true)
	var sa := a.stats()
	_ok(absi(int(sa.score) - 400000) < 3000, "nur Takt = ~40 %% (%d)" % int(sa.score))
	# Nur Einsaetze perfekt, Schlaege daneben.
	var b2 := _core(c)
	for cue in c.cues:
		for k in 2:
			if DirigentChart.mask_has(int(cue.mask), k):
				b2.key_down(k, float(cue.t))
	b2.update(60000.0)
	var sb := b2.stats()
	_ok(absi(int(sb.score) - 600000) < 3000, "nur Einsaetze = ~60 %% (%d)" % int(sb.score))
	_ok(float(sa.accuracy) > 0.39 and float(sa.accuracy) < 0.41, "Acc gewichtet (Takt %.3f)" % float(sa.accuracy))
	_ok(float(sb.accuracy) > 0.59 and float(sb.accuracy) < 0.61, "Acc gewichtet (Einsaetze %.3f)" % float(sb.accuracy))
	_ok(sa.mode == "dirigent" and sa.has("beats_hit") and sa.has("beats_total") and sa.has("aim_err") \
			and sa.has("max_combo") and sa.has("n_miss"), "stats(): Felder vorhanden")


## Beats aus der Hand setzen (Cursor je Schlag direkt auf den Punkt), Einsaetze auslassen.
func _run_idle(core: DirigentCore, c: DirigentChart, skip_cues: bool) -> void:
	for i in c.beats.size():
		core.cursor_moved(c.beats[i].pos, float(c.beats[i].t) - 30.0)
		core.update(float(c.beats[i].t) + 1.0)
	core.update(60000.0)


func _drive(core: DirigentCore, plan: Dictionary, t_end: float, step: float = 16.0) -> void:
	var t := 0.0
	while t < t_end:
		core.bot_step(plan, t)
		core.update(t)
		t += step


func _test_replay() -> void:
	print("-- Replay deterministisch")
	var bm := _map(120.0, 4, 40)
	var c := DirigentChart.build(bm)
	var plan := DirigentCore.bot_plan(c, 7, 30.0, 2.2, 5)   # Hand teils ausserhalb, Auslasser
	var live := _core(c)
	live.set_replay_mode(true)
	_drive(live, plan, 30000.0, 13.0)
	var s1 := live.stats()
	_ok(live.replay_log.size() > 50 and int(live.replay_log[0][1]) == DirigentCore.EV_RULES, "Log mit Regel-Marke")
	_ok(int(s1.n_miss) > 0 or int(s1.beats_hit) < int(s1.beats_total), "Lauf hat Fehler (testet mehr als SS)")
	# Replay ueber JSON-Rundlauf mit anderer Bildrate.
	var parsed = JSON.parse_string(JSON.stringify(live.replay_log))
	var rep := _core(c)
	var t := 0.0
	var idx := 0
	while t < 30000.0:
		while idx < parsed.size() and float(parsed[idx][0]) <= t:
			rep.apply_event(parsed[idx])
			idx += 1
		rep.update(t)
		t += 7.0
	var s2 := rep.stats()
	_ok(int(s1.score) == int(s2.score), "Score gleich (%d / %d)" % [int(s1.score), int(s2.score)])
	_ok(s1.n_max == s2.n_max and s1.n300 == s2.n300 and s1.n_miss == s2.n_miss \
			and s1.beats_hit == s2.beats_hit and s1.max_combo == s2.max_combo, "alle Zaehler gleich")
	# Zweiter Live-Lauf mit anderer Bildrate: gleiche Wertung wie der erste.
	var live2 := _core(c)
	live2.set_replay_mode(true)
	_drive(live2, plan, 30000.0, 16.0)
	var s3 := live2.stats()
	_ok(int(s3.score) == int(s1.score) or absf(float(s3.accuracy) - float(s1.accuracy)) < 0.02, "Wertung unabhaengig von der Bildrate (naeherungsweise)")


func _test_autoplay_ss() -> void:
	print("-- Autoplay = SS")
	for spec in [[120.0, 4], [140.0, 3], [90.0, 6], [240.0, 4], [110.0, 5]]:
		var bm := _map(float(spec[0]), int(spec[1]), 60)
		bm.kiai_intervals = [{"start": 12000.0, "end": 20000.0}]
		var c := DirigentChart.build(bm)
		var core := _core(c)
		var plan := DirigentCore.bot_plan(c, 1, 3.0, 0.8, 0)
		_drive(core, plan, c.duration_ms + 5000.0, 16.0)
		var s := core.stats()
		_ok(s.grade == "SS" and int(s.score) > 990000 and int(s.n_miss) == 0 \
				and int(s.beats_hit) == int(s.beats_total) and core.is_finished(),
			"Bot %s %d/x: SS, Score %d, Takt %d/%d" % [spec[0], spec[1], int(s.score), int(s.beats_hit), int(s.beats_total)])


func _test_stars() -> void:
	print("-- Sterne")
	var easy := DirigentChart.build(_map(80.0, 4, 40))
	var hard_bm := _std(200.0, 4)
	for i in 400:
		_circle(hard_bm, 1000.0 + float(i) * 150.0, 2 if (i / 2) % 2 == 1 else 0)
	var hard := DirigentChart.build(hard_bm)
	var se := easy.stars()
	var sh := hard.stars()
	_ok(se >= 0.0 and sh <= DirigentChart.STAR_MAX, "im Bereich 0..15 (%.2f, %.2f)" % [se, sh])
	_ok(sh > se + 1.0, "dichter + schneller = mehr Sterne (%.2f > %.2f)" % [sh, se])
	# Gleichzeitigkeit zaehlt: Akkord-Map hat mehr Sterne als gleich dichte Einzeltasten.
	var single := _std(120.0, 4)
	var chords := _std(120.0, 4)
	for i in 120:
		_circle(single, 1000.0 + float(i) * 200.0, 0)
		_circle(chords, 1000.0 + float(i) * 200.0, 4)
	_ok(DirigentChart.build(chords).stars() > DirigentChart.build(single).stars(), "Akkorde (beide Tasten) zaehlen mehr")
	_ok(DirigentChart.build(_std()).stars() == 0.0, "leere Map: 0 Sterne")


func _test_breaks() -> void:
	print("-- Pausen")
	var bm := _std(120.0, 4)
	for i in 8:
		_circle(bm, 1000.0 + float(i) * 500.0)
	for i in 8:
		_circle(bm, 30000.0 + float(i) * 500.0)
	var c := DirigentChart.build(bm)
	var mid := 0
	for b in c.beats:
		if float(b.t) > 8000.0 and float(b.t) < 28000.0:
			mid += 1
	_ok(mid <= 4, "in der Pause keine Schlaege (%d)" % mid)
	var gap := false
	for i in c.beats.size() - 1:
		gap = gap or c.is_gap(i)
	_ok(gap, "Pause als Luecke erkannt (Figur ruht)")


func _spam(core: DirigentCore, c: DirigentChart) -> void:
	for cue in c.cues:
		var t := float(cue.t)
		core.key_down(0, t)
		core.key_down(1, t + 3.0)
	core.update(float(c.cues[c.cues.size() - 1].t) + 1000.0)


func _test_anti_mash() -> void:
	print("-- Anti-Mash")
	var bm := _std()
	for i in 24:
		_circle(bm, 1000.0 + 400.0 * i, [0, 2, 4][i % 3])   # A, B, beide
	var c := DirigentChart.build(bm)
	var before := _core(c)
	before.anti_mash = false
	_spam(before, c)
	var after := _core(c)
	_spam(after, c)
	print("  Dirigent Spam A+B: vorher Einsatz-Acc %.1f%% (Misses %d), nachher %.1f%% (Misses %d)" % [
		before.cue_acc() * 100.0, before.n_miss, after.cue_acc() * 100.0, after.n_miss])
	_ok(after.cue_acc() < before.cue_acc() - 0.15 and after.n_miss > before.n_miss, "Spam: Einsatz-Acc faellt")
	# Falsche Taste = sofort Miss, danach richtige heilt nicht.
	var d := _core(c)
	d.key_down(1, float(c.cues[0].t))
	_ok(d.n_miss == 1 and d.combo == 0, "B auf A-Einsatz: sofort Miss")
	d.key_down(0, float(c.cues[0].t) + 5.0)
	_ok(d.n_miss == 1 and d.n_max == 0, "richtige danach heilt nicht")
	# Richtige zuerst, dann Zusatztaste: Treffer bleibt.
	var e := _core(c)
	e.key_down(0, float(c.cues[0].t))
	e.key_down(1, float(c.cues[0].t) + 4.0)
	_ok(e.n_max == 1 and e.is_cue_done(0) and e.n_miss == 0, "richtig dann falsch: Treffer bleibt")
	# Akzent (beide): A allein wertet nie, beide = Treffer.
	var f := _core(c)
	f.key_down(0, float(c.cues[2].t))
	f.update(float(c.cues[2].t) + f.w50 + 1.0)
	_ok(f.n_max + f.n300 == 0 and f.n_miss >= 1, "Akzent mit A allein: Miss")
	var g := _core(c)
	g.key_down(0, float(c.cues[2].t))
	g.key_down(1, float(c.cues[2].t) + 10.0)
	_ok(g.n_max == 1 and g.is_cue_done(2), "Akzent mit beiden = Treffer")
	# Leer-Druck ohne Einsatz im Fenster: nichts.
	var h := _core(c)
	h.key_down(0, 500.0)
	_ok(h.n_miss == 0, "Leer-Druck = nichts")
	_ok(DirigentCore.REPLAY_RULES == 3, "Replay-Regelversion 3")


func _test_rules_3() -> void:
	print("-- Regeln 3: Wechselschlag, Nachzuegler")
	var bm := _std()
	for i in 6:
		_circle(bm, 1000.0 + 120.0 * i, 0)   # Strom, in der Map alles A
	_circle(bm, 3000.0, 4)                    # Akzent, frei
	_circle(bm, 4000.0, 4)                    # Akzent mit Nachbar nach 120 ms
	_circle(bm, 4120.0, 0)
	_circle(bm, 5000.0, 0)
	_circle(bm, 5400.0, 0)                    # langsam: gleiche Taste bleibt
	var c := DirigentChart.build(bm)
	var masks: Array = []
	for cue in c.cues:
		masks.append(int(cue.mask))
	_ok(masks == [1, 2, 1, 2, 1, 2, 3, 1, 2, 1, 1], "Strom wechselt, enger Akzent wird einfach %s" % str(masks))
	var min_same := INF
	var last := [-INF, -INF]
	for cue in c.cues:
		for k in 2:
			if DirigentChart.mask_has(int(cue.mask), k):
				min_same = minf(min_same, float(cue.t) - float(last[k]))
				last[k] = float(cue.t)
	_ok(min_same >= DirigentChart.FAST_KEY_MS, "gleiche Taste nie unter 180 ms (%.0f)" % min_same)
	# Nachzuegler: A verpasst, A kurz danach trifft den B-Einsatz nicht (einmal).
	var bm2 := _std()
	_circle(bm2, 1000.0, 0)
	_circle(bm2, 1100.0, 2)
	_circle(bm2, 3000.0, 0)
	var c2 := DirigentChart.build(bm2)
	var d := _core(c2)
	d.update(1000.0 + d.w50 + 2.0)
	d.key_down(0, 1000.0 + d.w50 + 5.0)
	_ok(d.n_miss == 1 and not d.is_cue_done(1), "spaeter Druck nach Miss: keine falsche Taste")
	d.key_down(0, 1000.0 + d.w50 + 7.0)
	_ok(d.n_miss == 2 and d.is_cue_done(1), "Nachzuegler gilt nur einmal")
