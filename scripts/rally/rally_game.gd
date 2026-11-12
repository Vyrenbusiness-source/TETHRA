extends Control

## Rally-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause, Fail,
## Ende -> Results, Score speichern unter Modus "rally", Replays, Multiplayer).
## Logik: RallyChart/RallyCore, Darstellung: RallyView. Szene: res://scenes/rally.tscn
## mit GameSession.osz_path/difficulty_version.
##
## Tasten: 4 Zonen = Mania-4K-Tasten (Settings.key_lanes, Standard D F J K). Zwei
## Zonentasten zugleich = Schmetterball, halten = Aufladen. Regeln: docs/modes/rally.md.
## CLI: --autoplay, --auto-miss=<n>, --auto-jitter=<ms>, --auto-seed=<n>,
## --rally-map=<Teil des osz-Namens> [--rally-diff=<Version>], --shot
## --shot-at=<ms|lob|stream|smash|charge|hold> --shot-out=<png>, --shot-results
## [--shot-fail], --shot-pause, --shot-intro, --mp-bot, --mp-cut=<s>, --mp-back=<s>.

const MODE := "rally"
const JUDGE_SCALE := 0.5
const ZONE_COLS := [Color(0.52, 0.74, 0.92), Color(0.55, 0.85, 0.62), Color(0.95, 0.80, 0.35),
	Color(0.95, 0.52, 0.30)]
const SMASH_COL := Color(0.93, 0.90, 0.85)
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.55, 0.85, 0.55),
	"B": Color(0.50, 0.70, 0.95), "C": Color(0.75, 0.58, 0.95), "D": Color(0.90, 0.50, 0.45),
}

var core: RallyCore
var shots: Array[RallyChart.Shot] = []
var _beatmap: Beatmap
var _use_audio := false
var _debug_start_usec := 0
var _debug_running := false
var _ended := false
var _autoplay := false
var _countdown_running := false
var _song_len_ms := 1.0
var _held := [[false, false], [false, false], [false, false], [false, false]]
var _zones := 3
var _view: RallyView
var _hud: CanvasLayer
var _bg_tex: TextureRect
var _judge_disp: JudgeDisplay
var _err_bar: HitErrorBar
var _hp_bar: HpBar
var _acc_label: Label
var _score_label: Label
var _miss_label: Label
var _grade_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _legend: Control
var _hint: Label
var _hint_tween: Tween
var _pause_menu: PauseMenu
var _results: RallyResults
var _sound: RallySound
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()
var _plan: Array = []
var _plan_idx := 0
var _replay := false
var _replay_events: Array = []
var _replay_idx := 0
var _replay_end_ms := -1.0
var _last_update_t := 0.0
var _snd_t := -INF
var _smashes := 0
var _charges := 0
var _mp_send_cd := 0.0
var _mp_bot := false
var _mp_cut_ms := -1.0
var _mp_skip_voted := false
var _mp_live_seen: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	_replay = GameSession.is_replay and GameSession.replay_mode == MODE \
			and RallyCore.replay_ok(GameSession.replay_events)
	var old_replay := GameSession.is_replay and not _replay
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
	core = RallyCore.new()
	core.setup(shots, _beatmap.od(), _beatmap.hp())
	core.set_replay_mode(not _replay)
	core.shot_judged.connect(_on_shot_judged)
	core.charge_started.connect(_on_charge_started)
	core.press_ignored.connect(_on_press_ignored)
	core.finished.connect(func(_s): _show_results(false))
	if _replay:
		_replay_events = GameSession.replay_events
		_replay_end_ms = GameSession.replay_end_ms
	if _autoplay:
		_plan = RallyCore.bot_plan(shots, seed, jitter, skip)
	_build_bg()
	_view = RallyView.new()
	add_child(_view)
	_view.setup(shots, core)
	_view.key_labels = _zone_labels()
	_sound = RallySound.new()
	add_child(_sound)
	_build_hud()
	_update_hud()
	if old_replay:
		_flash_hint(tr("Altes Replay (Rally v1) passt nicht zu den neuen Regeln"))
	if Lobby.active and Lobby.in_game:
		Lobby.skip_now.connect(_do_skip)
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if _mp_bot:
		print("MPORBIT start: %d Schlaege, autoplay=%s" % [shots.size(), _autoplay])
	if DisplayServer.get_name() == "headless" and not _mp_bot:
		print("=== Rally Smoke: %d Schlaege ===" % shots.size())
		get_tree().quit(0)
		return
	if OS.get_cmdline_args().has("--shot"):
		_capture_shot()
	else:
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)
		if OS.get_cmdline_args().has("--shot-intro"):
			await get_tree().create_timer(0.45, true).timeout
			await RenderingServer.frame_post_draw
			_save_shot(_shot_path("rally_intro.png"))
			get_tree().quit(0)


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
	_zones = RallyCore.replay_zones(GameSession.replay_events) if (GameSession.is_replay and GameSession.replay_mode == MODE and RallyCore.replay_ok(GameSession.replay_events)) else Settings.rally_zones
	shots = RallyChart.build(_beatmap, float(Settings.rally_flight_ms), _zones)
	if shots.is_empty():
		return false
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		var lead := _beatmap.audio_lead_in()
		var need := float(Settings.rally_flight_ms) + 900.0
		if shots[0].t + lead < need:
			lead = need - shots[0].t
		SyncClock.play(stream, lead)
		_use_audio = true
	return true


