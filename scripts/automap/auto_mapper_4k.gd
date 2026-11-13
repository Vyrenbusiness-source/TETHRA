class_name AutoMapper4K
extends RefCounted

## Ablauf des 4K-Auto-Mappers (docs/automap/spec.md): Musikdatei -> .osz mit
## mehreren 4K-Schwierigkeiten. Spricht AmFeatures, AmGrid, AmChart und AmWriter
## nur ueber ihre class_name an. generate() blockiert (Aufrufer startet den Thread).
##
## opts ueber die Spec hinaus (alle optional):
##   cancelled: Callable -> bool   zwischen den Stufen gefragt; true bricht ab
##   stars: bool (true)            Sterne je Diff ueber StarService nachschlagen
##   ffmpeg: String                ffmpeg-Pfad vorgeben ("" = als fehlend behandeln)
## Ergebnis ueber die Spec hinaus: artist, title, audio_path, tempo_factor, grid
## (das benutzte Gitter, fuer den Schritt "Takt pruefen").

const PARAMS_PATH := "res://data/automap/params.json"
const STAGE_DECODE := "decode"
const STAGE_GRID := "grid"
const STAGE_FEATURES := "features"
const STAGE_CHART := "chart"
const STAGE_WRITE := "write"
const STAGE_DONE := "done"
## Anteil am Gesamtfortschritt, bei dem die Stufe beginnt.
const STAGE_AT := {"decode": 0.0, "grid": 0.15, "features": 0.4, "chart": 0.7, "write": 0.92, "done": 1.0}
const ERR_NO_FFMPEG := "ffmpeg not found"
const ERR_CANCELLED := "cancelled"


static func generate(audio_path: String, maps_dir: String, opts: Dictionary = {}) -> Dictionary:
	var progress: Callable = opts.get("progress", Callable())
	var cancelled: Callable = opts.get("cancelled", Callable())
	var profiles: Array = opts.get("profiles", [])
	if profiles.is_empty():
		profiles = AmChart.PROFILES.duplicate()
	var tempo_factor := float(opts.get("tempo_factor", 1.0))
	var offset_ms := float(opts.get("offset_ms", 0.0))
	if not FileAccess.file_exists(audio_path):
		return _fail("audio file missing: " + audio_path)
	var ff := str(opts["ffmpeg"]) if opts.has("ffmpeg") else ClipExporter.find_ffmpeg()
	if ff == "":
		return _fail(ERR_NO_FFMPEG)
	var params := load_params()

	_report(progress, STAGE_DECODE, 0.0)
	var dec: Dictionary = AmFeatures.decode(audio_path)
	if not bool(dec.get("ok", false)):
		return _fail(str(dec.get("error", "decode failed")))
	var pcm: PackedFloat32Array = dec.pcm
	var rate := int(dec.rate)
	var meta: Dictionary = AmFeatures.tags(audio_path)
	if _stop(cancelled):
		return _fail(ERR_CANCELLED)

	_report(progress, STAGE_GRID, 0.0)
	var grid: Dictionary = AmGrid.track(pcm, rate, params.get("grid", {}))
	if not bool(grid.get("ok", false)):
		return _fail(str(grid.get("error", "no beat found")))
	var alternatives: Array = grid.get("alternatives", [])
	var confidence := float(grid.get("confidence", 0.0))
	grid = adjusted_grid(grid, tempo_factor, offset_ms)
	if _stop(cancelled):
		return _fail(ERR_CANCELLED)

	_report(progress, STAGE_FEATURES, 0.0)
	var features: Dictionary = AmFeatures.analyze(pcm, rate, params.get("features", {}))
	if not bool(features.get("ok", false)):
		return _fail(str(features.get("error", "analysis failed")))
	pcm = PackedFloat32Array()
	if _stop(cancelled):
		return _fail(ERR_CANCELLED)

	var charts: Array = []
	for i in profiles.size():
		_report(progress, STAGE_CHART, float(i) / profiles.size())
		var c: Dictionary = AmChart.build(features, grid, str(profiles[i]), params.get("chart", {}))
		if bool(c.get("ok", false)) and not (c.get("notes", []) as Array).is_empty():
			charts.append(c)
		if _stop(cancelled):
			return _fail(ERR_CANCELLED)
	if charts.is_empty():
		return _fail("no notes found. Is the file music?")

	_report(progress, STAGE_WRITE, 0.0)
	var wmeta := {"artist": str(meta.get("artist", "Unknown")), "title": str(meta.get("title", "")),
		"with_orbit": bool(opts.get("with_orbit", true)), "ffmpeg": ff}
	if wmeta.title == "":
		wmeta.title = audio_path.get_file().get_basename()
	var w: Dictionary = AmWriter.write_osz(audio_path, maps_dir, wmeta, grid, features, charts)
	if not bool(w.get("ok", false)):
		return _fail(str(w.get("error", "write failed")))

	var stars := {}
	if bool(opts.get("stars", true)):
		_report(progress, STAGE_WRITE, 0.5)
		stars = StarService.stars_for(str(w.osz_path))
	var diffs: Array = []
	for c in charts:
		var inner := AmWriter.osu_name(wmeta.artist, wmeta.title, str(c.profile))
		var st := -1.0
		if stars.has(inner) and stars[inner] is Dictionary:
			st = float(stars[inner].get("stars", -1.0))
		diffs.append({"name": str(c.profile), "notes": (c.notes as Array).size(), "stars": st})
	_report(progress, STAGE_DONE, 1.0)
	var seg := main_segment(grid, float(features.get("duration_ms", 0.0)))
	return {"ok": true, "error": "", "osz_path": str(w.osz_path),
		"bpm": 60000.0 / float(seg.beat_ms), "offset_ms": float(grid.segments[0].start_ms),
		"confidence": confidence, "diffs": diffs, "alternatives": alternatives,
		"artist": wmeta.artist, "title": wmeta.title, "audio_path": audio_path,
		"tempo_factor": tempo_factor, "user_offset_ms": offset_ms, "grid": grid,
		"background": str(w.get("background", ""))}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "osz_path": "", "bpm": 0.0, "offset_ms": 0.0,
		"confidence": 0.0, "diffs": [], "alternatives": []}


