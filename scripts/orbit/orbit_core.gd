class_name OrbitCore
extends RefCounted

## Orbit-Wertung: Ziele auf zwei Ringen um die Mitte. Der Cursor-WINKEL
## waehlt die Richtung, die Taste den Ring (0 = innen, 1 = aussen). Ein
## Treffer zaehlt nur, wenn Zeitfenster UND Winkel (+-ANGLE_TOL_DEG) stimmen.
## Bogen: Kopf wie ein Tap, danach Taste halten und der wandernden Spitze
## folgen. Zu frueh loslassen oder laenger als ARC_OUT_MS ausserhalb der
## Toleranz = Miss (DROP), wie Mania-Holds.
##
## Zeitfenster, Qualitaeten, Score, Acc, Grade, HP und stats() kommen aus
## ManiaCore: ein internes ManiaCore-Objekt (_tally) zaehlt alles, damit die
## Formeln nur an einer Stelle stehen. Keine Szenen/Autoloads noetig (Mods
## kommen optional aus GameSession, falls vorhanden).

signal note_spawned(index: int)
signal note_judged(index: int, result: Dictionary)
signal arc_started(index: int, quality: int)
signal ring_pressed(ring: int, hit: bool)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

## Gleiche Staffel wie ManiaCore (MAX, PERFECT, GOOD, OK, MEH, MISS).
const Quality := ManiaCore.Quality
const RINGS := 2
## Winkel-Toleranz fuer Taps, Bogen-Koepfe und das Folgen eines Bogens.
const ANGLE_TOL_DEG := 22.0
## So lange darf der Cursor beim Bogen ausserhalb der Toleranz sein.
const ARC_OUT_MS := 150.0
## Zielmitte: nur so nah am Ziel (Grad) gibt es die beste Stufe CORE.
const CENTER_DEG := 9.0

## --- Eigene Orbit-Wertung (nicht Mania): Stufen, Wert, Acc, Grade ---
## Stufen-Index = Quality-Index (0 CORE .. 5 MISS), damit HP/Zaehler/HUD
## weiter funktionieren. Namen (uebersetzt ueber translations/orbit.csv):
const TIER_NAMES: Array[String] = ["CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS"]
## Zeitwert je Stufe.
const TIER_VALUE: Array[float] = [1.0, 0.94, 0.68, 0.40, 0.16, 0.0]
## Zielfaktor: in der Mitte 1,0, am Rand der Toleranz AIM_EDGE_FACTOR.
const AIM_EDGE_FACTOR := 0.88
## Anteil der Kombo-Wertung am Score (Rest = Praezision).
const STREAK_SHARE := 0.1
## Kombo, ab der ein Treffer vollen Streak-Wert hat.
const STREAK_FULL := 100
## Grade-Schwellen (Orbit-Acc): SS braucht ausserdem keinen Miss.
const GRADE_SS := 0.985
const GRADE_STEPS := [[0.95, "S"], [0.90, "A"], [0.82, "B"], [0.72, "C"]]

var notes: Array[OrbitNote] = []
var preempt: float = ManiaCore.BASE_PREEMPT

var _tally := ManiaCore.new()
var _spawn_order: Array[int] = []
var _next_spawn := 0
var _ring_notes: Array = []
var _ring_head: Array[int] = []
var _active_arc: Array[int] = [-1, -1]
var _arc_quality: Array[int] = [0, 0]
## Seit wann der Cursor ausserhalb der Bogen-Toleranz ist (INF = innerhalb).
var _out_since: Array[float] = [INF, INF]
## Zeit der letzten Bogen-Pruefung je Ring (Cursor stand seitdem still).
var _last_check: Array[float] = [0.0, 0.0]
var _judged: Dictionary = {}
var _judged_count := 0
var _finished_emitted := false
var _cursor := 0.0
## Orbit-Wertung: Summe der Trefferwerte, Streak-Summe, gewertete Ziele.
var _val_sum := 0.0
var _streak_sum := 0.0
var _n_done := 0
var _aim_sum := 0.0
var _aim_n := 0

