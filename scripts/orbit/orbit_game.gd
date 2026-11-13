extends Control

## Orbit-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause,
## Fail, Ende -> Results, Score speichern unter Modus "orbit").
## Darstellung: OrbitView (ein _draw). Logik: OrbitCore/OrbitConverter
## (Task orbit-core). Mania 4K bleibt davon voellig unberuehrt.
##
## Steuerung (Satelliten, docs/modes/orbit_satellit.md): Cursor (Maus/Tablet,
## absolute Position) wird in Feld-Koordinaten umgerechnet (OrbitView
## screen_to_field); Taste A / B = Settings.orbit_key_inner / orbit_key_outer
## oder Maus links / rechts, Akzent = beide.
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
## Bot: groesster Zeitschritt fuer Cursor-Updates (ms).
const BOT_STEP_MS := 8.0
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
## Bot: Tasten-Ereignisse [t, down, k] (zeitlich sortiert), naechstes Ereignis,
## Wegpunkte [Ankunft, Abgang, Index, Versatz] fuer den Cursor, zuletzt
## gerechnete Zeit.
var _bot_keys: Array = []
var _bot_key_idx := 0
var _bot_way: Array = []
var _bot_t := -INF
var _bot_down: Array[bool] = [false, false]
var _countdown_running := false
var _song_len_ms := 1.0
## Cursor in Feld-Koordinaten, Zielradius (Feld) dieser Map, Orbit-Sterne.
var _cursor_p := Vector2(0.5, 0.5)
var _radius := OrbitCore.DEFAULT_TARGET_RADIUS
var _stars := 0.0
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
var _top_bg: ColorRect
var _title_label: Label
var _tag_label: Label
var _stat_left: VBoxContainer
var _stat_right: VBoxContainer
## HUD-Schriften [Label, Groesse bei 720 px Hoehe]: skalieren mit der Fensterhoehe.
var _hud_fonts: Array = []
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
## Je gewertetem Ziel ein Eintrag fuer OrbitResults: OrbitResults.entry(note, result,
## Cursor beim Druck) (neuer Endscreen), sonst [Feld-Pos, Taste, dt, Zielfehler
## (Feld x 100), Stufe, Zeit] (alter Endscreen).
var _hit_log: Array = []
## Fehldrucke je Grund (aim/key/early/lock) fuer die Tasten-Statistik.
var _presses := {"aim": 0, "key": 0, "early": 0, "lock": 0}
## Halten: Cursor beim Kopf-Druck (Index -> Feld-Pos).
var _hold_cursor := {}
## OrbitResults.entry vorhanden (neuer Endscreen)? null = noch nicht geprueft.
static var _has_entry = null
var _mp_send_cd := 0.0
var _mods_label: Label
## Replay-Wiedergabe: Events (OrbitCore.EV_*), naechster Index, Endzeit des Laufs.
var _replay := false
var _replay_events: Array = []
var _replay_idx := 0
var _replay_end_ms := -1.0
var _replay_down: Array[bool] = [false, false]
## Replay aus einer aelteren Orbit-Version (meta orbit_rules < 3): nicht abspielbar.
var _replay_old := false
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
		# Menschlicher Bot: --auto-jitter=<ms> --auto-aim=<Feld x 100> --auto-seed=<n>.
		_bot_plan = OrbitCore.bot_plan(notes, seed, jitter, aim, _auto_miss)
		_bot_build()
	_beat.setup(_beatmap.timing_points)
	_intensity.build(_beatmap)
	_build_bg()
	_view = OrbitView.new()
	add_child(_view)
	_view.setup(notes)
	_view.clock = OrbitClock.from_beatmap(_beatmap)
	_view.target_radius = core.target_radius
	_view.key_hint = key_hint_on(Settings.orbit_key_hint, _stars, GameSession.tutorial)
	_view.key_labels = [UiTheme.key_short(Settings.orbit_key_inner), UiTheme.key_short(Settings.orbit_key_outer)]
	_view.music = Settings.orbit_music
	_view.size_k = clampf(float(setting("orbit_target_size", 100)) / 100.0, 0.9, 1.2)
	_view.cursor_k = clampf(float(setting("orbit_cursor_size", 100)) / 100.0, 0.5, 1.5)
	_view.mod_hidden = bool(core.mods.get("HD", false))
	_view.mod_fade_in = bool(core.mods.get("FI", false))
	_view.show_cursor = true
	_view.show_stage = true
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
			if not await _sleep(0.45):
				return
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
	if not await _sleep(3.5):
		return
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
		var need := _first_lead() + 900.0
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
	if notes.is_empty():
		notes = OrbitConverter.convert(_beatmap, int(setting("orbit_laps", 0)))
	_radius = OrbitConverter.target_radius(_beatmap)
	_stars = OrbitConverter.stars(notes)
	core = OrbitCore.new()
	core.setup(notes, _beatmap.od(), null, _radius, _beatmap.hp())
	core.note_judged.connect(_on_note_judged)
	core.hold_started.connect(_on_hold_started)
	core.press_missed.connect(_on_press_missed)
	core.finished.connect(func(_s): _show_results(false))
	# Immer deterministisch (Wertung unabhaengig von der Bildrate); live mitschreiben.
	core.set_replay_mode(not GameSession.is_replay)
	_w300 = core.w300


