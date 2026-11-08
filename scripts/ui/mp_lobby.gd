extends Control

## Multiplayer-Lobby: Raum erstellen (Port oeffnet sich automatisch per UPnP,
## Raum-Code zum Teilen), per Code beitreten, LAN-Raeume erscheinen von selbst.
## Im Raum: Spielerliste mit Krone (Host vergibt sie), Kronentraeger waehlt
## die Map, fehlende Maps laden automatisch vom Mirror, Host startet.
##
## Layout (Vollbild, 8er-Raster, Rand M): Kopfzeile, darunter entweder der
## Raum-Browser (Formulare oben, Raumkarten darunter) oder der Raum
## (links Raum-Panel mit Spielern, rechts Map-Karte, unten Aktionsleiste).

# Farben: eine Akzentfarbe (Primaer-Aktion, aktiver Reiter, Hover), dazu nur
# Zustandsfarben (bereit, Map fehlt, Krone). Keine Glas-Karten, keine Verlaeufe
# ausser der Lesbarkeits-Abdunklung unter dem Cover-Titel.
const COL_ACCENT := UiTheme.ACCENT
const COL_DIM := UiTheme.DIM
const COL_TEXT := UiTheme.TEXT
const COL_FAINT := Color(0.616, 0.592, 0.553, 0.5)
const COL_GOLD := Color(0.95, 0.79, 0.38)
const COL_READY := UiTheme.GOOD
const COL_WARN := UiTheme.BAD
const COL_HOVER := Color(1, 1, 1, 0.045)
const COL_LINE := Color(1, 1, 1, 0.09)

# Raster: 8er-Schritte, Rand M, ein Eckenradius R fuer alles.
const M := 24
const R := 4
const HEAD_H := 40
const BAR_H := 48
const ROW_H := 40
const PROW_H := 40
const SIDE_W := 344
# Spalten der Raumliste (Kopf und Zeilen teilen sie, damit die Kanten fluchten).
const RC_ICON := 20
const RC_MODE := 96
const RC_WHERE := 148
const RC_PLAYERS := 72
const RC_JOIN := 104
# Spalten der Spielerliste.
const PC_BADGE := 56
const PC_STATE := 112
# Vier Groessen, zwei Schnitte: Text (Theme-Schrift) und Zahlen/Titel (Bahnschrift).
const FS_S := 13
const FS_M := 15
const FS_L := 20
const FS_XL := 28

var _library: MapLibrary
var _mirror: BeatmapMirror
var _browser_box: VBoxContainer
var _room_box: VBoxContainer
var _rooms_list: VBoxContainer
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
var _star_pill: Control
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
var _play_btns: Dictionary = {}
var _mode_row: HBoxContainer
var _mode_info: Label
var _board_holder: VBoxContainer
var _team_board: TeamBoard = null
var _royale_board: RoyaleBoard = null
var _balance_btn: Button
var _tour_hidden := false
## Harness: Spielerzahl fuer die Zusammenfassung im Erstell-Dialog (0 = Lobby).
var _shot_players := 0
## Bereits gezeigte Spieler (nur neue Zeilen blenden ein, kein Flackern bei Scores).
var _seen_rows: Dictionary = {}
var _bpm_cache: Dictionary = {}
var _icons: Dictionary = {}
var _f_display: Font
var _f_num: Font
var _code_cap: Label
var _kind_sep: HBoxContainer
var _star_swatch: Control
var _facts: Dictionary = {}
var _players_rule: ColorRect
var _alone_hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-"):
			_harness_tr()
			break
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

	_fonts()
	# Hintergrund: ruhige Grundfarbe, darueber das geblurrte Cover (beim Oeffnen
	# das zuletzt gespielte Lied, im Raum die gewaehlte Map), kraeftig abgedunkelt.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = UiTheme.BG
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
	dim.color = Color(0.02, 0.02, 0.03, 0.80)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# Vollbild-Raster: Rand M ringsum, Kopfzeile, Haarlinie, Inhalt (Browser oder Raum).
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = M
	root.offset_top = M
	root.offset_right = -M
	root.offset_bottom = -M
	root.add_theme_constant_override("separation", 0)
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
	title.add_theme_font_override("font", _f_display)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_status_label = _lbl(" ", FS_S, COL_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_status_label)
	root.add_child(_gap(16))
	root.add_child(_sep())
	root.add_child(_gap(M))

	_browser_box = VBoxContainer.new()
	_browser_box.add_theme_constant_override("separation", 0)
	_browser_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_browser_box)
	_build_browser()

	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 0)
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
	# Bereit-Stand im Turnier-Panel (Runde starten) live nachziehen.
	Lobby.players_changed.connect(func():
		if _tpanel != null:
			_tpanel.sync_from_lobby())
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


## Screenshot-Harness: Texte aus translations/lobbycraft.csv direkt laden, solange
## die Datei (noch) nicht im Projekt registriert ist.
static func _harness_tr() -> void:
	if TranslationServer.translate("Spielmodus") != "Spielmodus" or TranslationServer.get_locale().begins_with("de"):
		return
	var f := FileAccess.open("res://translations/lobbycraft.csv", FileAccess.READ)
	if f == null:
		return
	var head := f.get_csv_line()
	var tl: Array = []
	for i in range(1, head.size()):
		var t := Translation.new()
		t.locale = head[i]
		tl.append(t)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < head.size() or row[0] == "":
			continue
		for i in range(1, head.size()):
			tl[i - 1].add_message(row[0], row[i])
	for t in tl:
		TranslationServer.add_translation(t)


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
# Bausteine: Labels, Knoepfe, Schalter, Icons (zwei Schnitte, 4 Groessen)
# ---------------------------------------------------------------------------

## Schnitte: Bahnschrift fett fuer Titel, Bahnschrift mit Tabellenziffern fuer
## alle Zahlen (Code, Spielerzahl, Sterne, BPM, Score) - Spalten fluchten.
func _fonts() -> void:
	var d := SystemFont.new()
	d.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Semibold", "Segoe UI"])
	d.font_weight = 700
	_f_display = d
	var n := SystemFont.new()
	n.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])
	n.font_weight = 500
	var nv := FontVariation.new()
	nv.base_font = n
	var ts := TextServerManager.get_primary_interface()
	nv.opentype_features = {ts.name_to_tag("tnum"): 1, ts.name_to_tag("lnum"): 1}
	_f_num = nv


func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Zahl/Code: Tabellenziffern, nie uebersetzt.
func _num(text: String, size: int, col: Color) -> Label:
	var l := _lbl(text, size, col)
	l.add_theme_font_override("font", _f_num)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Kleine Abschnitts-Beschriftung (Satzschreibung, gedimmt).
