class_name RallyChart
extends RefCounted

## Rally: Schlagfolge aus einer Map (osu!standard oder Mania 4K) und die
## Flugbahn des Balls. Alles reine Funktionen der Zeit (kein Zustand), damit
## Core, Ansicht und Tests dieselben Zahlen sehen. Details: docs/modes/rally.md.
##
## Koordinaten der Flugbahn sind normiert (x in Breiten, y in Hoehen, y waechst
## nach unten): die Ansicht skaliert auf ihr Rechteck.

const KEY_A := 0
const KEY_B := 1
## Akkord-Toleranz (gleiche Zeit in der Quell-Map).
const CHORD_EPS_MS := 2.0
## Zwei Schlaege naeher als das werden zusammengefasst.
const MERGE_MS := 90.0
## Leichte Maps (Schlaege/s darunter): nur Achtel, also Mindestabstand 1/4 Beat.
const LIGHT_NPS := 2.5
## Kuerzere Slider/Holds bleiben normale Schlaege.
const MIN_CHARGE_MS := 200.0
const MAX_CHARGE_MS := 4000.0
## Ab diesem Abstand gibt es keinen durchgehenden Ballwechsel: Gegner schlaegt neu auf.
const BREAK_MS := 3500.0
const SERVE_LEAD_MS := 1800.0
## Nach dem Schlag vor einer Pause fliegt der Ball so lange zum Gegner und verschwindet.
const EXIT_MS := 800.0

## Layout (normiert).
const X_PLAYER := 0.14
const X_OPP := 0.86
const X_TABLE_L := 0.20
const X_TABLE_R := 0.80
const Y_TABLE := 0.66
const Y_LOW := 0.585     ## Trefferhoehe Taste A (tiefer Ball)
const Y_HIGH := 0.36     ## Trefferhoehe Taste B (hoher Ball)
const Y_OPP := 0.47
## Bruchteil der Flugzeit (x linear), an dem der Ball auf dem Tisch aufkommt.
const F_BOUNCE_OPP := 0.70
const F_BOUNCE_ME := 0.72


class Shot extends RefCounted:
	var t := 0.0            ## Notenzeit (Schlag / Druck)
	var end := 0.0          ## Loslassen (== t bei normalem Schlag)
	var key := 0            ## 0 = A (tief), 1 = B (hoch)
	var smash := false      ## Schmetterball: beide Tasten
	var serve := false      ## Ball erscheint beim Gegner neu (Start/Pause)
	var m := 0.0            ## Zeit des Gegnerschlags vor diesem Schlag
	var exit_after := false ## nach diesem Schlag folgt eine Pause
	var src := 0            ## Index des Quellobjekts

	func is_charge() -> bool:
		return end > t


static func hit_y(key: int) -> float:
	return Y_HIGH if key == KEY_B else Y_LOW


# ---------------------------------------------------------------------------
# Aufbau aus der Map
# ---------------------------------------------------------------------------

static func build(beatmap: Beatmap) -> Array[Shot]:
	var out: Array[Shot] = []
	if beatmap == null or beatmap.hit_objects.is_empty():
		return out
	var raw := _raw_events(beatmap)
	var groups := _group(raw)
	var span := 1000.0
	if groups.size() > 1:
		span = maxf(float(groups[-1][0]) - float(groups[0][0]), 1000.0)
	var light := float(groups.size()) / (span / 1000.0) < LIGHT_NPS
	for g in groups:
		var s := _shot_of(g)
		var gap := MERGE_MS
		if light:
			gap = maxf(MERGE_MS, _beat_ms(beatmap, s.t) * 0.25 - 1.0)
		if not out.is_empty() and s.t - out[-1].end < gap:
			continue
		out.append(s)
	finalize(out)
	return out


