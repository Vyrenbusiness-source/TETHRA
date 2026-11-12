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
## Quadrat, Akzent = Scheibe halb/halb mit weissem Ring; Koerper mit dezentem
## Innenverlauf (oben heller) und feinem Rand. Um jedes Ziel ein
## duenner Orbit-Ring (ORBIT_K x Radius) mit Marke oben; der Satellit (weisser
## Punkt mit kurzer Spur auf dem Ring) kreist eine Runde pro lap_ms und steht
## zur Trefferzeit genau an der Marke. Pips (eine Reihe direkt unter dem Ziel,
## innerhalb des Rings) = verbleibende ganze Runden. In der letzten Runde ist der
## Rest des Rings bis zur Marke heller (wann). Das naechste Ziel ist voll deckend
## mit weissem Rand und traegt die Taste, spaetere LATER_ALPHA. Folgepunkte
## (feine Pfeile wie osu!) zwischen aufeinanderfolgenden Zielen: blenden
## nacheinander ein und verschwinden von vorn, waehrend die Zeit vom einen zum
## naechsten Ziel laeuft. Ecken des Felds dezent markiert, im Kiai pulst ein
## feiner Rahmen sehr leise im Beat. Halten: Band entlang des Pfads, Kugel und
## Folgekreis. Treffer: Ring dehnt sich aus und blendet (HIT_MS) in Tastenfarbe,
## aussen ein feiner Ring in Stufenfarbe; Miss: X blendet aus; Fehldruck: kurzes
## Wort am Cursor. Cursor mit weicher kurzer Spur. Kein Glow, keine Partikel.

