extends SceneTree

## Headless-Tests fuer den Empfehlungs-Kern (Recommender): Koennen je Modus
## aus synthetischen Profilen (Anfaenger, Mittel, Profi, Wenigspieler, nur
## Fehlschlaege), Stufen, Push (Top-pp), Regression echter Mittel-Spieler,
## Stil-Vorlieben, Filter, Abwechslung, Determinismus.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_recommender_tests.gd

var _passed := 0
var _failed := 0
const NOW := 1800000000  # feste Testzeit (Unix)


func _initialize() -> void:
	print("=== TETHRA Recommender-Tests ===")
	_test_skill_levels()
	_test_profiles()
	_test_mid_player_regression()
	_test_push_top_pp()
	_test_slope_fit()
	_test_style()
	_test_filters()
	_test_variety()
	_test_empty_and_playable()
	_test_determinism()
	_test_profile()
	_test_reasons()
	_test_paging_novelty()
	_test_online()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


# --- Hilfen ---

func _date(offset_sec: int) -> String:
	return Time.get_datetime_string_from_unix_time(NOW - offset_sec)


## Deterministisches Rauschen -1..1.
func _noise(i: int) -> float:
	return sin(float(i) * 12.9898 + 4.1414) * 0.5 + sin(float(i) * 3.77) * 0.5


## Profil: count Laeufe um center Sterne (+-spread), Acc um acc0 (+-acc_sd),
## 1 Lauf je 10 min, der juengste age_days alt.
func _profile(mode: String, center: float, acc0: float, count: int = 30, spread: float = 0.3,
		acc_sd: float = 0.03, age_days: int = 3, fail_every: int = 0) -> Array:
	var out: Array = []
	for i in count:
		var st := maxf(0.4, center + spread * _noise(i))
		var acc := clampf(acc0 + acc_sd * _noise(i + 101), 0.3, 1.0)
		var failed := fail_every > 0 and i % fail_every == 0
		var r := {"set": "s%d" % i, "diff": "d", "stars": st, "accuracy": 0.0 if failed else acc,
			"failed": failed, "grade": "F" if failed else ("S" if acc >= 0.95 else ("A" if acc >= 0.9 else "B")),
			"date": _date(age_days * 86400 + (count - i) * 600)}
		if mode == "mania" and not failed:
			r["pp"] = Recommender.mania_pp(6.0, st, acc)
		out.append(r)
	return out


## Kandidaten 0,5 .. 8 Sterne in 0,1-Schritten, je zwei Diffs pro Set.
func _cands(osu_mode: int = 3) -> Array:
	var out: Array = []
	for i in 76:
		var st := 0.5 + 0.1 * i
		out.append({"set": "c%d" % (i / 2), "diff": "v%d" % (i % 2), "stars": st,
			"osu_mode": osu_mode, "max_pp": Recommender.mania_pp(6.0, st, 1.0)})
	return out


func _has(list: Array, pick: Dictionary) -> bool:
	for s in list:
		if s.set == pick.set and s.diff == pick.diff:
			return true
	return false


func _mean_stars(list: Array) -> float:
	var t := 0.0
	for s in list:
		t += float(s.stars)
	return t / maxf(1.0, float(list.size()))


# --- Tests ---

func _test_skill_levels() -> void:
	print("-- Koennen je Modus")
	for m in Recommender.MODES:
		var nb := Recommender.skill(m, _profile(m, 1.0, 0.80))
		var mid := Recommender.skill(m, _profile(m, 2.7, 0.90))
		var pro := Recommender.skill(m, _profile(m, 5.0, 0.975))
		_ok(nb.comfort < mid.comfort and mid.comfort < pro.comfort,
			"%s: Anfaenger < Mittel < Profi (%.2f < %.2f < %.2f)" % [m, nb.comfort, mid.comfort, pro.comfort])
		_ok(absf(mid.comfort - 2.7) < 0.25, "%s: Mittel (2,7 Sterne, B-A) -> Level %.2f" % [m, mid.comfort])
		_ok(pro.comfort > 5.0 and pro.comfort < 5.9, "%s: Profi (5 Sterne, S) -> Level %.2f" % [m, pro.comfort])
		_ok(nb.comfort < 1.0, "%s: Anfaenger (1 Stern, 80 %%) -> Level %.2f" % [m, nb.comfort])
		var a: float = Recommender.acc_at(mid, mid.comfort)
		_ok(a > 0.85 and a < 0.95, "%s: Acc am Level im Band B-A (%.3f)" % [m, a])


