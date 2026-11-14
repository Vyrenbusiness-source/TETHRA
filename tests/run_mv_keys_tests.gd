extends SceneTree

## Headless-Tests fuer Mania mit 5K, 6K und 7K (echte Maps, ManiaKeys).
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_mv_keys_tests.gd
## Optional: --maps-dir=<Ordner mit echten 5K-7K-.osz> prueft zusaetzlich echte Maps
## (Import, Spaltenzahl, Autoplay ohne Miss). Ohne den Ordner nur die festen Faelle.

var _failed := 0
var _passed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _initialize() -> void:
	print("=== Mania 5K-7K (mv-keys) ===")
	_test_defaults()
	_test_pattern_colors()
	_test_rails()
	_test_online_modes()
	_test_parser_and_core()
	_test_import_filter()
	_test_map_set_filter()
	_test_mirror()
	_test_settings()
	_test_score_store()
	_test_online_body()
	_test_note_colors()
	_test_skin()
	_test_replay_marker()
	_test_real_maps()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## osu!mania-Text mit n Spalten: je Spalte eine Note (x = Spaltenmitte), dazu ein Hold.
static func _osu(keys: int, mode: int = 3) -> String:
	var ho := ""
	for c in keys:
		var x := int((float(c) + 0.5) * 512.0 / float(keys))
		ho += "%d,192,%d,1,0,0:0:0:0:\n" % [x, 1000 + c * 200]
	ho += "%d,192,3000,128,0,3600:0:0:0:0:\n" % int(512.0 / float(keys) * 0.5)
	return ("osu file format v14\n\n[General]\nMode: %d\n\n[Metadata]\nTitle:T\nArtist:A\nVersion:%dK Test\n\n"
		+ "[Difficulty]\nHPDrainRate: 5\nCircleSize: %d\nOverallDifficulty: 5\nApproachRate: 5\n"
		+ "SliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n%s") % [mode, keys, keys, ho]


func _test_defaults() -> void:
	print("- Standard-Tasten wie osu!")
	_check(ManiaKeys.default_keys(4) == [KEY_D, KEY_F, KEY_J, KEY_K] as Array[int], "4K D F J K")
	_check(ManiaKeys.default_keys(5) == [KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K] as Array[int], "5K D F Space J K")
	_check(ManiaKeys.default_keys(6) == [KEY_S, KEY_D, KEY_F, KEY_J, KEY_K, KEY_L] as Array[int], "6K S D F J K L")
	_check(ManiaKeys.default_keys(7) == [KEY_S, KEY_D, KEY_F, KEY_SPACE, KEY_J, KEY_K, KEY_L] as Array[int],
		"7K S D F Space J K L")
	var a := ManiaKeys.default_keys(7)
	a[0] = KEY_A
	_check(ManiaKeys.default_keys(7)[0] == KEY_S, "default_keys liefert eine Kopie")
	_check(ManiaKeys.supported(4) and ManiaKeys.supported(7), "4K und 7K unterstuetzt")
	_check(not ManiaKeys.supported(3) and not ManiaKeys.supported(8), "3K und 8K nicht")


func _test_pattern_colors() -> void:
	print("- Spaltenmuster und Farben wie osu!")
	var want := {4: "1221", 5: "12S21", 6: "121121", 7: "121S121"}
	for k in want:
		var s := ""
		for c in int(k):
			s += ManiaKeys.pattern(c, int(k))
		_check(s == want[k], "%dK Muster %s (war %s)" % [k, want[k], s])
	for c in 4:
		_check(ManiaKeys.palette_index(c, 4) == c, "4K Palette unveraendert %d" % c)
	_check(ManiaKeys.palette_index(3, 7) == -1 and ManiaKeys.is_center(3, 7), "7K Mitte = eigene Farbe")
	_check(ManiaKeys.palette_index(2, 5) == -1, "5K Mitte = eigene Farbe")
	_check(not ManiaKeys.is_center(2, 6) and not ManiaKeys.is_center(3, 6), "6K hat keine Mitte")
	_check(ManiaKeys.palette_index(0, 7) == 0 and ManiaKeys.palette_index(6, 7) == 3, "7K aussen = Farben 0/3")
	_check(ManiaKeys.palette_index(1, 7) == 1 and ManiaKeys.palette_index(5, 7) == 2, "7K innen = Farben 1/2")


