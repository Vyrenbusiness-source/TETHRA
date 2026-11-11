extends SceneTree

## Headless-Tests fuer das Orbit-Spiel "Satelliten" (Task orbit-sat-game):
## Score-Trennung nach Modus, Orbit-Tasten in den Settings, Feld-Abbildung
## Bildschirm <-> Feld, Autoplay-Bot (perfekt = SS, menschlich), HD/FI,
## Ansicht-Zustaende, Klaenge.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_play_tests.gd

var _passed := 0
var _failed := 0
var OrbitGameScript: GDScript
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== TETHRA Orbit-Play-Tests (Satelliten) ===")
	OrbitGameScript = load("res://scripts/orbit/orbit_game.gd")
	_test_score_modes()
	_test_settings()
	_test_field_mapping()
	_test_key_hint()
	_test_bot_ss()
	_test_bot_human()
	_test_bot_smooth()
	_test_mods_view()
	_test_view_states()
	_test_sound()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Hilfen ---

func _tp(bm: Beatmap, t: float, bpm: float) -> void:
	var tp := TimingPoint.new()
	tp.time = t
	tp.beat_length = 60000.0 / bpm
	tp.meter = 4
	tp.uninherited = true
	bm.timing_points.append(tp)


## osu!standard-Map: Spruenge, Stream, Hitsounds (Whistle = B, Finish = Akzent), Slider.
func _std_map() -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "0"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5", "ApproachRate": "9"}
	_tp(bm, 0.0, 150.0)
	var beat := 400.0
	var t := 1200.0
	for i in 96:
		var o: HitObject
		if i % 12 == 5:
			var s := HitSlider.new()
			s.curve_type = "B"
			s.x = 120.0 + float((i * 41) % 260)
			s.y = 90.0 + float((i * 29) % 180)
			s.curve_points = PackedVector2Array([Vector2(s.x, s.y), Vector2(s.x + 60, s.y - 50), Vector2(s.x + 130, s.y)])
			s.slides = 1
			s.length = 150.0
			s.single_duration_ms = beat
			o = s
		else:
			o = HitCircle.new()
			o.x = 40.0 + float((i * 137) % 430)
			o.y = 40.0 + float((i * 71) % 300)
			o.hit_sound = [0, 2, 0, 8, 4, 0, 2, 0][i % 8]
		o.time = t
		bm.hit_objects.append(o)
		if i % 12 == 5:
			t += beat * 2.0
		elif i >= 40 and i < 56:
			t += beat * 0.25   # Stream
		else:
			t += beat * 0.5
	return bm


## Mania-4K-Map mit Akkorden und Holds.
func _mania_map() -> Beatmap:
	var bm := Beatmap.new()
	bm.general = {"Mode": "3"}
	bm.difficulty = {"CircleSize": "4", "OverallDifficulty": "8", "HPDrainRate": "5"}
	_tp(bm, 0.0, 128.0)
	var beat := 60000.0 / 128.0
	var t := 1000.0
	for i in 80:
		var n := ManiaNote.new()
		n.time = t
		n.column = (i * 3) % 4
		if i % 10 == 3:
			n.is_hold = true
			n.hold_end = t + beat * 1.5
			t += beat * 2.0
		else:
			t += beat * 0.5
		bm.hit_objects.append(n)
		if i % 16 == 8:
			var c := ManiaNote.new()
			c.time = n.time
			c.column = (n.column + 2) % 4
			bm.hit_objects.append(c)
	return bm


## Spiel-Instanz ohne Szene: Core + Ansicht + Bot wie OrbitGame._ready.
func _game(bm: Beatmap, plan_sigma_t := 0.0, plan_sigma_a := 0.0, miss_every := 0, mods: Dictionary = {}) -> Control:
	var g: Control = OrbitGameScript.new()
	g._beatmap = bm
	g.notes = OrbitConverter.convert(bm)
	g._radius = OrbitConverter.target_radius(bm)
	g.core = OrbitCore.new()
	g.core.setup(g.notes, bm.od(), mods, g._radius, bm.hp())
	g.core.set_replay_mode(true)
	g._view = OrbitView.new()
	g._view.size = Vector2(1280, 720)
	g._view.setup(g.notes)
	g._autoplay = true
	g._bot_plan = OrbitCore.bot_plan(g.notes, 7, plan_sigma_t, plan_sigma_a, miss_every)
	g._bot_build()
	return g


