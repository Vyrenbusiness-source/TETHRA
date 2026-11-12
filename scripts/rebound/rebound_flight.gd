class_name ReboundFlight
extends RefCounted

## Rebound: Bahnen der vier Baelle, rein aus der Mania-Notenliste (deterministisch,
## ohne Zufall, ohne Wertung). Je Spalte eine Folge von Fluegen:
##   Start = Ende der vorigen Note derselben Spalte (Hold: Hold-Ende), Landung =
##   Notenzeit (exakt). Pause > MAX_AIR_MS oder erste Note: Ball faellt von oben
##   herein (Fallzeit = drop_ms, nur Optik). Gipfelhoehe ~ Flugzeit^2, gedeckelt.
##   Hold: Ball liegt gequetscht auf dem Fell bis zum Hold-Ende.
## Hoehe ist normiert: 0 = Fellflaeche, 1 = hoechster Gipfel. Seitlich x in -1..1
## (Einheit "a" der Ansicht): die Landepunkte wechseln links/rechts, damit
## Bogen und Geister-Bogen lesbar bleiben.

## Pausen darueber: Ball faellt herein.
const MAX_AIR_MS := 1600.0
## Flugzeit, ab der die volle Gipfelhoehe erreicht ist.
const ARC_FULL_MS := 1200.0
const MIN_PEAK := 0.045
const DROP_MIN_MS := 600.0
const DROP_MAX_MS := 1600.0
const DROP_DEFAULT_MS := 1000.0
## Starthoehe beim Hereinfallen (ueber dem Gipfel, ausserhalb des Bildes).
const FALL_H := 1.12
## Nach der letzten Note vor einer Pause: kleiner Auslauf-Huepfer.
const EXIT_MS := 420.0
const EXIT_PEAK := 0.13
## Flugzeit, ab der der seitliche Schwung voll ist.
const SWING_FULL_MS := 600.0
const SWING_MIN := 0.25

enum Kind { HIDDEN, AIR, FALL, REST, EXIT }

class Seg extends RefCounted:
	var idx := 0          ## Index in beatmap.hit_objects
	var col := 0
	var t0 := 0.0         ## Start des Flugs
	var t1 := 0.0         ## Landung = Notenzeit
	var free := 0.0       ## Ball wieder frei (Hold-Ende, sonst t1)
	var fall := false     ## true = Hereinfallen
	var peak := 0.0       ## Gipfelhoehe 0..1 (Luftflug)
	var x0 := 0.0
	var x1 := 0.0
	var hold := false
	var first_free := false  ## folgt ein Folgeflug direkt (Luftflug) an free?
	func dur() -> float:
		return t1 - t0

var columns := 4
var drop_ms := DROP_DEFAULT_MS
## Je Spalte: Array[Seg] nach Landezeit.
var segs: Array = []


static func peak_for(flight_ms: float) -> float:
	var q := clampf(flight_ms / ARC_FULL_MS, 0.0, 1.0)
	return clampf(q * q, MIN_PEAK, 1.0)


static func clamp_drop(ms: float) -> float:
	return clampf(ms, DROP_MIN_MS, DROP_MAX_MS)


## Aus einer Mania-Beatmap (ManiaNote in hit_objects).
static func from_beatmap(bm: Beatmap, p_drop_ms: float = DROP_DEFAULT_MS) -> ReboundFlight:
	var notes: Array = []
	for i in bm.hit_objects.size():
		var o := bm.hit_objects[i]
		if o is ManiaNote:
			var n := o as ManiaNote
			notes.append([n.time, n.end_time(), n.column, i, n.is_hold])
	return from_notes(notes, bm.column_count(), p_drop_ms)


## notes: [[t, end, col, idx, is_hold], ...] (Reihenfolge egal).
static func from_notes(notes: Array, p_columns: int = 4, p_drop_ms: float = DROP_DEFAULT_MS) -> ReboundFlight:
	var f := ReboundFlight.new()
	f.columns = maxi(p_columns, 1)
	f.drop_ms = clamp_drop(p_drop_ms)
	var per: Array = []
	for c in f.columns:
		per.append([])
		f.segs.append([])
	for n in notes:
		var c: int = clampi(int(n[2]), 0, f.columns - 1)
		per[c].append(n)
	for c in f.columns:
		var list: Array = per[c]
		list.sort_custom(func(a, b): return float(a[0]) < float(b[0]) \
				or (float(a[0]) == float(b[0]) and int(a[3]) < int(b[3])))
		var prev: Seg = null
		var swing := 0   # Zaehler aufeinanderfolgender Luftfluege (Seitenwechsel)
		for n in list:
			var s := Seg.new()
			s.idx = int(n[3])
			s.col = c
			s.t1 = float(n[0])
			s.free = maxf(float(n[1]), s.t1)
			s.hold = bool(n[4]) and s.free > s.t1
			if prev != null and s.t1 - prev.free <= MAX_AIR_MS and s.t1 - prev.free > 0.0:
				s.fall = false
				s.t0 = prev.free
				s.peak = peak_for(s.t1 - s.t0)
				s.x0 = prev.x1
				swing += 1
				var side := 1.0 if swing % 2 == 1 else -1.0
				s.x1 = side * clampf((s.t1 - s.t0) / SWING_FULL_MS, SWING_MIN, 1.0) * 0.5
				if absf(s.x1 - s.x0) > 1.0:
					s.x1 = clampf(s.x1, s.x0 - 1.0, s.x0 + 1.0)
				prev.first_free = true
			elif prev != null and s.t1 - prev.free <= 0.0:
				# Gleichzeitig/ueberlappend (kein gueltiges Mania): kurzer Huepfer am Ort.
				s.fall = false
				s.t0 = s.t1 - 40.0
				s.peak = MIN_PEAK
				s.x0 = prev.x1
				s.x1 = prev.x1
			else:
				s.fall = true
				s.t0 = s.t1 - f.drop_ms
				s.peak = FALL_H
				swing = 0
				s.x0 = 0.0
				s.x1 = 0.0
			f.segs[c].append(s)
			prev = s
	return f


