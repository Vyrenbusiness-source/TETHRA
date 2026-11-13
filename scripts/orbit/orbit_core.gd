class_name OrbitCore
extends RefCounted

## Orbit-Wertung (Satelliten, docs/modes/orbit_satellit.md): Ziele liegen im Feld
## (0..1 x 0..1) an OrbitNote.pos. Ein Treffer zaehlt nur, wenn Zeitfenster
## (OD wie osu!standard, tier_windows) UND Cursor im Trefferradius (AIM_RADIUS x Zielradius) UND die
## richtige Taste stimmen. Taste 0 = A, 1 = B; Akzent (key 2) = beide Tasten
## innerhalb ACCENT_MS, gewertet beim zweiten Druck.
## Nur das fruehste offene Ziel ist trefferbar (Notelock), ausser es liegt im
## selben Zeitpunkt (Akzent). Ein Druck ohne Treffer sendet press_missed mit
## Grund "aim" | "key" | "early" | "lock" und frisst kein Ziel.
## Halten (is_hold): Kopf wie ein Tap, danach Taste halten und der Kugel
## (OrbitNote.pos_at) im Folgeradius (FOLLOW_RADIUS x Zielradius) folgen. Mehr
## als HOLD_OUT_MS draussen oder vor Ende - 50er-Fenster losgelassen = MISS
## (miss_kind "DROP"), sonst zaehlt die Kopf-Qualitaet.
##
## Alle Ereignisse werden in Zeitreihenfolge exakt verarbeitet: ablaufende Ziele,
## Halte-Austritte (analytisch aus Pfad und Cursor gerechnet) und Eingaben. Das
## Ergebnis haengt nicht von der Bildrate ab. Einheiten: Feld (0..1); aim_err in
## stats() = Feld-Einheiten x 100.
##
## Zeitfenster, Qualitaeten, HP und Zaehler kommen aus einem internen
## ManiaCore-Objekt (_tally); Score, Acc, Grade nach Orbit-Regeln. Keine Szenen/
## Autoloads noetig (Mods optional aus GameSession).

signal note_spawned(index: int)
signal note_judged(index: int, result: Dictionary)
signal hold_started(index: int, quality: int)
signal key_pressed(key: int, hit: bool)
## Druck ohne Treffer: Cursor-Ort (Feld), Taste und Grund "aim" | "key" |
## "early" | "lock".
signal press_missed(pos: Vector2, key: int, reason: String)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

const Quality := ManiaCore.Quality
const KEYS := 2
## Standard-Zielradius (Feld-Einheiten) und Faktoren.
const DEFAULT_TARGET_RADIUS := 0.045
const AIM_RADIUS := 1.15
const FOLLOW_RADIUS := 2.0
## Beide Tasten des Akzents innerhalb dieser Zeit.
const ACCENT_MS := 40.0
## So lange darf die Kugel beim Halten ausserhalb des Folgeradius sein.
const HOLD_OUT_MS := 150.0
## Druck so weit vor dem EDGE-Fenster heisst noch "early" (sonst gar nichts).
const EARLY_MS := 40.0

const ORBIT_MODS := ["HD", "FI", "PR"]
const ORBIT_MOD_ORDER := ["HD", "FI", "PR", "NF", "SV"]
## HD/FI 1,06, PR (Fenster und Radius 30 % enger) 1,12; NF/SV aus ManiaCore.
const ORBIT_MOD_MULT := {"HD": 1.06, "FI": 1.06, "PR": 1.12}
const PR_SCALE := 0.7

const TIER_NAMES: Array[String] = ["CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS"]
const TIER_VALUE: Array[float] = [1.0, 0.94, 0.68, 0.40, 0.16, 0.0]
## Zielfaktor: bis AIM_FULL_FRAC des Trefferradius 1,0, linear bis AIM_EDGE_FACTOR am Rand.
const AIM_FULL_FRAC := 0.5
const AIM_EDGE_FACTOR := 0.88
const STREAK_SHARE := 0.1
const STREAK_FULL := 100
const GRADE_SS := 0.985
const GRADE_STEPS := [[0.95, "S"], [0.90, "A"], [0.82, "B"], [0.72, "C"]]

