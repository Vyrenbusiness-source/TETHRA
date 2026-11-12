class_name RallyView
extends Control

## Rally v2: Blick hinter und ueber dem Spieler (ein _draw). Der Tisch laeuft in echter
## Perspektive vom unteren Bildrand weg (eigene Projektion Vector3 -> Bildschirm), Netz in
## der Mitte, Gegner am fernen Ende, deine Haelfte in 4 Zonen. Alles ist eine reine Funktion
## von t_ms + Wertung (RallyCore): Baelle, Ringe und Schlaeger werden jedes Bild aus
## RallyFlight neu berechnet, nichts davon steuert die Wertung.
## Farbe = Zone (tief kuehl -> hoch warm), Schmetterball weiss umrandet und groesser,
## schrumpfender Landering + Schatten auf dem Tisch = WO und WANN.

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
const FX_MS := 260.0
const MISS_FLY_MS := 450.0
const GOLD := 2.399963

var beat_ms := 500.0
var shots: Array[RallyChart.Shot] = []
var core: RallyCore
var t_ms := 0.0
## Gehaltene Zonentasten (links nach rechts); der Game-Knoten setzt sie.
var held := [false, false, false, false]
var key_labels := ["D", "F", "J"]
var flight_ms := 800.0

var _fx: Array = []
var _hit_t: Dictionary = {}
var _rel_t: Dictionary = {}
var _shake := 0.0
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
		return
	if bool(result.get("hold_end", false)):
		_rel_t[idx] = t_ms
		_add_fx("release", s, t_ms)
		return
	_hit_t[idx] = t_ms
	_add_fx("hit", s, t_ms)
	_swing_t = t_ms
	for z in zs:
		_pulse[z] = t_ms
	if s.smash:
		_shake = 1.0


func on_charge(idx: int) -> void:
	if idx < 0 or idx >= shots.size():
		return
	var s := shots[idx]
	_hit_t[idx] = t_ms
	_swing_t = t_ms
	for z in RallyFlight.zones_of(s):
		_pulse[z] = t_ms
	_add_fx("hit", s, t_ms)


func _add_fx(kind: String, s: RallyChart.Shot, t0: float) -> void:
	var zs := RallyFlight.zones_of(s)
	_fx.append({"t0": t0, "kind": kind, "x": RallyFlight.shot_x(s), "smash": s.smash,
			"zone": int(zs[0])})
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
	_shake = maxf(_shake - delta * 7.0, 0.0)
	for k in _n():
		var on := 1.0 if (k < held.size() and bool(held[k])) else 0.0
		var cur: float = _lit[k]
		_lit[k] = move_toward(cur, on, delta * (14.0 if on > cur else 5.0))
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
	var off := Vector2.ZERO
	if _shake > 0.0:
		# Kamera-Impuls nur beim Schmetterball, hoechstens 2 px.
		off = Vector2(sin(t_ms * 0.09), cos(t_ms * 0.13)) * (1.9 * _shake)
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_room()
	_draw_table()
	_draw_zones()
	_draw_charge_bands()
	_draw_landings()
	var balls := _collect_balls()
	_draw_shadows(balls)
	_draw_opponent()
	_draw_net()
	# Alle Baelle nach dem Netz: nie vom Netz ueberdeckt.
	for b in balls:
		_draw_ball(b)
	_draw_player()
	_draw_fx()
	_draw_keys()
	_draw_counter()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	# Halbtransparent: das Map-Bild (MapBackdrop des Game-Knotens) scheint durch.
	draw_rect(Rect2(0, 0, w, h), Color(COL_ROOM, 0.74))
	var boost := 1.0 + 0.10 * _lvl
	# Raumlicht: weicher Kegel ueber der Tischmitte (konzentrische Ellipsen, sehr leise).
	var lc := _pp(_w(0.0, 0.0, 0.55))
	for i in 40:
		var f := float(i) / 39.0
		var rx := w * (0.62 - 0.46 * f)
		var ry := h * (0.58 - 0.42 * f)
		draw_set_transform(lc + Vector2(0, -h * 0.10), 0.0, Vector2(1.0, ry / rx))
		draw_circle(Vector2.ZERO, rx, Color(COL_LIGHT, 0.0045 * boost))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_audience()
	# Boden: hinter dem Tisch einen Hauch heller, nach vorn dunkel.
	var yh := _pp(_w(0.0, 0.0, 1.9)).y
	_quad_g(Vector2(0, yh), Vector2(w, yh), Vector2(w, h), Vector2(0, h),
			Color(COL_LIGHT, 0.030), Color(0, 0, 0, 0.0))
	# Weicher Schatten unter dem Tisch.
	var sc := _pp(_w(0.0, -0.76, 0.5))
	for i in 5:
		var f2 := float(i) / 4.0
		draw_set_transform(sc, 0.0, Vector2(1.0, 0.16))
		draw_circle(Vector2.ZERO, w * (0.42 - 0.07 * f2), Color(0, 0, 0, 0.07))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Vignette.
	var vg := 0.62
	_quad_g(Vector2(0, 0), Vector2(w * 0.16, 0), Vector2(w * 0.16, h), Vector2(0, h),
			Color(0, 0, 0, vg), Color(0, 0, 0, 0))
	_quad_g(Vector2(w, 0), Vector2(w * 0.84, 0), Vector2(w * 0.84, h), Vector2(w, h),
			Color(0, 0, 0, vg), Color(0, 0, 0, 0))
	_quad_g(Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.12), Vector2(0, h * 0.12),
			Color(0, 0, 0, 0.55), Color(0, 0, 0, 0))


