class_name OrbitResults
extends Control

## Endbild fuer Orbit (Satelliten, docs/modes/orbit_satellit.md). Rahmen, Kopf,
## Score, Rang, Stufen, Timing und Knoepfe kommen vom gemeinsamen ResultsScreen
## (gleicher Aufbau in allen Modi, im Multiplayer mit Rangliste). Orbit liefert
## dazu die Stufen-Namen CORE..MISS, den Zielfehler und den Reiter "Details":
## Ziel-Streuung (wo der Cursor beim Druck relativ zur Zielmitte lag), Treffer-
## Zeitleiste (Songzeit nach rechts, Zeitfehler nach unten: oben = frueh, unten =
## spaet; Form = Taste: Kreis = A, Quadrat = B, Raute = Akzent; Farbe = Stufe;
## Kreuz am Rand = Miss) und die Tasten-Statistik (A/B/Akzent, falsche Tasten).
##
## Haengt bewusst nicht an OrbitView (Farben als eigene Kopie): das Endbild laedt
## auch, wenn sich die Spielansicht aendert.

signal retry_pressed
signal back_pressed
## Replay ansehen (im Replay: selbst spielen) und Clip speichern (OrbitGame).
signal replay_pressed
signal clip_pressed

const REVEAL_S := 0.9
const TIER_COLS: Array[Color] = [
	Color(1.0, 0.96, 0.86),   # CORE: creme
	Color(0.62, 0.86, 1.0),   # SHARP
	Color(0.55, 0.78, 0.62),  # GOOD
	Color(0.80, 0.74, 0.50),  # FAIR
	Color(0.78, 0.58, 0.46),  # EDGE
	Color(0.90, 0.48, 0.48),  # MISS
]
## Wie OrbitView.A_COL / B_COL / EARLY_COL / LATE_COL / MAX_COL.
const A_COL := Color(0.38, 0.74, 1.0)
const B_COL := Color(1.0, 0.60, 0.30)
const ACC_COL := Color(0.97, 0.97, 1.0)
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MAX_COL := Color(1.0, 0.96, 0.86)
## Streuung: Rand der Scheibe = so viele Zielradien (Trefferradius 1,15 liegt innen).
const SCATTER_EXTENT := 1.45
const ROW_H := 22.0
## Nutzbreite im Panel des ResultsScreen (Panelbreite minus Rand).
const PAGE_W := ResultsScreen.PANEL_W - 44.0

var _data: Dictionary = {}
var _log: Array = []          ## normalisierte Eintraege (siehe entry)
var _w50 := 120.0
var _w_max := 16.0
var _radius := OrbitCore.DEFAULT_TARGET_RADIUS
var _t := 0.0
var _mean_dt := 0.0
var _ur := 0.0
var _mean_off := Vector2.ZERO
var _n_off := 0
var _mean_err_r := 0.0
var _key_rows: Array = []      ## je Taste {n, hit, val, dt}
var _presses: Dictionary = {}
var _font: Font
var _tab: Font
var _rs: ResultsScreen
var _scatter: Control
var _timeline: Control
var _legend: Control
var _keys_box: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Ein Log-Eintrag pro gewertetem Ziel (OrbitGame._on_note_judged):
## cursor = Cursor im Feld beim wertenden Druck (Halten: beim Kopf). Ohne Druck
## (Miss durch Ablauf) zaehlt das Ziel nicht zur Streuung.
static func entry(n: OrbitNote, result: Dictionary, cursor: Vector2) -> Dictionary:
	var q := int(result.get("quality", 5))
	var pressed := q != 5 or str(result.get("miss_kind", "")) == "DROP"
	return {
		"t": n.time_ms,
		"key": n.key,
		"q": q,
		"dt": float(result.get("dt", 0.0)),
		"off": cursor - n.pos if pressed else null,
		"hold": n.is_hold,
	}


