class_name OrbitView
extends Control

## Orbit "Satelliten": Spielfeld in einem _draw, ohne Nodes pro Ziel
## (docs/modes/orbit_satellit.md). Zeichnet nur; die Wertung macht OrbitCore.
##
## Feld 4:3, Hoehe FIELD_H_K der Control-Hoehe, mittig. Feld-Koordinaten 0..1 x
## 0..1 (osu! 512 x 384 normiert) -> Pixel ueber field_to_screen; Radien in
## Feld-Einheiten mal field_scale() (= Feldhoehe in Pixeln).
##
## Lesbarkeit wie osu!: Ziel A = kuehle Scheibe, Ziel B = warmes abgerundetes
## Quadrat, Akzent = Scheibe halb/halb mit weissem Ring. Um jedes Ziel ein
## duenner Orbit-Ring (ORBIT_K x Radius) mit Marke oben; der Satellit (weisser
## Punkt) kreist eine Runde pro lap_ms und steht zur Trefferzeit genau an der
## Marke. Pips unter dem Ziel = verbleibende ganze Runden. In der letzten Runde
## ist der Rest des Rings bis zur Marke heller (wann). Das naechste Ziel ist
## voll deckend und traegt die Taste, spaetere LATER_ALPHA. Duenne Linie vom
## naechsten zum folgenden Ziel. Halten: Band entlang des Pfads, Kugel und
## Folgekreis. Treffer: knapper Pop in Zielfarbe, Miss: kleines X, Fehldruck:
## kurzes Wort am Cursor. Kein Glow, keine Partikel, keine Deko.

## Feld: Hoehe relativ zur Control-Hoehe, Seitenverhaeltnis 4:3.
const FIELD_H_K := 0.8
const ASPECT := 4.0 / 3.0
## Orbit-Ring relativ zum Zielradius.
const ORBIT_K := 1.6
## Folgekreis beim Halten relativ zum Zielradius (OrbitCore.FOLLOW_RADIUS).
const FOLLOW_K := 2.0
## Quadrat-Halbseite und Eckenradius relativ zum Zielradius.
const SQUARE_K := 0.86
const CORNER_K := 0.34
const LATER_ALPHA := 0.55
const POP_IN_MS := 90.0
const HIT_MS := 130.0
const MISS_MARK_MS := 420.0
const PRESS_MS := 560.0
const LOCK_MS := 170.0
const MAX_PRESS := 6
const CHORD_EPS_MS := 2.0

## Farben (auch von OrbitResults/OrbitTutorial genutzt: INNER = A, OUTER = B).
const A_COL := Color(0.38, 0.74, 1.0)
const B_COL := Color(1.0, 0.60, 0.30)
const INNER_COL := A_COL
const OUTER_COL := B_COL
const MISS_COL := Color(0.50, 0.52, 0.58)
const MAX_COL := Color(1.0, 0.96, 0.86)
const PLATE_COL := Color(0.012, 0.016, 0.028)
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MISS_X_COL := Color(0.95, 0.42, 0.42)
const HEAD_COL := Color(0.97, 0.97, 1.0)
const LINE_COL := Color(0.82, 0.88, 1.0)
const WARN_COL := Color(1.0, 0.36, 0.32)

const ST_PENDING := 0
const ST_HIT := 1
const ST_MISS := 2
const ST_HOLD := 3       # Kopf getroffen, Taste gehalten
const ST_HOLD_DONE := 4
const ST_DROP := 5       # Halten verloren

