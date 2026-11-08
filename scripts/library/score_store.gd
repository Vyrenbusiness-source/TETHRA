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
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		# Harness/Screenshots: eigene Score-Datei (Test-Kopie), nie die echte.
		if a.begins_with("--scores-path="):
			return a.trim_prefix("--scores-path=")
	for a in OS.get_cmdline_args():
		if a == "--script" or a == "-s":
			DirAccess.make_dir_recursive_absolute("user://test_tmp")
			return "user://test_tmp/scores_%d.cfg" % OS.get_process_id()
	return "user://scores.cfg"
const OTHERS_CAP := 10
const NAME_MAX := 24
const GRADES := ["SS", "S", "A", "B", "C", "D", "F"]

## Spielmodus: "" / "mania" = Mania 4K (Standard, bisherige Sektionen),
## sonst eigene Sektionen "<mode>_scores", "<mode>_plays", "<mode>_history",
## "<mode>_recent". Damit bleiben Orbit-Scores ("orbit") komplett getrennt
## und fliessen nicht in Mania-Bestwerte, Profil-pp oder Statistiken.
const MODE_MANIA := "mania"
const MODE_ORBIT := "orbit"


static func _sec(base: String, mode: String) -> String:
	if mode == "" or mode == MODE_MANIA:
		return base
	return "%s_%s" % [mode, base]


## "" -> "mania", sonst unveraendert (Wert des Feldes "mode" in Eintraegen).
static func mode_name(mode: String) -> String:
	return MODE_MANIA if mode == "" else mode


## Anzeige-Name eines Modus ("Mania 4K" / "Orbit").
static func mode_label(mode: String) -> String:
	return "Orbit" if mode == MODE_ORBIT else "Mania 4K"


## SV-Stufe eines Scores (nur mit Mod "SV"): Feld "sv_level".
## Alte Eintraege ohne Feld: "" (unbekannt, Anzeige nur "SV").
const SV_NORMAL := "normal"
const SV_STRONG := "strong"


## SV-Stufe fuer einen neuen Score: result.sv_level (String oder SvMod-Stufe
## als Zahl), sonst die gerade aktive SvMod.strength.
static func _sv_level_for(result: Dictionary) -> String:
	var v = result.get("sv_level", null)
	if v is String and (v == SV_NORMAL or v == SV_STRONG):
		return v
	if v is int or v is float:
		return SV_STRONG if int(v) >= SvMod.STRENGTH_STRONG else SV_NORMAL
	return SV_STRONG if SvMod.strength >= SvMod.STRENGTH_STRONG else SV_NORMAL


## Gespeicherte SV-Stufe eines Eintrags ("" = ohne SV oder unbekannt).
static func sv_level(e: Dictionary) -> String:
	if not _mods_of(e).has("SV"):
		return ""
	var v := str(e.get("sv_level", ""))
	return v if v == SV_NORMAL or v == SV_STRONG else ""


