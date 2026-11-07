class_name MapSet
extends RefCounted

## Ein Mapset = eine .osz-Datei mit einer oder mehreren Difficulties.
## v2: haelt NUR Metadaten (aus dem Bibliotheks-Cache) — keine geparsten
## Beatmaps mehr. Dadurch oeffnet der Browser auch mit 100+ Maps sofort;
## voll geparst wird erst beim Spielen (Gameplay-Szene).

var osz_path: String = ""
var title: String = ""
var artist: String = ""
var creator: String = ""
var background_file: String = ""
## true, wenn mindestens eine Diff echte SV hat (MapLibrary.detect_sv).
var sv: bool = false
## Cache-Version der SV-Erkennung; != MapLibrary.SV_VERSION -> nachrechnen.
var sv_ver: int = 0

## Pro Difficulty ein Dictionary (leicht -> schwer sortiert):
## { version, osu_filename, stars, max_combo, notes, duration_ms,
##   cs, ar, od, preview_time, audio_filename, sv, holds, bpm }
## holds = Anzahl Long Notes, bpm = vorherrschendes Tempo (fehlen in alten
## Cache-Eintraegen, bis der Hintergrund-Nachlauf sie ergaenzt).
var diffs: Array = []

var _thumb_cache: Texture2D = null
var _thumb_loaded := false


func difficulty_count() -> int:
	return diffs.size()

func meta_at(index: int) -> Dictionary:
	if index < 0 or index >= diffs.size():
		return {}
	return diffs[index]

func version_name_at(index: int) -> String:
	return str(meta_at(index).get("version", ""))

func stars_at(index: int) -> float:
	return float(meta_at(index).get("stars", -1.0))

func osu_filename_at(index: int) -> String:
	return str(meta_at(index).get("osu_filename", ""))

func max_stars() -> float:
	var m := -1.0
	for d in diffs:
		m = maxf(m, float(d.get("stars", -1.0)))
	return m

func length_ms() -> float:
	var longest := 0.0
	for d in diffs:
		longest = maxf(longest, float(d.get("duration_ms", 0.0)))
	return longest

func has_sv() -> bool:
	return sv


## Alte Cache-Eintraege ohne Long-Note-/BPM-Werte: Nachlauf noetig.
func needs_stats() -> bool:
	for d in diffs:
		if not d.has("holds"):
			return true
	return false


## Kennwerte einer Diff fuer Filter: {ln (Long-Note-Anteil %), len_s, bpm};
## -1 = unbekannt.
func stats_at(index: int) -> Dictionary:
	var m := meta_at(index)
	var notes := int(m.get("notes", 0))
	var ln := -1
	if m.has("holds") and notes > 0:
		ln = roundi(float(m.holds) * 100.0 / float(notes))
	var dur := float(m.get("duration_ms", 0.0))
	return { "ln": ln, "len_s": roundi(dur / 1000.0) if dur > 0.0 else -1,
		"bpm": roundi(float(m.bpm)) if float(m.get("bpm", 0.0)) > 0.0 else -1 }


## Ergebnis des Hintergrund-Nachlaufs uebernehmen: by_file = { osu_filename:
## bool (nur SV) oder {sv, holds, bpm} }.
func apply_sv(by_file: Dictionary) -> void:
	sv = false
	for d in diffs:
		var r = by_file.get(str(d.get("osu_filename", "")), false)
		var v := false
		if r is Dictionary:
			v = bool(r.get("sv", false))
			if r.has("holds"):
				d["holds"] = int(r.holds)
				d["bpm"] = float(r.get("bpm", 0.0))
		else:
			v = bool(r)
		d["sv"] = v
		sv = sv or v
	sv_ver = MapLibrary.SV_VERSION


func search_haystack() -> String:
	return ("%s %s %s" % [artist, title, creator]).to_lower()


## Kleines Cover (Disk-Cache): fuer Karten-Liste — schnell, kein Zip-Zugriff
## nach dem ersten Scan.
func thumb_texture() -> Texture2D:
	if _thumb_loaded:
		return _thumb_cache
	_thumb_loaded = true
	var path := thumb_path()
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			_thumb_cache = ImageTexture.create_from_image(img)
			return _thumb_cache
	# Fallback: jetzt bauen (einmalig langsam).
	_thumb_cache = build_thumb()
	return _thumb_cache


## Volles Hintergrundbild (ein Zip-Zugriff) — nur fuer die aktuelle Auswahl.
func background_texture() -> Texture2D:
	if background_file == "":
		return null
	return OszImporter.load_image_texture(osz_path, background_file)


func thumb_path() -> String:
	var size := 0
	if FileAccess.file_exists(osz_path):
		var f := FileAccess.open(osz_path, FileAccess.READ)
		size = f.get_length()
	return "user://covers/%s_%d.webp" % [osz_path.get_file().md5_text(), size]


## Thumbnail aus dem Zip erzeugen und auf Disk cachen (~320px breit).
func build_thumb() -> Texture2D:
	if background_file == "":
		return null
	var tex := OszImporter.load_image_texture(osz_path, background_file)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var scale := 320.0 / maxf(float(img.get_width()), 1.0)
	if scale < 1.0:
		img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://covers"))
	img.save_webp(ProjectSettings.globalize_path(thumb_path()), true, 0.82)
	var out := ImageTexture.create_from_image(img)
	_thumb_cache = out
	_thumb_loaded = true
	return out


func to_dict() -> Dictionary:
	return {
		"title": title, "artist": artist, "creator": creator,
		"background_file": background_file, "diffs": diffs,
		"sv": sv, "sv_ver": sv_ver,
	}


static func from_dict(p_osz_path: String, d: Dictionary) -> MapSet:
	var ms := MapSet.new()
	ms.osz_path = p_osz_path
	ms.title = str(d.get("title", ""))
	ms.artist = str(d.get("artist", ""))
	ms.creator = str(d.get("creator", ""))
	ms.background_file = str(d.get("background_file", ""))
	ms.diffs = d.get("diffs", [])
	ms.sv = bool(d.get("sv", false))
	ms.sv_ver = int(d.get("sv_ver", 0))
	return ms