var notes: Array = []
var t_ms := 0.0
## Takt-Uhr (optional, nur fuer Aufrufer, die sie setzen).
var clock: OrbitClock = null
## Zielradius in Feld-Einheiten (OrbitConverter.target_radius, PR schon eingerechnet).
var target_radius := OrbitCore.DEFAULT_TARGET_RADIUS
## Cursor in Feld-Koordinaten; show_cursor = false blendet ihn aus.
var cursor := Vector2(0.5, 0.5)
var show_cursor := true
## Mods: HD blendet Satellit/Pips nach dem Erscheinen aus, FI zeigt sie erst in
## der letzten Runde.
var mod_hidden := false
var mod_fade_in := false
## Taste im naechsten Ziel zeigen + Beschriftung der Tasten A/B.
var key_hint := true
var key_labels: Array[String] = ["Z", "X"]
## Gedrueckte Tasten A/B (Cursor-Punkt zeigt sie dezent).
var held: Array[bool] = [false, false]
## Musik: Beat-Huellkurve 0..1 (BeatClock.beat_env), Takt-Eins, Kiai 0..1,
## Staerke (Settings.orbit_music: 0 aus, 1 dezent, 2 voll).
var beat_env := 0.0
var downbeat := false
var kiai := 0.0
var music := 1
## Halten: Index -> Warnstufe 0..1 (Kugel ausserhalb des Folgekreises).
var hold_warn: Dictionary = {}

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _state_q := PackedInt32Array()
var _first := 0
var _max_lead := 0.0
var _press: Array = []  # [pos, text, t0]
var _lock_t := -INF
var _lock_idx := -1
var _square := PackedVector2Array()
var _half_a := PackedVector2Array()
var _half_b := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shapes()


func setup(p_notes: Array) -> void:
	notes = p_notes
	var n := notes.size()
	_state = PackedInt32Array()
	_state.resize(n)
	_state_t = PackedFloat64Array()
	_state_t.resize(n)
	_state_q = PackedInt32Array()
	_state_q.resize(n)
	_max_lead = 0.0
	for i in n:
		_max_lead = maxf(_max_lead, float(notes[i].time_ms) - float(notes[i].spawn_ms))
	_first = 0
	_press.clear()
	_lock_t = -INF
	_lock_idx = -1
	hold_warn = {}
	queue_redraw()


# ---------------------------------------------------------------------------
# Geometrie
# ---------------------------------------------------------------------------

## Feld in Pixeln (Control-Koordinaten).
func field_rect() -> Rect2:
	var s := size
	var h := s.y * FIELD_H_K
	var w := h * ASPECT
	if w > s.x * 0.96:
		w = s.x * 0.96
		h = w / ASPECT
	return Rect2((s - Vector2(w, h)) * 0.5, Vector2(w, h))


## Pixel je Feld-Einheit fuer Radien (Feldhoehe).
func field_scale() -> float:
	return field_rect().size.y


func field_to_screen(p: Vector2) -> Vector2:
	var r := field_rect()
	return r.position + p * r.size


func screen_to_field(px: Vector2) -> Vector2:
	var r := field_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	return (px - r.position) / r.size


## Zielradius in Pixeln.
func radius_px() -> float:
	return target_radius * field_scale()


# ---------------------------------------------------------------------------
# Ereignisse (vom Spiel/Core)
# ---------------------------------------------------------------------------

func state_of(index: int) -> int:
	return _state[index] if index >= 0 and index < _state.size() else ST_PENDING


func on_judged(index: int, result: Dictionary) -> void:
	if index < 0 or index >= _state.size():
		return
	var q := int(result.get("quality", 0))
	var hold_end := bool(result.get("hold_end", false))
	if hold_end or notes[index].is_hold and _state[index] == ST_HOLD:
		_state[index] = ST_DROP if q == 5 else ST_HOLD_DONE
	else:
		_state[index] = ST_MISS if q == 5 else ST_HIT
	_state_t[index] = t_ms
	_state_q[index] = q
	hold_warn.erase(index)
	queue_redraw()


func on_hold_started(index: int, q: int = 0) -> void:
	if index < 0 or index >= _state.size():
		return
	_state[index] = ST_HOLD
	_state_t[index] = t_ms
	_state_q[index] = q
	queue_redraw()


