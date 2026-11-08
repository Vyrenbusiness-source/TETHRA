class_name OrbitCareer
extends RefCounted

## Orbit-Karriere: fuehrt neue Spieler langsam heran. Reine, statisch testbare
## Logik, unabhaengig von den Orbit-Trefferregeln: sie kennt pro Lauf nur
## Orbit-Sterne, Genauigkeit, Note und Fail.
##
## Zustand (user://orbit_career.cfg, Sektion "career"):
##   level  aktuelle Stufe in Orbit-Sternen (Start 1,5)
##   good / bad / great  Serien auf der Stufe
##   stamp  Datum des zuletzt verarbeiteten Laufs
##   event  letztes Ereignis: "" | "up" | "down" | "ready"
##   mode   "career" | "free"

const PATH := "user://orbit_career.cfg"
const START_LEVEL := 1.5
const MIN_LEVEL := 1.0
const MAX_LEVEL := 9.0
const STEP := 0.3
## Stufe steigt nach GOOD_NEED Laeufen >= GOOD_ACC, sinkt nach BAD_NEED
## Laeufen mit Fail oder < BAD_ACC (jeweils hintereinander).
const GOOD_ACC := 0.93
const GOOD_NEED := 3
const BAD_ACC := 0.80
const BAD_NEED := 3
## "Bereit fuer mehr": GREAT_NEED Laeufe >= GREAT_ACC hintereinander.
const GREAT_ACC := 0.97
const GREAT_NEED := 2
const READY_JUMP := 2.0  # in STEP-Einheiten
## Vorschlags-Fenster um die Stufe.
const WIN_LO := 0.3
const WIN_HI := 0.5

const MODE_CAREER := "career"
const MODE_FREE := "free"


static func new_state() -> Dictionary:
	return {
		"level": START_LEVEL, "good": 0, "bad": 0, "great": 0,
		"stamp": "", "event": "", "runs": 0,
		"mode": MODE_FREE, "offer": false,
	}


static func clamp_level(v: float) -> float:
	return snappedf(clampf(v, MIN_LEVEL, MAX_LEVEL), 0.05)


static func window(level: float) -> Vector2:
	return Vector2(level - WIN_LO, level + WIN_HI)


static func in_window(stars: float, level: float) -> bool:
	var w := window(level)
	return stars >= w.x - 0.0001 and stars <= w.y + 0.0001


## Lauf: {stars, accuracy, grade, failed}. Ein Fail oder Note F ist immer schlecht.
static func is_bad(run: Dictionary) -> bool:
	return bool(run.get("failed", false)) or str(run.get("grade", "")) == "F" \
			or float(run.get("accuracy", 0.0)) < BAD_ACC


static func is_good(run: Dictionary) -> bool:
	return not is_bad(run) and float(run.get("accuracy", 0.0)) >= GOOD_ACC


## Zustand um einen Lauf weiterschalten (reine Funktion, gibt Kopie zurueck).
## Laeufe ohne Sterne zaehlen nicht; gute Laeufe weit unter und schlechte weit
## ueber dem Fenster sagen nichts ueber die Stufe und werden uebergangen.
static func apply_run(state: Dictionary, run: Dictionary) -> Dictionary:
	var s := state.duplicate()
	var stars := float(run.get("stars", -1.0))
	if stars <= 0.0:
		return s
	var level := float(s.level)
	var bad := is_bad(run)
	var good := is_good(run)
	s["runs"] = int(s.get("runs", 0)) + 1
	s["event"] = ""
	if good and stars < level - WIN_LO - 0.0001:
		return s
	if bad and stars > level + WIN_HI + 0.0001:
		return s
	if bad:
		s["bad"] = int(s.bad) + 1
		s["good"] = 0
		s["great"] = 0
		if int(s.bad) >= BAD_NEED:
			s["level"] = clamp_level(level - STEP)
			s["bad"] = 0
			s["event"] = "down"
	elif good:
		s["bad"] = 0
		s["good"] = int(s.good) + 1
		s["great"] = int(s.great) + 1 if float(run.accuracy) >= GREAT_ACC else 0
		if int(s.great) >= GREAT_NEED:
			s["level"] = clamp_level(level + STEP * READY_JUMP)
			s["good"] = 0
			s["great"] = 0
			s["event"] = "ready"
		elif int(s.good) >= GOOD_NEED:
			s["level"] = clamp_level(level + STEP)
			s["good"] = 0
			s["great"] = 0
			s["event"] = "up"
	else:  # mittelmaessig: Serien reissen ab
		s["bad"] = 0
		s["good"] = 0
		s["great"] = 0
	return s


## Maps bis zur naechsten Stufe (mindestens 1).
static func runs_to_next(state: Dictionary) -> int:
	return maxi(GOOD_NEED - int(state.get("good", 0)), 1)


static func next_level(state: Dictionary) -> float:
	return clamp_level(float(state.get("level", START_LEVEL)) + STEP)


static func ready_for_more(state: Dictionary) -> bool:
	return str(state.get("event", "")) == "ready"