## Altes Format [Winkel, Spur, dt, Zielfehler, Stufe, Zeit] (Bahnen) geht weiter,
## nur ohne Streuung.
static func _norm(e) -> Dictionary:
	if e is Dictionary:
		var d: Dictionary = e
		return {"t": float(d.get("t", 0.0)), "key": clampi(int(d.get("key", 0)), 0, 2),
			"q": clampi(int(d.get("q", 5)), 0, 5), "dt": float(d.get("dt", 0.0)),
			"off": d.get("off", null), "hold": bool(d.get("hold", false))}
	if e is Array and (e as Array).size() >= 6:
		return {"t": float(e[5]), "key": clampi(int(e[1]), 0, 1), "q": clampi(int(e[4]), 0, 5),
			"dt": float(e[2]), "off": null, "hold": false}
	return {}


## data: s (OrbitCore.stats + failed), log (entry je Ziel), radius (Zielradius im
## Feld, core.target_radius), presses ({key, aim, lock, early}: Drucke ohne
## Treffer aus press_missed), w50/w_max (ms), title, artist, version, is_fail,
## new_best, allow_retry, can_replay, is_replay, can_clip, key_names ([A, B]).
func show_results(data: Dictionary) -> void:
	_data = data
	_log.clear()
	for e in data.get("log", []):
		var d := _norm(e)
		if not d.is_empty():
			_log.append(d)
	_w50 = maxf(float(data.get("w50", 120.0)), 1.0)
	_w_max = float(data.get("w_max", 16.0))
	_radius = maxf(float(data.get("radius", OrbitCore.DEFAULT_TARGET_RADIUS)), 0.001)
	_presses = data.get("presses", {})
	_summarize()
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	_tab = fv
	for c in get_children():
		c.queue_free()
	_t = 0.0

	var s: Dictionary = (data.get("s", {}) as Dictionary).duplicate()
	s["mode"] = ScoreStore.MODE_ORBIT
	var fail := bool(data.get("is_fail", false))
	var d := ResultsScreen.mode_data(data, multiplayer)
	d["s"] = s
	# Zeitfehler, Genauigkeit im Verlauf und Halte-Ziele aus dem Log.
	var offs := PackedFloat32Array()
	var trace := PackedFloat32Array()
	var val := 0.0
	var h_ok := 0
	var h_drop := 0
	for i in _log.size():
		var e: Dictionary = _log[i]
		val += OrbitCore.TIER_VALUE[int(e.q)]
		trace.append(val / float(i + 1))
		if int(e.q) != 5:
			offs.append(float(e.dt))
		if bool(e.hold):
			if int(e.q) == 5:
				h_drop += 1
			else:
				h_ok += 1
	d["offsets"] = offs
	d["trace"] = trace
	d["h_ok"] = h_ok
	d["h_drop"] = h_drop
	var names: Array = []
	for nm in OrbitCore.TIER_NAMES:
		names.append(tr(nm))
	d["tier_names"] = names
	d["hero_extra"] = [[tr("ZIELFEHLER"), UiTheme.fmt_num(float(s.get("aim_err", 0.0)), 1)]]
	var mods := str(s.get("mods_text", ""))
	if mods == "" and s.get("mods", []) is Array:
		mods = " ".join(PackedStringArray(s.get("mods", [])))
	d["mod_texts"] = Array(mods.split(" ", false))
	d["can_clip"] = bool(data.get("can_clip", false))
	d["can_replay"] = bool(data.get("can_replay", false))
	d["can_share"] = not fail
	d["allow_retry"] = bool(data.get("allow_retry", true))
	var page := _build_page()
	d["mode_page"] = {"title": tr("Details"), "content": page}

	_rs = ResultsScreen.new()
	add_child(_rs)
	_rs.retry_pressed.connect(func(): retry_pressed.emit())
	_rs.back_pressed.connect(func(): back_pressed.emit())
	_rs.replay_pressed.connect(func(): replay_pressed.emit())
	_rs.clip_pressed.connect(func(): clip_pressed.emit())
	_rs.show_results(d)
	if page.get_parent() == null:
		page.queue_free()   # Multiplayer-Rangliste: kein Details-Reiter


