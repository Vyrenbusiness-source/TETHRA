class_name OrbitConverter
extends RefCounted

## Wandelt eine osu!mania-Map (beliebige Spaltenzahl, gedacht fuer 4K) in
## Orbit-Ziele um. Komplett deterministisch: kein Zufall, nur Spalten,
## Zeitabstaende und der bisherige Musterfluss bestimmen das Ergebnis.
##
## Regeln (Details + Begruendung in docs/modes/orbit.md):
##  1. Akkord = Notes mit <= CHORD_EPS_MS Abstand. Ein Akkord ergibt hoechstens
##     ZWEI Ziele: beide Ringe am selben Winkel (niedrigste Spalte innen,
##     hoechste aussen). Derselbe Ring nebeneinander wird nicht erzeugt, weil
##     ein Tastendruck nur ein Ziel treffen kann.
##  2. Dichte-Reduktion: ein Akkord, der weniger als MIN_GAP_MS nach dem
##     letzten behaltenen Akkord kommt, wird verworfen (Jacks/Streams/Bursts
##     schneller als 1/4 bei 200 BPM werden zusammengefasst).
##  3. Winkel: Spalten liegen gedanklich auf einem Kreis. Der kreisfoermige
##     Spaltenabstand d (bei 4K -1..+2) mal Schrittweite ergibt den
##     Winkelsprung; die Schrittweite waechst mit dem Zeitabstand (kleine
##     Abstaende = kleine Spruenge, grosse Abstaende duerfen springen). Jeder
##     Sprung ist auf MAX_DEG_PER_MS * Abstand und MAX_JUMP_DEG gedeckelt.
##     Rolls (0123 0123) drehen so gleichmaessig im Kreis, Trills pendeln,
##     Jacks bleiben stehen.
##  4. Ring: Einzelnoten im Stream (Abstand < STREAM_GAP_MS) wechseln den Ring
##     (Tasten abwechseln wie beim Trillern), sonst entscheidet die
##     Spaltenhaelfte (linke Haelfte innen, rechte aussen).
##  5. LN -> Bogen: Winkellaenge = Dauer * ARC_DEG_PER_MS, gedeckelt auf
##     ARC_MAX_DEG, Richtung = aktuelle Flussrichtung. LNs < MIN_ARC_MS werden
##     Taps. Waehrend ein Bogen laeuft, werden neue Notes Taps auf dem freien
##     Ring genau an der Bogen-Spitze (Cursor ist ja dort), sonst verworfen.

const CHORD_EPS_MS := 2.0
const MIN_GAP_MS := 75.0
## Maximale Winkelgeschwindigkeit zwischen zwei Cursor-Punkten (Grad/ms).
const MAX_DEG_PER_MS := 0.6
const MAX_JUMP_DEG := 150.0
const COL_STEP_DEG := 24.0
const REF_GAP_MS := 150.0
const MAX_STEP_SCALE := 2.5
## Jacks mit mindestens diesem Abstand wandern um einen Schritt weiter.
const DRIFT_GAP_MS := 300.0
const STREAM_GAP_MS := 160.0
const MIN_ARC_MS := 100.0
const ARC_DEG_PER_MS := 0.12
const ARC_MAX_DEG := 270.0
## Nach einem Bogen-Ende braucht derselbe Ring so viel Pause, sonst anderer Ring.
const RELEASE_GAP_MS := 150.0


