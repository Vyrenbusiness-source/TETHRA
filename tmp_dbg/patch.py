p='tests/run_orbit_tests.gd'
s=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in s
s=s.replace('\r\n','\n')
def rep(a,b):
    global s
    assert a in s,a[:60]
    s=s.replace(a,b)
def cut(start,end,new):
    global s
    i=s.index(start); j=s.index(end,i)
    s=s[:i]+new+s[j:]
cut('func _test_chords()','func _test_density()','''func _test_chords() -> void:
	print("- Akkorde")
	var bm := _bm()
	_add(bm, 1000.0, 0)
	_add(bm, 1000.0, 2)
	_add(bm, 2000.0, 0)
	_add(bm, 2000.0, 1)
	_add(bm, 2001.0, 2)
	_add(bm, 2000.0, 3)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 2, "ein Zeiger = ein Ziel: jeder Akkord wird ein Ziel (%d)" % ns.size())
	if ns.size() != 2:
		return
	_ok(ns[0].source_index == 0 and ns[1].source_index == 2, "niedrigste Spalte bleibt")
	var bm2 := _bm()
	_add(bm2, 1000.0, 0, 200.0)
	_add(bm2, 1000.0, 3, 800.0)
	var n2 := OrbitConverter.convert(bm2)
	_ok(n2.size() == 1 and n2[0].is_arc and n2[0].source_index == 1, "Akkord mit Bogen: der laengste Bogen bleibt")


''')
rep('''	_add(bm, 15000.0, 0, 1000.0)
	_add(bm, 15000.0, 3, 4000.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 5, "5 Ziele (%d)" % ns.size())
	if ns.size() != 5:
		return''','''	_add(bm, 15000.0, 3, 4000.0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 4, "4 Ziele (%d)" % ns.size())
	if ns.size() != 4:
		return''')
rep('''	var v3 := ns[3].span_deg() / ns[3].duration_ms()
	var v4 := ns[4].span_deg() / ns[4].duration_ms()
	_ok(ns[3].is_arc and ns[4].is_arc and absf(v3 - v4) < EPS, "LN-Akkord: beide Boegen gleich schnell")
	_ok(absf(ns[4].angle_at(ns[4].end_ms) - OrbitNote.wrap_deg(ns[4].end_angle_deg)) < 1e-4, "angle_at(Ende) = Bogen-Ende")''','''	_ok(ns[3].is_arc and absf(ns[3].angle_at(ns[3].end_ms) - OrbitNote.wrap_deg(ns[3].end_angle_deg)) < 1e-4, "angle_at(Ende) = Bogen-Ende")''')
