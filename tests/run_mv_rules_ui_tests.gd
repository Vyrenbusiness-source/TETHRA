extends SceneTree

## Headless-Tests fuer die Oberflaeche der Regel-Mods (Task mv-rules, Runde 2):
## Song-Browser (Max-pp-Thread nach Freigabe), Ergebnisbild (Minen-Zeile, Details,
## Mod-Kennzeichen, FC) und Lobby-Raum-Mods (SD/PF/MN ueber cl_state).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mv_rules_ui_tests.gd

var _passed := 0
var _failed := 0
var _started := false


## Zaehlt Fehler/Skriptfehler (Logger, Godot 4.5+), auch aus Threads.
class ErrLog extends Logger:
	var n := 0
	var last := ""
	var mx := Mutex.new()

	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		mx.lock()
		n += 1
		last = "%s: %s %s" % [function, code, rationale]
		mx.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()   # laeuft mit await weiter; Autoloads sind hier schon da
	return false


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _run() -> void:
	print("=== OMEN Regel-Mods-UI-Tests ===")
	await _test_maxpp_after_free()
	await _test_maxpp_delivers()
	await _test_callbacks_after_leave()
	await _test_results_mines()
	_test_lobby_room_mods()
	_test_trace_fail_time()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bug (SD/PF-Shots): Browser wird frei, waehrend der Max-pp-Thread rechnet; danach griff
## der Thread auf das freigegebene self zu ("_on_maxpp_done" auf 'previously freed').
func _test_maxpp_after_free() -> void:
	print("- Max-pp nach Freigabe des Browsers")
	var SS: GDScript = load("res://scripts/song_select.gd")
	var ss: Control = SS.new()
	var id := ss.get_instance_id()
	ss.free()
	var log := ErrLog.new()
	OS.add_logger(log)
	var th := Thread.new()
	# Leere Pfade: StarService rechnet nichts und schreibt keinen Cache.
	th.start(Callable(SS, "_maxpp_job").bind(SS, id, "", "", 0))
	th.wait_to_finish()
	for i in 3:
		await process_frame
	OS.remove_logger(log)
	_ok(log.n == 0, "kein Fehler nach Freigabe (%d: %s)" % [log.n, log.last])


## Lebender Browser bekommt das Ergebnis (Thread wird eingesammelt).
func _test_maxpp_delivers() -> void:
	print("- Max-pp an lebenden Browser")
	var SS: GDScript = load("res://scripts/song_select.gd")
	var ss: Control = SS.new()
	var th := Thread.new()
	ss.set("_maxpp_thread", th)
	th.start(Callable(SS, "_maxpp_job").bind(SS, ss.get_instance_id(), "", "", 0))
	var frames := 0
	while ss.get("_maxpp_thread") != null and frames < 120:
		await process_frame
		frames += 1
	_ok(ss.get("_maxpp_thread") == null, "Ergebnis angekommen, Thread eingesammelt (%d Bilder)" % frames)
	ss.free()


## Bug: Rueckläufer aus Threads/Signalen (call_deferred) kommen nach einem
## Szenenwechsel an, wenn der Browser schon aus dem Baum ist, aber noch lebt:
## _bg_finished griff auf get_tree() (null) zu, _orbit_stars_done startete einen
## neuen Thread, _on_import_finished baute Hinweis/Auswahl.
func _test_callbacks_after_leave() -> void:
	print("- Thread-/Signal-Ruecklaeufer nach Verlassen des Browsers")
	var SS: GDScript = load("res://scripts/song_select.gd")
	var ss: Control = SS.new()
	var log := ErrLog.new()
	OS.add_logger(log)
	ss.call("_bg_finished", {"key": "qa|leave", "osz": "", "mode": "orbit"}, -1.0)
	ss.set("_play_mode", "orbit")
	ss.call("_bg_finished", {"key": "qa|leave2", "osz": "", "mode": "orbit"}, -1.0)
	ss.set("_os_want", "qa|other")
	ss.set("_os_want_args", ["", "", "orbit"])
	ss.call("_orbit_stars_done", "qa|leave", -1.0)
	var started: bool = ss.get("_os_thread") != null
	if started:
		(ss.get("_os_thread") as Thread).wait_to_finish()
		ss.set("_os_thread", null)
	ss.call("_on_import_progress", 1, 2, "")
	ss.call("_on_import_finished", {"imported": [], "failed": 1})
	for i in 3:
		await process_frame
	OS.remove_logger(log)
	_ok(log.n == 0, "kein Fehler ausserhalb des Baums (%d: %s)" % [log.n, log.last])
	_ok(not started, "kein neuer Orbit-Sterne-Thread nach dem Verlassen")
	ss.free()


func _stats(mines: int, hits: int, n_miss: int) -> Dictionary:
	var d := {"score": 812345, "accuracy": 0.9712, "grade": "S", "max_combo": 420,
		"n_max": 300, "n300": 100, "n200": 10, "n100": 2, "n50": 0, "n_miss": n_miss,
		"mods": ["SD", "MN"], "mod_mult": 1.0, "failed": false}
	if mines >= 0:
		d["mines"] = mines
		d["mine_hits"] = hits
	return d


