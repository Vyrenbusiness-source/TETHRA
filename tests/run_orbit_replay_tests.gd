extends SceneTree

## Headless-Tests fuer Orbit-Replays "Satelliten" (Task orbit-sat-game):
## Aufnahme im deterministischen OrbitCore (Feld-Cursor, Tasten A/B), Wiedergabe
## mit anderer Bildrate (und nach JSON-Rundreise) = exakt dieselbe Wertung;
## Wiedergabe ueber OrbitGame._feed_replay; Kompaktheit der Cursor-Spur;
## ReplayStore haelt Orbit und Mania getrennt; Regel-Marke 3, aeltere = alt.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_replay_tests.gd

var _passed := 0
var _failed := 0
var _done := false
const RADIUS := 0.05


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
	print("=== TETHRA Orbit-Replay-Tests (Satelliten) ===")
	_test_determinism()
	_test_fail_freeze()
	_test_compact()
	_test_store()
	_test_orbit_mods()
	_test_rules_marker()
	_test_game_replay()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Testkarte und simulierter Spieler ---

## Taps A/B, Akzente, dichte Stellen, Halten mit gebogenen Pfaden (Feld).
func _chart() -> Array[OrbitNote]:
	var ns: Array[OrbitNote] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var t := 1500.0
	var p := Vector2(0.5, 0.5)
	for i in 90:
		var key := rng.randi_range(0, 1)
		if i % 11 == 6:
			key = OrbitNote.KEY_ACCENT
		p = (p + Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))).clamp(
				Vector2(0.08, 0.08), Vector2(0.92, 0.92))
		var n: OrbitNote
		if i % 9 == 4:
			var dur := rng.randf_range(300.0, 900.0)
			var path := PackedVector2Array()
			var d := Vector2.from_angle(rng.randf() * TAU) * 0.2
			for k in 8:
				var u := float(k) / 7.0
				path.append((p + d * u + d.orthogonal() * sin(u * PI) * 0.3).clamp(Vector2.ZERO, Vector2.ONE))
			n = OrbitNote.make_hold(t, t + dur, path, key)
			p = path[path.size() - 1]
			t += dur + rng.randf_range(120.0, 300.0)
		else:
			n = OrbitNote.make_target(t, p, key)
			t += rng.randf_range(90.0, 380.0)
		n.lap_ms = 500.0
		n.laps = 2
		n.spawn_ms = n.time_ms - 1000.0
		ns.append(n)
	ns.sort_custom(func(a, b): return a.time_ms < b.time_ms)
	return ns


func _core(ns: Array[OrbitNote], mods: Dictionary = {}) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, 8.0, mods, RADIUS, 5.0)
	return c


## Rohe Eingabe eines "Menschen": Mausbewegung ~1 kHz mit Zittern, Tasten mit
## Zeitstreuung, ausgelassene Ziele, zu frueh losgelassene Halten.
## Event: [t (float ms), "m"|"d"|"u", Taste, Ort (Feld)].
func _human(ns: Array[OrbitNote], seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keys: Array = []
	var aims: Array = []   # [t, Ort] Stuetzpunkte der Cursor-Bahn
	aims.append([0.0, Vector2(0.5, 0.5)])
	for i in ns.size():
		var n := ns[i]
		if i % 13 == 7:
			continue   # Ziel auslassen
		var dt := rng.randfn(0.0, 22.0)
		var aim := n.pos + _noise(rng, 0.035)
		var td := n.time_ms + dt
		aims.append([td - 25.0, aim])
		aims.append([td, aim])
		var ks := [0, 1] if n.key == OrbitNote.KEY_ACCENT else [n.key]
		for k in ks:
			keys.append([td + (8.0 if k == 1 and ks.size() == 2 else 0.0), "d", k, aim])
		var stop := td + rng.randf_range(25.0, 70.0)
		if n.is_hold:
			stop = n.end_ms
			if i % 4 == 0:
				stop = lerpf(n.time_ms, n.end_ms, 0.5)   # zu frueh los
			var steps := int((stop - td) / 30.0)
			for k in steps:
				var tk := td + 30.0 * (k + 1)
				aims.append([tk, n.pos_at(tk) + _noise(rng, 0.02)])
			stop += rng.randf_range(0.0, 30.0)
		for k in ks:
			keys.append([stop, "u", k, Vector2.ZERO])
	aims.sort_custom(func(a, b): return a[0] < b[0])
	var evs: Array = []
	var t := 0.0
	var end_t: float = aims.back()[0] + 400.0
	var j := 0
	while t < end_t:
		while j + 1 < aims.size() and aims[j + 1][0] <= t:
			j += 1
		var a0: Array = aims[j]
		var a1: Array = aims[mini(j + 1, aims.size() - 1)]
		var span := maxf(float(a1[0]) - float(a0[0]), 1.0)
		var f := clampf((t - float(a0[0])) / span, 0.0, 1.0)
		var pos: Vector2 = (a0[1] as Vector2).lerp(a1[1], f) + _noise(rng, 0.0015)
		evs.append([t, "m", -1, pos])
		t += rng.randf_range(0.6, 1.4)
	evs.append_array(keys)
	evs.sort_custom(func(a, b): return a[0] < b[0])
	return evs


func _noise(rng: RandomNumberGenerator, sigma: float) -> Vector2:
	return Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))


