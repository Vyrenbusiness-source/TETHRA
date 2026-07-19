class_name ReplayStore
extends RefCounted

## Replays: pro Map+Difficulty wird der letzte Lauf gespeichert — als reine
## Input-Liste [{t, lane, down}] mit exakten Judgement-Zeitstempeln. Die
## Wiedergabe speist dieselben Events zeitgenau wieder in den ManiaCore ein.

const DIR := "user://replays"


static func _path(osz_path: String, version: String) -> String:
	return "%s/%s.json" % [DIR, ("%s|%s" % [osz_path.get_file(), version]).md5_text()]


static func exists(osz_path: String, version: String) -> bool:
	return FileAccess.file_exists(_path(osz_path, version))


static func save(osz_path: String, version: String, events: Array, meta: Dictionary) -> void:
	if events.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(_path(osz_path, version), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({ "meta": meta, "events": events }))
	f.close()


## Liefert { meta: Dictionary, events: Array } oder {}.
static func load_replay(osz_path: String, version: String) -> Dictionary:
	var path := _path(osz_path, version)
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
