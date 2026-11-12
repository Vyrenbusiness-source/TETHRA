class_name RallyResults
extends Control

## Rally-Endbild, Vollbild zweispaltig wie das Orbit-Endbild: links der Rang und
## die Treffer-Zeitleiste (Songzeit nach rechts, Zeitfehler nach unten: oben =
## frueh, unten = spaet; Form = Ball: Kreis = A, Quadrat = B, Ring = Schmetterball;
## Farbe = Wertung; Kreuz am Rand = Miss). Rechts Kopf, Score, Zahlen, Wertungs-
## Balken, Early/Late-Histogramm, Tabelle je Taste und Knoepfe.
## Alles in _draw, Texte als Labels. Kein Leuchten, keine Deko.

signal retry_pressed
signal back_pressed
signal replay_pressed

const REVEAL_S := 0.9
const BINS := 41
const ROW_H := 22.0
const TIER_COLS: Array[Color] = [
	Color(0.98, 0.93, 0.75), Color(0.80, 0.90, 0.96), Color(0.60, 0.82, 0.56),
	Color(0.52, 0.66, 0.92), Color(0.62, 0.62, 0.66), Color(0.87, 0.44, 0.38),
]
const TIER_NAMES := ["MAX", "300", "200", "100", "50", "MISS"]
const TIER_VALUE := [1.0, 1.0, 2.0 / 3.0, 1.0 / 3.0, 1.0 / 6.0, 0.0]
const GRADE_COL := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.55, 0.85, 0.55),
	"B": Color(0.50, 0.70, 0.95), "C": Color(0.75, 0.58, 0.95), "D": Color(0.90, 0.50, 0.45),
	"F": Color(0.90, 0.40, 0.38),
}
## Wie RallyView.COL_A / COL_B / COL_SMASH (eigene Kopie: das Endbild haengt nicht an der Ansicht).
const A_COL := Color(0.52, 0.74, 0.92)
const B_COL := Color(0.95, 0.64, 0.23)
const SMASH_COL := Color(0.93, 0.90, 0.85)
const PLATE_COL := Color(0.012, 0.016, 0.028)
const EARLY_COL := Color(0.55, 0.75, 0.95)
const LATE_COL := Color(0.97, 0.66, 0.50)
const MAX_COL := Color(0.98, 0.93, 0.75)
## Freies Band oben/unten in der Zeitleiste (px).
const BAND := 30.0
## Tabellenzeilen: 4 Zonen, Schmetterball, Aufladen.
const KEY_NAMES := ["ZONE 1", "ZONE 2", "ZONE 3", "ZONE 4", "SMASH", "CHARGE"]
const KEY_ROWS := 6
const KEY_ROW_H := 17.0
const ZONE_COLS := [Color(0.52, 0.74, 0.92), Color(0.55, 0.85, 0.62), Color(0.95, 0.80, 0.35),
	Color(0.95, 0.52, 0.30)]
const CHARGE_COL := Color(0.78, 0.62, 0.95)

var _data: Dictionary = {}
var _log: Array = []          ## {t, key (0-3 Zone, 4 Schmetterball, 5 Aufladen), q, dt, charge}
var _counts: Array[int] = [0, 0, 0, 0, 0, 0]
var _hist := PackedInt32Array()
var _hist_max := 1
var _w50 := 120.0
var _w_max := 16.5
var _mean := 0.0
var _ur := 0.0
var _key_rows: Array = []     ## je Taste {n, hit, val, dt}
var _t := 0.0
var _font: Font
var _tab: Font
var _grade: Label
var _score: Label
var _right: VBoxContainer
var _tier_rows: Control
var _hist_box: Control
var _keys_box: Control
var _cap_plot: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Ein Log-Eintrag je gewertetem Schlag (RallyGame._result_log): t (Notenzeit),
## key (Zone 0-3; Aufladen = 5, Schmetterball = 4), quality, dt (ms).
static func entry(shot_t: float, key: int, smash: bool, charge: bool, result: Dictionary) -> Dictionary:
	var row := 5 if charge else (4 if smash else clampi(key, 0, 3))
	return {"t": shot_t, "key": row, "q": int(result.get("quality", 5)),
		"dt": float(result.get("dt", 0.0)), "charge": charge}


