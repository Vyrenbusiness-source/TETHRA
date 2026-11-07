class_name Playfield2D
extends Control

## 2D-Modus ("wie normales Mania"): senkrechte Spalten in der Bildmitte,
## Noten als flache Balken, Holds als Balken mit Endkappe, Receptors an der
## Abfanglinie. Reine Darstellung: mania_3d.gd liefert pro Frame die
## Z-Positionen (gleiche Scroll-/SV-Rechnung wie in 3D), hier wird Z linear
## auf Bild-Y abgebildet (Z_FAR = Oberkante, Z_LINE = Abfanglinie).

const LINE_FRAC := 0.86       ## Abfanglinie bei 86 % Bildhoehe
const COL_W_FRAC := 0.10      ## Spaltenbreite bei 100 % Spurbreite (x Bildhoehe)
const NOTE_H_FRAC := 0.026    ## Notenbalken-Hoehe (x Bildhoehe)
const RECEPTOR_H_FRAC := 0.05 ## Receptor-Feld unter der Linie

const STATE_NORMAL := 0
const STATE_HELD := 1
const STATE_DEAD := 2         ## verpasst / losgelassen: grau

var columns := 4
var lane_k := 1.0
var note_k := 1.0    ## Settings.note_size_2d: Balkenhoehe bzw. Kreis-Durchmesser
var z_line := 3.0
var z_far := -46.0
var key_names: PackedStringArray = []
var lane_color := Color(0.7, 0.85, 1.0)
var show_keys := true
var circle := false   ## Settings.NOTE_STYLE_CIRCLE
var skin: ManiaSkin = null  ## osu!mania-Skin (Settings.skin_2d); null = eingebauter Look
var preview_size := Vector2.ZERO  ## > 0: Vorschau-Modus, _vs() nutzt diese Groesse statt des Viewports

# Kreis-Stil: Texturen einmal beim Setup erzeugt, pro Frame nur gezeichnet.
var _disc_tex: Texture2D
var _ring_tex: Texture2D

# Pro Frame gefuellt: [col, z_head, z_tail, color, state, is_hold]
var _items: Array = []
var _held: Array = []
var _flash: Array = []
var _flash_col: Array = []
var _font: Font


func setup(p_columns: int, p_lane_k: float, p_z_line: float, p_z_far: float,
		p_keys: PackedStringArray, p_lane_color: Color, p_style: int = 0,
		p_note_k: float = 1.0) -> void:
	circle = p_style == 1
	if circle:
		_disc_tex = _make_circle_tex(false)
		_ring_tex = _make_circle_tex(true)
	columns = p_columns
	lane_k = p_lane_k
	note_k = p_note_k
	z_line = p_z_line
	z_far = p_z_far
	key_names = p_keys
	lane_color = p_lane_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


## Spurbreite/Notengroesse live aendern (Pausenmenue).
func set_sizes(p_lane_k: float, p_note_k: float) -> void:
	lane_k = p_lane_k
	note_k = p_note_k
	queue_redraw()


## Notenbalken-Hoehe in Pixeln (mit Notengroesse).
func note_h() -> float:
	return _vs().y * NOTE_H_FRAC * note_k


## Kreis-Durchmesser: unabhaengig von der Spurbreite (nur Notengroesse), immer rund.
func circle_d() -> float:
	return _vs().y * COL_W_FRAC * 0.86 * note_k


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
	if skin != null:
		return _vs().y * skin.hit_position / ManiaSkin.SCREEN_UNITS
	return _vs().y * LINE_FRAC


func col_width() -> float:
	if skin != null:
		return _skin_unit() * skin.stage_units() / float(maxi(columns, 1))
	return _vs().y * COL_W_FRAC * lane_k


func field_rect() -> Rect2:
	var vs := _vs()
	if skin != null:
		var sw := _skin_unit() * skin.stage_units()
		return Rect2((vs.x - sw) * 0.5, 0.0, sw, vs.y)
	var w := col_width() * columns
	return Rect2((vs.x - w) * 0.5, 0.0, w, vs.y)


## Z (Strecke) -> Bild-Y: linear, Z_FAR an der Oberkante.
func z_to_y(z: float) -> float:
	return line_y() - (z_line - z) / (z_line - z_far) * line_y()


