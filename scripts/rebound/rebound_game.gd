extends Control

## Rebound-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause, Fail,
## Ende -> Results, Score unter Modus "rebound", Replays, Multiplayer).
## Wertung: ManiaCore unveraendert (nur Mania-4K-Maps). Bahnen: ReboundFlight,
## Darstellung: ReboundView. Szene: res://scenes/rebound.tscn mit
## GameSession.osz_path/difficulty_version.
##
## Tasten: Mania-4K-Belegung (Settings.key_lanes, Standard D F J K).
## CLI: --autoplay, --auto-miss=<n>, --auto-jitter=<ms>, --auto-seed=<n>,
## --rebound-map=<Teil des osz-Namens> [--rebound-diff=<Version>] [--rebound-dir=<Ordner>],
## --shot --shot-at=<ms|stream|jack|hold|chord|calm> --shot-out=<png>, --shot-results
## [--shot-fail], --shot-pause, --mp-bot, --mp-cut=<s>, --mp-back=<s>.

const MODE := "rebound"
const JUDGE_SCALE := 0.5
const LEAD_MS := 1800.0
## Replay-Regelversion: 2 = Anti-Mash (falsche Taste macht eine Note im 50er-Fenster zum Miss).
const AntiMash := preload("res://scripts/rebound/rebound_anti_mash.gd")
const REPLAY_RULES := 3
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.55, 0.85, 0.55),
	"B": Color(0.50, 0.70, 0.95), "C": Color(0.75, 0.58, 0.95), "D": Color(0.90, 0.50, 0.45),
}

var core: ManiaCore
var flight: ReboundFlight
var _beatmap: Beatmap
var _use_audio := false
var _debug_start_usec := 0
var _debug_running := false
var _ended := false
var _autoplay := false
var _countdown_running := false
var _song_len_ms := 1.0
var _view: ReboundView
var _hud: CanvasLayer
var _judge_disp: JudgeDisplay
var _err_bar: HitErrorBar
var _hp_bar: HpBar
var _acc_label: Label
var _score_label: Label
var _miss_label: Label
var _grade_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _pause_menu: PauseMenu
var _results: ResultsScreen
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()
var _judge_log: Array = []
var _hold_ok := 0
var _hold_drop := 0
var _hold_head_dt := {}
var _recorded: Array = []
var _held := [false, false, false, false]
var _plan: Array = []
var _plan_idx := 0
var _replay := false
var _old_replay := false
var _replay_idx := 0
var _last_update_t := 0.0
var _mp_send_cd := 0.0
var _mp_bot := false
var _mp_cut_ms := -1.0
var _mp_skip_voted := false
var _mp_live_seen: Dictionary = {}
var _first_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	_replay = GameSession.is_replay and GameSession.replay_mode == MODE \
			and ReboundReplay.replay_ok(GameSession.replay_events)
	if GameSession.is_replay and not _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
	_mp_bot = Lobby.active and Lobby.in_game and OS.get_cmdline_args().has("--mp-bot")
	_autoplay = ((OS.get_cmdline_args().has("--autoplay") and not Lobby.active) or _mp_bot) and not _replay
	var jitter := 0.0
	var seed := 1
	var skip := 0
	for a in OS.get_cmdline_args():
		if a.begins_with("--auto-miss="):
			skip = maxi(0, a.trim_prefix("--auto-miss=").to_int())
		elif a.begins_with("--auto-jitter="):
			jitter = maxf(0.0, a.trim_prefix("--auto-jitter=").to_float())
		elif a.begins_with("--auto-seed="):
			seed = a.trim_prefix("--auto-seed=").to_int()
		elif a.begins_with("--mp-cut="):
			_mp_cut_ms = maxf(0.0, a.trim_prefix("--mp-cut=").to_float()) * 1000.0
	if not _replay:
		_recorded = [AntiMash.marker()]
	core = ManiaCore.new()
	core.setup(_beatmap)
	# SV wirkt in Rebound nicht (ein Mehrspieler-Raum kann es setzen): kein Faktor, kein Badge.
	core.mods.erase("SV")
	core.mod_mult = ManiaCore.mod_multiplier(core.mods)
	core.note_judged.connect(_on_note_judged)
	core.hold_started.connect(_on_hold_started)
	core.finished.connect(func(_s): _show_results(false))
	if _autoplay:
		_plan = ReboundReplay.bot_plan(_beatmap, seed, jitter, skip)
	_build_bg()
	_view = ReboundView.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_view.setup(flight)
	_view.key_labels = []
	for c in 4:
		_view.key_labels.append(UiTheme.key_short(Settings.key_lanes[c]))
	_build_hud()
	_update_hud()
	if _old_replay:
		_show_old_replay()
		return
	if Lobby.active and Lobby.in_game:
		Lobby.skip_now.connect(_do_skip)
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if _mp_bot:
		print("MPORBIT start: %d Noten, autoplay=%s" % [_beatmap.hit_objects.size(), _autoplay])
	if DisplayServer.get_name() == "headless" and not _mp_bot:
		print("=== Rebound Smoke: %d Noten ===" % _beatmap.hit_objects.size())
		get_tree().quit(0)
		return
	if OS.get_cmdline_args().has("--shot"):
		_capture_shot()
	else:
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)


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
	if _beatmap == null or _beatmap.hit_objects.is_empty() or not _beatmap.is_mania() \
			or _beatmap.column_count() != 4:
		return false
	flight = ReboundFlight.from_beatmap(_beatmap, float(Settings.rebound_drop_ms))
	_first_t = _beatmap.hit_objects[0].time
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		var lead := _beatmap.audio_lead_in()
		lead = ReboundFlight.lead_in_ms(_first_t, float(Settings.rebound_drop_ms), lead)
		SyncClock.play(stream, lead)
		_use_audio = true
	return true


