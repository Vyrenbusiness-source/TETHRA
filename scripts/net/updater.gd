extends Node

## Auto-Updater (Autoload "Updater"): prueft beim Start und danach alle 10 min
## die neueste Version auf GitHub-Releases, laedt sie im Hintergrund und bietet
## per Toast den Neustart an (Auto-Neustart nach 8 s, nie mitten im Song). Der
## Tausch passiert per Batch-Skript nach dem Beenden (die laufende Exe haelt die
## .pck offen). Accounts/Scores/Settings (user://) und der maps-Ordner werden
## NIE angefasst.
##
## Release-Ablauf (Entwickler): CURRENT_VERSION hochzaehlen, PCK bauen,
## `gh release create vX.Y.Z release/TETHRA.pck` — fertig.

const CURRENT_VERSION := "1.7.9"
const REPO := "Vyrenbusiness-source/TETHRA"
const API_LATEST := "https://api.github.com/repos/" + REPO + "/releases/latest"
const HEADERS := ["User-Agent: TETHRA-Updater", "Accept: application/vnd.github+json"]

const CHECK_INTERVAL := 600.0
const RESTART_COUNTDOWN := 8.0
const BACKOFF_START := 15.0
const BACKOFF_MAX := 240.0
const MAX_RETRIES := 5
const CFG_PATH := "user://updater.cfg"
const NOTES_MAX_LINES := 6

## "", "checking", "downloading", "ready", "error" — plus Text fuers Menue.
signal state_changed(text: String, ratio: float)
var status := ""
var latest_version := ""

var _req: HTTPRequest
var _dl: HTTPRequest
var _pck_path := ""
var _new_path := ""
var _expected_size := 0
var _notes := ""
var _retries := 0
var _toast: UpdateToast
var _postponed := false
var _gate_acc := 0.0


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
	_toast = UpdateToast.new()
	_toast.restart_requested.connect(_apply_and_restart)
	_toast.postponed.connect(func(): _postponed = true)
	get_tree().root.add_child.call_deferred(_toast)
	_show_release_notes.call_deferred()
	_check_latest()
	var t := Timer.new()
	t.wait_time = CHECK_INTERVAL
	t.autostart = true
	t.timeout.connect(_on_interval)
	add_child(t)


func _on_interval() -> void:
	if status == "ready":
		_postponed = false
	elif status == "" or status == "error":
		_retries = 0
		_check_latest()


func _check_latest() -> void:
	if status == "checking" or status == "downloading" or status == "ready":
		return
	status = "checking"
	_req = HTTPRequest.new()
	_req.timeout = 10.0
	add_child(_req)
	_req.request_completed.connect(_on_latest)
	if _req.request(API_LATEST, HEADERS) != OK:
		_req.queue_free()
		_net_failed()


## Netzfehler: Retry mit Backoff (15 s, 30 s, 60 s ...), danach greift der 10-min-Timer.
func _net_failed() -> void:
	status = ""
	if _retries >= MAX_RETRIES:
		return
	var wait := backoff_for(_retries)
	_retries += 1
	get_tree().create_timer(wait).timeout.connect(_check_latest)


func _on_latest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429:
		_net_failed()
		return
	if code != 200:
		status = ""
		return
	_retries = 0
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		status = ""
		return
	latest_version = str(data.get("tag_name", "")).trim_prefix("v")
	if latest_version == "" or not _is_newer(latest_version, CURRENT_VERSION):
		status = ""
		return
	_notes = trim_notes(str(data.get("body", "")))
	# Download-URL und Soll-Groesse der TETHRA.pck aus den Release-Assets.
	var url := ""
	_expected_size = 0
	for a in data.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == "TETHRA.pck":
			url = str(a.get("browser_download_url", ""))
			_expected_size = int(a.get("size", 0))
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
		_dl.queue_free()
		_dl = null
		_download_failed()


func _download_failed() -> void:
	if FileAccess.file_exists(_new_path):
		DirAccess.remove_absolute(_new_path)
	status = "error"
	state_changed.emit("Update fehlgeschlagen — wird später erneut versucht.", -1.0)
	if _toast != null:
		_toast.show_error("Wird später erneut versucht.")
	# Kurzer Retry mit Backoff, sonst greift der 10-min-Timer.
	if _retries < MAX_RETRIES:
		var wait := backoff_for(_retries)
		_retries += 1
		get_tree().create_timer(wait).timeout.connect(func():
			if status == "error":
				status = ""
				_check_latest())


