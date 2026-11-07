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

	# aufraeumen
	DirAccess.remove_absolute(ScoreStore.PATH)
	if backup != "":
		var f := FileAccess.open(ScoreStore.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)
