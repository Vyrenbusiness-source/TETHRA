extends Control

## Multiplayer-Lobby: Raum erstellen (Port oeffnet sich automatisch per UPnP,
## Raum-Code zum Teilen), per Code beitreten, LAN-Raeume erscheinen von selbst.
## Im Raum: Spielerliste mit Krone (Host vergibt sie), Kronentraeger waehlt
## die Map, fehlende Maps laden automatisch vom Mirror, Host startet.

const COL_ACCENT := Color(0.20, 0.85, 1.0)
const COL_DIM := Color(0.62, 0.64, 0.72)
const COL_TEXT := Color(0.95, 0.96, 1.0)
const CROWN := "👑"

var _library: MapLibrary
var _mirror: BeatmapMirror
var _browser_box: VBoxContainer
var _room_box: VBoxContainer
var _rooms_list: VBoxContainer
var _code_edit: LineEdit
var _name_edit: LineEdit
var _pw_edit: LineEdit
var _join_pw_edit: LineEdit
var _fetch_timer: Timer
var _players_box: VBoxContainer
var _map_label: Label
var _map_meta: Label
var _map_cover: TextureRect
var _status_label: Label
var _start_btn: Button
var _pick_btn: Button
var _mod_btns: Dictionary = {}
var _code_label: Label
var _downloading := false
var _dl_set := 0
var _bg_rect: TextureRect
var _preview: AudioStreamPlayer
var _preview_fade: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new()
	_library.scan()
	_mirror = Mirror
	_preview = AudioStreamPlayer.new()
	_preview.bus = "Music"
	add_child(_preview)
	_mirror.download_progress.connect(_on_dl_progress)
	_mirror.download_done.connect(_on_dl_done)
	_mirror.download_failed.connect(_on_dl_failed)

	# Hintergrund: Neon-Shader als Fallback, darueber das geblurrte Cover —
	# beim Oeffnen das zuletzt gespielte Lied, im Raum immer die gewaehlte Map.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/menu_bg.gdshader")
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect.visible = false
	add_child(_bg_rect)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_update_bg()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.95)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(880, 560)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UiTheme.heading_font(3))
	title.add_theme_font_size_override("font_size", 26)
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(38, 38)
	UiTheme.style_button(close)
	close.pressed.connect(_back)
	head.add_child(close)
	var head_gap := Control.new()
	head_gap.custom_minimum_size = Vector2(0, 12)
	root.add_child(head_gap)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", COL_DIM)
	_status_label.text = " "
	root.add_child(_status_label)

	_browser_box = VBoxContainer.new()
	_browser_box.add_theme_constant_override("separation", 10)
	_browser_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_browser_box)
	_build_browser()

	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 10)
	_room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.visible = false
	root.add_child(_room_box)
	_build_room()

	Lobby.players_changed.connect(_refresh_room)
	Lobby.scores_changed.connect(_refresh_room)
	Lobby.map_changed.connect(_on_map_changed)
	Lobby.rooms_changed.connect(_refresh_rooms)
	Lobby.status.connect(func(m): _status_label.text = m)
	Lobby.left.connect(func(reason):
		_status_label.text = reason
		_show_browser())
	Lobby.round_done()
	if Lobby.active:
		_show_room()
		# Rueckkehr aus einer Runde: gewaehlte Map weiter vorhoeren.
		if not Lobby.sel_map.is_empty():
			_update_preview()
	else:
		Lobby.start_discovery()
		Lobby.fetch_online_rooms()
	# Oeffentliche Raumliste regelmaessig aktualisieren (nur im Browser).
	_fetch_timer = Timer.new()
	_fetch_timer.wait_time = 8.0
	_fetch_timer.autostart = true
	_fetch_timer.timeout.connect(func():
		if not Lobby.active:
			Lobby.fetch_online_rooms())
	add_child(_fetch_timer)
	_refresh_room()

	if OS.get_cmdline_args().has("--shot-mp"):
		_capture_shot()
	# Headless-Smoke: zwei Prozesse verbinden sich ueber localhost.
	if OS.get_cmdline_args().has("--mp-host-test"):
		Lobby.host_room()
		_mp_smoke(true)
	elif OS.get_cmdline_args().has("--mp-join-test"):
		Lobby.join_lan("127.0.0.1")
		_mp_smoke(false)
	elif OS.get_cmdline_args().has("--mp-auto-host"):
		if not Lobby.active:
			Lobby.host_room()
		_mp_auto(true)
	elif OS.get_cmdline_args().has("--mp-auto-client"):
		if not Lobby.active:
			Lobby.join_lan("127.0.0.1")
		_mp_auto(false)