func _caption(text: String) -> Label:
	var l := _lbl(text, FS_S, COL_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Abschnitts-Titel (Text, mittlere Groesse, hell).
func _section(text: String) -> Label:
	var l := _lbl(text, FS_M, COL_TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _hgap(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Haarlinie statt Kasten.
func _sep() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = COL_LINE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Senkrechte Haarlinie (Spalten-/Gruppentrenner).
func _vsep(h: int = 0) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(1, h)
	r.color = COL_LINE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h > 0:
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


## Fremde Tafeln (Teams/Royale) an das Lobby-Raster angleichen: Ecken auf R,
## kein Schatten, Linien statt Glas. Runde Avatare (Radius >= halbe Breite) bleiben rund.
func _flatten(n: Node) -> void:
	if n is Control:
		var c := n as Control
		for slot in ["panel", "normal", "hover", "pressed"]:
			if not c.has_theme_stylebox_override(slot):
				continue
			var sb := c.get_theme_stylebox(slot) as StyleBoxFlat
			if sb == null or sb.has_meta("lc_flat"):
				continue
			var w := c.custom_minimum_size.x
			if w > 0.0 and w == c.custom_minimum_size.y and sb.corner_radius_top_left * 2 >= int(w):
				continue
			var f := sb.duplicate() as StyleBoxFlat
			f.set_meta("lc_flat", true)
			for corner in 4:
				f.set_corner_radius(corner, mini(f.get_corner_radius(corner), R))
			f.shadow_size = 0
			if f.border_width_top > 0 and f.border_color.a > COL_LINE.a and f.border_color.s < 0.2:
				f.border_color = COL_LINE
			c.add_theme_stylebox_override(slot, f)
	for ch in n.get_children():
		_flatten(ch)


## Flache Flaeche (Dialoge), Innenrand margin.
func _panel_box(margin: int = M) -> StyleBoxFlat:
	var sb := _box(Color(0.06, 0.062, 0.08, 0.96), R, COL_LINE)
	sb.set_content_margin_all(margin)
	return sb


## Knopf mit echten Zustaenden (Hover/Pressed/Disabled/Fokus), ohne Skalieren.
## primary: einzige gefuellte Akzentflaeche pro Ansicht.
func _btn(text: String, primary: bool = false, h: int = BAR_H) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", FS_M)
	var n: StyleBoxFlat
	var hv: StyleBoxFlat
	var pr: StyleBoxFlat
	var ds: StyleBoxFlat
	if primary:
		n = _box(COL_ACCENT, R)
		hv = _box(COL_ACCENT.lightened(0.18), R)
		pr = _box(COL_ACCENT.darkened(0.15), R)
		# Gesperrt bleibt als Primaer-Platz erkennbar (Akzent-Kante), ohne Fuellung.
		ds = _box(Color(COL_ACCENT, 0.06), R, Color(COL_ACCENT, 0.28))
		b.add_theme_font_override("font", _f_display)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(fc, Color(0.02, 0.05, 0.08))
	else:
		n = _box(Color(1, 1, 1, 0.07), R)
		hv = _box(Color(1, 1, 1, 0.13), R)
		pr = _box(Color(1, 1, 1, 0.04), R)
		ds = _box(Color(1, 1, 1, 0.025), R)
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_pressed_color", COL_TEXT)
		b.add_theme_color_override("font_focus_color", COL_TEXT)
		b.add_theme_color_override("icon_normal_color", COL_DIM)
		b.add_theme_color_override("icon_hover_color", COL_TEXT)
	b.add_theme_color_override("font_disabled_color", COL_FAINT)
	for sb in [n, hv, pr, ds]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", ds)
	b.add_theme_stylebox_override("focus", UiTheme._focus_box(R))
	b.add_theme_constant_override("h_separation", 8)
	UiTheme._attach_sounds(b)
	return b


## Textknopf ohne Flaeche (Kopieren, Aktualisieren): Flaeche erst beim Hover.
func _text_btn(text: String, icon_id: String = "", h: int = 28) -> Button:
	var b := _btn(text, false, h)
	b.add_theme_font_size_override("font_size", FS_S)
	if icon_id != "":
		b.icon = _icon(icon_id)
	var n := _box(Color(1, 1, 1, 0.0), R)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_color_override("font_color", COL_DIM)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.content_margin_left = 8
		sb.content_margin_right = 10
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Quadratischer Icon-Knopf (Zurueck, Krone geben).
func _icon_btn(icon: Texture2D, tip: String, sz: int = HEAD_H) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(sz, sz)
	b.focus_mode = Control.FOCUS_NONE
	var n := _box(Color(1, 1, 1, 0.0), R)
	var hv := _box(Color(1, 1, 1, 0.09), R)
	var pr := _box(Color(1, 1, 1, 0.14), R)
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


## Reiter (Spielmodus, Wertung): Text, aktiv = Akzent-Unterstrich, sonst gedimmt.
func _chip_toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", FS_M - 1)
	UiTheme._attach_sounds(b)
	_paint_chip(b, false)
	return b


func _paint_chip(b: Button, active: bool) -> void:
	var mk := func(hover: bool, dis: bool) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.05 if hover and not active else 0.0)
		sb.border_width_bottom = 2
		sb.border_color = Color(COL_ACCENT, 0.55 if dis else 1.0) if active else Color(1, 1, 1, 0.0)
		sb.corner_radius_top_left = R
		sb.corner_radius_top_right = R
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 2
		return sb
	var n: StyleBoxFlat = mk.call(false, false)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("hover", mk.call(true, false))
	b.add_theme_stylebox_override("hover_pressed", mk.call(true, false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", mk.call(false, true))
	var fg := COL_TEXT if active else COL_DIM
	for fc in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, fg)
	b.add_theme_color_override("font_hover_color", COL_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", COL_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(COL_TEXT, 0.82) if active else COL_FAINT)


## Mod-Schalter (No-Fail / SV): flache Zeile, Switch rechts.
func _mod_toggle(text: String, tip: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(0, ROW_H)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_font_size_override("font_size", FS_M - 1)
	var mk := func(bg_a: float) -> StyleBoxFlat:
		var sb := _box(Color(1, 1, 1, bg_a), R)
		sb.content_margin_left = 12
		sb.content_margin_right = 8
		return sb
	c.add_theme_stylebox_override("normal", mk.call(0.045))
	c.add_theme_stylebox_override("pressed", mk.call(0.045))
	c.add_theme_stylebox_override("hover", mk.call(0.08))
	c.add_theme_stylebox_override("hover_pressed", mk.call(0.08))
	c.add_theme_stylebox_override("disabled", mk.call(0.02))
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
		"refresh":
			var rs: Array = []
			for i in 18:
				var a0 := -0.9 + 4.9 * i / 18.0
				var a1 := -0.9 + 4.9 * (i + 1) / 18.0
				rs.append([Vector2(8, 8) + Vector2(cos(a0), sin(a0)) * 5.2, Vector2(8, 8) + Vector2(cos(a1), sin(a1)) * 5.2])
			var tip := Vector2(8, 8) + Vector2(cos(-0.9), sin(-0.9)) * 5.2
			rs.append([tip, tip + Vector2(-3.2, -0.6)])
			rs.append([tip, tip + Vector2(0.4, 3.2)])
			tex = _line_icon(16, rs)
		"cup":
			tex = _line_icon(16, [[Vector2(4.5, 2.5), Vector2(11.5, 2.5)], [Vector2(4.5, 2.5), Vector2(5, 7)],
				[Vector2(11.5, 2.5), Vector2(11, 7)], [Vector2(5, 7), Vector2(8, 9.5)], [Vector2(11, 7), Vector2(8, 9.5)],
				[Vector2(8, 9.5), Vector2(8, 12.5)], [Vector2(5, 13.5), Vector2(11, 13.5)],
				[Vector2(4.6, 4), Vector2(2.2, 4)], [Vector2(2.2, 4), Vector2(3, 6.5)], [Vector2(3, 6.5), Vector2(5, 7)],
				[Vector2(11.4, 4), Vector2(13.8, 4)], [Vector2(13.8, 4), Vector2(13, 6.5)], [Vector2(13, 6.5), Vector2(11, 7)]])
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
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Zustandsmarke: kleines Quadrat (bereit, laedt, Map fehlt).
func _dot(col: Color, sz: int = 6) -> Control:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _box(col, 1))
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ---------------------------------------------------------------------------
# Browser: links Raum erstellen / Code, rechts die offenen Raeume als Tabelle
# ---------------------------------------------------------------------------

func _build_browser() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_browser_box.add_child(cols)

	# Links: zwei Formulare untereinander, feste Breite, gleiche Kanten.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	side.add_theme_constant_override("separation", 8)
	cols.add_child(side)
	side.add_child(_section("Raum erstellen"))
	_name_edit = _field("Raumname")
	_name_edit.text = _possessive_room(Settings.profile_name)
	_name_edit.max_length = 28
	side.add_child(_name_edit)
	_pw_edit = _field("Passwort (leer = öffentlich)")
	side.add_child(_pw_edit)
	side.add_child(_hint("Ohne Passwort erscheint der Raum bei allen in der Liste."))
	var create := _btn("Raum erstellen", true, ROW_H)
	var do_create := func():
		if Lobby.host_room(_name_edit.text, _pw_edit.text):
			_show_room()
	create.pressed.connect(do_create)
	_name_edit.text_submitted.connect(func(_t): do_create.call())
	_pw_edit.text_submitted.connect(func(_t): do_create.call())
	side.add_child(create)

	side.add_child(_gap(M - 8))
	side.add_child(_sep())
	side.add_child(_gap(M - 8))
	side.add_child(_section("Mit Code beitreten"))
	_code_edit = _field("Code (z. B. 7K3F9-A2QXM)")
	_code_edit.add_theme_font_override("font", _f_num)
	_code_edit.text_submitted.connect(func(_t): _join_by_code())
	side.add_child(_code_edit)
	_join_pw_edit = _field("Passwort (falls gesetzt)")
	_join_pw_edit.text_submitted.connect(func(_t): _join_by_code())
	side.add_child(_join_pw_edit)
	side.add_child(_hint("Den Code bekommst du vom Host des Raums."))
	var join := _btn("Beitreten", false, ROW_H)
	join.pressed.connect(_join_by_code)
	side.add_child(join)

	cols.add_child(_hgap(M))
	var vr := _vsep()
	vr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(vr)
	cols.add_child(_hgap(M))

	# Rechts: Raumliste als Tabelle (Kopf, Spaltenkoepfe, Zeilen mit Haarlinien).
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	cols.add_child(main)
	var rooms_head := HBoxContainer.new()
	rooms_head.custom_minimum_size = Vector2(0, 28)
	rooms_head.add_theme_constant_override("separation", 12)
	main.add_child(rooms_head)
	rooms_head.add_child(_section("Offene Räume"))
	_rooms_count = _num("", FS_M, COL_DIM)
	rooms_head.add_child(_rooms_count)
	rooms_head.add_child(_spacer())
	var refresh := _text_btn("Aktualisieren", "refresh")
	refresh.tooltip_text = "Liste aktualisieren"
	refresh.pressed.connect(func(): Lobby.fetch_online_rooms())
	rooms_head.add_child(refresh)
	main.add_child(_gap(12))
	var ch := _room_cols(["", "Raum", "Modus", "Verbindung", "Spielerzahl", ""])
	ch.custom_minimum_size = Vector2(0, 24)
	main.add_child(ch)
	main.add_child(_sep())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_rooms_list = VBoxContainer.new()
	_rooms_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_rooms_list)
	_refresh_rooms()


## Spaltenkopf der Raumliste (gleiche Breiten und Abstaende wie _room_card).
func _room_cols(heads: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widths := [RC_ICON, 0, RC_MODE, RC_WHERE, RC_PLAYERS, RC_JOIN]
	hb.add_child(_hgap(0))
	for i in heads.size():
		var l := _caption(str(heads[i]))
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if widths[i] == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = widths[i]
		if i == 4:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(l)
	hb.add_child(_hgap(0))
	return hb


func _hint(text: String) -> Label:
	var h := _lbl(text, FS_S, COL_DIM)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return h


func _field(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, ROW_H)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", FS_M - 1)
	var n := _box(Color(0, 0, 0, 0.32), R, Color(1, 1, 1, 0.10))
	var f := _box(Color(0, 0, 0, 0.40), R, Color(COL_ACCENT, 0.7))
	for sb in [n, f]:
		sb.content_margin_left = 12
		sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", n)
	e.add_theme_color_override("caret_color", COL_ACCENT)
	return e


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


## Avatar: kleines Quadrat mit Anfangsbuchstabe, gedeckte Farbe aus dem Namen.
func _avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(
		Color.from_hsv(float(absi(pname.hash()) % 360) / 360.0, 0.30, 0.42), R))
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", _f_display)
	l.add_theme_font_size_override("font_size", int(sz * 0.5))
	l.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(l)
	return p


## Tabellenzeile der Raumliste; die ganze Zeile ist der Knopf.
## Die Raum-Ansage kennt nur Name, Spielerzahl, Code und Spielmodus.
func _room_card(lan: bool, rname: String, players_n: int, where: String, mode: String,
		on_join: Callable) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 52)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = rname
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.0)
	n.border_width_bottom = 1
	n.border_color = COL_LINE
	var hv := StyleBoxFlat.new()
	hv.bg_color = COL_HOVER
	hv.border_width_left = 2
	hv.border_color = COL_ACCENT
	var pr: StyleBoxFlat = hv.duplicate()
	pr.bg_color = Color(1, 1, 1, 0.025)
	card.add_theme_stylebox_override("normal", n)
	card.add_theme_stylebox_override("hover", hv)
	card.add_theme_stylebox_override("pressed", pr)
	card.add_theme_stylebox_override("focus", UiTheme._focus_box(R))
	UiTheme._attach_sounds(card)
	card.pressed.connect(on_join)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)
	hb.add_child(_hgap(0))
	hb.add_child(_icon_rect("lan" if lan else "globe", COL_DIM, RC_ICON))
	var nl := _lbl(rname, FS_M, COL_TEXT)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hb.add_child(nl)
	var ml := _lbl(Lobby.play_name(Lobby.norm_play(mode)), FS_S + 1, COL_TEXT)
	ml.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ml.custom_minimum_size.x = RC_MODE
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ml)
	var wl := _lbl(where, FS_S + 1, COL_DIM) if lan else _num(where, FS_S + 1, COL_DIM)
	wl.custom_minimum_size.x = RC_WHERE
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(wl)
	var cnt := _num(str(players_n), FS_M, COL_TEXT)
	cnt.custom_minimum_size.x = RC_PLAYERS
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(cnt)
	card.tooltip_text = "%s  ·  %s" % [rname, tr("1 Spieler") if players_n == 1 else tr("%d Spieler") % players_n]
	var jb := HBoxContainer.new()
	jb.custom_minimum_size.x = RC_JOIN
	jb.alignment = BoxContainer.ALIGNMENT_END
	jb.add_theme_constant_override("separation", 4)
	jb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(jb)
	var join := _lbl("Beitreten", FS_S + 1, COL_DIM)
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	jb.add_child(join)
	var chev := _icon_rect("next", COL_DIM)
	jb.add_child(chev)
	hb.add_child(_hgap(0))
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
		_rooms_list.add_child(_room_card(true, str(r.name), int(r.players), tr("Dein Netzwerk"),
			str(r.get("mode", "mania")), func():
				if Lobby.join_lan(target_ip):
					_show_room()))
		count += 1
	for code in Lobby.online_rooms:
		if lan_codes.has(str(code)):
			continue
		var o: Dictionary = Lobby.online_rooms[code]
		var jcode := str(code)
		_rooms_list.add_child(_room_card(false, str(o.name), int(o.players), jcode,
			str(o.get("mode", "mania")), func():
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
		# Leerer Zustand: ruhig, linksbuendig in der Tabelle, mit klarer naechster Aktion.
		var empty := VBoxContainer.new()
		empty.set_meta("empty", true)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_constant_override("separation", 4)
		empty.add_child(_gap(M))
		empty.add_child(_lbl("Gerade ist es ruhig hier", FS_M, COL_TEXT))
		var el := _lbl("Keine offenen Räume. Erstelle einen, er erscheint hier automatisch bei allen Spielern.", FS_S, COL_DIM)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(el)
		_rooms_list.add_child(empty)
		_fade_in(empty)


# ---------------------------------------------------------------------------
# Raum
# ---------------------------------------------------------------------------

func _build_room() -> void:
	# ---------------- Kopf: Raumname + Code links, Spielmodus/Format rechts --
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", M)
	_room_box.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	_room_title = _lbl("", FS_XL, COL_TEXT)
	_room_title.add_theme_font_override("font", _f_display)
	_room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tv.add_child(_room_title)
	var code_row := HBoxContainer.new()
	code_row.custom_minimum_size = Vector2(0, 28)
	code_row.add_theme_constant_override("separation", 8)
	tv.add_child(code_row)
	_code_cap = _caption("Code")
	code_row.add_child(_code_cap)
	_code_label = _num("", FS_M, COL_TEXT)
	code_row.add_child(_code_label)
	_copy_btn = _text_btn("Kopieren", "copy")
	_copy_btn.pressed.connect(_copy_code)
	code_row.add_child(_copy_btn)

	# Spielmodus (Mania 4K / Orbit) und Format (Frei / Teams / Battle Royale)
	# als Reiter: waehlt die Krone, alle sehen den aktiven Unterstrich.
	var sv := VBoxContainer.new()
	sv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sv.add_theme_constant_override("separation", 6)
	head.add_child(sv)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_END
	srow.add_theme_constant_override("separation", 2)
	sv.add_child(srow)
	srow.add_child(_caption("Spielmodus"))
	srow.add_child(_hgap(6))
	for pm in ["mania", "orbit"]:
		var pb := _chip_toggle(Lobby.play_name(pm))
		pb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var pmode: String = pm
		pb.pressed.connect(func():
			Lobby.set_play_mode(pmode)
			_refresh_room())
		srow.add_child(pb)
		_play_btns[pm] = pb
	_kind_sep = HBoxContainer.new()
	_kind_sep.add_theme_constant_override("separation", 0)
	_kind_sep.add_child(_hgap(14))
	_kind_sep.add_child(_vsep(20))
	_kind_sep.add_child(_hgap(16))
	_kind_sep.add_child(_caption("Format"))
	_kind_sep.add_child(_hgap(8))
	srow.add_child(_kind_sep)
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 2)
	srow.add_child(_mode_row)
	for k in 3:
		var kb := _chip_toggle(Lobby.mode_name(k))
		var kind: int = k
		kb.pressed.connect(func():
			Lobby.set_room_mode(kind)
			_refresh_room())
		_mode_row.add_child(kb)
		_mode_btns.append(kb)
	_mode_info = _lbl(" ", FS_S, COL_DIM)
	_mode_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mode_info.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(_mode_info)

	_room_box.add_child(_gap(16))
	_room_box.add_child(_sep())
	_room_box.add_child(_gap(M))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.add_child(cols)

	# ---------------- Links: Map (Cover gross, Fakten, Mods) ----------------
	var mapcol := VBoxContainer.new()
	mapcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapcol.add_theme_constant_override("separation", 0)
	cols.add_child(mapcol)
	# Cover: harte Kante (Radius R), Abdunklung nur unter dem Titel.
	var mask := Panel.new()
	mask.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 1), R))
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.self_modulate = Color(0.075, 0.08, 0.10, 1.0)
	mask.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mask.custom_minimum_size = Vector2(0, 160)
	mapcol.add_child(mask)
	_map_cover = TextureRect.new()
	_map_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(_map_cover)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.0), Color(0.02, 0.02, 0.03, 0.88)])
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
	over.offset_left = M
	over.offset_right = -M
	over.offset_bottom = -20
	over.alignment = BoxContainer.ALIGNMENT_END
	over.add_theme_constant_override("separation", 2)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(over)
	_map_label = _lbl("Noch keine Map gewählt.", FS_XL, COL_TEXT)
	_map_label.add_theme_font_override("font", _f_display)
	_map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_map_label.add_theme_constant_override("shadow_offset_y", 1)
	over.add_child(_map_label)
	_map_artist = _lbl("", FS_M, COL_TEXT.darkened(0.08))
	_map_artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_artist.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	over.add_child(_map_artist)
	_map_stats = _lbl(" ", FS_S, COL_DIM.lightened(0.1))
	_map_stats.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_stats.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	over.add_child(_map_stats)
	_map_empty = _lbl("Der Kronenträger wählt die Map.", FS_S, COL_DIM)
	over.add_child(_map_empty)

	# Faktenleiste: Beschriftung klein, Wert gross in Tabellenziffern, Haarlinien dazwischen.
	mapcol.add_child(_gap(16))
	_map_drow = HBoxContainer.new()
	_map_drow.add_theme_constant_override("separation", 0)
	mapcol.add_child(_map_drow)
	var star := _fact("Sterne", true)
	_star_pill = star[0]
	_star_label = star[1]
	_star_swatch = _dot(Color.WHITE, 8)
	var sbox: HBoxContainer = _star_label.get_parent()
	sbox.add_child(_star_swatch)
	sbox.move_child(_star_swatch, 0)
	var diff := _fact("Schwierigkeit", false)
	_map_meta = diff[1]
	_map_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	diff[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_drow.add_child(diff[0])
	for k in ["keys", "bpm", "len", "notes"]:
		var cap: String = {"keys": "Tasten", "bpm": "BPM", "len": "Länge", "notes": "Noten"}[k]
		var f := _fact(cap, false)
		_facts[k] = f
		_map_drow.add_child(f[0])
	# Letzte Zelle ohne Nachlauf: rechte Kante fluchtet mit dem Cover.
	var last_gap: Control = _facts["notes"][0].get_child(_facts["notes"][0].get_child_count() - 1)
	last_gap.custom_minimum_size.x = 0

	# Fehlt die Raum-Map: Status, "Map laden" (genau diese Set-ID), Fortschritt, Abbruch.
	_dl_row = HBoxContainer.new()
	_dl_row.custom_minimum_size = Vector2(0, ROW_H)
	_dl_row.add_theme_constant_override("separation", 12)
	_dl_row.visible = false
	mapcol.add_child(_dl_row)
	_dl_row.add_child(_dot(COL_WARN, 6))
	_dl_text = _lbl("Nicht in deiner Bibliothek", FS_S + 1, COL_WARN)
	_dl_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_row.add_child(_dl_text)
	_dl_bar = ProgressBar.new()
	_dl_bar.min_value = 0.0
	_dl_bar.max_value = 1.0
	_dl_bar.show_percentage = false
	_dl_bar.custom_minimum_size = Vector2(80, 4)
	_dl_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.10), 1))
	_dl_bar.add_theme_stylebox_override("fill", _box(COL_ACCENT, 1))
	_dl_row.add_child(_dl_bar)
	_dl_label = _num("", FS_M, COL_TEXT)
	_dl_label.custom_minimum_size = Vector2(48, 0)
	_dl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	mapcol.add_child(_gap(16))
	# Mods: nur der Kronentraeger schaltet.
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mapcol.add_child(mrow)
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

	cols.add_child(_hgap(M))
	var vr := _vsep()
	vr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(vr)
	cols.add_child(_hgap(M))

	# ---------------- Rechts: Spieler (Tabelle) bzw. Teams-/Royale-Tafel -----
	var pcol := VBoxContainer.new()
	pcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pcol.add_theme_constant_override("separation", 0)
	cols.add_child(pcol)
	var ph := HBoxContainer.new()
	ph.custom_minimum_size = Vector2(0, 32)
	ph.add_theme_constant_override("separation", 12)
	pcol.add_child(ph)
	_players_headrow = ph
	_players_head = _section("Spieler im Raum")
	ph.add_child(_players_head)
	ph.add_child(_spacer())
	_balance_btn = _text_btn("Auto-Ausgleich")
	_balance_btn.pressed.connect(func(): Lobby.auto_balance_teams())
	ph.add_child(_balance_btn)
	_ready_count = _num("", FS_M, COL_DIM)
	ph.add_child(_ready_count)
	_players_rule = _sep()
	pcol.add_child(_gap(8))
	pcol.add_child(_players_rule)

	_players_scroll = ScrollContainer.new()
	_players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pcol.add_child(_players_scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 0)
	_players_scroll.add_child(_players_box)
	# Allein im Raum: naechster Schritt statt leerer Flaeche.
	_alone_hint = _hint("")
	_alone_hint.visible = false
	_alone_hint.custom_minimum_size = Vector2(0, 0)
	_alone_hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_board_holder = VBoxContainer.new()
	_board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_holder.visible = false
	pcol.add_child(_board_holder)

	# ---------------- Aktionsleiste: alle Knoepfe gleich hoch ---------------
	_room_box.add_child(_gap(M))
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, BAR_H)
	bar.add_theme_constant_override("separation", 8)
	_room_box.add_child(bar)
	_leave_btn = _btn("Verlassen")
	_leave_btn.custom_minimum_size.x = 144
	_leave_btn.pressed.connect(func():
		Lobby.leave()
		_show_browser())
	bar.add_child(_leave_btn)
	bar.add_child(_spacer())
	_tour_btn = _btn("Turnier")
	_tour_btn.icon = _icon("cup")
	_tour_btn.custom_minimum_size.x = 168
	_tour_btn.pressed.connect(_on_tour_btn)
	bar.add_child(_tour_btn)
	_pick_btn = _btn("Map wählen")
	_pick_btn.custom_minimum_size.x = 168
	_pick_btn.pressed.connect(_open_picker)
	bar.add_child(_pick_btn)
	_start_btn = _btn(UiTheme.sentence(tr("SPIELEN")), true)
	_start_btn.custom_minimum_size.x = 264
	_start_btn.add_theme_font_size_override("font_size", FS_M + 2)
	_start_btn.pressed.connect(func(): Lobby.start_game())
	bar.add_child(_start_btn)


