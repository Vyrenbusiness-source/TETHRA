class_name MilestoneBurst
extends Control
## Edle Einblendung fuer Kombo-Meilensteine ("100 KOMBO") und Kapitelnamen
## ("KIAI", "DROP") fuer die HUD-CanvasLayer. Sitzt immer am Seitenrand,
## nie ueber dem Notenfeld: Kombo links, Kapitel rechts.
##
## Alle Nodes entstehen einmal in setup(); fire()/fire_section() setzen nur
## eine Startzeit (kein Tween, keine Allokation). Der Pop beginnt exakt im
## Aufruf-Frame, der Aufrufer quantisiert den Aufruf auf den Downbeat.
##
## Nutzung:
##   var mb := MilestoneBurst.new(); hud.add_child(mb); mb.setup(theme_col)
##   mb.fire(core.combo)            # tut nur bei Meilensteinen etwas
##   mb.fire_section("KIAI")

const MILESTONES: Array[int] = [50, 100, 200, 300, 500, 1000]
const DURATION := 1.2
const POP_FROM := 1.35
const POP_S := 0.10
const FADE_S := 0.35
const SWEEP_START := 0.08
const SWEEP_S := 0.45
const EDGE_MARGIN := 28.0
const Y_COMBO := 0.40
const Y_SECTION := 0.28
const PLATE_W := 300.0
const PLATE_H := 64.0

class Slot:
	extends RefCounted
	var plate: Control
	var label: Label
	var rule: ColorRect
	var t := -1.0
	var right := false
	var big := true

var _theme := Color(0.45, 0.80, 1.00)
var _combo: Slot
var _section: Slot
var _ready_done := false


func setup(theme: Color) -> void:
	_theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _ready_done:
		_combo = _make_slot(false, true)
		_section = _make_slot(true, false)
		_ready_done = true
	for s in [_combo, _section]:
		var sl: Slot = s
		sl.label.add_theme_color_override("font_color", Color.WHITE.lerp(theme, 0.25))
		sl.label.add_theme_color_override("font_outline_color", Color(theme.darkened(0.7), 0.9))
		sl.rule.color = Color(theme, 0.85)
	_layout()
	resized.connect(_layout)


func _make_slot(right: bool, big: bool) -> Slot:
	var s := Slot.new()
	s.right = right
	s.big = big
	var p := Control.new()
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(PLATE_W, PLATE_H)
	p.visible = false
	p.draw.connect(_draw_plate.bind(s))
	add_child(p)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(PLATE_W, PLATE_H - 6.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 40 if big else 30)
	l.add_theme_constant_override("outline_size", 6)
	l.pivot_offset = Vector2(0.0 if not right else PLATE_W, (PLATE_H - 6.0) * 0.5)
	p.add_child(l)
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(PLATE_W, 2.0)
	r.position = Vector2(0.0, PLATE_H - 4.0)
	p.add_child(r)
	s.plate = p
	s.label = l
	s.rule = r
	return s


func _layout() -> void:
	if not _ready_done:
		return
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	_combo.plate.position = Vector2(EDGE_MARGIN, vs.y * Y_COMBO)
	_section.plate.position = Vector2(vs.x - EDGE_MARGIN - PLATE_W, vs.y * Y_SECTION)


func fire(combo: int) -> void:
	if not _ready_done or not MILESTONES.has(combo):
		return
	_combo.label.text = "%d KOMBO" % combo
	_start(_combo)


func fire_section(text: String) -> void:
	if not _ready_done or text.is_empty():
		return
	_section.label.text = text.to_upper()
	_start(_section)


func _start(s: Slot) -> void:
	s.t = 0.0
	_apply(s)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	var live := false
	for s in [_combo, _section]:
		var sl: Slot = s
		if sl.t < 0.0:
			continue
		sl.t += delta
		if sl.t >= DURATION:
			sl.t = -1.0
			sl.plate.visible = false
			continue
		live = true
		_apply(sl)
	if not live:
		set_process(false)


func _apply(s: Slot) -> void:
	var t := s.t
	var pop := clampf(t / POP_S, 0.0, 1.0)
	var e := 1.0 - (1.0 - pop) * (1.0 - pop)
	var sc := lerpf(POP_FROM, 1.0, e)
	var a := pop * clampf((DURATION - t) / FADE_S, 0.0, 1.0)
	s.plate.visible = true
	s.plate.modulate.a = a
	s.label.scale = Vector2(sc, sc)
	s.rule.scale.x = e
	s.rule.pivot_offset.x = PLATE_W if s.right else 0.0
	s.plate.queue_redraw()


func _draw_plate(s: Slot) -> void:
	if s.t < 0.0:
		return
	var k := (s.t - SWEEP_START) / SWEEP_S
	if k < 0.0 or k > 1.0:
		return
	# Schraeges Glanzband laeuft ueber die Platte, vom Rand nach innen.
	var kk := k if not s.right else 1.0 - k
	var cx := lerpf(-60.0, PLATE_W + 60.0, kk)
	var w := 34.0
	var sk := 22.0
	var c := Color(1, 1, 1, 0.55 * sin(k * PI))
	var c0 := Color(1, 1, 1, 0.0)
	var h := PLATE_H
	var pts := PackedVector2Array([
		Vector2(cx - w + sk, 0), Vector2(cx + sk, 0),
		Vector2(cx, h), Vector2(cx - w, h)])
	var cols := PackedColorArray([c0, c, c, c0])
	s.plate.draw_polygon(pts, cols)
