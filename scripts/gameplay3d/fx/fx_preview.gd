extends Node3D

## Demo fuer SkillFx: schwarzer Raum, Mania-Kamera, 128 BPM simuliert,
## Combo steigt automatisch (inkl. Miss + Kiai-Phase).
## Start: Godot --path . res://scenes/fx_preview.tscn [--shot] [--tier=N]
## --shot speichert nach SHOT_SEC ein PNG nach SHOT_PATH und beendet.

const SHOT_PATH := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/fx_preview.png"
const SHOT_SEC := 3.4
const BPM := 128.0
const Z_LINE := 3.0
const Z_FAR := -46.0
const ROAD_Y := -1.6
const RAIL_X: Array[float] = [-2.55, -0.85, 0.85, 2.55]
const HITS_PER_SEC := 7.0
const MISS_AT := 560
const THEME := Color(0.30, 0.85, 1.0)
const THEME_KIAI := Color(1.0, 0.45, 0.85)

var _fx: SkillFx
var _t := 0.0
var _combo := 0
var _hit_acc := 0.0
var _kiai := 0.0
var _shot := false
var _shot_done := false
var _rng := RandomNumberGenerator.new()
var _label: Label
var _shown_combo := -1


func _ready() -> void:
	_rng.seed = 1337
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a == "--shot":
			_shot = true
		elif a.begins_with("--tier="):
			var tier := clampi(int(a.substr(7)), 0, 4)
			_combo = [0, 60, 120, 230, 420][tier]
	if _shot and _combo == 0:
		_combo = 420
	_build_room()
	_fx = SkillFx.new()
	add_child(_fx)
	_fx.setup(RAIL_X, Z_LINE, Z_FAR, ROAD_Y, THEME, THEME_KIAI)


func _build_room() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.004, 0.010)
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.055
	env.glow_hdr_threshold = 0.92
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.78, 6.8)
	cam.rotation_degrees = Vector3(-15.2, 0.0, 0.0)
	cam.fov = 72.0
	add_child(cam)
	cam.make_current()

	# Referenz-Strecke (nur zur Beurteilung): dunkler Boden, Bahn-Guides,
	# Aussenkanten, Pads und ein paar Noten, die frei bleiben muessen.
	var road := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(7.2, absf(Z_FAR - Z_LINE) + 6.0)
	road.mesh = rp
	road.position = Vector3(0.0, ROAD_Y - 0.01, (Z_FAR + Z_LINE) * 0.5)
	road.material_override = _flat(Color(0.02, 0.025, 0.04), 0.0)
	add_child(road)
	for x in RAIL_X:
		var g := MeshInstance3D.new()
		var gp := PlaneMesh.new()
		gp.size = Vector2(0.02, absf(Z_FAR - Z_LINE))
		g.mesh = gp
		g.position = Vector3(x, ROAD_Y + 0.002, (Z_FAR + Z_LINE) * 0.5)
		g.material_override = _flat(Color(0.25, 0.3, 0.4), 0.25)
		add_child(g)
		var pad := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(1.25, 0.04, 0.32)
		pad.mesh = pb
		pad.position = Vector3(x, ROAD_Y + 0.02, Z_LINE)
		pad.material_override = _flat(Color(0.75, 0.85, 1.0), 0.5)
		add_child(pad)
	for sx in [-3.6, 3.6]:
		var e := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(0.10, 0.03, absf(Z_FAR) + 8.0)
		e.mesh = eb
		e.position = Vector3(sx, ROAD_Y, (Z_FAR + Z_LINE) * 0.5 + 2.0)
		e.material_override = _flat(THEME, 0.7)
		add_child(e)
	var notes := [[0, -2.0], [1, -7.0], [2, 0.6], [3, -12.0], [0, -18.0], [3, 1.8], [1, -26.0]]
	for n in notes:
		var nm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.5
		cm.height = 0.12
		nm.mesh = cm
		nm.position = Vector3(RAIL_X[int(n[0])], ROAD_Y + 0.32, float(n[1]))
		nm.material_override = _flat(Color(1.0, 1.0, 1.0), 0.9)
		add_child(nm)

	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.position = Vector2(18, 14)
	_label.add_theme_font_size_override(&"font_size", 18)
	_label.modulate = Color(1, 1, 1, 0.75)
	cl.add_child(_label)


func _flat(c: Color, emit: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * (1.0 + emit)
	return m


func _process(delta: float) -> void:
	_t += delta
	var beat_f := _t * BPM / 60.0
	var phase := fposmod(beat_f, 1.0)
	var env := exp(-phase * 5.0)

	# Auto-Combo: gleichmaessige Treffer, meist MAX/300.
	_hit_acc += delta * HITS_PER_SEC
	while _hit_acc >= 1.0:
		_hit_acc -= 1.0
		var col := _rng.randi_range(0, 3)
		if _combo >= MISS_AT:
			_fx.on_judge(col, 5)
			_combo = 0
			continue
		var q := 0 if _rng.randf() < 0.7 else (1 if _rng.randf() < 0.85 else 2)
		_fx.on_judge(col, q)
		_combo += 1
		if _combo % 100 == 0:
			_fx.on_milestone(_combo)

	# Kiai-Phase im Demo-Lauf zwischen Combo 300 und 450 (nicht im Screenshot).
	var kiai_target := 1.0 if (not _shot and _combo >= 300 and _combo < 450) else 0.0
	_kiai = move_toward(_kiai, kiai_target, delta * 1.5)
	_fx.update(delta, phase, env, _combo, 0.975, _kiai)

	if _combo != _shown_combo:
		_shown_combo = _combo
		_label.text = "SkillFx  combo %d  stufe %.2f" % [_combo, _fx.get_level()]

	if _shot and not _shot_done and _t >= SHOT_SEC:
		_shot_done = true
		_save_shot()


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT_PATH)
	print("fx_preview: shot ", SHOT_PATH, " err=", err)
	get_tree().quit()
