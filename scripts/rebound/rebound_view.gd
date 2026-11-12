class_name ReboundView
extends Control

## Rebound: Darstellung. Vier Trommelfelle im unteren Bilddrittel, je ein Ball, der
## nach ReboundFlight huepft. Rein visuell (liest Zeit und Urteile, wertet nichts).
## Lesbarkeit zuerst: Landering schrumpft bis zur Notenzeit, feiner Geister-Bogen
## zeigt den Huepfer danach, Schatten wird zur Landung kleiner und dunkler.

const COL_MISS := Color(0.55, 0.555, 0.57)
const COL_BODY := Color(0.105, 0.10, 0.095)
const JUDGE_COL := [
	Color(0.80, 0.93, 1.0), Color(1.0, 0.86, 0.45), Color(0.55, 0.85, 0.55),
	Color(0.50, 0.70, 0.95), Color(0.78, 0.60, 0.95), Color(0.55, 0.555, 0.57),
]
const DEFAULT_LANES := [
	Color(0.56, 0.68, 0.88), Color(0.95, 0.64, 0.23), Color(0.95, 0.64, 0.23), Color(0.56, 0.68, 0.88),
]
const RING_MS := 900.0
const GHOST_MS := 1300.0
const CONTACT_MS := 95.0
const FX_MS := 560.0
const TRAIL_STEP_MS := 26.0
const TRAIL_N := 5

var flight: ReboundFlight
var t_ms := 0.0:
	set(v):
		t_ms = v
		queue_redraw()
var held := [false, false, false, false]
var key_labels: Array = ["D", "F", "J", "K"]
## Notenindex -> Qualitaet (0..5), gesetzt aus dem Core.
var judged: Dictionary = {}

var _fx: Array = []
var _glow := [0.0, 0.0, 0.0, 0.0]
var _seg_of := {}
var _font: Font
var _cap_style: StyleBoxFlat
var _lane_cols: Array = []
var _last_hpx := 400.0


func setup(p_flight: ReboundFlight) -> void:
	flight = p_flight
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seg_of.clear()
	for c in flight.columns:
		for s in flight.segs[c]:
			_seg_of[(s as ReboundFlight.Seg).idx] = s
	_font = UiTheme.heading_font(2)
	_cap_style = StyleBoxFlat.new()
	_cap_style.set_corner_radius_all(7)
	_cap_style.bg_color = Color(1, 1, 1, 0.06)
	_cap_style.set_border_width_all(1)
	_cap_style.border_color = Color(1, 1, 1, 0.22)
	reload_colors()


## Spaltenfarben: Notenfarben aus den Einstellungen (sonst ruhige Vorgabe).
func reload_colors() -> void:
	_lane_cols.clear()
	for c in 4:
		var d: Color = DEFAULT_LANES[c % 4]
		if NoteColors.is_custom(Settings.playfield_2d):
			d = NoteColors.color_for(c, false, Settings.playfield_2d, d)
		_lane_cols.append(d)


func lane_color(c: int) -> Color:
	if _lane_cols.is_empty():
		return DEFAULT_LANES[posmod(c, 4)]
	return _lane_cols[posmod(c, _lane_cols.size())]


## Urteil (Core): Fell-Welle in Wertungsfarbe, Miss matt/grau.
func on_judged(index: int, result: Dictionary) -> void:
	var q := int(result.get("quality", 5))
	judged[index] = q
	_add_fx(index, int(result.get("column", 0)), q)


func on_hold_start(index: int, quality: int) -> void:
	var s = _seg_of.get(index)
	_add_fx(index, (s as ReboundFlight.Seg).col if s != null else 0, quality)


func _add_fx(index: int, col: int, q: int) -> void:
	var s = _seg_of.get(index)
	var x := (s as ReboundFlight.Seg).x1 if s != null else 0.0
	_fx.append({"t0": t_ms, "col": col, "q": q, "x": x})
	if _fx.size() > 40:
		_fx.pop_front()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

class Lay extends RefCounted:
	var rx := 80.0
	var ry := 24.0
	var pitch := 190.0
	var x0 := 0.0
	var y := 0.0
	var ball_r := 27.0
	var a := 70.0
	var hpx := 400.0
	var depth := 18.0

	func cx(c: int) -> float:
		return x0 + pitch * float(c)


