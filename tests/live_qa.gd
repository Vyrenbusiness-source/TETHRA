extends SceneTree

## Live-QA-Treiber: startet die echten Spielszenen und spielt sie mit echten
## Eingaben (Input.parse_input_event) bzw. dem eingebauten Bot (--autoplay bei
## Orbit/Rally/Dirigent). Prueft Pause/Resume, Break, Intro-Skip, Retry, Fail,
## Songende -> Ergebnis, Replay = gleiche Wertung, Mods (Score-Faktor).
## Kein Teil von "warmd check" (braucht ein Fenster); Aufruf ueber tests/live_qa.sh:
##   Godot --path . --audio-driver Dummy --script res://tests/live_qa.gd --live-qa
##     --qa-mode=<mania2d|mania3d|orbit|rally|dirigent|trace|rebound>
##     --qa-cases=flow,retry,fail,nfidle,mod:,mod:NF  --qa-src=<quelle.osz> --qa-out=<ordner>
## Ausgabe je Pruefung: "QA <modus> <fall> <pruefung> OK|BUG <detail>".

## Zeiten der Fixture-Map (ms); --qa-shift=<ms> schiebt alles nach hinten (Dirigent
## zaehlt vor der ersten Note Schlaege vor: Intro-Skip erst ab ~10 s Vorlauf).
var FIRST := 6000.0
var PAUSE_AT := 8600.0
var BREAK_A := 11000.0
var BREAK_MID := 14500.0
var BREAK_B := 18000.0
var LAST := 22000.0

const MODES := {
	"mania2d": {"scene": "res://scenes/mania_3d.tscn", "inject": "lanes"},
	"mania3d": {"scene": "res://scenes/mania_3d.tscn", "inject": "lanes"},
	"orbit": {"scene": "res://scenes/orbit.tscn", "inject": ""},
	"rally": {"scene": "res://scenes/rally.tscn", "inject": ""},
	"dirigent": {"scene": "res://scenes/dirigent.tscn", "inject": ""},
	"trace": {"scene": "res://scenes/trace.tscn", "inject": "trace"},
	"rebound": {"scene": "res://scenes/rebound.tscn", "inject": "lanes"},
}
## Erwarteter Score-Faktor je Mod und Modus.
const MULT := {
	"mania2d": {"NF": 0.5, "SV": 1.1, "HD": 1.0, "FI": 1.0, "CS": 1.0},
	"mania3d": {"NF": 0.5, "SV": 1.1, "CS": 1.0},
	"orbit": {"NF": 0.5, "HD": 1.06, "FI": 1.06, "PR": 1.12},
	"rally": {"NF": 0.5},
	"dirigent": {"NF": 1.0},
	"trace": {"NF": 0.5, "MR": 1.0, "HD": 1.06, "SS": 1.08},
	"rebound": {"NF": 0.5, "SV": 1.0},
}

var _mode := ""
var _cfg: Dictionary = {}
var _cases: PackedStringArray = []
var _src := ""
var _out := ""
var _osz := ""
var _ok := 0
var _bug := 0
var _case := ""
var _gs: Node
var _settings: Node
var _clock: Node
var _base_score := -1
var _autoplay := false


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--qa-mode="):
			_mode = a.trim_prefix("--qa-mode=")
		elif a.begins_with("--qa-cases="):
			_cases = a.trim_prefix("--qa-cases=").split(",")
		elif a.begins_with("--qa-src="):
			_src = a.trim_prefix("--qa-src=")
		elif a.begins_with("--qa-out="):
			_out = a.trim_prefix("--qa-out=")
		elif a.begins_with("--qa-shift="):
			var sh := a.trim_prefix("--qa-shift=").to_float()
			FIRST += sh
			PAUSE_AT += sh
			BREAK_A += sh
			BREAK_MID += sh
			BREAK_B += sh
			LAST += sh
	_autoplay = OS.get_cmdline_args().has("--autoplay")
	_main.call_deferred()


