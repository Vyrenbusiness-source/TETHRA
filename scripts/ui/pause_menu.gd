class_name PauseMenu
extends Control

## Pause-Menue: ruhige Graphit-Flaeche auf abgedunkeltem Spiel, linksbuendig gesetzt
## (Titel, Lied, Fortschritt mit Zeiten, Zahlenleiste, Aktionen, Schnelleinstellungen).
## Der Host (mania_3d) haelt das Spiel an und startet bei resume_pressed den 3-2-1-
## Countdown. Offset/Scroll-Speed werden direkt in Settings geschrieben.
## open(info): title, progress (0..1), score (int), acc (Prozent), difficulty,
## optional length_ms (Songlaenge, fuer die Zeitanzeige), is_2d (zeigt die
## 2D-Regler Spurbreite/Notengroesse/Hintergrund; Aenderung -> view_2d_changed).

signal resume_pressed
signal restart_pressed
signal quit_pressed
signal view_2d_changed

const W_1COL := 440.0
const W_2COL := 800.0
const PAD := 28
const ROW_H := 44
const STEP_H := 32

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _song: Label
var _bar: ProgressBar
var _time: Label
var _time_end: Label
var _time_row: Control
var _score_val: Label
var _acc_val: Label
var _vb: VBoxContainer
var _offset_val: Label
var _scroll_val: Label
var _lane2d_val: Label
var _note2d_val: Label
var _bg_val: Label
var _field_val: Label
var _quick: GridContainer
var _rows_2d: Array[Control] = []
var _btn_resume: Button
var _tween: Tween
var _f_num: FontVariation


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Tabellenziffern: Werte springen beim Verstellen nicht in der Breite.
	_f_num = UiTheme.heading_font(0)
	var ts := TextServerManager.get_primary_interface()
	_f_num.opentype_features = {ts.name_to_tag("tnum"): 1, ts.name_to_tag("lnum"): 1}

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(UiTheme.BG.r * 0.5, UiTheme.BG.g * 0.5, UiTheme.BG.b * 0.5, 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Deckende Graphit-Flaeche mit Haarlinien-Rand, wie das Einstellungs-Panel.
	_panel = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(UiTheme.SURFACE.r, UiTheme.SURFACE.g, UiTheme.SURFACE.b, 0.97)
	psb.set_corner_radius_all(UiTheme.R_MAX)
	psb.set_border_width_all(1)
	psb.border_color = UiTheme.LINE
	psb.content_margin_left = PAD
	psb.content_margin_right = PAD
	psb.content_margin_top = 22
	psb.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.custom_minimum_size = Vector2(W_1COL, 0)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_panel.add_child(vb)
	_vb = vb

	# "Pause" ist in beiden Sprachen dasselbe Wort (der Schluessel "Pause" gehoert
	# im Dirigenten zur Notenpause).
	_title = Label.new()
	_title.text = "Pause"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_font_override("font", UiTheme.heading_font(0))
	_title.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_title)

	_song = Label.new()
	_song.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_song.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_song.add_theme_font_size_override("font_size", 14)
	_song.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(_song)
	vb.add_child(_gap(14))

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 4)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.10)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = UiTheme.ACCENT
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	vb.add_child(_bar)
	vb.add_child(_gap(6))

	# Zeiten an den Enden des Balkens: links gespielt, rechts Gesamtlaenge.
	var times := HBoxContainer.new()
	_time_row = times
	_time = _num_label(12, UiTheme.TEXT)
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	times.add_child(_time)
	_time_end = _num_label(12, UiTheme.DIM)
	times.add_child(_time_end)
	vb.add_child(times)
	vb.add_child(_gap(14))

	# Zahlenleiste: kleine Beschriftung, Wert gross in Tabellenziffern.
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 0)
	vb.add_child(facts)
	_score_val = _fact(facts, "Score", true)
	_acc_val = _fact(facts, "Genauigkeit", false)
	vb.add_child(_gap(18))

	_btn_resume = _button("Fortsetzen", true, func(): _resume())
	_btn_resume.custom_minimum_size = Vector2(0, 48)
	_btn_resume.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_btn_resume.add_theme_font_size_override("font_size", 17)
	var esc := _num_label(12, Color(UiTheme.ON_ACCENT, 0.72))
	esc.text = "Esc"
	esc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	esc.offset_right = -16
	esc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	esc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	esc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_resume.add_child(esc)
	vb.add_child(_btn_resume)
	vb.add_child(_gap(6))
	vb.add_child(_list_button("Neu starten", func(): restart_pressed.emit()))
	vb.add_child(_list_button("Zum Song-Browser", func(): quit_pressed.emit()))
	vb.add_child(_gap(20))

	vb.add_child(UiTheme.section_label("Schnelleinstellungen"))
	vb.add_child(_gap(8))
	# 3D: eine Spalte; 2D: zwei Spalten, damit das Panel bei 720p nicht ueberlaeuft.
	_quick = GridContainer.new()
	_quick.columns = 1
	_quick.add_theme_constant_override("h_separation", 32)
	_quick.add_theme_constant_override("v_separation", 6)
	vb.add_child(_quick)
	_offset_val = Label.new()
	_quick.add_child(_stepper("Audio-Offset", _offset_val, -5.0, 5.0, func(d: float): _step_offset(d)))
	_scroll_val = Label.new()
	_quick.add_child(_stepper("Scroll Speed", _scroll_val, -1.0, 1.0, func(d: float): _step_scroll(d)))
	_lane2d_val = Label.new()
	_rows_2d.append(_stepper("Spurbreite", _lane2d_val, -0.1, 0.1,
			func(d: float): _step_2d("lane_width_2d", d)))
	_note2d_val = Label.new()
	_rows_2d.append(_stepper("Notengröße", _note2d_val, -0.1, 0.1,
			func(d: float): _step_2d("note_size_2d", d)))
	_bg_val = Label.new()
	_rows_2d.append(_stepper("Hintergrund", _bg_val, -0.1, 0.1, func(d: float): _step_bg(d)))
	_field_val = Label.new()
	_rows_2d.append(_stepper("Spielfeld", _field_val, -0.1, 0.1, func(d: float): _step_field(d)))
	for row in _rows_2d:
		_quick.add_child(row)
	vb.add_child(_gap(14))
	vb.add_child(UiTheme.hairline())
	vb.add_child(_gap(12))
	vb.add_child(_hint_row())


