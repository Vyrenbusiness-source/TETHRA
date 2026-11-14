extends SceneTree

## Marathon (Plan Punkt 14): Auswahl, Reihenfolge, Zeitachse (Taktgrenze auf
## Taktgrenze, Tempo-Angleich und Rampe, Bass-Tausch, faire Notenluecke, Intro/
## Outro gekuerzt), zusammengefuegte Map (gemeinsame HP/Kombo), Wertung je Map,
## Rangliste je Laenge, Replay-Rundreise. Nur eigene Testdateien (user://test_tmp).

var _fail := 0
var _count := 0


func _ok(cond: bool, what: String) -> void:
	_count += 1
	if not cond:
		_fail += 1
		print("FAIL: " + what)


func _near(a: float, b: float, eps: float, what: String) -> void:
	_ok(absf(a - b) <= eps, "%s (erwartet %.4f, war %.4f)" % [what, b, a])


func _initialize() -> void:
	_test_length_keys()
	_test_tempo_match()
	_test_mapping_roundtrip()
	_test_timeline_matched()
	_test_timeline_hard_cut()
	_test_timeline_half_time()
	_test_intro_outro()
	_test_merge()
	_test_shared_hp_combo()
	_test_json_roundtrip()
	_test_pick()
	_test_candidates()
	_test_order()
	_test_store()
	_test_per_map()
	_test_autoplay_events()
	_test_plan_key()
	print("=== MV-Marathon-Tests: %d Pruefungen, %d Fehler ===" % [_count, _fail])
	quit(1 if _fail > 0 else 0)


# --- Hilfen -------------------------------------------------------------------------

## Synthetische 4K-Mania-Map: Offset, BPM, Noten jeden Schlag von first bis last
## (ms, ab Offset auf dem Raster), Spalten reihum; hold_every > 0: jede n-te ein Hold.
func _map(bpm: float, offset: float, first_beat: int, last_beat: int, hold_every: int = 0,
		meter: int = 4, extra_tp: String = "") -> Beatmap:
	var bl := 60000.0 / bpm
	var ho := ""
	for k in range(first_beat, last_beat + 1):
		var t := int(round(offset + float(k) * bl))
		var col := k % 4
		var x := col * 128 + 64
		if hold_every > 0 and k % hold_every == 0 and k < last_beat:
			ho += "%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, t, int(t + bl * 0.5)]
		else:
			ho += "%d,192,%d,1,0,0:0:0:0:\n" % [x, t]
	var txt := "osu file format v14\n\n[General]\nMode: 3\nAudioFilename: a.mp3\n\n" \
		+ "[Metadata]\nTitle:T%d\nArtist:A\nVersion:V\n\n" % int(bpm) \
		+ "[Difficulty]\nHPDrainRate:7\nCircleSize:4\nOverallDifficulty:8\nApproachRate:5\n" \
		+ "SliderMultiplier:1.4\n\n[TimingPoints]\n%s,%s,%d,1,0,100,1,0\n%s\n[HitObjects]\n" % [
			str(offset), str(bl), meter, extra_tp] + ho
	var res := OsuParser.parse(txt)
	_ok(bool(res.ok), "Testmap parst (%d BPM)" % int(bpm))
	return res.beatmap


func _is_downbeat(reds: Array, s: float) -> bool:
	var r: Dictionary = reds[MarathonPlan.red_index(reds, s)]
	var bar := float(r.bl) * float(r.meter)
	var k := (s - float(r.t)) / bar
	return absf(k - round(k)) * bar < 0.01


# --- Tests --------------------------------------------------------------------------

func _test_length_keys() -> void:
	_ok(MarathonPlan.length_key("n", 3) == "n3", "Schluessel n3")
	_ok(MarathonPlan.parse_length_key("m10").value == 10, "m10 parst")
	_ok(MarathonPlan.parse_length_key("n4").is_empty(), "n4 ist keine Laenge")
	_ok(MarathonPlan.all_length_keys().size() == 6, "sechs Laengen")