## Eine Zelle der Faktenleiste: [Haarlinie] Beschriftung ueber Wert. Gibt [Zelle, Wert].
func _fact(cap: String, first: bool) -> Array:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not first:
		cell.add_child(_vsep(36))
		cell.add_child(_hgap(16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(v)
	v.add_child(_caption(cap))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	v.add_child(vrow)
	var val := _num("", FS_L, COL_TEXT)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(val)
	cell.add_child(_hgap(16))
	if first:
		_map_drow.add_child(cell)
	return [cell, val]


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


## Ruhiges Abzeichen "3D" / "2D" / "Orbit" mit feiner Kante; null bei unbekannter Darstellung.
func _view_badge(view: String) -> Control:
	if view == "":
		return null
	var pc := PanelContainer.new()
	var sb := _box(Color(1, 1, 1, 0.0), 3, Color(1, 1, 1, 0.18))
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.tooltip_text = tr("Spielt in %s") % view
	var l := _num(view, FS_S, COL_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


## Zustand einer Spielerzeile: [Text, Farbe]. Eigene Zeile kennt auch "Map fehlt"/"Laedt".
func _row_state(id: int, p: Dictionary, my_id: int) -> Array:
	if id == my_id and not Lobby.sel_map.is_empty() and Lobby.resolve_local_path() == "":
		return [tr("Lädt Map"), COL_ACCENT] if _downloading else [tr("Map fehlt"), COL_WARN]
	if bool(p.get("ready", false)):
		return [tr("Bereit"), COL_READY]
	return [tr("Wartet"), COL_DIM]


## Eine Spielerzeile: Avatar, Name, Krone/Host/(du), (Score), Abzeichen, Zustand, Krone geben.
## Abzeichen und Zustand stehen in festen Spalten, damit alle Zeilen fluchten.
func _player_row(id: int, p: Dictionary, my_id: int, in_round: bool) -> Control:
	var is_crown: bool = id == Lobby.crown_id
	var row := PanelContainer.new()
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1, 1, 1, 0.0)
	n.border_width_bottom = 1
	n.border_color = COL_LINE
	n.content_margin_left = 4
	n.content_margin_right = 4
	var hv: StyleBoxFlat = n.duplicate()
	hv.bg_color = COL_HOVER
	row.add_theme_stylebox_override("panel", n)
	row.custom_minimum_size = Vector2(0, PROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# Lambdas fangen Locals beim Erzeugen ein: Knopf ueber Meta holen, er entsteht erst unten.
	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", hv)
		var g: Button = row.get_meta("give") if row.has_meta("give") else null
		if g != null:
			g.modulate.a = 1.0)
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", n)
		# Knopf bleibt sichtbar, solange die Maus auf ihm steht (Kind der Zeile).
		var g: Button = row.get_meta("give") if row.has_meta("give") else null
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
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Breite = Textbreite, hoechstens was neben festen Spalten und Krone/Host/(du) bleibt.
	var tw := name_l.get_theme_font("font").get_string_size(str(p.name), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_M).x
	var fixed := 36.0 + PC_BADGE + 12.0 + PC_STATE + 12.0 + 48.0 + 120.0 + (236.0 if in_round else 0.0)
	name_l.custom_minimum_size.x = minf(ceilf(tw) + 2.0, maxf(_players_scroll.size.x - fixed, 96.0))
	name_box.add_child(name_l)
	if is_crown:
		var cr := _icon_rect("crown", COL_GOLD)
		cr.tooltip_text = "Kronenträger: wählt die Map und startet"
		cr.mouse_filter = Control.MOUSE_FILTER_PASS
		name_box.add_child(cr)
	if id == 1:
		var host := _caption("Host")
		host.tooltip_text = "Hostet den Raum"
		host.mouse_filter = Control.MOUSE_FILTER_PASS
		name_box.add_child(host)
	if id == my_id:
		name_box.add_child(_caption("(du)"))
	name_box.add_child(_spacer())
	if in_round:
		var cols := [[UiTheme.fmt_score(int(p.get("score", 0))), 88, COL_TEXT],
			[UiTheme.fmt_num(float(p.get("acc", 0.0)) * 100.0, 1) + " %", 64, COL_DIM],
			["%dx" % int(p.get("combo", 0)), 48, COL_DIM]]
		for c in cols:
			var sl := _num(str(c[0]), FS_S + 1, c[2])
			sl.custom_minimum_size.x = int(c[1])
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			hb.add_child(sl)
	# Feste Spalte fuer das Darstellungs-Abzeichen (leer bei alten Clients).
	var bslot := HBoxContainer.new()
	bslot.custom_minimum_size = Vector2(PC_BADGE, 0)
	bslot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := _view_badge(Lobby.view_of(id))
	if vb != null:
		bslot.add_child(vb)
	hb.add_child(bslot)
	var st := HBoxContainer.new()
	st.custom_minimum_size = Vector2(PC_STATE, 0)
	st.add_theme_constant_override("separation", 8)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state := _row_state(id, p, my_id)
	st.add_child(_dot(state[1]))
	var stl := _lbl(state[0], FS_S + 1, state[1])
	stl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	_code_cap.visible = has_code
	_code_label.text = Lobby.room_code if has_code else tr("Nur im eigenen Netzwerk")
	_code_label.add_theme_color_override("font_color", COL_TEXT if has_code else COL_DIM)
	_copy_btn.visible = has_code
	# Der Alleine-Hinweis bleibt erhalten: vor dem Leeren aushaengen.
	if _alone_hint.get_parent() != null:
		_alone_hint.get_parent().remove_child(_alone_hint)
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
	if Lobby.room_kind() == MatchMode.Kind.FREE and Lobby.players.size() == 1:
		if Lobby.room_code != "":
			_alone_hint.text = tr("Noch niemand da. Teile den Code %s, oder der Raum erscheint in der Liste offener Räume.") % Lobby.room_code
		else:
			_alone_hint.text = tr("Noch niemand da. Mitspieler im selben Netzwerk sehen den Raum in ihrer Liste.")
		_alone_hint.visible = true
		_players_box.add_child(_alone_hint)
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
		_star_swatch.add_theme_stylebox_override("panel", _box(MapPicker.star_color(stars), 1))
		_star_label.text = UiTheme.fmt_num(stars, 2)
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
	for pm in _play_btns:
		var pb: Button = _play_btns[pm]
		var pon: bool = Lobby.play_mode == pm
		pb.set_pressed_no_signal(pon)
		_paint_chip(pb, pon)
		pb.disabled = not is_crown or in_tour or Lobby.in_game
		pb.tooltip_text = tr("Alle im Raum spielen %s.") % Lobby.play_name(Lobby.play_mode) if pon \
			else tr("Nur der Kronenträger wählt den Spielmodus.") if not is_crown else ""
	for k in _mode_btns.size():
		var kb: Button = _mode_btns[k]
		var on: bool = Lobby.room_kind() == k and not in_tour
		kb.set_pressed_no_signal(on)
		_paint_chip(kb, on)
		kb.disabled = not is_crown or in_tour or Lobby.in_game
		kb.visible = not in_tour
	_kind_sep.visible = not in_tour
	_pick_btn.visible = is_crown and not in_tour
	# Primaer-Slot: Krone startet; alle anderen sehen ihren Zustand (nicht klickbar).
	_start_btn.visible = not in_tour
	if is_crown:
		_start_btn.text = UiTheme.sentence(tr("SPIELEN"))
		_start_btn.disabled = not Lobby.can_start()
		var why := Lobby.mode_blocker()
		if Lobby.sel_map.is_empty():
			why = tr("Noch keine Map gewählt.")
		elif why == "" and not Lobby.all_ready():
			why = tr("Noch nicht alle sind bereit.")
		_start_btn.tooltip_text = why
		_start_btn.add_theme_color_override("font_disabled_color", COL_FAINT)
	else:
		var me_ready := Lobby.players.has(my_id) and bool(Lobby.players[my_id].get("ready", false))
		_start_btn.text = UiTheme.sentence(tr("BEREIT") if me_ready else (tr("MAP LÄDT") if _downloading else tr("NICHT BEREIT")))
		_start_btn.disabled = true
		_start_btn.tooltip_text = tr("Der Kronenträger startet die Runde.")
		_start_btn.add_theme_color_override("font_disabled_color", COL_READY if me_ready else Color(COL_DIM, 0.85))
	if _tour_btn != null:
		_tour_btn.visible = in_tour or Lobby.is_host
		_tour_btn.text = "Zum Turnier" if in_tour else "Turnier"
	_refresh_dl_ui()


## Diff, Tasten, BPM, Laenge, Noten der Raum-Map (Tasten..Noten nur lokal bekannt).
func _fill_map_meta() -> void:
	var version := str(Lobby.sel_map.get("version", "")).strip_edges()
	_map_meta.text = version
	_map_meta.tooltip_text = version
	var ms := _local_set()
	for k in _facts:
		_facts[k][0].visible = ms != null
	if ms == null:
		_map_stats.text = " "
		return
	var di := 0
	for i in ms.difficulty_count():
		if ms.version_name_at(i) == str(Lobby.sel_map.get("version", "")):
			di = i
			break
	var m: Dictionary = ms.meta_at(di)
	var mania := int(m.get("mode", 3)) == 3
	_facts["keys"][0].visible = mania
	_facts["keys"][1].text = "%dK" % int(round(float(m.get("cs", 4.0))))
	var bpm := _bpm_text(ms, di)
	_facts["bpm"][0].visible = bpm != ""
	_facts["bpm"][1].text = bpm
	var sec := int(float(m.get("duration_ms", 0.0)) / 1000.0)
	_facts["len"][0].visible = sec > 0
	_facts["len"][1].text = "%d:%02d" % [sec / 60, sec % 60]
	var notes := int(m.get("notes", 0))
	_facts["notes"][0].visible = notes > 0
	_facts["notes"][1].text = UiTheme.fmt_score(notes) if notes >= 10000 else str(notes)
	_map_stats.text = tr("Map von %s") % ms.creator if ms.creator != "" else " "


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
	_players_rule.visible = kind != MatchMode.Kind.ROYALE
	_players_head.text = "Spieler im Raum" if kind == MatchMode.Kind.FREE else Lobby.mode_name(kind)
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
		_flatten(_team_board)
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
		_flatten(_royale_board)
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
	_dl_text.add_theme_color_override("font_color", COL_TEXT if _downloading else COL_WARN)
	(_dl_row.get_child(0) as Control).visible = not _downloading
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
	if _tpanel != null or _tend != null:
		return  # Turnier-Ansicht offen: keine zweite Musikquelle
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


## Host: Anzahl Maps (5/10/15), Sternbereich exakt (eintippen oder 0,1er-Schritte),
## Mods und Filter der Auto-Auswahl (Long Notes, Laenge, BPM). Unten steht live,
## was entsteht. Zwei Spalten, damit der Dialog auch bei 1280x720 passt.
func _open_tour_setup() -> void:
	if _tour_dialog != null:
		return
	# Zustand im Dictionary: Lambdas kopieren lokale int/float-Werte, Aenderungen gingen sonst verloren.
	var st: Dictionary = {"maps": 10, "lo": 2.0, "hi": 5.0, "ln": "any", "len": 0, "bpm_lo": 0, "bpm_hi": 0}
	var mods: Dictionary = {"SV": bool(Lobby.mods.get("SV", false)), "NF": bool(Lobby.mods.get("NF", false))}
	var back := UiTheme.modal_backdrop(self)
	_tour_dialog = back
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box(28))
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var close_dialog := func():
		back.queue_free()
		_tour_dialog = null
	var head: Control = UiTheme.modal_header("Turnier erstellen", close_dialog)
	head.add_theme_constant_override("margin_bottom", 4)
	# Titel in Satzschreibung und Anzeigeschrift statt gesperrter Versalien.
	var htitle := head.get_child(0).get_child(0) as Label
	if htitle != null:
		htitle.text = tr("Turnier erstellen")
		htitle.add_theme_font_override("font", _f_display)
		htitle.add_theme_font_size_override("font_size", FS_L + 2)
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	v.add_child(cols)
	var colw := func() -> VBoxContainer:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 10)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(c)
		return c
	var left: VBoxContainer = colw.call()
	var right: VBoxContainer = colw.call()
	var summary := TournamentPanel.lbl("", FS_S + 1, COL_TEXT)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var est := TournamentPanel.lbl("", 12, COL_DIM)
	est.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var cfg_of := func() -> Dictionary:
		var lnr: Array = Tournament.LN_PRESETS[st.ln]
		return {"maps": st.maps, "stars_lo": st.lo, "stars_hi": st.hi, "mods": mods.duplicate(),
			"filters": {"ln_lo": lnr[0], "ln_hi": lnr[1], "len_max": st.len,
				"bpm_lo": st.bpm_lo, "bpm_hi": st.bpm_hi}}
	var fmt_star := func(x: float) -> String:
		return UiTheme.fmt_num(x, 1 if is_equal_approx(snappedf(x, 0.1), x) else 2)
	var upd_summary := func():
		var c: Dictionary = Tournament.clean_config(cfg_of.call())
		var n: int = _shot_players if _shot_players > 0 else maxi(Lobby.players.size(), 1)
		var per := int(ceil(float(st.maps) / float(n)))
		var txt: String = tr("%d Maps zwischen ★ %s und ★ %s.") % [st.maps, fmt_star.call(st.lo), fmt_star.call(st.hi)]
		txt += " " + (tr("Bei %d Spielern wählt jeder bis zu %d Maps, dann streicht jeder eine.") % [n, per])
		var parts := TournamentPanel.filter_parts(c.filters)
		txt += "\n" + (tr("Auto-Auswahl: %s.") % ", ".join(parts) if not parts.is_empty()
			else tr("Auto-Auswahl: alle Maps im Sternbereich."))
		summary.text = txt
		est.text = tr("≈ %d Minuten Spielzeit") % (int(st.maps) * 3)
	# --- Links: Maps, Sterne, Mods
	left.add_child(_section(tr("Anzahl Maps")))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	left.add_child(chips)
	var chip_btns: Dictionary = {}
	for n in [5, 10, 15]:
		var b := TournamentPanel.seg_button(str(n), n == st.maps, 84)
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 18)
		b.name = "Maps%d" % n
		var nn: int = n
		b.pressed.connect(func():
			st.maps = nn
			for k in chip_btns:
				(chip_btns[k] as Button).set_pressed_no_signal(k == nn)
			upd_summary.call())
		chips.add_child(b)
		chip_btns[n] = b
	est.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_child(TournamentPanel._gap(0))
	chips.add_child(est)
	left.add_child(TournamentPanel._gap(4))
	left.add_child(_section(tr("Schwierigkeit")))
	# Werte direkt eintippbar (z. B. "4,37"), -/+ fuer 0,1er-Schritte.
	var val_lo := LineEdit.new()
	var val_hi := LineEdit.new()
	var upd := func():
		val_lo.text = fmt_star.call(st.lo)
		val_hi.text = fmt_star.call(st.hi)
		upd_summary.call()
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	left.add_child(srow)
	for pair in [[val_lo, true], [val_hi, false]]:
		var is_lo: bool = pair[1]
		if not is_lo:
			var bis := TournamentPanel.lbl("bis", FS_M, COL_DIM)
			bis.custom_minimum_size.x = 34
			bis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bis.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			srow.add_child(bis)
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.custom_minimum_size = Vector2(36, 40)
		UiTheme.style_ghost_button(minus, 10)
		srow.add_child(minus)
		var vl: LineEdit = pair[0]
		vl.custom_minimum_size = Vector2(84, 40)
		vl.alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.max_length = 5
		vl.select_all_on_focus = true
		vl.add_theme_font_size_override("font_size", 18)
		vl.add_theme_color_override("font_color", COL_TEXT)
		vl.tooltip_text = tr("Sterne, z. B. 4,37")
		srow.add_child(vl)
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
		plus.focus_mode = Control.FOCUS_NONE
		plus.custom_minimum_size = Vector2(36, 40)
		UiTheme.style_ghost_button(plus, 10)
		srow.add_child(plus)
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
	left.add_child(TournamentPanel._gap(4))
	left.add_child(_section(tr("Mods")))
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	left.add_child(mrow)
	for k in ["NF", "SV"]:
		var mb := _mod_toggle("No-Fail" if k == "NF" else "SV",
			"Kein Abbruch bei leerer Lebensleiste" if k == "NF" else "Jede Map mit Tempowechseln")
		mb.custom_minimum_size.x = 150
		mb.size_flags_horizontal = Control.SIZE_FILL
		var key: String = k
		mb.set_pressed_no_signal(bool(mods[key]))
		mb.toggled.connect(func(on: bool):
			mods[key] = on
			upd_summary.call())
		mrow.add_child(mb)
	# --- Rechts: Filter der Auto-Auswahl
	right.add_child(_section(tr("Auto-Auswahl")))
	var rh := TournamentPanel.lbl("Gilt für »Rest automatisch füllen« — eigene Picks sind frei.", 12, COL_DIM)
	rh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(rh)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	var seg_row := func(cap: String, opts: Array, key: String):
		var cl := TournamentPanel.lbl(cap, FS_M, COL_DIM)
		cl.custom_minimum_size.x = 96
		grid.add_child(cl)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		grid.add_child(h)
		var btns: Array = []
		for o in opts:
			var b := TournamentPanel.seg_button(str(o[0]), st[key] == o[1])
			b.name = "%s_%s" % [key, str(o[1])]
			btns.append(b)
			var val: Variant = o[1]
			b.pressed.connect(func():
				st[key] = val
				for x in btns:
					(x as Button).set_pressed_no_signal(x == b)
				upd_summary.call())
			h.add_child(b)
	seg_row.call("Long Notes", [["Egal", "any"], ["Wenig", "few"], ["Mittel", "mid"], ["Viel", "many"]], "ln")
	seg_row.call("Länge", [["Egal", 0], ["≤ 2 min", 120], ["≤ 3 min", 180], ["≤ 4 min", 240], ["≤ 5 min", 300]], "len")
	var bcap := TournamentPanel.lbl("BPM", FS_M, COL_DIM)
	bcap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	grid.add_child(bcap)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	grid.add_child(brow)
	for bk in ["bpm_lo", "bpm_hi"]:
		if bk == "bpm_hi":
			var bis2 := TournamentPanel.lbl("bis", FS_M, COL_DIM)
			bis2.custom_minimum_size.x = 34
			bis2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bis2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			brow.add_child(bis2)
		var be := LineEdit.new()
		be.name = "BpmLo" if bk == "bpm_lo" else "BpmHi"
		be.placeholder_text = tr("egal")
		be.custom_minimum_size = Vector2(84, 38)
		be.alignment = HORIZONTAL_ALIGNMENT_CENTER
		be.max_length = 3
		be.select_all_on_focus = true
		be.add_theme_font_size_override("font_size", 16)
		be.add_theme_color_override("font_color", COL_TEXT)
		brow.add_child(be)
		var bkey: String = bk
		var bcommit := func():
			var tx := be.text.strip_edges()
			st[bkey] = clampi(int(tx), 0, Tournament.BPM_MAX) if tx.is_valid_int() else 0
			be.text = str(st[bkey]) if int(st[bkey]) > 0 else ""
			upd_summary.call()
		be.text_submitted.connect(func(_x):
			bcommit.call()
			be.release_focus())
		be.focus_exited.connect(bcommit)
	# --- Zusammenfassung + Aktionen
	var sbox := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(1, 1, 1, 0.035)
	ssb.border_color = Color(1, 1, 1, 0.08)
	ssb.set_border_width_all(1)
	ssb.set_corner_radius_all(R)
	ssb.set_content_margin_all(14)
	sbox.add_theme_stylebox_override("panel", ssb)
	v.add_child(sbox)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sbox.add_child(sv)
	sv.add_child(_caption(tr("Es entsteht")))
	sv.add_child(summary)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var cancel := _btn("Abbrechen", false, 46)
	cancel.custom_minimum_size = Vector2(130, 46)
	cancel.pressed.connect(close_dialog)
	bar.add_child(cancel)
	var go := _btn("Turnier erstellen", true, 46)
	go.custom_minimum_size = Vector2(220, 46)
	go.pressed.connect(func():
		Lobby.tour_create(cfg_of.call())
		close_dialog.call())
	bar.add_child(go)
	upd.call()
	_flatten(panel)


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
			_stop_room_preview()  # Panel-Vorschau (geteilter Player) verstummt mit der Ansicht
			_tpanel.queue_free()
			_tpanel = null
		if _tend == null:
			_stop_room_preview()
			_tend = TournamentEnd.new(t, _tour_title())
			_tend.library = _library
			_tend.my_id = multiplayer.get_unique_id()
			_tend.is_host = Lobby.is_host
			_tend.back_to_room.connect(_leave_tour_view)
			add_child(_tend)
		return
	if _tend != null:
		_tend.queue_free()
		_tend = null
	if _tpanel == null:
		_stop_room_preview()
		_tpanel = TournamentPanel.new(_library)
		_tpanel.shared_preview = _preview
		_tpanel.room_title = Lobby.room_name
		_tpanel.back_to_room.connect(_leave_tour_view)
		add_child(_tpanel)
	_tpanel.sync_from_lobby()


