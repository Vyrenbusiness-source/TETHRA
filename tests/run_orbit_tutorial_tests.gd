extends SceneTree

## Headless-Tests fuer das Orbit-Tutorial (Satelliten): sieben Schritte, jeder
## per Bot (echte Maus-/Tasten-Events) loesbar, Muster nach der Spezifikation
## (Erscheinen auf dem Beat, Pips, Tasten, Akzent, Halten, Stream), Fehler nennen
## den Grund, Tasten aus den Settings, Ueberspringen, Gesehen-Merker, Karriere.
## Das Tutorial nutzt das Autoload Settings, darum nur per load().
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tutorial_tests.gd

const SCENE := "res://scenes/orbit_tutorial.tscn"
const SCRIPT := "res://scripts/orbit/orbit_tutorial.gd"
const FRAME := 1000.0 / 60.0

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== OMEN Orbit-Tutorial-Tests (Satelliten) ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	var old_career: String = S.career_path
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/orbit_tutorial_%d.cfg" % OS.get_process_id()
	S.career_path = "user://test_tmp/orbit_tut_career_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	DirAccess.remove_absolute(S.career_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_test_tempo(S)
	_test_patterns(S)
	_test_bot_run(tut, S)
	_test_aim_step(tut)
	_test_reasons(tut)
	_test_accent_needs_both(tut)
	_test_hold_release(tut)
	_test_keys_from_settings(tut)
	_test_skip(tut)
	tut.queue_free()
	DirAccess.remove_absolute(S.seen_path)
	DirAccess.remove_absolute(S.career_path)
	S.seen_path = old_seen
	S.career_path = old_career
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bis cond wahr ist simulieren (max. limit Frames); true, wenn erreicht.
func _run_until(tut: Control, cond: Callable, limit: int = 6000) -> bool:
	for i in limit:
		if cond.call():
			return true
		tut.advance(FRAME)
	return cond.call()


func _test_tempo(S: GDScript) -> void:
	var b: Array = S.BPMS
	_check(b.size() == 7 and int(S.STEP_COUNT) == 7, "sieben Schritte")
	_check(is_equal_approx(float(b[0]), 60.0), "Start mit 60 BPM")
	var rising := true
	for i in range(1, b.size()):
		rising = rising and float(b[i]) >= float(b[i - 1])
	_check(rising and float(b[6]) > float(b[0]), "Tempo steigt")


## Muster: sortiert, im Feld, Erscheinen exakt auf einem Beat-Tick, Pips = Runden.
func _test_patterns(S: GDScript) -> void:
	var t0 := 500.0
	var bm := 800.0
	for s in range(1, 7):
		for rnd in 2:
			var ns: Array = S.pattern(s, t0, bm, rnd)
			_check(ns.size() >= 1, "Schritt %d: Ziele" % (s + 1))
			var ok := true
			for i in ns.size():
				var n: OrbitNote = ns[i]
				var b := (n.spawn_ms - t0) / bm
				ok = ok and absf(b - roundf(b)) < 0.000001 and n.spawn_ms >= t0 - 0.001
				ok = ok and n.pos.x >= 0.06 and n.pos.x <= 0.94 and n.pos.y >= 0.08 and n.pos.y <= 0.92
				ok = ok and n.laps_left(n.spawn_ms) >= 1 and is_equal_approx(n.satellite_deg(n.time_ms), 0.0)
				if i > 0:
					ok = ok and n.time_ms >= ns[i - 1].time_ms
			_check(ok, "Schritt %d Runde %d: Beat-Tick, Feld, Satellit oben" % [s + 1, rnd])
			_check(_max_visible(ns) <= 6, "Schritt %d: hoechstens 6 Ziele sichtbar" % (s + 1))
	var sat: Array = S.pattern(1, t0, bm, 0)
	_check(sat.size() == 1 and sat[0].key == 0 and sat[0].laps_left(sat[0].spawn_ms) == 3,
			"Satellit: ein Ziel A, 3 Pips")
	var keys: Array = S.pattern(2, t0, bm, 0)
	_check(keys.any(func(n): return n.key == 0) and keys.any(func(n): return n.key == 1),
			"Tasten: A und B")
	var acc: Array = S.pattern(3, t0, bm, 0)
	_check(acc.any(func(n): return n.key == 2), "Akzent-Ziel vorhanden")
	var holds: Array = S.pattern(4, t0, bm, 0)
	var hold_ok := func(n): return n.is_hold and n.path.size() >= 2 and n.path[0] == n.pos and n.end_ms > n.time_ms
	_check(holds.all(hold_ok), "Halten: Pfad ab dem Ziel, Dauer > 0")
	var sk: Array = S.pattern(5, t0, bm, 0)
	var jump := 0.0
	var stream := 0
	for i in range(1, sk.size()):
		jump = maxf(jump, sk[i].pos.distance_to(sk[i - 1].pos))
		if absf(sk[i].time_ms - sk[i - 1].time_ms - bm * 0.5) < 0.01 and sk[i].key != sk[i - 1].key:
			stream += 1
	_check(jump > 0.5, "Skill: weite Spruenge (%.2f)" % jump)
	_check(stream >= 3, "Skill: Stream mit Wechselschlag (%d)" % stream)
	var tr_: Array = S.pattern(6, t0, bm, 0)
	var kinds := {}
	for n in tr_:
		kinds[n.key] = true
		if n.is_hold:
			kinds["hold"] = true
	_check(kinds.has(0) and kinds.has(1) and kinds.has(2) and kinds.has("hold"), "Probe: A, B, Akzent und Halten")


