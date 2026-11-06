extends SceneTree

## Headless-Tests fuer die Audio-Uhr (SyncClock.Smoother, Rampe, Projekt-
## Einstellungen) und Event-genaues Judgement in ManiaCore.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_clock_tests.gd

## Erst zur Laufzeit laden: beim Kompilieren des Test-Skripts sind die
## Autoload-Namen (GameSession ...) noch nicht registriert.
var SC: GDScript
var _started := false
## Live-Phase: echte Wiedergabe ueber den Dummy-Treiber (mischt in Echtzeit).
var _live := false
var _clock: Node
var _t0 := 0
var _step := 0
var _last_v := -INF
var _mono := true
var _mark := 0.0
var _gain := 0.0
var _seek_checked := false
var _dev_sum := 0.0
var _dev_n := 0
## Movie-Phase (Film-Zeit statt Wanduhr).
var _f0 := 0
var _movie_ok := true
var _movie_worst := 0.0
var _movie_last := -INF
var _movie_play_dev := 0.0
var _movie_played := false

var _passed := 0
var _failed := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
		return false
	if _live:
		_live_step()
	return false


func _run_all() -> void:
	SC = load("res://scripts/audio/sync_clock.gd")
	print("=== TETHRA Clock-Tests ===")
	_test_ideal()
	_test_jitter()
	_test_drift()
	_test_spike()
	_test_backward_jitter_monotone()
	_test_seek_forward()
	_test_restart_backward()
	_test_hold()
	_test_latency_step()
	_test_resume_behind_monotone()
	_test_mix_stall_monotone()
	_test_settle_forward_smooth()
	_test_movie_fps_parse()
	_test_movie_clock()
	_test_fade_level()
	_test_project_settings()
	_test_live_clock()
	_test_jack_between_frames()
	_test_windows_unchanged()
	_clock = root.get_node_or_null("/root/SyncClock")
	if _clock != null:
		print("- Live: Lead-In -> Audio nahtlos, Pause friert ein, Resume/Stop")
		_clock.play(_silence(4.0), 300.0)
		_t0 = Time.get_ticks_msec()
		_live = true
		return
	_finish()


func _finish() -> void:
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


## Simuliert n Samples im Abstand step_us; truth(t_us) liefert die wahre Zeit,
## noise(i) den Roh-Jitter. Gibt [max_dev, mean_dev, monoton, mean_signed] ab
## settle_us zurueck.
func _run(sm, n: int, step_us: int, truth: Callable, noise: Callable, settle_us: int = 1000000) -> Array:
	var last := -INF
	var mono := true
	var max_dev := 0.0
	var sum_dev := 0.0
	var sum_signed := 0.0
	var cnt := 0
	for i in n:
		var t_us := i * step_us
		var tr: float = truth.call(t_us)
		var out: float = sm.sample(tr + float(noise.call(i)), t_us)
		if out < last:
			mono = false
		last = out
		if t_us >= settle_us:
			var d := out - tr
			max_dev = maxf(max_dev, absf(d))
			sum_dev += absf(d)
			sum_signed += d
			cnt += 1
	return [max_dev, sum_dev / maxf(cnt, 1), mono, sum_signed / maxf(cnt, 1)]


func _lin(t_us: int) -> float:
	return float(t_us) / 1000.0


func _test_ideal() -> void:
	print("- Ideale Audio-Uhr wird exakt durchgereicht")
	var r := _run(SC.Smoother.new(), 600, 16667, _lin, func(_i): return 0.0, 0)
	_ok(r[0] < 0.001, "Abweichung < 0.001 ms (war %.4f)" % r[0])
	_ok(r[2], "monoton")


