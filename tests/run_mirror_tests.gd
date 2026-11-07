extends SceneTree

## Headless-Tests fuer den Online-Browser (Mirror): Genre-Mapping,
## Filter-Kombination, Sortierung, URL-Bau, Antwort-Parsing. Offline.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mirror_tests.gd

var _passed := 0
var _failed := 0
var _sections := 0


func _initialize() -> void:
	print("=== TETHRA Mirror-Tests ===")
	_test_genres()
	_test_url()
	_test_parse()
	_test_filters()
	_test_sort()
	_test_format()
	# Bricht ein Abschnitt per Script-Fehler ab, fehlt sein Abschluss.
	_ok(_sections == 6, "alle 6 Abschnitte vollstaendig gelaufen (%d)" % _sections)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _test_genres() -> void:
	print("-- Genres")
	_ok(BeatmapMirror.genre_label(2) == "Videospiel", "2 = Videospiel")
	_ok(BeatmapMirror.genre_label(9) == "Hip-Hop", "9 = Hip-Hop")
	_ok(BeatmapMirror.genre_label(10) == "Elektronisch", "10 = Elektronisch")
	_ok(BeatmapMirror.genre_label(12) == "Klassik", "12 = Klassik")
	_ok(BeatmapMirror.genre_label(6) == "Sonstiges", "6 = Sonstiges")
	_ok(BeatmapMirror.genre_label(0) == "", "0 = alle (leer)")
	_ok(BeatmapMirror.genre_label(99) == "Sonstiges", "unbekannt = Sonstiges")
	_ok(BeatmapMirror.GENRES.size() == 13, "13 osu!-Genres als Chips")
	var ids := {}
	for g in BeatmapMirror.GENRES:
		ids[int(g[0])] = true
	_ok(ids.size() == 13 and not ids.has(8) and not ids.has(0), "Genre-IDs eindeutig, ohne 0/8")
	_ok(BeatmapMirror.genre_id_of({"genre_id": 3}) == 3, "genre_id-Feld")
	_ok(BeatmapMirror.genre_id_of({"genre": {"id": 4, "name": "Rock"}}) == 4, "genre.id")
	_ok(BeatmapMirror.genre_id_of({"genre": {"name": "Hip Hop"}}) == 9, "genre.name Hip Hop")
	_ok(BeatmapMirror.genre_id_of({"genre": {"name": "Video Game"}}) == 2, "genre.name Video Game")
	_ok(BeatmapMirror.genre_id_of({"genre_id": null}) == 1, "null = ohne Angabe")
	_ok(BeatmapMirror.genre_id_of({}) == 1, "fehlt = ohne Angabe")
	_sections += 1



func _test_url() -> void:
	print("-- URL-Bau")
	var u := BeatmapMirror.build_search_url("", 0)
	_ok(u.begins_with(BeatmapMirror.SEARCH_URL + "?"), "Relevanz -> catboy")
	_ok(u.contains("mode=3") and u.contains("status=1") and u.contains("offset=0") \
		and u.contains("limit=50"), "mode/status/offset/limit")
	_ok(not u.contains("sort="), "Relevanz ohne sort")
	u = BeatmapMirror.build_search_url("camellia", 100, BeatmapMirror.Sort.PLAYS)
	_ok(u.begins_with(BeatmapMirror.SORTED_SEARCH_URL + "?"), "Beliebteste -> osu.direct")
	_ok(u.contains("sort=play_count%3Adesc"), "sort=play_count:desc (escaped)")
	_ok(u.contains("query=camellia") and u.contains("offset=100"), "Query + Offset")
	u = BeatmapMirror.build_search_url("x", 0, BeatmapMirror.Sort.BPM)
	_ok(u.contains("sort=bpm%3Adesc"), "BPM absteigend")
	u = BeatmapMirror.build_search_url("x", 0, BeatmapMirror.Sort.NEWEST)
	_ok(u.contains("sort=ranked_date%3Adesc"), "Neueste")
	u = BeatmapMirror.build_search_url("x", 0, BeatmapMirror.Sort.STARS)
	_ok(u.contains("sort=beatmaps.difficulty_rating%3Aasc"), "Sterne aufsteigend")
	u = BeatmapMirror.build_search_url("x", 0, BeatmapMirror.Sort.PLAYS, BeatmapMirror.STATUS_RANKED, false)
	_ok(u.begins_with(BeatmapMirror.SEARCH_URL) and not u.contains("sort="), "Fallback ohne sortierenden Mirror")
	u = BeatmapMirror.build_search_url("x", 0, 0, BeatmapMirror.STATUS_LOVED)
	_ok(u.contains("status=4"), "Loved = status 4")
	u = BeatmapMirror.build_search_url("  Mädchen & Rock  ", -5)
	_ok(u.contains("query=M%C3%A4dchen%20%26%20Rock&"), "Umlaut/Leerzeichen/& escaped, getrimmt")
	_ok(u.contains("offset=0"), "negativer Offset -> 0")
	u = BeatmapMirror.build_search_url("x", 0, BeatmapMirror.Sort.PLAYS, 1, true, "https://t.invalid/s")
	_ok(u.begins_with("https://t.invalid/s?"), "Override-URL")
	_ok(BeatmapMirror.user_agent().begins_with("TETHRA/"), "User-Agent gesetzt")
	_ok(BeatmapMirror.headers()[0].begins_with("User-Agent: TETHRA/"), "User-Agent-Header")
	_sections += 1



