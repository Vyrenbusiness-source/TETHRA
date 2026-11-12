class_name ChatOverlay
extends Control

## Chat-Overlay (Taste F): Unterhaltungen, Verlauf, Nutzersuche, Antworten,
## Map- und Score-Karten. Liegt als Kind einer eigenen CanvasLayer im
## Autoload GameSession, damit es in allen Menues gleich ist.

signal state_changed

const PANEL_W := 430.0
const OPEN_KEY := KEY_F

var api: ChatApi
var preview_set := -1
## Hinweise je Score-Karte ("Replay nicht verfuegbar" ...).
var card_notes: Dictionary = {}

var _panel: PanelContainer
var _body: VBoxContainer
var _badge: Button
var _view := "list"            # list | thread | search
var _thread_user := ""          # Empfaenger ohne bestehende Unterhaltung
var _thread_name := ""
var _reply: Dictionary = {}
var _pending_text := ""
var _edit: LineEdit
var _scroll: ScrollContainer
var _msgs: VBoxContainer
var _search_results: VBoxContainer
var _search_edit: LineEdit
var _search_seq := 0
var _owned_cache: Dictionary = {}
var _owned_at := -100000
var _downloading: Dictionary = {}
var _preview_req: HTTPRequest
var _player: AudioStreamPlayer
var _score_cache: Dictionary = {}
## Karten-Info-Schluessel -> lokales MapSet (oder null); _lib = einmal gescannte Bibliothek.
var _local_cache: Dictionary = {}
var _local_at := -100000
var _lib: MapLibrary = null
## Map-Link -> lokaler Bildpfad. Die Chat-API kennt nur Text: Bilder gehen nicht
## ueber den Server. Der Empfaenger sieht die Map-Karte mit Hinweis "Trace picture",
## der Sender zusaetzlich die lokale Vorschau.
var _picture_cache: Dictionary = {}
const PICTURE_HINT := "Trace picture"
var _status_line: Label
var _stick_bottom := true
var _hint := ""


func _ready() -> void:
	name = "ChatOverlay"
	# Unter einer CanvasLayer greifen Anker nicht: Groesse selbst an den Viewport binden.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	var online := _gs()
	api = ChatApi.new()
	api.name = "ChatApi"
	api.online = online.online if online != null and "online" in online else null
	add_child(api)
	api.unread_changed.connect(func(_n): _update_badge())
	api.conversations_changed.connect(_on_data)
	api.messages_changed.connect(func(_c): _on_data())
	_build_shell()
	_panel.visible = false
	var m := _mirror()
	if m != null:
		m.download_done.connect(_on_download_done)
		m.download_failed.connect(_on_download_failed)
		m.download_progress.connect(func(_s, _r): state_changed.emit())
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(stop_preview)
	if api.online != null:
		api.online.state_changed.connect(_on_auth_changed)
		if api.active():
			api.refresh_unread.call_deferred()
	set_process(true)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-chat="):
			_run_shot.call_deferred(a.trim_prefix("--shot-chat="))


## Autoload ueber den Pfad (kein Klassenbezug: GameSession erzeugt dieses Overlay).
func _gs() -> Node:
	return get_node_or_null("/root/GameSession")


## true = Szenenpfad gehoert zum Gameplay (Spiel laeuft).
static func _gameplay_scene(scene_path: String) -> bool:
	return scene_path.ends_with("orbit.tscn") or scene_path.ends_with("mania_3d.tscn") 		or scene_path.ends_with("gameplay_3d.tscn")


func _mirror() -> BeatmapMirror:
	return get_node_or_null("/root/Mirror") as BeatmapMirror


# --- Taste F / Esc -------------------------------------------------------------

## Reine Entscheidung fuer Tests: darf F den Chat jetzt oeffnen/schliessen?
static func key_allowed(scene_path: String, focus: Control) -> bool:
	if _gameplay_scene(scene_path):
		return false
	if scene_path.ends_with("tutorial.tscn"):
		return false
	if focus is LineEdit or focus is TextEdit or focus is CodeEdit:
		return false
	return true


