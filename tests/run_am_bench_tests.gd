extends SceneTree

## Headless-Tests fuer den Auto-Mapper-Pruefstand (Task am-bench): bekannte Eingaben -> bekannte
## Kennzahl. Ohne ffmpeg, ohne maps/. Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_bench_tests.gd

const B := preload("res://tools/automap_bench.gd")
const T := preload("res://tools/automap_tune.gd")

const STUB_GRID := """extends RefCounted
const DEFAULTS := {"win": 0.4, "steps": 4, "name": "x", "flag": true, "zero": 0.0, "lag": 10.0}
const TUNE_RANGES := {"lag": [0.0, 20.0]}
static func track(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary:
	return {"ok": true, "error": "", "confidence": 0.9, "alternatives": [{"factor": 2.0, "score": 0.5}],
			"segments": [{"start_ms": 100.0 + float(params.get("lag", 0.0)), "beat_ms": 500.0, "meter": 4, "downbeat_ms": 100.0 + float(params.get("lag", 0.0))}]}
"""
const STUB_FEATURES := """extends RefCounted
static func analyze(pcm: PackedFloat32Array, rate: int, params: Dictionary = {}) -> Dictionary:
	return {"ok": true, "error": "", "duration_ms": 20000.0, "events": [], "energy": PackedFloat32Array(), "frame_ms": 10.0,
			"sections": [{"start_ms": 0.0, "end_ms": 4100.0, "intensity": 0.2, "kind": "intro", "kiai": false, "lead": "drums"},
				{"start_ms": 4100.0, "end_ms": 8100.0, "intensity": 0.9, "kind": "chorus", "kiai": true, "lead": "drums"},
				{"start_ms": 8100.0, "end_ms": 20000.0, "intensity": 0.4, "kind": "outro", "kiai": false, "lead": "drums"}]}
"""
const STUB_CHART := """extends RefCounted
static func build(features: Dictionary, grid: Dictionary, profile: String, params: Dictionary = {}) -> Dictionary:
	var notes := []
	var s: Dictionary = grid.segments[0]
	for k in 20:
		notes.append({"t_ms": s.start_ms + k * s.beat_ms, "col": k % 4, "end_ms": (s.start_ms + k * s.beat_ms + 250.0) if k == 3 else -1.0})
	return {"ok": true, "error": "", "profile": profile, "notes": notes, "stats": {}}
static func lint(notes: Array, grid: Dictionary, profile: String) -> Array:
	return ["Jack zu lang", "Balance"] if profile == "Expert" else []
"""

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _near(a, b: float, label: String, tol: float = 1e-6) -> void:
	_ok(a != null and not is_nan(float(a)) and absf(float(a) - b) <= tol, "%s: %s statt %s" % [label, str(a), str(b)])


func _run() -> void:
	print("=== OMEN Auto-Mapper-Pruefstand-Tests ===")
	_test_basics()
	_test_truth_segments()
	_test_tempo()
	_test_phase()
	_test_segments()
	_test_downbeat()
	_test_notes()
	_test_stars()
	_test_record_and_report()
	_test_stubs()
	_test_old_adapter()
	_test_click()
	_test_tune()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _seg(start: float, beat: float, meter: int = 4, down = null) -> Dictionary:
	return {"start_ms": start, "beat_ms": beat, "meter": meter, "downbeat_ms": start if down == null else float(down)}


func _truth_seg(a: float, b: float, beat: float, down: float = 0.0, meter: int = 4) -> Dictionary:
	return {"start_ms": a, "end_ms": b, "beat_ms": beat, "meter": meter, "downbeat_ms": down}


func _test_basics() -> void:
	_ok(B.split_of("Song A.osz") == B.split_of("song a.OSZ"), "split unabhaengig von Gross/Klein")
	_ok(B.split_of("x/y/Song A.osz") == B.split_of("Song A.osz"), "split unabhaengig vom Ordner")
	var tune := 0
	for i in 1000:
		if B.split_of("map_%d.osz" % i) == "tune":
			tune += 1
	_ok(tune > 640 and tune < 760, "split etwa 70/30: %d" % tune)
	_near(B.percentile([4, 1, 3, 2], 50.0), 2.5, "Median")
	var r: Array = []
	for i in 101:
		r.append(i)
	_near(B.percentile(r, 95.0), 95.0, "p95")
	_ok(is_nan(B.median([])), "Median leer = NAN")
	var m: Array = B.merge_intervals([[5, 7], [0, 2], [1, 3], [9, 9]])
	_ok(m.size() == 2 and m[0][0] == 0.0 and m[0][1] == 3.0 and m[1][0] == 5.0, "merge_intervals: %s" % str(m))
	_near(B.interval_iou([[0, 10]], [[5, 15]]), 5.0 / 15.0, "IoU halb versetzt")
	_near(B.interval_iou([[0, 10], [20, 30]], [[0, 10], [20, 30]]), 1.0, "IoU gleich")
	_near(B.interval_iou([[0, 10]], []), 0.0, "IoU eine Seite leer")
	_ok(is_nan(B.interval_iou([], [])), "IoU beide leer = NAN")
	_near(B.wrap_c(260.0, 500.0), -240.0, "wrap_c")


