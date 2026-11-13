extends SceneTree

## Headless-Tests fuer OrbitCore (Satelliten-Wertung). Ausfuehren:
##   godot --headless --script res://tests/run_orbit_core_tests.gd

var _passed := 0
var _failed := 0
const P := Vector2(0.5, 0.5)
const OD := 8.0


func _initialize() -> void:
	print("=== OMEN Orbit-Core-Tests (Satelliten) ===")
	_test_hit()
	_test_aim_miss()
	_test_wrong_key()
	_test_early()
	_test_notelock()
	_test_accent()
	_test_hold_follow()
	_test_hold_drop_exact()
	_test_hold_release()
	_test_aim_factor()
	_test_score()
	_test_mods()
	_test_replay()
	_test_anti_mash()
	_test_windows()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


func _tap(t: float, pos: Vector2, key: int) -> OrbitNote:
	var n := OrbitNote.make_target(t, pos, key)
	n.spawn_ms = t - 1000.0
	return n


func _core(ns: Array[OrbitNote], mods: Dictionary = {}) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, OD, mods)
	return c


func _notes(a: Array) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	for n in a:
		out.append(n)
	return out


## Sammelt Fehldruecke: [[reason, key], ...]
func _watch(c: OrbitCore) -> Array:
	var log := []
	c.press_missed.connect(func(_p, k, r): log.append([r, k]))
	return log


func _test_hit() -> void:
	print("- Treffer")
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	c.cursor_moved(P + Vector2(0.01, 0.0), 900.0)
	c.key_down(0, 1010.0)
	c.update(1100.0)
	_ok(c.is_judged(0) and c.combo == 1 and c.n_max == 1, "Tap A mit Cursor und Taste = CORE (dt 10)")
	var s := c.stats()
	_ok(s.mode == "orbit" and s.n_max == 1 and s.max_combo == 1, "stats-Felder mode/n_max/max_combo")
	_ok(is_equal_approx(float(s.aim_err), 1.0), "aim_err in Feld x 100 (%.3f)" % float(s.aim_err))
	var c2 := _core(_notes([_tap(1000.0, P, 0)]))
	c2.cursor_moved(P, 0.0)
	c2.key_down(0, 1000.0 + c2.w_max + 1.0)
	_ok(c2.n300 == 1, "knapp ausserhalb CORE = SHARP")
	var c3 := _core(_notes([_tap(1000.0, P, 0)]))
	c3.cursor_moved(P, 0.0)
	c3.update(1000.0 + c3.w50 + 1.0)
	_ok(c3.n_miss == 1 and c3.combo == 0, "kein Druck = MISS (FULL)")


func _test_aim_miss() -> void:
	print("- Daneben")
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	var log := _watch(c)
	var r := c.aim_radius
	c.cursor_moved(P + Vector2(r + 0.005, 0.0), 0.0)
	c.key_down(0, 1000.0)
	_ok(not c.is_judged(0) and log == [["aim", 0]], "Cursor ausserhalb Trefferradius: aim, kein Treffer")
	c.cursor_moved(P + Vector2(r - 0.002, 0.0), 1010.0)
	c.key_down(0, 1020.0)
	_ok(c.is_judged(0) and c.combo == 1, "Druck am Rand im Radius (%.4f) trifft danach noch" % r)
	_ok(is_equal_approx(r, 0.045 * 1.15), "AIM_RADIUS = 1,15 x Zielradius")
	var c2 := OrbitCore.new()
	c2.setup(_notes([_tap(1000.0, P, 0)]), OD, {}, 0.1)
	_ok(is_equal_approx(c2.aim_radius, 0.115), "Zielradius aus setup-Parameter")


func _test_wrong_key() -> void:
	print("- Falsche Taste")
	var c := _core(_notes([_tap(1000.0, P, 1)]))
	var log := _watch(c)
	c.cursor_moved(P, 0.0)
	c.key_down(0, 1000.0)
	_ok(c.is_judged(0) and c.n_miss == 1 and log == [["wrong", 0]], "A auf B-Ziel: sofort Miss (wrong)")
	c.key_down(1, 1010.0)
	_ok(c.n_miss == 1 and c.combo == 0, "richtige Taste danach heilt nicht")
	# Cursor daneben: nur aim, kein Miss.
	var c2 := _core(_notes([_tap(1000.0, P, 1)]))
	var log2 := _watch(c2)
	c2.cursor_moved(Vector2(0.9, 0.1), 0.0)
	c2.key_down(0, 1000.0)
	_ok(not c2.is_judged(0) and log2.size() == 1 and log2[0][0] != "wrong", "falsche Taste neben dem Ziel: kein Miss")


