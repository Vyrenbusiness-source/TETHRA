extends SceneTree

## Headless-Tests fuer SnapColor.
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_snap_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _tp(time: float, bl: float, red: bool = true) -> TimingPoint:
	var p := TimingPoint.new()
	p.time = time
	p.beat_length = bl
	p.uninherited = red
	return p


func _initialize() -> void:
	print("=== SnapColor-Tests ===")
	_test_120bpm()
	_test_bpm_change()
	_test_offset()
	_test_tolerance()
	_test_colors()
	_test_precompute()
	print("=== Ergebnis: %d fehlgeschlagen ===" % _failed)
	quit(1 if _failed > 0 else 0)


func _test_120bpm() -> void:
	var tps := [_tp(0.0, 500.0)]
	_check(SnapColor.divisor_for(0.0, tps) == 1, "Beat = 1/1")
	_check(SnapColor.divisor_for(1000.0, tps) == 1, "Beat 2 = 1/1")
	_check(SnapColor.divisor_for(250.0, tps) == 2, "Achtel = 1/2")
	_check(SnapColor.divisor_for(125.0, tps) == 4, "16tel = 1/4")
	_check(SnapColor.divisor_for(375.0, tps) == 4, "16tel (3/4) = 1/4")
	_check(SnapColor.divisor_for(500.0 / 3.0, tps) == 3, "Triole = 1/3")
	_check(SnapColor.divisor_for(500.0 * 2.0 / 3.0, tps) == 3, "Triole 2 = 1/3")
	_check(SnapColor.divisor_for(500.0 / 6.0, tps) == 6, "Sextole = 1/6")
	_check(SnapColor.divisor_for(500.0 / 8.0, tps) == 8, "1/8 Beat = 1/8")
	_check(SnapColor.divisor_for(500.0 / 12.0, tps) == 12, "1/12 Beat = 1/12")
	_check(SnapColor.divisor_for(500.0 / 16.0, tps) == 16, "1/16 Beat = 1/16")


func _test_bpm_change() -> void:
	var tps := [_tp(0.0, 500.0), _tp(4000.0, 300.0), _tp(4100.0, -50.0, false)]
	_check(SnapColor.divisor_for(4150.0, tps) == 2, "nach BPM-Wechsel Achtel (150ms)")
	_check(SnapColor.divisor_for(4000.0 + 100.0, tps) == 3, "nach Wechsel Triole (100ms)")
	_check(SnapColor.divisor_for(3750.0, tps) == 2, "vor Wechsel alte Linie")
	_check(SnapColor.divisor_for(4300.0, tps) == 1, "nach Wechsel Beat")


func _test_offset() -> void:
	var tps := [_tp(137.0, 500.0)]
	_check(SnapColor.divisor_for(137.0, tps) == 1, "Offset: Linie selbst = 1/1")
	_check(SnapColor.divisor_for(387.0, tps) == 2, "Offset: Achtel")
	_check(SnapColor.divisor_for(137.0 - 250.0, tps) == 2, "vor erster Linie: Achtel rueckwaerts")
	_check(SnapColor.divisor_for(250.0, tps) == 16, "Offset: ungesnappte Note = 16")


func _test_tolerance() -> void:
	var tps := [_tp(0.0, 500.0)]
	_check(SnapColor.divisor_for(251.5, tps) == 2, "1.5 ms daneben noch gesnappt")
	_check(SnapColor.divisor_for(998.6, tps) == 1, "Rundung 1.4 ms vor Beat")
	_check(SnapColor.divisor_for(256.0, tps) != 2, "6 ms daneben nicht 1/2")
	var fast := [_tp(0.0, 120.0)] ## 1/24 Beat = 5 ms, TOL 2 ms
	_check(SnapColor.divisor_for(60.0, fast) == 2, "schnell: Achtel")


func _test_colors() -> void:
	var theme := Color(0.2, 0.8, 0.9)
	var seen := {}
	for d in SnapColor.DIVISORS:
		var c := SnapColor.color_for(d, theme)
		seen[c.to_html()] = true
	_check(seen.size() == SnapColor.DIVISORS.size(), "8 Teiler = 8 verschiedene Farben")
	var c1 := SnapColor.color_for(1, theme)
	_check(c1.r > c1.b, "1/1 warm")
	var c2 := SnapColor.color_for(2, theme)
	_check(c2.b > c2.r, "1/2 blau")
	_check(SnapColor.color_for(99, theme) == SnapColor.color_for(16, theme), "unbekannt = 1/16")
	var lo := 1.0
	var hi := 0.0
	for d in SnapColor.DIVISORS:
		var v := SnapColor.color_for(d, theme).get_luminance()
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_check(hi - lo < 0.3, "Helligkeit aehnlich")


func _test_precompute() -> void:
	var bm := Beatmap.new()
	bm.timing_points = [_tp(0.0, 500.0)]
	for t in [0.0, 250.0, 500.0 / 3.0, 125.0]:
		var o := HitObject.new()
		o.time = t
		bm.hit_objects.append(o)
	var r := SnapColor.precompute(bm)
	_check(r.size() == 4, "precompute Groesse")
	_check(r.size() == 4 and r[0] == 1 and r[1] == 2 and r[2] == 3 and r[3] == 4, "precompute Werte")
