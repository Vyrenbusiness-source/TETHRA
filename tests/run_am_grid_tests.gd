extends SceneTree

## Headless-Tests und Messung fuer AmGrid (Taktgitter des 4K-Auto-Mappers, OMEN).
## Unit-Tests (synthetische Klick-Tracks, immer):
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_grid_tests.gd
## Messung gegen die roten Timing-Points echter Maps, ein Prozess fuer alle Sets:
##   ... --script res://tests/run_am_grid_tests.gd -- --measure <maps-ordner> <anzahl>
##       [--cache <ordner>] [--out <grid.md>] [--dump <tsv>] [--params <json>]
## --cache: Onset-Fluss je Set wird dort abgelegt (zweiter Lauf braucht kein ffmpeg).
## --out: Tabelle zwischen den Marken MESSUNG:BEGIN/END (Standard docs/automap/grid.md).

const G := preload("res://scripts/automap/am_grid.gd")
const RATE := 22050
const TOL := 0.005
const SPEC_ALTS := [2.0, 0.5, 1.5, 0.6667]

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _run() -> void:
	print("=== OMEN AmGrid-Tests ===")
	var args := OS.get_cmdline_user_args()
	var mi := args.find("--measure")
	if mi >= 0 and mi + 1 < args.size():
		var cnt := int(args[mi + 2]) if mi + 2 < args.size() and args[mi + 2].is_valid_int() else 200
		_measure(args[mi + 1], cnt, args)
		quit(0)
		return
	_test_api()
	_test_synth()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


static func _wrap(d: float, T: float) -> float:
	return fposmod(d + T * 0.5, T) - T * 0.5


# ---------------------------------------------------------------------------
# Unit-Tests
# ---------------------------------------------------------------------------

func _test_api() -> void:
	var g := {"ok": true, "segments": [
			{"start_ms": 100.0, "beat_ms": 500.0, "meter": 4, "downbeat_ms": 600.0},
			{"start_ms": 8100.0, "beat_ms": 400.0, "meter": 3, "downbeat_ms": 8100.0}],
			"confidence": 1.0, "alternatives": [{"factor": 2.0, "score": 0.5}]}
	_ok(absf(G.snap(g, 1130.0, 1) - 1100.0) < 0.001, "snap 1/1")
	_ok(absf(G.snap(g, 1230.0, 4) - 1225.0) < 0.001, "snap 1/4")
	_ok(absf(G.snap(g, 8290.0, 2) - 8300.0) < 0.001, "snap im 2. Segment")
	_ok(absf(G.snap(g, 8050.0, 1) - 8100.0) < 0.001, "snap an der Segmentgrenze")
	_ok(absf(G.snap(g, 20.0, 1) - 100.0) < 0.001, "snap vor dem ersten Schlag")
	_ok(absf(G.beat_pos(g, 100.0)) < 0.001, "beat_pos 0")
	_ok(absf(G.beat_pos(g, 1350.0) - 2.5) < 0.001, "beat_pos 2,5")
	_ok(absf(G.beat_pos(g, 8500.0) - 17.0) < 0.001, "beat_pos ueber die Grenze")
	_ok(G.is_downbeat(g, 602.0) and not G.is_downbeat(g, 1100.0), "is_downbeat 4/4")
	_ok(G.is_downbeat(g, 2600.0) and G.is_downbeat(g, 9300.0) and not G.is_downbeat(g, 8500.0), "is_downbeat Folgetakte, 3/4")
	var s := G.scaled(g, 2.0)
	_ok(absf(s.segments[0].beat_ms - 250.0) < 0.001 and absf(s.segments[1].beat_ms - 200.0) < 0.001, "scaled x2")
	_ok(absf(g.segments[0].beat_ms - 500.0) < 0.001, "scaled laesst das Original")
	_ok(absf(s.segments[0].start_ms - 100.0) < 0.001 and absf(s.alternatives[0].factor - 1.0) < 0.001, "scaled: Start bleibt, Alternativen umgerechnet")
	_ok(absf(G.scaled(g, 1.5).segments[0].beat_ms - 333.3333) < 0.001, "scaled x1,5")
	var bad := G.track(PackedFloat32Array(), RATE)
	_ok(not bad.ok and bad.segments.is_empty(), "leeres Audio -> ok=false")
	var silent := PackedFloat32Array()
	silent.resize(RATE * 10)
	_ok(not G.track(silent, RATE).ok, "Stille -> ok=false")
	_ok(G.DEFAULTS.has("lead_ms") and G.OSU_LEAD_MS > 0.0, "DEFAULTS/OSU_LEAD_MS")