## Vorlauf der ersten Note (Erscheinen bis Treffer) in ms.
func _first_lead() -> float:
	if notes.is_empty():
		notes = OrbitConverter.convert(_beatmap, int(setting("orbit_laps", 0)))
	if notes.is_empty():
		return 2000.0
	return float(notes[0].time_ms) - float(notes[0].spawn_ms)


## Einstellung mit Rueckfall (neue Namen kommen mit dem Settings-Umbau).
static func setting(name: String, def):
	var v = Settings.get(name)
	return def if v == null else v


## Taste im naechsten Ziel: Settings.orbit_key_hint 0 = auto (Maps < 6 Sterne,
## Tutorial), 1 = an, 2 = aus.
static func key_hint_on(mode: int, stars: float, tutorial: bool) -> bool:
	match mode:
		1:
			return true
		2:
			return false
	return tutorial or stars < 6.0


func _time_ms() -> float:
	if _use_audio:
		return SyncClock.judgement_time_ms()
	if not _debug_running:
		return 0.0
	return float(Time.get_ticks_usec() - _debug_start_usec) / 1000.0 - 1000.0


## Scroll Speed (F3/F4, Pausenmenue): Orbit hat keine Anflugzeit (Runden aus AR).
func apply_scroll_speed(_speed: int) -> void:
	pass


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
	# Kein Welt-Himmel hinter dem Feld (keine Planeten/Deko): "Welt" = Map-Bild wie
	# osu!, unscharf und stark abgedunkelt (Einstellungen der Modi-Hintergruende).
	var bg_mode := Settings.orbit_background_mode()
	if bg_mode == OrbitBackdrop.BG_WORLD:
		bg_mode = OrbitBackdrop.BG_MAP
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	# Map-Bild: MapBackdrop (Unschaerfe Settings.modes_bg_blur, Deckkraft modes_bg_dim).
	_bg.setup(_beatmap, bg_mode, forced, GameSession.stars, cover, float(Settings.modes_bg_dim))


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
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	_shadow(title)
	title.modulate.a = 0.8
	_hud.add_child(title)
	_title_label = title
	_hud_fonts.append([title, 14])
	var mode_tag := Label.new()
	mode_tag.text = tr("ORBIT")
	mode_tag.add_theme_font_override("font", UiTheme.heading_font(3))
	mode_tag.add_theme_color_override("font_color", Color(UiTheme.ACCENT, 0.9))
	_hud.add_child(mode_tag)
	_tag_label = mode_tag
	_hud_fonts.append([mode_tag, 11])
	var ttw := create_tween()
	ttw.tween_interval(8.0)
	ttw.tween_property(title, "modulate:a", 0.4, 1.5)

	_time_label = Label.new()
	_time_label.anchor_left = 1.0
	_time_label.anchor_right = 1.0
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_color_override("font_color", UiTheme.DIM)
	_time_label.add_theme_font_override("font", _tabular_font(_time_label))
	_shadow(_time_label)
	_hud.add_child(_time_label)
	_hud_fonts.append([_time_label, 14])

	_top_bg = ColorRect.new()
	_top_bg.anchor_right = 1.0
	_top_bg.color = Color(UiTheme.TEXT, 0.08)
	_top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_bg)
	_top_fill = ColorRect.new()
	_top_fill.anchor_right = 0.0
	_top_fill.color = Color(UiTheme.ACCENT, 0.85)
	_top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_top_fill)

	# Werte in den Seitenstreifen neben der Buehne, vertikal mittig: links
	# Punkte und Genauigkeit, rechts der Rang (ruhig, nie im Feld).
	_stat_left = _stat_column()
	_score_label = _stat_block(_stat_left, tr("PUNKTE"), 30)
	_acc_label = _stat_block(_stat_left, tr("GENAUIGKEIT"), 30)
	_stat_right = _stat_column()
	_grade_label = _stat_block(_stat_right, tr("RANG"), 52)
	_grade_label.add_theme_font_override("font", UiTheme.heading_font(0))

	_hp_bar = HpBar.new()
	_hp_bar.label_text = "HP"
	_hud.add_child(_hp_bar)
	_hp_bar.setup(theme_col)

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
		_mods_label.add_theme_font_override("font", UiTheme.heading_font(3))
		_mods_label.add_theme_color_override("font_color", UiTheme.DIM)
		_hud.add_child(_mods_label)
		_hud_fonts.append([_mods_label, 11])

	_build_legend()

	_break_ov = BreakOverlay.new()
	_hud.add_child(_break_ov)
	_build_breaks()
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


