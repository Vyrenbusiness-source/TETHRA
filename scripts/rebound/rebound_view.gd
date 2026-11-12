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
## Spaltenfarben kuehl (Blau / helles Stahlblau): Gold bleibt allein den Hold-Baellen.
const DEFAULT_LANES := [
	Color(0.38, 0.62, 0.98), Color(0.66, 0.80, 0.95), Color(0.66, 0.80, 0.95), Color(0.38, 0.62, 0.98),
]
## Hold-Ball: warmes Gold, in keiner Spaltenfarbe, auch bei Rot-Gruen-Schwaeche klar.
const COL_HOLD := Color(1.0, 0.80, 0.22)
const COL_WRONG := Color(1.0, 0.50, 0.42)
const WRONG_MS := 800.0
const RING_MS := 900.0
const GHOST_MS := 1300.0
const CONTACT_MS := 95.0
const FX_MS := 380.0
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
var _wrong: Array = []
var _rest := [false, false, false, false]
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


## Falsche Taste (Anti-Mash): kurzer, dezenter Hinweis ueber der Spalte.
func on_wrong_key(col: int) -> void:
	_wrong.append({"col": col, "t0": Time.get_ticks_msec()})
	if _wrong.size() > 8:
		_wrong.pop_front()


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
	l.rx = minf(w * 0.108, h * 0.165)
	l.ry = l.rx * 0.30
	l.pitch = l.rx * 2.32
	var cols := flight.columns if flight != null else 4
	l.x0 = (w - l.pitch * float(cols - 1)) * 0.5
	l.y = h * 0.775
	l.ball_r = l.rx * 0.37
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
	var balls: Array = []
	for c in flight.columns:
		var bb := flight.ball(c, t_ms)
		balls.append(bb)
		_rest[c] = bb.kind == ReboundFlight.Kind.REST
	for c in flight.columns:
		_draw_drum(l, c)
	for c in flight.columns:
		_draw_target(l, c, balls[c])
	_draw_fx(l)
	_draw_chords(l, balls)
	for c in flight.columns:
		_draw_ball_full(l, c, balls[c])
	for c in flight.columns:
		_draw_keycap(l, c)
	_draw_wrong(l)


func _draw_floor(l: Lay) -> void:
	var y0 := l.y - l.ry * 3.0
	var pts := PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, size.y), Vector2(0, size.y)])
	var top := Color(0.03, 0.03, 0.035, 0.0)
	var bot := Color(0.03, 0.03, 0.035, 0.70)
	draw_polygon(pts, PackedColorArray([top, top, bot, bot]))


func _ell(center: Vector2, ratio: float) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, ratio))


func _flat() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Ziel dieser Flugphase ein Hold? (Ball im Anflug oder liegend; nicht beim Auslauf.)
func _is_hold(c: int, b: Dictionary) -> bool:
	if int(b.seg) < 0:
		return false
	if b.kind != ReboundFlight.Kind.AIR and b.kind != ReboundFlight.Kind.FALL and b.kind != ReboundFlight.Kind.REST:
		return false
	return (flight.segs[c][int(b.seg)] as ReboundFlight.Seg).hold


