extends SceneTree

## Orbit-QA (Bahnen): Messungen statt Bauchgefuehl.
##  1. Kopf-Tempo bei echten BPM/Taktarten und je Bahnform (Einheiten/s).
##  2. Erreichbarkeit: ein Bot, der dem Kopf wie ein Spieler folgt (Cursor
##     zieht dem Kopf mit Verzoegerung tau nach, Zeit- und Zielstreuung):
##     Tablet, Maus und ein schwacher Spieler, je Bahnform am Tempolimit und
##     auf Maps quer durch die Sterne.
##  3. Muster-Regelmaessigkeit: Anteil der Ziele auf dem Raster (Viertel/Achtel/
##     Sechzehntel) und wie oft ein Takt den Rhythmus eines der letzten 4 Takte
##     wiederholt.
##  4. Sterne gegen Bot-Erfolg (Rangkorrelation); erste Maps muessen leicht sein.
## Headless:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_qa_tests.gd

const STEP_MS := 4.0
## Bots: Nachlauf tau (ms), Zeitstreuung (ms), Zielstreuung (Aim-Punkte, 100 = eine Bahn-Einheit).
const BOTS := {
	"tablet": [35.0, 20.0, 4.0],
	"maus": [60.0, 25.0, 6.0],
	"schwach": [90.0, 32.0, 8.0],
}
const PICK := 9

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("=== TETHRA Orbit-QA (Bahnen) ===")
	_test_hand_speed()
	_test_follow_limits()
	_test_shapes()
	var picks := _pick_maps()
	_test_regularity(picks)
	_test_bots(picks)
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _tp(bm: Beatmap, t: float, bpm: float, meter: int) -> void:
	var tp := TimingPoint.new()
	tp.time = t
	tp.beat_length = 60000.0 / bpm
	tp.meter = meter
	tp.uninherited = true
	bm.timing_points.append(tp)


# --- 1. Hand-Tempo ---

func _test_hand_speed() -> void:
	print("- Hand-Tempo bei echten BPM")
	var worst := 0.0
	for meter in [3, 4, 6, 7]:
		var line := "  %d/4:" % meter
		for bpm in [80, 120, 140, 170, 200, 240, 280]:
			var bm := Beatmap.new()
			_tp(bm, 0.0, bpm, meter)
			var c := OrbitClock.from_beatmap(bm)
			var dps := c.speed_at(0.0) * 1000.0
			worst = maxf(worst, dps)
			line += " %d BPM %.0f Grad/s (%.0f U/min)," % [bpm, dps, dps / 6.0]
		print(line.trim_suffix(","))
	_ok(worst <= 360.0 / OrbitClock.MIN_BAR_MS * 1000.0 + 0.01, "nie schneller als %.0f Grad/s (%.1f Umdrehungen/s)" % [worst, worst / 360.0])
	var bm4 := Beatmap.new()
	_tp(bm4, 0.0, 240.0, 4)
	_ok(OrbitClock.from_beatmap(bm4).speed_at(0.0) * 1000.0 <= 180.0 + 0.01, "240 BPM 4/4: eine Umdrehung pro zwei Takte")


## Wie viel Nachlauf darf ein Spieler haben? Bei Tempo v (Einheiten/ms) steht der
## Cursor dauerhaft v * tau hinter dem Kopf; Zielstreuung 2 sigma kommt dazu.
func _test_follow_limits() -> void:
	print("- Folgen: erlaubter Nachlauf je Tempo (Tempolimit der Bahn)")
	var tol := OrbitCore.AIM_TOL / 100.0
	for v in [OrbitTrack.MAX_SPEED, OrbitTrack.MAX_SPEED_EASY]:
		var tau_max: float = (tol - 2.0 * float(BOTS["maus"][2]) / 100.0) / float(v)
		print("  Kopf %.4f E/ms: Nachlauf bis %.0f ms ok" % [v, tau_max])
		_ok(tau_max >= float(BOTS["maus"][0]), "Kopf %.4f E/ms: Maus-Nachlauf (60 ms) passt" % v)


