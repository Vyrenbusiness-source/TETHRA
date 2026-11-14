extends Control

## OMEN Hauptmenue: Logo-Buehne, links Spielen + Liste (Multiplayer, Daily
## Trace, Tutorial, Einstellungen, Beenden), rechts die sechs Modi als Raster.
## Am Rand: Profil mit Online-Punkt, "Laeuft gerade", Update-Hinweis, Version.
## Hintergrund: entsaettigtes Cover der letzten Map, Puls exakt auf dem Beat.

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := UiTheme.DIM

var _pp_label: Label
var _name_label: Label
var _card_avatar: Control
# Interaktive Tutorial-Tour: Pfeil zeigt auf ECHTE Menue-Elemente.
var _profile_card: Control
var _btn_play: Button
var _btn_mp: Button
var _btn_orbit: Button
var _mode_subs := {}  # Modus -> Unterzeile (Sprachwechsel)
var _btn_settings: Button
var _tour_step := -1
var _tour_steps: Array = []
var _tour_overlay: Control
# Leise Menue-Musik: der zuletzt gespielte Song ab seiner Preview-Stelle.
var _music: AudioStreamPlayer
var _viz: AudioVisualizer
var _beat_clock: BeatClock
# Bass-Reaktivitaet: Logo, Shader-Hintergrund, Overlay.
var _logo: Control
var _logo_sub: Label
var _bg_mat: ShaderMaterial
var _dim_overlay: ColorRect
var _bass_avg: float = 0.0
var _bass_smooth: float = 0.0
var _kick: float = 0.0
var _pulse: float = 0.0 ## einheitlicher Puls: BeatClock, sonst Spektrum-Kick
const MUSIC_DB := -14.0
# Ken-Burns-Zoom fuer das Hintergrund-Cover.
var _bg_rect: TextureRect
var _kb_t: float = 0.0
# Now-Playing-Leiste.
var _np_bar: Control
var _np_progress: ColorRect
var _np_track: Control
var _np_title: Label
var _np_clip: Control
var _np_t: float = 0.0
var _btns: Array[Button] = []
# Menue-Musik wartet auf die Hintergrund-Vorbereitung dieser .osz.
var _music_wait := ""
var _music_wait_t := 0
# Shader-Warmup (einmal pro Prozess): Gameplay-Shader im Hintergrund laden,
# dann ein paar Frames unsichtbar in einem SubViewport rendern. Die geladenen
# Shader bleiben referenziert -> load() in der Gameplay-Szene ist sofort fertig,
# und beim ersten Song kommt kein Kompilier-Haenger.
const WARMUP_SPATIAL := [
	"aurora", "glow_dot", "god_rays", "hit_ring", "hold_beam", "note_disc",
	"note_square", "planet", "plasma_line", "rail_fire", "road_wave",
	"skill_stream", "slider_body", "space_bg", "spark", "spiral_galaxy", "tunnel",
]
const WARMUP_CANVAS := ["screen_fx", "screen_glow"]
const WARMUP_FRAMES := 3
static var _warm_shaders: Array[Shader] = []
const BROWSER_SCENE := "res://scenes/song_select.tscn"

