extends SceneTree

## Headless-Tests fuer GameplayCore (Tipp-Modus: Aim + Timing-Fenster).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_gameplay_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Gameplay-Tests (Tipp-Modus) ===")
	_test_spawn_timing()
	_test_window_edges()
	_test_aim_miss()
	_test_early_notelock()
	_test_complete_miss()
	_test_slider_hold()
	_test_slider_drop()
	_test_slider_follow_circle()
	_test_stacking()
	_test_accuracy_formula()
	_test_score_multiplier()
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


## Testmap: OD5 (P +-50, G +-100, M +-150), CS4 (r=36.48), AR5 (preempt 1200).
func _make_core(hitobjects: String = "100,100,1000,1,0,0:0:0:0:\n300,200,2000,1,0,0:0:0:0:\n400,300,3000,1,0,0:0:0:0:\n") -> GameplayCore:
	var txt := "osu file format v14\n\n[General]\nMode: 0\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n" + hitobjects
	var res := OsuParser.parse(txt)
	assert(res.ok)
	var core := GameplayCore.new()
	core.setup(res.beatmap)
	return core


func _test_spawn_timing() -> void:
	print("- Spawn-Timing (preempt)")
	var core := _make_core()
	var spawned: Array[int] = []
	core.note_spawned.connect(func(i): spawned.append(i))
	_approx(core.preempt, 1200.0, "preempt(AR5)")
	core.update(-201.0)
	_ok(spawned.is_empty(), "vor time-preempt kein Spawn")
	core.update(-200.0)
	_ok(spawned == [0], "Spawn exakt bei time-preempt")
	core.update(810.0)
	_ok(spawned == [0, 1], "zweiter Spawn ab 800")


func _test_window_edges() -> void:
	print("- Timing-Window-Grenzen (OD5)")
	var core := _make_core()
	_approx(core.w_perfect, 50.0, "w_perfect")
	_approx(core.w_good, 100.0, "w_good")
	_approx(core.w_meh, 150.0, "w_meh")
	var r := core.handle_click(1050.0, Vector2(100, 100))
	_ok(r.quality == GameplayCore.Quality.PERFECT, "dt=+50 -> PERFECT")
	r = core.handle_click(1900.0, Vector2(300, 200))
	_ok(r.quality == GameplayCore.Quality.GOOD, "dt=-100 -> GOOD")
	_ok(bool(r.get("late", true)) == false, "dt<0 -> late=false (FAST)")
	r = core.handle_click(3150.0, Vector2(400, 300))
	_ok(r.quality == GameplayCore.Quality.MEH, "dt=+150 -> MEH")
	_ok(core.n300 == 1 and core.n100 == 1 and core.n50 == 1, "Zaehler 1/1/1")
	_ok(core.max_combo == 3, "Combo 3")


func _test_aim_miss() -> void:
	print("- Aim-Miss (Cursor daneben)")
	var core := _make_core()
	var r := core.handle_click(1000.0, Vector2(100.0 + 37.0, 100.0))
	_ok(r.quality == GameplayCore.Quality.MISS, "ausserhalb Radius -> MISS")
	_ok(r.miss_kind == "AIM", "miss_kind AIM")
	var core2 := _make_core()
	var r2 := core2.handle_click(1000.0, Vector2(100.0 + 36.4, 100.0))
	_ok(r2.quality == GameplayCore.Quality.PERFECT, "innerhalb Radius -> Hit")


func _test_early_notelock() -> void:
	print("- Notelock (zu frueh)")
	var core := _make_core()
	var r := core.handle_click(800.0, Vector2(100, 100))
	_ok(r.quality == GameplayCore.Quality.MISS, "zu frueh -> MISS")
	_ok(r.miss_kind == "EARLY", "miss_kind EARLY")
	_ok(core.n_miss == 1, "genau 1 Miss")
	var core2 := _make_core()
	var r2 := core2.handle_click(400.0, Vector2(100, 100))
	_ok(r2.is_empty(), "Klick < time-400ms ignoriert")


func _test_complete_miss() -> void:
	print("- Komplett-Miss (kein Klick)")
	var core := _make_core()
	core.update(1149.9)
	_ok(core.n_miss == 0, "bei dt=+149.9 noch kein Miss")
	core.update(1150.1)
	_ok(core.n_miss == 1, "Expiry -> genau 1 MISS")
	_ok(core.combo == 0, "Combo 0")