## Replays (deterministischer Modus): Eingaben auf ganze ms und Tausendstel Feld
## gerundet, nie vor die aktuelle Zeit gelegt. Cursor-Aufnahme nur bei Aenderung
## > REC_MIN_Q (Tausendstel je Achse) und fruehestens REC_GAP_MS nach dem letzten
## Eintrag; vor jedem Tastenereignis wird der aktuelle Cursor nachgetragen.
const REC_MIN_Q := 3
const REC_GAP_MS := 8.0
const Q_LIMIT := 4000
## Replay-Format 4 (Satelliten + Anti-Mash: falsche Taste = Miss, Fenster wie osu!standard,
## Runde = 2/4 Beats bei schnellen Songs; ab Client 1.28.0). Kleineres meta.orbit_rules = "aeltere Version".
const REPLAY_RULES := 5
## [t, EV_CURSOR, x, y] / [t, EV_DOWN + k] / [t, EV_UP + k]; x/y Tausendstel Feld.
const EV_CURSOR := 0
const EV_DOWN := 1
const EV_UP := 3
## Regel-Marke [0, EV_RULES, REPLAY_RULES] am Anfang jedes Replays.
const EV_RULES := 9

var notes: Array[OrbitNote] = []
## Zielradius, Trefferradius, Folgeradius dieses Laufs (Feld-Einheiten, PR enger).
var target_radius := DEFAULT_TARGET_RADIUS
var aim_radius := DEFAULT_TARGET_RADIUS * AIM_RADIUS
var follow_radius := DEFAULT_TARGET_RADIUS * FOLLOW_RADIUS

var _tally := ManiaCore.new()
var _spawn_order: Array[int] = []
var _next_spawn := 0
var _order: Array[int] = []
var _head := 0
var _holds: Dictionary = {}
var _hold_times: Dictionary = {}
var _judged: Dictionary = {}
var _judged_count := 0
var _finished_emitted := false
var _cursor := Vector2.ZERO
var _time := -INF
var _down_t: Array[float] = [-INF, -INF]
var _val_sum := 0.0
var _streak_sum := 0.0
var _n_done := 0
var _aim_sum := 0.0
var _aim_n := 0
var deterministic := false
## Anti-Mash (Regeln 4). Nur Messungen/Tests schalten es aus (Vorher-Werte); Spiel und Replay: immer an.
var anti_mash := true
var recording := false
var replay_log: Array = []
var _cur_q := Vector2i(-99999, -99999)
var _pend_q := Vector2i(-99999, -99999)
var _pend_t := 0.0
var _has_pend := false
var _rec_t := -INF

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


## p_notes: Ergebnis von OrbitConverter.convert. od: OverallDifficulty (Fenster wie
## osu!standard, tier_windows). p_mods: Mod-Dictionary, null = GameSession. p_target_radius: Zielradius
## in Feld-Einheiten. hp_drain: HPDrainRate der Map.
func setup(p_notes: Array[OrbitNote], od: float, p_mods = null,
		p_target_radius: float = DEFAULT_TARGET_RADIUS, hp_drain: float = 5.0) -> void:
	notes = p_notes
	_tally = ManiaCore.new()
	var w := tier_windows(od)
	_tally.w_max = w[0]
	_tally.w300 = w[1]
	_tally.w200 = w[2]
	_tally.w100 = w[3]
	_tally.w50 = w[4]
	_tally.w_miss = w[5]
	_tally._hp_miss_damage = 0.04 + 0.04 * (hp_drain / 10.0)
	var m: Dictionary = p_mods if p_mods is Dictionary else ManiaCore.session_mods()
	_tally.mods = m.duplicate()
	_tally.mod_mult = mod_multiplier(m)
	_tally.no_fail = bool(m.get("NF", false))
	var k := window_scale(m)
	_tally.w_max *= k
	_tally.w300 *= k
	_tally.w200 *= k
	_tally.w100 *= k
	_tally.w50 *= k
	_tally.w_miss *= k
	target_radius = p_target_radius * k
	aim_radius = target_radius * AIM_RADIUS
	follow_radius = target_radius * FOLLOW_RADIUS
	_tally._total_notes = notes.size()
	_spawn_order = []
	_order = []
	_hold_times = {}
	for i in notes.size():
		_spawn_order.append(i)
		_order.append(i)
		if notes[i].is_hold:
			_hold_times[i] = _vertex_times(notes[i])
	var by_spawn := func(a: int, b: int) -> bool:
		if notes[a].spawn_ms != notes[b].spawn_ms:
			return notes[a].spawn_ms < notes[b].spawn_ms
		return a < b
	var by_time := func(a: int, b: int) -> bool:
		if notes[a].time_ms != notes[b].time_ms:
			return notes[a].time_ms < notes[b].time_ms
		return a < b
	_spawn_order.sort_custom(by_spawn)
	_order.sort_custom(by_time)
	_head = 0
	_holds = {}
	_judged = {}
	_judged_count = 0
	_next_spawn = 0
	_finished_emitted = false
	_cursor = Vector2.ZERO
	_time = -INF
	_down_t = [-INF, -INF]
	_val_sum = 0.0
	_streak_sum = 0.0
	_n_done = 0
	_aim_sum = 0.0
	_aim_n = 0
	_cur_q = Vector2i(-99999, -99999)
	_pend_q = _cur_q
	_has_pend = false
	_rec_t = -INF
	replay_log = []


