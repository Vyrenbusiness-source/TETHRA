extends Node3D

## Standard-Modus in echtem 3D — poliert:
##  - Notes fliegen ENTLANG DES KAMERASTRAHLS (Rhythia-Modell): ihre Bildschirm-
##    position liegt den ganzen Anflug exakt ueber dem Socket-Ring, sie wachsen nur.
##  - Shader-Notes (Verlauf + Rim + Halo), Socket-Ringe, Slider-Ribbons,
##    Sternenfeld, Map-Hintergrund im Tunnel, Schockwellen, Beat-Puls.
##  - Getroffene Notes verschwinden SOFORT (kurzer Burst), nichts bleibt stehen.
##  - Kein Komet mehr: Maus zielt, Hook-Tasten druecken im Ring — das ist alles.

const WORLD_SCALE := 1.0 / 32.0
const SPAWN_DEPTH := 45.0
const CAM_DISTANCE := 9.0
const BASE_FOV := 70.0
## Strahl-Faktor: s = 1 + Restzeit/preempt * RAY_K; Position = P * s (x/y),
## z = D * (1 - s). Bildschirmposition dadurch konstant ueber dem Socket.
const RAY_K := SPAWN_DEPTH / CAM_DISTANCE

const COL_ANCHOR := Color(0.15, 0.75, 1.0)
const COL_ANCHOR_KIAI := Color(1.0, 0.52, 0.14)
const COL_AIMED := Color(0.35, 1.0, 0.6)
const QUALITY_TEXT := { 0: "PERFECT", 1: "GOOD", 2: "MEH", 3: "MISS" }
const QUALITY_COLOR := {
	0: Color(1.0, 1.0, 1.0), 1: Color(0.4, 0.9, 1.0),
	2: Color(0.75, 0.72, 0.5), 3: Color(1.0, 0.28, 0.28),
}
const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var core := GameplayCore.new()
var _beatmap: Beatmap
var _use_audio := false
var _camera: Camera3D
var _tunnel_mat: ShaderMaterial
var _note_shader: Shader
var _note_square_shader: Shader
var _glow_shader: Shader
var _slider_shader: Shader
## index -> {root, socket, disc, rim, socket_mat, core}
var _anchors: Dictionary = {}
var _note_numbers: Array[int] = []
var _cursor_root: Node3D
var _cursor_ring_mat: ShaderMaterial
var _cursor_dot_mat: ShaderMaterial
var _frame_mats: Array[StandardMaterial3D] = []
var _star_mm: MultiMesh
var _star_seeds: Array[Vector3] = []
var _star_scroll := 0.0
## Per-Star Farbton-Versatz + globaler Beat-getriebener Farbzustand.
var _star_mat: ShaderMaterial
var _star_hues: Array[float] = []
var _star_hue_base := 0.0
var _star_beat_kick := 0.0
var _star_beat_idx := -1

var _cursor_osu := Vector2(256, 192)
var _cursor_smooth := Vector2(256, 192)
var _scroll := 0.0
var _kiai_mix := 0.0
var _red_tp_idx := 0
var _ended := false
var _keys_down := 0

# Song-Farbthema (aus dem Banner der Map extrahiert).
var _theme_col := COL_ANCHOR
var _theme_kiai := COL_ANCHOR_KIAI

# Musikreaktivitaet (geglaettet).
var _bass := 0.0
var _treble := 0.0
var _tunnel_node: MeshInstance3D
var _tunnel_spin := 0.0

# Combo-Eskalation.
var _last_milestone := 0
var _fov_kick := 0.0

# Musik-Events: Bass-Onset-Punch + Takt-Schub.
var _bass_avg := 0.0
var _punch := 0.0
var _punch_cooldown := 0.0
var _last_bar := -1
var _star_burst := 0.0

# Flow-Visuals: Orb-Schweif + Flugbahn-Guide durch die naechsten Noten.
var _trail_mesh: ImmediateMesh
var _trail_points: Array[Vector3] = []
var _guide_mesh: ImmediateMesh

# Slider-Visuals: index -> {node, pts: Array[Vector3], lens: Array[float],
#                           total: float, ball: MeshInstance3D}
var _slider_paths: Dictionary = {}

# Aktuelle Tunnel-Auslenkung (Notes fliegen im Tunnelzentrum mit).
var _tunnel_sway := Vector2.ZERO

var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer

var _debug_running := false
var _debug_start_usec := 0
var _debug_lead_in_ms := 0.0

var _hud: CanvasLayer
var _combo_label: Label
var _acc_label: Label
var _grade_label: Label
var _score_label: Label
var _miss_label: Label
var _notes_label: Label
var _pauses_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _bottom_fill: ColorRect
var _hp_fill: ColorRect
var _hint_label: Label
var _pause_menu: Control
var _pause_count := 0
var _song_len_ms := 1.0


func _ready() -> void:
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	core.setup(_beatmap, Settings.ar_override)
	core.no_fail = bool(GameSession.mods.get("NF", false))
	core.note_spawned.connect(_on_note_spawned)
	core.note_judged.connect(_on_note_judged)
	core.slider_started.connect(_on_slider_started)
	core.finished.connect(_on_finished)

	_note_shader = load("res://shaders/note_disc.gdshader")
	_note_square_shader = load("res://shaders/note_square.gdshader")
	_glow_shader = load("res://shaders/glow_dot.gdshader")
	_slider_shader = load("res://shaders/slider_body.gdshader")
	_extract_theme_color()
	_compute_note_numbers()
	_build_world()
	# Extrem clean: OS-Mauszeiger im Gameplay ausblenden (eigener Punkt-Cursor).
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	_build_hud()
	_build_sound()
	_start_clock()

	if DisplayServer.get_name() == "headless":
		_run_smoke_test()
		return
	if OS.get_cmdline_args().has("--shot"):
		_capture_after_first_note()


## Dominante Farbe des Map-Banners bestimmen: saettigungs-gewichteter
## Farbton-Mittelwert. Ergibt pro Song ein eigenes Farbthema; Kiai nutzt den
## Komplementaerton. Fallback: Standard-Cyan.
func _extract_theme_color() -> void:
	if not GameSession.has_selection():
		return
	var tex := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	img.resize(32, 24, Image.INTERPOLATE_BILINEAR)
	var acc := Vector2.ZERO
	var total_w := 0.0
	for y in 24:
		for x in 32:
			var c := img.get_pixel(x, y)
			var w := c.s * c.v
			acc += Vector2(cos(c.h * TAU), sin(c.h * TAU)) * w
			total_w += w
	if total_w < 4.0 or acc.length() < 1.0:
		return  # zu grau/uneindeutig -> Standardfarben behalten
	var hue := fposmod(atan2(acc.y, acc.x) / TAU, 1.0)
	_theme_col = Color.from_hsv(hue, 0.72, 1.0)
	_theme_kiai = Color.from_hsv(fposmod(hue + 0.5, 1.0), 0.8, 1.0)


func _compute_note_numbers() -> void:
	# osu-artige Combo-Nummern (reset bei New Combo, 1..9 zyklisch).
	var n := 0
	for obj in _beatmap.hit_objects:
		if obj.new_combo or n >= 9:
			n = 0
		n += 1
		_note_numbers.append(n)


# ---------------------------------------------------------------------------
# Laden / Uhr
# ---------------------------------------------------------------------------

