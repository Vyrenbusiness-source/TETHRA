class_name OrbitTutorial
extends Control

## Orbit-Einfuehrung fuer neue Spieler: sechs kurze Schritte auf einem ruhigen
## Metronom-Takt (90 BPM), jeder mit eigenem kleinen Muster. Wertung ueber
## OrbitCore, Darstellung ueber OrbitView, genau wie im Spiel.
##   1 Zeigen  2 Innerer Ring  3 Aeusserer Ring  4 Ringwechsel  5 Bogen  6 Probe-Runde
## Prinzip: Winkel zur Mitte = Richtung, Abstand zur Mitte = Ring, beide Tasten
## (Maus links/rechts, Z/X) treffen jedes Ziel.
## Schritte 1-5 warten, bis der Spieler es NEED-mal geschafft hat (neue Runden
## kommen von selbst nach), Schritt 6 ist eine Runde mit Wertung.
## Tab = Schritt ueberspringen, Esc = beenden. Tasten aus den Settings
## (orbit_key_inner/outer = Taste A/B), dazu immer Maus links/rechts wie im Spiel.
## "Gesehen" steht in seen_path (Hinweis im Song-Browser).
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit
## simulierter Uhr, je Schritt ein Bild plus Wertung (ohne --lang de und en), dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://orbit_tutorial.cfg"

const BPM := 90.0
const BEAT_MS := 60000.0 / BPM
const NEED := 3
const STEP_COUNT := 6
const DONE_PAUSE_MS := 1300.0
## Mindest-Anflugzeit: im Tutorial nie hektischer als 1 s.
const MIN_PREEMPT := 1000.0
const OD := 5.0
## Schritt 1: so lange auf dem Ziel bleiben, Toleranz in Grad, Zielwinkel.
const AIM_HOLD_MS := 280.0
const AIM_TOL := 14.0
const AIM_ANGLES: Array[float] = [60.0, 200.0, 320.0]
## Ring des Zielflecks je Versuch in Schritt 1: erst innen, dann aussen, dann innen.
const AIM_RINGS: Array[int] = [0, 1, 0]
const BOT_TAP_MS := 40.0
## Bot drueckt im Bild, das der Trefferzeit am naechsten liegt (halbes Bild vorher).
const BOT_LEAD_MS := 8.0
## Anteil der Hoehe fuer den Text oben (das Spielfeld beginnt darunter).
const TOP_K := 0.185
const JUDGE_MS := 520.0

enum { AIM, INNER, OUTER, SWITCH, ARC, TRIAL }

## Probe-Runde: [Beat, Winkel, Ring] oder [Beat, Winkel, Ring, Beats, Spanne].
## Ringwechsel mit mindestens zwei Beats Luft (bei 90 BPM 1,3 s).
const TRIAL_PATTERN := [
	[0, 0.0, 0], [1, 30.0, 0], [2, 60.0, 0],
	[4, 100.0, 1], [5, 140.0, 1], [6, 175.0, 1],
	[8, 210.0, 0, 2, 80.0],
	[12, 300.0, 1], [13, 330.0, 1],
	[15, 20.0, 0], [16, 50.0, 0], [18, 90.0, 1],
]

const TITLES := ["Zeigen", "Innerer Ring", "Äußerer Ring", "Ringwechsel", "Bogen", "Probe-Runde"]
const TIER_COLS := [
	Color(1.0, 0.93, 0.80), Color(0.949, 0.635, 0.227), Color(0.553, 0.757, 0.549),
	Color(0.62, 0.64, 0.62), Color(0.62, 0.59, 0.55), Color(0.871, 0.443, 0.384),
]

var step := AIM
var success := 0
## Test/Harness: Uhr von aussen (advance), Bot gibt Eingaben als Events.
var manual_clock := false
var bot := false
var t_ms := 0.0
var core: OrbitCore
var notes: Array[OrbitNote] = []
var finished := false
var tiers: Array[int] = [0, 0, 0, 0, 0, 0]