func _test_rails() -> void:
	print("- 3D-Bahnen")
	var r4 := ManiaKeys.rail_x(4)
	_check(r4.size() == 4 and is_equal_approx(r4[0], -2.55) and is_equal_approx(r4[3], 2.55), "4K = alter Look")
	_check(is_equal_approx(ManiaKeys.field_scale(4), 1.0) and is_equal_approx(ManiaKeys.note_scale(4), 1.0),
		"4K Feld/Noten unveraendert")
	for k in [5, 6, 7]:
		var r := ManiaKeys.rail_x(k)
		_check(r.size() == k and is_equal_approx(r[0], -r[k - 1]), "%dK symmetrisch, %d Bahnen" % [k, k])
		var gap := r[1] - r[0]
		var note_w := 1.0 * ManiaKeys.note_scale(k)  # Notenbreite ~1.0 Welt-Einheiten bei 4K
		_check(gap - note_w > 0.4, "%dK: Spalt zwischen Noten bleibt (%.2f)" % [k, gap - note_w])
		_check(ManiaKeys.field_scale(k) >= 1.0, "%dK Feld nicht schmaler als 4K" % k)


func _test_online_modes() -> void:
	print("- Online-Modus je Tastenzahl")
	_check(ManiaKeys.online_mode(4) == "mania", "4K = mania (alte Ranglisten)")
	_check(ManiaKeys.online_mode(7) == "mania7k", "7K = mania7k")
	_check(ManiaKeys.keys_of_online_mode("mania6k") == 6, "mania6k -> 6")
	_check(ManiaKeys.keys_of_online_mode("mania") == 4, "mania -> 4")
	_check(ManiaKeys.keys_of_online_mode("mania9k") == 0 and ManiaKeys.keys_of_online_mode("orbit") == 0,
		"fremde Modi -> 0")
	_check(ManiaKeys.is_mania_online("mania5k") and not ManiaKeys.is_mania_online("trace"), "is_mania_online")


func _test_parser_and_core() -> void:
	print("- Parser und ManiaCore mit 5K-7K")
	for k in [5, 6, 7]:
		var res := OsuParser.parse(_osu(k))
		_check(bool(res.ok), "%dK parst" % k)
		if not res.ok:
			continue
		var bm: Beatmap = res.beatmap
		_check(bm.column_count() == k, "%dK column_count" % k)
		var cols := []
		for o in bm.hit_objects:
			cols.append((o as ManiaNote).column)
		var ok := true
		for c in k:
			ok = ok and cols[c] == c
		_check(ok, "%dK Spalten aus x: %s" % [k, str(cols)])
		var core := ManiaCore.new()
		core.setup(bm)
		_check(core.columns == k, "%dK ManiaCore.columns" % k)
		# Jede Spalte genau zur Notenzeit druecken: alles MAX, kein Miss.
		for c in k:
			var t := 1000.0 + c * 200.0
			core.key_down(c, t)
			core.key_up(c, t + 30.0)
			core.update(t + 40.0)
		core.key_down(0, 3000.0)
		core.update(3300.0)
		core.key_up(0, 3600.0)
		core.update(4500.0)
		var s := core.stats()
		_check(int(s.n_miss) == 0 and int(s.n_max) >= k, "%dK alle Spalten getroffen (max %d, miss %d)"
			% [k, int(s.n_max), int(s.n_miss)])
		core.key_down(k, 5000.0)  # Spalte ausserhalb: still ignoriert
		_check(int(core.stats().n_miss) == 0, "%dK Taste ausserhalb ignoriert" % k)


func _test_import_filter() -> void:
	print("- Import-Filter")
	for k in [4, 5, 6, 7]:
		_check(SongImport.header_usable({"mode": 3, "keys": k}), "%dK wird importiert" % k)
	_check(not SongImport.header_usable({"mode": 3, "keys": 8}), "8K nicht")
	_check(not SongImport.header_usable({"mode": 3, "keys": 1}), "1K nicht")
	_check(SongImport.header_usable({"mode": 0, "keys": 5}), "osu!standard unveraendert")
	_check(int(SongImport.osu_header(_osu(7)).get("keys", 0)) == 7, "osu_header liest 7K")
	_check(MapLibrary.osu_key_count(_osu(6)) == 6, "osu_key_count 6K")
	_check(MapLibrary.osu_key_count(_osu(5, 0)) == 0, "osu_key_count Standard = 0")


