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
## feiner Rahmen sehr leise im Beat. Halten: schmales, transparentes Band entlang des Pfads, Kugel und
## Folgekreis. Treffer: Ring dehnt sich aus und blendet (HIT_MS) in Tastenfarbe,
## aussen ein feiner Ring in Stufenfarbe; dazu bleibt die Marke kurz als
## Bezug stehen: Marke und ein Punkt zeigen, wo der Satellit beim Druck stand
## (links der Marke = zu frueh, kuehl; rechts = zu spaet, warm), nur wenn der
## Druck nicht in der besten Stufe lag. Miss: Umriss des Ziels
## verblasst grau, kleines X (nie ueber dem naechsten Ziel); Fehldruck: kurzes
## Wort am Cursor. Cursor mit weicher kurzer Spur. Kein Glow, keine Partikel.
## Spaetere Ziele sind deckend, aber gedimmt (dunkle Platte unter dem Koerper):
## Ueberlappungen bleiben sauber. Wird ein Ziel zum naechsten, blendet die
## Hervorhebung weich ueber EMPH_MS ein (kein Sprung).

## Feld: Hoehe relativ zur Control-Hoehe, Seitenverhaeltnis 4:3.
const FIELD_H_K := 0.8
const ASPECT := 4.0 / 3.0
## Orbit-Ring relativ zum Zielradius.
const ORBIT_K := 1.3
## Folgekreis beim Halten relativ zum Zielradius (OrbitCore.FOLLOW_RADIUS).
const FOLLOW_K := 2.0
## Halten-Band: Breite relativ zum Zielradius (schmaler als das Ziel, osu! 2,0).
const BAND_K := 1.4
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
## Treffer: Schatten des Orbit-Rings mit Druck-Punkt (frueh/spaet) so lange sichtbar.
const PRESS_DOT_MS := 300.0
## Druck-Punkt: groesster gezeigter Winkel neben der Marke (Grad).
const PRESS_DOT_MAX_DEG := 60.0
## Uebergang "spaeter" -> "naechstes Ziel" (Deckkraft, Rand) in ms.
const EMPH_MS := 110.0
## Folgekreis waechst beim Halten-Beginn weich auf (ms).
const FOLLOW_IN_MS := 140.0
const MISS_MARK_MS := 260.0
## Cursor-Spur (Songzeit-ms) und ihre Deckkraft an der Spitze.
const TRAIL_MS := 90.0
const TRAIL_ALPHA := 0.26
## Hoechste Spurlaenge relativ zum Cursor-Radius.
const TRAIL_LEN_K := 7.0
## Folgepunkte: nur zu Zielen mit Rang < FP_RANKS; Einblenden gestaffelt ueber
## FP_IN_SPREAD ab dem Erscheinen des Ziels, Ausblenden FP_OUT_MS.
const FP_RANKS := 2
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
## Klarheit (docs/modes/orbit_clarity.md):
## Stapel = spaeteres offenes Ziel naeher als STACK_K x Radius am selben Ort; es
## wird als versetzte "Karte" (STACK_OFF x Radius je Lage) hinter dem vorderen
## gezeigt, das vordere traegt die Zahl.
const STACK_K := 0.9
const STACK_OFF := 0.16
## Neustart: erstes Ziel nach einer Luecke >= BREAK_MS (oder nach der Pause:
## Songzeit stand RESUME_REAL_MS Echtzeit still) bekommt einen Countdown-Ring.
const BREAK_MS := 2500.0
const RESUME_REAL_MS := 350
## Halten: "folgen" in den ersten FOLLOW_TIP_MS des Haltens (und bei Warnung).
const FOLLOW_TIP_MS := 900.0
## Erst-Hinweis (Akzent/Halten/Stapel, einmal je Sitzung): Hoechstdauer.
const HINT_MS := 2600.0
const HINT_COL := Color(0.92, 0.94, 1.0)

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
## Settings.orbit_key_hint (0 auto, 1 an, 2 aus; -1 = ohne Settings, dann gilt
## key_hint). Nicht "aus": das naechste Ziel traegt immer seinen Buchstaben und
## Erst-Hinweise erscheinen.
var hint_mode := -1

## Erst-Hinweise je Sitzung (Prozess): Art -> schon gezeigt.
static var _seen_hints: Dictionary = {}
var _hint: Array = []  # [Text, Note-Index, t0]
var _last_t := -INF
var _last_t_real := 0
var _resume_t := -INF
var _resume_idx := -1

var _state := PackedInt32Array()
var _state_t := PackedFloat64Array()
var _state_q := PackedInt32Array()
## Zeitfehler des Drucks (ms, < 0 = zu frueh) und Zeit, seit der ein Ziel das naechste ist.
var _state_dt := PackedFloat64Array()
var _next_t := PackedFloat64Array()
## Sichtbare offene Ziele dieses Frames: [Index, Pixel-Position, Freiraum-Radius].
var _obs: Array = []
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
	var s := get_node_or_null("/root/Settings")
	if s != null and hint_mode < 0:
		hint_mode = int(s.get("orbit_key_hint"))