var _round := 0
var _round_over := false
var _done_t := -1.0
var _aim_target := 60.0
var _aim_ring := 0
## Gewaehlter Ring des Cursors (Hysterese wie OrbitCore) und Abstand in Bildhoehen.
var _sel_ring := 0
var _cursor_rho := 0.0
var _aim_since := -1.0
var _moved := false
var _cursor_deg := 0.0
var _held := [[false, false], [false, false]]
var _start_usec := 0
var _last_beat := -1
var _judge_t := -INF

var _view: OrbitView
var _hl: Highlight
var _step_lbl: Label
var _title_lbl: Label
var _body_lbl: Label
var _pips: Array[ColorRect] = []
var _pip_row: HBoxContainer
var _feedback: Label
var _judge: Label
var _judge_side: Label
var _bar: HBoxContainer
var _skip_btn: Button
var _quit_btn: Button
var _result: Control
var _tick_player: AudioStreamPlayer
var _hit_player: AudioStreamPlayer

var _bot_idx := 0
var _bot_release: Array[float] = [-1.0, -1.0]
var _bot_arc: Array[int] = [-1, -1]
var _bot_deg := 0.0
var _bot_rho := 0.2
var _bot_key_last := 1


## Hervorhebung ueber der OrbitView (gleiche Koordinaten): Ziel-Sektor in
## Schritt 1, ruhig pulsierender Ring bzw. Akkord-Linie in den Schritten 2-5.
class Highlight extends Control:
	var tut: OrbitTutorial

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if tut == null or tut.finished:
			return
		var v := tut._view
		var c := v.center()
		var ph := fposmod(tut.t_ms / OrbitTutorial.BEAT_MS, 1.0)
		var p := 0.55 + 0.45 * exp(-ph * 4.0)
		var acc := UiTheme.ACCENT
		var w := maxf(2.0, v.unit() * 0.004)
		match tut.step:
			OrbitTutorial.AIM:
				if tut._done_t >= 0.0:
					return
				# Zielfleck: Winkel UND Ring zugleich (ein Bogenstueck auf dem Ring).
				var r := v.ring_radius(tut._aim_ring)
				var a0 := deg_to_rad(tut._aim_target - OrbitTutorial.AIM_TOL - 90.0)
				var a1 := deg_to_rad(tut._aim_target + OrbitTutorial.AIM_TOL - 90.0)
				var band := v.unit() * 0.06
				draw_arc(c, r, a0, a1, 32, Color(acc, 0.16 + 0.10 * p), band, true)
				draw_arc(c, r + band * 0.5, a0, a1, 32, Color(acc, 0.8), w, true)
				draw_arc(c, r - band * 0.5, a0, a1, 32, Color(acc, 0.8), w, true)
				var f := tut.aim_progress()
				if f > 0.0:
					draw_arc(c, r + band * 0.5, a0, lerpf(a0, a1, f), 32, UiTheme.TEXT, w * 2.0, true)
				_tag(OrbitView.polar(c, 270.0, r), tut.ring_name(tut._aim_ring))
			OrbitTutorial.INNER, OrbitTutorial.OUTER:
				var rr := 0 if tut.step == OrbitTutorial.INNER else 1
				_ring(c, v.ring_radius(rr), p, w)
				_tag(OrbitView.polar(c, 270.0, v.ring_radius(rr)), tut.ring_name(rr))
			OrbitTutorial.ARC, OrbitTutorial.SWITCH:
				# Der Ring des naechsten Ziels pulst: dorthin zeigen.
				var nx := tut.next_note()
				var rn := nx.ring if nx != null else 0
				_ring(c, v.ring_radius(rn), p, w)
				_tag(OrbitView.polar(c, 270.0, v.ring_radius(rn)), tut.ring_name(rn))

	## Hervorgehobener Ring: weiches Band plus feine Linie, pulst auf dem Takt.
	func _ring(c: Vector2, r: float, p: float, w: float) -> void:
		var acc := UiTheme.ACCENT
		draw_arc(c, r, 0.0, TAU, 160, Color(acc, 0.07 + 0.07 * p), w * 6.0, true)
		draw_arc(c, r, 0.0, TAU, 160, Color(acc, 0.45 + 0.4 * p), w, true)

	## Ringname auf dem Ring (flach, Bernstein-Kante).
	func _tag(pos: Vector2, text: String) -> void:
		var font := get_theme_default_font()
		var fs := 15
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var sz := Vector2(maxf(ts.x + 16.0, 30.0), ts.y + 6.0)
		var rect := Rect2(pos - sz * 0.5, sz)
		var box := UiTheme.solid_box(UiTheme.BG, 6)
		box.set_border_width_all(1)
		box.border_color = UiTheme.ACCENT
		draw_style_box(box, rect)
		var base := rect.position.y + (sz.y - ts.y) * 0.5 + font.get_ascent(fs)
		draw_string(font, Vector2(rect.position.x, base), text, HORIZONTAL_ALIGNMENT_CENTER, sz.x, fs, UiTheme.TEXT)

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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_seen()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_view = OrbitView.new()
	add_child(_view)
	# Spielfeld unter den Text geschoben (OrbitView skaliert mit der Hoehe).
	resized.connect(_layout)
	_layout()
	_view.show_guides = Settings.orbit_guides
	_view.tol_deg = OrbitCore.ANGLE_TOL_DEG
	_view.center_deg = OrbitCore.CENTER_DEG
	_view.setup(notes)
	_hl = Highlight.new()
	_hl.tut = self
	_view.add_child(_hl)
	_build_ui()
	_build_sound()
	_start_usec = Time.get_ticks_usec()
	var shot := OS.get_cmdline_args().has("--shot-tutorial")
	if shot:
		manual_clock = true
		bot = true
	if DisplayServer.get_name() != "headless" and not shot:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(AIM)
	if shot:
		_run_shots.call_deferred()


