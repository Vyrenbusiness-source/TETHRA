class_name OszImporter
extends RefCounted

## Import einer .osz-Datei (Abschnitt 3.1). Eine .osz ist ein ZIP-Archiv:
## eine oder mehrere .osu-Dateien (eine pro Difficulty), die Audio-Datei
## (mp3/ogg) und optional Hintergrundbilder/Hitsounds (ignorierbar).
##
## Import-Flow: entpacken -> .osu-Dateien listen -> Difficulty waehlen ->
## zugehoerige Audio-Datei laden.

## Lade-Messung (--perf, gesetzt von GameSession): jede Lade-Phase loggt ihre Dauer.
static var perf := false


static func _perf(phase: String, t0: int, what: String) -> void:
	if perf:
		print("PERF %-44s %9.1f ms  (%s)" % [phase, float(Time.get_ticks_usec() - t0) / 1000.0, what.get_file()])


## Vorbereitung im Hintergrund (Song-Browser): prepare() parst die .osz und
## laedt Audio + Hintergrund in einem WorkerThreadPool-Task. import(),
## load_audio_stream*() und load_*_texture() nehmen danach das Fertige, statt
## erneut zu entpacken/dekodieren. Laeuft der Task noch, wartet der Aufrufer
## auf ihn (kein doppeltes Laden).
## - import-Ergebnis: EINMALIG (Gameplay veraendert Beatmaps; Retry parst neu).
## - Audio/Bilder: kleiner LRU-Cache (unveraenderliche Ressourcen).
const AUDIO_CACHE_MAX := 3
const IMAGE_CACHE_MAX := 4
static var _mutex := Mutex.new()
static var _prepared := {}      # osz_path -> import-Dictionary (einmalig)
static var _tasks := {}         # osz_path -> WorkerThreadPool-Task-ID
static var _audio_cache := {}   # "osz|name" -> AudioStream (Einfuege-Reihenfolge = LRU)
static var _image_cache := {}   # "osz|name" -> Texture2D


## Auswahl im Hintergrund vorbereiten (idempotent). audio_name/bg_name duerfen
## leer sein; version = Difficulty, deren eigenes Hintergrundbild (falls anders
## als bg_name) nach dem Parsen ebenfalls vorgeladen wird.
static func prepare(osz_path: String, audio_name: String, bg_name: String, version: String = "") -> void:
	_mutex.lock()
	var busy := _tasks.has(osz_path) or _prepared.has(osz_path)
	if not busy:
		_tasks[osz_path] = WorkerThreadPool.add_task(
			OszImporter._prepare_task.bind(osz_path, audio_name, bg_name, version), false, "osz prepare")
	_mutex.unlock()
	_reap_tasks()


static func _prepare_task(osz_path: String, audio_name: String, bg_name: String, version: String) -> void:
	var t0 := Time.get_ticks_usec()
	# Reihenfolge: Bild (Browser zeigt es zuerst), Audio, dann Vollparse.
	if bg_name != "" and _cache_get(_image_cache, _ckey(osz_path, bg_name)) == null:
		_cache_put(_image_cache, _ckey(osz_path, bg_name),
			_load_image_uncached(osz_path, bg_name), IMAGE_CACHE_MAX)
	if audio_name != "" and _cache_get(_audio_cache, _ckey(osz_path, audio_name)) == null:
		_cache_put(_audio_cache, _ckey(osz_path, audio_name),
			_load_audio_uncached(osz_path, audio_name), AUDIO_CACHE_MAX)
	var res := _import_uncached(osz_path)
	_mutex.lock()
	_prepared[osz_path] = res
	_mutex.unlock()
	for d in res.difficulties:
		var bm: Beatmap = d.beatmap
		if bm.version_name() == version and bm.background_file != "" 				and _cache_get(_image_cache, _ckey(osz_path, bm.background_file)) == null:
			_cache_put(_image_cache, _ckey(osz_path, bm.background_file),
				_load_image_uncached(osz_path, bm.background_file), IMAGE_CACHE_MAX)
	_perf("Hintergrund: Auswahl vorbereitet", t0, osz_path)