func _vs() -> Vector2:
	if preview_size.x > 0.0 and preview_size.y > 0.0:
		return preview_size
	var r := get_viewport_rect().size
	return r if r.x > 0.0 else Vector2(1920, 1080)


func _draw() -> void:
	if skin != null:
		_draw_skinned()
		return
	var vs := _vs()
	var fr := field_rect()
	var cw := col_width()
	var ly := line_y()
	# Spalten-Hintergrund: dunkel, halbtransparent; gedrueckte Spalte hellt auf.
	draw_rect(fr, Color(0.012, 0.014, 0.02, Settings.field_dim_2d))  # Spielfeld-Deckkraft
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
	var nh := note_h()
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
		if circle:
			_draw_circle_item(it, x0, w, yh, c, st)
			continue
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
	# Keine durchgehende Abfanglinie: nur die Receptors markieren die Trefferposition.
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
		if circle:
			var d := circle_d()
			var rr := Rect2(x + (cw - d) * 0.5, ly - d * 0.5, d, d)
			draw_texture_rect(_disc_tex, rr, false, Color(base.r, base.g, base.b, minf(fill_a, 0.85) * 0.6))
			draw_texture_rect(_ring_tex, rr, false, Color(base.r, base.g, base.b, 0.95 if on else 0.6))
		else:
			draw_rect(r, Color(base.r, base.g, base.b, minf(fill_a, 0.85)))
			draw_rect(r, Color(base.r, base.g, base.b, 0.9 if on else 0.55), false, 2.0)
		if show_keys and c < key_names.size() and _font != null:
			var fs := int(vs.y * 0.02)
			if preview_size.x > 0.0:
				fs = 11
			var txt := key_names[c]
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, Vector2(x + (cw - tw) * 0.5, ly + nh * 0.5 + rh * 0.5 + fs * 0.35),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 if on else 0.4))


## Kreis-Stil: runde Note; Hold = Balken mit runden Enden (Kopf-Kreis + Endkappe).
func _draw_circle_item(it: Array, x0: float, w: float, yh: float, c: Color, st: int) -> void:
	var vs := _vs()
	var d := circle_d()
	var cx := x0 + w * 0.5
	if bool(it[5]):
		var yt := z_to_y(float(it[2]))
		var top := minf(yh, yt)
		var bot := maxf(yh, yt)
		if bot < -d or top > vs.y + d:
			return
		var bw := d * 0.7
		var bc := c if st != STATE_HELD else c.lerp(Color(1, 1, 1), 0.25)
		var ba := 0.55 if st != STATE_HELD else 0.75
		draw_rect(Rect2(cx - bw * 0.5, top, bw, bot - top), Color(bc.r, bc.g, bc.b, ba))
		# Runde Endkappe in Koerperbreite.
		draw_texture_rect(_disc_tex, Rect2(cx - bw * 0.5, top - bw * 0.5, bw, bw), false,
				Color(bc.r, bc.g, bc.b, minf(ba + 0.3, 1.0)))
	elif yh < -d or yh > vs.y + d:
		return
	var r := Rect2(cx - d * 0.5, yh - d * 0.5, d, d)
	draw_texture_rect(_disc_tex, r, false, c)
	draw_texture_rect(_ring_tex, r, false, c.lerp(Color(1, 1, 1), 0.45))


## Weiche, kantengeglaettete Kreis- bzw. Ring-Textur (weiss, per modulate gefaerbt).
static func _make_circle_tex(ring: bool) -> Texture2D:
	const N := 128
	var img := Image.create(N, N, true, Image.FORMAT_RGBA8)
	var r_out := N * 0.5 - 1.5
	var r_in := r_out - N * 0.11
	for y in N:
		for x in N:
			var dist := Vector2(x + 0.5 - N * 0.5, y + 0.5 - N * 0.5).length()
			var a := clampf(r_out - dist + 0.5, 0.0, 1.0)
			if ring:
				a *= clampf(dist - r_in + 0.5, 0.0, 1.0)
			else:
				# Leicht dunklerer Kern, damit der Kreis nicht flach wirkt.
				var v := lerpf(0.82, 1.0, clampf(dist / r_out, 0.0, 1.0))
				img.set_pixel(x, y, Color(v, v, v, a))
				continue
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _draw_bar(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
	# Heller Oberkante-Glanz: Balken liest sich flach, aber klar.
	draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, r.size.y * 0.18))), c.lerp(Color(1, 1, 1), 0.45))


