extends SceneTree
# warmd: timeout=300  (Audio laeuft in Echtzeit; unter Last langsamer)

## Headless-Tests fuer die Mastering-Kette (Settings) und den Music-Bus.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mastering_tests.gd
## Prueft Bus-Struktur, Effekt-Reihenfolge, Spektrum-/Capture-Index, keine
## verbotenen (Latenz-)Effekte, die Gain-Mathematik und misst echte Pegel:
## Pink-Noise (-11 dBFS RMS, wie ein normalisierter Song) durch den Music-Bus,
## K-gewichtet vor und nach der Kette (der Dummy-Treiber mischt in Echtzeit).

const SEC_PER_RUN := 2.5
const SKIP_SEC := 0.6

var _failed := 0
var _started := false
var _settings: Node
var _music := -1
var _cap_post: AudioEffectCapture
var _cap_master: AudioEffectCapture
var _player: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _pink := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _noise_scale := 1.0
var _runs := [0.0, 0.75, 1.0]
var _run := -1
var _t0 := 0
var _k_pre: KWeight
var _k_post: KWeight
var _k_master: KWeight
var _peak_master := 0.0
var _results: Array[Dictionary] = []


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_static_checks()
		_start_measure()
		return false
	if _run >= _runs.size():
		return true
	if Time.get_ticks_msec() > 60000:
		_check(false, "Timeout")
		_finish()
		return true
	_feed()
	_collect()
	if float(Time.get_ticks_msec() - _t0) / 1000.0 >= SEC_PER_RUN:
		_results.append({"bass": _runs[_run], "pre": _k_pre.lufs(), "post": _k_post.lufs(),
			"master": _k_master.lufs(), "peak": linear_to_db(_peak_master)})
		_next_run()
		if _run >= _runs.size():
			_finish()
			return true
	return false


func _static_checks() -> void:
	_settings = root.get_node("/root/Settings")
	var clock := root.get_node("/root/SyncClock")
	_music = AudioServer.get_bus_index(&"Music")
	_check(_music > 0, "Bus Music existiert")
	_check(AudioServer.get_bus_send(_music) == &"Master", "Music sendet an Master")
	var expect: Array[String] = ["AudioEffectSpectrumAnalyzer", "AudioEffectCapture",
		"AudioEffectHighPassFilter", "AudioEffectLowShelfFilter", "AudioEffectEQ10",
		"AudioEffectAmplify", "AudioEffectDistortion", "AudioEffectCompressor",
		"AudioEffectStereoEnhance", "AudioEffectAmplify", "AudioEffectCompressor"]
	var got: Array[String] = []
	for i in AudioServer.get_bus_effect_count(_music):
		got.append(AudioServer.get_bus_effect(_music, i).get_class())
	_check(got == expect, "Effekt-Reihenfolge Music: %s" % ", ".join(got))
	var spec_inst := AudioServer.get_bus_effect_instance(_music, 0)
	_check(spec_inst is AudioEffectSpectrumAnalyzerInstance and spec_inst == clock.call("spectrum_instance"), "Spektrum-Instanz = Music[0] (pre-Mastering)")
	_check(AudioServer.get_bus_effect(_music, 1) == SongLoudness._capture, "Loudness-Capture = Music[1]")
	var hp := AudioServer.get_bus_effect(_music, 2) as AudioEffectHighPassFilter
	_check(is_equal_approx(hp.cutoff_hz, 28.0) and hp.db == AudioEffectFilter.FILTER_12DB, "Subsonic 28 Hz 12 dB/oct")
	var glue := AudioServer.get_bus_effect(_music, 7) as AudioEffectCompressor
	_check(is_equal_approx(glue.ratio, _settings.call("godot_ratio", 2.0)) and is_equal_approx(glue.attack_us, 10000.0) \
		and is_equal_approx(glue.release_ms, 150.0) and is_equal_approx(glue.threshold, -18.0), "Glue 2:1 10ms/150ms -18dB")
	var lim := AudioServer.get_bus_effect(_music, 10) as AudioEffectCompressor
	_check(is_equal_approx(lim.ratio, _settings.call("godot_ratio", 20.0)) and is_equal_approx(lim.attack_us, 20.0) \
		and is_equal_approx(lim.threshold, -0.8), "Limiter 20:1 20us -0.8dB")
	var master := AudioServer.get_bus_index(&"Master")
	var mcount := AudioServer.get_bus_effect_count(master)
	_check(mcount == 1 and AudioServer.get_bus_effect(master, 0) is AudioEffectCompressor, "Master nur Schutz-Limiter")
	# Verbotene Effekte (Lookahead/Delay) auf allen Bussen.
	var bad := 0
	for b in AudioServer.bus_count:
		for i in AudioServer.get_bus_effect_count(b):
			var e := AudioServer.get_bus_effect(b, i)
			if e is AudioEffectHardLimiter or e is AudioEffectDelay or e is AudioEffectChorus \
					or e is AudioEffectReverb or e is AudioEffectPhaser or e is AudioEffectPitchShift:
				bad += 1
			if e is AudioEffectStereoEnhance and (e as AudioEffectStereoEnhance).time_pullout_ms > 0.0:
				bad += 1
	_check(bad == 0, "keine Lookahead-/Delay-Effekte")
	# Gain-Mathematik.
	_check(absf(_settings.call("godot_ratio", 2.0) - 1.3165) < 0.001 and is_equal_approx(_settings.call("godot_ratio", 1.0), 1.0), "Engine-ratio fuer eff. 2:1 = 1.32")
	_check(is_equal_approx(_settings.call("shelf_gain_for_db", 7.0), pow(10.0, 7.0 / 40.0)), "Shelf-Gain 10^(dB/40)")
	_check(is_equal_approx(_settings.call("bass_shelf_db", 1.0), 7.0) and is_equal_approx(_settings.call("bass_shelf_db", 2.0), 7.0), "Bass max +7 dB")
	_check(is_equal_approx(_settings.call("bass_precomp_db", 1.0), -0.25 * 8.5), "Vorkompensation -0.25 dB je dB Bass")
	_check(is_equal_approx(_settings.call("bass_precomp_db", 0.0), 0.0), "kein Bass -> keine Vorkompensation")
	var sat := AudioServer.get_bus_effect(_music, 6) as AudioEffectDistortion
	_check(sat.mode == AudioEffectDistortion.MODE_ATAN and sat.drive <= 0.3 \
		and is_equal_approx(sat.post_gain, -_settings.call("atan_gain_db", sat.drive)), "Saettigung atan, pegelneutral")
	_check(is_equal_approx(SongLoudness.TARGET_RMS_DB, -11.0) and is_equal_approx(SongLoudness.MIN_GAIN_DB, -4.0) \
		and is_equal_approx(SongLoudness.MAX_GAIN_DB, 6.0), "Loudness-Ziel -11 / -4..+6 dB")
	_check(is_equal_approx(SongLoudness.compute_gain_db(-8.0, -3.0), -3.0), "typischer Master-Song: nur -3 dB")
	_check(is_equal_approx(SongLoudness.compute_gain_db(-4.0, 0.0), -4.0), "max. Absenkung -4 dB")


