extends Node

## Autoload "Settings": persistente Spieleinstellungen (user://settings.cfg).
## AR-Override betrifft NUR die Anflugzeit (preempt) — niemals Timing-Windows
## (Spec/Masterplan Regel 9). Scores mit Override sind "unranked".
##
## ===== Klang: Mastering-Kette (ALLES latenzfrei: kein Lookahead, kein Delay) =====
## Bus "Music" (send -> Master) fuer Song + Vorschau:
##   0 SpectrumAnalyzer      SyncClock, pre-Mastering (Visualizer/Effekte)
##   1 Capture               SongLoudness-Messung, pre-Mastering
##   2 HighPass 28 Hz        12 dB/oct, Subsonic gegen Rumpeln/Headroom
##   3 LowShelf 110 Hz       0..+7 dB (Settings.bass_boost)
##   4 EQ10                  62 Hz Kick-Punch 0..+1.5 dB (bass_boost),
##                           250/500 Hz -1/-0.5 (Mud), Klarheit: 2k +0.4,
##                           4k +0.8, 8k +0.6, 16k +1.5 (Praesenz/Air)
##   5 Amplify               Bass-Vorkompensation -0.25 dB je +1 dB Bass
##   6 Distortion ATAN       drive 0.2, post_gain = Kleinsignal-Ausgleich (Waerme)
##   7 Compressor (Glue)     eff. 2:1 (Engine-ratio 1.32), 10 ms / 150 ms, -18 dB, Make-up GLUE_MAKEUP_DB
##   8 StereoEnhance         pan_pullout 1.12, time_pullout 0 (kein Delay)
##   9 Amplify               +LIMIT_DRIVE_DB in den Limiter
##  10 Compressor (Limiter)  eff. 20:1 (Engine-ratio 1.84), 20 us, -0.8 dB Ceiling
## Bus "Master" (Hitsounds/UI + Music): nur Schutz-Limiter eff. 20:1 / 20 us / -0.3 dB.
## Godot-Kompressor: ratio NIE direkt setzen, immer godot_ratio() (siehe unten).
## NIE AudioEffectHardLimiter (Lookahead ~2 ms), NIE StereoEnhance mit time_pullout.
## Lautheit: SongLoudness normalisiert auf -11 dBFS RMS (-4..+6 dB).
## Gemessen (tests/run_mastering_tests.gd, Pink-Noise -11 dBFS RMS, K-gewichtet
## ~LUFS; pre = -8.7): Bass 0% -> -8.2, 75% -> -9.1, 100% -> -9.4; Peak <= -0.9 dBFS.

const PATH := "user://settings.cfg"

signal changed

