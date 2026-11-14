extends "res://tests/live_qa.gd"

## Echter Spiel-Lauf fuer mv-tempo (Uebungsmodus + Turbo) in der Mania-Szene, mit
## Screenshots. Nutzt Fixture/Eingabe-Hilfen aus tests/live_qa.gd. Kein Teil von
## "warmd check" (braucht ein Fenster); Aufruf ueber tests/mv_tempo_play.sh:
##   --tempo-cases=practice3d,practice2d,turbo3d   (mit --autoplay: Bot trifft alles)
##   --tempo-cases=turbo2d                          (echte Tasten, Misses, Replay-Vergleich)
## Keine Klassen mit Autoload-Bezug (PracticeController, TurboController) hier
## nennen: der Runner kompiliert sie sonst vor den Autoloads und sie bleiben kaputt.
## Ausgabe je Pruefung: "QA tempo <fall> <pruefung> OK|BUG <detail>".

## Fixture: 160 BPM (Takt 1,5 s), Noten 3..45 s alle 250 ms, Kiai 12..18 s.
## Turbo-Abschnitte: [3, 12) [12, 18) [18, 30) [30, 45].
const T_FIRST := 3000.0
const T_LAST := 45000.0
const KIAI_A := 12000.0
const KIAI_B := 18000.0

var _tcases: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_args():
		if a.begins_with("--tempo-cases="):
			_tcases = a.trim_prefix("--tempo-cases=").split(",")
		elif a.begins_with("--qa-src="):
			_src = a.trim_prefix("--qa-src=")
		elif a.begins_with("--qa-out="):
			_out = a.trim_prefix("--qa-out=")
	_autoplay = OS.get_cmdline_args().has("--autoplay")
	_mode = "tempo"
	_main.call_deferred()


func _main() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameSession")
	_settings = root.get_node_or_null("Settings")
	_clock = root.get_node_or_null("SyncClock")
	_cfg = MODES["mania3d"]
	if _gs == null or _settings == null or _clock == null or not _make_tempo_fixture():
		print("QA tempo setup init BUG autoloads/fixture %s" % _src)
		quit(2)
		return
	for c in _tcases:
		_case = c
		_settings.set("playfield_2d", c.ends_with("2d"))
		if c.begins_with("practice"):
			await _case_practice(c == "practice3d")
		elif c.begins_with("turbo"):
			await _case_turbo()
		elif c == "browser":
			await _case_browser()
		_reset_session()
		PracticeSession.clear()
	paused = false
	_clock.stop()
	# Laufende Effekt-Sounds (Ergebnis-Jingle) ausklingen lassen: sonst meldet
	# Godot beim Beenden eine noch spielende WAV als Leck.
	await create_timer(2.0).timeout
	print("QA DONE tempo ok=%d bug=%d" % [_ok, _bug])
	quit(1 if _bug > 0 else 0)


func _make_tempo_fixture() -> bool:
	if not _make_fixture():  # live_qa: Audiospur der echten Map nach _osz
		return false
	var zr := ZIPReader.new()
	if zr.open(_osz) != OK:
		return false
	var audio := ""
	var bytes := PackedByteArray()
	for f in zr.get_files():
		if not f.to_lower().ends_with(".osu"):
			audio = f
			bytes = zr.read_file(f)
	zr.close()
	_osz = _out.path_join("tempo.osz")
	var zp := ZIPPacker.new()
	if zp.open(_osz) != OK:
		return false
	zp.start_file(audio)
	zp.write_file(bytes)
	zp.close_file()
	var notes := ""
	var i := 0
	var t := T_FIRST
	while t <= T_LAST:
		var x := 64 + 128 * ((i * 3) % 4)
		if i == 20:
			notes += "%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, int(t), int(t) + 500]
		elif i == 21 or i == 22:
			pass  # Hold-Ende frei halten
		else:
			notes += "%d,192,%d,1,0,0:0:0:0:\n" % [x, int(t)]
		i += 1
		t += 250.0
	var timing := "0,375,4,2,0,60,1,0\n%d,-100,4,2,0,60,0,1\n%d,-100,4,2,0,60,0,0\n" % [int(KIAI_A), int(KIAI_B)]
	var osu := "osu file format v14\n\n[General]\nAudioFilename: %s\nAudioLeadIn: 0\nMode: 3\n\n" % audio \
		+ "[Metadata]\nTitle:TempoQA\nArtist:QA\nCreator:qa\nVersion:TEMPO\nBeatmapID:0\nBeatmapSetID:-1\n\n" \
		+ "[Difficulty]\nHPDrainRate:5\nCircleSize:4\nOverallDifficulty:7\nApproachRate:5\nSliderMultiplier:1.4\nSliderTickRate:1\n\n" \
		+ "[Events]\n\n[TimingPoints]\n%s\n[HitObjects]\n%s" % [timing, notes]
	zp.start_file("tempo.osu")
	zp.write_file(osu.to_utf8_buffer())
	zp.close_file()
	zp.close()
	return true


