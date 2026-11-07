class_name SvMod
extends RefCounted

## SV-Mod: erzeugt DETERMINISTISCH aus einer Map gruene SV-Linien wie in
## echten osu!mania-SV-Maps (Analyse und Kennzahlen: docs/qa/sv_mod.md).
##
## Arbeitet im Multiplikator-Raum der ScrollMap: m = SV * BaseBeatLength /
## beatLength. Jede gruene Linie bekommt SV = m * beatLength / Base, damit ist
## jeder BPM-Wechsel normalisiert wie in Ranked-Maps (SV = ModeBPM / BPM).
## Jeder Block (ein Beat, bei Ramps mehrere Beats) hat EXAKT den Mittelwert
## m = 1: Noten kommen in der Summe immer an derselben Scroll-Position an,
## mittlere Scroll-Geschwindigkeit 1.0, die Scroll-Speed-Einstellung stimmt.
##
## Muster (aus echten Maps abgeleitet):
##  ACCENT   Speed-Up hi fuer Anteil f ab der Note auf dem Beat, Rest kompensiert
##  STUTTER  1/2- oder 1/4-Takt: Paar (hi fuer f, lo = (1 - f*hi)/(1 - f))
##  BOUNCE   nach dem Downbeat erst langsamer, dann schneller
##  TELEPORT kurz (4-8 ms) SV 10 direkt vor der Note, davor leicht gebremst
##  FREEZE   letzter Beat vor dem Drop: SV 0.1 fuer 3/4, dann Burst
##  RAMP     1-2 Takte vor dem Drop von lo auf 2 - lo ansteigend (Mittel 1)
## Breaks bleiben ruhig (m = 1), Kiai ist deutlich lebendiger.
##
## Fairness: m immer > 0 (nie rueckwaerts), keine Wechsel naeher als
## MIN_SEG_MS, keine Note derselben Spalte ueberlagert (Positionsabstand
## mindestens GAP_RATIO der Zeit bzw. GAP_ABS_MS). Verletzt ein Block das,
## faellt er auf m = 1 zurueck.
##
## Map mit starkem eigenem SV (MapLibrary.has_strong_sv): ihr SV bleibt 1:1.
##
## Staerke (SvMod.strength): STRENGTH_NORMAL = die Muster oben (Stand v1.15),
## STRENGTH_STRONG (Standard, "max") = Beat-Tanz:
##  BOUNCE   jeder Beat: Ruecklauf (fast Freeze, wo fair kurz RUECKWAERTS -k
##           fuer 1/4 bis 1/2 Beat) und ein Burst, der GENAU auf dem naechsten
##           Beat endet: die Noten tanzen auf dem Beat hoch und runter
##  JUMP     Rueck-Sprung (-JUMP_M fuer wenige ms) direkt vor dem Burst
##  TELEPORT auf Downbeats/starken Beats: SV 10 fuer wenige ms vor dem Beat
##  PULSE    ruhige Strophe: Schub ab dem Beat, danach langsamer
##  WAVE     Hoehen/Tiefen: Beat-Mittel 1 + A*sin ueber den Takt (Takt-Mittel 1)
## Kiai/Chorus: Bounce auf jedem Beat + Reverse + Teleport, Strophen ruhiger
## (aber auf dem Beat), Breaks m = 1. Untergrenze vorwaerts M_MIN_STRONG.
## Reverse/Jump nur mit REV_MARGIN_MS/JUMP_MARGIN_MS Abstand zu jeder Note
## und jedem Hold-Koerper: waehrend der Rueckwaerts-Phase ist keine Note an
## der Trefferlinie, jede Note kommt vorwaerts an. Der Block (ein Takt) hat
## weiter Mittel m = 1 exakt; verletzt er die Fairness, wird erst das Reverse
## entfernt, dann die Welle, zuletzt m = 1.

