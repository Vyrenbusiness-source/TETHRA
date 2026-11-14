class_name MarathonPlan
extends RefCounted

## Marathon (Plan Punkt 14): mehrere Mania-Maps am Stueck auf EINER Zeitachse.
## Reine Logik (testbar, ohne Szene): Auswahl, Reihenfolge, Uebergaenge und die
## zusammengefuegte Beatmap.
##
## Zeitachse: "global" = Marathon-Zeit in ms (die Song-Uhr des Laufs). Jede Map
## ist ein Segment mit eigener Abbildung Songzeit s <-> globale Zeit g:
##   g in [g0, r0]: s = s_in + (g - g0) * rho          (Tempo an Vorgaenger angeglichen)
##   g in [r0, r1]: Rate laeuft linear von rho auf 1   (sanft zurueck aufs Original)
##   g > r1       : s laeuft mit Rate 1
## Uebergang A -> B ("DJ-Mix"): Mitte = erster Takt von A, der mindestens einen
## halben Schlag nach A's letzter Note liegt. Ueberblendung 4 Takte von A um die
## Mitte; B's Taktgrenze liegt auf A's Taktgrenze (Mitte), Tempo von B per Rate
## auf A angeglichen (auch 2:1 / 1:2). Bass-Tausch genau auf der Mitte. Passt das
## Tempo nicht (> MAX_RATE_DEV), wird hart auf dem Takt geschnitten (1 Schlag
## Blende), weiterhin Taktgrenze auf Taktgrenze.
## Noten: alle Noten von A enden vor Mitte - 1/2 Schlag, B's erste Note kommt
## fruehestens Mitte + 1/2 Schlag -> Luecke >= ein Schlag (gap_ms).
##
## Replay: die Zeitachse (timeline) wird im Replay gespeichert und beim Abspielen
## unveraendert benutzt -> exakt nachspielbar, auch wenn sich diese Regeln aendern.

const VERSION := 1
## Gleiche Schwierigkeit: Sterne +- STAR_TOL zum Ziel.
const STAR_TOL := 0.3
const COUNTS: Array[int] = [3, 5, 8]
const MINUTES: Array[int] = [5, 10, 20]
## Zu kurze Maps passen nicht (Rampe + zwei Uebergaenge brauchen Platz).
const MIN_MAP_MS := 45000.0
## Tempo-Angleich hoechstens +-8 % (sonst harter Schnitt auf dem Takt).
const MAX_RATE_DEV := 0.08
const OVERLAP_BARS := 4.0
const RAMP_BARS := 2.0
const INTRO_BARS := 2.0
const OUTRO_BARS := 2.0
## Mindestluecke zwischen letzter Note von A und erster Note von B (zusaetzlich
## zu einem Schlag).
const MIN_GAP_MS := 250.0
## Bass-Absenkung des jeweils "anderen" Decks in dB (EQ-artiger Tausch).
const BASS_CUT_DB := -26.0

const KIND_COUNT := "n"
const KIND_MINUTES := "m"


# --- Laengen-Schluessel (eigene Rangliste je Marathon-Laenge) ---------------------

## "n3", "n5", "n8" (Anzahl Maps) oder "m5", "m10", "m20" (Minuten).
static func length_key(kind: String, value: int) -> String:
	return "%s%d" % [kind, value]


static func parse_length_key(key: String) -> Dictionary:
	if key.length() < 2:
		return {}
	var kind := key.substr(0, 1)
	var v := key.substr(1).to_int()
	if kind == KIND_COUNT and COUNTS.has(v):
		return {"kind": kind, "value": v}
	if kind == KIND_MINUTES and MINUTES.has(v):
		return {"kind": kind, "value": v}
	return {}


static func all_length_keys() -> Array[String]:
	var out: Array[String] = []
	for n in COUNTS:
		out.append(length_key(KIND_COUNT, n))
	for m in MINUTES:
		out.append(length_key(KIND_MINUTES, m))
	return out


# --- Tempo-Passung ---------------------------------------------------------------