func _tour_title() -> String:
	return (tr("Turnier · %s") % Lobby.room_name) if Lobby.room_name != "" else tr("Turnier")


func _leave_tour_view() -> void:
	_tour_hidden = true
	_sync_tournament()


## Raum-Vorschau anhalten (Fade-Tween inklusive): sonst laeuft sie unter der
## Turnier-Ansicht weiter und doppelt sich mit der Panel-Vorschau.
func _stop_room_preview() -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	if _preview != null:
		_preview.stop()


func _clear_tour_views() -> void:
	_stop_room_preview()
	if _tpanel != null:
		_tpanel.queue_free()
		_tpanel = null
	if _tend != null:
		_tend.queue_free()
		_tend = null


func _count_playing(n: Node) -> int:
	var c := 1 if (n is AudioStreamPlayer and (n as AudioStreamPlayer).playing) else 0
	for ch in n.get_children():
		c += _count_playing(ch)
	return c


func _count_players(n: Node) -> int:
	var c := 1 if n is AudioStreamPlayer else 0
	for ch in n.get_children():
		c += _count_players(ch)
	return c


## Harness: Raum-Vorschau laeuft, Turnier-Ansicht oeffnet und schliesst, mehrfach
## (Ende -> Raum -> neues Turnier): immer hoechstens ein spielender Player.
func _audio_single_source_check() -> void:
	var base := _count_players(self)
	var ok := true
	for round_i in 3:
		_preview.stream = AudioStreamGenerator.new()
		_preview.play()
		var p := TournamentPanel.new(_library)
		p.harness = true
		p.shared_preview = _preview
		_tpanel = p
		_stop_room_preview()
		add_child(p)
		p._play_stream(AudioStreamGenerator.new())
		var during := _count_playing(self)
		var players := _count_players(self)
		_clear_tour_views()
		await get_tree().process_frame
		await get_tree().process_frame
		var after := _count_playing(self)
		print("AUDIO round=%d playing_during=%d playing_after=%d players=%d base=%d" % [
			round_i, during, after, players, base])
		ok = ok and during == 1 and after == 0 and players == base
	print("AUDIO-CHECK " + ("OK" if ok else "FAIL"))


