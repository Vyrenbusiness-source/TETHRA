class_name JudgeDisplay
extends Control
## Judgement-Feedback fuer die HUD-CanvasLayer: knackiger Judge-Pop knapp ueber
## der Abfanglinie (Mitte), FRUEH/SPAET klein darunter, grosse Kombo-Zahl.
##
## Alle Labels werden in setup() einmal angelegt; pro Treffer wird nichts
## allokiert (kein Tween, kein Node) — die Animation laeuft zeitbasiert in
## _process, damit der erste Frame nach dem Treffer schon den Pop zeigt.
##
## Nutzung:
##   var jd := JudgeDisplay.new(); hud.add_child(jd); jd.setup(theme_col)
##   jd.place(line_y_px)               # Abfanglinie in Bildschirm-Pixeln
##   jd.window_300_ms = core.w300      # FAST/SLOW erst ausserhalb 300-Fenster
##   jd.show_judge(q, offset_ms)       # offset < 0 = zu frueh
##   jd.set_combo(core.combo); jd.beat(beat_env)

## Qualitaet wie ManiaCore.Quality: 0=MAX 1=300 2=200 3=100 4=50 5=MISS.
const TEXTS: Array[String] = ["MAX", "300", "200", "100", "50", "MISS"]
const COLORS: Array[Color] = [
	Color(1.00, 0.95, 0.80),  # MAX gold-weiss
	Color(0.80, 0.96, 1.00),  # 300 cyan-weiss
	Color(0.52, 0.98, 0.62),  # 200 gruen
	Color(0.42, 0.62, 1.00),  # 100 blau
	Color(0.62, 0.64, 0.70),  # 50 grau
	Color(1.00, 0.34, 0.38),  # MISS rot
]
const EARLY_TEXT := "FRÜH"
const LATE_TEXT := "SPÄT"
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.62, 0.48)

const POP_FROM := 1.25
const POP_S := 0.080
const HOLD_S := 0.350
const FADE_S := 0.140
const COMBO_BUMP := 1.12
const COMBO_BUMP_S := 0.090
const COMBO_GLOW_FROM := 100
const COMBO_OUT_S := 0.160
const BREATH := 0.03

const JUDGE_SIZE := 44
const SUB_SIZE := 15
const COMBO_SIZE := 64
const BOX := Vector2(420, 80)

## Treffer innerhalb +-window_300_ms bekommen kein FRUEH/SPAET.
var window_300_ms := 49.5
## Abstand Judge-Mitte ueber der Abfanglinie bzw. Kombo ueber dem Judge (px).
var judge_gap := 64.0
var combo_gap := 92.0

var _theme := UiTheme.ACCENT
var _judges: Array[Label] = []
var _early: Label
var _late: Label
var _combo: Label
var _active := -1
var _sub: Label
var _jt := 99.0
var _combo_val := 0
var _ct := 99.0
var _combo_out := false
var _beat_env := 0.0
var _line_y := -1.0


func setup(theme: Color) -> void:
	_theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var judge_font := UiTheme.heading_font(3)
	var num_font := UiTheme.heading_font(1)
	# Tabellarische Ziffern: Kombo springt beim Hochzaehlen nicht seitlich.
	var ts := TextServerManager.get_primary_interface()
	num_font.opentype_features = {ts.name_to_tag("tnum"): 1}
	judge_font.opentype_features = {ts.name_to_tag("tnum"): 1}
	for q in TEXTS.size():
		var l := _make_label(TEXTS[q], judge_font, JUDGE_SIZE, COLORS[q])
		l.add_theme_constant_override("outline_size", 7)
		l.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.85))
		if q == 0:
			# MAX: weicher goldener Saum statt grellem Leuchten.
			l.add_theme_color_override("font_shadow_color", Color(1.0, 0.82, 0.45, 0.22))
			l.add_theme_constant_override("shadow_outline_size", 14)
			l.add_theme_constant_override("shadow_offset_x", 0)
			l.add_theme_constant_override("shadow_offset_y", 0)
		_judges.append(l)
	_early = _make_label(EARLY_TEXT, judge_font, SUB_SIZE, EARLY_COL)
	_late = _make_label(LATE_TEXT, judge_font, SUB_SIZE, LATE_COL)
	for l in [_early, _late]:
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.85))
	_combo = _make_label("", num_font, COMBO_SIZE, UiTheme.TEXT)
	_combo.add_theme_constant_override("outline_size", 8)
	_combo.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.7))
	_combo.add_theme_constant_override("shadow_offset_x", 0)
	_combo.add_theme_constant_override("shadow_offset_y", 0)
	_combo.add_theme_constant_override("shadow_outline_size", 0)
	_layout()
	set_process(true)


