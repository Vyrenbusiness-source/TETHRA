class_name AmChart
extends RefCounted

## OMEN Auto-Mapper 4K: Notensetzer (docs/automap/spec.md, Abschnitt AmChart).
##
## Eingang: features (AmFeatures.analyze) und grid (AmGrid.track). Ausgang: Noten je Profil,
## exakt auf dem Gitter. Die Muster kommen aus data/automap/patterns.json (Statistik der
## Menschen-Maps je Sterne-Band, gelernt von tests/run_am_chart_tests.gd --measure --learn).
## Reines GDScript, kein Szenenzugriff, thread-faehig (nur lesender Zugriff auf den Muster-Cache).
##
## Das Gitter wird hier selbst ausgewertet (gleiche Regeln wie AmGrid.snap/beat_pos), damit der
## Setzer ohne das parallel entstehende Modul AmGrid laeuft.

const PROFILES := ["Easy", "Normal", "Hard", "Insane", "Expert"]
const PATTERNS_PATH := "res://data/automap/patterns.json"

## Stellgroessen; params ueberschreibt einzelne Schluessel (Abschnitt "chart" in params.json).
const DEFAULTS := {
	"osu_lead_ms": 23.0,          # Ereignisse sind akustisch, das Gitter liegt in osu-Konvention
	"star_bands": {"Easy": [1.3, 1.9], "Normal": [2.1, 2.8], "Hard": [3.0, 3.8],
			"Insane": [4.0, 4.8], "Expert": [5.0, 6.0]},
	"star_scale": 0.0,            # 0 = aus patterns.json (star_fit), sonst 1
	"star_offset": 0.0,
	"star_tol": 0.12,             # Abbruch der Nachregelung: Abstand zur Bandmitte
	"tune_iters": 7,
	"seed": 0,
	"patterns": {},               # Tests: Mustertabellen direkt uebergeben
	"w_metric": 1.0,              # Gewicht der Taktposition in der Auswahl
	"w_strength": 1.0,            # Gewicht der Anschlagstaerke
	"support_drum_weight": 0.7,   # Kick/Snare, wenn das Schlagzeug nicht fuehrt
	"support_weight": 0.45,       # uebrige Ebenen, wenn sie nicht fuehren
	"dens_gain": 0.4,             # Dichte folgt Intensitaet (mal gelerntes Kiai-Verhaeltnis)
	"snap_quarter_bias_ms": 6.0,  # 1/4 gewinnt gegen 1/8 bei fast gleichem Abstand
	"hold_share_scale": 1.0,
	"motif_min_rows": 3,          # ab so vielen Zeilen je Takt gilt ein Takt als Motiv
	"pitch_weight": 2.0,          # Tonhoehe -> Spaltenrichtung
	"pitch_step": 0.04,
	"role_weight": 1.5,           # feste Spalten fuer Kick/Snare je Abschnitt
	"balance_weight": 6.0,
	"ngram_weight": 0.95,          # Anteil des 4er-Modells (naechste Zeile nach den 3 vorigen, Menschen-Maps)
	"sharpness": 2.0,
	"chord_boost_max": 0.15,      # hoechstens so viel mehr Akkorde, wenn die Sterne nicht reichen
	"fresh_weight": 1.0,          # Spalte nicht in der vorvorigen/drittletzten Zeile (Menschen laufen ueber alle Spalten)
	"top_boost": 20.0,             # Zusatzgewicht fuer die 60 haeufigsten 4er-Muster der Menschen im Band
	"sus_bonus": 0.3,             # gehaltene Toene in der Auswahl bevorzugen (Holds wie bei den Menschen)
	"figure_weight": 1.0,         # Treppe/Triller/Roll aus Tonhoehe und Hi-Hat-Laeufen
	"jack_weight": 2.0,           # Jacks auf den Anteil der Menschen-Maps des Bands halten
	"easy_hold_max_beats": 2.0,   # Easy/Normal: Hold ohne Ueberlappung hoechstens so lang, Zeilen darin entfallen
}

## Spielbarkeits-Regeln je Profil (Spec-Tabelle). Einheiten: 1/24 Schlag (24 = 1/1, 12 = 1/2,
## 6 = 1/4, 3 = 1/8, 4 = 1/6). chord_unit/c3_unit: Akkorde mit 2 bzw. 3 Noten nur auf dieser Teilung.
## Seit 2026-11-13 gelten die Statistiken der Menschen-Maps je Sterne-Band als Regel (patterns.json,
## 238 Sets / 989 4K-Diffs): *_share = Wert der Menschen (Ziel des Setzers), *_max = Obergrenze fuer
## lint = Menschen-Wert x 1,25. rare = seltene Teilung (Zeilen nur auf dieser Teilung), burst = hoechstens
## so viele Abstaende <= burst_gap in Folge (Normal: 1/4-Lauf bis 7 Zeilen = 90. Perzentil der Menschen).
const RULES := {
	"Easy": {"units": [24], "rare": 12, "rare_share": 0.269, "rare_max": 0.336,
			"chord": 2, "chord_unit": 24, "c3_unit": 24, "chord_max": 0.229, "c3_max": 0.0, "jack": 0,
			"gap": 1.0, "bal_lo": 0.40, "bal_hi": 0.60, "hold_unit": 12, "overlap": 1, "ovl_max": 0.0375,
			"hold_min": 0.5, "burst": 0, "burst_gap": 0.0, "burst_keep": 24},
	"Normal": {"units": [12], "rare": 6, "rare_share": 0.127, "rare_max": 0.159,
			"chord": 3, "chord_unit": 24, "c3_unit": 24, "chord_max": 0.411, "c3_max": 0.0199, "jack": 0,
			"gap": 0.5, "bal_lo": 0.40, "bal_hi": 0.60, "hold_unit": 6, "overlap": 1, "ovl_max": 0.086,
			"hold_min": 0.5, "burst": 6, "burst_gap": 0.27, "burst_keep": 12},
	"Hard": {"units": [6], "rare": 3, "rare_share": 0.081, "rare_max": 0.101,
			"chord": 3, "chord_unit": 6, "c3_unit": 24, "chord_max": 0.462, "c3_max": 0.065, "jack": 2,
			"gap": 0.25, "bal_lo": 0.42, "bal_hi": 0.58, "hold_unit": 6, "overlap": 2, "ovl_max": 1.0,
			"hold_min": 0.25, "burst": 2, "burst_gap": 0.13, "burst_keep": 6},
	"Insane": {"units": [6, 3], "rare": 0, "rare_share": 0.0, "rare_max": 0.0,
			"chord": 3, "chord_unit": 6, "c3_unit": 24, "chord_max": 0.495, "c3_max": 0.113, "jack": 3,
			"gap": 0.25, "bal_lo": 0.42, "bal_hi": 0.58, "hold_unit": 6, "overlap": 2, "ovl_max": 1.0,
			"hold_min": 0.25, "burst": 8, "burst_gap": 0.13, "burst_keep": 6},
	"Expert": {"units": [6, 3, 4], "rare": 0, "rare_share": 0.0, "rare_max": 0.0,
			"chord": 3, "chord_unit": 1, "c3_unit": 6, "chord_max": 0.513, "c3_max": 0.132, "jack": 4,
			"gap": 0.125, "bal_lo": 0.42, "bal_hi": 0.58, "hold_unit": 3, "overlap": 2, "ovl_max": 1.0,
			"hold_min": 0.25, "burst": 0, "burst_gap": 0.0, "burst_keep": 6},
}
const BALANCE_MIN_NOTES := 20     # lint: Hand-Balance erst ab so vielen Noten

const EPS := 0.01
const POP := [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]
const MIRROR := [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]
const NLR := [0, 1, 1, 2, -1, 0, 0, 1, -1, 0, 0, 1, -2, -1, -1, 0]
const MC := [1.5, 0.0, 1.0, 0.5, 2.0, 1.0, 1.5, 1.0, 3.0, 1.5, 2.0, 1.3333, 2.5, 1.6667, 2.0, 1.5]
const MASKS_BY_SIZE := [[], [1, 2, 4, 8], [3, 5, 9, 6, 10, 12], [7, 11, 13, 14], [15]]
const ROLES := [[1, 2], [0, 3], [2, 1], [3, 0]]   # [Kick-Spalte, Snare-Spalte] je Abschnitt
const KIND_BITS := {"kick": 1, "snare": 2, "hat": 4, "bass": 8, "tonal": 16, "vocal": 32, "other": 64}
const KIND_LAYER := {"kick": "drums", "snare": "drums", "hat": "drums", "bass": "bass",
		"tonal": "tonal", "vocal": "vocal", "other": ""}

# Zustand des Setzers (flaches Array, billig zu kopieren)
const S_LAST := 0      # 0..3 Beginn der letzten Note je Spalte (Schlaege)
const S_RUN := 4       # 4..7 Jack-Laenge je Spalte
const S_HEND := 8      # 8..11 Hold-Ende je Spalte (Schlaege)
const S_L := 12
const S_R := 13
const S_PM := 14       # vorige Zeile (Maske)
const S_PBP := 15
const S_PP := 16       # vorige Tonhoehe
const S_PC := 17       # mittlere Spalte der vorigen Zeile
const S_HIST := 18     # letzte 8 Masken (je 4 Bit)
const S_MAXJ := 19
const S_OVL := 20
const S_BLOCK := 21    # Easy/Normal: keine Zeile vor diesem Schlag (laufender Hold ohne Ueberlappung)
const S_PP2 := 22      # Tonhoehe vor zwei Zeilen
const S_DIR := 23      # letzte Laufrichtung (+1 rechts, -1 links)
const S_PK := 24       # Instrumente der vorigen Zeile
const S_JN := 25       # Noten in Jacks bisher
const S_ROWS := 26     # gesetzte Zeilen
const S_CH := 27       # davon Akkorde
const S_C3 := 28       # davon 3er/4er-Akkorde
const S_RARE := 29     # davon auf der seltenen Teilung

static var _pat_cache: Dictionary = {}
static var _pat_mutex := Mutex.new()


# ---------------------------------------------------------------------------
# Oeffentlich
# ---------------------------------------------------------------------------