## Tasten-Legende unter dem Feld (nur bis kurz vor der ersten Note).
func _build_legend() -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 30)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_legend = box
	_hud.add_child(box)
	var ka := UiTheme.key_short(Settings.orbit_key_inner)
	var kb := UiTheme.key_short(Settings.orbit_key_outer)
	var items := [
		[OrbitNote.KEY_A, tr("Taste %s") % ka],
		[OrbitNote.KEY_B, tr("Taste %s") % kb],
		[OrbitNote.KEY_ACCENT, tr("beide")],
	]
	for it in items:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(item)
		var key: int = it[0]
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(18, 18)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_legend_icon.bind(icon, key))
		item.add_child(icon)
		var l := Label.new()
		l.text = it[1]
		_hud_fonts.append([l, 15])
		var col: Color = UiTheme.TEXT if key == OrbitNote.KEY_ACCENT else OrbitView.key_col(key)
		l.add_theme_color_override("font_color", col.lerp(UiTheme.TEXT, 0.35))
		_shadow(l)
		item.add_child(l)
	var keys := Label.new()
	keys.text = tr("Zielen und drücken, wenn der Satellit oben ankommt (auch Maus links/rechts)")
	_hud_fonts.append([keys, 15])
	keys.add_theme_color_override("font_color", UiTheme.DIM.lerp(UiTheme.TEXT, 0.5))
	_shadow(keys)
	box.add_child(keys)


func _legend_icon(icon: Control, key: int) -> void:
	var p := icon.size * 0.5
	if key == OrbitNote.KEY_B:
		icon.draw_rect(Rect2(p - Vector2(6.5, 6.5), Vector2(13, 13)), OrbitView.B_COL)
	elif key == OrbitNote.KEY_ACCENT:
		icon.draw_circle(p, 7.5, Color.WHITE, true, -1.0, true)
		icon.draw_circle(p, 6.0, OrbitView.A_COL, true, -1.0, true)
		icon.draw_rect(Rect2(p.x, p.y - 6.0, 6.0, 12.0), OrbitView.B_COL)
	else:
		icon.draw_circle(p, 7.0, OrbitView.A_COL, true, -1.0, true)


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
	# Alles skaliert mit der Fensterhoehe (720 px = 1).
	var u := vs.y / 720.0
	for e in _hud_fonts:
		(e[0] as Label).add_theme_font_size_override("font_size", maxi(8, roundi(float(e[1]) * u)))
	_err_bar.pivot_offset = Vector2(_err_bar.size.x * 0.5, _err_bar.size.y)
	_err_bar.scale = Vector2(u, u)
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5, vs.y - _err_bar.size.y - 10.0 * u)
	_legend.size = Vector2(vs.x, 24.0 * u)
	_legend.position = Vector2(0, vs.y * 0.885)
	_title_label.position = Vector2(24, 13) * u
	_tag_label.position = Vector2(24, 34) * u
	if _mods_label != null:
		_mods_label.position = Vector2(24, 50) * u
	_time_label.offset_left = -260.0 * u
	_time_label.offset_right = -24.0 * u
	_time_label.offset_top = 13.0 * u
	var bar_h := maxf(3.0, roundf(3.0 * u))
	_top_bg.offset_bottom = bar_h
	_top_fill.offset_bottom = bar_h
	_hp_bar.position = Vector2(vs.x * 0.5 - 160.0, 8.0 * u)
	_hp_bar.size = Vector2(320, 24)
	_hp_bar.pivot_offset = Vector2(160, 0)
	_hp_bar.scale = Vector2(u, u)
	# Seitenstreifen: Mitte zwischen Fensterrand und Buehne; ohne Streifen
	# (schmales Fenster) wie bisher bei 11 % / 89 %.
	var fh := vs.y * OrbitView.FIELD_H_K
	var fw := minf(fh * OrbitView.ASPECT, vs.x * 0.96)
	var gut := maxf((vs.x - fw) * 0.5 - fh * OrbitView.STAGE_PAD_K, 0.0)
	var cx := gut * 0.5 if gut >= 190.0 * u else vs.x * 0.11
	_stat_place(_stat_left, cx, u)
	_stat_place(_stat_right, vs.x - cx, u)