## Zeitpunkte der Pfad-Ecken (konstante Geschwindigkeit wie OrbitNote.pos_at).
static func _vertex_times(n: OrbitNote) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var acc := PackedFloat64Array()
	var total := 0.0
	acc.append(0.0)
	for i in range(1, n.path.size()):
		total += n.path[i - 1].distance_to(n.path[i])
		acc.append(total)
	var dur := n.end_ms - n.time_ms
	for i in acc.size():
		out.append(n.time_ms + (dur * acc[i] / total if total > 0.0 else 0.0))
	return out


## Zeitfenster (+- ms, ohne Mods) [CORE, SHARP, GOOD, FAIR, EDGE, frueh]. Regeln 4 wie
## osu!standard: std300 = 80 - 6 OD, std100 = 140 - 8 OD, std50 = 200 - 10 OD; CORE =
## std300 / 2, SHARP = std300, GOOD = std100, FAIR = (std100 + std50) / 2, EDGE = std50,
## ausserhalb Miss. "frueh" (EDGE + EARLY_MS) trennt nur die Fehldruck-Gruende
## "early"/"far". legacy = Fenster vor Regeln 4 (wie Mania), nur fuer Vorher-Messungen.
static func tier_windows(od: float, legacy: bool = false) -> PackedFloat64Array:
	if legacy:
		return PackedFloat64Array([DifficultyCalc.mania_window_max(od), DifficultyCalc.mania_window_300(od),
			DifficultyCalc.mania_window_200(od), DifficultyCalc.mania_window_100(od),
			DifficultyCalc.mania_window_50(od), DifficultyCalc.mania_window_miss(od)])
	var s300 := DifficultyCalc.window_perfect(od)
	var s100 := DifficultyCalc.window_good(od)
	var s50 := DifficultyCalc.window_meh(od)
	return PackedFloat64Array([s300 * 0.5, s300, s100, (s100 + s50) * 0.5, s50, s50 + EARLY_MS])


static func window_scale(p_mods: Dictionary) -> float:
	return PR_SCALE if bool(p_mods.get("PR", false)) else 1.0


static func mod_multiplier(p_mods: Dictionary) -> float:
	var m := ManiaCore.mod_multiplier(p_mods)
	for k in ORBIT_MOD_MULT:
		if bool(p_mods.get(k, false)):
			m *= float(ORBIT_MOD_MULT[k])
	return m


static func mod_list(p_mods: Dictionary) -> Array:
	var out := []
	for k in ORBIT_MOD_ORDER:
		if bool(p_mods.get(k, false)):
			out.append(k)
	return out


static func mods_text(p_mods: Dictionary) -> String:
	return " ".join(mod_list(p_mods))


static func replay_mods(data: Dictionary) -> Dictionary:
	var meta = data.get("meta", {})
	var m = meta.get("mods", {}) if meta is Dictionary else {}
	var out := {}
	for k in ORBIT_MOD_ORDER:
		out[k] = bool(m.get(k, false)) if m is Dictionary else false
	return out


## Replay-Modus einschalten (nach setup): record = Eingaben mitschreiben.
func set_replay_mode(record: bool) -> void:
	deterministic = true
	recording = record
	if record:
		replay_log = [[0, EV_RULES, REPLAY_RULES]]