cut('func _test_ring_flow()','# --- Wertung ---','''func _test_ring_flow() -> void:
	print("- Ring-Wahl (Zeiger steht auf einem Ring)")
	var bm := _bm()
	for i in 8:
		_add(bm, 1000.0 + i * 100.0, 1)
	var ns := OrbitConverter.convert(bm)
	var same := true
	for i in range(1, ns.size()):
		same = same and ns[i].ring == ns[0].ring
	_ok(ns.size() == 8 and same, "Stream bleibt auf einem Ring (Wechselschlag mit zwei Tasten)")
	# Ringwechsel nur mit Zeit und Abstand zum letzten Wechsel.
	var raw: Array[OrbitNote] = [
		OrbitNote.make(1000.0, 10.0, 0, 0), OrbitNote.make(1100.0, 20.0, 1, 1),
		OrbitNote.make(1700.0, 30.0, 1, 2), OrbitNote.make(2000.0, 40.0, 0, 3),
		OrbitNote.make(3200.0, 50.0, 0, 4)]
	var lg := OrbitConverter.legalize(raw, [], false)
	_ok(lg[1].ring == 0, "Wechsel nach 100 ms nicht erlaubt")
	_ok(lg[2].ring == 1, "Wechsel nach 700 ms erlaubt")
	_ok(lg[3].ring == 1, "gleich wieder zurueck (300 ms) nicht erlaubt")
	_ok(lg[4].ring == 0, "nach RING_HOLD_MS wieder frei")
	var easy := OrbitConverter.legalize(raw, [], true)
	var sw := 0
	for i in range(1, easy.size()):
		sw += 1 if easy[i].ring != easy[i - 1].ring else 0
	_ok(sw <= 1, "leicht: hoechstens ein Wechsel (%d)" % sw)
	# Bogen: Ziele im Bogen liegen auf dem Bogen-Ring.
	var bm2 := _bm()
	_add(bm2, 1000.0, 0, 500.0)
	_add(bm2, 1550.0, 0)
	var n2 := OrbitConverter.convert(bm2)
	_ok(n2.size() == 2 and n2[1].ring == n2[0].ring, "Ziel nach Bogen-Ende ohne Ringwechsel")
	# Ueber eine ganze Map: jeder Wechsel haelt die Regeln.
	var mm := OrbitConverter.convert(_mixed_map())
	var bad := 0
	var last_sw := -INF
	for i in range(1, mm.size()):
		if mm[i].ring != mm[i - 1].ring:
			if mm[i].time_ms - mm[i - 1].end_ms < OrbitConverter.RING_SWITCH_MIN_MS - EPS \\
					or mm[i].time_ms - last_sw < OrbitConverter.RING_HOLD_MS - EPS:
				bad += 1
			last_sw = mm[i].time_ms
	_ok(bad == 0, "Ringwechsel halten Zeit + Abstand (%d Verstoesse)" % bad)


''')
rep('''	c.key_down(0, 4000.0 - c.w50 - 10.0, 0.0, _rho(0))
	_ok(got.has(3) and got[3].quality == OrbitCore.Quality.MISS, "zu frueh gezielt frisst das Ziel")''','''	var why: Array = []
	c.press_missed.connect(func(_d: float, _r: float, _ring: int, reason: String) -> void: why.append(reason))
	c.key_down(0, 4000.0 - c.w50 - 10.0, 0.0, _rho(0))
	_ok(not got.has(3) and why == ["EARLY"], "zu frueher Druck frisst das Ziel nicht (Fehldruck EARLY)")
	c.key_down(0, 4000.0, 0.0, _rho(0))
	_ok(got.has(3) and got[3].quality == OrbitCore.Quality.MAX, "danach trifft der richtige Druck")''')
