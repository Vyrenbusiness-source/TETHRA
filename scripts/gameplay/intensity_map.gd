class_name IntensityMap
extends RefCounted

## Musikalische "Groesse" jedes Moments, einmal beim Map-Start berechnet.
## Notendichte (gleitend ueber 2 Beats), Kiai, Breaks, Aufbau, Drops.
## Abfragen sind O(log n) auf vorab berechneten Tabellen.

const STEP_MS := 100.0
const BREAK_BEATS := 4.0     # Notenluecke ab dieser Laenge = Break
const MIN_REF_DENSITY := 4.0 # Noten/s, darunter gilt die Map nie als "voll"
const KIAI_BOOST := 0.15
const DROP_BARS := 2         # is_drop_at gilt so viele Takte nach dem Drop
const SECTION_BARS := 32
const MIN_DROP_GAP_BARS := 8

var _times := PackedFloat64Array()   # sortierte Notenzeiten
var _grid_values := PackedFloat32Array()
var _drops := PackedFloat64Array()
var _sections := PackedFloat64Array()
var _beat_ms := 500.0
var _bar_ms := 2000.0
var _origin := 0.0
var _ref := MIN_REF_DENSITY


func build(beatmap: Beatmap) -> void:
	_times = PackedFloat64Array()
	_grid_values = PackedFloat32Array()
	_drops = PackedFloat64Array()
	_sections = PackedFloat64Array()
	_beat_ms = 500.0
	_bar_ms = 2000.0
	_origin = 0.0
	if beatmap == null:
		return
	var meter := 4
	for tp in beatmap.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			_beat_ms = tp.beat_length
			meter = maxi(tp.meter, 1)
			_origin = tp.time
			break
	_bar_ms = _beat_ms * meter
	var arr: Array = []
	for h in beatmap.hit_objects:
		arr.append(h.time)
	arr.sort()
	_times = PackedFloat64Array(arr)
	if _times.is_empty():
		return
	var end_t: float = _times[_times.size() - 1]
	var n := int(ceil(end_t / STEP_MS)) + 2

	# 1) Rohdichte (Noten/s, Fenster = 2 Beats zentriert)
	var dens := PackedFloat32Array()
	dens.resize(n)
	for i in n:
		var t := i * STEP_MS
		dens[i] = _count(t - _beat_ms, t + _beat_ms) / (2.0 * _beat_ms / 1000.0)
	# 2) Glaetten (Box ueber 1 Beat)
	var r := maxi(int(round(_beat_ms * 0.5 / STEP_MS)), 1)
	var sm := PackedFloat32Array()
	sm.resize(n)
	var maxd := 0.0
	for i in n:
		var s := 0.0
		var c := 0
		for j in range(maxi(i - r, 0), mini(i + r, n - 1) + 1):
			s += dens[j]
			c += 1
		sm[i] = s / c
		maxd = maxf(maxd, sm[i])
	_ref = maxf(maxd, MIN_REF_DENSITY)

	# 3) Normieren + Kiai-Zuschlag
	_grid_values.resize(n)
	for i in n:
		var v: float = sm[i] / _ref
		if beatmap.is_kiai(i * STEP_MS):
			v += KIAI_BOOST
		_grid_values[i] = clampf(v, 0.0, 1.0)

	_find_drops(beatmap)
	_find_sections(beatmap, end_t)


## Anzahl Noten in [a, b).
func _count(a: float, b: float) -> int:
	return _times.bsearch(b, true) - _times.bsearch(a, true)


func _span_density(a: float, b: float) -> float:
	return _count(a, b) / ((b - a) / 1000.0)


func _find_drops(beatmap: Beatmap) -> void:
	var cands: Array = []   # [zeit, prioritaet]
	var gap := _beat_ms * BREAK_BEATS
	var post_len := _bar_ms * DROP_BARS
	# Break-Ende: erste Note nach langer Luecke
	for i in range(1, _times.size()):
		if _times[i] - _times[i - 1] >= gap:
			if _span_density(_times[i], _times[i] + post_len) >= 0.4 * _ref:
				cands.append([_times[i], 2])
	# Kiai-Start
	for iv in beatmap.kiai_intervals:
		if iv.start > 0.0:
			cands.append([float(iv.start), 3])
	# Aufbau: Dichte steigt Takt fuer Takt, dann Sprung
	var end_t: float = _times[_times.size() - 1]
	var b: float = _origin + _bar_ms * 2.0
	while b < end_t:
		var nxt := _span_density(b, b + _bar_ms)
		var p1 := _span_density(b - _bar_ms, b)
		var p2 := _span_density(b - 2.0 * _bar_ms, b - _bar_ms)
		if p1 > p2 and p1 > 0.0 and nxt >= 1.6 * p1 and nxt >= 0.6 * _ref:
			cands.append([b, 1])
		b += _bar_ms
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var min_gap := _bar_ms * MIN_DROP_GAP_BARS
	var last := -INF
	for c in cands:
		if c[0] - last >= min_gap or (c[1] >= 2 and c[0] - last >= post_len):
			_drops.append(c[0])
			last = c[0]


func _find_sections(beatmap: Beatmap, end_t: float) -> void:
	var bounds: Array = []
	for iv in beatmap.kiai_intervals:
		if iv.start > 0.0:
			bounds.append(float(iv.start))
	var gap := _beat_ms * BREAK_BEATS
	for i in range(1, _times.size()):
		if _times[i] - _times[i - 1] >= gap:
			bounds.append(_times[i])
	var t := _origin + _bar_ms * SECTION_BARS
	while t < end_t:
		bounds.append(t)
		t += _bar_ms * SECTION_BARS
	bounds.sort()
	for x in bounds:
		if _sections.is_empty() or x > _sections[_sections.size() - 1]:
			_sections.append(x)


## Intensitaet 0..1 (linear zwischen Tabellenpunkten).
func value_at(t_ms: float) -> float:
	var n := _grid_values.size()
	if n == 0:
		return 0.0
	var f := clampf(t_ms / STEP_MS, 0.0, float(n - 1))
	var i := int(f)
	if i >= n - 1:
		return _grid_values[n - 1]
	return lerpf(_grid_values[i], _grid_values[i + 1], f - i)


## Erste DROP_BARS Takte nach einem Drop.
func is_drop_at(t_ms: float) -> bool:
	var i := _drops.bsearch(t_ms, false) - 1  # letzter Drop <= t
	return i >= 0 and t_ms < _drops[i] + _bar_ms * DROP_BARS


## Abschnittsindex (0-basiert); wechselt an Kiai-Start, Break-Ende, alle 32 Takte.
func section_index(t_ms: float) -> int:
	return _sections.bsearch(t_ms, false)


func drops() -> PackedFloat64Array:
	return _drops
