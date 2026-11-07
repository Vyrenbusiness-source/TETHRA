class_name ScrollMap
extends RefCounted

## Scroll-Velocity-Positionstabelle wie osu!lazer mania (SequentialScrollAlgorithm
## + MultiplierControlPoint, RelativeScaleBeatLengths): Geschwindigkeit eines
## Abschnitts = SV der gruenen Linie * BaseBeatLength / beatLength der roten Linie.
## position(t) ist stueckweise linear (ms-Einheiten); Abstand einer Note zur
## Trefferlinie = position(hit) - position(t). Ohne SV-/BPM-Wechsel (alle
## Multiplikatoren 1) gilt position(t) == t exakt (bitgenau wie vorher).
##
## SV-Mod (Stufe Stark): eine gruene Linie mit Meta SV_META ("sv_mult") traegt
## den Multiplikator m direkt, auch NEGATIV (Reverse/Rueck-Sprung: die Noten
## laufen kurz nach oben). position(t) ist dann nicht mehr monoton; time_at()
## liefert den ERSTEN Zeitpunkt, an dem eine Position erreicht ist (laufendes
## Maximum), spawn_time() damit den ersten Moment im Sichtfenster.

const BL_MIN := 6.0
const BL_MAX := 60000.0
const SV_MIN := 0.01
const SV_MAX := 10.0
const DEFAULT_BL := 1000.0
## Meta-Schluessel fuer direkt gesetzte (auch negative) Multiplikatoren.
const SV_META := &"sv_mult"

## Kontrollpunkt-Zeiten, kumulative Positionen und Multiplikatoren (parallel).
var _times := PackedFloat64Array()
var _pos := PackedFloat64Array()
var _mult := PackedFloat64Array()
## Laufendes Maximum von _pos (fuer time_at bei nicht-monotoner Position).
var _pmax := PackedFloat64Array()
var _identity := true
var _monotone := true
var base_beat_length := DEFAULT_BL


static func red_beat_length(tp: TimingPoint) -> float:
	return clampf(tp.beat_length, BL_MIN, BL_MAX)


static func green_sv(tp: TimingPoint) -> float:
	var bl := tp.beat_length
	if is_nan(bl) or bl == 0.0 or bl > 0.0:
		return 1.0
	return clampf(100.0 / -bl, SV_MIN, SV_MAX)


## C#-Math.Round (Banker's Rounding) auf 3 Nachkommastellen.
static func _round3(x: float) -> float:
	var y := x * 1000.0
	var r := roundf(y)
	if absf(y - floorf(y) - 0.5) == 0.0 and fmod(r, 2.0) != 0.0:
		r -= signf(y)
	return r / 1000.0


## Baut die Tabelle. map_end_ms = groesste Endzeit aller Objekte (Holds: end_time).
func build(timing_points: Array, map_end_ms: float) -> void:
	_times.clear()
	_pos.clear()
	_mult.clear()
	_pmax.clear()
	_identity = true
	_monotone = true
	# Stabile Sortierung: Zeit, dann rot vor gruen, dann Array-Index.
	var order: Array = []
	for i in timing_points.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta: TimingPoint = timing_points[a]
		var tb: TimingPoint = timing_points[b]
		if ta.time != tb.time:
			return ta.time < tb.time
		if ta.uninherited != tb.uninherited:
			return ta.uninherited
		return a < b)
	var reds: Array = []
	for i in order:
		var tp: TimingPoint = timing_points[i]
		if tp.uninherited:
			reds.append(tp)
	base_beat_length = _most_common_beat_length(reds, map_end_ms)
	# Vor der ersten roten Linie gilt deren Tempo (lazer: TimingPointAt faellt
	# auf den ersten Punkt zurueck), nicht DEFAULT_BL.
	var bl := red_beat_length(reds[0]) if not reds.is_empty() else DEFAULT_BL
	var sv := 1.0
	for i in order:
		var tp: TimingPoint = timing_points[i]
		if tp.uninherited:
			bl = red_beat_length(tp)
			sv = 1.0
		else:
			sv = green_sv(tp)
		if tp.time > map_end_ms:
			continue
		var m := sv * base_beat_length / bl
		if not tp.uninherited and tp.has_meta(SV_META):
			m = float(tp.get_meta(SV_META))
		var n := _times.size()
		if n > 0 and _times[n - 1] == tp.time:
			_mult[n - 1] = m
		else:
			_times.append(tp.time)
			_mult.append(m)
	for i in _times.size():
		if i == 0:
			_pos.append(0.0)
		else:
			_pos.append(_pos[i - 1] + (_times[i] - _times[i - 1]) * _mult[i - 1])
		if _mult[i] != 1.0:
			_identity = false
		if _mult[i] <= 0.0:
			_monotone = false
		_pmax.append(_pos[i] if i == 0 else maxf(_pmax[i - 1], _pos[i]))


