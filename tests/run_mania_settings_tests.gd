extends SceneTree

## Headless-Tests: 2D-Spielfeld-Optionen wie osu!mania (Grenzwerte, Speichern/Laden,
## CLI ohne Speichern, Mods fuer Scores, Layout-Geometrie in Playfield2D, Masken).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mania_settings_tests.gd

const PATH := "user://mania_settings_test_tmp.cfg"

var SettingsScript: GDScript
var S: Node   ## Autoload (Playfield2D liest Settings direkt)
var _saved: Dictionary = {}
var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== TETHRA Mania-2D-Settings-Tests ===")
	S = root.get_node("/root/Settings")
	SettingsScript = S.get_script()
	for n in SettingsScript.LAYOUT_2D_KEYS:
		_saved[n] = S.get(n)
	_limits()
	_save_load()
	_cli()
	_mods()
	_layout()
	_mask()
	_constant_speed()
	for n in _saved:
		S.set(n, _saved[n])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(c: bool, msg: String) -> void:
	if c:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _limits() -> void:
	var c := SettingsScript.clamp_2d_option
	_ok(c.call("hit_position_2d", 100) == 240, "HitPosition unten begrenzt (240 wie osu!)")
	_ok(c.call("hit_position_2d", 999) == 480, "HitPosition oben begrenzt (480)")
	_ok(c.call("hit_position_2d", "402.4") == 402, "HitPosition aus Text gerundet")
	_ok(c.call("hit_position_2d", NAN) == 402, "NaN -> Standard 402")
	_ok(c.call("column_spacing_2d", -5) == 0 and c.call("column_spacing_2d", 99) == 40, "Spaltenabstand 0..40")
	_ok(c.call("stage_pos_2d", 7) == 2 and c.call("stage_pos_2d", -1) == 0, "Position 0..2")
	_ok(is_equal_approx(c.call("stage_scale_2d", 0.1), 0.5) and is_equal_approx(c.call("stage_scale_2d", 3.0), 1.5),
			"Skalierung 50..150 %")
	_ok(is_equal_approx(c.call("stage_scale_2d", 0.83), 0.85), "Skalierung 5-%-Raster")
	_ok(c.call("judge_pos_2d", -3) == 0 and c.call("combo_pos_2d", 600) == 480, "Judgement/Kombo 0..480")
	_ok(c.call("mod_vis_2d", 9) == 3 and c.call("mod_vis_2d", -2) == 0, "Sicht-Mod 0..3")
	_ok(c.call("cover_pct_2d", 5) == 20 and c.call("cover_pct_2d", 95) == 80, "Cover 20..80 % (lazer)")
	_ok(c.call("scroll_up_2d", "1") == true and c.call("scroll_up_2d", "0") == false, "Bool aus Text")
	_ok(c.call("skin_values_2d", []) == true, "Ungueltiger Typ -> Standard")
	_ok(SettingsScript.default_2d_option("skin_values_2d") == true, "Standard: Skin-Werte an (wie bisher)")
	_ok(SettingsScript.default_2d_option("hit_position_2d") == 402, "Standard HitPosition 402 (osu!)")


func _save_load() -> void:
	var s = SettingsScript.new()
	s.scroll_up_2d = true
	s.skin_values_2d = false
	s.hit_position_2d = 300
	s.column_spacing_2d = 12
	s.stage_pos_2d = 0
	s.stage_scale_2d = 0.75
	s.judge_pos_2d = 250
	s.combo_pos_2d = 90
	s.keys_under_notes_2d = true
	s.hit_line_2d = false
	s.mod_vis_2d = 3
	s.cover_pct_2d = 65
	s.cover_from_bottom_2d = true
	s.mod_constant = true
	s.save(PATH)
	var t = SettingsScript.new()
	t.load_settings(PATH)
	var same := true
	for n in SettingsScript.LAYOUT_2D_KEYS:
		if t.get(n) != s.get(n):
			same = false
			print("    verschieden: ", n, " ", t.get(n), " != ", s.get(n))
	_ok(same, "Alle 2D-Optionen ueberleben Speichern/Laden")
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	_ok(cfg.get_value("mods", "vis_2d", -1) == 3 and cfg.get_value("mods", "constant_speed", false) == true,
			"Mods in [mods] gespeichert")
	# Datei mit Unsinn -> geklemmt.
	cfg.set_value("game", "hit_position_2d", 5000)
	cfg.set_value("mods", "cover_pct", "abc")
	cfg.save(PATH)
	var u = SettingsScript.new()
	u.load_settings(PATH)
	_ok(u.hit_position_2d == 480, "Unsinn in Datei geklemmt (HitPosition)")
	_ok(u.cover_pct_2d == 20, "Unsinn in Datei geklemmt (Cover)")
	# Alte Datei ohne Schluessel -> Standardwerte.
	var old := ConfigFile.new()
	old.set_value("game", "skin_2d", "")
	old.save(PATH)
	var v = SettingsScript.new()
	v.load_settings(PATH)
	_ok(v.skin_values_2d == true and v.scroll_up_2d == false and v.mod_vis_2d == 0 and v.stage_scale_2d == 1.0,
			"Alte settings.cfg -> Standardwerte")
	s.free()
	t.free()
	u.free()
	v.free()


