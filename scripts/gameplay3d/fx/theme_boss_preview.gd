extends Node3D
## Demo: Welt-Thema "Bosskampf" (shaders/theme_boss.gdshader) mit Komfort-Kamera,
## monochrom blutroter Strecke (Farbsatz aus dem Shader-Kopf) und Pads.
## Ohne Argumente: 140 BPM, Beat-Vertrag simuliert (beat_step, downbeat_pulse,
## Kiai/Drop-Schleife 64 Schlaege), Blitz auf jedem 2. Downbeat (4/4),
## Gruppe wechselt reihum. Tasten: 1-3 Blitz in Gruppe, Leertaste Blitz auto.
##   --rise=<Zyklen/s>  --comfort=<0|1>
##   --shot [--shot-dir=<ordner>]  speichert boss_still / boss_beat (phase 0.02) /
##        boss_half (0.5) / boss_drop (Drop-Spitze) / boss_side (Blick 70 Grad)
##        und druckt die [luma]-Zeilen (Grenzen: Mitte +20 %, oben +35 %), dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "user://theme_shots/boss"
const BPM := 140.0
const NAME := "boss"
const DIR := "res://assets_game/themes/boss/"

# Farbsatz (siehe shaders/theme_boss.gdshader, FARBSATZ).
const C_ROAD := Color("#070203")
const C_LANE := Color("#3a0609")
const C_EDGE := Color("#8c0610")
const C_LINE := Color("#c01a1e")
const C_PAD_FILL := Color("#2a0507")
const C_NOTE := Color("#e8d4d4")

var _mat: ShaderMaterial
var _cam: Camera3D
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _flash := 0.0
var _cell := 0
var _last_beat := -1
var _bpm := BPM

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")

	_comfort = _arg_f("--comfort=", 0.0)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_boss.gdshader")
	_mat.set_shader_parameter("tex_a", load(DIR + "sky_boss.webp"))
	_mat.set_shader_parameter("stars_a", load(DIR + "sky_boss_embers.webp"))
	_mat.set_shader_parameter("shards_tex", load(DIR + "sky_boss_shards.webp"))
	_mat.set_shader_parameter("veil_tex", load(DIR + "sky_boss_veil.webp"))
	_mat.set_shader_parameter("flash_tex", load(DIR + "sky_boss_flash.webp"))
	_mat.set_shader_parameter("readability", 0.7)
	_mat.set_shader_parameter("ember_rise", 0.0 if _shot else _arg_f("--rise=", 0.12))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#140405")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2.1, 7.6)
	_cam.rotation_degrees = Vector3(-16, 0, 0)
	_cam.fov = 62.0
	_cam.current = true
	add_child(_cam)

	var road := _quad(Vector2(7.2, 60.0), Vector3(0, ROAD_Y - 0.01, -20.0), Color(C_ROAD, 0.92))
	add_child(road)
	for x in [-3.4, 3.4]:
		add_child(_quad(Vector2(0.06, 60.0), Vector3(x, ROAD_Y, -20.0), C_EDGE * 1.3))
	for x in [-1.7, 0.0, 1.7]:
		add_child(_quad(Vector2(0.035, 60.0), Vector3(x, ROAD_Y, -20.0), Color(C_LANE, 0.55)))
	var line := _quad(Vector2(7.2, 0.07), Vector3(0, ROAD_Y + 0.005, Z_LINE), C_LINE * 1.6)
	add_child(line)
	var disc_shader: Shader = load("res://shaders/note_disc.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(1.12, 1.12)
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.rotation_degrees = Vector3(-90, 0, 0)
		mi.position = Vector3(RAIL_X[i], ROAD_Y + 0.3, Z_LINE)
		var m := ShaderMaterial.new()
		m.shader = disc_shader
		m.set_shader_parameter("base_color", C_EDGE)
		m.set_shader_parameter("fill_alpha", 0.25)
		mi.material_override = m
		add_child(mi)
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[(i * 3 + 1) % 4], ROAD_Y + 0.32, -3.0 - 6.0 * i)
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", C_NOTE)
		n.material_override = nm
		add_child(n)