## Debug/Shots: --rebound-map=<Teil des osz-Namens> [--rebound-diff=<Version>].
func _cli_pick() -> void:
	var want := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--rebound-map="):
			want = a.trim_prefix("--rebound-map=")
		elif a.begins_with("--rebound-diff="):
			GameSession.difficulty_version = a.trim_prefix("--rebound-diff=")
	if want == "":
		return
	var dir := MapLibrary.default_maps_dir()
	for a in OS.get_cmdline_args():
		if a.begins_with("--rebound-dir="):
			dir = a.trim_prefix("--rebound-dir=")
	for f in DirAccess.get_files_at(dir):
		if f.to_lower().ends_with(".osz") and f.findn(want) >= 0:
			GameSession.osz_path = dir.path_join(f)
			return


## Spielzeit (Wertung): Audio oder Ersatzuhr.
func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - maxf(1000.0, ReboundFlight.lead_in_ms(_first_t, float(Settings.rebound_drop_ms), 0.0))


func _visual_ms() -> float:
	if _use_audio:
		return SyncClock.visual_time_ms()
	return _time_ms()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build_bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.color = UiTheme.BG
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	add_child(MapBackdrop.create(OszImporter.load_background_texture(GameSession.osz_path, _beatmap)))
	# Weiche Vignette: Mitte offen, Raender dunkel (Platz fuer die HUD-Werte).
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(UiTheme.BG, 0.0), Color(UiTheme.BG, 0.0), Color(UiTheme.BG, 0.72)])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.52)
	gt.fill_to = Vector2(1.0, 0.52)
	gt.width = 256
	gt.height = 256
	var vig := TextureRect.new()
	vig.texture = gt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)


func _tabular_font(ref: Control) -> Font:
	var fv := FontVariation.new()
	fv.base_font = ref.get_theme_default_font() if ref.get_theme_default_font() != null else ThemeDB.fallback_font
	fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return fv