## Jedes Profil liefert plausible Easy/Challenge/Push in jedem Modus.
func _test_profiles() -> void:
	print("-- Profile")
	var profiles := {
		"beginner": func(m): return _profile(m, 1.0, 0.80),
		"mid": func(m): return _profile(m, 2.7, 0.90),
		"pro": func(m): return _profile(m, 5.0, 0.975),
		"few": func(m): return _profile(m, 2.0, 0.92, 3),
		"fails": func(m): return _profile(m, 4.0, 0.0, 12, 0.3, 0.0, 3, 1),
		"long": func(m): return _profile(m, 3.5, 0.90, 1000, 0.6, 0.04),
	}
	for m in Recommender.MODES:
		for pname in profiles:
			var runs: Array = profiles[pname].call(m)
			var sk := Recommender.skill(m, runs)
			var c: float = sk.comfort
			var e := Recommender.suggest(m, "easy", _cands(), 5, runs, NOW)
			var ch := Recommender.suggest(m, "challenge", _cands(), 5, runs, NOW)
			var p := Recommender.suggest(m, "push", _cands(), 5, runs, NOW)
			var tag := "%s/%s (Level %.2f)" % [m, pname, c]
			_ok(e.size() == 5 and ch.size() == 5 and p.size() == 5, "%s: alle Stufen liefern 5" % tag)
			if e.is_empty() or ch.is_empty() or p.is_empty():
				continue
			var good := true
			for s in e:
				good = good and s.stars <= maxf(c - 0.3, 1.0) + 0.001 and s.expected_acc >= 0.85
			_ok(good, "%s: Easy unter dem Level, Acc >= 85 %%" % tag)
			good = true
			for s in ch:
				good = good and s.stars >= c - 0.001 and s.stars <= c + 0.6 + 0.001
			_ok(good, "%s: Challenge im Level .. +0,6" % tag)
			good = true
			for s in p:
				good = good and s.stars >= c + 0.4 - 0.001 and s.stars <= c + 1.3 + 0.001 \
						and s.expected_acc >= Recommender.MIN_PUSH_ACC
			_ok(good, "%s: Push +0,4 .. +1,3 mit Acc >= 80 %%" % tag)
			_ok(_mean_stars(e) < _mean_stars(ch) and _mean_stars(ch) < _mean_stars(p) + 0.001,
				"%s: Easy < Challenge <= Push (%.2f, %.2f, %.2f)" % [tag, _mean_stars(e), _mean_stars(ch), _mean_stars(p)])
	var fails := Recommender.skill("mania", _profile("mania", 4.0, 0.0, 12, 0.3, 0.0, 3, 1))
	_ok(fails.comfort < 3.2, "nur Fehlschlaege bei 4 Sternen -> Level unter 3,2 (%.2f)" % fails.comfort)
	var none := Recommender.skill("orbit", [])
	_ok(none.n == 0 and is_equal_approx(none.comfort, 1.5), "ohne Laeufe: Standardkurve")
	var one := Recommender.skill("orbit", [{"set": "a", "diff": "d", "stars": 6.0,
		"accuracy": 0.99, "date": _date(100)}])
	_ok(one.comfort > none.comfort and one.comfort < 4.0, "ein Glueckslauf: vorsichtig (%.2f)" % one.comfort)
	var old := _profile("rally", 1.5, 0.9, 30, 0.2, 0.02, 400)
	old.append_array(_profile("rally", 4.0, 0.9, 10, 0.2, 0.02, 3).map(func(r):
		r.set = "n" + str(r.set)
		return r))
	_ok(Recommender.skill("rally", old).comfort > 3.0,
		"alte Laeufe zaehlen weniger als juengste (%.2f)" % Recommender.skill("rally", old).comfort)