## Tempo von B an A angleichen: m = B-Schlaege je A-Schlag (1, 2 oder 1/2),
## rate = Abspieltempo fuer B (B-Schlag in globaler Zeit = A-Schlag / m).
## dev = |ln(rate)|, ok = Angleich innerhalb MAX_RATE_DEV.
static func tempo_match(bpm_a: float, bpm_b: float) -> Dictionary:
	if bpm_a <= 0.0 or bpm_b <= 0.0:
		return {"m": 1.0, "rate": 1.0, "dev": INF, "ok": false}
	var best := {"m": 1.0, "rate": 1.0, "dev": INF, "ok": false}
	for m in [1.0, 2.0, 0.5]:
		var rate: float = m * bpm_a / bpm_b
		var dev := absf(log(rate))
		if dev < float(best.dev) - 1e-9:
			best = {"m": m, "rate": rate, "dev": dev}
	best["ok"] = float(best.dev) <= log(1.0 + MAX_RATE_DEV) + 1e-9
	return best


## Energie einer Map: Noten pro Sekunde (Tonart ist aus osu!-Maps nicht
## bestimmbar, daher BPM + Energie).
static func energy(c: Dictionary) -> float:
	var d := float(c.get("duration_ms", 0.0))
	if d <= 0.0:
		return 0.0
	return float(c.get("notes", 0)) / (d / 1000.0)


# --- Auswahl ---------------------------------------------------------------------

## Kandidaten aus der Bibliothek (MapSet-Metadaten): je Set die 4K-Mania-Diff mit
## den Sternen am naechsten am Ziel. strict = nur innerhalb STAR_TOL.
## Eintrag: {osz, version, osu, stars, bpm, duration_ms, notes, title, artist, bg}
static func candidates_from_sets(sets: Array, target_stars: float, strict: bool = true,
		only_files: Array = []) -> Array:
	var out: Array = []
	for ms in sets:
		var osz := str(ms.osz_path)
		if not only_files.is_empty() and not only_files.has(osz.get_file()):
			continue
		var best: Dictionary = {}
		var best_d := INF
		for d in ms.diffs:
			if int(d.get("mode", 0)) != 3 or int(round(float(d.get("cs", 0.0)))) != 4:
				continue
			var st := float(d.get("stars", -1.0))
			if st <= 0.0:
				continue
			var dist := absf(st - target_stars)
			if dist < best_d:
				best_d = dist
				best = d
		if best.is_empty():
			continue
		if strict and best_d > STAR_TOL + 1e-6:
			continue
		out.append({
			"osz": osz, "version": str(best.get("version", "")),
			"osu": str(best.get("osu_filename", "")), "stars": float(best.get("stars", 0.0)),
			"bpm": float(best.get("bpm", 0.0)), "duration_ms": float(best.get("duration_ms", 0.0)),
			"notes": int(best.get("notes", 0)), "title": str(ms.title), "artist": str(ms.artist),
			"bg": str(ms.background_file),
		})
	return out


## Pool fuer die Auswahl: Sterne im Fenster, Laenge reicht, Tempo bekannt.
static func filter_pool(cands: Array, target_stars: float) -> Array:
	var out: Array = []
	for c in cands:
		if absf(float(c.get("stars", 0.0)) - target_stars) > STAR_TOL + 1e-6:
			continue
		if float(c.get("duration_ms", 0.0)) < MIN_MAP_MS or float(c.get("bpm", 0.0)) <= 0.0:
			continue
		out.append(c)
	return out


## Uebergangs-Kosten A -> B: Tempo-Abweichung (normiert) + Energiesprung.
static func pair_cost(a: Dictionary, b: Dictionary) -> float:
	var tm := tempo_match(float(a.get("bpm", 0.0)), float(b.get("bpm", 0.0)))
	var t := float(tm.dev) / log(1.0 + MAX_RATE_DEV)
	if not bool(tm.ok):
		t = 3.0 + t
	var ea := energy(a)
	var eb := energy(b)
	var e := absf(ea - eb) / maxf(maxf(ea, eb), 0.1)
	return t + 0.6 * e


## Ziel-Energiebogen 0..1 ueber die Position x in [0, 1]: ruhiger Start, Gipfel
## bei ~70 %, leichtes Ausklingen.
static func arc(x: float) -> float:
	if x <= 0.7:
		return 0.15 + 0.85 * sin(PI * 0.5 * x / 0.7)
	return 1.0 - 0.6 * (x - 0.7) / 0.3 * 0.35


