extends SceneTree

## Headless-Tests fuer die Regel-Mods (Task mv-rules): Sudden Death, Perfect, Minen.
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_mv_rules_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== OMEN Regel-Mods-Tests (SD/PF/MN) ===")
	_test_normalize()
	_test_browser_toggle()
	_test_sd_fail_on_miss()
	_test_sd_survives_hits()
	_test_pf_fail_on_200()
	_test_pf_ok_on_max_300()
	_test_pf_hold_end()
	_test_rule_with_nf_tutorial()
	_test_mod_mult_and_badges()
	_test_fail_reason_text()
	_test_gen_deterministic()
	_test_gen_rules()
	_test_gen_density()
	_test_gen_seed_independent_of_file()
	_test_mine_dodged()
	_test_mine_press()
	_test_mine_hold_through()
	_test_mine_window_edges()
	_test_mine_core_effects()
	_test_mine_sd()
	_test_mine_autoplay_clean()
	_test_mine_replay_same()
	_test_finish_waits_for_mines()
	_test_score_mode_and_pp()
	_test_body_fields()
	_test_trace_mods_badges()
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


# --- Hilfen ------------------------------------------------------------------

## 4K-Map: notes = [[zeit, spalte, ende(-1 = Tap)], ...].
func _map(notes: Array, od: float = 8.0) -> Beatmap:
	var xs := [64, 192, 320, 448]
	var ho := PackedStringArray()
	for n in notes:
		var t := int(n[0])
		var c := int(n[1])
		var e := int(n[2]) if n.size() > 2 else -1
		if e > t:
			ho.append("%d,192,%d,128,0,%d:0:0:0:0:" % [xs[c], t, e])
		else:
			ho.append("%d,192,%d,1,0,0:0:0:0:" % [xs[c], t])
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: %s\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,300,4,2,0,60,1,0\n\n[HitObjects]\n%s\n" % [str(od), "\n".join(ho)]
	var res := OsuParser.parse(txt)
	return res.beatmap


## Dichter Stream: alle 75 ms eine Note (13 nps), Spalten 0,1,0,1,... und ab und zu 2.
func _dense_map(n_notes: int = 400) -> Beatmap:
	var notes: Array = []
	for i in n_notes:
		var c := i % 2
		if i % 7 == 3:
			c = 2
		notes.append([1000 + i * 75, c])
	return _map(notes)


func _core(bm: Beatmap, mods: Dictionary) -> ManiaCore:
	var core := ManiaCore.new()
	core.setup(bm)
	core.mods = mods.duplicate()
	core.no_fail = bool(mods.get("NF", false))
	RuleMods.setup_core(core)
	return core


func _press(core: ManiaCore, c: int, t: float, hold_ms: float = 40.0) -> void:
	core.update(t)
	core.key_down(c, t)
	core.update(t + hold_ms)
	core.key_up(c, t + hold_ms)


## Autoplay wie mania_3d._run_autoplay (Taste zur Notenzeit, Tap 40 ms, Hold bis Ende).
func _autoplay(core: ManiaCore, bm: Beatmap, step: float = 4.0) -> Array:
	var events: Array = []
	var rel: Array[float] = [-1.0, -1.0, -1.0, -1.0]
	var idx := 0
	var objs := bm.hit_objects
	var t := 0.0
	var t_end := objs[objs.size() - 1].end_time() + 1000.0
	while t <= t_end:
		for c in 4:
			if rel[c] >= 0.0 and rel[c] <= t:
				core.key_up(c, rel[c])
				events.append({"t": rel[c], "lane": c, "down": false})
				rel[c] = -1.0
		while idx < objs.size() and objs[idx].time <= t:
			var n := objs[idx] as ManiaNote
			idx += 1
			if rel[n.column] >= 0.0:
				var r := minf(rel[n.column], n.time)
				core.key_up(n.column, r)
				events.append({"t": r, "lane": n.column, "down": false})
			core.key_down(n.column, n.time)
			events.append({"t": n.time, "lane": n.column, "down": true})
			rel[n.column] = n.end_time() if n.is_hold else n.time + 40.0
		core.update(t)
		t += step
	return events


