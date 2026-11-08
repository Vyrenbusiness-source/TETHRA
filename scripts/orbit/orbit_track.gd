class_name OrbitTrack
extends RefCounted

## Die Bahn eines Songs: Takt-Uhr + Plan der Bahnformen. Formen wechseln nur
## auf Takt-Eins; der Plan nennt Paare [Takt-Beginn ms, Form]. Der Spielkopf
## sitzt zur Zeit t auf pos(form(t), phase(t)). Alles rein aus Zeit abgeleitet,
## darum fuer Wertung, Ansicht und Replay identisch.

## Hoechste Kopfgeschwindigkeit (Bahn-Einheiten pro ms). Der Kreis bei
## MIN_BAR_MS = 1,2 s liegt knapp darunter; laengere Formen brauchen
## laengere Takte (siehe OrbitConverter.plan_shapes).
const MAX_SPEED := 0.0043
## Leichte Maps (Takt >= EASY_MIN_BAR_MS) bleiben ruhiger.
const MAX_SPEED_EASY := 0.0028

var clock: OrbitClock
## [[start_ms, shape], ...] aufsteigend; vor dem ersten Eintrag gilt der erste.
var plan: Array = []


static func fixed(p_clock: OrbitClock, shape: int = OrbitPath.CIRCLE) -> OrbitTrack:
	var tr := OrbitTrack.new()
	tr.clock = p_clock
	tr.plan = [[-INF, shape]]
	return tr


## Form zur Zeit t_ms.
func shape_at(t_ms: float) -> int:
	var k := 0
	var lo := 0
	var hi := plan.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(plan[mid][0]) <= t_ms:
			k = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return int(plan[k][1]) if not plan.is_empty() else OrbitPath.CIRCLE


## Form des naechsten Takts (fuer die Vorschau).
func next_shape_at(t_ms: float) -> int:
	return shape_at(clock.bar_end_at(t_ms) + 0.5)


## Wechselt die Form mit dem naechsten Takt-Eins?
func changes_next(t_ms: float) -> bool:
	return next_shape_at(t_ms) != shape_at(t_ms)


func head(t_ms: float) -> Vector2:
	return OrbitPath.pos(shape_at(t_ms), clock.phase_at(t_ms))


func lane_pos(t_ms: float, lane: int) -> Vector2:
	return OrbitPath.lane_pos(shape_at(t_ms), clock.phase_at(t_ms), lane)


## Kopfgeschwindigkeit (Bahn-Einheiten/ms) zur Zeit t_ms.
func speed_at(t_ms: float) -> float:
	return OrbitPath.length(shape_at(t_ms)) / clock.bar_ms_at(t_ms)


func max_speed_allowed() -> float:
	return MAX_SPEED
