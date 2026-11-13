class_name TraceView
extends Control

## Trace: Darstellung des Fadens (nur Zeichnen, keine Wertung).
## Welt in px, Kamera = TracePath.camera(t) (zustandslos), Kopf etwa Bildmitte. Der Weg
## voraus ist fein vorgezeichnet; jeder Knoten hat Pfeil(e) in Spaltenfarbe und einen
## Annaeherungsring, der bis zur Notenzeit schrumpft. Gespielte Strecke leuchtet in
## Spaltenfarbe nach, Miss = grauer, ausgefranster Faden. Holds: dicker, leuchtender
## Streifen bis zur Loslass-Marke. Am Ende zoomt `end_zoom` (0..1) auf das ganze Bild.

const INK := Color(0.045, 0.052, 0.07)
const THREAD := Color(0.86, 0.90, 0.97)
const GRAY := Color(0.55, 0.57, 0.62)
const HEAD := Color(0.97, 0.96, 0.92)
const APPROACH_MS := 640.0
const TRAIL_PX := 820.0
const FLASH_MS := 340.0
const ARROW_FADE_MS := 240.0
const GRID := 140.0
const RING_NEAR := 24.0
const RING_FAR := 42.0
const WRONG_MS := 900.0
const DOT_GAP := 16.0                ## Abstand der Vorlauf-Punkte (Welt-px)
const JUDGE_COL := [
	Color(0.80, 0.93, 1.0), Color(1.0, 0.86, 0.45), Color(0.55, 0.85, 0.55),
	Color(0.50, 0.70, 0.95), Color(0.78, 0.60, 0.95), Color(0.55, 0.555, 0.57),
]
const WRONG_COL := Color(0.92, 0.30, 0.28)
## End-Zeitraffer: end_zoom 0..1 = Auszoomen (0..0.2), Neuzeichnen (0.2..0.85), Einpassen (0.85..1).
const END_OUT := 0.2
const END_DRAW := 0.85
const END_ZOOM_FIT := 0.9

var path: TracePath
var core: ManiaCore
var note_colors: Array[Color] = []
var t_ms := 0.0
var end_zoom := 0.0
var key_labels := PackedStringArray()   ## je Spalte der Tastenbuchstabe (Spiel setzt sie, sonst Settings)
var mods := {}                          ## TraceMods.from_session(): HD/SS duennen den Vorlauf, MR spiegelt

var _hit_t := PackedFloat64Array()   ## je Note: Zeit des Kopf-Urteils (Sicht-ms), -1 = offen
var _hit_q := PackedInt32Array()
var _done := PackedByteArray()       ## je Note: 1 = Hold zu Ende gewertet / Tap gewertet
var _live := {}                      ## Hold-Note -> true solange gehalten
var _gray: Array = []                ## [s0, s1]: graue (verpasste) Abschnitte
var _frays: Array = []               ## { s, seed }
var _wrongs: Array = []              ## { t, s, seed }: falsche Abbiegung (Sicht-ms)
var _mirror := false
var _holds: Array = []               ## { note, col, s0, s1, t0, t1, k }
var _cam := Vector2.ZERO
var _sz := 1.0                       ## Welt -> Schirm
var _ctr := Vector2.ZERO


func setup(p: TracePath, c: ManiaCore, colors: Array[Color]) -> void:
	path = p
	core = c
	note_colors = colors
	var n := p.note_knot.size()
	_hit_t.resize(n)
	_hit_t.fill(-1.0)
	_hit_q.resize(n)
	_hit_q.fill(-1)
	_done.resize(n)
	_done.fill(0)
	mods = TraceMods.from_session()
	_mirror = TraceMods.has(mods, "MR")
	if key_labels.is_empty():
		# Settings ueber den Baum holen: Tests laden die Ansicht ohne Autoloads.
		var st: Node = get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
		var keys: Array = []
		if st != null:
			keys = st.get("trace_keys") if st.get("trace_keys") != null else st.get("key_lanes")
		for i in 4:
			key_labels.append(UiTheme.key_short(int(keys[i])).to_upper() if i < keys.size() else ["←", "↓", "↑", "→"][i])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for j in p.knots.size():
		var kn := p.knots[j]
		for h in kn.holds:
			_holds.append({
				"note": int(h.note), "col": int(h.col), "s0": kn.s, "s1": float(h.s_end),
				"t0": kn.t, "t1": float(h.t_end), "k": j,
			})


