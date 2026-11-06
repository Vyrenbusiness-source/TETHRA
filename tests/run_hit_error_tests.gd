extends SceneTree

## Headless-Tests fuer HitErrorBar (Mittelwert, Ringpuffer, UR).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	var b := HitErrorBar.new()
	root.add_child(b)
	b.setup({"max": 16, "w300": 40, "w200": 73, "w100": 103, "w50": 127}, 300.0)
	_check(b.get_count() == 0 and b.get_mean() == 0.0, "leer")
	b.add_hit(10.0)
	b.add_hit(-20.0)
	_check(b.get_count() == 2, "Anzahl 2")
	_check(is_equal_approx(b.get_mean(), -5.0), "Mittelwert -5")
	_check(is_equal_approx(b.get_ur(), 150.0), "UR 150")
	b.reset()
	_check(b.get_count() == 0 and b.get_mean() == 0.0, "reset")
	for i in 100:
		b.add_hit(float(i))
	_check(b.get_count() == HitErrorBar.CAP, "Ringpuffer begrenzt auf 64")
	_check(is_equal_approx(b.get_mean(), 67.5), "Mittelwert der letzten 64 (36..99)")
	if _failed > 0:
		print("=== HitError FAIL ===")
		quit(1)
		return
	print("=== HitError OK ===")
	quit(0)
