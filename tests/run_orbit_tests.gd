extends SceneTree

## Headless-Tests fuer den Orbit-Modus (OrbitConverter + OrbitCore).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tests.gd

var _passed := 0
var _failed := 0
const EPS := 1e-6


func _initialize() -> void:
	print("=== TETHRA Orbit-Tests ===")
	_test_chords()
	_test_density()
	_test_determinism()
	_test_speed_limit()
	_test_arc_length()
	_test_ring_flow()
	_test_tap_judge()
	_test_wrong_ring()
	_test_arc_hold()
	_test_arc_release()
	_test_arc_out()
	_test_arc_tap_inside()
	_test_acc_like_mania()
	_test_finished_stats()
	_test_real_map()
	_test_bot_synthetic()
	_test_library_maps()
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

func _bm(od: float = 8.0) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "3"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": str(od), "HPDrainRate": "5"}
	return bm


func _add(bm: Beatmap, t: float, col: int, hold_ms: float = 0.0) -> void:
	var n := ManiaNote.new()
	n.time = t
	n.column = col
	if hold_ms > 0.0:
		n.is_hold = true
		n.hold_end = t + hold_ms
	bm.hit_objects.append(n)


## Deterministisch "zufaellige" Map (LCG): alle Abstaende, Akkorde, LNs.
func _mixed_map() -> Beatmap:
	var bm := _bm()
	var s := 12345
	var t := 500.0
	var gaps := [30.0, 40.0, 60.0, 75.0, 90.0, 120.0, 150.0, 220.0, 300.0, 600.0, 1200.0]
	var holds := [0.0, 0.0, 0.0, 0.0, 0.0, 60.0, 300.0, 1000.0, 3000.0]
	for i in 1500:
		s = (s * 1103515245 + 12345) % 2147483648
		var col := (s >> 8) % 4
		s = (s * 1103515245 + 12345) % 2147483648
		var hold: float = holds[(s >> 8) % holds.size()]
		_add(bm, t, col, hold)
		s = (s * 1103515245 + 12345) % 2147483648
		if (s >> 8) % 7 == 0:
			_add(bm, t, (col + 1 + (s >> 12) % 3) % 4)
		s = (s * 1103515245 + 12345) % 2147483648
		t += float(gaps[(s >> 8) % gaps.size()])
	return bm


func _sig(ns: Array[OrbitNote]) -> String:
	var parts: PackedStringArray = []
	for n in ns:
		parts.append("%.3f/%.3f/%.4f/%.4f/%d/%s/%d" % [n.time_ms, n.end_ms, n.angle_deg,
				n.end_angle_deg, n.ring, n.is_arc, n.source_index])
	return ";".join(parts)


## Cursor-Punkte (Kopf, Bogen-Ende) in Zeitfolge; groesste Winkelgeschwindigkeit
## zwischen zwei Punkten in Grad/ms (INF bei Sprung ohne Zeitabstand).
func _max_speed(ns: Array[OrbitNote]) -> float:
	var pts: Array = []
	for n in ns:
		pts.append([n.time_ms, n.angle_deg])
		if n.is_arc:
			pts.append([n.end_ms, OrbitNote.wrap_deg(n.end_angle_deg)])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	var best := 0.0
	for i in range(1, pts.size()):
		var dt: float = pts[i][0] - pts[i - 1][0]
		var dd := OrbitNote.dist_deg(pts[i - 1][1], pts[i][1])
		if dt <= 0.001:
			if dd > 0.01:
				return INF
			continue
		best = maxf(best, dd / dt)
	return best


func _core(ns: Array[OrbitNote], od: float = 8.0) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, od, 1.0, 5.0, {})
	return c


func _results(c: OrbitCore) -> Dictionary:
	var got := {}
	c.note_judged.connect(func(i: int, r: Dictionary) -> void: got[i] = r)
	return got


# --- Umwandlung ---

