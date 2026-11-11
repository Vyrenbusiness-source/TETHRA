class_name RallyView
extends Control

## Rally: Seitenansicht (ein _draw). Spieler links, Gegner rechts, Tisch, ein Ball.
## Alles ist eine reine Funktion von t_ms + Wertung (RallyCore): Ball, Marken und
## Schlaeger werden jedes Bild neu aus RallyChart berechnet, nichts davon steuert
## die Wertung. Farbe = Taste (A kuehl/tief, B warm/hoch), Schmetterball weiss
## umrandet, Aufprallmarke mit schrumpfendem Ring = WANN.

const COL_A := Color(0.46, 0.72, 0.90)
const COL_B := Color(0.96, 0.64, 0.26)
const COL_SMASH := Color(0.97, 0.96, 0.93)
const COL_TABLE := Color(0.23, 0.30, 0.36)
const COL_TABLE_EDGE := Color(0.62, 0.72, 0.80)
const COL_APRON := Color(0.14, 0.18, 0.22)
const COL_FLOOR := Color(1, 1, 1, 0.05)
const COL_ME := Color(0.90, 0.87, 0.80)
const COL_OPP := Color(0.47, 0.52, 0.60)
const COL_MISS := Color(0.78, 0.42, 0.38)
const APPROACH_MS := 800.0
const FLOOR_Y := 0.82
const BALL_R := 0.021
const TRAIL_N := 6
const TRAIL_STEP_MS := 13.0
const FX_MS := 190.0
const MISS_FLY_MS := 420.0

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


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
		off = Vector2(sin(t_ms * 0.09), cos(t_ms * 0.13)) * (3.0 * _shake)
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_room()
	_draw_targets()
	_draw_players()
	_draw_balls()
	_draw_fx()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_room() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, h * FLOOR_Y, w, h * (1.0 - FLOOR_Y)), COL_FLOOR)
	draw_line(Vector2(0, h * FLOOR_Y), Vector2(w, h * FLOOR_Y), Color(1, 1, 1, 0.10), 1.5)
	var x0 := RallyChart.X_TABLE_L * w
	var x1 := RallyChart.X_TABLE_R * w
	var ty := RallyChart.Y_TABLE * h
	var slab := 0.016 * h
	# Beine und Zarge.
	var apron := 0.034 * h
	draw_rect(Rect2(x0 + 0.02 * w, ty + slab, 0.012 * w, h * FLOOR_Y - ty - slab), COL_APRON)
	draw_rect(Rect2(x1 - 0.032 * w, ty + slab, 0.012 * w, h * FLOOR_Y - ty - slab), COL_APRON)
	draw_rect(Rect2(x0 + 0.01 * w, ty + slab, x1 - x0 - 0.02 * w, apron), COL_APRON)
	# Platte, Spielerhaelfte etwas heller.
	var mid := w * 0.5
	draw_rect(Rect2(x0, ty, mid - x0, slab), COL_TABLE.lightened(0.06))
	draw_rect(Rect2(mid, ty, x1 - mid, slab), COL_TABLE)
	draw_line(Vector2(x0, ty), Vector2(x1, ty), COL_TABLE_EDGE, 2.0)
	# Netz.
	var nh := 0.058 * h
	draw_rect(Rect2(mid - 1.5, ty - nh, 3.0, nh), Color(0.80, 0.84, 0.88, 0.85))
	draw_rect(Rect2(mid - 2.5, ty - nh, 5.0, 3.0), Color(0.95, 0.96, 0.97, 0.95))


