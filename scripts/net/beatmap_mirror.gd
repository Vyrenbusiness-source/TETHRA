class_name BeatmapMirror
extends Node

## Direkter Beatmap-Download vom Mirror catboy.best (kein Login noetig).
## Laeuft als Autoload "Mirror": Downloads laufen PARALLEL und ueberleben
## jeden Szenenwechsel (Browser schliessen, Map spielen, Menue — egal).
##  - search(query): liefert Beatmapsets (4K-Mania, ranked).
##  - fetch_cover(set_id, url): laedt das Cover asynchron als Texture.
##  - download(set_id, dest_dir): laedt die .osz in den Maps-Ordner.
## Alle Ergebnisse kommen ueber Signale zurueck.

const SEARCH_URL := "https://catboy.best/api/v2/search"
## Download-Mirrors in Reihenfolge — schlaegt einer fehl (oder liefert Muell),
## springt der Download automatisch zum naechsten.
const DOWNLOAD_URLS := [
	"https://catboy.best/d/",
	"https://osu.direct/api/d/",
	"https://api.nerinyan.moe/d/",
]

signal search_done(results: Array, raw_count: int, offset: int)
signal search_failed(message: String)
signal cover_ready(set_id: int, texture: Texture2D)
signal download_progress(set_id: int, ratio: float)
signal download_done(set_id: int, osz_path: String)
signal download_failed(set_id: int, message: String)
## SV-Pruefung einer Diff fertig (check_sv). is_sv false auch bei Fehlern.
signal sv_checked(beatmap_id: int, is_sv: bool)

## Einzelne .osu per beatmap_id (per Testanfrage ermittelt; Mirror verlangt
## einen User-Agent, den HTTPRequest automatisch sendet).
const OSU_URL := "https://catboy.best/osu/"
const SV_CACHE_PATH := "user://sv_online_cache.cfg"
const SV_MAX_PARALLEL := 4

var _search_req: HTTPRequest
var _search_offset := 0
## SV-Filter: hängt "sv" an die Suche an und markiert Treffer (Feld "sv").
var sv_mode := false
## Aktive Downloads: set_id -> {req: HTTPRequest, dest: String, idx: int}.
var _downloads: Dictionary = {}
## SV-Pruefung: Cache (Abschnitt v<SV_VERSION>, Schluessel beatmap_id -> bool),
## Warteschlange, laufende Anfragen (id -> HTTPRequest), Fehlschlaege.
var _sv_cache: ConfigFile = null
var _sv_queue: Array[int] = []
var _sv_active: Dictionary = {}
var _sv_failed: Dictionary = {}
var _sv_dirty := 0


func _ready() -> void:
	_search_req = HTTPRequest.new()
	_search_req.timeout = 15.0
	add_child(_search_req)
	_search_req.request_completed.connect(_on_search_completed)



# ---------------------------------------------------------------------------
# Suche
# ---------------------------------------------------------------------------

func search(query: String, offset: int = 0) -> void:
	var q := query.strip_edges()
	if sv_mode and not is_sv_text(q):
		q = (q + " sv").strip_edges()
	_search_offset = offset
	# mode=3: osu!mania · status=1: nur RANKED · offset: Seiten fuer
	# unendliches Scrollen.
	var url := "%s?query=%s&limit=50&offset=%d&mode=3&status=1" % [
		SEARCH_URL, url_escape(q), offset]
	_search_req.cancel_request()
	var err := _search_req.request(url)
	if err != OK:
		search_failed.emit("Suche fehlgeschlagen (Fehler %d)." % err)


func _on_search_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		search_failed.emit("Keine Verbindung zum Mirror (HTTP %d)." % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array):
		search_failed.emit("Unerwartete Antwort vom Mirror.")
		return
	var results: Array = []
	for item in data:
		if not (item is Dictionary):
			continue
		# Absicherung: nur wirklich ranked Sets (falls der Server-Param
		# ignoriert wird).
		if str(item.get("status", "")) != "ranked":
			continue
		var std := _mania4k_difficulty(item)
		if std.is_empty():
			continue  # keine 4K-Mania-Difficulty -> ueberspringen
		var covers: Dictionary = item.get("covers", {})
		results.append({
			"id": int(item.get("id", 0)),
			"title": str(item.get("title", "?")),
			"artist": str(item.get("artist", "?")),
			"creator": str(item.get("creator", "?")),
			"stars": float(std.get("difficulty_rating", 0.0)),
			"star_list": std.get("star_list", []),
			"diffs": int(std.get("count", 1)),
			"cover_url": str(covers.get("card", covers.get("cover", ""))),
			"preview_url": _https(str(item.get("preview_url", ""))),
			"status": str(item.get("status", "")),
			"sv": is_sv_item(item),
			"sv_id": sv_check_id(item),
		})
	search_done.emit(results, data.size(), _search_offset)


