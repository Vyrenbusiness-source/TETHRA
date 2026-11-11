class_name RallyView
extends Control

## Rally: Seitenansicht (ein _draw). Spieler links, Gegner rechts, Tisch, ein Ball.
## Alles ist eine reine Funktion von t_ms + Wertung (RallyCore): Ball, Marken und
## Schlaeger werden jedes Bild neu aus RallyChart berechnet, nichts davon steuert
## die Wertung. Farbe = Taste (A kuehl/tief, B warm/hoch), Schmetterball weiss
## umrandet, Aufprallmarke mit schrumpfendem Ring = WANN.

const COL_A := Color(0.52, 0.74, 0.92)
const COL_B := Color(0.95, 0.64, 0.23)
const COL_SMASH := Color(0.93, 0.90, 0.85)
const COL_TABLE := Color(0.17, 0.205, 0.255)
const COL_TABLE_EDGE := Color(0.925, 0.902, 0.855, 0.38)
const COL_APRON := Color(0.075, 0.07, 0.068)
const COL_ME := Color(0.925, 0.902, 0.855)
const COL_OPP := Color(0.56, 0.62, 0.70)
const COL_MISS := Color(0.87, 0.44, 0.38)
const APPROACH_MS := 800.0
const FLOOR_Y := 0.80
const BALL_R := 0.027
const TRAIL_MS := 120.0
const TRAIL_N := 30
const FX_MS := 190.0
const MISS_FLY_MS := 420.0
## Tischplatte in Perspektive: hinten schmaler, vorn breiter (Anteile von Bildhoehe/-breite).
const TOP_FAR := -0.030
const TOP_NEAR := 0.052
const SLAB := 0.022

var shots: Array[RallyChart.Shot] = []
var core: RallyCore
var t_ms := 0.0
var held := [false, false]
var key_labels := ["A", "B"]
## Beim Sprung in der Zeit (Shots/Replay) Effektliste leeren.
var _fx: Array = []
var _swing_t := -9999.0
var _shake := 0.0
var _font: Font
var _key_font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_key_font = UiTheme.heading_font(2)


static func key_col(key: int) -> Color:
	return COL_B if key == RallyChart.KEY_B else COL_A


func setup(p_shots: Array[RallyChart.Shot], p_core: RallyCore) -> void:
	shots = p_shots
	core = p_core


## Wertung eines Schlags: Aufprall-Effekt an der Trefferstelle.
func on_judged(idx: int, result: Dictionary) -> void:
	if idx < 0 or idx >= shots.size():
		return
	var s := shots[idx]
	var q := int(result.get("quality", 5))
	var pos := Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(s.key))
	if q == 5:
		_fx.append({"t0": t_ms, "pos": pos, "kind": "miss", "col": COL_MISS, "smash": false})
		return
	if bool(result.get("hold_end", false)):
		_fx.append({"t0": t_ms, "pos": pos, "kind": "release", "col": key_col(s.key), "smash": false})
	else:
		_fx.append({"t0": t_ms, "pos": pos, "kind": "hit", "col": key_col(s.key), "smash": s.smash,
				"q": q})
		_swing_t = t_ms
		if s.smash:
			_shake = 1.0
	while _fx.size() > 12:
		_fx.pop_front()


func on_charge(idx: int) -> void:
	if idx < 0 or idx >= shots.size():
		return
	var s := shots[idx]
	_fx.append({"t0": t_ms, "pos": Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(s.key)),
			"kind": "hit", "col": key_col(s.key), "smash": false, "q": 1})


func reset_fx() -> void:
	_fx.clear()
	_swing_t = -9999.0


func _process(delta: float) -> void:
	_shake = maxf(_shake - delta * 7.0, 0.0)
	queue_redraw()


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------


func _p(v: Vector2) -> Vector2:
	return Vector2(v.x * size.x, v.y * size.y)


func _draw() -> void:
	if shots.is_empty() or size.x < 10.0:
		return
	var off := Vector2.ZERO
	if _shake > 0.0:
		# Kamera-Impuls nur beim Schmetterball, hoechstens 2 px.
		off = Vector2(sin(t_ms * 0.09), cos(t_ms * 0.13)) * (1.9 * _shake)
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_room()
	_draw_preview()
	_draw_players()
	_draw_targets()
	_draw_bounces()
	_draw_balls()
	_draw_fx()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gradient_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color) -> void:
	draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([ca, ca, cb, cb]))