func _layout() -> Lay:
	var l := Lay.new()
	var w := size.x
	var h := size.y
	l.rx = minf(w * 0.092, h * 0.118)
	l.ry = l.rx * 0.30
	l.pitch = l.rx * 2.32
	var cols := flight.columns if flight != null else 4
	l.x0 = (w - l.pitch * float(cols - 1)) * 0.5
	l.y = h * 0.775
	l.ball_r = l.rx * 0.34
	l.a = l.rx * 0.9
	l.depth = l.rx * 0.20
	l.hpx = l.y - l.ball_r * 2.0 - h * 0.15
	return l


func _ball_pos(l: Lay, c: int, b: Dictionary, sy: float) -> Vector2:
	return Vector2(l.cx(c) + float(b.x) * l.a, l.y - l.ball_r * sy - float(b.h) * l.hpx)


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	for c in 4:
		var target := 1.0 if held[c] else 0.0
		_glow[c] = move_toward(_glow[c], target, delta * (14.0 if target > _glow[c] else 5.0))
	queue_redraw()


func _draw() -> void:
	if flight == null or size.x < 8.0:
		return
	var l := _layout()
	_last_hpx = l.hpx
	_draw_floor(l)
	for c in flight.columns:
		_draw_drum(l, c)
	var balls: Array = []
	for c in flight.columns:
		balls.append(flight.ball(c, t_ms))
	for c in flight.columns:
		_draw_target(l, c, balls[c])
	_draw_fx(l)
	_draw_chords(l, balls)
	for c in flight.columns:
		_draw_ball_full(l, c, balls[c])
	for c in flight.columns:
		_draw_keycap(l, c)


func _draw_floor(l: Lay) -> void:
	var y0 := l.y - l.ry * 3.0
	var pts := PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, size.y), Vector2(0, size.y)])
	var top := Color(0.04, 0.038, 0.036, 0.0)
	var bot := Color(0.04, 0.038, 0.036, 0.62)
	draw_polygon(pts, PackedColorArray([top, top, bot, bot]))


func _ell(center: Vector2, ratio: float) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, ratio))


func _flat() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_drum(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var cx := l.cx(c)
	var body := COL_BODY.lerp(col, 0.07)
	# Korper: untere Ellipse + Band.
	_ell(Vector2(cx, l.y + l.depth), 0.3)
	draw_circle(Vector2.ZERO, l.rx, body.darkened(0.25))
	_flat()
	draw_rect(Rect2(cx - l.rx, l.y, l.rx * 2.0, l.depth), body.darkened(0.25))
	draw_rect(Rect2(cx - l.rx, l.y, l.rx * 2.0, l.depth), Color(col, 0.04))
	_ell(Vector2(cx, l.y + l.depth), 0.3)
	draw_arc(Vector2.ZERO, l.rx, 0.0, PI, 40, Color(col, 0.20 + 0.25 * g), 1.4, true)
	_flat()
	# Fell.
	_ell(Vector2(cx, l.y), 0.3)
	draw_circle(Vector2.ZERO, l.rx, body.lerp(col, 0.16 + 0.22 * g))
	draw_circle(Vector2.ZERO, l.rx * 0.84, Color(col, 0.05 + 0.10 * g))
	draw_arc(Vector2.ZERO, l.rx, 0.0, TAU, 56, Color(col, 0.55 + 0.40 * g), 3.2, true)
	draw_arc(Vector2.ZERO, l.rx * 0.84, 0.0, TAU, 48, Color(col, 0.10), 1.0, true)
	_flat()


func _draw_keycap(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var w := l.rx * 0.62
	var h := w * 0.82
	var r := Rect2(l.cx(c) - w * 0.5, l.y + l.depth + l.ry + h * 0.35, w, h)
	_cap_style.bg_color = Color(col, 0.08 + 0.30 * g)
	_cap_style.border_color = Color(col, 0.35 + 0.55 * g)
	draw_style_box(_cap_style, r)
	var txt := str(key_labels[c]) if c < key_labels.size() else ""
	var fs := int(h * 0.50)
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, Vector2(r.position.x + (w - ts.x) * 0.5, r.position.y + h * 0.5 + ts.y * 0.30),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.55 + 0.45 * g))