func _test_tempo_match() -> void:
	var t := MarathonPlan.tempo_match(140.0, 140.0)
	_ok(bool(t.ok) and absf(float(t.rate) - 1.0) < 1e-9, "gleiches Tempo: Rate 1")
	t = MarathonPlan.tempo_match(144.0, 146.7)
	_ok(bool(t.ok), "144 -> 146,7 passt")
	_near(float(t.rate), 144.0 / 146.7, 1e-9, "Rate 144/146,7")
	t = MarathonPlan.tempo_match(140.0, 70.0)
	_ok(bool(t.ok) and float(t.m) == 0.5, "Halbes Tempo: m = 1/2")
	t = MarathonPlan.tempo_match(85.0, 170.0)
	_ok(bool(t.ok) and float(t.m) == 2.0, "Doppeltes Tempo: m = 2")
	t = MarathonPlan.tempo_match(130.0, 146.7)
	_ok(not bool(t.ok), "130 -> 146,7 (12 %) passt nicht")
	t = MarathonPlan.tempo_match(0.0, 120.0)
	_ok(not bool(t.ok), "Tempo unbekannt: kein Angleich")


func _test_mapping_roundtrip() -> void:
	var seg := {"s_in": 1000.0, "g0": 5000.0, "rho": 0.95, "r0": 8000.0, "r1": 12000.0}
	for g in [5000.0, 6000.0, 8000.0, 9000.0, 11999.0, 12000.0, 20000.0]:
		var s := MarathonPlan.song_at(seg, g)
		_near(MarathonPlan.global_at(seg, s), g, 1e-6, "global(song(g)) = g bei %d" % int(g))
	_near(MarathonPlan.rate_at(seg, 7000.0), 0.95, 1e-9, "Rate vor der Rampe")
	_near(MarathonPlan.rate_at(seg, 10000.0), 0.975, 1e-9, "Rate mitten in der Rampe")
	_near(MarathonPlan.rate_at(seg, 13000.0), 1.0, 1e-9, "Rate nach der Rampe")
	# Stetig und Ableitung = Rate (numerisch).
	var h := 0.5
	for g in [7000.0, 10000.0, 15000.0]:
		var d := (MarathonPlan.song_at(seg, g + h) - MarathonPlan.song_at(seg, g - h)) / (2.0 * h)
		_near(d, MarathonPlan.rate_at(seg, g), 1e-4, "ds/dg = Rate bei %d" % int(g))


func _three_maps() -> Array:
	# 144 -> 146,7 -> 149,3 BPM (passen), je 80 Schlaege mit Holds.
	return [_map(144.0, 812.0, 8, 88, 7), _map(146.7, 233.0, 4, 84, 5), _map(149.3, 1490.0, 6, 90, 6)]


