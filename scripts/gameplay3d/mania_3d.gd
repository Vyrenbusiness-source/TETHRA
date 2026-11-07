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
const RAIL_X_BASE: Array[float] = [-2.55, -0.85, 0.85, 2.55]
## Strecken-Rand (Kanten/Waende) und Strassenbreite bei 100 % Spurbreite.
const EDGE_X_BASE := 3.6
const ROAD_W_BASE := 8.4
const WAVE_W_BASE := 8.6
# Receptor: gleiche Quad-Groesse wie die Note (dq.size), knapp unter ihr.
const NOTE_SIZE := 1.12
const PAD_SIZE := NOTE_SIZE
const PAD_Y := 0.30
# Ring-Helligkeit: Ruhe unter der Glow-Schwelle (0.92), Druck nur leicht drueber.
const PAD_IDLE := 0.85
const PAD_PRESS := 0.35
const PAD_MAX_SCALE := 1.15
# Leuchtfleck unter Noten (vorher 0.9 / Lock 1.6 -> ueberstrahlte Muster).
const NOTE_GLOW := 0.34
## Obergrenze der Streckenrand-Emission in Themen-Welten (Galaxie/Neon frei).
const EDGE_MAX_THEMED := 1.15
## Themen-Welten (Nutzer: goldene Eklipse-Waende fast weiss): Rand-/Wandbaender
## leuchten nur mit ~40 % des Galaxie-Grundtons, der Beat hebt sie hoechstens
## um 15 %. Pads bleiben unter den Noten, Lesbarkeit vor Glanz.
const EDGE_THEMED_K := 0.4
const EDGE_THEMED_BEAT := 0.15
const PAD_THEMED_K := 0.62

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
# Noten nach Beat-Teilung faerben (SnapColor); Setting folgt spaeter.
const SNAP_COLORS_ENABLED := true
# Beatmap-Hintergrund als ferne, geblurte, abgedunkelte Ebene hinter dem Nebel.
const MAP_BG_ENABLED := true
const MAP_BG_ALPHA := 0.18

const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var core := ManiaCore.new()
var _beatmap: Beatmap
var _use_audio := false
var _camera: Camera3D
# KAMERA-MODUS (Settings.camera_mode, Override per --cam=dyn / --cam=comfort):
# Komfort = gegen Motion-Sickness: Welt/Kosmos heben/kippen sich nicht,
# ruhigere Perspektive (kleineres FOV, hoeher + steiler), Vorwaerts-Fluss am
# Bildrand gedaempft (_flow). Licht-Pulse im Takt bleiben voll.
var _comfort := true
var _cam_pos := Vector3(0, 1.78, 6.8)
var _cam_pitch := -15.2
var _cam_fov := 72.0
## Vection-Faktor: Sterne/Staub/Beat-Schub (1.0 Dynamisch, 0.4 Komfort).
var _flow := 1.0
var _glow_shader: Shader
var _ring_shader: Shader
var _note_shader: Shader
var _sparks: HitSparks
# Skill-Belohnung (Lichtstroeme/Plasma/Aura ab Combo 50 bei >= 95 % Acc).
var _skill_fx: SkillFx

var _theme_col := Color(0.22, 0.68, 0.90)
var _theme_kiai := Color(0.92, 0.52, 0.20)
# Snap-Farbe je hit_object (einmal beim Laden berechnet, Index = Note).
var _snap_cols := PackedColorArray()
var _snap_divs := PackedInt32Array()
# Map-Hintergrundbild (einmal beim Map-Start geladen, nie im Gameplay).
var _bg_tex: Texture2D

## Traeger fuer die komplette Strecke (Rails/Linie/Pads/Notes/Laser).
## Bleibt FIX: kein Kippen/Banken/Wippen — die Bahn ist der Ruhepol.
var _world: Node3D
# OVERDRIVE-Effekt (Combo-Belohnung, rein Farbe/Glow).
var _overdrive := 0.0
var _was_kiai := false

var _edge_mats: Array[StandardMaterial3D] = []
var _pad_mats: Array[ShaderMaterial] = []
var _pad_flash: Array[float] = []
var _line_mat: StandardMaterial3D
var _ship: Node3D
var _ship_glow_mat: ShaderMaterial
var _horizon_mat: ShaderMaterial
var _road_mat: ShaderMaterial

# Beat-exakte FX: BeatClock liefert Phase/Kanten aus den Timing-Points.
var _clock := BeatClock.new()
var _vignette_mat: ShaderMaterial
var _ember_mm: MultiMesh
var _ember_pos: Array[Vector3] = []
var _ember_vel: Array[float] = []
var _ember_life: Array[float] = []
var _ember_next := 0
## Laufende Downbeat-Wellen: {node, mat, time, peak} — Position pro Frame ueber
## _note_z (folgt der SV wie die Noten).
var _beat_waves: Array = []
var _pad_nodes: Array[MeshInstance3D] = []
var _planet_mats: Array[ShaderMaterial] = []
var _nebula_kick := 0.0
var _line_flash := 0.0
## Hitsound-Basispegel; der Hitsound-Regler (Settings.hitsound_volume) kommt dazu.
const HIT_DB := -7.0
const MISS_DB := -6.0
# GROOVE: kurzer Licht-Schlag auf jeder Beat-Kante (Attack sofort, Decay
# ~140 ms). Hoehe = Musikenergie (Bass/Gesamt, ~1 Beat geglaettet) + Noten-
# dichte; Downbeat staerker, Kiai x1.6, alles * _fx_level(). Nur Licht —
# kein Wackeln, keine Kamera, nichts ueber den Noten.
const GROOVE_DECAY_MS := 48.0  ## exp(-140/48) ~ 5 %: nach ~140 ms verklungen
const GROOVE_DOWN := 1.0
const GROOVE_BEAT := 0.6
const GROOVE_KIAI := 1.6
var _groove := 0.0
var _groove_down := 0.0
var _groove_peak := 0.0
var _groove_is_down := false
var _groove_vt := 0.0
# Bild-Zeit dieses Frames (SyncClock.visual_time_ms) — Takt der Strecke.
var _vt := 0.0
var _comeback_pending := false
var _music_energy := 0.0
var _density2 := 0.0
var _groove_kiai_seen := false
var _kiai_sweep_pending := false
## Kiai-Licht-Sweeps: {node, mat, t0, dur, peak}
var _kiai_sweeps: Array = []
# TREFFER AUF DEM BEAT: Pad-Puls (300/MAX) in Snap-/Spurfarbe, MAX-Ring-Expand,
# Miss-Abdunkeln — je Spur, klingt in ~180-250 ms ab.
var _pad_groove: Array[float] = []
var _pad_groove_col: Array[Color] = []
var _pad_dark: Array[float] = []
var _max_rings: Array[MeshInstance3D] = []
var _max_ring_mats: Array[ShaderMaterial] = []
var _max_ring_t: Array[float] = []
var _ember_mat: ShaderMaterial

# Replay: Aufnahme jeder Runde + zeitgenaue Wiedergabe.
var _recorded: Array = []
## --autoplay (nur Screenshots/Debug): trifft jede Note exakt, speichert nichts.
var _autoplay := false
var _auto_idx := 0
var _auto_release: Array[float] = []
var _replay_idx := 0

# Kreative Song-Events: Drop-Warp, Notendichte-Surge, Phrasen-Sweep, Break.
var _density := 0.0
var _in_break := false
var _scan_from := 0

## index -> {root, glow_mat, rim, beam}
var _notes: Dictionary = {}
## Losgelassene/verpasste Hold-Strahlen scrollen entsaettigt weiter:
## { "beam": HoldBeam, "head": ms, "end": ms, "col": int }
var _released_beams: Array[Dictionary] = []

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
# BEAT-REISE + WELT-PULS: eine gemeinsame Beat-Huellkurve fuer die ganze
# Umgebung. _surge = Vorwaerts-Schub (Saegezahn: Stoss genau auf dem Schlag,
# gleitet bis zum naechsten aus, Downbeat x1.6); _world_pulse = Helligkeit
# (+12..20 %, Attack sofort, Decay ~180 ms). Beides aus BeatClock (visuelle
# Zeit), * Musikenergie, Kiai x1.5, * _fx_level().
const SURGE_DOWN := 1.6
const SURGE_KIAI := 1.5
const WORLD_PULSE_DECAY_MS := 62.0  ## exp(-180/62) ~ 5 %
const STAR_COUNT := 260
var _edge_peak := 0.0
var _edge_down := false
var _surge := 0.0
var _world_pulse := 0.0
var _star_rot: Array[Basis] = []
var _edge_band_mat: ShaderMaterial
## Alle Materialien mit world_pulse-Uniform (einmal beim Map-Start gesammelt).
var _pulse_mats: Array[ShaderMaterial] = []
var _galaxy_node: MeshInstance3D
# REISE-ROUTE: Basis-Positionen + Drift der Planeten ueber die Songdauer.
# Letzter Eintrag = Ziel-Planet (steigt auf, Docking-Finale zieht ihn mittig).
var _planet_base: Array = []
const PLANET_DRIFT := [
	Vector3(9.0, -2.6, 0.0), Vector3(-10.5, 2.8, 0.0),
	Vector3(6.0, 1.8, 0.0), Vector3(-2.0, 9.0, 0.0)]
# KOSMOS: der komplette Hintergrund haengt unter diesem frei beweglichen
# Node — die Bahn bleibt fix, das UNIVERSUM fliegt (Roll/Bank/Climb).
var _cosmos: Node3D
var _cosmos_lift := 0.0
var _cosmos_lift_target := 0.0
# Easing-Phase (0..1) fuer das langsame Break-Hochziehen.
var _lift_phase := 0.0
# Beat-Schub-Reise: akkumulierte Distanz statt linearer Zeit.
var _travel := 0.0
# Screen-FX: nur noch die ruhige Vignette (Aberration/Schockwelle/Glitch/
# Warp-Tunnel verzerrten das Spielfeld und sind raus).
var _screen_mat: ShaderMaterial
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
# KAPITEL-UEBERBLENDUNG: Startwerte beim Wechsel, Ziel = Kapitel-Werte;
# Mischung laeuft CH_FADE_BEATS Schlaege ab dem Kapitel-Downbeat (Bild-Zeit).
var _gal_from := {}
var _ch_w := 1.0
var _ch_kiai_w := 0.0      # 0..1: Kiai-Kapitel (dichter, heller, Aurora)
var _ch_kiai_from := 0.0
# VORBEIFLUG: zwei Slots (aktuelles + voriges Kapitel), beim Map-Start gebaut.
var _flyby: Array = []
# PANORAMA-HIMMEL (sky_panorama.gdshader): alle Paletten beim Map-Start
# geladen; Kapitelwechsel blendet tex_a -> tex_b ab dem Downbeat.
const SKY_PALS := ["violet", "azure", "ember", "emerald"]
const SKY_HUES := [0.78, 0.58, 0.05, 0.40]
var _sky_mat: ShaderMaterial
var _sky_neb: Array = []
var _sky_stars: Array = []
var _sky_a := -1
var _sky_b := -1
var _sky_phase := 0.0
# WELT-THEMA (WorldTheme): beim Map-Start gewaehlt. "galaxy" = sky_panorama
# mit Kapitel-Paletten; boss/aurora/neon = eigener Himmels-Shader mit dem
# gleichen Uniform-Interface (_sky_mat), Farbsatz ersetzt die Coverfarbe.
var _world_theme := WorldTheme.GALAXY
var _theme_lightning := 0.0
var _bs_smooth := 0.0     # monotone, geglaettete beat_step-Zeit
var _bs_flow_prev := 0.0  # beat_step des letzten Frames (flow_phase-Integral)
var _flow_phase := 0.0    # Vorwaerts-Weg in Schlaegen (Sturm-Durchflug), monoton
var _beat_total := 0     # gezaehlte Beat-Kanten (beat_step, monoton)
var _bc_kiai := false
var _kiai_t0 := -1.0
var _kiai_t1 := -1.0
var _theme_flow := 0.0
var _theme_grid := 0.0
var _gal_scale := 1.0
## Grund-Reisetempo aus dem BPM der Map (140 BPM = neutral).
var _bpm_factor := 1.0
# Flug-Choreografie (aus der Map geplant): nur noch Break-Kino.
var _flight_plan: Array = []
var _flight_idx := 0
## Stations-Assets werden beim Map-Start EINMAL geladen (Preload-Cache) —
## nie Disk-I/O mitten im Spiel (Latenz!). Eintrag = Liste von [Mesh, Tex].
var _station_pool: Array = []
var _dock_station: Node3D
# Reise v2: Nah-Staub, Landmarks, Sonnenaufgang, HUD-Reiseroute.
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
var _bass := 0.0
var _treble := 0.0
var _bass_avg := 0.0
var _sub := 0.0
var _sub_avg := 0.0
var _kick := 0.0
var _kick_cooldown := 0.0
var _punch := 0.0
var _punch_cooldown := 0.0
var _star_burst := 0.0
# Planeten-Referenzen fuer den Bass-Puls.
var _planet_nodes: Array = []
var _last_milestone := 0
var _ended := false

var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer

var _debug_running := false
var _debug_start_usec := 0

var _hud: CanvasLayer
# HUD-Module: Judge + Kombo, Timing-Leiste, HP oben, Intro/Break-Anzeige.
var _judge_disp: JudgeDisplay
var _err_bar: HitErrorBar
var _hp_bar: HpBar
var _break_ov: BreakOverlay
# Intro/Breaks als [start_ms, end_ms] (end = naechste Note).
var _breaks: Array[Vector2] = []
var _break_cur := -1
var _break_skip := false
var _hp_flash_cd := 0.0
var _ur_ema := 0.0
# Timing-Statistik fuer den Results-Screen (UR + mittlerer Fehler).
var _dt_n := 0
var _dt_sum := 0.0
var _dt_sqsum := 0.0
var _countdown_running := false
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
var _mp_board: Control
var _mp_send_t := 0.0
# Results-Screen (Komponente) + Clip-Export mit Fortschritt-Toast.
var _results_screen: ResultsScreen
var _clip_exporter: ClipExporter
var _clip_toast: PanelContainer
var _clip_toast_tw: Tween
# Hit-Fehler (ms) aller Treffer fuer das Histogramm im Results-Screen.
var _hit_offsets := PackedFloat32Array()
# Multiplayer-Stats: Acc nach jedem Urteil, Hold-Ergebnisse.
var _acc_trace := PackedFloat32Array()
var _hold_ok := 0
var _hold_drop := 0
var _mp_last_rank := -1
var _mp_team_bar: LiveTeamBar = null
var _mp_danger := -1
var _mp_rounds_at_start := 0
var _mp_round_no_at_start := 1
var _mp_rows: Dictionary = {}
## Test-Hook (--mp-demo): erfundene Scores + Screenshots, ohne zu spielen.
var _mp_demo := OS.get_cmdline_args().has("--mp-demo")
var _mp_demo_t := 0.0
var _mp_demo_shots := 0
var _acc_label: Label
var _grade_label: Label
var _score_label: Label
var _miss_label: Label
var _notes_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _bottom_fill: ColorRect
var _pause_menu: PauseMenu
var _song_len_ms := 1.0
# Spurbreite (Settings.lane_spacing, CLI --lane=70): skaliert alle Spur-X,
# Noten erst unter 85 % leicht mit (Settings.lane_note_scale). Strecke mittig.
var _lane_k := 1.0
var _note_k := 1.0
var RAIL_X: Array[float] = RAIL_X_BASE.duplicate()
# 2D-Modus (Settings.playfield_2d, CLI --2d/--3d): 3D-Welt bleibt als Logik-
# Traeger bestehen, ist aber unsichtbar; Playfield2D zeichnet die Spalten.
var _2d := false
var _bg_opacity := 0.3
var _bg_blur_on := true
var _note_style_2d := 0
var _lane_k_2d := 1.0   ## Settings.lane_width_2d (CLI --lane2d=150)
var _note_k_2d := 1.0   ## Settings.note_size_2d (CLI --note2d=150)
var _bg_mat_2d: ShaderMaterial
var _pf2d: Playfield2D
var _missed_2d: Array = []  ## verpasste Einzelnoten fallen grau weiter: [time, col]


func _ready() -> void:
	_setup_lane_spacing()
	# Erzwungene Welt: Texturen sofort im Hintergrund laden (kein Hitch spaeter).
	if not _2d:
		WorldTheme.prefetch(_forced_theme())
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	# Mania: AR egal, nur Scroll-Speed. Tutorial: deutlich gemuetlicheres
	# Anflug-Tempo, damit Einsteiger jede Note kommen sehen.
	var scroll := Settings.mania_scroll
	if GameSession.tutorial:
		scroll = minf(scroll, 1.0) * 0.65
	core.setup(_beatmap, -1.0, scroll)
	_clock.setup(_beatmap.timing_points)
	_autoplay = OS.get_cmdline_args().has("--autoplay") 			and not GameSession.is_replay and not Lobby.active
	_auto_release.resize(core.columns)
	_auto_release.fill(-1.0)
	core.note_spawned.connect(_on_note_spawned)
	core.note_judged.connect(_on_note_judged)
	core.hold_started.connect(_on_hold_started)
	core.lane_pressed.connect(_on_lane_pressed)
	core.finished.connect(func(_s): _show_results(false))

	_glow_shader = load("res://shaders/glow_dot.gdshader")
	_ring_shader = load("res://shaders/hit_ring.gdshader")
	_note_shader = load("res://shaders/note_disc.gdshader")
	_extract_theme_color()
	_choose_world_theme()
	if not _2d:
		WorldTheme.prefetch(_world_theme)
	_precompute_snap_colors()
	if not _2d:
		_preload_stations()  # 2D: keine Stations-Meshes/Texturen laden
	_build_world()
	if _2d:
		_build_playfield_2d()
	_sparks = HitSparks.new()
	_world.add_child(_sparks)
	_sparks.setup(RAIL_X, Z_LINE, ROAD_Y, _theme_col)
	_skill_fx = SkillFx.new()
	_world.add_child(_skill_fx)
	_skill_fx.setup(RAIL_X, Z_LINE, Z_FAR, ROAD_Y, _theme_col, _theme_kiai)
	_build_hud()
	if not _2d:
		_build_screen_fx()
	# Kapitel-Punkte unten entfernt (QA: unklar, doppelt zum Song-Fortschritt).
	_build_flight_plan()
	_build_galaxy_chapters()
	_apply_theme_world()
	if _2d:
		# 2D: versteckte Welt komplett pausieren (kein _process in Deko/FX).
		_world.process_mode = Node.PROCESS_MODE_DISABLED
		if _cosmos != null:
			_cosmos.process_mode = Node.PROCESS_MODE_DISABLED
	_build_sound()
	_beat_player = AudioStreamPlayer.new()
	_beat_player.stream = Sfx.beat_thump_stream()
	_beat_player.bus = "Master"
	_beat_player.volume_db = -16.0
	add_child(_beat_player)
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
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for _i in 300:
			_hit_offsets.append(rng.randfn(3.2, 17.0))
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


## Spurbreite aus den Settings (oder --lane=<prozent>) -> RAIL_X, _note_k.
func _setup_lane_spacing() -> void:
	var k := Settings.lane_spacing
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--lane="):
			k = a.trim_prefix("--lane=").to_float() / 100.0
	_lane_k = Settings.clamp_lane_spacing(k)
	_note_k = Settings.lane_note_scale(_lane_k)
	RAIL_X.clear()
	for x in RAIL_X_BASE:
		RAIL_X.append(x * _lane_k)
	_2d = Settings.playfield_2d
	_bg_opacity = Settings.bg_dim
	_bg_blur_on = Settings.bg_blur
	_note_style_2d = Settings.note_style_2d
	_lane_k_2d = Settings.lane_width_2d
	_note_k_2d = Settings.note_size_2d
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--2d":
			_2d = true
		elif a == "--3d":
			_2d = false
		elif a.begins_with("--bgdim="):
			_bg_opacity = Settings.clamp_bg_dim(a.trim_prefix("--bgdim=").to_float() / 100.0)
		elif a.begins_with("--lane2d="):
			_lane_k_2d = Settings.clamp_2d_size(a.trim_prefix("--lane2d=").to_float() / 100.0)
		elif a.begins_with("--note2d="):
			_note_k_2d = Settings.clamp_2d_size(a.trim_prefix("--note2d=").to_float() / 100.0)
		elif a == "--noblur":
			_bg_blur_on = false
		elif a.begins_with("--notes2d="):
			_note_style_2d = Settings.NOTE_STYLE_CIRCLE if a.ends_with("circle") 					else Settings.NOTE_STYLE_BAR


