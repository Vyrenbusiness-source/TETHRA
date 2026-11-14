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
## Herkunft der Replay-Events (ReplayStore-Modus): "mania" ({t, lane, down})
## oder "orbit"/"orbit_last" (OrbitCore-Events, Szene orbit.tscn).
var replay_mode := "mania"
## Orbit: Songzeit, zu der der aufgezeichnete Lauf endete (meta.end_ms, -1 = bis zum Ende).
var replay_end_ms := -1.0

## Clip-Export (zweiter Prozess, siehe ClipExporter): --clip <md5> spielt das
## Replay mit dieser md5 automatisch ab und beendet das Spiel 3 s nach den Results.
var clip_md5: String = ""
## --clip-mode <ReplayStore-Modus> (fehlt = "mania").
var clip_mode: String = "mania"
const CLIP_QUIT_DELAY := 3.0
var _clip_end_t := -1.0
var _clip_end_frames := 0

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


## Online-Scores / Website-Anbindung (scripts/net/online_api.gd).
var online: OnlineApi

## Kampagne (scripts/campaign/campaign.gd): laufende Stufe {"stage": id} oder {}.
## campaign_return: Stufe, bei der die Kampagnen-Szene oeffnet.
## Eine Stufe spielt mit den Einstellungen des Spielers (2D/3D, Welt, Skin ...) wie ein
## Start aus dem Song-Browser; die Kapitel-Welt ist nur Thema der Kampagnen-Ansicht.
var campaign: Dictionary = {}
var campaign_return: String = ""
const CAMPAIGN_HUD := "res://scripts/campaign/campaign_hud.gd"


func campaign_active() -> bool:
	return str(campaign.get("stage", "")) != ""


func start_campaign(stage_id: String) -> void:
	campaign = {"stage": stage_id}


func end_campaign() -> void:
	campaign = {}


## Spielszene einer Stufe betritt den Baum (auch beim Neustart): Ziele ins HUD,
## Harness: Bild der Stufe.
func _campaign_on_node_added(n: Node) -> void:
	if not campaign_active() or n.get_parent() != get_tree().root:
		return
	if not ScoreStore.MODE_SCENES.values().has(n.scene_file_path):
		return
	_campaign_attach_hud.call_deferred(n.get_instance_id())
	if campaign_run_prefix() != "":
		_campaign_run_game_shot(n)


func _campaign_attach_hud(game_id: int) -> void:
	var game := instance_from_id(game_id) as Node
	if game == null or not game.is_inside_tree() or not campaign_active():
		return
	# Zur Laufzeit laden: GameSession kompiliert so auch in Tests ohne Autoloads (HUD -> Lobby).
	load(CAMPAIGN_HUD).call("attach_stage", game, str(campaign.get("stage", "")))


## Harness --shot-campaign-run=<Praefix>: echter Stufenlauf (Kampagnen-Szene startet die
## Stufe, --autoplay spielt, Ergebnis traegt ein). Bilder <Praefix>_stage.png, _game.png,
## _result.png. Nur mit --campaign-path=<Datei>, nie gegen den echten Stand.
static func campaign_run_prefix() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-campaign-run="):
			return a.trim_prefix("--shot-campaign-run=")
	return ""


func _campaign_run_game_shot(game: Node) -> void:
	var prefix := campaign_run_prefix()
	await get_tree().create_timer(14.0, true).timeout
	await RenderingServer.frame_post_draw
	if not is_instance_valid(game) or not game.is_inside_tree():
		return
	get_viewport().get_texture().get_image().save_png(prefix + "_game.png")
	print("CAMPAIGN-RUN Spiel: Welt-Einstellung %d" % int(get_node("/root/Settings").world_theme))


## Kampagne endet, sobald eine Szene folgt, die keine Spielszene ist (Browser, Menue, Kampagne).
func _campaign_on_scene_changed() -> void:
	if not campaign_active():
		return
	var sc := get_tree().current_scene
	if sc == null or not ScoreStore.MODE_SCENES.values().has(sc.scene_file_path):
		end_campaign()


