class_name DirigentView
extends Control

## Dirigent: Darstellung in einem _draw. Alle festen Masse skalieren mit der
## Fensterhoehe (_u), Text sitzt auf ganzen Pixeln. Tiefe kommt aus zwei kleinen
## Texturen (Scheibe mit Verlauf, weicher Schatten), kein Shader je Objekt.
## - Buehne: runde Graphit-Scheibe mit Schatten, Lichtkante und feinem Achsenkreuz;
##   am Rand die Takt-Uhr (ein Strich je Schlag der Figur, Bernstein-Bogen = Stelle
##   im Takt, Schlag 1 steht oben).
## - Taktfigur: der aktuelle Zielpunkt gross (Scheibe, Zahl, Anflugring laeuft
##   gleichmaessig auf den Rand zu = Zeit bis zum Schlag; auf dem Schlag wird er
##   Bernstein), der naechste klein nummeriert, die uebrigen als kleine Marken; der
##   Figurenweg ist eine Linie mit dunklem Unterzug.
## - Leuchtspur: der schon gelaufene Ideal-Weg zum Zielpunkt (Spitze = Soll-Hand).
## - Hand: Taktstock mit kurzer Spur; der naechste Einsatz laeuft als Form in
##   Tastenfarbe auf einen festen Ring an der Spitze zu.
## - Rueckmeldung: Schlag = Ring loest sich in 150 ms, die Scheibe leuchtet kurz nach
##   (Mitte warm); verfehlt = kleines Kreuz. Einsatz = die Marke springt an der Linie
##   kurz auf, Ring in Stufenfarbe an Linie und Hand, dazu ein Strich unter der Leiste
##   an der Stelle des Drucks (rechts der Linie = zu frueh); verpasst = rotes Kreuz.
## - Taktwechsel: die neue Figur steht einen Takt vorher als Schablone neben der
##   aktuellen, mit Beschriftung.
## - Einsatz-Leiste unter der Buehne (Taiko-artig): Platte mit Schatten, Tastenfeld
##   links, Trefferzone, Marken laufen auf die Trefferlinie zu, Farbe + Form = Taste
##   (A = Kreis, B = Raute), Schlag-Raster als feine Linien, Takt-Eins betont.
## Alles in Figur-Einheiten (DirigentChart); to_px / to_unit rechnen um.

const KEY_A_COL := Color(0.949, 0.635, 0.227)     # Bernstein
const KEY_B_COL := Color(0.557, 0.690, 0.855)     # Stahlblau
const INK := Color(0.925, 0.902, 0.855)           # Creme
const DIM := Color(0.616, 0.592, 0.553)
const PLATE := Color(0.071, 0.067, 0.063)
const HIT_COL := Color(0.62, 0.84, 0.60)
const MISS_COL := Color(0.871, 0.443, 0.384)
const GOLD := Color(1.0, 0.87, 0.64)              # warmes Buehnenlicht
const GREY := Color(0.62, 0.62, 0.64)
const ROWS := 4
const BAR_LEAD_MS := 1500.0
const APPROACH_MS := 650.0
## Nach einer Pause steht die Figur mit dem Zielpunkt so lange vor dem ersten Schlag
## wieder (vorher erst auf dem Schlag selbst: kein Vorlauf).
const REST_LEAD_MS := 1500.0
const REST_AFTER_MS := 700.0
## Annaeherungsring am Taktstock: so lange vor dem Einsatz sichtbar.
const CUE_RING_MS := 1000.0

var chart: DirigentChart
var core: DirigentCore
var t_ms := 0.0
## Hand in Pixeln (Bildschirm).
var cursor_px := Vector2.ZERO
var kiai := 0.0
var beat_env := 0.0
var energy := 0.0
var show_guides := true
var key_names: Array[String] = ["A", "B"]
var key_held: Array[bool] = [false, false]

var _font: Font
var _head_font: Font
## Hand-Spur: letzte Punkte (px).
var _trail: Array[Vector2] = []
var _trail_t: Array[float] = []
## Rueckmeldungen am Punkt: [Zeit, Position (Einheiten), hit, Wert]
var _beat_fx: Array = []
## Rueckmeldungen an der Leiste: [Zeit, quality, mask, dt]
var _cue_fx: Array = []
var _wrong_t := -1e9
var _cue_first := 0
var _smooth_scale := 1.0
var _meter_label := ""
## Letzter Einsatz je Taste (Zeit), laesst die Orchester-Seite aufleuchten.
var _last_cue := [-99999.0, -99999.0]
var _tex_disc: Texture2D
var _tex_shadow: Texture2D
var _lane_box: StyleBoxFlat
var _lane_box_u := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	_head_font = UiTheme.heading_font(2)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build_textures()


func setup(p_chart: DirigentChart, p_core: DirigentCore) -> void:
	chart = p_chart
	core = p_core
	_cue_first = 0
	_beat_fx.clear()
	_cue_fx.clear()
	_last_cue = [-99999.0, -99999.0]


# ---------------------------------------------------------------------------
# Geometrie
# ---------------------------------------------------------------------------

func unit_px() -> float:
	return size.y * 0.288


func center_px() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.362)


func to_px(u: Vector2) -> Vector2:
	return center_px() + u * unit_px()


func to_unit(px: Vector2) -> Vector2:
	return (px - center_px()) / unit_px()


## Einsatz-Leiste: Linie links, Marken kommen von rechts.
func bar_rect() -> Rect2:
	var w := minf(size.x * 0.64, size.y * 1.5)
	var h := size.y * 0.082
	return Rect2(Vector2((size.x - w) * 0.5, size.y * 0.795), Vector2(w, h))


