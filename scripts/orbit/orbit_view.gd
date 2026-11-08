class_name OrbitView
extends Control

## Taktkreis-Spielfeld, ein _draw-Durchgang ohne Nodes pro Ziel.
##
## Lesbarkeit zuerst (wie osu!): dunkle Platte, zwei duenne Ringe, Raster nur
## als feine Striche, die HAND als einzige helle Linie (Spitze am Aussenring),
## dazu eine sehr schwache Zielzone (+-Toleranz) hinter der Hand. Innen = kuehle
## Scheibe, aussen = warmes Quadrat (Form UND Farbe). Die naechste Note je
## Ring ist am groessten mit hellem Rand, die uebrigen Noten des Takts sind
## etwas kleiner, die Vorschau (naechster Takt) deutlich blasser. Treffer: kurzer
## Pop (schrumpfende Note + kleiner Rand), Fehler: graue Note mit kleinem X.
## Kein Leuchten, keine Partikel, nichts bewegt sich ausser Hand und Cursor.

const R_INNER_K := OrbitCore.R_INNER_K
const R_OUTER_K := OrbitCore.R_OUTER_K
## Totzone (Bildhoehen) und Kern fuer Kombo/Judge.
const DEADZONE_K := OrbitCore.DEAD_K
const CORE_K := 0.078
## Notengroesse (Bildhoehen): halbe Kante / Radius.
const NOTE_K := 0.030
const OUTER_NOTE_K := 0.028
const PRIMARY_SCALE := 1.22
const CURRENT_SCALE := 0.92
const PREVIEW_SCALE := 0.78
const HAND_OVER_K := 0.055
const TOL_DEFAULT := 22.0

## Ziele ohne Takt-Uhr (Tutorial, Vorschau-Widget): Sichtfenster in ms.
const FALLBACK_WINDOW_MS := 1200.0

const INNER_COL := Color(0.47, 0.78, 0.98)
const OUTER_COL := Color(1.0, 0.70, 0.40)
const MISS_COL := Color(0.50, 0.52, 0.58)
const MAX_COL := Color(1.0, 0.96, 0.86)
const PLATE_COL := Color(0.012, 0.016, 0.028)
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MISS_X_COL := Color(0.90, 0.48, 0.48)
const HAND_COL := Color(0.97, 0.97, 1.0)
const CHORD_EPS_MS := 2.0

## Stufenfarben fuer den Treffer-Pop (CORE .. EDGE).
const TIER_POP := [Color(1.0, 0.96, 0.86), Color(0.85, 0.95, 1.0), Color(0.60, 0.85, 0.65),
		Color(0.95, 0.85, 0.50), Color(0.90, 0.60, 0.45)]
const POP_MS := 170.0
const MISS_MARK_MS := 520.0
const PRESS_MS := 420.0
const MAX_PRESS := 6

const ST_PENDING := 0
const ST_HIT := 1
const ST_MISS := 2
const ST_ARC := 3      # Halte gehalten
const ST_ARC_DONE := 4
const ST_DROP := 5     # Halte verloren

var notes: Array = []
var t_ms := 0.0
var preempt := 1200.0
## Takt-Uhr (Hand + Raster + Vorschau). null = kein Taktkreis (Tutorial).
var clock: OrbitClock = null
var cursor_deg := 0.0
var cursor_pos := Vector2(-1, -1)
var cursor_in_deadzone := false
var tol_deg := TOL_DEFAULT
var center_deg := 9.0
var show_guides := true
var mod_hidden := false
var mod_fade_in := false
var ring_held: Array[bool] = [false, false]
var sel_ring := -1
## Nur fuer Aufrufer, die sie noch setzen (Tutorial): ohne Wirkung.
var beat_env := 0.0
var kiai := 0.0
## Halte-Warnung je Ring: 0 = Cursor auf der Hand, 1 = Halte faellt gleich.
var arc_warn: Array[float] = [0.0, 0.0]

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _state_q := PackedInt32Array()
var _first := 0
var _next: Array[int] = [-1, -1]
var _aim_on := false
var _p_pos := PackedVector2Array()
var _p_t0 := PackedFloat64Array()
var _p_why := PackedStringArray()
var _p_next := 0
var _poly := PackedVector2Array()
var _ring_a: Array[float] = [0.0, 0.0]
var _last_frame_usec := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_fx()


