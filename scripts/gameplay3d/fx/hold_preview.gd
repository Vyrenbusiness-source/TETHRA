extends Node3D
## Demo: Holds in allen 3 Zustaenden. --shot speichert einen Screenshot und beendet.

const ROAD_Y := -1.6
const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/hold_preview.png"
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]

var _beams: Array[HoldBeam] = []
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
	cam.position = Vector3(0, 1.78, 6.8)
	cam.rotation_degrees = Vector3(-15.2, 0, 0)
	cam.fov = 72.0
	cam.current = true
	add_child(cam)

	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(6.4, 60.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, -20.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.05, 0.06, 0.09)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road.material_override = rm
	add_child(road)

	# Spur 0 anfliegend, 1 und 2 gehalten (lang/kurz), 3 losgelassen.
	var states := [0, 1, 1, 2]
	var heads := [-24.0, -16.0, -9.0, -20.0]
	var tails := [-12.0, 3.0, 1.0, -4.0]
	for i in 4:
		var b := HoldBeam.new()
		add_child(b)
		b.setup(0.85)
		b.set_state(states[i])
		b.set_span(heads[i], tails[i], RAIL_X[i], ROAD_Y + 0.05)
		_beams.append(b)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	var env := 0.5 + 0.5 * sin(_t * 6.0)
	for b in _beams:
		b.set_beat(env)
	if OS.get_cmdline_args().has("--shot") and _frames == 40:
		var img := get_viewport().get_texture().get_image()
		img.save_png(SHOT_PATH)
		print("shot: ", SHOT_PATH)
		get_tree().quit(0)
