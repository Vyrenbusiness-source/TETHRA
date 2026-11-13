class_name DirigentResults
extends Control

## Endscreen fuer Dirigent. Rahmen, Kopf, Score, Rang, Einsatz-Stufen, Timing und
## Knoepfe kommen vom gemeinsamen ResultsScreen (gleicher Aufbau in allen Modi, im
## Multiplayer mit Rangliste). Dirigent liefert dazu die zwei Anteile (Takt 40 %,
## Einsaetze 60 %), Zielfehler und Sterne sowie den Reiter "Details": der Lauf in
## zwei Streifen ueber die Songzeit: oben die Hand je Schlag (Abstand zum Punkt:
## oben = genau, unten = Trefferradius, Kreuz = verfehlt), unten die Einsaetze
## (Zeitfehler, Kreis = A, Raute = B, Quadrat = beide). Ruhig, flach.

signal retry_pressed
signal back_pressed
signal replay_pressed

const REVEAL_S := 0.9
const GUTTER := 46.0
const MISS_H := 16.0
const TIER_COLS: Array[Color] = [
	Color(1.0, 0.96, 0.86), Color(0.62, 0.86, 1.0), Color(0.55, 0.78, 0.62),
	Color(0.80, 0.74, 0.50), Color(0.78, 0.58, 0.46), Color(0.90, 0.48, 0.48),
]
const TIER_VALUE := [1.0, 1.0, 2.0 / 3.0, 1.0 / 3.0, 1.0 / 6.0, 0.0]

var _data: Dictionary = {}
var _beats: Array = []
var _cues: Array = []
var _w50 := 120.0
var _w_max := 16.0
var _t := 0.0
var _t0 := 0.0
var _span := 0.0
var _font: Font
var _tab: Font
var _rs: ResultsScreen
var _beat_plot: Control
var _cue_plot: Control


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
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	_tab = fv
	for c in get_children():
		c.queue_free()
	_t = 0.0
	var t0 := INF
	var t1 := -INF
	for b in _beats:
		t0 = minf(t0, float(b[0]))
		t1 = maxf(t1, float(b[0]))
	for c in _cues:
		t0 = minf(t0, float(c[0]))
		t1 = maxf(t1, float(c[0]))
	_t0 = t0
	_span = maxf(t1 - t0, 0.0) if t1 > t0 else 0.0

	var s: Dictionary = (data.get("s", {}) as Dictionary).duplicate()
	s["mode"] = ScoreStore.MODE_DIRIGENT
	var d := ResultsScreen.mode_data(data, multiplayer)
	d["s"] = s
	d["is_fail"] = false
	d["offsets"] = _cue_offsets()
	d["trace"] = _acc_trace()
	d["hero_extra"] = [
		[tr("ZIELFEHLER"), "%d %%" % int(round(float(s.get("aim_err", 0.0)) * 100.0))],
		[tr("STERNE"), UiTheme.fmt_num(float(s.get("stars", 0.0)), 2)],
	]
	d["cells"] = [
		[tr("TAKT  ·  40 %"), UiTheme.fmt_pct(float(s.get("beat_acc", 0.0)) * 100.0),
			"%d / %d" % [int(s.get("beats_hit", 0)), int(s.get("beats_total", 0))]],
		[tr("EINSÄTZE  ·  60 %"), UiTheme.fmt_pct(float(s.get("cue_acc", 0.0)) * 100.0), ""],
	]
	d["can_replay"] = bool(data.get("can_replay", false))
	d["can_share"] = false
	d["allow_retry"] = bool(data.get("allow_retry", true))
	var page := _build_page()
	d["mode_page"] = {"title": tr("Details"), "content": page}

	_rs = ResultsScreen.new()
	add_child(_rs)
	_rs.retry_pressed.connect(func(): retry_pressed.emit())
	_rs.back_pressed.connect(func(): back_pressed.emit())
	_rs.replay_pressed.connect(func(): replay_pressed.emit())
	_rs.show_results(d)
	if page.get_parent() == null:
		page.queue_free()   # Multiplayer-Rangliste: kein Details-Reiter


## Zeitfehler der getroffenen Einsaetze (ms).
func _cue_offsets() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in _cues:
		if int(c[2]) != 5:
			out.append(float(c[1]))
	return out


## Genauigkeit im Verlauf wie die Wertung: Takt 40 %, Einsaetze 60 %.
func _acc_trace() -> PackedFloat32Array:
	var ev: Array = []
	for b in _beats:
		ev.append([float(b[0]), 0, clampf(float(b[2]), 0.0, 1.0)])
	for c in _cues:
		ev.append([float(c[0]), 1, TIER_VALUE[clampi(int(c[2]), 0, 5)]])
	ev.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out := PackedFloat32Array()
	var sum := [0.0, 0.0]
	var cnt := [0, 0]
	for e in ev:
		sum[int(e[1])] += float(e[2])
		cnt[int(e[1])] += 1
		var beat: float = sum[0] / float(cnt[0]) if cnt[0] > 0 else -1.0
		var cue: float = sum[1] / float(cnt[1]) if cnt[1] > 0 else -1.0
		if beat < 0.0:
			out.append(cue)
		elif cue < 0.0:
			out.append(beat)
		else:
			out.append(0.4 * beat + 0.6 * cue)
	return out


