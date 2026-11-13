extends Control

## Dirigent-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause,
## Ende -> Results, Score speichern unter Modus "dirigent", Multiplayer-Meldungen).
## Darstellung: DirigentView. Logik: DirigentChart/DirigentCore.
##
## Steuerung: die Hand (Maus/Tablet, absolute Position) fuehrt die Taktfigur von
## Punkt zu Punkt; Taste A/B (Settings.dirigent_key_a/b, Maus links/rechts)
## setzen die Einsaetze.
## CLI: --dirigent --autoplay, --shot --shot-at=<ms|dense|kiai|change> --shot-out=<png>,
## --shot-results, --auto-miss=<n>, --auto-jitter=<ms>, --auto-aim=<0..>,
## --auto-seed=<n>, --dirigent-map=<Teil des osz-Namens> [--dirigent-diff=<Version>].
## Replays: DirigentCore schreibt die Eingaben mit (core.replay_log); am Ende
## DirigentReplay "last" und "best". GameSession.is_replay + replay_mode
## "dirigent" spielt die Events wieder ab (gleiche Wertung).

const MODE := "dirigent"
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.45, 0.95, 0.55),
	"B": Color(0.45, 0.70, 1.0), "C": Color(0.80, 0.55, 1.0), "D": Color(1.0, 0.45, 0.45),
}
const JUDGE_SCALE := 0.5
const SHOT_STEP_MS := 16.0

var core: DirigentCore
var chart: DirigentChart
var _beatmap: Beatmap
var _use_audio := false
var _debug_start_usec := 0
var _debug_running := false
var _ended := false
var _autoplay := false
var _auto_miss := 0
var _bot_plan: Dictionary = {}
var _countdown_running := false
var _song_len_ms := 1.0
var _held := [[false, false], [false, false]]
var _flash := [0.0, 0.0]
var _shot := false
var _sim_t := 0.0
var _last_update_t := 0.0
var _replay := false
var _replay_events: Array = []
var _replay_idx := 0
var _mp_send_cd := 0.0
var _mp_bot := false
var _mp_cut_ms := -1.0
var _mp_live_seen: Dictionary = {}
var _mp_skip_voted := false
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()
var _hit_log: Array = []

var _view: DirigentView
var _hud: CanvasLayer
var _judge_disp: JudgeDisplay
var _err_bar: HitErrorBar
var _acc_label: Label
var _score_label: Label
var _grade_label: Label
var _beat_label: Label
var _cue_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _hint: Label
var _pause_menu: PauseMenu
var _results: DirigentResults
var _bg: ColorRect
var _cover: Control
## Einsatz-Klaenge je Taste (gleiche Streams wie die Orbit-Spuren).
var _snd: Array = [null, null]


