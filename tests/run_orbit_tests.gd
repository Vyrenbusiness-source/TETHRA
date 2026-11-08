extends SceneTree

## Headless-Tests fuer den Orbit-Modus (Bahnen): OrbitClock, OrbitPath,
## OrbitTrack, OrbitConverter, OrbitCore. Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tests.gd

var _passed := 0
var _failed := 0
const EPS := 1e-6
## Phasen-Tempo in Grad/ms bei 2000 ms pro Takt (Taktphase der Noten).
const V := 0.18
## Bahn der Tests: Kreis, 2000 ms pro Takt.
var _tr := OrbitTrack.fixed(OrbitClock.fixed(2000.0), OrbitPath.CIRCLE)


func _initialize() -> void:
	print("=== TETHRA Orbit-Tests (Bahnen) ===")
	_test_clock()
	_test_paths()
	_test_shape_plan()
	_test_mania_rings()
	_test_std_rings()
	_test_density()
	_test_determinism()
	_test_tap_aim()
	_test_keys_are_rings()
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


## Bahnen-Ziel bei 2000 ms/Takt (Kreis).
func _note(t: float, ring: int, hold_ms: float = 0.0) -> OrbitNote:
	var clock := OrbitClock.fixed(2000.0)
	var n: OrbitNote
	if hold_ms > 0.0:
		n = OrbitNote.make_arc(t, t + hold_ms, clock.angle_at(t), V * hold_ms, ring)
	else:
		n = OrbitNote.make(t, clock.angle_at(t), ring)
	n.speed = _tr.speed_at(t)
	return n


func _head(t: float) -> Vector2:
	return _tr.head(t)


func _core(ns: Array[OrbitNote], od: float = 8.0) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, od, 1.0, 5.0, {})
	c.set_track(_tr)
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
	_ok(absf(c.angle_at(0.0)) < EPS and absf(c.angle_at(500.0) - 90.0) < EPS, "Takt-Eins = Phase 0, Viertel = 90 Grad")
	_ok(absf(c.angle_at(2000.0)) < EPS, "naechster Takt wieder oben")
	_ok(absf(c.speed_at(0.0) - V) < EPS, "Tempo 0,18 Grad/ms")
	_ok(absf(c.bar_start_at(2500.0) - 2000.0) < EPS and absf(c.bar_end_at(2500.0) - 4000.0) < EPS, "Takt-Beginn/-Ende")
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
	print("- 4K-Mania -> Spuren")
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
	_ok(absf(ns[0].angle_deg - 180.0) < EPS and absf(ns[1].angle_deg - 270.0) < EPS, "Phase = Taktposition (1000 ms = 180 Grad)")
	_ok(absf(ns[6].end_angle_deg - ns[6].angle_deg - V * 600.0) < 0.001, "Halte laeuft mit dem Takt")
	var v := OrbitConverter.violations(ns, bm)
	_ok(int(v.timing) + int(v.ring) + int(v.angle) + int(v.chord) == 0, "keine Verstoesse %s" % v)


func _test_std_rings() -> void:
	print("- osu!standard -> Spuren (Taiko-Regel)")
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
	_ok(ns[3].ring == 0 and ns[4].ring == 1 and ns[3].time_ms == ns[4].time_ms, "Finish = beide Spuren")
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
	_ok(times == [1000.0, 1060.0, 1150.0, 3000.0, 3400.0, 4000.0], "Spur-Abstaende %s" % [times])
	var v := OrbitConverter.violations(ns, bm)
	_ok(int(v.ring) == 0, "violations: Spuren ok")
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


# --- Bahnen ---