func _test_timeline_matched() -> void:
	var maps := _three_maps()
	var segs := MarathonPlan.build_timeline(maps)
	_ok(segs.size() == 3, "drei Segmente")
	for i in range(1, 3):
		var a: Dictionary = segs[i - 1]
		var b: Dictionary = segs[i]
		var ra := MarathonPlan.reds_of(maps[i - 1])
		var rb := MarathonPlan.reds_of(maps[i])
		var mid := float(b.mid_in)
		_ok(bool(b.tempo_ok), "Uebergang %d: Tempo angeglichen" % i)
		# Mitte ist Taktgrenze von A und von B.
		_ok(_is_downbeat(ra, MarathonPlan.song_at(a, mid)), "Uebergang %d: Mitte = Taktgrenze von A" % i)
		_ok(_is_downbeat(rb, MarathonPlan.song_at(b, mid)), "Uebergang %d: Mitte = Taktgrenze von B" % i)
		# Schlaege von B liegen in der Ueberblendung auf den Schlaegen von A.
		var beat_a := float(b.beat_in)
		var beat_b := MarathonPlan.beat_at(rb, 0.0)
		var sb_mid := MarathonPlan.song_at(b, mid)
		var worst := 0.0
		for k in range(-8, 8):
			var g_b := MarathonPlan.global_at(b, sb_mid + float(k) * beat_b)
			var g_a := MarathonPlan.global_at(a, MarathonPlan.song_at(a, mid) + float(k) * beat_a)
			if g_b <= float(b.r0):
				worst = maxf(worst, absf(g_b - g_a))
		_ok(worst < 0.01, "Uebergang %d: Schlaege deckungsgleich (max %.4f ms)" % [i, worst])
		# Rampe zurueck auf 1.
		_near(MarathonPlan.rate_at(b, float(b.r0) - 1.0), float(b.rho), 1e-9, "Uebergang %d: Rate = rho bis r0" % i)
		_near(MarathonPlan.rate_at(b, float(b.r1) + 1.0), 1.0, 1e-9, "Uebergang %d: Rate 1 nach r1" % i)
		_ok(float(b.r1) > float(b.r0), "Uebergang %d: Rampe hat Dauer" % i)
		# Blende: B stumm vor g0, A stumm nach seinem Ende; Mitte beide hoerbar.
		_near(MarathonPlan.volume_at(b, float(b.g0) - 1.0), 0.0, 1e-9, "Uebergang %d: B stumm vor der Blende" % i)
		_near(MarathonPlan.volume_at(a, float(a.fade_out[1]) + 1.0), 0.0, 1e-9, "Uebergang %d: A stumm danach" % i)
		_ok(MarathonPlan.volume_at(a, mid) > 0.99 and MarathonPlan.volume_at(b, mid) > 0.99,
				"Uebergang %d: Mitte beide voll" % i)
		_near(float(a.fade_out[1]) - float(b.fade_in[0]), MarathonPlan.OVERLAP_BARS * 4.0 * beat_a, 0.5,
				"Uebergang %d: Ueberblendung 4 Takte" % i)
		# Bass-Tausch genau auf der Mitte (ueber einen Schlag).
		_near(MarathonPlan.bass_db_at(b, mid - beat_a), MarathonPlan.BASS_CUT_DB, 1e-6, "Uebergang %d: B ohne Bass vorher" % i)
		_near(MarathonPlan.bass_db_at(b, mid + beat_a), 0.0, 1e-6, "Uebergang %d: B mit Bass danach" % i)
		_near(MarathonPlan.bass_db_at(a, mid - beat_a), 0.0, 1e-6, "Uebergang %d: A mit Bass vorher" % i)
		_near(MarathonPlan.bass_db_at(a, mid + beat_a), MarathonPlan.BASS_CUT_DB, 1e-6, "Uebergang %d: A ohne Bass danach" % i)
		_near(MarathonPlan.bass_db_at(a, mid) + MarathonPlan.bass_db_at(b, mid), MarathonPlan.BASS_CUT_DB, 1e-6,
				"Uebergang %d: Tausch halb-halb auf der Mitte" % i)


func _test_timeline_hard_cut() -> void:
	var maps := [_map(130.0, 500.0, 4, 70), _map(146.7, 300.0, 4, 70)]
	var segs := MarathonPlan.build_timeline(maps)
	var b: Dictionary = segs[1]
	_ok(not bool(b.tempo_ok), "harter Schnitt: Tempo passt nicht")
	_near(float(b.rho), 1.0, 1e-9, "harter Schnitt: Originaltempo")
	var beat_a := float(b.beat_in)
	_near(float(b.fade_in[1]) - float(b.fade_in[0]), beat_a, 0.01, "harter Schnitt: 1 Schlag Einblendung")
	_ok(_is_downbeat(MarathonPlan.reds_of(maps[1]), MarathonPlan.song_at(b, float(b.mid_in))),
			"harter Schnitt: B beginnt auf seiner Taktgrenze")
	_ok(_is_downbeat(MarathonPlan.reds_of(maps[0]), MarathonPlan.song_at(segs[0], float(b.mid_in))),
			"harter Schnitt: auf der Taktgrenze von A")
	_ok((b.bass_in as Array).is_empty(), "harter Schnitt: kein Bass-Tausch")
	var nr: Array = []
	var mg := MarathonPlan.merge(maps, segs, "M", nr)
	var last_a := 0.0
	for k in range(int(nr[0][0]), int(nr[0][1])):
		last_a = maxf(last_a, mg.hit_objects[k].end_time())
	_ok(mg.hit_objects[int(nr[1][0])].time - last_a >= beat_a - 0.01, "harter Schnitt: Luecke >= 1 Schlag")


