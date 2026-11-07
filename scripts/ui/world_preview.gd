class_name WorldPreview
extends Control

## Live-Vorschau einer Welt (Einstellungen): SubViewport mit Komfort-Kamera,
## Welt-Himmel (Shader + Texturen wie mania_3d._build_theme_sky) und einer
## angedeuteten dunklen Strecke. Beat-Uniforms mit 120 BPM nach
## docs/worlds/beat_contract.md (inkl. Komfort-Regeln: glatte beat_step-Formel).
## Texturen laden per ResourceLoader.load_threaded_request (kein Ruckeln),
## gerendert wird nur sichtbar (UPDATE_WHEN_VISIBLE), Freigabe beim Schliessen.

const SIZE_PX := Vector2(384, 216)
const BPM := 120.0
const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const FADE_OUT := 0.14
const FADE_IN := 0.35

var _vp: SubViewport
var _view: TextureRect
var _label: Label
var _mat: ShaderMaterial
var _env: Environment
var _gen := 0
var _pending: Array[String] = []
var _pending_shader: Shader
var _pending_keys: Dictionary = {}
var _pending_pano := ""
var _pending_layers: Dictionary = {}
var _t := 0.0
var _fade: Tween
var _loading_t := 0.0
var _live := false


func _ready() -> void:
	custom_minimum_size = SIZE_PX
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.02, 0.02, 0.03, 1.0)
	fb.set_corner_radius_all(14)
	frame.add_theme_stylebox_override("panel", fb)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_vp = SubViewport.new()
	_vp.size = Vector2i(int(SIZE_PX.x), int(SIZE_PX.y))
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.gui_disable_input = true
	add_child(_vp)
	_build_scene()

	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.modulate.a = 0.0
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_view)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", UiTheme.DIM)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_label)

	# Feiner Glasrand ueber dem Bild.
	var rim := Panel.new()
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0, 0, 0, 0)
	rb.set_corner_radius_all(14)
	rb.set_border_width_all(1)
	rb.border_color = Color(1, 1, 1, 0.16)
	rim.add_theme_stylebox_override("panel", rb)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rim)
	set_process(false)


func _exit_tree() -> void:
	release()


## Ressourcen freigeben (Schliessen): Rendern aus, Himmel + Texturen los.
func release() -> void:
	_gen += 1
	_live = false
	_pending.clear()
	_pending_shader = null
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _env != null:
		_env.sky = null
	_mat = null
	set_process(false)


func _build_scene() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.01, 0.01, 0.02)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0, 0, 0)
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	we.environment = _env
	_vp.add_child(we)

	# Komfort-Kamera (mania_3d Default).
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.1, 7.6)
	cam.rotation_degrees = Vector3(-16, 0, 0)
	cam.fov = 62.0
	cam.current = true
	_vp.add_child(cam)

	var zmid := (Z_FAR + Z_LINE) * 0.5
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(8.4, absf(Z_FAR) + 6.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, zmid)
	road.material_override = _unshaded(Color(0.02, 0.02, 0.03, 0.94))
	_vp.add_child(road)
	for x in [-1.7, 0.0, 1.7]:
		var ln := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.035, absf(Z_FAR) + 6.0)
		ln.mesh = lq
		ln.rotation_degrees = Vector3(-90, 0, 0)
		ln.position = Vector3(x, ROAD_Y, zmid)
		ln.material_override = _unshaded(Color(0.30, 0.32, 0.40, 0.35))
		_vp.add_child(ln)
	for sx in [-3.6, 3.6]:
		var edge := MeshInstance3D.new()
		var eq := QuadMesh.new()
		eq.size = Vector2(0.10, absf(Z_FAR) + 8.0)
		edge.mesh = eq
		edge.rotation_degrees = Vector3(-90, 0, 0)
		edge.position = Vector3(sx, ROAD_Y, zmid + 2.0)
		edge.material_override = _unshaded(Color(0.55, 0.60, 0.72, 0.6))
		_vp.add_child(edge)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Welt anzeigen. world: Name aus Settings.WORLD_ORDER, "" = Automatisch.
func show_world(world: String) -> void:
	_gen += 1
	_pending.clear()
	_live = false
	_fade_to(0.0, FADE_OUT)
	if world == "":
		_text("Automatisch: Die Welt passt sich dem Song an.\nKeine feste Vorschau.")
		return
	if world == WorldTheme.GALAXY:
		_text("Galaxie: Standard-Weltraum mit Planeten.")
		return
	if world == WorldTheme.NEON:
		_text("Neon: klassischer Neon-Himmel im Spiel.")
		return
	if not WorldTheme.is_available(world) or not _resolve(world):
		_text("Welt nicht installiert")
		return
	_text("Lädt …")
	_loading_t = 0.0
	for p in _pending_paths():
		ResourceLoader.load_threaded_request(p, "", true)
		_pending.append(p)
	set_process(true)


