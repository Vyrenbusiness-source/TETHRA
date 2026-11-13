class_name AmFeatures
extends RefCounted

## PLATZHALTER (Task am-pipeline). Gleiche Signaturen wie docs/automap/spec.md,
## Ergebnis aus dem alten AudioMapper (Onsets ohne Ebenen, grobe Abschnitte).
## Nach dem Merge des echten scripts/automap/am_features.gd diese Datei loeschen.

static func decode(audio_path: String) -> Dictionary:
	var pcm := AudioMapper.decode(audio_path)
	if pcm.is_empty():
		return {"ok": false, "error": "audio not decodable (ffmpeg found?)", "pcm": pcm,
			"rate": AudioMapper.RATE, "duration_ms": 0.0}
	return {"ok": true, "error": "", "pcm": pcm, "rate": AudioMapper.RATE,
		"duration_ms": pcm.size() * 1000.0 / AudioMapper.RATE}


static func tags(audio_path: String) -> Dictionary:
	var m := AudioMapper.read_meta(audio_path)
	var rx := RegEx.create_from_string("(?i)\\s*[\\(\\[](official[^\\)\\]]*|lyrics?[^\\)\\]]*|audio|video|visualizer|prod\\.[^\\)\\]]*)[\\)\\]]")
	return {"artist": rx.sub(str(m.artist), "", true).strip_edges(),
		"title": rx.sub(str(m.title), "", true).strip_edges()}


static func analyze(pcm: PackedFloat32Array, rate: int, _params: Dictionary = {}) -> Dictionary:
	var dur := pcm.size() * 1000.0 / float(rate)
	var out := {"ok": false, "error": "", "duration_ms": dur, "events": [],
		"energy": PackedFloat32Array(), "frame_ms": AudioMapper.HOP_MS, "sections": []}
	var flux := AudioMapper.onset_flux(pcm)
	var peaks := AudioMapper.pick_peaks(flux)
	if peaks.size() < 8:
		out.error = "no onsets found"
		return out
	var top := 0.0001
	for p in peaks:
		top = maxf(top, float(p[1]))
	for p in peaks:
		out.events.append({"t_ms": float(p[0]), "strength": float(p[1]) / top, "kind": "other",
			"pitch": -1.0, "sustain_ms": 0.0})
	out.sections = [
		{"start_ms": 0.0, "end_ms": dur * 0.3, "intensity": 0.4, "kind": "verse", "kiai": false, "lead": "drums"},
		{"start_ms": dur * 0.3, "end_ms": dur * 0.55, "intensity": 0.9, "kind": "chorus", "kiai": true, "lead": "drums"},
		{"start_ms": dur * 0.55, "end_ms": dur, "intensity": 0.5, "kind": "verse", "kiai": false, "lead": "drums"},
	]
	out.ok = true
	return out