func _stat_column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(v)
	return v


func _stat_place(v: VBoxContainer, cx: float, u: float) -> void:
	v.add_theme_constant_override("separation", roundi(26.0 * u))
	v.reset_size()
	var sz := v.get_combined_minimum_size()
	v.size = Vector2(maxf(sz.x, 240.0 * u), sz.y)
	v.position = Vector2(cx - v.size.x * 0.5, (get_viewport().get_visible_rect().size.y - sz.y) * 0.5)


func _stat_block(column: VBoxContainer, caption: String, size_px: int) -> Label:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 0)
	column.add_child(block)
	var cap := Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", UiTheme.heading_font(2))
	cap.add_theme_color_override("font_color", UiTheme.DIM)
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cap.add_theme_constant_override("shadow_outline_size", 5)
	block.add_child(cap)
	_hud_fonts.append([cap, 11])
	var val := Label.new()
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", UiTheme.TEXT)
	val.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	val.add_theme_constant_override("shadow_outline_size", 6)
	val.add_theme_font_override("font", _tabular_font(val))
	block.add_child(val)
	_hud_fonts.append([val, size_px])
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

## Bildschirm (Viewport-Pixel) -> Feld.
func _px_to_field(px: Vector2) -> Vector2:
	return _view.screen_to_field(_view.get_global_transform_with_canvas().affine_inverse() * px)


func _set_cursor_from(px: Vector2, t: float) -> void:
	_cursor_p = _px_to_field(px)
	_view.cursor = _cursor_p
	core.cursor_moved(_cursor_p, t)


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
		core.key_down(key, t)
	else:
		core.key_up(key, t)
	_sync_held_view()


## Cursor-Punkt zeigt gedrueckte Tasten.
func _sync_held_view() -> void:
	for k in 2:
		_view.held[k] = _held[k][0] or _held[k][1] or _bot_down[k] or _replay_down[k]


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


## Bot-Plan aufbauen: Wegpunkte fuer den Cursor und Tasten-Ereignisse. Der
## Cursor gleitet (smoothstep) vom letzten Ziel zum naechsten und kommt kurz
## vor der Trefferzeit an; beim Halten folgt er der Kugel. Taps 40 ms gedrueckt,
## Akzente beide Tasten zugleich, Halten bis zum Ende. Rein aus notes und
## _bot_plan berechnet (gleiche Eingaben bei jeder Bildrate).
func _bot_build() -> void:
	_bot_way = []
	_bot_keys = []
	_bot_key_idx = 0
	_bot_t = -INF
	_bot_down = [false, false]
	var per_key: Array = [[], []]
	for i in notes.size():
		if _bot_skip(i):
			continue
		var n := notes[i]
		var nt := float(n.time_ms) + _bot_dt(i)
		var off := OrbitCore.bot_offset(i, _bot_aim(i))
		var leave := nt
		var up := nt + AUTO_TAP_MS
		if n.is_hold:
			leave = float(n.end_ms) + _bot_dt(i) * 0.5
			up = leave + 5.0
		_bot_way.append([nt, leave, i, off])
		var ks := [0, 1] if n.key == OrbitNote.KEY_ACCENT else [clampi(n.key, 0, 1)]
		for k in ks:
			per_key[k].append([nt, up])
	_bot_way.sort_custom(func(a, b): return a[0] < b[0])
	for k in 2:
		var lst: Array = per_key[k]
		lst.sort_custom(func(a, b): return a[0] < b[0])
		for j in lst.size():
			var dn: float = lst[j][0]
			var up: float = lst[j][1]
			if j + 1 < lst.size():
				up = minf(up, float(lst[j + 1][0]) - 1.0)
			up = maxf(up, dn + 1.0)
			_bot_keys.append([dn, true, k])
			_bot_keys.append([up, false, k])
	# Loslassen vor Druecken bei gleicher Zeit.
	_bot_keys.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return (not a[1]) and b[1])


