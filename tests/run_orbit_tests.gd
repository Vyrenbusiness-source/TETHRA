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
	_test_orbit_mods()
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
	_test_reachability_all()
	_test_std_basic()
	_test_std_streams()
	_test_std_fair_mixed()
	_test_sources_compare()
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
	c.key_down(0, 1005.0, 97.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MAX and absf(got[0].angle_err - 7.0) < EPS,
			"Zeit + Winkel mittig = CORE, angle_err 7")
	c.key_down(0, 2040.0, 90.0)
	_ok(got.has(1) and got[1].quality == OrbitCore.Quality.PERFECT and got[1].late, "dt +40 bei OD8 = PERFECT, spaet")
	c.key_down(0, 2940.0, 10.0)
	_ok(got.has(2) and got[2].quality == OrbitCore.Quality.GOOD, "ueber 0 Grad hinweg (350 vs 10) = Treffer")
	c.key_down(0, 4000.0 - c.w50 - 10.0, 0.0)
	_ok(got.has(3) and got[3].quality == OrbitCore.Quality.MISS, "zu frueh gezielt frisst das Ziel")
	c.update(5000.0 + c.w50 + 1.0)
	_ok(got.has(4) and got[4].quality == OrbitCore.Quality.MISS and got[4].miss_kind == "FULL", "verpasst = MISS")
	_ok(c.combo == 0 and c.max_combo == 3, "Combo wie Mania")


