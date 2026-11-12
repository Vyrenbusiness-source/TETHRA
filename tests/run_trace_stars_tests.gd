extends SceneTree

## Trace-Sterne: leicht < schwer, deterministisch, Haarnadel teurer als gerade.
## Mit Argument "report" (nach --): misst die Bibliothek, schreibt docs/modes/trace_stars.md.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_stars_tests.gd [-- report]

const REPORT := "res://docs/modes/trace_stars.md"
var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Trace-Sterne ===")
	_test_synthetic()
	_test_cache()
	if "report" in OS.get_cmdline_user_args():
		_report()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


## cols je Note im Wechsel, Abstand gap ms, count Noten.
func _make(cols: Array, gap: float, count: int, hold := 0.0) -> float:
	var t := PackedFloat64Array()
	var c := PackedInt32Array()
	var e := PackedFloat64Array()
	for i in count:
		var tm := 1000.0 + gap * i
		t.append(tm)
		c.append(int(cols[i % cols.size()]))
		e.append(tm + hold)
	return TraceStars.from_notes(t, c, e)


func _test_synthetic() -> void:
	print("- Synthetisch")
	var easy := _make([0, 3], 600.0, 60)
	var hard := _make([0, 1, 3, 2, 0, 3], 130.0, 400)
	_ok(easy < hard, "leichte Map (%.2f) < schwere Map (%.2f)" % [easy, hard])
	_ok(_make([0, 3], 600.0, 60) == easy, "deterministisch")
	var straight := _make([0, 0], 200.0, 200)
	var hair := _make([0, 3], 200.0, 200)   # links/rechts = 180 Grad
	_ok(hair > straight, "Haarnadeln (%.2f) teurer als gerade (%.2f)" % [hair, straight])
	_ok(_make([0, 3], 200.0, 200) > _make([0, 3], 400.0, 100), "schneller teurer als langsam")
	_ok(TraceStars.from_notes(PackedFloat64Array(), PackedInt32Array(), PackedFloat64Array()) == 0.0, "leer = 0")
	_ok(easy > 0.0 and hard < 15.0, "Bereich plausibel")


func _test_cache() -> void:
	print("- Cache")
	_ok(StarService.trace_stars_for("user://does_not_exist.osz", "x.osu") < 0.0, "fehlende Datei = -1")
	_ok(StarService.trace_stars_cached("user://does_not_exist.osz", "x.osu") < 0.0, "kein Cache = -1")


func _report() -> void:
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		return
	var files := Array(da.get_files())
	files.sort()
	var rows: Array = []
	for f in files:
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		var mstars := StarService.stars_for(dir.path_join(f))
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if not bm.is_mania() or bm.column_count() != 4 or bm.hit_objects.size() < 30:
				continue
			var p := TracePath.from_beatmap(bm)
			rows.append({"label": "%s [%s]" % [str(f).get_basename().left(28), bm.version_name().left(24)],
				"stars": TraceStars.from_path(p), "mania": float(mstars.get(d.osu_filename, {}).get("stars", -1.0)),
				"n": bm.hit_objects.size(), "hp": p.hairpin_count(), "knots": p.knots.size()})
	rows.sort_custom(func(a, b): return a.stars < b.stars)
	if rows.is_empty():
		return
	var s: Array = rows.map(func(r): return r.stars)
	var out := "# Trace-Sterne: Kalibrierung\n\nErzeugt von `tests/run_trace_stars_tests.gd report`. Bibliothek: %d Mania-4K-Diffs.\n" % rows.size()
	out += "Formel: `scripts/trace/trace_stars.gd` (Tempo, Richtungswechsel, Haarnadeln, Akkord-Diagonalen/Kreuze, Hold-Ueberlappung, Lesestress, Stamina).\n\n"
	out += "## Verteilung\n\n- Median %.2f, 10 %%: %.2f, 90 %%: %.2f, Max %.2f\n" % [_q(s, 0.5), _q(s, 0.1), _q(s, 0.9), s[-1]]
	var bins := [0.0, 1.5, 2.5, 3.5, 4.5, 5.5, 7.0, 99.0]
	out += "\n| Trace-Sterne | Maps | Mania-Sterne Mittel |\n|---|---|---|\n"
	for i in bins.size() - 1:
		var c := 0
		var m := 0.0
		for r in rows:
			if r.stars >= bins[i] and r.stars < bins[i + 1]:
				c += 1
				m += maxf(r.mania, 0.0)
		out += "| %.1f - %.1f | %d | %.2f |\n" % [bins[i], minf(bins[i + 1], 15.0), c, m / maxf(c, 1)]
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	for r in rows:
		if r.mania >= 0.0:
			xs.append(r.stars)
			ys.append(r.mania)
	out += "\nKorrelation Trace/Mania-Sterne: %.2f\n" % _corr(xs, ys)
	out += "\n## Je Map (nach Sternen)\n\n| Map | Trace | Mania | Noten | Knoten | Haarnadeln |\n|---|---|---|---|---|---|\n"
	for r in rows:
		out += "| %s | %.2f | %.2f | %d | %d | %d |\n" % [r.label, r.stars, r.mania, r.n, r.knots, r.hp]
	var fh := FileAccess.open(REPORT, FileAccess.WRITE)
	if fh:
		fh.store_string(out)
		fh.close()
	print("  Median %.2f, 10%% %.2f, 90%% %.2f, Maps %d" % [_q(s, 0.5), _q(s, 0.1), _q(s, 0.9), rows.size()])


func _q(a: Array, f: float) -> float:
	return a[clampi(int(f * (a.size() - 1)), 0, a.size() - 1)]


func _corr(x: PackedFloat64Array, y: PackedFloat64Array) -> float:
	var n := x.size()
	if n < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += x[i]
		my += y[i]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		sxy += (x[i] - mx) * (y[i] - my)
		sxx += (x[i] - mx) * (x[i] - mx)
		syy += (y[i] - my) * (y[i] - my)
	return sxy / maxf(sqrt(sxx * syy), 0.000001)