## -1 = Aus (Map-AR verwenden), sonst 0..10.
var ar_override: float = -1.0
## Globaler Kalibrierungs-Offset in ms (±200), wirkt auf alle Judgements.
var offset_ms: float = 0.0
## 0 = Aus, 1 = Dezent, 2 = Voll.
var tunnel_intensity: int = 2
## Kamera: 0 = Komfort (Default, gegen Uebelkeit: Strecke kippt/rollt/hebt
## sich nicht, ruhigere Perspektive, gedaempfte Vorwaerts-Bewegung am Rand),
## 1 = Dynamisch (volle Flug-Bewegung). Der Schluessel ist neu: bestehende
## Nutzer ohne Eintrag landen dadurch einmalig auf Komfort.
var camera_mode: int = 0
## Welt-Thema: 0 = Automatisch (Default, WorldTheme.pick nach Song-Charakter),
## 1 = Galaxie, 2 = Bosskampf, 3 = Aurora, 4 = Neon.
var world_theme: int = 0
## Master-Lautstaerke in dB.
var volume_db: float = 0.0
## Frei belegbare Hook-Tasten (zusaetzlich zu Maus links/rechts).
var key_hook1: int = KEY_Z
var key_hook2: int = KEY_X
## Mania-4K: eine Taste pro Spalte.
var key_lanes: Array[int] = [KEY_D, KEY_F, KEY_J, KEY_K]
## Mania Scroll-Speed (x0.5 langsam .. x3.0 schnell). Rein visuell:
## verkuerzt/verlaengert nur die Anflugzeit, Timing-Fenster unveraendert.
var mania_scroll: float = 1.0
## Spur-Aufleuchten beim Tastendruck (Lane-Highlight) an/aus.
var lane_glow: bool = true
## Spurbreite: Abstand der 4 Spuren relativ zum Standard (0.7..1.2, 5er-Schritte).
## Noten bleiben bis 85 % gleich gross, darunter schrumpfen sie leicht mit.
var lane_spacing: float = 1.0
const LANE_SPACING_MIN := 0.7
const LANE_SPACING_MAX := 1.2
const LANE_SPACING_STEP := 0.05
## 2D-Modus: Kamera senkrecht von oben (klassische osu!mania-Spuren), keine
## 3D-Welt; Hintergrund = Map-Bild, abgedunkelt (bg_dim = Deckkraft 0..1)
## und optional leicht weichgezeichnet (bg_blur).
var playfield_2d: bool = false
var bg_dim: float = 0.3
var bg_blur: bool = true
## 2D-Notenform: 0 = Balken (flache Rechtecke), 1 = Kreis (runde Noten,
## Holds mit runden Enden, Receptors als Ringe).
var note_style_2d: int = 0
const NOTE_STYLE_BAR := 0
const NOTE_STYLE_CIRCLE := 1
## Hitsounds an/aus + Lautstaerke (0..1).
var hitsounds: bool = true
var hitsound_volume: float = 0.8
## Hitsound-Set: 0 Soft, 1 Clap, 2 Kick.
var hitsound_set: int = 0
## Echtes Vollbild (auch per F11 umschaltbar).
var fullscreen: bool = false
## Grafik-Qualitaet: 0 Niedrig (kein AA) · 1 Mittel (2x) · 2 Hoch (4x)
## · 3 Ultra (8x MSAA) · 4 Extrem (8x MSAA + 1.5x Supersampling).
var graphics_quality: int = 3
## FPS-Modus: 0 = VSync, 1 = Unlimited, 2 = 240, 3 = 360, 4 = 480.
## Unlimited/Caps schalten VSync ab — weniger Input-Latenz, besseres Timing.
## Default 240: Unlimited kann auf sehr neuen GPUs (Treiber-Timeouts)
## Instabilitaet ausloesen — wer will, stellt bewusst auf Unlimited.
var fps_mode: int = 2
## Anzeigename des Spielers (Profil).
var profile_name: String = "Player"

## Eigenes Profilbild (quadratisch beschnitten, 256px, user://avatar.png).
const AVATAR_PATH := "user://avatar.png"
signal avatar_changed


## Bild von beliebigem Pfad uebernehmen: quadratisch beschneiden, auf 256px
## verkleinern, als PNG speichern. true bei Erfolg.
func set_avatar(src_path: String) -> bool:
	var img := Image.new()
	if img.load(src_path) != OK:
		return false
	var side := mini(img.get_width(), img.get_height())
	if side < 8:
		return false
	var x0 := (img.get_width() - side) / 2
	var y0 := (img.get_height() - side) / 2
	img = img.get_region(Rect2i(x0, y0, side, side))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	if img.save_png(ProjectSettings.globalize_path(AVATAR_PATH)) != OK:
		return false
	avatar_changed.emit()
	return true


func avatar_texture() -> Texture2D:
	var p := ProjectSettings.globalize_path(AVATAR_PATH)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load(p) != OK:
		return null
	return ImageTexture.create_from_image(img)


func clear_avatar() -> void:
	var p := ProjectSettings.globalize_path(AVATAR_PATH)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	avatar_changed.emit()


var _vol_layer: CanvasLayer
var _vol_label: Label
var _vol_fill: ColorRect
var _vol_tween: Tween

## Klang: Mastering-Kette auf dem Music-Bus (siehe Kommentarblock oben).
## Bass wirkt IMMER ueber den Bass-Regler (0% = kein Boost); audio_enhance
## ("Klarheit") schaltet nur Praesenz/Air im EQ.
var audio_enhance: bool = true
## Bass-Staerke 0..1 (Default 0.75), skaliert Low-Shelf + Kick-Peak.
var bass_boost: float = 0.75

