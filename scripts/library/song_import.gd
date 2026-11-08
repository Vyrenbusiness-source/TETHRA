class_name SongImport
extends RefCounted

## Songs in die Bibliothek holen: .osz-Dateien, entpackte Map-Ordner
## (osu!stable "Songs") und — spaeter — eigene Audiodateien.
##
## Statische Helfer sind blockierend und headless testbar
## (tests/run_song_import_tests.gd). Fuer viele Ordner (osu!-Uebernahme,
## Ordner-Drop) laeuft ein Import-Job im Thread: start() -> progress(...)
## im Hauptthread -> finished(result). Abbrechen per cancel().
##
## Regel: uebernommen werden nur Sets mit mindestens einer 4K-Mania-Diff
## (Mode 3, CircleSize 4) oder osu!standard-Diff (Mode 0). Taiko, Catch,
## 5K/7K usw. werden uebersprungen bzw. nicht mit eingepackt.

signal progress(done: int, total: int, phase: String)
signal finished(result: Dictionary)

const AUDIO_EXTS := ["mp3", "ogg", "wav"]
## Videos machen ein Set schnell 50 MB+ schwer und werden nie abgespielt.
const SKIP_EXTS := ["mp4", "avi", "flv", "mkv", "webm", "wmv", "m4v", "mov"]

const PHASE_COPY := "copy"
const PHASE_ANALYSE := "analyse"

## Bibliotheks-Cache nach dem Packen im Thread vorbauen (Parsen, Sterne,
## Cover), damit der Scan im Hauptthread nur noch den Cache liest.
## Tests schalten das ab (kein python-Sternelauf).
var prebuild_library := true

var done := 0
var total := 0
var phase := PHASE_COPY

var _thread: Thread = null
var _cancel := false
var _result: Dictionary = {}
var _emitted := false


# ---------------------------------------------------------------------------
# osu!-Ordner finden
# ---------------------------------------------------------------------------

## osu!stable-Songs-Ordner (%LOCALAPPDATA%/osu!/Songs) oder "".
static func find_stable_songs_dir() -> String:
	var local := OS.get_environment("LOCALAPPDATA")
	if local == "":
		return ""
	var p := local.replace("\\", "/").path_join("osu!/Songs")
	return p if DirAccess.dir_exists_absolute(p) else ""


## osu!lazer-Datenordner (%APPDATA%/osu mit client.realm) oder "".
static func find_lazer_dir() -> String:
	var roaming := OS.get_environment("APPDATA")
	if roaming == "":
		return ""
	var p := roaming.replace("\\", "/").path_join("osu")
	return p if is_lazer_dir(p) else ""


## lazer legt Maps gehasht unter files/ ab, Index in client.realm —
## daraus lassen sich keine Map-Ordner lesen.
static func is_lazer_dir(path: String) -> bool:
	return FileAccess.file_exists(path.path_join("client.realm"))


# ---------------------------------------------------------------------------
# Map-Ordner lesen
# ---------------------------------------------------------------------------

## Map-Ordner unter root: root selbst, wenn er .osu-Dateien hat, sonst alle
## direkten Unterordner mit .osu-Dateien (osu!-Songs-Ordner). Sortiert.
static func list_map_folders(root: String) -> Array[String]:
	var out: Array[String] = []
	if _has_osu(root):
		out.append(root)
		return out
	var d := DirAccess.open(root)
	if d == null:
		return out
	var subs := d.get_directories()
	subs.sort()
	for s in subs:
		var p := root.path_join(s)
		if _has_osu(p):
			out.append(p)
	return out


static func _has_osu(dir_path: String) -> bool:
	var d := DirAccess.open(dir_path)
	if d == null:
		return false
	for f in d.get_files():
		if f.to_lower().ends_with(".osu"):
			return true
	return false


