class_name OffsetWizard
extends Control

## Offset-Kalibrierung: gleichmäßiger Metronom-Klick (oder blinkender Kreis),
## der Spieler tippt mit. Nach HITS_NEEDED Treffern wird aus dem Median der
## Abweichungen ein Vorschlag für Settings.offset_ms berechnet.
## Eigener AudioStreamPlayer, unabhängig von SyncClock.

signal finished(applied: bool)

const BPM := 120.0
const BEAT := 60.0 / BPM
const LEAD_IN := 4          ## Takt-Einzähler, wird nicht gewertet
const HITS_NEEDED := 16
const WINDOW := 0.25        ## Sekunden: Tipp zählt nur nahe an einem Klick
const OUTLIER_MS := 100.0   ## Abstand zum Median, ab dem ein Tipp verworfen wird
const TIMELINE_RANGE := 150.0

enum Phase { INTRO, RUN, RESULT }

var _phase: int = Phase.INTRO
var _visual := false
var _player: AudioStreamPlayer
var _devs: Array[float] = []   ## Abweichungen in ms (+ = zu spät)
var _used: Dictionary = {}     ## Klick-Index -> bereits getippt
var _suggest := 0
var _intro_box: Control
var _run_box: Control
var _result_box: Control
var _status: Label
var _result_label: Label
var _circle: Control
var _timeline: Control
var _flash := 0.0
var _last_beat := -1


# ------------------------------ reine Logik ---------------------------------

static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s: Array = values.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


## Wirft Ausreißer (weit weg vom Median) raus und gibt die übrigen zurück.
static func reject_outliers(values: Array, limit_ms: float = OUTLIER_MS) -> Array:
	if values.size() < 3:
		return values.duplicate()
	var m := median(values)
	var out: Array = []
	for v in values:
		if absf(float(v) - m) <= limit_ms:
			out.append(v)
	return out if not out.is_empty() else values.duplicate()


## Vorschlag für Settings.offset_ms: Judgement = Song + Offset, wer im Schnitt
## X ms zu spät drückt, braucht also -X.
static func suggest_offset(devs: Array) -> int:
	var clean := reject_outliers(devs)
	return clampi(int(roundf(-median(clean))), -200, 200)


## Zeit der Klicks im Stream (Sekunden).
static func click_time(i: int) -> float:
	return 0.5 + float(i) * BEAT


## Index des Klicks, der t am nächsten liegt (kann <0 oder zu groß sein).
static func nearest_click(t: float) -> int:
	return int(roundf((t - 0.5) / BEAT))


# ------------------------------ Aufbau --------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := UiTheme.glass_box(18, 0.86)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Offset kalibrieren"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", UiTheme.heading_font())
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	vb.add_child(title)

	_intro_box = VBoxContainer.new()
	_intro_box.add_theme_constant_override("separation", 10)
	vb.add_child(_intro_box)
	_intro_box.add_child(_text(tr("Tippe bei jedem Klick die Leertaste (oder eine Hook-Taste). Nach %d Treffern schlage ich dir einen Offset vor.") % HITS_NEEDED, UiTheme.DIM))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	_intro_box.add_child(modes)
	modes.add_child(_button("Audio-Test starten", true, func(): _start(false)))
	modes.add_child(_button("Bild-Test (blinkender Kreis)", false, func(): _start(true)))
	_intro_box.add_child(_button("Abbrechen", false, func(): _finish(false)))

	_run_box = VBoxContainer.new()
	_run_box.add_theme_constant_override("separation", 12)
	_run_box.visible = false
	vb.add_child(_run_box)
	_status = _text("", UiTheme.ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_run_box.add_child(_status)
	_circle = Control.new()
	_circle.custom_minimum_size = Vector2(0, 110)
	_circle.draw.connect(_draw_circle)
	_run_box.add_child(_circle)
	_run_box.add_child(_button("Abbrechen", false, func(): _finish(false)))

	_timeline = Control.new()
	_timeline.custom_minimum_size = Vector2(0, 46)
	_timeline.draw.connect(_draw_timeline)
	vb.add_child(_timeline)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 12)
	_result_box.visible = false
	vb.add_child(_result_box)
	_result_label = _text("", UiTheme.TEXT)
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_box.add_child(_result_label)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 10)
	_result_box.add_child(rb)
	rb.add_child(_button("Übernehmen", true, _apply))
	rb.add_child(_button("Nochmal", false, func(): _start(_visual)))
	rb.add_child(_button("Abbrechen", false, func(): _finish(false)))

	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	set_process(false)