func _mp_smoke(host: bool) -> void:
	var waited := 0.0
	while waited < 10.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		if Lobby.players.size() >= 2:
			var names := []
			for id in Lobby.players:
				names.append("%d:%s" % [id, Lobby.players[id].name])
			print("MP-SMOKE %s OK: %d Spieler [%s] crown=%d" % [
				"HOST" if host else "CLIENT", Lobby.players.size(),
				", ".join(names), Lobby.crown_id])
			await get_tree().create_timer(1.0).timeout
			get_tree().quit(0)
			return
	print("MP-SMOKE %s TIMEOUT" % ("HOST" if host else "CLIENT"))
	get_tree().quit(1)


## Zwei-Instanzen-Test (Host + Client auf 127.0.0.1), Ablauf siehe Log.
func _mp_auto(host: bool) -> void:
	var tag := "HOST" if host else "CLIENT"
	var out := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--mp-out="):
			out = a.substr(9)
	var step := func(msg: String): print("MPAUTO %s %s" % [tag, msg])
	var wait_for := func(cond: Callable, secs: float) -> bool:
		var w := 0.0
		while w < secs and not cond.call():
			await get_tree().create_timer(0.1).timeout
			w += 0.1
		return cond.call()
	var shot := func(name: String):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [out, tag.to_lower(), name])
	if not Lobby.played.is_empty():
		await get_tree().create_timer(1.5).timeout
		await shot.call("back")
		step.call("zurueck in Lobby, in_game=%s ready=%s" % [Lobby.in_game, str(Lobby.all_ready())])
		get_tree().quit(0)
		return
	Lobby.map_changed.connect(func():
		await get_tree().create_timer(0.4).timeout
		step.call("map_changed -> '%s' status='%s' all_ready=%s" % [
			str(Lobby.sel_map.get("title", "")), _status_label.text, Lobby.all_ready()]))
	if not await wait_for.call(func(): return Lobby.players.size() >= 2 and Lobby.players.has(multiplayer.get_unique_id()), 20.0):
		step.call("TIMEOUT players")
		get_tree().quit(1)
		return
	step.call("players synced: %d crown=%d" % [Lobby.players.size(), Lobby.crown_id])
	var sets := _library.mapsets
	if sets.size() < 2:
		step.call("zu wenig Maps")
		get_tree().quit(1)
		return
	if host:
		_pick(sets[0], 0)
		step.call("picked A: " + str(Lobby.sel_map.get("title", "")))
		await get_tree().create_timer(2.0).timeout
		step.call("ready after pick: all_ready=%s" % Lobby.all_ready())
		# Fehlende Map simulieren (nur Anzeige): Client meldet Status.
		Lobby.pick_map({ "set_id": 0, "file": "gibts_nicht.osz", "version": "X", "title": "Ghost", "artist": "Nobody", "stars": 1.0 })
		await get_tree().create_timer(1.5).timeout
		step.call("ghost map: all_ready=%s" % Lobby.all_ready())
		_pick(sets[0], 0)
		await get_tree().create_timer(1.0).timeout
		await shot.call("lobby")
		step.call("give crown to client")
		for id in Lobby.players:
			if id != 1:
				Lobby.give_crown(int(id))
		await get_tree().create_timer(1.0).timeout
		step.call("crown=%d pick by old host blocked: %s" % [Lobby.crown_id, str(not (Lobby.crown_id == 1))])
		var before := Lobby.sel_map.duplicate()
		_pick(sets[1], 0)
		step.call("old host pick ignored: %s" % str(Lobby.sel_map == before or Lobby.sel_map.get("title", "") != sets[1].title or Lobby.crown_id == 1))
		await get_tree().create_timer(0.5).timeout
		step.call("host start blocked: can_start=%s" % Lobby.can_start())
		if not await wait_for.call(func(): return Lobby.in_game, 40.0):
			step.call("TIMEOUT game start")
			get_tree().quit(1)
	else:
		await wait_for.call(func(): return Lobby.crown_id == multiplayer.get_unique_id(), 40.0)
		step.call("client got crown: %s" % str(Lobby.crown_id == multiplayer.get_unique_id()))
		await get_tree().create_timer(0.5).timeout
		_pick(sets[1], 0)
		await get_tree().create_timer(2.0).timeout
		step.call("client picked: %s all_ready=%s" % [str(Lobby.sel_map.get("title", "")), Lobby.all_ready()])
		await shot.call("lobby")
		Lobby.start_game()
		step.call("client start requested")


func _capture_shot() -> void:
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/mp_browser.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


func _exit_tree() -> void:
	Lobby.stop_discovery()


# ---------------------------------------------------------------------------
# Browser (Raum erstellen / Code / LAN-Liste)
# ---------------------------------------------------------------------------