# --- Zaehler und Fenster: alles liegt im ManiaCore-Zaehler ---
var combo: int:
	get: return _tally.combo
var max_combo: int:
	get: return _tally.max_combo
var n_max: int:
	get: return _tally.n_max
var n300: int:
	get: return _tally.n300
var n200: int:
	get: return _tally.n200
var n100: int:
	get: return _tally.n100
var n50: int:
	get: return _tally.n50
var n_miss: int:
	get: return _tally.n_miss
var score: int:
	get: return orbit_score()
var hp: float:
	get: return _tally.hp
var failed: bool:
	get: return _tally.failed
var no_fail: bool:
	get: return _tally.no_fail
var mods: Dictionary:
	get: return _tally.mods
var mod_mult: float:
	get: return _tally.mod_mult
var w_max: float:
	get: return _tally.w_max
var w300: float:
	get: return _tally.w300
var w200: float:
	get: return _tally.w200
var w100: float:
	get: return _tally.w100
var w50: float:
	get: return _tally.w50
var w_miss: float:
	get: return _tally.w_miss


## p_notes: Ergebnis von OrbitConverter.convert (nach time_ms sortiert).
## od: OverallDifficulty der Map (gleiche Fenster wie Mania).
## scroll_scale: wie ManiaCore (teilt nur die Anflugzeit, rein visuell).
## hp_drain: HPDrainRate der Map. p_mods: Mod-Dictionary, null = GameSession.
func setup(p_notes: Array[OrbitNote], od: float, scroll_scale: float = 1.0,
		hp_drain: float = 5.0, p_mods = null) -> void:
	notes = p_notes
	_tally = ManiaCore.new()
	_tally.w_max = DifficultyCalc.mania_window_max(od)
	_tally.w300 = DifficultyCalc.mania_window_300(od)
	_tally.w200 = DifficultyCalc.mania_window_200(od)
	_tally.w100 = DifficultyCalc.mania_window_100(od)
	_tally.w50 = DifficultyCalc.mania_window_50(od)
	_tally.w_miss = DifficultyCalc.mania_window_miss(od)
	_tally._hp_miss_damage = 0.04 + 0.04 * (hp_drain / 10.0)
	var m: Dictionary = p_mods if p_mods is Dictionary else ManiaCore.session_mods()
	_tally.mods = m.duplicate()
	_tally.mod_mult = ManiaCore.mod_multiplier(m)
	_tally.no_fail = bool(m.get("NF", false))
	_tally._total_notes = notes.size()
	preempt = ManiaCore.preempt_for(scroll_scale)
	_ring_notes = []
	_ring_head = []
	for r in RINGS:
		_ring_notes.append([])
		_ring_head.append(0)
	_spawn_order = []
	for i in notes.size():
		_spawn_order.append(i)
		_ring_notes[clampi(notes[i].ring, 0, RINGS - 1)].append(i)
	var by_time := func(a: int, b: int) -> bool:
		if notes[a].time_ms != notes[b].time_ms:
			return notes[a].time_ms < notes[b].time_ms
		return a < b
	_spawn_order.sort_custom(by_time)
	for r in RINGS:
		(_ring_notes[r] as Array).sort_custom(by_time)
	_active_arc = [-1, -1]
	_arc_quality = [0, 0]
	_out_since = [INF, INF]
	_last_check = [0.0, 0.0]
	_judged = {}
	_judged_count = 0
	_next_spawn = 0
	_finished_emitted = false
	_cursor = 0.0
	_val_sum = 0.0
	_streak_sum = 0.0
	_n_done = 0
	_aim_sum = 0.0
	_aim_n = 0


## Scroll-Faktor waehrend des Spiels aendern (nur Anflugzeit).
func set_scroll_scale(scroll_scale: float) -> void:
	preempt = ManiaCore.preempt_for(scroll_scale)


