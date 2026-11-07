extends Node3D
## Demo: Welt-Thema "Eklipse" (shaders/theme_eclipse.gdshader + eclipse_sky.webp
## + eclipse_ash.webp) mit Komfort-Kamera, schwarzer Strecke im matten
## Gold-Weiss-Farbsatz, Pads und Noten zur Lesbarkeits-Kontrolle.
## Ohne Argumente: 128 BPM, Beat-Vertrag simuliert (beat_step, downbeat_pulse,
## Kiai/Drop-Schleife 64 Schlaege): Schockring, Diamantring-Sprung, Asche stoesst auf.
##   --bpm=<n> --speed=<Asche-Drift> --warp=<0..1> --comfort=<0|1>
##   --shot [--shot-dir=<ordner>]  speichert eclipse_still / _beat (phase 0.02) /
##        _half (0.5) / _drop (Drop-Spitze) / _side (Blick 70 Grad) und druckt die
##        [luma]-Zeilen (Grenzen: Mitte +20 %, oben +35 %), dann Ende.

const NAME := "eclipse"
const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "user://theme_shots/eclipse"

# Farbsatz (siehe Kommentarblock in theme_eclipse.gdshader).
const C_ROAD := Color("#070707")
const C_LANE := Color("#2b2823")
const C_EDGE := Color("#d8c69c")
const C_EDGE_BEAT := Color("#f3e9d0")
const C_PAD := Color("#e6dbc2")
const C_NOTE_A := Color("#f1ead9")
const C_NOTE_B := Color("#c7a866")

var _mat: ShaderMaterial
var _cam: Camera3D
var _edge_mats: Array[StandardMaterial3D] = []
var _note_mats: Array[ShaderMaterial] = []
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _bpm := 128.0

## --bench: vsync aus, max_fps 0, 1920x1080, 120 Frames Warmup, dann 600 Frames messen;
## druckt "[perf] <welt> fps_avg=... frame_ms_p99=...". --bench-ref: dieselbe Szene mit sky_panorama.
var _bench := false
var _bench_ref := false
var _bench_n := 0
var _bench_ms := PackedFloat64Array()

func _bench_tick(delta: float) -> void:
	_bench_n += 1
	if _bench_n == 1:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		get_window().size = Vector2i(1920, 1080)
		if _bench_ref:
			_mat.shader = load("res://shaders/sky_panorama.gdshader")
	if _bench_n > 120:
		_bench_ms.append(delta * 1000.0)
	if _bench_n >= 720:
		var sorted := _bench_ms.duplicate()
		sorted.sort()
		var sum := 0.0
		for v in _bench_ms:
			sum += v
		print("[perf] eclipse%s fps_avg=%.1f frame_ms_p99=%.2f" % ["-ref" if _bench_ref else "", 1000.0 * _bench_ms.size() / sum, sorted[int(sorted.size() * 0.99)]])
		get_tree().quit()

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a == "--bench":
			_bench = true
		elif a == "--bench-ref":
			_bench_ref = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	_bpm = _arg_f("--bpm=", 128.0)
	_comfort = _arg_f("--comfort=", 0.0)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_eclipse.gdshader")
	_mat.set_shader_parameter("tex_a", load("res://assets_game/themes/eclipse/eclipse_sky.webp"))
	_mat.set_shader_parameter("shards_tex", load("res://assets_game/themes/eclipse/eclipse_shards.webp"))
	_mat.set_shader_parameter("ash_a", load("res://assets_game/themes/eclipse/eclipse_ash.webp"))
	_mat.set_shader_parameter("readability", 0.7)
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#0a0a0a")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Glow wie im Spiel (mania_3d.gd).
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	# Komfort-Kamera (mania_3d Default).
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2.1, 7.6)
	_cam.rotation_degrees = Vector3(-16, 0, 0)
	_cam.fov = 62.0
	_cam.current = true
	add_child(_cam)

	var zmid := (Z_FAR + Z_LINE) * 0.5
	var road := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(8.4, absf(Z_FAR) + 6.0)
	road.mesh = rq
	road.rotation_degrees = Vector3(-90, 0, 0)
	road.position = Vector3(0, ROAD_Y - 0.01, zmid)
	road.material_override = _unshaded(Color(C_ROAD, 0.94))
	add_child(road)
	for x in [-1.7, 0.0, 1.7]:
		var ln := MeshInstance3D.new()
		var lq := QuadMesh.new()
		lq.size = Vector2(0.035, absf(Z_FAR) + 6.0)
		ln.mesh = lq
		ln.rotation_degrees = Vector3(-90, 0, 0)
		ln.position = Vector3(x, ROAD_Y, zmid)
		ln.material_override = _unshaded(Color(C_LANE, 0.55))
		add_child(ln)
	for sx in [-3.6, 3.6]:
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.10, 0.03, absf(Z_FAR) + 8.0)
		edge.mesh = eb
		edge.position = Vector3(sx, ROAD_Y, zmid + 2.0)
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.02, 0.02, 0.03)
		em.emission_enabled = true
		em.emission = C_EDGE
		em.emission_energy_multiplier = 0.55
		_edge_mats.append(em)
		edge.material_override = em
		add_child(edge)

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
		m.set_shader_parameter("base_color", C_PAD)
		m.set_shader_parameter("fill_alpha", 0.16)
		mi.material_override = m
		add_child(mi)
	# Anfliegende Noten bis zum Spawn-Horizont (Lesbarkeit vor Sonne/Ruinen).
	for j in 8:
		var col := (j * 3 + 1) % 4
		var n := MeshInstance3D.new()
		n.mesh = q
		n.rotation_degrees = Vector3(-90, 0, 0)
		n.position = Vector3(RAIL_X[col], ROAD_Y + 0.32, -2.0 - 5.6 * j)
		var nm := ShaderMaterial.new()
		nm.shader = disc_shader
		nm.set_shader_parameter("base_color", C_NOTE_A if col == 1 or col == 2 else C_NOTE_B)
		n.material_override = nm
		_note_mats.append(nm)
		add_child(n)

	if not _shot:
		_mat.set_shader_parameter("star_speed", _arg_f("--speed=", 0.4))
		_mat.set_shader_parameter("warp", _arg_f("--warp=", 0.0))

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _arg_f(prefix: String, def: float) -> float:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return float(a.trim_prefix(prefix))
	return def

