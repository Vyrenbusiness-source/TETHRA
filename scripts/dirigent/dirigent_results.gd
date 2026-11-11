class_name DirigentResults
extends Control

## Endscreen fuer Dirigent. Links der Lauf in zwei Streifen ueber die Songzeit:
## oben die Hand je Schlag (Abstand zum Punkt: Mitte = genau, Rand = Trefferradius,
## Kreuz unten = verfehlt), unten die Einsaetze (Zeitfehler, Kreis = A, Raute = B,
## Quadrat = beide). Rechts Score, Acc, die zwei Anteile, Stufen. Ruhig, flach.

signal retry_pressed
signal back_pressed
signal replay_pressed

const REVEAL_S := 0.9
const ROW_H := 22.0
const GUTTER := 46.0
const MISS_H := 16.0
const TIER_COLS: Array[Color] = [
	Color(1.0, 0.96, 0.86), Color(0.62, 0.86, 1.0), Color(0.55, 0.78, 0.62),
	Color(0.80, 0.74, 0.50), Color(0.78, 0.58, 0.46), Color(0.90, 0.48, 0.48),
]
const TIER_NAMES: Array[String] = ["MAX", "300", "200", "100", "50", "MISS"]

var _data: Dictionary = {}
var _beats: Array = []
var _cues: Array = []
var _w50 := 120.0
var _w_max := 16.0
var _t := 0.0
var _counts: Array[int] = [0, 0, 0, 0, 0, 0]
var _font: Font
var _tab: Font
var _grade: Label
var _score: Label
var _tier_rows: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## data: s (DirigentCore.stats), beats ([Zeit, Abstand, Wert]), cues ([Zeit, dt, Stufe,
## Maske]), w50, w_max, title, artist, version, new_best, allow_retry, can_replay, is_replay.
func show_results(data: Dictionary) -> void:
	_data = data
	_beats = data.get("beats", [])
	_cues = data.get("cues", [])
	_w50 = maxf(float(data.get("w50", 120.0)), 1.0)
	_w_max = float(data.get("w_max", 16.0))
	var s: Dictionary = data.get("s", {})
	_counts = [int(s.get("n_max", 0)), int(s.get("n300", 0)), int(s.get("n200", 0)),
		int(s.get("n100", 0)), int(s.get("n50", 0)), int(s.get("n_miss", 0))]
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


func _tag(text: String, col: Color = UiTheme.DIM) -> Label:
	return _label(text, 12, col, UiTheme.heading_font(4))


static func grade_col(g: String) -> Color:
	match g:
		"SS": return Color(1.0, 0.96, 0.86)
		"S": return Color(1.0, 0.86, 0.52)
		"A": return Color(0.55, 0.92, 0.70)
		"B": return Color(0.55, 0.78, 1.0)
		"C": return Color(0.78, 0.66, 0.95)
	return Color(0.75, 0.76, 0.82)


func _stat(caption: String, value: String, size_px: int, col: Color = UiTheme.TEXT) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tag(caption))
	v.add_child(_label(value, size_px, col, _tab))
	return v


