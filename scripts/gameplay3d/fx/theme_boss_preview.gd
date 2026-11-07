extends Node3D
## Demo: Welt-Thema "Bosskampf" (shaders/theme_boss.gdshader) mit Komfort-Kamera,
## monochrom blutroter Strecke (Farbsatz aus dem Shader-Kopf) und Pads.
## Ohne Argumente: 140 BPM, Beat-Puls, Blitz auf jedem 2. Downbeat (4/4),
## Gruppe wechselt reihum. Tasten: 1-3 Blitz in Gruppe, Leertaste Blitz auto.
##   --pulse=<0..1>  --rise=<Zyklen/s>
##   --shot [--shot-dir=<ordner>]  speichert boss_calm.png, boss_flash0..2.png,
##        boss_pulse.png, boss_up.png (Blick nach oben), boss_back.png, dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/2690cab5-bd8f-418e-ba0f-9da78692e0cd/scratchpad/bossshot"
const BPM := 140.0
const DIR := "res://assets_game/themes/boss/"

# Farbsatz (siehe shaders/theme_boss.gdshader, FARBSATZ).
const C_ROAD := Color("#070203")
const C_LANE := Color("#3a0609")
const C_EDGE := Color("#8c0610")
const C_LINE := Color("#c01a1e")
const C_PAD_FILL := Color("#2a0507")
const C_NOTE := Color("#e8d4d4")

var _mat: ShaderMaterial
var _cam: Camera3D
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _flash := 0.0
var _cell := 0
var _last_beat := -1

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_boss.gdshader")
	_mat.set_shader_parameter("tex_a", load(DIR + "sky_boss.webp"))
	_mat.set_shader_parameter("stars_a", load(DIR + "sky_boss_embers.webp"))
	_mat.set_shader_parameter("flash_tex", load(DIR + "sky_boss_flash.webp"))
	_mat.set_shader_parameter("readability", 0.7)
	_mat.set_shader_parameter("ember_rise", 0.0 if _shot else _arg_f("--rise=", 0.12))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#140405")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2.1, 7.6)
	_cam.rotation_degrees = Vector3(-16, 0, 0)
	_cam.fov = 62.0
	_cam.current = true
	add_child(_cam)

	var road := _quad(Vector2(7.2, 60.0), Vector3(0, ROAD_Y - 0.01, -20.0), Color(C_ROAD, 0.92))
	add_child(road)
	for x in [-3.4, 3.4]:
		add_child(_quad(Vector2(0.06, 60.0), Vector3(x, ROAD_Y, -20.0), C_EDGE * 1.3))
	for x in [-1.7, 0.0, 1.7]:
		add_child(_quad(Vector2(0.035, 60.0), Vector3(x, ROAD_Y, -20.0), Color(C_LANE, 0.55)))
	var line := _quad(Vector2(7.2, 0.07), Vector3(0, ROAD_Y + 0.005, Z_LINE), C_LINE * 1.6)
	add_child(line)
	var disc_shader: Shader = load("res://shaders/note_disc.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(1.12, 1.12)
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(RAIL_X[i], ROAD_Y + 0.3, Z_LINE)
		var m := ShaderMaterial.new()
		m.shader = disc_shader
		m.set_shader_parameter("base_color", C_EDGE)
		m.set_shader_parameter("fill_alpha", 0.25)
		mi.material_override = m
		add_child(mi)
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[(i * 3 + 1) % 4], ROAD_Y + 0.32, -3.0 - 6.0 * i)
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", C_NOTE)
		n.material_override = nm
		add_child(n)

func _quad(size: Vector2, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	return mi

func _arg_f(prefix: String, def: float) -> float:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return float(a.trim_prefix(prefix))
	return def

func _strike(cell: int) -> void:
	_mat.set_shader_parameter("lightning_cell", cell)
	_flash = 1.0

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode >= KEY_1 and ev.keycode <= KEY_3:
			_strike(ev.keycode - KEY_1)
		elif ev.keycode == KEY_SPACE:
			_strike(-1)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _shot:
		_shot_step()
		return
	var beat_f := _t * BPM / 60.0
	var beat := int(beat_f)
	var pulse := pow(1.0 - fmod(beat_f, 1.0), 4.0) * _arg_f("--pulse=", 0.5)
	_mat.set_shader_parameter("beat_pulse", pulse)
	# Blitz auf jedem 2. Downbeat (alle 8 Schlaege), Gruppe reihum.
	if beat != _last_beat:
		_last_beat = beat
		if beat % 8 == 0:
			_strike(_cell)
			_cell = (_cell + 1) % 3
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_mat.set_shader_parameter("lightning", _flash)

## --shot: je 14 Frames Einschwingen (Sky inkrementell), dann speichern.
func _shot_step() -> void:
	if _frames % 14 != 0:
		return
	match _step:
		0:
			_mat.set_shader_parameter("lightning", 0.0)
		1:
			_save("boss_calm.png")
			_mat.set_shader_parameter("lightning_cell", 0)
			_mat.set_shader_parameter("lightning", 1.0)
		2:
			_save("boss_flash0.png")
			_mat.set_shader_parameter("lightning_cell", 1)
		3:
			_save("boss_flash1.png")
			_mat.set_shader_parameter("lightning_cell", 2)
		4:
			_save("boss_flash2.png")
			_mat.set_shader_parameter("lightning", 0.0)
			_mat.set_shader_parameter("beat_pulse", 1.0)
		5:
			_save("boss_pulse.png")
			_mat.set_shader_parameter("beat_pulse", 0.0)
			_mat.set_shader_parameter("lightning_cell", 0)
			_mat.set_shader_parameter("lightning", 0.8)
			_cam.rotation_degrees = Vector3(14, 0, 0)
			_cam.fov = 80.0
		6:
			_save("boss_up.png")
			_mat.set_shader_parameter("lightning_cell", 2)
			_cam.rotation_degrees = Vector3(8, 180, 0)
		7:
			_save("boss_back.png")
			get_tree().quit(0)
	_step += 1

func _save(file: String) -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(file)
	img.save_png(path)
	print("shot: ", path)
