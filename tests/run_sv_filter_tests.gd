extends SceneTree

## Headless-Tests fuer die SV-Erkennung (Bibliothek + Mirror-Suche).
## Ausfuehren:
##   Godot..._console.exe --headless --path . --script res://tests/run_sv_filter_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA SV-Filter-Tests ===")
	_test_detect()
	_test_text()
	_test_item()
	_test_mapset()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _tp(time: float, bl: float, red: bool) -> TimingPoint:
	var t := TimingPoint.new()
	t.time = time
	t.beat_length = bl
	t.uninherited = red
	return t


## Map mit Grundtempo 500 ms und n gruenen Linien (SV sv) alle 500 ms.
func _greens(n: int, sv: float) -> Array:
	var a: Array = [_tp(0, 500.0, true)]
	for i in n:
		a.append(_tp(1000.0 + i * 500.0, -100.0 / sv, false))
	return a


func _sv(tps: Array, t0: float = 0.0, t1: float = 100000.0) -> bool:
	return bool(MapLibrary.sv_stats_tp(tps, t0, t1).sv)


## Abwechselnd sv_a / sv_b alle step ms im Fenster 0..end.
func _alt(sv_a: float, sv_b: float, step: float, end: float) -> Array:
	var a: Array = [_tp(0, 500.0, true)]
	var t := 0.0
	var k := 0
	while t < end:
		a.append(_tp(t, -100.0 / (sv_a if k % 2 == 0 else sv_b), false))
		t += step
		k += 1
	return a


func _test_detect() -> void:
	_ok(not _sv([]), "leer: keine SV")
	_ok(not _sv(_greens(20, 1.0)), "20 Linien mit SV 1.0: keine SV")
	var reds: Array = []
	for i in 30:
		reds.append(_tp(i * 1000.0, 400.0 + i * 10.0, true))
	_ok(not _sv(reds, 0.0, 30000.0), "nur rote Linien (Tempo-Drift): keine SV")
	# Konstante Map mit BPM-Ausgleichslinien: 40 BPM-Wechsel 120 <-> 240 BPM,
	# jede rote Linie mit gruener Linie, die genau ausgleicht (m == 1).
	var comp: Array = []
	for i in 40:
		var t := i * 2500.0
		if i % 2 == 0:
			comp.append(_tp(t, 500.0, true))
		else:
			comp.append(_tp(t, 250.0, true))
			comp.append(_tp(t, -200.0, false))  # SV 0.5 * 500/250 = 1
	var st := MapLibrary.sv_stats_tp(comp, 0.0, 100000.0)
	_ok(not st.sv and st.jumps == 0 and float(st.frac) == 0.0,
		"BPM-Ausgleichslinien: keine SV (%s)" % str(st))
	# Ausgleichslinie 1 ms nach der roten Linie (haeufig in echten Maps).
	var late: Array = []
	for i in 40:
		var t := i * 2500.0
		if i % 2 == 0:
			late.append(_tp(t, 500.0, true))
		else:
			late.append(_tp(t, 1000.0, true))
			late.append(_tp(t + 1.0, -50.0, false))  # SV 2.0 * 500/1000 = 1
	st = MapLibrary.sv_stats_tp(late, 0.0, 100000.0)
	_ok(not st.sv and st.jumps == 0, "Ausgleich 1 ms spaeter: keine SV (%s)" % str(st))
	# Reiner BPM-Wechsel ohne gruene Linie (halbe Map doppelt so schnell).
	var bpm: Array = [_tp(0, 500.0, true), _tp(50000.0, 250.0, true)]
	_ok(not _sv(bpm), "reiner BPM-Wechsel: keine SV")
	# Global gesetzte SV 0.8 (konstant langsamer, keine Wechsel).
	_ok(not _sv([_tp(0, 500.0, true), _tp(0, -125.0, false)]), "globale SV 0.8: keine SV")
	# Mini-Abweichungen: 0.95 <-> 1.05 alle 500 ms ueber die ganze Map.
	st = MapLibrary.sv_stats_tp(_alt(0.95, 1.05, 500.0, 100000.0), 0.0, 100000.0)
	_ok(not st.sv and float(st.frac) == 0.0 and st.jumps == 0,
		"Mini-Abweichungen 0.95/1.05: keine SV (%s)" % str(st))
	# Wenige kurze SV-Effekte: 5 x 500 ms SV 0.5 in 100 s (2.5 %, 10 Wechsel).
	var few: Array = [_tp(0, 500.0, true)]
	for i in 5:
		few.append(_tp(10000.0 + i * 15000.0, -200.0, false))
		few.append(_tp(10500.0 + i * 15000.0, -100.0, false))
	st = MapLibrary.sv_stats_tp(few, 0.0, 100000.0)
	_ok(not st.sv and st.jumps == 10, "5 kurze SV-Effekte: keine SV (%s)" % str(st))
	# Echte SV-Map: 0.5 <-> 1.5 alle 1000 ms.
	st = MapLibrary.sv_stats_tp(_alt(0.5, 1.5, 1000.0, 100000.0), 0.0, 100000.0)
	_ok(st.sv and float(st.frac) >= 0.45 and int(st.jumps) > 50, "echte SV 0.5/1.5: SV (%s)" % str(st))
	# Langer langsamer Abschnitt: 20 % der Map SV 0.5, sonst 1.0.
	var slow: Array = [_tp(0, 500.0, true), _tp(40000.0, -200.0, false),
		_tp(60000.0, -100.0, false)]
	st = MapLibrary.sv_stats_tp(slow, 0.0, 100000.0)
	_ok(st.sv and absf(float(st.frac) - 0.2) < 0.001, "20 %% SV-Abschnitt: SV (%s)" % str(st))
	# Stutter-SV: 14 kurze Stopps (SV 0.01, 200 ms) -> 28 Wechsel, frac klein.
	var stut: Array = [_tp(0, 500.0, true)]
	for i in 14:
		stut.append(_tp(5000.0 + i * 6000.0, -10000.0, false))
		stut.append(_tp(5200.0 + i * 6000.0, -100.0, false))
	st = MapLibrary.sv_stats_tp(stut, 0.0, 100000.0)
	_ok(st.sv and int(st.jumps) == 28, "14 Stopps: SV durch Wechsel (%s)" % str(st))
	# BPM-Abschnitt 240 BPM mit Ausgleich (SV 0.5 -> m = 1), danach ohne.
	var mix: Array = [_tp(0, 500.0, true), _tp(30000.0, 250.0, true),
		_tp(30000.0, -200.0, false), _tp(50000.0, -100.0, false),
		_tp(70000.0, 500.0, true)]
	st = MapLibrary.sv_stats_tp(mix, 0.0, 100000.0)
	_ok(not st.sv, "Ausgleich, danach BPM-Abschnitt ohne Ausgleich: keine SV (%s)" % str(st))
	var mix2: Array = [_tp(0, 500.0, true), _tp(30000.0, 250.0, true),
		_tp(30000.0, -200.0, false), _tp(50000.0, -100.0, false),
		_tp(50000.0, 250.0, true), _tp(50000.0, -100.0, false),
		_tp(70000.0, 500.0, true), _tp(70000.0, -200.0, false)]
	st = MapLibrary.sv_stats_tp(mix2, 0.0, 100000.0)
	_ok(st.sv and absf(float(st.frac) - 0.3) < 0.001, "SV 0.5 nach Ausgleichsabschnitt: SV (%s)" % str(st))
	# Fenster: SV nur vor der ersten Note zaehlt nicht.
	var intro: Array = [_tp(0, 500.0, true), _tp(0, -200.0, false), _tp(20000.0, -100.0, false)]
	_ok(not _sv(intro, 20000.0, 100000.0), "SV nur im Intro vor der ersten Note: keine SV")
	# Beatmap-Variante: Fenster aus den Noten.
	var bm := Beatmap.new()
	for tp in _alt(0.5, 1.5, 1000.0, 60000.0):
		bm.timing_points.append(tp)
	for i in 100:
		var o := HitObject.new()
		o.time = 1000.0 + i * 500.0
		bm.hit_objects.append(o)
	_ok(MapLibrary.detect_sv(bm), "detect_sv(Beatmap) mit SV")
	_ok(not MapLibrary.detect_sv(Beatmap.new()), "detect_sv(Beatmap) ohne Noten")


