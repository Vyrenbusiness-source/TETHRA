class_name OrbitResults
extends Control

## Endbild fuer Orbit (Satelliten, docs/modes/orbit_satellit.md), ruhig wie das
## Mania-Endbild: links oben der Rang und die Ziel-Streuung (wo der Cursor beim
## Druck relativ zur Zielmitte lag), darunter die Treffer-Zeitleiste (Songzeit
## nach rechts, Zeitfehler nach unten: oben = frueh, unten = spaet; Form = Taste:
## Kreis = A, Quadrat = B, Raute = Akzent; Farbe = Stufe; Kreuz am Rand = Miss).
## Rechts Score, Genauigkeit, Kombo, Zielfehler, Stufen CORE..MISS mit
## Timing-Histogramm, Tasten-Statistik (A/B/Akzent, falsche Tasten) und Knoepfe.
## Alles in _draw, Texte als Labels. Kein Leuchten, keine Deko.
##
## Haengt bewusst nicht an OrbitView (Farben als eigene Kopie): das Endbild laedt
## auch, wenn sich die Spielansicht aendert.

signal retry_pressed
signal back_pressed
## Replay ansehen (im Replay: selbst spielen) und Clip speichern (OrbitGame).
signal replay_pressed
signal clip_pressed

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
## Wie OrbitView.A_COL / B_COL / PLATE_COL / EARLY_COL / LATE_COL / MAX_COL.
const A_COL := Color(0.38, 0.74, 1.0)
const B_COL := Color(1.0, 0.60, 0.30)
const ACC_COL := Color(0.97, 0.97, 1.0)
const PLATE_COL := Color(0.012, 0.016, 0.028)
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MAX_COL := Color(1.0, 0.96, 0.86)
## Streuung: Rand der Scheibe = so viele Zielradien (Trefferradius 1,15 liegt innen).
const SCATTER_EXTENT := 1.45
const ROW_H := 22.0

var _data: Dictionary = {}
var _log: Array = []          ## normalisierte Eintraege (siehe entry)
var _w50 := 120.0
var _w_max := 16.0
var _radius := OrbitCore.DEFAULT_TARGET_RADIUS
var _t := 0.0
var _counts: Array[int] = [0, 0, 0, 0, 0, 0]
var _hist := PackedInt32Array()
var _hist_max := 1
var _mean_dt := 0.0
var _ur := 0.0
var _mean_off := Vector2.ZERO
var _n_off := 0
var _mean_err_r := 0.0
var _key_rows: Array = []      ## je Taste {n, hit, val, dt}
var _presses: Dictionary = {}
var _font: Font
var _tab: Font
var _grade: Label
var _score: Label
var _right: VBoxContainer
var _tier_rows: Control
var _hist_box: Control
var _keys_box: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_btn: Button
var _toast_folder := ""
var _toast_tw: Tween


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
	var s: Dictionary = data.get("s", {})
	_counts = [int(s.get("n_max", 0)), int(s.get("n300", 0)), int(s.get("n200", 0)),
		int(s.get("n100", 0)), int(s.get("n50", 0)), int(s.get("n_miss", 0))]
	_summarize()
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.opentype_features = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	_tab = fv
	_build(s)
	_t = 0.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


## Histogramm, Mittel/UR, Streuung und Tasten-Statistik aus dem Log.
func _summarize() -> void:
	_hist.resize(BINS)
	_hist.fill(0)
	var sum := 0.0
	var sq := 0.0
	var n := 0
	_mean_off = Vector2.ZERO
	_n_off = 0
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
		var b := clampi(int(round((dt / _w50 * 0.5 + 0.5) * float(BINS - 1))), 0, BINS - 1)
		_hist[b] += 1
	_mean_dt = sum / float(maxi(n, 1))
	# Unstable Rate wie osu!: 10 x Standardabweichung des Zeitfehlers.
	_ur = 10.0 * sqrt(maxf(sq / float(maxi(n, 1)) - _mean_dt * _mean_dt, 0.0)) if n > 1 else 0.0
	if _n_off > 0:
		_mean_off /= float(_n_off)
		_mean_err_r = err_sum / float(_n_off) / _radius
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


