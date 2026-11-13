extends SceneTree

## OMEN Auto-Mapper 4K: Abstimmung. Sucht ueber die Abstimm-Menge (70 % der Maps) bessere Werte
## fuer die params der Module (Koordinaten-Suche), schreibt data/automap/params.json (Abschnitte
## grid, features, chart) und protokolliert vorher/nachher auf der Pruef-Menge.
##
## Aufruf (ein Prozess, beendet sich selbst):
##   timeout 7200 Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
##       --script res://tools/automap_tune.gd -- --maps <maps-ordner> [--songs 16] [--test-songs 8]
##       [--passes 2] [--points 5] [--knobs grid.x:0.1:0.9,chart.y:1:4:int] [--mapper auto|old|new] [--dry]
##
## Stellgroessen: ohne --knobs alle Zahlen aus `const DEFAULTS` der Module (Bereich 0,5x..1,5x,
## ganze Zahlen bleiben ganz); ein Modul kann mit `const TUNE_RANGES := {name: [min, max]}` eigene
## Bereiche vorgeben. Beim alten Mapper gibt es nur post.offset_shift_ms (Eichung des OSU_LEAD).
## Zielgroesse: automap_bench.gd objective() (gewichtete Zielerreichung, ohne Sterne und Dauer).
## Dekodiertes Audio und die Ergebnisse der teuren Stufen bleiben im Speicher: je Kandidat wird
## nur die Stufe neu gerechnet, deren Abschnitt sich aendert. Speicher: etwa 21 MB je Song.

const B := preload("res://tools/automap_bench.gd")
const PARAMS_PATH := "res://data/automap/params.json"
const OLD_KNOBS := [{"key": "post.offset_shift_ms", "min": -30.0, "max": 30.0, "int": false}]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_main(OS.get_cmdline_user_args()))
	return true


static func get_param(params: Dictionary, key: String, def = null):
	var parts := key.split(".")
	return params.get(parts[0], {}).get(parts[1], def)


static func set_param(params: Dictionary, key: String, value) -> void:
	var parts := key.split(".")
	if not params.has(parts[0]):
		params[parts[0]] = {}
	params[parts[0]][parts[1]] = value


## Stellgroessen aus den DEFAULTS eines Moduls. section: "grid" | "features" | "chart".
static func knobs_from_defaults(script, section: String) -> Array:
	var out: Array = []
	if script == null or not (script is Script):
		return out
	var consts: Dictionary = (script as Script).get_script_constant_map()
	var defs = consts.get("DEFAULTS")
	if not (defs is Dictionary):
		return out
	var ranges = consts.get("TUNE_RANGES", {})
	for k in defs:
		var v = defs[k]
		if not (v is float or v is int) or v is bool:
			continue
		var is_int: bool = v is int
		var lo := float(v) * 0.5
		var hi := float(v) * 1.5
		if ranges is Dictionary and ranges.has(k):
			lo = float(ranges[k][0])
			hi = float(ranges[k][1])
		elif float(v) == 0.0:
			continue
		elif is_int:
			lo = maxf(floorf(float(v) * 0.5), 1.0)
			hi = maxf(ceilf(float(v) * 1.5), lo + 1.0)
		if hi < lo:
			var t := lo
			lo = hi
			hi = t
		out.append({"key": "%s.%s" % [section, k], "min": lo, "max": hi, "int": is_int, "start": v})
	return out


## "grid.x:0.1:0.9,chart.y:1:4:int" -> Stellgroessen.
static func parse_knobs(text: String) -> Array:
	var out: Array = []
	for item in text.split(",", false):
		var p := item.split(":")
		if p.size() < 3 or p[0].find(".") < 0:
			continue
		out.append({"key": p[0], "min": float(p[1]), "max": float(p[2]), "int": p.size() > 3 and p[3] == "int"})
	return out


