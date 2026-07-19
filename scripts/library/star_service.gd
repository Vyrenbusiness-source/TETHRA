class_name StarService
extends RefCounted

## Star Rating / pp / Max-Combo — ausschliesslich aus rosu-pp (Masterplan
## Regel 9), via tools/starcalc.py (rosu-pp-py 4.0.2, Version gepinnt).
## Ergebnisse werden in user://stars.cfg gecacht (Key: Dateiname + Groesse),
## damit python nur einmal pro Mapset laeuft.

const CACHE_PATH := "user://stars.cfg"
const ROSU_VERSION := "rosu-pp-py 4.0.2"


## Batch-Vorberechnung fuer einen ganzen Maps-Ordner: EIN python-Aufruf statt
## einem pro Mapset (90 Mapsets = ~45s Freeze vermieden). Fuellt den Cache.
static func prefetch_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	var missing := 0
	for fname in dir.get_files():
		if fname.to_lower().ends_with(".osz"):
			var key := _cache_key(dir_path.path_join(fname))
			if key != "" and not cfg.has_section_key("stars", key):
				missing += 1
	if missing < 2:
		return  # einzelne Nachzuegler macht stars_for() guenstiger selbst
	var result := _run_starcalc(["--dir", ProjectSettings.globalize_path(dir_path)])
	if result.is_empty() or result.has("error"):
		return
	for osz_name in result:
		var entry = result[osz_name]
		if not (entry is Dictionary) or entry.has("error"):
			continue
		var key := "%s|%d" % [osz_name, int(entry.get("size", 0))]
		cfg.set_value("stars", key, entry.get("stars", {}))
	cfg.set_value("meta", "rosu_version", ROSU_VERSION)
	cfg.save(CACHE_PATH)


## Liefert { "<innerer .osu-Name>": {stars, max_combo, version}, ... } oder {}.
static func stars_for(osz_path: String) -> Dictionary:
	var key := _cache_key(osz_path)
	if key == "":
		return {}
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	if cfg.has_section_key("stars", key):
		var cached = cfg.get_value("stars", key)
		if cached is Dictionary:
			return cached
	var result := _run_starcalc(["--osz", ProjectSettings.globalize_path(osz_path)])
	if result.is_empty() or result.has("error"):
		return {}
	cfg.set_value("stars", key, result)
	cfg.set_value("meta", "rosu_version", ROSU_VERSION)
	cfg.save(CACHE_PATH)
	return result


## Exakte pp fuer ein Ergebnis. Liefert {pp, stars, max_combo} oder {}.
static func pp_for(osz_path: String, inner_osu: String, n300: int, n100: int,
		n50: int, miss: int, combo: int) -> Dictionary:
	if inner_osu == "":
		return {}
	var result := _run_starcalc([
		"--pp", "--osz", ProjectSettings.globalize_path(osz_path),
		"--osu", inner_osu,
		"--n300", str(n300), "--n100", str(n100), "--n50", str(n50),
		"--miss", str(miss), "--combo", str(combo),
	])
	if result.has("error"):
		return {}
	return result


## Exakte pp fuer ein MANIA-Ergebnis mit dem vollen Judgement-Satz:
## MAX -> n_geki, 300 -> n300, 200 -> n_katu, 100 -> n100, 50 -> n50.
## Liefert {pp, stars, max_combo} oder {}.
static func pp_for_mania(osz_path: String, inner_osu: String, nmax: int,
		p300: int, p200: int, p100: int, p50: int, miss: int, combo: int) -> Dictionary:
	if inner_osu == "":
		return {}
	var result := _run_starcalc([
		"--pp", "--osz", ProjectSettings.globalize_path(osz_path),
		"--osu", inner_osu,
		"--geki", str(nmax), "--n300", str(p300), "--katu", str(p200),
		"--n100", str(p100), "--n50", str(p50),
		"--miss", str(miss), "--combo", str(combo),
	])
	if result.has("error"):
		return {}
	return result


## Max-pp (SS, 100%% acc, Full Combo) einer Diff — nur aus rosu-pp,
## gecacht in user://stars.cfg (Section "maxpp"). -1 = nicht berechenbar.
static func max_pp_for(osz_path: String, inner_osu: String, note_count: int) -> float:
	var base_key := _cache_key(osz_path)
	if base_key == "" or inner_osu == "":
		return -1.0
	var key := "%s|%s" % [base_key, inner_osu]
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	if cfg.has_section_key("maxpp", key):
		return float(cfg.get_value("maxpp", key, -1.0))
	var info: Dictionary = stars_for(osz_path).get(inner_osu, {})
	var combo := int(info.get("max_combo", 0))
	var result := pp_for(osz_path, inner_osu, note_count, 0, 0, 0, combo)
	var pp := float(result.get("pp", -1.0)) if not result.is_empty() else -1.0
	cfg.load(CACHE_PATH)
	cfg.set_value("maxpp", key, pp)
	cfg.save(CACHE_PATH)
	return pp


## Nur Cache-Zugriff (blockiert nie). -1000 = noch nie berechnet.
static func max_pp_cached(osz_path: String, inner_osu: String) -> float:
	var base_key := _cache_key(osz_path)
	if base_key == "" or inner_osu == "":
		return -1.0
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH)
	var key := "%s|%s" % [base_key, inner_osu]
	if not cfg.has_section_key("maxpp", key):
		return -1000.0
	return float(cfg.get_value("maxpp", key, -1.0))


static func _run_starcalc(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := -1
	# Gebundelte starcalc.exe neben der Spiel-Exe bevorzugen (kein Python
	# noetig; Release-Fall). has_feature("editor") ist hier unbrauchbar.
	var bundled := OS.get_executable_path().get_base_dir().path_join("tools/starcalc.exe")
	if FileAccess.file_exists(bundled):
		code = OS.execute(bundled, args, output, true)
	else:
		var script := ProjectSettings.globalize_path("res://tools/starcalc.py")
		var full_args := PackedStringArray([script])
		full_args.append_array(args)
		code = OS.execute("python", full_args, output, true)
	if code != 0 or output.is_empty():
		push_warning("StarService: starcalc fehlgeschlagen (Code %d)" % code)
		return {}
	var parsed = JSON.parse_string(String(output[0]).strip_edges())
	if parsed is Dictionary:
		return parsed
	return {}


## Cache-Key: Dateiname + Groesse (aendert sich die Datei, aendert sich der Key).
static func _cache_key(osz_path: String) -> String:
	if not FileAccess.file_exists(osz_path):
		return ""
	var f := FileAccess.open(osz_path, FileAccess.READ)
	var size := f.get_length()
	f.close()
	return "%s|%d" % [osz_path.get_file(), size]