## Kopf einer .osu ohne vollen Parse: Mode, Tastenzahl, Set-ID, Titel.
## { mode, keys, set_id, title, artist }
static func osu_header(text: String) -> Dictionary:
	var h := {"mode": 0, "keys": 0, "set_id": 0, "title": "", "artist": ""}
	var section := ""
	for raw in text.split("\n", false):
		var line := raw.strip_edges()
		if line.begins_with("["):
			section = line
			if section == "[Events]" or section == "[TimingPoints]" or section == "[HitObjects]":
				break
			continue
		var c := line.find(":")
		if c <= 0:
			continue
		var k := line.substr(0, c).strip_edges()
		var v := line.substr(c + 1).strip_edges()
		match k:
			"Mode":
				h.mode = int(v)
			"CircleSize":
				if section == "[Difficulty]":
					h.keys = int(round(float(v)))
			"BeatmapSetID":
				h.set_id = int(v)
			"Title":
				h.title = v
			"Artist":
				h.artist = v
	return h


## Diff spielbar in TETHRA? osu!standard immer, Mania nur als 4K.
static func header_usable(h: Dictionary) -> bool:
	var m := int(h.get("mode", -1))
	if m == 0:
		return true
	return m == 3 and int(h.get("keys", 0)) == 4


## Ueberblick ueber einen Map-Ordner:
## { usable: bool, set_id: int, name: String, osu_files: Array[String] (nur spielbare) }
static func folder_info(folder: String) -> Dictionary:
	var info := {"usable": false, "set_id": 0, "name": folder.get_file(), "osu_files": []}
	var d := DirAccess.open(folder)
	if d == null:
		return info
	var keep: Array[String] = []
	for f in d.get_files():
		if not f.to_lower().ends_with(".osu"):
			continue
		var h := osu_header(FileAccess.get_file_as_string(folder.path_join(f)))
		if int(info.set_id) <= 0 and int(h.set_id) > 0:
			info.set_id = int(h.set_id)
		if header_usable(h):
			keep.append(f)
	if int(info.set_id) <= 0:
		info.set_id = set_id_of(folder.get_file())
	info.osu_files = keep
	info.usable = not keep.is_empty()
	return info


# ---------------------------------------------------------------------------
# Duplikate
# ---------------------------------------------------------------------------

## Set-ID aus "<id> Name", "mirror_<id>" (mit/ohne .osz), sonst 0.
static func set_id_of(name: String) -> int:
	var base := name.get_basename() if name.to_lower().ends_with(".osz") else name
	if base.begins_with("mirror_") and base.substr(7).is_valid_int():
		return int(base.substr(7))
	var head := base.split(" ")[0]
	return int(head) if head.is_valid_int() and int(head) > 0 else 0


## Vergleichsname: ohne fuehrende Set-ID, ohne " (2)"-Zaehler, klein.
static func name_key(name: String) -> String:
	var base := name.get_basename() if name.to_lower().ends_with(".osz") else name
	var parts := base.split(" ", true, 1)
	if parts.size() == 2 and parts[0].is_valid_int():
		base = parts[1]
	if base.begins_with("mirror_"):
		return ""
	var rx := RegEx.create_from_string("\\s\\(\\d+\\)$")
	base = rx.sub(base, "")
	return base.strip_edges().to_lower()


## Was liegt schon in maps_dir? { ids: {id: true}, names: {key: true} }
static func existing_index(maps_dir: String) -> Dictionary:
	var idx := {"ids": {}, "names": {}}
	var d := DirAccess.open(maps_dir)
	if d == null:
		return idx
	for f in d.get_files():
		if not f.to_lower().ends_with(".osz"):
			continue
		var sid := set_id_of(f)
		if sid > 0:
			idx.ids[sid] = true
		var nk := name_key(f)
		if nk != "":
			idx.names[nk] = true
	return idx


static func is_duplicate(idx: Dictionary, set_id: int, name: String) -> bool:
	if set_id > 0 and idx.ids.has(set_id):
		return true
	var nk := name_key(name)
	return nk != "" and idx.names.has(nk)


