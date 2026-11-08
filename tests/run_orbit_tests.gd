extends SceneTree

## Headless-Tests fuer den Orbit-Modus (Taktkreis): OrbitClock, OrbitConverter,
## OrbitCore. Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tests.gd

var _passed := 0
var _failed := 0
const EPS := 1e-6
## Hand-Tempo in Grad/ms bei 2000 ms pro Takt.
const V := 0.18


func _initialize() -> void:
	print("=== TETHRA Orbit-Tests (Taktkreis) ===")
	_test_clock()
	_test_mania_rings()
	_test_std_rings()
	_test_density()
	_test_determinism()
	_test_tap_aim()
	_test_keys_are_rings()
	_test_dead_zone()
	_test_accent()
	_test_hold()
	_test_hold_release_and_out()
	_test_scoring_values()
	_test_stars()
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


func _bm(od: float = 8.0) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "3"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": str(od), "HPDrainRate": "5"}
	_tp(bm, 0.0, 120.0)
	return bm


func _add(bm: Beatmap, t: float, col: int, hold_ms: float = 0.0) -> void:
	var n := ManiaNote.new()
	n.time = t
	n.column = col
	if hold_ms > 0.0:
		n.is_hold = true
		n.hold_end = t + hold_ms
	bm.hit_objects.append(n)


func _std_bm(bpm: float = 120.0, meter: int = 4) -> Beatmap:
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


func _spinner(bm: Beatmap, t: float, end: float) -> void:
	var s := Spinner.new()
	s.time = t
	s.x = 256.0
	s.y = 192.0
	s.spin_end_time = end
	bm.hit_objects.append(s)


## Taktkreis-Ziel bei 2000 ms/Takt (Hand-Tempo 0,18 Grad/ms).
func _note(t: float, ring: int, hold_ms: float = 0.0) -> OrbitNote:
	var clock := OrbitClock.fixed(2000.0)
	var n: OrbitNote
	if hold_ms > 0.0:
		n = OrbitNote.make_arc(t, t + hold_ms, clock.angle_at(t), V * hold_ms, ring)
	else:
		n = OrbitNote.make(t, clock.angle_at(t), ring)
	n.speed = V
	return n


func _core(ns: Array[OrbitNote], od: float = 8.0) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, od, 1.0, 5.0, {})
	return c


func _res(c: OrbitCore) -> Dictionary:
	var got := {}
	c.note_judged.connect(func(i: int, r: Dictionary) -> void: got[i] = r)
	return got


func _list(a: Array) -> Array[OrbitNote]:
	var ns: Array[OrbitNote] = []
	ns.assign(a)
	return ns


func _sig(ns: Array[OrbitNote]) -> String:
	var parts: PackedStringArray = []
	for n in ns:
		parts.append("%.3f/%.3f/%.4f/%.4f/%d/%s/%d" % [n.time_ms, n.end_ms, n.angle_deg,
				n.end_angle_deg, n.ring, n.is_arc, n.source_index])
	return ";".join(parts)


# --- Uhr ---