func _build_browser() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_browser_box.add_child(cols)

	# ---------------- Links: offene Raeume (weltweit + LAN) -----------------
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	cols.add_child(left_col)

	var rooms_head := HBoxContainer.new()
	left_col.add_child(rooms_head)
	var lan_head := Label.new()
	lan_head.text = "OFFENE RÄUME"
	lan_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_head.add_theme_font_override("font", UiTheme.heading_font(2))
	lan_head.add_theme_font_size_override("font_size", 14)
	lan_head.add_theme_color_override("font_color", COL_ACCENT)
	rooms_head.add_child(lan_head)
	var refresh := Button.new()
	refresh.text = "⟳"
	refresh.add_theme_font_size_override("font_size", 20)
	refresh.tooltip_text = "Liste aktualisieren"
	refresh.custom_minimum_size = Vector2(38, 34)
	UiTheme.style_button(refresh)
	refresh.pressed.connect(func(): Lobby.fetch_online_rooms())
	rooms_head.add_child(refresh)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(scroll)
	_rooms_list = VBoxContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_rooms_list)
	_refresh_rooms()

	# ---------------- Rechts: Erstellen + Code-Beitritt ---------------------
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(316, 0)
	right_col.add_theme_constant_override("separation", 12)
	cols.add_child(right_col)

	var create_card := PanelContainer.new()
	var cb := UiTheme.glass_box(12, 0.5)
	cb.set_content_margin_all(14)
	create_card.add_theme_stylebox_override("panel", cb)
	right_col.add_child(create_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	create_card.add_child(cv)
	var ch := Label.new()
	ch.text = "RAUM ERSTELLEN"
	ch.add_theme_font_override("font", UiTheme.heading_font(2))
	ch.add_theme_font_size_override("font_size", 14)
	ch.add_theme_color_override("font_color", COL_ACCENT)
	cv.add_child(ch)
	_name_edit = LineEdit.new()
	_name_edit.text = _possessive_room(Settings.profile_name)
	_name_edit.max_length = 28
	_name_edit.custom_minimum_size = Vector2(0, 44)
	_name_edit.add_theme_stylebox_override("normal", _field_box())
	cv.add_child(_name_edit)
	_pw_edit = LineEdit.new()
	_pw_edit.placeholder_text = "Passwort (leer = öffentlich)"
	_pw_edit.custom_minimum_size = Vector2(0, 44)
	_pw_edit.add_theme_stylebox_override("normal", _field_box())
	cv.add_child(_pw_edit)
	var create := Button.new()
	create.text = "+ Raum erstellen"
	create.custom_minimum_size = Vector2(0, 46)
	create.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(create, true)
	create.pressed.connect(func():
		if Lobby.host_room(_name_edit.text, _pw_edit.text):
			_show_room())
	cv.add_child(create)
	var hint := Label.new()
	hint.text = "Ohne Passwort erscheint dein Raum automatisch\nbei allen Spielern in der Liste."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_DIM)
	cv.add_child(hint)

	var code_card := PanelContainer.new()
	var kb := UiTheme.glass_box(12, 0.5, 0.28)
	kb.set_content_margin_all(18)
	code_card.add_theme_stylebox_override("panel", kb)
	right_col.add_child(code_card)
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", 8)
	code_card.add_child(kv)
	var kh := Label.new()
	kh.text = "MIT CODE BEITRETEN"
	kh.add_theme_font_size_override("font_size", 16)
	kh.add_theme_font_override("font", UiTheme.heading_font(2))
	kh.add_theme_color_override("font_color", COL_ACCENT)
	kv.add_child(kh)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Code (z. B. 7K3F9-A2QXM)"
	_code_edit.custom_minimum_size = Vector2(0, 44)
	_code_edit.add_theme_stylebox_override("normal", _field_box())
	_code_edit.text_submitted.connect(func(_t): _join_by_code())
	kv.add_child(_code_edit)
	_join_pw_edit = LineEdit.new()
	_join_pw_edit.placeholder_text = "Passwort (falls gesetzt)"
	_join_pw_edit.custom_minimum_size = Vector2(0, 44)
	_join_pw_edit.add_theme_stylebox_override("normal", _field_box())
	_join_pw_edit.text_submitted.connect(func(_t): _join_by_code())
	kv.add_child(_join_pw_edit)
	var join := Button.new()
	join.text = "Beitreten"
	join.custom_minimum_size = Vector2(0, 46)
	join.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(join)
	join.pressed.connect(_join_by_code)
	kv.add_child(join)


## Genitiv: Namen auf s/x/z (auch ss) nur mit Apostroph, sonst "s".
static func _possessive_room(n: String) -> String:
	var t := n.strip_edges()
	if t.is_empty():
		return "Raum"
	var last := t.substr(t.length() - 1).to_lower()
	if last in ["s", "x", "z"]:
		return "%s' Raum" % t
	return "%s's Raum" % t


func _field_box() -> StyleBoxFlat:
	var fb := UiTheme.glass_box(10, 0.85)
	fb.content_margin_left = 14
	fb.content_margin_right = 14
	return fb


