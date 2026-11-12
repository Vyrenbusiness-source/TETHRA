extends SceneTree

## Headless-Tests fuer den Orbit-Konverter (Satelliten): OrbitConverter,
## Taiko-Tastenregel, Halten, Beat-Spawn, Sichtbarkeit, Sterne, ganze Bibliothek.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Orbit-Tests (Satelliten-Konverter) ===")
	_test_std_basic()
	_test_skill()
	_test_taiko_keys()
	_test_slider_hold()
	_test_spinner()
	_test_mania_keys()
	_test_mania_pattern()
	_test_mania_flow()
	_test_mania_hold()
	_test_spawn_on_beat()
	_test_lap_ms()
	_test_visible_limit()
	_test_min_gap()
	_test_easy()
	_test_determinism()
	_test_stars()
	_test_analyze()
	_test_library()
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


func _mania_bm(bpm: float = 120.0) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "3"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5"}
	_tp(bm, 0.0, bpm)
	return bm


func _add(bm: Beatmap, t: float, col: int, hold_ms: float = 0.0) -> void:
	var n := ManiaNote.new()
	n.time = t
	n.column = col
	if hold_ms > 0.0:
		n.is_hold = true
		n.hold_end = t + hold_ms
	bm.hit_objects.append(n)


func _std_bm(bpm: float = 120.0) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "0"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5", "ApproachRate": "9"}
	_tp(bm, 0.0, bpm)
	return bm


func _circle(bm: Beatmap, t: float, x: float = 100.0, y: float = 100.0, hs: int = 0) -> void:
	var c := HitCircle.new()
	c.time = t
	c.x = x
	c.y = y
	c.hit_sound = hs
	bm.hit_objects.append(c)


func _spinner(bm: Beatmap, t: float, end: float) -> void:
	var s := Spinner.new()
	s.time = t
	s.x = 256.0
	s.y = 192.0
	s.spin_end_time = end
	bm.hit_objects.append(s)


func _slider(bm: Beatmap, t: float, dur: float, hs: int = 0) -> HitSlider:
	var s := HitSlider.new()
	s.time = t
	s.x = 100.0
	s.y = 100.0
	s.curve_type = "B"
	s.curve_points = PackedVector2Array([Vector2(100, 100), Vector2(160, 40), Vector2(220, 100)])
	s.slides = 1
	s.length = 150.0
	s.single_duration_ms = dur
	s.hit_sound = hs
	bm.hit_objects.append(s)
	return s


## Gleichmaessige Kreise im Abstand gap_ms, Positionen laufen ueber das Feld.
func _stream(bm: Beatmap, n: int, gap_ms: float, t0: float = 1000.0) -> void:
	for i in n:
		_circle(bm, t0 + gap_ms * float(i), 60.0 + float((i * 97) % 380), 50.0 + float((i * 53) % 280))


func _in_field(p: Vector2) -> bool:
	return p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0


# --- Tests ---

func _test_std_basic() -> void:
	print("- osu!standard: Position und Zeit")
	var bm := _std_bm()
	_circle(bm, 1000.0, 256.0, 192.0)
	_circle(bm, 1500.0, 128.0, 96.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 2, "2 Ziele")
	_ok(ns[0].pos.distance_to(Vector2(0.5, 0.5)) < 1e-6, "Mitte = (0,5 | 0,5)")
	_ok(absf(ns[0].time_ms - 1000.0) < 1e-6 and not ns[0].is_hold, "Zeit, kein Halten")
	var j := ns[1].pos.distance_to(ns[0].pos)
	_ok(j > 0.1 and j < 0.36, "Sprung folgt der Map, hoechstens gekappt (%.2f)" % j)
	_ok(_in_field(ns[1].pos), "im Feld")
	_ok(OrbitConverter.convert(bm, 2)[0].laps == 2, "laps = 2 explizit")
	_ok(OrbitConverter.convert(bm, 3)[0].laps == 3 and OrbitConverter.convert(bm, 1)[0].laps == 1,
			"laps-Parameter")
	_ok(OrbitConverter.convert(null).is_empty(), "null -> leer")


