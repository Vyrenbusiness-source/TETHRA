class_name NoteColorPicker
extends VBoxContainer

## Notenfarben einstellen. Aufbau von oben nach unten:
##   Kopf: Reiter 3D / 2D, Schalter "2D wie 3D", Zuruecksetzen.
##   Farbquelle: Automatisch / Eigene Farben / Nach Takt + ein Satz Erklaerung.
##   Links der Inhalt der Farbquelle (Vorlagen + Farbfelder je Spalte, Takt-Legende
##   oder Hinweis), rechts die Vorschau (3D: echte Spiel-Shader, 2D: Mini-Playfield).
## Ein Farbfeld oeffnet einen eigenen Farbwaehler im Spiel-Stil (Farbfeld, Farbton,
## Hex, zuletzt genutzt). Waehrend des Ziehens wird nur live gezeigt; gespeichert wird
## beim Schliessen ("Fertig", Klick daneben, Enter). Esc / "Verwerfen" stellt zurueck.
## Liest/schreibt NoteColors. Signal changed nach jeder gespeicherten Aenderung.

signal changed

const MODE_LABELS := {
	"auto": "Automatisch",
	"lanes": "Eigene Farben",
	"snap": "Nach Takt",
}
const MODE_HINTS := {
	"auto": "Die Noten nehmen die Farben von Map und Welt.",
	"lanes": "Jede Spalte bekommt ihre Farbe. Vorlage wählen oder ein Farbfeld anklicken.",
	"snap": "Die Farbe zeigt die Takt-Teilung der Note, wie in osu!.",
}
## Takt-Teiler, die die Legende zeigt.
const SNAP_LEGEND := [1, 2, 3, 4, 6, 8, 12, 16]
## Beispiel-Takt-Teiler je Spalte fuer die 2D-Vorschau im Modus "snap".
const SNAP_SAMPLE := [1, 2, 4, 3]
## So malt das Spiel ohne Welt-Farbe eine normale Note / einen Hold (Vorschau bei "auto").
const AUTO_NOTE := Color(0.58, 0.76, 0.94)
const AUTO_HOLD := Color(0.95, 0.72, 0.38)
## Ebene des Farbwaehlers: ueber Einstellungen, Pause-Menue und HUD.
const POPUP_LAYER := 128
const SWATCH := Vector2(70, 34)

var _is_2d := false
var _want_2d := false        ## gewuenschter Reiter (bleibt erhalten, solange verknuepft)
var _tab_btns: Array[Button] = []
var _link: CheckButton
var _reset_btn: Button
var _mode_btns := {}
var _hint: Label
var _editor: Control
var _auto_box: Control
var _snap_box: Control
var _chips := {}
var _lane_sw: Array[Button] = []
var _hold_sw: Array[Button] = []
var _key_lbls: Array[Label] = []
var _hold_auto: CheckButton
var _prev3d: _Prev3D
var _prev2d: _Prev2D
var _skin_note: Label
var _layer: CanvasLayer
var _popup: _ColorPopup
var _edit_lane := -1
var _edit_hold := false
var _edit_snap := {}
var _building := false
var _shown_2d := false


func _init() -> void:
	add_theme_constant_override("separation", 12)
	NoteColors.ensure_loaded()
	_build()
	_sync()


func _notification(what: int) -> void:
	# Seite gewechselt / Einstellungen zu: offenen Farbwaehler sauber schliessen
	# (die CanvasLayer erbt die Sichtbarkeit nicht).
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			if _popup != null and _popup.visible:
				_popup.finish(true)
		elif _prev2d != null and _is_2d:
			_prev2d.refresh()


# ------------------------------------------------------------------ Aufbau

