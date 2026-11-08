import re
def rw(p,f):
    s=open(p,encoding='utf-8',newline='').read()
    crlf='\r\n' in s
    s=s.replace('\r\n','\n'); s=f(s)
    if crlf: s=s.replace('\n','\r\n')
    open(p,'w',encoding='utf-8',newline='').write(s)
def conv(s):
    a="	var out := legalize(raw, reds, false)\n	if stars(out) < EASY_STARS:"
    assert a in s
    s=s.replace(a,"	var out := legalize(raw, reds, false)\n	if easy_enabled and stars(out) < EASY_STARS:")
    a="static func finish("
    s=s.replace(a,"## Aus: nur Tests schalten die ruhige Variante fuer leichte Maps ab.\nstatic var easy_enabled := true\n\n\n"+a,1)
    return s
rw('scripts/orbit/orbit_converter.gd',conv)
def tst(s):
    s=s.replace('func _test_std_basic() -> void:\n	print("- osu!standard: Grundformen")\n','func _test_std_basic() -> void:\n	print("- osu!standard: Grundformen")\n	OrbitConverter.easy_enabled = false\n',1)
    s=s.replace('	_ok(OrbitConverter.convert(_bm()).is_empty(), "leere Mania-Map bleibt leer")\n','	_ok(OrbitConverter.convert(_bm()).is_empty(), "leere Mania-Map bleibt leer")\n	OrbitConverter.easy_enabled = true\n',1)
    s=s.replace('func _test_std_streams() -> void:\n	print("- osu!standard: Streams, Stacks, Flow")\n','func _test_std_streams() -> void:\n	print("- osu!standard: Streams, Stacks, Flow")\n	OrbitConverter.easy_enabled = false\n',1)
    s=s.replace('''	alt = true
''','')
    s=s.replace('''	var alt := true
	for i in range(1, ns.size()):
		alt = alt and ns[i].ring != ns[i - 1].ring
	_ok(alt, "Stream wechselt die Ringe (Tasten abwechseln)")
	_std_fair(ns, bm, "Stream")''','''	var same := true
	for i in range(1, ns.size()):
		same = same and ns[i].ring == ns[0].ring
	_ok(same, "Stream bleibt auf einem Ring (Tasten wechseln ab)")
	_std_fair(ns, bm, "Stream")''')
    s=s.replace('''	_ok(float(f4.reversal) > 0.9 and float(f5.reversal) < 0.05, "FLOW: Pendel bzw. Drehung")
''','''	_ok(float(f4.reversal) > 0.9 and float(f5.reversal) < 0.05, "FLOW: Pendel bzw. Drehung")
	OrbitConverter.easy_enabled = true
''',1)
    a='''	var jump := OrbitConverter.convert(bm2)
	_ok(OrbitNote.dist_deg(jump[0].angle_deg, jump[1].angle_deg) > 90.0, "grosser Abstand darf weit springen")'''
    assert a in s
    s=s.replace(a,'''	OrbitConverter.easy_enabled = false
	var jump := OrbitConverter.convert(bm2)
	OrbitConverter.easy_enabled = true
	_ok(OrbitNote.dist_deg(jump[0].angle_deg, jump[1].angle_deg) > 90.0, "grosser Abstand darf weit springen")
	var jump_easy := OrbitConverter.convert(bm2)
	_ok(OrbitNote.dist_deg(jump_easy[0].angle_deg, jump_easy[1].angle_deg) <= OrbitConverter.EASY_FAR_JUMP_DEG + EPS,
			"leichte Map: Sprung hoechstens %d Grad" % OrbitConverter.EASY_FAR_JUMP_DEG)''')
    return s
rw('tests/run_orbit_tests.gd',tst)