## Buchstabe im naechsten Ziel (immer, ausser Einstellung "aus").
func letters_on() -> bool:
	return key_hint if hint_mode < 0 else hint_mode != 2


## Erst-Hinweise (gleiche Einstellung; ohne Settings wie key_hint).
func hints_on() -> bool:
	return letters_on()


func setup(p_notes: Array) -> void:
	notes = p_notes
	var n := notes.size()
	_state = PackedInt32Array()
	_state.resize(n)
	_state_t = PackedFloat64Array()
	_state_t.resize(n)
	_state_q = PackedInt32Array()
	_state_q.resize(n)
	_state_dt = PackedFloat64Array()
	_state_dt.resize(n)
	_next_t = PackedFloat64Array()
	_next_t.resize(n)
	_next_t.fill(INF)
	_max_lead = 0.0
	for i in n:
		_max_lead = maxf(_max_lead, float(notes[i].time_ms) - float(notes[i].spawn_ms))
	_first = 0
	_press.clear()
	_lock_t = -INF
	_lock_idx = -1
	hold_warn = {}
	_hint = []
	_last_t = -INF
	_resume_t = -INF
	_resume_idx = -1
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
	if not hold_end:
		_state_dt[index] = float(result.get("dt", 0.0))
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
		"wrong":
			text = "WRONG KEY"
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
		if t_ms - _state_t[_first] < PRESS_DOT_MS + 50.0:
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
	# 1. Rang = Zahl frueherer offener Zeitpunkte.
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
	# Stapel: spaetere offene Ziele am Ort eines frueheren (anderer Zeitpunkt).
	var cover := {}    # verdecktes Ziel -> Lage (1, 2, ...)
	var stack_n := {}  # vorderes Ziel -> Zahl der Ziele dort (inkl. sich)
	for a_i in vis.size():
		var i := vis[a_i]
		if not ranks.has(i) or int(ranks[i]) >= MAX_RANKS:
			continue
		var pi := field_to_screen(notes[i].pos)
		for b_i in a_i:
			var j := vis[b_i]
			if not ranks.has(j) or cover.has(j):
				continue
			if float(notes[i].time_ms) - float(notes[j].time_ms) <= CHORD_EPS_MS:
				continue
			if pi.distance_to(field_to_screen(notes[j].pos)) < R * STACK_K:
				var cnt: int = stack_n.get(j, 1) + 1
				stack_n[j] = cnt
				cover[i] = cnt - 1
				break
	_obs.clear()
	for i in vis:
		if ranks.has(i) and int(ranks[i]) < MAX_RANKS:
			_obs.append([i, field_to_screen(notes[i].pos), R * ((ORBIT_K + 0.1) if int(ranks[i]) < RING_RANKS else 1.05)])
	_track_resume(t, nxt)
	_update_hint(t, vis, ranks, stack_n)
	# 2. Folgepunkte zwischen aufeinanderfolgenden Zeitpunkten (unter allem).
	_draw_follow(t, R, ranks)
	# 3. Objekte wie osu!: spaete zuerst, je Objekt Halten-Band und dann Ziel,
	# so liegen spaetere Objekte (auch ihre Baender) unter frueheren und das
	# naechste Ziel oben und frei. Laufende Halten: Band ganz unten.
	for i in vis:
		if _state[i] == ST_HOLD:
			_draw_band(notes[i], R, 0.8)
	for j in range(vis.size() - 1, -1, -1):
		var i := vis[j]
		var n: OrbitNote = notes[i]
		if _state[i] != ST_PENDING:
			continue
		var rk: int = ranks.get(i, 0)
		if rk >= MAX_RANKS:
			continue
		var is_next := absf(float(n.time_ms) - nxt_t) <= CHORD_EPS_MS
		var em := _emph(i, is_next, t)
		var a := _alpha_of(i, n, em, t)
		if rk >= RING_RANKS:
			a = minf(a, FAR_ALPHA * clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0))
		if n.is_hold:
			_draw_band(n, R, a, rk < RING_RANKS, i)
		if cover.has(i):
			# Verdeckt im Stapel: versetzte Karte ohne eigenen Ring/Satelliten.
			var off := Vector2(1.0, 1.0) * R * STACK_OFF * float(cover[i])
			_draw_body(field_to_screen(n.pos) + off, R * _pop_scale(n, t), n.key,
					maxf(a, 0.5 * clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0)), 0.0)
			continue
		_draw_target(i, n, R, a, is_next, pulse, t, rk < RING_RANKS, em)
		if rk < RING_RANKS and int(stack_n.get(i, 1)) >= 2:
			_draw_stack_count(field_to_screen(n.pos), R, int(stack_n[i]), a)
		if is_next and i == nxt and _is_restart(nxt):
			_draw_countdown(nxt, n, R, t)
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
		_draw_fx(i, notes[i], R, t, nxt)
	_draw_press(t, R)
	_draw_hint(t, R, vis, ranks)
	# 7. Cursor.
	if show_cursor:
		_draw_cursor(R)


