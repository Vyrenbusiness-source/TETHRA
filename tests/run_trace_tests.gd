extends SceneTree

## Headless-Tests fuer Trace: Fadengeometrie (Knicke, Knoten, Haarnadel, Diagonale,
## Kreuz-/Sternknoten, Holds, Mindestabstand), Bogenlaenge = Zeit * Tempo, Determinismus,
## Kamera stetig, Wertung = ManiaCore (Bot = SS), Replay deterministisch, View-Zustand.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_tests.gd

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	print("Trace-Tests: %d ok, %d fehlgeschlagen" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _near(a: float, b: float, label: String, eps: float = 0.01) -> void:
	_ok(absf(a - b) <= eps, "%s (erwartet %f, war %f)" % [label, b, a])


## notes: [t, col] oder [t, col, end].
func _path(notes: Array, speed: float = 520.0) -> TracePath:
	var times := PackedFloat64Array()
	var cols := PackedInt32Array()
	var ends := PackedFloat64Array()
	for n in notes:
		times.append(float(n[0]))
		cols.append(int(n[1]))
		ends.append(float(n[2]) if n.size() > 2 else float(n[0]))
	return TracePath.build(times, cols, ends, speed)


func _beatmap(objects: String) -> Beatmap:
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Metadata]\nTitle:T\nArtist:A\nVersion:V\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n%s" % objects
	var res := OsuParser.parse(txt)
	assert(res.ok)
	return res.beatmap


func _obj(t: int, col: int, end: int = 0) -> String:
	var x := col * 128 + 64
	if end > 0:
		return "%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, t, end]
	return "%d,192,%d,1,0,0:0:0:0:\n" % [x, t]


func _run() -> void:
	_test_straight()
	_test_turns()
	_test_hairpin()
	_test_chords()
	_test_arclength()
	_test_min_seg()
	_test_hold()
	_test_determinism_camera()
	_test_scoring_bot()
	_test_replay()
	_test_view_state()


func _test_straight() -> void:
	# Jack in Spalte 3 (rechts): Knoten auf gerader Strecke, Abstand = Tempo * Zeit.
	var p := _path([[1000, 3], [1500, 3], [2000, 3]])
	_ok(p.knots.size() == 3, "3 Knoten")
	for k in p.knots:
		_ok(k.is_straight() and not k.hairpin, "Jack = gerader Knoten")
	_near(p.knots[1].s - p.knots[0].s, 260.0, "Abstand 0,5 s bei 520 px/s", 0.001)
	var d := p.knots[2].pos - p.knots[0].pos
	_near(d.x, 520.0, "Strecke nach rechts", 0.01)
	_near(d.y, 0.0, "keine Abweichung", 0.01)
	# Jede Spalte hat ihre absolute Richtung.
	var expect := [Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 0)]
	for c in 4:
		var q := _path([[1000, c], [1500, c]])
		var dir := (q.knots[1].pos - q.knots[0].pos).normalized()
		_ok(dir.distance_to(expect[c]) < 0.001, "Spalte %d Richtung" % c)


func _test_turns() -> void:
	# rechts, dann runter: Knick 90 Grad (im Uhrzeigersinn auf dem Schirm, y nach unten).
	var p := _path([[1000, 3], [1600, 1], [2200, 1]])
	_ok(not p.knots[1].is_straight(), "Knick am Knoten 1")
	_near(absf(p.knots[1].turn), PI * 0.5, "90 Grad", 0.001)
	_ok(not p.knots[1].hairpin, "kein Haarnadel")
	var after := p.knots[2].pos - p.pos_at(p.knots[1].s + p.knots[1].win)
	_ok(absf(after.x) < 0.01 and after.y > 200.0, "danach nach unten")
	_near(p.angle_at(p.knots[2].s), PI * 0.5, "Richtung unten", 0.001)