func _start_scene(mods: Dictionary) -> Node:
	var old := current_scene
	var old_id := old.get_instance_id() if old != null else 0
	paused = false
	_clock.stop()
	_gs.set_selection(_osz, 0, "TEMPO")
	_gs.mods = mods.duplicate()
	change_scene_to_file(_cfg.scene)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		var sc := current_scene
		if sc != null and sc.get_instance_id() != old_id and sc.is_node_ready() and sc.get("core") != null:
			return sc
	_check(false, "scene", "Szene startet nicht")
	return null


# --- Uebungsmodus -----------------------------------------------------------

func _case_practice(long_run: bool) -> void:
	# Fehlerstellen aus "frueheren Laeufen" (eigener APPDATA, nie Nutzerdaten).
	if PracticeStore.load_data(_osz, "TEMPO").runs.is_empty():
		PracticeStore.record_run(_osz, "TEMPO", [7250.0, 7500.0, 8000.0, 26000.0])
		PracticeStore.record_run(_osz, "TEMPO", [7500.0, 26250.0, 26500.0, 40000.0])
	var ses := PracticeSession.begin()
	ses.set_range(6000.0, 11000.0)
	ses.set_rates(0.8, 1.0, 0.10 if long_run else 0.05)
	var sc := await _start_scene({})
	if sc == null:
		return
	var tm = sc.get("_tempo_mode")
	if not _check(tm != null and tm.has_method("start_loop"), "uebung-haken", str(tm)):
		return
	await _frames(20)
	var panel = tm.panel
	_check(paused and panel.visible, "einstellbild", "paused=%s panel=%s" % [paused, panel.visible])
	var marks: Array = PracticeStore.error_marks(PracticeStore.load_data(_osz, "TEMPO").runs)
	_check(marks.size() >= 2, "fehlerstellen", "%d Marken: %s" % [marks.size(), str(marks)])
	await _shot(_case + "_panel")
	# Sprungmarke: Klick-Ersatz ueber den Knopf der ersten Fehlerstelle.
	var mk_btn: Button = null
	for ch in panel._marks_row.get_children():
		if ch is Button:
			mk_btn = ch
			break
	if mk_btn != null:
		mk_btn.pressed.emit()
		await _frames(2)
		_check(ses.a_ms <= 7250.0 and ses.b_ms >= 8000.0, "sprungmarke", "A..B %d..%d" % [int(ses.a_ms), int(ses.b_ms)])
	ses.set_range(6000.0, 11000.0)
	panel.timeline.set_range(ses.a_ms, ses.b_ms)
	panel._refresh()
	await _tap(KEY_ENTER)
	var w := Time.get_ticks_msec()
	while paused and Time.get_ticks_msec() - w < 6000:
		await process_frame
	_check(not paused and bool(tm.looping), "schleife-start", "paused=%s looping=%s" % [paused, tm.looping])
	var loops_goal := 3 if long_run else 1
	var shot_done := false
	var max_t_ms := 0.0
	var outside := 0
	w = Time.get_ticks_msec()
	while ses.loops < loops_goal and Time.get_ticks_msec() - w < 40000:
		await process_frame
		var t: float = sc._time_ms()
		max_t_ms = maxf(max_t_ms, t)
		var core = sc.get("core")
		for idx in sc.get("_notes"):
			var tt: float = sc._beatmap.hit_objects[idx].time
			if tt < ses.a_ms or tt >= ses.b_ms:
				outside += 1
		if not shot_done and ses.loops == loops_goal - 1 and t > 8500.0:
			shot_done = true
			_info("schleife", "t=%d rate=%.2f uhr=%.2f n300+=%d" % [int(t), ses.rate, _clock.get_rate(), int(core.n_max + core.n300)])
			await _shot(_case + "_loop")
	_check(ses.loops >= loops_goal, "schleifen", "%d Schleifen, sauber %d, Tempo jetzt %s" % [ses.loops, ses.clean_loops, RateTrack.pct_text(ses.rate)])
	_check(outside == 0, "nur-abschnitt", "%d Noten ausserhalb A..B sichtbar" % outside)
	_check(max_t_ms < 11000.0 + 1200.0, "schleife-endet", "hoechste Songzeit %d" % int(max_t_ms))
	if long_run:
		_check(is_equal_approx(ses.rate, 1.0) and ses.clean_loops >= 2, "tempo-stufen",
			"80 %% -> %s nach %d sauberen Schleifen" % [RateTrack.pct_text(ses.rate), ses.clean_loops])
		var st := PracticeStore.section_stats(_osz, "TEMPO", ses.a_ms, ses.b_ms)
		_check(int(st.get("plays", 0)) >= 3 and float(st.get("best_rate", 0.0)) >= 0.9, "abschnitt-statistik", str(st))
	# Esc -> Einstellbild mit Statistik.
	await _tap(KEY_ESCAPE)
	await _frames(6)
	_check(paused and tm.panel.visible and not tm.looping, "esc-einstellbild", "")
	await _shot(_case + "_panel_after")
	await _tap(KEY_ESCAPE)
	await _frames(10)


