extends SceneTree

## OMEN Auto-Mapper 4K: Pruefstand. Misst den Ablauf gegen die Menschen-Maps in maps/ und
## schreibt docs/automap/report.md (jede Zeile der Ziel-Tabelle aus docs/automap/spec.md).
##
## Aufruf (EIN Prozess fuer alle Maps, beendet sich selbst):
##   timeout 7200 Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . \
##       --script res://tools/automap_bench.gd -- --maps <maps-ordner> [--mapper auto|old|new]
##       [--limit N] [--set tune|test] [--stages] [--no-stars] [--resume] [--report-only]
## Hoerprobe (Klick je Note und je Schlag ueber den Song, Ausgabe user://automap_check/<name>.ogg):
##   ... --script res://tools/automap_bench.gd -- --click <audio|-> <osz> [Diff-Teilname] [--lead ms]
##
## --mapper auto: neue Module (AmGrid, AmFeatures, AmChart, AutoMapper4K), sobald ihre Skripte da
## sind, sonst der alte AudioMapper ueber einen Adapter (Ausgangswert "alt").
## Die Kennzahlen sind statische Funktionen (getestet in tests/run_am_bench_tests.gd) und werden
## auch von tools/automap_tune.gd benutzt.

const PROFILES := ["Easy", "Normal", "Hard", "Insane", "Expert"]
const STAR_BANDS := {"Easy": [1.3, 1.9], "Normal": [2.1, 2.8], "Hard": [3.0, 3.8],
		"Insane": [4.0, 4.8], "Expert": [5.0, 6.0]}
## Eine Menschen-Diff ist nur dann Vergleichspartner eines Profils, wenn ihre Sterne hoechstens
## so weit ausserhalb des Profil-Bands liegen.
const PARTNER_STAR_SLACK := 0.5
const TEMPO_TOL := 0.005
const DIAG_FACTORS := [2.0, 0.5, 1.5, 0.667, 0.75, 1.333, 3.0, 0.333]
const NOTE_TOL_MS := 15.0
const DENS_WIN_MS := 2000.0
const OUT_DIR := "user://automap_bench"
const CHECK_DIR := "user://automap_check"
const REPORT_PATH := "res://docs/automap/report.md"
const MODULE_PATHS := {
	"grid": "res://scripts/automap/am_grid.gd",
	"features": "res://scripts/automap/am_features.gd",
	"chart": "res://scripts/automap/am_chart.gd",
	"mapper": "res://scripts/automap/auto_mapper_4k.gd",
}
const CLICK_RATE := 44100
const CLICK_COL_HZ := [880.0, 1174.7, 1568.0, 2093.0]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var args := OS.get_cmdline_user_args()
	var code := 0
	if args.has("--click"):
		code = _cli_click(args)
	else:
		code = _cli_bench(args)
	quit(code)
	return true


# ===========================================================================
# Adapter: alter AudioMapper (Orbit) hinter den Schnittstellen der Spec
# ===========================================================================

## Der alte Mapper kennt ein Tempo, einen Offset und Notenzeiten in drei Stufen. Er kennt keine
## Spalten, keine Holds, kein Kiai, keine Alternativen, keinen Taktanfang in der Datei.
class OldGrid:
	static func track(pcm: PackedFloat32Array, _rate: int, _params: Dictionary = {}) -> Dictionary:
		var an: Dictionary = AudioMapper.analyze_samples(pcm)
		if not an.ok:
			return {"ok": false, "error": an.error, "segments": [], "confidence": 0.0, "alternatives": []}
		var beat := 60000.0 / float(an.bpm)
		# So schreibt build_osu die rote Linie: offset - OSU_LEAD_MS.
		var start := float(an.offset_ms) - AudioMapper.OSU_LEAD_MS
		return {"ok": true, "error": "", "confidence": -1.0, "alternatives": [], "_an": an,
				"segments": [{"start_ms": start, "beat_ms": beat, "meter": 4, "downbeat_ms": start}]}


class OldFeatures:
	static func decode(audio_path: String) -> Dictionary:
		var pcm := AudioMapper.decode(audio_path)
		if pcm.size() < AudioMapper.RATE * 4:
			return {"ok": false, "error": "Audio nicht dekodierbar oder kuerzer als 4 s", "pcm": pcm,
					"rate": AudioMapper.RATE, "duration_ms": 0.0}
		return {"ok": true, "error": "", "pcm": pcm, "rate": AudioMapper.RATE,
				"duration_ms": pcm.size() * 1000.0 / AudioMapper.RATE}

	static func analyze(pcm: PackedFloat32Array, rate: int, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true, "error": "", "duration_ms": pcm.size() * 1000.0 / maxi(rate, 1),
				"events": [], "energy": PackedFloat32Array(), "frame_ms": 0.0, "sections": []}


class OldChart:
	const PROFILES := ["Easy", "Normal", "Hard"]
	const MAP := {"Easy": "Leicht", "Normal": "Normal", "Hard": "Schwer"}

	static func build(_features: Dictionary, grid: Dictionary, profile: String, _params: Dictionary = {}) -> Dictionary:
		if not MAP.has(profile):
			return {"ok": false, "error": "Profil im alten Mapper nicht vorhanden", "profile": profile, "notes": []}
		if not grid.has("_an"):
			return {"ok": false, "error": "kein Gitter", "profile": profile, "notes": []}
		var notes: Array = []
		for n in AudioMapper.pick_notes(grid._an, MAP[profile]):
			notes.append({"t_ms": float(n[0]), "col": -1, "end_ms": -1.0})
		return {"ok": true, "error": "", "profile": profile, "notes": notes, "stats": {}}


## Module laden. Fehlende oder kaputte Skripte fuehren nie zum Absturz: dann gilt der Adapter.
## which: "auto" | "old" | "new". Rueckgabe {name: "alt"|"neu", grid, features, chart, mapper,
## missing: Array, caps: {cols, holds, kiai, profiles}}.
static func load_mods(which: String = "auto", paths: Dictionary = MODULE_PATHS) -> Dictionary:
	var old := {"name": "alt", "grid": OldGrid, "features": OldFeatures, "chart": OldChart,
			"mapper": null, "missing": [],
			"caps": {"cols": false, "holds": false, "kiai": false, "profiles": ["Easy", "Normal", "Hard"]}}
	if which == "old":
		return old
	var got := {}
	var missing: Array = []
	for k in paths:
		var s = null
		if ResourceLoader.exists(paths[k]):
			s = load(paths[k])
		if s != null and s is Script and (s as Script).can_instantiate():
			got[k] = s
		else:
			missing.append(k)
	if got.has("grid") and got.has("features") and got.has("chart"):
		return {"name": "neu", "grid": got.grid, "features": got.features, "chart": got.chart,
				"mapper": got.get("mapper"), "missing": missing,
				"caps": {"cols": true, "holds": true, "kiai": true, "profiles": PROFILES.duplicate()}}
	old.missing = missing
	return old


static func _has_static(script, method: String) -> bool:
	if script == null or not (script is Script):
		return false
	for m in (script as Script).get_script_method_list():
		if m.name == method:
			return true
	return false


# ===========================================================================
# Erzeugnis ("product"): einheitliche Form fuer beide Mapper
# {ok, error, segments, alternatives: [float], confidence, kiai: [[s,e]], charts: {profil: {ok,error,notes}},
#  lint: {profil: int (-1 = nicht geprueft)}, caps, stage_ms: {..}}
# ===========================================================================

static func _cached(cache: Dictionary, key: String, make: Callable):
	if cache.has(key):
		return cache[key]
	var v = make.call()
	cache[key] = v
	# je Stufe hoechstens 3 Staende halten (Koordinaten-Suche: bester + Kandidat)
	var prefix := key.substr(0, 2)
	var same: Array = []
	for k in cache:
		if String(k).begins_with(prefix):
			same.append(k)
	while same.size() > 3:
		cache.erase(same.pop_front())
	return v


## Stufen einzeln aufrufen (Abstimmung, Adapter). params: {grid, features, chart, post}.
## post.offset_shift_ms verschiebt Gitter und Noten gemeinsam (Eichung des OSU_LEAD).
## cache (optional) haelt die teuren Stufen je Parametersatz.
static func product_from_stages(mods: Dictionary, pcm: PackedFloat32Array, rate: int,
		params: Dictionary = {}, profiles: Array = PROFILES, cache: Dictionary = {}) -> Dictionary:
	var gp: Dictionary = params.get("grid", {})
	var fp: Dictionary = params.get("features", {})
	var cp: Dictionary = params.get("chart", {})
	var shift := float(params.get("post", {}).get("offset_shift_ms", 0.0))
	var stage := {}
	var t := Time.get_ticks_msec()
	var grid: Dictionary = _cached(cache, "g:" + JSON.stringify(gp), func(): return mods.grid.track(pcm, rate, gp))
	stage["grid"] = Time.get_ticks_msec() - t
	var prod := {"ok": false, "error": "", "segments": [], "alternatives": [], "confidence": -1.0,
			"kiai": [], "charts": {}, "lint": {}, "caps": mods.caps, "stage_ms": stage}
	if not grid.get("ok", false) or (grid.get("segments", []) as Array).is_empty():
		prod.error = "Gitter: " + str(grid.get("error", "leer"))
		return prod
	t = Time.get_ticks_msec()
	var feat: Dictionary = _cached(cache, "f:" + JSON.stringify(fp), func(): return mods.features.analyze(pcm, rate, fp))
	stage["features"] = Time.get_ticks_msec() - t
	if not feat.get("ok", false):
		prod.error = "Features: " + str(feat.get("error", ""))
		return prod
	for s in grid.segments:
		prod.segments.append({"start_ms": float(s.start_ms) + shift, "beat_ms": float(s.beat_ms),
				"meter": int(s.get("meter", 4)), "downbeat_ms": float(s.get("downbeat_ms", s.start_ms)) + shift})
	for alt in grid.get("alternatives", []):
		prod.alternatives.append(float(alt.factor) if alt is Dictionary else float(alt))
	prod.confidence = float(grid.get("confidence", -1.0))
	var kiai: Array = []
	for sec in feat.get("sections", []):
		if sec.get("kiai", false):
			kiai.append([float(sec.start_ms) + shift, float(sec.end_ms) + shift])
	prod.kiai = merge_intervals(kiai)
	t = Time.get_ticks_msec()
	var has_lint := _has_static(mods.chart, "lint")
	for p in profiles:
		var ch: Dictionary = mods.chart.build(feat, grid, p, cp)
		var notes: Array = []
		for n in ch.get("notes", []):
			var e := float(n.get("end_ms", -1.0))
			notes.append({"t_ms": float(n.t_ms) + shift, "col": int(n.get("col", -1)),
					"end_ms": (e + shift) if e >= 0.0 else -1.0})
		prod.charts[p] = {"ok": bool(ch.get("ok", false)), "error": str(ch.get("error", "")), "notes": notes}
		prod.lint[p] = -1
		if has_lint and ch.get("ok", false):
			var v = mods.chart.lint(ch.notes, grid, p)
			prod.lint[p] = (v as Array).size() if v is Array else -1
	stage["chart"] = Time.get_ticks_msec() - t
	prod.ok = true
	return prod


