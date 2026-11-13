class_name RallyView
extends Control

## Rally v2: Blick hinter und ueber dem Spieler (ein _draw). Der Tisch laeuft in echter
## Perspektive vom unteren Bildrand weg (eigene Projektion Vector3 -> Bildschirm), Netz in
## der Mitte, Gegner am fernen Ende, deine Haelfte in 4 Zonen. Alles ist eine reine Funktion
## von t_ms + Wertung (RallyCore): Baelle, Ringe und Schlaeger werden jedes Bild aus
## RallyFlight neu berechnet, nichts davon steuert die Wertung.
## Farbe = Zone (tief kuehl -> hoch warm), Schmetterball weiss umrandet und groesser,
## Umriss am Treffpunkt + Ring, der sich bis zur Notenzeit darauf zusammenzieht = WANN,
## Schatten und Aufsetzmarke auf dem Tisch = WO.

const COL_A := Color(0.46, 0.62, 0.88)
const COL_B := Color(0.95, 0.60, 0.34)
const COL_SMASH := Color(0.93, 0.90, 0.85)
const COL_MISS := Color(0.87, 0.44, 0.38)
const ZONE_COLS: Array[Color] = [
	Color(0.46, 0.62, 0.88), Color(0.45, 0.76, 0.72), Color(0.93, 0.79, 0.47), Color(0.95, 0.60, 0.34)]
const COL_ROOM := Color(0.040, 0.040, 0.046)
const COL_TABLE_DARK := Color(0.075, 0.100, 0.135)
const COL_TABLE_LIT := Color(0.190, 0.245, 0.305)
const COL_LIGHT := Color(1.0, 0.93, 0.82)
const COL_LINE := Color(0.925, 0.902, 0.855)
const COL_WOOD := Color(0.78, 0.62, 0.43)

## Kamera: knapp hinter und ueber dem Schlaeger, leicht nach unten geneigt.
const CAM_H := 0.95
const CAM_Z := 1.0
const PITCH_DEG := 20.0
const FOCAL := 1.0
const CY := 0.35
## Tisch in Metern: Halbbreite, Laenge (z 0 = deine Kante, 1 = Gegnerkante).
const HALF_W := 0.7625
const LEN := 2.74
const NET_H := 0.1525
const BALL_R := 0.042
const SMASH_R := 0.0588
const TRAIL_MS := 100.0
const FX_MS := 420.0
const FX_RING_MS := 230.0
const MISS_FLY_MS := 450.0
## Abstand der Rueckwand hinter der Tischkante (m) und Bodenhoehe unter der Platte.
const WALL_Z := 1.8
const FLOOR_Y := -0.76

var beat_ms := 500.0
var shots: Array[RallyChart.Shot] = []
var core: RallyCore
var t_ms := 0.0
## Gehaltene Zonentasten (links nach rechts); der Game-Knoten setzt sie.
var held := [false, false, false, false]
var key_labels := ["D", "F", "J"]
var flight_ms := 800.0

var _fx: Array = []
var _cap: StyleBoxFlat
var _hit_t: Dictionary = {}
var _rel_t: Dictionary = {}
var _u := 1.0
var _lit := [0.0, 0.0, 0.0, 0.0]
var _pulse := [-9999.0, -9999.0, -9999.0, -9999.0]
var _miss := [-9999.0, -9999.0, -9999.0, -9999.0]
var _lvl := 0.0
var _swing_t := -9999.0
var _key_font: Font
var _body_font: Font
var _sinp := 0.0
var _cosp := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key_font = UiTheme.heading_font(2)
	_body_font = UiTheme.body_font()
	_sinp = sin(deg_to_rad(PITCH_DEG))
	_cosp = cos(deg_to_rad(PITCH_DEG))


## Alte Zwei-Tasten-Schnittstelle: 0 = tief (Zone 0), 1 = hoch (Zone 3).
static func key_col(key: int) -> Color:
	return COL_B if key == 1 else COL_A


## Farbe der Zone: 4 Zonen = ganze Palette, 3 Zonen = kuehl, Mitte, warm.
static func zone_col(zone: int) -> Color:
	if RallyFlight.zone_count() == 3:
		return ZONE_COLS[[0, 1, 3][clampi(zone, 0, 2)]]
	return ZONE_COLS[clampi(zone, 0, 3)]


func _n() -> int:
	return RallyFlight.zone_count()


## Linke/rechte Grenze einer Zone (Tischkoordinate x).
func _zx(z: int, shift: float) -> float:
	return -1.0 + 2.0 / float(_n()) * float(z) + shift


func setup(p_shots: Array[RallyChart.Shot], p_core: RallyCore) -> void:
	shots = p_shots
	core = p_core
	if not shots.is_empty() and (shots[0].zones.is_empty() or shots[0].launch == 0.0):
		# Core noch ohne Zonen/Flug: Platzhalter nur in der Ansicht (Chart bleibt unberuehrt).
		RallyFlight.finalize(shots, flight_ms)
	if not shots.is_empty() and shots[0].t - shots[0].launch > 100.0:
		flight_ms = shots[0].t - shots[0].launch


## Wertung eines Schlags: Treffer-Effekt an der Trefferstelle.
func on_judged(idx: int, result: Dictionary) -> void:
	if idx < 0 or idx >= shots.size():
		return
	var s := shots[idx]
	var q := int(result.get("quality", 5))
	var zs := RallyFlight.zones_of(s)
	if q == 5:
		for z in zs:
			_miss[z] = t_ms
		_add_fx("miss", s, t_ms, q, 0.0)
		return
	if bool(result.get("hold_end", false)):
		_rel_t[idx] = t_ms
		_add_fx("release", s, t_ms, q, 0.0)
		return
	_hit_t[idx] = t_ms
	_add_fx("hit", s, t_ms, q, float(result.get("dt", 0.0)))
	_swing_t = t_ms
	for z in zs:
		_pulse[z] = t_ms