## Koordinaten-Suche (groesser = besser). Je Stellgroesse `points` gleichmaessig verteilte Werte im
## Bereich; ab dem zweiten Durchgang wird der Bereich um den besten Wert enger. eval: Callable(params) -> float.
## Rueckgabe {params, score, start_score, evals, log: [Zeilen]}.
static func coordinate_search(knobs: Array, start: Dictionary, eval: Callable, passes: int = 2, points: int = 5) -> Dictionary:
	var best: Dictionary = start.duplicate(true)
	var best_score: float = eval.call(best)
	var start_score := best_score
	var evals := 1
	var log: Array = []
	var span := {}
	for k in knobs:
		span[k.key] = [float(k.min), float(k.max)]
	for pass_i in passes:
		var improved := false
		for k in knobs:
			var lo: float = span[k.key][0]
			var hi: float = span[k.key][1]
			var cur = get_param(best, k.key, k.get("start"))
			var tried := {}
			var local_best = cur
			for i in points:
				var v: float = lo + (hi - lo) * i / maxi(points - 1, 1)
				var val = int(roundf(v)) if k.get("int", false) else v
				if tried.has(val) or (cur != null and is_equal_approx(float(val), float(cur))):
					continue
				tried[val] = true
				var cand: Dictionary = best.duplicate(true)
				set_param(cand, k.key, val)
				var sc: float = eval.call(cand)
				evals += 1
				if sc > best_score + 1e-9:
					best_score = sc
					best = cand
					local_best = val
					improved = true
			log.append("Durchgang %d, %s: %s -> %s (Zielgröße %.4f)" % [pass_i + 1, k.key, str(cur), str(local_best), best_score])
			if local_best != null:
				var w := (hi - lo) / maxi(points - 1, 1)
				span[k.key] = [maxf(float(k.min), float(local_best) - w), minf(float(k.max), float(local_best) + w)]
		if not improved:
			break
	return {"params": best, "score": best_score, "start_score": start_score, "evals": evals, "log": log}


## Songs einer Menge in fester, vom Dateinamen-Hash bestimmter Reihenfolge.
static func pick_files(files: Array, split: String, count: int) -> Array:
	var sel: Array = []
	for f in files:
		if B.split_of(f) == split:
			sel.append(f)
	sel.sort_custom(func(a, b): return String(a).sha256_text() < String(b).sha256_text())
	if count > 0 and sel.size() > count:
		sel.resize(count)
	return sel


static func load_songs(mods: Dictionary, maps_dir: String, files: Array) -> Array:
	var songs: Array = []
	var tmp := ProjectSettings.globalize_path(B.OUT_DIR)
	DirAccess.make_dir_recursive_absolute(tmp)
	for f in files:
		var osz: String = maps_dir.path_join(f)
		var truth: Dictionary = B.load_truth(osz, StarService.stars_for(osz))
		if not truth.ok:
			continue
		var audio: String = B.extract_file(osz, truth.audio_name, tmp.path_join("tune_audio_tmp"))
		if audio == "":
			continue
		var dec: Dictionary = mods.features.decode(audio)
		DirAccess.remove_absolute(audio)
		if not dec.get("ok", false):
			continue
		songs.append({"file": f, "truth": truth, "pcm": dec.pcm, "rate": int(dec.rate),
				"dur_ms": float(dec.duration_ms), "cache": {}})
	return songs


static func evaluate(mods: Dictionary, songs: Array, params: Dictionary) -> Dictionary:
	var recs: Array = []
	for s in songs:
		var prod: Dictionary = B.product_from_stages(mods, s.pcm, s.rate, params, mods.caps.profiles, s.cache)
		recs.append(B.song_record(s.file, s.truth, prod, 0.0, s.dur_ms))
	return B.aggregate(recs)


