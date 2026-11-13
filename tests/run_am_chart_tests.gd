extends SceneTree

## Headless-Tests und Messung fuer AmChart (OMEN Auto-Mapper 4K, Notensetzer).
##   Tests:    Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_chart_tests.gd
##   Messung:  ... --script res://tests/run_am_chart_tests.gd -- --measure <maps> <n> [--learn]
## --measure liest alle 4K-Diffs aus <maps> (ein Prozess), vergleicht erzeugte Muster je Sterne-Band
## mit den Menschen-Maps und prueft die Sterne ueber rosu-pp (StarService, ein Aufruf).
## --learn schreibt zusaetzlich data/automap/patterns.json (nur Statistik, keine Maps).

const BAND_EDGES := [2.0, 2.9, 3.9, 4.9, 6.5]   # Grenzen zwischen den Profil-Baendern (rosu-Sterne)
const TOP4 := 60
const TOP8 := 40

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mi := args.find("--measure")
	if mi >= 0 and args.size() > mi + 2:
		_measure(args[mi + 1], int(args[mi + 2]), args.has("--learn"))
		quit(0)
		return
	print("=== AmChart-Tests ===")
	_test_errors()
	_test_synthetic()
	_test_pitch_direction()
	_test_roles()
	_test_tempo_change()
	_test_lint_detects()
	_test_stars_and_stats()
	print("=== %s ===" % ("ALLE OK" if _failed == 0 else "%d FEHLER" % _failed))
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Eingaben
# ---------------------------------------------------------------------------

func _grid_one(start_ms: float, beat_ms: float) -> Dictionary:
	return {"ok": true, "error": "", "confidence": 1.0, "alternatives": [],
			"segments": [{"start_ms": start_ms, "beat_ms": beat_ms, "meter": 4, "downbeat_ms": start_ms}]}


func _ev(t: float, kind: String, strength: float, pitch: float = -1.0, sustain: float = 0.0) -> Dictionary:
	return {"t_ms": t + 23.0, "strength": strength, "kind": kind, "pitch": pitch, "sustain_ms": sustain}


## Synthetischer Song: 150 BPM, 64 Takte. Intro (gehaltene Toene), Vers (Motiv alle 2 Takte),
## Aufbau, Refrain (Kiai, dicht), Pause (keine Ereignisse), Vers 2, Outro.
func _synthetic() -> Dictionary:
	var beat := 400.0
	var start := 1000.0
	var bar := beat * 4.0
	var ev: Array = []
	var secs := [[0, 8, "intro", 0.25, "tonal"], [8, 24, "verse", 0.5, "vocal"], [24, 28, "build", 0.65, "drums"],
			[28, 44, "chorus", 0.95, "drums"], [44, 48, "break", 0.1, "tonal"], [48, 56, "verse", 0.5, "tonal"],
			[56, 64, "outro", 0.3, "tonal"]]
	var sections: Array = []
	var mel := [0.2, 0.4, 0.6, 0.8, 0.6, 0.4, 0.2, 0.4, 0.5, 0.7, 0.9, 0.7, 0.5, 0.3, 0.1, 0.3]
	var cho := [0.1, 0.3, 0.5, 0.3, 0.6, 0.8, 0.6, 0.4, 0.9, 0.7, 0.5, 0.7, 0.4, 0.2, 0.4, 0.6]
	for s in secs:
		var kind: String = s[2]
		sections.append({"start_ms": start + float(s[0]) * bar if int(s[0]) > 0 else 0.0, "end_ms": start + float(s[1]) * bar,
				"intensity": s[3], "kind": kind, "kiai": kind == "chorus", "lead": s[4]})
		for b in range(int(s[0]), int(s[1])):
			var t0 := start + float(b) * bar
			var jit := float((b * 7) % 5) - 2.0     # +-2 ms Unruhe
			if kind == "break":
				continue
			if kind == "intro" or kind == "outro":
				ev.append(_ev(t0 + jit, "tonal", 0.6, 0.2 + 0.2 * float(b % 4), beat * 2.0))
				ev.append(_ev(t0 + beat * 2.0, "bass", 0.45, 0.3))
				ev.append(_ev(t0 + beat * 3.0, "tonal", 0.4, 0.5 + 0.1 * float(b % 2)))
				continue
			for q in 4:
				var tb := t0 + float(q) * beat
				ev.append(_ev(tb + jit, "kick" if q % 2 == 0 else "snare", 0.8 if q % 2 == 0 else 0.75))
				ev.append(_ev(tb, "bass", 0.5, 0.2 + 0.15 * float(b % 4)))
			if kind == "verse":
				for h in 8:
					ev.append(_ev(t0 + float(h) * beat * 0.5 - jit, "tonal", 0.55, mel[(b % 2) * 8 + h]))
					ev.append(_ev(t0 + float(h) * beat * 0.5, "hat", 0.35))
				if b % 2 == 1:
					ev.append(_ev(t0, "vocal", 0.7, 0.6, beat * 1.5))
			else:
				for h in 16:
					ev.append(_ev(t0 + float(h) * beat * 0.25 + jit, "tonal", 0.6, cho[h]))
					ev.append(_ev(t0 + float(h) * beat * 0.25, "hat", 0.45))
				if kind == "chorus":
					for h in 16:
						ev.append(_ev(t0 + (float(h) + 0.5) * beat * 0.25, "hat", 0.3))
					if b % 4 == 0:
						ev.append(_ev(t0, "hat", 0.95))
					if b % 4 == 2:
						ev.append(_ev(t0 + beat * 2.0, "vocal", 0.8, 0.7, beat * 2.0))
	ev.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t_ms"]) < float(b["t_ms"]))
	var feats := {"ok": true, "error": "", "duration_ms": start + 64.0 * bar + 2000.0, "events": ev,
			"energy": PackedFloat32Array(), "frame_ms": 10.0, "sections": sections}
	return {"features": feats, "grid": _grid_one(start, beat), "start": start, "beat": beat, "bar": bar}


## Eigene Gitterpruefung (unabhaengig von AmChart): Tick in 1/24 Schlag oder -1.
func _own_tick(grid: Dictionary, t: float) -> int:
	var segs: Array = grid["segments"]
	var si := 0
	for i in segs.size():
		if float(segs[i]["start_ms"]) <= t + 0.001:
			si = i
	var x := (t - float(segs[si]["start_ms"])) / float(segs[si]["beat_ms"]) * 24.0
	if absf(x - round(x)) > 0.001:
		return -1
	return int(round(x))


func _times(notes: Array) -> Dictionary:
	var d := {}
	for nt: Dictionary in notes:
		d[int(round(float(nt["t_ms"]) * 10.0))] = true
	return d