func _test_slider_hold() -> void:
	print("- Slider: halten bis zum Ende")
	var core := _make_core("100,100,1000,2,0,L|200:100,1,100,0:0|0:0,\n")
	var results: Array = []
	core.note_judged.connect(func(_i, res): results.append(res))
	var r := core.handle_click(1000.0, Vector2(100, 100))
	_ok(r.get("pending", false), "Head-Hit startet Pending-Slider")
	_ok(core.combo == 1, "Combo sofort +1")
	core.update(1400.0)  # Ende ~1357, Taste gehalten
	_ok(core.n300 == 1, "gehalten -> 300")
	_ok(results.size() == 1 and bool(results[0].get("held", false)), "held=true")


func _test_slider_drop() -> void:
	print("- Slider: loslassen -> DROP auf MEH")
	var core := _make_core("100,100,1000,2,0,L|200:100,1,100,0:0|0:0,\n")
	var results: Array = []
	core.note_judged.connect(func(_i, res): results.append(res))
	core.handle_click(1000.0, Vector2(100, 100))
	core.set_holding(false)
	core.update(1400.0)
	_ok(core.n50 == 1 and core.n300 == 0, "losgelassen -> MEH (50)")
	_ok(results.size() == 1 and not bool(results[0].get("held", true)), "held=false")


func _test_slider_follow_circle() -> void:
	print("- Slider: Follow-Circle (Cursor muss dem Ball folgen)")
	# Gefolgt: Cursor faehrt mit dem Ball mit -> Head-Qualitaet bleibt.
	var core := _make_core("100,100,1000,2,0,L|200:100,1,100,0:0|0:0,\n")
	core.handle_click(1000.0, Vector2(100, 100))
	var t := 1040.0
	while t <= 1400.0:
		var prog := clampf((t - 1000.0) / 357.14, 0.0, 1.0)
		core.update(t, Vector2(100.0 + 100.0 * prog, 100.0))
		t += 40.0
	_ok(core.n300 == 1, "gefolgt -> 300")
	# Nicht gefolgt: Taste gehalten, aber Cursor weit weg -> MEH ("DROP").
	var core2 := _make_core("100,100,1000,2,0,L|200:100,1,100,0:0|0:0,\n")
	core2.handle_click(1000.0, Vector2(100, 100))
	t = 1040.0
	while t <= 1400.0:
		core2.update(t, Vector2(450.0, 350.0))
		t += 40.0
	_ok(core2.n50 == 1 and core2.n300 == 0, "Follow verlassen -> MEH trotz Halten")


func _test_stacking() -> void:
	print("- Stack-Offsets (Doppelte erkennbar)")
	var core := _make_core("100,100,1000,1,0,0:0:0:0:\n100,100,1200,1,0,0:0:0:0:\n100,100,1400,1,0,0:0:0:0:\n")
	var o: Array = core.beatmap.hit_objects
	_ok(o[0].position() == Vector2(100, 100), "Basis-Note unversetzt")
	_ok(o[1].position() == Vector2(95, 95), "2. Note um -5 versetzt")
	_ok(o[2].position() == Vector2(90, 90), "3. Note um -10 versetzt")


func _test_accuracy_formula() -> void:
	print("- Accuracy-Formel (offiziell)")
	var core := _make_core()
	core.n300 = 9
	core.n100 = 2
	core.n50 = 1
	core.n_miss = 1
	_approx(core.accuracy(), 2950.0 / 3900.0, "acc 9/2/1/1", 0.000001)
	_ok(core.grade() == "C", "Grade C bei ~75.6%")


func _test_score_multiplier() -> void:
	print("- Arcade-Score-Multiplier (Combo-basiert)")
	var core := _make_core()
	_approx(core.score_multiplier(), 1.0, "x1 bei Combo 0")
	core.combo = 100
	_approx(core.score_multiplier(), 2.0, "x2 bei Combo 100")
	core.combo = 300
	_approx(core.score_multiplier(), 4.0, "x4 bei Combo 300")
	core.combo = 999
	_approx(core.score_multiplier(), 4.0, "Cap bei x4")
	core.combo = 0
	var before := core.score
	core.handle_click(1000.0, Vector2(100, 100))
	_ok(core.score - before == 300, "PERFECT ohne Combo = 300 Punkte")