## Fehldruck am Cursor: reason "aim" | "key" | "lock" | "early".
func on_press_missed(pos: Vector2, _key: int, reason: String) -> void:
	var text := ""
	match reason:
		"aim":
			text = tr("daneben")
		"key":
			text = tr("andere Taste")
		"lock":
			_lock_t = t_ms
			_lock_idx = next_index()
			return
		_:
			return
	_press.append([pos, text, t_ms])
	while _press.size() > MAX_PRESS:
		_press.pop_front()


## Index des naechsten offenen Ziels (Zeitordnung), -1 = keins.
func next_index() -> int:
	for i in range(_first, notes.size()):
		if _state[i] == ST_PENDING:
			return i
	return -1


func _process(_d: float) -> void:
	queue_redraw()


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _build_shapes() -> void:
	# Abgerundetes Quadrat (Halbseite 1), Halbscheiben (Radius 1).
	_square = PackedVector2Array()
	var c := CORNER_K / SQUARE_K
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var start := [0.0, PI * 0.5, PI, PI * 1.5]
	for k in 4:
		var cc: Vector2 = corners[k] * (1.0 - c)
		for s in 7:
			var a: float = start[k] + PI * 0.5 * float(s) / 6.0
			_square.append(cc + Vector2(cos(a), sin(a)) * c)
	_half_a = PackedVector2Array()
	_half_b = PackedVector2Array()
	for s in 25:
		var a := PI * 0.5 + PI * float(s) / 24.0
		_half_a.append(Vector2(cos(a), sin(a)))
		_half_b.append(Vector2(cos(a + PI), sin(a + PI)))


static func key_col(key: int) -> Color:
	return B_COL if key == OrbitNote.KEY_B else A_COL


func _advance_first() -> void:
	while _first < notes.size():
		var st := _state[_first]
		if st == ST_PENDING or st == ST_HOLD:
			break
		if t_ms - _state_t[_first] < MISS_MARK_MS + 50.0:
			break
		_first += 1


## Beat-Puls 0..1 fuer die Orbit-Ringe (dezent, Takt-Eins staerker).
func _pulse() -> float:
	if music <= 0:
		return 0.0
	var k := 0.5 if music == 1 else 1.0
	return clampf(beat_env, 0.0, 1.0) * (1.0 if downbeat else 0.55) * k


func _draw() -> void:
	if _square.is_empty():
		_build_shapes()
	if notes.size() != _state.size():
		setup(notes)
	_advance_first()
	var t := t_ms
	var vis: Array[int] = []
	for i in range(_first, notes.size()):
		var n: OrbitNote = notes[i]
		if float(n.time_ms) > t + _max_lead + 1.0:
			break
		if float(n.spawn_ms) > t:
			continue
		vis.append(i)
	var nxt := next_index()
	var nxt_t := float(notes[nxt].time_ms) if nxt >= 0 else INF
	var R := radius_px()
	var pulse := _pulse()
	# 1. Halten-Baender (spaete zuerst).
	for j in range(vis.size() - 1, -1, -1):
		var i := vis[j]
		var n: OrbitNote = notes[i]
		if n.is_hold and _state[i] in [ST_PENDING, ST_HOLD]:
			_draw_band(n, R, _alpha_of(i, n, nxt_t, t))
	# 2. Verbindungslinie naechstes -> folgendes Ziel.
	if nxt >= 0:
		var follow := -1
		for i in vis:
			if i > nxt and _state[i] == ST_PENDING \
					and float(notes[i].time_ms) - nxt_t > CHORD_EPS_MS:
				follow = i
				break
		if follow >= 0:
			_draw_link(notes[nxt], notes[follow], R, t)
	# 3. Ziele (spaete zuerst, das naechste oben).
	for j in range(vis.size() - 1, -1, -1):
		var i := vis[j]
		if _state[i] != ST_PENDING:
			continue
		var n: OrbitNote = notes[i]
		var is_next := absf(float(n.time_ms) - nxt_t) <= CHORD_EPS_MS
		_draw_target(i, n, R, _alpha_of(i, n, nxt_t, t), is_next, pulse, t)
	# 4. Laufende Halten: Kugel + Folgekreis.
	for i in range(_first, notes.size()):
		if float(notes[i].spawn_ms) > t:
			break
		if _state[i] == ST_HOLD:
			_draw_ball(i, notes[i], R, t)
	# 5. Effekte.
	for i in range(_first, notes.size()):
		var st := _state[i]
		if st == ST_PENDING or st == ST_HOLD:
			if float(notes[i].spawn_ms) > t:
				break
			continue
		_draw_fx(i, notes[i], R, t)
	_draw_press(t, R)
	# 6. Cursor.
	if show_cursor:
		_draw_cursor(R)


