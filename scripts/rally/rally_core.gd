class_name RallyCore
extends RefCounted

## Rally: Wertung. Deterministisch und bildratenunabhaengig: jede Eingabe ist ein
## Ereignis [t_ms, Code] (ganze ms); vor jedem Ereignis wird die Zeit bis dahin
## nachgezogen (verpasste Schlaege), erst dann zaehlt der Druck. update(t) zieht
## nur die Zeit nach, ein anderer Bildtakt aendert also nie das Ergebnis.
## Das Ereignis-Log (replay_log) enthaelt nur die Eingaben, die Wertung folgt
## daraus. Fenster, Qualitaeten, ScoreV1, Acc, Grade, HP kommen aus ManiaCore.
##
## Regeln: tiefer Ball = Taste A, hoher Ball = Taste B (falsche Taste: kein
## Treffer). Schmetterball: beide Tasten innerhalb SMASH_MS (nur eine: hoechstens 50).
## Aufladen: Taste halten, am Ende loslassen (zu frueh loslassen = Fehlschlag).

signal shot_judged(index: int, result: Dictionary)
signal charge_started(index: int, quality: int)
## Druck ohne Wirkung: reason "KEY" (falsche Taste), "FREE" (kein Schlag in Reichweite).
signal press_ignored(key: int, reason: String)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

const Quality := ManiaCore.Quality
const MODE := "rally"
const SMASH_MS := 40.0
const REPLAY_RULES := 1
## Ereignis-Codes: [t, EV_DOWN + Taste], [t, EV_UP + Taste], Regel-Marke [0, EV_RULES, REPLAY_RULES].
const EV_DOWN := 1
const EV_UP := 3
const EV_RULES := 9
const MOD_ORDER := ["NF", "SV"]

var shots: Array[RallyChart.Shot] = []
var w_max := 16.5
var w300 := 49.5
var w200 := 82.5
var w100 := 112.5
var w50 := 136.5
var w_miss := 173.5

var replay_log: Array = []
var recording := true
## Ereignis-Log der Wertung: [t, "hit"/"miss"/"charge"/"drop", Index, Qualitaet].
var event_log: Array = []

var _tally := ManiaCore.new()
var _judged: Dictionary = {}
var _judged_count := 0
var _next := 0
var _clock := -1
var _log_t := 0
var _down := [false, false]
var _active := -1
var _active_q := 0
var _head_err := 0.0
var _pend_idx := -1
var _pend_key := 0
var _pend_t := 0.0
var _finished_emitted := false

var combo: int:
	get: return _tally.combo
var max_combo: int:
	get: return _tally.max_combo
var hp: float:
	get: return _tally.hp
var failed: bool:
	get: return _tally.failed
var no_fail: bool:
	get: return _tally.no_fail
	set(v): _tally.no_fail = v
var mods: Dictionary:
	get: return _tally.mods
var score: int:
	get: return _tally.score
var judged_count: int:
	get: return _judged_count
var charging: int:
	get: return _active


## p_shots: Ergebnis von RallyChart.build. od/hp_drain der Map, p_mods null = GameSession.
func setup(p_shots: Array[RallyChart.Shot], od: float, hp_drain: float = 5.0, p_mods = null) -> void:
	shots = p_shots
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
	_tally._total_notes = shots.size()
	w_max = _tally.w_max
	w300 = _tally.w300
	w200 = _tally.w200
	w100 = _tally.w100
	w50 = _tally.w50
	w_miss = _tally.w_miss
	_judged = {}
	_judged_count = 0
	_next = 0
	_clock = -1
	_down = [false, false]
	_active = -1
	_pend_idx = -1
	_finished_emitted = false
	event_log = []
	replay_log = [[0, EV_RULES, REPLAY_RULES]] if recording else []


func set_replay_mode(record: bool) -> void:
	recording = record
	replay_log = [[0, EV_RULES, REPLAY_RULES]] if record else []


# ---------------------------------------------------------------------------
# Eingabe (Live) und Ereignisse (Replay/Bot)
# ---------------------------------------------------------------------------

func key_down(key: int, t_ms: float) -> void:
	_event([maxi(int(t_ms), maxi(_clock, 0)), EV_DOWN + key])


func key_up(key: int, t_ms: float) -> void:
	_event([maxi(int(t_ms), maxi(_clock, 0)), EV_UP + key])


## Bot/Replay-Ereignis mitschreiben und werten (Zeit unveraendert).
func feed(ev: Array) -> void:
	_event([int(ev[0]), int(ev[1])])


func _event(ev: Array) -> void:
	if recording:
		replay_log.append(ev)
	apply_event(ev)


