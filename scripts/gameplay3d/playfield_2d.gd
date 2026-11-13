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
	# Kein Full-Rect-Anker: Position/Skalierung setzt _apply_stage_xf (Richtung, Groesse).
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_font = ThemeDB.fallback_font
	_apply_stage_xf()


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
	_apply_stage_xf()
	queue_redraw()


func line_y() -> float:
	if _own():
		return _vs().y * float(Settings.hit_position_2d) / ManiaSkin.SCREEN_UNITS
	if skin != null:
		return _vs().y * skin.hit_position / ManiaSkin.SCREEN_UNITS
	return _vs().y * LINE_FRAC


## Eigene Layout-Werte statt Skin-/Standard-Werten (Settings.skin_values_2d aus)?
func _own() -> bool:
	return not Settings.skin_values_2d


## Spaltenabstand in osu!-Einheiten zwischen Spalte c und c+1.
func _spacing_units(c: int) -> float:
	if _own():
		return float(Settings.column_spacing_2d)
	if skin != null and c < skin.column_spacing.size():
		return float(skin.column_spacing[c])
	return 0.0


## Skin: Buehnenbreite und linke Spaltenkante in osu!-Einheiten (mit Abstand-Override).
func _sk_stage_units() -> float:
	return _sk_col_off(columns - 1) + skin.col_units(columns - 1)


func _sk_col_off(col: int) -> float:
	var x := 0.0
	for c in col:
		x += skin.col_units(c) + _spacing_units(c)
	return x


## Eingebauter Look: Spaltenabstand in Pixeln, linke Kante einer Spalte.
func _gap_px() -> float:
	return _spacing_units(0) * _vs().y / ManiaSkin.SCREEN_UNITS * lane_k


func _bx(fr: Rect2, c: int) -> float:
	return fr.position.x + (col_width() + _gap_px()) * c


func col_width() -> float:
	if skin != null:
		return _skin_unit() * _sk_stage_units() / float(maxi(columns, 1))
	return _vs().y * COL_W_FRAC * lane_k


func field_rect() -> Rect2:
	var vs := _vs()
	var sw := 0.0
	if skin != null:
		sw = _skin_unit() * _sk_stage_units()
	else:
		sw = col_width() * columns + _gap_px() * (columns - 1)
	var x := (vs.x - sw) * 0.5
	if _own():
		if Settings.stage_pos_2d != Settings.STAGE_CENTER:
			# osu! ColumnStart 136 (Standard) ab dem Rand; in der Vorschau knapp am Rand.
			var m := 8.0 if preview_size.x > 0.0 else 136.0 * vs.y / ManiaSkin.SCREEN_UNITS
			x = m if Settings.stage_pos_2d == Settings.STAGE_LEFT else vs.x - sw - m
			x = clampf(x, 0.0, maxf(0.0, vs.x - sw))
	elif skin != null and _is_osu_skin() and skin.has_column_start and is_equal_approx(lane_k, 1.0) \
			and preview_size.x <= 0.0:
		# osu!: ColumnStart = linke Buehnenkante in 480er-Einheiten ab Bildrand (die
		# Skins rechnen damit fuer 16:9). Nur bei Original-Spurbreite und nicht in der
		# Vorschau; sonst mittig wie bisher.
		x = clampf(skin.column_start * vs.y / ManiaSkin.SCREEN_UNITS, 0.0, maxf(0.0, vs.x - sw))
	return Rect2(x, 0.0, sw, vs.y)


## Z (Strecke) -> Bild-Y: linear, Z_FAR an der Oberkante.
func z_to_y(z: float) -> float:
	return line_y() - (z_line - z) / (z_line - z_far) * line_y()


## osu!-Einheiten von oben (480 = Bildhoehe) -> Y im Feld.
func units_to_y(u: float) -> float:
	return _vs().y * u / ManiaSkin.SCREEN_UNITS


func _vs() -> Vector2:
	if preview_size.x > 0.0 and preview_size.y > 0.0:
		return preview_size
	if not is_inside_tree():   # setup() vor add_child: noch kein Viewport
		return Vector2(1920, 1080)
	var r := get_viewport_rect().size
	return r if r.x > 0.0 else Vector2(1920, 1080)


# ------------------------------------------- Buehne: Richtung + Skalierung
# Scroll nach oben (osu! UpsideDown) und Skalierung als Control-Transform: das Feld
# wird intern immer "nach unten" gezeichnet, scale.y = -s spiegelt es (Texturen wie
# osu! mit NoteFlip/KeyFlip-Standard 1), Texte/Judgements werden zurueckgedreht.
# Skaliert wird um die Unterkante (bzw. Oberkante bei "oben") der Feldmitte;
# clip_contents schneidet das kleinere Feld oben sauber ab.

## Position im Eltern-Control (Vorschau: Versatz in der Box; Spiel: 0).
var base_pos := Vector2.ZERO


func _up() -> bool:
	return Settings.scroll_up_2d


