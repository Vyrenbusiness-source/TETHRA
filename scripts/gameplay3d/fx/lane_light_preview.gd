extends Node3D
## Demo: Spurlicht bei 128 BPM. Spur 0+2 gehalten, 1 kurz getippt, 3 aus.
## --shot speichert Screenshot und beendet; --shot-out=<png> Zielpfad.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const BPM := 128.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const COLS: Array[Color] = [Color(0.58, 0.76, 0.94), Color(0.95, 0.72, 0.38), Color(0.62, 0.9, 0.7), Color(0.9, 0.55, 0.8)]
const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/lane_light_preview.png"

var _ll: LaneLight
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
	rq.size = Vector2(7.2, 60.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, -20.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.05, 0.06, 0.09)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road.material_override = rm
	add_child(road)
	_ll = LaneLight.new()
	add_child(_ll)
	_ll.setup(RAIL_X, Z_LINE, Z_FAR, ROAD_Y, COLS)
	_ll.press(0)
	_ll.press(2)


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	var phase := fmod(_t * BPM / 60.0, 1.0)
	_ll.set_beat(pow(1.0 - phase, 2.0))
	# Spur 1: tippt alle 2 s fuer 0.5 s
	if fmod(_t, 2.0) < 0.5:
		_ll.press(1)
	else:
		_ll.release(1)
	_ll.update(delta)
	if OS.get_cmdline_args().has("--shot") and _frames == 40:
		var path := SHOT_PATH
		for a in OS.get_cmdline_args():
			if a.begins_with("--shot-out="):
				path = a.trim_prefix("--shot-out=")
		get_viewport().get_texture().get_image().save_png(path)
		print("shot: ", path)
		get_tree().quit(0)
