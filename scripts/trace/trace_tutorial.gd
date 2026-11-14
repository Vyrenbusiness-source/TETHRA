class_name TraceTutorial
extends Control

## Trace-Einfuehrung (docs/modes/trace.md): fuenf kurze Schritte mit eigener
## Uebungsfolge (kein Map-Download), Ansicht und Wertung wie das Spiel (TraceView,
## TracePath, ManiaCore 4K).
##   1 Knicke   jeder Knick = Taste der Richtung (Pfeil), wenn der Kopf ihn erreicht
##   2 Takt     der Abstand der Knicke ist der Rhythmus; gleiche Richtung = Knoten
##   3 Halten   dickes Segment = Hold: halten bis zum Ende
##   4 Akkord   zwei Pfeile = Diagonale, Gegenpaar = Kreuzknoten
##   5 Song     Mini-Song mit Wertung, dann "Done" zurueck in den Browser
## Tasten aus den Settings (trace_keys: Spalte 0..3 = links, runter, hoch, rechts).
## Neue Runden kommen von selbst, bis die Bedingung des Schritts erfuellt ist.
## Fehler nennen den Grund am Ort (zu frueh / zu spaet / falsche Taste / nur eine
## Akkord-Taste / Hold zu frueh losgelassen) und oben als Hinweis.
## Tab = Schritt ueberspringen, Esc = beenden.
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit simulierter
## Uhr, je Schritt ein Bild, Fehlerbilder und die Wertung, dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://trace_tutorial.cfg"

enum { TURN, RHYTHM, HOLD, CHORD, SONG }
const STEP_COUNT := 5
## Erfolge (Noten) bis zum naechsten Schritt (Song: Wertung am Ende).
const NEED: Array[int] = [5, 6, 3, 6, 0]
const OD := 4.0
const LEAD_MS := 2400.0
const ROUND_GAP_MS := 900.0
const DONE_PAUSE_MS := 1300.0
const SAY_MS := 2600.0
const FX_MS := 1100.0
const LATE_MS := 450.0
const TOP_PAD := 150.0
const BOT_UP_MS := 40.0
const OK_COL := Color(0.62, 0.84, 0.60)
const BAD_COL := Color(0.95, 0.62, 0.42)
const DIRS := ["left", "down", "up", "right"]

## Test/Harness: eigene Uhr (advance) statt Echtzeit.
var manual_clock := false
## Bot spielt ueber echte Eingabe-Events mit.
var bot := false
var t_ms := 0.0
var step := TURN
var success := 0
var finished := false
var bm: Beatmap
var path: TracePath
var core: ManiaCore
var view: TraceView
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
var _hit_player: AudioStreamPlayer
var _miss_player: AudioStreamPlayer
var _start_usec := 0
var _say_t := -INF
var _done_t := -1.0
var _round_end_t := -1.0
var _round := 0
var _held := [false, false, false, false]
var _presses: Array = []
var _late: Array = []
var _flag_t := -INF
var _plan: Array = []
var _plan_idx := 0
var _hit_count := 0


# ---------------------------------------------------------------------------
# Uebungsfolgen
# ---------------------------------------------------------------------------