const M_MIN := 0.1
const M_MAX := 10.0
const MIN_SEG_MS := 4.0
const GAP_RATIO := 0.3
const GAP_ABS_MS := 24.0
## Speed-Up-Stufen wie in echten Maps (Akzent / Stutter-Spitze).
const HI_STEPS := [1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

enum Kind { NONE, ACCENT, STUTTER2, STUTTER4, BOUNCE, TELEPORT, PULSE }

## Staerke-Stufen (spaeter waehlbar; Standard Stark).
const STRENGTH_NORMAL := 0
const STRENGTH_STRONG := 1
static var strength := STRENGTH_STRONG

## Stark: kleinster Vorwaerts-Multiplikator (fast Freeze).
const M_MIN_STRONG := 0.05
## Stark: Abstand jeder Note/jedes Hold-Koerpers zu einer Rueckwaerts-Phase.
const REV_MARGIN_MS := 90.0
const JUMP_MARGIN_MS := 70.0
## Kuerzeste Rueckwaerts-Phase (ms, und Anteil am Beat).
const MIN_REV_MS := 30.0
const MIN_REV_BEAT := 0.12
## Rueck-Sprung: Geschwindigkeit (negativ angewendet) und groesster Betrag
## eines negativen Multiplikators.
const JUMP_M := 10.0
const M_REV_MAX := 10.0

static var _cache_seed := -1
static var _cache_strength := -1
static var _cache: Array = []


## Timing-Points fuer die ScrollMap mit aktivem SV-Mod (Ergebnis je Map gecacht).
static func timing_points_for(bm: Beatmap) -> Array:
	if bm == null:
		return []
	if bm.hit_objects.is_empty() or has_own_sv(bm):
		return bm.timing_points
	var s := map_seed(bm)
	if s != _cache_seed or strength != _cache_strength:
		_cache = generate(bm, s)
		_cache_seed = s
		_cache_strength = strength
	return _cache


## Hat die Map schon STARKES eigenes SV? Dann mischt der Mod nicht doppelt.
## Schwaches SV (nur BPM-Wechsel, < MapLibrary.SV_STRONG_JPM Wechsel/min)
## zaehlt nicht: dort erzeugt der Mod das SV (ersetzt die schwachen gruenen Linien).
static func has_own_sv(bm: Beatmap) -> bool:
	return MapLibrary.has_strong_sv(bm)


## Seed = Hash der Map (rote Linien + Noten): gleich auf jedem Rechner.
static func map_seed(bm: Beatmap) -> int:
	var parts := PackedStringArray()
	for tp in bm.timing_points:
		if tp.uninherited:
			parts.append("%d:%.4f:%d" % [int(round(tp.time)), tp.beat_length, tp.meter])
	for o in bm.hit_objects:
		var col := (o as ManiaNote).column if o is ManiaNote else 0
		parts.append("%d,%d,%d" % [int(round(o.time)), col, int(round(o.end_time()))])
	return "|".join(parts).md5_text().substr(0, 15).hex_to_int()


static func _sorted_reds(tps: Array) -> Array:
	var order: Array = []
	for i in tps.size():
		if (tps[i] as TimingPoint).uninherited:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta: float = (tps[a] as TimingPoint).time
		var tb: float = (tps[b] as TimingPoint).time
		if ta != tb:
			return ta < tb
		return a < b)
	var reds: Array = []
	for i in order:
		reds.append(tps[i])
	return reds


## Anzahl Werte in sorted mit lo <= x < hi.
static func _count(sorted: PackedFloat64Array, lo: float, hi: float) -> int:
	return sorted.bsearch(hi, true) - sorted.bsearch(lo, true)