## Ein Ereignis einspeisen (Live ueber key_down/up, Replay/Bot direkt).
func apply_event(ev: Array) -> void:
	var code := int(ev[1])
	if code == EV_RULES:
		return
	var t := int(ev[0])
	_advance(t)
	if _tally.failed:
		return
	if code >= EV_UP:
		_on_up(clampi(code - EV_UP, 0, 1), float(t))
	else:
		_on_down(clampi(code - EV_DOWN, 0, 1), float(t))


func update(t_ms: float) -> void:
	_advance(int(floorf(t_ms)))
	if _judged_count >= shots.size() and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


# ---------------------------------------------------------------------------
# Zeit nachziehen
# ---------------------------------------------------------------------------

func _advance(t: int) -> void:
	if t <= _clock:
		return
	var tf := float(t)
	# Faelliges in exakter Zeitreihenfolge abarbeiten (unabhaengig von der Bildrate):
	# ausstehender Schmetterball, Aufladen ohne Loslassen, verpasster Schlag.
	while true:
		_skip_judged()
		var due := INF
		var kind := 0
		if _pend_idx >= 0:
			due = _pend_t + SMASH_MS
			kind = 1
		if _active >= 0:
			var d := shots[_active].end + w100
			if d < due:
				due = d
				kind = 2
		if _next < shots.size() and _next != _pend_idx:
			var d2 := shots[_next].t + w50
			if d2 < due:
				due = d2
				kind = 3
		if kind == 0 or tf <= due:
			break
		_log_t = int(due)
		match kind:
			1:
				_resolve_smash_single()
			2:
				_finish_charge(_active_q_for(w100))
			_:
				_miss(_next)
				_next += 1
	_clock = t
	_log_t = t


func _active_q_for(tail_err: float) -> int:
	return _tally.hold_quality(_head_err, tail_err)


func _skip_judged() -> void:
	while _next < shots.size() and (_judged.has(_next) or _next == _active):
		_next += 1


# ---------------------------------------------------------------------------
# Tasten
# ---------------------------------------------------------------------------

func _on_down(key: int, t: float) -> void:
	_down[key] = true
	if _active >= 0:
		press_ignored.emit(key, "FREE")
		return
	_skip_judged()
	# Ausstehender Schmetterball: zweite Taste innerhalb des Fensters.
	if _pend_idx >= 0:
		if key != _pend_key and t - _pend_t <= SMASH_MS:
			var avg := (_pend_t + t) * 0.5 - shots[_pend_idx].t
			var idx := _pend_idx
			_pend_idx = -1
			_apply_hit(idx, _quality_for(absf(avg)), avg)
		else:
			press_ignored.emit(key, "FREE")
		return
	if _next >= shots.size():
		press_ignored.emit(key, "FREE")
		return
	var idx := _next
	var s := shots[idx]
	var dt := t - s.t
	if dt < -w_miss:
		press_ignored.emit(key, "FREE")
		return
	if not s.smash and key != s.key:
		press_ignored.emit(key, "KEY")
		return
	if dt < -w50:
		# Zu frueh: frisst den Schlag (wie Mania).
		_miss(idx)
		_next += 1
		return
	if s.smash:
		_pend_idx = idx
		_pend_key = key
		_pend_t = t
		return
	var q := _quality_for(absf(dt))
	if s.is_charge():
		_active = idx
		_active_q = q
		_head_err = absf(dt)
		_tally.combo += 1
		_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
		_judged[idx] = {"pending": true, "dt": dt}
		event_log.append([int(t), "charge", idx, q])
		charge_started.emit(idx, q)
		return
	_apply_hit(idx, q, dt)


func _on_up(key: int, t: float) -> void:
	_down[key] = false
	if _active < 0 or key != shots[_active].key:
		return
	var end := shots[_active].end
	if t < end - w50:
		_finish_charge(Quality.MISS)
	else:
		_finish_charge(_active_q_for(absf(t - end)))


func _resolve_smash_single() -> void:
	var idx := _pend_idx
	_pend_idx = -1
	var dt := _pend_t - shots[idx].t
	_apply_hit(idx, maxi(_quality_for(absf(dt)), Quality.MEH), dt)


func _quality_for(abs_dt: float) -> int:
	return _tally._quality_for(abs_dt)


# ---------------------------------------------------------------------------
# Wertung
# ---------------------------------------------------------------------------

func _apply_hit(idx: int, q: int, dt: float) -> void:
	_tally._count_quality(q)
	_tally.combo += 1
	_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
	_tally._add_score(q)
	_heal(q)
	event_log.append([_log_t, "hit", idx, q])
	_store(idx, {"quality": q, "dt": dt, "late": dt > 0.0, "key": shots[idx].key,
			"smash": shots[idx].smash, "miss_kind": ""})


func _miss(idx: int) -> void:
	_lose()
	event_log.append([_log_t, "miss", idx, Quality.MISS])
	_store(idx, {"quality": Quality.MISS, "key": shots[idx].key, "smash": shots[idx].smash,
			"miss_kind": "FULL", "late": false})


