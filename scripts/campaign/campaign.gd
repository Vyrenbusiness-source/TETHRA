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


## Formatpruefung: Liste der Fehler (leer = gueltig).
static func validate(data: Dictionary) -> Array[String]:
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
			if str(d.get("version", "")) == diff:
				return {"osz_path": osz, "index": i, "version": diff,
					"osu_filename": str(d.get("osu_filename", "")), "stars": float(d.get("stars", -1.0))}
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
