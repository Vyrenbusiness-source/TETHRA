p='tests/run_orbit_play_tests.gd'
s=open(p,encoding='utf-8',newline='').read()
crlf='\r\n' in s
s=s.replace('\r\n','\n')
a='		_check(v.radius_at(ring, -50.0) > v.ring_radius(ring), "nach der Zeit weiter aussen")'
assert a in s
b='''		var past := v.radius_at(ring, -50.0) - v.ring_radius(ring)
		_check(past > 0.0 if ring == 0 else past < 0.0, "nach der Zeit weiter in Laufrichtung (Ring %d)" % ring)
	_check(v.spawn_radius(0) < v.ring_radius(0) and v.spawn_radius(1) > v.ring_radius(1),
		"kein Ziel startet auf einem Trefferring: innen von innen, aussen von aussen")
	_check(v.spawn_radius(0) < v.ring_radius(0) and v.spawn_radius(1) > v.ring_radius(1)
		and v.spawn_radius(0) < v.ring_radius(0), "Anflugwege getrennt")'''
s=s.replace(a,b)
if crlf: s=s.replace('\n','\r\n')
open(p,'w',encoding='utf-8',newline='').write(s)