## Noten eines Profils. Leichtere Profile sind eine Auswahl der schwereren; darum wird die
## Kette von Expert bis zum gewuenschten Profil gerechnet (alle auf einmal: build_all).
static func build(features: Dictionary, grid: Dictionary, profile: String, params: Dictionary = {}) -> Dictionary:
	if not PROFILES.has(profile):
		return _fail(profile, "unbekanntes Profil: %s" % profile)
	var all := build_all(features, grid, params, profile)
	return all[profile]


## Alle Profile von Expert bis `upto` in einem Durchgang (Ergaenzung zur Spec, spart Rechenzeit).
static func build_all(features: Dictionary, grid: Dictionary, params: Dictionary = {}, upto: String = "Easy") -> Dictionary:
	var out := {}
	var P := _params(params)
	var G := _grid(grid)
	var err := ""
	var C := {}
	if int(G["n"]) == 0:
		err = "grid ohne gueltige Segmente"
	elif not (features.get("events") is Array):
		err = "features ohne events"
	else:
		C = _prep(features, G, P)
		if int(C["n"]) == 0:
			err = "keine Ereignisse"
	var stop := maxi(PROFILES.find(upto), 0)
	if err != "":
		for p: String in PROFILES:
			out[p] = _fail(p, err)
		return out
	var pats := _patterns(P)
	var parent := {}
	for pi in range(PROFILES.size() - 1, stop - 1, -1):
		var prof: String = PROFILES[pi]
		var res := _tune(C, G, prof, parent, P, pats)
		parent = {"flags": res["flags"], "sizes": res["sizes"]}
		out[prof] = {"ok": true, "error": "", "profile": prof, "notes": res["notes"], "stats": res["stats"]}
	return out


## Regelverstoesse (leer = spielbar nach Spec-Tabelle).
static func lint(notes: Array, grid: Dictionary, profile: String) -> Array[String]:
	var v: Array[String] = []
	if not RULES.has(profile):
		v.append("unbekanntes Profil %s" % profile)
		return v
	var G := _grid(grid)
	if int(G["n"]) == 0:
		v.append("grid ohne Segmente")
		return v
	var R: Dictionary = RULES[profile]
	var units: Array = R["units"]
	var rare: int = R["rare"]
	var gap_rule: float = R["gap"]
	var relgap := minf(gap_rule, 0.5)
	var jack_max: int = R["jack"]
	var n := notes.size()
	var last := [-1e9, -1e9, -1e9, -1e9]
	var run := [0, 0, 0, 0]
	var hstart := [-1e9, -1e9, -1e9, -1e9]
	var hend := [-1e9, -1e9, -1e9, -1e9]
	var left := 0
	var rare_n := 0
	var ovl_n := 0
	var prev_t := -1e18
	var row_bp := -1e9
	var row_size := 0
	var row_idx := -1
	var rows_bp: Array[float] = []
	var rows_size: Array[int] = []
	var rows_tick: Array[int] = []
	var burst := 0
	for i in n:
		var nt: Dictionary = notes[i]
		var t: float = nt.get("t_ms", 0.0)
		var col: int = nt.get("col", -1)
		var e: float = nt.get("end_ms", -1.0)
		if col < 0 or col > 3:
			v.append("Spalte ausserhalb 0..3 bei %d ms" % int(t))
			continue
		if t < prev_t - 0.001:
			v.append("Noten nicht sortiert bei %d ms" % int(t))
		prev_t = t
		var tk := _tick_at(G, t)
		var tick: int = tk[1]
		var bp: float = tk[3]
		if float(tk[2]) > 1.0:
			v.append("nicht auf dem Gitter: %d ms (%.1f ms daneben)" % [int(t), float(tk[2])])
		elif not _unit_ok(tick, units) and not (rare > 0 and posmod(tick, rare) == 0):
			v.append("Teilung zu fein fuer %s: %d ms" % [profile, int(t)])
		# Zeilen (Akkorde)
		if absf(bp - row_bp) < EPS:
			row_size += 1
			rows_size[row_idx] = row_size
		else:
			row_bp = bp
			row_size = 1
			row_idx += 1
			rows_bp.append(bp)
			rows_size.append(1)
			rows_tick.append(tick)
		# gleiche Spalte: Abstand, Jack, Hold
		var dl: float = bp - float(last[col])
		if dl < gap_rule - EPS:
			v.append("Mindestabstand gleiche Spalte verletzt: %d ms Spalte %d" % [int(t), col])
		if dl <= 0.25 + EPS:
			run[col] = int(run[col]) + 1
			if int(run[col]) > maxi(jack_max, 1) or jack_max == 0:
				v.append("Jack zu lang: %d ms Spalte %d" % [int(t), col])
		else:
			run[col] = 1
		for c in 4:
			var he: float = hend[c]
			if c == col:
				if he > -1e8 and bp < he + relgap - EPS:
					v.append("Note zu nah am Hold der eigenen Spalte: %d ms Spalte %d" % [int(t), col])
			elif he > bp + EPS and float(hstart[c]) < bp - EPS:
				ovl_n += 1
		last[col] = bp
		if col < 2:
			left += 1
		if e >= 0.0:
			var te := _tick_at(G, e)
			var ebp: float = te[3]
			if float(te[2]) > 1.0 or posmod(int(te[1]), int(R["hold_unit"])) != 0:
				v.append("Hold-Ende nicht auf dem Gitter: %d ms" % int(e))
			if ebp - bp < 0.25 - EPS:
				v.append("Hold zu kurz: %d ms" % int(t))
			hstart[col] = bp
			hend[col] = ebp
	# Akkorde und Bursts
	var nrows := rows_bp.size()
	for i in nrows:
		var sz: int = rows_size[i]
		var tick: int = rows_tick[i]
		if rare > 0 and not _unit_ok(tick, units) and posmod(tick, rare) == 0:
			rare_n += 1
		if sz > int(R["chord"]) and not (profile == "Expert" and sz == 4 and i == nrows - 1):
			v.append("Akkord zu gross (%d) in Zeile %d" % [sz, i])
		elif sz == 2 and posmod(tick, int(R["chord_unit"])) != 0:
			v.append("Akkord abseits des Akzents in Zeile %d" % i)
		elif sz == 3 and posmod(tick, int(R["c3_unit"])) != 0:
			v.append("3er-Akkord abseits des Akzents in Zeile %d" % i)
		if int(R["burst"]) > 0 and i > 0:
			if rows_bp[i] - rows_bp[i - 1] <= float(R["burst_gap"]):
				burst += 1
				if burst > int(R["burst"]):
					v.append("schnelle Folge zu lang in Zeile %d" % i)
			else:
				burst = 0
	if rare > 0 and rare_n > maxi(2, int(float(R["rare_max"]) * float(nrows))):
		v.append("zu viele Zeilen auf der seltenen Teilung fuer %s: %d von %d" % [profile, rare_n, nrows])
	var n2 := 0
	var n3 := 0
	for sz: int in rows_size:
		if sz == 2:
			n2 += 1
		elif sz >= 3:
			n3 += 1
	if float(R["chord_max"]) < 1.0 and n2 + n3 > maxi(2, int(float(R["chord_max"]) * float(nrows))):
		v.append("zu viele Akkorde fuer %s: %d von %d Zeilen" % [profile, n2 + n3, nrows])
	if int(R["chord"]) >= 3 and float(R["c3_max"]) < 1.0 and n3 > maxi(1, int(float(R["c3_max"]) * float(nrows))):
		v.append("zu viele 3er-Akkorde fuer %s: %d von %d Zeilen" % [profile, n3, nrows])
	var ovl_rule: int = R["overlap"]
	if ovl_rule == 0 and ovl_n > 0:
		v.append("Hold und Note gleichzeitig: %d" % ovl_n)
	elif ovl_rule == 1 and ovl_n > maxi(2, int(float(R["ovl_max"]) * n)):
		v.append("zu oft Hold und Note gleichzeitig: %d von %d" % [ovl_n, n])
	if n >= BALANCE_MIN_NOTES:
		var share := float(left) / float(n)
		if share < float(R["bal_lo"]) - 0.0005 or share > float(R["bal_hi"]) + 0.0005:
			v.append("Hand-Balance %.1f %% links" % (share * 100.0))
	return v


## Sterne-Schaetzung (Nachbau der osu!mania-Strain-Formel). Dient nur der Nachregelung; der
## Vergleich mit rosu-pp (StarService) steht in docs/automap/chart.md.
static func estimate_stars(notes: Array) -> float:
	var n := notes.size()
	if n < 2:
		return 0.0
	var st := [0.0, 0.0, 0.0, 0.0]
	var en := [0.0, 0.0, 0.0, 0.0]
	var ind := [0.0, 0.0, 0.0, 0.0]
	var ind_strain := 0.0
	var overall := 0.0
	var peaks := PackedFloat64Array()
	var cur_peak := 0.0
	var sec_end := 0.0
	var prev_t: float = notes[0]["t_ms"]
	for i in range(1, n):
		var nt: Dictionary = notes[i]
		var s: float = nt["t_ms"]
		var e: float = maxf(float(nt["end_ms"]), s)
		var col: int = nt["col"]
		if i == 1:
			sec_end = ceilf(s / 400.0) * 400.0
		while s > sec_end:
			peaks.append(cur_peak)
			var off := (sec_end - prev_t) / 1000.0
			cur_peak = ind_strain * pow(0.125, off) + overall * pow(0.30, off)
			sec_end += 400.0
		var delta := s - prev_t
		var overlapping := false
		var closest := absf(e - s)
		var hold_factor := 1.0
		for c in 4:
			var ec: float = en[c]
			if ec > s + 1.0 and e > ec + 1.0:
				overlapping = true
			if ec > e + 1.0:
				hold_factor = 1.25
			closest = minf(closest, absf(e - ec))
		var hold_add := 0.0
		if overlapping:
			hold_add = 1.0 / (1.0 + exp(0.27 * (30.0 - closest)))
		ind[col] = float(ind[col]) * pow(0.125, (s - float(st[col])) / 1000.0) + 2.0 * hold_factor
		if delta <= 1.0:
			ind_strain = maxf(ind_strain, float(ind[col]))
		else:
			ind_strain = float(ind[col])
		overall = overall * pow(0.30, delta / 1000.0) + (1.0 + hold_add) * hold_factor
		st[col] = s
		en[col] = e
		cur_peak = maxf(cur_peak, ind_strain + overall)
		prev_t = s
	peaks.append(cur_peak)
	peaks.sort()
	var sum := 0.0
	var w := 1.0
	for i in range(peaks.size() - 1, -1, -1):
		if peaks[i] <= 0.0 or w < 1e-7:
			break
		sum += peaks[i] * w
		w *= 0.9
	return sum * 0.018