func _ready() -> void:
	_ensure_translations()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var args := _args()
	_shot = args.has("--shot")
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	_replay = GameSession.is_replay and GameSession.replay_mode == DirigentReplay.MODE
	if GameSession.is_replay and not _replay:
		GameSession.is_replay = false   # fremde Replay-Events passen nicht
		GameSession.replay_events = []
	_mp_bot = Lobby.active and Lobby.in_game and args.has("--mp-bot")
	# --mp-bot spielt selbst (ohne --autoplay: dessen Watchdog wuerde den Smoke kappen).
	_autoplay = ((args.has("--autoplay") and not Lobby.active) or _mp_bot) and not _replay
	var jitter := 4.0
	var aim := 0.7
	var seed_v := 1
	for a in args:
		if a.begins_with("--auto-miss="):
			_auto_miss = maxi(0, a.trim_prefix("--auto-miss=").to_int())
		elif a.begins_with("--auto-jitter="):
			jitter = maxf(0.0, a.trim_prefix("--auto-jitter=").to_float())
		elif a.begins_with("--auto-aim="):
			aim = maxf(0.0, a.trim_prefix("--auto-aim=").to_float())
		elif a.begins_with("--auto-seed="):
			seed_v = a.trim_prefix("--auto-seed=").to_int()
		elif a.begins_with("--mp-cut="):
			_mp_cut_ms = maxf(0.0, a.trim_prefix("--mp-cut=").to_float()) * 1000.0
	_build_core()
	if _replay:
		_replay_events = GameSession.replay_events
		if not DirigentReplay.is_current(_replay_events):
			_replay_events = []
	if _autoplay:
		_bot_plan = DirigentCore.bot_plan(chart, seed_v, jitter, aim, _auto_miss)
	_bg = ColorRect.new()
	_bg.color = DirigentView.PLATE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_build_cover()
	_view = DirigentView.new()
	add_child(_view)
	_view.setup(chart, core)
	_view.show_guides = Settings.orbit_guides
	_view.key_names = [UiTheme.key_short(Settings.dirigent_key_a), UiTheme.key_short(Settings.dirigent_key_b)]
	_build_hud()
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.orbit_hit_stream(k)
		add_child(p)
		_snd[k] = p
	_update_hud()
	if _mp_bot:
		if _mp_cut_ms >= 0.0:
			_mp_cut_ms += float(chart.beats[0].t)
		print("MPORBIT start: %d Schlaege, %d Einsaetze, autoplay=%s, cut=%d ms" % [
			chart.beats.size(), chart.cues.size(), _autoplay, int(_mp_cut_ms)])
	if DisplayServer.get_name() == "headless" and not _mp_bot:
		print("=== Dirigent Smoke: %d Schlaege, %d Einsaetze, %.2f Sterne ===" % [
			chart.beats.size(), chart.cues.size(), chart.stars()])
		get_tree().quit(0)
		return
	if Lobby.active and Lobby.in_game:
		Lobby.skip_now.connect(_do_skip)
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if _shot:
		_capture_shot()
	elif _movie_from() >= 0.0:
		_movie_run()
	else:
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)


func _movie_from() -> float:
	for a in _args():
		if a.begins_with("--movie-from="):
			return a.trim_prefix("--movie-from=").to_float()
	return -1.0


## Debug (Demo-Videos): --movie-from=<ms> --movie-len=<s> mit --autoplay --write-movie.
## Spult Wertung + Ton auf <ms>-2,5 s vor, druckt MOVIE_START frame=<n>, endet nach <s> s.
func _movie_run() -> void:
	var from := _movie_from()
	var len_s := 22.0
	for a in _args():
		if a.begins_with("--movie-len="):
			len_s = a.trim_prefix("--movie-len=").to_float()
	var cut := from - 2500.0
	var t := float(chart.beats[0].t) - 1200.0
	while t < cut and not core.is_finished():
		t += 16.0
		if _autoplay:
			core.bot_step(_bot_plan, t)
		core.update(t)
	_last_update_t = t
	if _use_audio:
		SyncClock.seek_ms(cut)
	print("MOVIE_START frame=%d" % Engine.get_process_frames())
	await get_tree().create_timer(len_s, true).timeout
	get_tree().quit(0)


## Uebersetzungen aus translations/dirigent.csv (auch ohne Eintrag in project.godot).
static func _ensure_translations() -> void:
	for loc in ["de", "en"]:
		var path := "res://translations/dirigent.%s.translation" % loc
		if ResourceLoader.exists(path):
			var tr_res := load(path) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)


# ---------------------------------------------------------------------------
# Laden
# ---------------------------------------------------------------------------

func _load_beatmap() -> bool:
	_cli_pick()
	if not GameSession.has_selection():
		return false
	var imp := OszImporter.import(GameSession.osz_path)
	if not imp.ok:
		return false
	_beatmap = null
	for d in imp.difficulties:
		if d.beatmap.version_name() == GameSession.difficulty_version:
			_beatmap = d.beatmap
			break
	if _beatmap == null and not imp.difficulties.is_empty():
		_beatmap = imp.difficulties[0].beatmap
	if _beatmap == null or _beatmap.hit_objects.is_empty() \
			or not (_beatmap.is_mania() or _beatmap.mode() == 0):
		return false
	chart = DirigentChart.build(_beatmap)
	if chart.beats.is_empty():
		return false
	if not _args().has("--shot"):
		var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
		if stream != null:
			# Erster Schlag + Anlauf (Raum fuer den Countdown) hat immer genug Vorlauf.
			var lead := _beatmap.audio_lead_in()
			var need := 1600.0 - float(chart.beats[0].t)
			if lead < need:
				lead = need
			SyncClock.play(stream, lead)
			_use_audio = true
	return true


