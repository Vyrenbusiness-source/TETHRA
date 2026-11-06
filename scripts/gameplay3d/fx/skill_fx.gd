class_name SkillFx
extends Node3D

## Skill-Belohnung fuer gute Spieler: Lichtstroeme, Plasma-Band und Aura,
## die mit Combo + Accuracy in vier Stufen aufbluehen. Alles liegt peripher
## (Aussenkanten, an/hinter der Abfanglinie, auf dem Boden) und nie ueber den
## Noten. Keine Vollflaechen-Blitze: nur wandernde Pulse und weiche Fades.
##
## Nutzung: setup(...) einmal, dann pro Frame update(...), dazu die Events
## on_judge(column, quality) und on_milestone(combo).
##   Stufe 1 (Combo 50):  Lichtstroeme im Takt an beiden Aussenkanten
##   Stufe 2 (Combo 100): Plasma-Band an der Abfanglinie
##   Stufe 3 (Combo 200): zweite Kanten-Ebene (Lichtwand) + Aura hinter der Linie
##   Stufe 4 (Combo 400): Prisma-Farbverlauf in den Stroemen
## Jede Stufe verlangt Accuracy >= 0.95. Miss: in 0.6 s sanft eine Stufe runter.

const COMBO_TIERS: Array[int] = [50, 100, 200, 400]
const ACC_ON := 0.95
const ACC_OFF := 0.945          # Hysterese: kein Flattern an der Grenze
const RISE_RATE := 0.85         # Stufen pro Sekunde beim Aufbluehen
const FALL_TIME := 0.6          # Sekunden fuer eine Stufe nach unten
const LANE_HALF := 0.75
const PULSE_DECAY := 0.16        # s: Plasma-Puls auf dem Beat klingt in ~160 ms ab
const SWEEP_SPEED := 1.25       # Meilenstein-Welle: Strecken-Laengen pro Sekunde

const QUALITY_MAX := 0
const QUALITY_MISS := 5

var _streams: Array[MeshInstance3D] = []
var _walls: Array[MeshInstance3D] = []
var _stream_mats: Array[ShaderMaterial] = []
var _wall_mats: Array[ShaderMaterial] = []
var _plasma: MeshInstance3D
var _plasma_mat: ShaderMaterial
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial

var _theme := Color(0.3, 0.85, 1.0)
var _theme_kiai := Color(1.0, 0.45, 0.85)
var _ready_ok := false

var _level := 0.0               # angezeigte Stufe (0..4, kontinuierlich)
var _held := 0                  # erreichte Stufe seit dem letzten Miss
var _acc_ok := false
var _beat_count := 0
var _prev_phase := 0.0
var _beat_dur := 0.47           # geschaetzte Beat-Laenge (s), aus Phasenlauf
var _since_beat := 1.0          # s seit letzter Beat-Kante
var _time := 0.0
var _flow := 0.0
var _boost_t: Array[float] = [0.0, 0.0]   # Ziel-Energie links/rechts
var _boost: Array[float] = [0.0, 0.0]     # geglaettet
var _sweep := -1.0
var _rail_mid := 0.0
var _columns := 4


