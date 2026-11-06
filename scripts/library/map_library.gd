class_name MapLibrary
extends RefCounted

## Scannt den maps-Ordner und baut die MapSet-Liste fuer den Song-Browser.
## v2 mit Bibliotheks-Cache (user://library.cfg): Jede .osz wird nur EINMAL
## voll geparst (Metadaten + Thumbnail), danach laedt der Browser aus dem
## Cache und oeffnet sofort — auch mit 100+ Maps.

const DEV_MAPS_DIR := "C:/Users/Gexanx/Desktop/rhyg/maps"
const CACHE_PATH := "user://library.cfg"
## Version der "unbrauchbar"-Markierung: hochzaehlen, wenn der Importer neue
## Modi/Keycounts unterstuetzt, damit alte Skip-Eintraege neu geprueft werden.
const SKIP_VERSION := 1
## Version der SV-Erkennung: hochzaehlen -> alle Cache-Eintraege werden einmal
## im Hintergrund nachgerechnet (start_sv_backfill).
const SV_VERSION := 1
## Mindestanzahl gruener Linien mit SV != 1.0 fuer "echte SV".
const SV_MIN_LINES := 10

## Sets aus dem Cache ohne aktuelle SV-Erkennung (siehe start_sv_backfill).
var sv_pending: Array[String] = []
var _sv_thread: Thread = null
var _sv_cancel := false

var maps_dir: String = ""
var mapsets: Array[MapSet] = []


## "maps"-Ordner neben der Exe (Release UND Dev — die Godot-Exe liegt im
## Projektordner). Fallback: fester Dev-Pfad. KEIN has_feature("editor"):
## das ist beim Editor-Binary auch im PCK-Release true.
static func default_maps_dir() -> String:
	var local := OS.get_executable_path().get_base_dir().path_join("maps")
	if DirAccess.dir_exists_absolute(local):
		return local
	return DEV_MAPS_DIR


func _init(dir: String = "") -> void:
	maps_dir = dir if dir != "" else default_maps_dir()


## Ordner (neu) scannen. Gibt die Anzahl gefundener Mapsets zurueck.
func scan() -> int:
	mapsets.clear()
	sv_pending.clear()
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		push_warning("MapLibrary: maps-Ordner nicht gefunden: " + maps_dir)
		return 0
	var t0 := Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	OszImporter._perf("Library: Cache laden", t0, CACHE_PATH)
	t0 = Time.get_ticks_usec()

	var files := dir.get_files()
	files.sort()
	# Erst aus dem Cache bedienen; nur unbekannte Dateien voll analysieren.
	# Unbrauchbare Sets (keine Standard-/4K-Diff, kaputtes Zip) stehen als
	# {"skip": SKIP_VERSION} im Cache — sonst wuerden sie bei JEDEM Oeffnen neu
	# geparst und loesten jedes Mal den python-Sternelauf aus.
	var fresh: Array[String] = []
	for fname in files:
		if not fname.to_lower().ends_with(".osz"):
			continue
		var path := maps_dir.path_join(fname)
		var key := _cache_key(path)
		var cached = cfg.get_value("sets", key, null) if cfg.has_section_key("sets", key) else null
		if cached is Dictionary:
			if int(cached.get("skip", 0)) == SKIP_VERSION:
				continue
			if not cached.has("skip"):
				var ms := MapSet.from_dict(path, cached)
				if ms.difficulty_count() > 0:
					mapsets.append(ms)
					if ms.sv_ver != SV_VERSION:
						sv_pending.append(path)
				continue
		fresh.append(path)
	OszImporter._perf("Library: %d Sets aus Cache" % mapsets.size(), t0, maps_dir)

	var dirty := false
	if not fresh.is_empty():
		t0 = Time.get_ticks_usec()
		# Nur fuer NEUE Dateien Stars im Batch vorberechnen.
		if fresh.size() >= 2:
			StarService.prefetch_dir(maps_dir)
		for path in fresh:
			var ms := _build_mapset_full(path)
			if ms != null:
				cfg.set_value("sets", _cache_key(path), ms.to_dict())
				if ms.difficulty_count() > 0:
					mapsets.append(ms)
			else:
				cfg.set_value("sets", _cache_key(path), {"skip": SKIP_VERSION})
			dirty = true
		OszImporter._perf("Library: %d neue Dateien analysiert" % fresh.size(), t0, maps_dir)
	if dirty:
		cfg.save(CACHE_PATH)
	mapsets.sort_custom(func(a, b): return a.search_haystack() < b.search_haystack())
	return mapsets.size()


static func _cache_key(osz_path: String) -> String:
	var size := 0
	if FileAccess.file_exists(osz_path):
		var f := FileAccess.open(osz_path, FileAccess.READ)
		size = f.get_length()
	return "%s|%d" % [osz_path.get_file(), size]