## Live-Lauf: Bilder mit schwankender Laenge, Eingaben kommen gesammelt im
## Bild an (Zeitstempel teils vor dem letzten Bild). Gibt [Core, Urteile].
func _live(ns: Array[OrbitNote], evs: Array, seed: int, mods: Dictionary = {}) -> Array:
	var c := _core(ns, mods)
	c.set_replay_mode(true)
	var got := {}
	c.note_judged.connect(func(i: int, r: Dictionary) -> void: got[i] = r)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var frame_t := -500.0
	var k := 0
	var end_t: float = ns.back().end_ms + 1500.0
	while frame_t < end_t and not c.failed:
		frame_t += rng.randf_range(3.0, 21.0)
		while k < evs.size() and float(evs[k][0]) <= frame_t:
			var e: Array = evs[k]
			k += 1
			match str(e[1]):
				"m":
					c.cursor_moved(e[3], float(e[0]))
				"d":
					c.key_down(int(e[2]), float(e[0]))
				"u":
					c.key_up(int(e[2]), float(e[0]))
		c.update(frame_t)
	return [c, got]


## Wiedergabe: feste Bildlaenge frame_ms, Events wie in OrbitGame._process.
func _replay(ns: Array[OrbitNote], log: Array, frame_ms: float, mods: Dictionary = {}) -> Array:
	var c := _core(ns, mods)
	c.set_replay_mode(false)
	var got := {}
	c.note_judged.connect(func(i: int, r: Dictionary) -> void: got[i] = r)
	var frame_t := -500.0
	var k := 0
	var end_t: float = ns.back().end_ms + 1500.0
	while frame_t < end_t and not c.failed:
		frame_t += frame_ms
		while k < log.size() and float(log[k][0]) <= frame_t:
			c.apply_event(log[k])
			k += 1
		c.update(frame_t)
	return [c, got]