func _bm(id: int, mode: int, cs: float, sr: float, length: int = 90) -> Dictionary:
	return {"id": id, "mode_int": mode, "cs": cs, "difficulty_rating": sr,
		"total_length": length, "version": "Diff %d" % id}


func _test_parse() -> void:
	print("-- Parsing")
	var item := {
		"id": 77, "title": "Song", "artist": "Band", "creator": "Mapper",
		"status": "ranked", "genre_id": 10, "bpm": 174.5, "play_count": 12345,
		"ranked_date": "2026-11-05T17:23:45Z",
		"covers": {"card": "https://a/card.jpg", "card@2x": "https://a/card@2x.jpg"},
		"preview_url": "//b.ppy.sh/preview/77.mp3",
		"beatmaps": [_bm(1, 3, 4, 3.2, 100), _bm(2, 3, 4, 1.1, 120), _bm(3, 3, 7, 5.0), _bm(4, 0, 4, 6.0)],
	}
	var r := BeatmapMirror.parse_item(item)
	_ok(int(r.id) == 77 and int(r.diffs) == 2, "nur 4K-Mania-Diffs gezaehlt")
	_ok(is_equal_approx(float(r.stars), 3.2) and is_equal_approx(float(r.stars_lo), 1.1), "Sterne max/min")
	_ok(r.star_list == [1.1, 3.2], "Sternliste aufsteigend")
	_ok(int(r.genre_id) == 10 and is_equal_approx(float(r.bpm), 174.5), "Genre + BPM")
	_ok(int(r.length_s) == 120 and int(r.plays) == 12345, "Laenge (laengste 4K) + Plays")
	_ok(str(r.cover_url).ends_with("card@2x.jpg"), "scharfes Cover (card@2x)")
	_ok(str(r.preview_url).begins_with("https://"), "Preview-URL mit https")
	item.status = "loved"
	_ok(str(BeatmapMirror.parse_item(item).status) == "loved", "Loved akzeptiert")
	item.status = "graveyard"
	_ok(BeatmapMirror.parse_item(item).is_empty(), "Graveyard verworfen")
	item.status = "ranked"
	item.beatmaps = [_bm(5, 3, 7, 4.0)]
	_ok(BeatmapMirror.parse_item(item).is_empty(), "ohne 4K verworfen")
	var nulls := {"id": 5, "status": "ranked", "bpm": null, "play_count": null,
		"ranked_date": null, "covers": null, "genre": {"name": "Jazz"},
		"beatmaps": [_bm(9, 3, 4, 2.0)]}
	var n := BeatmapMirror.parse_item(nulls)
	_ok(not n.is_empty() and float(n.bpm) == 0.0 and int(n.plays) == 0 \
		and str(n.ranked_date) == "" and int(n.genre_id) == 14, "null-Felder robust")
	_sections += 1



func _r(id: int, genre: int, stars: Array, plays: int = 0, bpm: float = 120.0,
		date: String = "", artist: String = "A", title: String = "T") -> Dictionary:
	var sl := stars.duplicate()
	sl.sort()
	return {"id": id, "genre_id": genre, "star_list": sl, "stars": sl.back(),
		"stars_lo": sl.front(), "plays": plays, "bpm": bpm, "ranked_date": date,
		"artist": artist, "title": title}