func _cols_in(notes: Array, from_ms: float, to_ms: float) -> Array:
	var out: Array = []
	for nt: Dictionary in notes:
		var t: float = nt["t_ms"]
		if t >= from_ms - 1.0 and t < to_ms - 1.0:
			out.append([int(round(t - from_ms)), int(nt["col"])])
	return out


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_errors() -> void:
	print("-- Fehlerfaelle")
	var s := _synthetic()
	_check(not AmChart.build(s["features"], s["grid"], "Zen")["ok"], "unbekanntes Profil -> ok=false")
	_check(not AmChart.build(s["features"], {"segments": []}, "Hard")["ok"], "leeres Gitter -> ok=false")
	_check(not AmChart.build({"events": []}, s["grid"], "Hard")["ok"], "keine Ereignisse -> ok=false")
	_check(AmChart.PROFILES == ["Easy", "Normal", "Hard", "Insane", "Expert"], "PROFILES wie Spec")


func _test_synthetic() -> void:
	print("-- synthetischer Song, alle Profile")
	var s := _synthetic()
	var grid: Dictionary = s["grid"]
	var t0 := Time.get_ticks_msec()
	var all := AmChart.build_all(s["features"], grid)
	print("     build_all: %d ms" % (Time.get_ticks_msec() - t0))
	var unit_of := {"Easy": [12], "Normal": [12], "Hard": [6], "Insane": [3], "Expert": [3, 4]}
	var start: float = s["start"]
	var bar: float = s["bar"]
	var prev_times := {}
	for prof: String in AmChart.PROFILES:
		var res: Dictionary = all[prof]
		var notes: Array = res["notes"]
		var st: Dictionary = res["stats"]
		print("     %s: %d Noten, Sterne~%.2f, nps %.2f, Holds %d, Akkorde %d, Jack %d, Motive %d/%d, capped=%s" % [
				prof, notes.size(), st["stars_est"], st["nps_avg"], st["holds"], st["chords"], st["max_jack"],
				st["motif_reused"], st["motif_bars"], st["capped"]])
		_check(res["ok"] and notes.size() > 20, "%s: ok und Noten vorhanden" % prof)
		var viol := AmChart.lint(notes, grid, prof)
		_check(viol.is_empty(), "%s: lint = 0 Verstoesse%s" % [prof, "" if viol.is_empty() else " (" + viol[0] + ")"])
		# Gitter-Treue, sortiert, Spalten, Hold-Ende
		var on_grid := true
		var sorted := true
		var pt := -1e9
		for nt: Dictionary in notes:
			var tick := _own_tick(grid, float(nt["t_ms"]))
			var okk := false
			for u: int in unit_of[prof]:
				if tick >= 0 and tick % u == 0:
					okk = true
			if not okk:
				on_grid = false
			if float(nt["end_ms"]) >= 0.0 and _own_tick(grid, float(nt["end_ms"])) < 0:
				on_grid = false
			if float(nt["t_ms"]) < pt:
				sorted = false
			pt = nt["t_ms"]
		_check(on_grid, "%s: alle Noten und Hold-Enden exakt auf dem Gitter" % prof)
		_check(sorted, "%s: Noten sortiert" % prof)
		# Pausen bleiben Pausen (Takte 44..48 ohne Ereignisse)
		var in_break := 0
		for nt: Dictionary in notes:
			if float(nt["t_ms"]) > start + 44.0 * bar + 1.0 and float(nt["t_ms"]) < start + 48.0 * bar - 1.0:
				in_break += 1
		_check(in_break == 0, "%s: keine Noten in der Pause" % prof)
		# Balance
		var left := 0
		for nt: Dictionary in notes:
			if int(nt["col"]) < 2:
				left += 1
		var share := float(left) / float(maxi(notes.size(), 1))
		_check(share >= 0.40 and share <= 0.60, "%s: Hand-Balance %.1f %% links" % [prof, share * 100.0])
		# Auswahl-Eigenschaft: schwereres Profil enthaelt alle Stellen des leichteren
		var times := _times(notes)
		if not prev_times.is_empty():
			var missing := 0
			for k in prev_times:
				if not times.has(k):
					missing += 1
			_check(missing == 0, "%s enthaelt alle Stellen des leichteren Profils (fehlend: %d)" % [prof, missing])
		prev_times = times
		# einzelner build() liefert dasselbe wie build_all (deterministisch)
		if prof == "Hard" or prof == "Easy":
			var single := AmChart.build(s["features"], grid, prof)
			_check(JSON.stringify(single["notes"]) == JSON.stringify(notes), "%s: build() == build_all(), deterministisch" % prof)
	# Dichte folgt Intensitaet: Refrain dichter als Intro
	var hard: Array = all["Hard"]["notes"]
	var n_intro := _cols_in(hard, start, start + 8.0 * bar).size()
	var n_cho := _cols_in(hard, start + 28.0 * bar, start + 36.0 * bar).size()
	_check(n_cho > n_intro * 2, "Hard: Refrain dichter als Intro (%d gegen %d Noten in 8 Takten)" % [n_cho, n_intro])
	# Wiederholung: Vers-Takte b und b+2 tragen dieselbe Musik -> dasselbe Muster (oder gespiegelt)
	for prof: String in ["Normal", "Hard"]:
		var notes: Array = all[prof]["notes"]
		var same_rhythm := 0
		var same_cols := 0
		for b in range(9, 22):
			var a := _cols_in(notes, start + float(b) * bar, start + float(b + 1) * bar)
			var c := _cols_in(notes, start + float(b + 2) * bar, start + float(b + 3) * bar)
			if a.size() < 3 or a.size() != c.size():
				continue
			var rhythm := true
			var eq := true
			var mir := true
			for i in a.size():
				if a[i][0] != c[i][0]:
					rhythm = false
				if a[i][1] != c[i][1]:
					eq = false
				if a[i][1] != 3 - int(c[a.size() - 1 - i][1]) and a[i][1] != 3 - int(c[i][1]):
					mir = false
			if rhythm:
				same_rhythm += 1
				if eq or mir:
					same_cols += 1
		_check(same_rhythm >= 3 and same_cols * 10 >= same_rhythm * 7,
				"%s: wiederholte Takte gleich gesetzt (%d von %d)" % [prof, same_cols, same_rhythm])
	# Akzente -> Akkorde: Akkorde liegen ueberwiegend auf dem Schlag
	var rows_on := 0
	var chord_on := 0
	var chord_all := 0
	var rows_all := 0
	var i := 0
	while i < hard.size():
		var j := i
		while j < hard.size() and absf(float(hard[j]["t_ms"]) - float(hard[i]["t_ms"])) < 1.0:
			j += 1
		var onbeat := _own_tick(grid, float(hard[i]["t_ms"])) % 24 == 0
		rows_all += 1
		if onbeat:
			rows_on += 1
		if j - i >= 2:
			chord_all += 1
			if onbeat:
				chord_on += 1
		i = j
	_check(chord_all > 0 and float(chord_on) / float(chord_all) > float(rows_on) / float(rows_all),
			"Hard: Akkorde bevorzugt auf Akzenten (%d von %d auf dem Schlag)" % [chord_on, chord_all])
	# Holds: gehaltene Toene werden Holds; Easy ohne Note waehrend eines Holds (lint deckt es ab)
	_check(int(all["Hard"]["stats"]["holds"]) > 0, "Hard: gehaltene Toene werden Holds (%d)" % int(all["Hard"]["stats"]["holds"]))
	var cnt: Array = []
	for prof: String in AmChart.PROFILES:
		cnt.append(all[prof]["notes"].size())
	_check(cnt[0] < cnt[1] and cnt[1] < cnt[2] and cnt[2] <= cnt[3] and cnt[3] <= cnt[4], "Notenzahl steigt mit dem Profil %s" % str(cnt))


