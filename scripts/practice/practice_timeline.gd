class_name PracticeTimeline
extends Control

## Zeitleiste des Uebungsmodus: Notendichte als Saeulen, Kiai leicht hinterlegt,
## Abschnitt A..B in Bernstein, Fehlerstellen als Ziegel-Marken, Cursor.
## Maus: ziehen = neuer Abschnitt, A/B-Griff ziehen = Kante verschieben,
## Klick auf eine Fehlerstelle = Abschnitt darum. Tasten macht PracticePanel.

signal range_changed(a_ms: float, b_ms: float)
signal cursor_moved(t_ms: float)

const BINS := 160
const GRAB_PX := 9.0

var song_ms := 1.0
var a_ms := 0.0
var b_ms := 0.0
var cursor_ms := 0.0
var marks: Array = []
var _density := PackedFloat32Array()
var _kiai: Array = []
var _drag := ""
var _drag_from := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Notendichte je Zeitstueck (normiert auf das dichteste Stueck).
static func density_of(bm: Beatmap, end_ms: float, bins: int = BINS) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(bins)
	d.fill(0.0)
	for o in bm.hit_objects:
		var i := clampi(int(o.time / maxf(end_ms, 1.0) * bins), 0, bins - 1)
		d[i] += 1.0
	var mx := 0.0
	for v in d:
		mx = maxf(mx, v)
	if mx > 0.0:
		for i in bins:
			d[i] /= mx
	return d


func set_map(bm: Beatmap, end_ms: float) -> void:
	song_ms = maxf(end_ms, 1.0)
	_density = density_of(bm, song_ms)
	_kiai = []
	for iv in bm.kiai_intervals:
		_kiai.append(Vector2(float(iv.start), minf(float(iv.end), song_ms)))
	queue_redraw()


func set_range(a: float, b: float) -> void:
	a_ms = a
	b_ms = b
	queue_redraw()


func set_cursor(t: float) -> void:
	cursor_ms = clampf(t, 0.0, song_ms)
	queue_redraw()


func x_of(t: float) -> float:
	return t / song_ms * size.x


func t_of(x: float) -> float:
	return clampf(x / maxf(size.x, 1.0), 0.0, 1.0) * song_ms


func _draw() -> void:
	var w := size.x
	var h := size.y
	var top := 18.0
	var bar_h := h - top - 16.0
	draw_rect(Rect2(0, top, w, bar_h), UiTheme.RAISED)
	for k in _kiai:
		draw_rect(Rect2(x_of(k.x), top, x_of(k.y) - x_of(k.x), bar_h), Color(UiTheme.ACCENT, 0.06))
	var bw := w / float(maxi(_density.size(), 1))
	for i in _density.size():
		var v := _density[i]
		if v <= 0.0:
			continue
		var bh := maxf(2.0, v * (bar_h - 6.0))
		var t_mid := (float(i) + 0.5) / _density.size() * song_ms
		var inside := t_mid >= a_ms and t_mid < b_ms
		var col := Color(UiTheme.TEXT, 0.62) if inside else Color(UiTheme.DIM, 0.42)
		draw_rect(Rect2(i * bw + 0.5, top + bar_h - bh, maxf(bw - 1.0, 1.0), bh), col)
	if b_ms > a_ms:
		var xa := x_of(a_ms)
		var xb := x_of(b_ms)
		draw_rect(Rect2(xa, top, xb - xa, bar_h), Color(UiTheme.ACCENT, 0.16))
		for e in [[xa, "A"], [xb, "B"]]:
			draw_line(Vector2(e[0], top - 2.0), Vector2(e[0], top + bar_h), UiTheme.ACCENT, 2.0)
			_text(Vector2(float(e[0]) - 4.0, top - 4.0), str(e[1]), UiTheme.ACCENT, 12)
	for m in marks:
		var x0 := x_of(float(m.t0))
		var x1 := maxf(x_of(float(m.t1)), x0 + 3.0)
		draw_rect(Rect2(x0, top + bar_h + 4.0, x1 - x0, 4.0), UiTheme.BAD)
	var xc := x_of(cursor_ms)
	draw_line(Vector2(xc, top), Vector2(xc, top + bar_h), Color(UiTheme.TEXT, 0.85), 1.0)
	_text(Vector2(0, h - 1.0), _fmt(0.0), UiTheme.DIM, 11)
	var end_txt := _fmt(song_ms)
	_text(Vector2(w - _text_w(end_txt, 11), h - 1.0), end_txt, UiTheme.DIM, 11)


func _text(p: Vector2, s: String, col: Color, fs: int) -> void:
	draw_string(get_theme_default_font(), p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_w(s: String, fs: int) -> float:
	return get_theme_default_font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


static func _fmt(ms: float) -> String:
	var s := int(maxf(ms, 0.0) / 1000.0)
	return "%d:%02d" % [s / 60, s % 60]


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		var t := t_of(mb.position.x)
		if mb.pressed:
			# Klick unter der Leiste auf eine Fehlerstelle: Abschnitt darum.
			if mb.position.y > size.y - 16.0:
				for m in marks:
					if absf(mb.position.x - (x_of(float(m.t0)) + x_of(float(m.t1))) * 0.5) < 10.0 \
							+ (x_of(float(m.t1)) - x_of(float(m.t0))) * 0.5:
						var r := PracticeStore.range_for_mark(m, song_ms)
						set_range(r.x, r.y)
						range_changed.emit(a_ms, b_ms)
						return
			if b_ms > a_ms and absf(mb.position.x - x_of(a_ms)) <= GRAB_PX:
				_drag = "a"
			elif b_ms > a_ms and absf(mb.position.x - x_of(b_ms)) <= GRAB_PX:
				_drag = "b"
			else:
				_drag = "new"
				_drag_from = t
			set_cursor(t)
			cursor_moved.emit(cursor_ms)
		elif _drag != "":
			_apply_drag(t)
			_drag = ""
			range_changed.emit(a_ms, b_ms)
		accept_event()
	elif ev is InputEventMouseMotion and _drag != "":
		_apply_drag(t_of((ev as InputEventMouseMotion).position.x))
		accept_event()


func _apply_drag(t: float) -> void:
	match _drag:
		"a":
			a_ms = minf(t, b_ms - 1000.0)
		"b":
			b_ms = maxf(t, a_ms + 1000.0)
		"new":
			if absf(t - _drag_from) >= 300.0:
				a_ms = minf(t, _drag_from)
				b_ms = maxf(t, _drag_from)
	set_cursor(t)
	queue_redraw()