func _build(s: Dictionary) -> void:
	var g := str(s.get("grade", "D"))
	_grade = _label(g, 96, grade_col(g), UiTheme.heading_font(0))
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_grade)

	var right := VBoxContainer.new()
	right.anchor_left = 0.52
	right.anchor_right = 0.96
	right.anchor_bottom = 1.0
	right.offset_top = 36
	right.offset_bottom = -28
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_tag(tr("DIRIGENT") + "  ·  " + tr("ERGEBNIS"), Color(0.55, 0.78, 1.0, 0.85)))
	if bool(_data.get("new_best", false)):
		head.add_child(_tag(tr("NEUER BESTWERT"), UiTheme.ACCENT))
	right.add_child(head)
	var title := _label(str(_data.get("title", "")), 28, UiTheme.TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	right.add_child(title)
	right.add_child(_label("%s  ·  %s" % [_data.get("artist", ""), _data.get("version", "")], 14, UiTheme.DIM))
	_score = _label("0", 58, UiTheme.TEXT, _tab)
	right.add_child(_score)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(row)
	row.add_child(_stat(tr("GENAUIGKEIT"), UiTheme.fmt_pct(float(s.get("accuracy", 0.0)) * 100.0), 28))
	row.add_child(_stat(tr("KOMBO"), "%dx" % int(s.get("max_combo", 0)), 28))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 34)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(row2)
	var nb := int(s.get("beats_total", 0))
	row2.add_child(_stat(tr("TAKT  ·  40 %"), "%s  (%d/%d)" % [
		UiTheme.fmt_pct(float(s.get("beat_acc", 0.0)) * 100.0), int(s.get("beats_hit", 0)), nb], 20))
	row2.add_child(_stat(tr("EINSÄTZE  ·  60 %"), UiTheme.fmt_pct(float(s.get("cue_acc", 0.0)) * 100.0), 20))
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 34)
	row3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(row3)
	row3.add_child(_stat(tr("ZIELFEHLER"), "%d %%" % int(round(float(s.get("aim_err", 0.0)) * 100.0)), 20))
	row3.add_child(_stat(tr("STERNE"), UiTheme.fmt_num(float(s.get("stars", 0.0)), 2), 20))

	right.add_child(_tag(tr("EINSATZ-STUFEN")))
	_tier_rows = Control.new()
	_tier_rows.custom_minimum_size = Vector2(0, 6 * ROW_H)
	_tier_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier_rows.draw.connect(_draw_tiers)
	right.add_child(_tier_rows)
	for q in 6:
		var nm := _label(TIER_NAMES[q], 13, TIER_COLS[q], UiTheme.heading_font(3))
		nm.position = Vector2(0, float(q) * ROW_H + 2.0)
		_tier_rows.add_child(nm)
		var cnt := _label(str(_counts[q]), 15, UiTheme.TEXT, _tab)
		cnt.position = Vector2(62, float(q) * ROW_H)
		cnt.size = Vector2(50, 20)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tier_rows.add_child(cnt)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(spacer)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	right.add_child(btns)
	if bool(_data.get("allow_retry", true)):
		var retry := Button.new()
		retry.text = tr("Nochmal") + "  (R)"
		retry.custom_minimum_size = Vector2(150, 46)
		UiTheme.style_button(retry, true)
		retry.pressed.connect(func(): retry_pressed.emit())
		btns.add_child(retry)
	if bool(_data.get("can_replay", false)):
		var rp := Button.new()
		rp.text = tr("Selbst spielen") if bool(_data.get("is_replay", false)) else tr("Replay ansehen")
		rp.custom_minimum_size = Vector2(170, 46)
		UiTheme.style_ghost_button(rp)
		rp.pressed.connect(func(): replay_pressed.emit())
		btns.add_child(rp)
	var back := Button.new()
	back.text = tr("Zurück") + "  (Esc)"
	back.custom_minimum_size = Vector2(150, 46)
	UiTheme.style_ghost_button(back)
	back.pressed.connect(func(): back_pressed.emit())
	btns.add_child(back)


func _process(delta: float) -> void:
	if _data.is_empty():
		return
	_t += delta
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_score.text = UiTheme.fmt_score(int(float(_data.get("s", {}).get("score", 0)) * e))
	_grade.position = Vector2(size.x * 0.27, size.y * 0.16) - Vector2(120, 70)
	_grade.size = Vector2(240, 140)
	if k < 1.0 or _t < REVEAL_S + 0.1:
		queue_redraw()
		_tier_rows.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ESCAPE:
			back_pressed.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and bool(_data.get("allow_retry", true)):
			retry_pressed.emit()
			get_viewport().set_input_as_handled()


func _draw_tiers() -> void:
	var total := 0
	for v in _counts:
		total += v
	var x0 := 120.0
	var w := maxf(_tier_rows.size.x - x0, 10.0)
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	for q in 6:
		var y := float(q) * ROW_H + 8.0
		_tier_rows.draw_rect(Rect2(x0, y, w, 6), Color(1, 1, 1, 0.05))
		var f := float(_counts[q]) / float(maxi(total, 1)) * k
		if f > 0.0:
			_tier_rows.draw_rect(Rect2(x0, y, maxf(w * f, 2.0), 6), Color(TIER_COLS[q], 0.85))


