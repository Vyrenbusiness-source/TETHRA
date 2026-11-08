class_name OrbitView
extends Control

## Orbit-Spielfeld: zwei Ringe um die Bildschirmmitte. Alles in EINEM
## _draw-Durchgang (keine Nodes pro Note, keine Allokationen pro Frame).
## Lesbarkeit vor Glanz: ruhige Farben, harte Formen, kein Leuchten, kein Wackeln.
##
## Winkel: Grad, 0 = oben, im Uhrzeigersinn (wie OrbitNote).
## Innen = Ring 0: VOLLE Scheibe, kuehles Blau, kleiner.
## Aussen = Ring 1: HOHLE Raute mit dickem Rand, warmes Bernstein, groesser.
## Getrennte Bahnen, nie ueber einen Trefferring: Innen-Ziele fliegen vom Kern
## nach aussen zum Innenring, Aussen-Ziele von aussen nach innen zum Aussenring.
## Konstante Geschwindigkeit (Anflugzeit = Scroll Speed), genau zur Trefferzeit
## auf dem Ring, wo ihr Umriss schon wartet. Der Ring wird durch Zeigen
## gewaehlt: der Cursor zeigt nur auf dem gewaehlten Ring sein Toleranzfenster.

## Ringradien und Spawn-Radien relativ zur Bildschirmhoehe.
const R_INNER_K := OrbitCore.R_INNER_K
const R_OUTER_K := OrbitCore.R_OUTER_K
const R_SPAWN_K := 0.085
## Aussen-Ziele entstehen aussen (am Rand des Feldes) und fliegen nach innen.
const R_OUTER_SPAWN_K := 0.455
## Dunkler Kern (Kombo + Judge); Innen-Ziele entstehen an seinem Rand.
const CORE_K := 0.078
## Totzone um die Mitte (Cursor dort = Winkel bleibt stehen).
const DEADZONE_K := 0.045
## Notengroesse (Radius) relativ zur Hoehe: innen Scheibe, aussen Raute
## (Halbdiagonale x DIAMOND_K, also sichtbar groesser). Anflug startet kleiner.
const NOTE_K := 0.030
const OUTER_NOTE_K := 0.031
const DIAMOND_K := 1.3
const APPROACH_SCALE := 0.55
## Spaetere Ziele (nicht das naechste ihres Rings) sind blasser.
const FAR_ALPHA := 0.38
## Dichte Stellen: ein spaeteres Ziel schrumpft, statt ein frueheres zu
## ueberdecken (hoechstens auf FIT_MIN), mit FIT_GAP_K * unit() Luft dazwischen.
## Das naechste Ziel je Ring bleibt immer voll gross. Messung: docs/modes/orbit_qa.md.
const FIT_MIN := 0.3
const FIT_GAP_K := 0.004
const ARC_W_K := 0.026
## Winkel-Toleranz fuer die Cursor-Anzeige (Fallback, Core liefert den echten Wert).
const TOL_DEFAULT := 22.0
## So weit vor der Trefferzeit zeigt der Zeiger an, ob er auf dem Ziel steht.
const AIM_LOOKAHEAD_MS := 650.0
## HD: ab diesem Anflug-Fortschritt verblasst ein Ziel, bei HD_GONE ist es weg
## (letzte ~40 % des Wegs; die letzten 8 % bleiben leer = Gedaechtnis).
const HD_FADE_FROM := 0.60
const HD_GONE := 0.92
## FI: Ziel unsichtbar bis FI_FROM, dann kurzes Einblenden bis FI_FULL.
const FI_FROM := 0.50
const FI_FULL := 0.62

const INNER_COL := Color(0.47, 0.78, 0.98)
const OUTER_COL := Color(1.0, 0.70, 0.40)
const MISS_COL := Color(0.50, 0.52, 0.58)
const MAX_COL := Color(1.0, 0.96, 0.86)
const PLATE_COL := Color(0.012, 0.016, 0.028)
## Frueh/spaet: kuehl/warm, gedeckt.
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MISS_X_COL := Color(0.90, 0.48, 0.48)

const HIT_LIGHT_MS := 240.0
const MISS_FADE_MS := 260.0
## Fehltreffer-Marke (kleines X am Ring) bleibt etwas laenger stehen.
const MISS_MARK_MS := 560.0
## Kombo-Meilenstein: eine Welle vom Kern nach aussen.
const WAVE_MS := 760.0
const CHORD_EPS_MS := 2.0
## Ringpuffer fuer Effekte (keine Allokation im Spiel).
const MAX_LIGHTS := 24
const MAX_MARKS := 12

