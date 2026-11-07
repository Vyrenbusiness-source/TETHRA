extends Node

## Autoload "GameSession": traegt die Auswahl aus dem Song-Browser in die
## Gameplay-/Debug-Szene. Haelt ausserdem die "zuletzt gespielte" Map fuer den
## Startzustand des Browsers (Hintergrund).

const LAST_PLAYED_PATH := "user://last_played.cfg"

## Aktuelle Auswahl fuer den naechsten Szenenwechsel.
var osz_path: String = ""
var difficulty_index: int = 0
## Stabiler Difficulty-Bezeichner (Version-Name). Robuster als der Index, da
## Song-Browser und Importer unterschiedlich sortieren.
var difficulty_version: String = ""
## Innerer .osu-Dateiname im Archiv (fuer rosu-pp/StarService).
var osu_filename: String = ""
## Star Rating der gewaehlten Difficulty (aus rosu-pp, -1 = unbekannt).
var stars: float = -1.0

## Aktive Mods, Schnittstelle {"SV": bool, "NF": bool}.
## NF: kein Fail. SV: jede Map mit generierten Tempowechseln (SvMod).
var mods: Dictionary = {}
## Score-Multiplikatoren und Badge-Liste: ManiaCore.MOD_MULT / mod_multiplier
## / mod_list (SV x1.10, NF x0.5, kombiniert = Produkt).


static func mod_multiplier(p_mods: Dictionary) -> float:
	return ManiaCore.mod_multiplier(p_mods)


static func mod_list(p_mods: Dictionary) -> Array:
	return ManiaCore.mod_list(p_mods)


## Tutorial-Modus: Uebungs-Map mit Erklaer-Stopps, ohne Score-Wertung.
var tutorial := false

## Replay-Wiedergabe: true = aufgezeichnete Inputs abspielen statt Tastatur.
var is_replay := false
var replay_events: Array = []

## Clip-Export (zweiter Prozess, siehe ClipExporter): --clip <md5> spielt das
## Replay mit dieser md5 automatisch ab und beendet das Spiel 3 s nach den Results.
var clip_md5: String = ""
const CLIP_QUIT_DELAY := 3.0
var _clip_end_t := -1.0

## Lade-Messung (--perf): jede Phase loggt "PERF <phase> <ms>". Im Perf-Modus
## laeuft der Weg Hauptmenue -> Song-Browser -> Map-Wechsel -> SPIELEN automatisch;
## 10 s nach dem ersten Gameplay-Frame kommt die Frame-Statistik, dann Ende.
var perf_enabled := false
const PERF_GAMEPLAY_SEC := 10.0
var _perf_req_t := 0
var _perf_req_name := ""
var _perf_wait_frame := false
var _perf_gameplay_t := 0
var _perf_last_frame_t := 0
var _perf_frames: Array = []


func _ready() -> void:
	set_process(false)
	_arm_test_watchdog()
	perf_enabled = OS.get_cmdline_args().has("--perf") or OS.get_cmdline_user_args().has("--perf")
	if perf_enabled:
		perf_since("Engine-Start -> Autoload GameSession", 0)
		OszImporter.perf = true
		get_tree().scene_changed.connect(_perf_on_scene_changed)
		RenderingServer.frame_post_draw.connect(_perf_on_frame)
		_perf_req_t = 0
		_perf_req_name = "Spielstart -> Hauptmenue"
		_perf_wait_frame = true
	var args := OS.get_cmdline_args()
	var i := args.find("--clip")
	if i >= 0 and i + 1 < args.size():
		clip_md5 = args[i + 1]
		_start_clip.call_deferred()


## Replay zur md5 in der Bibliothek suchen (md5 = "<osz-Dateiname>|<version>"),
## Auswahl setzen und die Mania-Szene im Replay-Modus starten.
func _start_clip() -> void:
	await get_tree().process_frame
	var replay_path := "%s/%s.json" % [ReplayStore.DIR, clip_md5]
	if not FileAccess.file_exists(replay_path):
		push_error("Clip: kein Replay " + replay_path)
		get_tree().quit(1)
		return
	var lib := MapLibrary.new()
	lib.scan()
	for ms in lib.mapsets:
		for d in ms.difficulty_count():
			var ver: String = ms.version_name_at(d)
			if ("%s|%s" % [ms.osz_path.get_file(), ver]).md5_text() != clip_md5:
				continue
			var data := ReplayStore.load_replay(ms.osz_path, ver)
			if data.is_empty():
				break
			mods = {}
			set_selection(ms.osz_path, d, ver, ms.osu_filename_at(d), ms.stars_at(d))
			is_replay = true
			replay_events = data.events
			set_process(true)
			get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")
			return
	push_error("Clip: keine Map zu md5 " + clip_md5)
	get_tree().quit(1)


## Clip-Modus: sobald die Results stehen (Mania3D._ended), 3 s warten, dann beenden.
func _process(_dt: float) -> void:
	if clip_md5 == "":
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var ended = sc.get("_ended") if "_ended" in sc else false
	if not bool(ended):
		return
	if _clip_end_t < 0.0:
		_clip_end_t = Time.get_ticks_msec() / 1000.0
	elif Time.get_ticks_msec() / 1000.0 - _clip_end_t >= CLIP_QUIT_DELAY:
		get_tree().quit(0)


