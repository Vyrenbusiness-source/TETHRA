class_name OrbitBackdrop
extends Control

## Orbit-Hintergrund hinter den Ringen (Settings.orbit_background):
##   Welt    = Himmel der 3D-Welt (dieselbe Auswahl wie im 3D-Modus) in einem
##             eigenen SubViewport, ruhige Kamera (nur langsames Gieren, nie
##             Kippen/Rollen), dezenter Beat-Puls, Kiai etwas heller. Darueber
##             eine runde dunkle Vignette: im Ring-Bereich bleibt der
##             Hintergrund dunkel (Lesbarkeit) und fast unbewegt.
##   Map-Bild = Cover der Map, abgedunkelt (Settings.bg_dim).
##   Aus     = schwarz.
## Ohne Welten-Paket (oder wenn die Welt nicht baubar ist) faellt "Welt"
## automatisch auf das Map-Bild zurueck.

## Modi = Settings.ORBIT_BG_* (hier gespiegelt: keine statischen Autoload-Bezuege).
const BG_WORLD := 0
const BG_MAP := 1
const BG_OFF := 2
const BLACK := Color(0.008, 0.01, 0.018)
## SubViewport-Aufloesung relativ zum Fenster (Himmel ist weich, die Vignette
## dunkelt ihn ohnehin ab): spart Pixel-Shader-Last.
const RES_SCALE := 0.75
## Kamera: Blick knapp ueber den Horizont, langsames Pendeln um die Hochachse.
const CAM_PITCH_DEG := 4.0
const CAM_FOV := 72.0
const CAM_SWAY_DEG := 7.0
const CAM_SWAY_PERIOD_S := 140.0
## Himmel-Helligkeit (Shader `brightness`) ruhig / im Kiai.
const SKY_BRIGHT := 0.80
const SKY_BRIGHT_KIAI := 0.95
## Beat-Puls am Himmel (Anteil von beat_env) ruhig / im Kiai.
const PULSE_GAIN := 0.30
const PULSE_GAIN_KIAI := 0.55
## Vignette (Radien in Bildschirmhoehen ab Mitte, Deckkraft Schwarz):
## bis knapp hinter den Aussenring (OrbitView.R_OUTER_K = 0.37) fast deckend.
const VIG_STOPS := [
	[0.00, 0.86],
	[0.44, 0.84],
	[0.62, 0.62],
	[0.85, 0.40],
	[1.10, 0.30],
]

var mode := -1           ## tatsaechlich gezeigter Modus (BG_*)
var world := ""          ## Welt-Thema bei mode = Welt
var _vp: SubViewport
var _vp_rect: TextureRect
var _vig: TextureRect
var _cam: Camera3D
var _mat: ShaderMaterial
var _map: TextureRect
var _t := 0.0
var _flow := 0.0
var _pulse := 0.0


