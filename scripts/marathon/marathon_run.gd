class_name MarathonRun
extends RefCounted

## Laufender Marathon (statisch, ueberlebt Szenenwechsel wie GameSession):
## Plan -> Maps laden -> Zeitachse -> eine zusammengefuegte Beatmap, die die
## normale Mania-Szene (mania_3d) wie eine einzelne Map spielt. Dadurch sind HP
## und Kombo automatisch gemeinsam, Replays zeichnen globale Zeiten auf.
##
## Haken in mania_3d (klein): _load_beatmap (Map + Audio), _ready (attach),
## _show_results (Wertung/Replay hier statt ScoreStore), _back_to_browser (end).
##
## Plan (Dictionary, JSON-tauglich, steckt im Replay):
##   v, length (Laengen-Schluessel), seed, source ("auto" | "coll:<Name>"),
##   target_stars, maps: [{osz, version, osu, stars, bpm, title, artist, ...}],
##   timeline (nach dem ersten Laden; Replays benutzen sie unveraendert)

static var current: MarathonRun = null
static var _cmdline_checked := false

var plan: Dictionary = {}
var beatmaps: Array = []
var streams: Array = []
var gains_db: Array = []
var audio_ms: Array = []
var segs: Array = []
var merged: Beatmap
var note_ranges: Array = []
var mixer: MarathonMixer
var hud: MarathonHud
## Wertung je Map (index = Segment).
var per_map: Array = []
var _core: ManiaCore
var _last_score := 0
var result_info: Dictionary = {}


static func is_active() -> bool:
	return current != null


## Fuer die Spielszene: aktiver Marathon, oder einer aus der Kommandozeile
## (--marathon-maps=<osz>|<version>;... Harness/Tests).
static func active_for_scene() -> bool:
	if current == null and not _cmdline_checked:
		_cmdline_checked = true
		var p := plan_from_cmdline()
		if not p.is_empty():
			begin(p)
			var gs := _session()
			if gs != null and _has_arg("--marathon-nf"):
				gs.mods["NF"] = true
	return current != null


