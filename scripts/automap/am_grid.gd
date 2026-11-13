class_name AmGrid
extends RefCounted

## Taktgitter fuer den 4K-Auto-Mapper (docs/automap/spec.md, Abschnitt AmGrid).
## Reines GDScript, kein Szenenzugriff, thread-faehig. Messung: docs/automap/grid.md.
##
## Ablauf von track():
##   1. envelope(): Onset-Fluss in 3 Baendern (5-ms-Frames), Bass-Fluss, Bass-Nulldurchgaenge.
##   2. Autokorrelation in 4-s-Bloecken: grober Puls des Songs, Fenster mit fremdem Tempo
##      werden eigene Segmente (Tempowechsel).
##   3. Je Segment: Periode ueber alle Anschlaege fein gesucht (Phasensumme), dann die
##      Tempo-Hypothesen der Familie (x2, x0,5, x1,5, x0,667, x3, x0,333, x0,75, x1,333)
##      ueber die Taktstruktur bewertet (Schlag, Halbe, Viertel des Schlags, Fuellung,
##      Bass, Tempo-Vorwissen). Gewinner: Regression Zeit = Offset + k * Periode ueber das
##      ganze Segment (keine Drift), ganzzahlige BPM, wenn sie innerhalb der Messgenauigkeit liegt.
##   4. Feinphase aus dem gefalteten Onset-Profil, Taktart (4 oder 3) und Taktanfang aus
##      Akzent-, Bass-, Harmonie- und Abschnittswechsel-Statistik je Schlag.
## Alle Zeiten im Ergebnis sind akustische Anschlaege minus `lead_ms` (osu-Konvention).

## Noten echter Maps liegen so viele ms vor der Mitte des Onset-Anstiegs (gemessen, grid.md).
const OSU_LEAD_MS := 23.0

## Tempo-Faktoren der Hypothesen-Familie relativ zum groben Puls.
const FAMILY := [1.0, 2.0, 0.5, 1.5, 0.6667, 3.0, 0.3333, 0.75, 1.3333]

const DEFAULTS := {
	"hop_ms": 5.0,              # Frame-Laenge des Onset-Flusses
	"lead_ms": OSU_LEAD_MS,     # Abzug akustisch -> Map-Zeit
	"bpm_min": 60.0,            # Grenzen der Tempo-Hypothesen
	"bpm_max": 330.0,
	"pulse_min_ms": 200.0,      # Suchbereich des groben Pulses (Autokorrelation)
	"pulse_max_ms": 1000.0,
	"n_pulses": 4,              # Kandidaten des groben Pulses (lokale ACF-Maxima)
	"prior_bpm": 160.0,         # Tempo-Vorwissen (Log-Normal um diesen Wert)
	"prior_sigma_oct": 0.6,
	"w_half": 0.5,              # Gewicht Halbe/Viertel des Schlags in der Stuetzung
	"w_quarter": 0.25,
	"w_low": 0.0,               # Gewicht Bass-Periodizitaet auf dem Schlag
	"fill_pow": 1.5,            # Strafe fuer leere Schlaege
	"ref_pull": 2.0,            # Folgesegmente bleiben nah am Tempo des Hauptsegments
	"max_peaks": 1500,          # staerkste Anschlaege fuer Phasensummen
	"scan_peaks": 800,
	"foreign_ratio": 0.7,       # Fenster gilt als fremdes Tempo, wenn die Familie so schwach ist
	"foreign_tol": 0.03,
	"foreign_min_windows": 2,
	"snap_drift_ms": 12.0,      # ganzzahlige BPM, wenn die Abweichung ueber das Segment kleiner ist
	"flip_low_ratio": 1.4,      # Schlag um eine Halbe verschieben, wenn der Bass dort so viel staerker ist
	"phase_mode": "peak",       # "peak" oder "half" (halber Anstieg des gefalteten Profils)
	"meter3_ratio": 1.25,       # 3er-Takt nur, wenn so viel deutlicher als 4er
	"db_w_low": 1.0,            # Gewichte Taktanfang: Bass-Akzent, Akzent, Harmoniewechsel, Abschnittswechsel
	"db_w_acc": 0.5,
	"db_w_hc": 1.0,
	"db_w_nov": 1.0,
	"debug": false,
}


static func _cfg(params: Dictionary) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	return p


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "segments": [], "confidence": 0.0, "alternatives": []}


