extends Node3D

## TETHRA 4K: RAUMSCHIFF-INTERCEPT.
## Du fliegst ein Schiff ueber einen Energie-Highway im All. Vier Schienen
## laufen auf dich zu; Drohnen-Orbs gleiten mit KONSTANTER Geschwindigkeit
## heran und kreuzen exakt zur Hit-Time die ABFANGLINIE vor deinem Schiff —
## dort drueckst du (D/F/J/K), das Schiff feuert einen Laser. Holds = Strahl
## halten. Das "Wann" ist glasklar: Note beruehrt Linie + Lock-On + Beat-Puls.

const Z_FAR := -46.0        # Spawn-Horizont
const Z_LINE := 3.0         # Abfanglinie (Hit-Moment) — nah an der Kamera
const SHIP_Z := 3.8
const ROAD_Y := -1.6
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]

const QUALITY_TEXT := { 0: "MAX", 1: "300", 2: "200", 3: "100", 4: "50", 5: "✕" }
const QUALITY_COLOR := {
	0: Color(1.0, 0.92, 0.55), 1: Color(1.0, 1.0, 1.0),
	2: Color(0.4, 0.9, 1.0), 3: Color(0.45, 1.0, 0.6),
	4: Color(0.75, 0.72, 0.5), 5: Color(1.0, 0.28, 0.28),
}
# CLEAN-Schema bei "Effekte: Aus": neutrale, matte Farben — Hitzone grau,
# Noten gedecktes Blau, Holds Amber (klar unterscheidbar, nichts leuchtet).
const CLEAN_PAD := Color(0.52, 0.54, 0.60)
const CLEAN_NOTE := Color(0.58, 0.76, 0.94)
const CLEAN_HOLD := Color(0.95, 0.72, 0.38)

const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var core := ManiaCore.new()
var _beatmap: Beatmap
var _use_audio := false
var _camera: Camera3D
var _glow_shader: Shader
var _ring_shader: Shader

var _theme_col := Color(0.22, 0.68, 0.90)
var _theme_kiai := Color(0.92, 0.52, 0.20)

## Traeger fuer die komplette Strecke (Rails/Linie/Pads/Notes/Laser):
## wird als Ganzes geneigt/gerollt -> Flug-Gefuehl ohne Judgement-Einfluss.
var _world: Node3D
# OVERDRIVE-Effekt (Combo-Blitz) + Kamera-Beben.
var _overdrive := 0.0
var _shake := 0.0
var _was_kiai := false
var _pitch_smooth := 0.0
var _lift_smooth := 0.0

var _edge_mats: Array[StandardMaterial3D] = []
var _pad_mats: Array[StandardMaterial3D] = []
var _pad_flash: Array[float] = []
var _line_mat: StandardMaterial3D
var _ship: Node3D
var _ship_glow_mat: ShaderMaterial
var _horizon_mat: ShaderMaterial
var _road_mat: ShaderMaterial

# Beat-exakte FX: Integer-Beat-Kante triggert alles synchron zum Takt.
var _beat_idx_last := -999999
var _vignette_mat: ShaderMaterial
var _ember_mm: MultiMesh
var _ember_pos: Array[Vector3] = []
var _ember_vel: Array[float] = []
var _ember_life: Array[float] = []
var _ember_next := 0
var _pad_nodes: Array[MeshInstance3D] = []
var _planet_mats: Array[ShaderMaterial] = []
var _nebula_kick := 0.0
var _line_flash := 0.0
var _ember_mat: ShaderMaterial

# Replay: Aufnahme jeder Runde + zeitgenaue Wiedergabe.
var _recorded: Array = []
var _replay_idx := 0

# Kreative Song-Events: Drop-Warp, Notendichte-Surge, Phrasen-Sweep, Break.
var _density := 0.0
var _in_break := false
var _scan_from := 0

## index -> {root, glow_mat, rim, beam}
var _notes: Dictionary = {}

var _star_mm: MultiMesh
var _star_seeds: Array[Vector3] = []
var _star_scales: Array[float] = []
var _star_scroll := 0.0
# Akkumulierte Nebel-Drift-Uhr: laeuft im Beat schneller (Reise-Gefuehl).
var _nebula_drift := 0.0
# ON FIRE: Streckenkanten brennen ab 97% Acc, ab 99.5% Perfection-Plasma.
var _fire_mats: Array = []
var _fire_level := 0.0
var _fire_heat := 0.0
# HYPERSPACE-Drop: 1.0 beim Kiai-Start, zieht die Sterne zu Lichtfaeden.
var _warp_level := 0.0
# REISE-ROUTE: Basis-Positionen + Drift der Planeten ueber die Songdauer.
# Letzter Eintrag = Ziel-Planet (steigt auf, Docking-Finale zieht ihn mittig).
var _planet_base: Array = []
const PLANET_DRIFT := [
	Vector3(9.0, -2.6, 0.0), Vector3(-10.5, 2.8, 0.0),
	Vector3(6.0, 1.8, 0.0), Vector3(-2.0, 9.0, 0.0)]
# KOSMOS: der komplette Hintergrund haengt unter diesem frei beweglichen
# Node — die Bahn bleibt fix, das UNIVERSUM fliegt (Roll/Bank/Climb).
var _cosmos: Node3D
var _cosmos_roll := 0.0
var _cosmos_roll_target := 0.0
var _cosmos_bank := 0.0
var _cosmos_bank_target := 0.0
var _cosmos_lift := 0.0
var _cosmos_lift_target := 0.0
# Easing-Phasen (0..1) fuer butterweiche Roll-/Climb-Bewegungen.
var _roll_phase := 0.0
var _lift_phase := 0.0
# Beat-Schub-Reise: akkumulierte Distanz statt linearer Zeit.
var _travel := 0.0
# Screen-FX (Aberration/Schockwelle/Glitch/Vignette).
var _screen_mat: ShaderMaterial
var _shock := -1.0
var _glitch := 0.0
var _miss_streak := 0
# Schwarzes Loch + God-Rays.
var _bh_mat: ShaderMaterial
var _rays_mat: ShaderMaterial
# GALAXIEN-REISE: der Song ist in Kapitel geteilt — jede "Galaxie" hat ihr
# eigenes Farbklima, Nebelbild und Sternendichte. Uebergaenge crossfaden
# butterweich (~2s) und der Kapitelwechsel feuert einen Hyperspace-Sprung.
var _gal_chapters: Array = []
var _gal_idx := -1
var _gal_col := Color(0.2, 0.5, 1.0)
var _gal_col2 := Color(1.0, 0.4, 0.8)
var _gal_stars := 1.0
var _gal_scale := 1.0
## Grund-Reisetempo aus dem BPM der Map (140 BPM = neutral).
var _bpm_factor := 1.0
# Flug-Choreografie (aus der Map geplant) + aktive Vorbeifluege.
var _flight_plan: Array = []
var _flight_idx := 0
var _flybys: Array = []
var _whoosh_player: AudioStreamPlayer
## Stations-Assets werden beim Map-Start EINMAL geladen (Preload-Cache) —
## nie Disk-I/O mitten im Spiel (Latenz!). Eintrag = Liste von [Mesh, Tex].
var _station_pool: Array = []
var _dock_station: Node3D
## Planeten-Texturen fuer Nahvorbeifluege (vorab geladen).
var _planet_tex_cache: Array = []
# Reise v2: Warp-Tunnel-Huellkurve, Nah-Staub, Landmarks, Sonnenaufgang,
# HUD-Reiseroute.
var _tunnel_fx := 0.0
var _dust_mm: MultiMesh
var _dust_seeds: Array = []
var _dust_mat: ShaderMaterial
var _landmarks: Array = []
var _sun_mat: ShaderMaterial
var _galaxy_mat: ShaderMaterial
var _fg_neb_mats: Array = []
var _route_ui: Control
var _route_p := 0.0
var _sunrise := 0.0
const STATION_DEFS := [
	[["station01.obj", "station01_diffuse"]],
	[["station02_base.obj", "station02_base_diffuse"],
		["station02_ring.obj", "station02_ring_diffuse"]],
	[["station03_base.obj", "station03_base_diffuse"],
		["station03_ring.obj", "station03_ring_diffuse"]],
	[["station05.obj", "station05_diffuse"],
		["station05_ring.obj", "station05_ring_diffuse"]],
	[["station06_base.obj", "station06_base_diffuse"],
		["station06_ring.obj", "station06_ring_diffuse"]],
]
var _star_mat: ShaderMaterial
var _nebula_mat: ShaderMaterial
var _nebula_mat2: ShaderMaterial
var _aurora_mat: ShaderMaterial

var _kiai_mix := 0.0
var _red_tp_idx := 0
var _bass := 0.0
var _treble := 0.0
var _bass_avg := 0.0
var _punch := 0.0
var _punch_cooldown := 0.0
var _last_bar := -1
var _star_burst := 0.0
var _fov_kick := 0.0
# Planeten-Referenzen fuer den Bass-Puls.
var _planet_nodes: Array = []
var _last_milestone := 0
var _last_combo_shown := 0
var _ended := false

var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer

var _debug_running := false
var _debug_start_usec := 0

var _hud: CanvasLayer
var _judge_label: Label
var _judge_tween: Tween
var _ur_root: Control
var _ur_avg: ColorRect
var _ur_scale := 1.0
var _ur_ema := 0.0
# Timing-Statistik fuer den Results-Screen (UR + mittlerer Fehler).
var _dt_n := 0
var _dt_sum := 0.0
var _dt_sqsum := 0.0
var _countdown_running := false
var _skip_label: Label
# Tutorial: geplante Erklaer-Stopps {t, title, body} + aktives Panel.
var _tut_steps: Array = []
var _tut_idx := 0
var _tut_panel: Control
# BEAT-GEFUEHL (additiv, unabhaengig vom Effekt-Regler): weiche Huellkurve
# pro Beat/Takt fuer Rand, Hintergrund und Beat-Noten + Sub-Thump-Audio.
var _beat_env := 0.0
var _beat_player: AudioStreamPlayer
# Lane-Highlight (gedrueckte Spur leuchtet) + Judgement-Farbe der Pads.
var _lane_held: Array[bool] = [false, false, false, false]
var _lane_glow_mats: Array = []
var _pad_judge_col: Array = []
# Multiplayer: Live-Scoreboard (links) + Sende-Takt + Endscreen-Rangliste.
var _mp_board: VBoxContainer
var _mp_send_t := 0.0
var _mp_rank_box: VBoxContainer
var _mp_last_rank := -1
var _combo_label: Label
var _acc_label: Label
var _grade_label: Label
var _score_label: Label
var _miss_label: Label
var _notes_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _bottom_fill: ColorRect
var _hp_fill: ColorRect
var _pause_menu: Control
var _song_len_ms := 1.0


func _ready() -> void:
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	# Mania: AR egal, nur Scroll-Speed. Tutorial: deutlich gemuetlicheres
	# Anflug-Tempo, damit Einsteiger jede Note kommen sehen.
	var scroll := Settings.mania_scroll
	if GameSession.tutorial:
		scroll = minf(scroll, 1.0) * 0.65
	core.setup(_beatmap, -1.0, scroll)
	core.note_spawned.connect(_on_note_spawned)
	core.note_judged.connect(_on_note_judged)
	core.hold_started.connect(_on_hold_started)
	core.lane_pressed.connect(_on_lane_pressed)
	core.finished.connect(func(_s): _show_results(false))

	_glow_shader = load("res://shaders/glow_dot.gdshader")
	_ring_shader = load("res://shaders/hit_ring.gdshader")
	_extract_theme_color()
	_preload_stations()
	_build_world()
	_build_hud()
	_build_screen_fx()
	_build_route_ui()
	_build_flight_plan()
	_build_galaxy_chapters()
	_build_sound()
	_beat_player = AudioStreamPlayer.new()
	_beat_player.stream = Sfx.beat_thump_stream()
	_beat_player.bus = "Master"
	_beat_player.volume_db = -16.0
	add_child(_beat_player)
	_whoosh_player = AudioStreamPlayer.new()
	_whoosh_player.stream = Sfx.whoosh_stream()
	_whoosh_player.bus = "Master"
	_whoosh_player.volume_db = -13.0
	add_child(_whoosh_player)
	if GameSession.tutorial:
		core.no_fail = true
		_build_tutorial_steps()
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		_run_smoke_test()
		return
	if OS.get_cmdline_args().has("--shot-results"):
		# Harness: sofort den Endscreen zeigen und abfotografieren.
		# Tutorial-Flag verhindert, dass der Fake-Score gespeichert wird.
		GameSession.tutorial = true
		core.n_max = 214
		core.n300 = 91
		core.n200 = 12
		core.n100 = 3
		core.n50 = 1
		core.n_miss = 4
		core.score = 923412
		core.max_combo = 412
		core.combo = 0
		_dt_n = 300
		_dt_sum = 950.0
		_dt_sqsum = 90000.0
		_show_results(false)
		_capture_results_shot()
	elif OS.get_cmdline_args().has("--shot"):
		_capture_after_first_note()
	else:
		# START-COUNTDOWN: exakt 3 Sekunden (3-2-1, je 1s) bevor es losgeht —
		# Finger auf die Tasten, kein kalter Einstieg.
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)


func _load_beatmap() -> bool:
	if not GameSession.has_selection():
		return false
	var imp := OszImporter.import(GameSession.osz_path)
	if not imp.ok:
		return false
	_beatmap = null
	for d in imp.difficulties:
		if d.beatmap.version_name() == GameSession.difficulty_version:
			_beatmap = d.beatmap
			break
	if _beatmap == null and not imp.difficulties.is_empty():
		_beatmap = imp.difficulties[0].beatmap
	if _beatmap == null or _beatmap.hit_objects.is_empty() or not _beatmap.is_mania():
		return false
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		# Garantierter Vorlauf: manche Maps legen die erste Note direkt an den
		# Songanfang — dann stand sie beim Start schon fast am Ring. Die erste
		# Note bekommt IMMER ihre volle Anflugzeit plus Reaktionspuffer;
		# fehlt Zeit, wird sie als Lead-In-Stille vor den Song gelegt.
		var scroll := Settings.mania_scroll
		if GameSession.tutorial:
			scroll = minf(scroll, 1.0) * 0.65
		var preempt := ManiaCore.BASE_PREEMPT / clampf(scroll, 0.5, 3.0)
		var lead := _beatmap.audio_lead_in()
		var first_t: float = _beatmap.hit_objects[0].time
		var need := preempt + 600.0
		if first_t + lead < need:
			lead = need - first_t
		SyncClock.play(stream, lead)
		_use_audio = true
	return true


func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - 1000.0


func _extract_theme_color() -> void:
	var tex := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.resize(32, 24, Image.INTERPOLATE_BILINEAR)
	var acc := Vector2.ZERO
	var total_w := 0.0
	for y in 24:
		for x in 32:
			var c := img.get_pixel(x, y)
			var w := c.s * c.v
			acc += Vector2(cos(c.h * TAU), sin(c.h * TAU)) * w
			total_w += w
	if total_w < 4.0 or acc.length() < 1.0:
		return
	var hue := fposmod(atan2(acc.y, acc.x) / TAU, 1.0)
	# Satt in der Farbe, aber gedrosselt in der Helligkeit — Entsaettigung
	# wuerde alles nur weisser (= greller) machen.
	_theme_col = Color.from_hsv(hue, 0.72, 0.84)
	_theme_kiai = Color.from_hsv(fposmod(hue + 0.5, 1.0), 0.78, 0.86)


# ---------------------------------------------------------------------------
# Weltaufbau: Highway + Schiff + Sterne
# ---------------------------------------------------------------------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.004, 0.010)
	# Bewusst gezaehmt: weniger Bloom-Spill, damit nichts grell ausbrennt.
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	# Kamera: hinter/ueber dem Schiff, leicht nach unten auf den Highway.
	_camera = Camera3D.new()
	# Etwas hoeher + staerker geneigt: mehr Draufsicht, das Feld wirkt tiefer
	# und die Notenabstaende bleiben besser lesbar.
	_camera.position = Vector3(0, 1.78, 6.8)
	_camera.rotation_degrees = Vector3(-15.2, 0, 0)
	_camera.fov = 72.0
	_camera.current = true
	add_child(_camera)

	# Strecken-Traeger: ALLES Spielgeschehen haengt hier drunter und wird als
	# Ganzes geneigt/gerollt (Flug + Loopings) — Kamera bleibt fix.
	_world = Node3D.new()
	add_child(_world)

	# KEINE Innen-Schienen mehr (verdeckten bei Notenhagel die Sicht) —
	# nur Aussenkanten als Streckenrand (hell, bass-reaktiv).
	for sx in [-3.6, 3.6]:
		var edge := MeshInstance3D.new()
		var ebox := BoxMesh.new()
		ebox.size = Vector3(0.10, 0.03, absf(Z_FAR) + 8.0)
		edge.mesh = ebox
		edge.position = Vector3(sx, ROAD_Y, (Z_FAR + Z_LINE) * 0.5 + 2.0)
		var em := _emissive_mat(_theme_col, 0.7)
		_edge_mats.append(em)
		edge.material_override = em
		_world.add_child(edge)

	# ON-FIRE-Kanten: prozedurale Flammenwaende ueber beiden Streckenraendern.
	# Unsichtbar bis der Spieler sie sich mit hoher Accuracy "verdient".
	var fire_shader: Shader = load("res://shaders/rail_fire.gdshader")
	for sx in [-3.6, 3.6]:
		var fmesh := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(absf(Z_FAR) + 8.0, 1.15)
		fmesh.mesh = fq
		var fmat := ShaderMaterial.new()
		fmat.shader = fire_shader
		fmat.set_shader_parameter("base_color",
				_theme_col.lerp(Color(1.0, 0.55, 0.2), 0.65))
		fmat.set_shader_parameter("intensity", 0.0)
		fmesh.material_override = fmat
		fmesh.position = Vector3(sx, ROAD_Y + 0.56, (Z_FAR + Z_LINE) * 0.5 + 2.0)
		fmesh.rotation_degrees = Vector3(0, 90, 0)
		_fire_mats.append(fmat)
		_world.add_child(fmesh)

	# Kein durchgehender Querbalken mehr (stoerte optisch) — die Receptor-Pads
	# selbst markieren den Hit-Moment. _line_mat bleibt als Puls-Traeger fuer
	# die Beat-Werte bestehen und wird nur noch auf die Pads gespiegelt.
	_line_mat = _emissive_mat(Color(1, 1, 1), 1.4)

	# Receptor-Pads auf der Linie + Tasten-Labels davor.
	for i in RAIL_X.size():
		var pad := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.44
		tor.outer_radius = 0.58
		tor.rings = 128
		tor.ring_segments = 48
		pad.mesh = tor
		pad.position = Vector3(RAIL_X[i], ROAD_Y + 0.02, Z_LINE)
		var pm := _emissive_mat(_pad_color(i), 0.8)
		_pad_mats.append(pm)
		_pad_flash.append(0.0)
		pad.material_override = pm
		_world.add_child(pad)
		_pad_nodes.append(pad)

		# Lane-Highlight: transparente Bahn, leuchtet solange die Taste
		# gedrueckt ist (Standard-Mania-Feedback).
		var lg := MeshInstance3D.new()
		var lq := QuadMesh.new()
		# Exakt von der Hit-Linie bis zum Horizont — vorher fehlten vorne
		# ~3 Einheiten, der Balken "startete" sichtbar hinter dem Ring.
		lq.size = Vector2(1.5, absf(Z_FAR - Z_LINE))
		lg.mesh = lq
		lg.rotation_degrees = Vector3(-90, 0, 0)
		lg.position = Vector3(RAIL_X[i], ROAD_Y + 0.006, (Z_LINE + Z_FAR) * 0.5)
		var lgm := StandardMaterial3D.new()
		lgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var lane_c := _pad_color(i)
		lgm.albedo_color = Color(lane_c.r, lane_c.g, lane_c.b, 0.0)
		lg.material_override = lgm
		_world.add_child(lg)
		_lane_glow_mats.append(lgm)
		_pad_judge_col.append(_pad_color(i))

		var label := Label3D.new()
		label.text = OS.get_keycode_string(Settings.key_lanes[i])
		# Hohe Font-Aufloesung bei gleicher Weltgroesse — kein Pixelbrei.
		label.font_size = 96
		label.pixel_size = 0.0015
		label.outline_size = 40
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.modulate = Color(0.75, 0.8, 0.9, 0.75)
		label.no_depth_test = true
		label.position = Vector3(RAIL_X[i], ROAD_Y + 0.03, Z_LINE + 0.55)
		label.rotation_degrees = Vector3(-55, 0, 0)
		_world.add_child(label)

	_build_ship()
	_build_horizon()
	_build_starfield()


