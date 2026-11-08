class_name OrbitConverter
extends RefCounted

## Wandelt eine osu!mania-Map (beliebige Spaltenzahl, gedacht fuer 4K) oder
## eine osu!standard-Map (Mode 0, convert_std: Winkel = Richtung der Position
## zur Mitte, Ring = Abstand) in Orbit-Ziele um. Komplett deterministisch: kein Zufall, nur Spalten,
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
## Ein Finger pro Ring: zwei Ziele auf DEMSELBEN Ring brauchen mindestens so
## viel Abstand (Tap zu Tap); schnellere Folgen wechseln den Ring oder entfallen.
const SAME_RING_MIN_MS := 90.0
## Zeiger-Grenzen (Tablet/Maus): innerhalb von FLICK_WINDOW_MS hoechstens
## MAX_JUMP_DEG, unter SHORT_GAP_MS hoechstens SHORT_JUMP_DEG.
const FLICK_WINDOW_MS := 250.0
const SHORT_GAP_MS := 150.0
const SHORT_JUMP_DEG := 90.0
## Takt: Notes so nah an einem Schlag zaehlen als "auf dem Schlag".
const BEAT_SNAP_MS := 12.0
## Spruenge ab JUMP_DEG nur auf Schlaegen (beat_strength >= STRONG_BEAT);
## sonst wird der Sprung auf WEAK_JUMP_DEG gedeckelt.
const JUMP_DEG := 60.0
const STRONG_BEAT := 0.5
const WEAK_JUMP_DEG := 50.0
## Orbit-Sterne: Fensterraster und Gewichte (am menschlichen QA-Bot geeicht).
## Menschliche Erreichbarkeit (Messung: docs/modes/orbit_qa.md): ein Zeiger mit
## HUMAN_DEG_PER_MS (Maus ~250 Grad/s) faehrt vom letzten Ziel zum naechsten;
## das Ziel liegt hoechstens HUMAN_REACH_DEG neben der so erreichbaren Stelle
## (22 Grad Toleranz minus 2 sigma Zielstreuung). Gilt dauerhaft, nicht nur je
## Schritt: der Rueckstand des Zeigers waechst in Streams nicht an.
const HUMAN_DEG_PER_MS := 0.25
const HUMAN_REACH_DEG := 10.0
## Aus = alte Regeln ohne Erreichbarkeit (nur fuer Vorher/Nachher-Messungen).
static var human_reach := true
const STAR_HOP_MS := 1000.0
const STAR_DENS_K := 0.1
const STAR_PATH_K := 1.0
## Zugtempo-Gewicht im Wegterm: (Tempo / HUMAN_DEG_PER_MS)^2, gekappt bei
## STAR_SPEED_CAP. Schnelle Zuege fordern den Zeiger, langsame kaum (QA:
## Rangkorrelation zum Maus-Bot 0,56 -> 0,76, docs/modes/orbit_qa.md).
const STAR_SPEED_CAP := 2.0
const STAR_DECAY := 0.95

# --- osu!standard (Mode 0), Details in docs/modes/orbit_sources.md ---
## FLOW: osu-Wege werden Ring-Wege (Abstand -> Winkel, Drehsinn des Musters
## -> Drehrichtung). POLAR: Winkel = Richtung der Position zur Mitte.
enum StdStyle { FLOW, POLAR }
## Standard POLAR (Messung + Begruendung: docs/modes/orbit_sources.md);
## umschaltbar fuer Messungen.
static var std_style: int = StdStyle.POLAR
const STD_CENTER := Vector2(256.0, 192.0)
## FLOW: Grad Ringweg pro osu-Pixel Weg.
const STD_DEG_PER_PX := 0.45
## Kleinere Wege (Stacks, Doppel) bleiben auf der Stelle.
const STD_STACK_PX := 12.0
## Wende: Bewegung kehrt um (Winkel zwischen zwei Wegen > ~130 Grad).
const STD_REVERSE_DOT := -0.64
## Drehsinn nur bei deutlicher Kurve uebernehmen (|sin| zwischen zwei Wegen).
const STD_TURN_SIN := 0.35
## POLAR: Positionen so nah an der Mitte haben keine verlaessliche Richtung.
const STD_DEAD_PX := 48.0
## Ring aus dem Abstand zur Mitte: innen unter SPLIT - HYST, aussen ueber
## SPLIT + HYST, dazwischen bleibt der Ring.
const STD_RING_SPLIT_PX := 150.0
const STD_RING_HYST_PX := 25.0


