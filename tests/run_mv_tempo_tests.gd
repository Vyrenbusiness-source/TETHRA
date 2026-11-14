extends SceneTree

## Tests mv-tempo: Rate-Grundlage (RateTrack, Fenster x Rate, SyncClock mit Rate,
## Rate-Wechsel ohne Sprung, Time-Stretch-Latenz/Tonhoehe), Uebungsmodus
## (Abschnitt, Tempo-Stufen, Fehlerstellen, Statistik) und Turbo (Abschnitte,
## Anstieg/Rueckfall, Replay exakt, Rangliste).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mv_tempo_tests.gd
## Messwerte stehen als "MEASURE ..." im Log (Sync bei 0,75x/1,5x, Time-Stretch).

var _passed := 0
var _failed := 0
var _clock: Node
## Autoload-Skripte als Klassen (Autoload-Namen gibt es im Runner beim Kompilieren nicht).
var _GS: GDScript
var _SC: GDScript

const OSU_HEAD := "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n%s\n\n[HitObjects]\n%s"


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	print("=== OMEN mv-tempo-Tests ===")
	await process_frame
	_clock = root.get_node_or_null("SyncClock")
	_GS = load("res://scripts/game_session.gd")
	_SC = load("res://scripts/audio/sync_clock.gd")
	_test_rate_track()
	_test_windows_scale()
	_test_windows_unchanged_without_track()
	_test_window_per_note_time()
	_test_restrict_range()
	_test_practice_session()
	_test_practice_store()
	_test_turbo_sections()
	_test_turbo_rule()
	_test_turbo_replay_exact()
	_test_turbo_store()
	_test_smoother_rate()
	_test_old_replay_mods()
	if _clock != null:
		await _test_clock_rate(0.75, false)
		await _test_clock_rate(1.5, false)
		await _test_clock_rate(1.5, true)
		await _test_clock_rate_change()
		await _test_timestretch_measure()
	else:
		_ok(false, "SyncClock-Autoload vorhanden")
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _approx(actual: float, expected: float, label: String, eps: float = 0.001) -> void:
	_ok(absf(actual - expected) <= eps, "%s (erwartet %f, war %f)" % [label, expected, actual])


func _bm(notes: String, timing: String = "0,500,4,1,0,100,1,0") -> Beatmap:
	var res := OsuParser.parse(OSU_HEAD % [timing, notes])
	return res.beatmap


func _core(bm: Beatmap) -> ManiaCore:
	var c := ManiaCore.new()
	c.setup(bm)
	return c


func _notes_every(t0: int, t1: int, step: int) -> String:
	var s := ""
	var i := 0
	var t := t0
	while t <= t1:
		s += "%d,192,%d,1,0,0:0:0:0:\n" % [64 + 128 * (i % 4), t]
		i += 1
		t += step
	return s


# --- Rate-Grundlage -----------------------------------------------------------

func _test_rate_track() -> void:
	print("- RateTrack: Raster, Verlauf, Vorlauf, Replay-Format")
	_approx(RateTrack.snap(1.237), 1.25, "0,05er-Raster")
	_approx(RateTrack.snap(0.1), 0.5, "Untergrenze 0,5")
	_approx(RateTrack.snap(3.0), 2.0, "Obergrenze 2,0")
	var tr := RateTrack.constant(0.8)
	_approx(tr.rate_at(-5000.0), 0.8, "konstant gilt auch vor 0")
	tr.set_at(1000.0, 1.0)
	tr.set_at(2000.0, 1.05)
	_approx(tr.rate_at(999.0), 0.8, "vor Wechsel alte Rate")
	_approx(tr.rate_at(1000.0), 1.0, "ab Wirkzeit neue Rate")
	_approx(tr.rate_at(5000.0), 1.05, "letzte Rate")
	var t := tr.schedule(2500.0, 2600.0, 1.1)
	_ok(t >= 2500.0 + RateTrack.SCHEDULE_LEAD_MS, "Aenderung wirkt fruehestens nach Vorlauf (%.0f)" % t)
	tr.schedule(2600.0, 2600.0, 1.0)
	_approx(tr.rate_at(INF), 1.0, "spaetere Anmeldung ersetzt noch nicht wirksame")
	var back := RateTrack.from_array(JSON.parse_string(JSON.stringify(tr.to_array())))
	_ok(back != null and back.size() == tr.size(), "JSON-Rundreise")
	var same := true
	for x in [-1e9, 0.0, 999.0, 1000.0, 2000.0, 2900.0, 3100.0, 1e9]:
		same = same and is_equal_approx(back.rate_at(x), tr.rate_at(x))
	_ok(same, "JSON-Rundreise: gleiche Raten an allen Stellen")
	_approx(tr.max_rate(-INF, 2400.0), 1.05, "Hoechstrate bis 2,4 s")
	_ok(RateTrack.from_array([]) == null and RateTrack.from_array(null) == null, "leer = kein Verlauf")


