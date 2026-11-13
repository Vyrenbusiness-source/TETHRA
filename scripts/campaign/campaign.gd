class_name Campaign
extends RefCounted

## Kampagne: feste Map-Liste fuer alle Spieler (data/campaign.json), Kapitel = Welten,
## je Kapitel 5 Stufen + Boss-Stufe. Jede Stufe hat drei Ziele (Ziel, Zusatzziel,
## Meisterziel) = 1 bis 3 Sterne. Reine Logik, statisch testbar (Muster: OrbitCareer).
## Plan und Regeln: docs/campaign.md. Server-Vorschlag: docs/net/campaign_server.md.

const DATA_PATH := "res://data/campaign.json"
const PATH := "user://campaign.json"
const SCENE := "res://scenes/campaign.tscn"
const VERSION := "v1"
const STAGES_PER_CHAPTER := 6
const GOALS_PER_STAGE := 3
const GOAL_TYPES: Array[String] = ["pass", "acc", "grade", "miss"]
## Schlechtester -> bester Rang (Index = Wert).
const GRADE_ORDER: Array[String] = ["F", "D", "C", "B", "A", "S", "SS"]
const MODS_ALLOWED: Array[String] = ["SV"]

static var _data_cache: Dictionary = {}


# ------------------------------------------------------------------ Daten

## Kampagnen-Daten laden ({} bei Fehler). Ohne Pfad: data/campaign.json (einmal gelesen).
static func load_data(path: String = "") -> Dictionary:
	if path == "" and not _data_cache.is_empty():
		return _data_cache
	var p := DATA_PATH if path == "" else path
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (d is Dictionary):
		return {}
	if path == "":
		_data_cache = d
	return d


## Kampagne eines Modus aus den Gesamtdaten: {version, mode, chapters}. Alle
## Funktionen unten arbeiten auf dieser Form. Unbekannter Modus = keine Kapitel ("bald").
static func for_mode(all: Dictionary, mode: String) -> Dictionary:
	var camps: Variant = all.get("campaigns", {})
	var one: Variant = (camps as Dictionary).get(mode, {}) if camps is Dictionary else {}
	var chs: Variant = (one as Dictionary).get("chapters", []) if one is Dictionary else []
	return {"version": str(all.get("version", VERSION)), "mode": mode, "chapters": chs if chs is Array else []}


## Modus, dem eine Stufe gehoert ("" = unbekannt). IDs beginnen mit "<modus>-".
static func mode_of_stage(all: Dictionary, id: String) -> String:
	var m := id.get_slice("-", 0)
	return m if not stage_by_id(for_mode(all, m), id).is_empty() else ""


static func total_stars_all(all: Dictionary, state: Dictionary) -> int:
	var n := 0
	for m in ScoreStore.MODES:
		n += total_stars(for_mode(all, m), state)
	return n


static func max_stars_all(all: Dictionary) -> int:
	var n := 0
	for m in ScoreStore.MODES:
		n += max_stars(for_mode(all, m))
	return n