## Anonymisiertes echtes Profil: ~440 pp, Mania meist 2,4..2,7 Sterne mit
## Rang B bis A, wenige C, ein Abbruch, alte schwere Versuche mit C.
func _test_mid_player_regression() -> void:
	print("-- Regression Mittel-Spieler (Mania)")
	var data := [
		[2.53, 0.934], [2.55, 0.787], [2.66, 0.864], [2.64, 0.918], [2.59, 0.876],
		[2.68, 0.927], [2.26, 0.883], [2.25, 0.887], [2.50, 0.886], [2.58, 0.866],
		[2.60, 0.878], [2.59, 0.841], [2.49, 0.927], [2.64, 0.0], [2.58, 0.916],
		[2.64, 0.928], [2.60, 0.914], [2.61, 0.920], [2.41, 0.907], [2.49, 0.921],
		[2.51, 0.893], [2.65, 0.848], [2.55, 0.968], [2.57, 0.942], [2.50, 0.929],
		[2.52, 0.927], [2.64, 0.930], [2.43, 0.934], [2.36, 0.901], [2.30, 0.912],
		[2.20, 0.940], [2.10, 0.952], [2.62, 0.858], [2.47, 0.889], [2.33, 0.915],
	]
	var runs: Array = []
	for i in data.size():
		var st: float = data[i][0]
		var acc: float = data[i][1]
		var r := {"set": "m%d" % i, "diff": "d", "stars": st, "accuracy": acc, "failed": acc <= 0.0,
			"grade": "F" if acc <= 0.0 else ("S" if acc >= 0.95 else ("A" if acc >= 0.9 else ("B" if acc >= 0.8 else "C"))),
			"date": _date(5 * 86400 - i * 900)}
		if acc > 0.0:
			r["pp"] = Recommender.mania_pp(5.4, st, acc) * (1.25 if acc > 0.92 else 1.0)
		runs.append(r)
	# Alte schwere Versuche (4 Monate frueher), C-Rang
	for x in [[4.53, 0.790, 30.3], [5.36, 0.731, 27.9], [3.10, 0.707, 3.0]]:
		runs.append({"set": "old%s" % x[0], "diff": "d", "stars": x[0], "accuracy": x[1], "pp": x[2],
			"grade": "C", "date": _date(120 * 86400)})
	var sk := Recommender.skill("mania", runs)
	print("     Level %.2f, slope %.3f, rating %.0f pp" % [sk.comfort, sk.slope, sk.rating])
	_ok(sk.comfort >= 2.4 and sk.comfort <= 2.85, "Level im Spielbereich 2,4 .. 2,85 (%.2f)" % sk.comfort)
	var cands := _cands()
	var ch := Recommender.suggest("mania", "challenge", cands, 5, runs, NOW)
	var ok_ch := ch.size() == 5
	for s in ch:
		ok_ch = ok_ch and s.stars >= 2.4 and s.stars <= 3.4 and s.expected_acc >= 0.85 and s.expected_acc <= 0.93
	_ok(ok_ch, "Challenge 2,4 .. 3,4 Sterne mit 85..93 %% (%.2f..)" % (ch[0].stars if ch.size() else -1.0))
	var e := Recommender.suggest("mania", "easy", cands, 5, runs, NOW)
	var ok_e := e.size() == 5
	for s in e:
		ok_e = ok_e and s.stars >= 1.2 and s.stars <= 2.5 and s.expected_acc >= 0.92
	_ok(ok_e, "Easy 1,2 .. 2,5 Sterne, sicher A/S")
	var p := Recommender.suggest("mania", "push", cands, 5, runs, NOW)
	var ok_p: bool = p.size() == 5 and "would be top" in str(p[0].reason)
	for s in p:
		print("     push %.2f* %.3f %.1f %s" % [s.stars, s.expected_acc, s.expected_perf, s.reason])
		ok_p = ok_p and s.stars >= 2.8 and s.stars <= 4.0 and s.expected_acc >= 0.82 and s.expected_acc <= 0.93
		if "would be top" in str(s.reason):
			var gain := int(str(s.reason).get_slice("+", 1).get_slice(" ", 0))
			ok_p = ok_p and gain >= 1 and gain <= 25 and s.expected_perf <= 45.0
		else:
			ok_p = ok_p and "A step up" in str(s.reason)
	_ok(ok_p, "Push 2,8 .. 4,0 Sterne, realistischer Gewinn (%s)" % (p[0].reason if p.size() else "-"))
	var hard := Recommender.suggest("mania", "push", [{"set": "h", "diff": "d", "stars": 4.7,
		"osu_mode": 3, "max_pp": 120.0}], 5, runs, NOW)
	_ok(hard.is_empty(), "4,7-Sterne-Map ist kein Push-Vorschlag")


func _test_push_top_pp() -> void:
	print("-- Push")
	for m in ["orbit", "rally", "dirigent", "trace", "rebound"]:  # Mania: Regression oben
		var runs := _profile(m, 4.0, 0.92)
		var push := Recommender.suggest(m, Recommender.LEVEL_PUSH, _cands(), 5, runs, NOW)
		var good: bool = not push.is_empty() and (("would be top" in push[0].reason) or ("new top pp" in push[0].reason))
		_ok(good, "%s: Push zuerst mit Top-10-Grund (%s)" % [m, push[0].reason if push.size() else "-"])
	# Wenige schwache Laeufe: jede neue Leistung ist Top 10 -> Grund mit Rang.
	var p := Recommender.suggest("mania", "push", _cands(), 3, _profile("mania", 3.0, 0.9, 6), NOW)
	_ok(not p.is_empty() and "pp" in p[0].reason, "Mania-Grund in pp (%s)" % (p[0].reason if p.size() else "-"))
	var op := Recommender.suggest("orbit", "push", _cands(), 3, _profile("orbit", 3.0, 0.9), NOW)
	_ok(not op.is_empty() and "pts" in op[0].reason, "Orbit-Grund in pts")
	# Starke Top-Liste, keine Map kann rein -> naechster Schritt statt leerer Liste.
	var strong := _profile("mania", 3.0, 0.9)
	for i in 12:
		strong.append({"set": "top%d" % i, "diff": "d", "stars": 3.0, "accuracy": 0.99, "pp": 500.0,
			"grade": "S", "date": _date(30 * 86400)})
	var st := Recommender.suggest("mania", "push", _cands(), 5, strong, NOW)
	_ok(st.size() == 5 and "A step up" in st[0].reason, "keine Top-10-Chance -> 'A step up' (%s)" % (st[0].reason if st.size() else "-"))


func _test_slope_fit() -> void:
	print("-- Steigung")
	var steep: Array = []
	for i in 30:  # 1,5 .. 4,5 Sterne, Acc faellt 12 % je Stern
		var st := 1.5 + 0.1 * i
		steep.append({"set": "q%d" % i, "diff": "d", "stars": st, "accuracy": clampf(0.95 - 0.12 * (st - 2.0), 0.5, 1.0),
			"grade": "A", "date": _date(86400 + i * 60)})
	var sk := Recommender.skill("orbit", steep)
	_ok(sk.slope > 0.09 and sk.slope <= Recommender.SLOPE_MAX, "steile Kurve erkannt (%.3f)" % sk.slope)
	var flat := Recommender.skill("orbit", _profile("orbit", 3.0, 0.9, 30, 0.05))
	_ok(is_equal_approx(flat.slope, 0.07), "kaum Streuung -> Standard-Steigung (%.3f)" % flat.slope)