## Kosten einer Reihenfolge: Tempo-Weg + Abstand zum Energiebogen (Rang-normiert).
static func order_cost(list: Array) -> float:
	var n := list.size()
	if n <= 1:
		return 0.0
	var energies: Array[float] = []
	for c in list:
		energies.append(energy(c))
	var sorted := energies.duplicate()
	sorted.sort()
	var cost := 0.0
	for i in n:
		if i + 1 < n:
			cost += pair_cost(list[i], list[i + 1])
		var rank := float(sorted.find(energies[i])) / float(n - 1)
		var target := arc(float(i) / float(n - 1))
		cost += 1.2 * (rank - target) * (rank - target)
	return cost


## Reihenfolge fuer gute Uebergaenge: Start nach Energie aufsteigend, dann
## Tausch-Verbesserung bis nichts mehr besser wird (deterministisch).
static func order(list: Array) -> Array:
	var cur := list.duplicate()
	cur.sort_custom(func(a, b):
		var ea := energy(a)
		var eb := energy(b)
		if ea != eb:
			return ea < eb
		return str(a.get("osz", "")) < str(b.get("osz", "")))
	var best := order_cost(cur)
	var improved := true
	var guard := 0
	while improved and guard < 50:
		improved = false
		guard += 1
		for i in cur.size():
			for j in range(i + 1, cur.size()):
				var tmp = cur[i]
				cur[i] = cur[j]
				cur[j] = tmp
				var c := order_cost(cur)
				if c < best - 1e-9:
					best = c
					improved = true
				else:
					cur[j] = cur[i]
					cur[i] = tmp
	return cur


## Auswahl: n Maps (kind "n") oder bis die Dauer erreicht ist (kind "m").
## anchor = bevorzugte Start-Map (osz-Pfad, z. B. die im Browser gewaehlte).
## Liefert die Maps in Spielreihenfolge.
static func pick(pool: Array, length: String, seed: int, anchor: String = "") -> Array:
	var lk := parse_length_key(length)
	if lk.is_empty() or pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rest := pool.duplicate()
	rest.sort_custom(func(a, b): return str(a.osz) + str(a.version) < str(b.osz) + str(b.version))
	var chain: Array = []
	var start := -1
	for i in rest.size():
		if anchor != "" and str(rest[i].osz) == anchor:
			start = i
	if start < 0:
		start = rng.randi_range(0, rest.size() - 1)
	chain.append(rest[start])
	rest.remove_at(start)
	var total := float(chain[0].duration_ms)
	while not rest.is_empty():
		if str(lk.kind) == KIND_COUNT and chain.size() >= int(lk.value):
			break
		if str(lk.kind) == KIND_MINUTES and total >= float(lk.value) * 60000.0:
			break
		var last: Dictionary = chain.back()
		var best_i := 0
		var best_c := INF
		for i in rest.size():
			# Leichte Zufallsstreuung (fester Seed): nicht jedes Mal dieselbe Kette.
			var c := pair_cost(last, rest[i]) + rng.randf() * 0.35
			if c < best_c:
				best_c = c
				best_i = i
		chain.append(rest[best_i])
		total += float(rest[best_i].duration_ms)
		rest.remove_at(best_i)
	return order(chain)


# --- Takt-Raster einer Map -------------------------------------------------------

## Rote Linien einer Map, sortiert: [{t, bl, meter}].
static func reds_of(bm: Beatmap) -> Array:
	var out: Array = []
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			out.append({"t": tp.time, "bl": tp.beat_length, "meter": maxi(tp.meter, 1)})
	out.sort_custom(func(a, b): return float(a.t) < float(b.t))
	if out.is_empty():
		out.append({"t": 0.0, "bl": 500.0, "meter": 4})
	return out


static func red_index(reds: Array, s: float) -> int:
	var idx := 0
	for i in reds.size():
		if float(reds[i].t) <= s + 1e-6:
			idx = i
		else:
			break
	return idx


static func beat_at(reds: Array, s: float) -> float:
	return float(reds[red_index(reds, s)].bl)


static func bar_at(reds: Array, s: float) -> float:
	var r: Dictionary = reds[red_index(reds, s)]
	return float(r.bl) * float(r.meter)