## Formatpruefung der Gesamtdaten (alle Modi): Liste der Fehler (leer = gueltig).
static func validate(all: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if str(all.get("version", "")) == "":
		errs.append("version fehlt")
	var camps: Variant = all.get("campaigns", null)
	if not (camps is Dictionary) or (camps as Dictionary).is_empty():
		errs.append("campaigns fehlt")
		return errs
	var seen := {}
	var maps := {}
	for mode: String in camps:
		if not ScoreStore.MODES.has(mode):
			errs.append("%s: unbekannter Modus" % mode)
		var one := for_mode(all, mode)
		if chapters(one).is_empty():
			continue
		errs.append_array(validate_one(one))
		for s: Dictionary in all_stages(one):
			var id := str(s.get("id", ""))
			if seen.has(id) or not id.begins_with(mode + "-"):
				errs.append("%s: ID doppelt oder ohne Modus-Vorsatz" % id)
			seen[id] = true
			if str(s.get("mode", "")) != mode:
				errs.append("%s: Stufe gehoert nicht zum Modus" % id)
			var md5 := str(s.get("md5", ""))
			if md5 != "" and maps.has(md5):
				errs.append("%s: Map doppelt" % id)
			maps[md5] = true
	return errs


## Formatpruefung einer Modus-Kampagne (Form von for_mode).
static func validate_one(data: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if str(data.get("version", "")) == "":
		errs.append("version fehlt")
	var chs: Variant = data.get("chapters", null)
	if not (chs is Array) or (chs as Array).is_empty():
		errs.append("chapters fehlt")
		return errs
	var ids := {}
	var sets := {}
	for c: Variant in chs:
		if not (c is Dictionary):
			errs.append("Kapitel ist kein Objekt")
			continue
		var cid := str(c.get("id", ""))
		if not WorldTheme.NAMES.has(str(c.get("world", ""))):
			errs.append("%s: unbekannte Welt" % cid)
		if not ScoreStore.MODES.has(str(c.get("focus", ""))):
			errs.append("%s: unbekannter Schwerpunkt" % cid)
		var sts: Variant = c.get("stages", null)
		if not (sts is Array) or (sts as Array).size() != STAGES_PER_CHAPTER:
			errs.append("%s: braucht %d Stufen" % [cid, STAGES_PER_CHAPTER])
			continue
		for i in (sts as Array).size():
			var s: Variant = sts[i]
			if not (s is Dictionary):
				errs.append("%s: Stufe ist kein Objekt" % cid)
				continue
			var sid := str(s.get("id", ""))
			if sid == "" or ids.has(sid):
				errs.append("%s: Stufen-ID fehlt oder doppelt" % sid)
			ids[sid] = true
			if bool(s.get("boss", false)) != (i == STAGES_PER_CHAPTER - 1):
				errs.append("%s: nur die letzte Stufe ist Boss" % sid)
			if not ScoreStore.MODES.has(str(s.get("mode", ""))):
				errs.append("%s: unbekannter Modus" % sid)
			for m: Variant in s.get("mods", []):
				if not MODS_ALLOWED.has(str(m)):
					errs.append("%s: Mod %s nicht erlaubt" % [sid, str(m)])
			if has_map(s):
				if str(s.get("md5", "")).length() != 32:
					errs.append("%s: md5 ungueltig" % sid)
				if str(s.get("diff", "")) == "":
					errs.append("%s: Diff-Name fehlt" % sid)
				var key := "%d/%s" % [int(s.get("set_id", 0)), str(s.get("md5", ""))]
				if sets.has(key):
					errs.append("%s: Map doppelt" % sid)
				sets[key] = true
			var gs: Variant = s.get("goals", null)
			if not (gs is Array) or (gs as Array).size() != GOALS_PER_STAGE:
				errs.append("%s: braucht %d Ziele" % [sid, GOALS_PER_STAGE])
				continue
			for g: Variant in gs:
				if not (g is Dictionary) or not goal_valid(g):
					errs.append("%s: Ziel ungueltig" % sid)
	return errs


static func goal_valid(g: Dictionary) -> bool:
	match str(g.get("type", "")):
		"pass":
			return true
		"acc":
			var v := float(g.get("value", -1.0))
			return v > 0.0 and v <= 1.0
		"grade":
			return GRADE_ORDER.has(str(g.get("value", "")))
		"miss":
			return int(g.get("value", -1)) >= 0
	return false


## Stufe hat eine feste Map (geplante Stufen ohne Map sind noch nicht spielbar).
static func has_map(stage: Dictionary) -> bool:
	return int(stage.get("set_id", 0)) > 0 and str(stage.get("md5", "")) != ""


static func chapters(data: Dictionary) -> Array:
	var c: Variant = data.get("chapters", [])
	return c if c is Array else []


## Alle Stufen in Spielreihenfolge.
static func all_stages(data: Dictionary) -> Array:
	var out: Array = []
	for c: Dictionary in chapters(data):
		out.append_array(c.get("stages", []))
	return out


static func stage_by_id(data: Dictionary, id: String) -> Dictionary:
	for s: Dictionary in all_stages(data):
		if str(s.get("id", "")) == id:
			return s
	return {}


## Index des Kapitels einer Stufe (-1 = unbekannt).
static func chapter_index_of(data: Dictionary, id: String) -> int:
	var chs := chapters(data)
	for i in chs.size():
		for s: Dictionary in (chs[i] as Dictionary).get("stages", []):
			if str(s.get("id", "")) == id:
				return i
	return -1


## Index der Stufe in ihrem Kapitel (-1 = unbekannt).
static func stage_index_of(data: Dictionary, id: String) -> int:
	var ci := chapter_index_of(data, id)
	if ci < 0:
		return -1
	var sts: Array = (chapters(data)[ci] as Dictionary).get("stages", [])
	for i in sts.size():
		if str((sts[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


## Folge-Stufe ("" = letzte Stufe der Kampagne).
static func next_stage_id(data: Dictionary, id: String) -> String:
	var all := all_stages(data)
	for i in all.size():
		if str((all[i] as Dictionary).get("id", "")) == id:
			return str((all[i + 1] as Dictionary).get("id", "")) if i + 1 < all.size() else ""
	return ""


## Kennung fuer den Server (Feld "campaign" in POST /score).
static func score_tag(data: Dictionary, stage_id: String) -> String:
	return "%s/%s" % [str(data.get("version", VERSION)), stage_id]


# ------------------------------------------------------------------ Start

## Gespeicherte Browser-Schalter (song_select.gd BROWSER_STATE_PATH): Orbit- und Trace-Mods.
const BROWSER_STATE := "user://browser_state.cfg"


## Mods des Spielers fuer einen Modus, genau wie der Song-Browser sie beim Start setzt
## (song_select._current_mods), nur ohne No Fail: das gibt es in der Kampagne nicht.
## sv = Settings.mod_sv. Orbit/Trace-Schalter aus browser_state (fehlt = aus).
static func player_mods(mode: String, sv: bool, browser_path: String = BROWSER_STATE) -> Dictionary:
	var cfg := ConfigFile.new()
	var have := cfg.load(browser_path) == OK
	var out := {"NF": false}
	var keys: Array = []
	var saved: Variant = {}
	match mode:
		"mania":
			out["SV"] = sv
		"orbit":
			keys = OrbitCore.ORBIT_MODS
			saved = cfg.get_value("browser", "orbit_mods", {}) if have else {}
		"trace":
			keys = TraceMods.MODS
			saved = cfg.get_value("browser", "trace_mods", {}) if have else {}
	for k: String in keys:
		out[k] = bool((saved as Dictionary).get(k, false)) if saved is Dictionary else false
	return out


## Mods eines Stufenstarts: die des Spielers plus die der Stufe (SV); No Fail immer aus.
static func start_mods(stage: Dictionary, player: Dictionary) -> Dictionary:
	var out := player.duplicate()
	for m: Variant in stage.get("mods", []):
		out[str(m)] = true
	out["NF"] = false
	return out


# ------------------------------------------------------------------ Ziele

static func grade_value(g: String) -> int:
	return GRADE_ORDER.find(g.to_upper())


## Lauf: {failed, accuracy (0..1), grade, n_miss, score, max_combo} (ManiaCore.stats-Form).
## Ein Fail erfuellt nie ein Ziel.
static func goal_met(goal: Dictionary, run: Dictionary) -> bool:
	if bool(run.get("failed", false)):
		return false
	match str(goal.get("type", "")):
		"pass":
			return true
		"acc":
			return float(run.get("accuracy", 0.0)) + 0.000001 >= float(goal.get("value", 2.0))
		"grade":
			var need := grade_value(str(goal.get("value", "")))
			return need >= 0 and grade_value(str(run.get("grade", "F"))) >= need
		"miss":
			return int(run.get("n_miss", 999999)) <= int(goal.get("value", -1))
	return false


## Erfuellte Ziele eines Laufs als [bool, bool, bool]. Zusatz- und Meisterziel
## zaehlen nur, wenn das Hauptziel geschafft ist.
static func goals_met(stage: Dictionary, run: Dictionary) -> Array:
	var out: Array = []
	var gs: Array = stage.get("goals", [])
	var main: bool = gs.size() > 0 and goal_met(gs[0], run)
	for i in GOALS_PER_STAGE:
		out.append(main and i < gs.size() and goal_met(gs[i], run))
	return out


## Stand eines Ziels waehrend des Laufs (stats wie ManiaCore.stats()).
const LIVE_OPEN := 0   ## noch offen (pass erst am Ende, acc/grade gerade darunter)
const LIVE_HOLD := 1   ## waere jetzt erfuellt
const LIVE_LOST := 2   ## in diesem Lauf nicht mehr zu schaffen (Fail, zu viele Misses)


static func goal_live(goal: Dictionary, stats: Dictionary) -> int:
	if bool(stats.get("failed", false)):
		return LIVE_LOST
	match str(goal.get("type", "")):
		"miss":
			return LIVE_LOST if int(stats.get("n_miss", 0)) > int(goal.get("value", 0)) else LIVE_HOLD
		"acc", "grade":
			return LIVE_HOLD if goal_met(goal, stats) else LIVE_OPEN
	return LIVE_OPEN


## Alle drei Ziele live. Ist das Hauptziel verloren, sind es die anderen auch.
static func goals_live(stage: Dictionary, stats: Dictionary) -> Array:
	var gs: Array = stage.get("goals", [])
	var out: Array = []
	for i in gs.size():
		out.append(goal_live(gs[i], stats))
	if not out.is_empty() and int(out[0]) == LIVE_LOST:
		out.fill(LIVE_LOST)
	return out


## Aktueller Wert zum Ziel im Lauf: Genauigkeit, Misses "3 / 8", Rang ("" bei pass).
static func goal_live_value(goal: Dictionary, stats: Dictionary) -> String:
	match str(goal.get("type", "")):
		"acc":
			return acc_text(float(stats.get("accuracy", 0.0)))
		"miss":
			return "%d / %d" % [int(stats.get("n_miss", 0)), int(goal.get("value", 0))]
		"grade":
			return str(stats.get("grade", ""))
	return ""


## Wert des eigenen Bestlaufs zu einem Ziel ("" = nicht gespielt oder nichts zu zeigen).
static func goal_best_value(goal: Dictionary, e: Dictionary) -> String:
	if not e.has("score"):
		return ""
	match str(goal.get("type", "")):
		"acc":
			return acc_text(float(e.get("accuracy", 0.0)))
		"miss":
			var n := int(e.get("n_miss", 0))
			return tr_("1 Miss") if n == 1 else (tr_("%d Misses") % n)
		"grade":
			return str(e.get("grade", ""))
	return ""


## Warum eine Stufe gesperrt ist ("" = offen).
static func lock_reason(data: Dictionary, state: Dictionary, id: String) -> String:
	if stage_open(data, state, id):
		return ""
	var ci := chapter_index_of(data, id)
	if ci < 0:
		return ""
	if not chapter_open(data, state, ci):
		return tr_("Erst den Boss von Kapitel %d schaffen") % ci
	var sts: Array = (chapters(data)[ci] as Dictionary).get("stages", [])
	for i in range(1, sts.size()):
		if str((sts[i] as Dictionary).get("id", "")) == id:
			return tr_("Erst %s schaffen") % stage_label(sts[i - 1], i - 1)
	return ""


## Stufen eines Kapitels, deren Hauptziel geschafft ist.
static func chapter_cleared_count(ch: Dictionary, state: Dictionary) -> int:
	var n := 0
	for s: Dictionary in ch.get("stages", []):
		if stage_cleared(state, str(s.get("id", ""))):
			n += 1
	return n


static func count_true(a: Array) -> int:
	var n := 0
	for v: Variant in a:
		if bool(v):
			n += 1
	return n


## Sterne eines einzelnen Laufs (0..3).
static func stars_for(stage: Dictionary, run: Dictionary) -> int:
	return count_true(goals_met(stage, run))


# ------------------------------------------------------------------ Fortschritt

static func new_state() -> Dictionary:
	return {"version": VERSION, "stages": {}}


static func entry(state: Dictionary, id: String) -> Dictionary:
	var st: Variant = state.get("stages", {})
	if st is Dictionary and (st as Dictionary).get(id) is Dictionary:
		return st[id]
	return {}


static func met_of(state: Dictionary, id: String) -> Array:
	var m: Variant = entry(state, id).get("met", [])
	var out: Array = []
	for i in GOALS_PER_STAGE:
		out.append(m is Array and i < (m as Array).size() and bool(m[i]))
	return out


## Sterne der Stufe (Ziele bleiben ueber Laeufe hinweg erfuellt).
static func stage_stars(state: Dictionary, id: String) -> int:
	return count_true(met_of(state, id))


static func stage_cleared(state: Dictionary, id: String) -> bool:
	return bool(met_of(state, id)[0])


## Lauf eintragen. Liefert {stars_run, stars, gained, met_run, met, new_best, cleared_now}.
static func apply_run(state: Dictionary, stage: Dictionary, run: Dictionary) -> Dictionary:
	var id := str(stage.get("id", ""))
	if not (state.get("stages") is Dictionary):
		state["stages"] = {}
	var e := entry(state, id).duplicate()
	var before := met_of(state, id)
	var now := goals_met(stage, run)
	var merged: Array = []
	for i in GOALS_PER_STAGE:
		merged.append(bool(before[i]) or bool(now[i]))
	var score := int(run.get("score", 0))
	var ok := bool(now[0])
	var new_best := ok and score > int(e.get("score", -1))
	e["met"] = merged
	e["plays"] = int(e.get("plays", 0)) + 1
	if new_best:
		e["score"] = score
		e["accuracy"] = float(run.get("accuracy", 0.0))
		e["grade"] = str(run.get("grade", ""))
		e["max_combo"] = int(run.get("max_combo", 0))
		e["n_miss"] = int(run.get("n_miss", 0))
	state["stages"][id] = e
	return {"stars_run": count_true(now), "stars": count_true(merged),
		"gained": count_true(merged) - count_true(before), "met_run": now, "met": merged,
		"new_best": new_best, "cleared_now": ok and not bool(before[0])}


## Stufe offen: erste Stufe des offenen Kapitels oder Vorgaenger geschafft.
static func stage_open(data: Dictionary, state: Dictionary, id: String) -> bool:
	var ci := chapter_index_of(data, id)
	if ci < 0 or not chapter_open(data, state, ci):
		return false
	var sts: Array = (chapters(data)[ci] as Dictionary).get("stages", [])
	for i in sts.size():
		if str((sts[i] as Dictionary).get("id", "")) == id:
			return i == 0 or stage_cleared(state, str((sts[i - 1] as Dictionary).get("id", "")))
	return false


## Kapitel offen: das erste immer, sonst wenn die Boss-Stufe davor geschafft ist.
static func chapter_open(data: Dictionary, state: Dictionary, ci: int) -> bool:
	var chs := chapters(data)
	if ci < 0 or ci >= chs.size():
		return false
	if ci == 0:
		return true
	return chapter_done(chs[ci - 1], state)


static func chapter_done(ch: Dictionary, state: Dictionary) -> bool:
	var sts: Array = ch.get("stages", [])
	return not sts.is_empty() and stage_cleared(state, str((sts[sts.size() - 1] as Dictionary).get("id", "")))


static func chapter_stars(ch: Dictionary, state: Dictionary) -> int:
	var n := 0
	for s: Dictionary in ch.get("stages", []):
		n += stage_stars(state, str(s.get("id", "")))
	return n


static func chapter_max_stars(ch: Dictionary) -> int:
	return (ch.get("stages", []) as Array).size() * GOALS_PER_STAGE


## Erste offene, noch nicht geschaffte Stufe ("" = alles geschafft).
static func current_stage_id(data: Dictionary, state: Dictionary) -> String:
	for s: Dictionary in all_stages(data):
		var id := str(s.get("id", ""))
		if not stage_cleared(state, id):
			return id if stage_open(data, state, id) else ""
	return ""


static func total_stars(data: Dictionary, state: Dictionary) -> int:
	var n := 0
	for s: Dictionary in all_stages(data):
		n += stage_stars(state, str(s.get("id", "")))
	return n


static func max_stars(data: Dictionary) -> int:
	return all_stages(data).size() * GOALS_PER_STAGE


## Gesamtpunkte: Summe der Bestwerte aller geschafften Stufen (Gleichstand bei Sternen).
static func total_points(data: Dictionary, state: Dictionary) -> int:
	var n := 0
	for s: Dictionary in all_stages(data):
		var id := str(s.get("id", ""))
		if stage_cleared(state, id):
			n += int(entry(state, id).get("score", 0))
	return n


# ------------------------------------------------------------------ Datei

## Echte Datei: user://campaign.json. --campaign-path=<Datei> (Harness) und
## Headless-Tests (--script) bekommen immer eine eigene Datei.
static func default_path() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--campaign-path="):
			return a.trim_prefix("--campaign-path=")
	for a in OS.get_cmdline_args():
		if a == "--script" or a == "-s":
			DirAccess.make_dir_recursive_absolute("user://test_tmp")
			return "user://test_tmp/campaign_%d.json" % OS.get_process_id()
	return PATH


static func load_state(path: String = "") -> Dictionary:
	var p := default_path() if path == "" else path
	if not FileAccess.file_exists(p):
		return new_state()
	# JSON-Instanz statt parse_string: kaputte Datei ohne Fehlerzeile im Log.
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK:
		return new_state()
	var d: Variant = j.data
	if not (d is Dictionary) or not ((d as Dictionary).get("stages") is Dictionary):
		return new_state()
	return d


static func save_state(state: Dictionary, path: String = "") -> bool:
	var p := default_path() if path == "" else path
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(state, " "))
	f.close()
	return true


# ------------------------------------------------------------------ Maps

## Set-ID aus dem Dateinamen: "mirror_123.osz" oder "123 Artist - Title.osz" (0 = keine).
static func set_id_of_file(osz_file: String) -> int:
	var s := osz_file.get_file().trim_prefix("mirror_")
	var digits := ""
	for c in s:
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	return int(digits) if digits != "" else 0


## Lokale Map der Stufe: {osz_path, index, version, osu_filename, stars} oder {}.
## sets: Array aus MapSet (oder Dictionaries {osz_path, diffs:[{version, osu_filename, stars}]}).
## Diff-Name der Liste gegen den Namen in der .osu. Die Online-Quelle setzt bei Mania
## die Tastenzahl davor ("[4K] Easy"), in der Datei steht nur "Easy".
static func diff_matches(want: String, have: String) -> bool:
	if want == have:
		return true
	var close := want.find("K] ")
	return want.begins_with("[") and close >= 2 and want.substr(1, close - 1).is_valid_int() 			and want.substr(close + 3) == have


static func find_local(stage: Dictionary, sets: Array) -> Dictionary:
	var want := int(stage.get("set_id", 0))
	if want <= 0:
		return {}
	var diff := str(stage.get("diff", ""))
	for ms: Variant in sets:
		var osz := str(ms.get("osz_path"))
		if set_id_of_file(osz) != want:
			continue
		var diffs: Array = ms.get("diffs")
		for i in diffs.size():
			var d: Dictionary = diffs[i]
			if diff_matches(diff, str(d.get("version", ""))):
				return {"osz_path": osz, "index": i, "version": str(d.get("version", "")),
					"osu_filename": str(d.get("osu_filename", "")), "stars": float(d.get("stars", -1.0)),
					"set": ms}
	return {}


## Set-IDs des Kapitels, die lokal fehlen (ohne Doppelte, Reihenfolge der Stufen).
static func missing_sets(ch: Dictionary, sets: Array) -> Array[int]:
	var out: Array[int] = []
	for s: Dictionary in ch.get("stages", []):
		var id := int(s.get("set_id", 0))
		if has_map(s) and not out.has(id) and find_local(s, sets).is_empty():
			out.append(id)
	return out


# ------------------------------------------------------------------ Texte

static func tr_(msg: String) -> String:
	return str(TranslationServer.translate(msg))


static func pct_text(v: float) -> String:
	var p := v * 100.0
	var t := str(int(roundf(p))) if absf(p - roundf(p)) < 0.05 else ("%.1f" % p)
	if TranslationServer.get_locale().begins_with("de"):
		return t.replace(".", ",") + " %"
	return t + "%"


## Genauigkeit mit zwei Nachkommastellen ("97,12 %" / "97.12%").
static func acc_text(v: float) -> String:
	var t := "%.2f" % (v * 100.0)
	if TranslationServer.get_locale().begins_with("de"):
		return t.replace(".", ",") + " %"
	return t + "%"


static func goal_text(goal: Dictionary) -> String:
	match str(goal.get("type", "")):
		"pass":
			return tr_("Ohne Fail beenden")
		"acc":
			return tr_("Genauigkeit ab %s") % pct_text(float(goal.get("value", 0.0)))
		"grade":
			var g := str(goal.get("value", ""))
			return (tr_("Rang %s") % g) if g == "SS" else (tr_("Rang %s oder besser") % g)
		"miss":
			var n := int(goal.get("value", 0))
			if n == 0:
				return tr_("Kein Miss")
			return tr_("Höchstens %d Misses") % n
	return ""


## Kurzform fuer das Spiel-HUD ("Genauigkeit ≥ 95,8 %", "≤ 8 Misses").
static func goal_short(goal: Dictionary) -> String:
	match str(goal.get("type", "")):
		"pass":
			return tr_("Ohne Fail")
		"acc":
			return tr_("Genauigkeit ≥ %s") % pct_text(float(goal.get("value", 0.0)))
		"grade":
			var g := str(goal.get("value", ""))
			return (tr_("Rang %s") % g) if g == "SS" else (tr_("Rang ≥ %s") % g)
		"miss":
			var n := int(goal.get("value", 0))
			return tr_("Kein Miss") if n == 0 else (tr_("≤ %d Misses") % n)
	return ""


static func goal_name(index: int) -> String:
	var names: Array[String] = ["Ziel", "Zusatzziel", "Meisterziel"]
	return tr_(names[clampi(index, 0, 2)])


static func world_label(world: String) -> String:
	return tr_(str(WorldTheme.LABELS.get(world, world)))


static func stage_label(stage: Dictionary, index: int) -> String:
	return tr_("Boss") if bool(stage.get("boss", false)) else (tr_("Stufe %d") % (index + 1))


static func length_text(seconds: int) -> String:
	@warning_ignore("integer_division")
	return "%d:%02d" % [seconds / 60, seconds % 60]