## Landering + Geister-Bogen des Zielflugs.
func _draw_target(l: Lay, c: int, b: Dictionary) -> void:
	var arr: Array = flight.segs[c]
	var k := flight.first_landing_at_or_after(c, t_ms)
	if k < 0:
		return
	var s := arr[k] as ReboundFlight.Seg
	var col := lane_color(c)
	var until := s.t1 - t_ms
	var win := minf(RING_MS, maxf(s.dur(), 120.0))
	if until <= win and until >= -10.0 and b.kind != ReboundFlight.Kind.REST:
		var q := clampf(1.0 - until / win, 0.0, 1.0)
		var ease_q := q * q * (3.0 - 2.0 * q)
		var rr := lerpf(l.rx * 0.96, l.ball_r * 1.18, ease_q)
		_ell(Vector2(l.cx(c) + s.x1 * l.a, l.y), 0.3)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, 0.25 * q), 0.22 + 0.62 * q), 1.6 + 1.6 * q, true)
		if q > 0.82:
			draw_circle(Vector2.ZERO, l.ball_r * 1.18, Color(col, 0.10 * (q - 0.82) / 0.18))
		_flat()
	# Geister-Bogen: der Huepfer nach dieser Landung.
	if until < GHOST_MS and k + 1 < arr.size():
		var n := arr[k + 1] as ReboundFlight.Seg
		if not n.fall and n.peak > 0.07 and absf(n.t0 - s.free) < 1.0:
			var fade := clampf((GHOST_MS - until) / 500.0, 0.0, 1.0)
			var dots := clampi(int(n.dur() / 28.0), 8, 28)
			for i in range(1, dots):
				var p := float(i) / float(dots)
				var hh := 4.0 * n.peak * p * (1.0 - p)
				var xx := lerpf(n.x0, n.x1, p)
				var pos := Vector2(l.cx(c) + xx * l.a, l.y - l.ball_r - hh * l.hpx)
				draw_circle(pos, 1.7, Color(col.lerp(Color.WHITE, 0.3), 0.30 * fade))


func _draw_chords(l: Lay, balls: Array) -> void:
	var cols := flight.columns
	var targets: Array = []
	for c in cols:
		var k := flight.first_landing_at_or_after(c, t_ms)
		targets.append(flight.segs[c][k] if k >= 0 else null)
	for c in cols - 1:
		var a = targets[c]
		var b = targets[c + 1]
		if a == null or b == null or absf(a.t1 - b.t1) > 1.5:
			continue
		var ba: Dictionary = balls[c]
		var bb: Dictionary = balls[c + 1]
		if ba.kind == ReboundFlight.Kind.HIDDEN or bb.kind == ReboundFlight.Kind.HIDDEN:
			continue
		var pa := _ball_pos(l, c, ba, 1.0)
		var pb := _ball_pos(l, c + 1, bb, 1.0)
		var q := clampf(1.0 - maxf(a.t1 - t_ms, 0.0) / 700.0, 0.2, 1.0)
		draw_line(pa, pb, Color(1, 1, 1, 0.20 * q), 2.0, true)


func _squash(b: Dictionary) -> Vector2:
	var sx := 1.0
	var sy := 1.0
	var kind: int = b.kind
	if kind == ReboundFlight.Kind.REST:
		var ramp := clampf(float(b.since) / 70.0, 0.0, 1.0)
		return Vector2(lerpf(1.0, 1.28, ramp), lerpf(1.0, 0.60, ramp))
	var since: float = b.since
	if since < CONTACT_MS and kind != ReboundFlight.Kind.FALL:
		var s := sin(PI * since / CONTACT_MS) * 0.32
		sy -= s
		sx += s * 0.55
	var until: float = b.until
	if until < 40.0 and kind != ReboundFlight.Kind.EXIT:
		var s2 := (1.0 - until / 40.0) * 0.12
		sy += s2
		sx -= s2 * 0.5
	var sp := clampf(absf(float(b.vy)) * _last_hpx / 1.7, 0.0, 1.0)
	sy += 0.14 * sp
	sx -= 0.09 * sp
	return Vector2(sx, sy)


func _ball_color(c: int, b: Dictionary) -> Color:
	var col := lane_color(c)
	var pi := flight.last_landing_before(c, t_ms)
	if pi >= 0:
		var seg := flight.segs[c][pi] as ReboundFlight.Seg
		if int(judged.get(seg.idx, 0)) == 5 and b.kind != ReboundFlight.Kind.FALL:
			return Color(COL_MISS.lerp(col, 0.18), 0.62)
	return col


