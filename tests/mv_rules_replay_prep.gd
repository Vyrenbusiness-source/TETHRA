extends SceneTree

## Harness-Vorbereitung (Task mv-rules): legt in user:// einen Minen-Lauf an, wie ihn das
## Spiel speichert (ReplayStore + ScoreStore "mania_mn" + History), damit der Song-Browser
## die Minen-Liste zeigt und der Replay-Knopf den Lauf im Spiel abspielt
## (RuleModsHarness.run_browser, --rules-harness).
## NUR mit eigenem APPDATA starten (user:// des Tests, nie die Nutzerdaten):
##   APPDATA=<test> Godot --headless --path . --script res://tests/mv_rules_replay_prep.gd -- --maps-dir=<ordner>
## Waehlt die kuerzeste 4K-Diff (150+ Noten, hoechstens --max-s=40 s), spielt sie wie
## Autoplay und drueckt zusaetzlich in jede 4. Mine (Treffer). Gibt "PREP ..." aus.


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with(key + "="):
			return a.trim_prefix(key + "=")
	return fallback


func _run() -> void:
	var udir := ProjectSettings.globalize_path("user://")
	if udir.to_lower().contains("roaming/godot/app_userdata") and _arg("--i-know", "") == "":
		print("PREP FAIL user:// ist das echte Nutzerverzeichnis (%s): APPDATA setzen" % udir)
		quit(2)
		return
	var dir := _arg("--maps-dir", MapLibrary.default_maps_dir())
	var max_ms := float(_arg("--max-s", "40")) * 1000.0
	var pick: Dictionary = {}
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".osz"):
			continue
		var imp := OszImporter.import(dir.path_join(f))
		if not imp.ok:
			continue
		for d in imp.difficulties:
			var bm: Beatmap = d.beatmap
			if not bm.is_mania() or bm.column_count() != 4 or bm.hit_objects.size() < 150:
				continue
			var len_ms := float(bm.hit_objects.back().end_time())
			if len_ms > max_ms or (not pick.is_empty() and len_ms >= float(pick.len)):
				continue
			pick = {"osz": dir.path_join(f), "bm": bm, "len": len_ms}
	if pick.is_empty():
		print("PREP FAIL keine 4K-Diff unter %d s in %s" % [int(max_ms / 1000.0), dir])
		quit(1)
		return
	var bm: Beatmap = pick.bm
	var mods := {"SV": false, "NF": false, "MN": true, "MN_v": MineGen.VERSION}
	var core := ManiaCore.new()
	core.setup(bm)
	core.mods = mods.duplicate()
	RuleMods.setup_core(core)
	var events := _play(core, bm)
	var s := core.stats()
	s["pp"] = -1.0
	var osz: String = pick.osz
	var ver := bm.version_name()
	ScoreStore.submit(osz, ver, s, RuleMods.MINES_SCORE_MODE)
	ScoreStore.log_play(osz, ver, "%s - %s" % [bm.artist(), bm.title()], s, RuleMods.MINES_SCORE_MODE)
	ReplayStore.save(osz, ver, events, {"score": int(s.score), "grade": str(s.grade),
		"accuracy": float(s.accuracy), "date": Time.get_datetime_string_from_system(),
		"mods": RuleMods.replay_mods(mods, core.mods)})
	print("PREP map=%s ver=%s len=%d notes=%d mines=%d mine_hits=%d score=%d n_miss=%d events=%d" % [
		osz.get_file(), ver, int(pick.len), bm.hit_objects.size(), core.mines.count(), core.n_mine_hit,
		int(s.score), int(s.n_miss), events.size()])
	print("PREP title=%s" % bm.title())
	quit(0)


## Autoplay wie mania_3d (Tap 40 ms, Hold bis Ende) plus ein kurzer Druck in jede 4. Mine.
func _play(core: ManiaCore, bm: Beatmap) -> Array:
	var evs: Array = []
	var objs := bm.hit_objects
	for n in objs:
		var mn := n as ManiaNote
		evs.append({"t": mn.time, "lane": mn.column, "down": true})
		evs.append({"t": mn.end_time() if mn.is_hold else mn.time + 40.0, "lane": mn.column, "down": false})
	for i in core.mines.count():
		if i % 4 == 0:
			var t := core.mines.times[i]
			evs.append({"t": t - 4.0, "lane": core.mines.cols[i], "down": true})
			evs.append({"t": t + 20.0, "lane": core.mines.cols[i], "down": false})
	evs.sort_custom(func(a, b): return float(a.t) < float(b.t) or (float(a.t) == float(b.t) and not bool(a.down)))
	# Ueberlappende Druecke je Spalte entwirren: Druck in eine gedrueckte Spalte -> erst loslassen.
	var out: Array = []
	var held := [false, false, false, false]
	for e in evs:
		var c := int(e.lane)
		if bool(e.down):
			if held[c]:
				out.append({"t": float(e.t), "lane": c, "down": false})
			held[c] = true
			out.append(e)
		elif held[c]:
			held[c] = false
			out.append(e)
	var t_end := float(objs.back().end_time()) + 2000.0
	var k := 0
	var t := 0.0
	while t <= t_end:
		while k < out.size() and float(out[k].t) <= t:
			var ev: Dictionary = out[k]
			if bool(ev.down):
				core.key_down(int(ev.lane), float(ev.t))
			else:
				core.key_up(int(ev.lane), float(ev.t))
			k += 1
		core.update(t)
		t += 4.0
	return out