func _ready() -> void:
	online = OnlineApi.new()
	online.name = "OnlineApi"
	add_child(online)
	_make_chat()
	set_process(false)
	_arm_test_watchdog()
	_arm_playtime()
	get_tree().scene_changed.connect(_campaign_on_scene_changed)
	get_tree().node_added.connect(_campaign_on_node_added)
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
		var j := args.find("--clip-mode")
		if j >= 0 and j + 1 < args.size():
			clip_mode = args[j + 1]
		_start_clip.call_deferred()


## Chat-Overlay (Taste F) auf eigener CanvasLayer, in allen Menues gleich.
var chat: Control


func _make_chat(force: bool = false) -> void:
	if not force and DisplayServer.get_name() == "headless" and not OS.get_cmdline_args().has("--chat-headless"):
		return
	var layer := CanvasLayer.new()
	layer.name = "ChatLayer"
	layer.layer = 90
	add_child(layer)
	chat = load("res://scripts/ui/chat_overlay.gd").new()
	layer.add_child(chat)
	# _process ist aus (nur Clips): die Sperre laeuft am Bild-Signal des Baums.
	get_tree().process_frame.connect(_gate_chat)


## Replay zur md5 in der Bibliothek suchen (md5 = "<osz-Dateiname>|<version>"),
## Auswahl setzen und die Mania- bzw. (clip_mode orbit*) Orbit-Szene im
## Replay-Modus starten.
func _start_clip() -> void:
	await get_tree().process_frame
	var replay_path := ReplayStore.path_for_key(clip_md5, clip_mode)
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
			var data := ReplayStore.load_key(clip_md5, clip_mode)
			if data.is_empty():
				break
			mods = _replay_mods(data)
			set_selection(ms.osz_path, d, ver, ms.osu_filename_at(d), ms.stars_at(d))
			is_replay = true
			replay_events = data.events
			replay_mode = clip_mode
			replay_end_ms = float(data.get("meta", {}).get("end_ms", -1.0))
			set_process(true)
			get_tree().change_scene_to_file(ClipExporter.scene_for_mode(clip_mode))
			return
	push_error("Clip: keine Map zu md5 " + clip_md5)
	get_tree().quit(1)


## Clip-Modus: sobald die Results stehen (Mania3D._ended), 3 s warten, dann beenden.
## Chat-Taste F nur ausserhalb der Spielszenen: F ist in Rebound/Rally/Mania eine
## Spieltaste. ChatOverlay kennt nur Mania/Orbit, darum sperrt GameSession die Eingabe
## des Overlays in allen sechs Modi (und im Bild des Szenenwechsels, Szene == null).
static func chat_input_allowed(scene_path: String) -> bool:
	return scene_path != "" and playtime_mode_of(scene_path) == null


func _gate_chat() -> void:
	if chat == null:
		return
	var cur := get_tree().current_scene
	var allow := chat_input_allowed(cur.scene_file_path if cur != null else "")
	if chat.is_processing_input() != allow:
		chat.set_process_input(allow)
	if not allow and chat.has_method("is_open") and chat.is_open():
		chat.close()


func _process(_dt: float) -> void:
	if clip_md5 == "":
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var ended = sc.get("_ended") if "_ended" in sc else false
	if not bool(ended):
		return
	# In Frames zaehlen, nicht in Echtzeit: der Movie-Modus rendert schneller als
	# Echtzeit, sonst haengen mehrere Sekunden Results-Bild am Clip.
	if _clip_end_t < 0.0:
		_clip_end_t = 0.0
		_clip_end_frames = 0
	_clip_end_frames += 1
	if _clip_end_frames >= int(CLIP_QUIT_DELAY * _clip_fps()):
		get_tree().quit(0)


func _clip_fps() -> float:
	var a := OS.get_cmdline_args()
	var i := a.find("--fixed-fps")
	if i >= 0 and i + 1 < a.size() and a[i + 1].is_valid_int():
		return maxf(1.0, a[i + 1].to_float())
	return 60.0


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


