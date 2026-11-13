class_name BeatmapMirror
extends Node

## Direkter Beatmap-Download vom Mirror catboy.best (kein Login noetig).
## Laeuft als Autoload "Mirror": Downloads laufen PARALLEL und ueberleben
## jeden Szenenwechsel (Browser schliessen, Map spielen, Menue — egal).
##  - search(query, offset, sort, status): liefert Beatmapsets (4K-Mania).
##  - fetch_cover(set_id, url): laedt das Cover asynchron als Texture.
##  - download(set_id, dest_dir) / cancel_download(set_id): .osz laden.
## Alle Ergebnisse kommen ueber Signale zurueck.
##
## API-Befund (2026-11-07, per Testanfragen): catboy.best /api/v2/search
## ignoriert genre, genre_id, g und sort komplett und antwortet ohne
## User-Agent mit 403. osu.direct /api/v2/search versteht dieselben
## Parameter plus sort=<feld>:asc|desc (Meilisearch), filtert Genres aber
## ebenfalls nicht. Daher: Sortierung serverseitig ueber osu.direct (Fallback
## catboy + clientseitig sortieren), Genre immer clientseitig ueber genre_id.

const SEARCH_URL := "https://catboy.best/api/v2/search"
const SORTED_SEARCH_URL := "https://osu.direct/api/v2/search"
const PAGE_SIZE := 50
## Download-Mirrors in Reihenfolge — schlaegt einer fehl (oder liefert Muell),
## springt der Download automatisch zum naechsten.
const DOWNLOAD_URLS := [
	"https://catboy.best/d/",
	"https://osu.direct/api/d/",
	"https://api.nerinyan.moe/d/",
]

## osu!-Genres: [genre_id, deutscher Name]. Reihenfolge = Chip-Reihenfolge.
const GENRES := [
	[2, "Videospiel"], [3, "Anime"], [4, "Rock"], [5, "Pop"], [9, "Hip-Hop"],
	[10, "Elektronisch"], [11, "Metal"], [12, "Klassik"], [13, "Folk"],
	[14, "Jazz"], [7, "Novelty"], [6, "Sonstiges"], [1, "Ohne Genre"],
]
## Englische osu!-Namen (Antwortfeld genre.name) -> genre_id.
const GENRE_OSU_NAMES := {
	"unspecified": 1, "video game": 2, "anime": 3, "rock": 4, "pop": 5,
	"other": 6, "novelty": 7, "hip hop": 9, "electronic": 10, "metal": 11,
	"classical": 12, "folk": 13, "jazz": 14,
}

## Sortierungen des Online-Browsers.
enum Sort { RELEVANCE, NEWEST, PLAYS, STARS, BPM }
const SORT_LABELS := ["Relevanz", "Neueste", "Beliebteste", "Sterne", "BPM"]
## Serverseitige Sortierung (osu.direct); "" = catboy-Standardreihenfolge
## (Relevanz bzw. bei leerer Suche neueste zuerst).
const SORT_SERVER := ["", "ranked_date:desc", "play_count:desc",
	"beatmaps.difficulty_rating:asc", "bpm:desc"]

## Suchmodus (osu!-Modus-Code): Mania 4K (Standard) oder osu!standard fuer Orbit.
const MODE_MANIA := 3
const MODE_STD := 0

## Status-Filter: osu!-Statuscodes der Suche.
const STATUS_RANKED := 1
const STATUS_LOVED := 4

signal search_done(results: Array, raw_count: int, offset: int)
signal search_failed(message: String)
signal cover_ready(set_id: int, texture: Texture2D)
signal download_progress(set_id: int, ratio: float)
signal download_done(set_id: int, osz_path: String)
signal download_failed(set_id: int, message: String)
signal download_cancelled(set_id: int)
## SV-Pruefung einer Diff fertig (check_sv). is_sv false auch bei Fehlern.
signal sv_checked(beatmap_id: int, is_sv: bool)

## Einzelne .osu per beatmap_id (per Testanfrage ermittelt; Mirror verlangt
## einen User-Agent, sonst 403).
const OSU_URL := "https://catboy.best/osu/"
const SV_CACHE_PATH := "user://sv_online_cache.cfg"
const SV_MAX_PARALLEL := 4
const COVER_MAX_PARALLEL := 6
const COVER_CACHE_MAX := 240