## Hitzonen-Farbe: bei "Effekte: Aus" neutral grau statt Songfarbe.
func _pad_color(i: int) -> Color:
	if _fx_level() <= 0.0:
		return CLEAN_PAD
	return _lane_color(i)


func _lane_color(i: int) -> Color:
	# Innen hell, aussen Themenfarbe — Spuren sofort unterscheidbar.
	var inner := i == 1 or i == 2
	return _theme_col.lerp(Color(1, 1, 1), 0.5 if inner else 0.15)


func _build_ship() -> void:
	# COCKPIT-Perspektive: Die Kamera IST das Schiff — kein Modell verdeckt
	# die Mitte. Dieser unsichtbare Node ist nur der Laser-Ursprung (unten
	# aus dem Off, wie ein Sternenjaeger-Bug).
	_ship = Node3D.new()
	_ship.position = Vector3(0, ROAD_Y - 0.4, SHIP_Z + 2.6)
	_world.add_child(_ship)


func _build_horizon() -> void:
	# Kein Fluchtpunkt-Blob mehr (sah stoerend aus) — der Nebel traegt den
	# Himmel. Hier liegt nur noch die Beat-Wellen-Ebene.

	# Beat-WELLEN statt Tick-Linien: eine Leuchtwelle rollt pro Beat ueber den
	# Highway und trifft die Abfanglinie exakt auf dem Schlag.
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(8.4, absf(Z_FAR) + 6.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, (Z_FAR + Z_LINE) * 0.5)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://shaders/road_wave.gdshader")
	_road_mat.set_shader_parameter("base_color", _theme_col)
	road.material_override = _road_mat
	_world.add_child(road)


func _build_starfield() -> void:
	# KOSMOS-Traeger: alles Himmlische haengt hier drunter und kann als
	# Ganzes rollen/banken/sinken, ohne die Bahn anzufassen.
	_cosmos = Node3D.new()
	add_child(_cosmos)
	# Breites, hash-gestreutes Sternenfeld (kein "abgeschnittener" Rand)
	# mit unterschiedlichen Sterngroessen.
	_star_mm = MultiMesh.new()
	_star_mm.transform_format = MultiMesh.TRANSFORM_3D
	_star_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	_star_mm.mesh = q
	_star_mm.instance_count = 160
	for i in 160:
		var h1 := _hash01(float(i) * 12.9898)
		var h2 := _hash01(float(i) * 78.233)
		var h3 := _hash01(float(i) * 39.425)
		var h4 := _hash01(float(i) * 5.393)
		var x := (h1 - 0.5) * 68.0
		var y := h2 * 20.0 - 2.5
		var z0 := h3 * 60.0
		_star_seeds.append(Vector3(x, y, z0))
		_star_scales.append(0.5 + h4 * 1.7)
		# Farbmix: meist kuehles Weissblau, ein paar warme + Songfarben-Sterne.
		var ch := _hash01(float(i) * 91.7)
		var star_col := Color(0.75, 0.85, 1.0)
		if ch > 0.85:
			star_col = Color(1.0, 0.78, 0.55)
		elif ch > 0.70:
			star_col = _theme_col.lerp(Color(1, 1, 1), 0.5)
		_star_mm.set_instance_color(i, star_col)
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _star_mm
	_star_mat = ShaderMaterial.new()
	_star_mat.shader = _glow_shader
	_star_mat.set_shader_parameter("base_color", Color(1, 1, 1))
	_star_mat.set_shader_parameter("intensity", 0.35)
	inst.material_override = _star_mat
	_cosmos.add_child(inst)

	# Nebel v2: zwei Parallaxe-Ebenen (fern: gross + ruhig, nah: feiner und
	# schneller driftend) — Domain-Warp-Wolken, Milchstrasse, Sternenstaub.
	var neb := MeshInstance3D.new()
	var nq := QuadMesh.new()
	nq.size = Vector2(150, 54)
	neb.mesh = nq
	_nebula_mat = ShaderMaterial.new()
	_nebula_mat.shader = load("res://shaders/space_bg.gdshader")
	_nebula_mat.set_shader_parameter("col_a", _theme_col)
	_nebula_mat.set_shader_parameter("col_b", _theme_kiai)
	_nebula_mat.set_shader_parameter("scale", 1.0)
	_nebula_mat.set_shader_parameter("star_amount", 1.0)
	neb.material_override = _nebula_mat
	neb.position = Vector3(0, 7.5, Z_FAR - 9.0)
	_cosmos.add_child(neb)
	var neb2 := MeshInstance3D.new()
	var nq2 := QuadMesh.new()
	nq2.size = Vector2(140, 46)
	neb2.mesh = nq2
	_nebula_mat2 = ShaderMaterial.new()
	_nebula_mat2.shader = load("res://shaders/space_bg.gdshader")
	_nebula_mat2.set_shader_parameter("col_a", _theme_col.lerp(Color(1, 1, 1), 0.15))
	_nebula_mat2.set_shader_parameter("col_b", _theme_kiai)
	_nebula_mat2.set_shader_parameter("scale", 2.3)
	_nebula_mat2.set_shader_parameter("alpha_mul", 0.45)
	_nebula_mat2.set_shader_parameter("star_amount", 0.0)
	neb2.material_override = _nebula_mat2
	neb2.position = Vector3(4.0, 6.0, Z_FAR - 7.0)
	_cosmos.add_child(neb2)

	# Horizont-Glow: weicher Schein in Songfarbe, verankert die Strecke.
	var hg := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(110, 16)
	hg.mesh = hq
	var hm := ShaderMaterial.new()
	hm.shader = _glow_shader
	hm.set_shader_parameter("base_color", _theme_col)
	hm.set_shader_parameter("intensity", 0.13)
	hg.material_override = hm
	hg.position = Vector3(0, 1.2, Z_FAR - 4.0)
	_cosmos.add_child(hg)
	_horizon_mat = hm

	# AURORA: wehende Polarlicht-Vorhaenge ueber dem Horizont.
	var au := MeshInstance3D.new()
	var aq := QuadMesh.new()
	aq.size = Vector2(95, 13)
	au.mesh = aq
	_aurora_mat = ShaderMaterial.new()
	_aurora_mat.shader = load("res://shaders/aurora.gdshader")
	_aurora_mat.set_shader_parameter("col_a", _theme_col.lerp(Color(0.3, 1.0, 0.7), 0.4))
	_aurora_mat.set_shader_parameter("col_b", _theme_kiai)
	au.material_override = _aurora_mat
	au.position = Vector3(0, 6.8, Z_FAR - 5.5)
	_cosmos.add_child(au)

	# FERNE SPIRALGALAXIE: das Astro-Wahrzeichen, gegenueber vom
	# Schwarzen Loch — rotiert unmerklich, atmet mit dem Kiai.
	var gal := MeshInstance3D.new()
	var galq := QuadMesh.new()
	galq.size = Vector2(13.5, 9.5)
	gal.mesh = galq
	_galaxy_mat = ShaderMaterial.new()
	_galaxy_mat.shader = load("res://shaders/spiral_galaxy.gdshader")
	_galaxy_mat.set_shader_parameter("col_arm",
		_theme_col.lerp(Color(0.6, 0.72, 1.0), 0.5))
	gal.material_override = _galaxy_mat
	gal.position = Vector3(-21.0, 14.5, Z_FAR - 11.0)
	gal.rotation_degrees = Vector3(0, 0, -14)
	_cosmos.add_child(gal)

	# VORDERGRUND-NEBELFETZEN: zwei nahe, schnell driftende Schleier
	# seitlich — geben dem Raum zwischen Bahn und Fernnebel Tiefe.
	for fgi in 2:
		var fgn := MeshInstance3D.new()
		var fgq := QuadMesh.new()
		fgq.size = Vector2(62, 24)
		fgn.mesh = fgq
		var fgm := ShaderMaterial.new()
		fgm.shader = load("res://shaders/space_bg.gdshader")
		fgm.set_shader_parameter("col_a", _theme_col.lerp(Color(0.1, 0.08, 0.16), 0.45))
		fgm.set_shader_parameter("col_b", _theme_kiai)
		fgm.set_shader_parameter("scale", 3.6)
		fgm.set_shader_parameter("alpha_mul", 0.20)
		fgm.set_shader_parameter("star_amount", 0.0)
		fgn.material_override = fgm
		fgn.position = Vector3(-24.0 if fgi == 0 else 24.0, 4.5, Z_FAR + 13.0)
		_fg_neb_mats.append(fgm)
		_cosmos.add_child(fgn)

	# ATMOSPHAEREN-KANTE: duennes, helles Scattering-Band direkt am Horizont
	# (wie der Erdrand von der ISS) — verankert die Bahn im Raum.
	var edge_band := MeshInstance3D.new()
	var ebq := QuadMesh.new()
	ebq.size = Vector2(120, 1.7)
	edge_band.mesh = ebq
	var ebm := ShaderMaterial.new()
	ebm.shader = _glow_shader
	ebm.set_shader_parameter("base_color", _theme_col.lerp(Color(1, 1, 1), 0.55))
	ebm.set_shader_parameter("intensity", 0.12)
	edge_band.material_override = ebm
	edge_band.position = Vector3(0, 0.55, Z_FAR - 3.7)
	_cosmos.add_child(edge_band)

	# STERNHAUFEN: zwei weiche Kugelhaufen-Glows als Fern-Deko.
	for chi in 2:
		var cl2 := MeshInstance3D.new()
		var clq := QuadMesh.new()
		var cls := 1.7 if chi == 0 else 2.6
		clq.size = Vector2(cls, cls)
		cl2.mesh = clq
		var clm := ShaderMaterial.new()
		clm.shader = _glow_shader
		clm.set_shader_parameter("base_color", Color(0.95, 0.93, 0.85))
		clm.set_shader_parameter("intensity", 0.16)
		cl2.material_override = clm
		cl2.position = Vector3(7.5 if chi == 0 else -26.0,
				16.0 if chi == 0 else 8.0, Z_FAR - 10.5)
		_cosmos.add_child(cl2)

	# SCHWARZES LOCH: Gravitationslinse verbiegt Nebel/Sterne dahinter,
	# heisse Akkretionsscheibe rotiert (Kiai beschleunigt sie).
	var bh := MeshInstance3D.new()
	var bhq := QuadMesh.new()
	bhq.size = Vector2(7.5, 7.5)
	bh.mesh = bhq
	_bh_mat = ShaderMaterial.new()
	_bh_mat.shader = load("res://shaders/black_hole.gdshader")
	bh.material_override = _bh_mat
	bh.position = Vector3(19.5, 13.5, Z_FAR - 6.5)
	_cosmos.add_child(bh)

	# GOD-RAYS: Lichtfaecher aus dem Fluchtpunkt, atmet im Takt.
	var gr := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(64, 26)
	gr.mesh = gq
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = load("res://shaders/god_rays.gdshader")
	_rays_mat.set_shader_parameter("base_color", _theme_col.lerp(Color(1, 1, 1), 0.3))
	gr.material_override = _rays_mat
	gr.position = Vector3(0, 2.5, Z_FAR - 3.6)
	_cosmos.add_child(gr)

	# Ferne Planeten: ECHTE Textur-Planeten (Community-PBR-Maps, seed-gewaehlt
	# pro Map) + prozeduraler Ringplanet. Nachtseiten zeigen Stadtlichter/Lava.
	var planet_shader: Shader = load("res://shaders/planet.gdshader")
	var tex_pool := ["earth_like", "ocean_planet", "desert_planet",
			"lava_planet", "mining_planet", "ecumenopolis"]
	var seed_p: int = hash(GameSession.osu_filename)
	var anchor_tex: String = tex_pool[seed_p % tex_pool.size()]
	var dest_tex: String = tex_pool[(seed_p / 7 + 2) % tex_pool.size()]
	if dest_tex == anchor_tex:
		dest_tex = tex_pool[(seed_p / 7 + 3) % tex_pool.size()]
	var pdefs := [
		# [Pos, Groesse, Basis, Baender, Atmosphaere, Bandfreq, Seed, Ring, Tex]
		# Grosser Planet tief am Horizont (Anker der Komposition) …
		[Vector3(-15.5, 4.8, Z_FAR - 7.5), 10.5, Color(0.72, 0.56, 0.40),
			Color(0.47, 0.32, 0.22), Color(0.95, 0.78, 0.58), 11.0, 3.7, 0.0,
			anchor_tex],
		# … Ringplanet hoch rechts (bleibt prozedural — der Ring-Look sitzt) …
		[Vector3(14.5, 10.0, Z_FAR - 6.0), 5.8, Color(0.62, 0.72, 0.86),
			Color(0.34, 0.46, 0.66), Color(0.70, 0.82, 1.0), 6.0, 9.2, 0.85, ""],
		# … und ein ECHTER Mond nahe dem Anker.
		[Vector3(-9.0, 8.6, Z_FAR - 5.0), 1.7, Color(0.62, 0.60, 0.58),
			Color(0.42, 0.41, 0.40), Color(0.75, 0.75, 0.78), 3.0, 21.4, 0.0,
			"moon_like"],
		# ZIEL der Reise: echter Planet, steigt ueber die Songdauer auf.
		[Vector3(2.0, -2.5, Z_FAR - 8.0), 6.5, Color(0.45, 0.62, 0.60),
			Color(0.28, 0.42, 0.44), Color(0.65, 0.95, 0.90), 8.0, 14.6, 0.9,
			dest_tex],
	]
	for pdef in pdefs:
		var planet := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(pdef[1], pdef[1])
		planet.mesh = pq
		var pm := ShaderMaterial.new()
		pm.shader = planet_shader
		pm.set_shader_parameter("base_col", pdef[2])
		pm.set_shader_parameter("band_col", pdef[3])
		pm.set_shader_parameter("atmo_col", pdef[4])
		pm.set_shader_parameter("band_freq", pdef[5])
		pm.set_shader_parameter("seed", pdef[6])
		pm.set_shader_parameter("ring_amount", pdef[7])
		# Echte Textur zuweisen, wenn das Asset existiert (sonst prozedural).
		if pdef.size() > 8 and str(pdef[8]) != "":
			var dpath := "res://assets_game/planets/%s_diffuse.webp" % str(pdef[8])
			if ResourceLoader.exists(dpath):
				pm.set_shader_parameter("use_texture", 1.0)
				pm.set_shader_parameter("tex_diffuse", load(dpath))
				var epath := "res://assets_game/planets/%s_emission.webp" % str(pdef[8])
				if ResourceLoader.exists(epath):
					pm.set_shader_parameter("tex_emission", load(epath))
				if str(pdef[8]) == "earth_like" or str(pdef[8]) == "ocean_planet":
					pm.set_shader_parameter("clouds_amount", 0.85)
				# Manche Reisen haben Ringplaneten — aus dem Seed gewuerfelt.
				if str(pdef[8]) != "moon_like" \
						and _hash01(float(seed_p % 997) + float(pdef[6])) > 0.55:
					pm.set_shader_parameter("ring_amount", 0.85)
		planet.material_override = pm
		planet.position = pdef[0]
		_cosmos.add_child(planet)
		_planet_mats.append(pm)
		_planet_nodes.append(planet)
		_planet_base.append(pdef[0])

	# DOCKING-STATION: schwebt im Finale neben dem Zielplaneten ein.
	if not _station_pool.is_empty():
		_dock_station = _build_station_node(
				_station_pool[hash(GameSession.osu_filename) % _station_pool.size()])
		_dock_station.position = Vector3(9.5, 4.5, Z_FAR - 5.0)
		_dock_station.visible = false
		_cosmos.add_child(_dock_station)

	# NAH-STAUB: feine Partikel ziehen dicht an der Kamera vorbei —
	# nahe Parallaxe ist das staerkste Tempo-Signal (strikt seitlich).
	_dust_mm = MultiMesh.new()
	_dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	var dq := QuadMesh.new()
	dq.size = Vector2(0.055, 0.055)
	_dust_mm.mesh = dq
	_dust_mm.instance_count = 90
	for di in 90:
		var dh1 := _hash01(float(di) * 17.3)
		var dh2 := _hash01(float(di) * 5.9)
		var dh3 := _hash01(float(di) * 47.1)
		var dside := -1.0 if dh1 < 0.5 else 1.0
		_dust_seeds.append(Vector3(dside * (5.2 + dh2 * 9.0), dh3 * 8.0, dh1 * 42.0))
		_dust_mm.set_instance_transform(di, Transform3D(Basis.IDENTITY, Vector3(0, -100, 0)))
	var dinst := MultiMeshInstance3D.new()
	dinst.multimesh = _dust_mm
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = _glow_shader
	_dust_mat.set_shader_parameter("base_color", Color(0.85, 0.9, 1.0))
	_dust_mat.set_shader_parameter("intensity", 0.0)
	dinst.material_override = _dust_mat
	add_child(dinst)

	# LANDMARKS: jedes Galaxie-Kapitel hat ein Erkennungszeichen am Himmel.
	# L0: Asteroidenguertel-Band.
	var belt := MultiMeshInstance3D.new()
	var belt_mm := MultiMesh.new()
	belt_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bq3 := QuadMesh.new()
	bq3.size = Vector2(0.5, 0.5)
	belt_mm.mesh = bq3
	belt_mm.instance_count = 40
	for bi in 40:
		var bx := -30.0 + 60.0 * _hash01(float(bi) * 7.7)
		var by := 10.5 + sin(bx * 0.22) * 1.3 + (_hash01(float(bi) * 3.1) - 0.5) * 0.8
		var bs := 0.4 + _hash01(float(bi) * 11.3) * 1.1
		belt_mm.set_instance_transform(bi, Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * bs), Vector3(bx, by, Z_FAR - 12.0)))
	belt.multimesh = belt_mm
	var belt_mat := StandardMaterial3D.new()
	belt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	belt_mat.albedo_color = Color(0.30, 0.29, 0.30)
	belt.material_override = belt_mat
	belt.visible = false
	_cosmos.add_child(belt)
	_landmarks.append(belt)
	# L1: Doppelstern (zwei umeinander kreisende Sonnen).
	var binary := Node3D.new()
	binary.position = Vector3(13.0, 12.0, Z_FAR - 10.0)
	for bi2 in 2:
		var star := MeshInstance3D.new()
		var sq3 := QuadMesh.new()
		sq3.size = Vector2(2.6 if bi2 == 0 else 1.7, 2.6 if bi2 == 0 else 1.7)
		star.mesh = sq3
		var smat3 := ShaderMaterial.new()
		smat3.shader = _glow_shader
		smat3.set_shader_parameter("base_color",
			Color(1.0, 0.72, 0.35) if bi2 == 0 else Color(0.55, 0.75, 1.0))
		smat3.set_shader_parameter("intensity", 0.75)
		star.material_override = smat3
		star.position = Vector3(-1.6 if bi2 == 0 else 2.0, 0, 0)
		binary.add_child(star)
	binary.visible = false
	_cosmos.add_child(binary)
	_landmarks.append(binary)
	_apply_landmark(0)

	# SONNENAUFGANG: waechst ueber das letzte Galaxie-Kapitel hinterm Ziel.
	var sun2 := MeshInstance3D.new()
	var sunq := QuadMesh.new()
	sunq.size = Vector2(22, 22)
	sun2.mesh = sunq
	_sun_mat = ShaderMaterial.new()
	_sun_mat.shader = _glow_shader
	_sun_mat.set_shader_parameter("base_color", Color(1.0, 0.88, 0.62))
	_sun_mat.set_shader_parameter("intensity", 0.0)
	sun2.material_override = _sun_mat
	sun2.position = Vector3(3.0, 3.2, Z_FAR - 9.5)
	_cosmos.add_child(sun2)

	# Glut-Partikel-Pool: Funken fallen EXAKT auf den Beat (Spawn an der
	# Beat-Kante), schweben langsam zu Boden.
	_ember_mm = MultiMesh.new()
	_ember_mm.transform_format = MultiMesh.TRANSFORM_3D
	var eq := QuadMesh.new()
	eq.size = Vector2(0.09, 0.09)
	_ember_mm.mesh = eq
	_ember_mm.instance_count = 48
	for i in 48:
		_ember_pos.append(Vector3(0, -100, 0))
		_ember_vel.append(0.0)
		_ember_life.append(0.0)
		_ember_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, -100, 0)))
	var einst := MultiMeshInstance3D.new()
	einst.multimesh = _ember_mm
	var emat := ShaderMaterial.new()
	emat.shader = _glow_shader
	emat.set_shader_parameter("base_color", _theme_col)
	emat.set_shader_parameter("intensity", 0.9)
	einst.material_override = emat
	einst.set_meta("mat", emat)
	add_child(einst)
	_ember_mat = emat