func on_charge(idx: int) -> void:
	if idx < 0 or idx >= shots.size():
		return
	var s := shots[idx]
	_hit_t[idx] = t_ms
	_swing_t = t_ms
	for z in RallyFlight.zones_of(s):
		_pulse[z] = t_ms
	_add_fx("hit", s, t_ms, 0, 0.0)


func _add_fx(kind: String, s: RallyChart.Shot, t0: float, q: int = 0, dt: float = 0.0) -> void:
	var zs := RallyFlight.zones_of(s)
	_fx.append({"t0": t0, "kind": kind, "x": RallyFlight.shot_x(s), "smash": s.smash,
			"zone": int(zs[0]), "q": q, "dt": dt})
	while _fx.size() > 16:
		_fx.pop_front()


func reset_fx() -> void:
	_fx.clear()
	_hit_t.clear()
	_rel_t.clear()
	_swing_t = -9999.0
	_pulse = [-9999.0, -9999.0, -9999.0, -9999.0]
	_miss = [-9999.0, -9999.0, -9999.0, -9999.0]


func _process(delta: float) -> void:
	for k in _n():
		var on := 1.0 if (k < held.size() and bool(held[k])) else 0.0
		var cur: float = _lit[k]
		_lit[k] = move_toward(cur, on, delta * (16.0 if on > cur else 6.0))
	var cb := core.combo if core != null else 0
	var target := 3.0 if cb >= 200 else (2.0 if cb >= 100 else (1.0 if cb >= 50 else 0.0))
	_lvl = move_toward(_lvl, target, delta * 1.2)
	queue_redraw()


# ---------------------------------------------------------------------------
# Projektion
# ---------------------------------------------------------------------------

## Tischkoordinaten (x -1..1, y Meter, z 0..1) -> Meter-Welt.
func _w(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * HALF_W, y, z * LEN)


## Welt (Meter) -> Vector3(Bildschirm x, y, Tiefe).
func _cam(w: Vector3) -> Vector3:
	var dy := w.y - CAM_H
	var dz := w.z + CAM_Z
	var zc := maxf(-dy * _sinp + dz * _cosp, 0.12)
	var yc := dy * _cosp + dz * _sinp
	var f := FOCAL * size.y
	return Vector3(size.x * 0.5 + f * w.x / zc, size.y * CY - f * yc / zc, zc)


func _pp(w: Vector3) -> Vector2:
	var c := _cam(w)
	return Vector2(c.x, c.y)


## Pixel je Meter an dieser Stelle.
func _sc(w: Vector3) -> float:
	return FOCAL * size.y / _cam(w).z


func _draw() -> void:
	if shots.is_empty() or size.x < 10.0:
		return
	_u = size.y / 720.0
	_draw_room()
	_draw_table()
	_draw_zones()
	_draw_charge_bands()
	_draw_landings()
	var balls := _collect_balls()
	_draw_shadows(balls)
	_draw_opponent()
	_draw_net()
	# Schlaeger hinter Umriss und Ball: er faengt, verdeckt aber nichts.
	_draw_player()
	_draw_targets()
	# Alle Baelle nach dem Netz: nie vom Netz ueberdeckt.
	for b in balls:
		_draw_ball(b)
	_draw_fx()
	_draw_keys()


func _blob(center: Vector2, half: Vector2, col: Color) -> void:
	draw_texture_rect(ReboundView._radial("soft"), Rect2(center - half, half * 2.0), false, col)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), col)


func _quad_g(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color) -> void:
	draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([ca, ca, cb, cb]))


func _ground_ring(cx: float, cz: float, r: float, col: Color, width: float, fill: float = 0.0) -> void:
	var n := 28
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(_pp(Vector3(cx + cos(a) * r, 0.002, cz + sin(a) * r)))
	if fill > 0.0:
		draw_colored_polygon(pts, Color(col, col.a * fill))
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)


# ---------------------------------------------------------------------------
# Raum: dunkel, ruhig, weiches Licht ueber dem Tisch, Publikum im Halbdunkel
# ---------------------------------------------------------------------------

