extends SceneTree

## Headless-Test-Runner (Abschnitt 10, M1: Unit-Tests gegen echte .osu-Dateien).
## Ausfuehren:
##   Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd
##
## Deckt Abschnitt 3 (Parsing) und 3.5 (Difficulty-Formeln) ab.

var _passed := 0
var _failed := 0
var _fixtures := "res://tests/fixtures/"


func _initialize() -> void:
	print("=== HOOKLINE Parser-Tests ===")
	_test_v14_standard()
	_test_v9_old_and_ar_fallback()
	_test_greenlines_and_kiai()
	_test_mode_rejection()
	_test_difficulty_formulas()
	_test_bitfield_edgecases()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Assertion-Helfer
# ---------------------------------------------------------------------------

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (erwartet %s, war %s)" % [label, str(expected), str(actual)])


func _approx(actual: float, expected: float, label: String, eps: float = 0.001) -> void:
	_ok(absf(actual - expected) <= eps, "%s (erwartet %f, war %f)" % [label, expected, actual])


func _load_text(fixture: String) -> String:
	var f := FileAccess.open(_fixtures + fixture, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_v14_standard() -> void:
	print("- v14 Standard-Map")
	var res := OsuParser.parse(_load_text("v14_standard.osu"))
	_ok(res.ok, "Parse erfolgreich")
	if not res.ok:
		return
	var bm: Beatmap = res.beatmap
	_eq(bm.format_version, 14, "format_version")
	_eq(bm.mode(), 0, "Mode 0")
	_eq(bm.title(), "Test Song", "Title")
	_eq(bm.hit_objects.size(), 3, "Anzahl HitObjects")

	# [0] Circle
	var c: HitObject = bm.hit_objects[0]
	_eq(c.kind, HitObject.Kind.CIRCLE, "obj0 ist Circle")
	_approx(c.x, 256.0, "obj0.x")
	_approx(c.y, 192.0, "obj0.y")
	_approx(c.time, 1000.0, "obj0.time")

	# [1] Slider
	var s = bm.hit_objects[1]
	_eq(s.kind, HitObject.Kind.SLIDER, "obj1 ist Slider")
	_eq(s.curve_type, "B", "Slider curve_type B")
	_eq(s.slides, 2, "Slider slides")
	_approx(s.length, 310.5, "Slider length")
	_eq(s.curve_points.size(), 3, "Slider Kurvenpunkte (inkl. Start)")
	_approx(s.curve_points[0].x, 100.0, "Slider Startpunkt x")
	_approx(s.curve_points[0].y, 100.0, "Slider Startpunkt y")
	# beatLength 300, SV 2.0, mult 1.4: 310.5/(1.4*100*2)*300 = 332.678571
	_approx(s.single_duration_ms, 332.678571, "Slider single_duration", 0.01)
	_approx(s.total_duration_ms(), 665.357142, "Slider total_duration", 0.01)
	_approx(s.end_time(), 2000.0 + 665.357142, "Slider end_time", 0.01)

	# [2] Spinner (type 12 = 8|4)
	var sp = bm.hit_objects[2]
	_eq(sp.kind, HitObject.Kind.SPINNER, "obj2 ist Spinner")
	_ok(sp.new_combo, "Spinner new_combo (type & 4)")
	_approx(sp.spin_end_time, 7000.0, "Spinner endTime")
	_approx(sp.end_time(), 7000.0, "Spinner end_time()")

	# TimingPoints
	_eq(bm.timing_points.size(), 2, "Anzahl TimingPoints")
	var red: TimingPoint = bm.timing_points[0]
	_ok(red.uninherited, "TP0 rot")
	_approx(red.beat_length, 300.0, "TP0 beat_length")
	_approx(red.bpm(), 200.0, "TP0 BPM")
	var green: TimingPoint = bm.timing_points[1]
	_ok(not green.uninherited, "TP1 gruen")
	_approx(green.slider_velocity(), 2.0, "TP1 SV = -100/-50 = 2.0")


func _test_v9_old_and_ar_fallback() -> void:
	print("- v9 alte Map (AR=OD-Fallback, 2-Feld-TimingPoint)")
	var res := OsuParser.parse(_load_text("v9_old.osu"))
	_ok(res.ok, "Parse erfolgreich")
	if not res.ok:
		return
	var bm: Beatmap = res.beatmap
	_eq(bm.format_version, 9, "format_version 9")
	# AR fehlt -> AR = OD = 6
	_approx(bm.ar(), 6.0, "AR-Fallback = OD")
	# 2-Feld-TimingPoint -> uninherited default true
	_eq(bm.timing_points.size(), 1, "Anzahl TimingPoints")
	var tp: TimingPoint = bm.timing_points[0]
	_ok(tp.uninherited, "2-Feld-TP ist rot (uninherited=1)")
	_approx(tp.beat_length, 461.538461538462, "TP beat_length", 0.0001)
	_approx(tp.bpm(), 130.0, "TP BPM = 130", 0.001)
	# HitObjects: 2 Circles
	_eq(bm.hit_objects.size(), 2, "Anzahl HitObjects")
	_eq(bm.hit_objects[0].kind, HitObject.Kind.CIRCLE, "obj0 Circle")
	_eq(bm.hit_objects[1].kind, HitObject.Kind.CIRCLE, "obj1 Circle")
	_ok(bm.hit_objects[1].new_combo, "obj1 new_combo (type 5 = 1|4)")
	# preempt(6) = 1200 - 750*(1)/5 = 1050
	_approx(bm.preempt_ms(), 1050.0, "preempt(AR6)")


func _test_greenlines_and_kiai() -> void:
	print("- Viele gruene Linien + Kiai")
	var res := OsuParser.parse(_load_text("greenlines_kiai.osu"))
	_ok(res.ok, "Parse erfolgreich")
	if not res.ok:
		return
	var bm: Beatmap = res.beatmap
	# Kiai-Intervall: startet bei 1000 (Bit gesetzt), endet bei 3000 (ohne Bit)
	_eq(bm.kiai_intervals.size(), 1, "Anzahl Kiai-Intervalle")
	if bm.kiai_intervals.size() == 1:
		_approx(bm.kiai_intervals[0].start, 1000.0, "Kiai start")
		_approx(bm.kiai_intervals[0].end, 3000.0, "Kiai end")
	_ok(bm.is_kiai(1500.0), "is_kiai(1500) true")
	_ok(not bm.is_kiai(500.0), "is_kiai(500) false")
	_ok(bm.is_kiai(2999.0), "is_kiai(2999) true")
	_ok(not bm.is_kiai(3000.0), "is_kiai(3000) false (Intervallende exklusiv)")

	# Slider1 @1500: aktiver gruener Point t1000 (-50 -> SV2.0), beat 250, mult 1.6
	# 250/(1.6*100*2.0)*250 = 195.3125
	var s1 = bm.hit_objects[0]
	_approx(s1.single_duration_ms, 195.3125, "Slider1 duration (SV 2.0)", 0.001)
	# Slider2 @2500: aktiver gruener Point t2000 (-200 -> SV0.5)
	# 200/(1.6*100*0.5)*250 = 625
	var s2 = bm.hit_objects[1]
	_approx(s2.single_duration_ms, 625.0, "Slider2 duration (SV 0.5)", 0.001)

	_approx(bm.audio_lead_in(), 1000.0, "AudioLeadIn")


func _test_mode_rejection() -> void:
	print("- Mode-Gate (Mania akzeptiert, Taiko abgelehnt)")
	# Mania (Mode 3) wird seit dem 4K-Modus AKZEPTIERT und als Spalten geparst.
	var res := OsuParser.parse(_load_text("mania_reject.osu"))
	_ok(res.ok, "Mania-Map akzeptiert")
	if res.ok:
		_ok(res.beatmap.is_mania(), "als Mania erkannt")
		_ok(res.beatmap.hit_objects.size() == 1 and res.beatmap.hit_objects[0] is ManiaNote,
			"Note als ManiaNote geparst")
	# Taiko (Mode 1) bleibt abgelehnt.
	var taiko := OsuParser.parse("osu file format v14\n\n[General]\nMode: 1\n\n[HitObjects]\n256,192,1000,1,0,0:0:0:0:\n")
	_ok(not taiko.ok, "Taiko-Map abgelehnt")
	_ok(taiko.error.find("taiko") != -1, "Fehlermeldung nennt taiko")


func _test_difficulty_formulas() -> void:
	print("- Difficulty-Formeln (Abschnitt 3.5)")
	# Anker-Radius: 54.4 - 4.48*CS
	_approx(DifficultyCalc.anchor_radius(4.0), 36.48, "radius(CS4)")
	_approx(DifficultyCalc.anchor_radius(0.0), 54.4, "radius(CS0)")
	# Timing-Windows OD7
	_approx(DifficultyCalc.window_perfect(7.0), 38.0, "perfect(OD7)")
	_approx(DifficultyCalc.window_good(7.0), 84.0, "good(OD7)")
	_approx(DifficultyCalc.window_meh(7.0), 130.0, "meh(OD7)")
	# preempt: AR<5, =5, >5
	_approx(DifficultyCalc.preempt(3.0), 1200.0 + 600.0 * 2.0 / 5.0, "preempt(AR3)")
	_approx(DifficultyCalc.preempt(5.0), 1200.0, "preempt(AR5)")
	_approx(DifficultyCalc.preempt(8.0), 750.0, "preempt(AR8)")
	_approx(DifficultyCalc.preempt(9.0), 600.0, "preempt(AR9)")
	_approx(DifficultyCalc.preempt(10.0), 450.0, "preempt(AR10)")
	# fade_in = 2/3 preempt
	_approx(DifficultyCalc.fade_in(5.0), 800.0, "fade_in(AR5)")
	# playfield scale
	_approx(DifficultyCalc.playfield_scale(768.0), 2.0, "scale(768)")


func _test_bitfield_edgecases() -> void:
	print("- type-Bitfeld-Prioritaet (Slider vor Spinner vor Circle)")
	# type 2 = Slider (auch wenn Bit0 nicht gesetzt)
	var slider_line := "0,0,0,2,0,L|100:0,1,100,0:0|0:0,"
	var res := OsuParser.parse(_wrap_single(slider_line))
	_ok(res.ok, "Parse ok")
	if res.ok:
		_eq(res.beatmap.hit_objects[0].kind, HitObject.Kind.SLIDER, "type 2 -> Slider")
	# type 8 = Spinner
	var spinner_line := "256,192,0,8,0,500,0:0:0:0:"
	res = OsuParser.parse(_wrap_single(spinner_line))
	if res.ok:
		_eq(res.beatmap.hit_objects[0].kind, HitObject.Kind.SPINNER, "type 8 -> Spinner")
	# type 1 = Circle
	var circle_line := "10,20,0,1,0,0:0:0:0:"
	res = OsuParser.parse(_wrap_single(circle_line))
	if res.ok:
		_eq(res.beatmap.hit_objects[0].kind, HitObject.Kind.CIRCLE, "type 1 -> Circle")


func _wrap_single(hitobject_line: String) -> String:
	return "osu file format v14\n\n[General]\nMode: 0\n\n[Difficulty]\nSliderMultiplier: 1.4\nOverallDifficulty: 5\n\n[TimingPoints]\n0,300,4,1,0,100,1,0\n\n[HitObjects]\n" + hitobject_line + "\n"