## Feld -> Eltern-/Bildkoordinaten.
func stage_xf() -> Transform2D:
	var vs := _vs()
	var s := Settings.stage_scale_2d
	var cx := field_rect().get_center().x
	var sy := -s if _up() else s
	# Oben: Feld-Unterkante an die Oberkante (Vorschau: Box-Oberkante, base_pos.y
	# verschiebt nur den Ausschnitt nach unten).
	var py := s * vs.y if _up() else base_pos.y + vs.y * (1.0 - s)
	return Transform2D(Vector2(s, 0.0), Vector2(0.0, sy), Vector2(base_pos.x + cx * (1.0 - s), py))


func _apply_stage_xf() -> void:
	if preview_size.x <= 0.0:
		var vs := _vs()
		if size != vs:
			size = vs
	var t := stage_xf()
	var sc := Vector2(t.x.x, t.y.y)
	if scale != sc:
		scale = sc
	if position != t.origin:
		position = t.origin
	var clip := Settings.stage_scale_2d < 0.999
	if clip_contents != clip:
		clip_contents = clip


func to_screen(p: Vector2) -> Vector2:
	return stage_xf() * p


func screen_line_y() -> float:
	return to_screen(Vector2(0.0, line_y())).y


func screen_field_rect() -> Rect2:
	var fr := field_rect()
	var a := to_screen(fr.position)
	var b := to_screen(fr.end)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


## Texte/Bilder lesbar halten: bei "oben" um die Zeile cy zurueckspiegeln.
func _upright(cy: float) -> void:
	if _up():
		draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(0, -1), Vector2(0.0, 2.0 * cy)))


func _reset_xf() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw() -> void:
	_update_mask()
	if skin != null:
		if _is_osu_skin():
			_draw_osu()
		else:
			_draw_skinned()
		return
	var vs := _vs()
	var fr := field_rect()
	var cw := col_width()
	var ly := line_y()
	var gap := _gap_px()
	# Spalten-Hintergrund: dunkel, halbtransparent; gedrueckte Spalte hellt auf.
	if gap <= 0.0:
		draw_rect(fr, Color(0.012, 0.014, 0.02, Settings.field_dim_2d))  # Spielfeld-Deckkraft
	for c in columns:
		var x := _bx(fr, c)
		if gap > 0.0:
			draw_rect(Rect2(x, 0.0, cw, vs.y), Color(0.012, 0.014, 0.02, Settings.field_dim_2d))
		if c < _held.size() and bool(_held[c]) and Settings.lane_glow:
			var g := Rect2(x, 0.0, cw, ly)
			draw_rect(g, Color(lane_color.r, lane_color.g, lane_color.b, 0.07))
	# Feine Trennlinien + Rand (mit Spaltenabstand: beide Kanten jeder Spalte).
	for c in columns + 1:
		if gap > 0.0:
			if c < columns:
				var xl := _bx(fr, c)
				draw_line(Vector2(xl, 0.0), Vector2(xl, vs.y), Color(1, 1, 1, 0.30), 1.0)
				draw_line(Vector2(xl + cw, 0.0), Vector2(xl + cw, vs.y), Color(1, 1, 1, 0.30), 1.0)
			continue
		var a := 0.30 if (c == 0 or c == columns) else 0.10
		var x := fr.position.x + cw * c
		draw_line(Vector2(x, 0.0), Vector2(x, vs.y), Color(1, 1, 1, a), 1.0)
	var nh := note_h()
	var keys_under := _own() and Settings.keys_under_notes_2d
	if _own() and Settings.hit_line_2d:
		draw_rect(Rect2(fr.position.x, ly - 1.0, fr.size.x, 2.0), Color(1, 1, 1, 0.45))
	if keys_under:
		_draw_receptors(fr, cw, ly, nh, vs)
	# Noten/Holds.
	var pad := maxf(2.0, cw * 0.06)
	for it in _items:
		var col: int = it[0]
		var x0 := _bx(fr, col) + pad
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
			_nd_rect(body, Color(bc.r, bc.g, bc.b, 0.55 if st != STATE_HELD else 0.75))
			_nd_rect(Rect2(x0, top - nh * 0.25, w, nh * 0.5), Color(c.r, c.g, c.b, 0.95))
			_draw_bar(Rect2(x0, yh - nh * 0.5, w, nh), c)
		else:
			if yh < -nh or yh > vs.y + nh:
				continue
			_draw_bar(Rect2(x0, yh - nh * 0.5, w, nh), c)
	if not keys_under:
		_draw_receptors(fr, cw, ly, nh, vs)


## Receptors + Tastenbeschriftung (eingebauter Look).
func _draw_receptors(fr: Rect2, cw: float, ly: float, nh: float, vs: Vector2) -> void:
	# Keine durchgehende Abfanglinie: nur die Receptors markieren die Trefferposition.
	var rh := vs.y * RECEPTOR_H_FRAC
	var pad := maxf(2.0, cw * 0.06)
	draw_rect(Rect2(fr.position.x, ly + nh * 0.5, fr.size.x, vs.y - ly), Color(0.0, 0.0, 0.0, 0.55))
	for c in columns:
		var x := _bx(fr, c)
		var r := Rect2(x + pad, ly - nh * 0.5, cw - pad * 2.0, nh)
		var on := c < _held.size() and bool(_held[c])
		var fl := clampf(float(_flash[c]) if c < _flash.size() and Settings.hit_lighting_2d else 0.0, 0.0, 1.0)
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
			var by := ly + nh * 0.5 + rh * 0.5 + fs * 0.35
			_upright(by - fs * 0.35)
			draw_string(_font, Vector2(x + (cw - tw) * 0.5, by),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 if on else 0.4))
			_reset_xf()


