extends Control

## Multiplayer-Lobby: Raum erstellen (Port oeffnet sich automatisch per UPnP,
## Raum-Code zum Teilen), per Code beitreten, LAN-Raeume erscheinen von selbst.
## Im Raum: Spielerliste mit Krone (Host vergibt sie), Kronentraeger waehlt
## die Map, fehlende Maps laden automatisch vom Mirror, Host startet.
##
## Layout (Vollbild, 8er-Raster, Rand M): Kopfzeile, darunter entweder der
## Raum-Browser (Formulare oben, Raumkarten darunter) oder der Raum
## (links Raum-Panel mit Spielern, rechts Map-Karte, unten Aktionsleiste).

const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := UiTheme.DIM
const COL_TEXT := UiTheme.TEXT
## Farbe nur fuer Bedeutung: Krone, Bereit, Team-Farben (TeamBoard), Primaer.
const COL_GOLD := Color(0.95, 0.79, 0.38)
const COL_READY := Color(0.47, 0.85, 0.60)
const COL_CARD := Color(0.08, 0.08, 0.11, 0.94)
const COL_CARD_HOVER := Color(0.12, 0.12, 0.16, 0.96)
const COL_LINE := Color(1, 1, 1, 0.08)
## Raster: Rand/Spaltenabstand, Zeilenhoehen. Schrift: 4 Groessen.
const M := 24
const HEAD_H := 40
const BAR_H := 48
const ROW_H := 40
const PROW_H := 34
const FS_S := 13
const FS_M := 15
const FS_L := 20
const FS_XL := 26

var _library: MapLibrary
var _mirror: BeatmapMirror
var _browser_box: VBoxContainer
var _room_box: VBoxContainer
var _rooms_list: GridContainer
var _rooms_count: Label
var _code_edit: LineEdit
var _name_edit: LineEdit
var _pw_edit: LineEdit
var _join_pw_edit: LineEdit
var _fetch_timer: Timer
var _players_box: VBoxContainer
var _players_scroll: ScrollContainer
var _players_head: Label
var _ready_count: Label
var _room_title: Label
var _players_headrow: HBoxContainer
var _map_drow: HBoxContainer
var _copy_btn: Button
var _map_label: Label
var _map_artist: Label
var _map_meta: Label
var _map_stats: Label
var _map_cover: TextureRect
var _map_shade: TextureRect
var _map_empty: Label
var _star_pill: PanelContainer
var _star_label: Label
var _status_label: Label
var _start_btn: Button
var _pick_btn: Button
var _leave_btn: Button
var _mod_btns: Dictionary = {}
var _code_label: Label
var _downloading := false
var _dl_set := 0
var _bg_rect: TextureRect
var _map_tex: Texture2D = null
var _preview: AudioStreamPlayer
var _preview_fade: Tween
var _picker: MapPicker = null
var _dl_row: HBoxContainer
var _dl_text: Label
var _dl_btn: Button
var _dl_bar: ProgressBar
var _dl_label: Label
var _dl_cancel: Button
# Turnier: Raum-Knopf, Setup-Dialog, Phasen-Ansicht und Endbild.
var _center: Control
var _tour_btn: Button
var _tour_dialog: Control = null
var _tpanel: TournamentPanel = null
var _tend: TournamentEnd = null
var _tour_phase := -1
var _mode_btns: Array = []
var _mode_row: HBoxContainer
var _mode_info: Label
var _board_holder: VBoxContainer
var _team_board: TeamBoard = null
var _royale_board: RoyaleBoard = null
var _balance_btn: Button
var _tour_hidden := false
## Bereits gezeigte Spieler (nur neue Zeilen blenden ein, kein Flackern bei Scores).
var _seen_rows: Dictionary = {}
var _bpm_cache: Dictionary = {}
var _icons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new(_arg_value("--mp-maps="))
	_library.scan()
	_mirror = Mirror
	_preview = AudioStreamPlayer.new()
	_preview.bus = "Music"
	add_child(_preview)
	_mirror.download_progress.connect(_on_dl_progress)
	_mirror.download_done.connect(_on_dl_done)
	_mirror.download_failed.connect(_on_dl_failed)
	_mirror.download_cancelled.connect(_on_dl_cancelled)

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
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Vollbild-Raster: Rand M ringsum, Kopfzeile + Inhalt (Browser oder Raum).
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = M
	root.offset_top = M
	root.offset_right = -M
	root.offset_bottom = -M
	root.add_theme_constant_override("separation", M)
	add_child(root)
	_center = root

	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, HEAD_H)
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	var back := _icon_btn(_icon("back"), "Zurück (Esc)")
	back.pressed.connect(_back)
	head.add_child(back)
	var title := _lbl("Multiplayer", FS_L, COL_TEXT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_status_label = _lbl(" ", FS_S, COL_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_status_label)

	_browser_box = VBoxContainer.new()
	_browser_box.add_theme_constant_override("separation", 0)
	_browser_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_browser_box)
	_build_browser()

	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", M)
	_room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.visible = false
	root.add_child(_room_box)
	_build_room()
	_update_bg()

	Lobby.players_changed.connect(_refresh_room)
	Lobby.scores_changed.connect(_refresh_room)
	Lobby.map_changed.connect(_on_map_changed)
	Lobby.rooms_changed.connect(_refresh_rooms)
	Lobby.tournament_changed.connect(_sync_tournament)
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
	_sync_tournament()

	if OS.get_cmdline_args().has("--shot-tournament") or OS.get_cmdline_user_args().has("--shot-tournament"):
		_tournament_shots()
	if OS.get_cmdline_args().has("--shot-modes") or OS.get_cmdline_user_args().has("--shot-modes"):
		_mode_shots()
	if OS.get_cmdline_args().has("--shot-lobby") or OS.get_cmdline_user_args().has("--shot-lobby"):
		_lobby_shots()
	if OS.get_cmdline_args().has("--shot-mp"):
		_capture_shot()
	if OS.get_cmdline_args().has("--shot-picker") or OS.get_cmdline_user_args().has("--shot-picker"):
		_picker_shots()
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
	elif OS.get_cmdline_args().has("--mp-dl-host"):
		if not Lobby.active:
			Lobby.host_room()
		_mp_dl(true)
	elif OS.get_cmdline_args().has("--mp-dl-client"):
		if not Lobby.active:
			Lobby.join_lan("127.0.0.1")
		_mp_dl(false)
	elif OS.get_cmdline_args().has("--mp-auto-client"):
		if not Lobby.active:
			Lobby.join_lan("127.0.0.1")
		_mp_auto(false)


## Wert einer Kommandozeilen-Option "--name=wert" ("" = fehlt).
static func _arg_value(prefix: String) -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


## Download-Flow-Test (Host + Client, getrennte Scratch-Bibliotheken per
## --mp-maps=). Host: Online-Tab -> kleinste Map laden -> fuer Raum gewaehlt.
## Client: sieht fehlende Map, Abbruch, "Map laden", gleiche Set-ID, bereit.
func _mp_dl(host: bool) -> void:
	var tag := "HOST" if host else "CLIENT"
	var step := func(msg: String): print("MPDL %s %s" % [tag, msg])
	var wait_for := func(cond: Callable, secs: float) -> bool:
		var w := 0.0
		while w < secs and not cond.call():
			await get_tree().create_timer(0.1).timeout
			w += 0.1
		return cond.call()
	step.call("maps_dir=" + _library.maps_dir)
	if not await wait_for.call(func(): return Lobby.players.size() >= 2 and Lobby.players.has(multiplayer.get_unique_id()), 20.0):
		step.call("TIMEOUT players")
		get_tree().quit(1)
		return
	step.call("players synced")
	if host:
		_open_picker()
		_picker.open_online()
		var online: OnlineBrowser = _picker._online
		if not await wait_for.call(func(): return not online._results.is_empty(), 30.0):
			step.call("TIMEOUT online search")
			get_tree().quit(1)
			return
		var best: Dictionary = {}
		for r in online._results:
			if int(r.get("set_id", 0)) <= 0:
				continue
			if best.is_empty() or int(r.get("length_s", 9999)) < int(best.get("length_s", 9999)):
				best = r
		step.call("online %d Ergebnisse, kleinste: set=%s len=%s" % [online._results.size(), str(best.get("set_id")), str(best.get("length_s"))])
		var sid := int(best.get("set_id", 0))
		online.start_download(sid)
		if not await wait_for.call(func(): return int(Lobby.sel_map.get("set_id", 0)) == sid, 120.0):
			step.call("TIMEOUT download/pick")
			get_tree().quit(1)
			return
		step.call("host: Raum-Map gewaehlt set=%d local=%s ready=%s" % [sid, Lobby.resolve_local_path(), str(Lobby.players[multiplayer.get_unique_id()].get("ready", "?"))])
		if not await wait_for.call(func(): return Lobby.all_ready(), 150.0):
			step.call("TIMEOUT all_ready")
			get_tree().quit(1)
			return
		step.call("all_ready OK")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
	else:
		if not await wait_for.call(func(): return not Lobby.sel_map.is_empty(), 150.0):
			step.call("TIMEOUT sel_map")
			get_tree().quit(1)
			return
		var sid := int(Lobby.sel_map.get("set_id", 0))
		step.call("client sieht Map set=%d local='%s' downloading=%s btn_visible=%s" % [sid, Lobby.resolve_local_path(), str(_downloading), str(_dl_btn.visible)])
		await get_tree().create_timer(0.8).timeout
		_dl_cancel.pressed.emit()
		await get_tree().create_timer(0.8).timeout
		step.call("nach Abbruch: downloading=%s btn_visible=%s status='%s'" % [str(_downloading), str(_dl_btn.visible), _status_label.text])
		_dl_btn.pressed.emit()
		step.call("Klick Map laden: downloading=%s dl_set=%d (soll %d)" % [str(_downloading), _dl_set, sid])
		if not await wait_for.call(func(): return Lobby.resolve_local_path() != "", 120.0):
			step.call("TIMEOUT download status='%s'" % _status_label.text)
			get_tree().quit(1)
			return
		await get_tree().create_timer(1.0).timeout
		step.call("fertig local=%s status='%s' ready=%s" % [Lobby.resolve_local_path(), _status_label.text, str(Lobby.all_ready())])
		await get_tree().create_timer(2.0).timeout
		get_tree().quit(0)


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
	var path := _shot_prefix("user://mp") + "_browser.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


## Screenshot-Praefix aus --shot-out=<Praefix> (sonst fallback).
static func _shot_prefix(fallback: String) -> String:
	var out := ProjectSettings.globalize_path(fallback)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			out = a.substr(11)
	return out


