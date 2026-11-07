class_name NoteColorPicker
extends VBoxContainer

## Notenfarben einstellen: Modus (Auto / je Spalte / nach Takt), 4 Farbfelder samt
## Holds, Vorlagen-Chips, Live-Vorschau (3D: Ringe wie im Spiel, 2D: Mini-Playfield).
## Liest/schreibt NoteColors (speichert bei jeder Aenderung). Signal changed.

signal changed

const MODE_LABELS := {
	"auto": "Automatisch (nach Map)",
	"lanes": "Eigene Farbe je Spalte",
	"snap": "Nach Takt-Teilung",
}
## Beispiel-Takt-Teiler je Spalte fuer die Vorschau im Modus "snap".
const SNAP_SAMPLE := [1, 2, 4, 3]
## So malt das Spiel ohne Welt-Farbe eine normale Note / einen Hold (Vorschau bei "auto").
const AUTO_NOTE := Color(0.58, 0.76, 0.94)
const AUTO_HOLD := Color(0.95, 0.72, 0.38)

var _is_2d := false
var _tab_btns: Array[Button] = []
var _link: CheckButton
var _mode_btns := {}
var _chips := {}
var _lane_btns: Array[ColorPickerButton] = []
var _hold_btns: Array[ColorPickerButton] = []
var _hold_auto: CheckButton
var _fields: Control
var _chip_row: Control
var _prev3d: _Ring3DPreview
var _prev2d: _Prev2D
var _building := false


func _init() -> void:
	add_theme_constant_override("separation", 10)
	NoteColors.ensure_loaded()
	_build()
	_sync()


func _build() -> void:
	_building = true
	# 3D / 2D umschalten + "2D wie 3D".
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	for i in 2:
		var b := Button.new()
		b.text = "3D" if i == 0 else "2D"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(64, 0)
		_style_toggle(b)
		b.pressed.connect(_on_tab.bind(i == 1))
		top.add_child(b)
		_tab_btns.append(b)
	_link = CheckButton.new()
	_link.text = tr("2D wie 3D")
	_link.toggled.connect(func(on: bool):
		if _building:
			return
		NoteColors.set_link_2d(on)
		_commit())
	top.add_child(_link)

	# Modus.
	var mrow := HFlowContainer.new()
	mrow.add_theme_constant_override("h_separation", 8)
	mrow.add_theme_constant_override("v_separation", 6)
	add_child(mrow)
	for m in NoteColors.MODES:
		var b := Button.new()
		b.text = tr(MODE_LABELS[m])
		b.toggle_mode = true
		_style_toggle(b)
		b.pressed.connect(_on_mode.bind(m))
		mrow.add_child(b)
		_mode_btns[m] = b

	# Farbfelder: Zeile "Note" und "Hold", je 4 Spalten.
	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 6)
	add_child(_fields)
	_lane_btns = _color_row(_fields, tr("Note"), false)
	_hold_btns = _color_row(_fields, tr("Hold"), true)
	_hold_auto = CheckButton.new()
	_hold_auto.text = tr("Holds automatisch etwas dunkler")
	_hold_auto.toggled.connect(func(on: bool):
		if _building:
			return
		NoteColors.set_hold_auto(_is_2d, on)
		_commit())
	_fields.add_child(_hold_auto)

	# Vorlagen.
	_chip_row = HFlowContainer.new()
	_chip_row.add_theme_constant_override("h_separation", 6)
	_chip_row.add_theme_constant_override("v_separation", 6)
	add_child(_chip_row)
	for id in NoteColors.PRESET_IDS:
		var b := Button.new()
		b.text = tr(NoteColors.PRESET_NAMES[id])
		b.toggle_mode = true
		_style_toggle(b, 10)
		b.pressed.connect(_on_preset.bind(id))
		_chip_row.add_child(b)
		_chips[id] = b

	# Vorschau.
	var pv := CenterContainer.new()
	add_child(pv)
	_prev3d = _Ring3DPreview.new()
	pv.add_child(_prev3d)
	_prev2d = _Prev2D.new()
	pv.add_child(_prev2d)
	_building = false


## Knopf im Spiel-Look; gewaehlter Zustand deutlich mit Akzent-Rand und -Toenung.
func _style_toggle(b: Button, radius: int = 12) -> void:
	UiTheme.style_button(b, false, radius)
	var on := UiTheme.glass_box(radius, 0.5, 0.0)
	on.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.22)
	on.border_color = UiTheme.ACCENT
	on.set_border_width_all(2)
	on.content_margin_left = 14
	on.content_margin_right = 14
	on.content_margin_top = 5
	on.content_margin_bottom = 5
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)


func _color_row(parent: Control, title: String, hold: bool) -> Array[ColorPickerButton]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(52, 0)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	row.add_child(l)
	var out: Array[ColorPickerButton] = []
	for i in NoteColors.LANES:
		var cb := ColorPickerButton.new()
		cb.custom_minimum_size = Vector2(52, 30)
		cb.edit_alpha = false
		cb.tooltip_text = tr("Spalte %d") % (i + 1)
		var sb := UiTheme.glass_box(8, 0.0, 0.5)
		sb.set_border_width_all(2)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			cb.add_theme_stylebox_override(st, sb)
		cb.color_changed.connect(_on_color.bind(i, hold))
		row.add_child(cb)
		out.append(cb)
	return out


## Reiter auf den aktuellen Spielmodus stellen (3D oder 2D).
func show_mode(is_2d: bool) -> void:
	_is_2d = is_2d
	_sync()


