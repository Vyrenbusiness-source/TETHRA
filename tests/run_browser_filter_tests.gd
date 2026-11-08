extends SceneTree

## Headless-Tests fuer die Song-Browser-Filter (Task browser-filters): Score-Index
## je Modus aus einer Fake-scores.cfg in user://test_tmp, Bestwert-/Noten-Filter,
## Sortierungen (zuletzt gespielt, heruntergeladen, meistgespielt) und das
## Speichern/Pruefen des Modus-Filters.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_browser_filter_tests.gd

## Zur Laufzeit geladen: song_select.gd braucht Autoloads (GameSession), die
## beim Parsen eines --script noch fehlen.
var SS: GDScript
const TMP := "user://test_tmp/browser_filter_scores.cfg"

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== TETHRA Browser-Filter-Tests ===")
	SS = load("res://scripts/song_select.gd")
	if SS == null or not SS.can_instantiate():
		print("  FAIL: song_select.gd laedt nicht")
		quit(1)
		return
	_test_index()
	_test_best_filter()
	_test_sort()
	_test_mode_filter()
	_test_mtime()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Fake-Scores: Mania und Orbit in getrennten Sektionen (ScoreStore._sec).
func _fake_cfg() -> ConfigFile:
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "1 A.osz|Easy", {"grade": "A", "date": "2026-11-01T10:00:00"})
	cfg.set_value("scores", "1 A.osz|Hard", {"grade": "SS", "date": "2026-11-02T10:00:00"})
	cfg.set_value("scores", "2 B.osz|Normal", {"grade": "F", "date": "2026-10-01T10:00:00"})
	cfg.set_value("plays", "1 A.osz|Easy", 3)
	cfg.set_value("plays", "1 A.osz|Hard", 1)
	cfg.set_value("plays", "2 B.osz|Normal", 7)
	cfg.set_value("plays", "3 C.osz|X", 2)
	cfg.set_value("history", "3 C.osz|X", [
		{"date": "2026-11-05T09:00:00", "failed": true},
		{"date": "2026-11-06T09:00:00", "failed": true}])
	cfg.set_value("recent", "plays", [
		{"osz_file": "2 B.osz", "version": "Normal", "date": "2026-11-07T12:00:00"}])
	cfg.set_value("orbit_scores", "2 B.osz|Normal", {"grade": "S", "date": "2026-09-01T10:00:00"})
	cfg.set_value("orbit_plays", "2 B.osz|Normal", 1)
	cfg.save(TMP)
	var back := ConfigFile.new()
	back.load(TMP)
	return back


func _test_index() -> void:
	var cfg := _fake_cfg()
	var mania: Dictionary = SS.build_score_index(cfg, "")
	var orbit: Dictionary = SS.build_score_index(cfg, "orbit")
	_ok(mania.size() == 3, "Mania-Index hat 3 Sets (%d)" % mania.size())
	_ok(SS.set_best_grade(mania["1 A.osz"], ["Easy", "Hard"]) == "SS", "beste Note ueber Diffs = SS")
	_ok(SS.set_best_grade(mania["1 A.osz"], ["Easy"]) == "A", "nur sichtbare Diffs zaehlen")
	_ok(SS.set_best_grade(mania["2 B.osz"], ["Normal"]) == "D", "F zaehlt als D")
	_ok(SS.set_best_grade(mania["3 C.osz"], ["X"]) == "", "nur Fails: kein Bestwert")
	_ok(SS.set_plays(mania["1 A.osz"], ["Easy", "Hard"]) == 4, "Plays summiert")
	_ok(SS.set_last_played(mania["3 C.osz"], ["X"]) == "2026-11-06T09:00:00", "letzter Play aus History")
	_ok(SS.set_last_played(mania["2 B.osz"], ["Normal"]) == "2026-11-07T12:00:00", "letzter Play aus Recent")
	_ok(orbit.size() == 1 and orbit.has("2 B.osz"), "Orbit-Index getrennt von Mania")
	_ok(SS.set_best_grade(orbit["2 B.osz"], ["Normal"]) == "S", "Orbit-Note aus orbit_scores")
	_ok(SS.set_plays(orbit["2 B.osz"], ["Normal"]) == 1, "Orbit-Plays getrennt")
	_ok(SS.build_score_index(ConfigFile.new(), "").is_empty(), "leere cfg -> leerer Index")


