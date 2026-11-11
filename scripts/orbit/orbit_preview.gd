class_name OrbitPreview
extends Control

## Live-Vorschau fuer die Orbit-Einstellungen: echter OrbitView (Satelliten),
## eine kurze Demo-Folge (Taps A/B, Akzent, Halten) in Endlosschleife mit
## Autoplay-Treffern und gleitendem Cursor. Liest Tasten-Hinweis, Musik-Reaktion,
## Tasten und Hintergrund jeden Frame aus Settings (billig), laeuft nur sichtbar.
## Hintergrund "Welt" ist ein dunkler, ruhiger Platzhalter (keine zweite 3D-Welt).

const SIZE_PX := Vector2(384, 216)
const TAIL_MS := 700.0
const LAP_MS := 500.0
const LAPS := 2
const RADIUS := OrbitConverter.MANIA_RADIUS

var _view: OrbitView
var _bg: TextureRect
var _notes: Array = []
var _t := 0.0
var _next := 0           # naechstes Ziel, dessen Kopf noch nicht getroffen ist
var _hold_open: Array = []  # Indizes laufender Halten
var _end_ms := 0.0
var _bg_mode := -1
var _release_at := [-1.0, -1.0]


func _ready() -> void:
	custom_minimum_size = SIZE_PX
	size = SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.02, 0.02, 0.03, 1.0)
	fb.set_corner_radius_all(14)
	frame.add_theme_stylebox_override("panel", fb)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_bg)
	_view = OrbitView.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.target_radius = RADIUS
	_notes = demo_notes()
	_view.setup(_notes)
	_end_ms = 0.0
	for n in _notes:
		_end_ms = maxf(_end_ms, n.end_ms)
	_apply_settings()
	_restart()
	visibility_changed.connect(_on_vis)
	_on_vis()


## Demo: Taps A/B, Akzent, ein Halten (120 BPM, 2 Runden Vorlauf).
static func demo_notes() -> Array:
	var a: Array = []
	a.append(_tap(1000.0, Vector2(0.28, 0.55), OrbitNote.KEY_A))
	a.append(_tap(1500.0, Vector2(0.50, 0.32), OrbitNote.KEY_B))
	a.append(_tap(2000.0, Vector2(0.72, 0.55), OrbitNote.KEY_A))
	a.append(_tap(2500.0, Vector2(0.50, 0.72), OrbitNote.KEY_ACCENT))
	var path := PackedVector2Array()
	for k in 9:
		var u := float(k) / 8.0
		path.append(Vector2(lerpf(0.26, 0.62, u), 0.42 - sin(u * PI) * 0.16))
	a.append(_with_spawn(OrbitNote.make_hold(3000.0, 3750.0, path, OrbitNote.KEY_A)))
	a.append(_tap(4250.0, Vector2(0.76, 0.62), OrbitNote.KEY_B))
	return a


static func _tap(t: float, pos: Vector2, key: int) -> OrbitNote:
	return _with_spawn(OrbitNote.make_target(t, pos, key))


static func _with_spawn(n: OrbitNote) -> OrbitNote:
	n.lap_ms = LAP_MS
	n.laps = LAPS
	n.spawn_ms = n.time_ms - LAP_MS * LAPS
	return n


func _on_vis() -> void:
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		_restart()


func _restart() -> void:
	_view.setup(_notes)
	_next = 0
	_hold_open.clear()
	_release_at = [-1.0, -1.0]
	_view.held = [false, false]
	_t = 0.0


func _apply_settings() -> void:
	_view.key_hint = Settings.orbit_key_hint != 2
	_view.key_labels = [UiTheme.key_short(Settings.orbit_key_inner), UiTheme.key_short(Settings.orbit_key_outer)]
	_view.music = Settings.orbit_music
	_view.size_k = clampf(float(OrbitGame.setting("orbit_target_size", 100)) / 100.0, 0.9, 1.2)
	_view.cursor_k = clampf(float(OrbitGame.setting("orbit_cursor_size", 100)) / 100.0, 0.5, 1.5)
	if Settings.orbit_background != _bg_mode:
		_bg_mode = Settings.orbit_background
		match _bg_mode:
			Settings.ORBIT_BG_OFF:
				_bg.texture = null
				_bg.visible = false
			Settings.ORBIT_BG_MAP:
				_bg.texture = SettingsPanel._sample_bg_texture()
				_bg.modulate = Color(0.35, 0.35, 0.35)
				_bg.visible = true
			_:
				_bg.texture = _world_tex()
				_bg.modulate = Color.WHITE
				_bg.visible = true


static var _world_cache: Texture2D

## Dunkler, ruhiger Welt-Platzhalter (einmal erzeugt).
static func _world_tex() -> Texture2D:
	if _world_cache == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.07, 0.08, 0.14))
		g.set_color(1, Color(0.02, 0.02, 0.04))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.45)
		t.fill_to = Vector2(1.0, 1.0)
		t.width = 64
		t.height = 64
		_world_cache = t
	return _world_cache


func _process(delta: float) -> void:
	_apply_settings()
	_t += minf(delta, 0.1) * 1000.0
	_view.t_ms = _t
	# Beat-Puls (120 BPM, Takt-Eins alle 4 Schlaege).
	var ph := fposmod(_t, LAP_MS) / LAP_MS
	_view.beat_env = exp(-ph * 6.0)
	_view.downbeat = fposmod(_t, LAP_MS * 4.0) < LAP_MS
	# Autoplay: Tasten treffen exakt zur Zeit.
	while _next < _notes.size() and float(_notes[_next].time_ms) <= _t:
		var n: OrbitNote = _notes[_next]
		var ks := [0, 1] if n.key == OrbitNote.KEY_ACCENT else [n.key]
		for k in ks:
			_view.held[k] = true
		if n.is_hold:
			_view.on_hold_started(_next, 0)
			_hold_open.append(_next)
		else:
			_view.on_judged(_next, {"quality": 0, "dt": 0.0})
			for k in ks:
				_release_at[k] = _t + 70.0
		_next += 1
	for i in _hold_open.duplicate():
		var n: OrbitNote = _notes[i]
		if _t >= float(n.end_ms):
			_view.on_judged(i, {"quality": 0, "dt": 0.0, "hold_end": true})
			_hold_open.erase(i)
			_release_at[clampi(n.key, 0, 1)] = _t + 70.0
	for k in 2:
		if _release_at[k] >= 0.0 and _t >= _release_at[k] and _hold_open.is_empty():
			_view.held[k] = false
			_release_at[k] = -1.0
	_view.cursor = demo_cursor(_notes, _t)
	if _t > _end_ms + TAIL_MS:
		_restart()


## Cursor der Demo: gleitet zum naechsten Ziel, folgt beim Halten der Kugel.
static func demo_cursor(ns: Array, t: float) -> Vector2:
	var prev_p := Vector2(0.5, 0.5)
	var prev_t := 0.0
	for n in ns:
		if t <= float(n.time_ms):
			var start := prev_t
			var arrive := float(n.time_ms) - 80.0
			var u := clampf((t - start) / maxf(arrive - start, 1.0), 0.0, 1.0)
			return prev_p.lerp(n.pos, u * u * (3.0 - 2.0 * u))
		if t <= float(n.end_ms):
			return n.pos_at(t)
		prev_p = OrbitConverter.end_pos(n)
		prev_t = float(n.end_ms)
	return prev_p
