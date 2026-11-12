class_name ChatMapCard
extends PanelContainer

## Karte in einer Chat-Nachricht: Map ("map"), Score ("score") oder Trace-Bild ("picture":
## Map-Karte mit lokaler Bildvorschau, Klick = gross; score_id traegt den Bildpfad).
## Alle Aktionen laufen ueber das ChatOverlay (eine Vorschau gleichzeitig,
## ein Download-Weg); die Karte zeigt nur den Zustand und ruft zurueck.
##
## Aufbau Map/Score (gleich hoch): Cover links (lokal aus der Map, sonst ueber die
## Set-ID vom Mirror), Textspalte, bei Scores rechts Rang gross + Modus-Symbol.
## Nur Titelzeilen duerfen mit "…" gekuerzt werden; Werte stehen immer ganz da.

const COVER := 84.0
const CARD_H := 96.0

var kind := "map"
var info: Dictionary = {}
var overlay: Node
var score_id := ""

var _cover: TextureRect
var _cover_icon: TextureRect
var _title: Label
var _sub: Label
var _who: Label
var _extra: Label
var _grade: Label
var _side: VBoxContainer
var _badge_slot: HBoxContainer
var _badge_mode := "?"
var _btn_a: Button
var _btn_b: Button
var _status: Label
var _bar: ProgressBar
var _cover_key := ""


## kind "map": info = ChatApi.parse_map_link(). kind "score": info = ChatApi.parse_score(),
## p_score_id = Score-ID. Fehlt info bei "score" noch, zeigt die Karte "Laedt".
func setup(p_kind: String, p_info: Dictionary, p_overlay: Node, p_score_id: String = "") -> void:
	kind = p_kind
	info = p_info
	overlay = p_overlay
	score_id = p_score_id
	_build()
	if kind == "picture":
		var img := Image.load_from_file(score_id)
		if img != null and not img.is_empty():
			_cover.texture = ImageTexture.create_from_image(img)
	refresh()
	if overlay != null and overlay.has_signal("state_changed"):
		overlay.state_changed.connect(refresh)


func set_info(p_info: Dictionary) -> void:
	info = p_info
	refresh()


# --- Reine Textlogik (testbar) ---------------------------------------------------

## Texte der Score-Karte aus info (ChatApi.parse_score oder lokaler Score):
## {title, sub, who, stats, grade, mode}. accuracy darf 0..1 oder Prozent sein.
static func score_texts(p: Dictionary) -> Dictionary:
	var mode := ModeBadge.norm(str(p.get("mode", "")))
	var title := str(p.get("title", "")).strip_edges()
	var sub_bits: Array = []
	var artist := str(p.get("artist", "")).strip_edges()
	var diff := str(p.get("difficulty", p.get("version", ""))).strip_edges()
	if artist != "":
		sub_bits.append(artist)
	if diff != "":
		sub_bits.append(diff)
	var who: Array = []
	if str(p.get("player", "")) != "":
		who.append(str(p.player))
	who.append(UiTheme.fmt_score(int(p.get("score", 0))))
	var mods: Variant = p.get("mods", [])
	if mods is Array and not (mods as Array).is_empty():
		who.append("+" + "".join(mods))
	var stats: Array = [UiTheme.fmt_pct(ChatApi.acc_percent(float(p.get("accuracy", 0.0))))]
	if int(p.get("max_combo", 0)) > 0:
		stats.append("%dx" % int(p.max_combo))
	var rating := rating_text(p)
	if rating != "":
		stats.append(rating)
	var grade := str(p.get("grade", "")).strip_edges()
	return {
		"title": title if title != "" else TranslationServer.translate("Unbekannte Map"),
		"sub": "  ·  ".join(sub_bits),
		"who": "  ·  ".join(who),
		"stats": "  ·  ".join(stats),
		"grade": grade if grade != "" else "–",
		"mode": mode,
	}


## Wertung je Modus: Mania "123 pp", sonst Punkte ("2,1 Pkt." / "2.1 pts"); 0 = "".
static func rating_text(p: Dictionary) -> String:
	var mode := ModeBadge.norm(str(p.get("mode", "")))
	if ScoreStore.uses_points(mode):
		var pts := float(p.get("points", p.get("pp", 0.0)))
		if pts <= 0.0:
			return ""
		return "%s %s" % [UiTheme.fmt_num(pts, 1), TranslationServer.translate("Pkt.")]
	var pp := float(p.get("pp", 0.0))
	return UiTheme.fmt_pp(pp) if pp > 0.0 else ""