## Musterstatistik einer Map (Zaehler; zusammenfuehren und normieren macht der Lerner).
static func pattern_stats(notes: Array, grid: Dictionary) -> Dictionary:
	var big: Array = []
	for g in 4:
		var z: Array = []
		z.resize(256)
		z.fill(0)
		big.append(z)
	var uni: Array = []
	uni.resize(16)
	uni.fill(0)
	var out := {"notes": notes.size(), "rows": 0, "sizes": [0, 0, 0, 0, 0], "uni": uni, "big": big,
			"gaps": [0, 0, 0, 0], "holds": 0, "hold_rows": 0, "hold_beats": 0.0, "left": 0, "right": 0,
			"moves": [0, 0, 0, 0], "jack_runs": [0, 0, 0, 0, 0, 0, 0, 0, 0], "jack_notes": 0,
			"g4": {}, "g8": {}, "dur_s": 0.0, "nps_peak": 0.0,
			# Lage der Zeilen (1/1, 1/2, 1/4, feiner), Akkorde je Lage, Laeufe aus 1/4-Abstaenden
			# (Zeilen je Lauf, 1..16), Noten waehrend eines Holds einer anderen Spalte
			"pos": [0, 0, 0, 0], "cpos": [0, 0, 0, 0], "c3pos": [0, 0, 0, 0],
			"qrun": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "ovl": 0}
	var G := _grid(grid)
	var n := notes.size()
	if n == 0 or int(G["n"]) == 0:
		return out
	var pos: Array = out["pos"]
	var cpos: Array = out["cpos"]
	var c3pos: Array = out["c3pos"]
	var qrun: Array = out["qrun"]
	var qr := 1
	var hstart := [-1e9, -1e9, -1e9, -1e9]
	var hend := [-1e9, -1e9, -1e9, -1e9]
	var last := [-1e9, -1e9, -1e9, -1e9]
	var run := [0, 0, 0, 0]
	var jr: Array = out["jack_runs"]
	var sizes: Array = out["sizes"]
	var moves: Array = out["moves"]
	var gaps: Array = out["gaps"]
	var g4: Dictionary = out["g4"]
	var g8: Dictionary = out["g8"]
	var jack_notes := 0
	var rows := 0
	var pm := 0
	var pbp := -1e9
	var hist := 0
	var runlen := 0
	var i := 0
	var peak := 0
	var w0 := 0
	while i < n:
		var t: float = notes[i]["t_ms"]
		var bp := _g_bp(G, t)
		var mask := 0
		var row_holds := 0
		var j := i
		while j < n and absf(float(notes[j]["t_ms"]) - t) <= 2.0:
			var nt: Dictionary = notes[j]
			var col: int = clampi(int(nt["col"]), 0, 3)
			mask |= 1 << col
			if float(nt["end_ms"]) > t:
				out["holds"] = int(out["holds"]) + 1
				row_holds += 1
				out["hold_beats"] = float(out["hold_beats"]) + (_g_bp(G, float(nt["end_ms"])) - bp)
			if col < 2:
				out["left"] = int(out["left"]) + 1
			else:
				out["right"] = int(out["right"]) + 1
			for c in 4:
				if c != col and float(hend[c]) > bp + EPS and float(hstart[c]) < bp - EPS:
					out["ovl"] = int(out["ovl"]) + 1
					break
			if float(nt["end_ms"]) > t:
				hstart[col] = bp
				hend[col] = _g_bp(G, float(nt["end_ms"]))
			if bp - float(last[col]) <= 0.25 + EPS:
				run[col] = int(run[col]) + 1
			else:
				if int(run[col]) >= 2:
					jr[mini(int(run[col]), 8)] = int(jr[mini(int(run[col]), 8)]) + 1
					jack_notes += int(run[col])
				run[col] = 1
			last[col] = bp
			j += 1
		if row_holds > 0:
			out["hold_rows"] = int(out["hold_rows"]) + 1
		while float(notes[w0]["t_ms"]) < t - 1000.0:
			w0 += 1
		peak = maxi(peak, j - w0)
		rows += 1
		sizes[POP[mask]] = int(sizes[POP[mask]]) + 1
		uni[mask] = int(uni[mask]) + 1
		var tk := int(_tick_at(G, t)[1])
		var pc := 0 if posmod(tk, 24) == 0 else (1 if posmod(tk, 12) == 0 else (2 if posmod(tk, 6) == 0 else 3))
		pos[pc] = int(pos[pc]) + 1
		if POP[mask] >= 2:
			cpos[pc] = int(cpos[pc]) + 1
		if POP[mask] >= 3:
			c3pos[pc] = int(c3pos[pc]) + 1
		var gap := bp - pbp
		if pm != 0 and gap <= 0.27:
			qr += 1
		else:
			if qr >= 2:
				qrun[mini(qr, 16)] = int(qrun[mini(qr, 16)]) + 1
			qr = 1
		if pm != 0:
			var gc := _gapclass(gap)
			gaps[gc] = int(gaps[gc]) + 1
			var arr: Array = big[gc]
			arr[pm * 16 + mask] = int(arr[pm * 16 + mask]) + 1
			if POP[pm] == 1 and POP[mask] == 1:
				var d := absi(int(round(float(MC[pm]) - float(MC[mask]))))
				moves[d] = int(moves[d]) + 1
		if gap > 0.52:
			hist = 0
			runlen = 0
		hist = ((hist << 4) | mask) & 0xFFFFFFFF
		runlen += 1
		if runlen >= 4:
			var k4 := hist & 0xFFFF
			g4[k4] = int(g4.get(k4, 0)) + 1
		if runlen >= 8:
			g8[hist] = int(g8.get(hist, 0)) + 1
		pm = mask
		pbp = bp
		i = j
	for c in 4:
		if int(run[c]) >= 2:
			jr[mini(int(run[c]), 8)] = int(jr[mini(int(run[c]), 8)]) + 1
			jack_notes += int(run[c])
	if qr >= 2:
		qrun[mini(qr, 16)] = int(qrun[mini(qr, 16)]) + 1
	out["rows"] = rows
	out["jack_notes"] = jack_notes
	out["dur_s"] = maxf((float(notes[n - 1]["t_ms"]) - float(notes[0]["t_ms"])) / 1000.0, 1.0)
	out["nps_peak"] = float(peak)
	return out


## Muster-Cache verwerfen (nach dem Neuschreiben von patterns.json).
static func reload_patterns() -> void:
	_pat_mutex.lock()
	_pat_cache = {}
	_pat_mutex.unlock()


# ---------------------------------------------------------------------------
# Gitter (gleiche Regeln wie AmGrid)
# ---------------------------------------------------------------------------

static func _grid(grid: Dictionary) -> Dictionary:
	var start := PackedFloat64Array()
	var beat := PackedFloat64Array()
	var meter := PackedInt32Array()
	var db := PackedInt32Array()
	var bp0 := PackedFloat64Array()
	var segs = grid.get("segments", [])
	if segs is Array:
		for s in segs:
			if not (s is Dictionary):
				continue
			var b: float = s.get("beat_ms", 0.0)
			var st: float = s.get("start_ms", 0.0)
			if b <= 1.0 or (start.size() > 0 and st <= start[start.size() - 1]):
				continue
			var k := start.size()
			if k == 0:
				bp0.append(0.0)
			else:
				bp0.append(bp0[k - 1] + (st - start[k - 1]) / beat[k - 1])
			start.append(st)
			beat.append(b)
			var m: int = s.get("meter", 4)
			meter.append(m if m > 0 else 4)
			db.append(int(round((float(s.get("downbeat_ms", st)) - st) / b)))
	return {"n": start.size(), "start": start, "beat": beat, "meter": meter, "db": db, "bp0": bp0}