func _main() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameSession")
	_settings = root.get_node_or_null("Settings")
	_clock = root.get_node_or_null("SyncClock")
	if not MODES.has(_mode) or _gs == null or _settings == null or _clock == null:
		print("QA %s setup init BUG mode/autoloads fehlen" % _mode)
		quit(2)
		return
	_cfg = MODES[_mode]
	if not _make_fixture():
		print("QA %s setup fixture BUG %s" % [_mode, _src])
		quit(2)
		return
	for c in _cases:
		_case = c
		if c == "flow":
			await _case_flow()
		elif c == "retry":
			await _case_retry()
		elif c == "fail":
			await _case_fail(false)
		elif c == "nfidle":
			await _case_fail(true)
		elif c.begins_with("mod:"):
			await _case_mod(c.trim_prefix("mod:"))
		_reset_session()
	paused = false
	_clock.stop()
	print("QA DONE %s ok=%d bug=%d" % [_mode, _ok, _bug])
	quit(1 if _bug > 0 else 0)


# --- Hilfen ---------------------------------------------------------------

func _check(cond: bool, what: String, detail: String = "") -> bool:
	if cond:
		_ok += 1
	else:
		_bug += 1
	print("QA %s %s %s %s %s" % [_mode, _case, what, "OK" if cond else "BUG", detail])
	return cond


func _info(what: String, detail: String) -> void:
	print("QA %s %s %s INFO %s" % [_mode, _case, what, detail])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _tap(code: int) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return
	img.resize(640, int(640.0 * img.get_height() / maxf(img.get_width(), 1.0)), Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join("%s_%s.png" % [_mode, name]))


func _reset_session() -> void:
	paused = false
	_clock.stop()
	_gs.is_replay = false
	_gs.replay_events = []
	_gs.replay_mode = "mania"
	_gs.replay_end_ms = -1.0
	_gs.mods = {}
	_settings.set("mod_vis_2d", 0)
	_settings.set("mod_constant", false)


## Kurze 4K-Map (38 Noten, Hold, Break 11-18 s) + "QAFAIL" (129 Noten, HP 10) mit
## der Audiospur einer echten Map.
func _make_fixture() -> bool:
	var zr := ZIPReader.new()
	if zr.open(_src) != OK:
		return false
	var audio := ""
	for f in zr.get_files():
		if f.to_lower().ends_with(".osu"):
			for line in zr.read_file(f).get_string_from_utf8().split("\n"):
				if line.begins_with("AudioFilename:"):
					audio = line.trim_prefix("AudioFilename:").strip_edges()
					break
			if audio != "":
				break
	if audio == "":
		return false
	var bytes := zr.read_file(audio)
	zr.close()
	if bytes.is_empty():
		return false
	_osz = _out.path_join("liveqa.osz")
	var zp := ZIPPacker.new()
	if zp.open(_osz) != OK:
		return false
	zp.start_file(audio)
	zp.write_file(bytes)
	zp.close_file()
	var notes := ""
	var i := 0
	var t := FIRST
	while t <= BREAK_A:
		var x := 64 + 128 * ((i * 3) % 4)
		if i == 12:
			notes += "%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, int(t), int(t) + 400]
		else:
			notes += "%d,192,%d,1,0,0:0:0:0:\n" % [x, int(t)]
		i += 1
		t += 250.0
	t = BREAK_B
	while t <= LAST:
		notes += "%d,192,%d,1,0,0:0:0:0:\n" % [64 + 128 * ((i * 3) % 4), int(t)]
		i += 1
		t += 250.0
	var dense := ""
	i = 0
	t = FIRST
	while t <= LAST:
		dense += "%d,192,%d,1,0,0:0:0:0:\n" % [64 + 128 * ((i * 3) % 4), int(t)]
		i += 1
		t += 125.0
	zp.start_file("qa.osu")
	zp.write_file(_osu(audio, "QA4K", 7, "2,%d,%d\n" % [int(BREAK_A) + 500, int(BREAK_B) - 500], notes).to_utf8_buffer())
	zp.close_file()
	zp.start_file("qafail.osu")
	zp.write_file(_osu(audio, "QAFAIL", 10, "", dense).to_utf8_buffer())
	zp.close_file()
	zp.close()
	return true