## 2D-Modus: 3D-Welt + Kosmos ausblenden (bleiben Logik-Traeger), Map-Bild
## als geblurrter Vollbild-Hintergrund, darueber die 2D-Spalten.
func _build_playfield_2d() -> void:
	_world.visible = false
	if _cosmos != null:
		_cosmos.visible = false
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)
	var tex := _bg_tex
	if tex == null and GameSession.has_selection():
		tex = OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	var img: Image = tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		# Klein genug fuer billige Mips, gross genug fuer "nur leicht" weich.
		if img.get_width() > 1280:
			img.resize(1280, int(1280.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/bg_blur.gdshader")
		mat.set_shader_parameter("bg_tex", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("tex_size", Vector2(img.get_width(), img.get_height()))
		mat.set_shader_parameter("opacity", _bg_opacity)
		mat.set_shader_parameter("blur_lod", 2.6 if _bg_blur_on else 0.0)
		bg.material = mat
		_bg_mat_2d = mat
	var pf_layer := CanvasLayer.new()
	pf_layer.layer = 0
	add_child(pf_layer)
	_pf2d = Playfield2D.new()
	var keys := PackedStringArray()
	for i in core.columns:
		keys.append(_short_key_name(Settings.key_lanes[i]) if i < Settings.key_lanes.size() else "")
	_pf2d.setup(core.columns, _lane_k_2d, Z_LINE, Z_FAR, keys, _lane_color(0), _note_style_2d,
			_note_k_2d)
	_pf2d.skin = _load_skin_2d()
	pf_layer.add_child(_pf2d)


## Gewaehlter osu!mania-Skin (Settings.skin_2d, CLI --skin2d=<name>) oder null.
func _load_skin_2d() -> ManiaSkin:
	var nm := Settings.skin_2d
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--skin2d="):
			nm = a.trim_prefix("--skin2d=")
	return ManiaSkin.load_skin(nm) if nm != "" else null


## Pausenmenue hat 2D-Werte geaendert: sofort anwenden (ohne Neustart).
func _apply_2d_view() -> void:
	_lane_k_2d = Settings.lane_width_2d
	_note_k_2d = Settings.note_size_2d
	_bg_opacity = Settings.bg_dim
	if _pf2d != null:
		_pf2d.set_sizes(_lane_k_2d, _note_k_2d)
	if _bg_mat_2d != null:
		_bg_mat_2d.set_shader_parameter("opacity", _bg_opacity)
	_place_hud_to_line()  # UR-Leiste folgt der neuen Feldbreite


## 2D-Modus: Notenstand dieses Frames an Playfield2D (gleiche _note_z-Rechnung).
func _update_playfield_2d(t: float) -> void:
	_pf2d.begin_frame()
	for index in _notes:
		var obj := _beatmap.hit_objects[index] as ManiaNote
		var entry: Dictionary = _notes[index]
		var c: Color = entry.get("col", Color(1, 1, 1))
		var held: bool = core.active_hold(obj.column) == index
		var zh: float = (entry.root as Node3D).position.z
		if obj.is_hold:
			_pf2d.add_hold(obj.column, zh, _note_z(obj.end_time(), t), c,
					Playfield2D.STATE_HELD if held else Playfield2D.STATE_NORMAL)
		else:
			_pf2d.add_note(obj.column, zh, c)
	for rb in _released_beams:
		_pf2d.add_hold(int(rb.col), _note_z(float(rb.head), t), _note_z(float(rb.end), t),
				NoteColors.color_for(int(rb.col), true, true, CLEAN_HOLD), Playfield2D.STATE_DEAD)
	for mi in range(_missed_2d.size() - 1, -1, -1):
		var z := _note_z(float(_missed_2d[mi][0]), t)
		if z > Z_LINE + 12.0:
			_missed_2d.remove_at(mi)
			continue
		_pf2d.add_note(int(_missed_2d[mi][1]), z, Color.GRAY, Playfield2D.STATE_DEAD)
	_pf2d.set_combo(core.combo)
	_pf2d.set_lanes(_lane_held, _pad_flash, _pad_judge_col)


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
		# SV: Anflugzeit der ersten Note folgt der Scroll-Position (lazer).
		var sm := ManiaCore.build_scroll_map(_beatmap)
		if not sm.is_identity():
			preempt = first_t - sm.spawn_time(first_t, preempt)
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
	_bg_tex = tex
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


## Map-Hintergrund: Bild einmal klein rechnen (= starker Blur), abdunkeln,
## Mitte hinter der Strecke noch dunkler, Raender weich ausblenden. Liegt als
## riesige ferne Ebene HINTER dem Nebel; alles CPU-seitig, einmal beim Start.
func _build_map_bg() -> void:
	# Panorama-Himmel ist die Basis: die Map-Bild-Ebene wuerde ihn verdecken.
	if _sky_mat != null:
		return
	if not MAP_BG_ENABLED or _bg_tex == null:
		return
	var src := _bg_tex.get_image()
	if src == null or src.is_empty():
		return
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	# Zweistufig verkleinern (kein Aliasing), dann 3x Box-Blur.
	img.resize(128, 72, Image.INTERPOLATE_LANCZOS)
	img.resize(40, 22, Image.INTERPOLATE_BILINEAR)
	const W := 40
	const H := 22
	for _pass in 3:
		var blurred := Image.create(W, H, false, Image.FORMAT_RGBA8)
		for y in H:
			for x in W:
				var acc := Color(0, 0, 0, 0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						acc += img.get_pixel(clampi(x + ox, 0, W - 1), clampi(y + oy, 0, H - 1))
				blurred.set_pixel(x, y, acc / 9.0)
		img = blurred
	for y in H:
		for x in W:
			var u := (float(x) + 0.5) / float(W) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(H) * 2.0 - 1.0
			var c := img.get_pixel(x, y)
			# Abdunkeln + leicht entsaettigen (nichts grell, kein Grau-Lift).
			c = c.lerp(Color(c.get_luminance(), c.get_luminance(), c.get_luminance()), 0.25)
			c = c * 0.55
			# Mitte (hinter der Strecke) dunkler.
			var center := clampf(1.0 - Vector2(u * 2.6, v * 2.2).length(), 0.0, 1.0)
			# Weiche elliptische Maske: erreicht 0 schon bei r = 0.92, also weit vor
			# dem Quad-Rand -> nie eine sichtbare Kante, auch nicht beim Kurven.
			var r := Vector2(u, v).length()
			var edge := 1.0 - smoothstep(0.38, 0.92, r)
			# Unterhalb des Horizonts (v > 0, Bildzeile ~360) liegt die Strecke:
			# dort fast ausblenden, damit der schwarze Raum schwarz bleibt.
			var below := smoothstep(-0.02, 0.10, v)
			c.a = MAP_BG_ALPHA * (1.0 - 0.65 * center) * edge * (1.0 - 0.85 * below)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = ImageTexture.create_from_image(img)
	# Kein Wrap: sonst blutet der gegenueberliegende Rand als Kante ein.
	mat.texture_repeat = false
	mat.render_priority = -10
	var bg := MeshInstance3D.new()
	var bq := QuadMesh.new()
	var aspect := float(src.get_width()) / maxf(1.0, float(src.get_height()))
	# Deutlich groesser als der Sicht-Kegel in dieser Tiefe (~180 x 100):
	# Quad-Rand liegt immer ausserhalb, die Maske blendet vorher aus.
	var bh := 240.0
	bq.size = Vector2(maxf(bh * aspect, 420.0), bh)
	bg.mesh = bq
	bg.material_override = mat
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg.position = Vector3(0, 0.0, Z_FAR - 16.0)
	_cosmos.add_child(bg)


## Snap-Teiler aller Noten einmalig -> Farben. Lesbarkeit: Palette hat gleiche
## Helligkeit; leicht angehoben, damit sie auf dunklem Grund kraeftig bleibt.
func _precompute_snap_colors() -> void:
	_snap_cols = PackedColorArray()
	if not SNAP_COLORS_ENABLED or _beatmap == null:
		return
	var divs := SnapColor.precompute(_beatmap)
	_snap_divs = divs
	var cache := {}
	_snap_cols.resize(divs.size())
	for i in divs.size():
		var d: int = divs[i]
		if not cache.has(d):
			if WorldTheme.has_note_style(_world_theme):
				# Weltfarbe, Snap ueber Helligkeit/Saettigung gestaffelt.
				cache[d] = WorldTheme.snap_style(d, WorldTheme.note_color(_world_theme, false))
			else:
				var c := SnapColor.color_for(d, _theme_col)
				cache[d] = Color.from_hsv(c.h, clampf(c.s * 1.08, 0.0, 0.85),
						clampf(c.v * 1.04, 0.0, 0.95))
		_snap_cols[i] = cache[d]


func _snap_col(index: int) -> Color:
	if index < 0 or index >= _snap_cols.size():
		return Color(0, 0, 0, 0)
	return _snap_cols[index]


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
	if _2d:
		# 2D: kein Himmel, kein Bloom -> 3D-Pass rendert praktisch nichts.
		env.glow_enabled = false
	else:
		_build_sky(env)
	we.environment = env
	add_child(we)

	_setup_camera_mode()
	# Kamera: hinter/ueber dem Schiff, leicht nach unten auf den Highway.
	_camera = Camera3D.new()
	# Etwas hoeher + staerker geneigt: mehr Draufsicht, das Feld wirkt tiefer
	# und die Notenabstaende bleiben besser lesbar.
	_camera.position = _cam_pos
	_camera.rotation_degrees = Vector3(_cam_pitch, 0, 0)
	_camera.fov = _cam_fov
	_camera.current = true
	add_child(_camera)

	# Strecken-Traeger: ALLES Spielgeschehen haengt hier drunter und wird als
	# Ganzes geneigt/gerollt (Flug + Loopings) — Kamera bleibt fix.
	_world = Node3D.new()
	add_child(_world)

	# KEINE Innen-Schienen mehr (verdeckten bei Notenhagel die Sicht) —
	# nur Aussenkanten als Streckenrand (hell, bass-reaktiv).
	for sx in [-EDGE_X_BASE * _lane_k, EDGE_X_BASE * _lane_k]:
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
	for sx in [-EDGE_X_BASE * _lane_k, EDGE_X_BASE * _lane_k]:
		var fmesh := MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(absf(Z_FAR) + 8.0, 1.15)
		fmesh.mesh = fq
		var fmat := ShaderMaterial.new()
		fmat.shader = fire_shader
		fmat.set_shader_parameter("base_color",
				_theme_col.lerp(Color(1, 1, 1), 0.3))
		fmat.set_shader_parameter("intensity", 0.0)
		if _world_theme != WorldTheme.GALAXY:
			# Themen-Farbsatz auch fuer die heisse Flammen-Kante (sonst Eisblau).
			fmat.set_shader_parameter("hot_color", _theme_kiai)
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
	var lane_grad := Gradient.new()
	lane_grad.set_color(0, Color(1, 1, 1, 0.0))
	lane_grad.set_color(1, Color(1, 1, 1, 1.0))
	lane_grad.add_point(0.55, Color(1, 1, 1, 0.25))
	var lane_fade := GradientTexture2D.new()
	lane_fade.gradient = lane_grad
	lane_fade.width = 4
	lane_fade.height = 128
	lane_fade.fill_from = Vector2(0, 0)
	lane_fade.fill_to = Vector2(0, 1)
	for i in RAIL_X.size():
		# Receptor = exakt die Notenform: gleiches Quad (PAD_SIZE), gleicher
		# Shader (note_disc, fill_alpha 0 -> reiner Ring), knapp unter der
		# Notenhoehe -> gleicher Durchmesser und gleiche Strichstaerke wie
		# eine ankommende Note an der Linie.
		var pad := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(PAD_SIZE, PAD_SIZE) * _note_k
		pad.mesh = pq
		pad.rotation_degrees = Vector3(-90, 0, 0)
		pad.position = Vector3(RAIL_X[i], ROAD_Y + PAD_Y, Z_LINE)
		var pm := ShaderMaterial.new()
		pm.shader = _note_shader
		pm.set_shader_parameter("base_color", _pad_color(i))
		pm.set_shader_parameter("rim_color", _pad_color(i) * PAD_IDLE)
		pm.set_shader_parameter("fill_alpha", 0.0)
		pm.set_shader_parameter("halo_strength", 0.7)
		pm.set_shader_parameter("rim_boost", 0.0)
		pm.render_priority = -1
		_pad_mats.append(pm)
		_pad_flash.append(0.0)
		pad.material_override = pm
		_world.add_child(pad)
		_pad_nodes.append(pad)
		_pad_groove.append(0.0)
		_pad_groove_col.append(_pad_color(i))
		_pad_dark.append(0.0)
		# MAX-Ring: duenner Ring unter dem Pad (unter Noten und Linie gezeichnet),
		# weitet sich bei MAX kurz auf und verglimmt.
		var mr := MeshInstance3D.new()
		var mrq := QuadMesh.new()
		mrq.size = Vector2(PAD_SIZE, PAD_SIZE) * _note_k
		mr.mesh = mrq
		mr.rotation_degrees = Vector3(-90, 0, 0)
		mr.position = Vector3(RAIL_X[i], ROAD_Y + PAD_Y - 0.03, Z_LINE)
		var mrm := ShaderMaterial.new()
		mrm.shader = _note_shader
		mrm.set_shader_parameter("base_color", _pad_color(i))
		mrm.set_shader_parameter("rim_color", _pad_color(i))
		mrm.set_shader_parameter("fill_alpha", 0.0)
		mrm.set_shader_parameter("halo_strength", 0.35)
		mrm.set_shader_parameter("rim_boost", 0.0)
		mrm.set_shader_parameter("master_alpha", 0.0)
		mrm.render_priority = -2
		mr.material_override = mrm
		mr.visible = false
		_world.add_child(mr)
		_max_rings.append(mr)
		_max_ring_mats.append(mrm)
		_max_ring_t.append(0.0)

		# Lane-Highlight: transparente Bahn, leuchtet solange die Taste
		# gedrueckt ist (Standard-Mania-Feedback).
		var lg := MeshInstance3D.new()
		var lq := QuadMesh.new()
		# Exakt von der Hit-Linie bis zum Horizont — vorher fehlten vorne
		# ~3 Einheiten, der Balken "startete" sichtbar hinter dem Ring.
		# Breite = Ring-Aussendurchmesser; liegt flach auf der Bahn und laeuft
		# damit exakt mit den Schienen zum Fluchtpunkt (perspektivisch).
		lq.size = Vector2(PAD_SIZE * 0.93 * _note_k, absf(Z_FAR - Z_LINE))
		lg.mesh = lq
		lg.rotation_degrees = Vector3(-90, 0, 0)
		lg.position = Vector3(RAIL_X[i], ROAD_Y + 0.006, (Z_LINE + Z_FAR) * 0.5)
		var lgm := StandardMaterial3D.new()
		lgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lgm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var lane_c := _pad_color(i)
		lgm.albedo_color = Color(lane_c.r, lane_c.g, lane_c.b, 0.0)
		# Verlauf: am Receptor sichtbar, zum Horizont hin weg (UV v=0 = fern).
		lgm.albedo_texture = lane_fade
		lg.material_override = lgm
		_world.add_child(lg)
		_lane_glow_mats.append(lgm)
		_pad_judge_col.append(_pad_color(i))

		var label := Label3D.new()
		label.text = _short_key_name(Settings.key_lanes[i])
		# Hohe Font-Aufloesung bei gleicher Weltgroesse — kein Pixelbrei.
		label.font_size = 128
		label.pixel_size = 0.0019
		label.outline_size = 44
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.modulate = Color(0.82, 0.86, 0.95, 0.85)
		label.no_depth_test = true
		# Billboard: Schrift steht immer plan zur Kamera — nicht schraeg
		# auf der Bahn liegend (wirkte gestaucht/verzerrt).
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Satzzeichen ("," ".") sind als Glyphe winzig: deutlich groesser setzen,
		# damit jede Taste gleich gut lesbar ist.
		var key_txt := label.text
		var is_punct := key_txt.length() == 1 and key_txt.to_upper() == key_txt.to_lower() and not key_txt.is_valid_int()
		if is_punct:
			label.pixel_size = 0.0019 * 2.3
		label.pixel_size *= _note_k
		# Mittig IM Pad-Ring statt auf dessen vorderem Rand. Satzzeichen sitzen
		# auf der Schrift-Grundlinie -> etwas anheben, damit sie mittig wirken.
		label.position = Vector3(RAIL_X[i], ROAD_Y + PAD_Y + (0.18 if is_punct else 0.10), Z_LINE)
		_world.add_child(label)

	_build_ship()
	_build_horizon()
	_build_starfield()


## Hitzonen-Farbe: bei "Effekte: Aus" neutral grau statt Songfarbe.
## Kurzer Tastenname fuer die Pad-Beschriftung: Satzzeichen als Zeichen
## ("," statt "Comma"), Buchstaben gross.
## Kamera-Modus aus den Settings (CLI-Override fuer Vorher/Nachher-Bilder).
func _setup_camera_mode() -> void:
	_comfort = Settings.comfort_camera()
	for a in OS.get_cmdline_args():
		if a == "--cam=dyn":
			_comfort = false
		elif a == "--cam=comfort":
			_comfort = true
	if _comfort:
		_cam_pos = Vector3(0, 2.1, 7.6)
		_cam_pitch = -16.0
		_cam_fov = 62.0
		_flow = 0.4
	else:
		_cam_pos = Vector3(0, CAM_Y, CAM_Z)
		_cam_pitch = -15.2
		_cam_fov = 72.0
		_flow = 1.0


func _short_key_name(code: int) -> String:
	match code:
		KEY_COMMA: return ","
		KEY_PERIOD: return "."
		KEY_SEMICOLON: return ";"
		KEY_SLASH: return "/"
		KEY_BACKSLASH: return "\\"
		KEY_APOSTROPHE: return "'"
		KEY_QUOTELEFT: return "`"
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_MINUS: return "-"
		KEY_EQUAL: return "="
		KEY_SPACE: return "SPC"
	return OS.get_keycode_string(code).to_upper()


func _pad_color(i: int) -> Color:
	if _fx_level() <= 0.0:
		return CLEAN_PAD
	return _lane_color(i)


func _lane_color(i: int) -> Color:
	# Alle Spuren gleich kraeftig (QA: Spur 1 kraeftig, 2-3 blass war
	# irritierend) — Trennung kommt ueber Position + Tastenlabel.
	return _theme_col.lerp(Color(1, 1, 1), 0.3)


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
	rq.size = Vector2(ROAD_W_BASE * _lane_k, absf(Z_FAR) + 6.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, (Z_FAR + Z_LINE) * 0.5)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://shaders/road_wave.gdshader")
	_road_mat.set_shader_parameter("base_color", _theme_col)
	road.material_override = _road_mat
	_world.add_child(road)
	if _world_theme == WorldTheme.MONOLITH:
		# Dunkler Unterbau: Himmel-Panele scheinen sonst durch die Lanes.
		var under := MeshInstance3D.new()
		var uq := QuadMesh.new()
		uq.size = rq.size
		under.mesh = uq
		var um := StandardMaterial3D.new()
		um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		um.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		um.albedo_color = Color(0.015, 0.016, 0.02, 0.88)
		um.render_priority = -3
		um.cull_mode = BaseMaterial3D.CULL_DISABLED
		under.material_override = um
		under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		under.rotation_degrees = road.rotation_degrees
		under.position = road.position - Vector3(0, 0.01, 0)
		_world.add_child(under)


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
	_star_mm.instance_count = STAR_COUNT
	for i in STAR_COUNT:
		var h1 := _hash01(float(i) * 12.9898)
		var h2 := _hash01(float(i) * 78.233)
		var h3 := _hash01(float(i) * 39.425)
		var h4 := _hash01(float(i) * 5.393)
		var x := (h1 - 0.5) * 68.0
		var y := h2 * 20.0 - 2.5
		var z0 := h3 * 60.0
		_star_seeds.append(Vector3(x, y, z0))
		_star_scales.append(0.5 + h4 * 1.7)
		# Streifen-Richtung: radial vom Fluchtpunkt weg (Stern fliegt auf
		# die Kamera zu) — einmal vorberechnet, pro Frame nur skaliert.
		_star_rot.append(Basis(Vector3.BACK, atan2(y - _cam_pos.y, x)))
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
	# Mit Panorama-Himmel verdecken die Nebel-Quads ihn -> aus.
	neb.visible = _sky_mat == null
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
	neb2.visible = _sky_mat == null
	_cosmos.add_child(neb2)

	_build_map_bg()

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
	_galaxy_node = gal
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
		# Vor dem Panorama nur noch ein dezenter Nah-Schleier.
		fgm.set_shader_parameter("alpha_mul", 0.20 if _sky_mat == null else 0.10)
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
	_edge_band_mat = ebm
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

	# Kein Schwarzes Loch mehr: die Akkretionsscheibe wirkte am Himmel wie ein
	# Clip-Art-Torus (QA). _bh_mat bleibt null, _process prueft darauf.

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
		if pdef.size() > 8 and str(pdef[8]) != "" and not _2d:
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
	# Runde, weiche Brocken (glow_dot-Maske) — die frueheren unshaded
	# Quads standen als eckige graue Pixel-Quadrate am Horizont.
	var belt_mat := ShaderMaterial.new()
	belt_mat.shader = _glow_shader
	belt_mat.set_shader_parameter("base_color", Color(0.62, 0.58, 0.54))
	belt_mat.set_shader_parameter("intensity", 0.22)
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
	_collect_pulse_mats()


func _collect_pulse_mats() -> void:
	_pulse_mats.clear()
	for m in [_nebula_mat, _nebula_mat2, _galaxy_mat, _aurora_mat]:
		if m != null:
			_pulse_mats.append(m)
	_pulse_mats.append_array(_fg_neb_mats)
	_pulse_mats.append_array(_planet_mats)


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
# Noten auf den Schienen (Scroll-Velocity wie osu!lazer: Abstand ueber
# core.scroll.position, ohne SV/BPM-Wechsel exakt konstante Geschwindigkeit)
# ---------------------------------------------------------------------------

func _note_z(hit_time: float, t: float) -> float:
	var sm := core.scroll
	return Z_LINE - (sm.position(hit_time) - sm.position(t)) / core.preempt * (Z_LINE - Z_FAR)


func _on_note_spawned(index: int) -> void:
	var obj := _beatmap.hit_objects[index] as ManiaNote
	# Notenfarben KLAR vom Spielfeld getrennt (in allen Effekt-Stufen):
	# Hitzone/Umgebung tragen die Songfarbe — normale Noten sind
	# weiss-dominant (leichter Songfarb-Stich), Holds immer amber.
	var clean := _fx_level() <= 0.0
	var themed_note := WorldTheme.has_note_style(_world_theme) and not clean
	var col: Color
	if clean:
		col = CLEAN_HOLD if obj.is_hold else CLEAN_NOTE
	elif themed_note:
		col = WorldTheme.note_color(_world_theme, obj.is_hold)
	elif obj.is_hold:
		col = CLEAN_HOLD
	else:
		col = _theme_col.lerp(Color(1, 1, 1), 0.75)
		if _beatmap.is_kiai(obj.time):
			col = _theme_kiai.lerp(Color(1, 1, 1), 0.55)
	# Snap-Farbe: normale Noten komplett, Holds nur als feiner Innenring am Kopf.
	var snap := _snap_col(index)
	var has_snap := snap.a > 0.0
	if has_snap and not obj.is_hold:
		col = snap
	# Eigene Notenfarben (Modus lanes/snap) ersetzen Map-/Welt-/Snap-Farbe komplett.
	if NoteColors.is_custom(_2d):
		var dv := _snap_divs[index] if index < _snap_divs.size() else 0
		col = NoteColors.color_for(obj.column, obj.is_hold, _2d, col, dv)
		has_snap = false

	var root := Node3D.new()
	if _2d:
		# 2D: nur ein leerer Positions-Traeger (Playfield2D zeichnet die Note),
		# keine Meshes/Shader in der versteckten Welt; Hold-Laenge per _note_z.
		root.position = Vector3(RAIL_X[obj.column], ROAD_Y + 0.32, _note_z(obj.time, _time_ms()))
		_world.add_child(root)
		var dummy := ShaderMaterial.new()
		_notes[index] = { "root": root, "glow": dummy, "rim": dummy, "beam": null,
			"on_beat": false, "col": col }
		return
	# 2D-KONSISTENZ: Die Note ist ein FLACHER Kreis wie das Pad — sie gleitet
	# als Hit-Circle heran und landet exakt AUF dem Pad-Ring (kein 3D-Ball).
	# Kern + Rim in EINEM Quad (note_disc.gdshader): beat/approach pro Frame.
	var disc := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(NOTE_SIZE, NOTE_SIZE)
	disc.mesh = dq
	var rim := ShaderMaterial.new()
	rim.shader = _note_shader
	rim.set_shader_parameter("base_color", col)
	# Gleicher Ring wie das Receptor-Pad (Quad, Shader, Kontur), nur in
	# Notenfarbe und mit zart getoentem Kern -> landet deckungsgleich aufs Pad.
	# Gilt auch fuer Hold-Koepfe (in Hold-Farbe).
	rim.set_shader_parameter("rim_color", col * 1.15)
	rim.set_shader_parameter("fill_alpha", 0.22)
	rim.set_shader_parameter("halo_strength", 0.7)
	rim.set_shader_parameter("rim_boost", 0.3)
	disc.material_override = rim
	disc.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(disc)
	if has_snap and obj.is_hold:
		var inner := MeshInstance3D.new()
		var iq := QuadMesh.new()
		iq.size = Vector2(0.72, 0.72)
		inner.mesh = iq
		var im := ShaderMaterial.new()
		im.shader = _ring_shader
		im.set_shader_parameter("base_color", snap)
		im.set_shader_parameter("radius", 0.34)
		im.set_shader_parameter("approach", 1.0)
		im.set_shader_parameter("intensity", 0.55 if clean else 0.8)
		inner.material_override = im
		inner.rotation_degrees = Vector3(-90, 0, 0)
		inner.position = Vector3(0, 0.01, 0)
		root.add_child(inner)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	# Weicher Leuchtfleck: dezent, damit dichte Muster lesbar bleiben.
	q.size = Vector2(1.55, 1.55)
	glow.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = _glow_shader
	gm.set_shader_parameter("base_color", col)
	gm.set_shader_parameter("intensity", NOTE_GLOW * (0.5 if clean else 1.0))
	glow.material_override = gm
	glow.rotation_degrees = Vector3(-90, 0, 0)
	glow.position = Vector3(0, -0.02, 0)
	root.add_child(glow)
	root.position = Vector3(RAIL_X[obj.column], ROAD_Y + 0.32, _note_z(obj.time, _time_ms()))
	if _note_k < 1.0:
		root.scale = Vector3.ONE * _note_k
	_world.add_child(root)

	# Hold: Energiestrahl (HoldBeam), Laenge pro Frame ueber _note_z (SV-korrekt).
	var beam: HoldBeam = null
	if obj.is_hold:
		beam = HoldBeam.new()
		_world.add_child(beam)
		beam.setup(0.92 * _note_k, col)
		beam.set_span(root.position.z, _note_z(obj.end_time(), _time_ms()),
				RAIL_X[obj.column], ROAD_Y + 0.28)

	# Landelicht: weicher Reflexions-Spot unter der Drohne auf der Road —
	# verbindet Note und Spur optisch (Tiefenanker).
	var spot := MeshInstance3D.new()
	var sq2 := QuadMesh.new()
	sq2.size = Vector2(1.1, 0.8)
	spot.mesh = sq2
	var sm2 := ShaderMaterial.new()
	sm2.shader = _glow_shader
	sm2.set_shader_parameter("base_color", col)
	sm2.set_shader_parameter("intensity", 0.06 if clean else 0.10)
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
		"on_beat": _is_on_beat(obj.time), "col": col }


func _on_note_judged(index: int, result: Dictionary) -> void:
	var q: int = result.quality
	if q == ManiaCore.Quality.MISS:
		_play_miss()
	else:
		_play_hit([1.0, 1.0, 0.944, 0.891, 0.794][q])
	var col: int = result.get("column", 0)
	var hold_end: bool = result.get("hold_end", false)
	if hold_end and bool(result.get("held", false)):
		_fire_laser(col, Vector3(RAIL_X[col], ROAD_Y + 0.32, Z_LINE))
		_pad_flash[col] = 1.0
	if col < _pad_judge_col.size():
		_pad_judge_col[col] = QUALITY_COLOR[q]
	# TREFFER AUF DEM BEAT: Treffer im 300-Fenster pulsen das Pad in der
	# Snap-/Spurfarbe, MAX weitet zusaetzlich kurz einen Ring; Miss dunkelt ab.
	if col < _pad_groove.size():
		if q <= ManiaCore.Quality.PERFECT:
			_pad_groove[col] = 1.0
			var gcol := _snap_col(index) if SNAP_COLORS_ENABLED else Color(0, 0, 0, 0)
			_pad_groove_col[col] = gcol if gcol.a > 0.0 else _lane_color(col)
			if q == ManiaCore.Quality.MAX:
				_max_ring_t[col] = 1.0
		elif q == ManiaCore.Quality.MISS:
			_pad_dark[col] = 1.0
	# FRUEH/SPAET entscheidet JudgeDisplay (erst ausserhalb des 300-Fensters);
	# Hold-Enden ohne Zeitfehler bekommen keinen Hinweis.
	if _pf2d != null:
		_pf2d.on_judge(q, col)   # osu!-Skin: Judgement-Bild, LightingN
	if _judge_disp != null:
		var off: float = 0.0 if hold_end else float(result.get("dt", 0.0))
		_judge_disp.show_judge(q, off)
	if _hp_bar != null:
		if q == ManiaCore.Quality.MISS:
			_hp_bar.flash_miss()
		elif _hp_flash_cd <= 0.0 and core.hp < 0.999:
			# Ruhiger Glanz nur, solange sich die Leiste erholt (max. alle 0,6 s).
			_hp_bar.flash_hit()
			_hp_flash_cd = 0.6
	if not _2d:
		_sparks.spark(col, q)
		if _skill_fx != null:
			_skill_fx.on_judge(col, q)
		if q != ManiaCore.Quality.MISS:
			_sparks.lane_shot(col)
	_ur_tick(result)
	_acc_trace.append(core.accuracy())
	if hold_end:
		if bool(result.get("held", false)):
			_hold_ok += 1
		else:
			_hold_drop += 1
	if q != ManiaCore.Quality.MISS and result.has("dt"):
		_hit_offsets.append(float(result.dt))
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
			var miss_mat := entry.rim as ShaderMaterial
			# Verpasst: entsaettigt grau (kein Rot quer uebers Spielfeld —
			# Rot gibt es nur auf dem Pad bzw. der HP-Leiste).
			miss_mat.set_shader_parameter("rim_color", Color(0.42, 0.43, 0.47))
			miss_mat.set_shader_parameter("base_color", Color(0.16, 0.16, 0.19))
			if _2d and not (_beatmap.hit_objects[index] as ManiaNote).is_hold:
				_missed_2d.append([_beatmap.hit_objects[index].time, col])
			var tw := create_tween()
			tw.tween_property(node, "position:z", SHIP_Z + 6.0, 0.35)
			tw.parallel().tween_property(node, "scale", Vector3.ONE * 0.3, 0.35)
			tw.tween_callback(node.queue_free)
		var hb: HoldBeam = entry.beam
		if hb != null or (_2d and (_beatmap.hit_objects[index] as ManiaNote).is_hold):
			var hobj := _beatmap.hit_objects[index] as ManiaNote
			var dropped: bool = result.get("hold_end", false) and not result.get("held", true)
			if q == ManiaCore.Quality.MISS or dropped:
				# Rest des Holds scrollt entsaettigt weiter (Loslassen sichtbar).
				if hb != null:
					hb.set_state(HoldBeam.STATE_RELEASED)
				_released_beams.append({ "beam": hb,
					"head": maxf(hobj.time, _time_ms()) if dropped else hobj.time,
					"end": hobj.end_time(), "col": hobj.column })
			elif hb != null:
				hb.queue_free()
	if q == ManiaCore.Quality.MISS:
		_last_milestone = 0
	else:
		var c := core.combo
		if (c == 25 or c == 50 or (c >= 100 and c % 100 == 0)) and c != _last_milestone:
			_last_milestone = c
			if c >= 50 and _use_audio:
				Sfx.milestone(c)
			# Milestone-Belohnung: Sternschnuppe zieht ueber den Himmel.
			if c >= 50 and _fx_level() > 0.0 and not _2d:
				_spawn_shooting_star(c)
				if _skill_fx != null:
					_skill_fx.on_milestone(c)
			# OVERDRIVE: ab Combo 100 schlaegt alle 100 der Blitz ein.
			if c >= 100 and c % 100 == 0:
				_trigger_overdrive()
	_update_hud()


## OVERDRIVE bei grossen Combos: Pads/Kanten kippen 2 Sekunden weich in die
## Kiai-Farbe. Kein Flash, kein Beben, keine Bildverzerrung.
func _trigger_overdrive() -> void:
	var fx := _fx_level()
	if fx <= 0.0:
		return
	_overdrive = 2.0 * fx


func _on_hold_started(index: int, quality: int) -> void:
	_play_hit(1.0)
	# Hold-Kopf zaehlt fuer UR-Leiste und Trefferfehler wie eine normale Note.
	var head_dt := core.hold_head_dt(index)
	_ur_tick({"dt": head_dt, "quality": quality})
	_hit_offsets.append(head_dt)
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
	if _2d:
		return  # 2D: Hit-Licht macht Playfield2D am Receptor.
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
	# Halbiert ggue. frueher (1.1/1.35): Treffer bestaetigen, nicht blenden.
	var peak := (0.55 if fx <= 0.0 else 0.68) * power
	fm.set_shader_parameter("intensity", peak)
	flash.material_override = fm
	flash.position = target
	flash.rotation_degrees = Vector3(-9, 0, 0)
	_world.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * PAD_MAX_SCALE, 0.15)
	tw.parallel().tween_method(
		func(v): fm.set_shader_parameter("intensity", v), peak, 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

	# Weicher Halo hinter dem Kern: groesser, schwaecher, langsamer — gibt
	# dem Einschlag Tiefe statt nur eines flachen Blitzes.
	var halo := MeshInstance3D.new()
	var hq2 := QuadMesh.new()
	hq2.size = Vector2(1.6, 1.6)
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
	htw.tween_property(halo, "scale", Vector3.ONE * PAD_MAX_SCALE, 0.24)
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
	var rpeak := (0.4 if fx <= 0.0 else 0.75) * power
	rm.set_shader_parameter("intensity", rpeak)
	rm.set_shader_parameter("radius", 0.06)
	rm.set_shader_parameter("beat", _beat_env * 0.6)
	rm.set_shader_parameter("approach", 1.0)
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
	var bpeak := 0.35 * power * fx
	bm.set_shader_parameter("intensity", bpeak)
	beam.material_override = bm
	beam.position = Vector3(target.x, ROAD_Y + 1.0, target.z)
	_world.add_child(beam)
	var btw := create_tween().set_parallel(true)
	btw.tween_property(beam, "position:y", ROAD_Y + 1.7, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	btw.tween_property(beam, "scale:y", PAD_MAX_SCALE, 0.22)
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


func _ur_tick(result: Dictionary) -> void:
	# Timing-Tick auf der HitErrorBar (nur Hits mit bekanntem Fehler).
	if not result.has("dt"):
		return
	var dt: float = result.dt
	var q: int = result.quality
	if q == ManiaCore.Quality.MISS:
		return
	_dt_n += 1
	_dt_sum += dt
	_dt_sqsum += dt * dt
	if _err_bar != null:
		_err_bar.add_hit(dt)
	# Gleitender Mittelwert fuer die Timing-Toenung der Strecke.
	_ur_ema = lerpf(_ur_ema, dt, 0.2)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended or GameSession.is_replay or _autoplay:
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


## Autoplay: Taste exakt zur Notenzeit, Holds bis end_time, sonst 40 ms.
## Zeitstempel wie beim Replay -> Judgement bleibt unveraendert.
func _run_autoplay(t: float) -> void:
	for c in _auto_release.size():
		var rel := _auto_release[c]
		if rel >= 0.0 and rel <= t:
			core.key_up(c, rel)
			_lane_held[c] = false
			_auto_release[c] = -1.0
	var objs := _beatmap.hit_objects
	while _auto_idx < objs.size() and objs[_auto_idx].time <= t:
		var n := objs[_auto_idx] as ManiaNote
		_auto_idx += 1
		var c := n.column
		if c < 0 or c >= _auto_release.size():
			continue
		if _auto_release[c] >= 0.0:
			core.key_up(c, minf(_auto_release[c], n.time))
			_auto_release[c] = -1.0
		core.key_down(c, n.time)
		_lane_held[c] = true
		_auto_release[c] = n.end_time() if n.is_hold else n.time + 40.0


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


## SkillFx pro Frame. Effekt-Intensitaet skaliert: Aus = unsichtbar,
## Dezent = hoechstens Stufe 2 und gedaempfte Shader-Intensitaet.
func _update_skill_fx(delta: float, fx: float) -> void:
	if _skill_fx == null:
		return
	_skill_fx.visible = fx > 0.0
	if fx <= 0.0:
		return
	var combo := core.combo
	if fx < 1.0:
		combo = mini(combo, SkillFx.COMBO_TIERS[2] - 1)
	_skill_fx.update(delta, _clock.beat_phase, _clock.beat_env, combo,
			core.accuracy(), _kiai_mix, lerpf(0.4, 1.0, _music_energy))
	if fx < 1.0:
		for m in _skill_fx.get_children():
			var mi := m as MeshInstance3D
			if mi == null or not mi.visible:
				continue
			var sm := mi.material_override as ShaderMaterial
			if sm != null:
				var inten: float = sm.get_shader_parameter(&"intensity")
				sm.set_shader_parameter(&"intensity", inten * fx)


## Globaler Effekt-Faktor aus den Einstellungen (Aus/Dezent/Voll).
func _fx_level() -> float:
	match Settings.tunnel_intensity:
		0:
			return 0.0
		1:
			return 0.5
	return 1.0


func _do_skip() -> void:
	SyncClock.seek_ms(_beatmap.hit_objects[0].time - 2200.0)
	_update_break_overlay(_beatmap.hit_objects[0].time - 2200.0)


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
	if _autoplay:
		_run_autoplay(t)
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
		if _2d:
			# 2D: nur Position + Hold-Zustand, keine 3D-Shader-Updates.
			if obj.is_hold and core.active_hold(obj.column) == index:
				var h2 := clampf((t - obj.time) / 600.0, 0.0, 1.0)
				_pad_flash[obj.column] = maxf(_pad_flash[obj.column], 0.5 + h2 * 0.3)
			continue
		# Lock-On: im Fenster leuchtet die Drohne weiss auf.
		var until := obj.time - t
		var lock: bool = absf(until) <= core.w50
		# Beat-Anticipation: Noten, die AUF dem Beat landen, glimmen im
		# Anflug leicht heller und pulsieren mit der Beat-Huellkurve.
		var rim_base := 0.3
		if bool(entry.get("on_beat", false)):
			rim_base = 0.4 + _beat_env * 0.2
		var nmat := entry.rim as ShaderMaterial
		nmat.set_shader_parameter("rim_boost", 1.0 if lock else rim_base)
		nmat.set_shader_parameter("beat", _beat_env * 0.6)
		nmat.set_shader_parameter("approach",
				clampf((root.position.z - Z_FAR) / (Z_LINE - Z_FAR), 0.0, 1.0))
		(entry.glow as ShaderMaterial).set_shader_parameter("intensity",
				NOTE_GLOW * (1.4 if lock else 1.0) * (0.5 if _fx_level() <= 0.0 else 1.0))
		var beam: HoldBeam = entry.beam
		if beam != null:
			beam.set_span(root.position.z, _note_z(obj.end_time(), t),
					RAIL_X[obj.column], ROAD_Y + 0.28)
			beam.set_beat(_beat_env)
			# Halten: Strahl wird heiss, das Pad leuchtet dauerhaft mit.
			if core.active_hold(obj.column) == index:
				if not bool(entry.get("held", false)):
					entry["held"] = true
					beam.set_state(HoldBeam.STATE_HELD)
				var held_t: float = clampf((t - obj.time) / 600.0, 0.0, 1.0)
				_pad_flash[obj.column] = maxf(_pad_flash[obj.column], 0.5 + held_t * 0.3)
	for ri in range(_released_beams.size() - 1, -1, -1):
		var rb: Dictionary = _released_beams[ri]
		var rbeam: HoldBeam = rb.beam
		var z_end := _note_z(float(rb.end), t)
		if z_end > Z_LINE + 4.0:
			if rbeam != null:
				rbeam.queue_free()
			_released_beams.remove_at(ri)
			continue
		if rbeam != null:
			rbeam.set_span(_note_z(float(rb.head), t), z_end, RAIL_X[int(rb.col)], ROAD_Y + 0.28)
	if _pf2d != null:
		_update_playfield_2d(t)

	for c in core.columns:
		_pad_flash[c] = move_toward(_pad_flash[c], 0.0, delta * 5.0)
		if c < _pad_groove.size():
			_pad_groove[c] = maxf(_pad_groove[c] - delta / 0.18, 0.0)
			_pad_dark[c] = maxf(_pad_dark[c] - delta / 0.25, 0.0)
			_max_ring_t[c] = maxf(_max_ring_t[c] - delta / 0.20, 0.0)
			var mr_on := _max_ring_t[c] > 0.0 and _fx_level() > 0.0
			_max_rings[c].visible = mr_on
			if mr_on:
				var rr := 1.0 - _max_ring_t[c]
				# Ease-out: schnell auf, weich aus; max 1.22 (bleibt am Pad).
				_max_rings[c].scale = Vector3.ONE * (1.0 + 0.22 * (1.0 - (1.0 - rr) * (1.0 - rr)))
				_max_ring_mats[c].set_shader_parameter("rim_color", _pad_groove_col[c] * 1.3)
				_max_ring_mats[c].set_shader_parameter("master_alpha",
						_max_ring_t[c] * 0.85 * _fx_level())
		# Gedrueckte Spur leuchtet dezent auf (schnell rein, weich raus) —
		# in den Einstellungen abschaltbar.
		if c < _lane_glow_mats.size():
			var lm: StandardMaterial3D = _lane_glow_mats[c]
			var target := 0.16 if _lane_held[c] and Settings.lane_glow else 0.0
			lm.albedo_color.a = move_toward(lm.albedo_color.a, target,
				delta * (1.4 if _lane_held[c] else 0.5))

	# Globaler Effekt-Faktor (Einstellungen: Aus/Dezent/Voll).
	var fx := _fx_level()

	# Laser abklingen.
	# OVERDRIVE abklingen lassen.
	_overdrive = maxf(_overdrive - delta, 0.0)
	# Takt exakt aus BeatClock: Angriff liegt auf dem Schlag, Release bleibt
	# weich (~380 ms — atmet, statt zu blitzen).
	# Nur visuelle Pulse: Bild-Latenz-Zeit statt Judgement-Zeit.
	var vt: float = SyncClock.visual_time_ms() if _use_audio else t + SyncClock.visual_offset_ms()
	_clock.update(vt, delta)
	_vt = vt
	_hp_flash_cd = maxf(_hp_flash_cd - delta, 0.0)
	if _judge_disp != null:
		_judge_disp.beat(_clock.beat_env)
	_beat_env = maxf(_clock.beat_env, _beat_env - delta * 2.6)
	if _2d:
		# 2D: versteckte 3D-Welt nicht simulieren (FX, Himmel, Kapitel, Funken).
		_process_tail(t, delta)
		return
	_sparks.update(delta)
	_update_skill_fx(delta, fx)

	# NOTENDICHTE (naechste Sekunde) -> Intensitaets-Surge bei Bursts;
	# keine Note in 2.5s -> Break/Cruise, Rueckkehr mit Flash.
	var upcoming := 0
	var upcoming2 := 0
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
		if obj2.time <= t + 2000.0:
			upcoming2 += 1
		else:
			break
	_density = lerpf(_density, clampf(float(upcoming) / 8.0, 0.0, 1.0), minf(delta * 4.0, 1.0))
	# Groove-Dichte: Noten pro Sekunde der naechsten 2 s (10 NPS = voll).
	_density2 = lerpf(_density2, clampf(float(upcoming2) / 20.0, 0.0, 1.0), minf(delta * 3.0, 1.0))
	var now_break := next_gap > 2500.0
	if _in_break and not now_break:
		# Comeback: Flash + Glut-Salve kuendigen den Wiedereinstieg an —
		# erst auf dem naechsten Schlag (Strecke pulst nur im Takt).
		_comeback_pending = true
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
		_ember_mat.set_shader_parameter("base_color", _theme_col.lerp(Color(1, 1, 1), burn * 0.5))
	# Rand-Glut: Combo laesst den Bildschirmrand gluehen, ab ~150 brennt er.
	if _vignette_mat != null:
		# Kein roter HP-Alarm am Bildschirmrand mehr (faerbte das Spielfeld) —
		# Warnung zeigt nur die HP-Leiste.
		_vignette_mat.set_shader_parameter("intensity",
			(clampf(float(core.combo) / 200.0, 0.0, 1.0) * 0.26 + _kiai_mix * 0.10
			+ _overdrive * 0.10) * fx + _beat_env * 0.045)
		_vignette_mat.set_shader_parameter("burn", burn * 0.65)
		_vignette_mat.set_shader_parameter("glow_color", _theme_col)
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
	_punch = move_toward(_punch, 0.0, delta * 6.0)
	# SUB-BASS-KICK (30-100 Hz): Onset gegen gleitenden Mittelwert, kurzer
	# gedeckelter Puls (Analyse bleibt Pre-EQ, Judgement unberuehrt).
	var sub_raw := SyncClock.band_energy(30.0, 100.0)
	_sub = maxf(sub_raw, move_toward(_sub, 0.0, delta * 2.6))
	_sub_avg = lerpf(_sub_avg, sub_raw, minf(delta * 1.2, 1.0))
	_kick_cooldown = maxf(_kick_cooldown - delta, 0.0)
	if sub_raw - _sub_avg > 0.10 and _kick_cooldown <= 0.0:
		_kick = 1.0
		_kick_cooldown = 0.16
	_kick = move_toward(_kick, 0.0, delta * 4.5)
	if _clock.is_downbeat_edge:
		_star_burst = 1.0
	_star_burst = move_toward(_star_burst, 0.0, delta * 2.5)

	var pulse: float = maxf(maxf(_beat_env, _bass * 1.05), _punch)
	var kiai_now := _clock.kiai
	_kiai_mix = _clock.kiai_mix
	# STAERKE = MUSIK: Bass + Gesamtenergie, ueber ~1 Beat geglaettet —
	# leise Parts bleiben ruhig, der Drop knallt.
	var beat_s := 60.0 / _clock.bpm if _clock.bpm > 1.0 else 0.5
	var full_raw := SyncClock.band_energy(30.0, 8000.0)
	var e_raw := clampf((bass_raw * 0.6 + full_raw * 0.4 - 0.35) / 0.5, 0.0, 1.0)
	_music_energy = lerpf(_music_energy, e_raw, 1.0 - exp(-delta / beat_s))

	# BEAT-KANTE: alles hier feuert EXAKT auf dem Schlag.
	# Kiai-Eintritt merken: der Licht-Sweep startet genau auf dem naechsten Schlag.
	if _clock.kiai and not _groove_kiai_seen:
		_kiai_sweep_pending = true
	_groove_kiai_seen = _clock.kiai
	if _clock.is_beat_edge:
		_on_beat_edge(_clock.beat_index, _clock.is_downbeat_edge)
	_update_groove(vt)
	_update_beat_waves(vt)
	# STRECKEN-PULS NUR AUS BEATCLOCK-KANTEN (Bild-Zeit): keine Bass-/Kick-
	# Onsets auf Bahn, Kanten und Linie — die lagen beliebig zwischen den
	# Schlaegen (gemessen 95 ms Phasenstreuung). Phase/Groove kommen aus
	# _clock auf SyncClock.visual_time_ms, Energie ist ueber 1 Beat geglaettet.
	var road_e := 0.5 + (_music_energy * 0.7 + _kiai_mix * 0.4 + _density * 0.35) * fx
	if _road_mat != null:
		_road_mat.set_shader_parameter("beat_phase", _clock.beat_phase)
		_road_mat.set_shader_parameter("bar_phase", _clock.bar_phase)
		_road_mat.set_shader_parameter("punch", clampf(_groove_down, 0.0, 1.0))
		_road_mat.set_shader_parameter("wave_amount", fx)
		_road_mat.set_shader_parameter("energy", road_e)
		# Strecke bleibt in der Songfarbe (kein Timing-/Kiai-Farbkippen —
		# wandernde Fremdfarben auf dem Spielfeld stoerten).
		_road_mat.set_shader_parameter("base_color",
				_theme_col * 0.5 if _world_theme == WorldTheme.MONOLITH else _theme_col)

	# Die ABFANGLINIE pulsiert im Takt — der Hit-Moment ist hoerbar UND sichtbar.
	_line_mat.emission_energy_multiplier = 1.1 + _beat_env * 1.6 + _line_flash * 1.0 \
			+ _groove * 3.0
	_line_mat.emission = Color(1, 1, 1).lerp(_theme_col, _kiai_mix * 0.4)
	var pad_energy: Array[float] = []
	var edge_themed := _world_theme != WorldTheme.GALAXY and _world_theme != WorldTheme.NEON
	var beat_k := minf(maxf(_groove, 0.0), 1.0)
	for i in _pad_mats.size():
		var pf := clampf(_pad_flash[i], 0.0, 1.0)
		if edge_themed:
			# Themen-Welten: Ring ruhig unter den Noten, Beat max +15 %.
			pad_energy.append((PAD_IDLE if fx > 0.0 else 0.75) * PAD_THEMED_K
					* (1.0 + EDGE_THEMED_BEAT * beat_k * fx) + pf * PAD_PRESS)
		else:
			pad_energy.append((PAD_IDLE if fx > 0.0 else 0.75)
					+ (pulse * 0.08 + _punch * 0.06 + _kick * 0.03) * fx
					+ pf * PAD_PRESS + _groove * 1.0)
		# Druck-Feedback: Ring waechst dezent (max 1.15), kein Ueberstrahlen.
		# Der Takt-Schlag hebt nur die Helligkeit, Groesse hoechstens 1.04.
		if i < _pad_nodes.size():
			_pad_nodes[i].scale = Vector3.ONE * maxf(1.0 + (PAD_MAX_SCALE - 1.0) * pf,
					1.0 + minf(_groove, 1.0) * 0.04)
	for m in _edge_mats:
		var ee := (0.28 if fx <= 0.0 else 0.4) \
				+ (_music_energy * 0.9 + _density * 0.6
				+ _kiai_mix * 0.7) * fx
		if edge_themed:
			# Themen-Welten: Grundton ~40 %, Beat-Puls max +15 %, nie ueber
			# 40 % der alten Obergrenze (Rand-Baender nicht ausbrennen lassen).
			m.emission_energy_multiplier = minf(ee * EDGE_THEMED_K
					* (1.0 + EDGE_THEMED_BEAT * beat_k * fx), EDGE_MAX_THEMED * EDGE_THEMED_K)
		else:
			m.emission_energy_multiplier = ee + _groove * 3.0

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
		# Themen-Welten: Flammenwaende ~40 % Grundton, Beat max +15 %
		# (Beat-Anteil in rail_fire zusaetzlich gedaempft, _update_groove).
		fmat3.set_shader_parameter("intensity",
				_fire_level * 0.55 * EDGE_THEMED_K * (1.0 + EDGE_THEMED_BEAT * 0.5 * _beat_env) * fx
				if edge_themed else _fire_level * (0.55 + 0.45 * _beat_env) * fx)
		fmat3.set_shader_parameter("heat", _fire_heat)
		fmat3.set_shader_parameter("t", t / 1000.0)

	# DROP: Kiai-Start gibt den Sternen einen Warp-Schub (Hintergrund).
	if kiai_now and not _was_kiai:
		_start_drop_warp()
	_was_kiai = kiai_now

	# OVERDRIVE aktiv: Farben kippen weich (kein Flackern der Linie).
	# Farben werden pro Frame von der BASIS aus gemischt (kein Aufschaukeln).
	var od := clampf(_overdrive, 0.0, 1.0)
	for i in _pad_mats.size():
		var base_col := _pad_color(i)
		if i < _pad_judge_col.size():
			base_col = base_col.lerp(_pad_judge_col[i], clampf(_pad_flash[i], 0.0, 1.0) * 0.65)
		var pcol := base_col.lerp(_theme_kiai, od * 0.45)
		var pg := 0.0
		var dark := 1.0
		if i < _pad_groove.size():
			pg = _pad_groove[i] * fx
			pcol = pcol.lerp(_pad_groove_col[i], pg * 0.55)
			dark = 1.0 - _pad_dark[i] * 0.6
		_pad_mats[i].set_shader_parameter("base_color", pcol)
		_pad_mats[i].set_shader_parameter("rim_color", pcol * (pad_energy[i] + pg * 0.5) * dark)
	for em2 in _edge_mats:
		var edge_col := Color(0.45, 0.47, 0.53) if fx <= 0.0 \
				else _theme_col
		if fx > 0.0 and _fire_level > 0.0:
			# Brennende Kanten gluehen heller in der Songfarbe (kein Orange/Rot
			# entlang des Spielfelds), bei Perfection fast weiss.
			var glow_col := _theme_col.lerp(Color(1, 1, 1), 0.45 + _fire_heat * 0.4) \
					if not edge_themed else _theme_col.lerp(Color(1, 1, 1), 0.10 + _fire_heat * 0.10)
			edge_col = edge_col.lerp(glow_col, _fire_level * 0.7)
		em2.emission = edge_col

	# REISE-UHR: Beat-Schub-Distanz — jeder Downbeat schiebt sichtbar an,
	# dazwischen gleitet man aus. Bei Effekte=Aus laeuft die Reise linear
	# (gleiches Ziel, ohne Ruckeln). Docking bleibt zeitbasiert.
	# Komfort: Reise linear (kein Beat-Ruck der Planeten-Route).
	_travel += delta * ((0.55 + _beat_env * 1.1) if fx > 0.0 and not _comfort else 0.82)
	var journey_p := clampf(_travel * 1000.0 / (_song_len_ms * 0.82), 0.0, 1.0)
	var dock_mix := clampf((t - (_song_len_ms - 5000.0)) / 5000.0, 0.0, 1.0)
	dock_mix = dock_mix * dock_mix * (3.0 - 2.0 * dock_mix)

	# KAMERA bleibt ruhig: festes FOV, feste Position (kein Zoom-Pumpen,
	# kein Beat-Schub). Tempo-Gefuehl kommt nur aus Sternen/Staub.
	_camera.fov = _cam_fov
	_camera.position = _cam_pos

	# HYPERSPACE: Der Drop reisst die Sterne ~1.5s zu Lichtfaeden.
	_warp_level = move_toward(_warp_level, 0.0, delta * 0.7)
	_update_world_beat(fx)

	# REISE IM TAKT: Grundtempo folgt BPM (live aus BeatClock) und
	# Musikenergie; jeder Schlag stoesst nach vorn (_surge), das
	# Docking-Finale bremst die Reise sanft aus.
	var bpm_live := clampf((_clock.bpm if _clock.bpm > 1.0 else 140.0) / 140.0, 0.7, 1.6)
	var cruise := 9.0 * bpm_live * (0.75 + (_music_energy * 0.45 + _kiai_mix * 0.5 + _density * 0.2) * fx)
	# Komfort: Fluss UND Schub auf _flow (~40 %) — weniger Vection am Rand.
	var surge_m := _surge * _flow
	_star_scroll += delta * _flow * (cruise * (1.0 + surge_m) + (_warp_level * 55.0 + _star_burst * 18.0) * fx * _flow) * (1.0 - dock_mix * 0.75)
	# Panorama: ferne Sternen-Ebene stroemt langsamer (Parallaxe), gleicher
	# Beat-Schub; Welt-Puls + minimaler Warp auf dem Schlag.
	if _sky_mat != null:
		_sky_phase += delta * _flow * (0.05 * cruise / 9.0 * (1.0 + surge_m * fx) + _warp_level * 0.45 * fx * _flow) * (1.0 - dock_mix * 0.75)
		_sky_mat.set_shader_parameter(&"star_phase", _sky_phase)
		_sky_mat.set_shader_parameter(&"beat_pulse", clampf(_world_pulse, 0.0, 1.0))
		var sw := clampf(_warp_level * 0.7 + maxf(_surge, 0.0) * 0.05, 0.0, 1.0) * fx
		# Komfort: keine Warp-Streckung, kein Rollen der Sternen-Ebene.
		_sky_mat.set_shader_parameter(&"warp", sw if sw > 0.03 and not _comfort else 0.0)
		# Komfort-Regel: nie um die Blickachse rollen (Kopfschmerzen).
		_sky_mat.set_shader_parameter(&"stars_rotation", Vector3.ZERO)
	_update_theme_sky(delta)
	# Kurze Streifen auf dem Schlag (radial, minimal), Hyperspace laenger.
	var warp_stretch := 1.0 if _comfort else 			1.0 + maxf(_surge, 0.0) * 0.8 + _warp_level * 4.0 * fx
	var cy := _cam_pos.y + _cosmos_lift
	for i in (0 if _2d else _star_seeds.size()):
		var seed := _star_seeds[i]
		var z := fmod(seed.z + _star_scroll, 60.0) - 52.0
		# Mitte hinter der Strecke bleibt dunkel: Sterne nahe dem
		# Fluchtpunkt schrumpfen weg (projizierter Abstand zur Bildmitte).
		var rr := Vector2(seed.x, seed.y - cy).length() / maxf(_cam_pos.z - z, 0.5)
		var sc := _star_scales[i] * smoothstep(0.07, 0.2, rr)
		# Streifen werden laenger UND schmaler (Lichtstrich statt Ellipse).
		var basis := _star_rot[i] * Basis.from_scale(Vector3(sc * warp_stretch, sc / sqrt(warp_stretch), sc))
		_star_mm.set_instance_transform(i, Transform3D(basis, Vector3(seed.x, seed.y, z)))

	# GALAXIEN-REISE: Kapitel aus der IntensityMap (Kiai-Start, Break-Ende,
	# alle 32 Takte), Start immer auf einem Downbeat. Ueberblendung exakt ab
	# dem Downbeat ueber CH_FADE_BEATS Schlaege, in Bild-Zeit (wie BeatClock).
	_update_chapters(vt, fx)

	# Spiralgalaxie: traege Rotation, im Kiai etwas heller.
	if _galaxy_mat != null:
		_galaxy_mat.set_shader_parameter("t", t / 1000.0)
		_galaxy_mat.set_shader_parameter("intensity",
			(0.26 + _kiai_mix * 0.13 + _ch_kiai_w * 0.10 + _beat_env * 0.04) * maxf(fx, 0.25))
	# Vordergrund-Nebelfetzen driften deutlich schneller (Nah-Parallaxe).
	for fgm2 in _fg_neb_mats:
		# Komfort: Nah-Parallaxe am Rand deutlich ruhiger.
		fgm2.set_shader_parameter("drift", _nebula_drift * (1.4 if _comfort else 3.4))
		fgm2.set_shader_parameter("energy", 0.35 + (_bass * 0.3 + _kick * 0.15 + _beat_env * 0.2) * fx)

	# SONNENAUFGANG: waechst ueber das letzte Kapitel — Ankunft im Licht.
	_sunrise = 0.0
	if _gal_chapters.size() >= 2 and _gal_idx >= _gal_chapters.size() - 1:
		var last_t := float(_gal_chapters[_gal_chapters.size() - 1].t)
		_sunrise = clampf((t - last_t) / maxf(_song_len_ms - last_t, 1.0), 0.0, 1.0)
	if _sun_mat != null:
		_sun_mat.set_shader_parameter("intensity",
			(_sunrise * 0.34 + dock_mix * 0.14) * fx)
	# HUD-Route + Doppelstern-Kreisen.
	_route_p = journey_p
	if _route_ui != null:
		_route_ui.queue_redraw()
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
	_nebula_drift += delta * (1.0 + (_beat_env * 0.4 + _kiai_mix * 0.5) * fx + surge_m * 0.45) * _bpm_factor
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
		_nebula_mat.set_shader_parameter("alpha_mul", 1.0 - _kiai_mix * 0.25)
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
				_theme_col.lerp(Color(1, 1, 1), _sunrise * 0.3))
			_road_mat.set_shader_parameter("refl_amount", (0.20 + _beat_env * 0.08) * fx)
		if _nebula_mat2 != null:
			_nebula_mat2.set_shader_parameter("drift", _nebula_drift * 1.8)
			_nebula_mat2.set_shader_parameter("pulse", _beat_env * 0.6)
			_nebula_mat2.set_shader_parameter("energy",
				0.4 + (_bass * 0.4 + _kick * 0.2 + _kiai_mix * 0.4) * fx + _beat_env * 0.15)
	# Horizont atmet mit Takt und Bass — verankert den Beat im ganzen Bild.
	if _horizon_mat != null:
		# Beim Docking glueht der Horizont waermer auf — Ankunftslicht.
		_horizon_mat.set_shader_parameter("intensity",
			(0.10 + _beat_env * 0.10 + _bass * 0.05 + dock_mix * 0.15 + _sunrise * 0.08) * (1.0 + _world_pulse * 0.3))
	if _aurora_mat != null:
		_aurora_mat.set_shader_parameter("drift", t / 1000.0)
		_aurora_mat.set_shader_parameter("pulse", _beat_env)
		for pm2 in _planet_mats:
			pm2.set_shader_parameter("intensity", 0.85 + (_nebula_kick * 0.12 + _bass * 0.08) * fx)
			pm2.set_shader_parameter("t", t / 1000.0)
		_nebula_mat.set_shader_parameter("energy",
			0.5 + (_bass * 0.6 + _kick * 0.25 + _sub * 0.1 + _kiai_mix * 0.9 + _nebula_kick * 0.4) * fx
			+ _beat_env * 0.22 + _groove * 0.35)
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
		pn.scale = Vector3.ONE * journey_scale * (1.0 + _world_pulse * 0.02)

	# SCREEN-FX: nur ruhige Vignette (keine Aberration/Schockwelle/Glitch).
	if _screen_mat != null:
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

	# FLUGPLAN abarbeiten (Break-Kino).
	while _flight_idx < _flight_plan.size() and t >= float(_flight_plan[_flight_idx].t):
		_run_flight_event(_flight_plan[_flight_idx], t)
		_flight_idx += 1
	# KOSMOS: kein Roll/Bank mehr (kippte das ganze Bild). Nur in Breaks
	# sinkt der Hintergrund langsam ab (4s Smoothstep) — wirkt wie Steigflug.
	# Komfort: Horizont bleibt stehen (kein Break-Gleiten/Absinken).
	if fx <= 0.0 or _comfort:
		_cosmos_lift_target = 0.0
	_lift_phase = move_toward(_lift_phase,
			1.0 if _cosmos_lift_target > 0.1 else 0.0, delta / 4.0)
	_cosmos_lift = smoothstep(0.0, 1.0, _lift_phase) * 2.4
	if _cosmos != null:
		_cosmos.position = Vector3(0, -_cosmos_lift, 0)
	if _star_mat != null:
		# Im Hyperspace brennen die Lichtfaeden deutlich heller.
		_star_mat.set_shader_parameter("intensity",
			0.35 + (_treble * 0.30 + _kick * 0.10 + _sub * 0.05 + _star_burst * 0.15 + _warp_level * 0.5) * fx \
			+ _beat_env * 0.07 + _world_pulse * 0.14)

	_process_tail(t, delta)


## Ende jedes Frames (3D und 2D): Break-Overlay, MP-Score, Fail, HUD.
func _process_tail(t: float, delta: float) -> void:
	_update_break_overlay(t)
	# Multiplayer: eigenen Live-Score ~4x pro Sekunde teilen.
	if Lobby.active and Lobby.in_game and not _ended:
		_mp_send_t -= delta
		if _mp_send_t <= 0.0:
			_mp_send_t = 0.25
			if _mp_demo:
				_mp_demo_send()
			else:
				Lobby.send_score(core.score, core.combo, core.accuracy())
	if _mp_demo:
		_mp_demo_step(delta)
	if core.failed and not _mp_demo:
		_show_results(true)
	_update_hud()


## Gemeinsame Beat-Huellkurven der Umgebung aus der BeatClock-Phase
## (visuelle Zeit, framerate-unabhaengig, Attack exakt auf dem Schlag):
## _surge = Vorwaerts-Stoss, Saegezahn (1 - Phase)^3 ueber den ganzen Beat;
## _world_pulse = Helligkeit, Decay ~180 ms. Effekte=Aus -> beides 0.
func _update_world_beat(fx: float) -> void:
	if fx <= 0.0 or _clock.bpm <= 1.0:
		_surge = 0.0
		_world_pulse = 0.0
		_apply_world_pulse()
		return
	var ph := clampf(_clock.beat_phase, 0.0, 1.0)
	var bl := 60000.0 / _clock.bpm
	var peak := _edge_peak * (SURGE_DOWN if _edge_down else 1.0)
	# Mittelwert von (1-ph)^3 = 0.25 -> Grundtempo bleibt im Mittel erhalten:
	# Schub 0.35 .. ~3x direkt auf dem Schlag.
	_surge = (peak * 2.6 * pow(1.0 - ph, 3.0) - 0.65) * fx
	_world_pulse = peak * (1.15 if _edge_down else 1.0) * exp(-ph * bl / WORLD_PULSE_DECAY_MS) * fx
	_apply_world_pulse()


## Dieselbe Huellkurve auf alle Himmels-Materialien (Nebel, Galaxien,
## Aurora, Planeten, Horizontlinie) — die Welt atmet als eines.
func _apply_world_pulse() -> void:
	var wp := _world_pulse
	for m in _pulse_mats:
		m.set_shader_parameter(&"world_pulse", wp)
	if _galaxy_node != null:
		_galaxy_node.scale = Vector3.ONE * (1.0 + wp * 0.02)
	if _edge_band_mat != null:
		var themed_band := _world_theme != WorldTheme.GALAXY and _world_theme != WorldTheme.NEON
		_edge_band_mat.set_shader_parameter(&"intensity",
				0.09 * (1.0 + wp * 0.15) if themed_band else 0.12 * (1.0 + wp * 0.35))


## Feuert EXAKT auf jeder Beat-Kante: Pad-Pulse, Glut-Spawn, Nebel-Tick,
## Linien-Blitz (staerker auf Takt-Anfaengen).
func _on_beat_edge(beat_idx: int, downbeat: bool) -> void:
	# BEAT-REISE/WELT-PULS: Hoehe dieses Schlags (Huellkurven in _update_world_beat).
	_edge_down = downbeat
	_edge_peak = lerpf(0.55, 1.0, _music_energy) * lerpf(1.0, SURGE_KIAI, _kiai_mix)
	# GROOVE: Hoehe des Licht-Schlags fuer diesen Beat (Decay in _update_groove).
	_groove_peak = _groove_strength(downbeat)
	_groove_is_down = downbeat
	if _kiai_sweep_pending:
		_kiai_sweep_pending = false
		_spawn_kiai_sweep()
	if _comeback_pending:
		_comeback_pending = false
		_line_flash = 1.0
		_star_burst = 1.0
	# Sub-Thump auf dem Taktanfang (hoerbar UND fuehlbar, uebertoent die Musik
	# nicht); die Huellkurve kommt aus BeatClock.
	# BOSSKAMPF: ferne Wolken-Blitze auf den Kiai-Downbeats (Komfort: schwaecher).
	if downbeat and (_world_theme == WorldTheme.BOSS or _world_theme == WorldTheme.STORM) 			and _kiai_mix > 0.5 and _fx_level() > 0.0:
		var lmax := 0.5 if _world_theme == WorldTheme.STORM else 1.0
		_theme_lightning = lmax * (0.6 if _comfort else 1.0)
	if downbeat and _use_audio and _beat_player != null:
		_beat_player.play()
	# Downbeat-Welle: ein Lichtband rollt im Noten-Tempo vom Horizont zur
	# Hit-Linie — der Takt wird als Raumwelle sichtbar.
	if downbeat and _fx_level() > 0.0:
		_spawn_beat_wave()
	# Glut-Funken (mehr bei hoher Combo/Kiai).
	var n := int((2.2 + _kiai_mix * 2.2 + float(mini(core.combo / 100, 2))) * _fx_level())
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
	_line_flash = maxf(_line_flash, 0.45)
	if downbeat:
		_line_flash = 1.0
		# Takt-Anfang: der Nebel tickt staerker.
		_nebula_kick = 1.3
	# Kiai: gelegentliche Sternschnuppe am Himmel.
	if (_kiai_mix > 0.5 and beat_idx % 8 == 4 and _fx_level() > 0.0) \
			or _hash01(float(beat_idx) * 7.77) > 0.94:
		_spawn_shooting_star(beat_idx)


## Hoehe des Takt-Schlags: Grundwert * Musikenergie (+ Notendichte),
## Downbeat staerker, Kiai x1.6, Effekt-Stufe (Dezent ~50 %).
func _groove_strength(downbeat: bool) -> float:
	var s := lerpf(0.4, 1.0, _music_energy) + _density2 * 0.3
	return s * (GROOVE_DOWN if downbeat else GROOVE_BEAT) \
			* lerpf(1.0, GROOVE_KIAI, _kiai_mix) * _fx_level()


## Takt-Schlag pro Frame: Attack exakt auf der Beat-Kante, exponentieller
## Decay aus der Beat-Phase (framerate-unabhaengig), plus Shader-Uniforms.
func _update_groove(vt: float) -> void:
	_groove_vt = vt
	var bl := 60000.0 / _clock.bpm if _clock.bpm > 1.0 else 500.0
	_groove = _groove_peak * exp(-_clock.beat_phase * bl / GROOVE_DECAY_MS)
	_groove_down = _groove if _groove_is_down else 0.0
	var flash := clampf(_groove, 0.0, 1.0)
	var down := clampf(_groove_down, 0.0, 1.0)
	var me := clampf(_music_energy * _fx_level(), 0.0, 1.0)
	var mats: Array = [_road_mat, _vignette_mat, _nebula_mat, _nebula_mat2]
	mats.append_array(_fire_mats)
	var themed := _world_theme != WorldTheme.GALAXY and _world_theme != WorldTheme.NEON
	for m in mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		# rail_fire: Puls = 1 + flash*0.5 + down*0.25. Themen-Welten: zusammen
		# hoechstens +15 % (Wandbaender ruhig).
		var dim := 0.2 if themed and _fire_mats.has(sm) else 1.0
		sm.set_shader_parameter(&"beat_flash", flash * dim)
		sm.set_shader_parameter(&"downbeat", down * dim)
		sm.set_shader_parameter(&"music_energy", me)
	_update_kiai_sweeps(vt)


## Naechste Beat-Zeit >= time_ms auf dem Raster der Map.
func _beat_ceil(time_ms: float) -> float:
	var tp = null
	for p in _beatmap.timing_points:
		if p.uninherited and p.time <= time_ms + 1.0:
			tp = p
	if tp == null or tp.beat_length <= 0.0:
		return time_ms
	var bl: float = tp.beat_length
	return tp.time + ceilf((time_ms - tp.time) / bl - 0.001) * bl


## KIAI-Eintritt: ein weicher Licht-Sweep rollt auf dem Beat von hinten nach
## vorne ueber die Strecke (flach auf der Bahn, unter den Noten) und erreicht
## die Linie genau auf einem spaeteren Schlag.
func _spawn_kiai_sweep() -> void:
	var fx := _fx_level()
	if fx <= 0.0 or _glow_shader == null or _2d:
		return
	var sw := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WAVE_W_BASE * _lane_k, 3.4)
	sw.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
	m.set_shader_parameter("base_color", _theme_col.lerp(Color(1, 1, 1), 0.35))
	m.set_shader_parameter("intensity", 0.0)
	sw.material_override = m
	sw.rotation_degrees = Vector3(-90, 0, 0)
	sw.position = Vector3(0, ROAD_Y + 0.02, Z_FAR)
	_world.add_child(sw)
	var bl := 60000.0 / _clock.bpm if _clock.bpm > 1.0 else 500.0
	var dur := maxf(1.0, roundf(800.0 / bl)) * bl
	_kiai_sweeps.append({"node": sw, "mat": m, "t0": _vt, "dur": dur,
			"peak": 0.34 * fx})


func _update_kiai_sweeps(vt: float) -> void:
	var i := _kiai_sweeps.size() - 1
	while i >= 0:
		var w: Dictionary = _kiai_sweeps[i]
		var node: MeshInstance3D = w.node
		var prog := (vt - float(w.t0)) / float(w.dur)
		if prog >= 1.0 or prog < -0.05 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_kiai_sweeps.remove_at(i)
			if prog >= 1.0:
				# Ankunft auf dem Schlag: die Linie leuchtet einmal auf.
				_line_flash = 1.0
		else:
			var pr := clampf(prog, 0.0, 1.0)
			# Leicht beschleunigend (Perspektive): hinten langsam, vorne zuegig.
			node.position.z = lerpf(Z_FAR, Z_LINE, pr * pr * 0.35 + pr * 0.65)
			var a := smoothstep(0.0, 0.12, pr) * (1.0 - smoothstep(0.8, 1.0, pr))
			(w.mat as ShaderMaterial).set_shader_parameter("intensity", float(w.peak) * a)
		i -= 1


## DROP-Warp beim Kiai-Start: Sterne springen kurz auf Warp-Tempo —
## rein im Hintergrund (kein Flash, kein FOV-Kick, keine Streifen vor der Bahn).
func _start_drop_warp() -> void:
	if _fx_level() <= 0.0:
		return
	_star_burst = 1.0
	_warp_level = _themed_warp_cap(1.0)


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
	if _2d:
		return
	var wave := MeshInstance3D.new()
	var wq := QuadMesh.new()
	wq.size = Vector2(WAVE_W_BASE * _lane_k, 1.2)
	wave.mesh = wq
	var wm := ShaderMaterial.new()
	wm.shader = _glow_shader
	# Nur Songfarbe/Weiss auf dem Spielfeld (keine Fremdfarben-Wellen):
	# Kiai/On Fire machen die Welle nur heller, nie bunter.
	var wcol := _theme_col.lerp(Color(1, 1, 1), 0.15 + _kiai_mix * 0.2 + _fire_level * 0.2)
	wm.set_shader_parameter("base_color", wcol)
	var peak := (0.09 + _kiai_mix * 0.07) * _fx_level() * (0.7 + _music_energy * 0.6)
	wm.set_shader_parameter("intensity", peak)
	wave.material_override = wm
	wave.rotation_degrees = Vector3(-90, 0, 0)
	# Die Welle ist ein "Zeitpunkt" auf der Strecke wie eine Note: sie startet
	# am fernen Ende (eine Sichtweite voraus) und laeuft mit der Map-SV zur Linie.
	# Bild-Zeit (wie BeatClock): die Welle trifft die Linie exakt auf dem Schlag.
	var t_now := _vt
	var sm := core.scroll
	var w_time := sm.time_at(sm.position(t_now) + core.preempt)
	# Auf den naechsten Beat rasten: die Welle trifft die Linie genau auf dem Schlag.
	w_time = _beat_ceil(w_time)
	wave.position = Vector3(0, ROAD_Y + 0.015, _note_z(w_time, t_now))
	_world.add_child(wave)
	_beat_waves.append({"node": wave, "mat": wm, "time": w_time, "peak": peak})


func _update_beat_waves(t: float) -> void:
	var i := _beat_waves.size() - 1
	while i >= 0:
		var w: Dictionary = _beat_waves[i]
		var node: MeshInstance3D = w.node
		var w_time: float = w.time
		if t >= w_time or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_beat_waves.remove_at(i)
		else:
			var z := _note_z(w_time, t)
			node.position.z = z
			var prog := clampf((z - Z_FAR) / (Z_LINE - Z_FAR), 0.0, 1.0)
			var peak: float = w.peak
			# Wellen erst ab dem Horizont zeigen (auf den Schlag gerastet, s. Spawn);
			# der Takt-Schlag laesst sie kurz aufleuchten.
			node.visible = z >= Z_FAR
			(w.mat as ShaderMaterial).set_shader_parameter("intensity",
					lerpf(peak, 0.02, prog) * (1.0 + _groove * 1.6))
		i -= 1


## Alle Stations-Meshes/Texturen einmalig laden — das Docking-Finale
## greift nur noch auf den Cache zu (keine Frame-Hitches).
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

const CH_FADE_BEATS := 4.0   # Ueberblendung ab dem Kapitel-Downbeat
const CH_MIN_BARS := 8        # kuerzere Abschnitte werden zusammengelegt
const FLY_D0 := 230.0         # Vorbeiflug: Startdistanz (fern, klein)
const FLY_D1 := 13.0          # Enddistanz (nah, seitlich aus dem Bild)
const FLY_D1_COMFORT := 40.0  # Komfort-Kamera: Enddistanz (ruhiger Rand)
const CAM_Z := 6.8
const CAM_Y := 1.78


## Galaxie-Kapitel aus der IntensityMap: ein neues Kapitel beginnt auf dem
## ersten Downbeat eines neuen Abschnitts (Kiai-Start, Break-Ende, alle
## 32 Takte), mindestens CH_MIN_BARS Takte lang. Farbe aus der Songpalette,
## Szenerie (Galaxie + Planet, Seite, Form) aus dem Map-Seed — jede Map ist
## eine eigene, wiedererkennbare Route. Alles hier, einmal beim Map-Start.
func _build_galaxy_chapters() -> void:
	_gal_chapters = []
	_gal_idx = -1
	_gal_col = _theme_col
	_gal_col2 = _theme_kiai
	if _beatmap == null or _beatmap.hit_objects.is_empty():
		return
	var seed_h: int = hash(GameSession.osu_filename)
	var dur := maxf(_beatmap.duration_ms(), 1.0)
	var reds: Array = []
	for tp in _beatmap.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append(tp)
	if reds.is_empty():
		return
	_bpm_factor = clampf((60000.0 / reds[0].beat_length) / 140.0, 0.7, 1.5)
	var im := IntensityMap.new()
	im.build(_beatmap)
	# Downbeats der Map ablaufen: Abschnittswechsel -> Kapitelstart.
	var starts: Array = [0.0]
	var last_sec := im.section_index(0.0)
	for ri in reds.size():
		var tp = reds[ri]
		var bar: float = tp.beat_length * float(maxi(tp.meter, 1))
		var seg_end: float = dur if ri == reds.size() - 1 else float(reds[ri + 1].time)
		var tb: float = tp.time
		while tb < seg_end - 1.0 and tb < dur - bar * 4.0:
			var sec := im.section_index(tb + 1.0)
			if sec != last_sec:
				last_sec = sec
				var prev: float = starts[starts.size() - 1]
				if tb - prev >= bar * CH_MIN_BARS:
					starts.append(tb)
				elif starts.size() > 1 and _beatmap.is_kiai(tb + 1.0) \
						and not _beatmap.is_kiai(prev + 1.0):
					# Kiai gewinnt: zu knapper Vorgaenger rutscht auf den Drop.
					starts[starts.size() - 1] = tb
			tb += bar
	# Palette: Songfarbe + Nachbarn, Kiai-Kapitel in der Kiai-Farbe.
	var h := _theme_col.h
	var kh := _theme_kiai.h
	var hues := [h, fposmod(h + 0.08, 1.0), fposmod(h - 0.08, 1.0),
			fposmod(h + 0.16, 1.0)]
	var side := -1.0 if (seed_h % 2) == 0 else 1.0
	var calm_i := 0
	var pal_base := _sky_pal_for_hue(_theme_col.h, -1)
	var pal_alt := _sky_pal_for_hue(_theme_col.h, pal_base)
	var pal_kiai := _sky_pal_for_hue(_theme_kiai.h, pal_base)
	# Folge-Kapitel sollen sich klar unterscheiden: ruhige Kapitel rotieren
	# durch alle drei Nicht-Kiai-Paletten, Kiai-Ketten wechseln zu zweit.
	var calm_pals: Array = [pal_base, pal_alt]
	for pi3 in SKY_PALS.size():
		if pi3 != pal_base and pi3 != pal_alt and pi3 != pal_kiai:
			calm_pals.append(pi3)
			break
	var kiai_pals: Array = [pal_kiai, pal_alt if pal_alt != pal_kiai else pal_base]
	var kiai_i := 0
	for i in starts.size():
		var t0: float = starts[i]
		var t1: float = dur if i == starts.size() - 1 else float(starts[i + 1])
		var kiai := _beatmap.is_kiai(t0 + 1.0) or _beatmap.is_kiai(t0 + (t1 - t0) * 0.5)
		var drop := im.is_drop_at(t0 + 1.0)
		var hs := float(seed_h % 977) + float(i) * 3.3
		var hh: float = fposmod(kh + 0.09 * float(kiai_i % 2), 1.0) if kiai else float(hues[(calm_i + seed_h) % hues.size()])
		var pal: int = kiai_pals[kiai_i % 2] if kiai else calm_pals[calm_i % calm_pals.size()]
		if kiai:
			kiai_i += 1
		if not kiai:
			calm_i += 1
		var big := kiai or drop
		_gal_chapters.append({
			"t": t0, "t_end": t1, "kiai": kiai, "drop": drop,
			"col": Color.from_hsv(hh, 0.55 + 0.2 * _hash01(hs), 0.95),
			"col2": Color.from_hsv(h if kiai else kh, 0.75, 1.0),
			"stars": (1.25 if kiai else 0.55) + _hash01(hs * 1.7) * 0.5,
			"scale": 0.85 + _hash01(float(seed_h) * 2.0 + float(i)) * 0.9,
			"side": side,
			"arms": 2.0 + float(int(_hash01(hs * 2.3) * 2.99)),
			"twist": 4.0 + _hash01(hs * 3.1) * 3.5,
			"squash": 1.2 + _hash01(hs * 4.7) * 0.9,
			"tilt": (_hash01(hs * 5.3) - 0.5) * 0.9,
			"gsize": (26.0 if big else 19.0) + _hash01(hs * 6.1) * 6.0,
			"gh": 0.10 + _hash01(hs * 7.9) * 0.10,
			"psize": 5.0 + _hash01(hs * 8.3) * 5.0,
			"ph": 0.05 + _hash01(hs * 9.7) * 0.08,
			"pcol": Color.from_hsv(fposmod(hh + 0.5 + _hash01(hs * 10.1) * 0.2, 1.0), 0.45, 0.75),
			"pseed": _hash01(hs * 11.3) * 40.0,
			"pring": 0.85 if _hash01(hs * 12.7) > 0.5 else 0.0,
			"pal": pal,
		})
		side = -side
	if OS.get_cmdline_args().has("--shot"):
		for c in _gal_chapters:
			print("CHAPTER t=%.0f..%.0f kiai=%s drop=%s" % [float(c.t), float(c.t_end), str(c.kiai), str(c.drop)])
	_build_flyby()


## Zwei Vorbeiflug-Slots (aktuelles + voriges Kapitel): Galaxie + Planet,
## Materialien einmalig — pro Kapitel werden nur Uniforms umgestellt.
func _build_flyby() -> void:
	_flyby = []
	if _cosmos == null:
		return
	var gal_shader: Shader = load("res://shaders/spiral_galaxy.gdshader")
	var pl_shader: Shader = load("res://shaders/planet.gdshader")
	for k in 2:
		var g := MeshInstance3D.new()
		var gq := QuadMesh.new()
		gq.size = Vector2(1, 1)
		g.mesh = gq
		var gm := ShaderMaterial.new()
		gm.shader = gal_shader
		gm.render_priority = 1
		gm.set_shader_parameter("intensity", 0.0)
		g.material_override = gm
		g.visible = false
		_cosmos.add_child(g)
		var pl := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(1, 1)
		pl.mesh = pq
		var pm := ShaderMaterial.new()
		pm.shader = pl_shader
		pm.render_priority = 1
		pm.set_shader_parameter("fade", 0.0)
		pl.material_override = pm
		pl.visible = false
		_cosmos.add_child(pl)
		_flyby.append({"g": g, "gm": gm, "p": pl, "pm": pm, "ch": -1})


## Kapitel ci in seinen Slot laden (nur beim Kapitelwechsel).
func _setup_flyby(ci: int) -> void:
	if _flyby.is_empty() or ci < 0:
		return
	var fb: Dictionary = _flyby[ci % _flyby.size()]
	var c: Dictionary = _gal_chapters[ci]
	fb["ch"] = ci
	var gm: ShaderMaterial = fb.gm
	var col: Color = c.col
	gm.set_shader_parameter("col_arm", col.lerp(Color(0.8, 0.85, 1.0), 0.25))
	gm.set_shader_parameter("col_core", Color(1.0, 0.93, 0.80).lerp(col, 0.15))
	gm.set_shader_parameter("arm_n", float(c.arms))
	gm.set_shader_parameter("twist", float(c.twist))
	gm.set_shader_parameter("squash", float(c.squash))
	var gs: float = c.gsize
	(fb.g as MeshInstance3D).scale = Vector3(gs, gs * 0.72, 1.0)
	(fb.g as MeshInstance3D).rotation = Vector3(0, 0, float(c.tilt))
	var pm: ShaderMaterial = fb.pm
	var pc: Color = c.pcol
	pm.set_shader_parameter("base_col", pc)
	pm.set_shader_parameter("band_col", pc.darkened(0.35))
	pm.set_shader_parameter("atmo_col", col.lerp(Color(1, 1, 1), 0.3))
	pm.set_shader_parameter("band_freq", 5.0 + float(c.pseed) * 0.2)
	pm.set_shader_parameter("seed", float(c.pseed))
	pm.set_shader_parameter("ring_amount", float(c.pring))
	(fb.p as MeshInstance3D).scale = Vector3.ONE * float(c.psize)


## Kapitel pro Frame (Bild-Zeit vt): Wechsel erkennen, Farben/Sterne exakt
## ab dem Downbeat ueberblenden, Vorbeiflug-Szenerie bewegen. Keine Allokation
## ausser beim Kapitelwechsel selbst.
func _update_chapters(vt: float, fx: float) -> void:
	if _gal_chapters.is_empty():
		return
	var target := 0
	for ci in _gal_chapters.size():
		if vt >= float(_gal_chapters[ci].t):
			target = ci
		else:
			break
	if target != _gal_idx:
		var first := _gal_idx < 0
		if not first and fx > 0.0:
			# Nur Sternen-Warp im Hintergrund — kein Tunnel, kein FOV-Wabern.
			_warp_level = _themed_warp_cap(1.0)
		_gal_from = {"col": _gal_col, "col2": _gal_col2, "stars": _gal_stars,
				"scale": _gal_scale}
		_ch_kiai_from = _ch_kiai_w
		_gal_idx = target
		_apply_landmark(_gal_idx)
		_setup_flyby(_gal_idx)
		_sky_begin_chapter(int(_gal_chapters[_gal_idx].pal), first)
		if first:
			var c0: Dictionary = _gal_chapters[_gal_idx]
			_gal_from = {"col": c0.col, "col2": c0.col2, "stars": c0.stars,
					"scale": c0.scale}
			_ch_kiai_from = 1.0 if c0.kiai else 0.0
	var ch: Dictionary = _gal_chapters[_gal_idx]
	var bl := 60000.0 / _clock.bpm if _clock.bpm > 1.0 else 500.0
	var fade_ms := CH_FADE_BEATS * bl
	var w := smoothstep(0.0, fade_ms, vt - float(ch.t))
	if _sky_mat != null:
		if _sky_b >= 0 and w >= 1.0:
			_sky_set(true, _sky_b)
			_sky_b = -1
		_sky_mat.set_shader_parameter(&"palette_mix", w if _sky_b >= 0 else 0.0)
		# Themen: Kiai = eine Stufe intensiver (heller, kraeftigerer Puls).
		var themed := _world_theme != WorldTheme.GALAXY
		_sky_mat.set_shader_parameter(&"brightness",
				lerpf(0.95, 1.15 if themed else 1.2, _ch_kiai_w))
		if themed:
			_sky_mat.set_shader_parameter(&"kiai", _ch_kiai_w)
	_ch_w = w
	_gal_col = (_gal_from.col as Color).lerp(ch.col, w)
	_gal_col2 = (_gal_from.col2 as Color).lerp(ch.col2, w)
	_gal_stars = lerpf(float(_gal_from.stars), float(ch.stars), w)
	_gal_scale = lerpf(float(_gal_from.scale), float(ch.scale), w)
	_ch_kiai_w = lerpf(_ch_kiai_from, 1.0 if ch.kiai else 0.0, w)
	var fxc := clampf(fx, 0.0, 1.0)
	# Kiai-Kapitel: dichterer Sternenstrom, volle Aurora.
	if _star_mm != null:
		_star_mm.visible_instance_count = int(float(STAR_COUNT) * lerpf(0.7, 1.0, _ch_kiai_w * fxc))
	if _aurora_mat != null:
		_aurora_mat.set_shader_parameter("amount", lerpf(0.3, 1.0, _ch_kiai_w) * maxf(fxc, 0.3))
	# VORBEIFLUG: waechst aus der Ferne heran und zieht weit seitlich oben
	# vorbei (projizierter Abstand zur Bildmitte >= ~0.35, nie ueber der Bahn).
	for fb in _flyby:
		var g: MeshInstance3D = fb.g
		var pl: MeshInstance3D = fb.p
		var ci: int = fb.ch
		if ci < 0 or fx <= 0.0:
			g.visible = false
			pl.visible = false
			continue
		var c: Dictionary = _gal_chapters[ci]
		var t0: float = c.t
		var span := maxf(float(c.t_end) - t0 + fade_ms, 1.0)
		var p := (vt - t0) / span
		if p < 0.0 or p > 1.0:
			g.visible = false
			pl.visible = false
			continue
		var fin := smoothstep(0.0, fade_ms, vt - t0)
		var side: float = c.side
		var kb := 1.0 if c.kiai else 0.0
		# Galaxie: exponentielle Annaeherung = gleichmaessiges Tempo-Gefuehl.
		# Komfort: Vorbeiflug endet weiter weg -> langsamer im Augenwinkel.
		var d1 := FLY_D1_COMFORT if _comfort else FLY_D1
		var d := FLY_D0 * pow(d1 / FLY_D0, p)
		var r := lerpf(0.40, 1.75, p * p)
		var gs: float = c.gsize
		g.position = Vector3(side * r * d, _cam_pos.y + d * float(c.gh) + gs * 0.3, _cam_pos.z - d)
		g.visible = true
		var gm: ShaderMaterial = fb.gm
		gm.set_shader_parameter("t", vt / 1000.0)
		gm.set_shader_parameter("world_pulse", _world_pulse)
		gm.set_shader_parameter("intensity",
				(0.42 + kb * 0.38) * fin * (1.0 - smoothstep(0.88, 1.0, p)) * fxc)
		# Planet: gegenueberliegende Seite, etwas spaeter dran.
		var pp := clampf(p * 1.12 - 0.08, 0.0, 1.0)
		var d2 := FLY_D0 * 0.85 * pow(d1 / (FLY_D0 * 0.85), pp)
		var r2 := lerpf(0.48, 1.9, pp * pp)
		var ps: float = c.psize
		pl.position = Vector3(-side * r2 * d2, _cam_pos.y + d2 * float(c.ph) + ps * 0.6, _cam_pos.z - d2)
		pl.visible = p * 1.12 - 0.08 > 0.0
		var pm: ShaderMaterial = fb.pm
		pm.set_shader_parameter("t", vt / 1000.0)
		pm.set_shader_parameter("world_pulse", _world_pulse)
		pm.set_shader_parameter("fade", fin * (1.0 - smoothstep(0.9, 1.0, pp)) * fxc)


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
	var objs := _beatmap.hit_objects
	# Breaks (>4.5s ohne Noten): Hochziehen + Kometensturm.
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


func _play_hit(pitch: float) -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_hit_player.volume_db = linear_to_db(Settings.hitsound_volume) + HIT_DB
	_hit_player.pitch_scale = pitch
	_hit_player.play()


func _play_miss() -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_miss_player.volume_db = linear_to_db(Settings.hitsound_volume) + MISS_DB
	_miss_player.play()


func _build_sound() -> void:
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = HIT_DB
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	_miss_player.volume_db = MISS_DB
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
	# 2D: kein Vollbild-Shader (3D-Effekt, kostet nur GPU).
	if not _2d:
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
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("shadow_outline_size", 6)
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
	_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_time_label.add_theme_constant_override("shadow_offset_y", 2)
	_time_label.add_theme_constant_override("shadow_outline_size", 6)
	_time_label.add_theme_font_override("font", _tabular_font(_time_label))
	_hud.add_child(_time_label)

	# Song-Fortschritt: Haarlinie ganz oben ueber die volle Breite.
	var top_bg := ColorRect.new()
	top_bg.anchor_right = 1.0
	top_bg.offset_bottom = 4
	top_bg.color = Color(1, 1, 1, 0.08)
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top_bg)
	_top_fill = ColorRect.new()
	_top_fill.anchor_right = 0.0
	_top_fill.offset_bottom = 4
	_top_fill.color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.75)
	_top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_fill)

	# Rang links bei der Genauigkeit, rechts eine kompakte Zaehler-Gruppe.
	var left := _stat_column(Vector2(0.085, 0.42))
	_grade_label = _stat_block(left, "RANG", 26)
	_acc_label = _stat_block(left, "GENAUIGKEIT", 28)
	var right := _stat_column(Vector2(0.915, 0.42))
	_score_label = _stat_block(right, "PUNKTE", 30)
	_miss_label = _stat_block(right, "FEHLER", 24)
	_notes_label = _stat_block(right, "NOTEN", 24)

	# HP: HpBar mittig oben (Song-Fortschritt ist die Akzent-Linie ganz oben).
	_hp_bar = HpBar.new()
	_hp_bar.label_text = "HP"
	_hud.add_child(_hp_bar)
	_hp_bar.setup(_theme_col)
	_hp_bar.anchor_left = 0.5
	_hp_bar.anchor_right = 0.5
	_hp_bar.offset_left = -160
	_hp_bar.offset_right = 160
	_hp_bar.offset_top = 6
	_hp_bar.offset_bottom = 30

	# Timing-Leiste mittig unter der Abfanglinie, Fenster = echte core.w*-Werte.
	_err_bar = HitErrorBar.new()
	_hud.add_child(_err_bar)
	_err_bar.setup({"max": core.w_max, "w300": core.w300, "w200": core.w200,
		"w100": core.w100, "w50": core.w50}, 300.0)

	# Judge (MAX/300/…, FRUEH/SPAET) + Kombo knapp ueber der Abfanglinie.
	_judge_disp = JudgeDisplay.new()
	_hud.add_child(_judge_disp)
	_judge_disp.setup(_theme_col)
	_judge_disp.window_300_ms = core.w300

	# Intro/Breaks: Ring, Countdown, 3-2-1 auf dem Beat, Skip-Hinweis.
	_break_ov = BreakOverlay.new()
	_hud.add_child(_break_ov)
	_build_breaks()
	_place_hud_to_line()
	get_viewport().size_changed.connect(_place_hud_to_line)

	# MULTIPLAYER: Live-Scoreboard links (wie osu!mania) — sortiert nach
	# Score, eigener Eintrag hervorgehoben; Ueberholen sieht man sofort.
	if Lobby.active and Lobby.in_game:
		_mp_board = Control.new()
		_mp_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mp_board.offset_left = 18
		_mp_board.offset_top = 56
		_hud.add_child(_mp_board)
		Lobby.scores_changed.connect(_refresh_mp_board)
		Lobby.skip_now.connect(_do_skip)
		_mp_rounds_at_start = Lobby.mm.rounds_played
		_mp_round_no_at_start = Lobby.mm.round_no
		# Teams: Summe Rot gegen Blau live oben in der Mitte.
		if Lobby.mm.kind == MatchMode.Kind.TEAMS:
			_mp_team_bar = LiveTeamBar.new()
			_mp_team_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_mp_team_bar.custom_minimum_size = Vector2(560, 46)
			_hud.add_child(_mp_team_bar)
			_mp_team_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			_mp_team_bar.offset_top = 10
			_mp_team_bar.setup({ "names": Lobby.mm.team_names,
				"totals": Lobby.mm.team_totals(Lobby.live_results()) })
		_refresh_mp_board()