var _search_req: HTTPRequest
var _search_offset := 0
var _search_query := ""
var _search_sort := 0
var _search_status := STATUS_RANKED
var _search_mode := MODE_MANIA
## Lief die letzte Antwort ueber den sortierenden Mirror (osu.direct)?
var last_server_sorted := false
## Sortierender Mirror ausgefallen -> fuer diese Sitzung nur noch catboy.
var _sorted_down := false
var _search_on_sorted := false
## Diese Suche laeuft nach einem catboy-Fehler ueber osu.direct.
var _search_on_backup := false
## Test-Hook: ersetzt beide Such-URLs (Fehlerzustand im Screenshot-Harness).
var search_url_override := ""
## SV-Filter: hängt "sv" an die Suche an und markiert Treffer (Feld "sv").
var sv_mode := false
## Aktive Downloads: set_id -> {req, dest, idx, last}.
var _downloads: Dictionary = {}
## SV-Pruefung: Cache (Abschnitt v<SV_VERSION>, Schluessel beatmap_id -> bool),
## Warteschlange, laufende Anfragen (id -> HTTPRequest), Fehlschlaege.
var _sv_cache: ConfigFile = null
var _sv_queue: Array[int] = []
var _sv_active: Dictionary = {}
var _sv_failed: Dictionary = {}
var _sv_dirty := 0
## Cover: Warteschlange [set_id, url], laufende Anfragen, Textur-Cache
## (set_id -> Texture2D, aelteste fliegen ab COVER_CACHE_MAX raus) und
## laufende Dekodier-Jobs im WorkerThreadPool.
var _cover_queue: Array = []
var _cover_active: Dictionary = {}
var _cover_cache: Dictionary = {}
var _cover_order: Array[int] = []
var _cover_tasks: Dictionary = {}


func _ready() -> void:
	_search_req = HTTPRequest.new()
	_search_req.timeout = 15.0
	add_child(_search_req)
	_search_req.request_completed.connect(_on_search_completed)


func _exit_tree() -> void:
	for tid in _cover_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(tid)
	_cover_tasks.clear()


## User-Agent fuer alle Anfragen (catboy.best lehnt Anfragen ohne ab).
static func user_agent() -> String:
	return "OMEN/%s (Godot %s; 4K-Mania-Client)" % [
		str(ProjectSettings.get_setting("application/config/version", "1.0")),
		str(Engine.get_version_info().get("string", "4"))]


static func headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: " + user_agent()])


# ---------------------------------------------------------------------------
# Genres + Sortierung (statisch, headless getestet)
# ---------------------------------------------------------------------------

## Deutscher Anzeigename eines osu!-Genres ("" fuer 0 = alle).
static func genre_label(genre_id: int) -> String:
	for g in GENRES:
		if int(g[0]) == genre_id:
			return TranslationServer.translate(str(g[1]))
	return "" if genre_id == 0 else TranslationServer.translate("Sonstiges")


## genre_id aus einem Mirror-Eintrag: Feld genre_id, sonst genre.id bzw.
## genre.name (englischer osu!-Name). 1 = ohne Angabe.
static func genre_id_of(item: Dictionary) -> int:
	if item.get("genre_id", null) != null:
		return int(item.genre_id)
	var g: Variant = item.get("genre", null)
	if g is Dictionary:
		if g.get("id", null) != null:
			return int(g.id)
		return int(GENRE_OSU_NAMES.get(str(g.get("name", "")).to_lower(), 1))
	return 1


## Such-URL. Sortierungen mit Server-Feld gehen an osu.direct, sonst catboy.
## mode: 3 = osu!mania (Standard), 0 = osu!standard (Orbit) · status: 1 ranked / 4 loved · offset: Seiten fuer
## unendliches Scrollen.
static func build_search_url(query: String, offset: int, sort: int = Sort.RELEVANCE,
		status: int = STATUS_RANKED, sorted_mirror: bool = true, base_override: String = "", mode: int = MODE_MANIA) -> String:
	var field := ""
	if sort >= 0 and sort < SORT_SERVER.size():
		field = str(SORT_SERVER[sort])
	var use_sorted := sorted_mirror and field != ""
	var base := SORTED_SEARCH_URL if use_sorted else SEARCH_URL
	if base_override != "":
		base = base_override
	var url := "%s?query=%s&limit=%d&offset=%d&mode=%d&status=%d" % [
		base, query.strip_edges().uri_encode(), PAGE_SIZE, maxi(offset, 0), mode, status]
	if use_sorted:
		url += "&sort=" + field.uri_encode()
	return url


