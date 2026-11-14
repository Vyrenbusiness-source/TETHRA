extends SceneTree

## OMEN Auto-Mapper 4K: Auswahl-Modell des Notensetzers lernen (data/automap/select.json).
##
## Ein Prozess je Schritt, beendet sich selbst:
##   # 1. Kette einmal rechnen (decode, AmGrid, AmFeatures mit params.json) und je Set ablegen
##   timeout 7200 Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
##       --script res://tools/automap_learn_chart.gd -- --dump --maps <maps> --cache <ordner> [--set tune|test]
##   # 2. Modell lernen (nur Abstimm-Menge) und data/automap/select.json schreiben
##   ... -- --fit --cache <ordner> [--epochs 12] [--l2 0.0005] [--dry]
##   # 3. Setzer auf den abgelegten Eingaben messen (Pruef-Menge), ohne Audio, Sterne = estimate_stars
##   ... -- --eval --cache <ordner> [--set test] [--chart k=v,k=v] [--no-model]
##
## Modell (je Profil): logistische Regression ueber die Merkmale einer Gitter-Zeile (AmChart.row_features):
## Staerke je Ereignis-Art, dieselbe nur wenn die Art zur fuehrenden Ebene gehoert, Lage im Takt,
## Abschnitt (Art, Intensitaet, Kiai), oertliche Ereignis-Dichte und Lautheit, gehaltener Ton, Tempo,
## Abstand zu den Nachbar-Zeilen. Ziel: Mensch hat an dieser Zeile eine Note (+-15 ms; Menschen-Diff wie
## im Pruefstand je Profil gewaehlt). Dazu je Profil ein Akkord-Modell (Zeile hat beim Menschen >= 2 Noten)
## und ein Hold-Modell (Zeile beginnt beim Menschen einen Hold). Gelernt mit Adagrad + L2, Gewichte als
## Tabelle in select.json (Merkmalsname -> Gewicht), keine Maps.
##
## Nur Abstimm-Menge (automap_bench.split_of) fliesst ins Lernen; die Pruef-Menge misst.

const B := preload("res://tools/automap_bench.gd")
const PARAMS_PATH := "res://data/automap/params.json"
const SELECT_PATH := "res://data/automap/select.json"
const TOL := 15.0

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_main(OS.get_cmdline_user_args()))
	return true


static func _params() -> Dictionary:
	var params := {"grid": {}, "features": {}, "chart": {}}
	if FileAccess.file_exists(PARAMS_PATH):
		var pj = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
		if pj is Dictionary:
			for sec in pj:
				params[sec] = pj[sec]
	return params


static func _kv(text: String) -> Dictionary:
	var out := {}
	for item in text.split(",", false):
		var p := item.split("=")
		if p.size() == 2:
			out[p[0]] = float(p[1]) if p[1].is_valid_float() else p[1]
	return out


func _main(args: PackedStringArray) -> int:
	var cache := B._arg(args, "--cache", "")
	if cache == "":
		print("--cache <ordner> fehlt")
		return 2
	DirAccess.make_dir_recursive_absolute(cache)
	if args.has("--dump"):
		return _dump(args, cache)
	if args.has("--fit"):
		return _fit(args, cache)
	if args.has("--eval"):
		return _eval(args, cache)
	if args.has("--debug"):
		return _debug(args, cache)
	print("--dump | --fit | --eval")
	return 2


# ---------------------------------------------------------------------------
# 1. Kette rechnen und ablegen
# ---------------------------------------------------------------------------

