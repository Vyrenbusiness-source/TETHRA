extends Control

## Trace-Modus: Spielablauf (Map laden, Audio + SyncClock, eigene Trace-Tasten,
## Pause/Retry, Ende mit End-Zoom -> Ergebnis, Score unter Modus "trace", Replays,
## Multiplayer). Wertung: ManiaCore unveraendert. Geometrie: TracePath, Zeichnen: TraceView.
## Szene: res://scenes/trace.tscn mit GameSession.osz_path/difficulty_version (nur 4K-Maps).
##
## Tasten: Settings.trace_keys (Standard Pfeile), Spalte 0-3 = links / runter / hoch / rechts.
## Anti-Mash (Regeln 2): siehe TraceRules.press(), Replay meta rules = 2.
## CLI: --autoplay, --trace-map=<Teil des osz-Namens> [--trace-diff=<Version>]
## [--trace-dir=<Ordner>], --shot --shot-at=<ms|stream|hold|chord|hairpin|calm|kiai|end>
## --shot-out=<png>, --shot-results, --shot-pause, --mp-bot, --mp-cut=<s>, --mp-back=<s>.

const MODE := "trace"
const RULES := 2              ## Replay meta rules: 2 = mit Anti-Mash (falscher Knick)
const MODS_PATH := "res://scripts/trace/trace_mods.gd"
const PICTURE_PATH := "res://scripts/trace/trace_picture.gd"
## Gesetzt, wenn die naechste Runde ein frisch gespieltes Replay (aktuelle Regeln) ist.
static var fresh_replay := false
const JUDGE_SCALE := 0.5
const END_ZOOM_S := 2.2
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.55, 0.85, 0.55),
	"B": Color(0.50, 0.70, 0.95), "C": Color(0.75, 0.58, 0.95), "D": Color(0.90, 0.50, 0.45),
}

var core: ManiaCore
var _wrong_label: Label
var _wrong_tween: Tween
var _old_replay := false
var _mods: Dictionary = {}
var path: TracePath
var _beatmap: Beatmap
var _use_audio := false
var _debug_start_usec := 0
var _debug_running := false
var _ended := false
var _autoplay := false
var _countdown_running := false
var _song_len_ms := 1.0
var _view: TraceView
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
var _legend: Control
var _pause_menu: PauseMenu
var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()
var _judge_log: Array = []
var _hold_ok := 0
var _hold_drop := 0
var _hold_head_dt := {}
var _recorded: Array = []
var _lane_held := [false, false, false, false]
var _auto_idx := 0
var _auto_release: Array[float] = [-1.0, -1.0, -1.0, -1.0]
var _replay := false
var _replay_events: Array = []
var _replay_idx := 0
var _last_update_t := 0.0
var _prev_best = null
var _mp_send_cd := 0.0
var _mp_bot := false
var _mp_cut_ms := -1.0
var _mp_skip_voted := false
var _mp_live_seen: Dictionary = {}
var _finishing := false
var _dbg_seeked := false   # Debug --seek-end: springt kurz vor die letzte Note
var _fin_t0 := 0
var _fin_vt := 0.0
var _shot_mode := false
var _shot_hold := false
var _sim_done := false


## Ansicht des Spiels (QA Vorlauf). Die Spalten sind in _apply_mods schon getauscht, also
## spiegelt die Ansicht nicht nochmal (TraceMods.view_mods). Die Kamera, die die Knoten der
## naechsten 600 ms im Bild haelt, sitzt in TraceView selbst (Tutorial und Clips gleich).
class FairView extends TraceView:
	func setup(p: TracePath, c: ManiaCore, colors: Array[Color]) -> void:
		super.setup(p, c, colors)
		mods = TraceMods.view_mods(mods)
		_mirror = false


