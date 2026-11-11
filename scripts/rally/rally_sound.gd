class_name RallySound
extends Node

## Rally-Klaenge, im Code erzeugt (kein Rauschen-Matsch, kurz und satt):
## Schlag = trockenes "Tock" (Holzton + kurzer Anschlag), Schmetterball = tiefer
## mit hellem Knack, Tischaufprall = leises Tick, Gegnerschlag = weicher Tock,
## Fehlschlag = dumpfes Tippen. Lautstaerke ueber Settings.hitsounds/hitsound_volume.
## Der Schlagklang laeuft beim Tastendruck (Latenz = ein Audio-Puffer, weit unter 150 ms).

const RATE := 44100
const POLY := 4
## Protokoll der ausgeloesten Klaenge (Tests): [Art, Taste].
var log: Array = []
var _hit: Array = [[], []]
var _next := [0, 0]
var _smash: Array[AudioStreamPlayer] = []
var _smash_next := 0
var _bounce: AudioStreamPlayer
var _opp: AudioStreamPlayer
var _miss: AudioStreamPlayer
var _release: AudioStreamPlayer
var _charge: AudioStreamPlayer
static var _cache: Dictionary = {}


func _ready() -> void:
	for k in 2:
		for i in POLY:
			_hit[k].append(_mk(_tock(k)))
	for i in 2:
		_smash.append(_mk(_smash_stream()))
	_bounce = _mk(_tick())
	_opp = _mk(_tock(2))
	_miss = _mk(_thud())
	_release = _mk(_tock(3))
	_charge = _mk(_charge_loop())


func _mk(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


func _on() -> bool:
	return Settings.hitsounds and Settings.hitsound_volume > 0.01


func _db(base: float) -> float:
	return linear_to_db(maxf(Settings.hitsound_volume, 0.001)) + base


func play_hit(key: int, q: int = 1) -> void:
	log.append(["hit", key])
	if not _on():
		return
	var p: AudioStreamPlayer = _hit[key][_next[key]]
	_next[key] = (_next[key] + 1) % POLY
	p.volume_db = _db(-5.0)
	p.pitch_scale = [1.04, 1.0, 0.97, 0.93, 0.88, 1.0][clampi(q, 0, 5)]
	p.play()


func play_smash() -> void:
	log.append(["smash", 2])
	if not _on():
		return
	var p := _smash[_smash_next]
	_smash_next = (_smash_next + 1) % _smash.size()
	p.volume_db = _db(-2.0)
	p.play()


func play_bounce() -> void:
	log.append(["bounce", 0])
	if _on():
		_bounce.volume_db = _db(-17.0)
		_bounce.play()


func play_opp() -> void:
	log.append(["opp", 0])
	if _on():
		_opp.volume_db = _db(-12.0)
		_opp.play()


func play_miss() -> void:
	log.append(["miss", 0])
	if _on():
		_miss.volume_db = _db(-12.0)
		_miss.play()


func play_release() -> void:
	log.append(["release", 0])
	stop_charge()
	if _on():
		_release.volume_db = _db(-7.0)
		_release.play()


func start_charge() -> void:
	log.append(["charge", 0])
	if _on():
		_charge.volume_db = _db(-22.0)
		_charge.play()


func stop_charge() -> void:
	if _charge != null and _charge.playing:
		_charge.stop()


# ---------------------------------------------------------------------------
# Erzeugung
# ---------------------------------------------------------------------------

static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Tock: Holzton mit Anschlagknacks. Art 0 = A (heller), 1 = B (tiefer), 2 = Gegner
## (weich), 3 = Loslassen.
static func _tock(kind: int) -> AudioStreamWAV:
	var key := "tock%d" % kind
	if _cache.has(key):
		return _cache[key]
	var f := [980.0, 620.0, 520.0, 1200.0][kind]
	var dur := 0.09
	var amp := [0.62, 0.66, 0.4, 0.45][kind]
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed := 12345 + kind
	for i in n:
		var t := float(i) / RATE
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed) / float(0x7fffffff) * 2.0 - 1.0
		var body := sin(TAU * f * t * (1.0 - 0.18 * t * 10.0)) * exp(-t * 55.0)
		var knock := noise * exp(-t * 700.0) * 0.55
		var s := (body + knock) * amp * minf(t / 0.0006, 1.0)
		s *= clampf((dur - t) / 0.01, 0.0, 1.0)
		out[i] = s
	_cache[key] = _wav(out)
	return _cache[key]


static func _smash_stream() -> AudioStreamWAV:
	if _cache.has("smash"):
		return _cache["smash"]
	var dur := 0.16
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed := 777
	for i in n:
		var t := float(i) / RATE
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed) / float(0x7fffffff) * 2.0 - 1.0
		var body := sin(TAU * 240.0 * t * (1.0 - 0.5 * t * 4.0)) * exp(-t * 26.0)
		var crack := noise * exp(-t * 420.0) * 0.7 + sin(TAU * 2100.0 * t) * exp(-t * 160.0) * 0.35
		var s := (body * 0.9 + crack) * 0.75 * minf(t / 0.0005, 1.0)
		s *= clampf((dur - t) / 0.02, 0.0, 1.0)
		out[i] = s
	_cache["smash"] = _wav(out)
	return _cache["smash"]


static func _tick() -> AudioStreamWAV:
	if _cache.has("tick"):
		return _cache["tick"]
	var n := int(RATE * 0.03)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 1700.0 * t) * exp(-t * 170.0) * 0.4 * clampf((0.03 - t) / 0.004, 0.0, 1.0)
	_cache["tick"] = _wav(out)
	return _cache["tick"]


static func _thud() -> AudioStreamWAV:
	if _cache.has("thud"):
		return _cache["thud"]
	var n := int(RATE * 0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (150.0 - 450.0 * t) * t) * exp(-t * 40.0) * 0.55 \
				* minf(t / 0.003, 1.0) * clampf((0.09 - t) / 0.01, 0.0, 1.0)
	_cache["thud"] = _wav(out)
	return _cache["thud"]


static func _charge_loop() -> AudioStreamWAV:
	if _cache.has("charge"):
		return _cache["charge"]
	var n := int(RATE * 0.2)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * 110.0 * 0.2 * float(i) / float(n) * 5.0) * 0.2 \
				+ sin(TAU * 165.0 * 0.2 * float(i) / float(n) * 5.0) * 0.1
	_cache["charge"] = _wav(out, true)
	return _cache["charge"]