func _corner_label(text: String, size_px: int, col: Color, tabular: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	if tabular:
		l.add_theme_font_override("font", _tabular_font(l))
	_shadow(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


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



func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_song_len_ms = maxf(_beatmap.duration_ms(), 1.0)
	var title := _corner_label("%s — %s  ·  %s" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()],
			14, Color(0.78, 0.82, 0.92))
	title.position = Vector2(24, 14)
	title.modulate.a = 0.75
	_hud.add_child(title)
	var tag := _corner_label(tr("REBOUND"), 11, Color(UiTheme.ACCENT, 0.85))
	tag.add_theme_font_override("font", UiTheme.heading_font(3))
	tag.position = Vector2(24, 34)
	_hud.add_child(tag)
	var ttw := create_tween()
	ttw.tween_interval(8.0)
	ttw.tween_property(title, "modulate:a", 0.35, 1.5)

	_time_label = _corner_label("", 14, Color(0.7, 0.74, 0.85, 0.85), true)
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.offset_left = -240
	_time_label.offset_right = -20
	_time_label.offset_top = 14
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	# Wie Mania: links Rang + Genauigkeit, rechts Punkte + Fehler, mittig Kombo.
	var left := _stat_column(Vector2(0.085, 0.42))
	_grade_label = _stat_block(left, "RANG", 26)
	_acc_label = _stat_block(left, "GENAUIGKEIT", 28)
	var right := _stat_column(Vector2(0.915, 0.42))
	_score_label = _stat_block(right, "PUNKTE", 30)
	_miss_label = _stat_block(right, "FEHLER", 24)

	_hp_bar = HpBar.new()
	_hp_bar.label_text = "HP"
	_hud.add_child(_hp_bar)
	_hp_bar.setup(UiTheme.ACCENT)
	_hp_bar.anchor_left = 0.5
	_hp_bar.anchor_right = 0.5
	_hp_bar.offset_left = -160
	_hp_bar.offset_right = 160
	_hp_bar.offset_top = 10
	_hp_bar.offset_bottom = 34

	_err_bar = HitErrorBar.new()
	_hud.add_child(_err_bar)
	_err_bar.setup({"max": core.w_max, "w300": core.w300, "w200": core.w200, "w100": core.w100,
			"w50": core.w50}, 260.0)

	_judge_disp = JudgeDisplay.new()
	_hud.add_child(_judge_disp)
	_judge_disp.setup(UiTheme.ACCENT)
	_judge_disp.window_300_ms = core.w_max
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


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
	# Wertung und Kombo mittig ueber den Fellen, unter dem hoechsten Gipfel.
	_judge_disp.place(cy + (vs.y * 0.50 - cy) / k)
	# Oben unter der HP-Leiste: unten liegen die Tastenschilder, in der Mitte fliegen die Baelle.
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5, vs.y * 0.075)


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended or _autoplay or _replay or core == null:
		return
	if event is InputEventKey and not event.echo:
		var lane := Settings.lane_for_key(event.keycode)
		if lane >= 0 and lane < 4:
			_press(lane, event.pressed)


func _press(lane: int, down: bool) -> void:
	if get_tree().paused or _countdown_running or _held[lane] == down:
		return
	var t := _time_ms()
	_held[lane] = down
	_view.held[lane] = down
	_recorded.append({"t": t, "lane": lane, "down": down})
	if down:
		_down(lane, t)
	else:
		core.key_up(lane, t)


## Druck ueber die Anti-Mash-Schicht an ManiaCore geben (live, Replay und Bot gleich).
func _down(lane: int, t: float) -> void:
	if AntiMash.wrong_key_check(core, lane, t) >= 0:
		if _view.has_method("on_wrong_key"):
			_view.on_wrong_key(lane)
	core.key_down(lane, t)


## Replays ohne Regel-Marke oder mit anderer Version passen nicht zu den Regeln.
static func replay_current(events: Array) -> bool:
	return AntiMash.replay_current(events)


func _show_old_replay() -> void:
	var l := Label.new()
	l.text = tr("Dieses Replay stammt aus einer älteren Rebound-Version und lässt sich nicht mehr abspielen.")
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 22)
	_hud.add_child(l)
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(3.5, true).timeout
	if is_inside_tree():
		_back_to_browser()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running:
			_toggle_pause(true)
		return
	if event.keycode == KEY_R and Settings.lane_for_key(KEY_R) == -1 and not Lobby.active:
		_restart()
		return
	if event.keycode == KEY_SPACE and not _ended and Settings.lane_for_key(KEY_SPACE) == -1 \
			and _can_skip_intro():
		if Lobby.active and Lobby.in_game:
			Lobby.vote_skip()
		else:
			_do_skip()


func _can_skip_intro() -> bool:
	return _first_t - _time_ms() > 4000.0 and _use_audio


func _do_skip() -> void:
	if _can_skip_intro():
		SyncClock.seek_ms(_first_t - 2500.0)


# ---------------------------------------------------------------------------
# Schleife
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null:
		return
	var t := _time_ms()
	if _autoplay:
		_feed(_plan, t)
	if _replay:
		_feed(GameSession.replay_events, t)
		if GameSession.replay_end_ms >= 0.0 and t >= GameSession.replay_end_ms \
				and _plan_idx >= GameSession.replay_events.size():
			_show_results(core.failed)
			return
	_last_update_t = t
	core.update(t)
	if _ended:
		return
	if _mp_bot:
		_mp_bot_tick(t)
		if _ended:
			return
	_view.t_ms = _visual_ms()
	if Lobby.active and Lobby.in_game:
		_mp_send_cd -= delta
		if _mp_send_cd <= 0.0:
			_mp_send_cd = 0.25
			Lobby.send_score(core.score, core.combo, core.accuracy())
	if core.failed:
		_show_results(true)
		return
	_update_hud()


