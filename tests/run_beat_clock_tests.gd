extends SceneTree

## Headless-Tests fuer BeatClock.
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_beat_clock_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _tp(time: float, bl: float, meter: int = 4, red: bool = true, kiai: bool = false) -> TimingPoint:
	var p := TimingPoint.new()
	p.time = time
	p.beat_length = bl
	p.meter = meter
	p.uninherited = red
	p.kiai = kiai
	return p


func _initialize() -> void:
	print("=== BeatClock-Tests ===")
	_test_phase()
	_test_bpm_change()
	_test_meter3()
	_test_edges()
	_test_seek_back()
	_test_kiai()
	print("=== Ergebnis: %d fehlgeschlagen ===" % _failed)
	quit(1 if _failed > 0 else 0)


func _test_phase() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0)])
	c.update(250.0, 0.016)
	_check(absf(c.beat_phase - 0.5) < 1e-6, "120 BPM: Phase 0.5 bei 250ms")
	_check(absf(c.bpm - 120.0) < 1e-6, "bpm = 120")
	c.update(1250.0, 0.016)
	_check(c.beat_index == 2 and absf(c.beat_phase - 0.5) < 1e-6, "Beat 2 bei 1250ms")
	_check(absf(c.bar_phase - 0.625) < 1e-6, "bar_phase 0.625")
	c.update(2000.0, 0.016)
	_check(absf(c.beat_env - 1.0) < 1e-6, "Downbeat-Env 1.0")
	c.update(2500.0, 0.016)
	_check(absf(c.beat_env - 0.55) < 1e-6, "Off-Beat-Env 0.55")


func _test_bpm_change() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0), _tp(2000.0, 250.0)])
	c.update(2125.0, 0.016)
	_check(absf(c.bpm - 240.0) < 1e-6, "BPM-Wechsel: 240")
	_check(absf(c.beat_phase - 0.5) < 1e-6, "Phase nach Wechsel 0.5")
	_check(c.beat_index == 0, "Beat-Index relativ zum neuen Abschnitt")


func _test_meter3() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0, 3)])
	c.update(1750.0, 0.016)
	_check(absf(c.bar_phase - ((0.0 + 0.5) / 3.0)) < 1e-6, "3/4: Beat 3 (idx 3 -> Takt-Beat 0) Phase 0.5")
	c.update(1250.0, 0.016)
	_check(absf(c.bar_phase - (2.5 / 3.0)) < 1e-6, "3/4: bar_phase 2.5/3")
	var d := BeatClock.new()
	d.setup([_tp(0.0, 500.0, 3)])
	d.update(1400.0, 0.016)
	d.update(1500.0, 0.016)
	_check(d.is_downbeat_edge, "3/4: Downbeat bei Beat 3")


func _test_edges() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0)])
	var beats := 0
	var downs := 0
	var t := -10.0
	while t < 3990.0:
		c.update(t, 0.016)
		if c.is_beat_edge:
			beats += 1
		if c.is_downbeat_edge:
			downs += 1
		t += 16.0
	_check(beats == 8, "8 Schlagkanten (0..3500) (%d)" % beats)
	_check(downs == 2, "2 Downbeats (%d)" % downs)
	c.update(10000.0, 0.016)
	_check(c.is_beat_edge, "Grosser Sprung: eine Kante")
	c.update(10001.0, 0.016)
	_check(not c.is_beat_edge, "Danach keine Kante")


func _test_seek_back() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0), _tp(2000.0, 250.0)])
	c.update(3000.0, 0.016)
	c.update(100.0, 0.016)
	_check(not c.is_beat_edge, "Seek zurueck: keine Kante")
	_check(absf(c.bpm - 120.0) < 1e-6 and absf(c.beat_phase - 0.2) < 1e-6, "Seek zurueck: Abschnitt 1, Phase 0.2")
	c.update(520.0, 0.016)
	_check(c.is_beat_edge, "Nach Seek wieder Kanten")


func _test_kiai() -> void:
	var c := BeatClock.new()
	c.setup([_tp(0.0, 500.0), _tp(1000.0, -100.0, 4, false, true), _tp(2000.0, -100.0, 4, false, false)])
	c.update(500.0, 0.016)
	_check(not c.kiai and c.kiai_mix == 0.0, "Kiai aus")
	for i in 60:
		c.update(1500.0, 0.016)
	_check(c.kiai and c.kiai_mix > 0.9, "Kiai an, mix steigt")
	c.update(2500.0, 0.016)
	_check(not c.kiai and c.kiai_mix < 1.0, "Kiai aus, mix faellt")
