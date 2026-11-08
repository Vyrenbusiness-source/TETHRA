extends SceneTree

## Headless-Tests fuer das Orbit-Tutorial (Taktkreis): jeder der sechs Schritte
## ist mit simulierten Eingaben (Maus-/Tasten-Events) loesbar, Fehler nennen den
## Grund, Tasten kommen aus den Settings, Ueberspringen, Gesehen-Merker.
## Das Tutorial nutzt das Autoload Settings, darum nur per load() (keine
## statischen Verweise, siehe run_mania_settings_tests.gd).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_tutorial_tests.gd

const SCENE := "res://scenes/orbit_tutorial.tscn"
const SCRIPT := "res://scripts/orbit/orbit_tutorial.gd"
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


func _run() -> void:
	print("=== TETHRA Orbit-Tutorial-Tests ===")
	var S: GDScript = load(SCRIPT)
	var old_seen: String = S.seen_path
	DirAccess.make_dir_recursive_absolute("user://test_tmp")
	S.seen_path = "user://test_tmp/orbit_tutorial_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(S.seen_path)
	_check(not S.is_seen(), "frisch: nicht gesehen")
	var tut: Control = load(SCENE).instantiate()
	tut.manual_clock = true
	root.add_child(tut)
	_check(S.is_seen(), "Start merkt gesehen")
	_test_bot_run(tut)
	_test_patterns(S)
	_test_tempo_rises(S)
	_test_bar_step(tut)
	_test_aim_step(tut)
	_test_keys_from_settings(tut)
	_test_accent_needs_both(tut)
	_test_hold_needs_hold(tut)
	_test_preview(tut)
	_test_skip(tut)
	tut.queue_free()
	DirAccess.remove_absolute(S.seen_path)
	S.seen_path = old_seen
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bis cond wahr ist simulieren (max. limit Frames); true, wenn erreicht.
func _run_until(tut: Control, cond: Callable, limit: int = 4000) -> bool:
	for i in limit:
		if cond.call():
			return true
		tut.advance(FRAME)
	return cond.call()


func _test_bot_run(tut: Control) -> void:
	tut.bot = true
	tut.enter_step(0)
	for s in 6:
		_check(int(tut.step) == s, "Schritt %d aktiv" % (s + 1))
		var best := [0]
		var reached := _run_until(tut, func():
			best[0] = maxi(best[0], int(tut.success))
			return int(tut.step) != s)
		_check(reached and int(tut.step) == s + 1, "Schritt %d per Bot geloest" % (s + 1))
		_check(best[0] >= 3, "Schritt %d: 3x geschafft vor dem Weiter (%d)" % [s + 1, best[0]])
	_check(int(tut.step) == 6, "Probe-Runde erreicht")
	var ok := _run_until(tut, func(): return bool(tut.finished))
	_check(ok, "Probe-Runde endet mit Wertung")
	var total := 0
	for c in tut.tiers:
		total += int(c)
	var want: int = tut.pattern(6, 0.0, 1000.0, 0, 0).size()
	_check(total == want, "alle Probe-Ziele gewertet (%d von %d)" % [total, want])
	_check(int(tut.tiers[5]) == 0, "Bot ohne Fehltreffer")
	_check(float(tut.trial_accuracy()) > 0.9, "Bot-Genauigkeit > 90 %% (%.3f)" % tut.trial_accuracy())
	_check(str(tut.trial_grade()) in ["SS", "S", "A"], "Rang aus der Wertung (%s)" % tut.trial_grade())
	tut.bot = false
	tut._retry_trial()
	_check(not bool(tut.finished) and int(tut.step) == 6, "Nochmal startet die Probe-Runde neu")


## Alle Noten auf dem Achtel-Raster, Winkel = Taktanteil, Zeit exakt, Drehtempo gesetzt.
func _on_grid(ns: Array, t0: float, bm: float) -> bool:
	for n in ns:
		var b: float = (n.time_ms - t0) / bm
		if absf(b * 2.0 - roundf(b * 2.0)) > 0.001:
			return false
		if OrbitNote.dist_deg(n.angle_deg, fposmod(b * 90.0, 360.0)) > 0.01:
			return false
		if absf(n.speed - 90.0 / bm) > 0.0001:
			return false
	return true