func _make_label(text: String, font: Font, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = BOX
	l.pivot_offset = BOX * 0.5
	l.visible = false
	add_child(l)
	return l


## Abfanglinie in Pixeln (Viewport-Koordinaten). Ohne Aufruf: 84 % Hoehe.
func place(line_y: float) -> void:
	_line_y = line_y
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	if _combo == null:
		return
	var vs := get_viewport_rect().size
	var ly := _line_y if _line_y >= 0.0 else vs.y * 0.84
	var cx := vs.x * 0.5
	var jy := ly - judge_gap
	for l in _judges:
		l.position = Vector2(cx, jy) - BOX * 0.5
	var sy := jy + JUDGE_SIZE * 0.5 + 8.0
	_early.position = Vector2(cx, sy) - BOX * 0.5
	_late.position = _early.position
	_combo.position = Vector2(cx, jy - combo_gap) - BOX * 0.5


## Neuer Judge ersetzt den alten sofort (kein Ueberblenden).
func show_judge(quality: int, offset_ms: float) -> void:
	quality = clampi(quality, 0, TEXTS.size() - 1)
	if _active >= 0 and _active != quality:
		_judges[_active].visible = false
	_active = quality
	var l := _judges[quality]
	l.visible = true
	l.modulate.a = 1.0
	l.scale = Vector2.ONE * POP_FROM
	_early.visible = false
	_late.visible = false
	_sub = null
	if quality != 5 and absf(offset_ms) > window_300_ms:
		_sub = _early if offset_ms < 0.0 else _late
		_sub.visible = true
		_sub.modulate.a = 1.0
	_jt = 0.0


## Kombo setzen. Steigt sie: Bump. Faellt sie auf 0: kurzes Ausblenden.
func set_combo(combo: int) -> void:
	if combo == _combo_val:
		return
	if combo <= 0:
		_combo_val = 0
		if _combo.visible and not _combo_out:
			_combo_out = true
			_ct = 0.0
		return
	var grew := combo > _combo_val
	_combo_val = combo
	_combo_out = false
	_combo.text = str(combo)
	_combo.visible = true
	_combo.modulate.a = 0.94
	var glow := combo >= COMBO_GLOW_FROM
	_combo.add_theme_constant_override("shadow_outline_size", 12 if glow else 0)
	if glow:
		_combo.add_theme_color_override("font_shadow_color",
				Color(_theme.r, _theme.g, _theme.b, 0.30))
	if grew:
		_ct = 0.0


## Beat-Huelle 0..1 (1 = Schlag). Kombo atmet maximal 3 %.
func beat(beat_env: float) -> void:
	_beat_env = clampf(beat_env, 0.0, 1.0)


func _process(delta: float) -> void:
	if _combo == null:
		return
	if _active >= 0:
		_jt += delta
		var l := _judges[_active]
		var p := clampf(_jt / POP_S, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - p, 3.0)
		l.scale = Vector2.ONE * lerpf(POP_FROM, 1.0, e)
		var a := 1.0
		if _jt > HOLD_S:
			a = 1.0 - clampf((_jt - HOLD_S) / FADE_S, 0.0, 1.0)
		l.modulate.a = a
		if _sub != null:
			_sub.modulate.a = a
		if a <= 0.0:
			l.visible = false
			if _sub != null:
				_sub.visible = false
				_sub = null
			_active = -1
	if _combo.visible:
		_ct += delta
		var breath := 1.0 + BREATH * _beat_env
		if _combo_out:
			var k := clampf(_ct / COMBO_OUT_S, 0.0, 1.0)
			_combo.modulate.a = 0.94 * (1.0 - k)
			_combo.scale = Vector2.ONE * breath
			if k >= 1.0:
				_combo.visible = false
				_combo_out = false
		else:
			var bp := clampf(_ct / COMBO_BUMP_S, 0.0, 1.0)
			var be := 1.0 - pow(1.0 - bp, 2.0)
			_combo.scale = Vector2.ONE * lerpf(COMBO_BUMP, 1.0, be) * breath
