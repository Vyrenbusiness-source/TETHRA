extends Node

## Auto-Updater (Autoload "Updater"): prueft beim Start und danach alle 10 min
## die neueste Version auf GitHub-Releases, laedt sie im Hintergrund und bietet
## per Toast den Neustart an (Auto-Neustart nach 8 s, nie mitten im Song). Der
## Tausch passiert per Batch-Skript nach dem Beenden (die laufende Exe haelt die
## .pck offen). Accounts/Scores/Settings (user://) und der maps-Ordner werden
## NIE angefasst.
##
## Zwei Pakete: TETHRA.pck (Spiel, klein) und TETHRA_worlds.pck (Welten-Assets,
## gross, aendert sich selten). Das Welten-Paket wird nur geladen, wenn es lokal
## fehlt oder sich die Signatur (SHA-256-Digest bzw. Groesse+Zeitstempel des
## GitHub-Assets) geaendert hat. Download in 32-MB-Range-Stuecken in eine
## .part-Datei: Abbruch/Neustart setzt dort fort. Vorher Platzcheck.
##
## Release-Ablauf (Entwickler): CURRENT_VERSION hochzaehlen, beide PCKs bauen,
## `gh release create vX.Y.Z release/TETHRA.pck release/TETHRA_worlds.pck`.

const CURRENT_VERSION := "1.12.3"
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
## Grosse PCK (100+ MB): kein Gesamt-Timeout, stattdessen Stillstands-Wache.
const STALL_SECONDS := 45.0
const MAIN_ASSET := "TETHRA.pck"
const WORLDS_ASSET := "TETHRA_worlds.pck"
## Range-Stueckgroesse und Reserve fuer den Platzcheck.
const CHUNK_BYTES := 32 * 1024 * 1024
const SPACE_MARGIN := 64 * 1024 * 1024

## "", "checking", "downloading", "ready", "error" — plus Text fuers Menue.
signal state_changed(text: String, ratio: float)
var status := ""
var latest_version := ""

var _req: HTTPRequest
var _dl: HTTPRequest
var _exe_dir := ""
## Offene Downloads: {asset, url, size, final, new, part, sig}.
var _jobs: Array[Dictionary] = []
var _job_i := 0
var _job_offset := 0
var _done_before := 0
var _total_bytes := 0
var _notes := ""
var _retries := 0
var _toast: UpdateToast
var _postponed := false
var _gate_acc := 0.0
var _last_bytes := -1
var _stall := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Nur im Release aktiv: dort liegt TETHRA.pck neben der Exe.
	_exe_dir = OS.get_executable_path().get_base_dir()
	if not FileAccess.file_exists(_exe_dir.path_join(MAIN_ASSET)):
		return
	_commit_worlds_sig()
	# Liegt schon ein fertiges Update vom letzten Lauf da? Sofort anwenden.
	var blocked := false
	if not _ready_files().is_empty():
		if not apply_blocked(_apply_tries(), CURRENT_VERSION, CURRENT_VERSION):
			_apply_and_restart()
			return
		blocked = true
	_toast = UpdateToast.new()
	_toast.restart_requested.connect(_apply_and_restart)
	_toast.postponed.connect(func(): _postponed = true)
	get_tree().root.add_child.call_deferred(_toast)
	_show_release_notes.call_deferred()
	if blocked:
		_apply_failed.call_deferred()
		return
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
	_notes = trim_notes(str(data.get("body", "")))
	var jobs: Array[Dictionary] = []
	var assets: Array = data.get("assets", [])
	if latest_version != "" and _is_newer(latest_version, CURRENT_VERSION):
		var m := _make_job(assets, MAIN_ASSET)
		if not m.is_empty():
			jobs.append(m)
	# Welten-Paket: nur wenn lokal weg oder Signatur anders (auch ohne neue Spielversion).
	var w := _make_job(assets, WORLDS_ASSET)
	# Welten-Paket von Hand neben die Exe gelegt (gleiche Groesse wie im Release),
	# aber nie per Updater geladen: als aktuell uebernehmen statt 820 MB neu zu laden.
	if not w.is_empty() and _stored_worlds_sig() == "" 			and _file_size(_exe_dir.path_join(WORLDS_ASSET)) == int(w["size"]):
		_store_worlds_sig(str(w["sig"]))
	if not w.is_empty() and worlds_needs_update(FileAccess.file_exists(_exe_dir.path_join(WORLDS_ASSET)),
			_stored_worlds_sig(), str(w["sig"])):
		jobs.append(w)
	if jobs.is_empty():
		status = ""
		return
	_start_jobs(jobs)


