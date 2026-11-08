extends SceneTree

## Orbit-QA: Messungen statt Bauchgefuehl (Bericht: docs/modes/orbit_qa.md).
##  1. Takt: Zielzeit = Originalzeit, Anflug frame-genau am Ring (240 FPS),
##     Bogen-Spitze = Wertungs-Spitze, Bogen-Ende exakt.
##  2. Menschlicher Bot (Zeitstreuung, Zielstreuung, begrenztes Zeigertempo)
##     auf allen Testmaps, schlechteste Stellen mit Ursache.
##  3. Lesbarkeit: dichteste 5 s je Map, Ueberdeckung der Zielkreise.
##  4. Sterne gegen Bot-Erfolg (Rangkorrelation).
## Testmaps: user://orbit_sources/*.osz (osu!standard) + 4K-Maps aus maps/
## (SOURCES_MANIA). Ohne Testmaps laeuft nur der synthetische Teil.
## Headless:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_qa_tests.gd
## Rohdaten: user://orbit_qa/qa.json. Shots (Fenster, selbst-beendend):
##   ... --position -1920,0 --audio-driver Dummy --path . --script res://tests/run_orbit_qa_tests.gd -- --shots

const SOURCES_DIR := "user://orbit_sources"
const OUT_DIR := "user://orbit_qa"
const SOURCES_MANIA := ["Zekk - Fluctuation", "goreshit - burn this moment", "Billain - Specialist"]
const FRAME_MS := 1000.0 / 240.0
## Menschlicher Bot: Zeitstreuung, Zielstreuung, Zeigertempo (Grad/ms).
const SIG_T := 25.0
const SIG_A := 6.0
const V_TABLET := 0.35
const V_MOUSE := 0.25
const SEEDS := [3, 17]
const DENSE_MS := 5000.0
## Kurven schneiden: Vorhalt Richtung Folgeziel (Grad), nur bei Abstand < LEAD_GAP_MS.
const LEAD_DEG := 8.0
const LEAD_GAP_MS := 250.0
## Ziele zaehlen fuer die Ueberdeckung erst ab dieser Einblend-Deckkraft.
const VISIBLE_ALPHA := 0.5

var _passed := 0
var _failed := 0
var _out := {}


func _initialize() -> void:
	var shots := OS.get_cmdline_user_args().has("--shots")
	print("=== TETHRA Orbit-QA%s ===" % (" (Shots)" if shots else ""))
	var maps := _load_maps()
	if shots:
		_shots(maps)
		return
	_test_view_synthetic()
	_test_timing(maps)
	_test_view_frames(maps)
	_test_bot(maps)
	_test_density(maps)
	_test_stars(maps)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var fa := FileAccess.open(OUT_DIR + "/qa.json", FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(_out, " "))
		fa.close()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


# ---------------------------------------------------------------------------
# Testmaps
# ---------------------------------------------------------------------------

## [{tag, label, bm, ns}] fuer alle osu!standard-Diffs aus SOURCES_DIR und die
## 4K-Diffs der SOURCES_MANIA-Sets.
func _load_maps() -> Array:
	var maps: Array = []
	var da := DirAccess.open(SOURCES_DIR)
	if da != null:
		var files := Array(da.get_files())
		files.sort()
		for f in files:
			if not str(f).to_lower().ends_with(".osz"):
				continue
			var imp := OszImporter.import(SOURCES_DIR.path_join(f))
			for d in imp.difficulties:
				var bm: Beatmap = d.beatmap
				if bm.mode() == 0 and not bm.hit_objects.is_empty():
					maps.append(_entry("std", str(f), bm))
	var mdir := MapLibrary.default_maps_dir()
	var mda := DirAccess.open(mdir)
	if mda != null:
		var files := Array(mda.get_files())
		files.sort()
		for f in files:
			var hit := false
			for want in SOURCES_MANIA:
				hit = hit or str(f).find(want) >= 0
			if not hit or not str(f).to_lower().ends_with(".osz"):
				continue
			var imp := OszImporter.import(mdir.path_join(f))
			for d in imp.difficulties:
				var bm: Beatmap = d.beatmap
				if bm.is_mania() and bm.column_count() == 4 and not bm.hit_objects.is_empty():
					maps.append(_entry("4k", str(f), bm))
	print("  %d Testmaps (%d osu!standard, %d 4K)" % [maps.size(),
		maps.filter(func(m): return m.tag == "std").size(),
		maps.filter(func(m): return m.tag == "4k").size()])
	return maps