func update(t_ms: float) -> void:
	while _next_spawn < _spawn_order.size() \
			and notes[_spawn_order[_next_spawn]].time_ms - preempt <= t_ms:
		note_spawned.emit(_spawn_order[_next_spawn])
		_next_spawn += 1
	_check_arcs(t_ms)
	for r in RINGS:
		_expire_ring(r, t_ms)
	if _judged_count >= notes.size() and _next_spawn >= _spawn_order.size() \
			and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Cursor-Winkel (0 = oben, im Uhrzeigersinn) zur Event-Zeit t_ms. Bis t_ms
## stand der Cursor noch am alten Winkel; erst danach gilt der neue.
func cursor_moved(cursor_deg: float, t_ms: float) -> void:
	_check_arcs(t_ms)
	_cursor = OrbitNote.wrap_deg(cursor_deg)
	_check_arcs(t_ms)


## Taste fuer ring gedrueckt (0 = innen, 1 = aussen), Cursor bei cursor_deg.
func key_down(ring: int, t_ms: float, cursor_deg: float) -> void:
	if ring < 0 or ring >= RINGS or notes.is_empty():
		return
	cursor_moved(cursor_deg, t_ms)
	_expire_ring(ring, t_ms)
	if _active_arc[ring] >= 0:
		ring_pressed.emit(ring, false)
		return
	var lane: Array = _ring_notes[ring]
	var idx := -1
	var dt := 0.0
	var err := 0.0
	for j in range(_ring_head[ring], lane.size()):
		var i: int = lane[j]
		if _judged.has(i):
			continue
		var n := notes[i]
		var d := t_ms - n.time_ms
		if d < -w_miss:
			break
		if d > w50:
			continue
		var e := OrbitNote.dist_deg(_cursor, n.angle_at(t_ms))
		if e > ANGLE_TOL_DEG:
			continue
		idx = i
		dt = d
		err = e
		break
	if idx < 0:
		ring_pressed.emit(ring, false)
		return
	if dt < -w50:
		# Zu frueh, aber gezielt: frisst das Ziel (Mania-Verhalten).
		_miss(idx, dt, err)
		ring_pressed.emit(ring, false)
		return
	var q: int = _tally._quality_for(absf(dt))
	if q == Quality.MAX and err > CENTER_DEG:
		q = Quality.PERFECT  # Zeit perfekt, aber nicht mittig: SHARP statt CORE
	_aim_sum += err
	_aim_n += 1
	if notes[idx].is_arc:
		_active_arc[ring] = idx
		_arc_quality[ring] = q
		_out_since[ring] = INF
		_last_check[ring] = t_ms
		_tally.combo += 1
		_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
		_judged[idx] = {"pending": true, "dt": dt, "angle_err": err}
		arc_started.emit(idx, q)
	else:
		_apply_hit(idx, q, dt, err)
	ring_pressed.emit(ring, true)


## Taste fuer ring losgelassen.
func key_up(ring: int, t_ms: float) -> void:
	if ring < 0 or ring >= RINGS:
		return
	_check_arcs(t_ms)
	var h: int = _active_arc[ring]
	if h < 0:
		return
	# Kurz vor dem Ende loslassen ist ok (1.5x 50er-Fenster, wie Mania).
	var ok := t_ms >= notes[h].end_ms - w50 * 1.5
	_finish_arc(ring, ok, "" if ok else "RELEASE")


func accuracy() -> float:
	if _n_done == 0:
		return 1.0
	return _val_sum / float(_n_done)


func grade() -> String:
	var acc := accuracy()
	if acc >= GRADE_SS and _tally.n_miss == 0:
		return "SS"
	for g in GRADE_STEPS:
		if acc >= float(g[0]):
			return str(g[1])
	return "D"


## Orbit-Score 0..1.000.000 (x Mod-Faktor): 90 % Praezision (Zeitwert x
## Zielfaktor je Ziel), 10 % Streak (Trefferwert x Kombo-Anteil bis 100).
func orbit_score() -> int:
	var n := float(maxi(notes.size(), 1))
	var raw := (1.0 - STREAK_SHARE) * _val_sum / n + STREAK_SHARE * _streak_sum / n
	return int(round(1000000.0 * raw * _tally.mod_mult))