const BASS_SHELF_HZ := 110.0
const BASS_SHELF_MAX_DB := 7.0
## Sanfter Kick-Punch (EQ10-Band 62 Hz) bei bass_boost = 1.0.
const KICK_PEAK_MAX_DB := 1.5
## Vorkompensation: -0.25 dB je +1 dB Bass (Kompressor/Limiter druecken sonst
## die Zusatzenergie wieder weg -> gefuehlter Verlust).
const BASS_PRECOMP := -0.25
const SAT_DRIVE := 0.2
const GLUE_THRESHOLD_DB := -18.0
## Effektive Verhaeltnisse; ans Engine-ratio uebergeben via godot_ratio().
const GLUE_RATIO := 2.0
const LIMIT_RATIO := 20.0
## Godot-Kompressor rechnet die Ueberschreitung *2.08 (audio_effect_compressor.cpp:
## overdb = 2.08136898 * linear_to_db(peak / threshold)). Nominell ratio 2 wirkt
## so schon wie ein Limiter, ratio 20 drueckt laute Stellen WEIT unter die
## Schwelle (gemessen: Sinus -2 dBFS, Schwelle -18, ratio 20 -> -31 dBFS) -
## das war der Grund fuer "Musik zu leise". Darum umrechnen.
const GODOT_COMP_K := 2.08136898
const GLUE_MAKEUP_DB := 1.5
const LIMIT_DRIVE_DB := 2.0
const LIMIT_CEIL_DB := -0.8
const MASTER_CEIL_DB := -0.3
const STEREO_WIDTH := 1.12
# EQ10-Baender: 0=31 1=62 2=125 3=250 4=500 5=1k 6=2k 7=4k 8=8k 9=16k
const _EQ_KICK_BAND := 1
const _EQ_MUD := {3: -1.0, 4: -0.5}
const _EQ_CLARITY := {6: 0.4, 7: 0.8, 8: 0.6, 9: 1.5}

var _fx_shelf: AudioEffectLowShelfFilter
var _fx_eq: AudioEffectEQ10
var _fx_trim: AudioEffectAmplify


## Bass-Shelf in dB fuer bass_boost k (0..1).
static func bass_shelf_db(k: float) -> float:
	return BASS_SHELF_MAX_DB * clampf(k, 0.0, 1.0)


## Godot-Shelf: gain ist linear, wirkt als 40*log10(gain) dB (gemessen:
## gain 1.5 -> +6.9 dB bei 40 Hz). Also gain = 10^(dB/40).
static func shelf_gain_for_db(db: float) -> float:
	return pow(10.0, db / 40.0)


## Engine-ratio fuer ein gewuenschtes effektives Verhaeltnis (2 -> 1.32, 20 -> 1.84).
static func godot_ratio(effective: float) -> float:
	return 1.0 / (1.0 - (1.0 - 1.0 / maxf(effective, 1.0)) / GODOT_COMP_K)


## Pegel-Vorkompensation fuer den Bass-Schub (Shelf + Kick-Peak).
static func bass_precomp_db(k: float) -> float:
	var kk := clampf(k, 0.0, 1.0)
	return BASS_PRECOMP * (bass_shelf_db(kk) + KICK_PEAK_MAX_DB * kk)


## Kleinsignal-Verstaerkung von AudioEffectDistortion MODE_ATAN (Engine-Formel:
## atan(x*m)*d mit m = 10^(3*drive^2)-1+0.001, d = 1/(atan(m)*(1+8*drive))).
## post_gain = -dieser Wert haelt den Pegel gleich.
static func atan_gain_db(drive: float) -> float:
	var m := pow(10.0, drive * drive * 3.0) - 1.0 + 0.001
	var d := 1.0 / (atan(m) * (1.0 + drive * 8.0))
	return linear_to_db(m * d)