func _make_job(assets: Array, asset: String) -> Dictionary:
	for a in assets:
		if a is Dictionary and str(a.get("name", "")) == asset:
			var url := str(a.get("browser_download_url", ""))
			var size := int(a.get("size", 0))
			if url == "":
				return {}
			var fin := _exe_dir.path_join(asset)
			return {"asset": asset, "url": url, "size": size, "final": fin,
				"new": fin + ".new", "part": "%s.%s.part" % [fin, str(a.get("id", 0))],
				"sig": asset_sig(a)}
	return {}


## Signatur eines Release-Assets: Digest (sha256:...) falls vorhanden, sonst Groesse+Zeitstempel.
static func asset_sig(a: Dictionary) -> String:
	var d := str(a.get("digest", ""))
	if d != "":
		return d
	return "%d@%s" % [int(a.get("size", 0)), str(a.get("updated_at", ""))]


static func worlds_needs_update(local_exists: bool, stored_sig: String, remote_sig: String) -> bool:
	return not local_exists or stored_sig != remote_sig


## Header "Range: bytes=a-b" fuer das Stueck ab offset (b gedeckelt auf total-1).
static func range_header(offset: int, chunk: int, total: int) -> String:
	var last := offset + chunk - 1
	if total > 0:
		last = mini(last, total - 1)
	return "Range: bytes=%d-%d" % [offset, last]


## Reicht der freie Platz fuer den Rest des Downloads (plus Reserve)? free < 0 = unbekannt -> ok.
static func space_ok(free: int, remaining: int) -> bool:
	return free < 0 or free >= remaining + SPACE_MARGIN


func _store_worlds_sig(sig: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("updater", "worlds_sig", sig)
	cfg.save(CFG_PATH)


## Anzeigetext: echtes Spiel-Update oder nur das (einmalige) Welten-Paket?
func _progress_title() -> String:
	for j in _jobs:
		if str(j["asset"]) == MAIN_ASSET:
			return "Update v%s wird geladen…" % latest_version
	return "Welten werden geladen (einmalig, %d MB)…" % int(round(float(_total_bytes) / 1048576.0))


func _stored_worlds_sig() -> String:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	return str(cfg.get_value("updater", "worlds_sig", ""))


## Nach dem Tausch (Neustart) die vorgemerkte Signatur als gueltig uebernehmen.
func _commit_worlds_sig() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	var pend := str(cfg.get_value("updater", "worlds_sig_pending", ""))
	if pend != "" and FileAccess.file_exists(_exe_dir.path_join(WORLDS_ASSET)) \
			and not FileAccess.file_exists(_exe_dir.path_join(WORLDS_ASSET + ".new")):
		cfg.set_value("updater", "worlds_sig", pend)
		cfg.set_value("updater", "worlds_sig_pending", "")
		cfg.save(CFG_PATH)


func _start_jobs(jobs: Array[Dictionary]) -> void:
	_jobs = jobs
	_job_i = 0
	_done_before = 0
	_total_bytes = 0
	for j in jobs:
		_total_bytes += int(j["size"])
	# Alte .part-Reste anderer Asset-IDs aufraeumen.
	var keep: PackedStringArray = []
	for j in jobs:
		keep.append(str(j["part"]).get_file())
	var d := DirAccess.open(_exe_dir)
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".part") and not keep.has(fn):
				d.remove(fn)
	status = "downloading"
	state_changed.emit("⬇ " + _progress_title(), 0.0)
	_begin_job()


func _begin_job() -> void:
	var j: Dictionary = _jobs[_job_i]
	_job_offset = _file_size(str(j["part"]))
	if _job_offset > int(j["size"]) and int(j["size"]) > 0:
		DirAccess.remove_absolute(str(j["part"]))
		_job_offset = 0
	var free := -1
	var da := DirAccess.open(_exe_dir)
	if da != null:
		free = da.get_space_left()
	if not space_ok(free, maxi(int(j["size"]) - _job_offset, 0)):
		_fail_space(int(j["size"]) - _job_offset)
		return
	_next_chunk()


