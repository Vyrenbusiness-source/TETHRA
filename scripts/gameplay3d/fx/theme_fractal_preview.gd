extends Node3D
## Demo: Welt-Thema "Fraktal" (shaders/theme_fractal.gdshader + fractal_sky.webp
## + fractal_sky_shards.webp) mit Komfort-Kamera, Obsidian-Strecke im
## Karmin-Farbsatz, Pads und Noten zur Lesbarkeits-Kontrolle.
## Ohne Argumente: 150 BPM Bruch-Welle, Splitter kreisen langsam.
##   --bpm=<n> --speed=<Phase/s> --warp=<0..1>
##   --shot [--shot-dir=<ordner>]  speichert fractal_still / fractal_beat_hit /
##        fractal_beat_mid / fractal_beat_late / fractal_warp / fractal_drift /
##        fractal_side (Blick 70 Grad seitlich) als PNG, dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "user://theme_fractal_shots"

# Farbsatz (siehe Kommentarblock in theme_fractal.gdshader).
const C_ROAD := Color("#050304")
const C_LANE := Color("#2a1a1e")
const C_EDGE := Color("#a3142f")
const C_EDGE_HOT := Color("#d8455c")
const C_PAD := Color("#b5223c")
const C_NOTE_A := Color("#e6e2e4")
const C_NOTE_B := Color("#c42a45")

var _mat: ShaderMaterial
var _cam: Camera3D
var _edge_mats: Array[StandardMaterial3D] = []
var _note_mats: Array[ShaderMaterial] = []
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _bpm := 150.0

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	_bpm = _arg_f("--bpm=", 150.0)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_fractal.gdshader")
	_mat.set_shader_parameter("tex_a", load("res://assets_game/themes/fractal/fractal_sky.webp"))
	_mat.set_shader_parameter("shards_a", load("res://assets_game/themes/fractal/fractal_sky_shards.webp"))
	_mat.set_shader_parameter("readability", 0.7)
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#0a0507")
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
	road.material_override = _unshaded(Color(C_ROAD, 0.94))
	add_child(road)
	for x in [-1.7, 0.0, 1.7]:
		var ln := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.035, absf(Z_FAR) + 6.0)
		ln.mesh = lq
		ln.rotation_degrees = Vector3(-90, 0, 0)
		ln.position = Vector3(x, ROAD_Y, zmid)
		ln.material_override = _unshaded(Color(C_LANE, 0.55))
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
		em.emission_energy_multiplier = 0.75
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
		m.set_shader_parameter("fill_alpha", 0.16)
		mi.material_override = m
		add_child(mi)
	# Anfliegende Noten bis zum Spawn-Horizont (Lesbarkeit vor den Splittern).
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

func _set_pulse(p: float) -> void:
	_mat.set_shader_parameter("beat_pulse", p)
	for em in _edge_mats:
		em.emission = C_EDGE.lerp(C_EDGE_HOT, p)
		em.emission_energy_multiplier = 0.75 + 0.85 * p
	for nm in _note_mats:
		nm.set_shader_parameter("beat", p)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _shot:
		_shot_step()
		return
	var beat := _t * _bpm / 60.0
	# Wie mania_3d._world_pulse: steiler Anstieg, ~180 ms Abfall.
	_set_pulse(exp(-fmod(beat, 1.0) * 60.0 / _bpm * 1000.0 / 180.0))

## Schritt-Folge fuer --shot: je 12 Frames Einschwingen, dann speichern.
func _shot_step() -> void:
	if _frames % 12 != 0:
		return
	match _step:
		0:
			_set_pulse(0.0)
		1:
			_save("fractal_still.png")
			_set_pulse(0.92)
		2:
			_save("fractal_beat_hit.png")
			_set_pulse(0.5)
		3:
			_save("fractal_beat_mid.png")
			_set_pulse(0.18)
		4:
			_save("fractal_beat_late.png")
			_set_pulse(0.3)
			_mat.set_shader_parameter("warp", 0.8)
		5:
			_save("fractal_warp.png")
			_mat.set_shader_parameter("warp", 0.0)
			_set_pulse(0.0)
			_mat.set_shader_parameter("star_phase", 1.2)
		6:
			_save("fractal_drift.png")
			_mat.set_shader_parameter("star_phase", 0.0)
			_set_pulse(0.5)
			_cam.rotation_degrees = Vector3(-8, 70, 0)
		7:
			_save("fractal_side.png")
			_set_pulse(0.0)
			_cam.rotation_degrees = Vector3(-8, 180, 0)
		8:
			_save("fractal_back.png")
			get_tree().quit(0)
	_step += 1

func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path := _shot_dir.path_join(file)
	img.save_png(path)
	print("shot: ", path)