## pcm: mono, rate Hz (22050). Liefert das Taktgitter des ganzen Songs.
static func track(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary:
	if rate <= 0 or pcm.size() < rate * 4:
		return _fail("Audio kuerzer als 4 s")
	return track_env(envelope(pcm, rate, params), params)


# ---------------------------------------------------------------------------
# Gitter-Abfragen
# ---------------------------------------------------------------------------

static func _seg_index(grid: Dictionary, t_ms: float) -> int:
	var segs: Array = grid.get("segments", [])
	var idx := 0
	for i in segs.size():
		if float(segs[i].start_ms) <= t_ms + 0.001:
			idx = i
	return idx


## Naechster 1/div-Schlag.
static func snap(grid: Dictionary, t_ms: float, div: int) -> float:
	var segs: Array = grid.get("segments", [])
	if segs.is_empty():
		return t_ms
	var i := _seg_index(grid, t_ms)
	var s: Dictionary = segs[i]
	var step: float = float(s.beat_ms) / maxi(div, 1)
	var r: float = float(s.start_ms) + roundf((t_ms - float(s.start_ms)) / step) * step
	if i + 1 < segs.size() and r > float(segs[i + 1].start_ms) - step * 0.5:
		return float(segs[i + 1].start_ms)
	return r


## Schlaege seit Songanfang (stetig je Segment; 0 = erster Schlag des ersten Segments).
static func beat_pos(grid: Dictionary, t_ms: float) -> float:
	var segs: Array = grid.get("segments", [])
	if segs.is_empty():
		return 0.0
	var i := _seg_index(grid, t_ms)
	var b := 0.0
	for j in i:
		b += (float(segs[j + 1].start_ms) - float(segs[j].start_ms)) / float(segs[j].beat_ms)
	return b + (t_ms - float(segs[i].start_ms)) / float(segs[i].beat_ms)


static func is_downbeat(grid: Dictionary, t_ms: float, tol_ms: float = 8.0) -> bool:
	var segs: Array = grid.get("segments", [])
	if segs.is_empty():
		return false
	var s: Dictionary = segs[_seg_index(grid, t_ms)]
	var bar: float = float(s.beat_ms) * int(s.meter)
	var d: float = fposmod(t_ms - float(s.downbeat_ms) + bar * 0.5, bar) - bar * 0.5
	return absf(d) <= tol_ms


## Tempo x factor (2 = doppelt so viele Schlaege). Segmentgrenzen und Taktanfaenge bleiben.
static func scaled(grid: Dictionary, factor: float) -> Dictionary:
	var g := grid.duplicate(true)
	if factor <= 0.0:
		return g
	for s in g.get("segments", []):
		s.beat_ms = float(s.beat_ms) / factor
		if s.has("bpm"):
			s.bpm = 60000.0 / float(s.beat_ms)
	var alts: Array = []
	for a in g.get("alternatives", []):
		alts.append({"factor": snappedf(float(a.factor) / factor, 0.0001), "score": a.score})
	g["alternatives"] = alts
	return g


# ---------------------------------------------------------------------------
# Onset-Fluss
# ---------------------------------------------------------------------------

## {flux, low, zc, hop_ms}: Onset-Fluss (3 Baender, Log), Bass-Fluss, Summe der
## Bass-Nulldurchgaenge (Laenge n + 1) je Frame.
static func envelope(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary:
	var P := _cfg(params)
	var hop: int = maxi(1, int(round(rate * float(P.hop_ms) / 1000.0)))
	var n: int = pcm.size() / hop
	var flux := PackedFloat32Array()
	flux.resize(n)
	var low := PackedFloat32Array()
	low.resize(n)
	var zc := PackedFloat32Array()
	zc.resize(n + 1)
	var a1 := 1.0 - exp(-TAU * 200.0 / rate)
	var a2 := 1.0 - exp(-TAU * 2500.0 / rate)
	var l1 := 0.0
	var l1b := 0.0
	var l2 := 0.0
	var pv0 := 0.0
	var pv1 := 0.0
	var pv2 := 0.0
	var sgn := false
	var zcount := 0.0
	for f in n:
		var e0 := 0.0
		var e1 := 0.0
		var e2 := 0.0
		var base := f * hop
		for k in hop:
			var x := pcm[base + k]
			l1 += a1 * (x - l1)
			l1b += a1 * (l1 - l1b)
			l2 += a2 * (x - l2)
			var m := l2 - l1
			var h := x - l2
			e0 += l1 * l1
			e1 += m * m
			e2 += h * h
			if (l1b > 0.0) != sgn:
				sgn = not sgn
				zcount += 1.0
		var v0 := log(1.0 + 60.0 * sqrt(e0 / hop))
		var v1 := log(1.0 + 60.0 * sqrt(e1 / hop))
		var v2 := log(1.0 + 60.0 * sqrt(e2 / hop))
		if f > 0:
			var d0 := maxf(0.0, v0 - pv0)
			flux[f] = 0.6 * d0 + maxf(0.0, v1 - pv1) + 1.4 * maxf(0.0, v2 - pv2)
			low[f] = d0
		pv0 = v0
		pv1 = v1
		pv2 = v2
		zc[f + 1] = zcount
	return {"flux": flux, "low": low, "zc": zc, "hop_ms": hop * 1000.0 / rate}


## Lokale Maxima ueber adaptiver Schwelle: {t (ms), w (Wurzel der relativen Staerke), lw (Bass)}.
static func _peaks(flux: PackedFloat32Array, low: PackedFloat32Array, hop_ms: float) -> Dictionary:
	var n := flux.size()
	var pre := PackedFloat64Array()
	pre.resize(n + 1)
	var prel := PackedFloat64Array()
	prel.resize(n + 1)
	for i in n:
		pre[i + 1] = pre[i] + flux[i]
		prel[i + 1] = prel[i] + low[i]
	var half := 100
	var dom := 6
	var gmean := pre[n] / maxf(n, 1)
	var glow := prel[n] / maxf(n, 1)
	var t := PackedFloat64Array()
	var w := PackedFloat64Array()
	var lw := PackedFloat64Array()
	for i in range(1, n - 1):
		var v := flux[i]
		if v <= flux[i - 1] or v < flux[i + 1]:
			continue
		var lo := maxi(0, i - half)
		var hi := mini(n, i + half + 1)
		var lm := (pre[hi] - pre[lo]) / (hi - lo)
		if v < lm * 1.6 + gmean * 0.15:
			continue
		var best := true
		for j in range(maxi(0, i - dom), mini(n, i + dom + 1)):
			if flux[j] > v:
				best = false
				break
		if not best:
			continue
		var p := 0.0
		var a := flux[i - 1]
		var c := flux[i + 1]
		var den := a - 2.0 * v + c
		if absf(den) > 1e-9:
			p = clampf(0.5 * (a - c) / den, -0.5, 0.5)
		t.append((i + 0.5 + p) * hop_ms)
		w.append(sqrt(v / (lm + gmean * 0.1 + 1e-6)))
		var lv := maxf(low[i], maxf(low[i - 1], low[i + 1]))
		var llm := (prel[hi] - prel[lo]) / (hi - lo)
		lw.append(sqrt(lv / (llm + glow * 0.1 + 1e-6)))
	return {"t": t, "w": w, "lw": lw}


# ---------------------------------------------------------------------------
# Autokorrelation in Bloecken, grober Puls, Tempowechsel
# ---------------------------------------------------------------------------

const _BLOCK_MS := 4000.0
const _MIN_LAG := 8

static func _acf_blocks(flux: PackedFloat32Array, hop_ms: float) -> Dictionary:
	var n := flux.size()
	var pre := PackedFloat64Array()
	pre.resize(n + 1)
	for i in n:
		pre[i + 1] = pre[i] + flux[i]
	var n2 := n / 2
	var env := PackedFloat32Array()
	env.resize(n2)
	for j in n2:
		var s := 0.0
		for i in [2 * j, 2 * j + 1]:
			var lo := maxi(0, i - 100)
			var hi := mini(n, i + 101)
			s += maxf(0.0, flux[i] - (pre[hi] - pre[lo]) / (hi - lo))
		env[j] = s
	var lag_ms := 2.0 * hop_ms
	var maxlag := int(2000.0 / lag_ms)
	var blk := int(_BLOCK_MS / lag_ms)
	var nblk := int(ceil(float(n2) / blk))
	var blocks: Array = []
	var glob := PackedFloat32Array()
	glob.resize(maxlag + 1)
	for b in nblk:
		var a := PackedFloat32Array()
		a.resize(maxlag + 1)
		var i0 := b * blk
		var i1 := mini(n2, i0 + blk)
		var lag := 0
		while lag <= maxlag:
			var ie := mini(i1, n2 - lag)
			var sum := 0.0
			for i in range(i0, ie):
				sum += env[i] * env[i + lag]
			a[lag] = sum
			glob[lag] += sum
			lag = _MIN_LAG if lag == 0 else lag + 1
		blocks.append(a)
	return {"blocks": blocks, "glob": glob, "lag_ms": lag_ms, "maxlag": maxlag}


static func _ai(a: PackedFloat32Array, lag: float) -> float:
	if lag < _MIN_LAG or lag >= a.size() - 1:
		return 0.0
	var i := int(lag)
	var fr := lag - i
	return a[i] * (1.0 - fr) + a[i + 1] * fr


static func _comb(a: PackedFloat32Array, lag: float) -> float:
	return _ai(a, lag) + 0.5 * _ai(a, 2.0 * lag) + 0.5 * _ai(a, 0.5 * lag)


## Staerkster Puls: Vector2(Lag in Frames (fein), Wert).
static func _pulse(a: PackedFloat32Array, lag_ms: float, P: Dictionary) -> Vector2:
	var l0 := maxi(_MIN_LAG * 2, int(float(P.pulse_min_ms) / lag_ms))
	var l1 := mini(a.size() / 2 - 1, int(float(P.pulse_max_ms) / lag_ms))
	var best := -1.0
	var bl := l0
	for l in range(l0, l1 + 1):
		var c := _comb(a, l)
		if c > best:
			best = c
			bl = l
	var ya := _comb(a, bl - 1)
	var yc := _comb(a, bl + 1)
	var den := ya - 2.0 * best + yc
	var fr := 0.0
	if absf(den) > 1e-12:
		fr = clampf(0.5 * (ya - yc) / den, -0.5, 0.5)
	return Vector2(bl + fr, best)


## Kandidaten fuer den groben Puls (ms): staerkster Puls zuerst, dann die naechststaerksten
## lokalen Maxima der Kamm-Autokorrelation (mindestens 4 % auseinander).
static func _pulse_cands(a: PackedFloat32Array, lag_ms: float, P: Dictionary) -> Array:
	var l0 := maxi(_MIN_LAG * 2, int(float(P.pulse_min_ms) / lag_ms))
	var l1 := mini(a.size() / 2 - 1, int(float(P.pulse_max_ms) / lag_ms))
	var vals := PackedFloat64Array()
	for l in range(l0 - 1, l1 + 2):
		vals.append(_comb(a, l))
	var loc: Array = []
	for i in range(1, vals.size() - 1):
		if vals[i] >= vals[i - 1] and vals[i] > vals[i + 1]:
			var fr := 0.0
			var den := vals[i - 1] - 2.0 * vals[i] + vals[i + 1]
			if absf(den) > 1e-12:
				fr = clampf(0.5 * (vals[i - 1] - vals[i + 1]) / den, -0.5, 0.5)
			loc.append([vals[i], (l0 - 1 + i + fr) * lag_ms])
	loc.sort_custom(func(x, y): return x[0] > y[0])
	var out: Array = []
	for c in loc:
		if out.size() >= int(P.n_pulses):
			break
		var dup := false
		for o in out:
			if absf(float(c[1]) / float(o) - 1.0) < 0.04:
				dup = true
		if not dup:
			out.append(c[1])
	return out


## Grobe Segmente [{lo, hi, T}] (ms): Hauptpuls und Laeufe von Fenstern mit fremdem Tempo.
static func _rough_segments(ac: Dictionary, lag0: float, dur: float, P: Dictionary) -> Array:
	var blocks: Array = ac.blocks
	var lag_ms: float = ac.lag_ms
	var nw := blocks.size() - 1
	var t_main := lag0 * lag_ms
	var out: Array = [{"lo": 0.0, "hi": dur, "T": t_main}]
	if nw < 4:
		return out
	var energies: Array = []
	var wins: Array = []
	for j in nw:
		var a := PackedFloat32Array()
		a.resize(blocks[j].size())
		var b0: PackedFloat32Array = blocks[j]
		var b1: PackedFloat32Array = blocks[j + 1]
		for i in a.size():
			a[i] = b0[i] + b1[i]
		wins.append(a)
		energies.append(a[0])
	var se := energies.duplicate()
	se.sort()
	var med: float = se[se.size() / 2]
	# Etikett je Fenster: 0 = Haupttempo, >0 = fremde Periode (ms), -1 = still.
	var lab := PackedFloat64Array()
	lab.resize(nw)
	for j in nw:
		var a: PackedFloat32Array = wins[j]
		if a[0] < 0.05 * med:
			lab[j] = -1.0
			continue
		var pl := _pulse(a, lag_ms, P)
		var s_fam := 0.0
		var near := false
		for f in FAMILY:
			var lf: float = lag0 / float(f)
			for d in [-1.0, 0.0, 1.0]:
				s_fam = maxf(s_fam, _comb(a, lf + d))
			if absf(pl.x / lf - 1.0) <= float(P.foreign_tol):
				near = true
		if not near and s_fam < float(P.foreign_ratio) * pl.y:
			lab[j] = pl.x * lag_ms
	# Laeufe fremder Fenster mit gleichem Tempo.
	var runs: Array = []
	var j := 0
	while j < nw:
		if lab[j] <= 0.0:
			j += 1
			continue
		var j0 := j
		var per := [lab[j]]
		var j_last := j
		j += 1
		while j < nw and (lab[j] < 0.0 or (lab[j] > 0.0 and absf(lab[j] / float(per[0]) - 1.0) < 0.04)):
			if lab[j] > 0.0:
				per.append(lab[j])
				j_last = j
			j += 1
		if per.size() >= int(P.foreign_min_windows):
			per.sort()
			runs.append({"lo": j0 * _BLOCK_MS + _BLOCK_MS * 0.5,
					"hi": minf(dur, j_last * _BLOCK_MS + _BLOCK_MS * 1.5), "T": per[per.size() / 2]})
	if runs.is_empty():
		return out
	out = []
	var cur := 0.0
	for r in runs:
		if float(r.lo) - cur > _BLOCK_MS:
			out.append({"lo": cur, "hi": r.lo, "T": t_main})
		else:
			r.lo = cur
		out.append(r)
		cur = r.hi
	if dur - cur > _BLOCK_MS:
		out.append({"lo": cur, "hi": dur, "T": t_main})
	else:
		out[out.size() - 1].hi = dur
	return out


# ---------------------------------------------------------------------------
# Phasensummen, Regression
# ---------------------------------------------------------------------------

## Vector2(Betrag, Offset in ms) der gewichteten Phasensumme bei Periode T.
static func _res(ts: PackedFloat64Array, ws: PackedFloat64Array, T: float) -> Vector2:
	var sc := 0.0
	var ss := 0.0
	var k := TAU / T
	for i in ts.size():
		var th := ts[i] * k
		sc += ws[i] * cos(th)
		ss += ws[i] * sin(th)
	return Vector2(sqrt(sc * sc + ss * ss), fposmod(atan2(ss, sc) / TAU * T, T))


static func _scan(ts: PackedFloat64Array, ws: PackedFloat64Array, tc: float, rel: float, step: float, harms: Array) -> float:
	var best := -1.0
	var bt := tc
	var r := -rel
	while r <= rel:
		var T := tc * (1.0 + r)
		var s := 0.0
		for h in harms:
			s += _res(ts, ws, T / float(h)).x
		if s > best:
			best = s
			bt = T
		r += step
	return bt


## Phase (ms) mit dem meisten Anschlag-Gewicht bei Periode T. Anders als die Phase der
## Phasensumme liegt sie immer auf Anschlaegen (Swing: Summe zeigt zwischen Schlag und Achtel).
static func _best_phase(ts: PackedFloat64Array, ws: PackedFloat64Array, T: float) -> float:
	var nb := 48
	var hist := PackedFloat64Array()
	hist.resize(nb)
	for i in ts.size():
		hist[int(fposmod(ts[i], T) / T * nb) % nb] += ws[i]
	var bi := 0
	var bv := -1.0
	for i in nb:
		var v := hist[i] + 0.5 * (hist[posmod(i - 1, nb)] + hist[(i + 1) % nb])
		if v > bv:
			bv = v
			bi = i
	var ph := (bi + 0.5) * T / nb
	for _it in 2:
		var s := 0.0
		var sr := 0.0
		for i in ts.size():
			var r := fposmod(ts[i] - ph + T * 0.5, T) - T * 0.5
			if absf(r) <= T / 16.0:
				s += ws[i]
				sr += ws[i] * r
		if s > 0.0:
			ph += sr / s
	return fposmod(ph, T)


## Staerkste nmax Anschlaege im Indexbereich.
static func _top(F: Dictionary, i0: int, i1: int, nmax: int) -> Dictionary:
	var pt: PackedFloat64Array = F.pt
	var pw: PackedFloat64Array = F.pw
	var plw: PackedFloat64Array = F.plw
	var idx: Array = range(i0, i1)
	if idx.size() > nmax:
		idx.sort_custom(func(a, b): return pw[a] > pw[b])
		idx.resize(nmax)
	var t := PackedFloat64Array()
	var w := PackedFloat64Array()
	var lw := PackedFloat64Array()
	for i in idx:
		t.append(pt[i])
		w.append(pw[i])
		lw.append(plw[i])
	return {"t": t, "w": w, "lw": lw}


## Gewichtete Regression t = off + k * T ueber Anschlaege nahe am Raster.
static func _regress(pt: PackedFloat64Array, pw: PackedFloat64Array, i0: int, i1: int, T: float, off: float, win: float) -> Dictionary:
	var s := 0.0
	var sk := 0.0
	var skk := 0.0
	var st := 0.0
	var skt := 0.0
	var cnt := 0
	var k0 := roundf((pt[i0] - off) / T)
	for i in range(i0, i1):
		var k := roundf((pt[i] - off) / T)
		var r := pt[i] - off - k * T
		if absf(r) > win * T:
			continue
		var w := pw[i]
		var kk := k - k0
		var tt := pt[i] - pt[i0]
		s += w
		sk += w * kk
		skk += w * kk * kk
		st += w * tt
		skt += w * kk * tt
		cnt += 1
	var det := s * skk - sk * sk
	if cnt < 6 or absf(det) < 1e-6:
		return {"ok": false}
	var b := (s * skt - sk * st) / det
	var a := (st - b * sk) / s + pt[i0]
	return {"ok": true, "T": b, "off": a}


## Offset bei fester Periode: gewichtetes Mittel der Reste.
static func _phase_fix(pt: PackedFloat64Array, pw: PackedFloat64Array, i0: int, i1: int, T: float, off: float) -> float:
	for _it in 3:
		var s := 0.0
		var sr := 0.0
		for i in range(i0, i1):
			var r := pt[i] - off - roundf((pt[i] - off) / T) * T
			if absf(r) > 0.15 * T:
				continue
			s += pw[i]
			sr += pw[i] * r
		if s <= 0.0:
			break
		off += sr / s
	return off


## Anteil der Schlaege mit einem Anschlag in der Naehe.
static func _fill(pt: PackedFloat64Array, i0: int, i1: int, X: float, phase: float, lo: float, hi: float) -> float:
	var tol := clampf(0.07 * X, 12.0, 30.0)
	var k := ceilf((lo - phase) / X)
	var j := i0
	var hit := 0
	var cnt := 0
	while true:
		var t := phase + k * X
		if t > hi:
			break
		while j < i1 - 1 and pt[j] < t - tol:
			j += 1
		if j < i1 and absf(pt[j] - t) <= tol:
			hit += 1
		cnt += 1
		k += 1.0
	return float(hit) / maxi(cnt, 1)


## Mittlerer Akzent auf den Schlaegen: Vector2(Fluss, Bass).
static func _accent(F: Dictionary, X: float, phase: float, lo: float, hi: float) -> Vector2:
	var flux: PackedFloat32Array = F.flux
	var low: PackedFloat32Array = F.low
	var hop_ms: float = F.hop_ms
	var n := flux.size()
	var k := ceilf((lo - phase) / X)
	var sa := 0.0
	var sl := 0.0
	var cnt := 0
	while true:
		var t := phase + k * X
		if t > hi:
			break
		var f := int(t / hop_ms)
		var a := 0.0
		var l := 0.0
		for i in range(maxi(0, f - 2), mini(n, f + 3)):
			a = maxf(a, flux[i])
			l = maxf(l, low[i])
		sa += a
		sl += l
		cnt += 1
		k += 1.0
	return Vector2(sa / maxi(cnt, 1), sl / maxi(cnt, 1))


## Gefaltetes Onset-Profil bei Periode pd um phase: Vector2(Versatz des Maximums,
## Versatz des halben Anstiegs davor), in ms relativ zu phase.
static func _fold(F: Dictionary, lo: float, hi: float, pd: float, phase: float) -> Vector2:
	var flux: PackedFloat32Array = F.flux
	var hop_ms: float = F.hop_ms
	var nb := maxi(16, int(round(pd)))
	var prof := PackedFloat64Array()
	prof.resize(nb)
	var f0 := maxi(1, int(lo / hop_ms))
	var f1 := mini(flux.size(), int(hi / hop_ms))
	for i in range(f0, f1):
		var v := flux[i]
		if v <= 0.0:
			continue
		var x := fposmod((i + 0.5) * hop_ms - phase + pd * 0.5, pd) / pd * nb
		var b := int(x)
		if b >= nb:
			b = nb - 1
		var fr := x - b
		prof[b] += v * (1.0 - fr)
		prof[(b + 1) % nb] += v * fr
	var sm := PackedFloat64Array()
	sm.resize(nb)
	var base := INF
	for i in nb:
		var s := 0.0
		for d in range(-2, 3):
			s += prof[posmod(i + d, nb)]
		sm[i] = s / 5.0
		base = minf(base, sm[i])
	var c := nb / 2
	var span := nb / 4
	var bi := c
	for i in range(c - span, c + span + 1):
		if sm[i] > sm[bi]:
			bi = i
	var pk := float(bi)
	var ya := sm[posmod(bi - 1, nb)]
	var yc := sm[posmod(bi + 1, nb)]
	var den := ya - 2.0 * sm[bi] + yc
	if absf(den) > 1e-12:
		pk += clampf(0.5 * (ya - yc) / den, -0.5, 0.5)
	var lvl := base + 0.5 * (sm[bi] - base)
	var j := bi
	while j > bi - nb / 2 and sm[posmod(j - 1, nb)] > lvl:
		j -= 1
	var y1 := sm[posmod(j, nb)]
	var y0 := sm[posmod(j - 1, nb)]
	var hf := float(j)
	if y1 - y0 > 1e-12:
		hf = j - clampf((y1 - lvl) / (y1 - y0), 0.0, 1.0)
	var u := pd / nb
	return Vector2((pk - nb * 0.5) * u, (hf - nb * 0.5) * u)


# ---------------------------------------------------------------------------
# Hypothesen, Taktart, Taktanfang
# ---------------------------------------------------------------------------

static func _score(h: Dictionary, ref_bpm: float, P: Dictionary) -> float:
	var sup: float = float(h.r1) + float(P.w_half) * float(h.r2) + float(P.w_quarter) * float(h.r4) + float(P.w_low) * float(h.rl1)
	var oct: float = log(float(h.bpm) / float(P.prior_bpm)) / log(2.0) / float(P.prior_sigma_oct)
	var s: float = sup * pow(float(h.fill), float(P.fill_pow)) * exp(-0.5 * oct * oct)
	if ref_bpm > 0.0:
		s *= exp(-float(P.ref_pull) * absf(log(float(h.bpm) / ref_bpm) / log(2.0)))
	return s


## Taktart (4/3) und Taktanfang aus Statistik je Schlag. phase = Zeit des Schlags mit Index 0.
static func _meter(F: Dictionary, X: float, phase: float, lo: float, hi: float, P: Dictionary) -> Dictionary:
	var flux: PackedFloat32Array = F.flux
	var low: PackedFloat32Array = F.low
	var zc: PackedFloat32Array = F.zc
	var hop_ms: float = F.hop_ms
	var n := flux.size()
	var k0 := int(ceil((lo - phase) / X))
	var k1 := int(floor((hi - phase) / X)) - 1
	var nb := k1 - k0 + 1
	if nb < 16:
		return {"meter": 4, "db": phase + k0 * X, "q": 0.0, "db4": [], "db3": []}
	var feats: Array = [PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()]
	for a in feats:
		a.resize(nb)
	var zr := PackedFloat64Array()
	zr.resize(nb)
	var en := PackedFloat64Array()
	en.resize(nb)
	for j in nb:
		var t := phase + (k0 + j) * X
		var f := clampi(int(t / hop_ms), 0, n - 1)
		var f2 := clampi(int((t + X) / hop_ms), 0, n - 1)
		var a := 0.0
		var l := 0.0
		for i in range(maxi(0, f - 2), mini(n, f + 3)):
			a = maxf(a, flux[i])
			l = maxf(l, low[i])
		feats[1][j] = a
		feats[0][j] = l
		zr[j] = zc[f2] - zc[f]
		var e := 0.0
		for i in range(f, f2):
			e += flux[i]
		en[j] = e
	for j in range(1, nb):
		feats[2][j] = absf(zr[j] - zr[j - 1]) / (zr[j] + zr[j - 1] + 1.0)
	for j in range(4, nb - 4):
		var a := en[j] + en[j + 1] + en[j + 2] + en[j + 3]
		var b := en[j - 1] + en[j - 2] + en[j - 3] + en[j - 4]
		feats[3][j] = absf(a - b) / (a + b + 1e-6)
	var wts := [float(P.db_w_low), float(P.db_w_acc), float(P.db_w_hc), float(P.db_w_nov)]
	var res := {}
	for m in [4, 3]:
		var rows: Array = []
		for p in m:
			rows.append([0.0, 0.0, 0.0, 0.0])
		for fi in 4:
			var arr: PackedFloat64Array = feats[fi]
			var mean := 0.0
			for v in arr:
				mean += v
			mean /= nb
			var sd := 0.0
			for v in arr:
				sd += (v - mean) * (v - mean)
			sd = sqrt(sd / nb) + 1e-9
			var sums := PackedFloat64Array()
			sums.resize(m)
			var cnts := PackedFloat64Array()
			cnts.resize(m)
			for j in nb:
				var p := posmod(k0 + j, m)
				sums[p] += arr[j]
				cnts[p] += 1.0
			for p in m:
				if cnts[p] > 0.0:
					rows[p][fi] = (sums[p] / cnts[p] - mean) / (sd / sqrt(cnts[p]))
		res[m] = rows
	var out := {"db4": res[4], "db3": res[3]}
	var best := {}
	for m in [4, 3]:
		var bp := 0
		var bv := -INF
		for p in m:
			var d := 0.0
			for fi in 4:
				d += float(wts[fi]) * float(res[m][p][fi])
			if d > bv:
				bv = d
				bp = p
		best[m] = [bp, bv]
	var meter := 4
	if float(best[3][1]) > float(P.meter3_ratio) * maxf(float(best[4][1]), 0.0) and float(best[3][1]) > 4.0:
		meter = 3
	out["meter"] = meter
	out["db"] = phase + int(best[meter][0]) * X
	out["q"] = float(best[meter][1])
	out["s4"] = float(best[4][1])
	out["s3"] = float(best[3][1])
	return out


## Ein Segment [lo, hi] (ms) auswerten; tcs = Kandidaten der groben Periode (ms), jeder
## bringt seine Tempo-Familie mit, alle Hypothesen treten gegeneinander an.
static func _fit_segment(F: Dictionary, lo: float, hi: float, tcs: Array, ref_bpm: float, P: Dictionary) -> Dictionary:
	var pt: PackedFloat64Array = F.pt
	var pw: PackedFloat64Array = F.pw
	var i0 := pt.bsearch(lo)
	var i1 := pt.bsearch(hi)
	if i1 - i0 < 12:
		return {"ok": false}
	var top := _top(F, i0, i1, int(P.max_peaks))
	var ts: PackedFloat64Array = top.t
	var ws: PackedFloat64Array = top.w
	var lws: PackedFloat64Array = top.lw
	var sub := _top(F, i0, i1, int(P.scan_peaks))
	var D := maxf(hi - lo, 4000.0)
	var W := 0.0
	var WL := 0.0
	for i in ws.size():
		W += ws[i]
		WL += lws[i]
	W = maxf(W, 1e-9)
	WL = maxf(WL, 1e-9)
	var acf: PackedFloat32Array = F.acf
	var lag_ms: float = F.lag_ms
	var hyps: Array = []
	var t2s: Array = []
	for tc in tcs:
		var step := 0.25 * (float(tc) / 3.0) / D
		var T1 := _scan(sub.t, sub.w, tc, 0.03, step, [1, 2, 3])
		var T2 := _scan(ts, ws, T1, 2.0 * step, step * 0.1, [1, 2, 3, 4])
		t2s.append(T2)
		for f in FAMILY:
			var X: float = T2 / float(f)
			var bpm := 60000.0 / X
			if bpm < float(P.bpm_min) or bpm > float(P.bpm_max):
				continue
			var r := _res(ts, ws, X)
			var dup := -1
			for j in hyps.size():
				if absf(float(hyps[j].X) / X - 1.0) < 0.004:
					dup = j
			if dup >= 0 and float(hyps[dup].r1) >= r.x / W:
				continue
			var bp := _best_phase(ts, ws, X)
			var h := {"f": f, "X": X, "bpm": bpm, "phase": bp,
					"r1": r.x / W, "r2": _res(ts, ws, X / 2.0).x / W, "r4": _res(ts, ws, X / 4.0).x / W,
					"r3": _res(ts, ws, X / 3.0).x / W,
					"rl1": _res(ts, lws, X).x / WL, "rl2": _res(ts, lws, 2.0 * X).x / WL,
					"fill": _fill(pt, i0, i1, X, bp, lo, hi),
					"a1": _ai(acf, X / lag_ms) / maxf(acf[0], 1e-9), "a2": _ai(acf, 2.0 * X / lag_ms) / maxf(acf[0], 1e-9)}
			h["score"] = _score(h, ref_bpm, P)
			if dup >= 0:
				hyps[dup] = h
			else:
				hyps.append(h)
	if hyps.is_empty():
		return {"ok": false}
	hyps.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var T2: float = t2s[0]
	var win: Dictionary = hyps[0]
	var X: float = win.X
	# Feinste tragende Teilung fuer die Regression.
	var h_use := 1
	var m_best := float(win.r1)
	for hh in [[2, float(win.r2)], [4, float(win.r4)]]:
		if float(hh[1]) > 1.1 * m_best:
			m_best = hh[1]
			h_use = hh[0]
	var pd := X / h_use
	var off := _best_phase(ts, ws, pd)
	for wn in [0.25, 0.18, 0.12, 0.12]:
		var fit := _regress(pt, pw, i0, i1, pd, off, wn)
		if not fit.ok:
			break
		pd = fit.T
		off = fit.off
	X = pd * h_use
	var snapped := false
	var bpm_i := roundf(60000.0 / X)
	if bpm_i > 0.0 and absf(X - 60000.0 / bpm_i) * ((hi - lo) / X) <= float(P.snap_drift_ms):
		X = 60000.0 / bpm_i
		pd = X / h_use
		off = _phase_fix(pt, pw, i0, i1, pd, off)
		snapped = true
	# Schlag unter den Teilungen: Phase des Grundtons, auf das Teilraster gelegt.
	var ph := _best_phase(ts, ws, X)
	var phase := off + roundf((ph - off) / pd) * pd
	var acc0 := _accent(F, X, phase, lo, hi)
	var acc1 := _accent(F, X, phase + X * 0.5, lo, hi)
	var flipped := false
	if acc1.y > float(P.flip_low_ratio) * acc0.y and acc1.x > 0.8 * acc0.x:
		phase += X * 0.5
		flipped = true
	var fd := _fold(F, lo, hi, pd, phase)
	var half_delta := fd.y - fd.x
	phase += fd.x if String(P.phase_mode) == "peak" else fd.y
	var mt := _meter(F, X, phase, lo, hi, P)
	var alts: Array = []
	for i in range(1, hyps.size()):
		alts.append({"factor": snappedf(float(hyps[i].bpm) / float(win.bpm), 0.0001),
				"score": snappedf(float(hyps[i].score) / maxf(float(win.score), 1e-9), 0.001)})
	var margin := 1.0
	if hyps.size() > 1:
		margin = 1.0 - float(hyps[1].score) / maxf(float(win.score), 1e-9)
	var coh: float = float(win.r1) + float(win.r2) + float(win.r4)
	var conf := clampf(0.6 * minf(1.0, margin / 0.5) + 0.4 * minf(1.0, coh / 0.6), 0.0, 1.0)
	var res := {"ok": true, "X": X, "phase": phase, "pd": pd, "meter": mt.meter, "db": mt.db,
			"conf": conf, "alts": alts, "lo": lo, "hi": hi}
	if bool(P.debug):
		var ph4: Array = []
		var rl := _res(ts, lws, X)
		var ra := _res(ts, ws, X)
		for j in 4:
			var c := phase + j * X / 4.0
			var a := _accent(F, X, c, lo, hi)
			ph4.append([a.x, a.y, _fill(pt, i0, i1, X, c, lo, hi), cos(TAU * (c - rl.y) / X) * rl.x / WL,
					cos(TAU * (c - ra.y) / X) * ra.x / W])
		res["dbg"] = {"hyps": hyps, "T2": T2, "h_use": h_use, "snapped": snapped, "flipped": flipped,
				"half_delta": half_delta, "acc0": acc0, "acc1": acc1, "meter": mt, "phase": phase, "ph4": ph4}
	return res


## Grenze zwischen zwei Segmenten nahe rough: erster Anschlag, ab dem das Raster von b besser passt.
static func _boundary(F: Dictionary, a: Dictionary, b: Dictionary, rough: float, span: float) -> float:
	var pt: PackedFloat64Array = F.pt
	var pw: PackedFloat64Array = F.pw
	var i0 := pt.bsearch(rough - span)
	var i1 := pt.bsearch(rough + span)
	if i1 - i0 < 4:
		return rough
	var ka: float = TAU / float(a.pd)
	var kb: float = TAU / float(b.pd)
	var tot_b := 0.0
	for i in range(i0, i1):
		tot_b += pw[i] * cos((pt[i] - float(b.phase)) * kb)
	var best := -INF
	var bi := i0
	var pa := 0.0
	var pb := 0.0
	for i in range(i0, i1 + 1):
		var v := pa + (tot_b - pb)
		if v > best:
			best = v
			bi = i
		if i < i1:
			pa += pw[i] * cos((pt[i] - float(a.phase)) * ka)
			pb += pw[i] * cos((pt[i] - float(b.phase)) * kb)
	return pt[mini(bi, i1 - 1)]


## Wie track(), aber ab dem Ergebnis von envelope() (Messskript: Fluss wird zwischengespeichert).
static func track_env(feat: Dictionary, params: Dictionary = {}) -> Dictionary:
	var P := _cfg(params)
	var flux: PackedFloat32Array = feat.flux
	var hop_ms: float = feat.hop_ms
	var dur := flux.size() * hop_ms
	if dur < 4000.0:
		return _fail("Audio kuerzer als 4 s")
	var pk := _peaks(flux, feat.low, hop_ms)
	if pk.t.size() < 16:
		return _fail("Keine Anschlaege gefunden (Stille?)")
	var ac := _acf_blocks(flux, hop_ms)
	var F := {"flux": flux, "low": feat.low, "zc": feat.zc, "hop_ms": hop_ms,
			"pt": pk.t, "pw": pk.w, "plw": pk.lw, "acf": ac.glob, "lag_ms": ac.lag_ms}
	var p0 := _pulse(ac.glob, ac.lag_ms, P)
	if p0.y <= 0.0:
		return _fail("Kein Puls gefunden")
	var rough := _rough_segments(ac, p0.x, dur, P)
	# Laengstes Segment zuerst: es legt die Tempo-Ebene fest.
	var main_i := 0
	for i in rough.size():
		if float(rough[i].hi) - float(rough[i].lo) > float(rough[main_i].hi) - float(rough[main_i].lo):
			main_i = i
	var fits: Array = []
	fits.resize(rough.size())
	var mr: Dictionary = rough[main_i]
	var cands: Array = [float(mr.T)]
	for c in _pulse_cands(ac.glob, ac.lag_ms, P):
		if absf(float(c) / float(mr.T) - 1.0) >= 0.04:
			cands.append(c)
	var mfit := _fit_segment(F, mr.lo, mr.hi, cands, 0.0, P)
	if not mfit.ok and rough.size() > 1:
		mfit = _fit_segment(F, 0.0, dur, [p0.x * float(ac.lag_ms)], 0.0, P)
		rough = [{"lo": 0.0, "hi": dur, "T": p0.x * float(ac.lag_ms)}]
		fits = [null]
		main_i = 0
	if not mfit.ok:
		return _fail("Zu wenige Anschlaege fuer ein Raster")
	fits[main_i] = mfit
	var ref_bpm: float = 60000.0 / float(mfit.X)
	for i in rough.size():
		if i == main_i:
			continue
		var r: Dictionary = rough[i]
		var len := float(r.hi) - float(r.lo)
		var mg := minf(2000.0, 0.2 * len) if rough.size() > 1 else 0.0
		fits[i] = _fit_segment(F, float(r.lo) + mg, float(r.hi) - mg, [float(r.T)], ref_bpm, P)
	var list: Array = []
	for i in rough.size():
		var ft: Dictionary = fits[i]
		if not ft.ok:
			continue
		ft["rough_lo"] = rough[i].lo
		ft["main"] = i == main_i
		# Gleiches Tempo und gleiche Phase wie der Vorgaenger: zusammenlegen.
		if not list.is_empty():
			var pv: Dictionary = list[list.size() - 1]
			var d: float = fposmod(float(ft.phase) - float(pv.phase) + float(pv.X) * 0.5, float(pv.X)) - float(pv.X) * 0.5
			if absf(float(ft.X) / float(pv.X) - 1.0) < 0.001 and absf(d) < 0.08 * float(pv.X):
				if ft.main:
					ft["rough_lo"] = pv.rough_lo
					list[list.size() - 1] = ft
				continue
		list.append(ft)
	var lead: float = P.lead_ms
	var segs: Array = []
	var main_out: Dictionary = mfit
	for i in list.size():
		var ft: Dictionary = list[i]
		var X: float = ft.X
		var start: float
		if i == 0:
			start = float(ft.phase) + roundf((pk.t[0] - float(ft.phase)) / X) * X
		else:
			var bt := _boundary(F, list[i - 1], ft, ft.rough_lo, 6000.0)
			start = float(ft.phase) + roundf((bt - float(ft.phase)) / X) * X
			# Der Wechsel greift meist auf einem Schlag des alten Tempos: liegt der Schlag
			# davor auch auf dem alten Raster, beginnt das Segment dort.
			var pa: Dictionary = list[i - 1]
			var c := start - X
			var da: float = fposmod(c - float(pa.phase) + float(pa.X) * 0.5, float(pa.X)) - float(pa.X) * 0.5
			if absf(da) < 0.08 * float(pa.X) and c > bt - 1.5 * X:
				start = c
		start -= lead
		while start < 0.0:
			start += X
		var bar := X * int(ft.meter)
		var db := start + fposmod(float(ft.db) - lead - start, bar)
		if bar - (db - start) < 0.5:
			db = start
		segs.append({"start_ms": start, "beat_ms": X, "meter": int(ft.meter), "downbeat_ms": db,
				"bpm": 60000.0 / X})
		if ft.main:
			main_out = ft
	var grid := {"ok": true, "error": "", "segments": segs, "confidence": main_out.conf,
			"alternatives": main_out.alts}
	if bool(P.debug):
		grid["debug"] = main_out.get("dbg", {})
		grid["debug"]["rough"] = rough
	return grid