func _on_tab(is_2d: bool) -> void:
	_is_2d = is_2d
	_sync()


func _on_mode(m: String) -> void:
	NoteColors.set_mode(_is_2d, m)
	_commit()


func _on_preset(id: String) -> void:
	NoteColors.apply_preset(_is_2d, id)
	_commit()


func _on_color(c: Color, lane: int, hold: bool) -> void:
	if _building:
		return
	if hold:
		NoteColors.set_hold_color(_is_2d, lane, c)
	else:
		NoteColors.set_lane_color(_is_2d, lane, c)
	# Farbe gewaehlt = eigene Farben gewollt: aus "Automatisch" heraus schalten.
	if NoteColors.mode(_is_2d) == "auto":
		NoteColors.set_mode(_is_2d, "lanes")
	_commit()


func _commit() -> void:
	NoteColors.save()
	_sync()
	changed.emit()


## Oberflaeche aus NoteColors aufbauen (ohne Signale auszuloesen).
func _sync() -> void:
	_building = true
	var linked := NoteColors.link_2d()
	if linked and _is_2d:
		_is_2d = false   # verknuepft: es gibt nur einen Satz
	_tab_btns[0].button_pressed = not _is_2d
	_tab_btns[1].button_pressed = _is_2d
	_tab_btns[1].disabled = linked
	_link.button_pressed = linked
	var m := NoteColors.mode(_is_2d)
	for k in _mode_btns:
		(_mode_btns[k] as Button).button_pressed = (k == m)
	var custom := m == "lanes"
	_fields.modulate.a = 1.0 if custom else 0.7
	_chip_row.modulate.a = 1.0 if custom else 0.7
	var ha := NoteColors.hold_auto(_is_2d)
	_hold_auto.button_pressed = ha
	for i in NoteColors.LANES:
		_lane_btns[i].color = NoteColors.lane_color(_is_2d, i)
		_hold_btns[i].color = NoteColors.hold_color(_is_2d, i)
		_set_enabled(_hold_btns[i], not ha)
		_set_enabled(_lane_btns[i], true)
	var pid := NoteColors.preset(_is_2d)
	for id in _chips:
		(_chips[id] as Button).button_pressed = (id == pid and custom)
	_prev3d.visible = not _is_2d
	_prev2d.visible = _is_2d
	_prev3d.is_2d = _is_2d
	_prev3d.queue_redraw()
	_prev2d.refresh()
	_building = false


## Nicht "disabled" (das zeichnet ein Schachbrett), nur gedimmt und ohne Klick.
func _set_enabled(b: Control, on: bool) -> void:
	b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	b.modulate.a = 1.0 if on else 0.45


## Farbe, die das Spiel fuer diese Vorschau-Note nimmt.
static func sample_color(lane: int, hold: bool, is_2d: bool) -> Color:
	return NoteColors.color_for(lane, hold, is_2d, AUTO_HOLD if hold else AUTO_NOTE,
			SNAP_SAMPLE[lane % SNAP_SAMPLE.size()])


# ------------------------------------------------------------------ 3D-Vorschau

## Vier Noten-Ringe wie im Spiel (Halo, Fuellung, Ring) plus ein Hold-Balken.
class _Ring3DPreview extends Control:
	const BOX := Vector2(260, 150)
	var is_2d := false

	func _init() -> void:
		custom_minimum_size = BOX
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(UiTheme.glass_box(14, 0.7, 0.14), Rect2(Vector2.ZERO, size))
		var step := size.x / float(NoteColors.LANES)
		for i in NoteColors.LANES:
			var cx := step * (i + 0.5)
			# Hold-Balken unter dem zweiten und vierten Ring.
			if i == 1 or i == 3:
				var hc := NoteColorPicker.sample_color(i, true, is_2d)
				draw_rect(Rect2(cx - 7, 76, 14, 46), Color(hc.r, hc.g, hc.b, 0.55))
				_ring(Vector2(cx, 122), hc, 0.8)
			var c := NoteColorPicker.sample_color(i, false, is_2d)
			_ring(Vector2(cx, 44), c, 1.0)

	func _ring(p: Vector2, c: Color, k: float) -> void:
		for j in 5:
			var rr := 25.0 - j * 3.0
			draw_circle(p, rr, Color(c.r, c.g, c.b, 0.07 * k))
		draw_circle(p, 17.0, Color(c.r, c.g, c.b, 0.22))
		draw_arc(p, 17.0, 0.0, TAU, 40, Color(minf(c.r * 1.15, 1.0), minf(c.g * 1.15, 1.0),
				minf(c.b * 1.15, 1.0), 1.0), 3.5, true)


# ------------------------------------------------------------------ 2D-Vorschau

## PlayfieldPreview, aber mit den Notenfarben aus NoteColors.
class _Prev2D extends PlayfieldPreview:
	func _feed() -> void:
		if _pf == null:
			return
		_pf.begin_frame()
		var zl := 3.0
		var zf := -46.0
		var ph := _t / PERIOD
		for n in NOTES:
			var f := fposmod(ph + float(n[1]), 1.0)
			var z := zf + (zl - zf) * f * 1.15
			var col: int = n[0]
			var is_hold := float(n[2]) > 0.0
			var c := NoteColorPicker.sample_color(col, is_hold, true)
			if is_hold:
				_pf.add_hold(col, z, z - (zl - zf) * float(n[2]), c)
			else:
				_pf.add_note(col, z, c)
		_pf.set_lanes([], [], [])
