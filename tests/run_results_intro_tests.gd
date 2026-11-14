extends SceneTree

## Ergebnisbild: Intro-Animation darf nach einem sofortigen Szenenwechsel (Retry/Replay
## im ersten Bild) nicht auf get_tree() == null laufen (Live-QA, docs/qa/live_qa.md).
##   Godot --headless --audio-driver Dummy --path . --script res://tests/run_results_intro_tests.gd

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
	print("=== OMEN Ergebnisbild-Intro-Tests ===")
	var rs: Control = load("res://scripts/ui/results_screen.gd").new()
	_check(rs.has_method("_two_frames"), "ResultsScreen._two_frames fehlt")
	if rs.has_method("_two_frames"):
		# Nicht im Baum: sofort false, kein Zugriff auf get_tree().
		_check(not await rs.call("_two_frames"), "ausserhalb des Baums: false")
		root.add_child(rs)
		_check(await rs.call("_two_frames"), "im Baum: true nach zwei Bildern")
		# Im ersten Bild aus dem Baum genommen (Retry): false statt Skriptfehler.
		var st := {"done": false, "ok": true}
		var co := func() -> void:
			st.ok = await rs.call("_two_frames")
			st.done = true
		co.call()
		root.remove_child(rs)
		for i in 4:
			await process_frame
		_check(st.done and not st.ok, "im ersten Bild entfernt: false")
	var src := FileAccess.get_file_as_string("res://scripts/ui/results_screen.gd")
	_check(src.count("await get_tree().process_frame") == 1, "nur _two_frames wartet mit await get_tree().process_frame")
	rs.free()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