func _test_paths() -> void:
	print("- Bahnformen (Geometrie)")
	var starts_ok := true
	var closed_ok := true
	var const_ok := true
	var inside_ok := true
	for sh in OrbitPath.COUNT:
		var p0 := OrbitPath.pos(sh, 0.0)
		starts_ok = starts_ok and absf(p0.y) < 0.01 and p0.x < -0.7
		closed_ok = closed_ok and OrbitPath.pos(sh, 0.9999).distance_to(p0) < 0.01
		# Konstante Bahngeschwindigkeit: gleiche Phasenschritte = gleiche Strecke.
		var lo := INF
		var hi := 0.0
		for k in 200:
			var d := OrbitPath.pos(sh, float(k) / 200.0).distance_to(OrbitPath.pos(sh, float(k + 1) / 200.0))
			lo = minf(lo, d)
			hi = maxf(hi, d)
			var q := OrbitPath.pos(sh, float(k) / 200.0)
			inside_ok = inside_ok and absf(q.x) <= 1.001 and absf(q.y) <= 0.93
		const_ok = const_ok and hi < lo * 1.15 + 0.002
		print("    %s: Laenge %.2f" % [OrbitPath.NAMES[sh], OrbitPath.length(sh)])
	_ok(starts_ok, "alle Formen starten links (Takt-Eins)")
	_ok(closed_ok, "alle Bahnen sind geschlossen")
	_ok(const_ok, "konstante Bahngeschwindigkeit (Bogenlaenge)")
	_ok(inside_ok, "Formen liegen im Feld (|x| <= 1, |y| <= 0,93)")
	_ok(OrbitPath.length(OrbitPath.ROSE4) > OrbitPath.length(OrbitPath.CIRCLE) * 1.4, "Rose4 deutlich laenger als Kreis")
	# Spuren: A links der Laufrichtung = beim Kreis innen.
	var a := OrbitPath.lane_pos(OrbitPath.CIRCLE, 0.25, 0)
	var b := OrbitPath.lane_pos(OrbitPath.CIRCLE, 0.25, 1)
	_ok(a.length() < b.length() and absf(a.distance_to(b) - 2.0 * OrbitPath.LANE_OFF) < 0.01, "Spur A innen, Spur B aussen (Abstand %.3f)" % a.distance_to(b))
	# Der Kopf wechselt beim Formwechsel nicht den Ort (gleicher Startpunkt).
	var tr := OrbitTrack.fixed(OrbitClock.fixed(2000.0), OrbitPath.ELLIPSE)
	tr.plan.append([4000.0, OrbitPath.EIGHT])
	_ok(tr.head(3999.9).distance_to(tr.head(4000.0)) < 0.05, "Formwechsel springt nicht")
	_ok(tr.shape_at(3999.0) == OrbitPath.ELLIPSE and tr.shape_at(4000.0) == OrbitPath.EIGHT, "Form gilt ab Takt-Eins")
	_ok(tr.changes_next(2500.0) and tr.next_shape_at(2500.0) == OrbitPath.EIGHT and not tr.changes_next(500.0), "Vorschau: naechster Takt hat andere Form")


func _dense_bm(bpm: float, nps_by_bar: Array) -> Beatmap:
	# Mania-Map: je Takt nps Noten gleichmaessig, Spalten wechselnd.
	var bm := _bm()
	bm.timing_points.clear()
	_tp(bm, 0.0, bpm)
	var bar := 60000.0 / bpm * 4.0
	var col := 0
	for k in nps_by_bar.size():
		var n := int(round(float(nps_by_bar[k]) * bar / 1000.0))
		for j in n:
			_add(bm, float(k) * bar + 100.0 + float(j) * (bar - 200.0) / float(maxi(n, 1)), col % 4)
			col += 1
	return bm