func _test_pitch_direction() -> void:
	print("-- Tonhoehe -> Spaltenrichtung")
	var beat := 500.0
	var ev: Array = []
	var p := 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 240:
		var step := 0.12 if rng.randf() < 0.5 else -0.12
		if p + step > 0.95 or p + step < 0.05:
			step = -step
		p += step
		ev.append(_ev(1000.0 + float(i) * beat * 0.5, "tonal", 0.6, p))
	var feats := {"events": ev, "sections": [{"start_ms": 0.0, "end_ms": 200000.0, "intensity": 0.5,
			"kind": "verse", "kiai": false, "lead": "tonal"}]}
	var grid := _grid_one(1000.0, beat)
	# weites Band: alle Stellen bleiben, damit die Richtung an jeder Note pruefbar ist
	var res := AmChart.build(feats, grid, "Normal", {"star_bands": {"Normal": [0.0, 9.0]}, "star_tol": 9.0})
	var notes: Array = res["notes"]
	var by_t := {}
	for e: Dictionary in ev:
		by_t[int(round(float(e["t_ms"]) - 23.0))] = float(e["pitch"])
	var agree := 0
	var oppose := 0
	var total := 0
	for i in range(1, notes.size()):
		var a: Dictionary = notes[i - 1]
		var b: Dictionary = notes[i]
		var ka := int(round(float(a["t_ms"])))
		var kb := int(round(float(b["t_ms"])))
		if ka == kb or not by_t.has(ka) or not by_t.has(kb):
			continue
		var dp: float = float(by_t[kb]) - float(by_t[ka])
		var dc := int(b["col"]) - int(a["col"])
		total += 1
		if dp * float(dc) > 0.0:
			agree += 1
		elif dp * float(dc) < 0.0:
			oppose += 1
	_check(AmChart.lint(notes, grid, "Normal").is_empty(), "Melodie: lint = 0")
	_check(total > 100 and agree >= oppose * 3 and agree * 10 >= total * 6,
			"Spalte folgt der Tonhoehe: %d gleich, %d gegen, %d Schritte" % [agree, oppose, total])


func _test_roles() -> void:
	print("-- Kick/Snare: feste Rollen")
	var beat := 480.0
	var ev: Array = []
	for i in 160:
		ev.append(_ev(800.0 + float(i) * beat, "kick" if i % 2 == 0 else "snare", 0.8))
	var feats := {"events": ev, "sections": [{"start_ms": 0.0, "end_ms": 100000.0, "intensity": 0.6,
			"kind": "verse", "kiai": false, "lead": "drums"}]}
	var grid := _grid_one(800.0, beat)
	var res := AmChart.build(feats, grid, "Easy", {"star_bands": {"Easy": [0.0, 9.0]}, "star_tol": 9.0})
	var kick := [0, 0, 0, 0]
	var snare := [0, 0, 0, 0]
	for nt: Dictionary in res["notes"]:
		var idx := int(round((float(nt["t_ms"]) - 800.0) / beat))
		if idx % 2 == 0:
			kick[int(nt["col"])] += 1
		else:
			snare[int(nt["col"])] += 1
	var km: int = kick.max()
	var sm: int = snare.max()
	var kn: int = kick[0] + kick[1] + kick[2] + kick[3]
	var sn: int = snare[0] + snare[1] + snare[2] + snare[3]
	_check(kn > 30 and km * 10 >= kn * 6, "Kick liegt ueberwiegend in einer Spalte %s" % str(kick))
	_check(sn > 30 and sm * 10 >= sn * 6, "Snare liegt ueberwiegend in einer Spalte %s" % str(snare))
	_check(kick.find(km) != snare.find(sm), "Kick und Snare in verschiedenen Spalten")
	_check(AmChart.lint(res["notes"], grid, "Easy").is_empty(), "Schlagzeug: lint = 0")


func _test_tempo_change() -> void:
	print("-- Tempowechsel (zwei Segmente)")
	var grid := {"segments": [
			{"start_ms": 500.0, "beat_ms": 500.0, "meter": 4, "downbeat_ms": 500.0},
			{"start_ms": 30500.0, "beat_ms": 375.0, "meter": 4, "downbeat_ms": 30500.0}]}
	var ev: Array = []
	for i in 240:
		ev.append(_ev(500.0 + float(i) * 125.0, "tonal" if i % 2 == 1 else ("kick" if i % 8 == 0 else "hat"),
				0.5 + 0.3 * float(i % 4 == 0), 0.1 + 0.2 * float(i % 5), 750.0 if i % 16 == 4 else 0.0))
	for i in 480:
		ev.append(_ev(30500.0 + float(i) * 93.75, "tonal" if i % 2 == 1 else ("snare" if i % 8 == 4 else "hat"),
				0.5 + 0.3 * float(i % 4 == 0), 0.1 + 0.2 * float(i % 4)))
	var feats := {"events": ev, "sections": []}
	var all := AmChart.build_all(feats, grid)
	for prof: String in AmChart.PROFILES:
		var notes: Array = all[prof]["notes"]
		var viol := AmChart.lint(notes, grid, prof)
		var on := true
		for nt: Dictionary in notes:
			if _own_tick(grid, float(nt["t_ms"])) < 0:
				on = false
		_check(viol.is_empty() and on and notes.size() > 10, "%s: lint = 0 und auf dem Gitter ueber den Tempowechsel (%d Noten)%s" % [
				prof, notes.size(), "" if viol.is_empty() else " " + viol[0]])


func _n(t: float, col: int, e: float = -1.0) -> Dictionary:
	return {"t_ms": t, "col": col, "end_ms": e}


