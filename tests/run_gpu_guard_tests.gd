extends SceneTree

## Headless-Tests fuer den GPU-Waechter (scripts/core/gpu_guard.gd).
## Schreibt nur in einen Temp-Ordner, nie in den Spielordner.

const G := preload("res://scripts/core/gpu_guard.gd")
var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _initialize() -> void:
	var dir := OS.get_temp_dir().path_join("tethra_gpu_guard_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var marker := dir.path_join("running.marker")
	var ov := dir.path_join("override.cfg")

	# Marker-Logik
	_check(not G.evaluate_start(marker), "ohne Marker: kein Absturz")
	G.write_marker(marker)
	_check(G.evaluate_start(marker), "Marker da: Absturz erkannt")
	G.clear_marker(marker)
	_check(not G.evaluate_start(marker), "sauberes Ende loescht Marker")
	G.clear_marker(marker)
	_check(true, "Marker doppelt loeschen ist harmlos")

	# override.cfg
	_check(G.write_override(ov), "override.cfg geschrieben")
	var cfg := ConfigFile.new()
	_check(cfg.load(ov) == OK, "override.cfg ist gueltiges ConfigFile")
	_check(cfg.get_value("rendering", "renderer/rendering_method") == "gl_compatibility", "Renderer gl_compatibility")
	_check(cfg.get_value("rendering", "gl_compatibility/driver.windows") == "opengl3", "OpenGL-Treiber opengl3")
	G.remove_override(ov)
	_check(not FileAccess.file_exists(ov), "override.cfg entfernt")
	G.remove_override(ov)

	# Schutz: im Editor/Test-Lauf nie override.cfg neben der exe schreiben
	_check(not G.can_write_override(), "Editor/Test: can_write_override false")
	_check(not G.override_path().begins_with(ProjectSettings.globalize_path("res://")) or not G.can_write_override(),
		"override.cfg nie im Projektordner")

	# Qualitaet im sicheren Modus
	_check(G.effective_quality(4, true) == 1, "sicher: Extrem -> 2x MSAA")
	_check(G.effective_quality(0, true) == 0, "sicher: Niedrig bleibt")
	_check(G.effective_quality(3, false) == 3, "normal: unveraendert")

	# Sichere Standardwerte neuer Spieler (Quelltext-Pruefung: settings.gd ist
	# im -s-Modus wegen der Autoload-Namen nicht ladbar).
	var src := FileAccess.get_file_as_string("res://scripts/settings.gd")
	_check(src.contains("var graphics_quality: int = 2"), "Default graphics_quality 2 (4x MSAA)")
	_check(src.contains('"graphics_quality", 2)'), "Lade-Default graphics_quality 2")
	_check(src.contains("var fps_mode: int = 2"), "Default FPS mit Cap (240), nicht Unbegrenzt")
	_check(src.contains('"fps_mode", 2)'), "Lade-Default fps_mode 2")
	_check(not src.contains("scaling_3d_scale = 1.5") or src.contains("4:
				# Extrem"), "Supersampling nur in Stufe Extrem")

	DirAccess.remove_absolute(dir)
	print("=== GPU-Guard-Tests: %s ===" % ("OK" if _failed == 0 else "%d FEHLER" % _failed))
	quit(1 if _failed > 0 else 0)