func _test_truth_segments() -> void:
	var a: Dictionary = B.truth_segments([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 2000.0, "beat_ms": 500.0, "meter": 4}], 0.0, 10000.0)
	_ok(a.segments.size() == 1 and not a.effect, "gleiche Linie auf dem Gitter = 1 Segment")
	a = B.truth_segments([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 2100.0, "beat_ms": 500.0, "meter": 4}], 0.0, 10000.0)
	_ok(a.segments.size() == 2, "gleiches Tempo neben dem Gitter = 2 Segmente")
	a = B.truth_segments([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 4000.0, "beat_ms": 400.0, "meter": 4}], 0.0, 10000.0)
	_ok(a.segments.size() == 2 and a.segments[0].end_ms == 4000.0 and a.segments[1].end_ms == 10000.0 and not a.effect, "Tempowechsel: Enden")
	a = B.truth_segments([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 4000.0, "beat_ms": 0.01, "meter": 4}, {"time": 4010.0, "beat_ms": 500.0, "meter": 4}], 0.0, 10000.0)
	_ok(a.effect, "Effekt-Linie erkannt")
	a = B.truth_segments([{"time": 0.0, "beat_ms": 600.0, "meter": 4}, {"time": 5000.0, "beat_ms": 500.0, "meter": 4}], 6000.0, 20000.0)
	_ok(a.segments.size() == 1 and a.segments[0].beat_ms == 500.0, "Linie vor der ersten Note zaehlt nicht")
	a = B.truth_segments([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 30000.0, "beat_ms": 400.0, "meter": 4}], 0.0, 20000.0)
	_ok(a.segments.size() == 1, "Linie nach der letzten Note zaehlt nicht")
	a = B.truth_segments([{"time": 0.0, "beat_ms": -100.0, "meter": 4}], 0.0, 20000.0)
	_ok(a.segments.is_empty(), "keine rote Linie")


func _test_tempo() -> void:
	var t := _truth_seg(0.0, 10000.0, 500.0)
	_ok(B.tempo_eval([_seg(0.0, 500.0)], t).exact, "Tempo gleich = exakt")
	_ok(B.tempo_eval([_seg(0.0, 502.0)], t).exact, "0,4 % daneben = exakt")
	_ok(not B.tempo_eval([_seg(0.0, 503.5)], t).exact, "0,7 % daneben = nicht exakt")
	var e: Dictionary = B.tempo_eval([_seg(0.0, 1000.0)], t)
	_ok(not e.exact and e.alt_factor == 0.0 and e.diag_factor == 2.0, "halbes Tempo ohne Meldung: nur Diagnose x2")
	_near(e.ratio, 0.5, "ratio halbes Tempo")
	e = B.tempo_eval([_seg(0.0, 1000.0)], t, [0.5, 2.0])
	_ok(not e.exact and e.alt_factor == 2.0, "halbes Tempo mit gemeldeter Alternative x2")
	e = B.tempo_eval([_seg(0.0, 333.333)], t, [2.0])
	_ok(e.alt_factor == 0.0 and e.diag_factor == 0.667, "x1,5 zu schnell: falsche Alternative zaehlt nicht")
	_ok(not B.tempo_eval([_seg(0.0, 500.0), _seg(5000.0, 480.0)], t).exact, "halber Song falsch = nicht exakt")
	_near(B.tempo_share([_seg(0.0, 500.0), _seg(5000.0, 480.0)], 500.0, 0.0, 10000.0), 0.5, "tempo_share")
	_ok(B.tempo_eval([_seg(0.0, 500.0), _seg(9700.0, 480.0)], t).exact, "letzte 3 % falsch = noch exakt (95 %)")