func _key_name(k: int) -> String:
	var names: Array = _data.get("key_names", [])
	if k < 2 and names.size() > k:
		return str(names[k])
	if k == 0:
		return UiTheme.key_short(Settings.orbit_key_inner)
	if k == 1:
		return UiTheme.key_short(Settings.orbit_key_outer)
	return _key_name(0) + "+" + _key_name(1)


func _build(s: Dictionary) -> void:
	var fail := bool(_data.get("is_fail", false))
	var g := "F" if fail else str(s.get("grade", "D"))
	_grade = _label(g, 104, _grade_col(g), UiTheme.heading_font(0))
	_grade.name = "Grade"
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_grade)

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
	head.add_child(_tag(tr("ORBIT") + "  ·  " + tr("ERGEBNIS"), Color(A_COL, 0.85)))
	var mods := str(s.get("mods_text", ""))
	if mods == "" and s.get("mods", []) is Array:
		mods = " ".join(PackedStringArray(s.get("mods", [])))
	if mods != "":
		head.add_child(_tag(mods, UiTheme.DIM))
	if fail:
		head.add_child(_tag(tr("GESCHEITERT"), TIER_COLS[5]))
	elif bool(_data.get("new_best", false)):
		head.add_child(_tag(tr("NEUER BESTWERT"), B_COL))
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
	row.add_theme_constant_override("separation", 34)
	row.add_child(_stat(tr("GENAUIGKEIT"), UiTheme.fmt_pct(float(s.get("accuracy", 0.0)) * 100.0), 30))
	row.add_child(_stat(tr("KOMBO"), "%dx" % int(s.get("max_combo", 0)), 24))
	row.add_child(_stat(tr("ZIELFEHLER"), UiTheme.fmt_num(float(s.get("aim_err", 0.0)), 1), 24))
	row.add_child(_stat(tr("UR"), UiTheme.fmt_num(_ur, 0), 24))
	_right.add_child(row)

	# Stufentabelle links, Timing-Histogramm rechts: spart Hoehe, Knoepfe bleiben im Bild.
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
		var nm := _label(tr(OrbitCore.TIER_NAMES[q]), 13, TIER_COLS[q], UiTheme.heading_font(3))
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
	hl.add_child(_tag(tr("FRÜH"), EARLY_COL))
	# Normale Schrift: die Ueberschriftschrift hat kein "Ø".
	var mean := _label("%s  %+d ms" % [tr("Ø TIMING"), int(round(_mean_dt))], 12, Color(B_COL, 0.9), _tab)
	mean.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_child(mean)
	hl.add_child(_tag(tr("SPÄT"), LATE_COL))
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
	# Replay/Clip/Teilen in eigener Zeile ueber Nochmal/Zurueck (alles bleibt im Bild).
	var is_replay := bool(_data.get("is_replay", false))
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 12)
	if bool(_data.get("can_replay", false)):
		var rp := Button.new()
		rp.name = "ReplayButton"
		rp.text = tr("Selbst spielen") if is_replay else tr("▶  Replay ansehen")
		rp.custom_minimum_size = Vector2(170, 38)
		UiTheme.style_ghost_button(rp)
		rp.pressed.connect(func(): replay_pressed.emit())
		extra.add_child(rp)
	if bool(_data.get("can_clip", false)):
		var clip := Button.new()
		clip.name = "ClipButton"
		clip.text = tr("⤓  Clip speichern")
		clip.custom_minimum_size = Vector2(170, 38)
		UiTheme.style_ghost_button(clip)
		clip.pressed.connect(func(): clip_pressed.emit())
		extra.add_child(clip)
	if not is_replay and not fail:
		extra.add_child(ScoreShare.make_button(GameSession.osz_path, GameSession.difficulty_version,
			int(s.get("score", 0)), ScoreStore.MODE_ORBIT, "",
			func(b: Button): UiTheme.style_ghost_button(b)))
	if extra.get_child_count() > 0:
		_right.add_child(extra)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	if bool(_data.get("allow_retry", true)):
		var retry := Button.new()
		retry.name = "RetryButton"
		retry.text = tr("Nochmal") + "  (R)"
		retry.custom_minimum_size = Vector2(170, 44)
		UiTheme.style_button(retry, true)
		retry.pressed.connect(func(): retry_pressed.emit())
		btns.add_child(retry)
	var back := Button.new()
	back.name = "BackButton"
	back.text = tr("Zurück") + "  (Esc)"
	back.custom_minimum_size = Vector2(170, 44)
	UiTheme.style_ghost_button(back)
	back.pressed.connect(func(): back_pressed.emit())
	btns.add_child(back)
	_right.add_child(btns)