func _join_by_code() -> void:
	if Lobby.join_code(_code_edit.text, _join_pw_edit.text):
		_show_room()


## Fade+Slide-In fuer neu aufgebaute Karten (index staffelt leicht).
func _fade_in(c: Control, idx: int = 0) -> void:
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(minf(idx * 0.04, 0.3))
	tw.tween_property(c, "modulate:a", 1.0, 0.22)


## Runder Avatar mit Anfangsbuchstabe; Farbe aus dem Namen abgeleitet.
func _avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(pname.hash() % 360) / 360.0, 0.45, 0.62)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.08, 0.09, 0.14, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(sz * 0.5))
	l.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(l)
	return p


## Kleiner Status-Chip (Text auf getoenter Pille).
func _chip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.18)
	sb.border_color = Color(col.r, col.g, col.b, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	return p


## Eine Raum-Karte: Cover-Platzhalter, Name, Avatare, Status-Badge, JOIN.
func _room_card(badge: String, rname: String, players_n: int, sub: String,
		on_join: Callable, playing: bool = false) -> Control:
	var card := PanelContainer.new()
	var rb := UiTheme.glass_box(12, 0.42, 0.10)
	rb.shadow_size = 0
	rb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", rb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	# Map-Cover-Kachel (fuer fremde Raeume ist keine Map bekannt: Symbol).
	var cover := PanelContainer.new()
	var cs := UiTheme.glass_box(10, 0.7, 0.12)
	cs.shadow_size = 0
	cs.bg_color = Color(0.12, 0.2, 0.3, 0.8)
	cover.add_theme_stylebox_override("panel", cs)
	cover.custom_minimum_size = Vector2(54, 54)
	cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := Label.new()
	ic.text = badge
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", 24)
	cover.add_child(ic)
	hb.add_child(cover)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 3)
	hb.add_child(mid)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	mid.add_child(top)
	var nl := Label.new()
	nl.text = rname
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.add_theme_font_size_override("font_size", 16)
	nl.add_theme_color_override("font_color", COL_TEXT)
	top.add_child(nl)
	top.add_child(_chip("Spielt" if playing else "Wartet",
		Color(1.0, 0.7, 0.3) if playing else Color(0.5, 1.0, 0.6)))
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", -8)
	mid.add_child(bottom)
	for i in mini(players_n, 5):
		bottom.add_child(_avatar(rname + str(i), 22))
	var sl := Label.new()
	sl.text = "   %d Spieler  ·  %s" % [players_n, sub]
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", COL_DIM)
	bottom.add_child(sl)
	var jb := Button.new()
	jb.text = "JOIN"
	jb.custom_minimum_size = Vector2(76, 40)
	jb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(jb, true)
	jb.pressed.connect(on_join)
	hb.add_child(jb)
	UiTheme.attach_hover(card, 1.015)
	return card


func _draw_headphones(c: Control) -> void:
	var ctr := Vector2(c.size.x * 0.5, 26.0)
	c.draw_arc(ctr, 20.0, PI, TAU, 28, COL_DIM, 3.0, true)
	for sx in [-1.0, 1.0]:
		c.draw_rect(Rect2(ctr + Vector2(20.0 * sx - 5.0, 0.0), Vector2(10.0, 18.0)), COL_DIM, false, 3.0)


func _refresh_rooms() -> void:
	if _rooms_list == null:
		return
	for c in _rooms_list.get_children():
		c.queue_free()
	# LAN-Raeume zuerst (schnellste Route); weltweite danach, ohne Dubletten
	# (gleicher Raum-Code ueber beide Wege).
	var lan_codes := {}
	var count := 0
	for ip in Lobby.lan_rooms:
		var r: Dictionary = Lobby.lan_rooms[ip]
		lan_codes[str(r.get("code", ""))] = true
		var target_ip := str(ip)
		_rooms_list.add_child(_room_card("🏠", str(r.name), int(r.players),
			"Dein Netzwerk", func():
				if Lobby.join_lan(target_ip):
					_show_room()))
		count += 1
	for code in Lobby.online_rooms:
		if lan_codes.has(str(code)):
			continue
		var o: Dictionary = Lobby.online_rooms[code]
		var jcode := str(code)
		_rooms_list.add_child(_room_card("🌐", str(o.name), int(o.players),
			"Online  ·  " + jcode, func():
				if Lobby.join_code(jcode):
					_show_room()))
		count += 1
	var idx := 0
	for c in _rooms_list.get_children():
		_fade_in(c, idx)
		idx += 1
	if count == 0:
		var empty := VBoxContainer.new()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 10)
		var ei := Control.new()
		ei.custom_minimum_size = Vector2(56, 48)
		ei.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ei.draw.connect(func(): _draw_headphones(ei))
		empty.add_child(ei)
		var et := Label.new()
		et.text = "Gerade ist es ruhig hier"
		et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		et.add_theme_font_size_override("font_size", 18)
		et.add_theme_color_override("font_color", COL_TEXT)
		empty.add_child(et)
		var el := Label.new()
		el.text = "Keine offenen Räume. Erstelle einen, er erscheint hier automatisch bei allen Spielern."
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.custom_minimum_size = Vector2(320, 0)
		el.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.add_theme_constant_override("line_spacing", 6)
		el.add_theme_font_size_override("font_size", 13)
		el.add_theme_color_override("font_color", COL_DIM)
		empty.add_child(el)
		_rooms_list.add_child(empty)
		_fade_in(empty)