static func convert(beatmap: Beatmap) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	if beatmap == null:
		return out
	if beatmap.mode() == 0:
		return convert_std(beatmap, std_style)
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
	var ring_last := [-INF, -INF]
	var vc := INF  # virtueller Zeiger (HUMAN_DEG_PER_MS), INF = noch keiner
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
			vc = last_angle
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
			if free < 0 or t - float(ring_last[free]) < SAME_RING_MIN_MS or t - float(arc_end_at[free]) < RELEASE_GAP_MS:
				continue
			out.append(OrbitNote.make(t, tip, free, g[0]))
			ring_last[free] = t
			last_head = t
			continue

		var col := head.column
		var gap := t - last_time
		var dir_before := dir
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
		var angle := OrbitNote.wrap_deg(last_angle + delta)
		var reach := _reach(vc, gap, angle)
		angle = reach[0]
		if prev_col >= 0:
			delta = OrbitNote.delta_deg(last_angle, angle)
		if delta != 0.0:
			dir = signf(delta)

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
		# Ein Finger pro Ring: zu schnelle Wiederholung wechselt den Ring
		# (Einzelziel) oder entfaellt; Akkorde schrumpfen auf das freie Ziel.
		var spaced: Array = []
		for tg in kept:
			var r := int(tg[1])
			if _ring_free(ring_last, arc_end_at, r, t):
				spaced.append(tg)
			elif kept.size() == 1 and _ring_free(ring_last, arc_end_at, 1 - r, t):
				tg[1] = 1 - r
				spaced.append(tg)
		if spaced.is_empty():
			dir = dir_before
			continue
		targets = spaced

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
			ring_last[tg[1]] = t
		last_time = t
		last_angle = angle
		last_head = t
		vc = reach[1]
		prev_col = col
		last_ring = int(targets[0][1]) if targets.size() == 1 else -1
	out.sort_custom(func(a: OrbitNote, b: OrbitNote) -> bool:
		if a.time_ms != b.time_ms:
			return a.time_ms < b.time_ms
		return a.ring < b.ring)
	return out


## Menschliche Erreichbarkeit: der virtuelle Zeiger vc faehrt in gap ms mit
## HUMAN_DEG_PER_MS Richtung want; das Ziel bleibt hoechstens HUMAN_REACH_DEG
## vor ihm. Rueckgabe [Zielwinkel, neuer Zeigerwinkel] (beide 0..360).
static func _reach(vc: float, gap: float, want: float) -> Array:
	if vc == INF or gap == INF or not human_reach:
		return [OrbitNote.wrap_deg(want), OrbitNote.wrap_deg(want)]
	var d := OrbitNote.delta_deg(vc, want)
	var lim := HUMAN_DEG_PER_MS * gap
	var mv := clampf(d, -lim, lim)
	var rest := clampf(d - mv, -HUMAN_REACH_DEG, HUMAN_REACH_DEG)
	return [OrbitNote.wrap_deg(vc + mv + rest), OrbitNote.wrap_deg(vc + mv)]


## Ring r ist zur Zeit t frei: genug Abstand zum letzten Tap und zum letzten Bogen-Ende.
static func _ring_free(ring_last: Array, arc_end_at: Array, r: int, t: float) -> bool:
	return t - float(ring_last[r]) >= SAME_RING_MIN_MS and t - float(arc_end_at[r]) >= RELEASE_GAP_MS