func _test_orbit_mods() -> void:
	print("- Orbit-Mods (Fenster, Multiplikator, Anzeige)")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 90.0, 0, 0), OrbitNote.make(2000.0, 90.0, 0, 1),
			OrbitNote.make(3000.0, 90.0, 0, 2)]
	var plain := _core(ns)
	var pr := OrbitCore.new()
	pr.setup(ns, 8.0, 1.0, 5.0, {"PR": true})
	_ok(absf(pr.w300 - plain.w300 * 0.7) < EPS and absf(pr.w50 - plain.w50 * 0.7) < EPS
			and absf(pr.w_miss - plain.w_miss * 0.7) < EPS, "PR: Zeitfenster x0,7")
	_ok(absf(pr.angle_tol - 22.0 * 0.7) < EPS and absf(pr.center_tol - 9.0 * 0.7) < EPS
			and plain.angle_tol == OrbitCore.ANGLE_TOL_DEG, "PR: Winkel 15,4 / Mitte 6,3, ohne Mod 22 / 9")
	# 18 Grad daneben: ohne Mod ein Treffer, mit PR keiner.
	var g0 := _results(plain)
	var g1 := _results(pr)
	plain.key_down(0, 1000.0, 108.0)
	pr.key_down(0, 1000.0, 108.0)
	_ok(g0.has(0) and g0[0].quality != OrbitCore.Quality.MISS and not g1.has(0), "PR: 18 Grad daneben trifft nicht mehr")
	# 8 Grad daneben zeitgenau: ohne Mod CORE, mit PR nur SHARP.
	plain.key_down(0, 2000.0, 98.0)
	pr.key_down(0, 2000.0, 98.0)
	_ok(g0[1].quality == OrbitCore.Quality.MAX and g1[1].quality == OrbitCore.Quality.PERFECT, "PR: CORE-Mitte enger")
	# Zeitfehler zwischen PR-w50 und normalem w50: normal Treffer, PR verpasst (Ziel frisst).
	var dt := plain.w50 * 0.85
	plain.key_down(0, 3000.0 + dt, 90.0)
	pr.key_down(0, 3000.0 + dt, 90.0)
	pr.update(3000.0 + dt + 1.0)
	_ok(g0[2].quality != OrbitCore.Quality.MISS and g1.has(2) and g1[2].quality == OrbitCore.Quality.MISS,
			"PR: Zeitfehler 0,85 x w50 ist MISS")
	_ok(absf(OrbitCore.mod_multiplier({}) - 1.0) < EPS
			and absf(OrbitCore.mod_multiplier({"HD": true}) - 1.06) < EPS
			and absf(OrbitCore.mod_multiplier({"FI": true}) - 1.06) < EPS
			and absf(OrbitCore.mod_multiplier({"PR": true}) - 1.12) < EPS
			and absf(OrbitCore.mod_multiplier({"HD": true, "PR": true, "NF": true}) - 1.06 * 1.12 * 0.5) < EPS,
			"Multiplikator HD 1,06 / FI 1,06 / PR 1,12, mit NF x0,5")
	var hd := OrbitCore.new()
	hd.setup(ns, 8.0, 1.0, 5.0, {"HD": true})
	hd.key_down(0, 1000.0, 90.0)
	hd.key_down(0, 2000.0, 90.0)
	hd.key_down(0, 3000.0, 90.0)
	var p2 := _core(ns)
	p2.key_down(0, 1000.0, 90.0)
	p2.key_down(0, 2000.0, 90.0)
	p2.key_down(0, 3000.0, 90.0)
	_ok(hd.w50 == p2.w50 and hd.score == int(round(p2.score * 1.06)), "HD: Fenster gleich, Score x1,06")
	_ok(hd.stats().mods == ["HD"] and OrbitCore.mods_text({"PR": true, "NF": true, "FI": true}) == "FI PR NF",
			"Mods in Stats und Badge-Text")
	var rm := OrbitCore.replay_mods({"meta": {"mods": {"HD": true, "PR": true, "NF": false}}})
	_ok(rm.HD and rm.PR and not rm.FI and not rm.NF and OrbitCore.replay_mods({}).is_empty() == false
			and not OrbitCore.replay_mods({}).HD, "Replay-Meta liefert HD/FI/PR (alte Replays: keine)")
	# Darstellung: HD verblasst auf den letzten 40 %, FI erscheint spaet.
	var v := OrbitView.new()
	v.preempt = 1000.0
	var a_far := v.mod_alpha(900.0)
	v.mod_hidden = true
	_ok(a_far == 1.0 and v.mod_alpha(700.0) == 1.0 and v.mod_alpha(150.0) < 0.3 and v.mod_alpha(50.0) == 0.0,
			"HD: sichtbar bis 60 %, weg vor dem Ring")
	v.mod_hidden = false
	v.mod_fade_in = true
	_ok(v.mod_alpha(900.0) == 0.0 and v.mod_alpha(550.0) == 0.0 and v.mod_alpha(300.0) == 1.0,
			"FI: erst ab der Haelfte sichtbar")
	v.free()


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
	print("- Orbit-Wertung (eigene Acc/Score, HP/Kombo wie Mania)")
	var dts := [0.0, 10.0, -30.0, 45.0, -60.0, 80.0, 110.0, -120.0, 5.0, 999.0, 20.0, -15.0]
	var aims := [0.0, 4.0, 12.0, 20.0, 0.0, 6.0, 15.0, 2.0, 9.5, 0.0, 21.0, 3.0]
	var bm := _bm(7.0)
	var ns: Array[OrbitNote] = []
	for i in dts.size():
		_add(bm, 1000.0 + i * 1000.0, 0)
		ns.append(OrbitNote.make(1000.0 + i * 1000.0, 45.0, 0, i))
	var m := ManiaCore.new()
	m.setup(bm)
	var o := OrbitCore.new()
	o.setup(ns, bm.od(), 1.0, bm.hp(), m.mods)
	var got := _results(o)
	for i in dts.size():
		var t: float = 1000.0 + i * 1000.0 + float(dts[i])
		if dts[i] < 500.0:
			m.key_down(0, t)
			o.key_down(0, t, 45.0 + float(aims[i]))
		m.update(t + 1.0)
		o.update(t + 1.0)
	m.update(20000.0)
	o.update(20000.0)
	var want := 0.0
	for i in dts.size():
		var r: Dictionary = got[i]
		if r.quality != OrbitCore.Quality.MISS:
			want += OrbitCore.hit_value(r.quality, r.angle_err)
	want /= float(dts.size())
	_ok(absf(o.accuracy() - want) < EPS and o.n_miss == 1, "Acc = Mittel aus Zeitwert x Zielfaktor (%.4f)" % want)
	_ok(got[1].quality == OrbitCore.Quality.MAX and got[8].quality != OrbitCore.Quality.MAX,
			"CORE nur mittig (9.5 Grad = SHARP)")
	_ok(OrbitCore.hit_value(0, 0.0) == 1.0 and absf(OrbitCore.hit_value(0, 22.0) - 0.88) < EPS
			and OrbitCore.hit_value(1, 0.0) < 1.0, "Zielfaktor 1.0 mittig, 0.88 am Rand")
	var s := o.stats()
	_ok(s.score == o.orbit_score() and s.grade == o.grade() and s.mode == "orbit", "stats() nutzt Orbit-Score")
	_ok(s.score < 1000000 and s.accuracy < m.accuracy() + 0.2, "Score unter Max (%d)" % s.score)
	_ok(absf(m.hp - o.hp) < EPS and m.max_combo == o.max_combo, "HP + Combo gleich")


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


