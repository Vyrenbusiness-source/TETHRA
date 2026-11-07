extends Node3D
## Demo: Welt-Thema "Sturm" (shaders/theme_storm.gdshader + storm_sky*.webp) mit
## Komfort-Kamera, dunkler Strecke im Sturm-Farbsatz, Pads und Noten zur
## Lesbarkeits-Kontrolle. Simuliert die Beat-Uniforms des Beat-Vertrags
## (docs/worlds/beat_contract.md) mit denselben Formeln wie mania_3d.gd.
## Ohne Argumente: 150 BPM, der Mahlstrom ratscht pro Schlag eine Kerbe weiter.
##   --bpm=<n> --speed=<rad/s Zusatz-Sog> --warp=<0..1> --comfort
##   --kiai (Kiai ab Schlag 8: Drop, dann alle 32 Schlaege wiederholt)
##   --shot [--shot-dir=<ordner>]  speichert storm_still / storm_beat (Phase
##        0.02) / storm_half (0.5) / storm_drop (Drop-Spitze) / storm_side
##        (Blick 70 Grad seitlich) als PNG, druckt die [luma]-Zeile, dann Ende.

const ROAD_Y := -1.6
const Z_LINE := 3.0
const Z_FAR := -46.0
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const SHOT_DIR := "C:/Users/Gexanx/AppData/Local/Temp/claude/a8d2df055934fb12/80c0c6f9-06b1-4222-ad93-57c1e121669d/scratchpad/storm"
const DIR := "res://assets_game/themes/storm/"
const METER := 4
const DROP_PEAK := 0.6
const DROP_HOLD := 0.3

# Farbsatz (siehe Kommentarblock in theme_storm.gdshader).
const C_ROAD := Color("#0b0b0f")
const C_LANE := Color("#2a2936")
const C_EDGE := Color("#8e89a8")
const C_EDGE_HI := Color("#c9c5dc")
const C_PAD := Color("#a29dbb")
const C_NOTE_A := Color("#e4e1ef")
const C_NOTE_B := Color("#8e89a8")

var _mat: ShaderMaterial
var _cam: Camera3D
var _edge_mats: Array[StandardMaterial3D] = []
var _note_mats: Array[ShaderMaterial] = []
var _t := 0.0
var _frames := 0
var _shot := false
var _shot_dir := SHOT_DIR
var _step := 0
var _bpm := 150.0
var _kiai := false
var _comfort := false
var _luma: Dictionary = {}
var _wait := 0
var _bench := false
var _bench_ref := false
var _bench_ms: Array[float] = []
var _bench_n := 0

func _ready() -> void:
	for a in OS.get_cmdline_args():
		if a == "--shot":
			_shot = true
		elif a == "--kiai":
			_kiai = true
		elif a == "--bench":
			_bench = true
		elif a == "--bench-ref":
			_bench = true
			_bench_ref = true
		elif a == "--comfort":
			_comfort = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	if _bench:
		_kiai = true
	_bpm = _arg_f("--bpm=", 150.0)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/theme_storm.gdshader")
	_mat.set_shader_parameter("tex_a", load(DIR + "storm_sky.webp"))
	_mat.set_shader_parameter("clouds_a", load(DIR + "storm_sky_clouds.webp"))
	_mat.set_shader_parameter("rain_a", load(DIR + "storm_sky_rain.webp"))
	_mat.set_shader_parameter("debris_a", load(DIR + "storm_sky_debris.webp"))
	_mat.set_shader_parameter("readability", 0.7)  # wie mania_3d._build_theme_sky
	if _bench_ref:
		# Referenz: Standard-Panorama-Shader mit derselben Textur, gleiche Szene.
		_mat.shader = load("res://shaders/sky_panorama.gdshader")
		_mat.set_shader_parameter("tex_a", load(DIR + "storm_sky.webp"))
	var sky := Sky.new()
	sky.sky_material = _mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#0e0e14")
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
		em.albedo_color = Color(0.02, 0.02, 0.025)
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
	# Anfliegende Noten bis zum Spawn-Horizont (Lesbarkeit vor dem Auge).
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
		_mat.set_shader_parameter("star_speed", _arg_f("--speed=", 0.0))
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