func _osu(audio: String, version: String, hp: int, events: String, notes: String) -> String:
	return "osu file format v14\n\n[General]\nAudioFilename: %s\nAudioLeadIn: 0\nMode: 3\n\n" % audio \
		+ "[Metadata]\nTitle:LiveQA\nArtist:QA\nCreator:qa\nVersion:%s\nBeatmapID:0\nBeatmapSetID:-1\n\n" % version \
		+ "[Difficulty]\nHPDrainRate:%d\nCircleSize:4\nOverallDifficulty:7\nApproachRate:5\nSliderMultiplier:1.4\nSliderTickRate:1\n\n" % hp \
		+ "[Events]\n%s\n[TimingPoints]\n0,500,4,2,0,60,1,0\n\n[HitObjects]\n%s" % [events, notes]


func _start(version: String, mods: Dictionary) -> Node:
	var old := current_scene
	var old_id := old.get_instance_id() if old != null else 0
	paused = false
	_clock.stop()
	_gs.set_selection(_osz, 0, version)
	_gs.mods = mods.duplicate()
	change_scene_to_file(_cfg.scene)
	return await _wait_scene(old_id)


func _wait_scene(old_id: int) -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		var sc := current_scene
		if sc != null and sc.get_instance_id() != old_id and sc.is_node_ready():
			if sc.scene_file_path != _cfg.scene:
				_check(false, "scene", "falsche Szene %s" % sc.scene_file_path)
				return null
			if sc.get("core") == null:
				continue
			# Start-Countdown abwarten.
			while Time.get_ticks_msec() - t0 < 20000 and is_instance_valid(sc) \
					and (paused or bool(sc.get("_countdown_running"))) and not bool(sc.get("_ended")):
				await process_frame
			return sc if is_instance_valid(sc) else null
	_check(false, "scene", "Szene startet nicht")
	return null


func _chat_open() -> bool:
	var chat = _gs.get("chat")
	return chat != null and chat.has_method("is_open") and bool(chat.is_open())


func _stats(sc: Node) -> Dictionary:
	return sc.core.stats()


func _miss(sc: Node) -> int:
	var s := _stats(sc)
	return int(s.get("n_miss", s.get("miss", 0)))


func _plan(sc: Node, skip_every: int) -> Array:
	if str(_cfg.inject) == "":
		return []
	var p: Array = ReboundReplay.bot_plan(sc.get("_beatmap"), 3, 14.0, skip_every)
	p.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return p


func _keycode(lane: int) -> int:
	if str(_cfg.inject) == "trace":
		return int(_settings.trace_keys[lane])
	return int(_settings.key_lanes[lane])


func _settings_sig() -> String:
	var out := PackedStringArray()
	for p in _settings.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append("%s=%s" % [p.name, str(_settings.get(p.name))])
	return "\n".join(out).md5_text()


