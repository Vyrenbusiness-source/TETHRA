class_name AutomapCheck
extends Control

## Schritt "Takt pruefen" nach dem Erzeugen einer Map aus eigener Musik:
## Metronom-Klick ueber dem Song, Tempo x2 / x0,5 / x1,5, Offset -/+ 5 ms,
## "Neu erzeugen". Der Klick wird als Spur vorgemischt und im selben Frame wie
## der Song gestartet, liegt also samplegenau auf dem Gitter (kein Frame-Jitter).
## Texte: translations/automap.csv (Schluessel Englisch).

## Nutzer will mit geaendertem Takt neu erzeugen. opts: {tempo_factor, offset_ms}.
signal regenerate(opts: Dictionary)
signal closed

const WINDOW_MS := 24000.0
const OFFSET_STEP := 5.0
const FACTORS := [[0.5, "×0.5"], [1.5, "×1.5"], [2.0, "×2"]]

var _info: Dictionary = {}
var _factor := 1.0     ## Korrektur gegenueber dem erzeugten Gitter
var _offset := 0.0
var _grid: Dictionary = {}
var _beats: Array = []       ## [t_ms, ist_taktanfang] im Fenster
var _t0 := 0.0               ## Fensterbeginn im Song (ms)
var _song: AudioStreamPlayer
var _click: AudioStreamPlayer
var _bpm_label: Label
var _offset_label: Label
var _regen_btn: Button
var _strip: Control
var _beat_in_bar := -1
var _meter := 4
var _flash := 0.0


## info: Ergebnis von AutoMapper4K.generate (osz_path, audio_path, grid, bpm,
## artist, title, tempo_factor, user_offset_ms, confidence).
static func open(parent: Control, info: Dictionary) -> AutomapCheck:
	var c := AutomapCheck.new()
	c._info = info
	parent.add_child(c)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := UiTheme.modal_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var pb := UiTheme.solid_box(UiTheme.SURFACE, 14)
	pb.set_border_width_all(1)
	pb.border_color = UiTheme.LINE
	pb.content_margin_left = 28
	pb.content_margin_right = 28
	pb.content_margin_top = 24
	pb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", pb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	vb.add_child(UiTheme.modal_header("Check the beat", close))

	var song := _label(vb, "%s  ·  %s" % [str(_info.get("artist", "")), str(_info.get("title", ""))], 14, UiTheme.DIM)
	song.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	song.autowrap_mode = TextServer.AUTOWRAP_OFF
	song.clip_text = true

	# Tempo gross links, Takt-Streifen rechts daneben.
	var read := HBoxContainer.new()
	read.add_theme_constant_override("separation", 22)
	vb.add_child(read)
	var num := HBoxContainer.new()
	num.add_theme_constant_override("separation", 8)
	read.add_child(num)
	_bpm_label = _label(num, "", 54, UiTheme.TEXT)
	_bpm_label.add_theme_font_override("font", UiTheme.heading_font(0))
	var unit := _label(num, "BPM", 13, UiTheme.DIM)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	unit.add_theme_constant_override("line_spacing", 0)
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(0, 46)
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip.draw.connect(_draw_strip)
	read.add_child(_strip)

	var hint := _label(vb, tr("The click should land exactly on the beat of the music. If it runs twice as fast, half as fast or between the beats, correct it here and regenerate."), 13, UiTheme.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(UiTheme.hairline())

	var tempo := _row(vb, "Tempo")
	for f in FACTORS:
		var b := _button(tempo, tr(str(f[1])), false)
		b.custom_minimum_size.x = 76
		b.pressed.connect(_mul.bind(float(f[0])))
	var off := _row(vb, "Offset")
	_button(off, tr("−5 ms"), false).pressed.connect(_shift.bind(-OFFSET_STEP))
	_offset_label = _label(off, "", 15, UiTheme.TEXT)
	_offset_label.custom_minimum_size.x = 84
	_offset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(off, tr("+5 ms"), false).pressed.connect(_shift.bind(OFFSET_STEP))

	vb.add_child(UiTheme.hairline())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	vb.add_child(foot)
	_button(foot, tr("Looks right"), false).pressed.connect(close)
	_regen_btn = _button(foot, tr("Regenerate"), true)
	_regen_btn.pressed.connect(_on_regenerate)

	_song = AudioStreamPlayer.new()
	add_child(_song)
	_click = AudioStreamPlayer.new()
	add_child(_click)
	var ext := str(_info.get("audio_path", "x.mp3")).get_extension().to_lower()
	_song.stream = OszImporter.load_audio_stream_named(str(_info.get("osz_path", "")), "audio." + ext)
	_song.volume_db = -5.0
	_apply()


func _label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, primary: bool) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 15)
	if primary:
		UiTheme.style_button(b, true, 10)
	else:
		UiTheme.style_ghost_button(b, 10)
	parent.add_child(b)
	return b


## Zeile: Bezeichnung links in fester Breite, Knoepfe daneben.
func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _label(row, tr(title), 14, UiTheme.DIM)
	l.custom_minimum_size.x = 96
	return row