func _alpha_of(_i: int, n: OrbitNote, nxt_t: float, t: float) -> float:
	var a := clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0)
	if absf(float(n.time_ms) - nxt_t) > CHORD_EPS_MS:
		a *= LATER_ALPHA
	return a


func _pop_scale(n: OrbitNote, t: float) -> float:
	var a := clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0)
	var e := 1.0 - (1.0 - a) * (1.0 - a)
	return lerpf(0.78, 1.0, e)


## Sichtbarkeit von Satellit und Pips (HD/FI).
func _sat_alpha(n: OrbitNote, t: float) -> float:
	var total := maxf(float(n.time_ms) - float(n.spawn_ms), 1.0)
	var u := clampf((t - float(n.spawn_ms)) / total, 0.0, 1.0)
	var a := 1.0
	if mod_hidden:
		a *= 1.0 - smoothstep(0.2, 0.55, u)
	if mod_fade_in:
		var last := float(n.time_ms) - float(n.lap_ms)
		a *= smoothstep(last, last + float(n.lap_ms) * 0.3, t)
	return a


func _draw_target(i: int, n: OrbitNote, R: float, alpha: float, is_next: bool,
		pulse: float, t: float) -> void:
	if alpha <= 0.0:
		return
	var c := field_to_screen(n.pos)
	if i == _lock_idx and t - _lock_t < LOCK_MS:
		var k := (t - _lock_t) / LOCK_MS
		c.x += sin(k * TAU * 3.0) * R * 0.12 * (1.0 - k)
	var r := R * _pop_scale(n, t)
	var ring_r := r * ORBIT_K
	var lw := maxf(1.4, R * 0.055)
	# Orbit-Ring (Puls nur Helligkeit/Breite, dezent).
	var ring_a := (0.22 + 0.10 * kiai + 0.22 * pulse) * alpha
	draw_arc(c, ring_r, 0.0, TAU, 72, Color(1, 1, 1, ring_a), lw * (1.0 + 0.4 * pulse), true)
	# Letzte Runde: Rest bis zur Marke heller (zaehlt "jetzt" herunter).
	var sa := _sat_alpha(n, t) * alpha
	var deg := n.satellite_deg(t)
	if n.laps_left(t) == 0 and sa > 0.0 and t < float(n.time_ms):
		var a0 := deg_to_rad(deg) - PI * 0.5
		var a1 := TAU - PI * 0.5
		if a1 > a0 + 0.02:
			draw_arc(c, ring_r, a0, a1, maxi(6, int(48.0 * (a1 - a0) / TAU)),
					Color(1, 1, 1, 0.55 * sa), lw * 1.3, true)
	# Marke oben.
	var mark := Color(1, 1, 1, (0.85 if is_next else 0.6) * alpha)
	draw_line(c + Vector2(0, -ring_r + lw * 3.2), c + Vector2(0, -ring_r - lw * 3.2), mark, lw * 1.4, true)
	# Ziel.
	_draw_body(c, r, n.key, alpha, is_next)
	if is_next and key_hint:
		_draw_key_label(c, r, n.key, alpha)
	# Satellit.
	if sa > 0.0:
		var ar := deg_to_rad(deg)
		var sp := c + Vector2(sin(ar), -cos(ar)) * ring_r
		var sr := maxf(3.0, R * 0.17)
		draw_circle(sp, sr + 1.5, Color(0, 0, 0, 0.55 * sa), true, -1.0, true)
		draw_circle(sp, sr, Color(1, 1, 1, sa), true, -1.0, true)
		# Pips: verbleibende Runden unter dem Ring.
		var left := n.laps_left(t)
		if left > 0:
			var pr := maxf(2.0, R * 0.085)
			var gap := pr * 3.2
			var y := c.y + ring_r + pr * 3.0
			var x0 := c.x - gap * float(left - 1) * 0.5
			for k in left:
				draw_circle(Vector2(x0 + gap * k, y), pr, Color(1, 1, 1, 0.9 * sa), true, -1.0, true)


