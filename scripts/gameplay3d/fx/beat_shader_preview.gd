extends Node3D
## Demo: Strasse + Kanten + Nebel bei 128 BPM simuliert.
## --shot: je ein Bild direkt auf dem Beat (on) und zwischen Beats (off), dann Ende.

const Z_LINE := 3.0
const ROAD_Y := -1.6
const BPM := 128.0
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/"

var _road_mat: ShaderMaterial
var _rail_mats: Array[ShaderMaterial] = []
var _neb_mat: ShaderMaterial
var _t := 0.0
var _shot := false
var _stage := 0
var _busy := false


func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _ready() -> void:
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_shot = "--shot" in all or "shot" in all
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
	# Nebel
	var neb := MeshInstance3D.new()
	var nq := QuadMesh.new()
	nq.size = Vector2(60, 28)
	neb.mesh = nq
	_neb_mat = _mat("res://shaders/space_bg.gdshader")
	neb.material_override = _neb_mat
	neb.position = Vector3(0, 6, -28)
	add_child(neb)
	# Strasse (UV.y: 0 fern, 1 Linie)
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(7.4, 50.0)
	road.mesh = rq
	_road_mat = _mat("res://shaders/road_wave.gdshader")
	_road_mat.set_shader_parameter("wave_amount", 0.0)
	road.material_override = _road_mat
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y, Z_LINE - 47.0 * 0.5)
	add_child(road)
	# Kanten
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(50.0, 0.5)
		rail.mesh = q
		var m := _mat("res://shaders/rail_fire.gdshader")
		m.set_shader_parameter("intensity", 0.5)
		rail.material_override = m
		rail.rotation_degrees = Vector3(0, 90, 0)
		rail.position = Vector3(sx * 3.75, ROAD_Y + 0.25, Z_LINE - 22.0)
		add_child(rail)
		_rail_mats.append(m)
	# Rand-Glow
	var layer := CanvasLayer.new()
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := _mat("res://shaders/screen_glow.gdshader")
	gm.set_shader_parameter("intensity", 0.5)
	cr.material = gm
	layer.add_child(cr)
	add_child(layer)
	_rail_mats.append(gm)


func _set_beat(flash: float, down: float, en: float, beat_t: float) -> void:
	var beat := beat_t * BPM / 60.0
	var ph := fmod(beat, 1.0)
	_road_mat.set_shader_parameter("beat_phase", ph)
	_road_mat.set_shader_parameter("beat_flash", flash)
	_road_mat.set_shader_parameter("downbeat", down)
	_road_mat.set_shader_parameter("music_energy", en)
	_neb_mat.set_shader_parameter("drift", beat_t)
	_neb_mat.set_shader_parameter("beat_flash", flash)
	_neb_mat.set_shader_parameter("downbeat", down)
	_neb_mat.set_shader_parameter("music_energy", en)
	for m in _rail_mats:
		m.set_shader_parameter("t", beat_t)
		m.set_shader_parameter("beat_flash", flash)
		m.set_shader_parameter("downbeat", down)
		m.set_shader_parameter("music_energy", en)


func _process(delta: float) -> void:
	_t += delta
	var period := 60.0 / BPM
	var since := fmod(_t, period)
	var beat := int(_t / period)
	var flash := clampf(1.0 - since / 0.15, 0.0, 1.0)
	var down := flash if beat % 4 == 0 else 0.0
	_set_beat(flash, down, 0.8, _t)
	if not _shot or _busy:
		return
	# on: kurz nach einem Taktanfang; off: Mitte zwischen Beats (Flash abgeklungen).
	if _stage == 0 and beat >= 4 and beat % 4 == 0 and since > 0.03:
		_busy = true
		await _save("beat_shader_on.png")
		_stage = 1
		_busy = false
	elif _stage == 1 and beat % 4 == 2 and since > period * 0.6:
		_busy = true
		await _save("beat_shader_off.png")
		get_tree().quit()


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	img.save_png(SHOT_DIR + shot_name)
