class_name TraceView
extends Control

## Trace: Darstellung des Fadens (nur Zeichnen, keine Wertung).
## Welt in px, Kamera = TracePath.camera(t) (zustandslos), Kopf etwa Bildmitte. Der Weg
## voraus ist fein vorgezeichnet; jeder Knoten hat Pfeil(e) in Spaltenfarbe und einen
## Annaeherungsring, der bis zur Notenzeit schrumpft. Gespielte Strecke leuchtet in
## Spaltenfarbe nach, Miss = grauer, ausgefranster Faden. Holds: dicker, leuchtender
## Streifen bis zur Loslass-Marke. Am Ende zoomt `end_zoom` (0..1) auf das ganze Bild.
##
## Tiefe: die Welt liegt als leicht geneigter Boden im Bild (`_tilt`). Die Abbildung zieht
## nur zur Bildmitte zusammen (unten Faktor 1, oben kleiner), darum liegt alles, was die
## flache Kamera im Bild hat (TraceRules.fair_camera), auch geneigt im Bild.
## Musik: Takt und Kiai kommen ohne Zustand aus den Timing-Punkten der Map (Seek-sicher):
## Bodenlinien, Staub-Ebenen, Lichtwelle am Taktanfang, Kiai mit Bernstein-Licht und mehr Tiefe.
## Bewusst ohne Ringe: Licht laeuft nur ueber Linien (Bodenlinien, Bahn). Der einzige Kreis
## ist der Anflugring des naechsten Knotens.

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
const AMBER := Color(1.0, 0.74, 0.32)
const TILT := 0.24                   ## Boden-Neigung: oben 1/(1+TILT) so gross wie unten
const TILT_KIAI := 0.10              ## im Kiai kommt so viel dazu
const KIAI_IN_MS := 600.0
const KIAI_OUT_MS := 900.0
const GLINT_MS := 320.0              ## Glanz nach einem Treffer laeuft so lange voraus
const GLINT_PX := 250.0
const MILE_MS := 900.0               ## Kombo-Meilenstein: Bodenlinien kurz in Bernstein
const WAVE_PX := 1000.0              ## Lichtwelle am Taktanfang laeuft so weit ueber den Boden
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
var _tilt := 0.0                     ## Neigung dieses Bildes (0 = flach)
var _kx := 0.0                       ## Kiai-Anteil 0..1 dieses Bildes
var _env := 0.0                      ## Takt-Huellkurve 0..1 dieses Bildes
var _cur_s := 0.0
var _s_b := 0.0
var _red_t := PackedFloat64Array()   ## rote Timing-Punkte: Zeit, Beat-Laenge, Takt
var _red_len := PackedFloat64Array()
var _red_meter := PackedInt32Array()
var _kiai: Array[Vector2] = []       ## Kiai-Abschnitte (Start, Ende), kurze Luecken geschlossen
var _mile_t := -1.0e9                ## Sicht-ms des letzten Kombo-Meilensteins
var _mile_combo := 0
var _mile := 0.0                     ## Meilenstein-Anteil 0..1 dieses Bildes
var _wave_c := Vector2.ZERO          ## Lichtwelle: Ursprung (Welt), Radius, Staerke
var _wave_r := 0.0
var _wave_a := 0.0


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
	_read_timing(c.beatmap if c != null else null)
	for j in p.knots.size():
		var kn := p.knots[j]
		for h in kn.holds:
			_holds.append({
				"note": int(h.note), "col": int(h.col), "s0": kn.s, "s1": float(h.s_end),
				"t0": kn.t, "t1": float(h.t_end), "k": j,
			})