## Publikum: sehr dezente, weiche Silhouetten-Reihe in Raumfarbe (kein Kopf-Raster). Licht reagiert leise auf die Kombo.
func _draw_audience() -> void:
	var w := size.x
	var h := size.y
	var rim := 0.010 + 0.030 * _lvl
	var seg := 48
	for row in 2:
		var base_y := h * (0.115 - 0.030 * float(row))
		var amp := h * (0.040 - 0.010 * float(row))
		var col := COL_ROOM.lightened(0.030 - 0.012 * float(row))
		for i in seg:
			var x0 := w * float(i) / float(seg)
			var x1 := w * float(i + 1) / float(seg)
			var hs := float((i * 7919 + row * 104729) % 97) / 97.0
			var hn := float(((i + 1) * 7919 + row * 104729) % 97) / 97.0
			var y0 := base_y - amp * (0.35 + 0.65 * hs)
			var y1 := base_y - amp * (0.35 + 0.65 * hn)
			var top := Color(col, 0.0)
			var bot := Color(col, 0.34)
			draw_polygon(PackedVector2Array([Vector2(x0, y0 - amp * 0.9), Vector2(x1, y1 - amp * 0.9),
					Vector2(x1, base_y), Vector2(x0, base_y)]), PackedColorArray([top, top, bot, bot]))
			if rim > 0.0 and hs > 0.55:
				draw_line(Vector2(x0, y0), Vector2(x1, y1), Color(COL_LIGHT, rim * (1.0 - 0.4 * float(row))), 1.2, true)


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
	var a2 := _pp(_w(-1, -0.05, 0))
	var b2 := _pp(_w(1, -0.05, 0))
	_quad_g(a, b, b2, a2, COL_TABLE_DARK.lightened(0.06), COL_ROOM)
	draw_line(a, b, Color(COL_LINE, 0.55), 1.8, true)
	var af := _pp(_w(-1, 0, 1))
	var bf := _pp(_w(1, 0, 1))
	draw_line(af, bf, Color(COL_LINE, 0.20), 1.0, true)
	draw_line(a, af, Color(COL_LINE, 0.34), 1.4, true)
	draw_line(b, bf, Color(COL_LINE, 0.34), 1.4, true)
	# Mittellinie lang (Doppel-Linie des Tisches), sehr fein.
	draw_line(_pp(_w(0, 0, 0)), _pp(_w(0, 0, 1)), Color(COL_LINE, 0.07), 1.0, true)


