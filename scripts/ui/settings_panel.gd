class_name SettingsPanel
extends Control

## Einstellungen — schlank wie osu!mania, in drei klaren Sektionen:
## GAMEPLAY (Scroll, Tasten, Offset), AUDIO (Lautstaerke, Hitsounds),
## ANZEIGE (Effekte, Vollbild). Profilname/-bild wohnen in der Profil-Ansicht.

signal closed

const COL_DIM := Color(0.55, 0.58, 0.66)
const COL_SECTION := Color(0.45, 0.8, 1.0)

var _capturing := 0   # 0 = keine Aufnahme, 3..6 = Lane 1-4
var _lane_btns: Array[Button] = []
var _offset_value: Label
var _vol_value: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.75)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# Kopfzeile mit Schliessen-Knopf.
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "EINSTELLUNGEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UiTheme.heading_font(3))
	title.add_theme_font_size_override("font_size", 24)
	head.add_child(title)
	var close_x := Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(38, 38)
	UiTheme.style_button(close_x)
	close_x.pressed.connect(_close)
	head.add_child(close_x)

	# ------------------------------- GAMEPLAY -------------------------------
	_section(vb, "GAMEPLAY")

	var scroll_slider := HSlider.new()
	scroll_slider.min_value = 0.5
	scroll_slider.max_value = 3.0
	scroll_slider.step = 0.1
	scroll_slider.value = Settings.mania_scroll
	var scroll_value := Label.new()
	scroll_value.custom_minimum_size = Vector2(66, 0)
	scroll_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scroll_value.text = "x%.1f" % Settings.mania_scroll
	scroll_slider.value_changed.connect(func(v):
		Settings.mania_scroll = v
		scroll_value.text = "x%.1f" % v)
	_row(vb, "Scroll-Speed", scroll_slider, scroll_value)

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 8)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		var lane := i
		b.pressed.connect(func(): _start_capture(3 + lane))
		lane_row.add_child(b)
		_lane_btns.append(b)
	_row(vb, "Tasten 1-4", lane_row, null)

	var offset_slider := HSlider.new()
	offset_slider.min_value = -200.0
	offset_slider.max_value = 200.0
	offset_slider.step = 1.0
	offset_slider.value = Settings.offset_ms
	_offset_value = Label.new()
	_offset_value.custom_minimum_size = Vector2(66, 0)
	_offset_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	offset_slider.value_changed.connect(func(v):
		Settings.offset_ms = v
		Settings.apply()
		_offset_value.text = "%+d ms" % int(v))
	_row(vb, "Audio-Offset", offset_slider, _offset_value)

	# -------------------------------- AUDIO ---------------------------------
	_section(vb, "AUDIO")

	var vol_slider := HSlider.new()
	vol_slider.min_value = -30.0
	vol_slider.max_value = 0.0
	vol_slider.step = 1.0
	vol_slider.value = Settings.volume_db
	_vol_value = Label.new()
	_vol_value.custom_minimum_size = Vector2(66, 0)
	_vol_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_slider.value_changed.connect(func(v):
		Settings.volume_db = v
		Settings.apply()
		_vol_value.text = "%d dB" % int(v))
	_row(vb, "Lautstaerke", vol_slider, _vol_value)

	var enh := CheckButton.new()
	enh.button_pressed = Settings.audio_enhance
	enh.toggled.connect(func(on):
		Settings.audio_enhance = on
		Settings.apply())
	_row(vb, "Klang-Boost (Bass)", enh, null)

	var hs := CheckButton.new()
	hs.button_pressed = Settings.hitsounds
	hs.toggled.connect(func(on): Settings.hitsounds = on)
	_row(vb, "Hitsounds", hs, null)

	var hs_slider := HSlider.new()
	hs_slider.min_value = 0.0
	hs_slider.max_value = 1.0
	hs_slider.step = 0.05
	hs_slider.value = Settings.hitsound_volume
	var hs_value := Label.new()
	hs_value.custom_minimum_size = Vector2(66, 0)
	hs_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hs_value.text = "%d %%" % int(Settings.hitsound_volume * 100.0)
	hs_slider.value_changed.connect(func(v):
		Settings.hitsound_volume = v
		hs_value.text = "%d %%" % int(v * 100.0))
	_row(vb, "Hitsound-Lautstaerke", hs_slider, hs_value)

	# ------------------------------- ANZEIGE --------------------------------
	_section(vb, "ANZEIGE")

	var fx := OptionButton.new()
	fx.add_item("Aus", 0)
	fx.add_item("Dezent", 1)
	fx.add_item("Voll", 2)
	fx.select(Settings.tunnel_intensity)
	fx.custom_minimum_size = Vector2(0, 38)
	fx.item_selected.connect(func(i): Settings.tunnel_intensity = i)
	_row(vb, "Effekt-Intensitaet", fx, null)

	var gfx := OptionButton.new()
	gfx.add_item("Niedrig", 0)
	gfx.add_item("Mittel (2x AA)", 1)
	gfx.add_item("Hoch (4x AA)", 2)
	gfx.add_item("Ultra (8x AA)", 3)
	gfx.add_item("Extrem (8x AA + SSAA)", 4)
	gfx.select(Settings.graphics_quality)
	gfx.custom_minimum_size = Vector2(0, 38)
	gfx.item_selected.connect(func(i):
		Settings.graphics_quality = i
		Settings.apply())
	_row(vb, "Grafik-Qualitaet", gfx, null)

	var fps := OptionButton.new()
	fps.add_item("VSync", 0)
	fps.add_item("Unlimited", 1)
	fps.add_item("240 FPS", 2)
	fps.add_item("360 FPS", 3)
	fps.add_item("480 FPS", 4)
	fps.select(Settings.fps_mode)
	fps.custom_minimum_size = Vector2(0, 38)
	fps.item_selected.connect(func(i):
		Settings.fps_mode = i
		Settings.apply())
	_row(vb, "FPS-Limit", fps, null)

	var lg := CheckButton.new()
	lg.button_pressed = Settings.lane_glow
	lg.toggled.connect(func(on): Settings.lane_glow = on)
	_row(vb, "Spur-Aufleuchten (Taste)", lg, null)

	var fs := CheckButton.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.fullscreen = on; Settings.apply())
	_row(vb, "Vollbild (F11)", fs, null)

	# Fusszeile.
	var save := Button.new()
	save.text = "Speichern & Schliessen"
	save.custom_minimum_size = Vector2(0, 46)
	UiTheme.style_button(save, true)
	save.pressed.connect(_close)
	vb.add_child(save)

	_refresh_labels()


