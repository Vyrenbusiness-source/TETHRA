class_name DirigentView
extends Control

## Dirigent: Darstellung in einem _draw (ruhig, flach, gut lesbar).
## - Taktfigur: der aktuelle Zielpunkt gross (Trefferkreis, Zahl, Anflugring = Zeit bis
##   zum Schlag), der naechste klein nummeriert, die uebrigen Punkte nur als Marke.
##   Kein Grund hinter der Figur, keine Verbindungslinien.
## - Leuchtspur: nur der Ideal-Weg vom letzten zum Zielpunkt (Spitze = Soll-Hand).
## - Hand: der Cursor mit kurzer Spur.
## - Taktwechsel: die neue Figur steht einen Takt vorher als Schablone neben der
##   aktuellen, mit Beschriftung.
## - Einsatz-Leiste unter der Figur (Taiko-artig): Marken laufen auf die Trefferlinie zu,
##   Farbe + Form = Taste (Legende links in denselben Formen), Schlag-Ticks auf der
##   Leiste zeigen das Raster (Off-Beat-Einsaetze sind so lesbar), Taktart klein dabei.
## Alles in Figur-Einheiten (DirigentChart); to_px / to_unit rechnen um.

const KEY_A_COL := Color(0.949, 0.635, 0.227)     # Bernstein
const KEY_B_COL := Color(0.557, 0.690, 0.855)     # Stahlblau
const INK := Color(0.925, 0.902, 0.855)           # Creme
const DIM := Color(0.616, 0.592, 0.553)
const PLATE := Color(0.071, 0.067, 0.063)
const HIT_COL := Color(0.62, 0.84, 0.60)
const MISS_COL := Color(0.871, 0.443, 0.384)
const BAR_LEAD_MS := 1700.0
const APPROACH_MS := 650.0

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
## Rueckmeldungen an der Leiste: [Zeit, quality, mask]
var _cue_fx: Array = []
var _cue_first := 0
var _smooth_scale := 1.0
var _meter_label := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font() if get_theme_default_font() != null else ThemeDB.fallback_font
	_head_font = UiTheme.heading_font(2)


func setup(p_chart: DirigentChart, p_core: DirigentCore) -> void:
	chart = p_chart
	core = p_core
	_cue_first = 0
	_beat_fx.clear()
	_cue_fx.clear()


# ---------------------------------------------------------------------------
# Geometrie
# ---------------------------------------------------------------------------

func unit_px() -> float:
	return size.y * 0.34


func center_px() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.43)


func to_px(u: Vector2) -> Vector2:
	return center_px() + u * unit_px()


func to_unit(px: Vector2) -> Vector2:
	return (px - center_px()) / unit_px()


## Einsatz-Leiste: Linie links, Marken kommen von rechts.
func bar_rect() -> Rect2:
	var w := minf(size.x * 0.62, 980.0)
	var h := size.y * 0.085
	return Rect2(Vector2((size.x - w) * 0.5, size.y * 0.855), Vector2(w, h))


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
	_cue_fx.append([t_ms, int(result.quality), int(result.mask)])


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


func _draw() -> void:
	if chart == null or chart.beats.is_empty():
		return
	var uh := unit_px()
	var c := center_px()
	var cur := chart.beat_at(t_ms)
	var nxt := mini(cur + 1, chart.beats.size() - 1)
	var gap := chart.is_gap(cur) and cur >= 0 and t_ms > float(chart.beats[cur].t) + 700.0
	var before_first := cur < 0
	var target := nxt if not before_first else 0
	if cur >= 0 and cur + 1 >= chart.beats.size():
		target = cur
	# Bei einer Pause ruht die Figur: Hinweis statt Figur.
	_meter_label = str(chart.bars[int(chart.beats[target].bar)].label)
	if gap:
		_draw_rest()
		_draw_bar()
		return
	var bar_i: int = int(chart.beats[target].bar)
	_draw_figure(bar_i, target)
	_draw_announce(bar_i, target)
	_draw_trace(cur, nxt)
	_draw_beat_fx()
	_draw_hand()
	_draw_bar()


func _draw_rest() -> void:
	var c := center_px()
	var txt := tr("Pause")
	var w := _head_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(_head_font, c - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.5))


func _fig_beats(bar_i: int) -> Array:
	var b: Dictionary = chart.bars[bar_i]
	var out: Array = []
	for k in int(b.count):
		out.append(int(b.i0) + k)
	return out