## Ergebnisse clientseitig sortieren (Kopie). Relevanz behaelt die
## Server-Reihenfolge; Neueste/Beliebteste/BPM absteigend, Sterne aufsteigend
## (leichteste 4K-Diff zuerst). Gleichstand: Set-ID absteigend.
static func sort_results(results: Array, sort: int) -> Array:
	var out := results.duplicate()
	match sort:
		Sort.NEWEST:
			out.sort_custom(func(a, b): return _cmp(str(a.get("ranked_date", "")), str(b.get("ranked_date", "")), a, b, false))
		Sort.PLAYS:
			out.sort_custom(func(a, b): return _cmp(int(a.get("plays", 0)), int(b.get("plays", 0)), a, b, false))
		Sort.STARS:
			out.sort_custom(func(a, b): return _cmp(float(a.get("stars_lo", a.get("stars", 0.0))), float(b.get("stars_lo", b.get("stars", 0.0))), a, b, true))
		Sort.BPM:
			out.sort_custom(func(a, b): return _cmp(float(a.get("bpm", 0.0)), float(b.get("bpm", 0.0)), a, b, false))
	return out


static func _cmp(va: Variant, vb: Variant, a: Dictionary, b: Dictionary, asc: bool) -> bool:
	if va == vb:
		return int(a.get("id", 0)) > int(b.get("id", 0))
	return (va < vb) if asc else (va > vb)


## Filter-Kombination ohne Besitz/SV: irgendeine 4K-Diff im Sternbereich
## [lo, hi) UND Genre passt (0 = alle Genres).
static func passes_filters(r: Dictionary, lo: float, hi: float, genre_id: int = 0) -> bool:
	if genre_id != 0 and int(r.get("genre_id", 1)) != genre_id:
		return false
	var star_list: Array = r.get("star_list", [])
	if star_list.is_empty():
		star_list = [float(r.get("stars", 0.0))]
	for sv in star_list:
		if float(sv) >= lo and float(sv) < hi:
			return true
	return false


# ---------------------------------------------------------------------------
# Suche
# ---------------------------------------------------------------------------

func search(query: String, offset: int = 0, sort: int = Sort.RELEVANCE,
		status: int = STATUS_RANKED, mode: int = MODE_MANIA) -> void:
	var q := query.strip_edges()
	_search_mode = mode
	# SV gibt es nur in Mania.
	if sv_mode and mode == MODE_MANIA and not is_sv_text(q):
		q = (q + " sv").strip_edges()
	_search_query = q
	_search_offset = offset
	_search_sort = clampi(sort, 0, SORT_SERVER.size() - 1)
	_search_status = status
	_search_on_sorted = not _sorted_down and str(SORT_SERVER[_search_sort]) != ""
	_search_on_backup = false
	_send_search()


## Laufende Suche verwerfen (Browser geschlossen, neue Filter).
func cancel_search() -> void:
	_search_req.cancel_request()


func _send_search() -> void:
	var base := search_url_override
	if base == "" and _search_on_backup:
		base = SORTED_SEARCH_URL
	var url := build_search_url(_search_query, _search_offset, _search_sort,
		_search_status, _search_on_sorted, base, _search_mode)
	_search_req.cancel_request()
	var err := _search_req.request(url, headers())
	if err != OK:
		search_failed.emit("Suche konnte nicht starten (Fehler %d)." % err)


func _on_search_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array):
		# Sortierender Mirror kaputt -> still auf catboy zurueckfallen.
		if _search_on_sorted and search_url_override == "":
			_sorted_down = true
			_search_on_sorted = false
			_send_search()
			return
		# catboy lehnt ab (z. B. HTTP 403 nach vielen Downloads) -> einmal ueber
		# osu.direct (gleiche Parameter, ohne Server-Sortierung) versuchen.
		if not _search_on_sorted and not _search_on_backup and search_url_override == "":
			_search_on_backup = true
			_send_search()
			return
		if result != HTTPRequest.RESULT_SUCCESS:
			search_failed.emit("Keine Verbindung zum Mirror.")
		elif code != 200:
			search_failed.emit("Der Mirror antwortet nicht (HTTP %d)." % code)
		else:
			search_failed.emit("Unerwartete Antwort vom Mirror.")
		return
	last_server_sorted = _search_on_sorted
	var results: Array = []
	for item in data:
		if item is Dictionary:
			var r := parse_item(item, _search_mode)
			if not r.is_empty():
				results.append(r)
	search_done.emit(results, data.size(), _search_offset)


