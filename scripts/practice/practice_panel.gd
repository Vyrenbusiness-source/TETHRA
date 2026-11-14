class_name PracticePanel
extends Control

## Einstellbild des Uebungsmodus (Stil Song-Browser: Graphit, Bernstein,
## deckende Flaechen, keine Glows). Zeitleiste mit Notendichte und Fehler-
## stellen, A/B, Tempo Start/Ziel/Schritt, Tonhoehe, Statistik des Abschnitts.
## Tasten: A / B = Kante an den Cursor, Pfeile = Cursor (Umschalt: fein),
## Enter = Schleife starten, Esc = zurueck zum Song-Browser.

signal start_pressed
signal back_pressed

var ses: PracticeSession
var song_ms := 1.0
var title_text := ""
var timeline: PracticeTimeline
var _range_lbl: Label
var _stats_lbl: Label
var _marks_row: HFlowContainer
var _rate_lbls := {}
var _pitch_btn: CheckButton
var _start_btn: Button
var stats_provider: Callable


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


func build(p_ses: PracticeSession, bm: Beatmap, end_ms: float, p_title: String) -> void:
	ses = p_ses
	song_ms = end_ms
	title_text = p_title
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := UiTheme.modal_backdrop(self)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.solid_box(UiTheme.SURFACE, 6))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -470
	card.offset_right = 470
	card.offset_top = -280
	card.offset_bottom = 280
	add_child(card)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var cap := UiTheme.section_label(_t("Practice"))
	cap.add_theme_color_override("font_color", UiTheme.ACCENT)
	head.add_child(cap)
	var tl := Label.new()
	tl.text = "   " + title_text
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.add_theme_font_override("font", UiTheme.heading_font(0))
	tl.add_theme_font_size_override("font_size", 20)
	tl.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(tl)
	var unr := Label.new()
	unr.text = _t("unranked · no online scores")
	unr.add_theme_font_size_override("font_size", 12)
	unr.add_theme_color_override("font_color", UiTheme.DIM)
	head.add_child(unr)
	vb.add_child(UiTheme.hairline())

	timeline = PracticeTimeline.new()
	vb.add_child(timeline)
	timeline.set_map(bm, end_ms)
	timeline.range_changed.connect(_on_range)
	timeline.cursor_moved.connect(func(_t_ms): _refresh())

	_range_lbl = Label.new()
	_range_lbl.add_theme_font_size_override("font_size", 14)
	_range_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(_range_lbl)
	var hint := Label.new()
	hint.text = _t("Drag on the timeline to mark a section. A / B: set edge at cursor, arrow keys: move cursor (Shift: fine).")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(hint)

	vb.add_child(UiTheme.section_label(_t("Error spots from your last runs")))
	_marks_row = HFlowContainer.new()
	_marks_row.add_theme_constant_override("h_separation", 6)
	_marks_row.add_theme_constant_override("v_separation", 6)
	vb.add_child(_marks_row)

	vb.add_child(UiTheme.section_label(_t("Tempo")))
	var tempo := HBoxContainer.new()
	tempo.add_theme_constant_override("separation", 18)
	vb.add_child(tempo)
	_stepper(tempo, "start", _t("Start"))
	_stepper(tempo, "target", _t("Target"))
	_stepper(tempo, "step", _t("Step"))
	_pitch_btn = CheckButton.new()
	_pitch_btn.text = _t("Keep pitch")
	_pitch_btn.tooltip_text = _t("On: time-stretch, the song keeps its key. Off: faster songs sound higher (nightcore).")
	_pitch_btn.focus_mode = Control.FOCUS_NONE
	_pitch_btn.button_pressed = ses.keep_pitch
	_pitch_btn.add_theme_font_size_override("font_size", 14)
	_pitch_btn.toggled.connect(func(on):
		ses.keep_pitch = on
		TempoPrefs.set_keep_pitch(on))
	tempo.add_child(_pitch_btn)

	_stats_lbl = Label.new()
	_stats_lbl.add_theme_font_size_override("font_size", 14)
	_stats_lbl.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(_stats_lbl)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(fill)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	vb.add_child(btns)
	_start_btn = Button.new()
	_start_btn.text = _t("Start loop") + "  (Enter)"
	_start_btn.custom_minimum_size = Vector2(240, 46)
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.add_theme_font_size_override("font_size", 17)
	UiTheme.style_button(_start_btn, true)
	_start_btn.pressed.connect(func(): start_pressed.emit())
	btns.add_child(_start_btn)
	var bb := Button.new()
	bb.text = _t("Song select") + "  (Esc)"
	bb.custom_minimum_size = Vector2(0, 46)
	bb.focus_mode = Control.FOCUS_NONE
	bb.add_theme_font_size_override("font_size", 15)
	UiTheme.style_ghost_button(bb)
	bb.pressed.connect(func(): back_pressed.emit())
	btns.add_child(bb)
	timeline.set_range(ses.a_ms, ses.b_ms)
	timeline.set_cursor(ses.a_ms)