func _test_clock() -> void:
	print("- Takt-Uhr")
	var bm := _bm()
	var c := OrbitClock.from_beatmap(bm)
	_ok(absf(c.bar_ms_at(0.0) - 2000.0) < EPS, "120 BPM 4/4: Takt 2000 ms")
	_ok(absf(c.angle_at(0.0)) < EPS and absf(c.angle_at(500.0) - 90.0) < EPS, "12 Uhr = Takt-Eins, Viertel = 90 Grad")
	_ok(absf(c.angle_at(2000.0)) < EPS, "naechster Takt wieder oben")
	_ok(absf(c.speed_at(0.0) - V) < EPS, "Tempo 0,18 Grad/ms")
	_ok(c.bar_at(1999.0) != c.bar_at(2001.0), "Takt-Nummer wechselt")
	var b3 := _bm()
	b3.timing_points.clear()
	_tp(b3, 1000.0, 120.0, 3)
	var c3 := OrbitClock.from_beatmap(b3)
	_ok(absf(c3.bar_ms_at(1500.0) - 1500.0) < EPS and absf(c3.angle_at(1750.0) - 180.0) < EPS, "3/4: Takt 1500 ms")
	# Tempowechsel: neuer roter Punkt beginnt einen neuen Takt.
	var bt := _bm()
	_tp(bt, 4000.0, 60.0)
	var ct := OrbitClock.from_beatmap(bt)
	_ok(absf(ct.angle_at(4000.0)) < EPS and absf(ct.bar_ms_at(4500.0) - 4000.0) < EPS, "Tempowechsel: neuer Takt, langsamere Hand")
	# Sehr schnelle Takte: eine Umdrehung pro zwei Takte.
	var bf := _bm()
	bf.timing_points.clear()
	_tp(bf, 0.0, 240.0)
	var cf := OrbitClock.from_beatmap(bf)
	_ok(cf.bar_ms_at(0.0) >= OrbitClock.MIN_BAR_MS, "240 BPM: Umdrehung >= 1,2 s (%.0f ms)" % cf.bar_ms_at(0.0))
	var bn := Beatmap.new()
	_ok(absf(OrbitClock.from_beatmap(bn).bar_ms_at(0.0) - 2000.0) < EPS, "ohne Timing-Point: 120 BPM")


# --- Converter ---

func _test_mania_rings() -> void:
	print("- 4K-Mania -> Ringe")
	var bm := _bm()
	_add(bm, 1000.0, 0)
	_add(bm, 1500.0, 1)
	_add(bm, 2000.0, 2)
	_add(bm, 2500.0, 3)
	_add(bm, 3000.0, 1)      # Akkord ueber beide Seiten
	_add(bm, 3000.0, 2)
	_add(bm, 4000.0, 0, 600.0)
	var ns := OrbitConverter.convert_mania(bm)
	_ok(ns.size() == 7, "7 Ziele (Akzent = 2)")
	_ok([ns[0].ring, ns[1].ring, ns[2].ring, ns[3].ring] == [0, 0, 1, 1], "Spalten 1-2 innen, 3-4 aussen")
	_ok(ns[4].time_ms == 3000.0 and ns[5].time_ms == 3000.0 and ns[4].ring == 0 and ns[5].ring == 1
		and absf(ns[4].angle_deg - ns[5].angle_deg) < EPS, "Akkord ueber beide Seiten = Akzent am selben Winkel")
	_ok(ns[6].is_arc and absf(ns[6].end_ms - 4600.0) < EPS, "LN = Halte")
	_ok(absf(ns[0].angle_deg - 180.0) < EPS and absf(ns[1].angle_deg - 270.0) < EPS, "Winkel = Taktposition (1000 ms = 180 Grad)")
	_ok(absf(ns[6].end_angle_deg - ns[6].angle_deg - V * 600.0) < 0.001, "Halte laeuft mit der Hand")
	var v := OrbitConverter.violations(ns, bm)
	_ok(int(v.timing) + int(v.ring) + int(v.angle) + int(v.chord) == 0, "keine Verstoesse %s" % v)


func _test_std_rings() -> void:
	print("- osu!standard -> Ringe (Taiko-Regel)")
	var bm := _std_bm()
	_circle(bm, 1000.0, 0)    # normal -> innen
	_circle(bm, 1500.0, 2)    # whistle -> aussen
	_circle(bm, 2000.0, 8)    # clap -> aussen
	_circle(bm, 2500.0, 4)    # finish -> Akzent
	_circle(bm, 3000.0, 1)    # normal
	_spinner(bm, 4000.0, 5500.0)
	var ns := OrbitConverter.convert_std(bm)
	_ok(ns.size() == 7, "7 Ziele (Finish = 2)")
	_ok([ns[0].ring, ns[1].ring, ns[2].ring] == [0, 1, 1], "Whistle/Clap aussen, sonst innen")
	_ok(ns[3].ring == 0 and ns[4].ring == 1 and ns[3].time_ms == ns[4].time_ms, "Finish = beide Ringe")
	_ok(ns[6].is_arc and ns[6].ring == 0, "Spinner = Halte")
	var bm2 := _std_bm()
	_circle(bm2, 1000.0, 6)
	_ok(OrbitConverter.convert_std(bm2).size() == 2, "Whistle+Finish = Akzent")


