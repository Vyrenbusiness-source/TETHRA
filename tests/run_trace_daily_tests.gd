extends SceneTree

## Headless-Tests Daily Trace (scripts/trace/trace_daily.gd).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	var pool := []
	for id in [900, 12, 5, 77, 31, 4000, 8]:
		pool.append({ "key": "%012d" % id, "set_id": id })
	var rev := pool.duplicate()
	rev.reverse()
	_check(TraceDaily.pick("2026-11-12", pool).key == TraceDaily.pick("2026-11-12", pool).key, "gleicher Tag = gleiche Map")
	_check(TraceDaily.pick("2026-11-12", pool).key == TraceDaily.pick("2026-11-12", rev).key, "Reihenfolge der Liste egal")
	var seen := {}
	for d in 28:
		seen[TraceDaily.pick(TraceDaily.key_of_number(20000 + d), pool).key] = true
	_check(seen.size() >= 4, "Tage streuen ueber die Liste (%d)" % seen.size())
	_check(TraceDaily.pick("2026-11-12", []).is_empty(), "leere Liste = {}")
	_check(TraceDaily.day_key(0) == "1970-01-01" and TraceDaily.day_key(86400 * 365) == "1971-01-01", "day_key")
	_check(TraceDaily.day_number("2026-03-01") - TraceDaily.day_number("2026-02-28") == 1, "Monatsgrenze")
	_check(TraceDaily.key_of_number(TraceDaily.day_number("2026-11-12")) == "2026-11-12", "key<->number")
	_check(TraceDaily._set_key("9 a.osz") < TraceDaily._set_key("10 b.osz"), "Set-ID numerisch sortiert")
	_check(TraceDaily.online_pool([{ "id": 0 }, { "id": 5, "title": "x" }]).size() == 1, "online_pool ignoriert id 0")

	var st := { "days": {} }
	_check(TraceDaily.streak(st, "2026-11-12") == 0, "Serie leer = 0")
	_check(TraceDaily.start_attempt(st, "2026-11-10", "a"), "Versuch 1")
	_check(not TraceDaily.start_attempt(st, "2026-11-10", "b"), "zweiter Versuch am Tag zaehlt nicht")
	_check(st.days["2026-11-10"].key == "a", "erste Map bleibt")
	TraceDaily.start_attempt(st, "2026-11-11", "a")
	_check(TraceDaily.streak(st, "2026-11-11") == 2, "Serie 2")
	_check(TraceDaily.streak(st, "2026-11-12") == 2, "heute offen: Serie bleibt")
	TraceDaily.start_attempt(st, "2026-11-12", "a")
	_check(TraceDaily.streak(st, "2026-11-12") == 3, "Serie 3")
	_check(TraceDaily.streak(st, "2026-11-14") == 0, "Luecke bricht Serie")
	TraceDaily.start_attempt(st, "2026-10-31", "a")
	TraceDaily.start_attempt(st, "2026-11-01", "a")
	_check(TraceDaily.best_streak(st) == 3, "beste Serie %d" % TraceDaily.best_streak(st))
	_check(TraceDaily.set_score(st, "2026-11-12", 4200) and not TraceDaily.set_score(st, "2026-11-12", 9), "Score nur einmal")
	_check(not TraceDaily.set_score(st, "2030-01-01", 1), "Score ohne Versuch nein")

	var p := "user://trace_daily_test.cfg"
	TraceDaily.save_state(st, p)
	var back := TraceDaily.load_state(p)
	_check(back.days.size() == st.days.size() and int(back.days["2026-11-12"].score) == 4200, "speichern/laden")
	DirAccess.remove_absolute(p)

	var i1 := TraceDaily.picture("2026-11-12", 3)
	var i2 := TraceDaily.picture("2026-11-12", 3)
	_check(i1.get_width() == TraceDaily.PIC_SIZE and i1.get_data() == i2.get_data(), "Tages-Bild deterministisch")
	_check(i1.get_data() != TraceDaily.picture("2026-11-13", 3).get_data(), "Bild je Tag verschieden")
	print("FAILED: ", _failed if _failed else "none")
	quit(1 if _failed else 0)
