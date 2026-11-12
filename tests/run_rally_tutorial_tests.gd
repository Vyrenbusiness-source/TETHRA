extends SceneTree

## Headless-Tests fuer das Rally-Tutorial: fuenf Schritte, jeder per Bot (echte
## Zonentasten-Eingabe) loesbar bei 3 und 4 Zonen, Uebungsfolgen nach dem Spiel-Chart
## (Zonen, Smash, Aufladen), Fehler nennen den Grund (zu frueh / zu spaet / falsche
## Zone / Smash mit einer Taste / Hold zu frueh), Tasten aus den Settings,
## Ueberspringen, Gesehen-Merker, Mini-Song mit Wertung, alle Texte in
## translations/rally.csv. Das Tutorial nutzt das Autoload Settings, darum nur per load().
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_rally_tutorial_tests.gd

const SCENE := "res://scenes/rally_tutorial.tscn"
const SCRIPT := "res://scripts/rally/rally_tutorial.gd"
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
	print("=== TETHRA Rally-Tutorial-Tests ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	var old_zones: int = _settings().rally_zones
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/rally_tutorial_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	for n in [4, 3]:
		_settings().rally_zones = n
		_test_charts(S, n)
	_settings().rally_zones = 4
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_check(tut.view != null and tut.view.offset_top > 0.0, "Ansicht unter dem Textkopf")
	for n in [4, 3]:
		_settings().rally_zones = n
		_test_bot_run(tut, n)
	_settings().rally_zones = 4
	_test_reasons(tut)
	_test_keys_from_settings(tut)
	_test_skip(tut)
	_test_texts(S, tut)
	tut.queue_free()
	DirAccess.remove_absolute(S.seen_path)
	S.seen_path = old_seen
	_settings().rally_zones = old_zones
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bis cond wahr ist simulieren (max. limit Frames); true, wenn erreicht.
func _run_until(tut: Control, cond: Callable, limit: int = 6000) -> bool:
	for i in limit:
		if cond.call():
			return true
		tut.advance(FRAME)
	return cond.call()


func _key(tut: Control, zone: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = _settings().rally_keys(int(tut.zones))[zone]
	ev.pressed = down
	tut.handle_input(ev)


# ---------------------------------------------------------------------------

func _test_charts(S: GDScript, n: int) -> void:
	_check(int(S.STEP_COUNT) == 5, "fuenf Schritte")
	for s in 5:
		var shots: Array = S.make_shots(s, 3000.0, n, 800.0)
		_check(shots.size() >= 4, "Schritt %d (%d Zonen): Schlaege" % [s + 1, n])
		var ok := true
		var smash := 0
		var charge := 0
		for i in shots.size():
			var sh = shots[i]
			for z in sh.zones:
				ok = ok and z >= 0 and z < n
			if i > 0:
				ok = ok and sh.t > shots[i - 1].end
			if sh.smash:
				smash += 1
				ok = ok and sh.zones.size() == 2 and sh.zones[0] != sh.zones[1]
			if sh.is_charge():
				charge += 1
			ok = ok and sh.launch < sh.t
		_check(ok, "Schritt %d (%d Zonen): Zonen, Abstaende, Flug" % [s + 1, n])
		if s == 2:
			_check(smash >= 3, "Smash-Schritt hat Schmetterbaelle (%d)" % n)
		if s == 3:
			_check(charge >= 3, "Halten-Schritt hat Aufladungen (%d)" % n)
		if s == 0 or s == 1:
			_check(smash == 0 and charge == 0, "Schritt %d: nur einfache Baelle" % [s + 1])
	var arc: Array = S.make_shots(1, 0.0, n, 800.0)
	var gaps := []
	for i in range(1, arc.size()):
		gaps.append(arc[i].t - arc[i - 1].t)
	_check(gaps.min() < 400.0 and gaps.max() > 1200.0, "Bogen-Schritt mischt Lob und flache Baelle")
	var song: Array = S.make_shots(4, 0.0, n, 800.0)
	_check(song.size() >= 15, "Mini-Song hat genug Schlaege")


func _test_bot_run(tut: Control, n: int) -> void:
	tut.bot = true
	tut.retry_trial() if bool(tut.finished) else null
	tut.enter_step(0)
	_check(int(tut.zones) == n, "Zonenzahl aus Settings (%d)" % n)
	for s in 4:
		tut.enter_step(s)
		var ok := _run_until(tut, func(): return int(tut.step) > s, 12000)
		_check(ok, "Bot loest Schritt %d (%d Zonen)" % [s + 1, n])
	_check(int(tut.step) == 4, "nach Schritt 4 kommt der Mini-Song")
	var fin := _run_until(tut, func(): return bool(tut.finished), 20000)
	_check(fin, "Bot spielt den Mini-Song bis zur Wertung (%d Zonen)" % n)
	_check(str(tut.trial_grade()) != "-" and float(tut.trial_accuracy()) > 0.95,
			"Wertung: Note %s, Genauigkeit %.3f" % [tut.trial_grade(), tut.trial_accuracy()])
	_check(int(tut.trial_stats.get("n_miss", 99)) == 0, "Bot ohne Fehler")
	tut.retry_trial()
	tut.bot = false


## Ball in Reichweite bringen: Zeit auf shots[i].t + off setzen (ohne Eingaben).
func _to_ball(tut: Control, i: int, off: float) -> void:
	_run_until(tut, func(): return float(tut.t_ms) >= float(tut.shots[i].t) + off, 20000)


func _test_reasons(tut: Control) -> void:
	tut.bot = false
	# Falsche Zone.
	tut.enter_step(0)
	var z0: int = tut.shots[0].zones[0]
	var wrong := 3 if z0 < 2 else 0
	_to_ball(tut, 0, -40.0)
	_key(tut, wrong, true)
	_key(tut, wrong, false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "zone", "falsche Zone: Grund (%s)" % tut.last_reason)
	_check(tut.fx.size() > 0 and str(tut.fx[-1][2]) == tut.reason_short("zone"), "falsche Zone: Text am Ort")
	_check(int(tut.success) == 0, "falsche Zone zaehlt nicht")
	# Zu frueh (im Fenster vor dem Ball).
	tut.enter_step(0)
	_to_ball(tut, 0, -160.0)
	_key(tut, int(tut.shots[0].zones[0]), true)
	_key(tut, int(tut.shots[0].zones[0]), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "early", "zu frueh: Grund (%s)" % tut.last_reason)
	# Ohne Taste: "keine Taste" nach der Frist.
	tut.enter_step(0)
	_to_ball(tut, 0, 700.0)
	_check(str(tut.last_reason) == "none", "ohne Taste: Grund (%s)" % tut.last_reason)
	# Zu spaet: Taste nach dem Fenster.
	tut.enter_step(0)
	_to_ball(tut, 0, float(tut.core.w50) + 30.0)
	_key(tut, int(tut.shots[0].zones[0]), true)
	_key(tut, int(tut.shots[0].zones[0]), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "late", "zu spaet: Grund (%s)" % tut.last_reason)
	# Smash mit einer Taste.
	tut.enter_step(2)
	var sm = tut.shots[0]
	_to_ball(tut, 0, -3.0)
	_key(tut, int(sm.zones[0]), true)
	_key(tut, int(sm.zones[0]), false)
	_to_ball(tut, 0, 120.0)
	_check(str(tut.last_reason) == "smash", "Smash mit einer Taste: Grund (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "Smash mit einer Taste zaehlt nicht")
	# Smash mit beiden Tasten zaehlt.
	tut.enter_step(2)
	sm = tut.shots[0]
	_to_ball(tut, 0, -3.0)
	_key(tut, int(sm.zones[0]), true)
	_key(tut, int(sm.zones[1]), true)
	tut.advance(FRAME)
	_key(tut, int(sm.zones[0]), false)
	_key(tut, int(sm.zones[1]), false)
	tut.advance(FRAME * 4.0)
	_check(int(tut.success) == 1, "Smash mit beiden Tasten zaehlt (%d)" % tut.success)
	# Hold zu frueh losgelassen.
	tut.enter_step(3)
	var h = tut.shots[0]
	_to_ball(tut, 0, -3.0)
	_key(tut, int(h.zones[0]), true)
	tut.advance(250.0)
	_key(tut, int(h.zones[0]), false)
	tut.advance(FRAME)
	_check(str(tut.last_reason) == "hold", "Hold zu frueh: Grund (%s)" % tut.last_reason)
	_check(int(tut.success) == 0, "zu frueh losgelassener Hold zaehlt nicht")
	# Hold sauber gehalten zaehlt.
	tut.enter_step(3)
	h = tut.shots[0]
	_to_ball(tut, 0, -3.0)
	_key(tut, int(h.zones[0]), true)
	_to_ball(tut, 0, float(h.end - h.t) + 5.0)
	_key(tut, int(h.zones[0]), false)
	tut.advance(FRAME)
	_check(int(tut.success) == 1, "Hold gehalten zaehlt (%d)" % tut.success)
	# Hinweistexte nennen die Taste der Zone.
	var hint: String = tut.reason_hint("zone", 1)
	_check(hint.contains(str(tut.key_label(1))), "Hinweis nennt die Taste")


func _test_keys_from_settings(tut: Control) -> void:
	var st := _settings()
	# Rally hat eigene Tasten je Zonenzahl (Settings.rally_keys_3 / rally_keys_4).
	var old3: Array[int] = st.rally_keys_3.duplicate()
	var old4: Array[int] = st.rally_keys_4.duplicate()
	var nk3: Array[int] = [KEY_Q, KEY_W, KEY_E]
	var nk4: Array[int] = [KEY_Q, KEY_W, KEY_E, KEY_R]
	st.rally_keys_3 = nk3
	st.rally_keys_4 = nk4
	tut.enter_step(0)
	var want: Array = ["Q", "W", "E", "R"] if int(tut.zones) == 4 else ["Q", "W", "E"]
	var want_txt := "  ".join(PackedStringArray(want))
	_check(tut.key_labels() == want, "Tasten aus der Belegung: %s" % str(tut.key_labels()))
	_check(str(tut.body_for(0)).contains(want_txt), "Text nennt die aktuelle Belegung")
	_check(tut.view.key_labels == want, "Ansicht zeigt die Belegung")
	tut.bot = false
	_run_until(tut, func(): return float(tut.t_ms) >= float(tut.shots[0].t) - 2.0, 20000)
	var z: int = tut.shots[0].zones[0]
	_key(tut, z, true)
	_key(tut, z, false)
	tut.advance(FRAME * 3.0)
	_check(int(tut.success) == 1, "Eingabe ueber die Belegung trifft")
	st.rally_keys_3 = old3
	st.rally_keys_4 = old4


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


## Alle tr()-Texte stehen in translations/rally.csv (de + en) und wirken.
func _test_texts(_S: GDScript, tut: Control) -> void:
	var src := FileAccess.get_file_as_string(SCRIPT)
	var re := RegEx.new()
	re.compile("tr\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var keys := {}
	var f := FileAccess.open("res://translations/rally.csv", FileAccess.READ)
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
	_check(str(tut.title_for(0)) == "Landen und drücken", "Deutsch: Titel Schritt 1 (%s)" % tut.title_for(0))
	TranslationServer.set_locale("en")
	_check(str(tut.title_for(0)) == "Land and press", "Englisch: Titel Schritt 1")