func _test_filters() -> void:
	print("-- Filter-Kombination")
	var rock_easy := _r(1, 4, [1.2, 3.5])
	var anime_hard := _r(2, 3, [5.5])
	_ok(BeatmapMirror.passes_filters(rock_easy, 0.0, 999.0, 0), "alles erlaubt")
	_ok(BeatmapMirror.passes_filters(rock_easy, 0.0, 1.5, 4), "Rock + Anfaenger")
	_ok(not BeatmapMirror.passes_filters(rock_easy, 0.0, 1.5, 3), "Genre falsch")
	_ok(not BeatmapMirror.passes_filters(anime_hard, 0.0, 1.5, 3), "Genre richtig, Sterne falsch")
	_ok(BeatmapMirror.passes_filters(anime_hard, 4.0, 6.0, 3), "Anime + 4–6")
	_ok(BeatmapMirror.passes_filters(rock_easy, 3.0, 4.0, 4), "irgendeine Diff im Bereich")
	_ok(not BeatmapMirror.passes_filters(_r(3, 4, [1.5]), 0.0, 1.5, 0), "Obergrenze exklusiv (1,5)")
	_ok(BeatmapMirror.passes_filters(_r(3, 4, [1.5]), 1.5, 2.0, 0), "Untergrenze inklusiv")
	_ok(BeatmapMirror.passes_filters({"id": 4, "stars": 2.5}, 2.0, 3.0, 0), "ohne Sternliste -> stars")
	_ok(not BeatmapMirror.passes_filters({"id": 4, "stars": 2.5}, 2.0, 3.0, 5), "ohne genre_id = 1")
	var owned := {1: true, OnlineBrowser.at_key("Band", "Song (TV Size)"): true}
	_ok(not OnlineBrowser.visible_result(rock_easy, owned, 0.0, 999.0, 0), "installiert per ID ausgeblendet")
	var by_name := _r(9, 4, [2.0], 0, 120.0, "", "Band", "Song (TV-Size)")
	_ok(not OnlineBrowser.visible_result(by_name, owned, 0.0, 999.0, 0), "installiert per Artist|Titel")
	_ok(OnlineBrowser.visible_result(anime_hard, owned, 4.0, 6.0, 3), "Besitz + Genre + Sterne zusammen")
	_ok(not OnlineBrowser.visible_result(anime_hard, owned, 4.0, 6.0, 4), "Besitz ok, Genre nicht")
	_sections += 1



func _ids(arr: Array) -> Array:
	var out: Array = []
	for r in arr:
		out.append(int(r.id))
	return out


func _test_sort() -> void:
	print("-- Sortierung")
	var arr := [
		_r(1, 4, [3.0], 500, 150.0, "2026-01-02T00:00:00Z"),
		_r(2, 4, [1.0, 6.0], 9000, 220.0, "2025-05-05T00:00:00Z"),
		_r(3, 4, [2.0], 70, 90.5, "2026-11-01T00:00:00Z"),
		_r(4, 4, [2.0], 70, 90.5, "2026-11-01T00:00:00Z"),
	]
	_ok(_ids(BeatmapMirror.sort_results(arr, BeatmapMirror.Sort.RELEVANCE)) == [1, 2, 3, 4], "Relevanz = Server-Reihenfolge")
	_ok(_ids(BeatmapMirror.sort_results(arr, BeatmapMirror.Sort.PLAYS)) == [2, 1, 4, 3], "Beliebteste absteigend, Gleichstand ID")
	_ok(_ids(BeatmapMirror.sort_results(arr, BeatmapMirror.Sort.NEWEST)) == [4, 3, 1, 2], "Neueste zuerst")
	_ok(_ids(BeatmapMirror.sort_results(arr, BeatmapMirror.Sort.BPM)) == [2, 1, 4, 3], "BPM absteigend")
	_ok(_ids(BeatmapMirror.sort_results(arr, BeatmapMirror.Sort.STARS)) == [2, 4, 3, 1], "Sterne aufsteigend (leichteste Diff)")
	_ok(_ids(arr) == [1, 2, 3, 4], "Original unveraendert")
	_ok(BeatmapMirror.SORT_LABELS.size() == BeatmapMirror.SORT_SERVER.size(), "Labels = Server-Felder")
	_sections += 1



func _test_format() -> void:
	print("-- Anzeige")
	_ok(OnlineBrowser.fmt_length(88) == "1:28", "Laenge 1:28")
	_ok(OnlineBrowser.fmt_length(3723) == "1:02:03", "Laenge mit Stunden")
	var m := OnlineBrowser.meta_line(_r(1, 10, [2.0], 12345, 174.5))
	_ok(m.begins_with("Elektronisch") and m.contains("174,5 BPM") and m.contains("12.345 Plays"),
		"Meta-Zeile deutsch: " + m)
	_ok(OnlineBrowser.meta_line(_r(1, 2, [2.0], 5, 200.0)).contains("200 BPM"), "ganze BPM ohne Komma")
	_ok(OnlineBrowser.at_key("A B", "C-(d)") == "ab|cd", "Besitz-Schluessel")
	_sections += 1