## Takt und Kiai der Map merken. Sehr schnelle Beats zaehlen doppelt lang (kein Flimmern).
func _read_timing(bm: Beatmap) -> void:
	_red_t.clear()
	_red_len.clear()
	_red_meter.clear()
	_kiai.clear()
	if bm == null:
		return
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			var bl := float(tp.beat_length)
			while bl < 280.0:
				bl *= 2.0
			_red_t.append(tp.time)
			_red_len.append(bl)
			_red_meter.append(clampi(tp.meter, 1, 12))
	var all: Array[Vector2] = []
	for iv in bm.kiai_intervals:
		var a := float(iv.start)
		var b := float(iv.end)
		if not all.is_empty() and a - all[-1].y < 1500.0:
			all[-1] = Vector2(all[-1].x, maxf(all[-1].y, b))
		elif b > a:
			all.append(Vector2(a, b))
	# Kurze Kiai-Blitze sind kein eigener Moment.
	for v in all:
		if v.y - v.x >= 2000.0:
			_kiai.append(v)


## Takt zur Zeit t: x = Huellkurve (1 am Beat, faellt ab), y = ms seit Taktanfang (-1 = kein
## Takt bekannt), z = Beat-Laenge in ms.
func _beat_at(t: float) -> Vector3:
	if _red_t.is_empty():
		return Vector3(0.0, -1.0, 0.0)
	var i := 0
	while i + 1 < _red_t.size() and _red_t[i + 1] <= t:
		i += 1
	var bl := _red_len[i]
	var rel := t - _red_t[i]
	return Vector3(exp(-4.0 * fposmod(rel, bl) / bl), fposmod(rel, bl * float(_red_meter[i])), bl)


## Kiai-Anteil 0..1 zur Zeit t, weich ein und aus.
func _kiai_at(t: float) -> float:
	var k := 0.0
	for iv in _kiai:
		if t < iv.x or t > iv.y + KIAI_OUT_MS:
			continue
		k = maxf(k, _smooth((t - iv.x) / KIAI_IN_MS) * (1.0 - _smooth((t - iv.y) / KIAI_OUT_MS)))
	return k


func _col(note: int) -> Color:
	return note_colors[note] if note >= 0 and note < note_colors.size() else THREAD


## Urteil eines Kopfes/Taps/Hold-Endes (aus note_judged).
func on_judged(index: int, result: Dictionary) -> void:
	if path == null or index < 0 or index >= _hit_t.size():
		return
	var q := int(result.get("quality", 5))
	var kn := path.knots[path.note_knot[index]]
	if q != 5 and core != null:
		var cb := int(core.combo)
		if cb != _mile_combo and (cb == 50 or (cb > 0 and cb % 100 == 0)):
			_mile_combo = cb
			_mile_t = t_ms
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
	return _ctr + v * _pq(v.y)


## Tiefen-Faktor fuer Schirm-Abstand y von der Bildmitte (px, vor der Neigung): am unteren
## Rand 1, nach oben kleiner. Nie groesser als 1 im Bild, also rutscht nichts hinaus.
func _pq(y: float) -> float:
	if _tilt <= 0.0:
		return 1.0
	return 1.0 / maxf(1.0 + _tilt * (0.5 - y / maxf(_ctr.y * 2.0, 1.0)), 0.5)


## Groesse von Pfeil und Ring an einem Weltpunkt: in der Bildmitte 1, vorn/hinten nur wenig anders.
func _depth_size(p: Vector2) -> float:
	if _tilt <= 0.0:
		return 1.0
	return clampf(_pq((p.y - _cam.y) * _sz) * (1.0 + _tilt * 0.5), 0.9, 1.08)


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
	# Tiefe und Musik: im End-Zeitraffer flach und still (das Bild ist die Karte).
	var live := 1.0 - _smooth(u / END_OUT)
	var bt := _beat_at(t_ms)
	_kx = _kiai_at(t_ms) * live
	_env = bt.x * live
	_tilt = (TILT + TILT_KIAI * _kx) * live
	_cur_s = cur_s
	_s_b = s_b
	_set_waves(bt, live)
	_draw_depth(vs, sc, live)
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