func _stepper(parent: Control, key: String, caption: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	parent.add_child(hb)
	var c := Label.new()
	c.text = caption
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", UiTheme.DIM)
	hb.add_child(c)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "−" if d < 0 else "+"
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		UiTheme.style_ghost_button(b, 6)
		b.pressed.connect(_bump.bind(key, d))
		hb.add_child(b)
		if d < 0:
			var v := Label.new()
			v.custom_minimum_size = Vector2(58, 0)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_theme_font_override("font", UiTheme.heading_font(0))
			v.add_theme_font_size_override("font_size", 18)
			v.add_theme_color_override("font_color", UiTheme.TEXT)
			hb.add_child(v)
			_rate_lbls[key] = v


func _bump(key: String, d: int) -> void:
	var s := ses.start_rate
	var g := ses.target_rate
	var st := ses.step
	match key:
		"start":
			s = RateTrack.snap(s + 0.05 * d)
			g = maxf(g, s)
		"target":
			g = maxf(RateTrack.snap(g + 0.05 * d), s)
		"step":
			st = clampf(st + 0.05 * d, 0.05, 0.25)
	ses.set_rates(s, g, st)
	_refresh()


func _on_range(a: float, b: float) -> void:
	if absf(a - ses.a_ms) < 1.0 and absf(b - ses.b_ms) < 1.0:
		return
	ses.set_range(a, b)
	timeline.set_range(ses.a_ms, ses.b_ms)
	_refresh()


func set_marks(marks: Array) -> void:
	timeline.marks = marks
	timeline.queue_redraw()
	for ch in _marks_row.get_children():
		ch.queue_free()
	if marks.is_empty():
		var l := Label.new()
		l.text = _t("None yet: play the map normally or loop a section, misses show up here.")
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.DIM)
		_marks_row.add_child(l)
		return
	for mk in marks:
		var b := Button.new()
		b.text = "%s  ·  %d×" % [PracticeTimeline._fmt(float(mk.t0)), int(mk.n)]
		b.tooltip_text = _t("Jump: section around this spot")
		b.custom_minimum_size = Vector2(0, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UiTheme.BAD)
		UiTheme.style_ghost_button(b, 6)
		b.pressed.connect(func():
			var r := PracticeStore.range_for_mark(mk, song_ms)
			ses.set_range(r.x, r.y)
			timeline.set_range(ses.a_ms, ses.b_ms)
			timeline.set_cursor(ses.a_ms)
			_refresh())
		_marks_row.add_child(b)


func _refresh() -> void:
	_rate_lbls.start.text = RateTrack.pct_text(ses.start_rate)
	_rate_lbls.target.text = RateTrack.pct_text(ses.target_rate)
	_rate_lbls.step.text = "%d %%" % int(round(ses.step * 100.0))
	var len_s := (ses.b_ms - ses.a_ms) / 1000.0
	_range_lbl.text = "A  %s     B  %s     %s %s s     %s  %s" % [
		_fmt_precise(ses.a_ms), _fmt_precise(ses.b_ms), _t("Length"), UiTheme.fmt_num(len_s, 1),
		_t("Cursor"), _fmt_precise(timeline.cursor_ms)]
	var st: Dictionary = stats_provider.call() if stats_provider.is_valid() else {}
	if st.is_empty():
		_stats_lbl.text = _t("This section: not played yet.")
	else:
		var best_rate := float(st.get("best_rate", 0.0))
		_stats_lbl.text = _t("This section: %d loops, %d clean, best accuracy %s, fastest clean %s") % [
			int(st.plays), int(st.clean), UiTheme.fmt_pct(float(st.best_acc) * 100.0),
			RateTrack.pct_text(best_rate) if best_rate > 0.0 else "–"]


static func _fmt_precise(ms: float) -> String:
	var s := maxf(ms, 0.0) / 1000.0
	return "%d:%s" % [int(s / 60.0), UiTheme.fmt_num(fmod(s, 60.0), 1).lpad(4, "0")]


func open() -> void:
	visible = true
	_pitch_btn.set_pressed_no_signal(ses.keep_pitch)
	_refresh()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey) or not ev.pressed:
		return
	var k := ev as InputEventKey
	var step := 250.0 if k.shift_pressed else 2000.0
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			start_pressed.emit()
		KEY_ESCAPE:
			back_pressed.emit()
		KEY_LEFT:
			timeline.set_cursor(timeline.cursor_ms - step)
		KEY_RIGHT:
			timeline.set_cursor(timeline.cursor_ms + step)
		KEY_A:
			_on_range(minf(timeline.cursor_ms, ses.b_ms - 1000.0), ses.b_ms)
		KEY_B:
			_on_range(ses.a_ms, maxf(timeline.cursor_ms, ses.a_ms + 1000.0))
		_:
			return
	_refresh()
	get_viewport().set_input_as_handled()