func _test_shape_plan() -> void:
	print("- Bahnform-Plan (Konverter)")
	var levels: Array = []
	for k in 8:
		levels.append(1.0)
	for k in 12:
		levels.append(9.0)
	for k in 8:
		levels.append(1.0)
	var bm := _dense_bm(120.0, levels)
	var ns := OrbitConverter.convert(bm)
	var tr := OrbitConverter.track_for(bm, ns)
	var calm := tr.shape_at(2000.0 * 3.5)
	var busy := tr.shape_at(2000.0 * 14.5)
	_ok(calm == OrbitPath.CIRCLE or calm == OrbitPath.ELLIPSE, "ruhiger Teil: Kreis/Ellipse (%s)" % OrbitPath.NAMES[calm])
	_ok(busy >= OrbitPath.EIGHT, "dichter Teil: Acht/Rose (%s)" % OrbitPath.NAMES[busy])
	_ok(tr.shape_at(2000.0 * 27.5) <= OrbitPath.ELLIPSE, "danach wieder ruhig")
	# Wechsel nur auf Takt-Eins.
	var on_bar := true
	for e in tr.plan:
		if float(e[0]) > -1.0e9:
			on_bar = on_bar and absf(fposmod(float(e[0]), 2000.0)) < 0.01
	_ok(on_bar and tr.plan.size() >= 3, "Formwechsel nur auf Takt-Eins (%d Eintraege)" % tr.plan.size())
	# Mindesthaltedauer.
	var hold_ok := true
	for k in range(2, tr.plan.size()):
		hold_ok = hold_ok and float(tr.plan[k][0]) - float(tr.plan[k - 1][0]) >= 2000.0 * OrbitConverter.SHAPE_MIN_HOLD - 0.01
	_ok(hold_ok, "Form haelt mindestens %d Takte" % OrbitConverter.SHAPE_MIN_HOLD)
	# Kopfgeschwindigkeit nie ueber dem Deckel.
	var sp_ok := true
	for n in ns:
		sp_ok = sp_ok and n.speed <= OrbitTrack.MAX_SPEED + 1e-7
	_ok(sp_ok, "Kopf nie schneller als %.4f/ms" % OrbitTrack.MAX_SPEED)
	# Schneller Takt (1,2 s): lange Formen werden durch einfachere ersetzt.
	var fast := _dense_bm(200.0, [10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0])
	var fns := OrbitConverter.convert(fast)
	var ftr := OrbitConverter.track_for(fast, fns)
	var fast_ok := not fns.is_empty()
	for n in fns:
		fast_ok = fast_ok and OrbitPath.length(n.shape) / ftr.clock.bar_ms_at(n.time_ms) <= OrbitTrack.MAX_SPEED + 1e-7
	_ok(fast_ok, "schneller Takt: Deckel haelt")
	# Leichte Maps bleiben ruhig (nur Kreis/Ellipse).
	var easy := _bm()
	for i in 20:
		_add(easy, 1000.0 + 700.0 * i, i % 4)
	var en := OrbitConverter.convert(easy)
	var calm_only := true
	for n in en:
		calm_only = calm_only and n.shape <= OrbitPath.ELLIPSE
	_ok(calm_only, "leichte Map: Kreis/Ellipse")
	# Deterministisch.
	var tr2 := OrbitConverter.track_for(bm, ns)
	_ok(str(tr.plan) == str(tr2.plan), "Plan ist deterministisch")


# --- Core ---

func _test_tap_aim() -> void:
	print("- Zielen auf den Kopf ist Pflicht")
	var ns := _list([_note(1000.0, 0), _note(2000.0, 0), _note(3000.0, 0), _note(4000.0, 0)])
	var c := _core(ns)
	var got := _res(c)
	# 1: Cursor genau auf dem Kopf zur Druckzeit (Kopf ist 10 ms weiter als die Note).
	c.key_down(0, 1010.0, _head(1010.0))
	c.update(1011.0)
	_ok(int(got[0].quality) <= 1 and float(got[0].angle_err) < 0.01, "auf dem Kopf: Treffer, Fehler 0")
	# 2: Cursor steht auf der NOTE (Ort der Note), Druck 60 ms zu spaet -> Kopf ist weiter
	c.key_down(0, 2060.0, _head(2000.0))
	c.update(2061.0)
	var want := _head(2000.0).distance_to(_head(2060.0)) * 100.0
	_ok(got.has(1) and absf(float(got[1].angle_err) - want) < 0.5, "Zielfehler = Abstand zum KOPF (%.1f)" % float(got[1].angle_err))
	# 3: Cursor 60 Punkte neben dem Kopf: kein Treffer, Ziel laeuft ab
	var missed := []
	c.press_missed.connect(func(_p, _ring, why): missed.append(why))
	c.key_down(0, 3000.0, _head(3000.0) + Vector2(0.6, 0.0))
	_ok(missed == ["AIM"], "daneben: Grund AIM")
	c.update(3200.0)
	_ok(int(got[2].quality) == OrbitCore.Quality.MISS, "kein Treffer neben dem Kopf -> MISS")
	# 4: Toleranzrand
	c.key_down(0, 4000.0, _head(4000.0) + Vector2(OrbitCore.AIM_TOL - 1.0, 0.0) / 100.0)
	_ok(got.has(3) and int(got[3].quality) <= 4, "am Rand der Toleranz noch Treffer")
	var t_edge := OrbitCore.hit_value(0, OrbitCore.AIM_TOL - 0.5)
	_ok(t_edge < 0.9 and t_edge > 0.87, "Rand: Zielfaktor ~0,88")
	_ok(OrbitCore.hit_value(0, OrbitCore.AIM_CENTER) == 1.0 and OrbitCore.hit_value(0, 0.0) == 1.0, "bis zur Mitte Faktor 1,0")