func _draw() -> void:
	if _data.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(DirigentView.PLATE, 0.98))
	var x0 := size.x * 0.045
	var w := size.x * 0.46
	var t0 := INF
	var t1 := -INF
	for b in _beats:
		t0 = minf(t0, float(b[0]))
		t1 = maxf(t1, float(b[0]))
	for c in _cues:
		t0 = minf(t0, float(c[0]))
		t1 = maxf(t1, float(c[0]))
	if t1 <= t0:
		return
	var span := t1 - t0
	var shown := clampf(_t / REVEAL_S, 0.0, 1.0)
	# --- Oben: Hand je Schlag ---
	var o1 := Rect2(x0, size.y * 0.33, w, size.y * 0.22)
	var r1 := _panel(o1, tr("SCHLÄGE  ·  Abstand zum Punkt"), tr("genau"), tr("Rand"))
	var base_y := r1.position.y + 6.0
	var hh := r1.size.y - 12.0
	var nshow := int(float(_beats.size()) * shown)
	for i in nshow:
		var b: Array = _beats[i]
		var x := r1.position.x + 8.0 + (float(b[0]) - t0) / span * (r1.size.x - 16.0)
		var v := float(b[2])
		if v <= 0.0:
			var p := Vector2(x, o1.end.y - MISS_H * 0.5)
			draw_line(p - Vector2(3.5, 3.5), p + Vector2(3.5, 3.5), Color(TIER_COLS[5], 0.9), 1.5, true)
			draw_line(p - Vector2(3.5, -3.5), p + Vector2(3.5, -3.5), Color(TIER_COLS[5], 0.9), 1.5, true)
			continue
		var y := base_y + clampf(float(b[1]) / DirigentCore.HIT_R, 0.0, 1.0) * hh
		var col := TIER_COLS[0].lerp(TIER_COLS[3], clampf((1.0 - v) / 0.12, 0.0, 1.0))
		draw_circle(Vector2(x, y), 2.3, Color(col, 0.85), true, -1.0, true)
	# --- Unten: Einsaetze ---
	var o2 := Rect2(x0, size.y * 0.64, w, size.y * 0.22)
	var r2 := _panel(o2, tr("EINSÄTZE  ·  Zeitfehler"), tr("früh"), tr("spät"))
	var mid := r2.position.y + r2.size.y * 0.5
	var half := r2.size.y * 0.5
	draw_line(Vector2(r2.position.x, mid), Vector2(r2.end.x, mid), Color(1, 1, 1, 0.28), 1.0)
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	draw_rect(Rect2(r2.position.x, mid - cw, r2.size.x, cw * 2.0), Color(TIER_COLS[0], 0.05))
	var ns := int(float(_cues.size()) * shown)
	for i in ns:
		var c: Array = _cues[i]
		var x := r2.position.x + 8.0 + (float(c[0]) - t0) / span * (r2.size.x - 16.0)
		var q := int(c[2])
		if q == 5:
			var p := Vector2(x, o2.end.y - MISS_H * 0.5)
			draw_line(p - Vector2(3.5, 3.5), p + Vector2(3.5, 3.5), Color(TIER_COLS[5], 0.9), 1.5, true)
			draw_line(p - Vector2(3.5, -3.5), p + Vector2(3.5, -3.5), Color(TIER_COLS[5], 0.9), 1.5, true)
			continue
		var y := mid + clampf(float(c[1]) / _w50, -1.0, 1.0) * (half - 4.0)
		var col := Color(TIER_COLS[q], 0.85)
		var mask := int(c[3])
		var pp := Vector2(x, y)
		if mask == 1:
			draw_circle(pp, 2.5, col, true, -1.0, true)
		elif mask == 2:
			draw_colored_polygon(PackedVector2Array([pp + Vector2(0, -3.2), pp + Vector2(3.2, 0),
				pp + Vector2(0, 3.2), pp + Vector2(-3.2, 0)]), col)
		else:
			draw_rect(Rect2(pp - Vector2(2.4, 2.4), Vector2(4.8, 4.8)), col)
	var hint := tr("Kreis = Taste A, Raute = Taste B, Quadrat = beide")
	draw_string(_font, Vector2(o2.position.x, o2.end.y + 22.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(UiTheme.DIM, 0.85))


## Zeichnet Rahmen, Titel und die Achsenmarken in der linken Spalte. Gibt die
## reine Plotflaeche zurueck (ohne Spalte, ohne Miss-Zeile unten): Punkte liegen nie auf Text.
func _panel(r: Rect2, title: String, top_tag: String, bottom_tag: String) -> Rect2:
	var plot := Rect2(r.position.x + GUTTER, r.position.y, r.size.x - GUTTER, r.size.y - MISS_H)
	draw_rect(r, Color(1, 1, 1, 0.025))
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), r.end, Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(plot.position.x, plot.position.y), Vector2(plot.position.x, plot.end.y), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(plot.position.x, plot.end.y), Vector2(r.end.x, plot.end.y), Color(1, 1, 1, 0.05), 1.0)
	draw_string(_font, r.position + Vector2(0, -8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UiTheme.DIM, 0.95))
	draw_string(_font, r.position + Vector2(6, 16), top_tag, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 10.0, 11, Color(UiTheme.DIM, 0.7))
	draw_string(_font, Vector2(r.position.x + 6, plot.end.y - 6), bottom_tag, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 10.0, 11,
		Color(UiTheme.DIM, 0.7))
	return plot
