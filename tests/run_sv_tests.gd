extends SceneTree

## Headless-Tests fuer ScrollMap (osu!mania Scroll Velocity wie lazer).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_sv_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA SV-Tests ===")
	_test_constant_linear()
	_test_sv_double()
	_test_bpm_change()
	_test_stop()
	_test_monotonic()
	_test_hold_end()
	_test_base_beat_length()
	_test_inverse_spawn()
	_test_tie_green_wins()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps


func _red(t: float, bl: float) -> TimingPoint:
	var tp := TimingPoint.new()
	tp.time = t
	tp.beat_length = bl
	tp.uninherited = true
	return tp


func _green(t: float, sv: float) -> TimingPoint:
	var tp := TimingPoint.new()
	tp.time = t
	tp.beat_length = -100.0 / sv
	tp.uninherited = false
	return tp


func _map(tps: Array, end_ms: float) -> ScrollMap:
	var m := ScrollMap.new()
	m.build(tps, end_ms)
	return m


func _test_constant_linear() -> void:
	var m := _map([_red(500.0, 400.0)], 60000.0)
	_ok(m.is_identity(), "Konstante Map: Identitaet")
	var exact := true
	for t in [-1234.5, 0.0, 333.3, 500.0, 12345.678, 59999.9]:
		if m.position(t) != t:
			exact = false
	_ok(exact, "Konstante Map: position(t) == t bitgenau")
	_ok(m.spawn_time(2000.0, 1000.0) == 1000.0, "Konstante Map: spawn = hit - preempt")
	var empty := _map([], 1000.0)
	_ok(empty.position(777.0) == 777.0, "Ohne Timing-Punkte: linear")


func _test_sv_double() -> void:
	var m := _map([_red(0.0, 500.0), _green(1000.0, 2.0), _green(2000.0, 1.0)], 10000.0)
	_ok(_near(m.position(1000.0) - m.position(0.0), 1000.0), "SV 1.0 vor Abschnitt")
	_ok(_near(m.position(2000.0) - m.position(1000.0), 2000.0), "SV 2.0 doppelt so schnell")
	_ok(_near(m.position(3000.0) - m.position(2000.0), 1000.0), "SV zurueck auf 1.0")


func _test_bpm_change() -> void:
	# Basis 500ms (laengster Abschnitt), dann 250ms (doppelte BPM) -> doppelt so schnell.
	var m := _map([_red(0.0, 500.0), _red(8000.0, 250.0)], 10000.0)
	_ok(_near(m.base_beat_length, 500.0), "Basis-BeatLength = laengste rote Linie")
	_ok(_near(m.position(9000.0) - m.position(8000.0), 2000.0), "BPM-Wechsel relativ zur Basis")
	# Rote Linie setzt SV zurueck.
	var m2 := _map([_red(0.0, 500.0), _green(1000.0, 3.0), _red(2000.0, 500.0)], 10000.0)
	_ok(_near(m2.position(3000.0) - m2.position(2000.0), 1000.0), "Rote Linie setzt SV auf 1")


func _test_stop() -> void:
	var m := _map([_red(0.0, 500.0), _green(1000.0, 0.001), _green(3000.0, 1.0)], 10000.0)
	var d := m.position(3000.0) - m.position(1000.0)
	_ok(_near(d, 20.0), "Stop (SV geklemmt auf 0.01) friert fast ein")
	_ok(m.spawn_time(3500.0, 1000.0) < 1000.0, "Stop: Note nach Stop spawnt vor dem Stop")


func _test_monotonic() -> void:
	var m := _map([_red(0.0, 300.0), _green(500.0, 0.5), _red(1500.0, 200.0),
			_green(1600.0, 4.0), _green(2600.0, 0.01), _green(4000.0, 10.0)], 6000.0)
	var mono := true
	var prev := m.position(-1000.0)
	var t := -1000.0
	while t <= 7000.0:
		var p := m.position(t)
		if p < prev:
			mono = false
		prev = p
		t += 7.3
	_ok(mono, "Position monoton steigend")


func _test_hold_end() -> void:
	var m := _map([_red(0.0, 500.0), _green(1000.0, 2.0)], 10000.0)
	var head := m.position(1500.0)
	var tail := m.position(2500.0)
	_ok(_near(tail - head, 2000.0), "Hold-Ende: Koerper dehnt sich bei SV 2")
	var m2 := _map([_red(0.0, 500.0), _green(1000.0, 0.5)], 10000.0)
	_ok(_near(m2.position(2500.0) - m2.position(1500.0), 500.0), "Hold-Ende: Koerper staucht bei SV 0.5")


func _test_base_beat_length() -> void:
	# Kein Objekt-Ende vor zweiter Linie: erste dauert ab 0.
	var m := _map([_red(100.0, 400.0), _red(5000.0, 300.0)], 6000.0)
	_ok(_near(m.base_beat_length, 400.0), "MCBL: erste rote Linie zaehlt ab 0")
	var m2 := _map([_red(0.0, 400.0), _red(20000.0, 300.0)], 10000.0)
	_ok(_near(m2.base_beat_length, 400.0), "MCBL: Linie nach Map-Ende Dauer 0")


func _test_inverse_spawn() -> void:
	var m := _map([_red(0.0, 500.0), _green(1000.0, 2.0), _green(2000.0, 0.25)], 10000.0)
	var ok := true
	for hit in [500.0, 1500.0, 2200.0, 5000.0]:
		var s := m.spawn_time(hit, 1000.0)
		if not _near(m.position(hit) - m.position(s), 1000.0, 1e-4):
			ok = false
	_ok(ok, "spawn_time: Abstand bei Spawn == Sichtweite")
	_ok(_near(m.time_at(m.position(-300.0)), -300.0, 1e-6), "Inverse vor erstem Punkt")


func _test_tie_green_wins() -> void:
	# Gruen vor Rot im Array, gleiche Zeit: Gruen gewinnt trotzdem.
	var m := _map([_green(1000.0, 2.0), _red(0.0, 500.0), _red(1000.0, 500.0)], 10000.0)
	_ok(_near(m.position(2000.0) - m.position(1000.0), 2000.0), "Gleiche Zeit rot+gruen: gruen gewinnt")