func _draw_room() -> void:
	var w := size.x
	var h := size.y
	# Raum: Rueckwand und Boden, das Map-Bild scheint nur als Farbhauch durch.
	var zw := LEN + WALL_Z
	var hz: float = _pp(Vector3(0.0, FLOOR_Y, zw)).y
	var wt := Color(0.046, 0.045, 0.044, 0.88)
	var wb := Color(0.092, 0.089, 0.084, 0.92)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, hz), Vector2(0, hz)]),
			PackedColorArray([wt, wt, wb, wb]))
	# Wandfelder: feine senkrechte Fugen, perspektivisch richtig verteilt.
	for i in range(-6, 7):
		var fx := (float(i) + 0.5) * 1.25
		var fa := _pp(Vector3(fx, FLOOR_Y, zw))
		if fa.x < 0.0 or fa.x > w:
			continue
		draw_polyline_colors(PackedVector2Array([Vector2(roundf(fa.x) + 0.5, 0.0), Vector2(roundf(fa.x) + 0.5, hz)]),
				PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.07)]), 1.0)
	var ft := Color(0.118, 0.113, 0.106, 0.96)
	var fb := Color(0.040, 0.039, 0.038, 0.98)
	draw_polygon(PackedVector2Array([Vector2(0, hz), Vector2(w, hz), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([ft, ft, fb, fb]))
	# Sockelleiste.
	var sk := maxf(roundf(3.0 * _u), 2.0)
	draw_rect(Rect2(0, roundf(hz) - sk, w, sk), Color(0.135, 0.130, 0.122))
	draw_rect(Rect2(0, roundf(hz) - sk, w, 1.0), Color(1, 1, 1, 0.10))
	# Leuchte ueber dem Tisch: schmale Schiene, leiser Lichtkegel auf die Platte.
	var boost := 1.0 + 0.10 * _lvl
	var lx := w * 0.5
	var ly := roundf(h * 0.098)
	var lw := h * 0.30
	var c0 := Color(COL_LIGHT, 0.030 * boost)
	var c1 := Color(COL_LIGHT, 0.0)
	draw_polygon(PackedVector2Array([Vector2(lx - lw, ly), Vector2(lx + lw, ly), Vector2(lx + lw * 2.6, h * 0.86), Vector2(lx - lw * 2.6, h * 0.86)]),
			PackedColorArray([c0, c0, c1, c1]))
	var lh := maxf(roundf(5.0 * _u), 3.0)
	for sgn in [-1.0, 1.0]:
		var hx: float = roundf(lx + lw * 0.72 * sgn) + 0.5
		draw_line(Vector2(hx, 0.0), Vector2(hx, ly - lh), Color(1, 1, 1, 0.13), 1.0)
	draw_rect(Rect2(lx - lw, ly - lh, lw * 2.0, lh), Color(0.150, 0.146, 0.138))
	draw_rect(Rect2(lx - lw, ly - lh, lw * 2.0, 1.0), Color(1, 1, 1, 0.14))
	draw_rect(Rect2(lx - lw + lh, ly - maxf(roundf(2.0 * _u), 1.0), (lw - lh) * 2.0, maxf(roundf(2.0 * _u), 1.0)), Color(COL_LIGHT, 0.88))
	# Weicher Schatten des Tisches am Boden.
	var sc := _pp(_w(0.0, FLOOR_Y, 0.42))
	_blob(sc, Vector2(w * 0.50, h * 0.17), Color(0, 0, 0, 0.72))
	# Vignette: weich von den Seiten, keine harte Kante.
	var vg := Color(0, 0, 0, 0.36)
	var v0 := Color(0, 0, 0, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.30, 0), Vector2(w * 0.30, h), Vector2(0, h)]),
			PackedColorArray([vg, v0, v0, vg]))
	draw_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w * 0.70, 0), Vector2(w * 0.70, h), Vector2(w, h)]),
			PackedColorArray([vg, v0, v0, vg]))


# ---------------------------------------------------------------------------
# Tisch
# ---------------------------------------------------------------------------

func _table_col(x: float, z: float) -> Color:
	## x -1..1, z 0..1 -> Farbe der Platte unter dem Licht ueber der Tischmitte.
	var lx := x / 1.15
	var lz := (z - 0.55) / 0.85
	var l := exp(-(lx * lx + lz * lz) * 1.15) * (1.0 + 0.12 * _lvl)
	return COL_TABLE_DARK.lerp(COL_TABLE_LIT, clampf(l, 0.0, 1.0))


func _draw_table() -> void:
	var nx := 8
	var nz := 14
	for iz in nz:
		var z0 := float(iz) / float(nz)
		var z1 := float(iz + 1) / float(nz)
		for ix in nx:
			var x0 := -1.0 + 2.0 * float(ix) / float(nx)
			var x1 := -1.0 + 2.0 * float(ix + 1) / float(nx)
			draw_polygon(PackedVector2Array([_pp(_w(x0, 0, z0)), _pp(_w(x1, 0, z0)),
					_pp(_w(x1, 0, z1)), _pp(_w(x0, 0, z1))]),
					PackedColorArray([_table_col(x0, z0), _table_col(x1, z0),
					_table_col(x1, z1), _table_col(x0, z1)]))
	# Zarge (Vorderkante mit Dicke) und seitliche Kanten.
	var a := _pp(_w(-1, 0, 0))
	var b := _pp(_w(1, 0, 0))
	var a2 := _pp(_w(-0.985, -0.062, 0))
	var b2 := _pp(_w(0.985, -0.062, 0))
	_quad_g(a, b, b2, a2, COL_TABLE_DARK.lightened(0.10), COL_TABLE_DARK.darkened(0.55))
	draw_line(a2, b2, Color(0, 0, 0, 0.55), 1.0 * _u, true)
	draw_line(a, b, Color(COL_LINE, 0.62), 1.8 * _u, true)
	var af := _pp(_w(-1, 0, 1))
	var bf := _pp(_w(1, 0, 1))
	draw_line(af, bf, Color(COL_LINE, 0.26), 1.0 * _u, true)
	draw_line(a, af, Color(COL_LINE, 0.40), 1.4 * _u, true)
	draw_line(b, bf, Color(COL_LINE, 0.40), 1.4 * _u, true)
	# Mittellinie lang (Doppel-Linie des Tisches), sehr fein.
	draw_line(_pp(_w(0, 0, 0)), _pp(_w(0, 0, 1)), Color(COL_LINE, 0.07), 1.0, true)


