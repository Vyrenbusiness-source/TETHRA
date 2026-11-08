class_name OrbitConverter
extends RefCounted

## Wandelt eine osu!mania- oder osu!standard-Map in Bahnen-Ziele um. Komplett
## deterministisch. Jedes Ziel liegt auf der Zeit seiner Quell-Note, sein Winkel
## ist die Taktphase (OrbitClock). Dazu waehlt plan_shapes je Takt die Bahnform
## (Ellipse/Kreis ruhig, Acht/Rose dicht oder Kiai).
##
## Spur (Details: docs/modes/orbit_bahnen.md):
##  - osu!standard nach osu!taiko-Regel: Whistle/Clap = aussen (Taste B), sonst
##    innen (Taste A); Finish = Akzent (beide Ringe am selben Winkel).
##    Slider/Spinner (>= MIN_ARC_MS) werden Halte.
##  - 4K-Mania: Spalten 1-2 innen, 3-4 aussen; Akkord ueber beide Seiten =
##    Akzent; LN = Halte. Andere Spaltenzahlen: linke Haelfte innen, rechte aussen.
## Dichte: je Ring mindestens SAME_RING_MIN_MS zwischen zwei Tasten, nach einem
## Halte RELEASE_GAP_MS, im Halte kein weiteres Ziel auf seinem Ring. Leichte
## Diffs (Sterne < EASY_STARS) bekommen die groeberen EASY_*-Grenzen.

const CHORD_EPS_MS := 2.0
## Zwei Ziele auf demselben Ring (Tap zu Tap): ein Finger pro Taste.
const SAME_RING_MIN_MS := 90.0
## Nach dem Ende eines Haltens bis zum naechsten Ziel auf diesem Ring.
const RELEASE_GAP_MS := 150.0
const MIN_ARC_MS := 100.0
## Laengere Halte werden gekappt (Spinner).
const MAX_HOLD_MS := 6000.0
## Leichte Diffs: Sterne unter EASY_STARS -> groebere Mindestabstaende.
const EASY_STARS := 2.5
const EASY_RING_GAP_MS := 220.0
const EASY_GAP_MS := 150.0

## Orbit-Sterne: Fensterraster und Gewichte (gegen Bot-Messung kalibriert,
## siehe docs/modes/orbit.md "Messwerte").
const STAR_HOP_MS := 1000.0
const STAR_DENS_K := 0.34
const STAR_DECAY := 0.95
## Ringwechsel (Taste A <-> B) zaehlt zusaetzlich, wenn der Abstand klein ist.
const STAR_SWITCH_W := 0.5
const STAR_SWITCH_GAP_MS := 400.0
const STAR_ACCENT_W := 0.4
const STAR_HOLD_W := 0.5
## Kopfgeschwindigkeit, ab der das Folgen anspruchsvoll wird (Bahn-Einheiten/ms):
## Kreis bei 1,5 s/Takt = 0,0033. Folge-Anspruch = (Tempo x Kurvigkeit / Referenz)^2.
const HEAD_REF := 0.0033

## --- Bahnformen: Auswahl je Takt ---
## Schwellen der Last L (Ziele/s im Takt, im Kiai x KIAI_BOOST, geglaettet):
## < SHAPE_L_ELLIPSE Kreis, bis SHAPE_L_EIGHT Ellipse, bis SHAPE_L_ROSE Acht,
## darueber Rose3 oder Acht im Wechsel, ab SHAPE_L_ROSE4 Rose4.
const SHAPE_L_ELLIPSE := 2.0
const SHAPE_L_EIGHT := 3.8
const SHAPE_L_ROSE := 5.8
const SHAPE_L_ROSE4 := 8.5
const KIAI_BOOST := 1.35
## Eine Form haelt mindestens so viele Takte (kein Flackern).
const SHAPE_MIN_HOLD := 4
## Pause: so viele Takte ohne Ziel setzen die Bahn auf den Kreis zurueck.
const SHAPE_REST_BARS := 2
const STAR_FOLLOW_CAP := 2.5
const STAR_FOLLOW_K := 0.9
const STAR_MAX := 15.0
## Streckung oben: Bibliothek liegt roh bei Median 3,7 / p99 5,4 / Max 6,4;
## ab STAR_KNEE wird mit STAR_STRETCH gedehnt, damit 0..15 genutzt wird
## (Median ~3,7, p90 ~8, p99 ~10, Max ~14).
const STAR_KNEE := 3.5
const STAR_STRETCH := 3.5