func _test_phase() -> void:
	var t := _truth_seg(0.0, 10000.0, 500.0)
	var p: Dictionary = B.phase_track([_seg(7.0, 500.0)], t)
	_near(p.offset_ms, 7.0, "Offset +7")
	_near(p.drift_ms, 0.0, "Drift 0")
	_ok(p.n == 21, "21 Schlaege")
	p = B.phase_track([_seg(-12.0, 500.0)], t)
	_near(p.offset_ms, -12.0, "Offset -12")
	p = B.phase_track([_seg(250.0, 500.0)], t)
	_near(absf(p.offset_ms), 250.0, "halber Schlag = voller Fehler")
	p = B.phase_track([_seg(0.0, 500.5)], t)
	_near(p.drift_ms, 10.0, "Drift 20 Schlaege x 0,5 ms", 1e-4)
	_near(p.offset_ms, 5.0, "Offset-Median bei Drift", 1e-4)
	p = B.phase_track([_seg(0.0, 498.0)], _truth_seg(0.0, 100000.0, 500.0))
	_near(p.drift_ms, -400.0, "Drift ueber mehr als einen halben Schlag wird verfolgt", 1e-3)
	# Wahrheit beginnt spaeter als ihr Taktanfang
	p = B.phase_track([_seg(3.0, 500.0)], _truth_seg(2100.0, 10000.0, 500.0, 0.0))
	_near(p.offset_ms, 3.0, "Offset bei spaeter erster Note")


func _test_segments() -> void:
	var truth := [_truth_seg(0.0, 4000.0, 500.0), _truth_seg(4000.0, 10000.0, 400.0, 4000.0)]
	var r: Dictionary = B.segments_eval([_seg(0.0, 500.0), _seg(4000.0, 400.0)], truth)
	_ok(r.ok and r.bound_ok == 1 and r.seg_ok == 2, "Tempowechsel getroffen")
	r = B.segments_eval([_seg(0.0, 500.0)], truth)
	_ok(not r.ok and r.seg_ok == 1 and str(r.cause).begins_with("kein Tempowechsel"), "kein Wechsel erkannt: %s" % r.cause)
	r = B.segments_eval([_seg(0.0, 500.0), _seg(4300.0, 400.0)], truth)
	_ok(r.ok, "Grenze 300 ms daneben (unter 1 Schlag) zaehlt")
	r = B.segments_eval([_seg(0.0, 500.0), _seg(4450.0, 400.0)], truth)
	_ok(not r.ok and r.bound_ok == 0, "Grenze 450 ms daneben (ueber 1 Schlag) zaehlt nicht")
	r = B.segments_eval([_seg(0.0, 500.0), _seg(4000.0, 410.0)], truth)
	_ok(not r.ok and r.bound_ok == 1 and r.seg_ok == 1, "Grenze richtig, Tempo im 2. Segment falsch")


func _test_downbeat() -> void:
	var t := _truth_seg(0.0, 60000.0, 500.0)
	_ok(B.downbeat_eval([_seg(0.0, 500.0)], t).ok, "Taktanfang gleich")
	var d: Dictionary = B.downbeat_eval([_seg(0.0, 500.0, 4, 500.0)], t)
	_ok(not d.ok and d.shift_beats == 1, "ein Schlag verschoben")
	_ok(B.downbeat_eval([_seg(0.0, 500.0, 4, 2000.0)], t).ok, "ein ganzer Takt verschoben = gleich")
	_ok(B.downbeat_eval([_seg(0.0, 500.0, 4, 20.0)], t).ok, "20 ms daneben = gleich")
	_ok(not B.downbeat_eval([_seg(0.0, 500.0, 4, 260.0)], t).ok, "halber Schlag daneben = falsch")
	d = B.downbeat_eval([_seg(0.0, 500.0, 3)], t)
	_ok(not d.ok and d.meter_gen == 3, "andere Taktart = falsch")


