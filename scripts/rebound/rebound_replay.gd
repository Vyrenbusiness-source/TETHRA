class_name ReboundReplay
extends RefCounted

## Rebound-Replays: Eingabe-Liste [{t, lane, down}] wie Mania (exakte Zeitstempel),
## je Map+Difficulty in user://replays/rebound/<md5>.json, getrennt vom Mania-Replay
## (ReplayStore kennt den Modus nicht). Dateiformat wie ReplayStore: {meta, events}.
## Dazu der Bot (Autoplay, Multiplayer-Bot, Tests).

const MODE := "rebound"
const DIR := "user://replays/rebound"


static func path_for(osz_path: String, version: String) -> String:
	return "%s/%s.json" % [DIR, ReplayStore.key(osz_path, version)]


static func exists(osz_path: String, version: String) -> bool:
	return FileAccess.file_exists(path_for(osz_path, version))


static func save(osz_path: String, version: String, events: Array, meta: Dictionary) -> void:
	if events.size() <= 1:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(path_for(osz_path, version), FileAccess.WRITE)
	if f == null:
		return
	var m := meta.duplicate()
	m["mode"] = MODE
	f.store_string(JSON.stringify({"meta": m, "events": events}))
	f.close()


## {meta, events} oder {}.
static func load_replay(osz_path: String, version: String) -> Dictionary:
	var p := path_for(osz_path, version)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("events"):
		return parsed
	return {}


## Sind die Events brauchbar (Dictionaries mit t, lane, down)?
static func replay_ok(events: Array) -> bool:
	if events.is_empty():
		return false
	for e in events:
		if not (e is Dictionary) or not e.has("t") or not e.has("lane") or not e.has("down"):
			return false
	return true


## Bot: Taste exakt zur Notenzeit, Holds bis zum Ende, sonst 40 ms (nie laenger als
## bis kurz vor der naechsten Note derselben Spalte). jitter_ms > 0: gleichverteilter
## Zeitfehler (deterministisch aus seed); skip_every > 0 laesst jede n-te Note aus.
static func bot_plan(bm: Beatmap, seed: int = 1, jitter_ms: float = 0.0, skip_every: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var objs := bm.hit_objects
	var next_in_col := {}
	var next_t: Array = []
	next_t.resize(objs.size())
	for i in range(objs.size() - 1, -1, -1):
		var n := objs[i] as ManiaNote
		next_t[i] = float(next_in_col.get(n.column, 1e12))
		next_in_col[n.column] = n.time
	var out: Array = []
	for i in objs.size():
		if skip_every > 0 and (i + 1) % skip_every == 0:
			continue
		var n := objs[i] as ManiaNote
		var dt := rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0
		var du := rng.randf_range(-jitter_ms, jitter_ms) if jitter_ms > 0.0 else 0.0
		var t := int(round(n.time + dt))
		var up := int(round(n.end_time() + du)) if n.is_hold else t + 40
		up = maxi(up, t + 8)
		up = mini(up, int(next_t[i]) - 3) if next_t[i] < 1e11 else up
		up = maxi(up, t + 1)
		out.append({"t": t, "lane": n.column, "down": true, "o": 1})
		out.append({"t": up, "lane": n.column, "down": false, "o": 0})
	out.sort_custom(func(a, b):
		if a.t != b.t:
			return a.t < b.t
		return a.o < b.o)
	for e in out:
		e.erase("o")
	return out
