extends SceneTree

## Tests fuer ScoreStore: Mods im Bestwert, alte Eintraege ohne Mods,
## Modus-Trennung (Mania/Orbit), SV-Stufe, Migration alter Dateien.
## Laeuft immer auf einer Test-Datei (ScoreStore.PATH unter --script).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	var backup := ""
	if FileAccess.file_exists(ScoreStore.PATH):
		backup = FileAccess.get_file_as_string(ScoreStore.PATH)
		DirAccess.remove_absolute(ScoreStore.PATH)

	# Roundtrip mit Mods
	ScoreStore.submit("t1.osz", "Hard", { "score": 1000, "grade": "S", "mods": ["SV", "NF"], "mod_mult": 1.05 })
	var b := ScoreStore.best("t1.osz", "Hard")
	_check(b.get("mods", []) == ["SV", "NF"], "mods roundtrip")
	_check(is_equal_approx(float(b.get("mod_mult", 0)), 1.05), "mod_mult roundtrip")
	_check(ScoreStore.best_mods("t1.osz", "Hard") == ["SV", "NF"], "best_mods")
	_check(MapPicker.mods_badge(b) == "SV NF", "badge zeigt Mods")

	# Ohne Mods
	ScoreStore.submit("t2.osz", "Easy", { "score": 500, "grade": "A" })
	var c := ScoreStore.best("t2.osz", "Easy")
	_check(c.get("mods", ["x"]) == [], "ohne Mods leer")
	_check(MapPicker.mods_badge(c) == "", "kein Badge ohne Mods")

	# Alte Datei ohne mods-Feld
	var cfg := ConfigFile.new()
	cfg.load(ScoreStore.PATH)
	cfg.set_value("scores", ScoreStore._key("old.osz", "Old"), { "score": 700, "grade": "B", "accuracy": 0.9 })
	cfg.save(ScoreStore.PATH)
	var o := ScoreStore.best("old.osz", "Old")
	_check(int(o.get("score", 0)) == 700, "alter Eintrag lesbar")
	_check(ScoreStore.best_mods("old.osz", "Old") == [], "alter Eintrag: keine Mods")
	var r := ScoreStore.submit("old.osz", "Old", { "score": 900, "mods": ["NF"] })
	_check(bool(r.is_new_best), "alter Eintrag ueberbietbar")
	_check(ScoreStore.best_mods("old.osz", "Old") == ["NF"], "neue Mods ersetzen alte")

	# Fremde Scores
	ScoreStore.submit("77 Song.osz", "Hard", { "score": 1000, "grade": "A", "pp": 50.0, "accuracy": 0.9 })
	ScoreStore.log_play("77 Song.osz", "Hard", "x", { "score": 1000, "grade": "A" })
	var pp_before := ScoreStore.profile_pp()
	var bp_before := ScoreStore.best_plays(10).size()
	var tp_before := ScoreStore.total_plays()
	var mk := ScoreStore.map_id_for_set(77, "Hard")
	var fe := { "score": 2000, "accuracy": 0.95, "grade": "S", "max_combo": 10, "pp": 99.0, "mods": [], "date": "d1" }
	_check(ScoreStore.submit_others(mk, "Bob", [fe]) == 1, "fremder Score gespeichert")
	_check(ScoreStore.submit_others(mk, "Bob", [fe]) == 0, "Duplikat nicht doppelt")
	_check(ScoreStore.submit_others(mk, "Cy", [fe]) == 1, "gleicher Score anderer Spieler ok")
	var many: Array = []
	for i in 15:
		many.append(fe.merged({ "score": 3000 + i, "date": "m%d" % i }, true))
	ScoreStore.submit_others(mk, "Bob", many)
	var bob := 0
	var top_bob := 0
	for e in ScoreStore.top_scores_all("mirror_77.osz", "Hard", 100):
		if e.player == "Bob":
			bob += 1
			top_bob = maxi(top_bob, int(e.score))
	_check(bob == 10 and top_bob == 3014, "max. 10 pro Spieler, beste bleiben")
	var all := ScoreStore.top_scores_all("77 Song.osz", "Hard", 100)
	var sorted_ok := true
	for i in range(1, all.size()):
		if int(all[i - 1].score) < int(all[i].score):
			sorted_ok = false
	_check(sorted_ok and int(all[0].score) == 3014, "top_scores_all sortiert")
	_check(all.any(func(e): return e.is_self and e.player == ScoreStore._self_name()), "eigener Eintrag is_self")
	_check(ScoreStore.top_scores_all("77 Song.osz", "Hard", 3).size() == 3, "n begrenzt")
	_check(ScoreStore.top_scores_all("mirror_77.osz", "Hard", 100).size() == all.size() - 1, "anderer Dateiname: fremde zugeordnet")
	ScoreStore.register_set_id("Artist - Weird Name.osz", 77)
	_check(ScoreStore.top_scores_all("Artist - Weird Name.osz", "Hard", 100).size() == all.size() - 1, "Registry ordnet zu")
	_check(ScoreStore.top_scores("77 Song.osz", "Hard").size() == 1, "top_scores nur eigene")
	_check(is_equal_approx(ScoreStore.profile_pp(), pp_before) and ScoreStore.best_plays(10).size() == bp_before \
			and ScoreStore.total_plays() == tp_before and int(ScoreStore.best("77 Song.osz", "Hard").score) == 1000, "Profil/pp/Bestwert unveraendert")
	_check(ScoreStore.submit_others(mk, "Dee", [fe.merged({ "score": -1 }, true)]) == 0, "ungueltig abgewiesen")

	_test_modes()
	_test_sv_level()
	_test_migration()
	_test_legacy_rescore()
	_test_playtime()

	# aufraeumen
	DirAccess.remove_absolute(ScoreStore.PATH)
	if backup != "":
		var f := FileAccess.open(ScoreStore.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)