## Hinter dem Boden: Kiai-Licht am Horizont und zwei Staub-Ebenen (ruecken langsamer als
## der Boden, das gibt Tiefe). Alles ohne Zustand aus Zeit und Kamera.
func _draw_depth(vs: Vector2, sc: float, live: float) -> void:
	if live <= 0.02 or _sz < 0.45 * sc:
		return
	if _kx > 0.01:
		var h := vs.y * 0.42
		var a := (0.075 + 0.03 * _env) * _kx
		draw_primitive(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0.0), Vector2(vs.x, h), Vector2(0.0, h)]),
				PackedColorArray([Color(AMBER, a), Color(AMBER, a), Color(AMBER, 0.0), Color(AMBER, 0.0)]),
				PackedVector2Array())
	_draw_specks(vs, sc, 0.38, 0.55, 11, live)
	_draw_specks(vs, sc, 0.68, 0.8, 47, live)


## Eine Staub-Ebene: `par` = Anteil der Kamerafahrt, `scl` = Massstab gegen den Boden.
func _draw_specks(vs: Vector2, sc: float, par: float, scl: float, sd: int, live: float) -> void:
	var cell := 230.0
	var z := _sz * scl
	var cam := _cam * par + Vector2(0.0, -t_ms * 0.004 * par)
	var half := vs * 0.5 / z * (1.0 + _tilt)
	var col := THREAD.lerp(AMBER, 0.55 * _kx)
	var pulse := (0.8 + 0.45 * _env) * live
	for ix in range(int(floor((cam.x - half.x) / cell)), int(floor((cam.x + half.x) / cell)) + 1):
		for iy in range(int(floor((cam.y - half.y) / cell)), int(floor((cam.y + half.y) / cell)) + 1):
			var h := _hash(ix * 7 + sd, iy * 13 + sd)
			if h < 0.42:
				continue
			var v := (Vector2(float(ix) + _hash(ix + sd, iy + 31), float(iy) + _hash(ix + 57, iy + sd)) * cell - cam) * z
			if _mirror:
				v.x = -v.x
			var r := (1.0 + 1.7 * _hash(ix + 3, iy + sd * 5)) * sc * scl
			var c := AMBER if h > 0.9 else col
			draw_circle(_ctr + v * _pq(v.y), r, Color(c, (0.08 + 0.36 * (h - 0.42)) * pulse))


## Lichtwelle am Taktanfang und Kombo-Meilenstein: nur Werte, gezeichnet wird ueber die
## Bodenlinien (_draw_grid). Die Welle laeuft vom Ort des Kopfes nach aussen.
func _set_waves(bt: Vector3, live: float) -> void:
	_wave_a = 0.0
	_mile = 0.0
	if live <= 0.02:
		return
	var first_t := path.knots[0].t
	var last_t := path.knots[path.knots.size() - 1].t
	if bt.y >= 0.0 and t_ms > first_t - 2000.0 and t_ms < last_t + 600.0:
		var dur := clampf(bt.z * 2.0, 520.0, 1100.0)
		if bt.y < dur:
			var inv := 1.0 - bt.y / dur
			_wave_c = path.head_pos(t_ms - bt.y)
			_wave_r = WAVE_PX * (1.0 - inv * inv)
			_wave_a = (0.075 + 0.055 * _kx) * inv * live
	var age := t_ms - _mile_t
	if age >= 0.0 and age < MILE_MS:
		var inv2 := 1.0 - age / MILE_MS
		_mile = inv2 * inv2 * live


## Anteil der Lichtwelle auf einer Bodenlinie im Abstand d (Welt-px) vom Ursprung.
func _wave_on(d: float) -> float:
	if _wave_a <= 0.0:
		return 0.0
	var x := (d - _wave_r) / 130.0
	return _wave_a * exp(-x * x)