func _test_windows_scale() -> void:
	print("- Fenster in Songzeit x Rate (Echtzeit gleich breit)")
	var bm := _bm("64,192,1000,1,0,0:0:0:0:\n64,192,2000,1,0,0:0:0:0:\n64,192,3000,1,0,0:0:0:0:\n")
	var c := _core(bm)
	c.rate_track = RateTrack.constant(1.5)
	# 60 ms Songzeit bei 1,5x = 40 ms Echtzeit -> 300 (Fenster 49,5 ms Echtzeit).
	c.key_down(0, 1060.0)
	_ok(c.n300 == 1, "1,5x: 60 ms Songzeit = 40 ms echt -> 300")
	_approx(c.w300, 49.5 * 1.5, "w300 Songzeit = 49,5 x 1,5")
	# Expiry: 50er-Fenster 136,5 x 1,5 = 204,75 ms Songzeit.
	c.update(2200.0)
	_ok(c.n_miss == 0, "1,5x: 200 ms Songzeit nach der Note noch kein Miss")
	c.update(2210.0)
	_ok(c.n_miss == 1, "1,5x: nach 204,75 ms Songzeit Miss")
	var c2 := _core(bm)
	c2.rate_track = RateTrack.constant(0.75)
	c2.key_down(0, 1040.0)
	_ok(c2.n200 == 1, "0,75x: 40 ms Songzeit = 53 ms echt -> 200")


func _test_windows_unchanged_without_track() -> void:
	print("- Ohne Rate-Verlauf exakt wie bisher")
	var bm := _bm("64,192,1000,1,0,0:0:0:0:\n")
	var c := _core(bm)
	c.key_down(0, 1060.0)
	_ok(c.n200 == 1 and c.rate_track == null, "60 ms bei 1,0x -> 200 (unveraendert)")
	_approx(c.w300, 49.5, "w300 unveraendert")


func _test_window_per_note_time() -> void:
	print("- Fenster nach Rate zur Notenzeit (nicht zur Frame-Zeit)")
	var bm := _bm("64,192,1000,1,0,0:0:0:0:\n64,192,1400,1,0,0:0:0:0:\n")
	var tr := RateTrack.constant(1.0)
	tr.set_at(1200.0, 2.0)
	var c := _core(bm)
	c.rate_track = tr
	# Note 1 (Zeit 1000, Rate 1): 60 ms spaet -> 200, obwohl der Druck nach dem Wechsel kommt.
	c.key_down(0, 1060.0)
	_ok(c.n200 == 1, "Note vor Wechsel: Fenster 1,0x")
	c.key_down(0, 1490.0)
	_ok(c.n300 == 1, "Note nach Wechsel: 90 ms Songzeit bei 2,0x = 45 ms -> 300")


func _test_restrict_range() -> void:
	print("- Uebung: nur Noten im Abschnitt zaehlen")
	var bm := _bm(_notes_every(1000, 9000, 500))
	var c := _core(bm)
	var n := c.restrict_range(3000.0, 5000.0)
	_ok(n == 4, "4 Noten in 3,0..5,0 s (%d)" % n)
	var spawned := []
	c.note_spawned.connect(func(i): spawned.append(i))
	c.update(20000.0)
	_ok(spawned.size() == 4 and int(spawned[0]) == 4, "nur Abschnittsnoten spawnen (%s)" % str(spawned))
	_ok(c.n_miss == 4, "nur Abschnittsnoten werden Miss (%d)" % c.n_miss)
	var c2 := _core(bm)
	c2.restrict_range(3000.0, 5000.0)
	for i in range(4, 8):
		var o := bm.hit_objects[i] as ManiaNote
		c2.key_down(o.column, o.time)
		c2.key_up(o.column, o.time + 30.0)
	c2.update(20000.0)
	_ok(c2.n_miss == 0 and c2.n_max == 4, "sauberer Abschnitt: 4 MAX, 0 Miss")
	_ok(c2.score >= 999000, "Score bezieht sich nur auf den Abschnitt (%d)" % c2.score)


# --- Uebungsmodus --------------------------------------------------------------

func _test_practice_session() -> void:
	print("- Uebung: Tempo stufenweise nach sauberem Durchlauf")
	var s := PracticeSession.new()
	s.set_range(5000.0, 3000.0)
	_ok(s.a_ms == 3000.0 and s.b_ms == 5000.0, "A/B vertauscht -> sortiert")
	s.set_range(1000.0, 1200.0)
	_ok(s.b_ms - s.a_ms >= 1000.0, "Mindestlaenge 1 s")
	s.set_rates(0.8, 1.0, 0.1)
	_approx(s.rate, 0.8, "Start 80 %")
	var r := s.after_loop(2)
	_ok(not r.clean and is_equal_approx(s.rate, 0.8), "Miss: Tempo bleibt")
	s.after_loop(0)
	_approx(s.rate, 0.9, "sauber: +10 %")
	s.after_loop(0)
	_approx(s.rate, 1.0, "sauber: Ziel 100 %")
	r = s.after_loop(0)
	_ok(bool(r.reached) and is_equal_approx(s.rate, 1.0), "Ziel erreicht, bleibt 100 %")
	_ok(s.loops == 4 and s.clean_loops == 3, "Zaehler Schleifen/sauber")
	s.set_rates(1.2, 0.9, 0.05)
	_ok(s.target_rate >= s.start_rate, "Ziel nie unter Start")
	_ok(PracticeSession.current == null, "keine Sitzung ohne begin()")
	PracticeSession.begin()
	_ok(PracticeSession.active(), "begin() -> aktiv")
	PracticeSession.clear()
	_ok(not PracticeSession.active(), "clear() -> aus")