## Eine Runde fahren. o: plan, skip, pause, brk, stop_at, max_s, shots.
func _drive(sc: Node, o: Dictionary) -> Dictionary:
	var info := {"lost": false, "timeout": false}
	var plan: Array = o.get("plan", [])
	var pi := 0
	var need_skip := bool(o.get("skip", false))
	var need_pause := bool(o.get("pause", false))
	var brk := bool(o.get("brk", false))
	var stop_at := float(o.get("stop_at", -1.0))
	var wall := Time.get_ticks_msec()
	var max_ms := int(o.get("max_s", 45)) * 1000
	var watch_n := 0
	var watch_prev := 0.0
	var watch_max := 0.0
	var miss_resume := -1
	var t_resume := 0.0
	var b_state := 0
	var miss_brk := 0
	while is_instance_valid(sc) and not bool(sc.get("_ended")):
		if Time.get_ticks_msec() - wall > max_ms:
			info.timeout = true
			break
		await process_frame
		if not is_instance_valid(sc) or sc != current_scene:
			info.lost = true
			break
		if paused or bool(sc.get("_ended")):
			continue
		var t: float = sc._time_ms()
		if need_skip:
			need_skip = false
			if _check(bool(sc._can_skip_intro()), "skip-moeglich", "t=%d" % int(t)):
				await _tap(KEY_SPACE)
				await _frames(3)
				var t1: float = sc._time_ms()
				_check(t1 - t > 500.0 and FIRST - t1 >= 1000.0 and not paused, "skip",
					"t %d -> %d, erste Note %d (Vorlauf %d ms)" % [int(t), int(t1), int(FIRST), int(FIRST - t1)])
			continue
		if need_pause and t >= PAUSE_AT:
			need_pause = false
			miss_resume = _miss(sc)
			await _tap(KEY_ESCAPE)
			var tp: float = sc._time_ms()
			var vp: float = _clock.visual_time_ms()
			var pm = sc.get("_pause_menu")
			var menu: bool = pm != null and pm.visible
			await create_timer(1.2).timeout
			var tp2: float = sc._time_ms()
			_check(paused and menu and absf(tp2 - tp) < 1.0, "pause",
				"paused=%s menu=%s t=%d nach 1,2 s %d" % [paused, menu, int(tp), int(tp2)])
			if bool(o.get("shots", false)):
				await _shot("pause")
			await _tap(KEY_ESCAPE)
			var w := Time.get_ticks_msec()
			while paused and Time.get_ticks_msec() - w < 6000:
				await process_frame
			var tr: float = sc._time_ms()
			var vr: float = _clock.visual_time_ms()
			_check(not paused and absf(tr - tp) < 60.0 and absf(vr - vp) < 60.0, "resume-uhr",
				"t %d -> %d, sichtbar %d -> %d, Countdown %d ms" % [int(tp), int(tr), int(vp), int(vr), Time.get_ticks_msec() - w])
			watch_n = 40
			watch_prev = tr
			t_resume = tr
			continue
		if watch_n > 0:
			watch_max = maxf(watch_max, absf(t - watch_prev))
			if t < watch_prev - 0.5:
				watch_max = 9999.0
			watch_prev = t
			watch_n -= 1
			if watch_n == 0:
				_check(watch_max < 100.0, "resume-sprung", "groesster Schritt in 40 Bildern %.1f ms" % watch_max)
		if miss_resume >= 0 and t >= t_resume + 700.0:
			_check(_miss(sc) == miss_resume, "resume-noten", "Misses %d -> %d in 700 ms nach Resume" % [miss_resume, _miss(sc)])
			miss_resume = -1
		if brk:
			var ov = sc.get("_break_ov")
			if b_state == 0 and t >= BREAK_MID:
				b_state = 1
				_info("break-mitte", "overlay=%s aktiv=%s" % [ov != null, ov != null and ov.is_active()])
			elif b_state == 1 and t >= BREAK_B - 300.0:
				b_state = 2
				miss_brk = _miss(sc)
				var a := -1.0
				if ov != null and ov.get("_root") != null:
					a = float(ov._root.modulate.a) if ov._root.visible and ov.visible else 0.0
				_info("break-ende", "300 ms vor der Note: overlay aktiv=%s alpha=%.2f" % [ov != null and ov.is_active(), a])
				if bool(o.get("shots", false)):
					await _shot("break")
			elif b_state == 2 and t >= BREAK_B + 450.0:
				b_state = 3
				_check(_miss(sc) == miss_brk, "break-erste-note", "Misses %d -> %d" % [miss_brk, _miss(sc)])
		while pi < plan.size() and float(plan[pi].t) <= t:
			_key(_keycode(int(plan[pi].lane)), bool(plan[pi].down))
			pi += 1
		if stop_at >= 0.0 and t >= stop_at:
			break
	if is_instance_valid(sc) and sc == current_scene:
		info["stats"] = _stats(sc)
		info["ended"] = bool(sc.get("_ended"))
	else:
		info.lost = true
	# Tasten loslassen, die der Plan noch haelt.
	for lane in 4:
		if str(_cfg.inject) != "":
			_key(_keycode(lane), false)
	return info