func _entry(tag: String, file: String, bm: Beatmap) -> Dictionary:
	var name := file.get_basename()
	var sp := name.find(" ")
	if sp > 0 and name.left(sp).is_valid_int():
		name = name.substr(sp + 1)
	var ns := OrbitConverter.convert(bm)
	return {"tag": tag, "label": "%s %s [%s]" % [tag, name.left(22), bm.version_name()],
		"bm": bm, "ns": ns}


# ---------------------------------------------------------------------------
# 1. Takt
# ---------------------------------------------------------------------------

func _test_timing(maps: Array) -> void:
	print("- Takt: Zielzeit = Originalzeit")
	var rows: Array = []
	var worst := 0.0
	var worst_end := 0.0
	var n_all := 0
	var n_exact := 0
	for m in maps:
		var bm: Beatmap = m.bm
		var mx := 0.0
		var mx_end := 0.0
		var exact := 0
		for n in m.ns:
			var o: HitObject = bm.hit_objects[n.source_index]
			var d := absf(float(o.time) - n.time_ms)
			mx = maxf(mx, d)
			exact += 1 if d == 0.0 else 0
			if n.is_arc:
				mx_end = maxf(mx_end, absf(float(o.end_time()) - n.end_ms))
		n_all += m.ns.size()
		n_exact += exact
		worst = maxf(worst, mx)
		worst_end = maxf(worst_end, mx_end)
		rows.append({"map": m.label, "targets": m.ns.size(), "exact": exact, "max_ms": mx, "max_end_ms": mx_end})
	_out["timing"] = rows
	print("  %d Ziele, davon %d exakt (0 ms); max Abweichung Kopf %.3f ms, Ende %.3f ms" % [n_all, n_exact, worst, worst_end])
	_ok(n_all == 0 or n_exact == n_all, "jedes Ziel exakt auf Originalzeit (Kopf)")
	_ok(worst_end == 0.0, "jedes Bogen-Ende exakt auf Original-Ende")


## Prueft den Anflug ueber die Geometrie der View (dieselben Funktionen wie
## _draw): Zeitpunkt, an dem der gezeichnete Mittelpunkt den Ring erreicht,
## und Spitze eines Bogens gegen OrbitNote.angle_at (Wertung).
func _view_check(v: OrbitView, ns: Array) -> Dictionary:
	var res := {"cross_err_ms": 0.0, "first_frame_err_ms": 0.0, "angle_err_deg": 0.0,
		"tip_err_deg": 0.0, "end_err_deg": 0.0, "monotonic": true}
	var c := v.center()
	for i in ns.size():
		var n: OrbitNote = ns[i]
		var r1 := v.ring_radius(n.ring)
		var r0 := v.spawn_radius(n.ring)
		var speed := (r1 - r0) / v.preempt  # px/ms
		# Radius genau zur Trefferzeit -> Zeitfehler des Durchgangs.
		var e := absf(v.radius_at(n.ring, 0.0) - r1) / speed
		res.cross_err_ms = maxf(res.cross_err_ms, e)
		# 240-FPS-Frames mit wechselnder Phase: der erste Frame mit Radius
		# >= Ring liegt in [Treffer, Treffer + 1 Frame).
		var phase := fmod(float(i) * 1.618, 1.0) * FRAME_MS
		var prev := -INF
		var first := INF
		for k in range(-40, 3):
			var tf := n.time_ms + phase + float(k) * FRAME_MS
			var r := v.radius_at(n.ring, n.time_ms - tf)
			if r < prev:
				res.monotonic = false
			prev = r
			if r >= r1 - 1e-6 and first == INF:
				first = tf
		res.first_frame_err_ms = maxf(res.first_frame_err_ms, first - n.time_ms)
		# Gezeichneter Winkel am Ring = Zielwinkel der Wertung.
		var p := OrbitView.polar(c, n.angle_deg, r1)
		res.angle_err_deg = maxf(res.angle_err_deg, OrbitNote.dist_deg(OrbitView.angle_of(c, p), n.angle_deg))
		if n.is_arc:
			for k in 9:
				var t := lerpf(n.time_ms, n.end_ms, float(k) / 8.0)
				var tip := v.arc_tip_deg(n, t)
				res.tip_err_deg = maxf(res.tip_err_deg, OrbitNote.dist_deg(tip, n.angle_at(t)))
			res.end_err_deg = maxf(res.end_err_deg, absf(v.arc_tip_deg(n, n.end_ms, true) - n.end_angle_deg))
	return res