func _test_early() -> void:
	print("- Zu frueh")
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	var log := _watch(c)
	c.cursor_moved(P, 0.0)
	c.key_down(0, 1000.0 - c.w50 - 5.0)
	_ok(not c.is_judged(0) and c.n_miss == 0 and c.combo == 0 and log == [["early", 0]],
		"vor dem 50er-Fenster: early, kein Miss, Ziel bleibt")
	c.key_down(0, 1000.0)
	_ok(c.is_judged(0) and c.n_max == 1, "Ziel danach trotzdem trefferbar")


func _test_notelock() -> void:
	print("- Notelock")
	var a := _tap(1000.0, Vector2(0.3, 0.5), 0)
	var b := _tap(1030.0, Vector2(0.7, 0.5), 1)
	var c := _core(_notes([a, b]))
	var log := _watch(c)
	c.cursor_moved(Vector2(0.7, 0.5), 0.0)
	c.key_down(1, 1030.0)
	_ok(not c.is_judged(1) and log == [["lock", 1]], "spaeteres Ziel gesperrt, solange das fruehere offen ist")
	c.update(1000.0 + c.w50 + 1.0)
	_ok(c.is_judged(0) and c.n_miss == 1, "frueheres Ziel laeuft ab")
	c.key_down(1, 1000.0 + c.w50 + 2.0)
	_ok(c.is_judged(1) and c.combo == 1, "danach ist das naechste Ziel frei")
	# Gleicher Zeitpunkt: beide Ziele sind trefferbar.
	var x := _tap(1000.0, Vector2(0.3, 0.5), 0)
	var y := _tap(1000.0, Vector2(0.7, 0.5), 1)
	var c2 := _core(_notes([x, y]))
	c2.cursor_moved(Vector2(0.7, 0.5), 0.0)
	c2.key_down(1, 1000.0)
	_ok(c2.is_judged(1) and not c2.is_judged(0), "gleiche Zeit: kein Lock")


func _test_accent() -> void:
	print("- Akzent")
	var c := _core(_notes([_tap(1000.0, P, 2)]))
	var log := _watch(c)
	c.cursor_moved(P, 0.0)
	c.key_down(0, 1000.0)
	_ok(not c.is_judged(0) and log.is_empty(), "erste Taste: noch kein Treffer, kein Fehler")
	c.key_down(1, 1020.0)
	_ok(c.is_judged(0) and c.combo == 1 and c.n_max + c.n300 == 1, "beide Tasten in 40 ms: Treffer beim zweiten Druck")
	_ok(is_equal_approx(float(c.stats().accuracy), 1.0) or c.n300 == 1, "Wertung nach zweitem Druck (dt 20)")
	var c2 := _core(_notes([_tap(1000.0, P, 2)]))
	c2.cursor_moved(P, 0.0)
	c2.key_down(0, 960.0)
	c2.key_down(1, 1010.0)
	_ok(not c2.is_judged(0), "50 ms Abstand: kein Akzent")
	var c3 := _core(_notes([_tap(1000.0, P, 2)]))
	c3.cursor_moved(P, 0.0)
	c3.key_down(1, 1000.0)
	c3.key_down(0, 1040.0)
	_ok(c3.is_judged(0), "genau 40 ms: Akzent")
	var c4 := _core(_notes([_tap(1000.0, P, 2), _tap(2000.0, P, 0)]))
	c4.cursor_moved(P, 0.0)
	c4.key_down(0, 1000.0)
	c4.key_up(0, 1050.0)
	c4.update(1000.0 + c4.w50 + 1.0)
	_ok(c4.n_miss == 1, "nur eine Taste: Akzent wird MISS")


func _hold_note(key: int = 0) -> OrbitNote:
	var path := PackedVector2Array([Vector2(0.2, 0.5), Vector2(0.8, 0.5)])
	var n := OrbitNote.make_hold(1000.0, 2000.0, path, key)
	n.spawn_ms = 0.0
	return n


## Cursor folgt der Kugel in 10-ms-Schritten, Kopf bei 1000.
func _follow(c: OrbitCore, n: OrbitNote, t_to: float, off: Vector2 = Vector2.ZERO) -> void:
	var t := 1000.0
	while t <= t_to:
		c.cursor_moved(n.pos_at(t) + off, t)
		t += 10.0