## Bot-Lauf mit wechselnder Bildlaenge bis zum Ende. Rueckgabe: Urteile je Index.
func _play(g: Control, seed: int = 1) -> Dictionary:
	var got := {}
	var core: OrbitCore = g.core
	core.note_judged.connect(func(i: int, r: Dictionary) -> void: got[i] = r)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var t := -800.0
	var end_t: float = float(g.notes.back().end_ms) + 1200.0
	while t < end_t:
		t += rng.randf_range(4.0, 40.0)
		g._run_autoplay(t)
		core.update(t)
	return got


func _free_game(g: Control) -> void:
	g._view.free()
	g.free()


# --- Tests ---

func _test_score_modes() -> void:
	var old_path := ScoreStore.PATH
	ScoreStore.PATH = "user://test_tmp/orbit_play_scores_%d.cfg" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	DirAccess.remove_absolute(ScoreStore.PATH)
	var mania := {"score": 500000, "accuracy": 0.9, "grade": "A", "pp": 120.0, "max_combo": 50}
	var orbit := {"score": 900000, "accuracy": 0.98, "grade": "S", "pp": -1.0, "max_combo": 80}
	var r1 := ScoreStore.submit("map.osz", "Hard", mania)
	var r2 := ScoreStore.submit("map.osz", "Hard", orbit, ScoreStore.MODE_ORBIT)
	_check(bool(r1.is_new_best) and bool(r2.is_new_best), "beide Modi: erster Score ist Bestwert")
	_check(int(ScoreStore.best("map.osz", "Hard").score) == 500000, "Mania-Bestwert bleibt Mania")
	_check(int(ScoreStore.best("map.osz", "Hard", ScoreStore.MODE_ORBIT).score) == 900000, "Orbit-Bestwert getrennt")
	_check(ScoreStore.play_count("map.osz", "Hard", ScoreStore.MODE_ORBIT) == 1, "Orbit-Plays eigen")
	ScoreStore.log_play("map.osz", "Hard", "A - B", orbit, ScoreStore.MODE_ORBIT)
	_check(ScoreStore.recent_plays().is_empty(), "Orbit nicht in Mania-Recent")
	_check(ScoreStore.top_scores("map.osz", "Hard", 5, ScoreStore.MODE_ORBIT).size() == 1, "Orbit-History")
	DirAccess.remove_absolute(ScoreStore.PATH)
	ScoreStore.PATH = old_path


func _test_settings() -> void:
	var SettingsScript: GDScript = root.get_node("/root/Settings").get_script()
	var path := "user://test_tmp/orbit_play_settings_%d.cfg" % OS.get_process_id()
	var a = SettingsScript.new()
	_check(a.orbit_key_inner == KEY_Z and a.orbit_key_outer == KEY_X, "Standard Z/X")
	_check(a.orbit_key_hint == 0 and a.orbit_music == 1, "Tasten-Hinweis auto, Musik dezent")
	a.orbit_key_inner = KEY_A
	a.orbit_key_outer = KEY_S
	a.save(path)
	var b = SettingsScript.new()
	b.load_settings(path)
	_check(b.orbit_key_inner == KEY_A and b.orbit_key_outer == KEY_S, "Orbit-Tasten Roundtrip")
	_check(b.orbit_ring_for_key(KEY_A) == 0 and b.orbit_ring_for_key(KEY_S) == 1
		and b.orbit_ring_for_key(KEY_D) == -1, "Taste A/B je Tastencode")
	a.free()
	b.free()
	DirAccess.remove_absolute(path)


func _test_field_mapping() -> void:
	print("- Feld: Bildschirm <-> Feld")
	var v := OrbitView.new()
	v.size = Vector2(1280, 720)
	var r := v.field_rect()
	_check(is_equal_approx(r.size.y, 576.0) and is_equal_approx(r.size.x, 768.0), "Feld 4:3, Hoehe 80 %")
	_check(r.get_center().is_equal_approx(Vector2(640, 360)), "Feld mittig")
	_check(is_equal_approx(v.field_scale(), 576.0), "field_scale = Feldhoehe")
	_check(v.field_to_screen(Vector2.ZERO).is_equal_approx(Vector2(256, 72)), "Ecke oben links")
	_check(v.field_to_screen(Vector2.ONE).is_equal_approx(Vector2(1024, 648)), "Ecke unten rechts")
	for q in [Vector2(0.3, 0.7), Vector2(-0.1, 1.2), Vector2(0.5, 0.5)]:
		_check(v.screen_to_field(v.field_to_screen(q)).is_equal_approx(q), "Roundtrip %s" % q)
	# Schmales Fenster: Feld passt in die Breite.
	v.size = Vector2(800, 900)
	r = v.field_rect()
	_check(r.size.x <= 800.0 and is_equal_approx(r.size.x / r.size.y, 4.0 / 3.0), "Hochformat: 4:3 in der Breite")
	v.free()
	# Spiel: Viewport-Pixel -> Feld ueber die Ansicht (auch verschoben).
	var g: Control = OrbitGameScript.new()
	var holder := Control.new()
	root.add_child(holder)
	g._view = OrbitView.new()
	holder.add_child(g._view)
	g._view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g._view.position = Vector2(100, 50)
	g._view.size = Vector2(1280, 720)
	var want := Vector2(0.25, 0.75)
	var px: Vector2 = g._view.field_to_screen(want) + Vector2(100, 50)
	_check(g._px_to_field(px).is_equal_approx(want), "Viewport-Pixel -> Feld (Ansicht verschoben)")
	holder.queue_free()
	g.free()