func _same_judgements(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for i in a:
		if not b.has(i):
			return false
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		for key in ["quality", "dt", "aim_err", "miss_kind", "held", "drop_reason"]:
			if x.get(key) != y.get(key):
				print("    Ziel %d %s: %s != %s" % [i, key, x.get(key), y.get(key)])
				return false
	return true


func _same_stats(a: Dictionary, b: Dictionary) -> bool:
	for key in ["score", "accuracy", "max_combo", "n_max", "n300", "n200", "n100",
			"n50", "n_miss", "aim_err", "grade"]:
		if a.get(key) != b.get(key):
			print("    %s: %s != %s" % [key, a.get(key), b.get(key)])
			return false
	return true


# --- Tests ---

func _test_determinism() -> void:
	print("- Aufnahme -> Wiedergabe = gleiche Wertung")
	var ns := _chart()
	var evs := _human(ns, 5)
	var live := _live(ns, evs, 11)
	var lc: OrbitCore = live[0]
	var s: Dictionary = lc.stats()
	_check(int(s.n_miss) > 0 and int(s.n_max) + int(s.n300) > 0, "Lauf hat Treffer und Misses")
	var drops := 0
	for i in live[1]:
		if str(live[1][i].get("miss_kind", "")) == "DROP":
			drops += 1
	_check(drops > 0, "Lauf hat abgebrochene Halten (DROP)")
	_check((live[1] as Dictionary).size() == ns.size(), "alle Ziele gewertet")
	# Wiedergabe mit 60, 144 und 30 FPS.
	for fm in [1000.0 / 60.0, 1000.0 / 144.0, 1000.0 / 30.0]:
		var rp := _replay(ns, lc.replay_log, fm)
		_check(_same_stats(s, (rp[0] as OrbitCore).stats()), "Stats gleich bei %.1f ms/Bild" % fm)
		_check(_same_judgements(live[1], rp[1]), "jedes Urteil gleich bei %.1f ms/Bild" % fm)
	# JSON-Rundreise (wie ReplayStore).
	var parsed = JSON.parse_string(JSON.stringify(lc.replay_log))
	_check(parsed is Array and (parsed as Array).size() == lc.replay_log.size(), "JSON-Rundreise")
	var rj := _replay(ns, parsed, 1000.0 / 60.0)
	_check(_same_stats(s, (rj[0] as OrbitCore).stats()), "Stats gleich nach JSON")
	_check(_same_judgements(live[1], rj[1]), "Urteile gleich nach JSON")
	# Zweiter Live-Lauf derselben Eingabe mit anderen Bildzeiten: gleiche Wertung
	# (die Wertung haengt nicht an der Bildrate).
	var live2 := _live(ns, evs, 99)
	_check(_same_stats(s, (live2[0] as OrbitCore).stats()), "Live-Wertung unabhaengig von der Bildrate")
	_check(_same_judgements(live[1], live2[1]), "Live-Urteile unabhaengig von der Bildrate")


func _test_fail_freeze() -> void:
	print("- Fail: Wiedergabe endet am selben Stand")
	var ns := _chart()
	var evs: Array = []
	for e in _human(ns, 8):
		# Nur Mausbewegung bis 9 s, danach keine Tasten mehr -> HP laeuft leer.
		if str(e[1]) == "m" or float(e[0]) < 9000.0:
			evs.append(e)
	var live := _live(ns, evs, 3)
	var lc: OrbitCore = live[0]
	_check(lc.failed, "Lauf scheitert")
	var rp := _replay(ns, lc.replay_log, 1000.0 / 60.0)
	var rc: OrbitCore = rp[0]
	_check(rc.failed, "Wiedergabe scheitert auch")
	_check(_same_stats(lc.stats(), rc.stats()), "Stats beim Fail gleich")
	_check(_same_judgements(live[1], rp[1]), "Urteile beim Fail gleich")
	# Mods kommen mit: NF verhindert den Fail in beiden Laeufen gleich.
	var live_nf := _live(ns, evs, 3, {"NF": true})
	var rp_nf := _replay(ns, (live_nf[0] as OrbitCore).replay_log, 1000.0 / 60.0, {"NF": true})
	_check(not (live_nf[0] as OrbitCore).failed and not (rp_nf[0] as OrbitCore).failed, "NF: kein Fail")
	_check(_same_stats((live_nf[0] as OrbitCore).stats(), (rp_nf[0] as OrbitCore).stats()), "NF: Stats gleich")


func _test_compact() -> void:
	print("- Kompaktheit")
	var ns := _chart()
	var evs := _human(ns, 5)
	var raw_moves := 0
	for e in evs:
		if str(e[1]) == "m":
			raw_moves += 1
	var lc: OrbitCore = _live(ns, evs, 11)[0]
	var cnt := OrbitCore.count_events(lc.replay_log)
	var len_s: float = (float(evs.back()[0]) + 500.0) / 1000.0
	print("    roh %d Bewegungen, aufgezeichnet %d Cursor + %d Tasten, %d Bytes, %.1f s" % [
		raw_moves, cnt.cursor, cnt.keys, JSON.stringify(lc.replay_log).length(), len_s])
	_check(cnt.cursor < raw_moves / 3, "Cursor-Spur mindestens 3x kleiner als roh")
	_check(float(cnt.cursor) / len_s <= 1000.0 / OrbitCore.REC_GAP_MS + 60.0, "Cursor hoechstens ~125/s (+ grosse Spruenge)")
	_check(cnt.keys > 0 and cnt.keys <= 2 * ns.size(), "Tasten-Events: je Ziel hoechstens Druck + Loslassen")
	# Kein Eintrag ohne Aenderung, Zeiten ganzzahlig und nie rueckwaerts.
	var ok := true
	var last_t := -INF
	for e in lc.replay_log:
		var t := float(e[0])
		if t < last_t or t != floorf(t):
			ok = false
		last_t = t
	_check(ok, "Zeiten ganze ms, monoton")
	var bytes_per_s := float(JSON.stringify(lc.replay_log).length()) / len_s
	_check(bytes_per_s < 3000.0, "unter 3 KB je Sekunde (%.0f B/s)" % bytes_per_s)


func _test_store() -> void:
	print("- ReplayStore: Orbit getrennt von Mania")
	var osz := "__orbit_replay_test_%d__.osz" % OS.get_process_id()
	var ver := "Test"
	var mania_ev := [{"t": 100.0, "lane": 0, "down": true}, {"t": 180.0, "lane": 0, "down": false}]
	var orbit_ev := [[100, OrbitCore.EV_CURSOR, 450, 300], [120, OrbitCore.EV_DOWN], [160, OrbitCore.EV_UP]]
	ReplayStore.save(osz, ver, mania_ev, {"score": 1, "mods": {}})
	ReplayStore.save(osz, ver, orbit_ev, {"score": 2, "mods": {"NF": true}}, "orbit")
	_check(ReplayStore.dir_for("orbit_last") != ReplayStore.dir_for("orbit") and ReplayStore.dir_for("orbit") != ReplayStore.DIR, "eigene Ordner je Modus")
	_check(ReplayStore.exists(osz, ver) and ReplayStore.exists(osz, ver, "orbit"), "beide gespeichert")
	var m := ReplayStore.load_replay(osz, ver)
	var o := ReplayStore.load_replay(osz, ver, "orbit")
	_check(int(m.meta.score) == 1 and m.events.size() == 2 and m.events[0] is Dictionary, "Mania-Replay unveraendert")
	_check(not m.meta.has("mode"), "Mania-Meta ohne Modus (altes Format)")
	_check(int(o.meta.score) == 2 and str(o.meta.mode) == "orbit" and o.events.size() == 3, "Orbit-Replay mit meta.mode")
	_check(ReplayStore.path_for_key(ReplayStore.key(osz, ver)) == "%s/%s.json" % [ReplayStore.DIR, ReplayStore.key(osz, ver)],
		"Mania-Pfad wie bisher")
	_check(ReplayStore.load_key(ReplayStore.key(osz, ver), "orbit").events.size() == 3, "load_key Orbit")
	_check(ClipExporter.replay_length_s(ReplayStore.key(osz, ver), "orbit") == 0.16, "Clip-Laenge aus Orbit-Events")
	_check(ClipExporter.replay_length_s(ReplayStore.key(osz, ver)) == 0.18, "Clip-Laenge aus Mania-Events")
	_check(bool(o.meta.mods.get("NF", false)), "Mods in Orbit-Meta")
	for mode in ["mania", "orbit"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ReplayStore.path_for_key(ReplayStore.key(osz, ver), mode)))
	_check(not ReplayStore.exists(osz, ver) and not ReplayStore.exists(osz, ver, "orbit"), "aufgeraeumt")


