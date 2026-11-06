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
##
## Monotonie: song_time_ms() laeuft innerhalb eines Songs NIE rueckwaerts.
## Quellwechsel (Lead-In -> Audio, Resume) springen roh um bis zu einen
## Mix-Block (get_time_since_last_mix ist dort veraltet bzw. die Godot-eigene
## Pause-Blende schiebt die Position). Solche Abweichungen werden weich
## nachgefuehrt (rueckwaerts: Uhr laeuft kurz langsamer/haelt an), nie hart
## gesetzt. Hart gesetzt wird nur vorwaerts (Seek) oder bei echtem Neustart
## (> 1 s zurueck). seek_ms() springt nur vorwaerts. Nur stop()/play() setzen
## die Zeit zurueck.
##
## Movie-Maker-Modus (--write-movie): die Spielzeit ist die FILM-Zeit, nicht
## die Wanduhr (Rendern ist dort langsamer/schneller als Echtzeit). Zeitbasis
## = Prozess-Frames / feste FPS (aus dem festen Prozess-Delta); Lead-In und
## Rampen laufen darauf. Waehrend der Wiedergabe: Film-Zeit + Versatz zur
## Audio-Position (MovieClock, sample-genau; die rohe Position springt im
## Film in 512er-Mix-Schritten), ohne Mix-Zeitstempel, Latenz und Glaettung
## -> Bild und Ton im Film deckungsgleich. Kein visual_offset im Film (keine
## Bildschirm-Latenz). Judgement-Fenster und user_offset unveraendert.

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
	## Bestaetigte Abweichung VORWAERTS darueber = Sprung (Seek): hart setzen.
	## Darunter wird nachgefuehrt.
	const JUMP_MS := 50.0
	## Rueckwaerts wird nie hart gesetzt (Mix-Stau, Pause-Blende: nur
	## nachfuehren, Uhr haelt kurz an) — ausser bei echtem Neustart der Quelle
	## (bestaetigt mehr als so weit zurueck).
	const RESTART_MS := 1000.0
	## Nach einem Quellwechsel (settle()) so lange (Wanduhr) jede Abweichung
	## bis RESTART_MS weich nachfuehren statt filtern oder springen.
	const SETTLE_MS := 300.0

	var _ok := false
	var _base_ms := 0.0
	var _anchor_usec := 0
	var _last_out := 0.0
	var _dev_avg := 0.0
	var _bad_ms := 0.0
	var _settle_ms := 0.0

	func reset(raw_ms: float, now_usec: int) -> void:
		_ok = true
		_base_ms = raw_ms
		_anchor_usec = now_usec
		_last_out = raw_ms
		_dev_avg = 0.0
		_bad_ms = 0.0
		_settle_ms = 0.0

	## Die Roh-Quelle wechselt (Lead-In -> Audio, Resume): Abweichung gilt
	## sofort als echt und wird weich (monoton) nachgefuehrt, nicht gesprungen.
	func settle() -> void:
		_settle_ms = SETTLE_MS
		_bad_ms = 0.0

	func invalidate() -> void:
		_ok = false

	func is_valid() -> bool:
		return _ok

	## Zeit steht (Pause): Wert halten, Wanduhr-Anker mitziehen. Nach der
	## Pause gilt die Audio-Uhr sofort als echt (settle(), kein Ausreisser-
	## Filter): liegt sie zurueck, haelt die Ausgabe kurz an, statt vorzulaufen.
	func hold(now_usec: int) -> float:
		_anchor_usec = now_usec
		_base_ms = _last_out
		_settle_ms = SETTLE_MS
		_bad_ms = 0.0
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
		if _settle_ms > 0.0:
			# Quellwechsel: jede Abweichung ist echt, weich nachfuehren.
			_settle_ms -= dt_ms
			_bad_ms = 0.0
			if err < -RESTART_MS or err > RESTART_MS:
				return _restart(raw_ms, now_usec)
		elif absf(err) > OUTLIER_MS:
			_bad_ms += dt_ms
			if _bad_ms < CONFIRM_MS:
				outlier = true
			elif err > JUMP_MS or err < -RESTART_MS:
				return _restart(raw_ms, now_usec)
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

	## Hart auf die Roh-Zeit setzen: vorwaerts (Seek) oder echter Neustart.
	func _restart(raw_ms: float, now_usec: int) -> float:
		reset(raw_ms, now_usec)
		return raw_ms