## Vorschlaege aus Kandidaten {key, stars, played(optional)}: nur im Fenster,
## Ungespielte zuerst, dann nach Naehe zur Stufe + 0,1. Hoechstens n.
static func suggest(cands: Array, level: float, n: int = 5) -> Array:
	var out: Array = []
	for c in cands:
		var st := float((c as Dictionary).get("stars", -1.0))
		if st > 0.0 and in_window(st, level):
			out.append(c)
	var target := level + 0.1
	out.sort_custom(func(a, b):
		var pa := bool(a.get("played", false))
		var pb := bool(b.get("played", false))
		if pa != pb:
			return not pa
		return absf(float(a.stars) - target) < absf(float(b.stars) - target))
	return out.slice(0, n)


## Markierung "empfohlen" im Browser (Frei-Modus): Sterne im Fenster.
static func recommended(stars: float, level: float) -> bool:
	return stars > 0.0 and in_window(stars, level)


## Index in OnlineBrowser.STAR_FILTERS, der die Stufe am besten abdeckt.
## Orbit-Sterne und osu!-Sterne weichen etwas ab; das Fenster ist ein Anhalt.
static func online_star_filter(level: float) -> int:
	var f: Array = OnlineBrowser.STAR_FILTERS
	var best := 0
	var best_d := 1e9
	for i in range(1, f.size()):
		var lo := float(f[i][1])
		var hi := minf(float(f[i][2]), lo + 3.0)
		var mid := (lo + hi) * 0.5
		if level >= lo and level < float(f[i][2]):
			return i
		if absf(mid - level) < best_d:
			best_d = absf(mid - level)
			best = i
	return best


## Zustand aus Laeufen (aelteste zuerst) nachziehen, die neuer als state.stamp
## sind. Laeufe: {date, stars, accuracy, grade, failed}.
static func sync_runs(state: Dictionary, runs: Array) -> Dictionary:
	var s := state.duplicate()
	for r in runs:
		var d := str(r.get("date", ""))
		if d == "" or d <= str(s.get("stamp", "")):
			continue
		s = apply_run(s, r)
		s["stamp"] = d
	return s


## Anzeige "Stufe 2,1 ★".
static func level_text(level: float) -> String:
	return tr_("Stufe %s ★") % UiTheme.fmt_num(level, 1)


static func next_text(state: Dictionary) -> String:
	var n := runs_to_next(state)
	var nl := UiTheme.fmt_num(next_level(state), 1)
	if n == 1:
		return tr_("noch 1 Map bis %s ★") % nl
	return tr_("noch %d Maps bis %s ★") % [n, nl]


static func tr_(msg: String) -> String:
	return TranslationServer.translate(msg)


# ---------------------------------------------------------------------------
# Speichern
# ---------------------------------------------------------------------------

## Speicherort: Tests/Shots schreiben nie in die echte Datei
## (--career-path=<Datei> oder unter --script eine Test-Datei).
static func default_path() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--career-path="):
			return a.trim_prefix("--career-path=")
	for a in OS.get_cmdline_args():
		if a == "--script" or a == "-s":
			DirAccess.make_dir_recursive_absolute("user://test_tmp")
			return "user://test_tmp/career_%d.cfg" % OS.get_process_id()
	return PATH


## Nach dem Orbit-Tutorial: Karriere beim naechsten Browser-Besuch vorschlagen
## (nur, solange der Spieler sie nicht schon gewaehlt hat).
static func offer(path: String = "") -> void:
	var p := path if path != "" else default_path()
	var s := load_state(p)
	if s.mode == MODE_CAREER:
		return
	s["offer"] = true
	save_state(s, p)


static func load_state(path: String = "") -> Dictionary:
	if path == "":
		path = default_path()
	var s := new_state()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	for k in s.keys():
		var v = cfg.get_value("career", k, s[k])
		if typeof(v) == typeof(s[k]):
			s[k] = v
		elif typeof(s[k]) == TYPE_FLOAT and (typeof(v) == TYPE_INT):
			s[k] = float(v)
	s["level"] = clamp_level(float(s.level))
	if s.mode != MODE_CAREER:
		s["mode"] = MODE_FREE
	return s


static func save_state(state: Dictionary, path: String = "") -> void:
	if path == "":
		path = default_path()
	var cfg := ConfigFile.new()
	cfg.load(path)
	for k in state.keys():
		cfg.set_value("career", k, state[k])
	cfg.save(path)


## Laeufe aus ScoreStore (Sektion orbit_recent) holen und mit den Orbit-Sternen
## versorgen. stars_of: Callable(entry: Dictionary) -> float (-1 = unbekannt).
static func runs_from_store(stars_of: Callable, n: int = 12) -> Array:
	var recent := ScoreStore.recent_plays(n, ScoreStore.MODE_ORBIT)  # neueste zuerst
	recent.reverse()
	var out: Array = []
	for e in recent:
		var st: float = stars_of.call(e)
		out.append({
			"date": str(e.get("date", "")), "stars": st,
			"accuracy": float(e.get("accuracy", 0.0)),
			"grade": str(e.get("grade", "")), "failed": bool(e.get("failed", false)),
		})
	return out