## True, sobald prepare() fuer diese .osz fertig ist (oder nie lief).
static func is_prepared(osz_path: String) -> bool:
	_mutex.lock()
	var running := _tasks.has(osz_path)
	var task_id: int = _tasks.get(osz_path, -1)
	_mutex.unlock()
	return not running or WorkerThreadPool.is_task_completed(task_id)


## Laufenden Vorbereitungs-Task dieser .osz abwarten (no-op ohne Task).
static func _wait_prepared(osz_path: String) -> void:
	_mutex.lock()
	var task_id: int = _tasks.get(osz_path, -1)
	_tasks.erase(osz_path)
	_mutex.unlock()
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)


## Fertige Tasks abholen (WorkerThreadPool verlangt wait_for_task_completion).
static func _reap_tasks() -> void:
	_mutex.lock()
	var done: Array = []
	for k in _tasks:
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			done.append(k)
	var ids: Array = []
	for k in done:
		ids.append(_tasks[k])
		_tasks.erase(k)
	# Nur die zuletzt angefragten Vorbereitungen behalten (Speicher).
	while _prepared.size() > 2:
		_prepared.erase(_prepared.keys()[0])
	_mutex.unlock()
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)


static func _ckey(osz_path: String, inner_name: String) -> String:
	return osz_path + "|" + inner_name.get_file().to_lower()


static func _cache_get(cache: Dictionary, key: String) -> Variant:
	_mutex.lock()
	var v = cache.get(key)
	if v != null:
		cache.erase(key)
		cache[key] = v   # ans Ende = zuletzt benutzt
	_mutex.unlock()
	return v


static func _cache_put(cache: Dictionary, key: String, v: Variant, max_n: int) -> void:
	if v == null:
		return
	_mutex.lock()
	cache.erase(key)
	cache[key] = v
	while cache.size() > max_n:
		cache.erase(cache.keys()[0])
	_mutex.unlock()


## import(path) liefert:
##   {
##     ok: bool, error: String,
##     difficulties: Array[Dictionary]  # { osu_filename, beatmap: Beatmap }
##   }
## Nur Mode-0-.osu-Dateien landen in difficulties; abgelehnte werden uebersprungen.
static func import(osz_path: String) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	_wait_prepared(osz_path)
	_mutex.lock()
	var pre = _prepared.get(osz_path)
	_prepared.erase(osz_path)
	_mutex.unlock()
	if pre is Dictionary:
		_perf("osz importieren (vorbereitet)", t0, osz_path)
		return pre
	var res := _import_uncached(osz_path)
	_perf("osz entpacken + alle .osu parsen", t0, osz_path)
	return res