func _next_chunk() -> void:
	var j: Dictionary = _jobs[_job_i]
	var size := int(j["size"])
	if size > 0 and _job_offset >= size:
		_finish_job()
		return
	_dl = HTTPRequest.new()
	_dl.timeout = 0.0  # unbegrenzt; haengende Downloads faengt die Stillstands-Wache in _process
	_dl.body_size_limit = CHUNK_BYTES + 4096
	_dl.use_threads = true
	_last_bytes = -1
	_stall = 0.0
	add_child(_dl)
	_dl.request_completed.connect(_on_chunk_done)
	var hdr: PackedStringArray = ["User-Agent: TETHRA-Updater", range_header(_job_offset, CHUNK_BYTES, size)]
	if _dl.request(str(j["url"]), hdr) != OK:
		_dl.queue_free()
		_dl = null
		_download_failed()


func _on_chunk_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	var j: Dictionary = _jobs[_job_i]
	# 206 = Teilinhalt. 200 nur, wenn der Server die ganze (kleine) Datei von vorn schickt.
	var whole := code == 200 and _job_offset == 0
	if result != HTTPRequest.RESULT_SUCCESS or not (code == 206 or whole) or body.is_empty():
		_download_failed()
		return
	var f := FileAccess.open(str(j["part"]), FileAccess.READ_WRITE if _job_offset > 0 else FileAccess.WRITE)
	if f == null:
		_download_failed()
		return
	f.seek_end()
	f.store_buffer(body)
	f.close()
	_job_offset += body.size()
	if whole:
		_finish_job()
		return
	_next_chunk()


func _finish_job() -> void:
	var j: Dictionary = _jobs[_job_i]
	var part := str(j["part"])
	var got := _file_size(part)
	if not size_ok(got, int(j["size"])) or not _is_pck(part):
		DirAccess.remove_absolute(part)  # kaputt: von vorn
		_download_failed()
		return
	if FileAccess.file_exists(str(j["new"])):
		DirAccess.remove_absolute(str(j["new"]))
	if DirAccess.rename_absolute(part, str(j["new"])) != OK:
		_download_failed()
		return
	if str(j["asset"]) == WORLDS_ASSET:
		var cfg := ConfigFile.new()
		cfg.load(CFG_PATH)
		cfg.set_value("updater", "worlds_sig_pending", str(j["sig"]))
		cfg.save(CFG_PATH)
	_done_before += int(j["size"])
	_job_i += 1
	if _job_i < _jobs.size():
		_begin_job()
		return
	status = "ready"
	_postponed = false
	_offer_install()


func _fail_space(need: int) -> void:
	status = "error"
	var msg := "Zu wenig Speicherplatz: %d MB werden benötigt." % int(ceil(float(need + SPACE_MARGIN) / 1048576.0))
	state_changed.emit(msg, -1.0)
	if _toast != null:
		_toast.show_error(msg)
	# Kein Backoff-Retry: erst der 10-min-Timer prueft erneut (Nutzer kann Platz schaffen).


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


## Fertig geladene Updates neben der Exe (.new, gueltiges PCK).
func _ready_files() -> Array[String]:
	var out: Array[String] = []
	for a in [MAIN_ASSET, WORLDS_ASSET]:
		var n: String = _exe_dir.path_join(a) + ".new"
		if FileAccess.file_exists(n) and _is_pck(n):
			out.append(a)
	return out


func _download_failed() -> void:
	# .part bleibt liegen: der naechste Versuch setzt dort fort (HTTP Range).
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
		var cur := _dl.get_downloaded_bytes()
		_watch_stall(delta, cur)
		if _dl == null:
			return
		var total := _total_bytes
		if total > 0:
			var got := _done_before + _job_offset + cur
			var r := clampf(float(got) / float(total), 0.0, 1.0)
			state_changed.emit("⬇ %s %d %%" % [_progress_title(), int(r * 100.0)], r)
			if _toast != null:
				_toast.show_progress(latest_version, r, _progress_title())
	elif status == "ready":
		_gate_acc += delta
		if _gate_acc >= 0.5:
			_gate_acc = 0.0
			_offer_install()