func _test_lint_detects() -> void:
	print("-- lint erkennt Verstoesse")
	var grid := _grid_one(0.0, 400.0)
	var ok_notes: Array = []
	for i in 24:
		ok_notes.append(_n(float(i) * 400.0, [0, 2, 1, 3][i % 4]))
	_check(AmChart.lint(ok_notes, grid, "Easy").is_empty(), "saubere Easy-Folge: 0")
	_check(not AmChart.lint([_n(0.0, 0), _n(137.0, 1)], grid, "Hard").is_empty(), "neben dem Gitter")
	_check(not AmChart.lint([_n(0.0, 0), _n(100.0, 1)], grid, "Normal").is_empty(), "1/4 in Normal")
	_check(not AmChart.lint([_n(0.0, 0), _n(0.0, 1)], grid, "Easy").is_empty(), "Akkord in Easy")
	_check(not AmChart.lint([_n(0.0, 0), _n(0.0, 1), _n(0.0, 2)], grid, "Hard").is_empty(), "3er-Akkord in Hard")
	_check(not AmChart.lint([_n(0.0, 0), _n(100.0, 0), _n(200.0, 0)], grid, "Hard").is_empty(), "Jack 3 in Hard")
	_check(AmChart.lint([_n(0.0, 0), _n(100.0, 0), _n(200.0, 1)], grid, "Hard").is_empty(), "Jack 2 in Hard erlaubt")
	_check(not AmChart.lint([_n(0.0, 0), _n(200.0, 0)], grid, "Easy").is_empty(), "Mindestabstand Easy")
	_check(not AmChart.lint([_n(0.0, 0, 1200.0), _n(400.0, 2)], grid, "Easy").is_empty(), "Note waehrend Hold in Easy")
	_check(AmChart.lint([_n(0.0, 0, 1200.0), _n(400.0, 2)], grid, "Hard").is_empty(), "Note waehrend Hold in Hard erlaubt")
	_check(not AmChart.lint([_n(0.0, 0, 1230.0)], grid, "Hard").is_empty(), "Hold-Ende neben dem Gitter")
	_check(not AmChart.lint([_n(0.0, 0, 800.0), _n(400.0, 0)], grid, "Hard").is_empty(), "Note im Hold der eigenen Spalte")
	var lop: Array = []
	for i in 30:
		lop.append(_n(float(i) * 400.0, i % 2))
	_check(not AmChart.lint(lop, grid, "Normal").is_empty(), "Hand-Balance 100 % links")
	_check(not AmChart.lint([_n(0.0, 0), _n(0.0, 1), _n(0.0, 2), _n(0.0, 3), _n(400.0, 0)], grid, "Expert").is_empty(), "4er-Akkord nicht am Schluss")
	_check(AmChart.lint([_n(0.0, 0), _n(400.0, 0), _n(400.0, 1), _n(400.0, 2), _n(400.0, 3)], grid, "Expert").is_empty(), "4er-Schlussakkord erlaubt")
	var burst: Array = []
	for i in 14:
		burst.append(_n(float(i) * 50.0, [0, 2, 1, 3][i % 4]))
	_check(not AmChart.lint(burst, grid, "Insane").is_empty(), "zu lange 1/8-Folge in Insane")


func _test_stars_and_stats() -> void:
	print("-- Sterne und Statistik")
	var s := _synthetic()
	var all := AmChart.build_all(s["features"], s["grid"])
	for prof: String in ["Normal", "Hard"]:
		var st: Dictionary = all[prof]["stats"]
		var band: Array = AmChart.DEFAULTS["star_bands"][prof]
		_check(float(st["stars_est"]) >= float(band[0]) and float(st["stars_est"]) <= float(band[1]) and not st["capped"],
				"%s: Sterne-Schaetzung %.2f im Band" % [prof, st["stars_est"]])
	for prof: String in AmChart.PROFILES:
		var st: Dictionary = all[prof]["stats"]
		var band: Array = AmChart.DEFAULTS["star_bands"][prof]
		var inside := float(st["stars_est"]) >= float(band[0]) and float(st["stars_est"]) <= float(band[1])
		_check(inside != bool(st["capped"]), "%s: capped-Feld stimmt mit dem Band (%.2f, capped=%s)" % [prof, st["stars_est"], st["capped"]])
		for key: String in ["nps_avg", "nps_peak", "holds", "chords", "max_jack"]:
			if not st.has(key):
				_check(false, "%s: stats.%s fehlt" % [prof, key])
	# Schaetzung waechst mit der Dichte
	var slow: Array = []
	var fast: Array = []
	for i in 200:
		slow.append(_n(float(i) * 400.0, [0, 2, 1, 3][i % 4]))
		fast.append(_n(float(i) * 100.0, [0, 2, 1, 3][i % 4]))
	_check(AmChart.estimate_stars(fast) > AmChart.estimate_stars(slow) * 1.5, "estimate_stars: dichter = mehr Sterne (%.2f gegen %.2f)" % [
			AmChart.estimate_stars(fast), AmChart.estimate_stars(slow)])
	var ps := AmChart.pattern_stats(all["Hard"]["notes"], s["grid"])
	_check(int(ps["notes"]) == all["Hard"]["notes"].size() and int(ps["rows"]) > 0, "pattern_stats zaehlt Noten und Zeilen")
	# eigener Mustersatz ueber params: nur Spalte 0/3-Wechsel gelernt -> Setzer folgt
	var big: Array = []
	for g in 4:
		var arr: Array = []
		arr.resize(256)
		arr.fill(0.0)
		arr[1 * 16 + 8] = 0.5
		arr[8 * 16 + 1] = 0.5
		big.append(arr)
	var uni: Array = []
	uni.resize(16)
	uni.fill(0.0)
	uni[1] = 0.5
	uni[8] = 0.5
	var pats := {"bands": {"Easy": {"big": big, "uni": uni, "chord_share": 0.0, "hold_share_p90": 0.0}}}
	var ev: Array = []
	for i in 80:
		ev.append({"t_ms": 23.0 + float(i) * 500.0, "strength": 0.6, "kind": "other", "pitch": -1.0, "sustain_ms": 0.0})
	var res := AmChart.build({"events": ev, "sections": []}, _grid_one(0.0, 500.0), "Easy",
			{"patterns": pats, "star_bands": {"Easy": [0.0, 9.0]}, "star_tol": 9.0})
	var outer := 0
	for nt: Dictionary in res["notes"]:
		if int(nt["col"]) == 0 or int(nt["col"]) == 3:
			outer += 1
	_check(res["notes"].size() >= 70 and outer * 10 >= res["notes"].size() * 9,
			"Setzer nutzt die Mustertabellen (%d von %d Noten nach gelerntem Muster)" % [outer, res["notes"].size()])


# ---------------------------------------------------------------------------
# Messung ueber maps/
# ---------------------------------------------------------------------------

func _band_of(stars: float) -> int:
	for i in BAND_EDGES.size():
		if stars < float(BAND_EDGES[i]):
			return i
	return -1