func _cli_pick() -> void:
	var want := ""
	for a in _args():
		if a.begins_with("--dirigent-map=") or a.begins_with("--orbit-map="):
			want = a.get_slice("=", 1)
		elif a.begins_with("--dirigent-diff=") or a.begins_with("--orbit-diff="):
			GameSession.difficulty_version = a.get_slice("=", 1)
	if want == "":
		return
	var dir := MapLibrary.default_maps_dir()
	for f in DirAccess.get_files_at(dir):
		if f.to_lower().ends_with(".osz") and f.findn(want) >= 0:
			GameSession.osz_path = dir.path_join(f)
			return


## Konzertsaal-Grund: Map-Bild weich geblurt und stark abgedunkelt (wie Orbit),
## Buehnenlicht und Orchester zeichnet die View darueber.
func _build_cover() -> void:
	# Gemeinsamer Modus-Hintergrund (weich, abgedunkelt, Vignette, Korn); ohne Bild
	# bleibt der Graphit-Grund.
	_cover = MapBackdrop.create(OszImporter.load_background_texture(GameSession.osz_path, _beatmap))
	add_child(_cover)


func _build_core() -> void:
	core = DirigentCore.new()
	core.setup(chart, _beatmap.od())
	core.beat_judged.connect(_on_beat_judged)
	core.cue_judged.connect(_on_cue_judged)
	core.key_pressed.connect(_on_key_pressed)
	core.wrong_key.connect(func(_k, _i): if _view != null: _view.on_wrong_key())
	core.finished.connect(func(_s): _show_results())
	core.set_replay_mode(not _replay)


## Kommandozeile inkl. Argumente hinter "--".
static func _args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


func _time_ms() -> float:
	if _shot:
		return _sim_t
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - 1000.0


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)


func _tabular_font(ref: Control) -> Font:
	var fv := FontVariation.new()
	fv.base_font = ref.get_theme_default_font() if ref.get_theme_default_font() != null else ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	fv.opentype_features = { ts.name_to_tag("tnum"): 1 }
	return fv


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_song_len_ms = maxf(_beatmap.duration_ms(), 1.0)
	var title := Label.new()
	title.text = "%s — %s  ·  %s" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()]
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_shadow(title)
	title.modulate.a = 0.75
	_hud.add_child(title)
	var tag := Label.new()
	tag.text = tr("DIRIGENT")
	tag.position = Vector2(24, 34)
	tag.add_theme_font_override("font", UiTheme.heading_font(3))
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(UiTheme.ACCENT, 0.85))
	_hud.add_child(tag)
	var ttw := create_tween()
	ttw.tween_interval(8.0)
	ttw.tween_property(title, "modulate:a", 0.35, 1.5)

	_time_label = Label.new()
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.offset_left = -240
	_time_label.offset_right = -20
	_time_label.offset_top = 14
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.85, 0.85))
	_time_label.add_theme_font_override("font", _tabular_font(_time_label))
	_shadow(_time_label)
	_hud.add_child(_time_label)

	var top_bg := ColorRect.new()
	top_bg.anchor_right = 1.0
	top_bg.offset_bottom = 4
	top_bg.color = Color(1, 1, 1, 0.08)
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top_bg)
	_top_fill = ColorRect.new()
	_top_fill.anchor_right = 0.0
	_top_fill.offset_bottom = 4
	_top_fill.color = Color(UiTheme.ACCENT, 0.75)
	_top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_fill)

	# Wie Mania: Rang bei der Genauigkeit links, rechts eine kompakte Zaehler-Gruppe.
	var left := _stat_column(Vector2(0.085, 0.42))
	_grade_label = _stat_block(left, tr("RANG"), 26)
	_acc_label = _stat_block(left, tr("GENAUIGKEIT"), 28)
	var right := _stat_column(Vector2(0.915, 0.42))
	_score_label = _stat_block(right, tr("PUNKTE"), 30)
	_beat_label = _stat_block(right, tr("TAKT"), 24)
	_cue_label = _stat_block(right, tr("EINSÄTZE"), 24)

	_err_bar = HitErrorBar.new()
	_hud.add_child(_err_bar)
	_err_bar.setup({"max": core.w_max, "w300": core.w300, "w200": core.w200,
		"w100": core.w100, "w50": core.w50}, 260.0)

	_judge_disp = JudgeDisplay.new()
	_hud.add_child(_judge_disp)
	_judge_disp.setup(UiTheme.ACCENT)
	_judge_disp.window_300_ms = float(core.w_max)

	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = tr("Führe die Hand von Punkt zu Punkt, genau auf den Schlag. Einsätze mit den Tasten %s und %s.") % [
		UiTheme.key_short(Settings.dirigent_key_a), UiTheme.key_short(Settings.dirigent_key_b)]
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_shadow(_hint)
	_hud.add_child(_hint)
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