# ---------------------------------------------------------------------------
# Raum
# ---------------------------------------------------------------------------

func _build_room() -> void:
	_code_label = Label.new()
	_code_label.add_theme_font_size_override("font_size", 22)
	_code_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_room_box.add_child(_code_label)

	var players_head := Label.new()
	players_head.text = "SPIELER  (👑 wählt die Map und startet — der Kronenträger kann sie vergeben)"
	players_head.add_theme_font_size_override("font_size", 13)
	players_head.add_theme_color_override("font_color", COL_ACCENT)
	_room_box.add_child(players_head)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_players_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.add_child(_players_box)

	var map_card := PanelContainer.new()
	var mcs := UiTheme.glass_box(12, 0.5, 0.16)
	mcs.set_content_margin_all(10)
	map_card.add_theme_stylebox_override("panel", mcs)
	_room_box.add_child(map_card)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 14)
	map_card.add_child(mh)
	_map_cover = TextureRect.new()
	_map_cover.custom_minimum_size = Vector2(120, 68)
	_map_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_cover.clip_contents = true
	mh.add_child(_map_cover)
	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mv.add_theme_constant_override("separation", 2)
	mh.add_child(mv)
	_map_label = Label.new()
	_map_label.text = "Noch keine Map gewählt."
	_map_label.add_theme_font_size_override("font_size", 17)
	_map_label.add_theme_color_override("font_color", COL_TEXT)
	_map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mv.add_child(_map_label)
	_map_meta = Label.new()
	_map_meta.text = "Der Kronenträger wählt die Map."
	_map_meta.add_theme_font_size_override("font_size", 13)
	_map_meta.add_theme_color_override("font_color", COL_DIM)
	mv.add_child(_map_meta)

	# Mod-Chips: nur der Kronentraeger schaltet, alle anderen sehen sie read-only.
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	_room_box.add_child(mrow)
	var ml := Label.new()
	ml.text = "MODS"
	ml.add_theme_font_size_override("font_size", 13)
	ml.add_theme_color_override("font_color", COL_ACCENT)
	mrow.add_child(ml)
	for k in ["SV", "NF"]:
		var mb := Button.new()
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(110, 38)
		mb.add_theme_font_size_override("font_size", 16)
		UiTheme.style_button(mb)
		var key: String = k
		mb.pressed.connect(func():
			var nm: Dictionary = Lobby.mods.duplicate()
			nm[key] = not bool(nm.get(key, false))
			Lobby.pick_mods(nm)
			_refresh_room())
		mrow.add_child(mb)
		_mod_btns[k] = mb

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_room_box.add_child(btns)
	_pick_btn = Button.new()
	_pick_btn.text = "Map wählen"
	_pick_btn.custom_minimum_size = Vector2(0, 46)
	_pick_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_pick_btn)
	_pick_btn.pressed.connect(_open_picker)
	btns.add_child(_pick_btn)
	_start_btn = Button.new()
	_start_btn.text = "START"
	_start_btn.custom_minimum_size = Vector2(160, 46)
	UiTheme.style_button(_start_btn, true)
	_start_btn.pressed.connect(func(): Lobby.start_game())
	btns.add_child(_start_btn)
	var leave := Button.new()
	leave.text = "Verlassen"
	leave.custom_minimum_size = Vector2(120, 46)
	UiTheme.style_button(leave)
	leave.pressed.connect(func():
		Lobby.leave()
		_show_browser())
	btns.add_child(leave)


## Cover-Thumbnail der gewaehlten Map (null, wenn lokal nicht vorhanden).
func _map_cover_tex() -> Texture2D:
	var path := Lobby.resolve_local_path()
	if path == "":
		return null
	for ms in _library.mapsets:
		if ms.osz_path == path:
			return ms.thumb_texture()
	return null


func _show_room() -> void:
	Lobby.stop_discovery()
	_browser_box.visible = false
	_room_box.visible = true
	_refresh_room()


func _show_browser() -> void:
	_browser_box.visible = true
	_room_box.visible = false
	Lobby.start_discovery()
	_refresh_rooms()