## Hervorhebung 0..1: 1 = naechstes Ziel. Blendet weich ein, sobald ein Ziel das
## naechste wird (Songzeit; Sprung zurueck setzt neu an).
func _emph(i: int, is_next: bool, t: float) -> float:
	if not is_next:
		_next_t[i] = INF
		return 0.0
	if _next_t[i] > t:
		# Erstes Ziel der Map / nach einer Luecke: sofort voll (nichts zum Ueberblenden).
		var j := i - 1
		while j >= 0 and _state[j] == ST_PENDING:
			j -= 1
		_next_t[i] = t if j >= 0 and t - _state_t[j] < EMPH_MS else t - EMPH_MS
	return smoothstep(0.0, EMPH_MS, t - _next_t[i])


func _alpha_of(_i: int, n: OrbitNote, em: float, t: float) -> float:
	return clampf((t - float(n.spawn_ms)) / POP_IN_MS, 0.0, 1.0) * lerpf(LATER_ALPHA, 1.0, em)


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
		pulse: float, t: float, with_ring: bool = true, em: float = 1.0) -> void:
	if alpha <= 0.0:
		return
	if not with_ring:
		_draw_body(field_to_screen(n.pos), R * _pop_scale(n, t), n.key, alpha, 0.0)
		return
	var c := field_to_screen(n.pos)
	if i == _lock_idx and t - _lock_t < LOCK_MS:
		var k := (t - _lock_t) / LOCK_MS
		c.x += sin(k * TAU * 3.0) * R * 0.12 * (1.0 - k)
	var r := R * _pop_scale(n, t)
	var ring_r := r * ORBIT_K
	var lw := maxf(1.5, R * 0.05)
	# Orbit-Ring (Puls nur Helligkeit/Breite, dezent).
	var ring_a := (lerpf(0.22, 0.30, em) + 0.08 * kiai + 0.2 * pulse) * alpha
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
	var mk := Color(1, 1, 1, lerpf(0.75, 1.0, em) * alpha)
	var mh := R * 0.2
	draw_line(c + Vector2(0, -ring_r + mh), c + Vector2(0, -ring_r - mh), mk, lw * 2.2, true)
	# Ziel.
	_draw_body(c, r, n.key, alpha, em)
	if is_next and letters_on():
		_draw_key_label(c, r, n.key, alpha * em)
	if sa <= 0.0:
		return
	# Pips: verbleibende Runden ("noch 2 Runden"), gut sichtbar zwischen Ziel
	# und Ring, hell mit dunklem Rand.
	var left := n.laps_left(t)
	if left > 0:
		var pr := maxf(3.2, R * 0.12)
		var gap := pr * 2.7
		var y := c.y + (r + ring_r) * 0.5 + pr * 0.15
		var x0 := c.x - gap * float(left - 1) * 0.5
		for k in left:
			var pp := Vector2(x0 + gap * k, y)
			draw_circle(pp, pr + maxf(1.2, R * 0.035), Color(0, 0, 0, 0.6 * sa), true, -1.0, true)
			draw_circle(pp, pr, Color(0.96, 0.97, 1.0, (0.95 if is_next else 0.8) * sa), true, -1.0, true)
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


