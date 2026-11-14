class_name RallyTutorial
extends Control

## Rally-Einfuehrung (docs/modes/rally.md): fuenf kurze Schritte mit eigener
## Uebungsfolge (kein Map-Download), Ansicht und Wertung wie das Spiel (RallyView,
## RallyCore).
##   1 Landen   Ball landet in einer Zone -> Taste dieser Zone zum Zeitpunkt am Schlaeger
##   2 Bogen    Flugbogen lesen: Lob = langsam warten, flacher Ball = schnell
##   3 Smash    Schmetterball: beide Zonentasten zusammen
##   4 Halten   Aufladen: Taste halten bis der Balken endet
##   5 Song     Mini-Song mit Wertung, dann "Done" zurueck in den Browser
## 3 oder 4 Zonen und die Tasten kommen aus den Settings (rally_zones, rally_keys).
## Neue Runden kommen von selbst, bis die Bedingung des Schritts erfuellt ist.
## Fehler nennen den Grund am Ort (zu frueh / zu spaet / falsche Zone / nur eine
## Taste beim Smash / Hold zu frueh losgelassen) und oben als Hinweis.
## Tab = Schritt ueberspringen, Esc = beenden.
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit simulierter
## Uhr, je Schritt ein Bild, Fehlerbilder und die Wertung, dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://rally_tutorial.cfg"

enum { LAND, ARC, SMASH, HOLD, SONG }
const STEP_COUNT := 5
## Erfolge bis zum naechsten Schritt (Song: Wertung am Ende).
const NEED: Array[int] = [5, 6, 3, 3, 0]
const OD := 4.0
const LEAD_MS := 700.0
const ROUND_GAP_MS := 900.0
const DONE_PAUSE_MS := 1300.0
const SAY_MS := 2600.0
const FX_MS := 1100.0
const LATE_MS := 450.0
const TOP_PAD := 150.0
const OK_COL := Color(0.62, 0.84, 0.60)
const BAD_COL := Color(0.95, 0.62, 0.42)

## Test/Harness: eigene Uhr (advance) statt Echtzeit.
var manual_clock := false
## Bot spielt ueber echte Eingabe-Events mit.
var bot := false
var t_ms := 0.0
var step := LAND
var success := 0
var finished := false
var zones := 4
var shots: Array[RallyChart.Shot] = []
var core: RallyCore
var view: RallyView
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
var _snd: RallySound
var _start_usec := 0
var _say_t := -INF
var _done_t := -1.0
var _round_end_t := -1.0
var _round := 0
var _held: Array = [[false], [false], [false], [false]]
var _presses: Array = []
var _late: Array = []
var _flag_t := -INF
var _plan: Array = []
var _plan_idx := 0
var _hit_count := 0


# ---------------------------------------------------------------------------
# Uebungsfolgen
# ---------------------------------------------------------------------------

## Schlag-Zeilen je Schritt: [Zone oder Vector2i(a, b) fuer Smash, Abstand zum vorigen (ms),
## Haltezeit (ms)]. Zonen werden auf die Zonenzahl begrenzt.
static func pattern(s: int) -> Array:
	match s:
		LAND:
			return [[1, 0, 0], [2, 1500, 0], [0, 1500, 0], [3, 1500, 0], [1, 1500, 0]]
		ARC:
			return [[1, 0, 0], [2, 1700, 0], [3, 260, 0], [0, 1700, 0], [1, 260, 0],
					[2, 1700, 0], [0, 260, 0]]
		SMASH:
			return [[Vector2i(0, 1), 0, 0], [2, 1500, 0], [Vector2i(2, 3), 1500, 0],
					[1, 1300, 0], [Vector2i(1, 2), 1500, 0]]
		HOLD:
			return [[1, 0, 900], [2, 2000, 900], [0, 2000, 1200], [3, 2000, 900]]
	return [[1, 0, 0], [2, 700, 0], [3, 700, 0], [2, 700, 0], [1, 1400, 0],
			[Vector2i(0, 3), 1100, 0], [0, 1000, 700], [3, 1800, 0], [2, 500, 0],
			[1, 500, 0], [0, 900, 0], [1, 1200, 0], [Vector2i(1, 2), 1100, 0],
			[3, 1000, 900], [2, 1900, 0], [1, 600, 0], [0, 600, 0], [2, 1200, 0],
			[Vector2i(0, 2), 1100, 0], [3, 1200, 0]]


