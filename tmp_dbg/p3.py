def rw(p,f):
    s=open(p,encoding='utf-8',newline='').read()
    crlf='\r\n' in s
    s=s.replace('\r\n','\n'); s=f(s)
    if crlf: s=s.replace('\n','\r\n')
    open(p,'w',encoding='utf-8',newline='').write(s)
def tst(s):
    a='''			if e[1] == 0:
				if held[n.ring] >= 0:
					c.key_up(n.ring, te)
				held[n.ring] = e[2]
				c.key_down(n.ring, te, n.angle_at(te) + float(plan[e[2]][1]), _rho(n.ring))
			elif held[n.ring] == e[2]:
				c.key_up(n.ring, te)
				held[n.ring] = -1'''
    b='''			if e[1] == 0:
				# Zwei Tasten: die freie nehmen (Tap im Bogen = andere Taste),
				# sonst die aelteste loslassen.
				var key := 0 if held[0] < 0 else (1 if held[1] < 0 else 0)
				if held[key] >= 0:
					c.key_up(key, te)
				held[key] = e[2]
				c.key_down(key, te, n.angle_at(te) + float(plan[e[2]][1]), _rho(n.ring))
			else:
				for key in 2:
					if held[key] == e[2]:
						c.key_up(key, te)
						held[key] = -1'''
    assert a in s
    return s.replace(a,b)
rw('tests/run_orbit_tests.gd',tst)