func _test_hairpin() -> void:
	# links -> rechts -> links: Haarnadeln, Seite wechselt, nie auf sich selbst zurueck.
	var p := _path([[1000, 0], [1600, 3], [2200, 0], [2800, 3], [3400, 3]])
	_ok(p.knots[1].hairpin and p.knots[2].hairpin and p.knots[3].hairpin, "Gegenrichtung = Haarnadel")
	_near(absf(p.knots[1].turn), PI, "Halbkreis", 0.0001)
	_ok(p.knots[1].turn * p.knots[2].turn < 0.0, "Seite wechselt")
	_ok(p.hairpin_count() == 3, "3 Haarnadeln")
	# Der Rueckweg liegt seitlich versetzt (nicht auf dem Hinweg).
	var a := p.pos_at(p.knots[1].s - 130.0)
	var b := p.pos_at(p.knots[1].s + 130.0)
	_ok(absf(a.y - b.y) > 15.0, "Haarnadel seitlich versetzt")
	var c := p.pos_at(p.knots[1].s + 55.0)
	_ok(c.y != a.y, "Bogen verlaesst die Gerade")


func _test_chords() -> void:
	# Links + hoch = Diagonale nach links oben.
	var p := _path([[1000, 3], [1600, 0], [1600, 2], [2200, 3]])
	_ok(p.knots.size() == 3, "Akkord = ein Knoten")
	var k: TracePath.Knot = p.knots[1]
	_ok(k.kind == TracePath.Kind.DIAG and k.notes.size() == 2, "Diagonale")
	var want := atan2(-1.0, -1.0)
	_near(wrapf(k.angle - want, -PI, PI), 0.0, "Richtung links oben", 0.001)
	# Gegenpaar links+rechts: Kreuzknoten, Richtung bleibt.
	var q := _path([[1000, 1], [1600, 0], [1600, 3], [2200, 1]])
	var kc: TracePath.Knot = q.knots[1]
	_ok(kc.kind == TracePath.Kind.CROSS and kc.is_straight(), "Kreuzknoten, Richtung bleibt")
	var qp := _path([[1000, 1], [1600, 1], [1600, 2]])
	_ok(qp.knots[1].kind == TracePath.Kind.CROSS or qp.knots[1].kind == TracePath.Kind.DIAG, "runter+hoch ist Gegenpaar")
	_ok(qp.knots[1].kind == TracePath.Kind.CROSS, "runter+hoch = Kreuz")
	# 3 und 4 Noten: Stern, Richtung bleibt.
	var r := _path([[1000, 2], [1600, 0], [1600, 1], [1600, 3], [2200, 2], [2200, 0], [2200, 1], [2200, 3]])
	_ok(r.knots[1].kind == TracePath.Kind.STAR and r.knots[1].is_straight(), "Stern (3)")
	_ok(r.knots[2].kind == TracePath.Kind.STAR and r.knots[2].is_straight(), "Stern (4)")
	_ok(r.count_kind(TracePath.Kind.STAR) == 2, "zaehlt Sterne")
	# Notenindizes bleiben erhalten (beliebige Eingabereihenfolge).
	var s := _path([[1600, 2], [1000, 1], [1600, 0]])
	_ok(s.note_knot[0] == 1 and s.note_knot[2] == 1 and s.note_knot[1] == 0, "note_knot nach Zeit")


func _test_arclength() -> void:
	# Bogenlaenge der Kurve = Zeit * Tempo (innerhalb der Abtastung), auch ueber Knicke.
	var p := _path([[1000, 3], [1500, 1], [2100, 0], [2600, 3], [3200, 2], [3700, 2], [4300, 0], [4900, 1]])
	var s0: float = p.knots[0].s - 100.0
	var s1: float = p.knots[p.knots.size() - 1].s + 100.0
	var pts := p.sample(s0, s1, 1.0)
	var len := 0.0
	for i in range(1, pts.size()):
		len += pts[i].distance_to(pts[i - 1])
	_near(len, s1 - s0, "Polylinie = Bogenlaenge", (s1 - s0) * 0.002)
	_ok(p.s_at(1500.0) - p.s_at(1000.0) > 0.0, "s waechst")
	_near(p.s_at(1500.0) - p.s_at(1000.0), 260.0, "s(t) ohne Mindestabstand", 0.001)
	# Position stetig (kein Sprung am Knick).
	var worst := 0.0
	for i in range(1, pts.size()):
		worst = maxf(worst, pts[i].distance_to(pts[i - 1]))
	_ok(worst <= 1.0 + 0.001, "keine Spruenge (max Schritt %f)" % worst)
	# Kopf bewegt sich mit konstanter Geschwindigkeit auf freier Strecke.
	var h0 := p.head_pos(1100.0)
	var h1 := p.head_pos(1200.0)
	_near(h0.distance_to(h1), 52.0, "Kopf 100 ms = 52 px", 0.5)
	# Tempo-Einstellung skaliert die Strecke.
	var f := _path([[1000, 3], [1500, 3]], 1040.0)
	_near(f.knots[1].s - f.knots[0].s, 520.0, "doppeltes Tempo", 0.001)