func _start_measure() -> void:
	_rng.seed = 1234
	_cap_post = AudioEffectCapture.new()
	_cap_post.buffer_length = 0.5
	AudioServer.add_bus_effect(_music, _cap_post)
	_cap_master = AudioEffectCapture.new()
	_cap_master.buffer_length = 0.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), _cap_master)
	# Pink-Noise-Skalierung auf -11 dBFS RMS (Mono-Anteil + etwas Seite).
	var sq := 0.0
	for i in 48000:
		var v := _pink_sample()
		sq += v * v
	_noise_scale = db_to_linear(-11.0) / sqrt(sq / 48000.0)
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	var st := AudioStreamGenerator.new()
	st.mix_rate = AudioServer.get_mix_rate()
	st.buffer_length = 0.25
	_player.stream = st
	root.add_child(_player)
	_player.play()
	_gen = _player.get_stream_playback()
	_next_run()


func _next_run() -> void:
	_run += 1
	if _run >= _runs.size():
		return
	_settings.set("bass_boost", _runs[_run])
	_settings.set("audio_enhance", true)
	_settings.call("_apply_mastering")
	var rate := AudioServer.get_mix_rate()
	_k_pre = KWeight.new(rate)
	_k_post = KWeight.new(rate)
	_k_master = KWeight.new(rate)
	_peak_master = 0.0
	SongLoudness._capture.clear_buffer()
	_cap_post.clear_buffer()
	_cap_master.clear_buffer()
	_t0 = Time.get_ticks_msec()


func _pink_sample() -> float:
	var w := _rng.randf_range(-1.0, 1.0)
	_pink[0] = 0.99886 * _pink[0] + w * 0.0555179
	_pink[1] = 0.99332 * _pink[1] + w * 0.0750759
	_pink[2] = 0.96900 * _pink[2] + w * 0.1538520
	_pink[3] = 0.86650 * _pink[3] + w * 0.3104856
	_pink[4] = 0.55000 * _pink[4] + w * 0.5329522
	_pink[5] = -0.7616 * _pink[5] - w * 0.0168980
	var out: float = _pink[0] + _pink[1] + _pink[2] + _pink[3] + _pink[4] + _pink[5] + _pink[6] + w * 0.5362
	_pink[6] = w * 0.115926
	return out


func _feed() -> void:
	var n := _gen.get_frames_available()
	for i in n:
		var m := _pink_sample() * _noise_scale
		var side := _rng.randf_range(-1.0, 1.0) * 0.05
		_gen.push_frame(Vector2(m + side, m - side))


func _collect() -> void:
	var live := float(Time.get_ticks_msec() - _t0) / 1000.0 >= SKIP_SEC
	_drain(SongLoudness._capture, _k_pre, live, false)
	_drain(_cap_post, _k_post, live, false)
	_drain(_cap_master, _k_master, live, true)


