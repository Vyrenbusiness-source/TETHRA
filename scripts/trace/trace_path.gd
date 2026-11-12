class_name TracePath
extends RefCounted

## Trace: Geometrie des Fadens aus der Notenliste (rein, deterministisch, ohne Szene).
##
## Der Kopf laeuft mit festem Tempo (Bogenlaenge s je Zeit t); jede Note-Gruppe (Akkord =
## gleiche Zeit) ist ein Knoten an s(t). Richtung absolut: Spalte 0 links, 1 runter,
## 2 hoch, 3 rechts. Einzelnote: neue Richtung. Gleiche Richtung = Knoten auf gerader
## Strecke, Gegenrichtung = Haarnadel (Halbkreis, Seite wechselt), Akkord aus 2 =
## Diagonale (Gegenpaar: Kreuzknoten, Richtung bleibt), 3-4 = Sternknoten (Richtung bleibt).
## Die Kurve ist stueckweise Gerade/Kreisbogen (Knick = Bogen ueber [s-w, s+w]), daher
## stimmt Bogenlaenge = Zeit * Tempo exakt. Holds: Bereich [s(Kopf), s(Ende)].
## Nur Optik: Mindest-Segmentlaenge MIN_SEG (Streams) hebt das Tempo lokal an.

const BASE_SPEED := 520.0       ## Welt-px je Sekunde (Fadentempo-Standard)
const MIN_SEG := 84.0           ## kleinster Knotenabstand (Pfeile ueberdecken sich nie)
const WIN_MAX := 54.0           ## halbe Laenge des Knick-Bogens (max.)
const HAIRPIN_MIN := 2.9        ## ab diesem Knickwinkel (rad) = Haarnadel
const CHORD_MS := 2.0           ## Noten innerhalb dieser Zeit = Akkord
const LOOK_S := 1.2             ## Vorlauf in Sekunden (gezeichneter Weg voraus)
const ARROW_R := 18.0           ## Pfeil-Halbmesser (Einzelnote) fuer die Ueberdeckungspruefung
const CHORD_R := 36.0           ## Halbmesser eines Akkord-Knotens (Pfeile sitzen 19 px daneben)
## Leichte Zusatzkurven (rad) gegen Ueberdeckung, in dieser Reihenfolge probiert (deterministisch).
const EVADE := [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9, 1.2, -1.2, 1.57, -1.57, 2.0, -2.0, 2.4, -2.4, 2.8, -2.8, 3.14]
const HARD := 1000             ## ab diesen Kosten bleibt eine Ueberdeckung (Sackgasse)
const SAMPLE := 12.0            ## Stuetzpunktabstand des Fadens fuer die Ueberdeckungspruefung
const CELL := 16.0              ## Rasterzelle der Stuetzpunkte
const NEAR_KNOT := 6.0          ## Mindestluft zwischen zwei Pfeilen (px)
const NEAR_ARROW := 14.0        ## Pfeil-Mitte zu fremdem Faden (px)
const NEAR_THREAD := 8.0        ## Faden zu fremdem Faden (px)
const FOREIGN := 70.0           ## naeher als das (Bogenlaenge) gehoert Faden zum selben Stueck
const LOOKAHEAD := 96.0         ## so weit hinter dem Bogen wird der neue Faden mitgeprueft
const TRAIL_PX := 820.0         ## sichtbare Fadenspur hinter dem Kopf (wie TraceView)
const COL_ANGLE := [PI, PI * 0.5, -PI * 0.5, 0.0]  ## links, runter, hoch, rechts

enum Kind { SINGLE, DIAG, CROSS, STAR }


class Knot:
	extends RefCounted
	var t := 0.0              ## Zeit des Knotens (ms)
	var s := 0.0              ## Bogenlaenge (px)
	var pos := Vector2.ZERO
	var angle := 0.0          ## Richtung danach (rad, fortlaufend, ohne Sprung)
	var turn := 0.0           ## Drehung am Knoten (rad)
	var win := 0.0            ## halbe Bogenlaenge
	var kind := 0             ## TracePath.Kind
	var hairpin := false
	var notes: Array[int] = []   ## Indizes in der Notenliste (Reihenfolge des Beatmaps)
	var cols: Array[int] = []
	var holds: Array = []        ## je Hold: { "note": i, "col": c, "s_end": s, "t_end": ms }

	func is_straight() -> bool:
		return absf(turn) < 0.0001