## Film-Uhr fuer die Wiedergabe im Movie-Modus. Reine Logik (testbar).
## Der Movie-Writer gibt pro Frame genau mix_rate/fps Samples aus, der Mixer
## mischt aber in 512er-Schritten vor: get_playback_position() liegt deshalb
## 0..10.7 ms VOR dem, was im Film gerade zu hoeren ist, wechselnd pro Frame.
## Exakt ist: Film-Zeit * Tempo + konstanter Versatz. Der Versatz ist das
## Minimum von (Position - Film-Zeit * Tempo) — erreicht, sobald der Mix-
## Vorrat leer ist (spaetestens nach 16 Frames). Steht das Audio (Pause),
## faellt das Minimum mit, die Uhr steht also ebenfalls.
class MovieClock:
	var _min := INF

	func reset() -> void:
		_min = INF

	## Audio startet jetzt (Film-Zeit film_ms) bei pos_ms: Versatz daran
	## festmachen, damit die Uhr stetig mit Film-Tempo weiterlaeuft (die
	## erste Mix-Position nach dem Start liegt bis zu 512 Samples voraus).
	func anchor(pos_ms: float, film_ms: float, rate: float = 1.0) -> void:
		_min = pos_ms - film_ms * rate

	func sample(pos_ms: float, film_ms: float, rate: float = 1.0) -> float:
		_min = minf(_min, pos_ms - film_ms * rate)
		return _min + film_ms * rate


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
## Movie-Maker-Modus (siehe Kopf): Zeitbasis = Frames / _movie_fps.
var _movie := false
## true = durch --write-movie aktiviert: FPS dann aus dem festen Prozess-
## Delta (OS.get_cmdline_args() enthaelt --fixed-fps nicht).
var _movie_auto := false
var _movie_fps := 60.0
## Film-Zeit stetig ueber FPS-Korrekturen: Basis + Frames seit Basis / FPS.
var _movie_base_usec := 0.0
var _movie_base_frames := 0
var _movie_clock := MovieClock.new()
const MOVIE_FPS_CONFIRM := 5
var _fps_cand := 0.0
var _fps_cnt := 0
## Letzter ausgegebener Wert im Movie-Modus (Monotonie, Pause-Halt).
var _movie_last := 0.0

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
	if Engine.get_write_movie_path() != "":
		set_movie_mode(true, movie_fps_from_cmdline())
		_movie_auto = true
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


## Start-Schaetzung der Film-FPS: --fixed-fps <n> (bzw. --fixed-fps=<n>),
## sonst editor/movie_writer/fps (Godot-Default 60). Godot nimmt --fixed-fps
## meist aus OS.get_cmdline_args() heraus; massgeblich ist daher das feste
## Prozess-Delta (_process korrigiert ab dem ersten Frame stetig).
static func movie_fps_from_cmdline(args: PackedStringArray = OS.get_cmdline_args()) -> float:
	for i in args.size():
		var a := args[i]
		var v := ""
		if a == "--fixed-fps" and i + 1 < args.size():
			v = args[i + 1]
		elif a.begins_with("--fixed-fps="):
			v = a.substr(12)
		if v.is_valid_float() and v.to_float() > 0.0:
			return v.to_float()
	var fps := float(ProjectSettings.get_setting("editor/movie_writer/fps", 60))
	return fps if fps > 0.0 else 60.0


## Movie-Zeitbasis an/aus (automatisch bei --write-movie; Tests schalten
## sie direkt). Nur zwischen Songs umschalten.
func set_movie_mode(enabled: bool, fps: float = 60.0) -> void:
	_movie = enabled
	_movie_auto = false
	_movie_base_usec = 0.0
	_movie_base_frames = 0
	_movie_fps = fps if fps > 0.0 else 60.0
	_movie_base_usec = float(Engine.get_process_frames()) * 1000000.0 / _movie_fps
	_movie_base_frames = Engine.get_process_frames()
	_movie_clock.reset()
	_refresh_latency()


## Movie-Modus: Prozess-Delta = 1 / feste FPS (mal time_scale), aber Godots
## Physik-Jitter-Ausgleich verbiegt einzelne Deltas (gemessen 0.0323 statt
## 0.0333). Erst uebernehmen, wenn derselbe Wert 5 Frames am Stueck kommt.
func _track_movie_fps(delta: float) -> void:
	var est := Engine.time_scale / delta
	var r := roundf(est)
	est = r if absf(est - r) < 0.01 else snappedf(est, 0.001)
	if est == _fps_cand:
		_fps_cnt += 1
	else:
		_fps_cand = est
		_fps_cnt = 1
	if _fps_cnt >= MOVIE_FPS_CONFIRM:
		_set_movie_fps(est)