func _col(note: int) -> Color:
	return note_colors[note] if note >= 0 and note < note_colors.size() else THREAD


## Urteil eines Kopfes/Taps/Hold-Endes (aus note_judged).
func on_judged(index: int, result: Dictionary) -> void:
	if path == null or index < 0 or index >= _hit_t.size():
		return
	var q := int(result.get("quality", 5))
	var kn := path.knots[path.note_knot[index]]
	if bool(result.get("hold_end", false)):
		_live.erase(index)
		_done[index] = 1
		if q == 5:
			var s_end := kn.s
			for h in kn.holds:
				if int(h.note) == index:
					s_end = float(h.s_end)
			var s_now := clampf(path.s_at(t_ms), kn.s, s_end)
			_gray.append([s_now, s_end])
			_frays.append({"s": s_now, "seed": index * 3 + 1})
		return
	_hit_t[index] = t_ms
	_hit_q[index] = q
	_done[index] = 1
	if q == 5:
		var j := path.note_knot[index]
		var s1 := kn.s + TracePath.MIN_SEG
		if j + 1 < path.knots.size():
			s1 = path.knots[j + 1].s
		_gray.append([kn.s, s1])
		_frays.append({"s": kn.s, "seed": index * 3})


func on_hold_start(index: int, quality: int) -> void:
	if index < 0 or index >= _hit_t.size():
		return
	_hit_t[index] = t_ms
	_hit_q[index] = quality
	_live[index] = true


## Falsche Taste am Knick der Note idx: Faden franst kurz rot aus.
func on_wrong_turn(idx: int) -> void:
	if path == null or idx < 0 or idx >= path.note_knot.size():
		return
	var kn := path.knots[path.note_knot[idx]]
	_wrongs.append({"t": t_ms, "s": kn.s, "seed": idx * 7 + 5})


func _w2s(p: Vector2) -> Vector2:
	var v := (p - _cam) * _sz
	if _mirror:
		v.x = -v.x
	return _ctr + v


## Pfeilrichtung (Welt) -> Schirm, bei Mirror gespiegelt.
func _dir(col: int) -> Vector2:
	var d := TracePath.dir_of_col(col)
	return Vector2(-d.x, d.y) if _mirror else d


static func _hash(a: int, b: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453, 1.0)


## Ruhige Kamera: gewichtetes Mittel des Ziels ueber ~1 s, ohne Zustand (Seek/Replay-sicher).
## Haarnadeln lassen das Ziel springen, das lange Fenster glaettet das aus.
## Darueber TraceRules.fair_camera: Kopf und die Knoten der naechsten 600 ms bleiben im Bild.
## Gilt fuer jede Ansicht (Spiel, Tutorial, Clips), nicht nur fuer das Spiel.
func _camera(t: float) -> Vector2:
	return TraceRules.fair_camera(path, t, _calm_camera(t), TraceRules.view_half(size))


func _calm_camera(t: float) -> Vector2:
	var acc := Vector2.ZERO
	var wsum := 0.0
	for i in 22:
		var w := exp(-float(i) * 0.045 / 0.32)
		acc += path.camera_target(t - float(i) * 45.0, 0.2) * w
		wsum += w
	var c := acc / wsum
	# Kopf bleibt sicher im Bild.
	var head := path.head_pos(t)
	var lim := Vector2(size.x * 0.26, size.y * 0.26) / maxf(size.y / 720.0, 0.1)
	return Vector2(clampf(c.x, head.x - lim.x, head.x + lim.x), clampf(c.y, head.y - lim.y, head.y + lim.y))


