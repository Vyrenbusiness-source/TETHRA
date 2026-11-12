class_name RallyFlight
extends RefCounted

## Rally v2: Flugbahn eines Balls (rein optisch, nie Teil der Wertung).
## Tischkoordinaten: x quer -1..1 (Zonenmitte = zone_x), y Hoehe ueber der Tischplatte in
## Metern (Ballmitte), z 1 = Gegner .. 0 = deine Schlaeger-Linie. Der Ball faellt bei
## z = Z_LAND auf deine Tischhaelfte (landing_time) und kommt zur Notenzeit bei z = 0 an.
## Konstante Flugzeit: u = (t - launch) / (t_note - launch), z = 1 - u.

const BOUNCE_U := 0.75
const Z_LAND := 0.25
const Y_RACKET := 0.16
const Y_LAUNCH := 0.24
const RETURN_MS := 520.0
const LOB_GAP_MS := 900.0
const DRIVE_GAP_MS := 110.0
const CURVE_MIN_JUMP := 2.0
const CURVE_SIDE := 0.30


## Zonenzahl 3 oder 4 (Settings.rally_zones, Standard 3).
static func zone_count() -> int:
	var v: Variant = Settings.get("rally_zones")
	if v != null:
		return clampi(int(v), 3, 4)
	# Debug-Ersatz bis Settings.rally_zones existiert: --rally-zones=4.
	for a in OS.get_cmdline_args():
		if a.begins_with("--rally-zones="):
			return clampi(a.trim_prefix("--rally-zones=").to_int(), 3, 4)
	return 3


## Quer-Mitte einer Zone (Bruchteile erlaubt, z. B. 1.5 = zwischen Zone 1 und 2) bei
## `count` gleich breiten Zonen (count <= 0: aktuelle Einstellung).
static func zone_x(zone: float, count: int = -1) -> float:
	var n := count if count > 0 else zone_count()
	return (clampf(zone, 0.0, float(n - 1)) + 0.5) * 2.0 / float(n) - 1.0


## Zonen eines Schlags. Platzhalter fuer Charts ohne zones: key * (n-1), Schmetterball 0 und n-1.
static func zones_of(s: RallyChart.Shot) -> PackedInt32Array:
	if not s.zones.is_empty():
		return s.zones
	var n := zone_count()
	if s.smash:
		return PackedInt32Array([0, n - 1])
	return PackedInt32Array([s.key * (n - 1)])


static func zone_mean(s: RallyChart.Shot) -> float:
	var zs := zones_of(s)
	var sum := 0.0
	for z in zs:
		sum += float(z)
	return sum / float(zs.size())


static func shot_x(s: RallyChart.Shot) -> float:
	return zone_x(zone_mean(s))


## Setzt launch = t - flight_ms, arc nach Abstand zur vorigen Note (Lob vs. Drive)
## und curve bei Zonensprung >= 2 (Seitwaerts-Effet).
static func finalize(shots: Array[RallyChart.Shot], flight_ms: float) -> void:
	for j in shots.size():
		var s := shots[j]
		s.launch = s.t - flight_ms
		var gap := 1500.0
		var jump := 0.0
		if j > 0:
			gap = s.t - shots[j - 1].t
			jump = zone_mean(s) - zone_mean(shots[j - 1])
		var f := clampf((gap - DRIVE_GAP_MS) / (LOB_GAP_MS - DRIVE_GAP_MS), 0.0, 1.0)
		f = f * f * (3.0 - 2.0 * f)
		s.arc = lerpf(0.05, 1.0, f)
		s.curve = clampf(jump / 3.0, -1.0, 1.0) if absf(jump) >= CURVE_MIN_JUMP else 0.0


## Quer-Position beim Gegnerschlag (die Flugbahn laeuft von hier zur Zonenmitte).
static func launch_x(s: RallyChart.Shot) -> float:
	return shot_x(s) * 0.5


static func landing_time(s: RallyChart.Shot) -> float:
	return s.launch + BOUNCE_U * (s.t - s.launch)


## Ball zur Zeit t. Vor launch steht er beim Gegner, nach t fliegt er hinter deiner
## Schlaeger-Linie weiter (z < 0, faellt) - die Ansicht blendet ihn dann aus.
static func ball_pos(s: RallyChart.Shot, t: float) -> Vector3:
	var span := maxf(s.t - s.launch, 1.0)
	var u := maxf((t - s.launch) / span, 0.0)
	var xl := shot_x(s)
	var z := 1.0 - u
	if u >= 1.0:
		var d := u - 1.0
		return Vector3(xl, maxf(Y_RACKET - 2.2 * d * d, -0.25), z)
	if u >= BOUNCE_U:
		var s2 := (u - BOUNCE_U) / (1.0 - BOUNCE_U)
		var up := 1.0 - (1.0 - s2) * (1.0 - s2)
		return Vector3(xl, Y_RACKET * up, z)
	var sp := u / BOUNCE_U
	var e := sp * sp * (3.0 - 2.0 * sp)
	var x := lerpf(launch_x(s), xl, e) + s.curve * CURVE_SIDE * sin(PI * sp)
	var h := 0.10 + 0.50 * s.arc
	var y := Y_LAUNCH * (1.0 - sp) + 4.0 * h * sp * (1.0 - sp)
	return Vector3(x, y, z)


## Rueckschlag nach dem Treffer (nur Optik): vom Treffpunkt `from` zum Gegner, mit
## Aufsetzer auf dessen Haelfte. dt_ms = Zeit seit dem Treffer.
static func return_pos(from: Vector3, dt_ms: float) -> Vector3:
	var s := clampf(dt_ms / RETURN_MS, 0.0, 1.0)
	var z := lerpf(from.z, 1.02, s)
	var x := lerpf(from.x, from.x * 0.4, s)
	var y := 0.0
	if s < 0.6:
		var a := s / 0.6
		y = from.y * (1.0 - a) + 4.0 * 0.14 * a * (1.0 - a)
	else:
		var b := (s - 0.6) / 0.4
		y = Y_LAUNCH * (1.0 - (1.0 - b) * (1.0 - b))
	return Vector3(x, y, z)
