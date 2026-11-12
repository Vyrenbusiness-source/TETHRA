class_name DirigentTutorial
extends Control

## Dirigent-Einfuehrung (docs/modes/dirigent.md): fuenf kurze Schritte mit eigener
## Uebungs-Spur (kein Map-Download), Optik und Wertung wie das Spiel (DirigentView,
## DirigentCore, Konzertsaal).
##   1 Folgen    Taktstock folgt der Maus, Punkte der Figur der Reihe nach treffen
##   2 Ring      der Annaeherungsring zeigt, WANN der Punkt gilt (Dreiecksfigur)
##   3 Einsaetze Leiste: Kreis = Taste A, Raute = Taste B, zwei Teile = beide
##   4 Beides    Figur und Einsatz zugleich (auch zwischen den Schlaegen)
##   5 Song      Mini-Song mit 8 Takten und Wertung, dann "Fertig" zurueck in den Browser
## Neue Runden kommen von selbst, bis die Bedingung des Schritts erfuellt ist.
## Fehler nennen den Grund am Ort (zu frueh / zu spaet / falscher Punkt / falsche
## Taste / beide Tasten) und oben als Hinweis.
## Tab = Schritt ueberspringen, Esc = beenden. Tasten aus den Settings
## (Settings.dirigent_key_a/b = A/B), dazu immer Maus links/rechts.
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit simulierter
## Uhr, je Schritt ein Bild, Fehlerbilder und die Wertung, dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://dirigent_tutorial.cfg"

enum { FOLLOW, RING, CUES, BOTH, SONG }
const STEP_COUNT := 5
const BPMS: Array[float] = [50.0, 60.0, 60.0, 60.0, 75.0]
const METERS: Array[int] = [4, 3, 4, 4, 4]
## Erfolge bis zum naechsten Schritt (Song: Wertung am Ende).
const NEED: Array[int] = [6, 6, 6, 5, 0]
const OD := 4.0
const LEAD_BEATS := 2.0
const ROUND_GAP_MS := 900.0
const DONE_PAUSE_MS := 1300.0
const SAY_MS := 2600.0
const FX_MS := 1100.0
const LATE_MS := 450.0
const HIST_MS := 500.0
## Toleranz der Hand beim Einsatz im Schritt "Beides" (Vielfaches von HIT_R).
const AIM_TOL := 1.8
const TOP_PAD := 56.0
const BOT_LEAD_MS := 6.0
const BOT_TAP_MS := 40.0
const BOT_OFFSET := Vector2(0.02, 0.015)
const OK_COL := Color(0.62, 0.84, 0.60)
const BAD_COL := Color(0.95, 0.62, 0.42)

## Test/Harness: eigene Uhr (advance) statt Echtzeit.
var manual_clock := false
## Bot spielt ueber echte Eingabe-Events mit.
var bot := false
var t_ms := 0.0
var step := FOLLOW
var success := 0
var finished := false
var chart: DirigentChart
var core: DirigentCore
var view: DirigentView
var trial_stats: Dictionary = {}
## Textmeldungen am Ort: [Zeit, Position (px im Ansicht-Feld), Text, Farbe].
var fx: Array = []
## Letzter Fehlergrund (Code), fuer Tests.
var last_reason := ""

var _step_lbl: Label
var _title_lbl: Label
var _body_lbl: Label
var _feedback: Label
var _pip_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _bar: HBoxContainer
var _skip_btn: Button
var _quit_btn: Button
var _result: Control
var _overlay: Control
var _tick_player: AudioStreamPlayer
var _snd: Array[AudioStreamPlayer] = [null, null]
var _start_usec := 0
var _cursor_u := Vector2.ZERO
var _hist: Array = []
var _held: Array = [[false, false], [false, false]]
var _say_t := -INF
var _done_t := -1.0
var _round_end_t := -1.0
var _round := 0
var _last_beat := -1
var _late := {}
var _press_fail_t := -INF
var _bot_idx := 0
var _bot_release := [-1.0, -1.0]


# ---------------------------------------------------------------------------
# Spur
# ---------------------------------------------------------------------------

