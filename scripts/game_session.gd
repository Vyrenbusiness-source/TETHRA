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

## Aktive Mods (kosmetisch/teilweise funktional). z.B. {"NF": true}.
var mods: Dictionary = {}
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


func _ready() -> void:
	set_process(false)
	_arm_test_watchdog()
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
	if sc == null or not bool(sc.get("_ended")):
		return
	if _clip_end_t < 0.0:
		_clip_end_t = Time.get_ticks_msec() / 1000.0
	elif Time.get_ticks_msec() / 1000.0 - _clip_end_t >= CLIP_QUIT_DELAY:
		get_tree().quit(0)


func set_selection(p_osz_path: String, p_difficulty_index: int, p_difficulty_version: String = "", p_osu_filename: String = "", p_stars: float = -1.0) -> void:
	osz_path = p_osz_path
	difficulty_index = p_difficulty_index
	difficulty_version = p_difficulty_version
	osu_filename = p_osu_filename
	stars = p_stars


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
		if a.begins_with("--shot") or a == "--autoplay" or a == "--smoke":
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