## Screenshots aller Turnier-Phasen mit Fake-Daten (echte Tournament-Logik):
## Erstell-Dialog, dann je 6 und 2 Spieler Pick, Ban (verdeckt), Ban (aufgedeckt),
## Play (wer bereit ist/laedt, Countdown), Zwischenstand; zuletzt die Endbilder.
## Ziel: --shot-out=<Praefix> (sonst user://tournament). Fenstergroesse = Aufloesung.
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
	# Erstell-Dialog: 10 Maps, exakter Sternwert, wenig LN, bis 3 min, 120-200 BPM.
	_shot_players = 6
	_open_tour_setup()
	var edits := _tour_dialog.find_children("*", "LineEdit", true, false)
	if edits.size() >= 4:
		(edits[0] as LineEdit).text = "4,37"
		(edits[0] as LineEdit).text_submitted.emit("4,37")
		(edits[1] as LineEdit).text = "6.8"
		(edits[1] as LineEdit).text_submitted.emit("6.8")
		(edits[2] as LineEdit).text = "120"
		(edits[2] as LineEdit).text_submitted.emit("120")
		(edits[3] as LineEdit).text = "200"
		(edits[3] as LineEdit).text_submitted.emit("200")
	for bn in ["ln_few", "len_180"]:
		var b := _tour_dialog.find_child(bn, true, false) as Button
		if b != null:
			b.pressed.emit()
	await get_tree().create_timer(0.6).timeout
	await shot.call("setup")
	_tour_dialog.queue_free()
	_tour_dialog = null
	_shot_players = 0
	for n_players in [6, 2]:
		await _tour_phase_shots(shot, n_players)
	await _tour_end_shots(shot, out)
	get_tree().quit(0)


