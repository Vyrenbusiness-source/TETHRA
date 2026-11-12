class_name TraceStars
extends RefCounted

## Trace-Sterne: Schwierigkeit des LESENS und Steuerns, nicht der Mania-Dichte.
## Statisch und deterministisch, rechnet auf dem TracePath (Knoten = Akkord-Gruppen).
## Je Knoten ein Strain-Wert aus: Tempo (1/Abstand), Richtungswechsel (90 Grad,
## 180 Grad = Haarnadel), Akkord-Art (Diagonale, Kreuz, Stern), ueberlappende Holds
## und Lesestress (kurzes Segment mit Knick). Strain zerfaellt mit der Zeit; die
## Spitzen je Abschnitt werden gewichtet summiert (wie osu!), dazu Stamina.
## Kalibriert ueber die lokalen 4K-Maps (docs/modes/trace_stars.md).

const SECTION_MS := 400.0
const DECAY_PER_S := 0.35        ## Strain-Rest nach 1 s
const PEAK_WEIGHT := 0.9         ## Gewicht-Abfall der sortierten Spitzen
const STAMINA_WIN_MS := 10000.0
const STAMINA_W := 0.35
const SCALE := 0.435              ## Roh -> Sterne (Kalibrierung)
const POW := 0.65
const VERSION := 1               ## Cache-Version: bei Formelaenderung erhoehen


static func from_beatmap(bm: Beatmap) -> float:
	if bm == null or bm.hit_objects.is_empty():
		return 0.0
	return from_path(TracePath.from_beatmap(bm))


static func from_notes(times: PackedFloat64Array, cols: PackedInt32Array,
		ends: PackedFloat64Array) -> float:
	return from_path(TracePath.build(times, cols, ends))


static func from_path(p: TracePath) -> float:
	var n := p.knots.size()
	if n < 2:
		return 0.0
	var peaks := {}                  # Abschnitt -> max Strain
	var strain := 0.0
	var prev_t := p.knots[0].t
	var win_notes := {}              # Stamina: Noten je 10-s-Fenster
	var last_t := p.knots[n - 1].t
	for j in n:
		var k: TracePath.Knot = p.knots[j]
		var dt := maxf(k.t - prev_t, 1.0) if j > 0 else 1000.0
		strain *= pow(DECAY_PER_S, dt / 1000.0)
		strain += _knot_value(p, j, dt)
		prev_t = k.t
		var sec := int(k.t / SECTION_MS)
		if strain > float(peaks.get(sec, 0.0)):
			peaks[sec] = strain
		var win := int(k.t / STAMINA_WIN_MS)
		win_notes[win] = int(win_notes.get(win, 0)) + k.notes.size()
	var list: Array = peaks.values()
	list.sort()
	list.reverse()
	var sum := 0.0
	var w := 1.0
	for v in list:
		sum += float(v) * w
		w *= PEAK_WEIGHT
	var peak_part := sum * (1.0 - PEAK_WEIGHT)
	# Stamina: Mittel der dichtesten Fenster (Noten/s) ueber die Map.
	var dens: Array = win_notes.values()
	dens.sort()
	dens.reverse()
	var top := mini(dens.size(), 6)
	var d := 0.0
	for i in top:
		d += float(dens[i])
	var stamina := (d / maxf(top, 1)) / (STAMINA_WIN_MS / 1000.0)
	var length_f := clampf((last_t - p.knots[0].t) / 120000.0, 0.25, 1.0)
	var raw := peak_part + STAMINA_W * stamina * (0.7 + 0.3 * length_f)
	return SCALE * pow(maxf(raw, 0.0), POW)


static func _knot_value(p: TracePath, j: int, dt: float) -> float:
	var k: TracePath.Knot = p.knots[j]
	var speed := clampf(250.0 / dt, 0.0, 3.0)       # 250 ms = 1, 83 ms = 3
	var v := 0.25 * speed
	var turn := absf(k.turn)
	var turn_c := 0.0
	if k.hairpin:
		turn_c = 1.6
	elif turn > 0.2:
		turn_c = 0.6 * clampf(turn / (PI * 0.5), 0.0, 1.5)
	# Wendungen kosten mehr, je schneller sie kommen.
	v += turn_c * (0.4 + 0.6 * speed)
	match k.kind:
		TracePath.Kind.DIAG:
			v += 0.25 * (0.5 + speed)
		TracePath.Kind.CROSS:
			v += 0.55 * (0.5 + speed)
		TracePath.Kind.STAR:
			v += 0.8 * (0.5 + speed)
	# Lesestress: kurzes Segment mit Knick.
	if turn > 0.2 and dt < 160.0:
		v += 0.5 * (160.0 - dt) / 160.0
	# Holds ueberlappen: je aktiver Hold am Knoten.
	var active := 0
	for b in range(maxi(j - 6, 0), j):
		for h in p.knots[b].holds:
			if float(h.t_end) > k.t:
				active += 1
	if active > 0:
		v += 0.25 * minf(float(active), 3.0) * (0.5 + 0.5 * turn_c)
	return v