func _test_chords() -> void:
	print("- Akkorde")
	var bm := _bm()
	_add(bm, 1000.0, 0)
	_add(bm, 1000.0, 2)
	_add(bm, 2000.0, 0)
	_add(bm, 2000.0, 1)
	_add(bm, 2001.0, 2)
	_add(bm, 2000.0, 3)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 4, "2er- und 4er-Akkord ergeben je zwei Ziele (%d)" % ns.size())
	if ns.size() != 4:
		return
	_ok(ns[0].ring == 0 and ns[1].ring == 1, "beide Ringe belegt")
	_ok(absf(ns[0].angle_deg - ns[1].angle_deg) < EPS and absf(ns[2].angle_deg - ns[3].angle_deg) < EPS,
			"Akkord-Ziele am selben Winkel")
	_ok(ns[0].source_index == 0 and ns[1].source_index == 1, "niedrigste Spalte innen, hoechste aussen")


func _test_density() -> void:
	print("- Dichte-Reduktion")
	var bm := _bm()
	for i in 100:
		_add(bm, 1000.0 + i * 40.0, i % 4)
	var ns := OrbitConverter.convert(bm)
	var min_gap := INF
	for i in range(1, ns.size()):
		min_gap = minf(min_gap, ns[i].time_ms - ns[i - 1].time_ms)
	_ok(min_gap >= OrbitConverter.MIN_GAP_MS - EPS, "Stream 40 ms -> Abstand >= %d ms (%.0f)" % [OrbitConverter.MIN_GAP_MS, min_gap])
	_ok(ns.size() == 50, "jede zweite Note bleibt (%d von 100)" % ns.size())
	var bm2 := _bm()
	for i in 40:
		_add(bm2, 1000.0 + i * 80.0, i % 4)
	_ok(OrbitConverter.convert(bm2).size() == 40, "Stream 80 ms bleibt vollstaendig")


func _test_determinism() -> void:
	print("- Deterministisch")
	var a := OrbitConverter.convert(_mixed_map())
	var b := OrbitConverter.convert(_mixed_map())
	_ok(a.size() > 100 and _sig(a) == _sig(b), "gleiche Map = gleiches Muster (%d Ziele)" % a.size())
	var ok := true
	for n in a:
		if n.angle_deg < 0.0 or n.angle_deg >= 360.0 or n.ring < 0 or n.ring > 1:
			ok = false
	_ok(ok, "Winkel in [0,360), Ring 0/1")


func _test_speed_limit() -> void:
	print("- Winkelgeschwindigkeit")
	var ns := OrbitConverter.convert(_mixed_map())
	var v := _max_speed(ns)
	_ok(v <= OrbitConverter.MAX_DEG_PER_MS + EPS, "max %.3f Grad/ms <= %.2f" % [v, OrbitConverter.MAX_DEG_PER_MS])
	# Kleine Abstaende = kleine Spruenge.
	var bm := _bm()
	for i in 16:
		_add(bm, 1000.0 + i * 100.0, i % 4)
	var roll := OrbitConverter.convert(bm)
	var small := true
	var turn := 0.0
	for i in range(1, roll.size()):
		var d := OrbitNote.delta_deg(roll[i - 1].angle_deg, roll[i].angle_deg)
		small = small and absf(d) <= OrbitConverter.COL_STEP_DEG + EPS
		turn += d
	_ok(small, "Roll 100 ms: Spruenge <= %d Grad" % OrbitConverter.COL_STEP_DEG)
	_ok(absf(turn) > 300.0, "Roll dreht gleichmaessig im Kreis (%.0f Grad)" % turn)
	var bm2 := _bm()
	_add(bm2, 1000.0, 0)
	_add(bm2, 2000.0, 2)
	var jump := OrbitConverter.convert(bm2)
	_ok(OrbitNote.dist_deg(jump[0].angle_deg, jump[1].angle_deg) > 90.0, "grosser Abstand darf weit springen")


