extends SceneTree

## Headless-Tests fuer das Trace-Tutorial: fuenf Schritte, jeder per Bot (echte
## Tasten-Eingabe) loesbar, Uebungsfolgen nach dem Spiel-Chart (Mania 4K: Pfeile,
## Akkorde, Holds, Faden-Geometrie), Fehler nennen den Grund (zu frueh / zu spaet /
## falsche Taste / Akkord mit einer Taste / Hold zu frueh), Tasten aus den Settings,
## Ueberspringen, Gesehen-Merker, Mini-Song mit Wertung, alle Texte in
## translations/trace.csv. Das Tutorial nutzt das Autoload Settings, darum nur per load().
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_trace_tutorial_tests.gd

const SCENE := "res://scenes/trace_tutorial.tscn"
const SCRIPT := "res://scripts/trace/trace_tutorial.gd"
const FRAME := 1000.0 / 60.0

var _passed := 0
var _failed := 0
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


func _settings() -> Node:
	return root.get_node("Settings")


func _run() -> void:
	print("=== TETHRA Trace-Tutorial-Tests ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/trace_tutorial_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	_test_charts(S)
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_check(tut.view != null and tut.view.clip_contents and tut.view.offset_top > 0.0, "Ansicht unter dem Textkopf")
	_test_bot_run(tut)
	_test_reasons(tut)
	_test_keys_from_settings(tut)
	_test_skip(tut)
	_test_texts(S, tut)
	tut.queue_free()
	DirAccess.remove_absolute(S.seen_path)
	S.seen_path = old_seen
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bis cond wahr ist simulieren (max. limit Frames); true, wenn erreicht.
func _run_until(tut: Control, cond: Callable, limit: int = 6000) -> bool:
	for i in limit:
		if cond.call():
			return true
		tut.advance(FRAME)
	return cond.call()


func _key(tut: Control, lane: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _settings().key_lanes[lane]
	ev.pressed = down
	tut.handle_input(ev)


## Zeit auf Note i + off setzen (ohne Eingaben).
func _to_note(tut: Control, i: int, off: float) -> void:
	_run_until(tut, func(): return float(tut.t_ms) >= float(tut.bm.hit_objects[i].time) + off, 20000)


func _col(tut: Control, i: int) -> int:
	return int(tut.bm.hit_objects[i].column)


# ---------------------------------------------------------------------------

func _test_charts(S: GDScript) -> void:
	_check(int(S.STEP_COUNT) == 5, "fuenf Schritte")
	for s in 5:
		var bm: Beatmap = S.make_beatmap(s, 3000.0)
		_check(bm != null and bm.is_mania() and bm.column_count() == 4, "Schritt %d: 4K-Beatmap" % [s + 1])
		var objs := bm.hit_objects
		_check(objs.size() >= 4, "Schritt %d: Noten (%d)" % [s + 1, objs.size()])
		_check(int(objs[0].time) == 3000, "Schritt %d: erste Note zur Startzeit" % [s + 1])
		var holds := 0
		var chords := 0
		for i in objs.size():
			var n := objs[i] as ManiaNote
			if n.is_hold:
				holds += 1
			if i > 0 and absf(float(n.time) - float(objs[i - 1].time)) < 3.0:
				chords += 1
		if s == 2:
			_check(holds >= 3, "Halten-Schritt hat Holds (%d)" % holds)
		if s == 3:
			_check(chords >= 3, "Akkord-Schritt hat Akkorde (%d)" % chords)
		if s < 2:
			_check(holds == 0 and chords == 0, "Schritt %d: nur einfache Noten" % [s + 1])
		var path := TracePath.from_beatmap(bm, 520.0)
		_check(path.knots.size() >= 3, "Schritt %d: Faden hat Knicke (%d)" % [s + 1, path.knots.size()])
	var rh: Beatmap = S.make_beatmap(1, 0.0)
	var gaps := []
	for i in range(1, rh.hit_objects.size()):
		gaps.append(rh.hit_objects[i].time - rh.hit_objects[i - 1].time)
	_check(gaps.min() < 400 and gaps.max() > 1000, "Takt-Schritt mischt lange und kurze Abstaende")
	var cb: Beatmap = S.make_beatmap(1, 0.0)
	var path2 := TracePath.from_beatmap(cb, 520.0)
	_check(path2.count_kind(TracePath.Kind.SINGLE) >= 6, "Takt-Schritt: einzelne Knicke und Knoten")
	var ch: Beatmap = S.make_beatmap(3, 0.0)
	var path3 := TracePath.from_beatmap(ch, 520.0)
	_check(path3.count_kind(TracePath.Kind.DIAG) >= 2 and path3.count_kind(TracePath.Kind.CROSS) >= 1,
			"Akkord-Schritt: Diagonalen und Kreuzknoten")
	var song: Beatmap = S.make_beatmap(4, 0.0)
	_check(song.hit_objects.size() >= 20, "Mini-Song hat genug Noten")


func _test_bot_run(tut: Control) -> void:
	tut.bot = true
	tut.enter_step(0)
	for s in 4:
		tut.enter_step(s)
		var ok := _run_until(tut, func(): return int(tut.step) > s, 12000)
		_check(ok, "Bot loest Schritt %d" % [s + 1])
	_check(int(tut.step) == 4, "nach Schritt 4 kommt der Mini-Song")
	var fin := _run_until(tut, func(): return bool(tut.finished), 20000)
	_check(fin, "Bot spielt den Mini-Song bis zur Wertung")
	_check(str(tut.trial_grade()) == "SS" and float(tut.trial_accuracy()) > 0.99,
			"Wertung: Note %s, Genauigkeit %.3f" % [tut.trial_grade(), tut.trial_accuracy()])
	_check(int(tut.trial_stats.get("n_miss", 99)) == 0, "Bot ohne Fehler")
	tut.retry_trial()
	tut.bot = false


func _test_reasons(tut: Control) -> void:
	tut.bot = false
	# Falsche Taste.
	tut.enter_step(0)
	var wrong := (_col(tut, 0) + 1) % 4
	_to_note(tut, 0, -40.0)
	_key(tut, wrong, true)
	_key(tut, wrong, false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "key", "falsche Taste: Grund (%s)" % tut.last_reason)
	_check(tut.fx.size() > 0 and str(tut.fx[-1][2]) == tut.reason_short("key"), "falsche Taste: Text am Ort")
	_check(int(tut.success) == 0, "falsche Taste zaehlt nicht")
	# Zu frueh (im Fenster vor der Note).
	tut.enter_step(0)
	_to_note(tut, 0, -160.0)
	_key(tut, _col(tut, 0), true)
	_key(tut, _col(tut, 0), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "early", "zu frueh: Grund (%s)" % tut.last_reason)
	# Ohne Taste: "keine Taste" nach der Frist.
	tut.enter_step(0)
	_to_note(tut, 0, 700.0)
	_check(str(tut.last_reason) == "none", "ohne Taste: Grund (%s)" % tut.last_reason)
	# Zu spaet: Taste nach dem Fenster.
	tut.enter_step(0)
	_to_note(tut, 0, float(tut.core.w50) + 30.0)
	_key(tut, _col(tut, 0), true)
	_key(tut, _col(tut, 0), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "late", "zu spaet: Grund (%s)" % tut.last_reason)
	# Akkord mit einer Taste.
	tut.enter_step(3)
	_to_note(tut, 1, -3.0)
	_key(tut, _col(tut, 1), true)
	_key(tut, _col(tut, 1), false)
	_to_note(tut, 1, 300.0)
	_check(str(tut.last_reason) == "chord", "Akkord mit einer Taste: Grund (%s)" % tut.last_reason)
	# Akkord mit beiden Tasten zaehlt.
	tut.enter_step(3)
	_to_note(tut, 0, -3.0)
	_key(tut, _col(tut, 0), true)
	_key(tut, _col(tut, 0), false)
	_to_note(tut, 1, -3.0)
	var before := int(tut.success)
	_key(tut, _col(tut, 1), true)
	_key(tut, _col(tut, 2), true)
	tut.advance(FRAME)
	_key(tut, _col(tut, 1), false)
	_key(tut, _col(tut, 2), false)
	tut.advance(FRAME * 3.0)
	_check(int(tut.success) == before + 2, "Akkord mit beiden Tasten zaehlt (%d)" % tut.success)
	# Hold zu frueh losgelassen.
	tut.enter_step(2)
	_to_note(tut, 0, -3.0)
	_key(tut, _col(tut, 0), true)
	tut.advance(250.0)
	_key(tut, _col(tut, 0), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "hold", "Hold zu frueh: Grund (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "zu frueh losgelassener Hold zaehlt nicht")
	# Hold sauber gehalten zaehlt.
	tut.enter_step(2)
	var h = tut.bm.hit_objects[0]
	_to_note(tut, 0, -3.0)
	_key(tut, _col(tut, 0), true)
	_to_note(tut, 0, float(h.end_time() - h.time) + 5.0)
	_key(tut, _col(tut, 0), false)
	tut.advance(FRAME)
	_check(int(tut.success) == 1, "Hold gehalten zaehlt (%d)" % tut.success)
	# Hinweis nennt Taste und Richtung.
	var hint: String = tut.reason_hint("key", 1)
	_check(hint.contains(str(tut.key_label(1))) and hint.contains(str(tut.dir_name(1))), "Hinweis nennt Taste und Richtung")


func _test_keys_from_settings(tut: Control) -> void:
	var st := _settings()
	var old: Array[int] = st.key_lanes.duplicate()
	var nk: Array[int] = [KEY_Q, KEY_W, KEY_E, KEY_R]
	st.key_lanes = nk
	tut.enter_step(0)
	_check(str(tut.key_label(0)) == "Q" and str(tut.key_label(3)) == "R", "Tasten aus der Belegung")
	_check(str(tut.body_for(0)).contains("Q") and str(tut.body_for(0)).contains("R"), "Text nennt die aktuelle Belegung")
	tut.bot = false
	_to_note(tut, 0, -2.0)
	_key(tut, _col(tut, 0), true)
	_key(tut, _col(tut, 0), false)
	tut.advance(FRAME * 3.0)
	_check(int(tut.success) == 1, "Eingabe ueber die Belegung trifft")
	st.key_lanes = old


func _test_skip(tut: Control) -> void:
	tut.enter_step(0)
	tut.skip_step()
	_check(int(tut.step) == 1, "Ueberspringen: naechster Schritt")
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.pressed = true
	tut.handle_input(ev)
	_check(int(tut.step) == 2, "Tab ueberspringt")
	tut.enter_step(4)
	tut.skip_step()
	_check(bool(tut.finished), "Ueberspringen im Mini-Song zeigt das Ende")
	tut.retry_trial()
	_check(not bool(tut.finished), "Nochmal nach dem Ende")


## Alle tr()-Texte stehen in translations/trace.csv (de + en) und wirken.
func _test_texts(_S: GDScript, tut: Control) -> void:
	var src := FileAccess.get_file_as_string(SCRIPT)
	var re := RegEx.new()
	re.compile("tr\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var keys := {}
	var f := FileAccess.open("res://translations/trace.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3:
			keys[row[0]] = row
	var n := 0
	var missing: Array = []
	for m in re.search_all(src):
		n += 1
		var k := m.get_string(1)
		if not keys.has(k) or str(keys[k][1]).strip_edges() == "" or str(keys[k][2]).strip_edges() == "":
			missing.append(k)
	_check(n > 30, "tr()-Texte gefunden (%d)" % n)
	_check(missing.is_empty(), "alle Texte uebersetzt, fehlt: %s" % str(missing))
	TranslationServer.set_locale("de")
	_check(str(tut.title_for(0)) == "Jeder Knick, eine Taste", "Deutsch: Titel Schritt 1 (%s)" % tut.title_for(0))
	TranslationServer.set_locale("en")
	_check(str(tut.title_for(0)) == "Every bend, one key", "Englisch: Titel Schritt 1")