## Mods eines Eintrags als Anzeige-Text, SV mit Stufe: "SV Stark NF".
static func mods_label(e: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in _mods_of(e):
		if m == "SV":
			var lv := sv_level(e)
			if lv == SV_STRONG:
				m = "SV " + TranslationServer.translate("Stark")
			elif lv == SV_NORMAL:
				m = "SV " + TranslationServer.translate("Normal")
		parts.append(m)
	return " ".join(parts)


## Felder "mode" und (mit SV) "sv_level" an einen neuen Eintrag haengen.
static func _tag(entry: Dictionary, result: Dictionary, mode: String) -> Dictionary:
	entry["mode"] = mode_name(mode)
	if (entry.get("mods", []) as Array).has("SV"):
		entry["sv_level"] = _sv_level_for(result)
	return entry


## Zuletzt gespeichertes Ergebnis (fuer den Vergleich im Results-Screen):
## {key, mode, score, is_new_best, previous}. Leer, solange nichts gespeichert.
static var last_submit: Dictionary = {}


## Vorheriger Bestwert desselben Modus zum gerade gezeigten Ergebnis, oder
## null, wenn das Ergebnis nicht gespeichert wurde (Replay, Autoplay, ...).
static func previous_best_for(osz_file: String, version: String, mode: String, score: int):
	if last_submit.is_empty():
		return null
	if str(last_submit.get("key", "")) != _key(osz_file, version) 			or str(last_submit.get("mode", "")) != mode_name(mode) 			or int(last_submit.get("score", -1)) != score:
		return null
	return last_submit.get("previous", {})


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

## Schema der Datei ("meta"/"schema"). 2 = Modus-Trennung: Eintraege tragen
## "mode". Alte Dateien: alles bleibt Mania (keine Daten verloren); nur
## Verlaufs-Eintraege, die schon "mode" = anderer Modus tragen, wandern in
## dessen Sektionen.
const SCHEMA := 2
static var _migrated_path := ""


## Laedt PATH nach cfg und migriert einmal pro Prozess und Pfad.
static func _load(cfg: ConfigFile) -> Error:
	var err := cfg.load(PATH)
	if err == OK and _migrated_path != PATH:
		_migrated_path = PATH
		if migrate(cfg):
			cfg.save(PATH)
	return err


## Migriert cfg in-place; true, wenn sich etwas geaendert hat.
static func migrate(cfg: ConfigFile) -> bool:
	if int(cfg.get_value("meta", "schema", 1)) >= SCHEMA:
		return false
	for base in ["history", "recent"]:
		if not cfg.has_section(base):
			continue
		for key in cfg.get_section_keys(base):
			var list = cfg.get_value(base, key, [])
			if not (list is Array):
				continue
			var keep: Array = []
			for e in list:
				var m := str(e.get("mode", "")) if e is Dictionary else ""
				if m == "" or m == MODE_MANIA:
					keep.append(e)
				else:
					var sec := _sec(base, m)
					var moved: Array = cfg.get_value(sec, key, [])
					moved.append(e)
					cfg.set_value(sec, key, moved)
			if keep.size() != (list as Array).size():
				cfg.set_value(base, key, keep)
	cfg.set_value("meta", "schema", SCHEMA)
	return true


## Speichert ein Ergebnis; liefert {is_new_best: bool, previous: Dictionary}.
static func submit(osz_file: String, version: String, result: Dictionary, mode: String = "") -> Dictionary:
	var key := _key(osz_file, version)
	var cfg := ConfigFile.new()
	_load(cfg)
	var prev = cfg.get_value(_sec("scores", mode), key, {})
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
		cfg.set_value(_sec("scores", mode), key, _tag(entry, result, mode))
	var plays := int(cfg.get_value(_sec("plays", mode), key, 0)) + 1
	cfg.set_value(_sec("plays", mode), key, plays)
	cfg.save(PATH)
	last_submit = { "key": key, "mode": mode_name(mode), "score": int(result.get("score", 0)),
		"is_new_best": is_new_best, "previous": prev_dict }
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
static func best_mods(osz_file: String, version: String, mode: String = "") -> Array:
	return _mods_of(best(osz_file, version, mode))


const HISTORY_CAP := 20
const RECENT_CAP := 12


## Jeden abgeschlossenen Play zusaetzlich in History (pro Map) und Recent
## (global) ablegen. map_label = "Artist - Titel" fuer die Anzeige.
static func log_play(osz_file: String, version: String, map_label: String, result: Dictionary, mode: String = "") -> void:
	var key := _key(osz_file, version)
	var cfg := ConfigFile.new()
	_load(cfg)
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
	_tag(entry, result, mode)
	var hist: Array = cfg.get_value(_sec("history", mode), key, [])
	hist.append(entry)
	while hist.size() > HISTORY_CAP:
		hist.pop_front()
	cfg.set_value(_sec("history", mode), key, hist)
	var recent_entry := entry.duplicate()
	recent_entry["map"] = map_label
	recent_entry["version"] = version
	recent_entry["osz_file"] = osz_file.get_file()
	var recent: Array = cfg.get_value(_sec("recent", mode), "plays", [])
	recent.append(recent_entry)
	while recent.size() > RECENT_CAP:
		recent.pop_front()
	cfg.set_value(_sec("recent", mode), "plays", recent)
	cfg.save(PATH)


## Top-N Scores einer Map+Diff (beste zuerst, Fails ausgenommen).
static func top_scores(osz_file: String, version: String, n: int = 5, mode: String = "") -> Array:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return []
	var hist: Array = cfg.get_value(_sec("history", mode), _key(osz_file, version), [])
	var valid := hist.filter(func(e): return not bool(e.get("failed", false)))
	valid.sort_custom(func(a, b): return int(a.score) > int(b.score))
	return valid.slice(0, n)


## Letzte Plays (neueste zuerst).
## Global beste Bestwerte (nach pp sortiert) fuer die Profil-Ansicht.
## Jeder Eintrag bekommt "map" (Dateiname ohne .osz/Set-ID) und "version".
static func best_plays(n: int = 5, mode: String = "") -> Array:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return []
	var sec := _sec("scores", mode)
	if not cfg.has_section(sec):
		return []
	var entries: Array = []
	for key in cfg.get_section_keys(sec):
		var v = cfg.get_value(sec, key, {})
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
	if mode == MODE_ORBIT:
		# Orbit hat keine pp: nach Orbit-Wertung, dann Score.
		entries.sort_custom(func(a, b):
			var ra := orbit_points(a)
			var rb := orbit_points(b)
			return ra > rb if ra != rb else int(a.get("score", 0)) > int(b.get("score", 0)))
	else:
		entries.sort_custom(func(a, b): return float(a.get("pp", -1.0)) > float(b.get("pp", -1.0)))
	return entries.slice(0, n)


## Meistgespielte Maps (Play-Anzahl absteigend) inkl. Bestwert-Infos.
static func most_played(n: int = 5, mode: String = "") -> Array:
	var cfg := ConfigFile.new()
	var psec := _sec("plays", mode)
	if _load(cfg) != OK or not cfg.has_section(psec):
		return []
	var entries: Array = []
	for key in cfg.get_section_keys(psec):
		var count := int(cfg.get_value(psec, key, 0))
		if count <= 0:
			continue
		var parts := str(key).split("|")
		var fname := parts[0].get_basename()
		var words := fname.split(" ")
		if words.size() > 1 and words[0].is_valid_int():
			fname = " ".join(words.slice(1))
		var best_v = cfg.get_value(_sec("scores", mode), key, {})
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
			"score": int(best_e.get("score", 0)),
		})
	entries.sort_custom(func(a, b): return int(a.count) > int(b.count))
	return entries.slice(0, n)


