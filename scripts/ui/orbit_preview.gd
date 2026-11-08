class_name OrbitPreview
extends Control

## Live-Vorschau fuer die Orbit-Einstellungen: echter OrbitView, eine kurze
## Demo-Sequenz (Taps auf beiden Spuren, Akkord, Bogen, drei Bahnformen) in Endlosschleife mit
## Autoplay-Treffern. Liest Scroll Speed, Winkel-Hilfslinien und Hintergrund
## jeden Frame aus Settings (billig), laeuft nur sichtbar. Hintergrund "Welt" ist
## ein dunkler, ruhiger Platzhalter (keine zweite 3D-Welt in der Vorschau).

const SIZE_PX := Vector2(384, 216)
const TAIL_MS := 900.0

var _view: OrbitView
var _bg: TextureRect
var _notes: Array = []
var _t := 0.0
var _next := 0           # naechstes Ziel, dessen Kopf noch nicht getroffen ist
var _arc_open: Array = []  # Indizes laufender Boegen
var _end_ms := 0.0
var _preempt := -1.0
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
	_notes = demo_notes()
	_view.track = demo_track()
	_view.setup(_notes)
	_end_ms = 0.0
	for n in _notes:
		_end_ms = maxf(_end_ms, n.end_ms)
	_apply_settings()
	_restart()
	visibility_changed.connect(_on_vis)
	_on_vis()


## Demo: Taps auf Spur A/B, Akkord (beide Spuren gleichzeitig), ein Bogen.
## Zeiten passen zu demo_track (2000 ms pro Takt).
static func demo_notes() -> Array:
	var a: Array = []
	a.append(OrbitNote.make(0.0, 0.0, 0))
	a.append(OrbitNote.make(450.0, 90.0, 1))
	a.append(OrbitNote.make(900.0, 180.0, 0))
	a.append(OrbitNote.make(1350.0, 270.0, 1))
	a.append(OrbitNote.make(2000.0, 0.0, 0))   # Akkord
	a.append(OrbitNote.make(2000.0, 0.0, 1))
	a.append(OrbitNote.make_arc(2600.0, 3400.0, 108.0, 144.0, 0))
	a.append(OrbitNote.make(3500.0, 270.0, 1))
	a.append(OrbitNote.make(4300.0, 0.0, 1))
	a.append(OrbitNote.make(4800.0, 0.0, 0))
	return a


## Demo-Bahn: Ellipse, ab Takt 2 Acht, ab Takt 3 Rose (Formwechsel sichtbar).
static func demo_track() -> OrbitTrack:
	var tr := OrbitTrack.fixed(OrbitClock.fixed(2000.0), OrbitPath.ELLIPSE)
	tr.plan.append([2000.0, OrbitPath.EIGHT])
	tr.plan.append([4000.0, OrbitPath.ROSE3])
	return tr


func _on_vis() -> void:
	set_process(is_visible_in_tree())
	if is_visible_in_tree():
		_restart()


func _restart() -> void:
	_view.setup(_notes)
	_next = 0
	_arc_open.clear()
	_release_at = [-1.0, -1.0]
	_view.ring_held = [false, false]
	_t = -_preempt_ms()


func _preempt_ms() -> float:
	return ManiaCore.preempt_for(Settings.mania_scroll)


func _apply_settings() -> void:
	_view.show_guides = Settings.orbit_guides
	var p := _preempt_ms()
	if not is_equal_approx(p, _preempt):
		_preempt = p
		_view.preempt = p
	if Settings.orbit_background != _bg_mode:
		_bg_mode = Settings.orbit_background
		match _bg_mode:
			Settings.ORBIT_BG_OFF:
				_bg.texture = null
				_bg.visible = false
			Settings.ORBIT_BG_MAP:
				_bg.texture = SettingsPanel._sample_bg_texture()
				_bg.modulate = Color(0.55, 0.55, 0.55)
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
		g.set_color(0, Color(0.10, 0.12, 0.22))
		g.set_color(1, Color(0.02, 0.02, 0.05))
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
	# Autoplay: Cursor sitzt auf dem Kopf, Tasten treffen exakt zur Zeit.
	while _next < _notes.size() and float(_notes[_next].time_ms) <= _t:
		var n = _notes[_next]
		_view.ring_held[n.ring] = true
		if n.is_arc:
			_view.on_arc_started(_next, 0, 0.0)
			_arc_open.append(_next)
		else:
			_view.on_judged(_next, {"quality": 0, "dt": 0.0})
			_release_at[n.ring] = _t + 90.0
		_next += 1
	for i in _arc_open.duplicate():
		var n = _notes[i]
		if _t >= float(n.end_ms):
			_view.on_judged(i, {"quality": 0, "dt": 0.0})
			_arc_open.erase(i)
			_release_at[n.ring] = _t + 90.0
	for r in 2:
		if _release_at[r] >= 0.0 and _t >= _release_at[r] and not _holds_arc(r):
			_view.ring_held[r] = false
			_release_at[r] = -1.0
	_view.cursor_pos = _view.to_px(_view.head_path())
	if _t > _end_ms + TAIL_MS:
		_restart()


func _holds_arc(r: int) -> bool:
	for i in _arc_open:
		if _notes[i].ring == r:
			return true
	return false