# --- Turbo ------------------------------------------------------------------

func _case_turbo() -> void:
	# Bot-Lauf mit Time-Stretch (Tonhoehe halten), Tasten-Lauf mit Nightcore-Klang.
	TempoPrefs.set_keep_pitch(_autoplay)
	var sc := await _start_scene({"TB": true})
	if sc == null:
		return
	var tm = sc.get("_tempo_mode")
	if not _check(tm != null and tm.get("rule") != null, "turbo-haken", str(tm)):
		return
	var w := Time.get_ticks_msec()
	while (paused or bool(sc.get("_countdown_running"))) and Time.get_ticks_msec() - w < 8000:
		await process_frame
	# Echte Tasten: jede 70. Note fehlt -> Rueckfall (Bot: keine Misses).
	var plan := [] if _autoplay else _plan_turbo(sc)
	var pi := 0
	var shot_done := false
	var seen_rates := {}
	var max_step := 0.0
	var prev := -INF
	var prev_us := 0
	var max_at := 0.0
	var max_change := 0.0
	while is_instance_valid(sc) and not bool(sc.get("_ended")) and Time.get_ticks_msec() - w < 70000:
		await process_frame
		if paused:
			continue
		var t: float = sc._time_ms()
		if bool(sc.get("_ended")):
			break
		# Sprung = Songzeit-Schritt minus Rate x Wanduhr-Schritt (Bild-Haenger
		# durch Screenshots zaehlen so nicht als Sprung).
		var us := Time.get_ticks_usec()
		if prev > -INF:
			var dev := absf((t - prev) - _clock.get_rate() * float(us - prev_us) / 1000.0)
			if dev > max_step:
				max_step = dev
				max_at = t
			# Bilder rund um einen Rate-Wechsel (+-500 ms Songzeit) getrennt werten.
			for e in tm.rule.track.to_array():
				if absf(t - float(e[0])) < 500.0:
					max_change = maxf(max_change, dev)
					break
		prev = t
		prev_us = us
		seen_rates[snappedf(_clock.get_rate(), 0.05)] = true
		while pi < plan.size() and float(plan[pi].t) <= t:
			_key(_keycode(int(plan[pi].lane)), bool(plan[pi].down))
			pi += 1
		if not shot_done and t > 33000.0:
			shot_done = true
			_info("tempo", "t=%d rate=%.2f anzeige=%s" % [int(t), _clock.get_rate(), tm._value.text])
			_check(bool(_clock.keeps_pitch()) == _autoplay, "tonhoehe", "keep_pitch=%s Effekt-Latenz %.1f ms" % [
				_clock.keeps_pitch(), _clock.tempo_fx_latency_ms()])
			await _shot(_case + "_turbo_live")
	for lane in 4:
		_key(_keycode(lane), false)
	if not _check(is_instance_valid(sc) and bool(sc.get("_ended")), "songende", ""):
		return
	var s1: Dictionary = sc.core.stats()
	var rates := seen_rates.keys()
	rates.sort()
	_info("verlauf", "Raten %s, Abschnitte %d sauber %d Rueckfall %d, Verlauf %s" % [
		str(rates), tm.rule.secs.size(), tm.rule.clean, tm.rule.fallbacks, str(tm.rule.track.to_array())])
	_check(rates.size() >= 2 and float(rates.back()) > 1.0, "tempo-steigt", str(rates))
	# Kriterium: kein Sprung AM Wechsel. Der Rest misst den (bei Last stockenden)
	# Dummy-Mixer und steht nur als Info im Log.
	_check(max_change < 25.0, "kein-sprung", "am Rate-Wechsel hoechstens %.1f ms Abweichung je Bild (sonst max %.1f ms bei %d ms)" % [
		max_change, max_step, int(max_at)])
	if not _autoplay:
		_check(tm.rule.fallbacks >= 1, "rueckfall-bei-miss", "Misses %d" % int(s1.n_miss))
	await create_timer(2.5).timeout
	var rs := _results_node(sc)
	_check(rs != null and rs.visible, "ergebnisbild", "")
	_check(tm._info != null and tm._info.text.contains("%"), "ergebnis-tempo", tm._info.text if tm._info != null else "")
	await _shot(_case + "_turbo_results")
	if _autoplay:
		return
	var lst := TurboStore.list_for(_osz, "TEMPO")
	_check(lst.size() == 1 and float(lst[0].peak) > 1.0, "turbo-rangliste", str(lst))
	# Replay = gleiche Wertung (Rate-Verlauf aus den Mods).
	var old_id := sc.get_instance_id()
	sc.call("_on_results_replay")
	var sc2 := await _wait_scene(old_id)
	if sc2 == null:
		return
	var w2 := Time.get_ticks_msec()
	while is_instance_valid(sc2) and not bool(sc2.get("_ended")) and Time.get_ticks_msec() - w2 < 60000:
		await process_frame
	if _check(is_instance_valid(sc2) and bool(sc2.get("_ended")), "replay-ende", ""):
		var d := _same_stats(s1, sc2.core.stats())
		_check(d == "", "replay-wertung", d if d != "" else _brief(sc2.core.stats()))
	await create_timer(1.0).timeout