static func convert(beatmap: Beatmap) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	if beatmap == null:
		return out
	var evs: Array = convert_std_events(beatmap) if beatmap.mode() == 0 \
			else convert_mania_events(beatmap)
	var clock := OrbitClock.from_beatmap(beatmap)
	out = build(evs, clock, SAME_RING_MIN_MS, 0.0)
	plan_shapes(beatmap, out, clock)
	if stars(out) < EASY_STARS:
		out = build(evs, clock, EASY_RING_GAP_MS, EASY_GAP_MS)
		plan_shapes(beatmap, out, clock)
	return out


## Bahn (Uhr + Formplan) zu den umgewandelten Zielen ns einer Map. Dieselbe
## Rechnung wie in convert (deterministisch), Ergebnis steht auch in ns[i].shape.
static func track_for(beatmap: Beatmap, ns: Array[OrbitNote]) -> OrbitTrack:
	return plan_shapes(beatmap, ns, OrbitClock.from_beatmap(beatmap))


## Waehlt je Takt die Bahnform nach Dichte und Kiai und setzt shape/speed der
## Ziele. Wechsel nur auf Takt-Eins; die Form haelt SHAPE_MIN_HOLD Takte; eine
## Form, deren Kopf schneller als erlaubt liefe (OrbitTrack.MAX_SPEED, leichte
## Maps MAX_SPEED_EASY), wird durch die naechst-einfachere ersetzt.
static func plan_shapes(beatmap: Beatmap, ns: Array[OrbitNote], clock: OrbitClock) -> OrbitTrack:
	var tr := OrbitTrack.new()
	tr.clock = clock
	tr.plan = [[-INF, OrbitPath.CIRCLE]]
	if ns.is_empty() or beatmap == null:
		_stamp(tr, ns)
		return tr
	var cap := OrbitTrack.MAX_SPEED_EASY 			if OrbitClock.min_bar_for(beatmap) >= OrbitClock.EASY_MIN_BAR_MS else OrbitTrack.MAX_SPEED
	# Takte von der ersten bis zur letzten Note.
	var starts: Array[float] = []
	var ends: Array[float] = []
	var t := clock.bar_start_at(ns[0].time_ms)
	var t_last := ns[-1].end_ms
	while t <= t_last and starts.size() < 20000:
		var e := clock.bar_end_at(t + 0.5)
		if e <= t + 1.0:
			e = t + 1000.0
		starts.append(t)
		ends.append(e)
		t = e
	var nb := starts.size()
	var count := PackedFloat32Array()
	count.resize(nb)
	count.fill(0.0)
	var b := 0
	for i in ns.size():
		var n := ns[i]
		if i > 0 and absf(n.time_ms - ns[i - 1].time_ms) <= CHORD_EPS_MS:
			continue
		while b < nb - 1 and n.time_ms >= ends[b]:
			b += 1
		count[b] += 1.0
	var raw := PackedFloat32Array()
	raw.resize(nb)
	var kia: Array[bool] = []
	for k in nb:
		var secs := maxf((ends[k] - starts[k]) / 1000.0, 0.2)
		var kk := beatmap.is_kiai((starts[k] + ends[k]) * 0.5)
		kia.append(kk)
		raw[k] = count[k] / secs * (KIAI_BOOST if kk else 1.0)
	var cur := OrbitPath.CIRCLE
	var since := SHAPE_MIN_HOLD
	var changes := 0
	var rest := 0
	for k in nb:
		var prev_v: float = raw[k - 1] if k > 0 else raw[k]
		var next_v: float = raw[k + 1] if k + 1 < nb else raw[k]
		var level := (prev_v + 2.0 * raw[k] + next_v) * 0.25
		rest = rest + 1 if count[k] == 0.0 else 0
		var want := _shape_for_level(level, changes)
		if rest >= SHAPE_REST_BARS:
			want = OrbitPath.CIRCLE
		var full := clock.bar_ms_at(starts[k] + 0.5)
		# Geschwindigkeits-Deckel: zu kurze Takte vertragen nur einfache Formen.
		while want > OrbitPath.CIRCLE and OrbitPath.length(want) / full > cap:
			want -= 1
		var forced := OrbitPath.length(cur) / full > cap
		if want != cur and (since >= SHAPE_MIN_HOLD or forced or rest >= SHAPE_REST_BARS):
			cur = want
			since = 0
			changes += 1
			(tr.plan as Array).append([starts[k], cur])
		since += 1
	_stamp(tr, ns)
	return tr