func _label(text: String, size_px: int, col: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Kleine Ueberschrift wie im ResultsScreen.
func _tag(text: String, col: Color = ResultsScreen.CAPTION) -> Label:
	return _label(text, 13, col, UiTheme.heading_font(3))


static func grade_col(g: String) -> Color:
	return ResultsScreen.GRADE_COLOR.get(g, Color(0.75, 0.76, 0.82))


## Reiter "Details": zwei Streifen ueber die Songzeit.
func _build_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visibility_changed.connect(func():
		if page.visible:
			_t = 0.0)
	page.add_child(_label(tr("SCHLÄGE  ·  Abstand zum Punkt"), 12, ResultsScreen.CAPTION))
	_beat_plot = _plot(_draw_beats)
	page.add_child(_beat_plot)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(gap)
	page.add_child(_label(tr("EINSÄTZE  ·  Zeitfehler"), 12, ResultsScreen.CAPTION))
	_cue_plot = _plot(_draw_cues)
	page.add_child(_cue_plot)
	page.add_child(_label(tr("Kreis = Taste A, Raute = Taste B, Quadrat = beide"), 12, UiTheme.DIM))
	return page


func _plot(draw_cb: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 96)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(draw_cb)
	return c


func _process(delta: float) -> void:
	if _data.is_empty() or _t > REVEAL_S + 0.1:
		return
	_t += delta
	for c in [_beat_plot, _cue_plot]:
		if c != null and is_instance_valid(c):
			c.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func _miss(ci: CanvasItem, p: Vector2) -> void:
	ci.draw_line(p - Vector2(3.0, 3.0), p + Vector2(3.0, 3.0), Color(TIER_COLS[5], 0.9), 1.5, true)
	ci.draw_line(p - Vector2(3.0, -3.0), p + Vector2(3.0, -3.0), Color(TIER_COLS[5], 0.9), 1.5, true)


## Oben: Hand je Schlag.
func _draw_beats() -> void:
	var ci := _beat_plot
	var o := Rect2(Vector2.ZERO, ci.size)
	var r := _panel(ci, o, tr("genau"), tr("Rand"))
	if _span <= 0.0:
		return
	var base_y := r.position.y + 6.0
	var hh := r.size.y - 12.0
	var nshow := int(float(_beats.size()) * clampf(_t / REVEAL_S, 0.0, 1.0))
	for i in nshow:
		var b: Array = _beats[i]
		var x := r.position.x + 8.0 + (float(b[0]) - _t0) / _span * (r.size.x - 16.0)
		var v := float(b[2])
		if v <= 0.0:
			_miss(ci, Vector2(x, o.end.y - MISS_H * 0.5))
			continue
		var y := base_y + clampf(float(b[1]) / DirigentCore.HIT_R, 0.0, 1.0) * hh
		var col := TIER_COLS[0].lerp(TIER_COLS[3], clampf((1.0 - v) / 0.12, 0.0, 1.0))
		ci.draw_circle(Vector2(x, y), 2.3, Color(col, 0.85), true, -1.0, true)


## Unten: Einsaetze.
func _draw_cues() -> void:
	var ci := _cue_plot
	var o := Rect2(Vector2.ZERO, ci.size)
	var r := _panel(ci, o, tr("früh"), tr("spät"))
	var mid := r.position.y + r.size.y * 0.5
	var half := r.size.y * 0.5
	ci.draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), Color(1, 1, 1, 0.28), 1.0)
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	ci.draw_rect(Rect2(r.position.x, mid - cw, r.size.x, cw * 2.0), Color(TIER_COLS[0], 0.05))
	if _span <= 0.0:
		return
	var ns := int(float(_cues.size()) * clampf(_t / REVEAL_S, 0.0, 1.0))
	for i in ns:
		var c: Array = _cues[i]
		var x := r.position.x + 8.0 + (float(c[0]) - _t0) / _span * (r.size.x - 16.0)
		var q := int(c[2])
		if q == 5:
			_miss(ci, Vector2(x, o.end.y - MISS_H * 0.5))
			continue
		var y := mid + clampf(float(c[1]) / _w50, -1.0, 1.0) * (half - 4.0)
		var col := Color(TIER_COLS[q], 0.85)
		var mask := int(c[3])
		var pp := Vector2(x, y)
		if mask == 1:
			ci.draw_circle(pp, 2.5, col, true, -1.0, true)
		elif mask == 2:
			ci.draw_colored_polygon(PackedVector2Array([pp + Vector2(0, -3.2), pp + Vector2(3.2, 0),
				pp + Vector2(0, 3.2), pp + Vector2(-3.2, 0)]), col)
		else:
			ci.draw_rect(Rect2(pp - Vector2(2.4, 2.4), Vector2(4.8, 4.8)), col)


## Zeichnet Rahmen und die Achsenmarken in der linken Spalte. Gibt die reine
## Plotflaeche zurueck (ohne Spalte, ohne Miss-Zeile unten): Punkte liegen nie auf Text.
func _panel(ci: CanvasItem, r: Rect2, top_tag: String, bottom_tag: String) -> Rect2:
	var plot := Rect2(r.position.x + GUTTER, r.position.y, r.size.x - GUTTER, r.size.y - MISS_H)
	ci.draw_rect(r, Color(1, 1, 1, 0.03))
	ci.draw_line(Vector2(0, 0.5), Vector2(r.end.x, 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_line(Vector2(0, r.end.y - 0.5), Vector2(r.end.x, r.end.y - 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_line(Vector2(plot.position.x, plot.position.y), Vector2(plot.position.x, plot.end.y), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_line(Vector2(plot.position.x, plot.end.y), Vector2(r.end.x, plot.end.y), Color(1, 1, 1, 0.05), 1.0)
	ci.draw_string(_font, r.position + Vector2(6, 16), top_tag, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 10.0, 11, Color(UiTheme.DIM, 0.7))
	ci.draw_string(_font, Vector2(r.position.x + 6, plot.end.y - 6), bottom_tag, HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 10.0, 11,
		Color(UiTheme.DIM, 0.7))
	return plot