func _stat_column(anchor_pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_left = anchor_pos.x
	v.anchor_right = anchor_pos.x
	v.anchor_top = anchor_pos.y
	v.anchor_bottom = anchor_pos.y
	v.offset_left = -120
	v.offset_right = 120
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 22)
	_hud.add_child(v)
	return v


func _stat_block(column: VBoxContainer, caption: String, size_px: int) -> Label:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", -2)
	column.add_child(block)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", Color(0.58, 0.61, 0.70))
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cap.add_theme_constant_override("shadow_outline_size", 5)
	block.add_child(cap)
	var val := Label.new()
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", size_px)
	val.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	val.add_theme_constant_override("shadow_outline_size", 6)
	val.add_theme_font_override("font", _tabular_font(val))
	block.add_child(val)
	return val


func _place_hud() -> void:
	if _judge_disp == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var cy := vs.y * 0.5
	var k := JUDGE_SCALE * vs.y / 720.0
	_judge_disp.pivot_offset = vs * 0.5
	_judge_disp.scale = Vector2(k, k)
	_judge_disp.judge_gap = 0.0
	_judge_disp.combo_gap = vs.y * 0.045 / k
	# Wertung + Kombo zwischen Figur und Einsatz-Leiste.
	_judge_disp.place(cy + (vs.y * 0.757 - cy) / k)
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5, vs.y - _err_bar.size.y - 8.0)
	_hint.size = Vector2(vs.x, 24)
	_hint.position = Vector2(0, vs.y * 0.075)


func _update_hud() -> void:
	_judge_disp.set_combo(core.combo)
	var s: Dictionary = core.stats()
	var judged := int(s.n_max) + int(s.n300) + int(s.n200) + int(s.n100) + int(s.n50) + int(s.n_miss)
	if judged == 0 and core.beat_log.is_empty():
		_grade_label.text = "-"
		_grade_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		_acc_label.text = UiTheme.fmt_pct(100.0)
	else:
		var g := str(s.grade)
		_grade_label.text = g
		_grade_label.add_theme_color_override("font_color", GRADE_COLOR.get(g, Color.WHITE))
		_acc_label.text = UiTheme.fmt_pct(float(s.accuracy) * 100.0)
	_score_label.text = PauseMenu.fmt_int(int(s.score))
	_beat_label.text = UiTheme.fmt_pct(float(s.beat_acc) * 100.0)
	_cue_label.text = UiTheme.fmt_pct(float(s.cue_acc) * 100.0)
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.anchor_right = clampf(t / _song_len_ms, 0.0, 1.0)


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _set_cursor_from(pos: Vector2, t: float) -> void:
	_view.push_cursor(pos)
	core.cursor_moved(_view.to_unit(pos), t)


func _input(event: InputEvent) -> void:
	if _ended or _autoplay or _replay or core == null:
		return
	if event is InputEventMouseMotion:
		_set_cursor_from(event.position, _time_ms())
	elif event is InputEventMouseButton:
		var key := -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			key = 0
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			key = 1
		if key >= 0:
			_set_cursor_from(event.position, _time_ms())
			_press(key, 0, event.pressed)
	elif event is InputEventKey and not event.echo:
		var key := Settings.dirigent_key_for(event.keycode)
		if key >= 0:
			_press(key, 1, event.pressed)


func _press(key: int, source: int, down: bool) -> void:
	if get_tree().paused or _countdown_running:
		return
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	if now and not was:
		core.key_down(key, _time_ms())
	_view.key_held[key] = now


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running:
			_toggle_pause(true)
		return
	if event.keycode == KEY_R and Settings.dirigent_key_for(KEY_R) == -1 and not Lobby.active:
		_restart()
		return
	if event.keycode == KEY_SPACE and not _ended and Settings.dirigent_key_for(KEY_SPACE) == -1 \
			and _can_skip_intro():
		if Lobby.active and Lobby.in_game:
			Lobby.vote_skip()
		else:
			_do_skip()