func setup(rail_x: Array[float] = [-2.55, -0.85, 0.85, 2.55], z_line: float = 3.0,
		z_far: float = -46.0, road_y: float = -1.6,
		theme: Color = Color(0.3, 0.85, 1.0),
		theme_kiai: Color = Color(1.0, 0.45, 0.85)) -> void:
	_clear()
	_theme = theme
	_theme_kiai = theme_kiai
	var min_x := 0.0
	var max_x := 0.0
	if not rail_x.is_empty():
		min_x = rail_x[0]
		max_x = rail_x[0]
		for x in rail_x:
			min_x = minf(min_x, x)
			max_x = maxf(max_x, x)
	_rail_mid = (min_x + max_x) * 0.5
	_columns = maxi(1, rail_x.size())
	var half := (max_x - min_x) * 0.5 + LANE_HALF   # Aussenkante der Bahnen
	var stream_shader: Shader = load("res://shaders/skill_stream.gdshader")
	var plasma_shader: Shader = load("res://shaders/plasma_line.gdshader")

	# Lichtstroeme: flache Baender knapp ausserhalb der Streckenkante,
	# von etwas vor der Linie bis zum Horizont.
	var z_near := z_line + 1.4
	var length := absf(z_near - z_far)
	var z_mid := (z_near + z_far) * 0.5
	for side_i in 2:
		var sgn := -1.0 if side_i == 0 else 1.0
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.55, length)
		m.mesh = pm
		m.position = Vector3(_rail_mid + sgn * (half + 0.62), road_y + 0.012, z_mid)
		var mat := _stream_mat(stream_shader, sgn, 0.0)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_streams.append(m)
		_stream_mats.append(mat)

	# Zweite Kanten-Ebene: senkrechte Lichtwaende weiter aussen.
	for side_i in 2:
		var sgn := -1.0 if side_i == 0 else 1.0
		var w := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(length, 1.05)
		w.mesh = qm
		w.position = Vector3(_rail_mid + sgn * (half + 1.25), road_y + 0.525, z_mid)
		w.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		var wmat := _stream_mat(stream_shader, sgn, 1.0)
		w.material_override = wmat
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.visible = false
		add_child(w)
		_walls.append(w)
		_wall_mats.append(wmat)

	# Plasma-Band: Boden-Streifen direkt an der Abfanglinie (unter den Pads).
	_plasma = MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(half * 2.0 + 0.5, 0.62)
	_plasma.mesh = bp
	_plasma.position = Vector3(_rail_mid, road_y + 0.006, z_line)
	_plasma_mat = ShaderMaterial.new()
	_plasma_mat.shader = plasma_shader
	_plasma_mat.set_shader_parameter(&"mode", 0.0)
	_plasma_mat.set_shader_parameter(&"intensity", 0.0)
	_plasma.material_override = _plasma_mat
	_plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plasma.visible = false
	add_child(_plasma)

	# Aura: weicher Schein HINTER der Linie (zur Kamera hin), wo keine Noten sind.
	_aura = MeshInstance3D.new()
	var ap := PlaneMesh.new()
	ap.size = Vector2(half * 2.0 + 1.8, 2.4)
	_aura.mesh = ap
	_aura.position = Vector3(_rail_mid, road_y + 0.003, z_line + 0.1 + 1.2)
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = plasma_shader
	_aura_mat.set_shader_parameter(&"mode", 1.0)
	_aura_mat.set_shader_parameter(&"intensity", 0.0)
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	add_child(_aura)

	_ready_ok = true


func _stream_mat(shader: Shader, sgn: float, wall: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"side", sgn)
	mat.set_shader_parameter(&"wall", wall)
	mat.set_shader_parameter(&"intensity", 0.0)
	mat.set_shader_parameter(&"pulses", 6.0 if wall < 0.5 else 4.0)
	return mat


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_streams.clear()
	_walls.clear()
	_stream_mats.clear()
	_wall_mats.clear()
	_ready_ok = false


## Aktuelle Stufe (0..4, kontinuierlich) — fuer HUD/Debug.
func get_level() -> float:
	return _level


func set_theme(theme: Color, theme_kiai: Color) -> void:
	_theme = theme
	_theme_kiai = theme_kiai