## Debug/Shots: --rally-map=<Teil des osz-Namens> [--rally-diff=<Version>].
func _cli_pick() -> void:
	var want := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--rally-map="):
			want = a.trim_prefix("--rally-map=")
		elif a.begins_with("--rally-diff="):
			GameSession.difficulty_version = a.trim_prefix("--rally-diff=")
	if want == "":
		return
	var dir := MapLibrary.default_maps_dir()
	for a in OS.get_cmdline_args():
		if a.begins_with("--rally-dir="):
			dir = a.trim_prefix("--rally-dir=")
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
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - 1000.0


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
	var tex := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if tex != null:
		add_child(MapBackdrop.create(tex))
	# Weiche Vignette: Mitte offen, Raender dunkel (Platz fuer die HUD-Werte).
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(UiTheme.BG, 0.0), Color(UiTheme.BG, 0.0), Color(UiTheme.BG, 0.78)])
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
	var tag := _corner_label(tr("RALLY"), 11, Color(RallyView.COL_A, 0.85))
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

	# Wie Mania: links Rang + Genauigkeit, rechts Punkte + Fehler, mittig unten Kombo.
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

	_build_legend()
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", RallyView.COL_MISS)
	_shadow(_hint)
	_hint.modulate.a = 0.0
	_hud.add_child(_hint)
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


## Tastenbeschriftung der 4 Zonen (Mania-4K-Belegung).
func _zone_labels() -> Array:
	var out := []
	var keys := Settings.rally_keys(_zones)
	for k in _zones:
		out.append(UiTheme.key_short(keys[k]))
	return out


func _build_legend() -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 30)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_legend = box
	_hud.add_child(box)
	var labels := _zone_labels()
	var items := [
		[ZONE_COLS[0], tr("Zone 1-4: Tasten %s") % " ".join(labels)],
		[SMASH_COL, tr("Weiß umrandet: beide Zonentasten")],
		[Color(0.78, 0.82, 0.92), tr("Gestrichelter Ring: halten, dann loslassen")],
	]
	for it in items:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = it[0]
		dot.draw.connect(func(): dot.draw_circle(dot.size * 0.5, 6.5, col))
		item.add_child(dot)
		var l := _corner_label(str(it[1]), 14, col.lerp(Color.WHITE, 0.4))
		item.add_child(l)
		box.add_child(item)


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
	_judge_disp.place(cy + (vs.y * 0.915 - cy) / k)
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5, vs.y - _err_bar.size.y - 10.0)
	_legend.size = Vector2(vs.x, 24)
	_legend.position = Vector2(0, vs.y * 0.885)
	_hint.size = Vector2(vs.x, 24)
	_hint.position = Vector2(0, vs.y * 0.125)


