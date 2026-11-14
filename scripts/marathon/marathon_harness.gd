class_name MarathonHarness
extends Node

## Pruef-Lauf fuer den Marathon (nur mit --marathon-harness=<ordner>):
##   * Screenshots um jeden Uebergang (1 Takt vor der Mitte, Mitte, erste Noten
##     der neuen Map) und vom Ergebnis (Uebersicht + Reiter "Maps").
##   * Mitschnitt des Master-Busses je Uebergang (+- REC_MS um die Mitte) als
##     WAV; tools/marathon_sync_check.py misst daraus die Taktgrenzen-Abweichung.
##   * report.json: Zeitachse, Notenluecken, Deck-Abweichung (Mixer, je Uebergang),
##     Endwertung und Wertung je Map.
## Zusammen mit --marathon-maps=... --autoplay (siehe docs/modes/marathon.md).

const REC_MS := 8000.0

var _run: MarathonRun
var _host: Node
var _dir := ""
var _shots: Array = []  ## [{t, name}] aufsteigend
var _recs: Array = []   ## [{from, to, i, active, start_g}]
var _rec_fx: AudioEffectRecord
var _rec_bus := -1
var _report := {}
var _done := false


static func wanted() -> bool:
	return out_dir() != ""


static func out_dir() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--marathon-harness="):
			return a.trim_prefix("--marathon-harness=")
	return ""


func start(run: MarathonRun, host: Node) -> void:
	_run = run
	_host = host
	_dir = out_dir()
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(_dir)
	if run.mixer != null:
		run.mixer.log_errors = true
	var tag := "2d" if bool(host.get("_2d")) else "3d"
	var segs := run.segs
	for i in range(1, segs.size()):
		var mid := float(segs[i].mid_in)
		var bar := float(segs[i].beat_in) * 4.0
		_shots.append({"t": mid - bar, "name": "%s_t%d_a_before.png" % [tag, i]})
		_shots.append({"t": mid, "name": "%s_t%d_b_mid.png" % [tag, i]})
		var first_b := _first_note_of(i)
		_shots.append({"t": maxf(first_b - 250.0, mid + 200.0), "name": "%s_t%d_c_newmap.png" % [tag, i]})
		_recs.append({"from": mid - REC_MS, "to": mid + REC_MS, "i": i, "active": false, "start_g": 0.0})
	_shots.sort_custom(func(a, b): return float(a.t) < float(b.t))
	# Mitschnitt: Record-Effekt ans Ende des Master-Busses (vor der Ausgabe).
	_rec_bus = AudioServer.get_bus_index(&"Master")
	_rec_fx = AudioEffectRecord.new()
	_rec_fx.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(_rec_bus, _rec_fx)
	print("MARATHON-HARNESS start: %d Maps, %d Uebergaenge, Ende %.0f ms" % [segs.size(),
		segs.size() - 1, MarathonPlan.timeline_end(segs)])


func _exit_tree() -> void:
	_remove_rec()


func _remove_rec() -> void:
	if _rec_fx == null:
		return
	for k in AudioServer.get_bus_effect_count(_rec_bus):
		if AudioServer.get_bus_effect(_rec_bus, k) == _rec_fx:
			AudioServer.remove_bus_effect(_rec_bus, k)
			break
	_rec_fx = null


func _first_note_of(i: int) -> float:
	var r: Array = _run.note_ranges[i]
	if int(r[0]) < _run.merged.hit_objects.size():
		return _run.merged.hit_objects[int(r[0])].time
	return float(_run.segs[i].mid_in)


func _process(_delta: float) -> void:
	if _done or _run == null:
		return
	if _host.get("_results_screen") != null:
		_done = true
		_finish()
		return
	var clock := MarathonRun.autoload("SyncClock")
	if clock == null or not clock.is_playing():
		return
	var g: float = clock.song_time_ms()
	while not _shots.is_empty() and g >= float(_shots[0].t):
		var s: Dictionary = _shots.pop_front()
		_shot(str(s.name), g)
	var inst := _rec_instance()
	for r in _recs:
		if not bool(r.active) and g >= float(r.from) and g < float(r.to) and inst != null \
				and not inst.is_recording_active():
			r.active = true
			r.start_g = g
			r["start_raw"] = clock.raw_time_ms()
			inst.set_recording_active(true)
		elif bool(r.active) and g >= float(r.to):
			r.active = false
			r["stop_g"] = g
			var wav := inst.get_recording() if inst != null else null
			inst.set_recording_active(false)
			if wav != null:
				var p := "%s/trans_%d.wav" % [_dir, int(r.i)]
				wav.save_to_wav(p)
				r["wav"] = p
				r["mix_rate"] = wav.mix_rate


func _rec_instance() -> AudioEffectRecord:
	return _rec_fx


func _shot(name: String, g: float) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s" % [_dir, name])
	print("MARATHON-HARNESS shot %s bei %.0f ms" % [name, g])