static func _most_common_beat_length(reds: Array, last_time: float) -> float:
	if reds.is_empty():
		return DEFAULT_BL
	var keys: Array[float] = []
	var durs: Array[float] = []
	var lo := INF
	var hi := -INF
	for i in reds.size():
		var tp: TimingPoint = reds[i]
		var bl := red_beat_length(tp)
		lo = minf(lo, bl)
		hi = maxf(hi, bl)
		var d := 0.0
		if tp.time <= last_time:
			var start := 0.0 if i == 0 else tp.time
			var stop: float = last_time if i == reds.size() - 1 else (reds[i + 1] as TimingPoint).time
			d = stop - start
		var key := _round3(bl)
		var k := keys.find(key)
		if k < 0:
			keys.append(key)
			durs.append(d)
		else:
			durs[k] += d
	var best := 0
	for k in keys.size():
		if durs[k] > durs[best]:
			best = k
	var res := keys[best]
	if res == 0.0:
		res = DEFAULT_BL
	return clampf(res, lo, hi)


func is_identity() -> bool:
	return _identity


## false, wenn ein Abschnitt rueckwaerts (m <= 0) laeuft.
func is_monotone() -> bool:
	return _monotone


## Index des letzten Kontrollpunkts mit time <= t (0 fuer t davor).
func _seg_by_time(t: float) -> int:
	var lo := 0
	var hi := _times.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _times[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _seg_by_pos(p: float) -> int:
	var lo := 0
	var hi := _pos.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _pos[mid] <= p:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Scroll-Position (ms-Einheiten) zur Zeit t_ms. O(log n), keine Allokation.
func position(t_ms: float) -> float:
	if _identity or _times.is_empty():
		return t_ms
	var k := _seg_by_time(t_ms)
	return _pos[k] + (t_ms - _times[k]) * _mult[k]


## Inverse von position(): Zeit, zu der die Scroll-Position p erreicht ist.
## Nicht monoton (Reverse): der ERSTE Zeitpunkt mit position(t) >= p.
func time_at(p: float) -> float:
	if _identity or _times.is_empty():
		return p
	if _monotone:
		var k := _seg_by_pos(p)
		return _times[k] + (p - _pos[k]) / _mult[k]
	# Erster Kontrollpunkt j mit laufendem Maximum >= p.
	var n := _pmax.size()
	if p > _pmax[n - 1]:
		var kl := n - 1
		return _times[kl] + (p - _pos[kl]) / _mult[kl] if _mult[kl] > 0.0 else _times[kl]
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _pmax[mid] >= p:
			hi = mid
		else:
			lo = mid + 1
	if lo == 0:
		return _times[0] + (p - _pos[0]) / _mult[0] if _mult[0] > 0.0 else _times[0]
	if _pos[lo] == p:
		return _times[lo]
	# Abschnitt lo-1 steigt (pmax[lo-1] < p <= pos[lo]): dort wird p ueberquert.
	return _times[lo - 1] + (p - _pos[lo - 1]) / _mult[lo - 1]


## Zeitpunkt, ab dem eine Note mit Trefferzeit hit_ms sichtbar ist
## (position(hit) - position(t) <= view; bei Reverse der erste solche Moment).
func spawn_time(hit_ms: float, view: float) -> float:
	if _identity or _times.is_empty():
		return hit_ms - view
	return time_at(position(hit_ms) - view)