func _results_node(sc: Node) -> Node:
	for k in ["_results", "_results_screen"]:
		var n = sc.get(k)
		if n != null and n is Node:
			return n
	return _find_results(sc)


func _find_results(n: Node) -> Node:
	var scr = n.get_script()
	if scr != null and str(scr.resource_path).ends_with("results_screen.gd"):
		return n
	for ch in n.get_children():
		var r := _find_results(ch)
		if r != null:
			return r
	return null


func _same_stats(a: Dictionary, b: Dictionary) -> String:
	var diff := PackedStringArray()
	for k in a:
		var key := str(k)
		if not (key in ["score", "accuracy", "max_combo", "grade", "failed"] or key.begins_with("n")):
			continue
		var va = a[k]
		var vb = b.get(k)
		var same := false
		if va is float or vb is float:
			same = vb != null and absf(float(va) - float(vb)) < 0.000001
		else:
			same = str(va) == str(vb)
		if not same:
			diff.append("%s %s/%s" % [key, str(va), str(vb)])
	return ", ".join(diff)


func _brief(s: Dictionary) -> String:
	return "score=%s acc=%.4f combo=%s grade=%s miss=%s failed=%s mult=%s mods=%s" % [
		str(s.get("score")), float(s.get("accuracy", 0.0)), str(s.get("max_combo")), str(s.get("grade")),
		str(s.get("n_miss", s.get("miss"))), str(s.get("failed")), str(s.get("mod_mult")), str(s.get("mods"))]


# --- Faelle -----------------------------------------------------------------

## Skip, Pause/Resume, Break, Songende -> Ergebnis, Replay = gleiche Wertung.
func _case_flow() -> void:
	var sc := await _start("QA4K", {})
	if sc == null:
		return
	var r := await _drive(sc, {"plan": _plan(sc, 9), "skip": true, "pause": true, "brk": true, "shots": true})
	if not _check(not r.lost and not r.timeout and bool(r.get("ended", false)), "songende", str(r.get("timeout"))):
		return
	var s1: Dictionary = r.stats
	_info("ergebnis", _brief(s1))
	await create_timer(2.5).timeout
	var rs := _results_node(sc)
	_check(rs != null and rs.visible and int(s1.get("score", 0)) > 0 and not bool(s1.get("failed", false)),
		"ergebnisbild", "Knoten=%s" % (rs != null))
	await _shot("results")
	# Replay ansehen.
	var old_id := sc.get_instance_id()
	sc.call("_on_results_replay")
	sc = await _wait_scene(old_id)
	if sc == null:
		return
	if not _check(bool(_gs.is_replay), "replay-start", "is_replay=%s events=%d" % [_gs.is_replay, _gs.replay_events.size()]):
		return
	var r2 := await _drive(sc, {})
	if _check(not r2.lost and not r2.timeout and bool(r2.get("ended", false)), "replay-ende", ""):
		var d := _same_stats(s1, r2.stats)
		_check(d == "", "replay-wertung", d if d != "" else _brief(r2.stats))
	await create_timer(1.0).timeout


