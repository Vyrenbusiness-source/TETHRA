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
	_test_live()
	_test_lock_reason()
	_test_trial()
	_test_placement()


## Autoloads (Settings, GameSession) stehen erst im ersten Frame im Baum.
func _process(_delta: float) -> bool:
	_test_own_settings()
	_test_start_mods()
	print("=== Campaign-Tests: %d Pruefungen, %d Fehler ===" % [_count, _fail])
	quit(1 if _fail > 0 else 0)
	return true


## Alle Einstellungen als {Name: Wert} (Skript-Variablen des Autoloads Settings).
func _settings_snapshot(s: Node) -> Dictionary:
	var out := {}
	for p: Dictionary in s.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not str(p.name).begins_with("_"):
			var v: Variant = s.get(p.name)
			if typeof(v) != TYPE_OBJECT:
				out[str(p.name)] = v
	return out


func _settings_diff(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	for k: String in a:
		if a[k] != b.get(k):
			out.append(k)
	return ", ".join(out)


const _PROBE_SRC := "extends Node
var seen := {}
var world := \"\"
func _ready() -> void:
	var s := get_node(\"/root/Settings\")
	world = s.world_theme_name()
	for p in s.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not str(p.name).begins_with(\"_\"):
			var v = s.get(p.name)
			if typeof(v) != TYPE_OBJECT:
				seen[str(p.name)] = v
"


## Eine Kampagnen-Stufe startet mit den Einstellungen des Spielers, genau wie ein Start aus
## dem Song-Browser: Die Spielszene jedes Modus sieht beim Aufbau dieselben Werte (2D/3D,
## Welt inklusive Auto, Scroll Speed, Skin ...). Die Kapitel-Welt wird nie erzwungen.
func _test_own_settings() -> void:
	var s := root.get_node_or_null("/root/Settings")
	var gs := root.get_node_or_null("/root/GameSession")
	_ok(s != null and gs != null, "Autoloads Settings und GameSession da")
	if s == null or gs == null:
		return
	var src := GDScript.new()
	src.source_code = _PROBE_SRC
	src.reload()
	var before_2d: bool = s.playfield_2d
	var before_world: int = s.world_theme
	var all := Campaign.load_data()
	# Eigene Wahl: 2D an, Welt Auto (0) und eine feste Welt, die kein Kapitel dieser Stufen ist.
	for own_world: int in [0, 2]:
		for own_2d: bool in [true, false]:
			s.playfield_2d = own_2d
			s.world_theme = own_world
			var own := _settings_snapshot(s)
			for mode: String in ScoreStore.MODES:
				var chs := Campaign.chapters(Campaign.for_mode(all, mode))
				if chs.is_empty():
					continue
				var ch: Dictionary = chs[chs.size() - 1]
				var id := str(((ch.stages as Array)[0] as Dictionary).id)
				var tag := "%s (2D %s, Welt %d)" % [mode, str(own_2d), own_world]
				gs.start_campaign(id)
				_ok(gs.campaign_active(), "Stufe laeuft: " + tag)
				for attempt in 2:   # Start und Neustart der Stufe
					var game := Node.new()
					game.set_script(src)
					game.scene_file_path = ScoreStore.mode_scene(mode)
					root.add_child(game)
					var seen: Dictionary = game.get("seen")
					_ok(str(game.get("world")) == s.world_theme_name() and int(seen.get("world_theme", -1)) == own_world,
						"Spielszene sieht die eigene Welt, nicht die des Kapitels: " + tag)
					_ok(bool(seen.get("playfield_2d")) == own_2d, "Spielszene sieht eigenes 2D/3D: " + tag)
					_ok(_settings_diff(own, seen) == "", "Spielszene sieht alle eigenen Einstellungen: %s [%s]" % [tag, _settings_diff(own, seen)])
					game.free()
				gs.end_campaign()
				_ok(_settings_diff(own, _settings_snapshot(s)) == "", "Stufenende: Einstellungen unveraendert: " + tag)
	_ok(not ("_campaign_world_prev" in gs), "kein Welt-Zwang mehr in GameSession")
	_ok(not gs.campaign.has("world"), "laufende Stufe traegt keine Welt")
	s.playfield_2d = before_2d
	s.world_theme = before_world


## Mods eines Stufenstarts = Mods des Spielers fuer den Modus (wie der Song-Browser sie
## setzt) plus die Mods der Stufe. No Fail gibt es in der Kampagne nicht.
func _test_start_mods() -> void:
	var c := Campaign.new()
	_ok(c.has_method("start_mods") and c.has_method("player_mods"), "Campaign.start_mods / player_mods vorhanden")
	if not c.has_method("start_mods") or not c.has_method("player_mods"):
		return
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	var path := "user://test_tmp/campaign_browser_%d.cfg" % OS.get_process_id()
	var cfg := ConfigFile.new()
	cfg.set_value("browser", "orbit_mods", {"HD": true, "FI": false, "PR": true})
	cfg.set_value("browser", "trace_mods", {"MR": true, "HD": false, "SS": false})
	cfg.save(path)
	var mania: Dictionary = c.call("player_mods", "mania", true, path)
	_ok(mania == {"NF": false, "SV": true}, "Mania: SV des Spielers gilt")
	_ok(c.call("player_mods", "mania", false, path) == {"NF": false, "SV": false}, "Mania ohne SV")
	_ok(c.call("player_mods", "orbit", true, path) == {"NF": false, "HD": true, "FI": false, "PR": true}, "Orbit: HD/FI/PR des Spielers gelten")
	_ok(c.call("player_mods", "trace", true, path) == {"NF": false, "MR": true, "HD": false, "SS": false}, "Trace: MR/HD/SS des Spielers gelten")
	for m: String in ["rally", "dirigent", "rebound"]:
		_ok(c.call("player_mods", m, true, path) == {"NF": false}, m + ": keine eigenen Mods")
	_ok(c.call("player_mods", "orbit", false, "user://test_tmp/gibt_es_nicht.cfg") == {"NF": false, "HD": false, "FI": false, "PR": false}, "ohne Browser-Stand: Orbit-Mods aus")
	var plain := {"mode": "mania", "mods": []}
	var sv := {"mode": "mania", "mods": ["SV"]}
	_ok(c.call("start_mods", plain, {"NF": true, "SV": true}) == {"NF": false, "SV": true}, "No Fail gilt in der Kampagne nie")
	_ok(c.call("start_mods", sv, {"NF": false, "SV": false}) == {"NF": false, "SV": true}, "Mod der Stufe kommt dazu")
	_ok(c.call("start_mods", plain, {"NF": false, "SV": false}) == {"NF": false, "SV": false}, "ohne Mods bleibt es ohne")
	var player := {"NF": true, "HD": true}
	c.call("start_mods", plain, player)
	_ok(player == {"NF": true, "HD": true}, "start_mods aendert die Eingabe nicht")
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


## Ziele live im HUD: erfuellt (HOLD), offen, verloren.
func _test_live() -> void:
	var H := Campaign.LIVE_HOLD
	var O := Campaign.LIVE_OPEN
	var L := Campaign.LIVE_LOST
	_ok(Campaign.goal_live({"type": "pass"}, _run(0.5, "D", 9)) == O, "live: pass erst am Ende")
	_ok(Campaign.goal_live({"type": "pass"}, _run(0.9, "A", 0, 1, true)) == L, "live: Fail verliert pass")
	_ok(Campaign.goal_live({"type": "acc", "value": 0.95}, _run(0.96, "S", 0)) == H, "live: acc darueber")
	_ok(Campaign.goal_live({"type": "acc", "value": 0.95}, _run(0.94, "A", 0)) == O, "live: acc darunter bleibt offen")
	_ok(Campaign.goal_live({"type": "grade", "value": "S"}, _run(0.96, "S", 0)) == H, "live: Rang gehalten")
	_ok(Campaign.goal_live({"type": "miss", "value": 2}, _run(0.9, "A", 2)) == H, "live: Miss-Grenze gehalten")
	_ok(Campaign.goal_live({"type": "miss", "value": 2}, _run(0.9, "A", 3)) == L, "live: zu viele Misses")
	var st := {"goals": [{"type": "miss", "value": 0}, {"type": "acc", "value": 0.9}, {"type": "pass"}]}
	_ok(Campaign.goals_live(st, _run(0.99, "S", 1)) == [L, L, L], "live: Hauptziel verloren -> alle verloren")
	_ok(Campaign.goals_live(st, _run(0.85, "B", 0)) == [H, O, O], "live: gemischt")
	_ok(Campaign.goal_live_value({"type": "miss", "value": 8}, _run(0.9, "A", 3)) == "3 / 8", "live: Miss-Stand")
	_ok(Campaign.goal_live_value({"type": "grade", "value": "A"}, _run(0.9, "A", 3)) == "A", "live: Rang")
	_ok(Campaign.goal_live_value({"type": "pass"}, _run(0.9, "A", 3)) == "", "live: pass ohne Wert")
	_ok(Campaign.goal_best_value({"type": "acc", "value": 0.9}, {}) == "", "Bestwert: nicht gespielt")
	_ok(Campaign.goal_short({"type": "miss", "value": 3}).contains("3"), "Kurzform Miss")
	_ok(Campaign.goal_short({"type": "acc", "value": 0.958}).contains("95"), "Kurzform Genauigkeit")
	_ok(Campaign.goal_short({"type": "grade", "value": "A"}).contains("A") and Campaign.goal_short({"type": "pass"}) != "", "Kurzform Rang, pass")
	_ok(Campaign.goal_best_value({"type": "grade", "value": "A"}, {"score": 1, "grade": "B"}) == "B", "Bestwert: Rang")


## Warum gesperrt: Stufe davor oder Boss des Kapitels davor.
func _test_lock_reason() -> void:
	var d := _mini()
	var all := Campaign.all_stages(d)
	var state := Campaign.new_state()
	_ok(Campaign.lock_reason(d, state, "c01s1") == "", "offen: kein Grund")
	_ok(Campaign.lock_reason(d, state, "c01s3").contains("2"), "gesperrt: Stufe 2 fehlt")
	_ok(Campaign.lock_reason(d, state, "c02s1").contains("1"), "gesperrt: Boss Kapitel 1 fehlt")
	Campaign.apply_run(state, all[0], _run(0.5, "D", 40))
	_ok(Campaign.lock_reason(d, state, "c01s2") == "", "nach dem Ziel offen")
	_ok(Campaign.chapter_cleared_count(d.chapters[0], state) == 1, "eine Stufe geschafft")


## Kampagne mit n Kapiteln (Modus mania, Ziele wie _mini).
func _mini_n(n: int) -> Dictionary:
	var chs: Array = []
	for c in n:
		var sts: Array = []
		for k in Campaign.STAGES_PER_CHAPTER:
			sts.append({"id": "mania-c%02ds%d" % [c + 1, k + 1], "boss": k == Campaign.STAGES_PER_CHAPTER - 1,
				"mode": "mania", "mods": [], "set_id": 1000 + c * 10 + k, "beatmap_id": 1, "diff": "Easy",
				"md5": "%032d" % (c * 10 + k), "goals": [{"type": "pass"}, {"type": "acc", "value": 0.9},
				{"type": "miss", "value": 0}]})
		chs.append({"id": "c%02d" % (c + 1), "world": "galaxy", "focus": "mania", "stars": [1.0, 2.0], "stages": sts})
	return {"version": "t1", "mode": "mania", "chapters": chs}


## Skip-Pruefung: Boss zwei Kapitel weiter, 99 % Genauigkeit, Sterne nur zur Boss-Stufe.
func _test_trial() -> void:
	var d := _mini_n(13)
	_ok(Campaign.trial_target(d, 0) == 2 and Campaign.trial_target(d, 5) == 7, "Pruefung: zwei Kapitel weiter")
	_ok(Campaign.trial_target(d, 8) == 12 and Campaign.trial_target(d, 11) == 12, "Pruefung: letztes Drittel -> letztes Kapitel")
	_ok(Campaign.trial_target(d, 12) == -1 and Campaign.trial_target(_mini_n(1), 0) == -1, "Pruefung: keine im letzten Kapitel / bei einem Kapitel")
	_ok(str(Campaign.trial_stage(d, 0).get("id", "")) == "mania-c03s6", "Pruefungs-Map = Boss von Kapitel 3")
	var state := Campaign.new_state()
	_ok(Campaign.trial_available(d, state, 0) and not Campaign.trial_available(d, state, 1), "Pruefung nur in offenem Kapitel")
	# Nicht bestanden: 98,9 %, alle drei Ziele erfuellt -> Sterne zur Boss-Stufe, kein Sprung.
	var out := Campaign.apply_trial(state, d, 0, _run(0.989, "S", 0), {"NF": false})
	_ok(not bool(out.trial_passed) and str(out.trial_reason) != "", "unter 99 %: nicht bestanden, mit Grund")
	_ok(Campaign.stage_stars(state, "mania-c03s6") == 3, "Sterne der Pruefung zaehlen zur Boss-Stufe")
	_ok(not Campaign.chapter_open(d, state, 1) and Campaign.skip_to(state, "mania") == -1, "nicht bestanden: nichts frei")
	_ok(not Campaign.trial_passed(_run(0.995, "S", 0, 1, true), {}), "Fail besteht nie")
	_ok(not Campaign.trial_passed(_run(0.995, "S", 0), {"CS": true}), "Konstant zaehlt nicht")
	_ok(not Campaign.trial_passed(_run(0.995, "S", 0), {"NF": true}), "No Fail zaehlt nicht")
	var unr := _run(0.995, "S", 0)
	unr["unranked"] = true
	_ok(not Campaign.trial_passed(unr, {}), "Ungewertet zaehlt nicht")
	_ok(not Campaign.trial_passed(_run(0.9899, "S", 0), {}), "98,99 % besteht nicht")
	_ok(Campaign.trial_passed(_run(0.99, "S", 3), {"SV": true, "HD": true}), "genau 99 % mit schwereren Mods besteht")
	# Bestanden
	out = Campaign.apply_trial(state, d, 0, _run(0.993, "S", 2), {})
	_ok(bool(out.trial_passed) and bool(out.skip_new) and int(out.trial_to) == 2, "99,3 %: bestanden bis Kapitel 3")
	_ok(Campaign.stage_stars(state, "mania-c03s6") == 3, "keine doppelten Sterne")
	_ok(Campaign.chapter_open(d, state, 1) and Campaign.chapter_open(d, state, 2), "Kapitel 2 und 3 offen")
	_ok(Campaign.chapter_skipped(d, state, 1) and not Campaign.chapter_skipped(d, state, 2), "Kapitel 2 uebersprungen, 3 per Boss geschafft")
	_ok(Campaign.stage_open(d, state, "mania-c02s4") and Campaign.stage_open(d, state, "mania-c01s3"), "uebersprungene Stufen spielbar")
	_ok(Campaign.stage_stars(state, "mania-c02s4") == 0 and Campaign.total_stars(d, state) == 3, "uebersprungen = keine Sterne")
	_ok(Campaign.current_stage_id(d, state) == "mania-c04s1", "aktuelle Stufe nach dem Sprung")
	Campaign.apply_run(state, Campaign.stage_by_id(d, "mania-c02s4"), _run(0.95, "A", 0))
	_ok(Campaign.stage_stars(state, "mania-c02s4") == 3, "Nachholen gibt die Sterne")
	_ok(not Campaign.trial_available(d, state, 0), "Pruefung erledigt, Ziel offen")
	var lock := Campaign.chapter_lock_reason(d, state, 5)
	_ok(lock.contains("Skip") and lock.contains("5"), "Sperrgrund nennt die Skip-Pruefung")
	_ok(not Campaign.chapter_lock_reason(_mini_n(13), Campaign.new_state(), 6).contains("Skip"), "Sperrgrund ohne erreichbare Pruefung")
	# Spaeteres Bestehen einer kleineren Pruefung senkt den Sprung nicht.
	var before := Campaign.skip_to(state, "mania")
	Campaign.apply_trial(state, d, 0, _run(1.0, "SS", 0), {})
	_ok(Campaign.skip_to(state, "mania") == before, "Sprung sinkt nie")


## Einstufung: nur im leeren Modus, Folge-Pruefung = Pruefung des Ziel-Kapitels.
func _test_placement() -> void:
	var d := _mini_n(13)
	var state := Campaign.new_state()
	_ok(Campaign.placement_available(d, state), "Einstufung im leeren Modus")
	_ok(not Campaign.placement_available(_mini_n(1), state), "keine Einstufung ohne Pruefungen")
	_ok(Campaign.placement_next(d, 0) == 2 and Campaign.placement_next(d, 8) == -1, "Folge-Pruefung, Ende am letzten Kapitel")
	Campaign.apply_trial(state, d, 0, _run(0.995, "S", 0), {})
	_ok(not Campaign.placement_available(d, state), "nach dem ersten Sprung keine Einstufung mehr")
	Campaign.apply_trial(state, d, 2, _run(0.995, "S", 0), {})
	_ok(Campaign.skip_to(state, "mania") == 4 and Campaign.chapter_open(d, state, 4), "zweite Pruefung: bis Kapitel 5")