## Letzte Taktgrenze <= s (Raster der roten Linie, die bei s gilt).
static func downbeat_floor(reds: Array, s: float) -> float:
	var r: Dictionary = reds[red_index(reds, s)]
	var bar := float(r.bl) * float(r.meter)
	return float(r.t) + floorf((s - float(r.t)) / bar + 1e-7) * bar


## Erste Taktgrenze >= s (eine neue rote Linie beginnt einen neuen Takt).
static func downbeat_ceil(reds: Array, s: float) -> float:
	var i := red_index(reds, s)
	var r: Dictionary = reds[i]
	var bar := float(r.bl) * float(r.meter)
	var v := float(r.t) + ceilf((s - float(r.t)) / bar - 1e-7) * bar
	if i + 1 < reds.size() and v > float(reds[i + 1].t) and s <= float(reds[i + 1].t):
		v = float(reds[i + 1].t)
	return v


static func first_note_ms(bm: Beatmap) -> float:
	var f := INF
	for o in bm.hit_objects:
		f = minf(f, o.time)
	return 0.0 if f == INF else f


static func last_end_ms(bm: Beatmap) -> float:
	var e := 0.0
	for o in bm.hit_objects:
		e = maxf(e, o.end_time())
	return e


# --- Abbildung Songzeit <-> globale Zeit je Segment --------------------------------

static func song_at(seg: Dictionary, g: float) -> float:
	var rho := float(seg.rho)
	var g0 := float(seg.g0)
	var r0 := float(seg.r0)
	var r1 := float(seg.r1)
	if g <= r0:
		return float(seg.s_in) + (g - g0) * rho
	var s_r0 := float(seg.s_in) + (r0 - g0) * rho
	var dur := r1 - r0
	if g <= r1 and dur > 0.0:
		var d := g - r0
		return s_r0 + d * rho + 0.5 * (1.0 - rho) * d * d / dur
	var s_r1 := s_r0 + maxf(dur, 0.0) * (rho + 1.0) * 0.5
	return s_r1 + (g - maxf(r1, r0))


static func global_at(seg: Dictionary, s: float) -> float:
	var rho := float(seg.rho)
	var g0 := float(seg.g0)
	var r0 := float(seg.r0)
	var r1 := float(seg.r1)
	var s_r0 := float(seg.s_in) + (r0 - g0) * rho
	if s <= s_r0:
		return g0 + (s - float(seg.s_in)) / rho
	var dur := r1 - r0
	var s_r1 := s_r0 + maxf(dur, 0.0) * (rho + 1.0) * 0.5
	if s <= s_r1 and dur > 0.0:
		var ds := s - s_r0
		var k := (1.0 - rho) / (2.0 * dur)
		var d := 2.0 * ds / (rho + sqrt(maxf(rho * rho + 4.0 * k * ds, 0.0)))
		return r0 + d
	return maxf(r1, r0) + (s - s_r1)


## Abspieltempo des Segments bei globaler Zeit g.
static func rate_at(seg: Dictionary, g: float) -> float:
	var rho := float(seg.rho)
	var r0 := float(seg.r0)
	var r1 := float(seg.r1)
	if g <= r0:
		return rho
	if g >= r1 or r1 <= r0:
		return 1.0
	return lerpf(rho, 1.0, (g - r0) / (r1 - r0))


## Lautstaerke (linear 0..1) des Segments bei g: Einblendung (Sinus) und
## Ausblendung (Kosinus) = gleichmaessige Leistung.
static func volume_at(seg: Dictionary, g: float) -> float:
	var v := 1.0
	var fi: Array = seg.get("fade_in", [])
	if fi.size() == 2 and float(fi[1]) > float(fi[0]):
		if g < float(fi[0]):
			return 0.0
		var u := clampf((g - float(fi[0])) / (float(fi[1]) - float(fi[0])), 0.0, 1.0)
		v *= sin(u * PI * 0.5)
	var fo: Array = seg.get("fade_out", [])
	if fo.size() == 2 and float(fo[1]) > float(fo[0]):
		if g >= float(fo[1]):
			return 0.0
		var u2 := clampf((g - float(fo[0])) / (float(fo[1]) - float(fo[0])), 0.0, 1.0)
		v *= cos(u2 * PI * 0.5)
	return v