## Fake-Pool aus der echten Bibliothek (Cover), Rest wie Online-Maps.
func _shot_pool(n: int, by: Array) -> Array:
	var titles := ["Neon Skyline", "Gravity Bloom", "Echoes of Tomorrow", "Paper Planes",
		"Nightdrive", "Crystal Rain", "Last Light", "Pulse Garden", "Afterglow", "Zero Hour"]
	var arts := ["Kairo", "Lumen", "Velvet Static", "Mio", "Driftwood", "Aoi", "Halo Park", "Sora", "Nova", "Eclipse"]
	var sets: Array = _library.mapsets.duplicate()
	var pool: Array = []
	for i in n:
		var m := {"set_id": 900000 + i, "file": "", "version": "Hard", "title": titles[i % 10],
			"artist": arts[i % 10], "stars": 3.1 + i * 0.19, "by": by[i % by.size()], "online": true,
			"banned": false, "ln": [4, 12, 8, 0, 14, 6, 10, 3, 11, 9][i % 10],
			"len_s": 95 + (i * 37) % 90, "bpm": 128 + (i * 23) % 70}
		if i < sets.size():
			var ms: MapSet = sets[i]
			m["file"] = ms.osz_path.get_file()
			m["title"] = ms.title
			m["artist"] = ms.artist
			m["online"] = false
			if ms.difficulty_count() > 0:
				m["version"] = ms.version_name_at(ms.difficulty_count() - 1)
		pool.append(m)
	return pool


