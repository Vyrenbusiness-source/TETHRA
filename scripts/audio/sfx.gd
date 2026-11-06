class_name Sfx
extends RefCounted

## Prozedural erzeugte Sound-Effekte (kein Asset noetig). 16-bit mono PCM.
## Hitsounds sind essenziell fuers Rhythmus-Gefuehl: der Klick bestaetigt
## hoerbar, ob man im Takt ist.
##
## UI-Klang-Identitaet (A-Dur-Pentatonik: A C# E F# A, warm, kurz, -12..-18 dB).
## Neue Funktionen zur Integration (spielen direkt ueber einen internen Player;
## Lautstaerke = Master-Bus * Settings.hitsound_volume):
##   Sfx.ui_hover()              sehr leiser Tick bei Hover
##   Sfx.ui_click()              Klick / Bestaetigen
##   Sfx.ui_back()               Zurueck / Abbrechen
##   Sfx.ui_open()               Panel oeffnen (aufsteigender Whoosh)
##   Sfx.ui_close()              Panel schliessen (absteigender Whoosh)
##   Sfx.select_chime()          Map-Auswahl im Browser
##   Sfx.rank_reveal(rank: String)  Results-Rank-Hit ("SS","S","A","B","C","D")
##   Sfx.milestone(combo: int)   Combo-Meilenstein-Chime (Tonhoehe steigt mit Stufe)
## Gameplay-Hitsounds (hit_stream/miss_stream/...) bleiben unveraendert.

const RATE := 44100
const A4 := 440.0
const CS5 := 554.37
const E5 := 659.25
const FS5 := 739.99
const A5 := 880.0
const CS6 := 1108.73
const E6 := 1318.51
const A3 := 220.0
const E4 := 329.63

static var _cache: Dictionary = {}
static var _players: Array = []
static var _next_player := 0