static func convert(beatmap: Beatmap) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	if beatmap == null:
		return out
	var objs := beatmap.hit_objects
	var k := maxi(beatmap.column_count(), 1)
	var src: Array[int] = []
	for i in objs.size():
		if objs[i] is ManiaNote:
			src.append(i)
	src.sort_custom(func(a: int, b: int) -> bool:
		var na := objs[a] as ManiaNote
		var nb := objs[b] as ManiaNote
		if na.time != nb.time:
			return na.time < nb.time
		if na.column != nb.column:
			return na.column < nb.column
		return a < b)

	var groups: Array = []
	for i in src:
		var t := objs[i].time
		if not groups.is_empty() and t - objs[groups[-1][0]].time <= CHORD_EPS_MS:
			groups[-1].append(i)
		else:
			groups.append([i])

	var last_time := -INF
	var last_angle := 0.0
	var last_head := -INF
	var dir := 1.0
	var prev_col := -1
	var last_ring := -1
	var arcs: Array = [null, null]
	var arc_end_at := [-INF, -INF]
	for g in groups:
		var head := objs[g[0]] as ManiaNote
		var t := head.time
		# Abgelaufene Boegen freigeben; der zuletzt endende wird Cursor-Punkt.
		var any_active := false
		var ended: OrbitNote = null
		for r in 2:
			var a: OrbitNote = arcs[r]
			if a == null:
				continue
			if t > a.end_ms + CHORD_EPS_MS:
				arcs[r] = null
				arc_end_at[r] = a.end_ms
				if ended == null or a.end_ms > ended.end_ms:
					ended = a
			else:
				any_active = true
		if ended != null and not any_active:
			last_time = ended.end_ms
			last_angle = OrbitNote.wrap_deg(ended.end_angle_deg)
		if t - last_head < MIN_GAP_MS:
			continue
		if any_active:
			var free := -1
			var tip := 0.0
			for r in 2:
				if arcs[r] == null:
					if free < 0:
						free = r
				else:
					tip = (arcs[r] as OrbitNote).angle_at(t)
			if free < 0:
				continue
			out.append(OrbitNote.make(t, tip, free, g[0]))
			last_head = t
			continue

		var col := head.column
		var gap := t - last_time
		var delta := 0.0
		if prev_col >= 0:
			var d := posmod(col - prev_col, k)
			if d * 2 > k:
				d -= k
			var df := float(d)
			if d * 2 == k:
				df = dir * float(d)
			var unit := COL_STEP_DEG * clampf(gap / REF_GAP_MS, 1.0, MAX_STEP_SCALE)
			var lim := minf(MAX_JUMP_DEG, MAX_DEG_PER_MS * gap)
			if d == 0:
				if gap >= DRIFT_GAP_MS:
					delta = dir * minf(COL_STEP_DEG, lim)
			else:
				delta = clampf(df * unit, -lim, lim)
		if delta != 0.0:
			dir = signf(delta)
		var angle := OrbitNote.wrap_deg(last_angle + delta)

		# Ziele des Akkords: [quell-index, ring].
		var targets: Array = []
		if g.size() >= 2:
			targets = [[g[0], 0], [g[-1], 1]]
		else:
			var ring := 0 if col * 2 < k else 1
			if gap < STREAM_GAP_MS and last_ring >= 0:
				ring = 1 - last_ring
			targets = [[g[0], ring]]
		# Ring direkt nach einem Bogen-Ende gesperrt (Taste muss erst hoch).
		var kept: Array = []
		for tg in targets:
			if t - float(arc_end_at[tg[1]]) < RELEASE_GAP_MS:
				if targets.size() == 1:
					tg[1] = 1 - int(tg[1])
					kept.append(tg)
			else:
				kept.append(tg)
		if kept.is_empty():
			# Beide Ringe frisch frei: der laenger freie Ring bekommt das Ziel.
			kept = [[g[0], 0 if float(arc_end_at[0]) <= float(arc_end_at[1]) else 1]]
		targets = kept

		var longest := 0.0
		for tg in targets:
			longest = maxf(longest, _arc_len(objs[tg[0]] as ManiaNote))
		var speed := 0.0
		if longest > 0.0:
			speed = minf(ARC_DEG_PER_MS, ARC_MAX_DEG / longest)
		for tg in targets:
			var n := objs[tg[0]] as ManiaNote
			var dur := _arc_len(n)
			var on: OrbitNote
			if dur > 0.0:
				on = OrbitNote.make_arc(t, t + dur, angle, dir * speed * dur, tg[1], tg[0])
				arcs[tg[1]] = on
			else:
				on = OrbitNote.make(t, angle, tg[1], tg[0])
			out.append(on)
		last_time = t
		last_angle = angle
		last_head = t
		prev_col = col
		last_ring = int(targets[0][1]) if targets.size() == 1 else -1
	out.sort_custom(func(a: OrbitNote, b: OrbitNote) -> bool:
		if a.time_ms != b.time_ms:
			return a.time_ms < b.time_ms
		return a.ring < b.ring)
	return out


## Bogen-Dauer einer Mania-Note (0 = wird Tap).
static func _arc_len(n: ManiaNote) -> float:
	if not n.is_hold:
		return 0.0
	var dur := n.end_time() - n.time
	return dur if dur >= MIN_ARC_MS else 0.0
