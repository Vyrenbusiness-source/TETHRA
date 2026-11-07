extends Node3D
## Demo: Welt-Thema "Aurora"/"Frost" (shaders/theme_aurora.gdshader) mit
## Komfort-Kamera, dunkler Strecke, Pads und Noten im Frost-Farbsatz zur
## Lesbarkeits-Kontrolle. Polarlicht weht, Beat bei 90 BPM (ruhige Songs).
##   --pulse=<0..1>  --flow=<0..2>  --speed=<Zyklen/s Sternflug>
##   --shot [--shot-dir=<ordner>]  speichert aurora_still / aurora_beat
##        (phase 0.02) / aurora_half (phase 0.5) / aurora_drop (Drop-Spitze) /
##        aurora_side, druckt [luma] still=.. beat=.. drop=.. (Strecke: x .25-.75,
##        y .42-.87 | oben: y 0-.42). Beat-Uniforms nach docs/worlds/beat_contract.md.
##   --drop=<0..0.6> --kiai=<0..1> im Dauerlauf.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const BPM := 90.0
const CAM_POS := Vector3(0, 2.1, 7.6)
const CAM_ROT := Vector3(-16, 0, 0)
const TEX_DIR := "res://assets_game/themes/aurora/"
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/2690cab5-bd8f-418e-ba0f-9da78692e0cd/scratchpad/aurora"

# Frost-Farbsatz (siehe Kopf von theme_aurora.gdshader)
const C_ROAD := Color("05080a")
const C_EDGE := Color("8fb3b8")
const C_PAD := Color("a9c4c8")
const C_NOTE := Color("d6e6e8")
const C_ACCENT := Color("6f9aa0")

var _mat: ShaderMaterial
var _cam: Camera3D
var _t := 0.0
var _frames := 0
var _shot := false
var _bench := false
var _bench_base := false
var _bench_ms: PackedFloat64Array = PackedFloat64Array()
var _bench_last := 0
var _shot_dir := SHOT_DIR
var _step := 0

func _ready() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--shot":
			_shot = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_aurora.gdshader")
	_mat.set_shader_parameter("tex_a", load(TEX_DIR + "aurora_sky.webp"))
	_mat.set_shader_parameter("stars_a", load(TEX_DIR + "aurora_stars.webp"))
	_mat.set_shader_parameter("aurora_a", load(TEX_DIR + "aurora_aurora.webp"))
	_mat.set_shader_parameter("ice_a", load(TEX_DIR + "aurora_ice.webp"))
	_mat.set_shader_parameter("aurora_flow", _arg_f("--flow=", 1.0))
	_mat.set_shader_parameter("star_speed", 0.0 if _shot else _arg_f("--speed=", 0.0))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("0c1215")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Glow wie im Spiel (mania_3d.gd).
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.position = CAM_POS
	_cam.rotation_degrees = CAM_ROT
	_cam.fov = 62.0
	_cam.current = true
	add_child(_cam)

	var length := absf(Z_FAR) + 6.0
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(8.4, length)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, (Z_FAR + Z_LINE) * 0.5)
	road.material_override = _unshaded(Color(C_ROAD, 0.92))
	add_child(road)
	for sx in [-3.6, 3.6]:
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.10, 0.03, length)
		edge.mesh = eb
		edge.position = Vector3(sx, ROAD_Y, (Z_FAR + Z_LINE) * 0.5)
		edge.material_override = _unshaded(C_EDGE * 0.85)
		add_child(edge)
	var disc_shader: Shader = load("res://shaders/note_disc.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(1.12, 1.12)
	for i in 4:
		var pad := MeshInstance3D.new()
		pad.mesh = q
		pad.rotation_degrees = Vector3(-90, 0, 0)
		pad.position = Vector3(RAIL_X[i], ROAD_Y + 0.3, Z_LINE)
		var m := ShaderMaterial.new()
		m.shader = disc_shader
		m.set_shader_parameter("base_color", C_PAD)
		m.set_shader_parameter("fill_alpha", 0.0)
		pad.material_override = m
		add_child(pad)
	# Anfliegende Noten, auch ganz hinten am Horizont (Lesbarkeit vor dem Massiv).
	var zs: Array[float] = [-1.0, -7.0, -13.0, -20.0, -28.0, -36.0, -44.0]
	for k in zs.size():
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[(k * 3 + 1) % 4], ROAD_Y + 0.32, zs[k])
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", C_NOTE if k % 3 != 2 else C_ACCENT)
		n.material_override = nm
		add_child(n)

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _arg_f(prefix: String, def: float) -> float:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return float(a.trim_prefix(prefix))
	return def

