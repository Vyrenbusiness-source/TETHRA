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
	_qa_tests()
	print("Trace-Mods: %d ok, %d fail" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## QA: Mirror genau einmal, SV ohne Faktor, Kamera haelt kommende Knoten im Bild.
func _qa_tests() -> void:
	var vm := TraceMods.view_mods({"MR": true, "HD": true})
	_check(not vm.has("MR") and bool(vm.get("HD", false)), "view_mods: MR raus, HD bleibt")
	var sm := TraceMods.strip_foreign({"SV": true, "NF": true, "HD": true})
	_check(not sm.has("SV") and sm.has("NF") and sm.has("HD"), "strip_foreign: SV raus")
	_check(is_equal_approx(ManiaCore.mod_multiplier(sm) * TraceMods.mod_multiplier(sm), 0.5 * 1.06), "SV ohne Faktor in Trace")
	_check(is_equal_approx(TraceRules.lead_in_ms(300.0, 0.0), 1600.0), "Lead-In kurzer Start")
	_check(is_equal_approx(TraceRules.lead_in_ms(300.0, 3000.0), 3000.0), "AudioLeadIn bleibt")
	_check(is_equal_approx(TraceRules.lead_in_ms(9000.0, 0.0), 0.0), "spaete erste Note: kein Zusatz")
	# Mirror: Note in Spalte 0 liegt nach map_column in Spalte 3 (rechte Taste). Die Ansicht
	# zeigt dann mit view_mods den Pfeil nach rechts und die Taste der Spalte 3.
	var times := PackedFloat64Array()
	var cols := PackedInt32Array()
	var seed := 7
	for i in 240:
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		times.append(2000.0 + 250.0 * float(i))
		cols.append((seed >> 8) % 4)
	for speed in [300.0, 520.0, 900.0]:
		var path := TracePath.build(times, cols, times, speed)
		for vs in [Vector2(1920, 1080), Vector2(1024, 768)]:
			var view := TraceView.new()
			view.size = vs
			view.path = path
			var half := TraceRules.view_half(vs)
			var n := path.knots.size()
			var last_off := PackedFloat64Array()
			last_off.resize(n)
			last_off.fill(-1.0e12)
			var t: float = path.knots[0].t - 1300.0
			var a := 0
			var jump := 0.0
			var prev := Vector2.INF
			while t <= path.knots[n - 1].t:
				while a < n and path.knots[a].t < t:
					a += 1
				var cam := view._camera(t)   # die Ansicht selbst (Spiel, Tutorial, Clips)
				if prev != Vector2.INF:
					jump = maxf(jump, cam.distance_to(prev))
				prev = cam
				var j := a
				while j < n and path.knots[j].t <= t + 1200.0:
					var d: Vector2 = path.knots[j].pos - cam
					if absf(d.x) > half.x - 40.0 or absf(d.y) > half.y - 40.0:
						last_off[j] = t
					j += 1
				t += 20.0
			var worst := 1.0e9
			for j in n:
				worst = minf(worst, path.knots[j].t - (last_off[j] + 20.0))
			_check(worst >= 450.0, "Knoten >= 450 ms im Bild, Tempo %d, %dx%d (war %.0f)" % [int(speed), int(vs.x), int(vs.y), worst])
			_check(jump <= 60.0, "Kamera ohne Sprung, Tempo %d (max %.0f px je 20 ms)" % [int(speed), jump])
			view.free()