static func _stop(cancelled: Callable) -> bool:
	return cancelled.is_valid() and bool(cancelled.call())


## Gesamtfortschritt 0..1 aus Stufe + Anteil in der Stufe.
static func overall(stage: String, frac: float) -> float:
	var keys: Array = STAGE_AT.keys()
	var i := keys.find(stage)
	if i < 0:
		return 0.0
	var a := float(STAGE_AT[stage])
	var b := float(STAGE_AT[keys[i + 1]]) if i + 1 < keys.size() else 1.0
	return clampf(a + (b - a) * clampf(frac, 0.0, 1.0), 0.0, 1.0)


static func _report(progress: Callable, stage: String, frac: float) -> void:
	if progress.is_valid():
		progress.call(stage, overall(stage, frac))


## res://data/automap/params.json (Abschnitte grid, features, chart) oder {}.
static func load_params() -> Dictionary:
	if not FileAccess.file_exists(PARAMS_PATH):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(PARAMS_PATH))
	return v if v is Dictionary else {}


## Gitter mit Nutzer-Korrektur: Tempo-Faktor (AmGrid.scaled) und Offset in ms.
static func adjusted_grid(grid: Dictionary, tempo_factor: float, offset_ms: float) -> Dictionary:
	var g := grid
	if absf(tempo_factor - 1.0) > 0.0001 and tempo_factor > 0.0:
		g = AmGrid.scaled(g, tempo_factor)
	if absf(offset_ms) > 0.0001:
		g = g.duplicate(true)
		for s in g.segments:
			s.start_ms = float(s.start_ms) + offset_ms
			s.downbeat_ms = float(s.downbeat_ms) + offset_ms
	return g


## Segment, das am laengsten gilt (fuer die BPM-Anzeige).
static func main_segment(grid: Dictionary, duration_ms: float) -> Dictionary:
	var segs: Array = grid.get("segments", [])
	var best: Dictionary = segs[0]
	var best_len := -1.0
	for i in segs.size():
		var end := float(segs[i + 1].start_ms) if i + 1 < segs.size() else maxf(duration_ms, float(segs[i].start_ms) + 1.0)
		var span := end - float(segs[i].start_ms)
		if span > best_len:
			best_len = span
			best = segs[i]
	return best


## Schlaege in [from_ms, to_ms): Array von [t_ms, ist_taktanfang].
static func beat_times(grid: Dictionary, from_ms: float, to_ms: float) -> Array:
	var out: Array = []
	var segs: Array = grid.get("segments", [])
	for i in segs.size():
		var s: Dictionary = segs[i]
		var beat := maxf(float(s.beat_ms), 1.0)
		var meter := maxi(int(s.get("meter", 4)), 1)
		var down := float(s.get("downbeat_ms", s.start_ms))
		var a := maxf(from_ms, float(s.start_ms) - 0.5) if i > 0 else from_ms
		var b := minf(to_ms, float(segs[i + 1].start_ms) - 0.5) if i + 1 < segs.size() else to_ms
		if b <= a:
			continue
		var k := int(ceil((a - down) / beat - 0.0001))
		while down + k * beat < b:
			out.append([down + k * beat, posmod(k, meter) == 0])
			k += 1
	return out