## Bass-Pegel (dB) des Segments bei g: das hereinkommende Deck spielt ohne Bass
## bis zur Mitte, das gehende verliert ihn dort (Tausch ueber einen Schlag).
static func bass_db_at(seg: Dictionary, g: float) -> float:
	var db := 0.0
	var bi: Array = seg.get("bass_in", [])
	if bi.size() == 2:
		db += BASS_CUT_DB * (1.0 - clampf((g - float(bi[0])) / maxf(float(bi[1]) - float(bi[0]), 1.0), 0.0, 1.0))
	var bo: Array = seg.get("bass_out", [])
	if bo.size() == 2:
		db += BASS_CUT_DB * clampf((g - float(bo[0])) / maxf(float(bo[1]) - float(bo[0]), 1.0), 0.0, 1.0)
	return maxf(db, BASS_CUT_DB)


# --- Zeitachse ---------------------------------------------------------------------

## Baut die Zeitachse fuer die Maps in Spielreihenfolge. audio_ms[i] = Laenge des
## Songs (ms, <= 0 unbekannt). Segment-Dict (alles ms):
##   s_in, g0, rho, r0, r1      Abbildung (siehe Kopf)
##   play_from, play_to         Deck spielt (global)
##   fade_in, fade_out          [von, bis] global (leer = keine)
##   bass_in, bass_out          [von, bis] global (leer = keiner)
##   mid_in                     Uebergangsmitte von vorn (Takt-Raster wechselt hier)
##   note_from                  B-Noten frueher als das fallen weg (Fairness)
##   m, tempo_ok, beat_in       Tempo-Passung zum Vorgaenger, A-Schlag (global)
static func build_timeline(maps: Array, audio_ms: Array = []) -> Array:
	var segs: Array = []
	if maps.is_empty():
		return segs
	var reds_all: Array = []
	for bm in maps:
		reds_all.append(reds_of(bm))
	# Segment 0: Intro gekuerzt auf INTRO_BARS Takte vor der ersten Note.
	var bm0: Beatmap = maps[0]
	var f0 := first_note_ms(bm0)
	var s_in0 := maxf(0.0, downbeat_floor(reds_all[0], f0 - INTRO_BARS * bar_at(reds_all[0], f0)))
	segs.append({
		"s_in": s_in0, "g0": 0.0, "rho": 1.0, "r0": 0.0, "r1": 0.0,
		"play_from": 0.0, "play_to": INF, "fade_in": [0.0, 120.0], "fade_out": [],
		"bass_in": [], "bass_out": [], "mid_in": -INF, "note_from": -INF,
		"m": 1.0, "tempo_ok": true, "beat_in": 0.0,
	})
	for i in range(1, maps.size()):
		var a: Dictionary = segs[i - 1]
		var bm_a: Beatmap = maps[i - 1]
		var bm_b: Beatmap = maps[i]
		var ra: Array = reds_all[i - 1]
		var rb: Array = reds_all[i]
		var last_a := last_end_ms(bm_a)
		var beat_a := beat_at(ra, last_a)
		var bar_a := bar_at(ra, last_a)
		var mid_s := downbeat_ceil(ra, last_a + 0.5 * beat_a)
		var g_mid := global_at(a, mid_s)
		var first_b := first_note_ms(bm_b)
		var beat_b := beat_at(rb, first_b)
		var tm := tempo_match(60000.0 / beat_a, 60000.0 / beat_b)
		var ok := bool(tm.ok)
		var rho: float = float(tm.rate) if ok else 1.0
		# B's Taktgrenze, die auf der Mitte liegt: letzte vor (erste Note - 1/2 A-Schlag).
		var anchor := downbeat_floor(rb, first_b - 0.5 * beat_a * rho)
		var g_x0: float
		var g_x1: float
		var g_r0: float
		if ok:
			g_x0 = global_at(a, mid_s - 0.5 * OVERLAP_BARS * bar_a)
			g_x1 = global_at(a, mid_s + 0.5 * OVERLAP_BARS * bar_a)
			g_r0 = g_x1
		else:
			# Tempo passt nicht: harter Schnitt auf dem Takt (1 Schlag Blende).
			g_x0 = g_mid - beat_a
			g_x1 = g_mid + beat_a
			g_r0 = g_mid + bar_at(rb, anchor) / rho
		var b := {
			"s_in": anchor - (g_mid - g_x0) * rho, "g0": g_x0, "rho": rho,
			"r0": g_r0, "r1": g_r0,
			"play_from": g_x0, "play_to": INF,
			"fade_in": [g_x0, g_mid], "fade_out": [],
			"bass_in": [g_mid - 0.5 * beat_a, g_mid + 0.5 * beat_a], "bass_out": [],
			"mid_in": g_mid, "note_from": -INF,
			"m": float(tm.m), "tempo_ok": ok, "beat_in": beat_a,
		}
		if not ok:
			b["bass_in"] = []
		# Rampe zurueck auf Rate 1: RAMP_BARS Takte von B, muss vor B's eigener
		# Ausblendung fertig sein.
		var last_b := last_end_ms(bm_b)
		var bar_b := bar_at(rb, last_b)
		var out_x0_s := downbeat_ceil(rb, last_b + 0.5 * beat_at(rb, last_b)) \
				- 0.5 * OVERLAP_BARS * bar_b
		if i == maps.size() - 1:
			out_x0_s = last_b
		var s_r0 := song_at(b, g_r0)
		var dur := RAMP_BARS * bar_at(rb, maxf(s_r0, 0.0))
		dur = minf(dur, maxf(2.0 * (out_x0_s - s_r0) / (rho + 1.0), 0.0))
		if absf(rho - 1.0) < 1e-9:
			dur = 0.0
		b["r1"] = g_r0 + dur
		# Fairness: erste Note von B mindestens einen Schlag (und MIN_GAP_MS)
		# nach dem Ende der letzten Note von A.
		var gap := maxf(beat_a, MIN_GAP_MS)
		b["note_from"] = global_at(a, last_a) + gap - 0.001
		a["fade_out"] = [g_mid, g_x1]
		a["bass_out"] = [g_mid - 0.5 * beat_a, g_mid + 0.5 * beat_a] if ok else []
		a["play_to"] = g_x1
		if i - 1 < audio_ms.size() and float(audio_ms[i - 1]) > 0.0:
			a["play_to"] = minf(g_x1, global_at(a, float(audio_ms[i - 1])))
		segs.append(b)
	# Letztes Segment: Outro gekuerzt, sanft ausblenden.
	var li := maps.size() - 1
	var l: Dictionary = segs[li]
	var rl: Array = reds_all[li]
	var last_l := last_end_ms(maps[li])
	var end_s := downbeat_ceil(rl, last_l + 0.5 * beat_at(rl, last_l))
	var g_end0 := global_at(l, end_s)
	var g_end1 := global_at(l, end_s + OUTRO_BARS * bar_at(rl, last_l))
	l["fade_out"] = [g_end0, g_end1]
	l["play_to"] = g_end1
	if li < audio_ms.size() and float(audio_ms[li]) > 0.0:
		l["play_to"] = minf(g_end1, global_at(l, float(audio_ms[li])))
	return segs


