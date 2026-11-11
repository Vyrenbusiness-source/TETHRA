extends SceneTree

## Orbit-Endbild (OrbitResults): baut das Endbild aus einem kuenstlichen Lauf
## (Log ueber OrbitResults.entry wie im Spiel) und prueft Inhalte und Layout bei
## 1280x720. Mit --shot (Fenster-Lauf) speichert es user://orbit_results.png
## und user://orbit_results_fail.png.
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_results_tests.gd

var _failed := 0
var _passed := 0
## Per load(): OrbitResults nutzt Autoloads (Settings), die beim Kompilieren
## eines SceneTree-Skripts noch nicht bekannt sind.
var RS: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


## Kuenstlicher Lauf: 180 Ziele, A/B im Wechsel, jedes 9. Akzent, jedes 23.
## Halten; Zeitfehler leicht spaet gestreut, Cursor um die Mitte gestreut.
func _fake_log(radius: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var log: Array = []
	var counts := [0, 0, 0, 0, 0, 0]
	var combo := 0
	var best := 0
	for i in 180:
		var t := 1200.0 + float(i) * 420.0
		var key := 2 if i % 9 == 8 else i % 2
		var p := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))
		var n: OrbitNote
		if i % 23 == 5:
			n = OrbitNote.make_hold(t, t + 600.0, PackedVector2Array([p, p + Vector2(0.12, 0.05)]), key)
		else:
			n = OrbitNote.make_target(t, p, key)
		var dt := rng.randfn(6.0, 18.0)
		var q := 0
		var ad := absf(dt)
		if ad > 16.0: q = 1
		if ad > 34.0: q = 2
		if ad > 52.0: q = 3
		if ad > 70.0: q = 4
		var miss := i % 37 == 20
		var res := {"quality": 5 if miss else q, "dt": dt, "miss_kind": "FULL" if miss else ""}
		var cur := p + Vector2(rng.randfn(0.004, radius * 0.35), rng.randfn(-0.002, radius * 0.35))
		log.append(RS.entry(n, res, cur))
		counts[5 if miss else q] += 1
		combo = 0 if miss else combo + 1
		best = maxi(best, combo)
	return {"log": log, "counts": counts, "best": best}


func _data(fail: bool) -> Dictionary:
	var radius := 0.045
	var f := _fake_log(radius)
	var c: Array = f.counts
	return {
		"is_fail": fail,
		"s": {"n_max": c[0], "n300": c[1], "n200": c[2], "n100": c[3], "n50": c[4], "n_miss": c[5],
			"max_combo": f.best, "accuracy": 0.9634, "score": 912345, "grade": "S", "aim_err": 1.6,
			"mods": ["HD"]},
		"log": f.log,
		"radius": radius,
		"presses": {"key": 4, "aim": 7, "lock": 1, "early": 2},
		"w50": 120.0,
		"w_max": 16.0,
		"new_best": not fail,
		"title": "Satellite Test Song",
		"artist": "Orbit Artist",
		"version": "Insane",
		"allow_retry": true,
		"can_replay": true,
		"is_replay": false,
		"can_clip": true,
	}


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for ch in n.get_children():
		out += _all_text(ch)
	return out


func _inside(c: Control, rs: Control) -> bool:
	var r := c.get_global_rect()
	return Rect2(Vector2.ZERO, rs.size).grow(1.0).encloses(r)


func _show(fail: bool) -> Control:
	var host := Control.new()
	host.theme = UiTheme.build_theme()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var rs: Control = RS.new()
	host.add_child(rs)
	rs.call("show_results", _data(fail))
	return rs