## Judge/Kombo und Timing-Leiste an der projizierten Abfanglinie ausrichten.
func _place_hud_to_line() -> void:
	if _camera == null or _judge_disp == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var line_y := _pf2d.line_y() if _pf2d != null 			else _camera.unproject_position(Vector3(0.0, ROAD_Y, Z_LINE)).y
	if line_y <= 0.0 or line_y >= vs.y:
		line_y = vs.y * 0.84
	# Judge + FRUEH/SPAET ueber den Pads (Pad-Oberkante ~8,5 % Bildhoehe ueber der Linie).
	_judge_disp.judge_gap = vs.y * 0.085 + 44.0
	_judge_disp.place(line_y)
	if _pf2d != null:
		# 2D: UR-Leiste IM Spielfeld unten (nie breiter als das Feld), nicht
		# quer ueber Bildschirm/Tastenbeschriftung.
		var fr := _pf2d.field_rect()
		var w := clampf(fr.size.x - 16.0, 120.0, 300.0)
		if not is_equal_approx(_err_bar.size.x, w):
			_err_bar.custom_minimum_size = Vector2(w, _err_bar.custom_minimum_size.y)
			_err_bar.size = _err_bar.custom_minimum_size
		_err_bar.position = Vector2(fr.position.x + (fr.size.x - w) * 0.5,
			vs.y - _err_bar.size.y - 4.0)
		return
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5,
		minf(line_y + 34.0, vs.y - _err_bar.size.y - 8.0))


