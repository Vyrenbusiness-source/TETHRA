class_name OrbitNote
extends RefCounted

## Ein Ziel im Orbit-Modus (Bahnen): Taktposition + Spur. angle_deg ist die
## Taktphase zur Trefferzeit: 360 x Anteil des Takts (0 = Takt-Eins). Wo das
## Ziel liegt, ergibt sich aus der Bahnform des Takts (shape, OrbitPath) und
## der Spur (ring). speed = Kopfgeschwindigkeit in Bahn-Einheiten/ms.
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
## Spur: 0 = A (links der Laufrichtung, innen), 1 = B (rechts, aussen).
var ring: int = 0
## Bahnform des Takts dieses Ziels (OrbitPath.CIRCLE ...), vom Konverter gesetzt.
var shape: int = 0
var is_arc: bool = false
## Kopfgeschwindigkeit an dieser Note (Bahn-Einheiten/ms); 0 = unbekannt.
var speed: float = 0.0
## Index der Quell-Note in beatmap.hit_objects (-1 = keine Quelle).
var source_index: int = -1

# --- Orbit "Satelliten" (docs/modes/orbit_satellit.md) -----------------------
# Die Felder oben (angle_deg, ring, shape, is_arc, speed) gehoeren zum alten
# Bahnen-Modell und fallen weg, sobald Core/Konverter/Ansicht umgestellt sind.

## Taste: 0 = A (kuehl, Scheibe), 1 = B (warm, Quadrat), 2 = Akzent (beide).
const KEY_A := 0
const KEY_B := 1
const KEY_ACCENT := 2
## Position im Feld (0..1 x 0..1, 4:3 wie osu! 512x384 normiert).
var pos: Vector2 = Vector2(0.5, 0.5)
var key: int = KEY_A
var is_hold: bool = false
## Halten: Feldpunkte, path[0] == pos; die Kugel laeuft mit konstanter Geschwindigkeit.
var path: PackedVector2Array = PackedVector2Array()
## Erscheint auf diesem Beat-Tick (ms).
var spawn_ms: float = 0.0
## Dauer einer Satelliten-Runde (ms): ein Beat, 2 Beats unter 450 ms, 4 unter 225 ms.
var lap_ms: float = 500.0
## Runden ab spawn_ms bis zum Treffer (Pips beim Erscheinen); 0 = nur eine Teilrunde.
var laps: int = 2
var _path_len: PackedFloat32Array = PackedFloat32Array()


static func make_target(p_time: float, p_pos: Vector2, p_key: int, p_source: int = -1) -> OrbitNote:
	var n := OrbitNote.new()
	n.time_ms = p_time
	n.end_ms = p_time
	n.pos = p_pos
	n.key = p_key
	n.ring = 1 if p_key == KEY_B else 0
	n.source_index = p_source
	return n


static func make_hold(p_time: float, p_end: float, p_path: PackedVector2Array, p_key: int,
		p_source: int = -1) -> OrbitNote:
	var start := p_path[0] if p_path.size() > 0 else Vector2(0.5, 0.5)
	var n := make_target(p_time, start, p_key, p_source)
	n.end_ms = maxf(p_end, p_time)
	n.path = p_path
	n.is_hold = p_path.size() >= 2 and n.end_ms > n.time_ms
	n.is_arc = n.is_hold
	n._build_lengths()
	return n


func _build_lengths() -> void:
	_path_len = PackedFloat32Array()
	var acc := 0.0
	_path_len.append(0.0)
	for i in range(1, path.size()):
		acc += path[i - 1].distance_to(path[i])
		_path_len.append(acc)


## Halten: Kugelposition zur Zeit t_ms (konstante Geschwindigkeit); sonst pos.
func pos_at(t_ms: float) -> Vector2:
	if not is_hold or path.size() < 2:
		return pos
	if _path_len.size() != path.size():
		_build_lengths()
	var total := _path_len[_path_len.size() - 1]
	if total <= 0.0:
		return pos
	var f := clampf((t_ms - time_ms) / maxf(end_ms - time_ms, 1.0), 0.0, 1.0)
	var want := total * f
	for i in range(1, path.size()):
		if _path_len[i] >= want:
			var seg := _path_len[i] - _path_len[i - 1]
			var k := 0.0 if seg <= 0.0 else (want - _path_len[i - 1]) / seg
			return path[i - 1].lerp(path[i], k)
	return path[path.size() - 1]


## Satellit: 0 = oben, im Uhrzeigersinn; gleichmaessig eine Runde je lap_ms, genau
## oben bei t = time_ms und danach oben stehend (kein Weiterlaufen, kein Sprung).
func satellite_deg(t_ms: float) -> float:
	if t_ms >= time_ms:
		return 0.0
	var lap := maxf(lap_ms, 1.0)
	return wrap_deg(360.0 - 360.0 * fposmod((time_ms - t_ms) / lap, 1.0))


## Verbleibende ganze Runden bis zum Treffer (0 in der letzten Runde).
func laps_left(t_ms: float) -> int:
	return maxi(int(floor((time_ms - t_ms) / maxf(lap_ms, 1.0))), 0)


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
