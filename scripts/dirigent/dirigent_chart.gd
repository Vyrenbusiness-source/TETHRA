class_name DirigentChart
extends RefCounted

## Dirigent: aus einer Map (osu!standard oder Mania) werden Schlaege (Taktfigur)
## und Einsaetze (Tasten A/B) gebaut. Komplett deterministisch, keine Zufallszahlen.
##
## Schlaege (beats): je rotem Timing-Point laufen Beats im Abstand beat_length,
## der Takt faengt am roten Punkt an. Die Figur haengt von der Taktart ab:
##   4/4 Schlagfigur (unten, links, rechts, oben), 3/4 Dreieck, 2/4 unten/oben,
##   6/8 = 2 Hauptschlaege (Beat 1 und 4), sonst Kreis mit n Punkten.
## Schlaege < FAST_BEAT_MS: halbe Takte, nur die betonten Beats (0, 2, 4 ...).
## Dynamik: Kiai = Figur x KIAI_SCALE, sehr leise Stellen x QUIET_SCALE.
## Beats ausserhalb der Spielfenster (Pausen > BREAK_MS) fallen weg.
##
## Einsaetze (cues): Noten der Map, gruppiert wie OrbitConverter; Tasten A
## (osu! ohne Whistle/Clap, Mania Spalten links) / B (Whistle/Clap, rechts),
## Finish bzw. Akkord ueber beide Seiten = beide (mask 3). Naeher als MERGE_MS
## beisammen = ein Einsatz (Tasten vereinigt).

const FAST_BEAT_MS := 300.0
const MERGE_MS := 90.0
const BREAK_MS := 4000.0
const KIAI_SCALE := 1.3
const QUIET_SCALE := 0.8
const QUIET_LEVEL := 0.10
## Figur-Radius in Figur-Einheiten (1.0 = Bezugsgroesse der Ansicht).
const FIG := 0.62

## Je Schlag: t (ms), pt (Punkt in der Figur), n (Punkte), bar (Takt-Index),
## unit (Punkt ohne Skala), pos (mit Skala), scale, kiai (bool), label (Taktart).
var beats: Array[Dictionary] = []
## Je Takt: t, n, label, scale, i0 (erster Schlag), count.
var bars: Array[Dictionary] = []
## Je Einsatz: t, mask (1 = A, 2 = B, 3 = beide).
var cues: Array[Dictionary] = []
var duration_ms := 0.0


# ---------------------------------------------------------------------------
# Figuren
# ---------------------------------------------------------------------------

## Anzahl Punkte und Figur-Art fuer eine Taktart. kind: "44", "34", "24", "68", "circle".
static func figure_kind(meter: int, fast: bool) -> Dictionary:
	var m := meter if meter >= 2 else 4
	if m == 6:
		return {"kind": "68", "n": 2}
	var eff := (m + 1) / 2 if fast else m
	match eff:
		2: return {"kind": "24", "n": 2}
		3: return {"kind": "34", "n": 3}
		4: return {"kind": "44", "n": 4}
	return {"kind": "circle", "n": maxi(eff, 2)}


## Punkte der Figur (Einheiten, y nach unten), Reihenfolge = Schlagreihenfolge.
static func figure_points(kind: String, n: int) -> PackedVector2Array:
	var f := FIG
	match kind:
		"44":
			return PackedVector2Array([Vector2(0, f), Vector2(-f, 0.2 * f), Vector2(f, 0.2 * f), Vector2(0, -f)])
		"34":
			return PackedVector2Array([Vector2(0, f), Vector2(1.06 * f, 0.0), Vector2(-0.05 * f, -f)])
		"24", "68":
			return PackedVector2Array([Vector2(0, f), Vector2(0, -f)])
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(Vector2(sin(a), cos(a)) * f)
	return out


static func meter_label(meter: int) -> String:
	var m := meter if meter >= 2 else 4
	if m == 6:
		return "6/8"
	return "%d/4" % m


# ---------------------------------------------------------------------------
# Bau
# ---------------------------------------------------------------------------

static func build(beatmap: Beatmap) -> DirigentChart:
	var c := DirigentChart.new()
	if beatmap == null or beatmap.hit_objects.is_empty():
		return c
	c.duration_ms = beatmap.duration_ms()
	c._build_cues(beatmap)
	c._build_beats(beatmap)
	return c