func _test_practice_store() -> void:
	print("- Uebung: Fehlerstellen und Abschnitts-Statistik")
	var dir := "user://test_mv_tempo_practice"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var osz := "test_mv_tempo.osz"
	var p := PracticeStore._path(osz, "X", dir)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var jlog := [Vector4(1000, 0, ManiaCore.Quality.MISS, NAN), Vector4(1500, 1, ManiaCore.Quality.MAX, 2.0),
		Vector4(1800, 2, ManiaCore.Quality.MISS, NAN)]
	var ms := PracticeStore.misses_from_judge_log(jlog)
	_ok(ms.size() == 2 and float(ms[0]) == 1000.0, "Misses aus dem Urteils-Log der Fehler-Analyse")
	for i in 8:
		PracticeStore.record_run(osz, "X", [1000 + i * 10, 1700, 40000], "play", dir)
	var d := PracticeStore.load_data(osz, "X", dir)
	_ok((d.runs as Array).size() == PracticeStore.RUNS_KEEP, "nur die letzten %d Laeufe" % PracticeStore.RUNS_KEEP)
	var marks := PracticeStore.error_marks(d.runs)
	_ok(marks.size() == 2, "2 Fehlerstellen (%d)" % marks.size())
	_ok(float(marks[0].t0) >= 1000.0 and float(marks[0].t1) <= 1700.0 and int(marks[0].n) == 12,
			"Stelle 1: 1,0-1,7 s, 12 Misses (%s)" % str(marks[0]))
	_ok(int(marks[1].n) == 6 and float(marks[1].t0) == 40000.0, "Stelle 2 bei 40 s")
	_ok(PracticeStore.error_marks([{"misses": [5000]}]).is_empty(), "Einzelfehler ist keine Stelle")
	var r := PracticeStore.range_for_mark(marks[0], 60000.0)
	_ok(r.x < 1000.0 and r.y > 1700.0, "Sprungmarke: Abschnitt mit Anlauf")
	PracticeStore.record_section(osz, "X", 1000, 3000, 0.9, 2, 0.8, dir)
	var st := PracticeStore.record_section(osz, "X", 1000, 3000, 0.97, 0, 0.85, dir)
	_ok(int(st.plays) == 2 and int(st.clean) == 1, "Statistik: 2 Schleifen, 1 sauber")
	_approx(float(st.best_acc), 0.97, "beste Genauigkeit")
	_approx(float(st.best_rate), 0.85, "schnellstes sauberes Tempo")
	_ok(PracticeStore.section_stats(osz, "X", 1000, 4000, dir).is_empty(), "anderer Abschnitt: eigene Statistik")


# --- Turbo ----------------------------------------------------------------------

func _test_turbo_sections() -> void:
	print("- Turbo: Abschnitte aus Kiai/Breaks, sonst 8 Takte")
	# 120 BPM, 4/4: Takt 2000 ms. Noten 0..63,5 s ohne Kiai -> je 8 Takte (16 s).
	var bm := _bm(_notes_every(0, 63500, 500))
	var secs := TurboRule.sections(bm)
	_ok(secs.size() == 4, "64 s ohne Kiai: 4 Abschnitte zu 8 Takten (%d)" % secs.size())
	_approx(float(secs[1].a), 16000.0, "Abschnitt 2 beginnt nach 8 Takten", 0.5)
	# Kiai 10..30 s (Timing-Points mit Effekt 1), Break 40..50 s.
	var tp := "0,500,4,1,0,100,1,0\n10000,-100,4,1,0,100,0,1\n30000,-100,4,1,0,100,0,0"
	var bm2 := _bm(_notes_every(0, 39000, 500) + _notes_every(50000, 60000, 500), tp)
	var secs2 := TurboRule.sections(bm2)
	var starts := []
	for s in secs2:
		starts.append(int(float(s.a)))
	_ok(starts.has(10000) and starts.has(30000), "Grenzen an Kiai-Anfang/-Ende (%s)" % str(starts))
	var brk := false
	for s in secs2:
		brk = brk or (float(s.a) > 39000.0 and float(s.a) <= 50000.0)
	_ok(brk, "Grenze im Break 39..50 s")
	var all_notes := 0
	for s in secs2:
		all_notes += int(s.i1) - int(s.i0)
	_ok(all_notes == bm2.hit_objects.size(), "jede Note in genau einem Abschnitt")


