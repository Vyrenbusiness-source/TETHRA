class_name OrbitConverter
extends RefCounted

## Orbit "Satelliten": Beatmap (osu!standard oder Mania 4K) -> Ziele im Feld
## (docs/modes/orbit_satellit.md). Rein deterministisch, kein Zufall.
##
## Ablauf: Ereignisse sammeln -> Mindestabstand -> Taste/Akzent -> Position
## (Sprungweite gekappt, im Feld, ohne Ueberdeckung) -> Erscheinen auf einem
## Beat-Tick, Runden so, dass hoechstens MAX_VISIBLE Ziele zugleich sichtbar sind.

## Ereignisse naeher als das gelten als ein Akkord.
const CHORD_EPS_MS := 2.0
## Mindestabstand zweier Ziele (und nach einem Halten).
const MIN_GAP_MS := 75.0
const MAX_VISIBLE := 6
## Leichte Maps: weniger Ziele je Sekunde.
const EASY_NPS := 2.5
## Beats kuerzer als das: eine Runde = 2 Beats.
const MIN_BEAT_MS := 330.0
const MIN_HOLD_MS := 100.0
const MAX_HOLD_MS := 6000.0
const EASY_HOLD_BEATS := 2.0

const FIELD_MIN := Vector2(0.06, 0.08)
const FIELD_MAX := Vector2(0.94, 0.92)
## Mindestabstand der Mitten zweier gleichzeitig sichtbarer Ziele.
const SEP := 0.12
## Sprungweite (Feld-Einheiten) <= JUMP_BASE + JUMP_V * Sekunden.
const JUMP_BASE := 0.06
const JUMP_V_MIN := 1.0
const JUMP_V_MAX := 2.2
const JUMP_V_PER_NPS := 0.22
const EASY_JUMP_V := 0.9
const EASY_JUMP_MAX := 0.3
## Mania: erzeugter Schritt.
const MANIA_BASE := 0.07
const MANIA_V := 0.6
const MANIA_MAX := 0.26
## Halten: Kugelgeschwindigkeit (Feld/s) hoechstens, Pfad-Aufloesung.
const HOLD_V_MAX := 1.4
const PATH_STEP := 0.035
const MANIA_HOLD_V := 0.7
const MANIA_HOLD_MAX := 0.24

# Sterne
const STAR_HOP_MS := 1000.0
const STAR_KD := 0.55
const STAR_KJ := 0.5
const STAR_KS := 0.35
const STAR_KH := 0.3
const STAR_KA := 0.25
const STAR_DECAY := 0.95
const STAR_JUMP_CAP := 4.0
const STAR_SWITCH_GAP_MS := 400.0
const STAR_MAX := 15.0
const STAR_SCALE := 1.0
const STAR_POW := 1.0


static func convert(beatmap: Beatmap, laps: int = 2) -> Array[OrbitNote]:
	if beatmap == null:
		return [] as Array[OrbitNote]
	if beatmap.is_mania():
		return convert_mania(beatmap, laps)
	return convert_std(beatmap, laps)


static func convert_std(beatmap: Beatmap, laps: int = 2) -> Array[OrbitNote]:
	if beatmap == null:
		return [] as Array[OrbitNote]
	return _build(_events_std(beatmap, OrbitClock.from_beatmap(beatmap)), beatmap, laps, false)


static func convert_mania(beatmap: Beatmap, laps: int = 2) -> Array[OrbitNote]:
	if beatmap == null:
		return [] as Array[OrbitNote]
	return _build(_events_mania(beatmap), beatmap, laps, true)


# ---------------------------------------------------------------------------
# 1. Ereignisse
# ---------------------------------------------------------------------------