## Feld: Hoehe relativ zur Control-Hoehe, Seitenverhaeltnis 4:3.
const FIELD_H_K := 0.8
const ASPECT := 4.0 / 3.0
## Orbit-Ring relativ zum Zielradius.
const ORBIT_K := 1.3
## Folgekreis beim Halten relativ zum Zielradius (OrbitCore.FOLLOW_RADIUS).
const FOLLOW_K := 2.0
## Quadrat-Halbseite und Eckenradius relativ zum Zielradius.
const SQUARE_K := 0.86
const CORNER_K := 0.34
const LATER_ALPHA := 0.45
## Lesbarkeit: Ring + Satellit nur fuer die naechsten RING_RANKS Zeitpunkte, danach nur die
## Form (blasser); mehr als MAX_RANKS kommende Zeitpunkte werden nicht gezeigt.
const RING_RANKS := 2
const MAX_RANKS := 4
const FAR_ALPHA := 0.3
const POP_IN_MS := 90.0
const HIT_MS := 220.0
const HIT_FLASH_MS := 70.0
const MISS_MARK_MS := 420.0
## Cursor-Spur (Songzeit-ms) und ihre Deckkraft an der Spitze.
const TRAIL_MS := 90.0
const TRAIL_ALPHA := 0.26
## Hoechste Spurlaenge relativ zum Cursor-Radius.
const TRAIL_LEN_K := 7.0
## Folgepunkte: nur zu Zielen mit Rang < FP_RANKS; Einblenden gestaffelt ueber
## FP_IN_SPREAD ab dem Erscheinen des Ziels, Ausblenden FP_OUT_MS.
const FP_RANKS := 3
const FP_IN_SPREAD := 180.0
const FP_IN_MS := 120.0
const FP_OUT_MS := 90.0
## Koerper-Verlauf: Mitte heller, Rand oben/unten dunkler (Anteile).
const GRAD_IN := 0.10
const GRAD_TOP := 0.06
const GRAD_BOTTOM := 0.30
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
## Zielgroesse (Settings.orbit_target_size / 100, nur Anzeige) und Cursorgroesse.
var size_k := 1.0
var cursor_k := 1.0

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
var _disk := PackedVector2Array()
## Cursor-Spur: Feld-Positionen und Songzeiten.
var _trail_p := PackedVector2Array()
var _trail_t := PackedFloat64Array()


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
	_disk = PackedVector2Array()
	for s in 48:
		var a := TAU * float(s) / 48.0
		_disk.append(Vector2(cos(a), sin(a)))
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
	var R := radius_px() * size_k
	var pulse := _pulse()
	_draw_marks()
	# 1. Halten-Baender (spaete zuerst).
	for j in range(vis.size() - 1, -1, -1):
		var i := vis[j]
		var n: OrbitNote = notes[i]
		if n.is_hold and _state[i] in [ST_PENDING, ST_HOLD]:
			_draw_band(n, R, _alpha_of(i, n, nxt_t, t))
	# 2. Rang = Zahl frueherer offener Zeitpunkte.
	var ranks := {}
	var rank := -1
	var last_t := -INF
	for i in vis:
		if _state[i] != ST_PENDING:
			continue
		var tt := float(notes[i].time_ms)
		if tt - last_t > CHORD_EPS_MS:
			rank += 1
			last_t = tt
		ranks[i] = rank
	# 3. Folgepunkte zwischen aufeinanderfolgenden Zeitpunkten.
	_draw_follow(t, R, ranks)
	# 4. Ziele (spaete zuerst, das naechste oben).
	for j in range(vis.size() - 1, -1, -1):
		var i := vis[j]
		if _state[i] != ST_PENDING:
			continue
		var rk: int = ranks.get(i, 0)
		if rk >= MAX_RANKS:
			continue
		var n: OrbitNote = notes[i]
		var is_next := absf(float(n.time_ms) - nxt_t) <= CHORD_EPS_MS
		var a := _alpha_of(i, n, nxt_t, t)
		if rk >= RING_RANKS:
			a = minf(a, FAR_ALPHA * clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0))
		_draw_target(i, n, R, a, is_next, pulse, t, rk < RING_RANKS)
	# 5. Laufende Halten: Kugel + Folgekreis.
	for i in range(_first, notes.size()):
		if float(notes[i].spawn_ms) > t:
			break
		if _state[i] == ST_HOLD:
			_draw_ball(i, notes[i], R, t)
	# 6. Effekte.
	for i in range(_first, notes.size()):
		var st := _state[i]
		if st == ST_PENDING or st == ST_HOLD:
			if float(notes[i].spawn_ms) > t:
				break
			continue
		_draw_fx(i, notes[i], R, t)
	_draw_press(t, R)
	# 7. Cursor.
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
		pulse: float, t: float, with_ring: bool = true) -> void:
	if alpha <= 0.0:
		return
	if not with_ring:
		_draw_body(field_to_screen(n.pos), R * _pop_scale(n, t), n.key, alpha, false)
		return
	var c := field_to_screen(n.pos)
	if i == _lock_idx and t - _lock_t < LOCK_MS:
		var k := (t - _lock_t) / LOCK_MS
		c.x += sin(k * TAU * 3.0) * R * 0.12 * (1.0 - k)
	var r := R * _pop_scale(n, t)
	var ring_r := r * ORBIT_K
	var lw := maxf(1.5, R * 0.05)
	# Orbit-Ring (Puls nur Helligkeit/Breite, dezent).
	var ring_a := ((0.30 if is_next else 0.22) + 0.08 * kiai + 0.2 * pulse) * alpha
	draw_arc(c, ring_r, 0.0, TAU, 80, Color(1, 1, 1, ring_a), lw * (1.0 + 0.4 * pulse), true)
	var sa := _sat_alpha(n, t) * alpha
	var deg := n.satellite_deg(t)
	# Letzte Runde: Rest bis zur Marke heller (zaehlt "jetzt" herunter).
	if n.laps_left(t) == 0 and sa > 0.0 and t < float(n.time_ms):
		var a0 := deg_to_rad(deg) - PI * 0.5
		var a1 := TAU - PI * 0.5
		if a1 > a0 + 0.02:
			draw_arc(c, ring_r, a0, a1, maxi(6, int(64.0 * (a1 - a0) / TAU)),
					Color(1, 1, 1, 0.5 * sa), lw * 1.35, true)
	# Marke oben: kurzer kraeftiger Querstrich durch den Ring.
	var mk := Color(1, 1, 1, (1.0 if is_next else 0.75) * alpha)
	var mh := R * 0.2
	draw_line(c + Vector2(0, -ring_r + mh), c + Vector2(0, -ring_r - mh), mk, lw * 2.2, true)
	# Ziel.
	_draw_body(c, r, n.key, alpha, is_next)
	if is_next and key_hint:
		_draw_key_label(c, r, n.key, alpha)
	if sa <= 0.0:
		return
	# Pips: verbleibende Runden, eine Reihe direkt unter dem Ziel (im Ring).
	var left := n.laps_left(t)
	if left > 0:
		var pr := maxf(2.5, R * 0.1)
		var gap := pr * 3.0
		var y := c.y + r + (ring_r - r) * 0.42
		var x0 := c.x - gap * float(left - 1) * 0.5
		for k in left:
			var pp := Vector2(x0 + gap * k, y)
			draw_circle(pp, pr + 1.0, Color(0, 0, 0, 0.5 * sa), true, -1.0, true)
			draw_circle(pp, pr, Color(0.78, 0.8, 0.86, 0.9 * sa), true, -1.0, true)
	# Satellit: heller Punkt mit kurzer Spur entlang des Rings.
	var ar := deg_to_rad(deg)
	var trail := deg_to_rad(42.0)
	var segs := 8
	for k in segs:
		var u0 := float(k) / float(segs)
		var u1 := float(k + 1) / float(segs)
		var b0 := ar - trail * (1.0 - u0) - PI * 0.5
		var b1 := ar - trail * (1.0 - u1) - PI * 0.5
		draw_arc(c, ring_r, b0, b1, 4, Color(1, 1, 1, 0.75 * sa * u1 * u1), lw * (1.0 + 1.6 * u1), true)
	var sp := c + Vector2(sin(ar), -cos(ar)) * ring_r
	var sr := maxf(3.5, R * 0.19)
	draw_circle(sp, sr + maxf(1.5, R * 0.05), Color(0, 0, 0, 0.6 * sa), true, -1.0, true)
	draw_circle(sp, sr, Color(1, 1, 1, sa), true, -1.0, true)