func _ready() -> void:
	# ALWAYS: F11 und Alt+Scroll muessen auch im Pausenmenue funktionieren.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_migrate_from_hookline()
	load_settings()
	_setup_audio_enhance()
	# Globales Glass-Theme: ALLE Controls (Slider, Dropdowns, Scrollbalken,
	# Popups …) verlieren die graue Godot-Standard-Optik.
	get_window().theme = UiTheme.build_theme()
	apply()


## Mastering-Kette einmalig hinter Analyzer + Capture der SyncClock haengen
## (deren Indizes 0/1 bleiben stabil). Alles latenzfrei.
func _setup_audio_enhance() -> void:
	var bus: int = SyncClock.ensure_music_bus()
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 28.0
	hp.resonance = 0.5
	hp.db = AudioEffectFilter.FILTER_12DB
	AudioServer.add_bus_effect(bus, hp)
	_fx_shelf = AudioEffectLowShelfFilter.new()
	_fx_shelf.cutoff_hz = BASS_SHELF_HZ
	_fx_shelf.resonance = 0.5
	AudioServer.add_bus_effect(bus, _fx_shelf)
	_fx_eq = AudioEffectEQ10.new()
	AudioServer.add_bus_effect(bus, _fx_eq)
	_fx_trim = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(bus, _fx_trim)
	# Waerme: sehr sanfte atan-Saettigung, Kleinsignal-Pegel neutral.
	var sat := AudioEffectDistortion.new()
	sat.mode = AudioEffectDistortion.MODE_ATAN
	sat.drive = SAT_DRIVE
	sat.pre_gain = 0.0
	sat.post_gain = -atan_gain_db(SAT_DRIVE)
	sat.keep_hf_hz = 16000.0
	AudioServer.add_bus_effect(bus, sat)
	# Glue: 2:1, Attack 10 ms laesst den Kick-Anschlag durch, Release 150 ms.
	var glue := AudioEffectCompressor.new()
	glue.threshold = GLUE_THRESHOLD_DB
	glue.ratio = godot_ratio(GLUE_RATIO)
	glue.attack_us = 10000.0
	glue.release_ms = 150.0
	glue.gain = GLUE_MAKEUP_DB
	AudioServer.add_bus_effect(bus, glue)
	# Breite nur ueber M/S-Pegel, time_pullout = 0 -> kein Delay.
	var width := AudioEffectStereoEnhance.new()
	width.pan_pullout = STEREO_WIDTH
	width.time_pullout_ms = 0.0
	width.surround = 0.0
	AudioServer.add_bus_effect(bus, width)
	var drive := AudioEffectAmplify.new()
	drive.volume_db = LIMIT_DRIVE_DB
	AudioServer.add_bus_effect(bus, drive)
	# Limiter: Kompressor effektiv 20:1 / 20 us. NIE AudioEffectHardLimiter (Lookahead
	# verzoegert das Audio um ~2 ms und verschiebt das Timing).
	AudioServer.add_bus_effect(bus, _limiter(LIMIT_CEIL_DB))
	# Master bleibt sauber (Hitsounds/UI): nur Schutz-Limiter am Ende.
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), _limiter(MASTER_CEIL_DB))
	_apply_mastering()


static func _limiter(ceil_db: float) -> AudioEffectCompressor:
	var lim := AudioEffectCompressor.new()
	lim.threshold = ceil_db
	lim.ratio = godot_ratio(LIMIT_RATIO)
	lim.attack_us = 20.0
	lim.release_ms = 60.0
	lim.gain = 0.0
	return lim


## Regler-abhaengige Werte live setzen (Bass-Shelf, Kick, EQ, Vorkompensation).
func _apply_mastering() -> void:
	if _fx_eq == null:
		return
	var k := clampf(bass_boost, 0.0, 1.0)
	_fx_shelf.gain = shelf_gain_for_db(bass_shelf_db(k))
	for i in 10:
		var g := 0.0
		if i == _EQ_KICK_BAND:
			g = KICK_PEAK_MAX_DB * k
		elif _EQ_MUD.has(i):
			g = _EQ_MUD[i]
		elif audio_enhance and _EQ_CLARITY.has(i):
			g = _EQ_CLARITY[i]
		_fx_eq.set_band_gain_db(i, g)
	_fx_trim.volume_db = bass_precomp_db(k)


