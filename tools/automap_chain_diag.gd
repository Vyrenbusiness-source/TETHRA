extends SceneTree

## OMEN Auto-Mapper 4K: Uebergaenge der Kette messen (AmFeatures -> AmGrid -> AmChart).
## Ein Prozess fuer viele Maps, beendet sich selbst. Gibt Markdown-Tabellen aus.
##   timeout 3600 Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
##       --script res://tools/automap_chain_diag.gd -- --maps <maps-ordner> [--set tune|test] [--songs 40]
##       [--chart k=v,k=v] [--features k=v,...]
##
## Gemessen je Ereignis-Art: Zeitlage gegen Menschen-Noten und gegen das erzeugte Gitter, Trefferquote
## nach Staerke, obere Grenze der Kette (Anteil der Menschen-Noten mit irgendeinem eingerasteten
## Ereignis), Auswahl des Setzers (Hard) je Art, Dichte (Ereignisse, Intensitaet, erzeugt) gegen Mensch.

const B := preload("res://tools/automap_bench.gd")
const KINDS := ["kick", "snare", "hat", "bass", "tonal", "vocal", "other"]
const TOL := 15.0
const LEAD := 23.0

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_main(OS.get_cmdline_user_args()))
	return true


static func _kv(text: String) -> Dictionary:
	var out := {}
	for item in text.split(",", false):
		var p := item.split("=")
		if p.size() == 2:
			out[p[0]] = float(p[1]) if p[1].is_valid_float() else p[1]
	return out


static func _nearest(sorted: PackedFloat64Array, t: float) -> float:
	var lo := 0
	var hi := sorted.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if sorted[mid] < t:
			lo = mid + 1
		else:
			hi = mid
	var best := INF
	for k in [lo - 1, lo]:
		if k >= 0 and k < sorted.size() and absf(sorted[k] - t) < absf(best):
			best = sorted[k] - t
	return -best   # t - naechste


static func _pct(a: Array, p: float) -> float:
	return B.percentile(a, p) if not a.is_empty() else NAN