func _in_gameplay() -> bool:
	var sc := get_tree().current_scene
	return sc != null and _gameplay_scene(sc.scene_file_path)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()
		return
	if k.keycode != OPEN_KEY or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	var sc := get_tree().current_scene
	var path: String = sc.scene_file_path if sc != null else ""
	if not key_allowed(path, get_viewport().gui_get_focus_owner()):
		return
	toggle()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if _in_gameplay():
		return
	_panel.visible = true
	api.set_overlay_open(true)
	_view = "list" if api.open_id == "" and _thread_user == "" else "thread"
	_render()
	_update_badge()


func close() -> void:
	_panel.visible = false
	api.set_overlay_open(false)
	_thread_user = ""
	_reply = {}
	stop_preview()
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
	_update_badge()


## Chat mit vorbereiteter Map-Nachricht oeffnen; Empfaenger waehlen.
## meta: {md5, set_id, beatmap_id, title, artist?, version?, stars?}
func share_map(meta: Dictionary) -> void:
	_share(ChatApi.map_link(meta))


## Wie share_map fuer einen Score. summary: Text vor dem Link (optional).
func share_score(score_id: Variant, summary: String = "") -> void:
	var t := ChatApi.score_link(score_id)
	_share((summary.strip_edges() + " " + t).strip_edges())


## Trace-Bild teilen: Map-Link mit Hinweis "Trace picture"; die Vorschau bleibt lokal.
## meta wie share_map; summary = kurzer Text (z.B. Spieler und Acc).
func share_picture(image_path: String, meta: Dictionary, summary: String = "") -> void:
	var link := ChatApi.map_link(meta)
	_picture_cache[link] = image_path
	var head := PICTURE_HINT if summary.strip_edges() == "" else "%s · %s" % [PICTURE_HINT, summary.strip_edges()]
	_share(head + " " + link)


## Grosse Ansicht eines lokalen Bildes; Klick oder Esc schliesst.
func show_picture(image_path: String) -> void:
	var img := Image.load_from_file(image_path)
	if img == null or img.is_empty():
		return
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.04, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(img)
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 40
	tex.offset_right = -40
	tex.offset_top = 40
	tex.offset_bottom = -40
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(tex)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			shade.queue_free())
	shade.name = "PictureView"
	add_child(shade)


func _share(text: String) -> void:
	_pending_text = text
	_panel.visible = true
	api.set_overlay_open(true)
	api.open_id = ""
	_thread_user = ""
	_view = "list"
	_render()
	_update_badge()


# --- Aufbau ---------------------------------------------------------------------

func _build_shell() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.anchor_left = 1.0
	_panel.offset_left = -PANEL_W
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UiTheme.solid_box(UiTheme.SURFACE, 0)
	sb.border_color = UiTheme.LINE
	sb.border_width_left = 1
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_panel.add_child(_body)

	_badge = Button.new()
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -108
	_badge.offset_right = -14
	_badge.offset_top = 10
	_badge.offset_bottom = 34
	UiTheme.style_ghost_button(_badge, 6)
	_badge.pressed.connect(open)
	_badge.visible = false
	add_child(_badge)


func _update_badge() -> void:
	if _badge == null:
		return
	var n := ChatApi.unread_text(api.unread)
	_badge.visible = n != "" and not is_open() and not _in_gameplay()
	_badge.text = tr("Chat  ·  %s") % n


func _process(_dt: float) -> void:
	if not is_open() and _badge != null:
		var want := api.unread > 0 and not _in_gameplay()
		if _badge.visible != want:
			_update_badge()


func _on_auth_changed() -> void:
	if api.active():
		api.refresh_unread()
	else:
		api.set_unread(0)
		api.conversations = []
		api.messages = {}
	if is_open():
		_render()


func _on_data() -> void:
	_update_badge()
	if not is_open():
		return
	if _view == "thread":
		_render_messages()
	elif _view == "list":
		_render()


func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_edit = null
	_scroll = null
	_msgs = null
	_search_results = null
	_search_edit = null
	_status_line = null


