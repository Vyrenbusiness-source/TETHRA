extends SceneTree

## Headless-Tests: Scroll Speed wie osu!lazer (Formel, Umrechnung, Migration,
## Grenzen) und einmaliger Spielername.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_scroll_speed_tests.gd
## lazer-Quelle (ppy/osu master): DrawableManiaRuleset.ComputeScrollTime(speed)
## = MAX_TIME_RANGE / speed, MAX_TIME_RANGE = 11485, MIN_TIME_RANGE = 290 (bei 40);
## ManiaRulesetConfigManager: ScrollSpeed Default 8, Bereich 1..40.

var SettingsScript: GDScript
var _passed := 0
var _failed := 0
var _done := false
const PATH := "user://scroll_speed_test_tmp.cfg"


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== TETHRA Scroll-Speed-Tests ===")
	SettingsScript = root.get_node("/root/Settings").get_script()
	_formula()
	_conversion()
	_migration()
	_limits()
	_names()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _formula() -> void:
	_ok(is_equal_approx(SettingsScript.scroll_time_ms(1), 11485.0), "Speed 1 = 11485 ms (MAX_TIME_RANGE)")
	_ok(int(SettingsScript.scroll_time_ms(40)) == 287, "Speed 40 = 287 ms (~MIN_TIME_RANGE 290)")
	_ok(int(SettingsScript.scroll_time_ms(25)) == 459, "Speed 25 = 459 ms")
	_ok(int(SettingsScript.scroll_time_ms(8)) == 1435, "Speed 8 (lazer-Default) = 1435 ms")
	_ok(SettingsScript.scroll_value_text(25) == "25 (459 ms)", "Anzeige '25 (459 ms)'")
	_ok(SettingsScript.SCROLL_SPEED_DEFAULT == 8, "Default 8 wie lazer")
	_ok(is_equal_approx(SettingsScript.SCROLL_BASE_PREEMPT, ManiaCore.BASE_PREEMPT),
		"Basis = ManiaCore.BASE_PREEMPT")


func _conversion() -> void:
	# ManiaCore: preempt = BASE_PREEMPT / clampf(mania_scroll, 0.5, 3.0) -> exakt lazer-Zeit.
	var s = SettingsScript.new()
	for sp in [5, 8, 10, 15, 20, 25, 28]:
		s.scroll_speed = sp
		var preempt: float = ManiaCore.BASE_PREEMPT / clampf(s.mania_scroll, 0.5, 3.0)
		_ok(absf(preempt - 11485.0 / sp) < 0.01, "Speed %d: preempt %.1f ms = lazer" % [sp, preempt])
	# Rundweg Speed -> Faktor -> Speed fuer alle 40 Stufen.
	var all_ok := true
	for sp in range(1, 41):
		if SettingsScript.speed_from_mania(SettingsScript.mania_from_speed(sp)) != sp:
			all_ok = false
	_ok(all_ok, "Speed -> Faktor -> Speed fuer 1..40 verlustfrei")
	# Setter: +-0.1 (Pausenmenue) bewegt immer mindestens einen Schritt.
	s.scroll_speed = 11
	s.mania_scroll = snappedf(s.mania_scroll + 0.05, 0.05)
	_ok(s.scroll_speed == 12, "mania_scroll += 0.05 -> Speed 11 -> 12 (kein Haengen)")
	s.scroll_speed = 20
	s.mania_scroll = s.mania_scroll - 0.1
	_ok(s.scroll_speed == 19, "mania_scroll -= 0.1 -> Speed 20 -> 19")
	s.mania_scroll = 1.0
	_ok(s.scroll_speed == 10, "mania_scroll = 1.0 -> Speed 10")
	s.free()


func _migration() -> void:
	# Alte Datei: nur mania_scroll -> einmalig umrechnen, Original bleibt erhalten.
	var cases := [[1.0, 10], [0.5, 5], [3.0, 29], [1.5, 14], [2.0, 19]]
	for c in cases:
		var cfg := ConfigFile.new()
		cfg.set_value("game", "mania_scroll", c[0])
		cfg.save(PATH)
		var s = SettingsScript.new()
		s.load_settings(PATH)
		_ok(s.scroll_speed == c[1], "Migration x%.1f -> Speed %d (ist %d)" % [c[0], c[1], s.scroll_speed])
		s.save(PATH)
		var back := ConfigFile.new()
		back.load(PATH)
		_ok(int(back.get_value("game", "scroll_speed", -1)) == c[1], "  gespeichert scroll_speed %d" % c[1])
		_ok(is_equal_approx(float(back.get_value("game", "mania_scroll_legacy", -1.0)), c[0]),
			"  Originalwert x%.1f bleibt (mania_scroll_legacy)" % c[0])
		# Zweites Laden nimmt scroll_speed, rechnet NICHT erneut um.
		var s2 = SettingsScript.new()
		s2.scroll_speed = 1
		s2.load_settings(PATH)
		_ok(s2.scroll_speed == c[1], "  erneutes Laden bleibt Speed %d" % c[1])
		s.free()
		s2.free()
	# Neue Datei ohne Scroll-Eintrag -> Default 8.
	var cfg2 := ConfigFile.new()
	cfg2.set_value("game", "bg_dim", 0.0)
	cfg2.save(PATH)
	var d = SettingsScript.new()
	d.load_settings(PATH)
	_ok(d.scroll_speed == 8, "Ohne Eintrag -> Default 8")
	_ok(is_equal_approx(d.bg_dim, 0.0), "bg_dim 0 (Hintergrund aus) bleibt 0")
	d.free()


