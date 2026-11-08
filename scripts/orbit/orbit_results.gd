class_name OrbitResults
extends Control

## Eigener Endscreen fuer Orbit (nicht der Mania-ResultsScreen).
## Links die "Orbit-Karte": jedes Ziel an seinem Winkel auf seinem Ring,
## radial versetzt um seinen Zeitfehler (innen = frueh, aussen = spaet),
## Farbe = Stufe. In der Mitte der Rang. Rechts Score, Acc, Serie,
## Zielfehler, Stufen-Tabelle und ein Timing-Histogramm.
## Alles in einem _draw; Texte als Labels. Ruhig, kein Leuchten.

signal retry_pressed
signal back_pressed

const REVEAL_S := 0.9
const BINS := 41
const TIER_COLS: Array[Color] = [
	Color(1.0, 0.96, 0.86),   # CORE: creme
	Color(0.62, 0.86, 1.0),   # SHARP
	Color(0.55, 0.78, 0.62),  # GOOD
	Color(0.80, 0.74, 0.50),  # FAIR
	Color(0.78, 0.58, 0.46),  # EDGE
	Color(0.90, 0.48, 0.48),  # MISS
]

var _data: Dictionary = {}
var _log: Array = []
var _w50 := 120.0
var _w_max := 16.0
var _t := 0.0
var _counts: Array[int] = [0, 0, 0, 0, 0, 0]
var _hist := PackedInt32Array()
var _hist_max := 1
var _mean_dt := 0.0
var _font: Font
var _tab: Font
var _grade: Label
var _score: Label
var _right: VBoxContainer
var _tier_rows: Control
var _hist_box: Control
var _quad := PackedVector2Array()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_quad.resize(4)


## data: s (OrbitCore.stats + failed), log ([Winkel, Ring, dt, Zielfehler,
## Stufe, Zeit] je Ziel), w50/w_max (ms), title, artist, version, is_fail,
## new_best, allow_retry.
func show_results(data: Dictionary) -> void:
	_data = data
	_log = data.get("log", [])
	_w50 = maxf(float(data.get("w50", 120.0)), 1.0)
	_w_max = float(data.get("w_max", 16.0))
	var s: Dictionary = data.get("s", {})
	_counts = [int(s.get("n_max", 0)), int(s.get("n300", 0)), int(s.get("n200", 0)),
		int(s.get("n100", 0)), int(s.get("n50", 0)), int(s.get("n_miss", 0))]
	_hist.resize(BINS)
	_hist.fill(0)
	var sum := 0.0
	var n := 0
	for e in _log:
		if int(e[4]) == 5:
			continue
		var dt := float(e[2])
		sum += dt
		n += 1
		var b := clampi(int(round((dt / _w50 * 0.5 + 0.5) * float(BINS - 1))), 0, BINS - 1)
		_hist[b] += 1
	_mean_dt = sum / float(maxi(n, 1))
	_hist_max = 1
	for v in _hist:
		_hist_max = maxi(_hist_max, v)
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	_tab = fv
	_build(s)
	_t = 0.0
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


func _tag(text: String, col: Color) -> Label:
	var l := _label(text, 12, col, UiTheme.heading_font(4))
	return l


