class_name ReboundAntiMash
extends RefCounted

## Rebound Anti-Mash: duenne Schicht vor ManiaCore (ManiaCore bleibt unveraendert).
## Live, Replay und Bot gehen ueber dieselbe Funktion (rebound_game.gd).

## Replay-Regelversion: 2 = Anti-Mash.
const REPLAY_RULES := 2


static func marker() -> Dictionary:
	return {"t": -1.0, "lane": -1, "down": false, "rules": REPLAY_RULES}


## Replays ohne Regel-Marke oder mit anderer Version passen nicht zu den Regeln.
static func replay_current(events: Array) -> bool:
	return not events.is_empty() and events[0] is Dictionary 			and int(events[0].get("rules", 0)) == REPLAY_RULES


## Anti-Mash: Druck auf Spalte lane ohne Note im Miss-Fenster, waehrend eine andere
## Spalte eine ungewertete Note im 50er-Fenster hat: diese Note (die naechste) ist
## sofort Miss. Gibt deren Index zurueck, sonst -1. Druck ohne Note irgendwo = nichts.
static func wrong_key_check(core: ManiaCore, lane: int, t: float) -> int:
	if core == null or core.beatmap == null or lane < 0 or lane >= core.columns:
		return -1
	for c in core.columns:
		core._expire_lane(c, t)
	if core._broken_hold[lane] >= 0:
		return -1
	if core._lane_head[lane] < core._lane_notes[lane].size():
		var own: int = core._lane_notes[lane][core._lane_head[lane]]
		if t - core.beatmap.hit_objects[own].time >= -core.w_miss:
			return -1
	var victim := -1
	var best := INF
	for c in core.columns:
		if c == lane or core._lane_head[c] >= core._lane_notes[c].size():
			continue
		var idx: int = core._lane_notes[c][core._lane_head[c]]
		var dt := absf(t - core.beatmap.hit_objects[idx].time)
		if dt <= core.w50 and dt < best:
			best = dt
			victim = idx
	if victim >= 0:
		core._miss(victim, "WRONG")
	return victim


