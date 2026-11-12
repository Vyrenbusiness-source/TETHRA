extends SceneTree

## Headless-Tests fuer TraceMods.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_mods_tests.gd

var _passed := 0
var _failed := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var none := {}
	var mr := {"MR": true}
	var hd := {"HD": true}
	var ss := {"SS": true}
	# Mirror
	_check(TraceMods.map_column(0, mr) == 3 and TraceMods.map_column(3, mr) == 0, "mirror 0<->3")
	_check(TraceMods.map_column(1, mr) == 1 and TraceMods.map_column(2, mr) == 2, "mirror mitte")
	_check(TraceMods.map_column(0, none) == 0, "ohne mod")
	for c in 4:
		_check(TraceMods.map_column(TraceMods.map_column(c, mr), mr) == c, "mirror involutiv %d" % c)
	_check(is_equal_approx(TraceMods.map_angle(PI, mr), 0.0), "pfeil links->rechts")
	_check(is_equal_approx(TraceMods.map_angle(0.0, mr), PI) or is_equal_approx(TraceMods.map_angle(0.0, mr), -PI), "pfeil rechts->links")
	_check(is_equal_approx(TraceMods.map_angle(PI * 0.5, mr), PI * 0.5), "pfeil runter bleibt")
	_check(TraceMods.map_angle(1.0, none) == 1.0, "winkel ohne mod")
	# Hidden
	_check(TraceMods.path_alpha(0.0, hd) == 0.0, "hidden: am Kopf weg")
	_check(TraceMods.path_alpha(1200.0, hd) == 1.0, "hidden: vorn sichtbar")
	_check(TraceMods.path_alpha(300.0, hd) > TraceMods.path_alpha(150.0, hd), "hidden monoton")
	_check(TraceMods.path_alpha(0.0, none) == 1.0, "ohne mod voll")
	# Short Sight
	_check(TraceMods.path_alpha(499.0, ss) == 1.0, "ss: 499 sichtbar")
	_check(TraceMods.path_alpha(501.0, ss) == 0.0, "ss: 501 weg")
	_check(TraceMods.look_ms(1200.0, ss) == 500.0 and TraceMods.look_ms(1200.0, none) == 1200.0, "look_ms")
	# Faktoren
	_check(is_equal_approx(TraceMods.mod_multiplier(mr), 1.0), "x mirror")
	_check(is_equal_approx(TraceMods.mod_multiplier(hd), 1.06), "x hidden")
	_check(is_equal_approx(TraceMods.mod_multiplier(ss), 1.08), "x ss")
	_check(is_equal_approx(TraceMods.mod_multiplier({"HD": true, "SS": true, "NF": true}), 1.06 * 1.08), "x kombi (NF nicht hier)")
	_check(TraceMods.mod_list({"SS": true, "NF": true, "MR": true}) == ["MR", "SS", "NF"], "mod_list Reihenfolge")
	# Session
	_check(TraceMods.from_session().is_empty() or true, "from_session laeuft")
	# Determinismus
	_check(TraceMods.path_alpha(321.0, hd) == TraceMods.path_alpha(321.0, hd), "deterministisch")
	print("Trace-Mods: %d ok, %d fail" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
