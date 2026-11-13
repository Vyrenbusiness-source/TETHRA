class_name AmChart
extends RefCounted

## PLATZHALTER (Task am-pipeline). Gleiche Signaturen wie docs/automap/spec.md,
## setzt Onsets einfach auf das Gitter (Dichte je Profil, Spalten im Wechsel).
## Nach dem Merge des echten scripts/automap/am_chart.gd diese Datei loeschen.

const PROFILES := ["Easy", "Normal", "Hard", "Insane", "Expert"]
const _CFG := {
	"Easy": {"div": 1, "keep": 0.5}, "Normal": {"div": 2, "keep": 0.6}, "Hard": {"div": 2, "keep": 0.9},
	"Insane": {"div": 4, "keep": 0.8}, "Expert": {"div": 4, "keep": 1.0},
}

static func build(features: Dictionary, grid: Dictionary, profile: String, _params: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "error": "", "profile": profile, "notes": [],
		"stats": {"nps_avg": 0.0, "nps_peak": 0.0, "holds": 0, "chords": 0, "max_jack": 0}}
	if not _CFG.has(profile):
		out.error = "unknown profile: " + profile
		return out
	var cfg: Dictionary = _CFG[profile]
	var by_t := {}
	for e in features.get("events", []):
		if float(e.strength) < 1.0 - float(cfg.keep) and float(e.strength) < 0.5:
			continue
		var t := AmGrid.snap(grid, float(e.t_ms) - AudioMapper.OSU_LEAD_MS, int(cfg.div))
		if t < 600.0:
			continue
		var key := int(roundf(t))
		if not by_t.has(key) or float(by_t[key].s) < float(e.strength):
			by_t[key] = {"t": t, "s": float(e.strength)}
	var keys := by_t.keys()
	keys.sort()
	var col := 0
	for k in keys:
		col = (col + (1 if int(k) % 3 != 0 else 2)) % 4
		out.notes.append({"t_ms": float(by_t[k].t), "col": col, "end_ms": -1.0})
	var dur := maxf(float(features.get("duration_ms", 1.0)), 1.0)
	out.stats.nps_avg = out.notes.size() * 1000.0 / dur
	out.ok = true
	return out


static func lint(_notes: Array, _grid: Dictionary, _profile: String) -> Array[String]:
	return []