## Rohliste [t, end, key, finish, src] aus Mania- oder Standard-Objekten.
static func _raw_events(beatmap: Beatmap) -> Array:
	var list: Array = []
	var k := maxi(beatmap.column_count(), 1)
	for i in beatmap.hit_objects.size():
		var o = beatmap.hit_objects[i]
		if o is ManiaNote:
			var end := 0.0
			if o.is_hold and o.end_time() - o.time >= MIN_CHARGE_MS:
				end = minf(o.end_time(), o.time + MAX_CHARGE_MS)
			list.append([o.time, end, 0 if o.column * 2 < k else 1, false, i])
		else:
			var hs: int = o.hit_sound
			var end := 0.0
			if o.kind != HitObject.Kind.CIRCLE and o.end_time() - o.time >= MIN_CHARGE_MS:
				end = minf(o.end_time(), o.time + MAX_CHARGE_MS)
			list.append([o.time, end, 1 if (hs & 10) != 0 else 0, (hs & 4) != 0, i])
	list.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[4] < b[4])
	return list


## Gleichzeitige Objekte (<= CHORD_EPS_MS) zu Gruppen [t, [raw...]].
static func _group(list: Array) -> Array:
	var groups: Array = []
	for e in list:
		if groups.is_empty() or float(e[0]) - float(groups[-1][0]) > CHORD_EPS_MS:
			groups.append([e[0], []])
		(groups[-1][1] as Array).append(e)
	return groups


static func _shot_of(g: Array) -> Shot:
	var s := Shot.new()
	s.t = float(g[0])
	s.end = s.t
	var keys := [false, false]
	var finish := false
	var best_end := 0.0
	var charge_key := 0
	s.src = int(g[1][0][4])
	for e in g[1]:
		keys[int(e[2])] = true
		finish = finish or bool(e[3])
		if float(e[1]) > best_end:
			best_end = float(e[1])
			charge_key = int(e[2])
	if best_end > s.t:
		s.end = best_end
		s.key = charge_key
	else:
		s.key = 0 if keys[0] else 1
		s.smash = (keys[0] and keys[1]) or finish
	return s


static func _beat_ms(beatmap: Beatmap, t: float) -> float:
	var bl := 500.0
	var found := false
	for tp in beatmap.timing_points:
		if not tp.uninherited or tp.beat_length <= 0.0:
			continue
		if not found or tp.time <= t:
			bl = tp.beat_length
			found = true
	return bl


## Gegnerschlag (m) und Pausen-Marken je Schlag berechnen.
static func finalize(shots: Array[Shot]) -> void:
	for j in shots.size():
		var s := shots[j]
		s.exit_after = false
		if j == 0:
			s.serve = true
			s.m = s.t - SERVE_LEAD_MS
			continue
		var p := shots[j - 1].end
		var gap := s.t - p
		if gap > BREAK_MS:
			s.serve = true
			s.m = s.t - SERVE_LEAD_MS
			shots[j - 1].exit_after = true
		else:
			s.serve = false
			s.m = p + gap * 0.5


# ---------------------------------------------------------------------------
# Flugbahn
# ---------------------------------------------------------------------------

## Hoehe des Bogens (normiert) aus der Gesamtflugzeit: Lob bei grossem Abstand.
static func arc_for(gap_ms: float) -> float:
	return clampf(gap_ms * 0.00016, 0.03, 0.28)


static func _bez(y0: float, y1: float, s: float, arc: float) -> float:
	return lerpf(y0, y1, s) - 4.0 * arc * s * (1.0 - s)


## Ball zwischen Gegnerschlag m und Ankunft bei Schlag j (t > t_j: faellt weiter
## am Schlaeger vorbei). Gueltig ab t = shots[j].m.
static func pos_in(shots: Array[Shot], j: int, t: float) -> Vector2:
	var s := shots[j]
	var span := maxf(s.t - s.m, 1.0)
	var u := (t - s.m) / span
	var x := lerpf(X_OPP, X_PLAYER, u)
	var gap := span if s.serve else span * 2.0
	var a := arc_for(gap)
	var y_h := hit_y(s.key)
	var fb := F_BOUNCE_ME
	var y := 0.0
	if u < fb:
		y = _bez(Y_OPP, Y_TABLE, u / fb, a * 0.4)
	else:
		y = _bez(Y_TABLE, y_h, (u - fb) / (1.0 - fb), a)
	return Vector2(x, y)


