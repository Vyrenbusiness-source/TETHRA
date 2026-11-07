extends Control

## Orbit-Modus: Spielablauf (Map laden, Audio + SyncClock, Eingabe, Pause,
## Fail, Ende -> Results, Score speichern unter Modus "orbit").
## Darstellung: OrbitView (ein _draw). Logik: OrbitCore/OrbitConverter
## (Task orbit-core). Mania 4K bleibt davon voellig unberuehrt.
##
## Steuerung: Cursor-Winkel zur Mitte = Richtung; Ring-Taste innen
## (Maus links / Settings.orbit_key_inner) bzw. aussen (Maus rechts /
## Settings.orbit_key_outer). Tablet = absolute Mausposition.
## CLI: --orbit --autoplay (Autoplay), --shot --shot-at=<ms> --shot-out=<png>,
## --auto-miss=<n> (Autoplay laesst jede n-te Note aus, fuer Fehltreffer-Shots).

const MODE := "orbit"
const AUTO_TAP_MS := 40.0
## Groesse von Judge + Kombo relativ zu Mania (bei 720 px Hoehe).
const JUDGE_SCALE := 0.5
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.85, 0.40), "A": Color(0.45, 0.95, 0.55),
	"B": Color(0.45, 0.70, 1.0), "C": Color(0.80, 0.55, 1.0), "D": Color(1.0, 0.45, 0.45),
}
const HIT_DB := -7.0
const MISS_DB := -6.0

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
var _auto_from_deg := 0.0
var _auto_from_t := 0.0
var _countdown_running := false
var _song_len_ms := 1.0
var _cursor_deg := 0.0
## Haltequellen pro Ring: [Maus, Taste].
var _held := [[false, false], [false, false]]
var _w300 := 49.5

var _bg: TextureRect
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
var _results_screen: ResultsScreen
var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer
var _hit_offsets := PackedFloat32Array()
var _acc_trace := PackedFloat32Array()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _load_beatmap():
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	_autoplay = OS.get_cmdline_args().has("--autoplay") and not Lobby.active
	for a in OS.get_cmdline_args():
		if a.begins_with("--auto-miss="):
			_auto_miss = maxi(0, a.trim_prefix("--auto-miss=").to_int())
	_build_core()
	_build_bg()
	_view = OrbitView.new()
	add_child(_view)
	_view.setup(notes)
	_view.preempt = _preempt()
	_view.show_guides = Settings.orbit_guides
	_view.tol_deg = _tolerance()
	_build_sound()
	_build_hud()
	if not _use_audio:
		_debug_start_usec = Time.get_ticks_usec()
		_debug_running = true
	if DisplayServer.get_name() == "headless":
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


func _load_beatmap() -> bool:
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
	if _beatmap == null or _beatmap.hit_objects.is_empty() or not _beatmap.is_mania():
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


## Logik laden: OrbitConverter macht aus der Mania-Map die Ziele, OrbitCore
## wertet (NF liest OrbitCore selbst aus GameSession.mods).
func _build_core() -> void:
	notes = OrbitConverter.convert(_beatmap)
	core = OrbitCore.new()
	core.setup(notes, _beatmap.od(), Settings.mania_scroll, _beatmap.hp())
	core.note_judged.connect(_on_note_judged)
	core.arc_started.connect(_on_arc_started)
	core.finished.connect(func(_s): _show_results(false))
	_w300 = core.w300


func _preempt() -> float:
	return ManiaCore.preempt_for(Settings.mania_scroll)


func _tolerance() -> float:
	return OrbitCore.ANGLE_TOL_DEG


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
	var black := ColorRect.new()
	black.color = Color(0.008, 0.01, 0.018)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var tex := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if tex == null:
		return
	_bg = TextureRect.new()
	_bg.texture = tex
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Settings.bg_dim = Deckkraft des Map-Bilds (0 = aus).
	_bg.modulate = Color(1, 1, 1, Settings.bg_dim)
	_bg.visible = Settings.bg_dim > 0.001
	add_child(_bg)


func _build_sound() -> void:
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = HIT_DB
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	_miss_player.volume_db = MISS_DB
	add_child(_miss_player)


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
	_grade_label = _stat_block(left, tr("RANG"), 26)
	_acc_label = _stat_block(left, tr("GENAUIGKEIT"), 28)
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
	_judge_disp.window_300_ms = _w300

	_build_legend()

	_break_ov = BreakOverlay.new()
	_hud.add_child(_break_ov)
	_build_breaks()
	_place_hud()
	get_viewport().size_changed.connect(_place_hud)


