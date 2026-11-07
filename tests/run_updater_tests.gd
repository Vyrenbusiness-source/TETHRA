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
	# Welten-Paket: Signatur, Range, Platz, Batch
	_check(U.asset_sig({"digest": "sha256:ab", "size": 5}) == "sha256:ab", "Signatur = Digest")
	_check(U.asset_sig({"size": 5, "updated_at": "t"}) == "5@t", "Signatur ohne Digest = Groesse@Zeit")
	_check(U.worlds_needs_update(false, "x", "x"), "Welten-pck fehlt -> laden")
	_check(U.worlds_needs_update(true, "a", "b"), "Signatur anders -> laden")
	_check(not U.worlds_needs_update(true, "a", "a"), "unveraendert -> nicht laden")
	_check(U.range_header(0, 100, 1000) == "Range: bytes=0-99", "Range erstes Stueck")
	_check(U.range_header(900, 100, 950) == "Range: bytes=900-949", "Range letztes Stueck gedeckelt")
	_check(U.range_header(100, 100, 0) == "Range: bytes=100-199", "Range ohne Gesamtgroesse")
	_check(U.space_ok(-1, 1 << 40), "Platz unbekannt -> ok")
	_check(U.space_ok(1000 * 1048576, 900 * 1048576), "genug Platz")
	_check(not U.space_ok(900 * 1048576, 900 * 1048576), "Reserve fehlt -> zu wenig Platz")
	var bat: String = U.build_bat("C:/g/TETHRA.exe", "C:/g", ["TETHRA.pck", "TETHRA_worlds.pck"])
	_check(bat.contains("move /y") and bat.contains("TETHRA.pck.new")
			and bat.contains("TETHRA_worlds.pck.new") and bat.contains(":retry1"), "Batch tauscht beide Pakete")
	_check(bat.find("TETHRA_worlds.pck.new") < bat.find("start \"\""), "Batch startet erst nach dem Tausch")
	var bat2: String = U.build_bat("C:/g/TETHRA.exe", "C:/g", ["TETHRA.pck"], 4242,
			PackedStringArray(["--rendering-driver", "opengl3", "x&y"]))
	_check(bat2.contains("PID eq 4242") and bat2.find("PID eq 4242") < bat2.find("move /y"),
			"Batch wartet auf das Ende des Spielprozesses vor dem Tausch")
	_check(bat2.contains("if not exist \"C:\\g\\TETHRA.pck.new\" goto done0"), "Erfolg per if exist")
	_check(not bat2.contains("timeout /t"), "keine timeout-Pause (ohne Konsole kaputt)")
	_check(bat2.contains("\"--rendering-driver\" \"opengl3\"") and not bat2.contains("x&y"),
			"Startargumente weitergegeben, gefaehrliche verworfen")
	_check(U.apply_blocked(2, "1.0.0", "1.0.0") and not U.apply_blocked(1, "1.0.0", "1.0.0")
			and not U.apply_blocked(5, "0.9.0", "1.0.0"), "Schleifen-Bremse nach 2 Versuchen derselben Version")
	# WorldPack ohne Datei
	var W: GDScript = load("res://scripts/net/world_pack.gd")
	_check(not W.is_valid_file("res://nicht_da.pck"), "WorldPack: fehlende Datei ungueltig")
	_check(not W.mount(), "WorldPack: fehlt -> kein Mount, kein Fehler")
	u.free()
	quit(1 if _fails > 0 else 0)
