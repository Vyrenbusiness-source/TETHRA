class_name RallyResults
extends Control

## Rally-Endbild. Rahmen, Kopf, Score, Rang, Wertungen, Timing und Knoepfe kommen
## vom gemeinsamen ResultsScreen (gleicher Aufbau in allen Modi, im Multiplayer
## mit Rangliste). Rally liefert dazu Schmetterbaelle und Auflader sowie den
## Reiter "Details": Treffer-Zeitleiste (Songzeit nach rechts, Zeitfehler nach
## unten: oben = frueh, unten = spaet; Form = Ball: Kreis = Zone, Ring =
## Schmetterball, Quadrat = Aufladen; Farbe = Wertung; Kreuz am Rand = Miss) und
## die Tabelle je Zone.

signal retry_pressed
signal back_pressed
signal replay_pressed

const REVEAL_S := 0.9
const TIER_COLS: Array[Color] = [
	Color(0.98, 0.93, 0.75), Color(0.80, 0.90, 0.96), Color(0.60, 0.82, 0.56),
	Color(0.52, 0.66, 0.92), Color(0.62, 0.62, 0.66), Color(0.87, 0.44, 0.38),
]
const TIER_VALUE := [1.0, 1.0, 2.0 / 3.0, 1.0 / 3.0, 1.0 / 6.0, 0.0]
## Wie RallyView.COL_SMASH (eigene Kopie: das Endbild haengt nicht an der Ansicht).
const SMASH_COL := Color(0.93, 0.90, 0.85)
const EARLY_COL := Color(0.55, 0.75, 0.95)
const LATE_COL := Color(0.97, 0.66, 0.50)
const MAX_COL := Color(0.98, 0.93, 0.75)
## Freies Band oben/unten in der Zeitleiste (px).
const BAND := 22.0
## Tabellenzeilen: 4 Zonen, Schmetterball, Aufladen.
const KEY_NAMES := ["ZONE 1", "ZONE 2", "ZONE 3", "ZONE 4", "SMASH", "CHARGE"]
const KEY_ROWS := 6
const KEY_ROW_H := 19.0
const ZONE_COLS := [Color(0.52, 0.74, 0.92), Color(0.55, 0.85, 0.62), Color(0.95, 0.80, 0.35),
	Color(0.95, 0.52, 0.30)]
const CHARGE_COL := Color(0.78, 0.62, 0.95)
## Nutzbreite im Panel des ResultsScreen (Panelbreite minus Rand).
const PAGE_W := ResultsScreen.PANEL_W - 44.0

var _data: Dictionary = {}
var _log: Array = []          ## {t, key (0-3 Zone, 4 Schmetterball, 5 Aufladen), q, dt, charge}
var _w50 := 120.0
var _w_max := 16.5
var _mean := 0.0
var _ur := 0.0
var _key_rows: Array = []     ## je Taste {n, hit, val, dt}
var _t := 0.0
var _font: Font
var _tab: Font
var _rs: ResultsScreen
var _timeline: Control
var _legend: Control
var _keys_box: Control


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
	_summarize()
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	_tab = fv
	for c in get_children():
		c.queue_free()
	_t = 0.0

	var s: Dictionary = (data.get("s", {}) as Dictionary).duplicate()
	s["mode"] = ScoreStore.MODE_RALLY
	var d := ResultsScreen.mode_data(data, multiplayer)
	d["s"] = s
	# Zeitfehler und Genauigkeit im Verlauf aus dem Log.
	var offs := PackedFloat32Array()
	var trace := PackedFloat32Array()
	var val := 0.0
	for i in _log.size():
		var e: Dictionary = _log[i]
		val += TIER_VALUE[int(e.q)]
		trace.append(val / float(i + 1))
		if int(e.q) != 5:
			offs.append(float(e.dt))
	d["offsets"] = offs
	d["trace"] = trace
	d["combo_caption"] = tr("BEST STREAK")
	d["hero_extra"] = [[tr("SMASHES"), UiTheme.fmt_score(int(data.get("smashes", 0)))]]
	d["cells"] = [[tr("CHARGES"), UiTheme.fmt_score(int(data.get("charges", 0))), ""]]
	var mods := str(s.get("mods_text", ""))
	if mods == "" and s.get("mods", []) is Array:
		mods = " ".join(PackedStringArray(s.get("mods", [])))
	d["mod_texts"] = Array(mods.split(" ", false))
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


## Mittel/UR und Tasten-Tabelle aus dem Log.
func _summarize() -> void:
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
	_mean = sum / float(maxi(n, 1))
	# Unstable Rate wie osu!: 10 x Standardabweichung des Zeitfehlers.
	_ur = 10.0 * sqrt(maxf(sq / float(maxi(n, 1)) - _mean * _mean, 0.0)) if n > 1 else 0.0


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


## Reiter "Details": Zeitleiste oben, darunter die Tabelle je Zone.
func _build_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visibility_changed.connect(func():
		if page.visible:
			_t = 0.0)
	page.add_child(_tag(tr("HIT TIMELINE")))
	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0, 120)
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline.draw.connect(_draw_timeline)
	page.add_child(_timeline)
	_legend = Control.new()
	_legend.custom_minimum_size = Vector2(0, 17)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.draw.connect(_draw_legend)
	page.add_child(_legend)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(line)
	_build_keys(page)
	return page


