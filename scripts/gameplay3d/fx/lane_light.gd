class_name LaneLight
extends Node3D
## Spurlicht fuer gedrueckte Tasten / gehaltene Holds. Dezenter Streifen von
## der Abfanglinie nach hinten in Spurfarbe, pulsiert im Takt (set_beat),
## 120 ms Fade beim Loslassen. Alpha max 0.18 (Noten bleiben heller).

const FADE_IN := 0.04
const FADE_OUT := 0.12
const LANE_W := 1.0
const Y_LIFT := 0.012

var _mats: Array[ShaderMaterial] = []
var _held: Array[bool] = []
var _level: Array[float] = []


func setup(rail_x: Array[float], z_line: float, z_far: float, road_y: float, colors: Array[Color]) -> void:
	for c in get_children():
		c.queue_free()
	_mats.clear()
	_held.clear()
	_level.clear()
	var sh: Shader = load("res://shaders/lane_light.gdshader")
	var len := absf(z_far - z_line)
	for i in rail_x.size():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(LANE_W, len)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("lane_color", colors[i] if i < colors.size() else Color.WHITE)
		m.set_shader_parameter("intensity", 0.0)
		mi.material_override = m
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(rail_x[i], road_y + Y_LIFT, (z_line + z_far) * 0.5)
		mi.visible = false
		add_child(mi)
		_mats.append(m)
		_held.append(false)
		_level.append(0.0)


func press(column: int) -> void:
	if column >= 0 and column < _held.size():
		_held[column] = true


func release(column: int) -> void:
	if column >= 0 and column < _held.size():
		_held[column] = false


func set_beat(env: float) -> void:
	for m in _mats:
		m.set_shader_parameter("beat", clampf(env, 0.0, 1.0))


func update(delta: float) -> void:
	for i in _mats.size():
		var target := 1.0 if _held[i] else 0.0
		var rate := (1.0 / FADE_IN) if _held[i] else (1.0 / FADE_OUT)
		_level[i] = move_toward(_level[i], target, rate * delta)
		_mats[i].set_shader_parameter("intensity", _level[i])
		get_child(i).visible = _level[i] > 0.001
