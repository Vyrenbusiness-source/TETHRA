extends SceneTree

## Kommandozeile fuer den 4K-Auto-Mapper (Tests und Stapel). Je Song eine JSON-Zeile.
##   Godot --headless --audio-driver Dummy --path . --script res://tools/automap_cli.gd -- <audio|ordner>
##       [--out <dir>] [--profiles Easy,Hard] [--tempo <faktor>] [--offset <ms>] [--no-orbit] [--no-stars]
## Ohne --out landet das Set im maps-Ordner des Spiels (MapLibrary.default_maps_dir()).
## Ende-Code 0, wenn jeder Song ein Set ergab, sonst 1.
##
## Fensterlauf fuer Screenshots (nicht headless, eigenes APPDATA, --maps-dir=<Testordner>):
##   ... --script res://tools/automap_cli.gd -- <audio> --shot <dir> --maps-dir=<dir>
## zieht die Datei in den Browser und speichert progress.png, check.png,
## check_changed.png und browser.png (dazu offer.png, wenn "own songs" ein
## Angebot ausloest).

var _shot_dir := ""
var _shot_audio := ""
var _frame := 0
var _step := 0
var _wait := 0
var _t0 := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src := ""
	var out := ""
	var opts := {}
	var i := 0
	while i < args.size():
		var a := String(args[i])
		var next := String(args[i + 1]) if i + 1 < args.size() else ""
		match a:
			"--out":
				out = next
				i += 1
			"--profiles":
				opts["profiles"] = Array(next.split(",", false))
				i += 1
			"--tempo":
				opts["tempo_factor"] = float(next)
				i += 1
			"--offset":
				opts["offset_ms"] = float(next)
				i += 1
			"--shot":
				_shot_dir = next
				i += 1
			"--no-orbit":
				opts["with_orbit"] = false
			"--no-stars":
				opts["stars"] = false
			_:
				if not a.begins_with("--") and src == "":
					src = a.replace("\\", "/")
		i += 1
	if src == "":
		printerr("usage: -- <audio|folder> [--out <dir>] [--profiles a,b] [--tempo f] [--offset ms] [--no-orbit] [--no-stars]")
		quit(2)
		return
	if _shot_dir != "":
		_shot_audio = src
		_t0 = Time.get_ticks_msec()
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		change_scene_to_file("res://scenes/song_select.tscn")
		return
	if out == "":
		out = MapLibrary.default_maps_dir()
	var files: Array[String] = []
	if DirAccess.dir_exists_absolute(src):
		var names := DirAccess.get_files_at(src)
		names.sort()
		for f in names:
			if SongImport.is_audio(f):
				files.append(src.path_join(f))
	else:
		files.append(src)
	var bad := 0
	for f in files:
		var t := Time.get_ticks_msec()
		var r: Dictionary = AutoMapper4K.generate(f, out, opts)
		r.erase("grid")
		r["file"] = f.get_file()
		r["seconds"] = snappedf((Time.get_ticks_msec() - t) / 1000.0, 0.01)
		print(JSON.stringify(r))
		if not bool(r.get("ok", false)):
			bad += 1
	quit(1 if bad > 0 or files.is_empty() else 0)


# --- Fensterlauf ------------------------------------------------------------

func _process(_delta: float) -> bool:
	if _shot_dir == "":
		return false
	_frame += 1
	if Time.get_ticks_msec() - _t0 > 150000:
		printerr("shot: timeout in step %d" % _step)
		quit(1)
		return true
	var ss := current_scene
	if ss == null or _frame < 40:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			if ss.get("_own_offer") != null:
				_save("offer")   # Angebot fuer "own songs" unten rechts
			ss.call("_open_import_panel")
			ss.call("_import_paths", PackedStringArray([_shot_audio]))
			_step = 1
		1:
			var job = ss.get("_import_job")
			if ss.get("_automap_check") != null:
				printerr("shot: generation finished before a progress frame was caught")
				_step = 3
			elif job != null and float(job.stage_frac) >= 0.15:
				_step = 2
				_wait = 1
		2:
			_save("progress")
			_step = 3
		3:
			if ss.get("_automap_check") != null:
				_step = 4
				_wait = 150
			elif ss.get("_import_job") != null and not ss.get("_import_job").is_running():
				printerr("shot: import ended without the beat check")
				_save("failed")
				quit(1)
		4:
			_save("check")
			var c = ss.get("_automap_check")
			c.call("_mul", 2.0)
			c.call("_shift", 5.0)
			c.call("_shift", 5.0)
			_step = 5
			_wait = 40
		5:
			_save("check_changed")
			ss.get("_automap_check").call("close")
			_step = 6
			_wait = 120
		6:
			_save("browser")
			quit(0)
	return false


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var p := _shot_dir.path_join(name + ".png")
	img.save_png(p)
	print("shot: ", p)