# ------------------------------------------------ Mods: FadeIn/Hidden/Cover
# Wie lazer (PlayfieldCoveringWrapper): eine Abdeckung mit weichem Rand blendet
# Noten aus, Spielfeld/Tasten bleiben sichtbar. Gezeichnet wird als Maske: jede
# Noten-Flaeche wird in Streifen konstanter Deckkraft zerlegt (_mask_slices).
# FadeIn: Abdeckung oben (Noten tauchen auf), Hidden: an der Linie (Noten
# verschwinden); beide 16 % -> 40 % mit der Kombo (lazer: +0,05 % je Kombo).
# Cover: feste Abdeckung (Settings.cover_pct_2d) von oben oder unten.

const HIDDEN_MIN := 0.16
const HIDDEN_MAX := 0.40
const HIDDEN_PER_COMBO := 0.0005
const MASK_FADE := 0.25   ## weicher Rand: Anteil der Abdeckung
const MASK_STEPS := 6

var _mask := false
var _m0 := 0.0   ## Deckkraft 0 bei _m0 ...
var _m1 := 1.0   ## ... bis 1 bei _m1 (linear), ausserhalb konstant


## Replay: Sicht-Mods des aufgezeichneten Laufs (GameSession.mods: FI/HD/CO,
## CO_pct, CO_bottom) statt der aktuellen Einstellung. Vorher zeigte ein
## Hidden-Replay das Feld ohne Abdeckung, sobald die Einstellung anders stand.
var _run_vis := -1
var _run_cover_pct := 50
var _run_cover_bottom := false


func set_run_mods(m: Dictionary) -> void:
	var v := ManiaCore.vis_mods(m)
	_run_vis = int(v.vis)
	_run_cover_pct = int(v.pct)
	_run_cover_bottom = bool(v.bottom)


func _vis() -> int:
	return _run_vis if _run_vis >= 0 else Settings.mod_vis_2d


## Abdeckungsanteil (0..1 der Strecke Oberkante -> Linie) fuer den aktuellen Mod.
func cover_fraction() -> float:
	match _vis():
		Settings.VIS_FADE_IN, Settings.VIS_HIDDEN:
			return minf(HIDDEN_MAX, HIDDEN_MIN + float(_combo) * HIDDEN_PER_COMBO)
		Settings.VIS_COVER:
			return float(_run_cover_pct if _run_vis >= 0 else Settings.cover_pct_2d) / 100.0
	return 0.0


## Wie cover_from_top(), mit den Mods des Laufs (Replay).
func covers_from_top() -> bool:
	if _run_vis < 0:
		return cover_from_top()
	return _run_vis == Settings.VIS_FADE_IN or (_run_vis == Settings.VIS_COVER and not _run_cover_bottom)


## Abdeckung von oben (true) oder von der Linie aus (false)?
static func cover_from_top() -> bool:
	match Settings.mod_vis_2d:
		Settings.VIS_FADE_IN:
			return true
		Settings.VIS_COVER:
			return not Settings.cover_from_bottom_2d
	return false


func _update_mask() -> void:
	var f := cover_fraction()
	_mask = f > 0.0
	if not _mask:
		return
	var ly := line_y()
	var cov := ly * f
	var g := maxf(1.0, cov * MASK_FADE)
	if covers_from_top():
		_m0 = cov - g
		_m1 = cov
	else:
		_m0 = ly - cov + g
		_m1 = ly - cov


## Deckkraft der Maske an Feld-Y.
func mask_alpha(y: float) -> float:
	if not _mask:
		return 1.0
	return clampf((y - _m0) / (_m1 - _m0), 0.0, 1.0)


## [top, bot] -> Streifen [[y0, y1, deckkraft], ...] (unsichtbare entfallen).
func _mask_slices(top: float, bot: float) -> Array:
	if not _mask:
		return [[top, bot, 1.0]]
	var out: Array = []
	var lo := minf(_m0, _m1)
	var hi := maxf(_m0, _m1)
	var cuts: Array = [top]
	for k in MASK_STEPS + 1:
		var y := lo + (hi - lo) * float(k) / float(MASK_STEPS)
		if y > top and y < bot:
			cuts.append(y)
	cuts.append(bot)
	for i in cuts.size() - 1:
		var y0: float = cuts[i]
		var y1: float = cuts[i + 1]
		if y1 - y0 <= 0.01:
			continue
		var a := mask_alpha((y0 + y1) * 0.5)
		if a > 0.004:
			out.append([y0, y1, a])
	return out


## Noten-Rechteck mit Maske.
func _nd_rect(r: Rect2, c: Color) -> void:
	if not _mask:
		draw_rect(r, c)
		return
	for s in _mask_slices(r.position.y, r.end.y):
		draw_rect(Rect2(r.position.x, s[0], r.size.x, s[1] - s[0]), Color(c.r, c.g, c.b, c.a * s[2]))