func _test_arc_length() -> void:
	print("- Bogen-Laenge")
	var bm := _bm()
	_add(bm, 1000.0, 0, 1000.0)
	_add(bm, 4000.0, 1, 5000.0)
	_add(bm, 12000.0, 2, 50.0)
	_add(bm, 15000.0, 0, 1000.0)
	_add(bm, 15000.0, 3, 4000.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 5, "5 Ziele (%d)" % ns.size())
	if ns.size() != 5:
		return
	_ok(ns[0].is_arc and absf(absf(ns[0].span_deg()) - 120.0) < EPS, "1000 ms -> 120 Grad (%.1f)" % ns[0].span_deg())
	_ok(ns[1].is_arc and absf(absf(ns[1].span_deg()) - OrbitConverter.ARC_MAX_DEG) < EPS, "5000 ms gedeckelt auf %d Grad" % OrbitConverter.ARC_MAX_DEG)
	_ok(not ns[2].is_arc and ns[2].end_ms == ns[2].time_ms, "LN 50 ms -> Tap")
	var v3 := ns[3].span_deg() / ns[3].duration_ms()
	var v4 := ns[4].span_deg() / ns[4].duration_ms()
	_ok(ns[3].is_arc and ns[4].is_arc and absf(v3 - v4) < EPS, "LN-Akkord: beide Boegen gleich schnell")
	_ok(absf(ns[4].angle_at(ns[4].end_ms) - OrbitNote.wrap_deg(ns[4].end_angle_deg)) < 1e-4, "angle_at(Ende) = Bogen-Ende")


func _test_ring_flow() -> void:
	print("- Ring-Wahl")
	var bm := _bm()
	for i in 8:
		_add(bm, 1000.0 + i * 100.0, 1)
	_add(bm, 3000.0, 0)
	_add(bm, 4000.0, 3)
	var ns := OrbitConverter.convert(bm)
	var alt := true
	for i in range(1, 8):
		alt = alt and ns[i].ring != ns[i - 1].ring
	_ok(alt, "Jack/Stream wechselt den Ring")
	_ok(ns[8].ring == 0 and ns[9].ring == 1, "ruhige Stellen: Spaltenhaelfte bestimmt Ring")
	var bm2 := _bm()
	_add(bm2, 1000.0, 0, 500.0)
	_add(bm2, 1550.0, 0)
	var n2 := OrbitConverter.convert(bm2)
	_ok(n2[1].ring != n2[0].ring, "direkt nach Bogen-Ende anderer Ring")


# --- Wertung ---

func _test_tap_judge() -> void:
	print("- Tap-Wertung (Zeit + Winkel)")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 90.0, 0, 0), OrbitNote.make(2000.0, 90.0, 0, 1),
			OrbitNote.make(3000.0, 350.0, 0, 2), OrbitNote.make(4000.0, 0.0, 0, 3),
			OrbitNote.make(5000.0, 0.0, 0, 4)]
	var c := _core(ns)
	var got := _results(c)
	c.key_down(0, 1000.0, 120.0)
	_ok(not got.has(0), "30 Grad daneben = kein Treffer")
	c.key_down(0, 1005.0, 100.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MAX and absf(got[0].angle_err - 10.0) < EPS,
			"Zeit + Winkel stimmen = MAX, angle_err 10")
	c.key_down(0, 2040.0, 90.0)
	_ok(got.has(1) and got[1].quality == OrbitCore.Quality.PERFECT and got[1].late, "dt +40 bei OD8 = PERFECT, spaet")
	c.key_down(0, 2940.0, 10.0)
	_ok(got.has(2) and got[2].quality == OrbitCore.Quality.GOOD, "ueber 0 Grad hinweg (350 vs 10) = Treffer")
	c.key_down(0, 4000.0 - c.w50 - 10.0, 0.0)
	_ok(got.has(3) and got[3].quality == OrbitCore.Quality.MISS, "zu frueh gezielt frisst das Ziel")
	c.update(5000.0 + c.w50 + 1.0)
	_ok(got.has(4) and got[4].quality == OrbitCore.Quality.MISS and got[4].miss_kind == "FULL", "verpasst = MISS")
	_ok(c.combo == 0 and c.max_combo == 3, "Combo wie Mania")


func _test_wrong_ring() -> void:
	print("- Falscher Ring")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 180.0, 1, 0)]
	var c := _core(ns)
	var got := _results(c)
	c.key_down(0, 1000.0, 180.0)
	_ok(not got.has(0), "Taste A auf aeusserem Ziel = kein Treffer")
	c.key_down(1, 1000.0, 180.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MAX and got[0].ring == 1, "Taste B trifft")