func _test_skill() -> void:
	print("- Skill: AR -> Runden, CS -> Radius, treue Positionen")
	var bm := _std_bm()
	_circle(bm, 1000.0, 256.0, 192.0)
	var want := {"3": 3, "5": 3, "6": 2, "8": 2, "9": 1, "10": 1}
	var ok := true
	for ar in want:
		bm.difficulty["ApproachRate"] = ar
		ok = ok and OrbitConverter.convert(bm)[0].laps == int(want[ar])
	_ok(ok, "AR <= 5: 3, 6-8: 2, >= 9: 1 Runden (ohne Einstellung)")
	_ok(OrbitConverter.convert(bm, 3)[0].laps == 3, "Spieler-Einstellung schlaegt AR")
	_ok(absf(OrbitConverter.target_radius(bm) - 0.095) < 0.001, "CS 4 -> Radius 0,095 = 36,5/384 wie osu! (%.4f)" % OrbitConverter.target_radius(bm))
	bm.difficulty["CircleSize"] = "6"
	var r6 := OrbitConverter.target_radius(bm)
	bm.difficulty["CircleSize"] = "2"
	_ok(r6 < 0.095 and OrbitConverter.target_radius(bm) > 0.095, "hoeheres CS = kleiner")
	_ok(absf(OrbitConverter.target_radius(_mania_bm()) - OrbitConverter.MANIA_RADIUS) < 1e-6, "Mania: fester Radius")
	# dichte osu!-Map: Sprung 0.5 in 150 ms bleibt, Slider-Kurve ungekuerzt
	var d := _std_bm()
	var xs := [40.0, 440.0, 60.0, 450.0, 80.0, 420.0, 100.0, 400.0]
	for i in xs.size():
		_circle(d, 1000.0 + 150.0 * i + (0.0 if i < 8 else 0.0), xs[i], 50.0 + 30.0 * float(i))
	for i in 20:
		_circle(d, 3000.0 + 160.0 * i, 200.0 + 10.0 * (i % 5), 100.0)
	var ns := OrbitConverter.convert(d)
	var exact := true
	for i in xs.size():
		exact = exact and ns[i].pos.distance_to(Vector2(xs[i] / 512.0, (50.0 + 30.0 * float(i)) / 384.0)) < 1e-5
	_ok(exact, "dichte Map: Positionen exakt wie gemappt (Spruenge nicht gekappt)")
	var sd := _std_bm()
	_circle(sd, 500.0, 100.0, 100.0)
	for i in 30:
		_circle(sd, 800.0 + 180.0 * i, 100.0 + 8.0 * i, 100.0)
	var sl := _slider(sd, 7000.0, 1400.0, 0)
	sl.length = 300.0
	var sn := OrbitConverter.convert(sd)
	var hold: OrbitNote = null
	for n in sn:
		if n.is_hold:
			hold = n
	var plen := 0.0
	if hold != null:
		for i in range(1, hold.path.size()):
			plen += hold.path[i - 1].distance_to(hold.path[i])
	_ok(hold != null and absf(hold.end_ms - 8400.0) < 1.0 and plen > 0.5 * 300.0 / 512.0,
			"dichte Map: Slider ganz (Dauer + Laenge, %.2f)" % plen)


func _test_taiko_keys() -> void:
	print("- Taiko-Tastenregel")
	var bm := _std_bm()
	_stream(bm, 8, 400.0)
	bm.hit_objects[0].hit_sound = 0
	bm.hit_objects[1].hit_sound = 2
	bm.hit_objects[2].hit_sound = 8
	bm.hit_objects[3].hit_sound = 4
	bm.hit_objects[4].hit_sound = 4 | 2
	bm.hit_objects[5].hit_sound = 1
	var ns := OrbitConverter.convert(bm)
	_ok(ns[0].key == OrbitNote.KEY_A, "ohne Sound = A")
	_ok(ns[1].key == OrbitNote.KEY_B, "Whistle = B")
	_ok(ns[2].key == OrbitNote.KEY_B, "Clap = B")
	_ok(ns[3].key == OrbitNote.KEY_ACCENT, "Finish = Akzent")
	_ok(ns[4].key == OrbitNote.KEY_ACCENT, "Finish + Whistle = Akzent")
	_ok(ns[5].key == OrbitNote.KEY_A, "Normal = A")