## Wert eines Treffers: Zeitstufe x Zielfaktor (mittig 1,0, Rand 0,88).
static func hit_value(q: int, angle_err: float) -> float:
	var tv: float = TIER_VALUE[clampi(q, 0, 5)]
	var k := clampf((angle_err - CENTER_DEG) / maxf(ANGLE_TOL_DEG - CENTER_DEG, 0.001), 0.0, 1.0)
	return tv * lerpf(1.0, AIM_EDGE_FACTOR, k)


## Mittlerer Zielfehler (Grad) aller Treffer.
func mean_aim_err() -> float:
	return _aim_sum / float(maxi(_aim_n, 1))


## Wie ManiaCore.stats() (gleiche Felder fuer Results/Scores/Lobby), aber
## Score, Acc und Grade nach Orbit-Regeln; "mode": "orbit".
func stats() -> Dictionary:
	var s: Dictionary = _tally.stats()
	s["score"] = orbit_score()
	s["accuracy"] = accuracy()
	s["grade"] = grade()
	s["aim_err"] = mean_aim_err()
	s["mode"] = "orbit"
	return s


func _count_value(q: int, err: float) -> void:
	var v := hit_value(q, err) if q != Quality.MISS else 0.0
	_val_sum += v
	_streak_sum += v * minf(float(_tally.combo) / float(STREAK_FULL), 1.0)
	_n_done += 1


func is_judged(index: int) -> bool:
	return _judged.has(index)


## Index des laufenden Bogens auf ring, sonst -1.
func active_arc(ring: int) -> int:
	return _active_arc[ring]


## Letzter bekannter Cursor-Winkel (0-360).
func cursor_deg() -> float:
	return _cursor


## Wie lange der Cursor beim Bogen auf ring schon ausserhalb ist (0 = innen).
func arc_out_ms(ring: int, t_ms: float) -> float:
	if _active_arc[ring] < 0 or _out_since[ring] == INF:
		return 0.0
	return maxf(t_ms - _out_since[ring], 0.0)


## Zeitfehler des Bogen-Kopfs (ms, + = spaet), solange er laeuft; sonst 0.
func arc_head_dt(index: int) -> float:
	var j: Dictionary = _judged.get(index, {})
	return float(j.get("dt", 0.0))


## Laufende Boegen pruefen: Cursor ausserhalb > ARC_OUT_MS = DROP, Ende
## erreicht = Kopf-Qualitaet einloesen.
func _check_arcs(t_ms: float) -> void:
	for r in RINGS:
		var h: int = _active_arc[r]
		if h < 0:
			continue
		var n := notes[h]
		var tc := minf(t_ms, n.end_ms)
		if OrbitNote.dist_deg(_cursor, n.angle_at(tc)) > ANGLE_TOL_DEG:
			if _out_since[r] == INF:
				_out_since[r] = _exit_time(n, r, tc)
			if tc - _out_since[r] > ARC_OUT_MS:
				_finish_arc(r, false, "OUT")
				continue
		else:
			_out_since[r] = INF
		_last_check[r] = tc
		if t_ms >= n.end_ms:
			_finish_arc(r, true, "")


## Genauer Zeitpunkt, an dem die Spitze den still stehenden Cursor verlassen
## hat (zwischen letzter Pruefung und tc; die Spitze laeuft linear).
func _exit_time(n: OrbitNote, r: int, tc: float) -> float:
	var t0 := clampf(_last_check[r], n.time_ms, tc)
	var d0 := OrbitNote.delta_deg(_cursor, n.angle_at(t0))
	if absf(d0) > ANGLE_TOL_DEG or n.duration_ms() <= 0.0:
		return t0
	var v := n.span_deg() / n.duration_ms()
	if v == 0.0:
		return tc
	var edge := ANGLE_TOL_DEG if v > 0.0 else -ANGLE_TOL_DEG
	return clampf(t0 + (edge - d0) / v, t0, tc)