func _cli() -> void:
	var s = SettingsScript.new()
	s.hit_position_2d = 402
	s.apply_cli_2d(PackedStringArray(["--up", "--hitpos=300", "--cover=70", "--cover-bottom",
			"--colspace=8", "--stagepos=right", "--stagescale=80", "--skinvals=0", "--constant"]))
	_ok(s.scroll_up_2d and s.hit_position_2d == 300 and s.column_spacing_2d == 8, "CLI setzt Werte")
	_ok(s.mod_vis_2d == 3 and s.cover_pct_2d == 70 and s.cover_from_bottom_2d, "CLI --cover schaltet Cover ein")
	_ok(s.stage_pos_2d == 2 and is_equal_approx(s.stage_scale_2d, 0.8) and not s.skin_values_2d and s.mod_constant,
			"CLI Position/Skalierung/Skin-Werte/Konstant")
	s.save(PATH)
	var t = SettingsScript.new()
	t.load_settings(PATH)
	_ok(not t.scroll_up_2d and t.hit_position_2d == 402 and t.mod_vis_2d == 0 and t.skin_values_2d
			and not t.mod_constant, "CLI-Werte werden nie gespeichert")
	s.hit_position_2d = 350   # im Spiel geaendert -> wird gespeichert
	s.save(PATH)
	t.load_settings(PATH)
	_ok(t.hit_position_2d == 350, "Spaeter geaenderter Wert wird gespeichert")
	s.free()
	t.free()


func _mods() -> void:
	var s = SettingsScript.new()
	s.mod_vis_2d = 2
	s.mod_constant = true
	var m: Dictionary = s.extra_mods(true)
	_ok(m.get("HD") == true and m.get("FI") == false and m.get("CO") == false and m.get("CS") == true,
			"Mods-Dict: HD + CS")
	_ok(not s.extra_mods(false).get("HD", false) and s.extra_mods(false).get("CS") == true,
			"Sicht-Mods nur im 2D-Modus")
	s.mod_vis_2d = 3
	s.cover_pct_2d = 40
	m = s.extra_mods(true)
	_ok(m.get("CO") == true and m.get("CO_pct") == 40, "Cover mit Anteil")
	var gm := {"SV": false, "NF": true}
	gm.merge(s.extra_mods(true), true)
	_ok(gm.get("NF") == true and gm.get("CO") == true, "Merge in GameSession.mods behaelt SV/NF")
	_ok(ManiaCore.mod_multiplier(gm) == ManiaCore.mod_multiplier({"NF": true}),
			"Neue Mods aendern den Score-Multiplikator nicht (lazer 1.0)")
	var hud = load("res://scripts/gameplay3d/mania_3d.gd")
	var txt: String = hud.mods_hud_text({"NF": true, "HD": true, "CS": true})
	_ok(txt.contains("NF") and txt.contains("Hidden"), "HUD-Text listet Mods: " + txt)
	_ok(hud.mods_hud_text({"SV": false, "NF": false}) == "", "Ohne Mods kein HUD-Text")
	s.free()


func _pf() -> Playfield2D:
	var pf := Playfield2D.new()
	pf.setup(4, 1.0, 3.0, -46.0, PackedStringArray(["D", "F", "J", "K"]), Color.WHITE)
	pf.preview_size = Vector2(1920, 1080)
	return pf