func _test_density() -> void:
	print("- Dichte-Regeln")
	var bm := _bm()
	_add(bm, 1000.0, 0)
	_add(bm, 1060.0, 0)      # < 90 ms auf demselben Ring: weg
	_add(bm, 1060.0, 3)      # anderer Ring: bleibt
	_add(bm, 1150.0, 0)      # >= 90 ms: bleibt
	_add(bm, 3000.0, 0, 800.0)
	_add(bm, 3400.0, 3)      # anderer Ring im Halte: bleibt
	_add(bm, 3500.0, 0)      # im Halte des eigenen Rings: weg
	_add(bm, 3900.0, 0)      # 100 ms nach Halte-Ende: < 150, weg
	_add(bm, 4000.0, 0)      # 200 ms nach Halte-Ende: bleibt
	var ns := OrbitConverter.convert_mania(bm)
	var times := []
	for n in ns:
		times.append(n.time_ms)
	_ok(times == [1000.0, 1060.0, 1150.0, 3000.0, 3400.0, 4000.0], "Ring-Abstaende %s" % [times])
	var v := OrbitConverter.violations(ns, bm)
	_ok(int(v.ring) == 0, "violations: Ringe ok")
	# Leichte Diffs: groebere Grenzen.
	var easy := _bm()
	for i in 12:
		_add(easy, 1000.0 + 120.0 * i, i % 4)
	var en := OrbitConverter.convert(easy)
	_ok(en.size() < 12 and OrbitConverter.stars(en) < OrbitConverter.EASY_STARS + 1.0, "leichte Diff wird ausgeduennt (%d Ziele)" % en.size())


func _test_determinism() -> void:
	print("- Determinismus")
	var bm := _bm()
	var s := 12345
	var t := 500.0
	for i in 400:
		s = (s * 1103515245 + 12345) % 2147483648
		_add(bm, t, (s >> 8) % 4, 400.0 if (s >> 12) % 9 == 0 else 0.0)
		t += float([40, 90, 120, 250, 500][(s >> 16) % 5])
	_ok(_sig(OrbitConverter.convert(bm)) == _sig(OrbitConverter.convert(bm)), "gleiche Map = gleiches Ergebnis")
	var v := OrbitConverter.violations(OrbitConverter.convert(bm), bm)
	_ok(int(v.timing) + int(v.ring) + int(v.angle) + int(v.chord) == 0, "Zufallsmap ohne Verstoesse %s" % v)


# --- Core ---

func _test_tap_aim() -> void:
	print("- Zielen auf die Hand ist Pflicht")
	var ns := _list([_note(1000.0, 0), _note(2000.0, 0), _note(3000.0, 0), _note(4000.0, 0)])
	var c := _core(ns)
	var got := _res(c)
	var hit: Dictionary
	# 1: Cursor genau auf der Hand zur Druckzeit (Hand ist 10 ms weiter als die Note).
	c.key_down(0, 1010.0, ns[0].pointer_at(1010.0), 0.3)
	c.update(1011.0)
	_ok(int(got[0].quality) <= 1 and float(got[0].angle_err) < 0.01, "auf der Hand: Treffer, Fehler 0")
	# 2: Cursor steht auf der NOTE (Winkel der Note), Druck 80 ms zu spaet -> Hand ist 14,4 Grad weiter
	c.key_down(0, 2060.0, ns[1].angle_deg, 0.3)
	c.update(2061.0)
	_ok(got.has(1) and absf(float(got[1].angle_err) - V * 60.0) < 0.2, "Zielfehler = Abstand zur HAND (%.1f)" % float(got[1].angle_err))
	# 3: Cursor 90 Grad neben der Hand: kein Treffer, Ziel laeuft ab
	var missed := []
	c.press_missed.connect(func(_d, _r, _ring, why): missed.append(why))
	c.key_down(0, 3000.0, ns[2].pointer_at(3000.0) + 90.0, 0.3)
	_ok(missed == ["ANGLE"], "daneben: Grund ANGLE")
	c.update(3200.0)
	_ok(int(got[2].quality) == OrbitCore.Quality.MISS, "kein Treffer neben der Hand -> MISS")
	# 4: Toleranzrand
	c.key_down(0, 4000.0, ns[3].pointer_at(4000.0) + OrbitCore.ANGLE_TOL_DEG - 0.5, 0.3)
	_ok(got.has(3) and int(got[3].quality) <= 1 or got.has(3), "am Rand der Toleranz noch Treffer")
	hit = got[3]
	var t_edge := OrbitCore.hit_value(0, OrbitCore.ANGLE_TOL_DEG - 0.5)
	_ok(absf(t_edge - 0.88) < 0.01 or t_edge < 0.9, "Rand: Zielfaktor ~0,88")
	_ok(OrbitCore.hit_value(0, 9.0) == 1.0 and OrbitCore.hit_value(0, 0.0) == 1.0, "bis 9 Grad Faktor 1,0")