## Ereignisse {t, lane, down} mit ihren Original-Zeitstempeln einspeisen.
func _feed(evs: Array, t: float) -> void:
	while _plan_idx < evs.size() and float(evs[_plan_idx].t) <= t:
		var ev: Dictionary = evs[_plan_idx]
		_plan_idx += 1
		var lane := int(ev.lane)
		if lane < 0 or lane > 3:
			continue
		if bool(ev.down):
			_down(lane, float(ev.t))
		else:
			core.key_up(lane, float(ev.t))
		_held[lane] = bool(ev.down)
		_view.held[lane] = bool(ev.down)


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
	if _mp_cut_ms >= 0.0 and t >= _mp_cut_ms + _first_t:
		print("MPREBOUND cut at %d ms" % int(t))
		_show_results(core.failed)


func _update_hud() -> void:
	_judge_disp.set_combo(core.combo)
	var s: Dictionary = core.stats()
	var judged := int(s.n_max) + int(s.n300) + int(s.n200) + int(s.n100) + int(s.n50) + int(s.n_miss)
	if judged == 0:
		_grade_label.text = "-"
		_grade_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		_acc_label.text = UiTheme.fmt_pct(100.0)
	else:
		var g := str(core.grade())
		_grade_label.text = g
		_grade_label.add_theme_color_override("font_color", GRADE_COLOR.get(g, Color.WHITE))
		_acc_label.text = UiTheme.fmt_pct(core.accuracy() * 100.0)
	_score_label.text = PauseMenu.fmt_int(int(s.score))
	_miss_label.text = str(int(s.n_miss))
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.anchor_right = clampf(t / _song_len_ms, 0.0, 1.0)
	_hp_bar.set_hp(core.hp)


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


# ---------------------------------------------------------------------------
# Ereignisse des Cores
# ---------------------------------------------------------------------------

func _on_hold_started(index: int, quality: int) -> void:
	_view.on_hold_start(index, quality)
	var dt := core.hold_head_dt(index)
	_hold_head_dt[index] = dt
	_judge_disp.show_judge(quality, dt)
	_err_bar.add_hit(dt)
	_hit_offsets.append(dt)


func _on_note_judged(index: int, result: Dictionary) -> void:
	var q := int(result.get("quality", 5))
	var hold_end := bool(result.get("hold_end", false))
	_view.on_judged(index, result)
	if q == ManiaCore.Quality.MISS:
		_hp_bar.flash_miss()
	var off: float = 0.0 if hold_end else float(result.get("dt", 0.0))
	_judge_disp.show_judge(q, off)
	if q != ManiaCore.Quality.MISS and result.has("dt") and not hold_end:
		var dt := float(result.dt)
		_err_bar.add_hit(dt)
		_hit_offsets.append(dt)
	_acc_trace.append(core.accuracy())
	if hold_end:
		if bool(result.get("held", false)):
			_hold_ok += 1
		else:
			_hold_drop += 1
	var dt2 := NAN
	if result.has("dt"):
		dt2 = float(result.dt)
	elif _hold_head_dt.has(index):
		dt2 = float(_hold_head_dt[index])
	if q == ManiaCore.Quality.MISS and not hold_end:
		dt2 = NAN
	_judge_log.append(Vector4(float(_beatmap.hit_objects[index].time),
			float(result.get("column", 0)), float(q), dt2))


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
			"score": core.score,
			"acc": core.accuracy() * 100.0,
			"difficulty": _beatmap.version_name(),
			"length_ms": _song_len_ms,
		})
		get_tree().paused = true
		SyncClock.pause()
		_release_all()
	else:
		if _pause_menu != null and _pause_menu.visible:
			_pause_menu.close()
		_resume_with_countdown()


## Beim Pausieren gehaltene Tasten sauber loslassen.
func _release_all() -> void:
	if _autoplay or _replay:
		return
	var t := _time_ms()
	for k in 4:
		if _held[k]:
			_held[k] = false
			_view.held[k] = false
			_recorded.append({"t": t, "lane": k, "down": false})
			core.key_up(k, t)


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