func _arc_notes() -> Array[OrbitNote]:
	var ns: Array[OrbitNote] = [OrbitNote.make_arc(1000.0, 2000.0, 0.0, 120.0, 1, 0)]
	return ns


func _follow(c: OrbitCore, n: OrbitNote, from: float, to: float, offset: float = 0.0) -> void:
	var t := from
	while t <= to:
		c.cursor_moved(n.angle_at(t) + offset, t)
		c.update(t)
		t += 20.0


func _test_arc_hold() -> void:
	print("- Bogen halten")
	var ns := _arc_notes()
	var c := _core(ns)
	var got := _results(c)
	var started := []
	c.arc_started.connect(func(i: int, q: int) -> void: started.append([i, q]))
	c.key_down(1, 1010.0, 0.0)
	_ok(started.size() == 1 and started[0][1] == OrbitCore.Quality.MAX and c.active_arc(1) == 0, "Kopf wie Tap, arc_started")
	_follow(c, ns[0], 1010.0, 2000.0, 15.0)
	c.update(2001.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MAX and got[0].held and got[0].hold_end,
			"gefolgt (15 Grad Versatz) bis zum Ende = MAX")
	_ok(c.active_arc(1) == -1 and c.combo == 1, "Bogen beendet, Combo 1")


func _test_arc_release() -> void:
	print("- Bogen zu frueh losgelassen")
	var ns := _arc_notes()
	var c := _core(ns)
	var got := _results(c)
	c.key_down(1, 1000.0, 0.0)
	_follow(c, ns[0], 1000.0, 1500.0)
	c.key_up(1, 1500.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MISS and got[0].miss_kind == "DROP"
			and got[0].drop_reason == "RELEASE", "Loslassen in der Mitte = DROP")
	var c2 := _core(_arc_notes())
	var got2 := _results(c2)
	c2.key_down(1, 1000.0, 0.0)
	_follow(c2, c2.notes[0], 1000.0, 1900.0)
	c2.key_up(1, 1900.0)
	_ok(got2.has(0) and got2[0].quality == OrbitCore.Quality.MAX, "kurz vor dem Ende loslassen ist ok")


func _test_arc_out() -> void:
	print("- Bogen ausserhalb")
	var ns := _arc_notes()
	var c := _core(ns)
	var got := _results(c)
	c.key_down(1, 1000.0, 0.0)
	c.update(1400.0)
	_ok(got.has(0) and got[0].miss_kind == "DROP" and got[0].drop_reason == "OUT",
			"Cursor bleibt stehen -> nach %d ms DROP" % OrbitCore.ARC_OUT_MS)
	var c2 := _core(_arc_notes())
	var got2 := _results(c2)
	var n: OrbitNote = c2.notes[0]
	c2.key_down(1, 1000.0, 0.0)
	_follow(c2, n, 1000.0, 1300.0)
	c2.cursor_moved(n.angle_at(1300.0) + 40.0, 1300.0)
	c2.update(1400.0)
	_ok(c2.arc_out_ms(1, 1400.0) > 50.0, "arc_out_ms zaehlt die Zeit ausserhalb")
	_follow(c2, n, 1420.0, 2000.0)
	c2.update(2001.0)
	_ok(got2.has(0) and got2[0].quality == OrbitCore.Quality.MAX, "120 ms ausserhalb, dann zurueck = ok")


func _test_arc_tap_inside() -> void:
	print("- Tap waehrend Bogen")
	var bm := _bm()
	_add(bm, 1000.0, 3, 1000.0)
	_add(bm, 1500.0, 0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 2 and ns[1].ring != ns[0].ring and absf(ns[1].angle_deg - ns[0].angle_at(1500.0)) < 1e-4,
			"Note im Bogen -> anderer Ring an der Bogen-Spitze")
	if ns.size() != 2:
		return
	var c := _core(ns)
	var got := _results(c)
	c.key_down(ns[0].ring, 1000.0, ns[0].angle_deg)
	_follow(c, ns[0], 1000.0, 1500.0)
	c.key_down(ns[1].ring, 1500.0, ns[0].angle_at(1500.0))
	_follow(c, ns[0], 1500.0, 2000.0)
	c.update(2001.0)
	_ok(got.size() == 2 and got[0].quality == OrbitCore.Quality.MAX and got[1].quality == OrbitCore.Quality.MAX,
			"beide getroffen")