func update(t_ms: float) -> void:
	while _next_spawn < _spawn_order.size() \
			and notes[_spawn_order[_next_spawn]].spawn_ms <= t_ms:
		note_spawned.emit(_spawn_order[_next_spawn])
		_next_spawn += 1
	_advance(floorf(t_ms) if deterministic else t_ms)
	if _judged_count >= notes.size() and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Cursor zur Event-Zeit t_ms (Feld-Koordinaten). Bis t_ms stand er am alten Ort.
func cursor_moved(pos: Vector2, t_ms: float) -> void:
	if not deterministic:
		_do_cursor(pos, maxf(t_ms, _time))
		return
	if _tally.failed or notes.is_empty():
		return
	var q := Vector2i(_q_axis(pos.x), _q_axis(pos.y))
	var te := _q_time(t_ms)
	_pend_q = q
	_pend_t = te
	if q == _cur_q:
		_has_pend = false
		return
	if recording and _cur_q.x > -99999:
		if (absi(q.x - _cur_q.x) <= REC_MIN_Q and absi(q.y - _cur_q.y) <= REC_MIN_Q) \
				or te - _rec_t < REC_GAP_MS:
			_has_pend = true
			return
	_has_pend = false
	apply_event([int(te), EV_CURSOR, q.x, q.y])


## Taste gedrueckt (0 = A, 1 = B). Der Cursor ist der zuletzt gemeldete Ort.
func key_down(k: int, t_ms: float) -> void:
	if k < 0 or k >= KEYS or notes.is_empty():
		return
	if not deterministic:
		_do_down(k, maxf(t_ms, _time))
		return
	if _tally.failed:
		return
	var te := _q_time(t_ms)
	_flush_pending()
	apply_event([int(te), EV_DOWN + k])


func key_up(k: int, t_ms: float) -> void:
	if k < 0 or k >= KEYS or notes.is_empty():
		return
	if not deterministic:
		_do_up(k, maxf(t_ms, _time))
		return
	if not _tally.failed:
		var te := _q_time(t_ms)
		_flush_pending()
		apply_event([int(te), EV_UP + k])


func _flush_pending() -> void:
	if _has_pend and _pend_q != _cur_q:
		apply_event([int(_pend_t), EV_CURSOR, _pend_q.x, _pend_q.y])
	_has_pend = false


func _do_cursor(pos: Vector2, t: float) -> void:
	_advance(t)
	_cursor = pos
	for idx in _holds:
		var h: Dictionary = _holds[idx]
		var ins := _hold_inside(idx, t)
		if ins != h.inside:
			h.inside = ins
			h.out_since = INF if ins else t
		h.checked = t


func _hold_inside(idx: int, t: float) -> bool:
	return _cursor.distance_to(notes[idx].pos_at(t)) <= follow_radius


