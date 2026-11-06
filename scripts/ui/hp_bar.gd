class_name HpBar
extends Control

## Schmale HP-Leiste (Glas-Stil). Mittig oben platzieren, Breite frei waehlbar.
## API: setup(theme), set_hp(0..1), flash_hit(), flash_miss().
## Keine Allokation pro Frame: Polygone/Farben/Styleboxen werden vorab angelegt.

const BAR_H := 10.0
const LOW := 0.30
const RED := Color(1.0, 0.28, 0.32)

@export var label_text: String = ""   # z. B. "HP"; leer = keine Beschriftung

var _theme: Color = Color(0.20, 0.85, 1.0)
var _target: float = 1.0
var _shown: float = 1.0
var _sweep: float = -1.0   # 0..1 laufender Glanz, <0 = aus
var _miss: float = 0.0     # 0..1 abklingender Rot-Blitz
var _t: float = 0.0
var _track := StyleBoxFlat.new()
var _poly := PackedVector2Array([Vector2(), Vector2(), Vector2(), Vector2()])
var _cols := PackedColorArray([Color(), Color(), Color(), Color()])
var _heart := PackedVector2Array([Vector2(), Vector2(), Vector2()])
var _font: Font
var _font_size := 12


func _ready() -> void:
	custom_minimum_size = Vector2(320, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.bg_color = Color(1, 1, 1, 0.07)
	_track.border_color = Color(1, 1, 1, 0.20)
	_track.set_border_width_all(1)
	_track.set_corner_radius_all(int(BAR_H / 2.0))
	_font = ThemeDB.fallback_font
	set_process(true)


func setup(theme: Color) -> void:
	_theme = theme
	queue_redraw()


func set_hp(v: float) -> void:
	_target = clampf(v, 0.0, 1.0)


func flash_hit() -> void:
	_sweep = 0.0


func flash_miss() -> void:
	_miss = 1.0


func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, _target, 1.0 - exp(-8.0 * delta))
	if absf(_shown - _target) < 0.0005:
		_shown = _target
	if _sweep >= 0.0:
		_sweep += delta / 0.45
		if _sweep > 1.0:
			_sweep = -1.0
	_miss = maxf(0.0, _miss - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var icon_w := 22.0
	var lab_w := 0.0
	if label_text != "":
		lab_w = _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x + 8.0
	var x0 := icon_w + lab_w
	var w := size.x - x0
	var cy := size.y * 0.5
	var y0 := cy - BAR_H * 0.5
	if w <= 4.0:
		return
	var low := _shown < LOW
	var pulse := 0.0
	if low:
		pulse = 0.5 + 0.5 * sin(_t * 5.0)
	var tint := _theme
	if low:
		tint = _theme.lerp(RED, 0.75 + 0.25 * pulse)
	tint = tint.lerp(RED, _miss * 0.6)

	# Icon: Herz aus 2 Kreisen + Dreieck
	var ic := tint.lerp(Color.WHITE, 0.25)
	var hs := 1.0 + (0.06 * pulse if low else 0.0)
	var hc := Vector2(icon_w * 0.5 - 1.0, cy)
	var r := 3.6 * hs
	draw_circle(hc + Vector2(-r * 0.9, -r * 0.5), r, ic)
	draw_circle(hc + Vector2(r * 0.9, -r * 0.5), r, ic)
	_heart[0] = hc + Vector2(-r * 1.75, -r * 0.1)
	_heart[1] = hc + Vector2(r * 1.75, -r * 0.1)
	_heart[2] = hc + Vector2(0, r * 2.3)
	draw_colored_polygon(_heart, ic)

	if label_text != "":
		draw_string(_font, Vector2(icon_w + 2.0, cy + _font_size * 0.35), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(1, 1, 1, 0.7))

	# Glasbahn
	draw_style_box(_track, Rect2(x0, y0, w, BAR_H))

	# Fuellung mit Verlauf theme -> weiss
	var fw := (w - 2.0) * _shown
	if fw > 1.0:
		var fx := x0 + 1.0
		var fy := y0 + 1.0
		var fh := BAR_H - 2.0
		var c_l := tint
		var c_r := tint.lerp(Color.WHITE, 0.55 if low else 0.75)
		c_l.a = 0.92
		c_r.a = 0.95
		_poly[0] = Vector2(fx, fy)
		_poly[1] = Vector2(fx + fw, fy)
		_poly[2] = Vector2(fx + fw, fy + fh)
		_poly[3] = Vector2(fx, fy + fh)
		_cols[0] = c_l
		_cols[1] = c_r
		_cols[2] = c_r
		_cols[3] = c_l
		draw_polygon(_poly, _cols)
		# oberer Glasglanz
		draw_rect(Rect2(fx, fy, fw, fh * 0.4), Color(1, 1, 1, 0.14))
		# Glanz-Sweep
		if _sweep >= 0.0:
			var sw := 26.0
			var sx := fx + (fw + sw) * _sweep - sw
			var a := sin(_sweep * PI) * 0.55
			var l := clampf(sx, fx, fx + fw)
			var rr := clampf(sx + sw, fx, fx + fw)
			if rr > l:
				draw_rect(Rect2(l, fy, rr - l, fh), Color(1, 1, 1, a))