## Mittel/UR, Streuung und Tasten-Statistik aus dem Log.
func _summarize() -> void:
	var sum := 0.0
	var sq := 0.0
	var n := 0
	_mean_off = Vector2.ZERO
	_n_off = 0
	_mean_err_r = 0.0
	var err_sum := 0.0
	_key_rows = []
	for k in 3:
		_key_rows.append({"n": 0, "hit": 0, "val": 0.0, "dt": 0.0})
	for e in _log:
		var q: int = e.q
		var kr: Dictionary = _key_rows[e.key]
		kr.n += 1
		kr.val += OrbitCore.TIER_VALUE[q]
		if e.off is Vector2:
			_mean_off += e.off
			err_sum += (e.off as Vector2).length()
			_n_off += 1
		if q == 5:
			continue
		kr.hit += 1
		kr.dt += float(e.dt)
		var dt := float(e.dt)
		sum += dt
		sq += dt * dt
		n += 1
	_mean_dt = sum / float(maxi(n, 1))
	# Unstable Rate wie osu!: 10 x Standardabweichung des Zeitfehlers.
	_ur = 10.0 * sqrt(maxf(sq / float(maxi(n, 1)) - _mean_dt * _mean_dt, 0.0)) if n > 1 else 0.0
	if _n_off > 0:
		_mean_off /= float(_n_off)
		_mean_err_r = err_sum / float(_n_off) / _radius


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


func _key_name(k: int) -> String:
	var names: Array = _data.get("key_names", [])
	if k < 2 and names.size() > k:
		return str(names[k])
	if k == 0:
		return UiTheme.key_short(Settings.orbit_key_inner)
	if k == 1:
		return UiTheme.key_short(Settings.orbit_key_outer)
	return _key_name(0) + "+" + _key_name(1)


## Reiter "Details": Streuung links, Zeitleiste rechts, darunter die Tasten.
func _build_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visibility_changed.connect(func():
		if page.visible:
			_t = 0.0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(top)

	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 4)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sc)
	sc.add_child(_tag(tr("ZIELSTREUUNG")))
	_scatter = Control.new()
	_scatter.custom_minimum_size = Vector2(188, 150)
	_scatter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scatter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scatter.draw.connect(_draw_scatter)
	sc.add_child(_scatter)
	var cap := _label(tr("keine Zieldaten") if _n_off == 0
		else tr("Ø %d %% vom Zielradius") % int(round(_mean_err_r * 100.0)), 12, UiTheme.DIM, _tab)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.add_child(cap)

	var tl := VBoxContainer.new()
	tl.add_theme_constant_override("separation", 4)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tl)
	tl.add_child(_tag(tr("TREFFER-ZEITLEISTE")))
	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0, 150)
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline.draw.connect(_draw_timeline)
	tl.add_child(_timeline)
	_legend = Control.new()
	_legend.custom_minimum_size = Vector2(0, 17)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.draw.connect(_draw_legend)
	tl.add_child(_legend)

	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(line)
	_build_keys(page)
	return page