## Fertiges Set von AutoMapper4K.generate zurueckmessen (das, was der Nutzer wirklich bekommt).
static func product_from_osz(osz_path: String, gen_result: Dictionary, mods: Dictionary) -> Dictionary:
	var prod := {"ok": false, "error": "", "segments": [], "alternatives": [], "confidence": -1.0,
			"kiai": [], "charts": {}, "lint": {}, "caps": mods.caps, "stage_ms": {}}
	var imp: Dictionary = OszImporter._import_uncached(osz_path)
	if not imp.ok:
		prod.error = "erzeugtes Set nicht lesbar: " + str(imp.error)
		return prod
	for alt in gen_result.get("alternatives", []):
		prod.alternatives.append(float(alt.factor) if alt is Dictionary else float(alt))
	prod.confidence = float(gen_result.get("confidence", -1.0))
	var has_lint := _has_static(mods.chart, "lint")
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		if not bm.is_mania() or bm.column_count() != 4 or not PROFILES.has(bm.version_name()):
			continue
		var p := bm.version_name()
		if prod.segments.is_empty():
			for tp in bm.timing_points:
				if tp.uninherited and tp.beat_length > 0.0:
					prod.segments.append({"start_ms": tp.time, "beat_ms": tp.beat_length,
							"meter": tp.meter, "downbeat_ms": tp.time})
			var kiai: Array = []
			for iv in bm.kiai_intervals:
				kiai.append([float(iv.start), minf(float(iv.end), bm.duration_ms() + 60000.0)])
			prod.kiai = merge_intervals(kiai)
		var notes: Array = []
		for o in bm.hit_objects:
			var mn := o as ManiaNote
			if mn == null:
				continue
			notes.append({"t_ms": mn.time, "col": mn.column, "end_ms": mn.hold_end if mn.is_hold else -1.0})
		prod.charts[p] = {"ok": true, "error": "", "notes": notes}
		prod.lint[p] = -1
		if has_lint:
			var v = mods.chart.lint(notes, {"ok": true, "segments": prod.segments}, p)
			prod.lint[p] = (v as Array).size() if v is Array else -1
	if prod.segments.is_empty():
		prod.error = "erzeugtes Set ohne 4K-Diff mit Profilnamen"
		return prod
	prod.ok = true
	return prod


# ===========================================================================
# Kennzahlen (rein, getestet)
# ===========================================================================

## Feste Aufteilung ueber den Hash des Dateinamens: 70 % "tune" (Abstimm-Menge), 30 % "test".
static func split_of(fname: String) -> String:
	var h := fname.get_file().to_lower().sha256_text().substr(0, 8).hex_to_int()
	return "tune" if h % 100 < 70 else "test"


static func median(a: Array) -> float:
	return percentile(a, 50.0)


## Perzentil mit linearer Interpolation. Leere Liste -> NAN.
static func percentile(a: Array, p: float) -> float:
	if a.is_empty():
		return NAN
	var s := a.duplicate()
	s.sort()
	var pos := clampf(p / 100.0, 0.0, 1.0) * (s.size() - 1)
	var i := int(floor(pos))
	var j := mini(i + 1, s.size() - 1)
	return lerpf(float(s[i]), float(s[j]), pos - i)


static func mean(a: Array) -> float:
	if a.is_empty():
		return NAN
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()


static func wrap_c(d: float, period: float) -> float:
	return fposmod(d + period * 0.5, period) - period * 0.5


## Intervalle [[s,e],..] sortieren und verschmelzen.
static func merge_intervals(iv: Array) -> Array:
	var s: Array = []
	for x in iv:
		if float(x[1]) > float(x[0]):
			s.append([float(x[0]), float(x[1])])
	s.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for x in s:
		if not out.is_empty() and x[0] <= out[-1][1]:
			out[-1][1] = maxf(out[-1][1], x[1])
		else:
			out.append(x)
	return out


static func _total(iv: Array) -> float:
	var t := 0.0
	for x in iv:
		t += x[1] - x[0]
	return t


## Laenge der Schnittmenge zweier verschmolzener Intervall-Listen.
static func inter_len(a: Array, b: Array) -> float:
	var i := 0
	var j := 0
	var t := 0.0
	while i < a.size() and j < b.size():
		var lo := maxf(a[i][0], b[j][0])
		var hi := minf(a[i][1], b[j][1])
		if hi > lo:
			t += hi - lo
		if a[i][1] < b[j][1]:
			i += 1
		else:
			j += 1
	return t


## IoU zweier Intervall-Mengen. Beide leer -> NAN (nicht bewertbar).
static func interval_iou(a_in: Array, b_in: Array) -> float:
	var a := merge_intervals(a_in)
	var b := merge_intervals(b_in)
	var inter := inter_len(a, b)
	var uni := _total(a) + _total(b) - inter
	if uni <= 0.0:
		return NAN
	return inter / uni


## Rote Linien der Menschen-Map -> Tempo-Segmente im Bereich [t0, t1] (erste bis letzte Note).
## reds: [{time, beat_ms, meter}]. Eine rote Linie mit gleichem Tempo (0,05 %), die auf dem
## laufenden Gitter liegt (2 ms), ist kein neues Segment. effect = rote Linien als Effekt
## (Segment kuerzer als 2 Schlaege oder BPM ausserhalb 15..1000): nicht als Tempowechsel wertbar.
static func truth_segments(reds: Array, t0: float, t1: float) -> Dictionary:
	var rs: Array = []
	for r in reds:
		if float(r.beat_ms) > 0.0:
			rs.append(r)
	rs.sort_custom(func(a, b): return float(a.time) < float(b.time))
	# erste wirksame Linie: die letzte, die nicht nach t0 liegt
	var first := 0
	for i in rs.size():
		if float(rs[i].time) <= t0:
			first = i
	var segs: Array = []
	for i in range(first, rs.size()):
		var r = rs[i]
		if not segs.is_empty() and float(r.time) >= t1:
			break
		if not segs.is_empty():
			var p = segs[-1]
			var same_tempo := absf(float(r.beat_ms) / p.beat_ms - 1.0) < 0.0005
			var on_grid := absf(wrap_c(float(r.time) - p.downbeat_ms, p.beat_ms)) <= 2.0
			if same_tempo and on_grid:
				continue
		segs.append({"start_ms": float(r.time), "end_ms": t1, "beat_ms": float(r.beat_ms),
				"meter": int(r.get("meter", 4)), "downbeat_ms": float(r.time)})
	var effect := false
	for i in segs.size():
		if i + 1 < segs.size():
			segs[i].end_ms = segs[i + 1].start_ms
		var bpm: float = 60000.0 / segs[i].beat_ms
		if bpm > 1000.0 or bpm < 15.0:
			effect = true
		if segs.size() > 1 and segs[i].end_ms - maxf(segs[i].start_ms, t0) < 2.0 * segs[i].beat_ms:
			effect = true
	return {"segments": segs, "effect": effect}


static func seg_at(segs: Array, t: float) -> int:
	var k := 0
	for i in segs.size():
		if float(segs[i].start_ms) <= t:
			k = i
	return k


## t minus naechster Schlag des Gitters (Vorzeichen: + = t liegt hinter dem Schlag).
static func beat_delta(segs: Array, t: float) -> float:
	var s = segs[seg_at(segs, t)]
	return wrap_c(t - float(s.start_ms), float(s.beat_ms))


static func _tempo_match(gen_beat: float, true_beat: float, factor: float) -> bool:
	# BPM_gen * factor gegen BPM_wahr
	return absf(true_beat * factor / gen_beat - 1.0) <= TEMPO_TOL


## Anteil von [a, b], in dem das erzeugte Tempo (mal factor) auf +-0,5 % stimmt.
static func tempo_share(gen: Array, true_beat: float, a: float, b: float, factor: float = 1.0) -> float:
	if b <= a or gen.is_empty():
		return 0.0
	var good := 0.0
	for i in gen.size():
		var lo := float(gen[i].start_ms) if i > 0 else -INF
		var hi := float(gen[i + 1].start_ms) if i + 1 < gen.size() else INF
		var l := maxf(lo, a)
		var h := minf(hi, b)
		if h > l and _tempo_match(float(gen[i].beat_ms), true_beat, factor):
			good += h - l
	return good / (b - a)


## Erzeugtes Segment mit der groessten Ueberdeckung von [a, b].
static func dominant_seg(gen: Array, a: float, b: float) -> Dictionary:
	var best := 0
	var best_len := -1.0
	for i in gen.size():
		var lo := float(gen[i].start_ms) if i > 0 else -INF
		var hi := float(gen[i + 1].start_ms) if i + 1 < gen.size() else INF
		var l := minf(hi, b) - maxf(lo, a)
		if l > best_len:
			best_len = l
			best = i
	return gen[best]


## Tempo gegen ein Wahrheits-Segment. exact: >= 95 % der Strecke auf +-0,5 %.
## alt_factor: gemeldete Alternative, die trifft (0 = keine). diag_factor: Standard-Faktor, der
## treffen wuerde (nur Diagnose, zaehlt nicht). ratio = BPM_gen / BPM_wahr des Hauptsegments.
static func tempo_eval(gen: Array, truth: Dictionary, alternatives: Array = []) -> Dictionary:
	var a := float(truth.start_ms)
	var b := float(truth.end_ms)
	var tb := float(truth.beat_ms)
	var res := {"exact": tempo_share(gen, tb, a, b) >= 0.95, "alt_factor": 0.0, "diag_factor": 0.0,
			"ratio": tb / float(dominant_seg(gen, a, b).beat_ms)}
	if res.exact:
		return res
	for f in alternatives:
		if float(f) > 0.0 and tempo_share(gen, tb, a, b, float(f)) >= 0.95:
			res.alt_factor = float(f)
			break
	for f in DIAG_FACTORS:
		if tempo_share(gen, tb, a, b, f) >= 0.95:
			res.diag_factor = f
			break
	return res


## Lage des erzeugten Gitters gegen die Schlaege der Map, Schlag fuer Schlag verfolgt.
## offset_ms: Median von (erzeugter Schlag - Schlag der Map), auf +-halben Schlag gefaltet
## (+ = erzeugt zu spaet). drift_ms: Abweichung am letzten minus am ersten Schlag.
static func phase_track(gen: Array, truth: Dictionary) -> Dictionary:
	var tb := float(truth.beat_ms)
	var ds: Array = []
	var prev := 0.0
	var k := int(ceil((float(truth.start_ms) - float(truth.downbeat_ms)) / tb - 1e-9))
	var t := float(truth.downbeat_ms) + k * tb
	while t <= float(truth.end_ms) + 1e-6:
		var gs = gen[seg_at(gen, t)]
		var gb := float(gs.beat_ms)
		var d := -wrap_c(t - float(gs.start_ms), gb)
		if not ds.is_empty():
			while d - prev > gb * 0.5:
				d -= gb
			while d - prev < -gb * 0.5:
				d += gb
		ds.append(d)
		prev = d
		k += 1
		t = float(truth.downbeat_ms) + k * tb
	if ds.is_empty():
		return {"offset_ms": NAN, "drift_ms": NAN, "n": 0}
	return {"offset_ms": wrap_c(median(ds), tb), "drift_ms": float(ds[-1]) - float(ds[0]), "n": ds.size()}