## Ruhiger Raum: Boden als weicher Verlauf, Tisch mit Perspektive, Netz mit Proportionen.
func _draw_room() -> void:
	var w := size.x
	var h := size.y
	var fy := h * FLOOR_Y
	_gradient_quad(Vector2(0, fy), Vector2(w, fy), Vector2(w, h), Vector2(0, h),
			Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.0))
	draw_line(Vector2(0, fy), Vector2(w, fy), Color(1, 1, 1, 0.07), 1.0)
	var ty := RallyChart.Y_TABLE * h
	var xl := RallyChart.X_TABLE_L * w
	var xr := RallyChart.X_TABLE_R * w
	var inset := (xr - xl) * 0.022
	var yf := ty + TOP_FAR * h
	var yn := ty + TOP_NEAR * h
	var slab := SLAB * h
	# Weicher Bodenschatten unter dem Tisch.
	for i in 4:
		var f := float(i) / 3.0
		draw_set_transform(Vector2(w * 0.5, fy + 0.012 * h), 0.0, Vector2(1.0, 0.07))
		draw_circle(Vector2.ZERO, (xr - xl) * (0.50 - 0.05 * f), Color(0, 0, 0, 0.06))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Beine.
	var legw := 0.011 * w
	for lx in [xl + 0.055 * w, xr - 0.055 * w - legw]:
		_gradient_quad(Vector2(lx, yn + slab), Vector2(lx + legw, yn + slab),
				Vector2(lx + legw, fy), Vector2(lx, fy), COL_APRON.lightened(0.07), COL_APRON)
	# Platte: Oberflaeche mit Verlauf (hinten dunkler), Spielerhaelfte einen Hauch heller.
	var far_c := COL_TABLE.darkened(0.18)
	var near_c := COL_TABLE.lightened(0.10)
	var mid := w * 0.5
	var mf := lerpf(xl + inset, xr - inset, 0.5)
	var mn := mid
	draw_polygon(PackedVector2Array([Vector2(xl + inset, yf), Vector2(mf, yf), Vector2(mn, yn), Vector2(xl, yn)]),
			PackedColorArray([far_c.lightened(0.04), far_c.lightened(0.04), near_c.lightened(0.04), near_c.lightened(0.04)]))
	draw_polygon(PackedVector2Array([Vector2(mf, yf), Vector2(xr - inset, yf), Vector2(xr, yn), Vector2(mn, yn)]),
			PackedColorArray([far_c, far_c, near_c, near_c]))
	# Vorderkante (Zarge) mit heller Oberkante.
	_gradient_quad(Vector2(xl, yn), Vector2(xr, yn), Vector2(xr, yn + slab), Vector2(xl, yn + slab),
			COL_TABLE.lightened(0.02), COL_APRON.lightened(0.04))
	draw_line(Vector2(xl, yn), Vector2(xr, yn), COL_TABLE_EDGE, 1.6, true)
	draw_line(Vector2(xl + inset, yf), Vector2(xr - inset, yf), Color(COL_TABLE_EDGE, 0.16), 1.0, true)
	draw_line(Vector2(xl + inset, yf), Vector2(xl, yn), Color(COL_TABLE_EDGE, 0.16), 1.0, true)
	draw_line(Vector2(xr - inset, yf), Vector2(xr, yn), Color(COL_TABLE_EDGE, 0.16), 1.0, true)
	# Weisse Randlinie der Platte (fein, in Perspektive).
	var bi := 0.05
	var b0 := Vector2(lerpf(xl + inset, xr - inset, bi), lerpf(yf, yn, 0.12))
	var b1 := Vector2(lerpf(xr - inset, xl + inset, bi), b0.y)
	var b2 := Vector2(lerpf(xr, xl, bi * 0.8), lerpf(yn, yf, 0.12))
	var b3 := Vector2(lerpf(xl, xr, bi * 0.8), b2.y)
	draw_polyline(PackedVector2Array([b0, b1, b2, b3, b0]), Color(1, 1, 1, 0.10), 1.0, true)
	# Mittellinie quer ueber die Platte.
	draw_line(Vector2(mf, yf), Vector2(mn, yn), Color(1, 1, 1, 0.10), 1.0, true)
	# Netz: Bandkante oben, feine Flaeche, kleiner Fuss.
	var nh := 0.062 * h
	var nx := mid
	draw_rect(Rect2(nx - 1.5, ty - nh, 3.0, nh + 3.0), Color(0.78, 0.82, 0.86, 0.50))
	draw_rect(Rect2(nx - 2.5, ty - nh - 1.0, 5.0, 3.0), Color(0.93, 0.92, 0.89, 0.95))
	draw_rect(Rect2(nx - 4.0, ty - 1.0, 8.0, 4.0), Color(0.60, 0.64, 0.68, 0.9))