func _finish() -> void:
	var segs := _run.segs
	var trans: Array = []
	var ho := _run.merged.hit_objects
	for i in range(1, segs.size()):
		var a_rng: Array = _run.note_ranges[i - 1]
		var b_rng: Array = _run.note_ranges[i]
		var last_a := 0.0
		for k in range(int(a_rng[0]), int(a_rng[1])):
			last_a = maxf(last_a, ho[k].end_time())
		var first_b := ho[int(b_rng[0])].time if int(b_rng[0]) < ho.size() else INF
		var mid := float(segs[i].mid_in)
		var errs: Array = []
		if _run.mixer != null:
			for e in _run.mixer.err_log:
				if absf(float(e[0]) - mid) <= REC_MS:
					errs.append(absf(float(e[2])))
		errs.sort()
		var rec: Dictionary = {}
		for r in _recs:
			if int(r.i) == i:
				rec = r
		trans.append({
			"i": i, "mid": mid, "rho": float(segs[i].rho), "m": float(segs[i].m),
			"tempo_ok": bool(segs[i].tempo_ok), "beat_a": float(segs[i].beat_in),
			"last_a_end": last_a, "first_b": first_b,
			"gap_ms": first_b - last_a, "gap_beats": (first_b - last_a) / float(segs[i].beat_in),
			"deck_err_mean": _mean(errs), "deck_err_p95": _pct(errs, 0.95),
			"deck_err_max": float(errs.back()) if not errs.is_empty() else 0.0,
			"deck_err_n": errs.size(),
			"rec": rec,
		})
	var s: Dictionary = _host.get("core").stats() if _host.get("core") != null else {}
	_report = {
		"plan": _run.plan, "transitions": trans, "stats": s, "per_map": _run.per_map,
		"seeks": _run.mixer.seeks if _run.mixer != null else -1,
		"max_locked_err_ms": _run.mixer.max_locked_err_ms if _run.mixer != null else -1.0,
		"replay": _is_replay(), "result": _run.result_info,
		"view": "2d" if bool(_host.get("_2d")) else "3d",
		"timeline_end": MarathonPlan.timeline_end(segs),
		"click_ms": MarathonMixer.CLICK_MS,
		"err_signed": _signed_stats(),
	}
	var name := "report_replay.json" if _is_replay() else "report.json"
	var f := FileAccess.open("%s/%s" % [_dir, name], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_report, "  ", false, true))
		f.close()
	print("MARATHON-HARNESS report: score %d, combo %d, misses %d" % [int(s.get("score", 0)),
		int(s.get("max_combo", 0)), int(s.get("n_miss", 0))])
	var tag := "2d" if bool(_host.get("_2d")) else "3d"
	await get_tree().create_timer(2.8, true).timeout
	await _shot("%s_results.png" % tag, -1.0)
	var rs = _host.get("_results_screen")
	if rs != null and rs.has_method("show_page"):
		# Reiter: Uebersicht, Details, Maps.
		rs.show_page(2)
		await get_tree().create_timer(0.8, true).timeout
		await _shot("%s_results_maps.png" % tag, -1.0)
	_remove_rec()
	print("MARATHON-HARNESS DONE")
	get_tree().quit(0)


## Verteilung der vorzeichenbehafteten Deck-Abweichung (alle Messungen).
func _signed_stats() -> Dictionary:
	if _run.mixer == null or _run.mixer.err_all.is_empty():
		return {}
	var a: Array = Array(_run.mixer.err_all)
	a.sort()
	var hist := {}
	for v in a:
		var b := str(int(round(float(v))))
		hist[b] = int(hist.get(b, 0)) + 1
	return {"n": a.size(), "p05": _pct(a, 0.05), "p50": _pct(a, 0.5), "p95": _pct(a, 0.95),
		"mean": _mean(a), "hist_ms": hist}


func _is_replay() -> bool:
	var gs := MarathonRun.autoload("GameSession")
	return gs != null and bool(gs.is_replay)


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	return float(a[clampi(int(floor(q * float(a.size() - 1))), 0, a.size() - 1)])


## Eingaben, die der Autoplay (mania_3d._run_autoplay) erzeugt, als Replay-
## Ereignisse: Taste zur Notenzeit, Holds bis zum Ende, sonst 40 ms.
static func autoplay_events(bm: Beatmap, columns: int = 4) -> Array:
	var ev: Array = []
	var rel: Array[float] = []
	rel.resize(columns)
	rel.fill(-1.0)
	for o in bm.hit_objects:
		var n := o as ManiaNote
		if n == null or n.column < 0 or n.column >= columns:
			continue
		var c := n.column
		if rel[c] >= 0.0:
			ev.append({"t": minf(rel[c], n.time), "lane": c, "down": false})
			rel[c] = -1.0
		ev.append({"t": n.time, "lane": c, "down": true})
		rel[c] = n.end_time() if n.is_hold else n.time + 40.0
	for c in columns:
		if rel[c] >= 0.0:
			ev.append({"t": rel[c], "lane": c, "down": false})
	# Stabil nach Zeit (je Spur bleibt die Reihenfolge erhalten).
	var idx: Array = range(ev.size())
	idx.sort_custom(func(a, b):
		if float(ev[a].t) != float(ev[b].t):
			return float(ev[a].t) < float(ev[b].t)
		return a < b)
	var out: Array = []
	for k in idx:
		out.append(ev[k])
	return out
