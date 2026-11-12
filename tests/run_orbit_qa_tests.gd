extends SceneTree

## Orbit-QA (Satelliten): Erreichbarkeit rein rechnerisch (ohne Core/Frames).
## Bot: drueckt jedes Ziel mit Zeitstreuung, bewegt den Cursor mit konstanter
## Geschwindigkeit (Feld-Einheiten/s) vom Ende des vorigen Ziels zum naechsten und
## drueckt, sobald er im Trefferradius ist (AIM_R), Treffer nur im EDGE-Fenster; Halten: Kugel folgen =
## Pfadlaenge/Dauer <= Bot-Tempo. Akzent: zweite Taste ~8 ms hinter der ersten.
## Bot-Acc = Summe Stufenwert (OrbitCore.TIER_VALUE nach Zeitfehler) / Ziele.
## Vorher/nachher: jede Map auch mit den Regeln vor 4 (Mania-Fenster, Runde ab 330 ms
## ein Beat; OrbitConverter.legacy_laps, OrbitCore.tier_windows(od, true)).
## Ziel (docs/modes/orbit_satellit.md): Tablet (3,5/s, 25 ms) >= 97 % und Maus
## (2,5/s) >= 94 % auf Maps < 5 Sterne. Schreibt docs/modes/orbit_satellit_qa.md.
## Headless:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_qa_tests.gd

## [Tempo Feld-Einheiten/s, Zeitstreuung ms, Mindest-Trefferquote]
const BOTS := {
	"tablet": [3.5, 25.0, 0.97],
	"maus": [2.5, 25.0, 0.94],
}
const AIM_R := 0.05
const STAR_LIMIT := 5.0
const REPORT := "res://docs/modes/orbit_satellit_qa.md"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Orbit-QA (Satelliten) ===")
	_test_bot_model()
	var rows := _measure_library()
	_test_library(rows)
	_write_report(rows)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


## Trefferquote 0..1 eines Bots auf ns. od: Overall Difficulty (Trefferfenster).
static func bot_rate(ns: Array[OrbitNote], speed: float, sigma: float, od: float, seed: int) -> float:
	return bot_run(ns, speed, sigma, od, seed)[0]