# ------------------------------------------------------------ Skin-Look

## Pixel pro osu-Einheit (horizontal, mit Spurbreite-Faktor).
func _skin_unit() -> float:
	return _vs().y / ManiaSkin.SCREEN_UNITS * lane_k


## Textur mit Pixelmass (Hoehe aus Seitenverhaeltnis bei Zielbreite w).
func _tex_h(t: Texture2D, w: float) -> float:
	return w * float(t.get_height()) / maxf(1.0, float(t.get_width()))


func _draw_skinned() -> void:
	var vs := _vs()
	var sk := skin
	var u := _skin_unit()
	var uy := vs.y / ManiaSkin.SCREEN_UNITS
	var fr := field_rect()
	var ly := line_y()
	var xs: Array = []
	var ws: Array = []
	for c in columns:
		xs.append(fr.position.x + u * sk.col_offset_units(c))
		ws.append(u * sk.col_units(c))
	draw_rect(fr, Color(0.012, 0.014, 0.02, Settings.field_dim_2d))  # Spielfeld-Deckkraft
	for c in columns:
		if c < _held.size() and bool(_held[c]) and Settings.lane_glow:
			draw_rect(Rect2(float(xs[c]), 0.0, float(ws[c]), ly), Color(lane_color.r, lane_color.g, lane_color.b, 0.07))
	# Spaltenlinien (ColumnLineWidth) zwischen den Spalten.
	for c in columns + 1:
		var lu: float = float(sk.column_line_width[mini(c, sk.column_line_width.size() - 1)])
		if lu <= 0.0:
			continue
		var lw := maxf(1.0, u * lu)
		var lx := fr.end.x if c == columns else float(xs[c])
		draw_rect(Rect2(lx - lw * 0.5, 0.0, lw, vs.y), Color(1, 1, 1, 0.22))
	# Buehnenraender.
	var sl := sk.tex("stage_left")
	if sl != null:
		var w := sl.get_width() * uy * sk.tex_scale("stage_left")
		draw_texture_rect(sl, Rect2(fr.position.x - w, 0.0, w, vs.y), false)
	var sr := sk.tex("stage_right")
	if sr != null:
		var w2 := sr.get_width() * uy * sk.tex_scale("stage_right")
		draw_texture_rect(sr, Rect2(fr.end.x, 0.0, w2, vs.y), false)
	# Abfanglinie (StageHint) bzw. einfache Linie.
	var hint := sk.tex("stage_hint")
	if hint != null:
		var hh := hint.get_height() * uy * sk.tex_scale("stage_hint")
		draw_texture_rect(hint, Rect2(fr.position.x, ly - hh * 0.5, fr.size.x, hh), false)
	elif sk.judgement_line:
		draw_rect(Rect2(fr.position.x, ly - 1.0, fr.size.x, 2.0), Color(1, 1, 1, 0.35))
	if sk.keys_under_notes:
		_draw_skin_keys(xs, ws, ly, vs)
	for it in _items:
		_draw_skin_item(it, xs, ws, vs)
	if not sk.keys_under_notes:
		_draw_skin_keys(xs, ws, ly, vs)


func _draw_skin_keys(xs: Array, ws: Array, ly: float, vs: Vector2) -> void:
	var sk := skin
	for c in columns:
		var on := c < _held.size() and bool(_held[c])
		var key := ("keyd_%d" % c) if on else ("key_%d" % c)
		var t := sk.tex(key)
		if t == null:
			t = sk.tex("key_%d" % c)
		var x := float(xs[c])
		var w := float(ws[c])
		var top := ly
		var h := vs.y * RECEPTOR_H_FRAC
		if t != null:
			h = _tex_h(t, w)
			top = minf(ly, vs.y - h)
			draw_texture_rect(t, Rect2(x, top, w, h), false)
		else:
			# Fallback: eingebauter Receptor fuer genau diese Spalte.
			var fl := clampf(float(_flash[c]) if c < _flash.size() else 0.0, 0.0, 1.0)
			var fc: Color = _flash_col[c] if c < _flash_col.size() else lane_color
			var base := lane_color.lerp(fc, fl * 0.6)
			var r := Rect2(x + 2.0, ly, w - 4.0, h)
			draw_rect(r, Color(base.r, base.g, base.b, minf(0.14 + (0.45 if on else 0.0) + fl * 0.25, 0.85)))
			draw_rect(r, Color(base.r, base.g, base.b, 0.9 if on else 0.55), false, 2.0)
			top = ly
		if show_keys and c < key_names.size() and _font != null:
			var fs := int(vs.y * 0.02)
			if preview_size.x > 0.0:
				fs = 11
			var txt := key_names[c]
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, Vector2(x + (w - tw) * 0.5, minf(top + h * 0.5 + fs * 0.35, vs.y - 2.0)),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 if on else 0.4))


