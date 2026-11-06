extends Node3D
## Demo: alle 4 Spuren im 150-BPM-Takt. --shot speichert ein Bild und beendet.

const Z_LINE := 3.0
const ROAD_Y := -1.6
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/sparks_preview.png"

var _sparks: HitSparks
var _t := 0.0
var _beat := -1
var _shot := false
var _shot_done := false


func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _ready() -> void:
	_shot = "--shot" in OS.get_cmdline_args() or "shot" in OS.get_cmdline_args()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.06)
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.78, 6.8)
	cam.rotation_degrees = Vector3(-15.2, 0, 0)
	cam.fov = 72.0
	cam.current = true
	add_child(cam)
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(7.4, 50.0)
	road.mesh = rq
	road.material_override = _unlit(Color(0.05, 0.06, 0.09))
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, Z_LINE - 22.0)
	add_child(road)
	for x in RAIL_X:
		var pad := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(1.4, 0.3)
		pad.mesh = pq
		pad.material_override = _unlit(Color(0.3, 0.32, 0.38))
		pad.rotation_degrees = Vector3(-90, 0, 0)
		pad.position = Vector3(x, ROAD_Y + 0.02, Z_LINE)
		add_child(pad)
	_sparks = HitSparks.new()
	add_child(_sparks)
	_sparks.setup(RAIL_X, Z_LINE, ROAD_Y, Color(0.45, 0.85, 1.0))


func _process(delta: float) -> void:
	_t += delta
	var period := 60.0 / 150.0
	var b := int(_t / period)
	if b != _beat:
		_beat = b
		var col := b % 4
		_sparks.spark(col, 0 if b % 8 < 4 else 1)
		_sparks.lane_shot(col)
		if b % 2 == 1:
			_sparks.spark((col + 2) % 4, 3)
	_sparks.update(delta)
	if _shot and not _shot_done and _beat >= 3 and fmod(_t, period) > 0.08:
		_shot_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(SHOT_PATH.get_base_dir())
		img.save_png(SHOT_PATH)
		get_tree().quit()