func _test_jitter() -> void:
	print("- Mix-Jitter +-2 ms (60 Hz und 1 kHz Abfrage)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var noise := func(_i): return rng.randf_range(-2.0, 2.0)
	var r := _run(SC.Smoother.new(), 60 * 20, 16667, _lin, noise)
	_ok(r[2], "monoton (60 Hz)")
	_ok(r[1] < 0.5, "mittlere Abweichung < 0.5 ms (war %.3f, roh ~1.0)" % r[1])
	_ok(absf(r[3]) < 0.2, "kein Versatz (war %.3f)" % r[3])
	_ok(r[0] < 1.5, "max Abweichung < 1.5 ms (war %.3f, roh 2.0)" % r[0])
	rng.seed = 99
	var r2 := _run(SC.Smoother.new(), 1000 * 10, 1000, _lin, noise)
	_ok(r2[2], "monoton (1 kHz, Input-Events)")
	_ok(r2[1] < 0.5, "mittlere Abweichung 1 kHz < 0.5 ms (war %.3f)" % r2[1])


func _test_drift() -> void:
	print("- Drift Soundkarte gegen Wanduhr (+-500 ppm, 30 s)")
	for ppm in [500.0, -500.0]:
		var rate: float = 1.0 + ppm / 1000000.0
		var truth := func(t_us: int) -> float: return float(t_us) / 1000.0 * rate
		var r := _run(SC.Smoother.new(), 60 * 30, 16667, truth, func(_i): return 0.0)
		_ok(r[0] <= 1.0, "%+d ppm: max Abweichung <= 1 ms (war %.3f)" % [int(ppm), r[0]])
		_ok(r[2], "%+d ppm: monoton" % int(ppm))


func _test_spike() -> void:
	print("- Einzelner Mix-Block-Ausreisser (+10.7 ms) wird ignoriert")
	var noise := func(i): return 10.67 if i == 300 or i == 301 else 0.0
	var r := _run(SC.Smoother.new(), 600, 16667, _lin, noise)
	_ok(r[0] < 0.01, "max Abweichung < 0.01 ms (war %.3f)" % r[0])


func _test_backward_jitter_monotone() -> void:
	print("- Rohzeit springt 3 ms zurueck -> Ausgabe nie rueckwaerts")
	var noise := func(i): return -3.0 if i % 7 == 3 else 0.0
	var r := _run(SC.Smoother.new(), 600, 16667, _lin, noise)
	_ok(r[2], "monoton")
	_ok(r[0] <= 1.0, "max Abweichung <= 1 ms (war %.3f)" % r[0])


func _test_seek_forward() -> void:
	print("- Seek +5000 ms: Uhr folgt innerhalb ~60 ms")
	var sm = SC.Smoother.new()
	var t_us := 0
	for i in 60:
		sm.sample(float(t_us) / 1000.0, t_us)
		t_us += 16667
	var dev := INF
	for i in 6:
		var tr := float(t_us) / 1000.0 + 5000.0
		dev = absf(sm.sample(tr, t_us) - tr)
		t_us += 16667
	_ok(dev <= 1.0, "nach 6 Frames auf Zielzeit (Abw. %.3f)" % dev)


func _test_restart_backward() -> void:
	print("- Neustart/Seek rueckwaerts (-20 s) wird nach Bestaetigung uebernommen")
	var sm = SC.Smoother.new()
	var t_us := 0
	for i in 120:
		sm.sample(20000.0 + float(t_us) / 1000.0, t_us)
		t_us += 16667
	var out := 0.0
	var tr := 0.0
	for i in 6:
		tr = float(t_us) / 1000.0 - 2000.0
		out = sm.sample(tr, t_us)
		t_us += 16667
	_ok(absf(out - tr) < 0.01, "Uhr auf neue Zeit gesetzt (Abw. %.3f)" % absf(out - tr))


func _test_hold() -> void:
	print("- Pause: Zeit steht, nach Resume kein Sprung")
	var sm = SC.Smoother.new()
	var t_us := 0
	var v := 0.0
	for i in 60:
		v = sm.sample(float(t_us) / 1000.0, t_us)
		t_us += 16667
	var frozen := v
	var audio_ms := frozen  # Audio steht ebenfalls
	for i in 120:
		v = sm.hold(t_us)
		t_us += 16667
	_ok(absf(v - frozen) < 0.0001, "haelt waehrend Pause")
	var max_jump := 0.0
	var last := v
	for i in 60:
		var out: float = sm.sample(audio_ms, t_us)
		max_jump = maxf(max_jump, out - last)
		last = out
		audio_ms += 16.667
		t_us += 16667
	_ok(max_jump < 17.5, "Resume ohne Sprung (groesster Schritt %.3f ms)" % max_jump)
	_ok(absf(last - audio_ms + 16.667) <= 1.0, "nach Resume wieder an der Audio-Uhr")


func _test_latency_step() -> void:
	print("- Latenzwechsel 5 ms: gemittelte Abweichung schnell wieder <= 1 ms")
	var sm = SC.Smoother.new()
	var t_us := 0
	for i in 60:
		sm.sample(float(t_us) / 1000.0, t_us)
		t_us += 16667
	var dev := INF
	var mono := true
	var last := -INF
	for i in 30:
		var tr := float(t_us) / 1000.0 - 5.0
		var out: float = sm.sample(tr, t_us)
		mono = mono and out >= last
		last = out
		dev = absf(out - tr)
		t_us += 16667
	_ok(dev <= 1.0, "nach 0.5 s Abweichung <= 1 ms (war %.3f)" % dev)
	_ok(mono, "monoton waehrend Nachfuehrung")


## Simuliert: Uhr haelt (Pause), Audio-Rohzeit liegt nach Resume bis zu
## einen Mix-Block (85 ms, Dummy-Treiber) HINTER der gehaltenen Zeit (Godots
## Pause-Blende mischt nur ein Stueck). Frueher: harter Reset rueckwaerts.
func _test_resume_behind_monotone() -> void:
	print("- Resume mit Audio 20..85 ms hinter der Uhr: nie rueckwaerts, holt auf")
	var all_mono := true
	var worst_dev := 0.0
	for behind in [20.0, 49.0, 51.0, 60.0, 85.0]:
		var sm = SC.Smoother.new()
		var t_us := 0
		var last := -INF
		for i in 60:
			last = sm.sample(float(t_us) / 1000.0, t_us)
			t_us += 16667
		var held: float = last
		for i in 20:
			var h: float = sm.hold(t_us)
			all_mono = all_mono and h >= last
			last = h
			t_us += 16667
		var audio_ms: float = held - behind
		var out := 0.0
		for i in 90:
			out = sm.sample(audio_ms, t_us)
			all_mono = all_mono and out >= last
			last = out
			audio_ms += 16.667
			t_us += 16667
		worst_dev = maxf(worst_dev, absf(out - (audio_ms - 16.667)))
	_ok(all_mono, "monoton fuer alle Rueckstaende")
	_ok(worst_dev <= 1.0, "nach 1.5 s wieder an der Audio-Uhr (Abw. %.3f)" % worst_dev)


## Mix-Thread haengt (Last): Rohzeit = Position + Zeit seit Mix laeuft
## 150 ms weiter, dann kommt ein einzelner Block -> Rohzeit faellt ~120 ms.
func _test_mix_stall_monotone() -> void:
	print("- Mix-Stau: Rohzeit faellt 120 ms zurueck -> nie rueckwaerts, keine Drift")
	var sm = SC.Smoother.new()
	var t_us := 0
	var last := -INF
	var mono := true
	var audio := 0.0
	for i in 400:
		var raw := audio
		if i == 109:
			audio -= 120.0  # Treiber hat Zeit verloren: Audio liegt zurueck
			raw = audio
		var out: float = sm.sample(raw, t_us)
		mono = mono and out >= last
		last = out
		audio += 16.667
		t_us += 16667
	_ok(mono, "monoton ueber Stau und Rueckfall")
	var dev := absf(last - (audio - 16.667))
	_ok(dev <= 1.0, "danach wieder an der Audio-Uhr (Abw. %.3f)" % dev)


## Lead-In -> Audio: Rohzeit springt um den veralteten Mix-Zeitstempel
## (bis zu einen Block) vor. settle(): weich nachfuehren, kein harter Sprung.
func _test_settle_forward_smooth() -> void:
	print("- Lead-In -> Audio (+70 ms Rohsprung): weich, monoton, holt auf")
	var sm = SC.Smoother.new()
	var t_us := 0
	var last := -INF
	for i in 30:
		last = sm.sample(float(t_us) / 1000.0 - 300.0, t_us)
		t_us += 16667
	sm.settle()
	var mono := true
	var max_step := 0.0
	var out := 0.0
	var tr := 0.0
	for i in 60:
		tr = float(t_us) / 1000.0 - 300.0 + 70.0
		out = sm.sample(tr, t_us)
		mono = mono and out >= last
		max_step = maxf(max_step, out - last)
		last = out
		t_us += 16667
	_ok(mono, "monoton")
	_ok(max_step < 16.667 + 35.0, "kein harter Sprung (groesster Schritt %.2f ms)" % max_step)
	_ok(absf(out - tr) <= 1.0, "nach 1 s an der Audio-Uhr (Abw. %.3f)" % absf(out - tr))


func _test_movie_fps_parse() -> void:
	print("- Movie-FPS aus der Kommandozeile")
	_ok(is_equal_approx(SC.movie_fps_from_cmdline(PackedStringArray(["--write-movie", "a.avi", "--fixed-fps", "30"])), 30.0),
			"--fixed-fps 30")
	_ok(is_equal_approx(SC.movie_fps_from_cmdline(PackedStringArray(["--fixed-fps=24"])), 24.0), "--fixed-fps=24")
	var def := float(ProjectSettings.get_setting("editor/movie_writer/fps", 60))
	_ok(is_equal_approx(SC.movie_fps_from_cmdline(PackedStringArray()), def),
			"ohne Angabe: editor/movie_writer/fps (%.0f)" % def)


## Film-Uhr gegen ein nachgebautes Movie-Writer-Mixing: pro Frame 1600
## Samples Ausgabe (48 kHz / 30 fps), gemischt in 512er-Schritten mit Vorrat.
## Die rohe Position laeuft 0..10.7 ms vor dem Hoerbaren, die Uhr nicht.
func _test_movie_clock() -> void:
	print("- Film-Uhr: 512er-Mix-Vorrat, Pause -> sample-genau, monoton")
	var mc = SC.MovieClock.new()
	var spf := 1600
	# Vorrat im Mix-Puffer beim Start (Stille). Real immer ein Vielfaches von
	# ggT(1600, 512) = 64, weil der Puffer leer startet.
	var left := 320
	var left_song := 0  # davon Song-Samples
	var pos := 0  # gemischte Song-Samples (= get_playback_position)
	var heard := 0  # ausgegebene Song-Samples (= Wahrheit im Film)
	var playing := true
	var mono := true
	var ahead_max := 0.0
	var below := false
	var last := -INF
	var dev := INF
	var raw_jitter := 0.0
	mc.anchor(0.0, 0.0)
	for k in 120:
		var film := float(k) * 1000.0 / 30.0
		if k == 50:
			playing = false
		if k == 70:
			playing = true
		var v: float = mc.sample(float(pos) / 48.0, film)
		var truth := float(heard) / 48.0
		mono = mono and v >= last
		last = v
		below = below or v < truth - 0.0001
		ahead_max = maxf(ahead_max, v - truth) if k >= 90 else ahead_max
		raw_jitter = maxf(raw_jitter, float(pos - heard) / 48.0)
		dev = absf(v - truth)
		# Frame-Ende: Movie-Writer gibt spf Samples aus, erst den Vorrat.
		var use := mini(left, spf)
		var from_left := mini(left_song, use)
		heard += from_left
		left -= use
		left_song -= from_left
		var out := use
		while out < spf:
			var song := 512 if playing else 0
			pos += song
			var take := mini(512, spf - out)
			heard += mini(song, take)
			out += take
			left = 512 - take
			left_song = song - mini(song, take)
	_ok(raw_jitter > 5.0, "rohe Position laeuft voraus (bis %.2f ms)" % raw_jitter)
	_ok(mono, "monoton (auch ueber Pause)")
	_ok(not below, "nie hinter dem Hoerbaren")
	_ok(ahead_max < 0.001 and dev < 0.001, "nach Resume sample-genau (Abw. %.4f ms)" % maxf(ahead_max, dev))


func _test_fade_level() -> void:
	print("- Lautstaerke-Rampe 12 ms")
	_ok(SC.FADE_MS >= 10.0 and SC.FADE_MS <= 15.0, "Rampe 10-15 ms")
	_ok(is_equal_approx(SC.fade_level(1.0, 0.0, 0.0), 1.0), "Start = 1")
	_ok(is_equal_approx(SC.fade_level(1.0, 0.0, 6.0), 0.5), "Mitte = 0.5")
	_ok(is_equal_approx(SC.fade_level(1.0, 0.0, 30.0), 0.0), "Ende = 0 (geklemmt)")
	_ok(is_equal_approx(SC.fade_level(0.0, 1.0, -5.0), 0.0), "vor Start geklemmt")


func _test_project_settings() -> void:
	print("- Projekt-Einstellungen fuer Input")
	_ok(bool(ProjectSettings.get_setting("input_devices/buffering/agile_event_flushing", false)),
			"agile_event_flushing = true")


func _test_live_clock() -> void:
	print("- Live-Autoload SyncClock")
	var clock := root.get_node_or_null("/root/SyncClock")
	_ok(clock != null, "SyncClock vorhanden")
	if clock == null:
		return
	_ok(clock.has_method("visual_time_ms"), "visual_time_ms() vorhanden")
	_ok(absf(clock.visual_time_ms() - clock.song_time_ms() - clock.visual_offset_ms()) < 0.0001,
			"visual = song + visual_offset")
	_ok(clock.song_time_ms() == 0.0 and not clock.is_playing(), "gestoppt: Zeit 0")


## Jack: zwei Noten in Spalte 0 (1000, 1150). Spieler verpasst die erste,
## drueckt bei 1140 — ZWISCHEN zwei Frames (kein update() dazwischen). Der
## Druck muss die zweite Note treffen (die erste ist da schon abgelaufen).
func _test_jack_between_frames() -> void:
	print("- Event-genaues Judgement: Jack-Druck zwischen zwei Frames")
	var core := _make_core("64,192,1000,1,0,0:0:0:0:\n64,192,1150,1,0,0:0:0:0:\n")
	core.update(1100.0)  # letzter Frame: erste Note noch im Fenster
	core.key_down(0, 1140.0)
	_ok(core.n_miss == 1, "erste Note Miss (abgelaufen)")
	_ok(core.n_max == 1, "zweite Note MAX (dt -10)")
	_ok(core.combo == 1, "Combo 1")


func _test_windows_unchanged() -> void:
	print("- Fenster unveraendert (OD5)")
	var core := _make_core("64,192,1000,1,0,0:0:0:0:\n")
	_ok(is_equal_approx(core.w_max, 16.5) and is_equal_approx(core.w300, 49.5) \
			and is_equal_approx(core.w200, 82.5) and is_equal_approx(core.w100, 112.5) \
			and is_equal_approx(core.w50, 136.5) and is_equal_approx(core.w_miss, 173.5),
			"16.5/49.5/82.5/112.5/136.5/173.5")
	core.key_down(0, 1136.5)
	_ok(core.n50 == 1, "dt +136.5 = MEH (Grenze inklusive)")
	var c2 := _make_core("64,192,1000,1,0,0:0:0:0:\n")
	c2.key_down(0, 1136.6)
	c2.update(1136.6)
	_ok(c2.n_miss == 1 and c2.n50 == 0, "dt +136.6 = Miss")


func _make_core(hitobjects: String) -> ManiaCore:
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: 5\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n" + hitobjects
	var res := OsuParser.parse(txt)
	var core := ManiaCore.new()
	core.setup(res.beatmap)
	return core


func _silence(sec: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 48000
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(int(sec * 48000.0) * 2)
	wav.data = data
	return wav


func _sample_mono() -> float:
	var v := 0.0
	for i in 3:
		v = _clock.song_time_ms()
		if v < _last_v:
			_mono = false
		_last_v = v
	return v


func _live_step() -> void:
	var el := Time.get_ticks_msec() - _t0
	var player := _clock.get_node("SyncAudioPlayer") as AudioStreamPlayer
	match _step:
		0:
			var v := _sample_mono()
			if el >= 100 and _mark == 0.0:
				_mark = v
				_ok(v > -300.0 and v < -150.0, "Lead-In laeuft (%.1f ms)" % v)
			if el >= 450 and el < 700:
				# Abstand zur Audio-Rohzeit mitteln: die Rohzeit des Dummy-
				# Treibers ist ein Saegezahn (Mix-Thread schlaeft ungenau,
				# Mix-Race), die Uhr folgt ihrem Mittel.
				var near := INF
				for i in 3:
					var d: float = v - _clock.raw_time_ms()
					if absf(d) < absf(near):
						near = d
				_dev_sum += near
				_dev_n += 1
			if el >= 700:
				# Relativ zur tatsaechlich vergangenen Zeit pruefen (Frame-Takt
				# schwankt unter Last). Die Audio-Konvention (Position + Zeit seit
				# Mix) liegt bis zu einen Mix-Block (Dummy: 85 ms) vor der
				# Wanduhr des Lead-In -> Band statt fester Toleranz.
				var ahead := v - (float(el) - 300.0)
				_ok(ahead > -40.0 and ahead < 130.0, "nach Lead-In Audio-Zeit folgt Echtzeit (%.1f ms bei el=%d)" % [v, el])
				var mean := _dev_sum / maxf(float(_dev_n), 1.0)
				_ok(_dev_n > 0 and absf(mean) < 10.0,
						"an der Audio-Uhr (mittlere Abw. %.2f ms, %d Frames)" % [mean, _dev_n])
				_ok(player.playing, "Audio spielt")
				_gain = player.volume_db
				_clock.pause()
				_step = 1
		1:
			_sample_mono()
			if el >= 800:
				_ok(_clock.is_paused() and player.stream_paused, "nach Rampe pausiert")
				_mark = _sample_mono()
				_step = 2
		2:
			var v := _sample_mono()
			if el >= 1000:
				_ok(absf(v - _mark) < 0.001, "Zeit steht in Pause (%.3f ms Drift)" % (v - _mark))
				_clock.resume()
				_step = 3
		3:
			var v := _sample_mono()
			if el >= 1300 and not _seek_checked:
				_seek_checked = true
				_clock.seek_ms(v - 200.0)
				var after := _sample_mono()
				_ok(after >= v and after - v < 20.0, "seek_ms rueckwaerts ignoriert (%.2f -> %.2f)" % [v, after])
			if el >= 1100 and _mark >= 0.0:
				_ok(is_equal_approx(player.volume_db, _gain),
						"Rampe nach Resume fertig (volume_db %.2f)" % player.volume_db)
				_mark = -v - 1.0  # Startwert merken (negativ kodiert)
			if el >= 1600:
				var start := -_mark - 1.0
				_ok(absf((v - start) - 500.0) < 30.0, "laeuft nach Resume mit Echtzeit (+%.1f ms in 500 ms)" % (v - start))
				_ok(_mono, "Song-Zeit monoton ueber Lead-In, Pause, Resume")
				_clock.stop()
				_ok(_clock.song_time_ms() == 0.0, "stop(): Zeit 0")
				_step = 4
		4:
			if el >= 1700:
				_ok(not player.playing, "nach Stopp-Rampe gestoppt")
				_start_movie()
		5:
			_movie_step(player)


## Movie-Modus: Zeit = Frames / FPS, unabhaengig von der Wanduhr. Einzelne
## Frames werden kuenstlich verzoegert (langsames Rendern beim Film).
func _start_movie() -> void:
	print("- Movie-Modus (60 fps): Lead-In und Uhr laufen nach Film-Zeit")
	_clock.set_movie_mode(true, 60.0)
	_ok(_clock.is_movie_mode(), "Movie-Modus aktiv")
	_ok(_clock.visual_offset_ms() == 0.0, "kein visual_offset im Film")
	_clock.play(_silence(4.0), 300.0)
	_f0 = Engine.get_process_frames()
	_movie_last = -INF
	_step = 5


func _movie_us(frames: int) -> float:
	return roundf(float(frames) * 1000000.0 / 60.0)


func _movie_step(player: AudioStreamPlayer) -> void:
	var frames := Engine.get_process_frames()
	var f := frames - _f0
	# Im Test mischt der Dummy-Treiber in einem eigenen Thread (im echten
	# Film nicht): Position vor und nach der Abfrage einklammern.
	var v: float = _clock.song_time_ms()
	var pos1 := player.get_playback_position() * 1000.0
	if v < _movie_last:
		_movie_ok = false
	if not player.playing:
		# Lead-In: exakt Frames * 1000/60 - 300, egal wie lange der Frame dauerte.
		var want := (_movie_us(frames) - _movie_us(_f0)) / 1000.0 - 300.0
		_movie_worst = maxf(_movie_worst, absf(v - want))
		if f % 3 == 1:
			OS.delay_msec(25)  # langsamer Frame: Wanduhr laeuft davon
	else:
		if not _movie_played:
			_movie_played = true
			_ok(_movie_worst < 0.01, "Lead-In = Frames/FPS (max Abw. %.4f ms)" % _movie_worst)
			_ok(f >= 18 and f <= 20, "Audio startet nach 300 ms Film-Zeit (Frame %d)" % f)
		# Film-Uhr laeuft nie der gemischten Audio-Position voraus.
		_movie_play_dev = maxf(_movie_play_dev, v - maxf(pos1, _movie_last))
	_movie_last = v
	if f == 3:
		_ok(absf(_clock.judgement_time_ms() - v - _clock.user_offset_ms) < 0.0001,
				"Judgement = Film-Zeit + Offset")
	if f >= 45:
		_ok(_movie_played, "Audio gestartet")
		_ok(_movie_play_dev < 0.001, "Wiedergabe: Uhr nie vor der Audio-Position (%.4f ms)" % _movie_play_dev)
		_ok(_movie_ok, "Film-Zeit monoton")
		_clock.stop()
		_clock.set_movie_mode(false)
		_ok(not _clock.is_movie_mode(), "Movie-Modus wieder aus")
		_live = false
		_finish()