func _ready() -> void:
	_ensure_translations()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	var args := _args()
	_shot_mode = args.has("--shot")
	_replay = GameSession.is_replay and GameSession.replay_mode == MODE
	if GameSession.is_replay and not _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
	_mp_bot = Lobby.in_round() and args.has("--mp-bot")
	_autoplay = ((args.has("--autoplay") and not Lobby.in_round()) or _mp_bot) and not _replay
	for a in args:
		if a.begins_with("--mp-cut="):
			_mp_cut_ms = maxf(0.0, a.trim_prefix("--mp-cut=").to_float()) * 1000.0
	core = ManiaCore.new()
	core.setup(_beatmap, -1.0, 1.0)
	# SV wirkt in Trace nicht: kein Faktor, kein Badge (TraceMods.strip_foreign).
	core.mods = TraceMods.strip_foreign(core.mods)
	core.mod_mult = ManiaCore.mod_multiplier(core.mods) * _mod_mult()
	core.note_judged.connect(_on_note_judged)
	core.hold_started.connect(_on_hold_started)
	core.finished.connect(_on_finished)
	if _replay:
		_replay_events = GameSession.replay_events
		_old_replay = not fresh_replay and _file_rules() < RULES
		fresh_replay = false
	path = TracePath.from_beatmap(_beatmap, float(Settings.trace_speed))
	_build_bg()
	_view = FairView.new()
	add_child(_view)
	_view.setup(path, core, _note_colors())
	_build_sound()
	_build_hud()
	_update_hud()
	if _old_replay:
		_show_old_replay()
		return
	if Lobby.in_round():
		Lobby.skip_now.connect(_do_skip)
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if _mp_bot:
		print("MPORBIT start: %d Noten, autoplay=%s" % [_beatmap.hit_objects.size(), _autoplay])
	if DisplayServer.get_name() == "headless" and not _mp_bot:
		print("=== Trace Smoke: %d Noten, %d Knoten, %d Haarnadeln ===" % [
			_beatmap.hit_objects.size(), path.knots.size(), path.hairpin_count()])
		get_tree().quit(0)
		return
	if args.has("--shot"):
		_capture_shot()
	else:
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)


static func _args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


## Uebersetzungen aus translations/trace.csv (auch ohne Eintrag in project.godot).
## meta.rules der gespeicherten Replay-Datei (fehlt = 1). Ohne Datei: aktuelle Regeln.
func _file_rules() -> int:
	var data := ReplayStore.load_replay(GameSession.osz_path, _beatmap.version_name(), MODE)
	if data.is_empty():
		return RULES
	return int((data.get("meta", {}) as Dictionary).get("rules", 1))


## Replay mit Regeln 1 (ohne Anti-Mash) passt nicht mehr: Hinweis, zurueck zur Auswahl.
func _show_old_replay() -> void:
	var l := Label.new()
	l.text = tr("Dieses Replay nutzt die alten Trace-Regeln und lässt sich nicht mehr abspielen.")
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 22)
	_hud.add_child(l)
	_ended = true
	SyncClock.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(3.5, true).timeout
	if is_inside_tree():
		_back_to_browser()


static func _ensure_translations() -> void:
	for loc in ["de", "en"]:
		var p := "res://translations/trace.%s.translation" % loc
		if ResourceLoader.exists(p):
			var tr_res := load(p) as Translation
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
	if _beatmap == null or _beatmap.hit_objects.is_empty() or not _beatmap.is_mania() \
			or _beatmap.column_count() != 4:
		return false
	_apply_mods()
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		var first := float(_beatmap.hit_objects[0].time)
		var lead := _beatmap.audio_lead_in()
		lead = TraceRules.lead_in_ms(first, lead)
		SyncClock.play(stream, lead)
		_use_audio = true
	return true


## Score-Multiplikator der Trace-Mods (MR/HD/SS) aus TraceMods, sonst 1.
func _mod_mult() -> float:
	if _mods.is_empty() or not ResourceLoader.exists(MODS_PATH):
		return 1.0
	var m = load(MODS_PATH)
	return float(m.call("mod_multiplier", _mods)) if m != null and m.has_method("mod_multiplier") else 1.0


## Hook trace_mods.gd (nur wenn vorhanden): Mirror & Co. bilden die Notenspalten um.
func _apply_mods() -> void:
	if not ResourceLoader.exists(MODS_PATH):
		return
	var m = load(MODS_PATH)
	if m == null or not m.has_method("map_column") or not m.has_method("from_session"):
		return
	var mods = m.call("from_session")
	_mods = mods
	for o in _beatmap.hit_objects:
		var n := o as ManiaNote
		n.column = clampi(int(m.call("map_column", n.column, mods)), 0, 3)