func _draw_ball_full(l: Lay, c: int, b: Dictionary) -> void:
	if b.kind == ReboundFlight.Kind.HIDDEN or float(b.alpha) <= 0.01:
		return
	var sq := _squash(b)
	var col := _ball_color(c, b)
	var alpha: float = float(b.alpha) * col.a
	col.a = 1.0
	var R := l.ball_r
	var pos := _ball_pos(l, c, b, sq.y)
	# Schatten auf dem Fell: zur Landung kleiner und dunkler.
	var hh := clampf(float(b.h), 0.0, 1.0)
	var sx := l.cx(c) + float(b.x) * l.a
	_ell(Vector2(sx, l.y), 0.3)
	draw_circle(Vector2.ZERO, R * (0.62 + 0.62 * hh), Color(0, 0, 0, (0.60 - 0.42 * hh) * float(b.alpha)))
	_flat()
	# Spur.
	if b.kind != ReboundFlight.Kind.REST:
		for i in range(1, TRAIL_N + 1):
			var tb := flight.ball(c, t_ms - TRAIL_STEP_MS * float(i))
			if tb.kind == ReboundFlight.Kind.HIDDEN:
				break
			var tp := _ball_pos(l, c, tb, 1.0)
			var f := 1.0 - float(i) / float(TRAIL_N + 1)
			draw_circle(tp, R * (0.35 + 0.5 * f), Color(col, 0.13 * f * alpha))
	_draw_ball(pos, R * sq.x, R * sq.y, col, alpha)
	# Hold: Ring fuellt sich.
	if b.kind == ReboundFlight.Kind.REST:
		var rr := R * 1.45
		var cc := pos
		draw_arc(cc, rr, 0.0, TAU, 40, Color(col, 0.22), 2.0, true)
		draw_arc(cc, rr, -PI * 0.5, -PI * 0.5 + TAU * float(b.p), 48, Color(col.lerp(Color.WHITE, 0.3), 0.95), 3.2, true)


func _draw_ball(pos: Vector2, rx: float, ry: float, col: Color, alpha: float) -> void:
	var ratio := ry / maxf(rx, 0.001)
	draw_set_transform(pos, 0.0, Vector2(1.0, ratio))
	draw_circle(Vector2.ZERO, rx, Color(col.darkened(0.32), alpha))
	draw_circle(Vector2(-rx * 0.06, -rx * 0.08), rx * 0.90, Color(col, alpha))
	draw_circle(Vector2(-rx * 0.20, -rx * 0.26), rx * 0.55, Color(col.lightened(0.16), alpha))
	draw_circle(Vector2(-rx * 0.34, -rx * 0.40), rx * 0.20, Color(1, 1, 1, 0.55 * alpha))
	_flat()


func _draw_fx(l: Lay) -> void:
	var keep: Array = []
	for fx in _fx:
		var age: float = t_ms - float(fx.t0)
		if age < 0.0 or age > FX_MS:
			continue
		keep.append(fx)
		var q := age / FX_MS
		var c: int = fx.col
		var jc: Color = JUDGE_COL[clampi(int(fx.q), 0, 5)]
		var cx: float = l.cx(c) + float(fx.x) * l.a
		var miss: bool = int(fx.q) == 5
		var e := 1.0 - (1.0 - q) * (1.0 - q)
		var rr := lerpf(l.ball_r * 1.1, l.rx * (0.78 if miss else 1.28), e)
		_ell(Vector2(cx, l.y), 0.3)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(jc, (0.30 if miss else 0.85) * (1.0 - q)), lerpf(3.4, 1.0, q), true)
		if not miss and int(fx.q) <= 1:
			var r2 := lerpf(l.ball_r * 0.8, l.rx * 0.95, e)
			draw_arc(Vector2.ZERO, r2, 0.0, TAU, 40, Color(jc, 0.45 * (1.0 - q)), 1.6, true)
		_flat()
		if age < 200.0:
			var fl := 1.0 - age / 200.0
			_ell(Vector2(l.cx(c), l.y), 0.3)
			draw_circle(Vector2.ZERO, l.rx, Color(jc, (0.10 if miss else 0.26) * fl))
			_flat()
	_fx = keep