func seg_count(c: int) -> int:
	return (segs[c] as Array).size()


## Erster Flug der Spalte, dessen Landung bei oder nach t liegt (-1 = keiner).
func first_landing_at_or_after(c: int, t: float) -> int:
	var arr: Array = segs[c]
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if (arr[mid] as Seg).t1 >= t:
			hi = mid
		else:
			lo = mid + 1
	return lo if lo < arr.size() else -1


## Letzte Landung bis t (Index, -1 = keine).
func last_landing_before(c: int, t: float) -> int:
	var arr: Array = segs[c]
	var lo := 0
	var hi := arr.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if (arr[mid] as Seg).t1 > t:
			hi = mid
		else:
			lo = mid + 1
	return lo - 1


## Ball der Spalte c zur Zeit t:
## {kind, h (0..1+), x, alpha, seg (Index des Zielflugs/aktueller Hold, -1), p (0..1),
##  since (ms seit letzter Landung, 1e9 = nie), until (ms bis naechste Landung, 1e9 = keine),
##  vy (Hoehe/ms, + = steigt)}
func ball(c: int, t: float) -> Dictionary:
	var arr: Array = segs[c]
	var out := {"kind": Kind.HIDDEN, "h": 0.0, "x": 0.0, "alpha": 0.0, "seg": -1, "p": 0.0,
			"since": 1e9, "until": 1e9, "vy": 0.0}
	if arr.is_empty():
		return out
	var k := first_landing_at_or_after(c, t)
	var prev_i := last_landing_before(c, t)
	if prev_i >= 0:
		out.since = t - (arr[prev_i] as Seg).t1
	if k >= 0:
		out.until = (arr[k] as Seg).t1 - t
	# Im Flug zur naechsten Landung?
	if k >= 0:
		var s := arr[k] as Seg
		if t >= s.t0:
			var p := clampf((t - s.t0) / maxf(s.t1 - s.t0, 1.0), 0.0, 1.0)
			out.seg = k
			out.p = p
			out.alpha = 1.0
			out.x = lerpf(s.x0, s.x1, p)
			if s.fall:
				out.kind = Kind.FALL
				out.h = FALL_H * (1.0 - p * p)
				out.vy = -2.0 * FALL_H * p / maxf(s.dur(), 1.0)
			else:
				out.kind = Kind.AIR
				out.h = 4.0 * s.peak * p * (1.0 - p)
				out.vy = 4.0 * s.peak * (1.0 - 2.0 * p) / maxf(s.dur(), 1.0)
			return out
	# Davor: Hold-Ruhe oder Auslauf der letzten Landung?
	if prev_i >= 0:
		var q := arr[prev_i] as Seg
		out.x = q.x1
		if q.hold and t < q.free:
			out.kind = Kind.REST
			out.seg = prev_i
			out.alpha = 1.0
			out.p = clampf((t - q.t1) / maxf(q.free - q.t1, 1.0), 0.0, 1.0)
			return out
		if k >= 0 and not (arr[k] as Seg).fall:
			# Direkt im Anschluss geht der Luftflug los (t0 == free): nur Rundungsfall.
			out.kind = Kind.AIR
			out.seg = k
			out.alpha = 1.0
			out.h = 0.0
			return out
		var e := t - q.free
		if e >= 0.0 and e < EXIT_MS:
			var pe := e / EXIT_MS
			out.kind = Kind.EXIT
			out.seg = prev_i
			out.p = pe
			out.h = 4.0 * EXIT_PEAK * pe * (1.0 - pe)
			out.vy = 4.0 * EXIT_PEAK * (1.0 - 2.0 * pe) / EXIT_MS
			out.alpha = 1.0 - pe * pe
	return out


## Ende der letzten Note (fuer Tests/Zeitleiste).
func last_time() -> float:
	var m := 0.0
	for c in columns:
		var arr: Array = segs[c]
		if not arr.is_empty():
			m = maxf(m, (arr[arr.size() - 1] as Seg).free)
	return m