func _jlog() -> Array:
	var out: Array = []
	for i in 80:
		out.append(Vector4(500.0 + 250.0 * i, float(i % 4), 0.0 if i % 5 else 1.0, 3.0))
	return out


func _results(stats: Dictionary, mods: Dictionary) -> Control:
	var rs: Control = load("res://scripts/ui/results_screen.gd").new()
	root.add_child(rs)
	rs.show_results({"is_fail": false, "s": stats, "mods": mods, "pp": -1.0, "title": "T", "artist": "A",
		"version": "V", "judge_log": _jlog(), "offsets": [], "player": "P", "date": "2026-11-14T10:00:00"})
	return rs


## Ergebnisbild: ruhige Minen-Zeile im Ueberblick, Minen-Kennzahlen im Details-Reiter,
## Kennzeichen SD/Mines im Kopf, FC nur ohne ausgeloeste Mine.
func _test_results_mines() -> void:
	print("- Ergebnisbild mit Minen")
	var rs := _results(_stats(42, 3, 0), {"SD": true, "MN": true, "MN_v": 1})
	await process_frame
	var line := rs.find_child("MinesLine", true, false) as Label
	_ok(line != null and line.text.contains("42") and line.text.contains("3"),
			"Ueberblick: Minen-Zeile '%s'" % (line.text if line != null else "-"))
	var row := rs.find_child("MinesRow", true, false)
	_ok(row != null and row.get_child_count() == 4, "Details: Minen gesamt / ausgeloest / ausgewichen")
	var texts: Array = rs.call("mod_badge_texts")
	_ok(texts.has("SD") and texts.has(RuleMods.label("MN")), "Kennzeichen SD + Mines: %s" % str(texts))
	var badges: Array = rs.call("_badges")
	_ok(not badges.any(func(b): return str(b[0]) == "FC"), "kein FC mit 3 Minen-Treffern")
	_ok(not _has_text(rs, "FULL COMBO"), "Rang-Zeile: kein FULL COMBO mit Minen-Treffern")
	rs.queue_free()
	await process_frame
	rs = _results(_stats(-1, 0, 0), {"PF": true})
	await process_frame
	_ok(rs.find_child("MinesLine", true, false) == null and rs.find_child("MinesRow", true, false) == null,
			"ohne Minen: keine Minen-Zeile")
	texts = rs.call("mod_badge_texts")
	_ok(texts == ["PF"], "Kennzeichen PF: %s" % str(texts))
	badges = rs.call("_badges")
	_ok(badges.any(func(b): return str(b[0]) == "FC"), "FC ohne Miss und ohne Minen")
	_ok(_has_text(rs, "FULL COMBO"), "Rang-Zeile: FULL COMBO ohne Minen")
	rs.queue_free()
	await process_frame


## Trace (Sudden Death/Perfect-Fail): Fail-Marker zeigte 0:00, weil fail_ms nach
## SyncClock.stop() aus der Uhr kam. Jetzt die letzte Wertungszeit wie in Rebound.
func _test_trace_fail_time() -> void:
	print("- Trace: Fail-Zeit")
	var src := FileAccess.get_file_as_string("res://scripts/trace/trace_game.gd")
	_ok(not src.contains('data["fail_ms"] = maxf(_time_ms()'), "fail_ms nicht aus der gestoppten Uhr")
	_ok(src.contains('data["fail_ms"] = maxf(_last_update_t, 0.0)'), "fail_ms = letzte Wertungszeit")


func _has_text(n: Node, t: String) -> bool:
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).text == t:
			return true
	return false


## Lobby: Raum-Mods kommen beim Client (cl_state) samt Minen-Version an; Mod-Liste der
## Endergebnisse ohne "MN_v".
func _test_lobby_room_mods() -> void:
	print("- Lobby-Raum-Mods")
	var L = root.get_node("Lobby")
	L._reset()
	L.active = true
	L.is_host = true
	L.crown_id = 1
	L.players = {1: L._new_player("Host"), 2: L._new_player("Anna")}
	L.pick_mods(RuleMods.lobby_toggle(RuleMods.lobby_toggle(L.mods, "SD"), "MN"))
	_ok(RuleMods.has(L.mods, "SD") and RuleMods.has(L.mods, "MN") and int(L.mods.get("MN_v", 0)) == MineGen.VERSION,
			"Host setzt SD + MN: %s" % str(L.mods))
	_ok(L.mods_text(L.mods) == "SD MN", "mods_text: %s" % L.mods_text(L.mods))
	_ok(L._mods_list() == ["SD", "MN"], "Endergebnis-Mods ohne MN_v: %s" % str(L._mods_list()))
	var snap: Dictionary = L.mods.duplicate()
	snap["MN_v"] = 1
	L.mods = {"SV": false, "NF": false}
	L.cl_state(L.players, 1, {}, "R", [], snap)
	_ok(L.mods == snap, "cl_state uebernimmt SD/MN und MN_v des Hosts: %s" % str(L.mods))
	L.pick_mods(RuleMods.lobby_toggle(L.mods, "NF"))
	_ok(bool(L.mods.NF) and not L.mods.has("SD") and RuleMods.has(L.mods, "MN"), "NF im Raum schaltet SD aus: %s" % str(L.mods))
	L._reset()
	_ok(L.mods == {"SV": false, "NF": false}, "Reset: Mods aus")
