class_name OrbitNote
extends RefCounted

## Ein Ziel im Orbit-Modus (Taktkreis): Taktposition als Winkel + Ring.
## Der Winkel ist der Winkel der Hand (Zeiger) zur Trefferzeit: 360 Grad x
## Anteil des Takts. speed = Drehtempo der Hand in Grad/ms (0 = unbekannt,
## dann gilt das alte Verhalten: Ziel steht still bzw. laeuft auf dem Bogen).
## Tap: end_ms == time_ms, end_angle_deg == angle_deg.
## Bogen (is_arc): Taste ab time_ms halten, der Spitze von angle_deg nach
## end_angle_deg mit konstanter Winkelgeschwindigkeit bis end_ms folgen.
##
## Winkel: 0 = oben, im Uhrzeigersinn steigend. angle_deg liegt in [0, 360).
## end_angle_deg ist NICHT auf 0-360 gefaltet: end_angle_deg - angle_deg ist
## der vorzeichenbehaftete Bogen (+ = im Uhrzeigersinn), damit Bogen ueber
## 0 Grad eindeutig bleiben (z. B. 350 -> 410 = 60 Grad im Uhrzeigersinn).

var time_ms: float = 0.0
var end_ms: float = 0.0
var angle_deg: float = 0.0
var end_angle_deg: float = 0.0
## 0 = innerer Ring (Taste A), 1 = aeusserer Ring (Taste B).
var ring: int = 0
var is_arc: bool = false
## Drehtempo der Hand an dieser Note (Grad/ms, 360 / Taktlaenge); 0 = unbekannt.
var speed: float = 0.0
## Index der Quell-Note in beatmap.hit_objects (-1 = keine Quelle).
var source_index: int = -1


static func make(p_time: float, p_angle: float, p_ring: int, p_source: int = -1) -> OrbitNote:
	var n := OrbitNote.new()
	n.time_ms = p_time
	n.end_ms = p_time
	n.angle_deg = wrap_deg(p_angle)
	n.end_angle_deg = n.angle_deg
	n.ring = p_ring
	n.source_index = p_source
	return n


static func make_arc(p_time: float, p_end: float, p_angle: float, p_span: float,
		p_ring: int, p_source: int = -1) -> OrbitNote:
	var n := make(p_time, p_angle, p_ring, p_source)
	n.end_ms = maxf(p_end, p_time)
	n.end_angle_deg = n.angle_deg + p_span
	n.is_arc = true
	return n


## Vorzeichenbehaftete Bogenlaenge in Grad (+ = im Uhrzeigersinn, 0 bei Tap).
func span_deg() -> float:
	return end_angle_deg - angle_deg


func duration_ms() -> float:
	return end_ms - time_ms


## Winkel der Bogen-Spitze zur Zeit t_ms in [0, 360) (vor dem Kopf = Kopf,
## nach dem Ende = Ende). Bei Taps immer angle_deg.
func angle_at(t_ms: float) -> float:
	if not is_arc or end_ms <= time_ms:
		return angle_deg
	var f := clampf((t_ms - time_ms) / (end_ms - time_ms), 0.0, 1.0)
	return wrap_deg(angle_deg + span_deg() * f)


## Winkel der Hand zur Zeit t_ms (auch vor/nach der Note, linear mit speed).
## Ohne speed wie angle_at. Gegen diesen Winkel wird gezielt.
func pointer_at(t_ms: float) -> float:
	if speed == 0.0:
		return angle_at(t_ms)
	return wrap_deg(angle_deg + speed * (t_ms - time_ms))


## Winkel auf [0, 360) falten.
static func wrap_deg(a: float) -> float:
	var w := fposmod(a, 360.0)
	return 0.0 if w >= 360.0 else w


## Kuerzester Winkelabstand von a nach b in (-180, 180] (+ = im Uhrzeigersinn).
static func delta_deg(a: float, b: float) -> float:
	var d := fposmod(b - a + 180.0, 360.0) - 180.0
	return 180.0 if d <= -180.0 else d


## Betrag des kuerzesten Winkelabstands (0..180).
static func dist_deg(a: float, b: float) -> float:
	return absf(delta_deg(a, b))