## Noten-Textur mit Maske; src leer = ganze Textur; flip_v = senkrecht gespiegelt.
func _nd_tex(t: Texture2D, r: Rect2, mod: Color, src: Rect2 = Rect2(), flip_v: bool = false) -> void:
	if src.size == Vector2.ZERO:
		src = Rect2(Vector2.ZERO, t.get_size())
	if not _mask and not flip_v:
		draw_texture_rect_region(t, r, src, mod)
		return
	var top := r.position.y
	var h := maxf(r.size.y, 0.001)
	for s in _mask_slices(top, r.end.y):
		var y0: float = s[0]
		var y1: float = s[1]
		var f0 := (y0 - top) / h
		var f1 := (y1 - top) / h
		var sy := src.position.y + ((1.0 - f1) if flip_v else f0) * src.size.y
		var sr := Rect2(src.position.x, sy, src.size.x, (f1 - f0) * src.size.y)
		var m := Color(mod.r, mod.g, mod.b, mod.a * s[2])
		if flip_v:
			draw_set_transform(Vector2(0.0, y0 + y1), 0.0, Vector2(1.0, -1.0))
		draw_texture_rect_region(t, Rect2(r.position.x, y0, r.size.x, y1 - y0), sr, m)
		if flip_v:
			_reset_xf()


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
		_nd_rect(Rect2(cx - bw * 0.5, top, bw, bot - top), Color(bc.r, bc.g, bc.b, ba))
		# Runde Endkappe in Koerperbreite: nur die obere Kreishaelfte, gleiche Farbe/Deckkraft
		# wie der Koerper (kein heller Ball am Ende).
		var ts := Vector2(_disc_tex.get_size())
		_nd_tex(_disc_tex, Rect2(cx - bw * 0.5, top - bw * 0.5, bw, bw * 0.5),
				Color(bc.r, bc.g, bc.b, ba), Rect2(0, 0, ts.x, ts.y * 0.5))
	elif yh < -d or yh > vs.y + d:
		return
	var r := Rect2(cx - d * 0.5, yh - d * 0.5, d, d)
	_nd_tex(_disc_tex, r, c)
	_nd_tex(_ring_tex, r, c.lerp(Color(1, 1, 1), 0.45))


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
	_nd_rect(r, c)
	# Heller Oberkante-Glanz: Balken liest sich flach, aber klar.
	_nd_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, r.size.y * 0.18))), c.lerp(Color(1, 1, 1), 0.45))


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
		xs.append(fr.position.x + u * _sk_col_off(c))
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
	var line_on := Settings.hit_line_2d if _own() else true
	if hint != null and line_on:
		var hh := hint.get_height() * uy * sk.tex_scale("stage_hint")
		draw_texture_rect(hint, Rect2(fr.position.x, ly - hh * 0.5, fr.size.x, hh), false)
	elif (Settings.hit_line_2d if _own() else sk.judgement_line):
		draw_rect(Rect2(fr.position.x, ly - 1.0, fr.size.x, 2.0), Color(1, 1, 1, 0.35))
	var ku := _keys_under()
	if ku:
		_draw_skin_keys(xs, ws, ly, vs)
	for it in _items:
		_draw_skin_item(it, xs, ws, vs)
	if not ku:
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
			var fl := clampf(float(_flash[c]) if c < _flash.size() and Settings.hit_lighting_2d else 0.0, 0.0, 1.0)
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
			var by := minf(top + h * 0.5 + fs * 0.35, vs.y - 2.0)
			_upright(by - fs * 0.35)
			draw_string(_font, Vector2(x + (w - tw) * 0.5, by),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.75 if on else 0.4))
			_reset_xf()


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
	# Eingebaute Skins: Graustufen-Bilder, hier mit Noten- bzw. Hold-Farbe getoent.
	var tn := Color(1, 1, 1, 1)
	var th_c := Color(1, 1, 1, 1)
	if sk.tintable:
		var tt := sk.tints(col, it[3], bool(it[5]))
		tn = tt[0]
		th_c = tt[1]
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
		# Kugelfoermige Tails (fast quadratisch, typisch bei Kreis-Skins) weglassen:
		# kein Ball am Hold-Ende. Flache Kappen bleiben.
		if tail != null and float(tail.get_height()) >= float(tail.get_width()) * 0.6:
			tail = null
		var th := (_tex_h(tail, nw) if tail != null else (hh if head != null else vs.y * NOTE_H_FRAC * note_k))
		var body := sk.tex("body_%d" % col)
		var bm := mod * th_c
		if st == STATE_HELD:
			bm = Color(1.15, 1.15, 1.15, 1) * th_c
		var body_bot := yh - hh * 0.5
		if body_bot > top:
			if body != null:
				_draw_body(body, nx, nw, top, body_bot, bm)
			else:
				var cc: Color = it[3] if st != STATE_DEAD else Color(0.36, 0.37, 0.41, 0.8)
				var bw := w * 0.72
				_nd_rect(Rect2(x + (w - bw) * 0.5, top, bw, body_bot - top), Color(cc.r, cc.g, cc.b, 0.55 if st != STATE_HELD else 0.75))
		# Ende: nur eine eigene Tail-Textur des Skins. Fehlt sie, kein gespiegelter
		# Kopf mehr (bei Kreis-Skins war das ein zweiter Ball am Hold-Ende).
		if tail != null:
			_nd_tex(tail, Rect2(nx, top - th, nw, th), mod * tn)
	elif yh < -hh or yh > vs.y + hh:
		return
	if head != null:
		_nd_tex(head, Rect2(nx, yh - hh, nw, hh), mod * tn)
	else:
		var c: Color = it[3] if st != STATE_DEAD else Color(0.36, 0.37, 0.41, 0.8)
		_draw_bar(Rect2(x + 2.0, yh - hh, w - 4.0, hh), c)


