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
const PRIMARY_SCALE := 1.0
const CURRENT_SCALE := 1.0
const PREVIEW_SCALE := 0.6
## Hoechste Deckkraft der Vorschau (naechster Takt).
const PREVIEW_ALPHA := 0.25
## Quadrat-Halbseite relativ zum Kreisradius.
const SQUARE_K := 0.88
## Luecke im unteren Strich an Kreuzungen (Bahn-Einheiten) und Mindestabstand der Stuetzpunkte.
const CROSS_GAP := 0.05
const CROSS_SKIP := 12
const LINE_N := 192
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
const POP_MS := 130.0
const MISS_MARK_MS := 400.0
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
var _skip_cache := {}
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
	var src := OrbitPath.polyline(shape, LINE_N)
	var k := path_scale()
	var c := center()
	var out := PackedVector2Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = c + src[i] * k
	return out


## Bahnlinie: aktuelle Form (auf Takt-Eins ueberblendet, gefahrener Teil
## abgedunkelt), die alte Form blendet aus, die naechste Form steht als
## gestrichelte Vorschau da.
func _draw_lines(u: float) -> void:
	var cur := track.shape_at(t_ms)
	var bs := track.clock.bar_start_at(t_ms)
	var old := track.shape_at(bs - 1.0)
	var f := clampf((t_ms - bs) / FADE_MS, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var k := _path_alpha()
	var main_a := 0.40 * k
	var w := maxf(u * 0.002, 1.25)
	var ph := track.clock.phase_at(t_ms)
	if old != cur and f < 1.0:
		_draw_path(old, main_a * (1.0 - f), w, 0.0)
		_draw_path(cur, lerpf(0.16 * k, main_a, f), w, ph)
	else:
		_draw_path(cur, main_a, w, ph)
	if track.changes_next(t_ms):
		var nxt := track.next_shape_at(t_ms)
		# Vorschau wird zum Takt-Ende hin etwas deutlicher.
		var left := (track.clock.bar_end_at(t_ms) - t_ms) / maxf(track.clock.bar_ms_at(t_ms), 1.0)
		_draw_dashed(nxt, Color(LINE_COL, (0.20 + 0.12 * (1.0 - clampf(left, 0.0, 1.0))) * maxf(k, 0.5)))


## Zeichnet die Bahn shape; vor Phase ph (gefahren) dunkler. An Kreuzungen
## setzt die obere Lage (spaetere Phase) eine Luecke in die untere.
func _draw_path(shape: int, a: float, w: float, ph: float) -> void:
	var pts := _line_pts(shape)
	var skip := _cross_skip(shape)
	var n := pts.size() - 1
	var split := int(ph * float(n))
	var run := PackedVector2Array()
	var run_dark := false
	for i in n:
		var dark := i < split
		if skip[i] == 1 or (run.size() > 0 and dark != run_dark):
			_flush_run(run, run_dark, a, w)
			run = PackedVector2Array()
		if skip[i] == 1:
			continue
		if run.size() == 0:
			run.append(pts[i])
			run_dark = dark
		run.append(pts[i + 1])
	_flush_run(run, run_dark, a, w)


func _flush_run(run: PackedVector2Array, dark: bool, a: float, w: float) -> void:
	if run.size() >= 2:
		draw_polyline(run, Color(LINE_COL, a * (0.45 if dark else 1.0)), w, true)


func _draw_dashed(shape: int, col: Color) -> void:
	var pts := _line_pts(shape)
	var n := pts.size() - 1
	var i := 0
	while i < n:
		var j := mini(i + 4, n)
		draw_polyline(pts.slice(i, j + 1), col, 1.0, true)
		i += 8


## Segmente der Bahn, die unter einer spaeteren Lage liegen (1 = nicht zeichnen).
func _cross_skip(shape: int) -> PackedByteArray:
	if _skip_cache.has(shape):
		return _skip_cache[shape]
	var src := OrbitPath.polyline(shape, LINE_N)
	var n := src.size() - 1
	var out := PackedByteArray()
	out.resize(n)
	var g2 := CROSS_GAP * CROSS_GAP
	for i in n:
		for j in range(i + CROSS_SKIP, n):
			if n - j + i < CROSS_SKIP:
				break
			if src[i].distance_squared_to(src[j]) < g2:
				out[i] = 1
				break
	_skip_cache[shape] = out
	return out


func _path_alpha() -> float:
	return clampf(float(Settings.orbit_path_alpha) / 100.0, 0.3, 1.0)


func _note_k() -> float:
	return clampf(float(Settings.orbit_note_size) / 100.0, 0.9, 1.2)


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
			draw_line(p - nrm, p + nrm, Color(LINE_COL, 0.45), 1.5, true)
		else:
			draw_circle(p, u * 0.0035, Color(LINE_COL, 0.26), true, -1.0, true)


func _draw_head(u: float) -> void:
	var shape := track.shape_at(t_ms)
	var ph := track.clock.phase_at(t_ms)
	var hp := to_px(OrbitPath.pos(shape, ph))
	var ok := aim_ok()
	# Dezenter Zielring (Toleranz).
	var rt := tol / 100.0 * path_scale()
	draw_arc(hp, rt, 0.0, TAU, 56, Color(1, 1, 1, 0.55 if ok else 0.16), 1.0, true)
	# Spur-Marken links (A, Scheibe) und rechts (B, Quadrat) vom Kopf.
	var nrm := OrbitPath.left(shape, ph)
	var off := OrbitPath.LANE_OFF * path_scale()
	for r in 2:
		var side := 1.0 if r == 0 else -1.0
		var p := hp + nrm * off * side
		var a := 0.45 + 0.55 * _ring_a[r]
		var s := u * (0.0085 + 0.004 * _ring_a[r])
		if r == 0:
			draw_circle(p, s, Color(INNER_COL, a), true, -1.0, true)
		else:
			_square(p, s, Color(OUTER_COL, a), true)
	draw_circle(hp, u * HEAD_K, Color(HEAD_COL, 1.0 if ok else 0.8), true, -1.0, true)
	draw_arc(hp, u * HEAD_K * 1.75, 0.0, TAU, 32, Color(HEAD_COL, 0.5), 1.0, true)


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
	var base := u * NOTE_K * _note_k()
	if st == ST_HIT or st == ST_ARC_DONE:
		var age := t_ms - float(_state_t[i])
		if age < POP_MS:
			# Knackig: Form dehnt sich aus und blendet aus, in Spurfarbe.
			var f := age / POP_MS
			var tt := float(n.end_ms) if st == ST_ARC_DONE else float(n.time_ms)
			var at := _lane_px(tt, ring)
			_shape(at, ring, base * (1.0 + 0.7 * f), Color(col, 0.55 * (1.0 - f)), true)
			_shape(at, ring, base * (1.0 + 0.7 * f), Color(col.lerp(Color.WHITE, 0.4), 1.0 - f), false)
		return
	if st == ST_MISS or st == ST_DROP:
		var age := t_ms - float(_state_t[i])
		if age < MISS_MARK_MS:
			var a := 1.0 - age / MISS_MARK_MS
			var tt := float(n.time_ms) if st == ST_MISS else clampf(float(_state_t[i]), float(n.time_ms), float(n.end_ms))
			if st == ST_DROP:
				# Losgelassene Halte: Band wird sofort grau und blendet aus.
				_hold_band(n, tt, float(n.end_ms), Color(MISS_COL, 0.5 * a), maxf(u * 0.010, 3.0))
			var at := _lane_px(tt, ring)
			var s := base * 0.55
			draw_line(at + Vector2(-s, -s), at + Vector2(s, s), Color(MISS_X_COL, a), 2.0, true)
			draw_line(at + Vector2(-s, s), at + Vector2(s, -s), Color(MISS_X_COL, a), 2.0, true)
		return
	# Offene Note (oder laufende Halte). Hinter dem Laeufer sofort weg.
	if st == ST_PENDING and dt < -120.0 and not n.is_arc:
		return
	var prev := _is_preview(n)
	if prev and not Settings.orbit_preview:
		return
	var primary := _next[ring] == i
	var phase := clampf(1.0 - dt / maxf(horizon, 1.0), 0.0, 1.0)
	var alpha: float
	var scale: float
	if prev:
		alpha = 0.08 + (PREVIEW_ALPHA - 0.08) * phase
		scale = PREVIEW_SCALE
	elif primary:
		alpha = 1.0
		scale = PRIMARY_SCALE
	else:
		alpha = 0.62 + 0.23 * phase
		scale = CURRENT_SCALE
	alpha *= mod_alpha(maxf(dt, 0.0), horizon)
	if alpha <= 0.01:
		return
	if n.is_arc:
		_draw_hold(u, i, n, col, base * scale, alpha, prev, primary, st == ST_ARC)
		return
	var p := _lane_px(float(n.time_ms), ring)
	_chord_stem(i, n, alpha * 0.7)
	_note_body(p, ring, base * scale, col, alpha, prev, primary)


## Flache Note: Fuellung in Spurfarbe, hellerer Rand, naechste Note weiss umrandet.
func _note_body(p: Vector2, ring: int, s: float, col: Color, alpha: float,
		prev: bool, primary: bool) -> void:
	_shape(p, ring, s, Color(col, alpha), true)
	if prev:
		return
	if primary:
		_shape(p, ring, s, Color(1, 1, 1, 0.95), false)
	else:
		_shape(p, ring, s, Color(col.lerp(Color.WHITE, 0.45), alpha), false)


## Band der Halte entlang der Spur zwischen den Zeiten t0 und t1.
func _hold_band(n, t0: float, t1: float, col: Color, w: float) -> void:
	if t1 - t0 <= 1.0:
		return
	var steps := clampi(int((t1 - t0) / 40.0), 2, 160)
	var pts := PackedVector2Array()
	pts.resize(steps + 1)
	for k in steps + 1:
		pts[k] = _lane_px(lerpf(t0, t1, float(k) / float(steps)), n.ring)
	draw_polyline(pts, col, w, true)


func _draw_hold(u: float, i: int, n, col: Color, size_px: float, alpha: float,
		prev: bool, primary: bool, held: bool) -> void:
	var t0 := float(n.time_ms)
	var t1 := float(n.end_ms)
	var w := maxf(u * 0.010, 3.0)
	var from_t := t0
	if held:
		from_t = clampf(t_ms, t0, t1)
	# Gehalten: der Rest leuchtet, der gefahrene Teil ist verbraucht.
	_hold_band(n, from_t, t1, Color(col, alpha * (0.85 if held else 0.38)), w)
	var p := _lane_px(from_t, n.ring)
	_chord_stem(i, n, alpha * 0.7)
	_note_body(p, n.ring, size_px, col, alpha, prev, primary or held)
	# Ende: kleine Kappe in Spurform.
	var e := _lane_px(t1, n.ring)
	_shape(e, n.ring, w * 0.7, Color(col.lerp(Color.WHITE, 0.3), alpha * 0.9), true)
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


## Spur A: Scheibe, Spur B: achsparalleles Quadrat.
func _shape(p: Vector2, ring: int, s: float, col: Color, filled: bool) -> void:
	if ring == 0:
		if filled:
			draw_circle(p, s, col, true, -1.0, true)
		else:
			draw_arc(p, s, 0.0, TAU, 28, col, 2.0, true)
		return
	_square(p, s, col, filled)


func _square(p: Vector2, s: float, col: Color, filled: bool) -> void:
	var h := s * SQUARE_K
	var r := Rect2(p - Vector2(h, h), Vector2(h, h) * 2.0)
	if filled:
		draw_rect(r, col, true)
	else:
		draw_rect(r, col, false, 2.0)