## Screenshots des Map-Pickers: offen, Suche aktiv, Diff mit eigenem Score.
## Ziel: --shot-out=<Praefix> (sonst user://picker).
func _picker_shots() -> void:
	var out := ProjectSettings.globalize_path("user://picker")
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			out = a.substr(11)
	var shot := func(tag: String):
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [out, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT " + path)
	await get_tree().create_timer(0.5).timeout
	_open_picker()
	await get_tree().create_timer(1.5).timeout
	print("PICKER %d Maps" % _picker.shown_count())
	await shot.call("open")
	# Suchwort aus einer Map mit eigenem Score (sonst ein haeufiger Buchstabe).
	var q := "a"
	var best: Dictionary = MapPicker.load_scores().best
	for ms in _library.mapsets:
		var hit := false
		for i in ms.difficulty_count():
			if best.has("%s|%s" % [ms.osz_path.get_file(), ms.version_name_at(i)]):
				hit = true
				break
		if hit:
			for w in ms.title.split(" ", false):
				if w.length() >= 3:
					q = w.to_lower()
					break
			break
	_picker.set_query(q)
	await get_tree().create_timer(0.8).timeout
	print("PICKER Suche '%s': %d Treffer" % [q, _picker.shown_count()])
	await shot.call("search")
	print("PICKER Score-Set gefunden: %s" % str(_picker.select_first_scored()))
	await get_tree().create_timer(0.8).timeout
	await shot.call("score")
	# Online-Tab (Komponente des Song-Browsers) im Picker.
	_picker.open_online()
	await get_tree().create_timer(4.0).timeout
	print("PICKER Online offen: %s" % str(_picker.online_open()))
	await shot.call("online")
	_picker.close()
	await get_tree().create_timer(0.3).timeout
	print("PICKER geschlossen: %s" % str(not _picker.is_open()))
	get_tree().quit(0)


func _exit_tree() -> void:
	Lobby.stop_discovery()


# ---------------------------------------------------------------------------
# Bausteine: Labels, Knoepfe, Schalter, Icons (eine Schrift, 4 Groessen)
# ---------------------------------------------------------------------------

func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Kleine Abschnitts-Ueberschrift (Versalien, gedimmt, nicht gesperrt).
func _caption(text: String) -> Label:
	var l := _lbl(text, FS_S, COL_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Dezente Trennlinie statt Kasten.
func _sep() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COL_LINE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _box(bg: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.anti_aliasing = true
	return sb


## Haupt-Flaeche (wie das Info-Panel im Song-Browser), Innenrand M.
func _panel_box(margin: int = M) -> StyleBoxFlat:
	var sb := UiTheme.glass_box(16, 0.62, 0.10)
	sb.set_content_margin_all(margin)
	return sb


## Knopf mit echten Zustaenden (Hover/Pressed/Disabled/Fokus), ohne Skalieren.
## primary: einzige gefuellte Akzentflaeche pro Ansicht.
func _btn(text: String, primary: bool = false, h: int = BAR_H) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", FS_M)
	var r := 10
	var n: StyleBoxFlat
	var hv: StyleBoxFlat
	var pr: StyleBoxFlat
	if primary:
		n = _box(UiTheme.primary_fill(), r)
		hv = _box(UiTheme.primary_fill().lightened(0.10), r)
		pr = _box(UiTheme.primary_fill().darkened(0.12), r)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(fc, Color(0.02, 0.05, 0.08))
	else:
		n = _box(Color(1, 1, 1, 0.05), r, Color(1, 1, 1, 0.12))
		hv = _box(Color(1, 1, 1, 0.10), r, Color(1, 1, 1, 0.22))
		pr = _box(Color(1, 1, 1, 0.03), r, Color(1, 1, 1, 0.18))
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_pressed_color", COL_TEXT)
		b.add_theme_color_override("font_focus_color", COL_TEXT)
	var ds := _box(Color(1, 1, 1, 0.03), r, Color(1, 1, 1, 0.06))
	if primary:
		# Gesperrt bleibt als Primaer-Platz erkennbar (Akzent-Rand), aber ohne Fuellung.
		ds = _box(Color(UiTheme.primary_fill(), 0.10), r, Color(UiTheme.primary_fill(), 0.30))
	b.add_theme_color_override("font_disabled_color", Color(COL_DIM, 0.7))
	for sb in [n, hv, pr, ds]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", ds)
	b.add_theme_stylebox_override("focus", UiTheme._focus_box(r))
	b.add_theme_constant_override("h_separation", 8)
	UiTheme._attach_sounds(b)
	return b


## Quadratischer Icon-Knopf (Zurueck, Krone geben).
func _icon_btn(icon: Texture2D, tip: String, sz: int = HEAD_H) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(sz, sz)
	b.focus_mode = Control.FOCUS_NONE
	var n := _box(Color(1, 1, 1, 0.0), 10, Color(1, 1, 1, 0.14))
	var hv := _box(Color(1, 1, 1, 0.08), 10, Color(1, 1, 1, 0.26))
	var pr := _box(Color(1, 1, 1, 0.14), 10, Color(1, 1, 1, 0.26))
	for sb in [n, hv, pr]:
		sb.set_content_margin_all(0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("icon_normal_color", COL_DIM)
	b.add_theme_color_override("icon_hover_color", COL_TEXT)
	b.add_theme_color_override("icon_pressed_color", COL_TEXT)
	UiTheme._attach_sounds(b)
	return b


## Reiter-Chip im Look der Song-Browser-Tabs (aktiv = Akzent-Rand + Akzent-Text).
func _chip_toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", FS_S + 1)
	UiTheme._attach_sounds(b)
	_paint_chip(b, false)
	return b


func _paint_chip(b: Button, active: bool) -> void:
	var mk := func(hover: bool) -> StyleBoxFlat:
		var sb: StyleBoxFlat
		if active:
			sb = _box(Color(COL_ACCENT, 0.22 if hover else 0.15), 10, Color(COL_ACCENT, 0.6))
		else:
			sb = _box(Color(1, 1, 1, 0.09 if hover else 0.04), 10, Color(1, 1, 1, 0.22 if hover else 0.12))
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		return sb
	var n: StyleBoxFlat = mk.call(false)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("hover", mk.call(true))
	b.add_theme_stylebox_override("hover_pressed", mk.call(true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var dis: StyleBoxFlat = n.duplicate()
	if not active:
		dis.border_color = Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("disabled", dis)
	var fg := COL_ACCENT if active else COL_DIM
	for fc in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, fg)
	b.add_theme_color_override("font_hover_color", COL_ACCENT if active else COL_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", COL_ACCENT if active else COL_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.85) if active else Color(COL_DIM, 0.55))


## Mod-Schalter wie im Song-Browser (No-Fail / SV): Rahmen + Switch-Icon.
func _mod_toggle(text: String, tip: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(0, ROW_H)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_font_size_override("font_size", FS_S + 1)
	var mk := func(hover: bool) -> StyleBoxFlat:
		var sb := _box(Color(1, 1, 1, 0.09 if hover else 0.04), 10, Color(1, 1, 1, 0.22 if hover else 0.12))
		sb.content_margin_left = 14
		sb.content_margin_right = 10
		return sb
	c.add_theme_stylebox_override("normal", mk.call(false))
	c.add_theme_stylebox_override("pressed", mk.call(false))
	c.add_theme_stylebox_override("hover", mk.call(true))
	c.add_theme_stylebox_override("hover_pressed", mk.call(true))
	var dis: StyleBoxFlat = mk.call(false)
	dis.bg_color = Color(1, 1, 1, 0.02)
	dis.border_color = Color(1, 1, 1, 0.07)
	c.add_theme_stylebox_override("disabled", dis)
	c.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(fc, COL_TEXT)
	c.add_theme_color_override("font_disabled_color", COL_DIM)
	UiTheme._attach_sounds(c)
	return c


## Linien-/Flaechen-Icons, einmal gerastert (weiss, Farbe per modulate/icon_color).
func _icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var tex: Texture2D
	match id:
		"back":
			tex = _line_icon(16, [[Vector2(10, 3.5), Vector2(5.5, 8)], [Vector2(5.5, 8), Vector2(10, 12.5)]])
		"next":
			tex = _line_icon(16, [[Vector2(6, 3.5), Vector2(10.5, 8)], [Vector2(10.5, 8), Vector2(6, 12.5)]])
		"crown":
			tex = _fill_icon(16, PackedVector2Array([Vector2(2, 12.5), Vector2(1.5, 4.5), Vector2(5.3, 7.8),
				Vector2(8, 3), Vector2(10.7, 7.8), Vector2(14.5, 4.5), Vector2(14, 12.5)]),
				Rect2(2, 13.5, 12, 1.6))
		"globe":
			var segs: Array = []
			for i in 24:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				segs.append([Vector2(10, 10) + Vector2(cos(a0), sin(a0)) * 7.5, Vector2(10, 10) + Vector2(cos(a1), sin(a1)) * 7.5])
				segs.append([Vector2(10, 10) + Vector2(cos(a0) * 3.2, sin(a0) * 7.5), Vector2(10, 10) + Vector2(cos(a1) * 3.2, sin(a1) * 7.5)])
			segs.append([Vector2(2.5, 10), Vector2(17.5, 10)])
			tex = _line_icon(20, segs)
		"lan":
			tex = _line_icon(20, [[Vector2(3, 4), Vector2(17, 4)], [Vector2(17, 4), Vector2(17, 13)],
				[Vector2(17, 13), Vector2(3, 13)], [Vector2(3, 13), Vector2(3, 4)],
				[Vector2(10, 13), Vector2(10, 16.5)], [Vector2(6, 16.5), Vector2(14, 16.5)]])
		"copy":
			tex = _line_icon(16, [[Vector2(5.5, 5.5), Vector2(13, 5.5)], [Vector2(13, 5.5), Vector2(13, 13)],
				[Vector2(13, 13), Vector2(5.5, 13)], [Vector2(5.5, 13), Vector2(5.5, 5.5)],
				[Vector2(3, 10.5), Vector2(3, 3)], [Vector2(3, 3), Vector2(10.5, 3)]])
		"down":
			tex = _line_icon(16, [[Vector2(8, 2), Vector2(8, 10.5)], [Vector2(4.5, 7.5), Vector2(8, 11)],
				[Vector2(11.5, 7.5), Vector2(8, 11)], [Vector2(3, 13.5), Vector2(13, 13.5)]])
	_icons[id] = tex
	return tex


## Kleines Linien-Icon (weiss, ~1,6 px, kantengeglaettet) aus Segmenten.
static func _line_icon(size: int, segs: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half_w := 0.85
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := 99.0
			for s in segs:
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				d = minf(d, p.distance_to(a + ab * t))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(half_w - d + 0.6, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Gefuelltes Icon (Polygon + optionales Rechteck), 4x4-Supersampling.
static func _fill_icon(size: int, poly: PackedVector2Array, rect: Rect2 = Rect2()) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var hit := 0
			for sy in 4:
				for sx in 4:
					var p := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)
					if Geometry2D.is_point_in_polygon(p, poly) or rect.has_point(p):
						hit += 1
			img.set_pixel(x, y, Color(1, 1, 1, hit / 16.0))
	return ImageTexture.create_from_image(img)


func _icon_rect(id: String, col: Color, sz: int = 16) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _icon(id)
	t.modulate = col
	t.custom_minimum_size = Vector2(sz, sz)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Runder Punkt (Bereit-Status).
func _dot(col: Color, sz: int = 8) -> Control:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _box(col, sz))
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ---------------------------------------------------------------------------
# Browser (Raum erstellen / Code / offene Raeume)
# ---------------------------------------------------------------------------

func _build_browser() -> void:
	# Oben zwei Formulare nebeneinander: gleiche Hoehe, gleiche Kanten.
	var forms := HBoxContainer.new()
	forms.add_theme_constant_override("separation", M)
	_browser_box.add_child(forms)

	var create_row := _form(forms, "RAUM ERSTELLEN",
		"Ohne Passwort erscheint der Raum bei allen in der Liste.", 1.25)
	_name_edit = _field("Raumname", 1.3)
	_name_edit.text = _possessive_room(Settings.profile_name)
	_name_edit.max_length = 28
	create_row.add_child(_name_edit)
	_pw_edit = _field("Passwort (leer = öffentlich)", 1.0)
	create_row.add_child(_pw_edit)
	var create := _btn("RAUM ERSTELLEN", true, ROW_H)
	create.custom_minimum_size.x = 160
	var do_create := func():
		if Lobby.host_room(_name_edit.text, _pw_edit.text):
			_show_room()
	create.pressed.connect(do_create)
	_name_edit.text_submitted.connect(func(_t): do_create.call())
	_pw_edit.text_submitted.connect(func(_t): do_create.call())
	create_row.add_child(create)

	var join_row := _form(forms, "MIT CODE BEITRETEN",
		"Den Code bekommst du vom Host des Raums.", 1.0)
	_code_edit = _field("Code (z. B. 7K3F9-A2QXM)", 1.2)
	_code_edit.text_submitted.connect(func(_t): _join_by_code())
	join_row.add_child(_code_edit)
	_join_pw_edit = _field("Passwort (falls gesetzt)", 1.0)
	_join_pw_edit.text_submitted.connect(func(_t): _join_by_code())
	join_row.add_child(_join_pw_edit)
	var join := _btn("Beitreten", false, ROW_H)
	join.custom_minimum_size.x = 120
	join.pressed.connect(_join_by_code)
	join_row.add_child(join)

	_browser_box.add_child(_gap(M))
	_browser_box.add_child(_sep())
	_browser_box.add_child(_gap(16))

	var rooms_head := HBoxContainer.new()
	rooms_head.custom_minimum_size = Vector2(0, 32)
	rooms_head.add_theme_constant_override("separation", 8)
	_browser_box.add_child(rooms_head)
	rooms_head.add_child(_caption("OFFENE RÄUME"))
	_rooms_count = _caption("")
	_rooms_count.add_theme_color_override("font_color", COL_TEXT)
	rooms_head.add_child(_rooms_count)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_head.add_child(sp)
	var refresh := _btn("Liste aktualisieren", false, 32)
	refresh.add_theme_font_size_override("font_size", FS_S)
	refresh.pressed.connect(func(): Lobby.fetch_online_rooms())
	rooms_head.add_child(refresh)
	_browser_box.add_child(_gap(8))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_browser_box.add_child(scroll)
	_rooms_list = GridContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("h_separation", 16)
	_rooms_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_rooms_list)
	# Spaltenzahl folgt der Breite (1280: 2, 1920: 3), Karten nie schmaler als 440.
	scroll.resized.connect(func(): _layout_rooms(scroll.size.x))
	_refresh_rooms()


## Formular-Block: Ueberschrift, Eingabezeile, Hinweis. Gibt die Zeile zurueck.
func _form(parent: Control, head: String, hint: String, ratio: float) -> HBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = ratio
	v.add_theme_constant_override("separation", 8)
	parent.add_child(v)
	v.add_child(_caption(head))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var h := _lbl(hint, FS_S, COL_DIM)
	h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(h)
	return row


func _field(placeholder: String, ratio: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, ROW_H)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.size_flags_stretch_ratio = ratio
	e.add_theme_font_size_override("font_size", FS_M - 1)
	return e


func _layout_rooms(w: float) -> void:
	if _rooms_list == null:
		return
	var only_empty := _rooms_list.get_child_count() == 1 and _rooms_list.get_child(0).has_meta("empty")
	_rooms_list.columns = 1 if only_empty else clampi(int((w + 16.0) / 456.0), 1, 3)


## Genitiv: Namen auf s/x/z (auch ss) nur mit Apostroph, sonst "s".
static func _possessive_room(n: String) -> String:
	var t := n.strip_edges()
	if t.is_empty():
		return TranslationServer.translate("Raum")
	var last := t.substr(t.length() - 1).to_lower()
	if last in ["s", "x", "z"]:
		return TranslationServer.translate("%s' Raum") % t
	return TranslationServer.translate("%s's Raum") % t


func _join_by_code() -> void:
	if Lobby.join_code(_code_edit.text, _join_pw_edit.text):
		_show_room()


## Ruhiges Einblenden neu aufgebauter Zeilen (index staffelt leicht).
func _fade_in(c: Control, idx: int = 0) -> void:
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(minf(idx * 0.03, 0.24))
	tw.tween_property(c, "modulate:a", 1.0, 0.18)


## Runder Avatar mit Anfangsbuchstabe; gedeckte Farbe aus dem Namen.
func _avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(
		Color.from_hsv(float(absi(pname.hash()) % 360) / 360.0, 0.32, 0.46), sz))
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(sz * 0.46))
	l.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(l)
	return p


## Raumkarte im Kartenstil des Song-Browsers; die ganze Karte ist der Knopf.
## Die Raum-Ansage kennt nur Name, Spielerzahl und Code (keine Map/Modus).
func _room_card(lan: bool, rname: String, players_n: int, sub: String,
		on_join: Callable) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 72)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = rname
	var n := _box(COL_CARD, 12, Color(1, 1, 1, 0.06))
	var hv := _box(COL_CARD_HOVER, 12, Color(1, 1, 1, 0.16))
	var pr := _box(Color(0.06, 0.06, 0.09, 0.96), 12, Color(1, 1, 1, 0.16))
	card.add_theme_stylebox_override("normal", n)
	card.add_theme_stylebox_override("hover", hv)
	card.add_theme_stylebox_override("pressed", pr)
	card.add_theme_stylebox_override("focus", UiTheme._focus_box(12))
	UiTheme._attach_sounds(card)
	card.pressed.connect(on_join)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16
	hb.offset_right = -16
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.05), 10))
	tile.custom_minimum_size = Vector2(40, 40)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon_rect("lan" if lan else "globe", COL_DIM, 20)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.add_child(ic)
	hb.add_child(tile)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(mid)
	var nl := _lbl(rname, FS_M + 1, COL_TEXT)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mid.add_child(nl)
	var sl := _lbl(sub, FS_S, COL_DIM)
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(sl)
	var cnt := _lbl(tr("1 Spieler") if players_n == 1 else tr("%d Spieler") % players_n, FS_S, COL_TEXT)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(cnt)
	var join := _lbl("Beitreten", FS_S, COL_DIM)
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(join)
	var chev := _icon_rect("next", COL_DIM)
	hb.add_child(chev)
	card.mouse_entered.connect(func():
		join.add_theme_color_override("font_color", COL_ACCENT)
		chev.modulate = COL_ACCENT)
	card.mouse_exited.connect(func():
		join.add_theme_color_override("font_color", COL_DIM)
		chev.modulate = COL_DIM)
	return card


