class_name OrbitTutorial
extends Control

## Orbit-Einfuehrung fuer den Taktkreis: sechs kurze Schritte, jeder mit echtem
## Mitspielen und klarer Erfolgsbedingung, danach eine Probe-Runde mit Wertung.
## Wertung ueber OrbitCore, Darstellung ueber OrbitView, genau wie im Spiel.
##   1 Takt     Kreis = ein Takt, der Zeiger dreht, 12 Uhr = Eins: Taste bei Eins
##   2 Zielen   Cursor auf den Zeiger legen und mitfuehren (Pflicht)
##   3 Ringe    Taste A = innerer Ring, Taste B = aeusserer Ring
##   4 Akzent   beide Tasten zugleich
##   5 Halte    Taste halten, dem Zeiger folgen
##   6 Vorschau blasse Noten = naechster Takt
## Das Tempo steigt von Schritt zu Schritt (BPMS), jede Note sitzt auf ihrer
## Taktposition. Schritte 1-6 warten, bis der Spieler es NEED-mal geschafft hat
## (neue Runden kommen von selbst nach). Fehler nennen den Grund ("neben dem
## Zeiger", "anderer Ring", "zu frueh").
## Tab = Schritt ueberspringen, Esc = beenden. Tasten aus den Settings
## (orbit_key_inner/outer = Taste A/B), dazu immer Maus links/rechts wie im Spiel.
## "Gesehen" steht in seen_path (Hinweis im Song-Browser).
## Harness: --shot-tutorial [--shot-out=<ordner>] [--lang=en]: Bot spielt mit
## simulierter Uhr, je Schritt ein Bild plus Wertung (ohne --lang de und en), dann quit.

const BROWSER := "res://scenes/song_select.tscn"
static var seen_path := "user://orbit_tutorial.cfg"

enum { BAR, AIM, KEYS, ACCENT, HOLD, PREVIEW, TRIAL }

## Tempo je Schritt: langsam zum Start, dann steigend (4/4, ein Takt = 4 Schlaege).
const BPMS: Array[float] = [60.0, 60.0, 60.0, 66.0, 72.0, 78.0, 84.0]
const NEED := 3
const STEP_COUNT := 6
const DONE_PAUSE_MS := 1300.0
const OD := 5.0
## Schritt 1: so nah (ms) an Takt-Eins zaehlt der Druck.
const BAR_TOL_MS := 220.0
## Schritt 2: so lange am Stueck auf dem Zeiger bleiben.
const AIM_HOLD_MS := 2200.0
const BOT_TAP_MS := 40.0
## Bot drueckt im Bild, das der Trefferzeit am naechsten liegt (halbes Bild vorher).
const BOT_LEAD_MS := 8.0
## Anteil der Hoehe fuer den Text oben (das Spielfeld beginnt darunter).
const TOP_K := 0.185
const JUDGE_MS := 520.0
## Hinweis bleibt so lange stehen, bevor ihn ein anderer ersetzt.
const SAY_HOLD_MS := 1400.0

## Probe-Runde: [Beat ab Taktanfang, Ring (0 innen, 1 aussen, 2 Akzent), Halte-Beats].
const TRIAL_PATTERN := [
	[0.0, 0], [1.0, 0], [2.0, 1], [3.0, 1],
	[4.0, 2], [5.5, 0], [6.0, 1, 1.5],
	[8.0, 0, 2.0], [9.0, 1], [10.5, 2], [11.5, 0],
]

const TITLES := ["Der Takt", "Zielen", "Zwei Ringe", "Akzent", "Halte", "Vorschau", "Probe-Runde"]
const TIER_COLS := [
	Color(1.0, 0.93, 0.80), Color(0.949, 0.635, 0.227), Color(0.553, 0.757, 0.549),
	Color(0.62, 0.64, 0.62), Color(0.62, 0.59, 0.55), Color(0.871, 0.443, 0.384),
]

var step := BAR
var success := 0
## Test/Harness: Uhr von aussen (advance), Bot gibt Eingaben als Events.
var manual_clock := false
var bot := false
var t_ms := 0.0
var core: OrbitCore
var clock: OrbitClock
var notes: Array[OrbitNote] = []
var finished := false
var tiers: Array[int] = [0, 0, 0, 0, 0, 0]