func _test_style() -> void:
	print("-- Stil")
	var jack: Array = []
	var stream: Array = []
	var js: Array = []
	var ln: Array = []
	for i in 64:
		jack.append([i * 120.0, 1, false])
		stream.append([i * 100.0, i % 4, false])
		js.append([i * 110.0, i % 4, false])
		js.append([i * 110.0, (i + 2) % 4, false])
		ln.append([i * 300.0, i % 4, true])
	var sj := Recommender.mania_style(jack)
	var ss := Recommender.mania_style(stream)
	var sjs := Recommender.mania_style(js)
	var sl := Recommender.mania_style(ln)
	_ok(sj.jack > 0.9 and ss.stream > 0.9 and sjs.jumpstream > 0.9 and sl.hold > 0.9,
		"Muster erkannt: jack %.2f, stream %.2f, jumpstream %.2f, hold %.2f" % [sj.jack, ss.stream, sjs.jumpstream, sl.hold])
	var st := Recommender.std_style([[0.0, 0, 0], [200.0, 400, 300], [400.0, 0, 0], [600.0, 400, 300]])
	_ok(st.jumps > 0.9, "Standard: Spruenge erkannt (%.2f)" % st.jumps)
	# Vorlieben: oft wiederholte Jumpstream-Maps von Kuenstler "A", 150 BPM.
	var feats := {}
	var runs: Array = []
	var plays := {}
	for i in 8:
		var k := "liked%d|d" % i
		feats[k] = {"artist": "Artist A", "bpm": 150.0, "length": 150.0, "style": sjs}
		plays[k] = 4
		runs.append({"set": "liked%d" % i, "diff": "d", "stars": 3.0, "accuracy": 0.94, "grade": "A",
			"date": _date(86400 * 2 + i * 600)})
	for i in 4:
		var k2 := "other%d|d" % i
		feats[k2] = {"artist": "Artist Z%d" % i, "bpm": 220.0, "length": 90.0, "style": sl}
		runs.append({"set": "other%d" % i, "diff": "d", "stars": 3.0, "accuracy": 0.88, "grade": "B",
			"date": _date(86400 * 2 + 9000 + i * 600)})
	var t := Recommender.taste(runs, feats, plays)
	_ok(not t.is_empty(), "Vorlieben aus 12 Maps")
	var like := {"set": "x1", "diff": "d", "stars": 3.1, "osu_mode": 3, "artist": "Artist B", "bpm": 152.0, "length": 140.0, "style": sjs}
	var unlike := {"set": "x2", "diff": "d", "stars": 3.1, "osu_mode": 3, "artist": "Artist Y", "bpm": 230.0, "length": 60.0, "style": sl}
	var ml := Recommender.style_match(t, like)
	var mu := Recommender.style_match(t, unlike)
	_ok(float(ml.bonus) > float(mu.bonus) + 0.3, "aehnliche Map mehr Bonus (%.2f > %.2f)" % [ml.bonus, mu.bonus])
	_ok("Jumpstream" in str(ml.reason), "Grund nennt den Stil (%s)" % ml.reason)
	_ok(str(mu.reason) == "", "unpassende Map ohne Stil-Grund")
	_ok(Recommender.taste(runs.slice(0, 3), feats).is_empty(), "unter 5 Maps: keine Vorlieben")
	# Bonus hebt die passende Map bei gleichem Abstand nach vorn.
	var cands := [unlike, like]
	var out := Recommender.suggest("mania", "challenge", cands, 2, runs, NOW, t)
	_ok(out.size() == 2 and out[0].set == "x1" and str(out[0].style_reason) != "", "Stil-Bonus sortiert vor")
	# Abwechslung: 6 passende Maps desselben Kuenstlers, 3 andere.
	var many: Array = []
	for i in 6:
		many.append({"set": "a%d" % i, "diff": "d", "stars": 3.1, "osu_mode": 3, "artist": "Artist A", "bpm": 150.0, "length": 150.0, "style": sjs})
	for i in 3:
		many.append({"set": "b%d" % i, "diff": "d", "stars": 3.1, "osu_mode": 3, "artist": "Other %d" % i, "bpm": 200.0, "length": 60.0, "style": sl})
	var mix := Recommender.suggest("mania", "challenge", many, 5, runs, NOW, t)
	var same := 0
	for s in mix:
		if str(s.set).begins_with("a"):
			same += 1
	_ok(mix.size() == 5 and same <= Recommender.MAX_PER_ARTIST, "hoechstens %d je Kuenstler (%d)" % [Recommender.MAX_PER_ARTIST, same])