## Kern: rote Linien der Map + generierte gruene Linien.
static func generate(bm: Beatmap, seed_value: int) -> Array:
	var reds := _sorted_reds(bm.timing_points)
	if reds.is_empty() or bm.hit_objects.is_empty():
		return bm.timing_points
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var heads := PackedFloat64Array()
	var first := INF
	var last_time := -INF
	for o in bm.hit_objects:
		heads.append(o.time)
		first = minf(first, o.time)
		last_time = maxf(last_time, o.end_time())
	heads.sort()
	var base := ScrollMap._most_common_beat_length(reds, last_time)
	var first_red: float = (reds[0] as TimingPoint).time

	# Beat-Raster aller roten Abschnitte im Notenbereich.
	var bt := PackedFloat64Array()
	var blen := PackedFloat64Array()
	var bsec := PackedInt32Array()
	var bbar := PackedInt32Array()
	var bmeter := PackedInt32Array()
	var sec_bl := PackedFloat64Array()
	for k in reds.size():
		var r: TimingPoint = reds[k]
		var bl := ScrollMap.red_beat_length(r)
		sec_bl.append(bl)
		var stop: float = (reds[k + 1] as TimingPoint).time if k + 1 < reds.size() else last_time + bl
		var meter := maxi(r.meter, 1)
		var n := 0
		var t := r.time
		while t < stop - 0.5 and t <= last_time:
			if t + bl >= first - 8.0 * bl:
				bt.append(t)
				blen.append(minf(bl, stop - t))
				bsec.append(k)
				bbar.append(n % meter)
				bmeter.append(meter)
			n += 1
			t = r.time + n * bl

	var nb := bt.size()
	var cnt := PackedInt32Array()
	var on_beat := PackedInt32Array()
	var at_end := PackedInt32Array()
	var kiai := PackedByteArray()
	cnt.resize(nb)
	on_beat.resize(nb)
	at_end.resize(nb)
	kiai.resize(nb)
	for i in nb:
		cnt[i] = _count(heads, bt[i] - 2.0, bt[i] + blen[i] - 2.0)
		on_beat[i] = _count(heads, bt[i] - 3.0, bt[i] + 3.0)
		at_end[i] = _count(heads, bt[i] + blen[i] - 3.0, bt[i] + blen[i] + 3.0)
		kiai[i] = 1 if bm.is_kiai(bt[i] + 1.0) else 0

	# Drops: Kiai-Beginn -> Ramp davor, Freeze im letzten Beat, Akzent darauf.
	# Ohne Kiai: die dichtesten Takte (oberes Viertel) gelten als lebendig.
	if bm.kiai_intervals.is_empty() and nb > 0:
		var bars := []
		var j0 := 0
		while j0 < nb:
			var n := 0
			var j1 := j0
			while j1 < nb and (j1 == j0 or bbar[j1] != 0):
				n += cnt[j1]
				j1 += 1
			bars.append([j0, j1, n])
			j0 = j1
		var dens := []
		for b in bars:
			if int(b[2]) > 0:
				dens.append(int(b[2]))
		dens.sort()
		var thr: int = dens[int(dens.size() * 0.75)] if not dens.is_empty() else 1 << 30
		for b in bars:
			if int(b[2]) >= thr:
				for j in range(int(b[0]), int(b[1])):
					kiai[j] = 1

	# Drops: Kiai-Beginn und erste Note nach einem Break (>= 8 leere Beats).
	var drop_beats := []
	for iv in bm.kiai_intervals:
		var s: float = iv.start
		for i in nb:
			if absf(bt[i] - s) < blen[i] * 0.5:
				drop_beats.append(i)
				break
	var empty := 0
	for i in nb:
		if cnt[i] == 0:
			empty += 1
			continue
		if empty >= 8 and on_beat[i] > 0 and not drop_beats.has(i):
			drop_beats.append(i)
		empty = 0
	drop_beats.sort()
	var plan := {}  # beat index -> ["freeze"] / ["ramp", n, lo] / ["drop"]
	for d: int in drop_beats:
		if d < 1 or bsec[d - 1] != bsec[d] or plan.has(d):
			continue
		plan[d] = ["drop"]
		plan[d - 1] = ["freeze"]
		var want := 4 if rng.randf() < 0.5 else 8
		var lo := rng.randf_range(0.6, 0.75)
		if strength >= STRENGTH_STRONG:
			lo -= 0.25
		var r0 := d - 1
		while r0 - 1 >= 0 and d - 1 - (r0 - 1) <= want and bsec[r0 - 1] == bsec[d] \
				and blen[r0 - 1] == sec_bl[bsec[d]] and not plan.has(r0 - 1):
			r0 -= 1
		var rn := d - 1 - r0
		if rn >= 2:
			plan[r0] = ["ramp", rn, lo]

	var strong_mode := strength >= STRENGTH_STRONG
	var busy := _busy(bm) if strong_mode else []
	# Bloecke bauen: [t0, t1, pieces([[t, m], ...]), sec, alternativen, index]
	var blocks: Array = []
	var phrase := Kind.NONE
	var hi := 1.5
	var f := 0.25
	var invert := false
	var i := 0
	while i < nb:
		var t0 := bt[i]
		var L := blen[i]
		var sec := bsec[i]
		var bl := sec_bl[sec]
		if strong_mode and (bbar[i] == 0 or i == 0 or bsec[i - 1] != sec):
			var sb := _strong_bar(i, bt, blen, bsec, bbar, bmeter, sec_bl, cnt, on_beat, at_end,
					kiai, plan, heads, first_red, base, busy, rng)
			if not sb.is_empty():
				blocks.append(sb)
				i = int(sb[6])
				continue
		if bbar[i] == 0 or i == 0 or bsec[i - 1] != sec:
			var bar_n := 0
			var bar_k := 0
			for j in range(i, mini(i + bmeter[i], nb)):
				bar_n += cnt[j]
				bar_k += 1
			var dense := bar_n >= 4 * bar_k
			var r := rng.randf()
			if kiai[i] == 1:
				phrase = _pick(r, [[Kind.NONE, 0.05], [Kind.ACCENT, 0.25], [Kind.STUTTER2, 0.2],
					[Kind.STUTTER4, 0.25], [Kind.BOUNCE, 0.1], [Kind.TELEPORT, 0.15]])
				hi = HI_STEPS[rng.randi_range(2, 5)]
			else:
				phrase = _pick(r, [[Kind.NONE, 0.4], [Kind.ACCENT, 0.3], [Kind.BOUNCE, 0.15],
					[Kind.STUTTER2, 0.15]])
				hi = HI_STEPS[rng.randi_range(0, 2)]
			f = 0.25 if rng.randf() < 0.5 else 1.0 / 3.0
			invert = rng.randf() < 0.25
			if dense:
				if phrase == Kind.STUTTER4:
					phrase = Kind.STUTTER2
				hi = 1.0 + (hi - 1.0) * 0.7
		var near := _count(heads, t0 - L, t0 + 2.0 * L)
		var pieces: Array = [[t0, 1.0]]
		var span := 1
		var strong_beat := false
		var p: Array = plan.get(i, [])
		if near == 0:
			pass  # Break: ruhig
		elif t0 <= first_red + 0.5:
			pass  # vor dem ersten Kontrollpunkt gilt dessen m: Anlauf bleibt 1.0
		elif not p.is_empty() and p[0] == "ramp":
			span = int(p[1])
			var lo: float = p[2]
			pieces = []
			var steps := span * 2
			for j in steps:
				pieces.append([t0 + j * L * 0.5, lo + (2.0 - 2.0 * lo) * (j + 0.5) / steps])
		elif not p.is_empty() and p[0] == "freeze":
			var mz := M_MIN_STRONG if strong_mode else M_MIN
			pieces = [[t0, mz], [t0 + 0.75 * L, (1.0 - 0.75 * mz) / 0.25]]
		elif not p.is_empty() and p[0] == "drop":
			if on_beat[i] > 0:
				pieces = _pair(t0, L, 4.0, 0.2) if strong_mode else _pair(t0, L, 2.5, 0.25)
		elif strong_mode:
			strong_beat = true
		else:
			var strong := bbar[i] == 0 or (bmeter[i] >= 4 and bbar[i] == bmeter[i] / 2)
			match phrase:
				Kind.ACCENT:
					if on_beat[i] > 0:
						var a := hi if strong else 1.0 + (hi - 1.0) * 0.5
						if on_beat[i] >= 2:
							a = minf(a + 0.25, 3.25)
						pieces = _pair(t0, L, a, 0.25)
				Kind.STUTTER2, Kind.STUTTER4:
					var k := 2 if phrase == Kind.STUTTER2 else 4
					pieces = []
					for j in k:
						var st := t0 + j * L / k
						if invert:
							pieces.append_array(_pair(st, L / k, 0.4, 0.6))
						else:
							pieces.append_array(_pair(st, L / k, hi, f))
				Kind.BOUNCE:
					if bbar[i] == 0:
						var dep := 0.25 + 0.2 * (hi - 1.0) / 2.0
						pieces = [[t0, 1.0 - dep], [t0 + 0.5 * L, 1.0 + dep]]
					elif on_beat[i] > 0:
						pieces = _pair(t0, L, 1.0 + (hi - 1.0) * 0.5, 0.25)
				Kind.TELEPORT:
					if strong and at_end[i] > 0:
						var hi_t := minf(M_MAX, 10.0 * base / bl)
						var dd := clampf(0.012 * L, MIN_SEG_MS, 8.0)
						pieces = [[t0, (L - hi_t * dd) / (L - dd)], [t0 + L - dd, hi_t]]
					elif on_beat[i] > 0:
						pieces = _pair(t0, L, hi, 0.25)
		var t1 := bt[i + span - 1] + blen[i + span - 1]
		if strong_beat:
			# Stark, Takt nicht als Ganzes nutzbar: Beat einzeln (Mittel 1).
			var alts := _strong_beat_alts(t0, L, kiai[i] == 1, bbar[i], bmeter[i],
					at_end[i] > 0, bl, base, busy, rng)
			var ok_alts: Array = []
			for a in alts:
				if _block_ok(a, t1, bl, base):
					ok_alts.append(a)
			ok_alts.append([[t0, 1.0]])
			blocks.append([t0, t1, ok_alts[0], sec, ok_alts, 0])
			i += span
			continue
		if not _block_ok(pieces, t1, bl, base):
			pieces = [[t0, 1.0]]
		blocks.append([t0, t1, pieces, sec, [pieces, [[t0, 1.0]]], 0])
		i += span

	# Fairness: ueberlagerte Noten -> betroffene Bloecke auf m = 1.
	var pairs := _column_pairs(bm)
	var out: Array = []
	var bad := true
	for _iter in (8 if strong_mode else 4):
		out = _emit(reds, sec_bl, base, blocks)
		var sm := ScrollMap.new()
		sm.build(out, last_time)
		bad = false
		for pr in pairs:
			var ta: float = pr[0]
			var tb: float = pr[1]
			var dt := tb - ta
			var need := minf(dt, maxf(GAP_RATIO * dt, GAP_ABS_MS)) - 0.001
			if sm.position(tb) - sm.position(ta) >= need:
				continue
			for b in blocks:
				if float(b[0]) >= tb or float(b[1]) <= ta:
					continue
				var pcs: Array = b[2]
				if pcs.size() > 1 or float(pcs[0][1]) != 1.0:
					# Naechst ruhigere Alternative (zuletzt m = 1).
					var alts: Array = b[4]
					var k: int = mini(int(b[5]) + 1, alts.size() - 1)
					b[5] = k
					b[2] = alts[k]
					bad = true
		if not bad:
			break
	if bad:
		out = _emit(reds, sec_bl, base, blocks)
	return out


