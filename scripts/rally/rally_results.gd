class_name RallyResults
extends Control

## Rally-Endbild: Rang, Punkte, Genauigkeit, Stufenzaehler, Timing-Histogramm,
## Schmetterball-/Aufladen-Zaehler. Ruhig und flach (UiTheme), keine Effekte.

signal retry_pressed
signal back_pressed
signal replay_pressed

const BINS := 41
const TIER_COLS := [
	Color(0.98, 0.93, 0.75), Color(0.80, 0.90, 0.96), Color(0.60, 0.82, 0.56),
	Color(0.52, 0.66, 0.92), Color(0.62, 0.62, 0.66), Color(0.87, 0.44, 0.38),
]
const TIER_NAMES := ["MAX", "300", "200", "100", "50", "MISS"]
const GRADE_COL := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.55, 0.85, 0.55),
	"B": Color(0.50, 0.70, 0.95), "C": Color(0.75, 0.58, 0.95), "D": Color(0.90, 0.50, 0.45),
	"F": Color(0.90, 0.40, 0.38),
}

var _data: Dictionary = {}
var _hist := PackedInt32Array()
var _hist_max := 1
var _w50 := 120.0
var _mean := 0.0
var _hist_box: Control
var _tab: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## data: s (RallyCore.stats), offsets (ms je Treffer), w50, title, artist, version,
## is_fail, new_best, allow_retry, can_replay, stars, smashes, charges.
func show_results(data: Dictionary) -> void:
	_data = data
	_w50 = maxf(float(data.get("w50", 120.0)), 1.0)
	_hist.resize(BINS)
	_hist.fill(0)
	var sum := 0.0
	var offs: Array = data.get("offsets", [])
	for o in offs:
		sum += float(o)
		var b := clampi(int(round((float(o) / _w50 * 0.5 + 0.5) * float(BINS - 1))), 0, BINS - 1)
		_hist[b] += 1
	_mean = sum / float(maxi(offs.size(), 1))
	_hist_max = 1
	for v in _hist:
		_hist_max = maxi(_hist_max, v)
	var fv := FontVariation.new()
	var base := get_theme_default_font()
	fv.base_font = base if base != null else ThemeDB.fallback_font
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	_tab = fv
	_build()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func _label(text: String, size_px: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _stat(caption: String, value: String, size_px: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.add_child(_label(caption, 12, UiTheme.DIM, UiTheme.heading_font(3)))
	v.add_child(_label(value, size_px, UiTheme.TEXT, _tab))
	return v


func _build() -> void:
	var s: Dictionary = _data.get("s", {})
	var failed := bool(_data.get("is_fail", false))
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.glass_box(14, 0.6, 0.12))
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(pad)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 44)
	pad.add_child(root)

	# Links: Rang.
	var left := VBoxContainer.new()
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.custom_minimum_size = Vector2(210, 0)
	root.add_child(left)
	var g := "F" if failed else str(s.get("grade", "D"))
	var grade := _label(g, 150, GRADE_COL.get(g, UiTheme.TEXT), UiTheme.heading_font(1))
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(grade)
	var tag := _label(tr("RALLY"), 13, UiTheme.ACCENT2, UiTheme.heading_font(4))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(tag)
	if failed:
		var f := _label(tr("GESCHEITERT"), 14, UiTheme.BAD, UiTheme.heading_font(3))
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(f)
	elif bool(_data.get("new_best", false)):
		var nb := _label(tr("NEUE BESTLEISTUNG"), 13, UiTheme.GOOD, UiTheme.heading_font(3))
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(nb)

	# Rechts: Titel, Zahlen, Stufen, Histogramm, Knoepfe.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(560, 0)
	root.add_child(right)
	var title := _label(str(_data.get("title", "")), 28, UiTheme.TEXT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(title)
	right.add_child(_label("%s  ·  %s" % [_data.get("artist", ""), _data.get("version", "")], 15, UiTheme.DIM))
	right.add_child(_label(UiTheme.fmt_score(int(s.get("score", 0))), 60, UiTheme.TEXT, _tab))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.add_child(_stat(tr("GENAUIGKEIT"), UiTheme.fmt_pct(float(s.get("accuracy", 0.0)) * 100.0), 32))
	row.add_child(_stat(tr("BESTE SERIE"), "%dx" % int(s.get("max_combo", 0)), 26))
	row.add_child(_stat(tr("SCHMETTERBÄLLE"), str(int(_data.get("smashes", 0))), 26))
	row.add_child(_stat(tr("AUFLADEN"), str(int(_data.get("charges", 0))), 26))
	right.add_child(row)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 26)
	right.add_child(mid)
	var tiers := VBoxContainer.new()
	tiers.add_theme_constant_override("separation", 4)
	tiers.custom_minimum_size = Vector2(190, 0)
	mid.add_child(tiers)
	var counts := [int(s.get("n_max", 0)), int(s.get("n300", 0)), int(s.get("n200", 0)),
			int(s.get("n100", 0)), int(s.get("n50", 0)), int(s.get("n_miss", 0))]
	for q in 6:
		var line := HBoxContainer.new()
		var nm := _label(TIER_NAMES[q], 14, TIER_COLS[q], UiTheme.heading_font(3))
		nm.custom_minimum_size = Vector2(70, 0)
		line.add_child(nm)
		var c := _label(str(counts[q]), 16, UiTheme.TEXT, _tab)
		c.custom_minimum_size = Vector2(60, 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(c)
		tiers.add_child(line)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 4)
	mid.add_child(hv)
	var hl := HBoxContainer.new()
	hl.add_child(_label(tr("FRÜH"), 12, Color(0.55, 0.75, 0.95), UiTheme.heading_font(3)))
	var mean := _label("%s  %+d ms" % [tr("Ø TIMING"), int(round(_mean))], 12, UiTheme.DIM, _tab)
	mean.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_child(mean)
	hl.add_child(_label(tr("SPÄT"), 12, Color(0.97, 0.66, 0.50), UiTheme.heading_font(3)))
	hv.add_child(hl)
	_hist_box = Control.new()
	_hist_box.custom_minimum_size = Vector2(0, 120)
	_hist_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hist_box.draw.connect(_draw_hist)
	hv.add_child(_hist_box)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	right.add_child(btns)
	if bool(_data.get("allow_retry", true)):
		btns.add_child(_button(tr("Nochmal"), true, func(): retry_pressed.emit()))
	if bool(_data.get("can_replay", false)):
		btns.add_child(_button(tr("Replay"), false, func(): replay_pressed.emit()))
	btns.add_child(_button(tr("Zurück"), false, func(): back_pressed.emit()))


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 42)
	UiTheme.style_button(b, primary)
	b.pressed.connect(cb)
	return b


func _draw_hist() -> void:
	var sz := _hist_box.size
	_hist_box.draw_line(Vector2(sz.x * 0.5, 0), Vector2(sz.x * 0.5, sz.y), Color(1, 1, 1, 0.18), 1.0)
	var bw := sz.x / float(BINS)
	for i in BINS:
		var v := float(_hist[i]) / float(_hist_max)
		if v <= 0.0:
			continue
		var e := float(i) / float(BINS - 1) * 2.0 - 1.0
		var col := Color(0.55, 0.75, 0.95).lerp(Color(0.97, 0.66, 0.50), (e + 1.0) * 0.5)
		var hgt := maxf(v * (sz.y - 4.0), 2.0)
		_hist_box.draw_rect(Rect2(float(i) * bw + 1.0, sz.y - hgt, bw - 2.0, hgt), Color(col, 0.9))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		back_pressed.emit()
		get_viewport().set_input_as_handled()
