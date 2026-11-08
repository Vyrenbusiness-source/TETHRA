class_name OrbitView
extends Control

## Bahnen-Spielfeld, ein _draw-Durchgang ohne Nodes pro Ziel.
##
## Lesbarkeit zuerst (wie osu!): dunkler ruhiger Grund, die Bahn des Takts als
## feine helle Linie, der Spielkopf als weisser Punkt mit dezentem Zielring.
## Links und rechts der Bahn liegen zwei Spuren: Spur A (kuehl, Scheibe) links
## der Laufrichtung, Spur B (warm, Quadrat) rechts; am Kopf stehen beide
## Spur-Marken, sie leuchten bei gedrueckter Taste. Die naechste Note je Spur ist
## am groessten und hat einen hellen Rand, die uebrigen Noten des Takts sind
## etwas kleiner, die Vorschau (naechster Takt) deutlich dunkler. Wechselt die
## Bahnform im naechsten Takt, steht sie vorab als duenne Linie da und wird
## auf Takt-Eins ueberblendet. Treffer: kurzer Pop, Fehler: graue Note mit X.
## Keine Deko, kein Leuchten, keine Partikel.

## Bahn-Einheiten -> Pixel (Faktor, siehe path_scale).
const PATH_W_K := 0.36
const PATH_H_K := 0.40
const NOTE_K := 0.0235
const PRIMARY_SCALE := 1.25
const CURRENT_SCALE := 0.92
const PREVIEW_SCALE := 0.74
const HEAD_K := 0.0125
const FALLBACK_WINDOW_MS := 1200.0
## Ueberblendzeit der Bahnlinie auf Takt-Eins.
const FADE_MS := 450.0

const INNER_COL := Color(0.47, 0.78, 0.98)
const OUTER_COL := Color(1.0, 0.70, 0.40)
const MISS_COL := Color(0.50, 0.52, 0.58)
const MAX_COL := Color(1.0, 0.96, 0.86)
const PLATE_COL := Color(0.012, 0.016, 0.028)
const EARLY_COL := Color(0.45, 0.80, 1.00)
const LATE_COL := Color(1.00, 0.58, 0.45)
const MISS_X_COL := Color(0.90, 0.48, 0.48)
const HEAD_COL := Color(0.97, 0.97, 1.0)
const LINE_COL := Color(0.82, 0.88, 1.0)
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
## Bahn (Uhr + Formplan). null = nur Notenansicht ohne Kopf.
var track: OrbitTrack = null
## Kurzform fuer Aufrufer mit nur einer Uhr (Tutorial): fester Kreis.
var clock: OrbitClock:
	get:
		return track.clock if track != null else null
	set(c):
		track = OrbitTrack.fixed(c, OrbitPath.CIRCLE) if c != null else null
## Cursor in Pixeln (negativ = unbekannt) und Zieltoleranz in Aim-Punkten.
var cursor_pos := Vector2(-1, -1)
var tol := OrbitCore.AIM_TOL
var show_guides := true
var mod_hidden := false
var mod_fade_in := false
var ring_held: Array[bool] = [false, false]
## Nur fuer Aufrufer, die sie noch setzen: ohne Wirkung.
var beat_env := 0.0
var kiai := 0.0
## Halte-Warnung je Spur: 0 = Cursor auf dem Kopf, 1 = Halte faellt gleich.
var arc_warn: Array[float] = [0.0, 0.0]

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _state_q := PackedInt32Array()
var _first := 0
var _next: Array[int] = [-1, -1]
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


## Pixel je Bahn-Einheit.
func path_scale() -> float:
	return maxf(minf(size.x * PATH_W_K, size.y * PATH_H_K), 1.0)


func to_px(p: Vector2) -> Vector2:
	return center() + p * path_scale()


func to_path(px: Vector2) -> Vector2:
	return (px - center()) / path_scale()


static func polar(c: Vector2, deg: float, r: float) -> Vector2:
	var a := deg_to_rad(deg)
	return c + Vector2(sin(a), -cos(a)) * r