func _draw_body(c: Vector2, r: float, key: int, alpha: float, strong: bool) -> void:
	var rim_w := maxf(2.0, r * 0.13)
	var dark := 0.30 if strong else 0.42
	match key:
		OrbitNote.KEY_B:
			var pts := PackedVector2Array()
			var h := r * SQUARE_K
			for p in _square:
				pts.append(c + p * h)
			draw_colored_polygon(pts, Color(B_COL.darkened(dark), alpha))
			pts.append(pts[0])
			draw_polyline(pts, Color(B_COL.lightened(0.5), alpha), rim_w, true)
		OrbitNote.KEY_ACCENT:
			var pa := PackedVector2Array()
			var pb := PackedVector2Array()
			for p in _half_a:
				pa.append(c + p * r)
			for p in _half_b:
				pb.append(c + p * r)
			draw_colored_polygon(pa, Color(A_COL.darkened(dark), alpha))
			draw_colored_polygon(pb, Color(B_COL.darkened(dark), alpha))
			draw_arc(c, r - rim_w * 0.5, 0.0, TAU, 64, Color(1, 1, 1, alpha), rim_w * 1.15, true)
		_:
			draw_circle(c, r, Color(A_COL.darkened(dark), alpha), true, -1.0, true)
			draw_arc(c, r - rim_w * 0.5, 0.0, TAU, 64, Color(A_COL.lightened(0.5), alpha), rim_w, true)


func _draw_key_label(c: Vector2, r: float, key: int, alpha: float) -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var text := key_labels[0] + key_labels[1] if key == OrbitNote.KEY_ACCENT \
			else key_labels[clampi(key, 0, 1)]
	var fs := maxi(8, int(r * (0.72 if text.length() <= 1 else 0.5)))
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := c + Vector2(-sz.x * 0.5, f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.35)
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95 * alpha))


func _band_points(n: OrbitNote) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in n.path:
		pts.append(field_to_screen(p))
	return pts


func _draw_band(n: OrbitNote, R: float, alpha: float) -> void:
	if alpha <= 0.0 or n.path.size() < 2:
		return
	var pts := _band_points(n)
	var col := key_col(n.key)
	var w := R * 1.84
	var edge := Color(col.lightened(0.25), 0.55 * alpha)
	var body := Color(col.darkened(0.72), 0.85 * alpha)
	draw_polyline(pts, edge, w, true)
	draw_circle(pts[pts.size() - 1], w * 0.5, edge, true, -1.0, true)
	draw_polyline(pts, body, w - maxf(3.0, R * 0.16), true)
	draw_circle(pts[pts.size() - 1], (w - maxf(3.0, R * 0.16)) * 0.5, body, true, -1.0, true)
	# Ende: kleiner Ring.
	draw_arc(pts[pts.size() - 1], R * 0.5, 0.0, TAU, 40, Color(col.lightened(0.5), 0.8 * alpha),
			maxf(1.5, R * 0.08), true)


