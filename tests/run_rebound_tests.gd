extends SceneTree

## Headless-Tests fuer Rebound: Bahnen (Landung exakt zur Notenzeit, Start am
## vorigen Ende, Hold = Ruhe, Hereinfallen, Hoehe ~ Flugzeit^2 gedeckelt),
## Determinismus, Bot = SS, Replay deterministisch, Wertung = ManiaCore.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_rebound_tests.gd

var _passed := 0
var _failed := 0
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	print("Rebound-Tests: %d ok, %d fehlgeschlagen" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _near(a: float, b: float, label: String, eps: float = 0.0001) -> void:
	_ok(absf(a - b) <= eps, "%s (erwartet %f, war %f)" % [label, b, a])


## objects: Zeilen "x,y,time,type,hs,..." als String.
func _beatmap(objects: String) -> Beatmap:
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Metadata]\nTitle:T\nArtist:A\nVersion:V\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n%s" % objects
	var res := OsuParser.parse(txt)
	assert(res.ok)
	return res.beatmap


## Spaltenmitte x fuer 4K: col*128+64.
func _note(col: int, t: int, end: int = -1) -> String:
	var x := col * 128 + 64
	if end > t:
		return "%d,192,%d,128,0,%d:0:0:0:0:" % [x, t, end]
	return "%d,192,%d,1,0,0:0:0:0:" % [x, t]


func _map(list: Array) -> Beatmap:
	var lines: Array[String] = []
	for e in list:
		lines.append(_note(int(e[0]), int(e[1]), int(e[2]) if e.size() > 2 else -1))
	return _beatmap("\n".join(lines))


func _run() -> void:
	_test_landing()
	_test_height()
	_test_fall()
	_test_hold()
	_test_ball_state()
	_test_deterministic()
	_test_bot_ss()
	_test_bot_jitter()
	_test_replay()
	_test_replay_io()
	_test_anti_mash()


func _test_landing() -> void:
	var bm := _map([[0, 2000], [0, 2400], [0, 2700], [1, 2400], [3, 5000]])
	var f := ReboundFlight.from_beatmap(bm, 1000.0)
	_ok(f.seg_count(0) == 3, "Spalte 0: 3 Fluege")
	var s0: ReboundFlight.Seg = f.segs[0][0]
	var s1: ReboundFlight.Seg = f.segs[0][1]
	var s2: ReboundFlight.Seg = f.segs[0][2]
	_near(s0.t1, 2000.0, "Landung 1 = Notenzeit")
	_ok(s0.fall, "erste Note: Hereinfallen")
	_near(s0.t0, 1000.0, "Fallzeit 1000 ms")
	_ok(not s1.fall, "zweite Note: Luftflug")
	_near(s1.t0, 2000.0, "Start = vorige Landung")
	_near(s1.t1, 2400.0, "Landung 2 = Notenzeit")
	_near(s2.t0, 2400.0, "Start 3 = Landung 2")
	_near(s2.t1, 2700.0, "Landung 3 exakt")
	# Ball ist zur Notenzeit exakt auf dem Fell.
	for s in [s0, s1, s2]:
		var b := f.ball(0, s.t1)
		_near(b.h, 0.0, "Hoehe 0 bei Landung")
	# Alle Notenzeiten aller Spalten sind Landungen.
	for o in bm.hit_objects:
		var n := o as ManiaNote
		var arr: Array = f.segs[n.column]
		var found := false
		for s in arr:
			if (s as ReboundFlight.Seg).idx == bm.hit_objects.find(o) and is_equal_approx((s as ReboundFlight.Seg).t1, n.time):
				found = true
		_ok(found, "Note %d Spalte %d hat Landung" % [int(n.time), n.column])


