extends Node

## Audio-Sync-Clock (Abschnitt 5) — die WICHTIGSTE technische Regel.
## Es gibt genau eine Uhr: die Audio-Position. Niemals delta-Zeit aufsummieren,
## niemals Time.get_ticks_msec() als Spielzeit verwenden.
##
## Autoload-Singleton "SyncClock". Drei Zeiten, alle in ms Song-Zeit:
##   song_time_ms()       — was GERADE aus dem Lautsprecher kommt:
##       roh = (get_playback_position() + get_time_since_last_mix()) * 1000
##             - Ausgabelatenz
##       geglaettet durch Smoother (unten): monoton (nie rueckwaerts),
##       Mix-Jitter weggefiltert, Drift gegen die Audio-Position korrigiert,
##       gemittelte Abweichung zur Audio-Uhr max 1 ms. Bei JEDEM Aufruf frisch
##       berechnet (auch mitten im Frame, z. B. im _input-Callback).
##   judgement_time_ms()  — song_time_ms + user_offset_ms. NUR fuer Timing-
##       Vergleiche (Judgements, Replays). Fenster/Score haengen nur hieran.
##   visual_time_ms()     — song_time_ms + Settings.visual_offset_ms (falls
##       vorhanden, Default 0). Fuer alles, was man SIEHT und im Takt sein soll
##       (BeatClock, Puls/Wellen, FX): ein Bild wird erst nach der Bildschirm-
##       Latenz sichtbar, also positiver Wert = Bild laeuft so viele ms voraus.
##
## Ausgabelatenz: AudioServer.get_output_latency() ist teuer und wird daher
## gecacht (play/seek/resume + alle 2 s), nicht pro Aufruf abgefragt.
##
## AudioLeadIn wird als Stille vor Songstart respektiert; waehrend der Lead-In-
## Phase (Audio spielt noch nicht) laeuft eine Vorlaufuhr von -lead_in bis 0
## (ebenfalls latenzkorrigiert und pro Aufruf frisch, damit der Uebergang zur
## Audio-Uhr nahtlos ist).
##
## Pause/Resume/Stop: 12-ms-Lautstaerke-Rampe (nur volume_db) gegen Knackser.
## Die Zeitbasis bleibt unberuehrt: waehrend der Ausblende-Rampe laeuft das
## Audio (und damit die Uhr) wirklich weiter, danach steht beides.

signal song_started
signal song_finished

enum State { STOPPED, LEAD_IN, PLAYING }


## Glaettung der Audio-Uhr. Reine Logik (testbar): sagt die Zeit ueber die
## Wanduhr voraus und zieht sie sanft zur rohen Audio-Zeit. Die rohe Zeit
## springt pro Mix-Block (Thread-Jitter, Race zwischen Position und Mix-
## Zeitstempel); die Ausgabe nicht.
class Smoother:
	## Zeitkonstante der Nachfuehrung zur Audio-Uhr.
	const TAU_MS := 120.0
	## Zeitkonstante der gemittelten Rest-Abweichung.
	const AVG_TAU_MS := 100.0
	## Max. gemittelte Abweichung zur Audio-Uhr.
	const MAX_DEV_MS := 1.0
	## Abweichung ab der ein Sample als Ausreisser gilt (Mix-Block-Race:
	## ~10.7 ms bei 512 Frames / 48 kHz) ...
	const OUTLIER_MS := 8.0
	## ... und so lange (Wanduhr) muss sie bestehen, bis sie als echt gilt.
	const CONFIRM_MS := 40.0
	## Bestaetigte Abweichung darueber = Sprung (Seek, Neustart): hart setzen.
	## Darunter wird nachgefuehrt (rueckwaerts: Uhr haelt kurz an).
	const JUMP_MS := 50.0

	var _ok := false
	var _base_ms := 0.0
	var _anchor_usec := 0
	var _last_out := 0.0
	var _dev_avg := 0.0
	var _bad_ms := 0.0

	func reset(raw_ms: float, now_usec: int) -> void:
		_ok = true
		_base_ms = raw_ms
		_anchor_usec = now_usec
		_last_out = raw_ms
		_dev_avg = 0.0
		_bad_ms = 0.0

	func invalidate() -> void:
		_ok = false

	func is_valid() -> bool:
		return _ok

	## Zeit steht (Pause): Wert halten, Wanduhr-Anker mitziehen. Nach der
	## Pause gilt die Audio-Uhr sofort als echt (kein Ausreisser-Filter):
	## liegt sie zurueck, haelt die Ausgabe kurz an, statt vorzulaufen.
	func hold(now_usec: int) -> float:
		_anchor_usec = now_usec
		_base_ms = _last_out
		_bad_ms = CONFIRM_MS
		return _last_out

	func value() -> float:
		return _last_out

	## Neues Roh-Sample -> geglaettete, monotone Zeit. rate = Abspieltempo.
	func sample(raw_ms: float, now_usec: int, rate: float = 1.0) -> float:
		if not _ok:
			reset(raw_ms, now_usec)
			return raw_ms
		var dt_ms := maxf(float(now_usec - _anchor_usec) / 1000.0, 0.0)
		var pred := _base_ms + dt_ms * rate
		var err := raw_ms - pred
		var outlier := false
		if absf(err) > OUTLIER_MS:
			_bad_ms += dt_ms
			if _bad_ms < CONFIRM_MS:
				outlier = true
			elif absf(err) > JUMP_MS:
				reset(raw_ms, now_usec)
				return raw_ms
		else:
			_bad_ms = 0.0
		var out := pred
		if not outlier:
			out += err * (1.0 - exp(-dt_ms / TAU_MS))
			# Drift-Schranke: gemittelte Rest-Abweichung bleibt <= MAX_DEV_MS.
			_dev_avg += ((raw_ms - out) - _dev_avg) * (1.0 - exp(-dt_ms / AVG_TAU_MS))
			if absf(_dev_avg) > MAX_DEV_MS:
				var extra := _dev_avg - signf(_dev_avg) * MAX_DEV_MS
				out += extra
				_dev_avg -= extra
		out = maxf(out, _last_out)  # monoton: nie rueckwaerts
		_base_ms = out
		_anchor_usec = now_usec
		_last_out = out
		return out