static func _shape_for_level(level: float, changes: int) -> int:
	if level >= SHAPE_L_ROSE4:
		return OrbitPath.ROSE4
	if level >= SHAPE_L_ROSE:
		return OrbitPath.ROSE3 if changes % 2 == 0 else OrbitPath.EIGHT
	if level >= SHAPE_L_EIGHT:
		return OrbitPath.EIGHT
	if level >= SHAPE_L_ELLIPSE:
		return OrbitPath.ELLIPSE
	return OrbitPath.CIRCLE


static func _stamp(tr: OrbitTrack, ns: Array[OrbitNote]) -> void:
	for n in ns:
		n.shape = tr.shape_at(n.time_ms)
		n.speed = tr.speed_at(n.time_ms)


static func convert_std(beatmap: Beatmap) -> Array[OrbitNote]:
	if beatmap == null:
		return [] as Array[OrbitNote]
	return build(convert_std_events(beatmap), OrbitClock.from_beatmap(beatmap),
			SAME_RING_MIN_MS, 0.0)


static func convert_mania(beatmap: Beatmap) -> Array[OrbitNote]:
	if beatmap == null:
		return [] as Array[OrbitNote]
	return build(convert_mania_events(beatmap), OrbitClock.from_beatmap(beatmap),
			SAME_RING_MIN_MS, 0.0)


## Ereignisse: Array von Gruppen [t, [ [ring, end_ms (0 = Tap), src], ... ]]
## (je Ring hoechstens ein Eintrag), nach Zeit sortiert.
static func convert_mania_events(beatmap: Beatmap) -> Array:
	var objs := beatmap.hit_objects
	var k := maxi(beatmap.column_count(), 1)
	var list: Array = []
	for i in objs.size():
		var n = objs[i]
		if n is ManiaNote:
			var end := 0.0
			if n.is_hold and n.end_time() - n.time >= MIN_ARC_MS:
				end = n.end_time()
			list.append([n.time, 0 if n.column * 2 < k else 1, end, i])
	return _group(list)


static func convert_std_events(beatmap: Beatmap) -> Array:
	var objs := beatmap.hit_objects
	var list: Array = []
	for i in objs.size():
		var o = objs[i]
		if o is ManiaNote:
			continue
		var hs: int = o.hit_sound
		var end := 0.0
		if o.kind != HitObject.Kind.CIRCLE and o.end_time() - o.time >= MIN_ARC_MS:
			end = o.end_time()
		if (hs & 4) != 0 and end == 0.0:
			list.append([o.time, 0, 0.0, i])
			list.append([o.time, 1, 0.0, i])
		else:
			list.append([o.time, 1 if (hs & 10) != 0 else 0, end, i])
	return _group(list)


## Sortiert [t, ring, end, src] und fasst Akkorde (<= CHORD_EPS_MS) zusammen;
## je Ring zaehlt der laengste Halte.
static func _group(list: Array) -> Array:
	list.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[3] < b[3])
	var groups: Array = []
	for e in list:
		if groups.is_empty() or float(e[0]) - float(groups[-1][0]) > CHORD_EPS_MS:
			groups.append([e[0], []])
		var items: Array = groups[-1][1]
		var same := -1
		for j in items.size():
			if items[j][0] == e[1]:
				same = j
		if same < 0:
			items.append([e[1], e[2], e[3]])
		elif float(e[2]) > float(items[same][1]):
			items[same] = [e[1], e[2], e[3]]
	return groups