func _test_acc_like_mania() -> void:
	print("- Acc/Score wie Mania")
	var dts := [0.0, 10.0, -30.0, 45.0, -60.0, 80.0, 110.0, -120.0, 5.0, 999.0, 20.0, -15.0]
	var bm := _bm(7.0)
	var ns: Array[OrbitNote] = []
	for i in dts.size():
		_add(bm, 1000.0 + i * 1000.0, 0)
		ns.append(OrbitNote.make(1000.0 + i * 1000.0, 45.0, 0, i))
	var m := ManiaCore.new()
	m.setup(bm)
	var o := OrbitCore.new()
	o.setup(ns, bm.od(), 1.0, bm.hp(), m.mods)
	for i in dts.size():
		var t: float = 1000.0 + i * 1000.0 + float(dts[i])
		if dts[i] < 500.0:
			m.key_down(0, t)
			o.key_down(0, t, 45.0)
		m.update(t + 1.0)
		o.update(t + 1.0)
	m.update(20000.0)
	o.update(20000.0)
	_ok(absf(m.accuracy() - o.accuracy()) < EPS, "accuracy gleich (%.4f)" % o.accuracy())
	_ok(m.score == o.score and m.grade() == o.grade(), "Score + Grade gleich (%d, %s)" % [o.score, o.grade()])
	_ok(absf(m.hp - o.hp) < EPS and m.max_combo == o.max_combo, "HP + Combo gleich")
	var want := float(300 * (o.n_max + o.n300) + 200 * o.n200 + 100 * o.n100 + 50 * o.n50) \
			/ float(300 * dts.size())
	_ok(absf(o.accuracy() - want) < EPS and o.n_miss == 1, "osu!mania-Acc-Formel")


func _test_finished_stats() -> void:
	print("- finished/stats")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 0.0, 0, 0), OrbitNote.make(1500.0, 0.0, 1, 1)]
	var c := _core(ns)
	var fin := []
	c.finished.connect(func(s: Dictionary) -> void: fin.append(s))
	c.key_down(0, 1000.0, 0.0)
	c.update(1300.0)
	_ok(fin.is_empty(), "noch nicht fertig")
	c.update(2000.0)
	_ok(fin.size() == 1, "finished einmal")
	var keys := ManiaCore.new().stats().keys()
	var has_all := true
	for k in keys:
		has_all = has_all and fin[0].has(k)
	_ok(has_all and fin[0].mode == "orbit", "stats() hat alle ManiaCore-Felder + mode")
	c.update(3000.0)
	_ok(fin.size() == 1, "kein zweites finished")


func _test_real_map() -> void:
	print("- Echte Map")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var files := Array(da.get_files())
	files.sort()
	var done := 0
	for f in files:
		if done >= 2 or not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if done >= 2 or not bm.is_mania() or bm.column_count() != 4 or bm.hit_objects.size() < 300:
				continue
			var label := "%s [%s]" % [str(f).left(28), bm.version_name()]
			var t0 := Time.get_ticks_usec()
			var ns := OrbitConverter.convert(bm)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var arcs := 0
			var lns := 0
			for n in ns:
				arcs += 1 if n.is_arc else 0
			for o in bm.hit_objects:
				lns += 1 if (o as ManiaNote).is_hold else 0
			var v := _max_speed(ns)
			print("  %s: %d Notes (%d LN) -> %d Ziele (%d Boegen), max %.3f Grad/ms, %.0f ms" % [
					label, bm.hit_objects.size(), lns, ns.size(), arcs, v, ms])
			_ok(_sig(ns) == _sig(OrbitConverter.convert(bm)), label + ": deterministisch")
			_ok(v <= OrbitConverter.MAX_DEG_PER_MS + EPS, label + ": Winkelgeschwindigkeit eingehalten")
			_ok(ns.size() >= bm.hit_objects.size() / 4, label + ": genug Ziele uebrig")
			# Autoplay: perfekter Spieler muss SS bekommen.
			var c := _core(ns, bm.od())
			var pts: Array = []
			for i in ns.size():
				pts.append([ns[i].time_ms, 0, i])
				if ns[i].is_arc:
					pts.append([ns[i].end_ms, 1, i])
			pts.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
			var last_t: float = ns[0].time_ms if not ns.is_empty() else 0.0
			for p in pts:
				var n: OrbitNote = ns[p[2]]
				var t: float = p[0]
				# Cursor wie im Spiel jeden Frame (16 ms) nachfuehren.
				var s := last_t + 16.0
				while s < t:
					_autoplay_cursor(c, ns, s)
					c.update(s)
					s += 16.0
				last_t = t
				_autoplay_cursor(c, ns, t)
				c.update(t)
				if p[1] == 0:
					c.key_down(n.ring, t, n.angle_deg)
				else:
					c.key_up(n.ring, t)
			c.update(bm.duration_ms() + 10000.0)
			_ok(c.accuracy() >= 1.0 - EPS and c.n_miss == 0, label + ": Autoplay = SS (%d Misses)" % c.n_miss)
			done += 1