## Noten-Zeilen je Schritt: [Spalte oder [Spalten] (Akkord), Abstand zur vorigen (ms),
## Haltezeit (ms)]. Spalte 0..3 = links, runter, hoch, rechts.
static func pattern(s: int) -> Array:
	match s:
		TURN:
			return [[3, 0, 0], [1, 1000, 0], [0, 1000, 0], [2, 1000, 0], [3, 1000, 0], [1, 1000, 0]]
		RHYTHM:
			return [[3, 0, 0], [1, 1100, 0], [1, 550, 0], [0, 550, 0], [2, 1100, 0],
					[2, 350, 0], [3, 1100, 0], [0, 550, 0]]
		HOLD:
			return [[3, 0, 1000], [1, 1900, 900], [0, 1900, 1200], [2, 1900, 900]]
		CHORD:
			return [[3, 0, 0], [[0, 2], 1100, 0], [[1, 3], 1100, 0], [[0, 3], 1300, 0],
					[2, 1100, 0], [[1, 2], 1300, 0]]
	return [[3, 0, 0], [1, 700, 0], [0, 700, 0], [2, 700, 0], [2, 350, 0], [3, 1400, 0],
			[[0, 2], 1100, 0], [1, 700, 800], [3, 1800, 0], [0, 550, 0], [2, 550, 0],
			[1, 1100, 0], [[1, 3], 1100, 0], [0, 1100, 0], [3, 350, 0], [3, 350, 0],
			[2, 1100, 0], [[0, 3], 1300, 0], [1, 1100, 900], [2, 1800, 0], [0, 700, 0],
			[3, 700, 0]]


## Beatmap (Mania 4K) des Schritts: erste Note zur Zeit t0.
static func make_beatmap(s: int, t0: float) -> Beatmap:
	var lines := ""
	var t := t0
	var last_end := t0
	var first := true
	for row in pattern(s):
		t = t0 if first else last_end + float(row[1])
		first = false
		var cols: Array = row[0] if row[0] is Array else [row[0]]
		for c in cols:
			var x := int(c) * 128 + 64
			if int(row[2]) > 0:
				lines += "%d,192,%d,128,0,%d:0:0:0:0:\n" % [x, int(round(t)), int(round(t)) + int(row[2])]
			else:
				lines += "%d,192,%d,1,0,0:0:0:0:\n" % [x, int(round(t))]
		last_end = t + float(row[2])
	var txt := "osu file format v14\n\n[General]\nMode: 3\n\n[Metadata]\nTitle:Tutorial\nArtist:Trace\nVersion:Tutorial\n\n[Difficulty]\nHPDrainRate: 5\nCircleSize: 4\nOverallDifficulty: %s\nApproachRate: 5\nSliderMultiplier: 1.4\n\n[TimingPoints]\n0,500,4,1,0,100,1,0\n\n[HitObjects]\n%s" % [str(OD), lines]
	var res := OsuParser.parse(txt)
	return res.beatmap


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
		var p := "res://translations/trace.%s.translation" % loc
		if ResourceLoader.exists(p):
			var tr_res := load(p) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)


func _ready() -> void:
	_ensure_translations()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_seen()
	var bg := ColorRect.new()
	bg.color = TraceView.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = -8.0
	add_child(_hit_player)
	_miss_player = AudioStreamPlayer.new()
	_miss_player.stream = Sfx.miss_stream()
	_miss_player.volume_db = -8.0
	add_child(_miss_player)
	_build_ui()
	_start_usec = Time.get_ticks_usec()
	var shot := OS.get_cmdline_args().has("--shot-tutorial")
	if shot:
		manual_clock = true
		bot = true
	enter_step(TURN)
	if shot:
		_run_shots.call_deferred()


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


## Kopftext setzen. Die Hoehe kommt aus der Schrift (Breite des Kopfs), denn das
## Label meldet im VBox umbrochene Zeilen nicht: sonst ueberdeckt die zweite Zeile
## die Fortschritts-Striche.
func _set_body(text: String) -> void:
	_body_lbl.text = text
	var font := _body_lbl.get_theme_font("font")
	var fs := _body_lbl.get_theme_font_size("font_size")
	var h := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, 760.0, fs).y
	_body_lbl.custom_minimum_size.y = ceilf(h)


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

## Taste der Spalte (aus den Settings).
func key_label(col: int) -> String:
	return UiTheme.key_short(Settings.trace_keys[clampi(col, 0, 3)])


func dir_name(col: int) -> String:
	match col:
		0: return tr("left")
		1: return tr("down")
		2: return tr("up")
	return tr("right")