func _gap(h: int) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _num_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", _f_num)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Zelle der Zahlenleiste (Beschriftung ueber Wert); ab der zweiten mit Haarlinie davor.
func _fact(row: HBoxContainer, caption: String, first: bool) -> Label:
	if not first:
		var line := ColorRect.new()
		line.color = UiTheme.LINE
		line.custom_minimum_size = Vector2(1, 0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(16, 0)
		row.add_child(pad)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var c := Label.new()
	c.text = caption
	c.add_theme_font_size_override("font_size", 12)
	c.add_theme_color_override("font_color", UiTheme.DIM)
	col.add_child(c)
	var v := _num_label(22, UiTheme.TEXT)
	col.add_child(v)
	return v


## Zeile mit Keycaps: [Esc] Fortsetzen   [Enter] Auswaehlen.
func _hint_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_hint(row, "Esc", "Fortsetzen")
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(12, 0)
	row.add_child(sp)
	_hint(row, "Enter", "Auswählen")
	return row


func _hint(row: HBoxContainer, key: String, text: String) -> void:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.RAISED
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.border_color = Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.18)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", sb)
	var k := Label.new()
	k.text = key
	k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	return UiTheme.fmt_score(v)


## Sekunden -> "m:ss".
static func fmt_time(ms: float) -> String:
	var t := maxi(int(ms / 1000.0), 0)
	return "%d:%02d" % [t / 60, t % 60]


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	UiTheme.style_button(b, primary)
	return b