## data: s (RallyCore.stats), log (entry je Schlag), w50/w_max (ms), title, artist,
## version, is_fail, new_best, allow_retry, can_replay, smashes, charges.
func show_results(data: Dictionary) -> void:
	_data = data
	_log.clear()
	for e in data.get("log", []):
		if e is Dictionary:
			_log.append({"t": float(e.get("t", 0.0)), "key": clampi(int(e.get("key", 0)), 0, KEY_ROWS - 1),
				"q": clampi(int(e.get("q", 5)), 0, 5), "dt": float(e.get("dt", 0.0)),
				"charge": bool(e.get("charge", false))})
	_w50 = maxf(float(data.get("w50", 120.0)), 1.0)
	_w_max = float(data.get("w_max", 16.5))
	var s: Dictionary = data.get("s", {})
	_counts = [int(s.get("n_max", 0)), int(s.get("n300", 0)), int(s.get("n200", 0)),
		int(s.get("n100", 0)), int(s.get("n50", 0)), int(s.get("n_miss", 0))]
	_summarize()
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	_tab = fv
	_build(s)
	_t = 0.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


## Histogramm, Mittel/UR und Tasten-Tabelle aus dem Log.
func _summarize() -> void:
	_hist.resize(BINS)
	_hist.fill(0)
	var sum := 0.0
	var sq := 0.0
	var n := 0
	_key_rows = []
	for k in KEY_ROWS:
		_key_rows.append({"n": 0, "hit": 0, "val": 0.0, "dt": 0.0})
	for e in _log:
		var q: int = e.q
		var kr: Dictionary = _key_rows[e.key]
		kr.n += 1
		kr.val += TIER_VALUE[q]
		if q == 5:
			continue
		kr.hit += 1
		var dt := float(e.dt)
		kr.dt += dt
		sum += dt
		sq += dt * dt
		n += 1
		var b := clampi(int(round((dt / _w50 * 0.5 + 0.5) * float(BINS - 1))), 0, BINS - 1)
		_hist[b] += 1
	_mean = sum / float(maxi(n, 1))
	# Unstable Rate wie osu!: 10 x Standardabweichung des Zeitfehlers.
	_ur = 10.0 * sqrt(maxf(sq / float(maxi(n, 1)) - _mean * _mean, 0.0)) if n > 1 else 0.0
	_hist_max = 1
	for v in _hist:
		_hist_max = maxi(_hist_max, v)


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
	return _label(text, 12, col, UiTheme.heading_font(4))


func _stat(caption: String, value: String, size_px: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_tag(caption, UiTheme.DIM))
	v.add_child(_label(value, size_px, UiTheme.TEXT, _tab))
	return v