func title_for(s: int) -> String:
	match s:
		TURN: return tr("Every bend, one key")
		RHYTHM: return tr("Distance is rhythm")
		HOLD: return tr("Thick thread: hold")
		CHORD: return tr("Diagonals and crosses")
	return tr("Mini song")


func body_for(s: int) -> String:
	match s:
		TURN: return tr("The thread grows by itself. Every bend has an arrow: press the key of that direction just as the glowing head reaches the bend. Left %s, down %s, up %s, right %s.") % [key_label(0), key_label(1), key_label(2), key_label(3)]
		RHYTHM: return tr("The distance between bends is the rhythm: a long stretch means wait, a short one means hurry. The same direction twice is a knot on a straight line: press the same key again.")
		HOLD: return tr("A thick glowing stretch is a hold: press at the bend, keep holding the key until the stretch ends, then let go.")
		CHORD: return tr("Two arrows at one bend are a chord: press both keys together. Left + up bends up-left. Opposite arrows (left + right) make a cross knot and the thread goes straight on.")
	return tr("Everything together. Don't mash: a wrong key is a miss. You get a score at the end.")


func goal_for(s: int) -> String:
	match s:
		TURN, RHYTHM: return tr("%d bends hit") % NEED[s]
		HOLD: return tr("%d holds kept") % NEED[s]
		CHORD: return tr("%d chord keys hit") % NEED[s]
	return tr("%d of %d notes") % [mini(_hit_count, _note_count()), _note_count()]


func _note_count() -> int:
	return bm.hit_objects.size() if bm != null else 0


## Kurzer Text am Ort je Fehlergrund.
func reason_short(code: String) -> String:
	match code:
		"early": return tr("too early")
		"late": return tr("too late")
		"key": return tr("wrong key")
		"chord": return tr("both keys")
		"hold": return tr("let go too early")
		"none": return tr("no key")
	return tr("missed")


func reason_hint(code: String, col: int = 0) -> String:
	match code:
		"early": return tr("Too early: wait until the head reaches the bend.")
		"late": return tr("Too late: press when the head reaches the bend.")
		"key": return tr("Wrong key = miss. This bend points %s, press %s.") % [dir_name(col), key_label(col)]
		"chord": return tr("Chord: press both keys together.")
		"hold": return tr("Let go too early: keep holding until the thick stretch ends.")
		"none": return tr("No key pressed: press the arrow key as the head arrives.")
	return tr("Missed.")


func _update_texts() -> void:
	_step_lbl.text = tr("Step %d of %d") % [step + 1, STEP_COUNT]
	_title_lbl.text = title_for(step)
	_set_body(body_for(step))
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


## Pixelposition (im Ansichtsfeld) des Knicks von Note idx.
func note_px(idx: int) -> Vector2:
	var sc := view.size.y / 720.0
	return view.size * 0.5 + (path.knots[path.note_knot[idx]].pos - view._camera(t_ms)) * sc + Vector2(0, -34)


## Meldung am Ort plus Hinweis oben.
func _flag(code: String, idx: int, col: int = 0) -> void:
	last_reason = code
	_flag_t = t_ms
	fx.append([t_ms, note_px(idx), reason_short(code), BAD_COL])
	_say(reason_hint(code, col), BAD_COL)
	_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Schritte und Runden
# ---------------------------------------------------------------------------