func _tour_phase_shots(shot: Callable, np: int) -> void:
	var who := ["Kenji", "Aria", "Mara", "Tobi", "Lena", "Yuki", "Finn", "Noa"]
	var names := {}
	var fake := {}
	for i in np:
		names[i + 2] = who[i]
		fake[i + 2] = {"name": who[i], "ready": false}
	var ids: Array = names.keys()
	var maps := 10 if np > 2 else 5
	var t := Tournament.create({"maps": maps, "stars_lo": 3.0, "stars_hi": 5.0, "mods": {"SV": true, "NF": false},
		"seed": 11, "filters": {"ln_lo": 0, "ln_hi": 15, "len_max": 180, "bpm_lo": 120, "bpm_hi": 200}})
	t.set_players(ids, names)
	t.host_id = 2
	var full_pool := _shot_pool(maps, ids)
	var panel := TournamentPanel.new(_library)
	panel.harness = true
	panel.names = names
	panel.fake_players = fake
	panel.my_id = 2
	panel.is_host = true
	panel.room_title = "Freitagsrunde"
	panel.t = t
	add_child(panel)
	var tag := "%dp_" % np
	# PICK: Pool teilweise gefuellt, eine Map laedt noch.
	t.phase = Tournament.Phase.PICK
	t.pool = full_pool.slice(0, maps - 3 if np > 2 else 3)
	var dl_i: int = t.pool.size() - 1
	var dl_keep: Dictionary = t.pool[dl_i].duplicate()
	t.pool[dl_i]["file"] = ""
	t.pool[dl_i]["online"] = true
	panel.refresh()
	panel._on_dl_progress(int(t.pool[dl_i].set_id), 0.42)
	await get_tree().create_timer(1.2).timeout
	await shot.call(tag + "pick")
	# Download fertig: ab hier hat die Map wieder Datei und Cover.
	full_pool[dl_i]["file"] = dl_keep.file
	full_pool[dl_i]["online"] = dl_keep.online
	# BAN verdeckt: ich habe gebannt, ein Teil der anderen hat gewaehlt.
	t.pool = full_pool
	t.phase = Tournament.Phase.BAN
	t.hidden = true
	t.bans = {2: 1}
	t.voted = [2, 3] if np > 2 else [2]
	if np > 2:
		t.voted.append(5)
	for m in t.pool:
		m.banned = false
	t.pool[1].banned = true
	panel.refresh()
	await get_tree().create_timer(0.9).timeout
	await shot.call(tag + "ban")
	if np > 2:
		await _audio_single_source_check()
	# BAN aufgedeckt: alle haben gewaehlt (einer "Kein Ban").
	t.hidden = false
	t.voted = []
	for m in t.pool:
		m.banned = false
	t.bans = {}
	var targets := [1, 4, -1, 7, 4, -1, 2, 8] if np > 2 else [1, -1]
	for i in np:
		var e := t.ban(ids[i], targets[i])
		if e != "":
			t.ban(ids[i], Tournament.SKIP)
	panel._reveal_played = false
	panel.refresh()
	await get_tree().create_timer(4.2 if np > 2 else 2.6).timeout
	await shot.call(tag + "ban_reveal")
	# Zwei Runden spielen, dritte Runde steht fest (PLAY).
	for r in 2:
		t.next_map()
		t.record_round(_shot_results(ids, names, r))
	t.next_map()
	var k := 0
	for id in fake:
		fake[id]["ready"] = k != 1 and k != 3
		fake[id]["dl"] = 0.63 if k == 1 else -1.0
		k += 1
	panel.fake_auto_left = -1.0
	panel.refresh()
	await get_tree().create_timer(1.0).timeout
	await shot.call(tag + "play")
	# Alle bereit: Countdown laeuft.
	for id in fake:
		fake[id]["ready"] = true
	panel.fake_auto_left = 4.2
	panel.refresh()
	await get_tree().create_timer(0.5).timeout
	await shot.call(tag + "play_ready")
	# BETWEEN: nach Runde 3.
	t.record_round(_shot_results(ids, names, 2))
	panel.fake_auto_left = 7.6
	panel.refresh()
	await get_tree().create_timer(1.0).timeout
	await shot.call(tag + "between")
	panel.queue_free()
	await get_tree().process_frame


