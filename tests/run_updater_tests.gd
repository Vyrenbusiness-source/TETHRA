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
	# Ausweich-Quelle dist/latest.json
	var sha := "a".repeat(64)
	var dj: Dictionary = U.dist_job({"version": "1.2.3", "size": 30, "sha256": sha,
		"parts": [{"name": "TETHRA.pck.000", "size": 20}, {"name": "TETHRA.pck.001", "size": 10}]}, "https://x/", "C:/g", "TETHRA.pck")
	_check(dj.get("urls", []) == ["https://x/TETHRA.pck.000", "https://x/TETHRA.pck.001"] and int(dj.size) == 30 			and str(dj.sig) == "sha256:" + sha and str(dj.new).ends_with("TETHRA.pck.new"), "dist: Auftrag aus latest.json")
	_check(U.dist_job({"version": "1", "size": 31, "sha256": sha, "parts": [{"name": "a", "size": 30}]}, "b/", "c", "OMEN.pck").is_empty(),
		"dist: Teilsumme falsch -> verworfen")
	_check(U.dist_job({"version": "1", "size": 30, "sha256": "x", "parts": [{"name": "a", "size": 30}]}, "b/", "c", "OMEN.pck").is_empty(),
		"dist: ohne SHA-256 -> verworfen")
	_check(U.dist_part_at([20, 10], 0) == 0 and U.dist_part_at([20, 10], 20) == 1 and U.dist_part_at([20, 10], 7) == -1,
		"dist: Fortsetzen nur an Teilgrenzen")
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
	_check(bat2.contains("if not exist \"TETHRA.pck.new\" goto done0"), "Erfolg per if exist")
	var bat3: String = U.build_bat("C:/Users/Jörg Müller/AppData/Local/Programs/TETHRA/TETHRA.exe",
			"C:/Users/Jörg Müller/AppData/Local/Programs/TETHRA", ["TETHRA.pck"])
	_check(not bat3.contains("Jörg") and bat3.contains("cd /d \"%~dp0\"") and bat3.contains("\"%~dp0TETHRA.exe\""),
			"Batch ohne ausgeschriebene Pfade (Umlaute im Benutzernamen)")
	_check(not bat2.contains("timeout /t"), "keine timeout-Pause (ohne Konsole kaputt)")
	_check(bat2.contains("\"--rendering-driver\" \"opengl3\"") and not bat2.contains("x&y"),
			"Startargumente weitergegeben, gefaehrliche verworfen")
	_check(U.apply_blocked(2, "1.0.0", "1.0.0") and not U.apply_blocked(1, "1.0.0", "1.0.0")
			and not U.apply_blocked(5, "0.9.0", "1.0.0"), "Schleifen-Bremse nach 2 Versuchen derselben Version")
	var tmpf := "user://test_tmp/same.bin"
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var ff := FileAccess.open(tmpf, FileAccess.WRITE)
	ff.store_string("OMEN")
	ff.close()
	var hx := FileAccess.get_sha256(tmpf)
	_check(U.same_as_local("sha256:" + hx, tmpf) and not U.same_as_local("sha256:00", tmpf)
			and not U.same_as_local("", tmpf), "Digest-Vergleich gegen lokale Datei (kein Endlos-Update)")
	DirAccess.remove_absolute(tmpf)
	_rename_checks(U)
	# WorldPack ohne Datei
	var W: GDScript = load("res://scripts/net/world_pack.gd")
	_check(not W.is_valid_file("res://nicht_da.pck"), "WorldPack: fehlende Datei ungueltig")
	_check(not W.mount(), "WorldPack: fehlt -> kein Mount, kein Fehler")
	u.free()
	quit(1 if _fails > 0 else 0)


