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
## Takt: Notes so nah an einem Schlag zaehlen als "auf dem Schlag".
const BEAT_SNAP_MS := 12.0
## Spruenge ab JUMP_DEG nur auf Schlaegen (beat_strength >= STRONG_BEAT);
## sonst wird der Sprung auf WEAK_JUMP_DEG gedeckelt.
const JUMP_DEG := 60.0
const STRONG_BEAT := 0.5
const WEAK_JUMP_DEG := 50.0
## Orbit-Sterne: Fensterraster und Gewichte (an Mania-Sternen grob geeicht).
const STAR_HOP_MS := 1000.0
const STAR_DENS_K := 0.32
const STAR_PATH_K := 0.29


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

	var reds := red_points(beatmap)
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
			# Grosse Spruenge nur auf Schlaegen; dazwischen bleibt der Fluss ruhig.
			if absf(delta) >= JUMP_DEG and beat_strength(reds, t) < STRONG_BEAT:
				delta = signf(delta) * WEAK_JUMP_DEG
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



# ---------------------------------------------------------------------------
# Takt, Analyse, Orbit-Sterne
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


## Gewicht der Taktstelle t: 1 = Taktanfang, 0,75 = Halbtakt, 0,6 = Schlag,
## 0,35 = Achtel, 0,2 = sonst. Ohne Timing-Points immer 1 (keine Regel).
static func beat_strength(reds: Array, t: float) -> float:
	if reds.is_empty():
		return 1.0
	var tp = reds[0]
	for r in reds:
		if float(r.time) <= t + BEAT_SNAP_MS:
			tp = r
		else:
			break
	var bl: float = tp.beat_length
	var meter: int = maxi(int(tp.meter), 1)
	var ph := (t - float(tp.time)) / bl
	var beat := roundf(ph)
	if absf(ph - beat) * bl <= BEAT_SNAP_MS:
		var in_bar := posmod(int(beat), meter)
		if in_bar == 0:
			return 1.0
		if meter % 2 == 0 and in_bar == meter / 2:
			return 0.75
		return 0.6
	var half := roundf(ph * 2.0)
	if absf(ph * 2.0 - half) * bl * 0.5 <= BEAT_SNAP_MS:
		return 0.35
	return 0.2


## Cursor-Punkte (Kopf-Zeit/Winkel, Bogen-Enden), Akkorde zusammengefasst.
static func cursor_points(ns: Array[OrbitNote]) -> Array:
	var pts: Array = []
	for n in ns:
		if pts.is_empty() or absf(float(pts[-1][0]) - n.time_ms) > CHORD_EPS_MS or pts[-1][2]:
			pts.append([n.time_ms, n.angle_deg, false])
		if n.is_arc:
			pts.append([n.end_ms, OrbitNote.wrap_deg(n.end_angle_deg), true])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	return pts


## Kennzahlen eines umgewandelten Musters (Tests, Bericht).
static func analyze(ns: Array[OrbitNote], beatmap: Beatmap = null) -> Dictionary:
	var reds := red_points(beatmap)
	var a := {"arcs": 0, "chords": 0, "nps": 0.0, "jumps": 0, "weak_jumps": 0,
		"reversal": 0.0, "mean_speed": 0.0, "p95_speed": 0.0}
	if ns.is_empty():
		return a
	for i in ns.size():
		if ns[i].is_arc:
			a.arcs += 1
		if i > 0 and absf(ns[i].time_ms - ns[i - 1].time_ms) <= CHORD_EPS_MS:
			a.chords += 1
	var span := maxf(ns[-1].time_ms - ns[0].time_ms, 1000.0)
	a.nps = float(ns.size()) / (span / 1000.0)
	var pts := cursor_points(ns)
	var speeds := PackedFloat32Array()
	var moves := 0
	var flips := 0
	var last_sign := 0.0
	for i in range(1, pts.size()):
		var dt: float = pts[i][0] - pts[i - 1][0]
		if dt <= CHORD_EPS_MS:
			continue
		var d := OrbitNote.delta_deg(pts[i - 1][1], pts[i][1])
		speeds.append(absf(d) / dt)
		if not pts[i][2] and absf(d) >= JUMP_DEG:
			a.jumps += 1
			if beat_strength(reds, pts[i][0]) < STRONG_BEAT:
				a.weak_jumps += 1
		if absf(d) >= 3.0 and not pts[i][2] and not pts[i - 1][2]:
			moves += 1
			if last_sign != 0.0 and signf(d) != last_sign:
				flips += 1
			last_sign = signf(d)
	if not speeds.is_empty():
		var sum := 0.0
		for v in speeds:
			sum += v
		a.mean_speed = sum / float(speeds.size())
		var sorted := speeds.duplicate()
		sorted.sort()
		a.p95_speed = sorted[int(float(sorted.size() - 1) * 0.95)]
	a.reversal = float(flips) / float(maxi(moves, 1))
	return a


## Orbit-Sterne (eigene Zahl, nicht Mania-Sterne): Fenster von 2 s,
## Dichte (Ziele/s, Akkord-Zweitziel 0,5) plus Winkelweg (Grad/ms); die
## haertesten Fenster zaehlen am meisten (Gewicht 0,9^k wie osu!).
static func stars(ns: Array[OrbitNote]) -> float:
	if ns.size() < 2:
		return 0.0
	var pts := cursor_points(ns)
	var t0 := ns[0].time_ms
	var t_end := ns[-1].end_ms
	var n_win := maxi(1, int(ceil((t_end - t0) / STAR_HOP_MS)))
	var dens := PackedFloat32Array()
	var path := PackedFloat32Array()
	dens.resize(n_win)
	path.resize(n_win)
	dens.fill(0.0)
	path.fill(0.0)
	for i in ns.size():
		var w := clampi(int((ns[i].time_ms - t0) / STAR_HOP_MS), 0, n_win - 1)
		var chord := i > 0 and absf(ns[i].time_ms - ns[i - 1].time_ms) <= CHORD_EPS_MS
		dens[w] += 0.5 if chord else 1.0
	for i in range(1, pts.size()):
		var w := clampi(int((float(pts[i][0]) - t0) / STAR_HOP_MS), 0, n_win - 1)
		path[w] += OrbitNote.dist_deg(pts[i - 1][1], pts[i][1])
	# Fenster = zwei Hops (2 s), Werte je Sekunde.
	var vals: Array[float] = []
	for w in n_win:
		var dn := dens[w] + (dens[w - 1] if w > 0 else 0.0)
		var pa := path[w] + (path[w - 1] if w > 0 else 0.0)
		var nps := dn / (2.0 * STAR_HOP_MS / 1000.0)
		var dps := pa / (2.0 * STAR_HOP_MS / 1000.0)
		vals.append(STAR_DENS_K * pow(nps, 0.8) + STAR_PATH_K * dps / 100.0)
	vals.sort()
	vals.reverse()
	var num := 0.0
	var den := 0.0
	var wt := 1.0
	for v in vals:
		num += v * wt
		den += wt
		wt *= 0.9
		if wt < 0.001:
			break
	return num / maxf(den, 1e-6)
