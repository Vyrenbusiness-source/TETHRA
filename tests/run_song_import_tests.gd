extends SceneTree

## Headless-Tests fuer SongImport (scripts/library/song_import.gd):
## Fake-osu!-Songs-Ordner in user://test_tmp, Modus-Filter (4K/std),
## Duplikate, gepacktes .osz lesbar durch OszImporter, Thread-Job, Drop-Sortierung,
## Bibliotheks-Modusregel (MapSet.mode_shows).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_song_import_tests.gd

const ROOT := "user://test_tmp/song_import"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== OMEN Song-Import-Tests ===")
	var root := ProjectSettings.globalize_path(ROOT)
	_rm(root)
	var songs := root.path_join("Songs")
	var maps := root.path_join("maps")
	DirAccess.make_dir_recursive_absolute(songs)
	DirAccess.make_dir_recursive_absolute(maps)

	# Fake-Songs-Ordner: std, 4K, 7K, Taiko, gemischt (4K + 7K), Duplikat.
	_make_set(songs.path_join("101 Artist A - Std Song"), 101, [[0, 4, "Normal"]], true)
	_make_set(songs.path_join("102 Artist B - Mania Four"), 102, [[3, 4, "4K Hard"]])
	_make_set(songs.path_join("103 Artist C - Mania Seven"), 103, [[3, 7, "7K"]])
	_make_set(songs.path_join("104 Artist D - Taiko"), 104, [[1, 5, "Oni"]])
	_make_set(songs.path_join("105 Artist E - Mixed"), 105, [[3, 4, "4K"], [3, 7, "7K"]])
	_make_set(songs.path_join("106 Artist F - Already Here"), 106, [[3, 4, "4K"]])
	_make_set(songs.path_join("Artist G - No Id"), 0, [[0, 4, "Easy"]])
	DirAccess.make_dir_recursive_absolute(songs.path_join("empty folder"))
	# Schon in der Bibliothek: Set 106 (per ID) und "Artist G - No Id" (per Name).
	_touch(maps.path_join("mirror_106.osz"))
	_touch(maps.path_join("Artist G - No Id.osz"))

	# --- Kopf-Parser / Filter ---
	var h := SongImport.osu_header(_osu(3, 4, "X", 7))
	_ok(int(h.mode) == 3 and int(h.keys) == 4 and int(h.set_id) == 7, "osu_header liest Mode/Keys/Set-ID")
	_ok(SongImport.header_usable({"mode": 0, "keys": 9}), "std nutzbar")
	_ok(SongImport.header_usable({"mode": 3, "keys": 4}), "4K nutzbar")
	_ok(not SongImport.header_usable({"mode": 3, "keys": 7}), "7K uebersprungen")
	_ok(not SongImport.header_usable({"mode": 1, "keys": 5}), "Taiko uebersprungen")
	_ok(not SongImport.header_usable({"mode": 2, "keys": 4}), "Catch uebersprungen")

	# --- Ordner finden ---
	var folders := SongImport.list_map_folders(songs)
	_ok(folders.size() == 7, "7 Map-Ordner gefunden, leerer Ordner ignoriert (%d)" % folders.size())
	var single := SongImport.list_map_folders(songs.path_join("102 Artist B - Mania Four"))
	_ok(single.size() == 1, "einzelner Map-Ordner = er selbst")

	# --- Duplikat-Erkennung ---
	_ok(SongImport.set_id_of("1538859 Billain - Specialist.osz") == 1538859, "Set-ID aus '<id> Name.osz'")
	_ok(SongImport.set_id_of("mirror_42.osz") == 42, "Set-ID aus mirror_<id>.osz")
	_ok(SongImport.set_id_of("Artist - Title") == 0, "keine Set-ID -> 0")
	_ok(SongImport.name_key("123 Foo - Bar (2).osz") == "foo - bar", "name_key ohne ID und Zaehler")
	var idx := SongImport.existing_index(maps)
	_ok(SongImport.is_duplicate(idx, 106, "x"), "Duplikat per Set-ID")
	_ok(SongImport.is_duplicate(idx, 0, "Artist G - No Id"), "Duplikat per Name")
	_ok(not SongImport.is_duplicate(idx, 101, "101 Artist A - Std Song"), "neues Set kein Duplikat")

	# --- Blockierender Lauf ---
	var job := SongImport.new()
	job.prebuild_library = false
	var steps := [0]
	job.progress.connect(func(_d, _t, _p): steps[0] += 1)
	var res := job.run(folders, [], maps)
	_ok(int(res.total) == 7, "total 7")
	_ok(res.imported.size() == 3, "3 Sets uebernommen (std, 4K, gemischt): %d" % res.imported.size())
	_ok(int(res.dup) == 2, "2 Duplikate uebersprungen: %d" % int(res.dup))
	_ok(int(res.skipped) == 2, "2 Sets ohne 4K/std uebersprungen: %d" % int(res.skipped))
	_ok(int(res.failed) == 0, "keine Fehler")
	_ok(steps[0] == 7, "Fortschritt pro Ordner gemeldet: %d" % steps[0])
	_ok(FileAccess.file_exists(maps.path_join("101 Artist A - Std Song.osz")), "Dateiname = Ordnername.osz")

	# --- ZIP lesbar, 7K-Diff nicht mit eingepackt, Video draussen ---
	var mixed := OszImporter._import_uncached(maps.path_join("105 Artist E - Mixed.osz"))
	_ok(mixed.ok and mixed.difficulties.size() == 1, "gemischtes Set: nur 4K-Diff im .osz")
	if mixed.ok and not mixed.difficulties.is_empty():
		var bm: Beatmap = mixed.difficulties[0].beatmap
		_ok(bm.is_mania() and bm.column_count() == 4, "4K-Diff parst als Mania 4K")
	var std := OszImporter._import_uncached(maps.path_join("101 Artist A - Std Song.osz"))
	_ok(std.ok and std.difficulties.size() == 1 and int(std.difficulties[0].beatmap.mode()) == 0, "std-Set lesbar durch OszImporter")
	var zr := ZIPReader.new()
	if zr.open(maps.path_join("101 Artist A - Std Song.osz")) == OK:
		var inner := zr.get_files()
		_ok(inner.has("audio.mp3") and inner.has("bg.jpg"), "Audio und Bild mitgepackt")
		_ok(inner.has("sb/layer.png"), "Unterordner mitgepackt")
		_ok(not inner.has("video.mp4"), "Video nicht mitgepackt")
		zr.close()
	else:
		_ok(false, "gepacktes .osz oeffnet als ZIP")

	# --- Zweiter Lauf: alles schon da ---
	var again := job.run(folders, [], maps)
	_ok(again.imported.is_empty() and int(again.dup) == 5, "zweiter Lauf: nichts neu, 5 Duplikate (%d)" % int(again.dup))

	# --- Thread-Job + Abbrechen ---
	var maps2 := root.path_join("maps2")
	var tj := SongImport.new()
	tj.prebuild_library = false
	tj.start(folders, [], maps2)
	_ok(tj.is_running(), "Thread-Job laeuft")
	var tres := tj.wait()
	_ok(not tj.is_running() and tres.imported.size() == 5, "Thread-Job: 5 Sets (leere Bibliothek): %d" % tres.imported.size())
	var cj := SongImport.new()
	cj.prebuild_library = false
	cj.cancel()
	var cres := cj.run(folders, [], root.path_join("maps3"))
	_ok(bool(cres.cancelled) and cres.imported.is_empty(), "abgebrochen: nichts uebernommen")

	# --- .osz-Dateien (Dialog/Drop) ---
	var maps4 := root.path_join("maps4")
	var oj := SongImport.new()
	oj.prebuild_library = false
	var src_osz := maps.path_join("102 Artist B - Mania Four.osz")
	var ores := oj.run([], [src_osz], maps4)
	_ok(ores.imported.size() == 1, ".osz kopiert")
	ores = oj.run([], [src_osz], maps4)
	_ok(ores.imported.is_empty() and int(ores.dup) == 1, ".osz zweimal -> Duplikat")

	# --- Drop-Sortierung ---
	var c := SongImport.classify(PackedStringArray([src_osz, songs, "C:/x/song.MP3", "C:/x/readme.txt",
		songs.path_join("empty folder")]))
	_ok(c.osz.size() == 1 and c.audio.size() == 1, "Drop: .osz und Audio erkannt")
	_ok(c.folders.size() == 7, "Drop: Songs-Ordner -> 7 Map-Ordner")
	_ok(c.unsupported.size() == 2, "Drop: .txt und leerer Ordner nicht unterstuetzt")
	var lazer := root.path_join("lazer")
	DirAccess.make_dir_recursive_absolute(lazer)
	_touch(lazer.path_join("client.realm"))
	_ok(SongImport.is_lazer_dir(lazer), "lazer-Ordner erkannt")
	_ok(SongImport.classify(PackedStringArray([lazer])).unsupported.size() == 1, "lazer-Ordner nicht unterstuetzt")

	# --- Audio: geht an AudioMapper (fehlende Datei -> sauberer Fehler, kein Absturz) ---
	var a := SongImport.import_audio("C:/x/fehlt.ogg")
	_ok(not bool(a.ok) and str(a.error) != "" and a.has("osz_path"), "import_audio: fehlende Datei -> Fehler")
	_ok(not bool(SongImport.import_audio("C:/x/text.txt").ok), "import_audio: kein Audio -> Fehler")

	# --- Bibliotheksregel: Mania nur 4K, std nur Orbit ---
	_ok(MapSet.mode_shows({"mode": 3}, "mania") and MapSet.mode_shows({"mode": 3}, "orbit"), "4K in Mania und Orbit")
	_ok(not MapSet.mode_shows({"mode": 0}, "mania") and MapSet.mode_shows({"mode": 0}, "orbit"), "std nur in Orbit")
	_rm(root)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _osu(mode: int, keys: int, version: String, set_id: int) -> String:
	var objs := ""
	if mode == 3:
		var w := 512.0 / keys
		for i in 8:
			objs += "%d,192,%d,1,0,0:0:0:0:\n" % [int(w * (i % keys) + w / 2.0), 1000 + i * 300]
	else:
		for i in 8:
			objs += "%d,%d,%d,1,0,0:0:0:0:\n" % [100 + i * 30, 100 + i * 20, 1000 + i * 300]
	return """osu file format v14

[General]
AudioFilename: audio.mp3
PreviewTime: 1000
Mode: %d

[Metadata]
Title: Song
Artist: Tester
Creator: Mapper
Version: %s
BeatmapID: 1
BeatmapSetID: %d

[Difficulty]
HPDrainRate: 5
CircleSize: %d
OverallDifficulty: 7
ApproachRate: 8
SliderMultiplier: 1.4
SliderTickRate: 1

[Events]
0,0,"bg.jpg",0,0

[TimingPoints]
0,300,4,1,0,100,1,0

[HitObjects]
%s""" % [mode, version, set_id, keys, objs]


func _make_set(dir: String, set_id: int, diffs: Array, extras: bool = false) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for d in diffs:
		_write(dir.path_join("Tester - Song (Mapper) [%s].osu" % d[2]), _osu(d[0], d[1], d[2], set_id))
	_write(dir.path_join("audio.mp3"), "ID3fake")
	if extras:
		_write(dir.path_join("bg.jpg"), "fakejpg")
		_write(dir.path_join("video.mp4"), "fakevideo")
		DirAccess.make_dir_recursive_absolute(dir.path_join("sb"))
		_write(dir.path_join("sb/layer.png"), "fakepng")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _touch(path: String) -> void:
	_write(path, "x")


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for s in d.get_directories():
		_rm(path.path_join(s))
	DirAccess.remove_absolute(path)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)