func _draw() -> void:
	if path == null or path.knots.is_empty():
		return
	var vs := size
	var sc := vs.y / 720.0
	_ctr = vs * 0.5
	var u := clampf(end_zoom, 0.0, 1.0)
	var cam_play := _camera(t_ms)
	var zoom := 1.0
	_cam = cam_play
	var cur_s := path.s_at(t_ms)
	var s_b := path.s_at(t_ms + TracePath.LOOK_S * 1000.0)
	var s_a := cur_s - TRAIL_PX
	var first_s := path.knots[0].s - 90.0
	var last_s := path.knots[path.knots.size() - 1].s + 90.0
	var head_p := path.head_pos(t_ms)
	var redraw := u > END_OUT
	var fin := 0.0
	if u > 0.0:
		var b := path.bounds()
		var fit := minf(vs.x * 0.84 / maxf(b.size.x, 1.0), vs.y * 0.78 / maxf(b.size.y, 1.0)) / sc
		fit = minf(fit, 1.0)
		var zin := _smooth(u / END_OUT)
		fin = _smooth((u - END_DRAW) / (1.0 - END_DRAW))
		var lz := lerpf(lerpf(0.0, log(fit * END_ZOOM_FIT), zin), log(fit), fin)
		zoom = exp(lz)
		_cam = cam_play.lerp(b.get_center(), zin)
		if redraw:
			var tl := clampf((u - END_OUT) / (END_DRAW - END_OUT), 0.0, 1.0)
			tl = lerpf(tl, _smooth(tl), 0.35)
			cur_s = lerpf(first_s, last_s, tl)
			s_a = first_s
			s_b = cur_s + 40.0
			head_p = path.pos_at(cur_s)
		else:
			s_a = lerpf(s_a, first_s, zin)
			s_b = lerpf(s_b, last_s, zin)
	_sz = sc * zoom
	var wf := sc * pow(zoom, 0.5)   # Linienstaerke: schrumpft weniger als die Welt
	var step := clampf(5.0 / maxf(_sz, 0.05), 6.0, 60.0)
	var floor_a := lerpf(0.12, 0.9, _smooth(u / END_OUT))
	_draw_grid(vs)
	_draw_holds(cur_s, s_a, s_b, wf, step)
	if u <= 0.0:
		_draw_upcoming(cur_s, s_b, wf)
	_draw_played(cur_s, s_a, floor_a, wf, step)
	_draw_frays(s_a, s_b, wf)
	if zoom > 0.5:
		_draw_knots(s_a, s_b, zoom, wf)
	else:
		_draw_dots(s_a, s_b, wf)
	_draw_wrong(wf)
	_draw_head(head_p, wf, fin, redraw)