func _test_map_set_filter() -> void:
	print("- Browser-Filter (MapSet.mode_shows)")
	var m4 := {"mode": 3, "cs": 4.0}
	var m7 := {"mode": 3, "cs": 7.0}
	var m8 := {"mode": 3, "cs": 8.0}
	var std := {"mode": 0, "cs": 4.0}
	_check(MapSet.mode_shows(m4, "mania") and MapSet.mode_shows(m7, "mania"), "Mania zeigt 4K und 7K")
	_check(not MapSet.mode_shows(m8, "mania"), "Mania zeigt kein 8K")
	_check(MapSet.mode_shows(m7, "mania@7") and not MapSet.mode_shows(m4, "mania@7"), "Filter 7K")
	_check(MapSet.mode_shows(m4, "mania@4") and not MapSet.mode_shows(m7, "mania@4"), "Filter 4K (Trace/Rebound/MP)")
	_check(MapSet.mode_shows(m4, "orbit") and not MapSet.mode_shows(m7, "orbit"), "Orbit/Rally/Dirigent: nur 4K")
	_check(MapSet.mode_shows(std, "orbit") and not MapSet.mode_shows(std, "mania"), "Standard nur Orbit")
	var ms := MapSet.from_dict("x.osz", {"title": "t", "diffs": [
		{"mode": 3, "cs": 7.0, "osu_filename": "a.osu"}, {"mode": 3, "cs": 4.0, "osu_filename": "b.osu"},
		{"mode": 3, "cs": 7.0, "osu_filename": "c.osu"}]})
	_check(ms.key_counts() == [4, 7] as Array[int], "key_counts 4K 7K")
	_check(_ss().view_mode_of("mania") == "mania" and _ss().view_mode_of("trace") == "mania@4"
		and _ss().view_mode_of("orbit") == "orbit", "Sicht-Modus je Spielmodus")
	_check(_ss().online_mode_of({"mode": 3, "cs": 7.0}, "") == "mania7k", "Rangliste 7K = mania7k")
	_check(_ss().online_mode_of({"mode": 3, "cs": 4.0}, "") == "mania", "Rangliste 4K = mania")


func _test_mirror() -> void:
	print("- Online-Browser (Mirror)")
	var item := {"id": 1, "status": "ranked", "title": "t", "artist": "a", "beatmaps": [
		{"mode_int": 3, "cs": 4.0, "difficulty_rating": 2.0, "total_length": 90, "id": 11},
		{"mode_int": 3, "cs": 7.0, "difficulty_rating": 3.5, "total_length": 100, "id": 12},
		{"mode_int": 3, "cs": 7.0, "difficulty_rating": 4.5, "total_length": 100, "id": 13},
		{"mode_int": 3, "cs": 9.0, "difficulty_rating": 5.0, "total_length": 100, "id": 14},
		{"mode_int": 0, "cs": 4.0, "difficulty_rating": 5.0, "total_length": 100, "id": 15}]}
	var d4 := BeatmapMirror.mania_difficulty(item, 4)
	_check(int(d4.count) == 1 and d4["keys"] == [4], "4K: eine Diff")
	var d7 := BeatmapMirror.mania_difficulty(item, 7)
	_check(int(d7.count) == 2 and d7["keys"] == [7], "7K: zwei Diffs")
	var da := BeatmapMirror.mania_difficulty(item, 0)
	_check(int(da.count) == 3 and da["keys"] == [4, 7], "alle: 4K+7K, kein 9K")
	_check(BeatmapMirror.mania4k_difficulty(item).hash() == d4.hash(), "mania4k_difficulty unveraendert")
	_check(BeatmapMirror.parse_item(item, BeatmapMirror.MODE_MANIA, 6).is_empty(), "6K-Suche: Set ohne 6K faellt raus")
	_check(OnlineBrowser.keys_text({"keys": [4, 7]}) == "4K 7K" and OnlineBrowser.keys_text({"keys": [4]}) == "",
		"Karten-Marke")