func _test_notes() -> void:
	_ok(B.match_count([0, 100, 200], [10, 100, 230]) == 2, "match_count")
	_ok(B.match_count([100, 100], [100]) == 1, "Akkord gegen Einzelnote = 1 Treffer")
	_ok(B.match_count([100, 100], [100, 100]) == 2, "Akkord gegen Akkord = 2")
	_ok(B.match_count([0], [15]) == 1 and B.match_count([0], [15.5]) == 0, "Grenze 15 ms")
	_ok(B.match_count([], [1, 2]) == 0, "leer")
	_ok(B.match_count([0, 20], [10]) == 1, "eine Menschen-Note nur einmal")
	_near(B.pearson([1, 2, 3, 4], [2, 4, 6, 8]), 1.0, "Pearson +1")
	_near(B.pearson([1, 2, 3, 4], [8, 6, 4, 2]), -1.0, "Pearson -1")
	_ok(is_nan(B.pearson([1, 1, 1], [1, 2, 3])), "Pearson ohne Streuung = NAN")
	var dense := [100, 200, 300, 400, 2500, 6100, 6200, 6300]
	_near(B.density_corr(dense, dense), 1.0, "Dichte gleich = 1")
	var c: Array = B.density_curve([0, 1999, 2000, 4500], 6000.0)
	_ok(c.size() == 3 and c[0] == 2.0 and c[1] == 1.0 and c[2] == 1.0, "Dichtekurve: %s" % str(c))
	_near(B.density_corr([100, 200, 300, 2100], [100, 2100, 2200, 2300]), -1.0, "Dichte gegenlaeufig = -1")
	_near(B.hold_overlap([[0, 100], [200, 300]], [[0, 60], [400, 500]]), 0.5, "Hold-Ueberlappung")
	_near(B.hold_overlap([[0, 100]], [[0, 49]]), 0.0, "Hold unter der Haelfte zaehlt nicht")
	_near(B.hold_overlap([], [[0, 49]]), 0.0, "keine erzeugten Holds = 0")
	_near(B.hold_overlap([[0, 100]], [[0, 30], [20, 60]]), 1.0, "Hold ueber zwei Menschen-Holds")
	_near(B.on_grid_share([0, 60, 80, 7], [_seg(0.0, 480.0)]), 0.75, "auf dem Gitter (1/8, 1/6)")


func _test_stars() -> void:
	_ok(B.star_in_band("Hard", 3.4) and not B.star_in_band("Hard", 3.9) and B.star_in_band("Easy", 1.3), "Band")
	_near(B.star_band_dist("Hard", 3.9), 0.1, "Bandabstand")
	_near(B.star_band_dist("Hard", 3.5), 0.0, "Bandabstand im Band")
	var diffs := [{"stars": 1.5}, {"stars": 3.2}, {"stars": 3.5}, {"stars": 5.5}]
	_ok(B.pick_human_diff(diffs, "Hard") == 2, "Partner Hard")
	_ok(B.pick_human_diff(diffs, "Insane") == 2, "Partner Insane (0,5 unter dem Band erlaubt)")
	_ok(B.pick_human_diff(diffs, "Normal") == 1, "Partner Normal")
	_ok(B.pick_human_diff(diffs, "Expert") == 3, "Partner Expert")
	_ok(B.pick_human_diff([{"stars": 9.0}, {"stars": -1.0}], "Hard") == -1, "kein Partner")


func _truth(beat: float = 500.0) -> Dictionary:
	var times: Array = []
	for k in 40:
		times.append(k * beat)
	return {"ok": true, "audio_name": "a.mp3", "reds": [{"time": 0.0, "beat_ms": beat, "meter": 4}],
			"t0": 0.0, "t1": 39 * beat, "kiai": [[4000.0, 8000.0]], "ref": "H",
			"diffs4k": [{"name": "H", "file": "h.osu", "times": times, "holds": [[1500.0, 1750.0], [3000.0, 3400.0]],
				"hold_share": 0.2, "stars": 3.4}]}


func _product(beat: float, shift: float = 0.0) -> Dictionary:
	var notes: Array = []
	for k in 40:
		notes.append({"t_ms": k * beat + shift, "col": k % 4, "end_ms": (k * beat + shift + 250.0) if k == 3 else -1.0})
	var caps := {"cols": true, "holds": true, "kiai": true, "profiles": B.PROFILES.duplicate()}
	return {"ok": true, "error": "", "segments": [_seg(shift, beat)], "alternatives": [], "confidence": 0.9,
			"kiai": [[4000.0 + shift, 8000.0 + shift]], "charts": {"Hard": {"ok": true, "error": "", "notes": notes}},
			"lint": {"Hard": 0}, "caps": caps, "stage_ms": {"grid": 10}}