func _quad(size: Vector2, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	return mi

func _arg_f(prefix: String, def: float) -> float:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return float(a.trim_prefix(prefix))
	return def

func _strike(cell: int) -> void:
	_mat.set_shader_parameter("lightning_cell", cell)
	_flash = 1.0

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode >= KEY_1 and ev.keycode <= KEY_3:
			_strike(ev.keycode - KEY_1)
		elif ev.keycode == KEY_SPACE:
			_strike(-1)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _shot:
		_shot_run()
		return
	_sim_process()
	var beat := int(_t * BPM / 60.0)
	# Blitz auf jedem 2. Downbeat (alle 8 Schlaege), Gruppe reihum.
	if beat != _last_beat:
		_last_beat = beat
		if beat % 8 == 0:
			_strike(_cell)
			_cell = (_cell + 1) % 3
	_flash = move_toward(_flash, 0.0, delta * 4.0)
	_mat.set_shader_parameter("lightning", _flash)

# --- Beat-Vertrag-Simulation: exakt die Formeln aus docs/worlds/beat_contract.md ---
const METER := 4
const DROP_PEAK := 0.6
const DROP_HOLD := 0.3
const DROP_MAX := 0.6
const LOOP_BEATS := 64.0
const KIAI_ON := 16.0   ## Beat, an dem das Kiai (der Drop) beginnt
const KIAI_OFF := 40.0
var _comfort := 0.0
var _luma: Dictionary = {}
var _shot_i := 0

func _set_beat(beat_idx: int, phase: float, drop: float, kiai: float, energy: float) -> void:
	var beat_ms := 60000.0 / _bpm
	var bar_phase := (float(beat_idx % METER) + phase) / float(METER)
	var peak := 1.15 if beat_idx % METER == 0 else 1.0
	var cf := 1.0 - 0.5 * _comfort
	_mat.set_shader_parameter("beat_pulse", clampf(peak * exp(-phase * beat_ms / 62.0), 0.0, 1.0))
	_mat.set_shader_parameter("beat_phase", phase)
	_mat.set_shader_parameter("bar_phase", bar_phase)
	_mat.set_shader_parameter("beat_step", float(beat_idx) + 1.0 - pow(1.0 - phase, 4.0))
	_mat.set_shader_parameter("downbeat_pulse", exp(-bar_phase * float(METER) * 3.0))
	_mat.set_shader_parameter("kiai", kiai)
	_mat.set_shader_parameter("drop", minf(drop * cf, DROP_MAX))
	_mat.set_shader_parameter("energy", energy)
	_mat.set_shader_parameter("comfort", _comfort)

func _beat_off() -> void:
	_set_beat(0, 0.0, 0.0, 0.0, 0.0)
	_mat.set_shader_parameter("beat_pulse", 0.0)
	_mat.set_shader_parameter("beat_step", 0.0)
	_mat.set_shader_parameter("downbeat_pulse", 0.0)
	_mat.set_shader_parameter("bar_phase", 0.0)

## Drop-Huellkurve: Kiai-Start 1 Beat smoothstep auf PEAK, 4 Beats auf HOLD, Ende 2 Beats auf 0.
func _drop_at(b: float) -> float:
	if b < KIAI_ON:
		return 0.0
	if b < KIAI_OFF:
		var x := b - KIAI_ON
		if x < 1.0:
			return DROP_PEAK * smoothstep(0.0, 1.0, x)
		return lerpf(DROP_PEAK, DROP_HOLD, clampf((x - 1.0) / 4.0, 0.0, 1.0))
	return DROP_HOLD * (1.0 - clampf((b - KIAI_OFF) / 2.0, 0.0, 1.0))

func _sim_process() -> void:
	var b := fmod(_t * _bpm / 60.0, LOOP_BEATS)
	var kiai := smoothstep(KIAI_ON - 0.5, KIAI_ON + 0.5, b) * (1.0 - smoothstep(KIAI_OFF, KIAI_OFF + 2.0, b))
	var en := 0.35 + 0.5 * kiai
	_set_beat(int(b), fmod(b, 1.0), _drop_at(b), kiai, en)

func _mean_luma(img: Image, r: Rect2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(r.position.x * w)
	var x1 := int(r.end.x * w)
	var y0 := int(r.position.y * h)
	var y1 := int(r.end.y * h)
	var sum := 0.0
	var n := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(n, 1)

func _measure(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	_luma[tag] = [_mean_luma(img, Rect2(0.25, 0.42, 0.5, 0.45)), _mean_luma(img, Rect2(0.0, 0.0, 1.0, 0.42))]
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path := _shot_dir.path_join("%s_%s.png" % [NAME, tag])
	img.save_png(path)
	print("shot: ", path)

func _pct(a: float, b: float) -> float:
	return (a / maxf(b, 1e-6) - 1.0) * 100.0

func _report() -> void:
	var s: Array = _luma["still"]
	var be: Array = _luma["beat"]
	var h: Array = _luma["half"]
	var d: Array = _luma["drop"]
	print("[luma] still=%.4f/%.4f beat=%.4f/%.4f half=%.4f/%.4f drop=%.4f/%.4f (mitte/oben)" % [s[0], s[1], be[0], be[1], h[0], h[1], d[0], d[1]])
	print("[luma] drop vs still: mitte %+.1f%% (max +20) oben %+.1f%% (max +35, Drop-Spitze bei phase 0.5) | beat vs half: oben %+.1f%% mitte %+.1f%% (oben >=6 oder Bewegung)" % [_pct(d[0], s[0]), _pct(d[1], s[1]), _pct(be[1], h[1]), _pct(be[0], h[0])])

## --shot: still / beat (phase 0.02) / half (0.5) / drop (Spitze) / side. 14 Frames Einschwingen je Aufnahme.
func _shot_run() -> void:
	if _frames % 14 != 0:
		return
	match _shot_i:
		0:
			_beat_off()
		1:
			_measure("still")
			_set_beat(8, 0.02, 0.0, 0.0, 0.5)
		2:
			_measure("beat")
			_set_beat(8, 0.5, 0.0, 0.0, 0.5)
		3:
			_measure("half")
			_set_beat(8, 0.5, DROP_PEAK, 1.0, 0.9)
		4:
			_measure("drop")
			_set_beat(9, 0.3, DROP_PEAK, 1.0, 0.9)
			_cam.rotation_degrees = Vector3(-6, 70, 0)
			_cam.fov = 75.0
		5:
			_measure("side")
			_report()
			get_tree().quit(0)
	_shot_i += 1