## Songs mit Tempowechsel: jede Grenze der Map braucht eine erzeugte Grenze auf +-1 Schlag, und
## jedes Segment (ohne je 1 Schlag Rand) muss zu >= 90 % das richtige Tempo haben.
static func segments_eval(gen: Array, truth: Array) -> Dictionary:
	var b_ok := 0
	var s_ok := 0
	var cause := ""
	for i in truth.size():
		var ts = truth[i]
		var tb := float(ts.beat_ms)
		if i > 0:
			var hit := false
			for j in range(1, gen.size()):
				if absf(float(gen[j].start_ms) - float(ts.start_ms)) <= tb:
					hit = true
			if hit:
				b_ok += 1
			elif cause == "":
				cause = "Grenze bei %.0f ms fehlt" % float(ts.start_ms)
		var a := float(ts.start_ms)
		var b := float(ts.end_ms)
		if b - a > 3.0 * tb:
			a += tb
			b -= tb
		if tempo_share(gen, tb, a, b) >= 0.9:
			s_ok += 1
		elif cause == "" or gen.size() <= 1:
			cause = "Tempo in Segment %d falsch (Map %.2f BPM, erzeugt %.2f)" % [i + 1, 60000.0 / tb,
					60000.0 / float(dominant_seg(gen, a, b).beat_ms)]
	if gen.size() <= 1:
		cause = "kein Tempowechsel erkannt; " + cause
	var nb := truth.size() - 1
	return {"ok": b_ok == nb and s_ok == truth.size(), "bound_ok": b_ok, "bound_n": nb,
			"seg_ok": s_ok, "seg_n": truth.size(), "cause": cause}


## Taktanfang: erzeugter Taktanfang (nahe der Songmitte) gegen den der Map, modulo Taktlaenge.
## ok = gleiche Taktart und weniger als ein halber Schlag daneben.
static func downbeat_eval(gen: Array, truth: Dictionary) -> Dictionary:
	var tb := float(truth.beat_ms)
	var tm := (float(truth.start_ms) + float(truth.end_ms)) * 0.5
	var gs := dominant_seg(gen, float(truth.start_ms), float(truth.end_ms))
	var gbar := float(gs.beat_ms) * int(gs.get("meter", 4))
	var g := float(gs.get("downbeat_ms", gs.start_ms))
	g += roundf((tm - g) / gbar) * gbar
	var tbar := tb * int(truth.meter)
	var d := wrap_c(g - float(truth.downbeat_ms), tbar)
	var same_meter := int(gs.get("meter", 4)) == int(truth.meter)
	return {"ok": same_meter and absf(d) < tb * 0.5, "shift_beats": int(roundf(d / tb)),
			"meter_gen": int(gs.get("meter", 4)), "meter_true": int(truth.meter)}


## Eins-zu-eins-Zuordnung zweier sortierter Zeitlisten (jede Note hoechstens einmal), +-tol.
static func match_count(a: Array, b: Array, tol: float = NOTE_TOL_MS) -> int:
	var i := 0
	var j := 0
	var m := 0
	while i < a.size() and j < b.size():
		var d := float(a[i]) - float(b[j])
		if absf(d) <= tol:
			m += 1
			i += 1
			j += 1
		elif d < 0.0:
			i += 1
		else:
			j += 1
	return m


## Pearson-Korrelation. Ohne Streuung in einer Reihe -> NAN.
static func pearson(x: Array, y: Array) -> float:
	var n := mini(x.size(), y.size())
	if n < 2:
		return NAN
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += float(x[i])
		my += float(y[i])
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		var dx := float(x[i]) - mx
		var dy := float(y[i]) - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	if sxx <= 0.0 or syy <= 0.0:
		return NAN
	return sxy / sqrt(sxx * syy)


static func density_curve(times: Array, t_end: float, win: float = DENS_WIN_MS) -> Array:
	var n := maxi(int(ceil(t_end / win)), 1)
	var c: Array = []
	c.resize(n)
	c.fill(0.0)
	for t in times:
		var k := int(floor(float(t) / win))
		if k >= 0 and k < n:
			c[k] += 1.0
	return c


## Korrelation der Notendichte (Noten je 2-s-Fenster ab 0 bis zur letzten Note beider Maps).
static func density_corr(a: Array, b: Array, win: float = DENS_WIN_MS) -> float:
	if a.is_empty() or b.is_empty():
		return NAN
	var t_end := maxf(float(a[-1]), float(b[-1])) + 1.0
	return pearson(density_curve(a, t_end, win), density_curve(b, t_end, win))


## Anteil der erzeugten Holds, die zu mindestens der Haelfte ihrer Laenge unter einem Hold der
## Menschen-Map (beliebige Spalte) liegen. Keine erzeugten Holds -> 0.
static func hold_overlap(gen_holds: Array, human_holds: Array) -> float:
	if gen_holds.is_empty():
		return 0.0
	var hu := merge_intervals(human_holds)
	var ok := 0
	for h in gen_holds:
		var l := float(h[1]) - float(h[0])
		if l > 0.0 and inter_len([[float(h[0]), float(h[1])]], hu) >= 0.5 * l:
			ok += 1
	return float(ok) / gen_holds.size()


static func star_in_band(profile: String, stars: float) -> bool:
	var b: Array = STAR_BANDS[profile]
	return stars >= b[0] and stars <= b[1]


## Abstand zum Band (0 = im Band).
static func star_band_dist(profile: String, stars: float) -> float:
	var b: Array = STAR_BANDS[profile]
	return maxf(maxf(b[0] - stars, stars - b[1]), 0.0)


## Menschen-Diff, deren Sterne der Bandmitte am naechsten sind; -1, wenn keine innerhalb
## Band +- PARTNER_STAR_SLACK liegt (dann gibt es keinen fairen Vergleich gleicher Dichte).
static func pick_human_diff(diffs: Array, profile: String) -> int:
	var b: Array = STAR_BANDS[profile]
	var mid: float = (b[0] + b[1]) * 0.5
	var best := -1
	var best_d := INF
	for i in diffs.size():
		var st := float(diffs[i].get("stars", -1.0))
		if st <= 0.0 or st < b[0] - PARTNER_STAR_SLACK or st > b[1] + PARTNER_STAR_SLACK:
			continue
		if absf(st - mid) < best_d:
			best_d = absf(st - mid)
			best = i
	return best


## Anteil der Noten, die auf dem eigenen Gitter liegen (1/24-Schlag deckt 1/8 und 1/6), +-tol.
static func on_grid_share(times: Array, segs: Array, tol: float = 2.0) -> float:
	if times.is_empty() or segs.is_empty():
		return NAN
	var ok := 0
	for t in times:
		var s = segs[seg_at(segs, float(t))]
		if absf(wrap_c(float(t) - float(s.start_ms), float(s.beat_ms) / 24.0)) <= tol:
			ok += 1
	return float(ok) / times.size()


static func _n(v):
	# JSON kennt kein NAN/INF: als null ablegen
	if v is float and (is_nan(v) or is_inf(v)):
		return null
	return v


static func _times(notes: Array) -> Array:
	var t: Array = []
	for n in notes:
		t.append(float(n.t_ms))
	t.sort()
	return t


## Alle Kennzahlen eines Songs. truth: siehe load_truth. Ergebnis ist JSON-faehig.
static func song_record(file: String, truth: Dictionary, prod: Dictionary, time_ms: float, dur_ms: float) -> Dictionary:
	var rec := {"file": file, "split": split_of(file), "ok": bool(prod.get("ok", false)),
			"error": str(prod.get("error", "")), "dur_ms": dur_ms, "time_ms": time_ms,
			"time_norm_ms": time_ms * 240000.0 / maxf(dur_ms, 30000.0),
			"n4k": (truth.diffs4k as Array).size(), "prof": {}, "stars": {},
			"stage_ms": prod.get("stage_ms", {}), "confidence": prod.get("confidence", -1.0)}
	var ts := truth_segments(truth.reds, truth.t0, truth.t1)
	var tsegs: Array = ts.segments
	rec["nseg"] = tsegs.size()
	rec["effect"] = ts.effect
	rec["single"] = tsegs.size() == 1
	if tsegs.is_empty():
		rec["truth_bad"] = "Map ohne rote Linie"
		return rec
	rec["bpm"] = 60000.0 / float(tsegs[0].beat_ms)
	var gs: Array = prod.get("segments", [])
	var timing_note := ""
	if rec.ok and not gs.is_empty():
		rec["bpm_gen"] = 60000.0 / float(dominant_seg(gs, truth.t0, truth.t1).beat_ms)
		rec["nseg_gen"] = gs.size()
		if rec.single:
			var t0seg: Dictionary = tsegs[0].duplicate()
			t0seg.start_ms = truth.t0
			t0seg.end_ms = truth.t1
			var te := tempo_eval(gs, t0seg, prod.get("alternatives", []))
			rec["tempo_exact"] = te.exact
			rec["tempo_alt"] = te.exact or te.alt_factor != 0.0
			rec["ratio"] = te.ratio
			rec["diag_factor"] = te.diag_factor
			if te.exact:
				var ph := phase_track(gs, t0seg)
				rec["offset_ms"] = _n(ph.offset_ms)
				rec["drift_ms"] = _n(ph.drift_ms)
				var db := downbeat_eval(gs, t0seg)
				rec["downbeat_ok"] = db.ok
				rec["downbeat_shift"] = db.shift_beats
				rec["meter_gen"] = db.meter_gen
				rec["meter_true"] = db.meter_true
				if absf(ph.offset_ms) > NOTE_TOL_MS:
					timing_note = "Versatz %+.0f ms" % ph.offset_ms
				elif absf(ph.drift_ms) > NOTE_TOL_MS:
					timing_note = "Drift %+.0f ms" % ph.drift_ms
			else:
				timing_note = "Tempo falsch (x%.3f)" % te.ratio
		elif not ts.effect:
			var se := segments_eval(gs, tsegs)
			rec["seg_ok"] = se.ok
			rec["seg_share"] = float(se.seg_ok) / se.seg_n
			rec["seg_cause"] = se.cause
			if not se.ok:
				timing_note = "Tempowechsel nicht getroffen"
		else:
			timing_note = "Map mit Effekt-Linien"
	elif rec.single:
		rec["tempo_exact"] = false
		rec["tempo_alt"] = false
	elif not ts.effect:
		rec["seg_ok"] = false
		rec["seg_share"] = 0.0
		rec["seg_cause"] = "Erzeugung fehlgeschlagen: " + rec.error
	rec["timing_note"] = timing_note
	var caps: Dictionary = prod.get("caps", {})
	if rec.ok and caps.get("kiai", false):
		rec["kiai_iou"] = _n(interval_iou(prod.get("kiai", []), truth.kiai))
		rec["kiai_gen_ms"] = _total(merge_intervals(prod.get("kiai", [])))
		rec["kiai_true_ms"] = _total(merge_intervals(truth.kiai))
	for p in PROFILES:
		var hi := pick_human_diff(truth.diffs4k, p)
		if hi < 0:
			continue
		var hd: Dictionary = truth.diffs4k[hi]
		var e := {"human": hd.name, "hstars": hd.stars, "n_hum": (hd.times as Array).size(),
				"hold_share_hum": hd.hold_share}
		var ch = prod.get("charts", {}).get(p)
		if not rec.ok or ch == null or not ch.ok or (ch.notes as Array).is_empty():
			e["missing"] = true
			e["offered"] = (caps.get("profiles", []) as Array).has(p)
			rec.prof[p] = e
			continue
		var gt := _times(ch.notes)
		var m := match_count(gt, hd.times)
		e["n_gen"] = gt.size()
		e["prec"] = float(m) / gt.size()
		e["rec"] = float(m) / maxi((hd.times as Array).size(), 1)
		e["count_ratio"] = float(gt.size()) / maxi((hd.times as Array).size(), 1)
		e["dens"] = _n(density_corr(gt, hd.times))
		e["ongrid"] = _n(on_grid_share(gt, gs))
		if caps.get("holds", false) and float(hd.hold_share) >= 0.1:
			var gh: Array = []
			for n in ch.notes:
				if float(n.end_ms) > float(n.t_ms):
					gh.append([float(n.t_ms), float(n.end_ms)])
			e["hold"] = hold_overlap(gh, hd.holds)
			e["n_holds_gen"] = gh.size()
		e["lint"] = int(prod.get("lint", {}).get(p, -1))
		rec.prof[p] = e
	# Lint zaehlt fuer jedes erzeugte Profil, auch ohne Vergleichspartner
	var lint_all := {}
	for p in prod.get("lint", {}):
		lint_all[p] = int(prod.lint[p])
	rec["lint"] = lint_all
	return rec


