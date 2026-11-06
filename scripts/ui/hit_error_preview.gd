extends Control

## Demo fuer HitErrorBar. --shot speichert ein Bild.

const SHOT := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/hit_error_preview.png"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.18)
	add_child(bg)
	var bar := HitErrorBar.new()
	bar.show_ur = true
	add_child(bar)
	bar.setup({"max": 16, "w300": 40, "w200": 73, "w100": 103, "w50": 127}, 400.0)
	bar.position = Vector2(size.x * 0.5 - 200.0, size.y * 0.5 - 18.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		bar.add_hit(rng.randfn(6.0, 28.0))
	if DisplayServer.get_name() == "headless":
		print("=== HitErrorPreview Headless OK ===")
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot") or OS.get_cmdline_args().has("shot"):
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT)
		print("SHOT gespeichert: " + SHOT)
		get_tree().quit(0)