static func _pick(r: float, table: Array) -> int:
	var acc := 0.0
	for e in table:
		acc += float(e[1])
		if r < acc:
			return int(e[0])
	return int(table[table.size() - 1][0])


## Paar: hi fuer Anteil f, danach (1 - f*hi)/(1 - f) -> Mittelwert genau 1.
static func _pair(t0: float, L: float, hi: float, f: float) -> Array:
	return [[t0, hi], [t0 + f * L, (1.0 - f * hi) / (1.0 - f)]]


## Gueltiger Block: Werte im Bereich, keine Stuecke kuerzer als MIN_SEG_MS,
## gruene SV nach Normalisierung innerhalb der ScrollMap-Grenzen.
static func _block_ok(pieces: Array, t1: float, bl: float, base: float) -> bool:
	for j in pieces.size():
		var m: float = pieces[j][1]
		var end: float = t1 if j + 1 == pieces.size() else float(pieces[j + 1][0])
		if end - float(pieces[j][0]) < MIN_SEG_MS - 1e-9:
			return false
		if is_nan(m):
			return false
		if m < 0.0:
			# Reverse/Jump (nur Stark): ueber Meta, nicht ueber gruene SV.
			if strength < STRENGTH_STRONG or not (m <= -M_MIN + 1e-9 and m >= -M_REV_MAX - 1e-9):
				return false
			continue
		var m_min := M_MIN_STRONG if strength >= STRENGTH_STRONG else M_MIN
		if not (m >= m_min - 1e-9 and m <= M_MAX + 1e-9):
			return false
		var sv := m * bl / base
		if sv < ScrollMap.SV_MIN or sv > ScrollMap.SV_MAX:
			return false
	return true