## Debug/Shots: --trace-map=<Teil des osz-Namens> [--trace-diff=<Version>] [--trace-dir=<Ordner>].
func _cli_pick() -> void:
	var want := ""
	var dir := MapLibrary.default_maps_dir()
	for a in _args():
		if a.begins_with("--trace-map="):
			want = a.trim_prefix("--trace-map=")
		elif a.begins_with("--trace-diff="):
			GameSession.difficulty_version = a.trim_prefix("--trace-diff=")
		elif a.begins_with("--trace-dir="):
			dir = a.trim_prefix("--trace-dir=")
	if want == "":
		return
	for f in DirAccess.get_files_at(dir):
		if f.to_lower().ends_with(".osz") and f.findn(want) >= 0:
			GameSession.osz_path = dir.path_join(f)
			return


## Fadenfarbe je Note: Einstellung "Notenfarben" (Spalten, Takt-Teilung oder Standard).
func _note_colors() -> Array[Color]:
	var out: Array[Color] = []
	var base := NoteColors.preset_colors("standard")
	for o in _beatmap.hit_objects:
		var n := o as ManiaNote
		var col := n.column
		var div := SnapColor.divisor_for(float(n.time), _beatmap.timing_points)
		out.append(NoteColors.color_for(col, n.is_hold, true, base[clampi(col, 0, 3)], div))
	return out


func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - maxf(1000.0, TraceRules.lead_in_ms(_first_ms(), 0.0))


func _visual_ms() -> float:
	if _use_audio:
		return SyncClock.visual_time_ms()
	return _time_ms()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build_bg() -> void:
	var tex := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	add_child(MapBackdrop.create(tex))
	# Ruhiger Grund: Vignette, Mitte offen, Raender dunkel (Platz fuer die HUD-Werte).
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var vig := TextureRect.new()
	vig.texture = gt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _build_sound() -> void:
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	add_child(_miss_player)


func _play_hit(pitch: float) -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01 or _hit_player == null:
		return
	_hit_player.volume_db = linear_to_db(Settings.hitsound_volume) - 7.0
	_hit_player.pitch_scale = pitch
	_hit_player.play()


func _play_miss() -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01 or _miss_player == null:
		return
	_miss_player.volume_db = linear_to_db(Settings.hitsound_volume) - 6.0
	_miss_player.play()


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
	var tag := _corner_label(tr("TRACE"), 11, Color(TraceView.HEAD, 0.85))
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
	_grade_label = _stat_block(left, tr("RANG"), 26)
	_acc_label = _stat_block(left, tr("GENAUIGKEIT"), 28)
	var right := _stat_column(Vector2(0.915, 0.42))
	_score_label = _stat_block(right, tr("PUNKTE"), 30)
	_miss_label = _stat_block(right, tr("FEHLER"), 24)

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
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


## Zeile vor dem ersten Ton: Pfeil je Spalte mit Taste.
func _build_legend() -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 34)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_legend = box
	_hud.add_child(box)
	var base := NoteColors.preset_colors("standard")
	for c in 4:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col: Color = NoteColors.lane_color(true, c) if NoteColors.mode(true) == "lanes" else base[c]
		var d := TracePath.dir_of_col(c)
		dot.draw.connect(func():
			var ctr := dot.size * 0.5
			var perp := Vector2(-d.y, d.x)
			var poly := PackedVector2Array([ctr + d * 9.0, ctr - d * 5.0 + perp * 8.0,
					ctr - d * 0.0, ctr - d * 5.0 - perp * 8.0])
			dot.draw_colored_polygon(poly, col))
		item.add_child(dot)
		var l := _corner_label(UiTheme.key_short(Settings.trace_keys[c]), 15, col.lerp(Color.WHITE, 0.4))
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
	_legend.size = Vector2(vs.x, 26)
	_legend.position = Vector2(0, vs.y * 0.885)


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _ended or _finishing or _autoplay or _replay or core == null:
		return
	if event is InputEventKey and not event.echo:
		var lane := Settings.trace_lane_for_key(event.keycode)
		if lane < 0 or get_tree().paused or _countdown_running:
			return
		var down: bool = event.pressed
		if _lane_held[lane] == down:
			return
		var t := _time_ms()
		_recorded.append({"t": t, "lane": lane, "down": down})
		_lane_held[lane] = down
		if down:
			_press(lane, t)
		else:
			core.key_up(lane, t)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running and not _finishing:
			_toggle_pause(true)
		return
	if event.keycode == KEY_R and Settings.trace_lane_for_key(KEY_R) == -1 and not Lobby.in_round():
		_restart()
		return
	if event.keycode == KEY_SPACE and not _ended and Settings.trace_lane_for_key(KEY_SPACE) == -1 \
			and _can_skip_intro():
		if Lobby.in_round():
			Lobby.vote_skip()
		else:
			_do_skip()