func _build(s: Dictionary) -> void:
	var fail := bool(_data.get("is_fail", false))
	var g := "F" if fail else str(s.get("grade", "D"))
	_grade = _label(g, 104, GRADE_COL.get(g, UiTheme.TEXT), UiTheme.heading_font(1))
	_grade.name = "Grade"
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_grade)
	# Ueberschrift als Label: die Ueberschriftschrift zeichnet in _draw nicht sauber.
	_cap_plot = _tag(tr("HIT TIMELINE"), UiTheme.DIM)
	add_child(_cap_plot)

	_right = VBoxContainer.new()
	_right.anchor_left = 0.52
	_right.anchor_right = 0.96
	_right.anchor_top = 0.0
	_right.anchor_bottom = 1.0
	_right.offset_top = 36
	_right.offset_bottom = -28
	_right.add_theme_constant_override("separation", 8)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_tag(tr("RALLY") + "  ·  " + tr("RESULT"), Color(A_COL, 0.85)))
	var mods := str(s.get("mods_text", ""))
	if mods == "" and s.get("mods", []) is Array:
		mods = " ".join(PackedStringArray(s.get("mods", [])))
	if mods != "":
		head.add_child(_tag(mods, UiTheme.DIM))
	if fail:
		head.add_child(_tag(tr("FAILED"), TIER_COLS[5]))
	elif bool(_data.get("new_best", false)):
		head.add_child(_tag(tr("NEW BEST"), B_COL))
	_right.add_child(head)
	var title := _label(str(_data.get("title", "")), 28, UiTheme.TEXT)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	_right.add_child(title)
	_right.add_child(_label("%s  ·  %s" % [_data.get("artist", ""), _data.get("version", "")], 14, UiTheme.DIM))

	_score = _label(UiTheme.fmt_score(0), 58, UiTheme.TEXT, _tab)
	_score.name = "Score"
	_right.add_child(_score)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.add_child(_stat(tr("ACCURACY"), UiTheme.fmt_pct(float(s.get("accuracy", 0.0)) * 100.0), 30))
	row.add_child(_stat(tr("BEST STREAK"), "%dx" % int(s.get("max_combo", 0)), 24))
	row.add_child(_stat(tr("SMASHES"), str(int(_data.get("smashes", 0))), 24))
	row.add_child(_stat(tr("CHARGES"), str(int(_data.get("charges", 0))), 24))
	row.add_child(_stat(tr("UR"), UiTheme.fmt_num(_ur, 0), 24))
	_right.add_child(row)

	# Wertungs-Balken links, Early/Late-Histogramm rechts: spart Hoehe.
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 26)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(mid)
	_tier_rows = Control.new()
	_tier_rows.custom_minimum_size = Vector2(230, 6 * ROW_H)
	_tier_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tier_rows.draw.connect(_draw_tiers)
	mid.add_child(_tier_rows)
	for q in 6:
		var nm := _label(TIER_NAMES[q], 13, TIER_COLS[q], UiTheme.heading_font(3))
		nm.position = Vector2(0, q * ROW_H + 2)
		_tier_rows.add_child(nm)
		var cnt := _label(str(_counts[q]), 15, UiTheme.TEXT, _tab)
		cnt.position = Vector2(62, q * ROW_H)
		cnt.size = Vector2(50, 20)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_tier_rows.add_child(cnt)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(hv)
	var hl := HBoxContainer.new()
	hl.add_child(_tag(tr("EARLY"), EARLY_COL))
	# Normale Schrift: die Ueberschriftschrift hat kein "Ø".
	var mean := _label("%s  %+d ms" % [tr("AVG TIMING"), int(round(_mean))], 12, Color(B_COL, 0.9), _tab)
	mean.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_child(mean)
	hl.add_child(_tag(tr("LATE"), LATE_COL))
	hv.add_child(hl)
	_hist_box = Control.new()
	_hist_box.custom_minimum_size = Vector2(0, 6 * ROW_H - 20)
	_hist_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hist_box.draw.connect(_draw_hist)
	hv.add_child(_hist_box)

	_build_keys()

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(grow)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	if bool(_data.get("allow_retry", true)):
		var retry := Button.new()
		retry.name = "RetryButton"
		retry.text = tr("Retry") + "  (R)"
		retry.custom_minimum_size = Vector2(150, 44)
		UiTheme.style_button(retry, true)
		retry.pressed.connect(func(): retry_pressed.emit())
		btns.add_child(retry)
	if bool(_data.get("can_replay", false)):
		var rp := Button.new()
		rp.name = "ReplayButton"
		rp.text = tr("Watch replay")
		rp.custom_minimum_size = Vector2(170, 44)
		UiTheme.style_ghost_button(rp)
		rp.pressed.connect(func(): replay_pressed.emit())
		btns.add_child(rp)
	var back := Button.new()
	back.name = "BackButton"
	back.text = tr("Back") + "  (Esc)"
	back.custom_minimum_size = Vector2(150, 44)
	UiTheme.style_ghost_button(back)
	back.pressed.connect(func(): back_pressed.emit())
	btns.add_child(back)
	_right.add_child(btns)