## Zeitintervalle, die sichtbar getrennt bleiben muessen: je Spalte
## Ende der Note -> naechster Kopf, und Hold-Kopf -> Hold-Ende.
static func _column_pairs(bm: Beatmap) -> Array:
	var by_col := {}
	for o in bm.hit_objects:
		var col := (o as ManiaNote).column if o is ManiaNote else 0
		if not by_col.has(col):
			by_col[col] = []
		by_col[col].append(o)
	var pairs: Array = []
	for col in by_col:
		var arr: Array = by_col[col]
		arr.sort_custom(func(a, b): return a.time < b.time)
		for j in arr.size():
			var o = arr[j]
			if o.end_time() > o.time:
				pairs.append([o.time, o.end_time()])
			if j + 1 < arr.size() and arr[j + 1].time > o.end_time():
				pairs.append([o.end_time(), arr[j + 1].time])
	return pairs


## Rote Linien + gruene Linien (Basislinie m = 1 an jeder roten Linie, dann
## die Block-Stuecke; gleiche aufeinanderfolgende Werte zusammengefasst).
static func _emit(reds: Array, sec_bl: PackedFloat64Array, base: float, blocks: Array) -> Array:
	var out: Array = []
	var bi := 0
	for k in reds.size():
		var r: TimingPoint = reds[k]
		out.append(r)
		var lines: Array = [[r.time, 1.0]]
		while bi < blocks.size() and int(blocks[bi][3]) < k:
			bi += 1
		while bi < blocks.size() and int(blocks[bi][3]) == k:
			for pc in blocks[bi][2]:
				if float(pc[0]) <= float(lines[lines.size() - 1][0]):
					lines[lines.size() - 1] = pc
				else:
					lines.append(pc)
			bi += 1
		var cur := -1.0
		for ln in lines:
			var m: float = ln[1]
			if m == cur:
				continue
			cur = m
			var g := TimingPoint.new()
			g.time = float(ln[0])
			g.beat_length = -100.0 / (absf(m) * sec_bl[k] / base)
			g.uninherited = false
			g.meter = r.meter
			if m < 0.0:
				# Rueckwaerts: Multiplikator direkt (ScrollMap.SV_META).
				g.set_meta(ScrollMap.SV_META, m)
			out.append(g)
	return out