func _test_timeline_half_time() -> void:
	# 85 -> 170 BPM: B laeuft im Doppeltakt, Schlaege von B halbieren die von A.
	var maps := [_map(170.0, 400.0, 4, 120), _map(85.0, 700.0, 2, 60)]
	var segs := MarathonPlan.build_timeline(maps)
	var b: Dictionary = segs[1]
	_ok(bool(b.tempo_ok) and float(b.m) == 0.5, "Halbtakt erkannt (m = 1/2)")
	_ok(_is_downbeat(MarathonPlan.reds_of(maps[1]), MarathonPlan.song_at(b, float(b.mid_in))),
			"Halbtakt: Mitte = Taktgrenze von B")


func _test_intro_outro() -> void:
	var maps := _three_maps()
	var segs := MarathonPlan.build_timeline(maps)
	var r0 := MarathonPlan.reds_of(maps[0])
	var bar0 := MarathonPlan.bar_at(r0, 0.0)
	var first := MarathonPlan.first_note_ms(maps[0])
	var lead := first - float(segs[0].s_in)
	_ok(lead >= 2.0 * bar0 - 1.0 and lead < 3.0 * bar0, "Intro auf 2-3 Takte gekuerzt (%.0f ms)" % lead)
	_ok(_is_downbeat(r0, float(segs[0].s_in)), "Intro beginnt auf einer Taktgrenze")
	var l: Dictionary = segs[2]
	var fo: Array = l.fade_out
	var rl := MarathonPlan.reds_of(maps[2])
	_near(MarathonPlan.song_at(l, float(fo[1])) - MarathonPlan.song_at(l, float(fo[0])),
			2.0 * MarathonPlan.bar_at(rl, 0.0), 0.01, "Outro: 2 Takte Ausblendung")
	_ok(MarathonPlan.timeline_end(segs) == float(fo[1]), "Ende = Ausblendung der letzten Map")
	# Ein Uebergang kuerzt das Outro von A: A endet mit seiner Ausblendung.
	_ok(float(segs[0].play_to) <= float(segs[1].fade_in[0]) + 8.0 * 4.0 * float(segs[1].beat_in),
			"Outro von A gekuerzt")


