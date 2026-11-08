extends Control

## Orbit-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause,
## Fail, Ende -> Results, Score speichern unter Modus "orbit").
## Darstellung: OrbitView (ein _draw). Logik: OrbitCore/OrbitConverter
## (Task orbit-core). Mania 4K bleibt davon voellig unberuehrt.
##
## Steuerung (Bahnen): die TASTE waehlt die Spur (Taste A = links/innen, Taste B =
## rechts/aussen; Maus links/rechts, Settings.orbit_key_inner/outer), der Cursor
## muss beim Druck auf dem KOPF liegen (Abstand in Bahn-Einheiten). Tablet =
## absolute Mausposition, Maus geht genauso.
## CLI: --orbit --autoplay (Autoplay), --shot --shot-at=<ms> --shot-out=<png>,
## --auto-miss=<n> (Autoplay laesst jede n-te Note aus, fuer Fehltreffer-Shots).
## Replays: OrbitCore laeuft immer deterministisch und schreibt die Eingaben
## mit (core.replay_log). Am Ende: ReplayStore "orbit_last" (letzter Lauf) und
## "orbit" (bester Lauf). GameSession.is_replay spielt die Events wieder ab
## (Cursor + Ringe wie gespielt, gleiche Wertung). --shot-clip (mit
## --shot-results): nach dem Endbild-Shot den Clip-Knopf ausloesen und auf das
## Video warten (Harness).

const MODE := "orbit"
const AUTO_TAP_MS := 40.0
## Groesse von Judge + Kombo relativ zu Mania (bei 720 px Hoehe).
const JUDGE_SCALE := 0.5
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.45, 0.95, 0.55),
	"B": Color(0.45, 0.70, 1.0), "C": Color(0.80, 0.55, 1.0), "D": Color(1.0, 0.45, 0.45),
}

var core: OrbitCore
var notes: Array[OrbitNote] = []
var _beatmap: Beatmap
var _use_audio := false
var _debug_start_usec := 0
var _debug_running := false
var _ended := false
var _autoplay := false
var _auto_miss := 0
var _auto_idx := 0
var _auto_release: Array[float] = [-1.0, -1.0]
var _auto_arc: Array[int] = [-1, -1]
var _auto_off := Vector2.ZERO
var _countdown_running := false
var _song_len_ms := 1.0
## Cursor in Bahn-Einheiten.
var _cursor_p := Vector2.ZERO
## Haltequellen pro Taste (A/B): [Maus, Taste].
var _held := [[false, false], [false, false]]
var _w300 := 49.5

var _bg: OrbitBackdrop
var _view: OrbitView
var _hud: CanvasLayer
var _judge_disp: JudgeDisplay
var _err_bar: HitErrorBar
var _hp_bar: HpBar
var _break_ov: BreakOverlay
var _breaks: Array[Vector2] = []
var _break_cur := -1
var _break_skip := false
var _hp_flash_cd := 0.0
var _legend: Control
var _acc_label: Label
var _score_label: Label
var _grade_label: Label
var _time_label: Label
var _top_fill: ColorRect
var _pause_menu: PauseMenu
var _results_screen: OrbitResults
var _sound: OrbitSound
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()
## Takt + Intensitaet fuer den Ring-Puls (nur Helligkeit).
var _beat := BeatClock.new()
var _intensity := IntensityMap.new()
var _last_milestone := 0
## Bot-Plan (OrbitCore.bot_plan): je Ziel [Zeitversatz, Zielfehler, auslassen].
var _bot_plan: Array = []
## Je gewertetem Ziel [Winkel, Ring, dt, Zielfehler, Stufe, Zeit] fuer OrbitResults.
var _hit_log: Array = []
var _mp_send_cd := 0.0
var _mods_label: Label
## Replay-Wiedergabe: Events (OrbitCore.EV_*), naechster Index, Endzeit des Laufs.
var _replay := false
var _replay_events: Array = []
var _replay_idx := 0
var _replay_end_ms := -1.0
var _replay_down: Array[bool] = [false, false]
## Replay aus der Zeit vor "Ring durch Zeigen" (Format 1): nicht abspielbar.
var _replay_old := false
var _track: OrbitTrack
var _hint: Label
var _hint_tween: Tween
## Zeit des letzten core.update (Ende des Laufs fuer meta.end_ms).
var _last_update_t := 0.0
var _clip_exporter: ClipExporter
## MP-Smoke (--mp-bot): Bot spielt auch im Raum, Abbruch nach --mp-cut=<s> ab
## erster Note, hoechster gesehener Live-Score je Mitspieler (vor dessen Finale).
var _mp_bot := false
var _mp_cut_ms := -1.0
var _mp_live_seen: Dictionary = {}
var _mp_skip_voted := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	_replay = GameSession.is_replay and ReplayStore.is_orbit(GameSession.replay_mode)
	if GameSession.is_replay and not _replay:
		GameSession.is_replay = false   # Mania-Events passen nicht zu Orbit
		GameSession.replay_events = []
	_mp_bot = Lobby.active and Lobby.in_game and OS.get_cmdline_args().has("--mp-bot")
	# --mp-bot spielt selbst (ohne --autoplay: dessen 45-s-Watchdog wuerde den Smoke kappen).
	_autoplay = ((OS.get_cmdline_args().has("--autoplay") and not Lobby.active) or _mp_bot) and not _replay
	var jitter := 0.0
	var aim := 0.0
	var seed := 1
	for a in OS.get_cmdline_args():
		if a.begins_with("--auto-miss="):
			_auto_miss = maxi(0, a.trim_prefix("--auto-miss=").to_int())
		elif a.begins_with("--auto-jitter="):
			jitter = maxf(0.0, a.trim_prefix("--auto-jitter=").to_float())
		elif a.begins_with("--auto-aim="):
			aim = maxf(0.0, a.trim_prefix("--auto-aim=").to_float())
		elif a.begins_with("--auto-seed="):
			seed = a.trim_prefix("--auto-seed=").to_int()
		elif a.begins_with("--mp-cut="):
			_mp_cut_ms = maxf(0.0, a.trim_prefix("--mp-cut=").to_float()) * 1000.0
	_build_core()
	if _replay:
		_replay_events = GameSession.replay_events
		_replay_end_ms = GameSession.replay_end_ms
		_replay_old = is_old_replay(_replay_events)
	if _autoplay:
		# Menschlicher Bot: --auto-jitter=<ms> --auto-aim=<Grad> --auto-seed=<n>.
		_bot_plan = OrbitCore.bot_plan(notes, seed, jitter, aim, _auto_miss)
	_beat.setup(_beatmap.timing_points)
	_intensity.build(_beatmap)
	_build_bg()
	_view = OrbitView.new()
	add_child(_view)
	_view.setup(notes)
	_view.track = _track
	_view.preempt = _preempt()
	_view.show_guides = Settings.orbit_guides
	_view.key_hint_auto = GameSession.stars < 3.0
	_view.tol = _tolerance()
	_view.mod_hidden = bool(core.mods.get("HD", false))
	_view.mod_fade_in = bool(core.mods.get("FI", false))
	_build_sound()
	_build_hud()
	_update_hud()  # Startwerte schon im Intro sichtbar
	if _replay_old:
		_show_old_replay()
		return
	if Lobby.active and Lobby.in_game:
		Lobby.skip_now.connect(_do_skip)
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if _mp_bot:
		if _mp_cut_ms >= 0.0 and not notes.is_empty():
			_mp_cut_ms += float(notes[0].time_ms)
		print("MPORBIT start: %d Ziele, autoplay=%s, cut=%d ms" % [notes.size(), _autoplay, int(_mp_cut_ms)])
	if DisplayServer.get_name() == "headless" and not _mp_bot:
		print("=== Orbit Smoke: %d Ziele ===" % notes.size())
		get_tree().quit(0)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	if OS.get_cmdline_args().has("--shot"):
		_capture_shot()
	else:
		get_tree().paused = true
		SyncClock.pause()
		_resume_with_countdown(1.0)
		if OS.get_cmdline_args().has("--shot-intro"):
			# Shot: Intro/Countdown (Ziffer "3" steht, Spiel pausiert).
			await get_tree().create_timer(0.45, true).timeout
			await RenderingServer.frame_post_draw
			_save_shot(_shot_path("orbit_intro.png"))
			get_tree().quit(0)