## Beat-Vertrag simulieren: beats = gezaehlte Schlaege (Bruchteil = beat_phase),
## since = Beats seit Kiai-Start (< 0 = kein Kiai). Formeln wie mania_3d.gd.
func _sim(beats: float, since: float) -> void:
	var phase := fposmod(beats, 1.0)
	var total := floorf(beats)
	var bar := fposmod(beats, float(METER)) / float(METER)
	var beat_ms := 60000.0 / _bpm
	var is_down := bar < 1.0 / METER
	var pulse := exp(-phase * beat_ms / 62.0) * (1.15 if is_down else 1.0)
	pulse = clampf(pulse, 0.0, 1.0)
	var drop := 0.0
	var kiai := 0.0
	if since >= 0.0:
		kiai = 1.0
		if since < 1.0:
			drop = DROP_PEAK * smoothstep(0.0, 1.0, since)
		elif since < 5.0:
			drop = lerpf(DROP_PEAK, DROP_HOLD, (since - 1.0) / 4.0)
		else:
			drop = DROP_HOLD
	if _comfort:
		drop *= 0.5
	_mat.set_shader_parameter("beat_pulse", pulse)
	_mat.set_shader_parameter("beat_phase", phase)
	_mat.set_shader_parameter("bar_phase", bar)
	_mat.set_shader_parameter("beat_step", total + 1.0 - pow(1.0 - phase, 4.0))
	_mat.set_shader_parameter("downbeat_pulse", exp(-bar * METER * 3.0))
	_mat.set_shader_parameter("kiai", kiai)
	_mat.set_shader_parameter("drop", drop)
	_mat.set_shader_parameter("energy", 0.6)
	_mat.set_shader_parameter("comfort", 1.0 if _comfort else 0.0)
	for em in _edge_mats:
		em.emission = C_EDGE.lerp(C_EDGE_HI, pulse)
		em.emission_energy_multiplier = 0.55 + 0.6 * pulse
	for nm in _note_mats:
		nm.set_shader_parameter("beat", pulse)

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _frames % 10 == 0 or _frames < 4:
		print("DBG f=", _frames, " ms=", Time.get_ticks_msec())
	if _bench:
		_bench_step(delta)
	if _shot:
		_shot_step()
		return
	var beats := _t * _bpm / 60.0
	var since := -1.0
	if _kiai and beats >= 8.0:
		since = fposmod(beats - 8.0, 32.0)
	_sim(beats, since)

## --bench / --bench-ref: vsync aus, max_fps 0, 120 Frames Warmup, 600 gemessen,
## druckt "[perf] <welt> fps_avg=... frame_ms_p99=...". Mit --resolution 1920x1080.
func _bench_step(delta: float) -> void:
	if _frames == 1:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if _frames <= 120:
		return
	_bench_ms.append(delta * 1000.0)
	if _bench_ms.size() >= 600:
		var sum := 0.0
		for v in _bench_ms:
			sum += v
		var sorted := _bench_ms.duplicate()
		sorted.sort()
		var p99: float = sorted[int(sorted.size() * 0.99)]
		print("[perf] %s fps_avg=%.1f frame_ms_p99=%.2f" % ["storm-ref(sky_panorama)" if _bench_ref else "storm", 1000.0 / (sum / _bench_ms.size()), p99])
		get_tree().quit(0)

## Schuesse: je Schritt Zustand setzen, 10 Frames warten, speichern.
## still = Ruhe (Phase 0.9), beat = 0.02 (Downbeat), half = 0.5, drop = Spitze.
func _shot_step() -> void:
	if _frames < 20:
		return
	if _wait > 0:
		_wait -= 1
		return
	match _step:
		0:
			_mat.set_shader_parameter("swirl_speed", 0.0)
			_sim(8.9, -1.0)
		1:
			_grab("still")
			_sim(8.02, -1.0)
		2:
			_grab("beat")
			_sim(9.5, -1.0)
		3:
			_grab("half")
			_sim(13.5, 1.0)
		4:
			_grab("drop")
			_sim(9.5, -1.0)
			_cam.rotation_degrees = Vector3(-8, 70, 0)
		5:
			_grab("side")
			var s: Dictionary = _luma["still"]
			var line := "[luma]"
			for k in ["still", "beat", "half", "drop"]:
				var v: Dictionary = _luma[k]
				line += " %s=mid %.4f top %.4f" % [k, v["mid"], v["top"]]
			var dm: float = (_luma["drop"]["mid"] - s["mid"]) / maxf(s["mid"], 0.0001) * 100.0
			var dt: float = (_luma["drop"]["top"] - s["top"]) / maxf(s["top"], 0.0001) * 100.0
			var bt: float = (_luma["beat"]["top"] - _luma["half"]["top"]) / maxf(_luma["half"]["top"], 0.0001) * 100.0
			line += "  | drop vs still: mid %+.1f%% (max 20) top %+.1f%% (max 35)  beat vs half top %+.1f%% (min 6)" % [dm, dt, bt]
			print(line)
			get_tree().quit(0)
	_step += 1
	_wait = 10

func _grab(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var sm := 0.0
	var nm := 0
	var st := 0.0
	var nt := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			var fx := float(x) / w
			var fy := float(y) / h
			if fx >= 0.25 and fx <= 0.75 and fy >= 0.42 and fy <= 0.87:
				sm += l
				nm += 1
			if fy < 0.42:
				st += l
				nt += 1
	_luma[tag] = {"mid": sm / maxf(nm, 1), "top": st / maxf(nt, 1)}
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var path := _shot_dir.path_join("storm_%s.png" % tag)
	img.save_png(path)
	if tag == "drop" or tag == "still":
		# 100-%-Crop (512x512) zur Schaerfe-Pruefung, am besten mit --resolution 1920x1080.
		var cr := img.get_region(Rect2i(int((w - 512) * 0.5), int((h - 512) * 0.0), mini(512, w), mini(512, h)))
		cr.save_png(_shot_dir.path_join("storm_%s_crop.png" % tag))
	print("shot: ", path)