func _refresh_rooms() -> void:
	if _rooms_list == null:
		return
	for c in _rooms_list.get_children():
		_rooms_list.remove_child(c)
		c.queue_free()
	# LAN-Raeume zuerst (schnellste Route); weltweite danach, ohne Dubletten
	# (gleicher Raum-Code ueber beide Wege).
	var lan_codes := {}
	var count := 0
	for ip in Lobby.lan_rooms:
		var r: Dictionary = Lobby.lan_rooms[ip]
		lan_codes[str(r.get("code", ""))] = true
		var target_ip := str(ip)
		_rooms_list.add_child(_room_card(true, str(r.name), int(r.players),
			tr("Dein Netzwerk"), func():
				if Lobby.join_lan(target_ip):
					_show_room()))
		count += 1
	for code in Lobby.online_rooms:
		if lan_codes.has(str(code)):
			continue
		var o: Dictionary = Lobby.online_rooms[code]
		var jcode := str(code)
		_rooms_list.add_child(_room_card(false, str(o.name), int(o.players),
			tr("Online  ·  %s") % jcode, func():
				if Lobby.join_code(jcode):
					_show_room()))
		count += 1
	var idx := 0
	for c in _rooms_list.get_children():
		_fade_in(c, idx)
		idx += 1
	if _rooms_count != null:
		_rooms_count.text = str(count) if count > 0 else ""
	if count == 0:
		# Leerer Zustand: ruhig, linksbuendig im Raster, mit klarer naechster Aktion.
		var empty := VBoxContainer.new()
		empty.set_meta("empty", true)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_constant_override("separation", 4)
		empty.add_child(_gap(8))
		empty.add_child(_lbl("Gerade ist es ruhig hier", FS_M + 1, COL_TEXT))
		var el := _lbl("Keine offenen Räume. Erstelle einen, er erscheint hier automatisch bei allen Spielern.", FS_S, COL_DIM)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(el)
		_rooms_list.add_child(empty)
		_fade_in(empty)
	_layout_rooms(_rooms_list.get_parent().size.x if _rooms_list.get_parent() is Control else 0.0)


# ---------------------------------------------------------------------------
# Raum
# ---------------------------------------------------------------------------