## Baut die Ziele aus Ereignis-Gruppen: Dichte-Regeln, Winkel aus der Uhr.
## ring_gap: Mindestabstand Tap-zu-Tap je Ring; any_gap > 0: Mindestabstand
## zwischen zwei Gruppen insgesamt (leichte Diffs).
static func build(groups: Array, clock: OrbitClock, ring_gap: float,
		any_gap: float) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var last_t: Array = [-INF, -INF]
	var hold_end: Array = [-INF, -INF]
	var last_any := -INF
	for g in groups:
		var t: float = g[0]
		var keep: Array = []
		for it in g[1]:
			var r: int = it[0]
			if t < float(hold_end[r]) + RELEASE_GAP_MS:
				continue
			if t - float(last_t[r]) < ring_gap:
				continue
			keep.append(it)
		if keep.is_empty():
			continue
		if any_gap > 0.0 and t - last_any < any_gap:
			continue
		var ang := clock.angle_at(t)
		var spd := clock.speed_at(t)
		for it in keep:
			var r: int = it[0]
			var n: OrbitNote
			if float(it[1]) > 0.0:
				var end := minf(float(it[1]), t + MAX_HOLD_MS)
				n = OrbitNote.make_arc(t, end, ang, spd * (end - t), r, it[2])
				hold_end[r] = end
				last_t[r] = end
			else:
				n = OrbitNote.make(t, ang, r, it[2])
				last_t[r] = t
			n.speed = spd
			out.append(n)
		last_any = t
	out.sort_custom(func(a: OrbitNote, b: OrbitNote) -> bool:
		if a.time_ms != b.time_ms:
			return a.time_ms < b.time_ms
		return a.ring < b.ring)
	return out


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


## Spielbarkeits-Pruefung. Zaehlt Verstoesse; alle Zaehler muessen 0 sein.
##  timing: Zielzeit weicht mehr als CHORD_EPS_MS von der Quell-Note ab
##  ring: zwei Ziele auf einem Ring zu dicht (Tap < SAME_RING_MIN_MS, nach einem
##        Halte < RELEASE_GAP_MS) oder ein Ziel mitten im Halte seines Rings
##  angle: Winkel passt nicht zur Taktposition (Abweichung > 0,5 Grad)
##  chord: gleichzeitige Ziele auf demselben Ring oder an verschiedenem Winkel
static func violations(ns: Array[OrbitNote], beatmap: Beatmap) -> Dictionary:
	var v := {"timing": 0, "ring": 0, "angle": 0, "chord": 0, "targets": ns.size()}
	if beatmap == null:
		return v
	var clock := OrbitClock.from_beatmap(beatmap)
	var last_t: Array = [-INF, -INF]
	var hold_end: Array = [-INF, -INF]
	var prev: OrbitNote = null
	for n in ns:
		if n.source_index >= 0 and n.source_index < beatmap.hit_objects.size():
			var src = beatmap.hit_objects[n.source_index]
			if absf(float(src.time) - n.time_ms) > CHORD_EPS_MS + 0.001:
				v.timing += 1
			elif n.is_arc and absf(float(src.end_time()) - n.end_ms) > CHORD_EPS_MS + 0.001 \
					and n.end_ms - n.time_ms < MAX_HOLD_MS - 0.5:
				v.timing += 1
		if OrbitNote.dist_deg(n.angle_deg, clock.angle_at(n.time_ms)) > 0.5:
			v.angle += 1
		if prev != null and n.time_ms - prev.time_ms <= CHORD_EPS_MS:
			if n.ring == prev.ring or OrbitNote.dist_deg(n.angle_deg, prev.angle_deg) > 0.5:
				v.chord += 1
		else:
			var r := n.ring
			if n.time_ms - float(last_t[r]) < SAME_RING_MIN_MS - 0.001 \
					or n.time_ms < float(hold_end[r]) + RELEASE_GAP_MS - 0.001:
				v.ring += 1
		var r2 := n.ring
		last_t[r2] = n.end_ms if n.is_arc else n.time_ms
		if n.is_arc:
			hold_end[r2] = n.end_ms
		prev = n
	return v


