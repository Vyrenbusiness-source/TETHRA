class_name OrbitPath
extends RefCounted

## Bahnformen des Orbit-Spielkopfs. Der Kopf laeuft pro Takt einmal die
## geschlossene Bahn ab, mit KONSTANTER Bahngeschwindigkeit (Bogenlaenge
## parametrisiert, nicht der Winkel). Alle Formen beginnen am selben Punkt
## links (-1, 0) = Takt-Eins, darum springt der Kopf beim Formwechsel nie.
## Der Kopf laeuft gegen den Uhrzeigersinn: die linke Seite der Laufrichtung
## ist beim Kreis innen (Spur A), die rechte aussen (Spur B).
##
## Koordinaten: "Bahn-Einheiten", y nach unten (Bildschirm). Die Ansicht
## rechnet mit Faktor OrbitView.path_scale() in Pixel um.

enum { CIRCLE, ELLIPSE, EIGHT, ROSE3, ROSE4 }
const COUNT := 5
const NAMES: Array[String] = ["CIRCLE", "ELLIPSE", "EIGHT", "ROSE3", "ROSE4"]
## Folge-Anspruch je Form (Faktor auf das Kopftempo, siehe OrbitConverter.stars):
## Kreis = 1, mehr Kurven = mehr Richtungswechsel pro Strecke.
const CURVE := [1.0, 1.08, 1.3, 1.45, 1.6]
## Abstand der beiden Spuren zur Bahnlinie (Bahn-Einheiten, je Seite).
const LANE_OFF := 0.075
const STEPS := 720

static var _cum: Array = []      # je Form: kumulierte Bogenlaenge (0..1) an STEPS+1 Stuetzstellen
static var _len: Array = []      # je Form: Gesamtlaenge in Bahn-Einheiten


## Punkt der Form bei Kurvenparameter s in [0, 1] (NICHT bogenlaengentreu).
static func raw(shape: int, s: float) -> Vector2:
	var th := TAU * s
	match shape:
		ELLIPSE:
			return Vector2(-cos(th), sin(th) * 0.62)
		EIGHT:
			# Liegende Acht (Gerono-Lemniskate): Kreuzung in der Mitte.
			return Vector2(-cos(th), sin(th) * cos(th) * 1.15)
		ROSE3:
			var ph := PI * s
			var r := cos(3.0 * ph)
			return Vector2(-r * cos(ph), r * sin(ph)) * 0.92
		ROSE4:
			var ph2 := TAU * s
			var r2 := cos(2.0 * ph2)
			return Vector2(-r2 * cos(ph2), r2 * sin(ph2)) * 0.92
		_:
			return Vector2(-cos(th), sin(th)) * 0.78


static func _build(shape: int) -> void:
	while _cum.size() < COUNT:
		_cum.append(PackedFloat32Array())
		_len.append(0.0)
	var t := PackedFloat32Array()
	t.resize(STEPS + 1)
	var acc := 0.0
	var prev := raw(shape, 0.0)
	t[0] = 0.0
	for i in range(1, STEPS + 1):
		var p := raw(shape, float(i) / float(STEPS))
		acc += p.distance_to(prev)
		prev = p
		t[i] = acc
	_len[shape] = acc
	for i in STEPS + 1:
		t[i] = t[i] / maxf(acc, 1e-9)
	_cum[shape] = t


static func _table(shape: int) -> PackedFloat32Array:
	if _cum.size() < COUNT or (_cum[shape] as PackedFloat32Array).is_empty():
		_build(shape)
	return _cum[shape]


## Gesamtlaenge der Bahn in Bahn-Einheiten.
static func length(shape: int) -> float:
	_table(shape)
	return float(_len[shape])


## Kurvenparameter s zur Bogenlaengen-Phase f in [0, 1).
static func _param(shape: int, f: float) -> float:
	var t := _table(shape)
	var x := fposmod(f, 1.0)
	var lo := 0
	var hi := STEPS
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if t[mid] <= x:
			lo = mid
		else:
			hi = mid
	var span := t[hi] - t[lo]
	var u := 0.0 if span <= 0.0 else (x - t[lo]) / span
	return (float(lo) + u) / float(STEPS)


## Ort auf der Bahn zur Phase f in [0, 1) (Anteil der Bahnlaenge = Anteil des Takts).
static func pos(shape: int, f: float) -> Vector2:
	return raw(shape, _param(shape, f))


## Einheits-Laufrichtung an Phase f.
static func tangent(shape: int, f: float) -> Vector2:
	var d := 0.002
	var a := pos(shape, f - d)
	var b := pos(shape, f + d)
	var v := b - a
	return v.normalized() if v.length() > 1e-9 else Vector2.RIGHT


## Linke Seite der Laufrichtung (Spur A) als Einheitsvektor.
static func left(shape: int, f: float) -> Vector2:
	var t := tangent(shape, f)
	return Vector2(t.y, -t.x)


## Ort der Spur lane (0 = A links, 1 = B rechts) an Phase f.
static func lane_pos(shape: int, f: float, lane: int) -> Vector2:
	var side := 1.0 if lane == 0 else -1.0
	return pos(shape, f) + left(shape, f) * (LANE_OFF * side)