func _test_record_and_report() -> void:
	var caps := {"cols": true, "holds": true, "kiai": true, "profiles": B.PROFILES.duplicate()}
	var good: Dictionary = B.song_record("good.osz", _truth(), _product(500.0), 3000.0, 20000.0)
	_ok(good.single and good.tempo_exact and good.downbeat_ok, "perfekt: Takt")
	_near(good.offset_ms, 0.0, "perfekt: Offset")
	_near(good.prof.Hard.prec, 1.0, "perfekt: Praezision")
	_near(good.prof.Hard.rec, 1.0, "perfekt: Treffer")
	_near(good.prof.Hard.hold, 1.0, "perfekt: Hold")
	_near(good.kiai_iou, 1.0, "perfekt: Kiai")
	_near(good.time_norm_ms, 3000.0 * 240000.0 / 30000.0, "Dauer auf 4 min (Songs unter 30 s wie 30 s)")
	_ok(not good.prof.has("Easy"), "ohne Partner kein Paar")
	var ag: Dictionary = B.aggregate([good])
	_near(ag.tempo_exact, 1.0, "aggregate Tempo")
	_near(B.objective(ag), 1.0, "Zielgroesse perfekt = 1")
	# 9 ms zu spaet: Tempo stimmt, Offset 9, Noten noch im Fenster
	var late: Dictionary = B.song_record("late.osz", _truth(), _product(500.0, 9.0), 3000.0, 20000.0)
	_near(late.offset_ms, 9.0, "9 ms spaet")
	_near(late.prof.Hard.prec, 1.0, "9 ms spaet: Noten zaehlen noch")
	# 20 ms zu spaet: keine Note trifft
	var later: Dictionary = B.song_record("later.osz", _truth(), _product(500.0, 20.0), 3000.0, 20000.0)
	_near(later.prof.Hard.prec, 0.0, "20 ms spaet: keine Note trifft")
	_ok(str(later.timing_note).begins_with("Versatz"), "Ursache Versatz")
	# halbes Tempo
	var half: Dictionary = B.song_record("half.osz", _truth(), _product(1000.0), 3000.0, 20000.0)
	_ok(not half.tempo_exact and not half.tempo_alt and half.diag_factor == 2.0 and not half.has("offset_ms"), "halbes Tempo")
	# 40 erzeugte Noten bis 39 s, die Menschen-Map endet bei 19,5 s: nur 20 liegen auf Menschen-Noten
	_near(half.prof.Hard.prec, 0.5, "halbes Tempo: Noten nach dem Ende der Menschen-Map zaehlen als falsch")
	_near(half.prof.Hard.rec, 0.5, "halbes Tempo: halbe Menschen-Noten")
	# Erzeugung fehlgeschlagen zaehlt als falsch, nicht als fehlend
	var fail: Dictionary = B.song_record("fail.osz", _truth(), {"ok": false, "error": "kaputt", "caps": caps}, 100.0, 20000.0)
	_ok(fail.tempo_exact == false and fail.prof.Hard.missing and fail.prof.Hard.offered, "Fehlschlag: Profil angeboten, fehlt")
	var all := [good, late, later, half, fail]
	ag = B.aggregate(all)
	_near(ag.tempo_exact, 3.0 / 5.0, "aggregate: 3 von 5 exakt")
	_ok(ag.n_fail == 1 and ag.n_exact == 3, "aggregate Zaehler")
	_near(ag.off_med, 9.0, "aggregate Offset-Median")
	_near(ag.per.Hard.prec, (1.0 + 1.0 + 0.0 + 0.5 + 0.0) / 5.0, "aggregate Praezision, Fehlschlag = 0")
	_ok(B.objective(ag) < 0.9, "Zielgroesse sinkt")
	# JSON hin und zurueck liefert dieselben Zahlen
	var back = JSON.parse_string(JSON.stringify({"recs": all}))
	var ag2: Dictionary = B.aggregate(back.recs)
	_near(ag2.per.Hard.rec, float(ag.per.Hard.rec), "JSON-Rundlauf")
	_near(ag2.off_p95, float(ag.off_p95), "JSON-Rundlauf p95")
	# Sterne und Lint
	good["stars"] = {"Hard": 3.4, "Easy": 2.5}
	good["lint"] = {"Hard": 0, "Easy": 3}
	ag = B.aggregate([good])
	_near(ag.stars_min, 0.0, "Sterne: schlechtestes Profil zaehlt")
	_near(ag.per.Hard.stars_share, 1.0, "Sterne Hard im Band")
	_ok(ag.lint_sum == 3 and ag.lint_charts == 2, "Lint-Summe")
	var rows: Array = B.target_rows(ag, caps)
	_ok(rows.size() == 14, "14 Zeilen der Ziel-Tabelle: %d" % rows.size())
	_ok(rows[0][4] == "ja" and rows[11][4] == "**nein**" and rows[12][4] == "**nein**", "Urteile")
	_ok(str(rows[4][4]).begins_with("nicht messbar"), "Tempowechsel ohne Songs = nicht messbar")
	var old_caps := {"cols": false, "holds": false, "kiai": false, "profiles": ["Easy", "Normal", "Hard"]}
	rows = B.target_rows(ag, old_caps)
	_ok(rows.size() == 14 and str(rows[9][3]).begins_with("nicht messbar") and str(rows[11][3]).begins_with("nicht messbar"), "alter Mapper: nicht messbar")
	# Aufteilung
	var n_test := 0
	for r in all:
		if r.split == "test":
			n_test += 1
	_ok(int(B.aggregate(all, "test").n) == n_test and int(B.aggregate(all, "tune").n) == all.size() - n_test, "aggregate je Menge")
	# Tempowechsel-Map
	var tt := _truth()
	tt.reds = [{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 10000.0, "beat_ms": 400.0, "meter": 4}]
	var multi: Dictionary = B.song_record("multi.osz", tt, _product(500.0), 3000.0, 20000.0)
	_ok(not multi.single and multi.seg_ok == false and not multi.has("tempo_exact"), "Tempowechsel-Map zaehlt nicht bei Tempo exakt")
	var text: String = B.render_report([{"name": "alt", "caps": old_caps, "recs": all + [multi], "info": {"x": "y"}}], "Protokoll")
	_ok(text.find("Ziel-Tabelle") > 0 and text.find("Schlechteste 20") > 0 and text.find("Protokoll") > 0 and text.find("OMEN") > 0, "Bericht gebaut")
	_ok(text.find("TETHRA") < 0, "kein alter Spielname im Bericht")
	text = B.render_report([{"name": "neu", "caps": caps, "recs": all + [multi], "info": {}}])
	_ok(text.find("Sterne außerhalb des Bands") > 0, "Bericht neu mit Sternen")


