class_name ClipExporter
extends Node

## Clips teilen: exportiert ein gespeichertes Replay als AVI-Video ueber Godots
## Movie-Maker-Modus. Dafuer startet der Exporter einen ZWEITEN Prozess des
## Spiels (--write-movie ... --clip <md5>); GameSession erkennt "--clip" beim
## Start, spielt das Replay automatisch ab und beendet sich 3 s nach den Results.
##
## API fuer den Results-Button (Signal clip_pressed):
##   var exporter := ClipExporter.new()
##   add_child(exporter)                      # braucht den SceneTree zum Pollen
##   exporter.progress.connect(func(s): label.text = "Clip %d s ..." % int(s))
##   exporter.finished.connect(func(ok, path): ...)
##   clip_btn.pressed.connect(func():         # bzw. results.clip_pressed
##       exporter.export_clip(("%s|%s" % [osz_path.get_file(), version]).md5_text())
##   )
## Die md5 ist der Replay-Schluessel (= Dateiname in user://replays ohne .json).

## Elapsed Sekunden seit Start (aktuell keine Gesamtlaenge bekannt).
signal progress(elapsed_s: float)
## ok = AVI existiert und ist nicht leer.
signal finished(ok: bool, out_path: String)

const FPS := 60
const RESOLUTION := "1920x1080"

## Aufloesung des Clips (Tests nehmen 1280x720).
var resolution: String = RESOLUTION
## Letzter Fehlertext (leer = ok), fuer den Toast.
var last_error: String = ""
var pid: int = -1
var out_path: String = ""
var _t0_ms: int = 0


## Zielordner: Editor/Dev -> user://clips, Release -> Dokumente/TETHRA Clips.
static func clips_dir() -> String:
	var d: String
	if OS.has_feature("editor"):
		d = ProjectSettings.globalize_path("user://clips")
	else:
		d = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("TETHRA Clips")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Startet den Export. out_path leer = <clips_dir>/clip_<md5>.avi.
## Gibt false zurueck, wenn der Prozess nicht startet oder schon einer laeuft.
func export_clip(md5: String, p_out_path: String = "") -> bool:
	if is_running():
		return false
	last_error = ""
	out_path = p_out_path if p_out_path != "" else clips_dir().path_join("clip_%s.avi" % md5)
	out_path = ProjectSettings.globalize_path(out_path)
	if not FileAccess.file_exists("user://replays/%s.json" % md5):
		last_error = "Kein gespeichertes Replay"
		finished.emit(false, out_path)
		return false
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	else:
		var pck := OS.get_executable_path().get_base_dir().path_join("TETHRA.pck")
		if FileAccess.file_exists(pck):
			args.append_array(["--main-pack", pck])
	args.append_array(["--write-movie", out_path, "--fixed-fps", str(FPS),
		"--resolution", resolution, "--position", "-10000,-10000", "--clip", md5])
	pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		pid = -1
		last_error = "Prozess konnte nicht gestartet werden"
		finished.emit(false, out_path)
		return false
	_t0_ms = Time.get_ticks_msec()
	set_process(true)
	return true


func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func _ready() -> void:
	set_process(pid > 0)


func _process(_dt: float) -> void:
	if pid <= 0:
		set_process(false)
		return
	if OS.is_process_running(pid):
		progress.emit((Time.get_ticks_msec() - _t0_ms) / 1000.0)
		return
	pid = -1
	set_process(false)
	var ok := false
	if FileAccess.file_exists(out_path):
		var f := FileAccess.open(out_path, FileAccess.READ)
		ok = f != null and f.get_length() > 0
	if not ok:
		last_error = "Prozess abgebrochen, kein Video erzeugt"
	finished.emit(ok, out_path)