func _test_filters() -> void:
	print("-- Filter")
	var runs := _profile("mania", 3.0, 0.9)
	var cands := _cands()
	var all := Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, cands, 50, runs, NOW)
	_ok(all.size() > 2, "Ausgangsliste nicht leer")
	var pick: Dictionary = all[0]
	var c2: Array = cands.duplicate(true)
	for c in c2:
		if c.set == pick.set and c.diff == pick.diff:
			c["last_played"] = _date(3600)
	var r2 := Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, c2, 50, runs, NOW)
	_ok(not _has(r2, pick), "vor 1 h gespielt -> raus")
	for c in c2:
		if c.set == pick.set and c.diff == pick.diff:
			c["last_played"] = _date(3 * 86400)
	_ok(_has(Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, c2, 50, runs, NOW), pick),
		"vor 3 Tagen gespielt -> bleibt")
	var runs2: Array = runs.duplicate(true)
	runs2.append({"set": pick.set, "diff": pick.diff, "stars": pick.stars, "accuracy": 0.9,
		"pp": 50.0, "grade": "B", "date": _date(600)})
	_ok(not _has(Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, cands, 50, runs2, NOW), pick),
		"Lauf in den letzten 24 h -> raus")
	var runs3: Array = runs.duplicate(true)
	runs3.append({"set": pick.set, "diff": pick.diff, "stars": pick.stars, "accuracy": 1.0,
		"pp": 99.0, "grade": "SS", "date": _date(30 * 86400)})
	_ok(not _has(Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, cands, 50, runs3, NOW), pick),
		"SS -> raus")
	var c4: Array = cands.duplicate(true)
	for c in c4:
		if c.set == pick.set and c.diff == pick.diff:
			c["best_grade"] = "SS"
	_ok(not _has(Recommender.suggest("mania", Recommender.LEVEL_CHALLENGE, c4, 50, runs, NOW), pick),
		"best_grade SS am Kandidaten -> raus")


func _test_variety() -> void:
	print("-- Abwechslung")
	var cands: Array = []
	for i in 8:  # ein Set mit 8 Diffs, dazu 4 andere Sets
		cands.append({"set": "same", "diff": "v%d" % i, "stars": 3.2 + 0.03 * i, "osu_mode": 3})
	for i in 4:
		cands.append({"set": "o%d" % i, "diff": "v", "stars": 3.1 + 0.1 * i, "osu_mode": 3})
	var runs := _profile("orbit", 3.0, 0.9)
	var out := Recommender.suggest("orbit", Recommender.LEVEL_CHALLENGE, cands, 5, runs, NOW)
	var same := 0
	for s in out:
		if s.set == "same":
			same += 1
	_ok(out.size() == 5 and same <= 1, "5 Vorschlaege, hoechstens 1x dasselbe Set (%d)" % same)
	var only := Recommender.suggest("orbit", Recommender.LEVEL_CHALLENGE, cands.slice(0, 8), 5, runs, NOW)
	_ok(only.size() == Recommender.MAX_PER_SET, "nur ein Set: hoechstens %d Diffs (%d)" % [Recommender.MAX_PER_SET, only.size()])


func _test_empty_and_playable() -> void:
	print("-- Leer, spielbar")
	for lv in Recommender.LEVELS:
		_ok(Recommender.suggest("mania", lv, [], 5, [], NOW).is_empty(), "keine Kandidaten (%s) -> leer" % lv)
	_ok(Recommender.suggest("mania", "push", _cands(), 0, [], NOW).is_empty(), "n=0 -> leer")
	var std := _cands(0)
	for m in ["mania", "trace", "rebound"]:
		_ok(Recommender.suggest(m, "challenge", std, 5, [], NOW).is_empty(), "%s: Standard-Diffs nicht spielbar" % m)
	for m in ["orbit", "rally", "dirigent"]:
		_ok(not Recommender.suggest(m, "challenge", std, 5, [], NOW).is_empty(), "%s: Standard-Diffs spielbar" % m)
	var nofit := [{"set": "x", "diff": "v", "stars": 0.0, "osu_mode": 3}]
	_ok(Recommender.suggest("mania", "easy", nofit, 5, [], NOW).is_empty(), "Sterne unbekannt -> leer")
	var too_hard := [{"set": "x", "diff": "v", "stars": 20.0, "osu_mode": 3}]
	_ok(Recommender.suggest("mania", "push", too_hard, 5, _profile("mania", 2.0, 0.9), NOW).is_empty(),
		"Push: aussichtslos schwer -> leer")
	_ok(Recommender.normalize_level("quatsch") == Recommender.LEVEL_CHALLENGE, "unknown level -> Challenge")


func _test_determinism() -> void:
	print("-- Determinismus")
	var runs := _profile("mania", 4.0, 0.9)
	var rev: Array = runs.duplicate()
	rev.reverse()
	var cands := _cands()
	var rc: Array = cands.duplicate()
	rc.reverse()
	for lv in Recommender.LEVELS:
		var a := Recommender.suggest("mania", lv, cands, 6, runs, NOW)
		var b := Recommender.suggest("mania", lv, cands, 6, runs, NOW)
		var c := Recommender.suggest("mania", lv, rc, 6, rev, NOW)
		_ok(a == b, "%s: gleiche Eingabe -> gleiche Liste" % lv)
		_ok(a == c, "%s: Reihenfolge der Eingabe egal" % lv)