## Spielbarkeit ueber ALLE 4K-Maps der Bibliothek: Zeiten exakt, Zeigertempo,
## Flicks, ein Finger pro Ring, Akkorde am selben Winkel. Verstoesse = 0.
func _test_reachability_all() -> void:
	print("- Spielbarkeit (alle 4K-Maps)")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var tot := {"timing": 0, "speed": 0, "flick": 0, "ring": 0, "chord": 0, "targets": 0}
	var diffs := 0
	var sets := 0
	var worst := 0.0
	for f in da.get_files():
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		var used := false
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if not bm.is_mania() or bm.column_count() != 4 or bm.hit_objects.is_empty():
				continue
			var ns := OrbitConverter.convert(bm)
			var v := OrbitConverter.violations(ns, bm)
			for k in tot:
				tot[k] += int(v[k])
			worst = maxf(worst, _max_speed(ns))
			diffs += 1
			used = true
			if int(v.timing) + int(v.speed) + int(v.flick) + int(v.ring) + int(v.chord) > 0:
				print("  Verstoss: %s [%s] %s" % [f, bm.version_name(), v])
		if used:
			sets += 1
	print("  %d Sets, %d Diffs, %d Ziele; Verstoesse: Zeit %d, Tempo %d, Flick %d, Ring %d, Akkord %d; max Tempo %.3f Grad/ms" % [
		sets, diffs, tot.targets, tot.timing, tot.speed, tot.flick, tot.ring, tot.chord, worst])
	_ok(diffs > 0 or sets == 0, "Bibliothek gelesen")
	_ok(int(tot.timing) == 0, "Zeiten = Original (max 2 ms Akkord-Raster)")
	_ok(int(tot.speed) == 0, "Zeigertempo <= %.1f Grad/ms" % OrbitConverter.MAX_DEG_PER_MS)
	_ok(int(tot.flick) == 0, "Flicks <= 150 Grad/250 ms, <= 90 Grad unter 150 ms")
	_ok(int(tot.ring) == 0, "Ein Finger pro Ring (>= 90 ms, nach Bogen >= 150 ms)")
	_ok(int(tot.chord) == 0, "Akkorde nur am selben Winkel")


# --- osu!standard (Mode 0) ---

func _std_bm(bpm: float = 180.0, offset: float = 1000.0) -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "0"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5", "ApproachRate": "9"}
	var tp := TimingPoint.new()
	tp.time = offset
	tp.beat_length = 60000.0 / bpm
	tp.meter = 4
	tp.uninherited = true
	bm.timing_points.append(tp)
	return bm