func _hash01(x: float) -> float:
	return fposmod(sin(x) * 43758.5453, 1.0)


func _emissive_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.03)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


# ---------------------------------------------------------------------------
# Noten auf den Schienen (konstante Geschwindigkeit -> klares Timing)
# ---------------------------------------------------------------------------

func _note_z(hit_time: float, t: float) -> float:
	return Z_LINE - (hit_time - t) / core.preempt * (Z_LINE - Z_FAR)


func _on_note_spawned(index: int) -> void:
	var obj := _beatmap.hit_objects[index] as ManiaNote
	# Notenfarben KLAR vom Spielfeld getrennt (in allen Effekt-Stufen):
	# Hitzone/Umgebung tragen die Songfarbe — normale Noten sind
	# weiss-dominant (leichter Songfarb-Stich), Holds immer amber.
	var clean := _fx_level() <= 0.0
	var col: Color
	if clean:
		col = CLEAN_HOLD if obj.is_hold else CLEAN_NOTE
	elif obj.is_hold:
		col = CLEAN_HOLD
	else:
		col = _theme_col.lerp(Color(1, 1, 1), 0.75)
		if _beatmap.is_kiai(obj.time):
			col = _theme_kiai.lerp(Color(1, 1, 1), 0.55)

	var root := Node3D.new()
	# 2D-KONSISTENZ: Die Note ist ein FLACHER Kreis wie das Pad — sie gleitet
	# als Hit-Circle heran und landet exakt AUF dem Pad-Ring (kein 3D-Ball).
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.37
	cyl.bottom_radius = 0.37
	cyl.height = 0.04
	disc.mesh = cyl
	var disc_mat := _emissive_mat(col, 0.6 if clean else 1.0)
	disc.material_override = disc_mat
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var rtor := TorusMesh.new()
	rtor.inner_radius = 0.42
	rtor.outer_radius = 0.54
	rtor.rings = 96
	rtor.ring_segments = 40
	ring.mesh = rtor
	var rim := _emissive_mat(col.lerp(Color(1, 1, 1), 0.35 if clean else 0.6),
		0.9 if clean else 1.4)
	ring.material_override = rim
	root.add_child(ring)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.05, 2.05)
	glow.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = _glow_shader
	gm.set_shader_parameter("base_color", col)
	gm.set_shader_parameter("intensity", 0.32 if clean else 0.68)
	glow.material_override = gm
	glow.rotation_degrees = Vector3(-90, 0, 0)
	glow.position = Vector3(0, -0.02, 0)
	root.add_child(glow)
	root.position = Vector3(RAIL_X[obj.column], ROAD_Y + 0.32, _note_z(obj.time, _time_ms()))
	_world.add_child(root)

	# Hold: BREITE Leuchtbahn (fast Spurbreite, halbtransparent) mit hellem
	# Kernstreifen — unuebersehbar, Project-Sekai-Style.
	var beam: MeshInstance3D = null
	if obj.is_hold:
		beam = MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.02, 0.035, 1.0)
		beam.mesh = bb
		var bm := _emissive_mat(col, 0.38 if clean else 0.55)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(col.r, col.g, col.b, 0.30 if clean else 0.34)
		beam.material_override = bm
		var beam_core := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.30, 0.05, 1.0)
		beam_core.mesh = cb
		beam_core.material_override = _emissive_mat(col.lerp(Color(1, 1, 1), 0.55), 1.1)
		beam.add_child(beam_core)
		_world.add_child(beam)

	# Landelicht: weicher Reflexions-Spot unter der Drohne auf der Road —
	# verbindet Note und Spur optisch (Tiefenanker).
	var spot := MeshInstance3D.new()
	var sq2 := QuadMesh.new()
	sq2.size = Vector2(1.1, 0.8)
	spot.mesh = sq2
	var sm2 := ShaderMaterial.new()
	sm2.shader = _glow_shader
	sm2.set_shader_parameter("base_color", col)
	sm2.set_shader_parameter("intensity", 0.10 if clean else 0.20)
	spot.material_override = sm2
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.position = Vector3(0, -0.30, 0)
	root.add_child(spot)

	# Kometen-Schweif: gestreckter Glow hinter der Drohne (Speed-Gefuehl).
	var trail := MeshInstance3D.new()
	var trail_q := QuadMesh.new()
	trail_q.size = Vector2(0.55, 1.7)
	trail.mesh = trail_q
	var trail_m := ShaderMaterial.new()
	trail_m.shader = _glow_shader
	trail_m.set_shader_parameter("base_color", col)
	trail_m.set_shader_parameter("intensity", 0.18 if clean else 0.35)
	trail.material_override = trail_m
	trail.rotation_degrees = Vector3(-90, 0, 0)
	trail.position = Vector3(0, -0.05, -1.05)
	root.add_child(trail)

	_notes[index] = { "root": root, "glow": gm, "rim": rim, "beam": beam,
		"on_beat": _is_on_beat(obj.time) }


func _on_note_judged(index: int, result: Dictionary) -> void:
	var q: int = result.quality
	if q == ManiaCore.Quality.MISS:
		_play_miss()
		# 3 Misses in Folge: kurzer Schadens-Glitch (Screen-FX).
		_miss_streak += 1
		if _miss_streak >= 3:
			_glitch = 1.0
	else:
		_miss_streak = 0
		_play_hit([1.0, 1.0, 0.944, 0.891, 0.794][q])
	var col: int = result.get("column", 0)
	var sub := ""
	if q >= ManiaCore.Quality.GOOD and q != ManiaCore.Quality.MISS and not result.get("hold_end", false):
		sub = "SLOW" if result.get("late", false) else "FAST"
	if result.get("hold_end", false) and bool(result.get("held", false)):
		_fire_laser(col, Vector3(RAIL_X[col], ROAD_Y + 0.32, Z_LINE))
		_pad_flash[col] = 1.0
	if result.get("hold_end", false) and not result.get("held", true):
		sub = "DROP"
	if col < _pad_judge_col.size():
		_pad_judge_col[col] = QUALITY_COLOR[q]
	_spawn_popup(col, QUALITY_TEXT[q], QUALITY_COLOR[q], sub)
	_ur_tick(result)
	if _notes.has(index):
		var entry: Dictionary = _notes[index]
		_notes.erase(index)
		var node: Node3D = entry.root
		if q != ManiaCore.Quality.MISS:
			# Hit-Lighting IMMER exakt am Ring — nicht an der Notenposition
			# (die haengt beim fruehen Druecken noch weit vor der Linie).
			_fire_laser(col, Vector3(RAIL_X[col], ROAD_Y + 0.32, Z_LINE),
					[1.0, 1.0, 0.85, 0.7, 0.55][q])
			_pad_flash[col] = 1.0
			node.queue_free()
		else:
			# Drohne rauscht am Schiff vorbei und verglimmt rot.
			(entry.rim as StandardMaterial3D).emission = Color(1.0, 0.25, 0.25)
			var tw := create_tween()
			tw.tween_property(node, "position:z", SHIP_Z + 6.0, 0.35)
			tw.parallel().tween_property(node, "scale", Vector3.ONE * 0.3, 0.35)
			tw.tween_callback(node.queue_free)
		if entry.beam != null:
			(entry.beam as MeshInstance3D).queue_free()
	if q == ManiaCore.Quality.MISS:
		_last_milestone = 0
	else:
		var c := core.combo
		if (c == 25 or c == 50 or (c >= 100 and c % 100 == 0)) and c != _last_milestone:
			_last_milestone = c
			_fov_kick = 3.0
			# Milestone-Belohnung: Sternschnuppe zieht ueber den Himmel.
			if c >= 50 and _fx_level() > 0.0:
				_spawn_shooting_star(c)
			# OVERDRIVE: ab Combo 100 schlaegt alle 100 der Blitz ein.
			if c >= 100 and c % 100 == 0:
				_trigger_overdrive()
	_update_hud()


## OVERDRIVE: Blitzschlag bei grossen Combos — weisser Flash, Kamera-Beben,
## die Abfanglinie elektrisiert 2 Sekunden, Farben kippen auf Komplementaer.
func _trigger_overdrive() -> void:
	var fx := _fx_level()
	if fx <= 0.0:
		return
	_overdrive = 2.0 * fx
	_shake = 0.18 * fx
	_shock = 0.0
	# Vollbild-Blitz.
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.05)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.12)
	tw.tween_callback(flash.queue_free)
	# (Zackenblitze entfernt — nervten; Schockwelle + Puls reichen.)


func _spawn_bolt(seed_i: int) -> void:
	var im := ImmediateMesh.new()
	var x := (_hash01(float(seed_i) * 17.71 + 3.0) - 0.5) * 6.4
	var top := Vector3(x, 5.5, Z_LINE - 3.0 - _hash01(float(seed_i) * 7.3) * 8.0)
	var bottom := Vector3(x + (_hash01(float(seed_i) * 29.1) - 0.5) * 1.6, ROAD_Y, top.z)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := 7
	for s in range(steps + 1):
		var k := float(s) / float(steps)
		var p := top.lerp(bottom, k)
		p.x += (_hash01(float(seed_i) * 31.7 + float(s) * 5.1) - 0.5) * 0.9 * (1.0 - absf(k - 0.5) * 2.0 + 0.2)
		im.surface_set_color(Color(1, 1, 1, 0.55))
		im.surface_add_vertex(p)
	im.surface_end()
	var mesh := MeshInstance3D.new()
	mesh.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material_override = m
	_world.add_child(mesh)
	var tw := create_tween()
	tw.tween_interval(0.06 + _hash01(float(seed_i) * 3.3) * 0.22)
	tw.tween_callback(mesh.queue_free)


func _on_hold_started(index: int, _quality: int) -> void:
	_play_hit(1.0)
	if _notes.has(index):
		var obj := _beatmap.hit_objects[index] as ManiaNote
		_pad_flash[obj.column] = 1.0
		_fire_laser(obj.column, Vector3(RAIL_X[obj.column], ROAD_Y + 0.32, Z_LINE))


func _on_lane_pressed(column: int, hit: bool) -> void:
	_pad_flash[column] = maxf(_pad_flash[column], 0.6 if hit else 0.3)