## Ende des Marathons (global, ms): letzte Deck-Ausblendung.
static func timeline_end(segs: Array) -> float:
	var e := 0.0
	for s in segs:
		var fo: Array = s.get("fade_out", [])
		if fo.size() == 2:
			e = maxf(e, float(fo[1]))
	return e


# --- Zusammengefuegte Beatmap ------------------------------------------------------

## Fuegt die Maps entlang der Zeitachse zu EINER Mania-Beatmap zusammen. Noten,
## Timing-Punkte (Takt-Raster je Segment, Rampe als Taktschritte), SV je Segment
## (eigene Basis wie lazer, ueber direkte Multiplikatoren) und Kiai.
## note_ranges (Ausgabe) = [[von, bis)] Notenindex je Segment.
static func merge(maps: Array, segs: Array, title: String = "Marathon",
		note_ranges: Array = []) -> Beatmap:
	var out := Beatmap.new()
	out.general = {"Mode": "3", "AudioFilename": "", "AudioLeadIn": "0"}
	var od := 0.0
	var hp := 0.0
	for bm in maps:
		od += (bm as Beatmap).od()
		hp += (bm as Beatmap).hp()
	var n := maxi(maps.size(), 1)
	out.difficulty = {
		"CircleSize": "4", "OverallDifficulty": str(snappedf(od / n, 0.1)),
		"HPDrainRate": str(snappedf(hp / n, 0.1)), "ApproachRate": "5",
	}
	out.metadata = {"Title": title, "Artist": "%d Maps" % maps.size(), "Version": title,
		"Creator": ""}
	if not maps.is_empty():
		out.background_file = (maps[0] as Beatmap).background_file
	note_ranges.clear()
	for i in maps.size():
		var bm: Beatmap = maps[i]
		var seg: Dictionary = segs[i]
		var from := out.hit_objects.size()
		var nf := float(seg.get("note_from", -INF))
		for o in bm.hit_objects:
			if not (o is ManiaNote):
				continue
			var src := o as ManiaNote
			var g := global_at(seg, src.time)
			if g < nf:
				continue
			var nn := ManiaNote.new()
			nn.x = src.x
			nn.y = src.y
			nn.type = src.type
			nn.new_combo = src.new_combo
			nn.hit_sound = src.hit_sound
			nn.column = src.column
			nn.is_hold = src.is_hold
			nn.time = g
			nn.hold_end = global_at(seg, src.hold_end) if src.is_hold else g
			out.hit_objects.append(nn)
		note_ranges.append([from, out.hit_objects.size()])
		_merge_timing(out, bm, segs, i)
	# Deterministisch sortieren (Zeit, rot vor gruen, Einfuegefolge): gleiche
	# Eingabe -> bitgleiche Map (Replay).
	out.timing_points.sort_custom(func(a, b):
		if a.time != b.time:
			return a.time < b.time
		if a.uninherited != b.uninherited:
			return a.uninherited
		return int(a.get_meta(&"mseq", 0)) < int(b.get_meta(&"mseq", 0)))
	return out


