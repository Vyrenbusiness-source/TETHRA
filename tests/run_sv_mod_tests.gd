extends SceneTree

## Headless-Tests fuer den SV-Mod (SvMod + Einbau in ManiaCore).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_sv_mod_tests.gd
## SV_REPORT=<ordner>: schreibt generierte .osu-Dateien (Kennzahlen-Vergleich).

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA SV-Mod-Tests ===")
	var bm := _synthetic()
	_test_determinism(bm)
	_test_bounds(bm)
	_test_spacing(bm)
	_test_normalized(bm)
	_test_fair(bm, "synthetisch")
	_test_is_sv(bm)
	_test_own_sv()
	_test_bpm_change()
	_test_core_wiring(bm)
	_test_score()
	_test_real_maps()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


## 4K, 150 BPM, 64 Takte: Kiai 16-32 und 48-60, Break 33-40, Stream 24-28,
## Akkorde auf Downbeats, Holds alle 8 Takte.
func _osu_text(red_lines: String, bars: int = 64, bl: float = 400.0, extra_green: String = "") -> String:
	var ho := PackedStringArray()
	var xs := [64, 192, 320, 448]
	for bar in bars:
		if bar >= 33 and bar < 40:
			continue
		for beat in 4:
			var t0 := 1000.0 + (bar * 4 + beat) * bl
			var sub := 4 if bar >= 24 and bar < 28 else 2
			for s in sub:
				var t := int(round(t0 + s * bl / sub))
				var c := (bar * 7 + beat * 3 + s) % 4
				if bar % 8 == 5 and beat == 0 and s == 0:
					ho.append("%d,192,%d,128,0,%d:0:0:0:0:" % [xs[c], t, int(t + bl * 2)])
					continue
				ho.append("%d,192,%d,1,0,0:0:0:0:" % [xs[c], t])
				if beat == 0 and s == 0:
					ho.append("%d,192,%d,1,0,0:0:0:0:" % [xs[(c + 2) % 4], t])
	return "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 8\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n" \
		+ red_lines + extra_green + "\n[HitObjects]\n" + "\n".join(ho) + "\n"


func _parse(txt: String) -> Beatmap:
	var res := OsuParser.parse(txt)
	assert(res.ok)
	return res.beatmap


func _synthetic() -> Beatmap:
	var kiai := "%d,-100,4,1,0,100,0,1\n%d,-100,4,1,0,100,0,0\n%d,-100,4,1,0,100,0,1\n%d,-100,4,1,0,100,0,0\n" % [
		1000 + 16 * 1600, 1000 + 33 * 1600, 1000 + 48 * 1600, 1000 + 60 * 1600]
	return _parse(_osu_text("1000,400,4,1,0,100,1,0\n", 64, 400.0, kiai))


func _greens(tps: Array) -> Array:
	var out := []
	for tp in tps:
		if not tp.uninherited:
			out.append(tp)
	return out


func _sm(bm: Beatmap, tps: Array) -> ScrollMap:
	var last := -INF
	for o in bm.hit_objects:
		last = maxf(last, o.end_time())
	var sm := ScrollMap.new()
	sm.build(tps, last)
	return sm


func _test_determinism(bm: Beatmap) -> void:
	print("- Deterministik")
	var bm2 := _synthetic()
	var s1 := SvMod.map_seed(bm)
	_ok(s1 == SvMod.map_seed(bm2), "gleiche Map -> gleicher Seed")
	var a := SvMod.generate(bm, s1)
	var b := SvMod.generate(bm2, SvMod.map_seed(bm2))
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if a[i].time != b[i].time or a[i].beat_length != b[i].beat_length \
					or a[i].uninherited != b[i].uninherited:
				same = false
				break
	_ok(same, "gleicher Seed -> identische Linien (%d)" % a.size())
	_ok(_greens(a).size() > 100, "viele gruene Linien (%d)" % _greens(a).size())
	var c := SvMod.generate(bm, s1 + 1)
	var diff := c.size() != a.size()
	if not diff:
		for i in a.size():
			if a[i].beat_length != c[i].beat_length:
				diff = true
				break
	_ok(diff, "anderer Seed -> andere Linien")
	var shifted := _parse(_osu_text("1000,400,4,1,0,100,1,0\n", 63))
	_ok(SvMod.map_seed(shifted) != s1, "andere Map -> anderer Seed")