## kind 0 = Klick (1800 Hz), 1 = Kick (70 Hz + Klick), 2 = Hat (6 kHz).
func _add(s: PackedFloat32Array, t_ms: float, amp: float, kind: int) -> void:
	var i0 := int(round(t_ms * RATE / 1000.0))
	if i0 < 0 or i0 + 3000 >= s.size():
		return
	if kind == 2:
		for j in 120:
			s[i0 + j] += amp * sin(TAU * 6000.0 * j / RATE) * exp(-j / 25.0)
		return
	for j in 220:
		s[i0 + j] += amp * sin(TAU * 1800.0 * j / RATE) * exp(-j / 40.0)
	if kind == 1:
		for j in 2600:
			s[i0 + j] += amp * sin(TAU * 70.0 * j / RATE) * exp(-j / 700.0)


## Schlaege auf off + k*T, Takt-Akzent (Kick) alle `meter` ab Schlag `pickup`, Hats auf den Halben.
func _beats(s: PackedFloat32Array, bpm: float, off: float, t_end: float, meter: int, pickup: int, swing: bool) -> float:
	var T := 60000.0 / bpm
	var k := 0
	var t := off
	while t < t_end:
		var acc := posmod(k - pickup, meter) == 0
		_add(s, t, 0.8 if acc else 0.5, 1 if acc else 0)
		_add(s, t + T * (2.0 / 3.0 if swing else 0.5), 0.3 if swing else 0.2, 0 if swing else 2)
		k += 1
		t = off + k * T
	return t


func _pcm(secs: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(secs * RATE))
	return s


func _test_synth() -> void:
	var lead: float = G.DEFAULTS.lead_ms
	# Ein Tempo.
	for cfg in [[128.0, 350.0], [150.0, 40.0], [174.0, 120.0]]:
		var s := _pcm(60.0)
		_beats(s, cfg[0], cfg[1], 59000.0, 4, 0, false)
		var g := G.track(s, RATE)
		_ok(g.ok, "track ok %s" % str(cfg))
		if not g.ok:
			continue
		var T: float = 60000.0 / cfg[0]
		var sg: Dictionary = g.segments[0]
		_ok(g.segments.size() == 1, "%s: ein Segment (%d)" % [cfg[0], g.segments.size()])
		_ok(absf(sg.bpm - cfg[0]) < 0.02, "BPM %s -> %.3f" % [cfg[0], sg.bpm])
		var oe := absf(_wrap(sg.start_ms + lead - cfg[1], T))
		_ok(oe < 6.0, "%s: Offset-Fehler %.2f ms" % [cfg[0], oe])
		_ok(absf(sg.beat_ms - T) * (59000.0 / T) < 3.0, "%s: Drift < 3 ms" % cfg[0])
		_ok(sg.meter == 4, "%s: Taktart 4 (%d)" % [cfg[0], sg.meter])
		_ok(absf(_wrap(sg.downbeat_ms + lead - cfg[1], 4.0 * T)) < 6.0, "%s: Taktanfang" % cfg[0])
		_ok(sg.start_ms + lead < cfg[1] + 6.0 and sg.start_ms >= 0.0, "%s: start_ms am ersten Schlag (%.1f)" % [cfg[0], sg.start_ms])
		_ok(g.confidence > 0.0 and g.confidence <= 1.0 and g.alternatives.size() > 0, "%s: Vertrauen und Alternativen" % cfg[0])
	# 3/4.
	var s3 := _pcm(60.0)
	_beats(s3, 140.0, 200.0, 59000.0, 3, 0, false)
	var g3 := G.track(s3, RATE)
	_ok(g3.ok and absf(g3.segments[0].bpm - 140.0) < 0.02, "3/4: BPM")
	_ok(g3.ok and g3.segments[0].meter == 3, "3/4: Taktart 3")
	_ok(g3.ok and absf(_wrap(g3.segments[0].downbeat_ms + lead - 200.0, 3.0 * 60000.0 / 140.0)) < 6.0, "3/4: Taktanfang")
	# Auftakt: erster Taktanfang auf Schlag 3.
	var sa := _pcm(60.0)
	_beats(sa, 132.0, 150.0, 59000.0, 4, 3, false)
	var ga := G.track(sa, RATE)
	var Ta := 60000.0 / 132.0
	_ok(ga.ok and absf(ga.segments[0].bpm - 132.0) < 0.02, "Auftakt: BPM")
	_ok(ga.ok and absf(_wrap(ga.segments[0].downbeat_ms + lead - (150.0 + 3.0 * Ta), 4.0 * Ta)) < 6.0, "Auftakt: Taktanfang auf Schlag 3")
	_ok(ga.ok and absf(ga.segments[0].start_ms + lead - 150.0) < 6.0, "Auftakt: start_ms auf dem ersten Schlag")
	_ok(ga.ok and absf(ga.segments[0].downbeat_ms - ga.segments[0].start_ms - 3.0 * Ta) < 1.0, "Auftakt: downbeat_ms = erster Taktanfang im Segment")
	# Swing: Achtel auf 2/3 des Schlags, Tempo bleibt der Schlag.
	var ss := _pcm(60.0)
	_beats(ss, 126.0, 300.0, 59000.0, 4, 0, true)
	var gs := G.track(ss, RATE)
	_ok(gs.ok and absf(gs.segments[0].bpm - 126.0) < 0.02, "Swing: BPM 126 (%.3f)" % (gs.segments[0].bpm if gs.ok else 0.0))
	_ok(gs.ok and absf(_wrap(gs.segments[0].start_ms + lead - 300.0, 60000.0 / 126.0)) < 6.0, "Swing: Offset")
	# Tempowechsel 120 -> 150.
	var sc := _pcm(90.0)
	var t_change := _beats(sc, 120.0, 250.0, 44000.0, 4, 0, false)
	_beats(sc, 150.0, t_change, 89000.0, 4, 0, false)
	var gc := G.track(sc, RATE)
	_ok(gc.ok and gc.segments.size() == 2, "Wechsel: 2 Segmente (%d)" % (gc.segments.size() if gc.ok else 0))
	if gc.ok and gc.segments.size() == 2:
		_ok(absf(gc.segments[0].bpm - 120.0) < 0.1, "Wechsel: 1. Tempo %.3f" % gc.segments[0].bpm)
		_ok(absf(gc.segments[1].bpm - 150.0) < 0.1, "Wechsel: 2. Tempo %.3f" % gc.segments[1].bpm)
		_ok(absf(gc.segments[1].start_ms + lead - t_change) <= 400.0, "Wechsel: Grenze auf 1 Schlag (%.0f statt %.0f)" % [gc.segments[1].start_ms + lead, t_change])
		_ok(absf(_wrap(gc.segments[1].start_ms + lead - t_change, 400.0)) < 6.0, "Wechsel: Phase des 2. Segments")
		_ok(absf(G.beat_pos(gc, gc.segments[1].start_ms + 800.0) - G.beat_pos(gc, gc.segments[1].start_ms) - 2.0) < 0.001, "Wechsel: beat_pos stetig")