# ===========================================================================
# Zusammenfassung ueber Songs
# ===========================================================================

static func _share(ok: int, n: int):
	return (float(ok) / n) if n > 0 else null


static func _has(r: Dictionary, k: String) -> bool:
	return r.has(k) and r[k] != null


## Kennzahlen ueber eine Menge. split "" = alle, sonst "tune" / "test".
static func aggregate(recs: Array, split: String = "") -> Dictionary:
	var n := 0
	var n_fail := 0
	var n_single := 0
	var n_exact := 0
	var n_alt := 0
	var n_multi := 0
	var n_seg_ok := 0
	var n_effect := 0
	var n_db_ok := 0
	var offs: Array = []
	var offs_signed: Array = []
	var drifts: Array = []
	var kiai: Array = []
	var times: Array = []
	var norms: Array = []
	var ongrid: Array = []
	var dens_all: Array = []
	var holds: Array = []
	var lint_sum := 0
	var lint_charts := 0
	var per := {}
	for p in PROFILES:
		per[p] = {"prec": [], "rec": [], "dens": [], "ratio": [], "missing": 0, "not_offered": 0,
				"stars_n": 0, "stars_ok": 0, "stars": []}
	for r in recs:
		if split != "" and r.get("split", "") != split:
			continue
		if r.has("truth_bad"):
			continue
		n += 1
		if not r.get("ok", false):
			n_fail += 1
		else:
			times.append(float(r.time_ms))
			norms.append(float(r.time_norm_ms))
		if r.get("single", false):
			n_single += 1
			if r.get("tempo_exact", false):
				n_exact += 1
				if _has(r, "offset_ms"):
					offs.append(absf(float(r.offset_ms)))
					offs_signed.append(float(r.offset_ms))
				if _has(r, "drift_ms"):
					drifts.append(absf(float(r.drift_ms)))
				if r.get("downbeat_ok", false):
					n_db_ok += 1
			if r.get("tempo_alt", false):
				n_alt += 1
		elif r.get("effect", false):
			n_effect += 1
		else:
			n_multi += 1
			if r.get("seg_ok", false):
				n_seg_ok += 1
		if _has(r, "kiai_iou"):
			kiai.append(float(r.kiai_iou))
		var prof: Dictionary = r.get("prof", {})
		for p in prof:
			var e: Dictionary = prof[p]
			var a: Dictionary = per[p]
			if e.get("missing", false):
				if e.get("offered", false):
					# angebotenes Profil ohne brauchbare Map zaehlt als 0
					a.missing += 1
					a.prec.append(0.0)
					a.rec.append(0.0)
					a.dens.append(0.0)
					dens_all.append(0.0)
				else:
					a.not_offered += 1
				continue
			a.prec.append(float(e.prec))
			a.rec.append(float(e.rec))
			a.ratio.append(float(e.count_ratio))
			if _has(e, "dens"):
				a.dens.append(float(e.dens))
				dens_all.append(float(e.dens))
			if _has(e, "hold"):
				holds.append(float(e.hold))
			if _has(e, "ongrid"):
				ongrid.append(float(e.ongrid))
		var lint: Dictionary = r.get("lint", {})
		for p in lint:
			if int(lint[p]) >= 0:
				lint_charts += 1
				lint_sum += int(lint[p])
		var st: Dictionary = r.get("stars", {})
		for p in st:
			if st[p] == null or not per.has(p):
				continue
			per[p].stars_n += 1
			per[p].stars.append(float(st[p]))
			if star_in_band(p, float(st[p])):
				per[p].stars_ok += 1
	var a := {"n": n, "n_fail": n_fail, "n_single": n_single, "n_exact": n_exact, "n_multi": n_multi,
			"n_effect": n_effect,
			"tempo_exact": _share(n_exact, n_single), "tempo_alt": _share(n_alt, n_single),
			"off_med": _n(median(offs)), "off_p95": _n(percentile(offs, 95.0)),
			"off_signed_med": _n(median(offs_signed)),
			"drift_med": _n(median(drifts)), "drift_p95": _n(percentile(drifts, 95.0)),
			"drift_max": _n(percentile(drifts, 100.0)),
			"seg_ok": _share(n_seg_ok, n_multi), "downbeat_ok": _share(n_db_ok, n_exact),
			"dens": _n(mean(dens_all)), "n_dens": dens_all.size(),
			"hold": _n(mean(holds)), "n_hold": holds.size(),
			"kiai": _n(mean(kiai)), "n_kiai": kiai.size(),
			"lint_sum": lint_sum, "lint_charts": lint_charts,
			"dur_med": _n(median(times)), "dur_norm_p95": _n(percentile(norms, 95.0)),
			"dur_norm_max": _n(percentile(norms, 100.0)), "n_dur": times.size(),
			"ongrid": _n(mean(ongrid)), "per": {}}
	var n10 := 0
	for d in drifts:
		if d <= 10.0:
			n10 += 1
	a["drift_share10"] = _share(n10, drifts.size())
	var stars_min = null
	var stars_n := 0
	for p in PROFILES:
		var q: Dictionary = per[p]
		var sh = _share(q.stars_ok, q.stars_n)
		a.per[p] = {"prec": _n(mean(q.prec)), "rec": _n(mean(q.rec)), "dens": _n(mean(q.dens)),
				"ratio": _n(median(q.ratio)), "n": (q.prec as Array).size(), "missing": q.missing,
				"not_offered": q.not_offered, "stars_share": sh, "stars_n": q.stars_n,
				"stars_med": _n(median(q.stars))}
		stars_n += q.stars_n
		if sh != null and (stars_min == null or sh < stars_min):
			stars_min = sh
	a["stars_min"] = stars_min
	a["stars_n"] = stars_n
	return a


## Zielgroesse der Abstimmung: gewichtete Summe der Zielerreichung, 0..1 (1 = alle Ziele erreicht).
## Nur im Prozess messbare Kennzahlen (keine Sterne, keine Dauer). Nicht messbare fallen heraus.
const WEIGHTS := {"tempo_exact": 3.0, "tempo_alt": 1.0, "offset": 3.0, "drift": 2.0, "seg": 1.0,
		"downbeat": 1.5, "prec": 2.0, "rec": 2.0, "dens": 1.0, "hold": 1.0, "kiai": 1.0, "lint": 1.0}

static func objective(a: Dictionary, weights: Dictionary = WEIGHTS) -> float:
	var parts := {}
	if a.tempo_exact != null:
		parts["tempo_exact"] = minf(float(a.tempo_exact) / 0.95, 1.0)
		parts["tempo_alt"] = minf(float(a.tempo_alt) / 0.99, 1.0)
	if a.off_med != null:
		# Anteil der Songs mit richtigem Tempo geht ein, sonst lohnt es sich, Songs zu verlieren
		var cover := float(a.n_exact) / maxi(int(a.n_single), 1)
		parts["offset"] = cover * 0.5 * (minf(4.0 / maxf(float(a.off_med), 0.01), 1.0) + minf(12.0 / maxf(float(a.off_p95), 0.01), 1.0))
		parts["drift"] = cover * minf(10.0 / maxf(float(a.drift_p95), 0.01), 1.0)
		parts["downbeat"] = cover * minf(float(a.downbeat_ok) / 0.85, 1.0)
	elif a.tempo_exact != null:
		parts["offset"] = 0.0
		parts["drift"] = 0.0
		parts["downbeat"] = 0.0
	if a.seg_ok != null:
		parts["seg"] = minf(float(a.seg_ok) / 0.8, 1.0)
	var h: Dictionary = a.per.get("Hard", {})
	if h.get("prec") != null:
		parts["prec"] = minf(float(h.prec) / 0.85, 1.0)
		parts["rec"] = minf(float(h.rec) / 0.75, 1.0)
	if a.dens != null:
		parts["dens"] = clampf(float(a.dens) / 0.8, 0.0, 1.0)
	if a.hold != null:
		parts["hold"] = minf(float(a.hold) / 0.6, 1.0)
	if a.kiai != null:
		parts["kiai"] = minf(float(a.kiai) / 0.6, 1.0)
	if int(a.lint_charts) > 0:
		parts["lint"] = 1.0 / (1.0 + float(a.lint_sum) / float(a.lint_charts))
	var s := 0.0
	var w := 0.0
	for k in parts:
		s += float(weights.get(k, 0.0)) * float(parts[k])
		w += float(weights.get(k, 0.0))
	return (s / w) if w > 0.0 else 0.0


# ===========================================================================
# Bericht
# ===========================================================================

static func _pct(v) -> String:
	return "–" if v == null else ("%.1f %%" % (float(v) * 100.0))


static func _f(v, digits: int = 1) -> String:
	if v == null:
		return "–"
	return String.num(float(v), digits)


static func _verdict(n: int, ok: bool, why_empty: String = "keine passenden Songs in der Menge") -> String:
	if n <= 0:
		return "nicht messbar, weil " + why_empty
	return "ja" if ok else "**nein**"


