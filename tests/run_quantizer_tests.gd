extends SceneTree

## Headless-Tests fuer BeatQuantizer.
##   Godot..._console.exe --headless --path . --audio-driver Dummy --script res://tests/run_quantizer_tests.gd

var _failed := 0
var _fired: Array = []


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _tp(time: float, bl: float, meter: int = 4) -> TimingPoint:
	var p := TimingPoint.new()
	p.time = time
	p.beat_length = bl
	p.meter = meter
	p.uninherited = true
	return p


func _mk(bl: float = 250.0) -> BeatQuantizer:
	var q := BeatQuantizer.new()
	q.setup([_tp(0.0, bl)])
	return q


func _mark(tag: String) -> void:
	_fired.append(tag)


func _initialize() -> void:
	print("=== BeatQuantizer-Tests ===")
	# Beat 250 ms
	var q := _mk()
	q.process(10.0)
	q.schedule(_mark.bind("a"), 1)
	q.process(200.0)
	_check(_fired.is_empty(), "vor Kante nichts")
	q.process(249.0)
	_check(_fired.is_empty(), "249 nichts")
	q.process(251.0)
	_check(_fired == ["a"], "beat feuert bei 251")
	q.process(260.0)
	_check(_fired.size() == 1, "nur einmal")

	_fired.clear()
	q.process(260.0)
	q.schedule(_mark.bind("h"), 2)
	q.process(499.0)
	_check(_fired.is_empty(), "halber Takt: 499 nichts")
	q.process(501.0)
	_check(_fired == ["h"], "halber Takt bei 500")

	# Downbeat: bl 100 -> Takt 400 ms, naechster Downbeat 400, Abstand <=300
	_fired.clear()
	q = _mk(100.0)
	q.process(150.0)
	q.schedule(_mark.bind("d"), 4)
	q.process(399.0)
	_check(_fired.is_empty(), "downbeat 399 nichts")
	q.process(401.0)
	_check(_fired == ["d"], "downbeat bei 400")

	# Kante >300 ms: sofort
	_fired.clear()
	q = _mk(500.0)
	q.process(10.0)
	q.schedule(_mark.bind("s"), 4)
	_check(_fired == ["s"], "Downbeat 1990 ms weg -> sofort")
	q.schedule(_mark.bind("t"), 1)
	_check(_fired.size() == 2 and q.pending() == 0, "Beat 490 ms weg -> sofort")

	# Ohne Timing: sofort
	_fired.clear()
	var e := BeatQuantizer.new()
	e.process(0.0)
	e.schedule(_mark.bind("e"))
	_check(_fired == ["e"], "ohne Daten sofort")

	# clear / Seek zurueck
	_fired.clear()
	q = _mk()
	q.process(10.0)
	q.schedule(_mark.bind("c"), 1)
	q.clear()
	q.process(300.0)
	_check(_fired.is_empty() and q.pending() == 0, "clear verwirft")
	q.process(310.0)
	q.schedule(_mark.bind("r"), 1)
	q.process(5.0)
	q.process(300.0)
	_check(_fired.is_empty(), "Rueckwaertssprung verwirft")

	# grosser Vorwaertssprung feuert genau einmal
	q = _mk()
	q.process(10.0)
	q.schedule(_mark.bind("j"), 1)
	q.process(5000.0)
	q.process(5010.0)
	_check(_fired == ["j"], "Sprung einmal")

	# Timing-Wechsel: roter Punkt bei 300 vor Beat 500
	_fired.clear()
	q = BeatQuantizer.new()
	q.setup([_tp(0.0, 250.0), _tp(300.0, 1000.0)])
	q.process(260.0)
	q.schedule(_mark.bind("w"), 1)
	q.process(299.0)
	_check(_fired.is_empty(), "Wechsel 299 nichts")
	q.process(301.0)
	_check(_fired == ["w"], "Kante am neuen roten Punkt")

	print("FAILED: ", _failed)
	quit(1 if _failed > 0 else 0)
