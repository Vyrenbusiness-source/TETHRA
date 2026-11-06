class_name SongLoudness
extends RefCounted

## Lautheits-Normalisierung pro Song. Misst waehrend der Vorschau im Song-Browser
## RMS + Peak (AudioEffectCapture auf Master direkt nach dem SpectrumAnalyzer,
## also VOR EQ/Kompressor/Limiter) und speichert den Ziel-Gain in user://loudness.cfg.
## Der Gain wirkt nur ueber volume_db des Players: keine Latenz, Timing unberuehrt.

const TARGET_RMS_DB := -16.0
const MIN_GAIN_DB := -12.0
const MAX_GAIN_DB := 6.0
const PEAK_CEIL_DB := -1.0
const MIN_MEASURE_SEC := 6.0
const SILENCE_DB := -60.0

static var cache_path := "user://loudness.cfg"

static var _capture: AudioEffectCapture
static var _key := ""
static var _sum_sq := 0.0
static var _frames := 0
static var _peak := 0.0
static var _rate := 48000.0
static var _cfg: ConfigFile


## Reine Formel: Ziel-Gain aus gemessenem RMS/Peak (dBFS).
static func compute_gain_db(rms_db: float, peak_db: float) -> float:
	var g := clampf(TARGET_RMS_DB - rms_db, MIN_GAIN_DB, MAX_GAIN_DB)
	if peak_db + g > PEAK_CEIL_DB:
		g = PEAK_CEIL_DB - peak_db
	return g


static func make_key(osz_path: String, audio_filename: String) -> String:
	return "%s|%s" % [osz_path.get_file(), audio_filename]


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(cache_path)
	return _cfg


static func reset_cache_for_tests(path: String) -> void:
	cache_path = path
	_cfg = null


static func store(song_key: String, gain_db: float) -> void:
	var cfg := _load()
	cfg.set_value("gain", song_key, gain_db)
	cfg.save(cache_path)


## Gain fuer einen Song (0 dB wenn unbekannt).
static func gain_db_for(song_key: String) -> float:
	var cfg := _load()
	if song_key != "" and cfg.has_section_key("gain", song_key):
		return float(cfg.get_value("gain", song_key, 0.0))
	return 0.0


static func has_key(song_key: String) -> bool:
	return _load().has_section_key("gain", song_key)


## Gain ueber den osz-Dateinamen allein (Gameplay kennt den Audio-Dateinamen nicht).
static func gain_db_for_osz(osz_path: String) -> float:
	if osz_path == "":
		return 0.0
	var cfg := _load()
	if not cfg.has_section("gain"):
		return 0.0
	var prefix := osz_path.get_file() + "|"
	for k in cfg.get_section_keys("gain"):
		if k.begins_with(prefix):
			return float(cfg.get_value("gain", k, 0.0))
	return 0.0


## Von SyncClock aufgerufen: Capture-Effekt direkt hinter den Analyzer haengen.
static func attach_capture(bus: int) -> void:
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.25
	AudioServer.add_bus_effect(bus, _capture)
	_rate = AudioServer.get_mix_rate()


static func is_measuring() -> bool:
	return _key != ""


static func measured_sec() -> float:
	return float(_frames) / _rate


static func measure_start(song_key: String) -> void:
	_key = song_key
	_sum_sq = 0.0
	_frames = 0
	_peak = 0.0
	if _capture != null:
		_capture.clear_buffer()


## Pro Frame aufrufen. player_db = aktuelle volume_db des Vorschau-Players
## (wird herausgerechnet, Fade-In-Anfang wird uebersprungen).
static func poll(player_db: float) -> void:
	if _key == "" or _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	if player_db < -20.0:
		return
	var comp := db_to_linear(-player_db)
	for v in buf:
		var s := (v.x + v.y) * 0.5 * comp
		_sum_sq += s * s
		var p := maxf(absf(v.x), absf(v.y)) * comp
		if p > _peak:
			_peak = p
	_frames += buf.size()


## Beendet die Messung; speichert nur bei >= 6 s Material. Gibt den Gain zurueck
## oder NAN, wenn nichts gespeichert wurde.
static func measure_stop() -> float:
	var key := _key
	_key = ""
	if key == "" or float(_frames) / _rate < MIN_MEASURE_SEC:
		return NAN
	var rms := sqrt(_sum_sq / float(_frames))
	var rms_db := linear_to_db(rms)
	if rms_db < SILENCE_DB:
		return NAN
	var g := compute_gain_db(rms_db, linear_to_db(_peak))
	store(key, g)
	return g