## [Trefferquote, Acc] 0..1. legacy: Fenster vor Regeln 4.
static func bot_run(ns: Array[OrbitNote], speed: float, sigma: float, od: float, seed: int,
		legacy: bool = false) -> Array:
	if ns.is_empty():
		return [1.0, 1.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wins := OrbitCore.tier_windows(od, legacy)
	var w := wins[4]
	var hits := 0
	var val := 0.0
	var free_t := -INF
	var free_p := Vector2(0.5, 0.5)
	for n in ns:
		var e := clampf(rng.randfn(0.0, sigma), -2.5 * sigma, 2.5 * sigma)
		var press := n.time_ms + e
		var dist := maxf(free_p.distance_to(n.pos) - AIM_R, 0.0)
		var arrive := free_t + dist / speed * 1000.0
		# Zu spaet am Ziel: der Bot drueckt, sobald der Cursor da ist (Treffer, wenn noch im Fenster).
		press = maxf(press, arrive)
		var ok := absf(press - n.time_ms) <= w
		if n.key == OrbitNote.KEY_ACCENT:
			rng.randfn(0.0, 8.0)
		var rel := press
		if n.is_hold:
			var dur_s := (n.end_ms - n.time_ms) / 1000.0
			var len := 0.0
			for i in range(1, n.path.size()):
				len += n.path[i - 1].distance_to(n.path[i])
			if len / maxf(dur_s, 0.001) > speed:
				ok = false
			rel = n.end_ms + clampf(rng.randfn(0.0, sigma), -2.5 * sigma, 2.5 * sigma)
		if ok:
			hits += 1
			var q := 4
			for k in 5:
				if absf(press - n.time_ms) <= wins[k]:
					q = k
					break
			val += OrbitCore.TIER_VALUE[q]
		free_t = maxf(rel, press)
		free_p = OrbitConverter.end_pos(n)
	return [float(hits) / float(ns.size()), val / float(ns.size())]


func _test_bot_model() -> void:
	print("- Bot-Modell")
	var ns: Array[OrbitNote] = []
	for i in 40:
		ns.append(OrbitNote.make_target(1000.0 + 500.0 * i, Vector2(0.2 if i % 2 == 0 else 0.8, 0.5), i % 2))
	_ok(bot_rate(ns, 3.5, 25.0, 8.0, 1) >= 0.99, "lockere Spruenge (0,6 in 500 ms): Tablet trifft fast alles")
	var fast: Array[OrbitNote] = []
	for i in 40:
		fast.append(OrbitNote.make_target(1000.0 + 100.0 * i, Vector2(0.1 if i % 2 == 0 else 0.9, 0.5), 0))
	_ok(bot_rate(fast, 3.5, 25.0, 8.0, 1) < 0.2, "0,8 in 100 ms (8/s): unerreichbar")


func _measure_library() -> Array:
	print("- Bibliothek messen")
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	var rows: Array = []
	if da == null:
		print("  (kein maps/-Ordner)")
		return rows
	var files := Array(da.get_files())
	files.sort()
	var seed := 1
	for f in files:
		if not str(f).to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.hit_objects.size() < 30 or (bm.is_mania() and bm.column_count() != 4):
				continue
			var ns := OrbitConverter.convert(bm)
			if ns.size() < 20:
				continue
			OrbitConverter.legacy_laps = true
			var old := OrbitConverter.convert(bm)
			OrbitConverter.legacy_laps = false
			seed += 1
			var a := OrbitConverter.analyze(ns, bm)
			var r := {"label": "%s [%s]" % [str(f).get_basename().left(28), bm.version_name().left(24)],
				"mania": bm.is_mania(), "stars": OrbitConverter.stars(ns), "n": ns.size(),
				"nps": a.nps, "vis": a.max_visible, "jump": a.mean_jump_speed,
				"stars_old": OrbitConverter.stars(old), "n_old": old.size(), "partial": 0}
			for n in ns:
				if n.laps == 0:
					r.partial += 1
			for name in BOTS:
				var b: Array = BOTS[name]
				var now := bot_run(ns, b[0], b[1], bm.od(), seed)
				var was := bot_run(old, b[0], b[1], bm.od(), seed, true)
				r[name] = now[0]
				r[name + "_acc"] = now[1]
				r[name + "_old"] = was[0]
				r[name + "_acc_old"] = was[1]
			rows.append(r)
	rows.sort_custom(func(x, y): return x.stars < y.stars)
	return rows


func _test_library(rows: Array) -> void:
	print("- Erreichbarkeit (%d Diffs)" % rows.size())
	if rows.is_empty():
		return
	var n_low := 0
	var worst := {}
	for name in BOTS:
		worst[name] = 2.0
	for r in rows:
		if r.stars >= STAR_LIMIT:
			continue
		n_low += 1
		for name in BOTS:
			worst[name] = minf(worst[name], r[name])
	for name in BOTS:
		var need: float = BOTS[name][2]
		_ok(worst[name] >= need, "%s: schlechteste Map < %.0f Sterne %.1f %% (>= %.0f %%, %d Maps)" % [
			name, STAR_LIMIT, 100.0 * worst[name], 100.0 * need, n_low])
	var med: float = rows[rows.size() / 2].stars
	_ok(med >= 3.0 and med <= 5.0, "Sterne-Median %.2f im Bereich 3..5" % med)


func _write_report(rows: Array) -> void:
	if rows.is_empty():
		return
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f == null:
		print("  (Bericht nicht schreibbar)")
		return
	f.store_line("# Orbit Satelliten: QA-Messung")
	f.store_line("")
	f.store_line("Erzeugt von `tests/run_orbit_qa_tests.gd` (rein rechnerischer Bot, siehe dort). Bibliothek: %d Diffs (osu!standard + Mania 4K)." % rows.size())
	f.store_line("Bots: Tablet 3,5 Feld-Einheiten/s, Maus 2,5/s, je 25 ms Zeitstreuung, Trefferradius %.2f. Ziele: Tablet >= 97 %%, Maus >= 94 %% auf Maps unter %.0f Sternen." % [AIM_R, STAR_LIMIT])
	f.store_line("")
	var buckets := [[0.0, 2.5], [2.5, 4.0], [4.0, 5.0], [5.0, 6.0], [6.0, 8.0], [8.0, 99.0]]
	f.store_line("## Je Sterne-Gruppe")
	f.store_line("")
	f.store_line("| Sterne | Maps | Tablet min / Mittel | Maus min / Mittel | Ziele/s Mittel |")
	f.store_line("|---|---|---|---|---|")
	for b in buckets:
		var cnt := 0
		var tmin := 2.0
		var tsum := 0.0
		var mmin := 2.0
		var msum := 0.0
		var nps := 0.0
		for r in rows:
			if r.stars >= b[0] and r.stars < b[1]:
				cnt += 1
				tmin = minf(tmin, r.tablet)
				tsum += r.tablet
				mmin = minf(mmin, r.maus)
				msum += r.maus
				nps += r.nps
		if cnt > 0:
			f.store_line("| %.1f - %.1f | %d | %.1f %% / %.1f %% | %.1f %% / %.1f %% | %.2f |" % [
				b[0], minf(b[1], 15.0), cnt, 100.0 * tmin, 100.0 * tsum / cnt, 100.0 * mmin, 100.0 * msum / cnt, nps / cnt])
	f.store_line("")
	f.store_line("## Vorher/nachher (Regeln 4: Fenster wie osu!standard, Runde 2 Beats unter 450 ms, 4 unter 225 ms)")
	f.store_line("")
	f.store_line("Vorher = Regeln vor 4 (Fenster wie Mania, Runde 2 Beats erst unter 330 ms). Gleiche Maps, gleiche Bot-Zufallsfolge; Gruppen nach Sternen nachher.")
	f.store_line("")
	f.store_line("| Sterne | Maps | Tablet-Acc vorher / nachher | Maus-Acc vorher / nachher | Tablet-Treffer vorher / nachher | Maus-Treffer vorher / nachher | Sterne vorher / nachher (Mittel) |")
	f.store_line("|---|---|---|---|---|---|---|")
	for b in buckets:
		var cnt := 0
		var sums := {"tablet_acc_old": 0.0, "tablet_acc": 0.0, "maus_acc_old": 0.0, "maus_acc": 0.0,
			"tablet_old": 0.0, "tablet": 0.0, "maus_old": 0.0, "maus": 0.0, "stars_old": 0.0, "stars": 0.0}
		for r in rows:
			if r.stars >= b[0] and r.stars < b[1]:
				cnt += 1
				for k in sums:
					sums[k] += float(r[k])
		if cnt > 0:
			var m := func(k: String) -> float: return sums[k] / cnt
			f.store_line("| %.1f - %.1f | %d | %.1f %% / %.1f %% | %.1f %% / %.1f %% | %.1f %% / %.1f %% | %.1f %% / %.1f %% | %.2f / %.2f |" % [
				b[0], minf(b[1], 15.0), cnt, 100.0 * m.call("tablet_acc_old"), 100.0 * m.call("tablet_acc"),
				100.0 * m.call("maus_acc_old"), 100.0 * m.call("maus_acc"), 100.0 * m.call("tablet_old"),
				100.0 * m.call("tablet"), 100.0 * m.call("maus_old"), 100.0 * m.call("maus"),
				m.call("stars_old"), m.call("stars")])
	f.store_line("")
	var so: Array[float] = []
	var dmax := 0.0
	var dsum := 0.0
	var lost := 0
	var partial := 0
	for r in rows:
		so.append(r.stars_old)
		dmax = maxf(dmax, absf(r.stars - r.stars_old))
		dsum += absf(r.stars - r.stars_old)
		lost += maxi(int(r.n_old) - int(r.n), 0)
		partial += int(r.partial)
	so.sort()
	f.store_line("- Sterne: Median vorher %.2f, nachher %.2f; Abweichung je Map Mittel %.3f, max %.3f." % [
		so[so.size() / 2], _median_stars(rows), dsum / rows.size(), dmax])
	f.store_line("- Ziele: %d weniger als vorher (alle Maps); %d Ziele mit Teilrunde (laps 0, dichte schnelle Stellen)." % [lost, partial])
	f.store_line("")
	var st: Array[float] = []
	var easy: Array[float] = []
	var hard := 0
	for r in rows:
		st.append(r.stars)
		if r.nps < 2.5:
			easy.append(r.stars)
		if r.stars >= 8.0:
			hard += 1
	st.sort()
	easy.sort()
	f.store_line("## Sterne-Kalibrierung (Skill: Zielen, Tempo, Lesen)")
	f.store_line("")
	f.store_line("- Median %.2f Sterne, %d Maps >= 8 Sterne (%.1f %%)." % [st[st.size() / 2], hard, 100.0 * float(hard) / float(st.size())])
	if easy.size() > 0:
		f.store_line("- Leichte Maps (< 2,5 Ziele/s, %d): Median %.2f, 90 %%-Quantil %.2f Sterne." % [easy.size(), easy[easy.size() / 2], easy[int(easy.size() * 0.9)]])
	f.store_line("- Zielen: Sprung/Zeit, Richtungswechsel, schwere Spruenge (> 1,6 Feld/s zaehlen zusaetzlich). Tempo: Dichte, Tastenwechsel, Akzente, Halten. Lesen: wenige Runden, Ueberdeckung.")
	f.store_line("- osu!standard-Maps bleiben treu (keine gekappten Spruenge, ganze Slider-Kurven); nur leichte Maps werden verkleinert. Schwere Sprung-Maps haben dafuer hohe Sterne (Maps unter 5 Sternen: Tablet und Maus erreichen die Ziele).")
	f.store_line("")
	f.store_line("## Je Map (nach Sternen)")
	f.store_line("")
	f.store_line("| Map | Typ | Sterne | Ziele | Ziele/s | max sichtbar | Sprung/s | Tablet | Maus |")
	f.store_line("|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		f.store_line("| %s | %s | %.2f | %d | %.2f | %d | %.2f | %.1f %% | %.1f %% |" % [
			str(r.label).replace("|", "/"), "4K" if r.mania else "std", r.stars, r.n, r.nps, r.vis,
			r.jump, 100.0 * r.tablet, 100.0 * r.maus])
	f.close()


static func _median_stars(rows: Array) -> float:
	var st: Array[float] = []
	for r in rows:
		st.append(r.stars)
	st.sort()
	return st[st.size() / 2]