func _do_down(k: int, t: float) -> void:
	_advance(t)
	if _tally.failed:
		return
	var other := 1 - k
	var ready := _down_t[other] > -INF and t - _down_t[other] <= ACCENT_MS
	var first := _first_open()
	if first < 0:
		return
	var t0 := notes[first].time_ms
	var rs: Array = []
	var hit := -1
	var hit_err := 0.0
	var pending := false
	var later := -1
	var key_victim := -1
	var key_err := 0.0
	for j in range(_head, _order.size()):
		var i := _order[j]
		if _judged.has(i):
			continue
		var n := notes[i]
		var d := t - n.time_ms
		if d < -_tally.w50:
			if n.time_ms == t0:
				rs.append("early" if d >= -_tally.w_miss else "far")
			break
		if d > _tally.w50:
			continue
		var e := _cursor.distance_to(n.pos)
		var aim_ok := e <= aim_radius
		var is_accent := n.key == OrbitNote.KEY_ACCENT
		if n.time_ms == t0:
			if hit >= 0:
				continue
			if not aim_ok:
				rs.append("aim")
			elif is_accent:
				if ready:
					hit = i
					hit_err = e
				else:
					pending = true
			elif n.key == k:
				hit = i
				hit_err = e
			else:
				rs.append("key")
				if key_victim < 0:
					key_victim = i
					key_err = e
		elif later < 0 and aim_ok and (n.key == k or (is_accent and ready)):
			later = i
	if hit < 0:
		_down_t[k] = t
		if pending:
			return
		var reason := ""
		# Anti-Mash: falsche Taste auf das offene Ziel (Cursor drauf, 50er-Fenster, kein
		# passendes Ziel fuer diese Taste) = sofort Miss. Akzent zaehlt nur mit beiden Tasten.
		if anti_mash and key_victim >= 0 and later < 0:
			_miss(key_victim, t - notes[key_victim].time_ms, key_err)
			key_pressed.emit(k, false)
			press_missed.emit(_cursor, k, "wrong")
			return
		if later >= 0:
			reason = "lock"
		elif rs.has("key"):
			reason = "key"
		elif rs.has("aim"):
			reason = "aim"
		elif rs.has("early"):
			reason = "early"
		key_pressed.emit(k, false)
		if reason != "":
			press_missed.emit(_cursor, k, reason)
		return
	var hn := notes[hit]
	var dt := t - hn.time_ms
	var q: int = _tally._quality_for(absf(dt))
	_down_t[k] = -INF
	if hn.key == OrbitNote.KEY_ACCENT:
		_down_t[other] = -INF
	_aim_sum += hit_err
	_aim_n += 1
	if hn.is_hold:
		_judged[hit] = {"pending": true, "dt": dt, "aim_err": hit_err}
		_tally.combo += 1
		_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
		var ins := _hold_inside(hit, t)
		_holds[hit] = {
			"q": q, "dt": dt, "err": hit_err, "inside": ins,
			"out_since": INF if ins else t, "checked": t,
		}
		hold_started.emit(hit, q)
	else:
		_apply_hit(hit, q, dt, hit_err)
	key_pressed.emit(k, true)


func _do_up(k: int, t: float) -> void:
	_advance(t)
	_down_t[k] = -INF
	for idx in _holds.keys():
		var n := notes[idx]
		if n.key != k and n.key != OrbitNote.KEY_ACCENT:
			continue
		var ok := t >= n.end_ms - _tally.w50
		_finish_hold(idx, ok, "" if ok else "release")


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


## Orbit-Score 0..1.000.000 (x Mod-Faktor): 90 % Praezision, 10 % Streak.
func orbit_score() -> int:
	var n := float(maxi(notes.size(), 1))
	var raw := (1.0 - STREAK_SHARE) * _val_sum / n + STREAK_SHARE * _streak_sum / n
	return int(round(1000000.0 * raw * _tally.mod_mult))


## Zielfaktor: Abstand err (Feld) zum Treffer-Radius radius: bis AIM_FULL_FRAC 1,0,
## linear bis AIM_EDGE_FACTOR am Rand.
static func aim_factor(err: float, radius: float) -> float:
	var f := clampf((err / maxf(radius, 1e-9) - AIM_FULL_FRAC) / (1.0 - AIM_FULL_FRAC), 0.0, 1.0)
	return lerpf(1.0, AIM_EDGE_FACTOR, f)


## Wert eines Treffers: Zeitstufe x Zielfaktor.
static func hit_value(q: int, err: float,
		radius: float = DEFAULT_TARGET_RADIUS * AIM_RADIUS) -> float:
	return TIER_VALUE[clampi(q, 0, 5)] * aim_factor(err, radius)


## Mittlerer Zielfehler (Feld-Einheiten x 100) aller Treffer.
func mean_aim_err() -> float:
	return _aim_sum / float(maxi(_aim_n, 1)) * 100.0


func stats() -> Dictionary:
	var s: Dictionary = _tally.stats()
	s["score"] = orbit_score()
	s["accuracy"] = accuracy()
	s["grade"] = grade()
	s["aim_err"] = mean_aim_err()
	s["mode"] = "orbit"
	s["mods"] = mod_list(_tally.mods)
	return s


func _count_value(q: int, err: float) -> void:
	var v := hit_value(q, err, aim_radius) if q != Quality.MISS else 0.0
	_val_sum += v
	_streak_sum += v * minf(float(_tally.combo) / float(STREAK_FULL), 1.0)
	_n_done += 1


func is_judged(index: int) -> bool:
	return _judged.has(index)


