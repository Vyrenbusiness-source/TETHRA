extends SceneTree

## Headless-Tests fuer das Dirigent-Tutorial: fuenf Schritte, jeder per Bot (echte
## Maus-/Tasten-Events) loesbar, Uebungs-Spur nach dem Spiel-Chart (Figur, Raster,
## Handtempo), Fehler nennen den Grund (zu frueh / zu spaet / falscher Punkt /
## falsche Taste), Tasten aus den Settings, Ueberspringen, Gesehen-Merker,
## Mini-Song mit Wertung, alle Texte in translations/dirigent.csv.
## Das Tutorial nutzt das Autoload Settings, darum nur per load().
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_dirigent_tutorial_tests.gd

const SCENE := "res://scenes/dirigent_tutorial.tscn"
const SCRIPT := "res://scripts/dirigent/dirigent_tutorial.gd"
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
	print("=== TETHRA Dirigent-Tutorial-Tests ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/dirigent_tutorial_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	_test_charts(S)
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_check(tut.view.unit_px() > 1.0, "Ansicht hat eine Groesse")
	_test_bot_run(tut, S)
	_test_beat_reasons(tut)
	_test_key_reasons(tut)
	_test_wrong_aim_no_credit(tut)
	_test_mouse_buttons(tut)
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


func _run_to(tut: Control, t: float) -> void:
	while float(tut.t_ms) < t:
		tut.advance(FRAME)


func _move(tut: Control, u: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = tut.view.global_position + tut.view.to_px(u)
	tut.handle_input(ev)


func _key(tut: Control, k: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _settings().dirigent_key_a if k == 0 else _settings().dirigent_key_b
	ev.pressed = down
	tut.handle_input(ev)


func _tap(tut: Control, k: int) -> void:
	_key(tut, k, true)
	_key(tut, k, false)


# ---------------------------------------------------------------------------

## Spur: fuenf Schritte, Figur je Taktart, Raster, Einsaetze auf der Leiste, ruhige Hand.
func _test_charts(S: GDScript) -> void:
	_check(int(S.STEP_COUNT) == 5, "fuenf Schritte")
	var songs: Array = S.patterns(4)
	_check(songs.size() == 8, "Mini-Song hat 8 Takte")
	for s in int(S.STEP_COUNT):
		var c: DirigentChart = S.make_chart(s, 1000.0)
		var n: int = DirigentChart.figure_kind(int(S.METERS[s])).n
		_check(c.beats.size() == S.patterns(s).size() * n, "Schritt %d: Schlaege = Takte x Punkte" % (s + 1))
		_check(c.bars.size() == S.patterns(s).size(), "Schritt %d: Takte" % (s + 1))
		var sorted := true
		for i in range(1, c.beats.size()):
			sorted = sorted and float(c.beats[i].t) > float(c.beats[i - 1].t)
		for i in range(1, c.cues.size()):
			sorted = sorted and float(c.cues[i].t) > float(c.cues[i - 1].t)
		_check(sorted, "Schritt %d: Zeiten steigen" % (s + 1))
		_check(is_equal_approx(float(c.beats[0].t), 1000.0), "Schritt %d: erster Schlag auf t0" % (s + 1))
		var calm := true
		for i in range(1, c.beats.size()):
			var sp: float = (c.beats[i].pos as Vector2).distance_to(c.beats[i - 1].pos) \
					/ ((float(c.beats[i].t) - float(c.beats[i - 1].t)) / 1000.0)
			calm = calm and sp <= DirigentChart.MAX_SPEED
		_check(calm, "Schritt %d: Handtempo <= MAX_SPEED" % (s + 1))
		var inside := true
		for q in c.cues:
			inside = inside and float(q.t) >= float(c.beats[0].t) and float(q.t) <= float(c.beats[-1].t) + 1000.0
		_check(inside, "Schritt %d: Einsaetze liegen in der Spur" % (s + 1))
	_check(S.make_chart(0, 0.0).cues.is_empty() and S.make_chart(1, 0.0).cues.is_empty(),
			"Schritte 1 und 2 ohne Einsaetze")
	_check(S.make_chart(1, 0.0).bars[0].kind == "34", "Schritt 2: Dreiecksfigur")
	var kinds := {}
	for q in S.make_chart(2, 0.0).cues:
		kinds[int(q.mask)] = true
	_check(kinds.has(1) and kinds.has(2) and kinds.has(3), "Schritt 3: A, B und beide")
	var half := 0
	var c4: DirigentChart = S.make_chart(3, 0.0)
	for q in c4.cues:
		var beat_pos := float(q.t) / 1000.0
		if absf(beat_pos - roundf(beat_pos)) > 0.01:
			half += 1
	_check(half >= 1, "Schritt 4: Einsatz zwischen den Schlaegen")


func _test_bot_run(tut: Control, S: GDScript) -> void:
	tut.bot = true
	for s in 4:
		_check(int(tut.step) == s, "Schritt %d aktiv" % (s + 1))
		var best := [0]
		var reached := _run_until(tut, func():
			best[0] = maxi(best[0], int(tut.success))
			return int(tut.step) != s)
		_check(reached and int(tut.step) == s + 1, "Schritt %d per Bot geloest" % (s + 1))
		_check(best[0] >= int(S.NEED[s]), "Schritt %d: Bedingung erfuellt (%d)" % [s + 1, best[0]])
	_check(int(tut.step) == 4, "Mini-Song erreicht")
	var ok := _run_until(tut, func(): return bool(tut.finished), 9000)
	_check(ok, "Mini-Song endet mit Wertung")
	var st: Dictionary = tut.trial_stats
	var want: int = tut.chart.cues.size()
	var total := int(st.get("n_max", 0)) + int(st.get("n300", 0)) + int(st.get("n200", 0)) \
			+ int(st.get("n100", 0)) + int(st.get("n50", 0)) + int(st.get("n_miss", 0))
	_check(total == want and want > 20, "alle Einsaetze gewertet (%d von %d)" % [total, want])
	_check(int(st.get("n_miss", 1)) == 0, "Bot ohne verpassten Einsatz")
	_check(int(st.get("beats_hit", 0)) == int(st.get("beats_total", -1)) and int(st.get("beats_total", 0)) == 32,
			"alle 32 Schlaege getroffen")
	_check(str(tut.trial_grade()) in ["SS", "S"], "Rang aus DirigentCore (%s)" % tut.trial_grade())
	_check(tut.trial_accuracy() > 0.95, "Genauigkeit hoch")
	tut.bot = false
	tut.retry_trial()
	_check(not bool(tut.finished) and int(tut.step) == 4, "Nochmal startet den Mini-Song neu")


## Fehlergruende am Punkt: zu frueh, zu spaet, falscher Punkt, daneben.
func _test_beat_reasons(tut: Control) -> void:
	tut.bot = false
	# zu spaet: Hand kommt erst nach dem Schlag.
	tut.enter_step(1)
	var b: Dictionary = tut.chart.beats[0]
	_move(tut, Vector2(0.9, 0.9))
	_run_to(tut, float(b.t) + 40.0)
	_move(tut, b.pos)
	_run_to(tut, float(b.t) + 120.0)
	_check(str(tut.last_reason) == "late", "zu spaet erkannt (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "zu spaet zaehlt nicht")
	# zu frueh: Hand war da, ist vor dem Schlag weg.
	tut.enter_step(1)
	b = tut.chart.beats[0]
	_run_to(tut, float(b.t) - 350.0)
	_move(tut, b.pos)
	_run_to(tut, float(b.t) - 200.0)
	_move(tut, Vector2(0.9, 0.9))
	_run_to(tut, float(b.t) + 60.0)
	_check(str(tut.last_reason) == "early", "zu frueh erkannt (%s)" % tut.last_reason)
	_check(str(tut.reason_hint("early")).length() > 10, "Hinweistext zu frueh")
	# falscher Punkt: Hand liegt auf Punkt 2, gefragt ist Punkt 1.
	tut.enter_step(0)
	b = tut.chart.beats[0]
	_move(tut, tut.chart.beats[1].pos)
	_run_to(tut, float(b.t) + 60.0)
	_check(str(tut.last_reason) == "wrong", "falscher Punkt erkannt (%s)" % tut.last_reason)
	# daneben: Hand irgendwo, nie auf dem Punkt.
	tut.enter_step(0)
	b = tut.chart.beats[0]
	_move(tut, Vector2(0.85, -0.85))
	_run_to(tut, float(b.t) + 700.0)
	_check(str(tut.last_reason) == "off", "daneben erkannt (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "daneben zaehlt nicht")
	# treffen zaehlt.
	tut.enter_step(0)
	b = tut.chart.beats[0]
	_move(tut, b.pos)
	_run_to(tut, float(b.t) + 60.0)
	_check(int(tut.success) == 1, "Treffer zaehlt")


## Fehlergruende an der Leiste: falsche Taste, zu frueh, keine Marke, beide Tasten.
func _test_key_reasons(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(2)
	var c: Dictionary = tut.chart.cues[0]
	_move(tut, tut.chart.beats[0].pos)
	_run_to(tut, float(c.t) - 10.0)
	_tap(tut, 1)
	_check(str(tut.last_reason) == "key", "falsche Taste erkannt (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "falsche Taste zaehlt nicht")
	_run_to(tut, float(c.t) + 20.0)
	_tap(tut, 0)
	_check(int(tut.success) == 1, "richtige Taste zaehlt")
	# zu frueh: Taste lange vor dem naechsten Mark.
	tut.enter_step(2)
	c = tut.chart.cues[0]
	_run_to(tut, float(c.t) - 350.0)
	_tap(tut, 0)
	_check(str(tut.last_reason) == "early", "Taste zu frueh erkannt (%s)" % tut.last_reason)
	# keine Marke in Reichweite.
	tut.enter_step(2)
	_run_to(tut, float(tut.chart.cues[0].t) - 1200.0)
	_tap(tut, 0)
	_check(str(tut.last_reason) == "nomark", "keine Marke erkannt (%s)" % tut.last_reason)
	# beide Tasten: nur eine gedrueckt beim Akzent.
	tut.enter_step(2)
	var idx := -1
	for i in tut.chart.cues.size():
		if int(tut.chart.cues[i].mask) == 3:
			idx = i
			break
	_check(idx >= 0, "Akzent-Marke vorhanden")
	var ct: float = tut.chart.cues[idx].t
	_run_to(tut, ct - 10.0)
	_tap(tut, 0)
	_run_to(tut, ct + 400.0)
	_check(str(tut.last_reason) == "both", "beide Tasten erkannt (%s)" % tut.last_reason)
	# Akzent mit beiden Tasten zaehlt.
	tut.enter_step(2)
	ct = tut.chart.cues[idx].t
	_run_to(tut, ct - 10.0)
	var before := int(tut.success)
	_key(tut, 0, true)
	_key(tut, 1, true)
	_key(tut, 0, false)
	_key(tut, 1, false)
	_run_to(tut, ct + 100.0)
	_check(int(tut.success) == before + 1, "Akzent mit beiden Tasten zaehlt")


## Schritt 4: Einsatz mit Hand weit weg vom Punkt zaehlt nicht.
func _test_wrong_aim_no_credit(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(3)
	var c: Dictionary = tut.chart.cues[0]
	_move(tut, Vector2(0.9, -0.9))
	_run_to(tut, float(c.t) - 5.0)
	_tap(tut, 0)
	_run_to(tut, float(c.t) + 50.0)
	_check(int(tut.success) == 0, "Beides: Einsatz ohne Hand am Punkt zaehlt nicht")
	_check(str(tut.last_reason) == "off", "Beides: Grund 'daneben' (%s)" % tut.last_reason)


func _test_mouse_buttons(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(2)
	var c: Dictionary = tut.chart.cues[0]
	_run_to(tut, float(c.t) - 8.0)
	var ev := InputEventMouseButton.new()
	ev.position = tut.view.global_position + tut.view.to_px(Vector2(0, 0.6))
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	tut.handle_input(ev)
	_check(int(tut.success) == 1, "Linksklick = Taste A")
	ev.pressed = false
	tut.handle_input(ev)
	tut.enter_step(2)
	var cb := -1
	for i in tut.chart.cues.size():
		if int(tut.chart.cues[i].mask) == 2:
			cb = i
			break
	_run_to(tut, float(tut.chart.cues[cb].t) - 8.0)
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	tut.handle_input(ev)
	_check(int(tut.success) == 1, "Rechtsklick = Taste B")
	ev.pressed = false
	tut.handle_input(ev)


func _test_keys_from_settings(tut: Control) -> void:
	var st := _settings()
	var old_a: int = st.dirigent_key_a
	var old_b: int = st.dirigent_key_b
	st.dirigent_key_a = KEY_K
	st.dirigent_key_b = KEY_L
	_check(str(tut.key_label(0)) == "K" and str(tut.key_label(1)) == "L", "Tasten-Namen aus den Settings")
	tut.bot = false
	tut.enter_step(2)
	var c: Dictionary = tut.chart.cues[0]
	_run_to(tut, float(c.t) - 8.0)
	_tap(tut, 0)
	_check(int(tut.success) == 1, "Taste A aus den Settings spielt")
	st.dirigent_key_a = old_a
	st.dirigent_key_b = old_b


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


## Alle tr()-Texte stehen in translations/dirigent.csv (de + en) und wirken.
func _test_texts(S: GDScript, tut: Control) -> void:
	var src := FileAccess.get_file_as_string(SCRIPT)
	var re := RegEx.new()
	re.compile("tr\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var keys := {}
	var f := FileAccess.open("res://translations/dirigent.csv", FileAccess.READ)
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
	_check(str(tut.title_for(0)) == "Dem Takt folgen", "Deutsch: Titel Schritt 1 (%s)" % tut.title_for(0))
	TranslationServer.set_locale("en")
	_check(str(tut.title_for(0)) == "Follow the beat", "Englisch: Titel Schritt 1")