func _draw_figure(bar_i: int, target: int) -> void:
	var ids := _fig_beats(bar_i)
	var r := core.HIT_R * unit_px() if core != null else 40.0
	var ri := DirigentCore.INNER_R * unit_px()
	var font_px := int(clampf(size.y * 0.046, 22.0, 42.0))
	var small_px := int(clampf(size.y * 0.022, 12.0, 20.0))
	var nxt := target + 1
	# Uebrige Punkte der Figur: nur kleine Marken (Form der Figur bleibt lesbar).
	for id in ids:
		if id == target or id == nxt:
			continue
		var passed: bool = float(chart.beats[id].t) < t_ms
		draw_circle(to_px(chart.beats[id].pos), 4.0, Color(INK, 0.14 if passed else 0.28), true, -1.0, true)
	# Naechster Punkt: klein, nummeriert.
	if nxt < chart.beats.size() and not chart.is_gap(target):
		var nb: Dictionary = chart.beats[nxt]
		var np := to_px(nb.pos)
		var nr := r * 0.42
		draw_circle(np, nr, Color(INK, 0.05), true, -1.0, true)
		draw_arc(np, nr, 0.0, TAU, 32, Color(INK, 0.38), 1.5, true)
		var ns := str(int(nb.pt) + 1)
		var nw := _head_font.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, small_px).x
		draw_string(_head_font, np + Vector2(-nw * 0.5, small_px * 0.36), ns, HORIZONTAL_ALIGNMENT_LEFT, -1,
			small_px, Color(INK, 0.6))
	# Aktueller Zielpunkt: gross.
	var b: Dictionary = chart.beats[target]
	var p := to_px(b.pos)
	draw_arc(p, r, 0.0, TAU, 56, Color(INK, 0.38), 1.5, true)
	draw_arc(p, ri, 0.0, TAU, 40, Color(INK, 0.24), 1.0, true)
	_draw_pulse(p, target, b, r)
	var num := str(int(b.pt) + 1)
	var tw := _head_font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	draw_string(_head_font, p + Vector2(-tw * 0.5, font_px * 0.36), num, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_px, Color(INK, 0.95))


## Zielpunkt: Anflugring schrumpft ueber die ganze Zeit seit dem letzten Schlag auf den
## Trefferkreis zu (= Zeit bis zum Schlag), die Flaeche pulsiert kurz vor dem Schlag.
func _draw_pulse(p: Vector2, id: int, b: Dictionary, r: float) -> void:
	var dt := float(b.t) - t_ms
	if dt < -120.0:
		return
	var lead := APPROACH_MS
	if id > 0:
		lead = clampf(float(b.t) - float(chart.beats[id - 1].t), 250.0, 1100.0)
	var k := clampf(1.0 - dt / lead, 0.0, 1.0)
	if dt > 0.0:
		var rr := r * (1.0 + (1.0 - k) * 1.6)
		draw_arc(p, rr, 0.0, TAU, 64, Color(INK, 0.20 + 0.65 * k), 2.0 + 2.0 * k, true)
	var pulse := 0.0
	if dt > -100.0 and dt < 260.0:
		pulse = clampf(1.0 - absf(dt) / 260.0, 0.0, 1.0)
		pulse = pulse * pulse
	draw_circle(p, r * (0.55 + 0.45 * pulse), Color(INK, 0.06 + 0.20 * pulse), true, -1.0, true)
	draw_arc(p, r, 0.0, TAU, 56, Color(INK, 0.45 + 0.5 * pulse), 2.0 + 1.5 * pulse, true)


