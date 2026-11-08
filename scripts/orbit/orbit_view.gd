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
const R_INNER_K := 0.215
const R_OUTER_K := 0.37
const R_SPAWN_K := 0.085
## Dunkler Kern (Kombo + Judge); Ziele entstehen an seinem Rand.
const CORE_K := 0.078
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
## Frueh/Spaet wie JudgeDisplay; Fehltreffer-Kreuz gedecktes Rot.
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.62, 0.48)
const MISS_X_COL := Color(0.86, 0.50, 0.50)

const HIT_LIGHT_MS := 220.0
const MISS_FADE_MS := 260.0
## Fehltreffer-Marke (kleines Kreuz am Ring) bleibt so lange sichtbar.
const MISS_MARK_MS := 520.0
## Kombo-Meilenstein: ruhige Welle vom Kern bis zum Aussenring.
const WAVE_MS := 760.0
const CHORD_EPS_MS := 2.0
## Puffergroessen (fest, keine Allokationen pro Frame).
const MAX_LIGHTS := 24
const MAX_MARKS := 12

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
## Halbbreite der Mitte, in der MAX moeglich ist (OrbitCore.CENTER_DEG).
var center_deg := TOL_DEFAULT * 0.5
var show_guides := true
var ring_held: Array[bool] = [false, false]
## Takt-Puls 0..1 (BeatClock.beat_env, nach Intensitaet gewichtet) und Kiai 0..1.
var beat_env := 0.0
var kiai := 0.0
## Bogen-Warnung je Ring: 0 = Cursor auf dem Bogen, 1 = Bogen faellt gleich.
var arc_warn: Array[float] = [0.0, 0.0]

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _first := 0
# Licht-Pulse (Ringpuffer): Position, Winkel, Ring, Farbe, Start, MAX.
var _l_pos := PackedVector2Array()
var _l_deg := PackedFloat32Array()
var _l_ring := PackedInt32Array()
var _l_col := PackedColorArray()
var _l_t0 := PackedFloat64Array()
var _l_q := PackedInt32Array()
var _l_side := PackedFloat32Array()  # -1 frueh, +1 spaet, 0 ohne Marke
var _l_next := 0
# Fehltreffer-Marken (Ringpuffer).
var _m_pos := PackedVector2Array()
var _m_deg := PackedFloat32Array()
var _m_t0 := PackedFloat64Array()
var _m_next := 0
var _wave_t0 := -INF
var _wave_strong := false
# Wiederverwendete Punktpuffer fuer Formen.
var _quad := PackedVector2Array()
var _quad_in := PackedVector2Array()
var _loop := PackedVector2Array()
var _chev := PackedVector2Array()
var _ring_glow: Array[float] = [0.0, 0.0]
var _plate_tex: GradientTexture2D
var _glow_tex: GradientTexture2D
var _last_frame_usec := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_tex = _radial_tex([0.0, 0.55, 1.0],
		[Color(PLATE_COL, 0.84), Color(PLATE_COL, 0.74), Color(PLATE_COL, 0.0)])
	_glow_tex = _radial_tex([0.0, 0.22, 0.6, 1.0],
		[Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.0)])
	_quad.resize(4)
	_quad_in.resize(4)
	_loop.resize(6)
	_chev.resize(3)
	_reset_fx()


func _reset_fx() -> void:
	_l_pos.resize(MAX_LIGHTS)
	_l_deg.resize(MAX_LIGHTS)
	_l_ring.resize(MAX_LIGHTS)
	_l_col.resize(MAX_LIGHTS)
	_l_t0.resize(MAX_LIGHTS)
	_l_q.resize(MAX_LIGHTS)
	_l_side.resize(MAX_LIGHTS)
	_l_t0.fill(-1.0e12)
	_l_next = 0
	_m_pos.resize(MAX_MARKS)
	_m_deg.resize(MAX_MARKS)
	_m_t0.resize(MAX_MARKS)
	_m_t0.fill(-1.0e12)
	_m_next = 0
	_wave_t0 = -INF


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
	_reset_fx()


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
		var dropped: bool = n.is_arc and _state[index] == ST_ARC
		_state[index] = ST_DROP if dropped else ST_MISS
		_state_t[index] = t_ms
		# Ruhige Marke dort, wo das Ziel haette getroffen werden muessen
		# (Bogen: an der Spitze, wo er verloren ging).
		var deg := float(n.angle_at(t_ms)) if dropped else float(n.angle_deg)
		_mark(polar(center(), deg, ring_radius(n.ring)), deg)
		return
	if n.is_arc:
		_state[index] = ST_ARC_DONE
		_state_t[index] = t_ms
		_light(float(n.end_angle_deg), n.ring, q, 0.0)
		return
	_state[index] = ST_HIT
	_state_t[index] = t_ms
	_light(float(n.angle_deg), n.ring, q, float(result.get("dt", 0.0)))