func _load_beatmap() -> bool:
	var path := ""
	if GameSession.has_selection():
		path = GameSession.osz_path
	else:
		var lib := MapLibrary.new()
		if lib.scan() > 0:
			path = lib.mapsets[0].osz_path
	if path == "":
		push_error("Gameplay3D: keine Map verfuegbar.")
		return false
	var imp := OszImporter.import(path)
	if not imp.ok:
		push_error("Gameplay3D: " + imp.error)
		return false
	_beatmap = null
	if GameSession.difficulty_version != "":
		for d in imp.difficulties:
			if d.beatmap.version_name() == GameSession.difficulty_version:
				_beatmap = d.beatmap
				break
	if _beatmap == null:
		var idx := clampi(GameSession.difficulty_index, 0, imp.difficulties.size() - 1)
		_beatmap = imp.difficulties[idx].beatmap
	if _beatmap.hit_objects.is_empty():
		push_error("Gameplay3D: Map hat keine HitObjects.")
		return false
	var stream := OszImporter.load_audio_stream(path, _beatmap)
	if stream != null:
		SyncClock.play(stream, _beatmap.audio_lead_in())
		_use_audio = true
	return true


func _start_clock() -> void:
	if _use_audio:
		return
	_debug_lead_in_ms = 1000.0
	_debug_start_usec = Time.get_ticks_usec()
	_debug_running = true


func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - _debug_lead_in_ms


# ---------------------------------------------------------------------------
# Weltaufbau
# ---------------------------------------------------------------------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.004, 0.010)
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.82
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	add_child(we)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, CAM_DISTANCE)
	_camera.fov = BASE_FOV
	_camera.current = true
	add_child(_camera)

	# Tunnel-Tube.
	var tunnel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 13.0
	cyl.bottom_radius = 13.0
	cyl.height = 160.0
	cyl.radial_segments = 48
	cyl.rings = 1
	tunnel.mesh = cyl
	tunnel.rotation_degrees = Vector3(90, 0, 0)
	tunnel.position = Vector3(0, 0, -60.0)
	_tunnel_mat = ShaderMaterial.new()
	_tunnel_mat.shader = load("res://shaders/tunnel.gdshader")
	_tunnel_mat.set_shader_parameter("intensity", Settings.tunnel_intensity_value())
	# Song-Farbthema auf den Tunnel uebertragen.
	_tunnel_mat.set_shader_parameter("base_color", _theme_col * 0.5)
	_tunnel_mat.set_shader_parameter("kiai_color", _theme_kiai)
	tunnel.material_override = _tunnel_mat
	_tunnel_node = tunnel
	add_child(tunnel)

	_build_starfield()
	_build_playfield_frame()
	_build_cursor()

	# Orb-Schweif + Flugbahn-Guide (Flow-Identitaet).
	_trail_mesh = ImmediateMesh.new()
	var trail_inst := MeshInstance3D.new()
	trail_inst.mesh = _trail_mesh
	trail_inst.material_override = _flow_line_mat()
	add_child(trail_inst)
	_guide_mesh = ImmediateMesh.new()
	var guide_inst := MeshInstance3D.new()
	guide_inst.mesh = _guide_mesh
	guide_inst.material_override = _flow_line_mat()
	add_child(guide_inst)


func _build_starfield() -> void:
	# Warp-Sterne: fliegen aus der Tiefe an der Kamera vorbei (deterministisch).
	_star_mm = MultiMesh.new()
	_star_mm.transform_format = MultiMesh.TRANSFORM_3D
	_star_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.10, 0.10)
	_star_mm.mesh = q
	_star_mm.instance_count = 70
	for i in 70:
		var a := fmod(float(i) * 0.61803398875, 1.0) * TAU
		var rad := 3.5 + fmod(float(i) * 0.7548776662, 1.0) * 8.0
		var z0 := fmod(float(i) * 0.3819660113, 1.0) * 86.0
		_star_seeds.append(Vector3(cos(a) * rad, sin(a) * rad, z0))
		# Jeder Stern bekommt einen eigenen Farbton-Versatz -> Regenbogen-Warp.
		_star_hues.append(fmod(float(i) * 0.381966011, 1.0))
		_star_mm.set_instance_color(i, Color(0.7, 0.85, 1.0))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _star_mm
	var mat := ShaderMaterial.new()
	mat.shader = _glow_shader
	mat.set_shader_parameter("base_color", Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("intensity", 0.3)
	inst.material_override = mat
	_star_mat = mat
	add_child(inst)


func _build_playfield_frame() -> void:
	# Rhythia-Stil: nur vier weisse Eck-Klammern statt eines vollen Rahmens.
	var hw := 256.0 * WORLD_SCALE
	var hh := 192.0 * WORLD_SCALE
	var arm := 0.9
	var t := 0.045
	for corner in [Vector2(-hw, hh), Vector2(hw, hh), Vector2(-hw, -hh), Vector2(hw, -hh)]:
		var sx := -1.0 if corner.x > 0.0 else 1.0
		var sy := -1.0 if corner.y > 0.0 else 1.0
		# Horizontaler Arm.
		_add_bracket_box(Vector3(corner.x + sx * arm * 0.5, corner.y, 0), Vector3(arm, t, t))
		# Vertikaler Arm.
		_add_bracket_box(Vector3(corner.x, corner.y + sy * arm * 0.5, 0), Vector3(t, arm, t))


func _add_bracket_box(pos: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.97, 1.0)
	mat.emission_energy_multiplier = 0.9
	_frame_mats.append(mat)
	m.material_override = mat
	add_child(m)


## Additives Linien-/Ribbon-Material mit Vertexfarben.
func _flow_line_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	return m


## Orb-Schweif: der Spieler zieht eine leuchtende Spur (Flow-Identitaet).
func _update_trail(orb_world: Vector3) -> void:
	_trail_points.append(orb_world)
	if _trail_points.size() > 34:
		_trail_points.pop_front()
	_trail_mesh.clear_surfaces()
	if _trail_points.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_points.size()
	for i in n:
		var k := float(i) / float(n - 1)
		var width := 0.03 + 0.17 * k
		var dir3: Vector3
		if i < n - 1:
			dir3 = _trail_points[i + 1] - _trail_points[i]
		else:
			dir3 = _trail_points[i] - _trail_points[i - 1]
		var side := Vector3(-dir3.y, dir3.x, 0).normalized() * width
		if not side.is_finite() or side.length() < 0.0001:
			side = Vector3(0, width, 0)
		var c := _theme_col.lerp(Color(1, 1, 1), 0.35)
		var col := Color(c.r, c.g, c.b, 0.5 * k * k)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(_trail_points[i] + side)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(_trail_points[i] - side)
	_trail_mesh.surface_end()


## Flugbahn-Guide: leuchtende Linie durch die naechsten Noten-Positionen —
## macht aus verstreuten Zielen eine sichtbare Rennstrecke durch den Song.
func _update_guide(t: float) -> void:
	_guide_mesh.clear_surfaces()
	var pts: Array[Vector3] = []
	# Start an der aktuellen Orb-Position.
	pts.append(osu_to_world(_cursor_smooth, 0.015))
	var count := 0
	var i := core.open_index()
	while i < _beatmap.hit_objects.size() and count < 6:
		var obj := _beatmap.hit_objects[i]
		if not core.is_judged(i) and obj.kind != HitObject.Kind.SPINNER:
			if obj.time - t > core.preempt * 2.5:
				break
			pts.append(osu_to_world(obj.position(), 0.015))
			count += 1
		i += 1
	if pts.size() < 2:
		return
	# Sanfte Kurve (Catmull) durch die Punkte, nach vorn hin ausblendend.
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps_per_seg := 8
	var total_segs := pts.size() - 1
	for s in range(total_segs):
		var p0 := pts[maxi(s - 1, 0)]
		var p1 := pts[s]
		var p2 := pts[mini(s + 1, pts.size() - 1)]
		var p3 := pts[mini(s + 2, pts.size() - 1)]
		for j in range(steps_per_seg + (1 if s == total_segs - 1 else 0)):
			var u := float(j) / float(steps_per_seg)
			var u2 := u * u
			var u3 := u2 * u
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * u
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)
			var frac := (float(s) + u) / float(total_segs)
			var tangent := (p2 - p1)
			var side := Vector3(-tangent.y, tangent.x, 0).normalized() * 0.055
			if not side.is_finite() or side.length() < 0.0001:
				side = Vector3(0, 0.055, 0)
			var alpha := (1.0 - frac) * 0.4 + 0.08
			var c := _theme_col.lerp(Color(1, 1, 1), 0.2)
			var col := Color(c.r, c.g, c.b, alpha)
			_guide_mesh.surface_set_color(col)
			_guide_mesh.surface_add_vertex(p + side)
			_guide_mesh.surface_set_color(col)
			_guide_mesh.surface_add_vertex(p - side)
	_guide_mesh.surface_end()