func _render() -> void:
	_clear_body()
	_body.add_child(_header())
	if not api.active():
		_render_login()
		return
	match _view:
		"thread": _render_thread()
		"search": _render_search()
		_: _render_list()


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if _view != "list" and api.active():
		var back := _small_button("‹")
		back.custom_minimum_size = Vector2(32, 32)
		back.pressed.connect(func():
			api.open_id = ""
			_thread_user = ""
			_reply = {}
			_view = "list"
			_render())
		row.add_child(back)
	var t := Label.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("font", UiTheme.heading_font(0))
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", UiTheme.TEXT)
	t.text = tr("Chat")
	if _view == "thread" and api.active():
		t.text = _thread_title()
	elif _view == "search":
		t.text = tr("Neue Unterhaltung")
	t.clip_text = true
	row.add_child(t)
	var x := _small_button("✕")
	x.custom_minimum_size = Vector2(32, 32)
	x.pressed.connect(close)
	row.add_child(x)
	return row


func _small_button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	if primary:
		UiTheme.style_button(b, true, 6)
	else:
		UiTheme.style_ghost_button(b, 6)
	return b


## Winziger Textknopf ohne Rahmen (Antworten/Loeschen am Nachrichtenfuss).
func _tiny_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(22, 18)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiTheme.DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return b


