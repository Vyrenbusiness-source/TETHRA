extends Control

## TETHRA Main-Menue: animierter Neon-Hintergrund, grosses Logo, PLAY /
## EINSTELLUNGEN / BEENDEN, Profilkarte (Name editierbar, Gesamt-pp, Plays)
## und die letzten Scores.

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := UiTheme.DIM
const CARD_H := 94.0
const CARD_R := 12
const CARD_PAD := 12
const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var _pp_label: Label
var _plays_label: Label
var _name_label: Label
var _card_avatar: Control
# Interaktive Tutorial-Tour: Pfeil zeigt auf ECHTE Menue-Elemente.
var _profile_card: PanelContainer
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
var _menu_vb: VBoxContainer
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
const LOGO_SIZE := Vector2(600, 88)
const LOGO_SVG := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="-4 -4 944 139" width="600" height="88">
<g transform="translate(-8 -34.5)">
<path d="M97.82 73.82L126.98 115.94A28 28 0 1 0 126.98 84.06L97.82 126.18A46 46 0 1 1 97.82 73.82Z" fill="none" stroke="#ECE6DA" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="115.95" cy="100" r="13" fill="#F2A23A"/>
</g>
<g transform="translate(59 -59.5)">
<path d="M169.5 66H235.5M202.5 66V184" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M354.5 66H288.5V184H354.5M288.5 125H344.6" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M407.5 66H473.5M440.5 66V184" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M526.5 66V184M592.5 66V184M526.5 125H592.5" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M645.5 184V66H680.82A30.68 30.68 0 0 1 680.82 127.36H645.5M673.22 127.36L711.5 184" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M764.5 184L797.5 66L830.5 184M777.7 141.52H817.3" fill="none" stroke="#ECE6DA" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="867" cy="176" r="10" fill="#F2A23A"/>
</g>
</svg>"""
static var _browser_scene: PackedScene = null
static var _browser_req := false
var _warm_pending: Array[String] = []
var _warm_vp: SubViewport = null
var _warm_frames := 0
var _warm_t := 0


func _ready() -> void:
	var t_ready := Time.get_ticks_usec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Hintergrund: geblurrtes Cover der zuletzt gespielten Map — clean.
	# Fallback (noch nie gespielt): animierter Neon-Hintergrund.
	if not _build_blur_bg():
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/menu_bg.gdshader")
		bg.material = mat
		_bg_mat = mat
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	_build_calm()
	_build_logo()
	_build_buttons()
	_layout_menu()
	resized.connect(_layout_menu)
	_build_profile_card()
	_build_visualizer_slot()
	if DisplayServer.get_name() != "headless":
		_begin_menu_music()
		_begin_shader_warmup()
	_play_intro()

	# Update-Banner unten links: zeigt Fortschritt des Auto-Updaters.
	var upd := Label.new()
	upd.anchor_top = 1.0
	upd.anchor_bottom = 1.0
	upd.offset_left = 20
	upd.offset_right = 620
	upd.offset_top = -34
	upd.add_theme_font_size_override("font_size", 13)
	upd.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	upd.text = ""
	add_child(upd)
	Updater.state_changed.connect(func(text, _ratio): upd.text = text)

	# Dezentes Versions-Tag unten rechts.
	var ver := Label.new()
	ver.text = "TETHRA  ·  v" + Updater.CURRENT_VERSION
	ver.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	ver.add_theme_constant_override("shadow_offset_x", 1)
	ver.add_theme_constant_override("shadow_offset_y", 1)
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -260
	ver.offset_right = -24
	ver.offset_top = -34
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.9))
	add_child(ver)
	if GpuGuard.take_notice():
		_show_gpu_notice()
	GameSession.perf_since("Hauptmenue: _ready gesamt", t_ready)

	if DisplayServer.get_name() == "headless":
		print("=== MainMenu Headless OK (pp=%.1f, plays=%d) ===" % [
			ScoreStore.profile_pp(), ScoreStore.total_plays()])
		get_tree().quit(0)
	elif OS.get_cmdline_args().has("--shot-menu"):
		_capture()
	elif OS.get_cmdline_args().has("--shot-profile"):
		# Harness: Profil-Ansicht oeffnen und abfotografieren.
		add_child(ProfilePanel.new())
		_capture()
	elif OS.get_cmdline_args().has("--shot-settings"):
		add_child(SettingsPanel.new())
		_capture()
	elif OS.get_cmdline_args().has("--shot-login"):
		# Harness: Login-Dialog (Spielstart) erzwingen und abfotografieren.
		_open_login_dialog()
		_capture()
	elif GameSession.perf_enabled:
		# Lade-Messung: 1 s Menue zeigen, dann in den Song-Browser.
		await get_tree().create_timer(1.0).timeout
		GameSession.perf_request("Hauptmenue -> Song-Browser")
		_play()
	elif OS.get_cmdline_args().has("--autoplay"):
		# Test-Durchreiche in den Song-Browser.
		_play.call_deferred()
	elif LoginDialog.should_show(GameSession.online, OS.get_cmdline_args(), false):
		# Nicht angemeldet: einmal pro Spielstart ruhig nach dem Login fragen.
		await get_tree().create_timer(0.6).timeout
		if is_inside_tree():
			_open_login_dialog()
	elif LoginDialog.should_resume_backfill(GameSession.online, OS.get_cmdline_args(), false):
		# Angemeldet, Upload alter Scores steht noch aus (neue Merker-Version): nachholen.
		await get_tree().create_timer(2.0).timeout
		LoginDialog.after_login(GameSession.online, LoginDialog.scan_osz_files())


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
	if _viz != null:
		_viz.set_color(_cover_color(cover))
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


## Bass-Onset gegen gleitenden Mittelwert -> Kick-Puls; ruhig ohne Musik.
func _process(delta: float) -> void:
	_shader_warmup_step()
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
	if _np_progress != null and playing and _music.stream != null:
		var len_s: float = maxf(_music.stream.get_length(), 1.0)
		var frac: float = clampf(_music.get_playback_position() / len_s, 0.0, 1.0)
		_np_progress.size.x = _np_track.size.x * frac
	if _np_title != null and _np_clip != null:
		var over: float = _np_title.get_minimum_size().x - _np_clip.size.x
		if over > 1.0:
			_np_t += delta
			var travel: float = over / 32.0
			var pause := 1.6
			var cyc: float = 2.0 * (travel + pause)
			var t: float = fposmod(_np_t, cyc)
			var u: float
			if t < pause:
				u = 0.0
			elif t < pause + travel:
				u = (t - pause) / travel
			elif t < 2.0 * pause + travel:
				u = 1.0
			else:
				u = 1.0 - (t - 2.0 * pause - travel) / travel
			_np_title.position.x = -over * u
		else:
			_np_title.position.x = 0.0
	var pulse_k: float = _kick
	if _beat_clock != null and playing and _beat_clock.bpm > 0.0:
		# Exakt auf dem Beat: Position + Mix-Offset - Ausgabe-Latenz.
		var t_ms: float = _music.get_playback_position() * 1000.0 + AudioServer.get_time_since_last_mix() * 1000.0 - AudioServer.get_output_latency() * 1000.0
		_beat_clock.update(t_ms, delta)
		pulse_k = _beat_clock.beat_env
	_pulse = pulse_k
	if _viz != null:
		_viz.modulate.a = 0.6 + 0.2 * pulse_k
	if _bg_mat != null:
		_bg_mat.set_shader_parameter("bass", bass_lvl)
		_bg_mat.set_shader_parameter("kick", _kick)
	if _dim_overlay != null:
		_dim_overlay.color.a = 0.60 - 0.04 * bass_lvl - 0.03 * _pulse
	# Dezenter Bass-Puls nur am gehoverten/fokussierten Button.
	for b in _btns:
		if b.is_hovered() or b.has_focus():
			b.scale = Vector2.ONE * (1.0 + 0.02 * _pulse)


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


func _add_blur_layers(tex: Texture2D) -> void:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture = UiTheme.blurred_texture(tex)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.resized.connect(func(): rect.pivot_offset = rect.size * 0.5)
	rect.modulate = Color(0.55, 0.55, 0.55, 1.0)
	add_child(rect)
	_bg_rect = rect
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.60)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_dim_overlay = overlay
	# Weiche Vignette: Raender dunkler, Mitte frei.
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0.0))
	vg.set_color(1, Color(0, 0, 0, 0.55))
	vg.set_offset(0, 0.45)
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.0, 1.0)
	vt.width = 256
	vt.height = 256
	var vr := TextureRect.new()
	vr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vr.texture = vt
	vr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vr.stretch_mode = TextureRect.STRETCH_SCALE
	vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vr)


## Radiale Beruhigung hinter der Button-Saeule: dunkler weicher Fleck.
func _build_calm() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.6)
	t.fill_to = Vector2(0.86, 0.6)
	t.width = 256
	t.height = 256
	var r := TextureRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _build_logo() -> void:
	# Logo statt Schrift-Label: Spur-Marke + Wortmarke als Vektor, zur Laufzeit
	# in doppelter Aufloesung gerastert (scharf auch bei HiDPI).
	var tex: Texture2D = null
	var img := Image.new()
	if img.load_svg_from_string(LOGO_SVG, 2.0) == OK:
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	var logo := TextureRect.new()
	logo.texture = tex
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	add_child(logo)  # Lage: _layout_menu()
	_logo = logo

	# Untertitel auf Japanisch (Katakana) — Systemfont, da der Godot-Default
	# keine CJK-Glyphen mitbringt.
	var sub := Label.new()
	sub.text = "テトラ・リズムの彼方へ"
	sub.anchor_left = 0.5
	sub.anchor_right = 0.5
	sub.offset_left = -300
	sub.offset_right = 300
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var jp_font := SystemFont.new()
	jp_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic", "Noto Sans CJK JP"])
	sub.add_theme_font_override("font", jp_font)
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(0.85, 0.88, 0.96))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("shadow_offset_x", 1)
	sub.add_theme_constant_override("shadow_offset_y", 2)
	sub.add_theme_constant_override("shadow_outline_size", 6)
	add_child(sub)
	_logo_sub = sub


## Logo, Untertitel und Knopf-Block als ein Stapel senkrecht mittig: gleicher
## Abstand oben und unten (720p: "Beenden" nicht mehr am Rand). Bei kleinen
## Fenstern wird das Logo kleiner, damit es neben "Now playing" frei bleibt.
func _layout_menu() -> void:
	if _logo == null or _logo_sub == null or _menu_vb == null:
		return
	var h := size.y if size.y > 0.0 else get_viewport_rect().size.y
	var r := menu_stack(h, _menu_vb.get_combined_minimum_size().y)
	var sc: float = r.logo_scale
	for c: Control in [_logo, _logo_sub, _menu_vb]:
		c.anchor_top = 0.0
		c.anchor_bottom = 0.0
	_logo.offset_left = -LOGO_SIZE.x * sc * 0.5
	_logo.offset_right = LOGO_SIZE.x * sc * 0.5
	_logo.offset_top = r.logo_y
	_logo.offset_bottom = r.logo_y + LOGO_SIZE.y * sc
	_logo_sub.offset_top = r.sub_y
	_logo_sub.offset_bottom = r.sub_y + MENU_SUB_H
	_menu_vb.offset_top = r.buttons_y
	_menu_vb.offset_bottom = r.buttons_y + r.buttons_h


const MENU_SUB_H := 28.0     # Untertitel-Zeile
const MENU_SUB_GAP := 22.0   # Logo -> Untertitel
const MENU_BTN_GAP := 22.0   # Untertitel -> Knoepfe


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


## Platzhalter: hier haengt spaeter der AudioVisualizer ein.
func _build_visualizer_slot() -> void:
	var slot := Control.new()
	slot.name = "VisualizerSlot"
	slot.anchor_left = 0.0
	slot.anchor_right = 1.0
	slot.anchor_top = 1.0
	slot.anchor_bottom = 1.0
	slot.offset_top = -190
	slot.offset_bottom = -44
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	var viz := AudioVisualizer.new()
	viz.anchor_left = 0.5
	viz.anchor_right = 0.5
	viz.anchor_top = 0.0
	viz.anchor_bottom = 1.0
	viz.offset_left = -560
	viz.offset_right = 560
	viz.offset_top = 0
	viz.offset_bottom = 0
	viz.color = UiTheme.ACCENT
	_viz = viz
	viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viz.modulate.a = 0.7
	slot.add_child(viz)


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


## Now-Playing-Leiste oben rechts: Cover, Titel - Artist, duenne Fortschrittslinie.
func _build_now_playing(bm: Beatmap, cover: Texture2D) -> void:
	var bar := PanelContainer.new()
	_np_bar = bar
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -364
	bar.offset_right = -24
	bar.offset_top = 20
	bar.custom_minimum_size = Vector2(0, CARD_H)
	var sb := UiTheme.glass_box(CARD_R, 0.45)
	sb.set_content_margin_all(CARD_PAD)
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(vb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(44, 44)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture = cover
	thumb.clip_contents = true
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(thumb)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)

	var cap := Label.new()
	cap.text = "JETZT LÄUFT"
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", UiTheme.ACCENT)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(cap)

	var title := Label.new()
	title.text = "%s - %s" % [bm.title(), bm.artist()]
	title.add_theme_font_size_override("font_size", 15)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Lauftext statt Ellipse: Clip-Container, Label wird in _process gescrollt.
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(240, 22)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(title)
	title.position = Vector2.ZERO
	tv.add_child(clip)
	_np_title = title
	_np_clip = clip

	_np_track = Control.new()
	_np_track.custom_minimum_size = Vector2(0, 2)
	_np_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_np_track)
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.14)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_track.add_child(back)
	_np_progress = ColorRect.new()
	_np_progress.color = COL_ACCENT
	_np_progress.size = Vector2(0, 2)
	_np_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_np_track.add_child(_np_progress)

	bar.modulate.a = 0.0
	create_tween().tween_property(bar, "modulate:a", 1.0, 0.8).set_delay(0.9)


## Gestaffeltes Einblenden beim Start: Logo, Untertitel, Buttons, Profilkarte.
func _play_intro() -> void:
	var targets: Array = []
	for c in get_children():
		if (c is Label or c is PanelContainer or c is VBoxContainer) and c != _np_bar:
			targets.append(c)
	var i := 0
	for c in targets:
		var ctl: Control = c
		if ctl is VBoxContainer:
			for w in ctl.get_children():
				_fade_in(w, 0.25 + 0.08 * i)
				i += 1
		else:
			_fade_in(ctl, 0.05 + 0.08 * i)
			i += 1


func _fade_in(n: Control, delay: float) -> void:
	n.modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, 0.55).set_delay(delay)


func _build_buttons() -> void:
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	# Senkrechte Lage setzt _layout_menu() (Stapel mit Logo mittig).
	vb.offset_left = -180
	vb.offset_right = 180
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	_menu_vb = vb

	_btn_play = _menu_button("SPIELEN", true)
	_btn_play.pressed.connect(_play)
	_add_menu_button(vb, _btn_play)

	# Alle sechs Modi als ruhiges 3x2-Raster gleich grosser Kacheln unter SPIELEN:
	# jede oeffnet den Browser direkt im Modus (browser_state.cfg play_mode).
	# Knoepfe dafuer etwas flacher, damit "Beenden" bei 720p sichtbar bleibt.
	var modes := GridContainer.new()
	modes.columns = 3
	modes.custom_minimum_size = Vector2(360, 0)
	modes.add_theme_constant_override("h_separation", 8)
	modes.add_theme_constant_override("v_separation", 6)
	vb.add_child(modes)
	for m in MENU_MODES:
		var tile := _mode_tile(m)
		if m == "orbit":
			_btn_orbit = tile
		tile.pressed.connect(_play_mode_entry.bind(m))
		modes.add_child(tile)

	_btn_mp = _menu_button("MULTIPLAYER", false)
	_btn_mp.pressed.connect(func(): _fade_music_out(); SceneFader.go("res://scenes/mp_lobby.tscn"))
	_add_menu_button(vb, _btn_mp)

	var tut := _menu_button("TUTORIAL", false)
	tut.pressed.connect(_start_tour)
	_add_menu_button(vb, tut)

	_btn_settings = _menu_button("EINSTELLUNGEN", false)
	_btn_settings.pressed.connect(_open_settings)
	_add_menu_button(vb, _btn_settings)

	var quit := _menu_button("BEENDEN", false)
	quit.pressed.connect(func(): _fade_music_out(); get_tree().quit())
	_add_menu_button(vb, quit)


## Modus-Kacheln des Hauptmenues (Reihenfolge = ScoreStore.MODES).
const MENU_MODES := ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]
## Hoehe der Hauptknoepfe und Modus-Kacheln.
const MENU_BTN_H := 52.0
const MODE_TILE_H := 52.0


func _add_menu_button(parent: Control, b: Button) -> void:
	b.custom_minimum_size.y = MENU_BTN_H
	_add_wrapped(parent, b, MENU_BTN_H)


## Button in Wrapper: links Glow-Kante + Slide bei Hover, kleiner Puls beim Klick.
func _add_wrapped(parent: Control, b: Button, h: float = 58.0) -> void:
	var w := Control.new()
	w.custom_minimum_size = Vector2(360, h)
	parent.add_child(w)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(b)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.32))
	grad.set_color(1, Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 8
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.position = Vector2(-4, 4)
	glow.size = Vector2(56, 50)
	glow.modulate.a = 0.0
	# Kein Glow mehr (Identitaet: klare Kanten); nur die Akzent-Kante bleibt.
	glow.visible = false
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(glow)
	var edge := ColorRect.new()
	edge.color = COL_ACCENT
	edge.position = Vector2(-4, 9)
	edge.size = Vector2(4, h - 18.0)
	edge.modulate.a = 0.0
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(edge)
	_btns.append(b)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "offset_left", 14.0, 0.18)
		tw.tween_property(b, "offset_right", 14.0, 0.18)
		tw.tween_property(glow, "modulate:a", 1.0, 0.18)
		tw.tween_property(edge, "modulate:a", 1.0, 0.18))
	b.mouse_exited.connect(func():
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "offset_left", 0.0, 0.25)
		tw.tween_property(b, "offset_right", 0.0, 0.25)
		tw.tween_property(glow, "modulate:a", 0.0, 0.25)
		tw.tween_property(edge, "modulate:a", 0.0, 0.25))
	b.button_down.connect(func():
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.025, 1.025), 0.07)
		tw.tween_property(b, "scale", Vector2.ONE, 0.18))


## "MULTIPLAYER" -> "Multiplayer" (nur erster Buchstabe gross).
static func _sentence(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1).to_lower()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		for b in _btns:
			if is_instance_valid(b) and b.has_meta("key"):
				b.text = _sentence(tr(b.get_meta("key")))
		for m in _mode_subs:
			if is_instance_valid(_mode_subs[m]):
				(_mode_subs[m] as Label).text = _mode_sub_text(m)


func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	# Satzschreibung statt Versalien: Schluessel bleiben ("SPIELEN"), Anzeige
	# "Spielen"; bei Sprachwechsel neu gesetzt (_notification).
	b.set_meta("key", text)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = _sentence(tr(text))
	b.custom_minimum_size = Vector2(360, 58)
	b.add_theme_font_override("font", UiTheme.heading_font(0))
	b.add_theme_font_size_override("font_size", 21)
	if primary:
		UiTheme.style_button(b, true)
	else:
		UiTheme.style_ghost_button(b)
	return b


func _build_profile_card() -> void:
	# Klickbare Karte: oeffnet die Profil-Ansicht (Bild hochladen, Name, Stats).
	var card := PanelContainer.new()
	_profile_card = card
	card.position = Vector2(24, 20)
	card.custom_minimum_size = Vector2(250, CARD_H)
	var sb := UiTheme.glass_box(CARD_R, 0.45)
	sb.set_content_margin_all(CARD_PAD)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_profile())
	add_child(card)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	_card_avatar = Control.new()
	_card_avatar.custom_minimum_size = Vector2(44, 44)
	_card_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_card_avatar)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_name_label)

	_pp_label = Label.new()
	_pp_label.add_theme_font_size_override("font_size", 17)
	_pp_label.add_theme_color_override("font_color", UiTheme.ACCENT2)
	_pp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_pp_label)

	_plays_label = Label.new()
	_plays_label.add_theme_font_size_override("font_size", 13)
	_plays_label.add_theme_color_override("font_color", COL_DIM)
	_plays_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_plays_label)

	_refresh_profile()
	if GameSession.online != null:
		GameSession.online.avatar_changed.connect(_refresh_profile)


func _open_profile() -> void:
	var panel := ProfilePanel.new()
	panel.closed.connect(_refresh_profile)
	add_child(panel)
	# Tour: nach dem Schliessen des Profils geht es weiter.
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "profile":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


func _open_login_dialog() -> void:
	var dlg := LoginDialog.new()
	dlg.finished.connect(func(ok: bool):
		if ok:
			_refresh_profile())
	add_child(dlg)


func _open_settings() -> void:
	var panel := SettingsPanel.new()
	add_child(panel)
	if _tour_step >= 0 and _tour_step < _tour_steps.size() \
			and str(_tour_steps[_tour_step].get("click", "")) == "settings":
		panel.closed.connect(_tour_next, CONNECT_ONE_SHOT)


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


func _tour_next() -> void:
	if _tour_overlay != null:
		_tour_overlay.queue_free()
		_tour_overlay = null
	_tour_step += 1
	if _tour_step >= _tour_steps.size():
		_tour_finish()
		return
	var st: Dictionary = _tour_steps[_tour_step]
	_tour_overlay = Control.new()
	_tour_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tour_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tour_overlay)
	var target := st.target as Control
	var r := target.get_global_rect()
	# Blinkender Pfeil direkt ueber dem echten Element.
	var arrow := Label.new()
	arrow.text = "⬇"
	arrow.custom_minimum_size = Vector2(64, 0)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.position = Vector2(r.get_center().x - 32.0, r.position.y - 96.0)
	arrow.add_theme_font_size_override("font_size", 56)
	arrow.add_theme_color_override("font_color", UiTheme.ACCENT)
	arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	arrow.add_theme_constant_override("shadow_outline_size", 10)
	_tour_overlay.add_child(arrow)
	var atw := arrow.create_tween().set_loops()
	atw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.tween_property(arrow, "position:y", r.position.y - 66.0, 0.4)
	atw.tween_property(arrow, "position:y", r.position.y - 96.0, 0.4)
	atw.parallel().tween_property(arrow, "modulate:a", 0.55, 0.4)
	atw.chain().tween_property(arrow, "modulate:a", 1.0, 0.0)
	# Kurzer Text daneben (klickt NICHT weg — das Ziel ist klickbar).
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(12, 0.9)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var px := clampf(r.get_center().x + 60.0, 20.0, get_viewport_rect().size.x - 480.0)
	panel.position = Vector2(px, maxf(r.position.y - 90.0, 16.0))
	_tour_overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var body := Label.new()
	body.text = str(st.text)
	body.add_theme_font_size_override("font_size", 15)
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	if str(st.get("click", "")) == "":
		var next := Button.new()
		# "Weiter" heisst im Spiel (Pause) "Resume"; hier ist es "Next" -> eigener Text statt CSV-Schluessel.
		next.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		next.text = "Weiter" if UiTheme.is_german() else "Next"
		next.custom_minimum_size = Vector2(110, 36)
		UiTheme.style_button(next, true)
		next.pressed.connect(_tour_next)
		row.add_child(next)
	else:
		var hintl := Label.new()
		hintl.text = "→ klick das markierte Element"
		hintl.add_theme_font_size_override("font_size", 12)
		hintl.add_theme_color_override("font_color", COL_ACCENT)
		row.add_child(hintl)
	var skip := Button.new()
	skip.text = "Tour beenden"
	skip.custom_minimum_size = Vector2(0, 36)
	UiTheme.style_button(skip)
	skip.pressed.connect(_tour_finish)
	row.add_child(skip)


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
	guide.text = "📖 Wissens-Guide lesen (pp, Sterne, Acc …)"
	guide.custom_minimum_size = Vector2(0, 42)
	UiTheme.style_button(guide)
	guide.pressed.connect(func(): SceneFader.go("res://scenes/tutorial.tscn"))
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
			if int(m.get("mode", 0)) != 3:
				continue
			GameSession.tutorial = true
			GameSession.mods = { "NF": true }
			GameSession.is_replay = false
			GameSession.replay_events = []
			GameSession.set_selection(ms.osz_path, i, ms.version_name_at(i),
				str(m.get("osu_filename", "")), ms.stars_at(i))
			SceneFader.go("res://scenes/mania_3d.tscn")
			return


func _refresh_profile() -> void:
	_name_label.text = Settings.profile_name
	_pp_label.text = UiTheme.fmt_pp(ScoreStore.profile_pp())
	_plays_label.text = tr("%s Spiele") % UiTheme.fmt_score(ScoreStore.total_plays())
	# Avatar-Kreis: Website-Avatar (angemeldet), eigenes Bild oder Initial.
	for c in _card_avatar.get_children():
		c.queue_free()
	var tex := OnlineApi.display_avatar(GameSession.online, Settings.avatar_texture())
	if tex != null:
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/avatar_circle.gdshader")
		rect.material = m
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(rect)
	else:
		var circle := ColorRect.new()
		circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		circle.color = Color(0.16, 0.30, 0.42)
		var m2 := ShaderMaterial.new()
		m2.shader = load("res://shaders/avatar_circle.gdshader")
		circle.material = m2
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(circle)
		var initial := Label.new()
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.text = Settings.profile_name.substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 20)
		initial.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_avatar.add_child(initial)


func _build_recent() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -420
	panel.offset_right = -28
	panel.offset_top = 24
	var sb := UiTheme.glass_box(14, 0.5)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var head := Label.new()
	head.text = "Letzte Scores"
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(head)

	var recent := ScoreStore.recent_plays(6)
	if recent.is_empty():
		var empty := Label.new()
		empty.text = "Noch keine Spiele — leg los!"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", COL_DIM)
		vb.add_child(empty)
		return
	for e in recent:
		vb.add_child(_recent_row(e))


func _recent_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var grade := Label.new()
	var g := str(e.get("grade", "D"))
	grade.text = "F" if bool(e.get("failed", false)) else g
	grade.custom_minimum_size = Vector2(30, 0)
	grade.add_theme_font_size_override("font_size", 22)
	grade.add_theme_color_override("font_color",
		Color(1.0, 0.3, 0.3) if bool(e.get("failed", false)) else GRADE_COLOR.get(g, Color.WHITE))
	row.add_child(grade)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var map_label := Label.new()
	map_label.text = "%s [%s]" % [str(e.get("map", "?")), str(e.get("version", ""))]
	map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_label.add_theme_font_size_override("font_size", 14)
	info.add_child(map_label)
	var detail := Label.new()
	var pp := float(e.get("pp", -1.0))
	var pp_txt := ("  ·  " + UiTheme.fmt_num(pp, 1) + " pp") if pp >= 0.0 else ""
	detail.text = "%s  ·  %s%s" % [UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0), UiTheme.fmt_score(int(e.get("score", 0))), pp_txt]
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", COL_DIM)
	info.add_child(detail)

	return row


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


## Modus-Kachel: flach, Bernstein-Kontur, Titel + ruhige Unterzeile.
func _mode_tile(mode: String) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = ""
	b.tooltip_text = ""
	b.custom_minimum_size = Vector2(0, MODE_TILE_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_ghost_button(b)
	var a := COL_ACCENT
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
		sb.border_color = Color(a.r, a.g, a.b, 0.85 if st != "normal" else 0.6)
		sb.bg_color = Color(a.r, a.g, a.b, {"normal": 0.06, "hover": 0.13, "pressed": 0.18}[st])
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(st, sb)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var title := Label.new()
	title.text = ScoreStore.mode_label(mode)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.heading_font(0))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var sub := Label.new()
	sub.text = _mode_sub_text(mode)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(90, 0)
	sub.add_theme_font_override("font", UiTheme.body_font())
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", COL_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	_mode_subs[mode] = sub
	if not ScoreStore.mode_ready(mode):
		col.modulate.a = 0.55
	if ScoreStore.mode_tutorial(mode) != "":
		b.add_child(_tutorial_dot(mode))
	return b


## Kleines "?" oben rechts in der Kachel: oeffnet das Tutorial des Modus.
func _tutorial_dot(mode: String) -> Button:
	var q := Button.new()
	q.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	q.text = "?"
	q.focus_mode = Control.FOCUS_NONE
	q.tooltip_text = tr("Tutorial: %s") % ScoreStore.mode_label(mode)
	q.anchor_left = 1.0
	q.anchor_right = 1.0
	q.offset_left = -21
	q.offset_right = -3
	q.offset_top = 3
	q.offset_bottom = 21
	q.add_theme_font_size_override("font_size", 11)
	var a := COL_ACCENT
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(9)
		sb.set_border_width_all(1)
		sb.border_color = Color(a.r, a.g, a.b, 0.45 if st == "normal" else 0.9)
		sb.bg_color = Color(a.r, a.g, a.b, 0.0 if st == "normal" else 0.18)
		q.add_theme_stylebox_override(st, sb)
	q.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	q.add_theme_color_override("font_color", COL_DIM)
	q.add_theme_color_override("font_hover_color", COL_ACCENT)
	q.pressed.connect(_start_mode_tutorial.bind(mode))
	return q


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