func on_arc_started(index: int) -> void:
	if index < 0 or index >= notes.size():
		return
	_state[index] = ST_ARC
	_state_t[index] = t_ms
	var n = notes[index]
	_light(float(n.angle_deg), n.ring, 1, 0.0)


func _light(deg: float, ring: int, q: int, dt: float) -> void:
	# Immer Ringfarbe (innen/aussen bleibt auch im Licht erkennbar). MAX bekommt
	# einen hellen Praezisionsring, 300 die Ringfarbe, schwaechere Treffer ein
	# kleineres, matteres Licht plus Frueh/Spaet-Strich (innen = frueh).
	var i := _l_next
	_l_next = (_l_next + 1) % MAX_LIGHTS
	_l_pos[i] = polar(center(), deg, ring_radius(ring))
	_l_deg[i] = deg
	_l_ring[i] = ring
	var col := _ring_col(ring)
	if q == 0:
		col = col.lerp(MAX_COL, 0.55)
	elif q == 1:
		col = col.lightened(0.2)
	else:
		col = col.lerp(MISS_COL, 0.35)
	_l_col[i] = col
	_l_t0[i] = t_ms
	_l_q[i] = q
	_l_side[i] = (signf(dt) if q >= 2 else 0.0)


func _mark(pos: Vector2, deg: float) -> void:
	var i := _m_next
	_m_next = (_m_next + 1) % MAX_MARKS
	_m_pos[i] = pos
	_m_deg[i] = deg
	_m_t0[i] = t_ms