## Mania und Orbit getrennt: Bestwerte, Plays, Verlauf, Profil, Rangliste.
func _test_modes() -> void:
	_check(ScoreStore.PATH != "user://scores.cfg", "Test nutzt nie die echte scores.cfg")
	var O := ScoreStore.MODE_ORBIT
	ScoreStore.submit("88 Mix.osz", "Hard", { "score": 5000, "grade": "A", "accuracy": 0.91, "pp": 40.0 })
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 5000, "grade": "A", "accuracy": 0.91, "pp": 40.0 })
	var pp0 := ScoreStore.profile_pp()
	var plays0 := ScoreStore.total_plays()
	var best0 := ScoreStore.best_plays(99).size()
	var recent0 := ScoreStore.recent_plays(99).size()
	# Orbit-Score (mit pp-Wert, darf trotzdem nie in Mania-pp fliessen)
	var r := ScoreStore.submit("88 Mix.osz", "Hard", { "score": 9000, "grade": "S", "accuracy": 0.97, "pp": 500.0, "mode": "orbit" }, O)
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 9000, "grade": "S", "accuracy": 0.97, "pp": 500.0 }, O)
	ScoreStore.log_play("88 Mix.osz", "Hard", "A - Mix", { "score": 100, "grade": "F", "accuracy": 0.2, "failed": true }, O)
	_check(bool(r.is_new_best), "erster Orbit-Score ist Bestwert (Mania-Bestwert egal)")
	_check(int(ScoreStore.best("88 Mix.osz", "Hard").score) == 5000, "Mania-Bestwert unveraendert")
	_check(int(ScoreStore.best("88 Mix.osz", "Hard", O).score) == 9000, "Orbit-Bestwert eigen")
	_check(str(ScoreStore.best("88 Mix.osz", "Hard", O).get("mode", "")) == "orbit", "Orbit-Eintrag traegt mode")
	_check(str(ScoreStore.best("88 Mix.osz", "Hard").get("mode", "")) == "mania", "Mania-Eintrag traegt mode")
	_check(is_equal_approx(ScoreStore.profile_pp(), pp0), "Mania-pp nie durch Orbit veraendert")
	_check(ScoreStore.total_plays() == plays0 and ScoreStore.total_plays(O) == 1, "Plays je Modus")
	_check(ScoreStore.best_plays(99).size() == best0 and ScoreStore.best_plays(99, O).size() == 1, "Bestwerte je Modus")
	_check(ScoreStore.recent_plays(99).size() == recent0 and ScoreStore.recent_plays(99, O).size() == 2, "Verlauf je Modus")
	_check(ScoreStore.most_played(9, O).size() == 1 and int(ScoreStore.most_played(9, O)[0].count) == 1, "Meistgespielt je Modus")
	# Rangliste: Mania-Fremdscores nie in Orbit, Orbit-Fremdscores nie in Mania
	var fe := { "score": 7000, "accuracy": 0.9, "grade": "A", "max_combo": 5, "pp": 10.0, "mods": [], "date": "d" }
	ScoreStore.submit_others(ScoreStore.map_id_for_set(88, "Hard"), "Mia", [fe])
	ScoreStore.submit_others(ScoreStore.map_id_for_set(88, "Hard"), "Oli", [fe.merged({ "score": 7100 }, true)], O)
	var tm := ScoreStore.top_scores_all("88 Mix.osz", "Hard", 10)
	var to := ScoreStore.top_scores_all("88 Mix.osz", "Hard", 10, O)
	_check(tm.size() == 2 and tm.any(func(e): return e.player == "Mia") and not tm.any(func(e): return e.player == "Oli"), "Mania-Rangliste ohne Orbit")
	_check(to.size() == 2 and to.any(func(e): return e.player == "Oli") and not to.any(func(e): return e.player == "Mia"), "Orbit-Rangliste ohne Mania")
	_check(to.all(func(e): return e.mode == "orbit") and tm.all(func(e): return e.mode == "mania"), "Rangliste traegt Modus")
	_check(int(to[0].score) == 9000, "Orbit-Rangliste: eigener Orbit-Score zuerst")
	# Profil-Kennzahlen je Modus
	var so := ScoreStore.mode_stats(O)
	_check(int(so.plays) == 1 and int(so.maps) == 1 and int(so.best_score) == 9000, "Orbit-Kennzahlen")
	_check(is_equal_approx(float(so.avg_acc), 0.97), "Orbit-Acc ohne Fails")
	_check(is_equal_approx(float(so.rating), 100.0 * pow(0.97, 4.0)), "Orbit-Wertung")
	_check(is_equal_approx(float(ScoreStore.mode_stats().rating), ScoreStore.profile_pp()), "Mania-Wertung = pp")
	# Vergleich im Results-Screen: nur derselbe Modus
	ScoreStore.submit("88 Mix.osz", "Hard", { "score": 9500, "grade": "S", "accuracy": 0.98 }, O)
	var prev = ScoreStore.previous_best_for("88 Mix.osz", "Hard", O, 9500)
	_check(prev is Dictionary and int(prev.score) == 9000, "Bestleistung: vorheriger Orbit-Score")
	_check(ScoreStore.previous_best_for("88 Mix.osz", "Hard", "", 9500) == null, "Bestleistung: nie anderer Modus")
	_check(ScoreStore.previous_best_for("88 Mix.osz", "Hard", O, 1) == null, "Bestleistung: nur gespeichertes Ergebnis")


