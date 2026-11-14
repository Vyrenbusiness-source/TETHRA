class_name MarathonStore
extends RefCounted

## Marathon-Wertung (lokal): eigene Rangliste je Marathon-Laenge (n3/n5/n8 =
## Anzahl Maps, m5/m10/m20 = Minuten) und die Replays ganzer Marathons.
## Nichts davon geht an den Server (Online-Schluessel siehe ONLINE_MODE, vorerst
## nicht senden).
##
## Datei: user://marathon_scores.cfg, Section = Laengen-Schluessel, Key "runs" =
## Array der Eintraege (bester zuerst, hoechstens MAX_ENTRIES).
## Replays: user://replays/marathon/<id>.json = {meta, events}, meta.marathon =
## Plan inkl. Zeitachse (exakt nachspielbar).

const PATH := "user://marathon_scores.cfg"
const REPLAY_DIR := "user://replays/marathon"
const MAX_ENTRIES := 50
## Eigener Modus-Schluessel fuer den Server (Bericht), "ranked": false.
const ONLINE_MODE := "mania_marathon"

## Tests setzen hier eigene Pfade (nie gegen die echten Nutzerdaten).
static var path_override := ""
static var replay_dir_override := ""


static func path() -> String:
	return path_override if path_override != "" else PATH


static func replay_dir() -> String:
	return replay_dir_override if replay_dir_override != "" else REPLAY_DIR


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return int(a.get("score", 0)) > int(b.get("score", 0))
	return str(a.get("date", "")) < str(b.get("date", ""))


## Eintrag speichern. Liefert {rank (1-basiert), is_new_best, previous}.
static func submit(length: String, entry: Dictionary) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(path())
	var runs: Array = cfg.get_value(length, "runs", [])
	var prev: Dictionary = runs[0] if not runs.is_empty() else {}
	runs.append(entry)
	runs.sort_custom(_better)
	var rank := runs.find(entry) + 1
	if runs.size() > MAX_ENTRIES:
		runs.resize(MAX_ENTRIES)
	cfg.set_value(length, "runs", runs)
	cfg.save(path())
	return {"rank": rank, "is_new_best": rank == 1, "previous": prev}


static func top(length: String, n: int = 10) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path()) != OK:
		return []
	var runs: Array = cfg.get_value(length, "runs", [])
	return runs.slice(0, n)


static func best(length: String) -> Dictionary:
	var t := top(length, 1)
	return t[0] if not t.is_empty() else {}


## Online-Bericht (wird NICHT gesendet): Felder fuer den Server-Betreiber.
static func online_payload(length: String, entry: Dictionary, maps: Array) -> Dictionary:
	var ids: Array = []
	for m in maps:
		ids.append({"osz": str(m.get("osz", "")).get_file(), "version": str(m.get("version", "")),
			"stars": float(m.get("stars", 0.0))})
	return {
		"mode": ONLINE_MODE, "ranked": false, "length": length,
		"score": int(entry.get("score", 0)), "accuracy": float(entry.get("accuracy", 0.0)),
		"max_combo": int(entry.get("max_combo", 0)), "n_miss": int(entry.get("n_miss", 0)),
		"failed": bool(entry.get("failed", false)), "maps": ids,
		"mods": entry.get("mods", []),
	}


# --- Replays -------------------------------------------------------------------------

static func replay_path(id: String) -> String:
	return "%s/%s.json" % [replay_dir(), id]


static func save_replay(id: String, events: Array, meta: Dictionary) -> bool:
	if events.is_empty() or id == "":
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(replay_dir()))
	var f := FileAccess.open(replay_path(id), FileAccess.WRITE)
	if f == null:
		return false
	# Volle Genauigkeit: die Zeitachse muss bitgleich zurueckkommen.
	f.store_string(JSON.stringify({"meta": meta, "events": events}, "", false, true))
	f.close()
	return true


static func load_replay(id: String) -> Dictionary:
	var p := replay_path(id)
	if id == "" or not FileAccess.file_exists(p):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	if parsed is Dictionary and parsed.has("events") and parsed.has("meta"):
		return parsed
	return {}


static func has_replay(id: String) -> bool:
	return id != "" and FileAccess.file_exists(replay_path(id))
