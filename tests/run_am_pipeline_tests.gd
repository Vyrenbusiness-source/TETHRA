extends SceneTree

## Headless-Tests fuer AmWriter + AutoMapper4K + SongImport-Einbau (Task am-pipeline).
## Writer-Roundtrip ueber OsuParser, Mehrfach-Tempo, Holds, Kiai, Ersetzen, Dateinamen,
## Abbruch ohne ffmpeg. Der Teil mit echtem Audio braucht ffmpeg (sonst SKIP).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_pipeline_tests.gd

var _passed := 0
var _failed := 0
var _done := false
var _dir := ""


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _near(a: float, b: float, tol: float, label: String) -> void:
	_ok(absf(a - b) <= tol, "%s (ist %s, soll %s)" % [label, str(a), str(b)])


func _run() -> void:
	print("=== OMEN Auto-Mapper-Pipeline-Tests ===")
	_dir = ProjectSettings.globalize_path("user://am_pipeline_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_names()
	_test_timing()
	_test_writer()
	_test_cover_beside()
	_test_unranked()
	_test_pipeline_helpers()
	_test_no_ffmpeg()
	_test_own_songs()
	if ClipExporter.find_ffmpeg() == "":
		print("  SKIP: ffmpeg fehlt, Lauf mit echtem Audio uebersprungen")
	else:
		_test_real_audio()
	_rm(_dir)
	print("=== %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_rm(path.path_join(s))
	DirAccess.remove_absolute(path)


func _sub(name: String) -> String:
	var p := _dir.path_join(name)
	DirAccess.make_dir_recursive_absolute(p)
	return p


func _fake_audio(dir: String, name: String) -> String:
	var p := dir.path_join(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	var b := PackedByteArray()
	for i in 4096:
		b.append((i * 7) % 251)
	f.store_buffer(b)
	f.close()
	return p


func _grid2() -> Dictionary:
	return {"ok": true, "error": "", "confidence": 0.9, "alternatives": [], "segments": [
		{"start_ms": 500.0, "beat_ms": 500.0, "meter": 4, "downbeat_ms": 500.0},
		{"start_ms": 20500.0, "beat_ms": 400.0, "meter": 3, "downbeat_ms": 20500.0},
	]}


func _features() -> Dictionary:
	var ev: Array = []
	var t := 523.0
	while t < 39000.0:
		ev.append({"t_ms": t, "strength": 0.9 if int(t) % 1000 < 100 else 0.5, "kind": "kick", "pitch": -1.0, "sustain_ms": 0.0})
		t += 250.0 if t < 20500.0 else 200.0
	return {"ok": true, "error": "", "duration_ms": 40000.0, "events": ev,
		"energy": PackedFloat32Array(), "frame_ms": 10.0, "sections": [
			{"start_ms": 0.0, "end_ms": 8500.0, "intensity": 0.3, "kind": "intro", "kiai": false, "lead": "drums"},
			{"start_ms": 8500.0, "end_ms": 16500.0, "intensity": 0.8, "kind": "chorus", "kiai": true, "lead": "drums"},
			{"start_ms": 16500.0, "end_ms": 24500.0, "intensity": 0.95, "kind": "chorus", "kiai": true, "lead": "drums"},
			{"start_ms": 24500.0, "end_ms": 32100.0, "intensity": 0.4, "kind": "verse", "kiai": false, "lead": "bass"},
			{"start_ms": 32100.0, "end_ms": 36900.0, "intensity": 0.7, "kind": "build", "kiai": true, "lead": "tonal"},
			{"start_ms": 36900.0, "end_ms": 40000.0, "intensity": 0.2, "kind": "outro", "kiai": false, "lead": "tonal"},
		]}


func _chart(profile: String, step: float) -> Dictionary:
	var notes: Array = []
	var t := 1000.0
	var i := 0
	while t < 38000.0:
		var hold := i % 5 == 0
		notes.append({"t_ms": t, "col": i % 4, "end_ms": t + step * 0.5 if hold else -1.0})
		t += step
		i += 1
	return {"ok": true, "error": "", "profile": profile, "notes": notes, "stats": {}}


func _osz_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		out.append(f)
	return out


func _zip_text(osz: String, inner: String) -> String:
	var z := ZIPReader.new()
	if z.open(osz) != OK:
		return ""
	var b := z.read_file(inner)
	z.close()
	return b.get_string_from_utf8()


func _zip_names(osz: String) -> Array:
	var z := ZIPReader.new()
	if z.open(osz) != OK:
		return []
	var n := Array(z.get_files())
	z.close()
	return n


# ---------------------------------------------------------------------------

func _test_names() -> void:
	_ok(AmWriter.osz_name("MLAR", "AUTOPSIE") == "MLAR - AUTOPSIE (OMEN Auto).osz", "Dateiname des Sets")
	var n := AmWriter.osz_name("AC/DC", "What? \"Now\": <1>|2*")
	_ok(n.ends_with(" (OMEN Auto).osz"), "Dateiname behaelt Endung")
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		_ok(not n.contains(ch), "Dateiname ohne " + ch)
	_ok(AmWriter.osu_name("A", "B", "Hard") == "A - B (OMEN Auto) [Hard].osu", "Name der .osu")
	_ok(AmWriter.is_auto_set("C:/maps/A - B (OMEN Auto).osz"), "is_auto_set erkennt erzeugtes Set")
	_ok(not AmWriter.is_auto_set("C:/maps/123 A - B.osz"), "is_auto_set: fremdes Set nicht")
	_ok(SongImport.is_auto_set("x/A - B (OMEN Auto).osz"), "SongImport.is_auto_set")


func _test_timing() -> void:
	var red := AmWriter.red_points(_grid2())
	_ok(red.size() == 2, "eine rote Linie je Segment (%d)" % red.size())
	_near(float(red[0].t), 500.0, 0.01, "erste rote Linie am Taktanfang")
	_near(float(red[1].t), 20500.0, 0.01, "zweite rote Linie am Segmentbeginn")
	_ok(int(red[1].meter) == 3, "Meter des zweiten Segments")
	# Erster Taktanfang spaet im Song: Linie rutscht um ganze Takte nach vorn, bleibt >= 0.
	var late := {"segments": [{"start_ms": 4100.0, "beat_ms": 500.0, "meter": 4, "downbeat_ms": 5100.0}]}
	var r2 := AmWriter.red_points(late)
	_ok(r2.size() == 1, "ein Segment, eine Linie")
	_near(float(r2[0].t), 1100.0, 0.01, "Linie auf fruehestem Taktanfang >= 0")
	# Spaeteres Segment beginnt mitten im Takt: zweite Linie setzt den Takt zurueck.
	var mid := {"segments": [
		{"start_ms": 0.0, "beat_ms": 500.0, "meter": 4, "downbeat_ms": 0.0},
		{"start_ms": 10000.0, "beat_ms": 400.0, "meter": 4, "downbeat_ms": 10800.0}]}
	var r3 := AmWriter.red_points(mid)
	_ok(r3.size() == 3, "Segment mitten im Takt: Zusatzlinie (%d)" % r3.size())
	_near(float(r3[1].t), 10000.0, 0.01, "Segmentlinie am ersten Schlag")
	_near(float(r3[2].t), 10800.0, 0.01, "Zusatzlinie am Taktanfang")
	var k := AmWriter.kiai_ranges(_features())
	_ok(k.size() == 2, "beruehrende Kiai-Abschnitte zusammengelegt (%d)" % k.size())
	# Mit Gitter: Map-Zeit (minus OSU_LEAD) und auf den naechsten Taktanfang des Segments
	var ks := AmWriter.kiai_ranges(_features(), _grid2())
	_ok(ks.size() == 2, "Kiai mit Gitter: zwei Abschnitte (%d)" % ks.size())
	if ks.size() == 2:
		_near(float(ks[0][0]), 8500.0, 0.01, "Kiai-Beginn auf Taktanfang (4/4, 2000 ms)")
		_near(float(ks[0][1]), 24100.0, 0.01, "Kiai-Ende auf Taktanfang im 3/4-Segment")
		_near(float(ks[1][0]), 32500.0, 0.01, "zweiter Kiai-Beginn auf Taktanfang")
		_near(float(ks[1][1]), 37300.0, 0.01, "zweites Kiai-Ende auf Taktanfang")
	_ok(AmWriter.kiai_ranges({"sections": [{"start_ms": 1000.0, "end_ms": 1400.0, "kiai": true}]}, _grid2()).is_empty(),
			"Kiai kuerzer als ein Takt entfaellt")
	_ok(AmWriter.preview_time(_features()) == 16500, "PreviewTime am staerksten Refrain")
	_ok(AmWriter.preview_time({"duration_ms": 10000.0, "sections": []}) == 3000, "PreviewTime ohne Abschnitte: 30 %")


func _test_writer() -> void:
	var src := _sub("src_plain")
	var audio := _fake_audio(src, "song.mp3")
	var out := _sub("out_writer")
	var charts := [_chart("Easy", 1000.0), _chart("Hard", 250.0), _chart("Expert", 125.0)]
	var meta := {"artist": "Test: Artist", "title": "Title?", "with_orbit": true, "ffmpeg": ""}
	var w: Dictionary = AmWriter.write_osz(audio, out, meta, _grid2(), _features(), charts)
	_ok(bool(w.ok), "write_osz ok: " + str(w.get("error", "")))
	if not bool(w.ok):
		return
	var osz := str(w.osz_path)
	_ok(osz.get_file() == "Test_ Artist - Title_ (OMEN Auto).osz", "Dateiname: " + osz.get_file())
	_ok(str(w.get("background", "x")) == "bg.jpg", "ohne Bild: erzeugtes Vorschaubild bg.jpg")
	var names := _zip_names(osz)
	_ok(names.has("bg.jpg"), "Vorschaubild im Paket")
	var prev := OszImporter.decode_image_bytes(OszImporter.read_file_bytes(osz, "bg.jpg"))
	_ok(prev != null and prev.get_width() == AmWriter.PREVIEW_W and prev.get_height() == AmWriter.PREVIEW_H, "Vorschaubild 1280x720 lesbar")
	if prev != null:
		var corner := prev.get_pixel(8, 8)
		_ok(corner.r < 0.15 and corner.g < 0.15 and corner.b < 0.15, "Vorschaubild: Grund Graphit (%s)" % str(corner))
		var amber := 0
		for x in range(0, prev.get_width(), 4):
			for y in range(0, prev.get_height(), 8):
				var c := prev.get_pixel(x, y)
				if c.r > 0.75 and c.g > 0.45 and c.g < 0.75 and c.b < 0.4:
					amber += 1
		_ok(amber > 50, "Vorschaubild: Bernstein-Balken (%d)" % amber)
	_ok(names.has("audio.mp3"), "Audio als audio.mp3")
	_ok(OszImporter.read_file_bytes(osz, "audio.mp3") == FileAccess.get_file_as_bytes(audio), "Audio unveraendert")
	var osu_count := 0
	for n in names:
		if str(n).ends_with(".osu"):
			osu_count += 1
	_ok(osu_count == 3 + AudioMapper.DIFFS.size(), "3 Profile + Orbit-Diffs (%d)" % osu_count)

	for c in charts:
		var prof := str(c.profile)
		var text := _zip_text(osz, AmWriter.osu_name("Test: Artist", "Title?", prof))
		_ok(text != "", prof + ": .osu im Paket")
		var p: Dictionary = OsuParser.parse(text)
		_ok(bool(p.ok), prof + ": OsuParser ok: " + str(p.get("error", "")))
		if not bool(p.ok):
			continue
		var bm: Beatmap = p.beatmap
		_ok(bm.mode() == 3 and bm.column_count() == 4, prof + ": Mode 3, 4K")
		_ok(bm.version_name() == prof, prof + ": Version")
		_ok(str(bm.metadata.get("Creator", "")) == "OMEN Auto", prof + ": Creator")
		_ok(str(bm.metadata.get("Tags", "")) == "auto", prof + ": Tags")
		_ok(bm.title() == "Title?" and bm.artist() == "Test: Artist", prof + ": Titel/Kuenstler unveraendert")
		_ok(int(bm.general.get("PreviewTime", "-1")) == 16500, prof + ": PreviewTime")
		_near(bm.od(), float(AmWriter.PROFILE_DIFF[prof].od), 0.01, prof + ": OD")
		_near(bm.hp(), float(AmWriter.PROFILE_DIFF[prof].hp), 0.01, prof + ": HP")
		_ok(bm.background_file == "bg.jpg", prof + ": Vorschaubild in [Events]")
		var red: Array = []
		var green := 0
		for tp in bm.timing_points:
			if tp.uninherited:
				red.append(tp)
			else:
				green += 1
		_ok(red.size() == 2, prof + ": 2 rote Linien (%d)" % red.size())
		if red.size() == 2:
			_near(red[0].time, 500.0, 0.01, prof + ": Zeit rote Linie 1")
			_near(red[0].beat_length, 500.0, 0.0001, prof + ": Beat 1")
			_ok(red[0].meter == 4, prof + ": Meter 1")
			_near(red[1].time, 20500.0, 0.01, prof + ": Zeit rote Linie 2")
			_near(red[1].beat_length, 400.0, 0.0001, prof + ": Beat 2")
			_ok(red[1].meter == 3, prof + ": Meter 2")
			_ok(red[1].kiai, prof + ": rote Linie im Kiai traegt Kiai")
		_ok(green == 4, prof + ": gruene Linien nur fuer Kiai an/aus (%d)" % green)
		_ok(bm.kiai_intervals.size() == 2, prof + ": 2 Kiai-Abschnitte (%d)" % bm.kiai_intervals.size())
		if bm.kiai_intervals.size() == 2:
			_near(float(bm.kiai_intervals[0].start), 8500.0, 0.01, prof + ": Kiai 1 Beginn (Taktanfang)")
			_near(float(bm.kiai_intervals[0].end), 24100.0, 0.01, prof + ": Kiai 1 Ende (Taktanfang)")
			_near(float(bm.kiai_intervals[1].start), 32500.0, 0.01, prof + ": Kiai 2 Beginn (Taktanfang)")
			_near(float(bm.kiai_intervals[1].end), 37300.0, 0.01, prof + ": Kiai 2 Ende (Taktanfang)")
		var src_notes: Array = c.notes
		_ok(bm.hit_objects.size() == src_notes.size(), prof + ": Notenzahl %d/%d" % [bm.hit_objects.size(), src_notes.size()])
		var same := bm.hit_objects.size() == src_notes.size()
		var holds := 0
		if same:
			for i in src_notes.size():
				var n: ManiaNote = bm.hit_objects[i]
				var s: Dictionary = src_notes[i]
				if absf(n.time - roundf(float(s.t_ms))) > 0.01 or n.column != int(s.col):
					same = false
				var want_hold := float(s.end_ms) > float(s.t_ms)
				if n.is_hold != want_hold or (want_hold and absf(n.hold_end - roundf(float(s.end_ms))) > 0.01):
					same = false
				if n.is_hold:
					holds += 1
		_ok(same, prof + ": Zeiten, Spalten und Holds wie im Chart")
		_ok(holds > 0, prof + ": Holds als LN (%d)" % holds)

	# Orbit-Diffs: Mode 0, lesbar, Noten auf dem Gitter.
	var g := _grid2()
	for d in AudioMapper.DIFFS:
		var text := _zip_text(osz, AmWriter.osu_name("Test: Artist", "Title?", "Orbit " + str(d)))
		var p: Dictionary = OsuParser.parse(text)
		_ok(bool(p.ok), "Orbit %s: OsuParser ok" % d)
		if not bool(p.ok):
			continue
		var bm: Beatmap = p.beatmap
		_ok(bm.mode() == 0, "Orbit %s: Mode 0" % d)
		_ok(bm.hit_objects.size() >= 8, "Orbit %s: Noten (%d)" % [d, bm.hit_objects.size()])
		var off_grid := 0
		for h in bm.hit_objects:
			if absf(h.time - AmGrid.snap(g, h.time, 4)) > 0.6:
				off_grid += 1
		_ok(off_grid == 0, "Orbit %s: alle Noten auf dem Gitter (%d daneben)" % [d, off_grid])

	var imp: Dictionary = OszImporter.import(osz)
	_ok(bool(imp.ok), "OszImporter laedt das Set")

	# Ersetzen statt verdoppeln.
	var w2: Dictionary = AmWriter.write_osz(audio, out, meta, _grid2(), _features(), [_chart("Normal", 500.0)])
	_ok(bool(w2.ok) and str(w2.osz_path) == osz, "zweiter Lauf: gleicher Pfad")
	var files := _osz_files(out)
	_ok(files.size() == 1, "Ordner hat genau eine Datei (%s)" % str(files))
	_ok(_zip_text(osz, AmWriter.osu_name("Test: Artist", "Title?", "Normal")) != "", "neuer Inhalt im Set")
	_ok(not _zip_names(osz).has(AmWriter.osu_name("Test: Artist", "Title?", "Hard")), "alter Inhalt weg")

	# Fehlerfaelle.
	_ok(not bool(AmWriter.write_osz(audio, out, meta, {"segments": []}, _features(), charts).ok), "leeres Gitter: Fehler")
	_ok(not bool(AmWriter.write_osz(audio, out, meta, _grid2(), _features(), []).ok), "keine Charts: Fehler")
	_ok(not bool(AmWriter.write_osz(src.path_join("fehlt.mp3"), out, meta, _grid2(), _features(), charts).ok), "Audio fehlt: Fehler")


func _test_cover_beside() -> void:
	var src := _sub("src_cover")
	var audio := _fake_audio(src, "My Song.ogg")
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.6, 0.2))
	img.save_png(src.path_join("My Song.png"))
	var other := Image.create(8, 8, false, Image.FORMAT_RGB8)
	other.save_jpg(src.path_join("zzz.jpg"))
	var out := _sub("out_cover")
	var meta := {"artist": "A", "title": "B", "ffmpeg": ""}
	var w: Dictionary = AmWriter.write_osz(audio, out, meta, _grid2(), _features(), [_chart("Hard", 250.0)])
	_ok(bool(w.ok), "write_osz mit Bild ok")
	if not bool(w.ok):
		return
	_ok(str(w.background) == "bg.png", "Bild gleichen Namens hat Vorrang (%s)" % str(w.background))
	var osz := str(w.osz_path)
	_ok(_zip_names(osz).has("bg.png") and _zip_names(osz).has("audio.ogg"), "bg.png und audio.ogg im Paket")
	var p: Dictionary = OsuParser.parse(_zip_text(osz, AmWriter.osu_name("A", "B", "Hard")))
	_ok(bool(p.ok) and p.beatmap.background_file == "bg.png", "Hintergrund in [Events]")
	var tex := OszImporter.load_image_texture(osz, "bg.png")
	_ok(tex != null and tex.get_width() == 64, "Hintergrund ladbar")
	_ok(not bool(meta.get("with_orbit", false)) and not _zip_names(osz).has(AmWriter.osu_name("A", "B", "Orbit Normal")), "ohne with_orbit keine Orbit-Diffs")
	# Genau ein Bild im Ordner (anderer Name) zaehlt auch; webp wird zu jpg.
	var src2 := _sub("src_cover2")
	var audio2 := _fake_audio(src2, "x.mp3")
	img.save_webp(src2.path_join("cover.webp"))
	var c: Dictionary = AmWriter.find_cover(audio2, "")
	_ok(str(c.name) == "bg.jpg" and OszImporter.decode_image_bytes(c.bytes) != null, "einziges Bild im Ordner, webp -> bg.jpg")
	# Zwei fremde Bilder: keins gewinnt.
	other.save_jpg(src2.path_join("b.jpg"))
	_ok(str(AmWriter.find_cover(audio2, "").name) == "", "zwei Bilder ohne Namensgleichheit: keins")
	# Gross-/Kleinschreibung egal, .JPEG gross; schlaegt die fremden Bilder.
	var src3 := _sub("src_cover3")
	var audio3 := _fake_audio(src3, "Artist - Song (Official Video).mp3")
	other.save_jpg(src3.path_join("other.jpg"))
	img.save_jpg(src3.path_join("artist - song (official video).JPEG"))
	var c3: Dictionary = AmWriter.find_cover(audio3, "")
	var i3 := OszImporter.decode_image_bytes(c3.bytes) if str(c3.name) != "" else null
	_ok(str(c3.name) == "bg.jpg" and i3 != null and i3.get_width() == 64, "gleicher Name, andere Schreibung (.JPEG)")
	# Lockerer Vergleich: nur Buchstaben/Ziffern ("Artist_-_Song_(Official_Video).webp").
	var src4 := _sub("src_cover4")
	var audio4 := _fake_audio(src4, "Artist - Song (Official Video).mp3")
	other.save_jpg(src4.path_join("x.jpg"))
	img.save_webp(src4.path_join("Artist_-_Song_(Official_Video).WEBP"))
	var c4: Dictionary = AmWriter.find_cover(audio4, "")
	var i4 := OszImporter.decode_image_bytes(c4.bytes) if str(c4.name) != "" else null
	_ok(str(c4.name) == "bg.jpg" and i4 != null and i4.get_width() == 64, "aehnlicher Name (webp, Unterstriche)")
	# Kaputtes Bild gleichen Namens: uebersprungen, nicht als Hintergrund.
	var src5 := _sub("src_cover5")
	var audio5 := _fake_audio(src5, "s.ogg")
	_fake_audio(src5, "s.png")
	_ok(str(AmWriter.find_cover(audio5, "").name) == "", "unlesbares Bild wird uebersprungen")
	# Ohne Quelle (keine Features, keine Huellkurve): kein Vorschaubild.
	_ok(str(AmWriter.preview_image(PackedFloat32Array(), {}).name) == "", "ohne Quelle kein Vorschaubild")
	var wv := AmWriter.waveform(PackedFloat32Array([0.0, 0.5, -0.5, 0.0, 1.0, -1.0, 0.2, -0.2, 0.0, 0.0]), 5)
	_ok(wv.size() == 5 and wv[2] >= wv[0], "waveform: 5 Werte, laute Stelle hoeher")


func _test_unranked() -> void:
	_ok(OnlineApi.is_auto_map({"creator": "OMEN Auto", "osz_path": "x/Some.osz"}), "Creator OMEN Auto: Auto-Set")
	_ok(OnlineApi.is_auto_map({"creator": "", "osz_path": "x/A - B (OMEN Auto).osz"}), "Dateiname (OMEN Auto): Auto-Set")
	_ok(not OnlineApi.is_auto_map({"creator": "peppy", "osz_path": "x/A - B.osz"}), "fremde Map: kein Auto-Set")
	var api := OnlineApi.new()
	api.cfg_path = _dir.path_join("online.cfg")
	api.queue_path = _dir.path_join("online_queue.json")
	api.api_key = "k"
	api.token = "tok"
	var meta := {"md5": "abc", "osu_b64": "QQ==", "difficulty": "Hard", "artist": "A", "title": "B",
		"creator": "OMEN Auto", "osz_path": "x/A - B (OMEN Auto).osz", "total_notes": 10, "ranked": false}
	_ok(not api.submit({"score": 1000, "accuracy": 0.9}, meta, "mania"), "Auto-Set: kein Online-Submit")
	_ok(api.queue_size() == 0, "Auto-Set: nichts in der Warteschlange")
	meta.creator = "Someone"
	_ok(not api.submit({"score": 1000}, meta, "orbit"), "Auto-Set (Dateiname): kein Online-Submit")
	api.free()
	var entries := [
		{"mode": "mania", "osz_file": "A - B (OMEN Auto).osz", "version": "Hard", "grade": "S"},
		{"mode": "mania", "osz_file": "Real.osz", "version": "Hard", "grade": "S"},
	]
	var files := {"A - B (OMEN Auto).osz": "x/A - B (OMEN Auto).osz", "Real.osz": "x/Real.osz"}
	var cands := OnlineApi.backfill_candidates(entries, [], files)
	_ok(cands.size() == 1 and str(cands[0].osz_file) == "Real.osz", "Nachtrag alter Scores laesst Auto-Sets aus")


func _test_pipeline_helpers() -> void:
	var last := -1.0
	var mono := true
	for s in ["decode", "grid", "features", "chart", "write", "done"]:
		for f in [0.0, 0.5, 1.0]:
			var v := AutoMapper4K.overall(s, f)
			if v < last - 0.0001 or v < 0.0 or v > 1.0:
				mono = false
			last = v
	_ok(mono, "Fortschritt steigt ueber die Stufen")
	_near(AutoMapper4K.overall("done", 1.0), 1.0, 0.0001, "Fortschritt endet bei 1")
	var g := AutoMapper4K.adjusted_grid(_grid2(), 2.0, 10.0)
	_near(float(g.segments[0].beat_ms), 250.0, 0.001, "tempo_factor 2 halbiert den Schlag")
	_near(float(g.segments[0].start_ms), 510.0, 0.001, "offset_ms verschiebt den Beginn")
	_near(float(g.segments[1].downbeat_ms), 20510.0, 0.001, "offset_ms verschiebt den Taktanfang")
	_near(float(_grid2().segments[0].beat_ms), 500.0, 0.001, "Ausgangsgitter unveraendert")
	var b := AutoMapper4K.beat_times(_grid2(), 500.0, 2500.0)
	_ok(b.size() == 4 and bool(b[0][1]) and not bool(b[1][1]), "beat_times: 4 Schlaege, erster ist Taktanfang")
	var b2 := AutoMapper4K.beat_times(_grid2(), 19900.0, 21400.0)
	var ts: Array = []
	for x in b2:
		ts.append(int(roundf(float(x[0]))))
	_ok(ts == [20000, 20500, 20900, 21300], "beat_times ueber die Segmentgrenze: " + str(ts))
	_ok(int(AutoMapper4K.main_segment(_grid2(), 40000.0).meter) == 4, "main_segment: laengstes Segment")


func _test_no_ffmpeg() -> void:
	var src := _sub("src_noff")
	var audio := _fake_audio(src, "a.mp3")
	var out := _sub("out_noff")
	var stages: Array = []
	var r: Dictionary = AutoMapper4K.generate(audio, out, {"ffmpeg": "", "progress": func(s, _f): stages.append(s)})
	_ok(not bool(r.ok), "ohne ffmpeg: kein Erfolg")
	_ok(str(r.error) == AutoMapper4K.ERR_NO_FFMPEG, "ohne ffmpeg: klare Meldung (%s)" % str(r.error))
	_ok(str(r.osz_path) == "" and _osz_files(out).is_empty(), "ohne ffmpeg: nichts geschrieben")
	_ok(stages.is_empty(), "ohne ffmpeg: Abbruch vor der ersten Stufe")
	var r2: Dictionary = AutoMapper4K.generate(src.path_join("fehlt.mp3"), out, {})
	_ok(not bool(r2.ok) and str(r2.error) != "", "Datei fehlt: Fehler")
	for k in ["ok", "error", "osz_path", "bpm", "offset_ms", "confidence", "diffs", "alternatives"]:
		_ok(r.has(k), "Fehler-Ergebnis hat Feld " + k)
	# .wav braucht ffmpeg zum Wandeln (das Spiel spielt aus der .osz nur mp3/ogg).
	var wav := _fake_audio(src, "w.wav")
	var w: Dictionary = AmWriter.write_osz(wav, out, {"artist": "A", "title": "W", "ffmpeg": ""}, _grid2(), _features(), [_chart("Hard", 250.0)])
	_ok(not bool(w.ok) and str(w.error).begins_with(AmWriter.ERR_CONVERT), "wav ohne ffmpeg: klare Meldung (%s)" % str(w.error))
	_ok(_osz_files(out).is_empty(), "wav ohne ffmpeg: nichts geschrieben")


func _test_own_songs() -> void:
	var dir := _sub("own songs")
	_fake_audio(dir, "b.mp3")
	_fake_audio(dir, "a.ogg")
	_fake_audio(dir, "notes.txt")
	var idx := _dir.path_join("own_index.json")
	var p := SongImport.pending_own_songs(dir, idx)
	_ok(p.size() == 2 and p[0].get_file() == "a.ogg", "own songs: 2 Musikdateien, sortiert")
	SongImport.mark_own_songs([p[0]], idx)
	var p2 := SongImport.pending_own_songs(dir, idx)
	_ok(p2.size() == 1 and p2[0].get_file() == "b.mp3", "own songs: gemerkte Datei wird uebersprungen")
	_ok(SongImport.pending_own_songs("", idx).is_empty(), "own songs: ohne Ordner nichts")
	var c := SongImport.classify(PackedStringArray([dir.path_join("a.ogg"), dir.path_join("notes.txt")]))
	_ok(c.audio.size() == 1 and c.unsupported.size() == 1, "classify: Musik bleibt Musik")


# ---------------------------------------------------------------------------
# Echter Lauf (ffmpeg): Klick-Spur 120 BPM, mp3 mit Tags und eingebettetem Cover.
# ---------------------------------------------------------------------------

func _write_click_wav(path: String, bpm: float, seconds: float) -> void:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	data.fill(0)
	var beat := 60.0 / bpm
	var t := 0.25
	var k := 0
	while t < seconds - 0.2:
		var start := int(t * rate)
		var amp := 0.9 if k % 4 == 0 else 0.55
		for j in 900:
			var env := exp(-float(j) / 160.0)
			var v := sin(float(j) * (0.25 if k % 2 == 0 else 0.9)) * env * amp
			data.encode_s16((start + j) * 2, int(v * 32000.0))
		t += beat
		k += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("RIFF")
	f.store_32(36 + data.size())
	f.store_string("WAVEfmt ")
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_string("data")
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()


func _test_real_audio() -> void:
	var ff := ClipExporter.find_ffmpeg()
	var src := _sub("src_real")
	var wav := src.path_join("click.wav")
	_write_click_wav(wav, 120.0, 24.0)
	var cover := _sub("cover_src").path_join("c.png")
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.5, 0.9))
	img.save_png(cover)
	var mp3 := src.path_join("Some File (Official Video).mp3")
	var o := []
	var code := OS.execute(ff, ["-v", "error", "-y", "-i", wav, "-i", cover, "-map", "0:a", "-map", "1:v",
		"-c:a", "libmp3lame", "-b:a", "128k", "-c:v", "copy", "-id3v2_version", "3", "-disposition:v", "attached_pic",
		"-metadata", "artist=Click Band", "-metadata", "title=Metro Nome", mp3], o, true)
	_ok(code == 0 and FileAccess.file_exists(mp3), "Test-mp3 mit Cover gebaut: " + str(o))
	if code != 0:
		return
	DirAccess.remove_absolute(wav)
	var out := _sub("out_real")
	var stages: Array = []
	var fracs: Array = []
	var r: Dictionary = AutoMapper4K.generate(mp3, out, {"stars": false,
		"progress": func(s, f):
			if stages.is_empty() or stages[-1] != s:
				stages.append(s)
			fracs.append(f)})
	_ok(bool(r.ok), "generate ok: " + str(r.get("error", "")))
	if not bool(r.ok):
		return
	_ok(stages == ["decode", "grid", "features", "chart", "write", "done"], "Stufen in Reihenfolge: " + str(stages))
	var rising := true
	for i in range(1, fracs.size()):
		if float(fracs[i]) < float(fracs[i - 1]):
			rising = false
	_ok(rising and float(fracs[-1]) == 1.0, "Fortschritt steigt bis 1")
	_ok(str(r.osz_path).get_file() == "Click Band - Metro Nome (OMEN Auto).osz", "Name aus Tags: " + str(r.osz_path).get_file())
	_ok((r.diffs as Array).size() == AmChart.PROFILES.size(), "alle Profile (%d)" % (r.diffs as Array).size())
	_ok(float(r.bpm) > 0.0 and r.has("confidence") and r.has("alternatives") and r.has("offset_ms"), "Ergebnisfelder der Spec")
	_ok(str(r.background) == "bg.png", "eingebettetes Cover herausgeloest (%s)" % str(r.background))
	var osz := str(r.osz_path)
	var tex := OszImporter.load_image_texture(osz, "bg.png")
	_ok(tex != null and tex.get_width() == 96, "Cover im Set ladbar, Groesse unveraendert")
	_ok(OszImporter.read_file_bytes(osz, "audio.mp3") == FileAccess.get_file_as_bytes(mp3), "Audio unveraendert im Set")
	var mania := 0
	var orbit := 0
	for n in _zip_names(osz):
		if not str(n).ends_with(".osu"):
			continue
		var p: Dictionary = OsuParser.parse(_zip_text(osz, str(n)))
		_ok(bool(p.ok), "OsuParser laedt " + str(n))
		if not bool(p.ok):
			continue
		var bm: Beatmap = p.beatmap
		_ok(bm.background_file == "bg.png", "Hintergrund eingetragen: " + str(n))
		if bm.mode() == 3:
			mania += 1
			_ok(bm.column_count() == 4 and bm.hit_objects.size() > 0, "4K mit Noten: " + str(n))
		elif bm.mode() == 0:
			orbit += 1
	_ok(mania == AmChart.PROFILES.size(), "5 Mania-Diffs (%d)" % mania)
	_ok(orbit > 0, "Orbit-Diffs dabei (%d)" % orbit)
	# Neu erzeugen mit Tempo x2 und Offset: ersetzt das Set, doppelte BPM.
	var r2: Dictionary = AutoMapper4K.generate(mp3, out, {"stars": false, "with_orbit": false,
		"profiles": ["Hard"], "tempo_factor": 2.0, "offset_ms": 10.0})
	_ok(bool(r2.ok) and str(r2.osz_path) == osz, "Neu erzeugen: gleiches Set")
	if bool(r2.ok):
		_near(float(r2.bpm), float(r.bpm) * 2.0, 0.01, "tempo_factor 2 verdoppelt die BPM")
		_near(float(r2.offset_ms), float(r.offset_ms) + 10.0, 0.01, "offset_ms kommt im Ergebnis an")
		_ok((r2.diffs as Array).size() == 1 and str(r2.diffs[0].name) == "Hard", "profiles waehlt aus")
	var n_osz := 0
	for f in _osz_files(out):
		if str(f).ends_with(".osz"):
			n_osz += 1
	_ok(n_osz == 1, "nach Neu-Erzeugen genau ein Set (%d)" % n_osz)

	# .wav ohne Cover: Set mit audio.ogg (spielbar) und erzeugtem Vorschaubild.
	var src_w := _sub("src_wav")
	var wav2 := src_w.path_join("Click Wave.wav")
	_write_click_wav(wav2, 120.0, 12.0)
	var out_w := _sub("out_wav")
	var rw: Dictionary = AutoMapper4K.generate(wav2, out_w, {"stars": false, "with_orbit": false, "profiles": ["Hard"]})
	_ok(bool(rw.ok), "wav: generate ok: " + str(rw.get("error", "")))
	if bool(rw.ok):
		var ow := str(rw.osz_path)
		var nw := _zip_names(ow)
		_ok(nw.has("audio.ogg") and not nw.has("audio.wav"), "wav: als audio.ogg im Set: " + str(nw))
		var st := OszImporter.load_audio_stream_named(ow, "audio.ogg")
		_ok(st is AudioStreamOggVorbis, "wav: Stream im Spiel ladbar")
		if st != null:
			_near(st.get_length(), 12.0, 0.15, "wav: Laenge nach dem Wandeln")
		var pw: Dictionary = OsuParser.parse(_zip_text(ow, AmWriter.osu_name(str(rw.artist), str(rw.title), "Hard")))
		_ok(bool(pw.ok) and pw.beatmap.audio_filename() == "audio.ogg", "wav: AudioFilename audio.ogg")
		_ok(str(rw.background) == "bg.jpg" and bool(pw.ok) and pw.beatmap.background_file == "bg.jpg", "wav ohne Cover: Vorschaubild aus dem Song")

	# Abbruch: nichts Neues im Ordner.
	var out2 := _sub("out_cancel")
	var r3: Dictionary = AutoMapper4K.generate(mp3, out2, {"stars": false, "cancelled": func(): return true})
	_ok(not bool(r3.ok) and str(r3.error) == AutoMapper4K.ERR_CANCELLED, "Abbruch meldet cancelled")
	_ok(_osz_files(out2).is_empty(), "Abbruch schreibt nichts")

	# Import-Job (blockierend, wie der Thread): Stufen-Signal und Ergebnis fuer "Takt pruefen".
	var out3 := _sub("out_job")
	var job := SongImport.new()
	job.prebuild_library = false
	var seen: Array = []
	var songs := {}
	job.stage.connect(func(song, s, _f):
		songs[song] = true
		if seen.is_empty() or seen[-1] != s:
			seen.append(s))
	var res: Dictionary = job.run([], [], out3, [mp3])
	_ok(int(res.generated) == 1 and (res.imported as Array).size() == 1 and int(res.failed) == 0, "Import-Job erzeugt das Set")
	_ok((res.auto as Array).size() == 1 and (res.auto[0] as Dictionary).has("grid") and str(res.auto[0].audio_path) == mp3, "Ergebnis fuer den Takt-Schritt")
	_ok(songs.keys() == ["Some File (Official Video)"], "Stufen-Signal nennt die Datei: " + str(songs.keys()))
	_ok(seen.has("grid") and seen.has("chart") and seen[-1] == "done", "Import-Job meldet Stufen: " + str(seen))