func _test_best_filter() -> void:
	_ok(SS.grade_bucket("SSH") == "SS" and SS.grade_bucket("SH") == "S", "Hidden-Noten gebuendelt")
	_ok(SS.grade_bucket("X") == "SS" and SS.grade_bucket("") == "", "X = SS, leer bleibt leer")
	_ok(SS.passes_best_filter("", SS.BEST_ALL, []), "Alle: ohne Bestwert sichtbar")
	_ok(SS.passes_best_filter("B", SS.BEST_ALL, []), "Alle: mit Bestwert sichtbar")
	_ok(SS.passes_best_filter("A", SS.BEST_WITH, []), "Mit Bestwert")
	_ok(not SS.passes_best_filter("", SS.BEST_WITH, []), "Mit Bestwert schliesst leere aus")
	_ok(SS.passes_best_filter("", SS.BEST_WITHOUT, []), "Ohne Bestwert")
	_ok(not SS.passes_best_filter("S", SS.BEST_WITHOUT, []), "Ohne Bestwert schliesst Noten aus")
	_ok(SS.passes_best_filter("S", SS.BEST_WITH, ["S", "A"]), "Note S in S/A")
	_ok(not SS.passes_best_filter("B", SS.BEST_WITH, ["S", "A"]), "Note B nicht in S/A")
	_ok(not SS.passes_best_filter("", SS.BEST_ALL, ["S"]), "Note gewaehlt: ohne Bestwert weg")


func _rows() -> Array:
	return [
		{"i": 0, "stars": 3.0, "last": "", "plays": 0, "mtime": 100},
		{"i": 1, "stars": 5.0, "last": "2026-11-06T09:00:00", "plays": 2, "mtime": 300},
		{"i": 2, "stars": 1.0, "last": "2026-11-07T12:00:00", "plays": 7, "mtime": 200},
		{"i": 3, "stars": 3.0, "last": "", "plays": 2, "mtime": 300},
	]


func _order(rows: Array) -> Array:
	return rows.map(func(r): return int(r["i"]))


func _test_sort() -> void:
	var r := _rows()
	SS.sort_rows(r, SS.SORT_TITLE)
	_ok(_order(r) == [0, 1, 2, 3], "Titel: Bibliotheks-Reihenfolge")
	r = _rows()
	SS.sort_rows(r, SS.SORT_STARS_UP)
	_ok(_order(r) == [2, 0, 3, 1], "Sterne aufsteigend, Gleichstand stabil (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_STARS_DOWN)
	_ok(_order(r) == [1, 0, 3, 2], "Sterne absteigend (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_RECENT)
	_ok(_order(r) == [2, 1, 0, 3], "Zuletzt gespielt, ungespielte hinten (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_DOWNLOADED)
	_ok(_order(r) == [1, 3, 2, 0], "Zuletzt heruntergeladen (%s)" % str(_order(r)))
	r = _rows()
	SS.sort_rows(r, SS.SORT_MOST_PLAYED)
	_ok(_order(r) == [2, 1, 3, 0], "Meistgespielt (%s)" % str(_order(r)))


func _test_mode_filter() -> void:
	var d: Dictionary = SS.default_mode_filter()
	_ok(d["sort"] == SS.SORT_TITLE and d["best"] == SS.BEST_ALL and (d["grades"] as Array).is_empty(), "Standard")
	var s: Dictionary = SS.sanitize_mode_filter({"sort": 99, "best": -3, "grades": ["S", "Q", "S", "A"]})
	_ok(s["sort"] == SS.SORT_NAMES.size() - 1, "Sortierung begrenzt")
	_ok(s["grades"] == ["S", "A"], "unbekannte/doppelte Noten weg (%s)" % str(s["grades"]))
	_ok(s["best"] == SS.BEST_WITH, "Noten erzwingen Mit Bestwert")
	_ok(SS.sanitize_mode_filter({"grades": "S"})["grades"] == [], "kaputte Noten-Liste ignoriert")
	# Je Modus getrennt ueber ConfigFile gespeichert und wieder gelesen.
	var cfg := ConfigFile.new()
	cfg.set_value("browser", "mode_filters", {
		"mania": {"sort": SS.SORT_RECENT, "best": SS.BEST_WITHOUT, "grades": []},
		"orbit": {"sort": SS.SORT_MOST_PLAYED, "best": SS.BEST_WITH, "grades": ["SS"]}})
	var path := "user://test_tmp/browser_filter_state.cfg"
	cfg.save(path)
	var back := ConfigFile.new()
	back.load(path)
	var mfs: Dictionary = back.get_value("browser", "mode_filters", {})
	var m: Dictionary = SS.sanitize_mode_filter(mfs.get("mania", {}))
	var o: Dictionary = SS.sanitize_mode_filter(mfs.get("orbit", {}))
	_ok(m["sort"] == SS.SORT_RECENT and m["best"] == SS.BEST_WITHOUT, "Mania-Filter nach Neustart")
	_ok(o["sort"] == SS.SORT_MOST_PLAYED and o["grades"] == ["SS"], "Orbit-Filter nach Neustart")
	DirAccess.remove_absolute(path)


## "Zuletzt heruntergeladen" nutzt die Aenderungszeit der Datei.
func _test_mtime() -> void:
	var p := "user://test_tmp/browser_filter_map.osz"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var t := FileAccess.get_modified_time(p)
	_ok(absi(t - int(Time.get_unix_time_from_system())) < 120, "mtime der neuen Datei ist jetzt")
	DirAccess.remove_absolute(p)
	DirAccess.remove_absolute(TMP)