## Schlaege des Schritts ab t0 (Zeit des ersten Schlags) bei n Zonen.
static func make_shots(s: int, t0: float, n: int, flight_ms: float) -> Array[RallyChart.Shot]:
	RallyChart._zones = 3 if n == 3 else 4
	var out: Array[RallyChart.Shot] = []
	var t := t0
	var last_end := t0
	for row in pattern(s):
		t = t0 if out.is_empty() else last_end + float(row[1])
		var sh := RallyChart.Shot.new()
		sh.t = t
		sh.end = t + float(row[2])
		last_end = sh.end
		var spec = row[0]
		if spec is Vector2i:
			sh.smash = true
			var a := clampi(int(spec.x), 0, n - 1)
			var b := clampi(int(spec.y), 0, n - 1)
			if a == b:
				b = a + 1 if a + 1 < n else a - 1
			sh.zones = PackedInt32Array([mini(a, b), maxi(a, b)])
		else:
			sh.zones = PackedInt32Array([clampi(int(spec), 0, n - 1)])
		sh.key = 0 if sh.zones[0] < n / 2 else 1
		sh.src = out.size()
		out.append(sh)
	RallyChart.finalize(out)
	RallyChart.finalize_flight(out, flight_ms)
	return out


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
		var path := "res://translations/rally.%s.translation" % loc
		if ResourceLoader.exists(path):
			var tr_res := load(path) as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)


func _ready() -> void:
	_ensure_translations()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_seen()
	zones = 4 if Settings.rally_zones == 4 else 3
	var bg := ColorRect.new()
	bg.color = RallyView.COL_ROOM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	view = RallyView.new()
	add_child(view)
	view.offset_top = TOP_PAD
	view.flight_ms = float(Settings.rally_flight_ms)
	_overlay = Overlay.new()
	(_overlay as Overlay).tut = self
	view.add_child(_overlay)
	_snd = RallySound.new()
	add_child(_snd)
	_build_ui()
	_start_usec = Time.get_ticks_usec()
	var shot := OS.get_cmdline_args().has("--shot-tutorial")
	if shot:
		manual_clock = true
		bot = true
	enter_step(LAND)
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


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

## Tasten der Zonen links nach rechts (aus den Settings).
func key_labels() -> Array:
	var out := []
	for k in Settings.rally_keys(zones):
		out.append(UiTheme.key_short(k))
	return out


func key_label(zone: int) -> String:
	var l := key_labels()
	return str(l[clampi(zone, 0, l.size() - 1)])


func keys_text() -> String:
	return "  ".join(key_labels())


func title_for(s: int) -> String:
	match s:
		LAND: return tr("Land and press")
		ARC: return tr("Read the arc")
		SMASH: return tr("Smash: both keys")
		HOLD: return tr("Charge: hold")
	return tr("Mini song")


func body_for(s: int) -> String:
	match s:
		LAND: return tr("The ball bounces on your half of the table. The zone it lands in is your key: press that zone key just as the ball reaches the racket line at the front. Keys, left to right: %s. (3 or 4 zones: settings.)") % keys_text()
		ARC: return tr("The arc tells you how long to wait. A high lob is slow: wait for it. A flat ball is fast and the next one follows right behind. Press at the racket line every time.")
		SMASH: return tr("A ball with a white outline spans two zones: press both zone keys together (%s).") % keys_text()
		HOLD: return tr("A ball with a bar is a charge: press on arrival, keep holding the key until the bar ends, then let go.")
	return tr("Everything together. Don't mash: a wrong key is a miss. You get a score at the end.")


