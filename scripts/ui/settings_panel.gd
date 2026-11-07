class_name SettingsPanel
extends Control

## Einstellungen — ruhiges Glas-Panel mit Kategorie-Leiste links:
## Gameplay, 2D-Spielfeld (nur im 2D-Modus), Welt (nur 3D), Grafik, Audio.
## Profilname/-bild wohnen in der Profil-Ansicht.

signal closed

const COL_DIM := UiTheme.DIM
const VALUE_W := 72.0
const CAP_W := 180.0
const ROW_H := 40.0
const PAGE_H := 480.0
const CTRL_H := 34.0

const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	COLOR = vec4(c * 0.38, 1.0);
}
"""

var _world_preview: WorldPreview
var _panel: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _tab_cur := 0
var _preview_2d: Control
var _rows_3d: Array[Control] = []

var _capturing := 0   # 0 = keine Aufnahme, 3..6 = Lane 1-4
var _lane_btns: Array[Button] = []
var _offset_value: Label
var _offset_slider: HSlider
var _vol_value: Label


func _ready() -> void:
	Sfx.ui_open()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color.WHITE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	dim.material = mat
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.95)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(780, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	_panel = panel

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	# Kopfzeile mit Schliessen-Knopf.
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "EINSTELLUNGEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UiTheme.heading_font(3))
	title.add_theme_font_size_override("font_size", 22)
	head.add_child(title)
	var close_x := Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(36, 36)
	UiTheme.style_button(close_x)
	close_x.pressed.connect(_close)
	head.add_child(close_x)

	# Kategorie-Leiste links, Seiten rechts.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	vb.add_child(body)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.custom_minimum_size = Vector2(150, 0)
	body.add_child(side)
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(0, PAGE_H)
	body.add_child(stack)

	var pg_game := _page(side, stack, "Gameplay")
	var pg_2d := _page(side, stack, "2D-Spielfeld")
	var pg_world := _page(side, stack, "Welt")
	var pg_gfx := _page(side, stack, "Grafik")
	var pg_audio := _page(side, stack, "Audio")

	# ------------------------------- GAMEPLAY -------------------------------
	var mode_2d := CheckButton.new()
	mode_2d.button_pressed = Settings.playfield_2d
	mode_2d.tooltip_text = "Klassische senkrechte Spuren ohne 3D-Welt; Hintergrund = Map-Bild"
	mode_2d.toggled.connect(func(on):
		Settings.playfield_2d = on
		_update_2d_rows())
	_row(pg_game, "2D-Modus", mode_2d, null)

	_slider_row(pg_game, "Scrollgeschwindigkeit", 0.5, 3.0, 0.1, Settings.mania_scroll,
		_fmt_x, func(v): Settings.mania_scroll = v)

	var spacing_row := _slider_row(pg_game, "Spurbreite", Settings.LANE_SPACING_MIN * 100.0,
		Settings.LANE_SPACING_MAX * 100.0, Settings.LANE_SPACING_STEP * 100.0,
		Settings.lane_spacing * 100.0,
		func(v): return _fmt_pct0(Settings.clamp_lane_spacing(v / 100.0)),
		func(v): Settings.lane_spacing = Settings.clamp_lane_spacing(v / 100.0),
		"Abstand der Spuren in der 3D-Welt. Unter 85 % werden die Noten leicht kleiner.")
	_rows_3d.append(spacing_row)

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 8)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, CTRL_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiTheme.style_button(b)
		var lane := i
		b.pressed.connect(func(): _start_capture(3 + lane))
		lane_row.add_child(b)
		_lane_btns.append(b)
	_row(pg_game, "Tasten 1–4", lane_row, null).tooltip_text = "Knopf anklicken, dann Taste drücken (Esc bricht ab)"

	# ------------------------------ 2D-SPIELFELD ----------------------------
	var note_style := OptionButton.new()
	note_style.add_item("Balken", Settings.NOTE_STYLE_BAR)
	note_style.add_item("Kreis", Settings.NOTE_STYLE_CIRCLE)
	note_style.select(Settings.note_style_2d)
	note_style.custom_minimum_size = Vector2(0, CTRL_H)
	note_style.item_selected.connect(func(i):
		Settings.note_style_2d = i
		_refresh_2d_preview())
	_row(pg_2d, "Notenform", note_style, null)

	_slider_row(pg_2d, "Spurbreite", Settings.SIZE_2D_MIN * 100.0, Settings.SIZE_2D_MAX * 100.0,
		Settings.SIZE_2D_STEP * 100.0, Settings.lane_width_2d * 100.0,
		func(v): return _fmt_pct0(Settings.clamp_2d_size(v / 100.0)),
		func(v):
			Settings.lane_width_2d = Settings.clamp_2d_size(v / 100.0)
			_refresh_2d_preview(),
		"Breite der 2D-Spalten (auch im Pausenmenü einstellbar)")

	_slider_row(pg_2d, "Notengröße", Settings.SIZE_2D_MIN * 100.0, Settings.SIZE_2D_MAX * 100.0,
		Settings.SIZE_2D_STEP * 100.0, Settings.note_size_2d * 100.0,
		func(v): return _fmt_pct0(Settings.clamp_2d_size(v / 100.0)),
		func(v):
			Settings.note_size_2d = Settings.clamp_2d_size(v / 100.0)
			_refresh_2d_preview(),
		"Höhe der Balken bzw. Größe der Kreise (auch im Pausenmenü einstellbar)")

	_slider_row(pg_2d, "Hintergrund", 0.0, 100.0, 5.0, Settings.bg_dim * 100.0,
		func(v): return _fmt_bg(Settings.clamp_bg_dim(v / 100.0)),
		func(v): Settings.bg_dim = Settings.clamp_bg_dim(v / 100.0),
		"Deckkraft des Map-Bilds; 0 % = Hintergrund aus (schwarz)")

	var blur_btn := CheckButton.new()
	blur_btn.button_pressed = Settings.bg_blur
	blur_btn.toggled.connect(func(on): Settings.bg_blur = on)
	_row(pg_2d, "Hintergrund-Unschärfe", blur_btn, null).tooltip_text = "Map-Bild unscharf zeichnen"

	if ResourceLoader.exists("res://scripts/ui/skin_picker.gd"):
		var skin = load("res://scripts/ui/skin_picker.gd").new()
		if skin is Control:
			if skin.has_signal("changed"):
				skin.connect("changed", _refresh_2d_preview)
			_row(pg_2d, "Skin", skin, null)

	_add_2d_preview(pg_2d)

	# --------------------------------- WELT ---------------------------------
	var wt := OptionButton.new()
	wt.add_item("Automatisch", 0)
	for wi in Settings.WORLD_ORDER.size():
		var wname: String = Settings.WORLD_ORDER[wi]
		wt.add_item(str(WorldTheme.LABELS.get(wname, wname)), wi + 1)
		if wname != "galaxy" and not WorldTheme.is_available(wname):
			wt.set_item_disabled(wt.get_item_count() - 1, true)
	wt.select(Settings.world_theme)
	wt.custom_minimum_size = Vector2(0, CTRL_H)
	wt.tooltip_text = "Automatisch: düstere Welt passend zum Song\n(intensiv = Bosskampf, ruhig = Frost, sonst Eklipse, Abgrund, Fraktal, Obsidian …)"
	wt.item_selected.connect(func(i):
		Settings.world_theme = i
		_world_preview.show_world("" if i == 0 else Settings.WORLD_ORDER[i - 1]))
	_row(pg_world, "Welt", wt, null)

	_world_preview = WorldPreview.new()
	var wp_center := CenterContainer.new()
	wp_center.custom_minimum_size = Vector2(0, WorldPreview.SIZE_PX.y + 8)
	pg_world.add_child(wp_center)
	wp_center.add_child(_world_preview)
	_world_preview.show_world(Settings.world_theme_name())

	var cam := OptionButton.new()
	cam.add_item("Komfort", 0)
	cam.add_item("Dynamisch", 1)
	cam.select(Settings.camera_mode)
	cam.custom_minimum_size = Vector2(0, CTRL_H)
	cam.item_selected.connect(func(i): Settings.camera_mode = i)
	_row(pg_world, "Kamera", cam, null).tooltip_text = "Komfort: ruhige Kamera, gegen Übelkeit\nDynamisch: volle Flug-Bewegung"

	var fx := OptionButton.new()
	fx.add_item("Aus", 0)
	fx.add_item("Dezent", 1)
	fx.add_item("Voll", 2)
	fx.select(Settings.tunnel_intensity)
	fx.custom_minimum_size = Vector2(0, CTRL_H)
	fx.item_selected.connect(func(i): Settings.tunnel_intensity = i)
	_row(pg_world, "Effekte", fx, null)

	# -------------------------------- GRAFIK --------------------------------
	var gfx := OptionButton.new()
	gfx.add_item("Niedrig", 0)
	gfx.add_item("Mittel (2x AA)", 1)
	gfx.add_item("Hoch (4x AA)", 2)
	gfx.add_item("Ultra (8x AA)", 3)
	gfx.add_item("Extrem (8x AA + SSAA)", 4)
	gfx.select(Settings.graphics_quality)
	gfx.custom_minimum_size = Vector2(0, CTRL_H)
	gfx.item_selected.connect(func(i):
		Settings.graphics_quality = i
		Settings.apply())
	_row(pg_gfx, "Qualität", gfx, null)

	var fps := OptionButton.new()
	fps.add_item("VSync", 0)
	fps.add_item("Unbegrenzt", 1)
	fps.add_item("240 FPS", 2)
	fps.add_item("360 FPS", 3)
	fps.add_item("480 FPS", 4)
	fps.select(Settings.fps_mode)
	fps.custom_minimum_size = Vector2(0, CTRL_H)
	fps.item_selected.connect(func(i):
		Settings.fps_mode = i
		Settings.apply())
	_row(pg_gfx, "FPS-Limit", fps, null)

	var lg := CheckButton.new()
	lg.button_pressed = Settings.lane_glow
	lg.toggled.connect(func(on): Settings.lane_glow = on)
	_row(pg_gfx, "Spur-Leuchten", lg, null).tooltip_text = "Spur leuchtet auf, wenn die Taste gedrückt wird"

	var fs := CheckButton.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.fullscreen = on; Settings.apply())
	_row(pg_gfx, "Vollbild", fs, null).tooltip_text = "Vollbild (F11)"

	# --------------------------------- AUDIO --------------------------------
	_vol_value = Label.new()
	_slider_row(pg_audio, "Lautstärke", -30.0, 0.0, 1.0, Settings.volume_db,
		func(v): return "%d dB" % int(v),
		func(v):
			Settings.volume_db = v
			Settings.apply(), "", _vol_value)

	var enh := CheckButton.new()
	enh.button_pressed = Settings.audio_enhance
	enh.toggled.connect(func(on):
		Settings.audio_enhance = on
		Settings.apply())
	_row(pg_audio, "Klarheit", enh, null).tooltip_text = "Hellere Höhen für mehr Klarheit"

	var no_fill := StyleBoxEmpty.new()
	var bass_ref: Array = [null]
	var set_bass_fill := func(v: float):
		var bs: HSlider = bass_ref[0]
		if bs == null:
			return
		if v <= 0.001:
			bs.add_theme_stylebox_override("grabber_area", no_fill)
			bs.add_theme_stylebox_override("grabber_area_highlight", no_fill)
		else:
			bs.remove_theme_stylebox_override("grabber_area")
			bs.remove_theme_stylebox_override("grabber_area_highlight")
	var bass_row := _slider_row(pg_audio, "Bass", 0.0, 1.0, 0.05, Settings.bass_boost,
		func(v): return "%d %%" % int(v * 100.0),
		func(v):
			set_bass_fill.call(v)
			Settings.bass_boost = v
			Settings.apply())
	bass_ref[0] = bass_row.get_meta("slider")
	set_bass_fill.call(Settings.bass_boost)

	var hs := CheckButton.new()
	hs.button_pressed = Settings.hitsounds
	hs.toggled.connect(func(on): Settings.hitsounds = on)
	_row(pg_audio, "Treffer-Sounds", hs, null)

	var hset := OptionButton.new()
	hset.add_item("Soft", 0)
	hset.add_item("Clap", 1)
	hset.add_item("Kick", 2)
	hset.select(Settings.hitsound_set)
	hset.custom_minimum_size = Vector2(0, CTRL_H)
	hset.item_selected.connect(func(i):
		Settings.hitsound_set = i
		Sfx.preview_hit(i))
	_row(pg_audio, "Hitsound", hset, null)

	_slider_row(pg_audio, "Treffer-Lautstärke", 0.0, 1.0, 0.05, Settings.hitsound_volume,
		func(v): return "%d %%" % int(v * 100.0),
		func(v): Settings.hitsound_volume = v)

	_offset_value = Label.new()
	var off_row := _slider_row(pg_audio, "Audio-Offset", -200.0, 200.0, 1.0, Settings.offset_ms,
		func(v): return "%+d ms" % int(v),
		func(v):
			Settings.offset_ms = v
			Settings.apply(), "Verschiebt die Noten gegenüber dem Ton", _offset_value)
	_offset_slider = off_row.get_meta("slider")
	var calib_btn := Button.new()
	calib_btn.text = "Kalibrieren"
	calib_btn.custom_minimum_size = Vector2(0, CTRL_H)
	UiTheme.style_button(calib_btn)
	calib_btn.pressed.connect(_open_wizard)
	_row(pg_audio, "Kalibrierung", calib_btn, null)

	# Fusszeile.
	var save := Button.new()
	save.text = "Speichern & Schließen"
	save.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_button(save, true)
	save.pressed.connect(_close)
	vb.add_child(save)

	_update_2d_rows()
	_show_page(0)
	_refresh_labels()

	# Sanftes Einblenden: Scale 0.96 -> 1 + Fade, 0.18 s.
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	_intro.call_deferred(panel)

	if OS.get_cmdline_args().has("--shot-settings"):
		_shot_pages.call_deferred()


func _intro(panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18)


## Harness (--shot-settings): jede Kategorie als PNG, danach 2D-Modus-Wechsel.
func _shot_pages() -> void:
	var dir := OS.get_environment("SETTINGS_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	await get_tree().create_timer(1.5).timeout
	for mode_2d in [false, true]:
		Settings.playfield_2d = mode_2d
		_update_2d_rows()
		for i in _pages.size():
			if not _tabs[i].visible:
				continue
			_show_page(i)
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			var path := dir.path_join("settings_%s_%d.png" % ["2d" if mode_2d else "3d", i])
			get_viewport().get_texture().get_image().save_png(path)
			print("SHOT ", path)
	get_tree().quit(0)


## Kategorie: Knopf in der Leiste + Seite (VBox) im Stapel.
func _page(side: VBoxContainer, stack: Control, caption: String) -> VBoxContainer:
	var idx := _pages.size()
	var pg := VBoxContainer.new()
	pg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pg.add_theme_constant_override("separation", 4)
	pg.visible = false
	stack.add_child(pg)
	_pages.append(pg)
	var b := Button.new()
	b.text = caption
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	var hv := StyleBoxFlat.new()
	hv.bg_color = Color(1, 1, 1, 0.06)
	hv.set_corner_radius_all(12)
	hv.content_margin_left = 14
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		Sfx.ui_click()
		_show_page(idx))
	side.add_child(b)
	_tabs.append(b)
	return pg


func _show_page(i: int) -> void:
	_tab_cur = i
	for k in _pages.size():
		_pages[k].visible = k == i
		var b := _tabs[k]
		if k == i:
			# Aktiv wie die Chips im Song-Browser: Akzent-Fuellung + Rand.
			var sel := StyleBoxFlat.new()
			sel.bg_color = Color(UiTheme.ACCENT, 0.16)
			sel.border_color = Color(UiTheme.ACCENT, 0.60)
			sel.set_border_width_all(1)
			sel.set_corner_radius_all(12)
			sel.content_margin_left = 14
			b.add_theme_stylebox_override("normal", sel)
			b.add_theme_color_override("font_color", UiTheme.ACCENT)
		else:
			var n := StyleBoxEmpty.new()
			n.content_margin_left = 14
			b.add_theme_stylebox_override("normal", n)
			b.add_theme_color_override("font_color", UiTheme.DIM)


## Regler-Zeile: fmt(v) -> Text, on_change(v). Optional eigenes Wert-Label.
## Der HSlider liegt zusaetzlich als Meta "slider" an der Zeile.
func _slider_row(pg: VBoxContainer, caption: String, mn: float, mx: float, step: float,
		val: float, fmt: Callable, on_change: Callable, tip: String = "", value: Label = null) -> Control:
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = val
	if value == null:
		value = Label.new()
	value.text = str(fmt.call(val))
	sl.value_changed.connect(func(v):
		on_change.call(v)
		value.text = str(fmt.call(v)))
	var r := _row(pg, caption, sl, value)
	r.tooltip_text = tip
	r.set_meta("slider", sl)
	return r


## 2D-Vorschau-Haken (Task playfield-preview): nur wenn das Skript existiert.
func _add_2d_preview(parent: Control) -> void:
	if not (ClassDB.class_exists("PlayfieldPreview") or ResourceLoader.exists("res://scripts/ui/playfield_preview.gd")):
		return
	var scr = load("res://scripts/ui/playfield_preview.gd")
	if scr == null:
		return
	_preview_2d = scr.new()
	var cc := CenterContainer.new()
	parent.add_child(cc)
	cc.add_child(_preview_2d)


func _refresh_2d_preview() -> void:
	if _preview_2d != null and is_instance_valid(_preview_2d) and _preview_2d.has_method("refresh"):
		_preview_2d.call("refresh")


## Einheitliche Zeile: Beschriftung links (feste Breite), Control mittig,
## Wert rechts (feste Breite; ohne Wert bleibt der Platz frei).
func _row(vb: VBoxContainer, caption: String, control: Control, value: Label) -> PanelContainer:
	var hov := PanelContainer.new()
	hov.mouse_filter = Control.MOUSE_FILTER_PASS
	var hn := StyleBoxFlat.new()
	hn.bg_color = Color(1, 1, 1, 0.0)
	hn.set_corner_radius_all(8)
	hn.content_margin_left = 10
	hn.content_margin_right = 10
	hn.content_margin_top = 2
	hn.content_margin_bottom = 2
	hov.add_theme_stylebox_override("panel", hn)
	hov.custom_minimum_size = Vector2(0, ROW_H)
	hov.mouse_entered.connect(func(): hn.bg_color = Color(1, 1, 1, 0.05))
	hov.mouse_exited.connect(func(): hn.bg_color = Color(1, 1, 1, 0.0))
	vb.add_child(hov)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	hov.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(CAP_W, 0)
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(cap)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control is CheckButton:
		# Schalter ganz rechts.
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		control.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(control)
		return hov
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if value == null:
		value = Label.new()
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", COL_DIM)
	value.custom_minimum_size = Vector2(VALUE_W, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return hov


## Hintergrund-Deckkraft: 0 -> "Aus", sonst "30 %".
static func _fmt_bg(v: float) -> String:
	return "Aus" if v <= 0.001 else _fmt_pct0(v)


## 0.85 -> "85 %".
static func _fmt_pct0(v: float) -> String:
	return UiTheme.fmt_num(v * 100.0, 0) + " %"


## Modus-abhaengig: im 2D-Modus 3D-Spurbreite und Reiter "Welt" ausblenden,
## im 3D-Modus den Reiter "2D-Spielfeld".
func _update_2d_rows() -> void:
	var on := Settings.playfield_2d
	for r in _rows_3d:
		r.visible = not on
	if _tabs.size() >= 3:
		_tabs[1].visible = on
		_tabs[2].visible = not on
	if _tab_cur < _tabs.size() and not _tabs[_tab_cur].visible:
		_show_page(0)


static func _fmt_x(v: float) -> String:
	return ("%.1f" % v).replace(".", ",") + "×"


func _refresh_labels() -> void:
	for i in _lane_btns.size():
		_lane_btns[i].text = UiTheme.key_short(Settings.key_lanes[i])
	if _capturing >= 3 and _capturing - 3 < _lane_btns.size():
		_lane_btns[_capturing - 3].text = "…"
	_offset_value.text = "%+d ms" % int(Settings.offset_ms)
	_vol_value.text = "%d dB" % int(Settings.volume_db)


func _open_wizard() -> void:
	var w := OffsetWizard.new()
	w.finished.connect(func(_applied: bool):
		_offset_slider.set_value_no_signal(Settings.offset_ms)
		_refresh_labels())
	add_child(w)


func _start_capture(which: int) -> void:
	_capturing = which
	_refresh_labels()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _capturing >= 3:
			if event.keycode != KEY_ESCAPE:
				Settings.key_lanes[_capturing - 3] = event.keycode
			_capturing = 0
			_refresh_labels()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			Sfx.ui_back()
			_close(false)
			get_viewport().set_input_as_handled()


func _close(with_sound: bool = true) -> void:
	if with_sound:
		Sfx.ui_close()
	Settings.save()
	Settings.apply()
	if _world_preview != null:
		_world_preview.release()
	closed.emit()
	queue_free()