## Umbenennung TETHRA -> OMEN: bestehende Installationen (TETHRA.exe + TETHRA.pck)
## aktualisieren sich weiter, neue heissen OMEN.exe + OMEN.pck.
func _rename_checks(U: GDScript) -> void:
	_check(U.REPO == "Vyrenbusiness-source/OMEN" and U.UA == "User-Agent: OMEN-Updater", "Repo und User-Agent heissen OMEN")
	# Paketname = Name der laufenden Exe
	_check(U.main_pack_name("C:/g/TETHRA.exe") == "TETHRA.pck", "TETHRA.exe -> TETHRA.pck")
	_check(U.main_pack_name("C:/g/OMEN.exe") == "OMEN.pck", "OMEN.exe -> OMEN.pck")
	_check(U.main_pack_name("C:/Spiele/v1.2/OMEN.exe") == "OMEN.pck", "Punkt im Ordnernamen stoert nicht")
	# Asset-Auswahl: neuer Name zuerst, alter als Ausweich
	var a_old := {"name": "TETHRA.pck", "browser_download_url": "https://x/TETHRA.pck", "size": 5, "id": 1, "digest": "sha256:aa"}
	var a_new := {"name": "OMEN.pck", "browser_download_url": "https://x/OMEN.pck", "size": 5, "id": 2, "digest": "sha256:aa"}
	var a_other := {"name": "OMEN_Setup.exe", "browser_download_url": "https://x/s", "size": 9, "id": 3}
	_check(str(U.pick_asset([a_old, a_other, a_new], U.MAIN_ASSETS).name) == "OMEN.pck", "Asset: OMEN.pck hat Vorrang (Reihenfolge egal)")
	_check(str(U.pick_asset([a_other, a_old], U.MAIN_ASSETS).name) == "TETHRA.pck", "Asset: sonst TETHRA.pck")
	_check(U.pick_asset([a_other], U.MAIN_ASSETS).is_empty() and U.pick_asset([], U.MAIN_ASSETS).is_empty(), "Asset: keins da -> leer")
	var w_old := {"name": "TETHRA_worlds.pck", "browser_download_url": "https://x/w1", "size": 7, "id": 4}
	var w_new := {"name": "OMEN_worlds.pck", "browser_download_url": "https://x/w2", "size": 7, "id": 5}
	_check(str(U.pick_asset([w_old, a_old], U.WORLDS_ASSETS).name) == "TETHRA_worlds.pck"
			and str(U.pick_asset([w_old, w_new], U.WORLDS_ASSETS).name) == "OMEN_worlds.pck", "Welten-Asset: beide Namen, OMEN zuerst")
	# Alte Installation: Asset OMEN.pck wird als TETHRA.pck neben TETHRA.exe abgelegt.
	var j: Dictionary = U.asset_job([a_old, a_new], U.MAIN_ASSETS, "C:/g", U.main_pack_name("C:/g/TETHRA.exe"))
	_check(str(j.url) == "https://x/OMEN.pck" and str(j.final) == "C:/g/TETHRA.pck" and str(j.new) == "C:/g/TETHRA.pck.new"
			and str(j.asset) == "TETHRA.pck", "alte Installation: laedt OMEN.pck, ersetzt TETHRA.pck")
	var j2: Dictionary = U.asset_job([a_old], U.MAIN_ASSETS, "C:/g", U.main_pack_name("C:/g/OMEN.exe"))
	_check(str(j2.url) == "https://x/TETHRA.pck" and str(j2.final) == "C:/g/OMEN.pck", "neue Installation: Release nur mit TETHRA.pck -> ersetzt OMEN.pck")
	_check(U.asset_job([a_other], U.MAIN_ASSETS, "C:/g", "OMEN.pck").is_empty(), "kein Paket im Release -> kein Auftrag")
	# dist: Teilnamen kommen aus latest.json, Ziel ist das Paket der Exe
	var sha := "b".repeat(64)
	var d := {"version": "1.36.0", "size": 30, "sha256": sha,
		"parts": [{"name": "TETHRA.pck.000", "size": 20}, {"name": "TETHRA.pck.001", "size": 10}]}
	var dn: Dictionary = U.dist_job(d, "https://x/", "C:/g", "OMEN.pck")
	_check(dn.get("urls", []) == ["https://x/TETHRA.pck.000", "https://x/TETHRA.pck.001"]
			and str(dn.final) == "C:/g/OMEN.pck" and str(dn.asset) == "OMEN.pck", "dist: alte Teilnamen, Ziel OMEN.pck")
	var d2 := d.duplicate(true)
	d2["parts"] = [{"name": "OMEN.pck.000", "size": 30}]
	_check(U.dist_job(d2, "https://x/", "C:/g", "TETHRA.pck").get("urls", []) == ["https://x/OMEN.pck.000"],
			"dist: Teilnamen frei waehlbar (aus latest.json)")
	_check(str(U.DIST_BASES[0]) == "https://raw.githubusercontent.com/Vyrenbusiness-source/OMEN/dist/"
			and str(U.DIST_BASES[1]) == "https://cdn.jsdelivr.net/gh/Vyrenbusiness-source/OMEN@dist/", "dist-URLs auf dem neuen Repo")
	# Batch: startet die Exe, die laeuft; nie umbenennen
	var bo: String = U.build_bat("C:/g/OMEN.exe", "C:/g", ["OMEN.pck", "OMEN_worlds.pck"])
	_check(bo.contains("move /y \"OMEN.pck.new\" \"OMEN.pck\"") and bo.contains("\"%~dp0OMEN.exe\"")
			and not bo.contains("TETHRA"), "Batch neue Installation: nur OMEN-Dateien")
	var bt: String = U.build_bat("C:/g/TETHRA.exe", "C:/g", ["TETHRA.pck"])
	_check(bt.contains("move /y \"TETHRA.pck.new\" \"TETHRA.pck\"") and bt.contains("\"%~dp0TETHRA.exe\"")
			and not bt.contains("OMEN"), "Batch alte Installation: TETHRA.exe bleibt, keine Umbenennung")
	# Nutzerdaten bleiben am alten Ort (Scores, Replays, Einstellungen, Login).
	_check(str(ProjectSettings.get_setting("application/config/name")) == "OMEN", "Projektname OMEN")
	_check(OS.get_user_data_dir().replace("\\", "/").ends_with("/Godot/app_userdata/TETHRA"),
			"user:// zeigt weiter auf Godot/app_userdata/TETHRA ('%s')" % OS.get_user_data_dir())
	# Clip-Ordner: vorhandener alter Ordner bleibt, sonst neuer Name
	var CE: GDScript = load("res://scripts/replay/clip_exporter.gd")
	var docs := OS.get_temp_dir().path_join("omen_clipdir_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(docs)
	_check(CE.clips_dir_in(docs) == docs.path_join("OMEN Clips"), "Clips: neu -> OMEN Clips")
	DirAccess.make_dir_recursive_absolute(docs.path_join("TETHRA Clips"))
	_check(CE.clips_dir_in(docs) == docs.path_join("TETHRA Clips"), "Clips: alter Ordner wird weiterverwendet")
	DirAccess.remove_absolute(docs.path_join("TETHRA Clips"))
	DirAccess.remove_absolute(docs)
	# Welten-Paket lokal: beide Namen
	var W: GDScript = load("res://scripts/net/world_pack.gd")
	var dir := OS.get_temp_dir().path_join("omen_worldpack_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	_check(W.local_name(dir) == "OMEN_worlds.pck", "Welten lokal: nichts da -> neuer Name")
	_touch(dir.path_join("TETHRA_worlds.pck"))
	_check(W.local_name(dir) == "TETHRA_worlds.pck", "Welten lokal: altes Paket wird weiterverwendet")
	_check(W.is_valid_file(dir.path_join(W.local_name(dir))), "Welten lokal: altes Paket gilt als gueltig")
	_touch(dir.path_join("OMEN_worlds.pck"))
	_check(W.local_name(dir) == "OMEN_worlds.pck", "Welten lokal: beide da -> neuer Name")
	for n in ["TETHRA_worlds.pck", "OMEN_worlds.pck"]:
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)


func _touch(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("GDPC")
	f.store_buffer(PackedByteArray([0]).duplicate())
	var pad := PackedByteArray()
	pad.resize(2048)
	f.store_buffer(pad)
	f.close()
