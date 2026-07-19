class_name ManiaCore
extends RefCounted

## TETHRA-Mania (4K): 4 Spalten, eine Taste pro Spalte, Timing-Fenster aus OD
## (Mania-Formeln). Hold-Notes (LN): beim Head druecken und bis zum Ende
## halten — fruehes Loslassen degradiert auf MEH ("DROP"). Jede Note/LN zaehlt
## als EIN Acc-Objekt (konsistent mit dem Standard-Modus).

signal note_spawned(index: int)
signal note_judged(index: int, result: Dictionary)
signal hold_started(index: int, quality: int)
signal lane_pressed(column: int, hit: bool)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

## Volle osu!mania-Staffel: MAX(320er/rainbow), PERFECT(300), GOOD(200),
## OK(100), MEH(50), MISS — Fenster und Acc exakt wie im Original (Stable).
enum Quality { MAX, PERFECT, GOOD, OK, MEH, MISS }

var beatmap: Beatmap
var columns := 4
var preempt: float = 1000.0
var w_max: float = 16.5
var w300: float = 49.5
var w200: float = 82.5
var w100: float = 112.5
var w50: float = 136.5
var w_miss: float = 173.5

var _next_spawn := 0
## Pro Spalte: Index-Liste der Notes + Zeiger auf die naechste offene.
var _lane_notes: Array = []
var _lane_head: Array[int] = []
var _judged: Dictionary = {}
## Aktive Holds pro Spalte: index oder -1.
var _active_hold: Array[int] = []
var _hold_quality: Array[int] = []

var combo := 0
var max_combo := 0
var n_max := 0
var n300 := 0
var n200 := 0
var n100 := 0
var n50 := 0
var n_miss := 0
var score := 0
## ScoreV2-Prinzip: Praezisions-/Combo-Anteile akkumulieren als float.
const ACC_WEIGHT := [1.0, 1.0, 2.0 / 3.0, 1.0 / 3.0, 1.0 / 6.0, 0.0]
var _score_f := 0.0
var _total_notes := 0
var hp := 1.0
var no_fail := false
var failed := false
var _finished_emitted := false
var _judged_count := 0

var _hp_miss_damage := 0.08
var _hp_heal := {
	Quality.MAX: 0.016, Quality.PERFECT: 0.014, Quality.GOOD: 0.010,
	Quality.OK: 0.005, Quality.MEH: 0.002,
}


## Konstante Anflugzeit fuer ALLE Maps — wie im Original: osu!mania kennt
## kein AR, nur der Scroll-Speed des Spielers bestimmt das Tempo. Damit
## fliegen Noten auf jeder Map gleich schnell und niedrig-AR-Maps kleben
## nicht mehr gedraengt aufeinander.
const BASE_PREEMPT := 1200.0

## scroll_scale: Mania-Scroll-Speed (rein visuell — teilt nur die Anflugzeit,
## Timing-Fenster bleiben exakt). ar_override wird in Mania ignoriert.
func setup(p_beatmap: Beatmap, _ar_override: float = -1.0, scroll_scale: float = 1.0) -> void:
	beatmap = p_beatmap
	columns = beatmap.column_count()
	preempt = BASE_PREEMPT / clampf(scroll_scale, 0.5, 3.0)
	var od := beatmap.od()
	w_max = DifficultyCalc.mania_window_max(od)
	w300 = DifficultyCalc.mania_window_300(od)
	w200 = DifficultyCalc.mania_window_200(od)
	w100 = DifficultyCalc.mania_window_100(od)
	w50 = DifficultyCalc.mania_window_50(od)
	w_miss = DifficultyCalc.mania_window_miss(od)
	_hp_miss_damage = 0.04 + 0.04 * (beatmap.hp() / 10.0)
	no_fail = false
	_score_f = 0.0
	_total_notes = beatmap.hit_objects.size()
	_lane_notes.clear()
	_lane_head.clear()
	_active_hold.clear()
	_hold_quality.clear()
	for c in columns:
		_lane_notes.append([])
		_lane_head.append(0)
		_active_hold.append(-1)
		_hold_quality.append(Quality.PERFECT)
	for i in beatmap.hit_objects.size():
		var obj := beatmap.hit_objects[i]
		if obj is ManiaNote:
			_lane_notes[(obj as ManiaNote).column].append(i)


