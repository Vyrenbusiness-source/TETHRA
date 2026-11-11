class_name DirigentCore
extends RefCounted

## Dirigent: Wertung. Zwei Anteile:
##  - Takt (40 %): auf jedem Schlag muss die Hand (Cursor) im Radius HIT_R des
##    Schlagpunkts sein. Wert 1,0 im inneren Halbradius, linear bis EDGE_FACTOR
##    am Rand, danach "verfehlt" (0).
##  - Einsaetze (60 %): Tasten A/B nach Mania-Zeitfenstern (OD), Wert je Stufe.
## Score 1.000.000 x Mod-Faktor, Acc = gewichtetes Mittel, Grades wie Orbit.
##
## Deterministisch: der Core kennt nur Ereignisse (Cursor, Taste A/B) mit Zeit.
## Bevor ein Ereignis wirkt, wird die Zeit bis dorthin abgearbeitet (Schlaege
## werten mit dem Cursor VOR dem Ereignis, Einsaetze laufen ab). Cursor wird auf
## 1/1000 und die Zeit auf 0,25 ms gerastert, Cursor-Ereignisse sind auf
## CURSOR_MIN_MS gedrosselt: Live-Lauf und Replay sehen dieselbe Folge.
## replay_log: [t, code, a, b] mit EV_*.

signal beat_judged(index: int, result: Dictionary)
signal cue_judged(index: int, result: Dictionary)
signal key_pressed(key: int, hit: bool)
signal finished(stats: Dictionary)

const Quality := ManiaCore.Quality

## Trefferradius (Figur-Einheiten), innerer Vollwert-Radius, Randfaktor.
const HIT_R := 0.21
const INNER_R := 0.105
const EDGE_FACTOR := 0.88
const BEAT_SHARE := 0.4
const CUE_SHARE := 0.6
const CURSOR_MIN_MS := 4.0
const CURSOR_MIN_STEP := 0.002

const GRADE_SS := 0.985
const GRADE_STEPS := [[0.95, "S"], [0.90, "A"], [0.82, "B"], [0.72, "C"]]
## Einsatz-Wert je Stufe (MAX, 300, 200, 100, 50, MISS) = ManiaCore.HIT_VALUE / 320.
const CUE_VALUE: Array[float] = [1.0, 0.9375, 0.625, 0.3125, 0.15625, 0.0]

const EV_CURSOR := 0
const EV_KEY_A := 1
const EV_KEY_B := 2
const EV_RULES := 9
const REPLAY_RULES := 1

var chart: DirigentChart
var recording := false
var replay_log: Array = []
var combo := 0
var max_combo := 0
var n_max := 0
var n300 := 0
var n200 := 0
var n100 := 0
var n50 := 0
var n_miss := 0
var beats_hit := 0
var mod_mult := 1.0
var w_max := 16.0
var w300 := 40.0
var w200 := 73.0
var w100 := 103.0
var w50 := 127.0

var _beat_i := 0
var _cue_head := 0
var _cue_got: Array[int] = []
var _cue_dt: Array[float] = []
var _cue_done: Array[bool] = []
var _cue_judged := 0
var _beat_val := 0.0
var _beat_done := 0
var _cue_val := 0.0
var _aim_sum := 0.0
var _cursor := Vector2.ZERO
var _last_t := -INF
var _last_applied_t := -INF
var _pending := false
var _pending_pos := Vector2.ZERO
var _pending_t := 0.0
var _finished_emitted := false
## Beats, die verfehlt wurden bzw. ihr Ergebnis: [Zeit, Abstand, Wert] je Schlag.
var beat_log: Array = []