## Globaler Kalibrierungs-Offset in ms (Settings-Slider, +/-200). Wird auf alle
## Judgements addiert (Pflicht-Feature — jedes Audio-Setup hat anderen Offset).
var user_offset_ms: float = 0.0

var _state: int = State.STOPPED
var _player: AudioStreamPlayer
var _lead_in_ms: float = 0.0
## Vorlaufuhr fuer die Lead-In-Phase (nur hier ist Wanduhr-Zeit erlaubt, weil
## das Audio noch nicht spielt und keine Audio-Position existiert).
var _lead_in_elapsed_ms: float = 0.0
var _last_tick_usec: int = 0
var _finished_emitted: bool = false
var _paused: bool = false
## Gecachte Ausgabelatenz in ms (siehe Kopf).
var _latency_ms: float = 0.0
var _latency_usec: int = 0
const LATENCY_REFRESH_USEC := 2000000
var _smoother := Smoother.new()

## Lautstaerke-Rampe (linear in Amplitude, ueber volume_db angewandt; der
## Mixer interpoliert volume_db zusaetzlich ueber jeden Mix-Block).
const FADE_MS := 12.0
enum FadeAction { NONE, PAUSE, STOP }
## Lautheits-Gain des Songs = volume_db im Normalbetrieb.
var _gain_db: float = 0.0
var _fade_active: bool = false
var _fade_from: float = 1.0
var _fade_to: float = 1.0
var _fade_start_usec: int = 0
var _fade_action: int = FadeAction.NONE
var _fade_reached: bool = false


## Bus fuer Song + Vorschau (send -> Master). Master bleibt fuer Hitsounds/UI.
const MUSIC_BUS := &"Music"
## Feste Effekt-Indizes auf dem Music-Bus (VOR der Mastering-Kette aus Settings).
const FX_SPECTRUM := 0
const FX_CAPTURE := 1


## Music-Bus anlegen, falls noch nicht vorhanden. Gibt seinen Index zurueck.
static func ensure_music_bus() -> int:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, MUSIC_BUS)
		AudioServer.set_bus_send(idx, &"Master")
	return idx


func _ready() -> void:
	set_process(true)
	# Laeuft auch bei pausiertem Tree (Rampe beim Pausieren). Die Lead-In-Uhr
	# respektiert stattdessen _paused (pause()/resume()).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Tasten-Events einzeln und sofort zustellen (nichts zusammenfassen).
	Input.use_accumulated_input = false
	_refresh_latency()
	var bus := ensure_music_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "SyncAudioPlayer"
	_player.bus = MUSIC_BUS
	add_child(_player)
	_player.finished.connect(_on_player_finished)
	# Spektrum-Analyzer als ERSTER Effekt auf dem Music-Bus (pre-Mastering):
	# liefert Bass-/Hoehen-Energie fuer musikreaktive Effekte.
	var eff := AudioEffectSpectrumAnalyzer.new()
	eff.buffer_length = 0.06
	AudioServer.add_bus_effect(bus, eff, FX_SPECTRUM)
	# Capture direkt danach (Index 1, vor der Mastering-Kette): Lautheitsmessung.
	SongLoudness.attach_capture(bus, FX_CAPTURE)