func _plan_turbo(sc: Node) -> Array:
	var p: Array = ReboundReplay.bot_plan(sc.get("_beatmap"), 3, 12.0, 70)
	p.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return p


# --- Song-Browser -------------------------------------------------------------

## Turbo, Tonhoehe und Ueben in der Mods-Zeile (nur Mania). Bibliothek = --maps-dir
## (nur die Fixture-Maps), nie die echte.
func _case_browser() -> void:
	paused = false
	change_scene_to_file("res://scenes/song_select.tscn")
	var w := Time.get_ticks_msec()
	var btns: Array = []
	while Time.get_ticks_msec() - w < 20000:
		await process_frame
		var sc := current_scene
		if sc == null or not sc.scene_file_path.ends_with("song_select.tscn"):
			continue
		# Knoepfe ueber ihre Texte suchen (TempoBrowserRow nennt GameSession: hier
		# nicht direkt referenzieren, siehe Kopf).
		btns = []
		for t in ["Turbo", tr("Keep pitch"), tr("Practice")]:
			var n := _find_button(sc, t)
			if n != null:
				btns.append(n)
		if btns.size() == 3 and sc.get("_selected_set") != null:
			break
	await create_timer(1.5).timeout
	var vis := 0
	for b in btns:
		if is_instance_valid(b) and (b as Control).is_visible_in_tree():
			vis += 1
	_check(vis == 3, "browser-knoepfe", "%d von %d sichtbar" % [vis, btns.size()])
	await _shot("browser")


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for ch in n.get_children():
		var r := _find_button(ch, text)
		if r != null:
			return r
	return null