func _test_patterns(S: GDScript) -> void:
	for s in range(2, 7):
		for rnd in 2:
			var ns: Array = S.pattern(s, 500.0, 1000.0, 8, rnd)
			_check(ns.size() >= 3, "Schritt %d: Muster mit genug Zielen" % (s + 1))
			_check(_on_grid(ns, 500.0, 1000.0), "Schritt %d: Ziele auf dem Taktraster (Runde %d)" % [s + 1, rnd])
			var sorted := true
			for i in range(1, ns.size()):
				sorted = sorted and ns[i].time_ms >= ns[i - 1].time_ms
			_check(sorted, "Schritt %d: nach Zeit sortiert" % (s + 1))
	var keys: Array = S.pattern(2, 0.0, 1000.0, 0, 0)
	_check(keys.any(func(n): return n.ring == 0) and keys.any(func(n): return n.ring == 1),
			"Ringe: innen und aussen")
	_check(keys.all(func(n): return not n.is_arc), "Ringe: nur Taps")
	var acc: Array = S.pattern(3, 0.0, 1000.0, 0, 0)
	var pairs := true
	for i in range(0, acc.size(), 2):
		pairs = pairs and acc[i].ring == 0 and acc[i + 1].ring == 1 \
				and acc[i].time_ms == acc[i + 1].time_ms and acc[i].angle_deg == acc[i + 1].angle_deg
	_check(acc.size() % 2 == 0 and pairs, "Akzent: Paare innen+aussen, gleiche Zeit und Stelle")
	var holds: Array = S.pattern(4, 0.0, 1000.0, 0, 0)
	_check(holds.all(func(n): return n.is_arc and n.duration_ms() > 0.0), "Halte: nur Boegen")
	_check(holds.all(func(n): return absf(n.span_deg() - n.speed * n.duration_ms()) < 0.01),
			"Halte: Bogen folgt dem Zeiger")
	var pv: Array = S.pattern(5, 0.0, 1000.0, 0, 0)
	_check(pv.any(func(n): return n.time_ms < 4000.0) and pv.any(func(n): return n.time_ms >= 4000.0),
			"Vorschau: Noten in zwei Takten")
	var trial: Array = S.pattern(6, 0.0, 1000.0, 0, 0)
	var kinds := {"inner": false, "outer": false, "arc": false, "acc": false}
	for i in trial.size():
		var n: OrbitNote = trial[i]
		kinds["arc"] = kinds["arc"] or n.is_arc
		kinds["inner"] = kinds["inner"] or (n.ring == 0 and not n.is_arc)
		kinds["outer"] = kinds["outer"] or n.ring == 1
		if i + 1 < trial.size() and trial[i + 1].time_ms == n.time_ms and trial[i + 1].ring != n.ring:
			kinds["acc"] = true
	_check(kinds.values().all(func(v): return v), "Probe-Runde mischt innen, aussen, Akzent, Halte")


func _test_tempo_rises(S: GDScript) -> void:
	var b: Array = S.BPMS
	var up := true
	for i in range(1, b.size()):
		up = up and b[i] >= b[i - 1]
	_check(up and b[b.size() - 1] > b[0], "Tempo steigt von Schritt zu Schritt")
	_check(float(b[0]) <= 70.0, "Start langsam (%.0f BPM)" % float(b[0]))
	for bpm in b:
		_check(60000.0 / float(bpm) * 4.0 >= OrbitClock.MIN_BAR_MS, "BPM %.0f: Hand nicht zu schnell" % float(bpm))


