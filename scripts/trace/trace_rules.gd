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
