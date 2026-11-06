extends Node3D
## Demo: Premium-Himmel (shaders/sky_panorama.gdshader) mit Mania-Kamera,
## dunkler Strecke und Pads zur Lesbarkeits-Kontrolle.
## Ohne Argumente: Paletten wechseln alle 4 s (Taste 1-4 direkt), Sterne fliegen.
##   --palette=<violet|azure|ember|emerald>  feste Palette
##   --warp=<0..1> --speed=<Zyklen/s> --pulse=<0..1>
##   --shot [--shot-dir=<ordner>]  speichert sky_<palette>.png fuer alle 4
##        Paletten + sky_warp.png (Flug + Streckung) + sky_mix.png
##        (Ueberblendung violet->azure mit Beat-Puls), dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const PALETTES: Array[String] = ["violet", "azure", "ember", "emerald"]
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/2690cab5-bd8f-418e-ba0f-9da78692e0cd/scratchpad/sky"

var _mat: ShaderMaterial
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _fixed := ""
var _cur := 0
var _step := 0
var _pulse := 0.0

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--palette="):
			_fixed = a.trim_prefix("--palette=")

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/sky_panorama.gdshader")
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.1, 0.12)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Glow wie im Spiel (mania_3d.gd).
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.78, 6.8)
	cam.rotation_degrees = Vector3(-15.2, 0, 0)
	cam.fov = 72.0
	cam.current = true
	add_child(cam)

	# Strecke + Spurlinien + Pads (nur zur Lesbarkeits-Kontrolle).
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(7.2, 60.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, -20.0)
	road.material_override = _unshaded(Color(0.03, 0.035, 0.055, 0.9))
	add_child(road)
	for x in [-3.4, -1.7, 0.0, 1.7, 3.4]:
		var ln := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.04, 60.0)
		ln.mesh = lq
		ln.rotation_degrees = Vector3(-90, 0, 0)
		ln.position = Vector3(x, ROAD_Y, -20.0)
		ln.material_override = _unshaded(Color(0.35, 0.45, 0.7, 0.5))
		add_child(ln)
	var disc_shader: Shader = load("res://shaders/note_disc.gdshader")
	for i in 4:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.12, 1.12)
		mi.mesh = q
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(RAIL_X[i], ROAD_Y + 0.3, Z_LINE)
		var m := ShaderMaterial.new()
		m.shader = disc_shader
		m.set_shader_parameter("base_color", Color(0.62, 0.66, 0.78))
		m.set_shader_parameter("fill_alpha", 0.25)
		mi.material_override = m
		add_child(mi)
		# Anfliegende Noten auf verschiedenen Spuren.
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[(i * 3 + 1) % 4], ROAD_Y + 0.32, -3.0 - 6.0 * i)
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", Color(0.58, 0.76, 0.94))
		n.material_override = nm
		add_child(n)

	_cur = maxi(0, PALETTES.find(_fixed))
	_apply(PALETTES[_cur])
	if not _shot:
		_mat.set_shader_parameter("star_speed", _arg_f("--speed=", 0.08))
		_mat.set_shader_parameter("warp", _arg_f("--warp=", 0.0))

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _arg_f(prefix: String, def: float) -> float:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return float(a.trim_prefix(prefix))
	return def

func _tex(name: String) -> Texture2D:
	return load("res://assets_game/space/sky_%s.webp" % name)

func _stars(name: String) -> Texture2D:
	return load("res://assets_game/space/sky_%s_stars.webp" % name)

func _apply(name: String) -> void:
	_mat.set_shader_parameter("tex_a", _tex(name))
	_mat.set_shader_parameter("stars_a", _stars(name))
	_mat.set_shader_parameter("palette_mix", 0.0)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		var k: int = ev.keycode - KEY_1
		if k >= 0 and k < PALETTES.size():
			_cur = k
			_fixed = PALETTES[k]
			_apply(_fixed)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _shot:
		_shot_step()
		return
	# Beat-Puls (120 BPM), schnell abklingend.
	_pulse = pow(1.0 - fmod(_t * 2.0, 1.0), 4.0) * _arg_f("--pulse=", 0.6)
	_mat.set_shader_parameter("beat_pulse", _pulse)
	if _fixed == "" and int(_t / 4.0) % PALETTES.size() != _cur:
		_cur = int(_t / 4.0) % PALETTES.size()
		_apply(PALETTES[_cur])

## Schritt-Folge fuer --shot: je 12 Frames Einschwingen, dann speichern.
func _shot_step() -> void:
	if _frames % 12 != 0:
		return
	var n := PALETTES.size()
	if _step < n:
		if _step > 0:
			_save("sky_%s.png" % PALETTES[_step - 1])
		_apply(PALETTES[_step])
	elif _step == n:
		_save("sky_%s.png" % PALETTES[n - 1])
		_apply("violet")
		_mat.set_shader_parameter("star_phase", 0.3)
		_mat.set_shader_parameter("warp", 0.7)
	elif _step == n + 1:
		_save("sky_warp.png")
		_mat.set_shader_parameter("warp", 0.0)
		_mat.set_shader_parameter("star_phase", 0.0)
		_mat.set_shader_parameter("tex_b", _tex("azure"))
		_mat.set_shader_parameter("stars_b", _stars("azure"))
		_mat.set_shader_parameter("palette_mix", 0.5)
		_mat.set_shader_parameter("beat_pulse", 1.0)
	else:
		_save("sky_mix.png")
		get_tree().quit(0)
	_step += 1

func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file)
	img.save_png(path)
	print("shot: ", path)
