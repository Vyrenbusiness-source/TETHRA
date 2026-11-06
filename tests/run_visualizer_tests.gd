extends SceneTree

## Headless-Tests fuer AudioVisualizer.
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_visualizer_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _initialize() -> void:
	print("=== AudioVisualizer-Tests ===")
	var script: GDScript = load("res://scripts/ui/audio_visualizer.gd")
	var v: Control = script.new()
	v.bars = 48
	_test_bands(v)
	_test_decay(v)
	v.free()
	print("=== Ergebnis: %d fehlgeschlagen ===" % _failed)
	quit(1 if _failed > 0 else 0)


func _test_bands(v: Control) -> void:
	var e: PackedFloat32Array = v._edges
	_check(e.size() == 49, "49 Bandkanten fuer 48 Balken")
	_check(absf(e[0] - 40.0) < 0.01 and absf(e[48] - 12000.0) < 1.0, "Bereich 40 Hz - 12 kHz")
	var mono := true
	var widening := true
	for i in range(1, e.size()):
		if e[i] <= e[i - 1]:
			mono = false
		if i >= 2 and (e[i] - e[i - 1]) < (e[i - 1] - e[i - 2]):
			widening = false
	_check(mono, "Kanten streng monoton steigend")
	_check(widening, "Bandbreite waechst (logarithmisch)")


func _test_decay(v: Control) -> void:
	for i in v.bars:
		v._raw[i] = 1.0
	for k in 30:
		v._step(1.0 / 60.0, 0.0)
	_check(v._level[0] > 0.5, "Attack steigt mit Signal")
	for i in v.bars:
		v._raw[i] = 0.0
	var prev: float = v._level[0]
	v._step(1.0 / 60.0, 0.0)
	_check(v._level[0] < prev, "Release faellt ohne Signal")
	for k in 60 * 10:
		v._step(1.0 / 60.0, 0.0)
	var zero := true
	for i in v.bars:
		if v._level[i] != 0.0 or v._peak[i] != 0.0:
			zero = false
	_check(zero, "Glaettung und Peaks fallen auf 0")
