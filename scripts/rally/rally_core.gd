class_name RallyCore
extends RefCounted

## Rally: Wertung. Deterministisch und bildratenunabhaengig: jede Eingabe ist ein
## Ereignis [t_ms, Code] (ganze ms); vor jedem Ereignis wird die Zeit bis dahin
## nachgezogen (verpasste Schlaege), erst dann zaehlt der Druck. update(t) zieht
## nur die Zeit nach, ein anderer Bildtakt aendert also nie das Ergebnis.
## Das Ereignis-Log (replay_log) enthaelt nur die Eingaben, die Wertung folgt
## daraus. Fenster, Qualitaeten, ScoreV1, Acc, Grade, HP kommen aus ManiaCore.
##
## Regeln v3 (docs/modes/rally.md): 4 Zonen = 4 Tasten (Index 0..3). Jede Zone hat
## ihre eigene Ballfolge (kein Notelock zwischen Zonen); Druck in der falschen Zone
## trifft nichts. Schmetterball: beide Zonentasten innerhalb SMASH_MS (nur eine:
## hoechstens 50). Aufladen: Zonentaste halten, am Ende loslassen (wie Mania-Hold).

signal shot_judged(index: int, result: Dictionary)
signal charge_started(index: int, quality: int)
## Druck ohne Wirkung: reason "KEY" (falsche Zone, in einer anderen liegt ein Ball), "FREE" (kein Ball).
## Dazu "WRONG": falsche Zone bei einem Ball im 50er-Fenster, der Ball ist sofort Miss (Anti-Mash).
signal press_ignored(key: int, reason: String)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

const Quality := ManiaCore.Quality
const MODE := "rally"
const ZONES := 4
const SMASH_MS := 40.0
const REPLAY_RULES := 3
## Ereignis-Codes: [t, EV_DOWN + Zone], [t, EV_UP + Zone], Regel-Marke [0, EV_RULES, REPLAY_RULES].
const EV_DOWN := 1
const EV_UP := 5
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
## Anti-Mash (Regeln v3). Nur Messungen/Tests schalten es aus (Vorher-Werte); Spiel und Replay: immer an.
var anti_mash := true
## Zonenzahl dieses Laufs (3 oder 4), kommt aus RallyChart.zone_count(); steht in der Regel-Marke.
var zones := 4
var recording := true
## Ereignis-Log der Wertung: [t, "hit"/"miss"/"charge"/"drop", Index, Qualitaet].
var event_log: Array = []

var _tally := ManiaCore.new()
var _judged: Dictionary = {}
var _judged_count := 0
## Ballfolge je Zone (Schlag-Indizes) und Kopfzeiger.
var _zq: Array = []
var _zh: Array[int] = []
var _clock := -1
var _log_t := 0
var _down: Array[bool] = []
## Aufladen je Zone: Schlag-Index oder -1, Kopf-Qualitaet, Kopf-Fehler.
var _act: Array[int] = []
var _act_q: Array[int] = []
var _head_err: Array[float] = []
## Schmetterbaelle mit erster Taste, warten auf die zweite: Index -> [Zone, t].
var _pend: Dictionary = {}
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
## Index des (ersten) gerade aufladenden Schlags, -1 wenn keiner.
var charging: int:
	get:
		for z in _act.size():
			if _act[z] >= 0:
				return _act[z]
		return -1


## p_shots: Ergebnis von RallyChart.build. od/hp_drain der Map, p_mods null = GameSession.
func setup(p_shots: Array[RallyChart.Shot], od: float, hp_drain: float = 5.0, p_mods = null) -> void:
	shots = p_shots
	zones = RallyChart.zone_count()
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
	_zq = []
	_zh = []
	_down = []
	_act = []
	_act_q = []
	_head_err = []
	for z in ZONES:
		_zq.append([])
		_zh.append(0)
		_down.append(false)
		_act.append(-1)
		_act_q.append(0)
		_head_err.append(0.0)
	for i in shots.size():
		for z in shots[i].zones:
			(_zq[clampi(int(z), 0, ZONES - 1)] as Array).append(i)
	_clock = -1
	_pend = {}
	_finished_emitted = false
	event_log = []
	replay_log = [[0, EV_RULES, REPLAY_RULES, zones]] if recording else []


func set_replay_mode(record: bool) -> void:
	recording = record
	replay_log = [[0, EV_RULES, REPLAY_RULES, zones]] if record else []