func _test_merge() -> void:
	var maps := _three_maps()
	var segs := MarathonPlan.build_timeline(maps)
	var nr: Array = []
	var mg := MarathonPlan.merge(maps, segs, "Marathon", nr)
	_ok(mg.is_mania() and mg.column_count() == 4, "zusammengefuegt: 4K-Mania")
	_ok(nr.size() == 3, "Notenbereiche je Map")
	var sorted := true
	for k in range(1, mg.hit_objects.size()):
		if mg.hit_objects[k].time < mg.hit_objects[k - 1].time:
			sorted = false
	_ok(sorted, "Noten zeitlich sortiert")
	var total := 0
	for m in maps:
		total += (m as Beatmap).hit_objects.size()
	_ok(mg.hit_objects.size() <= total and mg.hit_objects.size() >= total - 6, "Notenzahl (hoechstens wenige gekappt)")
	for i in range(1, 3):
		var last_a := 0.0
		for k in range(int(nr[i - 1][0]), int(nr[i - 1][1])):
			last_a = maxf(last_a, mg.hit_objects[k].end_time())
		var first_b: float = mg.hit_objects[int(nr[i][0])].time
		var beat_a := float(segs[i].beat_in)
		_ok(first_b - last_a >= beat_a - 0.01, "Uebergang %d: Luecke %.0f ms >= 1 Schlag (%.0f)" % [i, first_b - last_a, beat_a])
		_ok(first_b - last_a >= MarathonPlan.MIN_GAP_MS - 0.01, "Uebergang %d: Luecke >= MIN_GAP" % i)
		# Rote Linie an der Mitte mit dem angeglichenen Schlag.
		var found := false
		for tp in mg.timing_points:
			if tp.uninherited and absf(tp.time - float(segs[i].mid_in)) < 0.01:
				found = absf(tp.beat_length - beat_a / float(segs[i].m)) < 0.01
		_ok(found, "Uebergang %d: Takt-Raster wechselt auf der Mitte, Schlag angeglichen" % i)
	# Takt-Raster im Feld laeuft weiter: keine zwei roten Linien enger als 1 ms.
	var tight := false
	var last_red := -INF
	for tp in mg.timing_points:
		if tp.uninherited:
			if tp.time - last_red < 1.0:
				tight = true
			last_red = tp.time
	_ok(not tight, "keine doppelten Taktlinien")
	# Notenzeiten: Map 2 auf der Zeitachse = global_at(Songzeit).
	var src: ManiaNote = maps[1].hit_objects[10]
	var found_n := false
	for k in range(int(nr[1][0]), int(nr[1][1])):
		var n := mg.hit_objects[k] as ManiaNote
		if n.column == src.column and absf(n.time - MarathonPlan.global_at(segs[1], src.time)) < 0.001:
			found_n = true
	_ok(found_n, "Notenzeit folgt der Abbildung")
	# Gleiche Eingabe -> gleiche Map (Replay).
	var mg2 := MarathonPlan.merge(maps, MarathonPlan.build_timeline(maps), "Marathon", [])
	var same := mg2.hit_objects.size() == mg.hit_objects.size() and mg2.timing_points.size() == mg.timing_points.size()
	if same:
		for k in mg.hit_objects.size():
			if mg.hit_objects[k].time != mg2.hit_objects[k].time:
				same = false
				break
	_ok(same, "deterministisch")


func _test_shared_hp_combo() -> void:
	var maps := _three_maps()
	var segs := MarathonPlan.build_timeline(maps)
	var nr: Array = []
	var mg := MarathonPlan.merge(maps, segs, "Marathon", nr)
	# Autoplay ueber alle Maps: eine durchgehende Kombo.
	var core := ManiaCore.new()
	core.setup(mg)
	var ev := MarathonHarness.autoplay_events(mg)
	var done := [false]  # Lambdas fangen Werte, kein bool direkt
	core.finished.connect(func(_s): done[0] = true)
	for e in ev:
		core.update(float(e.t))
		if bool(e.down):
			core.key_down(int(e.lane), float(e.t))
		else:
			core.key_up(int(e.lane), float(e.t))
	core.update(mg.hit_objects.back().end_time() + 1000.0)
	_ok(core.n_miss == 0, "Autoplay: keine Fehler")
	_ok(core.max_combo == mg.hit_objects.size(), "Kombo laeuft durch alle Maps (%d)" % core.max_combo)
	_ok(bool(done[0]), "Ende nach der letzten Map")
	# HP gemeinsam: Fehler in Map 1 bleiben in Map 2 sichtbar (kein Neustart der HP).
	var core2 := ManiaCore.new()
	core2.setup(mg)
	var miss_until: float = mg.hit_objects[int(nr[0][1]) - 1].time
	var hp_at_switch := -1.0
	for e in ev:
		var t := float(e.t)
		core2.update(t)
		if hp_at_switch < 0.0 and t >= float(segs[1].mid_in):
			hp_at_switch = core2.hp
		if t > miss_until - 6000.0 and t <= miss_until:
			continue  # letzte 6 s von Map 1 verpasst
		if bool(e.down):
			core2.key_down(int(e.lane), t)
		else:
			core2.key_up(int(e.lane), t)
	_ok(hp_at_switch >= 0.0 and hp_at_switch < 0.99, "HP an der Map-Grenze nicht aufgefuellt (%.2f)" % hp_at_switch)
	_ok(core2.max_combo < mg.hit_objects.size() and core2.n_miss > 0, "Fehler brechen die gemeinsame Kombo")