## Intro (lange Vorlaeufe) und Pausen ohne Noten fuer das BreakOverlay.
func _build_breaks() -> void:
	_breaks.clear()
	_break_cur = -1
	if _beatmap == null or _beatmap.hit_objects.is_empty():
		return
	var objs := _beatmap.hit_objects
	if objs[0].time > 3000.0:
		_breaks.append(Vector2(0.0, objs[0].time))
	var last_end: float = objs[0].end_time()
	for i in range(1, objs.size()):
		if objs[i].time - last_end > 4500.0:
			_breaks.append(Vector2(last_end + 500.0, objs[i].time))
		last_end = maxf(last_end, objs[i].end_time())


## Pro Frame: passenden Break suchen, Overlay zeigen/aktualisieren.
func _update_break_overlay(t: float) -> void:
	if _break_ov == null:
		return
	var idx := -1
	for i in _breaks.size():
		if t >= _breaks[i].x and t < _breaks[i].y + BreakOverlay.FADE_OUT_MS:
			idx = i
			break
	if idx < 0:
		if _break_cur >= 0:
			_break_ov.hide_break()
			_break_cur = -1
		return
	var can_skip: bool = _breaks[idx].x <= 0.0 and _can_skip_intro() 		and Settings.lane_for_key(KEY_SPACE) == -1 and not _ended
	if idx != _break_cur or can_skip != _break_skip:
		var beat_ms := 60000.0 / _clock.bpm if _clock.bpm > 1.0 else 500.0
		_break_ov.show_break(_breaks[idx].x, _breaks[idx].y, beat_ms, can_skip)
		_break_cur = idx
		_break_skip = can_skip
	_break_ov.update(t)