## Autoplay-Cursor: zeigt auf die Spitze des laufenden Bogens (falls einer).
func _autoplay_cursor(c: OrbitCore, ns: Array[OrbitNote], t: float) -> void:
	for r in OrbitCore.RINGS:
		var h := c.active_arc(r)
		if h >= 0:
			c.cursor_moved(ns[h].angle_at(t), t)
			return



# --- Bot (menschlich streuend, deterministisch) ---

## Spielt ns mit einem Bot-Plan (OrbitCore.bot_plan) durch: Druck zur Zeit
## + Versatz am Winkel + Zielfehler, Boegen mit gleichem Fehler verfolgt,
## Taps 40 ms gehalten. Frames alle 16 ms wie im Spiel.
func _bot_run(ns: Array[OrbitNote], od: float, hp: float, plan: Array, no_fail: bool = false) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, od, 1.0, hp, {"NF": no_fail})
	var ev: Array = []
	for i in ns.size():
		if bool(plan[i][2]):
			continue
		var tp: float = ns[i].time_ms + float(plan[i][0])
		ev.append([tp, 0, i])
		var tr: float = ns[i].end_ms + float(plan[i][0]) * 0.5 if ns[i].is_arc else tp + 40.0
		ev.append([tr, 1, i])
	ev.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var held: Array[int] = [-1, -1]
	var t: float = ns[0].time_ms - 1000.0 if not ns.is_empty() else 0.0
	var end_t: float = ns[-1].end_ms + 2000.0 if not ns.is_empty() else 0.0
	var k := 0
	while t < end_t and not c.failed:
		while k < ev.size() and float(ev[k][0]) <= t:
			var e: Array = ev[k]
			k += 1
			var te: float = e[0]
			var n: OrbitNote = ns[e[2]]
			c.update(te)
			if e[1] == 0:
				if held[n.ring] >= 0:
					c.key_up(n.ring, te)
				held[n.ring] = e[2]
				c.key_down(n.ring, te, n.angle_at(te) + float(plan[e[2]][1]))
			elif held[n.ring] == e[2]:
				c.key_up(n.ring, te)
				held[n.ring] = -1
		for r in 2:
			var h := c.active_arc(r)
			if h >= 0:
				c.cursor_moved(ns[h].angle_at(t) + float(plan[h][1]), t)
				break
		c.update(t)
		t += 16.0
	c.update(end_t + 5000.0)
	return c