func _max_visible(ns: Array) -> int:
	var best := 0
	for a in ns:
		var c := 0
		for b in ns:
			if b.spawn_ms <= a.time_ms and b.time_ms >= a.time_ms:
				c += 1
		best = maxi(best, c)
	return best


func _test_bot_run(tut: Control, S: GDScript) -> void:
	tut.bot = true
	tut.enter_step(0)
	for s in 6:
		_check(int(tut.step) == s, "Schritt %d aktiv" % (s + 1))
		var best := [0]
		var reached := _run_until(tut, func():
			best[0] = maxi(best[0], int(tut.success))
			return int(tut.step) != s)
		_check(reached and int(tut.step) == s + 1, "Schritt %d per Bot geloest" % (s + 1))
		_check(best[0] >= int(S.NEED[s]), "Schritt %d: Bedingung erfuellt (%d)" % [s + 1, best[0]])
	_check(int(tut.step) == 6, "Probe-Runde erreicht")
	var ok := _run_until(tut, func(): return bool(tut.finished), 9000)
	_check(ok, "Probe-Runde endet mit Wertung")
	var st: Dictionary = tut.trial_stats
	var want: int = S.pattern(6, 0.0, 1000.0, 0).size()
	var total := int(st.get("n_max", 0)) + int(st.get("n300", 0)) + int(st.get("n200", 0)) \
			+ int(st.get("n100", 0)) + int(st.get("n50", 0)) + int(st.get("n_miss", 0))
	_check(total == want, "alle Probe-Ziele gewertet (%d von %d)" % [total, want])
	_check(int(st.get("n_miss", 1)) == 0, "Bot ohne Fehltreffer")
	_check(str(tut.trial_grade()) in ["SS", "S"], "Rang aus OrbitCore (%s)" % tut.trial_grade())
	_check(bool(OrbitCareer.load_state(S.career_path).get("offer", false)), "Karriere angeboten")
	tut.bot = false
	tut.retry_trial()
	_check(not bool(tut.finished) and int(tut.step) == 6, "Nochmal startet die Probe-Runde neu")


func _settings() -> Node:
	return root.get_node("Settings")


