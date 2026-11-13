extends SceneTree

## Headless-Tests fuer Mania-Parser (Mode 3) und ManiaCore (4K).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_mania_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== OMEN Mania-Tests (4K) ===")
	_test_parser()
	_test_press_windows()
	_test_wrong_time_ignored()
	_test_expiry_miss()
	_test_hold_complete()
	_test_hold_drop()
	_test_hold_head_dt()
	_test_accuracy_weights()
	_test_hold_release_window()
	_test_chord_holds()
	_test_hp_start_and_break()
	_test_diag_log()
	_test_fail_reason()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _approx(actual: float, expected: float, label: String, eps: float = 0.001) -> void:
	_ok(absf(actual - expected) <= eps, "%s (erwartet %f, war %f)" % [label, expected, actual])


## 4K-Mania-Map, OD5: MAX +-16.5, 300 +-49.5, 200 +-82.5, 100 +-112.5,
## 50 +-136.5, Miss-Fenster 173.5 — volle osu!mania-Staffel (Stable, x.5).
func _make_core(hitobjects: String = "64,192,1000,1,0,0:0:0:0:\n192,192,1200,1,0,0:0:0:0:\n448,192,1400,128,0,1800:0:0:0:0:\n") -> ManiaCore:
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n" + hitobjects
	var res := OsuParser.parse(txt)
	assert(res.ok)
	var core := ManiaCore.new()
	core.setup(res.beatmap)
	return core


func _test_parser() -> void:
	print("- Parser: Mode 3, Spalten, Hold-Notes")
	var core := _make_core()
	var objs: Array = core.beatmap.hit_objects
	_ok(core.beatmap.is_mania(), "is_mania")
	_ok(core.columns == 4, "4 Spalten")
	_ok(objs.size() == 3, "3 Notes geparst")
	_ok((objs[0] as ManiaNote).column == 0, "x=64 -> Spalte 0")
	_ok((objs[1] as ManiaNote).column == 1, "x=192 -> Spalte 1")
	_ok((objs[2] as ManiaNote).column == 3, "x=448 -> Spalte 3")
	_ok((objs[2] as ManiaNote).is_hold, "type&128 -> Hold")
	_approx((objs[2] as ManiaNote).hold_end, 1800.0, "Hold-Ende 1800")
	_approx(core.w_max, 16.5, "Mania-MAX-Fenster (konstant)")
	_approx(core.w300, 49.5, "Mania-300er-Fenster OD5")
	_approx(core.w200, 82.5, "Mania-200er-Fenster OD5")
	_approx(core.w100, 112.5, "Mania-100er-Fenster OD5")
	_approx(core.w50, 136.5, "Mania-50er-Fenster OD5")


func _test_press_windows() -> void:
	print("- Timing-Fenster beim Druck")
	var core := _make_core()
	core.update(1000.0)
	core.key_down(0, 1010.0)
	_ok(core.n_max == 1, "dt=+10 -> MAX (Fenster 16.5)")
	core.key_down(1, 1200.0 + 120.0)
	_ok(core.n50 == 1, "dt=+120 -> MEH (ueber 100er-Grenze 112)")
	_ok(core.combo == 2, "Combo 2")


func _test_wrong_time_ignored() -> void:
	print("- Viel zu frueher Druck wird ignoriert")
	var core := _make_core()
	core.key_down(1, 1000.0)  # Note bei 1200, dt=-200 < -173
	_ok(core.n_miss == 0 and core.n300 == 0, "ignoriert (Leerdruck)")


func _test_expiry_miss() -> void:
	print("- Nicht gedrueckt -> Miss nach Fenster")
	var core := _make_core()
	core.update(1000.0 + 137.0)
	_ok(core.n_miss == 1, "Spalte 0 Miss (nach 136.5)")
	_ok(core.combo == 0, "Combo 0")