static func _gi(G: Dictionary, t: float) -> int:
	var start: PackedFloat64Array = G["start"]
	var lo := 0
	var hi := start.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if start[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func _g_bp(G: Dictionary, t: float) -> float:
	var i := _gi(G, t)
	var start: PackedFloat64Array = G["start"]
	var beat: PackedFloat64Array = G["beat"]
	var bp0: PackedFloat64Array = G["bp0"]
	return bp0[i] + (t - start[i]) / beat[i]


static func _g_ms(G: Dictionary, bp: float) -> float:
	var bp0: PackedFloat64Array = G["bp0"]
	var start: PackedFloat64Array = G["start"]
	var beat: PackedFloat64Array = G["beat"]
	var lo := 0
	var hi := bp0.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if bp0[mid] <= bp:
			lo = mid
		else:
			hi = mid - 1
	return start[lo] + (bp - bp0[lo]) * beat[lo]


## Naechster (mode 0) oder vorheriger (mode -1) Gitterpunkt; unit in 1/24 Schlag.
static func _g_snap(G: Dictionary, t: float, unit: int, mode: int) -> float:
	var i := _gi(G, t)
	var start: PackedFloat64Array = G["start"]
	var beat: PackedFloat64Array = G["beat"]
	var u := beat[i] / 24.0 * float(unit)
	var k := (t - start[i]) / u
	var r := start[i] + (roundf(k) if mode == 0 else floorf(k + 1e-6)) * u
	if i + 1 < start.size() and r > start[i + 1] - 0.5:
		r = start[i + 1]
	return r


## [Segment, Tick (1/24), Fehler in ms, Schlagposition] einer Zeit; 1 ms Rundung erlaubt.
static func _tick_at(G: Dictionary, t: float) -> Array:
	var i := _gi(G, t + 1.0)
	var start: PackedFloat64Array = G["start"]
	var beat: PackedFloat64Array = G["beat"]
	var bp0: PackedFloat64Array = G["bp0"]
	var x := (t - start[i]) / beat[i] * 24.0
	var k := int(round(x))
	var err := absf(x - float(k)) * beat[i] / 24.0
	var bp := bp0[i] + (float(k) / 24.0 if err <= 1.0 else x / 24.0)
	return [i, k, err, bp]


static func _unit_ok(tick: int, units: Array) -> bool:
	for u: int in units:
		if posmod(tick, u) == 0:
			return true
	return false


static func _gapclass(gap: float) -> int:
	if gap <= 0.13:
		return 0
	if gap <= 0.27:
		return 1
	if gap <= 0.52:
		return 2
	return 3


# ---------------------------------------------------------------------------
# Vorbereitung: Ereignisse -> Zeilen auf dem Gitter
# ---------------------------------------------------------------------------

static func _params(params: Dictionary) -> Dictionary:
	var P := DEFAULTS.duplicate(true)
	for k in params:
		if k == "star_bands" and params[k] is Dictionary:
			for b in params[k]:
				P["star_bands"][b] = params[k][b]
		else:
			P[k] = params[k]
	return P


static func _fail(profile: String, err: String) -> Dictionary:
	return {"ok": false, "error": err, "profile": profile, "notes": [], "stats": {}}


static func _prep(features: Dictionary, G: Dictionary, P: Dictionary) -> Dictionary:
	var events: Array = features.get("events", [])
	var sections: Array = features.get("sections", []) if features.get("sections") is Array else []
	var start: PackedFloat64Array = G["start"]
	var beat: PackedFloat64Array = G["beat"]
	var meter: PackedInt32Array = G["meter"]
	var db: PackedInt32Array = G["db"]
	var bp0: PackedFloat64Array = G["bp0"]
	var nseg: int = G["n"]
	var lead: float = P["osu_lead_ms"]
	var bias_ms: float = P["snap_quarter_bias_ms"]
	var wdrum: float = P["support_drum_weight"]
	var wsup: float = P["support_weight"]
	# 1. Durchgang: je Schlag entscheiden, ob gerade (1/8) oder triolisch (1/6) geteilt wird
	var ne := events.size()
	var e_seg := PackedInt32Array()
	var e_x := PackedFloat64Array()
	e_seg.resize(ne)
	e_x.resize(ne)
	var votes := {}
	for i in ne:
		var ev: Dictionary = events[i]
		var t: float = float(ev.get("t_ms", 0.0)) - lead
		var si := _gi(G, t)
		var x := (t - start[si]) / beat[si] * 24.0
		e_seg[i] = si
		e_x[i] = x
		var e3 := absf(x - round(x / 3.0) * 3.0)
		var e4 := absf(x - round(x / 4.0) * 4.0)
		var key := si * 1000000 + int(floor(x / 24.0)) + 500000
		var w: float = maxf(float(ev.get("strength", 0.5)), 0.05)
		if e4 + 0.35 < e3:
			votes[key] = float(votes.get(key, 0.0)) + w
		elif e3 + 0.35 < e4:
			votes[key] = float(votes.get(key, 0.0)) - w
	# 2. Durchgang: einrasten und je Gitterpunkt sammeln
	var slot := {}
	var raw: Array = []
	var sc := 0
	var nsec := sections.size()
	for i in ne:
		var ev: Dictionary = events[i]
		var te: float = ev.get("t_ms", 0.0)
		while sc + 1 < nsec and float(sections[sc].get("end_ms", 0.0)) <= te:
			sc += 1
		var lead_layer := "drums"
		var intensity := 0.5
		if nsec > 0:
			lead_layer = String(sections[sc].get("lead", "drums"))
			intensity = float(sections[sc].get("intensity", 0.5))
		var si: int = e_seg[i]
		var x: float = e_x[i]
		var key := si * 1000000 + int(floor(x / 24.0)) + 500000
		var tick := 0
		if float(votes.get(key, 0.0)) > 0.0:
			tick = int(round(x / 4.0)) * 4
		else:
			var q6 := roundf(x / 6.0) * 6.0
			var q3 := roundf(x / 3.0) * 3.0
			var bias := bias_ms / (beat[si] / 24.0)
			tick = int(q6) if absf(x - q6) <= absf(x - q3) + bias else int(q3)
		var ts := start[si] + float(tick) * beat[si] / 24.0
		if si + 1 < nseg and ts > start[si + 1] - 1.0:
			si += 1
			tick = 0
			ts = start[si]
		var kind := String(ev.get("kind", "other"))
		var layer := String(KIND_LAYER.get(kind, ""))
		var lw := wsup
		if layer == lead_layer and layer != "":
			lw = 1.0
		elif layer == "drums" and kind != "hat":
			lw = wdrum
		var strength: float = clampf(float(ev.get("strength", 0.5)), 0.0, 1.0)
		var ws := strength * lw
		var pitch: float = ev.get("pitch", -1.0)
		var sus: float = ev.get("sustain_ms", 0.0)
		var kbit: int = KIND_BITS.get(kind, 64)
		var skey := si * 1000000 + tick + 500000
		if slot.has(skey):
			var row: Array = raw[slot[skey]]
			if ws > float(row[3]):
				row[3] = ws
				row[6] = kbit
			# Tonhoehe der staerksten Ebene mit Tonhoehe (unabhaengig von der Reihenfolge)
			if pitch >= 0.0 and ws > float(row[12]):
				row[7] = pitch
				row[12] = ws
			row[4] = maxf(float(row[4]), strength)
			row[5] = int(row[5]) | kbit
			row[8] = maxf(float(row[8]), sus)
			if kind == "hat" and strength >= 0.75:
				row[11] = 1
		else:
			slot[skey] = raw.size()
			raw.append([ts, si, tick, ws, strength, kbit, kbit, pitch, sus, sc, intensity,
					1 if (kind == "hat" and strength >= 0.75) else 0, ws if pitch >= 0.0 else -1.0])
	raw.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# Zeilen, die ueber eine Segmentgrenze hinweg zu dicht liegen, zusammenlegen
	var rows: Array = []
	var prev_bp := -1e9
	for row: Array in raw:
		var si: int = row[1]
		var bp := bp0[si] + float(row[2]) / 24.0
		if bp - prev_bp < 0.12:
			if float(row[3]) > float(rows[rows.size() - 1][3]):
				rows[rows.size() - 1] = row
				prev_bp = bp
			continue
		rows.append(row)
		prev_bp = bp
	var n := rows.size()
	var C := {"n": n, "t": PackedFloat64Array(), "bp": PackedFloat64Array(), "tick": PackedInt32Array(),
			"score": PackedFloat64Array(), "acc": PackedFloat64Array(), "sus": PackedFloat64Array(),
			"susb": PackedFloat64Array(), "pitch": PackedFloat64Array(), "kinds": PackedInt32Array(),
			"kind": PackedInt32Array(), "bar": PackedInt32Array(), "tib": PackedInt32Array(),
			"sec": PackedInt32Array(), "inten": PackedFloat64Array()}
	var c_t: PackedFloat64Array = C["t"]
	var c_bp: PackedFloat64Array = C["bp"]
	var c_tick: PackedInt32Array = C["tick"]
	var c_score: PackedFloat64Array = C["score"]
	var c_acc: PackedFloat64Array = C["acc"]
	var c_sus: PackedFloat64Array = C["sus"]
	var c_susb: PackedFloat64Array = C["susb"]
	var c_pitch: PackedFloat64Array = C["pitch"]
	var c_kinds: PackedInt32Array = C["kinds"]
	var c_kind: PackedInt32Array = C["kind"]
	var c_bar: PackedInt32Array = C["bar"]
	var c_tib: PackedInt32Array = C["tib"]
	var c_sec: PackedInt32Array = C["sec"]
	var c_inten: PackedFloat64Array = C["inten"]
	var wm: float = P["w_metric"]
	var wst: float = P["w_strength"]
	for i in n:
		var row: Array = rows[i]
		var si: int = row[1]
		var tick: int = row[2]
		var b := int(floor(float(tick) / 24.0)) - db[si]
		var bar := int(floor(float(b) / float(meter[si])))
		var metric := 0.15
		var accb := 0.0
		if posmod(tick, 24) == 0:
			if posmod(b, meter[si]) == 0:
				metric = 1.0
				accb = 0.5
			else:
				metric = 0.8
				accb = 0.25
		elif posmod(tick, 12) == 0:
			metric = 0.55
		elif posmod(tick, 6) == 0:
			metric = 0.35
		var nk: int = POP[int(row[5]) & 15] + POP[(int(row[5]) >> 4) & 15]
		c_t.append(float(row[0]))
		c_bp.append(bp0[si] + float(tick) / 24.0)
		c_tick.append(tick)
		# Gleichstand: gleiche Taktposition gleich behandeln, Rest gleichmaessig ueber den Song
		var tib_i := tick - (db[si] + bar * meter[si]) * 24
		var jit := 0.001 * fmod(float(posmod(tib_i, 960)) * 0.6180339887, 1.0) + 0.00001 * fmod(float(i) * 0.6180339887, 1.0)
		c_score.append(wm * metric + wst * (float(row[3]) + 0.1 * float(nk - 1)) + jit)
		c_acc.append(float(row[4]) + accb + 0.3 * float(row[11]) + 0.15 * float(nk - 1) + 10.0 * jit)
		c_sus.append(float(row[8]))
		c_susb.append(float(row[8]) / beat[si])
		c_pitch.append(float(row[7]))
		c_kinds.append(int(row[5]))
		c_kind.append(int(row[6]))
		c_bar.append(si * 100000 + bar + 50000)
		c_tib.append(tick - (db[si] + bar * meter[si]) * 24)
		c_sec.append(int(row[9]))
		c_inten.append(float(row[10]))
	C["t"] = c_t
	C["bp"] = c_bp
	C["tick"] = c_tick
	C["score"] = c_score
	C["acc"] = c_acc
	C["sus"] = c_sus
	C["susb"] = c_susb
	C["pitch"] = c_pitch
	C["kinds"] = c_kinds
	C["kind"] = c_kind
	C["bar"] = c_bar
	C["tib"] = c_tib
	C["sec"] = c_sec
	C["inten"] = c_inten
	# Wiederholung: Takte mit gleicher Musik (Rhythmus, Instrument, Staerke, Tonhoehen-Verlauf,
	# gehaltene Toene, Intensitaet) bekommen dieselben Entscheidungen wie ihr erstes Vorkommen.
	var tmpl := PackedInt32Array()
	tmpl.resize(n)
	tmpl.fill(-1)
	var first := {}
	var i := 0
	while i < n:
		var j := i
		while j < n and c_bar[j] == c_bar[i]:
			j += 1
		if j - i >= int(P["motif_min_rows"]):
			var parts := PackedStringArray()
			var p0 := -1.0
			for q in range(i, j):
				var pb := 99
				if c_pitch[q] >= 0.0:
					if p0 < 0.0:
						p0 = c_pitch[q]
					pb = int(round((c_pitch[q] - p0) * 6.0))
				parts.append("%d:%d:%d:%d:%d:%d" % [c_tib[q], c_kinds[q], int(round(float(rows[q][4]) * 4.0)), pb,
						int(round(c_susb[q] * 2.0)), int(round(c_inten[q] * 4.0))])
			var sig := ",".join(parts)
			if first.has(sig):
				var f0: int = first[sig]
				for q in range(i, j):
					tmpl[q] = f0 + (q - i)
			else:
				first[sig] = i
		i = j
	C["tmpl"] = tmpl
	return C


# ---------------------------------------------------------------------------
# Mustertabellen
# ---------------------------------------------------------------------------

static func _patterns(P: Dictionary) -> Dictionary:
	var src: Dictionary = P.get("patterns", {})
	if not src.is_empty():
		return _pat_ready(src)
	_pat_mutex.lock()
	if _pat_cache.is_empty():
		var loaded := {}
		if FileAccess.file_exists(PATTERNS_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATTERNS_PATH))
			if parsed is Dictionary:
				loaded = parsed
		_pat_cache = _pat_ready(loaded)
	var out := _pat_cache
	_pat_mutex.unlock()
	return out