## HUD-Spalte: vertikal um anchor_pos zentriert, Bloecke mit festem Abstand.
func _stat_column(anchor_pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_left = anchor_pos.x
	v.anchor_right = anchor_pos.x
	v.anchor_top = anchor_pos.y
	v.anchor_bottom = anchor_pos.y
	v.offset_left = -120
	v.offset_right = 120
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 22)
	_hud.add_child(v)
	return v


## Label (13 px, gedimmt) direkt ueber dem Wert (~8 px Luft), Wert mit
## tabellarischen Ziffern, damit Zahlen beim Hochzaehlen nicht springen.
func _stat_block(column: VBoxContainer, caption: String, size: int) -> Label:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", -2)
	column.add_child(block)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(0.58, 0.61, 0.70))
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cap.add_theme_constant_override("shadow_outline_size", 5)
	block.add_child(cap)
	var val := Label.new()
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", size)
	val.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	val.add_theme_constant_override("shadow_outline_size", 6)
	val.add_theme_font_override("font", _tabular_font(val))
	block.add_child(val)
	return val


## Gleiche Schrift wie das Theme, aber mit OpenType "tnum" (feste Ziffernbreite).
func _tabular_font(ref: Control) -> Font:
	var fv := FontVariation.new()
	fv.base_font = ref.get_theme_default_font() if ref.get_theme_default_font() != null else ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	fv.opentype_features = { ts.name_to_tag("tnum"): 1 }
	return fv


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
	if _judge_disp == null:
		return
	# osu!-Skin mit Judgement-Bildern: Playfield2D zeigt Judgement + Kombo wie osu!.
	_judge_disp.visible = not (_pf2d != null and _pf2d.draws_judgements())
	_judge_disp.set_combo(core.combo)
	var judged_n := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	var g := core.grade()
	if judged_n == 0:
		# Vor der ersten gewerteten Note: kein "D" und keine 0.0%.
		_grade_label.text = "-"
		_grade_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		_acc_label.text = "100,00 %"
	else:
		_grade_label.text = g
		_grade_label.add_theme_color_override("font_color", GRADE_COLOR.get(g, Color.WHITE))
		_acc_label.text = UiTheme.fmt_pct(core.accuracy() * 100.0)
	# Farbecho des On-Fire-Zustands: Gold ab 97%, Eisblau ab 99.5%.
	var hud_j := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	var hud_acc := core.accuracy()
	if hud_j >= 30 and hud_acc >= 0.995:
		_acc_label.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
	elif hud_j >= 30 and hud_acc >= 0.97:
		_acc_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	else:
		_acc_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_score_label.text = PauseMenu.fmt_int(core.score)
	_miss_label.text = str(core.n_miss)
	var judged := core.n_max + core.n300 + core.n200 + core.n100 + core.n50 + core.n_miss
	_notes_label.text = "%s / %s" % [PauseMenu.fmt_int(judged), PauseMenu.fmt_int(_beatmap.hit_objects.size())]
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.anchor_right = clampf(t / _song_len_ms, 0.0, 1.0)
	_hp_bar.set_hp(core.hp)


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


