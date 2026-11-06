class_name HitErrorBar
extends Control

## Timing-Leiste: Fenster-Zonen, Treffer-Ticks (blenden aus), Mittelwert-Dreieck, optional UR.
## Ringpuffer mit 64 Ticks, keine Allokation pro Treffer.

const CAP := 64
const FADE_S := 2.5
const BAR_H := 8.0

var show_ur := false

var _off := PackedFloat32Array()
var _t := PackedFloat64Array()
var _count := 0
var _head := 0
var _sum := 0.0
var _w := {"max": 16.0, "w300": 40.0, "w200": 73.0, "w100": 103.0, "w50": 127.0}
var _span := 140.0
var _zone_cols := [
	Color(0.55, 0.85, 1.0, 0.30), Color(0.40, 0.80, 1.0, 0.22), Color(0.45, 0.90, 0.50, 0.20),
	Color(1.0, 0.85, 0.35, 0.20), Color(1.0, 0.45, 0.35, 0.20)]
var _font: Font


func _ready() -> void:
	_off.resize(CAP)
	_t.resize(CAP)
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(windows: Dictionary, width_px: float) -> void:
	for k in _w.keys():
		_w[k] = float(windows.get(k, _w[k]))
	_span = maxf(_w["w50"] * 1.1, 1.0)
	custom_minimum_size = Vector2(width_px, 36.0)
	size = custom_minimum_size
	queue_redraw()


func reset() -> void:
	_count = 0
	_head = 0
	_sum = 0.0
	queue_redraw()


func add_hit(offset_ms: float) -> void:
	if _off.size() != CAP:
		_off.resize(CAP)
		_t.resize(CAP)
	if _count == CAP:
		_sum -= _off[_head]
	else:
		_count += 1
	_off[_head] = offset_ms
	_t[_head] = Time.get_ticks_msec() / 1000.0
	_sum += offset_ms
	_head = (_head + 1) % CAP
	queue_redraw()


func get_count() -> int:
	return _count


func get_mean() -> float:
	return _sum / _count if _count > 0 else 0.0


## Unstable Rate = 10 * Standardabweichung der Offsets im Puffer.
func get_ur() -> float:
	if _count < 2:
		return 0.0
	var m := get_mean()
	var acc := 0.0
	for i in _count:
		var d := _off[i] - m
		acc += d * d
	return sqrt(acc / _count) * 10.0


func _x(ms: float) -> float:
	return size.x * 0.5 + clampf(ms / _span, -1.0, 1.0) * size.x * 0.5


func _process(_d: float) -> void:
	if _count > 0:
		queue_redraw()


func _draw() -> void:
	var cy := size.y * 0.5
	var y0 := cy - BAR_H * 0.5
	var keys := ["w50", "w100", "w200", "w300", "max"]
	for i in 5:
		var hw: float = _w[keys[i]]
		var x0 := _x(-hw)
		draw_rect(Rect2(x0, y0, _x(hw) - x0, BAR_H), _zone_cols[4 - i])
	draw_rect(Rect2(size.x * 0.5 - 1.0, cy - 9.0, 2.0, 18.0), Color(1, 1, 1, 0.85))
	var now := Time.get_ticks_msec() / 1000.0
	for i in _count:
		var a := 1.0 - (now - _t[i]) / FADE_S
		if a <= 0.0:
			continue
		var x := _x(_off[i])
		var ao := absf(_off[i])
		var col := Color(0.6, 0.9, 1.0, a * 0.9)
		if ao > _w["w200"]:
			col = Color(1.0, 0.5, 0.4, a * 0.9)
		elif ao > _w["w300"]:
			col = Color(1.0, 0.9, 0.5, a * 0.9)
		draw_rect(Rect2(x - 1.0, cy - 7.0, 2.0, 14.0), col)
	if _count > 0:
		var mx := _x(get_mean())
		draw_colored_polygon(PackedVector2Array([
			Vector2(mx - 4.0, cy - 15.0), Vector2(mx + 4.0, cy - 15.0), Vector2(mx, cy - 9.0)]),
			Color(1, 1, 1, 0.9))
	if show_ur and _font != null:
		draw_string(_font, Vector2(0, size.y - 1.0), "UR %d" % int(round(get_ur())),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 1, 1, 0.6))