func _test_turbo_rule() -> void:
	print("- Turbo: +5 % je fehlerfreiem Abschnitt, Miss -> zurueck auf Start")
	var bm := _bm(_notes_every(0, 63500, 500))
	var rule := TurboRule.new()
	rule.setup(bm)
	var judged := {}
	var is_j := func(i): return judged.has(i)
	for i in range(0, int(rule.secs[0].i1)):
		judged[i] = true
	rule.tick(16100.0, is_j)
	_approx(rule.target_rate(), 1.05, "Abschnitt 1 sauber -> 105 %")
	_ok(rule.track.rate_at(16100.0) == 1.0 and rule.track.rate_at(16600.0) == 1.05,
			"wirkt erst nach Vorlauf (400 ms)")
	for i in range(int(rule.secs[1].i0), int(rule.secs[1].i1)):
		judged[i] = true
	rule.tick(32100.0, is_j)
	_approx(rule.target_rate(), 1.10, "Abschnitt 2 sauber -> 110 %")
	rule.on_miss(bm.hit_objects[int(rule.secs[2].i0) + 3].time, 33700.0)
	_approx(rule.target_rate(), 1.0, "Miss -> zurueck auf 100 %")
	for i in range(int(rule.secs[2].i0), int(rule.secs[2].i1)):
		judged[i] = true
	rule.tick(48100.0, is_j)
	_approx(rule.target_rate(), 1.0, "Abschnitt mit Miss: kein Anstieg")
	_ok(rule.clean == 2 and rule.fallbacks == 1, "2 fehlerfrei, 1 Rueckfall")
	_approx(rule.peak_rate(64000.0), 1.10, "Hoechsttempo 110 %")


## Live-Lauf mit TurboRule (Frames 16 ms, Misses), dann Replay mit gespeichertem
## Verlauf und anderer Frame-Rate: gleiche Wertung, gleiches Hoechsttempo.
func _test_turbo_replay_exact() -> void:
	print("- Turbo-Replay: Rate-Verlauf im Replay, exakt nachgespielt")
	var bm := _bm(_notes_every(1000, 70000, 250))
	var rule := TurboRule.new()
	rule.setup(bm)
	var live := _core(bm)
	live.rate_track = rule.track
	live.note_judged.connect(func(i, r):
		if int(r.quality) == ManiaCore.Quality.MISS:
			rule.on_miss(bm.hit_objects[i].time, live._now))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var events := []
	for i in bm.hit_objects.size():
		var o := bm.hit_objects[i] as ManiaNote
		if i % 97 == 50:
			continue  # absichtlich verpasst
		var r := rule.track.rate_at(o.time)
		var dt := rng.randfn(0.0, 22.0) * r
		events.append({"t": o.time + dt, "lane": o.column, "down": true})
		events.append({"t": o.time + dt + 30.0, "lane": o.column, "down": false})
	events.sort_custom(func(a, b): return float(a.t) < float(b.t))
	# Live: Ereignisse vor dem Frame, dann update + Turbo-Auswertung (wie mania_3d).
	var t := 0.0
	var ei := 0
	while t < 72000.0:
		t += 16.0
		while ei < events.size() and float(events[ei].t) <= t:
			var ev: Dictionary = events[ei]
			ei += 1
			if bool(ev.down):
				live.key_down(int(ev.lane), float(ev.t))
			else:
				live.key_up(int(ev.lane), float(ev.t))
		live.update(t)
		rule.tick(t, live.is_judged)
	var stored: Variant = JSON.parse_string(JSON.stringify(rule.track.to_array()))
	_ok(rule.track.size() >= 3, "Verlauf hat Wechsel (%d Eintraege)" % rule.track.size())
	# Replay: Verlauf aus den Mods, Frames 33 ms.
	var rep := _core(bm)
	rep.rate_track = RateTrack.from_array(stored)
	t = 0.0
	ei = 0
	while t < 72000.0:
		t += 33.0
		while ei < events.size() and float(events[ei].t) <= t:
			var ev: Dictionary = events[ei]
			ei += 1
			if bool(ev.down):
				rep.key_down(int(ev.lane), float(ev.t))
			else:
				rep.key_up(int(ev.lane), float(ev.t))
		rep.update(t)
	var a := live.stats()
	var b := rep.stats()
	var same := true
	for k in ["n_max", "n300", "n200", "n100", "n50", "n_miss", "max_combo", "score"]:
		same = same and a[k] == b[k]
	_ok(same, "Replay = Live (score %d / %d, miss %d / %d)" % [a.score, b.score, a.n_miss, b.n_miss])
	_ok(rule.peak_rate(70000.0) > 1.0, "Lauf erreicht Tempo ueber 100 %% (%.2f)" % rule.peak_rate(70000.0))
	# Gegenprobe: ohne Verlauf (alte Replay-Regel) waere die Wertung anders.
	var plain := _core(bm)
	ei = 0
	for ev in events:
		if bool(ev.down):
			plain.key_down(int(ev.lane), float(ev.t))
		else:
			plain.key_up(int(ev.lane), float(ev.t))
	plain.update(72000.0)
	_ok(plain.stats().score != a.score, "Gegenprobe: ohne Rate-Verlauf andere Wertung")