func _run() -> void:
	print("=== Orbit-Endbild ===")
	RS = load("res://scripts/orbit/orbit_results.gd")
	root.size = Vector2i(1280, 720)
	var shot := OS.get_cmdline_args().has("--shot") or OS.get_cmdline_user_args().has("--shot")
	var rs := _show(false)
	await create_timer(1.2).timeout   # Aufdecken (0,9 s) durchlaufen
	await _frames(3)

	var txt := _all_text(rs)
	_check((rs.find_child("Grade", true, false) as Label).text == "S", "Rang S")
	_check((rs.find_child("Score", true, false) as Label).text == UiTheme.fmt_score(912345), "Score hochgezaehlt")
	for cap in ["GENAUIGKEIT", "KOMBO", "ZIELFEHLER", "CORE", "SHARP", "GOOD", "FAIR", "EDGE", "MISS",
			"TREFFER", "AKZENT", "HD"]:
		_check(txt.contains(TranslationServer.translate(cap)), "Text '%s' da" % cap)
	var ps := rs.find_child("PressStats", true, false) as Label
	_check(ps != null and ps.text.contains("4") and ps.text.contains("7"), "Falsche Taste / Daneben gezaehlt (%s)" % (ps.text if ps else ""))
	var rows: Array = rs.get("_key_rows")
	var total := 0
	for r in rows:
		total += int(r.n)
	_check(total == 180 and int(rows[2].n) == 20, "Tasten-Statistik zaehlt alle Ziele (A/B/Akzent)")
	_check(int(rs.get("_n_off")) == 180 - 5, "Streuung: alle gedrueckten Ziele (%d)" % int(rs.get("_n_off")))
	var mo: Vector2 = rs.get("_mean_off")
	_check(mo.x > 0.0 and mo.length() < 0.02, "Mittlere Zielabweichung plausibel (%s)" % str(mo))
	_check(float(rs.get("_ur")) > 100.0 and float(rs.get("_ur")) < 260.0, "UR plausibel (%.0f)" % float(rs.get("_ur")))
	for b in ["ReplayButton", "ClipButton", "ShareScoreButton", "RetryButton", "BackButton"]:
		var bn := rs.find_child(b, true, false) as Control
		_check(bn != null, "Knopf %s da" % b)
		if bn != null and bn.visible:
			_check(_inside(bn, rs), "Knopf %s im Bild (%s)" % [b, str(bn.get_global_rect())])
	var ks := rs.find_child("KeyStats", true, false) as Control
	_check(ks != null and _inside(ks, rs), "Tasten-Statistik im Bild")
	var got := [0]
	rs.connect("replay_pressed", func(): got[0] += 1)
	(rs.find_child("ReplayButton", true, false) as Button).pressed.emit()
	_check(got[0] == 1, "Replay-Knopf sendet replay_pressed")
	if shot:
		await _frames(10)
		root.get_texture().get_image().save_png("user://orbit_results.png")
		print("SHOT ", ProjectSettings.globalize_path("user://orbit_results.png"))
	rs.get_parent().queue_free()
	await _frames(2)

	# Gescheitert + altes Log-Format (Bahnen): laedt, kein Teilen, keine Streuung.
	var host := Control.new()
	host.theme = UiTheme.build_theme()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var rf: Control = RS.new()
	host.add_child(rf)
	var d := _data(true)
	var old: Array = []
	for e in d.log:
		old.append([0.0, mini(int(e.key), 1), e.dt, 0.0, e.q, e.t])
	d.log = old
	d.erase("presses")
	rf.call("show_results", d)
	await create_timer(1.2).timeout
	await _frames(3)
	_check((rf.find_child("Grade", true, false) as Label).text == "F", "Gescheitert: Rang F")
	_check(rf.find_child("ShareScoreButton", true, false) == null, "Gescheitert: kein Teilen")
	_check(int(rf.get("_n_off")) == 0, "Altes Format: keine Streuung, kein Fehler")
	if shot:
		await _frames(10)
		root.get_texture().get_image().save_png("user://orbit_results_fail.png")
		print("SHOT ", ProjectSettings.globalize_path("user://orbit_results_fail.png"))
	host.queue_free()
	await _frames(2)
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