func _layout() -> void:
	if _view != null:
		_view.offset_top = roundf(get_viewport_rect().size.y * TOP_K)


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_ui() -> void:
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.custom_minimum_size = Vector2(820, 0)
	top.offset_left = -410
	top.offset_right = 410
	top.offset_top = 28
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_step_lbl = _label(13, UiTheme.DIM)
	_step_lbl.add_theme_font_override("font", UiTheme.heading_font(1))
	top.add_child(_step_lbl)
	_title_lbl = _label(30, UiTheme.TEXT)
	_title_lbl.add_theme_font_override("font", UiTheme.heading_font(0))
	top.add_child(_title_lbl)
	_body_lbl = _label(17, Color(UiTheme.TEXT, 0.86))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_body_lbl)
	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_row.add_theme_constant_override("separation", 8)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_pip_row)
	for i in NEED:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(28, 4)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
		_pips.append(pip)
	_feedback = _label(14, UiTheme.DIM)
	top.add_child(_feedback)

	# Wertung in der Mitte des Spielfelds (Stufe, darunter frueh/spaet).
	var mid := VBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", 0)
	_view.add_child(mid)
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mid.custom_minimum_size = Vector2(200, 60)
	mid.offset_left = -100
	mid.offset_right = 100
	mid.offset_top = -30
	mid.offset_bottom = 30
	_judge = _label(22, UiTheme.TEXT)
	_judge.add_theme_font_override("font", UiTheme.heading_font(2))
	mid.add_child(_judge)
	_judge_side = _label(11, UiTheme.DIM)
	mid.add_child(_judge_side)

	# Unten rechts: flache Knoepfe mit ihrer Taste.
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_bar.offset_left = -420
	_bar.offset_top = -64
	_bar.offset_right = -24
	_bar.offset_bottom = -24
	_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(_bar)
	_skip_btn = Button.new()
	_skip_btn.text = tr("Schritt überspringen  (Tab)")
	_skip_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_skip_btn, 8)
	_skip_btn.pressed.connect(skip_step)
	_bar.add_child(_skip_btn)
	_quit_btn = Button.new()
	_quit_btn.text = tr("Beenden  (Esc)")
	_quit_btn.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(_quit_btn, 8)
	_quit_btn.pressed.connect(quit_tutorial)
	_bar.add_child(_quit_btn)


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
	_tick_player.volume_db = -14.0
	add_child(_tick_player)
	_hit_player = AudioStreamPlayer.new()
	_hit_player.stream = Sfx.hit_stream()
	_hit_player.volume_db = -7.0
	add_child(_hit_player)


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
# Schritte
# ---------------------------------------------------------------------------