static func _smooth(x: float) -> float:
	var v := clampf(x, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


func _draw_grid(vs: Vector2) -> void:
	var sp := GRID
	while sp * _sz < 34.0:
		sp *= 2.0
	var half := vs * 0.5 / _sz
	var x0 := floorf((_cam.x - half.x) / sp) * sp
	var y0 := floorf((_cam.y - half.y) / sp) * sp
	var nx := int(ceil(half.x * 2.0 / sp)) + 2
	var ny := int(ceil(half.y * 2.0 / sp)) + 2
	var col := Color(THREAD, 0.07)
	var r := maxf(1.3, 1.9 * vs.y / 720.0)
	for ix in nx:
		for iy in ny:
			draw_circle(_w2s(Vector2(x0 + ix * sp, y0 + iy * sp)), r, col)


func _pts_screen(s0: float, s1: float, step: float) -> PackedVector2Array:
	var w := path.sample(s0, s1, step)
	for i in w.size():
		w[i] = _w2s(w[i])
	return w


## Vorlauf: fein gepunkteter Weg, nach vorn blasser (Mods duennen ihn aus).
func _draw_upcoming(cur_s: float, s_b: float, wf: float) -> void:
	if s_b <= cur_s:
		return
	var span := s_b - cur_s
	var look := TracePath.LOOK_S * 1000.0
	var s := ceilf(cur_s / DOT_GAP) * DOT_GAP
	var r := 1.5 * wf + 0.3
	var cover: Array = []
	for h in _holds:
		if float(h.s1) >= cur_s and float(h.s0) <= s_b:
			cover.append(h)
	while s < s_b:
		var f := (s - cur_s) / span
		var a := 0.62 * pow(1.0 - f, 0.9) * clampf((s - cur_s) / 50.0, 0.0, 1.0)
		a *= TraceMods.path_alpha(look * f, mods)
		for h in cover:
			if s >= float(h.s0) and s <= float(h.s1):
				a = 0.0
		if a > 0.02:
			draw_circle(_w2s(path.pos_at(s)), r, Color(THREAD, a))
		s += DOT_GAP


## Gespielter Faden: je Knoten-Abschnitt in Spaltenfarbe (Miss: grau), hinten blasser.
func _draw_played(cur_s: float, s_a: float, floor_a: float, wf: float, step: float) -> void:
	var kn_n := path.knots.size()
	var j0 := maxi(path.first_knot_from_s(s_a) - 1, -1)
	var span := maxf(cur_s - s_a, 1.0)
	# Strecke vor dem ersten Knoten: neutraler Faden.
	var first_s := path.knots[0].s
	if s_a < first_s:
		_trail(s_a, minf(first_s, cur_s), THREAD.darkened(0.15), 0.8, cur_s, span, floor_a, wf, step)
	for j in range(maxi(j0, 0), kn_n):
		var kn := path.knots[j]
		if kn.s > cur_s:
			break
		var s1 := cur_s
		if j + 1 < kn_n:
			s1 = minf(path.knots[j + 1].s, cur_s)
		var s0 := maxf(kn.s, s_a)
		if s1 <= s0:
			continue
		if _knot_missed(kn):
			continue
		_trail(s0, s1, _col(kn.notes[0]), 1.0, cur_s, span, floor_a, wf, step)
	for g in _gray:
		var g0 := maxf(float(g[0]), s_a)
		var g1 := minf(float(g[1]), cur_s)
		if g1 > g0:
			_trail(g0, g1, GRAY, 0.55, cur_s, span, floor_a, wf, step, true)


func _knot_missed(kn: TracePath.Knot) -> bool:
	for n in kn.notes:
		if _hit_q[n] == 5:
			return true
	return false


func _trail(s0: float, s1: float, col: Color, a: float, cur_s: float, span: float, floor_a: float,
		wf: float, step: float, frayed := false) -> void:
	var pts := _pts_screen(s0, s1, step)
	var n := pts.size()
	if n < 2:
		return
	var fs := PackedFloat32Array()
	for i in n:
		var s := s0 + (s1 - s0) * float(i) / float(n - 1)
		fs.append(clampf(1.0 - (cur_s - s) / span, floor_a, 1.0))
	if frayed:
		var cg := PackedColorArray()
		for i in n:
			cg.append(Color(col, 0.55 * a * fs[i]))
		draw_polyline_colors(pts, cg, 2.4 * wf, true)
		return
	# Tiefe: aeltere Strecke dunkler und schmaler. Weiche Baender (Rand-Alpha 0) statt Linien.
	var core_col := col.lerp(Color.WHITE, 0.55)
	var wk := PackedFloat32Array()
	var dk := PackedColorArray()
	var dk_core := PackedColorArray()
	for i in n:
		wk.append(lerpf(0.5, 1.0, fs[i]))
		dk.append(col.darkened(0.5 * (1.0 - fs[i])))
		dk_core.append(core_col.darkened(0.5 * (1.0 - fs[i])))
	var nr := _normals(pts)
	# [halbe Breite, Feder, Alpha, Kern]
	_ribbon(pts, nr, wk, fs, dk, wf * 10.0, wf * 9.0, 0.07 * a)
	_ribbon(pts, nr, wk, fs, dk, wf * 3.6, wf * 4.5, 0.2 * a)
	_ribbon(pts, nr, wk, fs, dk, wf * 2.3, wf * 1.1, 0.93 * a)
	_ribbon(pts, nr, wk, fs, dk_core, wf * 0.8, wf * 0.7, 0.9 * a)


func _normals(pts: PackedVector2Array) -> PackedVector2Array:
	var nr := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		d = d.normalized() if d.length() > 0.001 else Vector2.RIGHT
		nr.append(Vector2(-d.y, d.x))
	return nr


## Band mit Breite je Punkt (w * wk), vollem Kern und weichem Rand (Alpha -> 0 ueber `feather`).
func _ribbon(pts: PackedVector2Array, nr: PackedVector2Array, wk: PackedFloat32Array, fs: PackedFloat32Array,
		cols: PackedColorArray, w: float, feather: float, alpha: float) -> void:
	var n := pts.size()
	var prev: PackedVector2Array
	var prev_c: PackedColorArray
	for i in n:
		var ww := w * wk[i]
		var c := cols[i]
		var cc := Color(c, alpha * fs[i])
		var c0 := Color(c, 0.0)
		var v := PackedVector2Array([pts[i] - nr[i] * (ww + feather), pts[i] - nr[i] * ww,
				pts[i] + nr[i] * ww, pts[i] + nr[i] * (ww + feather)])
		var vc := PackedColorArray([c0, cc, cc, c0])
		if i > 0:
			for k in 3:
				draw_primitive(PackedVector2Array([prev[k], prev[k + 1], v[k + 1], v[k]]),
						PackedColorArray([prev_c[k], prev_c[k + 1], vc[k + 1], vc[k]]), PackedVector2Array())
		prev = v
		prev_c = vc


func _draw_holds(cur_s: float, s_a: float, s_b: float, wf: float, step: float) -> void:
	for h in _holds:
		var s0: float = h.s0
		var s1: float = h.s1
		if s1 < s_a or s0 > s_b:
			continue
		var note: int = h.note
		var col := _col(note)
		var missed := _hit_q[note] == 5
		var started := _hit_t[note] >= 0.0 and not missed
		var a0 := maxf(s0, s_a)
		var a1 := minf(s1, s_b)
		if a1 <= a0:
			continue
		var pts := _pts_screen(a0, a1, step)
		draw_polyline(pts, Color(INK, 0.55), 17.0 * wf, true)
		if missed:
			draw_polyline(pts, Color(GRAY, 0.35), 11.0 * wf, true)
		else:
			draw_polyline(pts, Color(col.darkened(0.08), 0.74), 11.0 * wf, true)
			if started and cur_s > a0:
				var lit := _pts_screen(a0, minf(a1, cur_s), step)
				draw_polyline(lit, Color(col.lightened(0.12), 0.97), 11.0 * wf, true)
				draw_polyline(lit, Color(1, 1, 1, 0.55), 3.0 * wf, true)
		if s1 <= s_b:
			_end_mark(s1, col, missed, wf)


func _end_mark(s: float, col: Color, missed: bool, wf: float) -> void:
	var p := _w2s(path.pos_at(s))
	var a := path.angle_at(s)
	var nrm := Vector2(-sin(a), cos(a))
	var c := GRAY if missed else col.lightened(0.25)
	draw_line(p - nrm * 15.0 * wf, p + nrm * 15.0 * wf, Color(INK, 0.8), 6.0 * wf, true)
	draw_line(p - nrm * 14.0 * wf, p + nrm * 14.0 * wf, Color(c, 0.95), 3.2 * wf, true)


func _draw_frays(s_a: float, s_b: float, wf: float) -> void:
	for fr in _frays:
		var s: float = fr.s
		if s < s_a - 40.0 or s > s_b + 40.0:
			continue
		var base := _w2s(path.pos_at(s))
		var a := path.angle_at(s)
		var seed_i: int = fr.seed
		for i in 8:
			var ang := a + (_hash(seed_i, i) - 0.5) * 2.5
			var ln := (10.0 + 20.0 * _hash(seed_i, i + 20)) * wf
			var off := (_hash(seed_i, i + 40) - 0.5) * 8.0 * wf
			var p0 := base + Vector2(-sin(a), cos(a)) * off
			var p1 := p0 + Vector2(cos(ang), sin(ang)) * ln
			draw_line(p0, p1, Color(GRAY, 0.75), 1.3 * wf, true)
		draw_circle(base, 3.2 * wf, Color(GRAY, 0.9))


## Falsche Abbiegung: kurze rote Fasern am Knick, dezenter Text.
func _draw_wrong(wf: float) -> void:
	for w in _wrongs:
		var age: float = t_ms - float(w.t)
		if age < 0.0 or age > WRONG_MS:
			continue
		var k := age / WRONG_MS
		var fade := 1.0 - k
		var s: float = w.s
		var base := _w2s(path.pos_at(s))
		var a := path.angle_at(s)
		var nrm := Vector2(-sin(a), cos(a))
		var sd: int = w.seed
		var grow := minf(1.0, age / 120.0)
		for i in 11:
			var ang := a + (_hash(sd, i) - 0.5) * 2.9
			var ln := (10.0 + 26.0 * _hash(sd, i + 20)) * wf * grow * (1.0 - 0.4 * k)
			var p0 := base + nrm * (_hash(sd, i + 40) - 0.5) * 9.0 * wf
			var p1 := p0 + Vector2(cos(ang), sin(ang)) * ln
			draw_line(p0, p1, Color(WRONG_COL, 0.8 * fade), 1.3 * wf, true)
		draw_arc(base, 5.0 * wf, 0.0, TAU, 16, Color(WRONG_COL, 0.6 * fade), 1.4 * wf, true)
		var font := ThemeDB.fallback_font
		var fsz := int(round(13.0 * wf))
		var txt := tr("WRONG TURN")
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var tp := base + Vector2(-tw * 0.5, -30.0 * wf - 10.0 * k * wf)
		draw_string(font, tp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(INK, 0.6 * fade))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(WRONG_COL.lightened(0.2), 0.8 * fade))