## Bot-Cursor (Feld) zur Zeit t.
func bot_cursor(t: float) -> Vector2:
	if _bot_way.is_empty():
		return Vector2(0.5, 0.5)
	# Letzter Wegpunkt mit Ankunft <= t (binaere Suche).
	var lo := 0
	var hi := _bot_way.size() - 1
	var k := -1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if float(_bot_way[mid][0]) <= t:
			k = mid
			lo = mid + 1
		else:
			hi = mid - 1
	var from_t := -INF
	var from_p := Vector2(0.5, 0.5)
	if k >= 0:
		var w: Array = _bot_way[k]
		var n := notes[int(w[2])]
		if t <= float(w[1]):
			return n.pos_at(t - (float(w[0]) - float(n.time_ms))) + w[3]
		from_t = float(w[1])
		from_p = OrbitConverter.end_pos(n) + w[3]
	if k + 1 >= _bot_way.size():
		return from_p
	var nw: Array = _bot_way[k + 1]
	var to_p: Vector2 = notes[int(nw[2])].pos + nw[3]
	var arrive := float(nw[0])
	if from_t == -INF:
		from_t = arrive - 900.0
	var gap := arrive - from_t
	arrive -= clampf(gap * 0.22, 0.0, 70.0)
	var start := from_t + clampf(gap * 0.05, 0.0, 25.0)
	if t >= arrive:
		return to_p
	if t <= start:
		return from_p
	var u := (t - start) / maxf(arrive - start, 1.0)
	return from_p.lerp(to_p, u * u * (3.0 - 2.0 * u))


## Autoplay bis t: in Schritten <= BOT_STEP_MS (Cursor folgt Kugeln auch bei
## langsamen Frames), Tasten-Ereignisse exakt zu ihrer Zeit.
func _run_autoplay(t: float) -> void:
	if _bot_t == -INF:
		_bot_t = t
	var s := _bot_t
	while true:
		var step_to := minf(s + BOT_STEP_MS, t)
		while _bot_key_idx < _bot_keys.size() and float(_bot_keys[_bot_key_idx][0]) <= step_to:
			var ev: Array = _bot_keys[_bot_key_idx]
			_bot_key_idx += 1
			var te := float(ev[0])
			var k := int(ev[2])
			core.cursor_moved(bot_cursor(te), te)
			if bool(ev[1]):
				core.key_down(k, te)
			else:
				core.key_up(k, te)
			_bot_down[k] = bool(ev[1])
		core.cursor_moved(bot_cursor(step_to), step_to)
		s = step_to
		if s >= t:
			break
	_bot_t = t
	_cursor_p = bot_cursor(t)
	_view.cursor = _cursor_p
	_sync_held_view()


func _bot_dt(i: int) -> float:
	return float(_bot_plan[i][0]) if i < _bot_plan.size() else 0.0


func _bot_aim(i: int) -> float:
	return float(_bot_plan[i][1]) if i < _bot_plan.size() else 0.0