## Einmalige Migration: Projekt hiess frueher HOOKLINE — Settings/Scores/Caches
## aus dem alten user://-Verzeichnis uebernehmen, falls noch nicht vorhanden.
func _migrate_from_hookline() -> void:
	var old_dir := OS.get_data_dir().path_join("Godot/app_userdata/HOOKLINE")
	if not DirAccess.dir_exists_absolute(old_dir):
		return
	for fname in ["settings.cfg", "scores.cfg", "stars.cfg", "last_played.cfg"]:
		var dest := ProjectSettings.globalize_path("user://" + fname)
		var src := old_dir.path_join(fname)
		if FileAccess.file_exists(src) and not FileAccess.file_exists(dest):
			DirAccess.copy_absolute(src, dest)


func load_settings(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	ar_override = float(cfg.get_value("game", "ar_override", -1.0))
	offset_ms = float(cfg.get_value("game", "offset_ms", 0.0))
	tunnel_intensity = int(cfg.get_value("game", "tunnel_intensity", 2))
	camera_mode = clampi(int(cfg.get_value("game", "camera_mode", 0)), 0, 1)
	world_theme = clampi(int(cfg.get_value("game", "world_theme", 0)), 0, WORLD_ORDER.size())
	volume_db = float(cfg.get_value("game", "volume_db", 0.0))
	key_hook1 = int(cfg.get_value("keys", "hook1", KEY_Z))
	key_hook2 = int(cfg.get_value("keys", "hook2", KEY_X))
	for i in 4:
		key_lanes[i] = int(cfg.get_value("keys", "lane%d" % i, key_lanes[i]))
	mania_scroll = clampf(float(cfg.get_value("game", "mania_scroll", 1.0)), 0.5, 3.0)
	hitsounds = bool(cfg.get_value("game", "hitsounds", true))
	lane_glow = bool(cfg.get_value("game", "lane_glow", true))
	lane_spacing = clamp_lane_spacing(float(cfg.get_value("game", "lane_spacing", 1.0)))
	playfield_2d = bool(cfg.get_value("game", "playfield_2d", false))
	bg_dim = clamp_bg_dim(float(cfg.get_value("game", "bg_dim", 0.3)))
	bg_blur = bool(cfg.get_value("game", "bg_blur", true))
	note_style_2d = clampi(int(cfg.get_value("game", "note_style_2d", 0)), 0, 1)
	hitsound_set = clampi(int(cfg.get_value("game", "hitsound_set", 0)), 0, 2)
	hitsound_volume = clampf(float(cfg.get_value("game", "hitsound_volume", 0.8)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("game", "fullscreen", false))
	fps_mode = clampi(int(cfg.get_value("game", "fps_mode", 2)), 0, 4)
	graphics_quality = clampi(int(cfg.get_value("game", "graphics_quality", 3)), 0, 4)
	audio_enhance = bool(cfg.get_value("game", "audio_enhance", true))
	bass_boost = clampf(float(cfg.get_value("game", "bass_boost", 0.75)), 0.0, 1.0)
	profile_name = str(cfg.get_value("profile", "name", "Player"))


func save(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "ar_override", ar_override)
	cfg.set_value("game", "offset_ms", offset_ms)
	cfg.set_value("game", "tunnel_intensity", tunnel_intensity)
	cfg.set_value("game", "camera_mode", camera_mode)
	cfg.set_value("game", "world_theme", world_theme)
	cfg.set_value("game", "volume_db", volume_db)
	cfg.set_value("keys", "hook1", key_hook1)
	cfg.set_value("keys", "hook2", key_hook2)
	for i in 4:
		cfg.set_value("keys", "lane%d" % i, key_lanes[i])
	cfg.set_value("game", "mania_scroll", mania_scroll)
	cfg.set_value("game", "hitsounds", hitsounds)
	cfg.set_value("game", "lane_glow", lane_glow)
	cfg.set_value("game", "lane_spacing", lane_spacing)
	cfg.set_value("game", "playfield_2d", playfield_2d)
	cfg.set_value("game", "bg_dim", bg_dim)
	cfg.set_value("game", "bg_blur", bg_blur)
	cfg.set_value("game", "note_style_2d", note_style_2d)
	cfg.set_value("game", "hitsound_set", hitsound_set)
	cfg.set_value("game", "hitsound_volume", hitsound_volume)
	cfg.set_value("game", "fullscreen", fullscreen)
	cfg.set_value("game", "fps_mode", fps_mode)
	cfg.set_value("game", "graphics_quality", graphics_quality)
	cfg.set_value("game", "audio_enhance", audio_enhance)
	cfg.set_value("game", "bass_boost", bass_boost)
	cfg.set_value("profile", "name", profile_name)
	cfg.save(path)


## Einstellungen auf die laufenden Systeme anwenden.
func apply() -> void:
	SyncClock.user_offset_ms = offset_ms
	AudioServer.set_bus_volume_db(0, volume_db)
	_apply_mastering()
	if DisplayServer.get_name() != "headless":
		# EXCLUSIVE_FULLSCREEN = echtes Vollbild (nicht nur randloses Fenster).
		var target := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		# Test-/Screenshot-Laeufe: nie Vollbild (sonst landet das Testfenster auf
		# dem Hauptmonitor, auf dem der Nutzer spielt) und fest auf Monitor 2.
		if is_test_run():
			target = DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target:
			DisplayServer.window_set_mode(target)
		if is_test_run():
			_place_test_window()
		# Grafik-Qualitaet: MSAA-Stufe + optionales Supersampling.
		var vp := get_viewport()
		match graphics_quality:
			0:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.msaa_2d = Viewport.MSAA_DISABLED
				vp.scaling_3d_scale = 1.0
			1:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.msaa_2d = Viewport.MSAA_2X
				vp.scaling_3d_scale = 1.0
			2:
				vp.msaa_3d = Viewport.MSAA_4X
				vp.msaa_2d = Viewport.MSAA_4X
				vp.scaling_3d_scale = 1.0
			3:
				vp.msaa_3d = Viewport.MSAA_8X
				vp.msaa_2d = Viewport.MSAA_8X
				vp.scaling_3d_scale = 1.0
			4:
				# Extrem: 8x MSAA + 1.5x Supersampling (>16x-MSAA-Qualitaet).
				vp.msaa_3d = Viewport.MSAA_8X
				vp.msaa_2d = Viewport.MSAA_8X
				vp.scaling_3d_scale = 1.5
		# FPS: VSync-Modus vs. Unlimited/Cap (Input wird pro Frame gepollt —
		# mehr FPS = praezisere Hit-Zeitstempel).
		match fps_mode:
			0:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
				Engine.max_fps = 0
			1:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 0
			2:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 240
			3:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 360
			4:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 480
	changed.emit()


## F11 = Vollbild-Toggle · Alt+Mausrad = Master-Lautstaerke (wie osu).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		fullscreen = not fullscreen
		apply()
		save()
		return
	if event is InputEventMouseButton and event.pressed and event.alt_pressed:
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = 2.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = -2.0
		if step != 0.0:
			volume_db = clampf(volume_db + step, -30.0, 0.0)
			apply()
			save()
			_show_volume_overlay()
			get_viewport().set_input_as_handled()


## Kleines osu-artiges Overlay unten rechts: Prozent + Balken, blendet aus.
func _show_volume_overlay() -> void:
	if _vol_layer == null:
		_vol_layer = CanvasLayer.new()
		_vol_layer.layer = 100
		add_child(_vol_layer)
		var panel := PanelContainer.new()
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = -262
		panel.offset_right = -22
		panel.offset_top = -92
		panel.offset_bottom = -22
		var sb := UiTheme.glass_box(12, 0.8)
		sb.set_content_margin_all(14)
		panel.add_theme_stylebox_override("panel", sb)
		_vol_layer.add_child(panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		panel.add_child(vb)
		_vol_label = Label.new()
		_vol_label.add_theme_font_size_override("font_size", 15)
		vb.add_child(_vol_label)
		var bar_bg := Control.new()
		bar_bg.custom_minimum_size = Vector2(210, 6)
		vb.add_child(bar_bg)
		var bg_rect := ColorRect.new()
		bg_rect.size = Vector2(210, 6)
		bg_rect.color = Color(1, 1, 1, 0.12)
		bar_bg.add_child(bg_rect)
		_vol_fill = ColorRect.new()
		_vol_fill.size = Vector2(0, 6)
		_vol_fill.color = Color(0.20, 0.85, 1.0)
		bar_bg.add_child(_vol_fill)
	var pct := int(round((volume_db + 30.0) / 30.0 * 100.0))
	_vol_label.text = "Lautstaerke   %d %%" % pct
	_vol_fill.size = Vector2(210.0 * float(pct) / 100.0, 6)
	_vol_layer.visible = true
	if _vol_tween != null and _vol_tween.is_valid():
		_vol_tween.kill()
	var panel_node := _vol_layer.get_child(0) as Control
	panel_node.modulate.a = 1.0
	_vol_tween = create_tween()
	_vol_tween.tween_interval(1.1)
	_vol_tween.tween_property(panel_node, "modulate:a", 0.0, 0.35)
	_vol_tween.tween_callback(func(): _vol_layer.visible = false)


## Shader-Intensitaet fuer die gewaehlte Tunnel-Stufe.
func tunnel_intensity_value() -> float:
	match tunnel_intensity:
		0: return 0.0
		1: return 0.32
		_: return 0.62


## true = Komfort-Kamera (ruhig, gegen Motion-Sickness).
func comfort_camera() -> bool:
	return camera_mode == 0


## Fest gewaehltes Welt-Thema ("galaxy"/"boss"/"aurora"/"neon") oder "" = automatisch.
## Reihenfolge der Welt-Auswahl (Index 1..n; 0 = automatisch). Neue Welten hinten anhaengen.
const WORLD_ORDER: Array[String] = ["galaxy", "boss", "aurora", "neon", "eclipse", "abyss", "fractal", "obsidian", "storm", "singularity", "monolith", "rift", "nerve"]

func world_theme_name() -> String:
	if world_theme >= 1 and world_theme <= WORLD_ORDER.size():
		return WORLD_ORDER[world_theme - 1]
	return ""


## Spurbreite auf den erlaubten Bereich + 5-%-Raster ziehen (Datei kann alles enthalten).
static func clamp_lane_spacing(v: float) -> float:
	if is_nan(v):
		return 1.0
	v = clampf(v, LANE_SPACING_MIN, LANE_SPACING_MAX)
	return snappedf(v, LANE_SPACING_STEP)


## Hintergrund-Deckkraft (2D) auf 0..1 ziehen, 5-%-Raster.
static func clamp_bg_dim(v: float) -> float:
	if is_nan(v):
		return 0.3
	return snappedf(clampf(v, 0.0, 1.0), 0.05)


## Notengroesse zur Spurbreite: bis 85 % voll, darunter leicht mitskalieren,
## damit sich Nachbarnoten nie beruehren.
static func lane_note_scale(spacing: float) -> float:
	return clampf(spacing / 0.85, 0.0, 1.0)


func is_hook_key(keycode: int) -> bool:
	return keycode == key_hook1 or keycode == key_hook2


## Spalte (0-3) fuer eine Mania-Taste, -1 wenn keine.
func lane_for_key(keycode: int) -> int:
	for i in 4:
		if key_lanes[i] == keycode:
			return i
	return -1


## Laeuft gerade ein automatischer Test (Screenshot, Autoplay, Video)?
static func is_test_run() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot") or a == "--autoplay" or a == "--write-movie" or a == "--clip" or a == "--perf":
			return true
	return false


## Testfenster auf den Nicht-Hauptmonitor legen (Nutzer spielt auf dem
## Hauptmonitor). Gibt es nur einen Monitor, bleibt das Fenster, wo es ist.
func _place_test_window() -> void:
	var primary := DisplayServer.get_primary_screen()
	for s in DisplayServer.get_screen_count():
		if s == primary:
			continue
		var pos := DisplayServer.screen_get_position(s)
		DisplayServer.window_set_position(pos + Vector2i(120, 120))
		return