func _test_json_roundtrip() -> void:
	var maps := _three_maps()
	var segs := MarathonPlan.build_timeline(maps)
	var js := JSON.stringify(MarathonPlan.timeline_to_json(segs), "", false, true)
	var back := MarathonPlan.timeline_from_json(JSON.parse_string(js))
	_ok(back.size() == segs.size(), "Zeitachse: Rundreise Anzahl")
	_ok(back[0].mid_in == -INF and back[0].play_to != INF, "INF uebersteht JSON")
	var a := MarathonPlan.merge(maps, segs, "M", [])
	var b := MarathonPlan.merge(maps, back, "M", [])
	var same := a.hit_objects.size() == b.hit_objects.size()
	if same:
		for k in a.hit_objects.size():
			if a.hit_objects[k].time != b.hit_objects[k].time or a.hit_objects[k].end_time() != b.hit_objects[k].end_time():
				same = false
				break
	_ok(same, "Replay-Zeitachse ergibt bitgleiche Notenzeiten")


func _pool() -> Array:
	var out: Array = []
	var bpms := [120.0, 124.0, 128.0, 140.0, 142.0, 150.0, 174.0, 87.0, 180.0, 160.0]
	for k in bpms.size():
		out.append({"osz": "m%02d.osz" % k, "version": "V", "osu": "x.osu", "stars": 3.0 + 0.05 * float(k % 5),
			"bpm": bpms[k], "duration_ms": 90000.0 + 7000.0 * float(k), "notes": 400 + 60 * k,
			"title": "Song %d" % k, "artist": "A"})
	out.append({"osz": "far.osz", "version": "V", "stars": 4.5, "bpm": 140.0, "duration_ms": 90000.0, "notes": 500})
	out.append({"osz": "short.osz", "version": "V", "stars": 3.1, "bpm": 140.0, "duration_ms": 20000.0, "notes": 100})
	return out


func _test_pick() -> void:
	var pool := MarathonPlan.filter_pool(_pool(), 3.1)
	_ok(pool.size() == 10, "Pool: Sterne +- 0,3 und Mindestlaenge (%d)" % pool.size())
	var p1 := MarathonPlan.pick(pool, "n3", 42)
	var p2 := MarathonPlan.pick(pool, "n3", 42)
	_ok(p1.size() == 3, "n3: drei Maps")
	var same := true
	for k in p1.size():
		if p1[k].osz != p2[k].osz:
			same = false
	_ok(same, "gleicher Seed -> gleiche Auswahl")
	for c in p1:
		_ok(absf(float(c.stars) - 3.1) <= 0.3 + 1e-6, "Sterne im Fenster: " + str(c.osz))
	var p5 := MarathonPlan.pick(pool, "n5", 7, "m03.osz")
	var has_anchor := false
	for c in p5:
		if c.osz == "m03.osz":
			has_anchor = true
	_ok(p5.size() == 5 and has_anchor, "n5 mit gewaehlter Start-Map")
	var pm := MarathonPlan.pick(pool, "m10", 3)
	var tot := 0.0
	for c in pm:
		tot += float(c.duration_ms)
	_ok(tot >= 600000.0, "m10: mindestens 10 Minuten (%.0f s)" % (tot / 1000.0))
	# Passendes Tempo bevorzugt: Nachbarn mit kleiner Tempo-Abweichung.
	var ok_pairs := 0
	for k in range(1, p5.size()):
		if bool(MarathonPlan.tempo_match(float(p5[k - 1].bpm), float(p5[k].bpm)).ok):
			ok_pairs += 1
	_ok(ok_pairs >= 3, "n5: mindestens 3 von 4 Uebergaengen mit Tempo-Angleich (%d)" % ok_pairs)
	_ok(MarathonPlan.pick([], "n3", 1).is_empty(), "leerer Pool -> keine Auswahl")