func _new_view(w: float, h: float, scroll: float) -> OrbitView:
	var v := OrbitView.new()
	v.size = Vector2(w, h)
	v.preempt = ManiaCore.preempt_for(scroll)
	return v


func _test_view_synthetic() -> void:
	print("- Anflug (synthetisch)")
	var ns: Array = []
	for i in 50:
		ns.append(OrbitNote.make(1000.0 + i * 137.3, float(i * 37 % 360), i % 2))
	ns.append(OrbitNote.make_arc(9000.0, 9600.0, 350.0, 72.0, 0))
	ns.append(OrbitNote.make_arc(9800.0, 10400.0, 10.0, -72.0, 1))
	var v := _new_view(1920, 1080, 1.0)
	var r := _view_check(v, ns)
	v.free()
	_ok(r.cross_err_ms < 0.001 and r.first_frame_err_ms < FRAME_MS and r.monotonic, "Anflug erreicht den Ring zur Trefferzeit (%s)" % str(r))
	_ok(r.tip_err_deg < 0.01 and r.end_err_deg < 0.001, "Bogen-Spitze = Wertungs-Spitze, Ende exakt")


func _test_view_frames(maps: Array) -> void:
	print("- Takt: Anflug frame-genau (240 FPS), Bogen-Spitze und -Ende")
	var agg := {"cross_err_ms": 0.0, "first_frame_err_ms": 0.0, "angle_err_deg": 0.0,
		"tip_err_deg": 0.0, "end_err_deg": 0.0, "monotonic": true}
	for cfg in [[1920.0, 1080.0, 1.0], [2560.0, 1440.0, 1.6], [1280.0, 720.0, 0.7]]:
		var v := _new_view(cfg[0], cfg[1], cfg[2])
		for m in maps:
			var r := _view_check(v, m.ns)
			for k in agg:
				if k == "monotonic":
					agg[k] = agg[k] and r[k]
				else:
					agg[k] = maxf(agg[k], r[k])
		v.free()
	_out["view_timing"] = agg
	print("  %s" % str(agg))
	_ok(agg.cross_err_ms < 0.01, "Ring-Durchgang = Trefferzeit (< 0,01 ms)")
	_ok(agg.first_frame_err_ms < FRAME_MS, "erster Frame am Ring < 1 Frame nach Treffer")
	_ok(agg.monotonic, "Anflug monoton (kein Ruckeln)")
	_ok(agg.angle_err_deg < 0.01, "gezeichneter Winkel = Zielwinkel")
	_ok(agg.tip_err_deg < 0.01, "Bogen-Spitze = Wertungs-Spitze")
	_ok(agg.end_err_deg < 0.001, "Bogen-Ende exakt")


# ---------------------------------------------------------------------------
# 2. Menschlicher Bot
# ---------------------------------------------------------------------------