func _build_cues(beatmap: Beatmap) -> void:
	cues.clear()
	var evs: Array = OrbitConverter.convert_std_events(beatmap) if beatmap.mode() == 0 \
			else OrbitConverter.convert_mania_events(beatmap)
	var first_t := -INF
	for g in evs:
		var t := float(g[0])
		var mask := 0
		for it in g[1]:
			mask |= 1 << clampi(int(it[0]), 0, 1)
		if mask == 0:
			continue
		if not cues.is_empty() and t - first_t < MERGE_MS:
			cues[-1].mask = int(cues[-1].mask) | mask
			continue
		first_t = t
		cues.append({"t": t, "mask": mask})


## Rote Punkte als [t, beat_length, meter], sortiert; ohne Punkt: 120 BPM, 4/4.
static func red_points(beatmap: Beatmap) -> Array:
	var out: Array = []
	for p in beatmap.timing_points:
		if p.uninherited and p.beat_length > 0.0:
			out.append([float(p.time), float(p.beat_length), maxi(int(p.meter), 1)])
	out.sort_custom(func(a, b): return a[0] < b[0])
	if out.is_empty():
		out.append([0.0, 500.0, 4])
	return out


func _build_beats(beatmap: Beatmap) -> void:
	beats.clear()
	bars.clear()
	var reds := red_points(beatmap)
	var objs: Array[float] = []
	for h in beatmap.hit_objects:
		objs.append(float(h.time))
	objs.sort()
	var t_first: float = objs[0]
	var t_last := beatmap.duration_ms()
	var inten := IntensityMap.new()
	inten.build(beatmap)
	# Spielfenster: erste Note - ein Takt .. letzte Note + ein Beat, Pausen schneiden.
	var windows: Array = []
	var w_a := t_first
	var prev := t_first
	for i in range(1, objs.size()):
		if objs[i] - prev > BREAK_MS:
			windows.append([w_a, prev])
			w_a = objs[i]
		prev = objs[i]
	windows.append([w_a, maxf(prev, t_last)])
	var wi := 0
	for k in reds.size():
		var t0: float = reds[k][0]
		var bl: float = reds[k][1]
		var meter: int = reds[k][2]
		var t_end: float = reds[k + 1][0] if k + 1 < reds.size() else INF
		var fast := bl < FAST_BEAT_MS and meter != 6 and meter >= 2
		var fk := figure_kind(meter, fast)
		var pts := figure_points(fk.kind, fk.n)
		var bar_len := bl * float(maxi(meter, 1))
		var j := 0
		# Ein Takt vor dem ersten Fenster anfangen (Takt-Eins gehoert zum roten Punkt).
		var j0 := 0
		if t0 < t_first - bar_len * 2.0:
			j0 = int(floor((t_first - bar_len * 2.0 - t0) / bl / float(meter))) * meter
		j = j0
		var bar_idx := -1
		while true:
			var t := t0 + float(j) * bl
			if t >= t_end - 0.5 or t > windows[-1][1] + bl:
				break
			var idx_in_bar := j % maxi(meter, 1)
			var judged := true
			if meter == 6:
				judged = idx_in_bar % 3 == 0
			elif fast:
				judged = idx_in_bar % 2 == 0
			if judged and _in_windows(windows, t, bar_len):
				var pt := idx_in_bar / 3 if meter == 6 else (idx_in_bar / 2 if fast else idx_in_bar)
				pt = clampi(pt, 0, fk.n - 1)
				var kiai := beatmap.is_kiai(t)
				var sc := 1.0
				if kiai:
					sc = KIAI_SCALE
				elif inten.value_at(t) < QUIET_LEVEL:
					sc = QUIET_SCALE
				var this_bar := j / maxi(meter, 1)
				if bars.is_empty() or int(bars[-1].key) != k * 100000 + this_bar:
					bars.append({"t": t, "n": fk.n, "label": meter_label(meter), "scale": sc,
						"i0": beats.size(), "count": 0, "key": k * 100000 + this_bar, "kind": fk.kind})
				bars[-1].count = int(bars[-1].count) + 1
				var u: Vector2 = pts[pt]
				beats.append({"t": t, "pt": pt, "n": fk.n, "bar": bars.size() - 1, "unit": u,
					"pos": u * sc, "scale": sc, "kiai": kiai, "label": meter_label(meter),
					"kind": fk.kind})
			j += 1
	# Takt-Schluessel ist Hilfsfeld
	for b in bars:
		b.erase("key")


func _in_windows(windows: Array, t: float, bar_len: float) -> bool:
	for w in windows:
		if t >= float(w[0]) - bar_len and t <= float(w[1]) + 1.0:
			return true
	return false


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Index des Schlags, dessen Zeit <= t ist (-1 davor).
func beat_at(t: float) -> int:
	var lo := 0
	var hi := beats.size() - 1
	var res := -1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(beats[mid].t) <= t:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res