func _test_slider_hold() -> void:
	print("- Slider = Halten")
	var bm := _std_bm()
	_circle(bm, 500.0, 100.0, 100.0)
	var s := _slider(bm, 2000.0, 700.0, 2)
	var sl := _slider(bm, 6000.0, 1000.0, 0)
	sl.slides = 2
	sl.length = 150.0
	_circle(bm, 8500.0, 300.0, 200.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 4, "4 Ziele (%d)" % ns.size())
	var h := ns[1]
	_ok(h.is_hold and absf(h.end_ms - 2700.0) < 1e-6, "Halten 2000..2700")
	_ok(h.path.size() >= 3 and h.path[0] == h.pos, "Pfad aus der Kurve, path[0] == pos")
	var inside := true
	for p in h.path:
		inside = inside and _in_field(p)
	_ok(inside, "Pfad im Feld")
	var bent := false
	for p in h.path:
		if absf(p.y - h.pos.y) > 0.02:
			bent = true
	_ok(bent, "echte Kurve (nicht gerade)")
	_ok(h.key == OrbitNote.KEY_B, "Slider-Kopf Whistle = B")
	var h2 := ns[2]
	var path_len := 0.0
	for i in range(1, h2.path.size()):
		path_len += h2.path[i - 1].distance_to(h2.path[i])
	_ok(h2.is_hold and path_len > 0.0 and path_len / 1.0 <= OrbitConverter.HOLD_V_MAX + 0.01,
			"Halten-Tempo <= %.1f/s (%.2f)" % [OrbitConverter.HOLD_V_MAX, path_len])
	_ok(h2.pos_at(h2.time_ms).distance_to(h2.pos) < 1e-4 and h2.pos_at(h2.end_ms).distance_to(h2.path[-1]) < 1e-4,
			"Kugel laeuft von Kopf zu Pfadende")
	s.hit_sound = 4
	var ns2 := OrbitConverter.convert(bm)
	_ok(ns2[1].key != OrbitNote.KEY_ACCENT and ns2[1].is_hold, "Halten wird nie Akzent")


func _test_spinner() -> void:
	print("- Spinner = Akzent Mitte")
	var bm := _std_bm()
	_stream(bm, 12, 250.0, 100.0)
	_circle(bm, 3500.0, 300.0, 300.0)
	_spinner(bm, 4000.0, 6000.0)
	_stream(bm, 12, 250.0, 6500.0)
	var ns := OrbitConverter.convert(bm)
	var sp: OrbitNote = null
	for n in ns:
		if absf(n.time_ms - 4000.0) < 0.5:
			sp = n
	_ok(sp != null and sp.key == OrbitNote.KEY_ACCENT, "Akzent")
	_ok(sp != null and sp.pos.distance_to(Vector2(0.5, 0.5)) < 0.2, "in der Mitte (Sprungregel darf kuerzen)")


func _test_mania_keys() -> void:
	print("- Mania 4K: Tasten")
	var bm := _mania_bm()
	var cols := [[0], [1], [2], [3], [0, 3], [1, 2], [0, 1]]
	for i in cols.size():
		for c in cols[i]:
			_add(bm, 1000.0 + 250.0 * i, c)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 7, "7 Ziele, Akkorde zusammengefasst (%d)" % ns.size())
	var want := [0, 0, 1, 1, 2, 2, 0]
	var keys: Array = []
	for n in ns:
		keys.append(n.key)
	_ok(keys == want, "Spalten 1-2 = A, 3-4 = B, Akkord ueber beide = Akzent %s" % str(keys))


func _test_mania_pattern() -> void:
	print("- Mania 4K: musikalisches A/B-Muster")
	var bm := _mania_bm()
	# Strom 120 ms: Spalten 0,1,2,3 -> Wechselschlag
	for i in 4:
		_add(bm, 1000.0 + 120.0 * i, i)
	# wiederholter Klang (gleiche Spalte) im Strom: gleiche Taste
	for i in 4:
		_add(bm, 3000.0 + 120.0 * i, 3)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 8, "8 Ziele (%d)" % ns.size())
	var alt := ns[1].key != ns[0].key and ns[2].key != ns[1].key and ns[3].key != ns[2].key
	_ok(alt, "Strom wechselt A/B")
	_ok(ns[5].key == ns[4].key and ns[6].key == ns[5].key and ns[7].key == ns[6].key, "gleiche Spalte = gleiche Taste")