func _test_bot_synthetic() -> void:
	print("- Bot (synthetisch)")
	var bm := _mixed_map()
	var ns := OrbitConverter.convert(bm)
	var perfect := _bot_run(ns, 8.0, 5.0, OrbitCore.bot_plan(ns, 1, 0.0, 0.0))
	_ok(perfect.n_miss == 0 and perfect.accuracy() >= 1.0 - EPS, "Bot perfekt = SS")
	var p1 := OrbitCore.bot_plan(ns, 7, 24.0, 5.0)
	_ok(str(p1) == str(OrbitCore.bot_plan(ns, 7, 24.0, 5.0)), "Bot-Plan deterministisch (Seed)")
	var good := _bot_run(ns, 8.0, 5.0, p1)
	_ok(good.accuracy() > 0.85 and good.accuracy() < 1.0 and not good.failed,
		"Bot leicht streuend: hohe Acc, kein Fail (%.3f)" % good.accuracy())
	var s := good.stats()
	var total := int(s.n_max) + int(s.n300) + int(s.n200) + int(s.n100) + int(s.n50) + int(s.n_miss)
	_ok(total == ns.size(), "jedes Ziel genau einmal gewertet (%d/%d)" % [total, ns.size()])
	var m4 := _bot_run(ns, 8.0, 5.0, OrbitCore.bot_plan(ns, 3, 0.0, 0.0, 4))
	_ok(m4.n_miss >= ns.size() / 4 - 1 and m4.max_combo <= 3 + 3, "auto-miss 4: Misses + Kombo-Bruch")
	var wild := _bot_run(ns, 8.0, 10.0, OrbitCore.bot_plan(ns, 5, 0.0, 0.0, 2))
	_ok(wild.failed, "jedes 2. Ziel verpasst, HP 10: Fail")
	var nf := _bot_run(ns, 8.0, 10.0, OrbitCore.bot_plan(ns, 5, 0.0, 0.0, 2), true)
	_ok(not nf.failed and nf.hp >= 0.0, "NoFail: nie Fail")


# --- Echte Maps aus der Bibliothek: Statistik + Fairness ---

const LIB_MAPS := [
	["Billain - Specialist", "Pairo's Normal"],
	["Billain - Specialist", "Yuno's Hard"],
	["Billain - Specialist", "GoldenJumper's Insane"],
	["Lime - Aurora", "Hard"],
	["goreshit - burn this moment", "fear"],
]


func _test_library_maps() -> void:
	print("- Bibliothek (Statistik)")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var files := Array(da.get_files())
	for want in LIB_MAPS:
		var bm: Beatmap = null
		for f in files:
			if str(f).find(want[0]) < 0:
				continue
			var imp := OszImporter.import(dir.path_join(f))
			for d in imp.difficulties:
				if d.beatmap.version_name() == want[1]:
					bm = d.beatmap
			break
		if bm == null:
			print("  (%s [%s] fehlt)" % want)
			continue
		_map_report("%s [%s]" % want, bm)


func _map_report(label: String, bm: Beatmap) -> void:
	var ns := OrbitConverter.convert(bm)
	var a := OrbitConverter.analyze(ns, bm)
	print("  %s: %d -> %d Ziele (%d Boegen, %d Akkorde), %.1f/s, Spruenge>=60: %d (schwach %d), Wenden %.0f%%, Tempo mittel %.3f p95 %.3f Grad/ms, Orbit-Sterne %.2f" % [
		label, bm.hit_objects.size(), ns.size(), int(a.arcs), int(a.chords), float(a.nps),
		int(a.jumps), int(a.weak_jumps), float(a.reversal) * 100.0, float(a.mean_speed),
		float(a.p95_speed), OrbitConverter.stars(ns)])
	_ok(_max_speed(ns) <= OrbitConverter.MAX_DEG_PER_MS + EPS, label + ": Tempo gedeckelt")
	_ok(int(a.weak_jumps) == 0, label + ": grosse Spruenge nur auf starken Beats")
	var pf := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 0.0, 0.0))
	_ok(pf.n_miss == 0, label + ": perfekter Bot ohne Miss")
	var b1 := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 14.0, 6.0))
	var b2 := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 28.0, 11.0))
	print("    Bot gut: Acc %.2f%% Miss %d %s | Bot wackelig: Acc %.2f%% Miss %d %s" % [
		b1.accuracy() * 100.0, b1.n_miss, "FAIL" if b1.failed else "ok",
		b2.accuracy() * 100.0, b2.n_miss, "FAIL" if b2.failed else "ok"])
	_ok(not b1.failed and b1.accuracy() > 0.9, label + ": guter Bot schafft die Map")
