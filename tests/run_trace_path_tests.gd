extends SceneTree

## Headless-Tests fuer TracePath (Lesbarkeit): keine ueberdeckten Pfeile auch bei Streams,
## Quadratschleifen, Haarnadel-Ketten und Akkord-Folgen; Ausweichen nur bei Bedarf (leichte
## Kurve), deterministisch, Notenzeiten (s je Knoten) bleiben exakt.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_path_tests.gd

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	print("Trace-Path-Tests: %d ok, %d fehlgeschlagen" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


## notes: [t, col] oder [t, col, end]; ein Eintrag mit col als Array = Akkord (je Spalte eine Note).
func _path(notes: Array, speed: float = 520.0) -> TracePath:
	var times := PackedFloat64Array()
	var cols := PackedInt32Array()
	var ends := PackedFloat64Array()
	for n in notes:
		var cs: Array = n[1] if n[1] is Array else [n[1]]
		for c in cs:
			times.append(float(n[0]))
			cols.append(int(c))
			ends.append(float(n[2]) if n.size() > 2 else float(n[0]))
	return TracePath.build(times, cols, ends, speed)


func _stream(cols: Array, gap: float, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append([1000.0 + gap * float(i), cols[i % cols.size()]])
	return out


func _overlaps(p: TracePath) -> int:
	return p.overlap_pairs().size()


func _run() -> void:
	_test_patterns()
	_test_random()
	_test_exact_times()
	_test_minimal_change()
	_test_determinism()
	_test_camera()


func _test_patterns() -> void:
	# Quadratschleife links-runter-rechts-hoch: ohne Ausweichen laege jeder 5. Pfeil auf dem 1.
	_ok(_overlaps(_path(_stream([0, 1, 3, 2], 125.0, 80))) == 0, "Quadratschleife 16tel (L D R U)")
	_ok(_overlaps(_path(_stream([0, 2, 3, 1], 100.0, 80))) == 0, "Quadratschleife gegenlaeufig, 100 ms")
	_ok(_overlaps(_path(_stream([0, 3], 80.0, 120))) == 0, "Haarnadel-Kette L R, 80 ms")
	_ok(_overlaps(_path(_stream([1, 2], 80.0, 120))) == 0, "Haarnadel-Kette D U, 80 ms")
	_ok(_overlaps(_path(_stream([0, 1, 2, 3, 3, 2, 1, 0], 90.0, 160))) == 0, "Treppe rauf/runter")
	var ch: Array = []
	for i in 60:
		ch.append([1000.0 + 120.0 * float(i), [[0, 3], [1, 2], [0, 1], [2, 3], [0, 1, 2]][i % 5]])
	_ok(_overlaps(_path(ch)) == 0, "Akkord-Folge (Kreuz, Diagonale, Stern)")
	_ok(_overlaps(_path(_stream([0], 60.0, 100))) == 0, "gerader Stream gleicher Spalte")
	# Spiral-Falle: immer gleiche Drehrichtung (L U R D) bei dichtem Tempo.
	_ok(_overlaps(_path(_stream([0, 2, 3, 1], 70.0, 120), 900.0)) == 0, "Spirale bei hohem Fadentempo")
	# Mindestknotenabstand: Streams behalten ihren Mindestabstand auf dem Faden.
	var p := _path(_stream([0, 1, 3, 2], 60.0, 40))
	var ok := true
	for j in range(1, p.knots.size()):
		ok = ok and p.knots[j].s - p.knots[j - 1].s >= TracePath.MIN_SEG - 0.001
	_ok(ok, "Mindest-Segmentlaenge auf dem Faden")


func _test_random() -> void:
	var rng := RandomNumberGenerator.new()
	for seed in [1, 2, 3, 4, 5, 6]:
		rng.seed = seed
		var notes: Array = []
		var t := 500.0
		for i in 700:
			t += float(rng.randi_range(45, 260))
			var r := rng.randf()
			if r < 0.6:
				notes.append([t, rng.randi_range(0, 3)])
			elif r < 0.85:
				var a := rng.randi_range(0, 3)
				notes.append([t, [a, (a + rng.randi_range(1, 3)) % 4]])
			else:
				notes.append([t, [0, 1, 2, 3].slice(0, rng.randi_range(3, 4))])
		var p := _path(notes)
		_ok(_overlaps(p) == 0, "Zufallsmap %d ohne ueberdeckte Pfeile" % seed)


func _test_exact_times() -> void:
	var notes := _stream([0, 3, 1, 2, 2, 0], 85.0, 90)
	notes.append([200.0, 1, 700.0])
	var p := _path(notes)
	var ok := true
	var exp_s := 0.0
	for j in p.knots.size():
		if j > 0:
			exp_s += maxf(520.0 * (p.knots[j].t - p.knots[j - 1].t) / 1000.0, TracePath.MIN_SEG)
		ok = ok and absf(p.knots[j].s - exp_s) < 0.001 and absf(p.s_at(p.knots[j].t) - exp_s) < 0.001
	_ok(ok, "Knoten-s bleibt Summe aus Zeit*Tempo / Mindestlaenge (Ausweichen aendert s nie)")
	var kh: TracePath.Knot = p.knots[0]
	_ok(kh.holds.size() == 1 and absf(float(kh.holds[0]["t_end"]) - 700.0) < 0.001, "Hold-Ende bleibt exakt")
	# Position der Knoten = Faden bei s (Stuecke schliessen lueckenlos an).
	var gap := 0.0
	for j in p.knots.size():
		gap = maxf(gap, p.knots[j].pos.distance_to(p.pos_at(p.knots[j].s)))
	_ok(gap < 0.001, "Knotenposition liegt auf dem Faden")
	var cont := 0.0
	var s := p.knots[0].s - 50.0
	var prev := p.pos_at(s)
	while s < p.knots[p.knots.size() - 1].s + 50.0:
		s += 1.0
		var q := p.pos_at(s)
		cont = maxf(cont, q.distance_to(prev))
		prev = q
	_ok(cont < 1.001, "Faden ohne Sprung (Schritt 1 px = hoechstens 1 px)")


func _test_minimal_change() -> void:
	# Langsame Noten (viel Platz): keine Zusatzkurve, Drehung = Richtungsunterschied.
	var p := _path([[1000.0, 0], [2000.0, 1], [3000.0, 3], [4000.0, 2], [5000.0, 0]])
	_ok(absf(p.knots[1].turn - wrapf(TracePath.angle_of_col(1) - TracePath.angle_of_col(0), -PI, PI)) < 0.0001,
		"freie Bahn: Drehung = Richtungswechsel")
	var q := _path([[1000.0, 3], [2000.0, 3], [3000.0, 3]])
	_ok(q.knots[1].is_straight() and q.knots[2].is_straight(), "gleiche Richtung bleibt gerade")
	var h := _path([[1000.0, 0], [2000.0, 3]])
	_ok(h.knots[1].hairpin and absf(absf(h.knots[1].turn) - PI) < 0.0001, "freie Haarnadel bleibt Halbkreis")
	# Ausweichen ist leicht: jede Zusatzkurve hoechstens EVADE-Maximum.
	var dense := _path(_stream([0, 1, 3, 2], 125.0, 60))
	var lim := 0.0
	for e in TracePath.EVADE:
		lim = maxf(lim, absf(float(e)))
	var ok := true
	for j in range(1, dense.knots.size()):
		var kn: TracePath.Knot = dense.knots[j]
		ok = ok and absf(kn.turn) <= PI + lim + 0.001
	_ok(ok, "Zusatzkurven begrenzt")


func _test_determinism() -> void:
	var a := _path(_stream([0, 1, 3, 2, 0, 3], 95.0, 150))
	var b := _path(_stream([0, 1, 3, 2, 0, 3], 95.0, 150))
	var same := a.knots.size() == b.knots.size()
	for j in mini(a.knots.size(), b.knots.size()):
		same = same and a.knots[j].pos == b.knots[j].pos and a.knots[j].turn == b.knots[j].turn
	_ok(same, "Aufbau deterministisch")
	_ok(a.bounds() == b.bounds(), "Grenzen deterministisch")


func _test_camera() -> void:
	var p := _path(_stream([0, 1, 3, 2], 110.0, 120))
	var worst := 0.0
	var t := 1000.0
	while t < 1000.0 + 110.0 * 119.0:
		worst = maxf(worst, p.camera(t + 16.7).distance_to(p.camera(t)))
		t += 25.0
	_ok(worst < 40.0, "Kamera ohne Sprung im Stream (%.1f px/Bild)" % worst)