func _test_hold_complete() -> void:
	print("- Hold (osu!mania stable): Kopf + Ende ergeben EINE Wertung")
	var exact := _make_core()
	var results: Array = []
	exact.note_judged.connect(func(_i, r): results.append(r))
	exact.key_down(3, 1400.0)  # Kopf exakt
	exact.key_up(3, 1800.0)    # Ende exakt
	_ok(exact.n_max == 1, "Kopf + Ende exakt -> MAX")
	var hold_results := results.filter(func(r): return r.get("hold_end", false))
	_ok(hold_results.size() == 1 and bool(hold_results[0].held), "held=true")
	var past := _make_core("448,192,1400,128,0,1800:0:0:0:0:
")
	past.key_down(3, 1400.0)
	past.update(1800.0 + past.w100 + 1.0)  # ueber das spaete OK-Fenster gehalten
	_ok(past.n200 == 1 and past.n_miss == 0, "ueber das Ende gehalten -> wie Loslassen am OK-Rand (GOOD)")


func _test_hold_head_dt() -> void:
	print("- Hold-Kopf liefert Zeitfehler fuer die UR-Leiste")
	var core := _make_core()
	var got := [false, 0.0]
	core.hold_started.connect(func(i, _q):
		got[0] = true
		got[1] = core.hold_head_dt(i))
	core.key_down(3, 1412.0)
	_ok(bool(got[0]) and is_equal_approx(float(got[1]), 12.0), "hold_head_dt = +12 ms (war %s)" % str(got[1]))


func _test_hold_drop() -> void:
	print("- Hold im Koerper losgelassen: ohne erneuten Druck Miss, mit erneutem Druck hoechstens MEH")
	var core := _make_core("448,192,1400,128,0,1800:0:0:0:0:
")
	var results: Array = []
	core.note_judged.connect(func(_i, r): results.append(r))
	core.key_down(3, 1400.0)
	core.key_up(3, 1500.0)  # weit vor 1800
	_ok(core.n_miss == 0, "noch offen nach dem Loslassen")
	core.update(1800.0 + core.w100 + 1.0)
	_ok(core.n_miss == 1 and core.n50 == 0 and core.n_max == 0, "nicht wieder gedrueckt -> Miss (DROP)")
	_ok(core.combo == 0, "DROP bricht die Combo")
	var hold_results := results.filter(func(r): return r.get("hold_end", false))
	_ok(hold_results.size() == 1 and not bool(hold_results[0].held), "held=false")
	var again := _make_core()
	again.key_down(3, 1400.0)
	again.key_up(3, 1500.0)
	again.key_down(3, 1600.0)  # erneut gedrueckt
	again.key_up(3, 1800.0)    # Ende exakt
	_ok(again.n50 == 1 and again.n_max == 0 and again.n_miss == 0, "erneut gedrueckt -> MEH (hoechstens)")


func _test_accuracy_weights() -> void:
	print("- Accuracy: EXAKT die osu!mania-Formel (Stable)")
	var core := _make_core()
	_approx(core.accuracy(), 1.0, "ohne Judgements 100%")
	core.n_max = 1
	_approx(core.accuracy(), 1.0, "nur MAX -> 100%")
	core.n300 = 1
	_approx(core.accuracy(), 1.0, "MAX + 300 -> 100% (300er zaehlt voll)")
	core.n200 = 1
	_approx(core.accuracy(), 800.0 / 900.0, "+200er -> 88.9%")
	core.n100 = 1
	_approx(core.accuracy(), 900.0 / 1200.0, "+100er -> 75%")
	core.n50 = 1
	_approx(core.accuracy(), 950.0 / 1500.0, "+50er -> 63.3%")
	core.n_miss = 1
	_approx(core.accuracy(), 950.0 / 1800.0, "+Miss -> 52.8%")


func _test_hold_release_window() -> void:
	print("- Hold-Ende: Kopf-Fehler + End-Fehler (osu!mania stable)")
	var c := _make_core()
	_ok(c.hold_quality(0.0, 0.0) == ManiaCore.Quality.MAX, "0 + 0 -> MAX")
	_ok(c.hold_quality(c.w_max * 1.2, c.w_max * 1.2) == ManiaCore.Quality.MAX, "Kopf MAX x 1,2, Summe MAX x 2,4 -> MAX")
	_ok(c.hold_quality(c.w_max * 1.3, 0.0) == ManiaCore.Quality.PERFECT, "Kopf ueber MAX x 1,2 -> 300")
	_ok(c.hold_quality(0.0, c.w300 * 2.3) == ManiaCore.Quality.GOOD, "Summe ueber 300 x 2,2 -> 200")
	_ok(c.hold_quality(c.w100 + 1.0, 0.0) == ManiaCore.Quality.MEH, "Kopf ueber 100er -> MEH")
	var inside := _make_core()
	inside.key_down(3, 1400.0)
	inside.key_up(3, 1800.0 - 100.0)  # im fruehen MEH-Fenster des Endes (136,5)
	_ok(inside.n_miss == 0 and inside.n300 == 1, "100 ms vor Ende -> 300 (Summe 100 <= 300 x 2,2)")
	var late := _make_core()
	late.key_down(3, 1400.0)
	late.key_up(3, 1800.0 + 80.0)
	_ok(late.n_miss == 0 and late.n300 == 1, "80 ms nach dem Ende -> 300")
	var early := _make_core("448,192,1400,128,0,1800:0:0:0:0:
")
	early.key_down(3, 1400.0)
	early.key_up(3, 1800.0 - 210.0)  # vor dem fruehen MEH-Fenster: im Koerper
	early.update(1800.0 + early.w100 + 1.0)
	_ok(early.n_miss == 1 and early.n_max == 0, "210 ms vor Ende, nicht wieder gedrueckt -> Miss")


func _test_chord_holds() -> void:
	print("- Akkord-Holds: jede Spalte einzeln gewertet")
	var core := _make_core("64,192,1000,128,0,1600:0:0:0:0:
192,192,1000,128,0,1600:0:0:0:0:
")
	core.key_down(0, 1000.0)
	core.key_down(1, 1004.0)
	_ok(core.active_hold(0) >= 0 and core.active_hold(1) >= 0, "beide Holds aktiv")
	core.key_up(0, 1300.0)  # im Koerper -> Spalte 0 wartet auf erneuten Druck
	_ok(core.active_hold(0) < 0 and core.active_hold(1) >= 0, "Spalte 0 losgelassen, Spalte 1 laeuft weiter")
	core.key_up(1, 1600.0)  # Ende exakt, Kopf +4 ms
	_ok(core.n_max == 1, "Spalte 1 Kopf +4 / Ende 0 -> MAX")
	core.update(1600.0 + core.w100 + 1.0)
	_ok(core.n_miss == 1, "Spalte 0 ohne erneuten Druck -> Miss")


func _test_hp_start_and_break() -> void:
	print("- HP: Start voll, Break ohne Verlust")
	var core := _make_core("64,192,1000,1,0,0:0:0:0:
192,192,30000,1,0,0:0:0:0:
")
	_approx(core.hp, 1.0, "HP beim Start 1.0")
	core.key_down(0, 1000.0)
	var t := 1000.0
	while t < 29000.0:  # 28 s Pause ohne Noten
		t += 16.0
		core.update(t)
	_approx(core.hp, 1.0, "Break zieht keine HP ab")
	_ok(core.n_miss == 0 and not core.failed, "kein Miss im Break")


func _test_diag_log() -> void:
	print("- Diagnose-Log: Art je Wertung")
	var core := _make_core("64,192,1000,1,0,0:0:0:0:
192,192,1200,1,0,0:0:0:0:
448,192,1400,128,0,1800:0:0:0:0:
")
	core.key_down(0, 1000.0)       # MAX
	core.key_down(1, 1000.0)       # 200 ms zu frueh -> ignoriert (ausserhalb 173.5)
	core.key_down(1, 1050.0)       # 150 ms zu frueh -> frisst Note (EARLY)
	core.key_down(3, 1400.0)
	core.key_up(3, 1500.0)         # DROP
	core.update(3000.0)
	var kinds: Array = core.diag_log.map(func(e): return e.kind)
	_ok(kinds == ["MAX", "EARLY", "DROP"], "Arten MAX/EARLY/DROP (war %s)" % str(kinds))
	_ok(core.diag_log.size() <= ManiaCore.DIAG_LOG_MAX, "Log auf 30 begrenzt")
	core.note_frame(20.0, 100.0)
	core.note_frame(640.0, 2000.0)
	_ok(core.diag_spikes.size() == 1 and int(core.diag_spikes[0].ms) == 640, "nur Spitzen > 50 ms")
	_ok(core.diag_text("x", 3000.0).contains("DROP"), "Text enthaelt Wertungen")


func _entry(t: float, kind: String) -> Dictionary:
	return { "t": t, "col": 0, "kind": kind, "hp": 0.5 }


func _test_fail_reason() -> void:
	print("- Fail-Grund aus Wertungsliste")
	var burst: Array = []
	for i in 7:
		burst.append(_entry(10000.0 + i * 350.0, "FULL"))
	var r := ManiaCore.analyze_fail(burst, [], 12500.0)
	_ok(r.kind == "burst" and r.n == 7, "7 Misses am Stueck -> burst (war %s)" % str(r))
	_approx(float(r.secs), 2.1, "Spanne 2,1 s", 0.01)
	var stall := ManiaCore.analyze_fail(burst, [{ "t": 10900.0, "ms": 640.0 }], 12500.0)
	_ok(stall.kind == "stall" and int(stall.ms) == 640 and stall.n >= 1, "Ruckler 640 ms -> stall")
	var spike_only := ManiaCore.analyze_fail(burst, [{ "t": 2000.0, "ms": 640.0 }], 12500.0)
	_ok(spike_only.kind == "burst", "alter Ruckler ohne Misses -> kein stall")
	var drops: Array = [_entry(1000.0, "DROP"), _entry(2000.0, "DROP"), _entry(3000.0, "DROP"), _entry(4000.0, "FULL")]
	_ok(ManiaCore.analyze_fail(drops, [], 5000.0).kind == "drop", "3 Holds losgelassen -> drop")
	var early: Array = [_entry(1000.0, "EARLY"), _entry(1500.0, "EARLY"), _entry(2000.0, "EARLY"), _entry(2500.0, "EARLY")]
	var re := ManiaCore.analyze_fail(early, [], 3000.0)
	_ok(re.kind == "early" and re.n == 4, "4x zu frueh -> early")
	_ok(ManiaCore.analyze_fail([], [], 100.0).kind == "none", "leere Liste -> none")
	_ok(ManiaCore.fail_reason_text(r).contains("7"), "Text nennt die Anzahl")