static func _pat_ready(src: Dictionary) -> Dictionary:
	var out := {"learned": false, "star_a": 1.0, "star_b": 0.0, "bands": {}}
	var bands: Dictionary = src.get("bands", {}) if src.get("bands") is Dictionary else {}
	var fit = src.get("star_fit", {})
	if fit is Dictionary and fit.has("a"):
		out["star_a"] = float(fit["a"])
		out["star_b"] = float(fit.get("b", 0.0))
	var fallback_chords := [0.0, 0.05, 0.12, 0.2, 0.25]
	for pi in PROFILES.size():
		var prof: String = PROFILES[pi]
		var b: Dictionary = bands.get(prof, {}) if bands.get(prof) is Dictionary else {}
		var pat := {"chord_share": float(b.get("chord_share", fallback_chords[pi])),
				"chord3_share": float(b.get("chord3_share", 0.02 if pi >= 3 else 0.0)),
				"hold_share": float(b.get("hold_share_mean", 0.15)),
				"hold_p90": float(b.get("hold_share_p90", 0.3)),
				"holds_per_row": clampf(float(b.get("holds_per_row", 1.0)), 1.0, 2.0),
				"kiai_ratio": clampf(float(b.get("kiai_ratio", 1.3)), 1.0, 2.5),
				"jack_cap": int(b.get("jack_cap", 8)), "jack_share": float(b.get("jack_share", 0.05))}
		var uni := PackedFloat32Array()
		uni.resize(16)
		uni.fill(1.0 / 15.0)
		var u = b.get("uni", [])
		if u is Array and u.size() == 16:
			for i in 16:
				uni[i] = float(u[i])
		pat["uni"] = uni
		var big: Array = []
		var bsrc = b.get("big", [])
		for g in 4:
			var arr := PackedFloat32Array()
			arr.resize(256)
			arr.fill(1.0 / 225.0)
			if bsrc is Array and bsrc.size() == 4 and bsrc[g] is Array and bsrc[g].size() == 256:
				for i in 256:
					arr[i] = float(bsrc[g][i])
				out["learned"] = true
			big.append(arr)
		pat["big"] = big
		for gname: String in ["g4", "g8"]:
			var gd := {}
			var gs = b.get(gname, {})
			if gs is Dictionary:
				for k in gs:
					gd[int(String(k))] = float(gs[k])
			pat[gname] = gd
		var vals: Array = (pat["g4"] as Dictionary).values()
		vals.sort()
		var cut: float = vals[maxi(vals.size() - 60, 0)] if not vals.is_empty() else 2.0
		var top4 := {}
		for k4 in pat["g4"]:
			if float(pat["g4"][k4]) >= cut:
				top4[k4] = true
		pat["top4"] = top4
		out["bands"][prof] = pat
	return out


# ---------------------------------------------------------------------------
# Nachregelung je Profil
# ---------------------------------------------------------------------------

static func _tune(C: Dictionary, G: Dictionary, profile: String, parent: Dictionary, P: Dictionary, pats: Dictionary) -> Dictionary:
	var R: Dictionary = RULES[profile]
	var pat: Dictionary = pats["bands"][profile]
	var n: int = C["n"]
	var tick: PackedInt32Array = C["tick"]
	var score: PackedFloat64Array = C["score"]
	var inten: PackedFloat64Array = C["inten"]
	var acc: PackedFloat64Array = C["acc"]
	var susb: PackedFloat64Array = C["susb"]
	var has_parent := not parent.is_empty()
	var pflags: PackedByteArray = parent.get("flags", PackedByteArray())
	var psizes: PackedByteArray = parent.get("sizes", PackedByteArray())
	var units: Array = R["units"]
	var rare_unit: int = R["rare"]
	var dg: float = float(P["dens_gain"]) * float(pat["kiai_ratio"])
	var allowed: Array = []
	var rare: Array = []
	var sus_rows: Array = []
	var eff := PackedFloat64Array()
	eff.resize(n)
	for r in n:
		eff[r] = score[r] + dg * (inten[r] - 0.5) + (float(P["sus_bonus"]) if susb[r] >= float(R["hold_min"]) - EPS else 0.0)
		if has_parent and pflags[r] == 0:
			continue
		if _unit_ok(tick[r], units):
			allowed.append(r)
			if susb[r] >= float(R["hold_min"]) - EPS:
				sus_rows.append(r)
		elif rare_unit > 0 and posmod(tick[r], rare_unit) == 0:
			rare.append(r)
	var by_score := func(a: int, b: int) -> bool:
		return eff[a] > eff[b] if eff[a] != eff[b] else a < b
	var order_score := allowed.duplicate()
	order_score.sort_custom(by_score)
	rare.sort_custom(by_score)
	var order_acc := allowed.duplicate()
	order_acc.sort_custom(func(a: int, b: int) -> bool: return acc[a] > acc[b] if acc[a] != acc[b] else a < b)
	# Holds auf den staerksten gehaltenen Toenen (nicht den laengsten: Laengen wie bei den Menschen)
	sus_rows.sort_custom(by_score)
	var star_a: float = P["star_scale"]
	var star_b: float = P["star_offset"]
	if star_a <= 0.0:
		star_a = pats["star_a"]
		star_b = pats["star_b"]
	var seed_base := hash("%d|%d|%s|%d" % [n, int(C["t"][0]), profile, int(P["seed"])])
	var X := {"profile": profile, "R": R, "pat": pat, "P": P, "order_score": order_score, "rare": rare,
			"order_acc": order_acc, "sus_rows": sus_rows, "psizes": psizes, "has_parent": has_parent,
			"seed": seed_base, "na": allowed.size(), "pflags": pflags}
	var band: Array = P["star_bands"].get(profile, [0.0, 99.0])
	var lo_b: float = band[0]
	var hi_b: float = band[1]
	var target := (lo_b + hi_b) * 0.5
	var tol: float = P["star_tol"]
	var best := {}
	var best_err := 1e9
	var evals := 0
	var d := 1.0
	var d_lo := 0.02
	var d_hi := 2.0 if (int(R["chord"]) > 1 or rare_unit > 0) else 1.0
	var iters: int = P["tune_iters"]
	while evals <= iters:
		var res := _make(C, G, X, d, 0)
		evals += 1
		var stars := estimate_stars(res["notes"]) * star_a + star_b
		res["stars"] = stars
		res["d"] = d
		var e := absf(stars - target)
		if e < best_err:
			best_err = e
			best = res
		if e <= tol:
			break
		if stars < target:
			d_lo = d
		else:
			d_hi = d
		if d_hi - d_lo < 0.01:
			break
		d = (d_lo + d_hi) * 0.5
	# Sicherheitsnetz: Verstoss gegen die eigenen Regeln -> andere Zufallsfolge
	var gdict := {"segments": []}
	var gstart: PackedFloat64Array = G["start"]
	var gbeat: PackedFloat64Array = G["beat"]
	for i in gstart.size():
		gdict["segments"].append({"start_ms": gstart[i], "beat_ms": gbeat[i]})
	var viol := lint(best["notes"], gdict, profile)
	var tries := 1
	while not viol.is_empty() and tries <= 3:
		var alt := _make(C, G, X, float(best["d"]), tries)
		var v2 := lint(alt["notes"], gdict, profile)
		if v2.size() < viol.size():
			alt["stars"] = estimate_stars(alt["notes"]) * star_a + star_b
			alt["d"] = best["d"]
			best = alt
			viol = v2
		tries += 1
	var notes: Array = best["notes"]
	var stars_f: float = best["stars"]
	var nn := notes.size()
	var span := 1.0
	var peak := 0
	if nn > 0:
		span = maxf((float(notes[nn - 1]["t_ms"]) - float(notes[0]["t_ms"])) / 1000.0, 1.0)
		var w0 := 0
		for i in nn:
			while float(notes[w0]["t_ms"]) < float(notes[i]["t_ms"]) - 1000.0:
				w0 += 1
			peak = maxi(peak, i - w0 + 1)
	var holds := 0
	for nt: Dictionary in notes:
		if float(nt["end_ms"]) >= 0.0:
			holds += 1
	var lr: int = int(best["L"]) + int(best["R"])
	best["stats"] = {"nps_avg": float(nn) / span, "nps_peak": float(peak), "holds": holds,
			"chords": int(best["chords"]), "max_jack": int(best["maxjack"]),
			"stars_est": stars_f, "capped": stars_f < lo_b or stars_f > hi_b,
			"capped_low": stars_f < lo_b, "density": float(best["d"]), "lint": viol.size(),
			"balance": (float(best["L"]) / float(lr)) if lr > 0 else 0.5,
			"motif_bars": int(best["bars"]), "motif_reused": int(best["reused"]),
			"learned": bool(pats["learned"])}
	return best