func _agg_new() -> Dictionary:
	var big: Array = []
	for g in 4:
		var z: Array = []
		z.resize(256)
		z.fill(0)
		big.append(z)
	var uni: Array = []
	uni.resize(16)
	uni.fill(0)
	return {"maps": 0, "notes": 0, "rows": 0, "sizes": [0, 0, 0, 0, 0], "uni": uni, "big": big, "gaps": [0, 0, 0, 0],
			"holds": 0, "hold_beats": 0.0, "left": 0, "right": 0, "moves": [0, 0, 0, 0],
			"jack_runs": [0, 0, 0, 0, 0, 0, 0, 0, 0], "jack_notes": 0, "g4": {}, "g8": {},
			"hold_shares": [], "nps": [], "peaks": [], "kiai": []}


func _agg_add(a: Dictionary, st: Dictionary) -> void:
	a["maps"] += 1
	for key: String in ["notes", "rows", "holds", "hold_beats", "left", "right", "jack_notes"]:
		a[key] += st[key]
	for key: String in ["sizes", "uni", "gaps", "moves", "jack_runs"]:
		for i in a[key].size():
			a[key][i] += st[key][i]
	for g in 4:
		var src: Array = st["big"][g]
		var dst: Array = a["big"][g]
		for i in 256:
			if src[i] != 0:
				dst[i] += src[i]
	for key: String in ["g4", "g8"]:
		var d: Dictionary = a[key]
		for k in st[key]:
			d[k] = int(d.get(k, 0)) + int(st[key][k])
	a["hold_shares"].append(float(st["holds"]) / float(maxi(st["notes"], 1)))
	a["nps"].append(float(st["notes"]) / float(st["dur_s"]))
	a["peaks"].append(float(st["nps_peak"]))


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


func _quant(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(floor(q * float(b.size()))), 0, b.size() - 1)])


func _top(d: Dictionary, k: int) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(x, y) -> bool: return int(d[x]) > int(d[y]) if int(d[x]) != int(d[y]) else int(x) < int(y))
	return keys.slice(0, k)


## Kennzahlen eines Bands (Mensch oder erzeugt) fuer den Vergleich.
func _summ(a: Dictionary) -> Dictionary:
	var rows := float(maxi(a["rows"], 1))
	var notes := float(maxi(a["notes"], 1))
	var mv := float(maxi(a["moves"][0] + a["moves"][1] + a["moves"][2] + a["moves"][3], 1))
	var gp := float(maxi(a["gaps"][0] + a["gaps"][1] + a["gaps"][2] + a["gaps"][3], 1))
	return {"maps": a["maps"], "same": a["moves"][0] / mv, "adjacent": a["moves"][1] / mv, "wide": (a["moves"][2] + a["moves"][3]) / mv,
			"chord": float(a["sizes"][2] + a["sizes"][3] + a["sizes"][4]) / rows,
			"chord3": float(a["sizes"][3] + a["sizes"][4]) / rows, "jack": float(a["jack_notes"]) / notes,
			"hold": float(a["holds"]) / notes, "hold_beats": float(a["hold_beats"]) / float(maxi(a["holds"], 1)),
			"nps": _mean(a["nps"]), "peak": _mean(a["peaks"]), "left": float(a["left"]) / float(maxi(a["left"] + a["right"], 1)),
			"g8th": a["gaps"][0] / gp, "g4th": a["gaps"][1] / gp, "ghalf": a["gaps"][2] / gp}


## Aehnlichkeit der Zeilen-Uebergaenge (0..1): Schnittmenge der Verteilungen je Abstandsklasse,
## gewichtet mit dem Anteil der Klasse im erzeugten Material.
func _bigram_sim(h: Dictionary, g: Dictionary) -> float:
	var total := 0.0
	var wsum := 0.0
	for c in 4:
		var hs := 0.0
		var gs := 0.0
		for i in 256:
			hs += float(h["big"][c][i])
			gs += float(g["big"][c][i])
		if hs <= 0.0 or gs <= 0.0:
			continue
		var inter := 0.0
		for i in 256:
			inter += minf(float(h["big"][c][i]) / hs, float(g["big"][c][i]) / gs)
		total += inter * gs
		wsum += gs
	return total / wsum if wsum > 0.0 else 0.0


## Anteil der 4er-Muster von `a`, die unter den haeufigsten TOP4 Mustern der Menschen liegen.
func _top_share(a: Dictionary, top: Array) -> float:
	var s := 0
	var t := 0
	for k in a["g4"]:
		t += int(a["g4"][k])
		if top.has(k):
			s += int(a["g4"][k])
	return float(s) / float(maxi(t, 1))