## Aktuelle Analyzer-Instanz (Music[0]). Jedes add_bus_effect auf dem Bus
## (z. B. die Mastering-Kette aus Settings) erzeugt NEUE Instanzen, eine
## gecachte Instanz waere danach tot -> immer frisch holen.
func spectrum_instance() -> AudioEffectSpectrumAnalyzerInstance:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0 or AudioServer.get_bus_effect_count(bus) <= FX_SPECTRUM:
		return null
	return AudioServer.get_bus_effect_instance(bus, FX_SPECTRUM) as AudioEffectSpectrumAnalyzerInstance


## Normalisierte Energie (0..1) eines Frequenzbands. Bass ~ (30, 250),
## Hoehen ~ (2000, 8000).
func band_energy(from_hz: float, to_hz: float) -> float:
	var spec := spectrum_instance()
	if spec == null:
		return 0.0
	var mag := spec.get_magnitude_for_frequency_range(from_hz, to_hz).length()
	return clampf((linear_to_db(mag + 0.0000001) + 60.0) / 60.0, 0.0, 1.0)


## Song mit optionaler Lead-In-Stille starten.
func play(stream: AudioStream, lead_in_ms: float = 0.0) -> void:
	if stream == null:
		push_warning("SyncClock.play: kein AudioStream uebergeben.")
		return
	_player.stream = stream
	# Lautheits-Normalisierung: nur volume_db, unbekannter Song = 0 dB.
	_gain_db = SongLoudness.gain_db_for_osz(GameSession.osz_path)
	_cancel_fade()
	_player.volume_db = _gain_db
	_player.stream_paused = false
	_paused = false
	_lead_in_ms = maxf(lead_in_ms, 0.0)
	_lead_in_elapsed_ms = 0.0
	_finished_emitted = false
	_last_tick_usec = Time.get_ticks_usec()
	_refresh_latency()
	_smoother.invalidate()
	if _lead_in_ms > 0.0:
		_state = State.LEAD_IN
	else:
		_start_audio(0.0)


## Audio ab from_ms starten; die Uhr laeuft nahtlos weiter.
func _start_audio(from_ms: float) -> void:
	_state = State.PLAYING
	_player.play(maxf(from_ms, 0.0) / 1000.0)
	song_started.emit()


func stop() -> void:
	var fade_out := _state == State.PLAYING and not _paused \
			and _player.playing and not _player.stream_paused
	_state = State.STOPPED
	_paused = false
	_smoother.invalidate()
	if fade_out:
		# Ausblenden, danach wirklich stoppen (play() bricht die Rampe ab).
		_start_fade(0.0, FadeAction.STOP)
	else:
		_cancel_fade()
		_player.stop()
		_player.stream_paused = false
		_player.volume_db = _gain_db


## Pausiert das Audio (Song-Zeit friert nach der Ausblende-Rampe ein).
## resume() setzt fort.
func pause() -> void:
	if _state == State.STOPPED or _paused:
		return
	_paused = true
	if _state == State.LEAD_IN:
		_advance_lead_in(Time.get_ticks_usec())
	else:
		_start_fade(0.0, FadeAction.PAUSE)


func resume() -> void:
	if not _paused:
		return
	_paused = false
	_refresh_latency()
	var now := Time.get_ticks_usec()
	# Gestoppte Uhr nicht rueckwirkend springen lassen.
	_last_tick_usec = now
	if _smoother.is_valid():
		_smoother.hold(now)
	if _state == State.PLAYING:
		var from := _current_fade_level()
		_cancel_fade()
		_player.stream_paused = false
		_start_fade(1.0, FadeAction.NONE, from)


## Nach vorn springen (Intro-Skip). Im Lead-In wird direkt an der
## Zielposition gestartet.
func seek_ms(target_ms: float) -> void:
	var ms := maxf(target_ms, 0.0)
	_refresh_latency()
	if _state == State.PLAYING:
		_player.seek(ms / 1000.0)
	elif _state == State.LEAD_IN:
		_start_audio(ms)
	else:
		return
	_smoother.reset(ms - _latency_ms, Time.get_ticks_usec())


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return _state == State.PLAYING or _state == State.LEAD_IN


## Song-Zeit in ms (die "Wahrheit": was gerade hoerbar ist). Fuer Spawns,
## Slider-Progress etc. Geglaettet und monoton, siehe Kopf.
func song_time_ms() -> float:
	if _state == State.STOPPED:
		return 0.0
	var now := Time.get_ticks_usec()
	if _paused and (_state == State.LEAD_IN or _player.stream_paused):
		if _smoother.is_valid():
			return _smoother.hold(now)
		return _raw_time_ms(now)
	return _smoother.sample(_raw_time_ms(now), now, _rate())


## Ungeglaettete Zeit (nur Diagnose/Tests).
func raw_time_ms() -> float:
	return _raw_time_ms(Time.get_ticks_usec())


