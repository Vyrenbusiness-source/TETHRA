extends SceneTree

## Tests fuer die Orbit-Karriere (scripts/orbit/orbit_career.gd): Stufe auf/ab,
## Vorschlagsfenster, "Bereit fuer mehr", leere Daten, Speichern.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_career_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-4


func _run(stars: float, acc: float, failed: bool = false, grade: String = "A") -> Dictionary:
	return { "stars": stars, "accuracy": acc, "failed": failed, "grade": grade }


func _init() -> void:
	print("=== OMEN Orbit-Karriere-Tests ===")
	_test_levels()
	_test_ready()
	_test_window()
	_test_empty()
	_test_sync_and_save()
	print("=== %s ===" % ("ALLE OK" if _failed == 0 else "%d FEHLER" % _failed))
	quit(1 if _failed > 0 else 0)


func _test_levels() -> void:
	var s := OrbitCareer.new_state()
	_check(_near(s.level, 1.5), "Start bei 1,5")
	s = OrbitCareer.apply_run(s, _run(1.5, 0.94))
	s = OrbitCareer.apply_run(s, _run(1.6, 0.95))
	_check(_near(s.level, 1.5) and OrbitCareer.runs_to_next(s) == 1, "2 gute Laeufe: Stufe gleich, noch 1 Map")
	s = OrbitCareer.apply_run(s, _run(1.5, 0.93))
	_check(_near(s.level, 1.8) and s.event == "up", "3 Laeufe >= 93 %: Stufe +0,3")
	_check(OrbitCareer.runs_to_next(s) == 3, "danach wieder 3 Maps")
	# Mittelmaessiger Lauf reisst die Serie ab.
	s = OrbitCareer.apply_run(s, _run(1.8, 0.95))
	s = OrbitCareer.apply_run(s, _run(1.8, 0.88))
	s = OrbitCareer.apply_run(s, _run(1.8, 0.95))
	_check(_near(s.level, 1.8), "Serie bricht bei 88 % ab")
	# Absteigen: 3 schlechte hintereinander.
	var d := OrbitCareer.new_state()
	d["level"] = 2.1
	d = OrbitCareer.apply_run(d, _run(2.1, 0.7))
	d = OrbitCareer.apply_run(d, _run(2.0, 0.9, true, "F"))
	_check(_near(d.level, 2.1), "2 schlechte: noch keine Aenderung")
	d = OrbitCareer.apply_run(d, _run(2.2, 0.75))
	_check(_near(d.level, 1.8) and d.event == "down", "3 Fails/< 80 %: Stufe -0,3")
	# Untergrenze.
	var m := OrbitCareer.new_state()
	m["level"] = 1.0
	for i in 3:
		m = OrbitCareer.apply_run(m, _run(1.0, 0.5, true, "F"))
	_check(_near(m.level, 1.0), "Stufe faellt nicht unter 1,0")
	# Weit ausserhalb des Fensters zaehlt nicht.
	var o := OrbitCareer.new_state()
	for i in 4:
		o = OrbitCareer.apply_run(o, _run(0.5, 0.99))
	_check(_near(o.level, 1.5), "gute Laeufe auf viel zu leichten Maps heben nicht an")
	var p := OrbitCareer.new_state()
	for i in 4:
		p = OrbitCareer.apply_run(p, _run(4.0, 0.3, true, "F"))
	_check(_near(p.level, 1.5), "Fails auf viel zu schweren Maps senken nicht")
	# Lauf ohne Sterne wird uebergangen.
	var q := OrbitCareer.apply_run(OrbitCareer.new_state(), _run(-1.0, 0.99))
	_check(int(q.runs) == 0 and int(q.good) == 0, "unbekannte Sterne zaehlen nicht")


func _test_ready() -> void:
	var s := OrbitCareer.new_state()
	s = OrbitCareer.apply_run(s, _run(1.5, 0.98))
	_check(not OrbitCareer.ready_for_more(s), "ein 97+-Lauf: noch nicht bereit")
	s = OrbitCareer.apply_run(s, _run(1.6, 0.975))
	_check(OrbitCareer.ready_for_more(s) and _near(s.level, 2.1), "zweimal >= 97 %: Bereit fuer mehr, Stufe +0,6")
	s = OrbitCareer.apply_run(s, _run(2.1, 0.9))
	_check(not OrbitCareer.ready_for_more(s), "Hinweis verschwindet nach dem naechsten Lauf")
	var t := OrbitCareer.new_state()
	t = OrbitCareer.apply_run(t, _run(1.5, 0.98))
	t = OrbitCareer.apply_run(t, _run(1.5, 0.95))
	t = OrbitCareer.apply_run(t, _run(1.5, 0.98))
	_check(not OrbitCareer.ready_for_more(t), "97-Laeufe muessen direkt aufeinander folgen")