func enter_step(s: int) -> void:
	step = clampi(s, AIM, TRIAL)
	success = 0
	_round = 0
	_round_over = false
	_done_t = -1.0
	_aim_since = -1.0
	_aim_target = AIM_ANGLES[0]
	_aim_ring = AIM_RINGS[0]
	_judge_t = -INF
	tiers = [0, 0, 0, 0, 0, 0]
	_release_all()
	_bot_reset()
	_feedback.text = ""
	if step == AIM:
		core = null
		notes = []
		_view.setup(notes)
	else:
		_start_round(t_ms)
	_update_texts()


func skip_step() -> void:
	if finished:
		return
	if step == TRIAL:
		_show_result()
	else:
		enter_step(step + 1)


func quit_tutorial() -> void:
	mark_seen()
	# Danach Karriere vorschlagen (Song-Browser zeigt die Auswahl einmalig).
	OrbitCareer.offer()
	if manual_clock:
		return
	get_tree().change_scene_to_file.call_deferred(BROWSER)


func _preempt() -> float:
	return maxf(ManiaCore.preempt_for(Settings.mania_scroll), MIN_PREEMPT)


static func _bt(beat: int) -> float:
	return float(beat) * BEAT_MS


func _start_round(t: float) -> void:
	var pre := _preempt()
	var b0 := ceili((t + pre + BEAT_MS * 0.5) / BEAT_MS)
	notes = pattern(step, b0, _round)
	_round += 1
	_round_over = false
	core = OrbitCore.new()
	core.setup(notes, OD, 1.0, 0.0, {"NF": true})
	core.preempt = pre
	_view.preempt = pre
	core.note_judged.connect(_on_judged)
	core.arc_started.connect(_on_arc_started)
	core.press_missed.connect(_on_press_missed)
	core.finished.connect(func(_s): _round_over = true)
	_view.setup(notes)
	_bot_reset()


## Muster je Schritt ab Beat b0; rnd verschiebt den Startwinkel je Runde.
static func pattern(s: int, b0: int, rnd: int) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var a := fposmod(30.0 + rnd * 75.0, 360.0)
	match s:
		INNER, OUTER:
			for k in 4:
				out.append(OrbitNote.make(_bt(b0 + k * 2), a + k * 40.0, 0 if s == INNER else 1))
		SWITCH:
			for k in 4:
				out.append(OrbitNote.make(_bt(b0 + k * 3), a + k * 70.0, k % 2))
		ARC:
			for k in 3:
				var dir := 1.0 if k % 2 == 0 else -1.0
				out.append(OrbitNote.make_arc(_bt(b0 + k * 4), _bt(b0 + k * 4 + 2),
					a + k * 50.0, 70.0 * dir, k % 2))
		TRIAL:
			for e in TRIAL_PATTERN:
				var b := b0 + int(e[0])
				if e.size() > 3:
					out.append(OrbitNote.make_arc(_bt(b), _bt(b + int(e[3])), float(e[1]), float(e[4]), int(e[2])))
				else:
					out.append(OrbitNote.make(_bt(b), float(e[1]), int(e[2])))
	return out