## Hold-Koerper: NoteBodyStyle 0 = gestreckt, 1 = gekachelt ab Kopf (unten), 2 = ab Ende (oben).
func _draw_body(t: Texture2D, x: float, w: float, top: float, bot: float, mod: Color) -> void:
	var blen := bot - top
	var th := maxf(1.0, _tex_h(t, w))
	if skin.note_body_style == 0 or blen / th > 200.0:
		_nd_tex(t, Rect2(x, top, w, blen), mod)
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
		_nd_tex(t, Rect2(x, y, w, seg), mod, Rect2(0.0, sy, tw, tht * frac))
		done += seg


# ------------------------------------------------- osu!-Skin (importiert)
# Zeichnet importierte osu!mania-Skins wie osu! (Regeln aus lazer
# osu.Game.Rulesets.Mania.Skinning.Legacy: LegacyStageBackground, LegacyNotePiece,
# LegacyBodyPiece, LegacyHoldNoteTailPiece, LegacyKeyArea, LegacyHitTarget,
# LegacyColumnBackground, LegacyStageForeground, LegacyHitExplosion,
# LegacyManiaJudgementPiece, LegacyManiaComboCounter). Masse: ini-Positionen in
# 480er-Einheiten (u = H/480), Texturen in Pixeln des 768er-Raums (H/768, @2x halb).
# Eingebaute Skins (res://) behalten den eigenen Look (_draw_skinned).

const DARK_GRAY := Color(169.0 / 255.0, 169.0 / 255.0, 169.0 / 255.0, 1.0)  ## lazer Colour4.DarkGray (verpasst)
const Q_MISS := 5            ## ManiaCore.Quality.MISS

var _judge_q := -1           ## letztes Judgement (ManiaCore.Quality), -1 = keins
var _judge_t0 := -1e9        ## Startzeit (ms)
var _judge_rot := 0.0
var _combo := 0
var _combo_t0 := -1e9
var _expl_t0: Array = []     ## je Spalte: Startzeit LightingN
var _light_rel: Array = []   ## je Spalte: Loslass-Zeit fuer das StageLight-Ausblenden
var _prev_held: Array = []


## Tasten unter den Noten (osu! KeysUnderNotes)?
func _keys_under() -> bool:
	if _own():
		return Settings.keys_under_notes_2d
	return skin != null and skin.keys_under_notes


## Judgement-/Kombo-Mitte (Feld-Y): eigene Werte oder skin.ini (Built-in: lazer-Standard).
func judge_y() -> float:
	if _own():
		return units_to_y(float(Settings.judge_pos_2d))
	return units_to_y(skin.score_position if skin != null else float(Settings.JUDGE_POS_DEFAULT))


func combo_y() -> float:
	if _own():
		return units_to_y(float(Settings.combo_pos_2d))
	return units_to_y(skin.combo_position if skin != null else float(Settings.COMBO_POS_DEFAULT))


func _is_osu_skin() -> bool:
	return skin != null and not skin._dir.begins_with("res://")


## Zeigt Playfield2D Judgements/Kombo selbst? (Dann blendet mania_3d die Text-Anzeige aus.)
func draws_judgements() -> bool:
	return _is_osu_skin() and skin.has_judgement_images()


func _now_ms() -> float:
	return float(Time.get_ticks_usec()) / 1000.0


## Treffer melden (mania_3d._on_note_judged): Judgement-Bild + LightingN.
func on_judge(quality: int, col: int) -> void:
	_judge_q = quality
	_judge_t0 = _now_ms()
	_judge_rot = randf_range(-5.73, 5.73)
	if quality != Q_MISS and col >= 0:
		while _expl_t0.size() <= col:
			_expl_t0.append(-1e9)
		_expl_t0[col] = _judge_t0


func set_combo(c: int) -> void:
	if c > _combo:
		_combo_t0 = _now_ms()
	_combo = c


func _px() -> float:
	return _vs().y / 768.0


## Texturgroesse in Bildpixeln (nativ im 768er-Raum, @2x halbiert).
func _tex_px(key: String, t: Texture2D) -> Vector2:
	return Vector2(t.get_size()) * _px() * skin.tex_scale(key)