## Hit-Lighting am Ring: Kern-Blitz + flache Shockwave-Welle ueber die Bahn
## + kurzer Licht-Saeulen-Burst + Funken. power skaliert mit dem Judgement
## (MAX gross und hell, 50er dezent). Bei Effekte=Aus bleibt nur der cleane
## Kern-Blitz + eine kleine Welle.
func _fire_laser(column: int, target: Vector3, power: float = 1.0) -> void:
	var col := _pad_color(column)
	var fx := _fx_level()

	# Kern-Blitz (Billboard-Glow direkt am Ring).
	var flash := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	flash.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = _glow_shader
	fm.set_shader_parameter("base_color", col.lerp(Color(1, 1, 1), 0.30))
	var peak := (1.1 if fx <= 0.0 else 1.8) * power
	fm.set_shader_parameter("intensity", peak)
	flash.material_override = fm
	flash.position = target
	flash.rotation_degrees = Vector3(-9, 0, 0)
	_world.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * (1.4 + 0.5 * power), 0.15)
	tw.parallel().tween_method(
		func(v): fm.set_shader_parameter("intensity", v), peak, 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

	# Weicher Halo hinter dem Kern: groesser, schwaecher, langsamer — gibt
	# dem Einschlag Tiefe statt nur eines flachen Blitzes.
	var halo := MeshInstance3D.new()
	var hq2 := QuadMesh.new()
	hq2.size = Vector2(2.3, 2.3)
	halo.mesh = hq2
	var hm2 := ShaderMaterial.new()
	hm2.shader = _glow_shader
	hm2.set_shader_parameter("base_color", col)
	hm2.set_shader_parameter("intensity", peak * 0.30)
	halo.material_override = hm2
	halo.position = target + Vector3(0, 0, -0.05)
	halo.rotation_degrees = Vector3(-9, 0, 0)
	_world.add_child(halo)
	var htw := create_tween()
	htw.tween_property(halo, "scale", Vector3.ONE * 1.6, 0.24)
	htw.parallel().tween_method(
		func(v): hm2.set_shader_parameter("intensity", v), peak * 0.30, 0.0, 0.24)
	htw.tween_callback(halo.queue_free)

	# Shockwave: flacher Ring rollt vom Einschlag ueber die Bahn nach aussen.
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(2.5, 2.5)
	ring.mesh = rq
	var rm := ShaderMaterial.new()
	rm.shader = _ring_shader
	rm.set_shader_parameter("base_color", col.lerp(Color(1, 1, 1), 0.45))
	var rpeak := (0.8 if fx <= 0.0 else 1.5) * power
	rm.set_shader_parameter("intensity", rpeak)
	rm.set_shader_parameter("radius", 0.06)
	ring.material_override = rm
	ring.position = Vector3(target.x, ROAD_Y + 0.02, target.z)
	ring.rotation_degrees = Vector3(-90, 0, 0)
	_world.add_child(ring)
	var rtw := create_tween().set_parallel(true)
	rtw.tween_method(func(v): rm.set_shader_parameter("radius", v), 0.06, 0.46, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rtw.tween_method(func(v): rm.set_shader_parameter("intensity", v), rpeak, 0.0, 0.26)
	rtw.chain().tween_callback(ring.queue_free)

	if fx <= 0.0:
		return

	# Licht-Saeule: kurzer vertikaler Burst, der aus dem Einschlag aufsteigt.
	var beam := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.62, 2.1)
	beam.mesh = bq
	var bm := ShaderMaterial.new()
	bm.shader = _glow_shader
	bm.set_shader_parameter("base_color", col)
	var bpeak := 0.9 * power * fx
	bm.set_shader_parameter("intensity", bpeak)
	beam.material_override = bm
	beam.position = Vector3(target.x, ROAD_Y + 1.0, target.z)
	_world.add_child(beam)
	var btw := create_tween().set_parallel(true)
	btw.tween_property(beam, "position:y", ROAD_Y + 1.7, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	btw.tween_property(beam, "scale:y", 1.5, 0.22)
	btw.tween_method(func(v): bm.set_shader_parameter("intensity", v), bpeak, 0.0, 0.22)
	btw.chain().tween_callback(beam.queue_free)

	# Funken springen aus dem Einschlag (Anzahl nach Judgement + FX-Level).
	var n_sparks := 2 + int(3.0 * power * fx)
	for i in n_sparks:
		var sp := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(0.16, 0.16)
		sp.mesh = sq
		var sm := ShaderMaterial.new()
		sm.shader = _glow_shader
		sm.set_shader_parameter("base_color", col.lerp(Color(1, 1, 1), 0.6))
		sm.set_shader_parameter("intensity", 1.4)
		sp.material_override = sm
		sp.position = target
		_world.add_child(sp)
		var ang := randf() * TAU
		var dist := 0.45 + randf() * 0.6
		var dest := target + Vector3(cos(ang) * dist,
				0.3 + randf() * 0.6, sin(ang) * 0.25)
		var stw := create_tween().set_parallel(true)
		stw.tween_property(sp, "position", dest, 0.26) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		stw.tween_method(func(v): sm.set_shader_parameter("intensity", v), 1.4, 0.0, 0.26)
		stw.chain().tween_callback(sp.queue_free)


func _spawn_popup(_column: int, text: String, col: Color, sub: String = "") -> void:
	# Mini-Judgement zentral (klein, ueber der UR-Bar) statt Popups auf den
	# Noten — die Spielflaeche bleibt frei.
	if _judge_label == null:
		return
	_judge_label.text = text if sub == "" else "%s · %s" % [text, sub]
	_judge_label.add_theme_color_override("font_color", col)
	if _judge_tween != null and _judge_tween.is_valid():
		_judge_tween.kill()
	_judge_label.modulate.a = 0.95
	_judge_label.scale = Vector2.ONE * 1.12
	_judge_label.pivot_offset = Vector2(160, 13)
	_judge_tween = create_tween()
	_judge_tween.set_parallel(true)
	_judge_tween.tween_property(_judge_label, "scale", Vector2.ONE, 0.08)
	_judge_tween.tween_property(_judge_label, "modulate:a", 0.0, 0.25).set_delay(0.30)


func _ur_tick(result: Dictionary) -> void:
	# Timing-Tick auf der UR-Bar (nur Hits mit bekanntem Fehler).
	if _ur_root == null or not result.has("dt"):
		return
	var dt: float = result.dt
	var q: int = result.quality
	if q == ManiaCore.Quality.MISS:
		return
	_dt_n += 1
	_dt_sum += dt
	_dt_sqsum += dt * dt
	var x := clampf(dt * _ur_scale, -70.0, 70.0)
	var tick := ColorRect.new()
	tick.position = Vector2(x - 1.0, 114)
	tick.size = Vector2(2, 13)
	tick.color = QUALITY_COLOR[q]
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ur_root.add_child(tick)
	var tw := create_tween()
	tw.tween_property(tick, "modulate:a", 0.0, 2.2)
	tw.tween_callback(tick.queue_free)
	# Trend-Pfeil: gleitender Mittelwert (frueh/spaet auf einen Blick).
	_ur_ema = lerpf(_ur_ema, dt, 0.2)
	_ur_avg.position.x = clampf(_ur_ema * _ur_scale, -70.0, 70.0) - 1.5


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended or GameSession.is_replay:
		return
	if event is InputEventKey and not event.echo:
		var lane := Settings.lane_for_key(event.keycode)
		if lane >= 0:
			var t := _time_ms()
			_recorded.append({ "t": t, "lane": lane, "down": event.pressed })
			_lane_held[lane] = event.pressed
			if event.pressed:
				core.key_down(lane, t)
			else:
				core.key_up(lane, t)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running:
			_toggle_pause(true)
		return
	# R = Map sofort neu starten (im Spiel UND auf dem Results-Screen),
	# ausser R ist als Lane-Taste belegt.
	if event.keycode == KEY_R and Settings.lane_for_key(KEY_R) == -1 			and not Lobby.active:
		_restart()
		return
	# Intro-Skip: Leertaste springt lange Vorlaeufe bis kurz vor die erste
	# Note (nur wenn Space keine Lane-Taste ist).
	if event.keycode == KEY_SPACE and not _ended \
			and Settings.lane_for_key(KEY_SPACE) == -1 and _can_skip_intro():
		if Lobby.active and Lobby.in_game:
			Lobby.vote_skip()  # Multiplayer: springt erst, wenn ALLE druecken
		else:
			_do_skip()


## Liegt ein Zeitpunkt auf dem Beat-Raster der Map? (±30 ms)
func _is_on_beat(time_ms: float) -> bool:
	var tp = null
	for p in _beatmap.timing_points:
		if p.uninherited and p.time <= time_ms + 1.0:
			tp = p
	if tp == null or tp.beat_length <= 0.0:
		return false
	var ph := fposmod(time_ms - tp.time, tp.beat_length)
	return ph < 30.0 or ph > tp.beat_length - 30.0


## Globaler Effekt-Faktor aus den Einstellungen (Aus/Dezent/Voll).
func _fx_level() -> float:
	match Settings.tunnel_intensity:
		0:
			return 0.0
		1:
			return 0.45
	return 1.0


func _do_skip() -> void:
	SyncClock.seek_ms(_beatmap.hit_objects[0].time - 2200.0)
	if _skip_label != null:
		_skip_label.visible = false


func _can_skip_intro() -> bool:
	if GameSession.tutorial:
		return false
	if _beatmap == null or _beatmap.hit_objects.is_empty() or not _use_audio:
		return false
	return _beatmap.hit_objects[0].time - _time_ms() > 4500.0


# ---------------------------------------------------------------------------
# Frame-Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or _beatmap == null:
		return
	var t := _time_ms()
	# Replay: aufgezeichnete Inputs mit ihren ORIGINAL-Zeitstempeln einspeisen.
	if GameSession.is_replay:
		var evs := GameSession.replay_events
		while _replay_idx < evs.size() and float(evs[_replay_idx].t) <= t:
			var ev: Dictionary = evs[_replay_idx]
			_replay_idx += 1
			_lane_held[int(ev.lane)] = bool(ev.down)
			if bool(ev.down):
				core.key_down(int(ev.lane), float(ev.t))
			else:
				core.key_up(int(ev.lane), float(ev.t))
	core.update(t)
	# Tutorial: vor jedem neuen Element anhalten und erklaeren.
	if GameSession.tutorial and not _ended and not _countdown_running \
			and _tut_idx < _tut_steps.size() and t >= float(_tut_steps[_tut_idx].t):
		_show_tut_step(_tut_steps[_tut_idx])
		return

	for index in _notes:
		var obj := _beatmap.hit_objects[index] as ManiaNote
		var entry: Dictionary = _notes[index]
		var root: Node3D = entry.root
		var head_t := obj.time
		if core.active_hold(obj.column) == index:
			head_t = maxf(obj.time, t)
		root.position = Vector3(RAIL_X[obj.column], ROAD_Y + 0.32, _note_z(head_t, t))
		# Lock-On: im Fenster leuchtet die Drohne weiss auf.
		var until := obj.time - t
		var lock: bool = absf(until) <= core.w50
		# Beat-Anticipation: Noten, die AUF dem Beat landen, glimmen im
		# Anflug leicht heller und pulsieren mit der Beat-Huellkurve.
		var rim_base := 1.3
		if bool(entry.get("on_beat", false)):
			rim_base = 1.5 + _beat_env * 0.5
		(entry.rim as StandardMaterial3D).emission_energy_multiplier = 2.6 if lock else rim_base
		(entry.glow as ShaderMaterial).set_shader_parameter("intensity", 1.6 if lock else 0.9)
		var beam: MeshInstance3D = entry.beam
		if beam != null:
			var z1: float = root.position.z
			var z2 := _note_z(obj.end_time(), t)
			beam.position = Vector3(RAIL_X[obj.column], ROAD_Y + 0.28, (z1 + z2) * 0.5)
			# HOLD-GLOW: saettigt in ~0,6 s (auch lange Holds gluehen sofort
			# sichtbar), pulsiert mit dem Beat; der Kern wird weiss-heiss und
			# das Pad leuchtet dauerhaft, solange gehalten wird.
			var wide := 1.0
			if core.active_hold(obj.column) == index:
				var held_t: float = clampf((t - obj.time) / 600.0, 0.0, 1.0)
				wide = 1.0 + held_t * 0.45
				var bmat := beam.material_override as StandardMaterial3D
				if bmat != null:
					bmat.emission_energy_multiplier = 0.55 \
							+ held_t * (1.7 + _beat_env * 0.9)
					bmat.albedo_color.a = 0.34 + held_t * 0.30
				if beam.get_child_count() > 0:
					var cmat := (beam.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
					if cmat != null:
						cmat.emission_energy_multiplier = 1.1 \
								+ held_t * (2.4 + _beat_env * 1.2)
				_pad_flash[obj.column] = maxf(_pad_flash[obj.column], 0.5 + held_t * 0.3)
			beam.scale = Vector3(wide, 1, maxf(absf(z1 - z2), 0.05))

	for c in core.columns:
		_pad_flash[c] = move_toward(_pad_flash[c], 0.0, delta * 5.0)
		# Gedrueckte Spur leuchtet dezent auf (schnell rein, weich raus) —
		# in den Einstellungen abschaltbar.
		if c < _lane_glow_mats.size():
			var lm: StandardMaterial3D = _lane_glow_mats[c]
			var target := 0.10 if _lane_held[c] and Settings.lane_glow else 0.0
			lm.albedo_color.a = move_toward(lm.albedo_color.a, target,
				delta * (1.4 if _lane_held[c] else 0.5))

	# Globaler Effekt-Faktor (Einstellungen: Aus/Dezent/Voll).
	var fx := _fx_level()

	# Laser abklingen.
	# OVERDRIVE abklingen lassen.
	_overdrive = maxf(_overdrive - delta, 0.0)
	_shake = maxf(_shake - delta * 1.4, 0.0)
	# Weiche Beat-Huellkurve (Release ~380 ms — atmet, statt zu blitzen).
	_beat_env = maxf(_beat_env - delta * 2.6, 0.0)

	# NOTENDICHTE (naechste Sekunde) -> Intensitaets-Surge bei Bursts;
	# keine Note in 2.5s -> Break/Cruise, Rueckkehr mit Flash.
	var upcoming := 0
	var next_gap := 999999.0
	while _scan_from < _beatmap.hit_objects.size() 			and (_beatmap.hit_objects[_scan_from].time < t - 300.0 or core.is_judged(_scan_from)):
		_scan_from += 1
	for oi in range(_scan_from, _beatmap.hit_objects.size()):
		var obj2 := _beatmap.hit_objects[oi]
		if obj2.time < t or core.is_judged(oi):
			continue
		next_gap = minf(next_gap, obj2.time - t)
		if obj2.time <= t + 1000.0:
			upcoming += 1
		else:
			break
	_density = lerpf(_density, clampf(float(upcoming) / 8.0, 0.0, 1.0), minf(delta * 4.0, 1.0))
	var now_break := next_gap > 2500.0
	if _in_break and not now_break:
		# Comeback: kurzer Flash + Glut-Salve kuendigt den Wiedereinstieg an.
		_line_flash = 1.0
		_fov_kick = maxf(_fov_kick, 2.0)
		_star_burst = 1.0
	_in_break = now_break

	# --- Beat-exakte FX-Simulation ---
	_nebula_kick = maxf(_nebula_kick - delta * 2.0, 0.0)
	_line_flash = maxf(_line_flash - delta * 4.0, 0.0)
	# Glut faellt langsam, schwebt seitlich, verglimmt.
	var burn := clampf((float(core.combo) - 150.0) / 200.0, 0.0, 1.0)
	for i in _ember_pos.size():
		if _ember_life[i] <= 0.0:
			continue
		_ember_life[i] -= delta
		var pos := _ember_pos[i]
		pos.y -= _ember_vel[i] * delta
		pos.x += sin(t * 0.002 + float(i) * 1.7) * 0.35 * delta
		_ember_pos[i] = pos
		var sc := clampf(_ember_life[i] / 2.2, 0.05, 1.0)
		if _ember_life[i] <= 0.0 or pos.y < ROAD_Y - 0.2:
			_ember_life[i] = 0.0
			_ember_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0, -100, 0)))
		else:
			_ember_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), pos))
	if _ember_mat != null:
		_ember_mat.set_shader_parameter("base_color", _theme_col.lerp(Color(1.0, 0.5, 0.15), burn))
	# Rand-Glut: Combo laesst den Bildschirmrand gluehen, ab ~150 brennt er.
	if _vignette_mat != null:
		# HP-HERZSCHLAG: kritische HP faerbt den Bildschirmrand rot.
		var alarm := clampf(maxf(0.35 - core.hp, 0.0) * 2.2, 0.0, 1.0)
		_vignette_mat.set_shader_parameter("intensity",
			(clampf(float(core.combo) / 200.0, 0.0, 1.0) * 0.4 + _kiai_mix * 0.15
			+ _overdrive * 0.2) * fx + alarm * 0.3 + _beat_env * 0.07)
		_vignette_mat.set_shader_parameter("burn", burn)
		_vignette_mat.set_shader_parameter("glow_color", _theme_col.lerp(Color(1.0, 0.18, 0.16), alarm))
		_vignette_mat.set_shader_parameter("t", t / 1000.0)

	# Musikreaktivitaet.
	var bass_raw := SyncClock.band_energy(30.0, 250.0)
	var treble_raw := SyncClock.band_energy(2000.0, 8000.0)
	_bass = maxf(bass_raw, move_toward(_bass, 0.0, delta * 2.2))
	_treble = maxf(treble_raw, move_toward(_treble, 0.0, delta * 3.0))
	_bass_avg = lerpf(_bass_avg, bass_raw, minf(delta * 1.5, 1.0))
	_punch_cooldown = maxf(_punch_cooldown - delta, 0.0)
	if bass_raw - _bass_avg > 0.16 and _punch_cooldown <= 0.0:
		_punch = 1.0
		_punch_cooldown = 0.12
		_fov_kick = maxf(_fov_kick, 1.2)
	_punch = move_toward(_punch, 0.0, delta * 6.0)
	var bar := _current_bar(t)
	if bar != _last_bar:
		_last_bar = bar
		_star_burst = 1.0
	_star_burst = move_toward(_star_burst, 0.0, delta * 2.5)

	var pulse: float = maxf(maxf(_beat_pulse(t), _bass * 1.05), _punch)
	var kiai_now := _beatmap.is_kiai(t)
	_kiai_mix = move_toward(_kiai_mix, 1.0 if kiai_now else 0.0, delta * 2.5)

	# Beat-/Takt-Wellen: Phase 0..1, Welle trifft die Linie exakt auf dem Schlag.
	var tps := _beatmap.timing_points
	var ri := _red_tp_idx
	while ri >= 0 and ri < tps.size() and not tps[ri].uninherited:
		ri -= 1
	if ri >= 0 and ri < tps.size() and tps[ri].beat_length > 0.0 and _road_mat != null:
		var bl: float = tps[ri].beat_length
		var bar_len: float = bl * float(maxi(tps[ri].meter, 1))
		_road_mat.set_shader_parameter("beat_phase", fposmod(t - tps[ri].time, bl) / bl)
		_road_mat.set_shader_parameter("bar_phase", fposmod(t - tps[ri].time, bar_len) / bar_len)
		_road_mat.set_shader_parameter("punch", _punch)
		_road_mat.set_shader_parameter("wave_amount", fx)
		_road_mat.set_shader_parameter("energy", 0.5 + (_bass * 0.5 + _kiai_mix * 0.4 + _density * 0.35) * fx)
		# Timing-Tint: haengt der Trend spaet, waermt sich die Strecke leicht
		# auf; zu frueh kuehlt sie ab (peripheres Feedback ohne HUD-Blick).
		var road_col := _theme_col.lerp(_theme_kiai, _kiai_mix)
		var trend := clampf(_ur_ema / 90.0, -1.0, 1.0)
		if trend > 0.0:
			road_col = road_col.lerp(Color(1.0, 0.55, 0.30), trend * 0.16)
		else:
			road_col = road_col.lerp(Color(0.40, 0.70, 1.0), -trend * 0.16)
		_road_mat.set_shader_parameter("base_color", road_col)
		# BEAT-KANTE: alles hier feuert EXAKT auf dem Schlag.
		var beat_idx := int(floor((t - tps[ri].time) / bl))
		if beat_idx != _beat_idx_last:
			_beat_idx_last = beat_idx
			_on_beat_edge(beat_idx)

	# Die ABFANGLINIE pulsiert im Takt — der Hit-Moment ist hoerbar UND sichtbar.
	_line_mat.emission_energy_multiplier = 1.1 + pulse * 1.6 + _punch * 1.0 + _line_flash * 1.3
	_line_mat.emission = Color(1, 1, 1).lerp(_theme_kiai, _kiai_mix * 0.6)
	for i in _pad_mats.size():
		_pad_mats[i].emission_energy_multiplier = (0.45 if fx <= 0.0 else 0.65) \
				+ (pulse * 0.5 + _punch * 0.4 + _line_flash * 0.75) * fx \
				+ _pad_flash[i] * (1.1 if fx <= 0.0 else 1.9)
	for m in _edge_mats:
		m.emission_energy_multiplier = (0.28 if fx <= 0.0 else 0.4) \
				+ (_bass * 1.2 + _punch * 0.9 + _density * 0.6) * fx

	# ON FIRE: ab 97% Acc (und min. 30 gewerteten Noten) zuenden die Kanten —
	# je naeher an 100%, desto hoeher die Flammen. Ab 99.5% kippt das Feuer
	# in weissblaues Perfection-Plasma. Ein Acc-Einbruch loescht es schnell,
	# neu verdienen geht langsam (fuehlt sich wie ein Streak an).
	var fire_j := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	var fire_acc := core.accuracy()
	var fire_target := 0.0
	if fire_j >= 30 and fire_acc >= 0.97:
		fire_target = clampf((fire_acc - 0.97) / 0.025, 0.35, 1.0)
	_fire_level = move_toward(_fire_level, fire_target,
			delta * (0.7 if fire_target > _fire_level else 2.6))
	_fire_heat = move_toward(_fire_heat,
			1.0 if (fire_j >= 30 and fire_acc >= 0.995) else 0.0, delta * 1.4)
	for fmat3 in _fire_mats:
		fmat3.set_shader_parameter("intensity",
				_fire_level * (0.55 + 0.45 * _beat_env) * fx)
		fmat3.set_shader_parameter("heat", _fire_heat)
		fmat3.set_shader_parameter("t", t / 1000.0)

	# FLUG-CHOREOGRAFIE: Die ganze Strecke steigt/faellt und bankt im Takt
	# (BPM/Kiai skaliert), Bass-Kicks druecken die Nase kurz runter, und bei
	# Combo-Milestones/Kiai-Start gibt's einen Barrel-Roll-Looping.
	# Kamera bleibt fix — Judgement voellig unberuehrt.
	# BPM-SYNC: Die Choreografie folgt Takt-Phrasen statt freier Sinuswellen —
	# gebankt wird ueber 8 Beats, gestiegen ueber 16, Lift ueber 32. Die Welt
	# bewegt sich dadurch MUSIKALISCH, nicht zufaellig.
	# WICHTIG: Neigung HART begrenzen. Kippt die Welt nach oben, hebt sie den
	# Kamerawinkel auf und die Strecke wird brettflach/unlesbar. Nach unten
	# (mehr Draufsicht) ist ok, nach oben fast nichts.
	var beats := _song_beats(t)
	var climb := sin(TAU * beats / 16.0) * (1.0 + _kiai_mix * 0.8) * fx
	var pitch_target := clampf(climb - _punch * 0.5, -2.4, 0.8)
	_pitch_smooth = lerpf(_pitch_smooth, pitch_target, minf(delta * 2.2, 1.0))
	_lift_smooth = lerpf(_lift_smooth, sin(TAU * beats / 32.0) * 0.22 * fx, minf(delta * 2.0, 1.0))
	var bank_deg := sin(TAU * beats / 8.0 + 1.3) * (2.2 + _kiai_mix * 1.4) * fx
	_world.position.y = _lift_smooth
	_world.rotation_degrees = Vector3(_pitch_smooth, 0.0, bank_deg)
	# DROP: Kiai-Start feuert den Warp (Streifen + Flash + Sternen-Schub).
	if kiai_now and not _was_kiai:
		_start_drop_warp()
	_was_kiai = kiai_now

	# OVERDRIVE aktiv: Linie elektrisiert (Flacker), Farben kippen, Kamera bebt.
	# Farben werden pro Frame von der BASIS aus gemischt (kein Aufschaukeln).
	var od := clampf(_overdrive, 0.0, 1.0)
	if _overdrive > 0.0:
		var flicker := _hash01(floor(t * 0.05)) * 2.4
		_line_mat.emission_energy_multiplier += flicker * od * 0.25
	for i in _pad_mats.size():
		var base_col := _pad_color(i)
		if i < _pad_judge_col.size():
			base_col = base_col.lerp(_pad_judge_col[i], clampf(_pad_flash[i], 0.0, 1.0) * 0.65)
		_pad_mats[i].emission = base_col.lerp(_theme_kiai, od * 0.7)
	for em2 in _edge_mats:
		var edge_col := Color(0.45, 0.47, 0.53) if fx <= 0.0 \
				else _theme_col.lerp(_theme_kiai, maxf(od * 0.7, _kiai_mix))
		if fx > 0.0 and _fire_level > 0.0:
			# Brennende Kanten gluehen mit: Glut-Orange, bei Perfection Eisblau.
			var glow_col := Color(1.0, 0.6, 0.25).lerp(Color(0.72, 0.92, 1.0), _fire_heat)
			edge_col = edge_col.lerp(glow_col, _fire_level * 0.7)
		em2.emission = edge_col
	if _shake > 0.0:
		_camera.position.x = sin(t * 0.09) * _shake * 0.14
		_camera.position.y = 1.78 + sin(t * 0.117 + 2.0) * _shake * 0.10
	else:
		_camera.position.x = 0.0
		_camera.position.y = 1.78

	# REISE-UHR: Beat-Schub-Distanz — jeder Downbeat schiebt sichtbar an,
	# dazwischen gleitet man aus. Bei Effekte=Aus laeuft die Reise linear
	# (gleiches Ziel, ohne Ruckeln). Docking bleibt zeitbasiert.
	_travel += delta * ((0.55 + _beat_env * 1.1) if fx > 0.0 else 0.82)
	var journey_p := clampf(_travel * 1000.0 / (_song_len_ms * 0.82), 0.0, 1.0)
	var dock_mix := clampf((t - (_song_len_ms - 5000.0)) / 5000.0, 0.0, 1.0)
	dock_mix = dock_mix * dock_mix * (3.0 - 2.0 * dock_mix)

	_fov_kick = move_toward(_fov_kick, 0.0, delta * 9.0)
	# Beat-Puls im FOV + Mini-Schub der Kamera nach vorn: jeder Downbeat
	# fuehlt sich wie ein Antriebsstoss durchs All an (rein visuell).
	_camera.fov = 72.0 + (_kiai_mix * 5.0 + _bass * 2.6 + _density * 2.0 \
			+ _fov_kick + _beat_env * 1.6) * fx
	_camera.position.z = 6.8 - (_beat_env * 0.10 + _warp_level * 0.25) * fx

	# HYPERSPACE: Der Drop reisst die Sterne ~1.5s zu Lichtfaeden.
	_warp_level = move_toward(_warp_level, 0.0, delta * 0.7)

	# Sterne rasen vorbei — jeder Beat gibt einen Warp-Schub obendrauf,
	# das Docking-Finale bremst die Reise sanft aus.
	_star_scroll += delta * (9.0 * _bpm_factor + (_treble * 20.0 \
			+ _kiai_mix * 10.0 + _star_burst * 30.0 + _beat_env * 26.0 \
			+ _warp_level * 55.0 + _density * 9.0) * fx) \
			* (1.0 - dock_mix * 0.75)
	var warp_stretch := 1.0 + _warp_level * 16.0 * fx
	for i in _star_seeds.size():
		var seed := _star_seeds[i]
		var z := fmod(seed.z + _star_scroll, 60.0) - 52.0
		var basis := Basis.IDENTITY.scaled(Vector3(
				_star_scales[i], _star_scales[i], _star_scales[i] * warp_stretch))
		_star_mm.set_instance_transform(i, Transform3D(basis, Vector3(seed.x, seed.y, z)))

	# GALAXIEN-REISE: aktuelles Kapitel bestimmen — der Wechsel feuert
	# einen Hyperspace-Sprung, die Farbwelt crossfadet butterweich.
	var gal_target := _gal_idx
	for ci in _gal_chapters.size():
		if t >= float(_gal_chapters[ci].t):
			gal_target = ci
	if gal_target != _gal_idx:
		if _gal_idx >= 0 and fx > 0.0:
			_warp_level = 1.0
			_tunnel_fx = 1.0
			_fov_kick = maxf(_fov_kick, 4.0)
		_gal_idx = gal_target
		_apply_landmark(_gal_idx)
	if _gal_idx >= 0 and fx > 0.0:
		var gch: Dictionary = _gal_chapters[_gal_idx]
		var gk := minf(delta * 0.5, 1.0)
		_gal_col = _gal_col.lerp(gch.col, gk)
		_gal_col2 = _gal_col2.lerp(gch.col2, gk)
		_gal_stars = lerpf(_gal_stars, float(gch.stars), gk)
		_gal_scale = lerpf(_gal_scale, float(gch.scale), gk)

	# Spiralgalaxie: traege Rotation, im Kiai etwas heller.
	if _galaxy_mat != null:
		_galaxy_mat.set_shader_parameter("t", t / 1000.0)
		_galaxy_mat.set_shader_parameter("intensity",
			(0.26 + _kiai_mix * 0.13 + _beat_env * 0.04) * maxf(fx, 0.25))
	# Vordergrund-Nebelfetzen driften deutlich schneller (Nah-Parallaxe).
	for fgm2 in _fg_neb_mats:
		fgm2.set_shader_parameter("drift", _nebula_drift * 3.4)
		fgm2.set_shader_parameter("energy", 0.35 + (_bass * 0.3 + _beat_env * 0.2) * fx)

	# SONNENAUFGANG: waechst ueber das letzte Kapitel — Ankunft im Licht.
	_sunrise = 0.0
	if _gal_chapters.size() >= 2 and _gal_idx >= _gal_chapters.size() - 1:
		var last_t := float(_gal_chapters[_gal_chapters.size() - 1].t)
		_sunrise = clampf((t - last_t) / maxf(_song_len_ms - last_t, 1.0), 0.0, 1.0)
	if _sun_mat != null:
		_sun_mat.set_shader_parameter("intensity",
			(_sunrise * 0.34 + dock_mix * 0.14) * fx)
	# HUD-Route + Warp-Tunnel-Huellkurve + Doppelstern-Kreisen.
	_route_p = journey_p
	if _route_ui != null:
		_route_ui.queue_redraw()
	_tunnel_fx = maxf(_tunnel_fx - delta * 0.65, 0.0)
	if _screen_mat != null:
		_screen_mat.set_shader_parameter("warp_tunnel",
			sin(PI * clampf(_tunnel_fx, 0.0, 1.0)) * fx)
	if _landmarks.size() > 1 and is_instance_valid(_landmarks[1]) and _landmarks[1].visible:
		_landmarks[1].rotation.y += delta * 0.35
	# NAH-STAUB: rast mit dem Reisetempo an der Kamera vorbei.
	if _dust_mm != null:
		_dust_mat.set_shader_parameter("intensity",
			(0.16 + _beat_env * 0.10 + _warp_level * 0.4) * fx)
		if fx > 0.0:
			for di2 in _dust_seeds.size():
				var ds: Vector3 = _dust_seeds[di2]
				var dz := fmod(ds.z + _star_scroll * 2.4, 42.0) - 34.0
				_dust_mm.set_instance_transform(di2, Transform3D(
					Basis.IDENTITY, Vector3(ds.x, ds.y, dz)))

	# Nebel driftet und atmet mit Bass/Kiai — und beschleunigt im Beat,
	# als wuerde das Schiff durch die Wolken schieben.
	_nebula_drift += delta * (1.0 + (_beat_env * 1.1 + _kiai_mix * 0.5) * fx) * _bpm_factor
	if _nebula_mat != null:
		_nebula_mat.set_shader_parameter("drift", _nebula_drift)
		_nebula_mat.set_shader_parameter("pulse", _beat_env * (1.0 - dock_mix * 0.5))
		# Farbklima der AKTUELLEN Galaxie; Kiai kippt zur Komplementaerfarbe.
		var jc := _gal_col
		_nebula_mat.set_shader_parameter("col_a",
			jc.lerp(_theme_kiai, _kiai_mix * 0.45))
		_nebula_mat.set_shader_parameter("col_b", _gal_col2)
		# DRAMATURGIE: der Drop reisst den Nebel auf — sternenklarer Blick,
		# nach dem Kiai zieht er wieder zu.
		_nebula_mat.set_shader_parameter("alpha_mul", 1.0 - _kiai_mix * 0.55)
		_nebula_mat.set_shader_parameter("star_amount",
			_gal_stars + _kiai_mix * 0.5)
		_nebula_mat.set_shader_parameter("scale", _gal_scale)
		if _nebula_mat2 != null:
			_nebula_mat2.set_shader_parameter("alpha_mul",
				0.45 * (1.0 - _kiai_mix * 0.6))
		if _aurora_mat != null:
			_aurora_mat.set_shader_parameter("col_a",
				_gal_col.lerp(Color(0.3, 1.0, 0.7), 0.4))
			_aurora_mat.set_shader_parameter("col_b", _gal_col2)
		# NASSE BAHN: der Himmel spiegelt sich Richtung Horizont.
		if _road_mat != null:
			_road_mat.set_shader_parameter("sky_color",
				jc.lerp(_theme_kiai, _kiai_mix).lerp(Color(1.0, 0.85, 0.6), _sunrise * 0.5))
			_road_mat.set_shader_parameter("refl_amount", (0.20 + _beat_env * 0.08) * fx)
		if _nebula_mat2 != null:
			_nebula_mat2.set_shader_parameter("drift", _nebula_drift * 1.8)
			_nebula_mat2.set_shader_parameter("pulse", _beat_env * 0.6)
			_nebula_mat2.set_shader_parameter("energy",
				0.4 + (_bass * 0.4 + _kiai_mix * 0.4) * fx + _beat_env * 0.15)
	# Horizont atmet mit Takt und Bass — verankert den Beat im ganzen Bild.
	if _horizon_mat != null:
		# Beim Docking glueht der Horizont waermer auf — Ankunftslicht.
		_horizon_mat.set_shader_parameter("intensity",
			0.10 + _beat_env * 0.10 + _bass * 0.05 + dock_mix * 0.15 + _sunrise * 0.08)
	if _aurora_mat != null:
		_aurora_mat.set_shader_parameter("drift", t / 1000.0)
		_aurora_mat.set_shader_parameter("pulse", _beat_env)
		for pm2 in _planet_mats:
			pm2.set_shader_parameter("intensity", 0.85 + (_nebula_kick * 0.12 + _bass * 0.08) * fx)
			pm2.set_shader_parameter("t", t / 1000.0)
		_nebula_mat.set_shader_parameter("energy",
			0.5 + (_bass * 0.6 + _kiai_mix * 0.6 + _nebula_kick * 0.4) * fx
			+ _beat_env * 0.22)
	# Planeten atmen mit dem Bass, Sterne glitzern auf Hoehen.
	# REISE-ROUTE: Planeten wandern ueber die Songdauer vorbei; der letzte
	# ist das ZIEL — er steigt auf und schiebt sich im Docking gross mittig.
	for pi in _planet_nodes.size():
		var pn: MeshInstance3D = _planet_nodes[pi]
		if not is_instance_valid(pn):
			continue
		var journey_scale := 1.0
		if pi < _planet_base.size() and pi < PLANET_DRIFT.size():
			var ppos: Vector3 = _planet_base[pi] + PLANET_DRIFT[pi] * journey_p
			if pi == _planet_nodes.size() - 1:
				journey_scale = 0.55 + pow(journey_p, 1.35) * 1.35 + dock_mix * 1.5
				ppos = ppos.lerp(Vector3(0.0, 6.2, Z_FAR - 6.0), dock_mix)
			pn.position = ppos
		pn.scale = Vector3.ONE * journey_scale \
				* (1.0 + (_bass * 0.09 + _nebula_kick * 0.04) * fx)

	# SCREEN-FX: Aberration auf Bass-Kicks, Overdrive-Schockwelle, Glitch.
	if _screen_mat != null:
		if _shock >= 0.0:
			_shock += delta * 1.6
			if _shock > 1.5:
				_shock = -1.0
		_glitch = maxf(_glitch - delta * 2.2, 0.0)
		_screen_mat.set_shader_parameter("aberration",
				(clampf((_bass - 0.5) * 1.2, 0.0, 1.0) + _beat_env * 0.07) * fx)
		_screen_mat.set_shader_parameter("shock", _shock)
		_screen_mat.set_shader_parameter("shock_str", fx)
		_screen_mat.set_shader_parameter("glitch", _glitch * fx)
		_screen_mat.set_shader_parameter("vignette", 0.22 * fx)

	# Schwarzes Loch + God-Rays atmen mit Musik und Reise.
	if _bh_mat != null:
		_bh_mat.set_shader_parameter("t", t / 1000.0)
		_bh_mat.set_shader_parameter("spin", 0.25 + _kiai_mix * 0.9)
		_bh_mat.set_shader_parameter("strength", fx)
	if _rays_mat != null:
		_rays_mat.set_shader_parameter("rot", t / 4300.0)
		_rays_mat.set_shader_parameter("intensity",
				(0.05 + _beat_env * 0.05 + _kiai_mix * 0.04 + dock_mix * 0.22 \
				+ _sunrise * 0.11) * fx)

	# SONNENWANDERUNG: die Lichtrichtung aller Planeten wandert ueber den Song.
	var sun_dir := Vector3(-0.55 + journey_p * 1.15, 0.35 - journey_p * 0.05, 0.75).normalized()
	for pm2 in _planet_mats:
		pm2.set_shader_parameter("light_dir", sun_dir)

	# DOCKING-STATION: gleitet in den letzten Sekunden neben den Zielplaneten,
	# waechst weich mit und rotiert traege (Ankunftsbild).
	if _dock_station != null:
		_dock_station.visible = dock_mix > 0.01 and fx > 0.0
		if _dock_station.visible:
			_dock_station.position = Vector3(9.5, 4.5, Z_FAR - 5.0).lerp(
					Vector3(4.6, 5.2, Z_FAR - 4.0), dock_mix)
			_dock_station.scale = Vector3.ONE * (0.4 + dock_mix * 0.8)
			_dock_station.rotation.y += delta * 0.15

	# FLUGPLAN abarbeiten (Vorbeifluege, Ueberkopf-Roll, Break-Kino).
	while _flight_idx < _flight_plan.size() and t >= float(_flight_plan[_flight_idx].t):
		_run_flight_event(_flight_plan[_flight_idx], t)
		_flight_idx += 1
	# Aktive Vorbeifluege bewegen; kurz vor der Passage bankt der Kosmos weg
	# und das Notlicht der Wracks blinkt.
	var bank_req := 0.0
	for fb in _flybys:
		var fnode: Node3D = fb.node
		if not is_instance_valid(fnode):
			continue
		fnode.position.z += delta * float(fb.speed) * (1.0 + _beat_env * 0.25)
		fnode.rotation.z += delta * float(fb.get("tumble", 0.0))
		fnode.rotation.y += delta * float(fb.get("tumble", 0.0)) * 0.6
		# Beim Naeherkommen nach aussen ziehen — Passage bleibt seitlich sichtbar.
		fnode.position.x += delta * float(fb.side) * 2.0
		if fnode.has_meta("lamp"):
			(fnode.get_meta("lamp") as ShaderMaterial).set_shader_parameter(
				"intensity", 0.35 + 1.0 * float(int(t * 0.004) % 2))
		if fnode.position.z > -16.0 and fnode.position.z < 4.0:
			bank_req = -float(fb.side) * 0.038
		if not bool(fb.whooshed) and fnode.position.z > -7.0:
			fb.whooshed = true
			if _whoosh_player != null and fx > 0.0:
				_whoosh_player.play()
		if fnode.position.z > 18.0:
			fnode.queue_free()
	_flybys = _flybys.filter(func(fb2):
		return is_instance_valid(fb2.node) and fb2.node.position.z <= 18.0)
	_cosmos_bank_target = bank_req

	# KOSMOS-Transform: Roll (Ueberkopf-Flug), Bank (Ausweichen), Lift
	# (Hochziehen) — Pivot nahe dem Fluchtpunkt, Bahn bleibt unberuehrt.
	if fx <= 0.0:
		_cosmos_roll_target = 0.0
		_cosmos_bank_target = 0.0
		_cosmos_lift_target = 0.0
	# BUTTERWEICH: feste Phasen-Dauern + Smoothstep-Easing — der Roll baut
	# sich langsam auf, gleitet und laeuft weich aus (kein Ruck mehr).
	_roll_phase = move_toward(_roll_phase,
			1.0 if _cosmos_roll_target > 0.5 else 0.0, delta / 6.0)
	_cosmos_roll = smoothstep(0.0, 1.0, _roll_phase) * PI
	_lift_phase = move_toward(_lift_phase,
			1.0 if _cosmos_lift_target > 0.1 else 0.0, delta / 4.0)
	_cosmos_lift = smoothstep(0.0, 1.0, _lift_phase) * 2.4
	_cosmos_bank = lerpf(_cosmos_bank, _cosmos_bank_target, minf(delta * 1.1, 1.0))
	if _cosmos != null:
		var piv := Vector3(0, 3.6, Z_FAR * 0.5)
		_cosmos.transform = Transform3D(Basis(Vector3(0, 0, 1), _cosmos_roll + _cosmos_bank),
				piv + Vector3(0, -_cosmos_lift, 0)) * Transform3D(Basis.IDENTITY, -piv)
	if _star_mat != null:
		# Im Hyperspace brennen die Lichtfaeden deutlich heller.
		_star_mat.set_shader_parameter("intensity",
			0.35 + (_treble * 0.30 + _star_burst * 0.15 + _warp_level * 0.5) * fx \
			+ _beat_env * 0.07)

	if _skip_label != null:
		var can_skip: bool = _can_skip_intro() and Settings.lane_for_key(KEY_SPACE) == -1
		_skip_label.visible = can_skip
		if can_skip and Lobby.active and Lobby.in_game:
			_skip_label.text = "LEERTASTE  ·  Intro ueberspringen  (%d/%d)" % [
				Lobby.skip_votes.size(), Lobby.players.size()]
		else:
			_skip_label.text = "LEERTASTE  ·  Intro ueberspringen"
	# Multiplayer: eigenen Live-Score ~4x pro Sekunde teilen.
	if Lobby.active and Lobby.in_game and not _ended:
		_mp_send_t -= delta
		if _mp_send_t <= 0.0:
			_mp_send_t = 0.25
			Lobby.send_score(core.score, core.combo, core.accuracy())
	if core.failed:
		_show_results(true)
	_update_hud()