func _draw_net() -> void:
	var ex := 1.07
	var b0 := _pp(_w(-ex, 0.0, 0.5))
	var b1 := _pp(_w(ex, 0.0, 0.5))
	var t0 := _pp(Vector3(-ex * HALF_W, NET_H, 0.5 * LEN))
	var t1 := _pp(Vector3(ex * HALF_W, NET_H, 0.5 * LEN))
	_quad(b0, b1, t1, t0, Color(0.78, 0.82, 0.88, 0.10))
	var nv := 30
	for i in range(1, nv):
		var f := float(i) / float(nv)
		draw_line(b0.lerp(b1, f), t0.lerp(t1, f), Color(0.85, 0.88, 0.92, 0.10), 1.0)
	for i in range(1, 5):
		var g := float(i) / 5.0
		draw_line(b0.lerp(t0, g), b1.lerp(t1, g), Color(0.85, 0.88, 0.92, 0.07), 1.0)
	draw_line(t0, t1, Color(COL_LINE, 0.80), 2.0, true)
	draw_line(t0 + Vector2(0, 2.0), t1 + Vector2(0, 2.0), Color(COL_LINE, 0.16), 1.0, true)
	var pw := maxf(0.012 * _sc(_w(ex, 0, 0.5)), 2.0)
	draw_line(b0, t0, Color(0.55, 0.58, 0.63, 0.9), pw, true)
	draw_line(b1, t1, Color(0.55, 0.58, 0.63, 0.9), pw, true)


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
		var pulse := clampf(1.0 - (t_ms - float(_pulse[z])) / 260.0, 0.0, 1.0)
		var miss := clampf(1.0 - (t_ms - float(_miss[z])) / 320.0, 0.0, 1.0)
		var lit: float = _lit[z]
		var a := 0.085 + 0.20 * lit + 0.12 * pulse * pulse
		# Zone auf deiner Haelfte: vorn kraeftiger, zur Mitte hin auslaufend.
		_zone_quad(z, 0.0, 0.5, 0.012, Color(col, a), Color(col, a * 0.25))
		if miss > 0.0:
			_zone_quad(z, 0.0, 0.5, 0.012, Color(COL_MISS, 0.16 * miss), Color(COL_MISS, 0.03 * miss))
		# Leuchtende Vorderkante der gedrueckten Zone.
		var xa := _zx(z, 0.012)
		var xb := _zx(z + 1, -0.012)
		var la := 0.45 + 0.50 * lit
		draw_line(_pp(_w(xa, 0.001, 0.0)), _pp(_w(xb, 0.001, 0.0)), Color(col, la), 2.0, true)
		# Verlaengerung nach vorn (Lichtstreifen Richtung Taste).
		_zone_quad(z, -0.62, 0.0, 0.012, Color(col, 0.0), Color(col, 0.07 + 0.25 * lit))
	# Feine Trennlinien.
	for i in _n() + 1:
		var x := _zx(i, 0.0)
		var ea := 0.14 if (i == 0 or i == _n()) else 0.10
		draw_line(_pp(_w(x, 0.001, 0.0)), _pp(_w(x, 0.001, 0.5)), Color(COL_LINE, ea), 1.0, true)
	# Schlaegerlinie.
	draw_line(_pp(_w(-1, 0.001, 0.0)), _pp(_w(1, 0.001, 0.0)), Color(COL_LINE, 0.22), 1.2, true)