func _circle(bm: Beatmap, t: float, x: float, y: float) -> void:
	var c := HitCircle.new()
	c.time = t
	c.x = x
	c.y = y
	bm.hit_objects.append(c)


## Gerader Slider von (x, y) nach (x2, y2), dur ms je Durchlauf.
func _slider(bm: Beatmap, t: float, x: float, y: float, x2: float, y2: float,
		dur: float, slides: int = 1) -> void:
	var s := HitSlider.new()
	s.time = t
	s.x = x
	s.y = y
	s.curve_type = "L"
	s.curve_points = PackedVector2Array([Vector2(x, y), Vector2(x2, y2)])
	s.length = Vector2(x, y).distance_to(Vector2(x2, y2))
	s.slides = slides
	s.single_duration_ms = dur
	bm.hit_objects.append(s)


func _spinner(bm: Beatmap, t: float, end: float) -> void:
	var s := Spinner.new()
	s.time = t
	s.x = 256.0
	s.y = 192.0
	s.spin_end_time = end
	bm.hit_objects.append(s)


## Deterministisch "zufaellige" osu!standard-Map (LCG): Spruenge, Streams,
## Stacks, Slider (auch Repeats), Spinner, Abstaende von 1/8 bis 2 Takte.
func _std_mixed_map() -> Beatmap:
	var bm := _std_bm(180.0, 500.0)
	var s := 4242
	var t := 500.0
	var p := Vector2(256, 192)
	var beat := 60000.0 / 180.0
	var gaps := [beat / 4.0, beat / 4.0, beat / 4.0, beat / 2.0, beat / 2.0, beat, beat * 2.0, beat / 8.0, beat * 1.5]
	for i in 1200:
		s = (s * 1103515245 + 12345) % 2147483648
		var kind := (s >> 8) % 20
		s = (s * 1103515245 + 12345) % 2147483648
		var step := float((s >> 8) % 260)
		s = (s * 1103515245 + 12345) % 2147483648
		var ang := float((s >> 8) % 360)
		var q := p + Vector2(step, 0).rotated(deg_to_rad(ang))
		q = Vector2(clampf(q.x, 0, 512), clampf(q.y, 0, 384))
		if kind < 3:
			q = p  # Stack
		if kind == 19:
			_spinner(bm, t, t + beat * 6.0)
			t += beat * 8.0
			continue
		if kind >= 15:
			var e := q + Vector2(120, 0).rotated(deg_to_rad(ang + 70.0))
			e = Vector2(clampf(e.x, 0, 512), clampf(e.y, 0, 384))
			var slides := 1 + (kind % 3)
			_slider(bm, t, q.x, q.y, e.x, e.y, beat * (0.5 if kind % 2 == 0 else 1.0), slides)
			t += float(bm.hit_objects[-1].end_time() - t) + beat / 2.0
			p = e if slides % 2 == 1 else q
			continue
		_circle(bm, t, q.x, q.y)
		p = q
		s = (s * 1103515245 + 12345) % 2147483648
		t += float(gaps[(s >> 8) % gaps.size()])
	return bm


## Pruefung "fair": alle Zaehler von violations() = 0, Bogen-Enden exakt.
func _std_fair(ns: Array[OrbitNote], bm: Beatmap, label: String) -> void:
	var v := OrbitConverter.violations(ns, bm)
	var bad := int(v.timing) + int(v.speed) + int(v.flick) + int(v.ring) + int(v.chord)
	_ok(bad == 0, label + ": keine Verstoesse %s" % str(v))
	var exact := true
	for n in ns:
		var o: HitObject = bm.hit_objects[n.source_index]
		exact = exact and n.time_ms == o.time
		if n.is_arc:
			exact = exact and n.end_ms == o.end_time()
	_ok(exact, label + ": Zeiten und Bogen-Enden = Original exakt")


