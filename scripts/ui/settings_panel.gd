class_name SettingsPanel
extends Control

## Einstellungen — schlank wie osu!mania, in drei klaren Sektionen:
## GAMEPLAY (Scroll, Tasten, Offset), AUDIO (Lautstaerke, Hitsounds),
## ANZEIGE (Effekte, Vollbild). Profilname/-bild wohnen in der Profil-Ansicht.

signal closed

const COL_DIM := Color(0.55, 0.58, 0.66)
const COL_SECTION := Color(0.45, 0.8, 1.0)
const VALUE_W := 84.0

var _world_preview: WorldPreview
var _world_row: Control
var _panel: Control

const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	COLOR = vec4(c * 0.38, 1.0);
}
"""

var _capturing := 0   # 0 = keine Aufnahme, 3..6 = Lane 1-4
var _lane_btns: Array[Button] = []
var _offset_value: Label
var _offset_slider: HSlider
var _vol_value: Label
var _bg_dim_slider: HSlider
var _bg_blur_btn: CheckButton
var _note_style_opt: OptionButton


func _ready() -> void:
	Sfx.ui_open()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color.WHITE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	dim.material = mat
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.95)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	_panel = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
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
	var cv_gameplay := _section(vb, "GAMEPLAY")

	var scroll_slider := HSlider.new()
	scroll_slider.min_value = 0.5
	scroll_slider.max_value = 3.0
	scroll_slider.step = 0.1
	scroll_slider.value = Settings.mania_scroll
	var scroll_value := Label.new()
	scroll_value.custom_minimum_size = Vector2(VALUE_W, 0)
	scroll_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scroll_value.text = _fmt_x(Settings.mania_scroll)
	scroll_slider.value_changed.connect(func(v):
		Settings.mania_scroll = v
		scroll_value.text = _fmt_x(v))
	_row(cv_gameplay, "Scrollgeschwindigkeit", scroll_slider, scroll_value)

	var spacing_slider := HSlider.new()
	spacing_slider.min_value = Settings.LANE_SPACING_MIN * 100.0
	spacing_slider.max_value = Settings.LANE_SPACING_MAX * 100.0
	spacing_slider.step = Settings.LANE_SPACING_STEP * 100.0
	spacing_slider.value = Settings.lane_spacing * 100.0
	var spacing_value := Label.new()
	spacing_value.text = _fmt_pct0(Settings.lane_spacing)
	spacing_slider.value_changed.connect(func(v):
		Settings.lane_spacing = Settings.clamp_lane_spacing(v / 100.0)
		spacing_value.text = _fmt_pct0(Settings.lane_spacing))
	spacing_slider.tooltip_text = "Abstand der Spuren (3D und 2D). Unter 85 % werden die Noten leicht kleiner."
	_row(cv_gameplay, "Spurbreite", spacing_slider, spacing_value)

	var mode_2d := CheckButton.new()
	mode_2d.button_pressed = Settings.playfield_2d
	mode_2d.tooltip_text = "Klassische senkrechte Spuren ohne 3D-Welt; Hintergrund = Map-Bild"
	mode_2d.toggled.connect(func(on):
		Settings.playfield_2d = on
		_update_2d_rows())
	_row(cv_gameplay, "2D-Modus", mode_2d, null)

	_note_style_opt = OptionButton.new()
	_note_style_opt.add_item("Balken", Settings.NOTE_STYLE_BAR)
	_note_style_opt.add_item("Kreis", Settings.NOTE_STYLE_CIRCLE)
	_note_style_opt.select(Settings.note_style_2d)
	_note_style_opt.custom_minimum_size = Vector2(0, 36)
	_note_style_opt.item_selected.connect(func(i): Settings.note_style_2d = i)
	_row(cv_gameplay, "2D-Notenform", _note_style_opt, null)

	_bg_dim_slider = HSlider.new()
	_bg_dim_slider.min_value = 0.0
	_bg_dim_slider.max_value = 100.0
	_bg_dim_slider.step = 5.0
	_bg_dim_slider.value = Settings.bg_dim * 100.0
	var dim_value := Label.new()
	dim_value.text = _fmt_pct0(Settings.bg_dim)
	_bg_dim_slider.value_changed.connect(func(v):
		Settings.bg_dim = Settings.clamp_bg_dim(v / 100.0)
		dim_value.text = _fmt_pct0(Settings.bg_dim))
	_row(cv_gameplay, "Hintergrund-Deckkraft", _bg_dim_slider, dim_value)

	_bg_blur_btn = CheckButton.new()
	_bg_blur_btn.button_pressed = Settings.bg_blur
	_bg_blur_btn.toggled.connect(func(on): Settings.bg_blur = on)
	_row(cv_gameplay, "Hintergrund-Unschärfe", _bg_blur_btn, null)

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 8)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		var lane := i
		b.pressed.connect(func(): _start_capture(3 + lane))
		lane_row.add_child(b)
		_lane_btns.append(b)
	_row(cv_gameplay, "Tasten 1-4", lane_row, null)

	var offset_slider := HSlider.new()
	offset_slider.min_value = -200.0
	offset_slider.max_value = 200.0
	offset_slider.step = 1.0
	offset_slider.value = Settings.offset_ms
	_offset_value = Label.new()
	_offset_value.custom_minimum_size = Vector2(VALUE_W, 0)
	_offset_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	offset_slider.value_changed.connect(func(v):
		Settings.offset_ms = v
		Settings.apply()
		_offset_value.text = "%+d ms" % int(v))
	_offset_slider = offset_slider
	var offset_box := HBoxContainer.new()
	offset_box.add_theme_constant_override("separation", 10)
	offset_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offset_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	offset_slider.size_flags_stretch_ratio = 2.0
	offset_slider.custom_minimum_size = Vector2(140, 0)
	offset_box.add_child(offset_slider)
	var calib_btn := Button.new()
	calib_btn.text = "Kalibrieren"
	calib_btn.custom_minimum_size = Vector2(0, 34)
	calib_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiTheme.style_button(calib_btn)
	calib_btn.pressed.connect(_open_wizard)
	offset_box.add_child(calib_btn)
	_row(cv_gameplay, "Audio-Offset", offset_box, _offset_value)

	# -------------------------------- AUDIO ---------------------------------
	var cv_audio := _section(vb, "AUDIO")

	var vol_slider := HSlider.new()
	vol_slider.min_value = -30.0
	vol_slider.max_value = 0.0
	vol_slider.step = 1.0
	vol_slider.value = Settings.volume_db
	_vol_value = Label.new()
	_vol_value.custom_minimum_size = Vector2(VALUE_W, 0)
	_vol_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_slider.value_changed.connect(func(v):
		Settings.volume_db = v
		Settings.apply()
		_vol_value.text = "%d dB" % int(v))
	_row(cv_audio, "Lautstärke", vol_slider, _vol_value)

	var enh := CheckButton.new()
	enh.button_pressed = Settings.audio_enhance
	enh.toggled.connect(func(on):
		Settings.audio_enhance = on
		Settings.apply())
	_row(cv_audio, "Klarheit (Höhen)", enh, null)

	var bass_slider := HSlider.new()
	bass_slider.min_value = 0.0
	bass_slider.max_value = 1.0
	bass_slider.step = 0.05
	bass_slider.value = Settings.bass_boost
	var bass_value := Label.new()
	bass_value.custom_minimum_size = Vector2(VALUE_W, 0)
	bass_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bass_value.text = "%d %%" % int(Settings.bass_boost * 100.0)
	var no_fill := StyleBoxEmpty.new()
	var set_bass_fill := func(v: float):
		if v <= 0.001:
			bass_slider.add_theme_stylebox_override("grabber_area", no_fill)
			bass_slider.add_theme_stylebox_override("grabber_area_highlight", no_fill)
		else:
			bass_slider.remove_theme_stylebox_override("grabber_area")
			bass_slider.remove_theme_stylebox_override("grabber_area_highlight")
	set_bass_fill.call(Settings.bass_boost)
	bass_slider.value_changed.connect(func(v):
		set_bass_fill.call(v)
		Settings.bass_boost = v
		Settings.apply()
		bass_value.text = "%d %%" % int(v * 100.0))
	_row(cv_audio, "Bass", bass_slider, bass_value)

	var hs := CheckButton.new()
	hs.button_pressed = Settings.hitsounds
	hs.toggled.connect(func(on): Settings.hitsounds = on)
	_row(cv_audio, "Treffer-Sounds", hs, null)

	var hset := OptionButton.new()
	hset.add_item("Soft", 0)
	hset.add_item("Clap", 1)
	hset.add_item("Kick", 2)
	hset.select(Settings.hitsound_set)
	hset.custom_minimum_size = Vector2(0, 36)
	hset.item_selected.connect(func(i):
		Settings.hitsound_set = i
		Sfx.preview_hit(i))
	_row(cv_audio, "Hitsound", hset, null)

	var hs_slider := HSlider.new()
	hs_slider.min_value = 0.0
	hs_slider.max_value = 1.0
	hs_slider.step = 0.05
	hs_slider.value = Settings.hitsound_volume
	var hs_value := Label.new()
	hs_value.custom_minimum_size = Vector2(VALUE_W, 0)
	hs_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hs_value.text = "%d %%" % int(Settings.hitsound_volume * 100.0)
	hs_slider.value_changed.connect(func(v):
		Settings.hitsound_volume = v
		hs_value.text = "%d %%" % int(v * 100.0))
	_row(cv_audio, "Treffer-Lautstärke", hs_slider, hs_value)

	# ------------------------------- ANZEIGE --------------------------------
	var cv_anzeige := _section(vb, "ANZEIGE")

	var fx := OptionButton.new()
	fx.add_item("Aus", 0)
	fx.add_item("Dezent", 1)
	fx.add_item("Voll", 2)
	fx.select(Settings.tunnel_intensity)
	fx.custom_minimum_size = Vector2(0, 36)
	fx.item_selected.connect(func(i): Settings.tunnel_intensity = i)
	_row(cv_anzeige, "Effekt-Intensität", fx, null)

	var cam := OptionButton.new()
	cam.add_item("Komfort", 0)
	cam.add_item("Dynamisch", 1)
	cam.select(Settings.camera_mode)
	cam.custom_minimum_size = Vector2(0, 36)
	cam.tooltip_text = "Komfort: ruhige Kamera, gegen Übelkeit
Dynamisch: volle Flug-Bewegung"
	cam.item_selected.connect(func(i): Settings.camera_mode = i)
	_row(cv_anzeige, "Kamera", cam, null)

	var wt := OptionButton.new()
	wt.add_item("Automatisch", 0)
	for wi in Settings.WORLD_ORDER.size():
		var wname: String = Settings.WORLD_ORDER[wi]
		wt.add_item(str(WorldTheme.LABELS.get(wname, wname)), wi + 1)
		if wname != "galaxy" and not WorldTheme.is_available(wname):
			wt.set_item_disabled(wt.get_item_count() - 1, true)
	wt.select(Settings.world_theme)
	wt.custom_minimum_size = Vector2(0, 36)
	wt.tooltip_text = "Automatisch: düstere Welt passend zum Song
(intensiv = Bosskampf, ruhig = Frost, sonst Eklipse, Abgrund, Fraktal, Obsidian …)"
	wt.item_selected.connect(func(i):
		Settings.world_theme = i
		_world_preview.show_world("" if i == 0 else Settings.WORLD_ORDER[i - 1]))
	_row(cv_anzeige, "Welt", wt, null)
	_world_row = wt
	_update_2d_rows()
	_world_preview = WorldPreview.new()
	_world_preview.visible = false
	add_child(_world_preview)
	_world_preview.show_world(Settings.world_theme_name())

	var gfx := OptionButton.new()
	gfx.add_item("Niedrig", 0)
	gfx.add_item("Mittel (2x AA)", 1)
	gfx.add_item("Hoch (4x AA)", 2)
	gfx.add_item("Ultra (8x AA)", 3)
	gfx.add_item("Extrem (8x AA + SSAA)", 4)
	gfx.select(Settings.graphics_quality)
	gfx.custom_minimum_size = Vector2(0, 36)
	gfx.item_selected.connect(func(i):
		Settings.graphics_quality = i
		Settings.apply())
	_row(cv_anzeige, "Grafik-Qualität", gfx, null)

	var fps := OptionButton.new()
	fps.add_item("VSync", 0)
	fps.add_item("Unbegrenzt", 1)
	fps.add_item("240 FPS", 2)
	fps.add_item("360 FPS", 3)
	fps.add_item("480 FPS", 4)
	fps.select(Settings.fps_mode)
	fps.custom_minimum_size = Vector2(0, 36)
	fps.item_selected.connect(func(i):
		Settings.fps_mode = i
		Settings.apply())
	_row(cv_anzeige, "FPS-Limit", fps, null)

	var lg := CheckButton.new()
	lg.button_pressed = Settings.lane_glow
	lg.toggled.connect(func(on): Settings.lane_glow = on)
	_row(cv_anzeige, "Spur-Aufleuchten (Taste)", lg, null)

	var fs := CheckButton.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.fullscreen = on; Settings.apply())
	_row(cv_anzeige, "Vollbild (F11)", fs, null)

	# Fusszeile.
	var save := Button.new()
	save.text = "Speichern & Schließen"
	save.custom_minimum_size = Vector2(0, 46)
	UiTheme.style_button(save, true)
	save.pressed.connect(_close)
	vb.add_child(save)

	_refresh_labels()

	# Sanftes Einblenden: Scale 0.96 -> 1 + Fade, 0.18 s.
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	_intro.call_deferred(panel)


func _intro(panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18)


## Sektion als dezente Karte: Kopfzeile + Zeilen-Box. Gibt die Box zurueck.
func _section(vb: VBoxContainer, text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	vb.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_SECTION)
	inner.add_child(l)
	return inner


## Einheitliche Zeile: Beschriftung links (feste Breite), Control rechts.
func _row(vb: VBoxContainer, caption: String, control: Control, value: Label) -> void:
	var hov := PanelContainer.new()
	hov.mouse_filter = Control.MOUSE_FILTER_PASS
	var hn := StyleBoxFlat.new()
	hn.bg_color = Color(1, 1, 1, 0.0)
	hn.set_corner_radius_all(8)
	hn.content_margin_left = 8
	hn.content_margin_right = 8
	hn.content_margin_top = 3
	hn.content_margin_bottom = 3
	hov.add_theme_stylebox_override("panel", hn)
	hov.custom_minimum_size = Vector2(0, 44)
	hov.mouse_entered.connect(func(): hn.bg_color = Color(1, 1, 1, 0.06))
	hov.mouse_exited.connect(func(): hn.bg_color = Color(1, 1, 1, 0.0))
	vb.add_child(hov)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	hov.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(190, 0)
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(cap)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if value != null:
		value.add_theme_font_size_override("font_size", 14)
		value.add_theme_color_override("font_color", COL_DIM)
		value.custom_minimum_size = Vector2(VALUE_W, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)


## 0.85 -> "85 %".
static func _fmt_pct0(v: float) -> String:
	return UiTheme.fmt_num(v * 100.0, 0) + " %"


## 2D-Regler nur bei 2D aktiv; Welt-Auswahl gilt nur fuer 3D (ausgegraut).
func _update_2d_rows() -> void:
	var on := Settings.playfield_2d
	if _bg_dim_slider != null:
		_bg_dim_slider.editable = on
		_bg_dim_slider.modulate.a = 1.0 if on else 0.4
	if _note_style_opt != null:
		_note_style_opt.disabled = not on
		_note_style_opt.modulate.a = 1.0 if on else 0.4
	if _bg_blur_btn != null:
		_bg_blur_btn.disabled = not on
		_bg_blur_btn.modulate.a = 1.0 if on else 0.4
	if _world_row is OptionButton:
		(_world_row as OptionButton).disabled = on
		_world_row.modulate.a = 0.4 if on else 1.0


static func _fmt_x(v: float) -> String:
	return ("%.1f" % v).replace(".", ",") + "×"


func _refresh_labels() -> void:
	for i in _lane_btns.size():
		_lane_btns[i].text = UiTheme.key_short(Settings.key_lanes[i])
	if _capturing >= 3 and _capturing - 3 < _lane_btns.size():
		_lane_btns[_capturing - 3].text = "…"
	_offset_value.text = "%+d ms" % int(Settings.offset_ms)
	_vol_value.text = "%d dB" % int(Settings.volume_db)


func _open_wizard() -> void:
	var w := OffsetWizard.new()
	w.finished.connect(func(_applied: bool):
		_offset_slider.set_value_no_signal(Settings.offset_ms)
		_refresh_labels())
	add_child(w)


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
			Sfx.ui_back()
			_close(false)
			get_viewport().set_input_as_handled()


## Vorschau-Karte rechts neben das Panel, auf Hoehe der Welt-Zeile (sonst
## unter das Panel); bleibt im sichtbaren Bereich.
func _process(_delta: float) -> void:
	if _world_preview == null or _panel == null or _world_row == null:
		return
	var vr := get_viewport_rect().size
	var pr := _panel.get_global_rect()
	var sz := WorldPreview.SIZE_PX
	var x := pr.end.x + 16.0
	if x + sz.x > vr.x - 8.0:
		x = maxf(8.0, vr.x - sz.x - 8.0)
	var y := clampf(_world_row.get_global_rect().get_center().y - sz.y * 0.5, 8.0, maxf(8.0, vr.y - sz.y - 8.0))
	_world_preview.position = Vector2(x, y)
	_world_preview.modulate.a = _panel.modulate.a
	_world_preview.visible = _panel.modulate.a > 0.01


func _close(with_sound: bool = true) -> void:
	if with_sound:
		Sfx.ui_close()
	Settings.save()
	Settings.apply()
	if _world_preview != null:
		_world_preview.release()
	closed.emit()
	queue_free()