# ---------------------------------------------------------------- Stark ---

## Belegte Zeitspannen (Noten-Kopf bis -Ende), sortiert und verschmolzen:
## [starts, ends] fuer _free_gap.
static func _busy(bm: Beatmap) -> Array:
	var iv: Array = []
	for o in bm.hit_objects:
		iv.append([o.time, maxf(o.end_time(), o.time)])
	iv.sort_custom(func(a, b): return a[0] < b[0])
	var bs := PackedFloat64Array()
	var be := PackedFloat64Array()
	for e in iv:
		if not bs.is_empty() and float(e[0]) <= be[be.size() - 1]:
			be[be.size() - 1] = maxf(be[be.size() - 1], float(e[1]))
		else:
			bs.append(float(e[0]))
			be.append(float(e[1]))
	return [bs, be]


## Groesste Teilspanne von [a, b] mit mindestens margin Abstand zu jeder
## belegten Spanne; [] wenn keine.
static func _free_gap(busy: Array, a: float, b: float, margin: float) -> Array:
	var bs: PackedFloat64Array = busy[0]
	var be: PackedFloat64Array = busy[1]
	var i := be.bsearch(a - margin, false)
	var cur := a
	var best: Array = []
	var best_len := 0.0
	while i < bs.size() and bs[i] - margin < b:
		var e := bs[i] - margin
		if e - cur > best_len:
			best_len = e - cur
			best = [cur, e]
		cur = maxf(cur, be[i] + margin)
		i += 1
	if b - cur > best_len:
		best = [cur, b]
	return best


## Stuecke [[t, m], ...] mit genau einem Platzhalter (m = NAN) so loesen, dass
## das Mittel ueber [t0, t1] genau lv ist.
static func _solve(pcs: Array, t1: float, lv: float) -> Array:
	var t0: float = pcs[0][0]
	var sum := 0.0
	var free_len := 0.0
	var fi := -1
	for j in pcs.size():
		var end: float = t1 if j + 1 == pcs.size() else float(pcs[j + 1][0])
		var len := end - float(pcs[j][0])
		if is_nan(float(pcs[j][1])):
			fi = j
			free_len = len
		else:
			sum += float(pcs[j][1]) * len
	if fi >= 0 and free_len > 0.0:
		pcs[fi][1] = (lv * (t1 - t0) - sum) / free_len
	return pcs


## Ein Beat [t0, t0 + L] mit Mittel lv (Beat-Tanz):
## Ruecklauf lo*lv (fast Freeze), darin optional Reverse (-k fuer bis rev_len)
## bzw. Rueck-Sprung (-JUMP_M fuer dd), danach Burst, der GENAU auf dem
## naechsten Beat endet; tele_hi > 0: Teleport fuer dd direkt vor dem Beat.
## Zu grosser Burst: Reverse kuerzer, zuletzt ohne Rueckwaerts.
static func _bounce(t0: float, L: float, lv: float, lo: float, fs: float, k: float,
		rev_len: float, jump: bool, tele_hi: float, dd: float, s_cap: float, busy: Array) -> Array:
	var t1 := t0 + L
	var ss := t1 - fs * L
	var tries: Array = [[k, rev_len, jump], [k, rev_len * 0.6, jump], [0.0, 0.0, false]]
	var pcs: Array = []
	for tr in tries:
		var tk: float = tr[0]
		var tlen: float = tr[1]
		var tj: bool = tr[2]
		var rs := -1.0
		var re := -1.0
		var rm := 0.0
		if tj:
			var g := _free_gap(busy, t0, ss, JUMP_MARGIN_MS)
			if g.size() == 2 and float(g[1]) - float(g[0]) >= dd:
				re = minf(float(g[1]), ss)
				rs = re - dd
				rm = -JUMP_M
		elif tk > 0.0:
			var g := _free_gap(busy, t0, ss, REV_MARGIN_MS)
			if g.size() == 2:
				re = minf(float(g[1]), ss)
				rs = maxf(float(g[0]), re - tlen)
				if re - rs >= maxf(MIN_REV_MS, MIN_REV_BEAT * L):
					rm = -tk
				else:
					rs = -1.0
		pcs = []
		if rs < 0.0 or rs > t0 + MIN_SEG_MS:
			pcs.append([t0, lo * lv])
		if rs >= 0.0:
			pcs.append([maxf(rs, t0), rm])
			if re < ss - MIN_SEG_MS:
				pcs.append([re, lo * lv])
		var fi := pcs.size()
		pcs.append([ss, NAN])
		if tele_hi > 0.0 and ss < t1 - dd - MIN_SEG_MS:
			pcs.append([t1 - dd, tele_hi])
		_solve(pcs, t1, lv)
		var sv: float = pcs[fi][1]
		if sv <= s_cap and sv >= lo * lv:
			return pcs
	return pcs