## Listenzeile wie im Hauptmenue: Text links, Haarlinie unten, Hover/Fokus als
## helle Flaeche mit Bernstein-Marke links.
func _list_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", UiTheme.heading_font(0))
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.0)
	n.border_width_bottom = 1
	n.border_color = UiTheme.LINE
	n.content_margin_left = 16
	n.content_margin_right = 16
	var hv: StyleBoxFlat = n.duplicate()
	hv.bg_color = Color(1, 1, 1, 0.05)
	hv.border_width_left = 2
	hv.border_width_bottom = 0
	hv.border_color = UiTheme.ACCENT
	hv.content_margin_left = 14
	var pr: StyleBoxFlat = hv.duplicate()
	pr.bg_color = Color(1, 1, 1, 0.03)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", UiTheme.TEXT)
	b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	b.add_theme_color_override("font_focus_color", UiTheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	UiTheme._attach_sounds(b)
	return b


## Zeile: Label | - | Wert | +. minus/plus rufen cb(+-step). Feste Breiten: alle
## Zeilen fluchten in Knopf- und Wertspalte.
func _stepper(text: String, val: Label, minus: float, plus: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(l)
	var bm := _button("−", false, func(): cb.call(minus))
	bm.custom_minimum_size = Vector2(36, STEP_H)
	row.add_child(bm)
	val.custom_minimum_size = Vector2(112, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.add_theme_font_override("font", _f_num)
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(val)
	var bp := _button("+", false, func(): cb.call(plus))
	bp.custom_minimum_size = Vector2(36, STEP_H)
	row.add_child(bp)
	return row


func _step_offset(d: float) -> void:
	Settings.offset_ms = clampf(Settings.offset_ms + d, -200.0, 200.0)
	# Sofort wirksam (Settings.apply() wuerde auch Fenster/Grafik neu setzen).
	SyncClock.user_offset_ms = Settings.offset_ms
	Settings.save()
	_refresh_values()


## Scroll Speed 1..40 wie lazer: speichert, zieht das laufende Spiel live
## nach (mania_3d.apply_scroll_speed) und zeigt "Scroll Speed 25 (459 ms)".
func _step_scroll(d: float) -> void:
	Settings.step_scroll_speed(roundi(d))
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


## Spielfeld-Deckkraft 0..100 % (100 = schwarz), sofort aktiv.
func _step_field(d: float) -> void:
	Settings.field_dim_2d = Settings.clamp_bg_dim(Settings.field_dim_2d + d)
	Settings.save()
	_refresh_values()
	view_2d_changed.emit()


func _refresh_values() -> void:
	_offset_val.text = "%+.0f ms" % Settings.offset_ms
	_scroll_val.text = Settings.scroll_value_text(Settings.scroll_speed)
	_lane2d_val.text = _pct(Settings.lane_width_2d)
	_note2d_val.text = _pct(Settings.note_size_2d)
	_bg_val.text = tr("Aus") if Settings.bg_dim <= 0.001 else _pct(Settings.bg_dim)
	_field_val.text = _pct(Settings.field_dim_2d)


static func _pct(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func open(info: Dictionary = {}) -> void:
	_song.text = str(info.get("title", ""))
	_bar.value = clampf(float(info.get("progress", 0.0)), 0.0, 1.0)
	_score_val.text = fmt_int(int(info.get("score", 0)))
	_acc_val.text = UiTheme.fmt_pct(float(info.get("acc", 100.0)))
	var len_ms := float(info.get("length_ms", 0.0))
	_time_row.visible = len_ms > 0.0
	if len_ms > 0.0:
		_time.text = fmt_time(_bar.value * len_ms)
		_time_end.text = fmt_time(len_ms)
	var is_2d := bool(info.get("is_2d", false))
	for row in _rows_2d:
		row.visible = is_2d
	_quick.columns = 2 if is_2d else 1
	_refresh_values()
	_panel.custom_minimum_size = Vector2(W_2COL if is_2d else W_1COL, 0)
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