static func _remember(idx: Dictionary, set_id: int, name: String) -> void:
	if set_id > 0:
		idx.ids[set_id] = true
	var nk := name_key(name)
	if nk != "":
		idx.names[nk] = true


# ---------------------------------------------------------------------------
# Ordner -> .osz
# ---------------------------------------------------------------------------

## Map-Ordner als .osz packen. osu_keep: nur diese .osu-Dateien mitnehmen
## (leer = alle). Videos bleiben draussen. OK oder Fehlercode.
static func pack_folder(folder: String, dest: String, osu_keep: Array = []) -> int:
	var files: Array[String] = []
	_collect(folder, "", files)
	var zp := ZIPPacker.new()
	var tmp := dest + ".part"
	var err := zp.open(tmp)
	if err != OK:
		return err
	for rel in files:
		var ext := rel.get_extension().to_lower()
		if ext in SKIP_EXTS:
			continue
		if ext == "osu" and not osu_keep.is_empty() and not osu_keep.has(rel):
			continue
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(rel))
		if zp.start_file(rel) != OK:
			continue
		zp.write_file(bytes)
		zp.close_file()
	zp.close()
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	return DirAccess.rename_absolute(tmp, dest)


static func _collect(root: String, rel: String, out: Array[String]) -> void:
	var d := DirAccess.open(root.path_join(rel) if rel != "" else root)
	if d == null:
		return
	for f in d.get_files():
		out.append(rel.path_join(f) if rel != "" else f)
	for s in d.get_directories():
		_collect(root, rel.path_join(s) if rel != "" else s, out)


## Dateiname fuer ein Set: Ordnername ohne fuer Windows ungueltige Zeichen.
static func osz_name_for(folder: String) -> String:
	var n := folder.get_file()
	for ch in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		n = n.replace(ch, "_")
	n = n.strip_edges().trim_suffix(".")
	return (n if n != "" else "map") + ".osz"


# ---------------------------------------------------------------------------
# Einzelne Pfade (Datei-Dialog, Drag & Drop)
# ---------------------------------------------------------------------------

static func is_audio(path: String) -> bool:
	return path.get_extension().to_lower() in AUDIO_EXTS


static func is_osz(path: String) -> bool:
	return path.get_extension().to_lower() == "osz"


## Gemischte Pfadliste sortieren:
## { osz: [...], audio: [...], folders: [...], unsupported: [...] }
## folders = einzelne Map-Ordner (auch aus einem gedroppten Songs-Ordner).
static func classify(paths: PackedStringArray) -> Dictionary:
	var out := {"osz": [], "audio": [], "folders": [], "unsupported": []}
	for raw in paths:
		var p := String(raw).replace("\\", "/")
		if DirAccess.dir_exists_absolute(p):
			if is_lazer_dir(p):
				out.unsupported.append(p)
				continue
			var maps := list_map_folders(p)
			if maps.is_empty():
				out.unsupported.append(p)
			out.folders.append_array(maps)
		elif is_osz(p):
			out.osz.append(p)
		elif is_audio(p):
			out.audio.append(p)
		else:
			out.unsupported.append(p)
	return out


## TODO(audio-map): eigene Musik -> Orbit-Map. Der Generator kommt aus Task
## audio-map (AudioMapper.generate(audio_path, maps_dir)); bis zur Verdrahtung
## liefert diese Funktion bewusst nur "kommt bald". Rueckgabe:
## { ok: bool, osz_path: String, error: String }
static func import_audio(path: String) -> Dictionary:
	if not is_audio(path):
		return {"ok": false, "osz_path": "", "error": "nicht unterstuetzt"}
	# Eigene Musik -> erzeugte Orbit-Map (osu!standard, nur im Orbit-Modus). Blockierend.
	return AudioMapper.generate(path, _maps_dir_default())


static func _maps_dir_default() -> String:
	return MapLibrary.default_maps_dir()


# ---------------------------------------------------------------------------
# Import-Job (blockierend oder im Thread)
# ---------------------------------------------------------------------------