## Indizes der laufenden Halten-Ziele.
func active_holds() -> Array:
	return _holds.keys()


func cursor_pos() -> Vector2:
	return _cursor


## Wie lange die Kugel des Halten-Ziels index schon ausserhalb des Folgeradius
## ist (ms, 0 = innen oder nicht aktiv).
func hold_out_ms(index: int, t_ms: float) -> float:
	if not _holds.has(index) or _holds[index].out_since == INF:
		return 0.0
	return maxf(t_ms - float(_holds[index].out_since), 0.0)


## Zeitfehler des Kopfs (ms, + = spaet) eines laufenden Halten-Ziels.
func hold_head_dt(index: int) -> float:
	var j: Dictionary = _judged.get(index, {})
	return float(j.get("dt", 0.0))


## Erstes offenes Ziel in Zeitordnung (-1 = keins).
func _first_open() -> int:
	while _head < _order.size() and _judged.has(_order[_head]):
		_head += 1
	return _order[_head] if _head < _order.size() else -1


## Halten durchrechnen von a bis b bei festem Cursor. Rueckgabe
## {drop: Zeit oder -1, ins, os}. Austritte exakt aus den Pfad-Segmenten
## (|Kugel - Cursor| = Folgeradius ist je Segment eine quadratische Gleichung).
func _scan(idx: int, ins: bool, os: float, a: float, b: float) -> Dictionary:
	var n := notes[idx]
	var vt: PackedFloat64Array = _hold_times[idx]
	var trans: Array = []
	var r2 := follow_radius * follow_radius
	for j in range(1, n.path.size()):
		var ta := vt[j - 1]
		var tb := vt[j]
		if ta >= b:
			break
		if tb <= a or tb <= ta:
			continue
		var p0 := n.path[j - 1]
		var v := (n.path[j] - p0) / float(tb - ta)
		var rel := p0 - _cursor
		var qa := v.dot(v)
		if qa < 1e-18:
			continue
		var qb := 2.0 * rel.dot(v)
		var disc := qb * qb - 4.0 * qa * (rel.dot(rel) - r2)
		if disc < 0.0:
			continue
		var sq := sqrt(disc)
		var t1 := ta + (-qb - sq) / (2.0 * qa)
		var t2 := ta + (-qb + sq) / (2.0 * qa)
		if t1 > a and t1 <= b and t1 >= ta and t1 <= tb:
			trans.append([t1, true])
		if t2 > a and t2 <= b and t2 >= ta and t2 <= tb:
			trans.append([t2, false])
	for tr in trans:
		if tr[1]:
			if not ins:
				if os + HOLD_OUT_MS < tr[0]:
					return {"drop": os + HOLD_OUT_MS, "ins": ins, "os": os}
				ins = true
				os = INF
		elif ins:
			ins = false
			os = tr[0]
	if os < INF and os + HOLD_OUT_MS < b:
		return {"drop": os + HOLD_OUT_MS, "ins": ins, "os": os}
	return {"drop": -1.0, "ins": ins, "os": os}


## Alle Ereignisse bis t in Zeitreihenfolge: Ablauf offener Ziele (t > time + w50),
## Halten-Ende (end_ms) und Halten-Austritt (> HOLD_OUT_MS).
func _advance(t: float) -> void:
	if t <= _time:
		return
	while not _tally.failed:
		var best := INF
		var kind := ""
		var which := -1
		for idx in _holds:
			var h: Dictionary = _holds[idx]
			var n := notes[idx]
			var res := _scan(idx, h.inside, h.out_since, h.checked, n.end_ms)
			var drop: float = res.drop
			if drop >= 0.0:
				if drop < t and drop < best:
					best = drop
					kind = "drop"
					which = idx
			elif n.end_ms <= t and n.end_ms < best:
				best = n.end_ms
				kind = "end"
				which = idx
		var f := _first_open()
		if f >= 0:
			var e := notes[f].time_ms + _tally.w50
			if e < t and e < best:
				best = e
				kind = "miss"
				which = f
		if which < 0:
			break
		if kind == "drop":
			_finish_hold(which, false, "out")
		elif kind == "end":
			_finish_hold(which, true, "")
		else:
			_miss(which, _tally.w50, _cursor.distance_to(notes[which].pos))
	for idx in _holds:
		var h: Dictionary = _holds[idx]
		var to := minf(t, notes[idx].end_ms)
		var res := _scan(idx, h.inside, h.out_since, h.checked, to)
		h.inside = res.ins
		h.out_since = res.os
		h.checked = maxf(h.checked, to)
	_time = t