func _test_candidates() -> void:
	var a := MapSet.new()
	a.osz_path = "C:/x/a.osz"
	a.title = "A"
	a.diffs = [{"version": "Easy", "mode": 3, "cs": 4.0, "stars": 1.5, "bpm": 120.0, "duration_ms": 90000.0, "notes": 300},
		{"version": "Hard", "mode": 3, "cs": 4.0, "stars": 3.2, "bpm": 120.0, "duration_ms": 90000.0, "notes": 600},
		{"version": "7K", "mode": 3, "cs": 7.0, "stars": 3.0, "bpm": 120.0, "duration_ms": 90000.0, "notes": 600}]
	var b := MapSet.new()
	b.osz_path = "C:/x/b.osz"
	b.diffs = [{"version": "Std", "mode": 0, "cs": 4.0, "stars": 3.0}]
	var c := MarathonPlan.candidates_from_sets([a, b], 3.0)
	_ok(c.size() == 1 and c[0].version == "Hard", "je Set die passende 4K-Diff")
	var d := MarathonPlan.candidates_from_sets([a, b], 3.0, true, ["b.osz"])
	_ok(d.is_empty(), "Sammlung filtert Sets")
	_ok(MarathonPlan.candidates_from_sets([a], 2.4).is_empty(), "ausserhalb +- 0,3: keine")


func _test_order() -> void:
	var pool := MarathonPlan.filter_pool(_pool(), 3.1).slice(0, 6)
	var o := MarathonPlan.order(pool)
	_ok(o.size() == pool.size(), "Reihenfolge behaelt alle Maps")
	_ok(MarathonPlan.order_cost(o) <= MarathonPlan.order_cost(pool) + 1e-9, "Reihenfolge nicht schlechter als die Eingabe")
	var o2 := MarathonPlan.order(pool.duplicate())
	var same := true
	for k in o.size():
		if o[k].osz != o2[k].osz:
			same = false
	_ok(same, "Reihenfolge deterministisch")


func _test_store() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_tmp"))
	MarathonStore.path_override = "user://test_tmp/mv_marathon_scores.cfg"
	MarathonStore.replay_dir_override = "user://test_tmp/mv_marathon_replays"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MarathonStore.path_override))
	var r1 := MarathonStore.submit("n3", {"score": 500000, "date": "2026-11-14T10:00:00"})
	_ok(int(r1.rank) == 1 and bool(r1.is_new_best), "erster Eintrag Platz 1")
	var r2 := MarathonStore.submit("n3", {"score": 800000, "date": "2026-11-14T10:05:00"})
	_ok(int(r2.rank) == 1 and int(r2.previous.score) == 500000, "besserer Lauf Platz 1, Vorgaenger gemeldet")
	var r3 := MarathonStore.submit("n3", {"score": 600000, "date": "2026-11-14T10:10:00"})
	_ok(int(r3.rank) == 2 and not bool(r3.is_new_best), "mittlerer Lauf Platz 2")
	MarathonStore.submit("m5", {"score": 100, "date": "2026-11-14T10:00:00"})
	_ok(MarathonStore.top("n3").size() == 3 and MarathonStore.top("m5").size() == 1, "eigene Liste je Laenge")
	_ok(int(MarathonStore.best("n3").score) == 800000, "Bestwert je Laenge")
	var ev := [{"t": 1000.25, "lane": 1, "down": true}, {"t": 1040.25, "lane": 1, "down": false}]
	var meta := {"mode": "marathon", "marathon": {"maps": [{"osz": "a.osz"}], "timeline": [{"g0": 0.1234567890123}]}}
	_ok(MarathonStore.save_replay("abc", ev, meta), "Replay speichern")
	var back := MarathonStore.load_replay("abc")
	_ok(not back.is_empty() and back.events.size() == 2, "Replay laden")
	_ok(float(back.meta.marathon.timeline[0].g0) == 0.1234567890123, "Zeitachse volle Genauigkeit")
	_ok(not MarathonStore.save_replay("leer", [], meta), "leeres Replay wird nicht gespeichert")
	var op := MarathonStore.online_payload("n3", {"score": 5, "mods": ["NF"]}, [{"osz": "C:/x/a.osz", "version": "V"}])
	_ok(op.mode == "mania_marathon" and op.ranked == false and op.maps[0].osz == "a.osz", "Server-Felder")
	MarathonStore.path_override = ""
	MarathonStore.replay_dir_override = ""