func _mul(f: float) -> void:
	_factor *= f
	# x2 nach x0,5 (und umgekehrt) hebt sich auf; Rundungsreste glaetten.
	if absf(_factor - 1.0) < 0.01:
		_factor = 1.0
	_apply()


func _shift(d: float) -> void:
	_offset += d
	_apply()


func changed() -> bool:
	return _factor != 1.0 or _offset != 0.0


## Optionen fuer den naechsten Lauf (absolut, bezogen auf das erkannte Gitter).
func next_opts() -> Dictionary:
	return {"tempo_factor": float(_info.get("tempo_factor", 1.0)) * _factor,
		"offset_ms": float(_info.get("user_offset_ms", 0.0)) + _offset}


func _on_regenerate() -> void:
	var o := next_opts()
	_stop()
	regenerate.emit(o)


func close() -> void:
	_stop()
	closed.emit()
	queue_free()


func _stop() -> void:
	set_process(false)
	if _song != null:
		_song.stop()
		_click.stop()


## Gitter mit der aktuellen Korrektur neu aufbauen, Anzeige und Klick-Spur dazu.
func _apply() -> void:
	var base: Dictionary = _info.get("grid", {})
	if (base.get("segments", []) as Array).is_empty():
		return
	_grid = AutoMapper4K.adjusted_grid(base, _factor, _offset)
	var dur := _song.stream.get_length() * 1000.0 if _song.stream != null else 0.0
	var seg := AutoMapper4K.main_segment(_grid, dur)
	_meter = maxi(int(seg.get("meter", 4)), 1)
	_bpm_label.text = UiTheme.fmt_num(60000.0 / float(seg.beat_ms), 1)
	var total := float(_info.get("user_offset_ms", 0.0)) + _offset
	_offset_label.text = "%s%d ms" % ["+" if total > 0.0 else ("−" if total < 0.0 else "±"), int(absf(total))]
	_regen_btn.disabled = not changed()
	# Fenster: ab dem ersten Drittel (dort ist meist voller Klang), auf einem Taktanfang.
	var from := maxf(float(_grid.segments[0].start_ms), dur * 0.3)
	_t0 = from
	for b in AutoMapper4K.beat_times(_grid, from, from + 8000.0):
		if b[1]:
			_t0 = float(b[0])
			break
	_t0 = maxf(_t0 - 20.0, 0.0)
	_beats = AutoMapper4K.beat_times(_grid, _t0, _t0 + WINDOW_MS)
	_click.stream = _build_clicks()
	_restart()


func _restart() -> void:
	_beat_in_bar = -1
	if _song.stream != null:
		_song.play(_t0 / 1000.0)
	_click.play()
	set_process(true)


## Klick-Spur fuer das Fenster: Taktanfang voll, uebrige Schlaege leiser.
func _build_clicks() -> AudioStreamWAV:
	var tick: PackedByteArray = Sfx.hit_stream().data
	var data := PackedByteArray()
	data.resize(int(Sfx.RATE * WINDOW_MS / 1000.0) * 2)
	data.fill(0)
	for b in _beats:
		var start := int((float(b[0]) - _t0) / 1000.0 * Sfx.RATE) * 2
		if start < 0:
			continue
		var gain := 1.0 if b[1] else 0.55
		var n := mini(tick.size(), data.size() - start)
		for j in range(0, n - 1, 2):
			data.encode_s16(start + j, int(tick.decode_s16(j) * gain))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = Sfx.RATE
	wav.stereo = false
	wav.data = data
	return wav


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 5.0, 0.0)
	if not _click.playing:
		_restart()
		return
	var pos := (_click.get_playback_position() + AudioServer.get_time_since_last_mix()
		- AudioServer.get_output_latency()) * 1000.0 + _t0
	var idx := -1
	var bar_pos := -1
	for i in _beats.size():
		if float(_beats[i][0]) > pos:
			break
		idx = i
		bar_pos = 0 if _beats[i][1] else bar_pos + 1
	if idx >= 0 and bar_pos != _beat_in_bar:
		_beat_in_bar = bar_pos
		_flash = 1.0
	_strip.queue_redraw()


## Takt-Streifen: ein Feld je Schlag, das laufende leuchtet in Bernstein,
## der Taktanfang ist hoeher.
func _draw_strip() -> void:
	var w := _strip.size.x
	var h := _strip.size.y
	var gap := 6.0
	var cell := (w - gap * (_meter - 1)) / _meter
	for i in _meter:
		var ch := h if i == 0 else h * 0.62
		var r := Rect2(i * (cell + gap), h - ch, cell, ch)
		var col := UiTheme.RAISED
		if i == _beat_in_bar:
			col = UiTheme.RAISED.lerp(UiTheme.ACCENT, 0.45 + 0.55 * _flash)
		_strip.draw_rect(r, col)
		if i == 0:
			_strip.draw_rect(Rect2(r.position, Vector2(cell, 2)), Color(UiTheme.ACCENT, 0.7))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