## Logo (Quelle: docs/media/logo.svg, hier ohne Kachel und mit heller Schrift
## fuer den dunklen Menue-Hintergrund). Pfade gleich wie in logo.svg halten.
const LOGO_SIZE := Vector2(461, 88)
const LOGO_SVG := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="-4 -4 725.8 139" width="461" height="88">
<g transform="translate(-8 -34.5)">
<path d="M97.82 73.82L126.98 115.94A28 28 0 1 0 126.98 84.06L97.82 126.18A46 46 0 1 1 97.82 73.82Z" fill="none" stroke="#ECE6DA" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="115.95" cy="100" r="13" fill="#F2A23A"/>
</g>
<g transform="translate(-50.1 -59.5)">
<path d="M278.6 99A33 33 0 0 1 344.6 99V151A33 33 0 0 1 278.6 151Z" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M397.6 184V66L440.5 139.16L483.4 66V184" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M602.4 66H536.4V184H602.4M536.4 125H592.5" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M655.4 184V66L721.4 184V66" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="757.9" cy="176" r="10" fill="#F2A23A"/>
</g>
</svg>"""
static var _browser_scene: PackedScene = null
static var _browser_req := false
var _warm_pending: Array[String] = []
var _warm_vp: SubViewport = null
var _warm_frames := 0
var _warm_t := 0


func _begin_shader_warmup() -> void:
	# Song-Browser-Szene (song_select.gd ~2600 Zeilen) schon im Hintergrund
	# laden + kompilieren; die Referenz haelt sie im ResourceCache, sodass
	# SceneFader.go() -> change_scene_to_file() sie sofort bekommt.
	if _browser_scene == null and not _browser_req:
		_browser_req = ResourceLoader.load_threaded_request(BROWSER_SCENE, "PackedScene", true) == OK
	if not _warm_shaders.is_empty():
		return
	_warm_t = Time.get_ticks_usec()
	for n in WARMUP_SPATIAL + WARMUP_CANVAS:
		var path := "res://shaders/%s.gdshader" % n
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "Shader")
			_warm_pending.append(path)


func _shader_warmup_step() -> void:
	if _browser_req and ResourceLoader.load_threaded_get_status(BROWSER_SCENE) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_browser_req = false
		_browser_scene = ResourceLoader.load_threaded_get(BROWSER_SCENE) as PackedScene
	if _warm_vp != null:
		_warm_frames += 1
		if _warm_frames > WARMUP_FRAMES:
			_warm_vp.queue_free()
			_warm_vp = null
			GameSession.perf_since("Hauptmenue: Shader-Warmup fertig (seit _ready)", _warm_t)
		return
	if _warm_pending.is_empty():
		return
	for path in _warm_pending:
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
	var shaders: Array[Shader] = []
	for path in _warm_pending:
		var sh := ResourceLoader.load_threaded_get(path) as Shader
		if sh != null:
			shaders.append(sh)
	_warm_pending.clear()
	_warm_shaders = shaders
	_build_warmup_viewport(shaders)


## Winziger, unsichtbarer SubViewport (nie auf dem Bildschirm): je Shader ein
## Quad vor der Kamera, Umgebung mit Glow wie im Gameplay.
func _build_warmup_viewport(shaders: Array[Shader]) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	vp.add_child(cam)
	var quad := QuadMesh.new()
	var i := 0
	for sh in shaders:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		if sh.get_mode() == Shader.MODE_CANVAS_ITEM:
			var r := ColorRect.new()
			r.size = Vector2(8, 8)
			r.position = Vector2(i % 8, i / 8) * 8.0
			r.material = mat
			vp.add_child(r)
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mat
			mi.position = Vector3(float(i % 6) - 2.5, float(i / 6) - 1.5, 0.0) * 0.6
			mi.scale = Vector3.ONE * 0.5
			vp.add_child(mi)
		i += 1
	add_child(vp)
	_warm_vp = vp
	_warm_frames = 0


## Menue-Musik vorbereiten: .osz im Hintergrund parsen (WorkerThreadPool), damit
## der erste Menue-Frame nicht auf Entpacken + Parsen wartet; _process startet
## die Musik, sobald das Fertige bereitliegt.
func _begin_menu_music() -> void:
	var last := GameSession.load_last_played()
	if last.is_empty():
		return
	_music_wait = str(last.osz_path)
	_music_wait_t = Time.get_ticks_usec()
	OszImporter.prepare(_music_wait, "", str(last.get("bg_file", "")), "")


## Leise Hintergrundmusik: zuletzt gespielter Song ab der Preview-Stelle,
## mit sanftem Fade-in, endlos geloopt. Kein letzter Song -> Stille.
func _start_menu_music() -> void:
	var last := GameSession.load_last_played()
	if last.is_empty():
		return
	var imp := OszImporter.import(str(last.osz_path))
	if not imp.ok or imp.difficulties.is_empty():
		return
	var idx := clampi(int(last.difficulty_index), 0, imp.difficulties.size() - 1)
	var bm: Beatmap = imp.difficulties[idx].beatmap
	var stream := OszImporter.load_audio_stream(str(last.osz_path), bm)
	if stream == null:
		return
	var from_sec := maxf(float(bm.general.get("PreviewTime", -1.0)), 0.0) / 1000.0
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.bus = "Music"
	_music.volume_db = -80.0
	add_child(_music)
	_music.finished.connect(func():
		if is_instance_valid(_music):
			_music.volume_db = -80.0
			_music.play(from_sec)
			_fade_music_in())
	_music.play(from_sec)
	var cover := _load_cover(str(last.osz_path), bm)
	if not bm.timing_points.is_empty():
		_beat_clock = BeatClock.new()
		_beat_clock.setup(bm.timing_points)
	_build_now_playing(bm, cover)
	_fade_music_in()


## Klickfrei: 250 ms Fade-in beim Start/Loop.
func _fade_music_in() -> void:
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_DB, 0.25)


## Klickfrei: 120 ms Fade-out vor Szenenwechsel/Beenden.
func _fade_music_out() -> void:
	if _music != null and is_instance_valid(_music) and _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", -80.0, 0.12)


## Geblurrtes Hintergrundbild der zuletzt gespielten Map. false wenn keins da.
func _build_blur_bg() -> bool:
	var last := GameSession.load_last_played()
	if last.is_empty():
		return false
	# Schnellpfad: Hintergrund-Dateiname liegt im last_played-Cache — kein Parse.
	var bg_file := str(last.get("bg_file", ""))
	if bg_file != "":
		var fast_tex := OszImporter.load_image_texture(str(last.osz_path), bg_file)
		if fast_tex != null:
			_add_blur_layers(fast_tex)
			return true
	var imp := OszImporter.import(last.osz_path)
	if not imp.ok or imp.difficulties.is_empty():
		return false
	var idx := clampi(int(last.difficulty_index), 0, imp.difficulties.size() - 1)
	var tex := OszImporter.load_background_texture(str(last.osz_path), imp.difficulties[idx].beatmap)
	if tex == null:
		return false
	_add_blur_layers(tex)
	return true


## Senkrechte Lage des Stapels (statisch, getestet): {logo_scale, logo_y, sub_y,
## buttons_y, buttons_h, top, bottom}. Unter 900 px Hoehe Logo 85 %.
static func menu_stack(view_h: float, buttons_h: float) -> Dictionary:
	var sc := 0.85 if view_h < 900.0 else 1.0
	var total := LOGO_SIZE.y * sc + MENU_SUB_GAP + MENU_SUB_H + MENU_BTN_GAP + buttons_h
	var top := maxf(roundf((view_h - total) * 0.5), 0.0)
	var logo_y := top
	var sub_y := logo_y + LOGO_SIZE.y * sc + MENU_SUB_GAP
	var btn_y := sub_y + MENU_SUB_H + MENU_BTN_GAP
	return {"logo_scale": sc, "logo_y": logo_y, "sub_y": sub_y, "buttons_y": btn_y,
		"buttons_h": buttons_h, "top": top, "bottom": view_h - (btn_y + buttons_h)}


## Songfarbe: Durchschnitt des runterskalierten Covers, Saettigung/Helligkeit angehoben.
func _cover_color(cover: Texture2D) -> Color:
	if cover == null:
		return UiTheme.ACCENT
	var img := cover.get_image()
	if img == null or img.is_empty():
		return UiTheme.ACCENT
	if img.is_compressed():
		img.decompress()
	img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for y in 8:
		for x in 8:
			var c := img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
	var avg := Color(r / 64.0, g / 64.0, b / 64.0)
	return Color.from_hsv(avg.h, clampf(avg.s * 1.3, 0.45, 0.9), clampf(avg.v * 1.5, 0.75, 1.0))


func _load_cover(osz_path: String, bm: Beatmap) -> Texture2D:
	return OszImporter.load_background_texture(osz_path, bm)


var _btn_daily: Button
var _daily_busy := false
const DAILY_TIMEOUT_S := 8.0


## Ergebnis des letzten Trace-Laufs der Tages-Map uebernehmen (ScoreStore.last_submit).
func _daily_adopt_result(state: Dictionary) -> void:
	var today := TraceDaily.today_key()
	if not TraceDaily.has_attempt(state, today):
		return
	var e: Dictionary = state.days[today]
	var ls := ScoreStore.last_submit
	if ls.is_empty() or str(ls.get("mode", "")) != ScoreStore.mode_name("trace") or str(e.get("osz", "")) == "":
		return
	if str(ls.get("key", "")) == ScoreStore._key(str(e.osz), str(e.get("version", ""))):
		if TraceDaily.set_score(state, today, int(ls.get("score", 0))):
			TraceDaily.save_state(state)


func _daily_start() -> void:
	if _daily_busy:
		return
	_daily_busy = true
	_daily_status(tr("Finding today's map …"), true)
	var state := TraceDaily.load_state()
	var today := TraceDaily.today_key()
	# Schon gespielt: dieselbe Map nochmal (zaehlt nicht), ohne neue Suche.
	if TraceDaily.has_attempt(state, today):
		var e: Dictionary = state.days[today]
		if FileAccess.file_exists(str(e.get("osz", ""))):
			_daily_launch(str(e.osz), -1, str(e.get("version", "")), state, today, "")
			return
	var lib := MapLibrary.new()
	lib.scan()
	var mirror := get_node_or_null("/root/Mirror") as BeatmapMirror
	var items: Array = []
	if mirror != null:
		items = await _daily_online_items(mirror)
	var pick := {}
	if not items.is_empty():
		pick = TraceDaily.pick(today, TraceDaily.online_pool(items))
	var ms: MapSet = null
	if not pick.is_empty():
		ms = _daily_find_set(lib, int(pick.set_id))
		if ms == null and mirror != null:
			ms = await _daily_download(mirror, int(pick.set_id))
	if ms == null:
		# Offline (oder Download fehlgeschlagen): nur lokale Maps.
		var lp := TraceDaily.pick(today, TraceDaily.local_pool(lib.mapsets))
		for cand in lib.mapsets:
			if not lp.is_empty() and cand.osz_path == lp.osz_path:
				ms = cand
	var idx := TraceDaily.pick_diff(ms) if ms != null else -1
	if ms == null or idx < 0:
		_daily_busy = false
		_daily_status(tr("No 4K map found"), false)
		return
	_daily_launch(ms.osz_path, idx, ms.version_name_at(idx), state, today, ms.osu_filename_at(idx), ms.stars_at(idx))


func _daily_launch(osz: String, idx: int, version: String, state: Dictionary, today: String,
		osu_file: String, stars: float = -1.0) -> void:
	if idx < 0:
		# Wiederholung: Index ueber die Bibliothek aufloesen.
		var lib := MapLibrary.new()
		lib.scan()
		for ms in lib.mapsets:
			if ms.osz_path == osz:
				for i in ms.difficulty_count():
					if ms.version_name_at(i) == version:
						idx = i
						osu_file = ms.osu_filename_at(i)
						stars = ms.stars_at(i)
	if idx < 0:
		_daily_busy = false
		_refresh_daily()
		if is_instance_valid(_btn_daily):
			_btn_daily.disabled = false
		return
	if TraceDaily.start_attempt(state, today, osz.get_file()):
		var e: Dictionary = state.days[today]
		e["osz"] = osz
		e["version"] = version
		TraceDaily.save_state(state)
	GameSession.mods = {}
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.replay_mode = "mania"
	GameSession.set_selection(osz, idx, version, osu_file, stars)
	_fade_music_out()
	SceneFader.go(ScoreStore.mode_scene("trace"))


func _daily_find_set(lib: MapLibrary, set_id: int) -> MapSet:
	var pre := "%012d" % set_id
	for ms in lib.mapsets:
		if TraceDaily._set_key(str(ms.osz_path).get_file()).begins_with(pre) and TraceDaily.pick_diff(ms) >= 0:
			return ms
	return null


## Erste Seite Ranked-4K (beliebteste) vom Map-Browser-Mirror; [] bei Fehler/Zeitueberschreitung.
func _daily_online_items(mirror: BeatmapMirror) -> Array:
	var box := { "items": [], "done": false }
	var ok := func(results: Array, _raw: int, _off: int): box.items = results; box.done = true
	var bad := func(_msg: String): box.done = true
	mirror.search_done.connect(ok, CONNECT_ONE_SHOT)
	mirror.search_failed.connect(bad, CONNECT_ONE_SHOT)
	mirror.search("", 0, BeatmapMirror.Sort.PLAYS, BeatmapMirror.STATUS_RANKED, BeatmapMirror.MODE_MANIA)
	var t0 := Time.get_ticks_msec()
	while not box.done and Time.get_ticks_msec() - t0 < int(DAILY_TIMEOUT_S * 1000.0):
		await get_tree().process_frame
	if mirror.search_done.is_connected(ok):
		mirror.search_done.disconnect(ok)
	if mirror.search_failed.is_connected(bad):
		mirror.search_failed.disconnect(bad)
	return box.items


## Set ueber den vorhandenen Mirror-Download holen; null bei Fehler.
func _daily_download(mirror: BeatmapMirror, set_id: int) -> MapSet:
	var box := { "path": "", "done": false }
	var ok := func(id: int, path: String): if id == set_id: box.path = path; box.done = true
	var bad := func(id: int, _m: String): if id == set_id: box.done = true
	mirror.download_done.connect(ok)
	mirror.download_failed.connect(bad)
	mirror.download(set_id, MapLibrary.default_maps_dir())
	var t0 := Time.get_ticks_msec()
	while not box.done and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	mirror.download_done.disconnect(ok)
	mirror.download_failed.disconnect(bad)
	if str(box.path) == "":
		return null
	var lib := MapLibrary.new()
	lib.scan()
	return _daily_find_set(lib, set_id)


## Modus-Kacheln des Hauptmenues (Reihenfolge = ScoreStore.MODES).
const MENU_MODES := ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]


## "MULTIPLAYER" -> "Multiplayer" (nur erster Buchstabe gross).
static func _sentence(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1).to_lower()


# ---------------------------------------------------------------------------
# Tutorial-Tour: fuehrt LIVE durchs echte Menue (Pfeil blinkt, User klickt).
# ---------------------------------------------------------------------------

func _start_tour() -> void:
	_tour_steps = [
		{ "target": _profile_card, "click": "profile",
			"text": "Das ist DEIN PROFIL: Name, pp, Profilbild.\nKlick die Karte an — und danach wieder zu!" },
		{ "target": _btn_settings, "click": "settings",
			"text": "Hier stellst du Tasten, Scroll-Speed, Offset und FPS ein.\nKlick auf EINSTELLUNGEN — schau dich um und schließe wieder!" },
		{ "target": _btn_play, "click": "",
			"text": "SPIELEN oeffnet den Song-Browser.\nDort findest du auch den Online-Tab (Maps laden), ★-Filter und Collections." },
		{ "target": _btn_mp, "click": "",
			"text": "MULTIPLAYER: Raum erstellen, Code an Freunde schicken,\ndie Krone 👑 wählt die Map — mit Live-Scoreboard!" },
	]
	_tour_step = -1
	_tour_next()


func _tour_finish() -> void:
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
	_tour_step = -1
	Sfx.ui_open()
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(16, 0.9)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "Menü-Tour fertig!"
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(t)
	var b := Label.new()
	b.text = "Jetzt die Übungs-Map: sie hält an und zeigt dir\nNoten, Holds und Doppelnoten direkt im Spiel."
	b.add_theme_font_size_override("font_size", 15)
	vb.add_child(b)
	var go := Button.new()
	go.text = UiTheme.sentence(tr("🚀 ÜBUNGS-MAP STARTEN").trim_prefix("🚀 "))
	go.custom_minimum_size = Vector2(0, 48)
	UiTheme.style_button(go, true)
	go.pressed.connect(_start_practice)
	vb.add_child(go)
	var guide := Button.new()
	guide.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	guide.text = tr("📖 Wissens-Guide lesen (pp, Sterne, Acc …)").trim_prefix("📖 ")
	guide.custom_minimum_size = Vector2(0, 42)
	UiTheme.style_button(guide)
	guide.pressed.connect(_leave.bind("res://scenes/tutorial.tscn"))
	vb.add_child(guide)
	var close := Button.new()
	close.text = "Schließen"
	close.custom_minimum_size = Vector2(0, 38)
	UiTheme.style_button(close)
	close.pressed.connect(func():
		Sfx.ui_close()
		overlay.queue_free())
	vb.add_child(close)


## Uebungs-Map (Set 844183) im Tutorial-Modus starten.
func _start_practice() -> void:
	var lib := MapLibrary.new()
	lib.scan()
	for ms in lib.mapsets:
		if not ms.osz_path.get_file().begins_with("844183"):
			continue
		for i in ms.difficulty_count():
			var m := ms.meta_at(i)
			if not MapSet.mode_shows(m, "mania@4"):  # Tutorial: nur 4K (Set hat auch 5K-7K)
				continue
			GameSession.tutorial = true
			GameSession.mods = { "NF": true }
			GameSession.is_replay = false
			GameSession.replay_events = []
			GameSession.set_selection(ms.osz_path, i, ms.version_name_at(i),
				str(m.get("osu_filename", "")), ms.stars_at(i))
			_leave("res://scenes/mania_3d.tscn")
			return


func _play() -> void:
	_fade_music_out()
	SceneFader.go("res://scenes/song_select.tscn")


const BROWSER_STATE := "user://browser_state.cfg"


## Modus-Einstieg: Modus in browser_state.cfg vormerken (song_select liest
## "browser"/"play_mode" beim Start), restliche Browser-Werte bleiben.
func _play_mode_entry(mode: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(BROWSER_STATE)
	cfg.set_value("browser", "play_mode", mode)
	cfg.save(BROWSER_STATE)
	if mode == "orbit":
		# Bis der Spieler gewaehlt hat, fuehrt der Orbit-Eintrag in die Karriere.
		var career := OrbitCareer.load_state()
		if not bool(career.get("chosen", false)):
			career["mode"] = OrbitCareer.MODE_CAREER
			OrbitCareer.save_state(career)
	_play()


func _mode_sub_text(mode: String) -> String:
	# Modus ohne Spielszene: Kachel zeigt "Kommt bald" (Browser blendet ihn genauso aus).
	if not ScoreStore.mode_ready(mode):
		return tr("Kommt bald")
	match mode:
		"mania": return tr("Vier Spuren")
		"rally": return tr("Tischtennis")
		"dirigent": return tr("Takt führen")
		"trace": return tr("Den Takt zeichnen")
		"rebound": return tr("Im Takt springen")
	return tr("Zielen + Tippen")


## "?" auf einer Kachel: Tutorial des Modus (nur wenn scenes/<modus>_tutorial.tscn existiert).
func _start_mode_tutorial(mode: String) -> void:
	var path := ScoreStore.mode_tutorial(mode)
	if path == "":
		return
	if mode == "orbit" and ResourceLoader.exists("res://scripts/orbit/orbit_tutorial.gd"):
		(load("res://scripts/orbit/orbit_tutorial.gd") as GDScript).mark_seen()
	_fade_music_out()
	SceneFader.go(path)


func _capture() -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/main_menu.png"
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			path = a.trim_prefix("--shot-out=")
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


## Ruhiger Hinweis nach hartem Absturz: sicherer Grafikmodus wurde aktiviert.
func _show_gpu_notice() -> void:
	var l := Label.new()
	l.text = tr("Das Spiel wurde zuletzt unerwartet beendet. Sicherer Grafikmodus ist an (Einstellungen > Grafik).")
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.offset_left = -250
	l.offset_right = 250
	l.offset_top = 26
	l.offset_bottom = 70
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------------------
# Ansicht. Alles in Entwurfs-Einheiten (1 Einheit = 1 px bei 1280x720); _u
# rechnet auf die Fenstergroesse um. Schrift und Symbole werden in der
# Zielgroesse gerastert (nie skaliert), jede Kante liegt auf ganzen Pixeln.
# Raster: Inhalt 1088 breit = Spalte links 320 + Abstand 48 + 3 Kacheln je 232
# (Abstand 12). Rand zum Fenster 32.
# ---------------------------------------------------------------------------

const GRID_W := 1088.0
const COL_W := 320.0
const COL_GAP := 48.0
const TILE_W := 232.0
const TILE_H := 140.0
const TILE_GAP := 12.0
const PLAY_H := 58.0
const ROW_H := 37.0
const EDGE := 32.0
const BLOCK_H := TILE_H * 2.0 + TILE_GAP  # 292 = PLAY_H + 12 + 6 * ROW_H

## Symbole der Modi (Quelle: assets_game/icons/modes/<modus>.svg, gleiche Pfade).
## Hier als Text, damit sie in der Zielgroesse scharf gerastert werden.
const MODE_SVG := {
	"mania": '<path d="M4.5 3.5v17M9.5 3.5v17M14.5 3.5v17M19.5 3.5v17"/>',
	"orbit": '<circle cx="11" cy="13" r="7"/><circle cx="11" cy="13" r="2"/><circle cx="19.5" cy="4.5" r="2" fill="#fff" stroke="none"/>',
	"rally": '<circle cx="9.5" cy="10.5" r="6"/><path d="M13.8 14.8l5.7 5.7"/><circle cx="19.5" cy="5" r="2" fill="#fff" stroke="none"/>',
	"dirigent": '<path d="M3.5 18.5C6 9 13 5 20.5 5.5"/><path d="M3.5 18.5l3.5-1"/><circle cx="20.5" cy="5.5" r="1.5" fill="#fff" stroke="none"/>',
	"trace": '<path d="M3.5 19.5h6v-8h5v-6h6"/><circle cx="20.5" cy="5.5" r="1.5" fill="#fff" stroke="none"/>',
	"rebound": '<circle cx="12" cy="5" r="2.5"/><path d="M3.5 20.5C6 12 18 12 20.5 20.5"/>',
}

var _u := 1.0
var _ui: Control
var _built_for := Vector2.ZERO
var _dirty := false
var _intro: Array = []
var _markers: Array[ColorRect] = []
var _logo_stage: LogoStage
var _daily_detail: Label
var _status_dot: Panel
var _upd_label: Label
var _upd_text := ""
var _np_bm: Beatmap
var _np_cover: Texture2D
var _modal := 0
var _head_font: Font
var _body_font: Font
static var _tex_cache := {}


const PREVIEW_H := 82.0


## Mini-Vorschau eines Modus in der Kachel: eine kleine Spielszene mit den echten
## Objekten und Farben des Modus (gefuellte Formen mit Verlauf, Schatten und Kontur,
## kein Linien-Piktogramm). Gezeichnet in Entwurfs-Einheiten (Breite x PREVIEW_H),
## skaliert scharf mit u. Steht still; bei Hover/Fokus laeuft die Szene ruhig in
## einer Schleife.
class ModePreview extends Control:
	const INK := UiTheme.TEXT
	const AMBER := UiTheme.ACCENT
	const DARK := Color(0.043, 0.041, 0.038)
	const BLUE := Color(0.33, 0.53, 0.76)
	const TEAL := Color(0.37, 0.72, 0.68)
	const ORANGE := Color(0.90, 0.53, 0.26)
	var mode := "mania"
	var u := 1.0
	var col := Color.WHITE
	var hover := 0.0
	var want := 0.0
	var ph := 0.3
	var _bg: StyleBoxFlat
	var _rr: StyleBoxFlat

	func _ready() -> void:
		clip_contents = true
		set_process(false)

	func set_hover(on: bool) -> void:
		want = 1.0 if on else 0.0
		set_process(true)

	func _process(delta: float) -> void:
		hover = move_toward(hover, want, delta * 7.0)
		if want > 0.0:
			ph = fposmod(ph + delta * 0.42, 1.0)
		elif hover <= 0.0:
			set_process(false)
		queue_redraw()

	func _poly(pts: PackedVector2Array, fill: Color, line: Color, w: float) -> void:
		draw_colored_polygon(pts, fill)
		var c := pts.duplicate()
		c.append(pts[0])
		c.append(pts[1])
		draw_polyline(c, line, w, true)

	func _dot(p: Vector2, r: float, fill: Color, line: Color, w: float = 1.4) -> void:
		draw_circle(p, r + 1.6, Color(DARK, fill.a), true, -1.0, true)
		draw_circle(p, r, fill, true, -1.0, true)
		draw_arc(p, r - 0.4, 0.0, TAU, 40, line, w, true)

	func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 40:
			var a := TAU * float(i) / 40.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return pts

	func _ring(c: Vector2, rx: float, ry: float, line: Color, w: float) -> void:
		var pts := _ellipse(c, rx, ry)
		pts.append(pts[0])
		draw_polyline(pts, line, w, true)

	## Viereck mit senkrechtem Verlauf (oben/unten).
	func _quad(tl: Vector2, tr: Vector2, br: Vector2, bl: Vector2, top: Color, bot: Color) -> void:
		draw_polygon(PackedVector2Array([tl, tr, br, bl]), PackedColorArray([top, top, bot, bot]))

	func _shadow(p: Vector2, rx: float, ry: float, al: float) -> void:
		draw_colored_polygon(_ellipse(p, rx * 1.4, ry * 1.4), Color(0, 0, 0, al * 0.45))
		draw_colored_polygon(_ellipse(p, rx, ry), Color(0, 0, 0, al))

	## Kugel mit Licht von oben links: Kontur, Schattenseite, Koerper, Licht, Glanzpunkt.
	func _ball(p: Vector2, r: float, c: Color, al: float = 1.0) -> void:
		draw_circle(p, r + 0.9, Color(DARK, 0.9 * al), true, -1.0, true)
		draw_circle(p, r, Color(c.darkened(0.45), al), true, -1.0, true)
		draw_circle(p + Vector2(-0.10, -0.12) * r, r * 0.84, Color(c.darkened(0.14), al), true, -1.0, true)
		draw_circle(p + Vector2(-0.22, -0.26) * r, r * 0.55, Color(c.lightened(0.16), al), true, -1.0, true)
		draw_circle(p + Vector2(-0.34, -0.38) * r, r * 0.21, Color(1, 1, 1, 0.82 * al), true, -1.0, true)

	## Flache Scheibe mit Tiefe: Schatten, dunkle Fuellung, heller oben, Rand in Farbe.
	func _disc(p: Vector2, r: float, c: Color, al: float, rim: float = 1.8) -> void:
		draw_circle(p + Vector2(0.0, 1.8), r + 1.2, Color(0, 0, 0, 0.40 * al), true, -1.0, true)
		draw_circle(p, r, Color(c.darkened(0.62), 1.0), true, -1.0, true)
		draw_circle(p + Vector2(0.0, -r * 0.12), r * 0.84, Color(c.darkened(0.50), 1.0), true, -1.0, true)
		draw_arc(p, r - rim * 0.5, 0.0, TAU, 48, Color(c, al), rim, true)

	func _half(p: Vector2, r: float, a0: float, c: Color) -> void:
		var pts := PackedVector2Array()
		for i in 25:
			var ang := a0 + PI * float(i) / 24.0
			pts.append(p + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, c)

	func _capsule(p0: Vector2, p1: Vector2, r: float, fill: Color, line: Color) -> void:
		draw_line(p0, p1, line, (r + 1.3) * 2.0, true)
		draw_circle(p0, r + 1.3, line, true, -1.0, true)
		draw_circle(p1, r + 1.3, line, true, -1.0, true)
		draw_line(p0, p1, fill, r * 2.0, true)
		draw_circle(p0, r, fill, true, -1.0, true)
		draw_circle(p1, r, fill, true, -1.0, true)

	func _rrect(r: Rect2, rad: float, fill: Color, line: Color, lw: int) -> void:
		if _rr == null:
			_rr = StyleBoxFlat.new()
			_rr.anti_aliasing = true
		_rr.bg_color = fill
		_rr.border_color = line
		_rr.set_border_width_all(lw)
		_rr.set_corner_radius_all(roundi(rad))
		draw_style_box(_rr, r)

	## Ziffer scharf in Bildpunkten (nicht ueber die Skalierung der Zeichenflaeche).
	func _num(p: Vector2, txt: String, px: float, c: Color) -> void:
		var f := get_theme_default_font()
		var fs := maxi(roundi(px * u), 6)
		var bw := 40.0 * u
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(f, Vector2(p.x * u - bw * 0.5, p.y * u + float(fs) * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, bw, fs, c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))

	func _draw() -> void:
		var s := size
		if _bg == null:
			_bg = StyleBoxFlat.new()
			_bg.anti_aliasing = true
		var k := roundi(3.0 * u)
		_bg.corner_radius_top_left = k
		_bg.corner_radius_top_right = k
		var top := Color(0.086, 0.083, 0.079).lerp(Color(0.100, 0.096, 0.090), hover)
		var bot := Color(0.047, 0.045, 0.043).lerp(Color(0.056, 0.053, 0.050), hover)
		_bg.bg_color = top
		draw_style_box(_bg, Rect2(Vector2.ZERO, s))
		_quad(Vector2(0.0, float(k)), Vector2(s.x, float(k)), Vector2(s.x, s.y), Vector2(0.0, s.y), top, bot)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
		var w := s.x / u
		var h := s.y / u
		var dim := 0.86 + 0.14 * hover
		match mode:
			"orbit":
				_orbit(w, h, dim)
			"rally":
				_rally(w, h, dim)
			"dirigent":
				_dirigent(w, h, dim)
			"trace":
				_trace(w, h, dim)
			"rebound":
				_rebound(w, h, dim)
			_:
				_mania(w, h, dim)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var hair := maxf(roundf(u), 1.0)
		draw_rect(Rect2(0.0, s.y - hair, s.x, hair), Color(INK, 0.10), true)

	# Mania: Bahn in Perspektive, vier Spuren, fallende Noten, Tasten-Licht, Trefferlinie.
	func _mania(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		var y0 := -2.0
		var ly := h - 15.0
		var x_at := func(l: float, y: float) -> float:
			return cx + (l - 2.0) * lerpf(16.0, 37.0, (y - y0) / (h - y0))
		_quad(Vector2(x_at.call(0.0, y0), y0), Vector2(x_at.call(4.0, y0), y0),
			Vector2(x_at.call(4.0, h), h), Vector2(x_at.call(0.0, h), h),
			Color(0.060, 0.058, 0.056, 1.0), Color(0.150, 0.143, 0.132, 1.0))
		var lane_col := [INK, col, col, INK]
		var notes := [[0, 0.02], [2, 0.14], [1, 0.27], [3, 0.40], [1, 0.52], [0, 0.64], [2, 0.77], [3, 0.90]]
		var ys := []
		var press := [0.0, 0.0, 0.0, 0.0]
		for n in notes:
			var t := fposmod(float(n[1]) + ph, 1.0)
			var y := y0 + t * t * (h - y0 + 8.0) * 0.98 + t * 4.0
			ys.append(y)
			var l := int(n[0])
			press[l] = maxf(press[l], clampf(1.0 - absf(y - ly - 3.0) / 11.0, 0.0, 1.0))
		# Tasten-Licht: Saeule ueber der gedrueckten Spur.
		for l in 4:
			if press[l] > 0.01:
				var c: Color = lane_col[l]
				var yt := ly - 40.0
				_quad(Vector2(x_at.call(float(l), yt), yt), Vector2(x_at.call(float(l) + 1.0, yt), yt),
					Vector2(x_at.call(float(l) + 1.0, ly), ly), Vector2(x_at.call(float(l), ly), ly),
					Color(c, 0.0), Color(c, 0.30 * press[l] * a))
		for l in range(1, 4):
			draw_line(Vector2(x_at.call(float(l), y0), y0), Vector2(x_at.call(float(l), h), h), Color(INK, 0.11), 1.0, true)
		for l in [0.0, 4.0]:
			draw_line(Vector2(x_at.call(l, y0), y0), Vector2(x_at.call(l, h), h), Color(INK, 0.50 * a), 1.4, true)
		for i in notes.size():
			var n: Array = notes[i]
			var y: float = ys[i]
			var t := fposmod(float(n[1]) + ph, 1.0)
			var sc := lerpf(0.42, 1.0, clampf((y - y0) / (h - y0), 0.0, 1.0))
			var nh := 8.0 * sc
			var l := float(n[0])
			var g := 2.4 * sc
			var al := clampf(t * 9.0, 0.0, 1.0) * clampf((ly + 9.0 - y) / 7.0, 0.0, 1.0)
			if al <= 0.01:
				continue
			var c: Color = lane_col[int(n[0])]
			var tl := Vector2(x_at.call(l, y - nh) + g, y - nh)
			var tr := Vector2(x_at.call(l + 1.0, y - nh) - g, y - nh)
			var br := Vector2(x_at.call(l + 1.0, y) - g, y)
			var bl := Vector2(x_at.call(l, y) + g, y)
			draw_colored_polygon(PackedVector2Array([tl + Vector2(-0.8, 1.6), tr + Vector2(0.8, 1.6), br + Vector2(0.8, 2.2), bl + Vector2(-0.8, 2.2)]), Color(0, 0, 0, 0.45 * al))
			_quad(tl, tr, br, bl, Color(c.lightened(0.10), al), Color(c.darkened(0.30), al))
			draw_line(tl, tr, Color(c.lightened(0.55), al), 1.0, true)
		# Tasten unter der Trefferlinie.
		for l in 4:
			var c: Color = lane_col[l]
			var g := 1.6
			var k0 := Color(0.105, 0.100, 0.094, 1.0).lerp(Color(c.darkened(0.35), 1.0), press[l] * 0.8)
			_quad(Vector2(x_at.call(float(l), ly) + g, ly + 2.5), Vector2(x_at.call(float(l) + 1.0, ly) - g, ly + 2.5),
				Vector2(x_at.call(float(l) + 1.0, h) - g, h), Vector2(x_at.call(float(l), h) + g, h),
				k0, k0.darkened(0.35))
		draw_line(Vector2(x_at.call(0.0, ly), ly), Vector2(x_at.call(4.0, ly), ly), Color(DARK, 0.8), 5.0, true)
		draw_line(Vector2(x_at.call(0.0, ly), ly), Vector2(x_at.call(4.0, ly), ly), Color(AMBER, a), 2.4, true)

	# Orbit: Zielfeld mit Scheiben, Zieh-Bahnen, Quadrat mit Anflugring, geteilter
	# Scheibe (zwei Tasten) und Zeiger.
	func _orbit(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		for gx in 9:
			for gy in 3:
				var q := Vector2(cx - 112.0 + 28.0 * float(gx), 13.0 + 28.0 * float(gy))
				draw_line(q - Vector2(2, 0), q + Vector2(2, 0), Color(INK, 0.09), 1.0)
				draw_line(q - Vector2(0, 2), q + Vector2(0, 2), Color(INK, 0.09), 1.0)
		# Blaue Zieh-Bahn mit Kopf, zweite Scheibe.
		var b0 := Vector2(cx - 64.0, 27.0)
		var b1 := Vector2(cx - 20.0, 19.0)
		_capsule(b0, b1, 9.5, Color(BLUE.darkened(0.72), 1.0), Color(BLUE.darkened(0.38), a))
		draw_arc(b1, 5.6, 0.0, TAU, 32, Color(BLUE.darkened(0.15), a), 1.6, true)
		_disc(Vector2(cx - 80.0, 57.0), 12.5, BLUE, a)
		_disc(b0, 13.5, BLUE, a)
		# Bernstein-Quadrat mit Anflugring.
		var sq := Vector2(cx - 36.0, 54.0)
		draw_arc(sq, 17.5, 0.0, TAU, 48, Color(INK, 0.30 * a), 1.3, true)
		draw_line(sq + Vector2(0, -20.5), sq + Vector2(0, -15.0), Color(INK, 0.65 * a), 1.8, true)
		_rrect(Rect2(sq - Vector2(11, 11) + Vector2(0, 1.6), Vector2(22, 22)), 5.0, Color(0, 0, 0, 0.4), Color(0, 0, 0, 0.0), 0)
		_rrect(Rect2(sq - Vector2(11, 11), Vector2(22, 22)), 5.0, Color(AMBER.darkened(0.52), 1.0), Color(AMBER.lightened(0.12), a), 2)
		_rrect(Rect2(sq - Vector2(8, 8), Vector2(16, 9)), 3.0, Color(AMBER, 0.14), Color(0, 0, 0, 0.0), 0)
		# Bernstein-Zieh-Bahn rechts mit Folgering.
		var s0 := Vector2(cx + 50.0, 43.0)
		var s1 := Vector2(cx + 88.0, 62.0)
		_capsule(s0, s1, 9.5, Color(AMBER.darkened(0.68), 1.0), Color(AMBER.darkened(0.28), a))
		draw_arc(s1, 5.6, 0.0, TAU, 32, Color(AMBER.darkened(0.10), a), 1.6, true)
		draw_arc(s0, 23.0, 0.0, TAU, 64, Color(INK, 0.26 * a), 1.3, true)
		draw_arc(s0, 23.0, -PI * 0.5, -PI * 0.5 + TAU * (0.12 + 0.5 * ph), 40, Color(INK, 0.92 * a), 2.2, true)
		draw_circle(s0 + Vector2(0, 1.6), 11.4, Color(0, 0, 0, 0.4), true, -1.0, true)
		draw_circle(s0, 10.6, Color(INK, 1.0), true, -1.0, true)
		draw_circle(s0, 8.3, Color(AMBER.darkened(0.14), 1.0), true, -1.0, true)
		draw_circle(s0 + Vector2(0, -1.4), 6.2, Color(AMBER.lightened(0.06), 1.0), true, -1.0, true)
		draw_circle(s0, 2.3, Color(INK, 1.0), true, -1.0, true)
		# Geteilte Scheibe (zwei Tasten zugleich) mit schrumpfendem Anflugring.
		var sp := Vector2(cx + 4.0, 51.0)
		draw_circle(sp + Vector2(0, 1.8), 15.6, Color(0, 0, 0, 0.42), true, -1.0, true)
		_half(sp, 12.6, PI * 0.5, Color(BLUE.darkened(0.05), 1.0))
		_half(sp, 12.6, -PI * 0.5, Color(AMBER.darkened(0.20), 1.0))
		draw_arc(sp, 14.4, 0.0, TAU, 48, Color(INK, 1.0), 2.0, true)
		draw_arc(sp, 14.4 + 11.0 * (1.0 - ph), 0.0, TAU, 48, Color(INK, (0.20 + 0.6 * ph) * a), 1.3, true)
		# Zeiger auf dem Weg vom Quadrat zur Scheibe.
		var e := ph * ph * (3.0 - 2.0 * ph)
		var cur := (sq + Vector2(6, -4)).lerp(sp + Vector2(-13.5, 5.5), e)
		_dot(cur, 3.8, Color(1, 1, 1, 1), Color(1, 1, 1, 0.0))

	# Rally: Tisch in Perspektive mit Netz, drei Baelle im Flug mit Schatten, Schlaeger.
	func _rally(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		var yt := 21.0
		var yb := h + 8.0
		var hw := func(y: float) -> float:
			return lerpf(47.0, 106.0, (y - yt) / (yb - yt))
		var lx := func(l: float, y: float) -> float:
			return cx + (l - 2.0) * hw.call(y) * 0.5
		_quad(Vector2(lx.call(0.0, yt), yt), Vector2(lx.call(4.0, yt), yt), Vector2(lx.call(4.0, yb), yb), Vector2(lx.call(0.0, yb), yb),
			Color(0.105, 0.140, 0.185, 1.0), Color(0.190, 0.240, 0.305, 1.0))
		var tint := [BLUE, TEAL, Color(0.86, 0.74, 0.46), ORANGE]
		for l in [1, 2]:
			var c: Color = tint[l]
			_quad(Vector2(lx.call(float(l), yt), yt), Vector2(lx.call(float(l) + 1.0, yt), yt),
				Vector2(lx.call(float(l) + 1.0, yb), yb), Vector2(lx.call(float(l), yb), yb), Color(c, 0.02), Color(c, 0.13))
		for l in [1.0, 3.0]:
			draw_line(Vector2(lx.call(l, yt), yt), Vector2(lx.call(l, yb), yb), Color(INK, 0.13), 1.0, true)
		draw_line(Vector2(cx, yt), Vector2(cx, yb), Color(INK, 0.40 * a), 1.2, true)
		draw_polyline(PackedVector2Array([Vector2(lx.call(0.0, yb), yb), Vector2(lx.call(0.0, yt), yt), Vector2(lx.call(4.0, yt), yt), Vector2(lx.call(4.0, yb), yb)]),
			Color(INK, 0.85 * a), 1.5, true)
		# Zielringe an der vorderen Kante.
		for l in 4:
			var c: Color = tint[l]
			_ring(Vector2(lx.call(float(l) + 0.5, 73.0), 73.0), 10.0, 4.0, Color(c, 0.50 * a), 1.1)
		var yn := 46.0
		var balls := [[1.5, TEAL, 0.0], [2.5, Color(0.94, 0.92, 0.88), 0.36], [3.5, ORANGE, 0.70]]
		var draw_ball := func(b: Array, far: bool) -> void:
			var t := fposmod(float(b[2]) + ph, 1.0)
			var gy := lerpf(25.0, 75.0, t)
			if (gy < yn) != far:
				return
			var gx: float = lx.call(float(b[0]), gy)
			var hop := 24.0 * sin(PI * t / 0.6) if t < 0.6 else 12.0 * sin(PI * (t - 0.6) / 0.4)
			var r := lerpf(3.0, 6.6, t)
			var al := clampf(t * 8.0, 0.0, 1.0) * clampf((1.0 - t) * 8.0, 0.0, 1.0)
			_shadow(Vector2(gx, gy), r * 1.15, r * 0.40, 0.36 * al)
			_ball(Vector2(gx, gy - r - hop), r, b[1], al)
		for b in balls:
			draw_ball.call(b, true)
		# Netz: Gewebe, helle Oberkante, Pfosten.
		var nx0: float = lx.call(0.0, yn) - 4.0
		var nx1: float = lx.call(4.0, yn) + 4.0
		draw_rect(Rect2(nx0, yn - 10.0, nx1 - nx0, 10.0), Color(0.78, 0.84, 0.90, 0.13), true)
		var x := nx0 + 4.0
		while x < nx1:
			draw_line(Vector2(x, yn - 10.0), Vector2(x, yn), Color(INK, 0.10), 1.0)
			x += 4.0
		draw_line(Vector2(nx0, yn - 5.0), Vector2(nx1, yn - 5.0), Color(INK, 0.10), 1.0)
		draw_line(Vector2(nx0, yn - 10.0), Vector2(nx1, yn - 10.0), Color(INK, 0.92 * a), 1.8, true)
		draw_line(Vector2(nx0, yn - 11.5), Vector2(nx0, yn + 1.5), Color(INK, 0.75 * a), 2.0, true)
		draw_line(Vector2(nx1, yn - 11.5), Vector2(nx1, yn + 1.5), Color(INK, 0.75 * a), 2.0, true)
		# Schlaeger hinter dem weissen Ball.
		var pp := Vector2(lx.call(2.5, 70.0) - 3.0, 62.0)
		draw_line(pp + Vector2(-2.0, 9.0), pp + Vector2(-5.0, 24.0), Color(DARK, 1.0), 7.5, true)
		draw_line(pp + Vector2(-2.0, 9.0), pp + Vector2(-5.0, 24.0), Color(0.62, 0.46, 0.28, 1.0), 5.0, true)
		draw_circle(pp + Vector2(0, 1.6), 12.2, Color(0, 0, 0, 0.4), true, -1.0, true)
		draw_circle(pp, 11.6, Color(0.86, 0.80, 0.68, 1.0), true, -1.0, true)
		draw_circle(pp, 9.8, Color(0.170, 0.150, 0.130, 1.0), true, -1.0, true)
		draw_circle(pp + Vector2(0, -1.5), 7.6, Color(0.215, 0.190, 0.165, 1.0), true, -1.0, true)
		for b in balls:
			draw_ball.call(b, false)

	# Dirigent: runde Buehne mit Takt-Uhr, Schlagpunkte mit Ziffern, Taktstock auf dem
	# Weg zum naechsten Schlag; darunter die Einsatz-Leiste (Kreis/Raute je Taste).
	func _dirigent(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		var c := Vector2(cx, 30.0)
		var rad := 43.0
		draw_circle(c + Vector2(0, 2.0), rad + 2.0, Color(0, 0, 0, 0.36), true, -1.0, true)
		draw_circle(c, rad, Color(0.100, 0.096, 0.090, 1.0), true, -1.0, true)
		draw_circle(c + Vector2(0, -2.0), rad * 0.90, Color(0.128, 0.123, 0.115, 1.0), true, -1.0, true)
		draw_arc(c, rad * 0.62, 0.0, TAU, 64, Color(INK, 0.06), 1.0, true)
		draw_arc(c, rad, 0.0, TAU, 72, Color(INK, 0.30 * a), 1.2, true)
		var a1 := -PI * 0.5 + TAU * (0.16 + 0.25 * ph)
		draw_arc(c, rad + 3.6, -PI * 0.5, a1, 40, Color(AMBER, a), 1.8, true)
		draw_line(c + Vector2(0, -rad - 6.2), c + Vector2(0, -rad - 1.0), Color(AMBER, a), 1.6, true)
		draw_circle(c + Vector2(cos(a1), sin(a1)) * (rad + 3.6), 2.3, Color(AMBER, 1.0), true, -1.0, true)
		var p := [c + Vector2(0, 23), c + Vector2(-28, 3), c + Vector2(28, 3), c + Vector2(0, -19)]
		var curve := func(i0: int, i1: int, t: float) -> Vector2:
			var m: Vector2 = (p[i0] + p[i1]) * 0.5
			var ctl: Vector2 = m + (c + Vector2(0, 14) - m) * 0.9
			return (p[i0] as Vector2).lerp(ctl, t).lerp(ctl.lerp(p[i1], t), t)
		for sgm in [[0, 1], [1, 2], [2, 3]]:
			var pts := PackedVector2Array()
			for i in 13:
				pts.append(curve.call(sgm[0], sgm[1], float(i) / 12.0))
			draw_polyline(pts, Color(INK, 0.24 * a), 1.2, true)
		draw_circle(p[0], 3.0, Color(INK, 0.42 * a), true, -1.0, true)
		# Schlag 2 gerade getroffen: Bernstein-Scheibe mit auslaufendem Ring.
		draw_arc(p[1], 7.4 + 8.0 * ph, 0.0, TAU, 40, Color(AMBER, 0.75 * (1.0 - ph) * a), 1.3, true)
		draw_circle(p[1], 7.0, Color(AMBER.darkened(0.48), 1.0), true, -1.0, true)
		draw_arc(p[1], 6.5, 0.0, TAU, 40, Color(AMBER, a), 1.5, true)
		# Schlag 4 wartet, Schlag 3 ist das Ziel (gross, Anflugring).
		draw_circle(p[3], 6.8, Color(0.185, 0.178, 0.167, 1.0), true, -1.0, true)
		draw_arc(p[3], 6.3, 0.0, TAU, 40, Color(INK, 0.50 * a), 1.2, true)
		_num(p[3], "4", 8.5, Color(INK, 0.70 * a))
		draw_arc(p[2], 10.6 + 9.0 * (1.0 - ph), 0.0, TAU, 40, Color(INK, (0.18 + 0.5 * ph) * a), 1.2, true)
		draw_circle(p[2] + Vector2(0, 1.8), 11.2, Color(0, 0, 0, 0.4), true, -1.0, true)
		draw_circle(p[2], 10.6, Color(0.215, 0.206, 0.193, 1.0), true, -1.0, true)
		draw_arc(p[2], 9.9, 0.0, TAU, 48, Color(INK, a), 1.7, true)
		_num(p[2], "3", 12.0, Color(INK, a))
		# Taktstock.
		var e := ph * ph * (3.0 - 2.0 * ph)
		var tr_pts := PackedVector2Array()
		var tr_cols := PackedColorArray()
		for i in 13:
			var f := float(i) / 12.0
			tr_pts.append(curve.call(1, 2, e * f))
			tr_cols.append(Color(AMBER.lightened(0.2), 0.85 * f * a))
		if e > 0.03:
			draw_polyline_colors(tr_pts, tr_cols, 2.2, true)
		var hp: Vector2 = curve.call(1, 2, e)
		draw_line(hp + Vector2(9, 12), hp, Color(DARK, 0.8), 4.4, true)
		draw_line(hp + Vector2(9, 12), hp, Color(INK, 0.95), 2.0, true)
		draw_circle(hp + Vector2(9, 12), 2.5, AMBER, true, -1.0, true)
		_dot(hp, 3.6, Color(1.0, 0.97, 0.9, 1.0), Color(1, 1, 1, 0.0))
		# Einsatz-Leiste.
		var ly := 72.5
		var x0 := cx - 94.0
		var x1 := cx + 94.0
		_rrect(Rect2(x0, ly - 7.5 + 1.5, x1 - x0, 15.0), 5.0, Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.0), 0)
		_rrect(Rect2(x0, ly - 7.5, x1 - x0, 15.0), 5.0, Color(0.088, 0.085, 0.080, 1.0), Color(INK, 0.16), 1)
		var jx := x0 + 17.0
		for i in 14:
			var x := jx + (float(i) + 1.0 - 2.0 * ph) * 15.0
			if x < jx - 0.5 or x > x1 - 7.0:
				continue
			var al := clampf((x1 - 7.0 - x) / 12.0, 0.0, 1.0)
			var q := Vector2(x, ly)
			if i % 2 == 0:
				draw_circle(q, 5.0, Color(DARK, al), true, -1.0, true)
				draw_circle(q, 4.2, Color(AMBER.darkened(0.22), al), true, -1.0, true)
				draw_circle(q + Vector2(0, -0.8), 3.0, Color(AMBER.lightened(0.08), al), true, -1.0, true)
			else:
				var d := 4.8
				_poly(PackedVector2Array([q + Vector2(0, -d), q + Vector2(d, 0), q + Vector2(0, d), q + Vector2(-d, 0)]),
					Color(BLUE.lightened(0.05), al), Color(BLUE.lightened(0.45), al), 1.0)
		var kk := fposmod(ph * 2.0, 1.0)
		draw_arc(Vector2(jx, ly), 6.2 + 3.2 * kk, 0.0, TAU, 40, Color(AMBER, 0.8 * (1.0 - kk) * a), 1.2, true)
		draw_arc(Vector2(jx, ly), 5.8, 0.0, TAU, 40, Color(INK, 0.95 * a), 1.5, true)

	# Trace: farbiges Band je Richtung, Richtungspfeile ueber den Abschnitten, Kopf
	# mit Bernstein-Spur.
	func _trace(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		var seg_col := [Color(0.96, 0.76, 0.36), Color(0.36, 0.80, 0.95), Color(0.56, 0.93, 0.70), Color(0.95, 0.44, 0.80)]
		var seg_dir := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
		var n := 72
		var pts := PackedVector2Array()
		for i in n + 1:
			var f := float(i) / float(n)
			pts.append(Vector2(cx - 98.0 + 196.0 * f, 53.0 + 14.0 * sin(f * 7.2 + 0.4) + 4.0 * sin(f * 14.0)))
		var g := (0.06 + 0.86 * ph) * float(n)
		var hi := clampi(int(g), 1, n - 2)
		var head := pts[hi].lerp(pts[hi + 1], clampf(g - float(hi), 0.0, 1.0))
		var parts := []
		for s4 in 4:
			var i0 := maxi(s4 * n / 4, hi + 1)
			var i1 := (s4 + 1) * n / 4
			if i1 - i0 < 1:
				parts.append(PackedVector2Array())
				continue
			var part := pts.slice(i0, i1 + 1)
			if i0 == hi + 1:
				part.insert(0, head)
			parts.append(part)
		for part: PackedVector2Array in parts:
			if part.size() > 1:
				draw_polyline(part, Color(DARK, 0.95), 9.4, true)
		for s4 in 4:
			var part: PackedVector2Array = parts[s4]
			if part.size() < 2:
				continue
			var c: Color = seg_col[s4]
			draw_polyline(part, Color(c.darkened(0.30), a), 6.4, true)
			draw_polyline(part, Color(c, a), 4.0, true)
			draw_polyline(part, Color(c.lightened(0.45), 0.55 * a), 1.2, true)
		# Abschnittsgrenzen: Querstrich, darueber der Richtungspfeil.
		for s4 in range(1, 4):
			var i := s4 * n / 4
			if i <= hi:
				continue
			var c: Color = seg_col[s4]
			var q := pts[i]
			var tan := (pts[i + 1] - pts[i - 1]).normalized()
			var nrm := Vector2(-tan.y, tan.x)
			draw_line(q - nrm * 7.5, q + nrm * 7.5, Color(DARK, 0.9), 4.0, true)
			draw_line(q - nrm * 7.0, q + nrm * 7.0, Color(c.lightened(0.35), a), 1.8, true)
			var ap := q + Vector2(0.0, -19.0 if q.y > 34.0 else 19.0)
			var d: Vector2 = seg_dir[s4]
			var sd := Vector2(-d.y, d.x)
			var arrow := PackedVector2Array([ap + d * 7.5, ap - d * 5.5 + sd * 6.6, ap - d * 2.0, ap - d * 5.5 - sd * 6.6])
			var out := PackedVector2Array()
			for v in arrow:
				out.append(ap + (v - ap) * 1.28)
			draw_colored_polygon(out, Color(DARK, 0.95))
			_poly(arrow, Color(c.darkened(0.05), a), Color(c.lightened(0.45), a), 1.0)
		# Gespielter Weg und Kopf.
		var done := pts.slice(0, hi + 1)
		done.append(head)
		draw_polyline(done, Color(DARK, 0.9), 4.6, true)
		draw_polyline(done, Color(AMBER, 0.9 * a), 2.2, true)
		draw_circle(head, 9.6, Color(INK, 0.12), true, -1.0, true)
		draw_arc(head, 9.6, 0.0, TAU, 40, Color(INK, 0.38 * a), 1.0, true)
		_dot(head, 4.4, Color(1, 1, 1, 1), Color(1, 1, 1, 0.0))

	# Rebound: vier Trommeln mit Chromrand auf dem Pult, Kugeln springen im Takt,
	# Schatten und Aufschlag-Ring auf dem Fell.
	func _rebound(w: float, h: float, a: float) -> void:
		var cx := w * 0.5
		for i in 4:
			var px := cx + (float(i) - 1.5) * 50.0
			draw_rect(Rect2(px - 20.0, 5.0, 40.0, 44.0), Color(INK, 0.022), true)
			draw_rect(Rect2(px - 20.0, 5.0, 40.0, 44.0), Color(INK, 0.055), false, 1.0)
		_quad(Vector2(cx - 106.0, 46.0), Vector2(cx + 106.0, 46.0), Vector2(cx + 112.0, h + 2.0), Vector2(cx - 112.0, h + 2.0),
			Color(0.140, 0.135, 0.127, 1.0), Color(0.066, 0.063, 0.060, 1.0))
		draw_line(Vector2(cx - 106.0, 46.0), Vector2(cx + 106.0, 46.0), Color(INK, 0.24), 1.2, true)
		var ball_col := [Color(0.27, 0.53, 0.95), Color(0.74, 0.85, 0.97), Color(0.74, 0.85, 0.97), Color(0.27, 0.53, 0.95)]
		var offs := [0.0, 0.55, 0.25, 0.80]
		var high := [30.0, 24.0, 33.0, 20.0]
		var chrome := Color(0.80, 0.82, 0.85, 1.0)
		for i in 4:
			var p := Vector2(cx + (float(i) - 1.5) * 50.0, 58.0)
			var c: Color = ball_col[i]
			var t := fposmod(ph * 2.0 + float(offs[i]), 1.0)
			var up := sin(PI * t)
			_shadow(p + Vector2(0, 9.0), 22.0, 5.0, 0.30)
			draw_colored_polygon(_ellipse(p + Vector2(0, 6.5), 21.0, 6.0), Color(0.050, 0.050, 0.053, 1.0))
			draw_rect(Rect2(p.x - 21.0, p.y, 42.0, 6.5), Color(0.050, 0.050, 0.053, 1.0), true)
			for k in 5:
				var bx := p.x - 16.0 + 8.0 * float(k)
				var by := p.y + 5.6 - 0.9 * absf(float(k) - 2.0)
				draw_line(Vector2(bx, by), Vector2(bx, by + 4.0), Color(chrome, 0.55), 1.2)
			_ring(p + Vector2(0, 5.0), 21.0, 6.0, Color(c, 0.40 * a), 1.0)
			draw_colored_polygon(_ellipse(p, 21.0, 6.0), chrome.darkened(0.25))
			draw_colored_polygon(_ellipse(p + Vector2(0, -0.6), 20.6, 5.6), chrome)
			draw_colored_polygon(_ellipse(p, 19.0, 4.8), Color(0.120, 0.120, 0.126, 1.0))
			_ring(p, 13.5, 3.3, Color(c, 0.32 * a), 1.0)
			if t < 0.4:
				var e := t / 0.4
				_ring(p, 5.0 + 12.0 * e, 1.3 + 3.0 * e, Color(c.lightened(0.3), (1.0 - e) * a), 1.4)
			_shadow(p, 7.5 * (1.0 - 0.45 * up), 2.0 * (1.0 - 0.45 * up), 0.55 * (1.0 - 0.55 * up))
			_ball(p + Vector2(0.0, -8.0 - float(high[i]) * up), 8.4, c)


## Logo-Buehne: Wortmarke als Textur, der Bernstein-Punkt der Spur-Marke atmet
## im Takt (kleiner Radius-Puls, kein Blitz).
class LogoStage extends Control:
	var tex: Texture2D
	var dot := Vector2.ZERO
	var dot_r := 0.0
	var env := 0.0

	func set_env(v: float) -> void:
		if absf(v - env) > 0.004:
			env = v
			queue_redraw()

	func _draw() -> void:
		if tex != null:
			draw_texture(tex, Vector2.ZERO)
		if env > 0.01 and dot_r > 0.0:
			var a := UiTheme.ACCENT
			draw_circle(dot, dot_r * (1.0 + 0.16 * env), a, true, -1.0, true)


func _ready() -> void:
	var t_ready := Time.get_ticks_usec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Hintergrund: geblurrtes Cover der zuletzt gespielten Map. Noch nie
	# gespielt: ruhiger Shader-Hintergrund in Graphit/Bernstein.
	if not _build_blur_bg():
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/menu_bg.gdshader")
		mat.set_shader_parameter("base_color", Vector3(0.42, 0.29, 0.12))
		bg.material = mat
		_bg_mat = mat
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_rebuild_ui()
	resized.connect(func(): _dirty = true)
	Updater.state_changed.connect(func(text, _ratio):
		_upd_text = str(text)
		if is_instance_valid(_upd_label):
			_upd_label.text = _upd_text)
	if DisplayServer.get_name() != "headless":
		_begin_menu_music()
		_begin_shader_warmup()
	_play_intro()

	if GpuGuard.take_notice():
		_show_gpu_notice()
	GameSession.perf_since("Hauptmenue: _ready gesamt", t_ready)

	var args := OS.get_cmdline_args()
	if DisplayServer.get_name() == "headless":
		print("=== MainMenu Headless OK (pp=%.1f, plays=%d) ===" % [
			ScoreStore.profile_pp(), ScoreStore.total_plays()])
		get_tree().quit(0)
	elif args.has("--shot-menu"):
		# Harness: --shot-focus zeigt Tastatur-Fokus, --shot-tour die Menue-Tour.
		if args.has("--shot-focus") and _btn_orbit != null:
			_btn_orbit.grab_focus()
		if args.has("--shot-tour"):
			_start_tour.call_deferred()
		_capture()
	elif args.has("--shot-profile"):
		# Harness: Profil-Ansicht oeffnen und abfotografieren.
		add_child(ProfilePanel.new())
		_capture()
	elif args.has("--shot-settings"):
		add_child(SettingsPanel.new())
		_capture()
	elif args.has("--shot-login"):
		# Harness: Login-Dialog (Spielstart) erzwingen und abfotografieren.
		_open_login_dialog()
		_capture()
	elif GameSession.perf_enabled:
		# Lade-Messung: 1 s Menue zeigen, dann in den Song-Browser.
		await get_tree().create_timer(1.0).timeout
		GameSession.perf_request("Hauptmenue -> Song-Browser")
		_play()
	elif args.has("--autoplay"):
		# Test-Durchreiche in den Song-Browser.
		_play.call_deferred()
	elif LoginDialog.should_show(GameSession.online, args, false):
		# Nicht angemeldet: einmal pro Spielstart ruhig nach dem Login fragen.
		await get_tree().create_timer(0.6).timeout
		if is_inside_tree():
			_open_login_dialog()
	elif LoginDialog.should_resume_backfill(GameSession.online, args, false):
		# Angemeldet, Upload alter Scores steht noch aus (neue Merker-Version): nachholen.
		await get_tree().create_timer(2.0).timeout
		LoginDialog.after_login(GameSession.online, LoginDialog.scan_osz_files())


## Bass-Pegel und Beat-Puls; ruhig ohne Musik.
func _process(delta: float) -> void:
	_shader_warmup_step()
	if _dirty:
		_dirty = false
		if _view() != _built_for:
			_rebuild_ui()
	if _music_wait != "" and OszImporter.is_prepared(_music_wait):
		_music_wait = ""
		var t_music := Time.get_ticks_usec()
		_start_menu_music()
		GameSession.perf_since("Hauptmenue: Musik + Cover starten (Hauptthread)", t_music)
		GameSession.perf_since("Hauptmenue: Musik hoerbar (seit _ready)", _music_wait_t)
	var playing := _music != null and is_instance_valid(_music) and _music.playing
	var raw: float = SyncClock.band_energy(30.0, 120.0) if playing else 0.0
	_bass_avg = lerpf(_bass_avg, raw, clampf(delta * 1.5, 0.0, 1.0))
	_bass_smooth = lerpf(_bass_smooth, raw, clampf(delta * 8.0, 0.0, 1.0))
	var onset: float = raw - _bass_avg
	if onset > 0.08 and raw > 0.35:
		_kick = maxf(_kick, clampf(onset * 4.0, 0.0, 1.0))
	_kick = maxf(_kick - delta * 3.5, 0.0)
	var bass_lvl: float = clampf((_bass_smooth - 0.3) * 1.5, 0.0, 1.0) if playing else 0.0
	_kb_t += delta
	if _bg_rect != null:
		var z: float = 1.04 + 0.03 * sin(_kb_t * TAU / 40.0)
		_bg_rect.scale = Vector2.ONE * z
		_bg_rect.position = Vector2(sin(_kb_t * TAU / 55.0), cos(_kb_t * TAU / 70.0)) * 8.0
	if is_instance_valid(_np_progress) and playing and _music.stream != null:
		var len_s: float = maxf(_music.stream.get_length(), 1.0)
		var frac: float = clampf(_music.get_playback_position() / len_s, 0.0, 1.0)
		_np_progress.size.x = roundf(_np_track.size.x * frac)
	if is_instance_valid(_np_title) and is_instance_valid(_np_clip):
		var over: float = _np_title.get_minimum_size().x - _np_clip.size.x
		if over > 1.0:
			_np_t += delta
			var travel: float = over / (32.0 * _u)
			var pause := 1.6
			var cyc: float = 2.0 * (travel + pause)
			var t: float = fposmod(_np_t, cyc)
			var k: float
			if t < pause:
				k = 0.0
			elif t < pause + travel:
				k = (t - pause) / travel
			elif t < 2.0 * pause + travel:
				k = 1.0
			else:
				k = 1.0 - (t - 2.0 * pause - travel) / travel
			_np_title.position.x = roundf(-over * k)
		else:
			_np_title.position.x = 0.0
	# Ein Puls fuer alles: exakt auf dem Beat (BeatClock). Ohne Taktdaten bleibt
	# der Bass-Onset als Ersatz.
	var pulse_k: float = _kick
	if _beat_clock != null and playing and _beat_clock.bpm > 0.0:
		# Position + Mix-Offset - Ausgabe-Latenz.
		var t_ms: float = _music.get_playback_position() * 1000.0 + AudioServer.get_time_since_last_mix() * 1000.0 - AudioServer.get_output_latency() * 1000.0
		_beat_clock.update(t_ms, delta)
		pulse_k = _beat_clock.beat_env
	_pulse = pulse_k
	if is_instance_valid(_logo_stage):
		_logo_stage.set_env(_pulse)
	if is_instance_valid(_viz):
		_viz.modulate.a = 0.75 + 0.25 * _pulse
	if _bg_mat != null:
		_bg_mat.set_shader_parameter("bass", bass_lvl)
		_bg_mat.set_shader_parameter("kick", _pulse)
	if _dim_overlay != null:
		_dim_overlay.color.a = 0.72 - 0.03 * bass_lvl - 0.03 * _pulse
	# Marke am aktiven Eintrag atmet im Takt (nur Deckkraft, nichts bewegt sich).
	for m in _markers:
		if m.visible:
			m.color.a = 0.82 + 0.18 * _pulse


func _add_blur_layers(tex: Texture2D) -> void:
	# Cover als ruhige Farbstimmung: sehr weich (kein erkennbares Motiv), entsaettigt,
	# abgedunkelt, mit Vignette und feinem Korn (MapBackdrop). Steht still.
	var bg := MapBackdrop.create(tex, 0.30, 100)
	bg.set_calm(1.6, 0.6, 0.72, 0.24, 100)
	add_child(bg)


# --- Masse -----------------------------------------------------------------

func _view() -> Vector2:
	return size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size


## Entwurfs-Einheiten -> ganze Pixel.
func _px(v: float) -> float:
	return roundf(v * _u)


func _fs(v: float) -> int:
	return maxi(roundi(v * _u), 8)


## Rechteck in Entwurfs-Einheiten setzen; beide Kanten einzeln gerundet, damit
## Nachbarn ohne Luecke und ohne halbe Pixel aneinander liegen.
func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	var p := Vector2(roundf(x * _u), roundf(y * _u))
	c.position = p
	c.size = Vector2(roundf((x + w) * _u) - p.x, roundf((y + h) * _u) - p.y)


func _label(text: String, fs: float, col: Color, heading: bool = false) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", _head_font if heading else _body_font)
	l.add_theme_font_size_override("font_size", _fs(fs))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flat(bg: Color, radius: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(roundi(radius * _u))
	sb.anti_aliasing = radius > 0.0
	return sb


func _outline(col: Color, radius: float, width: float = 2.0, expand: float = 0.0) -> StyleBoxFlat:
	var sb := _flat(Color(0, 0, 0, 0), radius)
	sb.draw_center = false
	sb.set_border_width_all(maxi(roundi(width * _u), 1))
	sb.border_color = col
	sb.set_expand_margin_all(_px(expand))
	return sb


## SVG in genau der Zielbreite rastern (1 Texel = 1 Pixel), einmal je Groesse.
static func _svg_tex(key: String, svg: String, scale: float) -> Texture2D:
	var k := "%s@%.4f" % [key, scale]
	if _tex_cache.has(k):
		return _tex_cache[k]
	var tex: Texture2D = null
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) == OK:
		tex = ImageTexture.create_from_image(img)
	_tex_cache[k] = tex
	return tex


func _mode_icon(mode: String, px: float) -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % str(MODE_SVG.get(mode, MODE_SVG.mania))
	return _svg_tex("mode_" + mode, svg, px / 24.0)


# --- Aufbau ----------------------------------------------------------------

## Baut die ganze Bedien-Ebene neu (Start, Fenstergroesse, Sprachwechsel).
func _rebuild_ui() -> void:
	if _ui == null:
		return
	var keep_focus := ""
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo != null and _ui.is_ancestor_of(fo):
		keep_focus = str(fo.name)
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
		_tour_step = -1
	for c in _ui.get_children():
		_ui.remove_child(c)
		c.queue_free()
	_btns.clear()
	_markers.clear()
	_mode_subs.clear()
	_intro.clear()
	_np_bar = null
	_np_progress = null
	_np_track = null
	_np_title = null
	_np_clip = null
	_viz = null
	_btn_daily = null
	_daily_detail = null
	var v := _view()
	_built_for = v
	_u = clampf(minf(v.x / 1280.0, v.y / 720.0), 0.75, 4.0)
	if _head_font == null:
		_head_font = UiTheme.heading_font(0)
		_body_font = UiTheme.body_font()
	var d := v / _u
	var x0 := floorf((d.x - GRID_W) * 0.5)
	var st := menu_stack(d.y, BLOCK_H)
	_build_visualizer_slot(d, x0)
	_build_logo(x0, st)
	_build_buttons(x0, float(st.buttons_y))
	_build_modes(x0 + COL_W + COL_GAP, float(st.buttons_y))
	_build_profile_card()
	_build_footer(d)
	if _np_bm != null:
		_build_now_playing(_np_bm, _np_cover)
	if keep_focus != "":
		var n := _ui.find_child(keep_focus, true, false) as Control
		if n != null:
			n.grab_focus()


func _build_logo(x0: float, st: Dictionary) -> void:
	# Wortmarke in Zielgroesse gerastert. Die Spur-Marke sitzt buendig an der
	# linken Rasterkante (viewBox hat 4 Einheiten Rand).
	var sc: float = float(st.logo_scale)
	var w := LOGO_SIZE.x * sc
	var h := LOGO_SIZE.y * sc
	var stage := LogoStage.new()
	stage.name = "Logo"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.tex = _svg_tex("logo", LOGO_SVG, _px(w) / LOGO_SIZE.x)
	_ui.add_child(stage)
	var inset := 4.0 / 944.0 * w
	_place(stage, x0 - inset, float(st.logo_y), w, h)
	if stage.tex != null:
		var ts := stage.tex.get_size()
		stage.dot = Vector2((107.95 + 4.0) / 944.0 * ts.x, (65.5 + 4.0) / 139.0 * ts.y)
		stage.dot_r = 13.0 / 944.0 * ts.x
	_logo = stage
	_logo_stage = stage
	_intro.append(stage)

	# Unterzeile (Katakana, Systemfont mit CJK-Glyphen), daneben laeuft die
	# Haarlinie bis zur rechten Rasterkante: sie traegt den Block darunter.
	var sub := _label("オーメン・リズムの彼方へ", 15.0, UiTheme.DIM)
	var jp_font := SystemFont.new()
	jp_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP"])
	sub.add_theme_font_override("font", jp_font)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui.add_child(sub)
	var sw := ceilf(sub.get_minimum_size().x / _u)
	_place(sub, x0, float(st.sub_y), sw, MENU_SUB_H)
	_logo_sub = sub
	_intro.append(sub)
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(line)
	line.position = Vector2(_px(x0 + sw + 16.0), _px(float(st.sub_y) + MENU_SUB_H * 0.5))
	line.size = Vector2(_px(x0 + GRID_W) - line.position.x, maxf(roundf(_u), 1.0))
	_intro.append(line)


const MENU_SUB_H := 28.0     # Untertitel-Zeile
const MENU_SUB_GAP := 22.0   # Logo -> Untertitel
const MENU_BTN_GAP := 22.0   # Untertitel -> Knoepfe


## Leises Spektrum am unteren Rand, in Schriftfarbe (keine zweite Farbe).
func _build_visualizer_slot(d: Vector2, x0: float) -> void:
	var viz := AudioVisualizer.new()
	viz.name = "Visualizer"
	viz.color = Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.16)
	viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(viz)
	_place(viz, x0, d.y - 64.0 - 72.0, GRID_W, 72.0)
	_viz = viz


## Laeuft gerade: oben rechts, ohne Karte. Cover, Zeile, Fortschritts-Haarlinie.
func _build_now_playing(bm: Beatmap, cover: Texture2D) -> void:
	var first := _np_bm == null
	_np_bm = bm
	_np_cover = cover
	if is_instance_valid(_np_bar):
		_np_bar.queue_free()
	var d := _view() / _u
	var w := 300.0
	var bar := Control.new()
	bar.name = "NowPlaying"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bar)
	_place(bar, d.x - EDGE - w, 24.0, w, 56.0)
	_np_bar = bar

	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture = cover
	thumb.clip_contents = true
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(thumb)
	_place(thumb, 0.0, 0.0, 40.0, 40.0)

	var cap := _label(tr("JETZT LÄUFT"), 11.0, UiTheme.DIM, true)
	bar.add_child(cap)
	_place(cap, 52.0, 1.0, w - 52.0, 16.0)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(clip)
	_place(clip, 52.0, 17.0, w - 52.0, 24.0)
	# Lauftext statt Ellipse: Label wird in _process im Clip verschoben.
	var title := _label("%s - %s" % [bm.title(), bm.artist()], 15.0, UiTheme.TEXT)
	clip.add_child(title)
	title.position = Vector2.ZERO
	_np_title = title
	_np_clip = clip

	_np_track = Control.new()
	_np_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_np_track)
	_place(_np_track, 0.0, 52.0, w, 2.0)
	var back := ColorRect.new()
	back.color = UiTheme.LINE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_track.add_child(back)
	_np_progress = ColorRect.new()
	_np_progress.color = COL_ACCENT
	_np_progress.size = Vector2(0, _np_track.size.y)
	_np_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_track.add_child(_np_progress)

	if first:
		bar.modulate.a = 0.0
		create_tween().tween_property(bar, "modulate:a", 1.0, 0.5).set_delay(0.2)


## Gestaffeltes Einblenden beim Start: jedes Teil kommt 10 Einheiten von unten
## und wird dabei sichtbar. Ruhig und kurz (unter 1 s insgesamt).
func _play_intro() -> void:
	var i := 0
	for c: Control in _intro:
		var to_y := c.position.y
		c.modulate.a = 0.0
		c.position.y = to_y + _px(10.0)
		var tw := c.create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var delay := 0.04 + 0.028 * i
		tw.tween_property(c, "modulate:a", 1.0, 0.36).set_delay(delay)
		tw.tween_property(c, "position:y", to_y, 0.42).set_delay(delay)
		i += 1


## Bedien-Ebene weich aus- und einblenden, solange ein Fenster (Einstellungen,
## Profil, Login) darueber liegt.
func _dim_ui(on: bool) -> void:
	_modal = maxi(_modal + (1 if on else -1), 0)
	if not is_inside_tree() or _ui == null:
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ui, "modulate:a", 0.0 if _modal > 0 else 1.0, 0.16 if _modal > 0 else 0.26)


func _open_modal(panel: Node) -> void:
	_dim_ui(true)
	panel.tree_exited.connect(_dim_ui.bind(false), CONNECT_ONE_SHOT)
	add_child(panel)


## Szene verlassen: Musik klickfrei aus, dann ueberblenden.
func _leave(path: String) -> void:
	_fade_music_out()
	SceneFader.go(path)


## Linke Spalte: Spielen (einzige Bernstein-Flaeche), darunter die Liste.
func _build_buttons(x0: float, y0: float) -> void:
	_btn_play = _menu_button("SPIELEN", true)
	_btn_play.name = "Play"
	_btn_play.pressed.connect(_play)
	_ui.add_child(_btn_play)
	_place(_btn_play, x0, y0, COL_W, PLAY_H)
	# Feiner Winkel rechts in der Flaeche: zeigt "weiter", in Schriftfarbe.
	var chev := Control.new()
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn_play.add_child(chev)
	_place(chev, COL_W - 20.0 - 9.0, (PLAY_H - 16.0) * 0.5, 9.0, 16.0)
	chev.draw.connect(func():
		var s := chev.size
		chev.draw_polyline(PackedVector2Array([Vector2(0.5, 0.5), Vector2(s.x - 0.5, s.y * 0.5), Vector2(0.5, s.y - 0.5)]),
			UiTheme.ON_ACCENT, maxf(2.0 * _u, 1.5), true))
	_intro.append(_btn_play)
	var y := y0 + PLAY_H + 12.0

	y = _build_campaign_row(x0, y)

	_btn_mp = _menu_button("MULTIPLAYER", false)
	_btn_mp.pressed.connect(_leave.bind("res://scenes/mp_lobby.tscn"))
	y = _add_row(_btn_mp, x0, y)

	y = _build_daily_row(x0, y)

	var tut := _menu_button("TUTORIAL", false)
	tut.pressed.connect(_start_tour)
	y = _add_row(tut, x0, y)

	_btn_settings = _menu_button("EINSTELLUNGEN", false)
	_btn_settings.pressed.connect(_open_settings)
	y = _add_row(_btn_settings, x0, y)

	var quit := _menu_button("BEENDEN", false)
	quit.add_theme_color_override("font_color", UiTheme.DIM)
	quit.pressed.connect(func(): _fade_music_out(); get_tree().quit())
	_add_row(quit, x0, y)


## Listenzeile setzen: Haarlinie unten, Bernstein-Marke links bei Hover/Fokus.
func _add_row(b: Button, x0: float, y: float) -> float:
	b.name = "Row" + str(b.get_meta("key", "")).capitalize().replace(" ", "")
	_ui.add_child(b)
	_place(b, x0, y, COL_W, ROW_H)
	var mark := ColorRect.new()
	mark.color = COL_ACCENT
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	b.add_child(mark)
	mark.position = Vector2(0, _px(9.0))
	mark.size = Vector2(_px(3.0), b.size.y - 2.0 * _px(9.0))
	_markers.append(mark)
	var upd := func(): mark.visible = b.is_hovered() or b.has_focus()
	b.mouse_entered.connect(upd)
	b.mouse_exited.connect(upd)
	b.focus_entered.connect(upd)
	b.focus_exited.connect(upd)
	_intro.append(b)
	return y + ROW_H


## --- Kampagne: Weg durch die Welten, feste Maps fuer alle (Campaign) ---
func _build_campaign_row(x0: float, y: float) -> float:
	var b := _menu_button("KAMPAGNE", false)
	b.pressed.connect(_leave.bind(Campaign.SCENE))
	var ny := _add_row(b, x0, y)
	b.name = "RowCampaign"
	var data := Campaign.load_data()
	var det := _label(tr("%d / %d Sterne") % [Campaign.total_stars_all(data, Campaign.load_state()),
		Campaign.max_stars_all(data)], 13.0, UiTheme.DIM)
	det.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	det.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	det.clip_text = true
	b.add_child(det)
	_place(det, 132.0, 0.0, COL_W - 132.0 - 20.0, ROW_H)
	return ny


## --- Daily Trace: eine Map pro Tag fuer alle, Serie, Tages-Bild (TraceDaily) ---
func _build_daily_row(x0: float, y: float) -> float:
	if not ScoreStore.mode_ready("trace"):
		return y
	var state := TraceDaily.load_state()
	_daily_adopt_result(state)
	_btn_daily = _menu_button("", false)
	_btn_daily.pressed.connect(_daily_start)
	var ny := _add_row(_btn_daily, x0, y)
	_btn_daily.name = "RowDaily"
	# Serie und Tages-Score ruhig rechts in der Zeile.
	_daily_detail = _label("", 13.0, UiTheme.DIM)
	_daily_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_daily_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_daily_detail.clip_text = true
	_daily_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_btn_daily.add_child(_daily_detail)
	_place(_daily_detail, 132.0, 0.0, COL_W - 132.0 - 20.0, ROW_H)
	if _daily_busy:
		_daily_status(tr("Finding today's map …"), true)
	else:
		_refresh_daily(state)
	return ny


func _refresh_daily(state: Dictionary = {}) -> void:
	if not is_instance_valid(_btn_daily):
		return
	if state.is_empty():
		state = TraceDaily.load_state()
	var today := TraceDaily.today_key()
	var n := TraceDaily.streak(state, today)
	var done := TraceDaily.has_attempt(state, today)
	_btn_daily.text = tr("DAILY TRACE").capitalize()
	var parts := PackedStringArray()
	if done:
		var sc := int((state.days[today] as Dictionary).get("score", -1))
		parts.append((tr("Score %s") % UiTheme.fmt_score(sc)) if sc >= 0 else tr("played today"))
	if n > 0:
		parts.append(tr("Streak %d") % n)
	_btn_daily.tooltip_text = tr("Streak: %d days") % n if n > 0 else tr("Same map for everyone, every day. One try counts.")
	if is_instance_valid(_daily_detail):
		_daily_detail.text = "  ·  ".join(parts)
		_daily_detail.visible = true


## Zustandstext in der Daily-Zeile (Suche laeuft, nichts gefunden).
func _daily_status(text: String, busy: bool) -> void:
	if not is_instance_valid(_btn_daily):
		return
	_btn_daily.disabled = busy
	_btn_daily.text = text
	if is_instance_valid(_daily_detail):
		_daily_detail.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _ui != null:
		_built_for = Vector2.ZERO
		_dirty = true


func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	# Satzschreibung statt Versalien: Schluessel bleiben ("SPIELEN"), Anzeige
	# "Spielen". Sprachwechsel baut die Ebene neu (_notification).
	b.set_meta("key", text)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = _sentence(tr(text)) if text != "" else ""
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.add_theme_font_override("font", _head_font)
	var pad := _px(20.0)
	var boxes := {}
	if primary:
		var fill := UiTheme.primary_fill()
		boxes = {"normal": _flat(fill, 4.0), "hover": _flat(fill.lightened(0.10), 4.0),
			"pressed": _flat(fill.darkened(0.12), 4.0), "focus": _outline(UiTheme.TEXT, 6.0, 2.0, 3.0)}
		b.add_theme_font_size_override("font_size", _fs(24.0))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, UiTheme.ON_ACCENT)
	else:
		var t := UiTheme.TEXT
		boxes = {"normal": _flat(Color(t.r, t.g, t.b, 0.0)), "hover": _flat(Color(t.r, t.g, t.b, 0.06)),
			"pressed": _flat(Color(t.r, t.g, t.b, 0.11)), "focus": _flat(Color(t.r, t.g, t.b, 0.06)),
			"disabled": _flat(Color(t.r, t.g, t.b, 0.0))}
		for k in boxes:
			var sb: StyleBoxFlat = boxes[k]
			sb.border_width_bottom = maxi(roundi(_u), 1)
			sb.border_color = UiTheme.LINE
		b.add_theme_font_size_override("font_size", _fs(18.0))
		b.add_theme_color_override("font_color", t)
		b.add_theme_color_override("font_disabled_color", UiTheme.DIM)
	for k in boxes:
		var sb2: StyleBoxFlat = boxes[k]
		if k != "focus" or not primary:
			sb2.content_margin_left = pad
			sb2.content_margin_right = pad
		b.add_theme_stylebox_override(k, sb2)
	UiTheme._attach_sounds(b)
	_btns.append(b)
	return b


## Rechte Flaeche: die sechs Modi als 3x2-Raster gleich grosser Kacheln. Jede
## oeffnet den Browser direkt im Modus (browser_state.cfg play_mode).
func _build_modes(x0: float, y0: float) -> void:
	var i := 0
	for m in MENU_MODES:
		var tile := _mode_tile(m)
		if m == "orbit":
			_btn_orbit = tile
		tile.pressed.connect(_play_mode_entry.bind(m))
		_ui.add_child(tile)
		_place(tile, x0 + (i % 3) * (TILE_W + TILE_GAP), y0 + (i / 3) * (TILE_H + TILE_GAP), TILE_W, TILE_H)
		_fill_tile(tile, m)
		_intro.append(tile)
		i += 1


## Modus-Kachel: ruhige Flaeche, Symbol in Modusfarbe (ModeBadge), Name, Unterzeile.
## Hover und Tastatur-Fokus sehen gleich aus: Bernstein-Kontur.
func _mode_tile(mode: String) -> Button:
	var b := Button.new()
	b.name = "Mode" + mode.capitalize()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = ""
	var s := UiTheme.SURFACE
	var r := UiTheme.RAISED
	var t := UiTheme.TEXT
	var a := COL_ACCENT
	var bw := maxi(roundi(_u), 1)
	var normal := _flat(Color(s.r, s.g, s.b, 0.96), 4.0)
	normal.set_border_width_all(bw)
	normal.border_color = Color(t.r, t.g, t.b, 0.10)
	var hover := _flat(Color(r.r, r.g, r.b, 0.92), 4.0)
	hover.set_border_width_all(bw)
	hover.border_color = Color(a.r, a.g, a.b, 0.95)
	var pressed := _flat(Color(s.r, s.g, s.b, 0.95), 4.0)
	pressed.set_border_width_all(bw)
	pressed.border_color = a
	for sb: StyleBoxFlat in [normal, hover, pressed]:
		sb.shadow_color = Color(0, 0, 0, 0.34)
		sb.shadow_size = roundi(12.0 * _u)
		sb.shadow_offset = Vector2(0.0, _px(4.0))
	hover.bg_color = Color(r.r, r.g, r.b, 0.98)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", _outline(a, 4.0, 2.0))
	UiTheme._attach_sounds(b)
	_btns.append(b)
	return b


func _fill_tile(b: Button, mode: String) -> void:
	var ready := ScoreStore.mode_ready(mode)
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	# Mini-Vorschau des Spielfelds (gezeichnet, kein Icon), darunter Name + Unterzeile.
	var pv := ModePreview.new()
	pv.mode = mode
	pv.u = _u
	pv.col = ModeBadge.color(mode)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pv)
	var bw := 1.0 / _u * maxf(roundf(_u), 1.0)
	_place(pv, bw, bw, TILE_W - 2.0 * bw, PREVIEW_H)
	var upd := func(): pv.set_hover(b.is_hovered() or b.has_focus())
	b.mouse_entered.connect(upd)
	b.mouse_exited.connect(upd)
	b.focus_entered.connect(upd)
	b.focus_exited.connect(upd)
	var title := _label(ScoreStore.mode_label(mode), 19.0, UiTheme.TEXT, true)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(title)
	_place(title, 16.0, PREVIEW_H + 7.0, TILE_W - 32.0, 24.0)
	var sub := _label(_mode_sub_text(mode), 13.0, UiTheme.DIM)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(sub)
	_place(sub, 16.0, PREVIEW_H + 30.0, TILE_W - 32.0, 18.0)
	_mode_subs[mode] = sub
	if not ready:
		box.modulate.a = 0.5
	if ScoreStore.mode_tutorial(mode) != "":
		var q := _tutorial_dot(mode)
		b.add_child(q)
		_place(q, TILE_W - 10.0 - 22.0, 10.0, 22.0, 22.0)


## Kleines "?" oben rechts in der Kachel: oeffnet das Tutorial des Modus.
func _tutorial_dot(mode: String) -> Button:
	var q := Button.new()
	q.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	q.text = "?"
	q.focus_mode = Control.FOCUS_NONE
	q.tooltip_text = tr("Tutorial: %s") % ScoreStore.mode_label(mode)
	q.add_theme_font_override("font", _head_font)
	q.add_theme_font_size_override("font_size", _fs(13.0))
	var a := COL_ACCENT
	var t := UiTheme.TEXT
	for st in ["normal", "hover", "pressed"]:
		var sb := _flat(Color(a.r, a.g, a.b, 0.0 if st == "normal" else 0.16), 12.0)
		sb.set_border_width_all(maxi(roundi(_u), 1))
		sb.border_color = Color(t.r, t.g, t.b, 0.16) if st == "normal" else Color(a.r, a.g, a.b, 0.95)
		q.add_theme_stylebox_override(st, sb)
	q.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	q.add_theme_color_override("font_color", UiTheme.DIM)
	q.add_theme_color_override("font_hover_color", COL_ACCENT)
	q.add_theme_color_override("font_pressed_color", COL_ACCENT)
	q.pressed.connect(_start_mode_tutorial.bind(mode))
	return q


## Profil oben links, ohne Karte: Bild, Name mit Online-Punkt, pp und Spiele.
## Klick oeffnet die Profil-Ansicht (Bild hochladen, Name, Stats).
func _build_profile_card() -> void:
	var card := Button.new()
	card.name = "Profile"
	card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var t := UiTheme.TEXT
	card.add_theme_stylebox_override("normal", _flat(Color(t.r, t.g, t.b, 0.0), 4.0))
	card.add_theme_stylebox_override("hover", _flat(Color(t.r, t.g, t.b, 0.06), 4.0))
	card.add_theme_stylebox_override("pressed", _flat(Color(t.r, t.g, t.b, 0.11), 4.0))
	card.add_theme_stylebox_override("focus", _outline(COL_ACCENT, 4.0, 2.0))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pressed.connect(_open_profile)
	UiTheme._attach_sounds(card)
	_ui.add_child(card)
	_place(card, EDGE - 8.0, 16.0, 256.0, 56.0)
	_profile_card = card
	_intro.append(card)

	_card_avatar = Control.new()
	_card_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_card_avatar)
	_place(_card_avatar, 8.0, 8.0, 40.0, 40.0)

	_name_label = _label("", 16.0, UiTheme.TEXT, true)
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(_name_label)
	_place(_name_label, 60.0, 7.0, 170.0, 22.0)

	_status_dot = Panel.new()
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_status_dot)

	_pp_label = _label("", 13.0, UiTheme.DIM)
	_pp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(_pp_label)
	_place(_pp_label, 60.0, 29.0, 190.0, 20.0)

	_refresh_profile()
	if GameSession.online != null:
		if not GameSession.online.avatar_changed.is_connected(_refresh_profile):
			GameSession.online.avatar_changed.connect(_refresh_profile)
		if not GameSession.online.state_changed.is_connected(_refresh_profile):
			GameSession.online.state_changed.connect(_refresh_profile)


func _refresh_profile() -> void:
	if not is_instance_valid(_name_label) or not is_instance_valid(_card_avatar):
		return
	_name_label.text = Settings.profile_name
	_pp_label.text = "%s  ·  %s" % [UiTheme.fmt_pp(ScoreStore.profile_pp()),
		tr("%s Spiele") % UiTheme.fmt_score(ScoreStore.total_plays())]
	# Online-Punkt hinter dem Namen: gefuellt = angemeldet, Ring = offline.
	var online := GameSession.online != null and GameSession.online.logged_in()
	var dot := _flat(UiTheme.GOOD if online else Color(0, 0, 0, 0), 4.0)
	if not online:
		dot.set_border_width_all(maxi(roundi(_u), 1))
		dot.border_color = UiTheme.DIM
	_status_dot.add_theme_stylebox_override("panel", dot)
	var nw := minf(_name_label.get_minimum_size().x, _name_label.size.x)
	_status_dot.position = Vector2(_name_label.position.x + nw + _px(8.0), _px(7.0 + 8.0))
	_status_dot.size = Vector2(_px(7.0), _px(7.0))
	# Avatar-Kreis: Website-Avatar (angemeldet), eigenes Bild oder Initial.
	for c in _card_avatar.get_children():
		c.queue_free()
	var tex := OnlineApi.display_avatar(GameSession.online, Settings.avatar_texture())
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/avatar_circle.gdshader")
	if tex != null:
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		rect.material = m
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(rect)
	else:
		var circle := ColorRect.new()
		circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		circle.color = UiTheme.RAISED
		circle.material = m
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(circle)
		var initial := _label(Settings.profile_name.substr(0, 1).to_upper(), 18.0, UiTheme.TEXT, true)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_card_avatar.add_child(initial)


## Unterer Rand: Update-Hinweis links, Version rechts. Beides leise.
func _build_footer(d: Vector2) -> void:
	_upd_label = _label(_upd_text, 13.0, UiTheme.TEXT)
	_upd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui.add_child(_upd_label)
	_place(_upd_label, EDGE, d.y - 24.0 - 20.0, 600.0, 20.0)
	var ver := _label("OMEN  ·  v" + Updater.CURRENT_VERSION, 13.0, UiTheme.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui.add_child(ver)
	_place(ver, d.x - EDGE - 260.0, d.y - 24.0 - 20.0, 260.0, 20.0)
	_intro.append(ver)


func _open_profile() -> void:
	var panel := ProfilePanel.new()
	panel.closed.connect(_refresh_profile)
	_open_modal(panel)
	# Tour: nach dem Schliessen des Profils geht es weiter.
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "profile":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


func _open_login_dialog() -> void:
	var dlg := LoginDialog.new()
	dlg.finished.connect(func(ok: bool):
		if ok:
			_refresh_profile())
	_open_modal(dlg)


func _open_settings() -> void:
	var panel := SettingsPanel.new()
	_open_modal(panel)
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "settings":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


## Tastatur: erste Pfeil-/Tab-Taste setzt den Fokus auf "Spielen", danach
## wandert er ueber das Raster (Pfeile, Tab, Enter).
func _unhandled_input(event: InputEvent) -> void:
	if _modal > 0 or _tour_overlay != null or not event.is_pressed() or event.is_echo():
		return
	if get_viewport().gui_get_focus_owner() != null or not is_instance_valid(_btn_play):
		return
	for act in ["ui_down", "ui_up", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action(act):
			_btn_play.grab_focus()
			get_viewport().set_input_as_handled()
			return


func _tour_next() -> void:
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
	_tour_step += 1
	if _tour_step >= _tour_steps.size():
		_tour_finish()
		return
	var st: Dictionary = _tour_steps[_tour_step]
	var target := st.target as Control
	if not is_instance_valid(target):
		_tour_finish()
		return
	_tour_overlay = Control.new()
	_tour_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tour_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tour_overlay)
	var r := target.get_global_rect()
	# Ruhig atmender Bernstein-Rahmen um das echte Element (bleibt klickbar).
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _outline(COL_ACCENT, 5.0, 2.0))
	frame.position = r.position - Vector2.ONE * _px(5.0)
	frame.size = r.size + Vector2.ONE * _px(10.0)
	_tour_overlay.add_child(frame)
	var ftw := frame.create_tween().set_loops()
	ftw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ftw.tween_property(frame, "modulate:a", 0.45, 0.7)
	ftw.tween_property(frame, "modulate:a", 1.0, 0.7)
	# Kurzer Text daneben (klickt NICHT weg — das Ziel ist klickbar).
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(12, 0.95)
	sb.set_content_margin_all(_px(18.0))
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tour_overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(_px(12.0)))
	panel.add_child(vb)
	var step := _label("%d / %d" % [_tour_step + 1, _tour_steps.size()], 13.0, COL_ACCENT, true)
	vb.add_child(step)
	var body := _label(tr(str(st.text)).replace(" 👑", ""), 15.0, UiTheme.TEXT)
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_px(8.0)))
	vb.add_child(row)
	if str(st.get("click", "")) == "":
		var next := Button.new()
		# "Weiter" heisst im Spiel (Pause) "Resume"; hier ist es "Next" -> eigener Text statt CSV-Schluessel.
		next.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		next.text = "Weiter" if UiTheme.is_german() else "Next"
		next.custom_minimum_size = Vector2(_px(110.0), _px(36.0))
		UiTheme.style_button(next, true)
		next.add_theme_font_size_override("font_size", _fs(15.0))
		next.pressed.connect(_tour_next)
		row.add_child(next)
	else:
		var hintl := _label(tr("→ klick das markierte Element"), 13.0, COL_ACCENT)
		hintl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hintl)
	var skip := Button.new()
	skip.text = "Tour beenden"
	skip.custom_minimum_size = Vector2(0, _px(36.0))
	UiTheme.style_ghost_button(skip)
	skip.add_theme_font_size_override("font_size", _fs(15.0))
	skip.pressed.connect(_tour_finish)
	row.add_child(skip)
	# Rechts neben das Ziel, sonst darunter; immer ganz im Fenster.
	var ps := panel.get_combined_minimum_size()
	var v := _view()
	var pos := Vector2(r.end.x + _px(20.0), r.position.y)
	if pos.x + ps.x > v.x - _px(EDGE):
		pos = Vector2(r.position.x, r.end.y + _px(16.0))
	pos.x = clampf(pos.x, _px(EDGE), maxf(v.x - ps.x - _px(EDGE), _px(EDGE)))
	pos.y = clampf(pos.y, _px(EDGE), maxf(v.y - ps.y - _px(EDGE), _px(EDGE)))
	panel.position = pos.round()