func _shot_results(ids: Array, names: Dictionary, r: int) -> Dictionary:
	var res := {}
	var n := ids.size()
	for i in n:
		var rank := (i + r * 2) % n
		var id: int = ids[i]
		res[id] = {"score": 931000 - rank * 38500 - r * 6100, "accuracy": 0.986 - rank * 0.017 - r * 0.004,
			"max_combo": 1240 - rank * 160, "failed": r == 1 and i == n - 1 and n > 2, "name": names[id]}
	return res


func _tour_end_shots(shot: Callable, out: String) -> void:
	var who := ["Aria", "Kenji", "Mara", "Tobi", "Lena"]
	var names := {}
	for i in who.size():
		names[i + 2] = who[i]
	var rt := Tournament.new()
	rt.config = Tournament.clean_config({"maps": 10, "stars_lo": 3.0, "stars_hi": 5.0, "mods": {"SV": true}})
	rt.pool = _shot_pool(10, [2, 3, 4, 5, 6])
	rt.player_names = names.duplicate()
	rt.order = [0, 2, 3, 5, 6, 8, 9, 1, 4, 7]
	rt.phase = Tournament.Phase.END
	rt.current_round = rt.order.size() - 1
	var perms := [[0, 1, 2, 3, 4], [1, 0, 2, 4, 3], [0, 2, 1, 3, 4], [2, 0, 1, 3, 4], [1, 2, 0, 3, 4]]
	for r in 10:
		var res := {}
		var perm: Array = perms[r % 5]
		for k in 5:
			var rank: int = perm.find(k)
			var fail := r == 1 and k == 4
			res[k + 2] = {"score": 930000 - rank * 41000 - r * 7000, "accuracy": 0.985 - rank * 0.021 - (0.04 if r % 4 == 3 else 0.0),
				"max_combo": 400 + k * 30 + r * 11, "failed": fail, "name": who[k],
				"place": 5 if fail else rank + 1, "points": 0 if fail else 5 - rank, "absent": r == 9 and k == 2}
		rt.rounds.append({"map": rt.order[r], "results": res})
	var end := TournamentEnd.new(rt, tr("Turnier · %s") % "Freitagsrunde")
	end.harness = true
	end.my_id = 3
	end.library = _library
	add_child(end)
	await get_tree().create_timer(1.6).timeout
	await shot.call("end")
	var img_path := end.save_png("%s_end_image.png" % out)
	print("END-BILD " + img_path)
	end.queue_free()
	# 2 Spieler, 3 Maps, in Runde 3 beide durchgefallen.
	var t2 := Tournament.new()
	t2.config = Tournament.clean_config({"maps": 5, "stars_lo": 2.5, "stars_hi": 2.7})
	t2.pool = [rt.pool[0].duplicate(), rt.pool[1].duplicate(), rt.pool[2].duplicate()]
	t2.player_names = {2: "Circleguard", 3: "Gexanx"}
	t2.order = [0, 1, 2]
	for r in 3:
		var fail := r == 2
		t2.phase = Tournament.Phase.PLAY
		t2.current_round = r
		t2.record_round({
			2: {"score": 610000 - r * 90000, "accuracy": 0.82 - r * 0.2, "max_combo": 301 - r * 90, "failed": fail, "name": "Circleguard"},
			3: {"score": 540000 - r * 60000, "accuracy": 0.86 - r * 0.02, "max_combo": 255 - r * 20, "failed": fail, "name": "Gexanx"}})
	var end2 := TournamentEnd.new(t2, tr("Turnier · %s") % "Gexanx' Room")
	end2.harness = true
	end2.my_id = 3
	end2.library = _library
	add_child(end2)
	await get_tree().create_timer(1.2).timeout
	await shot.call("end2")
	end2.queue_free()
	await get_tree().process_frame


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
		# Gemischte Darstellung; Jonas (letzter) = alter Client ohne Angabe.
		Lobby.players[i + 2].view = ["3D", "2D", "2D", "3D", "Orbit", "3D", ""][i]
	Lobby.players[1].ready = true
	Lobby.players[1].view = "3D"
	if not _library.mapsets.is_empty():
		var ms: MapSet = _library.mapsets[mini(3, _library.mapsets.size() - 1)]
		var d := mini(1, ms.difficulty_count() - 1)
		Lobby.sel_map = {"set_id": _set_id_of(ms.osz_path.get_file()), "file": ms.osz_path.get_file(),
			"version": ms.version_name_at(d), "title": ms.title, "artist": ms.artist, "stars": ms.stars_at(d)}
	Lobby.mods = {"SV": false, "NF": true}
	_update_bg()
	Lobby.players_changed.emit()
	await shot.call("room_free_8")
	# Orbit-Raum: alle spielen Orbit, Abzeichen zeigen "Orbit".
	Lobby.play_mode = "orbit"
	for pid in Lobby.players:
		Lobby.players[pid].view = "Orbit" if pid != 8 else ""
	Lobby.players_changed.emit()
	await shot.call("room_orbit")
	Lobby.play_mode = "mania"
	for pid in Lobby.players:
		Lobby.players[pid].view = ["3D", "3D", "2D", "2D", "3D", "Orbit", "3D", ""][pid - 1]
	Lobby.players_changed.emit()
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