func _draw_dots(s_a: float, s_b: float, wf: float) -> void:
	var j0 := path.first_knot_from_s(s_a)
	var j1 := path.first_knot_from_s(s_b)
	for j in range(j0, mini(j1 + 1, path.knots.size())):
		var kn := path.knots[j]
		if _knot_missed(kn):
			continue
		draw_circle(_w2s(kn.pos), 2.2 * wf + 0.6, _col(kn.notes[0]).lightened(0.2))


func _draw_knots(s_a: float, s_b: float, zoom: float, wf: float) -> void:
	var j0 := maxi(path.first_knot_from_s(s_a - 60.0), 0)
	var j1 := mini(path.first_knot_from_s(s_b + 60.0) + 1, path.knots.size())
	var next_open := -1
	for j in range(j0, j1):
		var kn := path.knots[j]
		var open := false
		for n in kn.notes:
			if _hit_t[n] < 0.0:
				open = true
		if open and next_open < 0 and kn.t >= t_ms - 200.0:
			next_open = j
	for j in range(j0, j1):
		_draw_knot(path.knots[j], j == next_open, wf)


func _draw_knot(kn: TracePath.Knot, is_next: bool, wf: float) -> void:
	var p := _w2s(kn.pos)
	var dt := kn.t - t_ms
	var open := false
	var any_hit := false
	for n in kn.notes:
		if _hit_t[n] < 0.0:
			open = true
		elif _hit_q[n] != 5:
			any_hit = true
	var look := TracePath.LOOK_S * 1000.0
	var fade_in := clampf((look - dt) / 260.0, 0.0, 1.0)
	var zs := _sz
	if open:
		# Annaeherungsring: schrumpft bis zur Notenzeit.
		var frac := clampf(dt / APPROACH_MS, 0.0, 1.0)
		var base_col := _col(kn.notes[0])
		if dt < APPROACH_MS and dt > -140.0:
			var r := lerpf(RING_NEAR, RING_FAR, frac) * zs
			var a := (0.34 + 0.6 * (1.0 - frac)) * fade_in
			if is_next:
				a = minf(1.0, a + 0.2)
			draw_arc(p, RING_NEAR * zs, 0.0, TAU, 48, Color(base_col, 0.22 * fade_in * (1.0 - frac * 0.6)), 1.2 * wf, true)
			draw_arc(p, r, 0.0, TAU, 48, Color(INK, a * 0.55), 4.2 * wf, true)
			draw_arc(p, r, 0.0, TAU, 48, Color(base_col.lightened(0.15), a), 2.2 * wf, true)
		# Knoten-Punkt + Pfeile.
		draw_circle(p, 4.4 * wf, Color(INK, 0.8 * fade_in))
		draw_circle(p, 2.8 * wf, Color(THREAD, 0.95 * fade_in))
		var chord := kn.notes.size() > 1
		for i in kn.notes.size():
			var n: int = kn.notes[i]
			if _hit_t[n] >= 0.0:
				continue
			var grow := 1.0 + 0.2 * (1.0 - frac) if is_next or dt < APPROACH_MS else 1.0
			_arrow(p, _dir(kn.cols[i]), chord, _col(n), fade_in, grow, kn.cols[i])
	# Treffer-Leuchten und ausblendender Pfeil.
	for i in kn.notes.size():
		var n: int = kn.notes[i]
		var ht := _hit_t[n]
		if ht < 0.0 or _hit_q[n] == 5:
			continue
		var age := t_ms - ht
		var col := _col(n)
		if age < ARROW_FADE_MS:
			var fa := 1.0 - age / ARROW_FADE_MS
			_arrow(p, _dir(kn.cols[i]), kn.notes.size() > 1, col, fa, 1.0 + 0.3 * (1.0 - fa), kn.cols[i])
		if age < FLASH_MS:
			var u := age / FLASH_MS
			var inv := 1.0 - u
			var jc: Color = JUDGE_COL[clampi(_hit_q[n], 0, 5)]
			draw_circle(p, (14.0 + 16.0 * u) * zs, Color(jc, 0.2 * inv * inv))
			draw_arc(p, (RING_NEAR * 0.7 + 26.0 * u) * zs, 0.0, TAU, 48, Color(jc, 0.9 * inv), 2.8 * wf * inv + 0.6, true)
	if any_hit and not open:
		draw_circle(p, 3.0 * wf + 0.4, Color(_col(kn.notes[0]).lightened(0.2), 0.85))