## od: OverallDifficulty der Map (Fenster wie Mania).
func setup(p_chart: DirigentChart, od: float) -> void:
	chart = p_chart
	w_max = DifficultyCalc.mania_window_max(od)
	w300 = DifficultyCalc.mania_window_300(od)
	w200 = DifficultyCalc.mania_window_200(od)
	w100 = DifficultyCalc.mania_window_100(od)
	w50 = DifficultyCalc.mania_window_50(od)
	combo = 0
	max_combo = 0
	n_max = 0
	n300 = 0
	n200 = 0
	n100 = 0
	n50 = 0
	n_miss = 0
	beats_hit = 0
	_beat_i = 0
	_cue_head = 0
	_cue_got.clear()
	_cue_dt.clear()
	_cue_done.clear()
	for i in chart.cues.size():
		_cue_got.append(0)
		_cue_dt.append(0.0)
		_cue_done.append(false)
	_cue_judged = 0
	_beat_val = 0.0
	_beat_done = 0
	_cue_val = 0.0
	_aim_sum = 0.0
	_cursor = Vector2.ZERO
	_last_t = -INF
	_last_applied_t = -INF
	_pending = false
	_finished_emitted = false
	beat_log = []
	replay_log = []
	if recording:
		replay_log.append([0.0, EV_RULES, REPLAY_RULES])


func set_replay_mode(record: bool) -> void:
	recording = record
	replay_log = []
	if record:
		replay_log.append([0.0, EV_RULES, REPLAY_RULES])


static func snap_t(t: float) -> float:
	return snappedf(t, 0.25)


static func snap_p(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001))


func cursor_pos() -> Vector2:
	return _cursor


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

## Cursor in Figur-Einheiten. Gedrosselt, siehe CURSOR_MIN_MS.
func cursor_moved(pos: Vector2, t_ms: float) -> void:
	var t := maxf(snap_t(t_ms), _last_t)
	var p := snap_p(pos)
	if p.distance_to(_cursor) < CURSOR_MIN_STEP and not _pending:
		return
	if t - _last_applied_t >= CURSOR_MIN_MS:
		_pending = false
		_apply_cursor(p, t)
	else:
		_pending = true
		_pending_pos = p
		_pending_t = t


func key_down(key: int, t_ms: float) -> void:
	var t := maxf(snap_t(t_ms), _last_t)
	_flush_pending(t)
	_apply_key(clampi(key, 0, 1), t)


## Zeit weiterlaufen lassen (jeden Frame).
func update(t_ms: float) -> void:
	var t := maxf(snap_t(t_ms), _last_t)
	_flush_pending(t)
	_advance(t)
	_check_finished()


func _flush_pending(t: float) -> void:
	if _pending and t - _last_applied_t >= CURSOR_MIN_MS:
		_pending = false
		_apply_cursor(_pending_pos, maxf(_pending_t, _last_t))


## Aufgezeichnetes Ereignis einspielen (Replay).
func apply_event(ev: Array) -> void:
	if ev.size() < 2:
		return
	var t := maxf(snap_t(float(ev[0])), _last_t)
	match int(ev[1]):
		EV_CURSOR:
			if ev.size() >= 4:
				_apply_cursor(Vector2(float(ev[2]), float(ev[3])) / 1000.0, t)
		EV_KEY_A:
			_apply_key(0, t)
		EV_KEY_B:
			_apply_key(1, t)


func _apply_cursor(p: Vector2, t: float) -> void:
	_advance(t)
	_cursor = p
	_last_applied_t = t
	if recording:
		replay_log.append([t, EV_CURSOR, int(round(p.x * 1000.0)), int(round(p.y * 1000.0))])


func _apply_key(key: int, t: float) -> void:
	_advance(t)
	if recording:
		replay_log.append([t, EV_KEY_A + key, 0])
	# Frueheste offene Einsatz-Marke mit dieser Taste, die im Fenster liegt.
	var cues := chart.cues
	var i := _cue_head
	while i < cues.size():
		var c: Dictionary = cues[i]
		var ct := float(c.t)
		if ct - t > w50:
			break
		if not _cue_done[i] and DirigentChart.mask_has(int(c.mask), key) \
				and (_cue_got[i] >> key) & 1 == 0 and t - ct <= w50:
			_cue_got[i] |= 1 << key
			var dt := t - ct
			if absf(dt) > absf(_cue_dt[i]):
				_cue_dt[i] = dt
			key_pressed.emit(key, true)
			if _cue_got[i] == int(c.mask):
				_finish_cue(i, _quality_for(absf(_cue_dt[i])), _cue_dt[i])
			return
		i += 1
	key_pressed.emit(key, false)


# ---------------------------------------------------------------------------
# Zeit
# ---------------------------------------------------------------------------