func _build_cursor() -> void:
	# Rhythia-Stil: ein klarer weisser Punkt.
	_cursor_root = Node3D.new()
	add_child(_cursor_root)
	var dot := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.75, 0.75)
	dot.mesh = dq
	_cursor_dot_mat = ShaderMaterial.new()
	_cursor_dot_mat.shader = _glow_shader
	_cursor_dot_mat.set_shader_parameter("base_color", Color(1, 1, 1))
	_cursor_dot_mat.set_shader_parameter("intensity", 1.1)
	dot.material_override = _cursor_dot_mat
	_cursor_root.add_child(dot)


func _play_hit(pitch: float) -> void:
	if not Settings.hitsounds:
		return
	_hit_player.pitch_scale = pitch
	_hit_player.play()


func _play_miss() -> void:
	if not Settings.hitsounds:
		return
	_miss_player.play()


func _build_sound() -> void:
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = -7.0
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	_miss_player.volume_db = -6.0
	add_child(_miss_player)


func _note_mat(col: Color, fill: float, halo: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _note_shader
	m.set_shader_parameter("base_color", col)
	m.set_shader_parameter("rim_color", Color(1, 1, 1))
	m.set_shader_parameter("fill_alpha", fill)
	m.set_shader_parameter("halo_strength", halo)
	m.set_shader_parameter("rim_boost", 0.0)
	m.set_shader_parameter("master_alpha", 1.0)
	return m


# ---------------------------------------------------------------------------
# Koordinaten (Strahl-Modell)
# ---------------------------------------------------------------------------

func osu_to_world(osu: Vector2, z: float = 0.0) -> Vector3:
	return Vector3((osu.x - 256.0) * WORLD_SCALE, (192.0 - osu.y) * WORLD_SCALE, z)


func screen_to_osu(screen: Vector2) -> Vector2:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.z) < 0.0001:
		return _cursor_osu
	var t := -origin.z / dir.z
	var world := origin + dir * t
	return Vector2(world.x / WORLD_SCALE + 256.0, 192.0 - world.y / WORLD_SCALE)


func _approach_s(hit_time: float, t: float) -> float:
	return 1.0 + maxf(hit_time - t, 0.0) / core.preempt * RAY_K


## Anflugbahn: Die Note SPAWNT im Tunnel-Fluchtpunkt (Mitte, tief) und driftet
## in der ersten Haelfte des Anflugs auf den Kamerastrahl ihres Zielpunkts.
## Ab 50% preempt ist die Screen-Position exakt konstant ueber dem Socket
## (Masterplan-9.1-Regel) — Aim bleibt praezise lesbar, aber die Note kommt
## sichtbar AUS dem Tunnel.
func _anchor_world(osu_pos: Vector2, hit_time: float, t: float) -> Vector3:
	var p := osu_to_world(osu_pos)
	var s := _approach_s(hit_time, t)
	var progress := clampf(1.0 - (hit_time - t) / core.preempt, 0.0, 1.0)
	var k := smoothstep(0.0, 0.5, progress)
	# Fern (k~0): Note klebt am schwingenden Tunnelzentrum und fliegt mit.
	# Nah (k=1): exakt auf dem Strahl zum Socket — Aim bleibt unveraendert.
	var sway := _tunnel_sway * (1.0 - k)
	return Vector3(p.x * s * k + sway.x, p.y * s * k + sway.y, CAM_DISTANCE * (1.0 - s))


# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------

func _on_note_spawned(index: int) -> void:
	# Der bewaehrte 3D-Look: leuchtende Orbs (Emissive-Meshes) fliegen aus der
	# Tiefe. Bewusst KEINE osu-Elemente (keine Nummern, keine Slider-Balken).
	var obj := _beatmap.hit_objects[index]
	var kiai := _beatmap.is_kiai(obj.time)
	var col := _theme_kiai if kiai else _theme_col
	var r := core.radius * WORLD_SCALE
	var wpos := osu_to_world(obj.position())

	var root := Node3D.new()
	var disc_mat: StandardMaterial3D = null
	var rim_mat: StandardMaterial3D = null
	var core_mat: ShaderMaterial = null
	var note_sq_mat: ShaderMaterial = null
	var socket_sq_mat: ShaderMaterial = null

	if obj.kind == HitObject.Kind.SPINNER:
		var ring0 := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 3.4
		tor.outer_radius = 3.6
		ring0.mesh = tor
		ring0.rotation_degrees = Vector3(90, 0, 0)
		disc_mat = _emissive_mat(col, 1.2)
		ring0.material_override = disc_mat
		root.add_child(ring0)
	else:
		# Der bewaehrte Look: leuchtender ORB (gefuellte Scheibe + heller Rand).
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.92
		cyl.bottom_radius = r * 0.92
		cyl.height = 0.05
		disc.mesh = cyl
		disc.rotation_degrees = Vector3(90, 0, 0)
		disc_mat = _emissive_mat(col, 1.1)
		disc.material_override = disc_mat
		root.add_child(disc)

		var rim := MeshInstance3D.new()
		var tor2 := TorusMesh.new()
		tor2.inner_radius = r * 0.86
		tor2.outer_radius = r
		rim.mesh = tor2
		rim.rotation_degrees = Vector3(90, 0, 0)
		rim_mat = _emissive_mat(col.lerp(Color(1, 1, 1), 0.75), 1.5)
		rim.material_override = rim_mat
		root.add_child(rim)

		# Crisp WEISSER Kernpunkt: immer sichtbarer Zielmarker (ersetzt den
		# frueheren blauen Tiefen-Glow, der gestoert hat).
		var core_dot := MeshInstance3D.new()
		var cq := QuadMesh.new()
		cq.size = Vector2(r * 0.9, r * 0.9)
		core_dot.mesh = cq
		core_mat = ShaderMaterial.new()
		core_mat.shader = _glow_shader
		core_mat.set_shader_parameter("base_color", Color(1, 1, 1))
		core_mat.set_shader_parameter("intensity", 1.3)
		core_dot.material_override = core_mat
		core_dot.position = Vector3(0, 0, 0.01)
		root.add_child(core_dot)

	root.position = _anchor_world(obj.position(), obj.time, _time_ms())
	add_child(root)

	# Socket: duenner Ziel-Ring auf der Hit-Ebene, wird heller je naeher die Note.
	var socket: MeshInstance3D = null
	var socket_mat: StandardMaterial3D = null
	if obj.kind != HitObject.Kind.SPINNER:
		socket = MeshInstance3D.new()
		var ltor := TorusMesh.new()
		ltor.inner_radius = r * 1.04
		ltor.outer_radius = r * 1.10
		socket.mesh = ltor
		socket.rotation_degrees = Vector3(90, 0, 0)
		socket_mat = _emissive_mat(Color(0.45, 0.5, 0.6), 0.18)
		socket.material_override = socket_mat
		socket.position = Vector3(wpos.x, wpos.y, 0.0)
		add_child(socket)

		# Slider: echte Kurven-Roehre (Bezier/Perfect/Linear) auf der Ebene.
		# Der Laufball kommt erst beim Head-Hit (slider_started).
		if obj.kind == HitObject.Kind.SLIDER and obj.curve_points.size() >= 2:
			_build_slider_body(index, obj, col, r)

	_anchors[index] = {
		"root": root, "socket": socket, "disc": disc_mat, "rim": rim_mat,
		"socket_mat": socket_mat, "core": core_mat,
		"note_sq": note_sq_mat, "socket_sq": socket_sq_mat,
	}