# --- Stilprofil, Gruende, Seiten, Online ---

## Profil eines Spielers: 8 oft gespielte Jumpstream-Maps (175-185 BPM, Mapper
## "Kira", Electronic, SV) und 4 andere (Long Notes, 120 BPM).
func _style_player() -> Dictionary:
	var js: Array = []
	var ln: Array = []
	for i in 64:
		js.append([i * 110.0, i % 4, false])
		js.append([i * 110.0, (i + 2) % 4, false])
		ln.append([i * 300.0, i % 4, true])
	var sjs := Recommender.mania_style(js)
	var sl := Recommender.mania_style(ln)
	var feats := {}
	var runs: Array = []
	var plays := {}
	for i in 8:
		var k := "liked%d|d" % i
		feats[k] = {"artist": "Artist %d" % i, "title": "Night Drive" if i == 0 else "Liked %d" % i,
			"mapper": "Kira", "genre": "electronic", "language": "japanese", "tags": ["dnb", "kira"],
			"bpm": 175.0 + i * 1.5, "length": 150.0, "style": sjs, "sv": true}
		plays[k] = 6 if i == 0 else 3
		runs.append({"set": "liked%d" % i, "diff": "d", "stars": 2.8 + i * 0.05, "accuracy": 0.94, "grade": "A",
			"date": _date(86400 * 3 + i * 600)})
	for i in 4:
		var k2 := "other%d|d" % i
		feats[k2] = {"artist": "Other %d" % i, "title": "Other %d" % i, "mapper": "Zed %d" % i,
			"genre": "rock", "bpm": 120.0, "length": 90.0, "style": sl, "sv": false}
		runs.append({"set": "other%d" % i, "diff": "d", "stars": 2.2, "accuracy": 0.88, "grade": "B",
			"date": _date(86400 * 3 + 9000 + i * 600)})
	return {"t": Recommender.taste(runs, feats, plays), "runs": runs, "sjs": sjs, "sl": sl}


func _test_profile() -> void:
	print("-- Stilprofil")
	var p := _style_player()
	var t: Dictionary = p.t
	_ok(float(t.bpm_lo) >= 170.0 and float(t.bpm_hi) <= 190.0 and float(t.bpm_lo) <= float(t.bpm_hi),
		"BPM-Bereich aus den gespielten Maps (%.0f-%.0f)" % [t.bpm_lo, t.bpm_hi])
	_ok(float(t.stars_lo) >= 2.2 and float(t.stars_hi) <= 3.2 and float(t.stars_lo) < float(t.stars_hi),
		"Sterne-Bereich (%.2f-%.2f)" % [t.stars_lo, t.stars_hi])
	_ok(float(t.sv) > 0.6, "SV-Anteil (%.2f)" % t.sv)
	_ok(Recommender.top_key(t.mappers, t.total, 0.25) == "kira", "Lieblings-Mapper erkannt")
	_ok(Recommender.top_key(t.genres, t.total, 0.3) == "electronic", "Genre erkannt")
	_ok(Recommender.top_key(t.languages, t.total, 0.4) == "japanese", "Sprache erkannt")
	_ok(str(t.examples.jumpstream[1]) == "Night Drive", "Beispiel-Map = meistgespielte des Musters")
	_ok(Recommender.top_patterns(t)[0] == "Jumpstream", "staerkstes Muster zuerst")
	var txt := Recommender.profile_text(t)
	_ok(txt.begins_with("Your style: ") and "Jumpstream" in txt and "BPM" in txt and "SV" in txt,
		"Profil-Text kurz und konkret (%s)" % txt)
	_ok(txt.split(", ").size() <= 4, "Profil-Text hoechstens 4 Teile")
	var all_parts := Recommender.profile_parts(t)
	_ok(all_parts.has("Electronic") and all_parts.has("Japanese") and all_parts.has("mapped by kira"),
		"lange Fassung nennt Genre, Sprache, Mapper")
	_ok(Recommender.profile_text({}) == "" and Recommender.profile_parts({}).is_empty(), "ohne Daten kein Profil")
	var g := Recommender.genre_from_tags("drum and bass dnb japanese vocaloid", "")
	_ok(g.genre == "electronic" and g.language == "japanese", "Genre/Sprache aus Tags")
	g = Recommender.genre_from_tags("featured artist", "Touhou Project")
	_ok(g.genre == "video game", "Genre aus der Quelle")
	g = Recommender.genre_from_tags("something", "")
	_ok(g.genre == "" and g.language == "", "unbekannte Tags: kein Genre")
	_ok(Recommender.taste(p.runs, {}).is_empty(), "ohne Merkmale kein Profil")
	# Je Modus eigenes Profil: Laeufe eines anderen Modus aendern es nicht.
	var t2: Dictionary = _style_player().t
	_ok(str(t2) == str(t), "Profil deterministisch")