func _raw_time_ms(now_usec: int) -> float:
	match _state:
		State.LEAD_IN:
			var e := _lead_in_elapsed_ms
			if not _paused:
				e += float(now_usec - _last_tick_usec) / 1000.0
			return e - _lead_in_ms - _latency_ms
		State.PLAYING:
			var pos := _player.get_playback_position()
			var since_mix := AudioServer.get_time_since_last_mix()
			return (pos + since_mix) * 1000.0 - _latency_ms
		_:
			return 0.0


func _rate() -> float:
	return _player.pitch_scale * AudioServer.playback_speed_scale


func _refresh_latency() -> void:
	_latency_ms = AudioServer.get_output_latency() * 1000.0
	_latency_usec = Time.get_ticks_usec()


## Judgement-Zeit = Song-Zeit + Kalibrierungs-Offset (Abschnitt 5).
## Diese Uhr wird fuer alle Timing-Vergleiche verwendet.
func judgement_time_ms() -> float:
	return song_time_ms() + user_offset_ms


## Zeit fuer alles Sichtbare im Takt (BeatClock, Pulse, FX): song_time_ms +
## Settings.visual_offset_ms (Bildschirm-Latenz, Default 0). Siehe Kopf.
func visual_time_ms() -> float:
	return song_time_ms() + visual_offset_ms()


## Settings.visual_offset_ms, falls es das Feld gibt, sonst 0.
func visual_offset_ms() -> float:
	var s := get_node_or_null(^"/root/Settings")
	if s == null:
		return 0.0
	var v: Variant = s.get(&"visual_offset_ms")
	if v == null:
		return 0.0
	return float(v)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _fade_active:
		_update_fade(now)
	if _state == State.STOPPED:
		return
	if now - _latency_usec > LATENCY_REFRESH_USEC:
		_refresh_latency()
	if _state != State.LEAD_IN or _paused:
		return
	# Vorlaufuhr anhand echter Zeit fortschreiben (Audio spielt noch nicht).
	_advance_lead_in(now)
	if _lead_in_elapsed_ms >= _lead_in_ms:
		# Ueberhang (bis zu einem Frame) als Startposition: die Audio-Uhr setzt
		# genau dort fort, wo die Vorlaufuhr steht — kein Rueckwaertssprung.
		_start_audio(_lead_in_elapsed_ms - _lead_in_ms)


func _advance_lead_in(now_usec: int) -> void:
	_lead_in_elapsed_ms += float(now_usec - _last_tick_usec) / 1000.0
	_last_tick_usec = now_usec


# --- Lautstaerke-Rampe -------------------------------------------------------

## Rampen-Pegel (linear) t_ms nach Rampenstart. Reine Funktion (Tests).
static func fade_level(from_lin: float, to_lin: float, t_ms: float, dur_ms: float = FADE_MS) -> float:
	if dur_ms <= 0.0:
		return to_lin
	return lerpf(from_lin, to_lin, clampf(t_ms / dur_ms, 0.0, 1.0))


## Linearer Faktor relativ zum Lautheits-Gain -> volume_db (0.0001 = -80 dB).
func _apply_level(lin: float) -> void:
	_player.volume_db = _gain_db + linear_to_db(maxf(lin, 0.0001))


func _current_fade_level() -> float:
	if not _fade_active:
		return 0.0 if _player.stream_paused else 1.0
	return fade_level(_fade_from, _fade_to,
			float(Time.get_ticks_usec() - _fade_start_usec) / 1000.0)


func _start_fade(to_lin: float, action: int, from_lin: float = -1.0) -> void:
	if from_lin < 0.0:
		from_lin = _current_fade_level()
	_fade_from = from_lin
	_fade_to = to_lin
	_fade_action = action
	_fade_start_usec = Time.get_ticks_usec()
	_fade_active = true
	_fade_reached = false
	_apply_level(from_lin)


func _cancel_fade() -> void:
	_fade_active = false
	_fade_reached = false
	_fade_action = FadeAction.NONE


func _update_fade(now_usec: int) -> void:
	if _fade_reached:
		# Endpegel wurde in einem frueheren Frame gesetzt (also schon gemixt):
		# erst jetzt pausieren/stoppen.
		var action := _fade_action
		_cancel_fade()
		match action:
			FadeAction.PAUSE:
				_player.stream_paused = true
			FadeAction.STOP:
				_player.stop()
				_player.volume_db = _gain_db
		return
	var t_ms := float(now_usec - _fade_start_usec) / 1000.0
	_apply_level(fade_level(_fade_from, _fade_to, t_ms))
	if t_ms >= FADE_MS:
		if _fade_action == FadeAction.NONE:
			_cancel_fade()
		else:
			_fade_reached = true


func _on_player_finished() -> void:
	if _finished_emitted or _state == State.STOPPED:
		return
	_finished_emitted = true
	_state = State.STOPPED
	song_finished.emit()