## Ein Durchgang: Auswahl (Dichte d), Akkorde, Holds, Spalten. Zeilen in Holds entfallen erst beim
## Setzen; liegt der Akkord-Anteil danach ueber der Regel, wird mit weniger Akkorden neu gesetzt.
static func _make(C: Dictionary, G: Dictionary, X: Dictionary, d: float, seed_add: int) -> Dictionary:
	var R: Dictionary = X["R"]
	var s2 := 1.0
	var s3 := 1.0
	var sr := 1.0
	var res := {}
	for attempt in 4:
		res = _make1(C, G, X, d, seed_add, s2, s3, sr)
		var rows := maxi(int(res["rows"]), 1)
		var sh2 := float(res["chords"]) / float(rows)
		var sh3 := float(res["c3"]) / float(rows)
		var lim2 := float(R["chord_max"]) * 0.95
		var lim3 := float(R["c3_max"]) * 0.92
		var ok2 := float(R["chord_max"]) >= 1.0 or sh2 <= lim2 or int(res["chords"]) <= 2
		var ok3 := int(R["chord"]) < 3 or float(R["c3_max"]) >= 1.0 or sh3 <= lim3 or int(res["c3"]) <= 1
		var shr := float(res["rare_rows"]) / float(rows)
		var limr := float(R["rare_max"]) * 0.95
		var okr := int(R["rare"]) == 0 or shr <= limr or int(res["rare_rows"]) <= 2
		if ok2 and ok3 and okr:
			break
		if not okr:
			sr *= limr / shr * 0.97
		if not ok2:
			s2 *= lim2 / sh2 * 0.97
		if not ok3:
			s3 = 0.0 if attempt >= 2 else s3 * lim3 / maxf(sh3, 0.0001) * 0.95
	return res


static func _make1(C: Dictionary, G: Dictionary, X: Dictionary, d: float, seed_add: int, s2: float, s3: float, sr: float) -> Dictionary:
	var n: int = C["n"]
	var R: Dictionary = X["R"]
	var P: Dictionary = X["P"]
	var pat: Dictionary = X["pat"]
	var tick: PackedInt32Array = C["tick"]
	var bp: PackedFloat64Array = C["bp"]
	var bar: PackedInt32Array = C["bar"]
	var order_score: Array = X["order_score"]
	var rare: Array = X["rare"]
	var na: int = X["na"]
	var flags := PackedByteArray()
	flags.resize(n)
	var k := clampi(int(ceil(clampf(d, 0.0, 1.0) * float(na))), mini(na, 4), na)
	for i in k:
		flags[order_score[i]] = 1
	var boost := maxf(d - 1.0, 0.0)
	if rare.size() > 0:
		# seltene Teilung (Easy 1/2, Normal 1/4, Hard 1/8): bis d = 1 der Anteil der Menschen-Maps,
		# darueber bis knapp unter die Obergrenze der Spielbarkeits-Regel (mehr Noten statt Akkorde)
		var rs: float = R["rare_share"]
		var f := minf(rs * clampf(d, 0.0, 1.0) + boost * maxf(float(R["rare_max"]) * 0.9 - rs, 0.0), float(R["rare_max"]) * 0.9)
		f *= sr
		var kr := mini(rare.size(), int(floor(f / maxf(1.0 - f, 0.05) * float(k))))
		for i in kr:
			flags[rare[i]] = 1
	var tmpl: PackedInt32Array = C["tmpl"]
	var pflags: PackedByteArray = X["pflags"]
	for r in n:
		if tmpl[r] >= 0:
			flags[r] = flags[tmpl[r]] if (not X["has_parent"] or pflags[r] == 1) else 0
	var burst: int = R["burst"]
	if burst > 0:
		var gaps := 0
		var pb := -1e9
		for r in n:
			if flags[r] == 0:
				continue
			if bp[r] - pb <= float(R["burst_gap"]):
				if posmod(tick[r], int(R["burst_keep"])) != 0 and gaps + 1 >= burst:
					flags[r] = 0
					continue
				gaps += 1
			else:
				gaps = 0
			pb = bp[r]
	var sel := PackedInt32Array()
	var sizes := PackedByteArray()
	sizes.resize(n)
	for r in n:
		if flags[r] == 1:
			sel.append(r)
			sizes[r] = 1
	var ns := sel.size()
	# Takte mit Vorlage erben Akkorde und Holds: jede Vorlage zaehlt mit ihren Kopien
	var tcount := PackedInt32Array()
	tcount.resize(n)
	for r: int in sel:
		if tmpl[r] >= 0 and flags[tmpl[r]] == 1:
			tcount[tmpl[r]] += 1
	# Akzente -> Akkorde (Anteil aus den Menschen-Maps des Bands)
	var maxc: int = R["chord"]
	var psizes: PackedByteArray = X["psizes"]
	var has_parent: bool = X["has_parent"]
	if maxc >= 2:
		var mult := 1.0 + boost * float(P["chord_boost_max"])
		var order_acc: Array = X["order_acc"]
		var n2 := int(round(minf(float(pat["chord_share"]) * mult, float(R["chord_max"]) * 0.9) * float(ns) * s2))
		var n3 := int(round(minf(float(pat["chord3_share"]) * mult, float(R["c3_max"]) * 0.85) * float(ns) * s3)) if maxc >= 3 else 0
		var cu: int = R["chord_unit"]
		var c3: int = R["c3_unit"]
		var got := 0
		for r: int in order_acc:
			if got >= n2:
				break
			if flags[r] == 1 and tmpl[r] < 0 and got + 1 + tcount[r] <= n2 + 1 and posmod(tick[r], cu) == 0 and (not has_parent or psizes[r] >= 2):
				sizes[r] = 2
				got += 1 + tcount[r]
		got = 0
		var qof := {}
		for q in ns:
			qof[sel[q]] = q
		for r: int in order_acc:
			if got >= n3:
				break
			if sizes[r] == 2 and tmpl[r] < 0 and got + 1 + tcount[r] <= n3 and posmod(tick[r], c3) == 0 and (not has_parent or psizes[r] >= 3):
				# 3er-Akkord nur zwischen Einzelnoten (sonst erzwungene Jacks)
				var q: int = qof[r]
				if q > 0 and bp[r] - bp[sel[q - 1]] <= 0.26 and sizes[sel[q - 1]] >= 2:
					continue
				if q + 1 < ns and bp[sel[q + 1]] - bp[r] <= 0.26 and sizes[sel[q + 1]] >= 2:
					continue
				sizes[r] = 3
				got += 1 + tcount[r]
		for r: int in sel:
			if tmpl[r] >= 0:
				var sz: int = sizes[tmpl[r]] if flags[tmpl[r]] == 1 else 1
				if has_parent:
					sz = mini(sz, psizes[r])
				sizes[r] = sz
		if X["profile"] == "Expert" and ns > 0 and sizes[sel[ns - 1]] == 3:
			sizes[sel[ns - 1]] = 4
	# gehaltene Toene -> Holds (hoechstens der Anteil, den Menschen im Band setzen)
	var holdf := PackedByteArray()
	holdf.resize(n)
	# Anteil der Hold-Noten wie bei den Menschen (Holds je Note; Akkord-Zeilen tragen mehr Noten)
	# Obergrenze: 90. Perzentil der Menschen (Songs mit vielen gehaltenen Toenen bekommen mehr Holds,
	# wie LN-lastige Menschen-Maps); ohne gehaltene Toene keine Holds
	var kh := int(round(float(pat["hold_p90"]) * float(P["hold_share_scale"]) * float(ns)
			* (1.0 + float(pat["chord_share"])) / (float(pat["holds_per_row"]) if int(R["overlap"]) == 2 else 1.0)))
	var goth := 0
	for r: int in X["sus_rows"]:
		if goth >= kh:
			break
		if flags[r] == 1 and tmpl[r] < 0 and goth + 1 + tcount[r] <= kh + 1:
			holdf[r] = 1
			goth += 1 + tcount[r]
	for r: int in sel:
		if tmpl[r] >= 0:
			holdf[r] = holdf[tmpl[r]] if flags[tmpl[r]] == 1 else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(X["seed"]) + seed_add * 7919
	var Y := {"sel": sel, "holdf": holdf, "rng": rng, "R": R, "pat": pat, "P": P,
			"jack_cap": mini(int(R["jack"]), maxi(int(pat["jack_cap"]), 1)) if int(R["jack"]) > 0 else 0,
			"ovl_budget": int(0.6 * float(R["ovl_max"]) * float(ns)), "seed_i": int(X["seed"]) & 3, "avoid": 0,
			"ep": exp(float(P["pitch_weight"])), "erole": exp(float(P["role_weight"]))}
	var S: Array = [-1e9, -1e9, -1e9, -1e9, 0, 0, 0, 0, -1e9, -1e9, -1e9, -1e9, 0, 0, 0, -1e9, -1.0, 1.5, 0, 0, 0, -1e9,
			-1.0, 1, 0, 0, 0, 0, 0, 0]
	var notes: Array = []
	var memo := {}
	var motif_min: int = P["motif_min_rows"]
	var bars := 0
	var reused := 0
	var chords := 0
	var c_bp: PackedFloat64Array = C["bp"]
	var prev_mirror := -1       # vorheriger Takt kopiert: 0 gleich, 1 gespiegelt; -1 frisch gesetzt
	var snap: Array = []        # Zustand vor der letzten Zeile des vorigen, frisch gesetzten Takts
	var snap_q := -1
	var snap_sig := ""          # dessen Motiv-Eintrag (falls gemerkt)
	var i := 0
	while i < ns:
		var j := i
		var b: int = bar[sel[i]]
		while j < ns and bar[sel[j]] == b:
			j += 1
		var sig := ""
		var done := false
		if j - i >= motif_min:
			bars += 1
			sig = _bar_sig(C, sel, i, j, sizes, holdf)
			if memo.has(sig):
				var masks: PackedInt32Array = memo[sig]
				var first_mirror := false
				if prev_mirror >= 0:
					# gleiche Richtung wie der Vortakt: dann passt auch der Uebergang
					first_mirror = prev_mirror == 1
				else:
					var bal := 0
					for m in masks:
						bal += int(NLR[m])
					var dev := float(int(S[S_L]) - int(S[S_R])) / float(int(S[S_L]) + int(S[S_R]) + 6)
					first_mirror = absf(dev) > 0.03 and dev * float(bal) > 0.0
				var res := {}
				for mirror: bool in [first_mirror, not first_mirror]:
					res = _try_copy(S, C, G, Y, i, j, masks, mirror, false, flags, sizes)
					if not res.is_empty():
						break
				# Regeln am Uebergang lokal loesen: letzte Zeile des Vortakts so neu setzen, dass die
				# Spalten des Motivanfangs frei sind, dann das Motiv ganz uebernehmen
				if res.is_empty() and snap_q == i - 1 and not snap.is_empty():
					for mirror: bool in [first_mirror, not first_mirror]:
						var avoid := 0
						for q in range(i, j):
							if c_bp[sel[q]] > c_bp[sel[i]] + 0.6:
								break
							avoid |= MIRROR[masks[q - i]] if mirror else masks[q - i]
						var S3: Array = (snap[0] as Array).duplicate()
						var tmp3: Array = []
						Y["avoid"] = avoid
						var m3 := _do_row(S3, C, G, Y, i - 1, sizes[sel[i - 1]], 0, tmp3)
						Y["avoid"] = 0
						if m3 <= 0:
							continue
						var sz3 := sizes.duplicate()
						sz3[sel[i - 1]] = POP[m3]
						res = _try_copy(S3, C, G, Y, i, j, masks, mirror, false, flags, sz3)
						if not res.is_empty():
							notes.resize(int(snap[1]))
							notes.append_array(tmp3)
							if snap_sig != "" and memo.has(snap_sig):
								var pmk: PackedInt32Array = memo[snap_sig]
								pmk[pmk.size() - 1] = m3
								memo[snap_sig] = pmk
							break
				if res.is_empty():
					# sonst Zeile fuer Zeile so nah wie moeglich (beide Richtungen, mehr Treffer gewinnt)
					for mirror: bool in [first_mirror, not first_mirror]:
						var t := _try_copy(S, C, G, Y, i, j, masks, mirror, true, flags, sizes)
						if res.is_empty() or int(t["hit"]) > int(res["hit"]):
							res = t
				S = res["S"]
				notes.append_array(res["notes"])
				flags = res["flags"]
				sizes = res["sizes"]
				if int(res["hit"]) * 5 >= (j - i) * 4:
					reused += 1
				prev_mirror = 1 if res["mirror"] else 0
				snap = []
				snap_q = -1
				snap_sig = ""
				done = true
		if not done:
			prev_mirror = -1
			var placed := PackedInt32Array()
			for q in range(i, j):
				var r: int = sel[q]
				snap = [S.duplicate(), notes.size()]
				snap_q = q
				var m := _do_row(S, C, G, Y, q, sizes[r], 0, notes)
				placed.append(m)
				if m == 0:
					# entfallene Zeile (z. B. waehrend eines Holds) gehoert zum Motiv
					flags[r] = 0
					sizes[r] = 0
				else:
					sizes[r] = POP[m]
			snap_sig = ""
			# auch nicht ganz sauber gesetzte Takte merken: Kopien uebernehmen genau das Gesetzte
			if sig != "" and not memo.has(sig):
				memo[sig] = placed
				snap_sig = sig
		for q in range(i, j):
			if sizes[sel[q]] >= 2:
				chords += 1
		i = j
	return {"notes": notes, "flags": flags, "sizes": sizes, "maxjack": int(S[S_MAXJ]), "bars": bars,
			"reused": reused, "chords": int(S[S_CH]), "c3": int(S[S_C3]), "rows": int(S[S_ROWS]), "rare_rows": int(S[S_RARE]),
			"L": int(S[S_L]), "R": int(S[S_R])}


