extends Node3D
## Demo: Welt-Thema "Rift" (shaders/theme_rift.gdshader) mit Komfort-Kamera,
## Strecke + Pads im Farbsatz aus dem Shader-Kopf. Simuliert die Beat-Uniforms des
## Beat-Vertrags (docs/worlds/beat_contract.md) mit denselben Formeln wie mania_3d.gd.
## Ohne Argumente: 128 BPM live, Kiai-Zyklus (Drop) alle 64 Schlaege.
##   --bpm=<n>  --meter=<n>  --comfort
##   --shot [--shot-dir=<ordner>]  speichert <name>_still/beat/half/drop/side.png,
##        druckt die [luma]-Zeile (Strecke/Pads mitte-unten + Hintergrund oben), dann Ende.

const WORLD := "rift"
const SHADER := "res://shaders/theme_rift.gdshader"
const DIR := "res://assets_game/themes/rift/"
const TEXTURES := {
	"tex_a": "sky_rift.webp",
	"rows_a": "sky_rift_rows.webp",
	"stars_a": "sky_rift_stars.webp",
	"prisms_a": "sky_rift_prisms.webp",
}
const ROAD_Y := -1.6
const Z_LINE := 3.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/80c0c6f9-06b1-4222-ad93-57c1e121669d/scratchpad/shots"
const DROP_PEAK := 0.6
const DROP_HOLD := 0.3

# Farbsatz (siehe Shader-Kopf, FARBSATZ).
const C_ROAD := Color("#050706")
const C_LANE := Color("#1a211d")
const C_EDGE := Color("#7f9486")
const C_LINE := Color("#b8d0c0")
const C_NOTE := Color("#eef6f0")
const C_AMBIENT := Color("#070a08")

var _mat: ShaderMaterial
var _cam: Camera3D
var _t := 0.0
var _frames := 0
var _shot := false
var _comfort := 0.0
var _shot_dir := SHOT_DIR
var _step := 0
var _bpm := 128.0
var _meter := 4
var _luma := {}
var _bench := false
var _baseline := false
var _ft: Array[float] = []

func _ready() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--shot":
			_shot = true
		elif a == "--bench":
			_bench = true
		elif a == "--baseline":
			_baseline = true
		elif a == "--comfort":
			_comfort = 1.0
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--bpm="):
			_bpm = float(a.trim_prefix("--bpm="))
		elif a.begins_with("--meter="):
			_meter = int(a.trim_prefix("--meter="))

	if _shot or _bench:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	if _bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	_mat = ShaderMaterial.new()
	if _baseline:
		# Vergleichswert: dieselbe Szene mit dem Standard-Panorama-Himmel
		_mat.shader = load("res://shaders/sky_panorama.gdshader")
		_mat.set_shader_parameter("tex_a", load("res://assets_game/space/sky_violet.webp"))
		_mat.set_shader_parameter("stars_a", load("res://assets_game/space/sky_violet_stars.webp"))
	else:
		_mat.shader = load(SHADER)
		for k in TEXTURES:
			_mat.set_shader_parameter(k, load(DIR + TEXTURES[k]))
	_mat.set_shader_parameter("readability", 0.7)
	_mat.set_shader_parameter("comfort", _comfort)
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = C_AMBIENT
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

	add_child(_quad(Vector2(7.2, 60.0), Vector3(0, ROAD_Y - 0.01, -20.0), Color(C_ROAD, 0.92)))
	for x in [-3.4, 3.4]:
		add_child(_quad(Vector2(0.06, 60.0), Vector3(x, ROAD_Y, -20.0), C_EDGE * 1.2))
	for x in [-1.7, 0.0, 1.7]:
		add_child(_quad(Vector2(0.035, 60.0), Vector3(x, ROAD_Y, -20.0), Color(C_LANE, 0.55)))
	add_child(_quad(Vector2(7.2, 0.07), Vector3(0, ROAD_Y + 0.005, Z_LINE), C_LINE * 1.5))
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

## Beat-Uniforms aus (Schlag-Zaehler, Phase im Schlag, Kiai, Drop) - Formeln wie mania_3d.gd.
func _set_beat(beats_total: int, phase: float, kiai: float, drop: float, energy: float) -> void:
	var beat_ms := 60000.0 / _bpm
	var bar_phase := (float(beats_total % _meter) + phase) / float(_meter)
	var down := beats_total % _meter == 0
	var peak := 1.15 if down else 1.0
	_mat.set_shader_parameter("beat_pulse", minf(1.0, peak * exp(-phase * beat_ms / 62.0)))
	_mat.set_shader_parameter("beat_phase", phase)
	_mat.set_shader_parameter("bar_phase", bar_phase)
	_mat.set_shader_parameter("beat_step", float(beats_total) + phase + 0.25 * ((1.0 - pow(1.0 - phase, 2.0)) - phase))
	_mat.set_shader_parameter("downbeat_pulse", exp(-bar_phase * float(_meter) * 3.0))
	_mat.set_shader_parameter("kiai", kiai)
	_mat.set_shader_parameter("drop", drop * (1.0 - 0.5 * _comfort))
	_mat.set_shader_parameter("energy", energy)