# ---------------------------------------------------------------------------
# Messung gegen echte Maps
# ---------------------------------------------------------------------------

## Wahrheit aus den roten Linien: {segs: [{t, bl, meter, end}], reds, last, cat}.
func _truth(bm: Beatmap) -> Dictionary:
	var last := 0.0
	for o in bm.hit_objects:
		last = maxf(last, o.time)
	var reds: Array = []
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append(tp)
	reds.sort_custom(func(a, b): return a.time < b.time)
	var segs: Array = []
	var n_red := 0
	for tp in reds:
		if tp.time > last and not segs.is_empty():
			continue
		n_red += 1
		if segs.is_empty():
			segs.append({"t": tp.time, "bl": tp.beat_length, "meter": tp.meter, "kind": "start"})
			continue
		var pv: Dictionary = segs[segs.size() - 1]
		if absf(tp.beat_length / float(pv.bl) - 1.0) > 0.0005:
			segs.append({"t": tp.time, "bl": tp.beat_length, "meter": tp.meter, "kind": "tempo"})
		elif absf(_wrap(tp.time - float(pv.t), pv.bl)) > 2.5:
			segs.append({"t": tp.time, "bl": tp.beat_length, "meter": tp.meter, "kind": "phase"})
	for i in segs.size():
		segs[i]["end"] = segs[i + 1].t if i + 1 < segs.size() else maxf(last, float(segs[i].t) + 1.0)
	var single := true
	for s in segs:
		if absf(float(s.bl) / float(segs[0].bl) - 1.0) > 0.0005:
			single = false
	var cat := "single" if single else "multi"
	if n_red >= 30 or segs.size() >= 10:
		cat = "wild"
	return {"segs": segs, "reds": n_red, "last": last, "cat": cat}