static func recent_plays(n: int = 8, mode: String = "") -> Array:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return []
	var recent: Array = cfg.get_value(_sec("recent", mode), "plays", [])
	recent.reverse()
	return recent.slice(0, n)


## Profil-pp wie osu: Bestwerte aller Maps nach pp sortiert, gewichtet
## mit 0.95^i aufsummiert. NUR Mania (Sektion "scores"): andere Modi
## veraendern die pp nie.
static func profile_pp() -> float:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
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
static func total_plays(mode: String = "") -> int:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return 0
	var sec := _sec("plays", mode)
	if not cfg.has_section(sec):
		return 0
	var total := 0
	for key in cfg.get_section_keys(sec):
		total += int(cfg.get_value(sec, key, 0))
	return total


## Orbit-Wertung eines Bestwerts (einfach, ohne Sterne): 100 * acc^4,
## Fail/leer 0. Ungewertete zaehlen nicht.
static func orbit_points(e: Dictionary) -> float:
	if e.is_empty() or bool(e.get("failed", false)) or bool(e.get("unranked", false)):
		return 0.0
	return 100.0 * pow(clampf(float(e.get("accuracy", 0.0)), 0.0, 1.0), 4.0)


## Kennzahlen eines Modus fuer das Profil:
## {plays, maps, avg_acc (0..1, ueber alle nicht gescheiterten Plays im
## Verlauf), best_score, rating}. rating: Mania = profile_pp(), sonst
## Orbit-Wertung (orbit_points der Bestwerte, gewichtet 0.95^i).
static func mode_stats(mode: String = "") -> Dictionary:
	var out := { "plays": total_plays(mode), "maps": 0, "avg_acc": 0.0,
		"best_score": 0, "rating": 0.0 }
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return out
	var ssec := _sec("scores", mode)
	var pts: Array[float] = []
	if cfg.has_section(ssec):
		for key in cfg.get_section_keys(ssec):
			var e = cfg.get_value(ssec, key, {})
			if not (e is Dictionary) or e.is_empty():
				continue
			out.maps += 1
			out.best_score = maxi(int(out.best_score), int(e.get("score", 0)))
			pts.append(orbit_points(e))
	var hsec := _sec("history", mode)
	var acc_sum := 0.0
	var acc_n := 0
	if cfg.has_section(hsec):
		for key in cfg.get_section_keys(hsec):
			for h in cfg.get_value(hsec, key, []):
				if h is Dictionary and not bool(h.get("failed", false)):
					acc_sum += float(h.get("accuracy", 0.0))
					acc_n += 1
	out.avg_acc = acc_sum / float(acc_n) if acc_n > 0 else 0.0
	if mode == "" or mode == MODE_MANIA:
		out.rating = profile_pp()
	else:
		pts.sort()
		pts.reverse()
		var total := 0.0
		for i in pts.size():
			total += pts[i] * pow(0.95, i)
		out.rating = total
	return out