func _draw_net() -> void:
	var ex := 1.07
	var b0 := _pp(_w(-ex, 0.0, 0.5))
	var b1 := _pp(_w(ex, 0.0, 0.5))
	var t0 := _pp(Vector3(-ex * HALF_W, NET_H, 0.5 * LEN))
	var t1 := _pp(Vector3(ex * HALF_W, NET_H, 0.5 * LEN))
	# Schatten des Netzes auf der Platte (zur Spielerseite).
	_quad_g(_pp(_w(-1, 0.001, 0.5)), _pp(_w(1, 0.001, 0.5)), _pp(_w(1, 0.001, 0.468)), _pp(_w(-1, 0.001, 0.468)),
			Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.0))
	_quad(b0, b1, t1, t0, Color(0.78, 0.82, 0.88, 0.10))
	var nv := 30
	for i in range(1, nv):
		var f := float(i) / float(nv)
		draw_line(b0.lerp(b1, f), t0.lerp(t1, f), Color(0.85, 0.88, 0.92, 0.10), 1.0)
	for i in range(1, 5):
		var g := float(i) / 5.0
		draw_line(b0.lerp(t0, g), b1.lerp(t1, g), Color(0.85, 0.88, 0.92, 0.07), 1.0)
	# Netzband oben: helles Band mit Schattenkante.
	var tape := maxf(3.0 * _u, 2.0)
	_quad(t0, t1, t1 + Vector2(0, tape), t0 + Vector2(0, tape), Color(COL_LINE, 0.86))
	draw_line(t0 + Vector2(0, tape + 0.5), t1 + Vector2(0, tape + 0.5), Color(0, 0, 0, 0.35), 1.0)
	# Pfosten: Metall mit Lichtkante links.
	var pw := maxf(0.016 * _sc(_w(ex, 0, 0.5)), 3.0)
	for pq in [[b0, t0], [b1, t1]]:
		var pb: Vector2 = pq[0]
		var pt: Vector2 = pq[1]
		draw_line(pb + Vector2(0, pw * 0.5), pt - Vector2(0, pw * 0.4), Color(0.30, 0.31, 0.33), pw, true)
		draw_line(pb + Vector2(-pw * 0.25, pw * 0.5), pt + Vector2(-pw * 0.25, -pw * 0.4), Color(0.72, 0.73, 0.75, 0.85), maxf(pw * 0.25, 1.0), true)


# ---------------------------------------------------------------------------
# Zonen, Aufladen-Band, Landeringe
# ---------------------------------------------------------------------------

func _zone_quad(z: int, z0: float, z1: float, inset: float, col: Color, col_far: Color) -> void:
	var xa := _zx(z, inset)
	var xb := _zx(z + 1, -inset)
	_quad_g(_pp(_w(xa, 0.001, z0)), _pp(_w(xb, 0.001, z0)), _pp(_w(xb, 0.001, z1)),
			_pp(_w(xa, 0.001, z1)), col, col_far)


func _draw_zones() -> void:
	for z in _n():
		var col := zone_col(z)
		var pulse := clampf(1.0 - (t_ms - float(_pulse[z])) / 220.0, 0.0, 1.0)
		var miss := clampf(1.0 - (t_ms - float(_miss[z])) / 320.0, 0.0, 1.0)
		var lit: float = _lit[z]
		var a := 0.055 + 0.15 * lit + 0.10 * pulse * pulse
		# Zone auf deiner Haelfte: vorn kraeftiger, zur Mitte hin auslaufend.
		_zone_quad(z, 0.0, 0.5, 0.012, Color(col, a), Color(col, a * 0.20))
		if miss > 0.0:
			_zone_quad(z, 0.0, 0.5, 0.012, Color(COL_MISS, 0.14 * miss), Color(COL_MISS, 0.02 * miss))
		# Vorderkante in Zonenfarbe: die Schlaglinie.
		var xa := _zx(z, 0.012)
		var xb := _zx(z + 1, -0.012)
		draw_line(_pp(_w(xa, 0.001, 0.0)), _pp(_w(xb, 0.001, 0.0)), Color(col, 0.55 + 0.45 * lit),
				(2.0 + 1.0 * lit) * _u, true)
	# Feine Trennlinien.
	for i in _n() + 1:
		var x := _zx(i, 0.0)
		var ea := 0.14 if (i == 0 or i == _n()) else 0.09
		draw_line(_pp(_w(x, 0.001, 0.0)), _pp(_w(x, 0.001, 0.5)), Color(COL_LINE, ea), 1.0, true)


func _draw_keys() -> void:
	var fs := int(size.y * 0.026)
	for z in _n():
		var col := zone_col(z)
		var lit: float = _lit[z]
		var c := _pp(_w((_zx(z, 0.0) + _zx(z + 1, 0.0)) * 0.5, -0.034, 0.0))
		var half := Vector2(size.y * 0.034, size.y * 0.024)
		var rc := Rect2((c - half + Vector2(0, size.y * 0.016)).round(), (half * 2.0).round())
		# Tastenplatte: weicher Schatten, abgerundete dunkle Platte mit Lichtkante oben,
		# Zonenfarbe nur als Leiste unten und beim Druecken.
		if _cap == null:
			_cap = StyleBoxFlat.new()
			_cap.anti_aliasing = true
		var rad := int(round(4.0 * _u))
		_cap.set_corner_radius_all(rad)
		_cap.set_border_width_all(0)
		_cap.bg_color = Color(0, 0, 0, 0.45)
		draw_style_box(_cap, Rect2(rc.position + Vector2(0, maxf(2.0 * _u, 1.0)), rc.size))
		_cap.bg_color = Color(0.105, 0.102, 0.098).lerp(col.darkened(0.30), 0.78 * lit)
		_cap.set_border_width_all(1)
		_cap.border_color = Color(1, 1, 1, 0.13).lerp(Color(col, 0.9), lit)
		draw_style_box(_cap, rc)
		draw_rect(Rect2(rc.position.x + rad, rc.position.y + 1.0, rc.size.x - rad * 2.0, 1.0), Color(1, 1, 1, 0.10))
		var bar := maxf(round(2.0 * _u), 2.0)
		draw_rect(Rect2(rc.position.x + rad, rc.end.y - bar - 1.0, rc.size.x - rad * 2.0, bar), Color(col, 0.85 + 0.15 * lit), true)
		var txt: String = str(key_labels[z]) if z < key_labels.size() else ""
		var ts := _key_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_key_font, (rc.get_center() + Vector2(-ts.x * 0.5, fs * 0.34 - bar * 0.5)).round(), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_LINE, 0.74 + 0.26 * lit))