func _test_settings() -> void:
	print("- Tastenbelegung je Tastenzahl")
	var st: Node = load("res://scripts/settings.gd").new()
	_check(st.mania_keys(4) == st.key_lanes, "4K = key_lanes")
	_check(st.mania_keys(7) == ManiaKeys.default_keys(7), "7K Standard")
	_check(st.mania_lane_for_key(KEY_SPACE, 7) == 3 and st.mania_lane_for_key(KEY_SPACE, 4) == -1,
		"Space = 7K-Mitte, in 4K keine Spalte")
	_check(st.mania_lane_for_key(KEY_L, 6) == 5 and st.mania_lane_for_key(KEY_L, 5) == -1, "L: 6K ja, 5K nein")
	var path := "user://mv_keys_test_settings.cfg"
	st.key_lanes_k[7][0] = KEY_A
	st.save(path)
	var st2: Node = load("res://scripts/settings.gd").new()
	st2.load_settings(path)
	_check(st2.mania_keys(7)[0] == KEY_A and st2.mania_keys(7)[1] == KEY_D, "7K-Belegung gespeichert/geladen")
	_check(st2.mania_keys(5) == ManiaKeys.default_keys(5), "5K bleibt Standard")
	_check(st2.key_lanes == [KEY_D, KEY_F, KEY_J, KEY_K] as Array[int], "4K unberuehrt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	st.free()
	st2.free()


func _test_score_store() -> void:
	print("- ScoreStore je Tastenzahl")
	var old := ScoreStore.PATH
	ScoreStore.PATH = "user://mv_keys_test_scores.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ScoreStore.PATH))
	var r4 := {"score": 900000, "grade": "A", "accuracy": 0.95, "max_combo": 100, "pp": 100.0, "mods": []}
	var r7 := r4.duplicate()
	r7["pp"] = 300.0
	r7["keys"] = 7
	ScoreStore.submit("a.osz", "4K Hard", r4)
	ScoreStore.submit("b.osz", "7K Hard", r7)
	_check(is_equal_approx(ScoreStore.profile_pp(), 100.0), "4K-Profil-pp ohne 7K (%.1f)" % ScoreStore.profile_pp())
	_check(is_equal_approx(ScoreStore.profile_pp(7), 300.0), "7K-pp eigene Wertung")
	var cfg := ConfigFile.new()
	cfg.load(ScoreStore.PATH)
	var e7: Dictionary = cfg.get_value("scores", ScoreStore._key("b.osz", "7K Hard"), {})
	var e4: Dictionary = cfg.get_value("scores", ScoreStore._key("a.osz", "4K Hard"), {})
	_check(int(e7.get("keys", 0)) == 7, "Eintrag hat keys = 7")
	_check(not e4.has("keys"), "4K-Eintrag unveraendert (ohne keys)")
	_check(ScoreStore.mode_label("", 7) == "Mania 7K" and ScoreStore.mode_label("") == "Mania 4K", "mode_label")
	_check(ScoreStore.mode_label(ScoreStore.MODE_ORBIT, 7) == "Orbit", "Orbit-Label unveraendert")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ScoreStore.PATH))
	ScoreStore.PATH = old


func _test_online_body() -> void:
	print("- Online-Score-Body")
	var r := {"score": 1, "accuracy": 0.9, "grade": "A", "pp": 123.0, "mods": []}
	var b4 := OnlineApi.build_body(r, {"md5": "x"}, "mania")
	_check(str(b4.mode) == "mania" and not b4.has("keys") and float(b4.pp) == 123.0, "4K-Body unveraendert")
	var b7 := OnlineApi.build_body(r, {"md5": "x"}, ManiaKeys.online_mode(7))
	_check(str(b7.mode) == "mania7k" and int(b7.keys) == 7 and float(b7.pp) == 123.0, "7K: mode mania7k, keys, pp")
	_check(not b7.has("stars"), "7K wie Mania ohne stars-Feld")


func _test_note_colors() -> void:
	print("- Notenfarben (Spalten-Modus)")
	var keep := NoteColors.path
	NoteColors.path = "user://mv_keys_test_colors.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NoteColors.path))
	NoteColors.reload()
	NoteColors.set_mode(false, "lanes")
	for c in 4:
		_check(NoteColors.lane_color(false, c, 4) == NoteColors.lane_color(false, c), "4K Spalte %d unveraendert" % c)
	_check(NoteColors.lane_color(false, 0, 7) == NoteColors.lane_color(false, 0), "7K aussen links = Farbe 1")
	_check(NoteColors.lane_color(false, 6, 7) == NoteColors.lane_color(false, 3), "7K aussen rechts = Farbe 4")
	var mid := NoteColors.lane_color(false, 3, 7)
	_check(mid != NoteColors.lane_color(false, 2, 7) and mid != NoteColors.lane_color(false, 4, 7),
		"7K Mitte hebt sich ab")
	_check(NoteColors.color_for(3, false, false, Color.BLACK, 0, 7) == mid, "color_for nutzt Tastenzahl")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NoteColors.path))
	NoteColors.path = keep
	NoteColors.reload()