func _set_state(beats: int, phase: float, drop: float, kiai: float) -> void:
	var beat_ms := 60000.0 / BPM
	var meter := 4
	var bar_phase := (float(beats % meter) + phase) / float(meter)
	var p := exp(-phase * beat_ms / 62.0)
	if beats % meter == 0:
		p = minf(p * 1.15, 1.0)
	_mat.set_shader_parameter("beat_pulse", p)
	_mat.set_shader_parameter("beat_phase", phase)
	_mat.set_shader_parameter("bar_phase", bar_phase)
	_mat.set_shader_parameter("beat_step", float(beats) + phase + 0.25 * ((1.0 - pow(1.0 - phase, 2.0)) - phase))
	_mat.set_shader_parameter("downbeat_pulse", exp(-bar_phase * float(meter) * 3.0))
	_mat.set_shader_parameter("drop", drop)
	_mat.set_shader_parameter("kiai", kiai)
	_mat.set_shader_parameter("energy", 0.5)
	_mat.set_shader_parameter("comfort", 0.0)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	_bench_tick()
	if _shot:
		_shot_step()
		return
	var b := _t * BPM / 60.0
	var d := clampf(float(_arg_f("--drop=", 0.0)), 0.0, 0.6)
	_set_state(int(floor(b)), fmod(b, 1.0), d, _arg_f("--kiai=", 0.0))

func _luma(img: Image, y0: float, y1: float) -> float:
	var im := img.duplicate() as Image
	im.resize(160, 90)
	var s := 0.0
	var n := 0
	for y in range(int(y0 * 90), int(y1 * 90)):
		for x in range(int(0.25 * 160), int(0.75 * 160)) if y0 > 0.1 else range(0, 160):
			var c := im.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / float(maxi(n, 1))

var _lm: Dictionary = {}

func _grab(key: String) -> void:
	var img := get_viewport().get_texture().get_image()
	_lm[key] = [_luma(img, 0.42, 0.87), _luma(img, 0.0, 0.42)]
	_save("aurora_%s.png" % key)

## Schritt-Folge fuer --shot: je 12 Frames Einschwingen, dann speichern.
func _shot_step() -> void:
	if _jk >= 0:
		_jerk_tick()
		return
	if _frames % 12 != 0:
		return
	match _step:
		0:
			_set_state(8, 0.5, 0.0, 0.0)
		1:
			_grab("still")
			_set_state(8, 0.02, 0.0, 0.0)
		2:
			_grab("beat")
			_set_state(8, 0.5, 0.0, 0.0)
		3:
			_grab("half")
			_set_state(8, 0.02, 0.6, 1.0)
		4:
			_grab("drop")
			_set_state(8, 0.5, 0.0, 0.0)
			_cam.rotation_degrees = Vector3(-8, 70, 0)
		5:
			_grab("side")
			var s: Array = _lm["still"]
			var bt: Array = _lm["beat"]
			var h: Array = _lm["half"]
			var dr: Array = _lm["drop"]
			print("[luma] still=%.4f beat=%.4f drop=%.4f (Strecke) | oben still=%.4f beat=%.4f half=%.4f drop=%.4f" % [s[0], bt[0], dr[0], s[1], bt[1], h[1], dr[1]])
			print("[luma] Strecke drop/still=%+.1f%% (max +20) | oben drop/still=%+.1f%% (max +35) | beat/half oben=%+.1f%%" % [
				100.0 * (dr[0] / maxf(s[0], 1e-5) - 1.0), 100.0 * (dr[1] / maxf(s[1], 1e-5) - 1.0), 100.0 * (bt[1] / maxf(h[1], 1e-5) - 1.0)])
			_jerk_start(func(b: int, p: float) -> void: _set_state(b, p, 0.0, 0.0))
	_step += 1

func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path := _shot_dir.path_join(file)
	img.save_png(path)
	print("shot: ", path)