func _can_skip_intro() -> bool:
	return _use_audio and float(chart.beats[0].t) - _time_ms() > 4500.0


func _do_skip() -> void:
	SyncClock.seek_ms(float(chart.beats[0].t) - 2400.0)


# ---------------------------------------------------------------------------
# Frame-Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null or _view == null:
		return
	if _shot:
		_sim_t += delta * 1000.0 if _shot_live else 0.0
	var t := _time_ms()
	if _autoplay:
		_step_bot(t)
	if _replay:
		_feed_replay(t)
	_last_update_t = t
	core.update(t)
	if _ended:
		return
	if _mp_bot:
		_mp_bot_tick(t)
		if _ended:
			return
	for k in 2:
		_flash[k] = maxf(float(_flash[k]) - delta, 0.0)
		if _autoplay or _replay:
			_view.key_held[k] = float(_flash[k]) > 0.0
	_view.t_ms = t
	if _autoplay or _replay:
		_view.cursor_px = _view.to_px(core.cursor_pos())
		_view.push_cursor(_view.cursor_px)
	_view.kiai = lerpf(_view.kiai, 1.0 if _beatmap.is_kiai(t) else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	if Lobby.active and Lobby.in_game:
		_mp_send_cd -= delta
		if _mp_send_cd <= 0.0:
			_mp_send_cd = 0.25
			Lobby.send_score(core.dirigent_score(), core.combo, core.accuracy())
	if _hint != null and _hint.visible:
		var lead := float(chart.beats[0].t) - t
		_hint.modulate.a = clampf((lead + 1200.0) / 900.0, 0.0, 1.0)
		if _hint.modulate.a <= 0.0 and t > 0.0:
			_hint.visible = false
	_update_hud()


## MP-Smoke: Intro-Skip stimmen, Live-Scores der anderen mitschreiben, Abbruch per --mp-cut.
func _mp_bot_tick(t: float) -> void:
	if not _mp_skip_voted and _can_skip_intro():
		_mp_skip_voted = true
		Lobby.vote_skip()
	var me := multiplayer.get_unique_id()
	for id in Lobby.players:
		var p: Dictionary = Lobby.players[id]
		if int(id) == me or not (p.get("final", {}) as Dictionary).is_empty():
			continue
		_mp_live_seen[int(id)] = maxi(int(_mp_live_seen.get(int(id), 0)), int(p.get("score", 0)))
	if _mp_cut_ms >= 0.0 and t >= _mp_cut_ms:
		print("MPORBIT cut at %d ms" % int(t))
		_show_results()


func _step_bot(t: float) -> void:
	core.bot_step(_bot_plan, t)


func _feed_replay(t: float) -> void:
	while _replay_idx < _replay_events.size() and float(_replay_events[_replay_idx][0]) <= t:
		core.apply_event(_replay_events[_replay_idx])
		_replay_idx += 1


func _on_beat_judged(index: int, result: Dictionary) -> void:
	_view.on_beat_judged(index, result)
	_acc_trace.append(core.accuracy())


func _on_cue_judged(index: int, result: Dictionary) -> void:
	var q := int(result.quality)
	_view.on_cue_judged(index, result)
	_judge_disp.show_judge(q, float(result.dt) if q != 5 else 0.0)
	if q != 5:
		_err_bar.add_hit(float(result.dt))
		_hit_offsets.append(float(result.dt))
	_hit_log.append([float(chart.cues[index].t), float(result.dt), q, int(result.mask)])
	_acc_trace.append(core.accuracy())


func _on_key_pressed(key: int, hit: bool) -> void:
	_flash[key] = 0.11
	if hit and _use_audio and Settings.hitsounds and Settings.hitsound_volume > 0.01 and _snd[key] != null:
		var p: AudioStreamPlayer = _snd[key]
		p.volume_db = linear_to_db(Settings.hitsound_volume) - 7.0
		p.play()


# ---------------------------------------------------------------------------
# Pause / Countdown / Ende
# ---------------------------------------------------------------------------

func _toggle_pause(paused: bool) -> void:
	if paused:
		if _pause_menu == null:
			_pause_menu = PauseMenu.new()
			_hud.add_child(_pause_menu)
			_pause_menu.resume_pressed.connect(func(): _toggle_pause(false))
			_pause_menu.restart_pressed.connect(_restart)
			_pause_menu.quit_pressed.connect(_back_to_browser)
		_pause_menu.open({
			"is_2d": false,
			"title": "%s — %s" % [_beatmap.artist(), _beatmap.title()],
			"progress": clampf(_time_ms() / maxf(_song_len_ms, 1.0), 0.0, 1.0),
			"score": int(core.stats().score),
			"acc": core.accuracy() * 100.0,
			"difficulty": _beatmap.version_name(),
			"length_ms": _song_len_ms,
		})
		get_tree().paused = true
		SyncClock.pause()
		_held = [[false, false], [false, false]]
		_view.key_held = [false, false]
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_menu != null and _pause_menu.visible:
			_pause_menu.close()
		_resume_with_countdown()


func _resume_with_countdown(step: float = 0.4) -> void:
	if _countdown_running:
		return
	_countdown_running = true
	var lbl := Label.new()
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = -100
	lbl.offset_right = 100
	lbl.offset_top = -60
	lbl.offset_bottom = 60
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 84)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.95))
	_hud.add_child(lbl)
	for n in [3, 2, 1]:
		lbl.text = str(n)
		if not await _countdown_wait(step):
			return
	lbl.queue_free()
	_countdown_running = false
	get_tree().paused = false
	SyncClock.resume()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _countdown_wait(sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	var acc := 0.0
	var tree := get_tree()
	var last := t0
	while acc < sec and float(Time.get_ticks_msec() - t0) < sec * 2000.0:
		await tree.process_frame
		if not is_inside_tree():
			return false
		var now := Time.get_ticks_msec()
		var d := get_process_delta_time()
		if d <= 0.0:
			d = float(now - last) / 1000.0
		last = now
		acc += clampf(d, 0.0, 0.1)
	return is_inside_tree()


func _restart() -> void:
	get_tree().paused = false
	SyncClock.stop()
	get_tree().reload_current_scene()


func _back_to_browser() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	if Lobby.active:
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _show_results() -> void:
	if _ended:
		return
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	var s: Dictionary = core.stats()
	s["unranked"] = false
	s["pp"] = -1.0
	s["mode"] = MODE
	s["stars"] = chart.stars()
	var new_best := false
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
		_save_replay(s, new_best)
		_submit_online(s)
	if Lobby.active and Lobby.in_game:
		Lobby.send_score(int(s.score), core.max_combo, float(s.accuracy))
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace, 0, 0, false))
	_view.visible = false
	_bg.visible = false
	if _cover != null:
		_cover.visible = false
	for ch in _hud.get_children():
		if ch is CanvasItem:
			ch.visible = false
	var rs := DirigentResults.new()
	_hud.add_child(rs)
	_results = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	var has_log := core.replay_log.size() > 1
	rs.show_results({
		"s": s,
		"beats": core.beat_log,
		"cues": _hit_log,
		"w50": core.w50,
		"w_max": core.w_max,
		"new_best": new_best,
		"title": _beatmap.title(),
		"artist": _beatmap.artist(),
		"version": _beatmap.version_name(),
		"allow_retry": not Lobby.active,
		"can_replay": not Lobby.active and (_replay or has_log),
		"is_replay": _replay,
	})
	if _args().has("--shot-results"):
		_capture_results_shot()
	if _mp_bot:
		print("MPORBIT final score=%d acc=%.4f combo=%d failed=false live_seen=%s" % [
			int(s.score), float(s.accuracy), int(s.get("max_combo", 0)), str(_mp_live_seen)])
		# Wie der Klick auf "Zurueck": nach dem Endscreen (--mp-back=<s>, Standard 1,5) in den Raum.
		var back_s := 1.5
		for a in _args():
			if a.begins_with("--mp-back="):
				back_s = clampf(a.trim_prefix("--mp-back=").to_float(), 0.0, 60.0)
		await get_tree().create_timer(back_s, true).timeout
		if is_inside_tree():
			_back_to_browser()