## Tasten-Statistik: je Taste Treffer/Ziele, Genauigkeit, mittlerer Zeitfehler;
## darunter Drucke ohne Treffer (falsche Taste, daneben, Reihenfolge).
func _build_keys() -> void:
	_keys_box = Control.new()
	_keys_box.name = "KeyStats"
	_keys_box.custom_minimum_size = Vector2(0, ROW_H * 4.0)
	_keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys_box.draw.connect(_draw_keys)
	_right.add_child(_keys_box)
	var cols := [[tr("TASTE"), 22.0, 0], [tr("TREFFER"), 230.0, 1], [tr("GENAUIGKEIT"), 340.0, 1],
		[tr("Ø TIMING"), 450.0, 1]]
	for c in cols:
		var l := _tag(c[0], UiTheme.DIM)
		if c[2] == 1:
			l.size = Vector2(110, 16)
			l.position = Vector2(float(c[1]) - 110.0, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Ueberschriftschrift ohne "Ø": normale Schrift wie beim Histogramm.
			if str(c[0]).contains("Ø"):
				l.add_theme_font_override("font", _tab)
		else:
			l.position = Vector2(float(c[1]), 0)
		_keys_box.add_child(l)
	var names := [tr("A"), tr("B"), tr("AKZENT")]
	for k in 3:
		var kr: Dictionary = _key_rows[k]
		var y := 18.0 + float(k) * ROW_H
		var dim := int(kr.n) == 0
		var nm := _label("%s  %s" % [names[k], _key_name(k)], 14, UiTheme.DIM if dim else UiTheme.TEXT)
		nm.position = Vector2(22, y)
		_keys_box.add_child(nm)
		var vals := ["%d / %d" % [int(kr.hit), int(kr.n)],
			"—" if dim else UiTheme.fmt_pct(float(kr.val) / float(kr.n) * 100.0),
			"—" if int(kr.hit) == 0 else "%+d ms" % int(round(float(kr.dt) / float(kr.hit)))]
		for i in 3:
			var v := _label(vals[i], 14, UiTheme.DIM if dim else UiTheme.TEXT, _tab)
			v.size = Vector2(110, 20)
			v.position = Vector2(float(cols[i + 1][1]) - 110.0, y)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_keys_box.add_child(v)
	var parts := PackedStringArray()
	for p in [["key", tr("Falsche Taste")], ["aim", tr("Daneben")], ["lock", tr("Reihenfolge")]]:
		var n := int(_presses.get(p[0], 0))
		if p[0] == "key" or n > 0:
			parts.append("%s %d" % [p[1], n])
	var miss := _label("   ·   ".join(parts), 13, UiTheme.DIM, _tab)
	miss.name = "PressStats"
	miss.position = Vector2(22, 18.0 + 3.0 * ROW_H + 2.0)
	_keys_box.add_child(miss)
	_keys_box.custom_minimum_size.y = 18.0 + 3.0 * ROW_H + 22.0


## Toast oben mittig (Clip-Export), flach im UiTheme-Stil. sticky = bleibt
## stehen (Fortschritt), sonst nach 4 s (mit Ordner-Knopf 12 s) weg.
func show_toast(text: String, sticky: bool, folder: String = "") -> void:
	if _toast == null or not is_instance_valid(_toast):
		_toast = PanelContainer.new()
		_toast.anchor_left = 0.5
		_toast.anchor_right = 0.5
		_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast.offset_top = 14
		_toast.offset_bottom = 14
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiTheme.glass_box(8, 0.92)
		sb.set_content_margin_all(10)
		_toast.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_child(hb)
		_toast_label = _label("", 15, UiTheme.TEXT)
		_toast_label.custom_minimum_size.x = 420
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		hb.add_child(_toast_label)
		_toast_btn = Button.new()
		_toast_btn.text = tr("Ordner öffnen")
		UiTheme.style_button(_toast_btn, false)
		_toast_btn.pressed.connect(func() -> void:
			if _toast_folder != "":
				OS.shell_open(ProjectSettings.globalize_path(_toast_folder)))
		hb.add_child(_toast_btn)
		add_child(_toast)
	_toast_label.text = text
	_toast_folder = folder
	_toast_btn.visible = folder != ""
	_toast.modulate.a = 1.0
	_toast.reset_size()
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	if not sticky:
		_toast_tw = create_tween()
		_toast_tw.tween_interval(12.0 if folder != "" else 4.0)
		_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## Wie ResultsScreen: Fortschritt mit Restzeit (ClipExporter.progress_info).
func show_clip_progress(fraction: float, eta_s: float, phase: String = "render") -> void:
	var pct := int(clampf(fraction, 0.0, 1.0) * 100.0)
	var text := tr("Clip wird umgewandelt … %d %%") % pct if phase == "encode" \
		else tr("Clip wird aufgenommen … %d %%") % pct
	if eta_s >= 0.0:
		text += "  " + tr("noch ca. %d s") % int(ceilf(eta_s))
	show_toast(text, true)


func show_clip_result(ok: bool, path: String, error: String = "") -> void:
	if ok:
		show_toast(tr("Clip gespeichert: %s") % path, false, path.get_base_dir())
	else:
		show_toast(tr("Clip-Export fehlgeschlagen: %s") % (error if error != "" else tr("unbekannt")), false)


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


static func _key_col(k: int) -> Color:
	return A_COL if k == 0 else (B_COL if k == 1 else ACC_COL)


func _process(delta: float) -> void:
	if _data.is_empty():
		return
	_t += delta
	var k := clampf(_t / REVEAL_S, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var sc := int(float(_data.get("s", {}).get("score", 0)) * e)
	_score.text = UiTheme.fmt_score(sc)
	_grade.position = _grade_center() - Vector2(110, 75)
	_grade.size = Vector2(220, 150)
	if k < 1.0 or _t < REVEAL_S + 0.1:
		queue_redraw()
		_hist_box.queue_redraw()
		_tier_rows.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func _grade_center() -> Vector2:
	return Vector2(size.x * 0.135, size.y * 0.235)


## Mitte und Radius (px) der Streuungs-Scheibe.
func _scatter_disc() -> Array:
	var r := minf(size.y * 0.165, size.x * 0.11)
	return [Vector2(size.x * 0.36, size.y * 0.06 + 18.0 + r), r]


## Plotflaeche der Treffer-Zeitleiste.
func _plot_rect() -> Rect2:
	return Rect2(size.x * 0.04, size.y * 0.52, size.x * 0.43, size.y * 0.34)


func _draw() -> void:
	if _data.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(PLATE_COL, 0.97))
	_draw_scatter()
	_draw_timeline()


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
	var disc := _scatter_disc()
	var c: Vector2 = disc[0]
	var rp: float = disc[1]
	var k := rp / SCATTER_EXTENT   # px je Zielradius
	var fs := 12
	var hf := UiTheme.heading_font(4)
	draw_string(hf, Vector2(c.x - rp, c.y - rp - 8.0), tr("ZIELSTREUUNG"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.DIM)
	draw_circle(c, rp, Color(1, 1, 1, 0.025), true, -1.0, true)
	# Volle Zielwertung (bis 50 % Radius), Zielrand, Trefferradius.
	draw_circle(c, k * OrbitCore.AIM_FULL_FRAC, Color(MAX_COL, 0.05), true, -1.0, true)
	draw_arc(c, k, 0.0, TAU, 64, Color(1, 1, 1, 0.30), 1.0, true)
	draw_arc(c, k * OrbitCore.AIM_RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.10), 1.0, true)
	draw_line(c - Vector2(rp, 0), c + Vector2(rp, 0), Color(1, 1, 1, 0.06), 1.0)
	draw_line(c - Vector2(0, rp), c + Vector2(0, rp), Color(1, 1, 1, 0.06), 1.0)
	if _n_off == 0:
		var none := tr("keine Zieldaten")
		var w := _font.get_string_size(none, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, c + Vector2(-w * 0.5, 4.0), none, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.8))
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
		_shape(self, c + v, int(e.key), 1.9, Color(_key_col(int(e.key)), a))
	# Mittlere Abweichung: kleines Kreuz (zeigt, ob man systematisch daneben liegt).
	var m := _mean_off / _radius * k
	draw_line(c + m - Vector2(5, 0), c + m + Vector2(5, 0), Color(1, 1, 1, 0.9), 1.5)
	draw_line(c + m - Vector2(0, 5), c + m + Vector2(0, 5), Color(1, 1, 1, 0.9), 1.5)
	var cap := tr("Ø %d %% vom Zielradius") % int(round(_mean_err_r * 100.0))
	var cw := _tab.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_tab, Vector2(c.x - cw * 0.5, c.y + rp + 18.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.DIM, 0.9))