# --- SD / PF -----------------------------------------------------------------

func _test_normalize() -> void:
	var m := RuleMods.normalize({"SD": true, "NF": true, "SV": true})
	_ok(not m.has("NF") and bool(m.SD) and bool(m.SV), "SD schaltet NF aus, SV bleibt")
	m = RuleMods.normalize({"SD": true, "PF": true})
	_ok(bool(m.get("PF", false)) and not m.has("SD"), "PF schlaegt SD (gegenseitig)")
	m = RuleMods.normalize({"MN": true})
	_ok(int(m.get("MN_v", 0)) == MineGen.VERSION, "MN bekommt Versions-Marke MN_v")
	m = RuleMods.normalize({"MN": true, "MN_v": 1})
	_ok(int(m.MN_v) == 1, "vorhandene MN_v bleibt (altes Replay)")


func _test_browser_toggle() -> void:
	var sel := RuleMods.toggle({}, "SD", true)
	sel = RuleMods.toggle(sel, "PF", true)
	_ok(bool(sel.PF) and not bool(sel.SD), "Browser: PF an -> SD aus")
	_ok(RuleMods.clears_nf("SD") and RuleMods.clears_nf("PF") and not RuleMods.clears_nf("MN"),
		"SD/PF schalten NF aus, MN nicht")
	var nf := RuleMods.on_no_fail({"SD": true, "MN": true})
	_ok(not bool(nf.SD) and bool(nf.MN), "NF an -> SD/PF aus, MN bleibt")
	var mods := RuleMods.apply({"NF": true}, {"SD": true, "MN": true}, "mania")
	_ok(bool(mods.SD) and bool(mods.MN) and not mods.has("NF"), "apply Mania: SD + MN, NF weg")
	mods = RuleMods.apply({"NF": false}, {"SD": true, "MN": true}, "trace")
	_ok(bool(mods.SD) and not mods.has("MN"), "apply Trace: SD ja, MN nein")
	mods = RuleMods.apply({}, {"PF": true}, "rebound")
	_ok(bool(mods.PF), "apply Rebound: PF ja")
	mods = RuleMods.apply({}, {"SD": true}, "orbit")
	_ok(not mods.has("SD"), "apply Orbit: kein SD")


func _test_sd_fail_on_miss() -> void:
	var bm := _map([[1000, 0], [1500, 1], [2000, 2]])
	var core := _core(bm, {"SD": true})
	_press(core, 0, 1000.0)
	_ok(not core.failed, "SD: Treffer -> kein Fail")
	core.update(2000.0)   # Note 1500 abgelaufen -> Miss
	_ok(core.failed and core.fail_rule == "SD" and core.fail_what == "Miss", "SD: erster Miss -> Fail (SD, Miss)")
	_ok(core.hp > 0.5, "SD-Fail kommt nicht von der HP")


func _test_sd_survives_hits() -> void:
	var bm := _map([[1000, 0], [1500, 1], [2000, 2]])
	var core := _core(bm, {"SD": true})
	core.key_down(0, 1000.0 + core.w100 - 1.0)   # 100er
	core.key_up(0, 1100.0)
	_ok(not core.failed, "SD: 100er ist kein Abbruch")


func _test_pf_fail_on_200() -> void:
	var bm := _map([[1000, 0], [1500, 1]])
	var core := _core(bm, {"PF": true})
	var dt := (core.w300 + core.w200) * 0.5
	core.key_down(0, 1000.0 + dt)
	_ok(core.failed and core.fail_rule == "PF" and core.fail_what == "200", "PF: 200 -> Fail (PF, 200)")


