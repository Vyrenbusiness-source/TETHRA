extends SceneTree

## Tests fuer den Updater: Semver, Groessenpruefung, Szenen-Erkennung, Notes.
## Start: Godot --headless --path . --script tests/run_updater_tests.gd

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		print("FAIL ", what)
		_fails += 1


func _init() -> void:
	var U: GDScript = load("res://scripts/net/updater.gd")
	var u: Node = U.new()
	# Semver
	_check(u._is_newer("1.6.2", "1.6.1"), "1.6.2 > 1.6.1")
	_check(not u._is_newer("1.6.1", "1.6.1"), "gleich ist nicht neuer")
	_check(not u._is_newer("1.6.0", "1.6.1"), "1.6.0 nicht neuer")
	_check(u._is_newer("1.10.0", "1.9.9"), "1.10.0 > 1.9.9 (numerisch)")
	_check(u._is_newer("2.0", "1.9.9"), "2.0 > 1.9.9 (kurze Version)")
	_check(not u._is_newer("1.6", "1.6.0"), "1.6 == 1.6.0")
	_check(u._is_newer("1.6.1.1", "1.6.1"), "4. Segment zaehlt")
	# Groesse
	_check(U.size_ok(1000, 1000), "Groesse gleich")
	_check(not U.size_ok(999, 1000), "Groesse zu klein")
	_check(not U.size_ok(1001, 1000), "Groesse zu gross")
	_check(U.size_ok(500, 0), "Soll unbekannt -> ok")
	_check(not U.size_ok(-1, 0), "Datei fehlt -> nicht ok")
	# Szenen
	_check(U.is_gameplay_scene("res://scenes/mania_3d.tscn"), "mania_3d = Gameplay")
	_check(U.is_gameplay_scene("res://scenes/gameplay_3d.tscn"), "gameplay_3d = Gameplay")
	_check(not U.is_gameplay_scene("res://scenes/main_menu.tscn"), "Hauptmenue kein Gameplay")
	_check(not U.is_gameplay_scene("res://scenes/song_select.tscn"), "Songauswahl kein Gameplay")
	_check(not U.is_gameplay_scene(""), "leerer Pfad kein Gameplay")
	# Notes
	var body := "## Neu\n\n- a\n- b\n- c\n- d\n- e\n- f\n- g\n- h"
	var n: String = U.trim_notes(body)
	_check(n.split("\n").size() == 6, "Notes auf 6 Zeilen gekuerzt")
	_check(n.begins_with("Neu\n• a"), "Notes: Markdown bereinigt")
	_check(U.trim_notes("") == "", "leere Notes")
	# Backoff
	_check(U.backoff_for(0) == 15.0 and U.backoff_for(1) == 30.0, "Backoff verdoppelt")
	_check(U.backoff_for(20) == 240.0, "Backoff gedeckelt")
	u.free()
	quit(1 if _fails > 0 else 0)