## Echte Slider-Roehre: die tatsaechlich befahrene Kurve wird als leuchtende
## Energie-Leitbahn (ImmediateMesh-Ribbon) auf der Hit-Ebene gebaut — plus
## End-Kappe. Kein osu-Balken; ein 3D-Konduit mit fliessenden Streifen.
func _build_slider_body(index: int, obj: HitObject, col: Color, r: float) -> void:
	var osu_pts := (obj as HitSlider).path_points()
	if osu_pts.size() < 2:
		return
	var node := Node3D.new()
	var pts: Array[Vector3] = []
	var lens: Array[float] = []
	var total := 0.0
	for i in osu_pts.size():
		var w := osu_to_world(osu_pts[i])
		pts.append(Vector3(w.x, w.y, 0.03))
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		lens.append(total)

	var width := r * 1.05
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var tangent: Vector3
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == pts.size() - 1:
			tangent = pts[i] - pts[i - 1]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		tangent.z = 0.0
		if tangent.length() < 0.00001:
			tangent = Vector3.RIGHT
		tangent = tangent.normalized()
		var perp := Vector3(-tangent.y, tangent.x, 0.0) * (width * 0.5)
		var u: float = lens[i] / maxf(total, 0.001)
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(pts[i] + perp)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(pts[i] - perp)
	im.surface_end()

	var body := MeshInstance3D.new()
	body.mesh = im
	var mat := ShaderMaterial.new()
	mat.shader = _slider_shader
	mat.set_shader_parameter("body_color", col)
	mat.set_shader_parameter("edge_color", col.lerp(Color(1, 1, 1), 0.7))
	mat.set_shader_parameter("energy", 1.0)
	body.material_override = mat
	node.add_child(body)

	# End-Kappe.
	var end_ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = r * 0.72
	tor.outer_radius = r * 0.84
	end_ring.mesh = tor
	end_ring.rotation_degrees = Vector3(90, 0, 0)
	end_ring.material_override = _emissive_mat(col.lerp(Color(1, 1, 1), 0.4), 1.0)
	end_ring.position = pts[pts.size() - 1]
	node.add_child(end_ring)

	add_child(node)
	_slider_paths[index] = {
		"node": node, "pts": pts, "lens": lens, "total": total,
		"ball": null, "follow": null, "mat": mat, "flow": 0.0,
	}


## Punkt entlang einer Polyline bei Bruchteil frac (0..1).
func _point_along(pts: Array[Vector3], lens: Array[float], frac: float) -> Vector3:
	var target: float = clampf(frac, 0.0, 1.0) * lens[lens.size() - 1]
	for i in range(1, pts.size()):
		if lens[i] >= target:
			var seg := lens[i] - lens[i - 1]
			var k := 0.0 if seg <= 0.0 else (target - lens[i - 1]) / seg
			return pts[i - 1].lerp(pts[i], k)
	return pts[pts.size() - 1]


func _emissive_mat(col: Color, energy: float) -> StandardMaterial3D:
	# Shaded + schwarzes Albedo + Emission (unshaded wuerde EMISSION ignorieren).
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.03)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


## Kurze, cleane Judgement-Kuerzel: PF (nur mini), GD/OK mit FAST/SLOW darunter.
func _on_note_judged(index: int, result: Dictionary) -> void:
	var obj := _beatmap.hit_objects[index]
	var q: int = result.quality
	if q == GameplayCore.Quality.MISS:
		_play_miss()
	else:
		_play_hit([1.0, 0.891, 0.794][q])

	var text := ""
	var sub := ""
	match q:
		GameplayCore.Quality.PERFECT:
			text = "PF"
		GameplayCore.Quality.GOOD:
			text = "GD"
			sub = "SLOW" if result.get("late", false) else "FAST"
		GameplayCore.Quality.MEH:
			text = "OK"
			sub = "SLOW" if result.get("late", false) else "FAST"
		GameplayCore.Quality.MISS:
			text = "✕"
			match result.get("miss_kind", ""):
				"AIM": sub = "AIM"
				"EARLY": sub = "FAST"
	# Slider-Ende: "DROP" wenn losgelassen wurde.
	if result.get("slider_end", false):
		sub = "" if result.get("held", true) else "DROP"
		_free_slider_visuals(index)
	_spawn_popup(result.get("pos", obj.position()), text, QUALITY_COLOR[q], sub)

	# SOFORT weg: Hit -> kleiner Burst (erst ab Combo 25), Miss -> rot verglimmen.
	if _anchors.has(index):
		var entry: Dictionary = _anchors[index]
		_anchors.erase(index)
		if q != GameplayCore.Quality.MISS:
			if core.combo >= 25:
				_spawn_shockwave(obj.position(), _theme_kiai if _beatmap.is_kiai(obj.time) else _theme_col)
			(entry.root as Node3D).queue_free()
		else:
			_fade_out_miss(entry)
			_free_slider_visuals(index)
		if entry.socket != null:
			(entry.socket as MeshInstance3D).queue_free()

	# Combo-Meilensteine: sichtbare Belohnung (25/50/dann alle 100).
	if q == GameplayCore.Quality.MISS:
		_last_milestone = 0
	else:
		var c := core.combo
		if (c == 25 or c == 50 or (c >= 100 and c % 100 == 0)) and c != _last_milestone:
			_last_milestone = c
			_milestone_burst()
	_update_hud()


## Slider-Head getroffen: Note verschwindet, Laufball startet auf dem Pfad.
func _on_slider_started(index: int, quality: int) -> void:
	_play_hit([1.0, 0.891, 0.794][quality])
	if _anchors.has(index):
		var entry: Dictionary = _anchors[index]
		_anchors.erase(index)
		(entry.root as Node3D).queue_free()
		if entry.socket != null:
			(entry.socket as MeshInstance3D).queue_free()
	if _slider_paths.has(index):
		var sp: Dictionary = _slider_paths[index]
		# Heller Laufball (Kernpunkt).
		var ball := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.85, 0.85)
		ball.mesh = q
		var m := ShaderMaterial.new()
		m.shader = _glow_shader
		m.set_shader_parameter("base_color", Color(1, 1, 1))
		m.set_shader_parameter("intensity", 2.0)
		ball.material_override = m
		add_child(ball)
		sp["ball"] = ball
		# Follow-Ring um den Ball — zeigt EXAKT den Bereich, in dem der Cursor
		# bleiben muss (Core prueft 2.4x Radius, osu-korrekt).
		var follow := MeshInstance3D.new()
		var ftor := TorusMesh.new()
		ftor.inner_radius = core.radius * WORLD_SCALE * GameplayCore.FOLLOW_FACTOR * 0.94
		ftor.outer_radius = core.radius * WORLD_SCALE * GameplayCore.FOLLOW_FACTOR
		follow.mesh = ftor
		follow.rotation_degrees = Vector3(90, 0, 0)
		follow.material_override = _emissive_mat(Color(1, 1, 1), 1.4)
		add_child(follow)
		sp["follow"] = follow


