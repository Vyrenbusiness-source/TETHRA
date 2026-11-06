class_name HoldBeam
extends MeshInstance3D
## Hold-Koerper (Shader hold_beam.gdshader): deckend, scharfe Kanten, Endkappe.
## Lesbarkeit vor Glanz: keine Fluss-Animation, gehalten nur leicht heller,
## losgelassen klar grau. Pro Frame nur set_span(): Transform/Scale + Uniform
## length, keine Mesh-Neuerzeugung.

const STATE_APPROACH := 0
const STATE_HELD := 1
const STATE_RELEASED := 2

var _mat: ShaderMaterial
var _width := 0.8
var _state := 0
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
	# Vor den Noten zeichnen: der Kopf (Note in Hold-Farbe) liegt immer oben.
	_mat.render_priority = -1
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
			_set_look(1.12, 0.0)
		STATE_RELEASED:
			_set_look(0.85, 1.0)
		_:
			_set_look(1.0, 0.0)

func set_beat(beat_env: float) -> void:
	_mat.set_shader_parameter("beat", clampf(beat_env, 0.0, 1.0))

func _set_look(bright: float, desat: float) -> void:
	_mat.set_shader_parameter("brightness", bright)
	_mat.set_shader_parameter("desat", desat)