func _test_std_basic() -> void:
	print("- osu!standard: Grundformen")
	var bm := _std_bm(120.0, 1000.0)
	_circle(bm, 1000.0, 256.0, 40.0)       # oben
	_circle(bm, 1500.0, 470.0, 192.0)      # rechts
	_slider(bm, 2000.0, 470.0, 192.0, 470.0, 340.0, 500.0)
	_spinner(bm, 3500.0, 5500.0)
	_circle(bm, 6000.0, 100.0, 192.0)
	for style in [OrbitConverter.StdStyle.FLOW, OrbitConverter.StdStyle.POLAR]:
		var ns := OrbitConverter.convert_std(bm, style)
		var name := "FLOW" if style == OrbitConverter.StdStyle.FLOW else "POLAR"
		_ok(ns.size() == 5, name + ": jedes Objekt ein Ziel (%d)" % ns.size())
		if ns.size() != 5:
			continue
		_ok(not ns[0].is_arc and ns[2].is_arc and ns[3].is_arc and not ns[4].is_arc,
				name + ": Kreis = Tap, Slider/Spinner = Bogen")
		_ok(absf(ns[0].angle_deg) < EPS, name + ": erstes Ziel = Richtung der Position (oben = 0)")
		_ok(absf(ns[3].span_deg()) >= 200.0, name + ": Spinner = langer Bogen (%.0f Grad)" % ns[3].span_deg())
		_std_fair(ns, bm, name)
	var polar := OrbitConverter.convert_std(bm, OrbitConverter.StdStyle.POLAR)
	_ok(absf(polar[1].angle_deg - 90.0) < EPS, "POLAR: rechts = 90 Grad")
	_ok(polar[2].span_deg() > 20.0, "POLAR: Slider nach unten rechts dreht im Uhrzeigersinn (%.0f)" % polar[2].span_deg())
	# convert() waehlt nach Mode.
	_ok(_sig(OrbitConverter.convert(bm)) == _sig(OrbitConverter.convert_std(bm, OrbitConverter.std_style)),
			"convert() nimmt fuer Mode 0 den Standard-Weg")
	_ok(OrbitConverter.convert(_bm()).is_empty(), "leere Mania-Map bleibt leer")