func goal_for(s: int) -> String:
	match s:
		LAND, ARC: return tr("%d balls hit") % NEED[s]
		SMASH: return tr("%d smashes") % NEED[s]
		HOLD: return tr("%d charges held") % NEED[s]
	return tr("%d of %d balls") % [mini(_hit_count, shots.size()), shots.size()]


## Kurzer Text am Ort je Fehlergrund.
func reason_short(code: String) -> String:
	match code:
		"early": return tr("too early")
		"late": return tr("too late")
		"zone": return tr("wrong zone")
		"smash": return tr("both keys")
		"hold": return tr("let go too early")
		"none": return tr("no key")
	return tr("missed")


func reason_hint(code: String, zone: int = 0) -> String:
	match code:
		"early": return tr("Too early: wait until the ball reaches the racket line.")
		"late": return tr("Too late: press when the ball reaches the racket line.")
		"zone": return tr("Wrong zone = miss. Press the key of the zone where the ball lands (%s).") % key_label(zone)
		"smash": return tr("Smash: press both zone keys together.")
		"hold": return tr("Let go too early: keep holding until the bar ends.")
		"none": return tr("No key pressed: press the zone key as the ball arrives.")
	return tr("Missed.")


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


## Pixelposition (im Ansichtsfeld) der Stelle am Schlaeger, wo Schlag s ankommt.
func shot_px(s: RallyChart.Shot) -> Vector2:
	return view._pp(view._w(RallyFlight.shot_x(s), 0.05, 0.0)) + Vector2(0, -view.size.y * 0.05)


## Meldung am Ort plus Hinweis oben.
func _flag(code: String, s: RallyChart.Shot, zone: int = 0) -> void:
	last_reason = code
	_flag_t = t_ms
	fx.append([t_ms, shot_px(s), reason_short(code), BAD_COL])
	_say(reason_hint(code, zone), BAD_COL)
	_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# Schritte und Runden
# ---------------------------------------------------------------------------

func enter_step(s: int) -> void:
	step = clampi(s, LAND, SONG)
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
	zones = 4 if Settings.rally_zones == 4 else 3
	var flight := float(Settings.rally_flight_ms)
	shots = make_shots(step, t + flight + LEAD_MS, zones, flight)
	core = RallyCore.new()
	core.setup(shots, OD, 5.0, {})
	core.no_fail = true
	core.set_replay_mode(false)
	core.shot_judged.connect(_on_shot)
	core.charge_started.connect(_on_charge)
	core.press_ignored.connect(_on_ignored)
	core.finished.connect(_on_round_finished)
	view.setup(shots, core)
	view.reset_fx()
	view.flight_ms = flight
	view.key_labels = key_labels()
	view.held = [false, false, false, false]
	_held = [[false], [false], [false], [false]]
	_presses = []
	_late = []
	_plan = RallyCore.bot_plan(shots)
	_plan_idx = 0
	_round += 1
	_round_end_t = -1.0
	view.t_ms = t


func _on_round_finished(_s: Dictionary) -> void:
	_round_end_t = t_ms
	if step == SONG:
		trial_stats = core.stats()


# ---------------------------------------------------------------------------
# Wertung und Fehlergruende
# ---------------------------------------------------------------------------

func _on_charge(idx: int, q: int) -> void:
	view.on_charge(idx)
	_snd.play_hit(int(shots[idx].zones[0]), q)
	_snd.start_charge()


func _on_ignored(_zone: int, reason: String) -> void:
	if reason == "KEY":
		# Ball einer anderen Zone in Reichweite: falsche Zone.
		var s := _nearest_open(t_ms)
		if s != null:
			_flag("zone", s, int(s.zones[0]))
	elif reason == "FREE" and _flag_t < t_ms - 600.0 and step != SONG:
		var s := _nearest_open(t_ms)
		if s != null and s.t - t_ms > core.w_miss:
			_flag("early", s)