func _test_orbit_mods() -> void:
	print("- Orbit-Mods: Replay identisch, Mods aus der Meta")
	var ns := _chart()
	var evs := _human(ns, 5)
	var plain: OrbitCore = _live(ns, evs, 11)[0]
	for mods in [{"PR": true}, {"HD": true, "PR": true}, {"FI": true, "NF": true}]:
		var tag := OrbitCore.mods_text(mods)
		var live := _live(ns, evs, 11, mods)
		var lc: OrbitCore = live[0]
		# Ueber die Meta (JSON) wie ReplayStore + Song-Browser: Mods kommen mit.
		var meta = JSON.parse_string(JSON.stringify({"meta": {"mods": mods}}))
		var back := OrbitCore.replay_mods(meta)
		var log = JSON.parse_string(JSON.stringify(lc.replay_log))
		var rp := _replay(ns, log, 1000.0 / 60.0, back)
		_check(_same_stats(lc.stats(), (rp[0] as OrbitCore).stats()), "%s: Stats gleich" % tag)
		_check(_same_judgements(live[1], rp[1]), "%s: Urteile gleich" % tag)
		_check((rp[0] as OrbitCore).stats().mods == lc.stats().mods, "%s: Mods im Ergebnis" % tag)
	# PR wertet strenger: gleiche Eingaben, weniger Bestnoten.
	var pr: OrbitCore = _live(ns, evs, 11, {"PR": true})[0]
	_check(pr.n_max + pr.n300 < plain.n_max + plain.n300 or pr.n_miss > plain.n_miss,
		"PR: gleiche Eingaben werten strenger")
	# Ohne Mods abgespielt weicht ein PR-Lauf ab (Mods sind noetig).
	var wrong := _replay(ns, pr.replay_log, 1000.0 / 60.0, {})
	_check(not _same_stats(pr.stats(), (wrong[0] as OrbitCore).stats()) or pr.n_miss == plain.n_miss,
		"PR-Lauf ohne PR abgespielt ist anders")


