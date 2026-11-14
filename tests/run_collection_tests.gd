extends SceneTree

## Headless-Tests fuer Sammlungen: Speicher (scripts/library/collection_store.gd)
## und Sammlungs-Ansicht im Song-Browser (statische Helfer in scripts/song_select.gd).
## Laeuft nur gegen eine eigene Testdatei, nie gegen user://collections.cfg.

const TEST_PATH := "user://test_collections_run.cfg"
## Zur Laufzeit geladen: song_select.gd braucht Autoloads (GameSession), die
## beim Parsen eines --script noch fehlen.
var SongSelect: GDScript
var _done := false

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _mk(file: String, title: String, diffs: Array) -> MapSet:
	return MapSet.from_dict("C:/maps/" + file, {
		"title": title, "artist": "Artist", "creator": "Mapper", "diffs": diffs,
	})


func _d(version: String, stars: float, mode: int = 3) -> Dictionary:
	return { "version": version, "stars": stars, "mode": mode, "duration_ms": 120000.0,
		"osu_filename": version + ".osu" }


func _wipe() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	SongSelect = load("res://scripts/song_select.gd")
	CollectionStore.path_override = TEST_PATH
	_wipe()
	_check(CollectionStore.path() == TEST_PATH, "Tests schreiben in die Testdatei")
	_test_store()
	_test_safety()
	_test_view()
	_wipe()
	_test_modes()
	_wipe()
	CollectionStore.path_override = ""
	if _failed == 0:
		print("COLLECTION-TESTS OK")
	else:
		print("COLLECTION-TESTS FAILED: %d" % _failed)
	quit(0 if _failed == 0 else 1)


func _test_store() -> void:
	print("Speicher")
	_check(CollectionStore.list_names().is_empty(), "ohne Datei: keine Sammlungen")
	_check(CollectionStore.create("  Training "), "anlegen (Leerzeichen am Rand weg)")
	_check(not CollectionStore.create("Training"), "doppelter Name abgelehnt")
	_check(not CollectionStore.create("   "), "leerer Name abgelehnt")
	_check(CollectionStore.create("favoriten"), "zweite Sammlung")
	_check(CollectionStore.list_names() == ["favoriten", "Training"], "Namen sortiert, ohne Gross/Klein")
	_check(CollectionStore.toggle("Training", "C:/maps/1 a.osz"), "Map hinzufuegen")
	CollectionStore.toggle("Training", "2 b.osz")
	_check(CollectionStore.maps_in("Training") == ["1 a.osz", "2 b.osz"], "gespeichert wird nur der Dateiname")
	_check(CollectionStore.contains("Training", "D:/woanders/1 a.osz"), "enthalten, egal aus welchem Ordner")
	_check(CollectionStore.collections_of("1 a.osz") == ["Training"], "Sammlungen einer Map")
	_check(not CollectionStore.toggle("Training", "2 b.osz"), "Map entfernen")
	_check(CollectionStore.maps_in("Training") == ["1 a.osz"], "nach Entfernen")

	_check(CollectionStore.rename("Training", "Uebung"), "umbenennen")
	_check(CollectionStore.maps_in("Uebung") == ["1 a.osz"], "Maps bleiben beim Umbenennen")
	_check(not CollectionStore.exists("Training"), "alter Name weg")
	_check(not CollectionStore.rename("Uebung", "favoriten"), "umbenennen auf vorhandenen Namen abgelehnt")
	_check(not CollectionStore.rename("Uebung", "  "), "umbenennen auf leer abgelehnt")
	_check(not CollectionStore.rename("gibtsnicht", "x"), "umbenennen ohne Quelle abgelehnt")
	_check(CollectionStore.maps_in("Uebung") == ["1 a.osz"], "abgelehntes Umbenennen aendert nichts")

	CollectionStore.delete("Uebung")
	_check(CollectionStore.list_names() == ["favoriten"], "geloescht: nicht mehr in der Liste")
	_check(CollectionStore.deleted_names() == ["Uebung"], "geloescht: liegt im Papierkorb")
	_check(CollectionStore.restore("Uebung"), "wiederherstellen")
	_check(CollectionStore.maps_in("Uebung") == ["1 a.osz"], "wiederhergestellt mit allen Maps")
	_check(CollectionStore.deleted_names().is_empty(), "Papierkorb danach leer")
	_check(not CollectionStore.restore("Uebung"), "zweimal wiederherstellen geht nicht")

	# Loeschen, gleichnamig neu anlegen, zurueckholen: nichts geht verloren.
	CollectionStore.delete("Uebung")
	CollectionStore.create("Uebung")
	CollectionStore.toggle("Uebung", "9 z.osz")
	CollectionStore.restore("Uebung")
	var merged := CollectionStore.maps_in("Uebung")
	_check(merged.size() == 2 and merged.has("1 a.osz") and merged.has("9 z.osz"),
		"wiederherstellen vereint mit gleichnamiger neuer Sammlung")


