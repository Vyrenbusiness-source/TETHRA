extends SceneTree

## Tests Clip-Export fuer Trace und Zeitraffer: Parameter und Pfade, ohne echte Aufnahme.
##   Godot..._console.exe --audio-driver Dummy --path . --script res://tests/run_clip_trace_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Clip-Trace-Tests ===")
	_ok(ClipExporter.supports_mode("trace"), "supports_mode trace")
	_ok(ClipExporter.supports_mode("trace_last"), "supports_mode trace_last")
	_ok(ClipExporter.supports_mode("mania") and ClipExporter.supports_mode("orbit"), "mania/orbit weiter ok")
	_ok(not ClipExporter.supports_mode("unbekannt"), "unbekannter Modus nicht unterstuetzt")
	_ok(ClipExporter.scene_for_mode("trace") == "res://scenes/trace.tscn", "Szene trace")
	_ok(ClipExporter.scene_for_mode("trace_last") == "res://scenes/trace.tscn", "Szene trace_last")
	_ok(ClipExporter.scene_for_mode("orbit") == "res://scenes/orbit.tscn", "Szene orbit")
	_ok(FileAccess.file_exists(ClipExporter.scene_for_mode("trace")), "Trace-Szene existiert")
	var full := ClipExporter.default_out_path("abc")
	var tl := ClipExporter.default_out_path("abc", "timelapse")
	_ok(full.get_file() == "clip_abc.avi", "Pfad clip_<md5>.avi")
	_ok(tl.get_file() == "timelapse_abc.avi", "Pfad timelapse_<md5>.avi")
	_ok(ClipExporter.TIMELAPSE_S == 8.0 and ClipExporter.TIMELAPSE_SIZE == 1080, "Zeitraffer 8 s, 1080")
	_ok(is_equal_approx(ClipExporter.timelapse_audio_start_s(100.0), 35.0), "Audiostart 35 %")
	_ok(is_equal_approx(ClipExporter.timelapse_audio_start_s(10.0), 2.0), "Audiostart passt in kurzen Film")
	_ok(ClipExporter.timelapse_audio_start_s(5.0) == 0.0, "Audiostart bei Film < 8 s = 0")
	var a := ClipExporter.timelapse_args("in.avi", "out.mp4", 80.0)
	var joined := " ".join(a)
	_ok(joined.contains("setpts=0.100000*PTS"), "Raffungsfaktor 8/80")
	_ok(joined.contains("scale=1080:1080") and joined.contains("crop="), "Quadrat 1080 zugeschnitten")
	_ok(joined.contains("atrim=start=28.000:duration=8.000"), "Musikausschnitt 8 s ab 28 s")
	_ok(a.has("-t") and a[a.find("-t") + 1] == "8.000", "Ausgabe auf 8 s begrenzt")
	_ok(a[a.size() - 1] == "out.mp4" and a[a.find("-i") + 1] == "in.avi", "Ein-/Ausgabe")
	_ok(is_equal_approx(ClipExporter.parse_duration_s("  Duration: 00:01:34.42, start: 0"), 94.42), "ffmpeg-Dauer parsen")
	_ok(ClipExporter.parse_duration_s("nix") == 0.0, "ffmpeg-Dauer fehlt = 0")
	var ex := ClipExporter.new()
	_ok(not ex.export_clip("gibt_es_nicht", "", "trace"), "trace ohne Replay: kein Export")
	_ok(ex.last_error != "", "Fehlertext gesetzt")
	_ok(not ex.export_clip("x", "", "rally"), "rally nicht unterstuetzt")
	_ok(ex.last_error.contains("rally"), "Fehlertext nennt Modus")
	if ClipExporter.find_ffmpeg() != "":
		_ok(not ex.export_timelapse("gibt_es_nicht"), "Zeitraffer ohne Replay: kein Export")
		_ok(ex.style == "timelapse", "Stil timelapse gesetzt")
		ex.export_clip("gibt_es_nicht", "", "trace")
		_ok(ex.style == "full", "export_clip setzt Stil zurueck")
	ex.free()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)
