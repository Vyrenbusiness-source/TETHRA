class_name OrbitView
extends Control

## Orbit-Spielfeld: zwei Ringe um die Bildschirmmitte, Ziele wandern auf ihrem
## Winkel von der Mitte nach aussen und erreichen ihren Ring genau zur
## Trefferzeit. Alles in EINEM _draw-Durchgang (keine Nodes pro Note).
## Lesbarkeit vor Glanz: ruhige Farben, kein Blitzen, kein Wackeln.
##
## Winkel: Grad, 0 = oben, im Uhrzeigersinn (wie OrbitNote).
## Innen = Ring 0 (Kreis, kuehles Blau), Aussen = Ring 1 (Raute, warmes Bernstein).

## Ringradien und Spawn-Radius relativ zur Bildschirmhoehe.
const R_INNER_K := 0.205
const R_OUTER_K := 0.355
const R_SPAWN_K := 0.05
## Totzone um die Mitte (Cursor dort = Winkel bleibt stehen).
const DEADZONE_K := 0.045
## Notengroesse (Radius) relativ zur Hoehe; Anflug startet kleiner.
const NOTE_K := 0.026
const APPROACH_SCALE := 0.5
const ARC_W_K := 0.021
## Winkel-Toleranz fuer die Cursor-Anzeige (Fallback, Core liefert den echten Wert).
const TOL_DEFAULT := 22.0

const INNER_COL := Color(0.50, 0.80, 0.97)
const OUTER_COL := Color(0.98, 0.73, 0.47)
const MISS_COL := Color(0.50, 0.52, 0.58)
const MAX_COL := Color(1.0, 0.95, 0.84)
const PLATE_COL := Color(0.015, 0.02, 0.035)

const HIT_LIGHT_MS := 200.0
const MISS_FADE_MS := 260.0
const CHORD_EPS_MS := 2.0

## Zustand je Note (parallel zu notes).
const ST_PENDING := 0
const ST_HIT := 1
const ST_MISS := 2
const ST_ARC := 3      # Bogen gehalten
const ST_ARC_DONE := 4
const ST_DROP := 5     # Bogen verloren

var notes: Array = []
var t_ms := 0.0
var preempt := 1200.0
var cursor_deg := 0.0
var cursor_pos := Vector2(-1, -1)
var cursor_in_deadzone := false
var tol_deg := TOL_DEFAULT
var show_guides := true
var ring_held: Array[bool] = [false, false]

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _first := 0
var _lights: Array = []   # {pos, col, t0, r}
var _ring_glow: Array[float] = [0.0, 0.0]
var _plate_tex: GradientTexture2D
var _glow_tex: GradientTexture2D
var _last_frame_usec := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_tex = _radial_tex([0.0, 0.55, 1.0],
		[Color(PLATE_COL, 0.62), Color(PLATE_COL, 0.48), Color(PLATE_COL, 0.0)])
	_glow_tex = _radial_tex([0.0, 0.22, 0.6, 1.0],
		[Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])


