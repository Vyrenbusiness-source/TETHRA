class_name ReplayStore
extends RefCounted

## Replays: pro Map+Difficulty wird der letzte Lauf gespeichert — als reine
## Input-Liste [{t, lane, down}] mit exakten Judgement-Zeitstempeln. Die
## Wiedergabe speist dieselben Events zeitgenau wieder in den ManiaCore ein.
##
## Modus: "mania" (Standard, user://replays/<md5>.json, Format unveraendert),
## "orbit" (bester Orbit-Lauf, user://replays/orbit/<md5>.json) oder
## "orbit_last" (letzter Orbit-Lauf, user://replays/orbit/last/<md5>.json).
## Orbit-Events sind kompakt [t, code, a] (OrbitCore.EV_*), meta.mode =
## "orbit". Alles liegt getrennt: ein Orbit-Lauf ueberschreibt nie das
## Mania-Replay derselben Diff.

const DIR := "user://replays"
const MODE_ORBIT_BEST := "orbit"
const MODE_ORBIT_LAST := "orbit_last"
## Rally/Dirigent wie Orbit: je Modus bester ("rally") und letzter Lauf ("rally_last").
const MODE_RALLY_BEST := "rally"
const MODE_RALLY_LAST := "rally_last"
const MODE_DIRIGENT_BEST := "dirigent"
const MODE_DIRIGENT_LAST := "dirigent_last"
## Trace/Rebound (Mania-4K-Wertung, Mania-Events [t, lane, down]) ebenso getrennt.
const MODE_TRACE_BEST := "trace"
const MODE_TRACE_LAST := "trace_last"
const MODE_REBOUND_BEST := "rebound"
const MODE_REBOUND_LAST := "rebound_last"
## Spielmodi mit eigener Ablage (bester + letzter Lauf); Mania bleibt im alten Ordner.
const OWN_DIR_MODES := ["orbit", "rally", "dirigent", "trace", "rebound"]


## Replay-Schluessel (= Dateiname ohne .json, auch fuer --clip <md5>).
static func key(osz_path: String, version: String) -> String:
	return ("%s|%s" % [osz_path.get_file(), version]).md5_text()


## Ordner je Modus (Mania bleibt im alten Ordner).
static func dir_for(mode: String = "mania") -> String:
	match mode:
		MODE_ORBIT_BEST: return DIR + "/orbit"
		MODE_ORBIT_LAST: return DIR + "/orbit/last"
		MODE_RALLY_BEST: return DIR + "/rally"
		MODE_RALLY_LAST: return DIR + "/rally/last"
		MODE_DIRIGENT_BEST: return DIR + "/dirigent"
		MODE_DIRIGENT_LAST: return DIR + "/dirigent/last"
		MODE_TRACE_BEST: return DIR + "/trace"
		MODE_TRACE_LAST: return DIR + "/trace/last"
		MODE_REBOUND_BEST: return DIR + "/rebound"
		MODE_REBOUND_LAST: return DIR + "/rebound/last"
	return DIR


static func is_orbit(mode: String) -> bool:
	return mode == MODE_ORBIT_BEST or mode == MODE_ORBIT_LAST


## Spielmodus hinter einem Replay-Modus: "mania", "orbit", "rally", "dirigent", "trace", "rebound".
static func base_mode(mode: String) -> String:
	return mode.trim_suffix("_last") if mode != "mania" else "mania"


## Replay-Modus fuer den besten bzw. letzten Lauf eines Spielmodus.
static func best_mode_of(game_mode: String) -> String:
	return game_mode if game_mode in OWN_DIR_MODES else "mania"


static func last_mode_of(game_mode: String) -> String:
	return game_mode + "_last" if game_mode in OWN_DIR_MODES else "mania"


static func path_for_key(md5: String, mode: String = "mania") -> String:
	return "%s/%s.json" % [dir_for(mode), md5]


static func _path(osz_path: String, version: String, mode: String = "mania") -> String:
	return path_for_key(key(osz_path, version), mode)


static func exists(osz_path: String, version: String, mode: String = "mania") -> bool:
	return FileAccess.file_exists(_path(osz_path, version, mode))


static func save(osz_path: String, version: String, events: Array, meta: Dictionary,
		mode: String = "mania") -> void:
	if events.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_for(mode)))
	var f := FileAccess.open(_path(osz_path, version, mode), FileAccess.WRITE)
	if f == null:
		return
	var m := meta
	if base_mode(mode) != "mania":
		m = meta.duplicate()
		m["mode"] = base_mode(mode)
	f.store_string(JSON.stringify({ "meta": m, "events": events }))
	f.close()


## Liefert { meta: Dictionary, events: Array } oder {}.
static func load_replay(osz_path: String, version: String, mode: String = "mania") -> Dictionary:
	return load_key(key(osz_path, version), mode)


## Wie load_replay, aber ueber den Schluessel (Clip-Prozess).
static func load_key(md5: String, mode: String = "mania") -> Dictionary:
	var path := path_for_key(md5, mode)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("events"):
		return parsed
	return {}
