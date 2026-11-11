class_name DirigentReplay
extends RefCounted

## Dirigent-Replays: Ereignis-Log des DirigentCore ([t, code, a, b]) je Map +
## Difficulty, getrennt von Mania/Orbit unter user://replays/dirigent/. "last" =
## letzter Lauf, "best" = bester Lauf. Schluessel wie ReplayStore.key.

const MODE := "dirigent"
const DIR := "user://replays/dirigent"


static func _path(osz_path: String, version: String, slot: String) -> String:
	return "%s/%s_%s.json" % [DIR, ReplayStore.key(osz_path, version), slot]


static func exists(osz_path: String, version: String, slot: String = "last") -> bool:
	return FileAccess.file_exists(_path(osz_path, version, slot))


static func save(osz_path: String, version: String, events: Array, meta: Dictionary,
		slot: String = "last") -> void:
	if events.size() <= 1:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(_path(osz_path, version, slot), FileAccess.WRITE)
	if f == null:
		return
	var m := meta.duplicate()
	m["mode"] = MODE
	f.store_string(JSON.stringify({"meta": m, "events": events}))
	f.close()


## {meta, events} oder {}.
static func load_replay(osz_path: String, version: String, slot: String = "last") -> Dictionary:
	var path := _path(osz_path, version, slot)
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


## Passt das Log zu den aktuellen Regeln? (Regel-Marke steht vorn.)
static func is_current(events: Array) -> bool:
	for e in events:
		if e is Array and e.size() >= 3 and int(e[1]) == DirigentCore.EV_RULES:
			return int(e[2]) == DirigentCore.REPLAY_RULES
	return false


## Replay fuer die naechste Spielszene bereitstellen (Song-Auswahl/Ergebnis).
static func arm(events: Array) -> void:
	GameSession.is_replay = true
	GameSession.replay_events = events.duplicate()
	GameSession.replay_mode = MODE
