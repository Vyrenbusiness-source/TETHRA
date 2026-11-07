class_name LiveTeamBar
extends Control

## Ingame-Leiste oben: Rot gegen Blau als geteilter Balken mit Live-Summen.
## setup({names:[a,b], totals:[a,b]?}); set_totals([a,b]) gleitet ruhig.
## Zeichnet selbst; Styleboxen sind vorab angelegt.

const COLS := [Color(1.0, 0.38, 0.45), Color(0.38, 0.65, 1.0)]
const TEXT := Color(0.95, 0.96, 1.0)
const DIM := Color(0.62, 0.64, 0.72)
const BAR_H := 10.0
const MIN_SHARE := 0.08

var _names: Array = ["Rot", "Blau"]
var _totals: Array = [0, 0]
var _shown_share := 0.5
var _target_share := 0.5
var _shown_vals: Array = [0.0, 0.0]
var _txt: Array = ["0", "0"]
var _lead := ""
var _font: Font
var _tween: Tween
var _sb := [StyleBoxFlat.new(), StyleBoxFlat.new()]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 46)
	_font = get_theme_default_font()


func setup(d: Dictionary) -> void:
	var nm = d.get("names", null)
	if typeof(nm) == TYPE_ARRAY and nm.size() == 2:
		_names = [str(nm[0]), str(nm[1])]
	var tt = d.get("totals", null)
	if typeof(tt) == TYPE_ARRAY and tt.size() == 2:
		_totals = [maxi(0, int(tt[0])), maxi(0, int(tt[1]))]
	else:
		_totals = [0, 0]
	_shown_vals = [float(_totals[0]), float(_totals[1])]
	_target_share = _share(_totals)
	_shown_share = _target_share
	_refresh_text()
	queue_redraw()


func set_totals(totals: Array) -> void:
	if totals.size() != 2:
		return
	var n := [maxi(0, int(totals[0])), maxi(0, int(totals[1]))]
	if n == _totals:
		return
	_totals = n
	_target_share = _share(n)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_step_share, _shown_share, _target_share, 0.5)
	_tween.tween_method(_step_val.bind(0), _shown_vals[0], float(n[0]), 0.5)
	_tween.tween_method(_step_val.bind(1), _shown_vals[1], float(n[1]), 0.5)


func _share(t: Array) -> float:
	var sum: int = t[0] + t[1]
	if sum <= 0:
		return 0.5
	return clampf(float(t[0]) / float(sum), MIN_SHARE, 1.0 - MIN_SHARE)


func _step_share(v: float) -> void:
	_shown_share = v
	queue_redraw()


func _step_val(v: float, i: int) -> void:
	_shown_vals[i] = v
	_refresh_text()
	queue_redraw()


func _refresh_text() -> void:
	_txt = [UiTheme.fmt_score(int(_shown_vals[0])), UiTheme.fmt_score(int(_shown_vals[1]))]
	var diff := int(_shown_vals[0]) - int(_shown_vals[1])
	_lead = "" if diff == 0 else "+" + UiTheme.fmt_score(absi(diff))


func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	var w := size.x
	var bar_y := size.y - BAR_H - 2.0
	var split := w * _shown_share
	var gap := 2.0
	var r := BAR_H * 0.5
	# Balken: links Rot, rechts Blau, kleine Luecke in der Mitte
	_pill(Rect2(0, bar_y, maxf(split - gap, 0.0), BAR_H), 0, r)
	_pill(Rect2(split + gap, bar_y, maxf(w - split - gap, 0.0), BAR_H), 1, r)
	# Texte: Name + Summe aussen, Vorsprung in der Mitte
	var fs := 15
	var top := bar_y - 7.0
	draw_string(_font, Vector2(0, top), tr(_names[0]), HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, fs, DIM)
	var s0 := _font.get_string_size(tr(_names[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(s0 + 10.0, top), _txt[0], HORIZONTAL_ALIGNMENT_LEFT, w * 0.4, fs + 3, TEXT)
	draw_string(_font, Vector2(0, top), tr(_names[1]), HORIZONTAL_ALIGNMENT_RIGHT, w, fs, DIM)
	var s1 := _font.get_string_size(tr(_names[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(-(s1 + 10.0), top), _txt[1], HORIZONTAL_ALIGNMENT_RIGHT, w, fs + 3, TEXT)
	if _lead != "":
		var col: Color = COLS[0] if _shown_vals[0] > _shown_vals[1] else COLS[1]
		draw_string(_font, Vector2(0, top), _lead, HORIZONTAL_ALIGNMENT_CENTER, w, fs - 1, col)


func _pill(rect: Rect2, idx: int, radius: float) -> void:
	if rect.size.x <= 0.0:
		return
	var sb: StyleBoxFlat = _sb[idx]
	sb.bg_color = COLS[idx]
	var outer := int(radius)
	sb.corner_radius_top_left = outer if idx == 0 else 2
	sb.corner_radius_bottom_left = outer if idx == 0 else 2
	sb.corner_radius_top_right = 2 if idx == 0 else outer
	sb.corner_radius_bottom_right = 2 if idx == 0 else outer
	draw_style_box(sb, rect)