func _draw_skin_item(it: Array, xs: Array, ws: Array, vs: Vector2) -> void:
	var sk := skin
	var col: int = it[0]
	if col < 0 or col >= columns:
		return
	var x := float(xs[col])
	var w := float(ws[col])
	var yh := z_to_y(float(it[1]))   # Noten-Unterkante = Trefferzeit
	var st: int = it[4]
	var mod := Color(1, 1, 1, 1)
	if st == STATE_DEAD:
		mod = Color(0.5, 0.5, 0.55, 0.8)
	var head := sk.tex("head_%d" % col) if bool(it[5]) else null
	if head == null:
		head = sk.tex("note_%d" % col)
	if head == null:
		head = sk.tex("head_%d" % col)
	# Notengroesse skaliert gleichmaessig: Breite = Spalte * note_k, Hoehe aus Seitenverhaeltnis.
	var nw := w * note_k
	var nx := x + (w - nw) * 0.5
	var hh := _tex_h(head, nw) if head != null else vs.y * NOTE_H_FRAC * note_k
	if bool(it[5]):
		var yt := z_to_y(float(it[2]))
		var top := minf(yh, yt)
		var bot := maxf(yh, yt)
		if bot < -hh or top > vs.y + hh:
			return
		var tail := sk.tex("tail_%d" % col)
		var th := (_tex_h(tail, nw) if tail != null else (hh if head != null else vs.y * NOTE_H_FRAC * note_k))
		var body := sk.tex("body_%d" % col)
		var bm := mod
		if st == STATE_HELD:
			bm = Color(1.15, 1.15, 1.15, 1)
		var body_bot := yh - hh * 0.5
		if body_bot > top:
			if body != null:
				_draw_body(body, nx, nw, top, body_bot, bm)
			else:
				var cc: Color = it[3] if st != STATE_DEAD else Color(0.36, 0.37, 0.41, 0.8)
				var bw := w * 0.72
				draw_rect(Rect2(x + (w - bw) * 0.5, top, bw, body_bot - top), Color(cc.r, cc.g, cc.b, 0.55 if st != STATE_HELD else 0.75))
		# Ende: eigene Textur, sonst Kopf vertikal gespiegelt, sonst Balken.
		if tail != null:
			draw_texture_rect(tail, Rect2(nx, top - th, nw, th), false, mod)
		elif head != null:
			draw_texture_rect(head, Rect2(nx, top, nw, -th), false, mod)
	elif yh < -hh or yh > vs.y + hh:
		return
	if head != null:
		draw_texture_rect(head, Rect2(nx, yh - hh, nw, hh), false, mod)
	else:
		var c: Color = it[3] if st != STATE_DEAD else Color(0.36, 0.37, 0.41, 0.8)
		_draw_bar(Rect2(x + 2.0, yh - hh, w - 4.0, hh), c)


## Hold-Koerper: NoteBodyStyle 0 = gestreckt, 1 = gekachelt ab Kopf (unten), 2 = ab Ende (oben).
func _draw_body(t: Texture2D, x: float, w: float, top: float, bot: float, mod: Color) -> void:
	var blen := bot - top
	var th := maxf(1.0, _tex_h(t, w))
	if skin.note_body_style == 0 or blen / th > 200.0:
		draw_texture_rect(t, Rect2(x, top, w, blen), false, mod)
		return
	var tw := float(t.get_width())
	var tht := float(t.get_height())
	var from_bottom := skin.note_body_style == 1
	var done := 0.0
	while done < blen - 0.01:
		var seg := minf(th, blen - done)
		var frac := seg / th
		var y := (bot - done - seg) if from_bottom else (top + done)
		var sy := (tht - tht * frac) if from_bottom else 0.0
		draw_texture_rect_region(t, Rect2(x, y, w, seg), Rect2(0.0, sy, tw, tht * frac), mod)
		done += seg