func _test_hold_follow() -> void:
	print("- Halten folgen")
	var n := _hold_note()
	var c := _core(_notes([n]))
	var started := []
	c.hold_started.connect(func(i, q): started.append([i, q]))
	c.cursor_moved(n.pos, 0.0)
	c.key_down(0, 1005.0)
	_ok(started == [[0, 0]] and c.active_holds() == [0] and c.combo == 1,
		"Kopf startet das Halten (hold_started)")
	_follow(c, n, 1990.0, Vector2(0.03, 0.0))
	c.key_up(0, 1995.0)
	c.update(2100.0)
	_ok(c.is_judged(0) and c.n_max == 1 and c.n_miss == 0 and c.active_holds().is_empty(),
		"gefolgt und kurz vor Ende losgelassen = Kopf-Qualitaet (CORE)")
	var c2 := _core(_notes([_hold_note()]))
	c2.cursor_moved(n.pos, 0.0)
	c2.key_down(0, 1000.0)
	_follow(c2, n, 2000.0)
	c2.update(2500.0)
	_ok(c2.n_max == 1 and c2.n_miss == 0, "ohne Loslassen: Ende bei end_ms zaehlt")


func _test_hold_drop_exact() -> void:
	print("- Halten DROP, Zeit exakt")
	# Cursor bleibt am Start stehen: Kugel (0,0006/ms) verlaesst den Folgeradius
	# (0,09) bei 1150 ms; DROP nach 150 ms = 1300 ms.
	var n := _hold_note()
	var c := _core(_notes([n]))
	var res := []
	c.note_judged.connect(func(i, r): res.append([i, r]))
	c.cursor_moved(n.pos, 0.0)
	c.key_down(0, 1000.0)
	c.update(1290.0)
	_ok(res.is_empty() and c.hold_out_ms(0, 1290.0) > 139.0 and c.hold_out_ms(0, 1290.0) < 141.0,
		"bei 1290 noch gehalten, hold_out_ms = 140")
	c.update(1301.0)
	_ok(res.size() == 1 and res[0][1].miss_kind == "DROP" and c.n_miss == 1 and c.combo == 0,
		"nach 150 ms draussen: MISS, miss_kind DROP")
	# Bildratenunabhaengig: ein einziger grosser Sprung, gleiche Wertung.
	var c2 := _core(_notes([_hold_note()]))
	c2.cursor_moved(n.pos, 0.0)
	c2.key_down(0, 1000.0)
	c2.update(9000.0)
	_ok(c2.n_miss == 1 and c2.stats().n_max == 0, "grosser Zeitschritt = gleiches Ergebnis")
	# Kurz raus und wieder rein (<150 ms) ist ok.
	var c3 := _core(_notes([_hold_note()]))
	c3.cursor_moved(n.pos, 0.0)
	c3.key_down(0, 1000.0)
	c3.cursor_moved(n.pos_at(1100.0), 1100.0)
	c3.cursor_moved(n.pos_at(1200.0), 1200.0)
	_follow(c3, n, 2000.0)
	c3.update(2100.0)
	_ok(c3.n_miss == 0 and c3.n_max == 1, "kurz draussen (<150 ms) bleibt ok")


func _test_hold_release() -> void:
	print("- Halten zu frueh loslassen")
	var n := _hold_note()
	var c := _core(_notes([n]))
	c.cursor_moved(n.pos, 0.0)
	c.key_down(0, 1000.0)
	_follow(c, n, 1500.0)
	c.key_up(0, 1500.0)
	_ok(c.n_miss == 1 and c.is_judged(0) and c.combo == 0, "bei 1500 losgelassen = DROP")
	var c2 := _core(_notes([n]))
	c2.cursor_moved(n.pos, 0.0)
	c2.key_down(0, 1000.0)
	_follow(c2, n, 2000.0 - c2.w50 + 5.0)
	c2.key_up(0, 2000.0 - c2.w50 + 5.0)
	_ok(c2.n_miss == 0 and c2.is_judged(0), "innerhalb des 50er-Fensters vor Ende: ok")
	var c3 := _core(_notes([n]))
	c3.cursor_moved(n.pos, 0.0)
	c3.key_down(0, 1000.0)
	_follow(c3, n, 2000.0 - c3.w50 - 5.0)
	c3.key_up(0, 2000.0 - c3.w50 - 5.0)
	_ok(c3.n_miss == 1, "knapp vor dem Fenster: DROP")