func _draw_charge_bands() -> void:
	## Laufband: Aufladen-Note als Streifen in der Zone, der auf dich zu laeuft.
	var j := RallyChart.first_at_or_after(shots, t_ms - 200.0)
	var jmax := RallyChart.first_at_or_after(shots, t_ms + flight_ms)
	var list: Array[int] = []
	if core != null and core.charging >= 0 and core.charging < j:
		list.append(core.charging)
	for k in range(j, jmax):
		list.append(k)
	for k in list:
		var s := shots[k]
		if not s.is_charge():
			continue
		var za := clampf((s.t - t_ms) / flight_ms, 0.0, 0.5)
		var zb := clampf((s.end - t_ms) / flight_ms, 0.0, 0.5)
		if zb <= za + 0.002:
			continue
		var held_on := core != null and core.is_charging(k)
		for z in RallyFlight.zones_of(s):
			var col := zone_col(z)
			var al := 0.42 if held_on else 0.26
			_zone_quad(z, za, zb, 0.07, Color(col, al * 0.55), Color(col, al))
			var xa := _zx(z, 0.07)
			var xb := _zx(z + 1, -0.07)
			draw_line(_pp(_w(xa, 0.002, za)), _pp(_w(xa, 0.002, zb)), Color(col, 0.55), 1.2, true)
			draw_line(_pp(_w(xb, 0.002, za)), _pp(_w(xb, 0.002, zb)), Color(col, 0.55), 1.2, true)
			draw_line(_pp(_w(xa, 0.002, zb)), _pp(_w(xb, 0.002, zb)), Color(col, 0.75), 1.6, true)


func _draw_landings() -> void:
	## Aufsetzpunkt: nur eine feste, leise Marke (WO der Ball aufspringt). Das WANN zeigt
	## allein der Ring am Treffpunkt (_draw_targets), nichts hier schrumpft.
	var j := RallyChart.first_at_or_after(shots, t_ms)
	var jmax := RallyChart.first_at_or_after(shots, t_ms + flight_ms + 1.0)
	var cz := RallyFlight.Z_LAND * LEN
	for k in range(j, jmax):
		var s := shots[k]
		if s.launch > t_ms:
			continue
		var land := RallyFlight.landing_time(s)
		if t_ms >= land:
			continue
		var vis := clampf((t_ms - s.launch) / 120.0, 0.0, 1.0) * clampf((land - t_ms) / 80.0, 0.0, 1.0)
		var col := COL_SMASH if s.smash else zone_col(int(RallyFlight.zones_of(s)[0]))
		_ground_ring(RallyFlight.shot_x(s) * HALF_W, cz, 0.034 * (1.3 if s.smash else 1.0),
				Color(col, 0.30 * vis), 1.2 * _u, 0.30)


# ---------------------------------------------------------------------------
# Baelle
# ---------------------------------------------------------------------------

func _result_hit(k: int) -> int:
	## 1 = getroffen (oder Aufladen laeuft), 0 = Fehlschlag, -1 = noch offen.
	if core == null:
		return -1
	if core.is_charging(k):
		return 1
	var r: Dictionary = core.result_of(k)
	if r.is_empty() or bool(r.get("pending", false)):
		return -1
	return 0 if int(r.get("quality", 5)) == 5 else 1


func _ball_col(s: RallyChart.Shot) -> Color:
	if s.smash:
		return COL_SMASH
	return zone_col(int(RallyFlight.zones_of(s)[0]))


## Alle sichtbaren Baelle als Liste {P (Tischkoord.), col, rad, a, smash, trail, kind, s, k},
## ferne zuerst.
func _collect_balls() -> Array:
	var out: Array = []
	var T := t_ms
	var j := RallyChart.first_at_or_after(shots, T - 1000.0)
	var jmax := RallyChart.first_at_or_after(shots, T + flight_ms + 1.0)
	var idxs: Array[int] = []
	if core != null and core.charging >= 0 and core.charging < j:
		idxs.append(core.charging)
	for k in range(j, jmax):
		idxs.append(k)
	for k in idxs:
		var s := shots[k]
		var res := _result_hit(k)
		var hit_t: float = float(_hit_t.get(k, s.t))
		var col := _ball_col(s)
		var rad := SMASH_R if s.smash else BALL_R
		var returned := false
		if res == 1:
			# Aufladen: Ball haengt am Schlaeger, Ring fuellt sich.
			if s.is_charge() and T > hit_t and (core.is_charging(k) or T <= s.end):
				var hp := Vector3(RallyFlight.shot_x(s), RallyFlight.Y_RACKET, 0.0)
				out.append({"P": hp, "col": col, "rad": rad * 1.15, "a": 1.0, "smash": false,
						"trail": false, "kind": "held", "s": s, "k": k})
				continue
			var ret_t: float = float(_rel_t.get(k, s.end)) if s.is_charge() else hit_t
			if T >= ret_t:
				returned = true
				var dt := T - ret_t
				if dt <= RallyFlight.RETURN_MS:
					var from := RallyFlight.ball_pos(s, minf(ret_t, s.t))
					from.z = maxf(from.z, 0.0)
					if s.is_charge():
						from = Vector3(RallyFlight.shot_x(s), RallyFlight.Y_RACKET, 0.0)
					var rp := RallyFlight.return_pos(from, dt)
					var fa := clampf(1.0 - dt / RallyFlight.RETURN_MS, 0.0, 1.0)
					out.append({"P": rp, "col": col, "rad": rad * (1.0 - 0.25 * dt / RallyFlight.RETURN_MS),
							"a": 0.55 * fa, "smash": false, "trail": false, "kind": "return", "s": s, "k": k})
		if returned or T < s.launch:
			continue
		# Anflug (bei Treffer endet er mit dem Treffer, bei Fehlschlag fliegt er vorbei).
		if res == 1 and T >= hit_t:
			continue
		var a := 1.0
		if T > s.t:
			a = clampf(1.0 - (T - s.t) / MISS_FLY_MS, 0.0, 1.0)
			a *= a
			if a <= 0.0:
				continue
		var vis := clampf((T - s.launch) / 70.0, 0.0, 1.0)
		out.append({"P": RallyFlight.ball_pos(s, T), "col": col, "rad": rad, "a": a * vis,
				"smash": s.smash, "trail": true, "kind": "in", "s": s, "k": k})
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.P.z) > float(q.P.z))
	return out