func _load_env(osz: String, bm: Beatmap, cache_dir: String, name: String) -> Dictionary:
	var cf := cache_dir.path_join(name.md5_text() + ".env")
	if FileAccess.file_exists(cf):
		var f := FileAccess.open(cf, FileAccess.READ)
		var n := f.get_32()
		var hop := f.get_float()
		var feat := {"hop_ms": hop, "flux": f.get_buffer(n * 4).to_float32_array(),
				"low": f.get_buffer(n * 4).to_float32_array(), "zc": f.get_buffer((n + 1) * 4).to_float32_array(), "cached": true}
		f.close()
		return feat
	var bytes := OszImporter.read_file_bytes(osz, bm.audio_filename())
	if bytes.is_empty():
		return {}
	var apath := cache_dir.path_join("tmp_audio." + bm.audio_filename().get_extension())
	var fh := FileAccess.open(apath, FileAccess.WRITE)
	fh.store_buffer(bytes)
	fh.close()
	var pcm := AudioMapper.decode(apath)
	DirAccess.remove_absolute(apath)
	if pcm.size() < RATE * 4:
		return {}
	var feat2: Dictionary = G.envelope(pcm, RATE)
	var fo := FileAccess.open(cf, FileAccess.WRITE)
	fo.store_32(feat2.flux.size())
	fo.store_float(feat2.hop_ms)
	fo.store_buffer(feat2.flux.to_byte_array())
	fo.store_buffer(feat2.low.to_byte_array())
	fo.store_buffer(feat2.zc.to_byte_array())
	fo.close()
	feat2["cached"] = false
	return feat2


func _seg_at(grid: Dictionary, t: float) -> Dictionary:
	var best: Dictionary = grid.segments[0]
	for s in grid.segments:
		if s.start_ms <= t:
			best = s
	return best


## Vorzeichen-Fehler erkannt minus Map am Map-Schlag t.
func _err_at(grid: Dictionary, t: float) -> float:
	var s := _seg_at(grid, t)
	return -_wrap(t - float(s.start_ms), s.beat_ms)


func _ratio_name(r: float) -> String:
	for c in [[2.0, "x2 (Oktave)"], [0.5, "x0,5 (Oktave)"], [1.5, "x1,5 (3:2)"], [0.6667, "x0,667 (2:3)"],
			[0.75, "x0,75 (3:4)"], [1.3333, "x1,333 (4:3)"], [3.0, "x3"], [0.3333, "x0,333"], [4.0, "x4"], [0.25, "x0,25"]]:
		if absf(r / float(c[0]) - 1.0) <= 0.01:
			return c[1]
	return "kein einfaches Verhaeltnis (x%.3f)" % r


func _pct(a: int, b: int) -> String:
	return "%.1f %% (%d von %d)" % [100.0 * a / maxi(b, 1), a, b]


func _quant(v: Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)]


func _measure(maps_dir: String, count: int, args: PackedStringArray) -> void:
	var cache_dir := _arg(args, "--cache", ProjectSettings.globalize_path("user://am_grid_cache"))
	var out_path := _arg(args, "--out", ProjectSettings.globalize_path("res://docs/automap/grid.md"))
	var dump_path := _arg(args, "--dump", "")
	var only := _arg(args, "--only", "")
	var params := {"debug": true}
	var pj := _arg(args, "--params", "")
	if pj != "":
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(pj))
		if parsed is Dictionary:
			params.merge(parsed, true)
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var files: Array[String] = []
	for f in DirAccess.get_files_at(maps_dir):
		if f.to_lower().ends_with(".osz"):
			files.append(f)
	files.sort()
	var step := maxf(1.0, float(files.size()) / maxi(count, 1))
	var dump: FileAccess = FileAccess.open(dump_path, FileAccess.WRITE) if dump_path != "" else null
	var recs: Array = []
	var skipped: Array = []
	var pos := 0.0
	var idx := 0
	while int(pos) < files.size() and recs.size() < count:
		var name := files[int(pos)]
		pos += step
		idx += 1
		if only != "" and not Array(only.split(",")).any(func(o): return name.contains(o)):
			continue
		var osz := maps_dir.path_join(name)
		var imp := OszImporter.import(osz)
		if not imp.ok:
			skipped.append(name + ": nicht lesbar")
			continue
		var bm: Beatmap = null
		for d in imp.difficulties:
			if bm == null or d.beatmap.hit_objects.size() > bm.hit_objects.size():
				bm = d.beatmap
		var tr := _truth(bm)
		if tr.segs.is_empty() or bm.audio_filename() == "":
			skipped.append(name + ": keine rote Linie / kein Audio")
			continue
		var t0 := Time.get_ticks_msec()
		var feat := _load_env(osz, bm, cache_dir, name)
		var t_env := Time.get_ticks_msec() - t0
		if feat.is_empty():
			skipped.append(name + ": Audio nicht dekodierbar")
			continue
		t0 = Time.get_ticks_msec()
		var grid: Dictionary = G.track_env(feat, params)
		var t_trk := Time.get_ticks_msec() - t0
		if not grid.ok:
			skipped.append(name + ": " + str(grid.error))
			continue
		var rec := _eval(name, idx, tr, grid)
		rec["ms"] = t_trk
		rec["env_ms"] = -1 if feat.cached else t_env
		rec["dur"] = feat.flux.size() * float(feat.hop_ms)
		recs.append(rec)
		print("%3d %s | %s | map %.2f det %.2f %s | off %.1f drift %.1f | db %s | seg %d | conf %.2f | %d ms" % [
				recs.size(), name.left(36), rec.cat, rec.bpm_map, rec.bpm_det, "OK" if rec.exact else ("alt" if rec.alt4 else "FALSCH"),
				rec.off, rec.drift, str(rec.db_ok), rec.nseg, rec.conf, t_trk])
		if dump != null:
			_dump(dump, rec, grid, tr)
		if only != "":
			var dbg: Dictionary = grid.get("debug", {})
			print("  map: ", tr.segs.map(func(s): return "%.1f@%.1f m%d" % [60000.0 / float(s.bl), float(s.t), int(s.meter)]))
			print("  det: ", grid.segments.map(func(s): return "%.3f@%.1f m%d db%.1f" % [s.bpm, s.start_ms, s.meter, s.downbeat_ms]))
			for k in dbg:
				if k != "hyps":
					print("  %s: %s" % [k, str(dbg[k])])
			for h in dbg.get("hyps", []):
				print("  H %.3f f%.3f r1 %.3f r2 %.3f r4 %.3f r3 %.3f rl1 %.3f fill %.2f sc %.4f" % [h.bpm, float(h.bpm) / rec.bpm_map, h.r1, h.r2, h.r4, h.r3, h.rl1, h.fill, h.score])
	if dump != null:
		dump.close()
	var md := _report(recs, skipped, files.size())
	print(md)
	_write_out(out_path, md)


