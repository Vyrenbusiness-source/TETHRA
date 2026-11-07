class_name ScoreStore
extends RefCounted

## Persistente Bestwerte pro Map+Difficulty (user://scores.cfg).
## Key: "<osz-Dateiname>|<Difficulty-Version>". Unranked-Scores (AR-Override)
## werden gespeichert, aber separat markiert und ueberschreiben keine
## Ranked-Bestwerte.

##
## Fremde Scores (Multiplayer-Sync): Sektion "others", Key = map_id()
## ("<set_id>|<Version>", bei unbekannter Set-ID "f:<Dateiname>|<Version>"),
## Wert = Array von Eintraegen. Sie fliessen NIE in scores/plays/history/recent,
## also nicht in best(), best_plays(), profile_pp() oder Statistiken.
## Felder eines Eintrags (others und top_scores_all):
##   player: String (max. 24 Zeichen), score: int, accuracy: float 0..1,
##   grade: String, max_combo: int, pp: float (-1 = unbekannt),
##   unranked: bool, mods: Array[String], date: String,
##   is_self: bool (nur top_scores_all; eigene = Settings.profile_name)
## Map-Identitaet: Set-ID aus Dateiname ("123 Titel.osz", "mirror_123.osz") oder
## per register_set_id() aus der Sektion "setids" (Dateiname -> Set-ID), damit
## unterschiedliche Dateinamen derselben Map zusammenfallen.

## Echte Scores: user://scores.cfg. Headless-Testlaeufe (--script) bekommen
## IMMER eine eigene Datei pro Prozess, damit kein Test (auch parallel oder
## abgebrochen) die echten Scores des Spielers loeschen kann.
static var PATH: String = _default_path()


static func _default_path() -> String:
	for a in OS.get_cmdline_args():
		if a == "--script" or a == "-s":
			DirAccess.make_dir_recursive_absolute("user://test_tmp")
			return "user://test_tmp/scores_%d.cfg" % OS.get_process_id()
	return "user://scores.cfg"
const OTHERS_CAP := 10
const NAME_MAX := 24
const GRADES := ["SS", "S", "A", "B", "C", "D", "F"]


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
			"mods": _mods_of(result),
			"mod_mult": float(result.get("mod_mult", 1.0)),
			"date": Time.get_datetime_string_from_system(),
		}
		cfg.set_value("scores", key, entry)
	var plays := int(cfg.get_value("plays", key, 0)) + 1
	cfg.set_value("plays", key, plays)
	cfg.save(PATH)
	return { "is_new_best": is_new_best, "previous": prev_dict }


## Mod-Liste des Laufs als Array[String]; fehlt "mods" (alte Daten): [].
static func _mods_of(result: Dictionary) -> Array:
	var out: Array = []
	var m = result.get("mods", [])
	if m is Array:
		for x in m:
			out.append(str(x))
	elif m is Dictionary:
		for x in m:
			if bool(m[x]):
				out.append(str(x))
	return out


## Bestwert-Mods als Liste (alte Eintraege ohne "mods" -> []).
static func best_mods(osz_file: String, version: String) -> Array:
	return _mods_of(best(osz_file, version))


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
		"mods": _mods_of(result),
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


# ---------------------------------------------------------------------------
# Fremde Scores
# ---------------------------------------------------------------------------

## Set-ID einer lokalen .osz: Registry, sonst aus dem Dateinamen; 0 = unbekannt.
static func set_id_of(osz_file: String, cfg: ConfigFile = null) -> int:
	var f := osz_file.get_file()
	if cfg == null:
		cfg = ConfigFile.new()
		cfg.load(PATH)
	var reg := int(cfg.get_value("setids", f, 0))
	if reg > 0:
		return reg
	var base := f.get_basename()
	if base.begins_with("mirror_") and base.substr(7).is_valid_int():
		return int(base.substr(7))
	var head := base.split(" ")[0]
	if head.is_valid_int():
		return int(head)
	return 0


## Merkt sich Dateiname -> Set-ID (z. B. aus der .osu oder der Lobby-Auswahl).
static func register_set_id(osz_file: String, set_id: int) -> void:
	if set_id <= 0 or osz_file.get_file() == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if int(cfg.get_value("setids", osz_file.get_file(), 0)) == set_id:
		return
	cfg.set_value("setids", osz_file.get_file(), set_id)
	cfg.save(PATH)


static func map_id_for_set(set_id: int, version: String) -> String:
	return "%d|%s" % [set_id, version]