## Bestwert fuer Map+Diff oder {}.
static func best(osz_file: String, version: String, mode: String = "") -> Dictionary:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return {}
	var v = cfg.get_value(_sec("scores", mode), _key(osz_file, version), {})
	return v if v is Dictionary else {}


static func play_count(osz_file: String, version: String, mode: String = "") -> int:
	var cfg := ConfigFile.new()
	if _load(cfg) != OK:
		return 0
	return int(cfg.get_value(_sec("plays", mode), _key(osz_file, version), 0))


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
		_load(cfg)
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
	_load(cfg)
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
	var out := {
		"player": pname, "score": score, "accuracy": acc, "grade": grade,
		"max_combo": combo, "pp": pp, "unranked": bool(d.get("unranked", false)),
		"mods": mods, "date": date,
	}
	var lv = d.get("sv_level", "")
	if mods.has("SV") and (lv is String) and (lv == SV_NORMAL or lv == SV_STRONG):
		out["sv_level"] = lv
	return out


## Speichert Fremd-Scores einer Map (map_key aus map_id/map_id_for_set).
## Duplikate (gleicher Spieler + Score) werden uebersprungen; pro Spieler
## und Map bleiben die OTHERS_CAP besten. Liefert die Zahl neuer Eintraege.
## mode wie bei submit(): "" = Mania (Sektion "others"), sonst "<mode>_others".
static func submit_others(map_key: String, player: String, entries: Array, mode: String = "") -> int:
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
	_load(cfg)
	var list: Array = cfg.get_value(_sec("others", mode), map_key, [])
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
	cfg.set_value(_sec("others", mode), map_key, kept)
	cfg.save(PATH)
	return added


## Eigene + fremde Scores einer Map gemischt (beste zuerst, max. n).
## Jeder Eintrag hat "player", "is_self" und "mode". Eigene und fremde
## Scores kommen nur aus den Sektionen des Modus (Mania "others", Orbit
## "orbit_others"): Modi mischen sich nie.
static func top_scores_all(osz_file: String, version: String, n: int = 5, mode: String = "") -> Array:
	var cfg := ConfigFile.new()
	var loaded := _load(cfg) == OK
	var out: Array = []
	for e in top_scores(osz_file, version, HISTORY_CAP, mode):
		var d: Dictionary = e.duplicate()
		d["player"] = _self_name()
		d["is_self"] = true
		d["mode"] = mode_name(mode)
		out.append(d)
	if loaded:
		var others: Array = cfg.get_value(_sec("others", mode), map_id(osz_file, version, cfg), [])
		for o in others:
			if o is Dictionary:
				var d: Dictionary = o.duplicate()
				d["is_self"] = false
				d["mode"] = mode_name(mode)
				out.append(d)
	out.sort_custom(func(a, b): return int(a.score) > int(b.score))
	return out.slice(0, n)


## Eigener Profilname (Autoload per Pfad, damit Tests ohne Autoload-Symbol kompilieren).
static func _self_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var st = tree.root.get_node_or_null("Settings") if tree != null else null
	return str(st.profile_name) if st != null else "Player"