func _test_min_seg() -> void:
	# Stream (50 ms): optisch auseinandergezogen, Pfeile ueberdecken sich nie.
	var notes := []
	for i in 12:
		notes.append([1000 + i * 50, i % 4])
	var p := _path(notes)
	for j in range(1, p.knots.size()):
		_ok(p.knots[j].s - p.knots[j - 1].s >= TracePath.MIN_SEG - 0.001, "Mindestabstand %d" % j)
	for j in range(1, p.knots.size()):
		_ok(p.knots[j].pos.distance_to(p.knots[j - 1].pos) >= TracePath.MIN_SEG * 0.55,
				"Knoten %d liegen auseinander" % j)
	# Zeit bleibt monoton abgebildet.
	var last := -INF
	for t in range(900, 1800, 20):
		var s := p.s_at(float(t))
		_ok(s >= last, "s(t) monoton")
		last = s


func _test_hold() -> void:
	var p := _path([[1000, 3], [1500, 1, 2300], [2000, 0], [2600, 0]])
	var k: TracePath.Knot = p.knots[1]
	_ok(k.holds.size() == 1, "Hold am Knoten")
	var h: Dictionary = k.holds[0]
	_near(float(h.s_end), p.s_at(2300.0), "Hold-Ende = s(Ende)", 0.0001)
	_ok(float(h.s_end) > k.s + 100.0, "Hold hat Laenge")
	_ok(int(h.col) == 1 and int(h.note) == 1, "Hold-Spalte und Note")
	_ok(p.knots[0].holds.is_empty(), "Tap ohne Hold")


func _test_determinism_camera() -> void:
	var notes := []
	for i in 80:
		notes.append([1000 + i * 240, (i * 7 + i / 3) % 4])
	var a := _path(notes)
	var b := _path(notes)
	var same := true
	for j in a.knots.size():
		same = same and a.knots[j].pos == b.knots[j].pos and a.knots[j].angle == b.knots[j].angle
	_ok(same, "deterministisch")
	_ok(a.camera(5000.0) == b.camera(5000.0), "Kamera deterministisch")
	# Kamera stetig und nie schneller als ~2x Fadentempo.
	var prev := a.camera(500.0)
	var worst := 0.0
	for t in range(516, 21000, 16):
		var c := a.camera(float(t))
		worst = maxf(worst, c.distance_to(prev))
		prev = c
	_ok(worst < 520.0 * 0.016 * 3.0 * 1.2, "Kamera stetig (max %f px/Frame)" % worst)
	# Kopf nie weit von der Kamera (im Bild).
	var far := 0.0
	for t in range(1000, 20000, 50):
		far = maxf(far, a.camera(float(t)).distance_to(a.head_pos(float(t))))
	_ok(far < 330.0, "Kopf bleibt nahe der Bildmitte (max %f)" % far)
	var bb := a.bounds()
	_ok(bb.size.x > 10.0 or bb.size.y > 10.0, "Bounds fuer den End-Zoom")
	_ok(bb.has_point(a.head_pos(5000.0)), "Kopf liegt im Gesamtbild")


func _bot_events(bm: Beatmap) -> Array:
	var ev := []
	for o in bm.hit_objects:
		var n := o as ManiaNote
		ev.append({"t": float(n.time), "lane": n.column, "down": true})
		ev.append({"t": float(n.end_time()) if n.is_hold else float(n.time) + 40.0,
				"lane": n.column, "down": false})
	# Stabil nach Zeit, Druecke vor Loslassen.
	ev.sort_custom(func(a, b) -> bool:
		if a.t != b.t:
			return a.t < b.t
		return bool(a.down) and not bool(b.down))
	return ev


func _play(bm: Beatmap, events: Array) -> Dictionary:
	var core := ManiaCore.new()
	core.setup(bm, -1.0, 1.0)
	var idx := 0
	var t := -500.0
	var end := float(bm.hit_objects.back().end_time()) + 1000.0
	while t < end:
		while idx < events.size() and float(events[idx].t) <= t:
			var e: Dictionary = events[idx]
			idx += 1
			if bool(e.down):
				core.key_down(int(e.lane), float(e.t))
			else:
				core.key_up(int(e.lane), float(e.t))
		core.update(t)
		t += 8.0
	return core.stats()