func _key(tut: Control, code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = down
	tut.handle_input(ev)


## Cursor auf Winkel deg im Abstand rho (Bildhoehen).
func _aim_rho(tut: Control, deg: float, rho: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = OrbitView.polar(tut.view_center_global(), deg, tut._view.unit() * rho)
	tut.handle_input(ev)


## Cursor auf den Zeiger legen (plus Versatz in Grad).
func _on_hand(tut: Control, off: float = 0.0) -> void:
	_aim_rho(tut, tut.hand_deg() + off, 0.28)


## Bis cond wahr ist simulieren, der Cursor folgt dem Zeiger (plus Versatz).
func _follow_until(tut: Control, cond: Callable, off: float = 0.0, limit: int = 4000) -> bool:
	for i in limit:
		if cond.call():
			return true
		_on_hand(tut, off)
		tut.advance(FRAME)
	return cond.call()


## Bis auf ein halbes Bild vor Zeit t, der Cursor folgt dem Zeiger.
func _follow_to(tut: Control, t: float, off: float = 0.0) -> void:
	_follow_until(tut, func(): return tut.t_ms >= t - FRAME * 0.5, off)
	_on_hand(tut, off)


func _test_bar_step(tut: Control) -> void:
	tut.bot = false
	tut.enter_step(0)
	var k: int = root.get_node("/root/Settings").orbit_key_inner
	var bar: float = tut._bar_ms
	var first: float = tut._t0 + ceilf((tut.t_ms - tut._t0) / bar) * bar
	_follow_to(tut, first - bar * 0.5)
	_key(tut, k, true)
	_key(tut, k, false)
	_check(int(tut.success) == 0, "Takt: Druck mitten im Takt zaehlt nicht")
	_check(str(tut._feedback.text) != "", "Takt: Hinweis mit Grund")
	_follow_to(tut, first + 20.0)
	_key(tut, k, true)
	_key(tut, k, false)
	_check(int(tut.success) == 1, "Takt: Druck bei Takt-Eins zaehlt")
	_follow_to(tut, first + bar * 1.5)
	_key(tut, k, true)
	_key(tut, k, false)
	_check(int(tut.success) == 1, "Takt: Druck mitten im Takt zaehlt wieder nicht")


func _test_aim_step(tut: Control) -> void:
	tut.enter_step(1)
	# Cursor bleibt stehen, der Zeiger laeuft weg: nie lange genug auf dem Zeiger.
	_aim_rho(tut, 180.0, 0.28)
	_run_until(tut, func(): return tut.t_ms >= tut._t0 + tut._bar_ms * 2.0)
	_check(int(tut.success) == 0, "Zielen: stehender Cursor zaehlt nicht")
	# Neben dem Zeiger mitgefuehrt (60 Grad Versatz) zaehlt auch nicht.
	var until: float = tut.t_ms + 5000.0
	_follow_until(tut, func(): return tut.t_ms >= until, 60.0)
	_check(int(tut.success) == 0, "Zielen: Versatz von 60 Grad zaehlt nicht")
	# Auf dem Zeiger mitgefuehrt: Erfolg.
	_follow_until(tut, func(): return int(tut.success) >= 1)
	_check(int(tut.success) == 1, "Zielen: Cursor auf dem Zeiger zaehlt")
	# Abbruch nach dem Mitfuehren nennt den Grund.
	tut.enter_step(1)
	_follow_until(tut, func(): return tut.aim_progress() > 0.3)
	_aim_rho(tut, tut.hand_deg() + 120.0, 0.28)
	tut.advance(FRAME)
	_check(str(tut._feedback.text) != "", "Zielen: Hinweis nach Abbruch")


func _test_keys_from_settings(tut: Control) -> void:
	var st: Node = root.get_node("/root/Settings")
	var old_in: int = st.orbit_key_inner
	st.orbit_key_inner = KEY_Q
	tut.bot = false
	tut.enter_step(2)
	_check(str(tut._body_lbl.text).contains("Q"), "Text nennt die Taste aus den Settings")
	_check(str(tut.ring_tag(0)).contains("Q"), "Ringmarke zeigt die Belegung")
	var n: OrbitNote = tut.notes[0]
	_check(n.ring == 0, "erste Note innen")
	_follow_to(tut, n.time_ms)
	_key(tut, KEY_Z, true)
	_key(tut, KEY_Z, false)
	_check(int(tut.success) == 0, "alte Taste Z zaehlt nicht mehr")
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "Taste Q aus den Settings trifft")
	# Daneben gezielt: Cursor 90 Grad vom Zeiger weg.
	var n2: OrbitNote = tut.notes[1]
	_follow_to(tut, n2.time_ms)
	_on_hand(tut, 90.0)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "neben dem Zeiger zaehlt nicht")
	_check(str(tut._feedback.text) == tut.tr("Neben dem Zeiger: leg den Cursor auf den Zeiger."), "Grund: neben dem Zeiger")
	# Falsche Taste (aussen, Note innen) zaehlt nicht, Grund: anderer Ring.
	_on_hand(tut)
	_key(tut, st.orbit_key_outer, true)
	_key(tut, st.orbit_key_outer, false)
	_check(int(tut.success) == 1, "falscher Ring zaehlt nicht")
	_check(str(tut._feedback.text) == tut.tr("Anderer Ring: die Note liegt auf der anderen Taste."), "Grund: anderer Ring")
	# Der Cursor-Abstand entscheidet nicht: weit draussen gezeigt, Taste A trifft innen.
	_aim_rho(tut, tut.hand_deg(), 0.4)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 2, "Taste entscheidet den Ring, nicht der Abstand")
	# Zu frueh: lange vor der Note gedrueckt.
	tut.enter_step(2)
	_on_hand(tut)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 0, "zu frueh zaehlt nicht")
	# Maus rechts = Taste B trifft die Note auf dem aeusseren Ring.
	var n3: OrbitNote = tut.notes[2]
	_check(n3.ring == 1, "dritte Note aussen")
	_follow_to(tut, n3.time_ms)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.position = OrbitView.polar(tut.view_center_global(), tut.hand_deg(), tut._view.unit() * 0.28)
	mb.pressed = true
	tut.handle_input(mb)
	var mb_up: InputEventMouseButton = mb.duplicate()
	mb_up.pressed = false
	tut.handle_input(mb_up)
	_check(int(tut.success) == 1, "Maus rechts trifft den aeusseren Ring")
	st.orbit_key_inner = old_in


