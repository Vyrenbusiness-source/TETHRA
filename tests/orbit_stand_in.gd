extends RefCounted

## PLATZHALTER fuer Shots/Tests von orbit-play, bis Task orbit-core
## (scripts/orbit/orbit_note.gd, orbit_converter.gd, orbit_core.gd) in main ist.
## Gleiche Schnittstelle, einfache Logik. Wird von orbit_game.gd nur geladen,
## wenn scripts/orbit/orbit_core.gd fehlt. Kein Spielcode haengt sonst daran.


class Note:
	extends RefCounted
	var time_ms := 0.0
	var end_ms := 0.0
	var angle_deg := 0.0
	var end_angle_deg := 0.0
	var ring := 0
	var is_arc := false
	var source_index := 0

	func angle_at(t_ms: float) -> float:
		if not is_arc or end_ms <= time_ms:
			return angle_deg
		var u := clampf((t_ms - time_ms) / (end_ms - time_ms), 0.0, 1.0)
		return fposmod(lerpf(angle_deg, end_angle_deg, u), 360.0)


class Converter:
	extends RefCounted

	static func convert(bm: Beatmap) -> Array:
		var out: Array = []
		var a := 0.0
		var prev_t := -99999.0
		var prev_c := -1
		var i := 0
		for o in bm.hit_objects:
			var m := o as ManiaNote
			if m == null:
				i += 1
				continue
			var n := Note.new()
			n.time_ms = m.time
			n.end_ms = m.end_time() if m.is_hold else m.time
			n.ring = 0 if m.column == 1 or m.column == 2 else 1
			if absf(m.time - prev_t) > 2.0:
				var gap := clampf(m.time - prev_t, 0.0, 600.0)
				a = fposmod(a + (float(m.column - 1.5) * 0.12 * gap), 360.0)
			elif m.column != prev_c:
				n.ring = 1 - n.ring
			n.angle_deg = a
			n.is_arc = m.is_hold and n.end_ms - n.time_ms > 120.0
			var span := clampf((n.end_ms - n.time_ms) * 0.09, 20.0, 140.0)
			n.end_angle_deg = a + (span if m.column % 2 == 0 else -span) if n.is_arc else a
			if not n.is_arc:
				n.end_ms = n.time_ms
			n.source_index = i
			out.append(n)
			prev_t = m.time
			prev_c = m.column
			i += 1
		return out