func _move(tut: Control, p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = tut.field_to_global(p)
	tut.handle_input(ev)


func _key(tut: Control, k: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _settings().orbit_key_inner if k == 0 else _settings().orbit_key_outer
	ev.pressed = down
	tut.handle_input(ev)


func _tap(tut: Control, k: int) -> void:
	_key(tut, k, true)
	_key(tut, k, false)


func _test_aim_step(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(0)
	_move(tut, Vector2(0.05, 0.1))
	_run_until(tut, func(): return false, 90)
	_check(int(tut.success) == 0, "Zielen: daneben zaehlt nicht")
	_move(tut, tut._aim_pos)
	_run_until(tut, func(): return false, 20)
	_check(int(tut.success) == 0, "Zielen: kurz drauf reicht nicht")
	_run_until(tut, func(): return int(tut.success) >= 1, 60)
	_check(int(tut.success) == 1, "Zielen: drauf bleiben zaehlt")
	_check(tut._aim_pos != Vector2(0.5, 0.5), "Zielen: naechstes Ziel woanders")


## Fehlergruende: andere Taste, daneben, zu frueh, verpasst.
func _test_reasons(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(2)
	var n: OrbitNote = tut.notes[0]
	_move(tut, n.pos)
	_run_until(tut, func(): return tut.t_ms >= n.time_ms - 5.0)
	_tap(tut, 1 - n.key)
	_check(str(tut.fb_reason) == "key", "andere Taste erkannt (%s)" % tut.fb_reason)
	_check(int(tut.success) == 0, "andere Taste zaehlt nicht")
	_check(tut.core.is_judged(0), "Anti-Mash wie im Spiel: falsche Taste macht das Ziel zum Miss")
	tut.enter_step(2)
	n = tut.notes[0]
	_run_until(tut, func(): return tut.t_ms >= n.time_ms - 5.0)
	_move(tut, n.pos + Vector2(0.25, 0.0))
	_tap(tut, n.key)
	_check(str(tut.fb_reason) == "aim", "daneben erkannt (%s)" % tut.fb_reason)
	_move(tut, n.pos)
	_tap(tut, n.key)
	_check(int(tut.success) == 1, "danach richtig getroffen")
	var m: OrbitNote = tut.notes[1]
	_move(tut, m.pos)
	_run_until(tut, func(): return tut.t_ms >= m.spawn_ms + 50.0)
	_tap(tut, m.key)
	_check(str(tut.fb_reason) == "early", "zu frueh erkannt (%s)" % tut.fb_reason)
	_check(not tut.core.is_judged(1), "zu frueh frisst kein Ziel")
	var before := int(tut.fb_count)
	_run_until(tut, func(): return tut.core.is_judged(1))
	_check(str(tut.fb_reason) == "miss" and int(tut.fb_count) > before, "verpasst erkannt")
	_check(str(tut.reason_short("key")) != "" and str(tut.reason_hint("early", 0)) != "",
			"Gruende haben Texte")


func _test_accent_needs_both(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(3)
	var a: OrbitNote = tut.notes[0]
	var acc: OrbitNote = tut.notes[1]
	_check(acc.key == 2, "Akzent-Runde hat Akzent")
	_move(tut, a.pos)
	_run_until(tut, func(): return tut.t_ms >= a.time_ms)
	_tap(tut, a.key)
	_move(tut, acc.pos)
	_run_until(tut, func(): return tut.t_ms >= acc.time_ms)
	var before := int(tut.fb_count)
	_tap(tut, 0)
	_run_until(tut, func(): return int(tut.fb_count) > before)
	_check(int(tut.success) == 0, "Akzent: eine Taste reicht nicht")
	_check(str(tut.fb_reason) == "both", "Akzent: Grund beide Tasten (%s)" % tut.fb_reason)
	_run_until(tut, func(): return tut.notes.size() > 0 and not tut.core.is_judged(1) \
			and tut.notes[1] != acc)
	var b: OrbitNote = tut.notes[0]
	var acc2: OrbitNote = tut.notes[1]
	_move(tut, b.pos)
	_run_until(tut, func(): return tut.t_ms >= b.time_ms)
	_tap(tut, b.key)
	_move(tut, acc2.pos)
	_run_until(tut, func(): return tut.t_ms >= acc2.time_ms)
	_key(tut, 0, true)
	_key(tut, 1, true)
	_key(tut, 0, false)
	_key(tut, 1, false)
	_check(int(tut.success) == 1, "Akzent: beide Tasten zaehlen")


func _test_hold_release(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(4)
	var h: OrbitNote = tut.notes[0]
	_move(tut, h.pos)
	_run_until(tut, func(): return tut.t_ms >= h.time_ms)
	_key(tut, h.key, true)
	_check(tut.hold_active(0), "Halten laeuft nach dem Kopf")
	_run_until(tut, func():
		_move(tut, h.pos_at(tut.t_ms))
		return tut.t_ms >= (h.time_ms + h.end_ms) * 0.5)
	_key(tut, h.key, false)
	_check(str(tut.fb_reason) == "release", "zu frueh losgelassen erkannt (%s)" % tut.fb_reason)
	_check(int(tut.success) == 0, "losgelassenes Halten zaehlt nicht")


func _test_keys_from_settings(tut: Control) -> void:
	var old_a: int = _settings().orbit_key_inner
	var old_b: int = _settings().orbit_key_outer
	_settings().orbit_key_inner = KEY_K
	_settings().orbit_key_outer = KEY_L
	tut.enter_step(2)
	_check(str(tut.key_label(0)) == "K" and str(tut.key_label(1)) == "L", "Tasten-Namen aus den Settings")
	_check(str(tut.body_for(2)).contains("K") and str(tut.body_for(2)).contains("L"),
			"Text zeigt die echte Belegung")
	var n: OrbitNote = tut.notes[0]
	_move(tut, n.pos)
	_run_until(tut, func(): return tut.t_ms >= n.time_ms)
	_tap(tut, n.key)
	_check(int(tut.success) == 1, "Treffer mit umbelegter Taste")
	_settings().orbit_key_inner = old_a
	_settings().orbit_key_outer = old_b


func _test_skip(tut: Control) -> void:
	tut.enter_step(1)
	tut.skip_step()
	_check(int(tut.step) == 2, "Ueberspringen: naechster Schritt")
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	tut.handle_input(ev)
	_check(int(tut.step) == 3, "Tab ueberspringt")
	tut.enter_step(6)
	tut.skip_step()
	_check(bool(tut.finished), "Ueberspringen der Probe zeigt das Ergebnis")