## Spielt ns wie ein Mensch: Druck zur Zeit + N(0, sig_t), Zeiger faehrt mit
## hoechstens vmax Grad/ms zum naechsten Ziel (+ N(0, sig_a) Zielfehler),
## folgt gehaltenen Boegen, Taps 40 ms gehalten. 240 FPS.
## Rueckgabe: core + je Ziel [Druck-dt, Zeigerfehler beim Druck].
func _human(ns: Array[OrbitNote], bm: Beatmap, vmax: float, sig_t: float, sig_a: float, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var c := OrbitCore.new()
	c.setup(ns, bm.od(), 1.0, bm.hp(), {"NF": true})
	var n_ns := ns.size()
	var off_t := PackedFloat32Array()
	var off_a := PackedFloat32Array()
	off_t.resize(n_ns)
	off_a.resize(n_ns)
	var ev: Array = []
	for i in n_ns:
		off_t[i] = clampf(rng.randfn(0.0, sig_t), -3.0 * sig_t, 3.0 * sig_t) if sig_t > 0.0 else 0.0
		off_a[i] = clampf(rng.randfn(0.0, sig_a), -3.0 * sig_a, 3.0 * sig_a) if sig_a > 0.0 else 0.0
		var tp: float = ns[i].time_ms + off_t[i]
		ev.append([tp, 0, i])
		var tr: float = ns[i].end_ms + clampf(rng.randfn(0.0, sig_t * 0.5), -40.0, 40.0) if ns[i].is_arc else tp + 40.0
		ev.append([tr, 1, i])
	ev.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
	var press_err := PackedFloat32Array()
	press_err.resize(n_ns)
	var held: Array[int] = [-1, -1]
	var cur := ns[0].angle_deg if n_ns > 0 else 0.0
	var nxt := 0  # naechstes noch nicht gedruecktes Ziel
	var pressed := PackedByteArray()
	pressed.resize(n_ns)
	var t: float = ns[0].time_ms - 1000.0 if n_ns > 0 else 0.0
	var end_t: float = ns[-1].end_ms + 1000.0 if n_ns > 0 else 0.0
	var k := 0
	while t < end_t:
		# Ziel des Zeigers: gehaltener Bogen, sonst das naechste Ziel.
		var goal := INF
		for r in 2:
			if held[r] >= 0 and ns[held[r]].is_arc and c.active_arc(r) == held[r]:
				goal = ns[held[r]].angle_at(t + FRAME_MS) + off_a[held[r]]
		while nxt < n_ns and pressed[nxt] == 1:
			nxt += 1
		if goal == INF and nxt < n_ns:
			goal = ns[nxt].angle_at(ns[nxt].time_ms) + off_a[nxt]
			# Mensch schneidet Kurven: bei dichtem Folgeziel schon etwas
			# (hoechstens LEAD_DEG) Richtung uebernaechstes Ziel zielen.
			var j := nxt + 1
			while j < n_ns and ns[j].time_ms - ns[nxt].time_ms <= OrbitConverter.CHORD_EPS_MS:
				j += 1
			if j < n_ns and ns[j].time_ms - ns[nxt].time_ms < LEAD_GAP_MS and not ns[nxt].is_arc:
				goal += clampf(OrbitNote.delta_deg(ns[nxt].angle_deg, ns[j].angle_deg) * 0.5, -LEAD_DEG, LEAD_DEG)
		if goal != INF:
			var d := OrbitNote.delta_deg(cur, goal)
			var step := vmax * FRAME_MS
			cur = OrbitNote.wrap_deg(cur + clampf(d, -step, step))
		var t1 := t + FRAME_MS
		while k < ev.size() and float(ev[k][0]) <= t1:
			var e: Array = ev[k]
			k += 1
			var te: float = e[0]
			var i: int = e[2]
			var n: OrbitNote = ns[i]
			c.update(te)
			if e[1] == 0:
				if held[n.ring] >= 0:
					c.key_up(n.ring, te)
				held[n.ring] = i
				pressed[i] = 1
				press_err[i] = OrbitNote.dist_deg(cur, n.angle_at(te))
				c.key_down(n.ring, te, cur)
			elif held[n.ring] == i:
				c.key_up(n.ring, te)
				held[n.ring] = -1
		c.cursor_moved(cur, t1)
		c.update(t1)
		t = t1
	c.update(end_t + 5000.0)
	return {"core": c, "dt": off_t, "err": press_err}


## Vorheriger Cursor-Punkt je Ziel: [Zeit, Winkel, ist Bogen-Ende].
func _prev_points(ns: Array[OrbitNote]) -> Array:
	var pts := OrbitConverter.cursor_points(ns)
	var out: Array = []
	var j := 0
	for n in ns:
		while j + 1 < pts.size() and float(pts[j + 1][0]) < n.time_ms - OrbitConverter.CHORD_EPS_MS:
			j += 1
		if pts.is_empty() or float(pts[j][0]) >= n.time_ms - OrbitConverter.CHORD_EPS_MS:
			out.append([-INF, n.angle_deg, false])
		else:
			out.append(pts[j])
	return out


## Ursache eines Fehlers an Ziel i.
func _cause(ns: Array[OrbitNote], prev: Array, i: int, res: Dictionary, vmax: float) -> Dictionary:
	var n: OrbitNote = ns[i]
	var p: Array = prev[i]
	var gap := n.time_ms - float(p[0])
	var d := OrbitNote.dist_deg(float(p[1]), n.angle_deg)
	var need := maxf(0.0, d - OrbitCore.ANGLE_TOL_DEG + SIG_A) / maxf(gap, 1.0)
	var cause := "streuung"
	if str(res.get("miss_kind", "")) == "DROP":
		cause = "bogen_" + str(res.get("drop_reason", "")).to_lower()
	elif bool(p[2]) and gap < 400.0:
		cause = "bogen_ausstieg"
	elif need > vmax:
		cause = "sprung"
	elif n.is_arc:
		cause = "bogen_einstieg"
	elif gap < OrbitConverter.STREAM_GAP_MS:
		cause = "dichte"
	return {"cause": cause, "gap": gap, "deg": d, "need": need}


func _bot_eval(m: Dictionary, vmax: float) -> Dictionary:
	var ns: Array[OrbitNote] = m.ns
	var prev := _prev_points(ns)
	var miss := 0
	var acc := 0.0
	var causes := {}
	var spots := {}
	for s in SEEDS:
		var h := _human(ns, m.bm, vmax, SIG_T, SIG_A, s)
		var c: OrbitCore = h.core
		acc += c.accuracy()
		for i in ns.size():
			var res: Dictionary = c._judged.get(i, {})
			if int(res.get("quality", -1)) != OrbitCore.Quality.MISS:
				continue
			miss += 1
			var ca := _cause(ns, prev, i, res, vmax)
			causes[ca.cause] = int(causes.get(ca.cause, 0)) + 1
			var w := int(ns[i].time_ms / 2000.0)
			var sp: Dictionary = spots.get(w, {"t": ns[i].time_ms, "miss": 0, "causes": {}, "need": 0.0, "gap": INF, "deg": 0.0})
			sp.miss += 1
			sp.causes[ca.cause] = int(sp.causes.get(ca.cause, 0)) + 1
			sp.need = maxf(sp.need, ca.need)
			sp.gap = minf(sp.gap, ca.gap)
			sp.deg = maxf(sp.deg, ca.deg)
			spots[w] = sp
	var nseed := float(SEEDS.size())
	return {"acc": acc / nseed, "miss": float(miss) / nseed,
		"miss_rate": float(miss) / nseed / float(maxi(ns.size(), 1)), "causes": causes, "spots": spots}


func _test_bot(maps: Array) -> void:
	OrbitConverter.human_reach = false
	var old_maps: Array = []
	for m in maps:
		old_maps.append({"tag": m.tag, "label": m.label, "bm": m.bm, "ns": OrbitConverter.convert(m.bm)})
	OrbitConverter.human_reach = true
	print("  VORHER (ohne Erreichbarkeits-Regel):")
	var old := _bot_pass(old_maps)
	print("  NACHHER:")
	var now := _bot_pass(maps)
	_out["bot"] = {"before": old, "after": now}
	_ok(maps.is_empty() or now.total.tablet < 0.03, "Tablet-Bot verliert < 3 % der Ziele")
	_ok(maps.is_empty() or now.total.mouse < 0.06, "Maus-Bot verliert < 6 % der Ziele")
	_ok(maps.is_empty() or now.std_pos_med <= 20.0, "osu!standard-Lage bleibt erkennbar (Median <= 20 Grad)")


## Median-Abstand Zielwinkel <-> Richtung der osu-Position zur Mitte (nur std).
func _std_pos_err(m: Dictionary) -> PackedFloat32Array:
	var errs := PackedFloat32Array()
	if m.tag != "std":
		return errs
	for n in m.ns:
		var o: HitObject = m.bm.hit_objects[n.source_index]
		if o.kind != HitObject.Kind.SPINNER and o.position().distance_to(OrbitConverter.STD_CENTER) >= OrbitConverter.STD_DEAD_PX:
			errs.append(OrbitNote.dist_deg(n.angle_deg, OrbitConverter._polar_deg(o.position())))
	return errs


func _bot_pass(maps: Array) -> Dictionary:
	print("- Menschlicher Bot (Zeit %.0f ms, Ziel %.0f Grad; Tablet %.0f, Maus %.0f Grad/s)" % [SIG_T, SIG_A, V_TABLET * 1000.0, V_MOUSE * 1000.0])
	var rows: Array = []
	var all_spots: Array = []
	var tot := {"free": 0.0, "tablet": 0.0, "mouse": 0.0, "targets": 0}
	var causes := {}
	var pos_all := PackedFloat32Array()
	for m in maps:
		pos_all.append_array(_std_pos_err(m))
		var free := _bot_eval(m, 100.0)
		var tab := _bot_eval(m, V_TABLET)
		var mou := _bot_eval(m, V_MOUSE)
		m["bot"] = {"free": free.acc, "tablet": tab.acc, "mouse": mou.acc,
			"miss_free": free.miss_rate, "miss_tablet": tab.miss_rate, "miss_mouse": mou.miss_rate}
		tot.free += free.miss
		tot.tablet += tab.miss
		tot.mouse += mou.miss
		tot.targets += m.ns.size()
		for k in mou.causes:
			causes[k] = int(causes.get(k, 0)) + int(mou.causes[k])
		for w in mou.spots:
			var sp: Dictionary = mou.spots[w]
			var base := 0
			if free.spots.has(w):
				base = int(free.spots[w].miss)
			var dom := ""
			var best := -1
			for k in sp.causes:
				if int(sp.causes[k]) > best:
					best = int(sp.causes[k])
					dom = k
			all_spots.append({"map": m.label, "t": sp.t, "miss": float(sp.miss) / SEEDS.size(),
				"extra": float(int(sp.miss) - base) / SEEDS.size(), "cause": dom,
				"need": sp.need, "gap": sp.gap, "deg": sp.deg})
		rows.append({"map": m.label, "targets": m.ns.size(), "stars": OrbitConverter.stars(m.ns),
			"acc_free": free.acc, "acc_tablet": tab.acc, "acc_mouse": mou.acc,
			"miss_free": free.miss_rate, "miss_tablet": tab.miss_rate, "miss_mouse": mou.miss_rate,
			"causes_mouse": mou.causes})
		print("  %-46s %4d Ziele  Fehler frei %4.1f%%  Tablet %4.1f%%  Maus %4.1f%%  acc %.3f/%.3f/%.3f" % [
			m.label, m.ns.size(), free.miss_rate * 100.0, tab.miss_rate * 100.0, mou.miss_rate * 100.0,
			free.acc, tab.acc, mou.acc])
	all_spots.sort_custom(func(a, b): return a.extra > b.extra or (a.extra == b.extra and a.miss > b.miss))
	var top := all_spots.slice(0, 20)
	print("  Schlechteste 20 Stellen (Maus, Fehler je Lauf ueber dem Bot ohne Tempogrenze):")
	for sp in top:
		print("    %-46s %s  +%.1f (%.1f)  %-14s Weg %.0f Grad in %.0f ms, noetig %.2f Grad/ms" % [
			sp.map, _mmss(sp.t), sp.extra, sp.miss, sp.cause, sp.deg, sp.gap, sp.need])
	var n := float(maxi(int(tot.targets), 1))
	print("  Gesamt Fehlerquote: frei %.2f%%, Tablet %.2f%%, Maus %.2f%%; Ursachen (Maus) %s" % [
		tot.free / n * 100.0, tot.tablet / n * 100.0, tot.mouse / n * 100.0, str(causes)])
	pos_all.sort()
	var pos_med := pos_all[pos_all.size() / 2] if not pos_all.is_empty() else 0.0
	var pos_p90 := pos_all[int(pos_all.size() * 0.9)] if not pos_all.is_empty() else 0.0
	print("  osu!standard-Lage (Zielwinkel <-> osu-Position): Median %.1f Grad, p90 %.1f Grad" % [pos_med, pos_p90])
	return {"rows": rows, "top20": top, "total": {"free": tot.free / n, "tablet": tot.tablet / n,
		"mouse": tot.mouse / n}, "causes_mouse": causes, "std_pos_med": pos_med, "std_pos_p90": pos_p90}


func _mmss(t: float) -> String:
	var s := int(t / 1000.0)
	return "%d:%02d.%03d" % [s / 60, s % 60, int(t) % 1000]


# ---------------------------------------------------------------------------
# 3. Lesbarkeit bei hoher Dichte
# ---------------------------------------------------------------------------

## Beginn des dichtesten DENSE_MS-Fensters (meiste Ziele).
func _densest(ns: Array[OrbitNote]) -> float:
	var best := 0
	var t0 := ns[0].time_ms if not ns.is_empty() else 0.0
	var j := 0
	for i in ns.size():
		while ns[i].time_ms - ns[j].time_ms > DENSE_MS:
			j += 1
		if i - j + 1 > best:
			best = i - j + 1
			t0 = ns[j].time_ms
	return t0


## Ueberdeckung im Fenster [t0, t0 + DENSE_MS): je Frame (60 FPS) alle noch
## anfliegenden Ziele mit gezeichneter Groesse (OrbitView.draw_radius).
## any = Paare mit sich ueberschneidenden Kreisen, heavy = Mittelpunkt eines
## Ziels im Kreis des anderen; next_hidden = das jeweils uebernaechste Ziel
## eines Rings liegt zu mehr als der Haelfte unter dem naechsten.
func _overlap(v: OrbitView, ns: Array[OrbitNote], t0: float) -> Dictionary:
	v.setup(ns)
	var frames := 0
	var pair_any := 0
	var pair_heavy := 0
	var visible := 0
	var covered := {}
	var seen := {}
	var c := v.center()
	var t := t0
	var cross := 0
	while t < t0 + DENSE_MS:
		v.t_ms = t
		v.layout_frame()
		var idx: Array[int] = []
		for i in ns.size():
			var dt := ns[i].time_ms - t
			if dt > v.preempt:
				break
			if dt >= 0.0 and v.draw_alpha(i, t) >= VISIBLE_ALPHA:
				idx.append(i)
		var pos: Array[Vector2] = []
		var rad: Array[float] = []
		for i in idx:
			pos.append(v.draw_pos(c, i, t))
			rad.append(v.draw_radius(i, t))
			seen[i] = true
		visible += idx.size()
		for a in idx.size():
			for b in range(a + 1, idx.size()):
				var ia := idx[a]
				var ib := idx[b]
				if absf(ns[ia].time_ms - ns[ib].time_ms) <= OrbitConverter.CHORD_EPS_MS:
					continue
				var dist := pos[a].distance_to(pos[b])
				if dist < rad[a] + rad[b]:
					pair_any += 1
					cross += 1 if ns[ia].ring != ns[ib].ring else 0
					covered[ib] = true
					if dist < maxf(rad[a], rad[b]):
						pair_heavy += 1
		frames += 1
		t += 1000.0 / 60.0
	var n_seen := float(maxi(seen.size(), 1))
	return {"frames": frames, "visible": float(visible) / float(maxi(frames, 1)),
		"pairs_any": float(pair_any) / float(maxi(frames, 1)),
		"pairs_heavy": float(pair_heavy) / float(maxi(frames, 1)),
		"cross_share": float(cross) / float(maxi(pair_any, 1)),
		"covered_share": float(covered.size()) / n_seen}


func _test_density(maps: Array) -> void:
	var old := _density_pass(maps, false)
	var now := _density_pass(maps, true)
	_out["density"] = {"before": old, "after": now}
	_ok(maps.is_empty() or now.covered_mean < 0.15, "dichte Stellen: < 15 % der Ziele von anderen ueberdeckt")
	_ok(maps.is_empty() or now.heavy_mean < 0.1, "dichte Stellen: kaum starke Ueberdeckung (< 0,1 Paare/Frame)")


func _density_pass(maps: Array, fit: bool) -> Dictionary:
	print("- Lesbarkeit: dichteste 5 s je Map (1920x1080, Scroll 1,0), %s" % ("NACHHER (Groessen-Anpassung)" if fit else "VORHER"))
	var v := _new_view(1920, 1080, 1.0)
	v.fit_enabled = fit
	var rows: Array = []
	var sum_cov := 0.0
	var sum_heavy := 0.0
	for m in maps:
		var t0 := _densest(m.ns)
		var o := _overlap(v, m.ns, t0)
		var cnt := 0
		for n in m.ns:
			if n.time_ms >= t0 and n.time_ms < t0 + DENSE_MS:
				cnt += 1
		o["map"] = m.label
		o["t0"] = t0
		o["nps"] = float(cnt) / (DENSE_MS / 1000.0)
		rows.append(o)
		sum_cov += o.covered_share
		sum_heavy += o.pairs_heavy
		print("  %-46s %s %4.1f/s  sichtbar %4.1f  Ueberschneidungen/Frame %4.2f (stark %4.2f, Ring-uebergreifend %2.0f%%)  verdeckte Ziele %4.1f%%" % [
			m.label, _mmss(t0), o.nps, o.visible, o.pairs_any, o.pairs_heavy, o.cross_share * 100.0, o.covered_share * 100.0])
	v.free()
	var nm := float(maxi(maps.size(), 1))
	print("  Mittel: verdeckte Ziele %.1f%%, starke Ueberdeckung %.2f Paare/Frame" % [sum_cov / nm * 100.0, sum_heavy / nm])
	return {"rows": rows, "covered_mean": sum_cov / nm, "heavy_mean": sum_heavy / nm}


# ---------------------------------------------------------------------------
# 4. Sterne gegen Bot-Erfolg
# ---------------------------------------------------------------------------

static func _ranks(xs: Array) -> Array:
	var idx := range(xs.size())
	idx.sort_custom(func(a, b): return xs[a] < xs[b])
	var r := []
	r.resize(xs.size())
	for k in idx.size():
		r[idx[k]] = float(k)
	return r


static func _spearman(xs: Array, ys: Array) -> float:
	var n := xs.size()
	if n < 3:
		return 0.0
	var rx := _ranks(xs)
	var ry := _ranks(ys)
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += rx[i]
		my += ry[i]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		sxy += (rx[i] - mx) * (ry[i] - my)
		sxx += (rx[i] - mx) * (rx[i] - mx)
		syy += (ry[i] - my) * (ry[i] - my)
	return sxy / sqrt(maxf(sxx * syy, 1e-9))


func _test_stars(maps: Array) -> void:
	print("- Sterne gegen menschlichen Bot")
	var st: Array = []
	var mt: Array = []
	var mm: Array = []
	for m in maps:
		if not m.has("bot"):
			continue
		st.append(OrbitConverter.stars(m.ns))
		mt.append(m.bot.miss_tablet + (1.0 - m.bot.tablet))
		mm.append(m.bot.miss_mouse + (1.0 - m.bot.mouse))
	var rt := _spearman(st, mt)
	var rm := _spearman(st, mm)
	_out["stars"] = {"spearman_tablet": rt, "spearman_mouse": rm}
	print("  Rangkorrelation Sterne <-> Bot-Verlust: Tablet %.2f, Maus %.2f (%d Maps)" % [rt, rm, st.size()])
	_ok(st.size() < 3 or rm >= 0.7, "Sterne ordnen wie der Maus-Bot (Spearman >= 0,7)")


# ---------------------------------------------------------------------------
# Shots (Fenster)
# ---------------------------------------------------------------------------

func _shots(maps: Array) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "/shots")
	root.size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.04)
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var v := OrbitView.new()
	v.size = Vector2(1280, 720)
	v.preempt = ManiaCore.preempt_for(1.0)
	root.add_child(v)
	# Pro Quelle die dichtesten Diffs.
	var pick: Array = []
	var by := {}
	for m in maps:
		var t0 := _densest(m.ns)
		var cnt := 0
		for n in m.ns:
			if n.time_ms >= t0 and n.time_ms < t0 + DENSE_MS:
				cnt += 1
		m["t0"] = t0
		m["dense"] = cnt
		var key: String = m.label.left(m.label.find("["))
		if not by.has(key) or int(by[key].dense) < cnt:
			by[key] = m
	pick = by.values()
	var tag := OS.get_environment("ORBIT_QA_TAG")
	if tag == "":
		tag = "shot"
	for m in pick:
		v.setup(m.ns)
		var o := _overlap(v, m.ns, m.t0)
		# Frame mit der staerksten Ueberdeckung im Fenster.
		var best_t: float = m.t0
		var best := -1.0
		var t: float = m.t0
		while t < m.t0 + DENSE_MS:
			var r := _overlap_at(v, m.ns, t)
			if r > best:
				best = r
				best_t = t
			t += 50.0
		v.setup(m.ns)
		v.t_ms = best_t
		v.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var fn: String = "%s/shots/%s_%s.png" % [OUT_DIR, tag, m.label.validate_filename().replace(" ", "_").left(40)]
		img.save_png(fn)
		print("  %s  t=%s  verdeckt %.0f%%  -> %s" % [m.label, _mmss(best_t), o.covered_share * 100.0, ProjectSettings.globalize_path(fn)])
	quit(0)


func _overlap_at(v: OrbitView, ns: Array[OrbitNote], t: float) -> float:
	var c := v.center()
	v.t_ms = t
	v.layout_frame()
	var idx: Array[int] = []
	for i in ns.size():
		var dt := ns[i].time_ms - t
		if dt > v.preempt:
			break
		if dt >= 0.0 and v.draw_alpha(i, t) >= VISIBLE_ALPHA:
			idx.append(i)
	var s := 0.0
	for a in idx.size():
		for b in range(a + 1, idx.size()):
			var pa := v.draw_pos(c, idx[a], t)
			var pb := v.draw_pos(c, idx[b], t)
			if pa.distance_to(pb) < v.draw_radius(idx[a], t) + v.draw_radius(idx[b], t):
				s += 1.0
	return s
