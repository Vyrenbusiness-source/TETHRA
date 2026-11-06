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


func _greens(n: int, sv: float) -> Array:
	var a: Array = [_tp(0, 500.0, true)]
	for i in n:
		a.append(_tp(1000.0 + i * 500.0, -100.0 / sv, false))
	return a


func _test_detect() -> void:
	_ok(not MapLibrary.detect_sv([]), "leer: keine SV")
	_ok(not MapLibrary.detect_sv(_greens(20, 1.0)), "20 Linien mit SV 1.0: keine SV")
	_ok(not MapLibrary.detect_sv(_greens(9, 1.5)), "9 Linien SV 1.5: unter Schwelle")
	_ok(MapLibrary.detect_sv(_greens(10, 1.5)), "10 Linien SV 1.5: SV")
	_ok(MapLibrary.detect_sv(_greens(30, 0.5)), "30 Linien SV 0.5: SV")
	var reds: Array = []
	for i in 30:
		reds.append(_tp(i * 1000.0, 400.0 + i * 10.0, true))
	_ok(not MapLibrary.detect_sv(reds), "nur rote Linien: keine SV")


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