func _test_height() -> void:
	var f := ReboundFlight.from_notes([[0.0, 0.0, 0, 0, false], [400.0, 400.0, 0, 1, false],
			[1000.0, 1000.0, 0, 2, false], [1100.0, 1100.0, 0, 3, false],
			[2500.0, 2500.0, 0, 4, false]], 4, 1000.0)
	var s_short: ReboundFlight.Seg = f.segs[0][3]   # 100 ms
	var s_mid: ReboundFlight.Seg = f.segs[0][1]     # 400 ms
	var s_long: ReboundFlight.Seg = f.segs[0][2]    # 600 ms
	var s_cap: ReboundFlight.Seg = f.segs[0][4]     # 1400 ms
	_ok(s_short.peak < s_mid.peak and s_mid.peak < s_long.peak, "Hoehe waechst mit Flugzeit")
	_near(s_mid.peak / s_long.peak, pow(400.0 / 600.0, 2.0), "Hoehe ~ Flugzeit^2", 0.001)
	_ok(s_cap.peak <= 1.0, "Gipfel gedeckelt")
	_near(ReboundFlight.peak_for(5000.0), 1.0, "Deckel 1.0")
	_ok(ReboundFlight.peak_for(10.0) >= ReboundFlight.MIN_PEAK, "Mindesthoehe (Jack sichtbar)")
	# Gipfel in der Mitte des Flugs.
	var mid := f.ball(0, 1000.0 + 50.0)
	_near(mid.h, s_short.peak, "Gipfel in der Mitte (100 ms)", 0.001)


func _test_fall() -> void:
	var bm := _map([[2, 3000], [2, 3500], [2, 3500 + 1601], [2, 9000]])
	var f := ReboundFlight.from_beatmap(bm, 800.0)
	var segs: Array = f.segs[2]
	_ok(segs[0].fall, "erste faellt")
	_ok(not segs[1].fall, "500 ms Pause: Luft")
	_ok(segs[2].fall, "Pause 1601 > MAX_AIR_MS: faellt")
	_near(segs[2].t0, 3500.0 + 1601.0 - 800.0, "Fallzeit Einstellung 800")
	_ok(segs[3].fall, "grosse Pause faellt")
	# Genau MAX_AIR_MS bleibt Luftflug.
	var f2 := ReboundFlight.from_notes([[0.0, 0.0, 0, 0, false], [1600.0, 1600.0, 0, 1, false]], 4)
	_ok(not f2.segs[0][1].fall, "Pause = MAX_AIR_MS: noch Luft")
	_near(f2.segs[0][1].peak, ReboundFlight.peak_for(1600.0), "Deckel bei 1600")
	# Fallzeit begrenzt 600..1600.
	_near(ReboundFlight.from_notes([[5000.0, 5000.0, 0, 0, false]], 4, 100.0).drop_ms, 600.0, "drop min")
	_near(ReboundFlight.from_notes([[5000.0, 5000.0, 0, 0, false]], 4, 9000.0).drop_ms, 1600.0, "drop max")
	# Hereinfallen: von ueber dem Gipfel auf 0.
	var b0 := f.ball(2, 3000.0 - 800.0)
	_ok(b0.kind == ReboundFlight.Kind.FALL and b0.h > 1.0, "Fall startet ueber dem Gipfel")
	var b1 := f.ball(2, 3000.0 - 400.0)
	_ok(b1.h < b0.h and b1.h > 0.0, "Fall sinkt")
	# Vor dem Fall: unsichtbar.
	_ok(f.ball(2, 1000.0).kind == ReboundFlight.Kind.HIDDEN, "vor Fall unsichtbar")


func _test_hold() -> void:
	var bm := _map([[1, 2000, 3000], [1, 3500], [1, 9000]])
	var f := ReboundFlight.from_beatmap(bm, 1000.0)
	var s0: ReboundFlight.Seg = f.segs[1][0]
	var s1: ReboundFlight.Seg = f.segs[1][1]
	_ok(s0.hold, "Hold erkannt")
	_near(s0.free, 3000.0, "Hold-Ende")
	_near(s1.t0, 3000.0, "naechster Flug startet am Hold-Ende")
	_near(s1.t1, 3500.0, "Landung nach Hold exakt")
	var mid := f.ball(1, 2500.0)
	_ok(mid.kind == ReboundFlight.Kind.REST, "im Hold: Ball liegt")
	_near(mid.h, 0.0, "liegt auf dem Fell")
	_near(mid.p, 0.5, "Ring-Fortschritt")
	var rel := f.ball(1, 3000.0 + 250.0)
	_ok(rel.kind == ReboundFlight.Kind.AIR and rel.h > 0.0, "nach Loslassen fliegt er")
	# Hold am Ende, danach Auslauf und dann unsichtbar.
	var f2 := ReboundFlight.from_beatmap(_map([[0, 1000, 2000]]), 1000.0)
	_ok(f2.ball(0, 2100.0).kind == ReboundFlight.Kind.EXIT, "Auslauf nach letztem Hold")
	_ok(f2.ball(0, 2000.0 + ReboundFlight.EXIT_MS + 5.0).kind == ReboundFlight.Kind.HIDDEN, "danach weg")