func _eval(name: String, idx: int, tr: Dictionary, grid: Dictionary) -> Dictionary:
	var segs: Array = tr.segs
	var M: Dictionary = segs[0]
	for s in segs:
		if float(s.end) - float(s.t) > float(M.end) - float(M.t):
			M = s
	var bl: float = M.bl
	var nb := floorf((float(M.end) - float(M.t)) / bl)
	var mid: float = float(M.t) + floorf(nb * 0.5) * bl
	var D := _seg_at(grid, mid)
	var bpm_map := 60000.0 / bl
	var bpm_det: float = 60000.0 / float(D.beat_ms)
	var ratio := bpm_det / bpm_map
	var rec := {"name": name, "idx": idx, "cat": tr.cat, "reds": tr.reds, "tsegs": segs.size(),
			"bpm_map": bpm_map, "bpm_det": bpm_det, "ratio": ratio, "exact": absf(ratio - 1.0) <= TOL,
			"alt4": false, "alt_any": false, "alt_rank": -1, "off": 0.0, "off_half": 0.0, "drift": 0.0,
			"db_ok": false, "db_shift": -1, "meter_map": int(M.meter), "meter_det": int(D.meter),
			"conf": float(grid.confidence), "nseg": grid.segments.size(), "M": M, "mid": mid,
			"multi_ok": false, "mseg_n": 0, "mseg_tempo": 0, "mb_n": 0, "mb_ok": 0}
	var alts: Array = grid.alternatives
	for i in alts.size():
		var f: float = alts[i].factor
		if absf(ratio * f - 1.0) <= TOL:
			rec.alt_any = true
			if rec.alt_rank < 0:
				rec.alt_rank = i
			for sa in SPEC_ALTS:
				if absf(f / float(sa) - 1.0) < 0.01:
					rec.alt4 = true
	if rec.exact:
		var ea := _err_at(grid, float(M.t) + minf(2.0, nb) * bl)
		var eb := _err_at(grid, float(M.t) + maxf(0.0, nb - 1.0) * bl)
		rec.off = _err_at(grid, mid)
		rec.off_half = rec.off + float(grid.get("debug", {}).get("half_delta", 0.0))
		rec.drift = absf(eb - ea)
		var bar: float = bl * int(M.meter)
		var dd := _wrap(float(D.downbeat_ms) - float(M.t), bar)
		rec.db_shift = posmod(int(round(dd / bl)), int(M.meter))
		rec.db_ok = int(D.meter) == int(M.meter) and absf(dd) <= bl * 0.25
	# Tempowechsel: Tempo-Segmente der Map (gleiche Tempi zusammengelegt, ab 2 s Laenge).
	var ts: Array = []
	for s in segs:
		if not ts.is_empty() and absf(float(s.bl) / float(ts[ts.size() - 1].bl) - 1.0) <= 0.0005:
			ts[ts.size() - 1].end = s.end
		else:
			ts.append({"t": s.t, "bl": s.bl, "end": s.end})
	var all_ok := true
	for i in ts.size():
		var s: Dictionary = ts[i]
		if float(s.end) - float(s.t) < 2000.0:
			continue
		rec.mseg_n += 1
		var m2: float = float(s.t) + floorf((float(s.end) - float(s.t)) / float(s.bl) * 0.5) * float(s.bl)
		var d2 := _seg_at(grid, m2)
		if absf(float(s.bl) / float(d2.beat_ms) - 1.0) <= TOL:
			rec.mseg_tempo += 1
		else:
			all_ok = false
		if i > 0:
			rec.mb_n += 1
			var hit := false
			for ds in grid.segments:
				if absf(float(ds.start_ms) - float(s.t)) <= float(s.bl):
					hit = true
			if hit:
				rec.mb_ok += 1
			else:
				all_ok = false
	rec.multi_ok = all_ok
	return rec


