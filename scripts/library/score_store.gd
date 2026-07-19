class_name ScoreStore
extends RefCounted

## Persistente Bestwerte pro Map+Difficulty (user://scores.cfg).
## Key: "<osz-Dateiname>|<Difficulty-Version>". Unranked-Scores (AR-Override)
## werden gespeichert, aber separat markiert und ueberschreiben keine
## Ranked-Bestwerte.

const PATH := "user://scores.cfg"


## Speichert ein Ergebnis; liefert {is_new_best: bool, previous: Dictionary}.
static func submit(osz_file: String, version: String, result: Dictionary) -> Dictionary:
	var key := _key(osz_file, version)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var prev = cfg.get_value("scores", key, {})
	var prev_dict: Dictionary = prev if prev is Dictionary else {}
	var is_new_best := false
	var unranked := bool(result.get("unranked", false))
	var prev_unranked := bool(prev_dict.get("unranked", false))
	if result.get("failed", false):
		# Fails zaehlen nur die Play-Statistik hoch.
		pass
	elif prev_dict.is_empty():
		is_new_best = true
	elif prev_unranked and not unranked:
		is_new_best = true  # Ranked schlaegt Unranked immer
	elif unranked and not prev_unranked:
		is_new_best = false  # Unranked ueberschreibt Ranked nie
	else:
		is_new_best = int(result.get("score", 0)) > int(prev_dict.get("score", 0))
	if is_new_best:
		var entry := {
			"score": int(result.get("score", 0)),
			"accuracy": float(result.get("accuracy", 0.0)),
			"grade": str(result.get("grade", "D")),
			"max_combo": int(result.get("max_combo", 0)),
			"n_max": int(result.get("n_max", 0)),
			"n300": int(result.get("n300", 0)),
			"n200": int(result.get("n200", 0)),
			"n100": int(result.get("n100", 0)),
			"n50": int(result.get("n50", 0)),
			"n_miss": int(result.get("n_miss", 0)),
			"pp": float(result.get("pp", -1.0)),
			"unranked": unranked,
			"date": Time.get_datetime_string_from_system(),
		}
		cfg.set_value("scores", key, entry)
	var plays := int(cfg.get_value("plays", key, 0)) + 1
	cfg.set_value("plays", key, plays)
	cfg.save(PATH)
	return { "is_new_best": is_new_best, "previous": prev_dict }


const HISTORY_CAP := 20
const RECENT_CAP := 12


## Jeden abgeschlossenen Play zusaetzlich in History (pro Map) und Recent
## (global) ablegen. map_label = "Artist - Titel" fuer die Anzeige.
static func log_play(osz_file: String, version: String, map_label: String, result: Dictionary) -> void:
	var key := _key(osz_file, version)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var entry := {
		"score": int(result.get("score", 0)),
		"accuracy": float(result.get("accuracy", 0.0)),
		"grade": str(result.get("grade", "D")),
		"max_combo": int(result.get("max_combo", 0)),
		"pp": float(result.get("pp", -1.0)),
		"unranked": bool(result.get("unranked", false)),
		"failed": bool(result.get("failed", false)),
		"date": Time.get_datetime_string_from_system(),
	}
	var hist: Array = cfg.get_value("history", key, [])
	hist.append(entry)
	while hist.size() > HISTORY_CAP:
		hist.pop_front()
	cfg.set_value("history", key, hist)
	var recent_entry := entry.duplicate()
	recent_entry["map"] = map_label
	recent_entry["version"] = version
	recent_entry["osz_file"] = osz_file.get_file()
	var recent: Array = cfg.get_value("recent", "plays", [])
	recent.append(recent_entry)
	while recent.size() > RECENT_CAP:
		recent.pop_front()
	cfg.set_value("recent", "plays", recent)
	cfg.save(PATH)


## Top-N Scores einer Map+Diff (beste zuerst, Fails ausgenommen).
static func top_scores(osz_file: String, version: String, n: int = 5) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return []
	var hist: Array = cfg.get_value("history", _key(osz_file, version), [])
	var valid := hist.filter(func(e): return not bool(e.get("failed", false)))
	valid.sort_custom(func(a, b): return int(a.score) > int(b.score))
	return valid.slice(0, n)