## Tabelle je Taste: Treffer/Schlaege, Genauigkeit, mittlerer Zeitfehler.
func _build_keys() -> void:
	_keys_box = Control.new()
	_keys_box.name = "KeyStats"
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_box.draw.connect(_draw_keys)
	_right.add_child(_keys_box)
	var cols := [[tr("ZONE"), 22.0, 0], [tr("HITS"), 230.0, 1], [tr("ACCURACY"), 340.0, 1],
		[tr("AVG TIMING"), 450.0, 1]]
	for c in cols:
		var l := _tag(c[0], UiTheme.DIM)
		if c[2] == 1:
			l.size = Vector2(110, 16)
			l.position = Vector2(float(c[1]) - 110.0, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.position = Vector2(float(c[1]), 0)
		_keys_box.add_child(l)
	for k in KEY_ROWS:
		var kr: Dictionary = _key_rows[k]
		var y := 18.0 + float(k) * KEY_ROW_H
		var dim := int(kr.n) == 0
		var nm := _label(tr(KEY_NAMES[k]), 13, UiTheme.DIM if dim else UiTheme.TEXT)
		nm.position = Vector2(22, y)
		_keys_box.add_child(nm)
		var vals := ["%d / %d" % [int(kr.hit), int(kr.n)],
			"—" if dim else UiTheme.fmt_pct(float(kr.val) / float(kr.n) * 100.0),
			"—" if int(kr.hit) == 0 else "%+d ms" % int(round(float(kr.dt) / float(kr.hit)))]
		for i in 3:
			var v := _label(vals[i], 13, UiTheme.DIM if dim else UiTheme.TEXT, _tab)
			v.size = Vector2(110, 20)
			v.position = Vector2(float(cols[i + 1][1]) - 110.0, y)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_keys_box.add_child(v)
	_keys_box.custom_minimum_size = Vector2(0, 18.0 + float(KEY_ROWS) * KEY_ROW_H + 4.0)


static func _shape(ci: CanvasItem, p: Vector2, k: int, h: float, col: Color) -> void:
	if k < 4:
		ci.draw_circle(p, h, col, true, -1.0, true)
	elif k == 5:
		ci.draw_rect(Rect2(p - Vector2(h, h) * 0.9, Vector2(h, h) * 1.8), col)
	else:
		ci.draw_arc(p, h * 0.85, 0.0, TAU, 20, col, 1.6, true)


static func _key_col(k: int) -> Color:
	if k < 4:
		return ZONE_COLS[k]
	return SMASH_COL if k == 4 else CHARGE_COL


func _process(delta: float) -> void:
	if _data.is_empty():
		return
	_t += delta
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	_score.text = UiTheme.fmt_score(int(float(_data.get("s", {}).get("score", 0)) * e))
	_grade.add_theme_font_size_override("font_size", int(size.y * 0.2))
	_grade.size = Vector2(size.y * 0.34, size.y * 0.26)
	_grade.position = _grade_center() - _grade.size * 0.5
	_cap_plot.position = _plot_rect().position - Vector2(0, 22)
	if k < 1.0 or _t < REVEAL_S + 0.1:
		queue_redraw()
		_hist_box.queue_redraw()
		_tier_rows.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		back_pressed.emit()
		get_viewport().set_input_as_handled()


func _grade_center() -> Vector2:
	return Vector2(size.x * 0.135, size.y * 0.17)


## Plotflaeche der Zeitleiste.
func _plot_rect() -> Rect2:
	return Rect2(size.x * 0.04, size.y * 0.36, size.x * 0.43, size.y * 0.46)


func _draw() -> void:
	if _data.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(PLATE_COL, 0.97))
	_draw_timeline()