func _limits() -> void:
	for c in [[0, 1], [-5, 1], [41, 40], [99, 40], [24.6, 25], [1, 1], [40, 40]]:
		var cfg := ConfigFile.new()
		cfg.set_value("game", "scroll_speed", c[0])
		cfg.save(PATH)
		var s = SettingsScript.new()
		s.load_settings(PATH)
		_ok(s.scroll_speed == c[1], "scroll_speed %s -> %d" % [str(c[0]), c[1]])
		s.free()
	_ok(SettingsScript.clamp_scroll_speed(NAN) == 8, "NaN -> Default 8")
	_ok(SettingsScript.clamp_scroll_speed(null) == 8, "null -> Default 8")
	_ok(SettingsScript.speed_from_mania(-1.0) == 8, "Faktor <= 0 -> Default 8")
	_ok(is_equal_approx(SettingsScript.clamp_bg_dim(0.0), 0.0), "bg_dim 0 erlaubt")


func _names() -> void:
	_ok(SettingsScript.name_error("Gexanx") == "", "Name 'Gexanx' gueltig")
	_ok(SettingsScript.name_error("ab") == "", "2 Zeichen gueltig")
	_ok(SettingsScript.name_error("a") != "", "1 Zeichen ungueltig")
	_ok(SettingsScript.name_error("abcdefghijklmnopq") != "", "17 Zeichen ungueltig")
	_ok(SettingsScript.name_error("abcdefghijklmnop") == "", "16 Zeichen gueltig")
	_ok(SettingsScript.name_error("Player") != "", "'Player' ungueltig")
	_ok(SettingsScript.name_error("  player ") != "", "' player ' ungueltig")
	_ok(SettingsScript.name_error("ab\tc") != "", "Tab (Steuerzeichen) ungueltig")
	_ok(SettingsScript.name_error("ab" + String.chr(7) + "c") != "", "BEL ungueltig")
	_ok(SettingsScript.name_error("Jörg 二") == "", "Umlaut/Unicode gueltig")
	# Einmaliges Festlegen.
	var s = SettingsScript.new()
	_ok(s.can_set_name(), "Neues Profil 'Player' darf Namen setzen")
	_ok(s.set_name_once("x", PATH) != "", "Ungueltiger Name wird abgelehnt")
	_ok(s.can_set_name() and s.profile_name == "Player", "  Name bleibt 'Player'")
	_ok(s.set_name_once("  Gexanx ", PATH) == "", "Gueltiger Name gespeichert")
	_ok(s.profile_name == "Gexanx" and not s.can_set_name(), "  danach fest")
	_ok(s.set_name_once("Other", PATH) != "" and s.profile_name == "Gexanx", "Zweites Umbenennen abgelehnt")
	var back := ConfigFile.new()
	back.load(PATH)
	_ok(bool(back.get_value("profile", "name_set", false)), "settings.cfg profile/name_set=true")
	var r = SettingsScript.new()
	r.load_settings(PATH)
	_ok(r.profile_name == "Gexanx" and not r.can_set_name(), "Nach Neustart weiter fest")
	# Alte Datei mit eigenem Namen (ohne Flag) -> gilt als festgelegt.
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", "OldName")
	cfg.save(PATH)
	var o = SettingsScript.new()
	o.load_settings(PATH)
	_ok(not o.can_set_name(), "Bestehender eigener Name ist fest")
	var cfg3 := ConfigFile.new()
	cfg3.set_value("profile", "name", "Player")
	cfg3.save(PATH)
	var p = SettingsScript.new()
	p.load_settings(PATH)
	_ok(p.can_set_name(), "Bestehendes 'Player'-Profil darf einmal setzen")
	for x in [s, r, o, p]:
		x.free()


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		print("  OK   ", name)
	else:
		_failed += 1
		print("  FAIL ", name)
