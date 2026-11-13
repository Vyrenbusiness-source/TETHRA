class_name ReboundView
extends Control

## Rebound: Darstellung. Vier Trommeln auf einem Podest, je ein Ball, der
## nach ReboundFlight huepft. Rein visuell (liest Zeit und Urteile, wertet nichts).
## Lesbarkeit zuerst: Landering schrumpft gleichmaessig bis zur Notenzeit auf einen festen
## Zielring, die naechste Landung fuehrt (spaetere Ringe duenner), feiner Geister-Bogen
## zeigt den Huepfer danach, Schatten wird zur Landung kleiner und dunkler.

const COL_MISS := Color(0.55, 0.555, 0.57)
const COL_BODY := Color(0.105, 0.10, 0.095)
## Trommel: Kessel (dunkles Graphit), Metallreifen, Fell (warmes Grau).
const COL_SHELL := Color(0.215, 0.206, 0.194)
const COL_METAL := Color(0.470, 0.455, 0.430)
const COL_HEAD := Color(0.215, 0.208, 0.198)
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
const FX_MS := 420.0
const FX_RING_MS := 260.0
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
var _lead_t := INF
var _u := 1.0
var _body_font: Font
static var _tex := {}


func setup(p_flight: ReboundFlight) -> void:
	flight = p_flight
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seg_of.clear()
	for c in flight.columns:
		for s in flight.segs[c]:
			_seg_of[(s as ReboundFlight.Seg).idx] = s
	_font = UiTheme.heading_font(2)
	_body_font = UiTheme.body_font()
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
	var dt := 0.0 if bool(result.get("hold_end", false)) else float(result.get("dt", 0.0))
	_add_fx(index, int(result.get("column", 0)), q, dt)


func on_hold_start(index: int, quality: int) -> void:
	var s = _seg_of.get(index)
	_add_fx(index, (s as ReboundFlight.Seg).col if s != null else 0, quality)


## Falsche Taste (Anti-Mash): kurzer, dezenter Hinweis ueber der Spalte.
func on_wrong_key(col: int) -> void:
	_wrong.append({"col": col, "t0": Time.get_ticks_msec()})
	if _wrong.size() > 8:
		_wrong.pop_front()


func _add_fx(index: int, col: int, q: int, dt: float = 0.0) -> void:
	var s = _seg_of.get(index)
	var x := (s as ReboundFlight.Seg).x1 if s != null else 0.0
	_fx.append({"t0": t_ms, "col": col, "q": q, "x": x, "dt": dt})
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
	var cols := 4
	## Buehne: Horizont, Podest-Oberkante / -Vorderkante, Hoehe der Frontblende.
	var horizon := 0.0
	var deck_top := 0.0
	var deck_front := 0.0
	var face := 0.0
	var half_top := 0.0
	var half_front := 0.0

	func cx(c: int) -> float:
		return x0 + pitch * float(c)

	func mid() -> float:
		return x0 + pitch * float(cols - 1) * 0.5


func _layout() -> Lay:
	var l := Lay.new()
	var w := size.x
	var h := size.y
	l.rx = minf(w * 0.100, h * 0.150)
	l.ry = l.rx * 0.30
	l.pitch = l.rx * 2.34
	l.cols = flight.columns if flight != null else 4
	l.x0 = (w - l.pitch * float(l.cols - 1)) * 0.5
	l.y = h * 0.735
	l.ball_r = l.rx * 0.37
	l.a = l.rx * 0.9
	l.depth = l.rx * 0.30
	l.hpx = l.y - l.ball_r * 2.0 - h * 0.15
	l.horizon = l.y - l.ry * 2.6
	l.deck_top = l.y - l.ry * 1.55
	l.deck_front = l.y + l.depth + l.ry * 1.30
	l.face = h * 0.100
	var span := l.pitch * float(l.cols - 1) * 0.5
	l.half_top = span + l.rx * 1.22
	l.half_front = span + l.rx * 1.42
	return l


func _ball_pos(l: Lay, c: int, b: Dictionary, sy: float) -> Vector2:
	return Vector2(l.cx(c) + float(b.x) * l.a, l.y - l.ball_r * sy - float(b.h) * l.hpx)


