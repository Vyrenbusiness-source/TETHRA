extends Control

## Testszene fuer PauseMenu. --shot (ohne '--' davor) speichert ein Bild.

const SHOT := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/pause_preview.png"


func _ready() -> void:
	get_window().theme = UiTheme.build_theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.16, 0.30)
	add_child(bg)
	var menu := PauseMenu.new()
	add_child(menu)
	menu.resume_pressed.connect(func(): print("resume"); menu.open({}))
	menu.restart_pressed.connect(func(): print("restart"))
	menu.quit_pressed.connect(func(): print("quit"))
	menu.open({"title": "Camellia - Example Song [Hard 4K]", "progress": 0.42,
		"score": 482310, "acc": 96.84})
	if DisplayServer.get_name() == "headless":
		print("=== PausePreview Headless OK ===")
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot") or OS.get_cmdline_args().has("shot"):
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT)
		print("SHOT gespeichert: " + SHOT)
		get_tree().quit(0)