## Text nennt SV: Wort "sv" oder "slider velocity"/"scroll velocity".
static func is_sv_text(text: String) -> bool:
	var t := text.to_lower()
	if t.contains("slider velocity") or t.contains("scroll velocity") 			or t.contains("sv gimmick"):
		return true
	var word := ""
	for ch in t + " ":
		if ch.unicode_at(0) < 128 and (ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9"):
			word += ch
		else:
			if word == "sv" or word == "svs":
				return true
			word = ""
	return false


## Set ist ein SV-Set: Titel, Tags oder Diff-Namen (4K) nennen SV.
static func is_sv_item(item: Dictionary) -> bool:
	if is_sv_text(str(item.get("title", ""))) or is_sv_text(str(item.get("tags", ""))):
		return true
	for bm in item.get("beatmaps", []):
		if bm is Dictionary and int(bm.get("mode_int", -1)) == 3 				and is_sv_text(str(bm.get("version", ""))):
			return true
	return false


## Hoechste 4K-Mania-Difficulty eines Sets (oder leer, wenn keine).
## Bei Mania ist cs = Spaltenzahl -> nur cs == 4 zaehlt.
func _mania4k_difficulty(item: Dictionary) -> Dictionary:
	var best := {}
	var count := 0
	var star_list: Array = []
	for bm in item.get("beatmaps", []):
		if not (bm is Dictionary):
			continue
		if int(bm.get("mode_int", -1)) != 3:
			continue
		if int(round(float(bm.get("cs", 0.0)))) != 4:
			continue
		count += 1
		star_list.append(float(bm.get("difficulty_rating", 0.0)))
		if best.is_empty() or float(bm.get("difficulty_rating", 0.0)) > float(best.get("difficulty_rating", 0.0)):
			best = bm
	if best.is_empty():
		return {}
	best = best.duplicate()
	best["count"] = count
	best["star_list"] = star_list
	return best


# ---------------------------------------------------------------------------
# SV-Pruefung: .osu einer 4K-Diff laden und mit MapLibrary.sv_stats pruefen
# ---------------------------------------------------------------------------

## Diff-ID eines Sets fuer die SV-Pruefung: 4K-Diff, deren Name SV nennt,
## sonst die schwerste 4K-Diff. 0, wenn keine.
static func sv_check_id(item: Dictionary) -> int:
	var best := {}
	for bm in item.get("beatmaps", []):
		if not (bm is Dictionary) or int(bm.get("mode_int", -1)) != 3 \
				or int(round(float(bm.get("cs", 0.0)))) != 4:
			continue
		if is_sv_text(str(bm.get("version", ""))):
			return int(bm.get("id", 0))
		if best.is_empty() or float(bm.get("difficulty_rating", 0.0)) \
				> float(best.get("difficulty_rating", 0.0)):
			best = bm
	return int(best.get("id", 0))


## Ergebnis der SV-Pruefung einer Diff: 1 = SV, 0 = keine SV (oder Fehler),
## -1 = noch nicht geprueft.
func sv_state(beatmap_id: int) -> int:
	if beatmap_id <= 0 or _sv_failed.has(beatmap_id):
		return 0
	_load_sv_cache()
	if not _sv_cache.has_section_key(_sv_section(), str(beatmap_id)):
		return -1
	return 1 if bool(_sv_cache.get_value(_sv_section(), str(beatmap_id), false)) else 0


## Diff zur SV-Pruefung einreihen (max. SV_MAX_PARALLEL Anfragen parallel).
## Ergebnis kommt ueber sv_checked.
func check_sv(beatmap_id: int) -> void:
	if beatmap_id <= 0 or sv_state(beatmap_id) != -1 \
			or _sv_active.has(beatmap_id) or _sv_queue.has(beatmap_id):
		return
	_sv_queue.append(beatmap_id)
	_pump_sv()


## Offene SV-Pruefungen (wartend + laufend).
func sv_checks_pending() -> int:
	return _sv_queue.size() + _sv_active.size()


## Wartende SV-Pruefungen verwerfen (neue Suche); laufende enden normal.
func cancel_sv_checks() -> void:
	_sv_queue.clear()


func _sv_section() -> String:
	return "v%d" % MapLibrary.SV_VERSION


func _load_sv_cache() -> void:
	if _sv_cache != null:
		return
	_sv_cache = ConfigFile.new()
	_sv_cache.load(SV_CACHE_PATH)


func _pump_sv() -> void:
	while _sv_active.size() < SV_MAX_PARALLEL and not _sv_queue.is_empty():
		var id: int = _sv_queue.pop_front()
		var req := HTTPRequest.new()
		req.timeout = 15.0
		add_child(req)
		req.request_completed.connect(_on_sv_completed.bind(id))
		_sv_active[id] = req
		if req.request(OSU_URL + str(id)) != OK:
			_finish_sv(id, false, false)


func _on_sv_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, id: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_sv(id, false, false)
		return
	var parsed := OsuParser.parse(body.get_string_from_utf8())
	if not parsed.get("ok", false):
		_finish_sv(id, false, false)
		return
	_finish_sv(id, MapLibrary.detect_sv(parsed.beatmap), true)


func _finish_sv(id: int, is_sv: bool, ok: bool) -> void:
	var req: HTTPRequest = _sv_active.get(id)
	_sv_active.erase(id)
	if is_instance_valid(req):
		req.queue_free()
	if ok:
		_load_sv_cache()
		_sv_cache.set_value(_sv_section(), str(id), is_sv)
		_sv_dirty += 1
	else:
		_sv_failed[id] = true  # in dieser Sitzung nicht erneut anfragen
	if _sv_dirty > 0 and (_sv_dirty >= 10 or sv_checks_pending() == 0):
		_sv_cache.save(SV_CACHE_PATH)
		_sv_dirty = 0
	sv_checked.emit(id, is_sv and ok)
	_pump_sv()


# ---------------------------------------------------------------------------
# Cover
# ---------------------------------------------------------------------------

func fetch_cover(set_id: int, url: String) -> void:
	if url == "":
		return
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var tex := _texture_from_bytes(body)
			if tex != null:
				cover_ready.emit(set_id, tex)
		req.queue_free())
	if req.request(_https(url)) != OK:
		req.queue_free()