# ---------------------------------------------------------------------------
# Texturen (einmal erzeugt, von allen Views geteilt)
# ---------------------------------------------------------------------------

## soft: weicher Fleck (Schatten, Innenlicht). shade: Kugel-Schattierung (Licht oben links).
static func _radial(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for py in n:
		for px in n:
			var p := Vector2((float(px) + 0.5) / float(n) * 2.0 - 1.0, (float(py) + 0.5) / float(n) * 2.0 - 1.0)
			var d := p.length()
			var a := 0.0
			if kind == "soft":
				a = pow(smoothstep(1.0, 0.0, d), 1.5)
				img.set_pixel(px, py, Color(1, 1, 1, a))
			else:
				var e := p.distance_to(Vector2(-0.30, -0.36)) / 1.50
				a = smoothstep(0.30, 1.0, e) * 0.66 * clampf((1.0 - d) * float(n) * 0.5, 0.0, 1.0)
				img.set_pixel(px, py, Color(0, 0, 0, a))
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


func _blob(center: Vector2, half: Vector2, col: Color) -> void:
	draw_texture_rect(_radial("soft"), Rect2(center - half, half * 2.0), false, col)


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
	_u = size.y / 720.0
	_draw_floor(l)
	var balls: Array = []
	# Naechste Landung ueber alle Spalten: sie fuehrt, alles Spaetere tritt zurueck.
	_lead_t = INF
	for c in flight.columns:
		var bb := flight.ball(c, t_ms)
		balls.append(bb)
		_rest[c] = bb.kind == ReboundFlight.Kind.REST
		var k := flight.first_landing_at_or_after(c, t_ms)
		if k >= 0 and not _rest[c]:
			_lead_t = minf(_lead_t, (flight.segs[c][k] as ReboundFlight.Seg).t1)
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


## Buehne: Rueckwand mit Hoehenraster je Spalte, Boden, Podest mit Frontblende.
func _draw_floor(l: Lay) -> void:
	var w := size.x
	var h := size.y
	var m := l.mid()
	# Rueckwand: das Map-Bild scheint nur als Farbhauch durch.
	var wt := Color(0.050, 0.048, 0.046, 0.86)
	var wb := Color(0.086, 0.083, 0.078, 0.90)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, l.horizon), Vector2(0, l.horizon)]),
			PackedColorArray([wt, wt, wb, wb]))
	# Spaltenfeld: ruhige Bahn je Fell, Hoehenlinien als Massstab fuer den Flugbogen.
	var top := l.y - l.ball_r - l.hpx * 1.06
	var hw := l.rx * 0.98
	for c in l.cols:
		var x := l.cx(c)
		var ca := Color(1, 1, 1, 0.0)
		var cb := Color(1, 1, 1, 0.046)
		draw_polygon(PackedVector2Array([Vector2(x - hw, top), Vector2(x + hw, top), Vector2(x + hw, l.horizon), Vector2(x - hw, l.horizon)]),
				PackedColorArray([ca, ca, cb, cb]))
		for sgn in [-1.0, 1.0]:
			var xx: float = round(x + hw * sgn) + 0.5
			draw_polyline_colors(PackedVector2Array([Vector2(xx, top), Vector2(xx, l.horizon)]),
					PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.085)]), 1.0)
		for i in range(1, 5):
			var gy: float = round(l.y - l.ball_r - l.hpx * 0.25 * float(i)) + 0.5
			var tick := hw * (0.26 if i == 4 else 0.14)
			draw_line(Vector2(x - tick, gy), Vector2(x + tick, gy), Color(1, 1, 1, 0.16 if i == 4 else 0.11), 1.0)
	# Boden mit Horizontkante.
	var ft := Color(0.112, 0.108, 0.102, 0.96)
	var fb := Color(0.040, 0.039, 0.038, 0.98)
	draw_polygon(PackedVector2Array([Vector2(0, l.horizon), Vector2(w, l.horizon), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([ft, ft, fb, fb]))
	draw_line(Vector2(0, round(l.horizon) + 0.5), Vector2(w, round(l.horizon) + 0.5), Color(1, 1, 1, 0.10), 1.0)
	# Podest: Schatten am Boden, Deckflaeche, Frontblende mit Lichtkante und Bernsteinlinie.
	var fy := l.deck_front
	_blob(Vector2(m, fy + l.face * 0.95), Vector2(l.half_front * 1.16, l.face * 0.95), Color(0, 0, 0, 0.70))
	var dt := Color(0.118, 0.114, 0.108)
	var df := Color(0.162, 0.156, 0.147)
	draw_polygon(PackedVector2Array([Vector2(m - l.half_top, l.deck_top), Vector2(m + l.half_top, l.deck_top),
			Vector2(m + l.half_front, fy), Vector2(m - l.half_front, fy)]), PackedColorArray([dt, dt, df, df]))
	draw_line(Vector2(m - l.half_top, l.deck_top), Vector2(m + l.half_top, l.deck_top), Color(1, 1, 1, 0.10), 1.0, true)
	for sgn in [-1.0, 1.0]:
		draw_line(Vector2(m + l.half_top * sgn, l.deck_top), Vector2(m + l.half_front * sgn, fy), Color(1, 1, 1, 0.08), 1.0, true)
	var c0 := Color(0.098, 0.094, 0.089)
	var c1 := Color(0.058, 0.056, 0.053)
	var bx := l.half_front * 0.985
	draw_polygon(PackedVector2Array([Vector2(m - l.half_front, fy), Vector2(m + l.half_front, fy),
			Vector2(m + bx, fy + l.face), Vector2(m - bx, fy + l.face)]), PackedColorArray([c0, c0, c1, c1]))
	var e := maxf(round(1.5 * _u), 1.0)
	draw_rect(Rect2(m - l.half_front, round(fy), l.half_front * 2.0, e), Color(0.925, 0.902, 0.855, 0.30))
	draw_rect(Rect2(m - bx, round(fy + l.face) - e, bx * 2.0, e), Color(UiTheme.ACCENT, 0.55))


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


## Licht von links oben auf einer Zylinderwand: 0 (Schatten) .. 1 (Glanzstreifen).
func _lit(th: float, sharp: float) -> float:
	return pow(maxf(cos(th - 2.05), 0.0), sharp)


## Trommel: Kessel mit Verlauf, Metallreifen mit Glanzstreifen, Spannboecke, helles Fell.
func _draw_drum(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var cx := l.cx(c)
	var rest: bool = _rest[c]
	var edge := COL_HOLD if rest else col
	var on := maxf(g, 1.0 if rest else 0.0)
	# Kontaktschatten auf dem Podest.
	_blob(Vector2(cx + l.rx * 0.05, l.y + l.depth + l.ry * 0.55), Vector2(l.rx * 1.34, l.ry * 1.75), Color(0, 0, 0, 0.78))
	# Kessel: unten leicht verjuengt, waagerechter Lichtverlauf.
	var n := 28
	var hoop := l.depth * 0.20
	var rb := l.rx * 0.955
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var low := PackedVector2Array()
	var lowc := PackedColorArray()
	var hp := PackedVector2Array()
	var hc := PackedColorArray()
	var hlow := PackedVector2Array()
	var hlc := PackedColorArray()
	var inlay := PackedVector2Array()
	var rh := l.rx * 1.022
	for i in n + 1:
		var th := PI - PI * float(i) / float(n)
		var cs := cos(th)
		var sn := sin(th)
		var f := 0.50 + 1.05 * _lit(th, 2.0)
		pts.append(Vector2(cx + l.rx * cs, l.y + l.ry * sn))
		cols.append(Color(COL_SHELL.r * f, COL_SHELL.g * f, COL_SHELL.b * f))
		low.append(Vector2(cx + rb * cs, l.y + l.depth + l.ry * 0.955 * sn))
		lowc.append(Color(COL_SHELL.r * f * 0.55, COL_SHELL.g * f * 0.55, COL_SHELL.b * f * 0.55))
		var hf := 0.42 + 1.55 * _lit(th, 5.0)
		hp.append(Vector2(cx + rh * cs, l.y + l.ry * 1.022 * sn - hoop * 0.15))
		hc.append(Color(COL_METAL.r * hf, COL_METAL.g * hf, COL_METAL.b * hf))
		hlow.append(Vector2(cx + rh * cs, l.y + l.ry * 1.022 * sn + hoop))
		hlc.append(Color(COL_METAL.r * hf * 0.55, COL_METAL.g * hf * 0.55, COL_METAL.b * hf * 0.55))
		inlay.append(Vector2(cx + lerpf(l.rx, rb, 0.62) * cs, l.y + l.depth * 0.62 + l.ry * 0.97 * sn))
	low.reverse()
	lowc.reverse()
	pts.append_array(low)
	cols.append_array(lowc)
	draw_polygon(pts, cols)
	# Zierstreifen in Spaltenfarbe (Hold: Gold).
	draw_polyline(inlay, Color(edge, 0.50 + 0.50 * on), maxf(1.6 * _u, 1.0), true)
	# Spannboecke.
	for th in [2.62, 2.09, 1.571, 1.05, 0.52]:
		var lf := 0.55 + 1.2 * _lit(th, 3.0)
		var lw := maxf(l.rx * 0.045, 2.0)
		var lx: float = cx + l.rx * 0.995 * cos(th)
		var ly: float = l.y + l.ry * sin(th) + hoop
		draw_rect(Rect2(round(lx - lw * 0.5), ly, round(lw), l.depth * 0.34),
				Color(COL_METAL.r * lf * 0.8, COL_METAL.g * lf * 0.8, COL_METAL.b * lf * 0.8))
	# Reifen (vorn) als Band, oben als Ellipse mit Lichtkante hinten.
	hlow.reverse()
	hlc.reverse()
	hp.append_array(hlow)
	hc.append_array(hlc)
	draw_polygon(hp, hc)
	_ell(Vector2(cx, l.y - hoop * 0.15), 0.3)
	draw_circle(Vector2.ZERO, rh, Color(COL_METAL.r * 0.62, COL_METAL.g * 0.62, COL_METAL.b * 0.62), true, -1.0, true)
	draw_arc(Vector2.ZERO, rh - 0.6 * _u, PI * 1.08, PI * 1.92, 40, Color(1.0, 0.97, 0.92, 0.42), 1.2 * _u, true)
	_ell(Vector2(cx, l.y), 0.3)
	# Fell: warmes Grau, Innenlicht, dunkle Fuge zum Reifen, feiner Ring in Spaltenfarbe.
	var head := COL_HEAD.lerp(edge, 0.03 + 0.10 * g + (0.16 if rest else 0.0))
	draw_circle(Vector2.ZERO, l.rx * 0.955, Color(0.030, 0.029, 0.028), true, -1.0, true)
	draw_circle(Vector2.ZERO, l.rx * 0.935, head, true, -1.0, true)
	_blob(Vector2(-l.rx * 0.10, -l.rx * 0.12), Vector2(l.rx * 0.86, l.rx * 0.86), Color(1.0, 0.97, 0.92, 0.075 + 0.05 * g))
	draw_arc(Vector2.ZERO, l.rx * 0.875, 0.0, TAU, 72, Color(edge, 0.20 + 0.70 * on), (1.2 + 0.8 * on) * _u, true)
	_flat()


## Tastenschild in der Frontblende: eingelassene Platte, Leiste in Spaltenfarbe.
func _draw_keycap(l: Lay, c: int) -> void:
	var col := lane_color(c)
	var g: float = _glow[c]
	var fs := int(l.rx * 0.25)
	var txt := str(key_labels[c]) if c < key_labels.size() else ""
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var cx := l.cx(c)
	var edge := COL_HOLD if _rest[c] else col
	var ph := roundf(l.face * 0.56)
	var pw := maxf(ph * 1.5, ts.x + fs * 0.9)
	var plate := Rect2(Vector2(cx - pw * 0.5, l.deck_front + (l.face - ph) * 0.5).round(), Vector2(pw, ph).round())
	var rad := int(round(4.0 * _u))
	_cap_style.set_corner_radius_all(rad)
	_cap_style.set_border_width_all(0)
	# Lichtkante unten (eingelassen), dann die dunkle Platte.
	_cap_style.bg_color = Color(1, 1, 1, 0.10)
	draw_style_box(_cap_style, Rect2(plate.position + Vector2(0, maxf(_u, 1.0)), plate.size))
	_cap_style.bg_color = Color(0.036, 0.035, 0.034).lerp(edge.darkened(0.30), 0.78 * g)
	_cap_style.set_border_width_all(1)
	_cap_style.border_color = Color(0, 0, 0, 0.55).lerp(Color(edge, 0.9), g)
	draw_style_box(_cap_style, plate)
	var bar := maxf(round(2.0 * _u), 2.0)
	draw_rect(Rect2(plate.position.x + rad, plate.end.y - bar - 1.0, plate.size.x - rad * 2.0, bar), Color(edge, 0.80 + 0.20 * g), true)
	draw_string(_font, (plate.get_center() + Vector2(-ts.x * 0.5, fs * 0.34 - bar * 0.5)).round(), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.925, 0.902, 0.855, 0.80 + 0.20 * g))


## Landering + Flugbahn bis zur Landung + Geister-Bogen danach. Hold: doppelter Ring in Gold.
func _draw_target(l: Lay, c: int, b: Dictionary) -> void:
	var arr: Array = flight.segs[c]
	var k := flight.first_landing_at_or_after(c, t_ms)
	if k < 0:
		return
	var s := arr[k] as ReboundFlight.Seg
	var col := COL_HOLD if s.hold else lane_color(c)
	var until := s.t1 - t_ms
	var win := minf(RING_MS, maxf(s.dur(), 120.0))
	var lead := absf(s.t1 - _lead_t) <= 1.5
	if until <= win and until >= -10.0 and b.kind != ReboundFlight.Kind.REST:
		# Gleichmaessig schrumpfend (keine Bremse am Ende): der Moment bleibt ablesbar.
		var q := clampf(1.0 - until / win, 0.0, 1.0)
		var rt := l.ball_r * 1.18
		# Start so weit, dass der Ring auch bei seitlicher Landung auf dem Fell bleibt.
		var rr := lerpf(maxf(l.rx * 0.86 - absf(s.x1) * l.a, rt * 1.5), rt, q)
		var ka := 1.0 if lead else 0.50
		_ell(Vector2(l.cx(c) + s.x1 * l.a, l.y), 0.3)
		# Fester Zielring: darauf schliesst sich der Landering.
		draw_arc(Vector2.ZERO, rt, 0.0, TAU, 48, Color(col, (0.34 + 0.40 * q) * ka), 1.5 * _u, true)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(col.lerp(Color.WHITE, 0.25 * q), (0.40 + 0.60 * q) * ka),
				(1.8 + 1.6 * q) * (1.0 if lead else 0.7) * _u, true)
		if s.hold:
			draw_arc(Vector2.ZERO, rr * 0.80, 0.0, TAU, 48, Color(col, (0.30 + 0.60 * q) * ka), 1.5 * _u, true)
		_flat()
	# Flugbahn: der Rest des laufenden Bogens als feine Linie, zur Landung hin kraeftiger.
	if (b.kind == ReboundFlight.Kind.AIR or b.kind == ReboundFlight.Kind.FALL) and until > 40.0:
		var steps := clampi(int(until / 24.0), 3, 26)
		var pts := PackedVector2Array()
		var pc := PackedColorArray()
		var ac := col.lerp(Color.WHITE, 0.25)
		var ka2 := 0.62 if lead else 0.34
		for i in steps + 1:
			var p := float(i) / float(steps)
			var fb := flight.ball(c, lerpf(t_ms, s.t1, p))
			pts.append(_ball_pos(l, c, fb, 1.0))
			pc.append(Color(ac, ka2 * smoothstep(0.10, 0.75, p)))
		draw_polyline_colors(pts, pc, 1.5 * _u, true)
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
					draw_arc(pos, 2.4 * _u, 0.0, TAU, 10, Color(gc, 0.34 * fade), 1.2 * _u, true)
				else:
					draw_circle(pos, 1.5 * _u, Color(gc, 0.24 * fade), true, -1.0, true)
	# Vorschau-Kette (QA Vorlauf): weitere Landungen bis PREVIEW_MS voraus, auch flache Huepfer
	# schneller Folgen und der Huepfer nach einem liegenden Hold. Ende des Bogens = Landepunkt.
	var pr := flight.preview_range(c, t_ms)
	for j in range(pr.x, pr.y + 1):
		var n2 := arr[j] as ReboundFlight.Seg
		if j == k + 1 and n2.peak > 0.07 and absf(n2.t0 - s.free) < 1.0:
			continue
		var gc2 := COL_HOLD if n2.hold else lane_color(c).lerp(Color.WHITE, 0.3)
		var fade2 := clampf((ReboundFlight.PREVIEW_MS - (n2.t1 - t_ms)) / 200.0, 0.0, 1.0)
		var dots2 := clampi(int(n2.dur() / 28.0), 4, 28)
		for i in range(1, dots2 + 1):
			var p2 := float(i) / float(dots2)
			var h2 := 4.0 * n2.peak * p2 * (1.0 - p2)
			var pos2 := Vector2(l.cx(c) + lerpf(n2.x0, n2.x1, p2) * l.a, l.y - l.ball_r - h2 * l.hpx)
			if i == dots2:
				draw_arc(pos2, 3.4 * _u, 0.0, TAU, 12, Color(gc2, 0.55 * fade2), 1.3 * _u, true)
			else:
				draw_circle(pos2, 1.5 * _u, Color(gc2, 0.24 * fade2), true, -1.0, true)


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
				draw_line(pa, pb, Color(1, 1, 1, 0.26 * q), 2.0 * _u, true)
		prev = c


func _squash(b: Dictionary) -> Vector2:
	var sx := 1.0
	var sy := 1.0
	var kind: int = b.kind
	if kind == ReboundFlight.Kind.REST:
		var ramp := clampf(float(b.since) / 70.0, 0.0, 1.0)
		return Vector2(lerpf(1.0, 1.16, ramp), lerpf(1.0, 0.78, ramp))
	var since: float = b.since
	if since < CONTACT_MS and kind != ReboundFlight.Kind.FALL:
		var s := sin(PI * since / CONTACT_MS) * 0.26
		sy -= s
		sx += s * 0.55
	var until: float = b.until
	if until < 40.0 and kind != ReboundFlight.Kind.EXIT:
		var s2 := (1.0 - until / 40.0) * 0.05
		sy += s2
		sx -= s2 * 0.5
	var sp := clampf(absf(float(b.vy)) * _last_hpx / 1.7, 0.0, 1.0)
	sy += 0.055 * sp
	sx -= 0.035 * sp
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
	# Schatten auf dem Fell: weich, zur Landung kleiner und dunkler.
	var hh := clampf(float(b.h), 0.0, 1.0)
	var sx := l.cx(c) + float(b.x) * l.a
	var sr := R * (1.05 + 0.95 * hh)
	_blob(Vector2(sx + R * 0.10 * hh, l.y + l.ry * 0.04), Vector2(sr, sr * 0.3), Color(0, 0, 0, (0.92 - 0.52 * hh) * float(b.alpha)))
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
				draw_line(prev, tp, Color(col, 0.38 * f * alpha), (2.4 * f + 0.8) * _u, true)
			else:
				draw_line(prev, tp, Color(col, 0.16 * f * alpha), R * 0.70 * f, true)
			prev = tp
	if hold:
		_draw_hold_thread(l, c, b, pos, R * sq.y, col, alpha)
		_draw_ball(pos, R * sq.x, R * sq.y, col, alpha, true)
		if b.kind == ReboundFlight.Kind.REST:
			var rr := R * 1.50
			draw_arc(pos, rr, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 5.0 * _u, true)
			draw_arc(pos, rr, 0.0, TAU, 48, Color(col, 0.28), 3.0 * _u, true)
			draw_arc(pos, rr, -PI * 0.5, -PI * 0.5 + TAU * float(b.p), 48, Color(col.lightened(0.25), 1.0), 3.6 * _u, true)
	else:
		_draw_ball(pos, R * sq.x, R * sq.y, col, alpha, false)


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
	var cap := 5.0 * _u
	draw_line(a, e, Color(col, 0.85 * alpha), 2.6 * _u, true)
	draw_line(e + Vector2(-cap, 0), e + Vector2(cap, 0), Color(col, alpha), 2.6 * _u, true)


## Ball mit Volumen: dunkle Kontur, Koerper, Kugelschatten, weiches Licht, Glanzpunkt,
## Aufhellung unten rechts. Hold: Gold mit dunklem Band (Form, nicht nur Farbe).
func _draw_ball(pos: Vector2, rx: float, ry: float, col: Color, alpha: float, hold: bool) -> void:
	var ratio := ry / maxf(rx, 0.001)
	draw_set_transform(pos, 0.0, Vector2(1.0, ratio))
	var r := rx * 0.93
	draw_circle(Vector2.ZERO, rx, Color(col.darkened(0.72), alpha), true, -1.0, true)
	draw_circle(Vector2.ZERO, r, Color(col, alpha), true, -1.0, true)
	if hold:
		draw_arc(Vector2.ZERO, r * 0.58, 0.0, TAU, 40, Color(col.darkened(0.72), 0.92 * alpha), r * 0.20, true)
	draw_texture_rect(_radial("shade"), Rect2(-r, -r, r * 2.0, r * 2.0), false, Color(1, 1, 1, alpha))
	_blob(Vector2(-r * 0.30, -r * 0.36), Vector2(r * 0.62, r * 0.62), Color(1, 1, 1, 0.50 * alpha))
	draw_circle(Vector2(-r * 0.36, -r * 0.44), r * 0.105, Color(1, 1, 1, 0.88 * alpha), true, -1.0, true)
	draw_arc(Vector2.ZERO, r * 0.88, PI * 0.14, PI * 0.46, 20, Color(col.lightened(0.55), 0.20 * alpha), r * 0.05, true)
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
		var fs := int(size.y * 0.020)
		var txt := tr("wrong key")
		var ts := _body_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := Vector2(l.cx(int(w.col)) - ts.x * 0.5, l.y - l.ball_r * 3.0).round()
		draw_string_outline(_body_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.60 * a))
		draw_string(_body_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_WRONG, a))
	_wrong = keep