func _test_mania_flow() -> void:
	print("- Mania 4K: Positionsfluss")
	var bm := _mania_bm()
	for i in 80:
		_add(bm, 1000.0 + 300.0 * i, (i * 7 + i / 3) % 4)
	var ns := OrbitConverter.convert(bm)
	var ok_field := true
	var max_jump := 0.0
	var min_sep := 9.0
	for i in ns.size():
		ok_field = ok_field and _in_field(ns[i].pos)
		if i > 0:
			max_jump = maxf(max_jump, ns[i].pos.distance_to(ns[i - 1].pos))
		for j in range(maxi(i - 8, 0), i):
			if ns[j].time_ms > ns[i].spawn_ms:
				min_sep = minf(min_sep, ns[i].pos.distance_to(ns[j].pos))
	_ok(ok_field, "alle im Feld")
	_ok(max_jump <= OrbitConverter.MANIA_MAX + 0.3, "Abstand gekappt (%.2f)" % max_jump)
	_ok(min_sep >= OrbitConverter.SEP * 0.99, "keine Ueberlappung sichtbarer Ziele (%.3f)" % min_sep)
	var moved := false
	for i in range(1, ns.size()):
		if ns[i].pos.distance_to(ns[i - 1].pos) > 0.05:
			moved = true
	_ok(moved, "Fluss bewegt sich")
	_ok(OrbitConverter.violations(ns, bm).overlap == 0, "violations: overlap 0")


func _test_mania_hold() -> void:
	print("- Mania 4K: Holds")
	var bm := _mania_bm()
	_add(bm, 1000.0, 3, 800.0)
	_add(bm, 3000.0, 0, 50.0)
	_add(bm, 4000.0, 1, 1500.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 3, "3 Ziele")
	_ok(ns[0].is_hold and ns[0].key == OrbitNote.KEY_B and absf(ns[0].end_ms - 1800.0) < 1e-6, "Hold Spalte 4 = B")
	_ok(not ns[1].is_hold, "sehr kurzer Hold = Tap")
	_ok(ns[2].is_hold and ns[2].path.size() >= 2 and ns[2].path[0] == ns[2].pos, "Hold-Pfad ab pos")
	var d := ns[0].path[-1] - ns[0].path[0]
	_ok(d.length() > 0.04 and _in_field(ns[0].path[-1]), "Pfad kurz, im Feld (%.2f)" % d.length())
	_ok(OrbitConverter.violations(ns, bm).hold == 0, "violations: hold 0")


func _test_spawn_on_beat() -> void:
	print("- Erscheinen exakt auf dem Beat")
	var bm := _std_bm(137.0)
	_tp(bm, 20123.0, 93.0)
	for i in 60:
		_circle(bm, 700.0 + 421.0 * float(i), 60.0 + float((i * 71) % 400), 40.0 + float((i * 37) % 300))
	var clock := OrbitClock.from_beatmap(bm)
	var ns := OrbitConverter.convert(bm)
	var worst := 0.0
	var early := true
	for n in ns:
		worst = maxf(worst, absf(n.spawn_ms - clock.beat_tick_at_or_before(n.spawn_ms)))
		early = early and n.spawn_ms <= n.time_ms - float(n.laps) * n.lap_ms + 1e-6
	_ok(ns.size() > 40, "genug Ziele (%d)" % ns.size())
	_ok(worst < 1.0, "Spawn-Fehler < 1 ms (%.4f)" % worst)
	_ok(early, "Vorlauf >= laps x lap_ms")
	_ok(OrbitConverter.analyze(ns, bm).spawn_err_ms < 1.0, "analyze: spawn_err_ms < 1")
	var near := 0.0
	for n in ns:
		near = maxf(near, (n.time_ms - n.spawn_ms) - float(n.laps + 1) * n.lap_ms)
	_ok(near < 1e-6, "hoechstens eine Runde Rundungsabstand")


