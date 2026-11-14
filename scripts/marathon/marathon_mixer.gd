class_name MarathonMixer
extends Node

## Marathon-Wiedergabe: zwei Decks (eigene AudioStreamPlayer + eigener Bus mit
## EQ) spielen die Songs der Zeitachse (MarathonPlan) und blenden auf dem Takt
## ueber. Die Song-Uhr bleibt SyncClock: sie spielt eine stumme Spur ueber die
## ganze Marathon-Laenge (silent_master), Pause/Fortsetzen/Sprung/Lead-In laufen
## dort unveraendert. Die Decks folgen dieser Uhr sample-genau: ihre Position
## wird je Bild gegen die Master-Position gemessen (beide aus demselben Mix, also
## ohne Latenz-Unterschied), grobe Abweichung = Sprung (nur solange das Deck stumm
## ist oder > SEEK_MS daneben), feine = Tempo-Nachfuehrung (+-PLL_MAX).
##
## Tempo: Deck-Rate = MarathonPlan.rate_at (Angleich an den Vorgaenger, dann Rampe
## auf 1) ueber pitch_scale (Tonhoehe geht mit, wie ein Plattenspieler-Pitch).
## Spaeter auf die gemeinsame Rate-Grundlage (Task mv-tempo) umstellen: dort, wo
## _apply_rate() pitch_scale setzt (siehe Bericht).

const BUS_PREFIX := "MarathonDeck"
## Ab dieser Abweichung (ms) wird das Deck neu positioniert.
const SEEK_MS := 18.0
## Gilt als eingerastet, sobald die Abweichung darunter liegt (ms).
const LOCK_MS := 3.0
## Feinnachfuehrung: Tempo-Korrektur = Abweichung / PLL_TAU_MS, hoechstens PLL_MAX.
const PLL_TAU_MS := 400.0
const PLL_MAX := 0.006
## Deck startet so frueh stumm, damit es vor der Einblendung eingerastet ist.
const PREROLL_MS := 450.0
## Einblendung nach dem Einrasten (ms), gegen Knackser.
const LOCK_FADE_MS := 40.0
## Stumme Master-Spur: 8-Bit-Mono mit niedriger Rate (20 min = 4,8 MB).
const MASTER_RATE := 4000

var segs: Array = []
var streams: Array = []
var gains_db: Array = []
## Anzahl Neupositionierungen und groesste Abweichung im eingerasteten Zustand
## (Diagnose, Harness-Bericht).
var seeks := 0
var max_locked_err_ms := 0.0
var err_log: Array = []  ## [g, deck, err] im eingerasteten Zustand (Harness)
var log_errors := false
var err_all: PackedFloat32Array = PackedFloat32Array()  ## jede Messung (Harness)

var _decks: Array = []
var _was_running := false


## Stumme Master-Spur fuer SyncClock (Laenge in ms).
static func silent_master(length_ms: float) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.stereo = false
	w.mix_rate = MASTER_RATE
	var n := int(ceil(maxf(length_ms, 1000.0) / 1000.0 * MASTER_RATE))
	var data := PackedByteArray()
	data.resize(n)
	data.fill(0)
	w.data = data
	return w


## Pruef-Master (nur Harness): wie silent_master, aber mit leisen Klicks (3 kHz,
## 3 ms, Hann-Fenster) alle CLICK_MS globaler Zeit, 16 Bit, 44,1 kHz. Der
## Mitschnitt zeigt so die Uhr selbst; tools/marathon_sync_check.py misst die
## Decks dagegen (Musik gegen Notenuhr).
const CLICK_MS := 500.0
const CLICK_RATE := 44100


static func click_master(length_ms: float) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = CLICK_RATE
	var n := int(ceil(maxf(length_ms, 1000.0) / 1000.0 * CLICK_RATE))
	var data := PackedByteArray()
	data.resize(n * 2)
	data.fill(0)
	var len_s := int(0.003 * CLICK_RATE)
	var k := 0
	while true:
		var start := int(round(float(k) * CLICK_MS / 1000.0 * CLICK_RATE))
		if start + len_s >= n:
			break
		for j in len_s:
			var win := 0.5 - 0.5 * cos(TAU * float(j) / float(len_s))
			var v := 0.25 * win * sin(TAU * 3000.0 * float(j) / float(CLICK_RATE))
			data.encode_s16((start + j) * 2, int(v * 32767.0))
		k += 1
	w.data = data
	return w