func _draw_shadows(balls: Array) -> void:
	for b in balls:
		if str(b.kind) == "held":
			continue
		var P: Vector3 = b.P
		if P.z < 0.0 or P.z > 1.0 or absf(P.x) > 1.0:
			continue
		var rad := float(b.rad)
		var hgt := clampf(P.y / 0.7, 0.0, 1.0)
		var al := float(b.a) * (0.80 - 0.42 * hgt)
		var cx := P.x * HALF_W
		var cz := P.z * LEN
		var r := rad * (1.45 + 0.75 * hgt)
		# Weicher Schatten auf der Platte: am Boden klein und dunkel, in der Hoehe weit und blass.
		var ctr := _pp(Vector3(cx, 0.002, cz))
		var ex: float = absf(_pp(Vector3(cx + r, 0.002, cz)).x - ctr.x)
		var ey: float = absf(_pp(Vector3(cx, 0.002, cz + r)).y - ctr.y)
		_blob(ctr, Vector2(ex, maxf(ey, 1.0)), Color(0, 0, 0, al))


func _draw_ball(b: Dictionary) -> void:
	var P: Vector3 = b.P
	var rad := float(b.rad)
	var al := float(b.a)
	if al <= 0.01:
		return
	var col: Color = b.col
	var cm := _cam(_w(P.x, P.y + rad, P.z))
	var p := Vector2(cm.x, cm.y)
	var r := rad * FOCAL * size.y / cm.z
	var far := clampf((P.z - 0.35) / 0.65, 0.0, 1.0)
	# Tiefe: ferne Baelle einen Hauch heller, Zonenfarbe bleibt lesbar.
	var c := col.lerp(Color(1, 1, 1), 0.16 * far)
	var s: RallyChart.Shot = b.s
	if str(b.kind) == "in":
		# Spur: schmal, laeuft spitz aus.
		var step := 7
		var prev := p
		for i in range(1, step + 1):
			var tt := t_ms - TRAIL_MS * float(i) / float(step)
			if tt < s.launch:
				break
			var q := RallyFlight.ball_pos(s, tt)
			var cq := _cam(_w(q.x, q.y + rad, q.z))
			var pq := Vector2(cq.x, cq.y)
			var f := 1.0 - float(i) / float(step + 1)
			draw_line(prev, pq, Color(c, 0.30 * f * al), maxf(r * 1.25 * f, 1.0), true)
			prev = pq
	if bool(b.smash):
		draw_arc(p, r + maxf(r * 0.18, 2.0), 0.0, TAU, 40, Color(COL_SMASH, 0.95 * al), maxf(r * 0.10, 1.6), true)
	if str(b.kind) == "held":
		var k: int = b.k
		var h0: float = float(_hit_t.get(k, s.t))
		var prog := clampf((t_ms - h0) / maxf(s.end - h0, 1.0), 0.0, 1.0)
		var rr := r * 1.70
		draw_arc(p, rr, 0.0, TAU, 48, Color(c, 0.22), 2.0 * _u, true)
		draw_arc(p, rr, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(c, 0.95), 3.0 * _u, true)
	# Kugel: dunkle Kontur, Koerper, Schattierung (Licht oben links), weiches Licht, Glanzpunkt.
	var ri := maxf(r * 0.92, r - 2.0 * _u)
	draw_circle(p, r, Color(c.darkened(0.70), al), true, -1.0, true)
	draw_circle(p, ri, Color(c, al), true, -1.0, true)
	draw_texture_rect(ReboundView._radial("shade"), Rect2(p - Vector2(ri, ri), Vector2(ri, ri) * 2.0), false, Color(1, 1, 1, al))
	_blob(p + Vector2(-ri * 0.30, -ri * 0.36), Vector2(ri * 0.62, ri * 0.62), Color(1, 1, 1, 0.46 * al))
	if ri > 5.0:
		draw_circle(p + Vector2(-ri * 0.36, -ri * 0.44), ri * 0.105, Color(1, 1, 1, 0.85 * al), true, -1.0, true)


# ---------------------------------------------------------------------------
# Schlaeger
# ---------------------------------------------------------------------------

func _rot(v: Vector2, ang: float) -> Vector2:
	var ca := cos(ang)
	var sa := sin(ang)
	return Vector2(v.x * ca - v.y * sa, v.x * sa + v.y * ca)