static func _num(v: Variant, fallback: float = 0.0) -> float:
	return fallback if v == null else float(v)


## Mirror-Eintrag -> schlanker Ergebnis-Datensatz; leer, wenn das Set keine
## Diff des Modus hat (Mania: 4K, sonst osu!standard) oder weder
## ranked/approved noch loved ist.
static func parse_item(item: Dictionary, mode: int = MODE_MANIA) -> Dictionary:
	var status := str(item.get("status", ""))
	if not (status in ["ranked", "approved", "loved"]):
		return {}
	var std := mania4k_difficulty(item) if mode == MODE_MANIA else std_difficulty(item)
	if std.is_empty():
		return {}
	var covers: Variant = item.get("covers", {})
	if not (covers is Dictionary):
		covers = {}
	var cover := str(covers.get("card@2x", covers.get("card", covers.get("cover", ""))))
	var star_list: Array = std.get("star_list", [])
	star_list.sort()
	var date: Variant = item.get("ranked_date", "")
	return {
		"id": int(item.get("id", 0)),
		"title": str(item.get("title", "?")),
		"artist": str(item.get("artist", "?")),
		"creator": str(item.get("creator", "?")),
		"stars": float(std.get("difficulty_rating", 0.0)),
		"stars_lo": float(star_list[0]),
		"star_list": star_list,
		"diffs": int(std.get("count", 1)),
		"cover_url": _https(cover),
		"preview_url": _https(str(item.get("preview_url", ""))),
		"status": status,
		"genre_id": genre_id_of(item),
		"bpm": _num(item.get("bpm", null), _num(std.get("bpm", null))),
		"length_s": int(std.get("max_len", 0)),
		"plays": int(_num(item.get("play_count", null))),
		"ranked_date": "" if date == null else str(date),
		"sv": mode == MODE_MANIA and is_sv_item(item),
		"sv_id": sv_check_id(item) if mode == MODE_MANIA else 0,
		"mode": mode,
		"objects": int(std.get("objects", 0)),
	}


## Text nennt SV: Wort "sv" oder "slider velocity"/"scroll velocity".
static func is_sv_text(text: String) -> bool:
	var t := text.to_lower()
	if t.contains("slider velocity") or t.contains("scroll velocity") \
			or t.contains("sv gimmick"):
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
## Bei Mania ist cs = Spaltenzahl -> nur cs == 4 zaehlt. Liefert dazu
## count, star_list (alle 4K-Sterne) und max_len (laengste 4K-Diff, s).
static func mania4k_difficulty(item: Dictionary) -> Dictionary:
	var best := {}
	var count := 0
	var max_len := 0
	var star_list: Array = []
	for bm in item.get("beatmaps", []):
		if not (bm is Dictionary):
			continue
		if int(bm.get("mode_int", -1)) != 3:
			continue
		if int(round(_num(bm.get("cs", 0.0)))) != 4:
			continue
		count += 1
		star_list.append(_num(bm.get("difficulty_rating", 0.0)))
		max_len = maxi(max_len, int(_num(bm.get("total_length", 0))))
		if best.is_empty() or _num(bm.get("difficulty_rating", 0.0)) > _num(best.get("difficulty_rating", 0.0)):
			best = bm
	if best.is_empty():
		return {}
	best = best.duplicate()
	best["count"] = count
	best["star_list"] = star_list
	best["max_len"] = max_len
	return best


## Schwerste osu!standard-Difficulty eines Sets (Orbit) oder leer. Liefert
## wie mania4k_difficulty count, star_list, max_len und dazu objects (Kreise +
## Slider + Spinner der objektreichsten Diff).
static func std_difficulty(item: Dictionary) -> Dictionary:
	var best := {}
	var count := 0
	var max_len := 0
	var max_obj := 0
	var star_list: Array = []
	for bm in item.get("beatmaps", []):
		if not (bm is Dictionary) or int(bm.get("mode_int", -1)) != MODE_STD:
			continue
		count += 1
		var rating := _num(bm.get("difficulty_rating", 0.0))
		star_list.append(rating)
		max_len = maxi(max_len, int(_num(bm.get("total_length", 0))))
		max_obj = maxi(max_obj, int(_num(bm.get("count_circles", 0)))
			+ int(_num(bm.get("count_sliders", 0))) + int(_num(bm.get("count_spinners", 0))))
		if best.is_empty() or rating > _num(best.get("difficulty_rating", 0.0)):
			best = bm
	if best.is_empty():
		return {}
	best = best.duplicate()
	best["count"] = count
	best["star_list"] = star_list
	best["max_len"] = max_len
	best["objects"] = max_obj
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
		if req.request(OSU_URL + str(id), headers()) != OK:
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
# Cover: max. COVER_MAX_PARALLEL Anfragen, Dekodieren + Mipmaps im
# WorkerThreadPool (kein Ruckler im Hauptthread), Textur-Cache im Speicher.
# ---------------------------------------------------------------------------