func _bar_line_x() -> float:
	var r := bar_rect()
	return r.position.x + r.size.x * 0.16


func _cue_x(t_cue: float) -> float:
	var r := bar_rect()
	var line_x := _bar_line_x()
	return line_x + (t_cue - t_ms) / BAR_LEAD_MS * (r.end.x - line_x)


# ---------------------------------------------------------------------------
# Ereignisse
# ---------------------------------------------------------------------------

func on_beat_judged(index: int, result: Dictionary) -> void:
	if chart == null or index < 0 or index >= chart.beats.size():
		return
	_beat_fx.append([t_ms, chart.beats[index].pos, bool(result.hit), float(result.value)])


func on_cue_judged(index: int, result: Dictionary) -> void:
	_cue_fx.append([t_ms, int(result.quality), int(result.mask), float(result.get("dt", 0.0))])
	if int(result.quality) != 5:
		for k in 2:
			if DirigentChart.mask_has(int(result.mask), k):
				_last_cue[k] = t_ms


## Falsche Taste: kurzer Text "WRONG KEY" ueber der Einsatz-Leiste.
func on_wrong_key() -> void:
	_wrong_t = t_ms


func push_cursor(px: Vector2) -> void:
	cursor_px = px
	var now := Time.get_ticks_msec() / 1000.0
	_trail.append(px)
	_trail_t.append(now)
	while _trail.size() > 1 and now - _trail_t[0] > 0.22:
		_trail.remove_at(0)
		_trail_t.remove_at(0)


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()


## Pixel je 720p-Einheit: alle festen Masse wachsen mit der Fensterhoehe.
func _u() -> float:
	return maxf(size.y / 720.0, 0.5)


## Zwei kleine Texturen fuer alle Scheiben: Verlauf (Mitte hell, Rand dunkler, oben
## eine Spur Licht, Kante geglaettet) und weicher Schatten. Einmal gebaut, mit Mips.
func _build_textures() -> void:
	var n := 160
	var disc := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var shadow := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var half := float(n) * 0.5
	for y in n:
		for x in n:
			var v := Vector2((float(x) + 0.5 - half) / half, (float(y) + 0.5 - half) / half)
			var d := v.length()
			var g := lerpf(1.0, 0.66, smoothstep(0.0, 1.0, d)) + 0.10 * clampf(-v.y, 0.0, 1.0) * d
			var a := clampf((1.0 - d) * half / 1.4, 0.0, 1.0)
			disc.set_pixel(x, y, Color(minf(g, 1.0), minf(g, 1.0), minf(g, 1.0), a))
			var s := 1.0 - smoothstep(0.42, 1.0, d)
			shadow.set_pixel(x, y, Color(1, 1, 1, s * s))
	disc.generate_mipmaps()
	shadow.generate_mipmaps()
	_tex_disc = ImageTexture.create_from_image(disc)
	_tex_shadow = ImageTexture.create_from_image(shadow)


## Scheibe mit Verlauf (col = Farbe der Mitte).
func _disc(p: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_tex_disc, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


## Weicher Schatten: r = aeusserer Radius, a = Deckkraft in der Mitte.
func _soft(p: Vector2, r: float, a: float) -> void:
	draw_texture_rect(_tex_shadow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0, 0, 0, a))


## Bogen, der zu beiden Enden weich auslaeuft (Lichtkante).
func _arc_fade(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 33:
		var f := float(i) / 32.0
		var ang := lerpf(a0, a1, f)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		cols.append(Color(col, col.a * sin(PI * f)))
	draw_polyline_colors(pts, cols, w, true)


## Text mittig um c (waagrecht und senkrecht), auf ganze Pixel gesetzt (scharf).
func _text_c(f: Font, c: Vector2, txt: String, px: int, col: Color, outline: bool = false) -> void:
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := Vector2(c.x - w * 0.5, c.y + (f.get_ascent(px) - f.get_descent(px)) * 0.5).round()
	if outline:
		draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, int(px * 0.24)),
			Color(0, 0, 0, 0.6 * col.a))
	draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _draw() -> void:
	if chart == null or chart.beats.is_empty():
		return
	var cur := chart.beat_at(t_ms)
	var nxt := mini(cur + 1, chart.beats.size() - 1)
	var gap := rest_at(chart, cur, t_ms)
	var before_first := cur < 0
	var target := nxt if not before_first else 0
	if cur >= 0 and cur + 1 >= chart.beats.size():
		target = cur
	# Bei einer Pause ruht die Figur: Hinweis statt Figur.
	_meter_label = str(chart.bars[int(chart.beats[target].bar)].label)
	var bar_i: int = int(chart.beats[target].bar)
	if gap:
		_draw_stage(bar_i, cur, nxt, true)
		_draw_rest()
		_draw_bar()
		return
	_draw_stage(bar_i, cur, nxt, false)
	_draw_path(bar_i)
	_draw_figure(bar_i, target)
	_draw_announce(bar_i, target)
	_draw_trace(cur, nxt)
	_draw_beat_fx()
	_draw_cue_rings()
	_draw_hand()
	_draw_bar()


func stage_radius() -> float:
	return unit_px() * 1.02