var _round := 0
var _round_over := false
var _done_t := -1.0
var _beat_ms := 1000.0
var _bar_ms := 4000.0
## Zeit von Takt-Eins eines beliebigen Takts dieses Schritts (Anker der Uhr).
var _t0 := 0.0
## Noten ab dieser Zeit zaehlen als Erfolg (Vorschau: nur der zweite Takt).
var _count_from := -INF
var _q_of: Dictionary = {}
var _say_t := -INF
var _aim_since := -1.0
var _moved := false
var _cursor_deg := 0.0
var _cursor_rho := 0.0
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
var _bot_bar_t := 0.0


## Hervorhebung ueber der OrbitView (gleiche Koordinaten): Markierung bei Eins,
## Fortschritt beim Zielen, Ringnamen mit Tasten, Beschriftung der Vorschau.
class Highlight extends Control:
	var tut: OrbitTutorial

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if tut == null or tut.finished or tut._done_t >= 0.0:
			return
		var v := tut._view
		var c := v.center()
		var u := v.unit()
		var acc := UiTheme.ACCENT
		var w := maxf(2.0, u * 0.004)
		var r_out := v.ring_radius(1)
		match tut.step:
			OrbitTutorial.BAR:
				# Takt-Eins: Marke oben zwischen den Ringen, hell, wenn der Zeiger nah ist.
				var near := absf(OrbitNote.delta_deg(tut.hand_deg(), 0.0)) / 60.0
				var glow := clampf(1.0 - near, 0.0, 1.0)
				_tag(OrbitView.polar(c, 0.0, (v.ring_radius(0) + r_out) * 0.5), tr("EINS"), 0.6 + 0.4 * glow)
			OrbitTutorial.AIM:
				var f := tut.aim_progress()
				var rr := r_out + u * 0.09
				draw_arc(c, rr, 0.0, TAU, 96, Color(acc, 0.14), w, true)
				if f > 0.0:
					draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * f, 96, UiTheme.TEXT, w * 1.6, true)
			OrbitTutorial.KEYS, OrbitTutorial.ACCENT, OrbitTutorial.HOLD:
				var nx := tut.next_note()
				for rg in 2:
					var p := 0.55 + 0.45 * exp(-fposmod((tut.t_ms - tut._t0) / tut._beat_ms, 1.0) * 4.0)
					var on := nx != null and nx.ring == rg and tut.step != OrbitTutorial.ACCENT
					if tut.step == OrbitTutorial.ACCENT:
						on = true
					if on:
						draw_arc(c, v.ring_radius(rg), 0.0, TAU, 160, Color(acc, 0.06 + 0.06 * p), w * 6.0, true)
					_tag(OrbitView.polar(c, 290.0 if rg == 0 else 250.0, v.ring_radius(rg)), tut.ring_tag(rg))
			OrbitTutorial.PREVIEW:
				var pv := tut.first_preview()
				if pv != null:
					_tag(OrbitView.polar(c, pv.angle_deg, v.ring_radius(pv.ring) + u * (0.075 if pv.ring == 1 else -0.075)),
							tr("NÄCHSTER TAKT"))

	## Ringname mit Taste auf dem Ring (flach, Bernstein-Kante).
	func _tag(pos: Vector2, text: String, alpha: float = 1.0) -> void:
		var font := get_theme_default_font()
		var fs := 15
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var sz := Vector2(maxf(ts.x + 16.0, 30.0), ts.y + 6.0)
		var rect := Rect2(pos - sz * 0.5, sz)
		var box := UiTheme.solid_box(UiTheme.BG, 6)
		box.set_border_width_all(1)
		box.border_color = Color(UiTheme.ACCENT, alpha)
		draw_style_box(box, rect)
		var base := rect.position.y + (sz.y - ts.y) * 0.5 + font.get_ascent(fs)
		draw_string(font, Vector2(rect.position.x, base), text, HORIZONTAL_ALIGNMENT_CENTER, sz.x, fs, Color(UiTheme.TEXT, alpha))

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
	enter_step(BAR)
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
	step = clampi(s, BAR, TRIAL)
	success = 0
	_round = 0
	_round_over = false
	_done_t = -1.0
	_aim_since = -1.0
	_judge_t = -INF
	_say_t = -INF
	tiers = [0, 0, 0, 0, 0, 0]
	_release_all()
	_bot_reset()
	_feedback.text = ""
	# Neue Uhr: der naechste Takt-Anfang liegt 2,5 Schlaege voraus.
	_beat_ms = 60000.0 / BPMS[step]
	_bar_ms = _beat_ms * 4.0
	_t0 = t_ms - _bar_ms + _beat_ms * 2.5
	_last_beat = -1
	clock = OrbitClock.fixed(_bar_ms, 4, _t0)
	_view.clock = clock
	_view.preempt = _bar_ms
	_bot_bar_t = _next_bar_time(t_ms)
	core = null
	notes = []
	_view.setup(notes)
	if step >= KEYS:
		_start_round(t_ms)
	_update_texts()