func _first_ms() -> float:
	return float(_beatmap.hit_objects[0].time)


func _can_skip_intro() -> bool:
	return _first_ms() - _time_ms() > 4000.0 and _use_audio


func _do_skip() -> void:
	if _can_skip_intro():
		SyncClock.seek_ms(_first_ms() - 2500.0)


# ---------------------------------------------------------------------------
# Schleife
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null or _shot_hold:
		return
	if _finishing:
		_tick_finish()
		return
	if not _dbg_seeked and _args().has("--seek-end"):
		_dbg_seeked = true
		SyncClock.seek_ms(float(_beatmap.hit_objects[-1].time) - 4000.0)
	var t := _time_ms()
	if _autoplay:
		_run_autoplay(t)
	if _replay:
		_feed_replay(t)
	_last_update_t = t
	core.update(t)
	if _ended or _finishing:
		return
	if _mp_bot:
		_mp_bot_tick(t)
		if _ended:
			return
	_view.t_ms = _visual_ms()
	_view.queue_redraw()
	if Lobby.in_round():
		_mp_send_cd -= delta
		if _mp_send_cd <= 0.0:
			_mp_send_cd = 0.25
			Lobby.send_score(core.score, core.combo, core.accuracy())
	if _legend != null and _legend.visible:
		var lead := _first_ms() - t
		_legend.modulate.a = clampf((lead + 1000.0) / 900.0, 0.0, 1.0) if t < _first_ms() else 0.0
		if t > _first_ms() + 300.0:
			_legend.visible = false
	if core.failed:
		_show_results(true)
		return
	_update_hud()


## Druck durch die Trace-Regel (Anti-Mash), dann ggf. ManiaCore.
func _press(lane: int, t: float) -> void:
	for idx in TraceRules.press(core, lane, t):
		_on_wrong_turn(int(idx))


## Falscher Knick: Ansicht ausfransen lassen, Text "WRONG TURN".
func _on_wrong_turn(idx: int) -> void:
	if _view != null and _view.has_method("on_wrong_turn"):
		_view.call("on_wrong_turn", idx)
	if _wrong_label == null and _hud != null:
		_wrong_label = _corner_label(tr("WRONG TURN"), 22, Color(1.0, 0.45, 0.4))
		_hud.add_child(_wrong_label)
	if _wrong_label != null:
		var vs := get_viewport_rect().size
		_wrong_label.position = Vector2((vs.x - _wrong_label.size.x) * 0.5, vs.y * 0.72)
		_wrong_label.modulate.a = 1.0
		if _wrong_tween != null and _wrong_tween.is_valid():
			_wrong_tween.kill()
		_wrong_tween = create_tween()
		_wrong_tween.tween_interval(0.35)
		_wrong_tween.tween_property(_wrong_label, "modulate:a", 0.0, 0.4)


## Autoplay: Taste exakt zur Notenzeit, Holds bis end_time, sonst 40 ms (wie Mania).
func _run_autoplay(t: float) -> void:
	for c in 4:
		var rel := _auto_release[c]
		if rel >= 0.0 and rel <= t:
			core.key_up(c, rel)
			_auto_release[c] = -1.0
	var objs := _beatmap.hit_objects
	while _auto_idx < objs.size() and objs[_auto_idx].time <= t:
		var n := objs[_auto_idx] as ManiaNote
		_auto_idx += 1
		if _auto_idx - 1 == RuleModsHarness.auto_skip():
			continue   # Shots: --auto-skip=<n> laesst Note n aus (Sudden Death/Perfect)
		var c := n.column
		if c < 0 or c > 3:
			continue
		if _auto_release[c] >= 0.0:
			core.key_up(c, minf(_auto_release[c], n.time))
			_auto_release[c] = -1.0
		core.key_down(c, n.time)
		_auto_release[c] = n.end_time() if n.is_hold else n.time + 40.0


func _feed_replay(t: float) -> void:
	while _replay_idx < _replay_events.size() and float(_replay_events[_replay_idx].t) <= t:
		var ev: Dictionary = _replay_events[_replay_idx]
		_replay_idx += 1
		if bool(ev.down):
			_press(int(ev.lane), float(ev.t))
		else:
			core.key_up(int(ev.lane), float(ev.t))


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
	if _mp_cut_ms >= 0.0 and t >= _mp_cut_ms + _first_ms():
		print("MPTRACE cut at %d ms" % int(t))
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