func _test_reasons() -> void:
	print("-- Gruende")
	var p := _style_player()
	var t: Dictionary = p.t
	var fit := {"set": "new1", "diff": "d", "stars": 3.0, "osu_mode": 3, "artist": "New", "mapper": "Kira",
		"genre": "electronic", "bpm": 180.0, "length": 150.0, "style": p.sjs, "sv": true}
	var m := Recommender.style_match(t, fit)
	_ok(str(m.reason).begins_with("fits: "), "Grund beginnt mit 'fits:' (%s)" % m.reason)
	_ok("180 BPM" in str(m.reason) and "Jumpstream" in str(m.reason), "Grund nennt BPM und Muster")
	_ok("like Night Drive" in str(m.reason), "Grund nennt eine Beispiel-Map")
	_ok((m.fits as Array).size() <= 3, "hoechstens 3 Teile")
	var own := fit.duplicate()
	own["set"] = "liked0"
	_ok(not ("like Night Drive" in str(Recommender.style_match(t, own).reason)), "Map nicht mit sich selbst verglichen")
	var off := {"set": "new2", "diff": "d", "stars": 3.0, "osu_mode": 3, "artist": "X", "mapper": "Y",
		"genre": "folk", "bpm": 110.0, "length": 40.0, "style": p.sl, "sv": false}
	var mo := Recommender.style_match(t, off)
	_ok(str(mo.reason) == "" and float(mo.bonus) < float(m.bonus) - 0.3, "unpassende Map: kein Grund, weniger Bonus")
	var by_mapper := {"set": "new3", "diff": "d", "stars": 3.0, "osu_mode": 3, "artist": "New", "mapper": "kira",
		"bpm": 150.0, "length": 150.0, "style": p.sjs}
	_ok("mapped by kira" in str(Recommender.style_match(t, by_mapper).reason), "Grund nennt den Mapper")
	var long_t: Dictionary = t.duplicate(true)
	long_t.examples["jumpstream"] = [9.0, "A Very Long Song Title That Never Ends At All", "zz"]
	var lr := str(Recommender.style_match(long_t, fit).reason)
	_ok(lr.length() < 70 and "…" in lr, "langer Titel gekuerzt (%s)" % lr)
	var out := Recommender.suggest("mania", "challenge", [off, fit], 2, p.runs, NOW, t)
	_ok(out.size() >= 1 and out[0].set == "new1" and str(out[0].style_reason).begins_with("fits: "),
		"Vorschlag traegt den Grund")


func _test_paging_novelty() -> void:
	print("-- Seiten und Neuheit")
	var runs := _profile("mania", 3.0, 0.90)
	var cands: Array = []
	for i in 40:
		cands.append({"set": "p%02d" % i, "diff": "d", "stars": 3.0 + (i % 7) * 0.1, "osu_mode": 3,
			"artist": "Artist %d" % i})
	var all := Recommender.suggest("mania", "challenge", cands, 5 * Recommender.PAGE_MAX, runs, NOW)
	_ok(all.size() == 30, "30 Vorschlaege fuer 6 Seiten (%d)" % all.size())
	_ok(Recommender.page_count(all.size(), 5) == 6 and Recommender.page_count(7, 5) == 2
		and Recommender.page_count(0, 5) == 1 and Recommender.page_count(999, 5) == Recommender.PAGE_MAX,
		"Seitenzahl")
	var p0 := Recommender.page_slice(all, 0, 5)
	var p1 := Recommender.page_slice(all, 1, 5)
	var overlap := 0
	for a in p0:
		if _has(p1, a):
			overlap += 1
	_ok(p0.size() == 5 and p1.size() == 5 and overlap == 0, "Seite 2 zeigt andere Maps als Seite 1")
	_ok(str(Recommender.page_slice(all, 6, 5)) == str(p0), "nach der letzten Seite wieder die erste")
	_ok(Recommender.page_slice(all.slice(0, 7), 1, 5).size() == 2, "letzte Seite darf kuerzer sein")
	_ok(Recommender.page_slice([], 0, 5).is_empty(), "leere Liste: leere Seite")
	var first5 := Recommender.suggest("mania", "challenge", cands, 5, runs, NOW)
	_ok(str(first5) == str(p0), "Seite 1 = die besten 5")
	# Neuheit: oft gezeigte, nie gespielte Maps ruecken nach hinten.
	var seen := {}
	for it in first5:
		seen["%s|%s" % [it.set, it.diff]] = 4
	var fresh := Recommender.suggest("mania", "challenge", cands, 5, runs, NOW, {}, seen)
	var again := 0
	for it in fresh:
		if _has(first5, it):
			again += 1
	_ok(fresh.size() == 5 and again <= 1, "nach 4 Mal Zeigen kommen andere Maps (%d gleich)" % again)
	var once := {}
	once["%s|%s" % [first5[0].set, first5[0].diff]] = 1
	var mild := Recommender.suggest("mania", "challenge", cands, 30, runs, NOW, {}, once)
	_ok(_has(mild, first5[0]), "einmal gezeigt: Map bleibt im Angebot")
	_ok(str(Recommender.suggest("mania", "challenge", cands, 5, runs, NOW, {}, seen)) == str(fresh),
		"Neuheit deterministisch")
	var huge := {}
	huge["%s|%s" % [first5[0].set, first5[0].diff]] = 999
	var capped := {}
	capped["%s|%s" % [first5[0].set, first5[0].diff]] = Recommender.NOVELTY_CAP
	_ok(str(Recommender.suggest("mania", "challenge", cands, 30, runs, NOW, {}, huge))
		== str(Recommender.suggest("mania", "challenge", cands, 30, runs, NOW, {}, capped)), "Neuheit gedeckelt")