func skip_step() -> void:
	if finished:
		return
	if step == TRIAL:
		_show_result(false)
	else:
		enter_step(step + 1)


func quit_tutorial() -> void:
	mark_seen()
	# Danach Karriere vorschlagen (Song-Browser zeigt die Auswahl einmalig).
	OrbitCareer.offer()
	if manual_clock:
		return
	get_tree().change_scene_to_file.call_deferred(BROWSER)


## Zeit des naechsten Takt-Anfangs ab t (Anker _t0).
func _next_bar_time(t: float) -> float:
	return _t0 + ceilf((t - _t0) / _bar_ms) * _bar_ms


func _start_round(t: float) -> void:
	var k := ceili((t - _t0 + _beat_ms * 1.5) / _bar_ms)
	var b0 := k * 4
	notes = pattern(step, _t0, _beat_ms, b0, _round)
	_count_from = _t0 + float(b0 + 4) * _beat_ms - 1.0 if step == PREVIEW else -INF
	_round += 1
	_round_over = false
	_q_of = {}
	core = OrbitCore.new()
	core.setup(notes, OD, 1.0, 0.0, {"NF": true})
	core.preempt = _bar_ms
	core.note_judged.connect(_on_judged)
	core.arc_started.connect(_on_arc_started)
	core.press_missed.connect(_on_press_missed)
	core.finished.connect(func(_s): _round_over = true)
	_view.setup(notes)
	_bot_reset()


## Eine Note auf Taktposition beat (Schlaege ab Anker t0, Takt = 4 Schlaege):
## Winkel = Anteil des Takts x 360, Zeit exakt. dur > 0 = Halte, die der Hand folgt.
static func _mk(t0: float, bm: float, beat: float, ring: int, dur: float = 0.0) -> OrbitNote:
	var ang := fposmod(beat * 90.0, 360.0)
	var n: OrbitNote
	if dur > 0.0:
		n = OrbitNote.make_arc(t0 + beat * bm, t0 + (beat + dur) * bm, ang, 90.0 * dur, ring)
	else:
		n = OrbitNote.make(t0 + beat * bm, ang, ring)
	n.speed = 90.0 / bm
	return n


## Akzent = zwei Noten (innen, aussen) zur selben Zeit am selben Winkel.
static func _accent(out: Array[OrbitNote], t0: float, bm: float, beat: float) -> void:
	out.append(_mk(t0, bm, beat, 0))
	out.append(_mk(t0, bm, beat, 1))


## Muster je Schritt; b0 = Schlag-Nummer des Takt-Anfangs (Vielfaches von 4),
## rnd wechselt das Muster je Runde. Alle Zeiten liegen auf dem Taktraster.
static func pattern(s: int, t0: float, bm: float, b0: int, rnd: int) -> Array[OrbitNote]:
	var out: Array[OrbitNote] = []
	var b := float(b0)
	var odd := rnd % 2 == 1
	match s:
		KEYS:
			var rings: Array = [1, 0, 1, 0] if odd else [0, 0, 1, 1]
			for k in 4:
				out.append(_mk(t0, bm, b + k, int(rings[k])))
		ACCENT:
			for beat in ([0.0, 1.0, 3.0] if odd else [0.0, 2.0, 3.0]):
				_accent(out, t0, bm, b + beat)
		HOLD:
			var r0 := 1 if odd else 0
			out.append(_mk(t0, bm, b, r0, 1.5))
			out.append(_mk(t0, bm, b + 2.0, 1 - r0, 1.5))
			out.append(_mk(t0, bm, b + 4.0, r0, 2.0))
		PREVIEW:
			var r1 := 1 if odd else 0
			out.append(_mk(t0, bm, b + 1.0, r1))
			out.append(_mk(t0, bm, b + 3.0, r1))
			out.append(_mk(t0, bm, b + 4.0, 1 - r1))
			out.append(_mk(t0, bm, b + 5.0, r1))
			out.append(_mk(t0, bm, b + 6.0, 1 - r1))
		TRIAL:
			for e in TRIAL_PATTERN:
				var beat := b + float(e[0])
				if int(e[1]) == 2:
					_accent(out, t0, bm, beat)
				elif e.size() > 2:
					out.append(_mk(t0, bm, beat, int(e[1]), float(e[2])))
				else:
					out.append(_mk(t0, bm, beat, int(e[1])))
	return out