func _show_results(is_fail: bool) -> void:
	if _ended:
		return
	_ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	var s: Dictionary = core.stats()
	s["failed"] = is_fail or bool(s.get("failed", false))
	s["unranked"] = false
	s["pp"] = -1.0
	s["mode"] = MODE
	s["stars"] = GameSession.stars
	var new_best := false
	var prev_best = null
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		prev_best = save.get("previous", {})
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
		ReboundReplay.save(GameSession.osz_path, _beatmap.version_name(), _recorded, {
			"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
			"date": Time.get_datetime_string_from_system(), "mods": GameSession.mods.duplicate(),
			"end_ms": int(_last_update_t),
		})
		if not is_fail:
			_submit_online(s)
	if Lobby.active and Lobby.in_game:
		Lobby.send_score(int(s.score), int(s.max_combo), float(s.accuracy))
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace, _hold_ok, _hold_drop, s.failed))
	_view.visible = false
	for ch in _hud.get_children():
		if ch is CanvasItem:
			ch.visible = false
	var rs := ResultsScreen.new()
	_hud.add_child(rs)
	_results = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	var data := {
		"is_fail": is_fail, "s": s, "pp": -1.0, "unranked": false, "new_best": new_best,
		"title": _beatmap.title(), "artist": _beatmap.artist(), "version": _beatmap.version_name(),
		"cover_path": "", "offsets": _hit_offsets, "player": Settings.profile_name,
		"date": Time.get_datetime_string_from_system(), "allow_retry": not Lobby.active,
		"can_replay": _replay or _recorded.size() > 1, "is_replay": _replay,
		"lobby": Lobby.active, "trace": _acc_trace, "h_ok": _hold_ok, "h_drop": _hold_drop,
		"notes_total": _beatmap.hit_objects.size(), "judge_log": _judge_log,
		"length_ms": float(_beatmap.hit_objects.back().end_time()),
	}
	if prev_best != null:
		data["previous_best"] = prev_best
	if is_fail:
		data["fail_ms"] = maxf(_last_update_t, 0.0)
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if cover != null:
		data["cover"] = cover
	if Lobby.active:
		var me := multiplayer.get_unique_id()
		data["my_id"] = me
		if Lobby.players.has(me):
			data["final"] = Lobby.players[me].get("final", {})
	rs.show_results(data)
	_relabel_badge(rs)
	if OS.get_cmdline_args().has("--shot-results"):
		_capture_results_shot()
	if _mp_bot:
		print("MPORBIT final score=%d acc=%.4f combo=%d failed=%s live_seen=%s" % [
			int(s.score), float(s.accuracy), int(s.get("max_combo", 0)), str(s.failed), str(_mp_live_seen)])
		var back_s := 1.5
		for a in OS.get_cmdline_args():
			if a.begins_with("--mp-back="):
				back_s = clampf(a.trim_prefix("--mp-back=").to_float(), 0.0, 60.0)
		await get_tree().create_timer(back_s, true).timeout
		if is_inside_tree():
			_back_to_browser()


## Modus-Abzeichen im Kopf des Endbilds: ResultsScreen kennt nur Mania/Orbit und
## schreibt "MANIA 4K"; hier auf "REBOUND" umbenennen (bis ScoreStore.mode_label es kann).
func _relabel_badge(n: Node) -> void:
	for ch in n.get_children():
		if ch is Label and (ch as Label).text == ScoreStore.mode_label("").to_upper():
			(ch as Label).text = tr("REBOUND")
		else:
			_relabel_badge(ch)


func _on_results_replay() -> void:
	if _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
	elif _recorded.size() > 1:
		GameSession.is_replay = true
		GameSession.replay_events = _recorded.duplicate()
		GameSession.replay_mode = MODE
		GameSession.replay_end_ms = float(int(_last_update_t))
	else:
		return
	_restart()


func _submit_online(s: Dictionary) -> void:
	var api: OnlineApi = GameSession.online
	if api == null or not api.enabled() or not api.logged_in():
		return
	var meta := OnlineApi.meta_from_beatmap(_beatmap, GameSession.osz_path,
		GameSession.osu_filename, float(s.get("stars", -1.0)))
	meta["total_notes"] = _beatmap.hit_objects.size()
	var res := s.duplicate()
	res["date"] = Time.get_datetime_string_from_system(true)
	api.submit(res, meta, MODE)


# ---------------------------------------------------------------------------
# Shots (Harness)
# ---------------------------------------------------------------------------

func _shot_path(def: String) -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir().path_join(def)


func _save_shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT gespeichert: " + path)