func _toggle_pause(paused: bool) -> void:
	if paused:
		if _pause_menu == null:
			_pause_menu = PauseMenu.new()
			_hud.add_child(_pause_menu)
			_pause_menu.resume_pressed.connect(func(): _toggle_pause(false))
			_pause_menu.restart_pressed.connect(_restart)
			_pause_menu.quit_pressed.connect(_back_to_browser)
			_pause_menu.view_2d_changed.connect(_apply_2d_view)
		_pause_menu.open({
			"is_2d": _2d,
			"title": "%s — %s" % [_beatmap.artist(), _beatmap.title()],
			"progress": clampf(_time_ms() / maxf(_song_len_ms, 1.0), 0.0, 1.0),
			"score": core.score,
			"acc": core.accuracy() * 100.0,
			"difficulty": _beatmap.version_name(),
			"length_ms": _song_len_ms,
		})
		get_tree().paused = true
		SyncClock.pause()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_menu != null and _pause_menu.visible:
			_pause_menu.close()
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
			_pad_mats[c].set_shader_parameter("rim_color", _pad_color(c) * 1.25)
		if not await _countdown_wait(step * 0.5):
			return
		for c in hint:
			_pad_mats[c].set_shader_parameter("rim_color", _pad_color(c) * PAD_IDLE)
		if not await _countdown_wait(step * 0.5):
			return
	lbl.queue_free()
	_countdown_running = false
	if _autoplay:
		print("COUNTDOWN fertig")
	get_tree().paused = false
	SyncClock.resume()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


