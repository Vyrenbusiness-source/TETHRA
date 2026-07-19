extends SceneTree

## Headless-Tests fuer Mania-Parser (Mode 3) und ManiaCore (4K).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_mania_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Mania-Tests (4K) ===")
	_test_parser()
	_test_press_windows()
	_test_wrong_time_ignored()
	_test_expiry_miss()
	_test_hold_complete()
	_test_hold_drop()
	_test_accuracy_weights()
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
	print("- Hold bis zum Ende -> Head-Qualitaet")
	var core := _make_core()
	var results: Array = []
	core.note_judged.connect(func(_i, r): results.append(r))
	core.key_down(3, 1400.0)  # Head exakt -> MAX, halten
	core.update(1850.0)       # Ende 1800 erreicht, Taste unten
	_ok(core.n_max == 1, "gehalten -> MAX")
	var hold_results := results.filter(func(r): return r.get("hold_end", false))
	_ok(hold_results.size() == 1 and bool(hold_results[0].held), "held=true")


func _test_hold_drop() -> void:
	print("- Hold frueh loslassen -> DROP auf MEH")
	var core := _make_core()
	var results: Array = []
	core.note_judged.connect(func(_i, r): results.append(r))
	core.key_down(3, 1400.0)
	core.key_up(3, 1500.0)  # weit vor 1800
	_ok(core.n50 == 1 and core.n_max == 0, "losgelassen -> MEH (DROP)")
	_ok(core.combo == 0, "DROP bricht die Combo (Stable-Verhalten)")
	var hold_results := results.filter(func(r): return r.get("hold_end", false))
	_ok(hold_results.size() == 1 and not bool(hold_results[0].held), "held=false")


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
