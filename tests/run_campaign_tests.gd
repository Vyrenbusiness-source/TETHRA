extends SceneTree

## Kampagne: Datenformat, Ziele, Sterne, Freischaltung, Speichern.
## Arbeitet nur mit einer eigenen Testdatei (user://test_tmp), nie mit Echtdaten, ohne Netz.

var _fail := 0
var _count := 0


func _ok(cond: bool, what: String) -> void:
	_count += 1
	if not cond:
		_fail += 1
		print("FAIL: " + what)


func _initialize() -> void:
	_test_data()
	_test_goals()
	_test_stars()
	_test_progress()
	_test_unlock()
	_test_totals()
	_test_file()
	_test_maps()
	_test_validate_errors()


## Autoloads (Settings, GameSession) stehen erst im ersten Frame im Baum.
func _process(_delta: float) -> bool:
	_test_world_force()
	print("=== Campaign-Tests: %d Pruefungen, %d Fehler ===" % [_count, _fail])
	quit(1 if _fail > 0 else 0)
	return true


func _saved_world(s: Node, path: String) -> int:
	s.save(path)
	var cfg := ConfigFile.new()
	cfg.load(path)
	return int(cfg.get_value("game", "world_theme", -1))


## Welt-Zwang der Stufe: gilt nur, waehrend die Spielszene sich aufbaut. Er steht nie
## in den Einstellungen, auch nicht, wenn mitten in der Stufe gespeichert wird.
func _test_world_force() -> void:
	var s := root.get_node_or_null("/root/Settings")
	var gs := root.get_node_or_null("/root/GameSession")
	_ok(s != null and gs != null, "Autoloads Settings und GameSession da")
	if s == null or gs == null:
		return
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var path := "user://test_tmp/campaign_settings_%d.cfg" % OS.get_process_id()
	var order: Array = s.WORLD_ORDER
	var world := str(order[order.size() - 1])
	var own := 2
	var before: int = s.world_theme
	s.world_theme = own
	gs.start_campaign("c01s1", world)
	_ok(gs.campaign_active(), "Stufe laeuft")
	_ok(s.world_theme == own, "Stufenstart laesst die Einstellung in Ruhe")
	_ok(_saved_world(s, path) == own, "Speichern vor der Spielszene: eigene Welt")
	var src := GDScript.new()
	src.source_code = "extends Node