## Fein gestrichelte Vorschau der Flugbahn zum naechsten Schlag.
func _draw_preview() -> void:
	var k := RallyChart.first_at_or_after(shots, t_ms - 1.0)
	if k >= shots.size():
		return
	var s := shots[k]
	if s.t - t_ms > 1800.0:
		return
	var t0 := maxf(s.m, t_ms)
	if t0 >= s.t - 40.0:
		return
	var n := 36
	var col := key_col(s.key)
	var prev := _p(RallyChart.pos_in(shots, k, t0))
	for i in range(1, n + 1):
		var tt := lerpf(t0, s.t, float(i) / float(n))
		var cur := _p(RallyChart.pos_in(shots, k, tt))
		if i % 3 != 0:
			var f := float(i) / float(n)
			draw_line(prev, cur, Color(col, 0.10 + 0.38 * f), 1.6, true)
		prev = cur


## Feste, ruhige Hoehenmarken mit Taste im Ring und die kommenden Aufprallringe.
func _draw_targets() -> void:
	var r := BALL_R * size.y * 1.38
	for k in 2:
		var c := _p(Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(k)))
		var col := key_col(k)
		var lit: bool = bool(held[k])
		draw_circle(c, r, Color(col, 0.16 if lit else 0.05))
		draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.30), 1.4, true)
		var txt: String = key_labels[k]
		var fs := int(size.y * 0.030)
		var ts := _key_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var ta := 0.95 if lit else 0.50
		draw_string(_key_font, c + Vector2(-ts.x * 0.5, ts.y * 0.30), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(col.lerp(Color.WHITE, 0.4 if lit else 0.1), ta))
		if lit:
			draw_arc(c, r + 3.0, 0.0, TAU, 48, Color(col, 0.85), 2.0, true)
	var first := RallyChart.first_at_or_after(shots, t_ms - 60.0)
	var shown := 0
	var k2 := first
	while k2 < shots.size() and shown < 2:
		var s := shots[k2]
		var lead := s.t - t_ms
		if lead > APPROACH_MS:
			break
		if not _judged_done(k2):
			_draw_reticle(s, k2, lead, k2 == first)
			shown += 1
		k2 += 1


func _judged_done(k: int) -> bool:
	return core != null and core.is_judged(k)


func _draw_reticle(s: RallyChart.Shot, k: int, lead: float, is_next: bool) -> void:
	var rt := BALL_R * size.y * 1.38
	var c := _p(Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(s.key)))
	var col := key_col(s.key)
	var fade := clampf((APPROACH_MS - lead) / 160.0, 0.0, 1.0)
	if lead < -10.0:
		fade *= clampf(1.0 + lead / 60.0, 0.0, 1.0)
	var charging := core != null and core.is_charging(k)
	if not charging:
		if is_next:
			# Genau ein grosser Ring: schrumpft auf die Ziel-Marke.
			var r := rt + rt * 2.4 * clampf(lead / APPROACH_MS, 0.0, 1.0)
			if s.smash:
				draw_arc(c, r + 4.0, 0.0, TAU, 64, Color(COL_SMASH, 0.9 * fade), 1.6, true)
			draw_arc(c, r, 0.0, TAU, 64, Color(col, fade), 2.4, true)
		else:
			# Folgeschlag: klein, gedimmt, ruhend.
			var r2 := rt * 1.55
			draw_arc(c, r2, 0.0, TAU, 48, Color(col, 0.26 * fade), 1.4, true)
			if s.smash:
				draw_arc(c, r2 + 3.0, 0.0, TAU, 48, Color(COL_SMASH, 0.22 * fade), 1.0, true)
	if s.smash:
		draw_arc(c, rt + 3.0, 0.0, TAU, 40, Color(COL_SMASH, (0.85 if is_next else 0.3) * fade), 1.5, true)
	if s.is_charge():
		# Loslassen: zweiter, gestrichelter Ring schrumpft auf die Endzeit.
		var le := s.end - t_ms
		var r3 := rt + rt * 2.2 * clampf(le / (APPROACH_MS * 2.0), 0.0, 1.0) + 4.0
		var seg := 24
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			draw_arc(c, r3, a0, a0 + TAU / float(seg) * 0.5, 6,
					Color(col, (0.85 if is_next else 0.35) * fade), 2.0, true)