func _dump(f: FileAccess, rec: Dictionary, grid: Dictionary, _tr: Dictionary) -> void:
	var dbg: Dictionary = grid.get("debug", {})
	f.store_line("S\t%s\t%s\t%.3f\t%.3f\t%.4f\t%s\t%.2f\t%.2f\t%.2f\t%d\t%d\t%d\t%.2f\t%d\t%s\t%s" % [rec.name.left(40), rec.cat, rec.bpm_map, rec.bpm_det,
			rec.ratio, str(rec.exact), rec.off, rec.off_half, rec.drift, rec.db_shift, rec.meter_map, rec.meter_det, rec.conf, rec.nseg,
			str(dbg.get("snapped", false)), str(dbg.get("flipped", false))])
	for h in dbg.get("hyps", []):
		f.store_line("H\t%s\t%s\t%.3f\t%.4f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.4f" % [rec.name.left(40), rec.cat, h.bpm, float(h.bpm) / float(rec.bpm_map),
				h.r1, h.r2, h.r4, h.r3, h.rl1, h.rl2, h.fill, h.a1, h.a2, h.score])
	if rec.exact and dbg.has("ph4"):
		# Wahre Viertel-Phase des Schlags relativ zur gewaehlten Phase (0 = richtig, 2 = Halbe daneben).
		var Mq: Dictionary = rec.M
		var q := posmod(int(round((float(Mq.t) + float(G.DEFAULTS.lead_ms) - float(dbg.phase)) / (float(Mq.bl) / 4.0))), 4)
		var pl := "P\t%s\t%d" % [rec.name.left(40), q]
		for row in dbg.ph4:
			for v in row:
				pl += "\t%.4f" % v
		f.store_line(pl)
	var mt: Dictionary = dbg.get("meter", {})
	if rec.exact and mt.has("db4") and not mt.db4.is_empty():
		# Wahrer Taktanfang als Index relativ zum Schlag 0 der Analyse.
		var M: Dictionary = rec.M
		var lead: float = G.DEFAULTS.lead_ms
		var p_true := posmod(int(round((float(M.t) + lead - float(dbg.phase)) / float(M.bl))), int(M.meter))
		var line := "D\t%s\t%d\t%d\t%.2f\t%.2f" % [rec.name.left(40), int(M.meter), p_true, mt.get("s4", 0.0), mt.get("s3", 0.0)]
		for row in mt.db4:
			for v in row:
				line += "\t%.2f" % v
		f.store_line(line)
	f.flush()