## Feuert EXAKT auf jeder Beat-Kante: Pad-Pulse, Glut-Spawn, Nebel-Tick,
## Linien-Blitz (staerker auf Takt-Anfaengen).
func _on_beat_edge(beat_idx: int) -> void:
	# Beat-Huellkurve: Taktanfang voll, sonst sanft — plus Sub-Thump (hoerbar
	# UND fuehlbar, uebertoent die Musik nicht).
	var downbeat := beat_idx % 4 == 0
	_beat_env = 1.0 if downbeat else maxf(_beat_env, 0.45)
	if downbeat and _use_audio and _beat_player != null:
		_beat_player.play()
	# Downbeat-Welle: ein Lichtband rollt im Noten-Tempo vom Horizont zur
	# Hit-Linie — der Takt wird als Raumwelle sichtbar.
	if downbeat and _fx_level() > 0.0:
		_spawn_beat_wave()
	# Glut-Funken (mehr bei hoher Combo/Kiai).
	var n := int((3.0 + _kiai_mix * 3.0 + float(mini(core.combo / 100, 3))) * _fx_level())
	for k in n:
		var i := _ember_next % _ember_pos.size()
		_ember_next += 1
		var h := _hash01(float(beat_idx) * 13.7 + float(k) * 3.1)
		var h2 := _hash01(float(beat_idx) * 7.3 + float(k) * 11.9)
		# Glut NUR seitlich der Bahn — nie ueber dem Spielfeld.
		var eside := -1.0 if h < 0.5 else 1.0
		_ember_pos[i] = Vector3(eside * (4.4 + h2 * 3.4), 3.0 + h * 2.5, Z_LINE - 2.0 - h2 * 14.0)
		_ember_vel[i] = 0.5 + h * 0.8
		_ember_life[i] = 1.6 + h2 * 1.2
	# Nebel + Planeten ticken, Linie blitzt (Takt-Anfang staerker).
	_nebula_kick = 1.0
	_line_flash = maxf(_line_flash, 0.6)
	if beat_idx % 4 == 0:
		_line_flash = 1.0
	# Takt-Anfang: der Nebel tickt staerker.
	if beat_idx % 4 == 0:
		_nebula_kick = 1.3
	# Kiai: gelegentliche Sternschnuppe am Himmel.
	if (_kiai_mix > 0.5 and beat_idx % 8 == 4 and _fx_level() > 0.0) \
			or _hash01(float(beat_idx) * 7.77) > 0.94:
		_spawn_shooting_star(beat_idx)


## DROP-Warp beim Kiai-Start: Lichtstreifen rasen an der Kamera vorbei,
## kurzer Flash, Sterne springen auf Warp-Tempo.
func _start_drop_warp() -> void:
	var fx := _fx_level()
	if fx <= 0.0:
		return
	_star_burst = 1.0
	# Hyperspace: Sterne ziehen sich ~1.5s zu Lichtfaeden.
	_warp_level = 1.0
	_fov_kick = maxf(_fov_kick, 5.0)
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 1, 1, 0.5)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.22)
	ftw.tween_callback(flash.queue_free)
	for i in int(14.0 * fx):
		var streak := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.04, 10.0 + _hash01(float(i) * 3.7) * 14.0)
		streak.mesh = box
		var h1 := _hash01(float(i) * 17.3)
		var h2 := _hash01(float(i) * 51.9)
		streak.position = Vector3((h1 - 0.5) * 30.0, h2 * 14.0 - 3.0, Z_FAR * h2)
		streak.material_override = _emissive_mat(_theme_kiai.lerp(Color(1, 1, 1), 0.5), 1.6)
		add_child(streak)
		var tw3 := create_tween()
		tw3.tween_property(streak, "position:z", 14.0, 0.5 + h1 * 0.3) 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw3.tween_callback(streak.queue_free)


func _spawn_shooting_star(seed_i: int) -> void:
	# Sternschnuppe v2: heller Kopf mit langem Glow-Schweif, brennt kurz auf
	# und verglueht beschleunigend (wie ein echter Meteor).
	var h1 := _hash01(float(seed_i) * 4.7)
	var h2 := _hash01(float(seed_i) * 9.3)
	var root := Node3D.new()
	root.position = Vector3((h1 - 0.5) * 40.0, 9.0 + h2 * 6.0, Z_FAR - 4.0)
	add_child(root)
	var trail := MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(4.4, 0.30)
	trail.mesh = tq
	var tm := ShaderMaterial.new()
	tm.shader = _glow_shader
	tm.set_shader_parameter("base_color", Color(0.82, 0.90, 1.0))
	tm.set_shader_parameter("intensity", 0.0)
	trail.material_override = tm
	# Schweif hinter dem Kopf, entgegen der Flugrichtung (links-unten).
	trail.position = Vector3(2.1, 0.74, 0.0)
	trail.rotation_degrees = Vector3(0, 0, 19.5)
	root.add_child(trail)
	var head := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.55, 0.55)
	head.mesh = hq
	var hm := ShaderMaterial.new()
	hm.shader = _glow_shader
	hm.set_shader_parameter("base_color", Color(1, 1, 1))
	hm.set_shader_parameter("intensity", 0.0)
	head.material_override = hm
	root.add_child(head)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "position",
			root.position + Vector3(-13.0, -4.6, 0.0), 1.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v): hm.set_shader_parameter("intensity", v), 0.0, 1.3, 0.22)
	tw.tween_method(func(v): tm.set_shader_parameter("intensity", v), 0.0, 0.55, 0.22)
	tw.chain().tween_method(func(v): hm.set_shader_parameter("intensity", v), 1.3, 0.0, 0.7)
	tw.tween_method(func(v): tm.set_shader_parameter("intensity", v), 0.55, 0.0, 0.7)
	tw.finished.connect(root.queue_free)