func _test_ball_state() -> void:
	var f := ReboundFlight.from_beatmap(_map([[0, 2000], [0, 2500]]), 1000.0)
	var b := f.ball(0, 2250.0)
	_ok(b.kind == ReboundFlight.Kind.AIR, "Luft")
	_near(b.until, 250.0, "bis Landung")
	_near(b.since, 250.0, "seit Abflug")
	_ok(b.h > 0.0, "ueber dem Fell")
	var lb := f.ball(0, 2000.0)
	_near(lb.since, 0.0, "since = 0 bei Landung")
	_ok(f.first_landing_at_or_after(0, 2001.0) == 1, "naechste Landung")
	_ok(f.first_landing_at_or_after(0, 2501.0) == -1, "keine weitere")
	_ok(f.last_landing_before(0, 1999.0) == -1, "noch keine")
	_ok(f.last_landing_before(0, 2000.0) == 0, "Landung eingeschlossen")


func _test_deterministic() -> void:
	var list := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := 1000
	for i in 120:
		t += rng.randi_range(60, 700)
		list.append([rng.randi_range(0, 3), t])
	var bm := _map(list)
	var a := ReboundFlight.from_beatmap(bm, 1000.0)
	var b := ReboundFlight.from_beatmap(bm, 1000.0)
	var same := true
	for tt in range(0, t + 2000, 37):
		for c in 4:
			var x := a.ball(c, float(tt))
			var y := b.ball(c, float(tt))
			if x.hash() != y.hash():
				same = false
	_ok(same, "gleiche Eingabe = gleiche Bahn")
	# Reihenfolge der Notenliste egal.
	var notes: Array = []
	for o in bm.hit_objects:
		var n := o as ManiaNote
		notes.append([n.time, n.end_time(), n.column, bm.hit_objects.find(o), n.is_hold])
	var rev := notes.duplicate()
	rev.reverse()
	var c1 := ReboundFlight.from_notes(notes, 4, 1000.0)
	var c2 := ReboundFlight.from_notes(rev, 4, 1000.0)
	var same2 := true
	for tt in range(0, t + 2000, 53):
		for c in 4:
			if c1.ball(c, float(tt)).hash() != c2.ball(c, float(tt)).hash():
				same2 = false
	_ok(same2, "Notenreihenfolge egal")
	# Jede Bahn hat zu jeder Landung Hoehe 0 und nie negative Hoehe.
	var neg := false
	for tt in range(0, t + 2000, 11):
		for c in 4:
			if float(a.ball(c, float(tt)).h) < -0.0001:
				neg = true
	_ok(not neg, "nie unter dem Fell")


## Spielt einen Event-Plan in einen ManiaCore.
func _play(bm: Beatmap, plan: Array) -> ManiaCore:
	var core := ManiaCore.new()
	core.setup(bm)
	var end := float(bm.hit_objects.back().end_time()) + 1000.0
	var i := 0
	var t := 0.0
	while t <= end:
		while i < plan.size() and float(plan[i].t) <= t:
			var ev: Dictionary = plan[i]
			if bool(ev.down):
				core.key_down(int(ev.lane), float(ev.t))
			else:
				core.key_up(int(ev.lane), float(ev.t))
			i += 1
		core.update(t)
		t += 4.0
	return core