## Zeilen der Ziel-Tabelle: [Bereich, Kennzahl, Ziel, Ist, erreicht].
static func target_rows(a: Dictionary, caps: Dictionary) -> Array:
	var rows: Array = []
	var ns := int(a.n_single)
	var ne := int(a.n_exact)
	rows.append(["Takt", "Tempo exakt (±0,5 %), Maps mit einem Tempo", "≥ 95 %",
			"%s (n=%d)" % [_pct(a.tempo_exact), ns], _verdict(ns, a.tempo_exact != null and a.tempo_exact >= 0.95)])
	rows.append(["Takt", "Tempo exakt oder gemeldete Alternative trifft", "≥ 99 %",
			"%s (n=%d)" % [_pct(a.tempo_alt), ns], _verdict(ns, a.tempo_alt != null and a.tempo_alt >= 0.99)])
	rows.append(["Takt", "Offset-Fehler, Median / 95. Perzentil (nur richtiges Tempo)", "≤ 4 ms / ≤ 12 ms",
			"%s ms / %s ms (n=%d)" % [_f(a.off_med), _f(a.off_p95), ne],
			_verdict(ne, a.off_med != null and a.off_med <= 4.0 and a.off_p95 <= 12.0, "kein Song mit richtigem Tempo")])
	rows.append(["Takt", "Drift über den Song, 95. Perzentil (Median / Maximum / Anteil ≤ 10 ms)", "≤ 10 ms",
			"%s ms (%s ms / %s ms / %s; n=%d)" % [_f(a.drift_p95), _f(a.drift_med), _f(a.drift_max), _pct(a.drift_share10), ne],
			_verdict(ne, a.drift_p95 != null and a.drift_p95 <= 10.0, "kein Song mit richtigem Tempo")])
	rows.append(["Takt", "Tempowechsel: Grenzen ±1 Schlag und Tempo je Segment", "≥ 80 %",
			"%s (n=%d; %d Maps mit Effekt-Linien nicht gewertet)" % [_pct(a.seg_ok), int(a.n_multi), int(a.n_effect)],
			_verdict(int(a.n_multi), a.seg_ok != null and a.seg_ok >= 0.8)])
	rows.append(["Takt", "Taktanfang (Downbeat) stimmt", "≥ 85 %",
			"%s (n=%d)" % [_pct(a.downbeat_ok), ne],
			_verdict(ne, a.downbeat_ok != null and a.downbeat_ok >= 0.85, "kein Song mit richtigem Tempo")])
	var h: Dictionary = a.per.Hard
	rows.append(["Noten", "erzeugte Noten auf Menschen-Note (±15 ms), Hard", "≥ 85 %",
			"%s (n=%d, Notenzahl erzeugt/Mensch %s)" % [_pct(h.prec), int(h.n), _f(h.ratio, 2)],
			_verdict(int(h.n), h.prec != null and h.prec >= 0.85, "keine Menschen-4K-Diff im Hard-Band")])
	rows.append(["Noten", "Menschen-Noten getroffen (±15 ms), Hard", "≥ 75 %",
			"%s (n=%d)" % [_pct(h.rec), int(h.n)],
			_verdict(int(h.n), h.rec != null and h.rec >= 0.75, "keine Menschen-4K-Diff im Hard-Band")])
	rows.append(["Noten", "Korrelation der Dichtekurve (2-s-Fenster), alle Profile", "≥ 0,8",
			"%s (n=%d Paare)" % [_f(a.dens, 3), int(a.n_dens)],
			_verdict(int(a.n_dens), a.dens != null and a.dens >= 0.8, "kein Paar Profil/Menschen-Diff")])
	if caps.get("holds", false):
		rows.append(["Holds", "erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds)", "≥ 60 %",
				"%s (n=%d Paare)" % [_pct(a.hold), int(a.n_hold)], _verdict(int(a.n_hold), a.hold != null and a.hold >= 0.6)])
	else:
		rows.append(["Holds", "erzeugte Holds überlappen Holds der Map (Maps ≥ 10 % Holds)", "≥ 60 %",
				"nicht messbar, weil dieser Mapper keine Holds erzeugt", "**nein** (fehlt)"])
	if caps.get("kiai", false):
		rows.append(["Kiai", "Überlappung der Kiai-Abschnitte (IoU)", "≥ 0,6",
				"%s (n=%d)" % [_f(a.kiai, 3), int(a.n_kiai)], _verdict(int(a.n_kiai), a.kiai != null and a.kiai >= 0.6)])
	else:
		rows.append(["Kiai", "Überlappung der Kiai-Abschnitte (IoU)", "≥ 0,6",
				"nicht messbar, weil dieser Mapper kein Kiai erzeugt", "**nein** (fehlt)"])
	if caps.get("cols", false):
		var parts: Array = []
		for p in PROFILES:
			parts.append("%s %s" % [p, _pct(a.per[p].stars_share)])
		rows.append(["Stufen", "Sterne im Band, schlechtestes Profil", "≥ 90 %",
				"%s (%s; n=%d Diffs)" % [_pct(a.stars_min), ", ".join(parts), int(a.stars_n)],
				_verdict(int(a.stars_n), a.stars_min != null and a.stars_min >= 0.9, "keine Sterne berechnet (starcalc/python fehlt oder --no-stars)")])
		rows.append(["Spielbarkeit", "Regelverletzungen (AmChart.lint), Summe", "0",
				"%d in %d Diffs" % [int(a.lint_sum), int(a.lint_charts)],
				_verdict(int(a.lint_charts), int(a.lint_sum) == 0, "AmChart.lint fehlt")])
	else:
		rows.append(["Stufen", "Sterne im Band, schlechtestes Profil", "≥ 90 %",
				"nicht messbar, weil dieser Mapper keine 4K-Map erzeugt (Orbit ohne Spalten; nur 3 Stufen)", "**nein** (fehlt)"])
		rows.append(["Spielbarkeit", "Regelverletzungen (AmChart.lint), Summe", "0",
				"nicht messbar, weil die Noten keine Spalten haben", "**nein** (fehlt)"])
	rows.append(["Dauer", "ganzer Ablauf je Song, auf 4 min umgerechnet, 95. Perzentil (Maximum)", "≤ 15 s",
			"%s s (%s s; Median roh %s s; n=%d)" % [_f(_div(a.dur_norm_p95, 1000.0)), _f(_div(a.dur_norm_max, 1000.0)), _f(_div(a.dur_med, 1000.0)), int(a.n_dur)],
			_verdict(int(a.n_dur), a.dur_norm_p95 != null and a.dur_norm_p95 <= 15000.0)])
	return rows


static func _div(v, d: float):
	return null if v == null else float(v) / d


static func _table(head: Array, rows: Array) -> String:
	var s := "| " + " | ".join(head) + " |\n|" + "---|".repeat(head.size()) + "\n"
	for r in rows:
		var cells: Array = []
		for c in r:
			cells.append(str(c).replace("|", "/"))
		s += "| " + " | ".join(cells) + " |\n"
	return s