## Zeit des Aufpralls auf der Tischhaelfte des Spielers vor Schlag j.
static func bounce_me_time(shots: Array[Shot], j: int) -> float:
	var s := shots[j]
	return s.m + (s.t - s.m) * F_BOUNCE_ME


## Ball nach Schlag i (Loslassen end) bis zum Gegner. Zeit t in [end, out_end].
static func pos_out(shots: Array[Shot], i: int, t: float) -> Vector2:
	var s := shots[i]
	var m_next := out_end(shots, i)
	var span := maxf(m_next - s.end, 1.0)
	var u := (t - s.end) / span
	var x := lerpf(X_PLAYER, X_OPP, u)
	var a := arc_for(span * 2.0)
	var fb := F_BOUNCE_OPP
	var y := 0.0
	if u < fb:
		y = _bez(hit_y(s.key), Y_TABLE, u / fb, a * 0.5)
	else:
		y = _bez(Y_TABLE, Y_OPP, (u - fb) / (1.0 - fb), a)
	return Vector2(x, y)


## Ende des Ausflugs nach Schlag i: Gegnerschlag des naechsten Schlags oder EXIT_MS.
static func out_end(shots: Array[Shot], i: int) -> float:
	if i + 1 < shots.size() and not shots[i + 1].serve:
		return shots[i + 1].m
	return shots[i].end + EXIT_MS


static func bounce_opp_time(shots: Array[Shot], i: int) -> float:
	var s := shots[i]
	return s.end + (out_end(shots, i) - s.end) * F_BOUNCE_OPP


## Erster Schlag mit t >= time (binaere Suche), shots.size() wenn keiner.
static func first_at_or_after(shots: Array[Shot], time: float) -> int:
	var lo := 0
	var hi := shots.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if shots[mid].t < time:
			lo = mid + 1
		else:
			hi = mid
	return lo


# ---------------------------------------------------------------------------
# Sterne 0..15
# ---------------------------------------------------------------------------

const STAR_HOP_MS := 1000.0
const STAR_DENS_K := 0.62
const STAR_DECAY := 0.95
const STAR_SWITCH_W := 0.45
const STAR_SWITCH_GAP_MS := 450.0
const STAR_SMASH_W := 0.7
const STAR_CHARGE_W := 0.45
const STAR_MAX := 15.0
const STAR_KNEE := 9.0
const STAR_STRETCH := 0.7


## Sterne: je 2-s-Fenster Last (Schlaege/s; Tastenwechsel, Schmetterbaelle und
## Aufladen zaehlen extra), die haertesten Fenster zaehlen am meisten.
static func stars(shots: Array[Shot]) -> float:
	if shots.size() < 2:
		return 0.0
	var t0 := shots[0].t
	var t_end := shots[-1].end
	var n_win := maxi(1, int(ceil((t_end - t0) / STAR_HOP_MS)))
	var load_w := PackedFloat32Array()
	load_w.resize(n_win)
	load_w.fill(0.0)
	var last_key := -1
	var last_t := -INF
	for s in shots:
		var w := clampi(int((s.t - t0) / STAR_HOP_MS), 0, n_win - 1)
		var x := 1.0
		if last_key >= 0 and s.key != last_key and s.t - last_t < STAR_SWITCH_GAP_MS:
			x += STAR_SWITCH_W
		if s.smash:
			x += STAR_SMASH_W
		if s.is_charge():
			x += STAR_CHARGE_W
		load_w[w] += x
		last_key = s.key
		last_t = s.t
	var vals: Array[float] = []
	for w in n_win:
		var lw := load_w[w] + (load_w[w - 1] if w > 0 else 0.0)
		var per_s := lw / (2.0 * STAR_HOP_MS / 1000.0)
		vals.append(STAR_DENS_K * pow(per_s, 1.15))
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
	var raw := num / maxf(den, 1e-6)
	if raw > STAR_KNEE:
		raw = STAR_KNEE + (raw - STAR_KNEE) * STAR_STRETCH
	return clampf(raw, 0.0, STAR_MAX)