## Buehne: Graphit-Scheibe mit Schatten, Kontur, Lichtkante oben, Achsenkreuz und
## innerem Ring. Am Rand die Takt-Uhr: ein Strich je Schlag der Figur (Schlag 1 oben),
## der Bernstein-Bogen zeigt die Stelle im Takt.
func _draw_stage(bar_i: int, cur: int, nxt: int, resting: bool) -> void:
	var u := _u()
	var c := center_px()
	var rr := stage_radius()
	var hair := maxf(1.0, roundf(u))
	_soft(c + Vector2(0.0, 14.0 * u), rr * 1.16, 0.62)
	_disc(c, rr, Color(0.128, 0.122, 0.113, 0.95))
	# Achsenkreuz und innerer Ring: Mass fuer die Hand, sehr leise.
	var ax := rr * 0.90
	draw_rect(Rect2(roundf(c.x - ax), roundf(c.y), ax * 2.0, hair), Color(INK, 0.045), true)
	draw_rect(Rect2(roundf(c.x), roundf(c.y - ax), hair, ax * 2.0), Color(INK, 0.045), true)
	draw_arc(c, DirigentChart.FIG * unit_px(), 0.0, TAU, 96, Color(INK, 0.055), maxf(1.0, 1.0 * u), true)
	draw_arc(c, rr, 0.0, TAU, 128, Color(0, 0, 0, 0.55), 3.0 * u, true)
	draw_arc(c, rr, 0.0, TAU, 128, Color(INK, 0.15), maxf(1.0, 1.4 * u), true)
	_arc_fade(c, rr, -PI * 0.86, -PI * 0.14, Color(INK, 0.42), maxf(1.0, 1.4 * u))
	# Takt-Uhr.
	var b: Dictionary = chart.bars[bar_i]
	var n := maxi(int(b.count), 1)
	var frac := 0.0
	if not resting and cur >= 0 and cur != nxt:
		var t0 := float(chart.beats[cur].t)
		var t1 := float(chart.beats[nxt].t)
		var u_now := clampf((t_ms - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
		frac = fposmod((float(cur - int(b.i0)) + u_now) / float(n), 1.0)
		if int(chart.beats[cur].bar) != bar_i:
			frac = 0.0
	var r_in := rr + 7.0 * u
	var r_out := rr + 14.0 * u
	var r_mid := (r_in + r_out) * 0.5
	draw_arc(c, r_mid, 0.0, TAU, 128, Color(INK, 0.07), maxf(1.0, 1.0 * u), true)
	if frac > 0.002:
		draw_arc(c, r_mid, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(8, int(128.0 * frac)), Color(KEY_A_COL, 0.9),
			2.0 * u, true)
	for k in n:
		var ang := -PI * 0.5 + TAU * float(k) / float(n)
		var dir := Vector2(cos(ang), sin(ang))
		var passed := float(k) / float(n) <= frac + 0.001 and not resting
		var col := Color(KEY_A_COL, 1.0) if passed else Color(INK, 0.38)
		var grow := 3.0 * u if k == 0 else 0.0
		draw_line(c + dir * (r_in - grow), c + dir * (r_out + grow), Color(0, 0, 0, 0.5), 4.0 * u, true)
		draw_line(c + dir * (r_in - grow), c + dir * (r_out + grow), col, 2.0 * u, true)
	if frac > 0.002:
		var ha := -PI * 0.5 + TAU * frac
		draw_circle(c + Vector2(cos(ha), sin(ha)) * r_mid, 3.2 * u, KEY_A_COL, true, -1.0, true)


## Ganzer Figurenweg: helle Linie mit dunklem Unterzug (liest sich auf jedem Grund).
func _draw_path(bar_i: int) -> void:
	if not show_guides:
		return
	var b: Dictionary = chart.bars[bar_i]
	var first := int(b.i0)
	var last := mini(first + int(b.count), chart.beats.size() - 1)
	var u := _u()
	for pass_i in 2:
		for id in range(first, last):
			var t0 := float(chart.beats[id].t)
			var t1 := float(chart.beats[id + 1].t)
			if chart.is_gap(id) or t1 - t0 > 2500.0:
				continue
			var a: Vector2 = chart.beats[id].pos
			var e: Vector2 = chart.beats[id + 1].pos
			var pts := PackedVector2Array()
			for i in 25:
				pts.append(to_px(DirigentChart.path_point(a, e, float(i) / 24.0)))
			if pass_i == 0:
				draw_polyline(pts, Color(0, 0, 0, 0.30), 4.0 * u, true)
			else:
				draw_polyline(pts, Color(INK, 0.24), maxf(1.0, 1.5 * u), true)


## Pause: die Figur ruht ("Pause" statt Figur). cur = chart.beat_at(t).
static func rest_at(ch: DirigentChart, cur: int, t: float, rest_lead: float = REST_LEAD_MS) -> bool:
	if cur < 0 or not ch.is_gap(cur) or t <= float(ch.beats[cur].t) + REST_AFTER_MS:
		return false
	if cur + 1 >= ch.beats.size():
		return true
	return t < float(ch.beats[cur + 1].t) - rest_lead


## Messung/Tests: so lange vor seiner Zeit steht Schlag i als Zielpunkt da (ms).
static func beat_lead_ms(ch: DirigentChart, i: int, rest_lead: float = REST_LEAD_MS) -> float:
	if i <= 0:
		return INF
	var iv := float(ch.beats[i].t) - float(ch.beats[i - 1].t)
	if not ch.is_gap(i - 1):
		return iv
	return clampf(rest_lead, 0.0, iv - REST_AFTER_MS)


func _draw_rest() -> void:
	_text_c(_head_font, center_px(), tr("DIRIGENT_REST"), int(round(22.0 * _u())), Color(INK, 0.5))


func _fig_beats(bar_i: int) -> Array:
	var b: Dictionary = chart.bars[bar_i]
	var out: Array = []
	for k in int(b.count):
		out.append(int(b.i0) + k)
	return out


## Hierarchie: Zielpunkt gross (Scheibe, Zahl, Anflugring), naechster Punkt
## klein nummeriert, alle anderen nur als kleine Marke.
func _draw_figure(bar_i: int, target: int) -> void:
	var ids := _fig_beats(bar_i)
	var u := _u()
	var r := DirigentCore.HIT_R * unit_px()
	var ri := DirigentCore.INNER_R * unit_px()
	var font_px := int(round(36.0 * u))
	var small_px := int(round(16.0 * u))
	var nxt := target + 1
	var has_next := nxt < chart.beats.size() and not chart.is_gap(target)
	# Uebrige Punkte: kommende als kleine Scheibe mit Kontur, vergangene als Punkt.
	for id in ids:
		if id == target or (has_next and id == nxt):
			continue
		var q := to_px(chart.beats[id].pos)
		if float(chart.beats[id].t) < t_ms:
			draw_circle(q, 3.0 * u, Color(INK, 0.26), true, -1.0, true)
		else:
			_disc(q, 7.0 * u, Color(0.25, 0.24, 0.22, 1.0))
			draw_arc(q, 7.0 * u, 0.0, TAU, 32, Color(INK, 0.55), maxf(1.0, 1.5 * u), true)
	# Naechster Punkt: klein, nummeriert.
	if has_next:
		var nb: Dictionary = chart.beats[nxt]
		var np := to_px(nb.pos)
		var nr := r * 0.44
		_soft(np + Vector2(0.0, 3.0 * u), nr * 1.5, 0.55)
		_disc(np, nr, Color(0.215, 0.205, 0.19, 1.0))
		draw_arc(np, nr, 0.0, TAU, 48, Color(INK, 0.60), maxf(1.0, 1.6 * u), true)
		_text_c(_head_font, np, str(int(nb.pt) + 1), small_px, Color(INK, 0.82))
	# Zielpunkt.
	var b: Dictionary = chart.beats[target]
	var p := to_px(b.pos)
	var dt := float(b.t) - t_ms
	var lead := APPROACH_MS
	if target > 0:
		lead = clampf(float(b.t) - float(chart.beats[target - 1].t), 250.0, 1100.0)
	var k := clampf(1.0 - dt / lead, 0.0, 1.0)
	# near: 1 genau auf dem Schlag, 0 ab 140 ms davor/danach.
	var near := clampf(1.0 - absf(dt) / 140.0, 0.0, 1.0)
	near *= near
	_soft(p + Vector2(0.0, 5.0 * u), r * 1.42, 0.60)
	_disc(p, r, Color(0.235, 0.224, 0.208, 1.0).lerp(Color(0.52, 0.34, 0.11, 1.0), near))
	draw_arc(p, ri, 0.0, TAU, 48, Color(INK, 0.13 + 0.10 * near), maxf(1.0, 1.0 * u), true)
	_arc_fade(p, r - 3.5 * u, -PI * 0.85, -PI * 0.15, Color(INK, 0.30), maxf(1.0, 1.2 * u))
	# Anflugring: laeuft gleichmaessig auf den Rand zu, deckungsgleich = Schlag.
	if dt > 0.0:
		var a_in := clampf(k * 5.0, 0.0, 1.0)
		var ra := r * (1.0 + (1.0 - k) * 1.05)
		draw_arc(p, ra, 0.0, TAU, 96, Color(0, 0, 0, 0.35 * a_in), (3.4 + 1.0 * k) * u, true)
		draw_arc(p, ra, 0.0, TAU, 96, Color(GOLD, a_in * (0.45 + 0.50 * k)), (1.6 + 1.0 * k) * u, true)
	draw_arc(p, r, 0.0, TAU, 96, Color(0, 0, 0, 0.5), (4.4 + 1.0 * near) * u, true)
	draw_arc(p, r, 0.0, TAU, 96, Color(INK, 0.95).lerp(KEY_A_COL, near), (2.4 + 1.0 * near) * u, true)
	_text_c(_head_font, p + Vector2(0.0, 1.5 * u), str(int(b.pt) + 1), font_px, Color(0, 0, 0, 0.45))
	_text_c(_head_font, p, str(int(b.pt) + 1), font_px, Color(INK, 1.0))


func _dotted(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1.0:
		return
	var u := _u()
	var step := 7.0 * u
	var n := int(ln / step)
	var dir := d / ln
	for i in range(0, n, 2):
		draw_line(a + dir * (float(i) * step), a + dir * (minf(float(i + 1) * step, ln)), col, maxf(1.0, 1.4 * u), true)


## Taktwechsel: einen Takt vorher steht die neue Figur als Schablone rechts der Buehne.
func _draw_announce(bar_i: int, _target: int) -> void:
	if bar_i + 1 >= chart.bars.size():
		return
	var cur_bar: Dictionary = chart.bars[bar_i]
	var nb: Dictionary = chart.bars[bar_i + 1]
	if nb.label == cur_bar.label and nb.kind == cur_bar.kind:
		return
	if float(nb.t) - float(cur_bar.t) > BAR_LEAD_MS * 4.0:
		return
	var u := _u()
	var pts := DirigentChart.figure_points(str(nb.kind), int(nb.n))
	var sc := 0.30
	var origin := Vector2(size.x * 0.5 + unit_px() * 1.22, size.y * 0.20)
	_soft(origin + Vector2(0.0, 4.0 * u), unit_px() * 0.36, 0.5)
	_disc(origin, unit_px() * 0.29, Color(0.128, 0.122, 0.113, 0.95))
	draw_arc(origin, unit_px() * 0.29, 0.0, TAU, 64, Color(INK, 0.18), maxf(1.0, 1.4 * u), true)
	for k in pts.size():
		var p := origin + pts[k] * sc * unit_px()
		if k > 0:
			_dotted(origin + pts[k - 1] * sc * unit_px(), p, Color(INK, 0.34))
	for k in pts.size():
		var p := origin + pts[k] * sc * unit_px()
		_disc(p, 9.0 * u, Color(0.25, 0.24, 0.22, 1.0))
		draw_arc(p, 9.0 * u, 0.0, TAU, 24, Color(INK, 0.65), maxf(1.0, 1.4 * u), true)
		_text_c(_head_font, p, str(k + 1), int(round(11.0 * u)), Color(INK, 0.95))
	var base := origin + Vector2(0.0, unit_px() * sc + 34.0 * u)
	_text_c(_head_font, base, tr("Taktwechsel: %s") % nb.label, int(round(15.0 * u)), Color(INK, 0.95), true)
	_text_c(_font, base + Vector2(0.0, 20.0 * u), tr("ab dem nächsten Takt"), int(round(13.0 * u)), Color(DIM, 0.95), true)


## Leuchtspur: der schon gelaufene Ideal-Weg zum naechsten Punkt, Spitze = Soll-Hand.
func _draw_trace(cur: int, nxt: int) -> void:
	if not show_guides or chart.beats.size() < 2:
		return
	if cur < 0 or cur == nxt or chart.is_gap(cur):
		return
	var a: Vector2 = chart.beats[cur].pos
	var b: Vector2 = chart.beats[nxt].pos
	var t0 := float(chart.beats[cur].t)
	var t1 := float(chart.beats[nxt].t)
	var u_now := clampf((t_ms - t0) / maxf(t1 - t0, 1.0), 0.0, 1.0)
	var u := _u()
	var u_from := maxf(u_now - 0.45, 0.0)
	if u_now - u_from > 0.01:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in 19:
			var f := float(i) / 18.0
			pts.append(to_px(DirigentChart.path_point(a, b, lerpf(u_from, u_now, f))))
			cols.append(Color(GOLD, 0.85 * f * f))
		draw_polyline_colors(pts, cols, 2.6 * u, true)
	var head := to_px(DirigentChart.path_point(a, b, u_now))
	draw_circle(head, 5.4 * u, Color(0, 0, 0, 0.5), true, -1.0, true)
	draw_circle(head, 3.6 * u, Color(GOLD, 1.0), true, -1.0, true)


## Schlag-Rueckmeldung am Punkt: ein Ring loest sich in 150 ms (Mitte = warm, sonst
## Creme), die Scheibe leuchtet kurz nach; verfehlt = kleines Kreuz mit einem Wort.
func _draw_beat_fx() -> void:
	var keep: Array = []
	var u := _u()
	var r := DirigentCore.HIT_R * unit_px()
	for fx in _beat_fx:
		var age := t_ms - float(fx[0])
		var hit: bool = fx[2]
		var life := 300.0 if hit else 650.0
		if age > life or age < -50.0:
			continue
		keep.append(fx)
		var p := to_px(fx[1])
		if hit:
			var best := float(fx[3]) >= 0.999
			var col := GOLD if best else INK
			# Nachleuchten der Scheibe.
			var glow := 1.0 - clampf(age / life, 0.0, 1.0)
			_disc(p, r, Color(col, 0.20 * glow * glow))
			draw_arc(p, r, 0.0, TAU, 96, Color(col, 0.55 * glow * glow), 2.0 * u, true)
			# Ring: 150 ms, ease-out.
			if age < 150.0:
				var k := age / 150.0
				var e := 1.0 - pow(1.0 - k, 3.0)
				var fade := 1.0 - k * k
				draw_arc(p, r * (1.0 + 0.26 * e), 0.0, TAU, 96, Color(col, 0.90 * fade), (3.0 - 1.8 * k) * u, true)
				if best:
					draw_arc(p, DirigentCore.INNER_R * unit_px() * (1.0 + 0.40 * e), 0.0, TAU, 48,
						Color(col, 0.7 * fade), 1.6 * u, true)
		else:
			var k2 := clampf(age / life, 0.0, 1.0)
			var h := r * 0.26
			var al := 0.9 * clampf(age / 40.0, 0.0, 1.0) * (1.0 - smoothstep(0.45, 1.0, k2))
			draw_arc(p, r, 0.0, TAU, 96, Color(MISS_COL, al * 0.8), 2.4 * u, true)
			draw_line(p - Vector2(h, h), p + Vector2(h, h), Color(MISS_COL, al), 2.6 * u, true)
			draw_line(p - Vector2(h, -h), p + Vector2(h, -h), Color(MISS_COL, al), 2.6 * u, true)
			_text_c(_font, p + Vector2(0.0, -r - 14.0 * u), tr("Schlag verfehlt"), int(round(13.0 * u)),
				Color(MISS_COL.lerp(INK, 0.35), al), true)
	_beat_fx = keep


# ---------------------------------------------------------------------------
# Einsatz-Ring am Taktstock
# ---------------------------------------------------------------------------

## Die naechsten (hoechstens zwei) offenen Einsaetze.
func _upcoming_cues() -> Array:
	var out: Array = []
	var i := _cue_first
	while i < chart.cues.size() and out.size() < 2:
		var tc := float(chart.cues[i].t)
		if tc - t_ms > CUE_RING_MS:
			break
		if tc - t_ms > -140.0 and not (core != null and core.is_cue_done(i)):
			out.append(i)
		i += 1
	return out


func _mask_text(mask: int) -> String:
	if mask == 1:
		return key_names[0]
	if mask == 2:
		return key_names[1]
	return key_names[0] + "+" + key_names[1]


func _diamond_pts(p: Vector2, d: float, closed: bool = false) -> PackedVector2Array:
	var pts := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
	if closed:
		pts.append(pts[0])
		pts.append(pts[1])
	return pts


## Form des Einsatzes um p mit Radius r: A = Kreis, B = Raute, beide = Kreis und Raute.
func _ring_shape(p: Vector2, r: float, mask: int, col_a: float, w: float) -> void:
	if mask != 2:
		draw_arc(p, r, 0.0, TAU, 64, Color(0, 0, 0, 0.4 * col_a), w + 2.0 * _u(), true)
		draw_arc(p, r, 0.0, TAU, 64, Color(KEY_A_COL, col_a), w, true)
	if mask != 1:
		var d := r * (1.22 if mask == 2 else 1.4)
		draw_polyline(_diamond_pts(p, d, true), Color(0, 0, 0, 0.4 * col_a), w + 2.0 * _u(), true)
		draw_polyline(_diamond_pts(p, d, true), Color(KEY_B_COL, col_a), w, true)


## Naechster Einsatz an der Hand: eine Form in Tastenfarbe laeuft gleichmaessig auf
## den festen Zielring zu (deckungsgleich = druecken), die Taste steht klein daneben.
func _draw_cue_rings() -> void:
	if chart.cues.is_empty():
		return
	while _cue_first < chart.cues.size() and float(chart.cues[_cue_first].t) < t_ms - 260.0:
		_cue_first += 1
	var up := _upcoming_cues()
	if up.is_empty():
		return
	var p := cursor_px
	var u := _u()
	var c: Dictionary = chart.cues[up[0]]
	var mask := int(c.mask)
	var k := clampf((float(c.t) - t_ms) / CUE_RING_MS, 0.0, 1.0)
	var r_end := 22.0 * u
	var r := r_end + k * 62.0 * u
	var a := clampf((1.0 - k) * 6.0, 0.0, 1.0) * (0.40 + 0.60 * (1.0 - k))
	var near := clampf(1.0 - k * 5.0, 0.0, 1.0)
	var col := KEY_A_COL if mask == 1 else (KEY_B_COL if mask == 2 else INK)
	draw_arc(p, r_end, 0.0, TAU, 48, Color(INK, (0.30 + 0.50 * near) * minf(a * 2.0, 1.0)), maxf(1.0, 1.4 * u), true)
	_ring_shape(p, r, mask, a, (2.0 + 1.0 * near) * u)
	_text_c(_head_font, p + Vector2(r_end + 16.0 * u, -r_end - 6.0 * u), _mask_text(mask), int(round(15.0 * u)),
		Color(col.lerp(INK, 0.3), minf(a * 1.6, 1.0)), true)


## Hand: kurze, sich verjuengende Spur, Taktstock in fester Schraege, klare Spitze.
func _draw_hand() -> void:
	var u := _u()
	var n := _trail.size()
	if n > 1:
		for i in range(1, n):
			var al := float(i) / float(n)
			al = al * al
			draw_line(_trail[i - 1], _trail[i], Color(GOLD, 0.50 * al), (0.8 + 2.6 * al) * u, true)
	var p := cursor_px
	var tail := p + Vector2(0.62, 0.78) * (size.y * 0.046)
	var off := Vector2(0.0, 2.0 * u)
	draw_line(tail + off, p + off, Color(0, 0, 0, 0.45), 5.0 * u, true)
	draw_line(tail, p, Color(INK, 0.95), 2.4 * u, true)
	draw_circle(tail, 4.2 * u, Color(0, 0, 0, 0.5), true, -1.0, true)
	draw_circle(tail, 3.2 * u, Color(KEY_A_COL, 1.0), true, -1.0, true)
	draw_circle(p, 6.6 * u, Color(0, 0, 0, 0.55), true, -1.0, true)
	draw_circle(p, 4.6 * u, Color(1.0, 0.97, 0.9, 1.0), true, -1.0, true)


# ---------------------------------------------------------------------------
# Einsatz-Leiste
# ---------------------------------------------------------------------------

func _lane_style(u: float) -> StyleBoxFlat:
	if _lane_box == null or absf(_lane_box_u - u) > 0.001:
		_lane_box_u = u
		_lane_box = StyleBoxFlat.new()
		_lane_box.bg_color = Color(0.074, 0.070, 0.066, 0.96)
		_lane_box.set_corner_radius_all(maxi(2, int(round(7.0 * u))))
		_lane_box.set_border_width_all(maxi(1, int(round(u))))
		_lane_box.border_color = Color(INK, 0.13)
		_lane_box.shadow_color = Color(0, 0, 0, 0.42)
		_lane_box.shadow_size = int(round(16.0 * u))
		_lane_box.shadow_offset = Vector2(0.0, 5.0 * u)
		_lane_box.anti_aliasing = true
	return _lane_box


func _draw_bar() -> void:
	var r := bar_rect()
	var u := _u()
	var line_x := _bar_line_x()
	var mid_y := r.position.y + r.size.y * 0.5
	var h := r.size.y
	var px_ms := (r.end.x - line_x) / BAR_LEAD_MS
	var hair := maxf(1.0, roundf(u))
	# Platte mit Schatten und Kontur; oben eine feine Lichtkante.
	var strip := Rect2(r.grow_individual(12.0 * u, 0.0, 12.0 * u, 0.0).position.round(),
		r.grow_individual(12.0 * u, 0.0, 12.0 * u, 0.0).size.round())
	draw_style_box(_lane_style(u), strip)
	var inner := strip.grow(-hair)
	draw_rect(Rect2(inner.position.x + 6.0 * u, inner.position.y, inner.size.x - 12.0 * u, hair), Color(INK, 0.10), true)
	# Tastenfeld links: eine Spur dunkler, mit Trennlinie.
	var cap_a := Vector2(r.position.x + 26.0 * u, mid_y)
	var cap_b := Vector2(r.position.x + 68.0 * u, mid_y)
	var caps_end := cap_b.x + 24.0 * u
	draw_rect(Rect2(inner.position.x + 4.0 * u, inner.position.y + hair, caps_end - inner.position.x - 4.0 * u, inner.size.y - hair * 2.0),
		Color(0, 0, 0, 0.22), true)
	draw_rect(Rect2(roundf(caps_end), inner.position.y, hair, inner.size.y), Color(INK, 0.12), true)
	# Trefferzone um die Linie (300er-Breite im Zeitmass).
	if core != null:
		var wpx := maxf(core.w300 * px_ms, 3.0 * u)
		draw_rect(Rect2(line_x - wpx, inner.position.y, wpx * 2.0, inner.size.y), Color(INK, 0.075), true)
		draw_rect(Rect2(roundf(line_x - wpx), inner.position.y, hair, inner.size.y), Color(INK, 0.14), true)
		draw_rect(Rect2(roundf(line_x + wpx), inner.position.y, hair, inner.size.y), Color(INK, 0.14), true)
	# Schlag-Raster: feine Linie je Schlag, Takt-Eins betont (Off-Beat-Einsaetze lesbar).
	var bi := maxi(chart.beat_at(t_ms), 0)
	while bi < chart.beats.size():
		var tb := float(chart.beats[bi].t)
		if tb - t_ms > BAR_LEAD_MS:
			break
		var bx := roundf(_cue_x(tb))
		if tb >= t_ms - 60.0 and bx > caps_end + 2.0 * u and bx < inner.end.x - 2.0 * u:
			var one := int(chart.beats[bi].pt) == 0
			draw_rect(Rect2(bx, inner.position.y, hair, inner.size.y), Color(INK, 0.14 if one else 0.07), true)
			var th := h * (0.20 if one else 0.13)
			draw_rect(Rect2(bx, inner.position.y, hair, th), Color(INK, 0.45), true)
			draw_rect(Rect2(bx, inner.end.y - th, hair, th), Color(INK, 0.45), true)
		bi += 1
	_key_cap(cap_a, key_names[0], KEY_A_COL, key_held[0], 0)
	_key_cap(cap_b, key_names[1], KEY_B_COL, key_held[1], 1)
	if _meter_label != "":
		var mpx := int(round(13.0 * u))
		var mw := _head_font.get_string_size(_meter_label, HORIZONTAL_ALIGNMENT_LEFT, -1, mpx).x
		draw_string(_head_font, Vector2(strip.end.x - mw - 2.0 * u, strip.position.y - 8.0 * u).round(), _meter_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, mpx, Color(DIM, 0.95))
	# Marken (spaete zuerst: die naechste liegt oben).
	var rad := h * 0.27
	if not chart.cues.is_empty():
		while _cue_first < chart.cues.size() and float(chart.cues[_cue_first].t) < t_ms - 260.0:
			_cue_first += 1
		var last := _cue_first
		while last < chart.cues.size() and float(chart.cues[last].t) - t_ms <= BAR_LEAD_MS:
			last += 1
		for i in range(last - 1, _cue_first - 1, -1):
			if core != null and core.is_cue_done(i):
				continue
			var tc := float(chart.cues[i].t)
			var x := _cue_x(tc)
			var al := clampf((BAR_LEAD_MS - (tc - t_ms)) / 140.0, 0.0, 1.0)
			al *= clampf(1.0 - (t_ms - tc) / 140.0, 0.0, 1.0)
			al *= clampf((x - rad - caps_end) / (12.0 * u), 0.0, 1.0)
			if al > 0.01:
				_draw_mark(Vector2(x, mid_y), rad, int(chart.cues[i].mask), false, al)
	# Trefferlinie mit Zielring und zwei kleinen Zeigern (liegt ueber den Marken).
	var lw := maxf(2.0, roundf(2.0 * u))
	var lc := Vector2(line_x, mid_y)
	draw_rect(Rect2(roundf(line_x) - lw * 0.5 - hair, strip.position.y - 5.0 * u, lw + hair * 2.0, strip.size.y + 10.0 * u), Color(0, 0, 0, 0.45), true)
	draw_rect(Rect2(roundf(line_x) - lw * 0.5, strip.position.y - 5.0 * u, lw, strip.size.y + 10.0 * u), Color(INK, 1.0), true)
	draw_arc(lc, rad * 1.28, 0.0, TAU, 64, Color(0, 0, 0, 0.5), maxf(3.5, 4.4 * u), true)
	draw_arc(lc, rad * 1.28, 0.0, TAU, 64, Color(INK, 0.98), maxf(1.5, 2.2 * u), true)
	var top_y := strip.position.y - 7.0 * u
	var bot_y := strip.end.y + 7.0 * u
	var tr_w := 5.0 * u
	draw_colored_polygon(PackedVector2Array([Vector2(line_x - tr_w, top_y - tr_w * 1.3), Vector2(line_x + tr_w, top_y - tr_w * 1.3), Vector2(line_x, top_y)]), KEY_A_COL)
	draw_colored_polygon(PackedVector2Array([Vector2(line_x - tr_w, bot_y + tr_w * 1.3), Vector2(line_x, bot_y), Vector2(line_x + tr_w, bot_y + tr_w * 1.3)]), KEY_A_COL)
	# Rueckmeldung: die Marke springt an der Linie kurz auf (120 ms), Ring in Stufenfarbe
	# an Linie und Hand (150 ms); ein Strich unter der Leiste zeigt, wo gedrueckt wurde
	# (rechts der Linie = zu frueh). Verpasst: rotes Kreuz an der Linie.
	var keep: Array = []
	for fx in _cue_fx:
		var age := t_ms - float(fx[0])
		if age > 520.0 or age < -50.0:
			continue
		keep.append(fx)
		var q := clampi(int(fx[1]), 0, 5)
		var col: Color = MISS_COL if q == 5 else JudgeDisplay.COLORS[q]
		if q != 5 and age < 120.0:
			var kp := age / 120.0
			_draw_mark(lc, rad * (1.0 + 0.34 * (1.0 - pow(1.0 - kp, 2.0))), int(fx[2]), false, (1.0 - kp) * 0.9)
		if age < 150.0:
			var k := age / 150.0
			var e := 1.0 - pow(1.0 - k, 3.0)
			var fade := 1.0 - k * k
			draw_arc(lc, rad * (1.28 + 0.62 * e), 0.0, TAU, 64, Color(col, 0.9 * fade), (3.0 - 1.8 * k) * u, true)
			if q != 5:
				draw_arc(cursor_px, (22.0 + 20.0 * e) * u, 0.0, TAU, 48, Color(col, 0.8 * fade), (2.6 - 1.4 * k) * u, true)
		if age < 300.0:
			draw_arc(lc, rad * 1.28, 0.0, TAU, 64, Color(col, 0.85 * (1.0 - age / 300.0)), maxf(1.5, 2.2 * u), true)
		if q == 5:
			var ma := 1.0 - smoothstep(260.0, 520.0, age)
			var hx := rad * 0.5
			draw_line(lc - Vector2(hx, hx), lc + Vector2(hx, hx), Color(MISS_COL, ma), 2.6 * u, true)
			draw_line(lc - Vector2(hx, -hx), lc + Vector2(hx, -hx), Color(MISS_COL, ma), 2.6 * u, true)
		elif core != null:
			var dt := clampf(float(fx[3]), -float(core.w50), float(core.w50))
			var tx := roundf(line_x - dt * px_ms)
			var ta := 1.0 - smoothstep(260.0, 520.0, age)
			draw_rect(Rect2(tx - hair, strip.end.y + 3.0 * u, hair * 2.0, 8.0 * u), Color(col, 0.95 * ta), true)
	_cue_fx = keep
	var wa := t_ms - _wrong_t
	if wa >= 0.0 and wa < 600.0:
		_text_c(_head_font, Vector2(r.position.x + r.size.x * 0.5, strip.position.y - 16.0 * u), "WRONG KEY",
			int(round(15.0 * u)), Color(MISS_COL, 1.0 - smoothstep(300.0, 600.0, wa)), true)


## Legende: dieselbe Form und Farbe wie die Marke (A = Kreis, B = Raute), Taste darin.
## Gehalten = gefuellt.
func _key_cap(p: Vector2, txt: String, col: Color, held: bool, key: int) -> void:
	var u := _u()
	var w := maxf(1.2, 1.8 * u)
	var dark := Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 1.0)
	if key == 0:
		var rc := 15.0 * u
		_disc(p, rc, col if held else dark)
		draw_arc(p, rc, 0.0, TAU, 40, Color(col, 1.0), w, true)
	else:
		var d := 18.0 * u
		draw_colored_polygon(_diamond_pts(p, d), col if held else dark)
		draw_polyline(_diamond_pts(p, d, true), Color(col, 1.0), w, true)
	_text_c(_head_font, p, txt, int(round(14.0 * u)), PLATE if held else Color(col.lerp(INK, 0.55), 1.0))


## Marke: Kreis = A (Bernstein), Raute = B (Stahlblau), beide = A oben und B unten.
## Dunkler Rand trennt dicht aufeinander folgende Marken, helle Kontur + Innenlicht.
func _draw_mark(p: Vector2, rad: float, mask: int, done: bool, a: float) -> void:
	var al := a * (0.28 if done else 1.0)
	var rim := maxf(1.5, rad * 0.16)
	if mask == 1:
		_mark_circle(p, rad, rim, al)
	elif mask == 2:
		_diamond(p, rad * 1.16, Color(KEY_B_COL, al), rim)
	else:
		var o := rad * 0.98
		_mark_circle(p + Vector2(0, -o), rad * 0.80, rim, al)
		_diamond(p + Vector2(0, o), rad * 0.92, Color(KEY_B_COL, al), rim)


func _mark_circle(p: Vector2, rad: float, rim: float, al: float) -> void:
	draw_circle(p, rad + rim, Color(PLATE, al), true, -1.0, true)
	_disc(p, rad, Color(KEY_A_COL.lightened(0.16), al))
	draw_arc(p, rad - 0.5, 0.0, TAU, 40, Color(KEY_A_COL.lightened(0.42), al), maxf(1.0, rad * 0.11), true)


func _diamond(p: Vector2, r: float, col: Color, rim: float = 0.0) -> void:
	if rim > 0.0:
		draw_colored_polygon(_diamond_pts(p, r + rim * 1.4), Color(PLATE, col.a))
	draw_colored_polygon(_diamond_pts(p, r), Color(col.darkened(0.16), col.a))
	draw_colored_polygon(_diamond_pts(p + Vector2(0.0, -r * 0.10), r * 0.60), Color(col.lightened(0.10), col.a))
	draw_polyline(_diamond_pts(p, r - 0.5, true), Color(col.lightened(0.42), col.a), maxf(1.0, r * 0.10), true)