## Winkel von c nach p: 0 = oben, im Uhrzeigersinn, 0..360.
static func angle_of(c: Vector2, p: Vector2) -> float:
	var d := p - c
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## Ort des Kopfes in Bahn-Einheiten (ohne Bahn: Mitte).
func head_path() -> Vector2:
	return track.head(t_ms) if track != null else Vector2.ZERO


## Liegt der Cursor auf dem Kopf (Toleranz)? Rein zur Anzeige.
func aim_ok() -> bool:
	return track != null and cursor_pos.x >= 0.0 \
			and to_path(cursor_pos).distance_to(head_path()) * 100.0 <= tol


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


## Druck ohne Treffer: kleines X an der Cursorposition (pos in Bahn-Einheiten).
func on_press_missed(pos: Vector2, _ring: int, reason: String) -> void:
	if reason == "EARLY" or reason == "NONE":
		return
	_p_pos[_p_next] = to_px(pos)
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
	return track.clock.bar_ms_at(t_ms) if track != null else FALLBACK_WINDOW_MS


func _draw() -> void:
	var u := unit()
	_layout()
	var horizon := _horizon_ms()
	if track != null:
		_draw_lines(u)
		_draw_grid(u)
	var last := _last_visible(horizon)
	# Spaeteste zuerst: die naechste Note liegt obenauf.
	for i in range(last - 1, _first - 1, -1):
		_draw_note(u, i, horizon)
	if track != null:
		_draw_head(u)
	_draw_presses(u)
	_draw_cursor(u)


func _line_pts(shape: int) -> PackedVector2Array:
	var src := OrbitPath.polyline(shape)
	var k := path_scale()
	var c := center()
	var out := PackedVector2Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = c + src[i] * k
	return out


