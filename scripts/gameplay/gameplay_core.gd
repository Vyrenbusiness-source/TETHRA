class_name GameplayCore
extends RefCounted

## TETHRA-Spiellogik (Tipp-Modus, final): Maus zielt, Hook-Taste im
## Timing-Fenster druecken. Judgement-Regeln exakt Masterplan 3.5
## (DifficultyCalc) — Fenster/Radius unveraenderlich.
## Slider: Head klicken + Taste bis zum Ende halten (EIN Acc-Objekt,
## loslassen degradiert auf MEH/"DROP"). Spinner: Auto-300 bei endTime.

signal note_spawned(index: int)
signal note_judged(index: int, result: Dictionary)
signal slider_started(index: int, quality: int)
signal hp_changed(hp: float)
signal finished(stats: Dictionary)

enum Quality { PERFECT, GOOD, MEH, MISS }

const EARLY_LOCK_MS := 400.0

var beatmap: Beatmap

var preempt: float = 1200.0
var radius: float = 36.0
var w_perfect: float = 40.0
var w_good: float = 90.0
var w_meh: float = 140.0

var _next_spawn := 0
var _open := 0
var _judged: Dictionary = {}
var _spinner_done: Dictionary = {}

var _pending_slider := -1
var _pending_quality := Quality.PERFECT
var _holding := false
## Follow-Circle (osu-korrekt): Cursor muss dem Laufball folgen.
const FOLLOW_FACTOR := 2.4
const FOLLOW_MIN_FRACTION := 0.7
var _slider_pts: PackedVector2Array = PackedVector2Array()
var _slider_lens: Array[float] = []
var _slider_total := 0.0
var _follow_time_on := 0.0
var _follow_time_all := 0.0
var _last_update_t := 0.0

var combo := 0
var max_combo := 0
var n300 := 0
var n100 := 0
var n50 := 0
var n_miss := 0
var score := 0
var hp := 1.0
var no_fail := false
var failed := false
var _finished_emitted := false

var _hp_miss_damage := 0.08
var _hp_heal := { Quality.PERFECT: 0.015, Quality.GOOD: 0.008, Quality.MEH: 0.003 }


func setup(p_beatmap: Beatmap, ar_override: float = -1.0) -> void:
	beatmap = p_beatmap
	var ar := beatmap.ar() if ar_override < 0.0 else ar_override
	preempt = DifficultyCalc.preempt(ar)
	radius = DifficultyCalc.anchor_radius(beatmap.cs())
	w_perfect = DifficultyCalc.window_perfect(beatmap.od())
	w_good = DifficultyCalc.window_good(beatmap.od())
	w_meh = DifficultyCalc.window_meh(beatmap.od())
	_hp_miss_damage = 0.05 + 0.05 * (beatmap.hp() / 10.0)
	no_fail = false
	_apply_stacking()


const STACK_DIST := 3.0
const STACK_OFFSET := 5.0

## Gestapelte Notes diagonal versetzen (Doppelte klar erkennbar).
func _apply_stacking() -> void:
	var chain_base := Vector2.INF
	var chain_idx := 0
	var last_time := -1.0e12
	for obj in beatmap.hit_objects:
		if obj.kind == HitObject.Kind.SPINNER:
			chain_base = Vector2.INF
			continue
		var p := obj.position()
		if chain_base != Vector2.INF and p.distance_to(chain_base) <= STACK_DIST \
				and obj.time - last_time <= preempt:
			chain_idx += 1
			obj.x = chain_base.x - STACK_OFFSET * chain_idx
			obj.y = chain_base.y - STACK_OFFSET * chain_idx
		else:
			chain_base = p
			chain_idx = 0
		last_time = obj.time


func set_holding(h: bool) -> void:
	_holding = h


func score_multiplier() -> float:
	return 1.0 + minf(float(combo), 300.0) / 100.0