func _flash_hint(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text
	_hint.modulate.a = 1.0
	if _hint_tween != null:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(0.35)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.35)


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended or _autoplay or _replay or core == null:
		return
	if event is InputEventKey and not event.echo:
		var zone := Settings.rally_zone_for_key(event.keycode, _zones)
		if zone >= 0:
			_press(zone, 1, event.pressed)


## Zonentaste ueber eine Quelle (0 Maus, 1 Tastatur): der Core sieht nur den
## Uebergang "keine Quelle" <-> "mindestens eine".
func _press(key: int, source: int, down: bool) -> void:
	if get_tree().paused or _countdown_running:
		return
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	if now == was:
		return
	var t := _time_ms()
	if now:
		core.key_down(key, t)
	else:
		core.key_up(key, t)
	_sync_held_view()


func _sync_held_view() -> void:
	for k in RallyCore.ZONES:
		if k < _view.held.size():
			_view.held[k] = _held[k][0] or _held[k][1]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running:
			_toggle_pause(true)
		return
	if event.keycode == KEY_R and Settings.rally_zone_for_key(KEY_R, _zones) == -1 and not Lobby.active:
		_restart()
		return
	if event.keycode == KEY_SPACE and not _ended and Settings.rally_zone_for_key(KEY_SPACE, _zones) == -1 \
			and _can_skip_intro():
		if Lobby.active and Lobby.in_game:
			Lobby.vote_skip()
		else:
			_do_skip()


func _can_skip_intro() -> bool:
	return not shots.is_empty() and shots[0].launch - _time_ms() > 4000.0 and _use_audio


func _do_skip() -> void:
	if _can_skip_intro():
		SyncClock.seek_ms(shots[0].launch - 2500.0)


# ---------------------------------------------------------------------------
# Schleife
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null:
		return
	var t := _time_ms()
	if _autoplay:
		_feed_plan(t)
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
	var vt := _visual_ms()
	_view.t_ms = vt
	_play_flight_sounds(vt)
	if Lobby.active and Lobby.in_game:
		_mp_send_cd -= delta
		if _mp_send_cd <= 0.0:
			_mp_send_cd = 0.25
			Lobby.send_score(core.score, core.combo, core.accuracy())
	if _legend != null and _legend.visible:
		var lead := shots[0].launch - t
		_legend.modulate.a = clampf((lead + 1200.0) / 900.0, 0.0, 1.0) if t < shots[0].t else 0.0
		if t > shots[0].t + 300.0:
			_legend.visible = false
	if core.failed:
		_show_results(true)
		return
	_update_hud()


func _feed_plan(t: float) -> void:
	while _plan_idx < _plan.size() and float(_plan[_plan_idx][0]) <= t:
		var ev: Array = _plan[_plan_idx]
		core.feed(ev)
		_set_held_view(int(ev[1]))
		_plan_idx += 1


func _set_held_view(code: int) -> void:
	if code < RallyCore.EV_DOWN or code >= RallyCore.EV_RULES:
		return
	var z := (code - RallyCore.EV_UP) if code >= RallyCore.EV_UP else (code - RallyCore.EV_DOWN)
	if z >= 0 and z < _view.held.size():
		_view.held[z] = code < RallyCore.EV_UP


func _feed_replay(t: float) -> void:
	while _replay_idx < _replay_events.size() and float(_replay_events[_replay_idx][0]) <= t:
		var ev: Array = _replay_events[_replay_idx]
		_replay_idx += 1
		core.apply_event(ev)
		_set_held_view(int(ev[1]))
	if _replay_end_ms >= 0.0 and t >= _replay_end_ms and _replay_idx >= _replay_events.size():
		_show_results(core.failed)