func _notes_of(bm: Beatmap) -> Array:
	var out: Array = []
	for h in bm.hit_objects:
		var mn := h as ManiaNote
		if mn == null:
			continue
		out.append({"t_ms": mn.time, "col": clampi(mn.column, 0, 3), "end_ms": mn.hold_end if mn.is_hold else -1.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t_ms"]) < float(b["t_ms"]) if float(a["t_ms"]) != float(b["t_ms"]) else int(a["col"]) < int(b["col"]))
	return out


func _grid_of(bm: Beatmap) -> Dictionary:
	var segs: Array = []
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 1.0:
			segs.append({"start_ms": tp.time, "beat_ms": tp.beat_length, "meter": maxi(tp.meter, 1), "downbeat_ms": tp.time})
	return {"ok": true, "segments": segs, "confidence": 1.0, "alternatives": []}


## features aus einer Menschen-Map: Notenzeiten als Ereignisse, Spalte als Tonhoehe, Hold als
## gehaltener Ton, Akkord als Akzent, Kiai als Abschnitt.
func _features_of(notes: Array, kiai: Array) -> Dictionary:
	var ev: Array = []
	var i := 0
	var n := notes.size()
	while i < n:
		var t: float = notes[i]["t_ms"]
		var j := i
		var cs := 0.0
		var sus := 0.0
		while j < n and absf(float(notes[j]["t_ms"]) - t) <= 2.0:
			cs += float(notes[j]["col"])
			if float(notes[j]["end_ms"]) > t:
				sus = maxf(sus, float(notes[j]["end_ms"]) - t)
			j += 1
		var size := j - i
		ev.append({"t_ms": t + 23.0, "strength": clampf(0.35 + 0.18 * float(size), 0.0, 1.0), "kind": "tonal",
				"pitch": cs / float(size) / 3.0, "sustain_ms": sus})
		if size >= 2:
			ev.append({"t_ms": t + 23.0, "strength": 0.8, "kind": "hat", "pitch": -1.0, "sustain_ms": 0.0})
		i = j
	var end_ms: float = float(notes[n - 1]["t_ms"]) + 2000.0 if n > 0 else 0.0
	var sections: Array = []
	var cur := 0.0
	for k: Dictionary in kiai:
		var ks: float = k["start"]
		var ke: float = minf(float(k["end"]), end_ms)
		if ke <= ks or ks < cur:
			continue
		if ks > cur:
			sections.append({"start_ms": cur, "end_ms": ks, "intensity": 0.5, "kind": "verse", "kiai": false, "lead": "tonal"})
		sections.append({"start_ms": ks, "end_ms": ke, "intensity": 0.9, "kind": "chorus", "kiai": true, "lead": "tonal"})
		cur = ke
	if cur < end_ms:
		sections.append({"start_ms": cur, "end_ms": end_ms, "intensity": 0.5, "kind": "verse", "kiai": false, "lead": "tonal"})
	return {"ok": true, "error": "", "duration_ms": end_ms, "events": ev, "sections": sections}


func _kiai_ratio(notes: Array, kiai: Array) -> float:
	if notes.size() < 50 or kiai.is_empty():
		return -1.0
	var t0: float = notes[0]["t_ms"]
	var t1: float = notes[notes.size() - 1]["t_ms"]
	var kd := 0.0
	for k: Dictionary in kiai:
		kd += maxf(minf(float(k["end"]), t1) - maxf(float(k["start"]), t0), 0.0)
	var od := (t1 - t0) - kd
	if kd < 5000.0 or od < 5000.0:
		return -1.0
	var kn := 0
	for nt: Dictionary in notes:
		for k: Dictionary in kiai:
			if float(nt["t_ms"]) >= float(k["start"]) and float(nt["t_ms"]) < float(k["end"]):
				kn += 1
				break
	var on := notes.size() - kn
	if on <= 0:
		return -1.0
	return (float(kn) / kd) / (float(on) / od)


func _osu_text(notes: Array, grid: Dictionary, version: String) -> String:
	var sb := PackedStringArray()
	sb.append("osu file format v14\n\n[General]\nAudioFilename: audio.mp3\nMode: 3\n\n[Metadata]\nTitle:am\nArtist:am\nCreator:OMEN Auto\nVersion:%s\n" % version)
	sb.append("\n[Difficulty]\nHPDrainRate:7\nCircleSize:4\nOverallDifficulty:7\nApproachRate:5\nSliderMultiplier:1.4\nSliderTickRate:1\n\n[TimingPoints]\n")
	for s: Dictionary in grid["segments"]:
		sb.append("%d,%s,%d,2,0,100,1,0\n" % [int(round(float(s["start_ms"]))), str(float(s["beat_ms"])), int(s["meter"])])
	sb.append("\n[HitObjects]\n")
	for nt: Dictionary in notes:
		var x := int(nt["col"]) * 128 + 64
		var t := int(round(float(nt["t_ms"])))
		if float(nt["end_ms"]) >= 0.0:
			sb.append("%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, t, int(round(float(nt["end_ms"])))])
		else:
			sb.append("%d,192,%d,1,0,0:0:0:0:\n" % [x, t])
	return "".join(sb)


func _pct(x: float) -> String:
	return "%.1f %%" % (x * 100.0)


func _measure(maps_dir: String, n_sets: int, learn: bool) -> void:
	var t_all := Time.get_ticks_msec()
	print("=== AmChart-Messung: %s, %d Sets%s ===" % [maps_dir, n_sets, ", mit Lernen" if learn else ""])
	StarService.prefetch_dir(maps_dir)
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		print("FEHLER: Ordner nicht lesbar")
		return
	var files: Array = []
	for f in dir.get_files():
		if f.to_lower().ends_with(".osz"):
			files.append(f)
	files.sort()
	# Phase A: Menschen-Maps lesen, Statistik je Band, Sterne-Schaetzung gegen rosu
	var human: Array = []
	for i in 5:
		human.append(_agg_new())
	var tops: Array = []     # je Set die 4K-Diff mit den meisten Noten
	var fit_x: Array = []
	var fit_y: Array = []
	var n_diffs := 0
	var n_sets_4k := 0
	for f: String in files:
		var path := maps_dir.path_join(f)
		var stars := StarService.stars_for(path)
		var zr := ZIPReader.new()
		if zr.open(path) != OK:
			continue
		var best := {}
		for inner in zr.get_files():
			if not inner.to_lower().ends_with(".osu"):
				continue
			var text := zr.read_file(inner).get_string_from_utf8()
			if text.find("Mode: 3") < 0 and text.find("Mode:3") < 0:
				continue
			var res := OsuParser.parse(text)
			if not res["ok"]:
				continue
			var bm: Beatmap = res["beatmap"]
			if not bm.is_mania() or bm.column_count() != 4:
				continue
			var notes := _notes_of(bm)
			var grid := _grid_of(bm)
			if notes.size() < 50 or grid["segments"].is_empty():
				continue
			var info = stars.get(inner, {})
			var sr: float = float(info.get("stars", -1.0)) if info is Dictionary else -1.0
			n_diffs += 1
			var est := AmChart.estimate_stars(notes)
			if sr > 0.5:
				fit_x.append(est)
				fit_y.append(sr)
			var band := _band_of(sr) if sr > 0.5 else -1
			if band >= 0:
				var st := AmChart.pattern_stats(notes, grid)
				_agg_add(human[band], st)
				var kr := _kiai_ratio(notes, bm.kiai_intervals)
				if kr > 0.0:
					human[band]["kiai"].append(kr)
			if best.is_empty() or notes.size() > best["notes"].size():
				best = {"name": f, "notes": notes, "grid": grid, "kiai": bm.kiai_intervals, "stars": sr}
		zr.close()
		if not best.is_empty():
			tops.append(best)
			n_sets_4k += 1
	print("Gelesen: %d Sets mit 4K, %d Diffs, %.1f s" % [n_sets_4k, n_diffs, float(Time.get_ticks_msec() - t_all) / 1000.0])
	# Sterne-Schaetzung: Ausgleichsgerade rosu = a * est + b
	var fa := 1.0
	var fb := 0.0
	var mae_raw := 0.0
	var mae_fit := 0.0
	var nf := fit_x.size()
	if nf >= 10:
		var mx := _mean(fit_x)
		var my := _mean(fit_y)
		var sxx := 0.0
		var sxy := 0.0
		for i in nf:
			sxx += (float(fit_x[i]) - mx) * (float(fit_x[i]) - mx)
			sxy += (float(fit_x[i]) - mx) * (float(fit_y[i]) - my)
		fa = sxy / sxx if sxx > 0.0 else 1.0
		fb = my - fa * mx
		for i in nf:
			mae_raw += absf(float(fit_x[i]) - float(fit_y[i]))
			mae_fit += absf(float(fit_x[i]) * fa + fb - float(fit_y[i]))
		mae_raw /= float(nf)
		mae_fit /= float(nf)
	print("\n## Sterne-Schaetzung gegen rosu-pp (Menschen-Maps, n = %d)\n" % nf)
	print("| | Wert |\n|---|---|")
	print("| mittlerer Fehler roh | %.3f |" % mae_raw)
	print("| Ausgleich rosu = a * est + b | a = %.4f, b = %.4f |" % [fa, fb])
	print("| mittlerer Fehler nach Ausgleich | %.3f |" % mae_fit)
	if learn:
		_write_patterns(human, fa, fb, mae_fit, nf, n_sets_4k, n_diffs)
		AmChart.reload_patterns()
	# Phase B: aus n Sets erzeugen
	var step := maxf(float(tops.size()) / float(maxi(n_sets, 1)), 1.0)
	var picked: Array = []
	var pos := 0.0
	while int(pos) < tops.size() and picked.size() < n_sets:
		picked.append(tops[int(pos)])
		pos += step
	var gen: Array = []
	for i in 5:
		gen.append(_agg_new())
	var est_in := [0, 0, 0, 0, 0]
	var est_cap := [0, 0, 0, 0, 0]
	var lint_n := [0, 0, 0, 0, 0]
	var lint_first := ""
	var subset_bad := 0
	var times_ms: Array = []
	var out_dir := "user://am_chart_measure"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var old := DirAccess.open(out_dir)
	if old != null:
		for f in old.get_files():
			old.remove(f)
	var meta: Array = []      # je Set: {osz, est: [5], capped: [5]}
	for si in picked.size():
		var top: Dictionary = picked[si]
		var feats := _features_of(top["notes"], top["kiai"])
		var t0 := Time.get_ticks_msec()
		var all := AmChart.build_all(feats, top["grid"])
		times_ms.append(float(Time.get_ticks_msec() - t0))
		var zp := ZIPPacker.new()
		var osz := "set%03d.osz" % si
		zp.open(out_dir.path_join(osz))
		var m := {"osz": osz, "est": [], "capped": [], "src": float(top["stars"])}
		var prev := {}
		for pi in 5:
			var prof: String = AmChart.PROFILES[pi]
			var res: Dictionary = all[prof]
			if not res["ok"]:
				m["est"].append(-1.0)
				m["capped"].append(true)
				continue
			var notes: Array = res["notes"]
			var viol := AmChart.lint(notes, top["grid"], prof)
			lint_n[pi] += viol.size()
			if not viol.is_empty() and lint_first == "":
				lint_first = "%s / %s: %s" % [top["name"], prof, viol[0]]
			var st: Dictionary = res["stats"]
			m["est"].append(float(st["stars_est"]))
			m["capped"].append(bool(st["capped"]))
			if not st["capped"]:
				est_in[pi] += 1
			else:
				est_cap[pi] += 1
			if notes.size() >= 20:
				_agg_add(gen[pi], AmChart.pattern_stats(notes, top["grid"]))
			var times := _times(notes)
			for k in prev:
				if not times.has(k):
					subset_bad += 1
			prev = times
			zp.start_file("%s.osu" % prof)
			zp.write_file(_osu_text(notes, top["grid"], prof).to_utf8_buffer())
			zp.close_file()
		zp.close()
		meta.append(m)
	print("Erzeugt: %d Sets, %.1f s gesamt" % [picked.size(), float(Time.get_ticks_msec() - t_all) / 1000.0])
	# rosu-Sterne der erzeugten Maps: ein Aufruf fuer alle
	var rosu := StarService._run_starcalc(PackedStringArray(["--dir", ProjectSettings.globalize_path(out_dir)]))
	var r_in := [0, 0, 0, 0, 0]
	var r_cap_out := [0, 0, 0, 0, 0]    # ausserhalb und als capped gemeldet
	var r_miss := [0, 0, 0, 0, 0]       # ausserhalb, aber nicht gemeldet
	var r_n := [0, 0, 0, 0, 0]
	var r_err: Array = [[], [], [], [], []]
	var r_stars: Array = [[], [], [], [], []]
	for m: Dictionary in meta:
		var entry = rosu.get(m["osz"], {})
		var sd: Dictionary = entry.get("stars", {}) if entry is Dictionary else {}
		for pi in 5:
			var prof: String = AmChart.PROFILES[pi]
			var info = sd.get("%s.osu" % prof, {})
			if not (info is Dictionary) or not info.has("stars") or float(m["est"][pi]) < 0.0:
				continue
			var sr: float = info["stars"]
			var band: Array = AmChart.DEFAULTS["star_bands"][prof]
			r_n[pi] += 1
			r_stars[pi].append(sr)
			r_err[pi].append(absf(sr - float(m["est"][pi])))
			if sr >= float(band[0]) and sr <= float(band[1]):
				r_in[pi] += 1
			elif m["capped"][pi]:
				r_cap_out[pi] += 1
			else:
				r_miss[pi] += 1
	var old2 := DirAccess.open(out_dir)
	if old2 != null:
		for f in old2.get_files():
			old2.remove(f)
	# Bericht
	print("\n## Vergleich erzeugt gegen Mensch je Sterne-Band (%d Sets erzeugt; Mensch: alle 4K-Diffs im Band)\n" % picked.size())
	var rowsdef := [["Maps", "maps", 0], ["gleiche Spalte in Folge (Einzelnoten)", "same", 1], ["Nachbarspalte", "adjacent", 1],
			["weiter Sprung", "wide", 1], ["Akkord-Zeilen", "chord", 1], ["3er/4er-Akkorde", "chord3", 1],
			["Noten in Jacks (1/4)", "jack", 1], ["Hold-Anteil", "hold", 1], ["Hold-Laenge (Schlaege)", "hold_beats", 2],
			["Noten/s Mittel", "nps", 2], ["Noten/s Spitze", "peak", 2], ["linke Hand", "left", 1],
			["Abstand 1/8 und feiner", "g8th", 1], ["Abstand 1/4", "g4th", 1], ["Abstand 1/2", "ghalf", 1]]
	var hs: Array = []
	var gs: Array = []
	for pi in 5:
		hs.append(_summ(human[pi]))
		gs.append(_summ(gen[pi]))
	var head := "| Kennzahl |"
	var sep := "|---|"
	for pi in 5:
		head += " %s Mensch | %s erzeugt |" % [AmChart.PROFILES[pi], AmChart.PROFILES[pi]]
		sep += "---|---|"
	print(head)
	print(sep)
	for rd in rowsdef:
		var line := "| %s |" % rd[0]
		for pi in 5:
			for sdict: Dictionary in [hs[pi], gs[pi]]:
				var val = sdict[rd[1]]
				if int(rd[2]) == 0:
					line += " %d |" % int(val)
				elif int(rd[2]) == 1:
					line += " %s |" % _pct(float(val))
				else:
					line += " %.2f |" % float(val)
		print(line)
	var line_sim := "| Aehnlichkeit der Zeilen-Uebergaenge (0..1) |"
	var line_top := "| Anteil 4er-Muster in den Top %d der Menschen |" % TOP4
	for pi in 5:
		var top4 := _top(human[pi]["g4"], TOP4)
		line_sim += " 1.00 | %.2f |" % _bigram_sim(human[pi], gen[pi])
		line_top += " %s | %s |" % [_pct(_top_share(human[pi], top4)), _pct(_top_share(gen[pi], top4))]
	print(line_sim)
	print(line_top)
	print("\n## Sterne-Trefferquote je Profil (%d Sets)\n" % picked.size())
	print("| Profil | Band | rosu im Band | ausserhalb, als capped gemeldet | ausserhalb, nicht gemeldet | rosu Median | Schaetzung im Band | Fehler Schaetzung gegen rosu (Mittel) | lint-Verstoesse |")
	print("|---|---|---|---|---|---|---|---|---|")
	for pi in 5:
		var prof: String = AmChart.PROFILES[pi]
		var band: Array = AmChart.DEFAULTS["star_bands"][prof]
		var nn := float(maxi(r_n[pi], 1))
		print("| %s | %.1f-%.1f | %d / %d (%s) | %d | %d | %.2f | %d / %d | %.3f | %d |" % [prof, band[0], band[1], r_in[pi], r_n[pi],
				_pct(float(r_in[pi]) / nn), r_cap_out[pi], r_miss[pi], _quant(r_stars[pi], 0.5), est_in[pi],
				est_in[pi] + est_cap[pi], _mean(r_err[pi]), lint_n[pi]])
	print("\n## Weitere Messwerte\n")
	print("| | Wert |\n|---|---|")
	print("| lint-Verstoesse gesamt | %d%s |" % [lint_n[0] + lint_n[1] + lint_n[2] + lint_n[3] + lint_n[4], "" if lint_first == "" else " (erster: " + lint_first + ")"])
	print("| Stellen im leichteren, die im schwereren Profil fehlen | %d |" % subset_bad)
	print("| Rechenzeit build_all je Set: Mittel / Median / Maximum | %.0f ms / %.0f ms / %.0f ms |" % [_mean(times_ms), _quant(times_ms, 0.5), _quant(times_ms, 1.0)])
	print("| rosu-Ergebnisse erhalten | %d Sets |" % rosu.size())
	var src_bands := [0, 0, 0, 0, 0, 0]
	for m: Dictionary in meta:
		var b := _band_of(float(m["src"]))
		src_bands[b if b >= 0 else 5] += 1
	print("| Sterne der Vorlagen (Easy/Normal/Hard/Insane/Expert/darueber oder unbekannt) | %s |" % str(src_bands))
	print("\nGesamt: %.1f s" % (float(Time.get_ticks_msec() - t_all) / 1000.0))


func _write_patterns(human: Array, fa: float, fb: float, mae: float, nf: int, n_sets: int, n_diffs: int) -> void:
	var bands := {}
	var ready: Array = []
	for pi in 5:
		var a: Dictionary = human[pi]
		if int(a["maps"]) < 5:
			ready.append({})
			continue
		var s := _summ(a)
		var runs: Array = a["jack_runs"]
		var total_runs := 0
		for x in runs:
			total_runs += int(x)
		var cap := 2
		var acc := 0
		for l in range(2, 9):
			acc += int(runs[l])
			cap = l
			if total_runs == 0 or float(acc) >= 0.99 * float(total_runs):
				break
		var uni: Array = []
		var usum := 0.0
		for x in a["uni"]:
			usum += float(x)
		for x in a["uni"]:
			uni.append(snappedf(float(x) / maxf(usum, 1.0), 0.00001))
		var big: Array = []
		for g in 4:
			var bs := 0.0
			for x in a["big"][g]:
				bs += float(x)
			var arr: Array = []
			for x in a["big"][g]:
				arr.append(snappedf(float(x) / maxf(bs, 1.0), 0.00001))
			big.append(arr)
		var grams := {}
		for spec in [["g4", TOP4], ["g8", TOP8]]:
			var d: Dictionary = a[spec[0]]
			var top := _top(d, int(spec[1]))
			var out := {}
			if not top.is_empty():
				var mx := float(d[top[0]])
				for k in top:
					out[str(int(k))] = snappedf(float(d[k]) / mx, 0.0001)
			grams[spec[0]] = out
		var mv := float(maxi(a["moves"][0] + a["moves"][1] + a["moves"][2] + a["moves"][3], 1))
		ready.append({"n_maps": a["maps"], "n_notes": a["notes"],
				"chord_share": snappedf(s["chord"], 0.0001), "chord3_share": snappedf(s["chord3"], 0.0001),
				"hold_share_mean": snappedf(s["hold"], 0.0001), "hold_share_p90": snappedf(_quant(a["hold_shares"], 0.9), 0.0001),
				"hold_beats_mean": snappedf(s["hold_beats"], 0.001),
				"kiai_ratio": snappedf(_quant(a["kiai"], 0.5) if not a["kiai"].is_empty() else 1.3, 0.001),
				"nps_avg": snappedf(s["nps"], 0.001), "nps_peak": snappedf(s["peak"], 0.001),
				"balance_left": snappedf(s["left"], 0.0001), "jack_share": snappedf(s["jack"], 0.0001),
				"jack_runs": runs, "jack_cap": cap,
				"moves": [snappedf(a["moves"][0] / mv, 0.0001), snappedf(a["moves"][1] / mv, 0.0001),
						snappedf(a["moves"][2] / mv, 0.0001), snappedf(a["moves"][3] / mv, 0.0001)],
				"uni": uni, "big": big, "g4": grams["g4"], "g8": grams["g8"]})
	# duenn besetzte Baender uebernehmen die Tabellen des naechsten besetzten Bands
	for pi in 5:
		var entry: Dictionary = ready[pi]
		if entry.is_empty():
			for dist in range(1, 5):
				for cand: int in [pi + dist, pi - dist]:
					if entry.is_empty() and cand >= 0 and cand < 5 and not ready[cand].is_empty():
						entry = ready[cand].duplicate(true)
						entry["borrowed_from"] = AmChart.PROFILES[cand]
		bands[AmChart.PROFILES[pi]] = entry
	var data := {"version": 1, "game": "OMEN",
			"source": "Statistik aus %d Sets / %d 4K-Diffs von Menschen (maps/); enthaelt keine Maps" % [n_sets, n_diffs],
			"band_edges": BAND_EDGES, "star_fit": {"a": snappedf(fa, 0.0001), "b": snappedf(fb, 0.0001), "mae": snappedf(mae, 0.001), "n": nf},
			"bands": bands}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/automap"))
	var f := FileAccess.open("res://data/automap/patterns.json", FileAccess.WRITE)
	if f == null:
		print("FEHLER: patterns.json nicht schreibbar")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	print("patterns.json geschrieben (%d Baender)" % bands.size())