func _test_lap_ms() -> void:
	print("- lap_ms: Beat, unter 450 ms zwei Beats, unter 225 ms vier Beats")
	var bm := _std_bm(120.0)
	_stream(bm, 6, 500.0)
	_ok(absf(OrbitConverter.convert(bm)[0].lap_ms - 500.0) < 1e-6, "120 BPM: 500 ms")
	var bm2 := _std_bm(240.0)
	_stream(bm2, 6, 500.0)
	_ok(absf(OrbitConverter.convert(bm2)[0].lap_ms - 500.0) < 1e-6, "240 BPM: 2 Beats = 500 ms")
	var bm3 := _std_bm(180.0)
	_stream(bm3, 6, 500.0)
	_ok(absf(OrbitConverter.convert(bm3)[0].lap_ms - 666.6667) < 0.01, "180 BPM (333 ms): 2 Beats")
	var bm4 := _std_bm(300.0)
	_stream(bm4, 6, 500.0)
	_ok(absf(OrbitConverter.convert(bm4)[0].lap_ms - 800.0) < 1e-6, "300 BPM (200 ms): 4 Beats = 800 ms")
	_ok(is_equal_approx(OrbitConverter.lap_ms_for(450.0), 450.0) and is_equal_approx(OrbitConverter.lap_ms_for(449.0), 898.0)
		and is_equal_approx(OrbitConverter.lap_ms_for(225.0), 450.0) and is_equal_approx(OrbitConverter.lap_ms_for(224.0), 896.0),
		"Grenzen 450 / 225 ms")
	_ok(is_equal_approx(OrbitConverter.lap_ms_for(333.0, true), 333.0), "legacy (vorher): 330-ms-Grenze")
	var n := OrbitNote.make_target(2000.0, Vector2(0.5, 0.5), 0)
	n.lap_ms = 800.0
	var even := true
	var prev := n.satellite_deg(400.0)
	for i in range(1, 160):
		var d := fposmod(n.satellite_deg(400.0 + 10.0 * i) - prev, 360.0)
		even = even and absf(d - 4.5) < 1e-3
		prev = n.satellite_deg(400.0 + 10.0 * i)
	_ok(even, "Satellit gleichmaessig (4,5 Grad je 10 ms bei 800-ms-Runde, keine Spitze)")
	_ok(is_zero_approx(n.satellite_deg(2000.0)) and is_zero_approx(n.satellite_deg(2080.0)) and n.satellite_deg(1999.0) > 359.0,
		"Satellit endet exakt oben und bleibt dort")


func _test_visible_limit() -> void:
	print("- hoechstens 6 sichtbar")
	var bm := _std_bm(150.0)
	_stream(bm, 200, 120.0)
	for laps in [1, 2, 4]:
		var ns := OrbitConverter.convert(bm, laps)
		var a := OrbitConverter.analyze(ns, bm)
		_ok(a.max_visible <= 6, "laps %d: max sichtbar %d <= 6 (%d Ziele)" % [laps, a.max_visible, ns.size()])
	var ns4 := OrbitConverter.convert(bm, 4)
	var min_laps := 9
	var lead_ok := true
	for n in ns4:
		min_laps = mini(min_laps, n.laps)
		lead_ok = lead_ok and n.time_ms - n.spawn_ms >= maxf(0.5 * n.lap_ms, 400.0) - 1.0
	_ok(lead_ok and min_laps < 4, "dichte Stellen verringern die Runden (min %d, Vorlauf >= halbe Runde und 1 Beat)" % min_laps)
	_ok(ns4.size() == 200 and OrbitConverter.convert(bm, 1).size() == 200, "keine Ziele fallen weg (%d)" % ns4.size())
	var bm2 := _std_bm(120.0)
	_stream(bm2, 8, 1000.0)
	var sparse := OrbitConverter.convert(bm2, 4)
	_ok(sparse[3].laps == 4, "lockere Stellen behalten alle Runden")
	_ok(OrbitConverter.violations(OrbitConverter.convert(bm, 2), bm).visible == 0, "violations: visible 0")


func _test_min_gap() -> void:
	print("- Mindestabstand 75 ms")
	var bm := _std_bm()
	_circle(bm, 1000.0)
	_circle(bm, 1040.0, 300.0, 300.0)
	_circle(bm, 1080.0, 200.0, 200.0)
	_circle(bm, 1150.0, 220.0, 150.0)
	_circle(bm, 1500.0, 150.0, 250.0)
	var ns := OrbitConverter.convert(bm)
	var gaps_ok := true
	for i in range(1, ns.size()):
		gaps_ok = gaps_ok and ns[i].time_ms - ns[i - 1].time_ms >= 75.0 - 1e-6
	_ok(gaps_ok and ns.size() == 3, "zu dichte Ziele entfallen (%d)" % ns.size())
	var bm2 := _std_bm()
	_slider(bm2, 1000.0, 500.0)
	_circle(bm2, 1520.0, 300.0, 300.0)
	_circle(bm2, 1700.0, 300.0, 200.0)
	var ns2 := OrbitConverter.convert(bm2)
	_ok(ns2.size() == 2 and ns2[1].time_ms >= 1500.0 + 75.0, "kein Ziel unmittelbar nach dem Halten")