func _test_pf_ok_on_max_300() -> void:
	var bm := _map([[1000, 0], [1500, 1], [2000, 2]])
	var core := _core(bm, {"PF": true})
	core.key_down(0, 1000.0)
	core.key_up(0, 1040.0)
	core.key_down(1, 1500.0 + (core.w_max + core.w300) * 0.5)
	core.key_up(1, 1560.0)
	_ok(core.n_max == 1 and core.n300 == 1 and not core.failed, "PF: MAX und 300 sind ok")
	core.update(2400.0)
	_ok(core.failed and core.fail_what == "Miss", "PF: Miss -> Fail")


func _test_pf_hold_end() -> void:
	var bm := _map([[1000, 0, 2000]])
	var core := _core(bm, {"PF": true})
	core.key_down(0, 1000.0)
	core.key_up(0, 1500.0)   # mitten im Koerper los, kein erneuter Druck -> Miss am Ende
	core.update(2400.0)
	_ok(core.failed and core.fail_rule == "PF", "PF: losgelassener Hold -> Fail")
	var core2 := _core(bm, {"SD": true})
	core2.key_down(0, 1000.0)
	core2.key_up(0, 2000.0)
	core2.update(2400.0)
	_ok(not core2.failed and core2.n_max == 1, "SD: sauber gehaltener Hold -> kein Fail")


func _test_rule_with_nf_tutorial() -> void:
	var bm := _map([[1000, 0], [1500, 1]])
	var core := _core(bm, {"SD": true, "NF": true})
	_ok(not core.no_fail and not core.mods.has("NF"), "SD + NF: NF faellt weg")
	core.no_fail = true   # Tutorial setzt no_fail nach setup
	core.update(3000.0)
	_ok(not core.failed, "no_fail (Tutorial) schlaegt SD")


func _test_mod_mult_and_badges() -> void:
	_ok(is_equal_approx(ManiaCore.mod_multiplier({"SD": true, "PF": true, "MN": true}), 1.0),
		"SD/PF/MN: Score-Faktor 1,0")
	var l := ManiaCore.mod_list({"SV": true, "SD": true, "MN": true})
	_ok(l == ["SV", "SD", "MN"], "Badge-Liste SV SD MN: %s" % str(l))
	var core := _core(_map([[1000, 0]]), {"PF": true})
	_ok((core.stats().mods as Array) == ["PF"], "stats.mods traegt PF")


func _test_fail_reason_text() -> void:
	var bm := _map([[1000, 0], [1500, 1]])
	var core := _core(bm, {"SD": true})
	core.update(2000.0)
	_ok(RuleMods.fail_reason(core) == "Sudden Death: Miss", "Fail-Grund: '%s'" % RuleMods.fail_reason(core))
	var c2 := _core(bm, {})
	c2.update(3000.0)
	_ok(RuleMods.fail_reason(c2) == "", "ohne Regel kein Regel-Grund")


# --- Minen-Konverter ---------------------------------------------------------

func _test_gen_deterministic() -> void:
	var bm := _dense_map()
	var a := MineGen.generate(bm, 4)
	var b := MineGen.generate(_dense_map(), 4)
	_ok(a.size() > 0 and a == b, "Konverter deterministisch (%d Minen)" % a.size())


func _test_gen_rules() -> void:
	var bm := _dense_map()
	var mines := MineGen.generate(bm, 4)
	_ok(MineGen.violation(bm, 4, mines) == "", "Regeln 150 ms vor/nach eigener Note: %s" % MineGen.violation(bm, 4, mines))
	# Mit Holds: nie in einem Hold.
	var notes: Array = []
	for i in 300:
		notes.append([1000 + i * 70, i % 3])
	notes.append([2000, 3, 9000])
	var bm2 := _map(notes)
	var m2 := MineGen.generate(bm2, 4)
	var in_hold := false
	for m in m2:
		if int(m[1]) == 3 and float(m[0]) >= 1850.0 and float(m[0]) <= 9150.0:
			in_hold = true
	_ok(not in_hold and MineGen.violation(bm2, 4, m2) == "", "keine Mine im/am Hold (%d Minen)" % m2.size())
	# Mine liegt auf einer Zeile mit Noten, in einer Spalte ohne Note.
	var on_row := true
	for m in mines:
		var found := false
		for o in bm.hit_objects:
			if absf(o.time - float(m[0])) < 0.5:
				found = true
				if (o as ManiaNote).column == int(m[1]):
					on_row = false
		if not found:
			on_row = false
	_ok(on_row, "Minen liegen auf Notenzeilen in freien Spalten")


