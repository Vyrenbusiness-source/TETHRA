class_name BreakOverlay
extends Control

## Pausen-Anzeige: ruhig mittig "Pause", Fortschrittsring bis zur naechsten Note,
## Sekunden-Countdown. In den letzten 3 Beats 3-2-1 exakt auf den Beats
## (Beat k liegt bei end_ms - k * beat_ms), dann sanft weg.
## API: show_break(start_ms, end_ms, beat_ms, can_skip), update(t_ms), hide_break().

const FADE_IN_MS := 260.0
const FADE_OUT_MS := 380.0
const RING_SIZE := 240.0

const _RING_CODE := "shader_type canvas_item;
uniform float progress = 0.0;
uniform float pulse = 0.0;
uniform vec4 col : source_color = vec4(0.2, 0.85, 1.0, 1.0);
void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float w = 0.045 + 0.03 * pulse;
	float rr = 0.86;
	float a = 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.012, abs(r - rr));
	float ang = atan(p.x, -p.y);
	if (ang < 0.0) ang += 6.28318530718;
	float f = ang / 6.28318530718;
	float on = step(f, progress);
	float track = a * 0.16;
	float fill = a * on;
	float glow = exp(-abs(r - rr) * 14.0) * 0.22 * (0.4 + pulse) * on;
	vec3 c = mix(vec3(1.0), col.rgb, on);
	COLOR = vec4(c, clamp(max(track, fill) + glow, 0.0, 1.0));
}"

var _active := false
var _start_ms := 0.0
var _end_ms := 0.0
var _beat_ms := 500.0
var _can_skip := false

var _root: Control
var _panel: Panel
var _title: Label
var _num: Label
var _sub: Label
var _hint: Label
var _ring: ColorRect
var _mat: ShaderMaterial
var _last_num := -999
var _last_sub := -999


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.size = Vector2(RING_SIZE, RING_SIZE)
	_root.position = -_root.size * 0.5
	_root.pivot_offset = _root.size * 0.5
	add_child(_root)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiTheme.glass_box(int(RING_SIZE * 0.5), 0.38, 0.12))
	_panel.size = Vector2(RING_SIZE, RING_SIZE)
	_root.add_child(_panel)

	var sh := Shader.new()
	sh.code = _RING_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("col", UiTheme.ACCENT)
	_ring = ColorRect.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.material = _mat
	_ring.color = Color.WHITE
	_ring.size = Vector2(RING_SIZE, RING_SIZE)
	_root.add_child(_ring)

	var hf := UiTheme.heading_font(6)
	_title = _mk_label(hf, 20, UiTheme.DIM, "PAUSE")
	_title.position = Vector2(0, 50)
	_title.size = Vector2(RING_SIZE, 28)
	_num = _mk_label(hf, 88, UiTheme.TEXT, "")
	_num.position = Vector2(0, 76)
	_num.size = Vector2(RING_SIZE, 100)
	_num.pivot_offset = Vector2(RING_SIZE * 0.5, 50)
	_sub = _mk_label(UiTheme.heading_font(1), 13, UiTheme.DIM, "")
	_sub.position = Vector2(0, 170)
	_sub.size = Vector2(RING_SIZE, 22)
	_hint = _mk_label(null, 15, UiTheme.DIM, "Leertaste: Intro überspringen")
	_hint.position = Vector2(RING_SIZE * 0.5 - 160.0, RING_SIZE + 22.0)
	_hint.size = Vector2(320, 24)
	visible = false


func _mk_label(font: Font, fsize: int, col: Color, txt: String) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(l)
	return l


func show_break(start_ms: float, end_ms: float, beat_ms: float, can_skip: bool) -> void:
	_start_ms = start_ms
	_end_ms = end_ms
	_beat_ms = maxf(beat_ms, 50.0)
	_can_skip = can_skip
	_active = true
	_last_num = -999
	_last_sub = -999
	_title.text = "INTRO" if start_ms <= 0.0 else "PAUSE"
	_hint.visible = can_skip
	visible = true
	modulate.a = 0.0
	update(start_ms)


## Deckkraft-Faktor fuer einen Ring, der ueber dem Spielfeld liegt: voll sichtbar, bis
## die erste Note nach dem Break ins Feld kommt (visible_ms), 250 ms davor blendet er
## aus. So verdeckt er nie eine anfliegende Note (Mania 3D, Orbit, 2D ohne Platz daneben).
const CLEAR_FADE_MS := 250.0
static func clear_alpha(visible_ms: float, t_ms: float) -> float:
	return clampf((visible_ms - t_ms) / CLEAR_FADE_MS, 0.0, 1.0)


func hide_break() -> void:
	_active = false
	visible = false


func is_active() -> bool:
	return _active


## Pro Frame mit der Song-Zeit aufrufen. Text wird nur bei Wechsel gesetzt.
func update(t_ms: float) -> void:
	if not _active:
		return
	var dur := maxf(_end_ms - _start_ms, 1.0)
	var rem := _end_ms - t_ms

	# Nach der Note: sanft ausblenden, dann fertig.
	if rem <= 0.0:
		var f := 1.0 + rem / FADE_OUT_MS
		if f <= 0.0:
			hide_break()
			return
		modulate.a = f
		_root.scale = Vector2.ONE * (1.0 + (1.0 - f) * 0.06)
		_mat.set_shader_parameter("progress", 1.0)
		return

	var a := clampf((t_ms - _start_ms) / FADE_IN_MS, 0.0, 1.0)
	modulate.a = a * a * (3.0 - 2.0 * a)
	_mat.set_shader_parameter("progress", clampf((t_ms - _start_ms) / dur, 0.0, 1.0))

	# k = Beats bis zur Note: 3 in (2b,3b], 2 in (b,2b], 1 in (0,b]. Wechsel exakt bei end - k*beat.
	var k := int(ceil(rem / _beat_ms - 0.0001))
	var counting := k >= 1 and k <= 3 and (_end_ms - float(k) * _beat_ms) >= _start_ms - 1.0
	var bump := 0.0
	if counting:
		var phase := clampf(1.0 - (rem - (float(k) - 1.0) * _beat_ms) / _beat_ms, 0.0, 1.0)
		bump = exp(-phase * 6.0)
		if k != _last_num:
			_last_num = k
			_num.text = str(k)
			_num.add_theme_color_override("font_color", UiTheme.ACCENT)
		if _last_sub != -1:
			_last_sub = -1
			_sub.text = ""
		_title.modulate.a = 0.5
	else:
		var secs := int(ceil(rem / 1000.0))
		if secs != _last_num:
			_last_num = secs
			_num.text = str(secs)
			_num.add_theme_color_override("font_color", UiTheme.TEXT)
		if _last_sub != 0:
			_last_sub = 0
			_sub.text = "bis zur nächsten Note"
		_title.modulate.a = 1.0
	_num.scale = Vector2.ONE * (1.0 + 0.30 * bump)
	_root.scale = Vector2.ONE * (1.0 + 0.025 * bump)
	_mat.set_shader_parameter("pulse", bump)
