extends Node3D
## Demo: Holds wie im Spiel (Kamera, Pads, Kopfring = note_disc in Hold-Farbe).
## Spur 0 anfliegend (mitten auf der Strecke), 1 gehalten (Kopf auf der Linie),
## 2 kurzer Hold kurz vor der Linie + normale Note dahinter, 3 losgelassen.
## --shot speichert einen Screenshot und beendet; --shot-out=<png> Zielpfad,
## --close: Nahaufnahme der Kopfpartie.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const NOTE_SIZE := 1.12
const NOTE_Y := 0.32
const BEAM_Y := 0.28
const PAD_Y := 0.30
const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/hold_preview.png"
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const HOLD_COL := Color(0.95, 0.72, 0.38)
const NOTE_COL := Color(0.58, 0.76, 0.94)
const PAD_COL := Color(0.62, 0.66, 0.78)

var _beams: Array[HoldBeam] = []
var _rims: Array[ShaderMaterial] = []
var _t := 0.0
var _frames := 0

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.05)
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	if OS.get_cmdline_args().has("--close"):
		cam.position = Vector3(-0.9, 0.9, 5.2)
		cam.rotation_degrees = Vector3(-32.0, 0, 0)
		cam.fov = 50.0
	else:
		cam.position = Vector3(0, 1.78, 6.8)
		cam.rotation_degrees = Vector3(-15.2, 0, 0)
		cam.fov = 72.0
	cam.current = true
	add_child(cam)

	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(7.2, 60.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, -20.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.05, 0.06, 0.09)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road.material_override = rm
	add_child(road)

	var disc_shader: Shader = load("res://shaders/note_disc.gdshader")
	for i in 4:
		_disc(disc_shader, Vector3(RAIL_X[i], ROAD_Y + PAD_Y, Z_LINE), PAD_COL, true, -1)

	# [Zustand, Kopf-z, Ende-z]
	var holds := [[0, -6.0, -18.0], [1, Z_LINE, -9.0], [0, 0.6, -2.4], [2, -7.0, -15.0]]
	for i in 4:
		var h: Array = holds[i]
		var b := HoldBeam.new()
		add_child(b)
		b.setup(0.92, HOLD_COL)
		b.set_state(int(h[0]))
		b.set_span(float(h[1]), float(h[2]), RAIL_X[i], ROAD_Y + BEAM_Y)
		_beams.append(b)
		if int(h[0]) != HoldBeam.STATE_RELEASED:
			_rims.append(_disc(disc_shader, Vector3(RAIL_X[i], ROAD_Y + NOTE_Y, float(h[1])),
					HOLD_COL, false, 0))
	# Normale Note zum Vergleich (gleicher Ring, Notenfarbe).
	_rims.append(_disc(disc_shader, Vector3(RAIL_X[2], ROAD_Y + NOTE_Y, -5.0), NOTE_COL, false, 0))

func _disc(sh: Shader, pos: Vector3, col: Color, pad: bool, prio: int) -> ShaderMaterial:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(NOTE_SIZE, NOTE_SIZE)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", col)
	m.set_shader_parameter("rim_color", col * (0.85 if pad else 1.15))
	m.set_shader_parameter("fill_alpha", 0.0 if pad else 0.22)
	m.set_shader_parameter("halo_strength", 0.7)
	m.set_shader_parameter("rim_boost", 0.0 if pad else 0.3)
	m.render_priority = prio
	mi.material_override = m
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = pos
	add_child(mi)
	return m

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	var env := 0.5 + 0.5 * sin(_t * 6.0)
	for b in _beams:
		b.set_beat(env)
	if OS.get_cmdline_args().has("--shot") and _frames == 40:
		var path := SHOT_PATH
		for a in OS.get_cmdline_args():
			if a.begins_with("--shot-out="):
				path = a.trim_prefix("--shot-out=")
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("shot: ", path)
		get_tree().quit(0)