## Uebernimmt ein Motiv (Masken je Zeile, evtl. gespiegelt). partial = false: nur ganz oder gar
## nicht ({} bei Fehlschlag); partial = true: passende Zeilen gleich, die anderen frei gesetzt.
static func _try_copy(S: Array, C: Dictionary, G: Dictionary, Y: Dictionary, i: int, j: int, masks: PackedInt32Array,
		mirror: bool, partial: bool, flags: PackedByteArray, sizes: PackedByteArray) -> Dictionary:
	var sel: PackedInt32Array = Y["sel"]
	var S2 := S.duplicate()
	var tmp: Array = []
	var fl := flags.duplicate()
	var sz := sizes.duplicate()
	var hit := 0
	for q in range(i, j):
		var m: int = masks[q - i]
		if mirror:
			m = MIRROR[m]
		var got := _do_row(S2, C, G, Y, q, POP[m], m, tmp)
		if got == m:
			hit += 1
			if m == 0:
				fl[sel[q]] = 0
				sz[sel[q]] = 0
		elif partial:
			got = _do_row(S2, C, G, Y, q, POP[m], 0, tmp)
			if got <= 0:
				fl[sel[q]] = 0
				sz[sel[q]] = 0
			else:
				sz[sel[q]] = POP[got]
		else:
			return {}
	return {"S": S2, "notes": tmp, "flags": fl, "sizes": sz, "hit": hit, "mirror": mirror}


## Kennung eines Takts: Rhythmus, Akkordgroessen, Holds, Instrument und Tonhoehen-Verlauf.
static func _bar_sig(C: Dictionary, sel: PackedInt32Array, i: int, j: int, sizes: PackedByteArray, holdf: PackedByteArray) -> String:
	var tib: PackedInt32Array = C["tib"]
	var kind: PackedInt32Array = C["kind"]
	var pitch: PackedFloat64Array = C["pitch"]
	var p0 := -1.0
	var parts := PackedStringArray()
	for q in range(i, j):
		var r: int = sel[q]
		var pb := 99
		if pitch[r] >= 0.0:
			if p0 < 0.0:
				p0 = pitch[r]
			pb = int(round((pitch[r] - p0) * 6.0))
		parts.append("%d:%d%d:%d:%d" % [tib[r], sizes[r], holdf[r], kind[r], pb])
	return ",".join(parts)