## osu!standard -> Orbit. Gleiche Grenzen wie bei Mania: Zeit = Originalzeit,
## MIN_GAP_MS, MAX_DEG_PER_MS/MAX_JUMP_DEG, Spruenge nur auf Schlaegen, ein
## Finger pro Ring (SAME_RING_MIN_MS, RELEASE_GAP_MS), Boegen <= ARC_DEG_PER_MS
## und ARC_MAX_DEG. Kreis -> Tap, Slider -> Bogen (Winkelweg aus dem Pfad),
## Spinner -> Bogen in Flussrichtung.
static func convert_std(beatmap: Beatmap, style: int = StdStyle.POLAR) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	if beatmap == null:
		return out
	var objs := beatmap.hit_objects
	var src: Array[int] = []
	for i in objs.size():
		if not (objs[i] is ManiaNote):
			src.append(i)
	src.sort_custom(func(a: int, b: int) -> bool:
		if objs[a].time != objs[b].time:
			return objs[a].time < objs[b].time
		return a < b)
	var reds := red_points(beatmap)
	var last_time := -INF
	var last_angle := 0.0
	var last_head := -INF
	var dir := 1.0
	var last_ring := -1
	var rad_ring := -1
	var arc: OrbitNote = null
	var arc_end_at := [-INF, -INF]
	var ring_last := [-INF, -INF]
	var prev_pos := Vector2.INF
	var prev_vec := Vector2.ZERO
	var vc := INF
	for i in src:
		var o: HitObject = objs[i]
		var t := o.time
		if arc != null and t > arc.end_ms + CHORD_EPS_MS:
			arc_end_at[arc.ring] = arc.end_ms
			last_time = arc.end_ms
			last_angle = OrbitNote.wrap_deg(arc.end_angle_deg)
			vc = last_angle
			arc = null
		if t - last_head < MIN_GAP_MS:
			continue
		var pos := STD_CENTER if o.kind == HitObject.Kind.SPINNER else o.position()
		if arc != null:
			# Ueberlappung (selten): Tap auf dem freien Ring an der Bogen-Spitze.
			var fr := 1 - arc.ring
			if _ring_free(ring_last, arc_end_at, fr, t):
				out.append(OrbitNote.make(t, arc.angle_at(t), fr, i))
				ring_last[fr] = t
				last_head = t
			continue
		var gap := t - last_time
		var dir_before := dir
		var vec_before := prev_vec
		var want := 0.0
		var first := prev_pos == Vector2.INF
		if first:
			last_angle = _polar_deg(pos) if pos.distance_to(STD_CENTER) >= STD_DEAD_PX else 0.0
		elif style == StdStyle.POLAR:
			if pos.distance_to(STD_CENTER) >= STD_DEAD_PX:
				want = OrbitNote.delta_deg(last_angle, _polar_deg(pos))
		elif o.kind != HitObject.Kind.SPINNER:
			var v := pos - prev_pos
			if v.length() >= STD_STACK_PX:
				dir = _flow_dir(prev_vec, v, dir)
				want = dir * v.length() * STD_DEG_PER_PX
				prev_vec = v
			elif gap >= DRIFT_GAP_MS:
				want = dir * COL_STEP_DEG
		if not first:
			var lim := minf(MAX_JUMP_DEG, MAX_DEG_PER_MS * gap)
			var delta := clampf(want, -lim, lim)
			if absf(delta) >= JUMP_DEG and beat_strength(reds, t) < STRONG_BEAT:
				delta = signf(delta) * WEAK_JUMP_DEG
			var reached: Array = _reach(vc, gap, OrbitNote.wrap_deg(last_angle + delta))
			delta = OrbitNote.delta_deg(last_angle, reached[0])
			if style == StdStyle.POLAR and delta != 0.0:
				dir = signf(delta)
			want = delta
		var angle := OrbitNote.wrap_deg(last_angle + want)
		var vc_new: float = _reach(vc, gap, angle)[1]

		# Ring: Abstand zur Mitte (mit Hysterese), Streams wechseln ab.
		var rd := pos.distance_to(STD_CENTER)
		var rad_before := rad_ring
		if rad_ring < 0:
			rad_ring = 0 if rd < STD_RING_SPLIT_PX else 1
		elif rd < STD_RING_SPLIT_PX - STD_RING_HYST_PX:
			rad_ring = 0
		elif rd > STD_RING_SPLIT_PX + STD_RING_HYST_PX:
			rad_ring = 1
		var ring := rad_ring
		if gap < STREAM_GAP_MS and last_ring >= 0:
			ring = 1 - last_ring
		if not _ring_free(ring_last, arc_end_at, ring, t):
			ring = 1 - ring
			if not _ring_free(ring_last, arc_end_at, ring, t):
				dir = dir_before
				prev_vec = vec_before
				rad_ring = rad_before
				continue

		var dur := o.end_time() - t
		var on: OrbitNote
		var end_pos := pos
		if o.kind == HitObject.Kind.SLIDER and dur >= MIN_ARC_MS:
			var sl := o as HitSlider
			var pts := sl.path_points()
			var fwd := sl.curve_end() if pts.size() >= 2 else pos
			end_pos = fwd if sl.slides % 2 == 1 else pos
			var span := 0.0
			if style == StdStyle.POLAR:
				span = _path_polar_span(pts) * float(sl.slides)
			else:
				var mv := fwd - pos
				if mv.length() >= STD_STACK_PX:
					dir = _flow_dir(prev_vec, mv, dir)
					prev_vec = mv if sl.slides % 2 == 1 else -mv
				span = dir * _path_len(pts) * float(sl.slides) * STD_DEG_PER_PX
			var cap := minf(ARC_MAX_DEG, ARC_DEG_PER_MS * dur)
			span = clampf(span, -cap, cap)
			on = OrbitNote.make_arc(t, o.end_time(), angle, span, ring, i)
		elif o.kind == HitObject.Kind.SPINNER and dur >= MIN_ARC_MS:
			on = OrbitNote.make_arc(t, o.end_time(), angle,
					dir * minf(ARC_MAX_DEG, ARC_DEG_PER_MS * dur), ring, i)
			prev_vec = Vector2.ZERO
		else:
			on = OrbitNote.make(t, angle, ring, i)
		out.append(on)
		ring_last[ring] = t
		if on.is_arc:
			arc = on
		last_time = t
		last_angle = angle
		last_head = t
		vc = vc_new
		last_ring = ring
		prev_pos = end_pos
	out.sort_custom(func(a: OrbitNote, b: OrbitNote) -> bool:
		if a.time_ms != b.time_ms:
			return a.time_ms < b.time_ms
		return a.ring < b.ring)
	return out