## Pro Frame. beat_phase 0..1 innerhalb des Schlags, beat_env 0..1 Huellkurve.
## music_energy 0..1 (optional, Default 1.0) skaliert die Staerke der Beat-Pulse.
func update(delta: float, beat_phase: float, beat_env: float, combo: int,
		accuracy: float, kiai_mix: float, music_energy: float = 1.0) -> void:
	if not _ready_ok:
		return
	_time += delta
	_since_beat += delta
	if beat_phase < _prev_phase - 0.5:
		_beat_count += 1
		if _since_beat > 0.15 and _since_beat < 2.0:
			_beat_dur = lerpf(_beat_dur, _since_beat, 0.5)
		_since_beat = beat_phase * _beat_dur
	var energy := 0.6 + 0.4 * clampf(music_energy, 0.0, 1.0)
	# Attack sofort auf der Kante, danach exponentieller Decay (~160 ms).
	var beat_pulse := exp(-_since_beat / (PULSE_DECAY * 0.33)) * energy
	_prev_phase = beat_phase
	var beats := float(_beat_count) + beat_phase

	# --- Stufe bestimmen ---
	if _acc_ok:
		if accuracy < ACC_OFF:
			_acc_ok = false
	elif accuracy >= ACC_ON:
		_acc_ok = true
	var stats_tier := 0
	if _acc_ok:
		for i in COMBO_TIERS.size():
			if combo >= COMBO_TIERS[i]:
				stats_tier = i + 1
		_held = maxi(_held, stats_tier)
	else:
		_held = 0
	var target := float(_held)
	if _level < target:
		_level = minf(target, _level + RISE_RATE * delta)
	elif _level > target:
		_level = maxf(target, _level - delta / FALL_TIME)

	var w1 := _tier_w(1)
	var w2 := _tier_w(2)
	var w3 := _tier_w(3)
	var w4 := _tier_w(4)

	# --- Judge-Energie und Meilenstein-Welle ---
	var k_att := 1.0 - exp(-delta * 12.0)
	var k_dec := exp(-delta * 2.6)
	for i in 2:
		_boost_t[i] *= k_dec
		_boost[i] = lerpf(_boost[i], _boost_t[i], k_att)
	if _sweep >= 0.0:
		_sweep += delta * SWEEP_SPEED
		if _sweep > 1.2:
			_sweep = -1.0

	var kiai := clampf(kiai_mix, 0.0, 1.0)
	var col := _theme.lerp(_theme_kiai, kiai)
	var col2 := _theme_kiai.lerp(_theme, kiai)
	var env := clampf(beat_env, 0.0, 1.0)
	var kiai_gain := 1.0 + kiai * 0.15
	# Fluss des Plasmas leicht an den Puls gekoppelt (nie ruckartig).
	_flow += delta * (0.9 + env * 0.35 + kiai * 0.3)

	var s_int := clampf((w1 * 0.62 + w2 * 0.14 + w3 * 0.12 + w4 * 0.12) * kiai_gain, 0.0, 1.0)
	var wall_int := clampf(w3 * 0.55 * kiai_gain, 0.0, 1.0)
	for i in 2:
		_apply_stream(_stream_mats[i], _streams[i], s_int, col, beats, env, w4, i, music_energy)
		_apply_stream(_wall_mats[i], _walls[i], wall_int, col, beats, env, w4, i, music_energy)

	var p_int := clampf(w2 * (0.78 + w4 * 0.17) * kiai_gain, 0.0, 1.0)
	_plasma.visible = p_int > 0.002
	if _plasma.visible:
		_plasma_mat.set_shader_parameter(&"intensity", p_int)
		_plasma_mat.set_shader_parameter(&"color", col)
		_plasma_mat.set_shader_parameter(&"color2", col2)
		_plasma_mat.set_shader_parameter(&"env", env)
		_plasma_mat.set_shader_parameter(&"beat_pulse", beat_pulse)
		_plasma_mat.set_shader_parameter(&"flow", _flow)
		_plasma_mat.set_shader_parameter(&"prism", 0.0)  # kein Prisma: keine bunten Stroeme durchs Spielfeld (Nutzer)

	var a_int := clampf(w3 * 0.75 * kiai_gain, 0.0, 1.0)
	_aura.visible = a_int > 0.002
	if _aura.visible:
		_aura_mat.set_shader_parameter(&"intensity", a_int)
		_aura_mat.set_shader_parameter(&"color", col)
		_aura_mat.set_shader_parameter(&"color2", col2)
		_aura_mat.set_shader_parameter(&"env", env)
		_aura_mat.set_shader_parameter(&"beat_pulse", beat_pulse)
		_aura_mat.set_shader_parameter(&"flow", _flow)
		_aura_mat.set_shader_parameter(&"prism", 0.0)


func _apply_stream(mat: ShaderMaterial, mesh: MeshInstance3D, intensity: float,
		col: Color, beats: float, env: float, prism: float, side_i: int, music_energy: float = 1.0) -> void:
	mesh.visible = intensity > 0.002
	if not mesh.visible:
		return
	mat.set_shader_parameter(&"intensity", intensity)
	mat.set_shader_parameter(&"color", col)
	mat.set_shader_parameter(&"beats", beats)
	mat.set_shader_parameter(&"env", env)
	mat.set_shader_parameter(&"music_energy", clampf(music_energy, 0.0, 1.0))
	mat.set_shader_parameter(&"prism", 0.0)
	mat.set_shader_parameter(&"boost", _boost[side_i])
	mat.set_shader_parameter(&"sweep", _sweep)
	mat.set_shader_parameter(&"t", _time)


## Gewicht einer Stufe 0..1, weich ein-/ausgeblendet.
func _tier_w(tier: int) -> float:
	return smoothstep(0.0, 1.0, clampf(_level - float(tier - 1), 0.0, 1.0))


## quality: 0=MAX, 1=300, 2=200, 3=100, 4=50, 5=MISS.
func on_judge(column: int, quality: int) -> void:
	if quality >= QUALITY_MISS:
		# Eine Stufe zurueck; update() faehrt sie in FALL_TIME weich herunter.
		_held = maxi(0, maxi(_held, int(ceilf(_level - 0.001))) - 1)
		return
	var gain := 0.0
	match quality:
		QUALITY_MAX:
			gain = 0.32
		1:
			gain = 0.22
		2:
			gain = 0.08
	if gain <= 0.0:
		return
	# Spalten links der Mitte speisen den linken Strom, rechts den rechten.
	var side_i := 0 if column * 2 < _columns else 1
	_boost_t[side_i] = minf(1.0, _boost_t[side_i] + gain)


## Meilenstein (z. B. alle 100 Combo): eine weiche Welle laeuft die Stroeme hinab.
func on_milestone(_combo: int) -> void:
	_sweep = 0.0
