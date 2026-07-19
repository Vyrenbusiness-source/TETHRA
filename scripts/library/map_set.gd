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

## Pro Difficulty ein Dictionary (leicht -> schwer sortiert):
## { version, osu_filename, stars, max_combo, notes, duration_ms,
##   cs, ar, od, preview_time, audio_filename }
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
	}


static func from_dict(p_osz_path: String, d: Dictionary) -> MapSet:
	var ms := MapSet.new()
	ms.osz_path = p_osz_path
	ms.title = str(d.get("title", ""))
	ms.artist = str(d.get("artist", ""))
	ms.creator = str(d.get("creator", ""))
	ms.background_file = str(d.get("background_file", ""))
	ms.diffs = d.get("diffs", [])
	return ms