func _text(t: String, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	return l


func _button(t: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(b, primary)
	b.pressed.connect(cb)
	return b


## Ganze Klickfolge als ein Stream: sample-genau, kein Frame-Jitter.
func _build_stream() -> AudioStreamWAV:
	var tick: PackedByteArray = Sfx.hit_stream().data
	var total := int(Sfx.RATE * (click_time(LEAD_IN + HITS_NEEDED + 2) + 0.5))
	var data := PackedByteArray()
	data.resize(total * 2)
	data.fill(0)
	for i in LEAD_IN + HITS_NEEDED + 3:
		var start := int(click_time(i) * Sfx.RATE) * 2
		var n := mini(tick.size(), data.size() - start)
		for j in range(0, n - 1, 2):
			data.encode_s16(start + j, tick.decode_s16(j))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = Sfx.RATE
	wav.stereo = false
	wav.data = data
	return wav


func _start(visual: bool) -> void:
	_visual = visual
	_devs.clear()
	_used.clear()
	_last_beat = -1
	_phase = Phase.RUN
	_intro_box.visible = false
	_result_box.visible = false
	_run_box.visible = true
	_circle.visible = visual
	_status.text = "Mach dich bereit …"
	_player.stream = _build_stream()
	_player.volume_db = -80.0 if visual else 0.0   # Bild-Test: Stream nur als Uhr
	_player.play()
	set_process(true)
	_timeline.queue_redraw()


## Position im Stream in Sekunden (Ausgabelatenz kompensiert, wie SyncClock).
func _stream_pos() -> float:
	if not _player.playing:
		return -1.0
	var p := _player.get_playback_position() + AudioServer.get_time_since_last_mix()
	if not _visual:
		p -= AudioServer.get_output_latency()
	return p


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if _phase == Phase.RUN:
		var pos := _stream_pos()
		if pos >= 0.0:
			var b := nearest_click(pos)
			if b > _last_beat and click_time(b) <= pos:
				_last_beat = b
				_flash = 1.0
			if b < LEAD_IN:
				_status.text = tr("Einzähler … %d") % maxi(LEAD_IN - b, 1)
			else:
				_status.text = "%d / %d" % [_devs.size(), HITS_NEEDED]
		elif _phase == Phase.RUN and _last_beat >= LEAD_IN:
			# Stream zu Ende, zu wenig Treffer: neu starten.
			_start(_visual)
			_status.text = "Zu wenige Treffer – nochmal …"
	_circle.queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish(false)
		return
	if _phase != Phase.RUN:
		return
	var k: int = event.keycode
	if k != KEY_SPACE and k != _st().key_hook1 and k != _st().key_hook2:
		return
	get_viewport().set_input_as_handled()
	var pos := _stream_pos()
	if pos < 0.0:
		return
	var idx := nearest_click(pos)
	if idx < LEAD_IN or idx >= LEAD_IN + HITS_NEEDED + 2 or _used.has(idx):
		return
	var d := pos - click_time(idx)
	if absf(d) > WINDOW:
		return
	_used[idx] = true
	_devs.append(d * 1000.0)
	_timeline.queue_redraw()
	if _devs.size() >= HITS_NEEDED:
		_show_result()


func _show_result() -> void:
	_phase = Phase.RESULT
	_player.stop()
	set_process(false)
	var clean := reject_outliers(_devs)
	var m := median(clean)
	_suggest = suggest_offset(_devs)
	var dir := tr("zu spät") if m > 0.0 else tr("zu früh")
	_result_label.text = tr("Du drückst im Schnitt %d ms %s.\nVorschlag: Audio-Offset %+d ms (%d von %d Tipps gewertet)") % [
		int(roundf(absf(m))), dir, _suggest, clean.size(), _devs.size()]
	_run_box.visible = false
	_result_box.visible = true
	_timeline.queue_redraw()


func _apply() -> void:
	_st().offset_ms = float(_suggest)
	_st().apply()
	_finish(true)


func _finish(applied: bool) -> void:
	if _player != null:
		_player.stop()
	finished.emit(applied)
	queue_free()


# ------------------------------ Zeichnen ------------------------------------

func _draw_circle() -> void:
	var c := _circle.size * 0.5
	var r := 26.0 + 16.0 * _flash
	_circle.draw_circle(c, r + 10.0, Color(UiTheme.ACCENT, 0.12 * _flash))
	_circle.draw_circle(c, r, Color(UiTheme.ACCENT.lerp(Color.WHITE, _flash * 0.6), 0.35 + 0.65 * _flash))


func _draw_timeline() -> void:
	var w := _timeline.size.x
	var cy := _timeline.size.y * 0.5
	_timeline.draw_line(Vector2(0, cy), Vector2(w, cy), Color(1, 1, 1, 0.18), 2.0)
	_timeline.draw_line(Vector2(w * 0.5, cy - 14), Vector2(w * 0.5, cy + 14), UiTheme.GOOD, 2.0)
	var font := ThemeDB.fallback_font
	_timeline.draw_string(font, Vector2(2, cy + 24), tr("früh"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DIM)
	_timeline.draw_string(font, Vector2(w - 34, cy + 24), tr("spät"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DIM)
	for d in _devs:
		var x := w * 0.5 + clampf(d / TIMELINE_RANGE, -1.0, 1.0) * w * 0.5
		var col := UiTheme.ACCENT2 if absf(d) > OUTLIER_MS else UiTheme.ACCENT
		_timeline.draw_circle(Vector2(x, cy), 5.0, col)


## Autoload per Pfad: so bleibt die reine Logik auch in Headless-Skripttests ladbar.
func _st() -> Node:
	return get_node("/root/Settings")