func _draw_osu() -> void:
	var vs := _vs()
	var sk := skin
	var u := _skin_unit()
	var fr := field_rect()
	var ly := line_y()
	var now := _now_ms()
	var xs: Array = []
	var ws: Array = []
	for c in columns:
		xs.append(fr.position.x + u * _sk_col_off(c))
		ws.append(u * sk.col_units(c))
	_track_press(now)
	# Spalten-Hintergrund: Colour# (Standard Schwarz), Alpha quadriert (osu!-stable).
	for c in columns:
		var bc: Color = sk.colours.get(c, Color(0, 0, 0, 1))
		draw_rect(Rect2(float(xs[c]), 0.0, float(ws[c]), vs.y), Color(bc.r, bc.g, bc.b, bc.a * bc.a))
	# Spaltenlinien von oben bis zur Trefferlinie, Breite x 0,74 im 768er-Raum.
	var lc := sk.colour_column_line
	var lcol := Color(lc.r, lc.g, lc.b, lc.a * lc.a)
	for c in columns:
		var lw_l := float(sk.column_line_width[c]) * 0.74 * _px()
		var lw_r := float(sk.column_line_width[c + 1]) * 0.74 * _px()
		if lw_l > 0.0:
			draw_rect(Rect2(float(xs[c]), 0.0, lw_l, ly), lcol)
		if lw_r > 0.0 and (sk.version >= 2.4 or c == columns - 1):
			draw_rect(Rect2(float(xs[c]) + float(ws[c]) - lw_r, 0.0, lw_r, ly), lcol)
	# StageLight: Unterkante bei LightPosition, beim Druecken voll, beim Loslassen
	# 250 ms ausblenden und in Y zusammenziehen.
	var lt := sk.tex("stage_light")
	if lt != null:
		var lyb := sk.light_position * vs.y / ManiaSkin.SCREEN_UNITS
		for c in columns:
			var k := 1.0
			if not (c < _held.size() and bool(_held[c])):
				k = 1.0 - clampf((now - float(_light_rel[c])) / 250.0, 0.0, 1.0)
			if k <= 0.0:
				continue
			var lh := _tex_px("stage_light", lt).y * k
			var cl: Color = sk.colour_light.get(c, Color(55.0 / 255.0, 1, 1))
			draw_texture_rect(lt, Rect2(float(xs[c]), lyb - lh, float(ws[c]), lh), false,
					Color(cl.r, cl.g, cl.b, maxf(cl.a, 1.0 / 255.0) * k))
	# Buehnenraender: native Breite, volle Hoehe.
	var sl := sk.tex("stage_left")
	if sl != null:
		var w := _tex_px("stage_left", sl).x
		draw_texture_rect(sl, Rect2(fr.position.x - w, 0.0, w, vs.y), false)
	var sr := sk.tex("stage_right")
	if sr != null:
		draw_texture_rect(sr, Rect2(fr.end.x, 0.0, _tex_px("stage_right", sr).x, vs.y), false)
	# Trefferlinie: StageHint (Hoehe x 0,9 x 1,6025, mittig auf der Linie) und/oder JudgementLine.
	var hint := sk.tex("stage_hint")
	var line_on := Settings.hit_line_2d if _own() else true
	if hint != null and line_on:
		var hh := _tex_px("stage_hint", hint).y * 0.9 * 1.6025
		draw_texture_rect(hint, Rect2(fr.position.x, ly - hh * 0.5, fr.size.x, hh), false)
	if (line_on and hint == null) if _own() else sk.judgement_line:
		var jc := sk.colour_judgement_line
		draw_rect(Rect2(fr.position.x, ly, fr.size.x, maxf(1.0, _px())), Color(jc.r, jc.g, jc.b, jc.a * 0.9))
	var ku := _keys_under()
	if ku:
		_draw_osu_keys(xs, ws, vs)
	# osu!/lazer: fruehere Objekte liegen oben (naeher an der Linie = zuletzt gezeichnet),
	# z. B. Hold-Ende ueber dem Kopf der direkt folgenden Note.
	var order := _items.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	# Zwei Ebenen: erst alle Hold-Koerper/-Enden, dann alle Noten/Koepfe obendrauf -
	# sonst schneiden deckende Hold-Enden (z. B. schwarze Kappen) die naechste Note
	# zum Halbkreis ab, sobald die Noten groesser sind (Spurbreite > 100 %).
	for layer in 2:
		for it in order:
			_draw_osu_item(it, xs, ws, vs, ly, layer)
	if not ku:
		_draw_osu_keys(xs, ws, vs)
	# StageBottom (x 1,6), unten mittig, ueber Noten und Tasten.
	var sb := sk.tex("stage_bottom")
	if sb != null:
		var sz := _tex_px("stage_bottom", sb) * 1.6
		draw_texture_rect(sb, Rect2(fr.get_center().x - sz.x * 0.5, vs.y - sz.y, sz.x, sz.y), false)
	if Settings.hit_lighting_2d:
		_draw_osu_lighting(xs, ws, ly, now)
	_draw_osu_judgement(fr, vs, now)
	_draw_osu_combo(fr, vs, now)


func _track_press(now: float) -> void:
	while _light_rel.size() < columns:
		_light_rel.append(-1e9)
		_prev_held.append(false)
	for c in columns:
		var on := c < _held.size() and bool(_held[c])
		if bool(_prev_held[c]) and not on:
			_light_rel[c] = now
		_prev_held[c] = on