## Einsatz-Zeilen je Takt: 2 Zeichen je Schlag (Achtel), A / B / X (beide) / . (nichts).
static func patterns(s: int) -> Array:
	match s:
		FOLLOW: return ["........", "........"]
		RING: return ["......", "......", "......"]
		CUES: return ["A.A.B.B.", "A.B.X.X."]
		BOTH: return ["A.B.A.B.", "X...A.B.", "A.A.XA.B"]
	return ["A...A...", "A.B.A.B.", "A.A.B.B.", "X...A.B.",
			"A.AAB.B.", "A.B.A.B.", "X.A.B.A.", "A...X..."]


## Spur des Schritts ab t0 (Zeit des ersten Schlags), von Hand gebaut wie DirigentChart.build.
static func make_chart(s: int, t0: float) -> DirigentChart:
	var c := DirigentChart.new()
	var bl := 60000.0 / BPMS[s]
	var meter := METERS[s]
	var fk := DirigentChart.figure_kind(meter)
	var n: int = fk.n
	var pts := DirigentChart.figure_points(str(fk.kind), n)
	var label := DirigentChart.meter_label(meter)
	var pats := patterns(s)
	for b in pats.size():
		var tb := t0 + float(b * n) * bl
		c.bars.append({"t": tb, "n": n, "label": label, "scale": 1.0, "i0": c.beats.size(),
			"count": n, "kind": fk.kind, "ext": false, "step": 1})
		for p in n:
			var u: Vector2 = pts[p]
			c.beats.append({"t": tb + float(p) * bl, "pt": p, "n": n, "bar": b, "unit": u, "pos": u,
				"scale": 1.0, "kiai": false, "label": label, "kind": fk.kind, "step": 1})
		var row: String = pats[b]
		for i in row.length():
			var mask := 0
			match row[i]:
				"A": mask = 1
				"B": mask = 2
				"X": mask = 3
			if mask > 0:
				c.cues.append({"t": tb + float(i) * bl * 0.5, "mask": mask})
	c.duration_ms = t0 + float(pats.size() * n) * bl
	return c


# ---------------------------------------------------------------------------
# Gesehen-Merker (eigene Datei)
# ---------------------------------------------------------------------------

static func is_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(seen_path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "seen", false))


static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "seen", true)
	cfg.save(seen_path)


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

## Uebersetzungen des Modus laden (wie im Spiel).
static func _ensure_translations() -> void:
	for loc in ["de", "en"]:
		var path := "res://translations/dirigent.%s.translation" % loc
		if ResourceLoader.exists(path):
			var tr_res := load(path) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)


func _ready() -> void:
	_ensure_translations()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_seen()
	var bg := ColorRect.new()
	bg.color = DirigentView.PLATE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	view = DirigentView.new()
	add_child(view)
	view.offset_top = TOP_PAD
	view.key_names = [UiTheme.key_short(Settings.dirigent_key_a), UiTheme.key_short(Settings.dirigent_key_b)]
	_overlay = Overlay.new()
	(_overlay as Overlay).tut = self
	view.add_child(_overlay)
	_build_ui()
	_build_sound()
	_start_usec = Time.get_ticks_usec()
	var shot := OS.get_cmdline_args().has("--shot-tutorial")
	if shot:
		manual_clock = true
		bot = true
	if DisplayServer.get_name() != "headless" and not shot:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(FOLLOW)
	if shot:
		_run_shots.call_deferred()


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.custom_minimum_size = Vector2(760, 0)
	top.offset_left = -380
	top.offset_right = 380
	top.offset_top = 12
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_step_lbl = _label(13, UiTheme.DIM)
	_step_lbl.add_theme_font_override("font", UiTheme.heading_font(1))
	top.add_child(_step_lbl)
	_title_lbl = _label(26, UiTheme.TEXT)
	_title_lbl.add_theme_font_override("font", UiTheme.heading_font(0))
	top.add_child(_title_lbl)
	_body_lbl = _label(16, Color(UiTheme.TEXT, 0.86))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_body_lbl)
	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_row.add_theme_constant_override("separation", 8)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_pip_row)
	_feedback = _label(15, UiTheme.DIM)
	top.add_child(_feedback)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bar.offset_left = -300
	_bar.offset_top = 12
	_bar.offset_right = -14
	_bar.offset_bottom = 44
	_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(_bar)
	_skip_btn = Button.new()
	_skip_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_skip_btn, 6)
	_skip_btn.pressed.connect(skip_step)
	_bar.add_child(_skip_btn)
	_quit_btn = Button.new()
	_quit_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_quit_btn, 6)
	_quit_btn.pressed.connect(quit_tutorial)
	_bar.add_child(_quit_btn)
	_update_buttons()