func _draw_grid(vs: Vector2) -> void:
	var sp := GRID
	while sp * _sz < 34.0:
		sp *= 2.0
	var half := vs * 0.5 / _sz * (1.0 + _tilt)
	var x0 := floorf((_cam.x - half.x) / sp) * sp
	var y0 := floorf((_cam.y - half.y) / sp) * sp
	var nx := int(ceil(half.x * 2.0 / sp)) + 2
	var ny := int(ceil(half.y * 2.0 / sp)) + 2
	var col := Color(THREAD, 0.07 + 0.035 * _env)
	var r := maxf(1.3, 1.9 * vs.y / 720.0)
	# Bodenlinien: geben dem geneigten Boden Fluchtlinien. Jede zweite etwas klarer.
	if _tilt > 0.0:
		var lc := THREAD.lerp(AMBER, maxf(0.7 * _kx, _mile))
		var la := (0.042 + 0.028 * _kx + 0.07 * _mile) * _tilt / TILT
		var lw := maxf(1.0, vs.y / 720.0)
		var xe := x0 + float(nx - 1) * sp
		var ye := y0 + float(ny - 1) * sp
		for ix in nx:
			var x := x0 + ix * sp
			var major := posmod(int(round(x / sp)), 2) == 0
			draw_line(_w2s(Vector2(x, y0)), _w2s(Vector2(x, ye)),
					Color(lc, la * (1.7 if major else 1.0) + _wave_on(absf(x - _wave_c.x))), lw, true)
		for iy in ny:
			var y := y0 + iy * sp
			var major2 := posmod(int(round(y / sp)), 2) == 0
			draw_line(_w2s(Vector2(x0, y)), _w2s(Vector2(xe, y)),
					Color(lc, la * (1.7 if major2 else 1.0) + _wave_on(absf(y - _wave_c.y))), lw, true)
	for ix in nx:
		for iy in ny:
			draw_circle(_w2s(Vector2(x0 + ix * sp, y0 + iy * sp)), r, col)


func _pts_screen(s0: float, s1: float, step: float) -> PackedVector2Array:
	var w := path.sample(s0, s1, step)
	for i in w.size():
		w[i] = _w2s(w[i])
	return w