## Downbeat-Welle: dezentes Lichtband, das im Noten-Tempo (preempt) vom
## Horizont zur Hit-Linie rollt — Beat als raeumliche Bewegung.
func _spawn_beat_wave() -> void:
	var wave := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(8.6, 1.2)
	wave.mesh = wq
	var wm := ShaderMaterial.new()
	wm.shader = _glow_shader
	# Farbe folgt dem Zustand: Kiai kippt sie zur Komplementaerfarbe,
	# brennende Kanten (On Fire) faerben die Welle in Glut/Plasma.
	var wcol := _theme_col.lerp(_theme_kiai, _kiai_mix)
	if _fire_level > 0.3:
		wcol = wcol.lerp(Color(1.0, 0.6, 0.25).lerp(Color(0.72, 0.92, 1.0), _fire_heat), 0.6)
	wm.set_shader_parameter("base_color", wcol)
	var peak := (0.09 + _kiai_mix * 0.07) * _fx_level()
	wm.set_shader_parameter("intensity", peak)
	wave.material_override = wm
	wave.rotation_degrees = Vector3(-90, 0, 0)
	wave.position = Vector3(0, ROAD_Y + 0.015, Z_FAR + 1.0)
	_world.add_child(wave)
	var dur: float = core.preempt / 1000.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(wave, "position:z", Z_LINE, dur)
	tw.tween_method(func(v): wm.set_shader_parameter("intensity", v), peak, 0.02, dur)
	tw.chain().tween_callback(wave.queue_free)


## Alle Stations-Meshes/Texturen einmalig laden — _spawn_flyby und das
## Docking-Finale greifen nur noch auf den Cache zu (keine Frame-Hitches).
func _preload_stations() -> void:
	_station_pool = []
	for sdef in STATION_DEFS:
		var parts: Array = []
		for p in sdef:
			var mp := "res://assets_game/stations/%s" % str(p[0])
			if not ResourceLoader.exists(mp):
				parts = []
				break
			var tex: Texture2D = null
			var tp := "res://assets_game/stations/%s.webp" % str(p[1])
			if ResourceLoader.exists(tp):
				tex = load(tp)
			parts.append([load(mp), tex])
		if not parts.is_empty():
			_station_pool.append(parts)
	# Planeten-Texturen fuer Nahvorbeifluege cachen.
	for tname in ["earth_like", "ocean_planet", "desert_planet", "lava_planet",
			"mining_planet", "ecumenopolis", "moon_like"]:
		var dp := "res://assets_game/planets/%s_diffuse.webp" % tname
		if ResourceLoader.exists(dp):
			var ep := "res://assets_game/planets/%s_emission.webp" % tname
			_planet_tex_cache.append([load(dp),
				load(ep) if ResourceLoader.exists(ep) else null,
				tname == "earth_like" or tname == "ocean_planet"])


## Stations-Node aus vorab geladenen Teilen bauen (auf ~5 Einheiten normiert).
func _build_station_node(parts: Array) -> Node3D:
	var st := Node3D.new()
	var norm := 0.0
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var mmat := StandardMaterial3D.new()
		mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if part[1] != null:
			mmat.albedo_texture = part[1]
		mmat.albedo_color = Color(0.95, 1.0, 1.1)
		mi.material_override = mmat
		if norm == 0.0:
			var aabb: AABB = (part[0] as Mesh).get_aabb()
			norm = 5.0 / maxf(maxf(aabb.size.x, aabb.size.y),
					maxf(aabb.size.z, 0.001))
		mi.scale = Vector3.ONE * norm
		st.add_child(mi)
	return st


## HUD-REISEROUTE: feine Linie mit Galaxie-Punkten, der Marker wandert
## mit dem Song-Fortschritt — die Reise als sichtbare Route.
func _build_route_ui() -> void:
	_route_ui = Control.new()
	_route_ui.anchor_left = 0.5
	_route_ui.anchor_right = 0.5
	_route_ui.anchor_top = 1.0
	_route_ui.anchor_bottom = 1.0
	_route_ui.offset_left = -120
	_route_ui.offset_right = 120
	_route_ui.offset_top = -30
	_route_ui.offset_bottom = -14
	_route_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_route_ui.draw.connect(_draw_route)
	_hud.add_child(_route_ui)


func _draw_route() -> void:
	if _gal_chapters.is_empty() or _route_ui == null:
		return
	var w := _route_ui.size.x
	var ry := _route_ui.size.y * 0.5
	_route_ui.draw_line(Vector2(0, ry), Vector2(w, ry), Color(1, 1, 1, 0.10), 1.5)
	var dur := maxf(_song_len_ms, 1.0)
	for ci in _gal_chapters.size():
		var rx := clampf(float(_gal_chapters[ci].t) / dur, 0.0, 1.0) * w
		_route_ui.draw_circle(Vector2(rx, ry), 3.0,
			Color(0.2, 0.85, 1.0, 0.9) if ci <= _gal_idx else Color(1, 1, 1, 0.22))
	_route_ui.draw_circle(Vector2(w, ry), 3.0, Color(0.5, 1.0, 0.75, 0.6))
	_route_ui.draw_circle(Vector2(_route_p * w, ry), 4.5, Color(1, 1, 1, 0.9))


## Landmark des aktuellen Kapitels einblenden (Rest verstecken).
func _apply_landmark(idx: int) -> void:
	for li in _landmarks.size():
		if is_instance_valid(_landmarks[li]):
			_landmarks[li].visible = (maxi(idx, 0) % 2) == li


## Fullscreen-Post-FX-Ebene UNTER dem HUD: verzerrt nur das Spielbild,
## alle Anzeigen bleiben gestochen scharf.
func _build_screen_fx() -> void:
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)
	var fx_rect := ColorRect.new()
	fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = load("res://shaders/screen_fx.gdshader")
	# Warp-Streifen in gedimmter Songfarbe statt grellem Weiss.
	_screen_mat.set_shader_parameter("tunnel_color",
		_theme_col.lerp(Color(0.7, 0.8, 1.0), 0.3) * 0.8)
	fx_rect.material = _screen_mat
	fx_layer.add_child(fx_rect)


# ---------------------------------------------------------------------------
# FLUG-CHOREOGRAFIE: deterministisch aus der Map geplant (Phrasengrenzen,
# Kiai-Start, Breaks) und mit dem Dateinamen geseedet — jedes Replay fliegt
# exakt dieselbe Route. Grosse Manoever nur in ruhigen Passagen.
# ---------------------------------------------------------------------------

## Galaxie-Kapitel aus der Map: 3-4 Abschnitte, an den Kiai-Start
## ausgerichtet, Farb-/Nebel-Identitaet aus dem Map-Seed — jede Map ist
## eine eigene, wiedererkennbare Route durch verschiedene Galaxien.
func _build_galaxy_chapters() -> void:
	_gal_chapters = []
	_gal_idx = -1
	_gal_col = _theme_col
	_gal_col2 = _theme_kiai
	if _beatmap == null or _beatmap.hit_objects.is_empty():
		return
	var seed_h: int = hash(GameSession.osu_filename)
	var dur := maxf(_beatmap.duration_ms(), 1.0)
	for tp in _beatmap.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			_bpm_factor = clampf((60000.0 / tp.beat_length) / 140.0, 0.7, 1.5)
			break
	var n_ch := 4 if dur > 90000.0 else 3
	var bounds: Array = []
	for i in n_ch:
		bounds.append(dur * float(i) / float(n_ch))
	# Der Kiai-Start ersetzt die naechstgelegene Grenze (musikalischer Schnitt).
	var scan := 0.0
	while scan < dur:
		if _beatmap.is_kiai(scan):
			var best := 1
			var bd := 1.0e12
			for i in range(1, bounds.size()):
				if absf(float(bounds[i]) - scan) < bd:
					bd = absf(float(bounds[i]) - scan)
					best = i
			bounds[best] = scan
			break
		scan += 400.0
	bounds.sort()
	var base_h := _theme_col.h
	var hue_step := 0.16 + float(seed_h % 23) * 0.008
	for i in bounds.size():
		var hh := fposmod(base_h + float(i) * hue_step, 1.0)
		var sat := 0.45 + 0.25 * _hash01(float(seed_h % 977) + float(i) * 3.3)
		_gal_chapters.append({
			"t": bounds[i],
			"col": Color.from_hsv(hh, sat, 0.95),
			"col2": Color.from_hsv(fposmod(hh + 0.45, 1.0), 0.8, 1.0),
			"stars": 0.6 + _hash01(float(seed_h) + float(i) * 7.7) * 0.9,
			"scale": 0.85 + _hash01(float(seed_h) * 2.0 + float(i)) * 0.9,
		})


func _build_flight_plan() -> void:
	_flight_plan = []
	_flight_idx = 0
	if _beatmap == null or _beatmap.hit_objects.is_empty():
		return
	var bar := 4.0 * 500.0
	for tp in _beatmap.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			bar = tp.beat_length * float(maxi(tp.meter, 1))
			break
	var seed_h: int = hash(GameSession.osu_filename)
	var objs := _beatmap.hit_objects
	var t0: float = objs[0].time
	var t_end: float = objs[objs.size() - 1].time
	# 1) Vorbeifluege an 8-Takt-Grenzen — nur wenn das Fenster ruhig ist.
	var k := 0
	var pt := t0 + bar * 8.0
	while pt < t_end - 4000.0:
		var fkind := (seed_h / 7 + k) % 2
		if k % 5 == 2:
			fkind = 3
		_flight_plan.append({ "t": pt - 2600.0, "type": "flyby",
			"side": (-1.0 if (seed_h + k) % 2 == 0 else 1.0),
			"kind": fkind })
		k += 1
		pt += bar * 8.0
	# 2) Ueberkopf-Roll beim ersten Kiai (6 Takte kopfueber, dann zurueck).
	var kiai_t := -1.0
	var scan := 0.0
	var scan_end := maxf(_beatmap.duration_ms(), 1.0)
	while scan < scan_end:
		if _beatmap.is_kiai(scan):
			kiai_t = scan
			break
		scan += 400.0
	if kiai_t > 0.0:
		_flight_plan.append({ "t": kiai_t, "type": "roll", "on": true })
		_flight_plan.append({ "t": kiai_t + bar * 6.0, "type": "roll", "on": false })
	# 3) Breaks (>4.5s ohne Noten): Hochziehen + Kometensturm.
	for i in range(1, objs.size()):
		var gap: float = objs[i].time - objs[i - 1].time
		if gap > 4500.0:
			_flight_plan.append({ "t": objs[i - 1].time + 600.0,
				"type": "break_show", "until": objs[i].time - 1500.0 })
	_flight_plan.sort_custom(func(a, b): return float(a.t) < float(b.t))


func _window_density(t: float, half: float) -> int:
	var n := 0
	for o in _beatmap.hit_objects:
		if absf(o.time - t) <= half:
			n += 1
	return n


func _run_flight_event(ev: Dictionary, t: float) -> void:
	if _fx_level() <= 0.0:
		return
	match str(ev.type):
		"flyby":
			_spawn_flyby(float(ev.side), int(ev.kind))
		"roll":
			# Nur kopfueber gehen, wenn gerade wenig los ist.
			if bool(ev.on) and _density < 0.85:
				_cosmos_roll_target = PI
			else:
				_cosmos_roll_target = 0.0
		"break_show":
			_cosmos_lift_target = 2.4
			var dur: float = maxf((float(ev.until) - t) / 1000.0, 1.2)
			for i in 7:
				var st := get_tree().create_timer(0.35 * float(i) + 0.2, false)
				var comet_seed := int(t) + i * 41
				st.timeout.connect(func():
					if is_inside_tree() and not _ended:
						_spawn_shooting_star(comet_seed))
			get_tree().create_timer(dur, false).timeout.connect(func():
				if is_inside_tree():
					_cosmos_lift_target = 0.0)


## Wrack/Asteroid: spawnt weit hinten AUSSERHALB des Noten-Korridors und
## rauscht seitlich-oben an der Kamera vorbei.
func _spawn_flyby(side: float, kind: int) -> void:
	var root := Node3D.new()
	# IMMER oben-seitlich: hoch genug ueber dem Horizont und weit genug
	# aussen — die Flugbahn kreuzt NIE den Noten-Korridor.
	root.position = Vector3(side * 11.0, 6.0 + randf() * 2.5, Z_FAR - 16.0)
	_cosmos.add_child(root)
	if kind == 0:
		# WRACK v2: aufgerissener Frachter als BELEUCHTETE Silhouette —
		# unshaded-Materialien mit per-Teil-Helligkeit (die Szene hat kein
		# echtes Licht; Standard-Shading rendert sonst pechschwarz),
		# warme Fensterreihen, Sonnen-Streiflicht, Antenne, Truemmerfeld.
		var hull_col := Color(0.15, 0.17, 0.22)
		var parts := [
			[Vector3(0, 0, 0), Vector3(4.4, 1.3, 1.6), 1.0],
			[Vector3(-1.7, 0.95, 0.0), Vector3(1.5, 0.9, 1.1), 1.35],
			[Vector3(2.1, -0.35, 0.2), Vector3(1.7, 0.8, 1.2), 0.7],
		]
		for part in parts:
			var hull := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[1]
			hull.mesh = bm
			var hmat := StandardMaterial3D.new()
			hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hmat.albedo_color = hull_col * float(part[2])
			hull.material_override = hmat
			hull.position = part[0]
			hull.rotation_degrees = Vector3(randf() * 6.0 - 3.0,
					randf() * 10.0 - 5.0, randf() * 6.0 - 3.0)
			root.add_child(hull)
		# Fensterreihe: warme Lichtpunkte, ein Teil ist "ausgefallen".
		for w in 8:
			if randf() < 0.3:
				continue
			var win := MeshInstance3D.new()
			var wq := QuadMesh.new()
			wq.size = Vector2(0.17, 0.11)
			win.mesh = wq
			var wmat := StandardMaterial3D.new()
			wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wmat.albedo_color = Color(1.0, 0.86, 0.55)
			win.position = Vector3(-1.9 + float(w) * 0.55, 0.12, 0.82)
			root.add_child(win)
		# Abgeknickte Antenne.
		var ant := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.06, 1.5, 0.06)
		ant.mesh = am
		var amat := StandardMaterial3D.new()
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amat.albedo_color = hull_col * 1.2
		ant.material_override = amat
		ant.position = Vector3(1.3, 1.2, 0)
		ant.rotation_degrees = Vector3(0, 0, 34)
		root.add_child(ant)
		# Sonnen-Streiflicht: warmer Glow verkauft die Beleuchtung.
		var sun := MeshInstance3D.new()
		var sq2 := QuadMesh.new()
		sq2.size = Vector2(4.4, 4.4)
		sun.mesh = sq2
		var smat2 := ShaderMaterial.new()
		smat2.shader = _glow_shader
		smat2.set_shader_parameter("base_color", Color(1.0, 0.82, 0.55))
		smat2.set_shader_parameter("intensity", 0.10)
		sun.material_override = smat2
		sun.position = Vector3(-1.6, 0.7, -0.4)
		root.add_child(sun)
		# Truemmerfeld: kleine Fragmente driften um das Wrack.
		for dtri in 5:
			var deb := MeshInstance3D.new()
			var dm := BoxMesh.new()
			var dsz := 0.14 + randf() * 0.24
			dm.size = Vector3(dsz, dsz * 0.7, dsz)
			deb.mesh = dm
			var dmat := StandardMaterial3D.new()
			dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dmat.albedo_color = hull_col * (0.7 + randf() * 0.7)
			deb.material_override = dmat
			deb.position = Vector3((randf() - 0.5) * 6.5,
					(randf() - 0.5) * 4.0, (randf() - 0.5) * 3.0)
			deb.rotation_degrees = Vector3(randf() * 360.0, randf() * 360.0, 0)
			root.add_child(deb)
		var lamp := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.7, 0.7)
		lamp.mesh = lq
		var lmat := ShaderMaterial.new()
		lmat.shader = _glow_shader
		lmat.set_shader_parameter("base_color", Color(1.0, 0.25, 0.2))
		lmat.set_shader_parameter("intensity", 1.0)
		lamp.material_override = lmat
		lamp.position = Vector3(-1.7, 1.7, 0)
		root.add_child(lamp)
		root.set_meta("lamp", lmat)
	elif kind == 2:
		# RAUMSTATION: echtes 3D-Modell (Community-Asset), unshaded texturiert,
		# auf einheitliche Groesse normiert. Fallback: einfacher Ring.
		if not _station_pool.is_empty():
			var st := _build_station_node(
					_station_pool[randi() % _station_pool.size()])
			st.rotation_degrees = Vector3(10, randf() * 360.0, 5)
			root.add_child(st)
		else:
			var ring := MeshInstance3D.new()
			var rt := TorusMesh.new()
			rt.inner_radius = 0.9
			rt.outer_radius = 1.5
			ring.mesh = rt
			var rm2 := StandardMaterial3D.new()
			rm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm2.albedo_color = Color(0.22, 0.25, 0.32)
			ring.material_override = rm2
			root.add_child(ring)
		var plight := MeshInstance3D.new()
		var plq := QuadMesh.new()
		plq.size = Vector2(0.55, 0.55)
		plight.mesh = plq
		var plmat := ShaderMaterial.new()
		plmat.shader = _glow_shader
		plmat.set_shader_parameter("base_color", Color(0.4, 1.0, 0.6))
		plmat.set_shader_parameter("intensity", 1.0)
		plight.material_override = plmat
		plight.position = Vector3(0, 1.4, 0)
		root.add_child(plight)
		root.set_meta("lamp", plmat)
	elif kind == 3 and not _planet_tex_cache.is_empty():
		# PLANETEN-NAHVORBEIFLUG: ein riesiger Textur-Planet zieht
		# majestaetisch knapp am Spielfeld vorbei — der Wow-Moment.
		var ptex: Array = _planet_tex_cache[randi() % _planet_tex_cache.size()]
		var pp3 := MeshInstance3D.new()
		var pq3 := QuadMesh.new()
		var psize := 14.0 + randf() * 6.0
		pq3.size = Vector2(psize, psize)
		pp3.mesh = pq3
		var pmat3 := ShaderMaterial.new()
		pmat3.shader = load("res://shaders/planet.gdshader")
		pmat3.set_shader_parameter("use_texture", 1.0)
		pmat3.set_shader_parameter("tex_diffuse", ptex[0])
		if ptex[1] != null:
			pmat3.set_shader_parameter("tex_emission", ptex[1])
		if bool(ptex[2]):
			pmat3.set_shader_parameter("clouds_amount", 0.85)
		pmat3.set_shader_parameter("seed", randf() * 30.0)
		pmat3.set_shader_parameter("atmo_col", _theme_col.lerp(Color(0.7, 0.85, 1.0), 0.5))
		pp3.material_override = pmat3
		root.add_child(pp3)
		# Weiter aussen + hoeher als Wracks, damit er trotz Groesse nie
		# ueber dem Spielfeld haengt.
		root.position = Vector3(side * 19.0, 9.5 + randf() * 2.0, Z_FAR - 26.0)
	else:
		# ASTEROID: grauer Brocken mit dem Planeten-Shader.
		var rock := MeshInstance3D.new()
		var rq2 := QuadMesh.new()
		var rs := 2.0 + randf() * 2.5
		rq2.size = Vector2(rs, rs)
		rock.mesh = rq2
		var rmat := ShaderMaterial.new()
		rmat.shader = load("res://shaders/planet.gdshader")
		rmat.set_shader_parameter("base_col", Color(0.45, 0.43, 0.41))
		rmat.set_shader_parameter("band_col", Color(0.30, 0.29, 0.28))
		rmat.set_shader_parameter("atmo_col", Color(0.5, 0.5, 0.55))
		rmat.set_shader_parameter("band_freq", 17.0)
		rmat.set_shader_parameter("seed", randf() * 40.0)
		rmat.set_shader_parameter("ring_amount", 0.0)
		rock.material_override = rmat
		root.add_child(rock)
	# Planeten gleiten langsam und lautlos (majestaetisch), Rest rauscht.
	var spd := 16.0 + randf() * 8.0
	var tmb := (randf() - 0.5) * 0.3
	if kind == 3:
		spd = 9.0 + randf() * 3.0
		tmb = 0.0
	_flybys.append({ "node": root, "side": side, "speed": spd,
		"whooshed": kind == 3, "tumble": tmb })