func _build_room() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", M)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.add_child(cols)

	# ---------------- Links: Raum-Panel ------------------------------------
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _panel_box())
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	left.add_child(lv)
	_room_title = _lbl("", FS_XL, COL_TEXT)
	_room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lv.add_child(_room_title)
	var code_row := HBoxContainer.new()
	code_row.custom_minimum_size = Vector2(0, 32)
	code_row.add_theme_constant_override("separation", 8)
	lv.add_child(code_row)
	_code_label = _lbl("", FS_M - 1, COL_DIM)
	_code_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(_code_label)
	_copy_btn = _btn("Kopieren", false, 28)
	_copy_btn.icon = _icon("copy")
	_copy_btn.add_theme_font_size_override("font_size", FS_S)
	_copy_btn.add_theme_color_override("icon_normal_color", COL_DIM)
	_copy_btn.add_theme_color_override("icon_hover_color", COL_TEXT)
	_copy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb: StyleBoxFlat = _copy_btn.get_theme_stylebox(st)
		sb.content_margin_left = 10
		sb.content_margin_right = 12
	_copy_btn.pressed.connect(_copy_code)
	code_row.add_child(_copy_btn)

	lv.add_child(_gap(16))
	# Raum-Modus: Frei / Teams / Battle Royale (waehlt die Krone, alle sehen ihn).
	_mode_row = HBoxContainer.new()
	_mode_row.custom_minimum_size = Vector2(0, 32)
	_mode_row.add_theme_constant_override("separation", 8)
	lv.add_child(_mode_row)
	for k in 3:
		var kb := _chip_toggle(Lobby.mode_name(k))
		var kind: int = k
		kb.pressed.connect(func():
			Lobby.set_room_mode(kind)
			_refresh_room())
		_mode_row.add_child(kb)
		_mode_btns.append(kb)
	var msp := Control.new()
	msp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_row.add_child(msp)
	_balance_btn = _btn("Auto-Ausgleich", false, 32)
	_balance_btn.add_theme_font_size_override("font_size", FS_S)
	_balance_btn.pressed.connect(func(): Lobby.auto_balance_teams())
	_mode_row.add_child(_balance_btn)
	lv.add_child(_gap(8))
	_mode_info = _lbl(" ", FS_S, COL_DIM)
	_mode_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lv.add_child(_mode_info)

	lv.add_child(_gap(16))
	lv.add_child(_sep())
	lv.add_child(_gap(16))
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	lv.add_child(ph)
	_players_headrow = ph
	_players_head = _caption("SPIELER IM RAUM")
	ph.add_child(_players_head)
	var psp := Control.new()
	psp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(psp)
	_ready_count = _caption("")
	ph.add_child(_ready_count)
	lv.add_child(_gap(8))

	_players_scroll = ScrollContainer.new()
	_players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(_players_scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 2)
	_players_scroll.add_child(_players_box)
	_board_holder = VBoxContainer.new()
	_board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_holder.visible = false
	lv.add_child(_board_holder)

	# ---------------- Rechts: Map-Karte -------------------------------------
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _panel_box(8))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	right.add_child(rv)
	# Cover als Held: abgerundete Maske (clip_children), Verlauf fuer den Titel.
	var mask := Panel.new()
	mask.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 1), 10))
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.self_modulate = Color(0.10, 0.11, 0.15, 1.0)
	mask.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mask.custom_minimum_size = Vector2(0, 160)
	rv.add_child(mask)
	_map_cover = TextureRect.new()
	_map_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(_map_cover)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0.03, 0.03, 0.05, 0.0), Color(0.03, 0.03, 0.05, 0.10), Color(0.03, 0.03, 0.05, 0.86)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	_map_shade = TextureRect.new()
	_map_shade.texture = gt
	_map_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_map_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(_map_shade)
	var over := VBoxContainer.new()
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	over.offset_left = M - 8
	over.offset_right = -(M - 8)
	over.offset_bottom = -(M - 8)
	over.alignment = BoxContainer.ALIGNMENT_END
	over.add_theme_constant_override("separation", 2)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(over)
	_map_empty = _lbl("Der Kronenträger wählt die Map.", FS_S, COL_DIM)
	_map_label = _lbl("Noch keine Map gewählt.", FS_XL, COL_TEXT)
	_map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_map_label.add_theme_constant_override("shadow_offset_y", 1)
	over.add_child(_map_label)
	_map_artist = _lbl("", FS_M, COL_TEXT.darkened(0.1))
	_map_artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_artist.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	over.add_child(_map_artist)
	over.add_child(_map_empty)

	var info := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		info.add_theme_constant_override(side, M - 8)
	info.add_theme_constant_override("margin_top", 16)
	info.add_theme_constant_override("margin_bottom", M - 8)
	rv.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	info.add_child(iv)
	# Diff-Zeile: Sterne-Pill in Sternfarbe (einziger Farbfleck), Diff-Name.
	var drow := HBoxContainer.new()
	drow.custom_minimum_size = Vector2(0, 28)
	drow.add_theme_constant_override("separation", 12)
	iv.add_child(drow)
	_map_drow = drow
	_star_pill = PanelContainer.new()
	_star_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drow.add_child(_star_pill)
	_star_label = _lbl("", FS_S, Color(0.05, 0.05, 0.08))
	_star_pill.add_child(_star_label)
	_map_meta = _lbl("", FS_M, COL_TEXT)
	_map_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_meta.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	drow.add_child(_map_meta)
	iv.add_child(_gap(8))
	_map_stats = _lbl(" ", FS_S, COL_DIM)
	_map_stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	iv.add_child(_map_stats)

	# Fehlt die Raum-Map: Status, "Map laden" (genau diese Set-ID), Fortschritt, Abbruch.
	_dl_row = HBoxContainer.new()
	_dl_row.custom_minimum_size = Vector2(0, ROW_H)
	_dl_row.add_theme_constant_override("separation", 12)
	_dl_row.visible = false
	iv.add_child(_dl_row)
	_dl_text = _lbl("Nicht in deiner Bibliothek", FS_S, COL_TEXT)
	_dl_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_row.add_child(_dl_text)
	_dl_bar = ProgressBar.new()
	_dl_bar.min_value = 0.0
	_dl_bar.max_value = 1.0
	_dl_bar.show_percentage = false
	_dl_bar.custom_minimum_size = Vector2(80, 6)
	_dl_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pbg := _box(Color(1, 1, 1, 0.08), 3)
	var pfill := _box(COL_ACCENT.darkened(0.1), 3)
	_dl_bar.add_theme_stylebox_override("background", pbg)
	_dl_bar.add_theme_stylebox_override("fill", pfill)
	_dl_row.add_child(_dl_bar)
	_dl_label = _lbl("", FS_S, COL_TEXT)
	_dl_label.custom_minimum_size = Vector2(40, 0)
	_dl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dl_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_row.add_child(_dl_label)
	_dl_cancel = _btn("Abbrechen", false, 32)
	_dl_cancel.add_theme_font_size_override("font_size", FS_S)
	_dl_cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_cancel.pressed.connect(_cancel_room_download)
	_dl_row.add_child(_dl_cancel)
	_dl_btn = _btn("Map laden", false, 32)
	_dl_btn.icon = _icon("down")
	_dl_btn.add_theme_font_size_override("font_size", FS_S)
	_dl_btn.add_theme_color_override("font_color", COL_ACCENT)
	_dl_btn.add_theme_color_override("icon_normal_color", COL_ACCENT)
	_dl_btn.add_theme_color_override("icon_hover_color", COL_ACCENT.lightened(0.2))
	_dl_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_btn.pressed.connect(_download_room_map)
	_dl_row.add_child(_dl_btn)

	iv.add_child(_gap(16))
	iv.add_child(_sep())
	iv.add_child(_gap(16))
	# Mods: Schalter wie im Song-Browser; nur der Kronentraeger schaltet.
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	iv.add_child(mrow)
	for k in ["NF", "SV"]:
		var mb := _mod_toggle("No-Fail" if k == "NF" else "SV",
			"Kein Abbruch bei leerer Lebensleiste" if k == "NF" else "Jede Map mit Tempowechseln")
		var key: String = k
		mb.toggled.connect(func(_on: bool):
			var nm: Dictionary = Lobby.mods.duplicate()
			nm[key] = not bool(nm.get(key, false))
			Lobby.pick_mods(nm)
			_refresh_room())
		mrow.add_child(mb)
		_mod_btns[k] = mb

	# ---------------- Aktionsleiste: alle Knoepfe gleich hoch ---------------
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, BAR_H)
	bar.add_theme_constant_override("separation", 8)
	_room_box.add_child(bar)
	_leave_btn = _btn("Verlassen")
	_leave_btn.custom_minimum_size.x = 168
	_leave_btn.pressed.connect(func():
		Lobby.leave()
		_show_browser())
	bar.add_child(_leave_btn)
	var bsp := Control.new()
	bsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(bsp)
	_tour_btn = _btn("Turnier")
	_tour_btn.custom_minimum_size.x = 168
	_tour_btn.pressed.connect(_on_tour_btn)
	bar.add_child(_tour_btn)
	_pick_btn = _btn("Map wählen")
	_pick_btn.custom_minimum_size.x = 168
	_pick_btn.pressed.connect(_open_picker)
	bar.add_child(_pick_btn)
	_start_btn = _btn("SPIELEN", true)
	_start_btn.custom_minimum_size.x = 264
	_start_btn.add_theme_font_size_override("font_size", FS_M + 1)
	_start_btn.pressed.connect(func(): Lobby.start_game())
	bar.add_child(_start_btn)


func _copy_code() -> void:
	if Lobby.room_code == "":
		return
	DisplayServer.clipboard_set(Lobby.room_code)
	_copy_btn.text = "Kopiert"
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(_copy_btn):
			_copy_btn.text = "Kopieren")


## Cover-Thumbnail der gewaehlten Map (null, wenn lokal nicht vorhanden).
func _map_cover_tex() -> Texture2D:
	var ms := _local_set()
	return ms.thumb_texture() if ms != null else null


## Lokales MapSet der Raum-Map (null = fehlt).
func _local_set() -> MapSet:
	var path := Lobby.resolve_local_path()
	if path == "":
		return null
	for ms in _library.mapsets:
		if ms.osz_path == path:
			return ms
	return null


func _show_room() -> void:
	Lobby.stop_discovery()
	_browser_box.visible = false
	_room_box.visible = true
	_seen_rows.clear()
	_refresh_room()


func _show_browser() -> void:
	_browser_box.visible = true
	_room_box.visible = false
	Lobby.start_discovery()
	_refresh_rooms()