static func _radial_tex(offsets: Array, cols: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(cols)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func setup(p_notes: Array) -> void:
	notes = p_notes
	_state.resize(notes.size())
	_state.fill(ST_PENDING)
	_state_t.resize(notes.size())
	_state_t.fill(0.0)
	_first = 0
	_lights.clear()


# ---------------------------------------------------------------------------
# Geometrie (auch fuer Tests)
# ---------------------------------------------------------------------------

func center() -> Vector2:
	return size * 0.5


func unit() -> float:
	return maxf(size.y, 1.0)


func ring_radius(ring: int) -> float:
	return unit() * (R_OUTER_K if ring == 1 else R_INNER_K)


## Radius eines Ziels dt_ms vor seiner Trefferzeit (dt < 0 = schon vorbei:
## laeuft gleichmaessig weiter nach aussen).
func radius_at(ring: int, dt_ms: float) -> float:
	var r0 := unit() * R_SPAWN_K
	var r1 := ring_radius(ring)
	return r0 + (r1 - r0) * (1.0 - dt_ms / maxf(preempt, 1.0))


static func polar(c: Vector2, deg: float, r: float) -> Vector2:
	var a := deg_to_rad(deg)
	return c + Vector2(sin(a), -cos(a)) * r


## Winkel von c nach p: 0 = oben, im Uhrzeigersinn, 0..360.
static func angle_of(c: Vector2, p: Vector2) -> float:
	var d := p - c
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## Bildschirmwinkel (draw_arc: 0 = rechts, im Uhrzeigersinn) zu Orbit-Grad.
static func _ga(deg: float) -> float:
	return deg_to_rad(deg - 90.0)


func deadzone_radius() -> float:
	return unit() * DEADZONE_K


# ---------------------------------------------------------------------------
# Ereignisse aus dem Spiel
# ---------------------------------------------------------------------------

func on_judged(index: int, result: Dictionary) -> void:
	if index < 0 or index >= notes.size():
		return
	var n = notes[index]
	var q := int(result.get("quality", 5))
	if q == 5:
		_state[index] = ST_DROP if n.is_arc and _state[index] == ST_ARC else ST_MISS
		_state_t[index] = t_ms
		return
	if n.is_arc:
		_state[index] = ST_ARC_DONE
		_state_t[index] = t_ms
		_light(polar(center(), float(n.end_angle_deg), ring_radius(n.ring)), n.ring, q)
		return
	_state[index] = ST_HIT
	_state_t[index] = t_ms
	_light(polar(center(), float(n.angle_deg), ring_radius(n.ring)), n.ring, q)


func on_arc_started(index: int) -> void:
	if index < 0 or index >= notes.size():
		return
	_state[index] = ST_ARC
	_state_t[index] = t_ms
	var n = notes[index]
	_light(polar(center(), float(n.angle_deg), ring_radius(n.ring)), n.ring, 1)


func _light(pos: Vector2, ring: int, q: int) -> void:
	var col: Color = MAX_COL if q == 0 else (OUTER_COL if ring == 1 else INNER_COL).lightened(0.25)
	_lights.append({"pos": pos, "col": col, "t0": t_ms, "ring": ring})
	if _lights.size() > 24:
		_lights.pop_front()


func state_of(index: int) -> int:
	return _state[index] if index >= 0 and index < _state.size() else ST_PENDING


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_frame_usec) / 1000000.0, 0.0, 0.1)
	_last_frame_usec = now
	for r in 2:
		var target := 1.0 if ring_held[r] else 0.0
		# Weiches Nachziehen (~60 ms), nie ein harter Sprung.
		_ring_glow[r] = lerpf(_ring_glow[r], target, 1.0 - exp(-dt / 0.06))
	queue_redraw()


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _draw() -> void:
	var c := center()
	var u := unit()
	var r_in := ring_radius(0)
	var r_out := ring_radius(1)

	# Dunkle Platte hinter dem Spielfeld: Lesbarkeit ueber jedem Map-Bild.
	var pr := r_out * 1.45
	draw_texture_rect(_plate_tex, Rect2(c - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false)

	if show_guides:
		_draw_guides(c, u, r_in, r_out)
	_draw_rings(c, u, r_in, r_out)
	_draw_cursor(c, u, r_in, r_out)

	# Sichtbare Noten: _first rueckt nach, sobald alles davor verblasst ist.
	while _first < notes.size():
		var f = notes[_first]
		var gone := _state[_first] != ST_PENDING and _state[_first] != ST_ARC \
				and t_ms - _state_t[_first] > MISS_FADE_MS
		if gone or float(f.end_ms) + 1500.0 < t_ms:
			_first += 1
		else:
			break
	var last := _first
	while last < notes.size() and float(notes[last].time_ms) - t_ms <= preempt:
		last += 1

	# Landemarken + Akkord-Verbindungen unter den Noten.
	for i in range(_first, last):
		_draw_landing(c, i)
	for i in range(_first, last - 1):
		var a = notes[i]
		var b = notes[i + 1]
		if absf(float(b.time_ms) - float(a.time_ms)) <= CHORD_EPS_MS \
				and _state[i] == ST_PENDING and _state[i + 1] == ST_PENDING:
			_draw_chord(c, a, b)
	# Spaetere zuerst: die naechste Note liegt immer obenauf.
	for i in range(last - 1, _first - 1, -1):
		var n = notes[i]
		if n.is_arc:
			_draw_arc_note(c, u, i, n)
		else:
			_draw_tap(c, u, i, n)
	_draw_lights(u)
	_draw_cursor_dot(u)


func _ring_col(ring: int) -> Color:
	return OUTER_COL if ring == 1 else INNER_COL


func _draw_guides(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var r0 := u * R_SPAWN_K * 1.6
	for k in 8:
		var deg := float(k) * 45.0
		var major := k % 2 == 0
		var col := Color(1, 1, 1, 0.075 if major else 0.04)
		draw_line(polar(c, deg, r0), polar(c, deg, r_out + u * 0.025), col, 1.0, true)
	# Feine Teilstriche aussen alle 15 Grad.
	for k in 24:
		var deg := float(k) * 15.0
		var long := k % 6 == 0
		var a := r_out + u * 0.012
		var b := a + u * (0.016 if long else 0.008)
		draw_line(polar(c, deg, a), polar(c, deg, b), Color(1, 1, 1, 0.16 if long else 0.08), 1.0, true)
	var _unused := r_in


func _draw_rings(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var band := u * 0.034
	for r in 2:
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r)
		var g := _ring_glow[r]
		# Trefferzone: breites, sehr leises Band.
		draw_arc(c, rad, 0.0, TAU, 128, Color(col, 0.045 + 0.05 * g), band, true)
		# Ringlinie: Aussen doppelt (zwei feine Linien), innen einfach -> auch
		# ohne Farbe unterscheidbar.
		var la := 0.34 + 0.34 * g
		if r == 1:
			draw_arc(c, rad - 2.0, 0.0, TAU, 160, Color(col, la), 1.5, true)
			draw_arc(c, rad + 2.0, 0.0, TAU, 160, Color(col, la * 0.6), 1.0, true)
		else:
			draw_arc(c, rad, 0.0, TAU, 128, Color(col, la), 2.0, true)


func _draw_cursor(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var a0 := _ga(cursor_deg - tol_deg)
	var a1 := _ga(cursor_deg + tol_deg)
	var dim := 0.55 if cursor_in_deadzone else 1.0
	# Leiser Zeiger von der Mitte bis aussen.
	draw_line(polar(c, cursor_deg, u * R_SPAWN_K * 1.6), polar(c, cursor_deg, r_out - u * 0.03),
		Color(1, 1, 1, 0.06 * dim), 1.5, true)
	for r in 2:
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r).lerp(Color.WHITE, 0.35)
		var g := _ring_glow[r]
		var w := u * 0.046
		draw_arc(c, rad, a0, a1, 24, Color(col, (0.09 + 0.13 * g) * dim), w, true)
		# Raender der Toleranz als feine Kanten.
		for e in [cursor_deg - tol_deg, cursor_deg + tol_deg]:
			draw_line(polar(c, e, rad - w * 0.5), polar(c, e, rad + w * 0.5),
				Color(col, (0.20 + 0.15 * g) * dim), 1.0, true)
		# Mittelmarke: kurzer radialer Strich.
		draw_line(polar(c, cursor_deg, rad - w * 0.62), polar(c, cursor_deg, rad + w * 0.62),
			Color(1, 1, 1, (0.55 + 0.35 * g) * dim), 2.5, true)


func _draw_cursor_dot(u: float) -> void:
	if cursor_pos.x < 0.0:
		return
	draw_circle(cursor_pos, u * 0.0055, Color(1, 1, 1, 0.55), true, -1.0, true)
	draw_arc(cursor_pos, u * 0.011, 0.0, TAU, 24, Color(1, 1, 1, 0.22), 1.0, true)


func _draw_landing(c: Vector2, i: int) -> void:
	if _state[i] != ST_PENDING:
		return
	var n = notes[i]
	var dt := float(n.time_ms) - t_ms
	var win := preempt * 0.55
	if dt < 0.0 or dt > win:
		return
	var k := 1.0 - dt / win
	var rad := ring_radius(n.ring)
	var col := _ring_col(n.ring)
	var span := rad_to_deg(unit() * NOTE_K * 1.3 / rad)
	var a := float(n.angle_deg)
	draw_arc(c, rad, _ga(a - span), _ga(a + span), 12, Color(col, 0.42 * k * k), 3.0, true)


func _draw_chord(c: Vector2, a, b) -> void:
	var dt := float(a.time_ms) - t_ms
	var pa := polar(c, float(a.angle_deg), radius_at(a.ring, dt))
	var pb := polar(c, float(b.angle_deg), radius_at(b.ring, dt))
	var k := _approach_alpha(dt)
	draw_line(pa, pb, Color(1, 1, 1, 0.22 * k), 2.0, true)


## Einblenden im ersten Fuenftel des Anflugs (kein Aufploppen in der Mitte).
func _approach_alpha(dt: float) -> float:
	var p := 1.0 - dt / maxf(preempt, 1.0)
	return clampf(p / 0.2, 0.0, 1.0)


func _approach_scale(dt: float) -> float:
	var p := clampf(1.0 - dt / maxf(preempt, 1.0), 0.0, 1.0)
	return lerpf(APPROACH_SCALE, 1.0, sqrt(p))


func _draw_tap(c: Vector2, u: float, i: int, n) -> void:
	var st := _state[i]
	if st == ST_HIT:
		return
	var dt := float(n.time_ms) - t_ms
	var alpha := _approach_alpha(dt)
	var col := _ring_col(n.ring)
	if st == ST_MISS:
		var f := clampf((t_ms - _state_t[i]) / MISS_FADE_MS, 0.0, 1.0)
		alpha = 0.7 * (1.0 - f)
		col = MISS_COL
	if alpha <= 0.002:
		return
	var p := polar(c, float(n.angle_deg), radius_at(n.ring, dt))
	var s := u * NOTE_K * _approach_scale(dt)
	_shape(p, float(n.angle_deg), n.ring, s, col, alpha)


## Notenform: innen Kreis, aussen Raute (Spitze radial). Dunkler Kern,
## farbiger Rand, heller Mittelpunkt.
func _shape(p: Vector2, deg: float, ring: int, s: float, col: Color, alpha: float) -> void:
	var fill := Color(col.darkened(0.62), 0.92 * alpha)
	var rim := Color(col, alpha)
	var core := Color(col.lightened(0.45), alpha)
	if ring == 0:
		draw_circle(p, s, fill, true, -1.0, true)
		draw_arc(p, s, 0.0, TAU, 32, rim, maxf(2.0, s * 0.2), true)
		draw_circle(p, s * 0.34, core, true, -1.0, true)
	else:
		var a := deg_to_rad(deg)
		var ur := Vector2(sin(a), -cos(a)) * s * 1.18
		var ut := Vector2(cos(a), sin(a)) * s * 1.18
		var pts := PackedVector2Array([p + ur, p + ut, p - ur, p - ut])
		draw_colored_polygon(pts, fill)
		var loop := pts.duplicate()
		loop.append(pts[0])
		loop.append(pts[1])  # Ecke sauber schliessen
		draw_polyline(loop, rim, maxf(2.0, s * 0.2), true)
		var k := 0.36
		draw_colored_polygon(PackedVector2Array([p + ur * k, p + ut * k, p - ur * k, p - ut * k]), core)


func _draw_arc_note(c: Vector2, u: float, i: int, n) -> void:
	var st := _state[i]
	var col := _ring_col(n.ring)
	var a0 := float(n.angle_deg)
	var a1 := float(n.end_angle_deg)
	var t0 := float(n.time_ms)
	var t1 := float(n.end_ms)
	var w := u * ARC_W_K
	var fade := 1.0
	if st == ST_ARC_DONE:
		return
	if st == ST_MISS or st == ST_DROP:
		fade = 0.65 * (1.0 - clampf((t_ms - _state_t[i]) / (MISS_FADE_MS * 1.6), 0.0, 1.0))
		col = MISS_COL
		if fade <= 0.002:
			return
	var dt := t0 - t_ms
	var held := st == ST_ARC
	var rad := ring_radius(n.ring) if (held or dt < 0.0) else radius_at(n.ring, dt)
	var alpha := _approach_alpha(dt) * fade
	# Spitze: bewegt sich ab der Trefferzeit von a0 nach a1.
	var k := clampf((t_ms - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0) if (held or dt < 0.0) else 0.0
	var tip := lerpf(a0, a1, k)
	if k > 0.0 and n.has_method("angle_at"):
		# Gleiche Spitze wie der Core; nahe der linearen Schaetzung entfaltet.
		var core_tip := float(n.angle_at(t_ms))
		tip += rad_to_deg(angle_difference(deg_to_rad(tip), deg_to_rad(core_tip)))
	var lo := minf(tip, a1)
	var hi := maxf(tip, a1)
	var seg := maxi(8, int(absf(hi - lo) / 3.0))
	if hi - lo > 0.3:
		# Weicher Schein, Koerper, helle Mittellinie.
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(col, 0.13 * alpha * (1.6 if held else 1.0)), w * 2.4, true)
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(col.darkened(0.25), 0.78 * alpha), w, true)
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(col.lightened(0.35), (0.75 if held else 0.45) * alpha), maxf(1.5, w * 0.22), true)
	# Bereits abgefahrener Teil: leise Spur, die mit der Zeit verschwindet.
	if held and absf(tip - a0) > 0.3:
		var tlo := minf(a0, tip)
		var thi := maxf(a0, tip)
		draw_arc(c, rad, _ga(tlo), _ga(thi), maxi(6, int((thi - tlo) / 4.0)), Color(col, 0.12), w * 0.45, true)
	# Ende: offener Ring als Ziel.
	var pe := polar(c, a1, rad)
	draw_circle(pe, w * 0.62, Color(col.darkened(0.6), 0.9 * alpha), true, -1.0, true)
	draw_arc(pe, w * 0.62, 0.0, TAU, 24, Color(col, 0.9 * alpha), 2.0, true)
	if held:
		var pt := polar(c, tip, rad)
		var gs := u * 0.075
		draw_texture_rect(_glow_tex, Rect2(pt - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(col.lightened(0.3), 0.55))
		draw_circle(pt, w * 0.55, Color(col.lightened(0.6), 0.95), true, -1.0, true)
		# Richtungspfeil kurz vor der Spitze.
		_chevron(c, rad, tip, signf(a1 - a0), w, Color(1, 1, 1, 0.55))
	else:
		var s := u * NOTE_K * (_approach_scale(dt) if dt > 0.0 else 1.0)
		_shape(polar(c, a0, rad), a0, n.ring, s, col, alpha)
		if st == ST_PENDING:
			_chevron(c, rad, a0, signf(a1 - a0), w, Color(1, 1, 1, 0.45 * alpha))


## Kleiner Pfeil auf dem Bogen in Laufrichtung (dir +1 = Uhrzeigersinn).
func _chevron(c: Vector2, rad: float, deg: float, dir: float, w: float, col: Color) -> void:
	if dir == 0.0:
		return
	var off := rad_to_deg(w * 2.3 / maxf(rad, 1.0))
	var tip_deg := deg + dir * off
	var p := polar(c, tip_deg, rad)
	var a := deg_to_rad(tip_deg)
	var tan := Vector2(cos(a), sin(a)) * dir
	var nrm := Vector2(sin(a), -cos(a))
	var h := w * 0.55
	draw_polyline(PackedVector2Array([p - tan * h + nrm * h, p, p - tan * h - nrm * h]), col, 2.0, true)


func _draw_lights(u: float) -> void:
	for l in _lights:
		var f := (t_ms - float(l.t0)) / HIT_LIGHT_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var col: Color = l.col
		var gs := u * lerpf(0.07, 0.10, f)
		draw_texture_rect(_glow_tex, Rect2(l.pos - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false,
			Color(col, 0.42 * e * e))
		draw_arc(l.pos, u * NOTE_K * lerpf(1.0, 1.9, sqrt(f)), 0.0, TAU, 32, Color(col, 0.45 * e), 1.5, true)