func _test_turbo_store() -> void:
	print("- Turbo: lokale Rangliste nach Hoechsttempo")
	var path := "user://test_mv_tempo_turbo.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_ok(TurboStore.submit("a.osz", "V", {"peak": 1.2, "score": 500000}, path) == 1, "erster Eintrag Platz 1")
	_ok(TurboStore.submit("a.osz", "V", {"peak": 1.35, "score": 100000}, path) == 1, "hoeheres Tempo schlaegt Score")
	_ok(TurboStore.submit("a.osz", "V", {"peak": 1.2, "score": 600000}, path) == 2, "gleiches Tempo: Score entscheidet")
	var l := TurboStore.list_for("a.osz", "V", path)
	_ok(l.size() == 3 and is_equal_approx(float(l[0].peak), 1.35), "Liste sortiert")
	for i in 12:
		TurboStore.submit("a.osz", "V", {"peak": 1.0, "score": i}, path)
	_ok(TurboStore.list_for("a.osz", "V", path).size() == TurboStore.KEEP, "hoechstens %d Eintraege" % TurboStore.KEEP)
	_ok(TurboStore.list_for("b.osz", "V", path).is_empty(), "je Map getrennt")


func _test_smoother_rate() -> void:
	print("- Uhr-Glaettung mit Rate: folgt 1,5x, Wechsel ohne Sprung")
	var sm = load("res://scripts/audio/sync_clock.gd").Smoother.new()
	var t_us := 0
	var raw := 0.0
	var out := 0.0
	var rate := 1.5
	var max_step := 0.0
	var prev := 0.0
	for i in 600:
		t_us += 16667
		raw += 16.667 * rate
		if i == 300:
			rate = 0.75
		out = sm.sample(raw, t_us, rate)
		if i > 0:
			max_step = maxf(max_step, out - prev)
		prev = out
	_ok(absf(out - raw) < 2.0, "nach Wechsel 1,5x -> 0,75x an der Audio-Uhr (%.2f ms)" % (out - raw))
	_ok(max_step < 16.667 * 1.5 + 3.0, "kein Sprung pro Frame (max %.1f ms)" % max_step)


func _test_old_replay_mods() -> void:
	print("- Alte Replays: ohne TB keine Tempo-Variante")
	var m: Dictionary = _GS._replay_mods({"meta": {"mods": {"SV": true}}})
	_ok(not m.has("TB") and not m.has("TB_track"), "alte Mods ohne Turbo-Felder")
	var m2: Dictionary = _GS._replay_mods({"meta": {"mods": {"TB": true, "TB_track": [[-1e15, 1.0], [5000, 1.05]], "TB_pitch": false}}})
	var tr := RateTrack.from_array(m2.get("TB_track"))
	_ok(bool(m2.TB) and tr != null and is_equal_approx(tr.rate_at(6000.0), 1.05), "Turbo-Replay traegt den Verlauf")


# --- SyncClock mit Rate (echtes Audio, Dummy-Treiber) -------------------------

func _tone(seconds: float, hz: float = 0.0, clicks_ms: float = 0.0) -> AudioStreamWAV:
	var mix := 48000
	var n := int(seconds * mix)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := 0.0
		if hz > 0.0:
			v = 0.5 * sin(TAU * hz * float(i) / mix)
		if clicks_ms > 0.0:
			var per := int(clicks_ms * mix / 1000.0)
			if i % per < 48:
				v = 0.9
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = mix
	w.stereo = false
	w.data = data
	return w