func enter_step(s: int) -> void:
	step = clampi(s, TURN, SONG)
	success = 0
	_round = 0
	_done_t = -1.0
	_round_end_t = -1.0
	_say_t = -INF
	_flag_t = -INF
	last_reason = ""
	fx = []
	trial_stats = {}
	_hit_count = 0
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
	bm = make_beatmap(step, t + LEAD_MS)
	core = ManiaCore.new()
	core.setup(bm, -1.0, 1.0)
	core.no_fail = true
	core.note_judged.connect(_on_note)
	core.hold_started.connect(_on_hold_start)
	core.lane_pressed.connect(_on_lane_pressed)
	core.finished.connect(_on_round_finished)
	path = TracePath.from_beatmap(bm, float(Settings.trace_speed))
	var colors: Array[Color] = []
	var base := NoteColors.preset_colors("standard")
	for o in bm.hit_objects:
		colors.append(base[clampi((o as ManiaNote).column, 0, 3)])
	_new_view()
	view.setup(path, core, colors)
	view.offset_top = TOP_PAD
	view.t_ms = t
	_held = [false, false, false, false]
	_presses = []
	_late = []
	_plan = []
	for o in bm.hit_objects:
		var n := o as ManiaNote
		_plan.append([float(n.time), n.column, true])
		_plan.append([float(n.end_time()) if n.is_hold else float(n.time) + BOT_UP_MS, n.column, false])
	_plan.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return (not a[2]) and b[2])
	_plan_idx = 0
	_round += 1
	_round_end_t = -1.0


## Frische Ansicht je Runde (TraceView merkt sich Urteile und graue Abschnitte).
func _new_view() -> void:
	var vis := true
	if view != null:
		vis = view.visible
		view.queue_free()
	view = TraceView.new()
	view.visible = vis
	add_child(view)
	move_child(view, 1)
	view.offset_top = TOP_PAD
	view.clip_contents = true
	_overlay = Overlay.new()
	(_overlay as Overlay).tut = self
	view.add_child(_overlay)


func _on_round_finished(_s: Dictionary) -> void:
	_round_end_t = t_ms
	if step == SONG:
		trial_stats = core.stats()


# ---------------------------------------------------------------------------
# Wertung und Fehlergruende
# ---------------------------------------------------------------------------

func _play(hit: bool) -> void:
	if manual_clock:
		return
	(_hit_player if hit else _miss_player).play()


func _on_hold_start(_idx: int, _q: int) -> void:
	_play(true)


## Nicht gewertete Taste: falsche Spalte oder zu frueh.
func _on_lane_pressed(col: int, hit: bool) -> void:
	if hit or t_ms - _flag_t < 80.0:
		return
	var i := _nearest_open(t_ms)
	if i < 0:
		return
	var n := bm.hit_objects[i] as ManiaNote
	if n.column != col and absf(t_ms - float(n.time)) <= core.w_miss and not _chord_has(i, col):
		_flag("key", i, n.column)
	elif n.column == col and float(n.time) - t_ms > core.w_miss and step != SONG:
		_flag("early", i)


## Hat die Note (oder ihr Akkord-Partner) die Spalte?
func _chord_has(i: int, col: int) -> bool:
	for j in bm.hit_objects.size():
		var o := bm.hit_objects[j] as ManiaNote
		if absf(float(o.time) - float((bm.hit_objects[i] as ManiaNote).time)) < 3.0 and o.column == col:
			return true
	return false


## Naechste noch nicht gewertete Note (-1: keine).
func _nearest_open(t: float) -> int:
	for i in bm.hit_objects.size():
		var n := bm.hit_objects[i] as ManiaNote
		if not core.is_judged(i) and float(n.end_time()) + core.w50 >= t:
			return i
	return -1


func _on_note(idx: int, result: Dictionary) -> void:
	var q := int(result.get("quality", 5))
	view.on_judged(idx, result)
	var hold_end := bool(result.get("hold_end", false))
	if q == ManiaCore.Quality.MISS:
		_play(false)
		_explain_miss(idx, hold_end)
		return
	_play(true)
	_hit_count += 1
	fx.append([t_ms, note_px(idx), _quality_text(q), OK_COL])
	if step != SONG and success < NEED[step]:
		success += 1
		_update_pips()
		if success >= NEED[step]:
			_done_t = t_ms
			_say(tr("Good. Next step."), OK_COL)


func _quality_text(q: int) -> String:
	return [tr("perfect"), tr("perfect"), tr("great"), tr("good"), tr("ok")][clampi(q, 0, 4)]