func _free_slider_visuals(index: int) -> void:
	if _slider_paths.has(index):
		var sp: Dictionary = _slider_paths[index]
		(sp.node as Node3D).queue_free()
		if sp.ball != null:
			(sp.ball as MeshInstance3D).queue_free()
		if sp.get("follow") != null:
			(sp.follow as MeshInstance3D).queue_free()
		_slider_paths.erase(index)


func _milestone_burst() -> void:
	_fov_kick = 3.0
	var wave := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(6.0, 6.0)
	wave.mesh = q
	var m := _note_mat(_theme_col, 0.0, 1.0)
	m.set_shader_parameter("rim_boost", 1.6)
	wave.material_override = m
	wave.position = Vector3(0, 0, 0.1)
	add_child(wave)
	var tw := create_tween()
	tw.tween_property(wave, "scale", Vector3.ONE * 3.4, 0.45)
	tw.parallel().tween_method(
		func(v): m.set_shader_parameter("master_alpha", v), 0.9, 0.0, 0.45)
	tw.tween_callback(wave.queue_free)


func _spawn_shockwave(osu_pos: Vector2, col: Color) -> void:
	var r := core.radius * WORLD_SCALE
	# Klein und schnell — clean, kein Riesen-Effekt.
	var wave := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.4, r * 2.4)
	wave.mesh = q
	var m := _note_mat(col, 0.0, 0.6)
	m.set_shader_parameter("rim_boost", 1.0)
	wave.material_override = m
	wave.position = osu_to_world(osu_pos, 0.06)
	add_child(wave)
	var tw := create_tween()
	tw.tween_property(wave, "scale", Vector3.ONE * 1.5, 0.12)
	tw.parallel().tween_method(
		func(v): m.set_shader_parameter("master_alpha", v), 0.9, 0.0, 0.12)
	tw.tween_callback(wave.queue_free)


func _fade_out_miss(entry: Dictionary) -> void:
	var root: Node3D = entry.root
	# Rot einfaerben (Raute via Shader, Spinner via Emission).
	var note_sq: ShaderMaterial = entry.get("note_sq")
	if note_sq != null:
		note_sq.set_shader_parameter("base_color", Color(1.0, 0.25, 0.25))
	var disc_mat: StandardMaterial3D = entry.get("disc")
	if disc_mat != null:
		disc_mat.emission = Color(1.0, 0.25, 0.25)
	var tw := create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * 0.01, 0.13)
	tw.parallel().tween_property(root, "position:y", root.position.y - 0.4, 0.13)
	tw.tween_callback(root.queue_free)


## Mini-Popup, clean mittig auf der Note: Hauptkuerzel + optional FAST/SLOW.
func _spawn_popup(osu_pos: Vector2, text: String, col: Color, sub: String = "") -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = Color(col.r, col.g, col.b, 0.95)
	label.font_size = 64
	label.pixel_size = 0.0085
	label.outline_size = 14
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = osu_to_world(osu_pos, 0.5)
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 0.35, 0.32)
	tw.tween_property(label, "modulate:a", 0.0, 0.32).set_delay(0.08)
	tw.chain().tween_callback(label.queue_free)
	if sub != "":
		var s := Label3D.new()
		s.text = sub
		s.modulate = Color(0.75, 0.78, 0.86, 0.9)
		s.font_size = 36
		s.pixel_size = 0.0085
		s.outline_size = 10
		s.outline_modulate = Color(0, 0, 0, 0.85)
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.no_depth_test = true
		s.position = osu_to_world(osu_pos, 0.5) + Vector3(0, -0.45, 0)
		add_child(s)
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(s, "position:y", s.position.y + 0.3, 0.32)
		tw2.tween_property(s, "modulate:a", 0.0, 0.32).set_delay(0.08)
		tw2.chain().tween_callback(s.queue_free)


