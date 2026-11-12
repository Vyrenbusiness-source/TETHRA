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
	# Richtungen.
	var ang := angle_of_col(knots[0].cols[0]) if knots[0].cols.size() == 1 else 0.0
	var first_ang := ang
	var hair_sign := 1.0
	for j in knots.size():
		var kn := knots[j]
		var target := ang
		var keep := false
		var cs := kn.cols.duplicate()
		cs.sort()
		var m := cs.size()
		if m == 1:
			target = angle_of_col(cs[0])
		elif m == 2:
			var v := dir_of_col(cs[0]) + dir_of_col(cs[1])
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
		if not keep:
			d = wrapf(target - ang, -PI, PI)
			if absf(d) >= HAIRPIN_MIN:
				kn.hairpin = true
				d = PI * hair_sign
				hair_sign = -hair_sign
			elif absf(d) < 0.0001:
				d = 0.0
		kn.turn = d
		ang += d
		kn.angle = ang
	# Bogenfenster so, dass sich Nachbarn nie ueberlappen.
	for j in knots.size():
		var w := WIN_MAX
		if j > 0:
			w = minf(w, 0.5 * (knots[j].s - knots[j - 1].s))
		if j < knots.size() - 1:
			w = minf(w, 0.5 * (knots[j + 1].s - knots[j].s))
		knots[j].win = w
	_build_pieces(first_ang)
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


func _build_pieces(a0: float) -> void:
	var cs := 0.0
	var cx := 0.0
	var cy := 0.0
	var ca := a0
	var started := false
	for kn in knots:
		if kn.is_straight():
			continue
		var s_in := kn.s - kn.win
		var s_out := kn.s + kn.win
		if started and s_in > cs + 0.0001:
			var r := _add_piece(cs, s_in, cx, cy, ca, 0.0)
			cx = r.x
			cy = r.y
		elif not started:
			cs = s_in
		cs = s_in
		started = true
		var kk := kn.turn / (2.0 * kn.win)
		var r2 := _add_piece(cs, s_out, cx, cy, ca, kk)
		cx = r2.x
		cy = r2.y
		ca += kn.turn
		cs = s_out
	_end_x = cx
	_end_y = cy
	_end_a = ca
	_end_s = cs


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