func _update_texts() -> void:
	_step_lbl.text = tr("Probe") if step == TRIAL else tr("Schritt %d von %d") % [step + 1, STEP_COUNT]
	_title_lbl.text = tr(TITLES[step])
	var ka := key_label(0)
	var kb := key_label(1)
	match step:
		BAR:
			_body_lbl.text = tr("Der Kreis ist ein Takt. Der Zeiger dreht im Songtempo, oben beginnt er. Drück eine Taste, wenn er oben steht.")
		AIM:
			_body_lbl.text = tr("Zielen ist Pflicht. Leg Maus oder Stift auf den Zeiger und führ ihn mit, ohne abzusetzen.")
		KEYS:
			_body_lbl.text = tr("Taste A (%s) spielt den inneren Ring, Taste B (%s) den äußeren. Maus links und rechts gehen auch. Drück, wenn der Zeiger die Note erreicht.") % [ka, kb]
		ACCENT:
			_body_lbl.text = tr("Zwei Noten an einer Stelle sind ein Akzent. Drück beide Tasten (%s und %s) zugleich.") % [ka, kb]
		HOLD:
			_body_lbl.text = tr("Ein Bogen ist eine Halte. Halt die Taste und führ den Cursor mit dem Zeiger, bis der Bogen endet.")
		PREVIEW:
			_body_lbl.text = tr("Blasse Noten gehören zum nächsten Takt. Lies sie voraus, bevor der Zeiger sie erreicht.")
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
	elif t_ms - _say_t > SAY_HOLD_MS:
		_feedback.text = ""


## Hinweis mit Grund; ein juengerer Hinweis wird nicht gleich ueberschrieben.
func _say(text: String) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", UiTheme.DIM)
	_say_t = t_ms


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
	if step == AIM and _done_t < 0.0:
		_update_aim(t)
	var a := clampf(1.0 - (t - _judge_t) / JUDGE_MS, 0.0, 1.0)
	_judge.modulate.a = a
	_judge_side.modulate.a = a
	if _done_t >= 0.0:
		if t - _done_t >= DONE_PAUSE_MS:
			if step == TRIAL:
				_show_result(true)
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
	var b := floori((t - _t0) / _beat_ms)
	if b == _last_beat:
		return
	_last_beat = b
	if not manual_clock and _tick_player != null:
		_tick_player.play()


## Winkel des Zeigers jetzt (0 = oben).
func hand_deg() -> float:
	return clock.angle_at(t_ms) if clock != null else 0.0


func aim_progress() -> float:
	if _aim_since < 0.0:
		return 0.0
	return clampf((t_ms - _aim_since) / AIM_HOLD_MS, 0.0, 1.0)


## Liegt der Cursor jetzt auf dem Zeiger (Winkel, nicht in der Totzone)?
func on_hand(t: float) -> bool:
	return _moved and _cursor_rho >= OrbitCore.DEAD_K \
			and OrbitNote.dist_deg(_cursor_deg, clock.angle_at(t)) <= OrbitCore.ANGLE_TOL_DEG


func _update_aim(t: float) -> void:
	if on_hand(t):
		if _aim_since < 0.0:
			_aim_since = t
		elif t - _aim_since >= AIM_HOLD_MS:
			_aim_since = -1.0
			_play_hit()
			_add_success()
	else:
		if _aim_since >= 0.0 and t - _aim_since > 300.0:
			_say(tr("Neben dem Zeiger: bleib auf ihm."))
		_aim_since = -1.0