## Fortlaufende Beat-Zahl der Song-Zeit (fuer BPM-synchrone Choreografie).
func _song_beats(t: float) -> float:
	var tps := _beatmap.timing_points
	var i := _red_tp_idx
	while i >= 0 and i < tps.size() and not tps[i].uninherited:
		i -= 1
	if i < 0 or i >= tps.size() or tps[i].beat_length <= 0.0:
		return t / 500.0
	return (t - tps[i].time) / tps[i].beat_length


func _current_bar(t: float) -> int:
	var tps := _beatmap.timing_points
	var i := _red_tp_idx
	while i >= 0 and i < tps.size() and not tps[i].uninherited:
		i -= 1
	if i < 0 or i >= tps.size() or tps[i].beat_length <= 0.0:
		return -1
	var bar_len := tps[i].beat_length * float(maxi(tps[i].meter, 1))
	return int(floor((t - tps[i].time) / bar_len))


func _beat_pulse(t: float) -> float:
	var tps := _beatmap.timing_points
	while _red_tp_idx + 1 < tps.size() and tps[_red_tp_idx + 1].time <= t:
		_red_tp_idx += 1
	var i := _red_tp_idx
	while i >= 0 and not tps[i].uninherited:
		i -= 1
	if i < 0 or tps[i].beat_length <= 0.0:
		return 0.0
	var phase := fposmod(t - tps[i].time, tps[i].beat_length) / tps[i].beat_length
	return pow(1.0 - phase, 2.0)


func _play_hit(pitch: float) -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_hit_player.volume_db = linear_to_db(Settings.hitsound_volume)
	_hit_player.pitch_scale = pitch
	_hit_player.play()


func _play_miss() -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_miss_player.volume_db = linear_to_db(Settings.hitsound_volume)
	_miss_player.play()


func _build_sound() -> void:
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = -7.0
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	_miss_player.volume_db = -6.0
	add_child(_miss_player)


# ---------------------------------------------------------------------------
# HUD / Pause / Results
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_song_len_ms = maxf(_beatmap.duration_ms(), 1.0)

	if GameSession.is_replay:
		var rp := Label.new()
		rp.text = "▶ REPLAY"
		rp.position = Vector2(24, 44)
		rp.add_theme_font_size_override("font_size", 22)
		rp.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_hud.add_child(rp)

	# Bildschirmrand-Glut (Combo-Stufen: gluehen -> brennen), unterste Ebene.
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = load("res://shaders/screen_glow.gdshader")
	_vignette_mat.set_shader_parameter("glow_color", _theme_col)
	vignette.material = _vignette_mat
	_hud.add_child(vignette)

	# Songtitel: klein und dezent oben links (kein fetter Balken mehr in der
	# Mitte), dimmt nach ein paar Sekunden weiter ab.
	var title := Label.new()
	title.text = "%s — %s  ·  %s" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()]
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	title.modulate.a = 0.75
	_hud.add_child(title)
	var ttw := create_tween()
	ttw.tween_interval(8.0)
	ttw.tween_property(title, "modulate:a", 0.35, 1.5)

	# Zeit: klein oben rechts.
	_time_label = Label.new()
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.offset_left = -240
	_time_label.offset_right = -20
	_time_label.offset_top = 14
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.85, 0.85))
	_hud.add_child(_time_label)

	# Song-Fortschritt: Haarlinie ganz oben ueber die volle Breite.
	var top_bg := ColorRect.new()
	top_bg.anchor_right = 1.0
	top_bg.offset_bottom = 3
	top_bg.color = Color(1, 1, 1, 0.06)
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top_bg)
	_top_fill = ColorRect.new()
	_top_fill.anchor_right = 0.0
	_top_fill.offset_bottom = 3
	_top_fill.color = Color(0.9, 0.92, 1.0, 0.55)
	_top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_fill)

	# Combo gross und mittig (klassisch Mania), Grade + Accuracy links als
	# ruhige Spalte, Zaehler rechts.
	_combo_label = _stat_value(Vector2(0.5, 0.5), 26)
	_combo_label.offset_top = 142
	_combo_label.offset_bottom = 142
	_combo_label.modulate.a = 0.92
	_grade_label = _stat_value(Vector2(0.085, 0.32), 40)
	_stat_caption(Vector2(0.085, 0.44), "ACCURACY")
	_acc_label = _stat_value(Vector2(0.085, 0.48), 26)
	_stat_caption(Vector2(0.915, 0.28), "SCORE")
	_score_label = _stat_value(Vector2(0.915, 0.32), 30)
	_stat_caption(Vector2(0.915, 0.50), "MISSES")
	_miss_label = _stat_value(Vector2(0.915, 0.54), 26)
	_stat_caption(Vector2(0.915, 0.72), "NOTES")
	_notes_label = _stat_value(Vector2(0.915, 0.76), 26)

	# HP: KLEINE cleane Bar mittig oben (nichts liegt ueber den Noten).
	var hp_bg := ColorRect.new()
	hp_bg.anchor_left = 0.5
	hp_bg.anchor_right = 0.5
	hp_bg.offset_left = -110
	hp_bg.offset_right = 110
	hp_bg.offset_top = 14
	hp_bg.offset_bottom = 18
	hp_bg.color = Color(1, 1, 1, 0.10)
	_hud.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.anchor_left = 0.5
	_hp_fill.anchor_right = 0.5
	_hp_fill.offset_left = -110
	_hp_fill.offset_right = 110
	_hp_fill.offset_top = 14
	_hp_fill.offset_bottom = 18
	_hp_fill.color = Color(0.3, 1.0, 0.6, 0.85)
	_hud.add_child(_hp_fill)

	# UR-BAR: kleine Timing-Leiste mittig unter der Bildmitte. Zonen = echte
	# Trefferfenster (PF/GD/MEH), pro Hit ein kurzlebiger Tick, Pfeil = Trend.
	_ur_root = Control.new()
	_ur_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ur_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_ur_root)
	_ur_scale = 66.0 / maxf(core.w50, 1.0)
	var zones := [
		[core.w50, Color(1.0, 0.62, 0.25, 0.20)],
		[core.w100, Color(0.45, 1.0, 0.6, 0.20)],
		[core.w200, Color(0.35, 0.75, 1.0, 0.24)],
		[core.w300, Color(0.95, 0.95, 1.0, 0.28)],
		[core.w_max, Color(1.0, 0.92, 0.55, 0.45)],
	]
	for z in zones:
		var w: float = z[0] * _ur_scale
		var zr := ColorRect.new()
		zr.position = Vector2(-w, 118)
		zr.size = Vector2(w * 2.0, 5)
		zr.color = z[1]
		zr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ur_root.add_child(zr)
	var mid := ColorRect.new()
	mid.position = Vector2(-1, 113)
	mid.size = Vector2(2, 15)
	mid.color = Color(1, 1, 1, 0.9)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ur_root.add_child(mid)
	_ur_avg = ColorRect.new()
	_ur_avg.position = Vector2(-1.5, 108)
	_ur_avg.size = Vector2(3, 4)
	_ur_avg.color = Color(1.0, 0.95, 0.5, 0.95)
	_ur_avg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ur_root.add_child(_ur_avg)

	# Mini-Judgement (PF/GD/…) mittig ueber der UR-Bar — nie ueber den Noten.
	_judge_label = Label.new()
	_judge_label.anchor_left = 0.5
	_judge_label.anchor_right = 0.5
	_judge_label.anchor_top = 0.5
	_judge_label.anchor_bottom = 0.5
	_judge_label.offset_left = -160
	_judge_label.offset_right = 160
	_judge_label.offset_top = 74
	_judge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_judge_label.add_theme_font_size_override("font_size", 26)
	_judge_label.modulate.a = 0.0
	_judge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_judge_label)

	# MULTIPLAYER: Live-Scoreboard links (wie osu!mania) — sortiert nach
	# Score, eigener Eintrag hervorgehoben; Ueberholen sieht man sofort.
	if Lobby.active and Lobby.in_game:
		_mp_board = VBoxContainer.new()
		_mp_board.anchor_top = 0.5
		_mp_board.anchor_bottom = 0.5
		_mp_board.offset_left = 18
		_mp_board.offset_top = 40
		_mp_board.add_theme_constant_override("separation", 4)
		_hud.add_child(_mp_board)
		Lobby.scores_changed.connect(_refresh_mp_board)
		Lobby.skip_now.connect(_do_skip)
		_refresh_mp_board()

	# Intro-Skip-Hinweis (nur sichtbar, solange ein langer Vorlauf laeuft).
	_skip_label = Label.new()
	_skip_label.text = "LEERTASTE  ·  Intro ueberspringen"
	_skip_label.anchor_left = 0.5
	_skip_label.anchor_right = 0.5
	_skip_label.anchor_top = 1.0
	_skip_label.anchor_bottom = 1.0
	_skip_label.offset_left = -200
	_skip_label.offset_right = 200
	_skip_label.offset_top = -92
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.add_theme_font_size_override("font_size", 16)
	_skip_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.85))
	_skip_label.visible = false
	_hud.add_child(_skip_label)


func _stat_caption(anchor_pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.anchor_left = anchor_pos.x
	l.anchor_right = anchor_pos.x
	l.anchor_top = anchor_pos.y
	l.anchor_bottom = anchor_pos.y
	l.offset_left = -120
	l.offset_right = 120
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	_hud.add_child(l)


func _stat_value(anchor_pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.anchor_left = anchor_pos.x
	l.anchor_right = anchor_pos.x
	l.anchor_top = anchor_pos.y
	l.anchor_bottom = anchor_pos.y
	l.offset_left = -120
	l.offset_right = 120
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	_hud.add_child(l)
	return l


func _update_hud() -> void:
	if _combo_label == null:
		return
	_combo_label.text = "%dx" % core.combo
	_combo_label.visible = core.combo > 0
	if core.combo > _last_combo_shown and core.combo > 0:
		_combo_label.pivot_offset = Vector2(120, 15)
		_combo_label.scale = Vector2.ONE * 1.16
		var ctw := create_tween()
		ctw.tween_property(_combo_label, "scale", Vector2.ONE, 0.12)
	_last_combo_shown = core.combo
	var g := core.grade()
	_grade_label.text = g
	_grade_label.add_theme_color_override("font_color", GRADE_COLOR.get(g, Color.WHITE))
	_acc_label.text = "%.1f%%" % (core.accuracy() * 100.0)
	# Farbecho des On-Fire-Zustands: Gold ab 97%, Eisblau ab 99.5%.
	var hud_j := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	var hud_acc := core.accuracy()
	if hud_j >= 30 and hud_acc >= 0.995:
		_acc_label.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
	elif hud_j >= 30 and hud_acc >= 0.97:
		_acc_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	else:
		_acc_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_score_label.text = "%d" % core.score
	_miss_label.text = str(core.n_miss)
	var judged := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	_notes_label.text = "%d/%d" % [judged, _beatmap.hit_objects.size()]
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.anchor_right = clampf(t / _song_len_ms, 0.0, 1.0)
	_hp_fill.offset_right = -110 + 220.0 * core.hp
	_hp_fill.color = Color(0.3, 1.0, 0.6, 0.85) if core.hp > 0.3 else Color(1.0, 0.35, 0.3, 0.9)


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


func _toggle_pause(paused: bool) -> void:
	if paused:
		if _pause_menu == null:
			_build_pause_menu()
		_pause_menu.visible = true
		get_tree().paused = true
		SyncClock.pause()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_menu != null:
			_pause_menu.visible = false
		_resume_with_countdown()


## 3-2-1-Countdown — beim Map-Start (1s pro Zahl, wie in Mania) und vor dem
## Weiterspielen nach Pause (schneller). Laeuft, waehrend der Tree pausiert ist.
func _resume_with_countdown(step: float = 0.4) -> void:
	if _countdown_running:
		return
	_countdown_running = true
	var lbl := Label.new()
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = -100
	lbl.offset_right = 100
	lbl.offset_top = -140
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 96)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.95))
	_hud.add_child(lbl)
	# Steht die erste Note noch aus, blinken die Pads ihrer Lane(s) im Takt
	# des Countdowns — man sieht sofort, WO die erste Note landen wird.
	var hint: Array[int] = []
	if _beatmap != null and not _beatmap.hit_objects.is_empty():
		var t0: float = _beatmap.hit_objects[0].time
		if _time_ms() < t0 - 200.0:
			for o in _beatmap.hit_objects:
				if o.time > t0 + 5.0:
					break
				var c := (o as ManiaNote).column
				if c >= 0 and c < _pad_mats.size() and not hint.has(c):
					hint.append(c)
	for n in [3, 2, 1]:
		lbl.text = str(n)
		lbl.scale = Vector2.ONE * 1.25
		lbl.pivot_offset = Vector2(100, 48)
		for c in hint:
			_pad_mats[c].emission_energy_multiplier = 3.2
		await get_tree().create_timer(step * 0.5, true).timeout
		if not is_inside_tree():
			return
		for c in hint:
			_pad_mats[c].emission_energy_multiplier = 0.9
		await get_tree().create_timer(step * 0.5, true).timeout
		if not is_inside_tree():
			return
	lbl.queue_free()
	_countdown_running = false
	get_tree().paused = false
	SyncClock.resume()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_hud.add_child(_pause_menu)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_pause_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.11, 0.97)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	for def in [
		["Weiter", func(): _toggle_pause(false)],
		["Retry", func(): _restart()],
		["Einstellungen", func(): _hud.add_child(SettingsPanel.new())],
		["Song-Browser", func(): _back_to_browser()],
	]:
		var b := Button.new()
		b.text = def[0]
		b.custom_minimum_size = Vector2(260, 46)
		b.pressed.connect(def[1])
		vb.add_child(b)
	_pause_menu.gui_input.connect(func(ev):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_toggle_pause(false))


func _restart() -> void:
	get_tree().paused = false
	SyncClock.stop()
	get_tree().reload_current_scene()


func _back_to_browser() -> void:
	GameSession.tutorial = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSession.is_replay = false
	GameSession.replay_events = []
	SyncClock.stop()
	# Multiplayer: zurueck in den Raum statt in den Song-Browser.
	if Lobby.active:
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _show_results(is_fail: bool) -> void:
	if _ended:
		return
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	# Full Combo: kleiner Meteorschauer am Himmel hinter dem Endscreen.
	if not is_fail and core.n_miss == 0 and _fx_level() > 0.0 \
			and DisplayServer.get_name() != "headless":
		for shower_i in 8:
			var st := get_tree().create_timer(0.3 * float(shower_i) + 0.4, true)
			st.timeout.connect(func():
				if is_inside_tree():
					_spawn_shooting_star(977 + shower_i * 37))
	var s := core.stats()
	# Multiplayer: letzten Live-Stand + Finale an alle melden.
	if Lobby.active and Lobby.in_game:
		Lobby.send_score(core.score, core.combo, core.accuracy())
		Lobby.send_final({ "score": core.score, "acc": core.accuracy(),
			"grade": core.grade(), "combo": core.max_combo,
			"failed": is_fail,
			"n_max": core.n_max, "n300": core.n300, "n200": core.n200,
			"n100": core.n100, "n50": core.n50, "n_miss": core.n_miss })
	var unranked := false  # Mania ist immer ranked (Scroll rein visuell)
	s["unranked"] = unranked
	var pp := -1.0
	if not is_fail:
		var pp_res := StarService.pp_for_mania(
			GameSession.osz_path, GameSession.osu_filename,
			s.n_max, s.n300, s.n200, s.n100, s.n50, s.n_miss, s.max_combo)
		if pp_res.has("pp"):
			pp = float(pp_res.pp)
		# TETHRA-pp-Floor: Die offizielle Mania-Formel vergibt unter ~80%
		# (Custom-)Accuracy exakt 0 pp — fuer die Solo-Progression gibt es
		# stattdessen einen Acc-basierten Mindestwert, verankert an der
		# ECHTEN rosu-SS-pp dieser Diff (nie mehr als rosu bei guter Acc).
		var acc := float(s.accuracy)
		if acc > 0.0:
			var max_pp := StarService.max_pp_for(
				GameSession.osz_path, GameSession.osu_filename,
				_beatmap.hit_objects.size())
			if max_pp > 0.0:
				pp = maxf(pp, max_pp * pow(acc, 6.0) * 0.8)
	s["pp"] = pp
	var new_best := false
	if GameSession.is_replay or GameSession.tutorial:
		# Replay-Ansicht/Tutorial: NICHTS werten oder speichern.
		pp = -1.0
	else:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s)
		ReplayStore.save(GameSession.osz_path, _beatmap.version_name(), _recorded, {
			"score": int(s.score), "grade": str(s.grade),
			"accuracy": float(s.accuracy), "date": Time.get_datetime_string_from_system(),
		})
	_build_results(is_fail, s, pp, unranked, new_best)