var knots: Array[Knot] = []
var speed := BASE_SPEED
var note_knot := PackedInt32Array()   ## Note-Index -> Knoten-Index

var _kt := PackedFloat64Array()       ## Knoten-Zeiten
var _ks := PackedFloat64Array()       ## Knoten-Bogenlaengen
# Stuecke (Gerade/Bogen): Beginn s, Ende s, Startposition, Startwinkel, Kruemmung.
var _p_s0 := PackedFloat64Array()
var _p_s1 := PackedFloat64Array()
var _p_x := PackedFloat64Array()
var _p_y := PackedFloat64Array()
var _p_a := PackedFloat64Array()
var _p_k := PackedFloat64Array()
var _end_x := 0.0
var _end_y := 0.0
var _end_a := 0.0
var _end_s := 0.0
var _bounds := Rect2()
# Nur waehrend des Aufbaus: Zustand am Fadenende, Stuetzpunkte (+ Raster), Knotenmitten.
var _cx := 0.0
var _cy := 0.0
var _ca := 0.0
var _h_pts := PackedVector2Array()
var _h_s := PackedFloat64Array()
var _h_grid := {}
var _k_pos := PackedVector2Array()


static func angle_of_col(c: int) -> float:
	return float(COL_ANGLE[clampi(c, 0, 3)])


static func dir_of_col(c: int) -> Vector2:
	var a := angle_of_col(c)
	return Vector2(cos(a), sin(a))


## Aus einem Mania-4K-Beatmap (hit_objects in Dateireihenfolge).
static func from_beatmap(bm: Beatmap, p_speed: float = BASE_SPEED) -> TracePath:
	var times := PackedFloat64Array()
	var cols := PackedInt32Array()
	var ends := PackedFloat64Array()
	for o in bm.hit_objects:
		var n := o as ManiaNote
		times.append(float(n.time))
		cols.append(n.column)
		ends.append(float(n.end_time()) if n.is_hold else float(n.time))
	return build(times, cols, ends, p_speed)


## times/cols/ends je Note (ends = times fuer Tap). Beliebige Reihenfolge.
static func build(times: PackedFloat64Array, cols: PackedInt32Array, ends: PackedFloat64Array,
		p_speed: float = BASE_SPEED) -> TracePath:
	var p := TracePath.new()
	p.speed = maxf(p_speed, 50.0)
	p._build(times, cols, ends)
	return p


func _build(times: PackedFloat64Array, cols: PackedInt32Array, ends: PackedFloat64Array) -> void:
	var n := times.size()
	note_knot.resize(n)
	note_knot.fill(-1)
	if n == 0:
		return
	var order: Array[int] = []
	for i in n:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if times[a] != times[b]:
			return times[a] < times[b]
		return a < b)
	# Gruppen = Akkorde.
	var g_start := -1.0
	for i in order:
		if knots.is_empty() or times[i] - g_start > CHORD_MS:
			var k := Knot.new()
			k.t = times[i]
			g_start = times[i]
			knots.append(k)
		var kn := knots[knots.size() - 1]
		kn.notes.append(i)
		kn.cols.append(clampi(cols[i], 0, 3))
		note_knot[i] = knots.size() - 1
	# Bogenlaenge je Knoten (Mindestabstand: nur Optik).
	var s := 0.0
	for j in knots.size():
		if j > 0:
			s += maxf(speed * (knots[j].t - knots[j - 1].t) / 1000.0, MIN_SEG)
		knots[j].s = s
		_kt.append(knots[j].t)
		_ks.append(s)
	# Bogenfenster so, dass sich Nachbarn nie ueberlappen.
	for j in knots.size():
		var w := WIN_MAX
		if j > 0:
			w = minf(w, 0.5 * (knots[j].s - knots[j - 1].s))
		if j < knots.size() - 1:
			w = minf(w, 0.5 * (knots[j + 1].s - knots[j].s))
		knots[j].win = w
	_lay_out()
	for kn in knots:
		kn.pos = pos_at(kn.s)
	# Holds.
	for i in n:
		if ends[i] > times[i] + 0.5:
			var kn := knots[note_knot[i]]
			kn.holds.append({
				"note": i, "col": clampi(cols[i], 0, 3),
				"s_end": s_at(ends[i]), "t_end": ends[i],
			})
	_calc_bounds()