## Pfeilspitze in Richtung d (Welt) mit Tastenbuchstabe, bei Akkord seitlich zum Rand verschoben.
func _arrow(p: Vector2, d: Vector2, chord: bool, col: Color, alpha: float, grow: float, lane := -1) -> void:
	if alpha <= 0.01:
		return
	var u := _sz * grow
	var c := p + d * (24.0 * u if chord else 0.0)
	var perp := Vector2(-d.y, d.x)
	var tip := c + d * 19.0 * u
	var wl := c - d * 11.0 * u + perp * 17.0 * u
	var wr := c - d * 11.0 * u - perp * 17.0 * u
	var notch := c - d * 3.0 * u
	var poly := PackedVector2Array([tip, wl, notch, wr])
	var line := PackedVector2Array([tip, wl, notch, wr, tip])
	var fill := col.lightened(0.06)
	draw_colored_polygon(poly, Color(fill, alpha))
	draw_polyline(line, Color(INK, 0.8 * alpha), 2.4 * maxf(u, 0.6), true)
	if lane >= 0 and lane < key_labels.size() and u > 0.5:
		var font := ThemeDB.fallback_font
		var fsz := int(round(15.0 * u))
		var txt := key_labels[TraceMods.map_column(lane, mods)]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		var tc := c + d * 1.5 * u
		for ox in [0.0, 0.7]:
			draw_string(font, tc + Vector2(-tw * 0.5 + ox, fsz * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz,
					Color(INK, 0.95 * alpha))


func _draw_head(p0: Vector2, wf: float, fin: float, racing: bool) -> void:
	var p := _w2s(p0)
	var r := 6.0 * wf
	var fa := 1.0 - fin
	draw_circle(p, r * 4.2, Color(HEAD, 0.07 * fa))
	draw_circle(p, r * 2.6, Color(HEAD, 0.14 * fa))
	draw_circle(p, r * 1.5, Color(INK, 0.85 * fa))
	draw_circle(p, r, Color(HEAD, fa))
	if not racing:
		draw_arc(p, r * 1.9, 0.0, TAU, 32, Color(HEAD, 0.55 * fa), 1.4 * wf, true)
