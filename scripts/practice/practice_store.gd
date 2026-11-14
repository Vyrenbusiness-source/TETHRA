class_name PracticeStore
extends RefCounted

## Uebungsmodus-Daten je Map+Diff (user://practice/<ReplayStore.key>.json):
##   runs:     Miss-Zeiten (Notenzeit, ms) der letzten RUNS_KEEP Laeufe (normale
##             Laeufe aus dem Urteils-Log der Fehler-Analyse + Uebungs-Schleifen)
##   sections: Statistik je Abschnitt "a-b" (ms): plays, clean, best_acc,
##             last_acc, best_rate (hoechstes fehlerfrei gespieltes Tempo)
## Nichts davon geht online. Fehlerstellen = Miss-Haeufungen (error_marks).

const DIR := "user://practice"
const RUNS_KEEP := 6
## Misses naeher als das gehoeren zu einer Fehlerstelle (ms).
const CLUSTER_MS := 2500.0
const MARKS_MAX := 8


static func _path(osz_path: String, version: String, dir: String = DIR) -> String:
	return "%s/%s.json" % [dir, ReplayStore.key(osz_path, version)]


static func load_data(osz_path: String, version: String, dir: String = DIR) -> Dictionary:
	var p := _path(osz_path, version, dir)
	var d = null
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			d = JSON.parse_string(f.get_as_text())
			f.close()
	if not (d is Dictionary):
		d = {}
	if not (d.get("runs") is Array):
		d["runs"] = []
	if not (d.get("sections") is Dictionary):
		d["sections"] = {}
	return d


static func _save(osz_path: String, version: String, d: Dictionary, dir: String = DIR) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(_path(osz_path, version, dir), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()


## Miss-Zeiten aus dem Urteils-Log (Vector4(Notenzeit, Spur, Quality, dt)).
static func misses_from_judge_log(jlog: Array) -> Array:
	var out := []
	for e in jlog:
		if e is Vector4 and int((e as Vector4).z) == ManiaCore.Quality.MISS:
			out.append(float((e as Vector4).x))
	return out


## Einen Lauf merken (kind "play" = normaler Lauf, "practice" = Schleife).
static func record_run(osz_path: String, version: String, misses: Array, kind: String = "play",
		dir: String = DIR) -> void:
	var d := load_data(osz_path, version, dir)
	var runs: Array = d.runs
	var ms := []
	for m in misses:
		ms.append(int(round(float(m))))
	runs.append({"kind": kind, "misses": ms, "date": Time.get_datetime_string_from_system()})
	while runs.size() > RUNS_KEEP:
		runs.pop_front()
	_save(osz_path, version, d, dir)


static func section_key(a_ms: float, b_ms: float) -> String:
	return "%d-%d" % [int(round(a_ms)), int(round(b_ms))]


## Ergebnis einer Uebungs-Schleife in die Abschnitts-Statistik.
static func record_section(osz_path: String, version: String, a_ms: float, b_ms: float,
		acc: float, misses: int, rate: float, dir: String = DIR) -> Dictionary:
	var d := load_data(osz_path, version, dir)
	var k := section_key(a_ms, b_ms)
	var st: Dictionary = d.sections.get(k, {"plays": 0, "clean": 0, "best_acc": 0.0,
			"last_acc": 0.0, "best_rate": 0.0})
	st.plays = int(st.plays) + 1
	st.last_acc = acc
	st.best_acc = maxf(float(st.best_acc), acc)
	if misses == 0:
		st.clean = int(st.clean) + 1
		st.best_rate = maxf(float(st.best_rate), rate)
	d.sections[k] = st
	_save(osz_path, version, d, dir)
	return st


static func section_stats(osz_path: String, version: String, a_ms: float, b_ms: float,
		dir: String = DIR) -> Dictionary:
	return load_data(osz_path, version, dir).sections.get(section_key(a_ms, b_ms), {})


## Fehlerstellen der letzten Laeufe: Miss-Haeufungen {t0, t1, n, runs},
## die MARKS_MAX dichtesten, nach Zeit sortiert. Eine Stelle braucht mindestens
## zwei Misses (im selben oder in verschiedenen Laeufen); Einzelfehler fallen weg.
static func error_marks(runs: Array, max_n: int = MARKS_MAX) -> Array:
	var pts: Array = []
	for ri in runs.size():
		var r = runs[ri]
		if not (r is Dictionary):
			continue
		for m in r.get("misses", []):
			pts.append([float(m), ri])
	pts.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var clusters: Array = []
	var i := 0
	while i < pts.size():
		var t0: float = pts[i][0]
		var t1 := t0
		var seen := {}
		var n := 0
		while i < pts.size() and float(pts[i][0]) - t1 <= CLUSTER_MS:
			t1 = float(pts[i][0])
			seen[pts[i][1]] = true
			n += 1
			i += 1
		if n >= 2:
			clusters.append({"t0": t0, "t1": t1, "n": n, "runs": seen.size()})
	clusters.sort_custom(func(x, y):
		if int(x.n) != int(y.n):
			return int(x.n) > int(y.n)
		return float(x.t0) < float(y.t0))
	if clusters.size() > max_n:
		clusters.resize(max_n)
	clusters.sort_custom(func(x, y): return float(x.t0) < float(y.t0))
	return clusters


## A/B-Vorschlag um eine Fehlerstelle: etwas Anlauf davor, etwas danach.
static func range_for_mark(mark: Dictionary, song_end_ms: float) -> Vector2:
	var a := maxf(float(mark.t0) - 1500.0, 0.0)
	var b := minf(float(mark.t1) + 1500.0, song_end_ms)
	return Vector2(a, maxf(b, a + 1000.0))
