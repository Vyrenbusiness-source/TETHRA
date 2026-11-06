class_name HoldBeam
extends MeshInstance3D
## Hold-Koerper (Shader hold_beam.gdshader) im VSRG-Skin-Stil: Kopf = normaler
## Notenring in Hold-Farbe (zeichnet der Aufrufer), der Strahl beginnt sauber
## UNTER/HINTER dem Ring (Kreis-Ausschnitt im Ringband), Breite ~0.62 x
## Ringdurchmesser, runde Endkappe. Gehalten bleibt der Kopf auf der Linie und
## der Strahl wird vom Ring "eingesaugt" (Ausschnitt schneidet ihn dort ab).
## Losgelassen: kein Kopfring mehr -> runde Kappe vorne, klar grau.
## Pro Frame nur set_span(): Transform/Scale + Uniforms, kein neues Mesh.

const STATE_APPROACH := 0
const STATE_HELD := 1
const STATE_RELEASED := 2

## Notenring (note_disc.gdshader): Quad NOTE_SIZE, Ring 0.70..0.93 des Radius.
const RING_INNER := 0.70
const RING_OUTER := 0.93
const BODY_OF_RING := 0.62   # Koerperbreite relativ zum Ringdurchmesser
const CONTOUR := 0.035       # dunkle Aussenkontur (wie im Shader)

var _mat: ShaderMaterial
var _width := 0.8
var _body_w := 0.65
var _cut := 0.46
var _state := 0
var _last_len := -1.0
var _last_sign := 0.0

## width: Breite des Quads (mind. Koerper + Kontur). ring_size: Quad-Groesse
## des Kopfrings (NOTE_SIZE), head_dy: wie viel hoeher der Ring liegt.
func setup(width: float, color: Color = Color(1.0, 0.62, 0.22),
		ring_size: float = 1.12, head_dy: float = 0.04) -> void:
	var ring_r := ring_size * 0.5
	_body_w = BODY_OF_RING * ring_r * RING_OUTER * 2.0
	_width = maxf(width, _body_w + CONTOUR * 2.0 + 0.02)
	# Ausschnitt mitten im deckenden Ringband: Kante liegt immer unter dem Ring.
	_cut = ring_r * (RING_INNER + RING_OUTER) * 0.5
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/hold_beam.gdshader")
	_mat.set_shader_parameter("beam_color", color)
	_mat.set_shader_parameter("width", _width)
	_mat.set_shader_parameter("body_w", _body_w)
	_mat.set_shader_parameter("head_dy", head_dy)
	# Vor den Noten zeichnen: der Kopf (Note in Hold-Farbe) liegt immer oben.
	_mat.render_priority = -1
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_state(STATE_APPROACH)

## z_head: Kopfmitte (= Ringmitte, an der Linie solange gehalten),
## z_tail: Ende des Holds. Das Quad reicht von der Kopfmitte bis knapp hinter
## das Ende (Platz fuer die Kontur der Endkappe).
func set_span(z_head: float, z_tail: float, x: float, y: float) -> void:
	var sgn := 1.0 if z_head >= z_tail else -1.0
	var len := maxf(absf(z_head - z_tail), 0.001)
	var qlen := len + CONTOUR + 0.02
	position = Vector3(x, y, z_head - sgn * qlen * 0.5)
	scale = Vector3(_width, 1.0, qlen)
	if absf(len - _last_len) > 0.0005:
		_last_len = len
		_mat.set_shader_parameter("length_u", len)
		_mat.set_shader_parameter("quad_len", qlen)
	if sgn != _last_sign:
		_last_sign = sgn
		_mat.set_shader_parameter("head_sign", sgn)

func set_state(state: int) -> void:
	_state = state
	match state:
		STATE_HELD:
			_set_look(1.12, 0.0, _cut, 0.42)
		STATE_RELEASED:
			# Kein Kopfring mehr: Ausschnitt aus, vorne runde Kappe.
			_set_look(0.85, 1.0, 0.0, 0.0)
		_:
			_set_look(1.0, 0.0, _cut, 0.18)

func set_beat(beat_env: float) -> void:
	_mat.set_shader_parameter("beat", clampf(beat_env, 0.0, 1.0))

func _set_look(bright: float, desat: float, cut: float, glow: float) -> void:
	_mat.set_shader_parameter("brightness", bright)
	_mat.set_shader_parameter("desat", desat)
	_mat.set_shader_parameter("cut_radius", cut)
	_mat.set_shader_parameter("head_glow", glow)