func _update_buttons() -> void:
	_skip_btn.text = tr("Skip step  (Tab)")
	_quit_btn.text = tr("Quit  (Esc)")


func _label(size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _build_sound() -> void:
	_tick_player = AudioStreamPlayer.new()
	_tick_player.stream = _tick_stream()
	_tick_player.volume_db = -16.0
	add_child(_tick_player)
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.orbit_hit_stream(k)
		p.volume_db = -7.0
		add_child(p)
		_snd[k] = p


## Leiser Holz-Tick fuer das Metronom (kurzer Sinus mit schnellem Abklingen).
static func _tick_stream() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.05)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(TAU * 1250.0 * t) * exp(-t * 90.0) * minf(t / 0.002, 1.0)
		data.encode_s16(i * 2, int(clampf(s * 0.45, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

func key_label(key: int) -> String:
	return UiTheme.key_short(Settings.dirigent_key_a if key == 0 else Settings.dirigent_key_b)


func title_for(s: int) -> String:
	match s:
		FOLLOW: return tr("Follow the beat")
		RING: return tr("The closing ring")
		CUES: return tr("Cues: A and B")
		BOTH: return tr("Hand and keys together")
	return tr("Mini song")


func body_for(s: int) -> String:
	match s:
		FOLLOW: return tr("The baton follows your mouse. Move it onto the glowing dot, then on to the next number: 1, 2, 3, 4.")
		RING: return tr("The ring shrinks onto the dot and tells you when: be on the dot just as the ring closes. This figure has 3 dots.")
		CUES: return tr("Marks run along the bar to the line. Circle: %s (left click). Diamond: %s (right click). Both parts: both keys together.") % [key_label(0), key_label(1)]
		BOTH: return tr("Guide the baton and press the keys at the same moment. The ticks on the bar are the beats; marks between two ticks are off-beat.")
	return tr("Eight bars, everything together. You get a score at the end.")


func goal_for(s: int) -> String:
	match s:
		FOLLOW: return tr("%d dots") % NEED[s]
		RING: return tr("%d dots on the beat") % NEED[s]
		CUES: return tr("%d cues") % NEED[s]
		BOTH: return tr("%d cues with the baton on the dot") % NEED[s]
	return tr("Bar %d of %d") % [current_bar() + 1, patterns(SONG).size()]


func current_bar() -> int:
	if chart == null or chart.beats.is_empty():
		return 0
	return maxi(int(chart.beats[maxi(chart.beat_at(t_ms), 0)].bar), 0)


## Kurzer Text am Ort je Fehlergrund.
func reason_short(code: String) -> String:
	match code:
		"early": return tr("too early")
		"late": return tr("too late")
		"wrong": return tr("wrong dot")
		"off": return tr("off the dot")
		"key": return tr("wrong key")
		"both": return tr("both keys")
		"nomark": return tr("no mark yet")
	return tr("missed")


func reason_hint(code: String, key: int = 0) -> String:
	match code:
		"early": return tr("Too early: stay on the dot until the ring closes.")
		"late": return tr("Too late: be on the dot when the ring closes.")
		"wrong": return tr("Wrong dot: follow the numbers in order.")
		"off": return tr("Off the dot: move the baton onto the glowing dot.")
		"key": return tr("Wrong key: this mark needs %s.") % key_label(key)
		"both": return tr("Two-part mark: press %s and %s together.") % [key_label(0), key_label(1)]
		"nomark": return tr("No mark at the line yet: wait for it.")
	return tr("Missed: press when the mark is on the line.")


func _update_texts() -> void:
	_step_lbl.text = tr("Step %d of %d") % [step + 1, STEP_COUNT]
	_title_lbl.text = title_for(step)
	_body_lbl.text = body_for(step)
	if _say_t == -INF:
		_feedback.text = goal_for(step)
		_feedback.add_theme_color_override("font_color", UiTheme.DIM)
	_update_pips()


func _update_pips() -> void:
	var need := NEED[step]
	while _pips.size() < need:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 4)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pips.append(pip)
	for i in _pips.size():
		_pips[i].visible = i < need
		_pips[i].color = UiTheme.ACCENT if i < success else Color(UiTheme.TEXT, 0.16)
	_pip_row.visible = need > 1


func _say(text: String, col: Color = UiTheme.TEXT) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", col)
	_say_t = t_ms


## Meldung am Ort (px im Ansichtsfeld) plus Hinweis oben.
func _flag(code: String, px: Vector2, key: int = 0) -> void:
	last_reason = code
	fx.append([t_ms, px, reason_short(code), BAD_COL])
	_say(reason_hint(code, key), BAD_COL)
	_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Schritte und Runden
# ---------------------------------------------------------------------------

func enter_step(s: int) -> void:
	step = clampi(s, FOLLOW, SONG)
	success = 0
	_round = 0
	_done_t = -1.0
	_round_end_t = -1.0
	_say_t = -INF
	_late = {}
	_press_fail_t = -INF
	last_reason = ""
	fx = []
	trial_stats = {}
	_held = [[false, false], [false, false]]
	view.key_held = [false, false]
	_feedback.text = ""
	_start_round(t_ms)
	_update_texts()


func skip_step() -> void:
	if finished:
		return
	if step == SONG:
		_show_result(false)
	else:
		enter_step(step + 1)


func quit_tutorial() -> void:
	mark_seen()
	if manual_clock:
		return
	get_tree().change_scene_to_file.call_deferred(BROWSER)


func _start_round(t: float) -> void:
	var bl := 60000.0 / BPMS[step]
	chart = make_chart(step, t + bl * LEAD_BEATS)
	core = DirigentCore.new()
	core.setup(chart, OD)
	core.anti_mash = false   # Lernmodus: falsche Taste zeigt nur den Hinweis, kein Miss
	core.beat_judged.connect(_on_beat)
	core.cue_judged.connect(_on_cue)
	core.key_pressed.connect(_on_key_pressed)
	core.finished.connect(_on_round_finished)
	view.setup(chart, core)
	view.t_ms = t
	_round += 1
	_round_end_t = -1.0
	_last_beat = -1
	_bot_idx = 0
	_bot_release = [-1.0, -1.0]
	_late = {}
	if _cursor_u != Vector2.ZERO:
		core.cursor_moved(_cursor_u, t)


func _on_round_finished(_s: Dictionary) -> void:
	_round_end_t = t_ms
	if step == SONG:
		trial_stats = core.stats()


# ---------------------------------------------------------------------------
# Wertung der Ereignisse
# ---------------------------------------------------------------------------

func _on_beat(index: int, res: Dictionary) -> void:
	if step != CUES:
		view.on_beat_judged(index, res)
	if _done_t >= 0.0 or step == CUES:
		return
	if bool(res.hit):
		if step == FOLLOW or step == RING:
			_add_success()
		return
	_beat_miss(index)


func _add_success() -> void:
	success += 1
	_update_pips()
	if success >= NEED[step] and NEED[step] > 0 and _done_t < 0.0:
		_done_t = t_ms
		_say(tr("Well done."), OK_COL)


func _beat_miss(index: int) -> void:
	var b: Dictionary = chart.beats[index]
	var bar: Dictionary = chart.bars[int(b.bar)]
	var cur := core.cursor_pos()
	var px: Vector2 = view.to_px(b.pos) + Vector2(0, DirigentCore.HIT_R * view.unit_px() + 24.0)
	for j in range(int(bar.i0), int(bar.i0) + int(bar.count)):
		if j != index and cur.distance_to(chart.beats[j].pos) <= DirigentCore.HIT_R:
			_flag("wrong", px)
			return
	for h in _hist:
		if float(h[0]) >= float(b.t) - HIST_MS and float(h[0]) < float(b.t) \
				and (h[1] as Vector2).distance_to(b.pos) <= DirigentCore.HIT_R:
			_flag("early", px)
			return
	# Spaet? Dann liegt die Hand kurz nach dem Schlag auf dem Punkt.
	_late = {"pos": b.pos, "px": px, "t": float(b.t), "until": float(b.t) + LATE_MS}


func _check_late() -> void:
	if _late.is_empty():
		return
	if _cursor_u.distance_to(_late.pos) <= DirigentCore.HIT_R:
		_flag("late", _late.px)
		_late = {}
	elif t_ms > float(_late.until):
		_flag("off", _late.px)
		_late = {}


func _line_px() -> Vector2:
	return Vector2(view._bar_line_x(), view.bar_rect().position.y - 30.0)


func _on_cue(index: int, res: Dictionary) -> void:
	view.on_cue_judged(index, res)
	if _done_t >= 0.0:
		return
	var q := int(res.quality)
	if q != 5:
		if step == CUES:
			_add_success()
		elif step == BOTH:
			var d := core.cursor_pos().distance_to(chart.ideal_at(float(chart.cues[index].t)))
			if d <= DirigentCore.HIT_R * AIM_TOL:
				_add_success()
			else:
				_flag("off", _line_px())
		return
	if t_ms - _press_fail_t < 700.0:
		return
	if core._cue_got[index] != 0:
		_flag("both", _line_px())
	else:
		_flag("missed", _line_px())


func _on_key_pressed(key: int, hit: bool) -> void:
	if hit:
		_play_key(key)
		return
	if _done_t >= 0.0:
		return
	# Naechstes offenes Mark in Reichweite suchen und den Grund bestimmen.
	var best := -1
	var best_d := 500.0
	for i in chart.cues.size():
		if core.is_cue_done(i):
			continue
		var d := absf(float(chart.cues[i].t) - t_ms)
		if d < best_d:
			best_d = d
			best = i
	_press_fail_t = t_ms
	if best < 0:
		_flag("nomark", _line_px())
		return
	var c: Dictionary = chart.cues[best]
	if not DirigentChart.mask_has(int(c.mask), key):
		_flag("key", _line_px(), 1 - key)
	elif float(c.t) - t_ms > core.w50:
		_flag("early", _line_px())
	else:
		_flag("late", _line_px())


func _play_key(key: int) -> void:
	if manual_clock or _snd[key] == null:
		return
	_snd[key].play()


# ---------------------------------------------------------------------------
# Zeit
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if manual_clock:
		return
	t_ms = float(Time.get_ticks_usec() - _start_usec) / 1000.0
	_tick(delta * 1000.0)


## Simulierte Uhr (Tests, Harness).
func advance(ms: float) -> void:
	t_ms += ms
	_tick(ms)


func _tick(_dt: float) -> void:
	view.t_ms = t_ms
	if finished:
		return
	if bot:
		_bot_tick(t_ms)
	core.update(t_ms)
	_check_late()
	var bi := chart.beat_at(t_ms)
	if bi != _last_beat and bi >= 0:
		_last_beat = bi
		if not manual_clock:
			_tick_player.play()
	if bi >= 0:
		view.beat_env = clampf(1.0 - (t_ms - float(chart.beats[bi].t)) / 300.0, 0.0, 1.0)
	else:
		view.beat_env = 0.0
	if _say_t != -INF and t_ms - _say_t > SAY_MS:
		_say_t = -INF
		_update_texts()
	if step == SONG and _say_t == -INF:
		_feedback.text = goal_for(step)
	var keep: Array = []
	for f in fx:
		if t_ms - float(f[0]) <= FX_MS:
			keep.append(f)
	fx = keep
	_overlay.queue_redraw()
	if _done_t >= 0.0:
		if t_ms - _done_t >= DONE_PAUSE_MS:
			enter_step(step + 1)
		return
	if _round_end_t >= 0.0 and t_ms - _round_end_t >= ROUND_GAP_MS:
		if step == SONG:
			_show_result(true)
		else:
			_start_round(t_ms)


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	handle_input(event)


func handle_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseMotion:
		_aim_at(event.position)
	elif event is InputEventMouseButton:
		var key := -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			key = 0
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			key = 1
		if key < 0 or (event.pressed and _bar.get_global_rect().has_point(event.position)):
			return
		_aim_at(event.position)
		_press(key, 0, event.pressed)
	elif event is InputEventKey and not event.echo:
		var key := Settings.dirigent_key_for(event.keycode)
		if key >= 0:
			_press(key, 1, event.pressed)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_TAB:
			skip_step()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_ESCAPE:
			quit_tutorial()
			get_viewport().set_input_as_handled()


func _aim_at(pos: Vector2) -> void:
	var local := pos - view.global_position
	view.push_cursor(local)
	_cursor_u = view.to_unit(local)
	_hist.append([t_ms, _cursor_u])
	while _hist.size() > 1 and t_ms - float(_hist[0][0]) > HIST_MS * 1.5:
		_hist.remove_at(0)
	if core != null and _done_t < 0.0:
		core.cursor_moved(_cursor_u, t_ms)


func _press(key: int, source: int, down: bool) -> void:
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	view.key_held[key] = now
	if now and not was and core != null and _done_t < 0.0:
		core.key_down(key, t_ms)


# ---------------------------------------------------------------------------
# Bot (Test und Harness): spielt ueber echte Eingabe-Events
# ---------------------------------------------------------------------------

func _bot_move(u: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = view.global_position + view.to_px(u + BOT_OFFSET)
	handle_input(ev)


func _bot_key(key: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = Settings.dirigent_key_a if key == 0 else Settings.dirigent_key_b
	ev.pressed = down
	handle_input(ev)


## Der Bot folgt dem Ideal-Weg und drueckt faellige Einsaetze.
func _bot_tick(t: float) -> void:
	for k in 2:
		if float(_bot_release[k]) >= 0.0 and float(_bot_release[k]) <= t:
			_bot_key(k, false)
			_bot_release[k] = -1.0
	_bot_move(chart.ideal_at(t))
	while _bot_idx < chart.cues.size() and float(chart.cues[_bot_idx].t) <= t + BOT_LEAD_MS:
		var c: Dictionary = chart.cues[_bot_idx]
		_bot_idx += 1
		_bot_move(chart.ideal_at(float(c.t)))
		for k in 2:
			if DirigentChart.mask_has(int(c.mask), k):
				_bot_key(k, true)
				_bot_release[k] = t + BOT_TAP_MS


# ---------------------------------------------------------------------------
# Ergebnis des Mini-Songs
# ---------------------------------------------------------------------------

func trial_accuracy() -> float:
	return float(trial_stats.get("accuracy", 0.0))


func trial_grade() -> String:
	return str(trial_stats.get("grade", "D"))


func _show_result(completed: bool) -> void:
	if finished:
		return
	finished = true
	for k in 2:
		_held[k] = [false, false]
		view.key_held[k] = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	view.visible = false
	_bar.visible = false
	_step_lbl.text = tr("Mini song")
	_title_lbl.text = tr("Mini song done") if completed else tr("Mini song")
	_body_lbl.text = tr("That was Dirigent. Change the keys in the settings under Controls.")
	_pip_row.visible = false
	_feedback.text = ""
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -110
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_result = box
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 28)
	box.add_child(head)
	var grade := _label(64, UiTheme.ACCENT)
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.text = trial_grade() if completed else "-"
	head.add_child(grade)
	var acc_box := VBoxContainer.new()
	acc_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(acc_box)
	var cap := _label(12, UiTheme.DIM)
	cap.text = tr("ACCURACY")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc_box.add_child(cap)
	var acc := _label(30, UiTheme.TEXT)
	acc.add_theme_font_override("font", UiTheme.heading_font(0))
	acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc.text = UiTheme.fmt_pct(trial_accuracy() * 100.0)
	acc_box.add_child(acc)
	box.add_child(UiTheme.hairline())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	box.add_child(grid)
	var cues_hit := int(trial_stats.get("n_max", 0)) + int(trial_stats.get("n300", 0)) \
			+ int(trial_stats.get("n200", 0)) + int(trial_stats.get("n100", 0)) + int(trial_stats.get("n50", 0))
	var cells := [
		[tr("BEATS"), "%d / %d" % [int(trial_stats.get("beats_hit", 0)), int(trial_stats.get("beats_total", 0))]],
		[tr("CUES"), "%d / %d" % [cues_hit, chart.cues.size()]],
		[tr("COMBO"), str(int(trial_stats.get("max_combo", 0)))],
	]
	for c in cells:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := _label(12, UiTheme.DIM)
		name_l.text = str(c[0])
		cell.add_child(name_l)
		var n_l := _label(22, UiTheme.TEXT)
		n_l.text = str(c[1])
		cell.add_child(n_l)
		grid.add_child(cell)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var again := Button.new()
	again.text = tr("Retry")
	again.custom_minimum_size = Vector2(150, 40)
	UiTheme.style_ghost_button(again, 6)
	again.pressed.connect(retry_trial)
	row.add_child(again)
	var done := Button.new()
	done.text = tr("Done")
	done.custom_minimum_size = Vector2(180, 40)
	UiTheme.style_button(done, true, 6)
	done.pressed.connect(quit_tutorial)
	row.add_child(done)


func retry_trial() -> void:
	if _result != null:
		_result.queue_free()
		_result = null
	finished = false
	view.visible = true
	_bar.visible = true
	if DisplayServer.get_name() != "headless" and not manual_clock:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(SONG)


# ---------------------------------------------------------------------------
# Meldungen am Ort (ueber der Ansicht)
# ---------------------------------------------------------------------------

class Overlay extends Control:
	var tut: DirigentTutorial
	var _font: Font

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = UiTheme.heading_font(2)

	func _draw() -> void:
		if tut == null:
			return
		for f in tut.fx:
			var age := tut.t_ms - float(f[0])
			if age < 0.0 or age > DirigentTutorial.FX_MS:
				continue
			var k := age / DirigentTutorial.FX_MS
			var al := 1.0 - k * k
			var txt: String = f[2]
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			var p: Vector2 = f[1] + Vector2(-w * 0.5, -10.0 * k)
			draw_string(_font, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0, 0, 0, 0.6 * al))
			draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(f[3], al))


# ---------------------------------------------------------------------------
# Harness: --shot-tutorial (Bot, simulierte Uhr, ein Bild je Schritt)
# ---------------------------------------------------------------------------

func _shot_dir() -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("--shot-out="):
			return a.trim_prefix("--shot-out=")
	return OS.get_user_data_dir()


func _run_shots() -> void:
	var dir := _shot_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var langs: Array = [TranslationServer.get_locale().substr(0, 2)]
	for a in OS.get_cmdline_args():
		if a.begins_with("--lang="):
			langs = [a.trim_prefix("--lang=")]
	for lang in langs:
		TranslationServer.set_locale(lang)
		_update_buttons()
		await _shots_one(dir, lang)
	get_tree().quit(0)


func _step_until(cond: Callable, limit: int = 6000) -> void:
	for i in limit:
		if cond.call():
			return
		advance(1000.0 / 60.0)


## Hand-Spur leeren und wenige Frames laufen lassen: kurze, saubere Spur im Bild.
func _settle() -> void:
	view._trail.clear()
	view._trail_t.clear()
	for i in 3:
		advance(1000.0 / 60.0)


func _next_beat_in(ms: float) -> bool:
	var bi := chart.beat_at(t_ms)
	if bi < 0 or bi + 1 >= chart.beats.size():
		return false
	return float(chart.beats[bi + 1].t) - t_ms < ms


func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		retry_trial()
	bot = true
	for s in STEP_COUNT:
		enter_step(s)
		match s:
			FOLLOW, RING:
				_step_until(func(): return success >= 3 and _next_beat_in(300.0))
			CUES:
				_step_until(func(): return core._cue_head >= 4 and success >= 3 \
						and float(chart.cues[core._cue_head].t) - t_ms < 500.0)
			BOTH:
				_step_until(func(): return core._cue_head >= 4 and success >= 3 \
						and float(chart.cues[core._cue_head].t) - t_ms < 400.0)
			_:
				_step_until(func(): return current_bar() >= 3 and core._cue_head >= 10)
		_settle()
		await _save("dirigent_tut_%s_%d.png" % [lang, s + 1], dir)
	# Fehlerbild 1: zu spaet am Punkt (Schritt 2, Hand kommt erst nach dem Schlag).
	bot = false
	enter_step(RING)
	var b: Dictionary = chart.beats[0]
	_aim_at(view.global_position + view.to_px(Vector2(0.9, 0.5)))
	_step_until(func(): return t_ms >= float(b.t) + 30.0)
	_aim_at(view.global_position + view.to_px(b.pos))
	advance(30.0)
	_settle()
	await _save("dirigent_tut_%s_fehler_spaet.png" % lang, dir)
	# Fehlerbild 2: falsche Taste (Schritt 3).
	enter_step(CUES)
	var c: Dictionary = chart.cues[0]
	_step_until(func(): return t_ms >= float(c.t) - 30.0)
	_press(1, 0, true)
	_press(1, 0, false)
	advance(60.0)
	await _save("dirigent_tut_%s_fehler_taste.png" % lang, dir)
	bot = true
	enter_step(SONG)
	_step_until(func(): return finished, 12000)
	await _save("dirigent_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
