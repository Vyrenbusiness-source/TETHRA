extends SceneTree

## Headless-Tests fuer den Empfehlungs-Kern (Recommender): Koennen je Modus
## (Anfaenger/Mittel/Profi), Stufen, Push (Top-pp), Filter, Determinismus.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_recommender_tests.gd

var _passed := 0
var _failed := 0
const NOW := 1800000000  # feste Testzeit (Unix)


func _initialize() -> void:
	print("=== TETHRA Recommender-Tests ===")
	_test_skill_levels()
	_test_few_runs_and_fails()
	_test_levels_bands()
	_test_push_top_pp()
	_test_filters()
	_test_variety()
	_test_empty_and_playable()
	_test_determinism()
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


## Laeufe ueber comfort-1 .. comfort+1 Sterne: Acc nach der Kurve eines Spielers mit Komfort c.
func _runs(mode: String, comfort: float, count: int = 20, age_days: int = 3) -> Array:
	var out: Array = []
	for i in count:
		var st := maxf(0.8, comfort - 1.0 + 2.0 * float(i) / float(count))
		var acc := clampf(0.97 - 0.02 * (st - comfort), 0.5, 0.995)
		var r := {"set": "s%d" % i, "diff": "d", "stars": st, "accuracy": acc,
			"failed": false, "grade": "A", "date": _date(age_days * 86400 + i * 60)}
		if mode == "mania":
			r["pp"] = 10.0 * st * st * pow(acc, 4.0)
		out.append(r)
	return out


func _cands(count: int = 40, osu_mode: int = 3) -> Array:
	var out: Array = []
	for i in count:
		out.append({"set": "c%d" % (i / 2), "diff": "v%d" % (i % 2),
			"stars": 0.8 + 0.25 * i, "osu_mode": osu_mode,
			"max_pp": 10.0 * pow(0.8 + 0.25 * i, 2.0)})
	return out


func _has(list: Array, pick: Dictionary) -> bool:
	for s in list:
		if s.set == pick.set and s.diff == pick.diff:
			return true
	return false


# --- Tests ---

func _test_skill_levels() -> void:
	print("-- Koennen je Modus")
	for m in Recommender.MODES:
		var nb := Recommender.skill(m, _runs(m, 1.5))
		var mid := Recommender.skill(m, _runs(m, 3.5))
		var pro := Recommender.skill(m, _runs(m, 6.0))
		_ok(nb.comfort < mid.comfort and mid.comfort < pro.comfort,
			"%s: Anfaenger < Mittel < Profi (%.2f < %.2f < %.2f)" % [m, nb.comfort, mid.comfort, pro.comfort])
		_ok(absf(pro.comfort - 6.0) < 0.8, "%s: Profi-Komfort nahe 6 (%.2f)" % [m, pro.comfort])
		_ok(pro.limit > pro.comfort, "%s: Grenze ueber Komfort" % m)
		_ok(Recommender.acc_at(pro, pro.comfort) > 0.96 and Recommender.acc_at(pro, pro.limit) < 0.93,
			"%s: Acc-Kurve 97 %% am Komfort, <93 %% an der Grenze" % m)


func _test_few_runs_and_fails() -> void:
	print("-- Wenige Laeufe, Fehlschlaege")
	var none := Recommender.skill("orbit", [])
	_ok(none.n == 0 and is_equal_approx(none.comfort, 1.5), "ohne Laeufe: Standardkurve")
	var one := Recommender.skill("orbit", [{"set": "a", "diff": "d", "stars": 6.0,
		"accuracy": 0.99, "date": _date(100)}])
	_ok(one.comfort > none.comfort and one.comfort < 4.0, "ein Lauf: vorsichtig (%.2f)" % one.comfort)
	var ok_runs := _runs("rally", 4.0, 10)
	var with_fail: Array = ok_runs.duplicate(true)
	for i in 12:  # Median: erst bei ueberwiegend Fehlschlaegen sichtbar
		with_fail.append({"set": "f%d" % i, "diff": "d", "stars": 6.0, "accuracy": 0.5,
			"failed": true, "grade": "F", "date": _date(10 + i)})
	_ok(Recommender.skill("rally", with_fail).comfort < Recommender.skill("rally", ok_runs).comfort,
		"Fehlschlaege senken das Komfort-Level")