func _build(s: Dictionary) -> void:
	var fail := bool(_data.get("is_fail", false))
	var g := "F" if fail else str(s.get("grade", "D"))
	_grade = _label(g, 96, _grade_col(g), UiTheme.heading_font(0))
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_grade)

	_right = VBoxContainer.new()
	_right.anchor_left = 0.50
	_right.anchor_right = 0.95
	_right.anchor_top = 0.0
	_right.anchor_bottom = 1.0
	_right.offset_top = 64
	_right.offset_bottom = -48
	_right.add_theme_constant_override("separation", 10)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_tag(tr("ORBIT") + "  ·  " + tr("ERGEBNIS"), Color(OrbitView.INNER_COL, 0.85)))
	if fail:
		head.add_child(_tag(tr("GESCHEITERT"), TIER_COLS[5]))
	elif bool(_data.get("new_best", false)):
		head.add_child(_tag(tr("NEUER BESTWERT"), OrbitView.OUTER_COL))
	_right.add_child(head)
	var title := _label(str(_data.get("title", "")), 30, UiTheme.TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	_right.add_child(title)
	_right.add_child(_label("%s  ·  %s" % [_data.get("artist", ""), _data.get("version", "")], 15, UiTheme.DIM))

	_right.add_child(_spacer(6))
	_score = _label(UiTheme.fmt_score(0), 64, UiTheme.TEXT, _tab)
	_right.add_child(_score)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.add_child(_stat(tr("GENAUIGKEIT"), UiTheme.fmt_pct(float(s.get("accuracy", 0.0)) * 100.0), 34))
	row.add_child(_stat(tr("BESTE SERIE"), "%dx" % int(s.get("max_combo", 0)), 26))
	row.add_child(_stat(tr("ZIELFEHLER"), "%s°" % UiTheme.fmt_num(float(s.get("aim_err", 0.0)), 1), 26))
	_right.add_child(row)

	_right.add_child(_spacer(2))
	# Stufentabelle links, Timing-Histogramm rechts: spart Hoehe, Knoepfe bleiben im Bild.
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 26)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(mid)
	_tier_rows = Control.new()
	_tier_rows.custom_minimum_size = Vector2(250, 6 * 26)
	_tier_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_rows.size_flags_stretch_ratio = 1.0
	_tier_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier_rows.draw.connect(_draw_tiers)
	mid.add_child(_tier_rows)
	for q in 6:
		var name := _label(tr(OrbitCore.TIER_NAMES[q]), 13, TIER_COLS[q], UiTheme.heading_font(3))
		name.position = Vector2(0, q * 26 + 3)
		_tier_rows.add_child(name)
		var cnt := _label(str(_counts[q]), 15, UiTheme.TEXT, _tab)
		cnt.position = Vector2(66, q * 26 + 1)
		cnt.size = Vector2(50, 22)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tier_rows.add_child(cnt)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(hv)
	var hl := HBoxContainer.new()
	hl.add_child(_tag(tr("FRÜH"), OrbitView.EARLY_COL))
	# Normale Schrift: die Ueberschriftschrift hat kein "Ø".
	var mean := _label("%s  %+d ms" % [tr("Ø TIMING"), int(round(_mean_dt))], 12, Color(OrbitView.OUTER_COL, 0.9), _tab)
	mean.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_child(mean)
	hl.add_child(_tag(tr("SPÄT"), OrbitView.LATE_COL))
	hv.add_child(hl)
	_hist_box = Control.new()
	_hist_box.custom_minimum_size = Vector2(0, 6 * 26 - 24)
	_hist_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hist_box.draw.connect(_draw_hist)
	hv.add_child(_hist_box)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(grow)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	if bool(_data.get("allow_retry", true)):
		var retry := Button.new()
		retry.text = tr("Nochmal") + "  (R)"
		retry.custom_minimum_size = Vector2(170, 46)
		UiTheme.style_button(retry, true)
		retry.pressed.connect(func(): retry_pressed.emit())
		btns.add_child(retry)
	var back := Button.new()
	back.text = tr("Zurück") + "  (Esc)"
	back.custom_minimum_size = Vector2(170, 46)
	UiTheme.style_ghost_button(back)
	back.pressed.connect(func(): back_pressed.emit())
	btns.add_child(back)
	_right.add_child(btns)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _stat(caption: String, value: String, size_px: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tag(caption, UiTheme.DIM))
	v.add_child(_label(value, size_px, UiTheme.TEXT, _tab))
	return v


static func _grade_col(g: String) -> Color:
	match g:
		"SS": return Color(1.0, 0.96, 0.86)
		"S": return Color(1.0, 0.86, 0.52)
		"A": return Color(0.55, 0.92, 0.70)
		"B": return Color(0.55, 0.78, 1.0)
		"C": return Color(0.78, 0.66, 0.95)
		"F": return Color(0.90, 0.48, 0.48)
	return Color(0.75, 0.76, 0.82)


func _process(delta: float) -> void:
	if _data.is_empty():
		return
	_t += delta
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var sc := int(float(_data.get("s", {}).get("score", 0)) * e)
	_score.text = UiTheme.fmt_score(sc)
	var c := _chart_center()
	_grade.position = c - Vector2(120, 70)
	_grade.size = Vector2(240, 140)
	if k < 1.0 or _t < REVEAL_S + 0.1:
		queue_redraw()
		_hist_box.queue_redraw()
		_tier_rows.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func _chart_center() -> Vector2:
	return Vector2(size.x * 0.26, size.y * 0.52)


func _chart_r() -> float:
	return minf(size.y * 0.36, size.x * 0.21)