## Kombo-Meilenstein: eine ruhige Welle (strong = 100er-Stufen, etwas heller).
func start_wave(strong: bool) -> void:
	_wave_t0 = t_ms
	_wave_strong = strong


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
	var pr := r_out * 1.6
	draw_texture_rect(_plate_tex, Rect2(c - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false)
	# Kiai: ein sehr weicher Hof hinter dem Aussenring (atmet im Takt).
	if kiai > 0.01:
		var kr := r_out * 1.32
		draw_texture_rect(_glow_tex, Rect2(c - Vector2(kr, kr), Vector2(kr, kr) * 2.0), false,
			Color(OUTER_COL.lerp(INNER_COL, 0.5), 0.045 * kiai * (0.75 + 0.25 * beat_env)))
	# Kern: ruhige Flaeche fuer Kombo + Judge, feiner Rand = Entstehungslinie.
	draw_circle(c, u * CORE_K, Color(PLATE_COL, 0.6), true, -1.0, true)
	draw_arc(c, u * CORE_K, 0.0, TAU, 64, Color(1, 1, 1, 0.07 + 0.05 * beat_env), 1.0, true)

	if show_guides:
		_draw_guides(c, u, r_out)
	_draw_rings(c, u, r_in, r_out)
	_draw_wave(c, u, r_out)
	_draw_cursor(c, u, r_in, r_out)

	# Sichtbare Noten: _first rueckt nach, sobald alles davor verblasst ist.
	while _first < notes.size():
		var f = notes[_first]
		var gone := _state[_first] != ST_PENDING and _state[_first] != ST_ARC \
				and t_ms - _state_t[_first] > MISS_FADE_MS * 1.6
		if gone or float(f.end_ms) + 1500.0 < t_ms:
			_first += 1
		else:
			break
	var last := _first
	while last < notes.size() and float(notes[last].time_ms) - t_ms <= preempt:
		last += 1

	# Landeschatten + Bogen-Vorschau + Akkord-Verbindungen unter den Noten.
	for i in range(_first, last):
		_draw_landing(c, u, i)
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
	_draw_marks(u)
	_draw_lights(c, u)
	_draw_cursor_dot(u)


func _ring_col(ring: int) -> Color:
	return OUTER_COL if ring == 1 else INNER_COL


func _draw_guides(c: Vector2, u: float, r_out: float) -> void:
	var r0 := u * R_SPAWN_K
	var lift := 1.0 + 0.5 * kiai
	for k in 8:
		var deg := float(k) * 45.0
		var major := k % 2 == 0
		var col := Color(1, 1, 1, (0.07 if major else 0.035) * lift)
		draw_line(polar(c, deg, r0), polar(c, deg, r_out + u * 0.025), col, 1.0, true)
	# Feine Teilstriche aussen alle 15 Grad.
	for k in 24:
		var deg := float(k) * 15.0
		var long := k % 6 == 0
		var a := r_out + u * 0.012
		var b := a + u * (0.016 if long else 0.008)
		draw_line(polar(c, deg, a), polar(c, deg, b),
			Color(1, 1, 1, (0.16 if long else 0.08) * lift), 1.0, true)


func _draw_rings(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var band := u * 0.034
	# Takt: Ringe werden kurz heller (nie groesser, kein Wackeln). Im Kiai etwas mehr.
	var pulse := beat_env * (0.55 + 0.45 * kiai)
	for r in 2:
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r)
		var g := _ring_glow[r]
		# Trefferzone: breites, sehr leises Band.
		draw_arc(c, rad, 0.0, TAU, 128,
			Color(col, 0.045 + 0.05 * g + 0.035 * pulse + 0.02 * kiai), band, true)
		# Ringlinie: Aussen doppelt (zwei feine Linien), innen einfach -> auch
		# ohne Farbe unterscheidbar.
		var la := 0.34 + 0.34 * g + 0.2 * pulse
		if r == 1:
			draw_arc(c, rad - 2.0, 0.0, TAU, 160, Color(col, la), 1.5, true)
			draw_arc(c, rad + 2.0, 0.0, TAU, 160, Color(col, la * 0.6), 1.0, true)
		else:
			draw_arc(c, rad, 0.0, TAU, 128, Color(col, la), 2.0, true)


## Kombo-Meilenstein: eine feine Welle laeuft vom Kern nach aussen.
func _draw_wave(c: Vector2, u: float, r_out: float) -> void:
	var f := (t_ms - _wave_t0) / WAVE_MS
	if f < 0.0 or f >= 1.0:
		return
	var e := 1.0 - f
	var rad := lerpf(u * CORE_K, r_out + u * 0.05, 1.0 - e * e)
	var a := (0.32 if _wave_strong else 0.22) * e * e
	draw_arc(c, rad, 0.0, TAU, 128, Color(MAX_COL, a), 2.0, true)
	draw_arc(c, rad, 0.0, TAU, 128, Color(MAX_COL, a * 0.25), u * 0.02, true)


func _draw_cursor(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var a0 := _ga(cursor_deg - tol_deg)
	var a1 := _ga(cursor_deg + tol_deg)
	var dim := 0.55 if cursor_in_deadzone else 1.0
	# Leiser Zeiger von der Mitte bis aussen.
	draw_line(polar(c, cursor_deg, u * R_SPAWN_K), polar(c, cursor_deg, r_out - u * 0.03),
		Color(1, 1, 1, 0.06 * dim), 1.5, true)
	for r in 2:
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r).lerp(Color.WHITE, 0.35)
		var g := _ring_glow[r]
		var w := u * 0.046
		draw_arc(c, rad, a0, a1, 24, Color(col, (0.08 + 0.12 * g) * dim), w, true)
		# Mitte der Toleranz etwas dichter: zentriert zielen lohnt (MAX nur dort).
		var ac := _ga(cursor_deg - center_deg)
		var bc := _ga(cursor_deg + center_deg)
		draw_arc(c, rad, ac, bc, 12, Color(col, (0.05 + 0.08 * g) * dim), w, true)
		# Raender der Toleranz als feine Kanten.
		for side in 2:
			var e := cursor_deg + (tol_deg if side == 1 else -tol_deg)
			draw_line(polar(c, e, rad - w * 0.5), polar(c, e, rad + w * 0.5),
				Color(col, (0.20 + 0.15 * g) * dim), 1.0, true)
		# Mittelmarke: kurzer radialer Strich.
		draw_line(polar(c, cursor_deg, rad - w * 0.62), polar(c, cursor_deg, rad + w * 0.62),
			Color(1, 1, 1, (0.55 + 0.35 * g) * dim), 2.5, true)


func _draw_cursor_dot(u: float) -> void:
	if cursor_pos.x < 0.0:
		return
	draw_circle(cursor_pos, u * 0.0055, Color(1, 1, 1, 0.6), true, -1.0, true)
	draw_arc(cursor_pos, u * 0.011, 0.0, TAU, 24, Color(1, 1, 1, 0.22), 1.0, true)


## Landeschatten: dort, wo das Ziel ankommt, liegt sein Umriss auf dem Ring
## und wird mit der Annaeherung deutlicher. Deckt die Note den Umriss genau,
## ist es Zeit. Boegen zeigen ausserdem ihren Weg als feine Spur.
func _draw_landing(c: Vector2, u: float, i: int) -> void:
	if _state[i] != ST_PENDING:
		return
	var n = notes[i]
	var dt := float(n.time_ms) - t_ms
	var win := preempt * 0.7
	if dt < 0.0 or dt > win:
		return
	var k := 1.0 - dt / win
	var rad := ring_radius(n.ring)
	var col := _ring_col(n.ring)
	var a := float(n.angle_deg)
	if n.is_arc:
		var a1 := float(n.end_angle_deg)
		var lo := minf(a, a1)
		var hi := maxf(a, a1)
		draw_arc(c, rad, _ga(lo), _ga(hi), maxi(8, int((hi - lo) / 4.0)),
			Color(col, 0.16 * k), u * ARC_W_K * 0.55, true)
	_outline(polar(c, a, rad), a, n.ring, u * NOTE_K, col, 0.5 * k * k)


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
		alpha = 0.6 * (1.0 - f)
		col = MISS_COL
	if alpha <= 0.002:
		return
	var p := polar(c, float(n.angle_deg), radius_at(n.ring, dt))
	var s := u * NOTE_K * _approach_scale(dt)
	_shape(p, float(n.angle_deg), n.ring, s, col, alpha)


## Eckpunkte der Raute (Spitze radial) in _quad, Groesse s.
func _diamond(p: Vector2, deg: float, s: float) -> void:
	var a := deg_to_rad(deg)
	var ur := Vector2(sin(a), -cos(a)) * s * 1.18
	var ut := Vector2(cos(a), sin(a)) * s * 1.18
	_quad[0] = p + ur
	_quad[1] = p + ut
	_quad[2] = p - ur
	_quad[3] = p - ut


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
		_diamond(p, deg, s)
		draw_colored_polygon(_quad, fill)
		_rim_loop(rim, maxf(2.0, s * 0.2))
		for j in 4:
			_quad_in[j] = p + (_quad[j] - p) * 0.36
		draw_colored_polygon(_quad_in, core)


## Nur der Umriss der Notenform (Landeschatten).
func _outline(p: Vector2, deg: float, ring: int, s: float, col: Color, alpha: float) -> void:
	if alpha <= 0.002:
		return
	if ring == 0:
		draw_arc(p, s, 0.0, TAU, 32, Color(col, alpha), 1.5, true)
	else:
		_diamond(p, deg, s)
		_rim_loop(Color(col, alpha), 1.5)


func _rim_loop(col: Color, w: float) -> void:
	for j in 4:
		_loop[j] = _quad[j]
	_loop[4] = _quad[0]
	_loop[5] = _quad[1]  # Ecke sauber schliessen
	draw_polyline(_loop, col, w, true)


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
	var dropped := st == ST_MISS or st == ST_DROP
	if dropped:
		fade = 0.6 * (1.0 - clampf((t_ms - _state_t[i]) / (MISS_FADE_MS * 1.6), 0.0, 1.0))
		col = MISS_COL
		if fade <= 0.002:
			return
	var dt := t0 - t_ms
	var held := st == ST_ARC
	var rad := ring_radius(n.ring) if (held or dt < 0.0) else radius_at(n.ring, dt)
	var alpha := _approach_alpha(dt) * fade
	# Spitze: bewegt sich ab der Trefferzeit von a0 nach a1.
	var k := clampf((t_ms - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0) if (held or dt < 0.0) else 0.0
	if dropped:
		# Verlorener Bogen bleibt an der Stelle stehen, an der er fiel.
		k = clampf((_state_t[i] - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	# Gleiche Spitze wie OrbitNote.angle_at, aber entfaltet (a1 - a0 = Bogen).
	var tip := lerpf(a0, a1, k)
	var lo := minf(tip, a1)
	var hi := maxf(tip, a1)
	var seg := maxi(8, int(absf(hi - lo) / 3.0))
	# Warnung: Cursor neben dem Bogen -> Spitze wird matter (ruhig, kein Blinken).
	var warn := clampf(arc_warn[n.ring], 0.0, 1.0) if held else 0.0
	var body := col.lerp(MISS_COL, warn * 0.7)
	if hi - lo > 0.3:
		# Weicher Schein, Koerper, helle Mittellinie.
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(body, 0.13 * alpha * (1.6 if held else 1.0)), w * 2.4, true)
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(body.darkened(0.25), 0.78 * alpha), w, true)
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(body.lightened(0.35), (0.75 if held else 0.45) * alpha), maxf(1.5, w * 0.22), true)
	# Bereits abgefahrener Teil: leise Spur.
	if held and absf(tip - a0) > 0.3:
		var tlo := minf(a0, tip)
		var thi := maxf(a0, tip)
		draw_arc(c, rad, _ga(tlo), _ga(thi), maxi(6, int((thi - tlo) / 4.0)), Color(col, 0.12), w * 0.45, true)
	# Ende: offener Ring als Ziel; wird zum Schluss heller und fuellt sich.
	var pe := polar(c, a1, rad)
	var near := 0.0
	if held:
		near = clampf(1.0 - (t1 - t_ms) / 300.0, 0.0, 1.0)
	draw_circle(pe, w * 0.62, Color(col.darkened(0.6).lerp(col, near * 0.6), 0.9 * alpha), true, -1.0, true)
	draw_arc(pe, w * 0.62, 0.0, TAU, 24, Color(col.lightened(0.3 * near), 0.9 * alpha), 2.0, true)
	if near > 0.0:
		draw_arc(pe, w * lerpf(1.25, 0.7, near), 0.0, TAU, 24, Color(col, 0.5 * near), 1.5, true)
	if held:
		var pt := polar(c, tip, rad)
		var gs := u * 0.075
		var tcol := col.lerp(MISS_COL, warn * 0.8)
		draw_texture_rect(_glow_tex, Rect2(pt - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false,
			Color(tcol.lightened(0.3), 0.55 * (1.0 - 0.5 * warn)))
		draw_circle(pt, w * 0.55, Color(tcol.lightened(0.6), 0.95), true, -1.0, true)
		# Richtungspfeil kurz vor der Spitze.
		_chevron(c, rad, tip, signf(a1 - a0), w, Color(1, 1, 1, 0.55))
	else:
		var s := u * NOTE_K * (_approach_scale(dt) if dt > 0.0 else 1.0)
		var hd := tip if dropped else a0
		_shape(polar(c, hd, rad), hd, n.ring, s, col, alpha)
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
	_chev[0] = p - tan * h + nrm * h
	_chev[1] = p
	_chev[2] = p - tan * h - nrm * h
	draw_polyline(_chev, col, 2.0, true)


## Fehltreffer: kleines, ruhiges Kreuz am Ring, blendet aus.
func _draw_marks(u: float) -> void:
	for i in MAX_MARKS:
		var f := (t_ms - _m_t0[i]) / MISS_MARK_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var p := _m_pos[i]
		var h := u * NOTE_K * 0.55
		var a := deg_to_rad(_m_deg[i] + 45.0)
		var d1 := Vector2(cos(a), sin(a)) * h
		var d2 := Vector2(-d1.y, d1.x)
		var col := Color(MISS_X_COL, 0.75 * e)
		draw_line(p - d1, p + d1, col, 2.0, true)
		draw_line(p - d2, p + d2, col, 2.0, true)


func _draw_lights(c: Vector2, u: float) -> void:
	for i in MAX_LIGHTS:
		var f := (t_ms - _l_t0[i]) / HIT_LIGHT_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var col := _l_col[i]
		var q := _l_q[i]
		var p := _l_pos[i]
		var big := 1.0 if q <= 1 else 0.75
		var gs := u * lerpf(0.075, 0.105, f) * big
		draw_texture_rect(_glow_tex, Rect2(p - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false,
			Color(col, (0.5 if q == 0 else (0.38 if q == 1 else 0.24)) * e * e))
		draw_arc(p, u * NOTE_K * lerpf(1.0, 1.55, sqrt(f)) * big, 0.0, TAU, 32,
			Color(col, 0.5 * e * e * big), 2.0, true)
		# Ring leuchtet kurz an der Trefferstelle auf.
		var rad := ring_radius(_l_ring[i])
		var span := 9.0 + 6.0 * f
		draw_arc(c, rad, _ga(_l_deg[i] - span), _ga(_l_deg[i] + span), 12,
			Color(col, 0.42 * e * big), 3.0, true)
		if q == 0:
			# Praezision: zweiter, feiner heller Ring (nur MAX).
			draw_arc(p, u * NOTE_K * lerpf(1.25, 2.0, sqrt(f)), 0.0, TAU, 32,
				Color(MAX_COL, 0.35 * e * e), 1.5, true)
		elif _l_side[i] != 0.0:
			# Frueh = Strich innen am Ring, spaet = aussen (wie die Note lief).
			var off := u * 0.024 * _l_side[i]
			var sc := EARLY_COL if _l_side[i] < 0.0 else LATE_COL
			draw_arc(c, rad + off, _ga(_l_deg[i] - 6.0), _ga(_l_deg[i] + 6.0), 8,
				Color(sc, 0.8 * e), 2.5, true)