func _replay_meta(s: Dictionary) -> Dictionary:
	return {
		"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
		"date": Time.get_datetime_string_from_system(), "end_ms": int(_last_update_t),
		"rules": DirigentCore.REPLAY_RULES,
	}


func _save_replay(s: Dictionary, new_best: bool) -> void:
	if core.replay_log.size() <= 1:
		return
	var ver := _beatmap.version_name()
	var meta := _replay_meta(s)
	DirigentReplay.save(GameSession.osz_path, ver, core.replay_log, meta, "last")
	if new_best or not DirigentReplay.exists(GameSession.osz_path, ver, "best"):
		DirigentReplay.save(GameSession.osz_path, ver, core.replay_log, meta, "best")


func _on_results_replay() -> void:
	if _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
	elif core.replay_log.size() > 1:
		DirigentReplay.arm(core.replay_log)
	else:
		return
	_restart()


func _submit_online(s: Dictionary) -> void:
	var api: OnlineApi = GameSession.online
	if api == null or not api.enabled() or not api.logged_in():
		return
	var meta := OnlineApi.meta_from_beatmap(_beatmap, GameSession.osz_path,
		GameSession.osu_filename, float(s.get("stars", -1.0)))
	meta["total_notes"] = chart.cues.size()  # Counts n_max..n_miss zaehlen nur Einsaetze (Server: Summe = total_notes)
	var res := s.duplicate()
	res["date"] = Time.get_datetime_string_from_system(true)
	api.submit(res, meta, MODE)


