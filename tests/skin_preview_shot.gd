extends Control

## Screenshot-Harness: Vorschau je eingebautem Skin. Aufruf (selbst-beendend):
##   godot --path . --position -1920,0 --audio-driver Dummy res://tests/skin_preview_shot.tscn -- --out=<dir>

func _ready() -> void:
	var out := "user://skinshots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pv := PlayfieldPreview.new()
	pv.position = Vector2(20, 20)
	add_child(pv)
	for id in ["", "builtin:Balken", "builtin:Kreise", "builtin:Pfeile"]:
		Settings.skin_2d = id
		pv.refresh()
		for i in 70:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image().get_region(Rect2i(0, 0, 300, 240))
		img.save_png(out + "/preview_" + (id.trim_prefix("builtin:") if id != "" else "Standard") + ".png")
	Settings.skin_2d = ""
	get_tree().quit()