func _on_note_judged(index: int, result: Dictionary) -> void:
	var q := int(result.quality)
	var hold_end := bool(result.get("hold_end", false))
	_view.on_judged(index, result)
	if q == ManiaCore.Quality.MISS:
		_play_miss()
		_hp_bar.flash_miss()
	else:
		_play_hit([1.0, 1.0, 0.944, 0.891, 0.794][q])
	var off := 0.0 if hold_end else float(result.get("dt", 0.0))
	_judge_disp.show_judge(q, off)
	if q != ManiaCore.Quality.MISS and result.has("dt"):
		var dt := float(result.dt)
		_err_bar.add_hit(dt)
		_hit_offsets.append(dt)
	_acc_trace.append(core.accuracy())
	var t_note := float(_beatmap.hit_objects[index].time)
	var col := int(result.get("column", 0))
	var dtl := NAN
	if result.has("dt"):
		dtl = float(result.dt)
	elif _hold_head_dt.has(index):
		dtl = float(_hold_head_dt[index])
	_hold_head_dt.erase(index)
	if q == ManiaCore.Quality.MISS and not hold_end:
		dtl = NAN
	_judge_log.append(Vector4(t_note, float(col), float(q), dtl))
	if hold_end:
		if bool(result.get("held", false)):
			_hold_ok += 1
		else:
			_hold_drop += 1


func _on_hold_started(index: int, quality: int) -> void:
	_view.on_hold_start(index, quality)
	_hold_head_dt[index] = core.hold_head_dt(index)
	_play_hit([1.0, 1.0, 0.944, 0.891, 0.794][quality])
	var dt := float(core.hold_head_dt(index))
	_judge_disp.show_judge(quality, dt)
	_err_bar.add_hit(dt)
	_hit_offsets.append(dt)


## Alle Noten gewertet: Kamera zoomt auf das ganze Bild, dann das Ergebnis.
func _on_finished(_s: Dictionary) -> void:
	_sim_done = true
	if _ended or _finishing or _shot_mode:
		return
	if core.failed:
		_show_results(true)
		return
	_update_hud()
	_finishing = true
	_fin_t0 = Time.get_ticks_msec()
	_fin_vt = _visual_ms()
	if _legend != null:
		_legend.visible = false


func _tick_finish() -> void:
	var dur := 0.4 if _mp_bot else END_ZOOM_S
	var u := clampf(float(Time.get_ticks_msec() - _fin_t0) / 1000.0 / dur, 0.0, 1.0)
	_view.t_ms = _fin_vt
	_view.end_zoom = u
	_view.queue_redraw()
	if u >= 1.0 and float(Time.get_ticks_msec() - _fin_t0) / 1000.0 >= dur + 0.5:
		_show_results(false)


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


## Beim Pausieren gehaltene Tasten sauber loslassen (wird als Ereignis aufgezeichnet).
func _release_all() -> void:
	var t := _time_ms()
	for c in 4:
		if _lane_held[c] and not _autoplay and not _replay:
			_recorded.append({"t": t, "lane": c, "down": false})
			core.key_up(c, t)
		_lane_held[c] = false


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
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.replay_mode = "mania"
	SyncClock.stop()
	if Lobby.in_round():
		get_tree().change_scene_to_file("res://scenes/mp_lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _show_results(is_fail: bool) -> void:
	if _ended:
		return
	_ended = true
	_finishing = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SyncClock.stop()
	var s: Dictionary = core.stats()
	print("TRACE ende: score=%d acc=%.4f miss=%d failed=%s" % [int(s.score), float(s.accuracy),
			int(s.n_miss), str(is_fail)])
	s["failed"] = is_fail or bool(s.get("failed", false))
	s["unranked"] = false
	s["pp"] = -1.0
	s["mode"] = MODE
	s["stars"] = GameSession.stars
	if not _mods.is_empty() and ResourceLoader.exists(MODS_PATH):
		var mm = load(MODS_PATH)
		if mm != null and mm.has_method("mod_list"):
			s["mods"] = mm.call("mod_list", _mods)
	if Lobby.in_round():
		Lobby.send_score(int(s.score), int(s.max_combo), float(s.accuracy))
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace, _hold_ok, _hold_drop,
				bool(s.failed)))
	var new_best := false
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		_prev_best = save.get("previous", {})
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
		_save_replay(s)
		if not is_fail:
			_submit_online(s)
	_build_results(is_fail, s, new_best)
	if _args().has("--quit-at-results"):
		await get_tree().create_timer(1.0, true).timeout
		get_tree().quit()
		return
	if _mp_bot:
		print("MPORBIT final score=%d acc=%.4f combo=%d failed=%s live_seen=%s" % [
			int(s.score), float(s.accuracy), int(s.get("max_combo", 0)), str(s.failed), str(_mp_live_seen)])
		var back_s := 1.5
		for a in _args():
			if a.begins_with("--mp-back="):
				back_s = clampf(a.trim_prefix("--mp-back=").to_float(), 0.0, 60.0)
		await get_tree().create_timer(back_s, true).timeout
		if is_inside_tree():
			_back_to_browser()