func _test_safety() -> void:
	print("Datensicherheit")
	# Alle loeschen: Daten bleiben im Papierkorb und in der .bak.
	for n in CollectionStore.list_names():
		CollectionStore.delete(n)
	_check(CollectionStore.list_names().is_empty(), "alle geloescht")
	_check(CollectionStore.deleted_names().size() == 2, "alle im Papierkorb")
	var bak := ConfigFile.new()
	_check(bak.load(TEST_PATH + ".bak") == OK and bak.has_section("collections"),
		".bak haelt den letzten Stand mit Sammlungen")
	CollectionStore.create("leer")
	CollectionStore.delete("leer")
	CollectionStore.toggle("x", "1 a.osz")
	bak = ConfigFile.new()
	bak.load(TEST_PATH + ".bak")
	_check(bak.has_section("collections"), ".bak wird nie mit einem leeren Stand ueberschrieben")

	# Leere Datei (0 Byte, wie nach einem Datenverlust): lesbar, Anlegen geht.
	_wipe()
	FileAccess.open(TEST_PATH, FileAccess.WRITE).close()
	_check(CollectionStore.list_names().is_empty(), "0-Byte-Datei: keine Sammlungen, kein Fehler")
	_check(CollectionStore.create("Neu"), "0-Byte-Datei: anlegen geht")
	_check(CollectionStore.list_names() == ["Neu"], "0-Byte-Datei: danach gespeichert")

	# Kaputte Datei: niemals ueberschreiben.
	_wipe()
	var broken := "[collections]\nA=[\"1 a.osz\"\nkaputt ===\n"
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(broken)
	f.close()
	var probe := ConfigFile.new()
	if probe.load(TEST_PATH) != OK:
		_check(not CollectionStore.create("B"), "kaputte Datei: anlegen abgelehnt")
		CollectionStore.toggle("B", "1 a.osz")
		CollectionStore.delete("A")
		_check(FileAccess.get_file_as_string(TEST_PATH) == broken, "kaputte Datei bleibt unveraendert")
	else:
		_check(true, "Datei wurde als lesbar gewertet (Parser tolerant)")
	_wipe()


func _test_view() -> void:
	print("Sammlungs-Ansicht")
	var sets := [
		_mk("1 a.osz", "Ghost", [_d("Easy", 1.5), _d("Hard", 4.2)]),
		_mk("2 b.osz", "Blue Sky", [_d("Normal", 2.5)]),
		_mk("3 c.osz", "Std Only", [_d("Std", 3.0, 0)]),
		_mk("4 d.osz", "Apex", [_d("Insane", 6.4)]),
	]
	var files := ["1 a.osz", "3 c.osz", "4 d.osz", "77 weg.osz"]
	var v: Dictionary = SongSelect.collection_view(sets, files, "mania", "")
	_check((v.shown as Array).size() == 2, "Mania: alle spielbaren Maps der Sammlung, egal welche Sterne")
	_check(int(v.other_mode) == 1, "Mania: osu!standard-Map als 'anderer Modus' gezaehlt")
	_check(int(v.missing) == 1, "fehlende .osz gezaehlt")
	v = SongSelect.collection_view(sets, files, "orbit", "")
	_check((v.shown as Array).size() == 3 and int(v.other_mode) == 0, "Orbit: auch die osu!standard-Map")
	v = SongSelect.collection_view(sets, files, "mania", "ghost")
	_check((v.shown as Array).size() == 1 and int(v.search_hidden) == 1, "Suche grenzt ein und wird gezaehlt")
	v = SongSelect.collection_view(sets, [], "mania", "")
	_check((v.shown as Array).is_empty() and int(v.missing) == 0, "leere Sammlung")

	_check(SongSelect.collection_empty_reason("", {}) == "none", "Grund: keine Sammlung")
	_check(SongSelect.collection_empty_reason("A", SongSelect.collection_view(sets, [], "mania", "")) == "empty",
		"Grund: Sammlung leer")
	_check(SongSelect.collection_empty_reason("A", SongSelect.collection_view(sets, ["3 c.osz"], "mania", "")) == "other_mode",
		"Grund: nur in anderem Modus")
	_check(SongSelect.collection_empty_reason("A", SongSelect.collection_view(sets, ["1 a.osz"], "mania", "zzz")) == "search",
		"Grund: Suche ohne Treffer")
	_check(SongSelect.collection_empty_reason("A", SongSelect.collection_view(sets, ["77 weg.osz"], "mania", "")) == "missing",
		"Grund: Dateien fehlen")
	_check(SongSelect.collection_empty_reason("A", SongSelect.collection_view(sets, files, "mania", "")) == "",
		"Grund: keiner, wenn Maps da sind")