func _draw_body(c: Vector2, r: float, key: int, alpha: float, strong: bool) -> void:
	var rim_w := maxf(1.6, r * (0.085 if strong else 0.065))
	var dark := 0.30 if strong else 0.46
	var rim_a := Color(1, 1, 1, alpha) if strong else Color(A_COL.lightened(0.45), 0.85 * alpha)
	var rim_b := Color(1, 1, 1, alpha) if strong else Color(B_COL.lightened(0.45), 0.85 * alpha)
	var edge := Color(0, 0, 0, 0.35 * alpha)
	match key:
		OrbitNote.KEY_B:
			var h := r * SQUARE_K
			var pts := PackedVector2Array()
			for p in _square:
				pts.append(c + p * h)
			_fill_grad(c, r, pts, B_COL.darkened(dark), alpha)
			var outer := PackedVector2Array()
			for p in _square:
				outer.append(c + p * (h + 0.75))
			outer.append(outer[0])
			draw_polyline(outer, edge, 1.5, true)
			var inner := PackedVector2Array()
			var hi := h - rim_w * 0.5
			for p in _square:
				inner.append(c + p * hi)
			inner.append(inner[0])
			draw_polyline(inner, rim_b, rim_w, true)
		OrbitNote.KEY_ACCENT:
			var pa := PackedVector2Array()
			var pb := PackedVector2Array()
			for p in _half_a:
				pa.append(c + p * r)
			for p in _half_b:
				pb.append(c + p * r)
			_fill_grad(c + Vector2(-r * 0.4, 0.0), r, pa, A_COL.darkened(dark), alpha)
			_fill_grad(c + Vector2(r * 0.4, 0.0), r, pb, B_COL.darkened(dark), alpha)
			draw_arc(c, r + 0.75, 0.0, TAU, 64, edge, 1.5, true)
			draw_arc(c, r - rim_w * 0.6, 0.0, TAU, 64, Color(1, 1, 1, alpha), rim_w * 1.2, true)
		_:
			var pts := PackedVector2Array()
			for p in _disk:
				pts.append(c + p * r)
			_fill_grad(c, r, pts, A_COL.darkened(dark), alpha)
			draw_arc(c, r + 0.75, 0.0, TAU, 64, edge, 1.5, true)
			draw_arc(c, r - rim_w * 0.5, 0.0, TAU, 64, rim_a, rim_w, true)


## Flaeche mit dezentem Innenverlauf: Faecher um c (Mitte etwas heller), Rand
## oben kaum, unten etwas dunkler. outline = konvexer Umriss um c.
func _fill_grad(c: Vector2, r: float, outline: PackedVector2Array, base: Color, alpha: float) -> void:
	var n := outline.size()
	if n < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	var cols := PackedColorArray()
	cols.resize(n + 1)
	var idx := PackedInt32Array()
	idx.resize(n * 3)
	pts[0] = c
	cols[0] = Color(base.lightened(GRAD_IN), alpha)
	var top := Color(base.darkened(GRAD_TOP), alpha)
	var bottom := Color(base.darkened(GRAD_BOTTOM), alpha)
	for k in n:
		pts[k + 1] = outline[k]
		var dy := clampf((outline[k].y - c.y) / maxf(r, 1.0), -1.0, 1.0)
		cols[k + 1] = top.lerp(bottom, dy * 0.5 + 0.5)
		idx[k * 3] = 0
		idx[k * 3 + 1] = k + 1
		idx[k * 3 + 2] = (k + 1) % n + 1
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


