extends Node

## Autoload "Settings": persistente Spieleinstellungen (user://settings.cfg).
## AR-Override betrifft NUR die Anflugzeit (preempt) — niemals Timing-Windows
## (Spec/Masterplan Regel 9). Scores mit Override sind "unranked".

const PATH := "user://settings.cfg"

signal changed

## -1 = Aus (Map-AR verwenden), sonst 0..10.
var ar_override: float = -1.0
## Globaler Kalibrierungs-Offset in ms (±200), wirkt auf alle Judgements.
var offset_ms: float = 0.0
## 0 = Aus, 1 = Dezent, 2 = Voll.
var tunnel_intensity: int = 2
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
## Hitsounds an/aus + Lautstaerke (0..1).
var hitsounds: bool = true
var hitsound_volume: float = 0.8
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

## Klang-Boost: EQ (Bass + Klarheit) und sanfter Kompressor auf dem Master-Bus.
## Beide Effekte arbeiten OHNE Lookahead/Delay — exakt 0 ms Zusatzlatenz,
## das Timing bleibt unberuehrt. Abschaltbar in den Settings.
var audio_enhance: bool = true
var _fx_eq_idx := -1
var _fx_comp_idx := -1


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


## Master-Bus-Effektkette einmalig aufbauen (nach dem Spektrum-Analyzer der
## SyncClock, damit dessen Instanz-Index stabil bleibt).
func _setup_audio_enhance() -> void:
	var bus := AudioServer.get_bus_index("Master")
	# 10-Band-EQ: satter, aber nicht droehnender Bass-Schub unten,
	# neutrale Mitten, etwas Praesenz und "Luft" oben.
	var eq := AudioEffectEQ10.new()
	var gains := [4.0, 3.2, 2.0, 0.6, 0.0, 0.0, 0.6, 1.2, 1.8, 1.6]
	for i in gains.size():
		eq.set_band_gain_db(i, gains[i])
	_fx_eq_idx = AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, eq)
	# Sanfter Kompressor: faengt die EQ-Spitzen ab (kein Clipping) und gibt
	# dem Mix Punch. Kein Lookahead -> latenzfrei.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -10.0
	comp.ratio = 2.5
	comp.attack_us = 40.0
	comp.release_ms = 200.0
	comp.gain = 2.0
	_fx_comp_idx = AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, comp)


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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	ar_override = float(cfg.get_value("game", "ar_override", -1.0))
	offset_ms = float(cfg.get_value("game", "offset_ms", 0.0))
	tunnel_intensity = int(cfg.get_value("game", "tunnel_intensity", 2))
	volume_db = float(cfg.get_value("game", "volume_db", 0.0))
	key_hook1 = int(cfg.get_value("keys", "hook1", KEY_Z))
	key_hook2 = int(cfg.get_value("keys", "hook2", KEY_X))
	for i in 4:
		key_lanes[i] = int(cfg.get_value("keys", "lane%d" % i, key_lanes[i]))
	mania_scroll = clampf(float(cfg.get_value("game", "mania_scroll", 1.0)), 0.5, 3.0)
	hitsounds = bool(cfg.get_value("game", "hitsounds", true))
	lane_glow = bool(cfg.get_value("game", "lane_glow", true))
	hitsound_volume = clampf(float(cfg.get_value("game", "hitsound_volume", 0.8)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("game", "fullscreen", false))
	fps_mode = clampi(int(cfg.get_value("game", "fps_mode", 2)), 0, 4)
	graphics_quality = clampi(int(cfg.get_value("game", "graphics_quality", 3)), 0, 4)
	audio_enhance = bool(cfg.get_value("game", "audio_enhance", true))
	profile_name = str(cfg.get_value("profile", "name", "Player"))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "ar_override", ar_override)
	cfg.set_value("game", "offset_ms", offset_ms)
	cfg.set_value("game", "tunnel_intensity", tunnel_intensity)
	cfg.set_value("game", "volume_db", volume_db)
	cfg.set_value("keys", "hook1", key_hook1)
	cfg.set_value("keys", "hook2", key_hook2)
	for i in 4:
		cfg.set_value("keys", "lane%d" % i, key_lanes[i])
	cfg.set_value("game", "mania_scroll", mania_scroll)
	cfg.set_value("game", "hitsounds", hitsounds)
	cfg.set_value("game", "lane_glow", lane_glow)
	cfg.set_value("game", "hitsound_volume", hitsound_volume)
	cfg.set_value("game", "fullscreen", fullscreen)
	cfg.set_value("game", "fps_mode", fps_mode)
	cfg.set_value("game", "graphics_quality", graphics_quality)
	cfg.set_value("game", "audio_enhance", audio_enhance)
	cfg.set_value("profile", "name", profile_name)
	cfg.save(PATH)


## Einstellungen auf die laufenden Systeme anwenden.
func apply() -> void:
	SyncClock.user_offset_ms = offset_ms
	AudioServer.set_bus_volume_db(0, volume_db)
	if _fx_eq_idx >= 0:
		var bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_effect_enabled(bus, _fx_eq_idx, audio_enhance)
		AudioServer.set_bus_effect_enabled(bus, _fx_comp_idx, audio_enhance)
	if DisplayServer.get_name() != "headless":
		# EXCLUSIVE_FULLSCREEN = echtes Vollbild (nicht nur randloses Fenster).
		var target := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target:
			DisplayServer.window_set_mode(target)
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


func is_hook_key(keycode: int) -> bool:
	return keycode == key_hook1 or keycode == key_hook2


## Spalte (0-3) fuer eine Mania-Taste, -1 wenn keine.
func lane_for_key(keycode: int) -> int:
	for i in 4:
		if key_lanes[i] == keycode:
			return i
	return -1