## Dateinamen-unabhaengiger Map-Schluessel.
static func map_id(osz_file: String, version: String, cfg: ConfigFile = null) -> String:
	var sid := set_id_of(osz_file, cfg)
	if sid > 0:
		return map_id_for_set(sid, version)
	return "f:%s|%s" % [osz_file.get_file().get_basename(), version]


## Prueft/normalisiert einen Fremd-Eintrag; {} wenn ungueltig.
static func sanitize_foreign(e: Variant, player: String) -> Dictionary:
	if not (e is Dictionary):
		return {}
	var d: Dictionary = e
	var pname := ""
	for ch in player.strip_edges():
		if ch.unicode_at(0) >= 32:
			pname += ch
	pname = pname.substr(0, NAME_MAX).strip_edges()
	if pname == "":
		return {}
	for k in ["score", "accuracy", "max_combo", "pp"]:
		if not (d.get(k, 0) is int or d.get(k, 0) is float):
			return {}
	var score := int(d.get("score", 0))
	var acc := float(d.get("accuracy", 0.0))
	var combo := int(d.get("max_combo", 0))
	var pp := float(d.get("pp", -1.0))
	if is_nan(acc) or is_nan(pp) or is_inf(acc) or is_inf(pp):
		return {}
	if score < 0 or score > 100000000 or acc < 0.0 or acc > 1.0 			or combo < 0 or combo > 1000000 or pp < -1.0 or pp > 100000.0:
		return {}
	if bool(d.get("failed", false)):
		return {}
	var grade = d.get("grade", "D")
	if not (grade is String) or not GRADES.has(grade):
		return {}
	var mods: Array = []
	var m = d.get("mods", [])
	if not (m is Array) or m.size() > 8:
		return {}
	for x in m:
		if not (x is String) or x.length() > 8:
			return {}
		mods.append(x)
	var date = d.get("date", "")
	if not (date is String) or date.length() > 32:
		return {}
	return {
		"player": pname, "score": score, "accuracy": acc, "grade": grade,
		"max_combo": combo, "pp": pp, "unranked": bool(d.get("unranked", false)),
		"mods": mods, "date": date,
	}


## Speichert Fremd-Scores einer Map (map_key aus map_id/map_id_for_set).
## Duplikate (gleicher Spieler + Score) werden uebersprungen; pro Spieler
## und Map bleiben die OTHERS_CAP besten. Liefert die Zahl neuer Eintraege.
static func submit_others(map_key: String, player: String, entries: Array) -> int:
	if map_key == "":
		return 0
	var clean: Array = []
	for e in entries:
		var c := sanitize_foreign(e, player)
		if not c.is_empty():
			clean.append(c)
	if clean.is_empty():
		return 0
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var list: Array = cfg.get_value("others", map_key, [])
	var added := 0
	for c in clean:
		var dup := false
		for o in list:
			if o is Dictionary and str(o.get("player", "")) == c.player 					and int(o.get("score", -1)) == int(c.score):
				dup = true
				break
		if not dup:
			list.append(c)
			added += 1
	if added == 0:
		return 0
	# pro Spieler auf die besten OTHERS_CAP kappen
	list.sort_custom(func(a, b): return int(a.score) > int(b.score))
	var count := {}
	var kept: Array = []
	for o in list:
		var n := int(count.get(o.player, 0))
		if n < OTHERS_CAP:
			kept.append(o)
			count[o.player] = n + 1
	cfg.set_value("others", map_key, kept)
	cfg.save(PATH)
	return added


## Eigene + fremde Scores einer Map gemischt (beste zuerst, max. n).
## Jeder Eintrag hat "player" und "is_self".
static func top_scores_all(osz_file: String, version: String, n: int = 5) -> Array:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(PATH) == OK
	var out: Array = []
	for e in top_scores(osz_file, version, HISTORY_CAP):
		var d: Dictionary = e.duplicate()
		d["player"] = _self_name()
		d["is_self"] = true
		out.append(d)
	if loaded:
		var others: Array = cfg.get_value("others", map_id(osz_file, version, cfg), [])
		for o in others:
			if o is Dictionary:
				var d: Dictionary = o.duplicate()
				d["is_self"] = false
				out.append(d)
	out.sort_custom(func(a, b): return int(a.score) > int(b.score))
	return out.slice(0, n)


## Eigener Profilname (Autoload per Pfad, damit Tests ohne Autoload-Symbol kompilieren).
static func _self_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var st = tree.root.get_node_or_null("Settings") if tree != null else null
	return str(st.profile_name) if st != null else "Player"
