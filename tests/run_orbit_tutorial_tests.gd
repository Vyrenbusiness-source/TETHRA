extends SceneTree

## Headless-Tests fuer das Orbit-Tutorial (Task orbit-tutorial): jeder der
## sechs Schritte ist mit simulierten Eingaben (Maus-/Tasten-Events) loesbar,
## Tasten kommen aus den Settings, Ueberspringen, Gesehen-Merker.
## Das Tutorial nutzt das Autoload Settings, darum nur per load() (keine
## statischen Verweise, siehe run_mania_settings_tests.gd).
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
	print("=== TETHRA Orbit-Tutorial-Tests ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/orbit_tutorial_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_test_bot_run(tut)
	_test_patterns(S)
	_test_keys_from_settings(tut)
	_test_arc_needs_hold(tut)
	_test_skip(tut)
	tut.queue_free()
	DirAccess.remove_absolute(S.seen_path)
	S.seen_path = old_seen
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bis cond wahr ist simulieren (max. limit Frames); true, wenn erreicht.
func _run_until(tut: Control, cond: Callable, limit: int = 4000) -> bool:
	for i in limit:
		if cond.call():
			return true
		tut.advance(FRAME)
	return cond.call()


func _test_bot_run(tut: Control) -> void:
	tut.bot = true
	tut.enter_step(0)
	for s in 5:
		_check(int(tut.step) == s, "Schritt %d aktiv" % (s + 1))
		var best := [0]
		var reached := _run_until(tut, func():
			best[0] = maxi(best[0], int(tut.success))
			return int(tut.step) != s)
		_check(reached and int(tut.step) == s + 1, "Schritt %d per Bot geloest" % (s + 1))
		_check(best[0] >= 3, "Schritt %d: 3x geschafft vor dem Weiter (%d)" % [s + 1, best[0]])
	_check(int(tut.step) == 5, "Probe-Runde erreicht")
	var ok := _run_until(tut, func(): return bool(tut.finished))
	_check(ok, "Probe-Runde endet mit Wertung")
	var total := 0
	for c in tut.tiers:
		total += int(c)
	_check(total == tut.TRIAL_PATTERN.size(), "alle Probe-Ziele gewertet (%d)" % total)
	_check(int(tut.tiers[5]) == 0, "Bot ohne Fehltreffer")
	_check(float(tut.trial_accuracy()) > 0.9, "Bot-Genauigkeit > 90 %% (%.3f)" % tut.trial_accuracy())
	_check(str(tut.trial_grade()) in ["SS", "S", "A"], "Rang aus der Wertung (%s)" % tut.trial_grade())
	tut.bot = false
	tut._retry_trial()
	_check(not bool(tut.finished) and int(tut.step) == 5, "Nochmal startet die Probe-Runde neu")


func _test_patterns(S: GDScript) -> void:
	for s in range(1, 6):
		var ns: Array = S.pattern(s, 10, 0)
		_check(ns.size() >= 3, "Schritt %d: Muster mit genug Zielen" % (s + 1))
		var on_beat := true
		for n in ns:
			var b: float = n.time_ms / S.BEAT_MS
			on_beat = on_beat and absf(b - roundf(b)) < 0.001
		_check(on_beat, "Schritt %d: Ziele auf dem Takt" % (s + 1))
	var inner: Array = S.pattern(1, 10, 0)
	var outer: Array = S.pattern(2, 10, 0)
	_check(inner.all(func(n): return n.ring == 0), "Innerer Ring: nur Ring 0")
	_check(outer.all(func(n): return n.ring == 1), "Aeusserer Ring: nur Ring 1")
	var chord: Array = S.pattern(3, 10, 0)
	_check(chord[0].time_ms == chord[1].time_ms and chord[0].angle_deg == chord[1].angle_deg
		and chord[0].ring != chord[1].ring, "Akkord: gleiche Zeit, gleicher Winkel, beide Ringe")
	var arcs: Array = S.pattern(4, 10, 0)
	_check(arcs.all(func(n): return n.is_arc and n.duration_ms() > 0.0), "Bogen-Schritt: nur Boegen")
	var trial: Array = S.pattern(5, 10, 0)
	var kinds := {"inner": false, "outer": false, "arc": false}
	for n in trial:
		kinds["arc"] = kinds["arc"] or n.is_arc
		kinds["inner"] = kinds["inner"] or (n.ring == 0 and not n.is_arc)
		kinds["outer"] = kinds["outer"] or n.ring == 1
	_check(kinds.values().all(func(v): return v), "Probe-Runde mischt innen, aussen, Bogen")


func _key(tut: Control, code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = down
	tut.handle_input(ev)


func _aim(tut: Control, deg: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = OrbitView.polar(tut.view_center_global(), deg, 200.0)
	tut.handle_input(ev)


func _test_keys_from_settings(tut: Control) -> void:
	var st: Node = root.get_node("/root/Settings")
	var old_in: int = st.orbit_key_inner
	st.orbit_key_inner = KEY_Q
	tut.bot = false
	tut.enter_step(1)
	_check(str(tut._body_lbl.text).contains("Q"), "Text nennt die Taste aus den Settings")
	var n = tut.notes[0]
	_run_until(tut, func(): return tut.t_ms >= n.time_ms - FRAME * 0.5)
	_aim(tut, n.angle_deg)
	_key(tut, KEY_Z, true)
	_key(tut, KEY_Z, false)
	_check(int(tut.success) == 0, "alte Taste Z zaehlt nicht mehr")
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "Taste Q aus den Settings trifft")
	# Daneben gezielt: naechstes Ziel, Zeiger 90 Grad weg.
	var n2 = tut.notes[1]
	_run_until(tut, func(): return tut.t_ms >= n2.time_ms - FRAME * 0.5)
	_aim(tut, n2.angle_deg + 90.0)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "daneben gezielt zaehlt nicht")
	# Maus links = innen, immer.
	var n3 = tut.notes[2]
	_run_until(tut, func(): return tut.t_ms >= n3.time_ms - FRAME * 0.5)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = OrbitView.polar(tut.view_center_global(), n3.angle_deg, 200.0)
	mb.pressed = true
	tut.handle_input(mb)
	var mb_up: InputEventMouseButton = mb.duplicate()
	mb_up.pressed = false
	tut.handle_input(mb_up)
	_check(int(tut.success) == 2, "Maus links trifft den inneren Ring")
	st.orbit_key_inner = old_in


func _test_arc_needs_hold(tut: Control) -> void:
	tut.enter_step(4)
	var n = tut.notes[0]
	_run_until(tut, func(): return tut.t_ms >= n.time_ms - FRAME * 0.5)
	_aim(tut, n.angle_deg)
	var k: int = root.get_node("/root/Settings").orbit_key_inner
	_key(tut, k, true)
	tut.advance(FRAME * 3.0)
	_key(tut, k, false)
	_run_until(tut, func(): return tut.t_ms > n.end_ms + 400.0)
	_check(int(tut.success) == 0, "Bogen kurz antippen zaehlt nicht")
	_check(str(tut._feedback.text) != "", "Hinweis nach verlorenem Bogen")


func _test_skip(tut: Control) -> void:
	tut.enter_step(2)
	_key(tut, KEY_TAB, true)
	_check(int(tut.step) == 3, "Tab ueberspringt den Schritt")
	tut.skip_step()
	tut.skip_step()
	_check(int(tut.step) == 5, "Ueberspringen bis zur Probe-Runde")
	tut.skip_step()
	_check(bool(tut.finished), "Probe-Runde ueberspringen zeigt die Wertung")
