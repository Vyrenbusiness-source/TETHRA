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
var _players_box: VBoxContainer
var _map_label: Label
var _status_label: Label
var _start_btn: Button
var _pick_btn: Button
var _code_label: Label
var _downloading := false
var _bg_rect: TextureRect
var _preview: AudioStreamPlayer
var _preview_fade: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new()
	_library.scan()
	_mirror = Mirror
	_preview = AudioStreamPlayer.new()
	_preview.bus = "Master"
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
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_update_bg()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.7)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(640, 520)
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
	_refresh_room()

	# Headless-Smoke: zwei Prozesse verbinden sich ueber localhost.
	if OS.get_cmdline_args().has("--mp-host-test"):
		Lobby.host_room()
		_mp_smoke(true)
	elif OS.get_cmdline_args().has("--mp-join-test"):
		Lobby.join_lan("127.0.0.1")
		_mp_smoke(false)


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


func _exit_tree() -> void:
	Lobby.stop_discovery()


# ---------------------------------------------------------------------------
# Browser (Raum erstellen / Code / LAN-Liste)
# ---------------------------------------------------------------------------

func _build_browser() -> void:
	var create := Button.new()
	create.text = "+ Raum erstellen (Port oeffnet automatisch)"
	create.custom_minimum_size = Vector2(0, 52)
	create.add_theme_font_size_override("font_size", 18)
	UiTheme.style_button(create, true)
	create.pressed.connect(func():
		if Lobby.host_room():
			_show_room())
	_browser_box.add_child(create)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	_browser_box.add_child(code_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Raum-Code eingeben (z.B. 7K3F9-A2QXM)…"
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, 44)
	_code_edit.add_theme_stylebox_override("normal", UiTheme.glass_box(10, 0.55))
	_code_edit.text_submitted.connect(func(_t): _join_by_code())
	code_row.add_child(_code_edit)
	var join := Button.new()
	join.text = "Beitreten"
	join.custom_minimum_size = Vector2(120, 44)
	UiTheme.style_button(join, true)
	join.pressed.connect(_join_by_code)
	code_row.add_child(join)

	var lan_head := Label.new()
	lan_head.text = "RAEUME IN DEINEM NETZWERK (automatisch)"
	lan_head.add_theme_font_size_override("font_size", 13)
	lan_head.add_theme_color_override("font_color", COL_ACCENT)
	_browser_box.add_child(lan_head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_browser_box.add_child(scroll)
	_rooms_list = VBoxContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_rooms_list)
	_refresh_rooms()


func _join_by_code() -> void:
	if Lobby.join_code(_code_edit.text):
		_show_room()


func _refresh_rooms() -> void:
	if _rooms_list == null:
		return
	for c in _rooms_list.get_children():
		c.queue_free()
	if Lobby.lan_rooms.is_empty():
		var empty := Label.new()
		empty.text = "Keine Raeume im Netzwerk — erstelle einen oder nutze einen Code."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", COL_DIM)
		_rooms_list.add_child(empty)
		return
	for ip in Lobby.lan_rooms:
		var r: Dictionary = Lobby.lan_rooms[ip]
		var b := Button.new()
		b.text = "%s   ·   %d Spieler" % [str(r.name), int(r.players)]
		b.custom_minimum_size = Vector2(0, 44)
		UiTheme.style_button(b)
		var target_ip := str(ip)
		b.pressed.connect(func():
			if Lobby.join_lan(target_ip):
				_show_room())
		_rooms_list.add_child(b)


# ---------------------------------------------------------------------------
# Raum
# ---------------------------------------------------------------------------

func _build_room() -> void:
	_code_label = Label.new()
	_code_label.add_theme_font_size_override("font_size", 22)
	_code_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_room_box.add_child(_code_label)

	var players_head := Label.new()
	players_head.text = "SPIELER  (👑 waehlt die Map — Host klickt einen Spieler, um sie zu vergeben)"
	players_head.add_theme_font_size_override("font_size", 13)
	players_head.add_theme_color_override("font_color", COL_ACCENT)
	_room_box.add_child(players_head)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	_players_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.add_child(_players_box)

	_map_label = Label.new()
	_map_label.text = "Noch keine Map gewaehlt."
	_map_label.add_theme_font_size_override("font_size", 15)
	_map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_box.add_child(_map_label)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	_room_box.add_child(btns)
	_pick_btn = Button.new()
	_pick_btn.text = "Map waehlen"
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
	for id in Lobby.players:
		var p: Dictionary = Lobby.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var crown := Label.new()
		crown.text = CROWN if id == Lobby.crown_id else " "
		crown.custom_minimum_size = Vector2(30, 0)
		crown.add_theme_font_size_override("font_size", 17)
		row.add_child(crown)
		var name_l := Label.new()
		name_l.text = str(p.name) + ("  (du)" if id == my_id else "")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", COL_TEXT)
		row.add_child(name_l)
		var ready := Label.new()
		ready.text = "✓ bereit" if bool(p.ready) else "…"
		ready.add_theme_font_size_override("font_size", 13)
		ready.add_theme_color_override("font_color",
			Color(0.5, 1.0, 0.6) if bool(p.ready) else COL_DIM)
		row.add_child(ready)
		if Lobby.is_host and id != Lobby.crown_id:
			var give := Button.new()
			give.text = CROWN + " geben"
			give.custom_minimum_size = Vector2(0, 32)
			give.add_theme_font_size_override("font_size", 12)
			UiTheme.style_button(give)
			var target := int(id)
			give.pressed.connect(func(): Lobby.give_crown(target))
			row.add_child(give)
		_players_box.add_child(row)
	# Map-Zeile + Buttons.
	if not Lobby.sel_map.is_empty():
		_map_label.text = "Map:  %s — %s  [%s]  ★ %.2f" % [
			str(Lobby.sel_map.get("artist", "")), str(Lobby.sel_map.get("title", "")),
			str(Lobby.sel_map.get("version", "")), float(Lobby.sel_map.get("stars", 0.0))]
	_pick_btn.visible = Lobby.crown_id == my_id
	_start_btn.visible = Lobby.is_host
	_start_btn.disabled = not Lobby.all_ready()


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
	t.text = "Map waehlen"
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
	sub_l.add_theme_font_size_override("font_size", 12)
	sub_l.add_theme_color_override("font_color", COL_DIM)
	info.add_child(sub_l)
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
				d.text = "     [%s]   ★ %.2f" % [ms.version_name_at(i), ms.stars_at(i)]
				d.custom_minimum_size = Vector2(0, 34)
				d.alignment = HORIZONTAL_ALIGNMENT_LEFT
				d.add_theme_font_size_override("font_size", 13)
				UiTheme.style_button(d)
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
	if Lobby.sel_map.is_empty() or _downloading:
		return
	if Lobby.resolve_local_path() != "":
		Lobby.set_ready(true)
		_status_label.text = "Map vorhanden — bereit!"
		return
	var set_id := int(Lobby.sel_map.get("set_id", 0))
	if set_id <= 0:
		_status_label.text = "Map fehlt und hat keine Set-ID — Download nicht moeglich."
		return
	_downloading = true
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