func _explain_miss(idx: int, hold_end: bool) -> void:
	var n := bm.hit_objects[idx] as ManiaNote
	if hold_end:
		if last_reason != "hold" or t_ms - _flag_t > 3000.0:
			_flag("hold", idx)
		return
	var early := false
	var wrong := false
	var partner_pressed := false
	for p in _presses:
		var dt := float(p[0]) - float(n.time)
		if dt < -core.w_miss * 1.6 or dt > core.w50:
			continue
		if int(p[1]) == n.column:
			early = early or dt < 0.0
		elif _chord_has(idx, int(p[1])):
			partner_pressed = true
		else:
			wrong = true
	if partner_pressed:
		_flag("chord", idx)
	elif early:
		_flag("early", idx)
	elif wrong:
		if _flag_t < t_ms - 300.0:
			_flag("key", idx, n.column)
	else:
		# Ohne Taste: spaeter Druck (innerhalb LATE_MS) heisst "zu spaet", sonst "keine Taste".
		_late.append([idx, t_ms])


func _check_late() -> void:
	var keep: Array = []
	for e in _late:
		if t_ms - float(e[1]) > LATE_MS:
			if _flag_t < t_ms - 300.0:
				_flag("none", int(e[0]))
		else:
			keep.append(e)
	_late = keep


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
	view.queue_redraw()
	if finished:
		return
	if bot:
		_bot_tick(t_ms)
	core.update(t_ms)
	_check_late()
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
	if finished or not (event is InputEventKey) or event.echo:
		return
	var lane := Settings.trace_lane_for_key(event.keycode)
	if lane >= 0:
		press_lane(lane, event.pressed)
		get_viewport().set_input_as_handled()
	elif event.pressed and event.keycode == KEY_TAB:
		skip_step()
		get_viewport().set_input_as_handled()
	elif event.pressed and event.keycode == KEY_ESCAPE:
		quit_tutorial()
		get_viewport().set_input_as_handled()


## Spaltentaste (down/up) zur Zeit at (-1 = jetzt).
func press_lane(col: int, down: bool, at: float = -1.0) -> void:
	if col < 0 or col > 3 or core == null or _done_t >= 0.0:
		return
	var t := t_ms if at < 0.0 else at
	if _held[col] == down:
		return
	_held[col] = down
	if down:
		_presses.append([t, col])
		TraceRules.press(core, col, t)   # wie im Spiel: falscher Knick = Miss, sonst key_down
		for i in range(_late.size() - 1, -1, -1):
			var n := bm.hit_objects[int(_late[i][0])] as ManiaNote
			if n.column == col and t - float(n.time) <= LATE_MS + core.w50:
				var li := int(_late[i][0])
				_late.remove_at(i)
				_flag("late", li)
	else:
		var h := core.active_hold(col)
		if h >= 0 and t < float((bm.hit_objects[h] as ManiaNote).end_time()) - core.w50:
			_flag("hold", h)
		core.key_up(col, t)


# ---------------------------------------------------------------------------
# Bot (Test und Harness): spielt ueber dieselben Eingaben
# ---------------------------------------------------------------------------

func _bot_tick(t: float) -> void:
	while _plan_idx < _plan.size() and float(_plan[_plan_idx][0]) <= t:
		var ev: Array = _plan[_plan_idx]
		_plan_idx += 1
		press_lane(int(ev[1]), bool(ev[2]), float(ev[0]))


# ---------------------------------------------------------------------------
# Wertung am Ende
# ---------------------------------------------------------------------------