## SV-Stufe im Score: gespeichert, angezeigt, alte Eintraege ohne Stufe.
func _test_sv_level() -> void:
	var keep := SvMod.strength
	SvMod.strength = SvMod.STRENGTH_NORMAL
	ScoreStore.submit("sv.osz", "N", { "score": 10, "mods": ["SV"] })
	ScoreStore.log_play("sv.osz", "N", "x", { "score": 10, "mods": ["SV"] })
	SvMod.strength = SvMod.STRENGTH_STRONG
	ScoreStore.submit("sv.osz", "S", { "score": 10, "mods": ["SV", "NF"] })
	ScoreStore.submit("sv.osz", "X", { "score": 10, "mods": ["SV"], "sv_level": "normal" })
	ScoreStore.submit("sv.osz", "P", { "score": 10, "mods": ["NF"] })
	var n := ScoreStore.best("sv.osz", "N")
	var st := ScoreStore.best("sv.osz", "S")
	_check(str(n.get("sv_level", "")) == "normal", "SV Normal gespeichert")
	_check(str(ScoreStore.top_scores("sv.osz", "N")[0].get("sv_level", "")) == "normal", "SV-Stufe im Verlauf")
	_check(str(st.get("sv_level", "")) == "strong", "SV Stark gespeichert (Standard)")
	_check(ScoreStore.sv_level(ScoreStore.best("sv.osz", "X")) == "normal", "SV-Stufe aus dem Ergebnis")
	_check(not ScoreStore.best("sv.osz", "P").has("sv_level"), "ohne SV keine Stufe")
	_check(ScoreStore.mods_label(n) == "SV " + TranslationServer.translate("Normal"), "Anzeige SV Normal")
	_check(ScoreStore.mods_label(st) == "SV " + TranslationServer.translate("Stark") + " NF", "Anzeige SV Stark NF")
	_check(ScoreStore.mods_label({ "mods": ["SV"] }) == "SV", "alter SV-Score ohne Stufe")
	_check(ScoreStore.mods_label({}) == "", "ohne Mods leer")
	var f := ScoreStore.sanitize_foreign({ "score": 1, "accuracy": 0.5, "grade": "D", "max_combo": 1, "pp": -1.0,
		"mods": ["SV"], "sv_level": "strong" }, "Zed")
	_check(str(f.get("sv_level", "")) == "strong", "Fremd-Score behaelt SV-Stufe")
	var bad := ScoreStore.sanitize_foreign({ "score": 1, "accuracy": 0.5, "grade": "D", "max_combo": 1, "pp": -1.0,
		"mods": [], "sv_level": 5 }, "Zed")
	_check(not bad.is_empty() and not bad.has("sv_level"), "Fremd-Score: ungueltige Stufe verworfen")
	SvMod.strength = keep