func _refresh_room() -> void:
	if not _room_box.visible or _players_box == null:
		return
	_code_label.text = ("Raum-Code:  %s   (teilen!)" % Lobby.room_code) \
			if Lobby.room_code != "" else Lobby.room_name
	for c in _players_box.get_children():
		c.queue_free()
	var my_id := multiplayer.get_unique_id()
	var row_i := 0
	var in_round := false
	for id in Lobby.players:
		if int(Lobby.players[id].get("score", 0)) > 0:
			in_round = true
	for id in Lobby.players:
		var p: Dictionary = Lobby.players[id]
		var is_crown: bool = id == Lobby.crown_id
		var card := PanelContainer.new()
		var rs := UiTheme.glass_box(10, 0.45, 0.30 if is_crown else 0.10)
		rs.shadow_size = 0
		rs.set_content_margin_all(8)
		if is_crown:
			rs.border_color = Color(1.0, 0.85, 0.3, 0.55)
		card.add_theme_stylebox_override("panel", rs)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(_avatar(str(p.name), 34))
		var crown := Label.new()
		crown.text = CROWN if is_crown else ""
		crown.custom_minimum_size = Vector2(24, 0)
		crown.add_theme_font_size_override("font_size", 17)
		row.add_child(crown)
		var name_l := Label.new()
		name_l.text = str(p.name) + ("  (du)" if id == my_id else "")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", COL_TEXT)
		row.add_child(name_l)
		if in_round:
			var sc := Label.new()
			sc.text = "%s  ·  %s  ·  %dx" % [
				UiTheme.fmt_score(int(p.get("score", 0))),
				UiTheme.fmt_num(float(p.get("acc", 0.0)) * 100.0, 1) + " %", int(p.get("combo", 0))]
			sc.add_theme_font_size_override("font_size", 14)
			sc.add_theme_color_override("font_color", COL_ACCENT)
			row.add_child(sc)
		row.add_child(_chip("✓ Bereit", Color(0.5, 1.0, 0.6)) if bool(p.ready)
			else _chip("Wartet", COL_DIM))
		if Lobby.crown_id == my_id and not is_crown:
			var give := Button.new()
			give.text = CROWN + " geben"
			give.custom_minimum_size = Vector2(0, 32)
			give.add_theme_font_size_override("font_size", 13)
			UiTheme.style_button(give)
			var target := int(id)
			give.pressed.connect(func(): Lobby.give_crown(target))
			row.add_child(give)
		_players_box.add_child(card)
		UiTheme.attach_hover(card, 1.01)
		_fade_in(card, row_i)
		row_i += 1
	# Map-Karte + Buttons.
	if not Lobby.sel_map.is_empty():
		_map_label.text = "%s — %s" % [
			str(Lobby.sel_map.get("artist", "")), str(Lobby.sel_map.get("title", ""))]
		_map_meta.text = "[%s]   ★ %.2f" % [
			str(Lobby.sel_map.get("version", "")), float(Lobby.sel_map.get("stars", 0.0))]
		_map_cover.texture = _map_cover_tex()
	for k in _mod_btns:
		var mb: Button = _mod_btns[k]
		var on: bool = bool(Lobby.mods.get(k, false))
		mb.set_pressed_no_signal(on)
		mb.text = "%s  %s" % [k, "AN" if on else "AUS"]
		mb.disabled = Lobby.crown_id != my_id
		mb.modulate = Color(0.45, 1.0, 0.7) if on else Color(1, 1, 1, 0.85 if not mb.disabled else 0.6)
	_pick_btn.visible = Lobby.crown_id == my_id
	_start_btn.visible = Lobby.crown_id == my_id
	_start_btn.disabled = not Lobby.can_start()


# ---------------------------------------------------------------------------
# Map-Wahl (Kronentraeger) + Auto-Download
# ---------------------------------------------------------------------------