func _stress_map() -> Beatmap:
	var list := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var t := 1500
	for i in 200:
		t += rng.randi_range(70, 450)
		var col := rng.randi_range(0, 3)
		if i % 9 == 0:
			var e := t + rng.randi_range(300, 900)
			list.append([col, t, e])
			t = e + 50
		else:
			list.append([col, t])
			if i % 7 == 0:
				list.append([(col + 1) % 4, t])
	return _map(list)


func _test_bot_ss() -> void:
	var bm := _stress_map()
	var core := _play(bm, ReboundReplay.bot_plan(bm))
	_near(core.accuracy(), 1.0, "Bot = 100 %")
	_ok(core.grade() == "SS", "Bot = SS")
	_ok(core.n_miss == 0 and core.n50 == 0, "Bot ohne Miss")
	_ok(core.max_combo == bm.hit_objects.size(), "volle Kombo")
	_ok(core.score >= 999000, "Score ~1M (%d)" % core.score)
	# Wertung unveraendert Mania: gleicher Plan ueber ManiaCore ergibt dasselbe.
	var core2 := _play(bm, ReboundReplay.bot_plan(bm))
	_ok(core2.score == core.score, "Wertung deterministisch")


func _test_bot_jitter() -> void:
	var bm := _stress_map()
	var core := _play(bm, ReboundReplay.bot_plan(bm, 3, 90.0, 0))
	_ok(core.accuracy() < 1.0 and core.accuracy() > 0.6, "Jitter: unter 100 %% (%f)" % core.accuracy())
	var core2 := _play(bm, ReboundReplay.bot_plan(bm, 3, 90.0, 0))
	_ok(core.score == core2.score and core.n_miss == core2.n_miss, "Jitter gleicher Seed = gleich")
	var core3 := _play(bm, ReboundReplay.bot_plan(bm, 1, 0.0, 6))
	_ok(core3.n_miss >= bm.hit_objects.size() / 6 - 2, "auto-miss laesst Noten aus (%d)" % core3.n_miss)


func _test_replay() -> void:
	var bm := _stress_map()
	var plan := ReboundReplay.bot_plan(bm, 9, 30.0, 0)
	# Aufnahme wie das Spiel: {t, lane, down}, ueber JSON gespeichert und neu geladen.
	var back = JSON.parse_string(JSON.stringify(plan))
	_ok(ReboundReplay.replay_ok(back), "Replay lesbar")
	var a := _play(bm, plan)
	var b := _play(bm, back)
	_ok(a.score == b.score and a.n300 == b.n300 and a.n_miss == b.n_miss and a.max_combo == b.max_combo,
			"Replay = gleiche Wertung")
	_ok(not ReboundReplay.replay_ok([]), "leer ist kein Replay")
	_ok(not ReboundReplay.replay_ok([[1, 2, 3]]), "Fremdformat abgelehnt")


func _test_replay_io() -> void:
	var bm := _map([[0, 2000], [1, 2500]])
	var plan := ReboundReplay.bot_plan(bm)
	var osz := "rebound_test_%d.osz" % Time.get_ticks_usec()
	ReboundReplay.save(osz, "V", plan, {"score": 1})
	_ok(ReboundReplay.exists(osz, "V"), "gespeichert")
	var r := ReboundReplay.load_replay(osz, "V")
	_ok(r.get("events", []).size() == plan.size() and str(r.meta.mode) == "rebound", "geladen mit Modus")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ReboundReplay.path_for(osz, "V")))
	_ok(ReplayStore.path_for_key("x") != ReboundReplay.path_for("x", "V"), "getrennt von Mania-Replays")


const RG := ReboundAntiMash


## Wie das Spiel: Anti-Mash-Schicht vor ManiaCore (rules=false: roh wie vor v2).
func _play_rules(bm: Beatmap, plan: Array, rules: bool) -> ManiaCore:
	var core := ManiaCore.new()
	core.setup(bm)
	var end := float(bm.hit_objects.back().end_time()) + 1000.0
	var i := 0
	var t := 0.0
	while t <= end:
		while i < plan.size() and float(plan[i].t) <= t:
			var ev: Dictionary = plan[i]
			if bool(ev.down):
				if rules:
					RG.wrong_key_check(core, int(ev.lane), float(ev.t))
				core.key_down(int(ev.lane), float(ev.t))
			else:
				core.key_up(int(ev.lane), float(ev.t))
			i += 1
		core.update(t)
		t += 4.0
	return core