func _test_aim_factor() -> void:
	print("- Zielfaktor")
	var r := 0.0518
	_ok(is_equal_approx(OrbitCore.aim_factor(0.0, r), 1.0), "Mitte 1,0")
	_ok(is_equal_approx(OrbitCore.aim_factor(r * 0.5, r), 1.0), "bis 50 % Radius 1,0")
	_ok(is_equal_approx(OrbitCore.aim_factor(r, r), 0.88), "Rand 0,88")
	_ok(is_equal_approx(OrbitCore.aim_factor(r * 0.75, r), 0.94), "75 % Radius 0,94 (linear)")
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	c.cursor_moved(P + Vector2(c.aim_radius * 0.999, 0.0), 0.0)
	c.key_down(0, 1000.0)
	var fk := OrbitCore.aim_factor(c.aim_radius * 0.999, c.aim_radius)
	var expect := 1000000.0 * (0.9 * fk + 0.1 * fk * 0.01)
	_ok(absi(c.score - int(round(expect))) <= 1, "Treffer am Rand: Score mit Faktor 0,88 (%d)" % c.score)


func _test_score() -> void:
	print("- Score/Grade")
	_ok(Array(OrbitCore.TIER_VALUE) == [1.0, 0.94, 0.68, 0.40, 0.16, 0.0], "Stufenwerte")
	var ns: Array[OrbitNote] = []
	for i in 2000:
		ns.append(_tap(1000.0 + i * 300.0, P, i % 2))
	var c := _core(ns)
	c.cursor_moved(P, 0.0)
	for n in ns:
		c.key_down(n.key, n.time_ms)
		c.key_up(n.key, n.time_ms + 20.0)
	c.update(1.0e7)
	_ok(c.grade() == "SS" and c.n_miss == 0 and c.max_combo == 2000, "perfekt = SS")
	var streak := 0.0
	for i in 2000:
		streak += minf(float(i + 1) / 100.0, 1.0)
	var expect := 1000000.0 * (0.9 + 0.1 * streak / 2000.0)
	_ok(absi(c.score - int(round(expect))) <= 1 and c.score > 990000, "Score = Formel, nahe 1.000.000 (%d)" % c.score)
	var fin := []
	var c2 := _core(_notes([_tap(1000.0, P, 0)]))
	c2.finished.connect(func(s): fin.append(s))
	c2.cursor_moved(P, 0.0)
	c2.key_down(0, 1000.0)
	c2.update(1100.0)
	_ok(fin.size() == 1 and c2.score == 901000 and fin[0].grade == "SS",
		"ein perfektes Ziel: 0,9 + 0,1 x 0,01 Streak, finished einmal (%d, %d)" % [c2.score, fin.size()])
	var c3 := _core(_notes([_tap(1000.0, P, 0), _tap(1500.0, P, 0)]))
	c3.cursor_moved(P, 0.0)
	c3.key_down(0, 1000.0 + c3.w100 - 1.0)
	c3.update(5000.0)
	_ok(c3.n_miss == 1 and c3.grade() != "SS" and c3.accuracy() < 0.5, "Miss/schwacher Treffer senken Acc und Grade")


func _test_mods() -> void:
	print("- Mods")
	var c := _core(_notes([_tap(1000.0, P, 0)]), {"HD": true, "PR": true})
	_ok(is_equal_approx(c.mod_mult, 1.06 * 1.12), "HD x PR = 1,06 x 1,12")
	var base := _core(_notes([_tap(1000.0, P, 0)]))
	_ok(is_equal_approx(c.w50, base.w50 * 0.7) and is_equal_approx(c.aim_radius, base.aim_radius * 0.7),
		"PR: Fenster und Radius 30 % enger")
	var fi := _core(_notes([_tap(1000.0, P, 0)]), {"FI": true})
	_ok(is_equal_approx(fi.mod_mult, 1.06), "FI 1,06")
	var nf := _core(_notes([_tap(1000.0, P, 0)]), {"NF": true})
	_ok(nf.no_fail and is_equal_approx(nf.mod_mult, 0.5), "NF 0,5")
	_ok(OrbitCore.mods_text({"PR": true, "NF": true, "HD": true}) == "HD PR NF", "mods_text Reihenfolge")