# ---------------------------------------------------------------------------
# Eingabe (Live) und Ereignisse (Replay/Bot)
# ---------------------------------------------------------------------------

func key_down(zone: int, t_ms: float) -> void:
	_event([maxi(int(t_ms), maxi(_clock, 0)), EV_DOWN + zone])


func key_up(zone: int, t_ms: float) -> void:
	_event([maxi(int(t_ms), maxi(_clock, 0)), EV_UP + zone])


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
	if code < EV_DOWN or code >= EV_RULES:
		return
	var t := int(ev[0])
	_advance(t)
	if _tally.failed:
		return
	if code >= EV_UP:
		_on_up(code - EV_UP, float(t))
	else:
		_on_down(code - EV_DOWN, float(t))


func update(t_ms: float) -> void:
	_advance(int(floorf(t_ms)))
	if _judged_count >= shots.size() and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


# ---------------------------------------------------------------------------
# Zeit nachziehen
# ---------------------------------------------------------------------------

## Erster ungewerteter Ball der Zone z (-1 wenn keiner).
func _head(z: int) -> int:
	var q: Array = _zq[z]
	while _zh[z] < q.size() and _judged.has(int(q[_zh[z]])):
		_zh[z] += 1
	return int(q[_zh[z]]) if _zh[z] < q.size() else -1


func _advance(t: int) -> void:
	if t <= _clock:
		return
	var tf := float(t)
	# Faelliges in exakter Zeitreihenfolge abarbeiten (unabhaengig von der Bildrate):
	# ausstehender Schmetterball, Aufladen ohne Loslassen, verpasster Ball. Bei
	# gleicher Zeit: zuerst Schmetterball, dann Aufladen, dann Baelle, Zone aufsteigend.
	while true:
		var due := INF
		var kind := 0
		var arg := -1
		var pk := _pend.keys()
		pk.sort()
		for idx in pk:
			var d0: float = float((_pend[idx] as Array)[1]) + SMASH_MS
			if d0 < due:
				due = d0
				kind = 1
				arg = int(idx)
		for z in ZONES:
			if _act[z] >= 0:
				var d1 := shots[_act[z]].end + w100
				if d1 < due:
					due = d1
					kind = 2
					arg = z
		for z in ZONES:
			var h := _head(z)
			if h >= 0 and not _pend.has(h):
				var d2 := shots[h].t + w50
				if d2 < due:
					due = d2
					kind = 3
					arg = h
		if kind == 0 or tf <= due:
			break
		_log_t = int(due)
		match kind:
			1:
				_resolve_smash_single(arg)
			2:
				_finish_charge(arg, _tally.hold_quality(_head_err[arg], w100))
			_:
				_miss(arg)
	_clock = t
	_log_t = t


# ---------------------------------------------------------------------------
# Tasten
# ---------------------------------------------------------------------------

func _ignore(z: int, t: float) -> void:
	# Anti-Mash (v3): Druck ohne Ball in dieser Zone, waehrend eine andere Zone einen
	# ungewerteten Ball im 50er-Fenster hat: dieser Ball (der naechste) ist sofort Miss.
	# Auch ein Schmetterball mit erster Taste faellt so, wenn eine dritte Zone dazukommt.
	var victim := -1
	var best := INF
	for o in (ZONES if anti_mash else 0):
		if o == z:
			continue
		var h0 := _head(o)
		if h0 >= 0 and absf(t - shots[h0].t) <= w50 and absf(t - shots[h0].t) < best:
			best = absf(t - shots[h0].t)
			victim = h0
	if victim >= 0:
		_pend.erase(victim)
		_miss(victim)
		press_ignored.emit(z, "KEY")
		press_ignored.emit(z, "WRONG")
		return
	# Liegt in einer anderen Zone ein Ball in Reichweite, war es die falsche Zone.
	for o in ZONES:
		if o == z:
			continue
		var h := _head(o)
		if h >= 0 and absf(t - shots[h].t) <= w_miss:
			press_ignored.emit(z, "KEY")
			return
	press_ignored.emit(z, "FREE")