func setup(p_segs: Array, p_streams: Array, p_gains_db: Array) -> void:
	segs = p_segs
	streams = p_streams
	gains_db = p_gains_db


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100  # nach SyncClock/Spiel: Uhr steht fuer dieses Bild fest
	var music: int = _clock().ensure_music_bus()
	for d in 2:
		var bus_name := "%s%d" % [BUS_PREFIX, d]
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			idx = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, AudioServer.get_bus_name(music))
		while AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.remove_bus_effect(idx, 0)
		var eq := AudioEffectEQ6.new()
		AudioServer.add_bus_effect(idx, eq, 0)
		var p := AudioStreamPlayer.new()
		p.name = "Deck%d" % d
		p.bus = bus_name
		p.volume_db = -80.0
		add_child(p)
		_decks.append({"player": p, "eq": eq, "seg": -1, "locked": false, "skip": 0,
			"lock_t": 0.0, "tries": 0, "ended": false, "paused": false})


func _exit_tree() -> void:
	for d in _decks:
		(d.player as AudioStreamPlayer).stop()
	# Eigene Busse entfernen (hoechster Index zuerst, die anderen bleiben gueltig).
	var ids: Array[int] = []
	for d in 2:
		var idx := AudioServer.get_bus_index("%s%d" % [BUS_PREFIX, d])
		if idx > 0:
			ids.append(idx)
	ids.sort()
	ids.reverse()
	for idx in ids:
		AudioServer.remove_bus(idx)


func _clock() -> Node:
	return MarathonRun.autoload("SyncClock")


func _master() -> AudioStreamPlayer:
	var c := _clock()
	return c.get("_player") as AudioStreamPlayer if c != null else null


## Deck-Index eines Segments (abwechselnd, hoechstens zwei klingen gleichzeitig).
static func deck_of(seg_index: int) -> int:
	return seg_index % 2


## Globale Zeit, ab der das Deck des Segments (stumm) laufen soll.
static func play_window(seg: Dictionary) -> Vector2:
	var from := maxf(float(seg.play_from) - PREROLL_MS, MarathonPlan.global_at(seg, 0.0))
	return Vector2(from, float(seg.play_to))


func _process(delta: float) -> void:
	var master := _master()
	if master == null:
		return
	var clock := _clock()
	var running: bool = master.playing and not master.stream_paused and not clock.is_paused()
	if not running:
		if _was_running or clock.is_paused():
			_hold_all(not clock.is_playing())
		_was_running = false
		return
	_was_running = true
	# Positionen aus demselben Mix lesen (faellt ein Mix dazwischen: neu lesen).
	var gm := 0.0
	var pos: Array[float] = [0.0, 0.0]
	for attempt in 3:
		var m0 := AudioServer.get_time_since_last_mix()
		gm = master.get_playback_position() * 1000.0
		for d in 2:
			pos[d] = (_decks[d].player as AudioStreamPlayer).get_playback_position() * 1000.0
		var m1 := AudioServer.get_time_since_last_mix()
		if m1 >= m0:
			break
	for i in segs.size():
		var seg: Dictionary = segs[i]
		var d: int = deck_of(i)
		var deck: Dictionary = _decks[d]
		var p: AudioStreamPlayer = deck.player
		var win := play_window(seg)
		var inside := gm >= win.x and gm < win.y
		if not inside:
			if int(deck.seg) == i:
				p.stop()
				p.volume_db = -80.0
				deck.seg = -1
			continue
		if int(deck.seg) != i:
			# Deck uebernimmt dieses Segment (das vorige auf dem Deck ist vorbei).
			deck.seg = i
			deck.locked = false
			deck.tries = 0
			deck.ended = false
			deck.paused = false
			p.stream = streams[i]
			p.volume_db = -80.0
			p.pitch_scale = MarathonPlan.rate_at(seg, gm)
			p.play(maxf(MarathonPlan.song_at(seg, gm), 0.0) / 1000.0)
			deck.skip = 2
			continue
		if bool(deck.paused):
			p.stream_paused = false
			deck.paused = false
			deck.locked = false
			deck.tries = 0
			deck.skip = 2
		if not p.playing:
			deck.ended = true
			continue
		_sync_deck(deck, seg, gm, pos[d], delta, i)
		_apply_mix(deck, seg, gm, i)