func _draw_key_label(c: Vector2, r: float, key: int, alpha: float) -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var text := key_labels[0] + key_labels[1] if key == OrbitNote.KEY_ACCENT \
			else key_labels[clampi(key, 0, 1)]
	var fs := maxi(10, int(r * (0.78 if text.length() <= 1 else 0.52)))
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := c + Vector2(-sz.x * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.14)),
			Color(0, 0, 0, 0.45 * alpha))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))


## Ecken des 4:3-Felds: kurze, dezente Winkel.
func _draw_marks() -> void:
	var fr := field_rect()
	var l := fr.size.y * 0.035
	var k := clampf(kiai, 0.0, 1.0)
	var col := Color(1, 1, 1, 0.14 + 0.06 * k)
	var w := maxf(1.0, fr.size.y * 0.0022)
	# Kiai: feiner Rahmen, pulst sehr dezent im Beat (Musik-Reaktion aus = ruhig).
	if k > 0.01:
		var fa := k * (0.035 + 0.075 * _pulse())
		draw_rect(fr.grow(w * 2.0), Color(LINE_COL, fa * 0.35), false, w * 4.0, true)
		draw_rect(fr, Color(LINE_COL, fa), false, w, true)
	var cs := [fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]
	var dx := [1.0, -1.0, -1.0, 1.0]
	var dy := [1.0, 1.0, -1.0, -1.0]
	for j in 4:
		var p: Vector2 = cs[j]
		draw_line(p, p + Vector2(l * dx[j], 0.0), col, w, true)
		draw_line(p, p + Vector2(0.0, l * dy[j]), col, w, true)


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


## Folgepunkte wie osu!: feine Pfeile zwischen aufeinanderfolgenden
## Zeitpunkten (Akkorde = ein Zeitpunkt), nur zu offenen Zielen mit Rang <
## FP_RANKS. Sie blenden mit dem Ziel nacheinander von vorn nach hinten ein und
## verschwinden von vorn, waehrend die Zeit vom einen zum naechsten Ziel laeuft.
func _draw_follow(t: float, R: float, ranks: Dictionary) -> void:
	var prev := -1
	var prev_t := -INF
	for i in range(_first, notes.size()):
		var n: OrbitNote = notes[i]
		if float(n.spawn_ms) > t:
			break
		var tt := float(n.time_ms)
		if tt - prev_t <= CHORD_EPS_MS:
			continue
		if prev >= 0 and _state[i] == ST_PENDING:
			var rk: int = ranks.get(i, -1)
			if rk >= 0 and rk < FP_RANKS:
				_draw_fp_pair(notes[prev], n, R, t, rk)
		prev = i
		prev_t = tt


