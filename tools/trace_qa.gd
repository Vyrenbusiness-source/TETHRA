extends SceneTree

## Trace-QA ueber alle lokalen Mania-4K-Maps (Vorbild: tests/run_orbit_qa_tests.gd).
## Misst je Map: Segmentlaengen (px, Standardtempo), Pfeil-Ueberdeckung, Selbstueberschneidung
## des Fadens im sichtbaren Vorlauf, Haarnadel-Dichte, Kamera-Spruenge; ein Bot mit
## menschlicher Reaktionszeit/Streuung misst Acc je Sterne-Band.
## Messung in Stuecken (Headless-Zeitlimit), Ergebnis als TSV, dann Bericht:
##   Godot --headless --audio-driver Dummy --path . --script res://tools/trace_qa.gd -- --chunk=0/6 --tsv=<datei>
##   ... --script res://tools/trace_qa.gd -- --report --tsv=<datei> --out=res://docs/modes/trace_qa.md
## Optionen: --maps-dir=<Ordner> (MapLibrary), --label=<Text im Bericht>.

const BANDS := [[0.0, 2.0], [2.0, 3.0], [3.0, 4.0], [4.0, 5.0], [5.0, 6.0], [6.0, 99.0]]
const COLS := ["label", "stars", "n", "nps", "knots", "len_s", "seg_min", "seg_p5", "seg_med",
	"overlap_pairs", "overlap_notes", "cross_events", "cross_arrows", "hair", "hair_per10s",
	"hair_runs", "cam_max", "cam_jumps", "acc"]


func _initialize() -> void:
	var o := _opts()
	if o.has("report"):
		_report(o)
	else:
		_measure(o)
	quit(0)


func _opts() -> Dictionary:
	var o := {}
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			o[kv[0]] = kv[1] if kv.size() > 1 else true
	return o