func _texture_from_bytes(body: PackedByteArray) -> Texture2D:
	var img := Image.new()
	var ok := false
	if img.load_jpg_from_buffer(body) == OK:
		ok = true
	elif img.load_png_from_buffer(body) == OK:
		ok = true
	if not ok:
		return null
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

func download(set_id: int, dest_dir: String) -> void:
	if _downloads.has(set_id):
		return  # laeuft schon — einfach weiterlaufen lassen
	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK \
			and not DirAccess.dir_exists_absolute(dest_dir):
		download_failed.emit(set_id, "maps-Ordner nicht beschreibbar: " + dest_dir)
		return
	var req := HTTPRequest.new()
	req.timeout = 120.0
	req.use_threads = true
	# 4-MB-Chunks statt 64 KB Standard — deutlich hoehere Download-Rate.
	req.download_chunk_size = 4 * 1024 * 1024
	add_child(req)
	req.request_completed.connect(_on_download_completed.bind(set_id))
	_downloads[set_id] = {
		"req": req,
		"dest": dest_dir.path_join("mirror_%d.osz" % set_id),
		"idx": 0,
	}
	_start_download_attempt(set_id)


## Laeuft fuer dieses Set gerade ein Download?
func is_downloading(set_id: int) -> bool:
	return _downloads.has(set_id)


## Fortschritt (0..1) eines laufenden Downloads, -1 wenn keiner laeuft.
func active_ratio(set_id: int) -> float:
	if not _downloads.has(set_id):
		return -1.0
	var req: HTTPRequest = _downloads[set_id].req
	var total := req.get_body_size()
	if total <= 0:
		return 0.0
	return clampf(float(req.get_downloaded_bytes()) / float(total), 0.0, 1.0)


func _start_download_attempt(set_id: int) -> void:
	var d: Dictionary = _downloads[set_id]
	var req: HTTPRequest = d.req
	req.download_file = d.dest
	var err := req.request(DOWNLOAD_URLS[d.idx] + str(set_id))
	if err != OK:
		_advance_or_fail(set_id, "Download-Start fehlgeschlagen (Fehler %d)." % err)


## Naechsten Mirror probieren; erst wenn alle durch sind, endgueltig aufgeben.
func _advance_or_fail(set_id: int, msg: String) -> void:
	var d: Dictionary = _downloads[set_id]
	if FileAccess.file_exists(d.dest):
		DirAccess.remove_absolute(d.dest)
	d.idx += 1
	if d.idx < DOWNLOAD_URLS.size():
		_start_download_attempt(set_id)
		return
	_finish_download(set_id)
	download_failed.emit(set_id, msg)


func _process(_delta: float) -> void:
	for set_id in _downloads:
		var r := active_ratio(set_id)
		if r > 0.0:
			download_progress.emit(set_id, r)


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, set_id: int) -> void:
	if not _downloads.has(set_id):
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		var why := "HTTP %d" % code
		match result:
			HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
				why = "Zielordner nicht beschreibbar"
			HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CANT_CONNECT:
				why = "keine Verbindung"
			HTTPRequest.RESULT_TIMEOUT:
				why = "Zeitueberschreitung"
		_advance_or_fail(set_id, "Download fehlgeschlagen (%s)." % why)
		return
	# Verifizieren, dass es wirklich eine .osz (ZIP) ist.
	var dest: String = _downloads[set_id].dest
	if not _is_zip(dest):
		_advance_or_fail(set_id, "Datei ist keine gueltige .osz.")
		return
	_finish_download(set_id)
	download_done.emit(set_id, dest)


func _is_zip(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 4:
		return false
	var sig := f.get_buffer(2)
	f.close()
	return sig.size() == 2 and sig[0] == 0x50 and sig[1] == 0x4B  # "PK"


## Eintrag + HTTPRequest-Node eines Downloads aufraeumen.
func _finish_download(set_id: int) -> void:
	if not _downloads.has(set_id):
		return
	var req: HTTPRequest = _downloads[set_id].req
	_downloads.erase(set_id)
	if is_instance_valid(req):
		req.queue_free()




# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

func _https(url: String) -> String:
	if url.begins_with("//"):
		return "https:" + url
	return url


func url_escape(s: String) -> String:
	return s.uri_encode()
