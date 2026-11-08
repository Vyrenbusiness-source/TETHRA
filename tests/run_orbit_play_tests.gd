extends SceneTree

## Headless-Tests fuer den Orbit-Spielbau (Task orbit-play): Score-Trennung
## nach Modus, Orbit-Tasten in den Settings, Geometrie der OrbitView.
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
	print("=== TETHRA Orbit-Play-Tests ===")
	_test_score_modes()
	_test_settings()
	_test_view_geometry()
	_test_sound()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


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
	_check(int(ScoreStore.best("map.osz", "Hard", "mania").score) == 500000, "mode=mania = Standard")
	_check(int(ScoreStore.best("map.osz", "Hard", ScoreStore.MODE_ORBIT).score) == 900000, "Orbit-Bestwert getrennt")
	_check(ScoreStore.play_count("map.osz", "Hard") == 1, "Mania-Plays ohne Orbit")
	_check(ScoreStore.play_count("map.osz", "Hard", ScoreStore.MODE_ORBIT) == 1, "Orbit-Plays eigen")
	ScoreStore.log_play("map.osz", "Hard", "A - B", orbit, ScoreStore.MODE_ORBIT)
	_check(ScoreStore.recent_plays().is_empty(), "Orbit nicht in Mania-Recent")
	_check(ScoreStore.top_scores("map.osz", "Hard").is_empty(), "Orbit nicht in Mania-History")
	_check(ScoreStore.top_scores("map.osz", "Hard", 5, ScoreStore.MODE_ORBIT).size() == 1, "Orbit-History")
	var bp := ScoreStore.best_plays(10)
	_check(bp.size() == 1 and int(bp[0].score) == 500000, "best_plays nur Mania")
	_check(is_equal_approx(ScoreStore.profile_pp(), 120.0), "Profil-pp nur Mania")
	_check(ScoreStore.total_plays() == 1, "total_plays nur Mania")
	DirAccess.remove_absolute(ScoreStore.PATH)
	ScoreStore.PATH = old_path


func _test_settings() -> void:
	var SettingsScript: GDScript = root.get_node("/root/Settings").get_script()
	var path := "user://test_tmp/orbit_play_settings_%d.cfg" % OS.get_process_id()
	var a = SettingsScript.new()
	_check(a.orbit_key_inner == KEY_Z and a.orbit_key_outer == KEY_X, "Standard Z/X")
	_check(a.orbit_guides, "Raster standardmaessig an")
	_check(Array(a.key_lanes) == [KEY_D, KEY_F, KEY_J, KEY_K], "Mania-Tasten unveraendert")
	a.orbit_key_inner = KEY_A
	a.orbit_key_outer = KEY_S
	a.orbit_guides = false
	a.save(path)
	var b = SettingsScript.new()
	b.load_settings(path)
	_check(b.orbit_key_inner == KEY_A and b.orbit_key_outer == KEY_S, "Orbit-Tasten Roundtrip")
	_check(not b.orbit_guides, "Hilfslinien Roundtrip")
	_check(b.orbit_ring_for_key(KEY_A) == 0 and b.orbit_ring_for_key(KEY_S) == 1
		and b.orbit_ring_for_key(KEY_D) == -1, "Ring je Taste")
	_check(b.lane_for_key(KEY_A) == -1 and b.lane_for_key(KEY_D) == 0, "Mania-Lanes unberuehrt")
	a.free()
	b.free()
	DirAccess.remove_absolute(path)


func _test_view_geometry() -> void:
	var v := OrbitView.new()
	v.size = Vector2(1280, 720)
	var c := v.center()
	_check(c.is_equal_approx(Vector2(640, 360)), "Mitte")
	for q in [Vector2(0.3, -0.2), Vector2(-0.5, 0.1), Vector2.ZERO]:
		_check(v.to_path(v.to_px(q)).is_equal_approx(q), "to_px/to_path Roundtrip")
	# Feld passt in den Bildschirm: jede Form samt Spuren.
	for shape in OrbitPath.COUNT:
		var ok := true
		for p in OrbitPath.polyline(shape, 96):
			var px := v.to_px(p)
			if px.x < 40.0 or px.x > 1240.0 or px.y < 40.0 or px.y > 680.0:
				ok = false
		_check(ok, "Form %s passt ins Feld" % OrbitPath.NAMES[shape])
	# Kopf: eine Bahn pro Takt, Takt-Eins = Startpunkt; Cursor auf dem Kopf = Zielen ok.
	var clk := OrbitClock.fixed(2000.0)
	v.clock = clk
	v.track = OrbitTrack.fixed(clk, OrbitPath.ELLIPSE)
	v.tol = OrbitCore.AIM_TOL
	v.t_ms = 0.0
	_check(v.head_path().is_equal_approx(OrbitPath.pos(OrbitPath.ELLIPSE, 0.0)), "Kopf bei Takt-Eins am Start")
	v.t_ms = 500.0
	_check(v.head_path().is_equal_approx(OrbitPath.pos(OrbitPath.ELLIPSE, 0.25)), "Kopf nach einem Viertel")
	_check(not v.aim_ok(), "ohne Cursor: nicht auf dem Kopf")
	v.cursor_pos = v.to_px(v.head_path()) + Vector2(5, 0)
	_check(v.aim_ok(), "Cursor nah am Kopf zaehlt")
	v.cursor_pos = v.to_px(v.head_path()) + Vector2(0.3 * v.path_scale(), 0)
	_check(not v.aim_ok(), "Cursor weit weg: nicht auf dem Kopf")
	v.free()


func _test_sound() -> void:
	OrbitGameScript = load("res://scripts/orbit/orbit_game.gd")
	var a := Sfx.orbit_hit_stream(0)
	var b := Sfx.orbit_hit_stream(1)
	_check(a != b and a.data != b.data, "Ringe haben eigene Treffer-Klaenge")
	_check(a.data.size() < b.data.size(), "innen kuerzer als aussen")
	_check(Sfx.orbit_hit_stream(0) == a, "Klang gecacht")
	_check(Sfx.orbit_hold_stream(0).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Halteton geloopt")
	var snd = OrbitGameScript.OrbitSound.new()
	root.add_child(snd)
	snd.on_judged(0, 1, false)
	snd.on_judged(1, 2, false)
	_check(snd.log == [["hit", 0], ["hit", 1]], "ein Treffer = genau ein Klang, Ring-Zuordnung")
	snd.log.clear()
	snd.on_arc_started(1, 1)
	snd.on_judged(1, 1, true)
	_check(snd.log == [["hit", 1], ["hold", 1], ["end", 1]], "Bogen: Start-Hit, Halteton, Ende-Klick")
	snd.log.clear()
	snd.on_judged(0, 5, false)
	snd.on_judged(1, 5, true)
	_check(snd.log == [["miss", 0], ["miss", 1]], "Fehltreffer: nur Miss-Klang")
	snd.log.clear()
	for i in 10:
		snd.on_judged(0, 0, false)
	_check(snd.log.size() == 10 and snd._hit[0].size() == OrbitGameScript.OrbitSound.POLY, "schnelle Folge: Polyphonie begrenzt")
	root.remove_child(snd)
	snd.free()
