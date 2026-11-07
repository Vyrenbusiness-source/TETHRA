extends Node3D
## Demo: Welt-Thema "Neon" (shaders/theme_neon.gdshader + neon_sky.webp) mit
## Komfort-Kamera, dunkler Strecke im Neon-Farbsatz, Pads und Noten zur
## Lesbarkeits-Kontrolle.
## Ohne Argumente: 174 BPM Beat-Welle, Gitter stroemt zum Spieler.
##   --bpm=<n> --speed=<Zellen/s> --warp=<0..1>
##   --shot [--shot-dir=<ordner>]  speichert neon_still / neon_beat_far /
##        neon_beat_near / neon_warp / neon_side (Blick 70 Grad seitlich) als
##        PNG, dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/2690cab5-bd8f-418e-ba0f-9da78692e0cd/scratchpad/neon"

# Farbsatz (siehe Kommentarblock in theme_neon.gdshader).
const C_ROAD := Color("#0a0614")
const C_LANE := Color("#3b2a6e")
const C_EDGE := Color("#ff2bd6")
const C_PAD := Color("#19f0ff")
const C_NOTE_A := Color("#6ff7ff")
const C_NOTE_B := Color("#ff5ae0")

var _mat: ShaderMaterial
var _cam: Camera3D
var _edge_mats: Array[StandardMaterial3D] = []
var _note_mats: Array[ShaderMaterial] = []
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _bpm := 174.0

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	_bpm = _arg_f("--bpm=", 174.0)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_neon.gdshader")
	_mat.set_shader_parameter("tex_a", load("res://assets_game/themes/neon/neon_sky.webp"))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1a0d2e")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Glow wie im Spiel (mania_3d.gd).
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	# Komfort-Kamera (mania_3d Default).
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2.1, 7.6)
	_cam.rotation_degrees = Vector3(-16, 0, 0)
	_cam.fov = 62.0
	_cam.current = true
	add_child(_cam)

	var zmid := (Z_FAR + Z_LINE) * 0.5
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(8.4, absf(Z_FAR) + 6.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, zmid)
	road.material_override = _unshaded(Color(C_ROAD, 0.92))
	add_child(road)
	for x in [-1.7, 0.0, 1.7]:
		var ln := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.035, absf(Z_FAR) + 6.0)
		ln.mesh = lq
		ln.rotation_degrees = Vector3(-90, 0, 0)
		ln.position = Vector3(x, ROAD_Y, zmid)
		ln.material_override = _unshaded(Color(C_LANE, 0.5))
		add_child(ln)
	for sx in [-3.6, 3.6]:
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.10, 0.03, absf(Z_FAR) + 8.0)
		edge.mesh = eb
		edge.position = Vector3(sx, ROAD_Y, zmid + 2.0)
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.02, 0.02, 0.03)
		em.emission_enabled = true
		em.emission = C_EDGE
		em.emission_energy_multiplier = 0.7
		_edge_mats.append(em)
		edge.material_override = em
		add_child(edge)

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
		m.set_shader_parameter("base_color", C_PAD)
		m.set_shader_parameter("fill_alpha", 0.22)
		mi.material_override = m
		add_child(mi)
	# Anfliegende Noten bis zum Spawn-Horizont (Lesbarkeit vor Sonne/Skyline).
	for j in 8:
		var col := (j * 3 + 1) % 4
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[col], ROAD_Y + 0.32, -2.0 - 5.6 * j)
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", C_NOTE_A if col == 1 or col == 2 else C_NOTE_B)
		n.material_override = nm
		_note_mats.append(nm)
		add_child(n)

	if not _shot:
		_mat.set_shader_parameter("star_speed", _arg_f("--speed=", 1.6))
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

func _set_pulse(p: float) -> void:
	_mat.set_shader_parameter("beat_pulse", p)
	for em in _edge_mats:
		em.emission = C_EDGE.lerp(Color("#ff7ae8"), p)
		em.emission_energy_multiplier = 0.7 + 0.9 * p
	for nm in _note_mats:
		nm.set_shader_parameter("beat", p)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _shot:
		_shot_step()
		return
	var beat := _t * _bpm / 60.0
	_set_pulse(pow(1.0 - fmod(beat, 1.0), 4.0))

## Schritt-Folge fuer --shot: je 12 Frames Einschwingen, dann speichern.
func _shot_step() -> void:
	if _frames % 12 != 0:
		return
	match _step:
		0:
			_set_pulse(0.0)
		1:
			_save("neon_still.png")
			_set_pulse(0.85)
		2:
			_save("neon_beat_far.png")
			_set_pulse(0.06)
		3:
			_save("neon_beat_near.png")
			_set_pulse(0.35)
			_mat.set_shader_parameter("star_phase", 0.45)
			_mat.set_shader_parameter("warp", 0.8)
		4:
			_save("neon_warp.png")
			_mat.set_shader_parameter("warp", 0.0)
			_mat.set_shader_parameter("star_phase", 0.0)
			_set_pulse(0.5)
			_cam.rotation_degrees = Vector3(-8, 70, 0)
		5:
			_save("neon_side.png")
			get_tree().quit(0)
	_step += 1

func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path := _shot_dir.path_join(file)
	img.save_png(path)
	print("shot: ", path)