static func _tempo_cause(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "Erzeugung fehlgeschlagen: " + str(r.get("error", ""))
	var df := float(r.get("diag_factor", 0.0))
	if df != 0.0:
		return "Vielfaches: erzeugtes Tempo x%s wäre richtig" % String.num(df, 3)
	return "daneben: erzeugt %.2f BPM, Map %.2f BPM" % [float(r.get("bpm_gen", 0.0)), float(r.get("bpm", 0.0))]


static func _offset_cause(r: Dictionary) -> String:
	var o := float(r.offset_ms)
	var beat := 60000.0 / maxf(float(r.get("bpm", 120.0)), 1.0)
	if absf(absf(o) - beat * 0.5) < beat * 0.08:
		return "halber Schlag versetzt (Gitter auf dem Off-Beat)"
	if absf(absf(o) - beat * 0.25) < beat * 0.06:
		return "Viertelschlag versetzt"
	return "Gitter %s als die Map" % ("später" if o > 0.0 else "früher")


static func _note_cause(r: Dictionary, e: Dictionary) -> String:
	if e.get("missing", false):
		return "kein brauchbares Profil erzeugt"
	if str(r.get("timing_note", "")) != "":
		return str(r.timing_note)
	var cr := float(e.get("count_ratio", 1.0))
	if cr > 1.3 or cr < 0.77:
		return "Notenzahl erzeugt/Mensch = %.2f" % cr
	return "andere Stellen gewählt als der Mensch (Takt stimmt)"


## Liste der schlechtesten Songs. items: [[sort_key (gross = schlecht), Zeile-Array]].
static func _worst(title: String, head: Array, items: Array, limit: int = 20) -> String:
	var s := "### " + title + "\n\n"
	if items.is_empty():
		return s + "Keine Einträge.\n\n"
	items.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var rows: Array = []
	for i in mini(limit, items.size()):
		rows.append(items[i][1])
	return s + _table(head, rows) + "\n"


static func _short(file: String) -> String:
	var b := file.get_basename()
	return b if b.length() <= 60 else b.substr(0, 57) + "..."


static func worst_lists(recs: Array, caps: Dictionary) -> String:
	var tempo: Array = []
	var off: Array = []
	var drift: Array = []
	var seg: Array = []
	var db: Array = []
	var prec: Array = []
	var recl: Array = []
	var dens: Array = []
	var hold: Array = []
	var kiai: Array = []
	var stars: Array = []
	var lint: Array = []
	var dur: Array = []
	for r in recs:
		if r.has("truth_bad"):
			continue
		var name := "%s (%s)" % [_short(r.file), "P" if r.split == "test" else "A"]
		if r.get("single", false):
			if not r.get("tempo_exact", false):
				var ratio := float(r.get("ratio", 0.0))
				var key := absf(log(ratio)) if ratio > 0.0 else 99.0
				tempo.append([key, [name, _f(r.get("bpm"), 2), _f(r.get("bpm_gen"), 2), _tempo_cause(r)]])
			else:
				if _has(r, "offset_ms"):
					off.append([absf(float(r.offset_ms)), [name, "%+.1f" % float(r.offset_ms), _offset_cause(r)]])
				if _has(r, "drift_ms"):
					var beats := float(r.dur_ms) / (60000.0 / maxf(float(r.bpm), 1.0))
					drift.append([absf(float(r.drift_ms)), [name, "%+.1f" % float(r.drift_ms),
							"Tempo um %.4f %% daneben (erzeugt %.3f, Map %.3f BPM)%s" % [(float(r.ratio) - 1.0) * 100.0,
							float(r.bpm_gen), float(r.bpm), "" if int(r.get("nseg_gen", 1)) <= 1 else "; %d erzeugte Segmente" % int(r.nseg_gen)]]])
				if not r.get("downbeat_ok", false):
					var c := "Taktart %d statt %d" % [int(r.get("meter_gen", 4)), int(r.get("meter_true", 4))]
					if int(r.get("meter_gen", 4)) == int(r.get("meter_true", 4)):
						c = "um %d Schlag/Schläge verschoben" % int(r.get("downbeat_shift", 0))
						if int(r.get("downbeat_shift", 0)) == 0:
							c = "Gitter um etwa einen halben Schlag versetzt"
					db.append([absf(float(r.get("offset_ms", 0.0))) + 1.0, [name, c]])
		elif r.has("seg_ok") and not r.seg_ok:
			seg.append([1.0 - float(r.get("seg_share", 0.0)), [name, str(int(r.nseg)), str(int(r.get("nseg_gen", 0))), str(r.get("seg_cause", ""))]])
		var prof: Dictionary = r.get("prof", {})
		if prof.has("Hard") and (not prof.Hard.get("missing", false) or prof.Hard.get("offered", false)):
			var e: Dictionary = prof.Hard
			var c := _note_cause(r, e)
			prec.append([1.0 - float(e.get("prec", 0.0)), [name, _pct(e.get("prec", 0.0)), str(e.human), c]])
			recl.append([1.0 - float(e.get("rec", 0.0)), [name, _pct(e.get("rec", 0.0)), str(e.human), c]])
		for p in prof:
			var e: Dictionary = prof[p]
			if _has(e, "dens"):
				dens.append([1.0 - float(e.dens), [name, p, _f(e.dens, 3), _note_cause(r, e)]])
			if _has(e, "hold"):
				hold.append([1.0 - float(e.hold), [name, p, _pct(e.hold),
						"keine Holds erzeugt" if int(e.get("n_holds_gen", 0)) == 0 else "Holds an anderen Stellen (%d erzeugt)" % int(e.n_holds_gen)]])
		if _has(r, "kiai_iou"):
			var kc := "Abschnitte an anderer Stelle"
			if float(r.get("kiai_gen_ms", 0.0)) <= 0.0:
				kc = "kein Kiai erzeugt, Map hat %.0f s" % (float(r.kiai_true_ms) / 1000.0)
			elif float(r.get("kiai_true_ms", 0.0)) <= 0.0:
				kc = "Kiai erzeugt (%.0f s), Map hat keins" % (float(r.kiai_gen_ms) / 1000.0)
			kiai.append([1.0 - float(r.kiai_iou), [name, _f(r.kiai_iou, 3), kc]])
		var st: Dictionary = r.get("stars", {})
		for p in st:
			if st[p] != null and STAR_BANDS.has(p):
				var d := star_band_dist(p, float(st[p]))
				if d > 0.0:
					stars.append([d, [name, p, _f(st[p], 2), "%s–%s" % [_f(STAR_BANDS[p][0]), _f(STAR_BANDS[p][1])],
							("zu leicht" if float(st[p]) < STAR_BANDS[p][0] else "zu schwer") + " (%.0f BPM)" % float(r.get("bpm", 0.0))]])
		var ls := 0
		var lint_d: Dictionary = r.get("lint", {})
		for p in lint_d:
			ls += maxi(int(lint_d[p]), 0)
		if ls > 0:
			lint.append([float(ls), [name, str(ls), "siehe AmChart.lint je Profil: " + JSON.stringify(lint_d)]])
		if r.get("ok", false):
			var sm: Dictionary = r.get("stage_ms", {})
			var big := ""
			var big_v := -1.0
			for k in sm:
				if float(sm[k]) > big_v:
					big_v = float(sm[k])
					big = k
			dur.append([float(r.time_norm_ms), [name, _f(float(r.time_norm_ms) / 1000.0), _f(float(r.time_ms) / 1000.0),
					_f(float(r.dur_ms) / 1000.0, 0), ("größter Anteil: %s (%.1f s)" % [big, big_v / 1000.0]) if big != "" else "–"]])
	var s := "(P) = Prüf-Menge, (A) = Abstimm-Menge. Ursache = aus den Messwerten abgeleitete Einordnung, keine Hörprüfung.\n\n"
	s += _worst("Tempo falsch (Maps mit einem Tempo)", ["Song", "BPM Map", "BPM erzeugt", "Ursache"], tempo)
	s += _worst("Offset-Fehler", ["Song", "Fehler ms (+ = zu spät)", "Ursache"], off)
	s += _worst("Drift", ["Song", "Drift ms", "Ursache"], drift)
	s += _worst("Tempowechsel nicht getroffen", ["Song", "Segmente Map", "Segmente erzeugt", "Ursache"], seg)
	s += _worst("Taktanfang falsch", ["Song", "Ursache"], db)
	s += _worst("Noten: erzeugte Noten ohne Menschen-Note (Hard)", ["Song", "Anteil auf Menschen-Note", "Menschen-Diff", "Ursache"], prec)
	s += _worst("Noten: Menschen-Noten nicht getroffen (Hard)", ["Song", "Anteil getroffen", "Menschen-Diff", "Ursache"], recl)
	s += _worst("Dichtekurve", ["Song", "Profil", "Korrelation", "Ursache"], dens)
	if caps.get("holds", false):
		s += _worst("Holds", ["Song", "Profil", "Anteil überlappend", "Ursache"], hold)
	else:
		s += "### Holds\n\nEntfällt: dieser Mapper erzeugt keine Holds.\n\n"
	if caps.get("kiai", false):
		s += _worst("Kiai", ["Song", "IoU", "Ursache"], kiai)
	else:
		s += "### Kiai\n\nEntfällt: dieser Mapper erzeugt kein Kiai.\n\n"
	if caps.get("cols", false):
		s += _worst("Sterne außerhalb des Bands", ["Song", "Profil", "Sterne", "Band", "Ursache"], stars)
		s += _worst("Regelverletzungen", ["Song", "Anzahl", "Ursache"], lint)
	else:
		s += "### Sterne, Regelverletzungen\n\nEntfällt: dieser Mapper erzeugt keine 4K-Map (keine Spalten).\n\n"
	s += _worst("Dauer", ["Song", "s auf 4 min", "s roh", "Songlänge s", "Ursache"], dur)
	return s


## Ganzer Bericht. runs: [{name: "alt"|"neu", caps, recs, info: {...}}], tune_log: Text oder "".
static func render_report(runs: Array, tune_log: String = "") -> String:
	var s := "# OMEN Auto-Mapper 4K: Prüfstand-Bericht\n\n"
	s += "Erzeugt von `tools/automap_bench.gd` am %s. Nicht von Hand ändern; neu erzeugen (Befehle unten).\n\n" % Time.get_date_string_from_system()
	s += "Der Bericht bewertet gegen die Ziel-Tabelle aus `docs/automap/spec.md`. Maßgeblich ist die **Prüf-Menge** (30 % der Maps, wird nie zum Abstimmen benutzt). „nicht messbar“ heißt: Für diese Zeile gibt es keinen Wert; sie gilt nicht als erreicht.\n\n"
	for run in runs:
		var recs: Array = run.recs
		var caps: Dictionary = run.caps
		var info: Dictionary = run.get("info", {})
		var label := "alter Mapper (`AudioMapper`, Orbit) über Adapter" if run.name == "alt" else "neue Module (AmGrid, AmFeatures, AmChart, AutoMapper4K)"
		s += "## Mapper „%s“: %s\n\n" % [run.name, label]
		var at := aggregate(recs, "test")
		var au := aggregate(recs, "tune")
		var bad := 0
		for r in recs:
			if r.has("truth_bad"):
				bad += 1
		s += "- Gemessen: %d Sets (Prüf-Menge %d, Abstimm-Menge %d); %d ohne rote Linie übersprungen; Erzeugung fehlgeschlagen bei %d (Prüf) / %d (Abstimm).\n" % [recs.size() - bad, int(at.n), int(au.n), bad, int(at.n_fail), int(au.n_fail)]
		for k in info:
			s += "- %s: %s\n" % [k, str(info[k])]
		s += "\n### Ziel-Tabelle, Prüf-Menge\n\n"
		var rt := target_rows(at, caps)
		var ru := target_rows(au, caps)
		var rows: Array = []
		var n_yes := 0
		for i in rt.size():
			rows.append([rt[i][0], rt[i][1], rt[i][2], rt[i][3], rt[i][4], ru[i][3]])
			if rt[i][4] == "ja":
				n_yes += 1
		s += _table(["Bereich", "Kennzahl", "Ziel", "Ist (Prüf-Menge)", "erreicht", "Ist (Abstimm-Menge)"], rows)
		s += "\n**%d von %d Zielen erreicht.**\n\n" % [n_yes, rt.size()]
		s += "Zusatzwerte (Prüf-Menge): systematischer Versatz (Median mit Vorzeichen, + = erzeugt zu spät) %s ms; Noten auf dem eigenen Gitter %s.\n\n" % [_f(at.off_signed_med), _pct(at.ongrid)]
		s += "### Noten je Profil, Prüf-Menge\n\n"
		var prow: Array = []
		for p in PROFILES:
			var q: Dictionary = at.per[p]
			var note := ""
			if int(q.not_offered) > 0 and int(q.n) == 0:
				note = "Profil fehlt in diesem Mapper"
			elif int(q.missing) > 0:
				note = "%d ohne brauchbare Map (als 0 gezählt)" % int(q.missing)
			prow.append([p, str(int(q.n)), _pct(q.prec), _pct(q.rec), _f(q.dens, 3), _f(q.ratio, 2),
					("%s (Median %s, n=%d)" % [_pct(q.stars_share), _f(q.stars_med, 2), int(q.stars_n)]) if int(q.stars_n) > 0 else "–", note])
		s += _table(["Profil", "Paare", "auf Menschen-Note", "Menschen-Noten getroffen", "Dichte-Korrelation", "Notenzahl erzeugt/Mensch", "Sterne im Band", "Hinweis"], prow)
		s += "\n### Schlechteste 20 Songs je Kennzahl\n\n"
		s += worst_lists(recs, caps)
	if tune_log != "":
		s += "## Letzte Abstimmung (`tools/automap_tune.gd`)\n\n" + tune_log + "\n"
	s += DEFINITIONS
	return s


const DEFINITIONS := """## So wird gemessen

- **Wahrheit**: rote Linien, Noten, Holds und Kiai der Menschen-Maps in `maps/`. Zeitbezug je Set: die 4K-Diff mit den meisten Noten, sonst die Diff mit den meisten Objekten. Rote Linien mit gleichem Tempo (0,05 %), die auf dem laufenden Gitter liegen (2 ms), gelten nicht als neues Segment. Bewertet wird zwischen erster und letzter Note.
- **Aufteilung**: `sha256(Dateiname klein)`, erste 8 Hex-Stellen, modulo 100: unter 70 = Abstimm-Menge, sonst Prüf-Menge. Fest, unabhängig von Reihenfolge und Lauf.
- **Tempo exakt**: Auf mindestens 95 % der Strecke weicht das erzeugte Tempo höchstens 0,5 % ab. Zählt nur Maps mit genau einem Segment. Fehlgeschlagene Erzeugung zählt als falsch.
- **Alternative**: Zusätzlich gilt ein Song als getroffen, wenn ein vom Mapper **gemeldeter** Faktor das Tempo richtig macht. Faktoren, die der Mapper nicht meldet, zählen nicht (stehen nur als Ursache in der Liste).
- **Offset-Fehler**: Für jeden Schlag der Map der Abstand zum nächsten erzeugten Schlag, über den Song fortlaufend verfolgt; Median, gefaltet auf ± halben Schlag. Ein um einen halben Schlag versetztes Gitter zählt also mit vollem Fehler. Nur Songs mit exaktem Tempo.
- **Drift**: Abstand am letzten Schlag minus Abstand am ersten Schlag. Als erreicht gilt die Zeile, wenn das 95. Perzentil ≤ 10 ms ist; Maximum und Anteil stehen daneben.
- **Tempowechsel**: Jede Segmentgrenze der Map braucht eine erzeugte Grenze auf ±1 Schlag, und jedes Segment (ohne je einen Schlag Rand) hat zu ≥ 90 % das richtige Tempo. Maps, die rote Linien als Effekt benutzen (Segment kürzer als 2 Schläge, BPM unter 15 oder über 1000), werden nicht gewertet und gezählt ausgewiesen.
- **Taktanfang**: gleiche Taktart und erzeugter Taktanfang weniger als einen halben Schlag neben dem der Map (rote Linie = Taktanfang). Nenner: Songs mit exaktem Tempo; ein falscher Offset zählt hier ebenfalls als falsch.
- **Noten**: Vergleichspartner je Profil ist die 4K-Diff des Sets, deren Sterne der Bandmitte am nächsten sind und höchstens 0,5 Sterne außerhalb des Bands liegen; sonst gibt es kein Paar. Zuordnung eins zu eins nach Zeit (±15 ms), Spalte egal; ein Akkord braucht also einen Akkord. Die Notenzahl wird nicht künstlich angeglichen; das Verhältnis steht daneben, weil es beide Werte begrenzt. Mittelwert über Songs. Ein angebotenes Profil ohne brauchbare Map zählt 0.
- **Dichtekurve**: Noten je 2-s-Fenster ab 0 ms, Pearson-Korrelation je Paar, Mittel über alle Paare.
- **Holds**: nur Paare, deren Menschen-Diff ≥ 10 % Holds hat. Ein erzeugter Hold zählt, wenn mindestens die Hälfte seiner Länge unter einem Hold der Map liegt (Spalte egal). Keine erzeugten Holds = 0.
- **Kiai**: IoU der Zeitabschnitte je Song; Songs, bei denen weder Map noch Erzeugnis Kiai haben, zählen nicht; hat nur eine Seite Kiai, ist der Wert 0.
- **Sterne**: rosu-pp über `StarService`/`tools/starcalc.py`, ein Aufruf für alle erzeugten Diffs. Gewertet wird das schlechteste Profil. Die Ausnahme der Spec für ruhige Songs wird nicht angerechnet (der Prüfstand kann sie nicht beurteilen).
- **Regelverletzungen**: Summe der Meldungen von `AmChart.lint` über alle erzeugten Diffs.
- **Dauer**: Zeit im Prozess je Song, umgerechnet auf 4 Minuten Songlänge. Beim alten Mapper: Dekodieren, Analyse und drei Notenlisten, ohne Schreiben der .osz.

## Grenzen der Messung

- Die Menschen-Maps sind selbst nicht fehlerfrei: Ihr Offset streut um einige Millisekunden. Wie stark, misst der Prüfstand nicht; ein Median-Ziel von 4 ms liegt nahe an dieser Streuung.
- Noten-Kennzahlen messen Übereinstimmung mit **einer** Menschen-Map. Zwei gute Mapper wählen nicht dieselben Stellen; 100 % sind nicht zu erwarten. Wie hoch zwei Menschen-Maps desselben Songs übereinstimmen, ist hier nicht gemessen.
- Ob sich eine Map gut spielt und ob Muster zur Musik passen, misst keine dieser Zahlen. Dafür ist die Hörprobe da.

## Aufruf

```
# Prüfstand, alle Maps (ein Prozess; schreibt docs/automap/report.md)
timeout 7200 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_bench.gd -- --maps <maps-ordner>
#   --mapper old|new|auto   --limit N   --set tune|test   --stages   --no-stars   --resume   --report-only
# Abstimmung (sucht params, schreibt data/automap/params.json, Protokoll vorher/nachher auf der Prüf-Menge)
timeout 7200 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_tune.gd -- --maps <maps-ordner> [--songs 16] [--test-songs 8] [--passes 2] [--points 5] [--knobs grid.x:0.1:0.9,...]
# Hörprobe: Klick je Note (Tonhöhe je Spalte) und je Schlag über dem Song -> user://automap_check/<name>.ogg
timeout 600 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tools/automap_bench.gd -- --click <audio-datei oder -> <set.osz> [Diff-Teilname]
# Tests der Kennzahlen
timeout 300 ./Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_am_bench_tests.gd
```
"""


# ===========================================================================
# Wahrheit laden
# ===========================================================================

## Menschen-Set lesen. {ok, error, audio_name, reds, t0, t1, kiai, diffs4k: [{name, file, times,
## holds, hold_share, stars}], ref}. stars: {innerer .osu-Name: {stars,..}} aus StarService.
static func load_truth(osz_path: String, stars: Dictionary = {}) -> Dictionary:
	var imp: Dictionary = OszImporter._import_uncached(osz_path)
	if not imp.ok:
		return {"ok": false, "error": str(imp.error)}
	var ref: Beatmap = null
	var ref_4k := false
	var diffs: Array = []
	var t0 := INF
	var t1 := -INF
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		if bm.hit_objects.is_empty():
			continue
		var is4k := bm.is_mania() and bm.column_count() == 4
		t0 = minf(t0, bm.hit_objects[0].time)
		t1 = maxf(t1, bm.hit_objects[-1].time)
		if ref == null or (is4k and not ref_4k) or (is4k == ref_4k and bm.hit_objects.size() > ref.hit_objects.size()):
			ref = bm
			ref_4k = is4k
		if not is4k:
			continue
		var times: Array = []
		var holds: Array = []
		for o in bm.hit_objects:
			var mn := o as ManiaNote
			if mn == null:
				continue
			times.append(mn.time)
			if mn.is_hold and mn.hold_end > mn.time:
				holds.append([mn.time, mn.hold_end])
		times.sort()
		var st := -1.0
		var se = stars.get(d.osu_filename)
		if se is Dictionary and se.has("stars"):
			st = float(se.stars)
		diffs.append({"name": bm.version_name(), "file": d.osu_filename, "times": times, "holds": holds,
				"hold_share": float(holds.size()) / maxi(times.size(), 1), "stars": st})
	if ref == null:
		return {"ok": false, "error": "keine Diff mit Noten"}
	var reds: Array = []
	for tp in ref.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append({"time": tp.time, "beat_ms": tp.beat_length, "meter": maxi(tp.meter, 1)})
	var kiai: Array = []
	for iv in ref.kiai_intervals:
		kiai.append([maxf(float(iv.start), 0.0), minf(float(iv.end), t1 + 5000.0)])
	return {"ok": true, "error": "", "audio_name": ref.audio_filename(), "reds": reds, "t0": t0, "t1": t1,
			"kiai": merge_intervals(kiai), "diffs4k": diffs, "ref": ref.version_name()}


## Datei aus dem Archiv holen (Gross/Klein egal) und als Datei ablegen. "" bei Fehler.
static func extract_file(osz_path: String, inner: String, out_base: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(osz_path) != OK:
		return ""
	var hit := ""
	for f in reader.get_files():
		if f.to_lower() == inner.to_lower():
			hit = f
	if hit == "":
		reader.close()
		return ""
	var bytes := reader.read_file(hit)
	reader.close()
	var out := out_base + "." + hit.get_extension().to_lower()
	var fa := FileAccess.open(out, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_buffer(bytes)
	fa.close()
	return out


## Minimale 4K-.osu (nur fuer die Sterne-Berechnung der Stufen-Ausgabe).
static func osu_text(segs: Array, notes: Array, profile: String) -> String:
	var l: Array = ["osu file format v14", "", "[General]", "AudioFilename: audio.mp3", "Mode: 3", "",
			"[Metadata]", "Title:bench", "Artist:bench", "Creator:OMEN Auto", "Version:" + profile, "",
			"[Difficulty]", "HPDrainRate:7", "CircleSize:4", "OverallDifficulty:7", "ApproachRate:5",
			"SliderMultiplier:1.4", "SliderTickRate:1", "", "[TimingPoints]"]
	for s in segs:
		l.append("%.2f,%.6f,%d,2,0,60,1,0" % [float(s.start_ms), float(s.beat_ms), int(s.get("meter", 4))])
	l.append("")
	l.append("[HitObjects]")
	for n in notes:
		var x := clampi(int(n.col), 0, 3) * 128 + 64
		if float(n.end_ms) > float(n.t_ms):
			l.append("%d,192,%d,128,0,%d:0:0:0:0:" % [x, int(roundf(n.t_ms)), int(roundf(n.end_ms))])
		else:
			l.append("%d,192,%d,1,0,0:0:0:0:" % [x, int(roundf(n.t_ms))])
	return "\n".join(l) + "\n"


# ===========================================================================
# Lauf
# ===========================================================================

static func _arg(args: PackedStringArray, key: String, def: String = "") -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


static func list_osz(maps_dir: String) -> Array:
	var files: Array = []
	for f in DirAccess.get_files_at(maps_dir):
		if f.to_lower().ends_with(".osz"):
			files.append(f)
	files.sort()
	return files


static func _results_path(name: String) -> String:
	return OUT_DIR.path_join("results_%s.json" % name)


static func load_results(name: String) -> Dictionary:
	var p := _results_path(name)
	if not FileAccess.file_exists(p):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}


static func save_results(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var fa := FileAccess.open(_results_path(name), FileAccess.WRITE)
	if fa != null:
		fa.store_string(JSON.stringify(data))
		fa.close()


static func _clear_dir(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


static func write_report(path: String = REPORT_PATH) -> String:
	var runs: Array = []
	for name in ["alt", "neu"]:
		var d := load_results(name)
		if d.is_empty():
			continue
		runs.append({"name": name, "caps": d.caps, "recs": d.recs, "info": d.get("info", {})})
	var tl := ""
	var tlp := OUT_DIR.path_join("tune_log.md")
	if FileAccess.file_exists(tlp):
		tl = FileAccess.get_file_as_string(tlp)
	var text := render_report(runs, tl)
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var fa := FileAccess.open(abs_path, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_string(text)
	fa.close()
	return abs_path


func _cli_bench(args: PackedStringArray) -> int:
	print("=== OMEN Auto-Mapper Pruefstand ===")
	if args.has("--report-only"):
		print("Bericht: ", write_report(_arg(args, "--out", REPORT_PATH)))
		return 0
	var maps_dir := _arg(args, "--maps", ProjectSettings.globalize_path("res://maps"))
	if not DirAccess.dir_exists_absolute(maps_dir):
		print("Maps-Ordner fehlt: ", maps_dir, " (--maps <ordner>)")
		return 2
	var mods := load_mods(_arg(args, "--mapper", "auto"))
	if _arg(args, "--mapper", "auto") == "new" and mods.name != "neu":
		print("Neue Module fehlen: ", mods.missing)
		return 2
	var use_generate: bool = mods.name == "neu" and mods.mapper != null and not args.has("--stages")
	print("Mapper: %s%s  (fehlend: %s)" % [mods.name, " ueber AutoMapper4K.generate" if use_generate else " ueber Stufen", str(mods.missing)])
	var only_set := _arg(args, "--set", "")
	var limit := int(_arg(args, "--limit", "0"))
	var out_abs := ProjectSettings.globalize_path(OUT_DIR)
	var stars_dir := out_abs.path_join("stars_" + mods.name)
	var gen_dir := out_abs.path_join("gen")
	DirAccess.make_dir_recursive_absolute(out_abs)
	_clear_dir(gen_dir)
	var want_stars: bool = mods.caps.cols and not args.has("--no-stars")
	var recs: Array = []
	var done := {}
	if args.has("--resume"):
		for r in load_results(mods.name).get("recs", []):
			recs.append(r)
			done[r.file] = true
	else:
		_clear_dir(stars_dir)
	if not args.has("--no-stars"):
		StarService.prefetch_dir(maps_dir)
	var params := {}
	var pj = JSON.parse_string(FileAccess.get_file_as_string("res://data/automap/params.json")) if FileAccess.file_exists("res://data/automap/params.json") else null
	if pj is Dictionary:
		params = pj
	var files := list_osz(maps_dir)
	var t_start := Time.get_ticks_msec()
	var count := 0
	var info := {"Maps-Ordner": "%d .osz" % files.size(),
			"Weg": "AutoMapper4K.generate, erzeugtes Set zurückgelesen" if use_generate else "Stufen einzeln (decode, Gitter, Features, Noten)"}
	if not mods.missing.is_empty() and mods.name == "alt":
		info["Neue Module"] = "fehlen noch (%s), deshalb Ausgangswerte des alten Mappers" % ", ".join(mods.missing)
	for f in files:
		if only_set != "" and split_of(f) != only_set:
			continue
		if limit > 0 and count >= limit:
			break
		count += 1
		if done.has(f):
			continue
		var osz: String = maps_dir.path_join(f)
		var truth := load_truth(osz, StarService.stars_for(osz) if not args.has("--no-stars") else {})
		if not truth.ok:
			print("  UEBERSPRUNGEN %s: %s" % [f, truth.error])
			continue
		var audio := extract_file(osz, truth.audio_name, out_abs.path_join("audio_tmp"))
		var prod := {"ok": false, "error": "Audio im Set nicht gefunden: " + str(truth.audio_name), "caps": mods.caps}
		var dur_ms: float = truth.t1 + 2000.0
		var t := Time.get_ticks_msec()
		var star_name: String = String(f).sha256_text().substr(0, 16) + ".osz"
		if audio != "":
			if use_generate:
				var res: Dictionary = mods.mapper.generate(audio, gen_dir, {"with_orbit": false})
				if res.get("ok", false):
					prod = product_from_osz(str(res.osz_path), res, mods)
					if want_stars:
						_copy_osu_only(str(res.osz_path), stars_dir.path_join(star_name))
				else:
					prod.error = "generate: " + str(res.get("error", ""))
				_clear_dir(gen_dir)
			else:
				var dec: Dictionary = mods.features.decode(audio)
				if dec.get("ok", false):
					dur_ms = float(dec.duration_ms)
					prod = product_from_stages(mods, dec.pcm, int(dec.rate), params, mods.caps.profiles)
					prod.stage_ms["decode"] = Time.get_ticks_msec() - t - int(prod.stage_ms.get("grid", 0)) - int(prod.stage_ms.get("features", 0)) - int(prod.stage_ms.get("chart", 0))
					if want_stars and prod.ok:
						_write_star_osz(stars_dir.path_join(star_name), prod)
				else:
					prod.error = "decode: " + str(dec.get("error", ""))
			DirAccess.remove_absolute(audio)
		var el := float(Time.get_ticks_msec() - t)
		var rec := song_record(f, truth, prod, el, dur_ms)
		rec["star_file"] = star_name
		recs.append(rec)
		print("  [%d] %s | %s | %.1f s | Tempo %s | Offset %s | %s" % [count, rec.split, _short(f), el / 1000.0,
				str(rec.get("tempo_exact", "-")), _f(rec.get("offset_ms")), rec.get("error", "")])
		if recs.size() % 10 == 0:
			save_results(mods.name, {"caps": mods.caps, "recs": recs, "info": info})
	if want_stars:
		_fill_stars(recs, stars_dir)
	else:
		info["Sterne"] = "nicht berechnet (%s)" % ("--no-stars" if mods.caps.cols else "Mapper ohne Spalten")
	info["Laufzeit"] = "%.0f s für %d Sets" % [(Time.get_ticks_msec() - t_start) / 1000.0, count]
	if limit > 0 or only_set != "":
		info["Achtung"] = "Teil-Lauf (--limit %d, --set %s): Zahlen gelten nur für diesen Ausschnitt" % [limit, only_set]
	save_results(mods.name, {"caps": mods.caps, "recs": recs, "info": info})
	print("Bericht: ", write_report(_arg(args, "--out", REPORT_PATH)))
	var a := aggregate(recs, "test")
	for row in target_rows(a, mods.caps):
		print("  %s | %s | Ziel %s | %s | %s" % row)
	return 0


static func _write_star_osz(path: String, prod: Dictionary) -> void:
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return
	for p in prod.charts:
		if not prod.charts[p].ok:
			continue
		zip.start_file(p + ".osu")
		zip.write_file(osu_text(prod.segments, prod.charts[p].notes, p).to_utf8_buffer())
		zip.close_file()
	zip.close()


static func _copy_osu_only(src: String, dst: String) -> void:
	var reader := ZIPReader.new()
	if reader.open(src) != OK:
		return
	var zip := ZIPPacker.new()
	if zip.open(dst) != OK:
		reader.close()
		return
	for f in reader.get_files():
		if f.to_lower().ends_with(".osu"):
			zip.start_file(f)
			zip.write_file(reader.read_file(f))
			zip.close_file()
	zip.close()
	reader.close()


## Sterne aller erzeugten Diffs in EINEM starcalc-Aufruf.
static func _fill_stars(recs: Array, stars_dir: String) -> void:
	var res: Dictionary = StarService._run_starcalc(["--dir", stars_dir])
	if res.is_empty() or res.has("error"):
		print("  Sterne: starcalc fehlgeschlagen")
		return
	for r in recs:
		var e = res.get(r.get("star_file", ""))
		if not (e is Dictionary) or not e.has("stars"):
			continue
		var st := {}
		for inner in e.stars:
			var d = e.stars[inner]
			if d is Dictionary and d.has("stars") and PROFILES.has(str(d.get("version", ""))):
				st[str(d.version)] = float(d.stars)
		r["stars"] = st


# ===========================================================================
# Hoerprobe
# ===========================================================================

static func _burst(pcm: PackedFloat32Array, t_ms: float, hz: float, amp: float, len_ms: float, rate: int) -> void:
	var i0 := int(roundf(t_ms * rate / 1000.0))
	var n := int(len_ms * rate / 1000.0)
	var decay := n / 5.0
	for j in n:
		var i := i0 + j
		if i < 0 or i >= pcm.size():
			continue
		pcm[i] = clampf(pcm[i] + amp * sin(TAU * hz * j / rate) * exp(-j / decay), -1.0, 1.0)


## Klick-Spur. notes: [[t_ms, spalte]], beats: [[t_ms, taktanfang: bool]].
## Note = kurzer heller Ton (Tonhoehe je Spalte), Schlag = tiefer leiser Ton, Taktanfang tiefer und lauter.
static func click_pcm(notes: Array, beats: Array, dur_ms: float, rate: int = CLICK_RATE) -> PackedFloat32Array:
	var pcm := PackedFloat32Array()
	pcm.resize(int(dur_ms * rate / 1000.0) + 1)
	for b in beats:
		_burst(pcm, float(b[0]), 330.0 if b[1] else 440.0, 0.35 if b[1] else 0.2, 40.0, rate)
	for n in notes:
		_burst(pcm, float(n[0]), CLICK_COL_HZ[clampi(int(n[1]), 0, 3)], 0.5, 25.0, rate)
	return pcm


## Schlaege aus roten Linien bis end_ms. reds: [{time, beat_ms, meter}] sortiert.
static func beats_from_reds(reds: Array, end_ms: float) -> Array:
	var out: Array = []
	for i in reds.size():
		var stop: float = float(reds[i + 1].time) if i + 1 < reds.size() else end_ms
		var b := float(reds[i].beat_ms)
		if b < 60.0:
			continue
		var k := 0
		if i == 0:
			k = -int(floor(float(reds[i].time) / b))
		while float(reds[i].time) + k * b < stop - 1.0:
			out.append([float(reds[i].time) + k * b, posmod(k, int(reds[i].get("meter", 4))) == 0])
			k += 1
	return out


static func write_wav(path: String, pcm: PackedFloat32Array, rate: int) -> bool:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return false
	var data := PackedByteArray()
	data.resize(pcm.size() * 2)
	for i in pcm.size():
		data.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32767.0))
	fa.store_string("RIFF")
	fa.store_32(36 + data.size())
	fa.store_string("WAVEfmt ")
	fa.store_32(16)
	fa.store_16(1)
	fa.store_16(1)
	fa.store_32(rate)
	fa.store_32(rate * 2)
	fa.store_16(2)
	fa.store_16(16)
	fa.store_string("data")
	fa.store_32(data.size())
	fa.store_buffer(data)
	fa.close()
	return true


func _cli_click(args: PackedStringArray) -> int:
	var i := args.find("--click")
	if i + 2 >= args.size():
		print("Aufruf: --click <audio-datei oder -> <set.osz> [Diff-Teilname] [--lead ms]")
		return 2
	var audio := args[i + 1]
	var osz := args[i + 2]
	var want := args[i + 3] if i + 3 < args.size() and not args[i + 3].begins_with("--") else ""
	var lead := float(_arg(args, "--lead", "0"))
	var ff := ClipExporter.find_ffmpeg()
	if ff == "":
		print("ffmpeg fehlt")
		return 2
	var imp: Dictionary = OszImporter._import_uncached(osz)
	if not imp.ok:
		print("Set nicht lesbar: ", imp.error)
		return 2
	var bm: Beatmap = null
	for d in imp.difficulties:
		var b: Beatmap = d.beatmap
		if want != "" and b.version_name().to_lower().find(want.to_lower()) < 0:
			continue
		if bm == null or (b.is_mania() and not bm.is_mania()) or (b.is_mania() == bm.is_mania() and b.hit_objects.size() > bm.hit_objects.size()):
			bm = b
	if bm == null:
		print("Keine Diff passt zu: ", want)
		return 2
	var out_dir := ProjectSettings.globalize_path(CHECK_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tmp_audio := ""
	if audio == "-":
		tmp_audio = extract_file(osz, bm.audio_filename(), out_dir.path_join("_audio_tmp"))
		audio = tmp_audio
	if audio == "" or not FileAccess.file_exists(audio):
		print("Audiodatei fehlt: ", audio)
		return 2
	var notes: Array = []
	for o in bm.hit_objects:
		var mn := o as ManiaNote
		notes.append([o.time + lead, mn.column if mn != null else 0])
	var reds: Array = []
	for tp in bm.timing_points:
		if tp.uninherited and tp.beat_length > 0.0:
			reds.append({"time": tp.time + lead, "beat_ms": tp.beat_length, "meter": maxi(tp.meter, 1)})
	var end_ms := bm.duration_ms() + 2000.0
	var wav := out_dir.path_join("_click_tmp.wav")
	write_wav(wav, click_pcm(notes, beats_from_reds(reds, end_ms), end_ms), CLICK_RATE)
	var name := AudioMapper._safe_name("%s [%s]" % [osz.get_file().get_basename(), bm.version_name()])
	var out := out_dir.path_join(name + ".ogg")
	var log := []
	var code := OS.execute(ff, ["-v", "error", "-y", "-i", audio, "-i", wav, "-filter_complex",
			"[0:a]aresample=44100,volume=0.7[a];[1:a]volume=1.0[b];[a][b]amix=inputs=2:duration=first:normalize=0[o]",
			"-map", "[o]", "-c:a", "libvorbis", "-q:a", "5", out], log, true)
	DirAccess.remove_absolute(wav)
	if tmp_audio != "":
		DirAccess.remove_absolute(tmp_audio)
	if code != 0:
		print("ffmpeg fehlgeschlagen: ", log)
		return 1
	print("Hoerprobe: %s  (Diff %s, %d Noten, %d rote Linien, %.1f BPM)" % [out, bm.version_name(), notes.size(), reds.size(),
			60000.0 / float(reds[0].beat_ms) if not reds.is_empty() else 0.0])
	return 0