rep('_ok(c.combo == 0 and c.max_combo == 3, "Combo wie Mania")','_ok(c.combo == 0 and c.max_combo == 4, "Combo wie Mania")')
cut('func _test_wrong_ring()','func _arc_notes()','''func _test_wrong_ring() -> void:
	print("- Falscher Ring (Zeigen waehlt den Ring)")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 180.0, 1, 0)]
	var c := _core(ns)
	var got := _results(c)
	var why: Array = []
	c.press_missed.connect(func(_d: float, _r: float, _ring: int, reason: String) -> void: why.append(reason))
	c.key_down(0, 1000.0, 180.0, _rho(0))
	_ok(not got.has(0) and why == ["RING"], "Zeiger innen auf aeusserem Ziel = kein Treffer (RING)")
	c.key_down(0, 1000.0, 180.0, _rho(1))
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MAX and got[0].ring == 1, "Zeiger aussen trifft, egal mit welcher Taste")


func _test_pointing() -> void:
	print("- Ring durch Zeigen (Grenze + Hysterese)")
	var split := OrbitCore.RING_SPLIT_K
	var h := OrbitCore.RING_HYST_K
	_ok(OrbitCore.ring_for_rho(OrbitCore.R_INNER_K, 1) == 0, "Innenring-Abstand waehlt innen")
	_ok(OrbitCore.ring_for_rho(OrbitCore.R_OUTER_K, 0) == 1, "Aussenring-Abstand waehlt aussen")
	_ok(OrbitCore.ring_for_rho(split + h * 0.5, 0) == 0 and OrbitCore.ring_for_rho(split - h * 0.5, 1) == 1,
			"in der Hysterese bleibt der alte Ring")
	_ok(OrbitCore.ring_for_rho(split + h * 2.0, 0) == 1 and OrbitCore.ring_for_rho(split - h * 2.0, 1) == 0,
			"ausserhalb der Hysterese wechselt der Ring")
	_ok(absf(split - (OrbitCore.R_INNER_K + OrbitCore.R_OUTER_K) * 0.5) < EPS, "Grenze mittig zwischen den Ringen")
	var c := _core([OrbitNote.make(1000.0, 0.0, 0, 0)])
	c.cursor_moved(0.0, OrbitCore.R_OUTER_K, 0.0)
	_ok(c.cursor_ring() == 1, "cursor_ring folgt dem Abstand")
	c.cursor_moved(0.0, OrbitCore.R_INNER_K, 10.0)
	_ok(c.cursor_ring() == 0, "und zurueck")


func _test_keys() -> void:
	print("- Beide Tasten treffen jedes Ziel")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 0.0, 0, 0), OrbitNote.make(1100.0, 0.0, 0, 1),
			OrbitNote.make(1200.0, 90.0, 1, 2), OrbitNote.make(1300.0, 90.0, 1, 3)]
	var c := _core(ns)
	var got := _results(c)
	c.key_down(0, 1000.0, 0.0, _rho(0))
	c.key_up(0, 1030.0)
	c.key_down(1, 1100.0, 0.0, _rho(0))
	c.key_up(1, 1130.0)
	c.key_down(1, 1200.0, 90.0, _rho(1))
	c.key_up(1, 1230.0)
	c.key_down(0, 1300.0, 90.0, _rho(1))
	_ok(got.size() == 4, "Wechselschlag und gleiche Taste hintereinander: alle 4 getroffen (%d)" % got.size())
	_ok(c.combo == 4, "Combo 4")


func _test_press_missed() -> void:
	print("- Fehldruck-Meldung")
	var ns: Array[OrbitNote] = [OrbitNote.make(1000.0, 0.0, 0, 0)]
	var c := _core(ns)
	var why: Array = []
	c.press_missed.connect(func(_d: float, _r: float, _ring: int, reason: String) -> void: why.append(reason))
	c.key_down(0, 1000.0, 90.0, _rho(0))
	c.key_down(0, 5000.0, 0.0, _rho(0))
	_ok(why == ["ANGLE", "NONE"], "Winkel daneben = ANGLE, nichts in der Naehe = NONE (%s)" % str(why))


''')
cut('func _test_arc_tap_inside()','func _test_acc_like_mania()','''func _test_arc_tap_inside() -> void:
	print("- Tap waehrend Bogen")
	var bm := _bm()
	_add(bm, 1000.0, 3, 1000.0)
	_add(bm, 1500.0, 0)
	var ns := OrbitConverter.convert(bm)
	_ok(ns.size() == 2 and ns[1].ring == ns[0].ring and absf(ns[1].angle_deg - ns[0].angle_at(1500.0)) < 1e-4,
			"Note im Bogen -> gleicher Ring an der Bogen-Spitze")
	if ns.size() != 2:
		return
	var c := _core(ns)
	var got := _results(c)
	c.key_down(0, 1000.0, ns[0].angle_deg, _rho(ns[0].ring))
	_follow(c, ns[0], 1000.0, 1500.0)
	c.key_down(1, 1500.0, ns[0].angle_at(1500.0), _rho(ns[1].ring))
	c.key_up(1, 1520.0)
	_follow(c, ns[0], 1500.0, 2000.0)
	c.update(2001.0)
	_ok(got.size() == 2 and got[0].quality == OrbitCore.Quality.MAX and got[1].quality == OrbitCore.Quality.MAX,
			"beide getroffen, Bogen haelt mit der anderen Taste weiter")


func _test_arc_ring() -> void:
	print("- Bogen: auf dem Ring bleiben")
	var ns := _arc_notes()
	var n: OrbitNote = ns[0]
	var c := _core(ns)
	var got := _results(c)
	c.key_down(0, 1000.0, n.angle_deg, _rho(n.ring))
	_follow(c, n, 1000.0, 1300.0)
	for k in 12:
		c.cursor_moved(n.angle_at(1300.0 + k * 20.0), _rho(1 - n.ring), 1300.0 + k * 20.0)
		c.update(1300.0 + k * 20.0)
	_ok(got.has(0) and got[0].quality == OrbitCore.Quality.MISS, "Ring verlassen bricht den Bogen")


''')
rep('	_test_wrong_ring()','	_test_wrong_ring()\n	_test_pointing()\n	_test_keys()\n	_test_press_missed()\n	_test_arc_ring()')
if crlf: s=s.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(s)