## Richtungen und Faden, Knoten fuer Knoten. Die Notenrichtung gibt die Wunschdrehung vor;
## ueberdeckt der Pfeil danach einen frueheren (oder liegt er auf fremdem Faden), weicht
## eine leichte Zusatzkurve (EVADE) aus. Sackgasse = Ruecksprung zum Vorgaenger mit der
## naechsten Kurve (begrenztes Backtracking). Nur die Form aendert sich, s(t) bleibt exakt.
func _lay_out() -> void:
	var n := knots.size()
	var ang := angle_of_col(knots[0].cols[0]) if knots[0].cols.size() == 1 else 0.0
	var hair_sign := 1.0
	_cx = 0.0
	_cy = 0.0
	_ca = ang
	var cs: float = knots[0].s - knots[0].win
	_h_pts = PackedVector2Array()
	_h_s = PackedFloat64Array()
	_h_grid = {}
	_k_pos = PackedVector2Array()
	_h_add(Vector2.ZERO, cs)
	var offset := Vector2.ZERO
	var have_offset := false
	var kfirst := 0
	# Zustand vor jedem Knoten (fuer den Ruecksprung) und naechster Kurven-Versuch.
	var snap_f := PackedFloat64Array()
	var snap_i := PackedInt32Array()
	snap_f.resize(n * 8)
	snap_i.resize(n * 4)
	var next_try := PackedInt32Array()
	next_try.resize(n)
	var snapped := PackedByteArray()
	snapped.resize(n)
	var budget := n * 10 + 400
	var j := 0
	while j < n:
		var kn := knots[j]
		if snapped[j] == 0:
			snapped[j] = 1
			snap_f[j * 8] = _cx
			snap_f[j * 8 + 1] = _cy
			snap_f[j * 8 + 2] = _ca
			snap_f[j * 8 + 3] = cs
			snap_f[j * 8 + 4] = ang
			snap_f[j * 8 + 5] = hair_sign
			snap_f[j * 8 + 6] = offset.x
			snap_f[j * 8 + 7] = offset.y
			snap_i[j * 4] = _p_s0.size()
			snap_i[j * 4 + 1] = _h_pts.size()
			snap_i[j * 4 + 2] = _k_pos.size()
			snap_i[j * 4 + 3] = 1 if have_offset else 0
		var target := ang
		var keep := false
		var cs_cols := kn.cols.duplicate()
		cs_cols.sort()
		var m := cs_cols.size()
		kn.hairpin = false
		if m == 1:
			target = angle_of_col(cs_cols[0])
		elif m == 2:
			var v := dir_of_col(cs_cols[0]) + dir_of_col(cs_cols[1])
			if v.length() < 0.01:
				kn.kind = Kind.CROSS
				keep = true
			else:
				kn.kind = Kind.DIAG
				target = atan2(v.y, v.x)
		else:
			kn.kind = Kind.STAR
			keep = true
		var d := 0.0
		var hs_after := hair_sign
		if not keep:
			d = wrapf(target - ang, -PI, PI)
			if absf(d) >= HAIRPIN_MIN:
				kn.hairpin = true
				d = PI * hair_sign
				hs_after = -hair_sign
			elif absf(d) < 0.0001:
				d = 0.0
		var s_in := kn.s - kn.win
		var s_out := kn.s + kn.win
		_commit(cs, s_in, 0.0)
		while kfirst > 0 and knots[kfirst - 1].t >= kn.t - LOOK_S * 1000.0:
			kfirst -= 1
		while knots[kfirst].t < kn.t - LOOK_S * 1000.0:
			kfirst += 1
		var lo_s: float = knots[kfirst].s - TRAIL_PX
		var best := d
		var chosen := -1
		if j > 0:
			var bc := 1 << 30
			for ci in range(next_try[j], EVADE.size()):
				var c := _cost(j, s_in, kn.win, d + EVADE[ci], kfirst, lo_s, bc)
				if c < bc:
					bc = c
					best = d + EVADE[ci]
					chosen = ci
				if c == 0:
					break
			if bc >= HARD:
				chosen = -1
				if budget > 0:
					# Sackgasse: zum Vorgaenger zurueck, naechste Kurve dort.
					budget -= 1
					next_try[j] = 0
					snapped[j] = 0
					j -= 1
					_restore(j, snap_f, snap_i)
					ang = snap_f[j * 8 + 4]
					hair_sign = snap_f[j * 8 + 5]
					cs = snap_f[j * 8 + 3]
					offset = Vector2(snap_f[j * 8 + 6], snap_f[j * 8 + 7])
					have_offset = snap_i[j * 4 + 3] == 1
					continue
		else:
			chosen = 0
		next_try[j] = chosen + 1 if chosen >= 0 else EVADE.size()
		hair_sign = hs_after
		if absf(best) < 0.0001:
			best = 0.0
		kn.turn = best
		ang += best
		kn.angle = ang
		var k := best / (2.0 * kn.win) if kn.win > 0.0 else 0.0
		if best != 0.0 and not have_offset:
			have_offset = true
			offset = Vector2(_cx, _cy)
		var pm := _adv(_cx, _cy, _ca, kn.win, k)
		_k_pos.append(Vector2(pm.x, pm.y))
		_commit(s_in, s_out, k)
		cs = s_out
		j += 1
	_end_x = _cx - offset.x
	_end_y = _cy - offset.y
	_end_a = _ca
	_end_s = cs
	for i in _p_x.size():
		_p_x[i] -= offset.x
		_p_y[i] -= offset.y
	_h_pts = PackedVector2Array()
	_h_s = PackedFloat64Array()
	_h_grid = {}
	_k_pos = PackedVector2Array()