func _test_rules_marker() -> void:
	print("- Regel-Marke: aeltere Replays erkennen")
	var ns := _chart()
	var lc: OrbitCore = _live(ns, _human(ns, 5), 11)[0]
	_check(int(lc.replay_log[0][1]) == OrbitCore.EV_RULES and int(lc.replay_log[0][2]) == OrbitCore.REPLAY_RULES,
		"Replay beginnt mit der Regel-Marke")
	_check(OrbitCore.count_events(lc.replay_log).keys <= 2 * ns.size(), "Marke zaehlt nicht als Taste")
	var game: GDScript = load("res://scripts/orbit/orbit_game.gd")
	_check(not game.is_old_replay(lc.replay_log), "neues Replay ist nicht alt")
	_check(game.is_old_replay([[100, OrbitCore.EV_CURSOR, 450, 300], [120, OrbitCore.EV_DOWN]]),
		"ohne Marke = aeltere Version")
	_check(game.is_old_replay([[0, OrbitCore.EV_RULES, 2]]), "Marke 2 (Bahnen) = aeltere Version")
	_check(not game.is_old_replay([[0, OrbitCore.EV_RULES, 3]]), "Marke 3 (Satelliten) = aktuell")


## Wiedergabe ueber das Spiel (OrbitGame._feed_replay): gleiche Wertung, Cursor
## und Tasten wie aufgenommen.
func _test_game_replay() -> void:
	print("- Spiel-Wiedergabe (_feed_replay) = Aufnahme")
	var ns := _chart()
	var live := _live(ns, _human(ns, 5), 11)
	var lc: OrbitCore = live[0]
	var game_script: GDScript = load("res://scripts/orbit/orbit_game.gd")
	var g: Control = game_script.new()
	g.notes = ns
	g.core = _core(ns)
	g.core.set_replay_mode(false)
	g._view = OrbitView.new()
	g._view.setup(ns)
	g._replay = true
	g._replay_events = JSON.parse_string(JSON.stringify(lc.replay_log))
	var max_down := 0
	var t := -500.0
	var end_t: float = ns.back().end_ms + 1500.0
	while t < end_t:
		t += 1000.0 / 60.0
		g._feed_replay(t)
		g.core.update(t)
		max_down = maxi(max_down, int(g._view.held[0]) + int(g._view.held[1]))
	_check(_same_stats(lc.stats(), g.core.stats()), "Stats gleich")
	_check(max_down == 2, "Akzent: beide Tasten sichtbar gedrueckt")
	var last := Vector2.ZERO
	for e in lc.replay_log:
		if int(e[1]) == OrbitCore.EV_CURSOR:
			last = Vector2(float(e[2]), float(e[3])) / 1000.0
	_check((g._view.cursor as Vector2).is_equal_approx(last), "Cursor wie aufgenommen")
	g._view.free()
	g.free()