## Pseudo-Eingabe: Tap-Folge, Cursor leicht versetzt, Event-Zeiten mit Bruchteilen.
func _play(c: OrbitCore, ns: Array[OrbitNote], frame: float) -> void:
	var evs: Array = []
	for i in ns.size():
		var n := ns[i]
		var off := Vector2(0.01 * float((i % 3) - 1), 0.012 * float((i % 2)))
		evs.append([n.time_ms - 40.0 + 0.3, "c", n.pos + off])
		var dt := float((i * 37) % 90 - 45)
		evs.append([n.time_ms + dt + 0.4, "d", n.key])
		evs.append([n.time_ms + dt + 60.5, "u", n.key])
	evs.sort_custom(func(a, b): return a[0] < b[0])
	var t := 0.0
	var ei := 0
	var end := ns[ns.size() - 1].time_ms + 500.0
	while t < end:
		t += frame
		while ei < evs.size() and evs[ei][0] <= t:
			var e: Array = evs[ei]
			ei += 1
			match e[1]:
				"c":
					c.cursor_moved(e[2], e[0])
				"d":
					c.key_down(e[2], e[0])
				"u":
					c.key_up(e[2], e[0])
		c.update(t)


func _test_replay() -> void:
	print("- Replay deterministisch")
	var ns: Array[OrbitNote] = []
	for i in 60:
		ns.append(_tap(1000.0 + i * 250.0, Vector2(0.2 + 0.6 * fposmod(i * 0.37, 1.0), 0.3 + 0.4 * fposmod(i * 0.61, 1.0)), i % 2))
	ns.append(_hold_note())
	ns[ns.size() - 1].time_ms = 20000.0
	var hn := OrbitNote.make_hold(20000.0, 21000.0, PackedVector2Array([Vector2(0.3, 0.4), Vector2(0.6, 0.6)]), 1)
	ns[ns.size() - 1] = hn
	var a := _core(ns)
	a.set_replay_mode(true)
	_play(a, ns, 16.7)
	var b := _core(ns)
	b.set_replay_mode(true)
	_play(b, ns, 3.0)
	_ok(a.score == b.score and a.max_combo == b.max_combo and a.n_miss == b.n_miss,
		"andere Bildrate, gleiche Wertung (%d / %d)" % [a.score, b.score])
	_ok(a.replay_log.size() > 100 and a.replay_log == b.replay_log, "Event-Log gleich (%d Events)" % a.replay_log.size())
	_ok(int(a.replay_log[0][1]) == OrbitCore.EV_RULES and int(a.replay_log[0][2]) == 5 and OrbitCore.REPLAY_RULES == 5,
		"meta orbit_rules = 5 als erster Eintrag")
	var codes := {}
	for e in a.replay_log:
		codes[int(e[1])] = true
	_ok(codes.has(OrbitCore.EV_CURSOR) and codes.has(OrbitCore.EV_DOWN) and codes.has(OrbitCore.EV_DOWN + 1)
			and codes.has(OrbitCore.EV_UP) and codes.has(OrbitCore.EV_UP + 1), "Event-Codes Cursor/Down/Up")
	# Wiedergabe aus dem Log.
	var r := _core(ns)
	r.deterministic = true
	for e in a.replay_log:
		r.apply_event(e)
	r.update(1.0e6)
	_ok(r.score == a.score and r.stats().n_max == a.stats().n_max and r.n_miss == a.n_miss and r.combo == a.combo,
		"Wiedergabe des Logs = gleiche Wertung (%d)" % r.score)
	var cnt := OrbitCore.count_events(a.replay_log)
	_ok(cnt.keys > 100 and cnt.cursor > 50, "count_events")


func _spam(c: OrbitCore, ns: Array[OrbitNote]) -> void:
	for n in ns:
		c.cursor_moved(n.pos, n.time_ms - 30.0)
		c.key_down(0, n.time_ms)
		c.key_down(1, n.time_ms + 3.0)
		c.key_up(0, n.time_ms + 40.0)
		c.key_up(1, n.time_ms + 43.0)
	c.update(ns[ns.size() - 1].time_ms + 500.0)