func _bot_skip(i: int) -> bool:
	if i < _bot_plan.size():
		return bool(_bot_plan[i][2])
	return _auto_miss > 0 and i % _auto_miss == _auto_miss - 1


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
	_fade_hud_over_targets(t, delta)
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
	var warn := {}
	for i in core.active_holds():
		warn[i] = core.hold_out_ms(i, t) / OrbitCore.HOLD_OUT_MS
	_view.hold_warn = warn
	# Takt-Puls der Orbit-Ringe: in ruhigen Stellen schwaecher, Takt-Eins staerker.
	_beat.update(t, delta)
	var env := _beat.beat_env * (0.35 + 0.65 * _intensity.value_at(t))
	_view.beat_env = env
	_view.downbeat = _beat.bar_phase < 0.125
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
		if code == OrbitCore.EV_CURSOR and ev.size() >= 4:
			_cursor_p = Vector2(float(ev[2]), float(ev[3])) / 1000.0
			_view.cursor = _cursor_p
		elif code >= OrbitCore.EV_DOWN and code < OrbitCore.EV_DOWN + OrbitCore.KEYS:
			_replay_down[code - OrbitCore.EV_DOWN] = true
		elif code >= OrbitCore.EV_UP and code < OrbitCore.EV_UP + OrbitCore.KEYS:
			_replay_down[code - OrbitCore.EV_UP] = false
	_sync_held_view()


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
		var cur: Vector2 = _hold_cursor.get(index, core.cursor_pos())
		_hold_cursor.erase(index)
		_hit_log.append(log_entry(n, result, cur))
	_check_milestone(q)
	var hold_end := bool(result.get("hold_end", false))
	var snd_key := notes[index].key if index >= 0 and index < notes.size() else 0
	_sound.on_judged(snd_key, q, hold_end)
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


## Fehldruck: kurzes Wort am Cursor ("daneben", "andere Taste"), Notelock wackelt.
func _on_press_missed(pos: Vector2, key: int, reason: String) -> void:
	if _presses.has(reason):
		_presses[reason] = int(_presses[reason]) + 1
	_view.on_press_missed(pos, key, reason)


## Log-Eintrag: OrbitResults.entry, wenn der neue Endscreen da ist, sonst altes Format.
static func log_entry(n: OrbitNote, result: Dictionary, cursor: Vector2):
	if _has_entry == null:
		_has_entry = false
		var sc: Script = OrbitResults
		for m in sc.get_script_method_list():
			if str(m.get("name", "")) == "entry":
				_has_entry = true
				break
	if _has_entry:
		var sc: Script = OrbitResults
		return sc.call("entry", n, result, cursor)
	return [n.pos, n.key, float(result.get("dt", 0.0)),
		float(result.get("aim_err", 0.0)) * 100.0, int(result.get("quality", 5)), n.time_ms]


func _on_hold_started(index: int, quality: int) -> void:
	_hold_cursor[index] = core.cursor_pos()
	_view.on_hold_started(index, quality)
	if index >= 0 and index < notes.size():
		_sound.on_arc_started(notes[index].key, quality)


## Kombo-Meilensteine (50, 100, 200 ...): nur Klang, nie grell.
func _check_milestone(q: int) -> void:
	if q == 5:
		_last_milestone = 0
		return
	var c := int(core.combo)
	if (c == 50 or (c >= 100 and c % 100 == 0)) and c != _last_milestone:
		_last_milestone = c
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


## Echtzeit warten (auch bei pausiertem Tree). false = Szene ist inzwischen weg (oder
## war es schon): der Aufrufer bricht ab. Vorher: "Cannot call method 'create_timer'
## on a null value", wenn eine Shot-/Endbild-Folge nach dem Szenenwechsel weiterlief.
func _sleep(sec: float) -> bool:
	if not is_inside_tree():
		return false
	await get_tree().create_timer(sec, true).timeout
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
		"radius": float(core.target_radius),
		"presses": _presses.duplicate(),
		"key_names": _view.key_labels.duplicate(),
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
	if not is_inside_tree():
		return
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
		if not await _sleep(back_s):
			return
		if is_inside_tree():
			_back_to_browser()