## Naechstes noch offenes Ziel (fuer Hervorhebung), null = keins.
func next_note() -> OrbitNote:
	if core == null:
		return null
	for i in notes.size():
		if not core.is_judged(i):
			return notes[i]
	return null


## Erste offene Note im naechsten Takt (Vorschau), null = keine.
func first_preview() -> OrbitNote:
	if core == null or clock == null:
		return null
	for i in notes.size():
		if not core.is_judged(i) and clock.bar_at(notes[i].time_ms) != clock.bar_at(t_ms) \
				and notes[i].time_ms - t_ms <= _bar_ms:
			return notes[i]
	return null


## Kurzname von Taste A (0) bzw. B (1) aus den Settings.
func key_label(key: int) -> String:
	return UiTheme.key_short(Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer)


## Ringname fuer die Markierung auf dem Ring.
func ring_name(ring: int) -> String:
	return tr("AUSSEN") if ring == 1 else tr("INNEN")


## Ringname mit Belegung: "INNEN  A  Z", "AUSSEN  B  X".
func ring_tag(ring: int) -> String:
	return "%s  %s  %s" % [ring_name(ring), "B" if ring == 1 else "A", key_label(ring)]


func cursor_deg() -> float:
	return _cursor_deg


# ---------------------------------------------------------------------------
# Wertung
# ---------------------------------------------------------------------------

func _on_arc_started(index: int, q: int) -> void:
	_view.on_arc_started(index, q)
	_play_hit()


## Partner eines Akzents (gleiche Zeit, anderer Ring), -1 = keiner.
func accent_partner(index: int) -> int:
	var n := notes[index]
	for j in [index - 1, index + 1]:
		if j >= 0 and j < notes.size() and notes[j].ring != n.ring \
				and absf(notes[j].time_ms - n.time_ms) < 0.5:
			return j
	return -1


func _on_judged(index: int, res: Dictionary) -> void:
	_view.on_judged(index, res)
	var q := clampi(int(res.get("quality", 5)), 0, 5)
	_q_of[index] = q
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
	if n.time_ms < _count_from:
		return
	var partner := accent_partner(index)
	if partner >= 0:
		if q == 5:
			_say(tr("Akzent: beide Tasten zugleich."))
		elif int(_q_of.get(partner, 5)) < 5:
			_add_success()
		return
	var ok := q < 5
	if step == HOLD:
		ok = ok and n.is_arc and bool(res.get("held", false))
	if ok:
		_add_success()
	elif q == 5 and t_ms - _say_t > SAY_HOLD_MS:
		if str(res.get("miss_kind", "")) == "DROP":
			_say(tr("Halte verloren: bleib mit dem Cursor auf dem Zeiger und halt die Taste bis zum Ende."))
		else:
			_say(tr("Zu spät: drück, wenn der Zeiger die Note erreicht."))


## Fehldruck: Hinweis je Grund, Marke am Cursor.
func _on_press_missed(deg: float, rho: float, ring: int, reason: String) -> void:
	_view.on_press_missed(deg, rho, ring, reason)
	if step == TRIAL or _done_t >= 0.0:
		return
	match reason:
		"RING":
			_say(tr("Anderer Ring: die Note liegt auf der anderen Taste."))
		"EARLY":
			_say(tr("Zu früh: warte, bis der Zeiger die Note erreicht."))
		"ANGLE":
			_say(tr("Neben dem Zeiger: leg den Cursor auf den Zeiger."))
		"DEAD":
			_say(tr("Zu nah an der Mitte: zeig auf den Zeiger."))


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
# Eingabe (wie OrbitGame: Winkel zur Mitte, Taste waehlt den Ring)
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
	if core != null:
		core.cursor_moved(_cursor_deg, _cursor_rho, t_ms)


func _press(key: int, source: int, down: bool) -> void:
	var was: bool = _held[key][0] or _held[key][1]
	_held[key][source] = down
	var now: bool = _held[key][0] or _held[key][1]
	_sync_glow()
	if now == was:
		return
	if now and step == BAR and _done_t < 0.0:
		_bar_press()
	if core == null:
		return
	if now:
		core.key_down(key, t_ms, _cursor_deg, _cursor_rho)
	else:
		core.key_up(key, t_ms)