func _advance(t: float) -> void:
	if t <= _last_t:
		return
	_last_t = t
	# Schlaege: Cursor von vor dem Ereignis.
	while _beat_i < chart.beats.size() and float(chart.beats[_beat_i].t) < t:
		_judge_beat(_beat_i)
		_beat_i += 1
	# Einsaetze: abgelaufen = verfehlt.
	while _cue_head < chart.cues.size():
		if _cue_done[_cue_head]:
			_cue_head += 1
			continue
		if t - float(chart.cues[_cue_head].t) > w50:
			_finish_cue(_cue_head, Quality.MISS, 0.0)
			_cue_head += 1
			continue
		break


func _judge_beat(i: int) -> void:
	var b: Dictionary = chart.beats[i]
	var d := _cursor.distance_to(b.pos)
	var v := 0.0
	var hit := d <= HIT_R
	if hit:
		v = beat_value(d)
		beats_hit += 1
		combo += 1
		max_combo = maxi(max_combo, combo)
		_aim_sum += d / HIT_R
	else:
		combo = 0
	_beat_val += v
	_beat_done += 1
	beat_log.append([float(b.t), d, v])
	beat_judged.emit(i, {"hit": hit, "dist": d, "value": v, "pos": _cursor})


## Wert eines Schlags nach Abstand zum Punkt (Einheiten).
static func beat_value(d: float) -> float:
	if d > HIT_R:
		return 0.0
	var k := clampf((d - INNER_R) / (HIT_R - INNER_R), 0.0, 1.0)
	return lerpf(1.0, EDGE_FACTOR, k)


func _quality_for(abs_dt: float) -> int:
	if abs_dt <= w_max:
		return Quality.MAX
	elif abs_dt <= w300:
		return Quality.PERFECT
	elif abs_dt <= w200:
		return Quality.GOOD
	elif abs_dt <= w100:
		return Quality.OK
	return Quality.MEH


func _finish_cue(i: int, q: int, dt: float) -> void:
	_cue_done[i] = true
	_cue_judged += 1
	match q:
		Quality.MAX: n_max += 1
		Quality.PERFECT: n300 += 1
		Quality.GOOD: n200 += 1
		Quality.OK: n100 += 1
		Quality.MEH: n50 += 1
		_: n_miss += 1
	if q == Quality.MISS:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
	_cue_val += CUE_VALUE[q]
	cue_judged.emit(i, {"quality": q, "dt": dt, "mask": chart.cues[i].mask})


func _check_finished() -> void:
	if _finished_emitted:
		return
	if _beat_i >= chart.beats.size() and _cue_judged >= chart.cues.size():
		_finished_emitted = true
		finished.emit(stats())


func is_finished() -> bool:
	return _finished_emitted


func is_cue_done(i: int) -> bool:
	return i >= 0 and i < _cue_done.size() and _cue_done[i]


# ---------------------------------------------------------------------------
# Wertung
# ---------------------------------------------------------------------------

func beat_acc() -> float:
	return _beat_val / float(_beat_done) if _beat_done > 0 else 1.0


## Mania-Formel ueber die Einsaetze.
func cue_acc() -> float:
	var total := n_max + n300 + n200 + n100 + n50 + n_miss
	if total == 0:
		return 1.0
	return float(300 * (n_max + n300) + 200 * n200 + 100 * n100 + 50 * n50) / float(300 * total)


func accuracy() -> float:
	var wb := BEAT_SHARE if _beat_done > 0 else 0.0
	var wc := CUE_SHARE if _cue_judged > 0 else 0.0
	if wb + wc <= 0.0:
		return 1.0
	return (wb * beat_acc() + wc * cue_acc()) / (wb + wc)


func grade() -> String:
	var acc := accuracy()
	if acc >= GRADE_SS and n_miss == 0 and beats_hit == _beat_done:
		return "SS"
	for g in GRADE_STEPS:
		if acc >= float(g[0]):
			return str(g[1])
	return "D"


## Score 0..1.000.000 x Mod-Faktor.
func dirigent_score() -> int:
	var nb := float(chart.beats.size())
	var nc := float(chart.cues.size())
	var sb := _beat_val / nb if nb > 0.0 else 0.0
	var sc := _cue_val / nc if nc > 0.0 else 0.0
	var wb := BEAT_SHARE if nb > 0.0 else 0.0
	var wc := CUE_SHARE if nc > 0.0 else 0.0
	if wb + wc <= 0.0:
		return 0
	var raw := (wb * sb + wc * sc) / (wb + wc)
	return int(round(1000000.0 * raw * mod_mult))