func _blade(c: Vector2, rx: float, ry: float, ang: float, rubber: Color, edge: Color, handle: float) -> void:
	var n := 40
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var v := Vector2(cos(a) * rx, sin(a) * ry)
		outer.append(c + _rot(v, ang))
		inner.append(c + _rot(v * 0.86, ang))
	# Griff.
	var gw := rx * 0.17
	var top := ry * 0.86
	var grip := PackedVector2Array([
		c + _rot(Vector2(-gw, top), ang), c + _rot(Vector2(gw, top), ang),
		c + _rot(Vector2(gw * 1.15, top + handle), ang), c + _rot(Vector2(-gw * 1.15, top + handle), ang)])
	draw_colored_polygon(grip, COL_WOOD.darkened(0.42))
	draw_polyline(grip, Color(0, 0, 0, 0.55), 1.0 * _u, true)
	draw_colored_polygon(outer, COL_WOOD.darkened(0.55))
	var oc := outer.duplicate()
	oc.append(outer[0])
	draw_polyline(oc, Color(0, 0, 0, 0.60), 1.2 * _u, true)
	draw_colored_polygon(inner, rubber)
	_blob(c + _rot(Vector2(-rx * 0.22, -ry * 0.26), ang), Vector2(rx * 0.62, ry * 0.62), Color(1, 1, 1, 0.07))
	var hl := PackedVector2Array()
	for i in 14:
		var a2 := PI * 1.08 + PI * 0.52 * float(i) / 13.0
		hl.append(c + _rot(Vector2(cos(a2) * rx * 0.74, sin(a2) * ry * 0.74), ang))
	draw_polyline(hl, Color(1, 1, 1, 0.16), 1.4 * _u, true)
	var closed := inner.duplicate()
	closed.append(inner[0])
	draw_polyline(closed, Color(edge, 0.42), 1.2 * _u, true)


func _player_x() -> float:
	var T := t_ms
	var j := RallyChart.first_at_or_after(shots, T - 60.0)
	if core != null and core.charging >= 0:
		return RallyFlight.shot_x(shots[core.charging])
	if j >= shots.size():
		return RallyFlight.shot_x(shots[shots.size() - 1])
	var tgt := RallyFlight.shot_x(shots[j])
	var prev := 0.0
	var span := 420.0
	if j > 0:
		var gap := shots[j].t - shots[j - 1].end
		if gap < 1500.0:
			prev = RallyFlight.shot_x(shots[j - 1])
			span = clampf(gap * 0.75, 50.0, 230.0)
	var u := clampf(1.0 - (shots[j].t - T) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	return lerpf(prev, tgt, u)


func _draw_player() -> void:
	var px := _player_x()
	var sw := clampf((t_ms - _swing_t) / 150.0, 0.0, 1.0)
	var sv := sin(PI * sw) if sw < 1.0 else 0.0
	var wind := 0.0
	var jn := RallyChart.first_at_or_after(shots, t_ms - 60.0)
	if jn < shots.size() and sw >= 1.0:
		var lead := shots[jn].t - t_ms
		if lead > 0.0 and lead < 220.0:
			wind = sin(PI * 0.5 * (1.0 - lead / 220.0))
	# Blatt genau am Treffpunkt (hinter dem Umriss); Schwung nach vorn, Ausholen leicht zurueck.
	var wp := Vector3(px * HALF_W, RallyFlight.Y_RACKET + BALL_R + 0.02 * sv, 0.10 * sv - 0.03 * wind)
	var cm := _cam(wp)
	var pxm := FOCAL * size.y / cm.z
	var zc := zone_col(clampi(int(round((px + 1.0) * float(_n()) * 0.5 - 0.5)), 0, _n() - 1))
	# Schatten des Schlaegers auf der Tischkante.
	_blob(_pp(Vector3(px * HALF_W, 0.002, 0.03)), Vector2(0.085 * pxm, 0.018 * pxm), Color(0, 0, 0, 0.55))
	_blade(Vector2(cm.x, cm.y), 0.066 * pxm, 0.062 * pxm, 0.10 - 0.25 * sv + 0.10 * wind,
			Color(0.115, 0.105, 0.105).lerp(zc, 0.10), zc, 0.08 * pxm)


func _draw_opponent() -> void:
	var T := t_ms
	var j := RallyChart.first_at_or_after(shots, T + flight_ms - 140.0)
	var x := 0.0
	var swing := 0.0
	if j < shots.size():
		var tx := RallyFlight.launch_x(shots[j])
		var prev := 0.0
		var span := 300.0
		if j > 0:
			prev = RallyFlight.launch_x(shots[j - 1])
			span = clampf((shots[j].launch - shots[j - 1].launch) * 0.8, 40.0, 260.0)
		var u := clampf(1.0 - (shots[j].launch - T) / span, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		x = lerpf(prev, tx, u)
	elif not shots.is_empty():
		x = RallyFlight.launch_x(shots[shots.size() - 1])
	# Schwung: 150 ms nach dem Gegnerschlag (bei Streams der juengste Ball).
	var k := RallyChart.first_at_or_after(shots, T + flight_ms - 150.0)
	for q in range(maxi(k - 1, 0), mini(k + 1, shots.size())):
		var e := (T - shots[q].launch) / 150.0
		if e >= 0.0 and e <= 1.0:
			swing = maxf(swing, sin(PI * e))
	var wp := Vector3(x * HALF_W * 1.1, 0.24 + 0.02 * swing, LEN + 0.12 - 0.20 * swing)
	var cm := _cam(wp)
	var pxm := FOCAL * size.y / cm.z
	_blade(Vector2(cm.x, cm.y), 0.085 * pxm, 0.078 * pxm, -0.10 - 0.35 * swing,
			Color(0.20, 0.10, 0.10), Color(0.62, 0.66, 0.74), 0.10 * pxm)


# ---------------------------------------------------------------------------
# Effekte (kurz, dezent)
# ---------------------------------------------------------------------------

func _draw_fx() -> void:
	var keep: Array = []
	var fs := int(size.y * 0.020)
	for f in _fx:
		var age := t_ms - float(f.t0)
		if age < 0.0:
			keep.append(f)
			continue
		if age > FX_MS:
			continue
		keep.append(f)
		var smash := bool(f.smash)
		var rad := SMASH_R if smash else BALL_R
		var cm := _hit_c(float(f.x), rad)
		var p := Vector2(cm.x, cm.y)
		var r := rad * FOCAL * size.y / cm.z
		var col := zone_col(int(f.zone))
		var kind := str(f.kind)
		var ul := age / FX_MS
		if kind == "miss":
			# Fehlschlag: kleines, mattes Kreuz am Treffpunkt, kein Blitz.
			var am := (1.0 - ul) * (1.0 - ul)
			var d := r * 0.50
			draw_line(p + Vector2(-d, -d), p + Vector2(d, d), Color(COL_MISS, 0.85 * am), 2.0 * _u, true)
			draw_line(p + Vector2(-d, d), p + Vector2(d, -d), Color(COL_MISS, 0.85 * am), 2.0 * _u, true)
			continue
		var q := int(f.q)
		var u := age / FX_RING_MS
		if u < 1.0:
			# Ein sauberer Ring, der kurz aufgeht; schwaechere Wertung = leiser.
			var e := 1.0 - pow(1.0 - u, 3.0)
			var strong := 1.0 if q <= 1 else (0.70 if q == 2 else 0.45)
			var hot := col.lerp(Color.WHITE, 0.35)
			if kind == "hit":
				draw_circle(p, r, Color(hot, 0.34 * strong * (1.0 - u) * (1.0 - u)))
			draw_arc(p, r * (1.0 + (0.85 if smash else 0.60) * e), 0.0, TAU, 48,
					Color(hot, 0.90 * strong * (1.0 - u)), lerpf(2.6, 1.0, u) * _u, true)
			if smash:
				draw_arc(p, r * (1.30 + 1.0 * e), 0.0, TAU, 48, Color(COL_SMASH, 0.55 * (1.0 - u)), 1.4 * _u, true)
		var dt := float(f.dt)
		if kind == "hit" and q >= 1 and absf(dt) > 0.5:
			# Frueh / spaet: klein, direkt ueber dem Treffpunkt.
			var txt := tr("früh") if dt < 0.0 else tr("spät")
			var ts := _body_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var la := 1.0 - ul * ul
			var at := (p + Vector2(-ts.x * 0.5, -r * 1.75 - 4.0 * _u * ul)).round()
			draw_string_outline(_body_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.55 * la))
			draw_string(_body_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_LINE, 0.90 * la))
	_fx = keep