func _test_text() -> void:
	_ok(BeatmapMirror.is_sv_text("Neko SV"), "Titel mit SV")
	_ok(BeatmapMirror.is_sv_text("[4K] sv gimmick"), "sv gimmick")
	_ok(BeatmapMirror.is_sv_text("slider velocity map"), "slider velocity")
	_ok(BeatmapMirror.is_sv_text("a (SV) b"), "SV in Klammern")
	_ok(not BeatmapMirror.is_sv_text("Harvest"), "kein SV in Harvest")
	_ok(not BeatmapMirror.is_sv_text("lsv tsv svelte"), "SV nur als ganzes Wort")
	_ok(not BeatmapMirror.is_sv_text(""), "leer")


func _test_item() -> void:
	var item := {"title": "x", "tags": "pop sv", "beatmaps": []}
	_ok(BeatmapMirror.is_sv_item(item), "Tag sv trifft")
	item = {"title": "x", "tags": "pop", "beatmaps": [
		{"mode_int": 3, "version": "[4K] SV Insane"}]}
	_ok(BeatmapMirror.is_sv_item(item), "Diff-Name SV trifft")
	item = {"title": "x", "tags": "pop", "beatmaps": [
		{"mode_int": 0, "version": "SV"}]}
	_ok(not BeatmapMirror.is_sv_item(item), "Diff-Name nur fuer Mania")


func _test_mapset() -> void:
	var ms := MapSet.from_dict("a.osz", {"title": "t", "diffs": [
		{"osu_filename": "a.osu"}, {"osu_filename": "b.osu"}]})
	_ok(not ms.has_sv() and ms.sv_ver == 0, "ohne Cache-Feld: kein SV, Version 0")
	ms.apply_sv({"a.osu": false, "b.osu": true})
	_ok(ms.has_sv(), "Set hat SV, wenn eine Diff SV hat")
	_ok(bool(ms.diffs[1].sv) and not bool(ms.diffs[0].sv), "Diff-Felder gesetzt")
	var back := MapSet.from_dict("a.osz", ms.to_dict())
	_ok(back.has_sv() and back.sv_ver == MapLibrary.SV_VERSION, "Cache-Roundtrip")