## Jede Bahnform am Tempolimit (kuerzester erlaubter Takt): Noten auf jedem
## Achtel, wechselnde Spuren. Maus-Bot muss >= 90 % treffen.
func _test_shapes() -> void:
	print("- Erreichbarkeit je Bahnform (Takt am Tempolimit)")
	for shape in OrbitPath.COUNT:
		var bar := maxf(OrbitPath.length(shape) / OrbitTrack.MAX_SPEED, OrbitClock.MIN_BAR_MS)
		var clock := OrbitClock.fixed(bar, 4, 0.0)
		var tr := OrbitTrack.fixed(clock, shape)
		var ns: Array[OrbitNote] = []
		var step := bar / 8.0
		for i in 8 * 12:
			var t := 2000.0 + float(i) * step
			var n := OrbitNote.make(t, clock.angle_at(t), i % 2)
			n.shape = shape
			n.speed = tr.speed_at(t)
			ns.append(n)
		var line := "  %s (Takt %.0f ms, Kopf %.4f E/ms):" % [OrbitPath.NAMES[shape], bar, tr.speed_at(0.0)]
		for name in ["tablet", "maus"]:
			var r := _run_track(ns, tr, BOTS[name], 11, 5.0, 5.0)
			line += "  %s Acc %.1f%% Miss %d;" % [name, float(r[0]) * 100.0, r[1]]
			var hit := 1.0 - float(r[1]) / float(ns.size())
			_ok(hit >= 0.9 and not r[2], "%s: %s trifft >= 90 %% (%.1f%%)" % [OrbitPath.NAMES[shape], name, hit * 100.0])
		print(line)
	_ok(OrbitTrack.fixed(OrbitClock.fixed(1200.0), OrbitPath.CIRCLE).speed_at(0.0) <= OrbitTrack.MAX_SPEED + 1e-6,
		"Kreis bei kuerzestem Takt unter dem Tempolimit")


# --- Map-Auswahl ---

func _pick_maps() -> Array:
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	var found: Array = []
	if da == null:
		print("  (kein maps/-Ordner)")
		return found
	var files := Array(da.get_files())
	files.sort()
	var step := maxi(1, files.size() / 40)
	var i := 0
	while i < files.size():
		var f: String = files[i]
		i += step
		if not f.to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.hit_objects.size() < 80 or (bm.is_mania() and bm.column_count() != 4):
				continue
			var ns := OrbitConverter.convert(bm)
			found.append({"label": "%s [%s]" % [f.get_basename().left(26), bm.version_name()],
				"bm": bm, "ns": ns, "stars": OrbitConverter.stars(ns)})
	found.sort_custom(func(a, b): return a.stars < b.stars)
	var out: Array = []
	if found.size() <= PICK:
		return found
	for k in PICK:
		out.append(found[int(float(k) * float(found.size() - 1) / float(PICK - 1))])
	print("  %d Diffs in der Auswahl-Menge, Sterne %.2f .. %.2f" % [found.size(), found[0].stars, found[-1].stars])
	return out


# --- 3. Regelmaessigkeit ---