## Map-Picker im Browser-Stil: Karten mit Vorschaubild, Suche und
## Collection-Chips; Klick auf ein Set zeigt dessen Diffs.
func _open_picker() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var pdim := ColorRect.new()
	pdim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pdim.color = Color(0, 0, 0, 0.6)
	pdim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			overlay.queue_free())
	overlay.add_child(pdim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(16, 0.88)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(640, 560)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var t := Label.new()
	t.text = "Map wählen"
	t.add_theme_font_size_override("font_size", 20)
	vb.add_child(t)
	var search := LineEdit.new()
	search.placeholder_text = "Suchen…"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 40)
	search.add_theme_stylebox_override("normal", UiTheme.glass_box(8, 0.5))
	vb.add_child(search)

	# Collection-Chips (wie im Song-Browser).
	var coll_row := HBoxContainer.new()
	coll_row.add_theme_constant_override("separation", 6)
	vb.add_child(coll_row)
	var picker_state := { "coll": "", "q": "" }
	var coll_names := CollectionStore.list_names()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var fill := func():
		for c in list.get_children():
			c.queue_free()
		var q: String = str(picker_state.q).to_lower()
		var coll: String = str(picker_state.coll)
		var shown := 0
		for ms in _library.mapsets:
			if q != "" and not ms.search_haystack().contains(q):
				continue
			if coll != "" and not CollectionStore.contains(coll, ms.osz_path):
				continue
			var has_mania := false
			for i in ms.difficulty_count():
				if int(ms.meta_at(i).get("mode", 0)) == 3:
					has_mania = true
					break
			if not has_mania:
				continue
			list.add_child(_picker_card(ms, list, overlay))
			shown += 1
		if shown == 0:
			var empty := Label.new()
			empty.text = "Nichts gefunden."
			empty.add_theme_font_size_override("font_size", 13)
			empty.add_theme_color_override("font_color", COL_DIM)
			list.add_child(empty)

	# Chips bauen: "Alle" + jede Sammlung.
	var chip_defs := [""]
	chip_defs.append_array(coll_names)
	for cname in chip_defs:
		var chip := Button.new()
		chip.text = "Alle" if cname == "" else str(cname)
		chip.custom_minimum_size = Vector2(0, 30)
		chip.add_theme_font_size_override("font_size", 13)
		UiTheme.style_button(chip, cname == "")
		var target := str(cname)
		chip.pressed.connect(func():
			picker_state.coll = target
			fill.call())
		coll_row.add_child(chip)

	fill.call()
	search.text_changed.connect(func(txt):
		picker_state.q = txt
		fill.call())


## Karte im Browser-Stil: Thumb links, Titel/Mapper, Sterne-Bereich rechts.
## Klick klappt die Diff-Liste des Sets darunter auf.
func _picker_card(ms: MapSet, list: VBoxContainer, overlay: Control) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 66)
	UiTheme.style_button(card)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8
	hb.offset_right = -8
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(92, 52)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.texture = ms.thumb_texture()
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(thumb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(info)
	var title_l := Label.new()
	title_l.text = "%s — %s" % [ms.artist, ms.title]
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_l.add_theme_font_size_override("font_size", 15)
	title_l.add_theme_color_override("font_color", COL_TEXT)
	info.add_child(title_l)
	var sub_l := Label.new()
	sub_l.text = "Mapped by %s  ·  ★ %.2f" % [ms.creator, ms.max_stars()]
	sub_l.add_theme_font_size_override("font_size", 13)
	sub_l.add_theme_color_override("font_color", COL_DIM)
	info.add_child(sub_l)
	# Schon zusammen gespielt? Gruenes Badge direkt auf der Karte.
	if Lobby.set_was_played(ms.osz_path.get_file()):
		var pl := Label.new()
		pl.text = "✓ gespielt"
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pl.add_theme_font_size_override("font_size", 13)
		pl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pl)
	wrap.add_child(card)
	# Klick: Diff-Zeilen ein-/ausklappen.
	var diff_box := VBoxContainer.new()
	diff_box.visible = false
	diff_box.add_theme_constant_override("separation", 3)
	wrap.add_child(diff_box)
	card.pressed.connect(func():
		# Anhoeren beim Auswaehlen — wie im Song-Browser.
		_play_set_preview(ms.osz_path, ms.meta_at(0))
		if diff_box.visible:
			diff_box.visible = false
			return
		if diff_box.get_child_count() == 0:
			for i in ms.difficulty_count():
				if int(ms.meta_at(i).get("mode", 0)) != 3:
					continue
				var d := Button.new()
				var was := Lobby.was_played(ms.osz_path.get_file(), ms.version_name_at(i))
				d.text = "     [%s]   ★ %.2f%s" % [ms.version_name_at(i),
					ms.stars_at(i), "   ✓ gespielt" if was else ""]
				d.custom_minimum_size = Vector2(0, 34)
				d.alignment = HORIZONTAL_ALIGNMENT_LEFT
				d.add_theme_font_size_override("font_size", 13)
				UiTheme.style_button(d)
				if was:
					d.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
				var pick_diff := i
				d.pressed.connect(func():
					_pick(ms, pick_diff)
					overlay.queue_free())
				diff_box.add_child(d)
		diff_box.visible = true)
	return wrap


## Set-ID aus dem Dateinamen ziehen (fuehrende Zahl oder mirror_<id>).
func _set_id_of(fname: String) -> int:
	var base := fname.get_basename()
	if base.begins_with("mirror_") and base.substr(7).is_valid_int():
		return int(base.substr(7))
	var head := base.split(" ")[0]
	return int(head) if head.is_valid_int() else 0


func _pick(ms: MapSet, diff: int) -> void:
	var fname := ms.osz_path.get_file()
	Lobby.pick_map({
		"set_id": _set_id_of(fname), "file": fname,
		"version": ms.version_name_at(diff),
		"title": ms.title, "artist": ms.artist,
		"stars": ms.stars_at(diff),
	})