## Orbit-Winkel einer osu-Position (0 = oben, im Uhrzeigersinn).
static func _polar_deg(p: Vector2) -> float:
	var d := p - STD_CENTER
	return OrbitNote.wrap_deg(rad_to_deg(atan2(d.x, -d.y)))


## Drehrichtung fuer den Weg v nach dem Weg prev: Umkehr (spitzer Winkel)
## kehrt um, deutliche Kurve uebernimmt den Drehsinn des Musters (osu-y zeigt
## nach unten, Kreuzprodukt > 0 = im Uhrzeigersinn), sonst bleibt sie.
static func _flow_dir(prev: Vector2, v: Vector2, dir: float) -> float:
	if prev.length() < 0.001 or v.length() < 0.001:
		return dir
	var a := prev.normalized()
	var b := v.normalized()
	if a.dot(b) <= STD_REVERSE_DOT:
		return -dir
	var cr := a.cross(b)
	if absf(cr) >= STD_TURN_SIN:
		return signf(cr)
	return dir


static func _path_len(pts: PackedVector2Array) -> float:
	var s := 0.0
	for k in range(1, pts.size()):
		s += pts[k].distance_to(pts[k - 1])
	return s


## Vorzeichenbehafteter Winkelweg eines Slider-Pfads um die Mitte (ein Durchlauf).
static func _path_polar_span(pts: PackedVector2Array) -> float:
	var s := 0.0
	for k in range(1, pts.size()):
		if pts[k].distance_to(STD_CENTER) < STD_DEAD_PX or pts[k - 1].distance_to(STD_CENTER) < STD_DEAD_PX:
			continue
		s += OrbitNote.delta_deg(_polar_deg(pts[k - 1]), _polar_deg(pts[k]))
	return s


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