## Stellt den Fadenzustand vor Knoten j wieder her (Stuecke, Stuetzpunkte, Knotenmitten).
func _restore(j: int, snap_f: PackedFloat64Array, snap_i: PackedInt32Array) -> void:
	_cx = snap_f[j * 8]
	_cy = snap_f[j * 8 + 1]
	_ca = snap_f[j * 8 + 2]
	var np := snap_i[j * 4]
	_p_s0.resize(np)
	_p_s1.resize(np)
	_p_x.resize(np)
	_p_y.resize(np)
	_p_a.resize(np)
	_p_k.resize(np)
	var nh := snap_i[j * 4 + 1]
	for i in range(_h_pts.size() - 1, nh - 1, -1):
		var p := _h_pts[i]
		var c := Vector2i(int(floorf(p.x / CELL)), int(floorf(p.y / CELL)))
		var cell: PackedInt32Array = _h_grid[c]
		cell.resize(cell.size() - 1)
		_h_grid[c] = cell
	_h_pts.resize(nh)
	_h_s.resize(nh)
	_k_pos.resize(snap_i[j * 4 + 2])


## Zustand (x, y, Winkel) nach Laenge l auf einem Stueck mit Kruemmung k.
static func _adv(x: float, y: float, a: float, l: float, k: float) -> Vector3:
	if absf(k) < 1e-9:
		return Vector3(x + l * cos(a), y + l * sin(a), a)
	return Vector3(x + (sin(a + k * l) - sin(a)) / k, y - (cos(a + k * l) - cos(a)) / k, a + k * l)


## Haengt das Stueck [s0, s1] an den Faden (Stuecke + Stuetzpunkte fuer die Pruefung).
func _commit(s0: float, s1: float, k: float) -> void:
	var l := s1 - s0
	if l <= 0.0001:
		return
	var m := maxi(1, int(ceil(l / SAMPLE)))
	for i in range(1, m + 1):
		var q := _adv(_cx, _cy, _ca, l * float(i) / float(m), k)
		_h_add(Vector2(q.x, q.y), s0 + l * float(i) / float(m))
	var r := _add_piece(s0, s1, _cx, _cy, _ca, k)
	_ca += k * l
	_cx = r.x
	_cy = r.y


func _h_add(p: Vector2, s: float) -> void:
	var c := Vector2i(int(floorf(p.x / CELL)), int(floorf(p.y / CELL)))
	if not _h_grid.has(c):
		_h_grid[c] = PackedInt32Array()
	_h_grid[c].append(_h_pts.size())
	_h_pts.append(p)
	_h_s.append(s)


## 1, wenn ein Stuetzpunkt mit s in [lo, hi] naeher als r an p liegt.
func _near(p: Vector2, r: float, lo: float, hi: float) -> int:
	var c0 := Vector2i(int(floorf((p.x - r) / CELL)), int(floorf((p.y - r) / CELL)))
	var c1 := Vector2i(int(floorf((p.x + r) / CELL)), int(floorf((p.y + r) / CELL)))
	var r2 := r * r
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var cell = _h_grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for i in cell:
				var s := _h_s[i]
				if s >= lo and s <= hi and _h_pts[i].distance_squared_to(p) < r2:
					return 1
	return 0