func _drain(cap: AudioEffectCapture, k: KWeight, live: bool, track_peak: bool) -> void:
	var n := cap.get_frames_available()
	if n <= 0:
		return
	var buf := cap.get_buffer(n)
	if not live:
		return
	for v in buf:
		k.push(v)
		if track_peak:
			_peak_master = maxf(_peak_master, maxf(absf(v.x), absf(v.y)))


func _finish() -> void:
	if _results.size() < _runs.size():
		print("FAILED: ", _failed)
		quit(1)
		return
	print("  Pegel (K-gewichtet, Pink-Noise -11 dBFS RMS):")
	for r in _results:
		print("    bass %.2f  pre %.1f  post %.1f  master %.1f LUFS-ish  peak %.2f dBFS" % [
			r.bass, r.pre, r.post, r.master, r.peak])
	var r0: Dictionary = _results[0]
	var rd: Dictionary = _results[1]
	var r1: Dictionary = _results[2]
	var lift: float = r0.post - r0.pre
	_check(lift > -1.0 and lift < 2.0, "Kette ohne Bass: %+.1f dB ggue. pre (nicht leiser)" % lift)
	_check(rd.master > -10.5 and rd.master < -8.0, "Master-Lautheit Default-Bass %.1f (Ziel ~ -9)" % rd.master)
	_check(absf(r1.post - r0.post) < 1.5, "Bass 100%% vs 0%%: %+.1f dB (K-gewichtet, max 1.5 dB)" % (r1.post - r0.post))
	for r in _results:
		_check(r.peak <= 0.0, "kein Clipping bei bass %.2f (peak %.2f dBFS)" % [r.bass, r.peak])
	# Generator-Wiedergabe sauber beenden, bevor Godot herunterfaehrt: unter Last
	# stuerzte der Audio-Thread sonst gelegentlich beim Beenden ab (Exit != 0
	# nach "ALL OK").
	# _process gibt danach true zurueck (Ende der Hauptschleife), darum ohne await.
	_gen = null
	if _player != null:
		_player.stop()
		_player.get_parent().remove_child(_player)
		_player.free()
		_player = null
	if _failed > 0:
		print("FAILED: ", _failed)
		quit(1)
	else:
		print("ALL OK")
		quit(0)


## Vereinfachte K-Gewichtung (BS.1770: High-Shelf +4 dB ab ~1.5 kHz, HP 38 Hz),
## Mittelwert ueber L+R. Ergebnis grob in LUFS.
class KWeight:
	var _b: Array[PackedFloat64Array] = []
	# Zustand je (Kanal, Stufe): x1, x2, y1, y2 -> 2 * 2 * 4 Werte.
	var _s := PackedFloat64Array()
	var _sum := 0.0
	var _n := 0

	func _init(rate: float) -> void:
		_b.append(_shelf(rate, 1681.97, 3.9998, 0.7071))
		_b.append(_hp(rate, 38.13, 0.5003))
		_s.resize(16)
		_s.fill(0.0)

	func push(v: Vector2) -> void:
		var l := _biquad(1, 0, _biquad(0, 0, v.x))
		var r := _biquad(1, 1, _biquad(0, 1, v.y))
		_sum += l * l + r * r
		_n += 1

	func lufs() -> float:
		if _n == 0:
			return -100.0
		return -0.691 + 10.0 * log(_sum / float(_n)) / log(10.0)

	func _biquad(stage: int, ch: int, x: float) -> float:
		var c := _b[stage]
		var o := (ch * 2 + stage) * 4
		var y := c[0] * x + c[1] * _s[o] + c[2] * _s[o + 1] - c[3] * _s[o + 2] - c[4] * _s[o + 3]
		_s[o + 1] = _s[o]
		_s[o] = x
		_s[o + 3] = _s[o + 2]
		_s[o + 2] = y
		return y

	static func _shelf(fs: float, f0: float, g: float, q: float) -> PackedFloat64Array:
		var a := pow(10.0, g / 40.0)
		var w := TAU * f0 / fs
		var al := sin(w) / (2.0 * q)
		var cw := cos(w)
		var sa := 2.0 * sqrt(a) * al
		var a0 := (a + 1.0) - (a - 1.0) * cw + sa
		return PackedFloat64Array([a * ((a + 1.0) + (a - 1.0) * cw + sa) / a0,
			-2.0 * a * ((a - 1.0) + (a + 1.0) * cw) / a0,
			a * ((a + 1.0) + (a - 1.0) * cw - sa) / a0,
			2.0 * ((a - 1.0) - (a + 1.0) * cw) / a0,
			((a + 1.0) - (a - 1.0) * cw - sa) / a0])

	static func _hp(fs: float, f0: float, q: float) -> PackedFloat64Array:
		var w := TAU * f0 / fs
		var al := sin(w) / (2.0 * q)
		var cw := cos(w)
		var a0 := 1.0 + al
		return PackedFloat64Array([(1.0 + cw) / 2.0 / a0, -(1.0 + cw) / a0, (1.0 + cw) / 2.0 / a0,
			-2.0 * cw / a0, (1.0 - al) / a0])