## Knoepfe der Score-Karte: replay (sichtbar), replay_enabled (Map da),
## action "play" / "download" / "loading" / "" (Map fehlt, keine Set-ID).
static func score_buttons(p: Dictionary, owned: bool, dl: float) -> Dictionary:
	var action := "play"
	if not owned:
		if dl >= 0.0:
			action = "loading"
		elif int(p.get("set_id", 0)) > 0:
			action = "download"
		else:
			action = ""
	return {"replay": bool(p.get("has_replay", false)), "replay_enabled": owned, "action": action}


## Uebersetzung mit englischem Ersatz, solange der Schluessel nicht in der CSV steht.
static func tr2(de: String, en: String) -> String:
	var t := TranslationServer.translate(de)
	return en if t == de and not UiTheme.is_german() else t


static func grade_color(g: String) -> Color:
	match g.to_upper():
		"X", "XH", "SS", "SSH", "S", "SH":
			return UiTheme.ACCENT
		"A":
			return UiTheme.GOOD
		"B":
			return UiTheme.ACCENT2
		"D", "F":
			return UiTheme.BAD
	return UiTheme.DIM


# --- Aufbau ---------------------------------------------------------------------

func _build() -> void:
	var sb := UiTheme.solid_box(UiTheme.RAISED, 8)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_right = 10
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(0, CARD_H)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.solid_box(UiTheme.SURFACE, 6))
	frame.custom_minimum_size = Vector2(COVER, COVER) if kind != "picture" else Vector2(156, 82)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	row.add_child(frame)
	_cover_icon = TextureRect.new()
	_cover_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover_icon.custom_minimum_size = Vector2(28, 28)
	_cover_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cover_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cover_icon.modulate = Color(UiTheme.DIM, 0.45)
	frame.add_child(_cover_icon)
	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.clip_contents = true
	frame.add_child(_cover)
	if kind == "picture":
		_cover.mouse_filter = Control.MOUSE_FILTER_STOP
		_cover.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_cover.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_on_a())
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	_title = _label(14, UiTheme.TEXT)
	_title.add_theme_font_override("font", UiTheme.heading_font(0))
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size = Vector2(40, 0)
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_title)
	_sub = _label(12, UiTheme.DIM)
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.custom_minimum_size = Vector2(40, 0)
	_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_sub)
	_who = _label(12, UiTheme.TEXT)
	_who.visible = kind == "score"
	col.add_child(_who)
	_extra = _label(12, UiTheme.ACCENT)
	col.add_child(_extra)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 3)
	col.add_child(gap)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	col.add_child(btns)
	_btn_a = _button()
	_btn_a.pressed.connect(_on_a)
	btns.add_child(_btn_a)
	_btn_b = _button()
	_btn_b.pressed.connect(_on_b)
	btns.add_child(_btn_b)
	_status = _label(11, UiTheme.DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(50, 0)
	btns.add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.max_value = 1.0
	_bar.visible = false
	col.add_child(_bar)
	# Score: Rang gross rechts, Modus-Symbol darunter.
	_side = VBoxContainer.new()
	_side.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_theme_constant_override("separation", 2)
	_side.custom_minimum_size = Vector2(38, 0)
	_side.visible = kind == "score"
	row.add_child(_side)
	_grade = _label(30, UiTheme.DIM)
	_grade.add_theme_font_override("font", UiTheme.heading_font(0))
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_side.add_child(_grade)
	_badge_slot = HBoxContainer.new()
	_badge_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_child(_badge_slot)


## Modus-Symbol der Score-Karte setzen.
func _set_badge(mode: String) -> void:
	if _badge_slot == null or (_badge_mode == mode and _badge_slot.get_child_count() > 0):
		return
	for c in _badge_slot.get_children():
		c.queue_free()
	_badge_mode = mode
	_badge_slot.add_child(ModeBadge.make(mode, 18, false))


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 12)
	UiTheme.style_ghost_button(b, 6)
	return b


# --- Zustand ---------------------------------------------------------------------

## Lokales Mapset der Karte (ueber das Overlay) oder null.
func _local() -> MapSet:
	if overlay == null or not overlay.has_method("local_set") or info.is_empty():
		return null
	return overlay.local_set(info)


func _owned(local: MapSet) -> bool:
	if local != null:
		return true
	return overlay != null and overlay.is_owned(int(info.get("set_id", 0)))