## Spielbarkeits-Pruefung (2 Tasten + Zeiger). Zaehlt Verstoesse gegen die
## Grenzen dieser Datei; alle Zaehler muessen 0 sein.
##  timing: Zielzeit weicht mehr als CHORD_EPS_MS von ihrer Quell-Note ab
##  speed: Zeigerwinkel-Tempo > MAX_DEG_PER_MS
##  flick: Sprung > MAX_JUMP_DEG in FLICK_WINDOW_MS oder > SHORT_JUMP_DEG
##         unter SHORT_GAP_MS
##  ring: gleicher Ring zu dicht (Tap < SAME_RING_MIN_MS, nach Bogen
##         < RELEASE_GAP_MS) oder Druck waehrend ein Bogen den Ring haelt
##  chord: gleichzeitige Ziele nicht am selben Winkel
static func violations(ns: Array[OrbitNote], beatmap: Beatmap) -> Dictionary:
	var v := {"timing": 0, "speed": 0, "flick": 0, "ring": 0, "chord": 0, "targets": ns.size()}
	if beatmap == null:
		return v
	for n in ns:
		if n.source_index >= 0 and n.source_index < beatmap.hit_objects.size():
			if absf(float(beatmap.hit_objects[n.source_index].time) - n.time_ms) > CHORD_EPS_MS + 0.001:
				v.timing += 1
			elif n.is_arc and absf(float(beatmap.hit_objects[n.source_index].end_time()) - n.end_ms) > CHORD_EPS_MS + 0.001:
				v.timing += 1
	var pts := cursor_points(ns)
	for i in range(1, pts.size()):
		var dt: float = pts[i][0] - pts[i - 1][0]
		var d := OrbitNote.dist_deg(pts[i - 1][1], pts[i][1])
		if dt <= CHORD_EPS_MS:
			# Gleichzeitig = gleicher Winkel (Toleranz: Bogenlauf waehrend dt).
			if d > ARC_DEG_PER_MS * dt + 0.01:
				v.chord += 1
			continue
		if d / dt > MAX_DEG_PER_MS + 0.0005:
			v.speed += 1
		if (dt <= FLICK_WINDOW_MS and d > MAX_JUMP_DEG + 0.01) 				or (dt < SHORT_GAP_MS and d > SHORT_JUMP_DEG + 0.01):
			v.flick += 1
	for r in 2:
		var free_at := -INF
		var was_arc := false
		var last_t := -INF
		for n in ns:
			if n.ring != r:
				continue
			var need := RELEASE_GAP_MS - 0.001 if was_arc else SAME_RING_MIN_MS - 0.001
			if n.time_ms - free_at < need or n.time_ms < last_t:
				v.ring += 1
			last_t = n.time_ms
			free_at = n.end_ms if n.is_arc else n.time_ms
			was_arc = n.is_arc
	return v


## Kennzahlen eines umgewandelten Musters (Tests, Bericht).
static func analyze(ns: Array[OrbitNote], beatmap: Beatmap = null) -> Dictionary:
	var reds := red_points(beatmap)
	var a := {"arcs": 0, "chords": 0, "nps": 0.0, "jumps": 0, "weak_jumps": 0,
		"reversal": 0.0, "mean_speed": 0.0, "p95_speed": 0.0, "on_beat": 0.0, "on_half": 0.0}
	if ns.is_empty():
		return a
	# Takt-Passung: Anteil der Ziele auf Schlaegen (>= 0,6) bzw. Halbschlaegen.
	var on_b := 0
	var on_h := 0
	for n in ns:
		var bs := beat_strength(reds, n.time_ms)
		on_b += 1 if bs >= 0.6 else 0
		on_h += 1 if bs >= 0.35 else 0
	a.on_beat = float(on_b) / float(ns.size())
	a.on_half = float(on_h) / float(ns.size())
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
## Dichte (Ziele/s, Akkord-Zweitziel 0,5) plus Winkelweg je Sekunde, jeder
## Zug gewichtet mit seinem Tempo (siehe STAR_SPEED_CAP); die haertesten
## Fenster zaehlen am meisten (Gewicht STAR_DECAY^k).
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
		var d := OrbitNote.dist_deg(pts[i - 1][1], pts[i][1])
		var gap := maxf(float(pts[i][0]) - float(pts[i - 1][0]), 1.0)
		var f := minf(d / gap / HUMAN_DEG_PER_MS, STAR_SPEED_CAP)
		path[w] += d * f * f
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
		wt *= STAR_DECAY
		if wt < 0.001:
			break
	return num / maxf(den, 1e-6)