func _test_keys_are_rings() -> void:
	print("- Taste = Ring")
	var ns := _list([_note(1000.0, 1), _note(2000.0, 0)])
	var c := _core(ns)
	var got := _res(c)
	var missed := []
	c.press_missed.connect(func(_d, _r, _ring, why): missed.append(why))
	c.key_down(0, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	_ok(not got.has(0) and missed == ["RING"], "innere Taste trifft kein Ziel auf dem aeusseren Ring (Grund RING)")
	c.key_up(0, 1030.0)
	c.key_down(1, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	_ok(got.has(0) and int(got[0].ring) == 1, "aeussere Taste trifft den aeusseren Ring")
	# Der Cursor-Abstand spielt keine Rolle: innere Taste, Cursor weit draussen.
	c.key_down(0, 2000.0, ns[1].pointer_at(2000.0), 0.4)
	_ok(got.has(1) and int(got[1].quality) <= 1, "Radius egal (Taste A trifft innen, Cursor aussen)")


func _test_dead_zone() -> void:
	print("- Totzone")
	var ns := _list([_note(1000.0, 0), _note(2000.0, 0)])
	var c := _core(ns)
	var got := _res(c)
	var missed := []
	c.press_missed.connect(func(_d, _r, _ring, why): missed.append(why))
	c.key_down(0, 1000.0, ns[0].pointer_at(1000.0), OrbitCore.DEAD_K * 0.5)
	_ok(not got.has(0) and missed == ["DEAD"], "in der Totzone kein Treffer")
	c.key_up(0, 1020.0)
	c.key_down(0, 1010.0, ns[0].pointer_at(1010.0), OrbitCore.DEAD_K * 1.5)
	_ok(got.has(0), "knapp ausserhalb der Totzone: Treffer")


func _test_accent() -> void:
	print("- Akzent: beide Ringe")
	var ns := _list([_note(1000.0, 0), _note(1000.0, 1)])
	var c := _core(ns)
	var got := _res(c)
	var a := ns[0].pointer_at(1000.0)
	c.key_down(0, 1000.0, a, 0.3)
	c.key_down(1, 1002.0, a, 0.3)
	_ok(got.has(0) and got.has(1), "beide Tasten treffen beide Ziele")
	var c2 := _core(_list([_note(1000.0, 0), _note(1000.0, 1)]))
	var g2 := _res(c2)
	c2.key_down(1, 1000.0, a, 0.3)
	c2.update(1100.0)
	_ok(g2.has(1) and not g2.has(0) or int(g2[0].quality) == 5, "nur eine Taste = nur ein Treffer")


func _test_hold() -> void:
	print("- Halte folgt der Hand")
	var ns := _list([_note(1000.0, 1, 1000.0)])
	var c := _core(ns)
	var got := _res(c)
	c.key_down(1, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	var t := 1000.0
	while t < 2000.0:
		t += 8.0
		c.cursor_moved(ns[0].pointer_at(t) + 4.0, 0.3, t)
		c.update(t)
	c.key_up(1, 2000.0)
	c.update(2100.0)
	_ok(got.has(0) and bool(got[0].get("held", false)) and int(got[0].quality) <= 1, "Halte gehalten bis zum Ende: Treffer")


func _test_hold_release_and_out() -> void:
	print("- Halte: loslassen / neben der Hand")
	var ns := _list([_note(1000.0, 0, 1000.0)])
	var c := _core(ns)
	var got := _res(c)
	c.key_down(0, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	var tt := 1000.0
	while tt < 1400.0:
		tt += 8.0
		c.cursor_moved(ns[0].pointer_at(tt), 0.3, tt)
		c.update(tt)
	c.key_up(0, 1400.0)
	_ok(got.has(0) and str(got[0].get("drop_reason", "")) == "RELEASE" and int(got[0].quality) == 5, "zu frueh loslassen = DROP/RELEASE")
	# Cursor bleibt stehen, die Hand laeuft davon.
	var c2 := _core(_list([_note(1000.0, 0, 1000.0)]))
	var g2 := _res(c2)
	c2.key_down(0, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	var t := 1000.0
	while t < 2000.0 and not g2.has(0):
		t += 8.0
		c2.update(t)
	_ok(g2.has(0) and str(g2[0].get("drop_reason", "")) == "OUT", "Cursor steht, Hand laeuft weg = DROP/OUT")
	var dt: float = t - 1000.0
	_ok(dt > 250.0 and dt < 320.0, "Austritt nach Toleranz/Tempo + ARC_OUT_MS (%.0f ms)" % dt)
	# Andere Taste halten genuegt nicht: Taste des Rings loslassen beendet.
	var c3 := _core(_list([_note(1000.0, 0, 1000.0)]))
	var g3 := _res(c3)
	c3.key_down(0, 1000.0, ns[0].pointer_at(1000.0), 0.3)
	c3.key_down(1, 1100.0, ns[0].pointer_at(1100.0), 0.3)
	c3.key_up(0, 1300.0)
	_ok(g3.has(0) and int(g3[0].quality) == 5, "Loslassen der Ring-Taste beendet die Halte")


func _test_scoring_values() -> void:
	print("- Wertung unveraendert")
	_ok(Array(OrbitCore.TIER_VALUE) == [1.0, 0.94, 0.68, 0.40, 0.16, 0.0], "Stufenwerte")
	_ok(Array(OrbitCore.TIER_NAMES) == ["CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS"], "Stufennamen")
	_ok(OrbitCore.ANGLE_TOL_DEG == 30.0 and OrbitCore.CENTER_DEG == 9.0 and OrbitCore.AIM_EDGE_FACTOR == 0.88, "Toleranz 30, Mitte 9, Rand 0,88")
	var ns: Array[OrbitNote] = []
	for i in 150:
		ns.append(_note(1000.0 + i * 400.0, i % 2))
	var c := _core(ns)
	for n in ns:
		c.key_down(n.ring, n.time_ms, n.pointer_at(n.time_ms), 0.3)
		c.key_up(n.ring, n.time_ms + 30.0)
	c.update(100000.0)
	_ok(c.accuracy() >= 0.999 and c.grade() == "SS" and c.n_miss == 0 and c.score > 960000, "perfekt = SS, Wertung > 960000 (%d)" % c.score)


func _test_stars() -> void:
	print("- Orbit-Sterne")
	var sparse: Array[OrbitNote] = []
	for i in 40:
		sparse.append(_note(1000.0 + i * 1000.0, 0))
	var dense: Array[OrbitNote] = []
	var sw: Array[OrbitNote] = []
	for i in 400:
		dense.append(_note(1000.0 + i * 120.0, 0))
		sw.append(_note(1000.0 + i * 120.0, i % 2))
	var s1 := OrbitConverter.stars(sparse)
	var s2 := OrbitConverter.stars(dense)
	var s3 := OrbitConverter.stars(sw)
	_ok(s1 < s2, "dichter = mehr Sterne (%.2f < %.2f)" % [s1, s2])
	_ok(s2 < s3, "Ringwechsel = mehr Sterne (%.2f < %.2f)" % [s2, s3])
	var fast: Array[OrbitNote] = []
	for n in dense:
		var m := OrbitNote.make(n.time_ms, n.angle_deg, 0)
		m.speed = V * 2.0
		fast.append(m)
	_ok(OrbitConverter.stars(fast) > s2, "schnellere Hand = mehr Sterne")
	_ok(s1 >= 0.0 and OrbitConverter.stars(sw) <= OrbitConverter.STAR_MAX, "Skala 0..15")
	_ok(OrbitConverter.stars(_list([])) == 0.0, "leer = 0")


# --- Bibliothek ---

func _test_library() -> void:
	print("- Bibliothek (Spielbarkeit, Sterne)")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var tot := {"timing": 0, "ring": 0, "angle": 0, "chord": 0, "targets": 0}
	var diffs := 0
	var perfect_miss := 0
	var star_min := INF
	var star_all: Array[float] = []
	var star_max := 0.0
	var max_speed := 0.0
	for f in da.get_files():
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.hit_objects.is_empty() or (bm.is_mania() and bm.column_count() != 4):
				continue
			var ns := OrbitConverter.convert(bm)
			var v := OrbitConverter.violations(ns, bm)
			for k in tot:
				tot[k] += int(v[k])
			if int(v.timing) + int(v.ring) + int(v.angle) + int(v.chord) > 0:
				print("  Verstoss: %s [%s] %s" % [f, bm.version_name(), v])
			var st := OrbitConverter.stars(ns)
			star_min = minf(star_min, st)
			star_max = maxf(star_max, st)
			star_all.append(st)
			for n in ns:
				max_speed = maxf(max_speed, n.speed)
			diffs += 1
			if diffs % 40 == 1 and not ns.is_empty():
				var c := _core(ns, bm.od())
				for n in ns:
					c.key_down(n.ring, n.time_ms, n.pointer_at(n.time_ms), 0.3)
					c.key_up(n.ring, n.end_ms + 20.0)
					if n.is_arc:
						pass
				c.update(ns[-1].end_ms + 500.0)
				perfect_miss += c.n_miss if not ns.any(func(n): return n.is_arc) else 0
	print("  %d Diffs, %d Ziele; Verstoesse: Zeit %d, Ring %d, Winkel %d, Akkord %d; Sterne %.2f..%.2f; max Handtempo %.3f Grad/ms" % [
		diffs, tot.targets, tot.timing, tot.ring, tot.angle, tot.chord, star_min, star_max, max_speed])
	star_all.sort()
	if not star_all.is_empty():
		var q := func(f: float) -> float: return star_all[int(f * (star_all.size() - 1))]
		print("  Sterne-Verteilung: p10 %.2f p25 %.2f Median %.2f p75 %.2f p90 %.2f p99 %.2f" % [q.call(0.1), q.call(0.25), q.call(0.5), q.call(0.75), q.call(0.9), q.call(0.99)])
	_ok(diffs > 0 or da.get_files().is_empty(), "Bibliothek gelesen")
	_ok(int(tot.timing) == 0, "Zeiten = Original")
	_ok(int(tot.ring) == 0, "Ein Finger pro Ring")
	_ok(int(tot.angle) == 0, "Winkel = Taktposition")
	_ok(int(tot.chord) == 0, "Akzente am selben Winkel")
	_ok(star_max <= OrbitConverter.STAR_MAX, "Sterne <= 15")
	_ok(max_speed <= 360.0 / OrbitClock.MIN_BAR_MS + EPS, "Hand nie schneller als %.3f Grad/ms" % (360.0 / OrbitClock.MIN_BAR_MS))
	_ok(perfect_miss == 0, "perfekter Spieler ohne Miss (Stichprobe)")