## Ereignis: {t, end (== t bei Tap), key (-1 = offen), col, pos, path (roh, Feld), src, spin}
static func _events_std(bm: Beatmap, _clock: OrbitClock) -> Array:
	var out: Array = []
	var objs := bm.hit_objects
	for i in objs.size():
		var o = objs[i]
		if o is ManiaNote:
			continue
		var hs: int = o.hit_sound
		var key := OrbitNote.KEY_B if (hs & 10) != 0 else OrbitNote.KEY_A
		var e := {"t": float(o.time), "end": float(o.time), "key": key, "col": 0,
			"pos": _norm(Vector2(o.x, o.y)), "path": PackedVector2Array(), "src": i,
			"spin": false, "finish": (hs & 4) != 0}
		if o.kind == HitObject.Kind.SPINNER:
			e["pos"] = Vector2(0.5, 0.5)
			e["spin"] = true
			e["finish"] = true
		elif o.kind == HitObject.Kind.SLIDER and o is HitSlider:
			var dur: float = o.total_duration_ms()
			if dur >= MIN_HOLD_MS:
				e["end"] = float(o.time) + minf(dur, MAX_HOLD_MS)
				e["path"] = _slider_path(o)
				e["finish"] = false
		out.append(e)
	out.sort_custom(func(a, b): return a.t < b.t if a.t != b.t else a.src < b.src)
	return out


static func _events_mania(bm: Beatmap) -> Array:
	var k := maxi(bm.column_count(), 1)
	var notes: Array = []
	for i in bm.hit_objects.size():
		var n = bm.hit_objects[i]
		if n is ManiaNote:
			var end := float(n.time)
			if n.is_hold and float(n.end_time()) - float(n.time) >= MIN_HOLD_MS:
				end = minf(float(n.end_time()), float(n.time) + MAX_HOLD_MS)
			var c := clampi(int(n.column) * 4 / k, 0, 3)
			notes.append([float(n.time), c, end, i])
	notes.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var out: Array = []
	var j := 0
	while j < notes.size():
		var g: Array = [notes[j]]
		var t0: float = notes[j][0]
		j += 1
		while j < notes.size() and float(notes[j][0]) - t0 <= CHORD_EPS_MS:
			g.append(notes[j])
			j += 1
		var left := false
		var right := false
		var hold_note: Array = []
		for n in g:
			if int(n[1]) < 2:
				left = true
			else:
				right = true
			if float(n[2]) > float(n[0]) and (hold_note.is_empty() or float(n[2]) > float(hold_note[2])):
				hold_note = n
		var first: Array = g[0]
		var e := {"t": t0, "end": t0, "key": OrbitNote.KEY_A, "col": int(first[1]),
			"pos": Vector2.ZERO, "path": PackedVector2Array(), "src": int(first[3]),
			"spin": false, "finish": false}
		if not hold_note.is_empty():
			e["end"] = float(hold_note[2])
			e["col"] = int(hold_note[1])
			e["key"] = OrbitNote.KEY_A if int(hold_note[1]) < 2 else OrbitNote.KEY_B
			e["src"] = int(hold_note[3])
		elif left and right:
			e["finish"] = true
		else:
			e["key"] = OrbitNote.KEY_A if left else OrbitNote.KEY_B
		out.append(e)
	return out


static func _norm(p: Vector2) -> Vector2:
	return Vector2(p.x / 512.0, p.y / 384.0)


static func _clamp_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, FIELD_MIN.x, FIELD_MAX.x), clampf(p.y, FIELD_MIN.y, FIELD_MAX.y))


## Slider-Kurve (alle Durchlaeufe) im Feld, gleichmaessig abgetastet.
static func _slider_path(o: HitSlider) -> PackedVector2Array:
	var one := o.path_points()
	if one.size() < 2:
		return PackedVector2Array()
	var all := PackedVector2Array()
	for s in maxi(o.slides, 1):
		if s % 2 == 0:
			for p in one:
				all.append(_norm(p))
		else:
			for q in range(one.size() - 1, -1, -1):
				all.append(_norm(one[q]))
	return _resample(all, PATH_STEP)