func _test_accent_needs_both(tut: Control) -> void:
	var st: Node = root.get_node("/root/Settings")
	tut.enter_step(3)
	var a: OrbitNote = tut.notes[0]
	_check(tut.notes[1].time_ms == a.time_ms and tut.notes[1].ring != a.ring, "Akzent: zwei Noten gleichzeitig")
	_follow_to(tut, a.time_ms)
	_key(tut, st.orbit_key_inner, true)
	_key(tut, st.orbit_key_inner, false)
	_follow_until(tut, func(): return tut.t_ms > a.time_ms + 400.0)
	_check(int(tut.success) == 0, "Akzent: eine Taste allein zaehlt nicht")
	_check(str(tut._feedback.text) == tut.tr("Akzent: beide Tasten zugleich."), "Akzent: Hinweis nennt beide Tasten")
	var b: OrbitNote = tut.notes[2]
	_follow_to(tut, b.time_ms)
	_key(tut, st.orbit_key_inner, true)
	_key(tut, st.orbit_key_outer, true)
	_key(tut, st.orbit_key_inner, false)
	_key(tut, st.orbit_key_outer, false)
	_check(int(tut.success) == 1, "Akzent: beide Tasten zaehlen einmal")


func _test_hold_needs_hold(tut: Control) -> void:
	var k: int = root.get_node("/root/Settings").orbit_key_inner
	tut.enter_step(4)
	var n: OrbitNote = tut.notes[0]
	_follow_to(tut, n.time_ms)
	_key(tut, k, true)
	tut.advance(FRAME * 3.0)
	_key(tut, k, false)
	_follow_until(tut, func(): return tut.t_ms > n.end_ms + 400.0)
	_check(int(tut.success) == 0, "Halte kurz antippen zaehlt nicht")
	_check(str(tut._feedback.text) != "", "Hinweis nach verlorener Halte")
	# Gehalten und dem Zeiger gefolgt: zaehlt.
	tut.enter_step(4)
	var m: OrbitNote = tut.notes[0]
	_follow_to(tut, m.time_ms)
	_key(tut, k, true)
	_follow_until(tut, func(): return tut.t_ms >= m.end_ms + 5.0)
	_key(tut, k, false)
	_check(int(tut.success) == 1, "Halte gehalten und gefolgt zaehlt")
	# Neben dem Zeiger gehalten: faellt.
	tut.enter_step(4)
	var d: OrbitNote = tut.notes[0]
	_follow_to(tut, d.time_ms)
	_key(tut, k, true)
	_follow_until(tut, func(): return tut.t_ms >= d.end_ms + 5.0, 90.0)
	_key(tut, k, false)
	_check(int(tut.success) == 0, "Halte neben dem Zeiger faellt")


func _test_preview(tut: Control) -> void:
	var st: Node = root.get_node("/root/Settings")
	tut.enter_step(5)
	var first: OrbitNote = tut.notes[0]
	_check(tut.clock.bar_at(tut.notes[2].time_ms) != tut.clock.bar_at(first.time_ms), "Vorschau: Note 3 im naechsten Takt")
	_follow_to(tut, first.time_ms)
	var k: int = st.orbit_key_inner if first.ring == 0 else st.orbit_key_outer
	_key(tut, k, true)
	_key(tut, k, false)
	_check(int(tut.success) == 0, "Vorschau: Treffer im ersten Takt zaehlt noch nicht")
	_check(tut.first_preview() != null, "Vorschau: blasse Note des naechsten Takts vorhanden")


func _test_skip(tut: Control) -> void:
	tut.enter_step(2)
	_key(tut, KEY_TAB, true)
	_check(int(tut.step) == 3, "Tab ueberspringt den Schritt")
	tut.skip_step()
	tut.skip_step()
	tut.skip_step()
	_check(int(tut.step) == 6, "Ueberspringen bis zur Probe-Runde")
	tut.skip_step()
	_check(bool(tut.finished), "Probe-Runde ueberspringen zeigt die Wertung")