## Results im osu-Stil: Cover-Header, Score gross links, Judgement-Grid,
## riesiger Rank rechts, Combo/Accuracy unten.
func _build_results(is_fail: bool, s: Dictionary, pp: float, unranked: bool, new_best: bool) -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(screen)

	# Abgedunkeltes Cover als Vollbild-Hintergrund.
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if cover != null:
		var bg_tex := TextureRect.new()
		bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.texture = UiTheme.blurred_texture(cover)
		bg_tex.modulate = Color(0.55, 0.55, 0.6)
		screen.add_child(bg_tex)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.03, 0.62)
	screen.add_child(dim)

	# Kopfzeile: Map + Spieler + Datum (wie osu).
	var head_strip := ColorRect.new()
	head_strip.anchor_right = 1.0
	head_strip.offset_bottom = 92
	head_strip.color = Color(0, 0, 0, 0.55)
	screen.add_child(head_strip)
	var title := Label.new()
	title.text = "%s — %s" % [_beatmap.artist(), _beatmap.title()]
	title.position = Vector2(28, 12)
	title.add_theme_font_override("font", UiTheme.heading_font(1))
	title.add_theme_font_size_override("font_size", 24)
	screen.add_child(title)
	var sub := Label.new()
	sub.text = "[%s] · 4K   —   gespielt von %s · %s" % [
		_beatmap.version_name(), Settings.profile_name,
		Time.get_datetime_string_from_system().replace("T", " ")]
	sub.position = Vector2(28, 50)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.75, 0.78, 0.86))
	screen.add_child(sub)

	# Linkes Panel: Score + Judgement-Grid + Combo/Accuracy.
	var panel := PanelContainer.new()
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 60
	panel.offset_top = -190
	panel.offset_bottom = 190
	panel.custom_minimum_size = Vector2(520, 0)
	var psb := UiTheme.glass_box(18, 0.82)
	psb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", psb)
	screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	# SCORE-Block: Caption klein, Zahl in Marken-Typo.
	var score_cap := Label.new()
	score_cap.text = "SCORE"
	score_cap.add_theme_font_size_override("font_size", 12)
	score_cap.add_theme_color_override("font_color", Color(0.5, 0.53, 0.62))
	vb.add_child(score_cap)
	var score_lbl := Label.new()
	score_lbl.text = "%08d" % int(s.score)
	score_lbl.add_theme_font_override("font", UiTheme.heading_font(4))
	score_lbl.add_theme_font_size_override("font_size", 50)
	vb.add_child(score_lbl)

	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("separator", Color(1, 1, 1, 0.08))
	vb.add_child(sep1)

	# Judgement-Grid: Tags farbig, Zahlen rechtsbuendig — sauber ausgerichtet.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 56)
	grid.add_theme_constant_override("v_separation", 7)
	vb.add_child(grid)
	for def in [
		["MAX", s.n_max, QUALITY_COLOR[0]], ["100", s.n100, QUALITY_COLOR[3]],
		["300", s.n300, QUALITY_COLOR[1]], ["50", s.n50, QUALITY_COLOR[4]],
		["200", s.n200, QUALITY_COLOR[2]], ["✕", s.n_miss, QUALITY_COLOR[5]],
	]:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(200, 0)
		row.add_theme_constant_override("separation", 10)
		var tag := Label.new()
		tag.text = str(def[0])
		tag.custom_minimum_size = Vector2(52, 0)
		tag.add_theme_font_override("font", UiTheme.heading_font(1))
		tag.add_theme_font_size_override("font_size", 18)
		tag.add_theme_color_override("font_color", def[2])
		row.add_child(tag)
		var num := Label.new()
		num.text = "%d" % int(def[1])
		num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.add_theme_font_size_override("font_size", 21)
		row.add_child(num)
		grid.add_child(row)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(1, 1, 1, 0.08))
	vb.add_child(sep2)

	# Drei Stat-Bloecke nebeneinander: Accuracy · Max-Combo · pp.
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8)
	vb.add_child(stats_row)
	var pp_text := ("%.1f" % pp) if pp >= 0.0 else "—"
	for st in [["ACCURACY", "%.2f%%" % (s.accuracy * 100.0), Color(0.95, 0.97, 1.0)],
			["MAX COMBO", "%dx" % int(s.max_combo), Color(0.95, 0.97, 1.0)],
			["PP", pp_text, Color(1.0, 0.6, 0.9)]]:
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation", 2)
		var cap := Label.new()
		cap.text = str(st[0])
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", Color(0.5, 0.53, 0.62))
		block.add_child(cap)
		var val := Label.new()
		val.text = str(st[1])
		val.add_theme_font_override("font", UiTheme.heading_font(1))
		val.add_theme_font_size_override("font_size", 23)
		val.add_theme_color_override("font_color", st[2])
		block.add_child(val)
		stats_row.add_child(block)

	# Timing-Qualitaet: Unstable Rate + mittlerer Fehler (frueh/spaet).
	if _dt_n >= 2:
		var mean := _dt_sum / float(_dt_n)
		var variance := maxf(_dt_sqsum / float(_dt_n) - mean * mean, 0.0)
		var timing := Label.new()
		timing.text = "UR %.0f      Ø %+.1f ms (%s)" % [
			sqrt(variance) * 10.0, mean, "spaet" if mean > 0.0 else "frueh"]
		timing.add_theme_font_size_override("font_size", 15)
		timing.add_theme_color_override("font_color", Color(0.62, 0.66, 0.75))
		vb.add_child(timing)

	if new_best or unranked:
		var badge_wrap := HBoxContainer.new()
		vb.add_child(badge_wrap)
		var badge := PanelContainer.new()
		var bsb := UiTheme.solid_box(Color(1.0, 0.83, 0.25), 9)
		bsb.content_margin_left = 12
		bsb.content_margin_right = 12
		bsb.content_margin_top = 4
		bsb.content_margin_bottom = 4
		badge.add_theme_stylebox_override("panel", bsb)
		badge_wrap.add_child(badge)
		var badge_l := Label.new()
		badge_l.text = ("NEW BEST!" if new_best else "") + (" UNRANKED" if unranked else "")
		badge_l.add_theme_font_override("font", UiTheme.heading_font(1))
		badge_l.add_theme_font_size_override("font_size", 15)
		badge_l.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
		badge.add_child(badge_l)

	# MULTIPLAYER-Endscreen: Rangliste (traeufelt live ein, wenn andere
	# fertig werden).
	if Lobby.active:
		var rank_panel := PanelContainer.new()
		rank_panel.anchor_left = 1.0
		rank_panel.anchor_right = 1.0
		rank_panel.offset_left = -420
		rank_panel.offset_right = -40
		rank_panel.offset_top = 112
		var rsb := UiTheme.glass_box(16, 0.85)
		rsb.set_content_margin_all(20)
		rank_panel.add_theme_stylebox_override("panel", rsb)
		screen.add_child(rank_panel)
		var rvb := VBoxContainer.new()
		rvb.add_theme_constant_override("separation", 8)
		rank_panel.add_child(rvb)
		var rhead := Label.new()
		rhead.text = "RANGLISTE"
		rhead.add_theme_font_override("font", UiTheme.heading_font(2))
		rhead.add_theme_font_size_override("font_size", 15)
		rhead.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
		rvb.add_child(rhead)
		_mp_rank_box = VBoxContainer.new()
		_mp_rank_box.add_theme_constant_override("separation", 6)
		rvb.add_child(_mp_rank_box)
		Lobby.scores_changed.connect(_refresh_mp_ranking)
		_refresh_mp_ranking()

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var retry := Button.new()
	retry.text = "Nochmal ansehen" if GameSession.is_replay else "Retry  (R)"
	retry.visible = not Lobby.active
	retry.custom_minimum_size = Vector2(160, 46)
	UiTheme.style_button(retry, true)
	retry.pressed.connect(_restart)
	btns.add_child(retry)
	if GameSession.is_replay:
		var play_self := Button.new()
		play_self.text = "Selbst spielen"
		play_self.custom_minimum_size = Vector2(160, 46)
		UiTheme.style_button(play_self)
		play_self.pressed.connect(func():
			GameSession.is_replay = false
			GameSession.replay_events = []
			_restart())
		btns.add_child(play_self)
	elif _recorded.size() > 0:
		var watch := Button.new()
		watch.text = "▶ Replay ansehen"
		watch.custom_minimum_size = Vector2(170, 46)
		UiTheme.style_button(watch)
		watch.pressed.connect(func():
			GameSession.is_replay = true
			GameSession.replay_events = _recorded.duplicate()
			_restart())
		btns.add_child(watch)
	var back := Button.new()
	back.text = "Zur Lobby" if Lobby.active else "Song-Browser"
	back.custom_minimum_size = Vector2(160, 46)
	UiTheme.style_button(back)
	back.pressed.connect(_back_to_browser)
	btns.add_child(back)

	# Riesiger Rank rechts (osu-Look) mit Glow.
	var rank := Label.new()
	rank.text = "F" if is_fail else str(s.grade)
	rank.anchor_left = 1.0
	rank.anchor_right = 1.0
	rank.anchor_top = 0.5
	rank.anchor_bottom = 0.5
	rank.offset_left = -480
	rank.offset_right = -80
	rank.offset_top = -190
	rank.offset_bottom = 190
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.add_theme_font_override("font", UiTheme.heading_font(0))
	rank.add_theme_font_size_override("font_size", 280)
	var rc: Color = Color(1.0, 0.3, 0.3) if is_fail else GRADE_COLOR.get(str(s.grade), Color.WHITE)
	rank.add_theme_color_override("font_color", rc)
	rank.add_theme_color_override("font_shadow_color", Color(rc.r, rc.g, rc.b, 0.4))
	rank.add_theme_constant_override("shadow_outline_size", 28)
	screen.add_child(rank)
	# Auftritt: kurzer Zoom-Pop des Ranks.
	rank.pivot_offset = Vector2(200, 190)
	rank.scale = Vector2.ONE * 1.35
	rank.modulate.a = 0.0
	var rtw := create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(rank, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rtw.tween_property(rank, "modulate:a", 1.0, 0.22)
	if is_fail:
		var failed_lbl := Label.new()
		failed_lbl.text = "FAILED"
		failed_lbl.anchor_left = 1.0
		failed_lbl.anchor_right = 1.0
		failed_lbl.anchor_top = 0.5
		failed_lbl.anchor_bottom = 0.5
		failed_lbl.offset_left = -480
		failed_lbl.offset_right = -80
		failed_lbl.offset_top = 160
		failed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		failed_lbl.add_theme_font_size_override("font_size", 34)
		failed_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		screen.add_child(failed_lbl)


# ---------------------------------------------------------------------------
# Tutorial (Uebungs-Map mit Erklaer-Stopps)
# ---------------------------------------------------------------------------

## Stopps dynamisch aus der Map ableiten: erste Note, erster Hold,
## erste Doppelnote, HUD. Jeder Stopp zeigt mit einem Pfeil DIREKT auf die
## Stelle im Spielfeld (Weltposition -> Bildschirm).
func _build_tutorial_steps() -> void:
	var objs := _beatmap.hit_objects
	if objs.is_empty():
		return
	var k := []
	for code in Settings.key_lanes:
		k.append(OS.get_keycode_string(code))
	var first_note := -1.0
	var note_col := 0
	var first_hold := -1.0
	var hold_col := 0
	var first_chord := -1.0
	var chord_a := 0
	var chord_b := 1
	for i in objs.size():
		var o := objs[i] as ManiaNote
		if first_note < 0.0 and not o.is_hold:
			first_note = o.time
			note_col = o.column
		if first_hold < 0.0 and o.is_hold:
			first_hold = o.time
			hold_col = o.column
		if first_chord < 0.0 and i > 0 and absf(objs[i].time - objs[i - 1].time) < 2.0:
			first_chord = objs[i].time
			chord_a = (objs[i - 1] as ManiaNote).column
			chord_b = (objs[i] as ManiaNote).column
	_tut_steps = []
	_tut_steps.append({ "t": objs[0].time - 3000.0, "title": "DEINE TASTEN",
		"body": "%s  %s  %s  %s — eine Taste pro Spur (Pfeil: die Ringe).\nDruecke GENAU, wenn eine Drohne ihren Ring beruehrt." % [k[0], k[1], k[2], k[3]],
		"worlds": [Vector3(0.0, ROAD_Y + 0.3, Z_LINE)] })
	if first_note >= 0.0:
		_tut_steps.append({ "t": first_note - 1600.0, "title": "ERSTE NOTE",
			"body": "Gleich kommt eine Drohne auf DIESEN Ring zu.\nDruecke [%s] genau beim Beruehren.\nDeine Wertung (MAX … 50) erscheint danach in der Bildmitte." % k[note_col],
			"worlds": [Vector3(RAIL_X[note_col], ROAD_Y + 0.3, Z_LINE)] })
	if first_hold >= 0.0:
		_tut_steps.append({ "t": first_hold - 1600.0, "title": "HOLD-NOTE",
			"body": "Die Drohne mit dem langen Beam: [%s] druecken und HALTEN,\nbis der Beam vorbei ist. Zu frueh loslassen = Combo weg!" % k[hold_col],
			"worlds": [Vector3(RAIL_X[hold_col], ROAD_Y + 0.3, Z_LINE)] })
	if first_chord >= 0.0:
		_tut_steps.append({ "t": first_chord - 1600.0, "title": "DOPPELNOTE",
			"body": "Zwei Drohnen gleichzeitig — beide Pfeile!\n[%s] + [%s] EXAKT ZUSAMMEN druecken." % [k[chord_a], k[chord_b]],
			"worlds": [Vector3(RAIL_X[chord_a], ROAD_Y + 0.3, Z_LINE),
				Vector3(RAIL_X[chord_b], ROAD_Y + 0.3, Z_LINE)] })
	var span := objs[objs.size() - 1].time - objs[0].time
	_tut_steps.append({ "t": objs[0].time + span * 0.45, "title": "DEIN HUD",
		"body": "Der Pfeil zeigt auf die Timing-Leiste: Strich links = zu frueh,\nrechts = zu spaet. Darueber: Combo + Wertung.\nLinks: Accuracy · Rechts: Score · Oben: HP.\nJetzt spiel die Map zu Ende — viel Spass!",
		"screen": Vector2(0.5, 0.615) })
	_tut_steps.sort_custom(func(a, b): return float(a.t) < float(b.t))
	# Mindestabstand zwischen Stopps, sonst nerven sie.
	var cleaned: Array = []
	var last := -999999.0
	for st in _tut_steps:
		if float(st.t) - last >= 900.0:
			cleaned.append(st)
			last = float(st.t)
	_tut_steps = cleaned


func _show_tut_step(step: Dictionary) -> void:
	get_tree().paused = true
	SyncClock.pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tut_panel = Control.new()
	_tut_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tut_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.add_child(_tut_panel)
	# Leichtes Dim — das Spielfeld muss sichtbar bleiben (der Pfeil zeigt hin).
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.32)
	_tut_panel.add_child(dim)
	# Ziel-Pfeile: pulsierend, direkt ueber der Spielstelle.
	var targets: Array = []
	if step.has("worlds"):
		for w in step.worlds:
			# Ringe haengen unter dem geneigten _world-Traeger -> erst in
			# globale Koordinaten wandeln, sonst zeigen die Pfeile daneben.
			targets.append(_camera.unproject_position(_world.to_global(w)))
	elif step.has("screen"):
		targets.append(Vector2(step.screen) * Vector2(get_viewport().get_visible_rect().size))
	for tpos in targets:
		var arrow := Label.new()
		arrow.text = "⬇"
		arrow.custom_minimum_size = Vector2(64, 0)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.position = Vector2(tpos) + Vector2(-32, -150)
		arrow.add_theme_font_size_override("font_size", 64)
		arrow.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
		arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		arrow.add_theme_constant_override("shadow_offset_x", 0)
		arrow.add_theme_constant_override("shadow_offset_y", 0)
		arrow.add_theme_constant_override("shadow_outline_size", 10)
		_tut_panel.add_child(arrow)
		var atw := arrow.create_tween().set_loops()
		atw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		atw.tween_property(arrow, "position:y", tpos.y - 112.0, 0.45)
		atw.tween_property(arrow, "position:y", tpos.y - 150.0, 0.45)
	# Kompaktes Panel OBEN — verdeckt die Zielstelle nicht.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = 76
	var sb := UiTheme.glass_box(16, 0.92)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	_tut_panel.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "📘 " + str(step.title)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.20, 0.85, 1.0))
	vb.add_child(title)
	var body := Label.new()
	body.text = str(step.body)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(600, 0)
	body.add_theme_font_size_override("font_size", 16)
	vb.add_child(body)
	var go := Button.new()
	go.text = "WEITER  (Enter)"
	go.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(go, true)
	go.pressed.connect(_close_tut_step)
	vb.add_child(go)
	go.grab_focus()


func _close_tut_step() -> void:
	if _tut_panel != null:
		_tut_panel.queue_free()
		_tut_panel = null
	_tut_idx += 1
	_resume_with_countdown(0.4)


# ---------------------------------------------------------------------------
# Multiplayer-Anzeigen
# ---------------------------------------------------------------------------

func _refresh_mp_board() -> void:
	if _mp_board == null or not is_instance_valid(_mp_board):
		return
	for c in _mp_board.get_children():
		c.queue_free()
	var ranked := Lobby.ranked_players()
	var my_id := multiplayer.get_unique_id()
	var my_rank := -1
	for i in ranked.size():
		if int(ranked[i].id) == my_id:
			my_rank = i
	# Ueberhol-Feedback: eigener Rang verbessert -> kurzer FOV-Kick.
	if _mp_last_rank >= 0 and my_rank >= 0 and my_rank < _mp_last_rank:
		_fov_kick = maxf(_fov_kick, 1.6)
	_mp_last_rank = my_rank
	for i in ranked.size():
		var p: Dictionary = ranked[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var mine: bool = int(p.id) == my_id
		var leading := mine and i == 0 and ranked.size() > 1
		var num := Label.new()
		num.text = "#%d" % (i + 1)
		num.custom_minimum_size = Vector2(30, 0)
		num.add_theme_font_size_override("font_size", 14)
		num.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if i == 0 else Color(0.55, 0.58, 0.66))
		row.add_child(num)
		var name_l := Label.new()
		name_l.text = str(p.name)
		name_l.custom_minimum_size = Vector2(110, 0)
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.add_theme_font_size_override("font_size", 14)
		# Eigener Eintrag: GRUEN wenn du fuehrst, sonst Cyan.
		name_l.add_theme_color_override("font_color",
			Color(0.45, 1.0, 0.55) if leading
			else (Color(0.4, 0.95, 1.0) if mine else Color(0.85, 0.88, 0.95)))
		row.add_child(name_l)
		var score_l := Label.new()
		score_l.text = "%d" % int(p.score)
		score_l.add_theme_font_size_override("font_size", 14)
		score_l.add_theme_color_override("font_color",
			Color(0.45, 1.0, 0.55) if leading
			else (Color(1, 1, 1) if mine else Color(0.7, 0.73, 0.8)))
		row.add_child(score_l)
		# Live-Differenz am eigenen Eintrag: Vorsprung (+, gruen) oder
		# Rueckstand (-, rot) zum direkten Nachbarn.
		if mine and ranked.size() > 1:
			var diff_l := Label.new()
			var d := 0
			if i == 0:
				d = int(p.score) - int(ranked[1].score)
				diff_l.text = "+%s" % _fmt_score_diff(d)
				diff_l.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
			else:
				d = int(ranked[i - 1].score) - int(p.score)
				diff_l.text = "-%s" % _fmt_score_diff(d)
				diff_l.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
			diff_l.add_theme_font_size_override("font_size", 12)
			row.add_child(diff_l)
		_mp_board.add_child(row)


## Punktedifferenz kompakt: 950 · 12,3k · 1,2M.
func _fmt_score_diff(d: int) -> String:
	if d >= 1000000:
		return "%.1fM" % (d / 1000000.0)
	if d >= 10000:
		return "%.1fk" % (d / 1000.0)
	return str(d)


func _refresh_mp_ranking() -> void:
	if _mp_rank_box == null or not is_instance_valid(_mp_rank_box):
		return
	for c in _mp_rank_box.get_children():
		c.queue_free()
	var ranked := Lobby.ranked_players()
	var my_id := multiplayer.get_unique_id()
	for i in ranked.size():
		var p: Dictionary = ranked[i]
		var fin: Dictionary = p.get("final", {})
		var mine := int(p.id) == my_id
		var row := Label.new()
		var state := ""
		if fin.is_empty():
			state = "spielt noch…  (%d)" % int(p.score)
		else:
			state = "%d · %.2f%% · %s · %dx%s" % [int(fin.get("score", p.score)),
				float(fin.get("acc", 0.0)) * 100.0, str(fin.get("grade", "?")),
				int(fin.get("combo", 0)),
				"  [FAIL]" if bool(fin.get("failed", false)) else ""]
		row.text = "#%d  %s   %s" % [i + 1, str(p.name), state]
		row.add_theme_font_size_override("font_size", 15)
		row.add_theme_color_override("font_color",
			Color(0.4, 0.95, 1.0) if mine else Color(0.85, 0.88, 0.95))
		_mp_rank_box.add_child(row)
		# Detail-Zeile: alle Judgements — jeder sieht, wer wo gemisst hat.
		if not fin.is_empty():
			var det := Label.new()
			det.text = "      MAX %d · 300 %d · 200 %d · 100 %d · 50 %d · ✕ %d" % [
				int(fin.get("n_max", 0)), int(fin.get("n300", 0)),
				int(fin.get("n200", 0)), int(fin.get("n100", 0)),
				int(fin.get("n50", 0)), int(fin.get("n_miss", 0))]
			det.add_theme_font_size_override("font_size", 12)
			det.add_theme_color_override("font_color",
				Color(0.62, 0.66, 0.75) if not mine else Color(0.55, 0.85, 0.95))
			_mp_rank_box.add_child(det)


# ---------------------------------------------------------------------------
# Headless / Screenshot
# ---------------------------------------------------------------------------

func _run_smoke_test() -> void:
	print("=== Mania3D (Raumschiff) Smoke-Test ===")
	print("Map: %s - %s [%s], %dK, %d Notes, preempt %.0f" % [
		_beatmap.artist(), _beatmap.title(), _beatmap.version_name(),
		core.columns, _beatmap.hit_objects.size(), core.preempt])
	# Geometrie: Note erreicht die Linie exakt zur Hit-Time.
	var z_at_hit := _note_z(1000.0, 1000.0)
	print("z@hit = %.2f (Linie %.2f)" % [z_at_hit, Z_LINE])
	assert(absf(z_at_hit - Z_LINE) < 0.001)
	print("=== Smoke-Test OK ===")
	get_tree().quit(0)


func _capture_results_shot() -> void:
	await get_tree().create_timer(1.0, true).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/results.png")
	print("SHOT gespeichert (results)")
	get_tree().quit(0)


func _capture_after_first_note() -> void:
	# Harness: je ein Wrack + eine Station sichtbar platzieren, damit der
	# Screenshot die Vorbeiflug-Optik mitprueft.
	_spawn_flyby(-1.0, 0)
	_spawn_flyby(1.0, 3)
	for fb in _flybys:
		if is_instance_valid(fb.node):
			fb.node.position.z = -26.0
		fb.speed = 0.0
	var idx := mini(6, _beatmap.hit_objects.size() - 1)
	var target := _beatmap.hit_objects[idx].time - 150.0
	var guard := 0
	while _time_ms() < target and guard < 3600:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/mania_3d.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)