## Bildschirmpunkt (x, y, Tiefe) der Ballmitte im Treffmoment.
func _hit_c(x: float, rad: float) -> Vector3:
	return _cam(_w(x, RallyFlight.Y_RACKET + rad, 0.0))


## Treffpunkte: je Zone ein fester Umriss in Ballgroesse ueber der Schlaglinie. Der Ball
## fliegt genau in diesen Umriss, ein Ring zieht sich bis zur Notenzeit darauf zusammen.
## Rangfolge: naechster Schlag kraeftig, folgende duenn und erst ab einer Beat-Laenge.
func _draw_targets() -> void:
	var T := t_ms
	for z in _n():
		var cz := _hit_c(RallyFlight.zone_x(z), BALL_R)
		var rz := BALL_R * FOCAL * size.y / cz.z
		draw_arc(Vector2(cz.x, cz.y), rz, 0.0, TAU, 40, Color(zone_col(z), 0.20 + 0.25 * float(_lit[z])),
				1.2 * _u, true)
	var j := RallyChart.first_at_or_after(shots, T - 60.0)
	var jmax := RallyChart.first_at_or_after(shots, T + flight_ms + 1.0)
	var near := clampf(beat_ms, 200.0, flight_ms)
	var lead_t := -1.0
	for k in range(j, jmax):
		var s := shots[k]
		if _result_hit(k) != -1 or T < s.launch:
			continue
		var until := s.t - T
		if lead_t < 0.0:
			lead_t = s.t
		var lead := absf(s.t - lead_t) < 1.5
		if not lead and until > near:
			continue
		var rad := SMASH_R if s.smash else BALL_R
		var cm := _hit_c(RallyFlight.shot_x(s), rad)
		var p := Vector2(cm.x, cm.y)
		var r := rad * FOCAL * size.y / cm.z
		var rem := clampf(until / flight_ms, 0.0, 1.0)
		var vis := clampf((T - s.launch) / 120.0, 0.0, 1.0) * clampf(1.0 + until / 60.0, 0.0, 1.0)
		var zs := RallyFlight.zones_of(s)
		var col := COL_SMASH if s.smash else zone_col(int(zs[0]))
		var al := (1.0 if lead else 0.42) * vis * (0.40 + 0.60 * (1.0 - rem))
		if lead:
			draw_arc(p, r, 0.0, TAU, 48, Color(col, 0.75 * vis), 1.8 * _u, true)
		draw_arc(p, r * (1.0 + 1.7 * rem), 0.0, TAU, 56, Color(col, al), (2.4 if lead else 1.3) * _u, true)
		if s.smash and zs.size() > 1:
			# Schmetterball: Schlaglinie beider Zonen in Weiss = beide Tasten.
			for z in zs:
				draw_line(_pp(_w(_zx(z, 0.012), 0.001, 0.0)), _pp(_w(_zx(z + 1, -0.012), 0.001, 0.0)),
						Color(COL_SMASH, al), 3.0 * _u, true)
