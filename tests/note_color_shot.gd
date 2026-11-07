extends Control

## Screenshot-Harness: NoteColorPicker in 3D/2D, auto und lanes. Aufruf (selbst-beendend):
##   godot --path . --position -1920,0 --audio-driver Dummy res://tests/note_color_shot.tscn -- --out=<dir>

func _ready() -> void:
	var out := "user://notecolorshots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	NoteColors.path = "user://note_colors_shot.cfg"
	NoteColors.reload()
	Settings.skin_2d = ""
	theme = UiTheme.build_theme()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var p := NoteColorPicker.new()
	p.position = Vector2(20, 20)
	add_child(p)
	var steps := [["3d_auto", false, "auto", ""], ["3d_neon", false, "lanes", "neon"],
			["3d_classic", false, "lanes", "classic"], ["3d_snap", false, "snap", ""],
			["2d_lanes", true, "lanes", "pastel"]]
	for s in steps:
		var is_2d: bool = s[1]
		NoteColors.set_mode(is_2d, s[2])
		if s[3] != "":
			NoteColors.apply_preset(is_2d, s[3])
		p._is_2d = is_2d
		p._sync()
		for i in 40:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().get_region(Rect2i(0, 0, 520, 560)) \
				.save_png(out + "/picker_" + s[0] + ".png")
	DirAccess.remove_absolute(NoteColors.path)
	get_tree().quit()