func _test_gen_density() -> void:
	# Ruhig (2 nps): keine Minen.
	var calm: Array = []
	for i in 200:
		calm.append([1000 + i * 500, i % 4])
	_ok(MineGen.generate(_map(calm), 4).is_empty(), "ruhige Map: keine Minen")
	# Dichter = mehr Minen je Zeile.
	var mid: Array = []
	var fast: Array = []
	for i in 400:
		mid.append([1000 + i * 110, i % 2])     # ~9 nps
		fast.append([1000 + i * 60, i % 2])     # ~17 nps
	var n_mid := MineGen.generate(_map(mid), 4).size()
	var n_fast := MineGen.generate(_map(fast), 4).size()
	_ok(n_mid > 0 and float(n_fast) / 400.0 > float(n_mid) / 400.0,
		"dichter -> mehr Minen je Note (%d vs %d auf 400)" % [n_mid, n_fast])


func _test_gen_seed_independent_of_file() -> void:
	var a := MineGen.seed_for(_dense_map(), 4)
	var b := MineGen.seed_for(_dense_map(), 4)
	var c := MineGen.seed_for(_dense_map(399), 4)
	_ok(a == b and a != c and a >= 0, "Seed aus Noten-Hash (gleich je Map, anders je Map)")


# --- Minen im Spiel ----------------------------------------------------------

func _mine_core(mine_t: float = 2000.0, col: int = 3) -> ManiaCore:
	var bm := _map([[1000, 0], [mine_t, 0], [3000, 1]])
	var core := _core(bm, {})
	var mm := ManiaMines.new()
	mm.setup([[mine_t, col]], 4)
	core.mines = mm
	return core


func _test_mine_dodged() -> void:
	var core := _mine_core()
	core.update(2500.0)
	_ok(core.mines.done() and core.mines.n_hit() == 0 and core.n_mine_hit == 0, "Mine ohne Druck: sicher vorbei")


func _test_mine_press() -> void:
	var core := _mine_core()
	var hits := []
	core.mine_hit.connect(func(i, c): hits.append([i, c]))
	core.update(1990.0)
	core.key_down(3, 1995.0)
	_ok(hits == [[0, 3]] and core.n_mine_hit == 1, "Druck beim Durchlauf -> Mine loest aus")
	core.key_up(3, 2050.0)
	_ok(core.n_mine_hit == 1, "eine Mine loest nur einmal aus")


func _test_mine_hold_through() -> void:
	var core := _mine_core()
	core.key_down(3, 1500.0)
	core.update(1900.0)
	_ok(core.n_mine_hit == 0, "Halten vor der Mine: noch nichts")
	core.update(1975.0)
	_ok(core.n_mine_hit == 1, "gehalten, Mine erreicht die Linie -> Treffer")
	# Druck und Loslassen zwischen zwei Frames ueber die Mine hinweg.
	var c2 := _mine_core()
	c2.update(1900.0)
	c2.key_down(3, 1950.0)
	c2.key_up(3, 2100.0)
	c2.update(2200.0)
	_ok(c2.n_mine_hit == 1, "gehalten zwischen zwei Frames -> Treffer")