func _test_levels_bands() -> void:
	print("-- Stufen")
	for m in Recommender.MODES:
		var runs := _runs(m, 3.5)
		var sk := Recommender.skill(m, runs)
		var easy := Recommender.suggest(m, Recommender.LEVEL_EASY, _cands(), 5, runs, NOW)
		var ch := Recommender.suggest(m, Recommender.LEVEL_CHALLENGE, _cands(), 5, runs, NOW)
		_ok(not easy.is_empty() and not ch.is_empty(), "%s: Easy and Challenge liefern Maps" % m)
		var easy_ok := true
		for s in easy:
			easy_ok = easy_ok and s.stars <= sk.comfort + 0.001 and s.expected_acc >= 0.96
		_ok(easy_ok, "%s: Easy lies unter Komfort" % m)
		var ch_ok := true
		for s in ch:
			ch_ok = ch_ok and s.stars >= sk.comfort - 0.001 and s.stars <= sk.limit + 0.001
		_ok(ch_ok, "%s: Challenge lies zwischen Komfort und Grenze" % m)
		_ok(easy[0].stars < ch[0].stars, "%s: Easy easier than Challenge" % m)
	_ok(Recommender.normalize_level("quatsch") == Recommender.LEVEL_CHALLENGE, "unknown level -> Challenge")


func _test_push_top_pp() -> void:
	print("-- Push")
	for m in Recommender.MODES:
		var runs := _runs(m, 4.0)
		var sk := Recommender.skill(m, runs)
		var push := Recommender.suggest(m, Recommender.LEVEL_PUSH, _cands(), 5, runs, NOW)
		_ok(not push.is_empty(), "%s: Push liefert Kandidaten" % m)
		var good := true
		for s in push:
			good = good and s.stars >= sk.comfort - 0.001 and s.expected_acc >= 0.85
			good = good and (("would be top" in s.reason) or ("new top pp" in s.reason))
		_ok(good, "%s: Push an/ueber Komfort mit Text-Grund" % m)
	# Mania: neue Top-pp, wenn die Leistung die bisherige Bestleistung schlaegt.
	var mr := _runs("mania", 4.0)
	var top_old: float = float(Recommender.skill("mania", mr).top[0])
	var p := Recommender.suggest("mania", Recommender.LEVEL_PUSH, _cands(), 3, mr, NOW)
	_ok(p[0].expected_perf > top_old and "new top pp" in p[0].reason,
		"Mania-Push: neue Top-pp (%s)" % p[0].reason)
	_ok("pp" in p[0].reason, "Mania reason in pp")
	var op := Recommender.suggest("orbit", Recommender.LEVEL_PUSH, _cands(), 3, _runs("orbit", 4.0), NOW)
	_ok("pts" in op[0].reason, "Orbit reason in pts")


func _test_filters() -> void:
	print("-- Filter")
	var runs := _runs("mania", 3.5)
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
		cands.append({"set": "same", "diff": "v%d" % i, "stars": 3.5 + 0.05 * i, "osu_mode": 3})
	for i in 4:
		cands.append({"set": "o%d" % i, "diff": "v", "stars": 3.4 + 0.1 * i, "osu_mode": 3})
	var out := Recommender.suggest("orbit", Recommender.LEVEL_CHALLENGE, cands, 5, _runs("orbit", 3.0), NOW)
	var same := 0
	for s in out:
		if s.set == "same":
			same += 1
	_ok(out.size() == 5 and same <= 1, "5 Vorschlaege, hoechstens 1x dasselbe Set (%d)" % same)
	var only := Recommender.suggest("orbit", Recommender.LEVEL_CHALLENGE, cands.slice(0, 8), 5, _runs("orbit", 3.0), NOW)
	_ok(only.size() == Recommender.MAX_PER_SET, "nur ein Set: hoechstens %d Diffs (%d)" % [Recommender.MAX_PER_SET, only.size()])


func _test_empty_and_playable() -> void:
	print("-- Leer, spielbar")
	for lv in Recommender.LEVELS:
		_ok(Recommender.suggest("mania", lv, [], 5, [], NOW).is_empty(), "keine Kandidaten (%s) -> leer" % lv)
	_ok(Recommender.suggest("mania", "push", _cands(), 0, [], NOW).is_empty(), "n=0 -> leer")
	var std := _cands(40, 0)
	for m in ["mania", "trace", "rebound"]:
		_ok(Recommender.suggest(m, "challenge", std, 5, [], NOW).is_empty(), "%s: Standard-Diffs nicht spielbar" % m)
	for m in ["orbit", "rally", "dirigent"]:
		_ok(not Recommender.suggest(m, "challenge", std, 5, [], NOW).is_empty(), "%s: Standard-Diffs spielbar" % m)
	var nofit := [{"set": "x", "diff": "v", "stars": 0.0, "osu_mode": 3}]
	_ok(Recommender.suggest("mania", "easy", nofit, 5, [], NOW).is_empty(), "Sterne unbekannt -> leer")
	var too_hard := [{"set": "x", "diff": "v", "stars": 20.0, "osu_mode": 3}]
	_ok(Recommender.suggest("mania", "push", too_hard, 5, _runs("mania", 2.0), NOW).is_empty(),
		"Push: aussichtslos schwer -> leer")


func _test_determinism() -> void:
	print("-- Determinismus")
	var runs := _runs("mania", 4.0)
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