func _dim_label(text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	return l


func _render_login() -> void:
	var l := _dim_label(tr("Zum Chatten anmelden"), 15)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_body.add_child(l)
	var login_cls := _login_class()
	if login_cls != null:
		var b := _small_button(tr("Anmelden"), true)
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(_open_login.bind(login_cls))
		_body.add_child(b)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(sp)


## LoginDialog nur nutzen, falls die Klasse existiert.
func _login_class() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "LoginDialog":
			return load(str(c.path)) as Script
	return null


func _open_login(cls: Script) -> void:
	var d: Node = cls.new()
	add_child(d)
	if d.has_method("popup_centered"):
		d.popup_centered()
	elif d.has_method("open"):
		d.open()
	if d.has_signal("closed"):
		d.closed.connect(func(): d.queue_free())


func _pending_banner() -> Control:
	if _pending_text == "":
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var l := _dim_label(tr("Nachricht bereit – wähle einen Empfänger."), 12)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(l)
	var card := _content_widget(_pending_text, true)
	if card != null:
		box.add_child(card)
	return box


func _render_list() -> void:
	var banner := _pending_banner()
	if banner != null:
		_body.add_child(banner)
	var new_btn := _small_button(tr("Neue Unterhaltung"), true)
	new_btn.custom_minimum_size = Vector2(0, 34)
	new_btn.pressed.connect(func():
		_view = "search"
		_render())
	_body.add_child(new_btn)
	_body.add_child(UiTheme.hairline())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	if api.conversations.is_empty():
		list.add_child(_dim_label(tr("Noch keine Unterhaltungen.")))
	for c in api.conversations:
		list.add_child(_conversation_row(c))


func _conversation_row(c: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	b.flat = true
	b.add_theme_stylebox_override("normal", UiTheme.solid_box(Color(0, 0, 0, 0), 6))
	b.add_theme_stylebox_override("hover", UiTheme.solid_box(UiTheme.RAISED, 6))
	b.add_theme_stylebox_override("pressed", UiTheme.solid_box(UiTheme.RAISED, 6))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(_dot(bool(c.online)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var n := Label.new()
	n.text = str(c.name)
	n.add_theme_font_size_override("font_size", 15)
	n.add_theme_color_override("font_color", UiTheme.TEXT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(n)
	var last := Label.new()
	last.text = _preview_text(str(c.last_message))
	last.clip_text = true
	last.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	last.add_theme_font_size_override("font_size", 12)
	last.add_theme_color_override("font_color", UiTheme.DIM)
	last.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(last)
	if int(c.unread) > 0:
		row.add_child(_unread_pill(int(c.unread)))
	b.pressed.connect(func(): _open_thread(c))
	return b


func _preview_text(t: String) -> String:
	if not ChatApi.parse_map_link(t).is_empty():
		var m := ChatApi.parse_map_link(t)
		return "♪ " + (str(m.title) if str(m.title) != "" else tr("Map"))
	if not ChatApi.parse_score_link(t).is_empty():
		return "★ " + tr("Score")
	return t.replace("\n", " ")


func _dot(online: bool) -> Control:
	var d := ColorRect.new()
	d.color = UiTheme.GOOD if online else Color(UiTheme.DIM, 0.35)
	d.custom_minimum_size = Vector2(8, 8)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _unread_pill(n: int) -> Control:
	var p := PanelContainer.new()
	var psb := UiTheme.solid_box(UiTheme.ACCENT, 8)
	psb.content_margin_left = 7
	psb.content_margin_right = 7
	psb.content_margin_top = 1
	psb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", psb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = ChatApi.unread_text(n)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UiTheme.ON_ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _open_thread(c: Dictionary) -> void:
	_thread_user = ""
	_thread_name = str(c.name)
	_view = "thread"
	_stick_bottom = true
	api.open_conversation(str(c.id))
	_render()


func _thread_title() -> String:
	if _thread_user != "":
		return _thread_user
	for c in api.conversations:
		if c.id == api.open_id:
			return str(c.name)
	return _thread_name if _thread_name != "" else tr("Chat")


# --- Suche ----------------------------------------------------------------------

func _render_search() -> void:
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = tr("Spielername suchen")
	_search_edit.custom_minimum_size = Vector2(0, 34)
	_search_edit.text_changed.connect(_on_search_text)
	_search_edit.text_submitted.connect(func(t: String):
		if t.strip_edges() != "":
			_start_with_user(t.strip_edges()))
	_body.add_child(_search_edit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_search_results = VBoxContainer.new()
	_search_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_search_results)
	_search_edit.call_deferred("grab_focus")


func _on_search_text(t: String) -> void:
	_search_seq += 1
	var seq := _search_seq
	if t.strip_edges().length() < 2:
		_fill_results([])
		return
	api.search_users(t.strip_edges(), func(users: Array):
		if seq == _search_seq:
			_fill_results(users))


func _fill_results(users: Array) -> void:
	if _search_results == null:
		return
	for c in _search_results.get_children():
		c.queue_free()
	for u in users:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = ("●  " if bool(u.online) else "○  ") + str(u.name)
		b.custom_minimum_size = Vector2(0, 38)
		UiTheme.style_ghost_button(b, 6)
		var nm: String = u.name
		b.pressed.connect(func(): _start_with_user(nm))
		_search_results.add_child(b)


func _start_with_user(username: String) -> void:
	for c in api.conversations:
		if str(c.name).to_lower() == username.to_lower():
			_open_thread(c)
			_prefill()
			return
	_thread_user = username
	_thread_name = username
	api.open_id = ""
	_view = "thread"
	_render()
	_prefill()


func _prefill() -> void:
	if _pending_text != "" and _edit != null:
		_edit.text = _pending_text
		_edit.caret_column = _edit.text.length()
		_pending_text = ""


# --- Verlauf --------------------------------------------------------------------

func _render_thread() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_msgs = VBoxContainer.new()
	_msgs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msgs.add_theme_constant_override("separation", 8)
	_scroll.add_child(_msgs)
	_render_messages()
	if not _reply.is_empty():
		_body.add_child(_reply_bar())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 36)
	_edit.max_length = ChatApi.MAX_LEN
	_edit.placeholder_text = tr("Nachricht schreiben")
	_edit.text_submitted.connect(func(_t): _send())
	row.add_child(_edit)
	var send := _small_button(tr("Senden"), true)
	send.custom_minimum_size = Vector2(0, 36)
	send.pressed.connect(_send)
	row.add_child(send)
	_body.add_child(row)
	_status_line = _dim_label(_hint, 11)
	_body.add_child(_status_line)
	if _pending_text != "":
		_prefill()
	_edit.call_deferred("grab_focus")


func _reply_bar() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.solid_box(UiTheme.RAISED, 6))
	var row := HBoxContainer.new()
	p.add_child(row)
	var l := _dim_label("↩ %s: %s" % [_reply.get("name", ""), _preview_text(str(_reply.get("content", "")))], 12)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var x := _small_button("✕")
	x.pressed.connect(func():
		_reply = {}
		_render())
	row.add_child(x)
	return p


func _current_messages() -> Array:
	return api.messages.get(api.open_id, []) if api.open_id != "" else []


func _render_messages() -> void:
	if _msgs == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_stick_bottom = bar.value >= bar.max_value - bar.page - 8.0 or _msgs.get_child_count() == 0
	for c in _msgs.get_children():
		_msgs.remove_child(c)
		c.queue_free()
	var msgs := _current_messages()
	if msgs.is_empty():
		_msgs.add_child(_dim_label(tr("Noch keine Nachrichten.")))
	var my_id: String = api.online.user_id if api.online != null else ""
	for m in msgs:
		_msgs.add_child(_bubble(m, ChatApi.is_mine(m, my_id)))
	if _stick_bottom:
		_scroll_down.call_deferred()


func _scroll_down() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _bubble(m: Dictionary, mine: bool) -> Control:
	var outer := HBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
	p.custom_minimum_size = Vector2(0, 0)
	var sb := UiTheme.solid_box(Color(UiTheme.ACCENT, 0.16) if mine else UiTheme.RAISED, 8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(0, 0)
	p.add_child(col)
	var rt: Variant = m.get("reply_to", {})
	if rt is Dictionary and not rt.is_empty():
		var q := _dim_label("%s: %s" % [rt.sender_name, _preview_text(str(rt.content))], 11)
		q.autowrap_mode = TextServer.AUTOWRAP_OFF
		q.clip_text = true
		q.custom_minimum_size = Vector2(120, 0)
		col.add_child(q)
	var w := _content_widget(str(m.content), false)
	col.add_child(w)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	var tm := _dim_label(_time_text(str(m.created_at)), 10)
	tm.autowrap_mode = TextServer.AUTOWRAP_OFF
	foot.add_child(tm)
	var rb := _tiny_button("↩", tr("Antworten"))
	var who := _thread_title() if not mine else tr("Du")
	rb.pressed.connect(func():
		_reply = {"id": m.id, "name": who, "content": m.content}
		var keep := _edit.text if _edit != null else ""
		_render()
		if _edit != null:
			_edit.text = keep)
	foot.add_child(rb)
	if mine:
		var db := _tiny_button("✕", tr("Löschen"))
		db.pressed.connect(func(): api.delete_message(api.open_id, str(m.id)))
		foot.add_child(db)
	col.add_child(foot)
	outer.add_child(p)
	return outer


## Nachrichteninhalt: Text und/oder Map-/Score-Karte.
func _content_widget(content: String, compact: bool) -> Control:
	var maplink := ChatApi.parse_map_link(content)
	var scorelink := ChatApi.parse_score_link(content) if maplink.is_empty() else {}
	var rest := content
	if not maplink.is_empty():
		rest = str(maplink.text)
	elif not scorelink.is_empty():
		rest = str(scorelink.text)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var card_w := PANEL_W - 90.0 if not (maplink.is_empty() and scorelink.is_empty()) else PANEL_W - 150.0
	box.custom_minimum_size = Vector2(card_w if not compact else PANEL_W - 40.0, 0)
	if rest != "":
		var l := Label.new()
		l.text = rest
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(60, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UiTheme.TEXT)
		box.add_child(l)
	if not maplink.is_empty():
		var card := ChatMapCard.new()
		box.add_child(card)
		var pic := str(_picture_cache.get(str(maplink.get("link", "")), ""))
		if pic != "" and FileAccess.file_exists(pic):
			card.setup("picture", maplink, self, pic)
		else:
			card.setup("map", maplink, self)
	elif not scorelink.is_empty():
		var sid := str(scorelink.score_id)
		var card2 := ChatMapCard.new()
		box.add_child(card2)
		card2.setup("score", _score_cache.get(sid, {}), self, sid)
		if not _score_cache.has(sid):
			api.fetch_score(sid, func(info: Dictionary):
				if info.is_empty():
					card_notes[sid] = tr("Score nicht verfügbar")
					return
				_score_cache[sid] = info
				if is_instance_valid(card2):
					card2.set_info(info))
	return box


static func local_time_offset_s() -> int:
	return int(Time.get_time_zone_from_system().bias) * 60


## "2026-11-08T14:03:00Z" -> "15:03" (lokale Zeit).
static func time_text(iso: String) -> String:
	if iso == "":
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso.replace("Z", "").substr(0, 19))
	if unix <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + local_time_offset_s())
	return "%02d:%02d" % [d.hour, d.minute]


func _time_text(iso: String) -> String:
	return time_text(iso)


# --- Senden ---------------------------------------------------------------------

func _send() -> void:
	if _edit == null:
		return
	var text := ChatApi.clean(_edit.text)
	if text == "":
		return
	var reply_id := str(_reply.get("id", ""))
	_hint = ""
	var done := func(ok: bool, _cid: String):
		if not ok:
			_hint = tr("Senden fehlgeschlagen.")
			if _status_line != null:
				_status_line.text = _hint
			return
		_hint = ""
		_reply = {}
		_thread_user = ""
		_stick_bottom = true
		if is_open() and _view == "thread":
			_render()
	_edit.text = ""
	if _thread_user != "":
		api.send_to_user(_thread_user, text, reply_id, done)
	elif api.open_id != "":
		api.send_to_conversation(api.open_id, text, reply_id, done)


# --- Karten-Aktionen --------------------------------------------------------------

static func find_local_osz(set_id: int) -> String:
	var dir_path := MapLibrary.default_maps_dir()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for fname in dir.get_files():
		if not fname.to_lower().ends_with(".osz"):
			continue
		var base := fname.get_basename()
		var id_str := base.substr(7) if base.begins_with("mirror_") else base.split(" ")[0]
		if id_str.is_valid_int() and int(id_str) == set_id:
			return dir_path.path_join(fname)
	return ""


func is_owned(set_id: int) -> bool:
	if set_id <= 0:
		return false
	var now := Time.get_ticks_msec()
	if now - _owned_at > 2000:
		_owned_cache.clear()
		_owned_at = now
	if not _owned_cache.has(set_id):
		_owned_cache[set_id] = find_local_osz(set_id) != ""
	return _owned_cache[set_id]


func download_ratio(set_id: int) -> float:
	var m := _mirror()
	if m == null or not m.is_downloading(set_id):
		return -1.0
	return m.active_ratio(set_id)


func download_set(set_id: int) -> void:
	var m := _mirror()
	if m != null and set_id > 0:
		m.download(set_id, MapLibrary.default_maps_dir())
		state_changed.emit()


func _on_download_done(_set_id: int, _path: String) -> void:
	_owned_at = -100000
	_forget_local()
	state_changed.emit()


func _on_download_failed(_set_id: int, _msg: String) -> void:
	_owned_at = -100000
	_forget_local()
	state_changed.emit()


func toggle_preview(set_id: int) -> void:
	if preview_set == set_id:
		stop_preview()
		return
	stop_preview()
	preview_set = set_id
	if _preview_req == null:
		_preview_req = HTTPRequest.new()
		_preview_req.timeout = 12.0
		add_child(_preview_req)
		_preview_req.request_completed.connect(_on_preview_bytes)
	if _preview_req.request(ChatApi.PREVIEW_URL % set_id, BeatmapMirror.headers()) != OK:
		preview_set = -1
	state_changed.emit()


func stop_preview() -> void:
	if _preview_req != null:
		_preview_req.cancel_request()
	if _player != null:
		_player.stop()
	if preview_set != -1:
		preview_set = -1
		state_changed.emit()


func _on_preview_bytes(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if preview_set < 0:
		return
	var stream: AudioStream = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 4:
		# b.ppy.sh liefert trotz .mp3-Endung OGG Vorbis.
		if body[0] == 0x4F and body[1] == 0x67 and body[2] == 0x67 and body[3] == 0x53:
			stream = AudioStreamOggVorbis.load_from_buffer(body)
		else:
			var mp3 := AudioStreamMP3.new()
			mp3.data = body
			if mp3.get_length() > 0.0:
				stream = mp3
	if stream == null:
		preview_set = -1
		state_changed.emit()
		return
	_player.stream = stream
	_player.play()


func _forget_local() -> void:
	_local_cache.clear()
	_lib = null


## Lokales Mapset zu einer Karte: ueber die Set-ID (Dateiname), sonst ueber den md5 der
## .osu (nur Sets mit gleichem Titel werden gehasht). null = Map fehlt lokal.
## Treffer bleiben gemerkt, Fehlanzeigen 10 s (danach neu suchen).
func local_set(info: Dictionary) -> MapSet:
	var key := "%d|%s|%s" % [int(info.get("set_id", 0)), str(info.get("md5", "")), str(info.get("title", ""))]
	var now := Time.get_ticks_msec()
	if now - _local_at > 10000:
		for k in _local_cache.keys():
			if _local_cache[k] == null:
				_local_cache.erase(k)
		_local_at = now
	if not _local_cache.has(key):
		_local_cache[key] = _find_local_set(info)
	return _local_cache[key]


func _find_local_set(info: Dictionary) -> MapSet:
	var path := find_local_osz(int(info.get("set_id", 0)))
	var md5 := str(info.get("md5", ""))
	var title := str(info.get("title", "")).strip_edges().to_lower()
	if path == "" and (md5 == "" or title == ""):
		return null
	if _lib == null:
		_lib = MapLibrary.new()
		_lib.scan()
	for ms: MapSet in _lib.mapsets:
		if path != "":
			if ms.osz_path == path:
				return ms
			continue
		if ms.title.strip_edges().to_lower() != title:
			continue
		for d in ms.difficulty_count():
			var bytes := OszImporter.read_file_bytes(ms.osz_path, ms.osu_filename_at(d))
			if OnlineApi._md5_bytes(bytes) == md5:
				return ms
	return null


## Map lokal spielen, Diff nach Name, sonst erste. Score-Karten starten den Modus des Scores.
func play_map(info: Dictionary) -> void:
	var sel := _select_local(info)
	if sel.is_empty():
		return
	var gs := _gs()
	gs.mods = {}
	gs.is_replay = false
	gs.replay_events = []
	gs.replay_mode = "mania"
	stop_preview()
	close()
	var mode := int(sel.ms.meta_at(sel.diff).get("mode", 0))
	var play_mode := str(info.get("mode", ""))
	if play_mode != "" and play_mode != "mania" and ScoreStore.mode_ready(play_mode):
		get_tree().change_scene_to_file(ScoreStore.mode_scene(play_mode))
		return
	get_tree().change_scene_to_file("res://scenes/mania_3d.tscn" if mode == 3
		else "res://scenes/gameplay_3d.tscn")


## Lokales Set + Diff suchen und GameSession.set_selection setzen.
func _select_local(info: Dictionary) -> Dictionary:
	var local := local_set(info)
	var gs := _gs()
	if local == null or gs == null:
		return {}
	var diff := 0
	var want := str(info.get("version", info.get("difficulty", ""))).to_lower()
	for d in local.difficulty_count():
		if want != "" and local.version_name_at(d).to_lower() == want:
			diff = d
			break
	gs.set_selection(local.osz_path, diff, local.version_name_at(diff),
		local.osu_filename_at(diff), local.stars_at(diff))
	return {"ms": local, "diff": diff}


## Replay eines Chat-Scores laden und wie "Replay ansehen" im Song-Browser starten.
func watch_score_replay(score_id: String, info: Dictionary) -> void:
	card_notes[score_id] = tr("Replay wird geladen …")
	state_changed.emit()
	api.fetch_replay(score_id, func(res: Dictionary):
		match str(res.status):
			"missing":
				card_notes[score_id] = tr("Replay nicht verfügbar")
			"error":
				card_notes[score_id] = tr("Replay konnte nicht geladen werden")
			_:
				card_notes[score_id] = ""
				start_replay(info, res.data)
		state_changed.emit())


func start_replay(info: Dictionary, data: Dictionary) -> bool:
	var sel := _select_local(info)
	if sel.is_empty():
		return false
	var gs := _gs()
	var orbit := str(info.get("mode", "")).begins_with("orbit")
	var rmode := ReplayStore.MODE_ORBIT_BEST if orbit else "mania"
	gs.mods = OrbitCore.replay_mods(data) if orbit else gs.call("_replay_mods", data)
	gs.is_replay = true
	gs.replay_events = data.events
	gs.replay_mode = rmode
	gs.replay_end_ms = float(data.get("meta", {}).get("end_ms", -1.0))
	stop_preview()
	close()
	get_tree().change_scene_to_file("res://scenes/orbit.tscn" if orbit else "res://scenes/mania_3d.tscn")
	return true


# --- Screenshot (--shot-chat=<Ordner>) -----------------------------------------

func _run_shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.5).timeout
	api.transport = Callable()
	api.conversations = [
		{"id": "c1", "other_id": "2", "name": "Mira", "country": "DE", "online": true,
			"last_message": "https://butzebot.com/tethra/map/abc?set=1&b=1&t=x", "last_sender_id": "2",
			"unread": 2, "updated_at": ""},
		{"id": "c2", "other_id": "3", "name": "Jonas", "country": "DE", "online": false,
			"last_message": "bis später", "last_sender_id": "1", "unread": 0, "updated_at": ""},
	]
	var meta := {"md5": "0123456789abcdef0123456789abcdef", "set_id": 1060425, "beatmap_id": 2209148,
		"title": "Ending Theme", "artist": "Nanatsu no Taizai", "version": "4K Hard", "stars": 3.84}
	var sc := {"player": "Mira", "md5": "", "set_id": 1060425, "beatmap_id": 2209148,
		"title": "Ending Theme", "artist": "Nanatsu no Taizai", "difficulty": "4K Hard",
		"score": 1234567, "accuracy": 97.42, "grade": "S", "max_combo": 512, "pp": 188.4,
		"mods": ["NF"], "mode": "mania", "has_replay": true}
	_score_cache["77"] = sc
	# Server-Antworten wie GET /score/:id (flach, accuracy 0..1, pp null ausser Mania).
	_score_cache["78"] = ChatApi.parse_score(JSON.stringify({"score_id": 78, "mode": "trace",
		"beatmap_md5": "595c5fc1d6d431fd9977a70760062541", "beatmapset_id": 0, "player": "Gexanx",
		"artist": "d0tc0mmie", "title": "I Can't Wait feat. GUMI", "difficulty_name": "Beginner",
		"score": 582612, "accuracy": 0.8582, "grade": "B", "max_combo": 77, "pp": null,
		"points": 2.062, "has_replay": false}))
	_score_cache["79"] = ChatApi.parse_score(JSON.stringify({"score_id": 79, "mode": "mania",
		"beatmapset_id": 1060425, "player": "Gexanx", "artist": "Nanatsu no Taizai",
		"title": "Ending Theme (a very long title that has to end with an ellipsis)", "difficulty_name": "4K Insane",
		"score": 973268, "accuracy": 0.9912, "grade": "S", "max_combo": 420, "pp": 1234.6,
		"mods": ["HD", "NF"], "has_replay": true}))
	api.online.token = "shot"
	api.online.user_id = "1"
	api.messages["c1"] = [
		{"id": "m1", "sender_id": "2", "content": "Hast du die schon gespielt?", "created_at": "2026-11-08T14:03:00Z", "reply_to": {}},
		{"id": "m2", "sender_id": "2", "content": ChatApi.map_link(meta), "created_at": "2026-11-08T14:03:10Z", "reply_to": {}},
		{"id": "m3", "sender_id": "1", "content": "Nein, lade ich gleich.", "created_at": "2026-11-08T14:05:00Z",
			"reply_to": {"id": "m1", "sender_name": "Mira", "content": "Hast du die schon gespielt?"}},
		{"id": "m4", "sender_id": "2", "content": "Mein Lauf dazu: " + ChatApi.score_link("77"), "created_at": "2026-11-08T14:06:00Z", "reply_to": {}},
		{"id": "m5", "sender_id": "1", "content": ChatApi.score_link("78"), "created_at": "2026-11-08T14:07:00Z", "reply_to": {}},
		{"id": "m6", "sender_id": "2", "content": ChatApi.score_link("79"), "created_at": "2026-11-08T14:08:00Z", "reply_to": {}},
	]
	api.unread = 2
	_panel.visible = true
	api.overlay_open = false
	api.open_id = "c1"
	_view = "list"
	_render()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("chat_list.png"))
	_view = "thread"
	_render()
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("chat_thread.png"))
	print("SHOT-CHAT fertig ", _panel.get_global_rect(), " ", size, " vis=", _panel.visible, " api=", api.active())
	get_tree().quit()