## cursor_osu: fuer den Slider-Follow-Circle (Vector2.INF = kein Cursor-Check,
## z.B. in Tests ohne Cursor-Simulation).
func update(t_ms: float, cursor_osu: Vector2 = Vector2.INF) -> void:
	if beatmap == null:
		return
	var objs := beatmap.hit_objects
	# Follow-Circle verfolgen: Cursor muss beim Laufball bleiben (osu-korrekt).
	if _pending_slider >= 0 and cursor_osu != Vector2.INF:
		var s_obj := objs[_pending_slider]
		var f_dt := maxf(t_ms - _last_update_t, 0.0)
		if t_ms > s_obj.time and f_dt > 0.0 and f_dt < 500.0:
			_follow_time_all += f_dt
			if cursor_osu.distance_to(slider_ball_pos(t_ms)) <= radius * FOLLOW_FACTOR:
				_follow_time_on += f_dt
	_last_update_t = t_ms
	while _next_spawn < objs.size() and objs[_next_spawn].time - preempt <= t_ms:
		note_spawned.emit(_next_spawn)
		_next_spawn += 1
	while _open < objs.size():
		var obj := objs[_open]
		if _judged.has(_open):
			_open += 1
			continue
		if obj.kind == HitObject.Kind.SPINNER:
			if t_ms >= obj.end_time() and not _spinner_done.has(_open):
				_spinner_done[_open] = true
				_apply_hit(_open, Quality.PERFECT, 0.0)
			if t_ms >= obj.end_time():
				_open += 1
				continue
			break
		if t_ms > obj.time + w_meh:
			_miss(_open, "FULL", Vector2.ZERO)
			continue
		break
	if _pending_slider >= 0 and t_ms >= objs[_pending_slider].end_time():
		_finalize_slider()
	if _open >= objs.size() and _next_spawn >= objs.size() \
			and _pending_slider < 0 and not _finished_emitted:
		_finished_emitted = true
		finished.emit(stats())


## Tastendruck: Aim (Cursor im Radius) + Timing (Fenster aus OD).
func handle_click(t_ms: float, cursor_osu: Vector2) -> Dictionary:
	if beatmap == null or _open >= beatmap.hit_objects.size():
		return {}
	var obj := beatmap.hit_objects[_open]
	if obj.kind == HitObject.Kind.SPINNER:
		return {}
	var dt := t_ms - obj.time
	if dt < -EARLY_LOCK_MS:
		return {}
	if dt < -w_meh:
		return _miss(_open, "EARLY", cursor_osu)
	if dt > w_meh:
		return {}
	if cursor_osu.distance_to(obj.position()) > radius:
		return _miss(_open, "AIM", cursor_osu)
	var q := _quality_for(absf(dt))
	if obj.kind == HitObject.Kind.SLIDER:
		return _start_slider(_open, q, dt)
	return _apply_hit(_open, q, dt)


func _quality_for(abs_dt: float) -> int:
	if abs_dt <= w_perfect:
		return Quality.PERFECT
	elif abs_dt <= w_good:
		return Quality.GOOD
	return Quality.MEH


## Slider-Head getroffen: Combo sofort, Wertung am Ende (halten!).
func _start_slider(index: int, q: int, dt: float) -> Dictionary:
	var obj := beatmap.hit_objects[index]
	combo += 1
	max_combo = maxi(max_combo, combo)
	_pending_slider = index
	_pending_quality = q
	_holding = true
	# Kurve fuer den Follow-Circle cachen.
	_slider_pts = (obj as HitSlider).path_points()
	_slider_lens.clear()
	_slider_total = 0.0
	for i in _slider_pts.size():
		if i > 0:
			_slider_total += _slider_pts[i].distance_to(_slider_pts[i - 1])
		_slider_lens.append(_slider_total)
	_follow_time_on = 0.0
	_follow_time_all = 0.0
	var placeholder := { "quality": q, "dt": dt, "pending": true, "late": dt > 0.0, "pos": obj.position() }
	_judged[index] = placeholder
	if index == _open:
		_advance_open()
	slider_started.emit(index, q)
	return placeholder


## Laufball-Position auf der Kurve (osu-Koordinaten, mit Ping-Pong-Slides).
func slider_ball_pos(t_ms: float) -> Vector2:
	if _pending_slider < 0 or _slider_pts.size() < 2 or _slider_total <= 0.0:
		return Vector2.ZERO
	var obj := beatmap.hit_objects[_pending_slider]
	var dur := maxf(obj.total_duration_ms(), 1.0)
	var prog := clampf((t_ms - obj.time) / dur, 0.0, 1.0)
	var slides: int = maxi(obj.slides, 1)
	var leg := prog * float(slides)
	var leg_i := int(leg)
	var frac := leg - float(leg_i)
	if leg_i % 2 == 1:
		frac = 1.0 - frac
	var target := frac * _slider_total
	for i in range(1, _slider_pts.size()):
		if _slider_lens[i] >= target:
			var seg := _slider_lens[i] - _slider_lens[i - 1]
			var k := 0.0 if seg <= 0.0 else (target - _slider_lens[i - 1]) / seg
			return _slider_pts[i - 1].lerp(_slider_pts[i], k)
	return _slider_pts[_slider_pts.size() - 1]