func _test_key_hint() -> void:
	_check(OrbitGameScript.key_hint_on(0, 2.0, false), "auto: leichte Map zeigt Taste")
	_check(not OrbitGameScript.key_hint_on(0, 7.0, false), "auto: sehr schwere Map ohne Taste")
	_check(OrbitGameScript.key_hint_on(0, 7.0, true), "auto: Tutorial zeigt Taste")
	_check(OrbitGameScript.key_hint_on(1, 9.0, false), "an")
	_check(not OrbitGameScript.key_hint_on(2, 1.0, true), "aus")


func _test_bot_ss() -> void:
	print("- Bot perfekt = SS (std + Mania)")
	for bm in [_std_map(), _mania_map()]:
		var g := _game(bm)
		var ns: Array[OrbitNote] = g.notes
		var holds := 0
		var accents := 0
		for n in ns:
			holds += 1 if n.is_hold else 0
			accents += 1 if n.key == OrbitNote.KEY_ACCENT else 0
		var tag := "mania" if bm.is_mania() else "std"
		_check(holds > 0 and accents > 0, "%s: Map hat Halten und Akzente (%d/%d)" % [tag, holds, accents])
		var got := _play(g)
		var s: Dictionary = g.core.stats()
		_check(got.size() == ns.size(), "%s: alle Ziele gewertet" % tag)
		_check(int(s.n_miss) == 0, "%s: keine Misses (%d)" % [tag, int(s.n_miss)])
		_check(str(s.grade) == "SS", "%s: Rang SS (%s, %.4f)" % [tag, s.grade, float(s.accuracy)])
		_check(int(s.max_combo) >= ns.size(), "%s: volle Kombo" % tag)
		var held := true
		for i in got:
			if ns[i].is_hold:
				held = held and bool(got[i].get("held", false))
		_check(held, "%s: jedes Halten bis zum Ende" % tag)
		_free_game(g)


func _test_bot_human() -> void:
	print("- Bot menschlich (25 ms Streuung, Zielfehler) trifft fast alles")
	var g := _game(_std_map(), 25.0, 1.5)
	_play(g, 3)
	var s: Dictionary = g.core.stats()
	var n: int = g.notes.size()
	var hit_rate := 1.0 - float(s.n_miss) / float(n)
	print("    Treffer %.1f %%, Acc %.2f %%" % [hit_rate * 100.0, float(s.accuracy) * 100.0])
	_check(hit_rate >= 0.97, "menschlicher Bot >= 97 % Treffer")
	_free_game(g)
	# --auto-miss: jedes 4. Ziel ausgelassen.
	var gm := _game(_std_map(), 0.0, 0.0, 4)
	_play(gm)
	var sm: Dictionary = gm.core.stats()
	_check(int(sm.n_miss) >= gm.notes.size() / 4 - 1, "auto-miss laesst Ziele aus")
	_free_game(gm)


func _test_bot_smooth() -> void:
	print("- Bot-Cursor gleitet (kein Springen), sitzt zur Trefferzeit")
	var g := _game(_std_map())
	var ns: Array[OrbitNote] = g.notes
	var max_step := 0.0
	var prev: Vector2 = g.bot_cursor(0.0)
	var t := 0.0
	while t < float(ns.back().end_ms):
		t += 4.0
		var p: Vector2 = g.bot_cursor(t)
		max_step = maxf(max_step, p.distance_to(prev))
		prev = p
	_check(max_step < 0.09, "hoechstens 0,09 Feld je 4 ms (%.3f)" % max_step)
	var on := true
	for n in ns:
		on = on and (g.bot_cursor(n.time_ms) as Vector2).distance_to(n.pos) < 1e-4
	_check(on, "zur Trefferzeit genau auf dem Ziel")
	_free_game(g)