# ---------------------------------------------------------------------------
# Shots (Harness): ohne Audio, Zeit laeuft simuliert
# ---------------------------------------------------------------------------

var _shot_live := false


func _shot_path(def: String) -> String:
	for a in _args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir().path_join(def)


func _save_shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT gespeichert: " + path)


## Bis t_to in festen Schritten simulieren (Bot spielt, Wertung laeuft).
func _fast_forward(t_to: float) -> void:
	while _sim_t < t_to and not core.is_finished():
		_sim_t += SHOT_STEP_MS
		if _autoplay:
			core.bot_step(_bot_plan, _sim_t)
		core.update(_sim_t)
	_last_update_t = _sim_t


func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	if v == "kiai":
		for b in chart.beats:
			if bool(b.kiai) and float(b.t) > 6000.0:
				return float(b.t) + 700.0
		return def
	if v == "change":
		for i in range(1, chart.bars.size()):
			if chart.bars[i].label != chart.bars[i - 1].label and float(chart.bars[i].t) > 3000.0:
				return float(chart.bars[i - 1].t) + 0.5 * (float(chart.bars[i].t) - float(chart.bars[i - 1].t))
		return def
	if v == "dense":
		var best := -1
		var at := def
		var j := 0
		for i in chart.cues.size():
			while float(chart.cues[i].t) - float(chart.cues[j].t) > DirigentView.BAR_LEAD_MS:
				j += 1
			if float(chart.cues[j].t) >= 8000.0 and i - j > best:
				best = i - j
				at = float(chart.cues[j].t) + 400.0
		return at
	return def


func _capture_shot() -> void:
	_autoplay = _autoplay or not _replay
	if _autoplay and _bot_plan.is_empty():
		_bot_plan = DirigentCore.bot_plan(chart, 1, 4.0, 0.7, 0)
	_sim_t = float(chart.beats[0].t) - 1200.0
	_hint.visible = false
	var target := float(chart.beats[mini(9, chart.beats.size() - 1)].t) + 250.0
	for a in _args():
		if a.begins_with("--shot-at="):
			target = _shot_target(a.trim_prefix("--shot-at="), target)
	if _args().has("--shot-results"):
		_fast_forward(chart.duration_ms + 6000.0)
		_show_results()
		return
	_fast_forward(target - 500.0)
	_shot_live = true
	_hint.visible = _sim_t < float(chart.beats[0].t)
	var guard := 0
	while _sim_t < target and guard < 400:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_shot_live = false
	await RenderingServer.frame_post_draw
	_save_shot(_shot_path("dirigent.png"))
	get_tree().quit(0)


func _capture_results_shot() -> void:
	await get_tree().create_timer(2.6, true).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_save_shot(_shot_path("dirigent_results.png"))
	get_tree().quit(0)