## Replays ohne Regel-Marke oder aus Format 1-3 (vor den Bahnen) passen nicht zu
## den neuen Regeln: sauber als "alte Version" melden und zurueck zur Auswahl.
static func is_old_replay(events: Array) -> bool:
	for e in events:
		if e is Array and e.size() >= 3 and int(e[1]) == OrbitCore.EV_RULES:
			return int(e[2]) < OrbitCore.REPLAY_RULES
	return true


func _show_old_replay() -> void:
	var l := Label.new()
	l.text = tr("Dieses Replay stammt aus einer älteren Orbit-Version und lässt sich nicht mehr abspielen.")
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
	var stream := OszImporter.load_audio_stream(GameSession.osz_path, _beatmap)
	if stream != null:
		# Erste Note bekommt immer ihre volle Anflugzeit + Reaktionspuffer.
		var lead := _beatmap.audio_lead_in()
		var first_t: float = _beatmap.hit_objects[0].time
		var need := _preempt() + 900.0
		if first_t + lead < need:
			lead = need - first_t
		SyncClock.play(stream, lead)
		_use_audio = true
	return true


## Debug/Shots: --orbit-map=<Teil des osz-Namens> [--orbit-diff=<Version>]
## waehlt direkt eine Map aus maps/ (Szene orbit.tscn ohne Song-Browser).
func _cli_pick() -> void:
	var want := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--orbit-map="):
			want = a.trim_prefix("--orbit-map=")
		elif a.begins_with("--orbit-diff="):
			GameSession.difficulty_version = a.trim_prefix("--orbit-diff=")
	if want == "":
		return
	var dir := MapLibrary.default_maps_dir()
	for f in DirAccess.get_files_at(dir):
		if f.to_lower().ends_with(".osz") and f.findn(want) >= 0:
			GameSession.osz_path = dir.path_join(f)
			return


## Logik laden: OrbitConverter macht aus der Mania- oder osu!standard-Map die Ziele, OrbitCore
## wertet (NF liest OrbitCore selbst aus GameSession.mods).
func _build_core() -> void:
	notes = OrbitConverter.convert(_beatmap)
	_track = OrbitConverter.track_for(_beatmap, notes)
	core = OrbitCore.new()
	core.setup(notes, _beatmap.od(), Settings.mania_scroll, _beatmap.hp())
	core.set_track(_track)
	core.note_judged.connect(_on_note_judged)
	core.arc_started.connect(_on_arc_started)
	core.press_missed.connect(_on_press_missed)
	core.finished.connect(func(_s): _show_results(false))
	# Immer deterministisch (Wertung unabhaengig von der Bildrate); live mitschreiben.
	core.set_replay_mode(not GameSession.is_replay)
	_w300 = core.w300


func _preempt() -> float:
	return ManiaCore.preempt_for(Settings.mania_scroll)


func _tolerance() -> float:
	return core.angle_tol if core != null else OrbitCore.AIM_TOL


func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - 1000.0