## Wartet sec Sekunden, auch bei pausiertem Tree, Fenster ohne Fokus und
## --write-movie: zaehlt pro SceneTree.process_frame (feuert immer) die
## Frame-Zeit hoch, Echtzeit (Time.get_ticks_msec) als Sicherung — der
## Countdown kann nie haengen bleiben. false = Szene verlassen.
func _countdown_wait(sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	var acc := 0.0
	var tree := get_tree()
	var last := t0
	while acc < sec and float(Time.get_ticks_msec() - t0) < sec * 2000.0:
		await tree.process_frame
		if not is_inside_tree():
			return false
		var now := Time.get_ticks_msec()
		var d := get_process_delta_time()
		if d <= 0.0:
			d = float(now - last) / 1000.0
		last = now
		acc += clampf(d, 0.0, 0.1)
	return is_inside_tree()


func _restart() -> void:
	get_tree().paused = false
	SyncClock.stop()
	get_tree().reload_current_scene()


func _back_to_browser() -> void:
	if _mp_demo and _mp_demo_shots < 4:
		return
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
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace,
			_hold_ok, _hold_drop, is_fail))
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
	if GameSession.is_replay or GameSession.tutorial or _autoplay:
		# Replay-Ansicht/Tutorial/Autoplay: NICHTS werten oder speichern.
		pp = -1.0
	else:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s)
		ReplayStore.save(GameSession.osz_path, _beatmap.version_name(), _recorded, {
			"score": int(s.score), "grade": str(s.grade),
			"accuracy": float(s.accuracy), "date": Time.get_datetime_string_from_system(),
			"mods": GameSession.mods.duplicate(),  # Replay laeuft mit denselben Mods
		})
	_build_results(is_fail, s, pp, unranked, new_best)


## Results-Screen: eigenstaendige Komponente ResultsScreen (scripts/ui/
## results_screen.gd). Hier nur Daten befuellen und Signale verdrahten.
func _build_results(is_fail: bool, s: Dictionary, pp: float, unranked: bool, new_best: bool) -> void:
	var rs := ResultsScreen.new()
	_hud.add_child(rs)
	_results_screen = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	rs.clip_pressed.connect(_on_results_clip)
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	var data := {
		"is_fail": is_fail,
		"s": s,
		"pp": pp,
		"unranked": unranked,
		"new_best": new_best,
		"title": _beatmap.title(),
		"artist": _beatmap.artist(),
		"version": _beatmap.version_name(),
		# Das Cover liegt im .osz (kein Dateipfad) -> direkt als Textur.
		"cover_path": "",
		"offsets": _hit_offsets,
		"player": Settings.profile_name,
		"date": Time.get_datetime_string_from_system(),
		"allow_retry": not Lobby.active,
		"can_replay": GameSession.is_replay or _recorded.size() > 0,
		"is_replay": GameSession.is_replay,
		"lobby": Lobby.active,
	}
	if Lobby.active:
		var me := multiplayer.get_unique_id()
		data["my_id"] = me
		if Lobby.players.has(me):
			data["final"] = Lobby.players[me].get("final", {})
	if cover != null:
		data["cover"] = cover
	rs.show_results(data)
	# Rank-Reveal-Sound synchron zum Zoom-Pop der Komponente (~0.35 s).
	var grade := "F" if is_fail else str(s.get("grade", "D"))
	get_tree().create_timer(0.38, true).timeout.connect(func():
		if is_inside_tree() and _use_audio:
			Sfx.rank_reveal(grade))

	# MULTIPLAYER-Endscreen: Rangliste + Stats-Karten im ResultsScreen
	# (traeufeln live ein, wenn andere fertig werden).
	if Lobby.active:
		Lobby.scores_changed.connect(_refresh_mp_ranking)
		Lobby.players_changed.connect(_refresh_mp_ranking)
		_refresh_mp_ranking()


## Replay-Button: im Replay "Selbst spielen", sonst den eben gespielten Lauf
## als Replay ansehen.
func _on_results_replay() -> void:
	if GameSession.is_replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
	elif _recorded.size() > 0:
		GameSession.is_replay = true
		GameSession.replay_events = _recorded.duplicate()
	else:
		return
	_restart()


## Clip-Button: gespeichertes Replay dieser Diff als Video exportieren
## (zweiter Prozess, siehe ClipExporter) — Fortschritt als Toast.
func _on_results_clip() -> void:
	var version := _beatmap.version_name()
	if not ReplayStore.exists(GameSession.osz_path, version):
		_results_toast(tr("Kein gespeichertes Replay für diese Map"), false)
		return
	if _clip_exporter != null and _clip_exporter.is_running():
		_results_toast(tr("Clip wird bereits aufgenommen …"), true)
		return
	if _clip_exporter == null:
		_clip_exporter = ClipExporter.new()
		# An die Wurzel haengen: das MP4-Umkodieren laeuft weiter, auch wenn man
		# die Results verlaesst.
		get_tree().root.add_child(_clip_exporter)
		_clip_exporter.progress_info.connect(func(fraction: float, eta_s: float, phase: String):
			if _results_screen != null and is_instance_valid(_results_screen) 					and _results_screen.has_method("show_clip_progress"):
				_results_screen.show_clip_progress(fraction, eta_s, phase))
		_clip_exporter.finished.connect(func(ok: bool, path: String):
			# Fortschritts-Toast weg, Ergebnis kommt als Results-Toast mit
			# "Ordner öffnen"-Button (bzw. dem Fehlergrund).
			if _clip_toast != null and is_instance_valid(_clip_toast):
				_clip_toast.queue_free()
				_clip_toast = null
			if _results_screen != null and is_instance_valid(_results_screen) \
					and _results_screen.has_method("show_clip_result"):
				_results_screen.show_clip_result(ok, path, "" if ok else str(_clip_exporter.last_error))
			elif ok:
				_results_toast(tr("Clip gespeichert: %s") % path, false)
			else:
				_results_toast(tr("Clip-Export fehlgeschlagen"), false))
	var md5 := ("%s|%s" % [GameSession.osz_path.get_file(), version]).md5_text()
	var out := ClipExporter.clips_dir().path_join("clip_%s.avi" % md5)
	if _clip_exporter.export_clip(md5, out):
		_results_toast(tr("Clip wird aufgenommen …"), true)


## Kleiner Glas-Toast unten mittig auf dem Results-Screen. sticky = bleibt
## stehen (Fortschritt), sonst nach 4 s weich ausblenden.
func _results_toast(text: String, sticky: bool) -> void:
	if _results_screen == null or not is_instance_valid(_results_screen):
		return
	if _clip_toast == null or not is_instance_valid(_clip_toast):
		_clip_toast = PanelContainer.new()
		_clip_toast.anchor_left = 0.5
		_clip_toast.anchor_right = 0.5
		_clip_toast.anchor_top = 1.0
		_clip_toast.anchor_bottom = 1.0
		_clip_toast.offset_left = -320
		_clip_toast.offset_right = 320
		_clip_toast.offset_top = -138
		_clip_toast.offset_bottom = -94
		_clip_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiTheme.glass_box(12, 0.85)
		sb.set_content_margin_all(10)
		_clip_toast.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.name = "Text"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		_clip_toast.add_child(lbl)
		_results_screen.add_child(_clip_toast)
	(_clip_toast.get_node("Text") as Label).text = text
	_clip_toast.modulate.a = 1.0
	if _clip_toast_tw != null and _clip_toast_tw.is_valid():
		_clip_toast_tw.kill()
	if not sticky:
		_clip_toast_tw = create_tween()
		_clip_toast_tw.tween_interval(4.0)
		_clip_toast_tw.tween_property(_clip_toast, "modulate:a", 0.0, 0.5)


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
		k.append(_short_key_name(code))
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
	_tut_steps.append({ "t": objs[0].time - 3000.0, "title": tr("DEINE TASTEN"),
		"body": tr("%s  %s  %s  %s — eine Taste pro Spur (Pfeil: die Ringe).\nDrücke GENAU, wenn eine Drohne ihren Ring berührt.") % [k[0], k[1], k[2], k[3]],
		"worlds": [Vector3(0.0, ROAD_Y + 0.3, Z_LINE)] })
	if first_note >= 0.0:
		_tut_steps.append({ "t": first_note - 1600.0, "title": tr("ERSTE NOTE"),
			"body": tr("Gleich kommt eine Drohne auf DIESEN Ring zu.\nDrücke [%s] genau beim Berühren.\nDeine Wertung (MAX … 50) erscheint danach in der Bildmitte.") % k[note_col],
			"worlds": [Vector3(RAIL_X[note_col], ROAD_Y + 0.3, Z_LINE)] })
	if first_hold >= 0.0:
		_tut_steps.append({ "t": first_hold - 1600.0, "title": tr("HOLD-NOTE"),
			"body": tr("Die Drohne mit dem langen Beam: [%s] drücken und HALTEN,\nbis der Beam vorbei ist. Zu früh loslassen = Combo weg!") % k[hold_col],
			"worlds": [Vector3(RAIL_X[hold_col], ROAD_Y + 0.3, Z_LINE)] })
	if first_chord >= 0.0:
		_tut_steps.append({ "t": first_chord - 1600.0, "title": tr("DOPPELNOTE"),
			"body": tr("Zwei Drohnen gleichzeitig — beide Pfeile!\n[%s] + [%s] EXAKT ZUSAMMEN drücken.") % [k[chord_a], k[chord_b]],
			"worlds": [Vector3(RAIL_X[chord_a], ROAD_Y + 0.3, Z_LINE),
				Vector3(RAIL_X[chord_b], ROAD_Y + 0.3, Z_LINE)] })
	var span := objs[objs.size() - 1].time - objs[0].time
	_tut_steps.append({ "t": objs[0].time + span * 0.45, "title": tr("DEIN HUD"),
		"body": tr("Der Pfeil zeigt auf die Timing-Leiste: Strich links = zu früh,\nrechts = zu spät. Darüber: Combo + Wertung.\nLinks: Accuracy · Rechts: Score · Oben: HP.\nJetzt spiel die Map zu Ende — viel Spaß!"),
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

const MP_ROW_H := 46.0


func _mp_demo_send() -> void:
	var phase := 0.0 if Lobby.is_host else 2.4
	var t := _mp_demo_t
	var sc := int(t * 9000.0 + 22000.0 * sin(t * 0.45 + phase))
	Lobby.send_score(maxi(sc, 0), int(t * 3.0) % 120, 0.97 - 0.02 * sin(t + phase))


func _mp_demo_shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var out := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--mp-out="):
			out = a.substr(9)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [out, tag])
	print("MPAUTO shot %s" % tag)


func _mp_demo_step(delta: float) -> void:
	_mp_demo_t += delta
	if int(_mp_demo_t * 2.0) != int((_mp_demo_t - delta) * 2.0) and int(_mp_demo_t) % 2 == 0:
		print("MPAUTO tick %.1f paused=%s" % [_mp_demo_t, str(get_tree().paused)])
	if _mp_demo_shots == 0 and _mp_demo_t > 5.0:
		_mp_demo_shots = 1
		_mp_demo_shot("live1")
	elif _mp_demo_shots == 1 and _mp_demo_t > 9.0:
		_mp_demo_shots = 2
		_mp_demo_shot("live2")
	elif _mp_demo_shots == 2 and _mp_demo_t > 11.0:
		_mp_demo_shots = 3
		_show_results(false)
	elif _mp_demo_shots == 3 and _mp_demo_t > 14.0:
		_mp_demo_shots = 4
		_mp_demo_shot("results")
	elif _mp_demo_shots == 4 and _mp_demo_t > 15.0:
		_mp_demo_shots = 5
		_back_to_browser()

func _refresh_mp_board() -> void:
	if _mp_board == null or not is_instance_valid(_mp_board):
		return
	var ranked := Lobby.ranked_players()
	var my_id := multiplayer.get_unique_id()
	if _mp_team_bar != null and is_instance_valid(_mp_team_bar):
		_mp_team_bar.set_totals(Lobby.mm.team_totals(Lobby.live_results()))
	# Royale: wer gerade Letzter ist, wird ruhig markiert (kein Blinken).
	_mp_danger = Lobby.mm.in_danger(Lobby.live_results()) 			if Lobby.mm.kind == MatchMode.Kind.ROYALE else -1
	var alive := {}
	for i in ranked.size():
		var p: Dictionary = ranked[i]
		var id := int(p.id)
		alive[id] = true
		var row: Control = _mp_rows.get(id)
		if row == null or not is_instance_valid(row):
			row = _mp_make_row(id == my_id)
			_mp_board.add_child(row)
			row.position = Vector2(0, i * MP_ROW_H)
			_mp_rows[id] = row
		_mp_fill_row(row, i, p, ranked, id == my_id)
		# Plaetze tauschen: weich zur neuen Zeile gleiten.
		var ty := i * MP_ROW_H
		if absf(float(row.get_meta("ty", -1.0)) - ty) > 0.5:
			row.set_meta("ty", ty)
			var old: Tween = row.get_meta("tw") if row.has_meta("tw") else null
			if old != null and old.is_valid():
				old.kill()
			var tw := row.create_tween()
			tw.tween_property(row, "position:y", ty, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			row.set_meta("tw", tw)
	for id in _mp_rows.keys():
		if not alive.has(id):
			var gone: Control = _mp_rows[id]
			_mp_rows.erase(id)
			if is_instance_valid(gone):
				gone.queue_free()
	_mp_board.custom_minimum_size = Vector2(264, ranked.size() * MP_ROW_H)
	_mp_last_rank = -1
	for i in ranked.size():
		if int(ranked[i].id) == my_id:
			_mp_last_rank = i


func _mp_make_row(mine: bool) -> Control:
	var row := PanelContainer.new()
	row.size = Vector2(264, MP_ROW_H - 4)
	row.custom_minimum_size = Vector2(264, MP_ROW_H - 4)
	var sb := UiTheme.glass_box(8, 0.62 if mine else 0.42, 0.45 if mine else 0.10)
	sb.shadow_size = 0
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	if mine:
		sb.border_color = Color(0.4, 0.95, 1.0, 0.6)
		sb.bg_color = Color(0.10, 0.20, 0.28, 0.66)
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)
	var num := Label.new()
	num.name = "Rank"
	num.custom_minimum_size = Vector2(26, 0)
	num.add_theme_font_size_override("font_size", 17)
	hb.add_child(num)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var name_l := Label.new()
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.add_theme_font_size_override("font_size", 14)
	top.add_child(name_l)
	var score_l := Label.new()
	score_l.name = "Score"
	score_l.add_theme_font_size_override("font_size", 15)
	top.add_child(score_l)
	var sub := Label.new()
	sub.name = "Sub"
	sub.add_theme_font_size_override("font_size", 11)
	vb.add_child(sub)
	return row


func _mp_fill_row(row: Control, i: int, p: Dictionary, ranked: Array, mine: bool) -> void:
	var hb: HBoxContainer = row.get_child(0)
	var num: Label = hb.get_node("Rank")
	num.text = "%d" % (i + 1)
	num.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if i == 0 else Color(0.6, 0.63, 0.72))
	var vb: VBoxContainer = hb.get_child(1)
	var name_l: Label = vb.get_child(0).get_node("Name")
	var score_l: Label = vb.get_child(0).get_node("Score")
	var sub: Label = vb.get_node("Sub")
	name_l.text = str(p.name) + ("  " + tr("(du)") if mine else "")
	var leading := mine and i == 0 and ranked.size() > 1
	name_l.add_theme_color_override("font_color",
		Color(0.45, 1.0, 0.55) if leading
		else (Color(0.4, 0.95, 1.0) if mine else Color(0.85, 0.88, 0.95)))
	score_l.text = UiTheme.fmt_score(int(p.score))
	score_l.add_theme_color_override("font_color",
		Color(1, 1, 1) if mine else Color(0.75, 0.78, 0.85))
	var line := "%dx  ·  %s" % [int(p.combo), UiTheme.fmt_pct(float(p.acc) * 100.0)]
	# Eigene Zeile: Abstand zum Nachbarn (Vorsprung gruen / Rueckstand rot).
	var col := Color(0.55, 0.58, 0.68)
	if mine and ranked.size() > 1:
		if i == 0:
			line += "  ·  +" + _fmt_score_diff(int(p.score) - int(ranked[1].score))
			col = Color(0.45, 1.0, 0.55)
		else:
			line += "  ·  -" + _fmt_score_diff(int(ranked[i - 1].score) - int(p.score))
			col = Color(1.0, 0.55, 0.5)
	if int(p.id) == _mp_danger:
		line += "  ·  " + tr("gerade Letzter")
		col = Color(1.0, 0.72, 0.38)
		name_l.add_theme_color_override("font_color", col)
	sub.text = line
	sub.add_theme_color_override("font_color", col)


