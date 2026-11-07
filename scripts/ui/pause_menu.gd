class_name PauseMenu
extends Control

## Pause-Menue (Glas-Panel auf abgedunkeltem Hintergrund). Der Host
## (mania_3d) haelt das Spiel an und startet bei resume_pressed den 3-2-1-
## Countdown. Offset/Scroll-Speed werden direkt in Settings geschrieben.
## open(info): title, progress (0..1), score (int), acc (Prozent), difficulty,
## optional length_ms (Songlaenge, fuer die Zeitanzeige), is_2d (zeigt die
## 2D-Regler Spurbreite/Notengroesse/Hintergrund; Aenderung -> view_2d_changed).

signal resume_pressed
signal restart_pressed
signal quit_pressed
signal view_2d_changed

const W_1COL := 420.0
const W_2COL := 780.0

var _dim: ColorRect
var _panel: GlassPanel
var _title: Label
var _song: Label
var _bar: ProgressBar
var _stats: Label
var _time: Label
var _vb: VBoxContainer
var _offset_val: Label
var _scroll_val: Label
var _lane2d_val: Label
var _note2d_val: Label
var _bg_val: Label
var _quick: GridContainer
var _rows_2d: Array[Control] = []
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
	_panel.custom_minimum_size = Vector2(W_1COL, 0)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add(vb)
	_vb = vb

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

	_time = Label.new()
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.add_theme_font_size_override("font_size", 13)
	_time.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(_time)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.add_theme_color_override("font_color", UiTheme.ACCENT)
	vb.add_child(_stats)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vb.add_child(gap)
	_btn_resume = _button("Fortsetzen", true, func(): _resume())
	vb.add_child(_btn_resume)
	vb.add_child(_button("Neu starten", false, func(): restart_pressed.emit()))
	vb.add_child(_button("Zum Song-Browser", false, func(): quit_pressed.emit()))
	vb.add_child(_hint_row())

	vb.add_child(UiTheme.section_label("Schnelleinstellungen"))
	# 3D: eine Spalte; 2D: zwei Spalten, damit das Panel bei 720p nicht ueberlaeuft.
	_quick = GridContainer.new()
	_quick.columns = 1
	_quick.add_theme_constant_override("h_separation", 24)
	_quick.add_theme_constant_override("v_separation", 10)
	vb.add_child(_quick)
	_offset_val = Label.new()
	_quick.add_child(_stepper("Audio-Offset", _offset_val, -5.0, 5.0, func(d: float): _step_offset(d)))
	_scroll_val = Label.new()
	_quick.add_child(_stepper("Scrollgeschwindigkeit", _scroll_val, -0.1, 0.1, func(d: float): _step_scroll(d)))
	_lane2d_val = Label.new()
	_rows_2d.append(_stepper("Spurbreite", _lane2d_val, -0.1, 0.1,
			func(d: float): _step_2d("lane_width_2d", d)))
	_note2d_val = Label.new()
	_rows_2d.append(_stepper("Notengröße", _note2d_val, -0.1, 0.1,
			func(d: float): _step_2d("note_size_2d", d)))
	_bg_val = Label.new()
	_rows_2d.append(_stepper("Hintergrund", _bg_val, -0.1, 0.1, func(d: float): _step_bg(d)))
	for row in _rows_2d:
		_quick.add_child(row)


## Zeile mit Keycaps: [ESC] Fortsetzen   [Enter] Auswaehlen.
func _hint_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_hint(row, "ESC", "Fortsetzen")
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(14, 0)
	row.add_child(sp)
	_hint(row, "Enter", "Auswählen")
	return row


func _hint(row: HBoxContainer, key: String, text: String) -> void:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.22, 0.9)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.border_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.55)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", sb)
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", UiTheme.TEXT)
	cap.add_child(k)
	row.add_child(cap)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	row.add_child(l)


## Tausendertrenner mit Punkt: 1234 -> "1.234".
static func fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return ("-" + out) if v < 0 else out


## Sekunden -> "m:ss".
static func fmt_time(ms: float) -> String:
	var t := maxi(int(ms / 1000.0), 0)
	return "%d:%02d" % [t / 60, t % 60]


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


## 2D-Spurbreite/-Notengroesse in 10-%-Schritten (50..200 %), sofort aktiv.
func _step_2d(key: String, d: float) -> void:
	Settings.set(key, Settings.clamp_2d_size(float(Settings.get(key)) + d))
	Settings.save()
	_refresh_values()
	view_2d_changed.emit()


## Hintergrund-Deckkraft 0..100 % (0 = aus), sofort aktiv.
func _step_bg(d: float) -> void:
	Settings.bg_dim = Settings.clamp_bg_dim(Settings.bg_dim + d)
	Settings.save()
	_refresh_values()
	view_2d_changed.emit()


func _refresh_values() -> void:
	_offset_val.text = "%+.0f ms" % Settings.offset_ms
	_scroll_val.text = ("%.2f" % Settings.mania_scroll).replace(".", ",") + "x"
	_lane2d_val.text = _pct(Settings.lane_width_2d)
	_note2d_val.text = _pct(Settings.note_size_2d)
	_bg_val.text = "Aus" if Settings.bg_dim <= 0.001 else _pct(Settings.bg_dim)


static func _pct(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func open(info: Dictionary = {}) -> void:
	_song.text = str(info.get("title", ""))
	_bar.value = clampf(float(info.get("progress", 0.0)), 0.0, 1.0)
	_stats.text = "%s   |   %s %%" % [fmt_int(int(info.get("score", 0))),
		("%.2f" % float(info.get("acc", 100.0))).replace(".", ",")]
	var len_ms := float(info.get("length_ms", 0.0))
	_time.visible = len_ms > 0.0
	if len_ms > 0.0:
		_time.text = "%s / %s" % [fmt_time(_bar.value * len_ms), fmt_time(len_ms)]
	var is_2d := bool(info.get("is_2d", false))
	for row in _rows_2d:
		row.visible = is_2d
	_quick.columns = 2 if is_2d else 1
	_refresh_values()
	# GlassPanel ist ein reines Control: Hoehe aus dem Inhalt ableiten.
	_panel.custom_minimum_size = Vector2(W_2COL if is_2d else W_1COL,
			_panel.content.get_combined_minimum_size().y)
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