func _reset_fx() -> void:
	_p_pos.resize(MAX_PRESS)
	_p_t0.resize(MAX_PRESS)
	_p_why.resize(MAX_PRESS)
	_p_t0.fill(-1.0e9)
	_p_next = 0


func setup(p_notes: Array) -> void:
	notes = p_notes
	_state.resize(notes.size())
	_state.fill(ST_PENDING)
	_state_t.resize(notes.size())
	_state_t.fill(0.0)
	_state_q.resize(notes.size())
	_state_q.fill(0)
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


## Winkel der Hand (Taktkreis); ohne Uhr der Cursorwinkel.
func hand_deg() -> float:
	return clock.angle_at(t_ms) if clock != null else cursor_deg


## Liegt der Cursor auf der Hand (Winkel, Totzone)? Rein zur Anzeige.
func aim_ok() -> bool:
	return clock != null and not cursor_in_deadzone \
			and OrbitNote.dist_deg(cursor_deg, hand_deg()) <= tol_deg


func state_of(index: int) -> int:
	return _state[index]


# ---------------------------------------------------------------------------
# Ereignisse aus dem Spiel
# ---------------------------------------------------------------------------

func on_judged(index: int, result: Dictionary) -> void:
	if index < 0 or index >= notes.size():
		return
	var n = notes[index]
	var q := int(result.get("quality", 5))
	_state_q[index] = q
	_state_t[index] = t_ms
	if q == 5:
		_state[index] = ST_DROP if (n.is_arc and _state[index] == ST_ARC) else ST_MISS
		return
	_state[index] = ST_ARC_DONE if n.is_arc else ST_HIT


## Halte-Kopf getroffen: Pop am Kopf, die Halte laeuft.
func on_arc_started(index: int, q: int = 1, _dt: float = 0.0) -> void:
	if index < 0 or index >= notes.size():
		return
	_state[index] = ST_ARC
	_state_t[index] = t_ms
	_state_q[index] = q


## Druck ohne Treffer: kleines X an der Cursorposition.
func on_press_missed(deg: float, rho: float, ring: int, reason: String) -> void:
	if reason == "EARLY" or reason == "NONE":
		return
	_p_pos[_p_next] = polar(center(), deg, unit() * maxf(rho, 0.0))
	_p_t0[_p_next] = t_ms
	_p_why[_p_next] = reason
	_p_next = (_p_next + 1) % MAX_PRESS


## Kombo-Meilenstein: ohne Wirkung (keine Zusatzeffekte).
func start_wave(_strong: bool) -> void:
	pass


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_frame_usec) / 1000000.0, 0.0, 0.1)
	_last_frame_usec = now
	for r in 2:
		_ring_a[r] = lerpf(_ring_a[r], 1.0 if ring_held[r] else 0.0, 1.0 - exp(-dt / 0.04))
	queue_redraw()


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _ring_col(ring: int) -> Color:
	return OUTER_COL if ring == 1 else INNER_COL


func _horizon_ms() -> float:
	return clock.bar_ms_at(t_ms) if clock != null else FALLBACK_WINDOW_MS


