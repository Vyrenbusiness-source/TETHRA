class_name ManiaCore
extends RefCounted

## TETHRA-Mania (4K): 4 Spalten, eine Taste pro Spalte, Timing-Fenster aus OD
## (Mania-Formeln). Hold-Notes (LN): beim Head druecken und bis zum Ende
## halten — fruehes Loslassen ist ein Miss ("DROP"). Jede Note/LN zaehlt
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
## Scroll-Velocity-Tabelle (lazer) und Spawn-Zeit je Note (distanzbasiert:
## sichtbar sobald scroll.position(hit) - scroll.position(t) <= preempt).
var scroll := ScrollMap.new()
var _spawn_times := PackedFloat64Array()
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
## EXAKTE osu!mania-ScoreV1-Formel (max 1.000.000, mal Mod-Multiplikator):
##   Score = Base + Bonus, je Note:
##   Base  = (500000/Total) * HitValue/320
##   Bonus = (500000/Total) * HitBonusValue * sqrt(BonusZaehler)/320
##   BonusZaehler startet bei 100, MAX+2 / 300+1 / 200-8 / 100-24 / 50-44 /
##   Miss-100, geklemmt auf 0..100.
const HIT_VALUE := [320.0, 300.0, 200.0, 100.0, 50.0, 0.0]
const HIT_BONUS_VALUE := [32.0, 32.0, 16.0, 8.0, 4.0, 0.0]
const BONUS_DELTA := [2.0, 1.0, -8.0, -24.0, -44.0, -100.0]
var _score_f := 0.0
var _bonus := 100.0
var _total_notes := 0
var hp := 1.0
var no_fail := false
var failed := false
## Aktive Mods dieses Plays (Kopie von GameSession.mods beim setup).
var mods: Dictionary = {}
## Score-Multiplikator der Mods (SV x1.10, NF x0.5, kombiniert = Produkt).
var mod_mult := 1.0
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
	mods = session_mods()
	mod_mult = mod_multiplier(mods)
	no_fail = bool(mods.get("NF", false))
	_score_f = 0.0
	_bonus = 100.0
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
	_build_scroll()


## Baut die SV-Positionstabelle und die Spawn-Zeiten (einmal beim Laden).
func _build_scroll() -> void:
	var objs := beatmap.hit_objects
	scroll = build_scroll_map(beatmap, mods)
	_spawn_times.resize(objs.size())
	for i in objs.size():
		_spawn_times[i] = scroll.spawn_time(objs[i].time, preempt)


## Score-Multiplikator je Mod (kombinierbar: Produkt aller aktiven Mods).
const MOD_MULT := {"NF": 0.5, "SV": 1.1}
## Anzeige-Reihenfolge der Mod-Badges.
const MOD_ORDER := ["SV", "NF"]


## Score-Multiplikator fuer ein Mod-Dictionary (z.B. SV+NF = 1.1 * 0.5).
static func mod_multiplier(p_mods: Dictionary) -> float:
	var m := 1.0
	for k in MOD_MULT:
		if bool(p_mods.get(k, false)):
			m *= float(MOD_MULT[k])
	return m


## Aktive Mods als Badge-Liste, z.B. ["SV", "NF"].
static func mod_list(p_mods: Dictionary) -> Array:
	var out := []
	for k in MOD_ORDER:
		if bool(p_mods.get(k, false)):
			out.append(k)
	return out


## Mods aus dem Autoload GameSession (leer, falls nicht geladen).
static func session_mods() -> Dictionary:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var gs := (ml as SceneTree).root.get_node_or_null("GameSession")
		if gs != null:
			return (gs.mods as Dictionary).duplicate()
	return {}


## SV-Tabelle einer Map (lastTime = groesste Endzeit aller Objekte, lazer).
## p_mods null = GameSession.mods. Mit "SV" kommen die gruenen Linien aus
## SvMod (deterministisch je Map, Maps mit eigenem SV bleiben unveraendert).
static func build_scroll_map(bm: Beatmap, p_mods = null) -> ScrollMap:
	var m: Dictionary = p_mods if p_mods is Dictionary else session_mods()
	var objs := bm.hit_objects
	var last_time := 0.0
	if objs.is_empty():
		if not bm.timing_points.is_empty():
			last_time = bm.timing_points[bm.timing_points.size() - 1].time
	else:
		last_time = -INF
		for obj in objs:
			last_time = maxf(last_time, obj.end_time())
	var sm := ScrollMap.new()
	var tps: Array = bm.timing_points
	if bool(m.get("SV", false)):
		tps = SvMod.timing_points_for(bm)
	sm.build(tps, last_time)
	return sm


