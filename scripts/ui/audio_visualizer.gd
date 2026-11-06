class_name AudioVisualizer
extends Control

## Wiederverwendbarer Spektrum-Visualizer: abgerundete Balken, log-verteilte
## Baender 40 Hz - 12 kHz (SyncClock.band_energy), Attack schnell / Release
## langsam, Peak-Kappen, kurzer Helligkeits-Puls auf Sub-Bass-Kicks.
## Ruhig (Hoehe 0) ohne Musik. Keine Allokation pro Frame.

const F_MIN: float = 40.0
const F_MAX: float = 12000.0
const ATTACK: float = 28.0      # 1/s, schnell
const RELEASE: float = 4.5      # 1/s, langsam
const PEAK_HOLD: float = 0.12   # s
const PEAK_FALL: float = 0.45   # Hoehe/s
const BASS_BOOST: float = 0.35  # Bass-Baender bis +35 % gewichtet
const KICK_MAX: float = 0.2     # max +20 % Helligkeit
const GAP_RATIO: float = 0.28

@export var bars: int = 48:
	set(v):
		bars = maxi(v, 1)
		_rebuild()
@export var color: Color = Color(0.0, 0.85, 1.0, 1.0)
@export var mirrored: bool = true

var _edges: PackedFloat32Array = PackedFloat32Array()   # bars + 1 Kanten in Hz
var _weights: PackedFloat32Array = PackedFloat32Array()
var _raw: PackedFloat32Array = PackedFloat32Array()
var _level: PackedFloat32Array = PackedFloat32Array()
var _peak: PackedFloat32Array = PackedFloat32Array()
var _peak_hold: PackedFloat32Array = PackedFloat32Array()
var _pts: PackedVector2Array = PackedVector2Array()
var _cols: PackedColorArray = PackedColorArray()
var _bass_avg: float = 0.0
var _kick: float = 0.0
var _clock: Node = null


func _init() -> void:
	_pts.resize(6)
	_cols.resize(6)
	_rebuild()


func _ready() -> void:
	_clock = get_node_or_null("/root/SyncClock")


func set_color(c: Color) -> void:
	color = c
	queue_redraw()


## Log-verteilte Bandkanten + Bass-Gewichte + Zustands-Arrays neu anlegen.
func _rebuild() -> void:
	var n: int = maxi(bars, 1)
	_edges.resize(n + 1)
	_weights.resize(n)
	_raw.resize(n)
	_level.resize(n)
	_peak.resize(n)
	_peak_hold.resize(n)
	var ratio: float = F_MAX / F_MIN
	for i in n + 1:
		_edges[i] = F_MIN * pow(ratio, float(i) / float(n))
	for i in n:
		var t: float = float(i) / float(maxi(n - 1, 1))
		_weights[i] = 1.0 + BASS_BOOST * pow(1.0 - t, 2.0)
		_raw[i] = 0.0
		_level[i] = 0.0
		_peak[i] = 0.0
		_peak_hold[i] = 0.0


## Liest die Energien aus SyncClock (nur wenn Musik laeuft) in _raw.
func _sample() -> bool:
	var playing: bool = _clock != null and _clock.has_method("is_playing") and _clock.is_playing()
	if playing:
		for i in bars:
			_raw[i] = _clock.band_energy(_edges[i], _edges[i + 1])
	else:
		for i in bars:
			_raw[i] = 0.0
	return playing


## Ein Glaettungsschritt auf Basis von _raw. Rueckgabe: noch Bewegung?
func _step(delta: float, kick_raw: float) -> bool:
	var a: float = 1.0 - exp(-ATTACK * delta)
	var r: float = 1.0 - exp(-RELEASE * delta)
	var moving: bool = false
	for i in bars:
		var target: float = clampf(_raw[i] * _weights[i], 0.0, 1.0)
		var cur: float = _level[i]
		cur += (target - cur) * (a if target > cur else r)
		if cur < 0.002 and target <= 0.0:
			cur = 0.0
		_level[i] = cur
		if cur >= _peak[i]:
			_peak[i] = cur
			_peak_hold[i] = PEAK_HOLD
		elif _peak_hold[i] > 0.0:
			_peak_hold[i] -= delta
		else:
			_peak[i] = maxf(_peak[i] - PEAK_FALL * delta, cur)
		if _peak[i] < 0.002 and cur == 0.0:
			_peak[i] = 0.0
		if cur > 0.0 or _peak[i] > 0.0:
			moving = true
	# Sub-Bass-Kick: Onset gegen gleitenden Mittelwert.
	_bass_avg += (kick_raw - _bass_avg) * clampf(delta * 1.5, 0.0, 1.0)
	if kick_raw - _bass_avg > 0.08 and kick_raw > 0.35:
		_kick = 1.0
	_kick = maxf(_kick - delta * 4.0, 0.0)
	return moving or _kick > 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var playing: bool = _sample()
	var kick_raw: float = _clock.band_energy(30.0, 90.0) if playing else 0.0
	if _step(delta, kick_raw) or playing:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0 or bars <= 0:
		return
	var slot: float = w / float(bars)
	var bw: float = maxf(slot * (1.0 - GAP_RATIO), 1.0)
	var bright: float = 1.0 + KICK_MAX * _kick
	var tip := Color(minf(color.r * bright, 1.0), minf(color.g * bright, 1.0), minf(color.b * bright, 1.0), color.a)
	var base := Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, color.a * 0.3)
	var mid: float = h * 0.5 if mirrored else h
	var span: float = h * 0.5 if mirrored else h
	var rad: float = minf(bw * 0.5, 6.0)
	for i in bars:
		var x0: float = slot * i + (slot - bw) * 0.5
		var x1: float = x0 + bw
		var bh: float = _level[i] * span
		if bh > 0.5:
			var hh: float = maxf(bh, rad * 1.5)
			_draw_bar(x0, x1, mid, mid - hh, rad, base, tip)
			if mirrored:
				_draw_bar(x0, x1, mid, mid + hh, rad, base, tip)
		var ph: float = _peak[i] * span
		if ph > 1.0:
			var cap := Color(tip.r, tip.g, tip.b, tip.a * 0.85)
			draw_rect(Rect2(x0, mid - ph - 3.0, bw, 2.0), cap)
			if mirrored:
				draw_rect(Rect2(x0, mid + ph + 1.0, bw, 2.0), cap)


## Balken mit abgeschraegten (gerundeten) Spitzenecken und vertikalem Verlauf.
## y_base = Fuss, y_tip = Spitze (kann ueber oder unter y_base liegen).
func _draw_bar(x0: float, x1: float, y_base: float, y_tip: float, rad: float, c_base: Color, c_tip: Color) -> void:
	var dir: float = signf(y_tip - y_base)
	var yr: float = y_tip - dir * rad
	_pts[0] = Vector2(x0, y_base)
	_pts[1] = Vector2(x0, yr)
	_pts[2] = Vector2(x0 + rad * 0.3, y_tip)
	_pts[3] = Vector2(x1 - rad * 0.3, y_tip)
	_pts[4] = Vector2(x1, yr)
	_pts[5] = Vector2(x1, y_base)
	_cols[0] = c_base
	_cols[1] = c_tip
	_cols[2] = c_tip
	_cols[3] = c_tip
	_cols[4] = c_tip
	_cols[5] = c_base
	draw_polygon(_pts, _cols)