static func _import_uncached(osz_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(osz_path)
	if err != OK:
		return { "ok": false, "error": "Konnte .osz nicht oeffnen (Fehler %d): %s" % [err, osz_path], "difficulties": [] }

	var files := reader.get_files()
	var difficulties: Array[Dictionary] = []
	var rejected: Array[String] = []

	for fname in files:
		if not fname.to_lower().ends_with(".osu"):
			continue
		var bytes := reader.read_file(fname)
		var text := bytes.get_string_from_utf8()
		var res := OsuParser.parse(text)
		if res.ok:
			difficulties.append({ "osu_filename": fname, "beatmap": res.beatmap })
		else:
			rejected.append("%s: %s" % [fname, res.error])

	reader.close()

	if difficulties.is_empty():
		var reason := "Keine gueltigen osu!standard-Difficulties im Archiv."
		if not rejected.is_empty():
			reason += " (" + ", ".join(rejected) + ")"
		return { "ok": false, "error": reason, "difficulties": [] }

	# Nach Difficulty-Name sortieren waere ideal nach Star Rating (kommt via
	# rosu-pp in M4); vorerst alphabetisch nach Version-Name.
	difficulties.sort_custom(func(a, b):
		return String(a.beatmap.version_name()) < String(b.beatmap.version_name()))

	return { "ok": true, "error": "", "difficulties": difficulties }


## Rohe Bytes einer Datei aus dem Archiv lesen (z.B. die Audio-Datei).
static func read_file_bytes(osz_path: String, inner_name: String) -> PackedByteArray:
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return PackedByteArray()
	var data := reader.read_file(inner_name)
	reader.close()
	return data


## Audio-Datei einer Difficulty als AudioStream laden.
static func load_audio_stream(osz_path: String, beatmap: Beatmap) -> AudioStream:
	return load_audio_stream_named(osz_path, beatmap.audio_filename())


## Audio direkt per Dateiname laden (fuer den Browser-Cache, ohne Beatmap).
static func load_audio_stream_named(osz_path: String, target: String) -> AudioStream:
	if target == "":
		return null
	var t0 := Time.get_ticks_usec()
	var key := _ckey(osz_path, target)
	var hit = _cache_get(_audio_cache, key)
	if hit == null and _tasks.has(osz_path):
		_wait_prepared(osz_path)
		hit = _cache_get(_audio_cache, key)
	if hit != null:
		_perf("Audio laden (Cache)", t0, osz_path)
		return hit
	var out := _load_audio_uncached(osz_path, target)
	_cache_put(_audio_cache, key, out, AUDIO_CACHE_MAX)
	_perf("Audio laden", t0, osz_path)
	return out


static func _load_audio_uncached(osz_path: String, target: String) -> AudioStream:
	if target == "":
		return null
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return null
	var match_name := ""
	for fname in reader.get_files():
		if fname.get_file().to_lower() == target.to_lower():
			match_name = fname
			break
	if match_name == "":
		reader.close()
		return null
	var bytes := reader.read_file(match_name)
	reader.close()
	return _stream_from_bytes(bytes, match_name)


## Hintergrundbild einer Difficulty als Texture2D laden (aus [Events]).
static func load_background_texture(osz_path: String, beatmap: Beatmap) -> Texture2D:
	if beatmap.background_file == "":
		return null
	return load_image_texture(osz_path, beatmap.background_file)


## Beliebige Bilddatei aus dem Archiv als Texture2D laden (case-insensitiv,
## Suche nur ueber den Basisnamen, da .osu-Pfade Unterordner enthalten koennen).
static func load_image_texture(osz_path: String, inner_name: String) -> Texture2D:
	if inner_name == "":
		return null
	var t0 := Time.get_ticks_usec()
	var key := _ckey(osz_path, inner_name)
	var hit = _cache_get(_image_cache, key)
	if hit == null and _tasks.has(osz_path):
		_wait_prepared(osz_path)
		hit = _cache_get(_image_cache, key)
	if hit != null:
		_perf("Bild laden (Cache)", t0, osz_path)
		return hit
	var out := _load_image_uncached(osz_path, inner_name)
	_cache_put(_image_cache, key, out, IMAGE_CACHE_MAX)
	_perf("Bild laden (" + inner_name.get_file().left(20) + ")", t0, osz_path)
	return out


static func _load_image_uncached(osz_path: String, inner_name: String) -> Texture2D:
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return null
	var target := inner_name.get_file().to_lower()
	var match_name := ""
	for fname in reader.get_files():
		if fname.get_file().to_lower() == target:
			match_name = fname
			break
	if match_name == "":
		reader.close()
		return null
	var bytes := reader.read_file(match_name)
	reader.close()

	var img := decode_image_bytes(bytes)
	if img == null:
		return null
	# Mipmaps erlauben weichen Blur (textureLod) z.B. im Main-Menue.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Bild nach Magic-Bytes dekodieren (nicht nach Endung). Kaputt/unbekannt: null.
static func decode_image_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4D:
		err = img.load_bmp_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 			and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return img


static func _stream_from_bytes(bytes: PackedByteArray, filename: String) -> AudioStream:
	var lower := filename.to_lower()
	if lower.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	elif lower.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	elif lower.ends_with(".wav"):
		# WAV-Rohladen ist aufwendiger; in v1 nicht Pflicht.
		return null
	return null