func _finalize_slider() -> void:
	var index := _pending_slider
	var obj := beatmap.hit_objects[index]
	# osu-korrekt: Taste gehalten UND dem Ball im Follow-Circle gefolgt.
	var followed := _follow_time_all <= 0.0 \
		or (_follow_time_on / _follow_time_all) >= FOLLOW_MIN_FRACTION
	_pending_slider = -1
	var q: int = _pending_quality if (_holding and followed) else Quality.MEH
	var base := 0
	match q:
		Quality.PERFECT:
			n300 += 1
			base = 300
		Quality.GOOD:
			n100 += 1
			base = 100
		Quality.MEH:
			n50 += 1
			base = 50
	var bonus := (score_multiplier() - 1.0) * float(base)
	score += base + int(bonus * (1.0 if q == Quality.PERFECT else 0.5))
	hp = minf(hp + _hp_heal[q], 1.0)
	hp_changed.emit(hp)
	var result := {
		"quality": q, "dt": 0.0, "miss_kind": "", "late": false,
		"pos": (obj as HitSlider).curve_end(), "slider_end": true,
		"held": _holding and followed,
	}
	_judged[index] = result
	note_judged.emit(index, result)


func _apply_hit(index: int, q: int, dt: float) -> Dictionary:
	var obj := beatmap.hit_objects[index]
	var base := 0
	match q:
		Quality.PERFECT:
			n300 += 1
			base = 300
		Quality.GOOD:
			n100 += 1
			base = 100
		Quality.MEH:
			n50 += 1
			base = 50
	var bonus := (score_multiplier() - 1.0) * float(base)
	score += base + int(bonus * (1.0 if q == Quality.PERFECT else 0.5))
	combo += 1
	max_combo = maxi(max_combo, combo)
	hp = minf(hp + _hp_heal[q], 1.0)
	hp_changed.emit(hp)
	var result := {
		"quality": q, "dt": dt, "miss_kind": "",
		"late": dt > 0.0, "pos": obj.position(),
	}
	_judged[index] = result
	if index == _open:
		_advance_open()
	note_judged.emit(index, result)
	return result


func _miss(index: int, kind: String, cursor_osu: Vector2) -> Dictionary:
	var obj := beatmap.hit_objects[index]
	n_miss += 1
	combo = 0
	hp = maxf(hp - _hp_miss_damage, 0.0)
	hp_changed.emit(hp)
	if hp <= 0.0 and not no_fail:
		failed = true
	var result := {
		"quality": Quality.MISS, "dt": 0.0, "miss_kind": kind,
		"late": false, "pos": obj.position(), "cursor": cursor_osu,
	}
	_judged[index] = result
	_advance_open()
	note_judged.emit(index, result)
	return result


func _advance_open() -> void:
	_open += 1
	while _open < beatmap.hit_objects.size() and _judged.has(_open):
		_open += 1


func accuracy() -> float:
	var total := n300 + n100 + n50 + n_miss
	if total == 0:
		return 1.0
	return float(300 * n300 + 100 * n100 + 50 * n50) / float(300 * total)


func grade() -> String:
	var acc := accuracy()
	if acc >= 0.95 and n_miss == 0:
		return "S"
	elif acc >= 0.90:
		return "A"
	elif acc >= 0.80:
		return "B"
	elif acc >= 0.70:
		return "C"
	return "D"


func stats() -> Dictionary:
	return {
		"n300": n300, "n100": n100, "n50": n50, "n_miss": n_miss,
		"max_combo": max_combo, "accuracy": accuracy(), "grade": grade(),
		"failed": failed, "score": score,
	}


func open_index() -> int:
	return _open


func is_judged(index: int) -> bool:
	return _judged.has(index)