## Tasten-Statistik: je Taste Treffer/Ziele, Genauigkeit, mittlerer Zeitfehler;
## darunter Drucke ohne Treffer (falsche Taste, daneben, Reihenfolge).
func _build_keys(parent: Control) -> void:
	_keys_box = Control.new()
	_keys_box.name = "KeyStats"
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_box.draw.connect(_draw_keys)
	parent.add_child(_keys_box)
	var cols := [[tr("TASTE"), 22.0, 0], [tr("TREFFER"), PAGE_W * 0.52, 1], [tr("GENAUIGKEIT"), PAGE_W * 0.76, 1],
		[tr("Ø TIMING"), PAGE_W, 1]]
	for c in cols:
		var l := _tag(c[0])
		if c[2] == 1:
			l.size = Vector2(130, 16)
			l.position = Vector2(float(c[1]) - 130.0, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Ueberschriftschrift ohne "Ø": normale Schrift.
			if str(c[0]).contains("Ø"):
				l.add_theme_font_override("font", _tab)
		else:
			l.position = Vector2(float(c[1]), 0)
		_keys_box.add_child(l)
	var names := [tr("A"), tr("B"), tr("AKZENT")]
	for k in 3:
		var kr: Dictionary = _key_rows[k]
		var y := 20.0 + float(k) * ROW_H
		var dim := int(kr.n) == 0
		var nm := _label("%s  %s" % [names[k], _key_name(k)], 14, UiTheme.DIM if dim else UiTheme.TEXT)
		nm.position = Vector2(22, y)
		_keys_box.add_child(nm)
		var vals := ["%d / %d" % [int(kr.hit), int(kr.n)],
			"—" if dim else UiTheme.fmt_pct(float(kr.val) / float(kr.n) * 100.0),
			"—" if int(kr.hit) == 0 else "%+d ms" % int(round(float(kr.dt) / float(kr.hit)))]
		for i in 3:
			var v := _label(vals[i], 14, UiTheme.DIM if dim else UiTheme.TEXT, _tab)
			v.size = Vector2(130, 20)
			v.position = Vector2(float(cols[i + 1][1]) - 130.0, y)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_keys_box.add_child(v)
	var parts := PackedStringArray()
	for p in [["key", tr("Falsche Taste")], ["aim", tr("Daneben")], ["lock", tr("Reihenfolge")]]:
		var n := int(_presses.get(p[0], 0))
		if p[0] == "key" or n > 0:
			parts.append("%s %d" % [p[1], n])
	var miss := _label("   ·   ".join(parts), 13, UiTheme.DIM, _tab)
	miss.name = "PressStats"
	miss.position = Vector2(22, 20.0 + 3.0 * ROW_H + 3.0)
	_keys_box.add_child(miss)
	_keys_box.custom_minimum_size = Vector2(0, 20.0 + 3.0 * ROW_H + 24.0)


## Toast und Clip-Fortschritt: der gemeinsame ResultsScreen zeigt sie.
func show_toast(text: String, sticky: bool, folder: String = "") -> void:
	if _rs != null and is_instance_valid(_rs):
		_rs.show_toast(text, sticky, folder)


func show_clip_progress(fraction: float, eta_s: float, phase: String = "render") -> void:
	if _rs != null and is_instance_valid(_rs):
		_rs.show_clip_progress(fraction, eta_s, phase)


func show_clip_result(ok: bool, path: String, error: String = "") -> void:
	if _rs != null and is_instance_valid(_rs):
		_rs.show_clip_result(ok, path, error)


static func _key_col(k: int) -> Color:
	return A_COL if k == 0 else (B_COL if k == 1 else ACC_COL)


func _process(delta: float) -> void:
	if _data.is_empty() or _t > REVEAL_S + 0.1:
		return
	_t += delta
	for c in [_scatter, _timeline]:
		if c != null and is_instance_valid(c):
			c.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


## Form je Taste: Kreis = A, (abgerundetes) Quadrat = B, Raute = Akzent.
func _shape(ci: CanvasItem, p: Vector2, k: int, h: float, col: Color) -> void:
	if k == 0:
		ci.draw_circle(p, h, col, true, -1.0, true)
	elif k == 1:
		ci.draw_rect(Rect2(p - Vector2(h, h) * 0.9, Vector2(h, h) * 1.8), col)
	else:
		var d := h * 1.3
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0),
			p + Vector2(0, d), p + Vector2(-d, 0)]), col)