func fetch_cover(set_id: int, url: String) -> void:
	if url == "":
		return
	if _cover_cache.has(set_id):
		cover_ready.emit.call_deferred(set_id, _cover_cache[set_id])
		return
	if _cover_active.has(set_id) or _cover_tasks.values().has(set_id):
		return
	for q in _cover_queue:
		if int(q[0]) == set_id:
			return
	_cover_queue.append([set_id, url])
	_pump_covers()


## Cover aus dem Speicher-Cache (null, wenn noch nicht geladen).
func cached_cover(set_id: int) -> Texture2D:
	return _cover_cache.get(set_id, null)


## Wartende Cover verwerfen (neue Suche); laufende enden normal.
func cancel_covers() -> void:
	_cover_queue.clear()


func _pump_covers() -> void:
	while _cover_active.size() < COVER_MAX_PARALLEL and not _cover_queue.is_empty():
		var job: Array = _cover_queue.pop_front()
		var set_id: int = job[0]
		var req := HTTPRequest.new()
		req.timeout = 12.0
		add_child(req)
		_cover_active[set_id] = req
		req.request_completed.connect(_on_cover_completed.bind(set_id))
		if req.request(_https(str(job[1])), headers()) != OK:
			_end_cover_request(set_id)


func _on_cover_completed(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, set_id: int) -> void:
	_end_cover_request(set_id)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var tid := WorkerThreadPool.add_task(_decode_cover.bind(set_id, body), false, "Cover")
	_cover_tasks[tid] = set_id


func _end_cover_request(set_id: int) -> void:
	var req: HTTPRequest = _cover_active.get(set_id)
	_cover_active.erase(set_id)
	if is_instance_valid(req):
		req.queue_free()
	_pump_covers.call_deferred()


## Laeuft im WorkerThreadPool: JPG/PNG dekodieren + Mipmaps (scharfes
## Verkleinern ohne Flimmern). Textur entsteht danach im Hauptthread.
func _decode_cover(set_id: int, body: PackedByteArray) -> void:
	var img := Image.new()
	var ok := false
	# Format an den Magic-Bytes erkennen (kein Fehler-Spam durch Raten).
	if body.size() > 12:
		if body[0] == 0xFF and body[1] == 0xD8:
			ok = img.load_jpg_from_buffer(body) == OK
		elif body[0] == 0x89 and body[1] == 0x50:
			ok = img.load_png_from_buffer(body) == OK
		elif body[0] == 0x52 and body[1] == 0x49 and body[8] == 0x57 and body[9] == 0x45:
			ok = img.load_webp_from_buffer(body) == OK
	if ok:
		img.generate_mipmaps()
	_cover_decoded.call_deferred(set_id, img if ok else null)


func _cover_decoded(set_id: int, img: Image) -> void:
	for tid in _cover_tasks.keys():
		if WorkerThreadPool.is_task_completed(tid):
			WorkerThreadPool.wait_for_task_completion(tid)
			_cover_tasks.erase(tid)
	if img == null:
		return
	var tex := ImageTexture.create_from_image(img)
	_cover_cache[set_id] = tex
	_cover_order.append(set_id)
	while _cover_order.size() > COVER_CACHE_MAX:
		_cover_cache.erase(_cover_order.pop_front())
	cover_ready.emit(set_id, tex)


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

func download(set_id: int, dest_dir: String) -> void:
	if _downloads.has(set_id):
		return  # laeuft schon (Doppelklick) — einfach weiterlaufen lassen
	if DirAccess.make_dir_recursive_absolute(dest_dir) != OK \
			and not DirAccess.dir_exists_absolute(dest_dir):
		download_failed.emit(set_id, "Maps-Ordner nicht beschreibbar: " + dest_dir)
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
		# Erst in eine Teildatei laden; die .osz entsteht nur komplett und
		# geprueft (ein abgebrochener Lauf hinterlaesst keine kaputte Map).
		"part": dest_dir.path_join("mirror_%d.osz.part" % set_id),
		"idx": 0,
		"last": -1.0,
	}
	_start_download_attempt(set_id)