func _test_keys_are_rings() -> void:
	print("- Taste = Spur")
	var ns := _list([_note(1000.0, 1), _note(2000.0, 0)])
	var c := _core(ns)
	var got := _res(c)
	var missed := []
	c.press_missed.connect(func(_p, _ring, why): missed.append(why))
	c.key_down(0, 1000.0, _head(1000.0))
	_ok(not got.has(0) and missed == ["RING"], "Taste A trifft kein Ziel auf Spur B (Grund RING)")
	c.key_up(0, 1030.0)
	c.key_down(1, 1000.0, _head(1000.0))
	_ok(got.has(0) and int(got[0].ring) == 1, "Taste B trifft Spur B")
	c.key_down(0, 2000.0, _head(2000.0))
	_ok(got.has(1) and int(got[1].quality) <= 1, "Taste A trifft Spur A")


func _test_accent() -> void:
	print("- Akzent: beide Spuren")
	var ns := _list([_note(1000.0, 0), _note(1000.0, 1)])
	var c := _core(ns)
	var got := _res(c)
	var a := _head(1000.0)
	c.key_down(0, 1000.0, a)
	c.key_down(1, 1002.0, a)
	_ok(got.has(0) and got.has(1), "beide Tasten treffen beide Ziele")
	var c2 := _core(_list([_note(1000.0, 0), _note(1000.0, 1)]))
	var g2 := _res(c2)
	c2.key_down(1, 1000.0, a)
	c2.update(1100.0)
	_ok(g2.has(1) and not g2.has(0) or int(g2[0].quality) == 5, "nur eine Taste = nur ein Treffer")


func _test_hold() -> void:
	print("- Halte folgt dem Kopf")
	var ns := _list([_note(1000.0, 1, 1000.0)])
	var c := _core(ns)
	var got := _res(c)
	c.key_down(1, 1000.0, _head(1000.0))
	var t := 1000.0
	while t < 2000.0:
		t += 8.0
		c.cursor_moved(_head(t) + Vector2(0.04, 0.0), t)
		c.update(t)
	c.key_up(1, 2000.0)
	c.update(2100.0)
	_ok(got.has(0) and bool(got[0].get("held", false)) and int(got[0].quality) <= 1, "Halte gehalten bis zum Ende: Treffer")


func _test_hold_release_and_out() -> void:
	print("- Halte: loslassen / neben dem Kopf")
	var ns := _list([_note(1000.0, 0, 1000.0)])
	var c := _core(ns)
	var got := _res(c)
	c.key_down(0, 1000.0, _head(1000.0))
	var tt := 1000.0
	while tt < 1400.0:
		tt += 8.0
		c.cursor_moved(_head(tt), tt)
		c.update(tt)
	c.key_up(0, 1400.0)
	_ok(got.has(0) and str(got[0].get("drop_reason", "")) == "RELEASE" and int(got[0].quality) == 5, "zu frueh loslassen = DROP/RELEASE")
	# Cursor bleibt stehen, der Kopf laeuft davon.
	var c2 := _core(_list([_note(1000.0, 0, 1000.0)]))
	var g2 := _res(c2)
	c2.key_down(0, 1000.0, _head(1000.0))
	var t := 1000.0
	while t < 2000.0 and not g2.has(0):
		t += 8.0
		c2.update(t)
	_ok(g2.has(0) and str(g2[0].get("drop_reason", "")) == "OUT", "Cursor steht, Kopf laeuft weg = DROP/OUT")
	var dt: float = t - 1000.0
	var exp_dt: float = OrbitCore.AIM_TOL / 100.0 / ns[0].speed + OrbitCore.ARC_OUT_MS
	_ok(absf(dt - exp_dt) < 60.0, "Austritt nach Toleranz/Tempo + ARC_OUT_MS (%.0f ms, erwartet %.0f)" % [dt, exp_dt])
	# Andere Taste halten genuegt nicht: Taste der Spur loslassen beendet.
	var c3 := _core(_list([_note(1000.0, 0, 1000.0)]))
	var g3 := _res(c3)
	c3.key_down(0, 1000.0, _head(1000.0))
	c3.key_down(1, 1100.0, _head(1100.0))
	c3.key_up(0, 1300.0)
	_ok(g3.has(0) and int(g3[0].quality) == 5, "Loslassen der Spur-Taste beendet die Halte")


