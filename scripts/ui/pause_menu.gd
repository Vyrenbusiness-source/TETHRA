class_name PauseMenu
extends Control

## Pause-Menue (Glas-Panel auf abgedunkeltem Hintergrund). Der Host
## (mania_3d) haelt das Spiel an und startet bei resume_pressed den 3-2-1-
## Countdown. Offset/Scroll-Speed werden direkt in Settings geschrieben.
## open(info): title, progress (0..1), score (int), acc (Prozent), difficulty.

signal resume_pressed
signal restart_pressed
signal quit_pressed

var _dim: ColorRect
var _panel: GlassPanel
var _title: Label
var _song: Label
var _bar: ProgressBar
var _stats: Label
var _offset_val: Label
var _scroll_val: Label
var _btn_resume: Button
var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = GlassPanel.new(18.0, 28, 0.7)
	_panel.custom_minimum_size = Vector2(420, 480)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add(vb)

	_title = Label.new()
	_title.text = "PAUSE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_font_override("font", UiTheme.heading_font(4))
	_title.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_title)

	_song = Label.new()
	_song.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_song.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_song.add_theme_font_size_override("font_size", 14)
	_song.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(_song)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	vb.add_child(_bar)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.add_theme_color_override("font_color", UiTheme.ACCENT)
	vb.add_child(_stats)

	vb.add_child(Control.new())
	_btn_resume = _button("Fortsetzen", true, func(): _resume())
	vb.add_child(_btn_resume)
	vb.add_child(_button("Neustart", false, func(): restart_pressed.emit()))
	vb.add_child(_button("Song-Browser", false, func(): quit_pressed.emit()))

	vb.add_child(UiTheme.section_label("Schnelleinstellungen"))
	_offset_val = Label.new()
	vb.add_child(_stepper("Offset", _offset_val, -5.0, 5.0, func(d: float): _step_offset(d)))
	_scroll_val = Label.new()
	vb.add_child(_stepper("Scroll-Speed", _scroll_val, -0.1, 0.1, func(d: float): _step_scroll(d)))


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	UiTheme.style_button(b, primary)
	return b


## Zeile: Label | - | Wert | +. minus/plus rufen cb(+-step).
func _stepper(text: String, val: Label, minus: float, plus: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(l)
	var bm := _button("-", false, func(): cb.call(minus))
	bm.custom_minimum_size = Vector2(44, 36)
	row.add_child(bm)
	val.custom_minimum_size = Vector2(84, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(val)
	var bp := _button("+", false, func(): cb.call(plus))
	bp.custom_minimum_size = Vector2(44, 36)
	row.add_child(bp)
	return row


func _step_offset(d: float) -> void:
	Settings.offset_ms = clampf(Settings.offset_ms + d, -300.0, 300.0)
	Settings.save()
	_refresh_values()


func _step_scroll(d: float) -> void:
	Settings.mania_scroll = clampf(snappedf(Settings.mania_scroll + d, 0.05), 0.5, 3.0)
	Settings.save()
	_refresh_values()


func _refresh_values() -> void:
	_offset_val.text = "%+.0f ms" % Settings.offset_ms
	_scroll_val.text = "%.2fx" % Settings.mania_scroll


func open(info: Dictionary = {}) -> void:
	_song.text = str(info.get("title", ""))
	_bar.value = clampf(float(info.get("progress", 0.0)), 0.0, 1.0)
	_stats.text = "%d   |   %.2f%%" % [int(info.get("score", 0)), float(info.get("acc", 100.0))]
	_refresh_values()
	visible = true
	modulate.a = 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	_btn_resume.grab_focus()


func close() -> void:
	if _tween != null:
		_tween.kill()
	visible = false


func _resume() -> void:
	close()
	resume_pressed.emit()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_resume()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		accept_event()
		_resume()