## --bench [--bench-base]: vsync aus, max_fps 0, 1920x1080, 120 Frames Warmup,
## 600 Frames messen, druckt "[perf] <welt> fps_avg=.. frame_ms_p99=..".
## --bench-base tauscht den Welt-Shader gegen shaders/sky_panorama.gdshader.
func _bench_tick() -> bool:
	if _frames == 1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bench = args.has("--bench")
		_bench_base = args.has("--bench-base")
		if _bench:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			get_window().size = Vector2i(1920, 1080)
			if _bench_base:
				var tex = _mat.get_shader_parameter("tex_a")
				var tex2 = _mat.get_shader_parameter("stars_a")
				_mat.shader = load("res://shaders/sky_panorama.gdshader")
				_mat.set_shader_parameter("tex_a", tex)
				_mat.set_shader_parameter("stars_a", tex2)
	if not _bench:
		return false
	var now := Time.get_ticks_usec()
	if _frames > 120:
		_bench_ms.append(float(now - _bench_last) / 1000.0)
	_bench_last = now
	if _bench_ms.size() >= 600:
		var sorted := _bench_ms.duplicate()
		sorted.sort()
		var sum := 0.0
		for v in _bench_ms:
			sum += v
		print("[perf] ", "aurora", (" base" if _bench_base else ""), " fps_avg=", snappedf(1000.0 * _bench_ms.size() / sum, 0.1), " frame_ms_p99=", snappedf(sorted[int(sorted.size() * 0.99)], 0.01))
		get_tree().quit(0)
	return true

# --- Komfort-Pruefung (docs/worlds/beat_contract.md, Komfort-Regel 5) ---
# Nach den --shot-Aufnahmen: zwei Paare im Abstand 1/8 Beat, Licht eingefroren
# (Licht fest, nur beat_step + TIME laufen). mitte = 8.4375 -> 8.5625, schlag = 8.9375 -> 9.0625.
# Glatter Fluss: schlag/mitte ~ 1; Rasten/Stop-and-go auf dem Schlag gaebe >> 1.
const JK_NAME := "aurora"
const JK_BEATS: Array[float] = [8.4375, 8.5625, 8.9375, 9.0625]
var _jk := -1
var _jk_f := 0
var _jk_set: Callable
var _jk_img: Array[Image] = []

func _jerk_start(set_fn: Callable) -> void:
	_jk_set = set_fn
	_jk = 0
	_jk_f = 0
	_cam.rotation_degrees = CAM_ROT
	_cam.fov = 62.0

func _jerk_tick() -> void:
	_jk_f += 1
	if _jk_f % 14 != 0:
		return
	if _jk > 0:
		var img := get_viewport().get_texture().get_image()
		_jk_img.append(img)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://comfort_shots"))
		var path := ProjectSettings.globalize_path("user://comfort_shots/%s_j%d.png" % [JK_NAME, _jk - 1])
		img.save_png(path)
		print("shot: ", path)
	if _jk >= JK_BEATS.size():
		var mid := _jk_diff(_jk_img[0], _jk_img[1])
		var hit := _jk_diff(_jk_img[2], _jk_img[3])
		print("[jerk] %s 1/8 Beat: mitte=%.5f schlag=%.5f ratio=%.2f (glatt <= 1.6)" % [JK_NAME, mid, hit, hit / maxf(mid, 1e-6)])
		get_tree().quit(0)
		return
	var b: float = JK_BEATS[_jk]
	var bi := int(floor(b))
	var p := b - float(bi)
	# Licht (Himmel, Kanten, Noten) einfrieren auf Schlag 8, Phase 0.5: nur beat_step
	# (glatte Formel) und TIME laufen, damit nur die Bewegung verglichen wird.
	_jk_set.call(8, 0.5)
	_mat.set_shader_parameter("beat_step", float(bi) + p + 0.25 * ((1.0 - pow(1.0 - p, 2.0)) - p))
	_jk += 1

func _jk_diff(a: Image, b: Image) -> float:
	var ia := a.duplicate() as Image
	var ib := b.duplicate() as Image
	ia.resize(320, 180)
	ib.resize(320, 180)
	var s := 0.0
	for y in range(180):
		for x in range(320):
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			s += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return s / (320.0 * 180.0 * 3.0)