func _main(args: PackedStringArray) -> int:
	var maps_dir := B._arg(args, "--maps", "")
	var split := B._arg(args, "--set", "tune")
	var n_songs := int(B._arg(args, "--songs", "40"))
	var params := AutoMapper4K.load_params()
	var cp: Dictionary = params.get("chart", {}).duplicate()
	cp.merge(_kv(B._arg(args, "--chart", "")), true)
	var fp: Dictionary = params.get("features", {}).duplicate()
	fp.merge(_kv(B._arg(args, "--features", "")), true)
	var gp: Dictionary = params.get("grid", {})
	StarService.prefetch_dir(maps_dir)
	var files: Array = preload("res://tools/automap_tune.gd").pick_files(B.list_osz(maps_dir), split, n_songs)
	var tmp := ProjectSettings.globalize_path(B.OUT_DIR)
	DirAccess.make_dir_recursive_absolute(tmp)
	# Sammler
	var off_hum := {}      # Art -> [signed ms] Ereignis(-LEAD) minus naechste Menschen-Note (|d|<=40)
	var off_grid := {}     # Art -> [signed ms] Ereignis(-LEAD) minus naechster 1/4-Gitterpunkt (Tempo richtig)
	var hit_k := {}        # Art -> [hits, n] eingerastet auf Menschen-Note (alle Diffs vereinigt)
	var hit_ks := {}       # "Art|Staerke-Viertel" -> [hits, n]
	var sel_k := {}        # Art (staerkste am Platz) -> [Hard-Noten, davon auf Menschen-Note]
	var slot_k := {}       # Art -> [Plaetze, davon auf Menschen-Hard-Note]
	for k in KINDS:
		off_hum[k] = []
		off_grid[k] = []
		hit_k[k] = [0, 0]
		sel_k[k] = [0, 0]
		slot_k[k] = [0, 0]
	var ub_rec: Array = []       # Anteil der Menschen-Hard-Noten mit eingerastetem Ereignis
	var ub_rec_raw: Array = []   # dasselbe ohne Einrasten (Ereignis-LEAD +-15)
	var gen_prec: Array = []
	var gen_rec: Array = []
	var cnt_ratio: Array = []
	var dens_ev: Array = []
	var dens_int: Array = []
	var dens_gen: Array = []
	var kiai_iou: Array = []
	var kiai_iou_snap: Array = []
	var song_rows: Array = []
	var n_ok := 0
	for f in files:
		var osz: String = maps_dir.path_join(f)
		var truth: Dictionary = B.load_truth(osz, StarService.stars_for(osz))
		if not truth.ok:
			continue
		var hi := B.pick_human_diff(truth.diffs4k, "Hard")
		if hi < 0:
			continue
		var audio := B.extract_file(osz, truth.audio_name, tmp.path_join("diag_audio_tmp"))
		if audio == "":
			continue
		var dec: Dictionary = AmFeatures.decode(audio)
		DirAccess.remove_absolute(audio)
		if not dec.get("ok", false):
			continue
		var grid: Dictionary = AmGrid.track(dec.pcm, int(dec.rate), gp)
		var feat: Dictionary = AmFeatures.analyze(dec.pcm, int(dec.rate), fp)
		if not grid.get("ok", false) or not feat.get("ok", false):
			continue
		n_ok += 1
		var ts := B.truth_segments(truth.reds, truth.t0, truth.t1)
		var tempo_ok := false
		if ts.segments.size() == 1:
			var t0seg: Dictionary = ts.segments[0].duplicate()
			t0seg.start_ms = truth.t0
			t0seg.end_ms = truth.t1
			var te := B.tempo_eval(grid.segments, t0seg, [])
			tempo_ok = te.exact
		var union := PackedFloat64Array()
		for d in truth.diffs4k:
			for t in d.times:
				union.append(float(t))
		union.sort()
		var hard: Dictionary = truth.diffs4k[hi]
		var hts := PackedFloat64Array()
		for t in hard.times:
			hts.append(float(t))
		var hset := PackedFloat64Array()   # Zeilen (einmal je Zeit)
		for t in hts:
			if hset.is_empty() or t - hset[hset.size() - 1] > 2.0:
				hset.append(t)
		# Ereignisse: Lage, Einrasten wie AmChart (1/4, sonst 1/8), Treffer
		var snapped := PackedFloat64Array()
		var raw_t := PackedFloat64Array()
		var slot_kind := {}   # gerundete ms -> [Art der staerksten, Staerke]
		for ev in feat.events:
			var k := str(ev.kind)
			var t := float(ev.t_ms) - LEAD
			raw_t.append(t)
			var dh := _nearest(union, t)
			if absf(dh) <= 40.0:
				off_hum[k].append(dh)
			var q4 := AmGrid.snap(grid, t, 4)
			var q8 := AmGrid.snap(grid, t, 8)
			if tempo_ok:
				var dg := t - q4
				if absf(dg) <= float(grid.segments[0].beat_ms) / 8.0:
					off_grid[k].append(dg)
			var s := q4 if absf(t - q4) <= absf(t - q8) + 6.0 else q8
			snapped.append(s)
			var hit := absf(_nearest(union, s)) <= TOL
			hit_k[k][1] += 1
			if hit:
				hit_k[k][0] += 1
			var sq := clampi(int(float(ev.strength) * 4.0), 0, 3)
			var key := "%s|%d" % [k, sq]
			if not hit_ks.has(key):
				hit_ks[key] = [0, 0]
			hit_ks[key][1] += 1
			if hit:
				hit_ks[key][0] += 1
			var sk := int(roundf(s))
			if not slot_kind.has(sk) or float(ev.strength) > float(slot_kind[sk][1]):
				slot_kind[sk] = [k, float(ev.strength)]
		snapped.sort()
		raw_t.sort()
		var cov := 0
		var cov_raw := 0
		for t in hset:
			if absf(_nearest(snapped, t)) <= TOL:
				cov += 1
			if absf(_nearest(raw_t, t)) <= TOL:
				cov_raw += 1
		ub_rec.append(float(cov) / maxi(hset.size(), 1))
		ub_rec_raw.append(float(cov_raw) / maxi(hset.size(), 1))
		for sk in slot_kind:
			var k: String = slot_kind[sk][0]
			slot_k[k][0] += 1
			if absf(_nearest(hts, float(sk))) <= TOL:
				slot_k[k][1] += 1
		# Setzer Hard
		var ch: Dictionary = AmChart.build(feat, grid, "Hard", cp)
		var gt: Array = []
		for n in ch.get("notes", []):
			gt.append(float(n.t_ms))
		gt.sort()
		var m := B.match_count(gt, hard.times)
		gen_prec.append(float(m) / maxi(gt.size(), 1))
		gen_rec.append(float(m) / maxi(hard.times.size(), 1))
		cnt_ratio.append(float(gt.size()) / maxi(hard.times.size(), 1))
		var seen := {}
		for t in gt:
			var sk := int(roundf(t))
			if seen.has(sk):
				continue
			seen[sk] = true
			var kk := ""
			for dk in [0, -1, 1]:
				if slot_kind.has(sk + dk):
					kk = slot_kind[sk + dk][0]
			if kk == "":
				continue
			sel_k[kk][0] += 1
			if absf(_nearest(hts, t)) <= TOL:
				sel_k[kk][1] += 1
		# Dichte (2-s-Fenster)
		var t_end := float(hard.times[-1]) + 1.0
		var hc: Array = B.density_curve(hard.times, t_end)
		var ec: Array = B.density_curve(Array(snapped), t_end)
		var ic: Array = []
		ic.resize(hc.size())
		ic.fill(0.0)
		for sec in feat.sections:
			for w in hc.size():
				var c := (w + 0.5) * B.DENS_WIN_MS
				if c >= float(sec.start_ms) - LEAD and c < float(sec.end_ms) - LEAD:
					ic[w] = float(sec.intensity)
		var gc: Array = B.density_curve(gt, t_end)
		dens_ev.append(B.pearson(ec, hc))
		dens_int.append(B.pearson(ic, hc))
		dens_gen.append(B.pearson(gc, hc))
		# Kiai roh und auf Taktanfang gerastet
		var kraw: Array = []
		var ksnap: Array = []
		for sec in feat.sections:
			if sec.get("kiai", false):
				kraw.append([float(sec.start_ms), float(sec.end_ms)])
				ksnap.append([_bar_snap(grid, float(sec.start_ms) - LEAD), _bar_snap(grid, float(sec.end_ms) - LEAD)])
		if not (truth.kiai as Array).is_empty() or not kraw.is_empty():
			kiai_iou.append(B.interval_iou(B.merge_intervals(kraw), truth.kiai))
			kiai_iou_snap.append(B.interval_iou(B.merge_intervals(ksnap), truth.kiai))
		song_rows.append([B._short(f), "ja" if tempo_ok else "nein", "%.2f" % ub_rec[-1], "%.2f" % gen_prec[-1],
				"%.2f" % gen_rec[-1], "%.2f" % cnt_ratio[-1], "%.2f" % dens_gen[-1]])
		print("  " + " | ".join(PackedStringArray(song_rows[-1])))
	print("\n## Kette: %d Sets (%s), chart-params %s\n" % [n_ok, split, JSON.stringify(cp)])
	var rows: Array = []
	for k in KINDS:
		var hk: Array = hit_k[k]
		rows.append([k, str(hk[1]), "%.1f" % _pct(off_hum[k], 50.0), "%.1f / %.1f" % [_pct(off_hum[k], 25.0), _pct(off_hum[k], 75.0)],
				"%.1f" % _pct(off_grid[k], 50.0), "%.3f" % (float(hk[0]) / maxi(hk[1], 1)),
				"%.3f" % (float(slot_k[k][1]) / maxi(slot_k[k][0], 1)), str(sel_k[k][0]),
				"%.3f" % (float(sel_k[k][1]) / maxi(sel_k[k][0], 1))])
	print(B._table(["Art", "Ereignisse", "Lage gegen Mensch (Median ms, + = spaet)", "Quartile", "Lage gegen Gitter 1/4 (Median ms)",
			"eingerastet auf Menschen-Note (alle Diffs)", "Platz (staerkste Art) auf Hard-Note", "Hard-Noten mit dieser Art", "davon auf Hard-Note"], rows))
	rows = []
	for k in KINDS:
		var r: Array = [k]
		for q in 4:
			var v = hit_ks.get("%s|%d" % [k, q], [0, 0])
			r.append("%.3f (%d)" % [float(v[0]) / maxi(v[1], 1), v[1]] if v[1] > 0 else "-")
		rows.append(r)
	print(B._table(["Art", "Staerke 0-0,25", "0,25-0,5", "0,5-0,75", "0,75-1"], rows))
	print(B._table(["Kennzahl", "Mittel", "Median"], [
		["obere Grenze: Menschen-Hard-Zeilen mit eingerastetem Ereignis (+-15 ms)", "%.3f" % B.mean(ub_rec), "%.3f" % B.median(ub_rec)],
		["dasselbe ohne Einrasten", "%.3f" % B.mean(ub_rec_raw), "%.3f" % B.median(ub_rec_raw)],
		["Hard erzeugt: auf Menschen-Note", "%.3f" % B.mean(gen_prec), "%.3f" % B.median(gen_prec)],
		["Hard erzeugt: Menschen-Noten getroffen", "%.3f" % B.mean(gen_rec), "%.3f" % B.median(gen_rec)],
		["Notenzahl erzeugt/Mensch", "%.3f" % B.mean(cnt_ratio), "%.3f" % B.median(cnt_ratio)],
		["Dichte-Korrelation: eingerastete Ereignisse gegen Mensch", "%.3f" % _mean_ok(dens_ev), "-"],
		["Dichte-Korrelation: Abschnitts-Intensitaet gegen Mensch", "%.3f" % _mean_ok(dens_int), "-"],
		["Dichte-Korrelation: Hard erzeugt gegen Mensch", "%.3f" % _mean_ok(dens_gen), "-"],
		["Kiai IoU roh / auf Taktanfang gerastet", "%.3f / %.3f" % [_mean_ok(kiai_iou), _mean_ok(kiai_iou_snap)], "-"],
	]))
	print(B._table(["Set", "Tempo", "obere Grenze", "auf Mensch", "getroffen", "Anzahl", "Dichte"], song_rows))
	return 0


static func _mean_ok(a: Array) -> float:
	var s := 0.0
	var n := 0
	for v in a:
		if v != null and not is_nan(float(v)):
			s += float(v)
			n += 1
	return s / n if n > 0 else NAN


static func _bar_snap(grid: Dictionary, t: float) -> float:
	var segs: Array = grid.segments
	var s: Dictionary = segs[AmGrid._seg_index(grid, t)]
	var bar := float(s.beat_ms) * int(s.get("meter", 4))
	var d := float(s.get("downbeat_ms", s.start_ms))
	return d + roundf((t - d) / bar) * bar