func _test_mine_window_edges() -> void:
	var w := ManiaMines.WINDOW_MS
	var a := _mine_core()
	a.key_down(3, 2000.0 + w + 1.0)
	_ok(a.n_mine_hit == 0, "Druck nach dem Fenster: kein Treffer")
	var b := _mine_core()
	b.key_down(3, 1900.0)
	b.key_up(3, 2000.0 - w - 1.0)
	b.update(2100.0)
	_ok(b.n_mine_hit == 0, "vor dem Fenster losgelassen: kein Treffer")
	var c := _mine_core()
	c.key_down(3, 2000.0 - w)
	_ok(c.n_mine_hit == 1, "Druck am Fensterrand: Treffer")
	var d := _mine_core()
	d.key_down(2, 2000.0)
	d.update(2100.0)
	_ok(d.n_mine_hit == 0, "andere Spalte: kein Treffer")


func _test_mine_core_effects() -> void:
	var core := _mine_core()
	_press(core, 0, 1000.0)
	var combo_before := core.combo
	var hp_before := core.hp
	var acc_before := core.accuracy()
	core.key_down(3, 2000.0)
	_ok(combo_before == 1 and core.combo == 0, "Mine: Kombo bricht")
	_ok(core.hp < hp_before, "Mine: HP sinkt")
	_ok(is_equal_approx(core.accuracy(), acc_before) and core.n_miss == 0, "Mine: Acc und Miss-Zaehler unveraendert")
	var s := core.stats()
	_ok(int(s.get("mine_hits", -1)) == 1 and int(s.get("mines", -1)) == 1, "stats: mines/mine_hits")


func _test_mine_sd() -> void:
	var core := _mine_core()
	core.mods = {"SD": true}
	core.key_down(3, 2000.0)
	_ok(core.failed and core.fail_rule == "SD" and core.fail_what == "Mine", "SD + Mine -> Fail 'Mine'")
	_ok(RuleMods.fail_reason(core) == "Sudden Death: Mine", "Fail-Grund '%s'" % RuleMods.fail_reason(core))


func _test_mine_autoplay_clean() -> void:
	var bm := _dense_map()
	var core := _core(bm, {"MN": true})
	_ok(core.mines != null and core.mines.count() > 0, "MN in setup_core baut Minen (%d)" % (core.mines.count() if core.mines != null else 0))
	_autoplay(core, bm)
	_ok(core.mines.done() and core.n_mine_hit == 0 and core.n_miss == 0,
		"Autoplay trifft keine Mine (hits=%d miss=%d)" % [core.n_mine_hit, core.n_miss])


func _test_mine_replay_same() -> void:
	var bm := _dense_map()
	var core := _core(bm, {"MN": true})
	# Spieler drueckt zusaetzlich in jede Minen-Spalte zur Minen-Zeit (jede 3. Mine).
	var extra: Array = []
	for i in core.mines.count():
		if i % 3 == 0:
			extra.append({"t": core.mines.times[i] - 5.0, "lane": core.mines.cols[i], "down": true})
			extra.append({"t": core.mines.times[i] + 25.0, "lane": core.mines.cols[i], "down": false})
	var evs := _autoplay(core, bm)
	evs.append_array(extra)
	evs.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var runs: Array = []
	for r in 2:
		var c := _core(bm, {"MN": true, "MN_v": 1})
		var t := 0.0
		var k := 0
		while t < 40000.0:
			while k < evs.size() and float(evs[k].t) <= t:
				if bool(evs[k].down):
					c.key_down(int(evs[k].lane), float(evs[k].t))
				else:
					c.key_up(int(evs[k].lane), float(evs[k].t))
				k += 1
			c.update(t)
			t += 16.0 if r == 0 else 7.0   # andere Bildrate, gleiche Wertung
		runs.append([c.n_mine_hit, c.score, c.max_combo, c.accuracy()])
	_ok(runs[0] == runs[1] and int(runs[0][0]) > 0, "Replay gleich bei anderer Bildrate: %s" % str(runs[0]))