## Kosten einer Drehung am Knoten j (0 = keine Ueberdeckung): Pfeil auf frueherem Pfeil,
## Pfeil auf fremdem Faden, neuer Faden auf fremdem Faden.
func _cost(j: int, s_in: float, w: float, turn: float, kfirst: int, lo_s: float, limit: int) -> int:
	var k := turn / (2.0 * w)
	var rj := knot_radius(j)
	var pm := _adv(_cx, _cy, _ca, w, k)
	var pk := Vector2(pm.x, pm.y)
	var c := 0
	for q in range(kfirst, j):
		var rr := rj + knot_radius(q) + NEAR_KNOT
		if _k_pos[q].distance_squared_to(pk) < rr * rr:
			c += 1000
	if c >= limit:
		return c
	var s_far := s_in + w - FOREIGN
	c += 1000 * _near(pk, NEAR_ARROW + rj - ARROW_R, lo_s, s_far)
	var e := _adv(_cx, _cy, _ca, 2.0 * w, k)
	# Ein Knoten Vorschau: der naechste Knoten (gerade weiter) soll frei liegen.
	if j + 1 < knots.size():
		var gap: float = knots[j + 1].s - (s_in + 2.0 * w)
		var pn := Vector2(e.x + gap * cos(e.z), e.y + gap * sin(e.z))
		var rn := knot_radius(j + 1)
		var bad := 0
		for q in range(kfirst, j):
			var rr := rn + knot_radius(q) + NEAR_KNOT
			if _k_pos[q].distance_squared_to(pn) < rr * rr:
				bad += 1
		var rr2 := rn + rj + NEAR_KNOT
		if pk.distance_squared_to(pn) < rr2 * rr2:
			bad += 1
		c += 1000 * bad
		c += 8 * _near(pn, NEAR_ARROW + rn - ARROW_R, lo_s, s_in + 2.0 * w + gap - FOREIGN)
	var span := 2.0 * w + LOOKAHEAD
	var n := int(ceil(span / SAMPLE))
	for i in range(1, n + 1):
		var l := minf(float(i) * SAMPLE, span)
		var q: Vector3
		if l <= 2.0 * w:
			q = _adv(_cx, _cy, _ca, l, k)
		else:
			q = _adv(e.x, e.y, e.z, l - 2.0 * w, 0.0)
		c += _near(Vector2(q.x, q.y), NEAR_THREAD, lo_s, s_in + l - FOREIGN)
		if c >= limit:
			break
	return c


## Haengt ein Stueck an und liefert die Endposition (x, y).
func _add_piece(s0: float, s1: float, x: float, y: float, a: float, k: float) -> Vector2:
	_p_s0.append(s0)
	_p_s1.append(s1)
	_p_x.append(x)
	_p_y.append(y)
	_p_a.append(a)
	_p_k.append(k)
	var l := s1 - s0
	if absf(k) < 1e-9:
		return Vector2(x + l * cos(a), y + l * sin(a))
	return Vector2(x + (sin(a + k * l) - sin(a)) / k, y - (cos(a + k * l) - cos(a)) / k)


## Position bei Bogenlaenge s (vor/hinter dem Faden gerade verlaengert).
func pos_at(s: float) -> Vector2:
	var q := _eval(s)
	return Vector2(q[0], q[1])


## Richtung (rad) bei Bogenlaenge s.
func angle_at(s: float) -> float:
	return _eval(s)[2]