func _test_anti_mash() -> void:
	print("- Anti-Mash")
	var ns := _notes([])
	for i in 40:
		ns.append(_tap(1000.0 + 400.0 * i, Vector2(0.3 + 0.01 * (i % 5), 0.5), [0, 1, 2, 1][i % 4]))
	var b := _core(ns)
	b.anti_mash = false
	_spam(b, ns)
	var a := _core(ns)
	_spam(a, ns)
	print("  Orbit Spam A+B: vorher Acc %.1f%% (Misses %d), nachher Acc %.1f%% (Misses %d)" % [
		b.accuracy() * 100.0, b.n_miss, a.accuracy() * 100.0, a.n_miss])
	_ok(a.accuracy() < b.accuracy() - 0.15 and a.accuracy() < 0.7 and a.n_miss > b.n_miss, "Spam: Acc faellt deutlich")
	# A-Ziel nur mit A, nicht mit Akzent-Paar: B zuerst, dann A = Miss.
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	c.cursor_moved(P, 0.0)
	c.key_down(1, 1000.0)
	c.key_down(0, 1010.0)
	_ok(c.n_miss == 1 and c.combo == 0, "B auf A-Ziel, dann A: Miss")
	# Richtige zuerst, falsche danach: Treffer bleibt.
	var d := _core(_notes([_tap(1000.0, P, 0)]))
	d.cursor_moved(P, 0.0)
	d.key_down(0, 1000.0)
	d.key_down(1, 1005.0)
	_ok(d.n_miss == 0 and d.combo == 1, "richtige dann falsche: Treffer bleibt")
	# Akzent nicht mit einer Taste allein; beide = Treffer.
	var e := _core(_notes([_tap(1000.0, P, 2)]))
	e.cursor_moved(P, 0.0)
	e.key_down(0, 1000.0)
	e.update(1000.0 + e.w50 + 1.0)
	_ok(e.n_miss == 1 and e.combo == 0, "Akzent mit A allein: Miss")
	var f := _core(_notes([_tap(1000.0, P, 2)]))
	f.cursor_moved(P, 0.0)
	f.key_down(0, 1000.0)
	f.key_down(1, 1010.0)
	_ok(f.n_miss == 0 and f.combo == 1, "Akzent mit beiden = Treffer")
	# Leer-Druck: kein Ziel im Fenster = nichts.
	var g := _core(_notes([_tap(3000.0, P, 0)]))
	var lg := _watch(g)
	g.cursor_moved(P, 0.0)
	g.key_down(1, 1000.0)
	_ok(g.n_miss == 0 and not g.is_judged(0) and not lg.has(["wrong", 1]), "Leer-Druck = nichts")


func _test_windows() -> void:
	print("- Fenster wie osu!standard (Regeln 4)")
	var w := OrbitCore.tier_windows(5.0)
	_ok(is_equal_approx(w[0], 25.0) and is_equal_approx(w[1], 50.0) and is_equal_approx(w[2], 100.0)
		and is_equal_approx(w[3], 125.0) and is_equal_approx(w[4], 150.0),
		"OD 5: CORE 25, SHARP 50, GOOD 100, FAIR 125, EDGE 150 (%s)" % str(w))
	var c := _core(_notes([_tap(1000.0, P, 0)]))
	_ok(is_equal_approx(c.w_max, 16.0) and is_equal_approx(c.w300, 32.0) and is_equal_approx(c.w200, 76.0)
		and is_equal_approx(c.w100, 98.0) and is_equal_approx(c.w50, 120.0), "OD 8 im Core: 16/32/76/98/120")
	var pr := _core(_notes([_tap(1000.0, P, 0)]), {"PR": true})
	_ok(is_equal_approx(pr.w300, 32.0 * 0.7) and is_equal_approx(pr.w50, 120.0 * 0.7), "PR: alle Fenster x 0,7")
	var tiers := [[10.0, "n_max"], [20.0, "n300"], [60.0, "n200"], [90.0, "n100"], [115.0, "n50"]]
	var ok := true
	for tq in tiers:
		var ct := _core(_notes([_tap(1000.0, P, 0)]))
		ct.cursor_moved(P, 0.0)
		ct.key_down(0, 1000.0 + float(tq[0]))
		ct.update(1200.0)
		ok = ok and int(ct.get(tq[1])) == 1
	_ok(ok, "Stufen nach |dt| 10/20/60/90/115 ms = CORE/SHARP/GOOD/FAIR/EDGE")
	var late := _core(_notes([_tap(1000.0, P, 0)]))
	late.cursor_moved(P, 0.0)
	late.key_down(0, 1000.0 + 121.0)
	late.update(1300.0)
	_ok(late.n_miss == 1 and late.n50 == 0, "ausserhalb EDGE = MISS")
	var old := OrbitCore.tier_windows(8.0, true)
	_ok(is_equal_approx(old[0], 16.5) and is_equal_approx(old[4], 127.5), "legacy (vorher): Mania-Fenster")