func _test_easy() -> void:
	print("- leichte Maps: kleine Spruenge, keine Akzente")
	var bm := _std_bm(100.0)
	for i in 30:
		_circle(bm, 1000.0 + 600.0 * float(i), 40.0 + float((i * 211) % 440), 40.0 + float((i * 131) % 300), 4 if i % 3 == 0 else 0)
	var ns := OrbitConverter.convert(bm)
	var a := OrbitConverter.analyze(ns, bm)
	_ok(a.nps < 2.5, "leicht: %.2f Ziele/s" % a.nps)
	_ok(a.accent_share == 0.0, "keine Akzente")
	var maxj := 0.0
	for i in range(1, ns.size()):
		maxj = maxf(maxj, ns[i].pos.distance_to(ns[i - 1].pos))
	_ok(maxj <= OrbitConverter.EASY_JUMP_MAX + 1e-4 or maxj <= 0.3 + 1e-4, "kleine Spruenge (%.2f)" % maxj)
	var hard := _std_bm(150.0)
	for i in 80:
		_circle(hard, 1000.0 + 200.0 * float(i), 40.0 + float((i * 211) % 440), 40.0 + float((i * 131) % 300), 4 if i % 4 == 0 else 0)
	_ok(OrbitConverter.analyze(OrbitConverter.convert(hard), hard).accent_share > 0.1, "dichte Maps behalten Akzente")
	var hb := _std_bm(60.0)
	_slider(hb, 1000.0, 3000.0)
	_circle(hb, 6000.0, 300.0, 100.0)
	_circle(hb, 9000.0, 300.0, 100.0)
	var hn := OrbitConverter.convert(hb)
	_ok(hn[0].is_hold and hn[0].end_ms - hn[0].time_ms <= 2.0 * 1000.0 + 1e-6, "leichte Maps: Halten <= 2 Beats")


func _test_determinism() -> void:
	print("- Determinismus")
	var bm := _std_bm()
	_stream(bm, 150, 230.0)
	var a := OrbitConverter.convert(bm)
	var b := OrbitConverter.convert(bm)
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			same = same and a[i].time_ms == b[i].time_ms and a[i].pos == b[i].pos and a[i].key == b[i].key \
					and a[i].spawn_ms == b[i].spawn_ms and a[i].laps == b[i].laps and a[i].path == b[i].path
	_ok(same, "std: zweimal gleich")
	var m := _mania_bm()
	for i in 120:
		_add(m, 1000.0 + 180.0 * i, (i * 5) % 4, 400.0 if i % 9 == 0 else 0.0)
	var c := OrbitConverter.convert(m)
	var d := OrbitConverter.convert(m)
	same = c.size() == d.size()
	if same:
		for i in c.size():
			same = same and c[i].pos == d[i].pos and c[i].key == d[i].key and c[i].path == d[i].path \
					and c[i].spawn_ms == d[i].spawn_ms
	_ok(same, "4K: zweimal gleich")


func _test_stars() -> void:
	print("- Sterne-Skala")
	var easy := _std_bm(100.0)
	_stream(easy, 40, 700.0)
	var mid := _std_bm(150.0)
	_stream(mid, 200, 250.0)
	var hard := _std_bm(200.0)
	_stream(hard, 500, 110.0)
	var se := OrbitConverter.stars(OrbitConverter.convert(easy))
	var sm := OrbitConverter.stars(OrbitConverter.convert(mid))
	var sh := OrbitConverter.stars(OrbitConverter.convert(hard))
	print("  leicht %.2f, mittel %.2f, schwer %.2f" % [se, sm, sh])
	_ok(se < 2.5, "leicht < 2,5")
	_ok(se < sm and sm < sh, "monoton: leicht < mittel < schwer")
	_ok(sh <= 15.0 and se >= 0.0, "Bereich 0..15")
	_ok(OrbitConverter.stars([] as Array[OrbitNote]) == 0.0, "leer = 0")
	var a: Array[OrbitNote] = []
	var b: Array[OrbitNote] = []
	for i in 60:
		a.append(OrbitNote.make_target(1000.0 + 300.0 * i, Vector2(0.5, 0.5), 0))
		b.append(OrbitNote.make_target(1000.0 + 300.0 * i, Vector2(0.1 if i % 2 == 0 else 0.9, 0.5), 0))
	_ok(OrbitConverter.stars(b) > OrbitConverter.stars(a), "grosse Spruenge > Stillstand")
	var c: Array[OrbitNote] = []
	for i in 60:
		c.append(OrbitNote.make_target(1000.0 + 300.0 * i, Vector2(0.5, 0.5), i % 2))
	_ok(OrbitConverter.stars(c) > OrbitConverter.stars(a), "Tastenwechsel > gleiche Taste")
	var d: Array[OrbitNote] = []
	for i in 60:
		if i % 3 == 0:
			d.append(OrbitNote.make_hold(1000.0 + 300.0 * i, 1000.0 + 300.0 * i + 250.0,
					PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.55, 0.5)]), 0))
		else:
			d.append(OrbitNote.make_target(1000.0 + 300.0 * i, Vector2(0.5, 0.5), 0))
	_ok(OrbitConverter.stars(d) > OrbitConverter.stars(a), "Halten > nur Taps")