func _finish_charge(q: int) -> void:
	var idx := _active
	_active = -1
	if idx < 0:
		return
	var head: Dictionary = _judged.get(idx, {})
	var dt := float(head.get("dt", 0.0))
	if q == Quality.MISS:
		_lose()
		event_log.append([_log_t, "drop", idx, Quality.MISS])
		_store(idx, {"quality": Quality.MISS, "dt": dt, "key": shots[idx].key, "smash": false,
				"hold_end": true, "held": false, "miss_kind": "DROP", "late": false})
		return
	_tally._count_quality(q)
	_tally._add_score(q)
	_heal(q)
	event_log.append([_log_t, "hit", idx, q])
	_store(idx, {"quality": q, "dt": dt, "key": shots[idx].key, "smash": false,
			"hold_end": true, "held": true, "miss_kind": "", "late": dt > 0.0})


func _lose() -> void:
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
	shot_judged.emit(idx, result)


func is_judged(idx: int) -> bool:
	return _judged.has(idx) and not bool((_judged[idx] as Dictionary).get("pending", false))


func result_of(idx: int) -> Dictionary:
	return _judged.get(idx, {})


## Schlag idx haelt gerade (Aufladen laeuft).
func is_charging(idx: int) -> bool:
	return idx == _active


func smash_pending() -> bool:
	return _pend_idx >= 0


func accuracy() -> float:
	return _tally.accuracy()


func grade() -> String:
	return _tally.grade()


## Wie ManiaCore.stats() (gleiche Felder fuer Results/Scores/Lobby), "mode": "rally".
func stats() -> Dictionary:
	var s: Dictionary = _tally.stats()
	s["mode"] = MODE
	s["mods"] = mod_list(_tally.mods)
	s["n_shots"] = shots.size()
	return s


static func mod_list(p_mods: Dictionary) -> Array:
	var out := []
	for k in MOD_ORDER:
		if bool(p_mods.get(k, false)):
			out.append(k)
	return out


# ---------------------------------------------------------------------------
# Autoplay-Bot
# ---------------------------------------------------------------------------

## Eingaben eines Bots als Ereignis-Liste (nach Zeit sortiert). jitter_ms > 0:
## gleichverteilter Zeitfehler (deterministisch aus seed), skip_every > 0 laesst
## jeden n-ten Schlag aus.
static func bot_plan(p_shots: Array[RallyChart.Shot], seed: int = 1, jitter_ms: float = 0.0,
		skip_every: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	for i in p_shots.size():
		if skip_every > 0 and (i + 1) % skip_every == 0:
			continue
		var s := p_shots[i]
		var dt := rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0
		var dt2 := rng.randf_range(-jitter_ms, jitter_ms) * 0.3 if jitter_ms > 0.0 else 0.0
		var t := int(round(s.t + dt))
		var up := int(round(s.end + (rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0)))
		if s.smash:
			out.append([t, EV_DOWN + 0, i])
			out.append([t + int(round(dt2)) + 2, EV_DOWN + 1, i])
			out.append([t + 40, EV_UP + 0, i])
			out.append([t + 42, EV_UP + 1, i])
		else:
			out.append([t, EV_DOWN + s.key, i])
			out.append([maxi(up, t + 30) if s.is_charge() else t + 40, EV_UP + s.key, i])
	out.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[2] < b[2] or (a[2] == b[2] and a[1] < b[1]))
	return out


# ---------------------------------------------------------------------------
# Replays (eigene Dateien: ReplayStore kennt nur Mania/Orbit)
# ---------------------------------------------------------------------------

const REPLAY_DIR := "user://replays/rally"


static func replay_path(osz_path: String, version: String) -> String:
	return "%s/%s.json" % [REPLAY_DIR, ReplayStore.key(osz_path, version)]


static func save_replay(osz_path: String, version: String, events: Array, meta: Dictionary) -> void:
	if events.size() <= 1:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_DIR))
	var f := FileAccess.open(replay_path(osz_path, version), FileAccess.WRITE)
	if f == null:
		return
	var m := meta.duplicate()
	m["mode"] = MODE
	m["rules"] = REPLAY_RULES
	f.store_string(JSON.stringify({"meta": m, "events": events}))
	f.close()


static func load_replay(osz_path: String, version: String) -> Dictionary:
	var p := replay_path(osz_path, version)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("events"):
		return parsed
	return {}


## Replay mit gueltiger Regel-Marke dieser Version?
static func replay_ok(events: Array) -> bool:
	for e in events:
		if e is Array and e.size() >= 3 and int(e[1]) == EV_RULES:
			return int(e[2]) == REPLAY_RULES
	return false