## Eine Spielerzeile: Avatar, Krone, Name, (Score), Bereit-Status, Krone geben.
func _player_row(id: int, p: Dictionary, my_id: int, in_round: bool) -> Control:
	var is_crown: bool = id == Lobby.crown_id
	var row := PanelContainer.new()
	var n := _box(Color(1, 1, 1, 0.035), 8)
	n.content_margin_left = 8
	n.content_margin_right = 8
	var hv: StyleBoxFlat = n.duplicate()
	hv.bg_color = Color(1, 1, 1, 0.07)
	row.add_theme_stylebox_override("panel", n)
	row.custom_minimum_size = Vector2(0, PROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# Lambdas fangen Locals beim Erzeugen ein: Knopf ueber Meta holen, er entsteht erst unten.
	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", hv)
		var g: Button = row.get_meta("give", null)
		if g != null:
			g.modulate.a = 1.0)
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", n)
		# Knopf bleibt sichtbar, solange die Maus auf ihm steht (Kind der Zeile).
		var g: Button = row.get_meta("give", null)
		if g != null and not g.get_global_rect().has_point(g.get_global_mouse_position()):
			g.modulate.a = 0.0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	hb.add_child(_avatar(str(p.name), 24))
	var name_box := HBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 8)
	hb.add_child(name_box)
	var name_l := _lbl(str(p.name), FS_M, COL_TEXT)
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Breite = Textbreite (max. 60 % der Zeile), Krone/(du) folgen direkt dahinter.
	var tw := name_l.get_theme_font("font").get_string_size(str(p.name), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
	name_l.custom_minimum_size.x = minf(ceilf(tw) + 2.0, maxf(_players_scroll.size.x * 0.6, 160.0))
	name_box.add_child(name_l)
	if is_crown:
		var cr := _icon_rect("crown", COL_GOLD)
		cr.tooltip_text = "Kronenträger: wählt die Map und startet"
		cr.mouse_filter = Control.MOUSE_FILTER_PASS
		name_box.add_child(cr)
	if id == my_id:
		var you := _lbl("(du)", FS_S, COL_DIM)
		you.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_box.add_child(you)
	name_l.size_flags_horizontal = Control.SIZE_FILL
	var nsp := Control.new()
	nsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(nsp)
	if in_round:
		var sc := _lbl("%s  ·  %s  ·  %dx" % [
			UiTheme.fmt_score(int(p.get("score", 0))),
			UiTheme.fmt_num(float(p.get("acc", 0.0)) * 100.0, 1) + " %", int(p.get("combo", 0))],
			FS_S, COL_TEXT)
		sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(sc)
	var st := HBoxContainer.new()
	st.custom_minimum_size = Vector2(88, 0)
	st.add_theme_constant_override("separation", 8)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ready := bool(p.ready)
	st.add_child(_dot(COL_READY if ready else Color(COL_DIM, 0.5)))
	var stl := _lbl("Bereit" if ready else "Wartet", FS_S, COL_READY if ready else COL_DIM)
	stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_child(stl)
	hb.add_child(st)
	# Krone geben: nur der Kronentraeger, fester Platz fuer gleiche Kanten.
	if Lobby.crown_id == my_id:
		if not is_crown:
			var give := _icon_btn(_icon("crown"), tr("%s geben") % tr("Krone"), 28)
			row.set_meta("give", give)
			give.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Nur beim Hover der Zeile sichtbar: keine Reihe gleicher Icons.
			give.modulate.a = 0.0
			give.mouse_entered.connect(func(): give.modulate.a = 1.0)
			var target := int(id)
			give.pressed.connect(func(): Lobby.give_crown(target))
			hb.add_child(give)
		else:
			var slot := Control.new()
			slot.custom_minimum_size = Vector2(28, 28)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(slot)
	return row


func _refresh_room() -> void:
	if not _room_box.visible or _players_box == null:
		return
	_room_title.text = Lobby.room_name if Lobby.room_name != "" else tr("Raum")
	var has_code := Lobby.room_code != ""
	_code_label.text = (tr("Code  %s") % Lobby.room_code) if has_code else tr("Nur im eigenen Netzwerk")
	_copy_btn.visible = has_code
	for c in _players_box.get_children():
		_players_box.remove_child(c)
		c.queue_free()
	var my_id := multiplayer.get_unique_id()
	_refresh_mode(my_id)
	var in_round := false
	var n_ready := 0
	for id in Lobby.players:
		if int(Lobby.players[id].get("score", 0)) > 0:
			in_round = true
		if bool(Lobby.players[id].get("ready", false)):
			n_ready += 1
	_ready_count.text = tr("%d / %d bereit") % [n_ready, Lobby.players.size()]
	var row_i := 0
	for id in Lobby.players:
		if Lobby.room_kind() != MatchMode.Kind.FREE:
			break  # Teams/Royale: die Tafel ersetzt die Spielerliste
		var row := _player_row(int(id), Lobby.players[id], my_id, in_round)
		_players_box.add_child(row)
		if not _seen_rows.has(id):
			_seen_rows[id] = true
			_fade_in(row, row_i)
			row_i += 1
	# Map-Karte.
	var has_map := not Lobby.sel_map.is_empty()
	_map_empty.visible = not has_map
	_star_pill.visible = has_map
	_map_drow.visible = has_map
	if has_map:
		_map_label.text = str(Lobby.sel_map.get("title", ""))
		_map_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_map_artist.text = str(Lobby.sel_map.get("artist", ""))
		_map_artist.visible = true
		var stars := float(Lobby.sel_map.get("stars", 0.0))
		var pill := _box(MapPicker.star_color(stars), 8)
		pill.content_margin_left = 10
		pill.content_margin_right = 10
		pill.content_margin_top = 2
		pill.content_margin_bottom = 2
		_star_pill.add_theme_stylebox_override("panel", pill)
		_star_label.text = "★ " + UiTheme.fmt_num(stars, 2)
		_star_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08) if stars < 6.5 else Color(0.95, 0.95, 1.0))
		_fill_map_meta()
	else:
		_map_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
		_map_label.text = "Noch keine Map gewählt."
		_map_artist.visible = false
		_map_meta.text = ""
		_map_stats.text = " "
		_map_cover.texture = null
		_map_empty.text = "Wähle eine Map mit „Map wählen“." if Lobby.crown_id == my_id \
			else "Der Kronenträger wählt die Map."
	_map_shade.visible = _map_cover.texture != null or has_map
	var is_crown := Lobby.crown_id == my_id
	for k in _mod_btns:
		var mb: CheckButton = _mod_btns[k]
		mb.set_pressed_no_signal(bool(Lobby.mods.get(k, false)))
		mb.disabled = not is_crown
		mb.tooltip_text = (tr("Kein Abbruch bei leerer Lebensleiste") if k == "NF" else tr("Jede Map mit Tempowechseln")) \
			+ ("" if is_crown else "\n" + tr("Nur der Kronenträger schaltet Mods."))
	var in_tour := Lobby.tournament != null
	for k in _mode_btns.size():
		var kb: Button = _mode_btns[k]
		var on: bool = Lobby.room_kind() == k and not in_tour
		kb.set_pressed_no_signal(on)
		_paint_chip(kb, on)
		kb.disabled = not is_crown or in_tour or Lobby.in_game
		kb.visible = not in_tour
	_pick_btn.visible = is_crown and not in_tour
	# Primaer-Slot: Krone startet; alle anderen sehen ihren Zustand (nicht klickbar).
	_start_btn.visible = not in_tour
	if is_crown:
		_start_btn.text = "SPIELEN"
		_start_btn.disabled = not Lobby.can_start()
		var why := Lobby.mode_blocker()
		if Lobby.sel_map.is_empty():
			why = tr("Noch keine Map gewählt.")
		elif why == "" and not Lobby.all_ready():
			why = tr("Noch nicht alle sind bereit.")
		_start_btn.tooltip_text = why
		_start_btn.add_theme_color_override("font_disabled_color", Color(COL_DIM, 0.7))
	else:
		var me_ready := Lobby.players.has(my_id) and bool(Lobby.players[my_id].get("ready", false))
		_start_btn.text = "BEREIT" if me_ready else ("MAP LÄDT" if _downloading else "NICHT BEREIT")
		_start_btn.disabled = true
		_start_btn.tooltip_text = tr("Der Kronenträger startet die Runde.")
		_start_btn.add_theme_color_override("font_disabled_color", COL_READY if me_ready else Color(COL_DIM, 0.8))
	if _tour_btn != null:
		_tour_btn.visible = in_tour or Lobby.is_host
		_tour_btn.text = "Zum Turnier" if in_tour else "Turnier"
	_refresh_dl_ui()


## Diff, Tasten, BPM, Laenge, Noten der Raum-Map (nur lokal bekannt).
func _fill_map_meta() -> void:
	var version := str(Lobby.sel_map.get("version", "")).strip_edges()
	var ms := _local_set()
	if ms == null:
		_map_meta.text = version
		_map_stats.text = " "
		return
	var di := 0
	for i in ms.difficulty_count():
		if ms.version_name_at(i) == str(Lobby.sel_map.get("version", "")):
			di = i
			break
	var m: Dictionary = ms.meta_at(di)
	var mania := int(m.get("mode", 3)) == 3
	_map_meta.text = version + (("  ·  %dK" % int(round(float(m.get("cs", 4.0))))) if mania else "")
	var parts: Array = []
	var bpm := _bpm_text(ms, di)
	if bpm != "":
		parts.append(bpm + " BPM")
	var sec := int(float(m.get("duration_ms", 0.0)) / 1000.0)
	if sec > 0:
		parts.append("%d:%02d" % [sec / 60, sec % 60])
	if int(m.get("notes", 0)) > 0:
		parts.append(tr("%d Noten") % int(m.get("notes", 0)))
	if ms.creator != "":
		parts.append(tr("Map von %s") % ms.creator)
	_map_stats.text = "  ·  ".join(parts) if not parts.is_empty() else " "


## BPM (bzw. Bereich) aus den roten Timing-Linien, gecacht.
func _bpm_text(ms: MapSet, diff: int) -> String:
	var key := ms.osz_path + "|" + ms.osu_filename_at(diff)
	if _bpm_cache.has(key):
		return str(_bpm_cache[key])
	var lo := INF
	var hi := 0.0
	var bytes := OszImporter.read_file_bytes(ms.osz_path, ms.osu_filename_at(diff))
	var in_tp := false
	for raw in bytes.get_string_from_utf8().split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			if in_tp:
				break
			in_tp = line == "[TimingPoints]"
			continue
		if not in_tp or line == "":
			continue
		var tp := OsuParser._parse_timing_line(line)
		if tp != null and tp.uninherited and tp.beat_length > 0.0:
			var b: float = 60000.0 / tp.beat_length
			lo = minf(lo, b)
			hi = maxf(hi, b)
	var txt := ""
	if hi > 0.0:
		txt = ("%d" % roundi(hi)) if roundi(lo) == roundi(hi) else "%d–%d" % [roundi(lo), roundi(hi)]
	_bpm_cache[key] = txt
	return txt