func _test_window() -> void:
	var w := OrbitCareer.window(2.1)
	_check(_near(w.x, 1.8) and _near(w.y, 2.6), "Fenster [Stufe-0,3, Stufe+0,5]")
	var cands: Array = [
		{ "key": "a", "stars": 1.7 }, { "key": "b", "stars": 1.8 }, { "key": "c", "stars": 2.2 },
		{ "key": "d", "stars": 2.6 }, { "key": "e", "stars": 2.7 }, { "key": "f", "stars": 2.15, "played": true },
		{ "key": "g", "stars": -1.0 },
	]
	var sug := OrbitCareer.suggest(cands, 2.1, 5)
	var keys := []
	for c in sug:
		keys.append(c.key)
	_check(not keys.has("a") and not keys.has("e") and not keys.has("g"), "ausserhalb/unbekannt nicht vorgeschlagen")
	_check(keys.size() == 4 and keys[0] == "c", "naechste an Stufe+0,1 zuerst: %s" % str(keys))
	_check(keys[keys.size() - 1] == "f", "bereits gespielte zuletzt")
	_check(OrbitCareer.suggest(cands, 2.1, 2).size() == 2, "Obergrenze n")
	_check(OrbitCareer.recommended(2.0, 2.1) and not OrbitCareer.recommended(3.5, 2.1), "Markierung im Fenster")
	var f := OrbitCareer.online_star_filter(1.5)
	_check(f >= 1 and f < OnlineBrowser.STAR_FILTERS.size(), "Online-Filter-Index gueltig")
	_check(OrbitCareer.online_star_filter(2.4) == 3, "2,4 -> Filter 2-3")


func _test_empty() -> void:
	_check(OrbitCareer.suggest([], 1.5).is_empty(), "keine Kandidaten: leere Liste")
	var s := OrbitCareer.sync_runs(OrbitCareer.new_state(), [])
	_check(_near(s.level, 1.5) and int(s.runs) == 0, "keine Laeufe: Startzustand")
	var l := OrbitCareer.load_state("user://test_tmp/does_not_exist.cfg")
	_check(_near(l.level, 1.5) and l.mode == "free", "fehlende Datei: Startzustand")
	OrbitCareer.offer("user://test_tmp/offer.cfg")
	_check(bool(OrbitCareer.load_state("user://test_tmp/offer.cfg").offer), "Angebot nach Tutorial gemerkt")
	DirAccess.remove_absolute("user://test_tmp/offer.cfg")
	_check(OrbitCareer.runs_to_next(s) == 3 and OrbitCareer.next_text(s) != "", "Anzeige bei leerem Zustand")


func _test_sync_and_save() -> void:
	var runs := [
		{ "date": "2026-01-01T10:00:00", "stars": 1.5, "accuracy": 0.95, "grade": "A", "failed": false },
		{ "date": "2026-01-01T10:05:00", "stars": 1.5, "accuracy": 0.95, "grade": "A", "failed": false },
		{ "date": "2026-01-01T10:10:00", "stars": 1.5, "accuracy": 0.95, "grade": "A", "failed": false },
	]
	var s := OrbitCareer.sync_runs(OrbitCareer.new_state(), runs)
	_check(_near(s.level, 1.8) and s.stamp == "2026-01-01T10:10:00", "sync hebt an und merkt Stempel")
	var again := OrbitCareer.sync_runs(s, runs)
	_check(_near(again.level, 1.8) and int(again.runs) == int(s.runs), "bereits verarbeitete Laeufe nicht doppelt")
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var path := "user://test_tmp/career_%d.cfg" % OS.get_process_id()
	s["mode"] = "free"
	OrbitCareer.save_state(s, path)
	var l := OrbitCareer.load_state(path)
	_check(_near(l.level, 1.8) and l.mode == "free" and l.stamp == s.stamp, "Speichern/Laden")
	DirAccess.remove_absolute(path)