func _test_bounds(bm: Beatmap) -> void:
	print("- Grenzen")
	var tps := SvMod.timing_points_for(bm)
	var sm := _sm(bm, tps)
	var lo := INF
	var hi := -INF
	for m in sm._mult:
		lo = minf(lo, m)
		hi = maxf(hi, m)
	_ok(lo >= SvMod.M_MIN - 1e-6, "min Multiplikator >= 0.1 (%.3f), nie rueckwaerts" % lo)
	_ok(hi <= SvMod.M_MAX + 1e-6, "max Multiplikator <= 10 (%.3f)" % hi)
	var in_range := true
	for g in _greens(tps):
		var sv: float = -100.0 / g.beat_length
		if sv < ScrollMap.SV_MIN or sv > ScrollMap.SV_MAX:
			in_range = false
	_ok(in_range, "gruene SV innerhalb ScrollMap-Grenzen")
	var reds_kept := 0
	for tp in tps:
		if tp.uninherited:
			reds_kept += 1
	_ok(reds_kept == 1, "rote Linien unveraendert")


func _test_spacing(bm: Beatmap) -> void:
	print("- Keine Wechsel zu dicht")
	var sm := _sm(bm, SvMod.timing_points_for(bm))
	var min_gap := INF
	for i in range(1, sm._times.size()):
		min_gap = minf(min_gap, sm._times[i] - sm._times[i - 1])
	_ok(min_gap >= SvMod.MIN_SEG_MS - 1e-6, "kleinster Abstand %.2f ms >= %.0f ms" % [min_gap, SvMod.MIN_SEG_MS])


func _test_normalized(bm: Beatmap) -> void:
	print("- Normierung (mittlere Scroll-Geschwindigkeit 1.0)")
	var sm := _sm(bm, SvMod.timing_points_for(bm))
	var t0 := bm.hit_objects[0].time
	# Blockgrenze (Kiai-Ende, kein Drop): dort muss die Position exakt stimmen.
	var t1 := 1000.0 + 60 * 1600.0
	var drift_end := absf((sm.position(t1) - sm.position(t0)) - (t1 - t0))
	_ok(drift_end < 1.0, "Abweichung am Ende %.4f ms < 1 ms" % drift_end)
	var worst := 0.0
	for o in bm.hit_objects:
		worst = maxf(worst, absf((sm.position(o.time) - sm.position(t0)) - (o.time - t0)))
	_ok(worst <= 400.0, "Drift jeder Note <= 1 Beat (%.1f ms)" % worst)
	# Takt-Mittel ueber 4 Beats
	var bar_lo := INF
	var bar_hi := -INF
	var t := t0
	while t + 1600.0 <= t1:
		var m := (sm.position(t + 1600.0) - sm.position(t)) / 1600.0
		bar_lo = minf(bar_lo, m)
		bar_hi = maxf(bar_hi, m)
		t += 1600.0
	_ok(bar_lo >= 0.7 and bar_hi <= 1.3, "Takt-Mittel %.3f..%.3f im Bereich 0.7..1.3" % [bar_lo, bar_hi])


## Spielbar: keine Note unsichtbar oder ueberlagert.
func _test_fair(bm: Beatmap, label: String, tps: Array = []) -> void:
	if tps.is_empty():
		tps = SvMod.timing_points_for(bm)
	var sm := _sm(bm, tps)
	var bad := 0
	for pr in SvMod._column_pairs(bm):
		var dt: float = pr[1] - pr[0]
		var need := minf(dt, maxf(SvMod.GAP_RATIO * dt, SvMod.GAP_ABS_MS)) - 0.01
		if sm.position(pr[1]) - sm.position(pr[0]) < need:
			bad += 1
	_ok(bad == 0, "%s: keine ueberlagerten Noten (%d Verstoesse)" % [label, bad])
	var short := 0
	for preempt in [600.0, 1200.0, 2400.0]:
		for o in bm.hit_objects:
			if o.time - sm.spawn_time(o.time, preempt) < 0.4 * preempt:
				if short == 0:
					var k := sm._seg_by_time(o.time)
					var seg := []
					for q in range(maxi(k - 12, 0), mini(k + 2, sm._times.size())):
						seg.append("%.0f:%.2f" % [sm._times[q], sm._mult[q]])
					print("    kurz: t=%.0f preempt=%.0f sichtbar=%.0f  %s" % [o.time, preempt,
						o.time - sm.spawn_time(o.time, preempt), " ".join(seg)])
				short += 1
	_ok(short == 0, "%s: jede Note >= 40%% der Anflugzeit sichtbar (%d zu kurz)" % [label, short])