## Retry: R mitten im Song, Neustart im Pausenmenue, R im Ergebnis. Mods/Settings bleiben.
func _case_retry() -> void:
	var mods := {"NF": true}
	var sc := await _start("QA4K", mods)
	if sc == null:
		return
	var sig := _settings_sig()
	var hp0 = sc.core.get("hp")
	var r := await _drive(sc, {"plan": _plan(sc, 5), "skip": true, "stop_at": FIRST + 2600.0})
	if r.lost:
		_check(false, "retry-lauf", "Szene weg")
		return
	_info("vor-retry", _brief(r.stats))
	var score_before := int(r.stats.get("score", 0))
	_check(not _chat_open(), "chat-zu", "Chat-Overlay (Taste F) darf im Spiel nicht aufgehen")
	var old_id := sc.get_instance_id()
	await _tap(KEY_R)
	sc = await _wait_scene(old_id)
	if sc == null:
		return
	await _frames(3)
	var s: Dictionary = _stats(sc)
	_check(score_before > 0 and int(s.get("score", -1)) == 0 and str(sc.core.get("hp")) == str(hp0)
			and float(sc._time_ms()) < FIRST - 1000.0 and not bool(_gs.is_replay),
		"retry-taste-r", "score %d -> %s, hp %s -> %s, t=%d" % [score_before, str(s.get("score")), str(hp0), str(sc.core.get("hp")), int(sc._time_ms())])
	_check(str(_gs.mods.get("NF", false)) == "true" and absf(float(s.get("mod_mult", 1.0)) - float(MULT[_mode]["NF"])) < 0.0001,
		"retry-mods", "mods=%s mult=%s" % [str(_gs.mods), str(s.get("mod_mult"))])
	_check(_settings_sig() == sig, "retry-settings", "")
	# Zweiter Durchgang: Pausenmenue -> Neustart.
	r = await _drive(sc, {"plan": _plan(sc, 5), "stop_at": FIRST + 1300.0})
	if r.lost:
		_check(false, "retry-lauf2", "Szene weg")
		return
	score_before = int(r.stats.get("score", 0))
	await _frames(3)
	await _tap(KEY_ESCAPE)
	var pm = sc.get("_pause_menu")
	old_id = sc.get_instance_id()
	if _check(paused and pm != null and pm.visible, "retry-pausenmenue", "paused=%s" % paused):
		pm.restart_pressed.emit()
		sc = await _wait_scene(old_id)
		if sc == null:
			return
		await _frames(3)
		s = _stats(sc)
		_check(score_before > 0 and int(s.get("score", -1)) == 0 and not paused and str(sc.core.get("hp")) == str(hp0)
				and str(_gs.mods.get("NF", false)) == "true" and _settings_sig() == sig,
			"retry-pause-neustart", "score %d -> %s, hp %s, mods=%s" % [score_before, str(s.get("score")), str(sc.core.get("hp")), str(_gs.mods)])
	# Dritter Durchgang: bis zum Ergebnis, dort R.
	r = await _drive(sc, {"plan": _plan(sc, 5), "skip": true})
	if r.lost or not bool(r.get("ended", false)):
		_check(false, "retry-lauf3", "kein Ergebnis")
		return
	await create_timer(1.5).timeout
	old_id = sc.get_instance_id()
	await _tap(KEY_R)
	sc = await _wait_scene(old_id)
	if sc == null:
		return
	await _frames(3)
	s = _stats(sc)
	_check(int(r.stats.get("score", 0)) > 0 and int(s.get("score", -1)) == 0 and not bool(sc.get("_ended"))
			and str(_gs.mods.get("NF", false)) == "true" and not bool(_gs.is_replay),
		"retry-im-ergebnis", "score %s -> %s" % [str(r.stats.get("score")), str(s.get("score"))])