func _set_pulse(p: float) -> void:
	_mat.set_shader_parameter("beat_pulse", p)
	for em in _edge_mats:
		em.emission = C_EDGE.lerp(C_EDGE_BEAT, p)
		em.emission_energy_multiplier = 0.55 + 0.65 * p
	for nm in _note_mats:
		nm.set_shader_parameter("beat", p)

func _process(delta: float) -> void:
	if _bench:
		_bench_tick(delta)
	_t += delta
	_frames += 1
	if _shot:
		_shot_run()
		return
	_sim_process()

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
	_set_pulse(clampf(peak * exp(-phase * beat_ms / 62.0), 0.0, 1.0))
	_mat.set_shader_parameter("beat_phase", phase)
	_mat.set_shader_parameter("bar_phase", bar_phase)
	_mat.set_shader_parameter("beat_step", float(beat_idx) + phase + 0.25 * ((1.0 - pow(1.0 - phase, 2.0)) - phase))
	_mat.set_shader_parameter("downbeat_pulse", exp(-bar_phase * float(METER) * 3.0))
	_mat.set_shader_parameter("kiai", kiai)
	_mat.set_shader_parameter("drop", minf(drop * cf, DROP_MAX))
	_mat.set_shader_parameter("energy", energy)
	_mat.set_shader_parameter("comfort", _comfort)

func _beat_off() -> void:
	_set_beat(0, 0.0, 0.0, 0.0, 0.0)
	_set_pulse(0.0)
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
	print("[luma] drop vs still: mitte %+.1f%% (max +20) oben %+.1f%% (max +35) | beat vs half: oben %+.1f%% mitte %+.1f%% (oben >=6 oder Bewegung)" % [_pct(d[0], s[0]), _pct(d[1], s[1]), _pct(be[1], h[1]), _pct(be[0], h[0])])

## --shot: still / beat (phase 0.02) / half (0.5) / drop (Spitze) / side. 14 Frames Einschwingen je Aufnahme.
func _shot_run() -> void:
	if _jk >= 0:
		_jerk_tick()
		return
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
			_set_beat(8, 0.02, DROP_PEAK, 1.0, 0.9)
		4:
			_measure("drop")
			_set_beat(9, 0.3, DROP_PEAK, 1.0, 0.9)
			_cam.rotation_degrees = Vector3(-6, 70, 0)
			_cam.fov = 75.0
		5:
			_measure("side")
			_report()
			_jerk_start(func(b: int, p: float) -> void: _set_beat(b, p, 0.0, 0.0, 0.5))
	_shot_i += 1

# --- Komfort-Pruefung (docs/worlds/beat_contract.md, Komfort-Regel 5) ---
# Nach den --shot-Aufnahmen: zwei Paare im Abstand 1/8 Beat, Licht eingefroren
# (nur beat_step + TIME laufen). mitte = 8.4375 -> 8.5625, schlag = 8.9375 -> 9.0625.
# Glatter Fluss: schlag/mitte ~ 1; Rasten/Stop-and-go auf dem Schlag gaebe >> 1.
const JK_NAME := "eclipse"
const JK_BEATS: Array[float] = [8.4375, 8.5625, 8.9375, 9.0625]
var _jk := -1
var _jk_f := 0
var _jk_set: Callable
var _jk_img: Array[Image] = []

func _jerk_start(set_fn: Callable) -> void:
	_jk_set = set_fn
	_jk = 0
	_jk_f = 0
	_cam.rotation_degrees = Vector3(-16, 0, 0)
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
	_jk_set.call(bi, b - float(bi))
	# Licht einfrieren: nur die Bewegung vergleichen.
	_mat.set_shader_parameter("beat_pulse", 0.3)
	_mat.set_shader_parameter("downbeat_pulse", 0.0)
	_mat.set_shader_parameter("beat_phase", 0.5)
	_mat.set_shader_parameter("bar_phase", 0.5)
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