static func _has_arg(flag: String) -> bool:
	return (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has(flag)


## Gespeichertes Replay ({meta, events}) als laufenden Marathon vorbereiten: Plan
## mit Zeitachse aus dem Replay, Mods und Eingaben in die GameSession.
static func start_replay(data: Dictionary) -> bool:
	var meta: Dictionary = data.get("meta", {})
	var p = meta.get("marathon", {})
	if not (p is Dictionary) or (p as Dictionary).get("maps", []).is_empty():
		return false
	begin(p)
	var gs := _session()
	if gs != null:
		gs.mods = gs.call("_replay_mods", data)
		gs.is_replay = true
		gs.replay_events = data.get("events", [])
		gs.replay_mode = "mania"
		gs.replay_end_ms = -1.0
	return true


static func plan_from_cmdline() -> Dictionary:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--marathon-replay="):
			# Gespeichertes Marathon-Replay abspielen (Harness/Tests).
			var data := MarathonStore.load_replay(a.trim_prefix("--marathon-replay="))
			if data.is_empty():
				push_warning("Marathon: Replay fehlt: " + a)
				return {}
			start_replay(data)
			return {}
		if a.begins_with("--marathon-maps="):
			# <osz>|<version>|<sterne>;...  (Sterne optional)
			var maps: Array = []
			var st_sum := 0.0
			for part in a.trim_prefix("--marathon-maps=").split(";", false):
				var kv := part.split("|")
				var st := kv[2].to_float() if kv.size() > 2 else 0.0
				st_sum += st
				maps.append({"osz": kv[0], "version": kv[1] if kv.size() > 1 else "", "stars": st})
			var n := maxi(maps.size(), 1)
			var key := MarathonPlan.length_key(MarathonPlan.KIND_COUNT, n) 					if MarathonPlan.COUNTS.has(n) else "n3"
			return new_plan(maps, key, 1, "cmdline", snappedf(st_sum / float(n), 0.01))
	return {}


static func new_plan(maps: Array, length: String, seed: int, source: String, target_stars: float) -> Dictionary:
	return {"v": MarathonPlan.VERSION, "length": length, "seed": seed, "source": source,
		"target_stars": target_stars, "maps": maps.duplicate(true)}


## Marathon starten (Song-Browser/Replay). Auswahl der Spielszene: erste Map.
static func begin(p_plan: Dictionary) -> void:
	current = MarathonRun.new()
	current.plan = p_plan.duplicate(true)
	var first: Dictionary = current.plan.maps[0] if not current.plan.maps.is_empty() else {}
	var gs := _session()
	if gs != null and not first.is_empty():
		gs.set_selection(str(first.osz), 0, str(first.get("version", "")),
				str(first.get("osu", "")), float(first.get("stars", -1.0)))


static func end() -> void:
	current = null


static func _session() -> Node:
	return autoload("GameSession")


## Autoload per Name (Marathon-Skripte nennen Autoloads nie direkt: so
## kompilieren sie auch in Test-Laeufen ohne Autoloads).
static func autoload(name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null(name)
	return null


## Plan-Schluessel (gleiche Maps in gleicher Reihenfolge = gleicher Marathon).
static func plan_key(p: Dictionary) -> String:
	var parts: Array = [str(p.get("length", ""))]
	for m in p.get("maps", []):
		parts.append("%s|%s" % [str(m.get("osz", "")).get_file(), str(m.get("version", ""))])
	return ";".join(parts).md5_text()


# --- Laden -------------------------------------------------------------------------

## Maps parsen, Audio laden, Zeitachse bauen (oder aus dem Plan/Replay nehmen),
## zusammenfuegen. false = eine Map fehlt.
func load_maps() -> bool:
	beatmaps.clear()
	streams.clear()
	gains_db.clear()
	audio_ms.clear()
	for m in plan.get("maps", []):
		var osz := str(m.get("osz", ""))
		var imp := OszImporter.import(osz)
		if not bool(imp.get("ok", false)):
			push_warning("Marathon: Map fehlt: " + osz)
			return false
		var bm: Beatmap = null
		for d in imp.difficulties:
			if d.beatmap.version_name() == str(m.get("version", "")):
				bm = d.beatmap
				break
		if bm == null:
			for d in imp.difficulties:
				if d.beatmap.is_mania() and d.beatmap.column_count() == 4:
					bm = d.beatmap
					break
		if bm == null or not bm.is_mania() or bm.hit_objects.is_empty():
			push_warning("Marathon: keine 4K-Diff: " + osz)
			return false
		if str(m.get("title", "")) == "":
			m["title"] = bm.title()
			m["artist"] = bm.artist()
		m["version"] = bm.version_name()
		beatmaps.append(bm)
		var st := OszImporter.load_audio_stream(osz, bm)
		streams.append(st)
		audio_ms.append(st.get_length() * 1000.0 if st != null else 0.0)
		gains_db.append(SongLoudness.gain_db_for_osz(osz))
	var tl: Array = plan.get("timeline", [])
	if tl.size() == beatmaps.size():
		segs = MarathonPlan.timeline_from_json(tl)
	else:
		segs = MarathonPlan.build_timeline(beatmaps, audio_ms)
		plan["timeline"] = MarathonPlan.timeline_to_json(segs)
	merged = MarathonPlan.merge(beatmaps, segs, "Marathon", note_ranges)
	# Titelzeile im Spiel: "Marathon — 3 Maps · ★ 3,4".
	merged.metadata["Artist"] = TranslationServer.translate("Marathon")
	merged.metadata["Title"] = length_label()
	var ts := float(plan.get("target_stars", 0.0))
	merged.metadata["Version"] = "★ %s" % UiTheme.fmt_num(ts, 1) if ts > 0.0 else "4K"
	_reset_per_map()
	return merged != null and not merged.hit_objects.is_empty()


func _reset_per_map() -> void:
	per_map.clear()
	_last_score = 0
	for i in beatmaps.size():
		per_map.append({"n_max": 0, "n300": 0, "n200": 0, "n100": 0, "n50": 0, "n_miss": 0,
			"score": 0, "combo": 0, "max_combo": 0, "judged": 0,
			"notes": int(note_ranges[i][1]) - int(note_ranges[i][0])})


## Fuer mania_3d._load_beatmap: Maps laden (einmal je Lauf, Neustart nutzt sie
## weiter), Song-Uhr mit dem Vorlauf der Szene starten. null = Map fehlt.
func scene_beatmap(is_2d: bool) -> Beatmap:
	if merged == null and not load_maps():
		return null
	var root := (Engine.get_main_loop() as SceneTree).root
	var settings := root.get_node_or_null("Settings")
	var gs := _session()
	var scroll := float(settings.get("mania_scroll")) if settings != null else 1.0
	var run_mods: Dictionary = (gs.mods as Dictionary).duplicate() if gs != null else {}
	if settings != null and gs != null and not bool(gs.is_replay):
		run_mods.merge(settings.call("extra_mods", is_2d), true)
	_reset_per_map()
	start_audio(maxf(ManiaCore.start_lead_ms(merged, scroll, run_mods), 1.0))
	return merged


## Song-Uhr starten: stumme Master-Spur ueber die ganze Laenge (Decks folgen ihr).
func start_audio(lead_ms: float) -> void:
	var len_ms := MarathonPlan.timeline_end(segs) + 4000.0
	var master := MarathonMixer.click_master(len_ms) if MarathonHarness.wanted() 			else MarathonMixer.silent_master(len_ms)
	autoload("SyncClock").play(master, lead_ms)


## Spielszene ist aufgebaut: Mixer, Anzeige, Wertung je Map anhaengen.
func attach(host: Node, core: ManiaCore, hud_layer: CanvasLayer) -> void:
	_core = core
	_last_score = core.score
	result_info = {}
	mixer = MarathonMixer.new()
	mixer.name = "MarathonMixer"
	mixer.setup(segs, streams, gains_db)
	host.add_child(mixer)
	if not core.note_judged.is_connected(_on_judged):
		core.note_judged.connect(_on_judged)
	if hud_layer != null:
		hud = MarathonHud.new()
		hud.name = "MarathonHud"
		hud_layer.add_child(hud)
		hud.setup(self, host)
	if MarathonHarness.wanted():
		var h := MarathonHarness.new()
		h.name = "MarathonHarness"
		host.add_child(h)
		h.start(self, host)


func segment_of_note(index: int) -> int:
	for i in note_ranges.size():
		if index >= int(note_ranges[i][0]) and index < int(note_ranges[i][1]):
			return i
	return note_ranges.size() - 1


func _on_judged(index: int, result: Dictionary) -> void:
	var i := segment_of_note(index)
	if i < 0 or i >= per_map.size():
		return
	var pm: Dictionary = per_map[i]
	var q := int(result.get("quality", ManiaCore.Quality.MISS))
	var key: String = ["n_max", "n300", "n200", "n100", "n50", "n_miss"][clampi(q, 0, 5)]
	pm[key] = int(pm[key]) + 1
	pm.judged = int(pm.judged) + 1
	if q == ManiaCore.Quality.MISS:
		pm.combo = 0
	else:
		pm.combo = int(pm.combo) + 1
		pm.max_combo = maxi(int(pm.max_combo), int(pm.combo))
	if _core != null:
		pm.score = int(pm.score) + (_core.score - _last_score)
		_last_score = _core.score


static func map_accuracy(pm: Dictionary) -> float:
	var total := int(pm.n_max) + int(pm.n300) + int(pm.n200) + int(pm.n100) + int(pm.n50) + int(pm.n_miss)
	if total == 0:
		return 0.0
	return float(300 * (int(pm.n_max) + int(pm.n300)) + 200 * int(pm.n200) + 100 * int(pm.n100)
			+ 50 * int(pm.n50)) / float(300 * total)


## Map, die bei globaler Zeit g spielt (Wechsel an der Uebergangsmitte).
func map_at(g: float) -> int:
	return MarathonMixer.active_segment(segs, g)


func map_info(i: int) -> Dictionary:
	var maps: Array = plan.get("maps", [])
	return maps[i] if i >= 0 and i < maps.size() else {}


func length_label() -> String:
	return length_text(str(plan.get("length", "")), plan.get("maps", []).size())


static func length_text(length: String, n_maps: int = 0) -> String:
	var lk := MarathonPlan.parse_length_key(length)
	if lk.is_empty():
		return TranslationServer.translate("%d maps") % n_maps
	if str(lk.kind) == MarathonPlan.KIND_COUNT:
		return TranslationServer.translate("%d maps") % int(lk.value)
	return TranslationServer.translate("%d min") % int(lk.value)


# --- Ende: Wertung, Rangliste, Replay ------------------------------------------------

## Haken aus mania_3d._show_results: entscheidet, ob gespeichert wird (nie bei
## Replay/Tutorial/Autoplay; Harness mit --marathon-store speichert den Autoplay-
## Lauf samt erzeugten Eingaben, damit das Replay geprueft werden kann).
func finish_scene(s: Dictionary, is_fail: bool, recorded: Array, autoplay: bool) -> Dictionary:
	var gs := _session()
	var replay := gs != null and bool(gs.is_replay)
	var tutorial := gs != null and bool(gs.tutorial)
	var rec := recorded
	var store := not replay and not tutorial and not autoplay
	if autoplay and not replay and _has_arg("--marathon-store"):
		rec = MarathonHarness.autoplay_events(merged)
		store = true
	return finish(s, is_fail, rec, store)


## Vom Spiel nach dem Lauf. Speichert (ausser Replay/Autoplay) Rangliste + Replay.
## Liefert Zusatzdaten fuer den ResultsScreen.
func finish(s: Dictionary, is_fail: bool, recorded: Array, store: bool) -> Dictionary:
	var length := str(plan.get("length", ""))
	var maps_done := 0
	for i in per_map.size():
		if int(per_map[i].judged) >= int(per_map[i].notes) and int(per_map[i].notes) > 0:
			maps_done += 1
	var titles: Array = []
	for m in plan.get("maps", []):
		titles.append(str(m.get("title", "")))
	var info := {"rank": 0, "is_new_best": false, "maps_done": maps_done, "replay_id": ""}
	if store:
		var date := Time.get_datetime_string_from_system()
		var rid := ("%s|%s" % [plan_key(plan), date]).md5_text()
		var mods: Array = []
		var gs := _session()
		if gs != null:
			for k in (gs.mods as Dictionary):
				if bool(gs.mods[k]) and str(k).length() <= 3:
					mods.append(str(k))
		var entry := {
			"score": int(s.get("score", 0)), "accuracy": float(s.get("accuracy", 0.0)),
			"max_combo": int(s.get("max_combo", 0)), "grade": "F" if is_fail else str(s.get("grade", "D")),
			"n_miss": int(s.get("n_miss", 0)), "failed": is_fail, "maps": titles,
			"maps_done": maps_done, "stars": float(plan.get("target_stars", 0.0)),
			"date": date, "replay": rid, "mods": mods, "key": plan_key(plan),
		}
		var res := MarathonStore.submit(length, entry)
		info.rank = int(res.rank)
		info.is_new_best = bool(res.is_new_best)
		info["previous"] = res.get("previous", {})
		var meta := {
			"mode": "marathon", "marathon": plan.duplicate(true),
			"score": entry.score, "grade": entry.grade, "accuracy": entry.accuracy,
			"date": date,
			# Wie Einzel-Replays: Start-Mods + Minen-Version des Laufs (gleiche Minen).
			"mods": RuleMods.replay_mods(gs.mods, _core.mods if _core != null else {}) if gs != null else {},
		}
		if MarathonStore.save_replay(rid, recorded, meta):
			info.replay_id = rid
		# Online: eigener Schluessel, vorerst NICHT senden (Bericht).
		info["online"] = MarathonStore.online_payload(length, entry, plan.get("maps", []))
	result_info = info
	return info


## Zusatzdaten fuer ResultsScreen.show_results (Reiter "Maps", Kennzahlen).
func results_data(data: Dictionary) -> void:
	var n: int = plan.get("maps", []).size()
	var titles: Array = []
	for m in plan.get("maps", []):
		titles.append(str(m.get("title", "")))
	data["title"] = TranslationServer.translate("Marathon")
	data["artist"] = "  ›  ".join(titles)
	var ts := float(plan.get("target_stars", 0.0))
	data["version"] = "%s · ★ %s" % [length_label(), UiTheme.fmt_num(ts, 1)] if ts > 0.0 else length_label()
	data["can_clip"] = false  # Clip-Export kennt nur Einzel-Replays
	var rank := int(result_info.get("rank", 0))
	data["hero_extra"] = [
		[TranslationServer.translate("MAPS"), "%d/%d" % [int(result_info.get("maps_done", 0)), n]],
		[TranslationServer.translate("RANK"), "#%d" % rank if rank > 0 else "–"],
	]
	data["new_best"] = bool(result_info.get("is_new_best", false))
	data["mode_page"] = {"title": TranslationServer.translate("Maps"), "content": MarathonHud.results_table(self)}
	# Vergleich nur mit dem bisherigen Marathon-Bestwert dieser Laenge; kein
	# Dictionary = kein Vergleich (sonst nimmt der Screen den Bestwert der ersten Map).
	if result_info.has("previous") and not (result_info.previous as Dictionary).is_empty():
		data["previous_best"] = result_info.previous
	else:
		data["previous_best"] = false