# ---------------------------------------------------------------------------
# Schlaeger (nur stilisierte Paddel, flach, ohne Koerper)
# ---------------------------------------------------------------------------

func _blade(c: Vector2, rx: float, ry: float, ang: float, col: Color, rubber: Color) -> void:
	var n := 40
	var pts := PackedVector2Array()
	var pts2 := PackedVector2Array()
	var ca := cos(ang)
	var sa := sin(ang)
	for i in n:
		var a := TAU * float(i) / float(n)
		var v := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(c + Vector2(v.x * ca - v.y * sa, v.x * sa + v.y * ca))
		var v2 := v * 0.82
		pts2.append(c + Vector2(v2.x * ca - v2.y * sa, v2.x * sa + v2.y * ca))
	draw_colored_polygon(pts, col)
	draw_colored_polygon(pts2, rubber)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(1, 1, 1, 0.22), 1.0, true)


func _paddle(c: Vector2, ang: float, col: Color, rubber: Color) -> void:
	# ang: Neigung der Klingenachse (0 = senkrecht).
	var h := size.y
	var ry := 0.054 * h
	var rx := 0.029 * h
	var up := Vector2(sin(ang), -cos(ang))
	var grip_a := c - up * ry * 0.92
	var grip_b := grip_a - up * 0.052 * h
	var wood := UiTheme.ACCENT.darkened(0.25)
	draw_line(grip_a, grip_b, wood, 0.014 * h, true)
	draw_circle(grip_b, 0.007 * h, wood)
	_blade(c, rx, ry, ang, col, rubber)


func _draw_players() -> void:
	var h := size.y
	var py := _paddle_y()
	var swing := clampf((t_ms - _swing_t) / 140.0, 0.0, 1.0)
	var fwd := sin(PI * swing) * 0.016 if swing < 1.0 else 0.0
	var pull := 0.0
	if core != null and core.charging >= 0:
		var cs := shots[core.charging]
		pull = -0.02 * clampf((t_ms - cs.t) / maxf(cs.end - cs.t, 1.0), 0.0, 1.0)
	var gap := BALL_R * h * 1.38 * 1.9 / size.x
	var pp := _p(Vector2(RallyChart.X_PLAYER - gap + fwd + pull, py))
	var tilt := 0.12 + (0.0 if swing >= 1.0 else 0.35 * sin(PI * swing))
	_paddle(pp, tilt, COL_ME, Color(0.20, 0.15, 0.10).lerp(UiTheme.ACCENT, 0.32))
	# Gegner: schlaegt zur Mitte der Flugzeit zurueck.
	var ofwd := 0.0
	var j := RallyChart.first_at_or_after(shots, t_ms - 120.0)
	for k in range(maxi(j - 1, 0), mini(j + 2, shots.size())):
		var u := (t_ms - shots[k].m + 50.0) / 170.0
		if u >= 0.0 and u <= 1.0:
			ofwd = -sin(PI * u) * 0.030
	var op := _p(Vector2(RallyChart.X_OPP + gap + ofwd, RallyChart.Y_OPP))
	_paddle(op, -0.12 - (0.0 if ofwd > -0.002 else 0.3), COL_OPP, Color(0.12, 0.14, 0.17))