## Laufenden Download abbrechen: Anfrage stoppen, Teildatei loeschen.
func cancel_download(set_id: int) -> void:
	if not _downloads.has(set_id):
		return
	var d: Dictionary = _downloads[set_id]
	var req: HTTPRequest = d.req
	if is_instance_valid(req):
		req.cancel_request()
	_finish_download(set_id)
	_remove_file(d.part)
	download_cancelled.emit(set_id)


## Laeuft fuer dieses Set gerade ein Download?
func is_downloading(set_id: int) -> bool:
	return _downloads.has(set_id)


## Anzahl laufender Downloads.
func downloads_running() -> int:
	return _downloads.size()


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
	_remove_file(d.part)
	req.download_file = d.part
	var err := req.request(DOWNLOAD_URLS[d.idx] + str(set_id), headers())
	if err != OK:
		_advance_or_fail(set_id, "Download konnte nicht starten (Fehler %d)." % err)


## Naechsten Mirror probieren; erst wenn alle durch sind, endgueltig aufgeben.
func _advance_or_fail(set_id: int, msg: String) -> void:
	var d: Dictionary = _downloads[set_id]
	_remove_file(d.part)
	d.idx += 1
	d.last = -1.0
	if d.idx < DOWNLOAD_URLS.size():
		_start_download_attempt(set_id)
		return
	_finish_download(set_id)
	download_failed.emit(set_id, msg)


func _process(_delta: float) -> void:
	# Fortschritt nur bei echter Aenderung melden (>= 0,5 %), nicht pro Frame.
	for set_id in _downloads:
		var d: Dictionary = _downloads[set_id]
		var r := active_ratio(set_id)
		if r > 0.0 and r - float(d.last) >= 0.005:
			d.last = r
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
				why = "Zeitüberschreitung"
		_advance_or_fail(set_id, "Download fehlgeschlagen (%s)." % why)
		return
	# Verifizieren: vollstaendig geladen und eine lesbare .osz mit .osu-Datei.
	var d: Dictionary = _downloads[set_id]
	var req: HTTPRequest = d.req
	var total := req.get_body_size()
	if total > 0 and req.get_downloaded_bytes() < total:
		_advance_or_fail(set_id, "Download unvollständig.")
		return
	if not is_valid_osz(d.part):
		_advance_or_fail(set_id, "Datei ist keine gültige .osz.")
		return
	_remove_file(d.dest)
	if DirAccess.rename_absolute(d.part, d.dest) != OK:
		_advance_or_fail(set_id, "Zielordner nicht beschreibbar")
		return
	_finish_download(set_id)
	download_done.emit(set_id, d.dest)


## Vollstaendige .osz? ZIP-Signatur, lesbares Inhaltsverzeichnis (fehlt bei
## abgeschnittenen Dateien) und mindestens eine .osu-Datei.
static func is_valid_osz(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 22:
		return false
	var sig := f.get_buffer(2)
	if sig.size() != 2 or sig[0] != 0x50 or sig[1] != 0x4B:  # "PK"
		f.close()
		return false
	# Ende-Eintrag (EOCD "PK") in den letzten 64 KB suchen: fehlt er,
	# ist die Datei abgeschnitten — ohne ZIPReader-Fehlermeldung abweisen.
	var n := mini(f.get_length(), 65557)
	f.seek(f.get_length() - n)
	var tail := f.get_buffer(n)
	f.close()
	var eocd := false
	for i in range(tail.size() - 22, -1, -1):
		if tail[i] == 0x50 and tail[i + 1] == 0x4B and tail[i + 2] == 0x05 and tail[i + 3] == 0x06:
			eocd = true
			break
	if not eocd:
		return false
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return false
	var has_osu := false
	for fname in zr.get_files():
		if fname.to_lower().ends_with(".osu"):
			has_osu = true
			break
	zr.close()
	return has_osu


static func _remove_file(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


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

static func _https(url: String) -> String:
	if url.begins_with("//"):
		return "https:" + url
	return url


func url_escape(s: String) -> String:
	return s.uri_encode()
