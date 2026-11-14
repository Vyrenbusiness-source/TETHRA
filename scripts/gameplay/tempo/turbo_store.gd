class_name TurboStore
extends RefCounted

## Lokale Turbo-Rangliste je Map+Diff (user://turbo_scores.json), sortiert nach
## erreichtem Hoechsttempo, dann Score. Getrennt von ScoreStore: Turbo-Laeufe
## zaehlen nie in die normale Mania-Liste und werden (vorerst) nicht gesendet.
## Online-Vorschlag fuer den Server: eigener Modus-Schluessel MODE_KEY.

const PATH := "user://turbo_scores.json"
const KEEP := 10
const MODE_KEY := "mania_turbo"


static func _load_all(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


static func _save_all(data: Dictionary, path: String = PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


## a vor b? Hoechsttempo absteigend, dann Score absteigend.
static func better(a: Dictionary, b: Dictionary) -> bool:
	var pa := float(a.get("peak", 1.0))
	var pb := float(b.get("peak", 1.0))
	if absf(pa - pb) > 0.001:
		return pa > pb
	return int(a.get("score", 0)) > int(b.get("score", 0))


## Lauf eintragen. entry: {peak, score, accuracy, date, pitch, failed}.
## Rueckgabe: Platz (1-basiert) oder 0, wenn nicht unter den besten KEEP.
static func submit(osz_path: String, version: String, entry: Dictionary, path: String = PATH) -> int:
	var all := _load_all(path)
	var k := ReplayStore.key(osz_path, version)
	var list: Array = all.get(k, [])
	list.append(entry)
	list.sort_custom(better)
	var rank := list.find(entry) + 1
	if list.size() > KEEP:
		list.resize(KEEP)
	all[k] = list
	_save_all(all, path)
	return rank if rank <= KEEP else 0


static func list_for(osz_path: String, version: String, path: String = PATH) -> Array:
	return _load_all(path).get(ReplayStore.key(osz_path, version), [])