func _test_regularity(picks: Array) -> void:
	print("- Muster-Regelmaessigkeit (Raster, Wiederholung)")
	var sum_grid := 0.0
	var sum_rep := 0.0
	var n_maps := 0
	for p in picks:
		var bm: Beatmap = p.bm
		var ns: Array[OrbitNote] = p.ns
		var reds := OrbitConverter.red_points(bm)
		if ns.size() < 50 or reds.is_empty():
			continue
		var on_grid := 0
		var sigs: Dictionary = {}   # Takt -> Signatur
		var clock := OrbitClock.from_beatmap(bm)
		for n in ns:
			var s: Array = clock.segs[clock._idx(n.time_ms)]
			var beat := float(s[1]) / float(s[2])
			var ph := (n.time_ms - float(s[0])) / (beat / 4.0)
			if absf(ph - roundf(ph)) * beat / 4.0 <= 12.0:
				on_grid += 1
			var bar := clock.bar_at(n.time_ms)
			var key := "%d:%d" % [int(roundf(n.angle_deg / 22.5)) % 16, n.ring]
			sigs[bar] = str(sigs.get(bar, "")) + key + ","
		var bars := sigs.keys()
		bars.sort()
		var rep := 0
		for k in range(1, bars.size()):
			for j in range(maxi(0, k - 4), k):
				if sigs[bars[j]] == sigs[bars[k]]:
					rep += 1
					break
		var grid := float(on_grid) / float(ns.size())
		var repf := float(rep) / float(maxi(bars.size() - 1, 1))
		print("  %s: %d Ziele, auf Sechzehntel-Raster %.0f%%, Takt wiederholt einen der letzten 4: %.0f%%, Sterne %.2f" % [
			p.label, ns.size(), grid * 100.0, repf * 100.0, p.stars])
		sum_grid += grid
		sum_rep += repf
		n_maps += 1
	if n_maps > 0:
		_ok(sum_grid / n_maps >= 0.6, "Mehrheit der Ziele auf dem Raster (%.0f%%)" % (100.0 * sum_grid / n_maps))
		print("  Wiederholung im Mittel %.0f%%" % (100.0 * sum_rep / n_maps))


# --- 2. Erreichbarkeit mit Folge-Bot ---

func _core(ns: Array[OrbitNote], bm: Beatmap) -> OrbitCore:
	var c := OrbitCore.new()
	c.setup(ns, bm.od(), 1.0, bm.hp(), {})
	c.set_replay_mode(false)
	return c


func _run_bot(ns: Array[OrbitNote], bm: Beatmap, bot: Array, seed: int) -> Array:
	return _run_track(ns, OrbitConverter.track_for(bm, ns), bot, seed, bm.od(), bm.hp())


