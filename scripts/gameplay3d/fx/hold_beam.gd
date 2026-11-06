class_name HoldBeam
extends MeshInstance3D
## Hold-Koerper als leuchtender Energiestrahl (Shader hold_beam.gdshader).
## Pro Frame nur set_span(): Transform/Scale + Uniform length, keine Mesh-Neuerzeugung.

const STATE_APPROACH := 0
const STATE_HELD := 1
const STATE_RELEASED := 2

var _mat: ShaderMaterial
var _width := 0.8
var _state := 0
var _flow_speed := 0.8
var _flow_pos := 0.0
var _last_len := -1.0

func setup(width: float, color: Color = Color(1.0, 0.62, 0.22)) -> void:
	_width = width
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/hold_beam.gdshader")
	_mat.set_shader_parameter("beam_color", color)
	_mat.set_shader_parameter("width", width)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_state(STATE_APPROACH)

## z_head: fernes Ende (kleineres z), z_tail: nahes Ende.
func set_span(z_head: float, z_tail: float, x: float, y: float) -> void:
	var z0 := minf(z_head, z_tail)
	var z1 := maxf(z_head, z_tail)
	var len := maxf(z1 - z0, _width)
	position = Vector3(x, y, (z0 + z1) * 0.5)
	scale = Vector3(_width, 1.0, len)
	if absf(len - _last_len) > 0.0005:
		_last_len = len
		_mat.set_shader_parameter("length_u", len)

func set_state(state: int) -> void:
	_state = state
	match state:
		STATE_HELD:
			_set_look(1.15, 0.0, 0.18, 2.6)
		STATE_RELEASED:
			_set_look(0.22, 1.0, 0.0, 0.25)
		_:
			_set_look(0.6, 0.0, 0.0, 0.9)

func set_beat(beat_env: float) -> void:
	_mat.set_shader_parameter("beat", clampf(beat_env, 0.0, 1.0))

func _set_look(bright: float, desat: float, pulse: float, flow: float) -> void:
	_flow_speed = flow
	_mat.set_shader_parameter("brightness", bright)
	_mat.set_shader_parameter("desat", desat)
	_mat.set_shader_parameter("pulse", pulse)

func _process(delta: float) -> void:
	_flow_pos += _flow_speed * delta
	_mat.set_shader_parameter("flow_pos", _flow_pos)