## Schritt 1: Druck nahe Takt-Eins zaehlt, sonst "zu frueh" / "zu spaet".
func _bar_press() -> void:
	var d := fposmod(t_ms - _t0, _bar_ms)
	var off := d if d <= _bar_ms * 0.5 else d - _bar_ms
	if absf(off) <= BAR_TOL_MS:
		_play_hit()
		_judge.text = tr("Eins")
		_judge.add_theme_color_override("font_color", TIER_COLS[1])
		_judge_side.text = ""
		_judge_t = t_ms
		_add_success()
	elif off < 0.0:
		_say(tr("Zu früh: warte, bis der Zeiger oben steht."))
	else:
		_say(tr("Zu spät: der Zeiger war schon oben vorbei."))


func _sync_glow() -> void:
	for k in 2:
		_view.ring_held[k] = _held[k][0] or _held[k][1]


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


func _bot_move(deg: float, rho: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = OrbitView.polar(view_center_global(), fposmod(deg, 360.0), _view.unit() * rho)
	handle_input(ev)


func _bot_key(key: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = Settings.orbit_key_inner if key == 0 else Settings.orbit_key_outer
	ev.pressed = down
	handle_input(ev)


static func ring_rho(ring: int) -> float:
	return OrbitCore.R_OUTER_K if ring == 1 else OrbitCore.R_INNER_K


## Der Bot liegt immer auf dem Zeiger und drueckt zur Notenzeit die Taste des Rings.
func _bot_tick(t: float) -> void:
	for k in 2:
		if _bot_release[k] >= 0.0 and _bot_release[k] <= t:
			_bot_key(k, false)
			_bot_release[k] = -1.0
	var rho := 0.28
	if core != null:
		var nx := next_note()
		if nx != null:
			rho = ring_rho(nx.ring)
	_bot_move(clock.angle_at(t), rho)
	if step == BAR:
		if t >= _bot_bar_t - BOT_LEAD_MS:
			_bot_key(0, true)
			_bot_release[0] = t + BOT_TAP_MS
			_bot_bar_t += _bar_ms
		return
	while _bot_idx < notes.size() and notes[_bot_idx].time_ms <= t + BOT_LEAD_MS:
		var n := notes[_bot_idx]
		_bot_idx += 1
		_bot_key(n.ring, true)
		_bot_release[n.ring] = n.end_ms + 10.0 if n.is_arc else t + BOT_TAP_MS


# ---------------------------------------------------------------------------
# Ergebnis der Probe-Runde
# ---------------------------------------------------------------------------

## Karriere ist optional (eigener Branch): nur anbieten, falls die Klasse existiert.
func _offer_career() -> void:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "OrbitCareer":
			var s = load(str(c.get("path", "")))
			if s != null and s.has_method("offer"):
				s.offer()
			return


func _show_result(completed: bool) -> void:
	if finished:
		return
	finished = true
	_release_all()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if completed:
		_offer_career()
	_view.visible = false
	_bar.visible = false
	_step_lbl.text = tr("Probe")
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


## Bild je Schritt: nach dem ersten Erfolg, kurz bevor die naechste Note sitzt.
func _shots_one(dir: String, lang: String) -> void:
	if _result != null:
		_result.queue_free()
		_result = null
		finished = false
		_view.visible = true
		_bar.visible = true
	for s in STEP_COUNT:
		enter_step(s)
		var guard := 0
		while guard < 6000:
			guard += 1
			advance(1000.0 / 60.0)
			if s == BAR:
				if success >= 1 and fposmod(t_ms - _t0, _bar_ms) > _bar_ms * 0.7:
					break
				continue
			if s == AIM:
				if aim_progress() > 0.5:
					break
				continue
			if s == PREVIEW:
				if core != null and core.is_judged(0) and first_preview() != null:
					break
				continue
			var nx := next_note()
			if success >= 1 and nx != null and nx.time_ms - t_ms < 400.0 and nx.time_ms - t_ms > 330.0:
				break
		await _save("orbit_tut_%s_%d.png" % [lang, s + 1], dir)
	enter_step(TRIAL)
	var g2 := 0
	while not finished and g2 < 9000:
		g2 += 1
		advance(1000.0 / 60.0)
	await _save("orbit_tut_%s_result.png" % lang, dir)


func _save(file: String, dir: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var p := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("SHOT gespeichert: " + p)