static func percentile(v: Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return float(s[clampi(int(q * float(s.size() - 1)), 0, s.size() - 1)])


## Bot mit Reaktionszeit/Streuung. Rueckgabe: Acc 0..1 (Mania-Gewichte).
static func bot_acc(p: TracePath, bm: Beatmap, overlapped: Dictionary, seed: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var od := bm.od()
	var w300 := 64.0 - 3.0 * od
	var w200 := 97.0 - 3.0 * od
	var w100 := 127.0 - 3.0 * od
	var w50 := 151.0 - 3.0 * od
	var wmiss := 188.0 - 3.0 * od
	var pts := 0.0
	var n := p.knots.size()
	var total := 0
	var a := 0
	var b := 0
	for j in n:
		var kn := p.knots[j]
		# Dichte im Umfeld (Knoten im Fenster +-0,5 s).
		while p.knots[a].t < kn.t - 500.0:
			a += 1
		while b < n - 1 and p.knots[b + 1].t - kn.t < 500.0:
			b += 1
		var dens := float(b - a + 1)
		var sigma := 24.0 + 2.2 * maxf(dens - 6.0, 0.0)
		var miss_p := 0.004
		if overlapped.has(j):
			sigma += 22.0
			miss_p += 0.14
		if kn.hairpin:
			sigma += 6.0
		var notes := kn.notes.size()
		total += notes
		for i in notes:
			var e := absf(clampf(rng.randfn(0.0, sigma), -3.0 * sigma, 3.0 * sigma))
			if rng.randf() < miss_p or e > wmiss:
				continue
			if e <= w300:
				pts += 1.0
			elif e <= w200:
				pts += 2.0 / 3.0
			elif e <= w100:
				pts += 1.0 / 3.0
			elif e <= w50:
				pts += 1.0 / 6.0
	return pts / maxf(float(total), 1.0)


static func _cell(v: Vector2) -> Vector2i:
	return Vector2i(int(floorf(v.x / 16.0)), int(floorf(v.y / 16.0)))


## Messwerte einer Map als Dictionary (Schluessel = COLS ohne label/stars/n/nps).
static func measure(p: TracePath, bm: Beatmap, seed: int) -> Dictionary:
	var kn := p.knots
	var r := {"knots": kn.size(), "len_s": (kn[kn.size() - 1].t - kn[0].t) / 1000.0}
	var segs: Array = []
	for j in range(1, kn.size()):
		segs.append(kn[j].pos.distance_to(kn[j - 1].pos))
	r["seg_min"] = percentile(segs, 0.0)
	r["seg_p5"] = percentile(segs, 0.05)
	r["seg_med"] = percentile(segs, 0.5)
	var pairs := p.overlap_pairs()
	var ov := {}
	for pr in pairs:
		ov[pr[0]] = true
		ov[pr[1]] = true
	r["overlap_pairs"] = pairs.size()
	var on := 0
	for j in ov:
		on += kn[j].notes.size()
	r["overlap_notes"] = on
	# Selbstueberschneidung: Faden-Stuetzpunkte (10 px) mit fremdem Faden < 7 px im Vorlauf.
	var s0: float = kn[0].s - 40.0
	var s1: float = kn[kn.size() - 1].s + 40.0
	var pts := p.sample(s0, s1, 10.0)
	var stp := (s1 - s0) / maxf(float(pts.size() - 1), 1.0)
	var grid := {}
	for i in pts.size():
		var c := _cell(pts[i])
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		grid[c].append(i)
	var look_px := TracePath.LOOK_S * p.speed
	var hit := PackedByteArray()
	hit.resize(pts.size())
	for i in pts.size():
		var c := _cell(pts[i])
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cc := Vector2i(c.x + dx, c.y + dy)
				if not grid.has(cc):
					continue
				for k in grid[cc]:
					var ds := absf(float(k - i)) * stp
					if ds > 70.0 and ds < look_px and pts[i].distance_to(pts[k]) < 7.0:
						hit[i] = 1
	var ev := 0
	for i in pts.size():
		if hit[i] == 1 and (i == 0 or hit[i - 1] == 0):
			ev += 1
	r["cross_events"] = ev
	# Pfeile auf fremdem Faden: Knoten mit Faden (andere Stelle, Abstand <= Vorlauf) < 12 px.
	var ca := 0
	for j in kn.size():
		var c := _cell(kn[j].pos)
		var bad := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cc := Vector2i(c.x + dx, c.y + dy)
				if bad or not grid.has(cc):
					continue
				for k in grid[cc]:
					var d := absf(s0 + float(k) * stp - kn[j].s)
					if d > 70.0 and d < look_px and kn[j].pos.distance_to(pts[k]) < 12.0:
						bad = true
						break
		if bad:
			ca += 1
	r["cross_arrows"] = ca
	var h := p.hairpin_count()
	var runs := 0
	for j in range(1, kn.size()):
		if kn[j].hairpin and kn[j - 1].hairpin:
			runs += 1
	r["hair"] = h
	r["hair_per10s"] = float(h) / maxf(r["len_s"], 1.0) * 10.0
	r["hair_runs"] = runs
	# Kamera: Schritt je Bild (16,7 ms), Abtastung alle 50 ms.
	var cmax := 0.0
	var cj := 0
	var t: float = kn[0].t
	var tend: float = kn[kn.size() - 1].t
	while t < tend:
		var d := p.camera(t + 16.7).distance_to(p.camera(t))
		cmax = maxf(cmax, d)
		if d > 40.0:
			cj += 1
		t += 50.0
	r["cam_max"] = cmax
	r["cam_jumps"] = cj
	r["acc"] = bot_acc(p, bm, ov, seed)
	return r


func _measure(o: Dictionary) -> void:
	var dir := MapLibrary.default_maps_dir()
	var da := DirAccess.open(dir)
	if da == null:
		print("kein maps-Ordner: ", dir)
		return
	var files := Array(da.get_files())
	files.sort()
	var ci := 0
	var cn := 1
	if o.has("chunk"):
		var pr := str(o["chunk"]).split("/")
		ci = int(pr[0])
		cn = maxi(int(pr[1]), 1)
	var tsv := str(o.get("tsv", "user://trace_qa.tsv"))
	var out := FileAccess.open(tsv, FileAccess.READ_WRITE if FileAccess.file_exists(tsv) else FileAccess.WRITE)
	out.seek_end()
	var seed := 100
	var fi := -1
	var rows := 0
	for f in files:
		if not str(f).to_lower().ends_with(".osz"):
			continue
		fi += 1
		if fi % cn != ci:
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		var stars := {}
		var stars_done := false
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if bm.hit_objects.size() < 30 or not bm.is_mania() or bm.column_count() != 4:
				continue
			if not stars_done:
				stars = StarService.stars_for(dir.path_join(f))
				stars_done = true
			var st := -1.0
			if stars.has(d.osu_filename):
				st = float(stars[d.osu_filename].get("stars", -1.0))
			seed += 1
			var p := TracePath.from_beatmap(bm)
			if p.knots.size() < 20:
				continue
			var m := measure(p, bm, seed)
			var span: float = (bm.hit_objects[bm.hit_objects.size() - 1].time - bm.hit_objects[0].time) / 1000.0
			m["label"] = ("%s [%s]" % [str(f).get_basename().left(26), bm.version_name().left(20)]).replace("\t", " ")
			m["stars"] = st
			m["n"] = bm.hit_objects.size()
			m["nps"] = float(bm.hit_objects.size()) / maxf(span, 1.0)
			var line := PackedStringArray()
			for c in COLS:
				line.append(("%.4f" % m[c]) if m[c] is float else str(m[c]))
			out.store_line("\t".join(line))
			rows += 1
	out.close()
	print("chunk %d/%d: %d Maps" % [ci, cn, rows])


func _report(o: Dictionary) -> void:
	var tsv := str(o.get("tsv", "user://trace_qa.tsv"))
	var f := FileAccess.open(tsv, FileAccess.READ)
	if f == null:
		print("keine TSV: ", tsv)
		return
	var rows: Array = []
	while not f.eof_reached():
		var ln := f.get_line()
		if ln == "":
			continue
		var c := ln.split("\t")
		var r := {}
		for i in COLS.size():
			r[COLS[i]] = c[i] if i == 0 else float(c[i])
		rows.append(r)
	var md := "# Trace-QA (Lesbarkeit, alle lokalen Mania-4K-Maps)\n\n"
	md += "%s\n\n" % str(o.get("label", ""))
	md += "Messung: `tools/trace_qa.gd` (Standard-Fadentempo %d px/s, Vorlauf %.1f s, Pfeil-Halbmesser %d px, Akkord %d px). " % [int(TracePath.BASE_SPEED), TracePath.LOOK_S, int(TracePath.ARROW_R), int(TracePath.CHORD_R)]
	md += "%d Maps.\n\n" % rows.size()
	var tp := 0
	var tn := 0
	var tc := 0
	var ta := 0
	var mp := 0
	var smin := INF
	var cmax := 0.0
	var cj := 0
	for r in rows:
		tp += int(r.overlap_pairs)
		tn += int(r.overlap_notes)
		tc += int(r.cross_events)
		ta += int(r.cross_arrows)
		mp += 1 if r.overlap_pairs > 0 else 0
		smin = minf(smin, r.seg_min)
		cmax = maxf(cmax, r.cam_max)
		cj += int(r.cam_jumps)
	md += "## Gesamt\n\n"
	md += "- Maps mit ueberdeckten Pfeilen: **%d von %d** (%d Paare, %d Noten betroffen)\n" % [mp, rows.size(), tp, tn]
	md += "- kleinster Knotenabstand ueberhaupt: %.1f px\n" % smin
	md += "- Fadenkreuzungen im Vorlauf (Ereignisse): %d, Pfeile auf fremdem Faden: %d\n" % [tc, ta]
	md += "- Kamera: groesster Schritt %.1f px je Bild, Spruenge > 40 px/Bild: %d\n\n" % [cmax, cj]
	md += "## Je Sterne-Band\n\n| Sterne | Maps | Bot-Acc Mittel | Acc schlechteste | Segment p5 (px) | Ueberdeckt (Paare/Map) | Kreuzungen/Map | Haarnadeln/10 s | Kamera max (px/Bild) |\n|---|---|---|---|---|---|---|---|---|\n"
	for b in BANDS:
		var sel: Array = []
		for r in rows:
			if r.stars >= b[0] and r.stars < b[1]:
				sel.append(r)
		if sel.is_empty():
			continue
		var acc := 0.0
		var accmin := 1.0
		var p5 := 0.0
		var op := 0.0
		var cr := 0.0
		var hp := 0.0
		var cm := 0.0
		for r in sel:
			acc += r.acc
			accmin = minf(accmin, r.acc)
			p5 += r.seg_p5
			op += r.overlap_pairs
			cr += r.cross_events
			hp += r.hair_per10s
			cm = maxf(cm, r.cam_max)
		var k := float(sel.size())
		var lab := "%.0f-%.0f" % [b[0], b[1]] if b[1] < 99.0 else "%.0f+" % b[0]
		md += "| %s | %d | %.2f %% | %.2f %% | %.1f | %.1f | %.1f | %.2f | %.1f |\n" % [lab, sel.size(), acc / k * 100.0, accmin * 100.0, p5 / k, op / k, cr / k, hp / k, cm]
	var unk := 0
	for r in rows:
		if r.stars < 0.0:
			unk += 1
	if unk > 0:
		md += "\n%d Maps ohne Sternewert (nicht in den Baendern, aber in Gesamt).\n" % unk
	var worst := rows.duplicate()
	worst.sort_custom(func(a, b): return a.overlap_pairs > b.overlap_pairs if a.overlap_pairs != b.overlap_pairs else a.cross_arrows > b.cross_arrows)
	md += "\n## Schlechteste 12 Maps (Ueberdeckung, dann Pfeil auf Faden)\n\n| Map | Sterne | NPS | Paare | Noten | Faden-Kreuz | Pfeil auf Faden | Haarn./10 s | Segment min/p5/med | Acc |\n|---|---|---|---|---|---|---|---|---|---|\n"
	for i in mini(12, worst.size()):
		var r: Dictionary = worst[i]
		md += "| %s | %.2f | %.1f | %d | %d | %d | %d | %.1f | %.0f/%.0f/%.0f | %.2f %% |\n" % [r.label, r.stars, r.nps, r.overlap_pairs, r.overlap_notes, r.cross_events, r.cross_arrows, r.hair_per10s, r.seg_min, r.seg_p5, r.seg_med, r.acc * 100.0]
	md += "\nBot: Streuung 24 ms + 2,2 ms je Knoten/0,5 s ueber 6; ueberdeckte Pfeile +22 ms und 14 % Fehlleser; Haarnadel +6 ms; Acc mit Mania-Gewichten (OD der Map).\n"
	var outp := str(o.get("out", "res://docs/modes/trace_qa.md"))
	var w := FileAccess.open(outp, FileAccess.WRITE)
	w.store_string(md)
	w.close()
	print(md)