## Zeit zwischen zwei Schlaegen, ab der es eine Pause ist (Figur ruht).
func is_gap(i: int) -> bool:
	if i < 0 or i + 1 >= beats.size():
		return true
	return float(beats[i + 1].t) - float(beats[i].t) > BREAK_MS * 0.6


## Ideal-Weg: Position der Hand zur Zeit t (glatt von Punkt zu Punkt: Ease +
## leichter Bogen nach aussen). Vor dem ersten / nach dem letzten Schlag: dort ruhen.
func ideal_at(t: float) -> Vector2:
	if beats.is_empty():
		return Vector2.ZERO
	var i := beat_at(t)
	if i < 0:
		return beats[0].pos
	if i + 1 >= beats.size() or is_gap(i):
		return beats[i].pos
	return path_point(beats[i].pos, beats[i + 1].pos, (t - float(beats[i].t)) /
			(float(beats[i + 1].t) - float(beats[i].t)))


## Punkt auf dem Weg von a nach b, u = 0..1 (glatte Dreiecks-Gewichtung: Hand
## bremst in den Punkten, wie ein Schlag).
static func path_point(a: Vector2, b: Vector2, u: float) -> Vector2:
	u = clampf(u, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var d := b - a
	var perp := Vector2(-d.y, d.x).normalized() if d.length() > 0.001 else Vector2.ZERO
	return a.lerp(b, e) + perp * sin(PI * u) * d.length() * 0.10


## Einsatz-Schluessel: Taste 0 (A) / 1 (B) wird von der Maske verlangt?
static func mask_has(mask: int, key: int) -> bool:
	return (mask >> key) & 1 == 1


# ---------------------------------------------------------------------------
# Sterne 0..15
# ---------------------------------------------------------------------------

## Fenster-Raster (Sekunden), Gewichte (Messung: docs/modes/dirigent.md).
const STAR_HOP_MS := 1000.0
const STAR_DECAY := 0.95
const STAR_CUE_K := 0.34
const STAR_SPEED_K := 0.55
const STAR_SPEED_REF := 2.6      # Einheiten/s der Hand, ab der es spuerbar wird
const STAR_BOTH_W := 0.5         # beide Tasten gleichzeitig zaehlt zusaetzlich
const STAR_KNEE := 3.5
const STAR_STRETCH := 3.5
const STAR_MAX := 15.0


## Sterne: Fenster von 2 s mit Handtempo (Strecke/s der Figur, bei Kiai grosse
## Figur) und Einsatz-Last (Einsaetze/s, beide Tasten zaehlen mehr). Die
## haertesten Fenster zaehlen am meisten.
func stars() -> float:
	if cues.size() + beats.size() < 4:
		return 0.0
	var t0 := INF
	var t1 := -INF
	if not cues.is_empty():
		t0 = minf(t0, float(cues[0].t))
		t1 = maxf(t1, float(cues[-1].t))
	if not beats.is_empty():
		t0 = minf(t0, float(beats[0].t))
		t1 = maxf(t1, float(beats[-1].t))
	var n_win := maxi(1, int(ceil((t1 - t0) / STAR_HOP_MS)))
	var load_w := PackedFloat32Array()
	var dist_w := PackedFloat32Array()
	var time_w := PackedFloat32Array()
	load_w.resize(n_win)
	dist_w.resize(n_win)
	time_w.resize(n_win)
	load_w.fill(0.0)
	dist_w.fill(0.0)
	time_w.fill(0.0)
	for c in cues:
		var w := clampi(int((float(c.t) - t0) / STAR_HOP_MS), 0, n_win - 1)
		load_w[w] += 1.0 + (STAR_BOTH_W if int(c.mask) == 3 else 0.0)
	for i in range(0, beats.size() - 1):
		if is_gap(i):
			continue
		var dt := float(beats[i + 1].t) - float(beats[i].t)
		var w := clampi(int((float(beats[i].t) - t0) / STAR_HOP_MS), 0, n_win - 1)
		dist_w[w] += (beats[i + 1].pos - beats[i].pos).length()
		time_w[w] += dt
	var vals: Array[float] = []
	for w in n_win:
		var lw := load_w[w] + (load_w[w - 1] if w > 0 else 0.0)
		var per_s := lw / (2.0 * STAR_HOP_MS / 1000.0)
		var dw := dist_w[w] + (dist_w[w - 1] if w > 0 else 0.0)
		var tw := time_w[w] + (time_w[w - 1] if w > 0 else 0.0)
		var speed := dw / maxf(tw / 1000.0, 0.001) if tw > 0.0 else 0.0
		vals.append(STAR_CUE_K * pow(per_s, 0.8) + STAR_SPEED_K * pow(speed / STAR_SPEED_REF, 1.5))
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
