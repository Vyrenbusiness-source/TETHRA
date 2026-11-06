class_name HitSparks
extends Node3D
## Treffer-Funken an der Abfanglinie. Alles vorab gepoolt (MultiMesh + feste
## Mesh-Instanzen), keine Allokation pro Treffer. Additiv, Helligkeit gedeckelt.
## LESBARKEIT: Funken bleiben klein, kurz und flach an/unterhalb der Linie
## (nach aussen + zur Kamera, kaum nach oben, nie Richtung -z), der Ring-Puls
## zeichnet nur die kameraseitige Haelfte -> nie ueber anfliegenden Noten.

const SPARK_POOL := 96
const BRIGHT_CAP := 0.75     # Obergrenze Helligkeit (grell tut weh)
const LANE_TIME := 0.25
const RING_TIME := 0.18
const LANE_LEN := 22.0

const RING_CODE := "
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(0.6, 0.9, 1.0);
uniform float t = 1.0;
uniform float strength = 0.6;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float r = mix(0.22, 0.62, 1.0 - pow(1.0 - t, 2.0));
	float aa = max(fwidth(d), 0.001);
	float ring = 1.0 - smoothstep(0.02, 0.02 + aa * 1.5, abs(d - r));
	// UV.y >= 0.5 = Kamera-Seite der Linie (Quad um -90 Grad gedreht).
	float near_side = smoothstep(0.49, 0.53, UV.y);
	float a = ring * near_side * (1.0 - t) * (1.0 - t) * strength;
	ALBEDO = col * a;
	ALPHA = 1.0;
}
"

const LANE_CODE := "
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(0.6, 0.9, 1.0);
uniform float t = 1.0;
uniform float strength = 0.5;
void fragment() {
	// UV.y: 1 = Abfanglinie (nach Rotation unten am Quad), 0 = Horizont.
	float head = 1.0 - pow(t, 0.7);
	float behind = UV.y - head;
	float tail = smoothstep(0.0, 0.25, behind) * smoothstep(0.45, 0.25, behind);
	float front = smoothstep(0.03, 0.0, abs(behind));
	float across = smoothstep(1.0, 0.2, abs(UV.x * 2.0 - 1.0));
	float fade = (1.0 - t) * (0.3 + 0.7 * UV.y);
	float a = (tail * 0.35 + front) * across * fade * strength;
	ALBEDO = col * a;
	ALPHA = 1.0;
}
"

var _rail_x: Array[float] = []
var _z_line := 0.0
var _road_y := 0.0
var _theme := Color(0.55, 0.85, 1.0)

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _life0 := PackedFloat32Array()
var _size := PackedFloat32Array()
var _tint := PackedColorArray()
var _cursor := 0

var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _ring_t := PackedFloat32Array()
var _lanes: Array[MeshInstance3D] = []
var _lane_mats: Array[ShaderMaterial] = []
var _lane_t := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _ready_ok := false


func setup(rail_x: Array[float], z_line: float, road_y: float, theme: Color) -> void:
	_rail_x = rail_x
	_z_line = z_line
	_road_y = road_y
	_theme = theme
	_rng.seed = 7
	_build()
	_ready_ok = true


func _lighten(c: Color, k: float) -> Color:
	return c.lerp(Color(1, 1, 1), k)


func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _hide_spark(i: int) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_mm.set_instance_color(i, Color(0, 0, 0, 0))


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/spark.gdshader")
	mat.set_shader_parameter("max_bright", BRIGHT_CAP)
	quad.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = SPARK_POOL
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 10.0
	add_child(_mmi)
	_pos.resize(SPARK_POOL)
	_vel.resize(SPARK_POOL)
	_life.resize(SPARK_POOL)
	_life0.resize(SPARK_POOL)
	_size.resize(SPARK_POOL)
	_tint.resize(SPARK_POOL)
	for i in SPARK_POOL:
		_life[i] = 0.0
		_life0[i] = 1.0
		_hide_spark(i)

	var ring_shader := Shader.new()
	ring_shader.code = RING_CODE
	var lane_shader := Shader.new()
	lane_shader.code = LANE_CODE
	var n := _rail_x.size()
	_ring_t.resize(n)
	_lane_t.resize(n)
	_rings.clear()
	_ring_mats.clear()
	_lanes.clear()
	_lane_mats.clear()
	for i in n:
		_ring_t[i] = 1.0
		_lane_t[i] = 1.0
		var rm := ShaderMaterial.new()
		rm.shader = ring_shader
		var rq := QuadMesh.new()
		rq.size = Vector2(1.5, 1.5)
		var ri := MeshInstance3D.new()
		ri.mesh = rq
		ri.material_override = rm
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ri.position = Vector3(_rail_x[i], _road_y + 0.04, _z_line)
		ri.rotation_degrees = Vector3(-90, 0, 0)
		ri.visible = false
		add_child(ri)
		_rings.append(ri)
		_ring_mats.append(rm)

		var lm := ShaderMaterial.new()
		lm.shader = lane_shader
		var lq := QuadMesh.new()
		lq.size = Vector2(0.9, LANE_LEN)
		var li := MeshInstance3D.new()
		li.mesh = lq
		li.material_override = lm
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		li.position = Vector3(_rail_x[i], _road_y + 0.03, _z_line - LANE_LEN * 0.5)
		li.rotation_degrees = Vector3(-90, 0, 0)
		li.visible = false
		add_child(li)
		_lanes.append(li)
		_lane_mats.append(lm)