func _test_modes() -> void:
	print("Sammlungen je Modus")
	# Alte Datei ohne Modus-Section: alles bleibt, alles gilt in allen Modi.
	var old := ConfigFile.new()
	old.set_value("collections", "Alt", ["1 a.osz", "3 c.osz"])
	old.set_value("collections", "Zweite", ["2 b.osz"])
	old.save(TEST_PATH)
	var before := FileAccess.get_file_as_bytes(TEST_PATH)
	_check(CollectionStore.mode_of("Alt") == CollectionStore.MODE_ALL, "alte Sammlung = alle Modi")
	for m in CollectionStore.MODES:
		_check(CollectionStore.list_for(m) == ["Alt", "Zweite"], "alte Sammlungen in %s sichtbar" % m)
	_check(FileAccess.get_file_as_bytes(TEST_PATH) == before, "Lesen schreibt die alte Datei nicht um")
	# Neue Sammlung mit Modus.
	_check(CollectionStore.create("Orbit-Liste", "orbit"), "Sammlung mit Modus anlegen")
	_check(FileAccess.get_file_as_bytes(TEST_PATH + ".bak") == before, ".bak haelt den Stand vor der Aenderung")
	_check(CollectionStore.maps_in("Alt") == ["1 a.osz", "3 c.osz"], "Maps der alten Sammlung unveraendert")
	_check(CollectionStore.mode_of("Orbit-Liste") == "orbit", "Modus gespeichert")
	_check(CollectionStore.list_for("orbit") == ["Alt", "Orbit-Liste", "Zweite"], "Orbit: eigene + alle Modi")
	_check(CollectionStore.list_for("mania") == ["Alt", "Zweite"], "Mania: Orbit-Sammlung nicht in der Liste")
	_check(CollectionStore.list_names().size() == 3, "list_names kennt weiter alle")
	_check(CollectionStore.create("Frei") and CollectionStore.mode_of("Frei") == "", "ohne Angabe = alle Modi")
	_check(CollectionStore.create("Kaputt", "tennis") and CollectionStore.mode_of("Kaputt") == "", "unbekannter Modus = alle Modi")
	# Modus aendern, umbenennen, loeschen, zurueckholen.
	_check(CollectionStore.set_mode("Alt", "rally") and CollectionStore.mode_of("Alt") == "rally", "Modus aendern")
	_check(CollectionStore.maps_in("Alt") == ["1 a.osz", "3 c.osz"], "Modus aendern laesst die Maps")
	_check(CollectionStore.set_mode("Alt", "") and CollectionStore.mode_of("Alt") == "", "zurueck auf alle Modi")
	_check(not CollectionStore.set_mode("Gibt es nicht", "orbit"), "Modus nur fuer vorhandene Sammlung")
	_check(CollectionStore.rename("Orbit-Liste", "Orbit 2") and CollectionStore.mode_of("Orbit 2") == "orbit"
		and CollectionStore.mode_of("Orbit-Liste") == "", "Umbenennen nimmt den Modus mit")
	CollectionStore.toggle("Orbit 2", "3 c.osz")
	CollectionStore.delete("Orbit 2")
	_check(not CollectionStore.list_for("orbit").has("Orbit 2"), "geloescht: nicht mehr in der Liste")
	_check(CollectionStore.restore("Orbit 2") and CollectionStore.mode_of("Orbit 2") == "orbit"
		and CollectionStore.maps_in("Orbit 2") == ["3 c.osz"], "Zurueckholen bringt Modus und Maps")
	# Ansicht: im Modus nicht spielbare Maps werden gezeigt, aber markiert.
	var sets := [
		_mk("1 a.osz", "Ghost", [_d("Easy", 1.5)]),
		_mk("3 c.osz", "Std Only", [_d("Std", 3.0, 0)]),
	]
	var v: Dictionary = SongSelect.collection_view(sets, ["1 a.osz", "3 c.osz"], "mania", "")
	_check((v.unplayable as Array).size() == 1 and (v.unplayable[0] as MapSet).title == "Std Only",
		"Mania: osu!standard-Map als nicht spielbar gelistet")
	v = SongSelect.collection_view(sets, ["1 a.osz", "3 c.osz"], "mania", "ghost")
	_check((v.unplayable as Array).is_empty(), "Suche gilt auch fuer nicht spielbare Maps")
	v = SongSelect.collection_view(sets, ["1 a.osz", "3 c.osz"], "orbit", "")
	_check((v.unplayable as Array).is_empty(), "Orbit: alles spielbar")
	_check(SongSelect.collection_mode_hint("orbit") != "" and SongSelect.collection_mode_hint("") != ""
		and SongSelect.collection_mode_hint("orbit") != SongSelect.collection_mode_hint(""),
		"Modus-Hinweis fuer Modus und alle Modi")