## Vorlauf: durchgehende Bahn (Mittellinie + zwei Randlinien), nach vorn blasser (Mods duennen sie aus).
func _draw_upcoming(cur_s: float, s_b: float, wf: float) -> void:
	if s_b <= cur_s:
		return
	var span := s_b - cur_s
	var look := TracePath.LOOK_S * 1000.0
	var cover: Array = []
	for h in _holds:
		if float(h.s1) >= cur_s and float(h.s0) <= s_b:
			cover.append(h)
	# Schiene: durchgehende feine Linie unter den Punkten, im Takt etwas heller.
	var rail := path.sample(cur_s, s_b, 12.0)
	var rn := rail.size()
	if rn >= 2:
		var rc := PackedColorArray()
		var base := THREAD.lerp(AMBER, 0.3 * _kx)
		var lift := 0.6 + 0.12 * _env
		for i in rn:
			var rf := float(i) / float(rn - 1)
			var rs := cur_s + span * rf
			var ra := lift * pow(1.0 - rf, 0.8) * clampf(rf * span / 40.0, 0.0, 1.0)
			ra *= TraceMods.path_alpha(look * rf, mods)
			for h in cover:
				if rs >= float(h.s0) and rs <= float(h.s1):
					ra = 0.0
			rc.append(Color(base, ra))
			rail[i] = _w2s(rail[i])
		# Bahn: zwei feine Randlinien neben der Mittellinie (nah klar, vorn blasser).
		var rnr := _normals(rail)
		var side := PackedVector2Array()
		side.resize(rn)
		var sc_col := PackedColorArray()
		for i in rn:
			sc_col.append(Color(base, rc[i].a * 0.42))
		for sg in [-1.0, 1.0]:
			for i in rn:
				side[i] = rail[i] + rnr[i] * sg * 6.5 * wf
			draw_polyline_colors(side, sc_col, 1.0 * wf, true)
		draw_polyline_colors(rail, rc, 2.0 * wf, true)


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
	var edge := 1.0 + 0.4 * _env + 0.45 * _kx   # Lichtkante: im Takt und im Kiai kraeftiger
	_ribbon(pts, nr, wk, fs, dk, wf * 10.0, wf * 9.0, 0.07 * a * edge)
	_ribbon(pts, nr, wk, fs, dk, wf * 3.6, wf * 4.5, 0.2 * a * edge)
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
	var ks := _depth_size(kn.pos)
	var zs := _sz * ks
	if open:
		# Annaeherungsring: schrumpft bis zur Notenzeit.
		var frac := clampf(dt / APPROACH_MS, 0.0, 1.0)
		var base_col := _col(kn.notes[0])
		# Nur der naechste Knoten hat einen Ring: ein Kreis im Bild, eindeutig.
		if is_next and dt < APPROACH_MS and dt > -140.0:
			var r := lerpf(RING_NEAR, RING_FAR, frac) * zs
			var a := minf(1.0, (0.54 + 0.6 * (1.0 - frac)) * fade_in)
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
			_arrow(p, _dir(kn.cols[i]), chord, _col(n), fade_in, grow * ks, kn.cols[i])
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
			_arrow(p, _dir(kn.cols[i]), kn.notes.size() > 1, col, fa, (1.0 + 0.3 * (1.0 - fa)) * ks, kn.cols[i])
		if age < FLASH_MS:
			var u := age / FLASH_MS
			var inv := 1.0 - u
			var jc: Color = JUDGE_COL[clampi(_hit_q[n], 0, 5)]
			# Treffer: heller Querstrich ueber die Bahn, der kurz aufgeht (kein Ring).
			var ang := path.angle_at(kn.s + 1.0)
			var nrm := Vector2(-sin(ang), cos(ang)) * (9.0 + 15.0 * (1.0 - inv * inv))
			var q0 := _w2s(kn.pos - nrm)
			var q1 := _w2s(kn.pos + nrm)
			draw_line(q0, q1, Color(INK, 0.5 * inv), (3.4 * inv + 2.6) * wf, true)
			draw_line(q0, q1, Color(jc.lerp(Color.WHITE, 0.35), 0.95 * inv), (3.4 * inv + 0.8) * wf, true)
		if age < GLINT_MS and i == 0 and end_zoom <= 0.0:
			_glint(age, JUDGE_COL[clampi(_hit_q[n], 0, 5)], wf)
	if any_hit and not open:
		draw_circle(p, 3.0 * wf + 0.4, Color(_col(kn.notes[0]).lightened(0.2), 0.85))


## Glanz nach einem Treffer: kurzes helles Stueck laeuft dem Kopf auf der Schiene voraus.
func _glint(age: float, col: Color, wf: float) -> void:
	var k := age / GLINT_MS
	var mid := _cur_s + 26.0 + GLINT_PX * (1.0 - (1.0 - k) * (1.0 - k))
	var s0 := maxf(mid - 48.0, _cur_s)
	var s1 := minf(mid + 48.0, _s_b)
	if s1 - s0 < 10.0:
		return
	var pts := _pts_screen(s0, s1, 8.0)
	var n := pts.size()
	if n < 2:
		return
	var c := col.lerp(Color.WHITE, 0.55)
	var cs := PackedColorArray()
	for i in n:
		cs.append(Color(c, sin(PI * float(i) / float(n - 1)) * 0.95 * (1.0 - k)))
	draw_polyline_colors(pts, cs, 3.8 * wf, true)


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
	var r := 6.0 * wf * (1.0 + 0.14 * _env)
	var fa := 1.0 - fin
	draw_circle(p, r * 1.62, Color(INK, 0.85 * fa))
	if not racing:
		draw_circle(p, r * 1.3, Color(HEAD.lerp(AMBER, 0.8), fa))
	draw_circle(p, r * 0.92, Color(HEAD, fa))