func _report(recs: Array, skipped: Array, n_files: int) -> String:
	var single: Array = []
	var multi: Array = []
	var wild: Array = []
	for r in recs:
		match r.cat:
			"single": single.append(r)
			"multi": multi.append(r)
			_: wild.append(r)
	var ex := 0
	var ex_alt := 0
	var ex_top1 := 0
	var ex_any := 0
	var half := [0, 0, 0, 0]
	var offs: Array = []
	var offs_signed: Array = []
	var offs_half: Array = []
	var drifts: Array = []
	var drift_ok := 0
	var db_ok := 0
	var db_n := 0
	var db_shift := {}
	var m3_n := 0
	var m3_ok := 0
	var m_other := 0
	var over_seg := 0
	var conf_ok: Array = []
	var conf_bad: Array = []
	var wrong: Array = []
	for r in single:
		var h := int(r.idx) % 2
		half[h * 2 + 1] += 1
		if r.nseg > 1:
			over_seg += 1
		if r.exact:
			ex += 1
			half[h * 2] += 1
			conf_ok.append(r.conf)
			offs.append(absf(r.off))
			offs_signed.append(r.off)
			offs_half.append(r.off_half)
			drifts.append(r.drift)
			if r.drift <= 10.0:
				drift_ok += 1
			if r.meter_map == 3 or r.meter_map == 4:
				db_n += 1
				if r.db_ok:
					db_ok += 1
				elif r.meter_map == r.meter_det:
					db_shift[r.db_shift] = int(db_shift.get(r.db_shift, 0)) + 1
				if r.meter_map == 3:
					m3_n += 1
					if r.meter_det == 3:
						m3_ok += 1
			else:
				m_other += 1
		else:
			conf_bad.append(r.conf)
			wrong.append(r)
		if r.exact or r.alt4:
			ex_alt += 1
		if r.exact or r.alt_rank == 0:
			ex_top1 += 1
		if r.exact or r.alt_any:
			ex_any += 1
	var med_signed := _quant(offs_signed, 0.5)
	var med_half := _quant(offs_half, 0.5)
	var offs_c: Array = []
	var offs_hc: Array = []
	for v in offs_signed:
		offs_c.append(absf(v - med_signed))
	for v in offs_half:
		offs_hc.append(absf(v - med_half))
	var m_ok := 0
	var ms_n := 0
	var ms_t := 0
	var mb_n := 0
	var mb_ok := 0
	for r in multi:
		if r.multi_ok:
			m_ok += 1
		ms_n += r.mseg_n
		ms_t += r.mseg_tempo
		mb_n += r.mb_n
		mb_ok += r.mb_ok
	var w_ex := 0
	for r in wild:
		if r.exact:
			w_ex += 1
	var tms: Array = []
	var per_min: Array = []
	for r in recs:
		tms.append(r.ms)
		per_min.append(float(r.ms) / maxf(float(r.dur) / 60000.0, 0.1))
	var L: Array = []
	L.append("Gemessen mit `tests/run_am_grid_tests.gd -- --measure` in einem Prozess: %d Sets ausgewertet (von %d .osz, %d uebersprungen). Wahrheit: rote Timing-Points der Diff mit den meisten Objekten." % [recs.size(), n_files, skipped.size()])
	L.append("Sets mit einem Tempo: %d · mit Tempowechsel: %d · mit absichtlich wechselndem Timing (>= 30 rote Linien oder >= 10 Abschnitte, getrennt gewertet): %d." % [single.size(), multi.size(), wild.size()])
	L.append("")
	L.append("| Kennzahl (Spec, Zeile Takt) | Ziel | Ist |")
	L.append("|---|---|---|")
	L.append("| Tempo exakt (±0,5 %%) gegen die rote Linie, Sets mit einem Tempo | ≥ 95 %% | %s |" % _pct(ex, single.size()))
	L.append("| Tempo exakt oder gemeldete Alternative (x2, x0,5, x1,5, x0,667) trifft | ≥ 99 %% | %s |" % _pct(ex_alt, single.size()))
	L.append("| Offset-Fehler (Betrag, nur richtiges Tempo), Median / 95. Perzentil | ≤ 4 ms / ≤ 12 ms | %.1f ms / %.1f ms (n = %d) |" % [_quant(offs, 0.5), _quant(offs, 0.95), offs.size()])
	L.append("| Drift ueber den Song (letzter gegen ersten Schlag) | ≤ 10 ms | %s der Songs ≤ 10 ms; Median %.1f ms, 95. Perzentil %.1f ms, Maximum %.1f ms |" % [_pct(drift_ok, drifts.size()), _quant(drifts, 0.5), _quant(drifts, 0.95), _quant(drifts, 1.0)])
	L.append("| Tempowechsel: jede Segmentgrenze auf ±1 Schlag und Tempo je Segment exakt | ≥ 80 %% | %s |" % _pct(m_ok, multi.size()))
	L.append("| Taktanfang (Downbeat) stimmt mit der Map (richtiges Tempo, Map in 4/4 oder 3/4) | ≥ 85 %% | %s |" % _pct(db_ok, db_n))
	L.append("")
	L.append("Zusatzwerte:")
	L.append("")
	L.append("| Wert | Ist |")
	L.append("|---|---|")
	L.append("| Tempo exakt, Haelfte A (gerade Nummer) / Haelfte B (ungerade) | %s / %s |" % [_pct(half[0], half[1]), _pct(half[2], half[3])])
	L.append("| exakt oder die erste gemeldete Alternative trifft | %s |" % _pct(ex_top1, single.size()))
	L.append("| exakt oder irgendeine gemeldete Alternative trifft (auch x3, x0,333, x0,75, x1,333) | %s |" % _pct(ex_any, single.size()))
	L.append("| Offset-Fehler mit Vorzeichen (erkannt minus Map), Median | %.1f ms (0 = OSU_LEAD_MS stimmt) |" % med_signed)
	L.append("| Streuung um diesen Median, Median / 95. Perzentil (Phase am Maximum) | %.1f ms / %.1f ms |" % [_quant(offs_c, 0.5), _quant(offs_c, 0.95)])
	L.append("| dasselbe mit Phase am halben Anstieg: Median Vorzeichen, Streuung Median / 95. Perzentil | %.1f ms, %.1f ms / %.1f ms |" % [med_half, _quant(offs_hc, 0.5), _quant(offs_hc, 0.95)])
	L.append("| Sets mit einem Tempo, die faelschlich in mehrere Segmente geteilt wurden | %s |" % _pct(over_seg, single.size()))
	L.append("| Tempowechsel: Tempo je Map-Segment exakt / Grenze auf ±1 Schlag | %s / %s |" % [_pct(ms_t, ms_n), _pct(mb_ok, mb_n)])
	L.append("| 3/4-Maps (richtiges Tempo): Taktart 3 erkannt | %s |" % _pct(m3_ok, m3_n))
	L.append("| Maps mit anderer Taktart als 3 oder 4 (nicht in der Downbeat-Zeile) | %d |" % m_other)
	var sh := ""
	for k in db_shift:
		sh += "%d Schlaege daneben: %d · " % [k, db_shift[k]]
	L.append("| Falscher Taktanfang bei richtiger Taktart | %s |" % (sh if sh != "" else "keiner"))
	L.append("| Vertrauen im Mittel: richtiges Tempo / falsches Tempo | %.2f / %.2f |" % [_mean(conf_ok), _mean(conf_bad)])
	L.append("| Sets mit absichtlich wechselndem Timing: Tempo des laengsten Abschnitts exakt | %s |" % _pct(w_ex, wild.size()))
	L.append("| Rechenzeit track ohne Onset-Fluss, Median / Maximum je Song; je Minute Audio im Median | %d ms / %d ms; %d ms |" % [int(_quant(tms, 0.5)), int(_quant(tms, 1.0)), int(_quant(per_min, 0.5))])
	L.append("")
	L.append("### Sets mit einem Tempo und falschem Tempo (%d)" % wrong.size())
	L.append("")
	L.append("| Set | Map-BPM | erkannt | Verhaeltnis | Alternative trifft | Vertrauen |")
	L.append("|---|---|---|---|---|---|")
	for r in wrong:
		L.append("| %s | %.2f | %.2f | %s | %s | %.2f |" % [r.name.get_basename().left(48).replace("|", "/"), r.bpm_map, r.bpm_det, _ratio_name(r.ratio),
				("ja (Platz %d)" % (r.alt_rank + 1)) if r.alt_any else "nein", r.conf])
	L.append("")
	L.append("### Sets mit Tempowechsel (%d)" % multi.size())
	L.append("")
	L.append("| Set | rote Linien | Map-Segmente (ab 2 s) | Tempo exakt | Grenzen getroffen | erkannte Segmente | erfuellt |")
	L.append("|---|---|---|---|---|---|---|")
	for r in multi:
		L.append("| %s | %d | %d | %d | %d von %d | %d | %s |" % [r.name.get_basename().left(48).replace("|", "/"), r.reds, r.mseg_n, r.mseg_tempo, r.mb_ok, r.mb_n, r.nseg, "ja" if r.multi_ok else "nein"])
	L.append("")
	L.append("### Sets mit absichtlich wechselndem Timing (%d)" % wild.size())
	L.append("")
	L.append("| Set | rote Linien | Abschnitte | BPM laengster Abschnitt | erkannt | erkannte Segmente |")
	L.append("|---|---|---|---|---|---|")
	for r in wild:
		L.append("| %s | %d | %d | %.2f | %.2f | %d |" % [r.name.get_basename().left(48).replace("|", "/"), r.reds, r.tsegs, r.bpm_map, r.bpm_det, r.nseg])
	if not skipped.is_empty():
		L.append("")
		L.append("Uebersprungen: " + "; ".join(skipped).replace("|", "/"))
	return "\n".join(L)


func _mean(v: Array) -> float:
	var s := 0.0
	for x in v:
		s += float(x)
	return s / maxi(v.size(), 1)


func _write_out(path: String, md: String) -> void:
	var b := "<!-- MESSUNG:BEGIN -->"
	var e := "<!-- MESSUNG:END -->"
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var i := text.find(b)
	var j := text.find(e)
	if i >= 0 and j > i:
		text = text.substr(0, i + b.length()) + "\n" + md + "\n" + text.substr(j)
	else:
		text += ("\n" if text != "" else "") + b + "\n" + md + "\n" + e + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("Konnte %s nicht schreiben" % path)
		return
	f.store_string(text)
	f.close()