## FPS korrigieren, ohne dass die Film-Zeit springt (neue Basis).
func _set_movie_fps(fps: float) -> void:
	if fps <= 0.0 or absf(fps - _movie_fps) < 0.0001:
		return
	var frames := Engine.get_process_frames()
	_movie_base_usec += float(frames - _movie_base_frames) * 1000000.0 / _movie_fps
	_movie_base_frames = frames
	_movie_fps = fps


func is_movie_mode() -> bool:
	return _movie


## Zeitbasis in usec: Wanduhr, im Movie-Modus die Film-Zeit (Prozess-Frames
## / feste FPS). Gilt fuer Lead-In, Glaettung und Rampen.
func _now_usec() -> int:
	if _movie:
		return int(round(_movie_base_usec
				+ float(Engine.get_process_frames() - _movie_base_frames) * 1000000.0 / _movie_fps))
	return Time.get_ticks_usec()


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
	_last_tick_usec = _now_usec()
	_refresh_latency()
	_smoother.invalidate()
	_movie_last = -INF
	if _lead_in_ms > 0.0:
		_state = State.LEAD_IN
	else:
		_start_audio(0.0)


## Audio ab from_ms starten; die Uhr laeuft nahtlos weiter. Kommt sie aus
## dem Lead-In, weicht die Audio-Rohzeit um bis zu einen Mix-Block ab
## (veralteter Mix-Zeitstempel): weich nachfuehren statt springen.
func _start_audio(from_ms: float) -> void:
	_state = State.PLAYING
	_player.play(maxf(from_ms, 0.0) / 1000.0)
	_movie_clock.anchor(maxf(from_ms, 0.0), float(_now_usec()) / 1000.0, _rate())
	if _smoother.is_valid():
		_smoother.settle()
	song_started.emit()


func stop() -> void:
	var fade_out := _state == State.PLAYING and not _paused \
			and _player.playing and not _player.stream_paused
	_state = State.STOPPED
	_paused = false
	_smoother.invalidate()
	_movie_last = -INF
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
		_advance_lead_in(_now_usec())
	else:
		_start_fade(0.0, FadeAction.PAUSE)


func resume() -> void:
	if not _paused:
		return
	_paused = false
	_refresh_latency()
	var now := _now_usec()
	# Gestoppte Uhr nicht rueckwirkend springen lassen. hold() schaltet die
	# Glaettung auf weiches Nachfuehren (settle), die Audio-Rohzeit liegt nach
	# der Pause um bis zu einen Mix-Block daneben.
	_last_tick_usec = now
	if _smoother.is_valid():
		_smoother.hold(now)
	if _state == State.PLAYING:
		var from := _current_fade_level()
		var was_paused := _player.stream_paused
		_cancel_fade()
		_player.stream_paused = false
		if was_paused and not _movie and _smoother.is_valid():
			_catch_up_audio(now)
		_start_fade(1.0, FadeAction.NONE, from)


## Nach einer echten Pause liegt die Audio-Rohzeit hinter der gehaltenen
## Uhr: die Uhr lief bis zum Pausieren mit (Position + Zeit seit Mix), Godots
## eigene Pause-Blende mischt aber nur noch ein Stueck. Statt die Uhr bis zu
## einen Mix-Block anhalten zu lassen, das (stumme, gleich eingeblendete)
## Audio auf die gehaltene Zeit vorspulen: Uhr und Audio sofort deckungsgleich.
func _catch_up_audio(now_usec: int) -> void:
	var held := _smoother.value()
	if _raw_time_ms(now_usec) >= held - Smoother.MAX_DEV_MS:
		return
	# Roh = Position + Zeit seit Mix - Latenz  ->  Position fuer Roh = held.
	var target := held + _latency_ms - AudioServer.get_time_since_last_mix() * 1000.0
	if target > 0.0:
		_player.seek(target / 1000.0)


## Nach vorn springen (Intro-Skip). Im Lead-In wird direkt an der
## Zielposition gestartet. Ziele hinter der aktuellen Song-Zeit werden
## ignoriert (die Uhr laeuft nie rueckwaerts).
func seek_ms(target_ms: float) -> void:
	var ms := maxf(target_ms, 0.0)
	if _state == State.STOPPED:
		return
	var cur := song_time_ms()
	_refresh_latency()
	if ms - _latency_ms <= cur:
		return
	if _state == State.PLAYING:
		_player.seek(ms / 1000.0)
		_movie_clock.anchor(ms, float(_now_usec()) / 1000.0, _rate())
	else:
		_start_audio(ms)
	var now := _now_usec()
	if _movie:
		return
	# Roh-Zeit direkt nach dem Seek (Position + Zeit seit Mix) ist mit dem
	# naechsten Mix-Block stetig -> darauf setzen, nie unter den alten Wert.
	_smoother.reset(maxf(_raw_time_ms(now), cur), now)


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return _state == State.PLAYING or _state == State.LEAD_IN