func _draw_link(a: OrbitNote, b: OrbitNote, R: float, t: float) -> void:
	var pa := field_to_screen(OrbitConverter.end_pos(a))
	var pb := field_to_screen(b.pos)
	var d := pa.distance_to(pb)
	var gap := R * ORBIT_K + 4.0
	if d <= gap * 2.0:
		return
	var dir := (pb - pa) / d
	var al := clampf((t - float(b.spawn_ms)) / POP_IN_MS, 0.0, 1.0) * 0.26
	var s := pa + dir * gap
	var e := pb - dir * gap
	draw_line(s, e, Color(LINE_COL, al), maxf(1.2, R * 0.05), true)


func _draw_ball(i: int, n: OrbitNote, R: float, t: float) -> void:
	var bp := field_to_screen(n.pos_at(t))
	var col := key_col(n.key)
	var warn := clampf(float(hold_warn.get(i, 0.0)), 0.0, 1.0)
	var fr := R * FOLLOW_K
	var fcol := Color(1, 1, 1, 0.55).lerp(Color(WARN_COL, 0.9), warn)
	draw_arc(bp, fr, 0.0, TAU, 72, fcol, maxf(1.6, R * 0.07), true)
	draw_circle(bp, R * 0.7, Color(col.darkened(0.15), 1.0), true, -1.0, true)
	draw_arc(bp, R * 0.7, 0.0, TAU, 48, Color(1, 1, 1, 0.95), maxf(2.0, R * 0.11), true)


func _draw_fx(i: int, n: OrbitNote, R: float, t: float) -> void:
	var st := _state[i]
	var dt := t - _state_t[i]
	if dt < 0.0:
		return
	match st:
		ST_HIT, ST_HOLD_DONE:
			if dt >= HIT_MS:
				return
			var k := dt / HIT_MS
			var p := field_to_screen(OrbitConverter.end_pos(n) if st == ST_HOLD_DONE else n.pos)
			var col := key_col(n.key) if n.key != OrbitNote.KEY_ACCENT else Color.WHITE
			var r := R * (1.0 + 0.45 * k)
			var a := (1.0 - k) * 0.85
			draw_circle(p, r, Color(col.lightened(0.2), a * 0.35), true, -1.0, true)
			draw_arc(p, r, 0.0, TAU, 48, Color(col.lightened(0.55), a), maxf(2.0, R * 0.12) * (1.0 - 0.5 * k), true)
		ST_MISS, ST_DROP:
			if dt >= MISS_MARK_MS:
				return
			var p := field_to_screen(n.pos_at(_state_t[i]) if st == ST_DROP else n.pos)
			var a := 1.0 - dt / MISS_MARK_MS
			var h := R * 0.42
			var col := Color(MISS_X_COL, 0.95 * a)
			var w := maxf(2.0, R * 0.12)
			draw_line(p - Vector2(h, h), p + Vector2(h, h), col, w, true)
			draw_line(p - Vector2(h, -h), p + Vector2(h, -h), col, w, true)


func _draw_press(t: float, R: float) -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var fs := maxi(10, int(R * 0.52))
	for e in _press:
		var dt: float = t - float(e[2])
		if dt < 0.0 or dt >= PRESS_MS:
			continue
		var a := 1.0 - smoothstep(PRESS_MS * 0.5, PRESS_MS, dt)
		var text: String = e[1]
		var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := field_to_screen(e[0]) + Vector2(-sz.x * 0.5, -R * 1.1 - dt * 0.02)
		draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7 * a))
		draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(MISS_X_COL.lightened(0.3), a))
	while not _press.is_empty() and t - float(_press[0][2]) >= PRESS_MS:
		_press.pop_front()


func _draw_cursor(R: float) -> void:
	var p := field_to_screen(cursor)
	var r := clampf(R * 0.2, 4.0, 7.0)
	var down := held[0] or held[1]
	draw_circle(p, r + 2.0, Color(0, 0, 0, 0.6), true, -1.0, true)
	draw_circle(p, r, Color(1, 1, 1, 1.0), true, -1.0, true)
	if down:
		draw_arc(p, r + 4.5, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.5, true)
