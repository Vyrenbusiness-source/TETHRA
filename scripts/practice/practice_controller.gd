class_name PracticeController
extends TempoMode

## Uebungsmodus in der Mania-Szene: Einstellbild (PracticePanel), dann der
## Abschnitt A..B in Schleife. Jede Schleife = frischer ManiaCore, der nur die
## Noten in A..B wertet (restrict_range), mit fester Rate (RateTrack.constant);
## das Audio startet Anflugzeit + 0,8 s vor A neu (SyncClock.play from_ms).
## Nach einem sauberen Durchlauf steigt das Tempo um den Schritt bis zum Ziel.
## Ergebnisse je Abschnitt und Miss-Stellen gehen in PracticeStore (lokal).

const PREROLL_EXTRA_MS := 800.0
const TAIL_MS := 350.0

var ses: PracticeSession
var panel: PracticePanel
var looping := false
var _layer: CanvasLayer
var _bar: Label
var _toast: Label
var _toast_t := 0.0
var _loop_end := 0.0
var _scroll := 1.0
var _stream: AudioStream
var _bm: Beatmap
var _end_ms := 1.0
var _version := ""


func _setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ses = PracticeSession.current
	_bm = host.get("_beatmap")
	_version = _bm.version_name()
	_end_ms = maxf(_bm.duration_ms(), 1000.0)
	_stream = SyncClock.current_stream()
	_scroll = Settings.mania_scroll
	if not ses.has_range():
		var marks := _marks()
		if not marks.is_empty():
			var r := PracticeStore.range_for_mark(marks[0], _end_ms)
			ses.set_range(r.x, r.y)
		else:
			var a: float = _bm.hit_objects[0].time
			ses.set_range(maxf(a - 500.0, 0.0), minf(a + TurboRule.bar_ms(_bm, a) * 8.0, _end_ms))
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_bar = Label.new()
	_bar.offset_left = 24
	_bar.offset_top = 18
	_bar.add_theme_font_override("font", UiTheme.heading_font(0))
	_bar.add_theme_font_size_override("font_size", 16)
	_bar.add_theme_color_override("font_color", UiTheme.TEXT)
	_layer.add_child(_bar)
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.anchor_top = 0.24
	_toast.anchor_bottom = 0.24
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_override("font", UiTheme.heading_font(0))
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", UiTheme.TEXT)
	_toast.visible = false
	_layer.add_child(_toast)
	panel = PracticePanel.new()
	panel.stats_provider = func(): return PracticeStore.section_stats(
			GameSession.osz_path, _version, ses.a_ms, ses.b_ms)
	_layer.add_child(panel)
	panel.build(ses, _bm, _end_ms, "%s - %s [%s]" % [_bm.artist(), _bm.title(), _version])
	panel.start_pressed.connect(func(): start_loop(true))
	panel.back_pressed.connect(_back)
	panel.visible = false


func _marks() -> Array:
	return PracticeStore.error_marks(PracticeStore.load_data(GameSession.osz_path, _version).runs)


func take_start() -> bool:
	open_panel()
	return true


func open_panel() -> void:
	looping = false
	host.get_tree().paused = true
	SyncClock.pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.set_marks(_marks())
	panel.open()
	_bar.visible = false


func on_escape() -> bool:
	if looping:
		open_panel()
	return true


func _back() -> void:
	PracticeSession.clear()
	host.call("_back_to_browser")


## Schleife (neu) starten. countdown = vom Einstellbild aus (kurzer 3-2-1).
func start_loop(countdown: bool = false) -> void:
	panel.visible = false
	var c := ManiaCore.new()
	c.setup(_bm, -1.0, _scroll)
	var n := c.restrict_range(ses.a_ms, ses.b_ms)
	if n == 0:
		open_panel()
		return
	c.no_fail = true
	c.rate_track = RateTrack.constant(ses.rate)
	var first := -1
	var last_end := ses.a_ms
	for i in _bm.hit_objects.size():
		var o := _bm.hit_objects[i]
		if o.time >= ses.a_ms and o.time < ses.b_ms:
			if first < 0:
				first = i
			last_end = maxf(last_end, o.end_time())
	host.call("tempo_restart_run", c, first)
	if bool(GameSession.mods.get("CS", false)):
		host.call("_apply_constant_speed", _scroll)
	var from := ses.a_ms - c.preempt - PREROLL_EXTRA_MS
	if from >= 0.0:
		SyncClock.play(_stream, 1.0, from)
	else:
		SyncClock.play(_stream, -from, 0.0)
	SyncClock.set_rate(ses.rate, ses.keep_pitch)
	_loop_end = last_end + DifficultyCalc.mania_window_miss(_bm.od()) * ses.rate + TAIL_MS
	looping = true
	_bar.visible = true
	_update_bar()
	if countdown:
		host.get_tree().paused = true
		SyncClock.pause()
		host.call("_resume_with_countdown", 0.45)
	else:
		host.get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func tick(t: float) -> void:
	if not looping:
		return
	if t >= _loop_end:
		_finish_loop()


func _finish_loop() -> void:
	var core: ManiaCore = host.get("core")
	var misses := core.n_miss
	var acc := core.accuracy()
	var rate := ses.rate
	PracticeStore.record_section(GameSession.osz_path, _version, ses.a_ms, ses.b_ms, acc, misses, rate)
	PracticeStore.record_run(GameSession.osz_path, _version,
			PracticeStore.misses_from_judge_log(host.get("_judge_log")), "practice")
	var res := ses.after_loop(misses)
	print("PRACTICE loop=%d rate=%.2f misses=%d acc=%.4f next=%.2f" % [ses.loops, rate, misses, acc, ses.rate])
	if bool(res.clean):
		if float(res.rate) > rate + 0.001:
			_show_toast(_t("Clean") + "  ·  " + _t("next loop %s") % RateTrack.pct_text(float(res.rate)), UiTheme.ACCENT)
		else:
			_show_toast(_t("Clean at %s") % RateTrack.pct_text(rate), UiTheme.GOOD)
	else:
		_show_toast(_t("%d misses") % misses + "  ·  " + _t("again at %s") % RateTrack.pct_text(rate), UiTheme.TEXT)
	start_loop(false)


func _show_toast(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 2.2


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if looping:
		_update_bar()


func _update_bar() -> void:
	var core: ManiaCore = host.get("core")
	_bar.text = "%s  ·  %s – %s  ·  %s  ·  %s %d  ·  %s %d  ·  %s %d" % [
		_t("Practice"), PracticeTimeline._fmt(ses.a_ms), PracticeTimeline._fmt(ses.b_ms),
		RateTrack.pct_text(ses.rate), _t("Loop"), ses.loops + 1, _t("clean"), ses.clean_loops,
		_t("misses"), core.n_miss]


static func _t(s: String) -> String:
	return TranslationServer.translate(s)