## Spielt ns mit einem Folge-Bot. Rueckgabe: [Acc, Misses, gescheitert, Zielfehler-Mittel, Note].
func _run_track(ns: Array[OrbitNote], tr: OrbitTrack, bot: Array, seed: int, od: float, hp: float) -> Array:
	var tau: float = bot[0]
	var st: float = bot[1]
	var sa: float = bot[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var c := OrbitCore.new()
	c.setup(ns, od, 1.0, hp, {})
	c.set_track(tr)
	c.set_replay_mode(false)
	# Tasten-Events mit Zeitstreuung vorbereiten: [Zeit, Index, Zielversatz].
	var downs: Array = []
	for i in ns.size():
		var n := ns[i]
		var td := n.time_ms + clampf(rng.randfn(0.0, st), -2.5 * st, 2.5 * st)
		var oa := clampf(rng.randfn(0.0, sa), -2.5 * sa, 2.5 * sa)
		downs.append([td, i, Vector2.from_angle(float(i) * 2.399963) * (oa / 100.0)])
	downs.sort_custom(func(a, b): return a[0] < b[0])
	var ups: Array = []   # [t, ring]
	var t := ns[0].time_ms - 800.0
	var cur := tr.head(t)
	var di := 0
	var end_t: float = ns[-1].end_ms + 400.0
	var held := [-1, -1]
	var off := Vector2.ZERO
	while t < end_t and not c.failed:
		t += STEP_MS
		# Cursor zieht dem Kopf nach (Tiefpass), Zielversatz wandert langsam.
		var a := 1.0 - exp(-STEP_MS / tau)
		cur = cur.lerp(tr.head(t) + off, a)
		c.cursor_moved(cur, t)
		while di < downs.size() and float(downs[di][0]) <= t:
			var i: int = downs[di][1]
			off = downs[di][2]
			var n := ns[i]
			var td: float = downs[di][0]
			di += 1
			if held[n.ring] >= 0:
				c.key_up(n.ring, td)
				held[n.ring] = -1
			c.key_down(n.ring, td, cur)
			if n.is_arc:
				held[n.ring] = i
				ups.append([n.end_ms + rng.randf_range(-10.0, 25.0), n.ring])
			else:
				ups.append([td + 40.0, n.ring])
		ups.sort_custom(func(x, y): return x[0] < y[0])
		while not ups.is_empty() and float(ups[0][0]) <= t:
			var u: Array = ups.pop_front()
			c.key_up(u[1], float(u[0]))
			held[u[1]] = -1
		c.update(t)
	c.update(end_t + 600.0)
	return [c.accuracy(), c.n_miss, c.failed, c.mean_aim_err(), c.grade()]


func _test_bots(picks: Array) -> void:
	print("- Erreichbarkeit (Folge-Bot: Nachlauf tau, Zeit- und Zielstreuung)")
	if picks.is_empty():
		return
	var weak_miss: Array = []
	var stars: Array = []
	var speeds: Array = []
	var easy_ok := true
	for p in picks:
		var ns: Array[OrbitNote] = p.ns
		if ns.size() < 20:
			continue
		var sps: Array = []
		for n in ns:
			sps.append(n.speed)
		sps.sort()
		var line := "  %s * %.2f (%d Ziele, Kopf %.4f E/ms):" % [p.label, p.stars, ns.size(), float(sps[sps.size() / 2])]
		for name in BOTS:
			var r := _run_bot(ns, p.bm, BOTS[name], 7)
			line += "  %s Acc %.1f%% Miss %d %s %s;" % [name, float(r[0]) * 100.0, r[1], "FAIL" if r[2] else "ok", r[4]]
			if name == "tablet" or name == "maus":
				if p.stars < 5.0:
					_ok(not r[2] and float(r[0]) > 0.85, "%s: %s schafft %s (Acc %.1f%%)" % [name, p.label, "die Map", float(r[0]) * 100.0])
			if name == "schwach":
				weak_miss.append(float(r[1]) / float(ns.size()))
				stars.append(p.stars)
				var sp: Array = []
				for n in ns:
					sp.append(n.speed)
				sp.sort()
				speeds.append(float(sp[sp.size() / 2]))
				if p.stars < 3.0:
					easy_ok = easy_ok and not r[2] and float(r[0]) > 0.8
		print(line)
	_ok(easy_ok, "erste Maps (< 3 Sterne): auch der schwache Bot kommt mit Acc > 80% durch")
	if stars.size() >= 4:
		# Der schwache Bot scheitert am Folgen: auf Maps mit langsamem Kopf
		# (<= 0,0030 E/ms) macht er deutlich weniger Fehler als bei schneller.
		var slow := 0.0
		var fast := 0.0
		var ns_slow := 0
		var ns_fast := 0
		for i in speeds.size():
			if speeds[i] <= 0.0030:
				slow += weak_miss[i]
				ns_slow += 1
			else:
				fast += weak_miss[i]
				ns_fast += 1
		var rho_s := _spearman(stars, weak_miss)
		print("  Schwacher Bot: Fehlerquote langsamer Kopf %.1f%% (%d Maps), schneller Kopf %.1f%% (%d Maps); Spearman Sterne %.2f" % [
			100.0 * slow / maxi(ns_slow, 1), ns_slow, 100.0 * fast / maxi(ns_fast, 1), ns_fast, rho_s])
		if ns_slow > 0 and ns_fast > 0:
			_ok(slow / ns_slow < fast / ns_fast, "langsamer Kopf = weniger Fehler beim schwachen Bot")


static func _ranks(v: Array) -> Array:
	var idx := range(v.size())
	idx.sort_custom(func(a, b): return v[a] < v[b])
	var r: Array = []
	r.resize(v.size())
	for k in idx.size():
		r[idx[k]] = float(k)
	return r


static func _spearman(a: Array, b: Array) -> float:
	var ra := _ranks(a)
	var rb := _ranks(b)
	var n := float(a.size())
	var ma := (n - 1.0) * 0.5
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in a.size():
		num += (ra[i] - ma) * (rb[i] - ma)
		da += (ra[i] - ma) * (ra[i] - ma)
		db += (rb[i] - ma) * (rb[i] - ma)
	return num / maxf(sqrt(da * db), 1e-9)
