extends Control
## Demo des ResultsScreen mit Fake-Daten. --shot speichert ein Bild und beendet; --fail zeigt Fail,
## --unranked zeigt PP ohne Wertung, --lobby den Lobby-Modus.

const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/results_preview.png"


const CLIP_MD5 := "c72d6dea5503e90ba12244d54047d5e9"


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	theme = UiTheme.build_theme()
	var fail := "--fail" in args
	var unranked := "--unranked" in args
	var rs := ResultsScreen.new()
	add_child(rs)
	rs.retry_pressed.connect(func(): print("retry"))
	rs.replay_pressed.connect(func(): print("replay"))
	var exporter := ClipExporter.new()
	add_child(exporter)
	exporter.resolution = "1280x720"
	exporter.progress.connect(func(sec: float): rs.show_toast("Clip wird aufgenommen … %d s" % int(sec), true))
	exporter.finished.connect(func(ok: bool, path: String): rs.show_clip_result(ok, path, exporter.last_error))
	rs.clip_pressed.connect(func():
		print("clip")
		var md5: String = CLIP_MD5 if "--realclip" in args else "00000000000000000000000000000000"
		var out := ClipExporter.clips_dir().path_join("clip_preview.avi")
		if exporter.export_clip(md5, out):
			rs.show_toast("Clip wird aufgenommen …", true))
	rs.back_pressed.connect(func(): print("back"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offs: Array = []
	for i in 1800:
		offs.append(rng.randfn(3.5, 13.0))
	rs.show_results({
		"is_fail": fail,
		"s": {"n_max": 1210, "n300": 402, "n200": 96, "n100": 31, "n50": 7, "n_miss": 3 if not fail else 40,
			"max_combo": 842, "accuracy": 0.9667, "grade": "S", "score": 923412},
		"pp": 287.4,
		"unranked": unranked,
		"lobby": "--lobby" in args,
		"new_best": not fail,
		"title": "Preview Song",
		"artist": "Test Artist",
		"version": "Insane",
		"cover_path": _fake_cover(),
		"offsets": offs,
		"player": "VYREN",
		"date": "2026-11-06T22:37:00",
	})
	if "--donetoast" in args:
		await get_tree().create_timer(1.8).timeout
		rs.show_clip_result(true, ClipExporter.clips_dir().path_join("clip_preview.avi"))
	if "--toast" in args:
		await get_tree().create_timer(2.0).timeout
		rs.clip_pressed.emit()
		await get_tree().create_timer(0.1).timeout
	if "--shot" in args:
		if "--realclip" in args:
			await exporter.finished
			await get_tree().create_timer(0.8).timeout
		else:
			await get_tree().create_timer(2.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT_PATH)
		get_tree().quit()


func _fake_cover() -> String:
	var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
	for y in 360:
		for x in 640:
			img.set_pixel(x, y, Color.from_hsv(fmod(x / 640.0 * 0.5 + 0.55, 1.0), 0.6, 0.3 + y / 360.0 * 0.6))
	var p := "user://fake_cover.png"
	img.save_png(p)
	return ProjectSettings.globalize_path(p)
