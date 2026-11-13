class_name TraceRules
extends RefCounted

## Trace-Regel vor ManiaCore: Anti-Mash (falscher Knick). Rein, deterministisch, ohne Autoloads.

const CHORD_EPS := 2.0        ## ms: Noten so nah beieinander sind ein Akkord


## Trace-Regel vor ManiaCore (deterministisch, replay-faehig). Druck in Spalte `lane` ohne
## ungewertete Note im Miss-Fenster, waehrend eine andere Spalte eine ungewertete Note im
## 50er-Fenster hat = falscher Knick: diese Note (Akkord: alle Akkordnoten) sofort Miss.
## Druck ohne Note in irgendeinem Fenster = nichts. Gibt die verfehlten Noten-Indizes zurueck.
static func press(c: ManiaCore, lane: int, t: float) -> Array:
	if lane < 0 or lane >= c.columns:
		return []
	if c.lane_busy(lane):
		c.key_down(lane, t)
		return []
	var objs := c.beatmap.hit_objects
	var own := c.pending_head(lane, t)
	if own >= 0 and t - float(objs[own].time) >= -c.w_miss:
		c.key_down(lane, t)
		return []
	var targets: Array = []
	for col in c.columns:
		if col == lane:
			continue
		var idx := c.pending_head(col, t)
		if idx >= 0 and absf(t - float(objs[idx].time)) <= c.w50:
			targets.append(idx)
	if targets.is_empty():
		c.key_down(lane, t)
		return []
	var t0 := 1.0e18
	for idx in targets:
		t0 = minf(t0, float(objs[idx].time))
	var missed: Array = []
	for idx in targets:
		if float(objs[idx].time) <= t0 + CHORD_EPS:
			c.miss_note(int(idx), "WRONG")
			missed.append(idx)
	return missed


# ---------------------------------------------------------------------------
# Vorlauf (QA): Songstart und Kamera
# ---------------------------------------------------------------------------

const START_MS := 1900.0      ## Uhr startet mindestens so lange vor der ersten Note
const FAIR_MS := 600.0        ## Knoten bis so weit voraus muessen im Bild sein
const FAIR_RAMP_MS := 300.0   ## davor wird die Grenze weich angezogen (kein Kamerasprung)
const FAIR_SLACK := 700.0     ## Welt-px Spielraum am Anfang der Rampe
const KNOT_MARGIN := 64.0     ## Welt-px Rand fuer Pfeil und Tastenbuchstabe
const HEAD_MARGIN := 96.0     ## Welt-px Rand fuer den Kopf


## Vorlauf der Uhr vor Zeit 0: mindestens der AudioLeadIn der Map und genug, dass der volle
## Weg zur ersten Note sichtbar ist (auch ohne Audio, Retry, Replay, Mehrspieler).
static func lead_in_ms(first_t: float, audio_lead_ms: float) -> float:
	return maxf(audio_lead_ms, START_MS - first_t)


## Halbe Bildgroesse in Welt-px (die Ansicht skaliert auf 720 px Hoehe).
static func view_half(view_size: Vector2) -> Vector2:
	return view_size * 0.5 / maxf(view_size.y / 720.0, 0.1)


## Kamera so nachfuehren, dass der Kopf und jeder Knoten der naechsten FAIR_MS im Bild
## liegen. Ohne Zustand (gleiche Zeit = gleiche Kamera). `cam` ist die ruhige Kamera der
## Ansicht; sie bleibt, solange alles im Bild ist. Passt nicht alles hinein (sehr dichte
## Stellen), haben die zeitlich naeheren Knoten Vorrang.
static func fair_camera(path: TracePath, t: float, cam: Vector2, half: Vector2) -> Vector2:
	if path == null or path.knots.is_empty():
		return cam
	var head := path.head_pos(t)
	var hm := Vector2(maxf(half.x - HEAD_MARGIN, 1.0), maxf(half.y - HEAD_MARGIN, 1.0))
	var km := Vector2(maxf(half.x - KNOT_MARGIN, 1.0), maxf(half.y - KNOT_MARGIN, 1.0))
	var lo := head - hm
	var hi := head + hm
	var open_x := true
	var open_y := true
	var j := path.first_knot_from(t)
	while j < path.knots.size() and (open_x or open_y):
		var kn := path.knots[j]
		var dt := kn.t - t
		if dt > FAIR_MS + FAIR_RAMP_MS:
			break
		var slack := clampf((dt - FAIR_MS) / FAIR_RAMP_MS, 0.0, 1.0) * FAIR_SLACK
		if open_x:
			var a := kn.pos.x - km.x - slack
			var b := kn.pos.x + km.x + slack
			if a > hi.x:
				lo.x = hi.x
				open_x = false
			elif b < lo.x:
				hi.x = lo.x
				open_x = false
			else:
				lo.x = maxf(lo.x, a)
				hi.x = minf(hi.x, b)
		if open_y:
			var a2 := kn.pos.y - km.y - slack
			var b2 := kn.pos.y + km.y + slack
			if a2 > hi.y:
				lo.y = hi.y
				open_y = false
			elif b2 < lo.y:
				hi.y = lo.y
				open_y = false
			else:
				lo.y = maxf(lo.y, a2)
				hi.y = minf(hi.y, b2)
		j += 1
	return Vector2(clampf(cam.x, lo.x, hi.x), clampf(cam.y, lo.y, hi.y))
