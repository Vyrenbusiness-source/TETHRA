class_name BeatQuantizer
extends Node

## Legt Ereignis-Effekte auf das Beat-Raster.
## schedule(callable, grid): 1 = naechster Beat, 2 = naechster halber Takt
## (jeder 2. Beat), 4 = naechster Downbeat. Ist die Kante weiter als MAX_DELAY_MS
## entfernt, wird sofort ausgeloest. process(t_ms) einmal pro Frame aufrufen;
## faellige Callables laufen in dem Frame, in dem die Kante ueberschritten wird.
## Rueckwaertssprung (Retry/Seek) verwirft alle wartenden Callables.

const MAX_DELAY_MS := 300.0

var _red_t: Array[float] = []
var _red_len: Array[float] = []
var _red_meter: Array[int] = []
var _cbs: Array[Callable] = []
var _due: PackedFloat64Array = PackedFloat64Array()
var _n: int = 0
var _t: float = 0.0
var _has_t: bool = false


func setup(timing_points: Array) -> void:
	_red_t.clear()
	_red_len.clear()
	_red_meter.clear()
	var pts: Array = timing_points.duplicate()
	pts.sort_custom(func(a, b): return a.time < b.time)
	for tp in pts:
		if tp.uninherited and tp.beat_length > 0.0:
			_red_t.append(tp.time)
			_red_len.append(tp.beat_length)
			_red_meter.append(maxi(tp.meter, 1))
	clear()
	_has_t = false


func clear() -> void:
	_cbs.clear()
	_due.resize(0)
	_n = 0


func pending() -> int:
	return _n


func schedule(callable: Callable, grid: int = 1) -> void:
	var edge := _next_edge(_t, grid)
	if not _has_t or edge < 0.0 or edge - _t > MAX_DELAY_MS:
		callable.call()
		return
	_cbs.append(callable)
	_due.append(edge)
	_n += 1


func process(t_ms: float) -> void:
	if _has_t and t_ms < _t:
		clear()
	_t = t_ms
	_has_t = true
	var i := 0
	while i < _n:
		if _due[i] <= t_ms:
			var c: Callable = _cbs[i]
			_cbs.remove_at(i)
			for j in range(i, _n - 1):
				_due[j] = _due[j + 1]
			_n -= 1
			_due.resize(_n)
			c.call()
		else:
			i += 1


## Zeit der naechsten Rasterkante strikt nach t, -1 ohne Timing-Daten.
func _next_edge(t: float, grid: int) -> float:
	if _red_t.is_empty():
		return -1.0
	var rp := 0
	while rp + 1 < _red_t.size() and _red_t[rp + 1] <= t:
		rp += 1
	var bl: float = _red_len[rp]
	var meter: int = _red_meter[rp]
	var step: int = meter if grid >= 4 else maxi(grid, 1)
	var k: int = int(floor((t - _red_t[rp]) / bl)) + 1
	while posmod(k, step) != 0:
		k += 1
	var edge: float = _red_t[rp] + float(k) * bl
	if rp + 1 < _red_t.size() and _red_t[rp + 1] < edge:
		edge = _red_t[rp + 1]
	return edge