func _update_texts() -> void:
	_step_lbl.text = tr("Schritt %d von %d") % [step + 1, STEP_COUNT]
	_title_lbl.text = tr(TITLES[step])
	var ki := key_label(0)
	var ko := key_label(1)
	match step:
		AIM:
			_body_lbl.text = tr("Beweg Maus oder Stift. Der Winkel zur Mitte ist die Richtung, der Abstand wählt den Ring: nah an der Mitte innen, weit draußen außen. Zeig auf die markierte Stelle und bleib kurz dort.")
		INNER:
			_body_lbl.text = tr("Ziele wandern von der Mitte nach außen. Zeig nah an der Mitte auf das Ziel und drück eine Taste, wenn es den inneren Ring erreicht. Beide Tasten (%s und %s, auch Maus links und rechts) treffen: wechsle sie ab.") % [ki, ko]
		OUTER:
			_body_lbl.text = tr("Außen kommen die Ziele von außen herein. Zeig weit draußen auf das Ziel und drück, wenn es den äußeren Ring erreicht.")
		SWITCH:
			_body_lbl.text = tr("Das nächste Ziel liegt auf dem anderen Ring. Zeig vorher in die Tiefe, nah an die Mitte oder weit hinaus, und drück dann.")
		ARC:
			_body_lbl.text = tr("Ein Bogen beginnt wie ein Ziel. Halte eine Taste gedrückt, fahr der Spitze nach und bleib dabei auf dem Ring.")
		TRIAL:
			_body_lbl.text = tr("Jetzt alles zusammen, einmal durch. Danach siehst du deine Wertung.")
	_pip_row.visible = step != TRIAL
	_update_pips()


func _update_pips() -> void:
	for i in _pips.size():
		_pips[i].color = UiTheme.ACCENT if i < success else Color(UiTheme.TEXT, 0.14)


func _add_success() -> void:
	success += 1
	_update_pips()
	if success >= NEED:
		_done_t = t_ms
		_feedback.text = tr("Geschafft.")
		_feedback.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		_feedback.text = ""


func _say(text: String) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", UiTheme.DIM)


# ---------------------------------------------------------------------------
# Frame-Loop (auch von aussen ueber advance)
# ---------------------------------------------------------------------------

func _process(_d: float) -> void:
	if manual_clock:
		return
	t_ms = float(Time.get_ticks_usec() - _start_usec) / 1000.0
	tick()


func advance(ms: float) -> void:
	t_ms += ms
	tick()


func tick() -> void:
	if finished:
		return
	var t := t_ms
	if bot:
		_bot_tick(t)
	_metronome(t)
	if core != null:
		core.update(t)
		for r in 2:
			_view.arc_warn[r] = core.arc_out_ms(r, t) / OrbitCore.ARC_OUT_MS
	_view.t_ms = t
	_view.beat_env = exp(-fposmod(t / BEAT_MS, 1.0) * 5.0) * 0.6
	if step == AIM and _done_t < 0.0:
		_update_aim(t)
	var a := clampf(1.0 - (t - _judge_t) / JUDGE_MS, 0.0, 1.0)
	_judge.modulate.a = a
	_judge_side.modulate.a = a
	if _done_t >= 0.0:
		if t - _done_t >= DONE_PAUSE_MS:
			if step == TRIAL:
				_show_result()
			else:
				enter_step(step + 1)
		return
	if _round_over:
		_round_over = false
		if step == TRIAL:
			_done_t = t
		else:
			_start_round(t)


func _metronome(t: float) -> void:
	var b := floori(t / BEAT_MS)
	if b == _last_beat:
		return
	_last_beat = b
	if not manual_clock and _tick_player != null:
		_tick_player.play()


func aim_progress() -> float:
	if _aim_since < 0.0:
		return 0.0
	return clampf((t_ms - _aim_since) / AIM_HOLD_MS, 0.0, 1.0)


func _update_aim(t: float) -> void:
	if _moved and OrbitNote.dist_deg(_cursor_deg, _aim_target) <= AIM_TOL and _sel_ring == _aim_ring:
		if _aim_since < 0.0:
			_aim_since = t
		elif t - _aim_since >= AIM_HOLD_MS:
			_aim_since = -1.0
			_play_hit()
			_add_success()
			if success < NEED:
				_aim_target = AIM_ANGLES[success]
				_aim_ring = AIM_RINGS[success]
	else:
		_aim_since = -1.0


## Naechstes noch offenes Ziel (fuer Hervorhebung und Bot), null = keins.
func next_note() -> OrbitNote:
	if core == null:
		return null
	for i in notes.size():
		if not core.is_judged(i):
			return notes[i]
	return null