func _build() -> void:
	_building = true
	# Kopf: 3D / 2D, "2D wie 3D", Zuruecksetzen.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	for i in 2:
		var b := Button.new()
		b.text = "3D" if i == 0 else "2D"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(64, 32)
		b.tooltip_text = tr("Farben für das 3D-Spielfeld") if i == 0 else tr("Farben für das 2D-Spielfeld")
		_style_toggle(b)
		b.pressed.connect(_on_tab.bind(i == 1))
		top.add_child(b)
		_tab_btns.append(b)
	_link = CheckButton.new()
	_link.text = tr("2D wie 3D")
	_link.tooltip_text = tr("2D nutzt dieselben Farben wie 3D")
	_link.toggled.connect(func(on: bool):
		if _building:
			return
		NoteColors.set_link_2d(on)
		_commit())
	top.add_child(_link)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_reset_btn = Button.new()
	_reset_btn.text = tr("Zurücksetzen")
	_reset_btn.tooltip_text = tr("Diesen Satz auf Automatisch und Standard-Farben zurücksetzen")
	UiTheme.style_ghost_button(_reset_btn, 10)
	_reset_btn.pressed.connect(_on_reset)
	top.add_child(_reset_btn)

	# Farbquelle.
	var src := VBoxContainer.new()
	src.add_theme_constant_override("separation", 6)
	add_child(src)
	src.add_child(_caption(tr("Farbquelle")))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	src.add_child(mrow)
	for m in NoteColors.MODES:
		var b := Button.new()
		b.text = tr(MODE_LABELS[m])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 34)
		b.tooltip_text = tr(MODE_HINTS[m])
		_style_toggle(b)
		b.pressed.connect(_on_mode.bind(m))
		mrow.add_child(b)
		_mode_btns[m] = b
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", UiTheme.DIM)
	_hint.add_theme_font_size_override("font_size", 13)
	src.add_child(_hint)

	# Inhalt links, Vorschau rechts.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_build_editor(left)
	_build_auto(left)
	_build_snap(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(right)
	right.add_child(_caption(tr("Vorschau")))
	_prev3d = _Prev3D.new()
	right.add_child(_prev3d)
	_prev2d = _Prev2D.new()
	right.add_child(_prev2d)
	_skin_note = Label.new()
	_skin_note.text = tr("Der gewählte 2D-Skin zeichnet eigene Bilder; die Farben gelten ohne Skin.")
	_skin_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skin_note.custom_minimum_size = Vector2(_Prev3D.BOX.x, 0)
	_skin_note.add_theme_color_override("font_color", UiTheme.DIM)
	_skin_note.add_theme_font_size_override("font_size", 12)
	right.add_child(_skin_note)

	_layer = CanvasLayer.new()
	_layer.layer = POPUP_LAYER
	add_child(_layer)
	_popup = _ColorPopup.new()
	_popup.live.connect(_on_popup_live)
	_popup.done.connect(_on_popup_done)
	_layer.add_child(_popup)
	_building = false


## Eigene Farben: Vorlagen, Raster Spalte x (Note, Hold), Holds automatisch.
func _build_editor(parent: Control) -> void:
	var ed := VBoxContainer.new()
	ed.add_theme_constant_override("separation", 10)
	parent.add_child(ed)
	_editor = ed
	ed.add_child(_caption(tr("Vorlagen")))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	ed.add_child(chips)
	for id in NoteColors.PRESET_IDS:
		var b := Button.new()
		b.text = tr(NoteColors.PRESET_NAMES[id])
		b.toggle_mode = true
		b.icon = _preset_icon(id)
		b.tooltip_text = tr("Vorlage übernehmen")
		_style_toggle(b, 10)
		b.pressed.connect(_on_preset.bind(id))
		chips.add_child(b)
		_chips[id] = b

	ed.add_child(_caption(tr("Farbe je Spalte")))
	var grid := GridContainer.new()
	grid.columns = NoteColors.LANES + 1
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	ed.add_child(grid)
	grid.add_child(Control.new())
	for i in NoteColors.LANES:
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(SWATCH.x, 0)
		l.add_theme_color_override("font_color", UiTheme.DIM)
		l.add_theme_font_size_override("font_size", 12)
		grid.add_child(l)
		_key_lbls.append(l)
	for hold in [false, true]:
		var t := Label.new()
		t.text = tr("Hold") if hold else tr("Note")
		t.custom_minimum_size = Vector2(52, 0)
		t.add_theme_color_override("font_color", UiTheme.DIM)
		grid.add_child(t)
		for i in NoteColors.LANES:
			var sw := _Swatch.new()
			sw.custom_minimum_size = SWATCH
			sw.name = ("Hold%d" if hold else "Note%d") % i
			sw.pressed.connect(_open_popup.bind(i, hold))
			grid.add_child(sw)
			if hold:
				_hold_sw.append(sw)
			else:
				_lane_sw.append(sw)
	_hold_auto = CheckButton.new()
	_hold_auto.text = tr("Holds automatisch etwas dunkler")
	_hold_auto.tooltip_text = tr("Aus: jede Hold-Farbe frei wählen")
	_hold_auto.toggled.connect(func(on: bool):
		if _building:
			return
		NoteColors.set_hold_auto(_is_2d, on)
		_commit())
	ed.add_child(_hold_auto)


## Automatisch: Hinweis + Knopf zu eigenen Farben.
func _build_auto(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	_auto_box = box
	var l := Label.new()
	l.text = tr("Ohne Welt-Farben sind normale Noten hellblau und Holds orange. Welten und Kiai färben um.")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	box.add_child(l)
	var b := Button.new()
	b.name = "UseOwn"
	b.text = tr("Eigene Farben wählen")
	UiTheme.style_button(b, false, 10)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(_on_mode.bind("lanes"))
	box.add_child(b)


## Nach Takt: Legende Teiler -> Farbe.
func _build_snap(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	_snap_box = box
	box.add_child(_caption(tr("Takt-Teilung")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for d in SNAP_LEGEND:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot := ColorRect.new()
		dot.color = NoteColors.snap_color(d)
		dot.custom_minimum_size = Vector2(22, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var l := Label.new()
		l.text = "1/%d" % d
		l.custom_minimum_size = Vector2(38, 0)
		row.add_child(l)
		grid.add_child(row)
	var n := Label.new()
	n.text = tr("Holds nehmen dieselbe Farbe, etwas dunkler.")
	n.add_theme_color_override("font_color", UiTheme.DIM)
	n.add_theme_font_size_override("font_size", 12)
	box.add_child(n)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	return l


## Knopf im Spiel-Look; gewaehlter Zustand deutlich mit Akzent-Rand und -Toenung.
func _style_toggle(b: Button, radius: int = 12) -> void:
	UiTheme.style_button(b, false, radius)
	var on := UiTheme.glass_box(radius, 0.5, 0.0)
	on.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.22)
	on.border_color = UiTheme.ACCENT
	on.set_border_width_all(2)
	on.content_margin_left = 14
	on.content_margin_right = 14
	on.content_margin_top = 5
	on.content_margin_bottom = 5
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)


## Vier kleine Farbpunkte als Chip-Symbol.
func _preset_icon(id: String) -> ImageTexture:
	var cols: Array = NoteColors.preset_colors(id)
	var img := Image.create(40, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in cols.size():
		var c: Color = cols[i]
		for y in 12:
			for x in 10:
				var d := Vector2(x - 4.5, y - 5.5).length()
				if d <= 4.6:
					img.set_pixel(i * 10 + x, y, Color(c.r, c.g, c.b, clampf(4.9 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ Bedienung

## Reiter auf den aktuellen Spielmodus stellen (3D oder 2D).
func show_mode(is_2d: bool) -> void:
	_want_2d = is_2d
	_sync()


func _on_tab(is_2d: bool) -> void:
	_want_2d = is_2d
	_sync()


func _on_mode(m: String) -> void:
	NoteColors.set_mode(_is_2d, m)
	_commit()


func _on_preset(id: String) -> void:
	NoteColors.apply_preset(_is_2d, id)
	_commit()


func _on_reset() -> void:
	NoteColors.reset(_is_2d)
	_commit()


func _open_popup(lane: int, hold: bool) -> void:
	_edit_lane = lane
	_edit_hold = hold
	_edit_snap = NoteColors.snapshot(_is_2d)
	var sw: Control = (_hold_sw if hold else _lane_sw)[lane]
	var cur := NoteColors.hold_color(_is_2d, lane) if hold else NoteColors.lane_color(_is_2d, lane)
	var title := tr("Spalte %d") % (lane + 1) + "  ·  " + (tr("Hold") if hold else tr("Note"))
	var avoid := Rect2()
	var pv: Control = _prev2d if _is_2d else _prev3d
	if pv.is_visible_in_tree():
		avoid = pv.get_global_rect()
	_popup.open(title, cur, sw.get_global_rect(), avoid, sw)


func _on_popup_live(c: Color) -> void:
	if _edit_lane < 0:
		return
	if _edit_hold:
		NoteColors.set_hold_color(_is_2d, _edit_lane, c)
	else:
		NoteColors.set_lane_color(_is_2d, _edit_lane, c)
	if NoteColors.mode(_is_2d) != "lanes":
		NoteColors.set_mode(_is_2d, "lanes")
	_sync()


func _on_popup_done(keep: bool, c: Color) -> void:
	if _edit_lane < 0:
		return
	if keep:
		_on_popup_live(c)
		NoteColors.push_recent(c)
		_edit_lane = -1
		_commit()
	else:
		NoteColors.restore(_is_2d, _edit_snap)
		_edit_lane = -1
		_sync()


func _commit() -> void:
	NoteColors.save()
	_sync()
	changed.emit()


## Oberflaeche aus NoteColors aufbauen (ohne Signale auszuloesen).
func _sync() -> void:
	_building = true
	var linked := NoteColors.link_2d()
	_is_2d = _want_2d and not linked
	_tab_btns[0].button_pressed = not _is_2d
	_tab_btns[0].text = tr("3D + 2D") if linked else "3D"
	_tab_btns[1].button_pressed = _is_2d
	_tab_btns[1].visible = not linked
	_link.button_pressed = linked
	var m := NoteColors.mode(_is_2d)
	for k in _mode_btns:
		(_mode_btns[k] as Button).button_pressed = (k == m)
	_hint.text = tr(MODE_HINTS[m])
	_editor.visible = m == "lanes"
	_auto_box.visible = m == "auto"
	_snap_box.visible = m == "snap"
	var ha := NoteColors.hold_auto(_is_2d)
	_hold_auto.button_pressed = ha
	var keys: Array = _lane_keys()
	for i in NoteColors.LANES:
		var lc := NoteColors.lane_color(_is_2d, i)
		var hc := NoteColors.hold_color(_is_2d, i)
		(_lane_sw[i] as _Swatch).set_color(lc)
		(_hold_sw[i] as _Swatch).set_color(hc, ha)
		_lane_sw[i].tooltip_text = "%s · %s  #%s" % [tr("Spalte %d") % (i + 1), tr("Note"), lc.to_html(false).to_upper()]
		_hold_sw[i].tooltip_text = "%s · %s  #%s%s" % [tr("Spalte %d") % (i + 1), tr("Hold"),
				hc.to_html(false).to_upper(), ("  (" + tr("automatisch") + ")") if ha else ""]
		_key_lbls[i].text = "%d · %s" % [i + 1, keys[i]] if i < keys.size() and keys[i] != "" else str(i + 1)
	var pid := NoteColors.preset(_is_2d)
	for id in _chips:
		(_chips[id] as Button).button_pressed = (id == pid)
	_prev3d.visible = not _is_2d
	_prev2d.visible = _is_2d
	_prev3d.refresh(_is_2d)
	if _is_2d != _shown_2d:
		_shown_2d = _is_2d
		if _is_2d:
			_prev2d.refresh()   # Skin/Spurbreite neu lesen; Farben holt _feed jedes Bild
	var sk := _skin_2d()
	_skin_note.visible = _is_2d and sk != ""
	_building = false


func _lane_keys() -> Array:
	var out := []
	var s: Node = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
	if s == null:
		return out
	for k in s.get("key_lanes"):
		out.append(UiTheme.key_short(OS.get_keycode_string(int(k))))
	return out


func _skin_2d() -> String:
	var s: Node = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
	return String(s.get("skin_2d")) if s != null else ""


## Farbe, die das Spiel fuer diese Vorschau-Note nimmt.
static func sample_color(lane: int, hold: bool, is_2d: bool, div: int = 0) -> Color:
	var d: int = div if div > 0 else SNAP_SAMPLE[lane % SNAP_SAMPLE.size()]
	return NoteColors.color_for(lane, hold, is_2d, AUTO_HOLD if hold else AUTO_NOTE, d)


# ------------------------------------------------------------------ Farbfeld

## Farbfeld-Knopf: volle Farbe (kein Schachbrett), Rand bei Hover, Akzent-Ring bei Fokus.
class _Swatch extends Button:
	var color := Color.WHITE
	var auto := false

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func set_color(c: Color, is_auto: bool = false) -> void:
		color = c
		auto = is_auto
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.55 if is_hovered() else 0.16)
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		if auto:
			# Kleines "A": Farbe kommt automatisch aus der Notenfarbe.
			var f := get_theme_default_font()
			var dark := color.get_luminance() > 0.55
			draw_string(f, Vector2(size.x - 15, size.y - 7), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(0, 0, 0, 0.55) if dark else Color(1, 1, 1, 0.7))
		if has_focus():
			var fr := StyleBoxFlat.new()
			fr.draw_center = false
			fr.set_corner_radius_all(10)
			fr.set_border_width_all(2)
			fr.border_color = UiTheme.ACCENT
			fr.expand_margin_left = 3
			fr.expand_margin_right = 3
			fr.expand_margin_top = 3
			fr.expand_margin_bottom = 3
			draw_style_box(fr, r)


# ------------------------------------------------------------------ Farbwaehler

## Eigener Farbwaehler (Overlay in einer CanvasLayer): Saettigung/Helligkeit-Feld
## (nur der erlaubte Helligkeitsbereich, gewaehlt = gespeichert), Farbton-Leiste,
## Vorher/Neu, Hex, zuletzt genutzte Farben, Verwerfen/Fertig.
## Klick daneben = Fertig (wird verschluckt, schliesst nichts dahinter), Esc = Verwerfen.
class _ColorPopup extends Control:
	signal live(c: Color)
	signal done(keep: bool, c: Color)

	const W := 268.0
	const SV_H := 150.0
	const GAP := 10.0

	var _panel: PanelContainer
	var _title: Label
	var _sv: _SVField
	var _hue: _HueBar
	var _old_btn: Button
	var _new_rect: ColorRect
	var _hex: LineEdit
	var _recent_lbl: Label
	var _recent: HBoxContainer
	var _old := Color.WHITE
	var _h := 0.0
	var _s := 1.0
	var _v := 0.9
	var _return_focus: Control

	func _init() -> void:
		visible = false
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_panel = PanelContainer.new()
		var sb := UiTheme.glass_box(14, 0.97, 0.22)
		sb.bg_color = Color(0.07, 0.08, 0.12, 0.98)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 14
		sb.shadow_size = 22
		sb.shadow_color = Color(0, 0, 0, 0.55)
		_panel.add_theme_stylebox_override("panel", sb)
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", GAP)
		_panel.add_child(vb)
		_title = Label.new()
		_title.add_theme_font_override("font", UiTheme.heading_font(1))
		_title.add_theme_font_size_override("font_size", 14)
		vb.add_child(_title)
		_sv = _SVField.new()
		_sv.custom_minimum_size = Vector2(W, SV_H)
		_sv.changed.connect(func(s: float, v: float):
			_s = s
			_v = v
			_emit_live())
		vb.add_child(_sv)
		_hue = _HueBar.new()
		_hue.custom_minimum_size = Vector2(W, 16)
		_hue.changed.connect(func(h: float):
			_h = h
			_emit_live())
		vb.add_child(_hue)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		var cmp := HBoxContainer.new()
		cmp.add_theme_constant_override("separation", 0)
		row.add_child(cmp)
		_old_btn = Button.new()
		_old_btn.name = "Old"
		_old_btn.custom_minimum_size = Vector2(44, 30)
		_old_btn.tooltip_text = tr("Vorherige Farbe")
		_old_btn.focus_mode = Control.FOCUS_NONE
		_old_btn.pressed.connect(func(): _set_color(_old, true))
		cmp.add_child(_old_btn)
		_new_rect = ColorRect.new()
		_new_rect.custom_minimum_size = Vector2(44, 30)
		_new_rect.tooltip_text = tr("Neue Farbe")
		cmp.add_child(_new_rect)
		var hash := Label.new()
		hash.text = "#"
		hash.add_theme_color_override("font_color", UiTheme.DIM)
		row.add_child(hash)
		_hex = LineEdit.new()
		_hex.name = "Hex"
		_hex.max_length = 7
		_hex.custom_minimum_size = Vector2(0, 30)
		_hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hex.tooltip_text = tr("Hex-Farbe, z. B. 33D9FF. Enter übernimmt.")
		var hb := UiTheme.glass_box(8, 0.6, 0.18)
		hb.shadow_size = 0
		hb.content_margin_left = 8
		hb.content_margin_right = 8
		var hf := hb.duplicate() as StyleBoxFlat
		hf.border_color = UiTheme.ACCENT
		_hex.add_theme_stylebox_override("normal", hb)
		_hex.add_theme_stylebox_override("focus", hf)
		_hex.text_submitted.connect(func(_t: String): _apply_hex())
		_hex.focus_exited.connect(_apply_hex)
		row.add_child(_hex)

		_recent_lbl = Label.new()
		_recent_lbl.add_theme_color_override("font_color", UiTheme.DIM)
		_recent_lbl.add_theme_font_size_override("font_size", 12)
		vb.add_child(_recent_lbl)
		_recent = HBoxContainer.new()
		_recent.add_theme_constant_override("separation", 6)
		vb.add_child(_recent)

		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		btns.alignment = BoxContainer.ALIGNMENT_END
		vb.add_child(btns)
		var cancel := Button.new()
		cancel.name = "Cancel"
		cancel.text = tr("Verwerfen")
		cancel.tooltip_text = tr("Esc")
		UiTheme.style_ghost_button(cancel, 10)
		cancel.pressed.connect(func(): finish(false))
		btns.add_child(cancel)
		var ok := Button.new()
		ok.name = "Done"
		ok.text = tr("Fertig")
		ok.tooltip_text = tr("Enter")
		UiTheme.style_button(ok, true, 10)
		ok.pressed.connect(func(): finish(true))
		btns.add_child(ok)

	func open(title: String, c: Color, anchor: Rect2, avoid: Rect2, return_focus: Control) -> void:
		_title.text = title
		_old = c
		_return_focus = return_focus
		var ob := StyleBoxFlat.new()
		ob.bg_color = c
		ob.corner_radius_top_left = 6
		ob.corner_radius_bottom_left = 6
		for st in ["normal", "hover", "pressed"]:
			_old_btn.add_theme_stylebox_override(st, ob)
		_fill_recent()
		_set_color(c, false)
		visible = true
		_panel.reset_size()
		_panel.position = _place(anchor, avoid, _panel.get_combined_minimum_size())
		_sv.grab_focus()

	## Platz neben dem Farbfeld: unten, oben, rechts, links; nie ueber der Vorschau,
	## immer ganz im Fenster.
	func _place(anchor: Rect2, avoid: Rect2, sz: Vector2) -> Vector2:
		var vr := get_viewport_rect()
		var m := 8.0
		var cands := [
			Vector2(anchor.position.x, anchor.end.y + 6),
			Vector2(anchor.position.x, anchor.position.y - 6 - sz.y),
			Vector2(anchor.end.x + 8, anchor.get_center().y - sz.y * 0.5),
			Vector2(anchor.position.x - 8 - sz.x, anchor.get_center().y - sz.y * 0.5),
		]
		var best := Vector2.ZERO
		var best_score := INF
		for i in cands.size():
			var p: Vector2 = cands[i]
			var cp := Vector2(clampf(p.x, m, vr.size.x - sz.x - m), clampf(p.y, m, vr.size.y - sz.y - m))
			var r := Rect2(cp, sz)
			var score := (cp - p).length() + i * 2.0
			if avoid.has_area() and r.intersects(avoid):
				score += 10000.0
			if r.grow(4).intersects(anchor):
				score += 5000.0
			if score < best_score:
				best_score = score
				best = cp
		return best

	func _fill_recent() -> void:
		for c in _recent.get_children():
			c.queue_free()
		var cols: Array = NoteColors.recent()
		_recent_lbl.text = tr("Zuletzt genutzt") if not cols.is_empty() else tr("Vorschläge")
		if cols.is_empty():
			for id in ["standard", "neon"]:
				for c in NoteColors.preset_colors(id):
					cols.append(c)
		for i in mini(cols.size(), NoteColors.RECENT_MAX):
			var c: Color = cols[i]
			var b := Button.new()
			b.custom_minimum_size = Vector2(26, 26)
			b.tooltip_text = "#" + c.to_html(false).to_upper()
			b.focus_mode = Control.FOCUS_NONE
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(6)
			var hv := sb.duplicate() as StyleBoxFlat
			hv.set_border_width_all(2)
			hv.border_color = Color(1, 1, 1, 0.8)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", hv)
			b.add_theme_stylebox_override("pressed", hv)
			b.pressed.connect(func(): _set_color(c, true))
			_recent.add_child(b)

	func _set_color(c: Color, emit: bool) -> void:
		var cc := NoteColors.clamp_color(c)
		_h = cc.h
		_s = cc.s
		_v = cc.v
		_update_view()
		if emit:
			live.emit(current())

	func current() -> Color:
		return NoteColors.clamp_color(Color.from_hsv(_h, _s, _v))

	func _emit_live() -> void:
		_update_view()
		live.emit(current())

	func _update_view() -> void:
		var c := current()
		_sv.set_hsv(_h, _s, _v)
		_hue.set_hue(_h)
		_new_rect.color = c
		if not _hex.has_focus():
			_hex.text = c.to_html(false).to_upper()

	func _apply_hex() -> void:
		if not visible:
			return
		var t := _hex.text.strip_edges().trim_prefix("#")
		if t.length() in [3, 6] and Color.html_is_valid(t):
			_set_color(Color.html(t), true)
		_hex.text = current().to_html(false).to_upper()

	func finish(keep: bool) -> void:
		if not visible:
			return
		if keep and _hex.has_focus():
			_apply_hex()
		visible = false
		done.emit(keep, current() if keep else _old)
		if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
			_return_focus.grab_focus()

	func _gui_input(e: InputEvent) -> void:
		# Klick neben den Waehler: uebernehmen und schliessen; der Klick geht
		# NICHT an die Einstellungen dahinter (sonst schloss er das ganze Fenster).
		if e is InputEventMouseButton and e.pressed:
			accept_event()
			if e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
				finish(true)

	func _input(e: InputEvent) -> void:
		if not visible or not (e is InputEventKey) or not e.pressed:
			return
		if e.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finish(false)
		elif (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and not _hex.has_focus():
			get_viewport().set_input_as_handled()
			finish(true)


const _SV_SHADER := """shader_type canvas_item;
uniform float hue = 0.0;
uniform float vmin = 0.55;
uniform float vmax = 0.95;
uniform vec2 px = vec2(268.0, 150.0);
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
void fragment() {
	vec2 p = UV * px;
	vec2 q = abs(p - px * 0.5) - (px * 0.5 - 8.0);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 8.0;
	float a = clamp(0.5 - d, 0.0, 1.0);
	COLOR = vec4(hsv(hue, UV.x, mix(vmax, vmin, UV.y)), a);
}
"""

const _HUE_SHADER := """shader_type canvas_item;
uniform vec2 px = vec2(268.0, 16.0);
vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}
void fragment() {
	vec2 p = UV * px;
	float r = px.y * 0.5;
	vec2 q = abs(p - px * 0.5) - (px * 0.5 - r);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	COLOR = vec4(hsv(UV.x, 0.9, 0.95), clamp(0.5 - d, 0.0, 1.0));
}
"""


## Saettigung (x) / Helligkeit (y, nur MIN_V..MAX_V). Maus ziehen oder Pfeiltasten.
class _SVField extends Control:
	signal changed(s: float, v: float)
	var _s := 1.0
	var _v := 0.9
	var _mat: ShaderMaterial
	var _mark: Control

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = NoteColorPicker._SV_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("vmin", NoteColors.MIN_V)
		_mat.set_shader_parameter("vmax", NoteColors.MAX_V)
		bg.material = _mat
		add_child(bg)
		_mark = Control.new()
		_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mark.draw.connect(_draw_mark)
		add_child(_mark)
		resized.connect(func(): _mat.set_shader_parameter("px", size))
		focus_entered.connect(_mark.queue_redraw)
		focus_exited.connect(_mark.queue_redraw)

	func set_hsv(h: float, s: float, v: float) -> void:
		_s = s
		_v = v
		_mat.set_shader_parameter("hue", h)
		_mark.queue_redraw()

	func _pos() -> Vector2:
		var t := inverse_lerp(NoteColors.MAX_V, NoteColors.MIN_V, _v)
		return Vector2(clampf(_s, 0.0, 1.0) * size.x, clampf(t, 0.0, 1.0) * size.y)

	func _draw_mark() -> void:
		var p := _pos()
		_mark.draw_arc(p, 8.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 4.0, true)
		_mark.draw_arc(p, 8.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		if has_focus():
			_mark.draw_arc(p, 12.0, 0.0, TAU, 32, UiTheme.ACCENT, 2.0, true)

	func _pick(p: Vector2) -> void:
		_s = clampf(p.x / maxf(size.x, 1.0), 0.0, 1.0)
		_v = lerpf(NoteColors.MAX_V, NoteColors.MIN_V, clampf(p.y / maxf(size.y, 1.0), 0.0, 1.0))
		_mark.queue_redraw()
		changed.emit(_s, _v)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			grab_focus()
			_pick(e.position)
			accept_event()
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_pick(e.position)
			accept_event()
		elif e is InputEventKey and e.pressed:
			var d := Vector2.ZERO
			match e.keycode:
				KEY_LEFT: d.x = -1
				KEY_RIGHT: d.x = 1
				KEY_UP: d.y = -1
				KEY_DOWN: d.y = 1
			if d != Vector2.ZERO:
				_pick(_pos() + d * size * 0.03)
				accept_event()


## Farbton-Leiste. Maus ziehen oder Pfeiltasten (links/rechts).
class _HueBar extends Control:
	signal changed(h: float)
	var _h := 0.0
	var _mat: ShaderMaterial
	var _mark: Control

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = NoteColorPicker._HUE_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		bg.material = _mat
		add_child(bg)
		_mark = Control.new()
		_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mark.draw.connect(_draw_mark)
		add_child(_mark)
		resized.connect(func(): _mat.set_shader_parameter("px", size))
		focus_entered.connect(_mark.queue_redraw)
		focus_exited.connect(_mark.queue_redraw)

	func set_hue(h: float) -> void:
		_h = h
		_mark.queue_redraw()

	func _draw_mark() -> void:
		var x := clampf(_h, 0.0, 1.0) * size.x
		var c := Vector2(x, size.y * 0.5)
		_mark.draw_circle(c, size.y * 0.5 + 3.0, Color.from_hsv(_h, 0.9, 0.95))
		_mark.draw_arc(c, size.y * 0.5 + 3.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 4.0, true)
		_mark.draw_arc(c, size.y * 0.5 + 3.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		if has_focus():
			_mark.draw_arc(c, size.y * 0.5 + 7.0, 0.0, TAU, 32, UiTheme.ACCENT, 2.0, true)

	func _pick(x: float) -> void:
		_h = clampf(x / maxf(size.x, 1.0), 0.0, 0.999)
		_mark.queue_redraw()
		changed.emit(_h)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			grab_focus()
			_pick(e.position.x)
			accept_event()
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_pick(e.position.x)
			accept_event()
		elif e is InputEventKey and e.pressed and (e.keycode == KEY_LEFT or e.keycode == KEY_RIGHT):
			_pick(_h * size.x + (1.0 if e.keycode == KEY_RIGHT else -1.0) * size.x / 72.0)
			accept_event()


# ------------------------------------------------------------------ 3D-Vorschau

## Kurzes Stueck Strecke mit den ECHTEN Spiel-Shadern (note_disc, glow_dot, HoldBeam)
## und denselben Parametern wie mania_3d._on_note_spawned (ohne Welt-Effekte/Bloom).
class _Prev3D extends SubViewportContainer:
	const BOX := Vector2(300, 210)
	const ROAD_Y := -1.6
	const RAIL_X := [-2.55, -0.85, 0.85, 2.55]
	const Z_LINE := 3.0
	const NOTE_SIZE := 1.12
	const NOTE_GLOW := 0.34
	const PAD := Color(0.52, 0.54, 0.60)
	## [Spalte, z, Hold-Laenge (0 = Einzelnote), Takt-Teiler]
	const NOTES := [[0, 1.2, 0.0, 1], [3, 0.4, 0.0, 3], [1, -0.6, 3.6, 2], [2, -2.6, 0.0, 4],
			[0, -4.2, 0.0, 4], [3, -5.6, 2.6, 1], [2, -8.0, 0.0, 2]]

	var _vp: SubViewport
	var _items: Array = []   ## je Note {lane, hold, div, disc, glow, spot, trail, beam}
	var _note_sh: Shader
	var _glow_sh: Shader

	func _init() -> void:
		custom_minimum_size = BOX
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vp = SubViewport.new()
		_vp.size = Vector2i(BOX)
		_vp.own_world_3d = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_vp)
		_note_sh = load("res://shaders/note_disc.gdshader")
		_glow_sh = load("res://shaders/glow_dot.gdshader")
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.035, 0.04, 0.07)
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)
		var cam := Camera3D.new()
		cam.fov = 42.0
		var eye := Vector3(0, 4.3, 7.6)
		cam.transform = Transform3D(Basis.looking_at(Vector3(0, ROAD_Y, 0.2) - eye, Vector3.UP), eye)
		cam.current = true
		_vp.add_child(cam)
		# Strasse + Spurlinien, ruhig und dunkel.
		var road := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60.0, 80.0)
		road.mesh = pm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(0.06, 0.07, 0.11)
		road.material_override = rm
		road.position = Vector3(0, ROAD_Y, -30.0)
		_vp.add_child(road)
		for x in [-3.6, -1.7, 0.0, 1.7, 3.6]:
			var ln := MeshInstance3D.new()
			var lm := PlaneMesh.new()
			lm.size = Vector2(0.03, 40.0)
			ln.mesh = lm
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(0.16, 0.18, 0.25)
			ln.material_override = mm
			ln.position = Vector3(x, ROAD_Y + 0.005, -12.0)
			_vp.add_child(ln)
		# Receptor-Ringe an der Linie (wie im Spiel: gleicher Shader, leerer Kern).
		for i in 4:
			var pad := _quad(NOTE_SIZE, _note_sh)
			var m := pad.material_override as ShaderMaterial
			m.set_shader_parameter("base_color", PAD)
			m.set_shader_parameter("rim_color", PAD * 0.85)
			m.set_shader_parameter("fill_alpha", 0.0)
			m.set_shader_parameter("rim_boost", 0.0)
			pad.position = Vector3(RAIL_X[i], ROAD_Y + 0.30, Z_LINE)
			_vp.add_child(pad)
		for n in NOTES:
			var lane: int = n[0]
			var root := Node3D.new()
			root.position = Vector3(RAIL_X[lane], ROAD_Y + 0.32, float(n[1]))
			var it := {"lane": lane, "hold": float(n[2]) > 0.0, "div": int(n[3])}
			if it.hold:
				var beam := HoldBeam.new()
				_vp.add_child(beam)
				beam.setup(0.92, Color.WHITE)
				beam.set_span(float(n[1]), float(n[1]) - float(n[2]), RAIL_X[lane], ROAD_Y + 0.28)
				it.beam = beam
			it.disc = _quad(NOTE_SIZE, _note_sh)
			root.add_child(it.disc)
			it.glow = _quad(1.55, _glow_sh)
			it.glow.position = Vector3(0, -0.02, 0)
			root.add_child(it.glow)
			it.spot = _quad(1.1, _glow_sh, Vector2(1.1, 0.8))
			it.spot.position = Vector3(0, -0.30, 0)
			root.add_child(it.spot)
			it.trail = _quad(0.55, _glow_sh, Vector2(0.55, 1.7))
			it.trail.position = Vector3(0, -0.05, -1.05)
			root.add_child(it.trail)
			_vp.add_child(root)
			_items.append(it)

	func _quad(sz: float, sh: Shader, rect: Vector2 = Vector2.ZERO) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = rect if rect != Vector2.ZERO else Vector2(sz, sz)
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = sh
		mi.material_override = m
		mi.rotation_degrees = Vector3(-90, 0, 0)
		return mi

	## Farben neu setzen (wie mania_3d: Kern base, Ring base*1.15, Glow/Spot/Schweif).
	func refresh(is_2d: bool) -> void:
		for it in _items:
			var col := NoteColorPicker.sample_color(it.lane, it.hold, is_2d, it.div)
			var rim := (it.disc as MeshInstance3D).material_override as ShaderMaterial
			rim.set_shader_parameter("base_color", col)
			rim.set_shader_parameter("rim_color", col * 1.15)
			rim.set_shader_parameter("fill_alpha", 0.22)
			rim.set_shader_parameter("halo_strength", 0.7)
			rim.set_shader_parameter("rim_boost", 0.3)
			var gm := (it.glow as MeshInstance3D).material_override as ShaderMaterial
			gm.set_shader_parameter("base_color", col)
			gm.set_shader_parameter("intensity", NOTE_GLOW)
			var sm := (it.spot as MeshInstance3D).material_override as ShaderMaterial
			sm.set_shader_parameter("base_color", col)
			sm.set_shader_parameter("intensity", 0.10)
			var tm := (it.trail as MeshInstance3D).material_override as ShaderMaterial
			tm.set_shader_parameter("base_color", col)
			tm.set_shader_parameter("intensity", 0.35)
			if it.has("beam"):
				((it.beam as HoldBeam).material_override as ShaderMaterial).set_shader_parameter("beam_color", col)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	func sample_point(i: int) -> Vector2:
		## Bildposition (in der Vorschau) der Note i, fuer Tests.
		var it: Dictionary = _items[i]
		var cam := _vp.get_camera_3d()
		var p := ((it.disc as Node3D).get_parent() as Node3D).position
		return cam.unproject_position(p) * (size / Vector2(_vp.size))


# ------------------------------------------------------------------ 2D-Vorschau

## PlayfieldPreview (gleicher Ablauf wie dort: Treffer an der Linie, Holds gehalten),
## aber mit den Notenfarben aus NoteColors statt der festen Vorschau-Farben.
class _Prev2D extends PlayfieldPreview:
	func _feed() -> void:
		if _pf == null:
			return
		_pf.begin_frame()
		var ph := _t / PERIOD
		var held := [false, false, false, false]
		var fresh := _prev.size() != NOTES.size()
		if fresh:
			_prev.resize(NOTES.size())
		for i in NOTES.size():
			var n: Array = NOTES[i]
			var col: int = n[0]
			var f := fposmod(ph + float(n[1]), 1.0)
			var z := ZF + (ZL - ZF) * f * SPAN
			var zt := z - (ZL - ZF) * float(n[2])
			var is_hold := float(n[2]) > 0.0
			var c := NoteColorPicker.sample_color(col, is_hold, true)
			var p: Variant = _prev[i]
			_prev[i] = [z, zt]
			if not fresh and p != null and float(p[0]) <= z:
				if float(p[0]) < ZL and z >= ZL:
					_hit(col)
				if is_hold and float(p[1]) < ZL and zt >= ZL:
					_hit(col)
			if not is_hold:
				if z < ZL:
					_pf.add_note(col, z, c)
				elif z < ZL + PRESS_Z:
					held[col] = true
			elif zt < ZL:
				if z >= ZL:
					held[col] = true
					_pf.add_hold(col, z, zt, c, Playfield2D.STATE_HELD)
				else:
					_pf.add_hold(col, z, zt, c)
		_pf.set_combo(_combo)
		_pf.set_lanes(held, [], [])