## Feste, ruhige Hoehenmarken (tief = A, hoch = B) und die kommenden Aufprallmarken.
func _draw_targets() -> void:
	var r := BALL_R * size.y * 1.38
	for k in 2:
		var c := _p(Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(k)))
		var col := key_col(k)
		draw_circle(c, r, Color(col, 0.07))
		draw_arc(c, r, 0.0, TAU, 40, Color(col, 0.28), 1.5, true)
		var lit: bool = bool(held[k])
		var txt: String = key_labels[k]
		var fs := int(size.y * 0.026)
		var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(_font, c - Vector2(ts.x * 0.5, -ts.y * 0.28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(col.lerp(Color.WHITE, 0.35 if lit else 0.0), 0.95 if lit else 0.55))
		if lit:
			draw_arc(c, r + 3.0, 0.0, TAU, 40, Color(col, 0.9), 3.0, true)
	var j := RallyChart.first_at_or_after(shots, t_ms - 60.0)
	var shown := 0
	var k := j
	while k < shots.size() and shown < 4:
		var s := shots[k]
		var lead := s.t - t_ms
		if lead > APPROACH_MS:
			break
		if not _judged_done(k):
			_draw_reticle(s, k, lead)
			shown += 1
		k += 1


func _judged_done(k: int) -> bool:
	return core != null and core.is_judged(k)


func _draw_reticle(s: RallyChart.Shot, k: int, lead: float) -> void:
	var rt := BALL_R * size.y * 1.38
	var c := _p(Vector2(RallyChart.X_PLAYER, RallyChart.hit_y(s.key)))
	var col := key_col(s.key)
	var fade := clampf((APPROACH_MS - lead) / 160.0, 0.0, 1.0)
	if lead < -10.0:
		fade *= clampf(1.0 + lead / 60.0, 0.0, 1.0)
	var charging := core != null and core.is_charging(k)
	# Naechster Schlag deutlich, die danach leiser.
	var strong := 1.0 if k == RallyChart.first_at_or_after(shots, t_ms - 60.0) else 0.65
	var a := fade * strong
	if not charging:
		var r := rt + rt * 2.2 * clampf(lead / APPROACH_MS, 0.0, 1.0)
		if s.smash:
			draw_arc(c, r, 0.0, TAU, 56, Color(COL_SMASH, 0.95 * a), 7.0, true)
		draw_arc(c, r, 0.0, TAU, 56, Color(col, a), 3.5, true)
	if s.smash:
		draw_arc(c, rt + 4.0, 0.0, TAU, 40, Color(COL_SMASH, 0.9 * a), 2.5, true)
	if s.is_charge():
		# Loslassen: zweiter, gestrichelter Ring schrumpft auf die Endzeit.
		var le := s.end - t_ms
		var r2 := rt + rt * 2.2 * clampf(le / (APPROACH_MS * 2.0), 0.0, 1.0) + 4.0
		var seg := 20
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			draw_arc(c, r2, a0, a0 + TAU / float(seg) * 0.55, 6, Color(col, 0.85 * fade), 3.0, true)


func _draw_players() -> void:
	var h := size.y
	var w := size.x
	var py := _paddle_y()
	var swing := clampf((t_ms - _swing_t) / 140.0, 0.0, 1.0)
	var fwd := sin(PI * swing) * 0.032 if swing < 1.0 else 0.0
	var pull := 0.0
	var tilt := 0.0
	if core != null and core.charging >= 0:
		var cs := shots[core.charging]
		pull = -0.03 * clampf((t_ms - cs.t) / maxf(cs.end - cs.t, 1.0), 0.0, 1.0)
	var pp := _p(Vector2(RallyChart.X_PLAYER - 0.012 + fwd + pull, py))
	_draw_figure(Vector2(0.065 * w, FLOOR_Y * h), pp, COL_ME, 1.0)
	tilt = -0.5 + 0.9 * swing if swing < 1.0 else -0.25
	_draw_paddle(pp, tilt, COL_ME, 1.0)
	# Gegner: schlaegt zur Mitte der Flugzeit zurueck.
	var oy := RallyChart.Y_OPP
	var ofwd := 0.0
	var j := RallyChart.first_at_or_after(shots, t_ms - 120.0)
	for k in range(maxi(j - 1, 0), mini(j + 2, shots.size())):
		var u := (t_ms - shots[k].m + 50.0) / 170.0
		if u >= 0.0 and u <= 1.0:
			ofwd = -sin(PI * u) * 0.034
	var op := _p(Vector2(RallyChart.X_OPP + 0.012 + ofwd, oy))
	_draw_figure(Vector2(0.935 * w, FLOOR_Y * h), op, COL_OPP, -1.0)
	_draw_paddle(op, PI + 0.25 - (0.5 if ofwd < -0.002 else 0.0), COL_OPP, -1.0)


func _draw_figure(foot: Vector2, hand: Vector2, col: Color, dir: float) -> void:
	var h := size.y
	var body_top := foot + Vector2(0.0, -0.40 * h)
	var shoulder := body_top + Vector2(0.0, 0.04 * h)
	var wd := 0.034 * h
	draw_rect(Rect2(foot.x - wd, body_top.y, wd * 2.0, foot.y - body_top.y), Color(col, 0.55))
	draw_circle(body_top + Vector2(0, 0.0), wd, Color(col, 0.55))
	draw_circle(foot + Vector2(0, -0.455 * h), 0.036 * h, col)
	draw_line(shoulder + Vector2(dir * wd * 0.4, 0), hand, col, 0.014 * h, true)


func _draw_paddle(c: Vector2, ang: float, col: Color, dir: float) -> void:
	var r := 0.033 * size.y
	var d := Vector2(cos(ang), sin(ang)) * dir
	draw_line(c, c - d * r * 1.7 * dir, Color(col, 0.7), 0.008 * size.y, true)
	draw_circle(c, r, col.darkened(0.55))
	draw_circle(c, r * 0.86, col)


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
			var r := BALL_R * size.y * 1.9
			draw_arc(c, r, 0.0, TAU, 40, Color(key_col(s.key), 0.25), 3.0, true)
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * prog, 40, Color(key_col(s.key), 0.95), 4.0, true)
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
	# Schatten auf dem Tisch.
	var tx0 := RallyChart.X_TABLE_L * size.x
	var tx1 := RallyChart.X_TABLE_R * size.x
	var ty := RallyChart.Y_TABLE * size.y
	var hgt := clampf((ty - pos.y) / (size.y * 0.5), 0.0, 1.0)
	if pos.x > tx0 and pos.x < tx1 and pos.y < ty + 2.0:
		draw_set_transform(Vector2(pos.x, ty + 1.0), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, r * (1.2 - 0.4 * hgt), Color(0, 0, 0, 0.38 * alpha * (1.0 - 0.6 * hgt)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Schweif: wenige schwindende Punkte entlang der echten Bahn.
	for i in range(TRAIL_N, 0, -1):
		var tt := t_now - float(i) * TRAIL_STEP_MS
		if tt < t_from:
			continue
		var q := 1.0 - float(i) / float(TRAIL_N + 1)
		draw_circle(_p(fn.call(tt)), r * (0.35 + 0.5 * q), Color(col, 0.22 * q * alpha))
	if smash:
		draw_circle(pos, r + 3.5, Color(COL_SMASH, 0.95 * alpha))
	draw_circle(pos, r, Color(col.lightened(0.12), alpha))
	draw_arc(pos, r, 0.0, TAU, 24, Color(0, 0, 0, 0.35 * alpha), 1.5, true)


# ---------------------------------------------------------------------------
# Effekte (kurz, < 200 ms)
# ---------------------------------------------------------------------------

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
				var big := 1.6 if bool(f.smash) else 1.0
				var rr := r0 * (1.4 + 2.6 * big * e)
				if bool(f.smash):
					draw_arc(c, rr + 3.0, 0.0, TAU, 40, Color(COL_SMASH, 1.0 - u), 5.0, true)
				draw_arc(c, rr, 0.0, TAU, 40, Color(col, 1.0 - u), 3.5, true)
				var n := 10 if bool(f.smash) else 7
				for i in n:
					var ang := TAU * float(i) / float(n) + 0.3
					var d := Vector2(cos(ang), sin(ang))
					draw_line(c + d * (rr * 0.75), c + d * (rr * 0.75 + r0 * (1.1 - u)),
							Color(col.lerp(Color.WHITE, 0.4), 1.0 - u), 2.5, true)
			"release":
				draw_arc(c, r0 * (1.6 + 1.6 * e), 0.0, TAU, 40, Color(col, 1.0 - u), 3.0, true)
			"miss":
				var d := r0 * 0.9
				var col2 := Color(COL_MISS, 1.0 - u)
				var cc := c + Vector2(0, -u * r0 * 1.2)
				draw_line(cc + Vector2(-d, -d), cc + Vector2(d, d), col2, 3.0, true)
				draw_line(cc + Vector2(-d, d), cc + Vector2(d, -d), col2, 3.0, true)
	_fx = keep
	# Aufpralle auf dem Tisch: flache Ringe.
	var j := RallyChart.first_at_or_after(shots, t_ms - 200.0)
	for k in range(maxi(j - 2, 0), mini(j + 2, shots.size())):
		var tb := RallyChart.bounce_me_time(shots, k)
		_bounce_ring(tb, RallyChart.pos_in(shots, k, tb).x)
		if _result_hit(k) == 1:
			var to := RallyChart.bounce_opp_time(shots, k)
			_bounce_ring(to, RallyChart.pos_out(shots, k, to).x)


func _bounce_ring(tb: float, x: float) -> void:
	var u := (t_ms - tb) / 150.0
	if u < 0.0 or u > 1.0:
		return
	var ty := RallyChart.Y_TABLE * size.y
	draw_set_transform(Vector2(x * size.x, ty), 0.0, Vector2(1.0, 0.2))
	draw_arc(Vector2.ZERO, size.y * (0.012 + 0.03 * u), 0.0, TAU, 24, Color(1, 1, 1, 0.45 * (1.0 - u)), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