static func _path_len(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


## Gleichmaessige Abtastung (Abstand step), Anfang und Ende bleiben erhalten.
static func _resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.is_empty():
		return out
	out.append(p[0])
	var carry := 0.0
	for i in range(1, p.size()):
		var a := p[i - 1]
		var b := p[i]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += step
		carry = seg - (d - step)
	var last := p[p.size() - 1]
	if out[out.size() - 1].distance_to(last) > step * 0.25 or out.size() < 2:
		out.append(last)
	return out


## Anfang des Pfads bis zur Laenge `len`.
static func _prefix(p: PackedVector2Array, len: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.is_empty():
		return out
	out.append(p[0])
	var acc := 0.0
	for i in range(1, p.size()):
		var seg := p[i - 1].distance_to(p[i])
		if acc + seg >= len:
			if len > acc and seg > 0.0:
				out.append(p[i - 1].lerp(p[i], (len - acc) / seg))
			return out
		acc += seg
		out.append(p[i])
	return out


# ---------------------------------------------------------------------------
# 2. Aufbau
# ---------------------------------------------------------------------------

static func _build(events: Array, bm: Beatmap, laps_req: int, mania: bool) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var clock := OrbitClock.from_beatmap(bm)
	laps_req = clampi(laps_req, 1, 4)
	# Mindestabstand
	var kept: Array = []
	var last_t := -INF
	var last_end := -INF
	for e in events:
		if float(e.t) - last_t < MIN_GAP_MS or float(e.t) < last_end + MIN_GAP_MS:
			continue
		kept.append(e)
		last_t = e.t
		last_end = maxf(float(e.end), float(e.t))
	if kept.is_empty():
		return out
	var span := maxf((float(kept[-1].t) - float(kept[0].t)) / 1000.0, 1.0)
	var nps := float(kept.size()) / span
	var easy := nps < EASY_NPS
	var jump_v := clampf(JUMP_V_MIN + JUMP_V_PER_NPS * nps, JUMP_V_MIN, JUMP_V_MAX)
	if easy:
		jump_v = EASY_JUMP_V

	var placed: Array = []   # [pos, spawn_req, end]
	var prev_pos := Vector2(0.5, 0.5)
	var prev_t := -INF
	var flow := Vector2(1.0, 1.0)
	var built: Array[OrbitNote] = []
	for idx in kept.size():
		var e: Dictionary = kept[idx]
		var t: float = e.t
		var end: float = e.end
		var is_hold := end - t >= MIN_HOLD_MS
		var beat := clock.beat_ms_at(t)
		var lap := beat if beat >= MIN_BEAT_MS else 2.0 * beat
		var dt := 0.5 if prev_t == -INF else maxf((t - prev_t) / 1000.0, 0.0)
		# Halte-Dauer leichter Maps
		if is_hold and easy and not mania:
			end = minf(end, t + EASY_HOLD_BEATS * beat)
			if end - t < MIN_HOLD_MS:
				is_hold = false
				end = t
		# Taste
		var key: int = e.key
		if bool(e.finish) and not easy and not is_hold:
			key = OrbitNote.KEY_ACCENT
		# Position
		var want: Vector2
		if mania:
			var c: int = e.col
			var d := Vector2(-1.0, 0.0) if c == 0 else (Vector2(0.0, -1.0) if c == 1 else (Vector2(0.0, 1.0) if c == 2 else Vector2(1.0, 0.0)))
			flow = d
			var dist := minf(MANIA_BASE + MANIA_V * dt, MANIA_MAX)
			if prev_t == -INF:
				want = Vector2(0.5, 0.5)
			else:
				want = _reflect(prev_pos + d * dist)
		else:
			want = _clamp_field(e.pos)
			if prev_t != -INF:
				var maxd := JUMP_BASE + jump_v * dt
				if easy:
					maxd = minf(maxd, EASY_JUMP_MAX)
				var delta := want - prev_pos
				if delta.length() > maxd:
					want = prev_pos + delta.normalized() * maxd
				want = _clamp_field(want)
		var spawn_req := clock.beat_tick_at_or_before(t - float(laps_req) * lap)
		var pos := _free_pos(want, prev_pos, placed, spawn_req, idx, prev_t != -INF)
		# Ziel bauen
		var n: OrbitNote
		if is_hold:
			var path := PackedVector2Array()
			if mania:
				path = _mania_path(pos, flow, end - t, idx)
			else:
				path = _std_hold_path(e.path, pos, e.pos, t, end, e.end)
			n = OrbitNote.make_hold(t, end, path, key if key != OrbitNote.KEY_ACCENT else OrbitNote.KEY_A, e.src)
			prev_pos = path[path.size() - 1]
			prev_t = end
		else:
			n = OrbitNote.make_target(t, pos, key, e.src)
			prev_pos = pos
			prev_t = t
		n.lap_ms = lap
		n.laps = laps_req
		placed.append([pos, spawn_req, maxf(end, t)])
		built.append(n)
	return _assign_laps(built, clock, laps_req)


## Spiegelt Koordinaten am Feldrand zurueck (deterministisch), dann klemmen.
static func _reflect(p: Vector2) -> Vector2:
	var q := p
	if q.x < FIELD_MIN.x:
		q.x = 2.0 * FIELD_MIN.x - q.x
	elif q.x > FIELD_MAX.x:
		q.x = 2.0 * FIELD_MAX.x - q.x
	if q.y < FIELD_MIN.y:
		q.y = 2.0 * FIELD_MIN.y - q.y
	elif q.y > FIELD_MAX.y:
		q.y = 2.0 * FIELD_MAX.y - q.y
	return _clamp_field(q)


static func _conflicts(p: Vector2, placed: Array, spawn: float) -> bool:
	var j := placed.size() - 1
	var seen := 0
	while j >= 0 and seen < 48:
		var q: Array = placed[j]
		if float(q[2]) > spawn and p.distance_to(q[0]) < SEP:
			return true
		j -= 1
		seen += 1
	return false


## Naechste freie Position bei want (gleiche Sprungregel gilt, wenn moeglich).
static func _free_pos(want: Vector2, prev: Vector2, placed: Array, spawn: float, idx: int,
		has_prev: bool) -> Vector2:
	if not _conflicts(want, placed, spawn):
		return want
	var dirs := 16
	var best := want
	var found := false
	for ring in 5:
		var r := SEP * (1.05 + 0.5 * float(ring))
		for k in dirs:
			var a := TAU * float((k + idx) % dirs) / float(dirs)
			var c := want + Vector2(cos(a), sin(a)) * r
			if c.x < FIELD_MIN.x or c.x > FIELD_MAX.x or c.y < FIELD_MIN.y or c.y > FIELD_MAX.y:
				continue
			if _conflicts(c, placed, spawn):
				continue
			if not found or (has_prev and c.distance_to(prev) < best.distance_to(prev)):
				best = c
				found = true
		if found:
			return best
	# Notfall: Rasterpunkt mit dem groessten Abstand zu allen sichtbaren Zielen.
	var far := want
	var far_d := -1.0
	for gy in 9:
		for gx in 12:
			var c := Vector2(lerpf(FIELD_MIN.x, FIELD_MAX.x, float(gx) / 11.0),
					lerpf(FIELD_MIN.y, FIELD_MAX.y, float(gy) / 8.0))
			var md := _min_dist(c, placed, spawn)
			if md > far_d + 1e-6 or (absf(md - far_d) <= 1e-6 and c.distance_to(want) < far.distance_to(want)):
				far_d = md
				far = c
	return far


static func _min_dist(p: Vector2, placed: Array, spawn: float) -> float:
	var m := 10.0
	var j := placed.size() - 1
	var seen := 0
	while j >= 0 and seen < 48:
		var q: Array = placed[j]
		if float(q[2]) > spawn:
			m = minf(m, p.distance_to(q[0]))
		j -= 1
		seen += 1
	return m


static func _mania_path(pos: Vector2, flow: Vector2, dur_ms: float, idx: int) -> PackedVector2Array:
	var len := clampf(dur_ms / 1000.0 * MANIA_HOLD_V, 0.05, MANIA_HOLD_MAX)
	var d := flow
	var end := pos + d * len
	if end.x < FIELD_MIN.x or end.x > FIELD_MAX.x:
		d.x = -d.x
	if end.y < FIELD_MIN.y or end.y > FIELD_MAX.y:
		d.y = -d.y
	end = _clamp_field(pos + d * len)
	var perp := Vector2(-d.y, d.x) * (0.18 * len) * (1.0 if idx % 2 == 0 else -1.0)
	var mid := _clamp_field(pos.lerp(end, 0.5) + perp)
	return PackedVector2Array([pos, mid, end])


## Slider-Pfad auf die endgueltige Kopfposition schieben, auf Zeit/Tempo kuerzen.
static func _std_hold_path(raw: PackedVector2Array, pos: Vector2, src_pos: Vector2,
		t: float, end: float, src_end: float) -> PackedVector2Array:
	var path := raw
	if path.size() < 2:
		path = PackedVector2Array([pos, pos + Vector2(0.001, 0.0)])
	var total := _path_len(path)
	var dur_s := (end - t) / 1000.0
	var len := total
	if src_end > t and end < src_end:
		len = total * (end - t) / (src_end - t)
	len = minf(len, HOLD_V_MAX * dur_s)
	if len < total:
		path = _prefix(path, len)
	var off := pos - _clamp_field(src_pos)
	var out := PackedVector2Array()
	for p in path:
		out.append(_clamp_field(p + off))
	if out.size() < 2:
		out.append(out[0])
	out[0] = pos
	return out


## Erscheinen auf einem Beat-Tick; Runden an dichten Stellen verringern.
static func _assign_laps(ns: Array[OrbitNote], clock: OrbitClock, laps_req: int) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var vis: Array = []   # [spawn, end]
	for n in ns:
		var end := maxf(n.end_ms, n.time_ms)
		var ok := false
		var l := laps_req
		while l >= 1:
			var sp := clock.beat_tick_at_or_before(n.time_ms - float(l) * n.lap_ms)
			if _fits(vis, sp, end):
				n.spawn_ms = sp
				n.laps = l
				ok = true
				break
			l -= 1
		if ok:
			vis.append([n.spawn_ms, end])
			out.append(n)
	return out


static func _fits(vis: Array, sp: float, end: float) -> bool:
	var pts: Array = [sp]
	var lo := maxi(vis.size() - 64, 0)
	for j in range(lo, vis.size()):
		var v: Array = vis[j]
		if float(v[0]) > sp and float(v[0]) < end:
			pts.append(v[0])
	for p in pts:
		var c := 1
		for j in range(lo, vis.size()):
			var v: Array = vis[j]
			if float(v[0]) <= float(p) and float(p) < float(v[1]):
				c += 1
		if c > MAX_VISIBLE:
			return false
	return true


# ---------------------------------------------------------------------------
# Hilfen, Analyse, Sterne
# ---------------------------------------------------------------------------

## Rote Timing-Points (BPM/Takt) der Map, nach Zeit sortiert.
static func red_points(beatmap: Beatmap) -> Array:
	var reds: Array = []
	if beatmap == null:
		return reds
	for tp in beatmap.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append(tp)
	reds.sort_custom(func(a, b): return a.time < b.time)
	return reds


## Letzter Punkt eines Ziels (Halten: Pfadende).
static func end_pos(n: OrbitNote) -> Vector2:
	if n.is_hold and n.path.size() > 0:
		return n.path[n.path.size() - 1]
	return n.pos


## Spielbarkeits-Pruefung; alle Zaehler muessen 0 sein.
##  gap: Mindestabstand 75 ms verletzt; field: Position/Pfad ausserhalb des Felds;
##  spawn: Erscheinen nicht auf einem Beat-Tick (> 1 ms) oder Vorlauf zu kurz;
##  visible: mehr als 6 Ziele zugleich; overlap: zwei sichtbare Ziele naeher als SEP/2;
##  order: Zeiten nicht aufsteigend; hold: Halten ohne gueltigen Pfad.
static func violations(ns: Array[OrbitNote], beatmap: Beatmap) -> Dictionary:
	var v := {"gap": 0, "field": 0, "spawn": 0, "visible": 0, "overlap": 0, "order": 0,
		"hold": 0, "targets": ns.size()}
	var clock := OrbitClock.from_beatmap(beatmap)
	var prev_end := -INF
	var prev_t := -INF
	for i in ns.size():
		var n := ns[i]
		if n.time_ms < prev_t:
			v.order += 1
		if n.time_ms < prev_end + MIN_GAP_MS - 0.001 or n.time_ms - prev_t < MIN_GAP_MS - 0.001:
			v.gap += 1
		prev_t = n.time_ms
		prev_end = maxf(n.end_ms, n.time_ms)
		if n.pos.x < 0.0 or n.pos.x > 1.0 or n.pos.y < 0.0 or n.pos.y > 1.0:
			v.field += 1
		for p in n.path:
			if p.x < 0.0 or p.x > 1.0 or p.y < 0.0 or p.y > 1.0:
				v.field += 1
				break
		if absf(n.spawn_ms - clock.beat_tick_at_or_before(n.spawn_ms)) > 1.0 \
				or n.spawn_ms > n.time_ms - float(n.laps) * n.lap_ms + 1.0 or n.laps < 1:
			v.spawn += 1
		if n.is_hold and (n.path.size() < 2 or n.path[0] != n.pos):
			v.hold += 1
		# Sichtbarkeit zum Spawn dieses Ziels
		var c := 0
		for j in range(maxi(i - 64, 0), i + 1):
			var m := ns[j]
			if m.spawn_ms <= n.spawn_ms and n.spawn_ms < maxf(m.end_ms, m.time_ms):
				c += 1
				if j != i and m.pos.distance_to(n.pos) < SEP * 0.5:
					v.overlap += 1
		if c > MAX_VISIBLE:
			v.visible += 1
	return v


## Kennzahlen: count, nps (Ziele/s), max_visible, mean_jump (Feld-Einheiten), mean_jump_speed,
## accent_share, hold_share, spawn_err_ms (max. Abstand zum Beat-Tick; braucht beatmap).
static func analyze(ns: Array[OrbitNote], beatmap: Beatmap = null) -> Dictionary:
	var a := {"count": ns.size(), "nps": 0.0, "max_visible": 0, "mean_jump": 0.0,
		"mean_jump_speed": 0.0, "accent_share": 0.0, "hold_share": 0.0, "spawn_err_ms": 0.0}
	if ns.is_empty():
		return a
	var span := maxf((ns[-1].time_ms - ns[0].time_ms) / 1000.0, 1.0)
	a.nps = float(ns.size()) / span
	var acc := 0
	var holds := 0
	var jsum := 0.0
	var vsum := 0.0
	var clock: OrbitClock = null if beatmap == null else OrbitClock.from_beatmap(beatmap)
	var evs: Array = []
	for i in ns.size():
		var n := ns[i]
		if n.key == OrbitNote.KEY_ACCENT:
			acc += 1
		if n.is_hold:
			holds += 1
		if i > 0:
			var d := end_pos(ns[i - 1]).distance_to(n.pos)
			jsum += d
			vsum += d / maxf((n.time_ms - maxf(ns[i - 1].end_ms, ns[i - 1].time_ms)) / 1000.0, 0.05)
		if clock != null:
			a.spawn_err_ms = maxf(a.spawn_err_ms, absf(n.spawn_ms - clock.beat_tick_at_or_before(n.spawn_ms)))
		evs.append([n.spawn_ms, 1])
		evs.append([maxf(n.end_ms, n.time_ms), -1])
	evs.sort_custom(func(x, y): return x[0] < y[0] if x[0] != y[0] else x[1] < y[1])
	var cur := 0
	for e in evs:
		cur += int(e[1])
		a.max_visible = maxi(a.max_visible, cur)
	var m := float(maxi(ns.size() - 1, 1))
	a.mean_jump = jsum / m
	a.mean_jump_speed = vsum / m
	a.accent_share = float(acc) / float(ns.size())
	a.hold_share = float(holds) / float(ns.size())
	return a


## Rohwert der Orbit-Sterne (vor der Kalibrierung).
static func stars_raw(ns: Array[OrbitNote]) -> float:
	if ns.size() < 2:
		return 0.0
	var t0 := ns[0].time_ms
	var t_end := ns[-1].end_ms
	var n_win := maxi(1, int(ceil((t_end - t0) / STAR_HOP_MS)))
	var cnt := PackedFloat32Array()
	var jmp := PackedFloat32Array()
	var swt := PackedFloat32Array()
	var hld := PackedFloat32Array()
	var acc := PackedFloat32Array()
	for arr in [cnt, jmp, swt, hld, acc]:
		arr.resize(n_win)
		arr.fill(0.0)
	for i in ns.size():
		var n := ns[i]
		var w := clampi(int((n.time_ms - t0) / STAR_HOP_MS), 0, n_win - 1)
		cnt[w] += 1.0
		if n.is_hold:
			hld[w] += 1.0 + (n.end_ms - n.time_ms) / 1000.0
		if n.key == OrbitNote.KEY_ACCENT:
			acc[w] += 1.0
		if i > 0:
			var p := ns[i - 1]
			var gap := maxf(n.time_ms - maxf(p.end_ms, p.time_ms), 40.0)
			jmp[w] += minf(end_pos(p).distance_to(n.pos) / (gap / 1000.0), STAR_JUMP_CAP)
			if n.key != p.key and n.time_ms - p.time_ms < STAR_SWITCH_GAP_MS:
				swt[w] += 1.0
	var vals: Array[float] = []
	var secs := 2.0 * STAR_HOP_MS / 1000.0
	for w in n_win:
		var pw := maxi(w - 1, 0)
		var c := cnt[w] + (cnt[pw] if w > 0 else 0.0)
		var dens := c / secs
		var jm := (jmp[w] + (jmp[pw] if w > 0 else 0.0)) / maxf(c, 1.0)
		var sw := (swt[w] + (swt[pw] if w > 0 else 0.0)) / secs
		var hl := (hld[w] + (hld[pw] if w > 0 else 0.0)) / secs
		var ac := (acc[w] + (acc[pw] if w > 0 else 0.0)) / secs
		vals.append(STAR_KD * pow(dens, 0.8) + STAR_KJ * jm * minf(dens / 2.5, 1.0)
				+ STAR_KS * sw + STAR_KH * hl + STAR_KA * ac)
	vals.sort()
	vals.reverse()
	var num := 0.0
	var den := 0.0
	var wt := 1.0
	for v in vals:
		num += v * wt
		den += wt
		wt *= STAR_DECAY
		if wt < 0.001:
			break
	return num / maxf(den, 1e-6)


## Orbit-Sterne 0..15 (Dichte, Sprungweite je Zeit, Tastenwechsel, Halten).
static func stars(ns: Array[OrbitNote]) -> float:
	return clampf(STAR_SCALE * pow(stars_raw(ns), STAR_POW), 0.0, STAR_MAX)