func _draw_fx(l: Lay) -> void:
	var keep: Array = []
	var fs := int(size.y * 0.020)
	for fx in _fx:
		var age: float = t_ms - float(fx.t0)
		if age < 0.0 or age > FX_MS:
			continue
		keep.append(fx)
		var c: int = fx.col
		var qi := int(fx.q)
		var jc: Color = JUDGE_COL[clampi(qi, 0, 5)]
		var miss: bool = qi == 5
		var q := age / FX_RING_MS
		_ell(Vector2(l.cx(c), l.y), 0.3)
		if age < 130.0:
			# Fell leuchtet kurz in Wertungsfarbe nach.
			var fl := 1.0 - age / 130.0
			draw_circle(Vector2.ZERO, l.rx * 0.935, Color(jc, (0.05 if miss else 0.20) * fl * fl), true, -1.0, true)
		if q < 1.0:
			# Reifen pulst einmal; im Fell laeuft ein Ring vom Treffpunkt nach aussen (ease-out).
			var e := 1.0 - (1.0 - q) * (1.0 - q)
			draw_arc(Vector2.ZERO, l.rx * (1.022 + (0.0 if miss else 0.05) * e), 0.0, TAU, 72,
					Color(jc, (0.40 if miss else 0.95) * (1.0 - q)), lerpf(3.2, 1.2, q) * _u, true)
			if not miss:
				var hx := clampf(float(fx.x) * l.a, -l.rx * 0.4, l.rx * 0.4)
				var q2 := minf(age / 150.0, 1.0)
				var e2 := 1.0 - pow(1.0 - q2, 3.0)
				draw_arc(Vector2(hx * (1.0 - e2), 0.0), lerpf(l.ball_r * 1.18, l.rx * 0.86, e2), 0.0, TAU, 56,
						Color(jc.lerp(Color.WHITE, 0.3), 0.85 * (1.0 - q2)), lerpf(2.6, 1.0, q2) * _u, true)
		_flat()
		var dt := float(fx.dt)
		if not miss and qi >= 1 and absf(dt) > 0.5:
			# Frueh / spaet: klein, ueber dem Fell hinter dem Reifen.
			var txt := tr("früh") if dt < 0.0 else tr("spät")
			var ts := _body_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var ul := age / FX_MS
			var at := Vector2(l.cx(c) - ts.x * 0.5, l.deck_front - fs * 0.45).round()
			draw_string(_body_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(jc, 0.95 * (1.0 - ul * ul)))
	_fx = keep