## Zeitpunkt fuer --shot-at: Zahl (ms) oder calm / stream / jack / hold / chord.
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	var objs := _beatmap.hit_objects
	var best := -1.0
	var at := def
	if v == "stream":
		# Dichtestes 800-ms-Fenster (alle Spalten).
		var j0 := 0
		for i in objs.size():
			while objs[i].time - objs[j0].time > 800.0:
				j0 += 1
			if objs[j0].time >= 6000.0 and float(i - j0) > best:
				best = float(i - j0)
				at = objs[j0].time + 500.0
		return at
	if v == "calm":
		# Laengste Luft-Pause in einer Spalte (hoher Bogen), Ball im Gipfel.
		for c in flight.columns:
			for s in flight.segs[c]:
				var sg := s as ReboundFlight.Seg
				if not sg.fall and sg.t1 > 8000.0 and sg.dur() > best:
					best = sg.dur()
					at = sg.t0 + sg.dur() * 0.5
		return at
	if v == "jack":
		# Laengste schnelle Folge in einer Spalte (Abstand < 170 ms).
		for c in flight.columns:
			var run := 0
			var arr: Array = flight.segs[c]
			for i in range(1, arr.size()):
				var sg := arr[i] as ReboundFlight.Seg
				run = run + 1 if (not sg.fall and sg.dur() < 170.0) else 0
				if sg.t1 > 8000.0 and float(run) > best:
					best = float(run)
					at = sg.t1 - 120.0
		return at
	if v == "chord":
		for i in range(1, objs.size()):
			if objs[i].time > 8000.0 and absf(objs[i].time - objs[i - 1].time) < 2.0 \
					and objs.size() > i + 2 and absf(objs[i + 1].time - objs[i].time) < 2.0:
				return objs[i].time - 330.0
		return def
	for o in objs:
		var n := o as ManiaNote
		if v == "hold" and n.is_hold and n.time > 8000.0 and n.end_time() - n.time >= 600.0:
			return n.time + (n.end_time() - n.time) * 0.55
	return def


func _capture_shot() -> void:
	core.no_fail = true
	var target := _first_t - 300.0
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-at="):
			target = _shot_target(a.trim_prefix("--shot-at="), target)
	if OS.get_cmdline_args().has("--shot-pause"):
		await _wait_until(target)
		_toggle_pause(true)
		await get_tree().create_timer(0.6, true).timeout
		await RenderingServer.frame_post_draw
		_save_shot(_shot_path("rebound_pause.png"))
		get_tree().quit(0)
		return
	if OS.get_cmdline_args().has("--shot-results"):
		var has_at := false
		for a in OS.get_cmdline_args():
			has_at = has_at or a.begins_with("--shot-at=")
		if OS.get_cmdline_args().has("--shot-fail"):
			core.no_fail = false
		var t_end := target if has_at else float(_beatmap.hit_objects.back().end_time()) + 1000.0
		var t := _time_ms()
		while t < t_end and not core.failed:
			_feed(_plan, t)
			_last_update_t = t
			core.update(t)
			t += 16.0
		_view.t_ms = t
		_show_results(core.failed)
		return
	if target - _time_ms() > 4000.0 and _use_audio:
		# Vorspulen: Ereignisse bis kurz vor dem Ziel sofort einspeisen (deterministisch).
		var cut := target - 2500.0
		while _plan_idx < _plan.size() and float(_plan[_plan_idx].t) <= cut:
			var ev: Dictionary = _plan[_plan_idx]
			if bool(ev.down):
				core.key_down(int(ev.lane), float(ev.t))
			else:
				core.key_up(int(ev.lane), float(ev.t))
			_plan_idx += 1
		core.update(cut)
		SyncClock.seek_ms(cut)
	for a in OS.get_cmdline_args():
		if a.begins_with("--movie-len="):
			if OS.get_cmdline_args().has("--nohud"):
				_hud.visible = false
			print("MOVIE_START frame=%d" % Engine.get_process_frames())
			await get_tree().create_timer(a.trim_prefix("--movie-len=").to_float(), true).timeout
			get_tree().quit(0)
			return
	await _wait_until(target)
	if not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	_save_shot(_shot_path("rebound.png"))
	get_tree().quit(0)


func _wait_until(target: float) -> void:
	var guard := 0
	while _time_ms() < target and guard < 3600:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return


func _capture_results_shot() -> void:
	await get_tree().create_timer(1.0, true).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_save_shot(_shot_path("rebound_results.png"))
	get_tree().quit(0)