## Map-Ordner und .osz-Dateien nach maps_dir uebernehmen. Blockierend.
## Ergebnis: { imported: [osz-Pfade], dup: int, skipped: int (Modus),
##             failed: int, total: int, cancelled: bool }
func run(folders: Array, osz_files: Array, maps_dir: String, audio_files: Array = []) -> Dictionary:
	var res := {"imported": [], "dup": 0, "skipped": 0, "failed": 0, "generated": 0,
		"total": folders.size() + osz_files.size() + audio_files.size(), "cancelled": false}
	total = int(res.total)
	done = 0
	phase = PHASE_COPY
	DirAccess.make_dir_recursive_absolute(maps_dir)
	var idx := existing_index(maps_dir)
	var lib := MapLibrary.new(maps_dir)
	for f in osz_files:
		if _cancel:
			break
		var fp := String(f)
		if is_duplicate(idx, set_id_of(fp.get_file()), fp.get_file()):
			res.dup += 1
		else:
			var dest := lib.import_external(fp)
			if dest == "":
				res.failed += 1
			else:
				res.imported.append(dest)
				_remember(idx, set_id_of(fp.get_file()), fp.get_file())
		_step()
	for f in folders:
		if _cancel:
			break
		var folder := String(f)
		var info := folder_info(folder)
		if not info.usable:
			res.skipped += 1
		elif is_duplicate(idx, int(info.set_id), folder.get_file()):
			res.dup += 1
		else:
			var dest := maps_dir.path_join(osz_name_for(folder))
			var n := 1
			while FileAccess.file_exists(dest):
				dest = maps_dir.path_join("%s (%d).osz" % [osz_name_for(folder).get_basename(), n])
				n += 1
			if pack_folder(folder, dest, info.osu_files) == OK:
				res.imported.append(dest)
				_remember(idx, int(info.set_id), folder.get_file())
			else:
				res.failed += 1
		_step()
	# Eigene Musik: Orbit-Map erzeugen (dekodieren + Takt-Analyse, dauert Sekunden je Song).
	for f in audio_files:
		if _cancel:
			break
		var r := AudioMapper.generate(String(f), maps_dir)
		if bool(r.get("ok", false)):
			res.imported.append(str(r.osz_path))
			res.generated += 1
		else:
			res.failed += 1
		_step()
	res.cancelled = _cancel
	if prebuild_library and not _cancel and not res.imported.is_empty():
		phase = PHASE_ANALYSE
		done = 0
		total = res.imported.size()
		_emit_progress()
		var paths: Array[String] = []
		paths.assign(res.imported)
		lib.prebuild(paths, func(): return _cancel, func(i: int):
			done = i
			_emit_progress())
	return res


func _step() -> void:
	done += 1
	_emit_progress()


func _emit_progress() -> void:
	if _thread != null:
		emit_signal.call_deferred("progress", done, total, phase)
	else:
		progress.emit(done, total, phase)


## Job im Thread starten. finished(result) kommt im Hauptthread.
func start(folders: Array, osz_files: Array, maps_dir: String, audio_files: Array = []) -> void:
	if _thread != null:
		return
	_cancel = false
	_emitted = false
	_result = {}
	total = folders.size() + osz_files.size() + audio_files.size()
	done = 0
	_thread = Thread.new()
	_thread.start(_worker.bind(folders.duplicate(), osz_files.duplicate(), maps_dir, audio_files.duplicate()))


func _worker(folders: Array, osz_files: Array, maps_dir: String, audio_files: Array) -> void:
	_result = run(folders, osz_files, maps_dir, audio_files)
	_finish.call_deferred()


func _finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _emitted:
		return
	_emitted = true
	finished.emit(_result)


func is_running() -> bool:
	return _thread != null


func cancel() -> void:
	_cancel = true


## Auf den Thread warten (Szenenende, Tests). Liefert das Ergebnis.
func wait() -> Dictionary:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	return _result