## Punktedifferenz kompakt: 950 · 12,3k · 1,2M.
func _fmt_score_diff(d: int) -> String:
	if d >= 1000000:
		return UiTheme.fmt_num(d / 1000000.0, 1) + "M"
	if d >= 10000:
		return UiTheme.fmt_num(d / 1000.0, 1) + "k"
	return UiTheme.fmt_score(d)


## Platzierung unter dem Rang: erst wenn alle fertig sind, Gleichstand = gleicher Platz.
func _update_mp_placement(ranked: Array, my_id: int) -> void:
	_update_mp_mode_text()
	if _results_screen == null or not is_instance_valid(_results_screen):
		return
	var scores := {}
	for p in ranked:
		var fin: Dictionary = p.get("final", {})
		if fin.is_empty():
			return
		scores[int(p.id)] = int(fin.get("score", p.score))
	if not scores.has(my_id):
		return
	var mine: int = scores[my_id]
	var better := 0
	var tied := 0
	for id in scores:
		if id == my_id:
			continue
		if int(scores[id]) > mine:
			better += 1
		elif int(scores[id]) == mine:
			tied += 1
	var n := scores.size()
	var txt := tr("PLATZ %d VON %d") % [better + 1, n]
	if better == 0 and tied == 0:
		txt = tr("SIEG")
	elif better == 0:
		txt = tr("GLEICHSTAND AUF PLATZ 1")
	_results_screen.set_placement(txt, better == 0)


## Teams: Teamsumme + Rundensieger; Royale: wer fliegt raus / Sieger.
func _update_mp_mode_text() -> void:
	if _results_screen == null or not is_instance_valid(_results_screen):
		return
	var mm: MatchMode = Lobby.mm
	var txt := ""
	var col := Color(0.85, 0.88, 0.95)
	if mm.kind == MatchMode.Kind.TEAMS:
		var done := mm.rounds_played > _mp_rounds_at_start and not mm.history.is_empty()
		var tot: Array = mm.history.back().totals if done else mm.team_totals(Lobby.live_results())
		txt = "%s %s : %s %s" % [mm.team_names[0], UiTheme.fmt_score(int(tot[0])),
			UiTheme.fmt_score(int(tot[1])), mm.team_names[1]]
		if done:
			var w := int(mm.history.back().winner)
			col = LiveTeamBar.COLS[w] if w >= 0 else col
			txt += "
" + ((tr("Runde an %s") % mm.team_names[w]) if w >= 0 else tr("Runde unentschieden"))
			if mm.series_over():
				var sw := mm.series_winner()
				txt += "
" + tr("Endstand %s %s : %s %s") % [mm.team_names[0], mm.team_wins[0],
					mm.team_wins[1], mm.team_names[1]]
				if sw >= 0:
					txt += "  —  " + tr("%s gewinnt") % mm.team_names[sw]
			else:
				txt += "
" + tr("Serie %s : %s  (%s)") % [mm.team_wins[0], mm.team_wins[1], mm.series_label()]
	elif mm.kind == MatchMode.Kind.ROYALE:
		if mm.round_no > _mp_round_no_at_start:
			var out: Array = []
			for id in mm.out_order:
				if int(mm.players[id].out_round) == _mp_round_no_at_start:
					out.append(_mp_name(int(id)))
			txt = (tr("Raus:") + " " + ", ".join(out)) if not out.is_empty() else tr("Gleichstand — keiner fliegt raus")
			var me := multiplayer.get_unique_id()
			if mm.players.has(me) and not mm.players[me].alive:
				txt = tr("Du bist raus.") + "
" + txt
				col = Color(1.0, 0.72, 0.38)
			if mm.is_over():
				txt += "
" + tr("SIEGER:") + " " + _mp_name(mm.winner_peer)
				var order: Array = []
				for id in mm.out_order:
					order.append(_mp_name(int(id)))
				txt += "
" + tr("Ausgeschieden:") + " " + ", ".join(order)
				col = Color(0.45, 1.0, 0.55)
		else:
			var low := mm.in_danger(Lobby.live_results())
			txt = tr("Letzter fliegt raus") + (" — " + tr("gerade:") + " " + _mp_name(low) if low >= 0 else "")
	_results_screen.set_mode_text(txt, col)


func _mp_name(id: int) -> String:
	return str(Lobby.players[id].name) if Lobby.players.has(id) else "?"


func _refresh_mp_ranking() -> void:
	if _results_screen == null or not is_instance_valid(_results_screen):
		return
	var ranked := Lobby.ranked_players()
	var my_id := multiplayer.get_unique_id()
	_update_mp_placement(ranked, my_id)
	var entries: Array = []
	for p in ranked:
		entries.append({ "id": int(p.id), "name": str(p.name),
			"final": p.get("final", {}), "score": int(p.get("score", 0)) })
	_results_screen.set_board(entries, my_id, Lobby.mods_text(GameSession.mods))


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
	# Intro der Results-Komponente (Zaehler, Rank-Pop, Sweep) abwarten.
	await get_tree().create_timer(2.6, true).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/results.png")
	print("SHOT gespeichert (results)")
	get_tree().quit(0)


func _capture_after_first_note() -> void:
	var idx := mini(6, _beatmap.hit_objects.size() - 1)
	# --shot-lead=<ms>: Vorlauf vor der Note (0 = Note genau auf der Linie).
	var lead := 150.0
	# --shot-at=<ms>: Songzeit des Bildes (spaetere Kapitel), --shot-out=<png>.
	var shot_at := -1.0
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/mania_3d.png"
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-lead="):
			lead = a.trim_prefix("--shot-lead=").to_float()
		elif a.begins_with("--shot-at="):
			shot_at = a.trim_prefix("--shot-at=").to_float()
		elif a.begins_with("--shot-out="):
			path = a.trim_prefix("--shot-out=")
	var target := _beatmap.hit_objects[idx].time - lead
	if shot_at >= 0.0:
		# Auf den naechsten Beat ab shot_at, dann --shot-lead als Versatz
		# (0 = genau auf dem Schlag, halbe Beatlaenge = zwischen Beats).
		core.no_fail = true
		target = _beat_ceil(shot_at) - lead
		if target - _time_ms() > 4000.0:
			SyncClock.seek_ms(target - 3000.0)
	var guard := 0
	while _time_ms() < target and guard < 3600:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	# Takt-Lage des Bildes (Vergleich auf/zwischen Beats per --shot-lead).
	print("GROOVE t=%.0f bpm=%.1f phase=%.2f kiai=%.2f groove=%.2f energy=%.2f dens=%.2f surge=%.2f wpulse=%.2f chapter=%d" % [_time_ms(), _clock.bpm, _clock.beat_phase, _kiai_mix, _groove, _music_energy, _density2, _surge, _world_pulse, _gal_idx])
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


## Panorama-Himmel als Basis (BG_SKY); false, wenn Shader/Texturen fehlen.
func _build_sky(env: Environment) -> bool:
	if _world_theme != WorldTheme.GALAXY and _build_theme_sky(env):
		return true
	_world_theme = WorldTheme.GALAXY
	var sp := "res://shaders/sky_panorama.gdshader"
	if not ResourceLoader.exists(sp):
		return false
	for n in SKY_PALS:
		var np := "res://assets_game/space/sky_%s.webp" % n
		var tp := "res://assets_game/space/sky_%s_stars.webp" % n
		if not ResourceLoader.exists(np) or not ResourceLoader.exists(tp):
			_sky_neb = []
			_sky_stars = []
			return false
		var nt: Texture2D = load(np)
		var st: Texture2D = load(tp)
		if nt == null or st == null:
			# Nicht importiert/defekt: alter Nebel-Himmel bleibt.
			_sky_neb = []
			_sky_stars = []
			return false
		_sky_neb.append(nt)
		_sky_stars.append(st)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load(sp)
	_sky_set(true, _sky_pal_for_hue(_theme_col.h, -1))
	# Mitte hinter der Strecke bleibt dunkel (Notenlesbarkeit).
	_sky_mat.set_shader_parameter("readability", 0.7)
	_sky_mat.set_shader_parameter("star_speed", 0.0)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	return true


## Naechste Panorama-Palette zum Farbton (zirkulaer), optional ohne `skip`.
func _sky_pal_for_hue(h: float, skip: int) -> int:
	var best := 0
	var bd := 9.0
	for i in SKY_HUES.size():
		if i == skip:
			continue
		var d := absf(fposmod(h - float(SKY_HUES[i]) + 0.5, 1.0) - 0.5)
		if d < bd:
			bd = d
			best = i
	return best


## Panorama-Slot a oder b auf Palette pal setzen (nur bei Wechsel).
func _sky_set(slot_a: bool, pal: int) -> void:
	if _sky_mat == null or pal < 0 or pal >= _sky_neb.size():
		return
	_sky_mat.set_shader_parameter(&"tex_a" if slot_a else &"tex_b", _sky_neb[pal])
	_sky_mat.set_shader_parameter(&"stars_a" if slot_a else &"stars_b", _sky_stars[pal])
	if slot_a:
		_sky_a = pal


## Kapitelwechsel: neue Palette in Slot b, Mischung laeuft ab dem Downbeat.
func _sky_begin_chapter(pal: int, first: bool) -> void:
	if _sky_mat == null or _world_theme != WorldTheme.GALAXY:
		return
	if _sky_b >= 0:
		# Wechsel mitten in einer Ueberblendung: b war das Ziel -> wird Basis.
		_sky_set(true, _sky_b)
		_sky_b = -1
	if first:
		_sky_set(true, pal)
	elif pal != _sky_a:
		_sky_set(false, pal)
		_sky_b = pal
	_sky_mat.set_shader_parameter(&"palette_mix", 0.0)


## Welt-Thema waehlen: --theme=<name> (Screenshots) > Einstellung > Automatisch.
## Fehlt Shader oder Panorama eines Themas -> Galaxie (laeuft immer).
func _forced_theme() -> String:
	var forced := Settings.world_theme_name()
	for a in OS.get_cmdline_args():
		if a.begins_with("--theme="):
			forced = a.substr(8)
	return forced


func _choose_world_theme() -> void:
	var forced := _forced_theme()
	var stars := GameSession.stars
	var t := WorldTheme.resolve(forced, _beatmap, stars, _theme_col)
	if t != WorldTheme.GALAXY and _theme_files(t).is_empty():
		t = WorldTheme.GALAXY
	_world_theme = t
	var pal := WorldTheme.palette(t)
	if not pal.is_empty():
		_theme_col = pal.line
		_theme_kiai = pal.kiai
	print("[world] theme=%s (setting=%s, stars=%.2f)" % [t, forced if forced != "" else "auto", stars])


## Bilddateien des Themas: Stamm -> res-Pfad ({} = Shader oder Panorama fehlt).
func _theme_files(t: String) -> Dictionary:
	var sp := WorldTheme.shader_path(t)
	if sp == "" or not ResourceLoader.exists(sp):
		return {}
	var dir := WorldTheme.asset_dir(t)
	var out := {}
	if not DirAccess.dir_exists_absolute(dir):
		return {}
	for fname in ResourceLoader.list_directory(dir):
		var ext := fname.get_extension().to_lower()
		if ext in ["webp", "png", "jpg", "exr", "hdr"]:
			var path := dir.path_join(fname)
			if ResourceLoader.exists(path):
				out[fname.get_basename()] = path
	return out


## Themen-Himmel: Shader-Uniforms per Konvention mit Texturen fuellen.
## tex_a/tex_b = Panorama (Stamm ohne Ebenen-Suffix), <key>_a/<key>_b =
## Ebene *_<key> (stars, embers, aurora, ...). Slot b = Slot a (palette_mix
## wird bei Themen nicht genutzt).
func _build_theme_sky(env: Environment) -> bool:
	var files := _theme_files(_world_theme)
	if files.is_empty():
		return false
	var sh: Shader = load(WorldTheme.shader_path(_world_theme))
	if sh == null:
		return false
	var samplers: Array[String] = []
	for u in sh.get_shader_uniform_list():
		if int(u.type) == TYPE_OBJECT:
			samplers.append(str(u.name))
	var keys := {}
	for sn in samplers:
		var base := sn
		if base.ends_with("_a") or base.ends_with("_b"):
			base = base.substr(0, base.length() - 2)
		keys[sn] = base
	# Ebenen-Dateien (Suffix passt zu einem Sampler) vs. Panorama.
	var layer_of := {}
	var pano := ""
	var stems: Array = files.keys()
	stems.sort()
	for stem in stems:
		var hit := ""
		for sn in keys:
			var b: String = keys[sn]
			if b != "tex" and (stem == b or stem.ends_with("_" + b)):
				hit = b
		if hit != "":
			layer_of[hit] = files[stem]
		elif pano == "" or stem.length() < pano.get_file().get_basename().length():
			pano = files[stem]
	if pano == "":
		return false
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sh
	for sn in keys:
		var b: String = keys[sn]
		var path: String = pano if b == "tex" else str(layer_of.get(b, ""))
		if path != "":
			_sky_mat.set_shader_parameter(sn, WorldTheme.get_cached(path))
	_sky_mat.set_shader_parameter("readability", 0.7)
	_sky_mat.set_shader_parameter("star_speed", 0.0)
	_sky_mat.set_shader_parameter("palette_mix", 0.0)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	print("[world] sky %s: pano=%s layers=%s" % [_world_theme, pano.get_file(), str(layer_of.keys())])
	return true


## Themen-Welt: Weltraum-Deko (Planeten, Galaxien, Landmarks, Station,
## Sonnenaufgang, alte Aurora) passt nicht in Inferno/Polarnacht/Synthwave ->
## in einen unsichtbaren Traeger. Sternenstrom, Horizont-Glow,
## Atmosphaeren-Kante und God-Rays bleiben (in Themenfarbe).
func _apply_theme_world() -> void:
	if _world_theme == WorldTheme.GALAXY or _cosmos == null:
		return
	for ch in _gal_chapters:
		ch.col = _theme_col.lerp(_theme_kiai, 0.35) if ch.kiai else _theme_col
		ch.col2 = _theme_kiai
	_gal_col = _theme_col
	_gal_col2 = _theme_kiai
	var keep := [_star_mat, _horizon_mat, _edge_band_mat, _rays_mat]
	var hidden := Node3D.new()
	hidden.name = "GalaxyOnly"
	hidden.visible = false
	var kids := _cosmos.get_children()
	_cosmos.add_child(hidden)
	for c in kids:
		var m: Material = c.material_override if c is GeometryInstance3D else null
		if m != null and keep.has(m):
			continue
		c.reparent(hidden, false)


## Drop in Themen-Welten zaehmen: Warp hoechstens 0.4 (Galaxie unveraendert).
func _themed_warp_cap(v: float) -> float:
	if _world_theme != WorldTheme.GALAXY and _sky_mat != null:
		return minf(v, 0.4)
	return v


## Beat-Vertrag (docs/worlds/beat_contract.md): Uniforms auf das Himmels-Material.
## Zeitbasis wie _clock (SyncClock.visual_time_ms). Neon: eigener Pfad, nichts setzen.
func _update_beat_contract(delta: float = 0.016) -> void:
	if _world_theme == WorldTheme.NEON:
		return
	var fx := _fx_level()
	if _clock.is_beat_edge:
		_beat_total += 1
	var bl := 60000.0 / _clock.bpm if _clock.bpm > 1.0 else 500.0
	if _clock.kiai and not _bc_kiai:
		_kiai_t0 = _vt
		_kiai_t1 = -1.0
	elif not _clock.kiai and _bc_kiai:
		_kiai_t1 = _vt
	_bc_kiai = _clock.kiai
	var on := fx > 0.0 and _clock.bpm > 1.0
	var since_start := (_vt - _kiai_t0) / bl if _kiai_t0 >= 0.0 else -1.0
	var since_end := (_vt - _kiai_t1) / bl if _kiai_t1 >= 0.0 else -1.0
	var m := _sky_mat
	m.set_shader_parameter(&"beat_pulse", clampf(_world_pulse, 0.0, 1.0) if on else 0.0)
	m.set_shader_parameter(&"beat_phase", _clock.beat_phase if on else 0.0)
	m.set_shader_parameter(&"bar_phase", _clock.bar_phase if on else 0.0)
	# Glatte Zeitbasis: nie zurueck, Clock-Korrekturen/Kantenversatz werden
	# ueber ~50 ms eingeblendet statt zu springen (Seek > 2 Beats: sofort).
	var bs_target := WorldTheme.beat_step(_beat_total, _clock.beat_phase)
	var bs_d := bs_target - _bs_smooth
	if absf(bs_d) > 2.0:
		_bs_smooth = bs_target
	elif bs_d > 0.0:
		_bs_smooth += bs_d * clampf(delta * 20.0, 0.0, 1.0)
	m.set_shader_parameter(&"beat_step", _bs_smooth if on else 0.0)
	m.set_shader_parameter(&"downbeat_pulse", WorldTheme.downbeat_pulse(_clock.bar_phase, _meter_at(_vt)) if on else 0.0)
	m.set_shader_parameter(&"kiai", _ch_kiai_w if on else 0.0)
	var drop_v := WorldTheme.drop_env(since_start, since_end, _comfort) if on else 0.0
	m.set_shader_parameter(&"drop", drop_v)
	# Vorwaerts-Fluss (Sturm-Durchflug): Integral ueber beat_step, im Drop
	# gedeckelt schneller (bis 1.8x), Komfort halb. Glatt: nur der Zuwachs von
	# beat_step zaehlt, ein Seek (> 2 Schlaege) setzt nur die Referenz neu.
	var dbs := _bs_smooth - _bs_flow_prev
	_bs_flow_prev = _bs_smooth
	if on and dbs > 0.0 and dbs < 2.0:
		_flow_phase += dbs * (1.0 + 0.8 * drop_v / WorldTheme.DROP_MAX) * (0.5 if _comfort else 1.0)
	m.set_shader_parameter(&"flow_phase", _flow_phase)
	m.set_shader_parameter(&"energy", _music_energy if on else 0.0)
	m.set_shader_parameter(&"comfort", 1.0 if _comfort else 0.0)


## Taktart (Schlaege pro Takt) der roten Linie bei Zeit t.
func _meter_at(t: float) -> int:
	var meter := 4
	var first := true
	for p in _beatmap.timing_points:
		if p.uninherited and p.beat_length > 0.0:
			if first or p.time <= t:
				meter = maxi(p.meter, 1)
				first = false
			if p.time > t:
				break
	return meter


## Pro Frame: Themen-Uniforms (Blitz-Abklingen, Wehen). Komfort = ruhiger.
func _update_theme_sky(delta: float) -> void:
	if _sky_mat == null or _world_theme == WorldTheme.GALAXY:
		return
	_update_beat_contract(delta)
	_theme_lightning = maxf(0.0, _theme_lightning - delta * 3.2)
	_sky_mat.set_shader_parameter(&"lightning", _theme_lightning)
	var flow_rate := (0.5 if _comfort else 1.0) * (1.0 + _ch_kiai_w * 0.6)
	_theme_flow += delta * flow_rate
	_sky_mat.set_shader_parameter(&"aurora_flow", _theme_flow)
	if _world_theme == WorldTheme.NEON:
		# Neon-Gitter: star_phase = Flug in Zellen, beat_pulse = Welle vom
		# Horizont zum Spieler ueber einen ganzen Schlag (1 -> 0).
		_theme_grid += delta * 1.2 * _bpm_factor * _flow * (1.0 + _kiai_mix * 0.5)
		_sky_mat.set_shader_parameter(&"star_phase", _theme_grid)
		var bp := pow(1.0 - clampf(_clock.beat_phase, 0.0, 1.0), 4.0) if _fx_level() > 0.0 else 0.0
		_sky_mat.set_shader_parameter(&"beat_pulse", bp * (0.7 if _comfort else 1.0))
		_sky_mat.set_shader_parameter(&"grid_intensity", lerpf(1.0, 1.35, _ch_kiai_w))
