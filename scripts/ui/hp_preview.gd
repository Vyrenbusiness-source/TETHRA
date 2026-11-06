extends Control

## Testszene fuer HpBar. --shot (ohne '--' davor) speichert ein Bild.

const SHOT := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/hp_preview.png"
const LEVELS := [1.0, 0.7, 0.45, 0.2, 0.08]


func _ready() -> void:
	get_window().theme = UiTheme.build_theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.08, 0.16)
	add_child(bg)
	var bars: Array = []
	for i in LEVELS.size():
		var b := HpBar.new()
		b.label_text = "HP" if i % 2 == 0 else ""
		add_child(b)
		b.set_anchors_preset(Control.PRESET_CENTER_TOP)
		b.offset_left = -210.0
		b.offset_right = 210.0
		b.offset_top = 40.0 + i * 50.0
		b.offset_bottom = b.offset_top + 24.0
		b.setup(UiTheme.ACCENT)
		b.set_hp(LEVELS[i])
		bars.append(b)
	if DisplayServer.get_name() == "headless":
		for b in bars:
			b.flash_hit()
			b.flash_miss()
		await get_tree().process_frame
		await get_tree().process_frame
		print("=== HpPreview Headless OK ===")
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot") or OS.get_cmdline_args().has("shot"):
		# Treffer-Glanz auf Balken 2 mitten im Sweep einfangen
		await get_tree().create_timer(0.7).timeout
		bars[1].flash_hit()
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT)
		print("SHOT gespeichert: " + SHOT)
		get_tree().quit(0)
