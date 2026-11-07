class_name ProfilePanel
extends Control

## Profil-Ansicht im osu-Web-Stil: grosser Kopf (Avatar, Name, pp, Plays),
## darunter scrollbare Sektionen TOP-LEISTUNGEN / LETZTE SPIELE / MEISTGESPIELT.
## Jede Zeile zeigt das Song-Cover (lazy im Thread geladen), Grade, Acc, pp
## und Datum — und startet die Map per Klick direkt.

signal closed

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := Color(0.6, 0.63, 0.72)
const COL_PP := UiTheme.ACCENT2
const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
	COLOR = vec4(mix(texture(screen_tex, SCREEN_UV).rgb, c * 0.38, amount), 1.0);
}
"""
const PANEL_BG := Color(0.08, 0.09, 0.14, 0.95)
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.82, 0.38),
	"A": Color(0.5, 0.92, 0.6), "B": Color(0.45, 0.72, 0.95),
	"C": Color(0.8, 0.62, 0.92), "D": Color(0.95, 0.5, 0.5),
	"F": Color(0.95, 0.45, 0.45),
}

var _avatar_slot: Control
var _remove_btn: Button
var _name_edit: LineEdit
var _name_hint: Label
var _file_dialog: FileDialog

var _library: MapLibrary
var _set_by_file: Dictionary = {}
# Lazy-Cover-Loader: [{rect: TextureRect, file: String}], sequentiell im Thread.
var _thumb_jobs: Array = []
var _thumb_thread: Thread
var _closing := false
var _thumb_cache: Dictionary = {}


func _ready() -> void:
	Sfx.ui_open()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	_library = MapLibrary.new()
	_library.scan()
	for ms in _library.mapsets:
		_set_by_file[str(ms.osz_path).get_file()] = ms

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color.WHITE
	var blur_sh := Shader.new()
	blur_sh.code = BLUR_SHADER
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = blur_sh
	blur_mat.set_shader_parameter("amount", 0.0)
	dim.material = blur_mat
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
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(860, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)

	# Sanftes Einblenden: Abdunklung + Panel faden, Panel waechst leicht.
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(430, 300)
	panel.scale = Vector2(0.98, 0.98)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(blur_mat, "shader_parameter/amount", 1.0, 0.28)
	tw.tween_property(panel, "modulate:a", 1.0, 0.28)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28)

	# ------------------------------ Kopfzeile -------------------------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	vb.add_child(head)

	_avatar_slot = Control.new()
	_avatar_slot.custom_minimum_size = Vector2(128, 128)
	_avatar_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar_slot.tooltip_text = "Klicken: Profilbild ändern"
	_avatar_slot.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_pick_avatar())
	head.add_child(_avatar_slot)
	_rebuild_avatar()

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)

	# Name nur EINMAL festlegbar (gleiche Regel wie Einstellungen > Gameplay):
	# solange "Player" -> Eingabe + Enter, danach nur Anzeige.
	var name_edit := LineEdit.new()
	name_edit.text = Settings.profile_name
	name_edit.max_length = Settings.NAME_MAX_LEN
	name_edit.add_theme_font_override("font", UiTheme.heading_font(2))
	name_edit.add_theme_font_size_override("font_size", 28)
	name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("focus", UiTheme.glass_box(8, 0.4, 0.25))
	name_edit.editable = Settings.can_set_name()
	info.add_child(name_edit)
	_name_edit = name_edit
	if name_edit.editable:
		_name_hint = Label.new()
		_name_hint.text = tr("Enter: Name festlegen · kann nur einmal geändert werden")
		_name_hint.add_theme_font_size_override("font_size", 12)
		_name_hint.add_theme_color_override("font_color", Color(COL_DIM, 0.85))
		info.add_child(_name_hint)
		name_edit.text_submitted.connect(func(t): _save_name(t))

	# Gesamt-pp gross in ACCENT2.
	var pp_row := HBoxContainer.new()
	pp_row.add_theme_constant_override("separation", 6)
	info.add_child(pp_row)
	var pp_big := Label.new()
	pp_big.text = _fmt_int(roundi(ScoreStore.profile_pp()))
	pp_big.add_theme_font_override("font", UiTheme.heading_font(1))
	pp_big.add_theme_font_size_override("font_size", 44)
	pp_big.add_theme_color_override("font_color", COL_PP)
	pp_row.add_child(pp_big)
	var pp_cap := Label.new()
	pp_cap.text = "pp"
	pp_cap.size_flags_vertical = Control.SIZE_SHRINK_END
	pp_cap.add_theme_font_size_override("font_size", 18)
	pp_cap.add_theme_color_override("font_color", COL_DIM)
	pp_row.add_child(pp_cap)

	# Rang-Verteilung als Chips + Accuracy-Schnitt.
	var counts := { "SS": 0, "S": 0, "A": 0, "B": 0 }
	var acc_sum := 0.0
	var acc_n := 0
	for be in ScoreStore.best_plays(99999):
		var gr := str(be.get("grade", ""))
		if counts.has(gr):
			counts[gr] += 1
		if float(be.get("accuracy", 0.0)) > 0.0:
			acc_sum += float(be.get("accuracy", 0.0))
			acc_n += 1
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info.add_child(chips)
	for gk in ["SS", "S", "A", "B"]:
		chips.add_child(_rank_chip(gk, int(counts[gk])))

	# Rechte Statistik-Spalte mit feiner Trennlinie.
	var vline := ColorRect.new()
	vline.color = Color(1, 1, 1, 0.08)
	vline.custom_minimum_size = Vector2(1, 96)
	vline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(vline)
	var stat_col := VBoxContainer.new()
	stat_col.add_theme_constant_override("separation", 10)
	stat_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stat_col.custom_minimum_size = Vector2(150, 0)
	head.add_child(stat_col)
	_head_stat(stat_col, _fmt_int(ScoreStore.total_plays()), "Spiele", UiTheme.TEXT)
	_head_stat(stat_col, _fmt_pct(acc_sum / acc_n) if acc_n > 0 else "—",
			"Genauigkeit", UiTheme.TEXT)
	_head_stat(stat_col, _fmt_playtime(), "Spielzeit", UiTheme.TEXT)

	var head_btns := VBoxContainer.new()
	head_btns.add_theme_constant_override("separation", 8)
	head.add_child(head_btns)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 38)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiTheme.style_button(close)
	close.pressed.connect(_close)
	head_btns.add_child(close)
	_remove_btn = Button.new()
	_remove_btn.text = "Bild entfernen"
	_remove_btn.custom_minimum_size = Vector2(0, 34)
	UiTheme.style_button(_remove_btn)
	_remove_btn.visible = Settings.avatar_texture() != null
	_remove_btn.pressed.connect(func():
		Settings.clear_avatar()
		_remove_btn.visible = false
		_rebuild_avatar())
	head_btns.add_child(_remove_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(1, 1, 1, 0.08))
	vb.add_child(sep)

	# --------------------------- Scroll-Sektionen ---------------------------
	var scroll_wrap := Control.new()
	scroll_wrap.custom_minimum_size = Vector2(0, 520)
	vb.add_child(scroll_wrap)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_wrap.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(pad)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	pad.add_child(list)
	# Weicher Fade am unteren Rand statt harter Kappung.
	var grad := Gradient.new()
	grad.set_color(0, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, 0.0))
	grad.set_color(1, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, 1.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 4
	gtex.height = 64
	var fade := TextureRect.new()
	fade.texture = gtex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -56
	fade.offset_right = -14
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_wrap.add_child(fade)

	_section(list, "TOP-LEISTUNGEN")
	var best := ScoreStore.best_plays(8)
	if best.is_empty():
		_empty_hint(list)
	for e in best:
		list.add_child(_play_row(e, "best"))

	_section(list, "LETZTE SPIELE")
	var recent := ScoreStore.recent_plays(6)
	if recent.is_empty():
		_empty_hint(list)
	for e in recent:
		list.add_child(_play_row(e, "recent"))

	_section(list, "MEISTGESPIELT")
	var most := ScoreStore.most_played(5)
	if most.is_empty():
		_empty_hint(list)
	for e in most:
		list.add_child(_play_row(e, "most"))

	# Cover lazy im Hintergrund laden (Panel oeffnet sofort).
	if not _thumb_jobs.is_empty():
		_thumb_thread = Thread.new()
		_thumb_thread.start(_thumb_worker)

	# Datei-Dialog fuer den Bild-Upload.
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Profilbild auswählen"
	_file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; " + tr("Bilder")]
	_file_dialog.size = Vector2(760, 520)
	_file_dialog.file_selected.connect(func(path):
		if Settings.set_avatar(path):
			_remove_btn.visible = true
			_rebuild_avatar())
	add_child(_file_dialog)


func _rank_chip(g: String, n: int) -> Control:
	var col: Color = GRADE_COLOR.get(g, UiTheme.DIM)
	var chip := PanelContainer.new()
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(col.r, col.g, col.b, 0.14 if n > 0 else 0.05)
	cb.border_color = Color(col.r, col.g, col.b, 0.45 if n > 0 else 0.15)
	cb.set_border_width_all(1)
	cb.set_corner_radius_all(10)
	cb.content_margin_left = 12
	cb.content_margin_right = 12
	cb.content_margin_top = 4
	cb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", cb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(hb)
	var lg := Label.new()
	lg.text = g
	lg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lg.add_theme_font_override("font", UiTheme.heading_font(1))
	lg.add_theme_font_size_override("font_size", 15)
	lg.add_theme_color_override("font_color", col if n > 0 else COL_DIM)
	hb.add_child(lg)
	var ln := Label.new()
	ln.text = str(n)
	ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ln.add_theme_font_override("font", UiTheme.heading_font(1))
	ln.add_theme_font_size_override("font_size", 15)
	ln.add_theme_color_override("font_color", UiTheme.TEXT if n > 0 else COL_DIM)
	hb.add_child(ln)
	return chip


## Tausendertrenner nach Sprache: 1234 -> "1.234" (de) / "1,234" (en).
func _fmt_int(v: int) -> String:
	return UiTheme.fmt_score(v)


## Prozent nach Sprache: 0.8509 -> "85,09 %" (de) / "85.09%" (en).
func _fmt_pct(frac: float) -> String:
	return UiTheme.fmt_pct(frac * 100.0)


## Geschaetzte Spielzeit: Plays x Kartenlaenge (Abbrueche nicht erfasst).
func _fmt_playtime() -> String:
	var ms := 0.0
	for e in ScoreStore.most_played(99999):
		var ms_set = _set_by_file.get(str(e.get("osz_file", "")))
		if ms_set != null:
			ms += ms_set.length_ms() * int(e.get("count", 0))
	var mins := int(ms / 60000.0)
	if mins < 1:
		return "—"
	if mins < 60:
		return "%d min" % mins
	return "%dh %02dm" % [mins / 60, mins % 60]


func _head_stat(row: Container, value: String, caption: String, col: Color) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	row.add_child(box)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", UiTheme.heading_font(1))
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", col)
	box.add_child(v)
	var c := Label.new()
	c.text = caption
	c.add_theme_font_size_override("font_size", 12)
	c.add_theme_color_override("font_color", COL_DIM)
	box.add_child(c)


func _section(list: VBoxContainer, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	list.add_child(spacer)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", COL_ACCENT)
	list.add_child(l)


func _empty_hint(list: VBoxContainer) -> void:
	var empty := Label.new()
	empty.text = "Noch keine Spiele — leg los!"
	empty.add_theme_font_size_override("font_size", 13)
	empty.add_theme_color_override("font_color", COL_DIM)
	list.add_child(empty)


## Eine Play-Zeile im osu-Web-Stil: Cover · Titel/Diff/Datum · Grade · pp · ▶.
## mode: "best" (Datum + Acc), "recent" (Datum, Fail rot), "most" (Nx gespielt).
func _play_row(e: Dictionary, mode: String) -> Control:
	var row := PanelContainer.new()
	var rb := UiTheme.glass_box(12, 0.38, 0.08)
	rb.shadow_size = 0
	rb.set_content_margin_all(9)
	row.add_theme_stylebox_override("panel", rb)
	var rb_hover := rb.duplicate() as StyleBoxFlat
	rb_hover.bg_color = Color(0.14, 0.17, 0.26, 0.62)
	rb_hover.border_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.4)
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", rb_hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", rb))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)

	var osz_file := str(e.get("osz_file", ""))
	var playable := _set_by_file.has(osz_file)

	# Cover-Thumb (Platzhalter, echtes Bild kommt aus dem Loader-Thread).
	var thumb_holder := PanelContainer.new()
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.10, 0.12, 0.18)
	tb.set_corner_radius_all(7)
	thumb_holder.add_theme_stylebox_override("panel", tb)
	thumb_holder.custom_minimum_size = Vector2(84, 48)
	thumb_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(thumb_holder)
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.custom_minimum_size = Vector2(84, 48)
	thumb_holder.add_child(thumb)
	if playable:
		_thumb_jobs.append({ "rect": thumb, "file": osz_file })

	# Titel + Sub-Zeile.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 1)
	hb.add_child(mid)
	var title := Label.new()
	# Mirror-Downloads heissen "mirror_<id>" — dann den echten Artist/Titel
	# aus der Bibliothek anzeigen.
	var map_name := str(e.get("map", "?"))
	if playable and map_name.begins_with("mirror_"):
		var ms0: MapSet = _set_by_file[osz_file]
		if ms0.title != "":
			map_name = ("%s - %s" % [ms0.artist, ms0.title]) if ms0.artist != "" else ms0.title
	title.text = map_name
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.94, 0.95, 1.0))
	mid.add_child(title)
	var sub := Label.new()
	var sub_parts: Array[String] = []
	if str(e.get("version", "")) != "":
		sub_parts.append(_diff_name(str(e.get("version", ""))))
	if mode == "most":
		sub_parts.append(tr("%s× gespielt") % _fmt_int(int(e.get("count", 0))))
	var date := _fmt_date(str(e.get("date", "")))
	if date != "":
		sub_parts.append(date)
	if float(e.get("accuracy", 0.0)) > 0.0:
		sub_parts.append(_fmt_pct(float(e.get("accuracy", 0.0))))
	if int(e.get("max_combo", 0)) > 0:
		sub_parts.append("%sx" % _fmt_int(int(e.get("max_combo", 0))))
	sub.text = "  ·  ".join(sub_parts)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COL_DIM)
	mid.add_child(sub)

	# Grade-Badge (Fail rot).
	var g := str(e.get("grade", ""))
	if mode == "recent" and bool(e.get("failed", false)):
		g = "F"
	var gcol: Color = GRADE_COLOR.get(g, Color(0.7, 0.72, 0.8))
	var badge := PanelContainer.new()
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(gcol.r, gcol.g, gcol.b, 0.16)
	bb.border_color = Color(gcol.r, gcol.g, gcol.b, 0.5)
	bb.set_border_width_all(1)
	bb.set_corner_radius_all(9)
	bb.content_margin_left = 6
	bb.content_margin_right = 6
	bb.content_margin_top = 2
	bb.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", bb)
	badge.custom_minimum_size = Vector2(46, 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(badge)
	var grade := Label.new()
	grade.text = g if g != "" else "—"
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.add_theme_font_override("font", UiTheme.heading_font(1))
	grade.add_theme_font_size_override("font_size", 20)
	grade.add_theme_color_override("font_color", gcol)
	badge.add_child(grade)

	# pp rechts, gross.
	var pp_label := Label.new()
	var ppv := float(e.get("pp", -1.0))
	pp_label.text = (_fmt_int(roundi(ppv)) + " pp") if ppv >= 0.0 else "—"
	pp_label.custom_minimum_size = Vector2(88, 0)
	pp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pp_label.add_theme_font_override("font", UiTheme.heading_font(1))
	pp_label.add_theme_font_size_override("font_size", 24)
	pp_label.add_theme_color_override("font_color", COL_PP)
	hb.add_child(pp_label)

	# Direkt spielen.
	var play := Button.new()
	play.text = "▶"
	play.custom_minimum_size = Vector2(46, 40)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.disabled = not playable
	play.tooltip_text = "Map spielen" if playable else "Map nicht (mehr) in der Bibliothek"
	_style_ghost_icon(play)
	var version := str(e.get("version", ""))
	play.pressed.connect(func(): _start_map(osz_file, version))
	hb.add_child(play)

	if playable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_start_map(osz_file, version))
	return row


## Diff-Name ohne Leerraum und ohne vorhandene Klammern -> "[Name]".
func _diff_name(v: String) -> String:
	var t := v.strip_edges()
	while t.begins_with("["):
		t = t.substr(1).strip_edges()
	while t.ends_with("]"):
		t = t.left(t.length() - 1).strip_edges()
	return "[%s]" % t


## Ghost-Icon-Button: transparent, Fuellung nur bei Hover.
func _style_ghost_icon(b: Button) -> void:
	var none := StyleBoxEmpty.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.22)
	hover.set_corner_radius_all(10)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.34)
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("disabled", none)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", none)
	b.add_theme_color_override("font_color", COL_DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	b.add_theme_color_override("font_pressed_color", UiTheme.ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.3))
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE


## "2026-07-19T11:33:20" -> "19.07.2026" (en: "2026-07-19")
func _fmt_date(iso: String) -> String:
	if iso == "":
		return ""
	var d := iso.split("T")[0].split("-")
	if d.size() != 3:
		return iso
	if not UiTheme.is_german():
		return "%s-%s-%s" % [d[0], d[1], d[2]]
	return "%s.%s.%s" % [d[2], d[1], d[0]]


## Map direkt aus dem Profil starten (gleiche Diff wie der Play).
func _start_map(osz_file: String, version: String) -> void:
	if not _set_by_file.has(osz_file):
		return
	var ms: MapSet = _set_by_file[osz_file]
	var idx := 0
	for i in ms.difficulty_count():
		if ms.version_name_at(i) == version:
			idx = i
			break
	# Gleiche Mods wie im Song-Browser (bleiben an, bis man sie ausschaltet).
	GameSession.mods = {"NF": Settings.mod_nf, "SV": Settings.mod_sv}
	GameSession.is_replay = false
	GameSession.set_selection(ms.osz_path, idx, ms.version_name_at(idx),
			ms.osu_filename_at(idx), ms.stars_at(idx))
	get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")


# ---------------------------------------------------------------------------
# Cover-Loader (Thread): laedt die Hintergrundbilder der Zeilen nacheinander.
# ---------------------------------------------------------------------------

func _thumb_worker() -> void:
	for job in _thumb_jobs:
		if _closing:
			return
		var file: String = job.file
		var img: Image = null
		if _thumb_cache.has(file):
			img = _thumb_cache[file]
		else:
			var ms: MapSet = _set_by_file.get(file)
			if ms == null:
				continue
			var tex: Texture2D = ms.background_texture()
			if tex == null:
				continue
			img = tex.get_image()
			if img == null:
				continue
			if img.is_compressed():
				if img.decompress() != OK:
					continue
			var w := img.get_width()
			var h := img.get_height()
			if w > 220:
				img.resize(220, maxi(int(220.0 * float(h) / float(w)), 8),
						Image.INTERPOLATE_LANCZOS)
			_thumb_cache[file] = img
		call_deferred("_apply_thumb", job.rect, img)


func _apply_thumb(rect: TextureRect, img: Image) -> void:
	if _closing or not is_instance_valid(rect) or img == null:
		return
	rect.texture = ImageTexture.create_from_image(img)


## Avatar-Kreis neu aufbauen: eigenes Bild oder Initial auf Farbflaeche.
func _rebuild_avatar() -> void:
	for c in _avatar_slot.get_children():
		c.queue_free()
	var tex := Settings.avatar_texture()
	if tex != null:
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/avatar_circle.gdshader")
		rect.material = m
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_slot.add_child(rect)
	else:
		# Verlauf-Ring (Cyan -> Pink) um dunkle Flaeche mit Initiale.
		var ring := _circle_rect(_gradient_tex(UiTheme.ACCENT, UiTheme.ACCENT2), 0)
		_avatar_slot.add_child(ring)
		var inner := _circle_rect(_gradient_tex(Color(0.10, 0.20, 0.30), Color(0.16, 0.10, 0.26)), 5)
		_avatar_slot.add_child(inner)
		var initial := Label.new()
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.text = Settings.profile_name.strip_edges().substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_override("font", UiTheme.heading_font(1))
		initial.add_theme_font_size_override("font_size", 56)
		initial.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_slot.add_child(initial)


func _circle_rect(tex: Texture2D, inset: int) -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = inset
	r.offset_top = inset
	r.offset_right = -inset
	r.offset_bottom = -inset
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = tex
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/avatar_circle.gdshader")
	m.set_shader_parameter("border_col", Color(1, 1, 1, 0.0))
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _gradient_tex(a: Color, b: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 1)
	t.width = 128
	t.height = 128
	return t


func _pick_avatar() -> void:
	_file_dialog.popup_centered()


## Einmaliges Festlegen; Fehler ruhig im Hinweis, danach nur noch Anzeige.
func _save_name(t: String) -> void:
	var err := Settings.set_name_once(t)
	if err != "":
		if _name_hint != null:
			_name_hint.text = tr(err)
			_name_hint.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45, 0.95))
		return
	if _name_edit != null:
		_name_edit.text = Settings.profile_name
		_name_edit.editable = false
		_name_edit.release_focus()
	if _name_hint != null:
		_name_hint.queue_free()
		_name_hint = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Sfx.ui_back()
		_close(false)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_closing = true
	if _thumb_thread != null and _thumb_thread.is_started():
		_thumb_thread.wait_to_finish()


func _close(with_sound: bool = true) -> void:
	if with_sound:
		Sfx.ui_close()
	Settings.save()
	closed.emit()
	queue_free()