# ---------------------------------------------------------------------------
# Input: Maus zielt, Hook-Tasten druecken
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended:
		return
	if event is InputEventMouseMotion:
		_cursor_osu = screen_to_osu(event.position)
	elif event is InputEventKey and not event.echo:
		if Settings.is_hook_key(event.keycode):
			if event.pressed:
				_keys_down += 1
				core.set_holding(true)
				core.handle_click(_time_ms(), _cursor_osu)
			else:
				_keys_down = maxi(_keys_down - 1, 0)
				if _keys_down == 0:
					core.set_holding(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _ended:
			_toggle_pause(true)


# ---------------------------------------------------------------------------
# Frame-Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or _beatmap == null:
		return
	var t := _time_ms()
	core.update(t, _cursor_osu)

	# --- Musikreaktivitaet zuerst: treibt Notes, Slider, Tunnel, Sterne. ---
	var bass_raw := SyncClock.band_energy(30.0, 250.0)
	var treble_raw := SyncClock.band_energy(2000.0, 8000.0)
	_bass = maxf(bass_raw, move_toward(_bass, 0.0, delta * 2.2))
	_treble = maxf(treble_raw, move_toward(_treble, 0.0, delta * 3.0))

	# Bass-ONSET (Kick-Schlag): kurzer Punch auf Kamera, Klammern und Tunnel.
	_bass_avg = lerpf(_bass_avg, bass_raw, minf(delta * 1.5, 1.0))
	_punch_cooldown = maxf(_punch_cooldown - delta, 0.0)
	if bass_raw - _bass_avg > 0.16 and _punch_cooldown <= 0.0:
		_punch = 1.0
		_punch_cooldown = 0.12
		_fov_kick = maxf(_fov_kick, 1.3)
	_punch = move_toward(_punch, 0.0, delta * 6.0)

	# Takt-Anfang (Bar aus rotem TimingPoint): Sternen-Warp-Schub.
	var bar := _current_bar(t)
	if bar != _last_bar:
		_last_bar = bar
		_star_burst = 1.0
	_star_burst = move_toward(_star_burst, 0.0, delta * 2.5)
	var pulse: float = maxf(maxf(_beat_pulse(t), _bass * 1.05), _punch)
	var kiai_now := _beatmap.is_kiai(t)
	_kiai_mix = move_toward(_kiai_mix, 1.0 if kiai_now else 0.0, delta * 2.5)
	var bpm_k := clampf(_current_bpm() / 160.0, 0.5, 1.7)

	var open_idx := core.open_index()
	var aimed := false
	if open_idx < _beatmap.hit_objects.size():
		var open_obj := _beatmap.hit_objects[open_idx]
		aimed = _cursor_osu.distance_to(open_obj.position()) <= core.radius

	for index in _anchors:
		var obj := _beatmap.hit_objects[index]
		var entry: Dictionary = _anchors[index]
		(entry.root as Node3D).position = _anchor_world(obj.position(), obj.time, t)
		var until := obj.time - t
		var progress := clampf(1.0 - until / core.preempt, 0.0, 1.0)
		# Orb-Rand blitzt im Klick-Fenster auf — plus Beat/Bass-Puls.
		var rim_mat: StandardMaterial3D = entry.rim
		if rim_mat != null:
			var in_window: bool = absf(until) <= core.w_meh and index == open_idx
			rim_mat.emission_energy_multiplier = (2.6 if in_window else 1.5) + pulse * 0.8
		# Weisser Kernpunkt pulsiert mit dem Beat (Takt sichtbar).
		var core_mat: ShaderMaterial = entry.get("core")
		if core_mat != null:
			core_mat.set_shader_parameter("intensity", 0.7 + pulse * 0.6 + progress * 0.35)
		# Socket-Ring: dezent, heller je naeher; aktuell weiss, gezielt gruen.
		var socket_mat: StandardMaterial3D = entry.get("socket_mat")
		if socket_mat != null:
			var is_current: bool = index == open_idx
			if is_current and aimed:
				socket_mat.emission = COL_AIMED
			elif is_current:
				socket_mat.emission = Color(1, 1, 1)
			socket_mat.emission_energy_multiplier = 0.18 + progress * 0.8 + pulse * 0.3 + (0.5 if is_current else 0.0)

	# Slider-Roehren: fliessende Energie + Beat-Puls auf den Kanten.
	for s_index in _slider_paths:
		var sp: Dictionary = _slider_paths[s_index]
		var s_mat: ShaderMaterial = sp.get("mat")
		if s_mat != null:
			sp["flow"] = float(sp.get("flow", 0.0)) + delta * (6.0 + bpm_k * 4.0 + _treble * 10.0)
			s_mat.set_shader_parameter("flow", sp["flow"])
			s_mat.set_shader_parameter("beat", pulse)
			s_mat.set_shader_parameter("energy", 0.85 + _bass * 0.6 + _kiai_mix * 0.5)

	# Cursor: sanft nachziehen; gruen wenn korrekt gezielt.
	_cursor_smooth = _cursor_smooth.lerp(_cursor_osu, minf(delta * 28.0, 1.0))
	_cursor_root.position = osu_to_world(_cursor_smooth, 0.08)
	_update_trail(osu_to_world(_cursor_smooth, 0.06))
	_update_guide(t)
	_cursor_dot_mat.set_shader_parameter("base_color", COL_AIMED if aimed else Color(1, 1, 1))

	# Tunnel / Sterne / Beat — Tempo folgt BPM + Bass, Kiai eskaliert.
	_scroll += delta * (3.0 + bpm_k * 4.5 + _bass * 9.0 + _kiai_mix * 6.0)
	_tunnel_mat.set_shader_parameter("scroll", _scroll)
	_tunnel_mat.set_shader_parameter("beat_pulse", pulse)
	_tunnel_mat.set_shader_parameter("kiai", _kiai_mix)
	_tunnel_mat.set_shader_parameter("intensity",
		Settings.tunnel_intensity_value() * (0.45 + 0.75 * _bass + 0.55 * _kiai_mix))

	# Flug-Gefuehl: Wir bleiben IMMER exakt in der Tunnelmitte. Die Strecke vor
	# uns KRUEMMT sich (Shader-bend am fernen Ende) hoch/runter/links/rechts,
	# die Kamera bankt minimal mit, ferne Notes folgen der Kurve. Hit-Ebene und
	# Aim-Geometrie bleiben unangetastet (Regel 8).
	var sway_t := t / 1000.0
	var bend_amp := 1.4 + bpm_k * 0.9 + _bass * 2.6 + _kiai_mix * 2.6
	_tunnel_sway = Vector2(
		sin(sway_t * 0.31) * bend_amp,
		sin(sway_t * 0.23 + 1.7) * bend_amp * 0.75)
	_tunnel_node.position = Vector3(0.0, 0.0, -60.0)
	_tunnel_mat.set_shader_parameter("bend", _tunnel_sway)
	_tunnel_spin += delta * (0.05 + bpm_k * 0.06 + _kiai_mix * 0.25 + _treble * 0.2)
	# Spin um die EIGENE Roehrenachse (Euler-rotation.y wuerde die Roehre
	# seitlich wegkippen — "neben dem Tunnel stehen").
	_tunnel_node.basis = Basis(Vector3.RIGHT, deg_to_rad(90.0)) * Basis(Vector3.UP, _tunnel_spin)
	# Sanftes Banking in Kurvenrichtung (reine Kamera-Rolle, Mapping bleibt exakt).
	_camera.rotation.z = -_tunnel_sway.x * 0.022

	_fov_kick = move_toward(_fov_kick, 0.0, delta * 9.0)
	_camera.fov = BASE_FOV + _kiai_mix * 4.0 + _bass * 3.0 + _fov_kick
	for fm in _frame_mats:
		fm.emission_energy_multiplier = 0.35 + pulse * 1.0 + _punch * 1.3 + _kiai_mix * 0.4
	_update_starfield(delta, t)

	# Slider-Laufball entlang des Pfads (mit Ping-Pong bei Wiederholungen).
	for index in _slider_paths:
		var sp: Dictionary = _slider_paths[index]
		if sp.ball == null:
			continue
		var s_obj := _beatmap.hit_objects[index]
		var dur: float = maxf(s_obj.total_duration_ms(), 1.0)
		var prog: float = clampf((t - s_obj.time) / dur, 0.0, 1.0)
		var slides: int = maxi(s_obj.slides, 1)
		var leg := prog * slides
		var leg_i := int(leg)
		var frac := leg - leg_i
		if leg_i % 2 == 1:
			frac = 1.0 - frac
		var ball_pos := _point_along(sp.pts, sp.lens, frac)
		(sp.ball as MeshInstance3D).position = ball_pos + Vector3(0, 0, 0.05)
		if sp.get("follow") != null:
			(sp.follow as MeshInstance3D).position = ball_pos + Vector3(0, 0, 0.04)

	if core.failed:
		_show_results(true)
	_update_hud()


func _update_starfield(delta: float, t: float) -> void:
	# --- Beat-Erkennung: neuer Beat => Farbe rotiert + Speed-Burst. ---
	var beat_idx := _current_beat_index(t)
	if beat_idx != _star_beat_idx:
		_star_beat_idx = beat_idx
		# Farbrad springt pro Beat weiter; in Kiai groessere Spruenge.
		_star_hue_base = fposmod(_star_hue_base + 0.13 + _kiai_mix * 0.09, 1.0)
		_star_beat_kick = 1.0
	_star_beat_kick = move_toward(_star_beat_kick, 0.0, delta * 3.5)

	# Hoehen + Beat-Kick treiben die Sterne an -> ruckartiger Warp auf dem Beat.
	var speed := 6.0 + _treble * 16.0 + _kiai_mix * 7.0 + _star_beat_kick * 55.0 + _star_burst * 28.0
	_star_scroll += delta * speed

	# Globale Helligkeit pulsiert mit dem Beat; Saettigung steigt in Kiai.
	_star_mat.set_shader_parameter("intensity", 0.30 + _star_beat_kick * 0.9 + _kiai_mix * 0.5)
	var sat := 0.55 + _kiai_mix * 0.35
	for i in 70:
		var seed := _star_seeds[i]
		var z := fmod(seed.z + _star_scroll, 86.0) - 80.0
		_star_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(seed.x, seed.y, z)))
		# Farbton = globaler Beat-Zustand + fester Stern-Versatz -> Regenbogenfluss.
		var hue := fposmod(_star_hue_base + _star_hues[i], 1.0)
		var val := 0.85 + _star_beat_kick * 0.15
		_star_mm.set_instance_color(i, Color.from_hsv(hue, sat, val))