func _draw() -> void:
	if _data.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(OrbitView.PLATE_COL, 0.97))
	var c := _chart_center()
	var R := _chart_r()
	var radii: Array[float] = [R * 0.56, R]
	var band := R * 0.13
	var cols: Array[Color] = [OrbitView.INNER_COL, OrbitView.OUTER_COL]
	# Timing-Band je Ring (Breite = 50er-Fenster), feine Ringlinie = 0 ms.
	for r in 2:
		draw_arc(c, radii[r], 0.0, TAU, 160, Color(cols[r], 0.06), band * 2.0, true)
		draw_arc(c, radii[r], 0.0, TAU, 160, Color(cols[r], 0.5), 1.5, true)
		draw_arc(c, radii[r] - band, 0.0, TAU, 160, Color(cols[r], 0.12), 1.0, true)
		draw_arc(c, radii[r] + band, 0.0, TAU, 160, Color(cols[r], 0.12), 1.0, true)
	# Teilstriche alle 45 Grad.
	for k in 8:
		var deg := float(k) * 45.0
		draw_line(OrbitView.polar(c, deg, R * 0.3), OrbitView.polar(c, deg, R + band + 10.0),
			Color(1, 1, 1, 0.05), 1.0, true)
	# Ziele in Spielreihenfolge einblenden.
	var shown := int(float(_log.size()) * clampf(_t / REVEAL_S, 0.0, 1.0))
	for i in shown:
		var e: Array = _log[i]
		var q := int(e[4])
		var ring := int(e[1])
		var deg := float(e[0])
		if q == 5:
			var p := OrbitView.polar(c, deg, radii[ring])
			var h := 4.0
			draw_line(p - Vector2(h, h), p + Vector2(h, h), Color(TIER_COLS[5], 0.9), 1.5, true)
			draw_line(p - Vector2(h, -h), p + Vector2(h, -h), Color(TIER_COLS[5], 0.9), 1.5, true)
			continue
		var off := clampf(float(e[2]) / _w50, -1.0, 1.0) * band
		var p := OrbitView.polar(c, deg, radii[ring] + off)
		var col := TIER_COLS[q]
		if ring == 0:
			draw_circle(p, 2.6, Color(col, 0.85), true, -1.0, true)
		else:
			var a := deg_to_rad(deg)
			var ur := Vector2(sin(a), -cos(a)) * 3.4
			var ut := Vector2(cos(a), sin(a)) * 3.4
			_quad[0] = p + ur
			_quad[1] = p + ut
			_quad[2] = p - ur
			_quad[3] = p - ut
			draw_colored_polygon(_quad, Color(col, 0.85))
	# Lesehilfe unter der Karte.
	var hint := tr("innen = früh  ·  außen = spät")
	var fs := 12
	var tw := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(c.x - tw * 0.5, c.y + R + band + 34.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.8))


func _draw_tiers() -> void:
	var total := 0
	for v in _counts:
		total += v
	var x0 := 124.0
	var w := maxf(_tier_rows.size.x - x0, 10.0)
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	for q in 6:
		var y := float(q) * 26.0 + 9.0
		_tier_rows.draw_rect(Rect2(x0, y, w, 6), Color(1, 1, 1, 0.05))
		var f := float(_counts[q]) / float(maxi(total, 1)) * k
		if f > 0.0:
			_tier_rows.draw_rect(Rect2(x0, y, maxf(w * f, 2.0), 6), Color(TIER_COLS[q], 0.85))


func _draw_hist() -> void:
	var sz := _hist_box.size
	var bw := sz.x / float(BINS)
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	# CORE-Zeitfenster als helle Zone in der Mitte.
	var cw := _w_max / _w50 * sz.x * 0.5
	_hist_box.draw_rect(Rect2(sz.x * 0.5 - cw, 0, cw * 2.0, sz.y), Color(1, 0.96, 0.86, 0.05))
	for b in BINS:
		var v := float(_hist[b]) / float(_hist_max)
		if v <= 0.0:
			continue
		var h := maxf(v * (sz.y - 6.0) * k, 1.0)
		var mid := float(b) / float(BINS - 1) - 0.5
		var col := OrbitView.EARLY_COL if mid < 0.0 else OrbitView.LATE_COL
		col = col.lerp(Color(1, 0.96, 0.86), 1.0 - clampf(absf(mid) * 4.0, 0.0, 1.0))
		_hist_box.draw_rect(Rect2(float(b) * bw + 1.0, sz.y - h, bw - 2.0, h), Color(col, 0.85))
	_hist_box.draw_line(Vector2(sz.x * 0.5, 0), Vector2(sz.x * 0.5, sz.y), Color(1, 1, 1, 0.35), 1.0)
	var mx := sz.x * 0.5 + clampf(_mean_dt / _w50, -1.0, 1.0) * sz.x * 0.5
	_hist_box.draw_line(Vector2(mx, 0), Vector2(mx, sz.y), Color(OrbitView.OUTER_COL, 0.8), 2.0)
	_hist_box.draw_line(Vector2(0, sz.y), Vector2(sz.x, sz.y), Color(1, 1, 1, 0.15), 1.0)