## Alte Datei (Schema 1): alles bleibt Mania, nichts geht verloren; nur
## Verlaufs-Eintraege mit mode = "orbit" wandern zu Orbit.
func _test_migration() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("migrate_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	var old := ConfigFile.new()
	var k := ScoreStore._key("10 Old.osz", "Hard")
	old.set_value("scores", k, { "score": 800, "grade": "A", "accuracy": 0.93, "pp": 77.0 })
	old.set_value("plays", k, 3)
	old.set_value("history", k, [{ "score": 800, "grade": "A" }, { "score": 600, "grade": "B", "mode": "orbit" }])
	old.set_value("recent", "plays", [{ "score": 800, "map": "x" }, { "score": 600, "map": "x", "mode": "orbit" }])
	old.set_value("others", "10|Hard", [{ "player": "Bob", "score": 1 }])
	old.save(path)
	ScoreStore._migrated_path = ""
	_check(int(ScoreStore.best("10 Old.osz", "Hard").score) == 800, "Migration: Bestwert bleibt Mania")
	_check(ScoreStore.best("10 Old.osz", "Hard", ScoreStore.MODE_ORBIT).is_empty(), "Migration: kein Orbit-Bestwert erfunden")
	_check(is_equal_approx(ScoreStore.profile_pp(), 77.0), "Migration: pp unveraendert")
	_check(ScoreStore.play_count("10 Old.osz", "Hard") == 3, "Migration: Plays bleiben")
	_check(ScoreStore.top_scores("10 Old.osz", "Hard", 9).size() == 1, "Migration: Mania-Verlauf ohne Orbit")
	_check(ScoreStore.top_scores("10 Old.osz", "Hard", 9, ScoreStore.MODE_ORBIT).size() == 1, "Migration: Orbit-Verlauf verschoben")
	_check(ScoreStore.recent_plays(9).size() == 1 and ScoreStore.recent_plays(9, ScoreStore.MODE_ORBIT).size() == 1, "Migration: Recent getrennt")
	var after := ConfigFile.new()
	after.load(path)
	_check(int(after.get_value("meta", "schema", 0)) == ScoreStore.SCHEMA, "Migration: Schema gesetzt")
	_check((after.get_value("others", "10|Hard", []) as Array).size() == 1, "Migration: Fremd-Scores bleiben")
	_check(not ScoreStore.migrate(after), "Migration nur einmal")
	DirAccess.remove_absolute(path)
	ScoreStore.PATH = real


## Alte Arcade-Scores (vor v1.1.5): einmalig auf ScoreV1, Bestwert neu bestimmt.
func _test_legacy_rescore() -> void:
	var real := ScoreStore.PATH
	var path := real.get_base_dir().path_join("legacy_%d.cfg" % OS.get_process_id())
	ScoreStore.PATH = path
	var k := ScoreStore._key("5 Song.osz", "Hard")
	var old_best := { "score": 1497224, "accuracy": 0.9163, "grade": "A", "pp": 23.0,
		"n_max": 600, "n300": 300, "n200": 40, "n100": 60, "n50": 10, "n_miss": 20,
		"date": "2026-07-18T20:00:00" }
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 2)
	cfg.set_value("scores", k, old_best)
	cfg.set_value("history", k, [
		{ "score": 1497224, "accuracy": 0.9163, "grade": "A", "pp": 23.0, "date": "2026-07-18T20:00:00" },
		{ "score": 956161, "accuracy": 0.9812, "grade": "S", "pp": 45.0, "date": "2026-11-08T12:00:00" },
		{ "score": 504624, "accuracy": 0.8599, "grade": "B", "pp": 13.0, "date": "2026-11-07T12:00:00" }])
	cfg.set_value("others", "5|Hard", [{ "player": "Alt", "score": 1800000, "accuracy": 0.97,
		"grade": "S", "max_combo": 1, "pp": 1.0, "mods": [], "date": "2026-07-17T10:00:00" }])
	cfg.save(path)
	ScoreStore._migrated_path = ""
	var tops := ScoreStore.top_scores("5 Song.osz", "Hard", 9)
	_check(tops.size() == 3 and is_equal_approx(float(tops[0].pp), 45.0), "Alt-Score: 98-%-Lauf jetzt vorn")
	var maxed := true
	for e in tops:
		maxed = maxed and int(e.score) <= 1000000
	_check(maxed, "Alt-Score: alle <= 1.000.000")
	var leg: Dictionary = tops[1] if int(tops[1].get("legacy_score", 0)) == 1497224 else tops[2]
	_check(int(leg.get("legacy_score", 0)) == 1497224, "Alt-Score: alter Wert in legacy_score")
	var b := ScoreStore.best("5 Song.osz", "Hard")
	_check(int(b.score) == 956161 and is_equal_approx(ScoreStore.profile_pp(), 45.0), "Alt-Score: Bestwert + pp = neuer Lauf")
	var after := ConfigFile.new()
	after.load(path)
	var others: Array = after.get_value("others", "5|Hard", [])
	_check(others.size() == 1 and int(others[0].score) <= 1000000, "Alt-Score: Fremd-Score umgerechnet")
	_check(not ScoreStore.migrate(after), "Alt-Score: nur einmal")
	# Perfekter Lauf ergibt exakt das Maximum.
	_check(ScoreStore.rescore_v1({ "n_max": 500 }) == 1000000, "rescore_v1: SS = 1.000.000")
	# Fremd-Score ueber Maximum wird beim Empfang umgerechnet.
	var fe := ScoreStore.sanitize_foreign({ "score": 1500000, "accuracy": 0.95, "grade": "S",
		"max_combo": 5, "pp": 2.0, "mods": [], "date": "2026-07-18T10:00:00" }, "Alt")
	_check(int(fe.score) <= 1000000, "Fremd-Score beim Empfang umgerechnet")
	DirAccess.remove_absolute(path)
	ScoreStore.PATH = real


## Spielzeit: Startwert nur einmal, danach addieren, Modi getrennt.
func _test_playtime() -> void:
	_check(ScoreStore.playtime_ms() == -1, "Spielzeit: ungemessen = -1")
	ScoreStore.seed_playtime(60000)
	ScoreStore.seed_playtime(999999)
	_check(ScoreStore.playtime_ms() == 60000, "Spielzeit: Startwert nur einmal")
	ScoreStore.add_playtime(15000)
	_check(ScoreStore.playtime_ms() == 75000, "Spielzeit: addiert")
	ScoreStore.add_playtime(5000, ScoreStore.MODE_ORBIT)
	_check(ScoreStore.playtime_ms(ScoreStore.MODE_ORBIT) == 5000 and ScoreStore.playtime_ms() == 75000, "Spielzeit: Modi getrennt")
	var GS = load("res://scripts/game_session.gd")
	_check(GS.playtime_mode_of("res://scenes/orbit.tscn") == "orbit" 			and GS.playtime_mode_of("res://scenes/mania_3d.tscn") == "" 			and GS.playtime_mode_of("res://scenes/song_select.tscn") == null, "Spielzeit: Szenen-Modus")