## Bahnlinie: aktuelle Form (auf Takt-Eins ueberblendet), die alte Form blendet
## aus, die naechste Form steht als duenne Vorschau da.
func _draw_lines(u: float) -> void:
	var cur := track.shape_at(t_ms)
	var bs := track.clock.bar_start_at(t_ms)
	var old := track.shape_at(bs - 1.0)
	var f := clampf((t_ms - bs) / FADE_MS, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var main_a := 0.40
	var pre_a := 0.16
	var w := maxf(u * 0.0024, 1.5)
	if old != cur and f < 1.0:
		draw_polyline(_line_pts(old), Color(LINE_COL, main_a * (1.0 - f)), w, true)
		draw_polyline(_line_pts(cur), Color(LINE_COL, lerpf(pre_a, main_a, f)), lerpf(1.0, w, f), true)
	else:
		draw_polyline(_line_pts(cur), Color(LINE_COL, main_a), w, true)
	if track.changes_next(t_ms):
		var nxt := track.next_shape_at(t_ms)
		# Vorschau wird zum Takt-Ende hin etwas deutlicher.
		var left := (track.clock.bar_end_at(t_ms) - t_ms) / maxf(track.clock.bar_ms_at(t_ms), 1.0)
		draw_polyline(_line_pts(nxt), Color(LINE_COL, pre_a + 0.08 * (1.0 - clampf(left, 0.0, 1.0))), 1.0, true)


## Raster: Schlaege als feine Punkte auf der Bahn, Takt-Eins als kurzer Strich.
func _draw_grid(u: float) -> void:
	if not show_guides:
		return
	var shape := track.shape_at(t_ms)
	var beats := track.clock.beats_at(t_ms)
	for i in beats:
		var ph := float(i) / float(beats)
		var p := to_px(OrbitPath.pos(shape, ph))
		if i == 0:
			var nrm := OrbitPath.left(shape, 0.0) * u * 0.022
			draw_line(p - nrm, p + nrm, Color(LINE_COL, 0.55), 1.5, true)
		else:
			draw_circle(p, u * 0.0035, Color(LINE_COL, 0.32), true, -1.0, true)


func _draw_head(u: float) -> void:
	var shape := track.shape_at(t_ms)
	var ph := track.clock.phase_at(t_ms)
	var hp := to_px(OrbitPath.pos(shape, ph))
	var ok := aim_ok()
	# Dezenter Zielring (Toleranz).
	var rt := tol / 100.0 * path_scale()
	draw_arc(hp, rt, 0.0, TAU, 56, Color(1, 1, 1, 0.26 if ok else 0.09), 1.0, true)
	# Spur-Marken links (A, Scheibe) und rechts (B, Quadrat) vom Kopf.
	var nrm := OrbitPath.left(shape, ph)
	var tan_v := OrbitPath.tangent(shape, ph)
	var off := OrbitPath.LANE_OFF * path_scale()
	for r in 2:
		var side := 1.0 if r == 0 else -1.0
		var p := hp + nrm * off * side
		var a := 0.45 + 0.55 * _ring_a[r]
		var s := u * (0.0085 + 0.004 * _ring_a[r])
		if r == 0:
			draw_circle(p, s, Color(INNER_COL, a), true, -1.0, true)
		else:
			_square(p, tan_v, s, Color(OUTER_COL, a), true)
	draw_circle(hp, u * HEAD_K, Color(HEAD_COL, 1.0 if ok else 0.8), true, -1.0, true)
	draw_arc(hp, u * HEAD_K * 1.75, 0.0, TAU, 32, Color(HEAD_COL, 0.5), 1.5, true)


func _draw_cursor(u: float) -> void:
	if cursor_pos.x < 0.0:
		return
	var ok := aim_ok()
	if ok:
		draw_circle(cursor_pos, u * 0.0065, Color(1, 1, 1, 0.9), true, -1.0, true)
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


## Bestimmt _first und die naechste offene Note je Spur.
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
	return track != null and track.clock.bar_at(float(n.time_ms)) != track.clock.bar_at(t_ms)


func mod_alpha(dt: float, horizon: float) -> float:
	var f := clampf(dt / maxf(horizon, 1.0), 0.0, 1.0)
	var a := 1.0
	if mod_hidden:
		a *= clampf((f - 0.30) / 0.25, 0.0, 1.0)
	if mod_fade_in:
		a *= clampf((0.55 - f) / 0.15, 0.0, 1.0)
	return a


## Ort (Pixel) und Laufrichtung der Spur ring zur Zeit tt.
func _lane_px(tt: float, ring: int) -> Vector2:
	if track == null:
		return center()
	return to_px(track.lane_pos(tt, ring))


func _tan_at(tt: float) -> Vector2:
	if track == null:
		return Vector2.RIGHT
	return OrbitPath.tangent(track.shape_at(tt), track.clock.phase_at(tt))


func _draw_note(u: float, i: int, horizon: float) -> void:
	var n = notes[i]
	var st := _state[i]
	var dt := float(n.time_ms) - t_ms
	var ring: int = n.ring
	var col := _ring_col(ring)
	var base := u * NOTE_K
	if st == ST_HIT or st == ST_ARC_DONE:
		var age := t_ms - float(_state_t[i])
		if age < POP_MS:
			var q := clampi(int(_state_q[i]), 0, 4)
			var f := age / POP_MS
			var tt := float(n.end_ms) if st == ST_ARC_DONE else float(n.time_ms)
			var at := _lane_px(tt, ring)
			var tv := _tan_at(tt)
			_shape(at, tv, ring, base * (1.0 - 0.55 * f), Color(TIER_POP[q], 1.0 - f), true)
			_shape(at, tv, ring, base * (1.0 + 0.8 * f), Color(TIER_POP[q], 0.8 * (1.0 - f)), false)
		return
	if st == ST_MISS or st == ST_DROP:
		var age := t_ms - float(_state_t[i])
		if age < MISS_MARK_MS:
			var a := 1.0 - age / MISS_MARK_MS
			var tt := float(n.time_ms) if st == ST_MISS else clampf(float(_state_t[i]), float(n.time_ms), float(n.end_ms))
			var at := _lane_px(tt, ring)
			_shape(at, _tan_at(tt), ring, base * 0.8, Color(MISS_COL, 0.55 * a), true)
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
		alpha = 0.10 + 0.18 * phase
		scale = PREVIEW_SCALE
	elif primary:
		alpha = 1.0
		scale = PRIMARY_SCALE
	else:
		alpha = 0.60 + 0.25 * phase
		scale = CURRENT_SCALE
	alpha *= mod_alpha(maxf(dt, 0.0), horizon)
	if alpha <= 0.01:
		return
	if n.is_arc:
		_draw_hold(u, i, n, col, base * scale, alpha, prev, primary, st == ST_ARC)
		return
	var tt := float(n.time_ms)
	var p := _lane_px(tt, ring)
	var tv := _tan_at(tt)
	_chord_stem(i, n, alpha * 0.5)
	_shape(p, tv, ring, base * scale, Color(col, alpha), true)
	if primary and not prev:
		_shape(p, tv, ring, base * scale, Color(1, 1, 1, 0.95), false)


func _draw_hold(u: float, i: int, n, col: Color, size_px: float, alpha: float,
		prev: bool, primary: bool, held: bool) -> void:
	var t0 := float(n.time_ms)
	var t1 := float(n.end_ms)
	var w := u * 0.015
	var from_t := t0
	if held:
		from_t = clampf(t_ms, t0, t1)
	# Band entlang der Bahn zwischen from_t und Ende (alle ~40 ms ein Punkt).
	var steps := clampi(int((t1 - from_t) / 40.0), 2, 160)
	if t1 - from_t > 1.0:
		var pts := PackedVector2Array()
		pts.resize(steps + 1)
		for k in steps + 1:
			pts[k] = _lane_px(lerpf(from_t, t1, float(k) / float(steps)), n.ring)
		draw_polyline(pts, Color(col, alpha * (0.85 if held else 0.40)), w, true)
	var p := _lane_px(from_t, n.ring)
	var tv := _tan_at(from_t)
	_chord_stem(i, n, alpha * 0.5)
	_shape(p, tv, n.ring, size_px, Color(col, alpha), true)
	if (primary and not prev) or held:
		_shape(p, tv, n.ring, size_px, Color(1, 1, 1, 0.95), false)
	# Ende: kleiner Punkt.
	draw_circle(_lane_px(t1, n.ring), w * 0.55, Color(col, alpha * 0.8), true, -1.0, true)
	if held and arc_warn[n.ring] > 0.05:
		draw_arc(p, size_px * 1.45, 0.0, TAU, 20, Color(MISS_X_COL, minf(arc_warn[n.ring], 1.0)), 2.0, true)


## Akzent: duenne Verbindung zwischen der Note auf Spur A und der auf Spur B.
func _chord_stem(i: int, n, alpha: float) -> void:
	if n.ring != 0 or i + 1 >= notes.size():
		return
	var m = notes[i + 1]
	if m.ring == 1 and absf(float(m.time_ms) - float(n.time_ms)) <= CHORD_EPS_MS:
		var tt := float(n.time_ms)
		draw_line(_lane_px(tt, 0), _lane_px(tt, 1), Color(1, 1, 1, alpha * 0.6), 2.0, true)


## Spur A: Scheibe, Spur B: Quadrat (an der Laufrichtung ausgerichtet).
func _shape(p: Vector2, tan_v: Vector2, ring: int, s: float, col: Color, filled: bool) -> void:
	if ring == 0:
		if filled:
			draw_circle(p, s, col, true, -1.0, true)
		else:
			draw_arc(p, s, 0.0, TAU, 28, col, 2.0, true)
		return
	_square(p, tan_v, s, col, filled)


func _square(p: Vector2, tan_v: Vector2, s: float, col: Color, filled: bool) -> void:
	var a := tan_v * s
	var b := Vector2(-tan_v.y, tan_v.x) * s
	_poly.clear()
	_poly.append(p + a + b)
	_poly.append(p + a - b)
	_poly.append(p - a - b)
	_poly.append(p - a + b)
	if filled:
		draw_colored_polygon(_poly, col)
	else:
		_poly.append(_poly[0])
		draw_polyline(_poly, col, 2.0, true)
