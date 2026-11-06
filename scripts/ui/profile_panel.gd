class_name ProfilePanel
extends Control

## Profil-Ansicht im osu-Web-Stil: grosser Kopf (Avatar, Name, pp, Plays),
## darunter scrollbare Sektionen BESTE PLAYS / LETZTE PLAYS / MEISTGESPIELT.
## Jede Zeile zeigt das Song-Cover (lazy im Thread geladen), Grade, Acc, pp
## und Datum — und startet die Map per Klick direkt.

signal closed

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := Color(0.6, 0.63, 0.72)
const COL_PP := UiTheme.ACCENT2
const GRADE_COLOR := {
	"SS": Color(1.0, 0.92, 0.55), "S": Color(1.0, 0.82, 0.38),
	"A": Color(0.5, 0.92, 0.6), "B": Color(0.45, 0.72, 0.95),
	"C": Color(0.8, 0.62, 0.92), "D": Color(0.95, 0.5, 0.5),
	"F": Color(0.95, 0.45, 0.45),
}

var _avatar_slot: Control
var _remove_btn: Button
var _file_dialog: FileDialog

var _library: MapLibrary
var _set_by_file: Dictionary = {}
# Lazy-Cover-Loader: [{rect: TextureRect, file: String}], sequentiell im Thread.
var _thumb_jobs: Array = []
var _thumb_thread: Thread
var _closing := false
var _thumb_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

	_library = MapLibrary.new()
	_library.scan()
	for ms in _library.mapsets:
		_set_by_file[str(ms.osz_path).get_file()] = ms

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.03, 0.0)
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
	panel.custom_minimum_size = Vector2(860, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)

	# Sanftes Einblenden: Abdunklung + Panel faden, Panel waechst leicht.
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(430, 300)
	panel.scale = Vector2(0.98, 0.98)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "color:a", 0.72, 0.28)
	tw.tween_property(panel, "modulate:a", 1.0, 0.28)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28)

	# ------------------------------ Kopfzeile -------------------------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	vb.add_child(head)

	_avatar_slot = Control.new()
	_avatar_slot.custom_minimum_size = Vector2(128, 128)
	_avatar_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar_slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar_slot.tooltip_text = "Klicken: Profilbild aendern"
	_avatar_slot.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_pick_avatar())
	head.add_child(_avatar_slot)
	_rebuild_avatar()

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(info)

	var name_edit := LineEdit.new()
	name_edit.text = Settings.profile_name
	name_edit.max_length = 20
	name_edit.add_theme_font_override("font", UiTheme.heading_font(2))
	name_edit.add_theme_font_size_override("font_size", 28)
	name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	name_edit.add_theme_stylebox_override("focus", UiTheme.glass_box(8, 0.4, 0.25))
	name_edit.text_submitted.connect(func(t): _save_name(t))
	name_edit.focus_exited.connect(func(): _save_name(name_edit.text))
	info.add_child(name_edit)

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
	info.add_child(chips)
	for gk in ["SS", "S", "A", "B"]:
		chips.add_child(_rank_chip(gk, int(counts[gk])))

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 26)
	info.add_child(stat_row)
	_head_stat(stat_row, str(ScoreStore.total_plays()), "Plays", UiTheme.TEXT)
	_head_stat(stat_row, ("%.2f%%" % (acc_sum / acc_n * 100.0)) if acc_n > 0 else "—",
			"Accuracy", UiTheme.TEXT)
	_head_stat(stat_row, _fmt_playtime(), "Spielzeit", UiTheme.TEXT)

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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	_section(list, "TOP PLAYS")
	var best := ScoreStore.best_plays(8)
	if best.is_empty():
		_empty_hint(list)
	for e in best:
		list.add_child(_play_row(e, "best"))

	_section(list, "LETZTE PLAYS")
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
	_file_dialog.title = "Profilbild auswaehlen"
	_file_dialog.filters = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Bilder"]
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
	chip.add_child(hb)
	var lg := Label.new()
	lg.text = g
	lg.add_theme_font_override("font", UiTheme.heading_font(1))
	lg.add_theme_font_size_override("font_size", 15)
	lg.add_theme_color_override("font_color", col if n > 0 else COL_DIM)
	hb.add_child(lg)
	var ln := Label.new()
	ln.text = str(n)
	ln.add_theme_font_size_override("font_size", 15)
	ln.add_theme_color_override("font_color", UiTheme.TEXT if n > 0 else COL_DIM)
	hb.add_child(ln)
	return chip


## Tausendertrenner mit Punkt: 1234 -> "1.234".
func _fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return ("-" + out) if v < 0 else out


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


func _head_stat(row: HBoxContainer, value: String, caption: String, col: Color) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	row.add_child(box)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", UiTheme.heading_font(1))
	v.add_theme_font_size_override("font_size", 22)
	v.add_theme_color_override("font_color", col)
	box.add_child(v)
	var c := Label.new()
	c.text = caption
	c.add_theme_font_size_override("font_size", 11)
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
	empty.text = "Noch keine Plays — leg los!"
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
		sub_parts.append("[%s]" % str(e.get("version", "")))
	if mode == "most":
		sub_parts.append("%d× gespielt" % int(e.get("count", 0)))
	var date := _fmt_date(str(e.get("date", "")))
	if date != "":
		sub_parts.append(date)
	if float(e.get("accuracy", 0.0)) > 0.0:
		sub_parts.append("%.2f%%" % (float(e.get("accuracy", 0.0)) * 100.0))
	if int(e.get("max_combo", 0)) > 0:
		sub_parts.append("%dx" % int(e.get("max_combo", 0)))
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
	pp_label.text = ("%.0fpp" % ppv) if ppv >= 0.0 else "—"
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
	UiTheme.style_button(play, playable)
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


## "2026-07-19T11:33:20" -> "19.07.2026"
func _fmt_date(iso: String) -> String:
	if iso == "":
		return ""
	var d := iso.split("T")[0].split("-")
	if d.size() != 3:
		return iso
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
	GameSession.mods = {"NF": false}
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
		var circle := ColorRect.new()
		circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		circle.color = Color(0.16, 0.30, 0.42)
		var m2 := ShaderMaterial.new()
		m2.shader = load("res://shaders/avatar_circle.gdshader")
		circle.material = m2
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_slot.add_child(circle)
		var initial := Label.new()
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.text = Settings.profile_name.substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 44)
		initial.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_slot.add_child(initial)


func _pick_avatar() -> void:
	_file_dialog.popup_centered()


func _save_name(t: String) -> void:
	Settings.profile_name = t.strip_edges() if t.strip_edges() != "" else "Player"
	Settings.save()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_closing = true
	if _thumb_thread != null and _thumb_thread.is_started():
		_thumb_thread.wait_to_finish()


func _close() -> void:
	Settings.save()
	closed.emit()
	queue_free()
