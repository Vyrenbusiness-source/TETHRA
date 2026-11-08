class_name ChatMapCard
extends PanelContainer

## Karte in einer Chat-Nachricht: Map ("map") oder Score ("score").
## Alle Aktionen laufen ueber das ChatOverlay (eine Vorschau gleichzeitig,
## ein Download-Weg); die Karte zeigt nur den Zustand und ruft zurueck.

var kind := "map"
var info: Dictionary = {}
var overlay: Node
var score_id := ""

var _cover: TextureRect
var _title: Label
var _sub: Label
var _extra: Label
var _btn_a: Button
var _btn_b: Button
var _status: Label
var _bar: ProgressBar


## kind "map": info = ChatApi.parse_map_link(). kind "score": info = ChatApi.parse_score(),
## p_score_id = Score-ID. Fehlt info bei "score" noch, zeigt die Karte "Laedt".
func setup(p_kind: String, p_info: Dictionary, p_overlay: Node, p_score_id: String = "") -> void:
	kind = p_kind
	info = p_info
	overlay = p_overlay
	score_id = p_score_id
	_build()
	refresh()
	if overlay != null and overlay.has_signal("state_changed"):
		overlay.state_changed.connect(refresh)
	var m := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Mirror") as BeatmapMirror
	if m != null and int(info.get("set_id", 0)) > 0:
		m.cover_ready.connect(_on_cover)
		var sid := int(info.set_id)
		var cached := m.cached_cover(sid)
		if cached != null:
			_cover.texture = cached
		else:
			m.fetch_cover(sid, ChatApi.COVER_URL % sid)


func set_info(p_info: Dictionary) -> void:
	info = p_info
	var m := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Mirror") as BeatmapMirror
	if m != null and int(info.get("set_id", 0)) > 0:
		var sid := int(info.set_id)
		if not m.cover_ready.is_connected(_on_cover):
			m.cover_ready.connect(_on_cover)
		var cached := m.cached_cover(sid)
		if cached != null:
			_cover.texture = cached
		else:
			m.fetch_cover(sid, ChatApi.COVER_URL % sid)
	refresh()


func _on_cover(set_id: int, tex: Texture2D) -> void:
	if set_id == int(info.get("set_id", -1)) and is_instance_valid(_cover):
		_cover.texture = tex


func _build() -> void:
	add_theme_stylebox_override("panel", UiTheme.solid_box(UiTheme.RAISED, 8))
	custom_minimum_size = Vector2(0, 76)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_cover = TextureRect.new()
	_cover.custom_minimum_size = Vector2(88, 60)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.clip_contents = true
	_cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_cover)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_title = _label(14, UiTheme.TEXT)
	_title.add_theme_font_override("font", UiTheme.heading_font(0))
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_title)
	_sub = _label(12, UiTheme.DIM)
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_sub)
	_extra = _label(12, UiTheme.ACCENT)
	_extra.clip_text = true
	col.add_child(_extra)
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
	btns.add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.max_value = 1.0
	_bar.visible = false
	col.add_child(_bar)


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


## Anzeige nach Zustand (lokal vorhanden, Download, Vorschau) neu setzen.
func refresh() -> void:
	if not is_instance_valid(_title):
		return
	var sid := int(info.get("set_id", 0))
	var owned: bool = overlay != null and overlay.is_owned(sid)
	var dl: float = overlay.download_ratio(sid) if overlay != null else -1.0
	var title := str(info.get("title", ""))
	if kind == "score":
		if info.is_empty():
			_title.text = tr("Score wird geladen …")
			_sub.text = ""
			_extra.text = ""
			_btn_a.visible = false
			_btn_b.visible = false
			_status.text = ""
			return
		_title.text = "%s  ·  %s  ·  %s" % [info.player, info.grade, UiTheme.fmt_score(int(info.score))]
		_sub.text = "%s – %s [%s]" % [info.get("artist", ""), title, info.get("difficulty", "")]
		var parts: Array = [UiTheme.fmt_pct(float(info.accuracy)), "%dx" % int(info.max_combo)]
		if float(info.pp) > 0.0:
			parts.append(UiTheme.fmt_pp(float(info.pp)))
		if not (info.mods as Array).is_empty():
			parts.append("+" + "".join(info.mods))
		_extra.text = "  ·  ".join(parts)
		_btn_a.visible = bool(info.has_replay) and owned
		_btn_a.text = tr("Replay ansehen")
		_btn_b.visible = not owned
		_btn_b.text = tr("Herunterladen") if dl < 0.0 else tr("Lädt …")
		_btn_b.disabled = dl >= 0.0
	else:
		_title.text = title if title != "" else tr("Unbekannte Map")
		_sub.text = str(info.get("artist", ""))
		var bits: Array = []
		if str(info.get("version", "")) != "":
			bits.append(str(info.version))
		if float(info.get("stars", 0.0)) > 0.0:
			bits.append("%s ★" % UiTheme.fmt_num(float(info.stars), 2))
		_extra.text = "  ·  ".join(bits)
		_btn_a.visible = true
		_btn_a.text = tr("Vorhören") if overlay == null or overlay.preview_set != sid else tr("Stopp")
		if owned:
			_btn_b.visible = true
			_btn_b.text = tr("Spielen")
			_btn_b.disabled = false
		else:
			_btn_b.visible = true
			_btn_b.text = tr("Herunterladen") if dl < 0.0 else tr("Lädt …")
			_btn_b.disabled = dl >= 0.0
	_bar.visible = dl >= 0.0
	_bar.value = maxf(dl, 0.0)
	var st := ""
	if owned and kind == "map":
		st = tr("Schon vorhanden")
	if overlay != null and kind == "score" and str(overlay.card_notes.get(score_id, "")) != "":
		st = str(overlay.card_notes[score_id])
	_status.text = st


func _on_a() -> void:
	if overlay == null:
		return
	if kind == "map":
		overlay.toggle_preview(int(info.get("set_id", 0)))
	else:
		overlay.watch_score_replay(score_id, info)


func _on_b() -> void:
	if overlay == null:
		return
	if overlay.is_owned(int(info.get("set_id", 0))):
		overlay.play_map(info)
	else:
		overlay.download_set(int(info.get("set_id", 0)))
