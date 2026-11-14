class_name MineView
extends Node3D

## Darstellung der Minen (Mod "MN") fuer Mania 3D und 2D. Reine Ansicht: Zustand und
## Wertung liegen in ManiaMines/ManiaCore. Lesbarkeit zuerst: eigene Form (3D: stehender
## Oktaeder, 2D: Raute mit dunklem Kern) und eigene Farbe (gedecktes Rot), ruhig, ohne
## Pulsieren, Blinken oder Leuchten. Nach dem Durchlauf blendet die Mine kurz aus.

## Gedecktes Rot (nicht grell): Kante/Licht, Flanke, Schatten.
const COL_LIGHT := Color(0.86, 0.33, 0.31)
const COL_MID := Color(0.60, 0.16, 0.17)
const COL_DARK := Color(0.28, 0.06, 0.08)
const FADE_MS := 160.0
## Wie weit voraus (ms) Minen geprueft werden (SV kann Noten frueher zeigen).
const LOOKAHEAD_MIN_MS := 6000.0

var core: ManiaCore
var _z_of: Callable          ## func(hit_ms: float, t_ms: float) -> float (mania_3d._note_z)
var _rail_x: Array = []
var _road_y := 0.0
var _z_line := 3.0
var _z_far := -46.0
var _scale := 1.0
var _is_2d := false
var _first := 0
var _nodes := {}             ## Minen-Index -> Node3D (nur 3D)
var _vis: Array = []         ## [spalte, z, deckkraft] dieses Frames (2D)
static var _mesh: ArrayMesh
static var _shadow: Mesh
static var _mat: StandardMaterial3D
static var _shadow_mat: StandardMaterial3D


func setup(p_core: ManiaCore, z_of: Callable, rail_x: Array, road_y: float, z_line: float,
		z_far: float, scale_k: float, is_2d: bool) -> void:
	core = p_core
	_z_of = z_of
	_rail_x = rail_x
	_road_y = road_y
	_z_line = z_line
	_z_far = z_far
	_scale = scale_k
	_is_2d = is_2d
	if not _is_2d:
		_ensure_meshes()


## Deckkraft einer Mine zur Zeit t: offen voll, danach kurz ausblenden.
static func alpha_at(mines: ManiaMines, i: int, t: float) -> float:
	if mines.is_pending(i):
		return 1.0
	return clampf(1.0 - (t - mines.times[i]) / FADE_MS, 0.0, 1.0)


func update(t: float) -> void:
	_vis.clear()
	var mm := core.mines
	if mm == null:
		return
	var ahead := maxf(LOOKAHEAD_MIN_MS, core.preempt * 3.0)
	# Vorbei und ausgeblendet: nicht mehr anfassen.
	while _first < mm.count() and not mm.is_pending(_first) and alpha_at(mm, _first, t) <= 0.0:
		_drop(_first)
		_first += 1
	var i := _first
	while i < mm.count() and mm.times[i] - t <= ahead:
		var a := alpha_at(mm, i, t)
		var z: float = _z_of.call(mm.times[i], t)
		var on := a > 0.0 and z >= _z_far - 0.5 and z <= _z_line + 6.0
		if on:
			_vis.append([mm.cols[i], z, a])
		if not _is_2d:
			_place(i, on, z, a)
		i += 1


## 2D: Minen dieses Frames an Playfield2D (nach begin_frame, vor set_lanes).
func feed_2d(pf: Playfield2D) -> void:
	for v in _vis:
		pf.add_mine(int(v[0]), float(v[1]), float(v[2]))


## Anzahl sichtbarer Minen (Tests, Screenshot-Harness).
func visible_count() -> int:
	return _vis.size()


func _place(i: int, on: bool, z: float, a: float) -> void:
	var n: Node3D = _nodes.get(i)
	if not on:
		if n != null:
			n.visible = false
		return
	if n == null:
		n = _make_node()
		add_child(n)
		_nodes[i] = n
	var c: int = core.mines.cols[i]
	n.visible = true
	n.position = Vector3(float(_rail_x[c]), _road_y, z)
	for ch in n.get_children():
		(ch as GeometryInstance3D).transparency = 1.0 - a


func _drop(i: int) -> void:
	var n: Node3D = _nodes.get(i)
	if n != null:
		n.queue_free()
		_nodes.erase(i)


func _make_node() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _mesh
	body.material_override = _mat
	body.position = Vector3(0, 0.50, 0)
	body.scale = Vector3.ONE * _scale
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var sh := MeshInstance3D.new()
	sh.mesh = _shadow
	sh.material_override = _shadow_mat
	sh.position = Vector3(0, 0.03, 0)
	sh.rotation_degrees = Vector3(-90, 45, 0)
	sh.scale = Vector3.ONE * _scale
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sh)
	return root


## Oktaeder (Breite 0,74, Hoehe 0,84) mit fest eingefaerbten Flaechen: oben hell, unten
## dunkel, links/rechts verschieden. Unbeleuchtet: sieht in jeder Welt gleich aus.
static func _ensure_meshes() -> void:
	if _mesh != null:
		return
	var w := 0.37
	var h := 0.42
	var top := Vector3(0, h, 0)
	var bot := Vector3(0, -h, 0)
	var ring := [Vector3(w, 0, 0), Vector3(0, 0, w), Vector3(-w, 0, 0), Vector3(0, 0, -w)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Kamera schaut von +Z (hinter der Linie) leicht von oben: +Z-Flaechen sind die Front.
	var up_cols := [COL_MID, COL_LIGHT, COL_MID.lerp(COL_LIGHT, 0.45), COL_MID]
	var dn_cols := [COL_DARK, COL_MID.lerp(COL_DARK, 0.4), COL_DARK, COL_DARK]
	for k in 4:
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		st.set_color(up_cols[k])
		st.add_vertex(top)
		st.add_vertex(b)
		st.add_vertex(a)
		st.set_color(dn_cols[k])
		st.add_vertex(bot)
		st.add_vertex(a)
		st.add_vertex(b)
	_mesh = st.commit()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.62)
	_shadow = q
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(COL_MID.r, COL_MID.g, COL_MID.b, 0.45)