func _test_finish_waits_for_mines() -> void:
	var bm := _map([[1000, 0]])
	var core := _core(bm, {})
	var mm := ManiaMines.new()
	mm.setup([[1000.0, 2]], 4)
	core.mines = mm
	var done := [false]
	core.finished.connect(func(_s): done[0] = true)
	core.key_down(0, 1000.0)
	core.key_up(0, 1010.0)
	core.update(1010.0)
	_ok(not done[0], "Ende wartet auf offene Mine")
	core.update(1100.0)
	_ok(done[0], "Ende nach entschiedener Mine")


# --- Wertung / Server --------------------------------------------------------

func _test_score_mode_and_pp() -> void:
	_ok(RuleMods.score_mode({"MN": true}) == "mania_mn" and RuleMods.score_mode({"SD": true}) == "",
		"Score-Modus: MN eigene Liste, SD normal")
	_ok(RuleMods.no_pp({"MN": true}) and not RuleMods.no_pp({"SD": true, "PF": true}), "pp: MN keine, SD/PF normal")


func _test_body_fields() -> void:
	var res := {"score": 1000, "mods": ["MN"], "mines": 12, "mine_hits": 2, "pp": 55.0}
	var body := OnlineApi.build_body(res, {"md5": "x"}, "mania")
	_ok(float(body.pp) == 0.0 and str(body.get("board", "")) == "mania_mn" and int(body.mines) == 12
		and int(body.mine_hits) == 2 and (body.mods as Array).has("MN") and not bool(body.ranked),
		"POST /score mit MN: pp 0, board, Zaehler, ranked false")
	var b2 := OnlineApi.build_body({"score": 1, "mods": ["SD"], "pp": 12.0}, {"md5": "x"}, "mania")
	_ok(float(b2.pp) == 12.0 and not b2.has("board") and bool(b2.ranked), "POST /score mit SD: pp normal, ranked, kein board")
	var rm := RuleMods.replay_mods({"MN": true}, {"MN": true, "MN_v": 1})
	_ok(int(rm.get("MN_v", 0)) == 1 and RuleMods.replay_mods({"SD": true}, {"SD": true}) == {"SD": true},
		"Replay-Mods: MN_v aus dem Lauf, sonst unveraendert")


func _test_trace_mods_badges() -> void:
	var l := TraceMods.mod_list({"MR": true, "SD": true})
	_ok(l.has("SD"), "Trace-Badges zeigen SD: %s" % str(l))
	_ok(TraceMods.strip_foreign({"PF": true, "SV": true}).has("PF"), "Trace behaelt PF")


## Echte 4K-Maps aus maps/ (falls vorhanden): Regeln, Anteil, Autoplay trifft keine Mine.
## MV_REPORT=1: mehr Maps und eine Zeile je Map.
func _test_real_maps() -> void:
	print("- Echte Maps")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("  (kein maps/-Ordner, uebersprungen)")
		return
	var files := Array(da.get_files())
	files.sort()
	var want := 16 if OS.get_environment("MV_REPORT") != "" else 4
	var done := 0
	var max_ratio := 0.0
	for f in files:
		if done >= want or not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if done >= want or not bm.is_mania() or bm.column_count() != 4 or bm.hit_objects.size() < 200:
				continue
			var mines := MineGen.generate(bm, 4)
			var v := MineGen.violation(bm, 4, mines)
			var core := _core(bm, {"MN": true})
			_autoplay(core, bm, 8.0)
			var ratio := float(mines.size()) / float(bm.hit_objects.size())
			max_ratio = maxf(max_ratio, ratio)
			_ok(v == "" and core.n_mine_hit == 0, "%s [%s]: %d Noten, %d Minen (%.1f %%, erste %s ms), Autoplay-Treffer %d %s" % [
				str(f).left(28), bm.version_name().left(20), bm.hit_objects.size(), mines.size(),
				ratio * 100.0, str(mines.slice(0, 1).map(func(m): return int(m[0]))), core.n_mine_hit, v])
			done += 1
	_ok(done == 0 or max_ratio < 0.25, "Minen-Anteil hoechstens 25 %% der Noten (max %.1f %%)" % (max_ratio * 100.0))