## em 0..1 = Hervorhebung (1 = naechstes Ziel: heller, weisser Rand). Unter dem
## Koerper liegt eine dunkle, fast deckende Platte: gedimmte Ziele bleiben
## geschlossene Flaechen, nichts scheint durch.
func _draw_body(c: Vector2, r: float, key: int, alpha: float, em: float) -> void:
	var strong := em > 0.5
	var rim_w := maxf(1.6, r * lerpf(0.065, 0.085, em))
	var dark := lerpf(0.46, 0.30, em)
	var rim_a := Color(A_COL.lightened(0.45), 0.85 * alpha).lerp(Color(1, 1, 1, alpha), em)
	var rim_b := Color(B_COL.lightened(0.45), 0.85 * alpha).lerp(Color(1, 1, 1, alpha), em)
	var edge := Color(0, 0, 0, 0.35 * alpha)
	var plate := Color(PLATE_COL, minf(alpha * 2.4, 0.94))
	match key:
		OrbitNote.KEY_B:
			var h := r * SQUARE_K
			var pts := PackedVector2Array()
			for p in _square:
				pts.append(c + p * h)
			draw_colored_polygon(pts, plate)
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
			draw_circle(c, r, plate, true, -1.0, true)
			_fill_grad(c + Vector2(-r * 0.4, 0.0), r, pa, A_COL.darkened(dark), alpha)
			_fill_grad(c + Vector2(r * 0.4, 0.0), r, pb, B_COL.darkened(dark), alpha)
			draw_arc(c, r + 0.75, 0.0, TAU, 64, edge, 1.5, true)
			draw_arc(c, r - rim_w * 0.6, 0.0, TAU, 64, Color(1, 1, 1, alpha), rim_w * 1.2, true)
			# Doppelrand: zweiter feiner Ring aussen = "beide Tasten".
			var r2 := r + rim_w * 1.5
			draw_arc(c, r2 + 1.0, 0.0, TAU, 64, edge, maxf(1.2, rim_w * 0.6) + 2.0, true)
			draw_arc(c, r2, 0.0, TAU, 64, Color(1, 1, 1, (0.95 if strong else 0.7) * alpha),
					maxf(1.2, rim_w * 0.6), true)
		_:
			var pts := PackedVector2Array()
			for p in _disk:
				pts.append(c + p * r)
			draw_circle(c, r, plate, true, -1.0, true)
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
	if key == OrbitNote.KEY_ACCENT:
		# Beide Buchstaben getrennt, je einer auf seiner Farbhaelfte.
		var fs2 := maxi(10, int(r * (0.56 if maxi(key_labels[0].length(), key_labels[1].length()) <= 1 else 0.36)))
		for k in 2:
			var tx: String = key_labels[k]
			var sz2 := f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			var cx := c.x + r * (0.42 if k == 1 else -0.42)
			var p2 := Vector2(cx - sz2.x * 0.5, c.y + (f.get_ascent(fs2) - f.get_descent(fs2)) * 0.5)
			draw_string_outline(f, p2, tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, maxi(2, int(fs2 * 0.14)),
					Color(0, 0, 0, 0.45 * alpha))
			draw_string(f, p2, tx, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, alpha))
		return
	var text := key_labels[clampi(key, 0, 1)]
	var fs := maxi(10, int(r * (0.78 if text.length() <= 1 else 0.52)))
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := c + Vector2(-sz.x * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.14)),
			Color(0, 0, 0, 0.45 * alpha))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))


## Stapel: kleine Zahl unten rechts ausserhalb des Orbit-Rings ("x2" = hier
## kommen 2 Treffer nacheinander).
func _draw_stack_count(c: Vector2, R: float, cnt: int, alpha: float) -> void:
	var f := get_theme_default_font()
	if f == null or alpha <= 0.0:
		return
	var fs := maxi(11, int(R * 0.42))
	var text := "×%d" % cnt
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := c + Vector2(1.0, 1.0).normalized() * R * (ORBIT_K + 0.5)
	var p := at + Vector2(-sz.x * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	var a := minf(1.0, alpha * 1.4)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(fs * 0.3)), Color(0, 0, 0, 0.6 * a))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92 * a))


## Pause erkennen: Songzeit stand laenger still (Pausenmenue/Intro) und laeuft
## wieder -> das dann naechste Ziel ist ein Neustart.
func _track_resume(t: float, nxt: int) -> void:
	var now := Time.get_ticks_msec()
	if t == _last_t:
		return
	if _last_t > -INF and t > _last_t and now - _last_t_real > RESUME_REAL_MS:
		_resume_t = t
		_resume_idx = nxt
	_last_t = t
	_last_t_real = now


## Erstes Ziel nach Songanfang, Luecke >= BREAK_MS oder Pause.
func _is_restart(i: int) -> bool:
	if i < 0 or i >= notes.size():
		return false
	if i == _resume_idx and _resume_t > -INF:
		return true
	if i == 0:
		return true
	return float(notes[i].time_ms) - float(notes[i - 1].end_ms) >= BREAK_MS


## Countdown-Ring: aeusserer Bogen, leert sich von oben bis zum Treffer.
func _draw_countdown(i: int, n: OrbitNote, R: float, t: float) -> void:
	var start := float(n.spawn_ms)
	if i == _resume_idx and _resume_t > start:
		start = _resume_t
	var total := maxf(float(n.time_ms) - start, 1.0)
	var rest := clampf((float(n.time_ms) - t) / total, 0.0, 1.0)
	if rest <= 0.0 or t < start:
		return
	var c := field_to_screen(n.pos)
	var rr := R * _pop_scale(n, t) * ORBIT_K + R * 0.3
	var w := maxf(2.0, R * 0.08)
	draw_arc(c, rr, 0.0, TAU, 80, Color(1, 1, 1, 0.1), w, true)
	draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * rest, maxi(8, int(80.0 * rest)), Color(1, 1, 1, 0.7), w, true)