func _draw_fp_pair(a: OrbitNote, b: OrbitNote, R: float, t: float, rk: int) -> void:
	var pa := field_to_screen(OrbitConverter.end_pos(a))
	var pb := field_to_screen(b.pos)
	var d := pa.distance_to(pb)
	var g0 := R * (ORBIT_K + 0.3)
	var g1 := R * ((ORBIT_K + 0.3) if rk < RING_RANKS else 1.3)
	var span := d - g0 - g1
	var step := maxf(R * 0.6, 12.0)
	if span < step * 0.5:
		return
	var dir := (pb - pa) / d
	var nrm := Vector2(-dir.y, dir.x)
	var cnt := int(span / step) + 1
	var s := maxf(R * 0.11, 3.0)
	var w := maxf(1.3, R * 0.042)
	var base := 0.5 if rk == 0 else 0.3
	var ta := float(a.end_ms)
	var dur := maxf(float(b.time_ms) - ta, 1.0)
	for k in cnt:
		var off := g0 + (span * float(k) / float(cnt - 1) if cnt > 1 else span * 0.5)
		var u := off / d
		var a_in := clampf((t - float(b.spawn_ms) - u * FP_IN_SPREAD) / FP_IN_MS, 0.0, 1.0)
		var a_out := 1.0 - clampf((t - ta - u * dur) / FP_OUT_MS, 0.0, 1.0)
		var al := base * a_in * a_out
		if al <= 0.01:
			continue
		var m := pa + dir * off
		var tip := m + dir * s * 0.5
		var chev := PackedVector2Array([tip - dir * s + nrm * s * 0.75, tip, tip - dir * s - nrm * s * 0.75])
		draw_polyline(chev, Color(LINE_COL, al), w, true)


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
			var e := 1.0 - pow(1.0 - k, 3.0)
			var a := (1.0 - k) * (1.0 - 0.4 * k)
			var p := field_to_screen(OrbitConverter.end_pos(n) if st == ST_HOLD_DONE else n.pos)
			var qcol: Color = JudgeDisplay.COLORS[clampi(_state_q[i], 0, 5)]
			# Kurzer, schwacher Blitz auf der Flaeche (nur am Anfang).
			if dt < HIT_FLASH_MS:
				var fc := Color.WHITE if n.key == OrbitNote.KEY_ACCENT else key_col(n.key).lightened(0.35)
				draw_circle(p, R * lerpf(0.95, 1.1, e), Color(fc, 0.2 * (1.0 - dt / HIT_FLASH_MS)),
						true, -1.0, true)
			# Ring in Tastenfarbe (Akzent: halb/halb), dehnt sich aus und blendet.
			var r1 := R * lerpf(1.0, 1.4, e)
			var w1 := maxf(1.5, R * 0.1 * (1.0 - 0.6 * k))
			if n.key == OrbitNote.KEY_ACCENT:
				draw_arc(p, r1, PI * 0.5, PI * 1.5, 32, Color(A_COL.lightened(0.3), 0.85 * a), w1, true)
				draw_arc(p, r1, -PI * 0.5, PI * 0.5, 32, Color(B_COL.lightened(0.3), 0.85 * a), w1, true)
			else:
				draw_arc(p, r1, 0.0, TAU, 56, Color(key_col(n.key).lightened(0.3), 0.85 * a), w1, true)
			# Aussen ein feiner Ring in Stufenfarbe (MAX/300/200/...).
			var r2 := R * lerpf(1.06, 1.62, e)
			draw_arc(p, r2, 0.0, TAU, 64, Color(qcol, 0.6 * a), maxf(1.2, R * 0.045), true)
		ST_MISS, ST_DROP:
			if dt >= MISS_MARK_MS:
				return
			var p := field_to_screen(n.pos_at(_state_t[i]) if st == ST_DROP else n.pos)
			var a := clampf(dt / 40.0, 0.0, 1.0) * (1.0 - smoothstep(MISS_MARK_MS * 0.35, MISS_MARK_MS, dt))
			var h := R * 0.4
			var col := Color(MISS_X_COL, 0.9 * a)
			var w := maxf(2.0, R * 0.11)
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
	var r := clampf(R * 0.13, 4.0, 8.0) * cursor_k
	var down := held[0] or held[1]
	_draw_trail(r)
	draw_circle(p, r + 2.0, Color(0, 0, 0, 0.6), true, -1.0, true)
	draw_circle(p, r, Color(1, 1, 1, 1.0), true, -1.0, true)
	if down:
		draw_arc(p, r + 4.5, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.5, true)


## Weiche kurze Spur hinter dem Cursor (letzte TRAIL_MS Songzeit): ein Band,
## das zur Spitze hin deckender wird. Zeitsprung zurueck = Spur leeren.
func _draw_trail(r: float) -> void:
	var t := t_ms
	if not _trail_t.is_empty() and t < _trail_t[_trail_t.size() - 1]:
		_trail_p.clear()
		_trail_t.clear()
	if _trail_p.is_empty() or _trail_p[_trail_p.size() - 1].distance_to(cursor) > 0.0005:
		_trail_p.append(cursor)
		_trail_t.append(t)
	var drop := 0
	while drop < _trail_t.size() - 1 and t - _trail_t[drop] > TRAIL_MS:
		drop += 1
	if drop > 0:
		_trail_p = _trail_p.slice(drop)
		_trail_t = _trail_t.slice(drop)
	var n := _trail_p.size()
	if n < 2:
		return
	# Von der Spitze rueckwaerts, hoechstens max_len Pixel lang (kurz, auch bei
	# schnellen Spruengen); Deckkraft faellt mit Alter und Abstand.
	var max_len := r * TRAIL_LEN_K
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var acc := 0.0
	var prev := field_to_screen(_trail_p[n - 1])
	for k in range(n - 1, -1, -1):
		var q := field_to_screen(_trail_p[k])
		var seg := prev.distance_to(q)
		var cut := acc + seg > max_len
		if cut and seg > 0.0:
			q = prev.lerp(q, (max_len - acc) / seg)
		acc = minf(acc + seg, max_len)
		var u := minf(1.0 - clampf((t - _trail_t[k]) / TRAIL_MS, 0.0, 1.0), 1.0 - acc / max_len)
		pts.append(q)
		cols.append(Color(1, 1, 1, TRAIL_ALPHA * u * u))
		prev = q
		if cut:
			break
	if pts.size() < 2 or acc < r * 0.5:
		return
	draw_polyline_colors(pts, cols, r * 1.1, true)
