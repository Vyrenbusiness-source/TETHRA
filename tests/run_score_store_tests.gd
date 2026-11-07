extends SceneTree

## Tests fuer ScoreStore: Mods im Bestwert, alte Eintraege ohne Mods.

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

	# aufraeumen
	DirAccess.remove_absolute(ScoreStore.PATH)
	if backup != "":
		var f := FileAccess.open(ScoreStore.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)