## Kurzname von Taste A (0) bzw. B (1) aus den Settings.
func key_label(key: int) -> String:
	return UiTheme.key_short(Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer)


## Ringname fuer die Markierung auf dem Ring.
func ring_name(ring: int) -> String:
	return tr("AUSSEN") if ring == 1 else tr("INNEN")


func cursor_deg() -> float:
	return _cursor_deg


func cursor_ring() -> int:
	return _sel_ring


# ---------------------------------------------------------------------------
# Wertung
# ---------------------------------------------------------------------------

func _on_arc_started(index: int, q: int) -> void:
	_view.on_arc_started(index, q)
	_play_hit()


func _on_judged(index: int, res: Dictionary) -> void:
	_view.on_judged(index, res)
	var q := clampi(int(res.get("quality", 5)), 0, 5)
	if step == TRIAL:
		tiers[q] += 1
	if _done_t >= 0.0:
		return
	_show_judge(q, res)
	if q < 5 and not notes[index].is_arc:
		_play_hit()
	if step == TRIAL:
		return
	var n := notes[index]
	var ok := q < 5
	match step:
		ARC:
			ok = ok and n.is_arc and bool(res.get("held", false))
	if ok:
		_add_success()
	elif q == 5:
		if str(res.get("miss_kind", "")) == "DROP":
			_say(tr("Halte die Taste bis zum Ende, folge der Spitze und bleib auf dem Ring."))
		else:
			_say(tr("Zeig auf das Ziel und drück, wenn es den Ring erreicht."))


## Fehldruck: Hinweis je Grund, Marke am Cursor.
func _on_press_missed(deg: float, rho: float, ring: int, reason: String) -> void:
	_view.on_press_missed(deg, rho, ring, reason)
	if step == TRIAL or _done_t >= 0.0:
		return
	match reason:
		"RING":
			_say(tr("Anderer Ring: zeig näher an die Mitte oder weiter hinaus."))
		"EARLY":
			_say(tr("Zu früh: warte, bis das Ziel den Ring erreicht."))
		"ANGLE":
			_say(tr("Zeig genau auf das Ziel."))


func _show_judge(q: int, res: Dictionary) -> void:
	_judge.text = tr("VERFEHLT") if q == 5 else tr(OrbitCore.TIER_NAMES[q])
	_judge.add_theme_color_override("font_color", TIER_COLS[q])
	var dt := float(res.get("dt", 0.0))
	_judge_side.text = ""
	if q >= 2 and q < 5 and absf(dt) >= 1.0:
		_judge_side.text = tr("FRÜH") if dt < 0.0 else tr("SPÄT")
	_judge_t = t_ms


func _play_hit() -> void:
	if not manual_clock and _hit_player != null:
		_hit_player.play()


# ---------------------------------------------------------------------------
# Eingabe (wie OrbitGame: Winkel + Abstand zur Mitte, zwei gleichwertige Tasten)
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
		var key := Settings.orbit_ring_for_key(event.keycode)
		if key >= 0:
			_press(key, 1, event.pressed)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_TAB:
			skip_step()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.keycode == KEY_ESCAPE:
			quit_tutorial()
			get_viewport().set_input_as_handled()


func view_center_global() -> Vector2:
	return _view.global_position + _view.center()


func _aim_at(pos: Vector2) -> void:
	var c := view_center_global()
	_view.cursor_pos = pos - _view.global_position
	_cursor_rho = pos.distance_to(c) / maxf(_view.unit(), 1.0)
	var inside := pos.distance_to(c) < _view.deadzone_radius()
	_view.cursor_in_deadzone = inside
	if not inside:
		_cursor_deg = OrbitView.angle_of(c, pos)
		_view.cursor_deg = _cursor_deg
		_moved = true
	_sel_ring = OrbitCore.ring_for_rho(_cursor_rho, _sel_ring)
	_view.sel_ring = _sel_ring
	if core != null:
		core.cursor_moved(_cursor_deg, _cursor_rho, t_ms)