## quality: 0 MAX, 1 300, 2 200, 3 100, 4 50, 5 Miss.
func spark(column: int, quality: int) -> void:
	if not _ready_ok or column < 0 or column >= _rail_x.size() or quality >= 5:
		return
	var count := 0
	var ring := 0.0
	match quality:
		0:
			count = 6
			ring = 0.45
		1:
			count = 4
		2:
			count = 2
		_:
			ring = 0.18
	var origin := Vector3(_rail_x[column], _road_y + 0.12, _z_line)
	var side := -1.0 if column < _rail_x.size() / 2 else 1.0
	var col := _lighten(_theme, 0.2 if quality == 0 else 0.1)
	for k in count:
		var i := _cursor
		_cursor = (_cursor + 1) % SPARK_POOL
		# Flach: seitlich nach aussen und zur Kamera (+z), kaum nach oben,
		# nie nach -z -> bleibt im Bild an/unterhalb der Abfanglinie.
		_vel[i] = Vector3(
			side * _rng.randf_range(0.2, 1.1) + _rng.randf_range(-0.4, 0.4),
			_rng.randf_range(0.15, 0.55),
			_rng.randf_range(1.0, 2.2))
		_pos[i] = origin + Vector3(_rng.randf_range(-0.15, 0.15), 0.0, 0.15)
		_life0[i] = _rng.randf_range(0.16, 0.26)
		_life[i] = _life0[i]
		_size[i] = _rng.randf_range(0.05, 0.09) * (1.0 if quality == 0 else 0.8)
		_tint[i] = col.lerp(Color(1.0, 0.85, 0.6), _rng.randf() * 0.35)
	if ring > 0.0:
		_ring_t[column] = 0.0
		_ring_mats[column].set_shader_parameter("col", _vec(_lighten(_theme, 0.25)))
		_ring_mats[column].set_shader_parameter("strength", minf(ring, BRIGHT_CAP))
		_rings[column].visible = true


## Frueher ein Licht-Schuss die Spur hinauf. Der lief genau ueber die
## anfliegenden Noten und stoerte das Lesen -> bewusst ohne Wirkung (API bleibt).
func lane_shot(column: int) -> void:
	if not _ready_ok or column < 0 or column >= _rail_x.size():
		return


func update(delta: float) -> void:
	if not _ready_ok:
		return
	for i in SPARK_POOL:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_hide_spark(i)
			continue
		var v := _vel[i]
		v.y -= 9.0 * delta
		v *= maxf(0.0, 1.0 - 1.8 * delta)
		var p := _pos[i] + v * delta
		if p.y < _road_y + 0.03:
			p.y = _road_y + 0.03
			v.y = absf(v.y) * 0.25
		_vel[i] = v
		_pos[i] = p
		var k := _life[i] / _life0[i]
		var s := _size[i] * (0.4 + 0.6 * k)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
		var c := _tint[i]
		_mm.set_instance_color(i, Color(c.r, c.g, c.b, k * k))
	for i in _ring_t.size():
		if _ring_t[i] < 1.0:
			_ring_t[i] = minf(1.0, _ring_t[i] + delta / RING_TIME)
			_ring_mats[i].set_shader_parameter("t", _ring_t[i])
			if _ring_t[i] >= 1.0:
				_rings[i].visible = false
		if _lane_t[i] < 1.0:
			_lane_t[i] = minf(1.0, _lane_t[i] + delta / LANE_TIME)
			_lane_mats[i].set_shader_parameter("t", _lane_t[i])
			if _lane_t[i] >= 1.0:
				_lanes[i].visible = false