func _main(args: PackedStringArray) -> int:
	print("=== OMEN Auto-Mapper Abstimmung ===")
	var maps_dir: String = B._arg(args, "--maps", ProjectSettings.globalize_path("res://maps"))
	if not DirAccess.dir_exists_absolute(maps_dir):
		print("Maps-Ordner fehlt: ", maps_dir, " (--maps <ordner>)")
		return 2
	var mods: Dictionary = B.load_mods(B._arg(args, "--mapper", "auto"))
	var knobs: Array = []
	if args.has("--knobs"):
		knobs = parse_knobs(B._arg(args, "--knobs"))
	elif mods.name == "neu":
		for sec in ["grid", "features", "chart"]:
			knobs.append_array(knobs_from_defaults(mods[sec], sec))
	else:
		knobs = OLD_KNOBS.duplicate(true)
	if knobs.is_empty():
		print("Keine Stellgroessen gefunden (Module ohne const DEFAULTS? dann --knobs angeben)")
		return 2
	var params := {"grid": {}, "features": {}, "chart": {}}
	if FileAccess.file_exists(PARAMS_PATH):
		var pj = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		if pj is Dictionary:
			for sec in pj:
				params[sec] = pj[sec]
	for k in knobs:
		if get_param(params, k.key) == null and k.has("start"):
			set_param(params, k.key, k.start)
	StarService.prefetch_dir(maps_dir)
	var files: Array = B.list_osz(maps_dir)
	var n_tune := int(B._arg(args, "--songs", "16"))
	var n_test := int(B._arg(args, "--test-songs", "8"))
	var t0 := Time.get_ticks_msec()
	var tune_songs := load_songs(mods, maps_dir, pick_files(files, "tune", n_tune))
	var test_songs := load_songs(mods, maps_dir, pick_files(files, "test", n_test))
	print("Mapper %s, %d Stellgroessen, %d Songs Abstimm-Menge, %d Songs Pruef-Menge" % [mods.name, knobs.size(), tune_songs.size(), test_songs.size()])
	if tune_songs.is_empty() or test_songs.is_empty():
		print("Zu wenige Songs geladen")
		return 2
	var before_test := evaluate(mods, test_songs, params)
	var res := coordinate_search(knobs, params, func(p): return B.objective(evaluate(mods, tune_songs, p)),
			int(B._arg(args, "--passes", "2")), int(B._arg(args, "--points", "5")))
	var after_test := evaluate(mods, test_songs, res.params)
	var ob := B.objective(before_test)
	var oa := B.objective(after_test)
	var better: bool = res.score > res.start_score + 1e-9 and oa >= ob - 0.002
	var log := "- Stand: %s, Mapper „%s“, %d Songs Abstimm-Menge, %d Songs Prüf-Menge, %d Auswertungen, %.0f s.\n" % [
			Time.get_datetime_string_from_system(), mods.name, tune_songs.size(), test_songs.size(), res.evals, (Time.get_ticks_msec() - t0) / 1000.0]
	log += "- Zielgröße (0..1, 1 = alle Ziele erreicht; ohne Sterne und Dauer): Abstimm-Menge %.4f -> %.4f, **Prüf-Menge %.4f -> %.4f**.\n" % [res.start_score, res.score, ob, oa]
	for l in res.log:
		log += "- " + l + "\n"
	var rb: Array = B.target_rows(before_test, mods.caps)
	var ra: Array = B.target_rows(after_test, mods.caps)
	var rows: Array = []
	for i in rb.size():
		rows.append([rb[i][1], rb[i][2], rb[i][3], ra[i][3], ra[i][4]])
	log += "\n" + B._table(["Kennzahl (Prüf-Menge, nur die geladenen Songs)", "Ziel", "vorher", "nachher", "erreicht nachher"], rows)
	if args.has("--dry"):
		log += "\nNicht geschrieben (--dry).\n"
	elif mods.name != "neu":
		log += "\n`data/automap/params.json` unverändert: Der alte Mapper hat keine params. Gefundener gemeinsamer Versatz für Gitter und Noten: %s ms (Hinweis für `OSU_LEAD_MS`).\n" % str(get_param(res.params, "post.offset_shift_ms", 0.0))
	elif not better:
		log += "\n`data/automap/params.json` unverändert: keine Verbesserung auf der Abstimm-Menge oder schlechter auf der Prüf-Menge.\n"
	else:
		var out := {"grid": res.params.get("grid", {}), "features": res.params.get("features", {}), "chart": res.params.get("chart", {})}
		var fa := FileAccess.open(ProjectSettings.globalize_path(PARAMS_PATH), FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify(out, "\t") + "\n")
			fa.close()
		log += "\n`data/automap/params.json` geschrieben.\n"
	print(log)
	var fl := FileAccess.open(B.OUT_DIR.path_join("tune_log.md"), FileAccess.WRITE)
	if fl != null:
		fl.store_string(log)
		fl.close()
	return 0