func _draw_timeline() -> void:
	var r := _plot_rect()
	var mid := r.position.y + r.size.y * 0.5
	var half := r.size.y * 0.5
	var fs := 12
	draw_string(UiTheme.heading_font(4), Vector2(r.position.x, r.position.y - 10.0), tr("TREFFER-ZEITLEISTE"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.DIM)
	draw_rect(r, Color(1, 1, 1, 0.025))
	# CORE-Fenster, 50er-Fenster (Rand) und Nulllinie.
	var cw := clampf(_w_max / _w50, 0.02, 1.0) * half
	draw_rect(Rect2(r.position.x, mid - cw, r.size.x, cw * 2.0), Color(MAX_COL, 0.05))
	draw_line(Vector2(r.position.x, mid), Vector2(r.end.x, mid), Color(1, 1, 1, 0.30), 1.0)
	draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color(1, 1, 1, 0.08), 1.0)
	draw_string(_font, r.position + Vector2(6, 16), tr("FRÜH"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(EARLY_COL, 0.8))
	draw_string(_font, Vector2(r.position.x + 6, r.end.y - 8), tr("SPÄT"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
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
		# Ziele in Spielreihenfolge einblenden.
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
			var y := mid + clampf(float(e.dt) / _w50, -1.0, 1.0) * (half - 6.0)
			_shape(self, Vector2(x, y), int(e.key), 2.3, Color(TIER_COLS[q], 0.85))
	# Legende: Formen statt Text allein.
	var lx := r.position.x
	var ly := r.end.y + 20.0
	var items := [[0, tr("A")], [1, tr("B")], [2, tr("Akzent")]]
	for it in items:
		_shape(self, Vector2(lx + 4.0, ly - 4.0), int(it[0]), 3.0, Color(UiTheme.DIM, 0.9))
		draw_string(_font, Vector2(lx + 12.0, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.9))
		lx += 24.0 + _font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var xh := tr("× = Miss  ·  Farbe = Stufe")
	draw_string(_font, Vector2(lx + 8.0, ly), xh, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.DIM, 0.7))


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
	# CORE-Zeitfenster als helle Zone in der Mitte.
	var cw := _w_max / _w50 * sz.x * 0.5
	_hist_box.draw_rect(Rect2(sz.x * 0.5 - cw, 0, cw * 2.0, sz.y), Color(1, 0.96, 0.86, 0.05))
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
	var mx := sz.x * 0.5 + clampf(_mean_dt / _w50, -1.0, 1.0) * sz.x * 0.5
	_hist_box.draw_line(Vector2(mx, 0), Vector2(mx, sz.y), Color(B_COL, 0.8), 2.0)
	_hist_box.draw_line(Vector2(0, sz.y), Vector2(sz.x, sz.y), Color(1, 1, 1, 0.15), 1.0)


func _draw_keys() -> void:
	for k in 3:
		var y := 18.0 + float(k) * ROW_H + 10.0
		var dim := int(_key_rows[k].n) == 0
		_shape(_keys_box, Vector2(8.0, y), k, 4.0, Color(_key_col(k), 0.35 if dim else 0.95))
		_keys_box.draw_line(Vector2(0, y + ROW_H * 0.5 + 0.5), Vector2(450, y + ROW_H * 0.5 + 0.5),
			Color(1, 1, 1, 0.04), 1.0)
