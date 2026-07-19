extends Node

## Audio-Sync-Clock (Abschnitt 5) — die WICHTIGSTE technische Regel.
## Es gibt genau eine Uhr: die Audio-Position. Niemals delta-Zeit aufsummieren,
## niemals Time.get_ticks_msec() als Spielzeit verwenden.
##
## Autoload-Singleton "SyncClock". Liefert song_time_ms jeden Frame frisch aus:
##   (get_playback_position() + get_time_since_last_mix() - get_output_latency()) * 1000
##
## AudioLeadIn wird als Stille vor Songstart respektiert; waehrend der Lead-In-
## Phase (Audio spielt noch nicht) laeuft eine Vorlaufuhr von -lead_in bis 0.

signal song_started
signal song_finished

enum State { STOPPED, LEAD_IN, PLAYING }

## Globaler Kalibrierungs-Offset in ms (Settings-Slider, +/-200). Wird auf alle
## Judgements addiert (Pflicht-Feature — jedes Audio-Setup hat anderen Offset).
var user_offset_ms: float = 0.0

var _state: int = State.STOPPED
var _player: AudioStreamPlayer
var _lead_in_ms: float = 0.0
## Vorlaufuhr fuer die Lead-In-Phase (nur hier ist Delta-Zeit erlaubt, weil das
## Audio noch nicht spielt und keine Audio-Position existiert).
var _lead_in_elapsed_ms: float = 0.0
var _last_tick_usec: int = 0
var _finished_emitted: bool = false


var _spectrum: AudioEffectSpectrumAnalyzerInstance


func _ready() -> void:
	set_process(true)
	_player = AudioStreamPlayer.new()
	_player.name = "SyncAudioPlayer"
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_player_finished)
	# Spektrum-Analyzer auf dem Master-Bus: liefert Bass-/Hoehen-Energie fuer
	# musikreaktive Effekte.
	var bus := AudioServer.get_bus_index("Master")
	var eff := AudioEffectSpectrumAnalyzer.new()
	eff.buffer_length = 0.06
	AudioServer.add_bus_effect(bus, eff)
	_spectrum = AudioServer.get_bus_effect_instance(bus, AudioServer.get_bus_effect_count(bus) - 1)


## Normalisierte Energie (0..1) eines Frequenzbands. Bass ~ (30, 250),
## Hoehen ~ (2000, 8000).
func band_energy(from_hz: float, to_hz: float) -> float:
	if _spectrum == null:
		return 0.0
	var mag := _spectrum.get_magnitude_for_frequency_range(from_hz, to_hz).length()
	return clampf((linear_to_db(mag + 0.0000001) + 60.0) / 60.0, 0.0, 1.0)


## Song mit optionaler Lead-In-Stille starten.
func play(stream: AudioStream, lead_in_ms: float = 0.0) -> void:
	if stream == null:
		push_warning("SyncClock.play: kein AudioStream uebergeben.")
		return
	_player.stream = stream
	_lead_in_ms = maxf(lead_in_ms, 0.0)
	_lead_in_elapsed_ms = 0.0
	_finished_emitted = false
	_last_tick_usec = Time.get_ticks_usec()
	if _lead_in_ms > 0.0:
		_state = State.LEAD_IN
	else:
		_state = State.PLAYING
		_player.play()
		song_started.emit()


func stop() -> void:
	_player.stop()
	_state = State.STOPPED


## Pausiert das Audio (Song-Zeit friert ein). resume() setzt fort.
func pause() -> void:
	if _state == State.PLAYING:
		_player.stream_paused = true


func resume() -> void:
	if _state == State.PLAYING:
		_player.stream_paused = false
	elif _state == State.LEAD_IN:
		# Lead-In-Uhr nicht rueckwirkend springen lassen.
		_last_tick_usec = Time.get_ticks_usec()


## Nach vorn springen (Intro-Skip). Im Lead-In wird direkt an der
## Zielposition gestartet.
func seek_ms(target_ms: float) -> void:
	var sec := maxf(target_ms, 0.0) / 1000.0
	if _state == State.PLAYING:
		_player.seek(sec)
	elif _state == State.LEAD_IN:
		_state = State.PLAYING
		_player.play(sec)
		song_started.emit()


func is_paused() -> bool:
	return _player.stream_paused


func is_playing() -> bool:
	return _state == State.PLAYING or _state == State.LEAD_IN


## Rohe Song-Zeit in ms (die "Wahrheit"). Fuer Spawns, Slider-Progress etc.
func song_time_ms() -> float:
	match _state:
		State.LEAD_IN:
			return _lead_in_elapsed_ms - _lead_in_ms
		State.PLAYING:
			var pos := _player.get_playback_position()
			var since_mix := AudioServer.get_time_since_last_mix()
			var latency := AudioServer.get_output_latency()
			return (pos + since_mix - latency) * 1000.0
		_:
			return 0.0


## Judgement-Zeit = Song-Zeit + Kalibrierungs-Offset (Abschnitt 5).
## Diese Uhr wird fuer alle Timing-Vergleiche verwendet.
func judgement_time_ms() -> float:
	return song_time_ms() + user_offset_ms


func _process(_delta: float) -> void:
	if _state != State.LEAD_IN:
		return
	# Vorlaufuhr anhand echter Zeit fortschreiben (Audio spielt noch nicht).
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_tick_usec) / 1000.0
	_last_tick_usec = now
	_lead_in_elapsed_ms += dt_ms
	if _lead_in_elapsed_ms >= _lead_in_ms:
		_state = State.PLAYING
		_player.play()
		song_started.emit()


func _on_player_finished() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.STOPPED
	song_finished.emit()
