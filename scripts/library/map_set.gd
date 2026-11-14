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


## Spielmodus-Filter im Song-Browser: 4K-Mania-Diffs (Mode 3) gibt es in
## allen Modi, osu!standard-Diffs (Mode 0) NUR im Orbit-Modus (Orbit leitet
## seine Ziele aus den Positionen ab, Mania kann sie nicht spielen).
## 5K-7K-Diffs (ManiaKeys) nur in Mania selbst.
## play_mode: "mania" (4K-7K) | "mania@<n>" (nur nK, Tasten-Filter; Trace/Rebound:
## "mania@4") | "orbit" (Standard + 4K).
static func mode_shows(meta: Dictionary, play_mode: String) -> bool:
	var m := int(meta.get("mode", 0))
	if m == 3:
		var k := ManiaKeys.keys_of_meta(meta)
		if play_mode == "mania":
			return ManiaKeys.supported(k)
		if play_mode.begins_with("mania@"):
			return k == int(play_mode.trim_prefix("mania@"))
		return k == 4
	return m == 0 and play_mode == "orbit"


## Tastenzahlen der Mania-Diffs dieses Sets (aufsteigend, ohne Doppelte).
func key_counts() -> Array[int]:
	var out: Array[int] = []
	for d in diffs:
		var k := ManiaKeys.keys_of_meta(d)
		if k > 0 and not out.has(k):
			out.append(k)
	out.sort()
	return out


func diff_visible(index: int, play_mode: String) -> bool:
	return index >= 0 and index < diffs.size() and mode_shows(diffs[index], play_mode)


## Indizes der im Modus sichtbaren Diffs (leicht -> schwer).
func visible_diffs(play_mode: String) -> Array[int]:
	var out: Array[int] = []
	for i in diffs.size():
		if mode_shows(diffs[i], play_mode):
			out.append(i)
	return out


## Sichtbare Diff nahe index (index selbst, sonst die naechste darunter,
## sonst darueber); -1 wenn das Set im Modus nichts zeigt.
func nearest_visible(index: int, play_mode: String) -> int:
	if diff_visible(index, play_mode):
		return index
	var vis := visible_diffs(play_mode)
	if vis.is_empty():
		return -1
	var best := vis[0]
	for i in vis:
		if i <= index:
			best = i
	return best


## Sichtbare Diffs nach Modus-Sternen (leicht -> schwer). stars: Diff-Index ->
## Sterne des aktiven Modus; fehlt ein Index (oder < 0), zaehlen die Mania-Sterne
## vorlaeufig. Gleichstand: Bibliotheks-Reihenfolge (Index).
func visible_by_stars(play_mode: String, stars: Dictionary) -> Array[int]:
	var out := visible_diffs(play_mode)
	var val := {}
	for i in out:
		val[i] = star_or_base(i, stars)
	out.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(float(val[a]), float(val[b])):
			return float(val[a]) < float(val[b])
		return a < b)
	return out


## Modus-Sterne einer Diff aus stars, sonst die Mania-Sterne (vorlaeufig).
func star_or_base(index: int, stars: Dictionary) -> float:
	var st := float(stars.get(index, -1.0))
	return st if st >= 0.0 else stars_at(index)


## Hoechste Modus-Sterne der im Modus sichtbaren Diffs (-1 = keine).
func max_visible_stars(play_mode: String, stars: Dictionary) -> float:
	var m := -1.0
	for i in visible_diffs(play_mode):
		m = maxf(m, star_or_base(i, stars))
	return m


## Naechste Diff in der Modus-Reihenfolge order (dir -1/+1, ringfoermig);
## current fehlt in order -> erste Diff.
static func cycle_in(order: Array, current: int, dir: int) -> int:
	if order.is_empty():
		return current
	var at := order.find(current)
	if at < 0:
		return order[0]
	return order[wrapi(at + dir, 0, order.size())]


## osu!standard-Diff (Mode 0)?
func is_standard(index: int) -> bool:
	return int(meta_at(index).get("mode", -1)) == 0


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
		"sv": sv, "sv_ver": sv_ver, "kv": MapLibrary.KEYS_VERSION,
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