## Einmalige Voll-Analyse einer .osz: parsen, Metadaten extrahieren,
## Thumbnail auf Disk legen.
func _build_mapset_full(osz_path: String) -> MapSet:
	var imp := OszImporter.import(osz_path)
	if not imp.ok or imp.difficulties.is_empty():
		return null
	var ms := MapSet.new()
	ms.osz_path = osz_path
	var star_data := StarService.stars_for(osz_path)
	var entries: Array = []
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		# Standard (0) immer; Mania nur als 4K.
		if bm.is_mania() and bm.column_count() != 4:
			continue
		var fname: String = d.osu_filename
		var s := -1.0
		var mc := 0
		if star_data.has(fname):
			s = float(star_data[fname].get("stars", -1.0))
			mc = int(star_data[fname].get("max_combo", 0))
		entries.append({
			"version": bm.version_name(), "osu_filename": fname,
			"stars": s, "max_combo": mc, "mode": bm.mode(),
			"notes": bm.note_count(), "duration_ms": bm.duration_ms(),
			"cs": bm.cs(), "ar": bm.ar(), "od": bm.od(),
			"preview_time": float(bm.general.get("PreviewTime", -1.0)),
			"audio_filename": bm.audio_filename(),
			"_sort_notes": bm.note_count(),
			"sv": detect_sv(bm.timing_points),
		})
		if ms.background_file == "" and bm.background_file != "":
			ms.background_file = bm.background_file
	if entries.is_empty():
		return null
	entries.sort_custom(func(a, b):
		if float(a.stars) >= 0.0 and float(b.stars) >= 0.0:
			return float(a.stars) < float(b.stars)
		return int(a._sort_notes) < int(b._sort_notes))
	ms.diffs = entries
	ms.sv = false
	for e in entries:
		ms.sv = ms.sv or bool(e.sv)
	ms.sv_ver = SV_VERSION
	var first: Beatmap = imp.difficulties[0].beatmap
	ms.title = first.title()
	ms.artist = first.artist()
	ms.creator = str(first.metadata.get("Creator", ""))
	ms.build_thumb()
	return ms


## Echte SV: mindestens SV_MIN_LINES gruene Linien mit SV != 1.0 (auf 3
## Stellen gerundet). Reine Tempo-Wechsel (rote Linien) zaehlen nicht.
static func detect_sv(timing_points: Array) -> bool:
	var n := 0
	for tp in timing_points:
		if tp.uninherited:
			continue
		if absf(roundf(ScrollMap.green_sv(tp) * 1000.0) / 1000.0 - 1.0) > 0.0005:
			n += 1
			if n >= SV_MIN_LINES:
				return true
	return false


func sv_backfill_running() -> bool:
	return _sv_thread != null


## Rechnet die SV-Erkennung fuer Cache-Eintraege ohne aktuelle Version im
## Hintergrund nach. on_done() kommt im Hauptthread, nachdem Sets und
## library.cfg aktualisiert sind.
func start_sv_backfill(on_done: Callable) -> void:
	if _sv_thread != null or sv_pending.is_empty():
		return
	var todo: Array[String] = sv_pending.duplicate()
	sv_pending.clear()
	_sv_cancel = false
	_sv_thread = Thread.new()
	_sv_thread.start(_sv_worker.bind(todo, on_done))


func _sv_worker(paths: Array[String], on_done: Callable) -> void:
	var out := {}
	for path in paths:
		if _sv_cancel:
			break
		var imp := OszImporter._import_uncached(path)
		var by_file := {}
		if imp.get("ok", false):
			for d in imp.difficulties:
				by_file[str(d.osu_filename)] = detect_sv(d.beatmap.timing_points)
		out[path] = by_file
	_sv_finish.call_deferred(out, on_done)


func _sv_finish(results: Dictionary, on_done: Callable) -> void:
	if _sv_thread != null:
		_sv_thread.wait_to_finish()
		_sv_thread = null
	if _sv_cancel:
		return
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	for ms in mapsets:
		if results.has(ms.osz_path):
			ms.apply_sv(results[ms.osz_path])
			cfg.set_value("sets", _cache_key(ms.osz_path), ms.to_dict())
	cfg.save(CACHE_PATH)
	if on_done.is_valid():
		on_done.call()


## Thread beim Szenenende abwarten.
func shutdown() -> void:
	_sv_cancel = true
	if _sv_thread != null:
		_sv_thread.wait_to_finish()
		_sv_thread = null


## Eine externe .osz in den maps-Ordner importieren (Drag&Drop/Download).
func import_external(source_path: String) -> String:
	if not source_path.to_lower().ends_with(".osz"):
		return ""
	if not FileAccess.file_exists(source_path):
		return ""
	DirAccess.make_dir_recursive_absolute(maps_dir)
	var dest := maps_dir.path_join(source_path.get_file())
	if FileAccess.file_exists(dest):
		var base := source_path.get_file().get_basename()
		var i := 1
		while FileAccess.file_exists(dest):
			dest = maps_dir.path_join("%s (%d).osz" % [base, i])
			i += 1
	var err := DirAccess.copy_absolute(source_path, dest)
	if err != OK:
		push_error("Import fehlgeschlagen (%d): %s" % [err, source_path])
		return ""
	return dest