## Song-Zeit in ms (die "Wahrheit": was gerade hoerbar ist). Fuer Spawns,
## Slider-Progress etc. Geglaettet und monoton, siehe Kopf.
func song_time_ms() -> float:
	if _state == State.STOPPED:
		return 0.0
	var now := _now_usec()
	if _movie:
		# Film-Zeit ist exakt (kein Jitter, steht in der Pause von selbst:
		# Lead-In-Uhr bzw. Audio-Position): nur Monotonie absichern.
		_movie_last = maxf(_raw_time_ms(now), _movie_last)
		return _movie_last
	if _paused and (_state == State.LEAD_IN or _player.stream_paused):
		if _smoother.is_valid():
			return _smoother.hold(now)
		return _raw_time_ms(now)
	return _smoother.sample(_raw_time_ms(now), now, _rate())


## Ungeglaettete Zeit (nur Diagnose/Tests).
func raw_time_ms() -> float:
	return _raw_time_ms(_now_usec())


func _raw_time_ms(now_usec: int) -> float:
	match _state:
		State.LEAD_IN:
			var e := _lead_in_elapsed_ms
			if not _paused:
				e += float(now_usec - _last_tick_usec) / 1000.0
			return e - _lead_in_ms - _latency_ms
		State.PLAYING:
			if _movie:
				# Film-Uhr (MovieClock): Film-Zeit + Versatz zur Audio-Position,
				# kein Mix-Zeitstempel (waere Wanduhr), keine Latenz.
				return _movie_clock.sample(_player.get_playback_position() * 1000.0,
						float(now_usec) / 1000.0, _rate())
			# Position und Mix-Zeitstempel kommen aus dem Mix-Thread: faellt ein
			# Mix zwischen die beiden Abfragen, liegt die Summe einen Block
			# daneben. Zeitstempel davor/danach lesen, bei Mix neu lesen.
			var pos := 0.0
			var since_mix := 0.0
			for attempt in 3:
				var m0 := AudioServer.get_time_since_last_mix()
				pos = _player.get_playback_position()
				since_mix = AudioServer.get_time_since_last_mix()
				if since_mix >= m0:
					break
			return (pos + since_mix) * 1000.0 - _latency_ms
		_:
			return 0.0


func _rate() -> float:
	return _player.pitch_scale * AudioServer.playback_speed_scale


func _refresh_latency() -> void:
	# Im Film gibt es keine Ausgabelatenz (Audio liegt frame-genau im File).
	_latency_ms = 0.0 if _movie else AudioServer.get_output_latency() * 1000.0
	_latency_usec = Time.get_ticks_usec()


## Judgement-Zeit = Song-Zeit + Kalibrierungs-Offset (Abschnitt 5).
## Diese Uhr wird fuer alle Timing-Vergleiche verwendet.
func judgement_time_ms() -> float:
	return song_time_ms() + user_offset_ms


## Zeit fuer alles Sichtbare im Takt (BeatClock, Pulse, FX): song_time_ms +
## Settings.visual_offset_ms (Bildschirm-Latenz, Default 0). Siehe Kopf.
func visual_time_ms() -> float:
	return song_time_ms() + visual_offset_ms()


## Settings.visual_offset_ms, falls es das Feld gibt, sonst 0. Im Movie-
## Modus 0 (der Film hat keine Bildschirm-Latenz).
func visual_offset_ms() -> float:
	if _movie:
		return 0.0
	var s := get_node_or_null(^"/root/Settings")
	if s == null:
		return 0.0
	var v: Variant = s.get(&"visual_offset_ms")
	if v == null:
		return 0.0
	return float(v)


func _process(delta: float) -> void:
	if _movie_auto and delta > 0.0 and Engine.time_scale > 0.0:
		_track_movie_fps(delta)
	var now := _now_usec()
	if _fade_active:
		_update_fade(now)
	if _state == State.STOPPED:
		return
	if Time.get_ticks_usec() - _latency_usec > LATENCY_REFRESH_USEC:
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
			float(_now_usec() - _fade_start_usec) / 1000.0)


func _start_fade(to_lin: float, action: int, from_lin: float = -1.0) -> void:
	if from_lin < 0.0:
		from_lin = _current_fade_level()
	_fade_from = from_lin
	_fade_to = to_lin
	_fade_action = action
	_fade_start_usec = _now_usec()
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