func _eval(s: float) -> Array:
	var np := _p_s0.size()
	if np == 0:
		return [s * cos(_end_a), s * sin(_end_a), _end_a]
	if s <= _p_s0[0]:
		var a0 := _p_a[0]
		return [_p_x[0] + (s - _p_s0[0]) * cos(a0), _p_y[0] + (s - _p_s0[0]) * sin(a0), a0]
	if s >= _p_s1[np - 1]:
		var l := s - _end_s
		return [_end_x + l * cos(_end_a), _end_y + l * sin(_end_a), _end_a]
	var lo := 0
	var hi := np - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _p_s0[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var i := lo
	var u := s - _p_s0[i]
	var a := _p_a[i]
	var k := _p_k[i]
	if absf(k) < 1e-9:
		return [_p_x[i] + u * cos(a), _p_y[i] + u * sin(a), a]
	return [_p_x[i] + (sin(a + k * u) - sin(a)) / k, _p_y[i] - (cos(a + k * u) - cos(a)) / k, a + k * u]


## Bogenlaenge zur Zeit t (ms): linear zwischen Knoten, davor/danach mit Grundtempo.
func s_at(t: float) -> float:
	var n := _kt.size()
	if n == 0:
		return speed * t / 1000.0
	if t <= _kt[0]:
		return _ks[0] + speed * (t - _kt[0]) / 1000.0
	if t >= _kt[n - 1]:
		return _ks[n - 1] + speed * (t - _kt[n - 1]) / 1000.0
	var lo := 0
	var hi := n - 1
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if _kt[mid] <= t:
			lo = mid
		else:
			hi = mid
	var f := (t - _kt[lo]) / (_kt[hi] - _kt[lo])
	return _ks[lo] + f * (_ks[hi] - _ks[lo])


## Position des Kopfs zur Zeit t (ms).
func head_pos(t: float) -> Vector2:
	return pos_at(s_at(t))


## Index des ersten Knotens mit Zeit >= t (knots.size() wenn keiner).
func first_knot_from(t: float) -> int:
	var lo := 0
	var hi := knots.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _kt[mid] < t:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Index des ersten Knotens mit Bogenlaenge >= s.
func first_knot_from_s(s: float) -> int:
	var lo := 0
	var hi := knots.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _ks[mid] < s:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Stuetzpunkte des Fadens zwischen s0 und s1, hoechstens alle `step` px.
func sample(s0: float, s1: float, step: float = 6.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s1 < s0:
		return out
	var n := maxi(1, int(ceil((s1 - s0) / maxf(step, 0.5))))
	for i in n + 1:
		out.append(pos_at(s0 + (s1 - s0) * float(i) / float(n)))
	return out


## Zielpunkt der Kamera zur Zeit t: Kopf, leicht zum kommenden Weg verschoben.
func camera_target(t: float, lead: float = 0.18) -> Vector2:
	var s := s_at(t)
	var head := pos_at(s)
	var ahead := pos_at(s_at(t + LOOK_S * 1000.0))
	return head + (ahead - head) * lead


## Weiche Kamera ohne Zustand: gewichtetes Mittel des Ziels ueber die letzten ~0,45 s.
## Gleiche Zeit = gleiche Kamera (Seek, Pause, Replay, Screenshot).
func camera(t: float) -> Vector2:
	var acc := Vector2.ZERO
	var wsum := 0.0
	for i in 10:
		var w := exp(-float(i) * 0.045 / 0.2)
		acc += camera_target(t - float(i) * 45.0) * w
		wsum += w
	return acc / wsum


func _calc_bounds() -> void:
	if knots.is_empty():
		_bounds = Rect2()
		return
	var s0 := knots[0].s - 80.0
	var s1 := knots[knots.size() - 1].s + 80.0
	var pts := sample(s0, s1, maxf((s1 - s0) / 4000.0, 8.0))
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	_bounds = r


## Rechteck um den ganzen Faden (fuer den End-Zoom).
func bounds() -> Rect2:
	return _bounds


func total_length() -> float:
	return 0.0 if knots.is_empty() else knots[knots.size() - 1].s - knots[0].s


## Anzahl Knoten einer Art (Tests, Debug).
func count_kind(k: int) -> int:
	var c := 0
	for kn in knots:
		if kn.kind == k:
			c += 1
	return c


func hairpin_count() -> int:
	var c := 0
	for kn in knots:
		if kn.hairpin:
			c += 1
	return c


## Halbmesser der Pfeile eines Knotens (Ueberdeckungspruefung).
func knot_radius(j: int) -> float:
	return CHORD_R if knots[j].notes.size() > 1 else ARROW_R


## Knotenpaare [j, k], die im Vorlauf gleichzeitig sichtbar sind (Zeit <= LOOK_S) und
## sich ueberdecken (Mittelpunktabstand < Summe der Pfeil-Halbmesser).
func overlap_pairs() -> Array:
	var out: Array = []
	var look := LOOK_S * 1000.0
	for j in knots.size():
		var rj := knot_radius(j)
		var k := j + 1
		while k < knots.size() and knots[k].t - knots[j].t <= look:
			if knots[j].pos.distance_to(knots[k].pos) < rj + knot_radius(k):
				out.append([j, k])
			k += 1
	return out