## Tasten: Spaltenbreite, native Hoehe, Unterkante am Bildrand.
func _draw_osu_keys(xs: Array, ws: Array, vs: Vector2) -> void:
	for c in columns:
		var on := c < _held.size() and bool(_held[c])
		var key := ("keyd_%d" % c) if on else ("key_%d" % c)
		var t := skin.tex(key)
		if t == null:
			continue
		var h := _tex_px(key, t).y
		draw_texture_rect(t, Rect2(float(xs[c]), vs.y - h, float(ws[c]), h), false)


## Notenhoehe: Texturhoehe / Texturbreite x WidthForNoteHeightScale (sonst schmalste
## Spalte); die Notengroesse aus den Einstellungen skaliert die Hoehe.
func _osu_note_h(t: Texture2D) -> float:
	return float(t.get_height()) / maxf(1.0, float(t.get_width())) \
			* skin.note_height_units() * _skin_unit() * note_k


## layer 0: Hold-Koerper und -Enden, layer 1: Noten und Hold-Koepfe.
func _draw_osu_item(it: Array, xs: Array, ws: Array, vs: Vector2, ly: float, layer: int = 1) -> void:
	var sk := skin
	var col: int = it[0]
	if col < 0 or col >= columns:
		return
	var x := float(xs[col])
	var w := float(ws[col])
	var st: int = it[4]
	var mod := DARK_GRAY if st == STATE_DEAD else Color(1, 1, 1, 1)
	var yh := z_to_y(float(it[1]))   # Unterkante der Note = Trefferzeit
	if not bool(it[5]):
		if layer != 1:
			return
		var nt := sk.tex("note_%d" % col)
		if nt == null:
			return
		var nh := _osu_note_h(nt)
		if yh < 0.0 or yh - nh > vs.y:
			return
		_nd_tex(nt, Rect2(x, yh - nh, w, nh), mod)
		return
	if st == STATE_HELD:
		yh = minf(yh, ly)   # Kopf bleibt beim Halten an der Linie
	var yt := z_to_y(float(it[2]))
	var head := sk.tex("head_%d" % col)
	var hh := _osu_note_h(head) if head != null else 0.0
	# Importierte Skins exakt wie das Original (Nutzer-Wunsch): eigenes Tail-Bild,
	# fehlt es, der Kopf als Ende (lazer LegacyHoldNoteTailPiece: Tail ?? Head).
	var tail := sk.tex("tail_%d" % col)
	if tail == null:
		tail = head
	var th := _osu_note_h(tail) if tail != null else hh
	if yh < 0.0 or yt - th > vs.y:
		return
	if layer == 1:
		if head != null:
			_nd_tex(head, Rect2(x, yh - hh, w, hh), mod)
		return
	var body := sk.tex("body_%d" % col)
	var b_top := yt - th * 0.5
	var b_bot := yh - hh * 0.5
	if body != null and b_bot > b_top:
		_draw_osu_body(col, body, x, w, b_top, b_bot, mod)
	if tail != null:
		# Ende gespiegelt (osu!/lazer: LegacyHoldNoteTailPiece dreht die Richtung um).
		# Wie eine Note am Endzeitpunkt (yt = Unterkante), vertikal gespiegelt.
		_nd_tex(tail, Rect2(x, yt - th, w, th), mod, Rect2(), true)


## Hold-Koerper. NoteBodyStyle 0: gestreckt. 1: ab oben (Ende) in nativer Hoehe
## wiederholt, 2: ab unten (Kopf). Breite immer Spaltenbreite.
func _draw_osu_body(col: int, t: Texture2D, x: float, w: float, top: float, bot: float, mod: Color) -> void:
	var key := "body_%d" % col
	if skin.note_body_style == 0:
		_nd_tex(t, Rect2(x, top, w, bot - top), mod)
		return
	var tw := float(t.get_width())
	var src_h := skin.tex_src_h(key)
	var tile := maxf(1.0, src_h * _px() * skin.tex_scale(key))   # Hoehe einer Kachel in Pixeln
	var rows := float(t.get_height())                           # geladene Zeilen (evtl. abgeschnitten)
	var from_top := skin.note_body_style == 1
	var blen := bot - top
	# Nur sichtbare Kacheln: lange Holds reichen weit ueber den Bildrand, die Kachel-Phase
	# bleibt am Anker (oben bzw. unten), es fehlt kein Stueck am Kopf.
	var vis_top := maxf(top, 0.0)
	var vis_bot := minf(bot, _vs().y)
	if vis_bot <= vis_top:
		return
	var k0 := floorf(((vis_top - top) if from_top else (bot - vis_bot)) / tile)
	var done := k0 * tile
	var guard := 0
	while done < blen - 0.01 and guard < 4096:
		guard += 1
		var seg := minf(tile, blen - done)
		var y := (top + done) if from_top else (bot - done - seg)
		if (from_top and y >= vis_bot) or (not from_top and y + seg <= vis_top):
			break
		var src_rows := minf(rows, seg / tile * src_h)
		var sy := 0.0 if from_top else (src_h - src_rows)
		if sy + src_rows > rows:   # unterer Teil fehlt (abgeschnitten): oberen nehmen
			sy = maxf(0.0, rows - src_rows)
		_nd_tex(t, Rect2(x, y, w, seg), mod, Rect2(0.0, sy, tw, src_rows))
		done += seg