func _expire_ring(r: int, t_ms: float) -> void:
	var lane: Array = _ring_notes[r]
	while _ring_head[r] < lane.size():
		var idx: int = lane[_ring_head[r]]
		if _judged.has(idx):
			_ring_head[r] += 1
			continue
		if t_ms > notes[idx].time_ms + w50 and _active_arc[r] != idx:
			_miss(idx, t_ms - notes[idx].time_ms,
					OrbitNote.dist_deg(_cursor, notes[idx].angle_deg))
			continue
		break


func _finish_arc(r: int, held_to_end: bool, reason: String) -> void:
	var idx: int = _active_arc[r]
	_active_arc[r] = -1
	_out_since[r] = INF
	if idx < 0:
		return
	var head: Dictionary = _judged.get(idx, {})
	var dt := float(head.get("dt", 0.0))
	var err := float(head.get("angle_err", 0.0))
	if not held_to_end:
		_lose_hp_and_combo()
		var dropped := {
			"quality": Quality.MISS, "dt": dt, "angle_err": err, "ring": r,
			"hold_end": true, "held": false, "miss_kind": "DROP",
			"drop_reason": reason, "late": false,
		}
		_store(idx, dropped)
		return
	var q: int = _arc_quality[r]
	_tally._count_quality(q)
	_tally._add_score(q)
	_count_value(q, err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": dt, "angle_err": err, "ring": r,
		"hold_end": true, "held": true, "miss_kind": "", "late": dt > 0.0,
	})


func _apply_hit(idx: int, q: int, dt: float, err: float) -> void:
	_tally._count_quality(q)
	_tally.combo += 1
	_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
	_tally._add_score(q)
	_count_value(q, err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": dt, "late": dt > 0.0, "angle_err": err,
		"ring": notes[idx].ring, "miss_kind": "",
	})


func _miss(idx: int, dt: float, err: float) -> void:
	_lose_hp_and_combo()
	_store(idx, {
		"quality": Quality.MISS, "dt": dt, "angle_err": err,
		"ring": notes[idx].ring, "miss_kind": "FULL", "late": false,
	})


func _lose_hp_and_combo() -> void:
	_count_value(Quality.MISS, 0.0)
	_tally.n_miss += 1
	_tally.combo = 0
	_tally._add_score(Quality.MISS)
	_tally.hp = maxf(_tally.hp - _tally._hp_miss_damage, 0.0)
	hp_changed.emit(_tally.hp)
	if _tally.hp <= 0.0 and not _tally.no_fail:
		_tally.failed = true


func _heal(q: int) -> void:
	_tally.hp = minf(_tally.hp + float(_tally._hp_heal[q]), 1.0)
	hp_changed.emit(_tally.hp)


func _store(idx: int, result: Dictionary) -> void:
	_judged[idx] = result
	_judged_count += 1
	note_judged.emit(idx, result)


# ---------------------------------------------------------------------------
# Bot (Autoplay-Varianten, Tests)
# ---------------------------------------------------------------------------

## Plan fuer einen "menschlichen" Bot: je Ziel [Zeitversatz ms (+ = spaet),
## Zielfehler Grad, auslassen]. Deterministisch ueber seed. sigma_t/sigma_a =
## Streuung (Normalverteilung, auf 3 sigma gedeckelt); miss_every > 0 laesst
## jedes n-te Ziel aus. sigma 0 = perfekt.
static func bot_plan(p_notes: Array, seed: int, sigma_t: float, sigma_a: float,
		miss_every: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	out.resize(p_notes.size())
	for i in p_notes.size():
		var ot := 0.0
		var oa := 0.0
		if sigma_t > 0.0:
			ot = clampf(rng.randfn(0.0, sigma_t), -3.0 * sigma_t, 3.0 * sigma_t)
		if sigma_a > 0.0:
			oa = clampf(rng.randfn(0.0, sigma_a), -3.0 * sigma_a, 3.0 * sigma_a)
		out[i] = [ot, oa, miss_every > 0 and i % miss_every == miss_every - 1]
	return out