func _sync_deck(deck: Dictionary, seg: Dictionary, gm: float, pos_ms: float, delta: float, i: int) -> void:
	var p: AudioStreamPlayer = deck.player
	var rate := MarathonPlan.rate_at(seg, gm)
	if int(deck.skip) > 0:
		deck.skip = int(deck.skip) - 1
		p.pitch_scale = rate
		return
	var err := MarathonPlan.global_at(seg, pos_ms) - gm
	var audible := MarathonPlan.volume_at(seg, gm) > 0.001
	if absf(err) > SEEK_MS or (not bool(deck.locked) and absf(err) > LOCK_MS and int(deck.tries) < 8):
		# Neu positionieren: gilt ab dem naechsten Mix, in dem auch der Master
		# von gm aus weiterlaeuft -> danach deckungsgleich.
		p.seek(maxf(MarathonPlan.song_at(seg, gm), 0.0) / 1000.0)
		seeks += 1
		deck.tries = int(deck.tries) + 1
		if bool(deck.locked) and audible:
			push_warning("Marathon: Deck %d sprang um %.1f ms" % [i % 2, err])
		deck.locked = false
		deck.skip = 2
		p.pitch_scale = rate
		return
	if not bool(deck.locked):
		deck.locked = true
		deck.lock_t = 0.0
	deck.lock_t = float(deck.lock_t) + delta * 1000.0
	if float(deck.lock_t) > 200.0:
		max_locked_err_ms = maxf(max_locked_err_ms, absf(err))
		if log_errors and audible:
			err_log.append([gm, i % 2, err])
	if log_errors:
		err_all.append(err)
	var corr := clampf(err / PLL_TAU_MS, -PLL_MAX, PLL_MAX)
	_apply_rate(p, rate * (1.0 - corr))


## Abspieltempo setzen. Umstellpunkt fuer die gemeinsame Rate-Grundlage (mv-tempo):
## dort ggf. Tonhoehe getrennt halten (Pitch-Shift-Effekt auf dem Deck-Bus).
func _apply_rate(p: AudioStreamPlayer, rate: float) -> void:
	p.pitch_scale = clampf(rate, 0.5, 2.0)


func _apply_mix(deck: Dictionary, seg: Dictionary, gm: float, i: int) -> void:
	var p: AudioStreamPlayer = deck.player
	var lock_k := 0.0
	if bool(deck.locked):
		lock_k = clampf(float(deck.lock_t) / LOCK_FADE_MS, 0.0, 1.0)
	var lin := MarathonPlan.volume_at(seg, gm) * lock_k
	var gain: float = float(gains_db[i]) if i < gains_db.size() else 0.0
	p.volume_db = gain + linear_to_db(maxf(lin, 0.0001))
	var eq: AudioEffectEQ6 = deck.eq
	var bass := MarathonPlan.bass_db_at(seg, gm)
	eq.set_band_gain_db(0, bass)
	eq.set_band_gain_db(1, bass)
	eq.set_band_gain_db(2, bass * 0.35)


## Uhr steht (Pause) oder ist aus (Ende): Decks leise anhalten bzw. stoppen.
func _hold_all(stop: bool) -> void:
	for deck in _decks:
		var p: AudioStreamPlayer = deck.player
		if int(deck.seg) < 0:
			continue
		if stop:
			p.stop()
			deck.seg = -1
		elif p.playing and not p.stream_paused:
			p.volume_db = -80.0
			p.stream_paused = true
			deck.paused = true


## Aktives (lautestes) Segment bei globaler Zeit g (fuer Anzeige/Uhr-Bericht).
static func active_segment(p_segs: Array, g: float) -> int:
	var best := 0
	for i in p_segs.size():
		var mid := float(p_segs[i].get("mid_in", -INF))
		if g >= mid:
			best = i
	return best