func _test_mods_view() -> void:
	print("- HD/FI: Satellit und Pips ausblenden")
	var n := OrbitNote.make_target(2000.0, Vector2(0.5, 0.5), 0)
	n.lap_ms = 500.0
	n.laps = 3
	n.spawn_ms = 500.0
	var v := OrbitView.new()
	_check(is_equal_approx(v._sat_alpha(n, 600.0), 1.0) and is_equal_approx(v._sat_alpha(n, 1990.0), 1.0),
		"ohne Mod immer sichtbar")
	v.mod_hidden = true
	_check(v._sat_alpha(n, 600.0) > 0.99, "HD: beim Erscheinen sichtbar")
	_check(v._sat_alpha(n, 1500.0) < 0.01, "HD: in der letzten Runde weg")
	v.mod_hidden = false
	v.mod_fade_in = true
	_check(v._sat_alpha(n, 600.0) < 0.01, "FI: beim Erscheinen unsichtbar")
	_check(v._sat_alpha(n, 1800.0) > 0.99, "FI: in der letzten Runde sichtbar")
	v.free()
	# Spiel liest HD/FI aus den Mods.
	var g := _game(_std_map(), 0.0, 0.0, 0, {"HD": true})
	_check(bool(g.core.mods.get("HD", false)), "HD im Core")
	_free_game(g)


func _test_view_states() -> void:
	print("- Ansicht: naechstes Ziel, Zustaende, Fehldruck")
	var ns: Array = []
	for i in 4:
		var n := OrbitNote.make_target(1000.0 + 500.0 * i, Vector2(0.2 + 0.2 * i, 0.5), i % 2)
		n.lap_ms = 500.0
		n.laps = 2
		n.spawn_ms = n.time_ms - 1000.0
		ns.append(n)
	var v := OrbitView.new()
	v.size = Vector2(1280, 720)
	v.setup(ns)
	_check(v.next_index() == 0, "naechstes Ziel = erstes")
	v.t_ms = 1000.0
	v.on_judged(0, {"quality": 0})
	_check(v.state_of(0) == OrbitView.ST_HIT and v.next_index() == 1, "Treffer -> naechstes")
	v.on_judged(1, {"quality": 5})
	_check(v.state_of(1) == OrbitView.ST_MISS, "Miss")
	v.on_hold_started(2, 1)
	_check(v.state_of(2) == OrbitView.ST_HOLD and v.next_index() == 3, "Halten laeuft")
	v.on_judged(2, {"quality": 1, "hold_end": true})
	_check(v.state_of(2) == OrbitView.ST_HOLD_DONE, "Halten fertig")
	v.on_press_missed(Vector2(0.5, 0.5), 0, "aim")
	v.on_press_missed(Vector2(0.5, 0.5), 1, "key")
	v.on_press_missed(Vector2(0.5, 0.5), 1, "early")
	_check(v._press.size() == 2 and v._press[0][1] == String(TranslationServer.translate("daneben")) and v._press[1][1] == String(TranslationServer.translate("andere Taste")),
		"Fehldruck: daneben / andere Taste, zu frueh = nichts")
	v.on_press_missed(Vector2(0.5, 0.5), 1, "lock")
	_check(v._lock_idx == 3, "Notelock wackelt das naechste Ziel")
	# Satellit oben zur Trefferzeit, Pips = verbleibende Runden.
	var n3: OrbitNote = ns[3]
	_check(is_zero_approx(fposmod(n3.satellite_deg(n3.time_ms), 360.0)), "Satellit oben bei Trefferzeit")
	_check(n3.laps_left(n3.spawn_ms) == 2 and n3.laps_left(n3.time_ms - 10.0) == 0, "Pips 2 -> 0")
	v.free()


func _test_sound() -> void:
	var a := Sfx.orbit_hit_stream(0)
	var b := Sfx.orbit_hit_stream(1)
	_check(a != b and a.data != b.data, "A und B haben eigene Treffer-Klaenge")
	_check(Sfx.orbit_hold_stream(0).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Halteton geloopt")
	var snd = OrbitGameScript.OrbitSound.new()
	root.add_child(snd)
	snd.on_judged(0, 1, false)
	snd.on_judged(1, 2, false)
	_check(snd.log == [["hit", 0], ["hit", 1]], "ein Treffer = genau ein Klang, Tasten-Zuordnung")
	snd.log.clear()
	snd.on_arc_started(1, 1)
	snd.on_judged(1, 1, true)
	_check(snd.log == [["hit", 1], ["hold", 1], ["end", 1]], "Halten: Start-Hit, Halteton, Ende-Klick")
	snd.log.clear()
	snd.on_judged(2, 0, false)
	_check(snd.log.size() == 1, "Akzent: ein Klang")
	snd.log.clear()
	snd.on_judged(0, 5, false)
	_check(snd.log == [["miss", 0]], "Fehltreffer: nur Miss-Klang")
	root.remove_child(snd)
	snd.free()