## Scroll Speed live (F3/F4, Pausenmenue): nur die Anflugzeit aendert sich.
func apply_scroll_speed(_speed: int) -> void:
	if _view != null:
		_view.preempt = _preempt()
	if core != null:
		core.set_scroll_scale(Settings.mania_scroll)


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build_bg() -> void:
	# Welt / Map-Bild / Aus (Settings.orbit_background, CLI --orbit-bg=...).
	var forced := Settings.world_theme_name()
	for a in OS.get_cmdline_args():
		if a.begins_with("--theme="):
			forced = a.substr(8)
	_bg = OrbitBackdrop.new()
	add_child(_bg)
	# Kein Welt-Himmel hinter den Bahnen (keine Planeten/Deko): "Welt" = dunkler Grund.
	var bg_mode := Settings.orbit_background_mode()
	if bg_mode == OrbitBackdrop.BG_WORLD:
		bg_mode = OrbitBackdrop.BG_OFF
	_bg.setup(_beatmap, bg_mode, forced, GameSession.stars,
			OszImporter.load_background_texture(GameSession.osz_path, _beatmap), Settings.bg_dim)

func _build_sound() -> void:
	_sound = OrbitSound.new()
	add_child(_sound)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_song_len_ms = maxf(_beatmap.duration_ms(), 1.0)
	var theme_col := UiTheme.ACCENT

	var title := Label.new()
	title.text = "%s — %s  ·  %s" % [_beatmap.artist(), _beatmap.title(), _beatmap.version_name()]
	title.position = Vector2(24, 14)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_shadow(title)
	title.modulate.a = 0.75
	_hud.add_child(title)
	var mode_tag := Label.new()
	mode_tag.text = tr("ORBIT")
	mode_tag.position = Vector2(24, 34)
	mode_tag.add_theme_font_override("font", UiTheme.heading_font(3))
	mode_tag.add_theme_font_size_override("font_size", 11)
	mode_tag.add_theme_color_override("font_color", Color(OrbitView.INNER_COL, 0.8))
	_hud.add_child(mode_tag)
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
	_top_fill.color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.75)
	_top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_fill)

	# Werte links/rechts neben den Ringen, vertikal mittig (ruhig, nie im Feld).
	var left := _stat_column(0.11)
	_acc_label = _stat_block(left, tr("GENAUIGKEIT"), 40)
	_grade_label = _stat_block(left, tr("RANG"), 24)
	var right := _stat_column(0.89)
	_score_label = _stat_block(right, tr("PUNKTE"), 30)

	_hp_bar = HpBar.new()
	_hp_bar.label_text = "HP"
	_hud.add_child(_hp_bar)
	_hp_bar.setup(theme_col)
	_hp_bar.anchor_left = 0.5
	_hp_bar.anchor_right = 0.5
	_hp_bar.offset_left = -160
	_hp_bar.offset_right = 160
	_hp_bar.offset_top = 6
	_hp_bar.offset_bottom = 30

	_err_bar = HitErrorBar.new()
	_hud.add_child(_err_bar)
	var w := {}
	for k in ["w_max", "w300", "w200", "w100", "w50"]:
		if k in core:
			w["max" if k == "w_max" else k] = float(core.get(k))
	_err_bar.setup(w, 260.0)

	_judge_disp = JudgeDisplay.new()
	_hud.add_child(_judge_disp)
	_judge_disp.setup(theme_col)
	# Eigene Orbit-Stufen; FRUEH/SPAET schon ab SHARP (alles ausser CORE-Zeit).
	_judge_disp.window_300_ms = float(core.w_max)
	for q in OrbitCore.TIER_NAMES.size():
		_judge_disp._judges[q].text = tr(OrbitCore.TIER_NAMES[q])
	_judge_disp._judges[0].add_theme_color_override("font_color", OrbitView.MAX_COL)

	# Mods oben links unter dem ORBIT-Tag (wie Mania), nur wenn welche aktiv.
	var mt := OrbitCore.mods_text(core.mods)
	if mt != "":
		_mods_label = Label.new()
		_mods_label.text = mt
		_mods_label.position = Vector2(24, 50)
		_mods_label.add_theme_font_override("font", UiTheme.heading_font(3))
		_mods_label.add_theme_font_size_override("font_size", 11)
		_mods_label.add_theme_color_override("font_color", Color(OrbitView.OUTER_COL, 0.85))
		_hud.add_child(_mods_label)

	_build_legend()
	_build_hint()

	_break_ov = BreakOverlay.new()
	_hud.add_child(_break_ov)
	_build_breaks()
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


## Spur-Legende unter dem Feld (nur bis kurz vor der ersten Note).
func _build_hint() -> void:
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", OrbitView.MISS_X_COL)
	_shadow(_hint)
	_hint.modulate.a = 0.0
	_hud.add_child(_hint)


## Kurzer Hinweis (0,7 s) bei einem Druck, der nicht zaehlte.
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


func _build_legend() -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 34)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_legend = box
	_hud.add_child(box)
	for r in 2:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(item)
		var col: Color = OrbitView.OUTER_COL if r == 1 else OrbitView.INNER_COL
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(18, 18)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lane := r
		icon.draw.connect(func():
			var p := icon.size * 0.5
			if lane == 0:
				icon.draw_circle(p, 7.0, col, true, -1.0, true)
			else:
				icon.draw_rect(Rect2(p - Vector2(6.5, 6.5), Vector2(13, 13)), col))
		item.add_child(icon)
		var l := Label.new()
		l.text = (tr("Spur B (rechts): Taste %s") % UiTheme.key_short(Settings.orbit_key_outer)) if r == 1 else (tr("Spur A (links): Taste %s") % UiTheme.key_short(Settings.orbit_key_inner))
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
		_shadow(l)
		item.add_child(l)
	var keys := Label.new()
	keys.text = tr("Folg dem weißen Punkt, drück im Takt (auch Maus links/rechts)")
	keys.add_theme_font_size_override("font_size", 15)
	keys.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_shadow(keys)
	box.add_child(keys)


func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)