func _draw() -> void:
	var c := center()
	var u := unit()
	var r_in := ring_radius(0)
	var r_out := ring_radius(1)
	# Platte: dunkle Flaeche, damit Noten und Hand ueber jedem Map-Bild stehen.
	draw_circle(c, r_out + u * 0.075, Color(PLATE_COL, 0.86), true, -1.0, true)
	draw_circle(c, u * CORE_K, Color(PLATE_COL, 0.55), true, -1.0, true)
	_draw_grid(c, u, r_in, r_out)
	for r in 2:
		var rad := r_in if r == 0 else r_out
		draw_arc(c, rad, 0.0, TAU, 96, Color(_ring_col(r), 0.30 + 0.45 * _ring_a[r]),
				1.5 + 1.5 * _ring_a[r], true)
	var hd := hand_deg()
	if clock != null:
		_draw_zone(c, u, r_out, hd)
	_layout()
	var horizon := _horizon_ms()
	var last := _last_visible(horizon)
	# Spaeteste zuerst: die naechste Note liegt obenauf.
	for i in range(last - 1, _first - 1, -1):
		_draw_note(c, u, i, horizon)
	if clock != null:
		_draw_hand(c, u, r_out, hd)
	_draw_presses(u)
	_draw_cursor(c, u)


## Raster: Spalten bei Viertel (Schlag) und Achtel, aussen als Striche, die
## Eins (12 Uhr) etwas laenger; dazu sehr schwache Speichen zwischen den Ringen.
func _draw_grid(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	if clock == null or not show_guides:
		return
	var beats := clock.beats_at(t_ms)
	for i in beats * 2:
		var deg := 360.0 * float(i) / float(beats * 2)
		var whole := i % 2 == 0
		var a0 := r_out + u * 0.018
		var a1 := a0 + u * (0.032 if whole else 0.014)
		var al := 0.30 if whole else 0.12
		if i == 0:
			a1 += u * 0.014
			al = 0.55
		draw_line(polar(c, deg, a0), polar(c, deg, a1), Color(1, 1, 1, al), 1.5 if whole else 1.0, true)
		if whole:
			draw_line(polar(c, deg, r_in), polar(c, deg, r_out), Color(1, 1, 1, 0.045), 1.0, true)


## Schwache Zielzone hinter der Hand (+- Toleranz).
func _draw_zone(c: Vector2, u: float, r_out: float, hd: float) -> void:
	var r0 := u * DEADZONE_K
	var r1 := r_out + u * HAND_OVER_K
	_poly.clear()
	var steps := 10
	for k in steps + 1:
		_poly.append(polar(c, hd - tol_deg + tol_deg * 2.0 * float(k) / float(steps), r1))
	_poly.append(polar(c, hd + tol_deg, r0))
	_poly.append(polar(c, hd - tol_deg, r0))
	draw_colored_polygon(_poly, Color(1, 1, 1, 0.045 if not aim_ok() else 0.085))


func _draw_hand(c: Vector2, u: float, r_out: float, hd: float) -> void:
	var ok := aim_ok()
	var col := Color(HAND_COL, 1.0 if ok else 0.78)
	var r1 := r_out + u * HAND_OVER_K
	draw_line(polar(c, hd, u * DEADZONE_K), polar(c, hd, r1), col, 3.0, true)
	# Spitze: kleines Dreieck nach aussen.
	var tip := polar(c, hd, r1 + u * 0.016)
	var b := polar(c, hd, r1 - u * 0.006)
	var side := Vector2(cos(deg_to_rad(hd)), sin(deg_to_rad(hd))) * u * 0.009
	draw_colored_polygon(PackedVector2Array([tip, b + side, b - side]), col)


func _draw_cursor(_c: Vector2, u: float) -> void:
	if cursor_pos.x < 0.0:
		return
	var ok := aim_ok()
	if ok:
		draw_circle(cursor_pos, u * 0.0075, Color(1, 1, 1, 0.95), true, -1.0, true)
	else:
		draw_arc(cursor_pos, u * 0.0095, 0.0, TAU, 20, Color(MISS_X_COL, 0.9), 2.0, true)
		draw_circle(cursor_pos, u * 0.003, Color(MISS_X_COL, 0.9), true, -1.0, true)


func _draw_presses(u: float) -> void:
	for k in MAX_PRESS:
		var age := t_ms - _p_t0[k]
		if age < 0.0 or age > PRESS_MS:
			continue
		var a := 1.0 - age / PRESS_MS
		var s := u * 0.011
		var p := _p_pos[k]
		var col := Color(MISS_X_COL, a)
		draw_line(p + Vector2(-s, -s), p + Vector2(s, s), col, 2.0, true)
		draw_line(p + Vector2(-s, s), p + Vector2(s, -s), col, 2.0, true)


## Bestimmt _first und die naechste offene Note je Ring.
func _layout() -> void:
	while _first < notes.size():
		var n = notes[_first]
		var st := _state[_first]
		var done := st == ST_HIT or st == ST_MISS or st == ST_ARC_DONE or st == ST_DROP
		if done and t_ms - maxf(float(_state_t[_first]), float(n.end_ms)) > MISS_MARK_MS \
				or (not done and t_ms > float(n.end_ms) + 600.0):
			_first += 1
		else:
			break
	_next = [-1, -1]
	for i in range(_first, notes.size()):
		var n = notes[i]
		if float(n.time_ms) - t_ms > _horizon_ms():
			break
		var st := _state[i]
		if (st == ST_PENDING or st == ST_ARC) and _next[n.ring] < 0 \
				and float(n.end_ms) >= t_ms - 100.0:
			_next[n.ring] = i


func _last_visible(horizon: float) -> int:
	var i := _first
	while i < notes.size() and float(notes[i].time_ms) - t_ms <= horizon:
		i += 1
	return i


func _is_preview(n) -> bool:
	return clock != null and clock.bar_at(float(n.time_ms)) != clock.bar_at(t_ms)


func mod_alpha(dt: float, horizon: float) -> float:
	var f := clampf(dt / maxf(horizon, 1.0), 0.0, 1.0)
	var a := 1.0
	if mod_hidden:
		a *= clampf((f - 0.30) / 0.25, 0.0, 1.0)
	if mod_fade_in:
		a *= clampf((0.55 - f) / 0.15, 0.0, 1.0)
	return a


func _draw_note(c: Vector2, u: float, i: int, horizon: float) -> void:
	var n = notes[i]
	var st := _state[i]
	var dt := float(n.time_ms) - t_ms
	var ring: int = n.ring
	var col := _ring_col(ring)
	var deg := float(n.angle_deg)
	var rad := ring_radius(ring)
	var base := u * (OUTER_NOTE_K if ring == 1 else NOTE_K)
	if st == ST_HIT or st == ST_ARC_DONE:
		var age := t_ms - float(_state_t[i])
		if age < POP_MS:
			var q := clampi(int(_state_q[i]), 0, 4)
			var f := age / POP_MS
			var at := polar(c, float(n.end_angle_deg) if st == ST_ARC_DONE else deg, rad)
			_shape(at, deg, ring, base * (1.0 - 0.55 * f), Color(TIER_POP[q], 1.0 - f), true)
			_shape(at, deg, ring, base * (1.0 + 0.7 * f), Color(TIER_POP[q], 0.8 * (1.0 - f)), false)
		return
	if st == ST_MISS or st == ST_DROP:
		var age := t_ms - float(_state_t[i])
		if age < MISS_MARK_MS:
			var a := 1.0 - age / MISS_MARK_MS
			var at := polar(c, deg if st == ST_MISS else float(n.pointer_at(float(_state_t[i]))), rad)
			_shape(at, deg, ring, base * 0.8, Color(MISS_COL, 0.55 * a), true)
			var s := base * 0.7
			draw_line(at + Vector2(-s, -s), at + Vector2(s, s), Color(MISS_X_COL, a), 2.0, true)
			draw_line(at + Vector2(-s, s), at + Vector2(s, -s), Color(MISS_X_COL, a), 2.0, true)
		return
	# Offene Note (oder laufende Halte).
	var prev := _is_preview(n)
	var primary := _next[ring] == i
	var phase := clampf(1.0 - dt / maxf(horizon, 1.0), 0.0, 1.0)
	var alpha: float
	var scale: float
	if prev:
		alpha = 0.10 + 0.20 * phase
		scale = PREVIEW_SCALE
	elif primary:
		alpha = 1.0
		scale = PRIMARY_SCALE
	else:
		alpha = 0.62 + 0.25 * phase
		scale = CURRENT_SCALE
	alpha *= mod_alpha(maxf(dt, 0.0), horizon)
	if alpha <= 0.01:
		return
	if n.is_arc:
		_draw_hold(c, u, i, n, col, base * scale, alpha, prev, primary, st == ST_ARC)
		return
	var p := polar(c, deg, rad)
	_chord_stem(c, i, n, alpha * 0.5, u)
	_shape(p, deg, ring, base * scale, Color(col, alpha), true)
	if primary and not prev:
		_shape(p, deg, ring, base * scale * 1.0, Color(1, 1, 1, 0.95), false)


func _draw_hold(c: Vector2, u: float, i: int, n, col: Color, size_px: float, alpha: float,
		prev: bool, primary: bool, held: bool) -> void:
	var rad := ring_radius(n.ring)
	var a0 := float(n.angle_deg)
	var total := float(n.end_angle_deg) - a0
	var span := total
	var w := u * 0.016
	var from_deg := a0
	if held:
		var f := clampf((t_ms - float(n.time_ms)) / maxf(float(n.duration_ms()), 1.0), 0.0, 1.0)
		from_deg = a0 + total * f
		span = total * (1.0 - f)
	if absf(span) > 0.5:
		draw_arc(c, rad, _ga(from_deg), _ga(from_deg + span), maxi(int(absf(span) / 6.0), 4),
				Color(col, alpha * (0.85 if held else 0.40)), w, true)
	# Kopf (offen) bzw. Spitze an der Hand (gehalten).
	var head_deg := from_deg if held else a0
	var p := polar(c, head_deg, rad)
	_chord_stem(c, i, n, alpha * 0.5, u)
	_shape(p, head_deg, n.ring, size_px, Color(col, alpha), true)
	if (primary and not prev) or held:
		_shape(p, head_deg, n.ring, size_px, Color(1, 1, 1, 0.95), false)
	# Ende: kleiner Strich.
	var e := polar(c, float(n.end_angle_deg), rad)
	draw_circle(e, w * 0.55, Color(col, alpha * 0.8), true, -1.0, true)
	if held and arc_warn[n.ring] > 0.05:
		draw_arc(p, size_px * 1.45, 0.0, TAU, 20, Color(MISS_X_COL, minf(arc_warn[n.ring], 1.0)), 2.0, true)


## Akzent: duenne Verbindung zwischen der inneren und der aeusseren Note.
func _chord_stem(c: Vector2, i: int, n, alpha: float, u: float) -> void:
	if n.ring != 0 or i + 1 >= notes.size():
		return
	var m = notes[i + 1]
	if m.ring == 1 and absf(float(m.time_ms) - float(n.time_ms)) <= CHORD_EPS_MS:
		var d := float(n.angle_deg)
		draw_line(polar(c, d, ring_radius(0)), polar(c, d, ring_radius(1)),
				Color(1, 1, 1, alpha * 0.6), 2.0, true)


## Innen: Scheibe, aussen: Quadrat (an der Tangente ausgerichtet).
func _shape(p: Vector2, deg: float, ring: int, s: float, col: Color, filled: bool) -> void:
	if ring == 0:
		if filled:
			draw_circle(p, s, col, true, -1.0, true)
		else:
			draw_arc(p, s, 0.0, TAU, 28, col, 2.0, true)
		return
	var a := deg_to_rad(deg)
	var rad_v := Vector2(sin(a), -cos(a)) * s
	var tan_v := Vector2(cos(a), sin(a)) * s
	_poly.clear()
	_poly.append(p + rad_v + tan_v)
	_poly.append(p + rad_v - tan_v)
	_poly.append(p - rad_v - tan_v)
	_poly.append(p - rad_v + tan_v)
	if filled:
		draw_colored_polygon(_poly, col)
	else:
		_poly.append(_poly[0])
		draw_polyline(_poly, col, 2.0, true)