## Combo-Anteil des Scores: ab 100er-Combo zaehlt eine Note voll.
func score_multiplier() -> float:
	return minf(float(combo), 100.0) / 100.0


## Map-Maximum ist IMMER exakt 1.000.000 (SS + Full Combo):
## 80% Praezision (gleiche Gewichte wie die Accuracy-Formel) + 20% Combo.
## Der Combo-Term ist auf das jeweils bestmoegliche normiert — sonst wuerde
## selbst ein perfektes Play wegen der Anlauf-Rampe keine glatte Million.
func _add_score(q: int) -> void:
	var note_i := minf(float(_judged_count + 1), 100.0)
	var combo_term := clampf(minf(float(combo), 100.0) / note_i, 0.0, 1.0)
	_score_f += 1000000.0 / maxf(float(_total_notes), 1.0) \
			* (0.8 * ACC_WEIGHT[q] + 0.2 * combo_term)
	score = int(round(_score_f))


func update(t_ms: float) -> void:
	if beatmap == null:
		return
	var objs := beatmap.hit_objects
	while _next_spawn < objs.size() and objs[_next_spawn].time - preempt <= t_ms:
		note_spawned.emit(_next_spawn)
		_next_spawn += 1
	# Verpasste Heads pro Spalte.
	for c in columns:
		while _lane_head[c] < _lane_notes[c].size():
			var idx: int = _lane_notes[c][_lane_head[c]]
			if _judged.has(idx):
				_lane_head[c] += 1
				continue
			if t_ms > objs[idx].time + w50 and _active_hold[c] != idx:
				_miss(idx)
				continue
			break
		# Hold-Ende erreicht, Taste noch unten -> Head-Qualitaet einloesen.
		var h: int = _active_hold[c]
		if h >= 0 and t_ms >= objs[h].end_time():
			_finish_hold(c, true)
	if _judged_count >= objs.size() and _next_spawn >= objs.size() and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Tastendruck in Spalte c.
func key_down(c: int, t_ms: float) -> void:
	if c < 0 or c >= columns or beatmap == null:
		return
	var objs := beatmap.hit_objects
	while _lane_head[c] < _lane_notes[c].size() and _judged.has(_lane_notes[c][_lane_head[c]]):
		_lane_head[c] += 1
	if _lane_head[c] >= _lane_notes[c].size():
		lane_pressed.emit(c, false)
		return
	var idx: int = _lane_notes[c][_lane_head[c]]
	var obj := objs[idx] as ManiaNote
	var dt := t_ms - obj.time
	if dt < -w_miss:
		lane_pressed.emit(c, false)
		return
	if dt < -w50:
		# Zu frueh: frisst die Note (Mania-Verhalten).
		_miss(idx)
		lane_pressed.emit(c, false)
		return
	if dt > w50:
		lane_pressed.emit(c, false)
		return
	var q := _quality_for(absf(dt))
	if obj.is_hold:
		_active_hold[c] = idx
		_hold_quality[c] = q
		combo += 1
		max_combo = maxi(max_combo, combo)
		_judged[idx] = { "pending": true }
		hold_started.emit(idx, q)
	else:
		_apply_hit(idx, q, dt)
	lane_pressed.emit(c, true)


## Taste losgelassen in Spalte c.
func key_up(c: int, t_ms: float) -> void:
	if c < 0 or c >= columns:
		return
	var h: int = _active_hold[c]
	if h < 0:
		return
	var end := beatmap.hit_objects[h].end_time()
	# Kurz vor dem Ende loslassen ist ok (1.5x 50er-Fenster), sonst DROP.
	_finish_hold(c, t_ms >= end - w50 * 1.5)