## Phase seit t0 (Time.get_ticks_usec) loggen.
func perf_since(phase: String, t0: int) -> void:
	if perf_enabled:
		print("PERF %-44s %9.1f ms" % [phase, float(Time.get_ticks_usec() - t0) / 1000.0])


## Szenenwechsel-Messung starten: Zeit bis zum ersten gezeichneten Frame der
## neuen Szene (Laden + _ready + erster Draw).
func perf_request(phase: String) -> void:
	if not perf_enabled:
		return
	_perf_req_t = Time.get_ticks_usec()
	_perf_req_name = phase


func _perf_on_scene_changed() -> void:
	var sc := get_tree().current_scene
	if sc == null or _perf_req_name == "":
		return
	perf_since(_perf_req_name + " (Szene bereit)", _perf_req_t)
	_perf_wait_frame = true


func _perf_on_frame() -> void:
	var now := Time.get_ticks_usec()
	if _perf_wait_frame:
		_perf_wait_frame = false
		perf_since(_perf_req_name + " (erster Frame)", _perf_req_t)
		_perf_req_name = ""
		var sc := get_tree().current_scene
		if sc != null and (sc.scene_file_path.contains("mania_3d") or sc.scene_file_path.contains("gameplay_3d")):
			_perf_gameplay_t = now
			_perf_frames.clear()
	elif _perf_gameplay_t > 0:
		_perf_frames.append(now - _perf_last_frame_t)
		if now - _perf_gameplay_t >= int(PERF_GAMEPLAY_SEC * 1000000.0):
			_perf_report_frames()
	_perf_last_frame_t = now


## Frame-Statistik der ersten Gameplay-Sekunden (Shader-/Lade-Haenger).
func _perf_report_frames() -> void:
	_perf_gameplay_t = 0
	var worst := 0
	var over50 := 0
	var over100 := 0
	var total := 0
	for f in _perf_frames:
		worst = maxi(worst, int(f))
		total += int(f)
		if f > 50000:
			over50 += 1
		if f > 100000:
			over100 += 1
	print("PERF %-44s %9.1f ms" % ["Gameplay laengster Frame (10 s)", worst / 1000.0])
	print("PERF %-44s %9d" % ["Gameplay Frames > 50 ms", over50])
	print("PERF %-44s %9d" % ["Gameplay Frames > 100 ms", over100])
	print("PERF %-44s %9.1f ms" % ["Gameplay Frame-Mittel", total / 1000.0 / maxf(1.0, _perf_frames.size())])
	print("PERF-DONE")
	get_tree().quit(0)


func set_selection(p_osz_path: String, p_difficulty_index: int, p_difficulty_version: String = "", p_osu_filename: String = "", p_stars: float = -1.0) -> void:
	osz_path = p_osz_path
	difficulty_index = p_difficulty_index
	difficulty_version = p_difficulty_version
	osu_filename = p_osu_filename
	stars = p_stars


## Song-Browser: Auswahl im Hintergrund vorbereiten (WorkerThreadPool) —
## .osz parsen, Audio + Cover laden. Die Gameplay-Szene bekommt beim Start
## ueber OszImporter.import()/load_audio_stream() das Fertige (kein zweites
## Entpacken/Dekodieren).
func preload_selection(p_osz_path: String, audio_name: String, bg_file: String, version: String) -> void:
	if p_osz_path != "":
		OszImporter.prepare(p_osz_path, audio_name, bg_file, version)


func has_selection() -> bool:
	return osz_path != ""


## Zuletzt gespielte Map persistent speichern (Browser-Startzustand).
## bg_file erlaubt dem Menue, das Blur-Cover ohne Vollparse zu laden.
func save_last_played(p_osz_path: String, p_difficulty_index: int, p_bg_file: String = "") -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("last_played", "osz_path", p_osz_path)
	cfg.set_value("last_played", "difficulty_index", p_difficulty_index)
	cfg.set_value("last_played", "bg_file", p_bg_file)
	cfg.save(LAST_PLAYED_PATH)


## Liefert {osz_path, difficulty_index} der zuletzt gespielten Map oder {} .
func load_last_played() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_PLAYED_PATH) != OK:
		return {}
	var p := str(cfg.get_value("last_played", "osz_path", ""))
	if p == "" or not FileAccess.file_exists(p):
		return {}
	return {
		"osz_path": p,
		"difficulty_index": int(cfg.get_value("last_played", "difficulty_index", 0)),
		"bg_file": str(cfg.get_value("last_played", "bg_file", "")),
	}


## Test-Watchdog: jeder Debug-/Screenshot-Lauf (--shot*, --autoplay) beendet sich
## spaetestens nach 45 s, Headless-Test-Runner (--script) nach 120 s selbst, damit keine
## Testfenster offen haengen bleiben. Prueft auch User-Args nach "--".
func _arm_test_watchdog() -> void:
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var limit := 0.0
	for a in all:
		if a.begins_with("--shot") or a == "--autoplay" or a == "--smoke" or a == "--perf":
			limit = 45.0
		elif (a == "--script" or a == "-s") and limit == 0.0:
			limit = 120.0   # Headless-Test-Runner: grosszuegiger, haengt aber nie ewig
	if limit <= 0.0 or all.has("--clip"):
		return
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = limit
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	t.timeout.connect(func() -> void:
		push_warning("Test-Watchdog: Lauf nach %d s beendet." % int(limit))
		get_tree().quit(3))
	add_child(t)
	t.start()