static func _tp(time: float, bl: float, meter: int, red: bool, kiai: bool) -> TimingPoint:
	var tp := TimingPoint.new()
	tp.time = time
	tp.beat_length = bl
	tp.meter = meter
	tp.uninherited = red
	tp.kiai = kiai
	tp.effects = 1 if kiai else 0
	return tp


## Zustandstabelle der Original-Map (einmal je Map): nach jedem Timing-Punkt
## {bl, meter, sv, kiai}; Abfrage per Binaersuche (Maps mit tausenden Punkten).
static func _state_table(bm: Beatmap) -> Dictionary:
	var pts := bm.timing_points.duplicate()
	pts.sort_custom(func(a, b):
		if a.time != b.time:
			return a.time < b.time
		return a.uninherited and not b.uninherited)
	var bl := 500.0
	var meter := 4
	for tp in pts:
		if tp.uninherited and tp.beat_length > 0.0:
			bl = tp.beat_length
			meter = maxi(tp.meter, 1)
			break
	var sv := 1.0
	var t := PackedFloat64Array()
	var st: Array = []
	var init := {"bl": bl, "meter": meter, "sv": 1.0, "kiai": false}
	for tp in pts:
		if tp.uninherited:
			if tp.beat_length > 0.0:
				bl = tp.beat_length
				meter = maxi(tp.meter, 1)
			sv = 1.0
		else:
			sv = ScrollMap.green_sv(tp)
		t.append(tp.time)
		st.append({"bl": bl, "meter": meter, "sv": sv, "kiai": tp.kiai or (tp.effects & 1) != 0})
	return {"t": t, "st": st, "init": init}


## Zustand der Original-Map bei Songzeit s: {bl, meter, sv, kiai}.
static func _state_at(table: Dictionary, s: float) -> Dictionary:
	var t: PackedFloat64Array = table.t
	var i := t.bsearch(s + 1e-6, false) - 1
	if i < 0:
		return table.init
	return table.st[i]