func _press(key: int, source: int, down: bool) -> void:
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	_sync_glow()
	if now == was or core == null:
		return
	if now:
		core.key_down(key, t_ms, _cursor_deg, _cursor_rho)
	else:
		core.key_up(key, t_ms)


func _sync_glow() -> void:
	var any: bool = _held[0][0] or _held[0][1] or _held[1][0] or _held[1][1]
	_view.ring_held[0] = any and _sel_ring == 0
	_view.ring_held[1] = any and _sel_ring == 1


func _release_all() -> void:
	for k in 2:
		var was: bool = _held[k][0] or _held[k][1]
		_held[k] = [false, false]
		if was and core != null:
			core.key_up(k, t_ms)
	if _view != null:
		_sync_glow()


# ---------------------------------------------------------------------------
# Bot (Test und Harness): spielt ueber echte Eingabe-Events
# ---------------------------------------------------------------------------

func _bot_reset() -> void:
	_bot_idx = 0
	_bot_release = [-1.0, -1.0]
	_bot_arc = [-1, -1]


func _bot_move(deg: float, rho: float) -> void:
	_bot_deg = fposmod(deg, 360.0)
	_bot_rho = rho
	var ev := InputEventMouseMotion.new()
	ev.position = OrbitView.polar(view_center_global(), _bot_deg, _view.unit() * rho)
	handle_input(ev)


