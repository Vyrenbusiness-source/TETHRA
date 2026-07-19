class_name HitSlider
extends HitObject

## Schiene (Abschnitt 3.4). Heisst HitSlider, weil "Slider" ein eingebauter
## Godot-Control-Typ ist und der Name kollidieren wuerde.
## x,y,time,type,hitSound,curveType|curvePoints,slides,length,edgeSounds,edgeSets,hitSample

## "B"=Bezier, "P"=Perfect Circle, "L"=Linear, "C"=Catmull.
var curve_type: String = "B"

## Kontrollpunkte inkl. Startpunkt als erstem Element (Playfield-Koordinaten).
## Der Startpunkt (x,y der Zeile) wird beim Parsen vorangestellt — er steht laut
## Spezifikation NICHT in der pipe-getrennten Liste.
var curve_points: PackedVector2Array = PackedVector2Array()

## Anzahl Durchlaeufe. 1=hin, 2=hin+zurueck, ...
var slides: int = 1

## Pfadlaenge in osupixeln.
var length: float = 0.0

## Dauer EINES Durchlaufs in ms:
## durationMs = length / (SliderMultiplier * 100 * SV) * beatLength
var single_duration_ms: float = 0.0

func _init() -> void:
	kind = Kind.SLIDER

## Gesamtdauer ueber alle Durchlaeufe.
func total_duration_ms() -> float:
	return single_duration_ms * slides

func end_time() -> float:
	return time + total_duration_ms()


# ---------------------------------------------------------------------------
# Reale Kurvengeometrie (Abschnitt 3.4): Bezier / Perfect Circle / Linear /
# Catmull werden zu einer dichten Polyline abgetastet und auf die Pixel-Laenge
# `length` getrimmt. Genutzt fuer die 3D-Slider-Roehre UND das echte Ende.
# ---------------------------------------------------------------------------

## Dichte Polyline der tatsaechlich befahrenen Kurve (osu-Koordinaten), eine
## Fahrt vorwaerts, auf `length` getrimmt.
func path_points() -> PackedVector2Array:
	var cp := curve_points
	if cp.size() < 2:
		return cp
	var raw: PackedVector2Array
	match curve_type:
		"L":
			raw = cp.duplicate()
		"P":
			raw = _perfect_path(cp)
		"C":
			raw = _catmull_path(cp)
		_:
			raw = _bezier_path(cp)
	return _trim_to_length(raw, length)


## Endpunkt der Kurve nach `length` (korrektes Slider-Ende).
func curve_end() -> Vector2:
	var pts := path_points()
	return pts[pts.size() - 1] if pts.size() > 0 else position()


func _bezier_path(cp: PackedVector2Array) -> PackedVector2Array:
	# Wiederholte Punkte trennen die Segmente (osu-Konvention).
	var out := PackedVector2Array()
	var seg := PackedVector2Array()
	seg.append(cp[0])
	for i in range(1, cp.size()):
		if cp[i] == cp[i - 1]:
			_append_bezier(out, seg)
			seg = PackedVector2Array()
		seg.append(cp[i])
	_append_bezier(out, seg)
	return out


func _append_bezier(out: PackedVector2Array, seg: PackedVector2Array) -> void:
	if seg.size() < 2:
		return
	if seg.size() == 2:
		if out.is_empty():
			out.append(seg[0])
		out.append(seg[1])
		return
	var approx := 0.0
	for i in range(1, seg.size()):
		approx += seg[i].distance_to(seg[i - 1])
	var steps := maxi(int(approx / 4.0), 4)
	if out.is_empty():
		out.append(seg[0])
	for s in range(1, steps + 1):
		out.append(_bezier_at(seg, float(s) / float(steps)))


func _bezier_at(seg: PackedVector2Array, t: float) -> Vector2:
	var tmp := seg.duplicate()
	var n := tmp.size()
	for k in range(1, n):
		for i in range(0, n - k):
			tmp[i] = tmp[i].lerp(tmp[i + 1], t)
	return tmp[0]


func _perfect_path(cp: PackedVector2Array) -> PackedVector2Array:
	if cp.size() != 3:
		return _bezier_path(cp)
	var a := cp[0]
	var b := cp[1]
	var c := cp[2]
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return cp.duplicate()  # kollinear -> linear
	var a2 := a.x * a.x + a.y * a.y
	var b2 := b.x * b.x + b.y * b.y
	var c2 := c.x * c.x + c.y * c.y
	var center := Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
	var r := center.distance_to(a)
	var start := (a - center).angle()
	var end := (c - center).angle()
	# Umlaufsinn so, dass der Bogen durch b geht.
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross > 0.0:
		while end < start:
			end += TAU
	else:
		while end > start:
			end -= TAU
	var steps := maxi(int(absf(end - start) * r / 4.0), 4)
	var out := PackedVector2Array()
	for s in range(steps + 1):
		var ang := lerpf(start, end, float(s) / float(steps))
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


func _catmull_path(cp: PackedVector2Array) -> PackedVector2Array:
	# Catmull-Rom (selten). Randpunkte gespiegelt.
	var out := PackedVector2Array()
	var n := cp.size()
	for i in range(n - 1):
		var p0 := cp[maxi(i - 1, 0)]
		var p1 := cp[i]
		var p2 := cp[mini(i + 1, n - 1)]
		var p3 := cp[mini(i + 2, n - 1)]
		var steps := maxi(int(p1.distance_to(p2) / 4.0), 3)
		for s in range(steps + 1):
			var t := float(s) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (
				(2.0 * p1)
				+ (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


func _trim_to_length(raw: PackedVector2Array, target: float) -> PackedVector2Array:
	if raw.size() < 2 or target <= 0.0:
		return raw
	var out := PackedVector2Array()
	out.append(raw[0])
	var acc := 0.0
	for i in range(1, raw.size()):
		var seg := raw[i - 1].distance_to(raw[i])
		if seg <= 0.0001:
			continue
		if acc + seg >= target:
			out.append(raw[i - 1].lerp(raw[i], (target - acc) / seg))
			return out
		acc += seg
		out.append(raw[i])
	# Falls die abgetastete Kurve kuerzer ist: entlang der letzten Richtung strecken.
	if acc < target and out.size() >= 2:
		var dir := (out[out.size() - 1] - out[out.size() - 2]).normalized()
		out.append(out[out.size() - 1] + dir * (target - acc))
	return out