## Hintergrund aktualisieren: gewaehlte Map (falls lokal vorhanden),
## sonst zuletzt gespieltes Lied — jeweils geblurrt.
func _update_bg() -> void:
	var tex: Texture2D = null
	# 1) Im Raum: das ausgewaehlte Lied.
	if not Lobby.sel_map.is_empty():
		var path := Lobby.resolve_local_path()
		if path != "":
			for ms in _library.mapsets:
				if ms.osz_path == path:
					var full := OszImporter.load_image_texture(path, ms.background_file)
					tex = full if full != null else ms.thumb_texture()
					break
	# 2) Fallback: zuletzt gespielt (wie im Hauptmenue).
	if tex == null:
		var last := GameSession.load_last_played()
		if not last.is_empty() and str(last.get("bg_file", "")) != "":
			tex = OszImporter.load_image_texture(str(last.osz_path), str(last.bg_file))
	if tex != null:
		_bg_rect.texture = UiTheme.blurred_texture(tex)
		_bg_rect.visible = true


## Lokales Set leise vorhoeren (ab PreviewTime, mit Einblendung).
func _play_set_preview(osz_path: String, meta: Dictionary) -> void:
	var stream := OszImporter.load_audio_stream_named(osz_path, str(meta.get("audio_filename", "")))
	if stream == null:
		_status_label.text = "Vorschau: Audio nicht lesbar."
		return
	var preview_ms := float(meta.get("preview_time", -1.0))
	if preview_ms < 0:
		preview_ms = float(meta.get("duration_ms", 0.0)) * 0.4
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	_preview.stream = stream
	_preview.volume_db = -40.0
	_preview.play(maxf(preview_ms, 0.0) / 1000.0)
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", -14.0, 0.9)


## Leise Vorschau der gewaehlten Map (ab PreviewTime, mit Einblendung).
func _update_preview() -> void:
	if Lobby.sel_map.is_empty():
		_preview.stop()
		return
	var path := Lobby.resolve_local_path()
	if path == "":
		return  # kommt nach dem Download
	# Meta ueber die Library (Dateinamen-Vergleich), sonst direkt aus der .osz.
	var fname := path.get_file()
	for ms in _library.mapsets:
		if ms.osz_path.get_file() != fname:
			continue
		var m: Dictionary = ms.meta_at(0)
		for i in ms.difficulty_count():
			if ms.version_name_at(i) == str(Lobby.sel_map.get("version", "")):
				m = ms.meta_at(i)
				break
		_play_set_preview(path, m)
		return
	var imp := OszImporter.import(path)
	if imp.ok and not imp.difficulties.is_empty():
		var bm: Beatmap = imp.difficulties[0].beatmap
		_play_set_preview(path, {
			"audio_filename": bm.audio_filename(),
			"preview_time": float(bm.general.get("PreviewTime", -1.0)),
			"duration_ms": bm.duration_ms(),
		})


## Neue Map gewaehlt: lokal pruefen, sonst automatisch herunterladen.
func _on_map_changed() -> void:
	_refresh_room()
	_update_bg()
	_update_preview()
	if Lobby.sel_map.is_empty():
		return
	if Lobby.resolve_local_path() != "":
		Lobby.set_ready(true)
		_status_label.text = "Map vorhanden — bereit!"
		return
	var set_id := int(Lobby.sel_map.get("set_id", 0))
	if set_id <= 0:
		_status_label.text = "Map fehlt und hat keine Set-ID — Download nicht möglich."
		return
	if _downloading and _dl_set == set_id:
		return  # derselbe Download laeuft schon
	_downloading = true
	_dl_set = set_id
	_status_label.text = "Map fehlt — lade automatisch herunter…"
	_mirror.download(set_id, _library.maps_dir)


func _on_dl_progress(id: int, ratio: float) -> void:
	# Der Mirror ist global — nur auf den Download der Raum-Map reagieren.
	if _downloading and id == int(Lobby.sel_map.get("set_id", 0)):
		_status_label.text = "Lade Map… %d %%" % int(ratio * 100.0)


func _on_dl_done(id: int, _path: String) -> void:
	if id != int(Lobby.sel_map.get("set_id", 0)):
		return
	_downloading = false
	_library.scan()
	_status_label.text = "Map heruntergeladen — bereit!"
	Lobby.set_ready(true)
	_refresh_room()
	_update_bg()
	_update_preview()


func _on_dl_failed(id: int, message: String) -> void:
	if id != int(Lobby.sel_map.get("set_id", 0)):
		return
	_downloading = false
	_status_label.text = "Download fehlgeschlagen: " + message


func _back() -> void:
	if not Lobby.active:
		Lobby.stop_discovery()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