## Cover: lokal aus der Map, sonst ueber die Set-ID vom Mirror; ohne beides das Modus-Symbol.
func _apply_cover(local: MapSet) -> void:
	if kind == "picture":
		return
	_cover_icon.texture = ModeBadge.icon(str(info.get("mode", "")) if kind == "score" else "mania")
	var sid := int(info.get("set_id", 0))
	var key := "%s|%d" % [local.osz_path if local != null else "", sid]
	if key == _cover_key:
		return
	_cover_key = key
	if local != null:
		var tex := local.thumb_texture()
		if tex != null:
			_cover.texture = tex
			return
	if sid <= 0:
		return
	var m := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Mirror") as BeatmapMirror
	if m == null:
		return
	if not m.cover_ready.is_connected(_on_cover):
		m.cover_ready.connect(_on_cover)
	var cached := m.cached_cover(sid)
	if cached != null:
		_cover.texture = cached
	else:
		m.fetch_cover(sid, ChatApi.COVER_URL % sid)


func _on_cover(set_id: int, tex: Texture2D) -> void:
	if set_id == int(info.get("set_id", -1)) and is_instance_valid(_cover) and _cover.texture == null:
		_cover.texture = tex


## Anzeige nach Zustand (lokal vorhanden, Download, Vorschau) neu setzen.
func refresh() -> void:
	if not is_instance_valid(_title):
		return
	var sid := int(info.get("set_id", 0))
	var dl: float = overlay.download_ratio(sid) if overlay != null else -1.0
	if kind == "score" and info.is_empty():
		_title.text = tr("Score wird geladen …")
		for l in [_sub, _who, _extra, _grade]:
			l.text = ""
		_btn_a.visible = false
		_btn_b.visible = false
		_status.text = _note()
		_bar.visible = false
		return
	var local := _local()
	var owned := _owned(local)
	_apply_cover(local)
	if kind == "score":
		_refresh_score(owned, dl)
	else:
		_refresh_map(owned, dl, sid)
	_bar.visible = dl >= 0.0
	_bar.value = maxf(dl, 0.0)


func _refresh_score(owned: bool, dl: float) -> void:
	var t := score_texts(info)
	_title.text = t.title
	_title.tooltip_text = t.title
	_sub.text = t.sub
	_sub.tooltip_text = t.sub
	_who.text = t.who
	_extra.text = t.stats
	_grade.text = t.grade
	_grade.add_theme_color_override("font_color", grade_color(t.grade))
	_set_badge(t.mode)
	var b := score_buttons(info, owned, dl)
	_btn_a.visible = b.replay
	_btn_a.text = tr("Replay ansehen")
	_btn_a.disabled = not b.replay_enabled
	_btn_a.tooltip_text = "" if b.replay_enabled else tr2("Map zuerst herunterladen", "Download the map first")
	_btn_b.visible = b.action != ""
	_btn_b.disabled = b.action == "loading"
	match str(b.action):
		"play":
			_btn_b.text = tr("Spielen")
		"download":
			_btn_b.text = tr2("Map herunterladen", "Download map")
		"loading":
			_btn_b.text = tr("Lädt …")
	var st := _note()
	if st == "" and b.action == "":
		st = tr("Map fehlt")
	_status.text = st


func _refresh_map(owned: bool, dl: float, sid: int) -> void:
	var title := str(info.get("title", ""))
	_title.text = title if title != "" else tr("Unbekannte Map")
	_title.tooltip_text = _title.text
	_sub.text = str(info.get("artist", ""))
	var bits: Array = []
	if str(info.get("version", "")) != "":
		bits.append(str(info.version))
	if float(info.get("stars", 0.0)) > 0.0:
		bits.append("%s ★" % UiTheme.fmt_num(float(info.stars), 2))
	_extra.text = "  ·  ".join(bits)
	_btn_a.visible = true
	if kind == "picture":
		_btn_a.text = tr("Vergrößern")
	else:
		_btn_a.text = tr("Vorhören") if overlay == null or overlay.preview_set != sid else tr("Stopp")
	_btn_b.visible = true
	if owned:
		_btn_b.text = tr("Spielen")
		_btn_b.disabled = false
	else:
		_btn_b.text = tr("Herunterladen") if dl < 0.0 else tr("Lädt …")
		_btn_b.disabled = dl >= 0.0
	var st := ""
	if owned and kind == "map":
		st = tr("Schon vorhanden")
	elif kind == "picture":
		st = tr("Trace picture")
	_status.text = st


func _note() -> String:
	if overlay != null and kind == "score":
		return str(overlay.card_notes.get(score_id, ""))
	return ""


func _on_a() -> void:
	if overlay == null:
		return
	if kind == "map":
		overlay.toggle_preview(int(info.get("set_id", 0)))
	elif kind == "picture":
		overlay.show_picture(score_id)
	else:
		overlay.watch_score_replay(score_id, info)


func _on_b() -> void:
	if overlay == null:
		return
	if _owned(_local()):
		overlay.play_map(info)
	else:
		overlay.download_set(int(info.get("set_id", 0)))