func _place_hud() -> void:
	if _judge_disp == null or _view == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var cy := vs.y * 0.5
	# Wertung klein und ruhig unten mittig (die Mitte gehoert der Bahn), Kombo
	# knapp darueber, darunter die Timing-Leiste. Skalierung um die Bildschirmmitte.
	var k := JUDGE_SCALE * vs.y / 720.0
	_judge_disp.pivot_offset = vs * 0.5
	_judge_disp.scale = Vector2(k, k)
	_judge_disp.judge_gap = 0.0
	_judge_disp.combo_gap = vs.y * 0.045 / k
	_judge_disp.place(cy + (vs.y * 0.915 - cy) / k)
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5, vs.y - _err_bar.size.y - 10.0)
	_legend.size = Vector2(vs.x, 24)
	_legend.position = Vector2(0, vs.y * 0.915)
	_hint.size = Vector2(vs.x, 24)
	_hint.position = Vector2(0, vs.y * 0.075)


func _stat_column(ax: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_left = ax
	v.anchor_right = ax
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
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


func _tabular_font(ref: Control) -> Font:
	var fv := FontVariation.new()
	fv.base_font = ref.get_theme_default_font() if ref.get_theme_default_font() != null else ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	fv.opentype_features = { ts.name_to_tag("tnum"): 1 }
	return fv


func _build_breaks() -> void:
	_breaks.clear()
	_break_cur = -1
	if notes.is_empty():
		return
	if float(notes[0].time_ms) > 3000.0:
		_breaks.append(Vector2(0.0, float(notes[0].time_ms)))
	var last_end := float(notes[0].end_ms)
	for i in range(1, notes.size()):
		var t := float(notes[i].time_ms)
		if t - last_end > 4500.0:
			_breaks.append(Vector2(last_end + 500.0, t))
		last_end = maxf(last_end, float(notes[i].end_ms))


func _update_break_overlay(t: float) -> void:
	if _break_ov == null:
		return
	var idx := -1
	for i in _breaks.size():
		if t >= _breaks[i].x and t < _breaks[i].y + BreakOverlay.FADE_OUT_MS:
			idx = i
			break
	if idx < 0:
		if _break_cur >= 0:
			_break_ov.hide_break()
			_break_cur = -1
		return
	var can_skip: bool = _breaks[idx].x <= 0.0 and _can_skip_intro() and not _ended \
			and Settings.orbit_ring_for_key(KEY_SPACE) == -1
	if idx != _break_cur or can_skip != _break_skip:
		_break_ov.show_break(_breaks[idx].x, _breaks[idx].y, _beat_ms(), can_skip)
		_break_cur = idx
		_break_skip = can_skip
	_break_ov.update(t)


func _beat_ms() -> float:
	for p in _beatmap.timing_points:
		if p.uninherited and p.beat_length > 0.0:
			return p.beat_length
	return 500.0


func _can_skip_intro() -> bool:
	if notes.is_empty() or not _use_audio:
		return false
	return float(notes[0].time_ms) - _time_ms() > 4500.0


func _do_skip() -> void:
	SyncClock.seek_ms(float(notes[0].time_ms) - 2200.0)
	_update_break_overlay(float(notes[0].time_ms) - 2200.0)


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _view_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _set_cursor_from(pos: Vector2, t: float) -> void:
	_view.cursor_pos = pos
	_cursor_p = _view.to_path(pos)
	core.cursor_moved(_cursor_p, t)
	_sync_held_view()


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
		var key := Settings.orbit_ring_for_key(event.keycode)
		if key >= 0:
			_press(key, 1, event.pressed)


## Taste A/B gedrueckt/losgelassen ueber eine Quelle (0 Maus, 1 Taste): der Core
## sieht nur den Uebergang "keine Quelle" <-> "mindestens eine".
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
		core.key_down(key, t, _cursor_p)
	else:
		core.key_up(key, t)
	_sync_held_view()


## Spur-Marken am Kopf leuchten, solange ihre Taste unten ist.
func _sync_held_view() -> void:
	for k in 2:
		_view.ring_held[k] = _held[k][0] or _held[k][1] or _auto_release[k] >= 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _ended:
			_back_to_browser()
		elif not _countdown_running:
			_toggle_pause(true)
		return
	if event.keycode == KEY_R and Settings.orbit_ring_for_key(KEY_R) == -1 and not Lobby.active:
		_restart()
		return
	if event.keycode == KEY_SPACE and not _ended and Settings.orbit_ring_for_key(KEY_SPACE) == -1 \
			and _can_skip_intro():
		if Lobby.active and Lobby.in_game:
			Lobby.vote_skip()  # Multiplayer: springt erst, wenn ALLE druecken
		else:
			_do_skip()


## Autoplay: Taste der Spur exakt zur Trefferzeit, Cursor auf dem Kopf (plus
## Zielfehler des Bot-Plans). Halten bis end_ms; der Cursor folgt dem Kopf
## immer, auch zwischen den Noten (wie ein Spieler, der mitkreist).
func _run_autoplay(t: float) -> void:
	for k in 2:
		if _auto_release[k] >= 0.0 and _auto_release[k] <= t:
			var rel := _auto_release[k]
			if _auto_arc[k] >= 0:
				_auto_cursor(_track.head(rel) + OrbitCore.bot_offset(_auto_arc[k], _bot_aim(_auto_arc[k])), rel)
			core.key_up(k, rel)
			_auto_release[k] = -1.0
			_auto_arc[k] = -1
	while _auto_idx < notes.size() and float(notes[_auto_idx].time_ms) + _bot_dt(_auto_idx) <= t:
		var i := _auto_idx
		var n = notes[i]
		_auto_idx += 1
		var nt := float(n.time_ms) + _bot_dt(i)
		if _bot_skip(i):
			continue
		var k: int = n.ring
		if _auto_release[k] >= 0.0:
			core.key_up(k, minf(_auto_release[k], nt))
			_auto_release[k] = -1.0
			_auto_arc[k] = -1
		var off := OrbitCore.bot_offset(i, _bot_aim(i))
		var aim := _track.head(nt) + off
		_auto_cursor(aim, nt)
		core.key_down(k, nt, aim)
		_auto_off = off
		if n.is_arc:
			_auto_arc[k] = i
			_auto_release[k] = float(n.end_ms) + _bot_dt(i) * 0.5
		else:
			_auto_release[k] = nt + AUTO_TAP_MS
	# Cursor folgt dem Kopf (exakt, mit dem Zielfehler des naechsten Ziels).
	var off_f := _auto_off
	if _auto_idx < notes.size():
		off_f = OrbitCore.bot_offset(_auto_idx, _bot_aim(_auto_idx))
	_auto_cursor(_track.head(t) + off_f, t)
	_sync_held_view()


func _bot_dt(i: int) -> float:
	return float(_bot_plan[i][0]) if i < _bot_plan.size() else 0.0


func _bot_aim(i: int) -> float:
	return float(_bot_plan[i][1]) if i < _bot_plan.size() else 0.0


func _bot_skip(i: int) -> bool:
	if i < _bot_plan.size():
		return bool(_bot_plan[i][2])
	return _auto_miss > 0 and i % _auto_miss == _auto_miss - 1


func _auto_cursor(p: Vector2, t: float) -> void:
	_cursor_p = p
	_view.cursor_pos = _view.to_px(p)
	core.cursor_moved(p, t)


# ---------------------------------------------------------------------------
# Frame-Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null:
		return
	var t := _time_ms()
	if _autoplay:
		_run_autoplay(t)
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
	if _replay and _replay_end_ms >= 0.0 and t >= _replay_end_ms \
			and _replay_idx >= _replay_events.size():
		# Lauf endete hier (z. B. Abbruch im Shot): Endbild wie im Lauf.
		_show_results(bool(core.failed))
		return
	_view.t_ms = t
	for r in 2:
		_view.arc_warn[r] = core.arc_out_ms(r, t) / OrbitCore.ARC_OUT_MS
	# Takt-Puls: nur Helligkeit, in ruhigen Stellen schwaecher.
	_beat.update(t, delta)
	var env := _beat.beat_env * (0.35 + 0.65 * _intensity.value_at(t))
	_view.beat_env = env
	_view.energy = _intensity.value_at(t)
	_view.combo = int(core.get("combo")) if "combo" in core else 0
	_view.kiai = _beat.kiai_mix
	_judge_disp.beat(env)
	_bg.update_world(delta, _beat, _intensity.value_at(t))
	# Multiplayer: Live-Stand 4x pro Sekunde.
	if Lobby.active and Lobby.in_game:
		_mp_send_cd -= delta
		if _mp_send_cd <= 0.0:
			_mp_send_cd = 0.25
			Lobby.send_score(core.orbit_score(), int(core.combo), core.accuracy())
	_hp_flash_cd = maxf(_hp_flash_cd - delta, 0.0)
	_update_break_overlay(t)
	if _legend != null and _legend.visible and not notes.is_empty():
		var lead := float(notes[0].time_ms) - t
		_legend.modulate.a = clampf((lead - 300.0) / 900.0, 0.0, 1.0)
		if _legend.modulate.a <= 0.0 and t > 0.0:
			_legend.visible = false
	if bool(core.get("failed")) if "failed" in core else false:
		_show_results(true)
		return
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
		_show_results(bool(core.failed))


## Replay: Events bis t in den Core (Originalzeiten), Cursor + Ring anzeigen.
func _feed_replay(t: float) -> void:
	while _replay_idx < _replay_events.size() and float(_replay_events[_replay_idx][0]) <= t:
		var ev: Array = _replay_events[_replay_idx]
		_replay_idx += 1
		core.apply_event(ev)
		var code := int(ev[1])
		if code < OrbitCore.EV_UP and ev.size() >= 4:
			_cursor_p = Vector2(float(ev[2]), float(ev[3])) / 1000.0
			_view.cursor_pos = _view.to_px(_cursor_p)
		if code >= OrbitCore.EV_DOWN and code < OrbitCore.EV_UP:
			_replay_down[code - OrbitCore.EV_DOWN] = true
		elif code >= OrbitCore.EV_UP:
			_replay_down[clampi(code - OrbitCore.EV_UP, 0, 1)] = false
	_view.ring_held[0] = _replay_down[0]
	_view.ring_held[1] = _replay_down[1]


func _update_hud() -> void:
	var combo := int(core.get("combo")) if "combo" in core else 0
	_judge_disp.set_combo(combo)
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
	var t := clampf(_time_ms(), 0.0, _song_len_ms)
	_time_label.text = "%s / %s" % [_fmt_time(t), _fmt_time(_song_len_ms)]
	_top_fill.anchor_right = clampf(t / _song_len_ms, 0.0, 1.0)
	if "hp" in core:
		_hp_bar.set_hp(float(core.hp))


func _fmt_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


func _on_note_judged(index: int, result: Dictionary) -> void:
	var q := int(result.get("quality", 5))
	_view.on_judged(index, result)
	if index >= 0 and index < notes.size():
		var n := notes[index]
		_hit_log.append([n.angle_deg, n.ring, float(result.get("dt", 0.0)),
			float(result.get("angle_err", 0.0)), q, n.time_ms])
	_check_milestone(q)
	var hold_end := bool(result.get("hold_end", false))
	var snd_ring := int(result.get("ring", notes[index].ring if index >= 0 and index < notes.size() else 0))
	_sound.on_judged(snd_ring, q, hold_end)
	var off: float = 0.0 if hold_end else float(result.get("dt", 0.0))
	_judge_disp.show_judge(q, off)
	if q == 5:
		_hp_bar.flash_miss()
	elif _hp_flash_cd <= 0.0 and "hp" in core and float(core.hp) < 0.999:
		_hp_bar.flash_hit()
		_hp_flash_cd = 0.6
	if q != 5 and result.has("dt") and not hold_end:
		var dt := float(result.dt)
		_err_bar.add_hit(dt)
		_hit_offsets.append(dt)
	_acc_trace.append(core.accuracy())


## Fehldruck: kurze Marke am Cursor (Grund steht in der Form, siehe OrbitView).
func _on_press_missed(pos: Vector2, ring: int, reason: String) -> void:
	_view.on_press_missed(pos, ring, reason)
	match reason:
		"AIM":
			_flash_hint(tr("neben dem Kopf"))
		"RING":
			_flash_hint(tr("andere Taste"))


func _on_arc_started(index: int, quality: int) -> void:
	_view.on_arc_started(index, quality, core.arc_head_dt(index))
	if index >= 0 and index < notes.size():
		_sound.on_arc_started(notes[index].ring, quality)


## Kombo-Meilensteine (50, 100, 200 ...): ruhige Welle + Klang, nie grell.
func _check_milestone(q: int) -> void:
	if q == 5:
		_last_milestone = 0
		return
	var c := int(core.combo)
	if (c == 50 or (c >= 100 and c % 100 == 0)) and c != _last_milestone:
		_last_milestone = c
		_view.start_wave(c >= 100)
		if _use_audio:
			Sfx.milestone(c)


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
		_release_all()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_menu != null and _pause_menu.visible:
			_pause_menu.close()
		_resume_with_countdown()


## Beim Pausieren gehaltene Ringe sauber loslassen (kein haengender Bogen).
func _release_all() -> void:
	var t := _time_ms()
	for k in 2:
		var was: bool = _held[k][0] or _held[k][1]
		_held[k] = [false, false]
		if was and not _autoplay and not _replay:
			core.key_up(k, t)
	_sync_held_view()


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


## Wie mania_3d.gd: zaehlt Frames auch bei pausiertem Tree, nie haengend.
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
	# Multiplayer: zurueck in den Raum statt in den Song-Browser.
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
	s["pp"] = -1.0   # Orbit hat (noch) keine pp-Formel
	s["mode"] = MODE
	# Orbit-Sterne fuers Orbit-Rating im Profil (Gewichtung wie pp).
	s["stars"] = OrbitConverter.stars(notes)
	var new_best := false
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
		_save_replay(s, new_best)
		if not is_fail:
			_submit_online(s)
	# Multiplayer: letzten Live-Stand + Finale an alle melden.
	if Lobby.active and Lobby.in_game:
		Lobby.send_score(int(s.score), int(core.combo), float(s.accuracy))
		Lobby.send_final(PlayerStatsCard.pack(s, _hit_offsets, _acc_trace, 0, 0, s.failed))
	# Eigener Orbit-Endscreen (Karte der Treffer, Stufen, Timing).
	var rs := OrbitResults.new()
	# Spielfeld + HUD ausblenden: der Endscreen steht fuer sich.
	_view.visible = false
	for ch in _hud.get_children():
		if ch is CanvasItem:
			ch.visible = false
	_hud.add_child(rs)
	_results_screen = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.replay_pressed.connect(_on_results_replay)
	rs.clip_pressed.connect(_on_results_clip)
	var has_log := core.replay_log.size() > 1
	rs.show_results({
		"is_fail": is_fail,
		"s": s,
		"log": _hit_log,
		"w50": float(core.w50),
		"w_max": float(core.w_max),
		"new_best": new_best,
		"title": _beatmap.title(),
		"artist": _beatmap.artist(),
		"version": _beatmap.version_name(),
		"allow_retry": not Lobby.active,
		"can_replay": not Lobby.active and (_replay or has_log),
		"is_replay": _replay,
		"can_clip": _replay or has_log,
	})
	var grade := "F" if is_fail else str(s.get("grade", "D"))
	get_tree().create_timer(0.38, true).timeout.connect(func():
		if is_inside_tree() and _use_audio:
			Sfx.rank_reveal(grade))
	if OS.get_cmdline_args().has("--shot-results"):
		_capture_results_shot()
	if _mp_bot:
		print("MPORBIT final score=%d acc=%.4f combo=%d failed=%s live_seen=%s" % [
			int(s.score), float(s.accuracy), int(s.get("max_combo", 0)), str(s.failed), str(_mp_live_seen)])
		# Wie der Klick auf "Zurueck": nach dem Endscreen (--mp-back=<s>, Standard 1,5) in den Raum.
		var back_s := 1.5
		for a in OS.get_cmdline_args():
			if a.begins_with("--mp-back="):
				back_s = clampf(a.trim_prefix("--mp-back=").to_float(), 0.0, 60.0)
		await get_tree().create_timer(back_s, true).timeout
		if is_inside_tree():
			_back_to_browser()


## Meta fuer ReplayStore (Mods: Wiedergabe mit denselben Mods; end_ms: Ende des Laufs).
func _replay_meta(s: Dictionary) -> Dictionary:
	return {
		"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
		"date": Time.get_datetime_string_from_system(), "mods": GameSession.mods.duplicate(),
		"end_ms": int(_last_update_t), "mode": MODE, "orbit_rules": OrbitCore.REPLAY_RULES,
	}


## Letzten Lauf immer, besten Lauf bei neuem Bestwert (oder wenn noch keiner da ist).
func _save_replay(s: Dictionary, new_best: bool) -> void:
	if core.replay_log.size() <= 1:
		return
	var ver := _beatmap.version_name()
	var meta := _replay_meta(s)
	ReplayStore.save(GameSession.osz_path, ver, core.replay_log, meta, ReplayStore.MODE_ORBIT_LAST)
	if new_best or not ReplayStore.exists(GameSession.osz_path, ver, ReplayStore.MODE_ORBIT_BEST):
		ReplayStore.save(GameSession.osz_path, ver, core.replay_log, meta, ReplayStore.MODE_ORBIT_BEST)


## Replay-Knopf: im Replay "Selbst spielen", sonst den eben gespielten Lauf ansehen.
func _on_results_replay() -> void:
	if _replay:
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.replay_mode = "mania"
	elif core.replay_log.size() > 1:
		GameSession.is_replay = true
		GameSession.replay_events = core.replay_log.duplicate()
		GameSession.replay_mode = ReplayStore.MODE_ORBIT_LAST
		GameSession.replay_end_ms = float(int(_last_update_t))
	else:
		return
	_restart()


## Clip-Knopf: diesen Lauf (bzw. das laufende Replay) als Video exportieren,
## wie Mania (zweiter Prozess, ClipExporter) mit Fortschritt im Endbild.
func _on_results_clip() -> void:
	var ver := _beatmap.version_name()
	var mode := GameSession.replay_mode if _replay else ReplayStore.MODE_ORBIT_LAST
	if not _replay and core.replay_log.size() > 1 \
			and (_autoplay or not ReplayStore.exists(GameSession.osz_path, ver, mode)):
		# Autoplay/Shots speichern sonst nichts: den Lauf fuer den Clip ablegen.
		ReplayStore.save(GameSession.osz_path, ver, core.replay_log, _replay_meta(core.stats()), mode)
	if not ReplayStore.exists(GameSession.osz_path, ver, mode):
		_results_screen.show_toast(tr("Kein gespeichertes Replay für diese Map"), false)
		return
	if _clip_exporter != null and _clip_exporter.is_running():
		_results_screen.show_toast(tr("Clip wird bereits aufgenommen …"), true)
		return
	if _clip_exporter == null:
		_clip_exporter = ClipExporter.new()
		# An der Wurzel: das Umkodieren laeuft weiter, auch nach dem Endbild.
		get_tree().root.add_child(_clip_exporter)
		_clip_exporter.progress_info.connect(func(fraction: float, eta_s: float, phase: String):
			if _results_screen != null and is_instance_valid(_results_screen):
				_results_screen.show_clip_progress(fraction, eta_s, phase))
		_clip_exporter.finished.connect(func(ok: bool, path: String):
			print("CLIP %s %s" % ["OK" if ok else "FEHLER", path])
			if _results_screen != null and is_instance_valid(_results_screen):
				_results_screen.show_clip_result(ok, path, "" if ok else str(_clip_exporter.last_error)))
	var md5 := ReplayStore.key(GameSession.osz_path, ver)
	var out := ClipExporter.clips_dir().path_join("clip_orbit_%s.avi" % md5)
	if _clip_exporter.export_clip(md5, out, mode):
		_results_screen.show_toast(tr("Clip wird aufgenommen …"), true)


# ---------------------------------------------------------------------------
# Shots (Harness)
# ---------------------------------------------------------------------------

func _shot_path(def: String) -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir().path_join(def)


## --shot --shot-at=<ms>: Bild zur Songzeit (Autoplay laeuft dabei mit).
## --shot-results: bis zum Ende spielen lassen (oder springen), dann Results.
func _capture_shot() -> void:
	core._tally.no_fail = true  # Shots: nie scheitern
	var target := float(notes[mini(6, notes.size() - 1)].time_ms) if not notes.is_empty() else 2000.0
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-at="):
			target = _shot_target(a.trim_prefix("--shot-at="), target)
	if OS.get_cmdline_args().has("--shot-pause"):
		await _wait_until(target)
		_toggle_pause(true)
		await get_tree().create_timer(0.6, true).timeout
		await RenderingServer.frame_post_draw
		_save_shot(_shot_path("orbit_pause.png"))
		get_tree().quit(0)
		return
	if OS.get_cmdline_args().has("--shot-results"):
		# Ganze Map (oder bis --shot-at) sofort durchspielen, dann Endscreen.
		# --shot-fail: Scheitern erlaubt (z. B. mit --auto-miss=2).
		var has_at := false
		for a in OS.get_cmdline_args():
			has_at = has_at or a.begins_with("--shot-at=")
		if OS.get_cmdline_args().has("--shot-fail"):
			core._tally.no_fail = false
		var t_end := target if has_at else float(notes[-1].end_ms) + 1000.0
		var t := _time_ms()
		while t < t_end and not bool(core.failed):
			_run_autoplay(t)
			_last_update_t = t
			core.update(t)
			t += 16.0
		_view.t_ms = t
		_show_results(bool(core.failed))
		return
	if target - _time_ms() > 4000.0 and _use_audio:
		# Vorspulen: Wertung neu ab dem Sprungpunkt, damit das Bild keine
		# kuenstlichen Fehler der uebersprungenen Ziele zeigt.
		var cut := _first_note_after(target - 2500.0)
		var rest: Array[OrbitNote] = []
		rest.assign(notes.slice(cut))
		notes = rest
		core.setup(notes, _beatmap.od(), Settings.mania_scroll, _beatmap.hp())
		core._tally.no_fail = true
		_view.setup(notes)
		_auto_idx = 0
		SyncClock.seek_ms(target - 2500.0)
	await _wait_until(target)
	if not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	_save_shot(_shot_path("orbit.png"))
	if OS.get_cmdline_args().has("--shot-bg"):
		# Kontrast-Messung: dasselbe Bild nur mit Hintergrund (Ringe/HUD aus).
		_view.visible = false
		_hud.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save_shot(_shot_path("orbit.png").get_basename() + "_bg.png")
		_view.visible = true
		_hud.visible = true
	for a in OS.get_cmdline_args():
		if a.begins_with("--fps-sec="):
			await _measure_fps(maxf(1.0, a.trim_prefix("--fps-sec=").to_float()))
	get_tree().quit(0)


## --fps-sec=<s> (nach dem Shot, Autoplay laeuft weiter): Frame-Zeiten messen.
func _measure_fps(sec: float) -> void:
	# Ohne VSync/Cap messen: Reserve sichtbar statt Bildschirmtakt.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 10:
		await RenderingServer.frame_post_draw
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var t0 := last
	while Time.get_ticks_usec() - t0 < int(sec * 1000000.0):
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	if times.size() < 2:
		return
	times.remove_at(0)
	var total := 0.0
	for f in times:
		total += f
	var sorted := times.duplicate()
	sorted.sort()
	var mean := total / times.size()
	print("ORBIT-FPS bg=%s theme=%s frames=%d mean=%.2fms fps=%.1f p95=%.2fms worst=%.2fms" % [
		["world", "map", "off"][clampi(_bg.mode, 0, 2)], _bg.world, times.size(), mean,
		1000.0 / maxf(mean, 0.001), sorted[int(sorted.size() * 0.95)], sorted[-1]])


## Zeitpunkt fuer --shot-at: Zahl (ms), "arc" (Bogen mitten im Halten)
## oder "chord" (Akkord kurz vor der Ankunft).
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	if v == "dense":
		# Dichteste Stelle: meiste Ziele in einem Anflug-Fenster.
		var best := -1
		var at := def
		var j := 0
		var win := _preempt()
		for i in notes.size():
			while notes[i].time_ms - notes[j].time_ms > win:
				j += 1
			if notes[j].time_ms >= 8000.0 and i - j > best:
				best = i - j
				at = notes[j].time_ms + 40.0
		return at
	for i in notes.size():
		var n := notes[i]
		if n.time_ms < 8000.0:
			continue
		if v == "arc" and n.is_arc and n.duration_ms() >= 400.0:
			return n.time_ms + n.duration_ms() * 0.45
		if v == "chord" and i + 1 < notes.size() \
				and absf(notes[i + 1].time_ms - n.time_ms) <= OrbitView.CHORD_EPS_MS:
			return n.time_ms - 160.0
	return def


func _first_note_after(t: float) -> int:
	for i in notes.size():
		if float(notes[i].time_ms) >= t:
			return i
	return notes.size()


func _wait_until(target: float) -> void:
	var guard := 0
	while _time_ms() < target and guard < 3600:
		guard += 1
		await get_tree().process_frame
		if not is_inside_tree():
			return


func _save_shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT gespeichert: " + path)


func _capture_results_shot() -> void:
	await get_tree().create_timer(2.6, true).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_save_shot(_shot_path("orbit_results.png"))
	if OS.get_cmdline_args().has("--shot-clip"):
		# Harness: Clip-Knopf ausloesen, auf das fertige Video warten.
		_on_results_clip()
		if _clip_exporter != null and _clip_exporter.is_running():
			await _clip_exporter.finished
	get_tree().quit(0)


## Orbit-Klaenge: Treffer je Ring, Bogen-Halteton + Ende-Klick, leiser Fehlklang.
## Lautstaerke/An-Aus ueber Settings.hitsounds / hitsound_volume. Polyphonie
## begrenzt (Ringpuffer), Klang laeuft synchron zur Wertung (beim Tastendruck).
class OrbitSound extends Node:
	const POLY := 4
	const HIT_DB := -7.0
	const END_DB := -10.0
	const HOLD_DB := -20.0
	const MISS_DB := -15.0
	const PITCH := [1.0, 1.0, 0.944, 0.891, 0.794]
	## Protokoll der ausgeloesten Klaenge: [Art, Ring] (Art: hit, end, miss, hold)
	var log: Array = []
	var _hit: Array = [[], []]
	var _next: Array = [0, 0]
	var _hold: Array = [null, null]
	var _end: AudioStreamPlayer
	var _miss: AudioStreamPlayer

	func _ready() -> void:
		for r in 2:
			for i in POLY:
				_hit[r].append(_mk(Sfx.orbit_hit_stream(r)))
			_hold[r] = _mk(Sfx.orbit_hold_stream(r))
		_end = _mk(Sfx.orbit_end_stream())
		_miss = _mk(Sfx.orbit_miss_stream())

	func _mk(stream: AudioStream) -> AudioStreamPlayer:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		add_child(p)
		return p

	func _on() -> bool:
		return Settings.hitsounds and Settings.hitsound_volume > 0.01

	func _db(base: float) -> float:
		return linear_to_db(Settings.hitsound_volume) + base

	func on_judged(ring: int, q: int, hold_end: bool) -> void:
		ring = clampi(ring, 0, 1)
		if hold_end:
			stop_hold(ring)
			if q == 5:
				_play_miss(ring)
			else:
				_play_end(ring)
		elif q == 5:
			_play_miss(ring)
		else:
			play_hit(ring, PITCH[clampi(q, 0, 4)])

	func on_arc_started(ring: int, q: int) -> void:
		ring = clampi(ring, 0, 1)
		play_hit(ring, PITCH[clampi(q, 0, 4)])
		log.append(["hold", ring])
		if _on() and _hold[ring] != null:
			var p: AudioStreamPlayer = _hold[ring]
			p.volume_db = _db(HOLD_DB)
			p.play()

	func stop_hold(ring: int) -> void:
		var p: AudioStreamPlayer = _hold[ring]
		if p != null and p.playing:
			p.stop()

	func play_hit(ring: int, pitch: float = 1.0) -> void:
		log.append(["hit", ring])
		if not _on() or _hit[ring].is_empty():
			return
		var p: AudioStreamPlayer = _hit[ring][_next[ring]]
		_next[ring] = (_next[ring] + 1) % POLY
		p.volume_db = _db(HIT_DB)
		p.pitch_scale = pitch
		p.play()

	func _play_end(ring: int) -> void:
		log.append(["end", ring])
		if _on() and _end != null:
			_end.volume_db = _db(END_DB)
			_end.play()

	func _play_miss(ring: int) -> void:
		log.append(["miss", ring])
		if _on() and _miss != null:
			_miss.volume_db = _db(MISS_DB)
			_miss.play()


## Online-Score (nur angemeldet, gewerteter Lauf). Asynchron + mit Warteschlange.
func _submit_online(s: Dictionary) -> void:
	var api: OnlineApi = GameSession.online
	if api == null or not api.enabled() or not api.logged_in():
		return
	var meta := OnlineApi.meta_from_beatmap(_beatmap, GameSession.osz_path,
		GameSession.osu_filename, float(s.get("stars", -1.0)))
	meta["total_notes"] = notes.size()
	var res := s.duplicate()
	res["date"] = Time.get_datetime_string_from_system(true)
	api.submit(res, meta, "orbit")