## Kein Byte seit STALL_SECONDS: Download abbrechen, Backoff-Retry starten.
func _watch_stall(delta: float, bytes: int) -> void:
	if bytes != _last_bytes:
		_last_bytes = bytes
		_stall = 0.0
		return
	_stall += delta
	if stalled(_stall):
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
		_download_failed()


static func stalled(stall_time: float) -> bool:
	return stall_time >= STALL_SECONDS


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


## Batch-Skript: wartet bis DIESER Prozess (pid) wirklich beendet ist, tauscht
## die .pck(s) und startet neu (mit denselben Startargumenten, z. B. OpenGL).
## Ohne Konsole: `ping` als Pause (`timeout` bricht ohne Konsole sofort ab),
## Erfolg per `if exist` pruefen (errorlevel von `move` ist unzuverlaessig).
## `move` statt `copy`: gleiche Platte = Umbenennen, bei 1+ GB sofort.
static func build_bat(exe_path: String, exe_dir: String, assets: Array, pid: int = 0,
		args: PackedStringArray = PackedStringArray()) -> String:
	var L: PackedStringArray = ["@echo off"]
	if pid > 0:
		L.append_array(["set n=0", ":wait",
			"tasklist /fi \"PID eq %d\" 2>nul | find \"%d\" >nul" % [pid, pid],
			"if errorlevel 1 goto gone", "set /a n+=1", "if %n% geq 60 goto gone",
			"ping -n 2 127.0.0.1 >nul", "goto wait", ":gone"])
	L.append("ping -n 2 127.0.0.1 >nul")
	var i := 0
	for a in assets:
		var fin: String = exe_dir.path_join(str(a)).replace("/", "\\")
		L.append_array(["set t=0", ":retry%d" % i,
			"move /y \"%s.new\" \"%s\" >nul 2>&1" % [fin, fin],
			"if not exist \"%s.new\" goto done%d" % [fin, i],
			"set /a t+=1", "if %t% geq 30 goto done" + str(i),
			"ping -n 2 127.0.0.1 >nul", "goto retry%d" % i, ":done%d" % i])
		i += 1
	var arg_s := ""
	for a in args:
		var x := str(a)
		if x.contains("\"") or x.contains("&") or x.contains("|") or x.contains("%"):
			continue
		arg_s += " \"%s\"" % x
	L.append("start \"\" /d \"%s\" \"%s\"%s" % [exe_dir.replace("/", "\\"),
			exe_path.replace("/", "\\"), arg_s])
	L.append("del \"%~f0\"")
	return "\r\n".join(L)


## Schleifen-Bremse: wie oft wurde fuer diese Spielversion schon ein Tausch
## versucht? Ab MAX_APPLY_TRIES kein Auto-Neustart mehr (Datei gesperrt o. ae.).
const MAX_APPLY_TRIES := 2

static func apply_blocked(tries: int, tried_from: String, current: String) -> bool:
	return tried_from == current and tries >= MAX_APPLY_TRIES


func _apply_tries() -> int:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	if str(cfg.get_value("updater", "apply_from", "")) != CURRENT_VERSION:
		return 0
	return int(cfg.get_value("updater", "apply_tries", 0))


func _note_apply_try() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	var n := _apply_tries() + 1
	cfg.set_value("updater", "apply_from", CURRENT_VERSION)
	cfg.set_value("updater", "apply_tries", n)
	cfg.save(CFG_PATH)


func _apply_and_restart() -> void:
	if apply_blocked(_apply_tries(), CURRENT_VERSION, CURRENT_VERSION):
		_apply_failed()
		return
	_note_apply_try()
	_remember_notes()
	var assets := _ready_files()
	var bat_path := _exe_dir.path_join("tethra_update.bat")
	var bat := build_bat(OS.get_executable_path(), _exe_dir, assets, OS.get_process_id(),
			OS.get_cmdline_args())
	var f := FileAccess.open(bat_path, FileAccess.WRITE)
	if f == null:
		_apply_failed()
		return
	f.store_string(bat)
	f.close()
	OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\")])
	get_tree().quit()


## Tausch klappte mehrfach nicht: nicht weiter neu starten, Nutzer informieren.
func _apply_failed() -> void:
	status = "error"
	var msg := "Update ließ sich nicht installieren. TETHRA schließen und neu starten — sonst neu von GitHub laden."
	state_changed.emit(msg, -1.0)
	if _toast != null:
		_toast.show_error(msg)


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
