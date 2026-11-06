extends Control

## Testszene fuer BreakOverlay. 150 BPM, Intro 0..9000 ms. --shot speichert Bilder
## (Pause mit Sekunden, dann Countdown "2" auf dem Beat). Headless: Beat-Check.

const SHOT := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/break_preview.png"
const SHOT2 := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/break_preview_count.png"
const BEAT := 400.0

var _ov: BreakOverlay
var _t := 0.0
var _manual := false


func _ready() -> void:
	get_window().theme = UiTheme.build_theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.16, 0.30)
	add_child(bg)
	_ov = BreakOverlay.new()
	add_child(_ov)
	_ov.show_break(0.0, 9000.0, BEAT, true)
	if DisplayServer.get_name() == "headless":
		var ok := true
		for k in [3, 2, 1]:
			var te := 9000.0 - float(k) * BEAT
			_ov.update(te + 1.0)
			if _ov._num.text != str(k):
				ok = false
				print("FEHLER k=", k, " text=", _ov._num.text)
			_ov.update(te - 1.0)
			if _ov._num.text == str(k):
				ok = false
				print("FEHLER zu frueh k=", k)
		print("=== BreakPreview Headless ", "OK" if ok else "FEHLER", " ===")
		get_tree().quit(0 if ok else 1)
	elif OS.get_cmdline_args().has("--shot") or OS.get_cmdline_args().has("shot"):
		_manual = true
		_ov.update(4200.0)
		await get_tree().create_timer(0.5).timeout
		_ov.update(4200.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT)
		_ov.update(9000.0 - 2.0 * BEAT + 20.0)
		await get_tree().process_frame
		_ov.update(9000.0 - 2.0 * BEAT + 20.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT2)
		print("SHOT gespeichert: " + SHOT)
		get_tree().quit(0)


func _process(dt: float) -> void:
	if _manual:
		return
	_t += dt * 1000.0
	if _t > 9500.0:
		_t = 0.0
		_ov.show_break(0.0, 9000.0, BEAT, true)
	_ov.update(_t)
