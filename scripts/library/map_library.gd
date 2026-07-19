class_name MapLibrary
extends RefCounted

## Scannt den maps-Ordner und baut die MapSet-Liste fuer den Song-Browser.
## v2 mit Bibliotheks-Cache (user://library.cfg): Jede .osz wird nur EINMAL
## voll geparst (Metadaten + Thumbnail), danach laedt der Browser aus dem
## Cache und oeffnet sofort — auch mit 100+ Maps.

const DEV_MAPS_DIR := "C:/Users/Gexanx/Desktop/rhyg/maps"
const CACHE_PATH := "user://library.cfg"

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
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		push_warning("MapLibrary: maps-Ordner nicht gefunden: " + maps_dir)
		return 0
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)

	# Nur fuer NEUE Dateien Stars im Batch vorberechnen.
	StarService.prefetch_dir(maps_dir)

	var files := dir.get_files()
	files.sort()
	var dirty := false
	for fname in files:
		if not fname.to_lower().ends_with(".osz"):
			continue
		var path := maps_dir.path_join(fname)
		var key := _cache_key(path)
		var cached = cfg.get_value("sets", key, false) if cfg.has_section_key("sets", key) else null
		var ms: MapSet = null
		if cached is Dictionary:
			ms = MapSet.from_dict(path, cached)
		else:
			ms = _build_mapset_full(path)
			if ms != null:
				cfg.set_value("sets", key, ms.to_dict())
				dirty = true
		if ms != null and ms.difficulty_count() > 0:
			mapsets.append(ms)
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
	var first: Beatmap = imp.difficulties[0].beatmap
	ms.title = first.title()
	ms.artist = first.artist()
	ms.creator = str(first.metadata.get("Creator", ""))
	ms.build_thumb()
	return ms


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