func _text(t: String) -> void:
	_label.text = t
	_label.modulate.a = 1.0
	_label.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _pending.is_empty():
		set_process(false)


func _fade_to(a: float, dur: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_view, "modulate:a", a, dur)


## Shader + Sampler-Konvention wie mania_3d._build_theme_sky.
func _resolve(world: String) -> bool:
	var dir := WorldTheme.asset_dir(world)
	var files := {}
	if not DirAccess.dir_exists_absolute(dir):
		return false
	for fname in ResourceLoader.list_directory(dir):
		if fname.get_extension().to_lower() in ["webp", "png", "jpg", "exr", "hdr"]:
			var path := dir.path_join(fname)
			if ResourceLoader.exists(path):
				files[fname.get_basename()] = path
	if files.is_empty():
		return false
	var sh: Shader = load(WorldTheme.shader_path(world))
	if sh == null:
		return false
	var keys := {}
	for u in sh.get_shader_uniform_list():
		if int(u.type) == TYPE_OBJECT:
			var sn := str(u.name)
			var base := sn
			if base.ends_with("_a") or base.ends_with("_b"):
				base = base.substr(0, base.length() - 2)
			keys[sn] = base
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
	_pending_shader = sh
	_pending_keys = keys
	_pending_pano = pano
	_pending_layers = layer_of
	return true


func _path_for(sn: String) -> String:
	var b: String = _pending_keys[sn]
	return _pending_pano if b == "tex" else str(_pending_layers.get(b, ""))


func _pending_paths() -> Array[String]:
	var out: Array[String] = []
	for sn in _pending_keys:
		var p := _path_for(sn)
		if p != "" and not out.has(p):
			out.append(p)
	return out


func _poll_loading() -> void:
	var done := true
	for p in _pending:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			done = false
		elif st != ResourceLoader.THREAD_LOAD_LOADED:
			_pending.clear()
			_text("Welt nicht installiert")
			return
	if not done:
		return
	var m := ShaderMaterial.new()
	m.shader = _pending_shader
	for sn in _pending_keys:
		var p := _path_for(sn)
		if p != "":
			m.set_shader_parameter(sn, ResourceLoader.load_threaded_get(p))
	m.set_shader_parameter("readability", 0.7)
	m.set_shader_parameter("star_speed", 0.0)
	m.set_shader_parameter("palette_mix", 0.0)
	_mat = m
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_pending.clear()
	_pending_shader = null
	_label.visible = false
	_live = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_set_beat(0, 0.0)
	_fade_to(1.0, FADE_IN)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not _pending.is_empty():
		_loading_t += delta
		_label.modulate.a = 0.55 + 0.35 * sin(_loading_t * 3.0)
		_poll_loading()
		return
	if not _live or _mat == null:
		set_process(false)
		return
	# Glatte, monotone Zeitbasis (Komfort-Regel 3): Frame-Delta begrenzt.
	_t += clampf(delta, 0.0, 0.05)
	var b := _t * BPM / 60.0
	_set_beat(int(floor(b)), fmod(b, 1.0))


## Beat-Uniforms nach docs/worlds/beat_contract.md (120 BPM, Takt 4, kein Kiai/Drop).
func _set_beat(beats: int, p: float) -> void:
	var meter := 4
	var beat_ms := 60000.0 / BPM
	var bar_phase := (float(beats % meter) + p) / float(meter)
	var pulse := exp(-p * beat_ms / 62.0)
	if beats % meter == 0:
		pulse = minf(pulse * 1.15, 1.0)
	# Glatte beat_step-Formel (Komfort-Regel 2): Tempo 0,75x..1,25x, nie still.
	var step := float(beats) + p + 0.25 * ((1.0 - (1.0 - p) * (1.0 - p)) - p)
	_mat.set_shader_parameter(&"beat_pulse", pulse)
	_mat.set_shader_parameter(&"beat_phase", p)
	_mat.set_shader_parameter(&"bar_phase", bar_phase)
	_mat.set_shader_parameter(&"beat_step", step)
	_mat.set_shader_parameter(&"downbeat_pulse", exp(-bar_phase * float(meter) * 3.0))
	_mat.set_shader_parameter(&"kiai", 0.0)
	_mat.set_shader_parameter(&"drop", 0.0)
	_mat.set_shader_parameter(&"energy", 0.5)
	_mat.set_shader_parameter(&"comfort", 1.0 if Settings.camera_mode == 0 else 0.0)