class Core:
	extends RefCounted
	signal note_judged(index: int, result: Dictionary)
	signal arc_started(index: int)
	signal hp_changed(hp: float)
	signal finished(stats: Dictionary)

	const TOL := 22.0
	var notes: Array = []
	var preempt := 1200.0
	var w_max := 16.5
	var w300 := 49.5
	var w200 := 82.5
	var w100 := 112.5
	var w50 := 136.5
	var w_miss := 173.5
	var combo := 0
	var max_combo := 0
	var n_max := 0
	var n300 := 0
	var n200 := 0
	var n100 := 0
	var n50 := 0
	var n_miss := 0
	var score := 0
	var hp := 1.0
	var no_fail := false
	var failed := false
	var _judged: Dictionary = {}
	var _arc := [-1, -1]
	var _arc_q := [0, 0]
	var _arc_out := [0.0, 0.0]
	var _cursor := 0.0
	var _done := false

	func setup(p_notes: Array, od: float, scroll: float) -> void:
		notes = p_notes
		preempt = ManiaCore.preempt_for(scroll)
		w_max = DifficultyCalc.mania_window_max(od)
		w300 = DifficultyCalc.mania_window_300(od)
		w200 = DifficultyCalc.mania_window_200(od)
		w100 = DifficultyCalc.mania_window_100(od)
		w50 = DifficultyCalc.mania_window_50(od)
		w_miss = DifficultyCalc.mania_window_miss(od)

	func _err(a: float, b: float) -> float:
		return absf(angle_difference(deg_to_rad(a), deg_to_rad(b))) * 180.0 / PI

	func _q(adt: float) -> int:
		if adt <= w_max: return 0
		if adt <= w300: return 1
		if adt <= w200: return 2
		if adt <= w100: return 3
		return 4

	func update(t: float) -> void:
		for r in 2:
			var ai: int = _arc[r]
			if ai < 0:
				continue
			var n = notes[ai]
			if t >= n.end_ms:
				_arc[r] = -1
				_judge(ai, _arc_q[r], 0.0, {"hold_end": true, "held": true})
			elif _err(_cursor, n.angle_at(t)) > TOL:
				_arc_out[r] += 16.0
				if _arc_out[r] > 150.0:
					_arc[r] = -1
					_miss(ai, "DROP")
			else:
				_arc_out[r] = 0.0
		for i in notes.size():
			if _judged.has(i) or _arc.has(i):
				continue
			if notes[i].time_ms + w50 < t:
				_miss(i, "FULL")
			elif notes[i].time_ms > t:
				break
		if not _done and _judged.size() >= notes.size():
			_done = true
			finished.emit(stats())

	func key_down(ring: int, t: float, cursor_deg: float) -> void:
		_cursor = cursor_deg
		for i in notes.size():
			var n = notes[i]
			if _judged.has(i) or _arc.has(i) or n.ring != ring:
				continue
			if n.time_ms - t > w_miss:
				return
			var dt: float = t - n.time_ms
			if absf(dt) > w50 or _err(cursor_deg, n.angle_deg) > TOL:
				continue
			var q := _q(absf(dt))
			if n.is_arc:
				_arc[ring] = i
				_arc_q[ring] = q
				_arc_out[ring] = 0.0
				arc_started.emit(i)
			else:
				_judge(i, q, dt, {})
			return

	func key_up(ring: int, t: float) -> void:
		var ai: int = _arc[ring]
		if ai >= 0 and t < notes[ai].end_ms - w100:
			_arc[ring] = -1
			_miss(ai, "DROP")

	func cursor_moved(cursor_deg: float, _t: float) -> void:
		_cursor = cursor_deg

	func _judge(i: int, q: int, dt: float, extra: Dictionary) -> void:
		match q:
			0: n_max += 1
			1: n300 += 1
			2: n200 += 1
			3: n100 += 1
			_: n50 += 1
		combo += 1
		max_combo = maxi(max_combo, combo)
		hp = minf(hp + 0.02, 1.0)
		hp_changed.emit(hp)
		_judged[i] = true
		score = int(1000000.0 * accuracy() * float(_judged.size()) / maxf(notes.size(), 1.0))
		var res := {"quality": q, "dt": dt, "angle_err": 0.0, "ring": notes[i].ring}
		res.merge(extra)
		note_judged.emit(i, res)

	func _miss(i: int, kind: String) -> void:
		n_miss += 1
		combo = 0
		hp = maxf(hp - 0.08, 0.0)
		hp_changed.emit(hp)
		if hp <= 0.0 and not no_fail:
			failed = true
		_judged[i] = true
		note_judged.emit(i, {"quality": 5, "ring": notes[i].ring, "miss_kind": kind})

	func accuracy() -> float:
		var total := n_max + n300 + n200 + n100 + n50 + n_miss
		if total == 0:
			return 1.0
		return float(300 * (n_max + n300) + 200 * n200 + 100 * n100 + 50 * n50) / float(300 * total)

	func grade() -> String:
		var acc := accuracy()
		if acc >= 1.0: return "SS"
		if acc > 0.95: return "S"
		if acc > 0.90: return "A"
		if acc > 0.80: return "B"
		if acc > 0.70: return "C"
		return "D"

	func stats() -> Dictionary:
		return {"n_max": n_max, "n300": n300, "n200": n200, "n100": n100, "n50": n50,
			"n_miss": n_miss, "max_combo": max_combo, "accuracy": accuracy(),
			"grade": grade(), "failed": failed, "score": score, "mods": [], "mod_mult": 1.0}