## Letzte Plays (neueste zuerst).
## Global beste Bestwerte (nach pp sortiert) fuer die Profil-Ansicht.
## Jeder Eintrag bekommt "map" (Dateiname ohne .osz/Set-ID) und "version".
static func best_plays(n: int = 5) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return []
	if not cfg.has_section("scores"):
		return []
	var entries: Array = []
	for key in cfg.get_section_keys("scores"):
		var v = cfg.get_value("scores", key, {})
		if not (v is Dictionary) or v.is_empty():
			continue
		var e: Dictionary = (v as Dictionary).duplicate()
		var parts := str(key).split("|")
		var fname := parts[0].get_basename()
		# Fuehrende Set-ID im Dateinamen ("123456 Artist - Titel") abschneiden.
		var words := fname.split(" ")
		if words.size() > 1 and words[0].is_valid_int():
			fname = " ".join(words.slice(1))
		e["map"] = fname
		e["version"] = parts[1] if parts.size() > 1 else ""
		e["osz_file"] = parts[0]
		entries.append(e)
	entries.sort_custom(func(a, b): return float(a.get("pp", -1.0)) > float(b.get("pp", -1.0)))
	return entries.slice(0, n)


## Meistgespielte Maps (Play-Anzahl absteigend) inkl. Bestwert-Infos.
static func most_played(n: int = 5) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section("plays"):
		return []
	var entries: Array = []
	for key in cfg.get_section_keys("plays"):
		var count := int(cfg.get_value("plays", key, 0))
		if count <= 0:
			continue
		var parts := str(key).split("|")
		var fname := parts[0].get_basename()
		var words := fname.split(" ")
		if words.size() > 1 and words[0].is_valid_int():
			fname = " ".join(words.slice(1))
		var best_v = cfg.get_value("scores", key, {})
		var best_e: Dictionary = best_v if best_v is Dictionary else {}
		entries.append({
			"osz_file": parts[0],
			"version": parts[1] if parts.size() > 1 else "",
			"map": fname,
			"count": count,
			"grade": str(best_e.get("grade", "")),
			"pp": float(best_e.get("pp", -1.0)),
			"accuracy": float(best_e.get("accuracy", 0.0)),
			"date": str(best_e.get("date", "")),
		})
	entries.sort_custom(func(a, b): return int(a.count) > int(b.count))
	return entries.slice(0, n)


static func recent_plays(n: int = 8) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return []
	var recent: Array = cfg.get_value("recent", "plays", [])
	recent.reverse()
	return recent.slice(0, n)


## Profil-pp wie osu: Bestwerte aller Maps nach pp sortiert, gewichtet
## mit 0.95^i aufsummiert.
static func profile_pp() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0.0
	if not cfg.has_section("scores"):
		return 0.0
	var pps: Array[float] = []
	for key in cfg.get_section_keys("scores"):
		var e = cfg.get_value("scores", key, {})
		if e is Dictionary and float(e.get("pp", -1.0)) > 0.0 and not bool(e.get("unranked", false)):
			pps.append(float(e.pp))
	pps.sort()
	pps.reverse()
	var total := 0.0
	for i in pps.size():
		total += pps[i] * pow(0.95, i)
	return total


## Gesamtzahl aller Plays.
static func total_plays() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0
	if not cfg.has_section("plays"):
		return 0
	var total := 0
	for key in cfg.get_section_keys("plays"):
		total += int(cfg.get_value("plays", key, 0))
	return total


## Bestwert fuer Map+Diff oder {}.
static func best(osz_file: String, version: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var v = cfg.get_value("scores", _key(osz_file, version), {})
	return v if v is Dictionary else {}


static func play_count(osz_file: String, version: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return 0
	return int(cfg.get_value("plays", _key(osz_file, version), 0))


static func _key(osz_file: String, version: String) -> String:
	return "%s|%s" % [osz_file.get_file(), version]
