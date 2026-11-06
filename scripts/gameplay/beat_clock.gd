class_name BeatClock
extends RefCounted

## Exakter Takt aus den Timing-Points einer Map.
## Rote Linien setzen BPM/Meter, Kiai kommt vom jeweils letzten Point (rot oder gruen).
## update() einmal pro Frame; Zeiger statt Suche, Seek rueckwaerts (Retry) erlaubt.

const ENV_DECAY := 3.0 ## exp(-3) nach 1/4 Beat
const ENV_OFF_BEAT := 0.55
const KIAI_RATE := 6.0

var beat_phase: float = 0.0
var bar_phase: float = 0.0
var beat_index: int = 0 ## Beat seit Start des aktuellen roten Abschnitts
var is_beat_edge: bool = false
var is_downbeat_edge: bool = false
var beat_env: float = 0.0
var bpm: float = 0.0
var kiai: bool = false
var kiai_mix: float = 0.0

var _red_t: Array[float] = []
var _red_len: Array[float] = []
var _red_meter: Array[int] = []
var _kiai_t: Array[float] = []
var _kiai_on: Array[bool] = []
var _rp: int = 0
var _kp: int = -1
var _has_prev: bool = false
var _prev_t: float = 0.0
var _prev_seg: int = 0
var _prev_idx: int = 0


func setup(timing_points: Array) -> void:
	_red_t.clear()
	_red_len.clear()
	_red_meter.clear()
	_kiai_t.clear()
	_kiai_on.clear()
	var pts: Array = timing_points.duplicate()
	pts.sort_custom(func(a, b): return a.time < b.time)
	for tp in pts:
		_kiai_t.append(tp.time)
		_kiai_on.append(tp.kiai or (tp.effects & 1) != 0)
		if tp.uninherited and tp.beat_length > 0.0:
			_red_t.append(tp.time)
			_red_len.append(tp.beat_length)
			_red_meter.append(maxi(tp.meter, 1))
	_rp = 0
	_kp = -1
	_has_prev = false
	beat_phase = 0.0
	bar_phase = 0.0
	beat_index = 0
	is_beat_edge = false
	is_downbeat_edge = false
	beat_env = 0.0
	bpm = 0.0
	kiai = false
	kiai_mix = 0.0


func update(t_ms: float, delta: float) -> void:
	is_beat_edge = false
	is_downbeat_edge = false
	if _red_t.is_empty():
		return
	while _rp + 1 < _red_t.size() and _red_t[_rp + 1] <= t_ms:
		_rp += 1
	while _rp > 0 and _red_t[_rp] > t_ms:
		_rp -= 1
	var bl: float = _red_len[_rp]
	var meter: int = _red_meter[_rp]
	var x: float = (t_ms - _red_t[_rp]) / bl
	var idx: int = int(floor(x))
	beat_phase = clampf(x - float(idx), 0.0, 1.0)
	beat_index = idx
	var in_bar: int = posmod(idx, meter)
	bar_phase = (float(in_bar) + beat_phase) / float(meter)
	bpm = 60000.0 / bl
	var peak: float = 1.0 if in_bar == 0 else ENV_OFF_BEAT
	beat_env = peak * exp(-beat_phase / 0.25 * ENV_DECAY)

	# Kanten: nur bei Vorwaertslauf, bei grossem Sprung genau einmal.
	if _has_prev and t_ms > _prev_t:
		if _rp > _prev_seg or (_rp == _prev_seg and idx > _prev_idx):
			is_beat_edge = true
			is_downbeat_edge = in_bar == 0
	_has_prev = true
	_prev_t = t_ms
	_prev_seg = _rp
	_prev_idx = idx

	while _kp + 1 < _kiai_t.size() and _kiai_t[_kp + 1] <= t_ms:
		_kp += 1
	while _kp >= 0 and _kiai_t[_kp] > t_ms:
		_kp -= 1
	kiai = _kp >= 0 and _kiai_on[_kp]
	var target: float = 1.0 if kiai else 0.0
	kiai_mix = clampf(kiai_mix + (target - kiai_mix) * (1.0 - exp(-maxf(delta, 0.0) * KIAI_RATE)), 0.0, 1.0)