func _test_per_map() -> void:
	var run := MarathonRun.new()
	run.note_ranges = [[0, 3], [3, 5]]
	run.per_map = []
	for r in run.note_ranges:
		run.per_map.append({"n_max": 0, "n300": 0, "n200": 0, "n100": 0, "n50": 0, "n_miss": 0,
			"score": 0, "combo": 0, "max_combo": 0, "judged": 0, "notes": int(r[1]) - int(r[0])})
	for k in 3:
		run._on_judged(k, {"quality": ManiaCore.Quality.MAX})
	run._on_judged(3, {"quality": ManiaCore.Quality.MISS})
	run._on_judged(4, {"quality": ManiaCore.Quality.GOOD})
	_ok(int(run.per_map[0].n_max) == 3 and int(run.per_map[0].max_combo) == 3, "Map 1: drei MAX, Kombo 3")
	_ok(int(run.per_map[1].n_miss) == 1 and int(run.per_map[1].n200) == 1, "Map 2: ein Fehler, ein 200")
	_near(MarathonRun.map_accuracy(run.per_map[0]), 1.0, 1e-9, "Genauigkeit Map 1")
	_near(MarathonRun.map_accuracy(run.per_map[1]), 200.0 / 600.0, 1e-9, "Genauigkeit Map 2")
	_ok(run.segment_of_note(4) == 1 and run.segment_of_note(0) == 0, "Note -> Map")


func _test_autoplay_events() -> void:
	var bm := _map(120.0, 0.0, 0, 16, 3)
	var ev := MarathonHarness.autoplay_events(bm)
	var downs := 0
	var ok_order := true
	for k in ev.size():
		if bool(ev[k].down):
			downs += 1
		if k > 0 and float(ev[k].t) < float(ev[k - 1].t):
			ok_order = false
	_ok(downs == bm.hit_objects.size() and ev.size() == 2 * downs, "je Note ein Druecken und Loslassen")
	_ok(ok_order, "Ereignisse zeitlich sortiert")


func _test_plan_key() -> void:
	var p := MarathonRun.new_plan([{"osz": "C:/a/x.osz", "version": "H"}, {"osz": "D:/y.osz", "version": "I"}], "n3", 1, "auto", 3.0)
	var q := MarathonRun.new_plan([{"osz": "E:/x.osz", "version": "H"}, {"osz": "y.osz", "version": "I"}], "n3", 9, "auto", 3.0)
	_ok(MarathonRun.plan_key(p) == MarathonRun.plan_key(q), "gleiche Maps -> gleicher Schluessel (Ordner egal)")
	var r := MarathonRun.new_plan([{"osz": "y.osz", "version": "I"}, {"osz": "x.osz", "version": "H"}], "n3", 1, "auto", 3.0)
	_ok(MarathonRun.plan_key(p) != MarathonRun.plan_key(r), "andere Reihenfolge -> anderer Schluessel")
	_ok(MarathonRun.length_text("m10").contains("10"), "Laengen-Text")