## Ohne Eingaben: Fail-Bild (nf=false) bzw. mit NF bis zum Ende ohne Fail.
func _case_fail(nf: bool) -> void:
	if _autoplay:
		_check(false, "fail", "Fall braucht einen Lauf ohne --autoplay")
		return
	var sc := await _start("QAFAIL", {"NF": true} if nf else {})
	if sc == null:
		return
	var r := await _drive(sc, {"skip": true, "max_s": 40})
	if not _check(not r.lost and not r.timeout and bool(r.get("ended", false)), "ende", "timeout=%s" % str(r.timeout)):
		return
	var s: Dictionary = r.stats
	_info("ergebnis", _brief(s) + " t_ende=%d" % int(sc.get("_last_update_t") if sc.get("_last_update_t") != null else -1))
	await create_timer(3.0).timeout
	var rs := _results_node(sc)
	var failed := bool(s.get("failed", false)) or (sc.core.get("failed") != null and bool(sc.core.get("failed")))
	if nf:
		_check(not failed and rs != null and rs.visible, "nf-kein-fail", "failed=%s" % failed)
		await _shot("nfidle")
	else:
		if _mode == "dirigent":
			_check(not failed and rs != null and rs.visible, "kein-fail-im-modus", "Dirigent kennt kein Fail: Ergebnis mit Note %s" % str(s.get("grade")))
		else:
			_check(failed and rs != null and rs.visible, "fail-bild", "failed=%s Knoten=%s" % [failed, rs != null])
		await _shot("fail")


## Mod im Lauf: Faktor in den Stats, Score = Rohwert x Faktor.
func _case_mod(mod: String) -> void:
	var mods := {}
	if mod != "":
		mods[mod] = true
	if _mode.begins_with("mania"):
		if mod == "HD":
			_settings.set("mod_vis_2d", _settings.VIS_HIDDEN)
		elif mod == "FI":
			_settings.set("mod_vis_2d", _settings.VIS_FADE_IN)
		elif mod == "CS":
			_settings.set("mod_constant", true)
	var sc := await _start("QA4K", mods)
	if sc == null:
		return
	var r := await _drive(sc, {"plan": _plan(sc, 7), "skip": true})
	if not _check(not r.lost and not r.timeout and bool(r.get("ended", false)), "ende", ""):
		return
	var s: Dictionary = r.stats
	_info("ergebnis", _brief(s))
	var score := int(s.get("score", 0))
	if mod == "":
		_base_score = score
		_check(score > 0 and absf(float(s.get("mod_mult", 1.0)) - 1.0) < 0.0001, "ohne-mod", "score=%d" % score)
		return
	var want := float(MULT[_mode].get(mod, 1.0))
	var got := float(s.get("mod_mult", 1.0))
	_check(absf(got - want) < 0.0001, "faktor", "mod_mult=%s erwartet %s" % [str(got), str(want)])
	var active: bool = bool(sc.core.get("mods").get(mod, false)) if sc.core.get("mods") is Dictionary else false
	var listed: bool = mod in (s.get("mods", []) as Array)
	_info("aktiv", "core.mods=%s stats.mods=%s session=%s" % [str(sc.core.get("mods")), str(s.get("mods")), str(_gs.mods)])
	if want != 1.0 or _mode != "dirigent":
		if not (_mode == "rebound" and mod == "SV"):
			_check(active or listed, "aktiv-im-lauf", "")
	var raw = sc.core.get("_score_f")
	if raw != null:
		_check(score == int(round(float(raw) * got)) and score > 0, "score-faktor", "score=%d roh=%.1f x %s" % [score, float(raw), str(got)])
	elif _base_score > 0 and _autoplay and mod != "PR":
		_check(absi(score - int(round(_base_score * want))) <= 2, "score-faktor", "score=%d ohne Mod %d x %s" % [score, _base_score, str(want)])
	else:
		_info("score-faktor", "score=%d ohne Mod %d" % [score, _base_score])
	await create_timer(1.5).timeout
	var rs := _results_node(sc)
	_check(rs != null and rs.visible, "ergebnisbild", "")