## Erst-Begegnung: erstes Akzent-/Halten-/Stapel-Ziel der Sitzung (sichtbar mit
## Ring) bekommt einmal einen kleinen Text daneben.
func _update_hint(t: float, vis: Array[int], ranks: Dictionary, stack_n: Dictionary) -> void:
	if not _hint.is_empty() or not hints_on():
		return
	for i in vis:
		if not ranks.has(i) or int(ranks[i]) >= RING_RANKS:
			continue
		var n: OrbitNote = notes[i]
		var kind := ""
		var text := ""
		if n.key == OrbitNote.KEY_ACCENT and not _seen_hints.has("accent"):
			kind = "accent"
			text = tr("beide Tasten: %s + %s") % [key_labels[0], key_labels[1]]
		elif n.is_hold and not _seen_hints.has("hold"):
			kind = "hold"
			text = tr("halten und der Kugel folgen")
		elif int(stack_n.get(i, 1)) >= 2 and not _seen_hints.has("stack"):
			kind = "stack"
			text = tr("%d Treffer hier nacheinander") % int(stack_n[i])
		if kind != "":
			_seen_hints[kind] = true
			_hint = [text, i, t]
			return


func _draw_hint(t: float, R: float, vis: Array[int], ranks: Dictionary) -> void:
	if _hint.is_empty():
		return
	var i: int = _hint[1]
	var t0: float = _hint[2]
	if i >= notes.size() or t < t0:
		_hint = []
		return
	var st := _state[i]
	var end := t0 + HINT_MS
	if st != ST_PENDING and st != ST_HOLD:
		end = minf(end, _state_t[i] + 250.0)
	if t >= end:
		_hint = []
		return
	var f := get_theme_default_font()
	if f == null:
		return
	var a := clampf((t - t0) / 150.0, 0.0, 1.0) * (1.0 - smoothstep(end - 300.0, end, t))
	var n: OrbitNote = notes[i]
	var c := field_to_screen(n.pos_at(t) if st == ST_HOLD else n.pos)
	var text: String = _hint[0]
	var fs := maxi(12, int(R * 0.36))
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := f.get_ascent(fs)
	var gap := R * ((FOLLOW_K + 0.3) if st == ST_HOLD else (ORBIT_K + 0.45))
	# Freie Seite suchen: unten, oben, rechts, links (Rechteck = Textbox).
	var cands := [
		Rect2(c + Vector2(-sz.x * 0.5, gap), sz),
		Rect2(c + Vector2(-sz.x * 0.5, -gap - sz.y), sz),
		Rect2(c + Vector2(gap, -sz.y * 0.5), sz),
		Rect2(c + Vector2(-gap - sz.x, -sz.y * 0.5), sz),
	]
	var view := Rect2(Vector2.ZERO, size).grow(-4.0)
	for rc: Rect2 in cands:
		if not view.encloses(rc):
			continue
		var free := true
		for j in vis:
			if j == i or not ranks.has(j) or int(ranks[j]) >= MAX_RANKS:
				continue
			var pj := field_to_screen(notes[j].pos)
			var rr := R * (ORBIT_K + 0.1 if int(ranks[j]) < RING_RANKS else 1.05)
			var q := Vector2(clampf(pj.x, rc.position.x, rc.end.x), clampf(pj.y, rc.position.y, rc.end.y))
			if q.distance_to(pj) < rr:
				free = false
				break
		if not free or not _band_free(rc, vis, R):
			continue
		var p := (rc.position + Vector2(0.0, asc)).round()
		draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(fs * 0.32)),
				Color(0, 0, 0, 0.6 * a))
		draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(HINT_COL, 0.92 * a))
		return


## Liegt rc neben allen sichtbaren Halten-Baendern (offen oder laufend)?
func _band_free(rc: Rect2, vis: Array[int], R: float) -> bool:
	for j in vis:
		if not notes[j].is_hold or (_state[j] != ST_PENDING and _state[j] != ST_HOLD):
			continue
		for pp in _band_points(notes[j]):
			var q := Vector2(clampf(pp.x, rc.position.x, rc.end.x), clampf(pp.y, rc.position.y, rc.end.y))
			if q.distance_to(pp) < R * BAND_K * 0.5:
				return false
	return true


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