func _finish_hold(c: int, held_to_end: bool) -> void:
	var idx: int = _active_hold[c]
	_active_hold[c] = -1
	if idx < 0:
		return
	var q: int = _hold_quality[c] if held_to_end else Quality.MEH
	var obj := beatmap.hit_objects[idx]
	if not held_to_end:
		# Stable-Verhalten: zu fruehes Loslassen einer LN bricht die Combo.
		combo = 0
	_count_quality(q)
	_add_score(q)
	hp = minf(hp + _hp_heal[q], 1.0)
	hp_changed.emit(hp)
	var result := {
		"quality": q, "column": (obj as ManiaNote).column,
		"hold_end": true, "held": held_to_end, "miss_kind": "",
	}
	_judged[idx] = result
	_judged_count += 1
	note_judged.emit(idx, result)


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


func _count_quality(q: int) -> void:
	var base := 0
	match q:
		Quality.MAX:
			n_max += 1
			base = 320
		Quality.PERFECT:
			n300 += 1
			base = 300
		Quality.GOOD:
			n200 += 1
			base = 200
		Quality.OK:
			n100 += 1
			base = 100
		Quality.MEH:
			n50 += 1
			base = 50
	# base wird nicht mehr direkt gutgeschrieben — der Score laeuft ueber
	# das 1M-System in _add_score (Acc 80% + Combo 20%).
	var _unused := base


func _apply_hit(idx: int, q: int, dt: float) -> void:
	var obj := beatmap.hit_objects[idx]
	_count_quality(q)
	combo += 1
	max_combo = maxi(max_combo, combo)
	_add_score(q)
	hp = minf(hp + _hp_heal[q], 1.0)
	hp_changed.emit(hp)
	var result := {
		"quality": q, "dt": dt, "late": dt > 0.0,
		"column": (obj as ManiaNote).column, "miss_kind": "",
	}
	_judged[idx] = result
	_judged_count += 1
	note_judged.emit(idx, result)


func _miss(idx: int) -> void:
	var obj := beatmap.hit_objects[idx]
	n_miss += 1
	combo = 0
	hp = maxf(hp - _hp_miss_damage, 0.0)
	hp_changed.emit(hp)
	if hp <= 0.0 and not no_fail:
		failed = true
	var result := {
		"quality": Quality.MISS, "column": (obj as ManiaNote).column,
		"miss_kind": "FULL", "late": false,
	}
	_judged[idx] = result
	_judged_count += 1
	note_judged.emit(idx, result)


func accuracy() -> float:
	# EXAKT die osu!mania-Formel (Stable/ScoreV1):
	# (300*(MAX+300) + 200*n200 + 100*n100 + 50*n50) / (300 * total)
	var total := n_max + n300 + n200 + n100 + n50 + n_miss
	if total == 0:
		return 1.0
	return float(300 * (n_max + n300) + 200 * n200 + 100 * n100 + 50 * n50) \
			/ float(300 * total)


func grade() -> String:
	# osu!mania-Grades: SS = 100%, S > 95%, A > 90%, B > 80%, C > 70%.
	var acc := accuracy()
	if acc >= 1.0:
		return "SS"
	elif acc > 0.95:
		return "S"
	elif acc > 0.90:
		return "A"
	elif acc > 0.80:
		return "B"
	elif acc > 0.70:
		return "C"
	return "D"


func stats() -> Dictionary:
	return {
		"n_max": n_max, "n300": n300, "n200": n200, "n100": n100,
		"n50": n50, "n_miss": n_miss,
		"max_combo": max_combo, "accuracy": accuracy(), "grade": grade(),
		"failed": failed, "score": score,
	}


func is_judged(index: int) -> bool:
	return _judged.has(index)


func active_hold(c: int) -> int:
	return _active_hold[c]