## Fell: flache Flaeche mit klarer Kante. Hold: Kante und Flaeche in Gold.
func _draw_drum(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var cx := l.cx(c)
	var rest: bool = _rest[c]
	var edge := COL_HOLD if rest else col
	var body := COL_BODY.lerp(edge, 0.10 + (0.22 if rest else 0.0) + 0.18 * g)
	# Seitenband: nur eine ruhige dunkle Kante.
	_ell(Vector2(cx, l.y + l.depth), 0.3)
	draw_circle(Vector2.ZERO, l.rx, COL_BODY.darkened(0.4))
	_flat()
	draw_rect(Rect2(cx - l.rx, l.y, l.rx * 2.0, l.depth), COL_BODY.darkened(0.4))
	# Fell.
	_ell(Vector2(cx, l.y), 0.3)
	draw_circle(Vector2.ZERO, l.rx, body)
	draw_arc(Vector2.ZERO, l.rx, 0.0, TAU, 64, Color(edge, 0.75 + 0.25 * maxf(g, 1.0 if rest else 0.0)), 3.4, true)
	_flat()


## Tastenbuchstabe gross unter dem Fell, Balken in Spaltenfarbe.
func _draw_keycap(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var fs := int(l.rx * 0.50)
	var txt := str(key_labels[c]) if c < key_labels.size() else ""
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var cx := l.cx(c)
	var y := l.y + l.depth + l.ry + fs * 1.05
	var edge := COL_HOLD if _rest[c] else col
	var pw := maxf(fs * 1.5, ts.x + fs * 0.7)
	var plate := Rect2(cx - pw * 0.5, y - fs * 1.05, pw, fs * 1.5)
	_cap_style.bg_color = Color(edge, 0.10 + 0.40 * g)
	_cap_style.border_color = Color(edge, 0.55 + 0.45 * g)
	_cap_style.set_border_width_all(2)
	draw_style_box(_cap_style, plate)
	draw_string(_font, Vector2(cx - ts.x * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 0.80 + 0.20 * g))


## Landering + Geister-Bogen des Zielflugs. Hold: doppelter Ring in Gold.
func _draw_target(l: Lay, c: int, b: Dictionary) -> void:
	var arr: Array = flight.segs[c]
	var k := flight.first_landing_at_or_after(c, t_ms)
	if k < 0:
		return
	var s := arr[k] as ReboundFlight.Seg
	var col := COL_HOLD if s.hold else lane_color(c)
	var until := s.t1 - t_ms
	var win := minf(RING_MS, maxf(s.dur(), 120.0))
	if until <= win and until >= -10.0 and b.kind != ReboundFlight.Kind.REST:
		var q := clampf(1.0 - until / win, 0.0, 1.0)
		var ease_q := q * q * (3.0 - 2.0 * q)
		var rr := lerpf(l.rx * 0.96, l.ball_r * 1.18, ease_q)
		var lw := 1.8 + 2.2 * q
		_ell(Vector2(l.cx(c) + s.x1 * l.a, l.y), 0.3)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(col.lerp(Color.WHITE, 0.2 * q), 0.30 + 0.70 * q), lw, true)
		if s.hold:
			draw_arc(Vector2.ZERO, rr * 0.80, 0.0, TAU, 40, Color(col, 0.30 + 0.70 * q), lw * 0.8, true)
		if q > 0.82:
			draw_circle(Vector2.ZERO, l.ball_r * 1.18, Color(col, 0.14 * (q - 0.82) / 0.18))
		_flat()
	# Geister-Bogen: der Huepfer nach dieser Landung (uebernaechste Note, gedimmt).
	if until < GHOST_MS and k + 1 < arr.size():
		var n := arr[k + 1] as ReboundFlight.Seg
		if not n.fall and n.peak > 0.07 and absf(n.t0 - s.free) < 1.0:
			var gc := COL_HOLD if n.hold else lane_color(c).lerp(Color.WHITE, 0.3)
			var fade := clampf((GHOST_MS - until) / 500.0, 0.0, 1.0)
			var dots := clampi(int(n.dur() / 28.0), 8, 28)
			for i in range(1, dots):
				var p := float(i) / float(dots)
				var hh := 4.0 * n.peak * p * (1.0 - p)
				var xx := lerpf(n.x0, n.x1, p)
				var pos := Vector2(l.cx(c) + xx * l.a, l.y - l.ball_r - hh * l.hpx)
				if n.hold:
					draw_arc(pos, 2.6, 0.0, TAU, 10, Color(gc, 0.34 * fade), 1.4, true)
				else:
					draw_circle(pos, 1.6, Color(gc, 0.22 * fade))


func _draw_chords(l: Lay, balls: Array) -> void:
	var cols := flight.columns
	var targets: Array = []
	for c in cols:
		var k := flight.first_landing_at_or_after(c, t_ms)
		targets.append(flight.segs[c][k] if k >= 0 else null)
	# Spalten mit gleicher Landezeit der Reihe nach verbinden.
	var prev := -1
	for c in cols:
		var a = targets[c]
		if a == null or (balls[c] as Dictionary).kind == ReboundFlight.Kind.HIDDEN:
			continue
		if prev >= 0:
			var p = targets[prev]
			if absf(a.t1 - p.t1) <= 1.5:
				var pa := _ball_pos(l, prev, balls[prev], 1.0)
				var pb := _ball_pos(l, c, balls[c], 1.0)
				var q := clampf(1.0 - maxf(a.t1 - t_ms, 0.0) / 700.0, 0.2, 1.0)
				draw_line(pa, pb, Color(1, 1, 1, 0.22 * q), 2.0, true)
		prev = c


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
	var col := COL_HOLD if _is_hold(c, b) else lane_color(c)
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
	var hold := _is_hold(c, b)
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
	# Spur: Normal ein schmaler Streifen, Hold ein duenner, goldener Faden.
	if b.kind != ReboundFlight.Kind.REST:
		var prev := pos
		for i in range(1, TRAIL_N + 1):
			var tb := flight.ball(c, t_ms - TRAIL_STEP_MS * float(i))
			if tb.kind == ReboundFlight.Kind.HIDDEN:
				break
			var tp := _ball_pos(l, c, tb, 1.0)
			var f := 1.0 - float(i) / float(TRAIL_N + 1)
			if hold:
				draw_line(prev, tp, Color(col, 0.38 * f * alpha), 2.4 * f + 0.8, true)
			else:
				draw_line(prev, tp, Color(col, 0.16 * f * alpha), R * 0.9 * f, true)
			prev = tp
	if hold:
		_draw_hold_thread(l, c, b, pos, R * sq.y, col, alpha)
		_draw_ball_hold(pos, R * sq.x, R * sq.y, col, alpha)
		if b.kind == ReboundFlight.Kind.REST:
			var rr := R * 1.55
			draw_arc(pos, rr, 0.0, TAU, 40, Color(col, 0.25), 3.0, true)
			draw_arc(pos, rr, -PI * 0.5, -PI * 0.5 + TAU * float(b.p), 48, Color(col.lightened(0.25), 1.0), 4.4, true)
	else:
		_draw_ball(pos, R * sq.x, R * sq.y, col, alpha)


## Faden ueber dem Hold-Ball: Laenge = Hold-Dauer, beim Halten schmilzt er ab.
func _draw_hold_thread(l: Lay, c: int, b: Dictionary, pos: Vector2, ry: float, col: Color, alpha: float) -> void:
	var s := flight.segs[c][int(b.seg)] as ReboundFlight.Seg
	var len := l.ball_r * (0.9 + 2.4 * clampf((s.free - s.t1) / 1600.0, 0.0, 1.0))
	if b.kind == ReboundFlight.Kind.REST:
		len *= 1.0 - float(b.p)
	if len < 2.0:
		return
	var a := pos + Vector2(0, -ry * 1.05)
	var e := a + Vector2(0, -len)
	draw_line(a, e, Color(col, 0.85 * alpha), 3.0, true)
	draw_line(e + Vector2(-5, 0), e + Vector2(5, 0), Color(col, alpha), 3.0, true)


## Normaler Ball: flache Scheibe in Spaltenfarbe mit dunklem Rand.
func _draw_ball(pos: Vector2, rx: float, ry: float, col: Color, alpha: float) -> void:
	var ratio := ry / maxf(rx, 0.001)
	draw_set_transform(pos, 0.0, Vector2(1.0, ratio))
	draw_circle(Vector2.ZERO, rx, Color(col.darkened(0.45), alpha))
	draw_circle(Vector2.ZERO, rx * 0.88, Color(col, alpha))
	draw_circle(Vector2(-rx * 0.22, -rx * 0.26), rx * 0.30, Color(col.lightened(0.35), 0.8 * alpha))
	_flat()


## Hold-Ball: dunkler Kern in dickem Goldring, Punkt in der Mitte, zweiter Ring aussen.
func _draw_ball_hold(pos: Vector2, rx: float, ry: float, col: Color, alpha: float) -> void:
	var ratio := ry / maxf(rx, 0.001)
	draw_set_transform(pos, 0.0, Vector2(1.0, ratio))
	draw_circle(Vector2.ZERO, rx * 1.0, Color(col, alpha))
	draw_circle(Vector2.ZERO, rx * 0.62, Color(COL_BODY, alpha))
	draw_circle(Vector2.ZERO, rx * 0.26, Color(col, alpha))
	draw_arc(Vector2.ZERO, rx * 1.22, 0.0, TAU, 40, Color(col, 0.55 * alpha), 2.0, true)
	_flat()


func _draw_wrong(l: Lay) -> void:
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for w in _wrong:
		var age := float(now - int(w.t0))
		if age < 0.0 or age > WRONG_MS:
			continue
		keep.append(w)
		var q := age / WRONG_MS
		var a := (1.0 - q * q) * minf(age / 80.0, 1.0)
		var fs := int(maxf(l.rx * 0.20, 12.0))
		var txt := "WRONG KEY"
		var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var cx := l.cx(int(w.col))
		var y := l.y - l.ball_r * 3.0 - 10.0 * q
		var r := Rect2(cx - ts.x * 0.5 - 8.0, y - fs - 2.0, ts.x + 16.0, fs + 10.0)
		draw_rect(r, Color(0.05, 0.04, 0.04, 0.70 * a))
		draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), Color(COL_WRONG, 0.85 * a))
		draw_string(_font, Vector2(cx - ts.x * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_WRONG, a))
	_wrong = keep


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
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(jc, (0.30 if miss else 0.90) * (1.0 - q)), lerpf(3.6, 1.0, q), true)
		_flat()
		if age < 160.0:
			var fl := 1.0 - age / 160.0
			_ell(Vector2(l.cx(c), l.y), 0.3)
			draw_circle(Vector2.ZERO, l.rx, Color(jc, (0.10 if miss else 0.26) * fl))
			_flat()
	_fx = keep