## Meta fuer ReplayStore (Mods: Wiedergabe mit denselben Mods; end_ms: Ende des Laufs).
func _replay_meta(s: Dictionary) -> Dictionary:
	return {
		"score": int(s.score), "grade": str(s.grade), "accuracy": float(s.accuracy),
		"date": Time.get_datetime_string_from_system(), "mods": core.mods.duplicate(),
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
		if not is_inside_tree():
			return
		_toggle_pause(true)
		if not await _sleep(0.6):
			return
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
		core.setup(notes, _beatmap.od(), null, _radius, _beatmap.hp())
		core.set_replay_mode(true)
		core._tally.no_fail = true
		_view.setup(notes)
		if _autoplay:
			_bot_plan = _bot_plan.slice(cut)
			_bot_build()
		SyncClock.seek_ms(target - 2500.0)
	if await _movie_hold(target):
		return
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


## Debug (Demo-Videos): --movie-len=<s> mit --shot --shot-at=<ms> --write-movie:
## druckt MOVIE_START frame=<n> (Filmbeginn) und beendet nach <s> Film-Sekunden.
func _movie_hold(_target: float) -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("--movie-len="):
			print("MOVIE_START frame=%d" % Engine.get_process_frames())
			if not await _sleep(a.trim_prefix("--movie-len=").to_float()):
				return
			get_tree().quit(0)
			return true
	return false


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


## Zeitpunkt fuer --shot-at: Zahl (ms) oder eine Stelle der Map (ab 8 s):
## "hold"/"arc" (mitten im Halten), "hold-in" (kurz vor einem Halten-Kopf),
## "accent"/"chord" (kurz vor einem Akzent), "stream" (Anfang der ersten
## Folge von 6 Zielen mit <= 200 ms Abstand), "jump" (groesster Sprung je
## Zeit), "dense" (meiste sichtbare Ziele), "kiai" (1,5 s im ersten Kiai).
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	var from := 8000.0
	match v:
		"dense":
			var best := -1
			var at := def
			for i in notes.size():
				if notes[i].time_ms < from:
					continue
				var t := float(notes[i].time_ms) - 60.0
				var c := 0
				for n in notes:
					if n.spawn_ms <= t and n.end_ms >= t:
						c += 1
				if c > best:
					best = c
					at = t
			return at
		"stream":
			for i in notes.size():
				if notes[i].time_ms < from or i + 6 >= notes.size():
					continue
				var ok := true
				for k in range(i, i + 5):
					ok = ok and notes[k + 1].time_ms - notes[k].time_ms <= 200.0
				if ok:
					return notes[i].time_ms - 90.0
			return def
		"jump":
			var best := 0.0
			var at := def
			for i in range(1, notes.size()):
				var n := notes[i]
				var dt := maxf(float(n.time_ms) - float(notes[i - 1].end_ms), 60.0)
				var d := OrbitConverter.end_pos(notes[i - 1]).distance_to(n.pos)
				if n.time_ms >= from and d / dt > best:
					best = d / dt
					at = float(n.time_ms) - 120.0
			return at
	if v == "kiai":
		for tp in _beatmap.timing_points:
			if (tp.kiai or (tp.effects & 1) != 0) and tp.time >= from:
				return tp.time + 1500.0
		return def
	for i in notes.size():
		var n := notes[i]
		if n.time_ms < from:
			continue
		if v in ["arc", "hold"] and n.is_hold and n.end_ms - n.time_ms >= 400.0:
			return n.time_ms + (n.end_ms - n.time_ms) * 0.45
		if v == "hold-in" and n.is_hold and n.end_ms - n.time_ms >= 400.0:
			return n.time_ms - 0.4 * n.lap_ms
		if v in ["accent", "chord"] and n.key == OrbitNote.KEY_ACCENT:
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
	if not await _sleep(2.6):
		return
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


## Kombo/Wertung unten mittig liegen im Spielfeld: kommt dort in den naechsten
## 1,5 s ein Ziel, blendet die Anzeige weich auf 20 % aus (wie das osu!-HUD).
func _fade_hud_over_targets(t: float, delta: float) -> void:
	if _judge_disp == null or _view == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var r := _view.radius_px() * 1.4
	var zone := Rect2(Vector2(vs.x * 0.36, vs.y * 0.78), Vector2(vs.x * 0.28, vs.y * 0.22)).grow(r)
	var covered := false
	var i := maxi(_view.next_index(), 0)
	var notes: Array = _view.notes
	while i < notes.size():
		var n: OrbitNote = notes[i]
		if n.time_ms > t + 1500.0:
			break
		if zone.has_point(_view.field_to_screen(n.pos)):
			covered = true
			break
		i += 1
	var target := 0.2 if covered else 1.0
	var a := _judge_disp.modulate.a
	_judge_disp.modulate.a = move_toward(a, target, delta * 4.0)