func _test_scoring_bot() -> void:
	var objs := ""
	for i in 40:
		objs += _obj(1000 + i * 300, i % 4)
	objs += _obj(14000, 1, 15000)
	objs += _obj(14000, 2)
	objs += _obj(16000, 0) + _obj(16000, 3)
	var bm := _beatmap(objs)
	_ok(bm.is_mania() and bm.column_count() == 4, "4K-Beatmap")
	var s := _play(bm, _bot_events(bm))
	_ok(int(s.n_miss) == 0, "Bot: keine Misses")
	_ok(str(s.grade) == "SS", "Bot = SS (%s)" % str(s.grade))
	_near(float(s.accuracy), 1.0, "Bot: Genauigkeit 100 %", 0.0001)
	_ok(int(s.score) >= 999000, "Bot: Score ~1 Mio (%d)" % int(s.score))
	_ok(int(s.max_combo) == bm.hit_objects.size(), "Bot: volle Kombo")
	# Geometrie aus demselben Beatmap: ein Knoten je Zeit.
	var p := TracePath.from_beatmap(bm, 520.0)
	_ok(p.note_knot.size() == bm.hit_objects.size(), "from_beatmap: Note-Zuordnung")
	_ok(p.knots.size() == 40 + 1 + 1, "from_beatmap: Akkorde zusammengefasst (%d)" % p.knots.size())
	_ok(p.knots[40].holds.size() == 1, "from_beatmap: Hold erkannt")
	# Ohne Eingabe: alles Miss.
	var none := _play(bm, [])
	_ok(int(none.n_miss) == bm.hit_objects.size() and int(none.score) == 0, "ohne Eingabe: nur Misses")


func _test_replay() -> void:
	var objs := ""
	for i in 30:
		objs += _obj(1000 + i * 280, (i * 3) % 4)
	objs += _obj(10000, 2, 10800)
	var bm := _beatmap(objs)
	var ev := _bot_events(bm)
	# Etwas ungenau spielen (deterministisch): feste Versaetze, ein Auslasser.
	var noisy := []
	for i in ev.size():
		var e: Dictionary = (ev[i] as Dictionary).duplicate()
		if i == 10 or i == 11:
			continue
		e.t = float(e.t) + float((i * 7) % 31 - 15)
		noisy.append(e)
	noisy.sort_custom(func(a, b) -> bool: return a.t < b.t)
	var a := _play(bm, noisy)
	var b := _play(bm, noisy.duplicate(true))
	_ok(int(a.score) == int(b.score) and int(a.n_miss) == int(b.n_miss) and int(a.n300) == int(b.n300),
			"Replay: gleiche Wertung")
	_ok(int(a.n_miss) >= 1 and int(a.score) < 1000000, "Lauf mit Fehlern nicht SS")
	# Replay ueber JSON hin und zurueck (wie ReplayStore).
	var json = JSON.parse_string(JSON.stringify({"events": noisy}))
	var c := _play(bm, json.events)
	_ok(int(c.score) == int(a.score) and int(c.max_combo) == int(a.max_combo), "Replay ueber JSON identisch")


func _test_view_state() -> void:
	var bm := _beatmap(_obj(1000, 3) + _obj(1500, 1) + _obj(2000, 0, 2600) + _obj(3000, 0))
	var p := TracePath.from_beatmap(bm, 520.0)
	var core := ManiaCore.new()
	core.setup(bm, -1.0, 1.0)
	var cols: Array[Color] = []
	for i in bm.hit_objects.size():
		cols.append(Color.WHITE)
	var v := TraceView.new()
	v.setup(p, core, cols)
	v.t_ms = 1000.0
	v.on_judged(0, {"quality": 0, "column": 3, "dt": 2.0})
	v.on_judged(1, {"quality": 5, "column": 1, "miss_kind": "FULL"})
	v.on_hold_start(2, 1)
	v.on_judged(2, {"quality": 5, "column": 0, "hold_end": true, "held": false})
	_ok(v._hit_q[0] == 0 and v._hit_q[1] == 5, "View merkt Urteile")
	_ok(v._gray.size() == 2 and v._frays.size() == 2, "Miss/Drop grau und ausgefranst")
	_ok(not v._live.has(2), "Hold-Ende beendet Leuchten")
	v.free()
