class_name AmGrid
extends RefCounted

## PLATZHALTER (Task am-pipeline). Gleiche Signaturen wie docs/automap/spec.md,
## Ergebnis aus dem alten AudioMapper (ein Tempo, Meter 4). Nach dem Merge des
## echten scripts/automap/am_grid.gd diese Datei loeschen.

static func track(pcm: PackedFloat32Array, rate: int, _params: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "error": "", "segments": [], "confidence": 0.0, "alternatives": []}
	if pcm.size() < rate * 4:
		out.error = "audio shorter than 4 s"
		return out
	var flux := AudioMapper.onset_flux(pcm)
	var peaks := AudioMapper.pick_peaks(flux)
	if peaks.size() < 8:
		out.error = "no onsets found"
		return out
	var g := AudioMapper.estimate_grid(peaks, flux)
	var beat := 60000.0 / float(g.bpm)
	var start := float(g.offset_ms) - AudioMapper.OSU_LEAD_MS
	out.ok = true
	out.segments = [{"start_ms": start, "beat_ms": beat, "meter": 4, "downbeat_ms": start}]
	out.confidence = 0.5
	out.alternatives = [{"factor": 2.0, "score": 0.3}, {"factor": 0.5, "score": 0.3},
		{"factor": 1.5, "score": 0.1}, {"factor": 0.667, "score": 0.1}]
	return out


static func _seg(grid: Dictionary, t_ms: float) -> Dictionary:
	var segs: Array = grid.get("segments", [])
	var cur: Dictionary = segs[0]
	for s in segs:
		if float(s.start_ms) <= t_ms + 0.001:
			cur = s
	return cur


static func snap(grid: Dictionary, t_ms: float, div: int) -> float:
	var s := _seg(grid, t_ms)
	var step := float(s.beat_ms) / float(maxi(div, 1))
	return float(s.downbeat_ms) + roundf((t_ms - float(s.downbeat_ms)) / step) * step


static func beat_pos(grid: Dictionary, t_ms: float) -> float:
	var segs: Array = grid.get("segments", [])
	var pos := 0.0
	for i in segs.size():
		var s: Dictionary = segs[i]
		var end := float(segs[i + 1].start_ms) if i + 1 < segs.size() else INF
		if t_ms < end or i == segs.size() - 1:
			return pos + (t_ms - float(s.start_ms)) / float(s.beat_ms)
		pos += (end - float(s.start_ms)) / float(s.beat_ms)
	return pos


static func is_downbeat(grid: Dictionary, t_ms: float, tol_ms: float = 8.0) -> bool:
	var s := _seg(grid, t_ms)
	var bar := float(s.beat_ms) * float(s.meter)
	var d := fposmod(t_ms - float(s.downbeat_ms), bar)
	return minf(d, bar - d) <= tol_ms


static func scaled(grid: Dictionary, factor: float) -> Dictionary:
	var out := grid.duplicate(true)
	for s in out.segments:
		s.beat_ms = float(s.beat_ms) / factor
	return out
