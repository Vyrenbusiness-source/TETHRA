extends SceneTree

## Headless-Tests fuer Spielfeld-Einstellungen (Spurbreite, 2D-Modus, Hintergrund).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_settings_tests.gd

# Kein preload: settings.gd braucht die Autoloads (SyncClock) zum Kompilieren.
var SettingsScript: GDScript
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
	print("=== TETHRA Settings-Tests ===")
	SettingsScript = root.get_node("/root/Settings").get_script()
	var path := "user://settings_test_tmp.cfg"
	# Roundtrip: Werte schreiben, in frische Instanz laden.
	var a = SettingsScript.new()
	a.lane_spacing = 0.75
	a.playfield_2d = true
	a.bg_dim = 0.8
	a.bg_blur = false
	a.save(path)
	var b = SettingsScript.new()
	b.load_settings(path)
	_ok(is_equal_approx(b.lane_spacing, 0.75), "Roundtrip lane_spacing 0.75")
	_ok(b.playfield_2d == true, "Roundtrip playfield_2d an")
	_ok(is_equal_approx(b.bg_dim, 0.8), "Roundtrip bg_dim 0.8")
	_ok(b.bg_blur == false, "Roundtrip bg_blur aus")
	# Standardwerte ohne Eintrag.
	var c = SettingsScript.new()
	_ok(is_equal_approx(c.lane_spacing, 1.0) and not c.playfield_2d \
			and is_equal_approx(c.bg_dim, 0.3) and c.bg_blur, "Standardwerte 100 % / 3D / 30 % / Blur an")
	# Kaputte/ausserhalb liegende Werte aus der Datei werden begrenzt.
	var cfg := ConfigFile.new()
	cfg.set_value("game", "lane_spacing", 3.0)
	cfg.set_value("game", "bg_dim", -2.0)
	cfg.save(path)
	var d = SettingsScript.new()
	d.load_settings(path)
	_ok(is_equal_approx(d.lane_spacing, 1.2), "lane_spacing 3.0 -> 1.2")
	_ok(is_equal_approx(d.bg_dim, 0.0), "bg_dim -2 -> 0")
	# Grenzen + 5er-Raster.
	_ok(is_equal_approx(SettingsScript.clamp_lane_spacing(0.1), 0.7), "clamp 0.1 -> 0.7")
	_ok(is_equal_approx(SettingsScript.clamp_lane_spacing(0.83), 0.85), "clamp 0.83 -> 0.85")
	_ok(is_equal_approx(SettingsScript.clamp_lane_spacing(NAN), 1.0), "clamp NaN -> 1.0")
	_ok(is_equal_approx(SettingsScript.clamp_bg_dim(1.5), 1.0), "bg_dim 1.5 -> 1.0")
	_ok(is_equal_approx(SettingsScript.clamp_bg_dim(0.32), 0.3), "bg_dim 0.32 -> 0.3")
	# Notengroesse: bis 85 % voll, darunter mitskalieren; Nachbarnoten beruehren sich nie.
	_ok(is_equal_approx(SettingsScript.lane_note_scale(1.2), 1.0), "Note 120 % = voll")
	_ok(is_equal_approx(SettingsScript.lane_note_scale(0.85), 1.0), "Note 85 % = voll")
	var k := 0.7
	var gap := 1.7 * k  # Spurabstand bei RAIL_X 0.85 / 2.55
	_ok(1.12 * SettingsScript.lane_note_scale(k) < gap, "70 %: Note schmaler als Spurabstand")
	for s in [a, b, c, d]:
		s.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		print("  OK   ", name)
	else:
		_failed += 1
		print("  FAIL ", name)
