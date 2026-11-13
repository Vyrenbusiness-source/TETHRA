extends SceneTree

## Break-/Intro-Ring ueber dem Spielfeld (Mania 3D, Orbit): weg, bevor die erste Note
## nach dem Break ins Feld kommt (Live-QA, docs/qa/live_qa.md).
##   Godot --headless --audio-driver Dummy --path . --script res://tests/run_break_clear_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== TETHRA Break-Ring gibt das Feld frei ===")
	var ov: GDScript = load("res://scripts/ui/break_overlay.gd")
	var has := false
	for m in ov.get_script_method_list():
		has = has or str(m.name) == "clear_alpha"
	_check(has, "BreakOverlay.clear_alpha fehlt")
	if has:
		_check(is_equal_approx(ov.clear_alpha(17000.0, 14000.0), 1.0), "mitten im Break voll sichtbar")
		_check(is_equal_approx(ov.clear_alpha(17000.0, 16875.0), 0.5), "125 ms vor der Sichtbarkeit halb")
		_check(is_equal_approx(ov.clear_alpha(17000.0, 17000.0), 0.0), "Note sichtbar: Ring weg")
		_check(is_equal_approx(ov.clear_alpha(17000.0, 17700.0), 0.0), "Note im Anflug: Ring weg")
	# Beide Szenen mit Ring ueber dem Feld nutzen die Regel.
	var mania := FileAccess.get_file_as_string("res://scripts/gameplay3d/mania_3d.gd")
	_check(mania.count("BreakOverlay.clear_alpha(") >= 2, "Mania: 2D-Rueckfall und 3D blenden rechtzeitig aus")
	var orbit := FileAccess.get_file_as_string("res://scripts/orbit/orbit_game.gd")
	_check(orbit.count("BreakOverlay.clear_alpha(") >= 1, "Orbit blendet rechtzeitig aus")
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