## Punkt und Richtung bei Bogenlaenge s (Pixel) entlang pts.
static func _along(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for k in range(1, pts.size()):
		var seg := pts[k - 1].distance_to(pts[k])
		if seg <= 0.0:
			continue
		var dir := (pts[k] - pts[k - 1]) / seg
		if acc + seg >= s or k == pts.size() - 1:
			return [pts[k - 1] + dir * clampf(s - acc, 0.0, seg), dir]
		acc += seg
	return [pts[0], Vector2.RIGHT]


static func _path_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for k in range(1, pts.size()):
		l += pts[k - 1].distance_to(pts[k])
	return l


func _draw_band(n: OrbitNote, R: float, alpha: float, detail: bool = false, index: int = -1) -> void:
	if alpha <= 0.0 or n.path.size() < 2:
		return
	_draw_band_body(n, R, alpha)
	if detail:
		_draw_band_detail(n, R, alpha, index)


## Liegt rc frei (kein anderes sichtbares Ziel samt Ring darunter)?
func _rect_free(rc: Rect2, skip: int) -> bool:
	for o in _obs:
		if int(o[0]) == skip:
			continue
		var pj: Vector2 = o[1]
		var q := Vector2(clampf(pj.x, rc.position.x, rc.end.x), clampf(pj.y, rc.position.y, rc.end.y))
		if q.distance_to(pj) < float(o[2]):
			return false
	return true


## Halten schon beim Erscheinen erkennbar: feine Pfeile in Laufrichtung auf dem
## Band und ein kleines "HOLD" (auf dem Band, bei kurzen Baendern hinter dem Ende).
func _draw_band_detail(n: OrbitNote, R: float, alpha: float, index: int = -1) -> void:
	var pts := _band_points(n)
	var total := _path_len(pts)
	var a := minf(1.0, alpha * 1.6)
	var col := key_col(n.key).lightened(0.7)
	var head := R * (ORBIT_K + 0.25)
	var tail := R * 0.45
	var free := total - head - tail
	var long := free > R * 2.4
	var w := maxf(1.4, R * 0.05)
	var s := maxf(R * 0.2, 5.0)
	var fr: Array = [0.22, 0.82] if long else [0.5]
	if free > R * 0.6:
		for u in fr:
			var q: Array = _along(pts, head + free * float(u))
			var m: Vector2 = q[0]
			var dir: Vector2 = q[1]
			var nrm := Vector2(-dir.y, dir.x)
			var tip := m + dir * s * 0.5
			draw_polyline(PackedVector2Array([tip - dir * s + nrm * s * 0.7, tip, tip - dir * s - nrm * s * 0.7]),
					Color(col, 0.75 * a), w, true)
	var f := get_theme_default_font()
	if f == null:
		return
	var fs := maxi(10, int(R * 0.3))
	var text := "HOLD"
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at: Vector2
	if long:
		at = _along(pts, head + free * 0.52)[0]
	else:
		var q2: Array = _along(pts, total)
		at = (q2[0] as Vector2) + (q2[1] as Vector2) * (R * BAND_K * 0.5 + sz.x * 0.5 + R * 0.2)
	# Nur auf freier Stelle: das Wort liegt nie auf einem anderen Ziel oder dessen Ring.
	if not _rect_free(Rect2(at - sz * 0.5, sz).grow(R * 0.08), index):
		return
	var p := (at + Vector2(-sz.x * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)).round()
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(fs * 0.3)),
			Color(0, 0, 0, 0.55 * a))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.9 * a))


func _draw_band_body(n: OrbitNote, R: float, alpha: float) -> void:
	var pts := _band_points(n)
	var col := key_col(n.key)
	var w := R * BAND_K
	var rim := maxf(1.5, R * 0.05)
	var edge := Color(col.lightened(0.3), 0.40 * alpha)
	var body := Color(col.darkened(0.68), 0.62 * alpha)
	draw_polyline(pts, edge, w, true)
	draw_circle(pts[pts.size() - 1], w * 0.5, edge, true, -1.0, true)
	draw_polyline(pts, body, w - rim * 2.0, true)
	draw_circle(pts[pts.size() - 1], w * 0.5 - rim, body, true, -1.0, true)
	# Ende: kleiner Ring.
	draw_arc(pts[pts.size() - 1], R * 0.36, 0.0, TAU, 40, Color(col.lightened(0.5), 0.7 * alpha),
			maxf(1.5, R * 0.06), true)


## Folgepunkte wie osu!: feine Pfeile zwischen aufeinanderfolgenden
## Zeitpunkten (Akkorde = ein Zeitpunkt), nur zu offenen Zielen mit Rang <
## FP_RANKS. Sie blenden mit dem Ziel nacheinander von vorn nach hinten ein und
## verschwinden von vorn, waehrend die Zeit vom einen zum naechsten Ziel laeuft.
func _draw_follow(t: float, R: float, ranks: Dictionary) -> void:
	# Hindernisse: sichtbare offene Ziele (Mitte, Freiraum). Pfeile, die ein
	# anderes Ziel oder dessen Orbit-Ring kreuzen wuerden, entfallen dort.
	var obs: Array = []
	for i in ranks:
		var rk: int = ranks[i]
		if rk < MAX_RANKS:
			obs.append([field_to_screen(notes[i].pos), R * ((ORBIT_K + 0.2) if rk < RING_RANKS else 1.2)])
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
				_draw_fp_pair(notes[prev], n, R, t, rk, obs)
		prev = i
		prev_t = tt