func _test_std_streams() -> void:
	print("- osu!standard: Streams, Stacks, Flow")
	# 1/4-Stream bei 180 BPM (83 ms): alle bleiben, Ringe wechseln ab.
	var bm := _std_bm(180.0, 1000.0)
	for i in 32:
		var sp := Vector2(256, 192) + Vector2(0, -150).rotated(deg_to_rad(i * 5.0))
		_circle(bm, 1000.0 + i * 250.0 / 3.0, sp.x, sp.y)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 32, "Stream 83 ms bleibt vollstaendig (%d)" % ns.size())
	var alt := true
	for i in range(1, ns.size()):
		alt = alt and ns[i].ring != ns[i - 1].ring
	_ok(alt, "Stream wechselt die Ringe (Tasten abwechseln)")
	_std_fair(ns, bm, "Stream")
	# 1/6 bei 200 BPM (50 ms): Dichte-Reduktion wie Mania.
	var bm2 := _std_bm(200.0, 1000.0)
	for i in 40:
		var bp := Vector2(256, 192) + Vector2(0, -150).rotated(deg_to_rad(i * 3.0))
		_circle(bm2, 1000.0 + i * 50.0, bp.x, bp.y)
	var ns2 := OrbitConverter.convert_std(bm2)
	var min_gap := INF
	for i in range(1, ns2.size()):
		min_gap = minf(min_gap, ns2[i].time_ms - ns2[i - 1].time_ms)
	_ok(min_gap >= OrbitConverter.MIN_GAP_MS - EPS, "Burst 50 ms -> Abstand >= 75 ms (%.0f)" % min_gap)
	_std_fair(ns2, bm2, "Burst")
	# Stack: gleiche Position = gleicher Winkel.
	var bm3 := _std_bm(180.0, 1000.0)
	_circle(bm3, 1000.0, 300.0, 100.0)
	_circle(bm3, 1000.0 + 250.0 / 3.0, 300.0, 100.0)
	_circle(bm3, 1000.0 + 500.0 / 3.0, 300.0, 100.0)
	var ns3 := OrbitConverter.convert_std(bm3)
	_ok(ns3.size() == 3 and absf(ns3[0].angle_deg - ns3[2].angle_deg) < EPS, "Stack bleibt am selben Winkel")
	# Hin-und-her-Spruenge = Pendel, Kreismuster = Drehung.
	var bm4 := _std_bm(150.0, 1000.0)
	for i in 16:
		_circle(bm4, 1000.0 + i * 400.0, 100.0 if i % 2 == 0 else 400.0, 60.0)
	var a4 := OrbitConverter.analyze(OrbitConverter.convert_std(bm4), bm4)
	_ok(float(a4.reversal) > 0.9, "Hin-und-her = Pendel (Wenden %.0f%%)" % (float(a4.reversal) * 100.0))
	var bm5 := _std_bm(150.0, 1000.0)
	for i in 24:
		var p := Vector2(256, 192) + Vector2(0, -140).rotated(deg_to_rad(i * 45.0))
		_circle(bm5, 1000.0 + i * 200.0, p.x, p.y)
	var ns5 := OrbitConverter.convert_std(bm5)
	var a5 := OrbitConverter.analyze(ns5, bm5)
	var turn := 0.0
	for i in range(1, ns5.size()):
		turn += OrbitNote.delta_deg(ns5[i - 1].angle_deg, ns5[i].angle_deg)
	_ok(float(a5.reversal) < 0.05 and turn > 300.0, "Kreismuster im Uhrzeigersinn = Drehung (%.0f Grad)" % turn)
	# POLAR (Standard): Ziel zeigt genau in Richtung der osu-Position.
	var exact := true
	for i in ns5.size():
		exact = exact and OrbitNote.dist_deg(ns5[i].angle_deg, fposmod(i * 45.0, 360.0)) < 0.01
	_ok(OrbitConverter.std_style == OrbitConverter.StdStyle.POLAR and exact,
			"POLAR: Winkel = Richtung der Position zur Mitte (wenn erreichbar)")
	# FLOW: Hin-und-her ebenso Pendel, Kreismuster ebenso Drehung.
	var f4 := OrbitConverter.analyze(OrbitConverter.convert_std(bm4, OrbitConverter.StdStyle.FLOW), bm4)
	var f5 := OrbitConverter.analyze(OrbitConverter.convert_std(bm5, OrbitConverter.StdStyle.FLOW), bm5)
	_ok(float(f4.reversal) > 0.9 and float(f5.reversal) < 0.05, "FLOW: Pendel bzw. Drehung")


func _test_std_fair_mixed() -> void:
	print("- osu!standard: Fairness (gemischte Map)")
	var bm := _std_mixed_map()
	for style in [OrbitConverter.StdStyle.FLOW, OrbitConverter.StdStyle.POLAR]:
		var name := "FLOW" if style == OrbitConverter.StdStyle.FLOW else "POLAR"
		var ns := OrbitConverter.convert_std(bm, style)
		_ok(ns.size() > 600 and _sig(ns) == _sig(OrbitConverter.convert_std(bm, style)),
				name + ": deterministisch (%d Ziele)" % ns.size())
		_ok(_max_speed(ns) <= OrbitConverter.MAX_DEG_PER_MS + EPS, name + ": Tempo <= 0,6 Grad/ms")
		_std_fair(ns, bm, name)
		var a := OrbitConverter.analyze(ns, bm)
		_ok(int(a.weak_jumps) == 0, name + ": grosse Spruenge nur auf starken Beats")
		var pf := _bot_run(ns, 8.0, 5.0, OrbitCore.bot_plan(ns, 3, 0.0, 0.0))
		_ok(pf.n_miss == 0 and pf.accuracy() >= 1.0 - EPS, name + ": perfekter Bot = SS")