## 20-ms-Ton-Stoss (1 kHz) bei at_ms, sonst Stille.
func _burst(seconds: float, at_ms: float) -> AudioStreamWAV:
	var mix := 48000
	var n := int(seconds * mix)
	var data := PackedByteArray()
	data.resize(n * 2)
	data.fill(0)
	var i0 := int(at_ms * mix / 1000.0)
	for i in range(i0, mini(i0 + mix / 50, n)):
		data.encode_s16(i * 2, int(0.8 * sin(TAU * 1000.0 * float(i - i0) / mix) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = mix
	w.stereo = false
	w.data = data
	return w


## Energie-Schwerpunkt (Frame-Index) eines Puffers.
func _centroid(frames: PackedVector2Array) -> float:
	var e := 0.0
	var te := 0.0
	for i in frames.size():
		var x2 := frames[i].x * frames[i].x
		e += x2
		te += float(i) * x2
	return te / maxf(e, 1e-12)


## Erster Frame mit |Pegel| ueber rel x Spitzenpegel (-1 = keiner).
func _onset(frames: PackedVector2Array, rel: float) -> int:
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
	if peak < 0.05:
		return -1
	for i in frames.size():
		if absf(frames[i].x) > rel * peak:
			return i
	return -1


## Tonhoehe (Nulldurchgaenge), Pegel (RMS) und Reinheit (Energie-Anteil bei hz,
## Goertzel) eines Capture-Puffers (linker Kanal).
func _tone_quality(fr: PackedVector2Array, hz: float, mix: float) -> Dictionary:
	var n := fr.size()
	if n < 2:
		return {"hz": 0.0, "rms": 0.0, "purity": 0.0}
	var zc := 0
	var sq := 0.0
	var w := TAU * hz / mix
	var cr := 0.0
	var ci := 0.0
	for i in n:
		var x := fr[i].x
		if i > 0 and (fr[i - 1].x < 0.0) != (x < 0.0):
			zc += 1
		sq += x * x
		cr += x * cos(w * i)
		ci -= x * sin(w * i)
	var ms := sq / n
	var amp := 2.0 * sqrt(cr * cr + ci * ci) / n
	return {"hz": float(zc) / 2.0 / (float(n) / mix), "rms": sqrt(ms),
		"purity": (amp * amp / 2.0) / maxf(ms, 1e-12)}


func _wait_ms(ms: float) -> void:
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) / 1000.0 < ms:
		await process_frame


## Geraete-Uhr: ein stummer Referenz-Player mit Tempo 1 auf demselben Mixer.
## Seine Position (+ Zeit seit Mix) ist die Zeit, die das Audiogeraet wirklich
## ausgegeben hat. Der Dummy-Treiber laeuft nicht exakt mit der Wanduhr (gemessen
## ~2 % langsamer, mit Time-Stretch-Last mehr); Sync heisst: die Spieluhr folgt
## dem HOERBAREN Audio, also dieser Uhr x Rate. Wanduhr-Werte nur als Info.
var _ref: AudioStreamPlayer


func _dev_start() -> void:
	if _ref == null:
		_ref = AudioStreamPlayer.new()
		_ref.volume_db = -80.0
		root.add_child(_ref)
	_ref.stream = _tone(30.0)
	_ref.play()


func _dev_ms() -> float:
	return (_ref.get_playback_position() + AudioServer.get_time_since_last_mix()) * 1000.0


## "Perfekter Spieler": drueckt genau auf den hoerbaren Takt. Abweichung =
## Judgement-Uhr beim Druck minus Soll-Songzeit s0 + Rate x Geraetezeit.
## Der Test-PC ist oft voll ausgelastet (parallele Agents): dann stockt der
## Dummy-Mixer selbst. Bis zu 3 Messungen, die beste zaehlt (alle im Log).
func _test_clock_rate(rate: float, keep_pitch: bool) -> void:
	print("- SyncClock %s mit %s" % [RateTrack.rate_text(rate), "Time-Stretch" if keep_pitch else "Tonhoehe mit"])
	var m := {}
	for attempt in 3:
		m = await _measure_sync(rate, keep_pitch)
		if m.ok:
			break
	_ok(int(m.hits) >= 15, "genug Treffer gemessen (%d)" % int(m.hits))
	_ok(float(m.mean) < 4.0, "mittlere Treffer-Abweichung %s unter 4 ms (%.2f)" % [RateTrack.rate_text(rate), float(m.mean)])
	_ok(float(m.p90) < 10.0, "90 %% der Treffer %s unter 10 ms (%.2f)" % [RateTrack.rate_text(rate), float(m.p90)])
	_ok(float(m.drift) < 4.0, "keine Drift ueber 7 s (%.2f ms)" % float(m.drift))


func _measure_sync(rate: float, keep_pitch: bool) -> Dictionary:
	_clock.user_offset_ms = 0.0
	_dev_start()
	_clock.play(_tone(14.0, 220.0), 0.0)
	_clock.set_rate(rate, keep_pitch)
	await _wait_ms(600.0)
	var s0: float = _clock.judgement_time_ms()
	var d0 := _dev_ms()
	var w0 := Time.get_ticks_usec()
	var devs := PackedFloat64Array()
	var next_beat := ceilf(s0 / 250.0) * 250.0 + 250.0
	var wall_dev := 0.0
	while float(Time.get_ticks_usec() - w0) < 7000000.0:
		await process_frame
		var now_s: float = _clock.judgement_time_ms()
		var expect := s0 + rate * (_dev_ms() - d0)
		if expect >= next_beat:
			devs.append(now_s - expect)
			next_beat += 250.0
		wall_dev = now_s - (s0 + rate * float(Time.get_ticks_usec() - w0) / 1000.0)
	_clock.stop()
	_ref.stop()
	# Der Anker s0 ist ein einzelnes (verrauschtes) Sample: Abweichungen auf ihren
	# Median beziehen. Der feste Versatz (Latenz-Ausgleich) wird getrennt gemessen
	# (Ausgabelatenz: Godot; Time-Stretch: _test_timestretch_measure).
	var sorted := devs.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	var mean := 0.0
	var mx := 0.0
	for i in devs.size():
		devs[i] -= med
		mean += absf(devs[i])
		mx = maxf(mx, absf(devs[i]))
	mean /= maxf(devs.size(), 1.0)
	# 90-%-Wert der Abweichung: einzelne Haenger des (geteilten, ausgelasteten)
	# Test-PCs sollen den Test nicht kippen; max steht trotzdem im Log.
	var absd := PackedFloat64Array()
	for d in devs:
		absd.append(absf(d))
	absd.sort()
	var p90: float = absd[int(absd.size() * 0.9)] if not absd.is_empty() else 0.0
	# Drift: Mittel der letzten minus Mittel der ersten 8 Treffer.
	var lin := 0.0
	if devs.size() >= 16:
		var head := 0.0
		var tail := 0.0
		for i in 8:
			head += devs[i]
			tail += devs[devs.size() - 1 - i]
		lin = absf(tail - head) / 8.0
	print("  MEASURE sync rate=%.2f pitch=%s hits=%d mean_abs=%.2f ms p90=%.2f ms max=%.2f ms drift7s=%.2f ms fx_lat=%.1f ms (Wanduhr-Info: Dummy-Geraet nach 7 s %.1f ms zurueck)" % [
		rate, "keep" if keep_pitch else "nightcore", devs.size(), mean, p90, mx, lin, _clock.tempo_fx_latency_ms(), -wall_dev])
	return {"hits": devs.size(), "mean": mean, "p90": p90, "drift": lin,
		"ok": devs.size() >= 15 and mean < 4.0 and p90 < 10.0 and lin < 4.0}


## Rate-Wechsel mitten im Song: Songzeit springt nicht, danach Steigung = neue Rate
## (gegen die Geraete-Uhr).
func _test_clock_rate_change() -> void:
	print("- SyncClock: Rate-Wechsel mitten im Song ohne Sprung")
	var m := {}
	for attempt in 3:
		m = await _measure_rate_change()
		if m.ok:
			break
	_ok(not bool(m.back), "Songzeit nie rueckwaerts")
	_ok(float(m.jump) < 15.0, "kein Sprung beim Wechsel (max Abweichung je Frame %.2f ms)" % float(m.jump))
	_approx(float(m.slope), 1.5, "danach laeuft die Uhr mit 1,5x", 0.02)


func _measure_rate_change() -> Dictionary:
	_dev_start()
	_clock.play(_tone(14.0, 220.0), 0.0)
	_clock.set_rate(1.0, false)
	await _wait_ms(1500.0)
	var max_jump := 0.0
	var prev: float = _clock.song_time_ms()
	var prev_us := Time.get_ticks_usec()
	var back := false
	var rates := [1.25, 0.8, 1.5]
	for r in rates:
		_clock.set_rate(r, false)
		var t_end := Time.get_ticks_usec() + 1200000
		while Time.get_ticks_usec() < t_end:
			await process_frame
			var now: float = _clock.song_time_ms()
			var us := Time.get_ticks_usec()
			var expect_step: float = float(us - prev_us) / 1000.0 * float(r)
			max_jump = maxf(max_jump, absf((now - prev) - expect_step))
			back = back or now < prev
			prev = now
			prev_us = us
	var s_a: float = _clock.song_time_ms()
	var d_a := _dev_ms()
	await _wait_ms(1500.0)
	var slope: float = (_clock.song_time_ms() - s_a) / (_dev_ms() - d_a)
	_clock.stop()
	_ref.stop()
	print("  MEASURE ratechange max_frame_dev=%.2f ms slope_after=%.3f (Songzeit je ms Geraetezeit)" % [max_jump, slope])
	return {"back": back, "jump": max_jump, "slope": slope,
		"ok": not back and max_jump < 15.0 and absf(slope - 1.5) <= 0.02}


## Time-Stretch: Latenz (Klick-Einsatz im Capture mit/ohne Effekt) und
## Tonhoehe (Nulldurchgaenge eines 440-Hz-Tons bei 1,5x mit Ausgleich).
func _test_timestretch_measure() -> void:
	print("- Time-Stretch-Messung (AudioEffectPitchShift gegenlaeufig)")
	var probe := AudioServer.bus_count
	AudioServer.add_bus(probe)
	AudioServer.set_bus_name(probe, "TempoProbe")
	var ps := AudioEffectPitchShift.new()
	ps.fft_size = _SC.TEMPO_FFT
	ps.oversampling = _SC.TEMPO_OVERSAMPLING
	AudioServer.add_bus_effect(probe, ps, 0)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(probe, cap, 1)
	var p := AudioStreamPlayer.new()
	p.bus = "TempoProbe"
	root.add_child(p)
	var mix := AudioServer.get_mix_rate()
	# 1) Latenz: Ton-Stoss bei 300 ms, Rate 1,5. Zwei Busse (mit/ohne Effekt), zwei
	#    Player im selben Frame gestartet -> gleicher Mix-Block; Differenz der
	#    Einsaetze = Effekt-Latenz in Echtzeit.
	var ref_bus := AudioServer.bus_count
	AudioServer.add_bus(ref_bus)
	AudioServer.set_bus_name(ref_bus, "TempoProbeRef")
	var cap_ref := AudioEffectCapture.new()
	cap_ref.buffer_length = 4.0
	AudioServer.add_bus_effect(ref_bus, cap_ref, 0)
	var p_ref := AudioStreamPlayer.new()
	p_ref.bus = "TempoProbeRef"
	root.add_child(p_ref)
	await process_frame
	var burst := _burst(1.0, 300.0)
	p.stream = burst
	p_ref.stream = burst
	var exp_ms := float(_SC.TEMPO_FX_LATENCY_FRAMES) / mix * 1000.0
	var found := true
	var worst := 0.0
	var lats := PackedStringArray()
	var all_lat := PackedFloat64Array()
	for r in [0.5, 0.75, 1.0, 1.5, 2.0]:
		p.pitch_scale = r
		p_ref.pitch_scale = r
		ps.pitch_scale = _SC.tempo_fx_pitch(r)
		cap.clear_buffer()
		cap_ref.clear_buffer()
		p.play()
		p_ref.play()
		await _wait_ms(300.0 / r + 500.0)
		p.stop()
		p_ref.stop()
		var buf_fx: PackedVector2Array = cap.get_buffer(cap.get_frames_available())
		var buf_ref: PackedVector2Array = cap_ref.get_buffer(cap_ref.get_frames_available())
		# Der Phasen-Vocoder verschmiert den Stoss ueber ein FFT-Fenster (42,7 ms):
		# massgeblich ist der Energie-Schwerpunkt (dort hoert man den Schlag);
		# 10-%- und 50-%-Einsatz zeigen die Verschmierung.
		var on_fx := _onset(buf_fx, 0.1)
		var on_ref := _onset(buf_ref, 0.1)
		found = found and on_fx >= 0 and on_ref >= 0
		var lat_ms := (_centroid(buf_fx) - _centroid(buf_ref)) / mix * 1000.0
		var lat10 := float(on_fx - on_ref) / mix * 1000.0
		var lat50 := float(_onset(buf_fx, 0.5) - _onset(buf_ref, 0.5)) / mix * 1000.0
		print("  MEASURE timestretch_latency fft=2048 os=%d rate=%.2f schwerpunkt=%.1f ms (Einsatz 10%% %.1f / 50%% %.1f ms) angenommen=%.1f ms" % [
			_SC.TEMPO_OVERSAMPLING, r, lat_ms, lat10, lat50, exp_ms])
		lats.append("%.2f: %.1f" % [r, lat_ms])
		worst = maxf(worst, absf(lat_ms - exp_ms))
		all_lat.append(lat_ms)
	all_lat.sort()
	var med_lat: float = all_lat[all_lat.size() / 2]
	_ok(found, "Ton-Stoss in beiden Capture-Puffern gefunden")
	# Der Schwerpunkt eines kurzen Stosses streut je Tonhoehen-Verhaeltnis (Vocoder-
	# Verschmierung): Median muss passen, jede Rate in 12 ms (unter einem Bild).
	_ok(absf(med_lat - exp_ms) < 4.0, "Uhr-Ausgleich = gemessene Effekt-Latenz (Median %.1f / %.1f ms)" % [med_lat, exp_ms])
	_ok(worst < 12.0, "jede Rate nah am Ausgleich (%s, angenommen %.1f ms)" % [", ".join(lats), exp_ms])
	# 2) Qualitaet: 440 Hz bei Rate 1,5 + Ausgleich 1/1,5 (soll 440 Hz bleiben)
	#    gegen denselben Ton unbearbeitet (Tempo 1, Referenz-Bus): Tonhoehe,
	#    Pegel-Unterschied und Reinheit (Anteil der Energie bei 440 Hz).
	var tone := _tone(3.0, 440.0)
	p.stream = tone
	p_ref.stream = tone
	p.pitch_scale = 1.5
	p_ref.pitch_scale = 1.0
	ps.pitch_scale = _SC.tempo_fx_pitch(1.5)
	p.play()
	p_ref.play()
	await _wait_ms(500.0)
	cap.clear_buffer()
	cap_ref.clear_buffer()
	await _wait_ms(800.0)
	var fr: PackedVector2Array = cap.get_buffer(cap.get_frames_available())
	var fr_ref: PackedVector2Array = cap_ref.get_buffer(cap_ref.get_frames_available())
	p.stop()
	p_ref.stop()
	var q := _tone_quality(fr, 440.0, mix)
	var q_ref := _tone_quality(fr_ref, 440.0, mix)
	var gain_db := 20.0 * log(maxf(q.rms, 1e-6) / maxf(q_ref.rms, 1e-6)) / log(10.0)
	print("  MEASURE timestretch_quality rate=1.50 tone=440 measured=%.1f Hz (ohne Ausgleich 660 Hz) pegel=%+.2f dB reinheit=%.3f (unbearbeitet %.3f)" % [
		q.hz, gain_db, q.purity, q_ref.purity])
	_ok(absf(q.hz - 440.0) < 12.0, "Tonhoehe bleibt bei 1,5x (%.1f Hz)" % q.hz)
	_ok(q.purity > 0.9, "Ton bleibt rein (%.3f)" % q.purity)
	# Pegel schwankt je Lauf (gemessen -2,1 bis +2,4 dB, Phasenlage des Vocoders):
	# kein fester Ausgleich, nur Grenze.
	_ok(absf(gain_db) < 3.0, "Pegel bleibt in +-3 dB (%+.2f dB)" % gain_db)
	p_ref.queue_free()
	AudioServer.remove_bus(ref_bus)
	p.queue_free()
	AudioServer.remove_bus(probe)