## Zustand je Note (fuer die Darstellung).
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
## Halbbreite der Mitte, in der CORE moeglich ist (OrbitCore.CENTER_DEG).
var center_deg := TOL_DEFAULT * 0.5
var show_guides := true
## Orbit-Mods (OrbitCore.ORBIT_MODS): HD blendet Ziele vor dem Ring aus,
## FI blendet sie erst spaet ein. Rein visuell, die Wertung bleibt gleich.
var mod_hidden := false
var mod_fade_in := false
var ring_held: Array[bool] = [false, false]
## Vom Cursor gewaehlter Ring (-1 = unbekannt, dann zeigen beide Ringe ihr Fenster).
var sel_ring := -1
## Takt-Puls 0..1 (BeatClock.beat_env, nach Intensitaet gewichtet) und Kiai 0..1.
var beat_env := 0.0
var kiai := 0.0
## Bogen-Warnung je Ring: 0 = Cursor auf dem Bogen, 1 = Bogen faellt gleich.
var arc_warn: Array[float] = [0.0, 0.0]

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _first := 0
## Naechstes offenes (oder gehaltenes) Ziel je Ring in diesem Frame, -1 = keins.
var _next: Array[int] = [-1, -1]
## Zeiger-Ausrichtung je Ring: 0 daneben, 1 in der Toleranz, 2 mittig (CORE).
var _aim: Array[int] = [0, 0]
# Licht-Pulse (Ringpuffer): Position, Winkel, Ring, Farbe, Start, Stufe, Seite.
var _l_pos := PackedVector2Array()
var _l_deg := PackedFloat32Array()
var _l_ring := PackedInt32Array()
var _l_col := PackedColorArray()
var _l_t0 := PackedFloat64Array()
var _l_q := PackedInt32Array()
var _l_side := PackedFloat32Array()  # -1 frueh, +1 spaet, 0 ohne Marke
var _l_next := 0
# Fehldruck-Marken (Ringpuffer): Ort, Winkel, Ring, Grund, Start.
const MAX_PRESS := 6
const PRESS_MS := 480.0
var _p_pos := PackedVector2Array()
var _p_deg := PackedFloat32Array()
var _p_ring := PackedInt32Array()
var _p_why := PackedStringArray()
var _p_t0 := PackedFloat64Array()
var _p_next := 0
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
## Groessenfaktor (FIT_MIN..1) je sichtbarem Ziel in diesem Frame (layout_frame).
var _fit := {}
## Stapel-Hinweis: Radius (px) des Rahmens eines Ziels, dessen Mitte unter einem
## frueheren Ziel liegt (gleicher Winkel kurz danach). Der Rahmen ragt ueber das
## verdeckende Ziel hinaus: ein Ring je verdecktem Ziel.
var _halo := {}
## Aus = alte Darstellung (alle Ziele volle Groesse), nur fuer Messungen.
var fit_enabled := true
var _plate_tex: GradientTexture2D
var _last_frame_usec := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Abdunklung hinter dem Spielfeld (kein Leuchten): fast deckend bis knapp
	# ausserhalb des Aussenrings, dann kurzer Uebergang zum Map-Bild.
	_plate_tex = _radial_tex([0.0, 0.62, 0.78, 1.0],
		[Color(PLATE_COL, 0.93), Color(PLATE_COL, 0.90), Color(PLATE_COL, 0.6), Color(PLATE_COL, 0.0)])
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
	_p_pos.resize(MAX_PRESS)
	_p_deg.resize(MAX_PRESS)
	_p_ring.resize(MAX_PRESS)
	_p_why.resize(MAX_PRESS)
	_p_t0.resize(MAX_PRESS)
	_p_t0.fill(-1.0e12)
	_p_next = 0


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


## Startradius der Bahn eines Rings (innen: Kernrand, aussen: Feldrand).
func spawn_radius(ring: int) -> float:
	return unit() * (R_OUTER_SPAWN_K if ring == 1 else R_SPAWN_K)


## Radius eines Ziels dt_ms vor seiner Trefferzeit: linear (konstante
## Geschwindigkeit), genau bei dt = 0 auf dem Ring, danach weiter nach aussen.
func radius_at(ring: int, dt_ms: float) -> float:
	var r0 := spawn_radius(ring)
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


## Zeiger-Ausrichtung je Ring (0 daneben, 1 Toleranz, 2 mittig), Stand letzter Frame.
func aim_state(ring: int) -> int:
	return _aim[clampi(ring, 0, 1)]


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


## Bogen-Kopf getroffen: Licht mit der Stufe und Frueh/Spaet des Kopfes.
func on_arc_started(index: int, q: int = 1, dt: float = 0.0) -> void:
	if index < 0 or index >= notes.size():
		return
	_state[index] = ST_ARC
	_state_t[index] = t_ms
	var n = notes[index]
	_light(float(n.angle_deg), n.ring, q, dt)


func _light(deg: float, ring: int, q: int, dt: float) -> void:
	# Ringfarbe bleibt (innen/aussen auch im Licht erkennbar). CORE: helles
	# Creme mit Doppelrahmen; SHARP: Ringfarbe; schwaechere Stufen matter.
	# Jede Stufe unter CORE zeigt frueh (Strich innen) oder spaet (aussen).
	var i := _l_next
	_l_next = (_l_next + 1) % MAX_LIGHTS
	_l_pos[i] = polar(center(), deg, ring_radius(ring))
	_l_deg[i] = deg
	_l_ring[i] = ring
	var col := _ring_col(ring)
	if q == 0:
		col = MAX_COL
	elif q == 1:
		col = col.lightened(0.15)
	else:
		col = col.lerp(MISS_COL, 0.45)
	_l_col[i] = col
	_l_t0[i] = t_ms
	_l_q[i] = q
	_l_side[i] = (signf(dt) if q >= 1 and absf(dt) >= 1.0 else 0.0)