func _test_analyze() -> void:
	print("- analyze")
	var bm := _std_bm()
	_stream(bm, 40, 300.0)
	bm.hit_objects[5].hit_sound = 4
	_slider(bm, 13500.0, 600.0)
	var ns := OrbitConverter.convert(bm)
	var a := OrbitConverter.analyze(ns, bm)
	_ok(a.count == ns.size() and a.nps > 2.5 and a.nps < 4.5, "count/nps (%.2f)" % a.nps)
	_ok(a.accent_share > 0.0 and a.hold_share > 0.0, "Akzent-/Halte-Anteil")
	_ok(a.mean_jump > 0.0 and a.mean_jump_speed > 0.0, "mittlerer Sprung")
	_ok(a.max_visible >= 1 and a.max_visible <= 6, "max sichtbar")
	_ok(OrbitConverter.analyze([] as Array[OrbitNote]).count == 0, "leer")


func _test_library() -> void:
	print("- ganze Bibliothek")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var files := Array(da.get_files())
	files.sort()
	var maps := 0
	var bad_maps := 0
	var tot := {}
	var worst_vis := 0
	var stars_list: Array[float] = []
	var easy_stars: Array[float] = []
	var errs := 0
	for f in files:
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.hit_objects.size() < 2 or (bm.is_mania() and bm.column_count() != 4):
				continue
			maps += 1
			for laps in [1, 2, 3]:
				var ns := OrbitConverter.convert(bm, laps)
				var v := OrbitConverter.violations(ns, bm)
				var bad := 0
				for k in v:
					if k != "targets":
						bad += int(v[k])
						tot[k] = int(tot.get(k, 0)) + int(v[k])
				if bad > 0:
					bad_maps += 1
					if errs < 5:
						errs += 1
						print("  Verstoss %s [%s] laps %d: %s" % [str(f).left(30), bm.version_name(), laps, str(v)])
				if laps == 2:
					worst_vis = maxi(worst_vis, OrbitConverter.analyze(ns).max_visible)
					if ns.size() >= 20:
						var s := OrbitConverter.stars(ns)
						stars_list.append(s)
						if OrbitConverter.analyze(ns).nps < 2.5:
							easy_stars.append(s)
	print("  %d Diffs, Verstoesse %s" % [maps, str(tot)])
	_ok(maps > 0 and bad_maps == 0, "ganze Bibliothek ohne Verstoss (%d Diffs x 3 Vorlaeufe)" % maps)
	_ok(worst_vis <= 6, "nie mehr als 6 sichtbar (%d)" % worst_vis)
	if stars_list.size() > 20:
		stars_list.sort()
		var med := stars_list[stars_list.size() / 2]
		_ok(med >= 3.5 and med <= 4.5, "Sterne-Median ~4 (%.2f)" % med)
		_ok(stars_list[-1] <= 15.0 and stars_list[0] >= 0.0, "Sterne in 0..15 (%.2f .. %.2f)" % [stars_list[0], stars_list[-1]])
		if easy_stars.size() >= 10:
			easy_stars.sort()
			var q90 := easy_stars[int(easy_stars.size() * 0.9)]
			_ok(q90 < 2.5, "leichte Diffs (< 2,5 Ziele/s): 90 %% unter 2,5 Sterne (%.2f, %d Diffs)" % [q90, easy_stars.size()])