func mean_aim_err() -> float:
	return _aim_sum / float(maxi(beats_hit, 1))


func stats() -> Dictionary:
	return {
		"n_max": n_max, "n300": n300, "n200": n200, "n100": n100, "n50": n50,
		"n_miss": n_miss, "beats_hit": beats_hit, "beats_total": chart.beats.size(),
		"aim_err": mean_aim_err(), "max_combo": max_combo, "accuracy": accuracy(),
		"grade": grade(), "score": dirigent_score(), "failed": false,
		"beat_acc": beat_acc(), "cue_acc": cue_acc(), "mods": [], "mod_mult": mod_mult,
		"mode": "dirigent",
	}


# ---------------------------------------------------------------------------
# Autoplay-Bot
# ---------------------------------------------------------------------------

## Plan eines menschlich-glatten Bots (deterministisch aus seed): je Schlag ein
## Versatz der Hand (Einheiten, <= aim * INNER_R), je Einsatz ein Zeitversatz
## (ms, <= jitter) und ob er ausgelassen wird (skip_every > 0: jeder n-te).
## Ergebnis: {"beat_off": [Vector2], "cue_dt": [float], "cue_skip": [bool]}.
static func bot_plan(p_chart: DirigentChart, seed_v: int, jitter_ms: float, aim: float,
		skip_every: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var off: Array[Vector2] = []
	for i in p_chart.beats.size():
		var a := rng.randf() * TAU
		var r := rng.randf() * aim * INNER_R
		off.append(Vector2(cos(a), sin(a)) * r)
	var dts: Array[float] = []
	var skips: Array[bool] = []
	for i in p_chart.cues.size():
		dts.append((rng.randf() * 2.0 - 1.0) * jitter_ms)
		skips.append(skip_every > 0 and i % skip_every == skip_every - 1)
	return {"beat_off": off, "cue_dt": dts, "cue_skip": skips}


## Versatz der Hand zur Zeit t: zwischen den Schlag-Versaetzen weich geblendet.
static func bot_offset_at(p_chart: DirigentChart, plan: Dictionary, t: float) -> Vector2:
	var offs: Array = plan.get("beat_off", [])
	var i := p_chart.beat_at(t)
	if offs.is_empty():
		return Vector2.ZERO
	if i < 0:
		return offs[0]
	if i + 1 >= offs.size() or p_chart.is_gap(i):
		return offs[i]
	var u := (t - float(p_chart.beats[i].t)) / (float(p_chart.beats[i + 1].t) - float(p_chart.beats[i].t))
	u = clampf(u, 0.0, 1.0)
	return (offs[i] as Vector2).lerp(offs[i + 1], u * u * (3.0 - 2.0 * u))


var _bot_ci := 0


## Bot-Schritt zur Zeit t (jeden Frame): Hand folgt dem Ideal-Weg (plus glatter
## Versatz), faellige Einsaetze werden gedrueckt. Wie ein Spieler: Cursor- und
## Tasten-Ereignisse laufen durch cursor_moved/key_down, werden also mitgeschrieben.
func bot_step(plan: Dictionary, t: float) -> void:
	var dts: Array = plan.get("cue_dt", [])
	var skips: Array = plan.get("cue_skip", [])
	while _bot_ci < chart.cues.size():
		var c: Dictionary = chart.cues[_bot_ci]
		var dt := float(dts[_bot_ci]) if _bot_ci < dts.size() else 0.0
		var tp := float(c.t) + dt
		if tp > t:
			break
		var skip := bool(skips[_bot_ci]) if _bot_ci < skips.size() else false
		if not skip:
			cursor_moved(chart.ideal_at(tp) + bot_offset_at(chart, plan, tp), tp)
			for k in 2:
				if DirigentChart.mask_has(int(c.mask), k):
					key_down(k, tp)
		_bot_ci += 1
	cursor_moved(chart.ideal_at(t) + bot_offset_at(chart, plan, t), t)