func _layout() -> void:
	S.skin_values_2d = true
	S.scroll_up_2d = false
	S.stage_scale_2d = 1.0
	S.stage_pos_2d = 1
	S.column_spacing_2d = 0
	var pf := _pf()
	_ok(is_equal_approx(pf.line_y(), 1080.0 * 0.86), "Skin-Werte an: eingebaute Linie bei 86 %")
	var w0 := pf.field_rect().size.x
	S.skin_values_2d = false
	S.hit_position_2d = 240
	_ok(is_equal_approx(pf.line_y(), 540.0), "Eigene Trefferposition 240 = Bildmitte")
	S.column_spacing_2d = 10
	var gap := 10.0 * 1080.0 / 480.0
	_ok(is_equal_approx(pf.field_rect().size.x, w0 + 3.0 * gap), "Spaltenabstand verbreitert die Buehne um 3 Luecken")
	_ok(is_equal_approx(pf._bx(pf.field_rect(), 1) - pf._bx(pf.field_rect(), 0), pf.col_width() + gap),
			"Spalte 2 beginnt nach Breite + Abstand")
	S.stage_pos_2d = 0
	var left := pf.field_rect().position.x
	S.stage_pos_2d = 2
	var right := pf.field_rect().end.x
	_ok(is_equal_approx(left, 136.0 * 1080.0 / 480.0), "Links = osu! ColumnStart 136")
	_ok(is_equal_approx(1920.0 - right, left), "Rechts gespiegelt")
	S.stage_pos_2d = 1
	S.skin_values_2d = true
	S.scroll_up_2d = true
	_ok(is_equal_approx(pf.screen_line_y(), 1080.0 * 0.14), "Scroll nach oben: Linie oben gespiegelt")
	S.scroll_up_2d = false
	S.stage_scale_2d = 0.5
	var fr := pf.screen_field_rect()
	_ok(is_equal_approx(fr.end.y, 1080.0) and is_equal_approx(fr.size.y, 540.0), "Skalierung 50 %: um die Unterkante")
	_ok(is_equal_approx(fr.get_center().x, pf.field_rect().get_center().x), "Skalierung haelt die Feldmitte")
	S.stage_scale_2d = 1.0
	S.skin_values_2d = false
	S.judge_pos_2d = 240
	S.combo_pos_2d = 120
	_ok(is_equal_approx(pf.judge_y(), 540.0) and is_equal_approx(pf.combo_y(), 270.0), "Eigene Judgement-/Kombo-Hoehe")
	S.keys_under_notes_2d = true
	_ok(pf._keys_under(), "Tasten unter den Noten (eigener Wert)")
	S.skin_values_2d = true
	_ok(not pf._keys_under(), "Skin-Werte: eingebauter Look Tasten ueber den Noten")
	pf.free()


func _mask() -> void:
	S.skin_values_2d = true
	var pf := _pf()
	S.mod_vis_2d = 0
	pf._update_mask()
	_ok(pf.mask_alpha(10.0) == 1.0, "Ohne Mod keine Maske")
	S.mod_vis_2d = 1   # FadeIn: oben verdeckt
	pf.set_combo(0)
	pf._update_mask()
	_ok(pf.mask_alpha(1.0) == 0.0 and pf.mask_alpha(pf.line_y() - 1.0) == 1.0, "FadeIn: oben unsichtbar, an der Linie sichtbar")
	S.mod_vis_2d = 2   # Hidden: an der Linie verdeckt
	pf._update_mask()
	_ok(pf.mask_alpha(1.0) == 1.0 and pf.mask_alpha(pf.line_y() - 1.0) == 0.0, "Hidden: oben sichtbar, an der Linie weg")
	var f0 := pf.cover_fraction()
	pf.set_combo(1000)
	_ok(is_equal_approx(f0, 0.16) and is_equal_approx(pf.cover_fraction(), 0.40), "Hidden 16 % -> 40 % mit der Kombo")
	S.mod_vis_2d = 3
	S.cover_pct_2d = 50
	S.cover_from_bottom_2d = false
	pf._update_mask()
	var ly := pf.line_y()
	_ok(pf.mask_alpha(ly * 0.3) == 0.0 and pf.mask_alpha(ly * 0.6) == 1.0, "Cover 50 % von oben")
	S.cover_from_bottom_2d = true
	pf._update_mask()
	_ok(pf.mask_alpha(ly * 0.3) == 1.0 and pf.mask_alpha(ly * 0.8) == 0.0, "Cover 50 % von unten")
	var sl: Array = pf._mask_slices(0.0, ly)
	var vis := 0.0
	for s in sl:
		vis += float(s[1]) - float(s[0])
	_ok(sl.size() > 2 and vis < ly * 0.6, "Maske zerlegt Flaechen in weiche Streifen")
	S.mod_vis_2d = 0
	pf.free()


func _constant_speed() -> void:
	var sm := ScrollMap.new()
	sm.build([], 60000.0)
	_ok(is_equal_approx(sm.position(12345.0), 12345.0) and sm.is_monotone(), "Konstant: position(t) == t")