func _stub(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _test_stubs() -> void:
	var missing: Dictionary = B.load_mods("auto", {"grid": "res://gibt/es/nicht_grid.gd", "features": "res://gibt/es/nicht_f.gd",
			"chart": "res://gibt/es/nicht_c.gd", "mapper": "res://gibt/es/nicht_m.gd"})
	_ok(missing.name == "alt" and missing.missing.size() == 4, "fehlende Module: Adapter statt Absturz")
	_ok(B.load_mods("old").name == "alt", "--mapper old")
	var mods := {"name": "neu", "grid": _stub(STUB_GRID), "features": _stub(STUB_FEATURES), "chart": _stub(STUB_CHART),
			"mapper": null, "missing": ["mapper"], "caps": {"cols": true, "holds": true, "kiai": true, "profiles": B.PROFILES.duplicate()}}
	_ok(B._has_static(mods.chart, "lint") and not B._has_static(mods.grid, "lint"), "lint erkannt")
	var cache := {}
	var prod: Dictionary = B.product_from_stages(mods, PackedFloat32Array([0.0]), 22050, {}, B.PROFILES, cache)
	_ok(prod.ok and prod.segments.size() == 1 and prod.segments[0].beat_ms == 500.0, "Stufen-Weg mit Modulen")
	_ok(prod.alternatives == [2.0], "Alternativen als Faktoren")
	_ok(prod.kiai.size() == 1 and prod.kiai[0][0] == 4100.0 and prod.kiai[0][1] == 8100.0, "Kiai aus Abschnitten")
	_ok(prod.charts.size() == 5 and prod.charts.Hard.notes.size() == 20, "fuenf Profile")
	_ok(prod.lint.Expert == 2 and prod.lint.Hard == 0, "lint gezaehlt")
	_ok(cache.size() == 2, "Stufen im Speicher gehalten")
	var p2: Dictionary = B.product_from_stages(mods, PackedFloat32Array([0.0]), 22050, {"grid": {"lag": 5.0}, "post": {"offset_shift_ms": 2.0}}, ["Hard"], cache)
	_near(p2.segments[0].start_ms, 107.0, "params und Versatz wirken")
	_near(p2.charts.Hard.notes[0].t_ms, 107.0, "Versatz auf Noten")
	_near(p2.charts.Hard.notes[3].end_ms, 100.0 + 5.0 + 1500.0 + 250.0 + 2.0, "Versatz auf Hold-Ende")
	_ok(cache.size() == 3, "neuer Gitter-Stand, Features wiederverwendet")
	var text: String = B.osu_text(prod.segments, prod.charts.Hard.notes, "Hard")
	var parsed: Dictionary = OsuParser.parse(text)
	_ok(parsed.ok and parsed.beatmap.is_mania() and parsed.beatmap.hit_objects.size() == 20, "osu_text lesbar")
	if parsed.ok:
		var mn := parsed.beatmap.hit_objects[3] as ManiaNote
		_ok(mn != null and mn.column == 3 and mn.is_hold and mn.hold_end == 1850.0, "osu_text: Spalte und Hold")
	# Stellgroessen aus DEFAULTS
	var knobs: Array = T.knobs_from_defaults(mods.grid, "grid")
	var keys: Array = []
	for k in knobs:
		keys.append(k.key)
	keys.sort()
	_ok(keys == ["grid.lag", "grid.steps", "grid.win"], "Stellgroessen: %s" % str(keys))
	for k in knobs:
		if k.key == "grid.win":
			_near(k.min, 0.2, "Bereich win min")
			_near(k.max, 0.6, "Bereich win max")
		if k.key == "grid.steps":
			_ok(k.int and k.min == 2.0 and k.max == 6.0, "Bereich steps ganzzahlig")
		if k.key == "grid.lag":
			_ok(k.min == 0.0 and k.max == 20.0, "TUNE_RANGES gilt")
	# Abstimmung ueber den Stufen-Weg: Wahrheit liegt bei Start 107 ms -> lag 7 ist am besten
	var truth := _truth()
	truth.reds = [{"time": 107.0, "beat_ms": 500.0, "meter": 4}]
	var songs := [{"file": "s.osz", "truth": truth, "pcm": PackedFloat32Array([0.0]), "rate": 22050, "dur_ms": 20000.0, "cache": {}}]
	var res: Dictionary = T.coordinate_search([{"key": "grid.lag", "min": 0.0, "max": 20.0, "int": false}], {"grid": {"lag": 20.0}},
			func(p): return B.objective(T.evaluate(mods, songs, p)), 3, 5)
	_ok(res.score > res.start_score, "Suche verbessert die Zielgroesse")
	_ok(absf(float(res.params.grid.lag) - 7.0) <= 4.0, "Suche findet lag nahe 7: %s" % str(res.params.grid.lag))


func _test_old_adapter() -> void:
	# Klick-Spur 128 BPM, 30 s (wie tests/run_audio_map_tests.gd)
	var rate: int = AudioMapper.RATE
	var s := PackedFloat32Array()
	s.resize(30 * rate)
	var beat := 60000.0 / 128.0
	var k := 0
	while true:
		var i0 := int((350.0 + k * beat) * rate / 1000.0)
		if i0 >= s.size() - 300:
			break
		for j in 220:
			s[i0 + j] = (0.9 if k % 4 == 0 else 0.6) * sin(TAU * 1800.0 * j / rate) * exp(-j / 40.0)
		k += 1
	var mods: Dictionary = B.load_mods("old")
	var prod: Dictionary = B.product_from_stages(mods, s, rate, {}, B.PROFILES)
	_ok(prod.ok, "alter Mapper ueber Adapter laeuft")
	if not prod.ok:
		return
	_near(60000.0 / prod.segments[0].beat_ms, 128.0, "Adapter BPM", 0.1)
	_ok(prod.charts.Hard.ok and prod.charts.Hard.notes.size() > 20, "Adapter Hard-Noten")
	_ok(not prod.charts.Insane.ok and not prod.charts.Expert.ok, "Insane/Expert fehlen im alten Mapper")
	_ok(prod.lint.Hard == -1, "kein lint im alten Mapper")
	var truth := _truth(beat)
	truth.reds = [{"time": 350.0 - AudioMapper.OSU_LEAD_MS, "beat_ms": beat, "meter": 4}]
	truth.t0 = 350.0
	truth.t1 = 29000.0
	var rec: Dictionary = B.song_record("click.osz", truth, prod, 500.0, 30000.0)
	_ok(rec.tempo_exact, "Adapter: Tempo exakt gegen die Klick-Spur")
	_ok(rec.has("offset_ms") and absf(float(rec.offset_ms)) < 6.0, "Adapter: Offset < 6 ms: %s" % str(rec.get("offset_ms")))
	_ok(rec.prof.Hard.has("prec") and rec.prof.Insane.missing and not rec.prof.Insane.offered if rec.prof.has("Insane") else rec.prof.Hard.has("prec"), "Adapter: Profile")
	var rows: Array = B.target_rows(B.aggregate([rec]), mods.caps)
	_ok(str(rows[12][3]).begins_with("nicht messbar"), "Adapter: Regelverletzungen nicht messbar")


func _test_click() -> void:
	var beats: Array = B.beats_from_reds([{"time": 1000.0, "beat_ms": 500.0, "meter": 4}], 3000.0)
	_ok(beats.size() == 6 and beats[0][0] == 0.0 and beats[5][0] == 2500.0, "Schlaege ab 0: %s" % str(beats))
	_ok(beats[2][1] == true and beats[0][1] == false and beats[1][1] == false, "Taktanfang auf der roten Linie")
	beats = B.beats_from_reds([{"time": 0.0, "beat_ms": 500.0, "meter": 4}, {"time": 1000.0, "beat_ms": 250.0, "meter": 3}], 2000.0)
	_ok(beats.size() == 6 and beats[2][0] == 1000.0 and beats[5][0] == 1750.0 and beats[5][1] == true, "zwei Segmente: %s" % str(beats))
	var pcm: PackedFloat32Array = B.click_pcm([[1000.0, 2]], [[500.0, true]], 2000.0, 8000)
	_ok(pcm.size() == 16001, "Klick-Laenge")
	var e_note := 0.0
	var e_beat := 0.0
	var e_quiet := 0.0
	for i in 160:
		e_note += absf(pcm[8000 + i])
		e_beat += absf(pcm[4000 + i])
		e_quiet += absf(pcm[1000 + i])
	_ok(e_note > 1.0 and e_beat > 1.0 and e_quiet == 0.0, "Klick an Note und Schlag, sonst Stille")
	_ok(pcm[7999] == 0.0, "Klick beginnt genau an der Note")
	var path := "user://am_bench_test_click.wav"
	_ok(B.write_wav(path, pcm, 8000), "WAV geschrieben")
	var bytes := FileAccess.get_file_as_bytes(path)
	_ok(bytes.size() == 44 + pcm.size() * 2 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF", "WAV-Groesse")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_tune() -> void:
	var knobs := [{"key": "grid.a", "min": 0.0, "max": 10.0, "int": false}, {"key": "chart.b", "min": 1.0, "max": 9.0, "int": true}]
	var f := func(p): return -pow(float(p.grid.a) - 7.0, 2.0) - pow(float(p.chart.b) - 3.0, 2.0)
	var res: Dictionary = T.coordinate_search(knobs, {"grid": {"a": 0.0}, "chart": {"b": 9}}, f, 4, 5)
	_ok(absf(float(res.params.grid.a) - 7.0) < 0.7, "Suche a nahe 7: %s" % str(res.params.grid.a))
	_ok(int(res.params.chart.b) == 3, "Suche b = 3: %s" % str(res.params.chart.b))
	_ok(res.score > res.start_score and res.evals > 5 and res.log.size() >= 2, "Suche protokolliert")
	res = T.coordinate_search(knobs, {"grid": {"a": 7.0}, "chart": {"b": 3}}, f, 2, 5)
	_ok(float(res.params.grid.a) == 7.0 and res.score == res.start_score, "bester Startwert bleibt")
	var p := {}
	T.set_param(p, "features.x", 2.5)
	_ok(T.get_param(p, "features.x") == 2.5 and T.get_param(p, "grid.y", 4) == 4, "get/set_param")
	var ks: Array = T.parse_knobs("grid.x:0.1:0.9,chart.y:1:4:int,kaputt")
	_ok(ks.size() == 2 and ks[0].key == "grid.x" and ks[0].max == 0.9 and ks[1].int, "parse_knobs")
	var picked: Array = T.pick_files(["a.osz", "b.osz", "c.osz", "d.osz", "e.osz", "f.osz", "g.osz", "h.osz"], "tune", 3)
	_ok(picked.size() <= 3 and picked == T.pick_files(["h.osz", "g.osz", "f.osz", "e.osz", "d.osz", "c.osz", "b.osz", "a.osz"], "tune", 3), "pick_files fest")
