extends SceneTree

## Tests fuer den Clip-Export. Ohne Argument: reine Logik (Restzeit, Replay-
## Laenge, Presets, ffmpeg-Suche). Mit "-- --integration <md5>": echter Export
## (zweiter Prozess), prueft Datei, Dauer-Gleichheit Bild/Ton (ffprobe) und
## Tempo gegen Echtzeit (--max-ratio <x>, Standard 0.6).
## Ausfuehren:
##   Godot..._console.exe --audio-driver Dummy --path . --script res://tests/run_clip_tests.gd
##   ... --script res://tests/run_clip_tests.gd -- --integration <md5>

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Clip-Tests ===")
	_test_logic()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--integration")
	if i >= 0 and i + 1 < args.size():
		var ratio := 0.6
		var r := args.find("--max-ratio")
		if r >= 0 and r + 1 < args.size():
			ratio = args[r + 1].to_float()
		await _test_integration(args[i + 1], ratio)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


func _test_logic() -> void:
	_ok(ClipExporter.eta_s(0.01, 10.0) < 0.0, "ETA: vor 5 % keine Schaetzung")
	_ok(ClipExporter.eta_s(0.5, 10.0) == 10.0, "ETA: 50 % nach 10 s -> 10 s Rest")
	_ok(is_equal_approx(ClipExporter.eta_s(0.25, 6.0), 18.0), "ETA: 25 % nach 6 s -> 18 s Rest")
	_ok(ClipExporter.PRESETS["fast"] == 30 and ClipExporter.PRESETS["smooth"] == 60, "Presets 30/60 FPS")
	_ok(ClipExporter.RESOLUTION == "1280x720", "Fenster = Viewport 1280x720")
	_ok(ClipExporter.replay_length_s("gibt_es_nicht") == 0.0, "Replay-Laenge: fehlende Datei = 0")
	var ex := ClipExporter.new()
	_ok(ex.fps == 30 and ex.convert_mp4, "Standard: 30 FPS, MP4")
	_ok(not ex.export_clip("gibt_es_nicht"), "ohne Replay kein Export")
	_ok(ex.last_error != "", "Fehlertext gesetzt")
	ex.free()
	var ff := ClipExporter.find_ffmpeg()
	print("  info ffmpeg: ", ff if ff != "" else "keins (AVI-Ergebnis)")


func _probe(path: String, entries: String) -> String:
	var out := []
	OS.execute("ffprobe", ["-v", "error", "-select_streams", entries.get_slice("|", 0), "-show_entries",
		"stream=" + entries.get_slice("|", 1), "-of", "csv=p=0", path], out, true)
	return String(out[0]).strip_edges() if out.size() > 0 else ""


func _test_integration(md5: String, max_ratio: float) -> void:
	var ex := ClipExporter.new()
	root.add_child(ex)
	var out := ClipExporter.clips_dir().path_join("test_%s.avi" % md5)
	var done := [false, false, ""]
	ex.finished.connect(func(ok: bool, path: String) -> void:
		done[0] = true
		done[1] = ok
		done[2] = path)
	var fracs := []
	ex.progress_info.connect(func(f: float, _e: float, _p: String) -> void: fracs.append(f))
	var t0 := Time.get_ticks_msec()
	_ok(ex.export_clip(md5, out), "Export gestartet")
	while not done[0] and (Time.get_ticks_msec() - t0) < 400000:
		await process_frame
	if not done[0]:
		if ex.pid > 0:
			OS.kill(ex.pid)
		print("  Zeitueberschreitung, Prozess beendet")
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	_ok(done[1], "Export fertig (%s)" % done[2])
	var path: String = done[2]
	_ok(FileAccess.file_exists(path) and FileAccess.open(path, FileAccess.READ).get_length() > 0, "Datei nicht leer")
	_ok(not FileAccess.file_exists(out.get_basename() + ".part.avi"), "keine Zwischendatei")
	_ok(fracs.size() > 0, "Fortschritt gemeldet (%d Meldungen)" % fracs.size())
	var vd := _probe(path, "v:0|duration").to_float()
	var ad := _probe(path, "a:0|duration").to_float()
	if ad <= 0.0:
		# AVI/PCM meldet keine Dauer: Samples / Rate.
		var n := _probe(path, "a:0|nb_frames").to_float()
		ad = n / 48000.0
	print("  info Wand=%.1f s  Film=%.1f s (Bild)  %.1f s (Ton)  Verhaeltnis=%.2f" % [wall, vd, ad, wall / maxf(vd, 0.1)])
	_ok(vd > 1.0 and absf(vd - ad) < 0.1, "Bild- und Tondauer gleich (Sync)")
	_ok(wall / maxf(vd, 0.1) <= max_ratio, "Export schneller als %.0f %% der Echtzeit" % (max_ratio * 100.0))
	ex.queue_free()