## Kennzahlen eines umgewandelten Musters (Tests, Bericht).
static func analyze(ns: Array[OrbitNote], _beatmap: Beatmap = null) -> Dictionary:
	var a := {"arcs": 0, "chords": 0, "nps": 0.0, "switches": 0, "inner": 0,
		"outer": 0, "max_speed": 0.0, "shape_changes": 0, "shapes": [0, 0, 0, 0, 0]}
	if ns.is_empty():
		return a
	var last_ring := -1
	for i in ns.size():
		var n := ns[i]
		if n.is_arc:
			a.arcs += 1
		if n.ring == 0:
			a.inner += 1
		else:
			a.outer += 1
		if i > 0 and absf(n.time_ms - ns[i - 1].time_ms) <= CHORD_EPS_MS:
			a.chords += 1
		elif last_ring >= 0 and n.ring != last_ring:
			a.switches += 1
		last_ring = n.ring
		a.max_speed = maxf(a.max_speed, n.speed)
		a.shapes[clampi(n.shape, 0, OrbitPath.COUNT - 1)] += 1
		if i > 0 and n.shape != ns[i - 1].shape:
			a.shape_changes += 1
	var span := maxf(ns[-1].time_ms - ns[0].time_ms, 1000.0)
	a.nps = float(ns.size()) / (span / 1000.0)
	return a


## Orbit-Sterne (eigene Zahl, 0..15): Fenster von 2 s mit
##  Last = Ziele (Akzent-Zweitziel zaehlt STAR_ACCENT_W, Halte STAR_HOLD_W,
##  Ringwechsel unter STAR_SWITCH_GAP_MS STAR_SWITCH_W) je Sekunde,
##  Wert = STAR_DENS_K * Last^0,8 + STAR_FOLLOW_K * Folge * min(nps / 3, 1);
##  Folge = (Kopftempo x Kurvigkeit der Form / HEAD_REF)^2 (gekappt). Die haertesten Fenster
##  zaehlen am meisten (Gewicht STAR_DECAY^k).
static func stars(ns: Array[OrbitNote]) -> float:
	if ns.size() < 2:
		return 0.0
	var t0 := ns[0].time_ms
	var t_end := ns[-1].end_ms
	var n_win := maxi(1, int(ceil((t_end - t0) / STAR_HOP_MS)))
	var load_w := PackedFloat32Array()
	var cnt := PackedFloat32Array()
	var spd := PackedFloat32Array()
	load_w.resize(n_win)
	cnt.resize(n_win)
	spd.resize(n_win)
	load_w.fill(0.0)
	cnt.fill(0.0)
	spd.fill(0.0)
	var last_ring := -1
	var last_time := -INF
	for i in ns.size():
		var n := ns[i]
		var w := clampi(int((n.time_ms - t0) / STAR_HOP_MS), 0, n_win - 1)
		var chord := i > 0 and absf(n.time_ms - ns[i - 1].time_ms) <= CHORD_EPS_MS
		var x := 1.0
		if chord:
			x = STAR_ACCENT_W
		elif last_ring >= 0 and n.ring != last_ring and n.time_ms - last_time < STAR_SWITCH_GAP_MS:
			x += STAR_SWITCH_W
		if n.is_arc:
			x += STAR_HOLD_W
		load_w[w] += x
		cnt[w] += 0.5 if chord else 1.0
		spd[w] = maxf(spd[w], n.speed * float(OrbitPath.CURVE[clampi(n.shape, 0, OrbitPath.COUNT - 1)]))
		if not chord:
			last_ring = n.ring
			last_time = n.time_ms
	var vals: Array[float] = []
	for w in n_win:
		var lw := load_w[w] + (load_w[w - 1] if w > 0 else 0.0)
		var nps := (cnt[w] + (cnt[w - 1] if w > 0 else 0.0)) / (2.0 * STAR_HOP_MS / 1000.0)
		var sp := maxf(spd[w], spd[w - 1] if w > 0 else 0.0)
		var follow := minf(pow(sp / HEAD_REF, 2.0), STAR_FOLLOW_CAP)
		var per_s := lw / (2.0 * STAR_HOP_MS / 1000.0)
		vals.append(STAR_DENS_K * pow(per_s, 0.8) + STAR_FOLLOW_K * follow * minf(nps / 3.0, 1.0))
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