func _build_results(is_fail: bool, s: Dictionary, new_best: bool) -> void:
	_view.visible = false
	for ch in _hud.get_children():
		if ch is CanvasItem:
			ch.visible = false
	var rs := ResultsScreen.new()
	_hud.add_child(rs)
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	var data := {
		"is_fail": is_fail, "fail_reason": RuleMods.fail_reason(core) if is_fail else "", "s": s, "pp": -1.0, "unranked": false,
		"new_best": new_best, "title": _beatmap.title(), "artist": _beatmap.artist(),
		"version": _beatmap.version_name(), "cover_path": "", "offsets": _hit_offsets,
		"player": Settings.profile_name, "date": Time.get_datetime_string_from_system(),
		"allow_retry": not Lobby.in_round(),
		"can_replay": GameSession.is_replay or _recorded.size() > 0,
		"is_replay": GameSession.is_replay, "lobby": Lobby.in_round(),
		"trace": _acc_trace, "h_ok": _hold_ok, "h_drop": _hold_drop,
		"notes_total": _beatmap.hit_objects.size(), "judge_log": _judge_log,
		"length_ms": float(_beatmap.hit_objects.back().end_time()),
	}
	if ResourceLoader.exists(PICTURE_PATH):
		data["trace_picture"] = {"script": PICTURE_PATH, "path": path, "judgements": _judge_log}
	if _prev_best != null:
		data["previous_best"] = _prev_best
	if is_fail:
		# Letzte Wertungszeit wie Rebound: die Uhr steht hier schon (SyncClock.stop -> 0:00).
		data["fail_ms"] = maxf(_last_update_t, 0.0)
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if cover != null:
		data["cover"] = cover
	if Lobby.in_round():
		var me := multiplayer.get_unique_id()
		data["my_id"] = me
		if Lobby.players.has(me):
			data["final"] = Lobby.players[me].get("final", {})
	rs.show_results(data)
	if _args().has("--shot-results"):
		_capture_results_shot()


func _save_replay(s: Dictionary) -> void:
	if _recorded.is_empty():
		return
	# Eigener Replay-Ordner je Modus; ohne ihn wuerde ein Trace-Lauf das Mania-Replay ueberschreiben.
	if ReplayStore.dir_for(MODE) == ReplayStore.DIR:
		return
	ReplayStore.save(GameSession.osz_path, _beatmap.version_name(), _recorded, {
		"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
		"date": Time.get_datetime_string_from_system(), "mods": GameSession.mods.duplicate(),
		"end_ms": int(_last_update_t), "rules": RULES,
	}, MODE)


func _on_results_replay() -> void:
	if GameSession.is_replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
	elif _recorded.size() > 0:
		GameSession.is_replay = true
		GameSession.replay_events = _recorded.duplicate()
		GameSession.replay_mode = MODE
		GameSession.replay_end_ms = float(int(_last_update_t))
		fresh_replay = true
	else:
		return
	_restart()


func _submit_online(s: Dictionary) -> void:
	var api: OnlineApi = GameSession.online
	if api == null or not api.enabled() or not api.logged_in():
		return
	var meta := OnlineApi.meta_from_beatmap(_beatmap, GameSession.osz_path,
		GameSession.osu_filename, GameSession.stars)
	meta["total_notes"] = _beatmap.hit_objects.size()
	var res := s.duplicate()
	res["date"] = Time.get_datetime_string_from_system(true)
	api.submit(res, meta, MODE)


# ---------------------------------------------------------------------------
# Shots (Harness)
# ---------------------------------------------------------------------------