## Fortlaufender Beat-Index (roter TimingPoint als Nullpunkt), fuer Beat-Trigger.
func _current_beat_index(t: float) -> int:
	var tps := _beatmap.timing_points
	var i := _red_tp_idx
	while i >= 0 and i < tps.size() and not tps[i].uninherited:
		i -= 1
	if i < 0 or i >= tps.size() or tps[i].beat_length <= 0.0:
		return 0
	return int(floor((t - tps[i].time) / tps[i].beat_length))


## Takt-Index (Bar) zur Zeit t — aus beatLength * meter des roten TimingPoints.
func _current_bar(t: float) -> int:
	var tps := _beatmap.timing_points
	var i := _red_tp_idx
	while i >= 0 and i < tps.size() and not tps[i].uninherited:
		i -= 1
	if i < 0 or i >= tps.size() or tps[i].beat_length <= 0.0:
		return -1
	var bar_len := tps[i].beat_length * float(maxi(tps[i].meter, 1))
	return int(floor((t - tps[i].time) / bar_len))


## BPM des aktuell gueltigen roten TimingPoints (nutzt den _red_tp_idx-Cache).
func _current_bpm() -> float:
	var tps := _beatmap.timing_points
	var i := _red_tp_idx
	while i >= 0 and i < tps.size() and not tps[i].uninherited:
		i -= 1
	if i < 0 or i >= tps.size() or tps[i].beat_length <= 0.0:
		return 120.0
	return 60000.0 / tps[i].beat_length


func _beat_pulse(t: float) -> float:
	var tps := _beatmap.timing_points
	while _red_tp_idx + 1 < tps.size() and tps[_red_tp_idx + 1].time <= t:
		_red_tp_idx += 1
	var i := _red_tp_idx
	while i >= 0 and not tps[i].uninherited:
		i -= 1
	if i < 0 or tps[i].beat_length <= 0.0:
		return 0.0
	var phase := fposmod(t - tps[i].time, tps[i].beat_length) / tps[i].beat_length
	return pow(1.0 - phase, 2.0)


# ---------------------------------------------------------------------------
# HUD / Pause / Results
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	# Rhythia-Layout: Typo-Spalten links/rechts NEBEN dem Feld, Zeit + duenner
	# Fortschritt oben, gruener Fortschrittsbalken unten. Alles auf Schwarz.
	_hud = CanvasLayer.new()
	add_child(_hud)
	_song_len_ms = maxf(_beatmap.duration_ms(), 1.0)

	var title := Label.new()
	var unranked := "  ·  UNRANKED" if Settings.ar_override >= 0.0 else ""
	title.text = "%s — %s [%s]%s" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name(), unranked]
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -460
	title.offset_right = 460
	title.offset_top = 16
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_hud.add_child(title)

	_time_label = Label.new()
	_time_label.anchor_left = 0.5
	_time_label.anchor_right = 0.5
	_time_label.offset_left = -200
	_time_label.offset_right = 200
	_time_label.offset_top = 44
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 16)
	_time_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	_hud.add_child(_time_label)

	# Duenner Fortschritt oben.
	var top_bg := ColorRect.new()
	top_bg.anchor_left = 0.5
	top_bg.anchor_right = 0.5
	top_bg.offset_left = -300
	top_bg.offset_right = 300
	top_bg.offset_top = 72
	top_bg.offset_bottom = 76
	top_bg.color = Color(1, 1, 1, 0.10)
	_hud.add_child(top_bg)
	_top_fill = ColorRect.new()
	_top_fill.anchor_left = 0.5
	_top_fill.anchor_right = 0.5
	_top_fill.offset_left = -300
	_top_fill.offset_right = -300
	_top_fill.offset_top = 72
	_top_fill.offset_bottom = 76
	_top_fill.color = Color(0.9, 0.92, 1.0, 0.85)
	_hud.add_child(_top_fill)

	# Linke Spalte: COMBO, GRADE, ACCURACY, PAUSES.
	_combo_label = _stat_value(Vector2(0.085, 0.30), 40)
	_grade_label = _stat_value(Vector2(0.085, 0.50), 46)
	_stat_caption(Vector2(0.085, 0.62), "ACCURACY")
	_acc_label = _stat_value(Vector2(0.085, 0.66), 26)
	_stat_caption(Vector2(0.085, 0.80), "PAUSES")
	_pauses_label = _stat_value(Vector2(0.085, 0.84), 26)

	# Rechte Spalte: SCORE, MISSES, NOTES.
	_stat_caption(Vector2(0.915, 0.28), "SCORE")
	_score_label = _stat_value(Vector2(0.915, 0.32), 30)
	_stat_caption(Vector2(0.915, 0.50), "MISSES")
	_miss_label = _stat_value(Vector2(0.915, 0.54), 26)
	_stat_caption(Vector2(0.915, 0.72), "NOTES")
	_notes_label = _stat_value(Vector2(0.915, 0.76), 26)

	# HP: KLEINE cleane Bar mittig oben (nichts liegt ueber den Noten) —
	# identisch zum Mania-Modus.
	var hp_bg := ColorRect.new()
	hp_bg.anchor_left = 0.5
	hp_bg.anchor_right = 0.5
	hp_bg.offset_left = -110
	hp_bg.offset_right = 110
	hp_bg.offset_top = 82
	hp_bg.offset_bottom = 86
	hp_bg.color = Color(1, 1, 1, 0.10)
	_hud.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.anchor_left = 0.5
	_hp_fill.anchor_right = 0.5
	_hp_fill.offset_left = -110
	_hp_fill.offset_right = 110
	_hp_fill.offset_top = 82
	_hp_fill.offset_bottom = 86
	_hp_fill.color = Color(0.3, 1.0, 0.6, 0.85)
	_hud.add_child(_hp_fill)

	_hint_label = Label.new()
	_hint_label.text = "Maus zielen · %s/%s druecken, wenn die Note im Ring landet · Slider: halten · Esc = Pause" % [
		OS.get_keycode_string(Settings.key_hook1), OS.get_keycode_string(Settings.key_hook2)]
	_hint_label.anchor_left = 0.5
	_hint_label.anchor_right = 0.5
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -520
	_hint_label.offset_right = 520
	_hint_label.offset_top = -46
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.8))
	_hud.add_child(_hint_label)
	var tw := create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 1.5)