func _dump(args: PackedStringArray, cache: String) -> int:
	var maps_dir := B._arg(args, "--maps", "")
	var only := B._arg(args, "--set", "")
	var limit := int(B._arg(args, "--limit", "0"))
	var params := _params()
	StarService.prefetch_dir(maps_dir)
	var files: Array = B.list_osz(maps_dir)
	var tmp := cache.path_join("audio_tmp")
	var n := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		if only != "" and B.split_of(f) != only:
			continue
		if limit > 0 and n >= limit:
			break
		n += 1
		var out := cache.path_join(String(f).sha256_text().substr(0, 16) + ".bin")
		if FileAccess.file_exists(out):
			continue
		var osz: String = maps_dir.path_join(f)
		var truth: Dictionary = B.load_truth(osz, StarService.stars_for(osz))
		if not truth.ok:
			continue
		var audio: String = B.extract_file(osz, truth.audio_name, tmp)
		if audio == "":
			continue
		var dec: Dictionary = AmFeatures.decode(audio)
		DirAccess.remove_absolute(audio)
		if not dec.get("ok", false):
			continue
		var grid: Dictionary = AmGrid.track(dec.pcm, int(dec.rate), params.grid)
		# Gitter mitgeben (AmFeatures ab am3-sections legt Abschnitte und bar_density auf dessen Takte)
		var fp: Dictionary = params.features.duplicate(true)
		fp["grid"] = grid
		var feat: Dictionary = AmFeatures.analyze(dec.pcm, int(dec.rate), fp)
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa == null:
			continue
		fa.store_var({"file": f, "split": B.split_of(f), "truth": truth, "grid": grid, "features": feat,
				"dur_ms": float(dec.duration_ms)})
		fa.close()
		print("  [%d] %s %s %.0f s" % [n, B.split_of(f), B._short(f), (Time.get_ticks_msec() - t0) / 1000.0])
	print("fertig: %d Sets, %.0f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	return 0


static func _load(cache: String, split: String) -> Array:
	var out: Array = []
	var names := DirAccess.get_files_at(cache)
	var sorted: Array = Array(names)
	sorted.sort()
	for nm in sorted:
		if not String(nm).ends_with(".bin"):
			continue
		var fa := FileAccess.open(cache.path_join(nm), FileAccess.READ)
		if fa == null:
			continue
		var d = fa.get_var()
		fa.close()
		if d is Dictionary and (split == "" or d.split == split):
			out.append(d)
	return out


# ---------------------------------------------------------------------------
# 2. Lernen
# ---------------------------------------------------------------------------

## Beispiele eines Sets je Profil: {profil: {x: Array[PackedFloat32Array], y, yc, yh}}.
static func _examples(song: Dictionary, P: Dictionary) -> Dictionary:
	var out := {}
	var grid: Dictionary = song.grid
	if not grid.get("ok", false) or not song.features.get("ok", false):
		return out
	var G := AmChart._grid(grid)
	if int(G["n"]) == 0:
		return out
	var C := AmChart._prep(song.features, G, P)
	var n: int = C["n"]
	if n == 0:
		return out
	var X: Array = AmChart.row_features(C)
	var ct: PackedFloat64Array = C["t"]
	for p in AmChart.PROFILES:
		var hi := B.pick_human_diff(song.truth.diffs4k, p)
		if hi < 0:
			continue
		var hd: Dictionary = song.truth.diffs4k[hi]
		var ht := PackedFloat64Array(hd.times)
		var hs := {}
		for h in hd.holds:
			hs[int(round(float(h[0])))] = float(h[1]) - float(h[0])
		var hl := PackedFloat32Array()   # je Zeile: Hold-Laenge des Menschen in Schlaegen (0 = kein Hold)
		hl.resize(n)
		var bms: PackedFloat64Array = C["beat_ms"]
		var y := PackedByteArray()
		var yc := PackedByteArray()
		var yh := PackedByteArray()
		y.resize(n)
		yc.resize(n)
		yh.resize(n)
		var hit := 0
		var j := 0
		for r in n:
			var t := ct[r]
			while j < ht.size() and ht[j] < t - TOL:
				j += 1
			var cnt := 0
			var hold := false
			var k := j
			while k < ht.size() and ht[k] <= t + TOL:
				cnt += 1
				if hs.has(int(round(ht[k]))):
					hold = true
					hl[r] = maxf(hl[r], float(hs[int(round(ht[k]))]) / bms[r])
				k += 1
			if cnt > 0:
				y[r] = 1
				hit += 1
			if cnt >= 2:
				yc[r] = 1
			if hold:
				yh[r] = 1
		# Gitter daneben (Tempo/Versatz): Zeilen treffen kaum Menschen-Noten -> nichts lernen
		if float(hit) < 0.35 * float(mini(n, ht.size())):
			continue
		var hrows := 0
		var last := -1e9
		for ti in ht:
			if ti - last > 2.0:
				hrows += 1
			last = ti
		out[p] = {"x": X, "y": y, "yc": yc, "yh": yh, "susb": C["susb"], "hl": hl,
				"n_rows": n, "n_pos": hit, "n_hrows": hrows, "n_hnotes": ht.size()}
	return out


## Adagrad, logistisch, L2. data: Array von [X: Array[PackedFloat32Array], y: PackedByteArray, rows: PackedInt32Array].
static func _train(data: Array, dim: int, epochs: int, l2: float, lr: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(dim)
	var g2 := PackedFloat32Array()
	g2.resize(dim)
	g2.fill(1e-6)
	var order: Array = []
	for di in data.size():
		var rows: PackedInt32Array = data[di][2]
		for r in rows:
			order.append(di * 1000000 + r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for ep in epochs:
		# feste Mischung je Epoche
		for i in range(order.size() - 1, 0, -1):
			var k := rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[k]
			order[k] = tmp
		var loss := 0.0
		for code: int in order:
			var di := code / 1000000
			var r := code % 1000000
			var x: PackedFloat32Array = data[di][0][r]
			var z := 0.0
			for f in dim:
				var xv := x[f]
				if xv != 0.0:
					z += w[f] * xv
			var pr := 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))
			var yv := float((data[di][1] as PackedByteArray)[r])
			loss -= log(maxf(pr if yv > 0.5 else 1.0 - pr, 1e-9))
			var g := pr - yv
			for f in dim:
				var xv := x[f]
				if xv != 0.0:
					var gf := g * xv + l2 * w[f]
					g2[f] += gf * gf
					w[f] -= lr * gf / sqrt(g2[f])
		print("    Epoche %d: Verlust %.4f" % [ep + 1, loss / maxf(order.size(), 1.0)])
	return w


static func _auc(data: Array, w: PackedFloat32Array) -> float:
	var pos: Array = []
	var neg: Array = []
	for d in data:
		var rows: PackedInt32Array = d[2]
		for r in rows:
			var x: PackedFloat32Array = d[0][r]
			var z := 0.0
			for f in w.size():
				z += w[f] * x[f]
			if (d[1] as PackedByteArray)[r] == 1:
				pos.append(z)
			else:
				neg.append(z)
	if pos.is_empty() or neg.is_empty():
		return NAN
	var all: Array = []
	for z in pos:
		all.append([z, 1])
	for z in neg:
		all.append([z, 0])
	all.sort_custom(func(a, b): return a[0] < b[0])
	var rank_sum := 0.0
	for i in all.size():
		if all[i][1] == 1:
			rank_sum += i + 1
	return (rank_sum - pos.size() * (pos.size() + 1) / 2.0) / (float(pos.size()) * neg.size())


func _fit(args: PackedStringArray, cache: String) -> int:
	var epochs := int(B._arg(args, "--epochs", "10"))
	var l2 := float(B._arg(args, "--l2", "0.0003"))
	var lr := float(B._arg(args, "--lr", "0.08"))
	var params := _params()
	var P := AmChart._params(params.chart)
	P["select_model"] = false
	var t0 := Time.get_ticks_msec()
	var sets := {"tune": _load(cache, "tune"), "test": _load(cache, "test")}
	print("Sets: Abstimm %d, Pruef %d" % [sets.tune.size(), sets.test.size()])
	var ex := {"tune": [], "test": []}
	for sp in sets:
		for s in sets[sp]:
			ex[sp].append(_examples(s, P))
	var names: Array = AmChart.ROW_FEATURES
	var dim := names.size()
	var model := {"version": 1, "features": names, "tol_ms": TOL,
			"trained": "%s, %d Sets Abstimm-Menge" % [Time.get_date_string_from_system(), sets.tune.size()],
			"profiles": {}}
	var log_lines: Array = []
	for p in AmChart.PROFILES:
		var m := {}
		var tot := [0, 0, 0, 0]
		for e in ex.tune:
			if e.has(p):
				tot[0] += int(e[p].n_rows)
				tot[1] += int(e[p].n_pos)
				tot[2] += int(e[p].n_hrows)
				tot[3] += int(e[p].n_hnotes)
		print("%s: Kandidat-Zeilen %d, davon auf Menschen-Zeile %d (%.1f %%), Menschen-Zeilen %d (gedeckt %.1f %%), Menschen-Noten %d" % [
				p, tot[0], tot[1], 100.0 * tot[1] / maxf(tot[0], 1), tot[2], 100.0 * tot[1] / maxf(tot[2], 1), tot[3]])
		if args.has("--stats"):
			continue
		for task in ["note", "chord", "hold", "hold_any"]:
			var dt := {"tune": [], "test": []}
			for sp in dt:
				for e in ex[sp]:
					if not e.has(p):
						continue
					var E: Dictionary = e[p]
					var rows := PackedInt32Array()
					var yarr: PackedByteArray = E.y
					if task == "chord":
						yarr = E.yc
					elif task == "hold" or task == "hold_any":
						yarr = E.yh
					var susb: PackedFloat64Array = E.susb
					for r in (E.y as PackedByteArray).size():
						if task == "note":
							rows.append(r)
						elif task == "chord" and E.y[r] == 1:
							rows.append(r)
						elif task == "hold" and E.y[r] == 1 and susb[r] >= 0.24:
							rows.append(r)
						elif task == "hold_any" and E.y[r] == 1:
							rows.append(r)
					dt[sp].append([E.x, yarr, rows])
			var w := _train(dt.tune, dim, epochs, l2, lr)
			var a_tune := _auc(dt.tune, w)
			var a_test := _auc(dt.test, w)
			var line := "%s %s: AUC Abstimm %.3f, Pruef %.3f" % [p, task, a_tune, a_test]
			print(line)
			log_lines.append(line)
			var wd := {}
			for f in dim:
				wd[names[f]] = snappedf(w[f], 0.0001)
			m[task] = wd
			m[task + "_auc_test"] = snappedf(a_test, 0.001)
		# Hold-Laenge: Mensch gegen gehaltenen Ton (Schlaege), Zeilen mit Menschen-Hold und sustain
		var ratios: Array = []
		var lens: Array = []
		for e in ex.tune:
			if not e.has(p):
				continue
			var E: Dictionary = e[p]
			var hl: PackedFloat32Array = E.hl
			var susb: PackedFloat64Array = E.susb
			for r in hl.size():
				if hl[r] > 0.0:
					lens.append(float(hl[r]))
					if susb[r] >= 0.24:
						ratios.append(float(hl[r]) / susb[r])
		if not lens.is_empty():
			m["hold_len"] = {"ratio_med": snappedf(B.median(ratios), 0.001) if not ratios.is_empty() else 1.0,
					"len_med": snappedf(B.median(lens), 0.001), "len_p90": snappedf(B.percentile(lens, 90.0), 0.001),
					"n": lens.size(), "n_sus": ratios.size()}
			print("%s Hold-Laenge: %s" % [p, JSON.stringify(m["hold_len"])])
		model.profiles[p] = m
	print("Zeit %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if args.has("--dry"):
		return 0
	var fa := FileAccess.open(ProjectSettings.globalize_path(SELECT_PATH), FileAccess.WRITE)
	fa.store_string(JSON.stringify(model, "\t") + "\n")
	fa.close()
	print("geschrieben: ", SELECT_PATH)
	return 0


# ---------------------------------------------------------------------------
# 3. Messen ohne Audio
# ---------------------------------------------------------------------------

func _eval(args: PackedStringArray, cache: String) -> int:
	var split := B._arg(args, "--set", "test")
	var params := _params()
	var cp: Dictionary = params.chart.duplicate(true)
	var extra := _kv(B._arg(args, "--chart", ""))
	for k in extra:
		cp[k] = extra[k]
	if args.has("--no-model"):
		cp["select_model"] = false
	var mods: Dictionary = B.load_mods("new")
	var pats := AmChart._patterns(AmChart._params(cp))
	var recs: Array = []
	var t0 := Time.get_ticks_msec()
	var songs := _load(cache, split)
	var diag := {}
	for s in songs:
		var prod := _product(s, cp, mods)
		var rec := B.song_record(s.file, s.truth, prod, 0.0, float(s.dur_ms))
		var st := {}
		for p in prod.charts:
			if prod.charts[p].ok:
				st[p] = AmChart.estimate_stars(prod.charts[p].notes) * float(pats.star_a) + float(pats.star_b)
				var band: Array = B.STAR_BANDS[p]
				var dkey: String = "d_" + str(p)
				if not diag.has(dkey):
					diag[dkey] = [0, 0, 0]
				var d0 := float(prod.charts[p].stats.get("density", 0.0))
				diag[dkey][0 if d0 < 0.999 else (1 if d0 < 1.001 else 2)] += 1
				if float(st[p]) < float(band[0]):
					var key: String = "low_" + str(p)
					if not diag.has(key):
						diag[key] = [0, 0, 0.0]
					diag[key][0] += 1
					var dd := float(prod.charts[p].stats.get("density", 0.0))
					if dd >= 1.9:
						diag[key][1] += 1
					diag[key][2] += dd
					if args.has("--low"):
						var hs := []
						for hd in s.truth.diffs4k:
							hs.append(snappedf(float(hd.stars), 0.01))
						print("    unter Band %s %s: %.2f Sterne, d %.2f, BPM erzeugt %.0f / Map %s, Tempo exakt %s, Menschen-Sterne %s" % [p, B._short(s.file),
								float(st[p]), dd, 60000.0 / float(s.grid.segments[0].beat_ms), str(snappedf(float(rec.get("bpm", 0.0)), 0.1)),
								str(rec.get("tempo_exact", "-")), str(hs)])
		rec["stars"] = st
		recs.append(rec)
		_diag_add(diag, s, prod)
		# Auswahl-Eigenschaft: Stellen des leichteren Profils fehlen im schwereren
		if prod.ok:
			for pi in range(AmChart.PROFILES.size() - 1):
				var lo_t := {}
				for nt in prod.charts[AmChart.PROFILES[pi + 1]].notes:
					lo_t[int(round(float(nt.t_ms)))] = true
				for nt in prod.charts[AmChart.PROFILES[pi]].notes:
					if not lo_t.has(int(round(float(nt.t_ms)))):
						diag["subset_bad"] = int(diag.get("subset_bad", 0)) + 1
		if args.has("--rank"):
			_rank_add(diag, s, prod, cp)
	var a := B.aggregate(recs, split)
	print("Sets %d, %.0f s" % [songs.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for row in B.target_rows(a, mods.caps):
		if String(row[0]) in ["Noten", "Holds", "Stufen", "Spielbarkeit"]:
			print("  %s | %s | %s" % [row[1], row[3], row[4]])
	# je Profil
	for p in AmChart.PROFILES:
		var pa: Dictionary = a.get("per", {}).get(p, {})
		print("  %s: %s" % [p, JSON.stringify(_short_prof(pa))])
	print("  Stellen im leichteren Profil, die im schwereren fehlen: %d" % int(diag.get("subset_bad", 0)))
	for p in AmChart.PROFILES:
		if diag.has("d_" + p):
			print("  %s Dichte d: < 1: %d, = 1: %d, > 1: %d" % [p, diag["d_" + p][0], diag["d_" + p][1], diag["d_" + p][2]])
		if diag.has("low_" + p):
			var lw: Array = diag["low_" + p]
			print("  %s unter dem Band: %d, davon d >= 1,9: %d, mittleres d %.2f" % [p, lw[0], lw[1], lw[2] / maxf(lw[0], 1)])
		if diag.has("rank_" + p):
			var rk: Array = diag["rank_" + p]
			print("  %s Rangfolge: beste %d von %d Kandidaten, davon auf Menschen-Zeile %.1f %%" % [p, rk[0], rk[2], 100.0 * rk[1] / maxf(rk[0], 1)])
		if diag.has(p):
			var d: Dictionary = diag[p]
			print("  %s Zeilen: erzeugt %d, auf Menschen-Zeile %.1f %%, Akkord-Zeilen erzeugt %.1f %% / Mensch %.1f %%, Noten je Zeile erzeugt %.2f / Mensch %.2f, Zeilen-Treffer mit Akkord-Fehler %.1f %%, Holds je Note erzeugt %.1f %% / Mensch %.1f %%" % [
					p, d.g_rows, 100.0 * d.g_hit / maxf(d.g_rows, 1), 100.0 * d.g_ch / maxf(d.g_rows, 1), 100.0 * d.h_ch / maxf(d.h_rows, 1),
					float(d.g_notes) / maxf(d.g_rows, 1), float(d.h_notes) / maxf(d.h_rows, 1), 100.0 * d.size_mis / maxf(d.g_hit, 1),
					100.0 * d.g_holds / maxf(d.g_notes, 1), 100.0 * d.h_holds / maxf(d.h_notes, 1)])
	if args.has("--json"):
		var fo := FileAccess.open(B._arg(args, "--json"), FileAccess.WRITE)
		fo.store_string(JSON.stringify(recs))
		fo.close()
	return 0


## Zeilen (gleiche Zeit) aus sortierten Zeiten: [[t, Anzahl], ...]
static func _rows(times: Array) -> Array:
	var out: Array = []
	for t in times:
		if not out.is_empty() and float(t) - float(out[-1][0]) <= 2.0:
			out[-1][1] += 1
		else:
			out.append([float(t), 1])
	return out


static func _diag_add(diag: Dictionary, s: Dictionary, prod: Dictionary) -> void:
	if not prod.ok:
		return
	for p in AmChart.PROFILES:
		var hi := B.pick_human_diff(s.truth.diffs4k, p)
		if hi < 0 or not prod.charts[p].ok:
			continue
		if not diag.has(p):
			diag[p] = {"g_rows": 0, "g_hit": 0, "g_ch": 0, "h_rows": 0, "h_ch": 0, "g_notes": 0, "h_notes": 0, "size_mis": 0,
					"g_holds": 0, "h_holds": 0}
		var d: Dictionary = diag[p]
		for nt in prod.charts[p].notes:
			if float(nt.end_ms) > float(nt.t_ms):
				d.g_holds += 1
		d.h_holds += (s.truth.diffs4k[hi].holds as Array).size()
		var gr := _rows(B._times(prod.charts[p].notes))
		var hr := _rows(s.truth.diffs4k[hi].times)
		d.g_rows += gr.size()
		d.h_rows += hr.size()
		var j := 0
		for g in gr:
			d.g_notes += int(g[1])
			if int(g[1]) >= 2:
				d.g_ch += 1
			while j < hr.size() and float(hr[j][0]) < float(g[0]) - TOL:
				j += 1
			if j < hr.size() and absf(float(hr[j][0]) - float(g[0])) <= TOL:
				d.g_hit += 1
				if int(hr[j][1]) != int(g[1]):
					d.size_mis += 1
		for h in hr:
			d.h_notes += int(h[1])
			if int(h[1]) >= 2:
				d.h_ch += 1


## Obere Grenze der Rangfolge: Trefferquote der besten K Zeilen nach Modell (K = erzeugte Zeilen),
## gegen die Zeilen, die der Setzer wirklich gesetzt hat.
static func _rank_add(diag: Dictionary, s: Dictionary, prod: Dictionary, cp: Dictionary) -> void:
	if not prod.ok:
		return
	var P := AmChart._params(cp)
	var ex := _examples(s, P)
	var model := AmChart._select_model(P)
	for p in ex:
		if not model.has(p) or not prod.charts[p].ok:
			continue
		var E: Dictionary = ex[p]
		var z := AmChart._logits(E.x, model[p]["note"])
		var gr := _rows(B._times(prod.charts[p].notes))
		var idx: Array = []
		for r in z.size():
			var xr: PackedFloat32Array = E.x[r]
			# nur Zeilen, die der Setzer in diesem Profil nehmen darf (keine Triolen/Feineres, keine Zwischen-Zeilen)
			if xr[45] == 0.0 and (p == "Expert" or (xr[20] == 0.0 and xr[21] == 0.0)):
				idx.append(r)
		idx.sort_custom(func(a, b): return z[a] > z[b])
		var k := mini(gr.size(), idx.size())
		var hit := 0
		for i in k:
			hit += int((E.y as PackedByteArray)[idx[i]])
		var key: String = "rank_" + str(p)
		if not diag.has(key):
			diag[key] = [0, 0, 0]
		diag[key][0] += k
		diag[key][1] += hit
		diag[key][2] += int(E.n_rows)


static func _short_prof(pa: Dictionary) -> Dictionary:
	var o := {}
	for k in pa:
		var v = pa[k]
		if v is float:
			o[k] = snappedf(v, 0.001)
		elif v is int or v is String:
			o[k] = v
	return o


static func _product(s: Dictionary, cp: Dictionary, mods: Dictionary) -> Dictionary:
	var grid: Dictionary = s.grid
	var feat: Dictionary = s.features
	var prod := {"ok": false, "error": "", "segments": [], "alternatives": [], "confidence": -1.0,
			"kiai": [], "charts": {}, "lint": {}, "caps": mods.caps, "stage_ms": {}}
	if not grid.get("ok", false) or (grid.get("segments", []) as Array).is_empty() or not feat.get("ok", false):
		prod.error = "Kette fehlgeschlagen"
		return prod
	for sg in grid.segments:
		prod.segments.append({"start_ms": float(sg.start_ms), "beat_ms": float(sg.beat_ms),
				"meter": int(sg.get("meter", 4)), "downbeat_ms": float(sg.get("downbeat_ms", sg.start_ms))})
	for alt in grid.get("alternatives", []):
		prod.alternatives.append(float(alt.factor) if alt is Dictionary else float(alt))
	prod.kiai = B.merge_intervals(AmWriter.kiai_ranges(feat, grid))
	var all := AmChart.build_all(feat, grid, cp, "Easy")
	for p in AmChart.PROFILES:
		var ch: Dictionary = all[p]
		prod.charts[p] = {"ok": bool(ch.ok), "error": str(ch.error), "notes": ch.notes, "stats": ch.get("stats", {})}
		var lv: Array = AmChart.lint(ch.notes, grid, p) if ch.ok else []
		prod.lint[p] = lv.size() if ch.ok else -1
		for m in lv:
			print("    lint %s %s: %s" % [p, B._short(s.file), m])
	prod.ok = true
	return prod


## Hard frei gewaehlt: gesetzte Zeilen gegen die besten K nach Modell (K = gesetzte Zeilen), aufgeschluesselt.
func _debug(args: PackedStringArray, cache: String) -> int:
	var params := _params()
	var cp: Dictionary = params.chart.duplicate(true)
	var extra := _kv(B._arg(args, "--chart", ""))
	for k in extra:
		cp[k] = extra[k]
	var P := AmChart._params(cp)
	var prof := B._arg(args, "--profile", "Hard")
	var pats := AmChart._patterns(P)
	var tot := {"k": 0, "set_hit": 0, "top_hit": 0, "only_set": 0, "only_set_hit": 0, "only_top": 0, "only_top_hit": 0,
			"os_tmpl": 0, "os_rare": 0, "os_fill": 0, "ot_rare": 0, "ot_tmpl": 0, "ot_burst": 0}
	for s in _load(cache, B._arg(args, "--set", "tune")):
		var ex := _examples(s, P)
		if not ex.has(prof):
			continue
		var G := AmChart._grid(s.grid)
		var C := AmChart._prep(s.features, G, P)
		C["X"] = AmChart.row_features(C)
		C["model"] = AmChart._select_model(P)
		var res := AmChart._tune(C, G, prof, {}, P, pats)
		var fl: PackedByteArray = res["flags"]
		var y: PackedByteArray = ex[prof].y
		var z := AmChart._logits(C["X"], C["model"][prof]["note"])
		var tick: PackedInt32Array = C["tick"]
		var fill: PackedByteArray = C["fill"]
		var tmpl: PackedInt32Array = C["tmpl"]
		var idx: Array = []
		for r in z.size():
			if fill[r] == 0 and posmod(tick[r], 3) == 0:
				idx.append(r)
		idx.sort_custom(func(a, b): return z[a] > z[b])
		var k := 0
		for r in fl.size():
			k += int(fl[r])
		var top := PackedByteArray()
		top.resize(fl.size())
		for i in mini(k, idx.size()):
			top[idx[i]] = 1
		tot.k += k
		# Dichte (2-s-Fenster) gegen den Menschen: gesetzt, Summe p, alle Kandidaten
		var hd: Dictionary = s.truth.diffs4k[B.pick_human_diff(s.truth.diffs4k, prof)]
		var ct: PackedFloat64Array = C["t"]
		var t_end := float(hd.times[-1]) + 2000.0
		var nw := int(t_end / B.DENS_WIN_MS) + 1
		var wsel := []
		var wp := []
		var wall := []
		var wnotes := []
		for a in [wsel, wp, wall, wnotes]:
			a.resize(nw)
			a.fill(0.0)
		for r in fl.size():
			var w := int(ct[r] / B.DENS_WIN_MS)
			if w < 0 or w >= nw:
				continue
			if fl[r] == 1:
				wsel[w] += 1.0
			if fill[r] == 0 and posmod(tick[r], 3) == 0:
				wp[w] += 1.0 / (1.0 + exp(-z[r]))
				wall[w] += 1.0
		for nt in res["notes"]:
			var w := int(float(nt.t_ms) / B.DENS_WIN_MS)
			if w >= 0 and w < nw:
				wnotes[w] += 1.0
		var hum := B.density_curve(hd.times, t_end)
		for key in ["c_rows", "c_p", "c_all", "c_notes"]:
			if not tot.has(key):
				tot[key] = 0.0
		tot.c_rows += B.pearson(hum, wsel.slice(0, hum.size()))
		tot.c_p += B.pearson(hum, wp.slice(0, hum.size()))
		tot.c_all += B.pearson(hum, wall.slice(0, hum.size()))
		tot.c_notes += B.pearson(hum, wnotes.slice(0, hum.size()))
		tot["n_songs"] = int(tot.get("n_songs", 0)) + 1
		for r in fl.size():
			if fl[r] == 1:
				tot.set_hit += int(y[r])
			if top[r] == 1:
				tot.top_hit += int(y[r])
			if fl[r] == 1 and top[r] == 0:
				tot.only_set += 1
				tot.only_set_hit += int(y[r])
				tot.os_tmpl += int(tmpl[r] >= 0)
				tot.os_rare += int(posmod(tick[r], 6) != 0)
				tot.os_fill += int(fill[r])
			if top[r] == 1 and fl[r] == 0:
				tot.only_top += 1
				tot.only_top_hit += int(y[r])
				tot.ot_rare += int(posmod(tick[r], 6) != 0)
				tot.ot_tmpl += int(tmpl[r] >= 0)
	print(JSON.stringify(tot))
	return 0