## Teams-/Royale-Tafel statt Spielerliste; Info-Zeile mit Serienstand oder Startgrund.
func _refresh_mode(my_id: int) -> void:
	var kind := Lobby.room_kind()
	var mm: MatchMode = Lobby.mm
	_players_scroll.visible = kind == MatchMode.Kind.FREE
	_board_holder.visible = kind != MatchMode.Kind.FREE
	# RoyaleBoard bringt eine eigene Kopfzeile mit (Runde, noch dabei).
	_players_headrow.visible = kind != MatchMode.Kind.ROYALE
	_players_head.text = "SPIELER IM RAUM" if kind == MatchMode.Kind.FREE else ("TEAMS" if kind == MatchMode.Kind.TEAMS else "BATTLE ROYALE")
	_balance_btn.visible = kind == MatchMode.Kind.TEAMS and Lobby.crown_id == my_id \
			and not Lobby.in_game and Lobby.tournament == null
	var info := tr("Jeder für sich — der höchste Score gewinnt.")
	if Lobby.tournament != null:
		info = tr("Turnier läuft — Modus ist fest.")
	var live := Lobby.live_results() if Lobby.in_game else []
	if kind == MatchMode.Kind.TEAMS:
		if _team_board == null:
			_team_board = TeamBoard.new()
			_team_board.custom_minimum_size = Vector2(1, 200)
			_team_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_team_board.team_requested.connect(func(peer: int, team: int): Lobby.set_team(peer, team))
			_board_holder.add_child(_team_board)
		var plist: Array = []
		for id in mm.order:
			if Lobby.players.has(id):
				plist.append({ "peer": id, "name": str(Lobby.players[id].name),
					"team": int(mm.team_of.get(id, 0)),
					"score": int(Lobby.players[id].get("score", 0)) if Lobby.in_game else 0 })
		_team_board.visible = true
		_team_board.setup({ "names": mm.team_names, "players": plist,
			"totals": mm.team_totals(live) if Lobby.in_game \
				else (mm.history.back().totals if not mm.history.is_empty() else [0, 0]),
			"hint": mm.balance_hint(), "editable": not Lobby.in_game })
		if _royale_board != null:
			_royale_board.visible = false
		info = tr("Teams %s  ·  %s") % [mm.format_label(), mm.series_label()]
		if mm.rounds_played > 0:
			info = "%s %s : %s %s  ·  %s" % [tr(mm.team_names[0]), mm.team_wins[0],
				mm.team_wins[1], tr(mm.team_names[1]), mm.series_label()]
		if mm.series_over():
			info = tr("Endstand %s %s : %s %s — %s") % [tr(mm.team_names[0]), mm.team_wins[0],
				mm.team_wins[1], tr(mm.team_names[1]), _series_winner_name(mm)]
	elif kind == MatchMode.Kind.ROYALE:
		if _royale_board == null:
			_royale_board = RoyaleBoard.new()
			_royale_board.custom_minimum_size = Vector2(1, 200)
			_royale_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_board_holder.add_child(_royale_board)
		var rl: Array = []
		for id in mm.order:
			if Lobby.players.has(id) and mm.players.has(id):
				rl.append({ "peer": id, "name": str(Lobby.players[id].name),
					"alive": bool(mm.players[id].alive), "out_round": int(mm.players[id].out_round),
					"score": int(Lobby.players[id].get("score", 0)) if Lobby.in_game else 0 })
		_royale_board.visible = true
		_royale_board.setup({ "round": mm.round_no, "players": rl,
			"danger": mm.in_danger(live) if Lobby.in_game else -1,
			"final": mm.is_final(), "winner": mm.winner_peer })
		if _team_board != null:
			_team_board.visible = false
		# Runde und "noch dabei" zeigt die Tafel selbst: hier nur die Regel.
		info = tr("Jede Runde scheidet der niedrigste Score aus.")
		if mm.is_over() and Lobby.players.has(mm.winner_peer):
			info = tr("Sieger: %s") % str(Lobby.players[mm.winner_peer].name)
		elif Lobby.spectating and Lobby.in_game:
			info = tr("Du bist ausgeschieden — du schaust zu.")
	if Lobby.crown_id == my_id and Lobby.tournament == null and not Lobby.in_game:
		var why := Lobby.mode_blocker()
		if why != "":
			info = why
	_mode_info.text = info
	_mode_info.tooltip_text = info


func _series_winner_name(mm: MatchMode) -> String:
	var w := mm.series_winner()
	return tr(mm.team_names[w]) if w >= 0 else tr("unentschieden")


## Download-Zeile der Map-Karte: nur sichtbar, wenn die Raum-Map lokal fehlt.
func _refresh_dl_ui() -> void:
	if _dl_row == null:
		return
	var missing := not Lobby.sel_map.is_empty() and Lobby.resolve_local_path() == ""
	_dl_row.visible = missing
	_map_stats.visible = not missing and not Lobby.sel_map.is_empty()
	if not missing:
		return
	var set_id := int(Lobby.sel_map.get("set_id", 0))
	_dl_text.text = "Wird geladen" if _downloading else "Nicht in deiner Bibliothek"
	_dl_bar.visible = _downloading
	_dl_label.visible = _downloading
	_dl_cancel.visible = _downloading
	_dl_btn.visible = not _downloading
	_dl_btn.disabled = set_id <= 0
	_dl_btn.tooltip_text = tr("Set %d vom Mirror laden") % set_id if set_id > 0 \
			else "Diese Map hat keine Set-ID — Download nicht möglich."
	# Ohne Download-Balken fuellt ein Platzhalter, damit der Knopf rechts steht.
	if not _downloading:
		_dl_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_dl_text.size_flags_horizontal = Control.SIZE_FILL


# ---------------------------------------------------------------------------
# Map-Wahl (Kronentraeger) + Auto-Download
# ---------------------------------------------------------------------------

## Map-Picker im Stil des Song-Browsers (scripts/ui/map_picker.gd): Suche,
## Sortierung, Sterne-Filter, eigene Bestwerte je Diff, Online-Tab.
## Bleibt nach dem ersten Oeffnen versteckt am Leben (Cover-Cache, Scroll).
func _open_picker() -> void:
	if Lobby.crown_id != multiplayer.get_unique_id() and Lobby.active:
		return
	if _picker == null:
		_picker = MapPicker.new(_library)
		_picker.visible = false
		_picker.played_fn = func(file: String, version: String) -> bool:
			return Lobby.was_played(file, version)
		add_child(_picker)
		_picker.picked.connect(func(ms: MapSet, diff: int):
			_pick(ms, diff)
			_picker.close())
		_picker.set_selected.connect(func(ms: MapSet):
			if ms.difficulty_count() > 0:
				_play_set_preview(ms.osz_path, ms.meta_at(0)))
		_picker.preview_stream.connect(func(st: AudioStream):
			if _preview_fade != null and _preview_fade.is_valid():
				_preview_fade.kill()
			_preview.stream = st
			_preview.volume_db = -14.0
			_preview.play())
		_picker.preview_stop.connect(func(): _preview.stop())
		_picker.closed.connect(_update_preview)
	_picker.can_pick = not Lobby.active or Lobby.crown_id == multiplayer.get_unique_id()
	_picker.open()


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
	# Map-Karte zeigt dasselbe Cover scharf (fehlt die Map: dunkle Flaeche).
	_map_tex = tex
	if _map_cover != null:
		_map_cover.texture = tex
		_map_shade.visible = tex != null or not Lobby.sel_map.is_empty()
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
	# Fehlt: automatisch laden (Knopf "Map laden" bleibt fuer Abbruch/Fehler).
	_download_room_map()


## Genau die Set-ID der Raum-Map laden; danach automatisch bereit.
func _download_room_map() -> void:
	var set_id := int(Lobby.sel_map.get("set_id", 0))
	if set_id <= 0:
		_status_label.text = "Map fehlt und hat keine Set-ID — Download nicht möglich."
		_refresh_dl_ui()
		return
	if _downloading and _dl_set == set_id:
		return  # derselbe Download laeuft schon
	if _downloading and _dl_set != set_id:
		_mirror.cancel_download(_dl_set)  # alte Raum-Map wird nicht mehr gebraucht
	_downloading = true
	_dl_set = set_id
	_dl_bar.value = 0.0
	_dl_label.text = "0 %"
	_status_label.text = "Map fehlt — lade herunter…"
	_refresh_dl_ui()
	if not _mirror.is_downloading(set_id):
		_mirror.download(set_id, _library.maps_dir)


func _cancel_room_download() -> void:
	if _downloading:
		_mirror.cancel_download(_dl_set)


func _on_dl_progress(id: int, ratio: float) -> void:
	# Der Mirror ist global — nur auf den Download der Raum-Map reagieren.
	if _downloading and id == _dl_set:
		_dl_bar.value = ratio
		_dl_label.text = "%d %%" % int(ratio * 100.0)
		_status_label.text = tr("Lade Map… %d %%") % int(ratio * 100.0)


func _on_dl_done(id: int, _path: String) -> void:
	if id == _dl_set:
		_downloading = false
	if id != int(Lobby.sel_map.get("set_id", 0)):
		return
	_library.scan()
	if _picker != null and _picker.is_open():
		_picker.reload()
	if Lobby.resolve_local_path() != "":
		_status_label.text = "Map heruntergeladen — bereit!"
		Lobby.set_ready(true)
	_refresh_room()
	_update_bg()
	_update_preview()


func _on_dl_failed(id: int, message: String) -> void:
	if id != _dl_set:
		return
	_downloading = false
	_status_label.text = tr("Download fehlgeschlagen: %s") % message
	_refresh_dl_ui()


func _on_dl_cancelled(id: int) -> void:
	if id != _dl_set or not _downloading:
		return
	_downloading = false
	_status_label.text = "Download abgebrochen — „Map laden“ startet ihn neu."
	_refresh_dl_ui()


func _back() -> void:
	if not Lobby.active:
		Lobby.stop_discovery()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()


# ---------------------------------------------------------------------------
# Turnier: Setup-Dialog, Phasen-Ansicht, Endbild
# ---------------------------------------------------------------------------

func _on_tour_btn() -> void:
	if Lobby.tournament != null:
		_tour_hidden = false
		_sync_tournament()
	elif Lobby.is_host:
		_open_tour_setup()