## Ring-Legende unter dem Feld (nur bis kurz vor der ersten Note).
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
		var ring := r
		icon.draw.connect(func():
			var p := icon.size * 0.5
			if ring == 0:
				icon.draw_circle(p, 7.0, Color(col.darkened(0.6), 0.95), true, -1.0, true)
				icon.draw_arc(p, 7.0, 0.0, TAU, 24, col, 2.0, true)
			else:
				var pts := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0), p + Vector2(0, -8)])
				icon.draw_colored_polygon(pts.slice(0, 4), Color(col.darkened(0.6), 0.95))
				icon.draw_polyline(pts, col, 2.0, true))
		item.add_child(icon)
		var l := Label.new()
		var key := UiTheme.key_short(Settings.orbit_key_outer if r == 1 else Settings.orbit_key_inner)
		var mouse := tr("Maus rechts") if r == 1 else tr("Maus links")
		l.text = "%s   %s · %s" % [tr("Außen") if r == 1 else tr("Innen"), key, mouse]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
		_shadow(l)
		item.add_child(l)


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
	# Judge knapp unter der Mitte, Kombo knapp darueber (innerhalb des inneren Rings).
	# Kleiner als in Mania: alles bleibt im dunklen Kern innerhalb der
	# Entstehungszone der Ziele (Skalierung um die Bildschirmmitte).
	var k := JUDGE_SCALE * vs.y / 720.0
	_judge_disp.pivot_offset = vs * 0.5
	_judge_disp.scale = Vector2(k, k)
	_judge_disp.judge_gap = 0.0
	_judge_disp.combo_gap = vs.y * 0.05 / k
	_judge_disp.place(cy + vs.y * 0.026 / k)
	var r_out := vs.y * OrbitView.R_OUTER_K
	_err_bar.position = Vector2((vs.x - _err_bar.size.x) * 0.5,
		minf(cy + r_out + vs.y * 0.045, vs.y - _err_bar.size.y - 8.0))
	_legend.size = Vector2(vs.x, 24)
	_legend.position = Vector2(0, cy + r_out + vs.y * 0.075)


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
	var c := _view_center()
	_view.cursor_pos = pos
	# Totzone: ganz in der Mitte bleibt der letzte Winkel stehen (kein Zappeln).
	var inside := pos.distance_to(c) < _view.deadzone_radius()
	_view.cursor_in_deadzone = inside
	if inside:
		return
	_cursor_deg = OrbitView.angle_of(c, pos)
	_view.cursor_deg = _cursor_deg
	core.cursor_moved(_cursor_deg, t)


func _input(event: InputEvent) -> void:
	if _ended or _autoplay or core == null:
		return
	if event is InputEventMouseMotion:
		_set_cursor_from(event.position, _time_ms())
	elif event is InputEventMouseButton:
		var ring := -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			ring = 0
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			ring = 1
		if ring >= 0:
			_set_cursor_from(event.position, _time_ms())
			_press(ring, 0, event.pressed)
	elif event is InputEventKey and not event.echo:
		var ring := Settings.orbit_ring_for_key(event.keycode)
		if ring >= 0:
			_press(ring, 1, event.pressed)


## Ring gedrueckt/losgelassen ueber eine Quelle (0 Maus, 1 Taste): der Core
## sieht nur den Uebergang "keine Quelle" <-> "mindestens eine".
func _press(ring: int, source: int, down: bool) -> void:
	if get_tree().paused or _countdown_running:
		return
	var was: bool = _held[ring][0] or _held[ring][1]
	_held[ring][source] = down
	var now: bool = _held[ring][0] or _held[ring][1]
	_view.ring_held[ring] = now
	if now == was:
		return
	var t := _time_ms()
	if now:
		core.key_down(ring, t, _cursor_deg)
	else:
		core.key_up(ring, t)


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
		_do_skip()


## Autoplay: Taste exakt zur Trefferzeit auf dem exakten Winkel; Boegen
## werden bis end_ms gehalten und der Cursor folgt der Spitze. Zwischen den
## Zielen gleitet der Cursor ruhig zum naechsten Winkel (nur Anzeige).
func _run_autoplay(t: float) -> void:
	for r in 2:
		if _auto_release[r] >= 0.0 and _auto_release[r] <= t:
			var rel := _auto_release[r]
			if _auto_arc[r] >= 0:
				_auto_cursor(float(notes[_auto_arc[r]].end_angle_deg), rel)
				_auto_from_deg = float(notes[_auto_arc[r]].end_angle_deg)
				_auto_from_t = rel
			core.key_up(r, rel)
			_view.ring_held[r] = false
			_auto_release[r] = -1.0
			_auto_arc[r] = -1
	while _auto_idx < notes.size() and float(notes[_auto_idx].time_ms) <= t:
		var i := _auto_idx
		var n = notes[i]
		_auto_idx += 1
		var r: int = n.ring
		var nt := float(n.time_ms)
		if _auto_miss > 0 and i % _auto_miss == _auto_miss - 1:
			continue
		if _auto_release[r] >= 0.0:
			core.key_up(r, minf(_auto_release[r], nt))
			_auto_release[r] = -1.0
			_auto_arc[r] = -1
		_auto_cursor(float(n.angle_deg), nt)
		core.key_down(r, nt, float(n.angle_deg))
		_view.ring_held[r] = true
		_auto_from_deg = float(n.angle_deg)
		_auto_from_t = nt
		if n.is_arc:
			_auto_arc[r] = i
			_auto_release[r] = float(n.end_ms)
		else:
			_auto_release[r] = nt + AUTO_TAP_MS
	# Cursor-Fuehrung fuer dieses Bild.
	for r in 2:
		if _auto_arc[r] >= 0:
			_auto_cursor(notes[_auto_arc[r]].angle_at(t), t)
			return
	if _auto_idx < notes.size():
		var nx = notes[_auto_idx]
		var span := maxf(float(nx.time_ms) - _auto_from_t, 1.0)
		var f := clampf((t - _auto_from_t) / span, 0.0, 1.0)
		f = f * f * (3.0 - 2.0 * f)
		var d := rad_to_deg(angle_difference(deg_to_rad(_auto_from_deg), deg_to_rad(float(nx.angle_deg))))
		_auto_cursor(_auto_from_deg + d * f, t, true)