# --- Quellen-Vergleich (osu!standard vs. Mania, docs/modes/orbit_sources.md) ---

const SOURCES_DIR := "user://orbit_sources"
## Mania-Gegenstuecke (gleiche Songs) aus der Bibliothek.
## (Lime - Aurora ist in der Bibliothek 7K und faellt darum weg.)
const SOURCES_MANIA := ["Zekk - Fluctuation", "goreshit - burn this moment", "Billain - Specialist"]


## Laeuft nur, wenn user://orbit_sources/ .osz enthaelt (Testordner, nicht
## die Bibliothek). Prueft Fairness + Bot und schreibt Kennzahlen und
## Zielzeiten nach user://orbit_sources/out/ (Bericht, Audio-Analyse).
func _test_sources_compare() -> void:
	var da := DirAccess.open(SOURCES_DIR)
	if da == null:
		return
	print("- Quellen-Vergleich (osu!standard vs. Mania)")
	DirAccess.make_dir_recursive_absolute(SOURCES_DIR + "/out")
	var rows: Array = []
	var files := Array(da.get_files())
	files.sort()
	for f in files:
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(SOURCES_DIR.path_join(f))
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.mode() != 0:
				continue
			for style in [OrbitConverter.StdStyle.FLOW, OrbitConverter.StdStyle.POLAR]:
				var tag := "std-flow" if style == OrbitConverter.StdStyle.FLOW else "std-polar"
				rows.append(_source_row(tag, SOURCES_DIR.path_join(f), bm, OrbitConverter.convert_std(bm, style)))
	var mdir := MapLibrary.default_maps_dir()
	var mda := DirAccess.open(mdir)
	if mda != null:
		for f in mda.get_files():
			var hit := false
			for want in SOURCES_MANIA:
				hit = hit or str(f).find(want) >= 0
			if not hit or not str(f).to_lower().ends_with(".osz"):
				continue
			var imp := OszImporter.import(mdir.path_join(f))
			if not imp.ok:
				print("  (Mania-Quelle nicht lesbar: %s)" % f)
			for d in imp.difficulties:
				var bm: Beatmap = d.beatmap
				if bm.is_mania() and bm.column_count() == 4:
					rows.append(_source_row("mania", mdir.path_join(f), bm, OrbitConverter.convert(bm)))
	var fa := FileAccess.open(SOURCES_DIR + "/out/rows.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(rows, " "))
	fa.close()
	print("  %d Zeilen -> %s" % [rows.size(), ProjectSettings.globalize_path(SOURCES_DIR + "/out/rows.json")])


func _source_row(tag: String, path: String, bm: Beatmap, ns: Array[OrbitNote]) -> Dictionary:
	var file := path.get_file()
	var a := OrbitConverter.analyze(ns, bm)
	var v := OrbitConverter.violations(ns, bm)
	var bad := int(v.timing) + int(v.speed) + int(v.flick) + int(v.ring) + int(v.chord)
	var label := "%s %s [%s]" % [tag, file.left(30), bm.version_name()]
	_ok(bad == 0, label + ": fair %s" % str(v))
	var pf := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 0.0, 0.0))
	_ok(pf.n_miss == 0, label + ": perfekter Bot ohne Miss")
	var b1 := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 14.0, 6.0))
	var b2 := _bot_run(ns, bm.od(), bm.hp(), OrbitCore.bot_plan(ns, 11, 28.0, 11.0))
	var reds := OrbitConverter.red_points(bm)
	var times: Array = []
	var arcs_ms := 0.0
	var big_turns := 0
	var tn: Array = []
	for n in ns:
		times.append(n.time_ms)
		tn.append([n.time_ms, n.end_ms, snappedf(n.angle_deg, 0.01), snappedf(n.span_deg(), 0.01), n.ring])
		if n.is_arc:
			arcs_ms += n.duration_ms()
	var span := maxf(1.0, (ns[-1].end_ms - ns[0].time_ms)) if not ns.is_empty() else 1.0
	# Gleichmaessigkeit der Wende-Abstaende (in Schlaegen): Anteil Wenden auf
	# Taktanfang/Halbtakt.
	var pts := OrbitConverter.cursor_points(ns)
	var last_sign := 0.0
	var flips_strong := 0
	var flips := 0
	for i in range(1, pts.size()):
		var d := OrbitNote.delta_deg(pts[i - 1][1], pts[i][1])
		if absf(d) < 3.0 or pts[i][2] or pts[i - 1][2]:
			continue
		if absf(d) >= 90.0:
			big_turns += 1
		if last_sign != 0.0 and signf(d) != last_sign:
			flips += 1
			if OrbitConverter.beat_strength(reds, float(pts[i - 1][0])) >= 0.6:
				flips_strong += 1
		last_sign = signf(d)
	# Treue zur osu-Position (nur Mode 0): Abstand Zielwinkel <-> Richtung der
	# Quell-Position zur Mitte (Objekte nahe der Mitte zaehlen nicht).
	var errs := PackedFloat32Array()
	if bm.mode() == 0:
		for n in ns:
			var o: HitObject = bm.hit_objects[n.source_index]
			if o.kind != HitObject.Kind.SPINNER and o.position().distance_to(OrbitConverter.STD_CENTER) >= OrbitConverter.STD_DEAD_PX:
				errs.append(OrbitNote.dist_deg(n.angle_deg, OrbitConverter._polar_deg(o.position())))
	errs.sort()
	var pos_med := errs[errs.size() / 2] if not errs.is_empty() else -1.0
	var pos_p90 := errs[int(errs.size() * 0.9)] if not errs.is_empty() else -1.0
	var row := {"tag": tag, "pos_med": pos_med, "pos_p90": pos_p90, "file": file, "version": bm.version_name(), "objects": bm.hit_objects.size(),
		"targets": ns.size(), "kept": float(ns.size()) / float(maxi(bm.hit_objects.size(), 1)),
		"nps": a.nps, "arcs": a.arcs, "arc_share": arcs_ms / span, "chords": a.chords,
		"jumps": a.jumps, "big_turns": big_turns, "reversal": a.reversal,
		"flip_on_beat": float(flips_strong) / float(maxi(flips, 1)),
		"mean_speed": a.mean_speed, "p95_speed": a.p95_speed, "on_beat": a.on_beat, "on_half": a.on_half,
		"stars": OrbitConverter.stars(ns), "violations": bad,
		"bot_good_acc": b1.accuracy(), "bot_good_miss": b1.n_miss, "bot_good_fail": b1.failed,
		"bot_wobbly_acc": b2.accuracy(), "bot_wobbly_miss": b2.n_miss, "bot_wobbly_fail": b2.failed,
		"audio": bm.audio_filename(), "osz": ProjectSettings.globalize_path(path),
		"times": times, "notes": tn}
	print("  %s: %d->%d Ziele, %.1f/s, Boegen %d, Wenden %.0f%% (auf Schlag %.0f%%), Tempo %.3f/%.3f, Schlag %.0f%%, Sterne %.2f, Bot %.1f%%/%.1f%%, Lage %.0f/%.0f Grad" % [
		label, bm.hit_objects.size(), ns.size(), float(a.nps), int(a.arcs), float(a.reversal) * 100.0,
		float(row.flip_on_beat) * 100.0, float(a.mean_speed), float(a.p95_speed), float(a.on_beat) * 100.0,
		float(row.stars), b1.accuracy() * 100.0, b2.accuracy() * 100.0, pos_med, pos_p90])
	return row