func _stat_caption(anchor_pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.anchor_left = anchor_pos.x
	l.anchor_right = anchor_pos.x
	l.anchor_top = anchor_pos.y
	l.anchor_bottom = anchor_pos.y
	l.offset_left = -120
	l.offset_right = 120
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	_hud.add_child(l)


func _stat_value(anchor_pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.anchor_left = anchor_pos.x
	l.anchor_right = anchor_pos.x
	l.anchor_top = anchor_pos.y
	l.anchor_bottom = anchor_pos.y
	l.offset_left = -120
	l.offset_right = 120
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	_hud.add_child(l)
	return l


func _update_hud() -> void:
	if _combo_label == null:
		return
	_combo_label.text = "%dx" % core.combo
	var g := core.grade()
	_grade_label.text = g
	_grade_label.add_theme_color_override("font_color", GRADE_COLOR.get(g, Color.WHITE))
	_acc_label.text = "%.1f%%" % (core.accuracy() * 100.0)
	_pauses_label.text = str(_pause_count)
	_score_label.text = "%d" % core.score
	_miss_label.text = str(core.n_miss)
	var judged := core.n300 + core.n100 + core.n50 + core.n_miss
	_notes_label.text = "%d/%d" % [judged, _beatmap.hit_objects.size()]
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.offset_right = -300 + 600.0 * (t / _song_len_ms)
	_hp_fill.offset_right = -110 + 220.0 * core.hp
	_hp_fill.color = Color(0.3, 1.0, 0.6, 0.85) if core.hp > 0.3 else Color(1.0, 0.35, 0.3, 0.9)


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


func _toggle_pause(paused: bool) -> void:
	if paused:
		if _pause_menu == null:
			_build_pause_menu()
		_pause_count += 1
		_pause_menu.visible = true
		get_tree().paused = true
		SyncClock.pause()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_menu != null:
			_pause_menu.visible = false
		get_tree().paused = false
		SyncClock.resume()
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_hud.add_child(_pause_menu)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_pause_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.62)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Pause"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	for def in [
		["Weiter", func(): _toggle_pause(false)],
		["Retry", func(): _restart()],
		["Einstellungen", func(): _open_settings()],
		["Song-Browser", func(): _back_to_browser()],
	]:
		var b := Button.new()
		b.text = def[0]
		b.custom_minimum_size = Vector2(260, 46)
		b.add_theme_font_size_override("font_size", 18)
		UiTheme.style_button(b, def[0] == "Weiter")
		b.pressed.connect(def[1])
		vb.add_child(b)

	_pause_menu.gui_input.connect(func(ev):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_toggle_pause(false))


func _open_settings() -> void:
	var panel := SettingsPanel.new()
	panel.closed.connect(func():
		_tunnel_mat.set_shader_parameter("intensity", Settings.tunnel_intensity_value()))
	_hud.add_child(panel)


func _restart() -> void:
	get_tree().paused = false
	SyncClock.stop()
	get_tree().reload_current_scene()


func _back_to_browser() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _on_finished(_stats: Dictionary) -> void:
	_show_results(false)


func _show_results(is_fail: bool) -> void:
	if _ended:
		return
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	var s := core.stats()
	var unranked := Settings.ar_override >= 0.0 or bool(GameSession.mods.get("NF", false))
	s["unranked"] = unranked

	var pp := -1.0
	if not is_fail and not unranked and GameSession.has_selection():
		var pp_res := StarService.pp_for(
			GameSession.osz_path, GameSession.osu_filename,
			s.n300, s.n100, s.n50, s.n_miss, s.max_combo)
		if pp_res.has("pp"):
			pp = float(pp_res.pp)
	s["pp"] = pp

	var save := {}
	if GameSession.has_selection():
		save = ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s)
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s)

	_build_results_screen(is_fail, s, pp, unranked, bool(save.get("is_new_best", false)))


func _build_results_screen(is_fail: bool, s: Dictionary, pp: float, unranked: bool, new_best: bool) -> void:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(screen)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.015, 0.03, 0.94)
	screen.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.custom_minimum_size = Vector2(640, 0)
	center.add_child(vb)

	var map_label := Label.new()
	map_label.text = "%s — %s  [%s]" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()]
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_label.add_theme_font_size_override("font_size", 18)
	map_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	vb.add_child(map_label)

	var head := Label.new()
	head.text = "FAILED" if is_fail else str(s.grade)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 120 if not is_fail else 72)
	var head_col: Color = Color(1.0, 0.3, 0.3) if is_fail else GRADE_COLOR.get(str(s.grade), Color.WHITE)
	head.add_theme_color_override("font_color", head_col)
	head.add_theme_color_override("font_shadow_color", Color(head_col.r, head_col.g, head_col.b, 0.35))
	head.add_theme_constant_override("shadow_offset_y", 4)
	vb.add_child(head)

	var badges := ""
	if new_best:
		badges += "NEW BEST!   "
	if unranked:
		badges += "UNRANKED (AR-Override)"
	if badges != "":
		var badge_label := Label.new()
		badge_label.text = badges.strip_edges()
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_label.add_theme_font_size_override("font_size", 20)
		badge_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if new_best else Color(0.8, 0.6, 1.0))
		vb.add_child(badge_label)

	var score_label := Label.new()
	var pp_text := ("%.1f pp" % pp) if pp >= 0.0 else "pp: —"
	score_label.text = "Score %d    ·    %.2f%%    ·    %s" % [int(s.score), s.accuracy * 100.0, pp_text]
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 30)
	vb.add_child(score_label)

	var counts := HBoxContainer.new()
	counts.alignment = BoxContainer.ALIGNMENT_CENTER
	counts.add_theme_constant_override("separation", 34)
	vb.add_child(counts)
	for def in [
		["PERFECT", s.n300, QUALITY_COLOR[0]], ["GOOD", s.n100, QUALITY_COLOR[1]],
		["MEH", s.n50, QUALITY_COLOR[2]], ["MISS", s.n_miss, QUALITY_COLOR[3]],
	]:
		var cvb := VBoxContainer.new()
		var num := Label.new()
		num.text = str(def[1])
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 34)
		num.add_theme_color_override("font_color", def[2])
		cvb.add_child(num)
		var cap := Label.new()
		cap.text = def[0]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
		cvb.add_child(cap)
		counts.add_child(cvb)

	var combo_label := Label.new()
	combo_label.text = "Max-Combo %dx" % int(s.max_combo)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(combo_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	vb.add_child(btns)
	var retry := Button.new()
	retry.text = "Retry"
	retry.custom_minimum_size = Vector2(180, 50)
	retry.add_theme_font_size_override("font_size", 18)
	UiTheme.style_button(retry, true)
	retry.pressed.connect(_restart)
	btns.add_child(retry)
	var back := Button.new()
	back.text = "Song-Browser"
	back.custom_minimum_size = Vector2(180, 50)
	back.add_theme_font_size_override("font_size", 18)
	UiTheme.style_button(back)
	back.pressed.connect(_back_to_browser)
	btns.add_child(back)


# ---------------------------------------------------------------------------
# Headless / Screenshot
# ---------------------------------------------------------------------------

func _run_smoke_test() -> void:
	print("=== Gameplay3D Smoke-Test ===")
	print("Map: %s - %s [%s], %d Objekte, preempt %.0f, Radius %.1f" % [
		_beatmap.artist(), _beatmap.title(), _beatmap.version_name(),
		_beatmap.hit_objects.size(), core.preempt, core.radius])
	var osu := Vector2(100, 300)
	var w := osu_to_world(osu)
	var back := Vector2(w.x / WORLD_SCALE + 256.0, 192.0 - w.y / WORLD_SCALE)
	assert(back.distance_to(osu) < 0.001)
	# Strahl-Modell: bei hit ist s=1 -> Position exakt auf der Ebene.
	var obj := _beatmap.hit_objects[0]
	var at_hit := _anchor_world(obj.position(), obj.time, obj.time)
	var plane := osu_to_world(obj.position())
	print("Strahl @hit: %s (Ebene: %s)" % [at_hit, plane])
	assert(at_hit.distance_to(plane) < 0.001)
	print("=== Smoke-Test OK ===")
	get_tree().quit(0)


func _capture_after_first_note() -> void:
	var idx := mini(4, _beatmap.hit_objects.size() - 1)
	var target := _beatmap.hit_objects[idx].time - 200.0
	var guard := 0
	while _time_ms() < target and guard < 3600:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/gameplay_3d.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)