func _dotted(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1.0:
		return
	var step := 9.0
	var n := int(ln / step)
	var dir := d / ln
	for i in range(0, n, 2):
		draw_line(a + dir * (float(i) * step), a + dir * (minf(float(i + 1) * step, ln)), col, 1.5, true)


## Taktwechsel: einen Takt vorher steht die neue Figur als Schablone rechts.
func _draw_announce(bar_i: int, target: int) -> void:
	if bar_i + 1 >= chart.bars.size():
		return
	var cur_bar: Dictionary = chart.bars[bar_i]
	var nb: Dictionary = chart.bars[bar_i + 1]
	if nb.label == cur_bar.label and nb.kind == cur_bar.kind:
		return
	if float(nb.t) - float(cur_bar.t) > BAR_LEAD_MS * 4.0:
		return
	var pts := DirigentChart.figure_points(str(nb.kind), int(nb.n))
	var sc := 0.32
	var origin := Vector2(size.x * 0.5 + unit_px() * 1.18, size.y * 0.20)
	for k in pts.size():
		var p := origin + pts[k] * sc * unit_px()
		if k > 0:
			_dotted(origin + pts[k - 1] * sc * unit_px(), p, Color(KEY_B_COL, 0.35))
		draw_circle(p, 8.0, Color(KEY_B_COL, 0.28), true, -1.0, true)
		draw_arc(p, 8.0, 0.0, TAU, 20, Color(KEY_B_COL, 0.8), 1.5, true)
		draw_string(_font, p + Vector2(-4, 5), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.9))
	var txt := tr("Taktwechsel: %s") % nb.label
	var tw := _head_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(_head_font, origin + Vector2(-tw * 0.5, unit_px() * sc + 40.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(KEY_B_COL, 0.95))
	var sub := tr("ab dem nächsten Takt")
	var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_font, origin + Vector2(-sw * 0.5, unit_px() * sc + 60.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(DIM, 0.95))


## Leuchtspur: Ideal-Weg vom letzten zum naechsten Punkt, Spitze = Soll-Hand.
func _draw_trace(cur: int, nxt: int) -> void:
	if not show_guides or chart.beats.size() < 2:
		return
	var a_i := maxi(cur, 0)
	if cur < 0:
		return
	if a_i == nxt or chart.is_gap(a_i):
		return
	var a: Vector2 = chart.beats[a_i].pos
	var b: Vector2 = chart.beats[nxt].pos
	var t0 := float(chart.beats[a_i].t)
	var t1 := float(chart.beats[nxt].t)
	var u_now := clampf((t_ms - t0) / (t1 - t0), 0.0, 1.0)
	var steps := 36
	var prev := to_px(DirigentChart.path_point(a, b, 0.0))
	for i in range(1, steps + 1):
		var u := float(i) / float(steps)
		var p := to_px(DirigentChart.path_point(a, b, u))
		# Voraus schwach, schon gelaufen heller; kurz hinter der Spitze am hellsten.
		var behind := u_now - u
		var al := 0.10
		if behind >= 0.0:
			al = 0.10 + 0.55 * exp(-behind * 6.0)
		draw_line(prev, p, Color(INK, al), 3.0 if behind >= 0.0 and behind < 0.2 else 1.6, true)
		prev = p
	var head := to_px(DirigentChart.path_point(a, b, u_now))
	draw_circle(head, 7.0, Color(INK, 0.16), true, -1.0, true)
	draw_circle(head, 3.5, Color(INK, 0.95), true, -1.0, true)


func _draw_beat_fx() -> void:
	var keep: Array = []
	for fx in _beat_fx:
		var age := t_ms - float(fx[0])
		if age > 650.0 or age < -50.0:
			continue
		keep.append(fx)
		var k := clampf(age / 650.0, 0.0, 1.0)
		var p := to_px(fx[1])
		var hit: bool = fx[2]
		var r := DirigentCore.HIT_R * unit_px()
		if hit:
			var col := HIT_COL.lerp(INK, float(fx[3]) - 0.88) if float(fx[3]) >= 0.88 else HIT_COL
			draw_arc(p, r * (1.0 + 0.25 * k), 0.0, TAU, 56, Color(col, 0.85 * (1.0 - k)), 3.0, true)
		else:
			var h := r * 0.38
			var al := 0.9 * (1.0 - k)
			draw_line(p - Vector2(h, h), p + Vector2(h, h), Color(MISS_COL, al), 3.0, true)
			draw_line(p - Vector2(h, -h), p + Vector2(h, -h), Color(MISS_COL, al), 3.0, true)
			var txt := tr("Schlag verfehlt")
			var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(_font, p + Vector2(-tw * 0.5, -r - 12.0 - 10.0 * k), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(MISS_COL, al))
	_beat_fx = keep


func _draw_hand() -> void:
	if _trail.size() > 1:
		for i in range(1, _trail.size()):
			var al := float(i) / float(_trail.size())
			draw_line(_trail[i - 1], _trail[i], Color(INK, 0.30 * al), 2.0 + 3.0 * al, true)
	var p := cursor_px
	draw_circle(p, 11.0, Color(PLATE, 0.8), true, -1.0, true)
	draw_arc(p, 9.0, 0.0, TAU, 28, Color(INK, 0.95), 2.0, true)
	draw_circle(p, 2.5, Color(INK, 0.95), true, -1.0, true)


# ---------------------------------------------------------------------------
# Einsatz-Leiste
# ---------------------------------------------------------------------------

func _draw_bar() -> void:
	var r := bar_rect()
	var line_x := _bar_line_x()
	var mid_y := r.position.y + r.size.y * 0.5
	var h := r.size.y
	# Streifen: flach, mit feiner Kante.
	draw_rect(r, Color(1, 1, 1, 0.035), true)
	draw_rect(r, Color(INK, 0.10), false, 1.0)
	# Trefferfenster-Zone um die Linie (CORE-Breite im Zeitmass).
	if core != null:
		var wpx := core.w300 / BAR_LEAD_MS * (r.end.x - line_x)
		draw_rect(Rect2(line_x - wpx, r.position.y, wpx * 2.0, h), Color(INK, 0.05), true)
	# Schlag-Ticks: das Raster der Figur auf der Leiste (Off-Beat-Einsaetze lesbar).
	var bi := maxi(chart.beat_at(t_ms), 0)
	while bi < chart.beats.size():
		var tb := float(chart.beats[bi].t)
		if tb - t_ms > BAR_LEAD_MS:
			break
		if tb >= t_ms - 60.0:
			var bx := _cue_x(tb)
			draw_line(Vector2(bx, r.position.y), Vector2(bx, r.position.y + h * 0.16), Color(INK, 0.40), 1.5, true)
			draw_line(Vector2(bx, r.end.y - h * 0.16), Vector2(bx, r.end.y), Color(INK, 0.40), 1.5, true)
		bi += 1
	# Trefferlinie (deutlich) mit Ring, Legende links in den Formen der Marken.
	var held_a: bool = key_held[0]
	var held_b: bool = key_held[1]
	draw_line(Vector2(line_x, r.position.y - 8.0), Vector2(line_x, r.end.y + 8.0), Color(INK, 0.22), 9.0, true)
	draw_line(Vector2(line_x, r.position.y - 8.0), Vector2(line_x, r.end.y + 8.0), Color(INK, 1.0), 3.0, true)
	draw_arc(Vector2(line_x, mid_y), h * 0.40, 0.0, TAU, 40, Color(INK, 0.85), 2.5, true)
	_key_cap(Vector2(r.position.x + 30.0, mid_y), key_names[0], KEY_A_COL, held_a, 0)
	_key_cap(Vector2(r.position.x + 78.0, mid_y), key_names[1], KEY_B_COL, held_b, 1)
	if _meter_label != "":
		var mw := _head_font.get_string_size(_meter_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(_head_font, Vector2(r.end.x - mw, r.position.y - 9.0), _meter_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(DIM, 0.95))
	# Marken.
	if chart.cues.is_empty():
		return
	while _cue_first < chart.cues.size() and float(chart.cues[_cue_first].t) < t_ms - 260.0:
		_cue_first += 1
	var i := _cue_first
	var rad := h * 0.26
	while i < chart.cues.size():
		var tc := float(chart.cues[i].t)
		if tc - t_ms > BAR_LEAD_MS:
			break
		var done := core != null and core.is_cue_done(i)
		var x := _cue_x(tc)
		if not done or t_ms < tc + 120.0:
			_draw_mark(Vector2(x, mid_y), rad, int(chart.cues[i].mask), done, clampf(1.0 - (tc - t_ms) / BAR_LEAD_MS * 0.25, 0.6, 1.0))
		i += 1
	# Rueckmeldung an der Linie.
	var keep: Array = []
	for fx in _cue_fx:
		var age := t_ms - float(fx[0])
		if age > 380.0 or age < -50.0:
			continue
		keep.append(fx)
		var k := clampf(age / 380.0, 0.0, 1.0)
		var q := int(fx[1])
		var col := MISS_COL if q == 5 else INK
		draw_arc(Vector2(line_x, mid_y), rad * (1.2 + 1.2 * k), 0.0, TAU, 32, Color(col, 0.7 * (1.0 - k)), 2.0, true)
	_cue_fx = keep


## Legende: dieselbe Form und Farbe wie die Marke (A = Kreis, B = Raute), Taste darin.
func _key_cap(p: Vector2, txt: String, col: Color, held: bool, key: int) -> void:
	var fill := Color(col, 0.95 if held else 0.22)
	if key == 0:
		draw_circle(p, 15.0, fill, true, -1.0, true)
		draw_arc(p, 15.0, 0.0, TAU, 28, Color(col, 0.95), 1.8, true)
	else:
		var d := 18.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), fill)
		draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]),
			Color(col, 0.95), 1.8, true)
	var tw := _head_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_head_font, p + Vector2(-tw * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		PLATE if held else Color(col.lerp(INK, 0.4), 1.0))


## Marke: Kreis = A (Bernstein), Raute = B (Stahlblau), beide = zwei Haelften.
func _draw_mark(p: Vector2, rad: float, mask: int, done: bool, a: float) -> void:
	var al := a * (0.28 if done else 1.0)
	if mask == 1:
		draw_circle(p, rad, Color(KEY_A_COL, al), true, -1.0, true)
		draw_arc(p, rad, 0.0, TAU, 24, Color(INK, 0.5 * al), 1.2, true)
	elif mask == 2:
		_diamond(p, rad * 1.18, Color(KEY_B_COL, al))
	else:
		# Akkord: beide Tasten, uebereinander (A oben, B unten).
		var o := rad * 1.05
		draw_circle(p + Vector2(0, -o), rad * 0.82, Color(KEY_A_COL, al), true, -1.0, true)
		_diamond(p + Vector2(0, o), rad * 0.98, Color(KEY_B_COL, al))
		draw_line(p + Vector2(-rad, 0), p + Vector2(rad, 0), Color(INK, 0.35 * al), 1.0, true)


func _diamond(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(INK, 0.5 * col.a), 1.2, true)