func _beats_off() -> void:
	for k in ["beat_pulse", "beat_phase", "bar_phase", "downbeat_pulse", "kiai", "drop", "energy"]:
		_mat.set_shader_parameter(k, 0.0)
	_mat.set_shader_parameter("beat_step", 5.0)

## Drop-Huellkurve (Vertrag): 1 Beat smoothstep auf PEAK, 4 Beats auf HOLD, Ende 2 Beats auf 0.
func _drop_env(beat_f: float, k_start: float, k_end: float) -> float:
	if beat_f < k_start or beat_f > k_end + 2.0:
		return 0.0
	if beat_f > k_end:
		return DROP_HOLD * (1.0 - smoothstep(0.0, 2.0, beat_f - k_end))
	var s := beat_f - k_start
	if s < 1.0:
		return DROP_PEAK * smoothstep(0.0, 1.0, s)
	return lerpf(DROP_PEAK, DROP_HOLD, smoothstep(1.0, 5.0, s))

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _bench:
		_bench_step(delta)
		return
	if _shot:
		_shot_step()
		return
	var beat_f := _t * _bpm / 60.0
	var cyc := fmod(beat_f, 64.0)
	var kiai := smoothstep(15.0, 17.0, cyc) * (1.0 - smoothstep(47.0, 49.0, cyc))
	_set_beat(int(beat_f), fmod(beat_f, 1.0), kiai, _drop_env(cyc, 16.0, 48.0), 0.4 + 0.4 * kiai)

func _luma_of(img: Image, x0: float, x1: float, y0: float, y1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var acc := 0.0
	var n := 0
	for y in range(int(h * y0), int(h * y1), 3):
		for x in range(int(w * x0), int(w * x1), 3):
			var c := img.get_pixel(x, y)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return acc / maxf(n, 1)

## --shot: je 8 Frames Einschwingen, dann speichern.
func _shot_step() -> void:
	if _frames % 8 != 0:
		return
	match _step:
		0:
			_beats_off()
		1:
			_save("still")
			_set_beat(5, 0.02, 0.0, 0.0, 0.6)
		2:
			_save("beat")
			_set_beat(5, 0.5, 0.0, 0.0, 0.6)
		3:
			_save("half")
			_set_beat(5, 0.02, 1.0, DROP_PEAK, 0.9)
		4:
			_save("drop")
			_beats_off()
			_cam.rotation_degrees = Vector3(0, 70, 0)
		5:
			_save("side")
			var s: float = _luma["still"]
			var d: float = _luma["drop"]
			var ts: float = _luma["top_still"]
			var td: float = _luma["top_drop"]
			print("[luma] still=%.4f beat=%.4f drop=%.4f (%+.1f%%) | top still=%.4f beat=%.4f half=%.4f drop=%.4f (%+.1f%%) beat/half=%.2fx" % [
				s, _luma["beat"], d, (d / maxf(s, 1e-6) - 1.0) * 100.0,
				ts, _luma["top_beat"], _luma["top_half"], td, (td / maxf(ts, 1e-6) - 1.0) * 100.0,
				_luma["top_beat"] / maxf(_luma["top_half"], 1e-6)])
			get_tree().quit(0)
	_step += 1

func _save(tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var img := get_viewport().get_texture().get_image()
	_luma[tag] = _luma_of(img, 0.25, 0.75, 0.42, 0.87)
	_luma["top_" + tag] = _luma_of(img, 0.0, 1.0, 0.03, 0.40)
	var path := _shot_dir.path_join("%s_%s.png" % [WORLD, tag])
	img.save_png(path)
	print("shot: ", path)
	if tag == "beat":
		# 100-%-Crop (512x512 aus 1920x1080) zur Schaerfepruefung
		var cx := int(img.get_width() * 0.04)
		var cy := int(img.get_height() * 0.04)
		img.get_region(Rect2i(cx, cy, 512, 512)).save_png(_shot_dir.path_join("%s_crop.png" % WORLD))

## --bench: 120 Frames Warmup, dann 600 Frames messen (live simulierter Beat inkl. Kiai/Drop).
func _bench_step(delta: float) -> void:
	var beat_f := _t * _bpm / 60.0 + 16.0
	var cyc := fmod(beat_f, 64.0)
	if not _baseline:
		_set_beat(int(beat_f), fmod(beat_f, 1.0), 1.0, DROP_HOLD, 0.7)
	if _frames > 120:
		_ft.append(delta)
	if _ft.size() >= 600:
		var sum := 0.0
		for f in _ft:
			sum += f
		var sorted := _ft.duplicate()
		sorted.sort()
		print("[perf] %s%s fps_avg=%.1f frame_ms_p99=%.2f" % [WORLD, " (baseline)" if _baseline else "", _ft.size() / sum, sorted[int(sorted.size() * 0.99)] * 1000.0])
		get_tree().quit(0)