func _draw_fp_pair(a: OrbitNote, b: OrbitNote, R: float, t: float, rk: int, obs: Array) -> void:
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
	var s := maxf(R * 0.15, 5.0)
	var w := maxf(1.4, R * 0.04)
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
		var blocked := false
		for o in obs:
			if m.distance_to(o[0]) < float(o[1]):
				blocked = true
				break
		if blocked:
			continue
		var tip := m + dir * s * 0.5
		var chev := PackedVector2Array([tip - dir * s + nrm * s * 0.62, tip, tip - dir * s - nrm * s * 0.62])
		draw_polyline(chev, Color(LINE_COL, al), w, true)


func _draw_ball(i: int, n: OrbitNote, R: float, t: float) -> void:
	var bp := field_to_screen(n.pos_at(t))
	var col := key_col(n.key)
	var warn := clampf(float(hold_warn.get(i, 0.0)), 0.0, 1.0)
	var since0 := t - _state_t[i]
	var grow := 1.0 - pow(1.0 - clampf(since0 / FOLLOW_IN_MS, 0.0, 1.0), 3.0)
	var fr := R * lerpf(1.15, FOLLOW_K, grow)
	var fcol := Color(1, 1, 1, 0.55 * grow).lerp(Color(WARN_COL, 0.9), warn)
	# Kopf getroffen: gleiche Rueckmeldung wie bei einem Einzelziel.
	if since0 >= 0.0 and since0 < HIT_MS:
		_draw_hit_fx(i, n, field_to_screen(n.pos), R, since0, false)
	draw_arc(bp, fr, 0.0, TAU, 72, fcol, maxf(1.6, R * 0.07), true)
	# Restzeit: heller Bogen auf dem Folgekreis, leert sich bis zum Ende.
	var dur := maxf(float(n.end_ms) - float(n.time_ms), 1.0)
	var rest := clampf((float(n.end_ms) - t) / dur, 0.0, 1.0)
	if rest > 0.01:
		draw_arc(bp, fr, -PI * 0.5, -PI * 0.5 + TAU * rest, maxi(8, int(72.0 * rest)),
				Color(1, 1, 1, 0.9).lerp(Color(WARN_COL, 0.95), warn), maxf(2.4, R * 0.12), true)
	draw_circle(bp, R * 0.6, Color(col.darkened(0.15), 1.0), true, -1.0, true)
	draw_arc(bp, R * 0.6, 0.0, TAU, 48, Color(1, 1, 1, 0.95), maxf(2.0, R * 0.11), true)
	# "folgen": kurz zu Beginn des Haltens und wenn die Kugel wegzulaufen droht.
	var since := t - _state_t[i]
	var ta := maxf(1.0 - smoothstep(FOLLOW_TIP_MS * 0.6, FOLLOW_TIP_MS, since), warn)
	# Erst-Hinweis an diesem Ball sagt schon "folgen": nicht doppelt beschriften.
	if not _hint.is_empty() and int(_hint[1]) == i and warn < 0.02:
		ta = 0.0
	if ta > 0.02:
		var f := get_theme_default_font()
		if f != null:
			var fs := maxi(10, int(R * 0.36))
			var text := tr("folgen")
			var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p := bp + Vector2(-sz.x * 0.5, -fr - R * 0.22)
			draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(fs * 0.3)),
					Color(0, 0, 0, 0.6 * ta))
			draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(1, 1, 1, 0.9 * ta).lerp(Color(WARN_COL.lightened(0.3), ta), warn))


func _draw_fx(i: int, n: OrbitNote, R: float, t: float, nxt: int = -1) -> void:
	var st := _state[i]
	var dt := t - _state_t[i]
	if dt < 0.0:
		return
	match st:
		ST_HIT, ST_HOLD_DONE:
			if dt >= PRESS_DOT_MS:
				return
			var p := field_to_screen(OrbitConverter.end_pos(n) if st == ST_HOLD_DONE else n.pos)
			_draw_hit_fx(i, n, p, R, dt, st == ST_HIT)
		ST_MISS, ST_DROP:
			if dt >= MISS_MARK_MS:
				return
			var p := field_to_screen(n.pos_at(_state_t[i]) if st == ST_DROP else n.pos)
			# Nie ueber dem naechsten Ziel (samt Orbit-Ring).
			if nxt >= 0 and p.distance_to(field_to_screen(notes[nxt].pos)) < R * (ORBIT_K + 0.3):
				return
			var a := clampf(dt / 30.0, 0.0, 1.0) * (1.0 - smoothstep(MISS_MARK_MS * 0.3, MISS_MARK_MS, dt))
			# Umriss des verpassten Ziels verblasst grau (welches war es?).
			if st == ST_MISS:
				_draw_outline(p, R * (1.0 - 0.05 * dt / MISS_MARK_MS), n.key, Color(MISS_COL, 0.55 * a), maxf(1.4, R * 0.055))
			var h := R * 0.22
			var col := Color(MISS_X_COL, 0.85 * a)
			var w := maxf(1.8, R * 0.07)
			draw_line(p - Vector2(h, h), p + Vector2(h, h), col, w, true)
			draw_line(p - Vector2(h, -h), p + Vector2(h, -h), col, w, true)