## Combo-Anteil des Scores: ab 100er-Combo zaehlt eine Note voll.
func score_multiplier() -> float:
	return minf(float(combo), 100.0) / 100.0


## Original osu!mania ScoreV1: Basis- + Bonus-Anteil, Maximum 1.000.000
## (mal mod_mult: SV 1.100.000, NF 500.000).
func _add_score(q: int) -> void:
	var unit := 500000.0 / maxf(float(_total_notes), 1.0)
	_bonus = clampf(_bonus + BONUS_DELTA[q], 0.0, 100.0)
	_score_f += unit * (HIT_VALUE[q] / 320.0) \
			+ unit * (HIT_BONUS_VALUE[q] * sqrt(_bonus) / 320.0)
	score = int(round(_score_f * mod_mult))


func update(t_ms: float) -> void:
	if beatmap == null:
		return
	var objs := beatmap.hit_objects
	while _next_spawn < objs.size() and _spawn_times[_next_spawn] <= t_ms:
		note_spawned.emit(_next_spawn)
		_next_spawn += 1
	# Verpasste Heads pro Spalte.
	for c in columns:
		_expire_lane(c, t_ms)
		# Hold-Ende erreicht, Taste noch unten -> Head-Qualitaet einloesen.
		var h: int = _active_hold[c]
		if h >= 0 and t_ms >= objs[h].end_time():
			_finish_hold(c, true)
	if _judged_count >= objs.size() and _next_spawn >= objs.size() and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Spalte c bis t_ms nachziehen: gerichtete Heads ueberspringen, Heads mit
## abgelaufenem 50er-Fenster als Miss werten (gleiche Bedingung wie update()).
func _expire_lane(c: int, t_ms: float) -> void:
	var objs := beatmap.hit_objects
	while _lane_head[c] < _lane_notes[c].size():
		var idx: int = _lane_notes[c][_lane_head[c]]
		if _judged.has(idx):
			_lane_head[c] += 1
			continue
		if t_ms > objs[idx].time + w50 and _active_hold[c] != idx:
			_miss(idx)
			continue
		break


## Tastendruck in Spalte c. t_ms ist der Zeitpunkt des Events (nicht der
## Frame-Zeit): Heads, deren Fenster bis dahin abgelaufen sind, werden erst
## als Miss gewertet — sonst wuerde ein Druck zwischen zwei Frames bei Jacks
## am alten Head haengen bleiben und die naechste Note verfehlen.
func key_down(c: int, t_ms: float) -> void:
	if c < 0 or c >= columns or beatmap == null:
		return
	var objs := beatmap.hit_objects
	_expire_lane(c, t_ms)
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
		_judged[idx] = { "pending": true, "dt": dt }
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
	var obj := beatmap.hit_objects[idx]
	if not held_to_end:
		# Mitten im Hold losgelassen: Miss (Combo-Bruch + HP-Abzug wie eine verpasste Note).
		n_miss += 1
		combo = 0
		_add_score(Quality.MISS)
		hp = maxf(hp - _hp_miss_damage, 0.0)
		hp_changed.emit(hp)
		if hp <= 0.0 and not no_fail:
			failed = true
		var dropped := {
			"quality": Quality.MISS, "column": (obj as ManiaNote).column,
			"hold_end": true, "held": false, "miss_kind": "DROP", "late": false,
		}
		_judged[idx] = dropped
		_judged_count += 1
		note_judged.emit(idx, dropped)
		return
	var q: int = _hold_quality[c]
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


## Zeitfehler des Hold-Kopfs (ms, + = spaet), solange der Hold laeuft; sonst 0.
func hold_head_dt(idx: int) -> float:
	var j: Dictionary = _judged.get(idx, {})
	return float(j.get("dt", 0.0))


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
	_add_score(Quality.MISS)
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
		"mods": mod_list(mods), "mod_mult": mod_mult,
	}


func is_judged(index: int) -> bool:
	return _judged.has(index)


func active_hold(c: int) -> int:
	return _active_hold[c]