func _test_is_sv(bm: Beatmap) -> void:
	print("- Ergebnis ist eine SV-Map, Kiai lebendiger, Break ruhig")
	var tps := SvMod.timing_points_for(bm)
	var t0 := bm.hit_objects[0].time
	var t1 := bm.hit_objects[bm.hit_objects.size() - 1].end_time()
	_ok(bool(MapLibrary.sv_stats_tp(tps, t0, t1).sv), "SV-Erkennung der Bibliothek schlaegt an")
	var kiai_n := 0
	var calm_n := 0
	var brk_n := 0
	for g in _greens(tps):
		if bm.is_kiai(g.time):
			kiai_n += 1
		elif g.time > 1000 + 34 * 1600 and g.time < 1000 + 39 * 1600:
			brk_n += 1
		else:
			calm_n += 1
	# Kiai: 28 Takte, Rest ohne Break: 29 Takte.
	_ok(kiai_n > calm_n, "Kiai mehr Linien (%d) als ruhige Teile (%d)" % [kiai_n, calm_n])
	_ok(brk_n == 0, "Break ohne SV-Wechsel (%d)" % brk_n)
	var sm := _sm(bm, tps)
	var drop := 1000.0 + 16 * 1600
	var slow := (sm.position(drop - 100.0) - sm.position(drop - 400.0)) / 300.0
	_ok(slow < 0.2, "Freeze vor dem Drop (m %.2f)" % slow)


func _test_own_sv() -> void:
	print("- Map mit eigenem SV")
	var g := PackedStringArray()
	for i in 200:
		g.append("%d,%d,4,1,0,100,0,0" % [1000 + i * 200, -50 if i % 2 == 0 else -200])
	var bm := _parse(_osu_text("1000,400,4,1,0,100,1,0\n", 32, 400.0, "\n".join(g) + "\n"))
	_ok(SvMod.has_own_sv(bm), "eigenes SV erkannt")
	var tps := SvMod.timing_points_for(bm)
	_ok(tps == bm.timing_points, "eigenes SV bleibt unveraendert (nicht doppelt)")
	var plain := _synthetic()
	_ok(not SvMod.has_own_sv(plain), "Map ohne SV: Mod greift")


func _test_bpm_change() -> void:
	print("- BPM-Wechsel normalisiert (SV = ModeBPM / BPM)")
	# 40 Takte 400 ms, danach 24 Takte 300 ms.
	var t_change := 1000 + 40 * 1600
	var bm := _parse(_osu_text("1000,400,4,1,0,100,1,0\n%d,300,4,1,0,100,1,0\n" % t_change, 64))
	var tps := SvMod.timing_points_for(bm)
	var sm := _sm(bm, tps)
	var t1 := bm.hit_objects[bm.hit_objects.size() - 1].time
	var m2 := (sm.position(t1) - sm.position(t_change)) / (t1 - t_change)
	_ok(absf(m2 - 1.0) < 0.35, "zweiter Abschnitt im Mittel ~1.0 (%.3f)" % m2)
	var raw := _sm(bm, bm.timing_points)
	var r2: float = raw.position(t1 + 1.0) - raw.position(t1)
	_ok(absf(r2 - 400.0 / 300.0) < 0.01, "ohne Mod schneller (%.3f)" % r2)
	_test_fair(bm, "BPM-Wechsel", tps)


func _test_core_wiring(bm: Beatmap) -> void:
	print("- Einbau in ManiaCore.build_scroll_map")
	var plain := ManiaCore.build_scroll_map(bm, {})
	_ok(plain.is_identity(), "ohne Mod: identisch wie vorher")
	var sv := ManiaCore.build_scroll_map(bm, {"SV": true})
	_ok(not sv.is_identity(), "mit SV: Tempowechsel")
	var gs = root.get_node_or_null("GameSession")
	_ok(gs != null, "Autoload GameSession vorhanden")
	if gs == null:
		return
	gs.mods = {"SV": true, "NF": false}
	var from_session := ManiaCore.build_scroll_map(bm)
	_ok(from_session._mult == sv._mult, "liest GameSession.mods[\"SV\"]")
	var core := ManiaCore.new()
	core.setup(bm)
	_ok(core.scroll._mult == sv._mult, "ManiaCore.setup nutzt SV-Tabelle")
	gs.mods = {}