func _show_result(completed: bool) -> void:
	if finished:
		return
	finished = true
	_held = [false, false, false, false]
	view.visible = false
	_bar.visible = false
	_step_lbl.text = tr("Mini song")
	_title_lbl.text = tr("Mini song done") if completed else tr("Mini song")
	_set_body(tr("That was Trace. Change the keys in the settings."))
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
	var total := _note_count()
	var cells := [
		[tr("NOTES"), "%d / %d" % [total - int(trial_stats.get("n_miss", 0)), total]],
		[tr("MISSES"), str(int(trial_stats.get("n_miss", 0)))],
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


func trial_grade() -> String:
	return core.grade() if core != null else "-"


func trial_accuracy() -> float:
	return core.accuracy() if core != null else 0.0


func retry_trial() -> void:
	if _result != null:
		_result.queue_free()
		_result = null
	finished = false
	view.visible = true
	_bar.visible = true
	enter_step(SONG)


# ---------------------------------------------------------------------------
# Meldungen am Ort (ueber der Ansicht)
# ---------------------------------------------------------------------------

class Overlay extends Control:
	var tut: TraceTutorial
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
			if age < 0.0 or age > TraceTutorial.FX_MS:
				continue
			var k := age / TraceTutorial.FX_MS
			var al := 1.0 - k * k
			var txt: String = f[2]
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			var p: Vector2 = f[1] + Vector2(-w * 0.5, -10.0 - 22.0 * k)
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
	var lang := TranslationServer.get_locale().substr(0, 2)
	for a in OS.get_cmdline_args():
		if a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	TranslationServer.set_locale(lang)
	_update_buttons()
	await _shots_one(dir, lang)
	get_tree().quit(0)


func _step_until(cond: Callable, limit: int = 6000) -> void:
	for i in limit:
		if cond.call():
			return
		advance(1000.0 / 60.0)


## Laeuft, bis Note i um before_ms vor ihrer Zeit ist (negativ: danach).
func _until_note(i: int, before_ms: float) -> void:
	_step_until(func(): return i < bm.hit_objects.size() and t_ms >= float(bm.hit_objects[i].time) - before_ms)


func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		retry_trial()
	bot = true
	for s in STEP_COUNT:
		enter_step(s)
		match s:
			TURN: _until_note(2, 250.0)
			RHYTHM: _until_note(3, 200.0)
			HOLD: _until_note(1, -500.0)
			CHORD: _until_note(2, 250.0)
			_: _until_note(8, -250.0)
		await _save("trace_tut_%s_%d.png" % [lang, s + 1], dir)
	# Fehlerbild 1: falsche Taste (Schritt 1).
	bot = false
	enter_step(TURN)
	_until_note(1, 60.0)
	var c1 := int((bm.hit_objects[1] as ManiaNote).column)
	var wrong := (c1 + 1) % 4
	press_lane(wrong, true)
	advance(60.0)
	press_lane(wrong, false)
	advance(30.0)
	await _save("trace_tut_%s_fehler_taste.png" % lang, dir)
	# Fehlerbild 2: zu frueh (Schritt 1).
	enter_step(TURN)
	_until_note(0, 160.0)
	var c0 := int((bm.hit_objects[0] as ManiaNote).column)
	press_lane(c0, true)
	advance(50.0)
	press_lane(c0, false)
	await _save("trace_tut_%s_fehler_frueh.png" % lang, dir)
	# Fehlerbild 3: Hold zu frueh losgelassen (Schritt 3).
	enter_step(HOLD)
	_until_note(0, 0.0)
	var ch := int((bm.hit_objects[0] as ManiaNote).column)
	press_lane(ch, true)
	advance(250.0)
	press_lane(ch, false)
	advance(30.0)
	await _save("trace_tut_%s_fehler_hold.png" % lang, dir)
	# Fehlerbild 4: Akkord mit einer Taste (Schritt 4).
	enter_step(CHORD)
	_until_note(1, 0.0)
	press_lane(int((bm.hit_objects[1] as ManiaNote).column), true)
	advance(250.0)
	await _save("trace_tut_%s_fehler_akkord.png" % lang, dir)
	bot = true
	enter_step(SONG)
	_step_until(func(): return finished, 12000)
	await _save("trace_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