## Schub ab dem Beat (hi fuer f), Rest kompensiert, Mittel lv.
static func _pulse(t0: float, L: float, lv: float, hi: float, f: float) -> Array:
	return [[t0, hi * lv], [t0 + f * L, lv * (1.0 - f * hi) / (1.0 - f)]]


## Gewuerfelte Phrase eines Takts (Stark = max, so weit fair).
static func _strong_phrase(is_kiai: bool, dense: bool, rng: RandomNumberGenerator) -> Dictionary:
	var ph := {}
	if is_kiai:
		ph.kind = _pick(rng.randf(), [[Kind.BOUNCE, 0.75], [Kind.STUTTER2, 0.2], [Kind.PULSE, 0.05]])
		ph.lo = rng.randf_range(0.08, 0.2)
		ph.fs = 0.15 if rng.randf() < 0.5 else 0.2
		ph.k = rng.randf_range(1.0, 2.0)
		ph.rev_p = 0.7
		ph.jump_p = 0.45
		ph.tele_p = 0.6
		ph.hi = rng.randf_range(3.0, 4.0)
		ph.amp = rng.randf_range(0.2, 0.35)
	else:
		ph.kind = _pick(rng.randf(), [[Kind.BOUNCE, 0.5], [Kind.PULSE, 0.4], [Kind.NONE, 0.1]])
		ph.lo = rng.randf_range(0.35, 0.55)
		ph.fs = 0.2 if rng.randf() < 0.5 else 0.25
		ph.k = rng.randf_range(0.6, 1.0)
		ph.rev_p = 0.35
		ph.jump_p = 0.2
		ph.tele_p = 0.2
		ph.hi = rng.randf_range(2.0, 3.0)
		ph.amp = rng.randf_range(0.2, 0.35)
	ph.rev_frac = [0.25, 0.375, 0.5][rng.randi_range(0, 2)]
	ph.wave_ph = rng.randf()
	if dense:
		if ph.kind == Kind.STUTTER2:
			ph.kind = Kind.BOUNCE
		ph.lo = minf(float(ph.lo) + 0.2, 0.7)
		ph.hi = 1.0 + (float(ph.hi) - 1.0) * 0.8
	return ph


## Alternativen eines Beats (Stark, Mittel lv): [voll, ohne Rueckwaerts].
static func _beat_alts(t0: float, L: float, lv: float, ph: Dictionary, bar_pos: int,
		meter: int, note_at_end: bool, bl: float, base: float, busy: Array,
		rng: RandomNumberGenerator) -> Array:
	var r_rev := rng.randf()
	var r_jump := rng.randf()
	var r_tele := rng.randf()
	var next_strong := (bar_pos + 1) % meter == 0 or (meter >= 4 and bar_pos + 1 == meter / 2)
	var down := bar_pos == 0
	var dd := clampf(0.02 * L, MIN_SEG_MS + 1.0, 10.0)
	# Groesster Burst: M_MAX und gruene SV-Grenze (BPM-normalisiert), mit Reserve.
	var s_cap := minf(M_MAX, ScrollMap.SV_MAX * base / bl) * 0.95
	var lo: float = ph.lo
	if down:
		lo = maxf(lo * 0.6, M_MIN_STRONG)
	match int(ph.kind):
		Kind.BOUNCE, Kind.STUTTER2:
			var tele := 0.0
			if next_strong and note_at_end and r_tele < float(ph.tele_p):
				tele = minf(M_MAX, 10.0 * base / bl)
			var k := 0.0
			var jump := false
			if r_rev < float(ph.rev_p):
				k = float(ph.k)
			elif r_jump < float(ph.jump_p):
				jump = true
			var fs: float = ph.fs
			if int(ph.kind) == Kind.STUTTER2:
				var h := L * 0.5
				var full := _bounce(t0, h, lv, lo, fs * 1.5, 0.0, 0.0, false, 0.0, dd, s_cap, busy)
				full.append_array(_bounce(t0 + h, h, lv, lo, fs * 1.5, k, h * float(ph.rev_frac),
						jump, tele, dd, s_cap, busy))
				var calm := _bounce(t0, h, lv, lo, fs * 1.5, 0.0, 0.0, false, 0.0, dd, s_cap, busy)
				calm.append_array(_bounce(t0 + h, h, lv, lo, fs * 1.5, 0.0, 0.0, false, tele, dd, s_cap, busy))
				return [full, calm]
			var full := _bounce(t0, L, lv, lo, fs, k, L * float(ph.rev_frac), jump, tele, dd, s_cap, busy)
			var calm := _bounce(t0, L, lv, lo, fs, 0.0, 0.0, false, tele, dd, s_cap, busy)
			return [full, calm]
		Kind.PULSE:
			var a: float = ph.hi if (down or next_strong) else 1.0 + (float(ph.hi) - 1.0) * 0.6
			var f := minf(0.25, 0.85 / (a - 0.15))
			var pul := _pulse(t0, L, lv, a, f)
			if r_rev < float(ph.rev_p) * 0.5:
				# Kurzer Ruecklauf vor dem naechsten Beat (wo fair).
				var b := _bounce(t0, L, lv, lo, 0.25, float(ph.k), L * float(ph.rev_frac), false,
						0.0, dd, s_cap, busy)
				return [b, pul]
			return [pul]
	return [[[t0, lv]]]