func _draw_scatter() -> void:
	var ci := _scatter
	var c := ci.size * 0.5
	var rp := minf(ci.size.x, ci.size.y) * 0.5 - 1.0
	var k := rp / SCATTER_EXTENT   # px je Zielradius
	ci.draw_circle(c, rp, Color(1, 1, 1, 0.03), true, -1.0, true)
	# Volle Zielwertung (bis 50 % Radius), Zielrand, Trefferradius.
	ci.draw_circle(c, k * OrbitCore.AIM_FULL_FRAC, Color(MAX_COL, 0.06), true, -1.0, true)
	ci.draw_arc(c, k, 0.0, TAU, 64, Color(1, 1, 1, 0.30), 1.0, true)
	ci.draw_arc(c, k * OrbitCore.AIM_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.10), 1.0, true)
	ci.draw_line(c - Vector2(rp, 0), c + Vector2(rp, 0), Color(1, 1, 1, 0.06), 1.0)
	ci.draw_line(c - Vector2(0, rp), c + Vector2(0, rp), Color(1, 1, 1, 0.06), 1.0)
	if _n_off == 0:
		return
	var shown := int(float(_log.size()) * clampf(_t / REVEAL_S, 0.0, 1.0))
	for i in shown:
		var e: Dictionary = _log[i]
		if not (e.off is Vector2):
			continue
		var v: Vector2 = (e.off as Vector2) / _radius * k
		if v.length() > rp - 3.0:
			v = v.normalized() * (rp - 3.0)
		var a := 0.45 if int(e.q) == 5 else 0.8
		_shape(ci, c + v, int(e.key), 1.9, Color(_key_col(int(e.key)), a))
	# Mittlere Abweichung: kleines Kreuz (zeigt, ob man systematisch daneben liegt).
	var m := _mean_off / _radius * k
	ci.draw_line(c + m - Vector2(5, 0), c + m + Vector2(5, 0), Color(1, 1, 1, 0.9), 1.5)
	ci.draw_line(c + m - Vector2(0, 5), c + m + Vector2(0, 5), Color(1, 1, 1, 0.9), 1.5)


func _draw_timeline() -> void:
	var ci := _timeline
	var r := Rect2(Vector2.ZERO, ci.size)
	var mid := r.size.y * 0.5
	var half := r.size.y * 0.5
	var fs := 12
	ci.draw_rect(r, Color(1, 1, 1, 0.03))
	# CORE-Fenster, 50er-Fenster (Rand) und Nulllinie.
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	ci.draw_rect(Rect2(0, mid - cw, r.size.x, cw * 2.0), Color(MAX_COL, 0.05))
	ci.draw_line(Vector2(0, mid), Vector2(r.end.x, mid), Color(1, 1, 1, 0.30), 1.0)
	ci.draw_line(Vector2(0, 0.5), Vector2(r.end.x, 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_line(Vector2(0, r.end.y - 0.5), Vector2(r.end.x, r.end.y - 0.5), Color(1, 1, 1, 0.08), 1.0)
	ci.draw_string(_font, Vector2(6, 16), tr("FRÜH"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(EARLY_COL, 0.8))
	ci.draw_string(_font, Vector2(6, r.end.y - 16), tr("SPÄT"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
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
	# Ziele in Spielreihenfolge einblenden.
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
		# Unten bleibt ein Band frei fuer die Miss-Kreuze.
		var y := mid + clampf(float(e.dt) / _w50, -1.0, 1.0) * (half - 14.0)
		_shape(ci, Vector2(x, y), int(e.key), 2.3, Color(TIER_COLS[q], 0.85))


## Legende: Formen statt Text allein.
func _draw_legend() -> void:
	var ci := _legend
	var fs := 12
	var lx := 0.0
	var ly := 13.0
	for it in [[0, tr("A")], [1, tr("B")], [2, tr("Akzent")]]:
		_shape(ci, Vector2(lx + 4.0, ly - 4.0), int(it[0]), 3.0, Color(UiTheme.DIM, 0.9))
		ci.draw_string(_font, Vector2(lx + 12.0, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.9))
		lx += 24.0 + _font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(_font, Vector2(lx + 8.0, ly), tr("× = Miss  ·  Farbe = Stufe"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.7))


func _draw_keys() -> void:
	for k in 3:
		var y := 20.0 + float(k) * ROW_H + 10.0
		var dim := int(_key_rows[k].n) == 0
		_shape(_keys_box, Vector2(8.0, y), k, 4.0, Color(_key_col(k), 0.35 if dim else 0.95))
		_keys_box.draw_line(Vector2(0, y + ROW_H * 0.5 + 0.5), Vector2(PAGE_W, y + ROW_H * 0.5 + 0.5),
			Color(1, 1, 1, 0.05), 1.0)