static func _merge_timing(out: Beatmap, bm: Beatmap, segs: Array, i: int) -> void:
	var seg: Dictionary = segs[i]
	var reds := reds_of(bm)
	var table := _state_table(bm)
	var base := ScrollMap._most_common_beat_length(_red_tps(bm), last_end_ms(bm))
	var g_from: float = float(seg.mid_in) if i > 0 else -INF
	var g_to: float = float(segs[i + 1].mid_in) if i + 1 < segs.size() else INF
	var s_from: float = song_at(seg, g_from) if i > 0 else -INF
	var s_to: float = song_at(seg, g_to) if g_to != INF else INF
	# Startzustand an der Uebergangsmitte (Taktgrenze von B).
	if i > 0:
		var st := _state_at(table, s_from)
		_emit_red(out, g_from, float(st.bl) / rate_at(seg, g_from), int(st.meter), bool(st.kiai),
				float(st.sv) * base / float(st.bl))
	# Originalpunkte im Bereich.
	for tp in bm.timing_points:
		if i > 0 and tp.time <= s_from + 1e-6:
			continue
		if tp.time >= s_to - 1e-6:
			continue
		var g := global_at(seg, tp.time)
		var st2 := _state_at(table, tp.time)
		if tp.uninherited:
			_emit_red(out, g, tp.beat_length / rate_at(seg, g), maxi(tp.meter, 1), bool(st2.kiai),
					base / tp.beat_length)
		else:
			_add_tp(out, _sv_tp(g, float(st2.sv) * base / float(st2.bl), bool(st2.kiai)))
	# Rampe: je Takt von B eine rote Linie mit der tatsaechlichen Taktlaenge.
	var r0 := float(seg.r0)
	var r1 := float(seg.r1)
	if r1 > r0:
		var s := downbeat_ceil(reds, song_at(seg, r0))
		var guard := 0
		while guard < 256:
			guard += 1
			var g_a := global_at(seg, s)
			if g_a >= r1 or g_a >= g_to:
				break
			var bar := bar_at(reds, s)
			var st3 := _state_at(table, s)
			var g_b := global_at(seg, s + bar)
			if g_a > g_from + 1e-6:
				_emit_red(out, g_a, (g_b - g_a) / float(st3.meter), int(st3.meter), bool(st3.kiai),
						float(st3.sv) * base / float(st3.bl))
			s += bar
		# Ab der naechsten Taktgrenze nach der Rampe wieder Originaltempo.
		var g_c := global_at(seg, s)
		if g_c < g_to:
			var st4 := _state_at(table, s)
			_emit_red(out, g_c, float(st4.bl), int(st4.meter), bool(st4.kiai),
					float(st4.sv) * base / float(st4.bl))
	# Kiai-Intervalle.
	for iv in bm.kiai_intervals:
		var a := clampf(global_at(seg, float(iv.start)), g_from, g_to)
		var b := clampf(global_at(seg, float(iv.end)), g_from, g_to)
		if b > a:
			out.kiai_intervals.append({"start": a, "end": b})


static func _red_tps(bm: Beatmap) -> Array:
	var out: Array = []
	for tp in bm.timing_points:
		if tp.uninherited:
			out.append(tp)
	return out


## Rote Linie + direkter SV-Multiplikator (ScrollMap.SV_META) an derselben Stelle:
## die Scroll-Geschwindigkeit jedes Segments bleibt wie in seiner eigenen Map.
static func _emit_red(out: Beatmap, g: float, bl: float, meter: int, kiai: bool, mult: float) -> void:
	_add_tp(out, _tp(g, bl, meter, true, kiai))
	_add_tp(out, _sv_tp(g, mult, kiai))


static func _add_tp(out: Beatmap, tp: TimingPoint) -> void:
	tp.set_meta(&"mseq", out.timing_points.size())
	out.timing_points.append(tp)


static func _sv_tp(g: float, mult: float, kiai: bool) -> TimingPoint:
	var tp := _tp(g, -100.0 / maxf(mult, 0.01), 4, false, kiai)
	tp.set_meta(ScrollMap.SV_META, mult)
	return tp


# --- Serialisierung (Replay) -------------------------------------------------------

## JSON-taugliche Kopie der Zeitachse (INF als grosse Zahl).
static func timeline_to_json(segs: Array) -> Array:
	var out: Array = []
	for s in segs:
		var d := {}
		for k in s:
			d[k] = _jsonable(s[k])
		out.append(d)
	return out


static func timeline_from_json(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		if not (s is Dictionary):
			continue
		var d := {}
		for k in s:
			d[k] = _unjson(s[k])
		out.append(d)
	return out


const BIG := 1.0e15


static func _jsonable(v: Variant) -> Variant:
	if v is float:
		if is_inf(v):
			return BIG if v > 0.0 else -BIG
		return v
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_jsonable(x))
		return a
	return v


static func _unjson(v: Variant) -> Variant:
	if v is float or v is int:
		var f := float(v)
		if f >= BIG:
			return INF
		if f <= -BIG:
			return -INF
		return f
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_unjson(x))
		return a
	return v