func _bot_key(key: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer
	ev.pressed = down
	handle_input(ev)


static func ring_rho(ring: int) -> float:
	return OrbitCore.R_OUTER_K if ring == 1 else OrbitCore.R_INNER_K


## Gleitet Winkel und Abstand ein Stueck zum Ziel (Grad / Bildhoehen je Bild).
func _bot_glide(target: float, rho: float, max_step: float) -> void:
	var d := rad_to_deg(angle_difference(deg_to_rad(_bot_deg), deg_to_rad(target)))
	var dr := clampf(rho - _bot_rho, -0.012, 0.012)
	_bot_move(_bot_deg + clampf(d, -max_step, max_step), _bot_rho + dr)


func _bot_tick(t: float) -> void:
	if step == AIM:
		_bot_glide(_aim_target, ring_rho(_aim_ring), 6.0)
		return
	for k in 2:
		if _bot_release[k] >= 0.0 and _bot_release[k] <= t:
			_bot_key(k, false)
			_bot_release[k] = -1.0
			_bot_arc[k] = -1
	while _bot_idx < notes.size() and notes[_bot_idx].time_ms <= t + BOT_LEAD_MS:
		var n := notes[_bot_idx]
		var i := _bot_idx
		_bot_idx += 1
		# Tasten abwechseln; eine Taste, die einen Bogen haelt, bleibt gedrueckt.
		var k := 1 - _bot_key_last
		if _bot_arc[k] >= 0:
			k = 1 - k
		if _bot_release[k] >= 0.0:
			_bot_key(k, false)
		_bot_key_last = k
		_bot_move(n.angle_deg, ring_rho(n.ring))
		_bot_key(k, true)
		_bot_arc[k] = i if n.is_arc else -1
		_bot_release[k] = n.end_ms + 10.0 if n.is_arc else t + BOT_TAP_MS
	for k in 2:
		if _bot_arc[k] >= 0:
			var an := notes[_bot_arc[k]]
			_bot_move(an.angle_at(t), ring_rho(an.ring))
			return
	if _bot_idx < notes.size():
		_bot_glide(notes[_bot_idx].angle_deg, ring_rho(notes[_bot_idx].ring), 4.0)


# ---------------------------------------------------------------------------
# Ergebnis der Probe-Runde
# ---------------------------------------------------------------------------

func _show_result() -> void:
	if finished:
		return
	finished = true
	_release_all()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_view.visible = false
	_bar.visible = false
	_step_lbl.text = tr("Schritt %d von %d") % [STEP_COUNT, STEP_COUNT]
	_title_lbl.text = tr("Probe-Runde geschafft")
	_body_lbl.text = tr("Das war Orbit. Tasten änderst du in den Einstellungen unter Orbit.")
	_pip_row.visible = false
	_feedback.text = ""
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -150
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
	grade.text = trial_grade()
	head.add_child(grade)
	var acc_box := VBoxContainer.new()
	acc_box.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(acc_box)
	var cap := _label(12, UiTheme.DIM)
	cap.text = tr("GENAUIGKEIT")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc_box.add_child(cap)
	var acc := _label(30, UiTheme.TEXT)
	acc.add_theme_font_override("font", UiTheme.heading_font(0))
	acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	acc.text = UiTheme.fmt_pct(trial_accuracy() * 100.0)
	acc_box.add_child(acc)
	var line := ColorRect.new()
	line.color = Color(UiTheme.TEXT, 0.12)
	line.custom_minimum_size = Vector2(0, 1)
	box.add_child(line)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	box.add_child(grid)
	for q in 6:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := _label(12, TIER_COLS[q])
		name_l.text = tr("VERFEHLT") if q == 5 else tr(OrbitCore.TIER_NAMES[q])
		cell.add_child(name_l)
		var n_l := _label(22, UiTheme.TEXT)
		n_l.text = str(tiers[q])
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
	again.text = tr("Nochmal")
	again.custom_minimum_size = Vector2(150, 40)
	UiTheme.style_ghost_button(again, 8)
	again.pressed.connect(_retry_trial)
	row.add_child(again)
	var done := Button.new()
	done.text = tr("Zu den Maps")
	done.custom_minimum_size = Vector2(180, 40)
	UiTheme.style_button(done, true, 8)
	done.pressed.connect(quit_tutorial)
	row.add_child(done)


func _retry_trial() -> void:
	if _result != null:
		_result.queue_free()
		_result = null
	finished = false
	_view.visible = true
	_bar.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	enter_step(TRIAL)


## Genauigkeit der Probe-Runde mit den Orbit-Stufenwerten (0..1).
func trial_accuracy() -> float:
	var n := 0
	var v := 0.0
	for q in 6:
		n += tiers[q]
		v += tiers[q] * OrbitCore.TIER_VALUE[q]
	return v / n if n > 0 else 0.0


func trial_grade() -> String:
	var a := trial_accuracy()
	if a >= OrbitCore.GRADE_SS:
		return "SS"
	for g in OrbitCore.GRADE_STEPS:
		if a >= float(g[0]):
			return str(g[1])
	return "D"


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
	# Ohne --lang beide Sprachen in einem Lauf.
	var langs: Array = [TranslationServer.get_locale().substr(0, 2)]
	if not Array(OS.get_cmdline_args()).any(func(a): return str(a).begins_with("--lang=")):
		langs = ["de", "en"]
	for lang in langs:
		TranslationServer.set_locale(lang)
		_skip_btn.text = tr("Schritt überspringen  (Tab)")
		_quit_btn.text = tr("Beenden  (Esc)")
		await _shots_one(dir, lang)
	get_tree().quit(0)


func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		_result.queue_free()
		_result = null
		finished = false
		_view.visible = true
		_bar.visible = true
	for s in STEP_COUNT:
		enter_step(s)
		# Bis ein Treffer geschafft ist und das naechste Ziel kurz vor dem Ring steht.
		var guard := 0
		while guard < 4000:
			guard += 1
			advance(1000.0 / 60.0)
			if s == AIM:
				if success >= 1 and aim_progress() > 0.0 and aim_progress() < 0.6:
					break
				continue
			var nx := next_note()
			var want := 1 if s != TRIAL else 0
			if (s == TRIAL and tiers[0] + tiers[1] >= 3 or success >= want) and nx != null \
					and nx.time_ms - t_ms < 380.0 and nx.time_ms - t_ms > 300.0:
				break
		await _save("orbit_tut_%s_%d.png" % [lang, s + 1], dir)
	enter_step(TRIAL)
	var g2 := 0
	while not finished and g2 < 6000:
		g2 += 1
		advance(1000.0 / 60.0)
	await _save("orbit_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