## Setzt eine Zeile. Liefert die Maske, 0 = Zeile entfaellt, -1 = vorgegebene Maske passt nicht.
static func _do_row(S: Array, C: Dictionary, G: Dictionary, Y: Dictionary, q: int, size: int, forced: int, notes: Array) -> int:
	var sel: PackedInt32Array = Y["sel"]
	var r: int = sel[q]
	var R: Dictionary = Y["R"]
	var c_bp: PackedFloat64Array = C["bp"]
	var bp: float = c_bp[r]
	var gap_rule: float = R["gap"]
	var relgap := minf(gap_rule, 0.5)
	var jack_max: int = Y["jack_cap"]
	var overlap: int = R["overlap"]
	if bp < float(S[S_BLOCK]) - EPS:
		return -1 if forced > 0 else 0
	var free := 0
	var active := 0
	for c in 4:
		var he: float = S[S_HEND + c]
		if he > bp + EPS:
			active += 1
		if he > -1e8 and bp < he + relgap - EPS:
			continue
		var dl: float = bp - float(S[S_LAST + c])
		if dl < gap_rule - EPS:
			continue
		if dl <= 0.25 + EPS and int(S[S_RUN + c]) + 1 > jack_max:
			continue
		free |= 1 << c
	if overlap == 0 and active > 0:
		return -1 if forced > 0 else 0
	var avoid: int = Y["avoid"]
	if avoid != 0 and forced == 0 and POP[free & ~avoid] >= size:
		free &= ~avoid
	var mask := 0
	if forced > 0:
		if (forced & free) != forced:
			return -1
		mask = forced
	else:
		while size > 0:
			mask = _choose(S, C, Y, r, size, free, bp)
			if mask > 0:
				break
			size -= 1
		if mask <= 0:
			return 0
	var c_pitch: PackedFloat64Array = C["pitch"]
	var p: float = c_pitch[r]
	# Hold: Ende auf dem Gitter, bei Easy/Normal vor der naechsten Note
	var hold_col := -1
	var end_ms := -1.0
	var end_bp := 0.0
	var holdf: PackedByteArray = Y["holdf"]
	if holdf[r] == 1 and active < 2:
		var c_t: PackedFloat64Array = C["t"]
		var c_sus: PackedFloat64Array = C["sus"]
		var c_susb: PackedFloat64Array = C["susb"]
		var hu: int = R["hold_unit"]
		end_ms = _g_snap(G, c_t[r] + c_sus[r], hu, 0)
		end_bp = _g_bp(G, end_ms)
		var limited := false
		if overlap == 0:
			# Easy: Hold behaelt seine Laenge (gedeckelt), Zeilen waehrend des Holds entfallen
			var cap_bp := bp + float(Y["P"]["easy_hold_max_beats"])
			if end_bp > cap_bp + EPS:
				end_ms = _g_snap(G, _g_ms(G, cap_bp) + 0.01, hu, -1)
				end_bp = _g_bp(G, end_ms)
		elif overlap == 1:
			var cnt := 0
			var qq := q + 1
			while qq < sel.size() and c_bp[sel[qq]] < end_bp - EPS:
				cnt += 1
				qq += 1
			if int(S[S_OVL]) + cnt <= int(Y["ovl_budget"]):
				S[S_OVL] = int(S[S_OVL]) + cnt
			else:
				# wie Easy: Hold behaelt seine Laenge (gedeckelt), Zeilen darin entfallen
				var cap_n := bp + float(Y["P"]["easy_hold_max_beats"])
				if end_bp > cap_n + EPS:
					end_ms = _g_snap(G, _g_ms(G, cap_n) + 0.01, hu, -1)
					end_bp = _g_bp(G, end_ms)
				if end_bp - bp >= float(R["hold_min"]) - EPS:
					S[S_BLOCK] = end_bp
		if limited and q + 1 < sel.size():
			var limit: float = c_bp[sel[q + 1]] - 0.5
			if end_bp > limit + EPS:
				end_ms = _g_snap(G, _g_ms(G, limit) + 0.01, hu, -1)
				end_bp = _g_bp(G, end_ms)
		if end_bp - bp >= float(R["hold_min"]) - EPS:
			var want := int(round(p * 3.0)) if p >= 0.0 else (0 if (q & 1) == 0 else 3)
			var bestd := 99
			for c in 4:
				if (mask >> c) & 1 == 1 and absi(c - want) < bestd:
					bestd = absi(c - want)
					hold_col = c
	# mehrere Holds in einer Akkord-Zeile, so oft wie bei den Menschen (Hard und schwerer)
	var hold_cols := 0
	if hold_col >= 0:
		hold_cols = 1 << hold_col
		if overlap == 2 and POP[mask] >= 2 and active == 0:
			var extra: float = float(Y["pat"]["holds_per_row"]) - 1.0
			var hrng: RandomNumberGenerator = Y["rng"]
			for c in 4:
				if (mask >> c) & 1 == 1 and c != hold_col and hrng.randf() < extra:
					hold_cols |= 1 << c
	var c_tt: PackedFloat64Array = C["t"]
	var t: float = c_tt[r]
	for c in 4:
		if (mask >> c) & 1 == 0:
			continue
		var is_hold := (hold_cols >> c) & 1 == 1
		notes.append({"t_ms": t, "col": c, "end_ms": end_ms if is_hold else -1.0})
		var dl: float = bp - float(S[S_LAST + c])
		var run: int = int(S[S_RUN + c]) + 1 if dl <= 0.25 + EPS else 1
		S[S_RUN + c] = run
		if run >= 2:
			S[S_JN] = int(S[S_JN]) + (2 if run == 2 else 1)
		if run > int(S[S_MAXJ]):
			S[S_MAXJ] = run
		S[S_LAST + c] = bp
		if is_hold:
			S[S_HEND + c] = end_bp
		if c < 2:
			S[S_L] = int(S[S_L]) + 1
		else:
			S[S_R] = int(S[S_R]) + 1
	var hist: int = S[S_HIST]
	if bp - float(S[S_PBP]) > 0.52:
		hist = 0
	S[S_HIST] = ((hist << 4) | mask) & 0xFFFFFFFF
	S[S_ROWS] = int(S[S_ROWS]) + 1
	var c_tick: PackedInt32Array = C["tick"]
	if int(R["rare"]) > 0 and not _unit_ok(c_tick[r], R["units"]):
		S[S_RARE] = int(S[S_RARE]) + 1
	if POP[mask] >= 2:
		S[S_CH] = int(S[S_CH]) + 1
	if POP[mask] >= 3:
		S[S_C3] = int(S[S_C3]) + 1
	var pmask: int = S[S_PM]
	if POP[mask] == 1 and POP[pmask] == 1 and mask != pmask:
		S[S_DIR] = 1 if MC[mask] > MC[pmask] else -1
	S[S_PM] = mask
	S[S_PBP] = bp
	if p >= 0.0:
		S[S_PP2] = S[S_PP]
		S[S_PP] = p
	S[S_PC] = MC[mask]
	var c_kinds: PackedInt32Array = C["kinds"]
	S[S_PK] = c_kinds[r]
	return mask


## Waehlt die Spalten einer Zeile: 4er-Modell der Menschen-Maps (naechste Zeile nach den drei
## vorigen) gemischt mit den Zeilen-Uebergaengen je Abstand, gewichtet mit Tonhoehe, Figuren
## (Treppe, Triller, Roll), Kick/Snare-Rolle, Hand-Balance und Jack-Anteil des Bands.
static func _choose(S: Array, C: Dictionary, Y: Dictionary, r: int, size: int, free: int, bp: float) -> int:
	var pat: Dictionary = Y["pat"]
	var P: Dictionary = Y["P"]
	var gap: float = bp - float(S[S_PBP])
	var pm: int = S[S_PM]
	var bigs: Array = pat["big"]
	var bigarr: PackedFloat32Array = bigs[_gapclass(gap)]
	var uni: PackedFloat32Array = pat["uni"]
	var g4: Dictionary = pat["g4"]
	var g8: Dictionary = pat["g8"]
	var lr: int = int(S[S_L]) + int(S[S_R])
	var dev := float(int(S[S_L]) - int(S[S_R])) / float(lr + 6)
	var kbal: float = float(P["balance_weight"]) * dev + 400.0 * dev * dev * dev
	var c_pitch: PackedFloat64Array = C["pitch"]
	var p: float = c_pitch[r]
	var pp: float = S[S_PP]
	var pp2: float = S[S_PP2]
	var pc: float = S[S_PC]
	var thr: float = P["pitch_step"]
	var ep: float = Y["ep"]
	var c_kinds: PackedInt32Array = C["kinds"]
	var c_sec: PackedInt32Array = C["sec"]
	var kinds: int = c_kinds[r]
	var rc := -1
	if kinds & 1:
		rc = ROLES[(c_sec[r] + int(Y["seed_i"])) & 3][0]
	elif kinds & 2:
		rc = ROLES[(c_sec[r] + int(Y["seed_i"])) & 3][1]
	var erole: float = Y["erole"]
	var lam: float = P["ngram_weight"]
	var sharp: float = P["sharpness"]
	var near := gap <= 0.52
	var hist: int = S[S_HIST] if near else 0
	# Figur: bevorzugte Einzelspalte (Maske) aus Tonhoehe und Instrument
	var fig := 0
	if size == 1 and near and POP[pm] == 1:
		var pcol := int(MC[pm])
		var m2 := (hist >> 4) & 15
		if p >= 0.0 and pp >= 0.0 and pp2 >= 0.0:
			if absf(p - pp2) <= thr and absf(p - pp) > thr and POP[m2] == 1 and m2 != pm:
				fig = m2                                   # Triller: zwei Toene im Wechsel
			elif (p - pp > thr and pp - pp2 > thr) or (p - pp < -thr and pp - pp2 < -thr):
				var dir := 1 if p > pp else -1             # Treppe: Tonhoehe laeuft weiter
				if pcol + dir >= 0 and pcol + dir <= 3:
					fig = 1 << (pcol + dir)
		if fig == 0 and rc < 0 and (kinds & 4) != 0 and (int(S[S_PK]) & 4) != 0 and gap <= 0.26:
			var rdir: int = S[S_DIR]                       # Roll: Hi-Hat-Lauf
			if pcol + rdir < 0 or pcol + rdir > 3:
				rdir = -rdir
			fig = 1 << (pcol + rdir)
	var efig: float = exp(float(P["figure_weight"]))
	var fresh: float = P["fresh_weight"]
	var top4: Dictionary = pat["top4"]
	var etop: float = 1.0 + float(P["top_boost"])
	# Jacks: Anteil der Menschen-Maps des Bands halten
	var jratio := float(S[S_JN]) / float(maxi(lr, 30)) / maxf(float(pat["jack_share"]), 0.003)
	var jexp := clampf(-float(P["jack_weight"]) * (jratio - 1.0), -4.0, 0.5)
	var cands: Array = MASKS_BY_SIZE[size]
	var ms := PackedInt32Array()
	var wb := PackedFloat64Array()
	var wg := PackedFloat64Array()
	var sb := 0.0
	var sg := 0.0
	var h3 := (hist & 0xFFF) << 4
	var has3 := near and ((hist >> 8) & 15) != 0
	for m: int in cands:
		if (m & free) != m:
			continue
		var b: float = (uni[m] if pm == 0 else bigarr[pm * 16 + m]) + 0.002
		var g := 0.0
		if has3:
			g = float(g4.get(h3 | m, 0.0))
		ms.append(m)
		wb.append(b)
		wg.append(g)
		sb += b
		sg += g
	if ms.is_empty():
		return 0
	var ws := PackedFloat64Array()
	ws.resize(ms.size())
	var total := 0.0
	for i in ms.size():
		var m: int = ms[i]
		var w: float = wb[i] / sb
		if sg > 0.0:
			w = (1.0 - lam) * w + lam * wg[i] / sg
		w += 0.0005
		var mc: float = MC[m]
		if p >= 0.0:
			if pp >= 0.0:
				var dp := p - pp
				# Gegenrichtung zur Tonhoehe stark bestraft (Musik-Regel vor Muster-Haeufigkeit)
				if dp > thr:
					w *= ep if mc > pc + 0.01 else (1.0 / (ep * ep) if mc < pc - 0.01 else 0.7)
				elif dp < -thr:
					w *= ep if mc < pc - 0.01 else (1.0 / (ep * ep) if mc > pc + 0.01 else 0.7)
				elif gap > 0.25 + EPS and absf(mc - pc) < 0.01:
					w *= sqrt(ep)
			else:
				w *= exp(-0.5 * absf(mc - p * 3.0))
		if fig != 0 and m == fig:
			w *= efig
		if fresh > 0.0 and near:
			w *= exp(-fresh * float(POP[m & ((hist >> 8) & 15)] + POP[m & ((hist >> 4) & 15)]) / float(POP[m]))
		if has3 and top4.has(h3 | m):
			w *= etop
		if rc >= 0 and (m >> rc) & 1 == 1:
			w *= erole
		w *= exp(-kbal * float(NLR[m]))
		if gap <= 0.25 + EPS and (m & pm) != 0:
			w *= exp(jexp * float(POP[m & pm]))
		var k8 := ((hist << 4) | m) & 0xFFFFFFFF
		if g8.has(k8):
			w *= 1.0 + float(g8[k8])
		w = pow(w, sharp)
		ws[i] = w
		total += w
	var rng: RandomNumberGenerator = Y["rng"]
	var x := rng.randf() * total
	for i in ms.size():
		x -= ws[i]
		if x <= 0.0:
			return ms[i]
	return ms[ms.size() - 1]