## Naechster noch nicht gewerteter Schlag.
func _nearest_open(t: float) -> RallyChart.Shot:
	for i in shots.size():
		if not core.is_judged(i) and shots[i].end + core.w50 >= t:
			return shots[i]
	return null


func _on_shot(idx: int, result: Dictionary) -> void:
	var s := shots[idx]
	var q := int(result.get("quality", 5))
	view.on_judged(idx, result)
	var hold_end := bool(result.get("hold_end", false))
	if hold_end:
		_snd.stop_charge()
	if q == 5:
		_snd.play_miss()
		_explain_miss(idx, result)
		return
	if hold_end:
		_snd.play_release()
	elif s.smash:
		_snd.play_smash()
		if _smash_pressed(s) < 2:
			_flag("smash", s)
			return
	else:
		_snd.play_hit(int(s.zones[0]), q)
	_hit_count += 1
	fx.append([t_ms, shot_px(s), _quality_text(q), OK_COL])
	if step != SONG and success < NEED[step]:
		success += 1
		_update_pips()
		if success >= NEED[step]:
			_done_t = t_ms
			_say(tr("Good. Next step."), OK_COL)


func _quality_text(q: int) -> String:
	return [tr("perfect"), tr("great"), tr("good"), tr("ok"), tr("ok")][clampi(q, 0, 4)]


## Zahl verschiedener Zonen, die um den Smash gedrueckt wurden.
func _smash_pressed(s: RallyChart.Shot) -> int:
	var seen := {}
	for p in _presses:
		if absf(float(p[0]) - s.t) <= 140.0 and s.zones.has(int(p[1])):
			seen[int(p[1])] = true
	return seen.size()


func _explain_miss(idx: int, result: Dictionary) -> void:
	var s := shots[idx]
	if str(result.get("miss_kind", "")) == "DROP":
		_flag("hold", s)
		return
	if s.smash and _smash_pressed(s) == 1:
		_flag("smash", s)
		return
	var early := false
	var wrong := false
	for p in _presses:
		var dt := float(p[0]) - s.t
		if dt < -core.w_miss * 1.6 or dt > core.w50:
			continue
		if s.zones.has(int(p[1])):
			early = early or dt < 0.0
		else:
			wrong = true
	if early:
		_flag("early", s)
	elif wrong:
		if _flag_t < t_ms - 300.0:
			_flag("zone", s, int(s.zones[0]))
	else:
		# Ohne Taste: spaeter Druck (innerhalb LATE_MS) heisst "zu spaet", sonst "keine Taste".
		_late.append([idx, t_ms])


func _check_late() -> void:
	var keep: Array = []
	for e in _late:
		if t_ms - float(e[1]) > LATE_MS:
			if _flag_t < t_ms - 300.0:
				_flag("none", shots[int(e[0])])
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
	var zone := Settings.rally_zone_for_key(event.keycode, zones)
	if zone >= 0:
		press_zone(zone, event.pressed)
		get_viewport().set_input_as_handled()
	elif event.pressed and event.keycode == KEY_TAB:
		skip_step()
		get_viewport().set_input_as_handled()
	elif event.pressed and event.keycode == KEY_ESCAPE:
		quit_tutorial()
		get_viewport().set_input_as_handled()


## Zonentaste (down/up) zur Zeit at (-1 = jetzt).
func press_zone(zone: int, down: bool, at: float = -1.0) -> void:
	if zone < 0 or zone >= zones or core == null or _done_t >= 0.0:
		return
	var t := t_ms if at < 0.0 else at
	if _held[zone][0] == down:
		return
	_held[zone][0] = down
	view.held[zone] = down
	if down:
		_presses.append([t, zone])
		core.key_down(zone, t)
		for i in range(_late.size() - 1, -1, -1):
			var s := shots[int(_late[i][0])]
			if s.zones.has(zone) and t - s.t <= LATE_MS + core.w50:
				_late.remove_at(i)
				_flag("late", s)
	else:
		core.key_up(zone, t)


