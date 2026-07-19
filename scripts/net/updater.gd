extends Node

## Auto-Updater (Autoload "Updater"): prueft beim Start die neueste Version
## auf GitHub-Releases und laedt sie automatisch herunter — kein manuelles
## Loeschen/Neuinstallieren. Der Tausch passiert per Batch-Skript nach dem
## Beenden (die laufende Exe haelt die .pck offen). Accounts/Scores/Settings
## (user://) und der maps-Ordner werden NIE angefasst.
##
## Release-Ablauf (Entwickler): CURRENT_VERSION hochzaehlen, PCK bauen,
## `gh release create vX.Y.Z release/TETHRA.pck` — fertig.

const CURRENT_VERSION := "1.0.2"
const REPO := "Vyrenbusiness-source/TETHRA"
const API_LATEST := "https://api.github.com/repos/" + REPO + "/releases/latest"
const HEADERS := ["User-Agent: TETHRA-Updater", "Accept: application/vnd.github+json"]

## "", "checking", "downloading", "ready", "error" — plus Text fuers Menue.
signal state_changed(text: String, ratio: float)
var status := ""
var latest_version := ""

var _req: HTTPRequest
var _dl: HTTPRequest
var _pck_path := ""
var _new_path := ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Nur im Release aktiv: dort liegt TETHRA.pck neben der Exe.
	var exe_dir := OS.get_executable_path().get_base_dir()
	_pck_path = exe_dir.path_join("TETHRA.pck")
	_new_path = exe_dir.path_join("TETHRA.pck.new")
	if not FileAccess.file_exists(_pck_path):
		return
	# Liegt schon ein fertiges Update vom letzten Lauf da? Sofort anwenden.
	if FileAccess.file_exists(_new_path) and _is_pck(_new_path):
		_apply_and_restart()
		return
	_check_latest()


func _check_latest() -> void:
	status = "checking"
	_req = HTTPRequest.new()
	_req.timeout = 10.0
	add_child(_req)
	_req.request_completed.connect(_on_latest)
	if _req.request(API_LATEST, HEADERS) != OK:
		status = "error"


func _on_latest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status = ""
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		status = ""
		return
	latest_version = str(data.get("tag_name", "")).trim_prefix("v")
	if latest_version == "" or not _is_newer(latest_version, CURRENT_VERSION):
		status = ""
		return
	# Download-URL der TETHRA.pck aus den Release-Assets suchen.
	var url := ""
	for a in data.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == "TETHRA.pck":
			url = str(a.get("browser_download_url", ""))
			break
	if url == "":
		status = ""
		return
	_start_download(url)


func _start_download(url: String) -> void:
	status = "downloading"
	state_changed.emit("⬇ Update v%s wird geladen…" % latest_version, 0.0)
	_dl = HTTPRequest.new()
	_dl.timeout = 300.0
	_dl.use_threads = true
	_dl.download_chunk_size = 4 * 1024 * 1024
	_dl.download_file = _new_path
	add_child(_dl)
	_dl.request_completed.connect(_on_download_done)
	if _dl.request(url, ["User-Agent: TETHRA-Updater"]) != OK:
		status = "error"
		state_changed.emit("Update fehlgeschlagen — beim naechsten Start erneut.", -1.0)


func _process(_delta: float) -> void:
	if status != "downloading" or _dl == null:
		return
	var total := _dl.get_body_size()
	if total > 0:
		var r := clampf(float(_dl.get_downloaded_bytes()) / float(total), 0.0, 1.0)
		state_changed.emit("⬇ Update v%s wird geladen… %d %%" % [latest_version, int(r * 100.0)], r)


func _on_download_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not _is_pck(_new_path):
		if FileAccess.file_exists(_new_path):
			DirAccess.remove_absolute(_new_path)
		status = "error"
		state_changed.emit("Update fehlgeschlagen — beim naechsten Start erneut.", -1.0)
		return
	status = "ready"
	# Im Hauptmenue: sofort neu starten (der User hat noch nichts angefangen).
	# Sonst (mitten im Spiel o.ae.): Update liegt bereit und wird beim
	# naechsten Start automatisch angewendet.
	var cs := get_tree().current_scene
	if cs != null and str(cs.scene_file_path).ends_with("main_menu.tscn"):
		state_changed.emit("Update v%s installiert — Neustart…" % latest_version, 1.0)
		await get_tree().create_timer(0.8, true).timeout
		_apply_and_restart()
	else:
		state_changed.emit("Update v%s bereit — wird beim naechsten Start installiert." % latest_version, 1.0)


## Batch-Skript: wartet bis die Exe zu ist, tauscht die .pck, startet neu.
func _apply_and_restart() -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var bat_path := exe_dir.path_join("tethra_update.bat")
	var bat := "@echo off\r\n" \
			+ "timeout /t 1 /nobreak >nul\r\n" \
			+ ":retry\r\n" \
			+ "copy /y \"%s\" \"%s\" >nul 2>&1\r\n" % [_new_path.replace("/", "\\"), _pck_path.replace("/", "\\")] \
			+ "if errorlevel 1 (timeout /t 1 /nobreak >nul & goto retry)\r\n" \
			+ "del \"%s\" >nul 2>&1\r\n" % _new_path.replace("/", "\\") \
			+ "start \"\" \"%s\"\r\n" % OS.get_executable_path().replace("/", "\\") \
			+ "del \"%~f0\""
	var f := FileAccess.open(bat_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(bat)
	f.close()
	OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\")])
	get_tree().quit()


func _is_pck(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 1024:
		return false
	var magic := f.get_buffer(4)
	f.close()
	# Godot-PCK-Magic "GDPC".
	return magic.size() == 4 and magic[0] == 0x47 and magic[1] == 0x44 \
			and magic[2] == 0x50 and magic[3] == 0x43


## Semver-Vergleich: ist a neuer als b?
func _is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var va := int(pa[i]) if i < pa.size() else 0
		var vb := int(pb[i]) if i < pb.size() else 0
		if va != vb:
			return va > vb
	return false