## LightingN beim Treffer (80 ms ein, 120 ms aus), LightingL solange ein Hold gehalten wird.
func _draw_osu_lighting(xs: Array, ws: Array, ly: float, now: float) -> void:
	var sk := skin
	var held_cols: Dictionary = {}
	for it in _items:
		if bool(it[5]) and int(it[4]) == STATE_HELD:
			held_cols[int(it[0])] = true
	for c in columns:
		var scale_n := 1.0
		if sk.version >= 2.5:
			var lw := float(sk.lighting_n_width[c]) if c < sk.lighting_n_width.size() else 0.0
			scale_n = (lw if lw > 0.0 else sk.col_units(c)) / ManiaSkin.DEFAULT_COLUMN_WIDTH
		var key := "lighting_l" if held_cols.has(c) else "lighting_n"
		var t := sk.tex(key)
		if t == null:
			continue
		var a := 0.0
		if held_cols.has(c):
			a = 1.0
		elif c < _expl_t0.size():
			var dt := now - float(_expl_t0[c])
			if dt >= 0.0 and dt < 200.0:
				a = dt / 80.0 if dt < 80.0 else 1.0 - (dt - 80.0) / 120.0
		if a <= 0.0:
			continue
		var cx := float(xs[c]) + float(ws[c]) * 0.5
		var sz := _tex_px(key, t) * scale_n
		draw_texture_rect(t, Rect2(cx - sz.x * 0.5, ly - sz.y * 0.5, sz.x, sz.y), false,
				Color(1, 1, 1, clampf(a, 0.0, 1.0)))


## Judgement-Bild mittig bei ScorePosition (lazer LegacyManiaJudgementPiece):
## 20 ms ein, 160 ms stehen, 40 ms aus; Treffer 0,8->1 (40 ms), 0,85->0,7 (40 ms),
## 100 ms stehen, ->0,4 (40 ms); Miss 1,2->1 (100 ms) mit kleiner Drehung.
func _draw_osu_judgement(fr: Rect2, _view: Vector2, now: float) -> void:
	if _judge_q < 0 or _judge_q >= ManiaSkin.HIT_NAMES.size():
		return
	var key: String = ManiaSkin.HIT_NAMES[_judge_q]
	var t := skin.tex(key)
	if t == null:
		return
	var dt := now - _judge_t0
	if dt < 0.0 or dt > 220.0:
		return
	var a := minf(1.0, dt / 20.0) if dt < 180.0 else 1.0 - (dt - 180.0) / 40.0
	var sc := 1.0
	var rot := 0.0
	if _judge_q == Q_MISS:
		var km := _ease_out(minf(1.0, dt / 100.0))
		sc = lerpf(1.2, 1.0, km)
		rot = deg_to_rad(_judge_rot) * km
	elif dt < 40.0:
		sc = lerpf(0.8, 1.0, dt / 40.0)
	elif dt < 80.0:
		sc = lerpf(0.85, 0.7, (dt - 40.0) / 40.0)
	elif dt < 180.0:
		sc = 0.7
	else:
		var k := minf(1.0, (dt - 180.0) / 40.0)
		sc = lerpf(0.7, 0.4, k * k)
	var sz := _tex_px(key, t) * sc
	var c := Vector2(fr.get_center().x, judge_y())
	draw_set_transform(c, rot, Vector2(1.0, -1.0 if _up() else 1.0))
	draw_texture_rect(t, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


## Kombo aus den Ziffern [Fonts] ComboPrefix mittig bei ComboPosition; ab 1 sichtbar,
## bei Zuwachs Y-Streckung 1,4 -> 1 in 300 ms.
func _draw_osu_combo(fr: Rect2, vs: Vector2, now: float) -> void:
	if _combo <= 0:
		return
	var digits := str(_combo)
	var texs: Array = []
	var total := 0.0
	var over := skin.combo_overlap * _px()
	for ch in digits:
		var r := skin.tex_named(skin.combo_prefix + "-" + ch)
		if r[0] == null:
			texs.clear()
			break
		var sz := Vector2((r[0] as Texture2D).get_size()) * _px() * (0.5 if bool(r[1]) else 1.0)
		texs.append([r[0], sz])
		total += sz.x
	var cy := combo_y()
	var k := clampf((now - _combo_t0) / 300.0, 0.0, 1.0)
	var sy := lerpf(1.4, 1.0, _ease_out(k))
	var cx := fr.get_center().x
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0, -sy if _up() else sy))
	if texs.is_empty():
		if _font != null:
			var fs := int(vs.y * 0.05)
			var tw := _font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, Vector2(-tw * 0.5, fs * 0.35), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	total -= over * float(texs.size() - 1)
	var x := -total * 0.5
	for e in texs:
		var sz: Vector2 = e[1]
		draw_texture_rect(e[0], Rect2(x, -sz.y * 0.5, sz.x, sz.y), false)
		x += sz.x - over
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