## Fake-Antwort des Mirrors (kein Netz): Eintraege wie BeatmapMirror.parse_item.
func _fake_online() -> Array:
	var out: Array = []
	for i in 12:
		out.append({"id": 1000 + i, "title": "Online %d" % i, "artist": "OA %d" % (i % 9),
			"creator": "Kira" if i == 3 else "M%d" % i, "stars": 2.0 + i * 0.3,
			"star_list": [1.2 + i * 0.1, 2.0 + i * 0.3], "bpm": 180.0 if i == 3 else 140.0,
			"length_s": 150, "plays": 1000 * (i + 1), "genre": "electronic" if i == 3 else "rock",
			"sv": i == 3, "cover_url": "https://example.invalid/%d.jpg" % i, "preview_url": ""})
	return out


func _test_online() -> void:
	print("-- Online-Kandidaten")
	var p := _style_player()
	var t: Dictionary = p.t
	var runs := _profile("mania", 2.8, 0.90)
	var sk := Recommender.skill("mania", runs)
	var q := Recommender.online_query("mania", "challenge", sk, t)
	var rng := Recommender.star_range(sk, "challenge")
	_ok(int(q.osu_mode) == 3 and float(q.lo) < rng.x and float(q.hi) > rng.y,
		"Mania: 4K, Sterne-Bereich des Levels (%.2f-%.2f)" % [q.lo, q.hi])
	_ok(str(q.genre) == "electronic", "Suche kennt das Lieblings-Genre")
	var qo := Recommender.online_query("orbit", "challenge", Recommender.skill("orbit", _profile("orbit", 2.0, 0.9)), {}, 1.5)
	_ok(int(qo.osu_mode) == 0, "Orbit: osu!standard")
	_ok(float(qo.shift) == 1.5 and float(qo.target) > 3.0, "Orbit: Modus-Sterne auf osu!-Sterne verschoben")
	for m in ["rally", "dirigent", "trace", "rebound"]:
		_ok(int(Recommender.online_query(m, "easy", Recommender.skill(m, []), {}).osu_mode) == 3, "%s: 4K" % m)
	_ok(str(q.key) == str(Recommender.online_query("mania", "challenge", sk, t).key) and str(q.key) != str(qo.key),
		"Cache-Schluessel stabil und je Suche eigen")
	var res := _fake_online()
	var out := Recommender.online_rank(q, t, res, 6)
	_ok(not out.is_empty() and out.size() <= 6, "Kandidaten gefunden (%d)" % out.size())
	var in_range := true
	var artists := {}
	var dup_artist := false
	for o in out:
		if float(o.osu_stars) < float(q.lo) - 0.001 or float(o.osu_stars) > float(q.hi) + 0.001:
			in_range = false
		if artists.has(o.artist):
			dup_artist = true
		artists[o.artist] = true
	_ok(in_range, "nur Diffs im Sterne-Bereich")
	_ok(not dup_artist, "eine Map je Kuenstler")
	var q3 := q.duplicate()
	q3["lo"] = 2.6
	q3["hi"] = 3.2
	q3["target"] = 2.9
	var o3 := Recommender.online_rank(q3, t, res, 6)
	_ok(o3.size() >= 2 and int(o3[0].id) == 1003, "passende Map (BPM, Mapper, Genre) zuerst")
	_ok(str(o3[0].reason).begins_with("fits: ") and "180 BPM" in str(o3[0].reason), "Online-Grund aus dem Profil (%s)" % o3[0].reason)
	_ok(str(o3[o3.size() - 1].reason) != "", "jeder Online-Vorschlag hat einen Grund")
	_ok(o3[0].has("cover_url") and o3[0].has("preview_url") and float(o3[0].stars) > 0.0, "Daten fuer Cover, Vorhoeren, Sterne")
	var seen := {"online:1003": 4}
	var o4 := Recommender.online_rank(q3, t, res, 6, seen)
	_ok(int(o4[0].id) != 1003 or o4.size() == 1, "oft gezeigter Online-Vorschlag rueckt nach hinten")
	_ok(Recommender.online_rank(q, t, [], 6).is_empty(), "keine Antwort (offline): keine Gruppe")
	_ok(Recommender.online_rank(q3, {}, res, 6).size() >= 2, "ohne Profil: nur nach Sternen")
	var qs := q3.duplicate()
	qs["shift"] = 1.0
	_ok(is_equal_approx(float(Recommender.online_rank(qs, t, res, 1)[0].stars), float(Recommender.online_rank(qs, t, res, 1)[0].osu_stars) - 1.0),
		"Sterne in der Modus-Skala")
	_ok(str(Recommender.online_rank(q3, t, res, 6)) == str(o3), "Online-Reihenfolge deterministisch")