## want = Settings.orbit_background_mode(), forced = Welt-Thema ("" = Auto).
func setup(beatmap: Beatmap, want: int, forced: String, stars: float, cover: Texture2D, bg_dim: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var black := ColorRect.new()
	black.color = BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	mode = want
	if mode == BG_WORLD and not _build_world(beatmap, forced, stars, cover):
		mode = BG_MAP
	if mode == BG_MAP:
		_build_map(cover, bg_dim)
	print("[orbit] background=%s%s" % [["world", "map", "off"][clampi(mode, 0, 2)],
			(" theme=" + world) if mode == BG_WORLD else ""])


func _build_map(cover: Texture2D, bg_dim: float) -> void:
	if cover == null:
		return
	_map = TextureRect.new()
	_map.texture = cover
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Settings.bg_dim = Deckkraft des Map-Bilds (0 = aus).
	# Orbit dimmt staerker als Mania: Ziele liegen ueber dem ganzen Bild.
	_map.modulate = Color(1, 1, 1, bg_dim * 0.6)
	_map.visible = bg_dim > 0.001
	add_child(_map)


func _build_world(beatmap: Beatmap, forced: String, stars: float, cover: Texture2D) -> bool:
	if not WorldBackdrop.has_world_pack():
		return false
	var col := Color(0.22, 0.68, 0.90)
	var cc := WorldBackdrop.cover_colors(cover)
	if cc.size() == 2:
		col = cc[0]
	var t := WorldTheme.resolve(forced, beatmap, stars, col)
	if t == WorldTheme.GALAXY:
		_mat = WorldBackdrop.galaxy_material(col.h)
	else:
		_mat = WorldBackdrop.theme_sky_material(t)
	if _mat == null:
		return false
	world = t
	# Ruhiger Hintergrund: keine Blitze, kein Warp/Drop, Komfort-Pfade der Shader.
	_mat.set_shader_parameter(&"comfort", 1.0)
	_mat.set_shader_parameter(&"brightness", SKY_BRIGHT)
	_mat.set_shader_parameter(&"lightning", 0.0)
	_mat.set_shader_parameter(&"warp", 0.0)
	_mat.set_shader_parameter(&"drop", 0.0)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.size = _vp_size()
	add_child(_vp)
	var env := Environment.new()
	env.background_color = BLACK
	env.glow_enabled = false
	WorldBackdrop.attach_sky(env, _mat)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.rotation_degrees = Vector3(CAM_PITCH_DEG, 0.0, 0.0)
	_cam.current = true
	_vp.add_child(_cam)
	_vp_rect = TextureRect.new()
	_vp_rect.texture = _vp.get_texture()
	_vp_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vp_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_vp_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vp_rect)
	_vig = TextureRect.new()
	_vig.texture = _vignette_texture()
	_vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vig.stretch_mode = TextureRect.STRETCH_SCALE
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vig)
	_place()
	resized.connect(_place)
	return true


func _vp_size() -> Vector2i:
	var s := get_viewport().get_visible_rect().size
	return Vector2i(maxi(64, int(s.x * RES_SCALE)), maxi(64, int(s.y * RES_SCALE)))


## Vignette: quadratisch (Kreis bleibt rund), Seite = 2.2 Bildschirmhoehen.
func _place() -> void:
	if _vig == null:
		return
	var s := get_viewport().get_visible_rect().size
	var side := s.y * 2.2
	_vig.position = s * 0.5 - Vector2(side, side) * 0.5
	_vig.size = Vector2(side, side)
	if _vp != null:
		_vp.size = _vp_size()


## Radialer Verlauf (keine eigenen Shader: nichts extra zu kompilieren).
func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in VIG_STOPS:
		offs.append(float(st[0]) / 1.1)
		cols.append(Color(BLACK.r, BLACK.g, BLACK.b, float(st[1])))
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 512
	gt.height = 512
	return gt


## Pro Frame: t_ms Songzeit, beat = BeatClock (beat_env/kiai_mix), intensity 0..1.
func update_world(delta: float, beat: BeatClock, intensity: float) -> void:
	if _mat == null:
		return
	_t += delta
	var kiai := clampf(beat.kiai_mix, 0.0, 1.0)
	_cam.rotation_degrees = Vector3(CAM_PITCH_DEG,
			CAM_SWAY_DEG * sin(_t * TAU / CAM_SWAY_PERIOD_S), 0.0)
	# Puls weich nachgefuehrt (kein Flackern bei kurzen Huellkurven).
	var target := beat.beat_env * lerpf(PULSE_GAIN, PULSE_GAIN_KIAI, kiai) * (0.5 + 0.5 * intensity)
	_pulse = lerpf(_pulse, target, clampf(delta * 18.0, 0.0, 1.0))
	_mat.set_shader_parameter(&"beat_pulse", clampf(_pulse, 0.0, 1.0))
	_mat.set_shader_parameter(&"beat_phase", beat.beat_phase)
	_mat.set_shader_parameter(&"bar_phase", beat.bar_phase)
	_mat.set_shader_parameter(&"kiai", kiai * 0.6)
	_mat.set_shader_parameter(&"energy", 0.25 + 0.35 * intensity)
	_mat.set_shader_parameter(&"brightness", lerpf(SKY_BRIGHT, SKY_BRIGHT_KIAI, kiai))
	_flow += delta * (0.4 + 0.3 * kiai)
	_mat.set_shader_parameter(&"aurora_flow", _flow)


## Fuer Messungen: nur der Hintergrund (Ringe/HUD ausgeblendet) ist der Aufrufer.
func is_world() -> bool:
	return mode == BG_WORLD and _mat != null
