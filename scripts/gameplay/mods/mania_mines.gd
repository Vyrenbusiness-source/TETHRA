class_name ManiaMines
extends RefCounted

## Minen eines Laufs (Mod "MN"): Zustand und Ausloese-Regel, ohne Darstellung.
## Eine Mine steht von T - WINDOW_MS bis T + WINDOW_MS auf der Linie. Ist die Taste
## ihrer Spalte in dieser Zeit irgendwann unten (gedrueckt oder gehalten), loest sie
## aus; sonst ist sie sicher vorbei. Alle Zeiten sind Event-Zeiten (Replay-fest).
## ManiaCore ruft key_down/key_up/update und wertet die gelieferten Indizes als Miss.

const WINDOW_MS := 30.0

const PENDING := 0
const DODGED := 1
const HIT := 2

var times := PackedFloat64Array()
var cols := PackedInt32Array()
var state := PackedByteArray()
var _lane: Array = []        ## je Spalte: Minen-Indizes nach Zeit
var _head: Array[int] = []   ## je Spalte: erste offene Position in _lane
var _held: Array[bool] = []
var _down_since: Array[float] = []
var _open := 0


## list: [[zeit_ms, spalte], ...] (MineGen.generate).
func setup(list: Array, columns: int) -> void:
	times.clear()
	cols.clear()
	_lane.clear()
	_head.clear()
	_held.clear()
	_down_since.clear()
	for c in columns:
		_lane.append([])
		_head.append(0)
		_held.append(false)
		_down_since.append(0.0)
	var sorted := list.duplicate()
	sorted.sort_custom(func(a, b): return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for m in sorted:
		var c := int(m[1])
		if c < 0 or c >= columns:
			continue
		(_lane[c] as Array).append(times.size())
		times.append(float(m[0]))
		cols.append(c)
	state.resize(times.size())
	state.fill(PENDING)
	_open = times.size()


func count() -> int:
	return times.size()


func n_hit() -> int:
	return state.count(HIT)


## Alle Minen entschieden?
func done() -> bool:
	return _open <= 0


func is_pending(i: int) -> bool:
	return state[i] == PENDING


## Taste in Spalte c unten (Zeit t). Liefert die dadurch ausgeloesten Minen.
func key_down(c: int, t: float) -> Array[int]:
	var out: Array[int] = []
	if c < 0 or c >= _lane.size():
		return out
	_scan(c, t, false, t, out)
	_held[c] = true
	_down_since[c] = t
	_scan(c, t, true, t, out)
	return out


## Taste in Spalte c oben (Zeit t): Minen, die waehrend des Haltens kamen, loesen aus.
func key_up(c: int, t: float) -> Array[int]:
	var out: Array[int] = []
	if c < 0 or c >= _lane.size() or not _held[c]:
		return out
	_scan(c, t, true, _down_since[c], out)
	_held[c] = false
	return out


## Frame: gehaltene Spalten loesen erreichte Minen aus, vorbeigezogene sind sicher.
func update(now: float) -> Array[int]:
	var out: Array[int] = []
	for c in _lane.size():
		_scan(c, now, _held[c], _down_since[c], out)
	return out


## Spalte c bis Zeit now abarbeiten. down = Taste seit since unten.
func _scan(c: int, now: float, down: bool, since: float, out: Array[int]) -> void:
	var lane: Array = _lane[c]
	var k: int = _head[c]
	while k < lane.size():
		var i: int = lane[k]
		if state[i] != PENDING:
			k += 1
			continue
		var t0 := times[i] - WINDOW_MS
		var t1 := times[i] + WINDOW_MS
		if t0 > now:
			break
		if down and since <= t1:
			state[i] = HIT
			_open -= 1
			out.append(i)
		elif t1 < now:
			state[i] = DODGED
			_open -= 1
		else:
			break
		k += 1
	_head[c] = k