## Host: Anzahl Maps (5/10/15), Sternbereich exakt (eintippen oder 0,1er-Schritte), Mods.
func _open_tour_setup() -> void:
	if _tour_dialog != null:
		return
	# Zustand im Dictionary: Lambdas kopieren lokale int/float-Werte, Aenderungen gingen sonst verloren.
	var st: Dictionary = {"maps": 10, "lo": 2.0, "hi": 5.0}
	var mods: Dictionary = {"SV": bool(Lobby.mods.get("SV", false)), "NF": bool(Lobby.mods.get("NF", false))}
	var back := UiTheme.modal_backdrop(self)
	_tour_dialog = back
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.95)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var close_dialog := func():
		back.queue_free()
		_tour_dialog = null
	v.add_child(UiTheme.modal_header("Turnier erstellen", close_dialog))
	v.add_child(TournamentPanel.lbl("ANZAHL MAPS", 13, COL_ACCENT, true))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	v.add_child(chips)
	var chip_btns: Dictionary = {}
	for n in [5, 10, 15]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = str(n)
		b.custom_minimum_size = Vector2(110, 44)
		UiTheme.style_button(b)
		var nn: int = n
		b.pressed.connect(func():
			st.maps = nn
			for k in chip_btns:
				(chip_btns[k] as Button).set_pressed_no_signal(k == nn))
		b.set_pressed_no_signal(n == st.maps)
		chips.add_child(b)
		chip_btns[n] = b
	v.add_child(TournamentPanel.lbl("SCHWIERIGKEIT (STERNE)", 13, COL_ACCENT, true))
	# Werte direkt eintippbar (z. B. "4,37"), -/+ fuer 0,1er-Schritte.
	var val_lo := LineEdit.new()
	var val_hi := LineEdit.new()
	var fmt_star := func(x: float) -> String:
		return UiTheme.fmt_num(x, 1 if is_equal_approx(snappedf(x, 0.1), x) else 2)
	var upd := func():
		val_lo.text = fmt_star.call(st.lo)
		val_hi.text = fmt_star.call(st.hi)
	for pair in [["Min", val_lo, true], ["Max", val_hi, false]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var cap := TournamentPanel.lbl(pair[0], 16, COL_DIM)
		cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cap.custom_minimum_size.x = 50
		row.add_child(cap)
		var is_lo: bool = pair[2]
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(48, 40)
		UiTheme.style_button(minus)
		row.add_child(minus)
		var star := TournamentPanel.lbl("★", 20, COL_TEXT)
		row.add_child(star)
		var vl: LineEdit = pair[1]
		vl.custom_minimum_size = Vector2(84, 40)
		vl.alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.max_length = 5
		vl.select_all_on_focus = true
		vl.add_theme_font_size_override("font_size", 20)
		vl.add_theme_color_override("font_color", COL_TEXT)
		row.add_child(vl)
		var commit := func():
			var txt := vl.text.replace(",", ".").replace("★", "").strip_edges()
			if txt.is_valid_float():
				var f := snappedf(clampf(txt.to_float(), 0.0, 15.0), 0.01)
				if is_lo:
					st.lo = f
					st.hi = maxf(st.hi, st.lo)
				else:
					st.hi = f
					st.lo = minf(st.lo, st.hi)
			upd.call()
		vl.text_submitted.connect(func(_x):
			commit.call()
			vl.release_focus())
		vl.focus_exited.connect(commit)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(48, 40)
		UiTheme.style_button(plus)
		row.add_child(plus)
		var step := func(d: float):
			if is_lo:
				st.lo = snappedf(clampf(st.lo + d, 0.0, 15.0), 0.1)
				st.hi = maxf(st.hi, st.lo)
			else:
				st.hi = snappedf(clampf(st.hi + d, 0.0, 15.0), 0.1)
				st.lo = minf(st.lo, st.hi)
			upd.call()
		# 0,1er-Schritte; gedrueckt halten = schnell weiterzaehlen.
		for pb in [[minus, -0.1], [plus, 0.1]]:
			var btn: Button = pb[0]
			var dd: float = pb[1]
			var rep := Timer.new()
			btn.add_child(rep)
			rep.timeout.connect(func():
				step.call(dd)
				rep.wait_time = 0.06)
			btn.button_down.connect(func():
				step.call(dd)
				rep.wait_time = 0.4
				rep.start())
			btn.button_up.connect(func(): rep.stop())
	upd.call()
	v.add_child(TournamentPanel.lbl("MODS", 13, COL_ACCENT, true))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	v.add_child(mrow)
	for k in ["NF", "SV"]:
		var mb := _mod_toggle("No-Fail" if k == "NF" else "SV",
			"Kein Abbruch bei leerer Lebensleiste" if k == "NF" else "Jede Map mit Tempowechseln")
		mb.custom_minimum_size.x = 160
		mb.size_flags_horizontal = Control.SIZE_FILL
		var key: String = k
		mb.set_pressed_no_signal(bool(mods[key]))
		mb.toggled.connect(func(on: bool): mods[key] = on)
		mrow.add_child(mb)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var cancel := Button.new()
	cancel.text = "Abbrechen"
	cancel.custom_minimum_size = Vector2(130, 46)
	UiTheme.style_button(cancel)
	cancel.pressed.connect(close_dialog)
	bar.add_child(cancel)
	var go := Button.new()
	go.text = "Turnier erstellen"
	go.custom_minimum_size = Vector2(200, 46)
	UiTheme.style_button(go, true)
	go.pressed.connect(func():
		Lobby.tour_create({"maps": st.maps, "stars_lo": st.lo, "stars_hi": st.hi, "mods": mods.duplicate()})
		close_dialog.call())
	bar.add_child(go)


## Passende Ansicht zum Turnier-Zustand zeigen (oder zurueck zum Raum).
func _sync_tournament() -> void:
	var t: Tournament = Lobby.tournament
	if t == null:
		_tour_phase = -1
		_tour_hidden = false
		_clear_tour_views()
		if _center != null:
			_center.visible = true
		_refresh_room()
		return
	if t.phase != _tour_phase:
		_tour_hidden = false
	_tour_phase = t.phase
	if _tour_hidden:
		_clear_tour_views()
		if _center != null:
			_center.visible = true
		_refresh_room()
		return
	if _tour_dialog != null:
		_tour_dialog.queue_free()
		_tour_dialog = null
	_center.visible = false
	if t.phase == Tournament.Phase.END:
		if _tpanel != null:
			_tpanel.queue_free()
			_tpanel = null
		if _tend == null:
			_tend = TournamentEnd.new(t, _tour_title())
			_tend.my_id = multiplayer.get_unique_id()
			_tend.is_host = Lobby.is_host
			_tend.back_to_room.connect(_leave_tour_view)
			add_child(_tend)
		return
	if _tend != null:
		_tend.queue_free()
		_tend = null
	if _tpanel == null:
		_tpanel = TournamentPanel.new(_library)
		_tpanel.back_to_room.connect(_leave_tour_view)
		add_child(_tpanel)
	_tpanel.sync_from_lobby()


func _tour_title() -> String:
	return (tr("Turnier · %s") % Lobby.room_name) if Lobby.room_name != "" else tr("Turnier")


func _leave_tour_view() -> void:
	_tour_hidden = true
	_sync_tournament()


func _clear_tour_views() -> void:
	if _tpanel != null:
		_tpanel.queue_free()
		_tpanel = null
	if _tend != null:
		_tend.queue_free()
		_tend = null


## Fake-Turnier fuer die Screenshots (ueberschreibt nur die Auswertung).
class _FakeTournament extends Tournament:
	var fake_stand: Array = []
	var fake_wins: Array = []

	func standings() -> Array:
		return fake_stand

	func map_winners() -> Array:
		return fake_wins

	func play_order() -> Array[int]:
		var o: Array[int] = []
		for i in order:
			o.append(int(i))
		return o


## Screenshots aller Turnier-Phasen mit Fake-Daten + Endbild (1920x1080).
## Ziel: --shot-out=<Praefix> (sonst user://tournament).
func _tournament_shots() -> void:
	var out := ProjectSettings.globalize_path("user://tournament")
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			out = a.substr(11)
	var shot := func(tag: String):
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [out, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT " + path)
	await get_tree().create_timer(0.6).timeout
	_center.visible = false
	var who := ["Aria", "Kenji", "Mara", "Tobi", "Lena"]
	var names := {}
	for i in who.size():
		names[i + 2] = who[i]
	var t := _FakeTournament.new()
	t.config = {"maps": 10, "stars_lo": 3.0, "stars_hi": 5.0, "mods": {"SV": true, "NF": false}}
	t.player_names = names
	var titles := ["Neon Skyline", "Gravity Bloom", "Echoes of Tomorrow", "Paper Planes",
		"Nightdrive", "Crystal Rain", "Last Light", "Pulse Garden", "Afterglow", "Zero Hour"]
	var arts := ["Kairo", "Lumen", "Velvet Static", "Mio", "Driftwood", "Aoi", "Halo Park", "Sora", "Nova", "Eclipse"]
	var versions := ["Insane", "Another", "4K Hard", "Expert", "Lv. 18", "Master", "Hyper", "Heavy", "Light", "Stage"]
	var sets: Array = _library.mapsets.duplicate()
	for i in 10:
		var m := {"set_id": 900000 + i, "file": "", "version": versions[i],
			"title": titles[i], "artist": arts[i], "stars": 3.1 + i * 0.19,
			"by": 2 + (i % 5), "online": false, "banned": false}
		if i < sets.size() and i < 8:
			var ms: MapSet = sets[i]
			m["file"] = ms.osz_path.get_file()
			m["title"] = ms.title
			m["artist"] = ms.artist
			if ms.difficulty_count() > 0:
				m["version"] = ms.version_name_at(0)
		if i >= 8:
			m["online"] = true
		t.pool.append(m)
	var panel := TournamentPanel.new(_library)
	panel.harness = true
	panel.names = names
	panel.my_id = 3
	panel.is_host = true
	panel.t = t
	add_child(panel)
	# PICK: 8 von 10 Maps, zwei laden noch.
	t.phase = Tournament.Phase.PICK
	var full_pool: Array = t.pool.duplicate()
	t.pool = full_pool.slice(0, 8)
	t.pool[6]["file"] = ""
	t.pool[6]["online"] = true
	panel.refresh()
	panel._on_dl_progress(900006, 0.42)
	await get_tree().create_timer(1.2).timeout
	await shot.call("pick")
	# BAN: nur Teilstimmen sichtbar.
	t.pool = full_pool
	t.phase = Tournament.Phase.BAN
	t.bans = {2: 4, 3: 1, 4: -1, 5: 4, 6: -1}
	panel.refresh()
	await get_tree().create_timer(1.0).timeout
	await shot.call("ban")
	# BAN: alle gewaehlt -> Aufdecken + Reihenfolge.
	t.bans = {2: 4, 3: 1, 4: 7, 5: 4, 6: 1}
	for i in [1, 4, 7]:
		t.pool[i]["banned"] = true
	t.order = [0, 2, 3, 5, 6, 8, 9]
	panel._reveal_played = false
	panel.refresh()
	await get_tree().create_timer(3.4).timeout
	await shot.call("ban_reveal")
	# BETWEEN: nach Runde 3.
	t.phase = Tournament.Phase.BETWEEN
	t.rounds = []
	for r in 3:
		var res := {}
		for k in 5:
			res[k + 2] = {"score": 930000 - ((k + r * 2) % 5) * 41000 - r * 7000,
				"accuracy": 0.985 - ((k + r * 2) % 5) * 0.021, "max_combo": 400 + k * 30,
				"failed": r == 1 and k == 4, "name": who[k]}
		t.rounds.append({"map": [0, 2, 3][r], "results": res})
	t.fake_stand = [
		{"peer": 3, "name": "Kenji", "points": 14, "wins": 2, "avg_acc": 0.974, "total_score": 2711000, "rank": 1},
		{"peer": 2, "name": "Aria", "points": 12, "wins": 1, "avg_acc": 0.962, "total_score": 2650000, "rank": 2},
		{"peer": 5, "name": "Tobi", "points": 9, "wins": 0, "avg_acc": 0.951, "total_score": 2512000, "rank": 3},
		{"peer": 4, "name": "Mara", "points": 8, "wins": 0, "avg_acc": 0.948, "total_score": 2480000, "rank": 4},
		{"peer": 6, "name": "Lena", "points": 4, "wins": 0, "avg_acc": 0.910, "total_score": 2210000, "rank": 5},
	]
	panel.refresh()
	await get_tree().create_timer(1.0).timeout
	await shot.call("between")
	# END: Endbild.
	t.phase = Tournament.Phase.END
	t.order = [0, 2, 3, 5, 6, 8, 9, 1, 4, 7]
	t.fake_wins = []
	var wnames := ["Kenji", "Aria", "Kenji", "Tobi", "Mara", "Aria", "Lena", "Kenji", "Tobi", "Aria"]
	for i in 10:
		t.fake_wins.append({"map": t.pool[t.order[i]], "winner_name": wnames[i], "score": 900000 - i * 3000})
	panel.queue_free()
	var end := TournamentEnd.new(t, tr("Turnier · %s") % "Freitagsrunde")
	end.harness = true
	end.my_id = 3
	add_child(end)
	await get_tree().create_timer(1.6).timeout
	await shot.call("end")
	var img_path := end.save_png("%s_end_image.png" % out)
	print("END-BILD " + img_path)
	# Erstell-Dialog: exakter Sternwert per Eingabe.
	end.queue_free()
	_open_tour_setup()
	var edits := _tour_dialog.find_children("*", "LineEdit", true, false)
	if edits.size() >= 2:
		(edits[0] as LineEdit).text = "4,37"
		(edits[0] as LineEdit).text_submitted.emit("4,37")
		(edits[1] as LineEdit).text = "6.8"
		(edits[1] as LineEdit).text_submitted.emit("6.8")
	await get_tree().create_timer(0.6).timeout
	await shot.call("setup")
	get_tree().quit(0)


## Screenshots der Raum-Modi mit Fake-Raum: Teams, Teams im Spiel, Royale, Royale-Ende.
## Ziel: --shot-out=<Praefix> (sonst user://modes).
func _mode_shots() -> void:
	var out := ProjectSettings.globalize_path("user://modes")
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			out = a.substr(11)
	var shot := func(tag: String):
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [out, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT " + path)
	await get_tree().create_timer(0.6).timeout
	var who := ["Kenji", "Aria", "Mara", "Tobi", "Lena"]
	Lobby.active = true
	Lobby.is_host = true
	Lobby.crown_id = 1
	Lobby.room_name = "Freitagsrunde"
	Lobby.players = {}
	for i in who.size():
		Lobby.players[i + 1] = Lobby._new_player(who[i])
		Lobby.players[i + 1].ready = true
	Lobby.sel_map = {"set_id": 1, "file": "", "version": "Insane", "title": "Neon Skyline",
		"artist": "Kairo", "stars": 4.2}
	Lobby.mm = MatchMode.new(MatchMode.Kind.TEAMS)
	for i in 4:
		Lobby.mm.add_player(i + 1)
	_show_room()
	await shot.call("teams")
	# Teams im Spiel: Live-Summen.
	Lobby.in_game = true
	var sc := [812000, 744000, 698000, 655000]
	for i in 4:
		Lobby.players[i + 1].score = sc[i]
	Lobby.players_changed.emit()
	await shot.call("teams_live")
	Lobby.in_game = false
	Lobby.mm.finish_team_round(Lobby.live_results())
	Lobby.mm.finish_team_round(Lobby.live_results())
	for i in 4:
		Lobby.players[i + 1].score = 0
	Lobby.players_changed.emit()
	await shot.call("teams_series")
	# Royale: Runde 3, zwei ausgeschieden.
	Lobby.mm = MatchMode.new()
	Lobby.mm.start_royale([1, 2, 3, 4, 5])
	Lobby.mm.eliminate([{"peer": 1, "score": 900}, {"peer": 2, "score": 800}, {"peer": 3, "score": 700},
		{"peer": 4, "score": 600}, {"peer": 5, "score": 100}])
	Lobby.mm.eliminate([{"peer": 1, "score": 900}, {"peer": 2, "score": 800}, {"peer": 3, "score": 700},
		{"peer": 4, "score": 50}])
	Lobby.players_changed.emit()
	await shot.call("royale")
	# Royale im Spiel, ich (Host, Kenji) schaue nicht zu; Letzter markiert.
	Lobby.in_game = true
	for i in 3:
		Lobby.players[i + 1].score = [800000, 640000, 590000][i]
	Lobby.players_changed.emit()
	await shot.call("royale_live")
	Lobby.in_game = false
	Lobby.mm.eliminate([{"peer": 1, "score": 900}, {"peer": 2, "score": 800}, {"peer": 3, "score": 10}])
	Lobby.mm.eliminate([{"peer": 1, "score": 900}, {"peer": 2, "score": 10}])
	Lobby.players_changed.emit()
	await shot.call("royale_end")
	Lobby.set_meta("harness", true)
	Lobby._reset()
	get_tree().quit(0)


## Screenshots aller Lobby-Zustaende mit Fake-Daten (kein Netz, keine Ansage):
## Browser leer/mit Raeumen, Raum Frei (1 und 8 Spieler, lange Namen),
## Teams, Royale, Download laeuft, Sicht ohne Krone.
## Ziel: --shot-out=<Praefix> (sonst user://lobby).
func _lobby_shots() -> void:
	var out := _shot_prefix("user://lobby")
	var shot := func(tag: String):
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var path := "%s_%s.png" % [out, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT " + path)
	_fetch_timer.stop()
	# Laufende Online-Abfrage abwarten, sonst ueberschreibt sie die Fake-Raeume.
	var w := 0.0
	while Lobby._fetch_req != null and w < 9.0:
		await get_tree().create_timer(0.2).timeout
		w += 0.2
	Lobby.online_rooms = {}
	Lobby.lan_rooms = {}
	_refresh_rooms()
	await shot.call("browser_empty")
	var far := Time.get_ticks_msec() + 3600000
	Lobby.lan_rooms = {"192.168.178.24": {"name": "Kenjis Raum", "players": 3, "code": "", "t": far}}
	Lobby.online_rooms = {
		"7K3F9-A2QXM": {"name": "Freitagsrunde", "players": 6, "t": 0},
		"Q2M8X-PL4KD": {"name": "Nur 7K-Maps, bitte keine Anfänger und keine SV", "players": 8, "t": 0},
		"H4T2K-9ZWQE": {"name": "Aria's Raum", "players": 1, "t": 0},
		"M3N7P-2RTXA": {"name": "Turnier-Training", "players": 4, "t": 0},
	}
	_refresh_rooms()
	await shot.call("browser_rooms")
	Lobby.stop_discovery()
	Lobby.lan_rooms = {}
	Lobby.online_rooms = {}
	# Raum: ich (Peer 1) bin Host und Kronentraeger.
	Lobby._announce_t = 1.0e9
	Lobby.active = true
	Lobby.is_host = true
	Lobby.crown_id = 1
	Lobby.room_name = "Freitagsrunde"
	Lobby.room_code = "7K3F9-A2QXM"
	Lobby.players = {1: Lobby._new_player(Settings.profile_name if Settings.profile_name != "" else "Gexanx")}
	Lobby.sel_map = {}
	Lobby.mm = MatchMode.new()
	_show_room()
	await shot.call("room_free_1")
	var who := ["Kenji", "Maximilian_Unaufhaltsam", "Aria", "Tobi", "Lena", "Mara", "Jonas"]
	for i in who.size():
		Lobby.players[i + 2] = Lobby._new_player(who[i])
		Lobby.players[i + 2].ready = i % 3 != 1
	Lobby.players[1].ready = true
	if not _library.mapsets.is_empty():
		var ms: MapSet = _library.mapsets[mini(3, _library.mapsets.size() - 1)]
		var d := mini(1, ms.difficulty_count() - 1)
		Lobby.sel_map = {"set_id": _set_id_of(ms.osz_path.get_file()), "file": ms.osz_path.get_file(),
			"version": ms.version_name_at(d), "title": ms.title, "artist": ms.artist, "stars": ms.stars_at(d)}
	Lobby.mods = {"SV": false, "NF": true}
	_update_bg()
	Lobby.players_changed.emit()
	await shot.call("room_free_8")
	# Teams (4 Spieler).
	for i in range(5, 9):
		Lobby.players.erase(i)
	Lobby.mm = MatchMode.new(MatchMode.Kind.TEAMS)
	for i in 4:
		Lobby.mm.add_player(i + 1)
	Lobby.players_changed.emit()
	await shot.call("room_teams")
	# Royale (5 Spieler), Runde 3.
	Lobby.players[5] = Lobby._new_player("Lena")
	Lobby.players[5].ready = true
	Lobby.mm = MatchMode.new()
	Lobby.mm.start_royale([1, 2, 3, 4, 5])
	Lobby.mm.eliminate([{"peer": 1, "score": 900}, {"peer": 2, "score": 800}, {"peer": 3, "score": 700},
		{"peer": 4, "score": 600}, {"peer": 5, "score": 100}])
	Lobby.players_changed.emit()
	await shot.call("room_royale")
	# Frei, Map fehlt lokal, Download laeuft (nur Anzeige, kein echter Download).
	Lobby.mm = MatchMode.new()
	Lobby.sel_map = {"set_id": 987654, "file": "987654 Kairo - Neon Skyline.osz", "version": "Insane",
		"title": "Neon Skyline (Extended Mix)", "artist": "Kairo feat. Mio", "stars": 4.62}
	for id in Lobby.players:
		Lobby.players[id].ready = id != 1
	_downloading = true
	_dl_set = 987654
	_dl_bar.value = 0.42
	_dl_label.text = "42 %"
	_status_label.text = tr("Lade Map… %d %%") % 42
	_update_bg()
	Lobby.players_changed.emit()
	await shot.call("room_download")
	# Sicht ohne Krone: Kenji (Peer 2) hat sie, Map fehlt, Download pausiert.
	_downloading = false
	Lobby.crown_id = 2
	_status_label.text = " "
	Lobby.players_changed.emit()
	await shot.call("room_client")
	Lobby.set_meta("harness", true)
	Lobby._reset()
	get_tree().quit(0)