func _shot_path(def: String) -> String:
	for a in _args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir().path_join(def)


func _save_shot(p: String) -> void:
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)


## Zeitpunkt fuer --shot-at: Zahl (ms) oder stream / hold / chord / hairpin / calm / end.
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	var kn := path.knots
	if v == "end":
		return float(_beatmap.hit_objects.back().end_time()) + 200.0
	if v == "kiai":
		for iv in _beatmap.kiai_intervals:
			if float(iv.end) - float(iv.start) > 4000.0 and float(iv.start) > 8000.0:
				return float(iv.start) + 2600.0
		return def
	if v == "stream":
		var best := -1
		var j0 := 0
		var at := def
		for i in kn.size():
			while kn[i].t - kn[j0].t > 800.0:
				j0 += 1
			if kn[j0].t >= 8000.0 and i - j0 > best:
				best = i - j0
				at = kn[j0].t + 300.0
		return at
	for j in kn.size():
		var k := kn[j]
		if k.t < 8000.0:
			continue
		var gap := (kn[j + 1].t - k.t) if j + 1 < kn.size() else 0.0
		if v == "hold" and not k.holds.is_empty() and float(k.holds[0].t_end) - k.t >= 500.0:
			return k.t + (float(k.holds[0].t_end) - k.t) * 0.55
		if v == "chord" and k.kind == TracePath.Kind.DIAG:
			return k.t - 380.0
		if v == "star" and k.kind == TracePath.Kind.STAR:
			return k.t - 380.0
		if v == "cross" and k.kind == TracePath.Kind.CROSS:
			return k.t - 380.0
		if v == "hairpin" and k.hairpin and gap > 250.0:
			return k.t - 380.0
		if v == "calm" and gap > 330.0 and gap < 600.0 and k.t > 12000.0:
			return k.t - 300.0
	return def


## Wertung/Autoplay ohne Audio bis t vorspulen (deterministisch, 8-ms-Schritte).
func _sim_to(target: float) -> void:
	var t := -2000.0
	while t < target and not _sim_done and not (core.failed and not core.no_fail):   # Fail (SD/PF) endet hier
		t += 8.0
		if _autoplay:
			_run_autoplay(t)
		_last_update_t = t
		core.update(t)


func _capture_shot() -> void:
	core.no_fail = not _args().has("--shot-fail")   # --shot-fail: echter Fail (SD/PF)
	var target := _first_ms() + 1200.0
	var at_arg := ""
	for a in _args():
		if a.begins_with("--shot-at="):
			at_arg = a.trim_prefix("--shot-at=")
			target = _shot_target(at_arg, target)
	var zoomed := at_arg == "end"
	if _args().has("--shot-results"):
		var t_end := _first_ms() + 1.0
		t_end = float(_beatmap.hit_objects.back().end_time()) + 1000.0
		_sim_to(t_end)
		_show_results(core.failed)
		return
	if _args().has("--shot-pause"):
		_sim_to(target)
		_shot_hold = true
		_view.t_ms = target
		_view.queue_redraw()
		_toggle_pause(true)
		await get_tree().create_timer(0.6, true).timeout
		await RenderingServer.frame_post_draw
		_save_shot(_shot_path("trace_pause.png"))
		get_tree().quit(0)
		return
	if target - _time_ms() > 3000.0:
		var cut := target - 2500.0
		_sim_to(cut)
		if _use_audio:
			SyncClock.seek_ms(cut)
	for a in _args():
		if a.begins_with("--movie-len=") and not zoomed:
			if OS.get_cmdline_args().has("--nohud"):
				_hud.visible = false
			# Debug (Demo-Videos): Film ab hier, endet nach <s> Film-Sekunden.
			print("MOVIE_START frame=%d" % Engine.get_process_frames())
			await get_tree().create_timer(a.trim_prefix("--movie-len=").to_float(), true).timeout
			get_tree().quit(0)
			return
	if zoomed:
		# Ende: alles gewertet, Kamera ganz heraus (Endbild).
		_sim_to(target)
		_shot_hold = true
		_legend.visible = false
		_update_hud()
		_view.t_ms = target
		_view.end_zoom = 1.0
		_view.queue_redraw()
		await get_tree().create_timer(0.5, true).timeout
	else:
		await _wait_until(target)
		_update_hud()
	if not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	_save_shot(_shot_path("trace.png"))
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
	_save_shot(_shot_path("trace_results.png"))
	get_tree().quit(0)