## Sektions-Kopf: kleine Versal-Zeile + Trennlinie.
func _section(vb: VBoxContainer, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vb.add_child(spacer)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_SECTION)
	vb.add_child(l)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(1, 1, 1, 0.08))
	vb.add_child(sep)


## Einheitliche Zeile: Beschriftung links (feste Breite), Control rechts.
func _row(vb: VBoxContainer, caption: String, control: Control, value: Label) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(160, 0)
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(cap)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if value != null:
		value.add_theme_font_size_override("font_size", 14)
		value.add_theme_color_override("font_color", COL_DIM)
		row.add_child(value)


func _refresh_labels() -> void:
	for i in _lane_btns.size():
		_lane_btns[i].text = OS.get_keycode_string(Settings.key_lanes[i])
	if _capturing >= 3 and _capturing - 3 < _lane_btns.size():
		_lane_btns[_capturing - 3].text = "…"
	_offset_value.text = "%+d ms" % int(Settings.offset_ms)
	_vol_value.text = "%d dB" % int(Settings.volume_db)


func _start_capture(which: int) -> void:
	_capturing = which
	_refresh_labels()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _capturing >= 3:
			if event.keycode != KEY_ESCAPE:
				Settings.key_lanes[_capturing - 3] = event.keycode
			_capturing = 0
			_refresh_labels()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()


func _close() -> void:
	Settings.save()
	Settings.apply()
	closed.emit()
	queue_free()