# ---------------------------------------------------------------------------
# Bot (Test und Harness): spielt ueber dieselben Eingaben
# ---------------------------------------------------------------------------

func _bot_tick(t: float) -> void:
	while _plan_idx < _plan.size() and float(_plan[_plan_idx][0]) <= t:
		var ev: Array = _plan[_plan_idx]
		_plan_idx += 1
		var code := int(ev[1])
		if code >= RallyCore.EV_UP:
			press_zone(code - RallyCore.EV_UP, false, float(ev[0]))
		else:
			press_zone(code - RallyCore.EV_DOWN, true, float(ev[0]))


# ---------------------------------------------------------------------------
# Wertung am Ende
# ---------------------------------------------------------------------------

func _show_result(completed: bool) -> void:
	if finished:
		return
	finished = true
	for z in 4:
		_held[z] = [false]
		view.held[z] = false
	_snd.stop_charge()
	view.visible = false
	_bar.visible = false
	_step_lbl.text = tr("Mini song")
	_title_lbl.text = tr("Mini song done") if completed else tr("Mini song")
	_body_lbl.text = tr("That was Rally. Change zones and keys in the settings.")
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
	var hit := int(trial_stats.get("n_shots", shots.size())) - int(trial_stats.get("n_miss", 0))
	var cells := [
		[tr("BALLS"), "%d / %d" % [hit, shots.size()]],
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
	var tut: RallyTutorial
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
			if age < 0.0 or age > RallyTutorial.FX_MS:
				continue
			var k := age / RallyTutorial.FX_MS
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


## Laeuft, bis Ball i um before_ms vor dem Schlaeger ist (negativ: danach).
func _until_ball(i: int, before_ms: float) -> void:
	_step_until(func(): return i < shots.size() and t_ms >= shots[i].t - before_ms)


func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		retry_trial()
	bot = true
	for s in STEP_COUNT:
		enter_step(s)
		match s:
			LAND: _until_ball(2, 260.0)
			ARC: _until_ball(3, 250.0)
			SMASH: _until_ball(2, 230.0)
			HOLD: _until_ball(1, -500.0)
			_: _until_ball(6, -250.0)
		await _save("rally_tut_%s_%d.png" % [lang, s + 1], dir)
	# Fehlerbild 1: falsche Zone (Schritt 1).
	bot = false
	enter_step(LAND)
	_until_ball(0, 40.0)
	var wrong := (int(shots[0].zones[0]) + 1) % zones
	press_zone(wrong, true)
	advance(60.0)
	press_zone(wrong, false)
	advance(30.0)
	await _save("rally_tut_%s_fehler_zone.png" % lang, dir)
	# Fehlerbild 2: zu frueh gedrueckt (Schritt 1).
	enter_step(LAND)
	_until_ball(0, core.w_miss * 0.8)
	press_zone(int(shots[0].zones[0]), true)
	advance(50.0)
	press_zone(int(shots[0].zones[0]), false)
	await _save("rally_tut_%s_fehler_frueh.png" % lang, dir)
	# Fehlerbild 3: Hold zu frueh losgelassen (Schritt 4).
	enter_step(HOLD)
	_until_ball(0, 0.0)
	press_zone(int(shots[0].zones[0]), true)
	advance(250.0)
	press_zone(int(shots[0].zones[0]), false)
	advance(30.0)
	await _save("rally_tut_%s_fehler_hold.png" % lang, dir)
	bot = true
	enter_step(SONG)
	_step_until(func(): return finished, 12000)
	await _save("rally_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