## Perfektes Spiel: Score mit Mods (SV x1.10, NF x0.5, kombiniert).
func _play_perfect(mods: Dictionary) -> Dictionary:
	var gs = root.get_node("GameSession")
	gs.mods = mods
	var bm := _parse(_osu_text("1000,400,4,1,0,100,1,0\n", 8))
	var core := ManiaCore.new()
	core.setup(bm)
	gs.mods = {}
	var objs := bm.hit_objects
	var ev: Array = []  # [zeit, 0=down/1=up, spalte]
	for o in objs:
		ev.append([o.time, 0, (o as ManiaNote).column])
		ev.append([maxf(o.end_time(), o.time + 1.0), 1, (o as ManiaNote).column])
	ev.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	for e in ev:
		core.update(e[0])
		if e[1] == 0:
			core.key_down(e[2], e[0])
		else:
			core.key_up(e[2], e[0])
	core.update(objs[objs.size() - 1].end_time() + 1000.0)
	return {"score": core.score, "no_fail": core.no_fail, "stats": core.stats()}


func _test_score() -> void:
	print("- Score-Multiplikator")
	var none := _play_perfect({})
	var sv := _play_perfect({"SV": true})
	var nf := _play_perfect({"NF": true})
	var both := _play_perfect({"SV": true, "NF": true})
	var base := float(none.score)
	_ok(base > 900000.0, "Referenz ohne Mod (%d)" % int(none.score))
	_ok(absf(float(sv.score) - base * 1.1) <= 1.0, "SV x1.10 (%d)" % int(sv.score))
	_ok(absf(float(nf.score) - base * 0.5) <= 1.0, "NF x0.5 (%d)" % int(nf.score))
	_ok(absf(float(both.score) - base * 0.55) <= 1.0, "SV+NF kombiniert x0.55 (%d)" % int(both.score))
	_ok(bool(nf.no_fail) and not bool(sv.no_fail), "NF setzt no_fail")
	_ok(sv.stats.mods == ["SV"] and both.stats.mods == ["SV", "NF"], "stats.mods markiert den Mod")
	_ok(absf(ManiaCore.mod_multiplier({"SV": true}) - 1.1) < 1e-9, "ManiaCore.mod_multiplier")


## Echte Maps aus maps/: Fairness + Deterministik auf realen Patterns.
func _test_real_maps() -> void:
	print("- Echte Maps")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var files := Array(da.get_files())
	files.sort()
	var report := OS.get_environment("SV_REPORT")
	var want := 12 if report != "" else 4
	var done := 0
	for f in files:
		if done >= want or not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if done >= want or not bm.is_mania() or bm.hit_objects.size() < 200 or SvMod.has_own_sv(bm):
				continue
			var tps := SvMod.generate(bm, SvMod.map_seed(bm))
			var again := SvMod.generate(bm, SvMod.map_seed(bm))
			_ok(tps.size() == again.size(), "%s [%s]: deterministisch" % [str(f).left(30), bm.version_name()])
			_test_fair(bm, "%s [%s]" % [str(f).left(30), bm.version_name()], tps)
			if report != "":
				_dump(report, "%02d_%s" % [done, str(f).get_basename().left(30)], bm, tps)
			done += 1


func _dump(out_dir: String, name: String, bm: Beatmap, tps: Array) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join(name.validate_filename() + ".osu"), FileAccess.WRITE)
	f.store_string("osu file format v14\n\n[General]\nMode: 3\n\n[TimingPoints]\n")
	for tp in tps:
		var k := 1 if bm.is_kiai(tp.time + 0.5) else 0
		f.store_string("%.3f,%.6f,%d,1,0,100,%d,%d\n" % [tp.time, tp.beat_length, tp.meter, 1 if tp.uninherited else 0, k])
	f.store_string("\n[HitObjects]\n")
	for o in bm.hit_objects:
		var col: int = (o as ManiaNote).column
		if o.end_time() > o.time:
			f.store_string("%d,192,%d,128,0,%d:0:0:0:0:\n" % [64 + col * 128, int(o.time), int(o.end_time())])
		else:
			f.store_string("%d,192,%d,1,0,0:0:0:0:\n" % [64 + col * 128, int(o.time)])
	f.close()
