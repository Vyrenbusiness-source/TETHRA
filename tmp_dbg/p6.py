p='tests/run_orbit_tutorial_tests.gd'
s=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in s
s=s.replace('\r\n','\n')
def rep(a,b):
    global s
    assert a in s,a[:50]
    s=s.replace(a,b)
rep('''	var chord: Array = S.pattern(3, 10, 0)
	_check(chord[0].time_ms == chord[1].time_ms and chord[0].angle_deg == chord[1].angle_deg
		and chord[0].ring != chord[1].ring, "Akkord: gleiche Zeit, gleicher Winkel, beide Ringe")''','''	var sw: Array = S.pattern(3, 10, 0)
	var alt := true
	for i in range(1, sw.size()):
		alt = alt and sw[i].ring != sw[i - 1].ring and sw[i].time_ms > sw[i - 1].time_ms
	_check(alt, "Ringwechsel: nacheinander, jedes Ziel auf dem anderen Ring")''')
rep('''func _aim(tut: Control, deg: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = OrbitView.polar(tut.view_center_global(), deg, 200.0)
	tut.handle_input(ev)''','''## Zeigt auf Winkel deg im Abstand des Rings (Ring durch Zeigen).
func _aim(tut: Control, deg: float, ring: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	var k: float = OrbitCore.R_OUTER_K if ring == 1 else OrbitCore.R_INNER_K
	ev.position = OrbitView.polar(tut.view_center_global(), deg, tut._view.unit() * k)
	tut.handle_input(ev)''')
rep('''	_aim(tut, n2.angle_deg + 90.0)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "daneben gezielt zaehlt nicht")''','''	_aim(tut, n2.angle_deg + 90.0, n2.ring)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "daneben gezielt zaehlt nicht")
	# Falscher Ring (weit draussen gezeigt, Ziel innen) zaehlt nicht.
	_aim(tut, n2.angle_deg, 1 - n2.ring)
	_key(tut, KEY_Q, true)
	_key(tut, KEY_Q, false)
	_check(int(tut.success) == 1, "falscher Ring zaehlt nicht")''')
rep('''	# Maus links = innen, immer.
	var n3 = tut.notes[2]
	_run_until(tut, func(): return tut.t_ms >= n3.time_ms - FRAME * 0.5)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = OrbitView.polar(tut.view_center_global(), n3.angle_deg, 200.0)''','''	# Beide Maustasten treffen jedes Ziel, der Abstand waehlt den Ring.
	var n3 = tut.notes[2]
	_run_until(tut, func(): return tut.t_ms >= n3.time_ms - FRAME * 0.5)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.position = OrbitView.polar(tut.view_center_global(), n3.angle_deg, tut._view.unit() * OrbitCore.R_INNER_K)''')
rep('"Maus links trifft den inneren Ring"','"Maus rechts trifft das Ziel auf dem gezeigten Ring"')
rep('''	_aim(tut, n.angle_deg)
	var k: int''','''	_aim(tut, n.angle_deg, n.ring)
	var k: int''')
rep('''	_aim(tut, n.angle_deg)
	_key(tut, KEY_Z, true)''','''	_aim(tut, n.angle_deg, n.ring)
	_key(tut, KEY_Z, true)''')
if crlf: s=s.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(s)
