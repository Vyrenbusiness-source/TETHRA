extends SceneTree

## Headless-Tests fuer IntensityMap.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_intensity_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


## Map mit 500-ms-Beats (4/4). spans: [von_ms, bis_ms, Abstand_ms].
func _map(spans: Array, kiai: Array = []) -> Beatmap:
	var bm := Beatmap.new()
	var tp := TimingPoint.new()
	tp.time = 0.0
	tp.beat_length = 500.0
	tp.meter = 4
	tp.uninherited = true
	bm.timing_points.append(tp)
	for s in spans:
		var t: float = s[0]
		while t < s[1]:
			var h := HitObject.new()
			h.time = t
			bm.hit_objects.append(h)
			t += s[2]
	for k in kiai:
		bm.kiai_intervals.append({"start": k[0], "end": k[1]})
	return bm


func _initialize() -> void:
	print("=== IntensityMap-Tests ===")
	_test_ramp()
	_test_break_drop()
	_test_kiai()
	_test_empty()
	print("=== Ergebnis: %d fehlgeschlagen ===" % _failed)
	quit(1 if _failed > 0 else 0)


func _test_ramp() -> void:
	var m := IntensityMap.new()
	m.build(_map([[0, 20000, 500], [20000, 40000, 125]]))
	_check(m.value_at(30000) > m.value_at(10000) + 0.3, "dicht > ruhig")
	_check(m.value_at(30000) > 0.8, "dicht nahe 1")
	_check(m.value_at(-5) >= 0.0 and m.value_at(1e9) <= 1.0, "Werte in 0..1")
	_check(m.section_index(5000) == 0, "Abschnitt 0 am Anfang")
	_check(m.section_index(39000) == 0, "noch Abschnitt 0 (32 Takte = 64 s)")


func _test_break_drop() -> void:
	var m := IntensityMap.new()
	m.build(_map([[0, 10000, 125], [20000, 30000, 125]]))
	_check(m.value_at(15000) < 0.1, "Break ist leise")
	_check(m.value_at(5000) > 0.5, "vor Break laut")
	_check(m.drops().size() == 1 and absf(m.drops()[0] - 20000.0) < 1.0, "Drop am Break-Ende")
	_check(not m.is_drop_at(5000.0), "kein Drop am Anfang")
	_check(m.is_drop_at(20000.0) and m.is_drop_at(23900.0), "Drop in ersten 2 Takten")
	_check(not m.is_drop_at(24100.0), "Drop endet nach 2 Takten")
	_check(m.section_index(25000) == m.section_index(20000) and m.section_index(19000) < m.section_index(20000), "Abschnitt wechselt am Break-Ende")


func _test_kiai() -> void:
	var m := IntensityMap.new()
	m.build(_map([[0, 40000, 500]], [[20000, 30000]]))
	_check(m.value_at(25000) > m.value_at(10000), "Kiai hebt Intensitaet")
	_check(m.drops().size() == 1 and absf(m.drops()[0] - 20000.0) < 1.0, "Drop am Kiai-Start")
	_check(m.section_index(19999) + 1 == m.section_index(20000), "Abschnitt wechselt am Kiai-Start")
	var l := IntensityMap.new()
	l.build(_map([[0, 140000, 500]]))
	_check(l.section_index(63000) == 0 and l.section_index(65000) == 1 and l.section_index(129000) == 2, "alle 32 Takte neuer Abschnitt")


func _test_empty() -> void:
	var m := IntensityMap.new()
	m.build(Beatmap.new())
	_check(m.value_at(1000) == 0.0 and not m.is_drop_at(1000) and m.section_index(1000) == 0 and m.drops().is_empty(), "leere Map")
	m.build(null)
	_check(m.drops().is_empty(), "null-Map")