## Schlaeger-Hoehe: gleitet vor dem Treffer auf die Hoehe des naechsten Balls.
func _paddle_y() -> float:
	var j := RallyChart.first_at_or_after(shots, t_ms - 80.0)
	var rest := 0.50
	if j >= shots.size():
		return rest
	var tgt := RallyChart.hit_y(shots[j].key)
	var prev := rest
	var gap := 700.0
	if j > 0:
		prev = RallyChart.hit_y(shots[j - 1].key)
		gap = clampf(shots[j].t - shots[j - 1].end, 60.0, 700.0)
	var span := minf(gap, 260.0)
	var u := clampf(1.0 - (shots[j].t - t_ms) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	if j == 0 or shots[j].t - shots[j - 1].end > 1500.0:
		prev = rest
		span = 500.0
		u = clampf(1.0 - (shots[j].t - t_ms) / span, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
	return lerpf(prev, tgt, u)


# ---------------------------------------------------------------------------
# Ball
# ---------------------------------------------------------------------------

func _result_hit(k: int) -> int:
	## 1 = getroffen (oder Aufladen laeuft), 0 = Fehlschlag, -1 = noch offen.
	if core == null:
		return -1
	if core.is_charging(k):
		return 1
	var r: Dictionary = core.result_of(k)
	if r.is_empty() or bool(r.get("pending", false)):
		return -1
	return 0 if int(r.get("quality", 5)) == 5 else 1


func _draw_balls() -> void:
	var j := RallyChart.first_at_or_after(shots, t_ms - 1.0)
	for k in range(maxi(j - 3, 0), mini(j + 2, shots.size())):
		var s := shots[k]
		var res := _result_hit(k)
		# Anflug zu Schlag k.
		if t_ms >= s.m and t_ms <= s.t:
			var fn := func(tt: float) -> Vector2: return RallyChart.pos_in(shots, k, tt)
			_draw_ball(fn, s.m, t_ms, s.key, s.smash, 1.0)
		elif res != 1 and t_ms > s.t and t_ms < s.t + MISS_FLY_MS:
			# Verfehlt: der Ball fliegt am Schlaeger vorbei und verblasst.
			var fn2 := func(tt: float) -> Vector2: return RallyChart.pos_in(shots, k, tt)
			var a := 1.0 - (t_ms - s.t) / MISS_FLY_MS
			_draw_ball(fn2, s.m, t_ms, s.key, s.smash, a * a, true)
		if res != 1:
			continue
		# Aufladen: Ball haengt am Schlaeger, Ring fuellt sich bis zum Loslassen.
		if s.is_charge() and t_ms > s.t and (core.is_charging(k) or t_ms <= s.end):
			var hold_pos := Vector2(RallyChart.X_PLAYER - 0.004, RallyChart.hit_y(s.key))
			var fn3 := func(_tt: float) -> Vector2: return hold_pos
			_draw_ball(fn3, s.t, t_ms, s.key, false, 1.0)
			var prog := clampf((t_ms - s.t) / maxf(s.end - s.t, 1.0), 0.0, 1.0)
			var c := _p(hold_pos)
			var r := BALL_R * size.y * 1.8
			draw_arc(c, r, 0.0, TAU, 48, Color(key_col(s.key), 0.22), 2.0, true)
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * prog, 48, Color(key_col(s.key), 0.95), 3.0, true)
			continue
		# Rueckschlag: von der Freigabe zum Gegner.
		var fin := RallyChart.out_end(shots, k)
		if t_ms >= s.end and t_ms <= fin:
			var nk := shots[k + 1] if k + 1 < shots.size() else s
			var fn4 := func(tt: float) -> Vector2: return RallyChart.pos_out(shots, k, tt)
			var fade := 1.0
			if s.exit_after or k + 1 >= shots.size() or nk.serve:
				fade = clampf((fin - t_ms) / 300.0, 0.0, 1.0)
			_draw_ball(fn4, s.end, t_ms, nk.key, nk.smash if k + 1 < shots.size() else false, fade)


func _draw_ball(fn: Callable, t_from: float, t_now: float, key: int, smash: bool, alpha: float,
		missed: bool = false) -> void:
	var col := key_col(key)
	if missed:
		col = col.lerp(Color(0.55, 0.55, 0.58), 0.55)
	var r := BALL_R * size.y
	var pos: Vector2 = _p(fn.call(t_now))
	# Weicher Schatten auf der Tischmitte, kleiner und dunkler je naeher am Tisch.
	var tx0 := RallyChart.X_TABLE_L * size.x
	var tx1 := RallyChart.X_TABLE_R * size.x
	var ty := RallyChart.Y_TABLE * size.y
	var hgt := clampf((ty - pos.y) / (size.y * 0.45), 0.0, 1.0)
	if pos.x > tx0 and pos.x < tx1 and pos.y < ty + 2.0:
		for i in 3:
			var f := float(i) / 2.0
			draw_set_transform(Vector2(pos.x, ty + 2.0), 0.0, Vector2(1.0, 0.24))
			draw_circle(Vector2.ZERO, r * (1.7 - 0.45 * f) * (1.0 + 0.5 * hgt),
					Color(0, 0, 0, (0.10 + 0.05 * f) * alpha * (1.0 - 0.55 * hgt)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Schmier: nur die letzten ~120 ms, weich auslaufend entlang der echten Bahn.
	var t0 := maxf(t_from, t_now - TRAIL_MS)
	for i in range(TRAIL_N, 0, -1):
		var tt := lerpf(t_now, t0, float(i) / float(TRAIL_N))
		if tt < t_from:
			continue
		var q := 1.0 - float(i) / float(TRAIL_N + 1)
		draw_circle(_p(fn.call(tt)), r * (0.30 + 0.62 * q), Color(col, 0.05 * q * alpha))
	if smash:
		draw_arc(pos, r + 3.5, 0.0, TAU, 40, Color(COL_SMASH, 0.95 * alpha), 1.8, true)
	draw_circle(pos, r, Color(col.darkened(0.10), alpha))
	draw_circle(pos + Vector2(-r * 0.18, -r * 0.2), r * 0.72, Color(col.lightened(0.14), alpha))
	draw_circle(pos + Vector2(-r * 0.34, -r * 0.38), r * 0.22, Color(1, 1, 1, 0.55 * alpha))
	draw_arc(pos, r, 0.0, TAU, 32, Color(0, 0, 0, 0.30 * alpha), 1.2, true)


# ---------------------------------------------------------------------------
# Aufprall und Effekte (kurz, < 200 ms)
# ---------------------------------------------------------------------------

func _draw_bounces() -> void:
	var j := RallyChart.first_at_or_after(shots, t_ms - 200.0)
	for k in range(maxi(j - 2, 0), mini(j + 2, shots.size())):
		var tb := RallyChart.bounce_me_time(shots, k)
		_bounce_ring(tb, RallyChart.pos_in(shots, k, tb).x)
		if _result_hit(k) == 1:
			var to := RallyChart.bounce_opp_time(shots, k)
			_bounce_ring(to, RallyChart.pos_out(shots, k, to).x)


func _bounce_ring(tb: float, x: float) -> void:
	var u := (t_ms - tb) / 160.0
	if u < 0.0 or u > 1.0:
		return
	var ty := RallyChart.Y_TABLE * size.y
	draw_set_transform(Vector2(x * size.x, ty + 2.0), 0.0, Vector2(1.0, 0.22))
	draw_arc(Vector2.ZERO, size.y * (0.014 + 0.036 * u), 0.0, TAU, 32, Color(1, 1, 1, 0.50 * (1.0 - u)), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fx() -> void:
	var keep: Array = []
	for f in _fx:
		var u := (t_ms - float(f.t0)) / FX_MS
		if u < 0.0 or u > 1.0:
			if u < 0.0:
				keep.append(f)
			continue
		keep.append(f)
		var c := _p(f.pos)
		var r0 := BALL_R * size.y
		var col: Color = f.col
		var e := 1.0 - pow(1.0 - u, 3.0)
		match str(f.kind):
			"hit":
				var big := 1.5 if bool(f.smash) else 1.0
				var rr := r0 * (1.5 + 2.2 * big * e)
				if bool(f.smash):
					draw_arc(c, rr + 4.0, 0.0, TAU, 56, Color(COL_SMASH, 0.9 * (1.0 - u)), 1.5, true)
				draw_arc(c, rr, 0.0, TAU, 56, Color(col, 1.0 - u), 2.2, true)
				var n := 10 if bool(f.smash) else 6
				for i in n:
					var ang := TAU * float(i) / float(n) + 0.3
					var d := Vector2(cos(ang), sin(ang))
					draw_line(c + d * (rr * 0.8), c + d * (rr * 0.8 + r0 * (0.9 - 0.7 * u)),
							Color(col.lerp(Color.WHITE, 0.4), 0.8 * (1.0 - u)), 1.6, true)
			"release":
				draw_arc(c, r0 * (1.6 + 1.6 * e), 0.0, TAU, 48, Color(col, 1.0 - u), 2.0, true)
			"miss":
				var d := r0 * 0.7
				var col2 := Color(COL_MISS, 1.0 - u)
				var cc := c + Vector2(0, -u * r0 * 1.2)
				draw_line(cc + Vector2(-d, -d), cc + Vector2(d, d), col2, 2.0, true)
				draw_line(cc + Vector2(-d, d), cc + Vector2(d, -d), col2, 2.0, true)
	_fx = keep