var seen := \"\"
func _ready() -> void:
	seen = get_node(\"/root/Settings\").world_theme_name()
"
	src.reload()
	var game := Node.new()
	game.set_script(src)
	game.scene_file_path = ScoreStore.MODE_SCENES.mania
	root.add_child(game)
	_ok(str(game.get("seen")) == world, "Spielszene sieht beim Aufbau die Welt des Kapitels")
	_ok(s.world_theme == own, "nach dem Aufbau wieder die eigene Welt")
	_ok(_saved_world(s, path) == own, "Speichern mitten in der Stufe: eigene Welt")
	s.world_theme = 3
	_ok(_saved_world(s, path) == 3, "Weltwechsel in der Pause bleibt")
	game.free()
	var retry := Node.new()
	retry.set_script(src)
	retry.scene_file_path = ScoreStore.MODE_SCENES.orbit
	root.add_child(retry)
	_ok(str(retry.get("seen")) == world, "Neustart der Stufe: wieder die Welt des Kapitels")
	_ok(s.world_theme == 3, "Neustart laesst die Einstellung in Ruhe")
	retry.free()
	gs.end_campaign()
	_ok(not gs.campaign_active() and s.world_theme == 3, "Stufenende: Einstellung unveraendert")
	var free_play := Node.new()
	free_play.set_script(src)
	free_play.scene_file_path = ScoreStore.MODE_SCENES.mania
	root.add_child(free_play)
	_ok(str(free_play.get("seen")) == str(order[2]), "ohne Kampagne: eigene Welt")
	free_play.free()
	s.world_theme = before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run(acc: float, grade: String, miss: int, score: int = 500000, failed: bool = false) -> Dictionary:
	return {"failed": failed, "accuracy": acc, "grade": grade, "n_miss": miss, "score": score, "max_combo": 100}


func _mini() -> Dictionary:
	var chs: Array = []
	for c in 2:
		var sts: Array = []
		for s in Campaign.STAGES_PER_CHAPTER:
			sts.append({"id": "c%02ds%d" % [c + 1, s + 1], "boss": s == Campaign.STAGES_PER_CHAPTER - 1,
				"mode": "mania", "mods": [], "set_id": 100 + c * 10 + s, "beatmap_id": 1, "diff": "Easy",
				"md5": "%032d" % (c * 10 + s), "goals": [{"type": "pass"}, {"type": "acc", "value": 0.9},
				{"type": "miss", "value": 0}]})
		chs.append({"id": "c%02d" % (c + 1), "world": "galaxy" if c == 0 else "boss", "focus": "mania",
			"stars": [1.0, 2.0], "stages": sts})
	return {"version": "t1", "chapters": chs}


func _test_data() -> void:
	var all := Campaign.load_data()
	_ok(not all.is_empty(), "data/campaign.json laedt")
	var d := Campaign.for_mode(all, "mania")
	var errs := Campaign.validate(all)
	for e in errs:
		print("  Datenfehler: " + e)
	_ok(errs.is_empty(), "data/campaign.json ist gueltig")
	var chs := Campaign.chapters(d)
	_ok(chs.size() == 13, "13 Kapitel")
	_ok(Campaign.all_stages(d).size() == 78, "78 Stufen")
	_ok(Campaign.max_stars(d) == 234, "234 Sterne maximal")
	var only_mania := true
	for s: Dictionary in Campaign.all_stages(d):
		only_mania = only_mania and str(s.mode) == "mania"
	_ok(only_mania, "Mania-Kampagne nur mit Mania-Stufen")
	for m in ScoreStore.MODES:
		_ok(all.campaigns.has(m), "Kampagne fuer %s vorhanden (oder bald)" % m)
	_ok(Campaign.chapters(Campaign.for_mode(all, "nope")).is_empty(), "unbekannter Modus = keine Kapitel")
	_ok(Campaign.mode_of_stage(all, "orbit-c01s2") == "orbit" and Campaign.mode_of_stage(all, "orbit-c99s1") == "", "mode_of_stage")
	# Fortschritt je Modus getrennt.
	var sep := Campaign.new_state()
	Campaign.apply_run(sep, Campaign.stage_by_id(d, "mania-c01s1"), _run(0.99, "SS", 0))
	var orbit := Campaign.for_mode(all, "orbit")
	_ok(Campaign.total_stars(d, sep) == 3 and Campaign.total_stars(orbit, sep) == 0, "Sterne je Modus getrennt")
	_ok(Campaign.stage_open(d, sep, "mania-c01s2") and not Campaign.stage_open(orbit, sep, "orbit-c01s2"), "Freischaltung je Modus getrennt")
	_ok(Campaign.total_stars_all(all, sep) == 3 and Campaign.max_stars_all(all) >= 234 + 18, "Summe ueber alle Modi")
	var worlds := {}
	for c: Dictionary in chs:
		worlds[str(c.world)] = true
	_ok(worlds.size() == 13, "jede Welt genau einmal")
	_ok(str((chs[chs.size() - 1] as Dictionary).world) == WorldTheme.BOSS, "Finale in der Boss-Welt")
	var playable := 0
	for c: Dictionary in chs:
		var all_maps := true
		for s: Dictionary in c.stages:
			all_maps = all_maps and Campaign.has_map(s)
		if all_maps:
			playable += 1
	_ok(playable >= 3, "mindestens 3 Kapitel mit echten Maps")
	_ok(float((chs[0] as Dictionary).stars[0]) <= 1.2, "Start sehr leicht")
	_ok(float((chs[12] as Dictionary).stars[1]) > float((chs[0] as Dictionary).stars[1]) + 2.0, "Schwierigkeit steigt")
	# Innerhalb eines Kapitels steigen die Map-Sterne.
	var rising := true
	for c: Dictionary in chs:
		var prev := 0.0
		for s: Dictionary in c.stages:
			if Campaign.has_map(s):
				rising = rising and float(s.map_stars) + 0.05 >= prev
				prev = float(s.map_stars)
	_ok(rising, "Map-Sterne steigen je Kapitel")
	_ok(Campaign.score_tag(d, "mania-c03s2") == "v1/mania-c03s2", "score_tag")
	_ok(Campaign.next_stage_id(d, "mania-c01s6") == "mania-c02s1", "next_stage_id ueber Kapitelgrenze")
	_ok(Campaign.next_stage_id(d, "mania-c13s6") == "", "letzte Stufe hat keine Folge")
	_ok(Campaign.chapter_index_of(d, "mania-c05s3") == 4 and Campaign.stage_index_of(d, "mania-c05s3") == 2, "Indizes")
	_ok(Campaign.stage_by_id(d, "nope").is_empty(), "unbekannte Stufe = {}")


func _test_goals() -> void:
	_ok(Campaign.goal_met({"type": "pass"}, _run(0.5, "D", 50)), "pass")
	_ok(not Campaign.goal_met({"type": "pass"}, _run(0.99, "S", 0, 1, true)), "Fail erfuellt kein Ziel")
	_ok(Campaign.goal_met({"type": "acc", "value": 0.95}, _run(0.95, "A", 3)), "acc genau erreicht")
	_ok(not Campaign.goal_met({"type": "acc", "value": 0.95}, _run(0.9499, "A", 3)), "acc knapp verfehlt")
	_ok(Campaign.goal_met({"type": "grade", "value": "A"}, _run(0.97, "S", 3)), "Rang besser als verlangt")
	_ok(Campaign.goal_met({"type": "grade", "value": "A"}, _run(0.97, "SS", 0)), "SS schlaegt A")
	_ok(not Campaign.goal_met({"type": "grade", "value": "A"}, _run(0.9, "B", 3)), "Rang zu schlecht")
	_ok(Campaign.goal_met({"type": "miss", "value": 0}, _run(0.97, "S", 0)), "kein Miss")
	_ok(not Campaign.goal_met({"type": "miss", "value": 0}, _run(0.97, "S", 1)), "ein Miss zu viel")
	_ok(Campaign.goal_met({"type": "miss", "value": 5}, _run(0.97, "S", 5)), "Miss-Grenze erreicht")
	_ok(not Campaign.goal_met({"type": "nope"}, _run(1.0, "SS", 0)), "unbekanntes Ziel nie erfuellt")
	_ok(Campaign.goal_valid({"type": "acc", "value": 0.9}) and not Campaign.goal_valid({"type": "acc", "value": 95}), "goal_valid acc")
	_ok(not Campaign.goal_valid({"type": "grade", "value": "X"}), "goal_valid grade")
	_ok(Campaign.goal_text({"type": "miss", "value": 0}) != "", "goal_text")


func _test_stars() -> void:
	var st: Dictionary = Campaign.all_stages(_mini())[0]
	_ok(Campaign.stars_for(st, _run(0.8, "C", 9)) == 1, "nur Ziel = 1 Stern")
	_ok(Campaign.stars_for(st, _run(0.93, "A", 2)) == 2, "Ziel + Zusatz = 2 Sterne")
	_ok(Campaign.stars_for(st, _run(0.99, "SS", 0)) == 3, "alle = 3 Sterne")
	_ok(Campaign.stars_for(st, _run(0.99, "SS", 0, 1, true)) == 0, "Fail = 0 Sterne")
	_ok(Campaign.goals_met(st, _run(0.85, "B", 0)) == [true, false, true], "Meisterziel ohne Zusatzziel")
	var hard := {"id": "x", "goals": [{"type": "acc", "value": 0.95}, {"type": "pass"}, {"type": "miss", "value": 99}]}
	_ok(Campaign.stars_for(hard, _run(0.9, "A", 1)) == 0, "ohne Hauptziel keine Sterne")


func _test_progress() -> void:
	var d := _mini()
	var st: Dictionary = Campaign.all_stages(d)[0]
	var state := Campaign.new_state()
	_ok(Campaign.stage_stars(state, "c01s1") == 0 and not Campaign.stage_cleared(state, "c01s1"), "leerer Stand")
	var r := Campaign.apply_run(state, st, _run(0.99, "S", 0, 1, true))
	_ok(int(r.stars) == 0 and not bool(r.new_best) and int(Campaign.entry(state, "c01s1").plays) == 1, "Fail zaehlt nur als Versuch")
	_ok(not Campaign.entry(state, "c01s1").has("score"), "Fail setzt keinen Bestwert")
	r = Campaign.apply_run(state, st, _run(0.93, "A", 2, 700000))
	_ok(int(r.stars) == 2 and int(r.gained) == 2 and bool(r.cleared_now) and bool(r.new_best), "erster Erfolg")
	r = Campaign.apply_run(state, st, _run(0.85, "B", 0, 600000))
	_ok(int(r.stars_run) == 2 and int(r.stars) == 3 and int(r.gained) == 1, "Ziele sammeln sich ueber Laeufe")
	_ok(not bool(r.new_best) and not bool(r.cleared_now), "schlechterer Score ist kein Bestwert")
	_ok(int(Campaign.entry(state, "c01s1").score) == 700000, "Bestwert bleibt")
	r = Campaign.apply_run(state, st, _run(0.7, "C", 30, 100))
	_ok(int(r.stars) == 3 and int(r.gained) == 0, "Sterne gehen nie verloren")
	_ok(int(Campaign.entry(state, "c01s1").plays) == 4, "Versuche gezaehlt")


func _test_unlock() -> void:
	var d := _mini()
	var all := Campaign.all_stages(d)
	var state := Campaign.new_state()
	_ok(Campaign.chapter_open(d, state, 0) and not Campaign.chapter_open(d, state, 1), "nur Kapitel 1 offen")
	_ok(not Campaign.chapter_open(d, state, 2) and not Campaign.chapter_open(d, state, -1), "Kapitel ausserhalb")
	_ok(Campaign.stage_open(d, state, "c01s1") and not Campaign.stage_open(d, state, "c01s2"), "nur Stufe 1 offen")
	_ok(Campaign.current_stage_id(d, state) == "c01s1", "aktuelle Stufe am Start")
	Campaign.apply_run(state, all[0], _run(0.5, "D", 40, 1, true))
	_ok(not Campaign.stage_open(d, state, "c01s2"), "Fail schaltet nichts frei")
	Campaign.apply_run(state, all[0], _run(0.5, "D", 40))
	_ok(Campaign.stage_open(d, state, "c01s2") and not Campaign.stage_open(d, state, "c01s3"), "Ziel schaltet naechste Stufe frei")
	for i in range(1, 5):
		Campaign.apply_run(state, all[i], _run(0.5, "D", 40))
	_ok(not Campaign.chapter_done(d.chapters[0], state) and not Campaign.chapter_open(d, state, 1), "ohne Boss kein Kapitel 2")
	_ok(not Campaign.stage_open(d, state, "c02s1"), "Stufe im gesperrten Kapitel zu")
	_ok(Campaign.current_stage_id(d, state) == "c01s6", "aktuelle Stufe = Boss")
	Campaign.apply_run(state, all[5], _run(0.5, "D", 40))
	_ok(Campaign.chapter_done(d.chapters[0], state) and Campaign.chapter_open(d, state, 1), "Boss schaltet Kapitel 2 frei")
	_ok(Campaign.stage_open(d, state, "c02s1") and Campaign.current_stage_id(d, state) == "c02s1", "Kapitel 2 Stufe 1 offen")
	for i in range(6, 12):
		Campaign.apply_run(state, all[i], _run(0.5, "D", 40))
	_ok(Campaign.current_stage_id(d, state) == "", "alles geschafft")


func _test_totals() -> void:
	var d := _mini()
	var all := Campaign.all_stages(d)
	var state := Campaign.new_state()
	Campaign.apply_run(state, all[0], _run(0.99, "SS", 0, 900000))
	Campaign.apply_run(state, all[1], _run(0.91, "A", 4, 800000))
	Campaign.apply_run(state, all[2], _run(0.91, "A", 4, 999999, true))
	_ok(Campaign.total_stars(d, state) == 5, "Gesamtsterne")
	_ok(Campaign.total_points(d, state) == 1700000, "Gesamtpunkte nur aus geschafften Stufen")
	_ok(Campaign.chapter_stars(d.chapters[0], state) == 5 and Campaign.chapter_max_stars(d.chapters[0]) == 18, "Kapitelsterne")
	_ok(Campaign.max_stars(d) == 36, "max_stars")


func _test_file() -> void:
	var path := "user://test_tmp/campaign_test_%d.json" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	_ok(Campaign.default_path() != Campaign.PATH, "Tests nutzen nie die echte Datei")
	_ok(Campaign.load_state(path).stages.is_empty(), "fehlende Datei = neuer Stand")
	var d := _mini()
	var state := Campaign.new_state()
	Campaign.apply_run(state, Campaign.all_stages(d)[0], _run(0.93, "A", 2, 700000))
	_ok(Campaign.save_state(state, path), "speichern")
	var back := Campaign.load_state(path)
	_ok(Campaign.stage_stars(back, "c01s1") == 2 and int(Campaign.entry(back, "c01s1").score) == 700000, "laden = gespeichert")
	_ok(Campaign.stage_open(d, back, "c01s2"), "Freischaltung nach dem Laden")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{kaputt")
	f.close()
	_ok(Campaign.load_state(path).stages.is_empty(), "kaputte Datei = neuer Stand")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_maps() -> void:
	_ok(Campaign.set_id_of_file("C:/maps/mirror_123456.osz") == 123456, "Set-ID mirror_")
	_ok(Campaign.set_id_of_file("79038 ALTIMA - Burst The Gravity.osz") == 79038, "Set-ID osu-Name")
	_ok(Campaign.set_id_of_file("song.osz") == 0, "keine Set-ID")
	var d := _mini()
	var st: Dictionary = Campaign.all_stages(d)[0]
	var sets := [
		{"osz_path": "C:/maps/mirror_999.osz", "diffs": [{"version": "Easy", "osu_filename": "a.osu", "stars": 1.0}]},
		{"osz_path": "C:/maps/mirror_100.osz", "diffs": [{"version": "Hard", "osu_filename": "h.osu", "stars": 3.0},
			{"version": "Easy", "osu_filename": "e.osu", "stars": 1.2}]},
	]
	var loc := Campaign.find_local(st, sets)
	_ok(str(loc.get("osu_filename", "")) == "e.osu" and int(loc.get("index", -1)) == 1, "find_local: Set und Diff")
	_ok(Campaign.find_local(Campaign.all_stages(d)[1], sets).is_empty(), "find_local: fehlt")
	# Online-Name "[4K] Easy", in der .osu steht "Easy".
	var pre: Dictionary = st.duplicate()
	pre["diff"] = "[4K] Easy"
	var loc_pre := Campaign.find_local(pre, sets)
	_ok(str(loc_pre.get("osu_filename", "")) == "e.osu" and str(loc_pre.get("version", "")) == "Easy",
		"find_local: Tastenzahl vor dem Diff-Namen")
	_ok(Campaign.diff_matches("[7K] Brutal [Lv.15]", "Brutal [Lv.15]"), "diff_matches: [7K]")
	_ok(not Campaign.diff_matches("[4K] Easy", "Hard") and not Campaign.diff_matches("[Extra] Easy", "Easy")
		and not Campaign.diff_matches("Easy", "[4K] Easy"), "diff_matches: sonst genau")
	var miss := Campaign.missing_sets(d.chapters[0], sets)
	_ok(miss.size() == 5 and not miss.has(100) and miss.has(101), "missing_sets")
	_ok(Campaign.length_text(125) == "2:05", "length_text")


func _test_validate_errors() -> void:
	_ok(Campaign.validate_one(_mini()).is_empty(), "Mini-Kampagne gueltig")
	var wrong: Dictionary = Campaign.load_data().duplicate(true)
	wrong.campaigns.orbit.chapters[0].stages[0]["mode"] = "mania"
	_ok(not Campaign.validate(wrong).is_empty(), "Stufe im falschen Modus geprueft")
	_ok(not Campaign.validate({}).is_empty(), "leere Daten ungueltig")
	var d := _mini()
	d.chapters[0].stages[1]["md5"] = "kurz"
	_ok(not Campaign.validate_one(d).is_empty(), "md5 geprueft")
	d = _mini()
	d.chapters[0].stages[1]["mode"] = "nope"
	_ok(not Campaign.validate_one(d).is_empty(), "Modus geprueft")
	d = _mini()
	d.chapters[0].stages[2]["id"] = "c01s1"
	_ok(not Campaign.validate_one(d).is_empty(), "doppelte ID geprueft")
	d = _mini()
	d.chapters[1].stages[0]["goals"] = [{"type": "pass"}]
	_ok(not Campaign.validate_one(d).is_empty(), "Zahl der Ziele geprueft")
	d = _mini()
	d.chapters[1].stages[0]["mods"] = ["NF"]
	_ok(not Campaign.validate_one(d).is_empty(), "NF nicht erlaubt")
	d = _mini()
	d.chapters[1]["world"] = "nirgendwo"
	_ok(not Campaign.validate_one(d).is_empty(), "Welt geprueft")