## Tabelle je Taste: Treffer/Schlaege, Genauigkeit, mittlerer Zeitfehler.
func _build_keys(parent: Control) -> void:
	_keys_box = Control.new()
	_keys_box.name = "KeyStats"
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_box.draw.connect(_draw_keys)
	parent.add_child(_keys_box)
	var cols := [[tr("ZONE"), 22.0, 0], [tr("HITS"), PAGE_W * 0.52, 1], [tr("ACCURACY"), PAGE_W * 0.76, 1],
		[tr("AVG TIMING"), PAGE_W, 1]]
	for c in cols:
		var l := _tag(c[0])
		if c[2] == 1:
			l.size = Vector2(130, 16)
			l.position = Vector2(float(c[1]) - 130.0, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.position = Vector2(float(c[1]), 0)
		_keys_box.add_child(l)
	for k in KEY_ROWS:
		var kr: Dictionary = _key_rows[k]
		var y := 20.0 + float(k) * KEY_ROW_H
		var dim := int(kr.n) == 0
		var nm := _label(tr(KEY_NAMES[k]), 13, UiTheme.DIM if dim else UiTheme.TEXT)
		nm.position = Vector2(22, y)
		_keys_box.add_child(nm)
		var vals := ["%d / %d" % [int(kr.hit), int(kr.n)],
			"—" if dim else UiTheme.fmt_pct(float(kr.val) / float(kr.n) * 100.0),
			"—" if int(kr.hit) == 0 else "%+d ms" % int(round(float(kr.dt) / float(kr.hit)))]
		for i in 3:
			var v := _label(vals[i], 13, UiTheme.DIM if dim else UiTheme.TEXT, _tab)
			v.size = Vector2(130, 20)
			v.position = Vector2(float(cols[i + 1][1]) - 130.0, y)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_keys_box.add_child(v)
	_keys_box.custom_minimum_size = Vector2(0, 20.0 + float(KEY_ROWS) * KEY_ROW_H + 2.0)


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
	if _data.is_empty() or _t > REVEAL_S + 0.1:
		return
	_t += delta
	if _timeline != null and is_instance_valid(_timeline):
		_timeline.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func _draw_timeline() -> void:
	var ci := _timeline
	var r := Rect2(Vector2.ZERO, ci.size)
	var mid := r.size.y * 0.5
	var half := r.size.y * 0.5
	var fs := 12
	ci.draw_rect(r, Color(1, 1, 1, 0.03))
	# MAX-Fenster, 50er-Fenster (Rand) und Nulllinie.
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	ci.draw_rect(Rect2(0, mid - cw, r.size.x, cw * 2.0), Color(MAX_COL, 0.05))
	ci.draw_line(Vector2(0, mid), Vector2(r.end.x, mid), Color(1, 1, 1, 0.30), 1.0)
	ci.draw_line(Vector2(0, 0.5), Vector2(r.end.x, 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_line(Vector2(0, r.end.y - 0.5), Vector2(r.end.x, r.end.y - 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_string(_font, Vector2(6, 16), tr("EARLY"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(EARLY_COL, 0.8))
	ci.draw_string(_font, Vector2(6, r.end.y - 16), tr("LATE"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(LATE_COL, 0.8))
	var ms := "±%d ms" % int(round(_w50))
	var mw := _tab.get_string_size(ms, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(_tab, Vector2(r.end.x - mw - 6.0, 16.0), ms, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.7))
	if _log.is_empty():
		return
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
		var x := 8.0 + (float(e.t) - t0) / span * (r.size.x - 16.0)
		if q == 5:
			var p := Vector2(x, r.end.y - 6.0)
			var h := 3.0
			ci.draw_line(p - Vector2(h, h), p + Vector2(h, h), Color(TIER_COLS[5], 0.9), 1.5, true)
			ci.draw_line(p - Vector2(h, -h), p + Vector2(h, -h), Color(TIER_COLS[5], 0.9), 1.5, true)
			continue
		# Oben/unten bleibt ein Band frei fuer FRUEH/SPAET und die Miss-Kreuze.
		var y := mid + clampf(float(e.dt) / _w50, -1.0, 1.0) * (half - BAND)
		_shape(ci, Vector2(x, y), int(e.key), 2.3, Color(TIER_COLS[q], 0.85))


## Legende: Formen statt Text allein.
func _draw_legend() -> void:
	var ci := _legend
	var fs := 12
	var lx := 0.0
	var ly := 13.0
	for k in [0, 4, 5]:
		var nm := tr("ZONE") if k == 0 else tr(KEY_NAMES[k])
		_shape(ci, Vector2(lx + 4.0, ly - 4.0), k, 3.0, Color(UiTheme.DIM, 0.9))
		ci.draw_string(_font, Vector2(lx + 12.0, ly), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.9))
		lx += 24.0 + _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(_font, Vector2(lx + 8.0, ly), tr("× = Miss  ·  colour = rating"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.7))


func _draw_keys() -> void:
	for k in KEY_ROWS:
		var y := 20.0 + float(k) * KEY_ROW_H + 10.0
		var dim := int(_key_rows[k].n) == 0
		_shape(_keys_box, Vector2(8.0, y), k, 4.0, Color(_key_col(k), 0.35 if dim else 0.95))
		_keys_box.draw_line(Vector2(0, y + KEY_ROW_H * 0.5 + 0.5), Vector2(PAGE_W, y + KEY_ROW_H * 0.5 + 0.5),
			Color(1, 1, 1, 0.05), 1.0)