## Gegnerschlag und Tischaufpralle (leise) zur Flugbahn, nie zur Wertung.
func _play_flight_sounds(t: float) -> void:
	if _snd_t == -INF or t - _snd_t > 300.0 or t < _snd_t:
		_snd_t = t
		return
	var j := RallyChart.first_at_or_after(shots, t - 600.0 - float(Settings.rally_flight_ms))
	for k in range(maxi(j - 1, 0), mini(j + 4, shots.size())):
		var s := shots[k]
		var hit: bool = core.is_judged(k) and int(core.result_of(k).get("quality", 5)) != 5
		if s.launch > _snd_t and s.launch <= t:
			_sound.play_opp()
		var tb := s.launch + (s.t - s.launch) * 0.72
		if tb > _snd_t and tb <= t:
			_sound.play_bounce()
		if hit and s.t + 300.0 > _snd_t and s.t + 300.0 <= t:
			_sound.play_bounce()
	_snd_t = t


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
	if _mp_cut_ms >= 0.0 and t >= _mp_cut_ms + shots[0].t:
		print("MPRALLY cut at %d ms" % int(t))
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

func _on_shot_judged(index: int, result: Dictionary) -> void:
	var q := int(result.get("quality", 5))
	var s := shots[index]
	_view.on_judged(index, result)
	var hold_end := bool(result.get("hold_end", false))
	if hold_end:
		_sound.stop_charge()
	if q == 5:
		_sound.play_miss()
		_hp_bar.flash_miss()
	elif hold_end:
		_sound.play_release()
	elif s.smash:
		_sound.play_smash()
		_smashes += 1
	else:
		_sound.play_hit(int(s.zones[0]), q)
	var off: float = 0.0 if hold_end else float(result.get("dt", 0.0))
	_judge_disp.show_judge(q, off)
	if q != 5 and result.has("dt") and not hold_end:
		var dt := float(result.dt)
		_err_bar.add_hit(dt)
		_hit_offsets.append(dt)
	_acc_trace.append(core.accuracy())
	if q != 5 and hold_end:
		_charges += 1


func _on_charge_started(index: int, quality: int) -> void:
	_view.on_charge(index)
	_sound.play_hit(int(shots[index].zones[0]), quality)
	_sound.start_charge()
	var dt := float(core.result_of(index).get("dt", 0.0))
	_judge_disp.show_judge(quality, dt)
	_err_bar.add_hit(dt)
	_hit_offsets.append(dt)


func _on_press_ignored(_key: int, reason: String) -> void:
	if reason == "KEY":
		_flash_hint(tr("andere Zone"))


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


## Beim Pausieren gehaltene Tasten sauber loslassen (kein haengendes Aufladen).
func _release_all() -> void:
	var t := _time_ms()
	for k in RallyCore.ZONES:
		var was: bool = _held[k][0] or _held[k][1]
		_held[k] = [false, false]
		if was and not _autoplay and not _replay:
			core.key_up(k, t)
	_sync_held_view()
	_sound.stop_charge()


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
	_sound.stop_charge()
	var s: Dictionary = core.stats()
	s["failed"] = is_fail or bool(s.get("failed", false))
	s["unranked"] = false
	s["pp"] = -1.0
	s["mode"] = MODE
	s["stars"] = RallyChart.stars(shots, _zones)
	var new_best := false
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
		_save_replay(s)
		if not is_fail:
			_submit_online(s)
	if Lobby.active and Lobby.in_game:
		Lobby.send_score(int(s.score), int(s.max_combo), float(s.accuracy))
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace, 0, 0, s.failed))
	var rs := RallyResults.new()
	_view.visible = false
	for ch in _hud.get_children():
		if ch is CanvasItem:
			ch.visible = false
	_hud.add_child(rs)
	_results = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	rs.show_results({
		"is_fail": is_fail, "s": s, "log": _result_log(), "w50": core.w50, "w_max": core.w_max,
		"new_best": new_best, "title": _beatmap.title(), "artist": _beatmap.artist(),
		"version": _beatmap.version_name(), "allow_retry": not Lobby.active,
		"can_replay": not Lobby.active and (_replay or core.replay_log.size() > 1),
		"smashes": _smashes, "charges": _charges,
	})
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


## Ein Eintrag je gewertetem Schlag fuer das Endbild (RallyResults.entry).
func _result_log() -> Array:
	var out := []
	for i in shots.size():
		if not core.is_judged(i):
			continue
		var sh := shots[i]
		out.append(RallyResults.entry(sh.t, int(sh.zones[0]), sh.smash, sh.is_charge(), core.result_of(i)))
	return out