## Treffer an p (dt ms seit dem Treffer): Ring in Tastenfarbe dehnt sich aus,
## aussen fein die Stufenfarbe. with_dot: Marke und ein Punkt, wo der Satellit
## beim Druck stand (links = frueh, rechts = spaet), nur unterhalb der besten Stufe.
func _draw_hit_fx(i: int, n: OrbitNote, p: Vector2, R: float, dt: float, with_dot: bool) -> void:
	var qcol: Color = JudgeDisplay.COLORS[clampi(_state_q[i], 0, 5)]
	if dt < HIT_MS:
		var k := dt / HIT_MS
		var e := 1.0 - pow(1.0 - k, 3.0)
		var a := (1.0 - k) * (1.0 - 0.4 * k)
		# Kurzer, schwacher Schein auf der Flaeche (nur am Anfang).
		if dt < HIT_FLASH_MS:
			var fc := Color.WHITE if n.key == OrbitNote.KEY_ACCENT else key_col(n.key).lightened(0.35)
			draw_circle(p, R * lerpf(0.95, 1.1, e), Color(fc, 0.2 * (1.0 - dt / HIT_FLASH_MS)),
					true, -1.0, true)
		# Ring in Tastenfarbe (Akzent: halb/halb), dehnt sich aus und blendet.
		var r1 := R * lerpf(1.0, 1.28, e)
		var w1 := maxf(1.5, R * 0.085 * (1.0 - 0.6 * k))
		if n.key == OrbitNote.KEY_ACCENT:
			draw_arc(p, r1, PI * 0.5, PI * 1.5, 32, Color(A_COL.lightened(0.3), 0.85 * a), w1, true)
			draw_arc(p, r1, -PI * 0.5, PI * 0.5, 32, Color(B_COL.lightened(0.3), 0.85 * a), w1, true)
		else:
			draw_arc(p, r1, 0.0, TAU, 56, Color(key_col(n.key).lightened(0.3), 0.85 * a), w1, true)
		# Aussen ein feiner Ring in Stufenfarbe (MAX/300/200/...).
		var r2 := R * lerpf(1.06, 1.46, e)
		draw_arc(p, r2, 0.0, TAU, 64, Color(qcol, 0.6 * a), maxf(1.2, R * 0.04), true)
	# Nur wenn der Druck nicht in der besten Stufe lag: sonst bleibt es ruhig.
	if not with_dot or dt >= PRESS_DOT_MS or _state_q[i] <= 0:
		return
	var fa := 1.0 - smoothstep(PRESS_DOT_MS * 0.4, PRESS_DOT_MS, dt)
	var ring_r := R * ORBIT_K
	var lw := maxf(1.5, R * 0.05)
	var deg := clampf(360.0 * _state_dt[i] / maxf(float(n.lap_ms), 1.0), -PRESS_DOT_MAX_DEG, PRESS_DOT_MAX_DEG)
	var ar := deg_to_rad(deg)
	var ecol := EARLY_COL if deg < 0.0 else LATE_COL
	# Kurzer Bogen von der Marke bis zum Druck-Punkt, Marke als Bezug.
	draw_arc(p, ring_r, -PI * 0.5 + minf(ar, 0.0), -PI * 0.5 + maxf(ar, 0.0), 12, Color(ecol, 0.55 * fa), lw, true)
	var mh := R * 0.14
	draw_line(p + Vector2(0, -ring_r + mh), p + Vector2(0, -ring_r - mh), Color(1, 1, 1, 0.6 * fa), lw * 1.6, true)
	var sp := p + Vector2(sin(ar), -cos(ar)) * ring_r
	var sr := maxf(2.6, R * 0.11)
	draw_circle(sp, sr + maxf(1.2, R * 0.04), Color(0, 0, 0, 0.6 * fa), true, -1.0, true)
	draw_circle(sp, sr, Color(ecol, fa), true, -1.0, true)


## Umriss der Zielform (A Kreis, B Quadrat, Akzent Kreis).
func _draw_outline(c: Vector2, r: float, key: int, col: Color, w: float) -> void:
	if key == OrbitNote.KEY_B:
		var pts := PackedVector2Array()
		for q in _square:
			pts.append(c + q * r * SQUARE_K)
		pts.append(pts[0])
		draw_polyline(pts, col, w, true)
	else:
		draw_arc(c, r, 0.0, TAU, 56, col, w, true)


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