func _test_skin() -> void:
	print("- Skins je Spaltenzahl")
	for nm in ManiaSkin.BUILTIN_NAMES:
		var id := ManiaSkin.BUILTIN_PREFIX + str(nm)
		var s4 := ManiaSkin.load_skin(id)
		var s7 := ManiaSkin.load_skin(id, ManiaSkin.SKINS_DIR, 7)
		_check(s4 != null and s7 != null, "%s laedt (4K und 7K)" % nm)
		if s4 == null or s7 == null:
			continue
		_check(s7.keys == 7 and s7.column_width.size() == 7, "%s 7K: 7 Spaltenbreiten" % nm)
		_check(is_equal_approx(float(s7.column_width[0]), float(s4.column_width[0])), "%s 7K: Breite wie 4K" % nm)
	var ini := "[General]\nName: t\n[Mania]\nKeys: 7\nColumnWidth: 30,31,32,33,34,35,36\n[Mania]\nKeys: 4\nColumnWidth: 40,40,40,40\n"
	var p := ManiaSkin.parse(ini, 7)
	_check(p.keys == 7 and int(p.column_width[6]) == 36, "osu!-Skin: eigener [Mania]-Block 7K")


func _test_replay_marker() -> void:
	print("- Replay-Marke")
	var osz := "user://mv_keys_test.osz"
	ReplayStore.save(osz, "7K Test", [{"t": 1000.0, "lane": 6, "down": true}],
		{"score": 1, "keys": 7, "mods": {}})
	var rp := ReplayStore.load_replay(osz, "7K Test")
	_check(int(rp.get("meta", {}).get("keys", 0)) == 7, "Replay traegt keys = 7")
	_check(int(rp.events[0].lane) == 6, "Replay-Ereignis Spalte 6")
	var p := ReplayStore._path(osz, "7K Test")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Echte Maps aus --maps-dir (nie im Repo): jede 5K-7K-Diff importieren, Spaltenzahl
## pruefen und per Autoplay-Schema (Druck zur Notenzeit) ohne Miss durchspielen.
func _test_real_maps() -> void:
	var dir := ""
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--maps-dir="):
			dir = a.trim_prefix("--maps-dir=")
	if dir == "":
		print("- Echte Maps: uebersprungen (kein --maps-dir)")
		return
	print("- Echte Maps aus ", dir)
	var seen := {}
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		_check(bool(imp.ok), "%s importiert" % f)
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if not bm.is_mania() or not ManiaKeys.supported(bm.column_count()) or bm.column_count() == 4:
				continue
			var k := bm.column_count()
			var core := ManiaCore.new()
			core.setup(bm)
			var maxc := 0
			for o in bm.hit_objects:
				maxc = maxi(maxc, (o as ManiaNote).column)
			_check(core.columns == k and maxc == k - 1, "%s [%s]: %dK, alle Spalten belegt"
				% [f, bm.version_name(), k])
			var miss := _autoplay_misses(core, bm)
			_check(miss == 0, "%s [%s]: Autoplay ohne Miss (%d)" % [f, bm.version_name(), miss])
			seen[k] = true
	_check(seen.size() >= 3, "echte 5K, 6K und 7K gefunden (%s)" % str(seen.keys()))


static func _autoplay_misses(core: ManiaCore, bm: Beatmap) -> int:
	var rel: Array[float] = []
	rel.resize(core.columns)
	rel.fill(-1.0)
	var objs := bm.hit_objects
	for i in objs.size():
		var n := objs[i] as ManiaNote
		for c in rel.size():
			if rel[c] >= 0.0 and rel[c] <= n.time:
				core.key_up(c, rel[c])
				rel[c] = -1.0
		var c := n.column
		if rel[c] >= 0.0:
			core.key_up(c, minf(rel[c], n.time))
			rel[c] = -1.0
		core.key_down(c, n.time)
		rel[c] = n.end_time() if n.is_hold else n.time + 40.0
		core.update(n.time)
	var t_end := 0.0
	for c in rel.size():
		if rel[c] >= 0.0:
			core.key_up(c, rel[c])
			t_end = maxf(t_end, rel[c])
	core.update(t_end + 1000.0)
	return int(core.stats().n_miss)


## song_select.gd hat keinen class_name: Skript laden, statische Funktionen aufrufen.
static func _ss() -> GDScript:
	return load("res://scripts/song_select.gd")