func _save_replay(s: Dictionary) -> void:
	if core.replay_log.size() <= 1:
		return
	RallyCore.save_replay(GameSession.osz_path, _beatmap.version_name(), core.replay_log, {
		"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
		"date": Time.get_datetime_string_from_system(), "mods": GameSession.mods.duplicate(),
		"end_ms": int(_last_update_t), "zones": _zones,
	})


func _on_results_replay() -> void:
	if _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
	elif core.replay_log.size() > 1:
		GameSession.is_replay = true
		GameSession.replay_events = core.replay_log.duplicate()
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
	meta["total_notes"] = shots.size()
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


## Zeitpunkt fuer --shot-at: Zahl (ms) oder lob / stream / smash / charge / hold.
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	var best := -1.0
	var at := def
	if v == "lob":
		# Laengster Ballwechsel (ohne Pause): Ball im hoechsten Punkt.
		for j in range(1, shots.size()):
			var gap := shots[j].t - shots[j - 1].end
			if shots[j].t > 8000.0 and gap < RallyChart.BREAK_MS and gap > best:
				best = gap
				at = shots[j].launch + (shots[j].t - shots[j].launch) * 0.40
		return at
	if v == "stream":
		var j0 := 0
		for i in shots.size():
			while shots[i].t - shots[j0].t > 800.0:
				j0 += 1
			if shots[j0].t >= 8000.0 and float(i - j0) > best:
				best = float(i - j0)
				at = shots[j0].t + 160.0
		return at
	for i in shots.size():
		var s := shots[i]
		if s.t < 8000.0:
			continue
		if v == "smash" and s.smash:
			return s.t - 70.0
		if v == "charge" and s.is_charge() and s.end - s.t >= 500.0:
			return s.t - 220.0
		if v == "hold" and s.is_charge() and s.end - s.t >= 500.0:
			return s.t + (s.end - s.t) * 0.6
	return def


func _capture_shot() -> void:
	core.no_fail = true
	var target := shots[mini(6, shots.size() - 1)].t - 200.0
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-at="):
			target = _shot_target(a.trim_prefix("--shot-at="), target)
	if OS.get_cmdline_args().has("--shot-pause"):
		await _wait_until(target)
		_toggle_pause(true)
		await get_tree().create_timer(0.6, true).timeout
		await RenderingServer.frame_post_draw
		_save_shot(_shot_path("rally_pause.png"))
		get_tree().quit(0)
		return
	if OS.get_cmdline_args().has("--shot-results"):
		var has_at := false
		for a in OS.get_cmdline_args():
			has_at = has_at or a.begins_with("--shot-at=")
		if OS.get_cmdline_args().has("--shot-fail"):
			core.no_fail = false
		var t_end := target if has_at else shots[-1].end + 1000.0
		var t := _time_ms()
		while t < t_end and not core.failed:
			_feed_plan(t)
			_last_update_t = t
			core.update(t)
			t += 16.0
		_view.t_ms = t
		_show_results(core.failed)
		return
	if target - _time_ms() > 4000.0 and _use_audio:
		# Vorspulen: Ereignisse bis kurz vor dem Ziel sofort einspeisen (deterministisch).
		var cut := target - 2500.0
		while _plan_idx < _plan.size() and float(_plan[_plan_idx][0]) <= cut:
			core.feed(_plan[_plan_idx])
			_plan_idx += 1
		core.update(cut)
		SyncClock.seek_ms(cut)
		_snd_t = -INF
	for a in OS.get_cmdline_args():
		if a.begins_with("--movie-len="):
			# Debug (Demo-Videos): Filmbeginn markieren, nach <s> Film-Sekunden beenden.
			print("MOVIE_START frame=%d" % Engine.get_process_frames())
			await get_tree().create_timer(a.trim_prefix("--movie-len=").to_float(), true).timeout
			get_tree().quit(0)
			return
	await _wait_until(target)
	if not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	_save_shot(_shot_path("rally.png"))
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
	_save_shot(_shot_path("rally_results.png"))
	get_tree().quit(0)