func _test_scoring_values() -> void:
	print("- Wertung unveraendert")
	_ok(Array(OrbitCore.TIER_VALUE) == [1.0, 0.94, 0.68, 0.40, 0.16, 0.0], "Stufenwerte")
	_ok(Array(OrbitCore.TIER_NAMES) == ["CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS"], "Stufennamen")
	_ok(OrbitCore.AIM_TOL == 40.0 and OrbitCore.AIM_CENTER == 12.0 and OrbitCore.AIM_EDGE_FACTOR == 0.88, "Toleranz 40, Mitte 12, Rand 0,88")
	var ns: Array[OrbitNote] = []
	for i in 150:
		ns.append(_note(1000.0 + i * 400.0, i % 2))
	var c := _core(ns)
	for n in ns:
		c.key_down(n.ring, n.time_ms, _head(n.time_ms))
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
	_ok(s2 < s3, "Spurwechsel = mehr Sterne (%.2f < %.2f)" % [s2, s3])
	var fast: Array[OrbitNote] = []
	for n in dense:
		var m := OrbitNote.make(n.time_ms, n.angle_deg, 0)
		m.speed = n.speed * 2.0
		fast.append(m)
	_ok(OrbitConverter.stars(fast) > s2, "schnellerer Kopf = mehr Sterne")
	# Kurvige Form = mehr Folge-Anspruch bei gleichem Tempo.
	var curvy: Array[OrbitNote] = []
	var flat: Array[OrbitNote] = []
	for n in dense:
		var m := OrbitNote.make(n.time_ms, n.angle_deg, 0)
		m.speed = n.speed * 1.5
		m.shape = OrbitPath.ROSE3
		curvy.append(m)
		var f := OrbitNote.make(n.time_ms, n.angle_deg, 0)
		f.speed = n.speed * 1.5
		flat.append(f)
	_ok(OrbitConverter.stars(curvy) > OrbitConverter.stars(flat), "kurvigere Bahn = mehr Sterne")
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
	var shape_n := [0, 0, 0, 0, 0]
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
			var tr := OrbitConverter.track_for(bm, ns)
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
				shape_n[clampi(n.shape, 0, OrbitPath.COUNT - 1)] += 1
			diffs += 1
			if diffs % 40 == 1 and not ns.is_empty():
				var c := _core(ns, bm.od())
				c.set_track(tr)
				for n in ns:
					c.key_down(n.ring, n.time_ms, tr.head(n.time_ms))
					c.key_up(n.ring, n.end_ms + 20.0)
					if n.is_arc:
						pass
				c.update(ns[-1].end_ms + 500.0)
				perfect_miss += c.n_miss if not ns.any(func(n): return n.is_arc) else 0
	print("  %d Diffs, %d Ziele; Verstoesse: Zeit %d, Ring %d, Winkel %d, Akkord %d; Sterne %.2f..%.2f; max Kopftempo %.4f/ms; Formen %s" % [
		diffs, tot.targets, tot.timing, tot.ring, tot.angle, tot.chord, star_min, star_max, max_speed, shape_n])
	star_all.sort()
	if not star_all.is_empty():
		var q := func(f: float) -> float: return star_all[int(f * (star_all.size() - 1))]
		print("  Sterne-Verteilung: p10 %.2f p25 %.2f Median %.2f p75 %.2f p90 %.2f p99 %.2f" % [q.call(0.1), q.call(0.25), q.call(0.5), q.call(0.75), q.call(0.9), q.call(0.99)])
	_ok(diffs > 0 or da.get_files().is_empty(), "Bibliothek gelesen")
	_ok(int(tot.timing) == 0, "Zeiten = Original")
	_ok(int(tot.ring) == 0, "Ein Finger pro Spur")
	_ok(int(tot.angle) == 0, "Phase = Taktposition")
	_ok(int(tot.chord) == 0, "Akzente am selben Winkel")
	_ok(star_max <= OrbitConverter.STAR_MAX, "Sterne <= 15")
	_ok(max_speed <= OrbitTrack.MAX_SPEED + 1e-7, "Kopf nie schneller als %.4f/ms" % OrbitTrack.MAX_SPEED)
	_ok(perfect_miss == 0, "perfekter Spieler ohne Miss (Stichprobe)")