func _draw_timeline() -> void:
	var r := _plot_rect()
	var mid := r.position.y + r.size.y * 0.5
	var half := r.size.y * 0.5
	var fs := 12
	draw_rect(r, Color(1, 1, 1, 0.025))
	# MAX-Fenster, 50er-Fenster (Rand) und Nulllinie.
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	draw_rect(Rect2(r.position.x, mid - cw, r.size.x, cw * 2.0), Color(MAX_COL, 0.05))
	draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), Color(1, 1, 1, 0.30), 1.0)
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), r.end, Color(1, 1, 1, 0.08), 1.0)
	draw_string(_font, r.position + Vector2(6, 16), tr("EARLY"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(EARLY_COL, 0.8))
	draw_string(_font, Vector2(r.position.x + 6, r.end.y - 16), tr("LATE"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(LATE_COL, 0.8))
	var ms := "±%d ms" % int(round(_w50))
	var mw := _tab.get_string_size(ms, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_tab, Vector2(r.end.x - mw - 6.0, r.position.y + 16.0), ms, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.7))
	if not _log.is_empty():
		var t0 := INF
		var t1 := -INF
		for e in _log:
			t0 = minf(t0, float(e.t))
			t1 = maxf(t1, float(e.t))
		var span := maxf(t1 - t0, 1.0)
		# Schlaege in Spielreihenfolge einblenden.
		var shown := int(float(_log.size()) * clampf(_t / REVEAL_S, 0.0, 1.0))
		for i in shown:
			var e: Dictionary = _log[i]
			var q: int = e.q
			var x := r.position.x + 8.0 + (float(e.t) - t0) / span * (r.size.x - 16.0)
			if q == 5:
				var p := Vector2(x, r.end.y - 5.0)
				var h := 3.5
				draw_line(p - Vector2(h, h), p + Vector2(h, h), Color(TIER_COLS[5], 0.9), 1.5, true)
				draw_line(p - Vector2(h, -h), p + Vector2(h, -h), Color(TIER_COLS[5], 0.9), 1.5, true)
				continue
			# Oben/unten bleibt ein Band frei fuer FRUEH/SPAET und die Miss-Kreuze.
			var y := mid + clampf(float(e.dt) / _w50, -1.0, 1.0) * (half - BAND)
			_shape(self, Vector2(x, y), int(e.key), 2.3, Color(TIER_COLS[q], 0.85))
	# Legende: Formen statt Text allein.
	var lx := r.position.x
	var ly := r.end.y + 20.0
	for k in [0, 4, 5]:
		var nm := tr("ZONE") if k == 0 else tr(KEY_NAMES[k])
		_shape(self, Vector2(lx + 4.0, ly - 4.0), k, 3.0, Color(UiTheme.DIM, 0.9))
		draw_string(_font, Vector2(lx + 12.0, ly), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.9))
		lx += 24.0 + _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(lx + 8.0, ly), tr("× = Miss  ·  colour = rating"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.7))


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


func _draw_hist() -> void:
	var sz := _hist_box.size
	var bw := sz.x / float(BINS)
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	var cw := _w_max / _w50 * sz.x * 0.5
	_hist_box.draw_rect(Rect2(sz.x * 0.5 - cw, 0, cw * 2.0, sz.y), Color(MAX_COL, 0.05))
	for b in BINS:
		var v := float(_hist[b]) / float(_hist_max)
		if v <= 0.0:
			continue
		var h := maxf(v * (sz.y - 6.0) * k, 1.0)
		var m := float(b) / float(BINS - 1) - 0.5
		var col := EARLY_COL if m < 0.0 else LATE_COL
		col = col.lerp(MAX_COL, 1.0 - clampf(absf(m) * 4.0, 0.0, 1.0))
		_hist_box.draw_rect(Rect2(float(b) * bw + 1.0, sz.y - h, bw - 2.0, h), Color(col, 0.85))
	_hist_box.draw_line(Vector2(sz.x * 0.5, 0), Vector2(sz.x * 0.5, sz.y), Color(1, 1, 1, 0.35), 1.0)
	var mx := sz.x * 0.5 + clampf(_mean / _w50, -1.0, 1.0) * sz.x * 0.5
	_hist_box.draw_line(Vector2(mx, 0), Vector2(mx, sz.y), Color(B_COL, 0.8), 2.0)
	_hist_box.draw_line(Vector2(0, sz.y), Vector2(sz.x, sz.y), Color(1, 1, 1, 0.15), 1.0)


func _draw_keys() -> void:
	for k in KEY_ROWS:
		var y := 18.0 + float(k) * KEY_ROW_H + 8.0
		var dim := int(_key_rows[k].n) == 0
		_shape(_keys_box, Vector2(8.0, y), k, 3.6, Color(_key_col(k), 0.35 if dim else 0.95))
		_keys_box.draw_line(Vector2(0, y + KEY_ROW_H * 0.5 + 0.5), Vector2(450, y + KEY_ROW_H * 0.5 + 0.5),
			Color(1, 1, 1, 0.04), 1.0)