## Spam: zu jeder Notenzeit alle vier Tasten.
func _spam_plan(bm: Beatmap) -> Array:
	var times := {}
	for o in bm.hit_objects:
		times[int(o.time)] = true
	var ks: Array = times.keys()
	ks.sort()
	var out: Array = []
	for t in ks:
		for c in 4:
			out.append({"t": t, "lane": c, "down": true})
		for c in 4:
			out.append({"t": t + 30, "lane": c, "down": false})
	return out


func _test_anti_mash() -> void:
	var bm := _stress_map()
	var plan := _spam_plan(bm)
	var before := _play_rules(bm, plan, false)
	var after := _play_rules(bm, plan, true)
	print("  Rebound Spam: vorher Acc %.1f%% (Misses %d), nachher Acc %.1f%% (Misses %d)" % [
		before.accuracy() * 100.0, before.n_miss, after.accuracy() * 100.0, after.n_miss])
	_ok(after.accuracy() < before.accuracy() - 0.2 and after.accuracy() < 0.6, "Spam: Acc faellt deutlich")
	_ok(after.n_miss > before.n_miss, "Spam gibt Misses")
	# Bot unberuehrt: SS auch mit Schicht.
	var bot := _play_rules(bm, ReboundReplay.bot_plan(bm), true)
	_ok(bot.n_miss == 0 and bot.accuracy() > 0.999, "Bot mit Schicht weiter SS")
	# Richtige + falsche gleichzeitig: Note in Spalte 0 bei 2000, Druck Spalte 2 bei 2000.
	var one := _map([[0, 2000], [0, 4000]])
	var c := ManiaCore.new()
	c.setup(one)
	var v := RG.wrong_key_check(c, 2, 1990.0)
	_ok(v == 0 and c.n_miss == 1 and c.combo == 0, "falsche Taste: Note sofort Miss")
	c.key_down(2, 1990.0)
	c.key_down(0, 2000.0)
	_ok(c.n_miss == 1 and c.n300 + c.n_max == 0, "danach richtige Taste trifft nicht mehr")
	# Richtig zuerst, dann falsch: Treffer bleibt.
	var d := ManiaCore.new()
	d.setup(one)
	RG.wrong_key_check(d, 0, 2000.0)
	d.key_down(0, 2000.0)
	var v2 := RG.wrong_key_check(d, 3, 2005.0)
	_ok(v2 == -1 and d.n_miss == 0 and d.combo == 1, "richtig dann falsch: Treffer bleibt")
	# Akkord richtig = Treffer.
	var chord := _map([[0, 2000], [3, 2000]])
	var e := ManiaCore.new()
	e.setup(chord)
	_ok(RG.wrong_key_check(e, 0, 2000.0) == -1, "Akkord: erste Taste ok")
	e.key_down(0, 2000.0)
	_ok(RG.wrong_key_check(e, 3, 2004.0) == -1, "Akkord: zweite Taste ok")
	e.key_down(3, 2004.0)
	_ok(e.n_miss == 0 and e.combo == 2, "Akkord richtig = 2 Treffer")
	# Leer-Druck ohne Note im Fenster = nichts.
	var f := ManiaCore.new()
	f.setup(one)
	_ok(RG.wrong_key_check(f, 2, 500.0) == -1 and f.n_miss == 0, "Leer-Druck (Note weit weg) = nichts")
	var g := ManiaCore.new()
	g.setup(one)
	_ok(RG.wrong_key_check(g, 2, 1700.0) == -1 and g.n_miss == 0, "Druck 300 ms vor Note: nichts (ausserhalb 50er)")
	# Replay-Regelversion.
	_ok(RG.replay_current([{"t": -1.0, "lane": -1, "down": false, "rules": RG.REPLAY_RULES}]), "Replay v2 akzeptiert")
	_ok(not RG.replay_current(plan), "altes Replay ohne Marke abgelehnt")