## Takt ab Beat i als EIN Block (Stark): Welle ueber den Takt (Beat-Mittel
## 1 + A*sin, Takt-Mittel exakt 1) und je Beat Bounce/Pulse/Reverse.
## Rueckgabe Block [t0, t1, pieces, sec, alts, 0, naechster Beat-Index]
## oder [] (Takt unvollstaendig, Break, Plan-Beat, vor der ersten roten Linie).
static func _strong_bar(i: int, bt: PackedFloat64Array, blen: PackedFloat64Array,
		bsec: PackedInt32Array, bbar: PackedInt32Array, bmeter: PackedInt32Array,
		sec_bl: PackedFloat64Array, cnt: PackedInt32Array, on_beat: PackedInt32Array,
		at_end: PackedInt32Array, kiai: PackedByteArray, plan: Dictionary,
		heads: PackedFloat64Array, first_red: float, base: float, busy: Array,
		rng: RandomNumberGenerator) -> Array:
	var nb := bt.size()
	var meter := bmeter[i]
	var sec := bsec[i]
	var bl := sec_bl[sec]
	if bbar[i] != 0 or i + meter > nb or bt[i] <= first_red + 0.5:
		return []
	var n := 0
	for j in range(i, i + meter):
		if bsec[j] != sec or bbar[j] != j - i or blen[j] != bl or plan.has(j):
			return []
		if _count(heads, bt[j] - blen[j], bt[j] + 2.0 * blen[j]) == 0:
			return []
		n += cnt[j]
	var is_kiai := kiai[i] == 1
	var ph := _strong_phrase(is_kiai, n >= 4 * meter, rng)
	# Welle: Beat-Mittel lv_j = 1 + A*sin(...), exakt auf Mittel 1 normiert.
	var lv := PackedFloat64Array()
	var mean := 0.0
	for j in meter:
		var v := 1.0 + float(ph.amp) * sin(TAU * (float(j) + 0.5 + float(ph.wave_ph)) / float(meter))
		lv.append(v)
		mean += v
	mean /= float(meter)
	for j in meter:
		lv[j] -= mean - 1.0
	var t0 := bt[i]
	var t1 := bt[i + meter - 1] + blen[i + meter - 1]
	var full: Array = []
	var calm: Array = []
	var flat: Array = []
	for j in meter:
		var bj := i + j
		var alts := _beat_alts(bt[bj], bl, lv[j], ph, j, meter, at_end[bj] > 0, bl, base, busy, rng)
		full.append_array(alts[0])
		calm.append_array(alts[alts.size() - 1])
		flat.append_array(_pulse(bt[bj], bl, 1.0, 1.0 + (float(ph.hi) - 1.0) * 0.5, 0.25)
				if on_beat[bj] > 0 else [[bt[bj], 1.0]])
	var out_alts: Array = []
	for a in [full, calm, flat]:
		if _block_ok(a, t1, bl, base) and (out_alts.is_empty() or out_alts[out_alts.size() - 1] != a):
			out_alts.append(a)
	out_alts.append([[t0, 1.0]])
	return [t0, t1, out_alts[0], sec, out_alts, 0, i + meter]


## Einzelner Beat (Stark), wenn der Takt nicht als Ganzes passt: Mittel 1.
static func _strong_beat_alts(t0: float, L: float, is_kiai: bool, bar_pos: int, meter: int,
		note_at_end: bool, bl: float, base: float, busy: Array, rng: RandomNumberGenerator) -> Array:
	var ph := _strong_phrase(is_kiai, false, rng)
	return _beat_alts(t0, L, 1.0, ph, bar_pos, maxi(meter, 1), note_at_end, bl, base, busy, rng)