func _mark(pos: Vector2, deg: float) -> void:
	var i := _m_next
	_m_next = (_m_next + 1) % MAX_MARKS
	_m_pos[i] = pos
	_m_deg[i] = deg
	_m_t0[i] = t_ms


## Fehldruck am Cursor (rho in Bildhoehen). reason: ANGLE / RING / EARLY / NONE
## (OrbitCore.press_missed). Die Marke steht dort, wo gedrueckt wurde.
func on_press_missed(deg: float, rho: float, ring: int, reason: String) -> void:
	var i := _p_next
	_p_next = (_p_next + 1) % MAX_PRESS
	_p_pos[i] = polar(center(), deg, rho * unit())
	_p_deg[i] = deg
	_p_ring[i] = ring
	_p_why[i] = reason
	_p_t0[i] = t_ms


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

	# Abdunklung hinter dem Spielfeld: Lesbarkeit ueber jedem Map-Bild.
	var pr := r_out * 1.5
	draw_texture_rect(_plate_tex, Rect2(c - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false)
	# Kern: ruhige Flaeche fuer Kombo + Judge, feiner Rand = Entstehungslinie.
	draw_circle(c, u * CORE_K, Color(PLATE_COL, 0.7), true, -1.0, true)
	draw_arc(c, u * CORE_K, 0.0, TAU, 64, Color(INNER_COL, 0.10 + 0.06 * beat_env), 1.0, true)

	var last := layout_frame()

	if show_guides:
		_draw_guides(c, u, r_out)
	_draw_rings(c, u, r_in, r_out)
	_draw_wave(c, u, r_out)
	_draw_cursor(c, u, r_in, r_out)

	# Landeumriss + Bogen-Vorschau + Akkord-Verbindungen unter den Noten.
	for i in range(_first, last):
		_draw_landing(c, u, i)
	# Spaetere zuerst: die naechste Note liegt immer obenauf.
	for i in range(last - 1, _first - 1, -1):
		var n = notes[i]
		if n.is_arc:
			_draw_arc_note(c, u, i, n)
		else:
			_draw_tap(c, u, i, n)
	_draw_marks(u)
	_draw_lights(c, u)
	_draw_presses(u)
	_draw_cursor_dot(u)


## Sichtbare Ziele dieses Frames (zur Zeit t_ms): _first, _next und die
## Groessen (_fit). Gibt das Ende des sichtbaren Bereichs zurueck. Oeffentlich
## fuer Tests (Ueberdeckungs-Messung ohne Zeichnen).
func layout_frame() -> int:
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
	# Naechstes Ziel je Ring (gehaltener Bogen zaehlt als naechstes).
	_next[0] = -1
	_next[1] = -1
	for i in range(_first, last):
		var st := _state[i]
		if st != ST_PENDING and st != ST_ARC:
			continue
		var rg: int = notes[i].ring
		if _next[rg] < 0:
			_next[rg] = i
		if _next[0] >= 0 and _next[1] >= 0:
			break
	_fit_sizes(last)
	return last


## Spaetere Ziele (Zeitreihenfolge) werden so weit verkleinert, dass sie kein
## frueheres anfliegendes Ziel ueberdecken; Akkord-Partner zaehlen nicht.
func _fit_sizes(last: int) -> void:
	_fit.clear()
	_halo.clear()
	var c := center()
	var gap := unit() * FIT_GAP_K
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	var tim := PackedFloat64Array()
	for i in range(_first, last):
		if _state[i] != ST_PENDING:
			continue
		var n = notes[i]
		var dt := float(n.time_ms) - t_ms
		var p := draw_pos(c, i, t_ms)
		var full := _base_radius(i, t_ms)
		var k := 1.0
		if fit_enabled and dt > 0.0 and _next[n.ring] != i and full > 0.0:
			var r := full
			var halo := 0.0
			for j in pos.size():
				if absf(tim[j] - float(n.time_ms)) <= CHORD_EPS_MS:
					continue
				var d := p.distance_to(pos[j])
				r = minf(r, d - rad[j] - gap)
				if d < rad[j]:
					halo = maxf(halo, d + rad[j] + gap * 1.5)
			k = clampf(r / full, FIT_MIN, 1.0)
			if halo > 0.0:
				_halo[i] = halo
		_fit[i] = k
		pos.append(p)
		rad.append(full * k)
		tim.append(float(n.time_ms))


## Stapel-Hinweis-Radius (px) von Ziel i in diesem Frame, 0 = keiner.
func halo_of(i: int) -> float:
	return float(_halo.get(i, 0.0))


## Rahmen um ein verdecktes Ziel (Radius rp in px, wie draw_radius).
func _draw_halo(p: Vector2, deg: float, ring: int, rp: float, col: Color, alpha: float) -> void:
	var s := rp if ring == 0 else rp / (DIAMOND_K * 0.85)
	_outline(p, deg, ring, s, col, 0.85 * alpha, 1.5)


## Groessenfaktor von Ziel i in diesem Frame (1 = volle Anfluggroesse).
func fit_of(i: int) -> float:
	return float(_fit.get(i, 1.0))


func _ring_col(ring: int) -> Color:
	return OUTER_COL if ring == 1 else INNER_COL


func _draw_guides(c: Vector2, u: float, r_out: float) -> void:
	var lift := 1.0 + 0.6 * kiai
	for k in 8:
		var deg := float(k) * 45.0
		var major := k % 2 == 0
		var col := Color(1, 1, 1, (0.06 if major else 0.03) * lift)
		draw_line(polar(c, deg, u * R_SPAWN_K), polar(c, deg, r_out + u * 0.025), col, 1.0, true)
	# Feine Teilstriche aussen alle 15 Grad; im Kiai-Takt etwas heller.
	for k in 24:
		var deg := float(k) * 15.0
		var long := k % 6 == 0
		var a := r_out + u * 0.024
		var b := a + u * (0.016 if long else 0.008)
		draw_line(polar(c, deg, a), polar(c, deg, b),
			Color(1, 1, 1, ((0.18 if long else 0.09) + 0.08 * beat_env * kiai) * lift), 1.0, true)


func _draw_rings(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var band := u * 0.036
	# Takt: Ringe werden kurz heller (nie groesser, kein Wackeln). Im Kiai etwas mehr.
	var pulse := beat_env * (0.55 + 0.45 * kiai)
	for r in 2:
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r)
		var g := _ring_glow[r]
		# Trefferzone: breites, leises Band; der gewaehlte Ring etwas deutlicher.
		var chosen := 0.05 if r == sel_ring else 0.0
		draw_arc(c, rad, 0.0, TAU, 128,
			Color(col, 0.05 + chosen + 0.06 * g + 0.04 * pulse + 0.02 * kiai), band, true)
		# Ringlinie: aussen doppelt, innen einfach -> auch ohne Farbe unterscheidbar.
		var la := 0.42 + 0.3 * g + 0.2 * pulse
		if r == 1:
			draw_arc(c, rad - 2.5, 0.0, TAU, 160, Color(col, la), 2.0, true)
			draw_arc(c, rad + 2.5, 0.0, TAU, 160, Color(col, la * 0.6), 1.0, true)
		else:
			draw_arc(c, rad, 0.0, TAU, 128, Color(col, la), 2.0, true)


## Kombo-Meilenstein: eine feine Welle laeuft vom Kern nach aussen.
func _draw_wave(c: Vector2, u: float, r_out: float) -> void:
	var f := (t_ms - _wave_t0) / WAVE_MS
	if f < 0.0 or f >= 1.0:
		return
	var e := 1.0 - f
	var rad := lerpf(u * CORE_K, r_out + u * 0.05, 1.0 - e * e)
	var a := (0.34 if _wave_strong else 0.22) * e * e
	draw_arc(c, rad, 0.0, TAU, 128, Color(MAX_COL, a), 2.0, true)
	if _wave_strong:
		draw_arc(c, rad - u * 0.012, 0.0, TAU, 128, Color(MAX_COL, a * 0.5), 1.0, true)


## Zielwinkel des naechsten Ziels auf Ring r (gehaltener Bogen: seine Spitze).
func _target_deg(r: int) -> float:
	var n = notes[_next[r]]
	return float(n.angle_at(t_ms)) if _state[_next[r]] == ST_ARC else float(n.angle_deg)


func _draw_cursor(c: Vector2, u: float, r_in: float, r_out: float) -> void:
	var dim := 0.55 if cursor_in_deadzone else 1.0
	# Ausrichtung: steht der Zeiger auf dem naechsten Ziel des Rings?
	for r in 2:
		_aim[r] = 0
		var i := _next[r]
		if i < 0 or cursor_in_deadzone or (sel_ring >= 0 and r != sel_ring):
			continue
		if _state[i] != ST_ARC and float(notes[i].time_ms) - t_ms > AIM_LOOKAHEAD_MS:
			continue
		var e := OrbitNote.dist_deg(cursor_deg, _target_deg(r))
		if e <= tol_deg:
			_aim[r] = 2 if e <= center_deg else 1
	# Ringgrenze: leise Linie nahe am Cursor, dort wechselt der Ring (mit Hysterese).
	var split := u * OrbitCore.RING_SPLIT_K
	draw_arc(c, split, _ga(cursor_deg - 28.0), _ga(cursor_deg + 28.0), 16,
		Color(1, 1, 1, 0.10 * dim), 1.0, true)
	var a0 := _ga(cursor_deg - tol_deg)
	var a1 := _ga(cursor_deg + tol_deg)
	var ac := _ga(cursor_deg - center_deg)
	var bc := _ga(cursor_deg + center_deg)
	for r in 2:
		if sel_ring >= 0 and r != sel_ring:
			continue
		var rad := r_out if r == 1 else r_in
		var col := _ring_col(r)
		var g := _ring_glow[r]
		var w := u * 0.05
		var on := _aim[r]
		# Toleranzfenster: Winkel (Bogenlaenge) UND Ring (Bandbreite) in einer Form.
		var fa := (0.10 + 0.10 * g + (0.16 if on > 0 else 0.0)) * dim
		draw_arc(c, rad, a0, a1, 24, Color(col.lerp(Color.WHITE, 0.3), fa), w, true)
		# Mitte (CORE-Zone) etwas dichter: zentriert zielen lohnt.
		draw_arc(c, rad, ac, bc, 12, Color(col.lerp(Color.WHITE, 0.3), (0.05 + 0.06 * g) * dim), w, true)
		# Raender der Toleranz als feine Kanten.
		for side in 2:
			var ed := cursor_deg + (tol_deg if side == 1 else -tol_deg)
			draw_line(polar(c, ed, rad - w * 0.5), polar(c, ed, rad + w * 0.5),
				Color(col, (0.30 + 0.2 * g + 0.25 * float(on)) * dim), 1.0 + float(on), true)
		# Mittelmarke: radialer Strich; mittig auf dem Ziel = laenger, Creme, Klammern.
		var mc := MAX_COL if on == 2 else Color.WHITE
		var ml := w * (0.62 if on == 0 else 0.85)
		draw_line(polar(c, cursor_deg, rad - ml), polar(c, cursor_deg, rad + ml),
			Color(mc, (0.6 + 0.3 * g + 0.1 * float(on)) * dim), 2.5 if on == 0 else 4.0, true)
		if on == 2:
			for side in 2:
				var ed := cursor_deg + (center_deg if side == 1 else -center_deg)
				draw_line(polar(c, ed, rad - w * 0.7), polar(c, ed, rad + w * 0.7),
					Color(MAX_COL, 0.7 * dim), 2.0, true)
		# Faden vom Cursorpunkt zum Ring: so sieht man, wohin der Druck zaehlt.
		if cursor_pos.x >= 0.0:
			var on_ring := polar(c, cursor_deg, rad)
			if cursor_pos.distance_to(on_ring) > u * 0.012:
				draw_line(cursor_pos, on_ring, Color(col, 0.35 * dim), 1.0, true)


func _draw_cursor_dot(u: float) -> void:
	if cursor_pos.x < 0.0:
		return
	draw_circle(cursor_pos, u * 0.0055, Color(1, 1, 1, 0.7), true, -1.0, true)
	draw_arc(cursor_pos, u * 0.011, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0, true)


## Landeumriss: dort, wo das Ziel ankommt, liegt sein Umriss auf dem Ring
## und wird mit der Annaeherung deutlicher. Deckt die Note den Umriss genau,
## ist es Zeit. Nur das naechste Ziel je Ring zeigt ihn kraeftig.
func _draw_landing(c: Vector2, u: float, i: int) -> void:
	if _state[i] != ST_PENDING:
		return
	var n = notes[i]
	var dt := float(n.time_ms) - t_ms
	var win := preempt * 0.8
	if dt < 0.0 or dt > win:
		return
	var ma := mod_alpha(dt)
	if ma <= 0.002:
		return
	var k := (1.0 - dt / win) * sqrt(ma)
	var nxt := _next[n.ring] == i
	var rad := ring_radius(n.ring)
	var col := _ring_col(n.ring)
	var a := float(n.angle_deg)
	if n.is_arc:
		var a1 := float(n.end_angle_deg)
		var lo := minf(a, a1)
		var hi := maxf(a, a1)
		var seg := maxi(8, int((hi - lo) / 4.0))
		var w := u * ARC_W_K
		# Weg des Bogens als zwei feine Schienen auf dem Ring.
		draw_arc(c, rad - w * 0.5, _ga(lo), _ga(hi), seg, Color(col, 0.22 * k), 1.0, true)
		draw_arc(c, rad + w * 0.5, _ga(lo), _ga(hi), seg, Color(col, 0.22 * k), 1.0, true)
	var s := _note_size(u, n.ring)
	_outline(polar(c, a, rad), a, n.ring, s, col, (0.75 if nxt else 0.3) * k * k, 2.0 if nxt else 1.0)


## Bogen-Spitze zur Zeit t (wie OrbitNote.angle_at; raw = entfaltet, a1 - a0 = Bogen).
func arc_tip_deg(n, t: float, raw: bool = false) -> float:
	var t0 := float(n.time_ms)
	var t1 := float(n.end_ms)
	var k := clampf((t - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	var tip := lerpf(float(n.angle_deg), float(n.end_angle_deg), k)
	return tip if raw else fposmod(tip, 360.0)


## Gezeichneter Mittelpunkt von Ziel i (Kopf) zur Zeit t, solange es anfliegt.
func draw_pos(c: Vector2, i: int, t: float) -> Vector2:
	var n = notes[i]
	return polar(c, float(n.angle_deg), radius_at(n.ring, float(n.time_ms) - t))


## Gezeichneter Radius von Ziel i (Kopf) zur Zeit t (Raute: mittlerer Radius),
## mit dem Groessenfaktor des letzten layout_frame().
func draw_radius(i: int, t: float) -> float:
	return _base_radius(i, t) * fit_of(i)


func _base_radius(i: int, t: float) -> float:
	var n = notes[i]
	var s := _note_size(unit(), n.ring) * _approach_scale(float(n.time_ms) - t)
	return s if n.ring == 0 else s * DIAMOND_K * 0.85


## Einblend-Deckkraft von Ziel i zur Zeit t (ohne Tiefe).
func draw_alpha(i: int, t: float) -> float:
	return _approach_alpha(float(notes[i].time_ms) - t)


## Fortschritt des Anflugs 0 (Spawn) .. 1 (Ring).
func _progress(dt: float) -> float:
	return clampf(1.0 - dt / maxf(preempt, 1.0), 0.0, 1.0)


## Einblenden im ersten Siebtel des Anflugs (kein Aufploppen), mal Mod-Faktor.
func _approach_alpha(dt: float) -> float:
	return clampf(_progress(dt) / 0.14, 0.0, 1.0) * mod_alpha(dt)


## Sichtbarkeit durch HD/FI (1 ohne Mods). dt = Zeit bis zum Ring.
func mod_alpha(dt: float) -> float:
	var p := _progress(dt)
	var a := 1.0
	if mod_hidden:
		a *= 1.0 - smoothstep(HD_FADE_FROM, HD_GONE, p)
	if mod_fade_in:
		a *= smoothstep(FI_FROM, FI_FULL, p)
	return a


## Tiefe: spaetere Ziele blasser, das naechste ihres Rings voll.
func _depth(dt: float, nxt: bool) -> float:
	return 1.0 if nxt else lerpf(FAR_ALPHA, 0.9, _progress(dt))


func _approach_scale(dt: float) -> float:
	return lerpf(APPROACH_SCALE, 1.0, _progress(dt))


func _note_size(u: float, ring: int) -> float:
	return u * (OUTER_NOTE_K if ring == 1 else NOTE_K)


func _draw_tap(c: Vector2, u: float, i: int, n) -> void:
	var st := _state[i]
	if st == ST_HIT:
		return
	var dt := float(n.time_ms) - t_ms
	var nxt := _next[n.ring] == i
	var alpha := _approach_alpha(dt) * _depth(dt, nxt)
	var col := _ring_col(n.ring)
	if st == ST_MISS:
		var f := clampf((t_ms - _state_t[i]) / MISS_FADE_MS, 0.0, 1.0)
		alpha = 0.6 * (1.0 - f)
		col = MISS_COL
		nxt = false
	if alpha <= 0.002:
		return
	var p := polar(c, float(n.angle_deg), radius_at(n.ring, dt))
	var s := _note_size(u, n.ring) * _approach_scale(dt) * (fit_of(i) if st == ST_PENDING else 1.0)
	_shape(p, float(n.angle_deg), n.ring, s, col, alpha)
	if st == ST_PENDING and halo_of(i) > 0.0:
		_draw_halo(p, float(n.angle_deg), n.ring, halo_of(i), col, maxf(alpha, 0.5))
	if nxt and dt > 0.0:
		# Das naechste Ziel: feiner heller Rahmen.
		_outline(p, float(n.angle_deg), n.ring, s * 1.28, Color.WHITE, 0.4 * alpha, 1.5)


## Eckpunkte der Raute (Spitze radial) in _quad, Groesse s.
func _diamond(p: Vector2, deg: float, s: float) -> void:
	var a := deg_to_rad(deg)
	var ur := Vector2(sin(a), -cos(a)) * s * DIAMOND_K
	var ut := Vector2(cos(a), sin(a)) * s * DIAMOND_K
	_quad[0] = p + ur
	_quad[1] = p + ut
	_quad[2] = p - ur
	_quad[3] = p - ut


## Notenform. Innen: volle helle Scheibe mit dunklem Punkt. Aussen: hohle,
## groessere Raute (dunkle Flaeche, dicker Rand, heller Kern). Damit
## unterscheiden sich die Ringe in Form, Fuellung, Farbe und Groesse.
func _shape(p: Vector2, deg: float, ring: int, s: float, col: Color, alpha: float) -> void:
	if ring == 0:
		draw_circle(p, s, Color(col, alpha), true, -1.0, true)
		draw_arc(p, s, 0.0, TAU, 32, Color(col.lightened(0.35), alpha), maxf(1.5, s * 0.12), true)
		draw_circle(p, s * 0.3, Color(PLATE_COL, 0.85 * alpha), true, -1.0, true)
	else:
		_diamond(p, deg, s)
		draw_colored_polygon(_quad, Color(PLATE_COL.lerp(col, 0.12), 0.94 * alpha))
		_rim_loop(Color(col, alpha), maxf(3.0, s * 0.26))


## Nur der Umriss der Notenform (Landeumriss, Rahmen des naechsten Ziels).
func _outline(p: Vector2, deg: float, ring: int, s: float, col: Color, alpha: float, w: float = 1.5) -> void:
	if alpha <= 0.002:
		return
	if ring == 0:
		draw_arc(p, s, 0.0, TAU, 32, Color(col, alpha), w, true)
	else:
		_diamond(p, deg, s)
		_rim_loop(Color(col, alpha), w)


func _rim_loop(col: Color, w: float) -> void:
	for j in 4:
		_loop[j] = _quad[j]
	_loop[4] = _quad[0]
	_loop[5] = _quad[1]  # Ecke sauber schliessen
	draw_polyline(_loop, col, w, true)


## Bogen: ein dunkles Band mit zwei Schienen (anders als jedes Tap-Ziel), am
## Kopf die Ringform (dort startet er wie ein Tap), am Ende ein Querbalken als
## klarer Abschluss, der in den letzten 300 ms creme und laenger wird.
func _draw_arc_note(c: Vector2, u: float, i: int, n) -> void:
	var st := _state[i]
	if st == ST_ARC_DONE:
		return
	var col := _ring_col(n.ring)
	var a0 := float(n.angle_deg)
	var a1 := float(n.end_angle_deg)
	var t0 := float(n.time_ms)
	var t1 := float(n.end_ms)
	var w := u * ARC_W_K
	var fade := 1.0
	var dropped := st == ST_MISS or st == ST_DROP
	if dropped:
		fade = 0.6 * (1.0 - clampf((t_ms - _state_t[i]) / (MISS_FADE_MS * 1.6), 0.0, 1.0))
		col = MISS_COL
		if fade <= 0.002:
			return
	var dt := t0 - t_ms
	var held := st == ST_ARC
	var nxt := _next[n.ring] == i
	var rad := ring_radius(n.ring) if (held or dt < 0.0) else radius_at(n.ring, dt)
	# Gehaltene / laufende Boegen bleiben trotz HD sichtbar (Folgen braucht Sicht).
	var base_a := clampf(_progress(dt) / 0.14, 0.0, 1.0) if (held or dt < 0.0) else _approach_alpha(dt)
	var alpha := base_a * fade * (1.0 if held else _depth(dt, nxt))
	# Spitze: bewegt sich ab der Trefferzeit von a0 nach a1.
	var k := clampf((t_ms - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0) if (held or dt < 0.0) else 0.0
	if dropped:
		# Verlorener Bogen bleibt an der Stelle stehen, an der er fiel.
		k = clampf((_state_t[i] - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	# Gleiche Spitze wie OrbitNote.angle_at, aber entfaltet (a1 - a0 = Bogen).
	var tip := arc_tip_deg(n, t_ms, true) if not dropped else lerpf(a0, a1, k)
	var lo := minf(tip, a1)
	var hi := maxf(tip, a1)
	var seg := maxi(8, int(absf(hi - lo) / 3.0))
	# Warnung: Cursor neben dem Bogen -> Band wird matter (ruhig, kein Blinken).
	var warn := clampf(arc_warn[n.ring], 0.0, 1.0) if held else 0.0
	var body := col.lerp(MISS_COL, warn * 0.7)
	if hi - lo > 0.3:
		draw_arc(c, rad, _ga(lo), _ga(hi), seg, Color(PLATE_COL.lerp(body, 0.28), 0.9 * alpha), w, true)
		var ra := (0.95 if held else 0.75) * alpha
		draw_arc(c, rad - w * 0.5, _ga(lo), _ga(hi), seg, Color(body, ra), 2.0, true)
		draw_arc(c, rad + w * 0.5, _ga(lo), _ga(hi), seg, Color(body, ra), 2.0, true)
	# Bereits abgefahrener Teil: leise Spur.
	if held and absf(tip - a0) > 0.3:
		var tlo := minf(a0, tip)
		var thi := maxf(a0, tip)
		draw_arc(c, rad, _ga(tlo), _ga(thi), maxi(6, int((thi - tlo) / 4.0)), Color(col, 0.10), w * 0.4, true)
	# Ende: Querbalken ueber das Band.
	var near := clampf(1.0 - (t1 - t_ms) / 300.0, 0.0, 1.0) if held else 0.0
	var ec := body.lightened(0.3).lerp(MAX_COL, near)
	var el := w * lerpf(0.85, 1.15, near)
	draw_line(polar(c, a1, rad - el), polar(c, a1, rad + el), Color(PLATE_COL, 0.9 * alpha), 7.0, true)
	draw_line(polar(c, a1, rad - el), polar(c, a1, rad + el), Color(ec, alpha), 4.0, true)
	if held:
		var pt := polar(c, tip, rad)
		var tcol := col.lerp(MISS_COL, warn * 0.8)
		# Spitze: helle Scheibe mit Rand; der Rand zieht sich zum Ende hin zusammen.
		draw_circle(pt, w * 0.62, Color(tcol.lightened(0.55), 0.98), true, -1.0, true)
		draw_arc(pt, w * lerpf(1.1, 0.8, near), 0.0, TAU, 24, Color(tcol, 0.8 * (1.0 - 0.5 * warn)), 2.0, true)
		_chevron(c, rad, tip, signf(a1 - a0), w, Color(1, 1, 1, 0.6))
	else:
		var s := _note_size(u, n.ring) * (_approach_scale(dt) * fit_of(i) if dt > 0.0 else 1.0)
		var hd := tip if dropped else a0
		_shape(polar(c, hd, rad), hd, n.ring, s, col, alpha)
		if st == ST_PENDING and halo_of(i) > 0.0:
			_draw_halo(polar(c, hd, rad), hd, n.ring, halo_of(i), col, maxf(alpha, 0.5))
		if st == ST_PENDING:
			_chevron(c, rad, a0, signf(a1 - a0), w, Color(1, 1, 1, 0.5 * alpha))
			if nxt and dt > 0.0:
				_outline(polar(c, hd, rad), hd, n.ring, s * 1.28, Color.WHITE, 0.4 * alpha, 1.5)


## Kleiner Pfeil auf dem Bogen in Laufrichtung (dir +1 = Uhrzeigersinn).
func _chevron(c: Vector2, rad: float, deg: float, dir: float, w: float, col: Color) -> void:
	if dir == 0.0:
		return
	var off := rad_to_deg(w * 2.4 / maxf(rad, 1.0))
	var tip_deg := deg + dir * off
	var p := polar(c, tip_deg, rad)
	var a := deg_to_rad(tip_deg)
	var tan := Vector2(cos(a), sin(a)) * dir
	var nrm := Vector2(sin(a), -cos(a))
	var h := w * 0.45
	_chev[0] = p - tan * h + nrm * h
	_chev[1] = p
	_chev[2] = p - tan * h - nrm * h
	draw_polyline(_chev, col, 2.0, true)


## Fehltreffer: ruhiges Kreuz am Ring, blendet aus.
func _draw_marks(u: float) -> void:
	for i in MAX_MARKS:
		var f := (t_ms - _m_t0[i]) / MISS_MARK_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var p := _m_pos[i]
		var h := u * NOTE_K * 0.6
		var a := deg_to_rad(_m_deg[i] + 45.0)
		var d1 := Vector2(cos(a), sin(a)) * h
		var d2 := Vector2(-d1.y, d1.x)
		var col := Color(MISS_X_COL, 0.8 * e)
		draw_line(p - d1, p + d1, col, 2.5, true)
		draw_line(p - d2, p + d2, col, 2.5, true)


## Fehldruck-Marken am Ort des Drucks. Form nennt den Grund, ohne Text:
## ANGLE Kreuz (Winkel daneben), RING Pfeil zum richtigen Ring, EARLY offener
## Kreis (zu frueh, frisst nichts), NONE kleiner Punkt.
func _draw_presses(u: float) -> void:
	var c := center()
	for i in MAX_PRESS:
		var f := (t_ms - _p_t0[i]) / PRESS_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var p := _p_pos[i]
		var h := u * 0.016
		var why := _p_why[i]
		if why == "ANGLE":
			var d1 := Vector2(1, 1).normalized() * h
			var d2 := Vector2(1, -1).normalized() * h
			var col := Color(MISS_X_COL, 0.85 * e)
			draw_line(p - d1, p + d1, col, 2.5, true)
			draw_line(p - d2, p + d2, col, 2.5, true)
		elif why == "RING":
			# Pfeil in Richtung des anderen Rings (radial), in dessen Farbe.
			var other := 1 - _p_ring[i]
			var dir := (p - c).normalized()
			if other == 0:
				dir = -dir
			var tip := p + dir * h * 2.2
			var side := Vector2(-dir.y, dir.x) * h * 0.7
			var col := Color(_ring_col(other), 0.9 * e)
			draw_line(p, tip, col, 2.5, true)
			draw_line(tip, tip - dir * h * 0.9 + side, col, 2.5, true)
			draw_line(tip, tip - dir * h * 0.9 - side, col, 2.5, true)
		elif why == "EARLY":
			draw_arc(p, h * (0.7 + 0.5 * f), 0.0, TAU, 20, Color(MISS_COL.lightened(0.2), 0.7 * e), 2.0, true)
		else:
			draw_circle(p, h * 0.35, Color(MISS_COL, 0.5 * e), true, -1.0, true)


## Treffer: harte Linien statt Leuchten. Abdruck der Notenform, ein sich
## weitender Rahmen (CORE: zweiter Rahmen in Creme), Ringbogen an der Stelle,
## darunter frueh/spaet als Strich innen (frueh) oder aussen (spaet) am Ring.
func _draw_lights(c: Vector2, u: float) -> void:
	for i in MAX_LIGHTS:
		var f := (t_ms - _l_t0[i]) / HIT_LIGHT_MS
		if f < 0.0 or f >= 1.0:
			continue
		var e := 1.0 - f
		var col := _l_col[i]
		var q := _l_q[i]
		var p := _l_pos[i]
		var ring := _l_ring[i]
		var big := 1.0 if q <= 1 else 0.8
		var s := _note_size(u, ring)
		var grow := sqrt(f)
		_shape(p, _l_deg[i], ring, s * lerpf(1.0, 0.7, f), col, 0.55 * e * e * big)
		_outline(p, _l_deg[i], ring, s * lerpf(1.1, 1.7, grow) * big, col, 0.7 * e * e, 2.0)
		var rad := ring_radius(ring)
		var span := 8.0 + 6.0 * f
		draw_arc(c, rad, _ga(_l_deg[i] - span), _ga(_l_deg[i] + span), 12,
			Color(col, 0.5 * e * big), 3.0, true)
		if q == 0:
			_outline(p, _l_deg[i], ring, s * lerpf(1.4, 2.2, grow), MAX_COL, 0.45 * e * e, 1.5)
		if _l_side[i] != 0.0:
			# Je schlechter die Stufe, desto laenger der Strich.
			var off := u * 0.034 * _l_side[i]
			var sc := EARLY_COL if _l_side[i] < 0.0 else LATE_COL
			var half := 4.0 + 2.5 * float(q)
			draw_arc(c, rad + off, _ga(_l_deg[i] - half), _ga(_l_deg[i] + half), 8,
				Color(sc, 0.9 * e), 3.0, true)