func _on_down(z: int, t: float) -> void:
	if z < 0 or z >= ZONES:
		return
	_down[z] = true
	if _act[z] >= 0:
		press_ignored.emit(z, "FREE")
		return
	var idx := _head(z)
	if idx < 0:
		_ignore(z, t)
		return
	var s := shots[idx]
	# Schmetterball mit erster Taste: zweite Zonentaste innerhalb des Fensters.
	if _pend.has(idx):
		var p: Array = _pend[idx]
		if int(p[0]) != z and t - float(p[1]) <= SMASH_MS:
			var avg := (float(p[1]) + t) * 0.5 - s.t
			_pend.erase(idx)
			_apply_hit(idx, _quality_for(absf(avg)), avg)
		else:
			press_ignored.emit(z, "FREE")
		return
	var dt := t - s.t
	if dt < -w_miss:
		_ignore(z, t)
		return
	if dt < -w50:
		# Zu frueh: frisst den Ball (wie Mania).
		_miss(idx)
		return
	if s.smash:
		_pend[idx] = [z, t]
		return
	var q := _quality_for(absf(dt))
	if s.is_charge():
		_act[z] = idx
		_act_q[z] = q
		_head_err[z] = absf(dt)
		_tally.combo += 1
		_tally.max_combo = maxi(_tally.max_combo, _tally.combo)
		_judged[idx] = {"pending": true, "dt": dt}
		event_log.append([int(t), "charge", idx, q])
		charge_started.emit(idx, q)
		return
	_apply_hit(idx, q, dt)


func _on_up(z: int, t: float) -> void:
	if z < 0 or z >= ZONES:
		return
	_down[z] = false
	if _act[z] < 0:
		return
	var end := shots[_act[z]].end
	if t < end - w50:
		_finish_charge(z, Quality.MISS)
	else:
		_finish_charge(z, _tally.hold_quality(_head_err[z], absf(t - end)))


func _resolve_smash_single(idx: int) -> void:
	var p: Array = _pend[idx]
	_pend.erase(idx)
	var dt := float(p[1]) - shots[idx].t
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
	_store(idx, {"quality": q, "dt": dt, "late": dt > 0.0, "key": shots[idx].zones[0],
			"zones": shots[idx].zones, "smash": shots[idx].smash, "miss_kind": ""})


func _miss(idx: int) -> void:
	_lose()
	event_log.append([_log_t, "miss", idx, Quality.MISS])
	_store(idx, {"quality": Quality.MISS, "key": shots[idx].zones[0], "zones": shots[idx].zones,
			"smash": shots[idx].smash, "miss_kind": "FULL", "late": false})


func _finish_charge(z: int, q: int) -> void:
	var idx := _act[z]
	_act[z] = -1
	if idx < 0:
		return
	var head: Dictionary = _judged.get(idx, {})
	var dt := float(head.get("dt", 0.0))
	if q == Quality.MISS:
		_lose()
		event_log.append([_log_t, "drop", idx, Quality.MISS])
		_store(idx, {"quality": Quality.MISS, "dt": dt, "key": z, "zones": shots[idx].zones,
				"smash": false, "hold_end": true, "held": false, "miss_kind": "DROP", "late": false})
		return
	_tally._count_quality(q)
	_tally._add_score(q)
	_heal(q)
	event_log.append([_log_t, "hit", idx, q])
	_store(idx, {"quality": q, "dt": dt, "key": z, "zones": shots[idx].zones,
			"smash": false, "hold_end": true, "held": true, "miss_kind": "", "late": dt > 0.0})


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
	return _act.has(idx)


func smash_pending() -> bool:
	return not _pend.is_empty()


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
			out.append([t, EV_DOWN + s.zones[0], i])
			out.append([t + int(round(dt2)) + 2, EV_DOWN + s.zones[1], i])
			out.append([t + 40, EV_UP + s.zones[0], i])
			out.append([t + 42, EV_UP + s.zones[1], i])
		else:
			var z: int = s.zones[0]
			out.append([t, EV_DOWN + z, i])
			out.append([maxi(up, t + 30) if s.is_charge() else t + 40, EV_UP + z, i])
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


## Zonenzahl eines Replays (Regel-Marke [0, 9, 2, zonen]; fehlt sie: 4).
static func replay_zones(events: Array) -> int:
	for e in events:
		if e is Array and e.size() >= 3 and int(e[1]) == EV_RULES:
			return 3 if e.size() > 3 and int(e[3]) == 3 else 4
	return 4


## Replay mit gueltiger Regel-Marke dieser Version?
static func replay_ok(events: Array) -> bool:
	for e in events:
		if e is Array and e.size() >= 3 and int(e[1]) == EV_RULES:
			return int(e[2]) == REPLAY_RULES
	return false