## Warmer, weicher Pluck (angenehm, mischt sich in die Musik statt zu klicken).
## Pitch pro Qualitaet skaliert die Szene in musikalischen Intervallen.
static func hit_stream() -> AudioStreamWAV:
	# Sehr cleanes, weiches "Tick": kurz, tief, kaum Obertoene.
	var dur := 0.075
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.005, 1.0)
		var s := sin(TAU * 480.0 * t) * exp(-t * 34.0)
		s += 0.18 * sin(TAU * 960.0 * t) * exp(-t * 55.0)
		var v := int(clampf(s * attack * 0.34, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data)


## Vorbeiflug-Whoosh: tiefpass-gefiltertes Rauschen mit An-/Abschwellen.
static func whoosh_stream() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_state := 777
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
		var raw := float(noise_state) / float(0x7FFFFFFF) * 2.0 - 1.0
		# Doppler-Gefuehl: Filter oeffnet sich zur Mitte hin und schliesst.
		var k := 0.86 - 0.10 * sin(PI * t / dur)
		last = last * k + raw * (1.0 - k)
		var env := pow(sin(PI * t / dur), 1.6)
		var v := int(clampf(last * env * 1.6, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data)


## Dumpfer Noise-Burst fuer Misses.
static func miss_stream() -> AudioStreamWAV:
	var dur := 0.12
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var noise_state := 12345
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		# Deterministischer LCG-Noise (kein randi — reproduzierbar).
		noise_state = (noise_state * 1103515245 + 12345) & 0x7FFFFFFF
		var raw := float(noise_state) / float(0x7FFFFFFF) * 2.0 - 1.0
		# Grober Tiefpass fuer dumpfen Klang — leise und weich, kein Schreck.
		last = last * 0.9 + raw * 0.1
		var s := last * exp(-t * 40.0) * 0.5 + 0.35 * sin(TAU * 140.0 * t) * exp(-t * 30.0)
		var v := int(clampf(s * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data)


## Sehr leiser, tiefer Sub-Thump fuer den Taktanfang: man FUEHLT den Beat,
## ohne dass er die Musik uebertoent (Kick mit Pitch-Drop 110->55 Hz).
static func beat_thump_stream() -> AudioStreamWAV:
	var dur := 0.14
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 55.0 + 110.0 * exp(-t * 18.0)
		phase += TAU * f / RATE
		var attack := minf(t / 0.008, 1.0)
		var s := sin(phase) * exp(-t * 20.0)
		var v := int(clampf(s * attack * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	return _wav(data)


# --- UI-Sounds -------------------------------------------------------------

static func ui_hover() -> void:
	_play("hover", 0.5)


static func ui_click() -> void:
	_play("click", 1.0)


static func ui_back() -> void:
	_play("back", 1.0)


static func ui_open() -> void:
	_play("open", 0.7)


static func ui_close() -> void:
	_play("close", 0.75)


static func select_chime() -> void:
	_play("select", 1.0)


static func rank_reveal(rank: String) -> void:
	var r := rank.to_upper()
	if r not in ["SS", "S", "A", "B", "C", "D"]:
		r = "D"
	_play("rank_" + r, 0.6)


static func milestone(combo: int) -> void:
	# Stufen: 50/100/200/... -> hoeher pro Stufe, gedeckelt.
	var lvl := 0
	if combo >= 1000:
		lvl = 4
	elif combo >= 500:
		lvl = 3
	elif combo >= 200:
		lvl = 2
	elif combo >= 100:
		lvl = 1
	_play("mile_%d" % clampi(lvl, 0, 4), 1.0)


static func _play(key: String, gain: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if not _cache.has(key):
		_cache[key] = _build(key)
	if _players.is_empty():
		for k in 4:
			var p := AudioStreamPlayer.new()
			p.bus = &"Master"
			tree.root.add_child.call_deferred(p)
			_players.append(p)
	var vol := 0.8
	var st = tree.root.get_node_or_null("Settings")
	if st != null and "hitsound_volume" in st:
		vol = float(st.hitsound_volume)
	if vol <= 0.001:
		return
	var pl: AudioStreamPlayer = _players[_next_player]
	if not is_instance_valid(pl):
		_players.clear()
		return
	_next_player = (_next_player + 1) % _players.size()
	pl.stream = _cache[key]
	pl.volume_db = linear_to_db(clampf(vol * gain, 0.0, 1.0))
	pl.play()


static func _build(key: String) -> AudioStreamWAV:
	match key:
		"hover":
			return _mix(0.05, [[A5, 0.0, 70.0, 0.05, 0.0]])
		"click":
			return _mix(0.11, [[E5, 0.0, 38.0, 0.20, 0.25], [A4, 0.0, 30.0, 0.12, 0.0]])
		"back":
			return _mix(0.13, [[A4, 0.0, 30.0, 0.18, 0.2], [E4, 0.015, 26.0, 0.14, 0.0]])
		"open":
			return _sweep(0.26, 380.0, 900.0, 0.12, true)
		"close":
			return _sweep(0.22, 900.0, 380.0, 0.10, false)
		"select":
			return _mix(0.38, [[A5, 0.0, 11.0, 0.14, 0.3], [E6, 0.045, 12.0, 0.10, 0.2]])
		"rank_D":
			return _mix(0.40, [[A3, 0.0, 7.0, 0.22, 0.3], [E4, 0.0, 8.0, 0.12, 0.0]])
		"rank_C":
			return _mix(0.42, [[A3, 0.0, 6.5, 0.2, 0.3], [CS5 / 2.0, 0.0, 7.0, 0.14, 0.2]])
		"rank_B":
			return _mix(0.5, [[A4, 0.0, 6.0, 0.18, 0.3], [CS5, 0.0, 6.0, 0.13, 0.2], [E5, 0.0, 6.0, 0.10, 0.0]])
		"rank_A":
			return _mix(0.6, [[A4, 0.0, 5.0, 0.17, 0.3], [CS5, 0.0, 5.0, 0.13, 0.2], [E5, 0.0, 5.0, 0.11, 0.1], [A5, 0.07, 6.0, 0.08, 0.0]])
		"rank_S":
			return _mix(0.8, [[A4, 0.0, 4.0, 0.16, 0.3], [E5, 0.0, 4.0, 0.12, 0.2], [A5, 0.06, 4.5, 0.12, 0.2], [CS6, 0.12, 5.0, 0.08, 0.0]])
		"rank_SS":
			return _mix(1.1, [[A4, 0.0, 3.2, 0.15, 0.3], [E5, 0.0, 3.2, 0.12, 0.2], [A5, 0.06, 3.5, 0.12, 0.2], [CS6, 0.12, 3.8, 0.09, 0.1], [E6, 0.19, 4.0, 0.07, 0.0]])
		_:
			var lvl := int(key.substr(5))
			var notes := [A5, CS6, E6, A5 * 2.0, CS6 * 2.0]
			var f: float = notes[clampi(lvl, 0, 4)]
			return _mix(0.5, [[f, 0.0, 9.0, 0.13, 0.25], [f * 1.5, 0.05, 10.0, 0.07, 0.0]])


## Additive Toene: [freq, start_s, decay, amp, 2nd_harmonic]. Weicher Attack, Sinus.
static func _mix(dur: float, notes: Array) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for nt in notes:
			var tt: float = t - float(nt[1])
			if tt < 0.0:
				continue
			var f: float = nt[0]
			var env := minf(tt / 0.004, 1.0) * exp(-tt * float(nt[2]))
			s += (sin(TAU * f * tt) + float(nt[4]) * sin(TAU * f * 2.0 * tt)) * env * float(nt[3])
		# Sanftes Ausblenden am Ende gegen Klicks.
		s *= clampf((dur - t) / 0.01, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _wav(data)


## Weicher Filter-Sweep (tiefpass-gefiltertes Rauschen), up = oeffnend.
static func _sweep(dur: float, f0: float, f1: float, amp: float, up: bool) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var st := 4242
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		st = (st * 1103515245 + 12345) & 0x7FFFFFFF
		var raw := float(st) / float(0x7FFFFFFF) * 2.0 - 1.0
		var f := lerpf(f0, f1, u)
		var k := exp(-TAU * f / RATE)
		last = last * k + raw * (1.0 - k)
		var env := pow(sin(PI * u), 1.4)
		data.encode_s16(i * 2, int(clampf(last * env * amp * 6.0, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
