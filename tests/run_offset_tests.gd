extends SceneTree

## Headless-Tests für die Offset-Logik des OffsetWizard.
##   Godot..._console.exe --headless --path . --script res://tests/run_offset_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	_check(OffsetWizard.median([]) == 0.0, "Median leer = 0")
	_check(OffsetWizard.median([5.0]) == 5.0, "Median einzeln")
	_check(OffsetWizard.median([3.0, 1.0, 2.0]) == 2.0, "Median ungerade")
	_check(is_equal_approx(OffsetWizard.median([4.0, 1.0, 2.0, 3.0]), 2.5), "Median gerade")

	var devs: Array = [20.0, 22.0, 18.0, 21.0, 19.0, 23.0, 20.0, 400.0, -300.0]
	var clean := OffsetWizard.reject_outliers(devs)
	_check(clean.size() == 7, "Ausreißer verworfen (%d)" % clean.size())
	_check(not clean.has(400.0) and not clean.has(-300.0), "Extremwerte entfernt")
	_check(OffsetWizard.reject_outliers([10.0, 900.0]).size() == 2, "unter 3 Werten kein Verwerfen")

	_check(OffsetWizard.suggest_offset(devs) == -20, "Spieler 20 ms zu spät -> -20 ms")
	_check(OffsetWizard.suggest_offset([-35.0, -30.0, -32.0, -31.0]) == 32 or OffsetWizard.suggest_offset([-35.0, -30.0, -32.0, -31.0]) == 31,
		"Spieler zu früh -> positiver Offset")
	_check(OffsetWizard.suggest_offset([900.0, 900.0, 900.0]) == -200, "Vorschlag auf +-200 begrenzt")
	_check(OffsetWizard.suggest_offset([]) == 0, "leer -> 0")

	_check(OffsetWizard.nearest_click(OffsetWizard.click_time(7) + 0.1) == 7, "nearest_click rundet")
	_check(OffsetWizard.nearest_click(OffsetWizard.click_time(7) - 0.1) == 7, "nearest_click rundet runter")

	if _failed > 0:
		print("=== %d Fehler ===" % _failed)
		quit(1)
	else:
		print("=== Offset-Tests OK ===")
		quit(0)