## Mods eines gespeicherten Replays (aeltere Replays ohne Eintrag: keine Mods).
static func _replay_mods(data: Dictionary) -> Dictionary:
	var meta = data.get("meta", {})
	var m = meta.get("mods", {}) if meta is Dictionary else {}
	if not (m is Dictionary):
		return {}
	# Alle gespeicherten Mods uebernehmen (Mania SV/NF, Orbit HD/FI/PR, SV-Stufe),
	# damit Replays und Clips exakt mit denselben Mods laufen.
	var out := {"SV": bool(m.get("SV", false)), "NF": bool(m.get("NF", false))}
	for k in m:
		if not out.has(k):
			out[k] = m[k]
	return out


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
	# Testfenster ohne Flag (nur tools/test_override.cfg als override.cfg im
	# Projekt): ebenfalls hart begrenzen, damit nie ein Fenster offen bleibt.
	if limit <= 0.0 and FileAccess.file_exists("res://override.cfg"):
		limit = 60.0
	# Live-QA (tests/live_qa.gd): mehrere Runden in einem Prozess, aussen timeout 150.
	if all.has("--live-qa") or campaign_run_prefix() != "":
		limit = 145.0
	# Marathon-Pruefung (mehrere Maps am Stueck, aussen timeout): bis 15 min.
	for a in all:
		if a.begins_with("--marathon-harness="):
			limit = 900.0
	# Movie-Aufnahmen (--write-movie) begrenzt Godot selbst per --quit-after;
	# die Watchdog-Zeit laeuft dort in Echtzeit und wuerde lange Aufnahmen kappen.
	if limit <= 0.0 or all.has("--clip") or Engine.get_write_movie_path() != "":
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


# ---------------------------------------------------------------------------
# Spielzeit (Profil): echte Sekunden im laufenden Song
# ---------------------------------------------------------------------------

const PLAYTIME_TICK := 1.0
const PLAYTIME_FLUSH_MS := 15000
var _playtime_mode := ""
var _playtime_pending := 0


## Zaehlt jede Sekunde, in der ein Song wirklich laeuft: Gameplay-Szene, nicht
## pausiert, nicht im Endbild, kein Replay/Tutorial/Testlauf. Speichert alle 15 s
## und beim Verlassen der Szene bzw. beim Beenden.
func _arm_playtime() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot") or a == "--autoplay" or a == "--smoke" or a == "--perf" 				or a.begins_with("--clip") or a.begins_with("--scores-path="):
			return
	var t := Timer.new()
	t.wait_time = PLAYTIME_TICK
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(_playtime_tick)
	t.start()


## Modus einer Szene fuer die Spielzeit: "" = Mania, sonst Modus-ID ("orbit" ...), null = keine Gameplay-Szene.
static func playtime_mode_of(scene_path: String) -> Variant:
	if scene_path.ends_with("orbit.tscn"):
		return "orbit"
	if scene_path.ends_with("rally.tscn"):
		return "rally"
	if scene_path.ends_with("dirigent.tscn"):
		return "dirigent"
	if scene_path.ends_with("trace.tscn"):
		return "trace"
	if scene_path.ends_with("rebound.tscn"):
		return "rebound"
	if scene_path.ends_with("mania_3d.tscn") or scene_path.ends_with("gameplay_3d.tscn"):
		return ""
	return null


func _playtime_tick() -> void:
	var sc := get_tree().current_scene
	var mode: Variant = playtime_mode_of(sc.scene_file_path) if sc != null else null
	var running: bool = mode != null and not get_tree().paused and not is_replay and not tutorial 			and not ("_ended" in sc and bool(sc.get("_ended")))
	if not running or str(mode) != _playtime_mode:
		_playtime_flush()
	if running:
		_playtime_mode = str(mode)
		_playtime_pending += int(PLAYTIME_TICK * 1000.0)
		if _playtime_pending >= PLAYTIME_FLUSH_MS:
			_playtime_flush()


func _playtime_flush() -> void:
	if _playtime_pending > 0:
		ScoreStore.add_playtime(_playtime_pending, _playtime_mode)
	_playtime_pending = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_playtime_flush()