func _auto_cursor(deg: float, t: float, display_only: bool = false) -> void:
	_cursor_deg = fposmod(deg, 360.0)
	_view.cursor_deg = _cursor_deg
	_view.cursor_pos = OrbitView.polar(_view_center(), _cursor_deg, _view.unit() * 0.28)
	if not display_only:
		core.cursor_moved(_cursor_deg, t)


# ---------------------------------------------------------------------------
# Frame-Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _ended or core == null:
		return
	var t := _time_ms()
	if _autoplay:
		_run_autoplay(t)
	core.update(t)
	_view.t_ms = t
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
	if q == 5:
		_play_miss()
	else:
		_play_hit([1.0, 1.0, 0.944, 0.891, 0.794][clampi(q, 0, 4)])
	var hold_end := bool(result.get("hold_end", false))
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


func _on_arc_started(index: int, _quality: int) -> void:
	_view.on_arc_started(index)


func _play_hit(pitch: float) -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_hit_player.volume_db = linear_to_db(Settings.hitsound_volume) + HIT_DB
	_hit_player.pitch_scale = pitch
	_hit_player.play()


func _play_miss() -> void:
	if not Settings.hitsounds or Settings.hitsound_volume <= 0.01:
		return
	_miss_player.volume_db = linear_to_db(Settings.hitsound_volume) + MISS_DB
	_miss_player.play()


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
	for r in 2:
		var was: bool = _held[r][0] or _held[r][1]
		_held[r] = [false, false]
		_view.ring_held[r] = false
		if was and not _autoplay:
			core.key_up(r, t)


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
	var new_best := false
	if not _autoplay and not GameSession.is_replay and not GameSession.tutorial:
		var save := ScoreStore.submit(GameSession.osz_path, _beatmap.version_name(), s, MODE)
		new_best = bool(save.get("is_new_best", false))
		ScoreStore.log_play(GameSession.osz_path, _beatmap.version_name(),
			"%s - %s" % [_beatmap.artist(), _beatmap.title()], s, MODE)
	var rs := ResultsScreen.new()
	_hud.add_child(rs)
	_results_screen = rs
	rs.retry_pressed.connect(_restart)
	rs.back_pressed.connect(_back_to_browser)
	rs.clip_pressed.connect(func(): rs.show_toast(tr("Clips gibt es nur in Mania 4K"), false))
	var data := {
		"is_fail": is_fail,
		"s": s,
		"pp": -1.0,
		"unranked": false,
		"new_best": new_best,
		"title": _beatmap.title(),
		"artist": _beatmap.artist(),
		"version": "%s  ·  %s" % [_beatmap.version_name(), tr("Orbit")],
		"cover_path": "",
		"offsets": _hit_offsets,
		"player": Settings.profile_name,
		"date": Time.get_datetime_string_from_system(),
		"allow_retry": true,
		"can_replay": false,
		"is_replay": false,
		"lobby": false,
	}
	var cover := OszImporter.load_background_texture(GameSession.osz_path, _beatmap)
	if cover != null:
		data["cover"] = cover
	rs.show_results(data)
	var grade := "F" if is_fail else str(s.get("grade", "D"))
	get_tree().create_timer(0.38, true).timeout.connect(func():
		if is_inside_tree() and _use_audio:
			Sfx.rank_reveal(grade))
	if OS.get_cmdline_args().has("--shot-results"):
		_capture_results_shot()


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
		await _wait_until(target)
		_show_results(false)
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
	get_tree().quit(0)


## Zeitpunkt fuer --shot-at: Zahl (ms), "arc" (Bogen mitten im Halten)
## oder "chord" (Akkord kurz vor der Ankunft).
func _shot_target(v: String, def: float) -> float:
	if v.is_valid_float():
		return v.to_float()
	for i in notes.size():
		var n := notes[i]
		if n.time_ms < 8000.0:
			continue
		if v == "arc" and n.is_arc and n.duration_ms() >= 400.0:
			return n.time_ms + n.duration_ms() * 0.45
		if v == "chord" and i + 1 < notes.size() 				and absf(notes[i + 1].time_ms - n.time_ms) <= OrbitView.CHORD_EPS_MS:
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
	get_tree().quit(0)