func _finish_hold(idx: int, held_to_end: bool, reason: String) -> void:
	if not _holds.has(idx):
		return
	var h: Dictionary = _holds[idx]
	_holds.erase(idx)
	var n := notes[idx]
	if not held_to_end:
		_lose_hp_and_combo()
		_store(idx, {
			"quality": Quality.MISS, "dt": h.dt, "aim_err": h.err, "key": n.key,
			"hold_end": true, "held": false, "miss_kind": "DROP",
			"drop_reason": reason, "late": false,
		})
		return
	var q: int = h.q
	_tally._count_quality(q)
	_tally._add_score(q)
	_count_value(q, h.err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": h.dt, "aim_err": h.err, "key": n.key,
		"hold_end": true, "held": true, "miss_kind": "", "late": h.dt > 0.0,
	})


func _apply_hit(idx: int, q: int, dt: float, err: float) -> void:
	_tally._count_quality(q)
	_tally.combo += 1
	_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
	_tally._add_score(q)
	_count_value(q, err)
	_heal(q)
	_store(idx, {
		"quality": q, "dt": dt, "late": dt > 0.0, "aim_err": err,
		"key": notes[idx].key, "miss_kind": "",
	})


func _miss(idx: int, dt: float, err: float) -> void:
	_lose_hp_and_combo()
	_store(idx, {
		"quality": Quality.MISS, "dt": dt, "aim_err": err,
		"key": notes[idx].key, "miss_kind": "FULL", "late": false,
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
# Replay (deterministischer Modus)
# ---------------------------------------------------------------------------

## Ein Replay-Event einspeisen (Wiedergabe) bzw. eine gerundete Live-Eingabe
## ausfuehren und mitschreiben.
func apply_event(ev_in: Array) -> void:
	if ev_in.size() < 2 or notes.is_empty() or _tally.failed:
		return
	var ev := ev_in.duplicate()
	var code := int(ev[1])
	var te := maxf(float(ev[0]), _time)
	ev[0] = int(te)
	_advance(te)
	if _tally.failed:
		return
	if recording and code != EV_RULES:
		replay_log.append(ev)
	if code == EV_CURSOR and ev.size() >= 4:
		_cur_q = Vector2i(int(ev[2]), int(ev[3]))
		_rec_t = te
		_do_cursor(Vector2(float(_cur_q.x), float(_cur_q.y)) / 1000.0, te)
	elif code >= EV_DOWN and code < EV_DOWN + KEYS:
		_do_down(code - EV_DOWN, te)
	elif code >= EV_UP and code < EV_UP + KEYS:
		_do_up(code - EV_UP, te)


func _q_time(t_ms: float) -> float:
	return maxf(roundf(t_ms), _time)


static func _q_axis(v: float) -> int:
	return clampi(int(roundf(v * 1000.0)), -Q_LIMIT, Q_LIMIT)


static func count_events(events: Array) -> Dictionary:
	var c := 0
	var k := 0
	for e in events:
		if e is Array and e.size() >= 2 and int(e[1]) != EV_RULES:
			if int(e[1]) == EV_CURSOR:
				c += 1
			else:
				k += 1
	return {"cursor": c, "keys": k}


# ---------------------------------------------------------------------------
# Bot (Autoplay-Varianten, Tests)
# ---------------------------------------------------------------------------

## Plan fuer einen "menschlichen" Bot: je Ziel [Zeitversatz ms (+ = spaet),
## Zielfehler (Feld x 100), auslassen]. Deterministisch ueber seed; sigma 0 =
## perfekt; miss_every > 0 laesst jedes n-te Ziel aus.
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


## Ortsversatz (Feld) fuer den Zielfehler err (Feld x 100) des Ziels i: feste,
## gleichmaessig verteilte Richtung je Ziel (goldener Winkel).
static func bot_offset(i: int, err: float) -> Vector2:
	return Vector2.from_angle(float(i) * 2.399963) * (err / 100.0)