func _process(delta: float) -> void:
	if status == "downloading" and _dl != null:
		var total := _dl.get_body_size()
		if total <= 0:
			total = _expected_size
		if total > 0:
			var r := clampf(float(_dl.get_downloaded_bytes()) / float(total), 0.0, 1.0)
			state_changed.emit("⬇ Update v%s wird geladen… %d %%" % [latest_version, int(r * 100.0)], r)
			if _toast != null:
				_toast.show_progress(latest_version, r)
	elif status == "ready":
		_gate_acc += delta
		if _gate_acc >= 0.5:
			_gate_acc = 0.0
			_offer_install()


func _on_download_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	var got := -1
	var f := FileAccess.open(_new_path, FileAccess.READ)
	if f != null:
		got = f.get_length()
		f.close()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or not size_ok(got, _expected_size) or not _is_pck(_new_path):
		_download_failed()
		return
	status = "ready"
	_postponed = false
	_offer_install()


## Ausserhalb des Gameplays: Toast mit Countdown. Im Gameplay: warten bis zum Songende.
func _offer_install() -> void:
	if _toast == null or status != "ready" or _postponed:
		return
	var cs := get_tree().current_scene
	var path: String = cs.scene_file_path if cs != null else ""
	if is_gameplay_scene(path):
		state_changed.emit("Update v%s bereit — wird nach dem Song angeboten." % latest_version, 1.0)
		_toast.show_waiting(latest_version)
		return
	state_changed.emit("Update v%s bereit." % latest_version, 1.0)
	if not _toast.is_counting():
		_toast.show_ready(latest_version, RESTART_COUNTDOWN)


func _show_release_notes() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	var last := str(cfg.get_value("updater", "version", ""))
	var pending := str(cfg.get_value("updater", "pending_version", ""))
	if last != "" and last != CURRENT_VERSION and pending == CURRENT_VERSION:
		var notes := str(cfg.get_value("updater", "pending_notes", ""))
		if notes == "":
			notes = "Verbesserungen und Fehlerbehebungen."
		_toast.show_notes(CURRENT_VERSION, notes)
	cfg.set_value("updater", "version", CURRENT_VERSION)
	cfg.set_value("updater", "pending_version", "")
	cfg.set_value("updater", "pending_notes", "")
	cfg.save(CFG_PATH)


func _remember_notes() -> void:
	if latest_version == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("updater", "pending_version", latest_version)
	cfg.set_value("updater", "pending_notes", _notes)
	cfg.save(CFG_PATH)


## Release-Notes auf max. 6 nicht-leere Zeilen kuerzen.
static func trim_notes(body: String, max_lines: int = NOTES_MAX_LINES) -> String:
	var out: PackedStringArray = []
	for line in body.replace("\r", "").split("\n"):
		var l := line.strip_edges().lstrip("#").strip_edges()
		if l == "":
			continue
		if l.begins_with("- ") or l.begins_with("* "):
			l = "• " + l.substr(2)
		if l.length() > 90:
			l = l.substr(0, 89) + "…"
		out.append(l)
		if out.size() >= max_lines:
			break
	return "\n".join(out)


## Gameplay-Szene (kein Neustart mitten im Song)?
static func is_gameplay_scene(path: String) -> bool:
	return path.ends_with("mania_3d.tscn") or path.ends_with("gameplay_3d.tscn")


## Groessenpruefung gegen die GitHub-Asset-size (<= 0 = unbekannt, nicht pruefbar).
static func size_ok(actual: int, expected: int) -> bool:
	if actual < 0:
		return false
	return expected <= 0 or actual == expected


static func backoff_for(attempt: int) -> float:
	return minf(BACKOFF_START * pow(2.0, attempt), BACKOFF_MAX)


## Batch-Skript: wartet bis die Exe zu ist, tauscht die .pck, startet neu.
func _apply_and_restart() -> void:
	_remember_notes()
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