func _draw_keys() -> void:
	var fs := int(size.y * 0.034)
	for z in _n():
		var col := zone_col(z)
		var lit: float = _lit[z]
		var c := _pp(_w((_zx(z, 0.0) + _zx(z + 1, 0.0)) * 0.5, -0.034, 0.0))
		var half := Vector2(size.y * 0.050, size.y * 0.030)
		var rc := Rect2(c - half, half * 2.0)
		draw_rect(rc, Color(col, 0.10 + 0.42 * lit), true)
		if lit > 0.02:
			draw_rect(rc.grow(size.y * 0.008 * lit), Color(col, 0.16 * lit), true)
		draw_rect(rc, Color(col, 0.55 + 0.45 * lit), false, 1.8)
		var txt: String = str(key_labels[z]) if z < key_labels.size() else ""
		var ts := _key_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_key_font, c + Vector2(-ts.x * 0.5, ts.y * 0.30), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lerp(Color.WHITE, 0.40 + 0.5 * lit), 0.85 + 0.15 * lit))


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
	var j := RallyChart.first_at_or_after(shots, t_ms)
	var jmax := RallyChart.first_at_or_after(shots, t_ms + flight_ms + 1.0)
	for k in range(j, jmax):
		var s := shots[k]
		if s.launch > t_ms:
			continue
		var land := RallyFlight.landing_time(s)
		if t_ms >= land:
			continue
		var span := maxf(land - s.launch, 1.0)
		var rem := clampf((land - t_ms) / span, 0.0, 1.0)
		var vis := clampf((t_ms - s.launch) / 90.0, 0.0, 1.0)
		var zs := RallyFlight.zones_of(s)
		var r := 0.055 + 0.085 * rem
		var rr := r * (1.28 if s.smash else 1.0)
		var al := (0.20 + 0.65 * (1.0 - rem)) * vis
		var cz := RallyFlight.Z_LAND * LEN
		for z in zs:
			var cx := RallyFlight.zone_x(z) * HALF_W
			var col := zone_col(z)
			_ground_ring(cx, cz, rr, Color(col, al), 2.0 if s.smash else 1.6, 0.10)
			if s.smash:
				_ground_ring(cx, cz, rr + 0.025, Color(COL_SMASH, al * 0.85), 1.4)
		if zs.size() > 1:
			var xa := RallyFlight.zone_x(zs[0]) * HALF_W
			var xb := RallyFlight.zone_x(zs[zs.size() - 1]) * HALF_W
			draw_line(_pp(Vector3(xa + rr, 0.002, cz)), _pp(Vector3(xb - rr, 0.002, cz)),
					Color(COL_SMASH, al * 0.5), 1.2, true)


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
		var al := float(b.a) * (0.20 - 0.12 * hgt)
		var col: Color = b.col
		var cx := P.x * HALF_W
		var cz := P.z * LEN
		var r := rad * (1.1 + 0.4 * hgt)
		var pts := PackedVector2Array()
		var pts2 := PackedVector2Array()
		for i in 20:
			var an := TAU * float(i) / 20.0
			pts.append(_pp(Vector3(cx + cos(an) * r, 0.002, cz + sin(an) * r)))
			pts2.append(_pp(Vector3(cx + cos(an) * r * 0.62, 0.003, cz + sin(an) * r * 0.62)))
		draw_colored_polygon(pts, Color(0, 0, 0, al))
		# Zonenfarbe als feiner Schein im Schatten: zeigt die Zone schon im Flug.
		draw_colored_polygon(pts2, Color(col, 0.22 * float(b.a)))


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
	# Tiefe: ferne Baelle heller (Nebel zum Licht), nahe satt.
	var c := col.lerp(Color(1, 1, 1), 0.40 * far)
	r *= 1.0 - 0.18 * far
	var s: RallyChart.Shot = b.s
	if str(b.kind) == "in":
		var step := 6
		var prev := p
		for i in range(1, step + 1):
			var tt := t_ms - TRAIL_MS * float(i) / float(step)
			if tt < s.launch:
				break
			var q := RallyFlight.ball_pos(s, tt)
			var cq := _cam(_w(q.x, q.y + rad, q.z))
			var pq := Vector2(cq.x, cq.y)
			var f := 1.0 - float(i) / float(step + 1)
			draw_line(prev, pq, Color(c, 0.22 * f * al), maxf(r * 1.5 * f, 1.0), true)
			prev = pq
	if bool(b.smash):
		draw_arc(p, r + maxf(r * 0.16, 2.0), 0.0, TAU, 40, Color(COL_SMASH, 0.95 * al), maxf(r * 0.10, 1.6), true)
	if str(b.kind) == "held":
		var k: int = b.k
		var h0: float = float(_hit_t.get(k, s.t))
		var prog := clampf((t_ms - h0) / maxf(s.end - h0, 1.0), 0.0, 1.0)
		var rr := r * 1.75
		draw_arc(p, rr, 0.0, TAU, 48, Color(c, 0.22), 2.0, true)
		draw_arc(p, rr, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(c, 0.95), 3.2, true)
	draw_circle(p, r, Color(c.darkened(0.12), al))
	draw_circle(p + Vector2(-r * 0.16, -r * 0.2), r * 0.74, Color(c.lightened(0.10), al))
	draw_circle(p + Vector2(-r * 0.34, -r * 0.38), r * 0.22, Color(1, 1, 1, 0.55 * al))
	draw_arc(p, r, 0.0, TAU, 28, Color(0, 0, 0, 0.30 * al), 1.0, true)


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
	draw_colored_polygon(grip, COL_WOOD.darkened(0.62))
	draw_colored_polygon(outer, COL_WOOD.darkened(0.52))
	draw_colored_polygon(inner, rubber)
	var hl := PackedVector2Array()
	for i in 14:
		var a2 := PI * 1.08 + PI * 0.52 * float(i) / 13.0
		hl.append(c + _rot(Vector2(cos(a2) * rx * 0.74, sin(a2) * ry * 0.74), ang))
	draw_polyline(hl, Color(1, 1, 1, 0.10), 1.4, true)
	var closed := inner.duplicate()
	closed.append(inner[0])
	draw_polyline(closed, Color(edge, 0.55), 1.4, true)


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
	var wp := Vector3(px * HALF_W * 1.02 + 0.03, 0.045 + 0.05 * sv + 0.01 * wind, -0.05 + 0.16 * sv - 0.05 * wind)
	var cm := _cam(wp)
	var pxm := FOCAL * size.y / cm.z
	var zc := zone_col(clampi(int(round((px + 1.0) * float(_n()) * 0.5 - 0.5)), 0, _n() - 1))
	_blade(Vector2(cm.x, cm.y), 0.040 * pxm, 0.037 * pxm, 0.10 - 0.25 * sv + 0.10 * wind,
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
	# Gegner-Schatten (Koerper nur angedeutet, dunkler als der Raum).
	var body := _pp(Vector3(wp.x * 0.9, 0.55, LEN + 0.45))
	draw_set_transform(body, 0.0, Vector2(0.55, 1.0))
	draw_circle(Vector2.ZERO, 0.24 * pxm, Color(0, 0, 0, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_blade(Vector2(cm.x, cm.y), 0.085 * pxm, 0.078 * pxm, -0.10 - 0.35 * swing,
			Color(0.20, 0.10, 0.10), Color(0.62, 0.66, 0.74), 0.10 * pxm)


# ---------------------------------------------------------------------------
# Effekte (kurz, dezent)
# ---------------------------------------------------------------------------

func _draw_fx() -> void:
	var keep: Array = []
	for f in _fx:
		var age := t_ms - float(f.t0)
		if age < 0.0:
			keep.append(f)
			continue
		if age > FX_MS:
			continue
		keep.append(f)
		var u := age / FX_MS
		var e := 1.0 - pow(1.0 - u, 3.0)
		var base := Vector3(float(f.x) * HALF_W, RallyFlight.Y_RACKET + BALL_R, 0.0)
		var p := _pp(base)
		var sc := _sc(base)
		var big := 1.5 if bool(f.smash) else 1.0
		var col := zone_col(int(f.zone))
		if str(f.kind) == "release":
			draw_arc(p, sc * 0.035 * (1.0 + 0.4 * e), 0.0, TAU, 40, Color(col, 0.8 * (1.0 - u)), 1.8, true)
			continue
		draw_arc(p, sc * 0.030 * (1.0 + 0.55 * big * e), 0.0, TAU, 40, Color(col, 0.7 * (1.0 - u)), 1.6, true)
		if bool(f.smash):
			draw_arc(p, sc * 0.045 * (1.0 + 0.6 * e), 0.0, TAU, 40, Color(COL_SMASH, 0.6 * (1.0 - u)), 1.4, true)
		# Funken: wenige, kleine Punkte in Zonenfarbe, bremsen ab und fallen leicht.
		var n := 12 if bool(f.smash) else 6
		var tseed := int(float(f.t0)) % 997
		for i in n:
			var h := float((i * 7919 + tseed * 31) % 101) / 101.0
			var ang := GOLD * float(i) + h * 2.0
			var spd := (0.30 + 0.45 * h) * big
			var d := Vector2(cos(ang), -absf(sin(ang)) * 0.8 - 0.25)
			var q := p + d * spd * sc * 0.40 * e + Vector2(0, u * u * sc * 0.07)
			var sa := (1.0 - u) * (1.0 - u)
			draw_circle(q, maxf(sc * 0.006 * (1.0 - 0.5 * u), 1.0), Color(col.lerp(Color.WHITE, 0.35), 0.75 * sa))
	_fx = keep


func _draw_counter() -> void:
	if core == null:
		return
	var cb := core.combo
	if cb < 2:
		return
	var fs := int(size.y * 0.034)
	var txt := str(cb)
	var ts := _body_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var c := Vector2(size.x * 0.5, size.y * 0.108)
	var a := 0.55 + 0.10 * _lvl
	draw_string(_body_font, c + Vector2(-ts.x * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(COL_LINE, a))
	var ls := int(size.y * 0.016)
	var lab := "BALLWECHSEL" if UiTheme.is_german() else "RALLY"
	var lsz := _body_font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, ls)
	draw_string(_body_font, c + Vector2(-lsz.x * 0.5, ts.y * 0.55), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, ls,
			Color(COL_LINE, 0.32))
