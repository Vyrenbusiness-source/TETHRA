class_name Playfield2D
extends Control

## 2D-Modus ("wie normales Mania"): senkrechte Spalten in der Bildmitte,
## Noten als flache Balken, Holds als Balken mit Endkappe, Receptors an der
## Abfanglinie. Reine Darstellung: mania_3d.gd liefert pro Frame die
## Z-Positionen (gleiche Scroll-/SV-Rechnung wie in 3D), hier wird Z linear
## auf Bild-Y abgebildet (Z_FAR = Oberkante, Z_LINE = Abfanglinie).

const LINE_FRAC := 0.86       ## Abfanglinie bei 86 % Bildhoehe
const COL_W_FRAC := 0.074     ## Spaltenbreite bei 100 % Spurbreite (x Bildhoehe)
const NOTE_H_FRAC := 0.026    ## Notenbalken-Hoehe (x Bildhoehe)
const RECEPTOR_H_FRAC := 0.05 ## Receptor-Feld unter der Linie

const STATE_NORMAL := 0
const STATE_HELD := 1
const STATE_DEAD := 2         ## verpasst / losgelassen: grau

var columns := 4
var lane_k := 1.0
var z_line := 3.0
var z_far := -46.0
var key_names: PackedStringArray = []
var lane_color := Color(0.7, 0.85, 1.0)
var show_keys := true

# Pro Frame gefuellt: [col, z_head, z_tail, color, state, is_hold]
var _items: Array = []
var _held: Array = []
var _flash: Array = []
var _flash_col: Array = []
var _font: Font


func setup(p_columns: int, p_lane_k: float, p_z_line: float, p_z_far: float,
		p_keys: PackedStringArray, p_lane_color: Color) -> void:
	columns = p_columns
	lane_k = p_lane_k
	z_line = p_z_line
	z_far = p_z_far
	key_names = p_keys
	lane_color = p_lane_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func begin_frame() -> void:
	_items.clear()


func add_note(col: int, z_head: float, color: Color, state: int = STATE_NORMAL) -> void:
	_items.append([col, z_head, z_head, color, state, false])


func add_hold(col: int, z_head: float, z_tail: float, color: Color, state: int = STATE_NORMAL) -> void:
	_items.append([col, z_head, z_tail, color, state, true])


func set_lanes(held: Array, flash: Array, flash_col: Array) -> void:
	_held = held
	_flash = flash
	_flash_col = flash_col
	queue_redraw()


func line_y() -> float:
	return _vs().y * LINE_FRAC


func col_width() -> float:
	return _vs().y * COL_W_FRAC * lane_k


func field_rect() -> Rect2:
	var vs := _vs()
	var w := col_width() * columns
	return Rect2((vs.x - w) * 0.5, 0.0, w, vs.y)


## Z (Strecke) -> Bild-Y: linear, Z_FAR an der Oberkante.
func z_to_y(z: float) -> float:
	return line_y() - (z_line - z) / (z_line - z_far) * line_y()


func _vs() -> Vector2:
	var r := get_viewport_rect().size
	return r if r.x > 0.0 else Vector2(1920, 1080)


func _draw() -> void:
	var vs := _vs()
	var fr := field_rect()
	var cw := col_width()
	var ly := line_y()
	# Spalten-Hintergrund: dunkel, halbtransparent; gedrueckte Spalte hellt auf.
	draw_rect(fr, Color(0.02, 0.025, 0.04, 0.82))
	for c in columns:
		var x := fr.position.x + cw * c
		if c < _held.size() and bool(_held[c]) and Settings.lane_glow:
			var g := Rect2(x, 0.0, cw, ly)
			draw_rect(g, Color(lane_color.r, lane_color.g, lane_color.b, 0.07))
	# Feine Trennlinien + Rand.
	for c in columns + 1:
		var x := fr.position.x + cw * c
		var a := 0.30 if (c == 0 or c == columns) else 0.10
		draw_line(Vector2(x, 0.0), Vector2(x, vs.y), Color(1, 1, 1, a), 1.0)
	# Noten/Holds.
	var nh := vs.y * NOTE_H_FRAC
	var pad := maxf(2.0, cw * 0.06)
	for it in _items:
		var col: int = it[0]
		var x0 := fr.position.x + cw * col + pad
		var w := cw - pad * 2.0
		var yh := z_to_y(float(it[1]))
		var c: Color = it[3]
		var st: int = it[4]
		if st == STATE_DEAD:
			c = Color(0.36, 0.37, 0.41, 0.8)
		if bool(it[5]):
			var yt := z_to_y(float(it[2]))
			var top := minf(yh, yt)
			var bot := maxf(yh, yt)
			if bot < -nh or top > vs.y + nh:
				continue
			# Koerper schmaler und etwas transparenter, Endkappe voll breit.
			var bw := w * 0.72
			var body := Rect2(x0 + (w - bw) * 0.5, top, bw, bot - top)
			var bc := c if st != STATE_HELD else c.lerp(Color(1, 1, 1), 0.25)
			draw_rect(body, Color(bc.r, bc.g, bc.b, 0.55 if st != STATE_HELD else 0.75))
			draw_rect(Rect2(x0, top - nh * 0.25, w, nh * 0.5), Color(c.r, c.g, c.b, 0.95))
			_draw_bar(Rect2(x0, yh - nh * 0.5, w, nh), c)
		else:
			if yh < -nh or yh > vs.y + nh:
				continue
			_draw_bar(Rect2(x0, yh - nh * 0.5, w, nh), c)
	# Abfanglinie + Receptors.
	var rh := vs.y * RECEPTOR_H_FRAC
	draw_rect(Rect2(fr.position.x, ly + nh * 0.5, fr.size.x, vs.y - ly), Color(0.0, 0.0, 0.0, 0.55))
	for c in columns:
		var x := fr.position.x + cw * c
		var r := Rect2(x + pad, ly - nh * 0.5, cw - pad * 2.0, nh)
		var on := c < _held.size() and bool(_held[c])
		var fl := clampf(float(_flash[c]) if c < _flash.size() else 0.0, 0.0, 1.0)
		var fc: Color = _flash_col[c] if c < _flash_col.size() else lane_color
		var base := lane_color.lerp(fc, fl * 0.6)
		var fill_a := 0.14 + (0.45 if on else 0.0) + fl * 0.25
		draw_rect(r, Color(base.r, base.g, base.b, minf(fill_a, 0.85)))
		draw_rect(r, Color(base.r, base.g, base.b, 0.9 if on else 0.55), false, 2.0)
		if show_keys and c < key_names.size() and _font != null:
			var fs := int(vs.y * 0.02)
			var txt := key_names[c]
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, Vector2(x + (cw - tw) * 0.5, ly + nh * 0.5 + rh * 0.5 + fs * 0.35),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 if on else 0.4))
	draw_line(Vector2(fr.position.x, ly), Vector2(fr.end.x, ly), Color(1, 1, 1, 0.55), 2.0)


func _draw_bar(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
	# Heller Oberkante-Glanz: Balken liest sich flach, aber klar.
	draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, r.size.y * 0.18))), c.lerp(Color(1, 1, 1), 0.45))
