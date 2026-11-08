p='scripts/orbit/orbit_core.gd'
s=open(p,encoding='utf-8',newline='').read()
nl='\r\n' if '\r\n' in s else '\n'
s=s.replace('\r\n','\n')
a="	if notes[idx].is_arc:\n		_active_arc[ring] = idx\n"
b="""	if notes[idx].is_arc:
		# Kopf eines neuen Bogens kurz vor dem Ende des alten: der alte ist geschafft.
		var old: int = _active_arc[ring]
		if old >= 0:
			_finish_arc(ring, t_ms >= notes[old].end_ms - w50 * 1.5, "NEXT")
		_active_arc[ring] = idx
"""
assert a in s
s=s.replace(a,b).replace('\n',nl)
open(p,'w',encoding='utf-8',newline='').write(s)
