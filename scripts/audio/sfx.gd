class_name Sfx
extends RefCounted

## Prozedural erzeugte Sound-Effekte (kein Asset noetig). 16-bit mono PCM.
## Hitsounds sind essenziell fuers Rhythmus-Gefuehl: der Klick bestaetigt
## hoerbar, ob man im Takt ist.

const RATE := 44100


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


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
