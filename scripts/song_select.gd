extends Control

## Song-Browser (Rhythia-Vorlage): Vollbild-Hintergrund der Auswahl, Info-Panel
## links (Sterne, Bestwert, SPIELEN), Mitte Cover-Buehne mit Visualizer, rechts
## Karten mit Cover und Grade-Badge. Kopfzeile: Profil, Tabs, Suche, Einstellungen.
## Sterne kommen ausschliesslich aus rosu-pp (StarService, Regel 9).
## Neue .osz einfach ins Fenster ziehen -> Import + Neuscan.

const COL_BG := Color(0.03, 0.03, 0.05)
const COL_PANEL := Color(0.07, 0.07, 0.10, 0.92)
const COL_CARD := Color(0.08, 0.08, 0.11, 0.94)
const COL_CARD_SEL := Color(0.13, 0.13, 0.18, 0.98)
const COL_ACCENT := Color(0.20, 0.85, 1.0)
const COL_TEXT := Color(0.95, 0.96, 1.0)
const COL_DIM := Color(0.62, 0.64, 0.72)
# Raster: 24 px Aussenrand, rechte Spalte (Toolbar, Filter, Liste) gleich breit.
const M := 24
const INFO_W := 400
const RIGHT_W := 640
const HEAD_Y := 24
const HEAD_H := 40
const FILTER_Y := 76
const FILTER_H := 32
const CHIPS_Y := 116
const CHIPS_H := 30
const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}

var _library: MapLibrary
var _filtered: Array[MapSet] = []
var _selected_set: MapSet = null
var _selected_diff := 0

var _bg: TextureRect
var _cover: TextureRect
var _stage: Control
var _stage_shadow: Panel
var _stage_mask: Panel
var _stage_viz: AudioVisualizer
var _title_label: Label
var _artist_label: Label
var _mapper_label: Label
var _diff_label: Label
var _stats_label: Label
var _star_label: Label
var _best_label: Label
var _lb_box: VBoxContainer
var _list_box: VBoxContainer
var _search: LineEdit
var _count_label: Label
var _card_buttons: Array[Button] = []
# Bass-Reaktion der Vorschau (dezent): Onset gegen gleitenden Mittelwert.
var _pulse_card: Button = null
var _play_btn: Button
# Glow der ausgewaehlten Karte: dieselbe StyleBox wird pro Frame nur
# skalar angepasst (keine Allokation).
var _sel_box: StyleBoxFlat = null
# Info-Panel: BPM/Laenge-Chips, Diff-Farbbalken, Vorschau-Fortschritt.
var _bpm_label: Label
var _len_label: Label
var _diff_bar: HBoxContainer
var _progress_bg: Control
var _progress_fill: ColorRect
var _preview_len := 0.0
var _bpm_cache: Dictionary = {}
# Weiches Scrollen der Liste beim Kartenwechsel.
var _scroll_tween: Tween
const CARD_H := 76.0
const CARD_RADIUS := 12
var _frame_idle: StyleBoxFlat
var _frame_hover: StyleBoxFlat
var _frame_sel: StyleBoxFlat
var _glow_box: StyleBoxFlat
var _card_cover_mat: ShaderMaterial
var _card_cover_size := Vector2.ZERO
const CARD_SLIDE := 8.0
const LIST_PAD := 16
const LIST_TOP := FILTER_Y + FILTER_H
const LIST_EDGE := 6
var _list_mask: TextureRect
var _list_grad: Gradient
var _preview: AudioStreamPlayer
var _preview_fade: Tween
var _preview_gain_db := 0.0
# Vorschau ~3 dB unter Gameplay-Pegel, mit sanfter Einblendung.
const PREVIEW_DB := -3.0
const PREVIEW_SILENT_DB := -60.0
const PREVIEW_FADE_OUT := 0.12
const PREVIEW_FADE_IN := 0.25
var _beat := BeatClock.new()
var _preview_set: MapSet = null
var _tp_cache: Dictionary = {}

## Aktiver No-Fail-Mod: Health kann nicht auf 0 fallen, Play zaehlt unranked.
var _nf_enabled := Settings.mod_nf
var _nf_btn: Button
## SV-Mod: jede Map mit generierten Tempowechseln (SvMod), Score x1.10.
var _sv_enabled := Settings.mod_sv
var _sv_btn: Button

# Lazy-Loading der Karten-Thumbnails (2 pro Frame).
var _thumb_queue: Array = []
# Lade-Messung (--perf): Startzeit von _ready bzw. der letzten Auswahl.
var _perf_ready_t := 0
var _perf_select_t := 0
# Hintergrund-Vorbereitung der Auswahl (Parse + Audio + Cover), entprellt:
# erst wenn die Auswahl PREPARE_DELAY_MS stabil ist (schnelles Scrollen
# startet keine Task-Lawine). Full-Res-Cover kommt danach aus dem Cache.
const PREPARE_DELAY_MS := 100
const THUMB_BUDGET_USEC := 4000
var _prep_due := 0
var _bg_wait_set: MapSet = null
# Gameplay-Szenen + ihre schweren Assets im Hintergrund vorladen
# (ResourceLoader-Threads): SPIELEN wechselt dann per change_scene_to_packed,
# ohne mania_3d.gd erst zu kompilieren und die Stationen zu laden. Statisch
# gehalten -> bleiben im ResourceCache, auch fuer Retry/naechsten Song.
const GAME_SCENES := ["res://scenes/mania_3d.tscn", "res://scenes/gameplay_3d.tscn"]
const GAME_ASSET_DIRS := ["res://assets_game/stations"]
const GAME_PRELOAD_DELAY := 0.3
static var _game_res: Dictionary = {}
static var _game_req: Array[String] = []   # laufende Requests (ueberleben Szenenwechsel)
var _game_preload_t := 0
# scores.cfg einmal pro Kartenaufbau lesen (statt pro Karte und Diff).
var _scores_cfg: ConfigFile = null
var _replay_btn: Button

# Collections-Ansicht.
var _collection_mode := false
var _active_collection := ""
var _chips_row: HBoxContainer
# Lokale Filter: Sterne-Bereich + Sortierung (clean als Chip-Reihe).
var _star_filter := 0
var _sort_mode := 0
var _star_chips: Array[Button] = []
var _sv_filter := false
## Filter/Sortierung/Sammlung/Suche bleiben ueber Map-Ende und Neustart erhalten.
const BROWSER_STATE_PATH := "user://browser_state.cfg"
var _state_ready := false
var _saved_search := ""
var _sv_chip: Button
# Max-pp (SS) der ausgewaehlten Diff — rosu-pp im Hintergrund-Thread.
var _maxpp_label: Label
var _maxpp_thread: Thread
var _tab_collections: Button
var _tab_downloaded: Button
var _tab_online: Button
var _scroll: ScrollContainer

# Online-Tab (Mirror catboy.best): eigener Browser, bleibt versteckt am Leben.
var _online: OnlineBrowser = null
# Schwierigkeits-Filter der Bibliothek (client-seitig).
const STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["<2★", 0.0, 2.0],
	["2–4★", 2.0, 4.0],
	["4–6★", 4.0, 6.0],
	["6★+", 6.0, 999.0],
]
func _ready() -> void:
	_perf_ready_t = Time.get_ticks_usec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new()
	_library.scan()
	GameSession.perf_since("Browser: Library-Scan gesamt", _perf_ready_t)
	# SV-Erkennung fuer alte Cache-Eintraege im Hintergrund nachrechnen.
	_library.start_sv_backfill(_on_sv_backfill_done)

	_preview = AudioStreamPlayer.new()
	_preview.bus = "Music"
	_preview.volume_db = PREVIEW_DB
	add_child(_preview)

	var t_ui := Time.get_ticks_usec()
	var restore := _load_browser_state()
	_build_ui()
	GameSession.perf_since("Browser: UI aufbauen", t_ui)
	t_ui = Time.get_ticks_usec()
	if restore:
		_search.text = _saved_search
		if _collection_mode:
			_set_collection_mode(true)
	_refresh_filter(_search.text)
	_state_ready = restore
	GameSession.perf_since("Browser: %d Karten bauen" % _filtered.size(), t_ui)
	get_window().files_dropped.connect(_on_files_dropped)
	t_ui = Time.get_ticks_usec()
	_select_initial()
	GameSession.perf_since("Browser: Startauswahl (Info, Cover, Vorschau)", t_ui)
	GameSession.perf_since("Browser: _ready gesamt", _perf_ready_t)
	get_tree().create_timer(GAME_PRELOAD_DELAY).timeout.connect(_begin_game_preload)

	if OS.get_cmdline_args().has("--sv"):
		_on_sv_toggled(true)  # Debug/Shots: SV-Mod vorwaehlen
	if DisplayServer.get_name() == "headless":
		_headless_report()
	elif GameSession.perf_enabled:
		_perf_flow.call_deferred()
	elif OS.get_cmdline_args().has("--mania"):
		# Debug: erste 4K-Mania-Diff automatisch starten.
		for ms in _filtered:
			for i in ms.difficulty_count():
				if int(ms.meta_at(i).get("mode", 0)) == 3:
					_select_set(ms, i)
					_selected_diff = i
					_on_play_pressed.call_deferred()
					return
		push_warning("--mania: keine 4K-Diff gefunden")
	elif OS.get_cmdline_args().has("--autoplay"):
		_on_play_pressed.call_deferred()
	elif OS.get_cmdline_args().has("--shot-sv"):
		_shot_sv.call_deferred()
	elif OS.get_cmdline_args().has("--shot-online"):
		# Harness: Online-Tab (Raster, Genre, Download, Fehler) als PNGs.
		_shot_online.call_deferred()
	elif OS.get_cmdline_args().has("--shot-settings"):
		# Harness: Einstellungen oeffnen, das Panel fotografiert seine Reiter selbst.
		# --skin2d=<Ordnername>: Skin fuer die Vorschau (nur im Speicher, nicht gespeichert).
		for a in OS.get_cmdline_args():
			if a.begins_with("--skin2d="):
				Settings.skin_2d = a.trim_prefix("--skin2d=")
		add_child.call_deferred(SettingsPanel.new())
	elif OS.get_cmdline_args().has("--shot"):
		_capture_screenshot_and_quit()


## Lade-Messung: Map wechseln (Auswahl -> Vorschau-Ton), kurz warten, SPIELEN.
func _perf_flow() -> void:
	var picks: Array = []
	for ms in _filtered:
		for i in ms.difficulty_count():
			if int(ms.meta_at(i).get("mode", 0)) == 3:
				picks.append([ms, i])
				break
	var at := 0
	for k in picks.size():
		if picks[k][0] == _selected_set:
			at = k
	for step in 2:
		await get_tree().create_timer(1.5).timeout
		if picks.is_empty():
			_move_selection(1)
		else:
			var pk: Array = picks[(at + 1 + step) % picks.size()]
			_select_set(pk[0], pk[1])
	await get_tree().create_timer(2.0).timeout
	GameSession.perf_request("SPIELEN -> Gameplay")
	_on_play_pressed()


## Harness: Browser mit aktivem SV-Chip, danach Online-Panel mit SV-Chip.
func _shot_sv() -> void:
	var dir := OS.get_environment("SV_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	# Backfill abwarten (max. 60 s).
	var waited := 0.0
	while _library.sv_backfill_running() and waited < 60.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_sv_filter = true
	_restyle_star_chips()
	_refresh_filter(_search.text)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("sv_browser.png"))
	print("SV-Sets lokal: %d von %d" % [_filtered.size(), _library.mapsets.size()])
	_open_download_panel()
	await get_tree().create_timer(1.0).timeout
	_online._set_sv(true)
	await _online._wait_loaded(120.0)
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("sv_online.png"))
	print("SV-DL-KARTEN: %d" % _online._rows.size())
	get_tree().quit(0)


func _shot_online() -> void:
	var dir := OS.get_environment("ONLINE_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	_open_download_panel()
	await _online.run_shot_harness(dir)
	get_tree().quit(0)


func _capture_screenshot_and_quit() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/song_select.png"
	img.save_png(path)
	print("SHOT gespeichert: " + path)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# UI-Aufbau
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.modulate = Color(0.34, 0.34, 0.40)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_init_card_styles()
	_build_header()
	_build_info_panel()
	_build_stage()
	_build_list()


func _build_header() -> void:
	# Profil-Ecke links oben: Name + pp in einer Zeile, Zahnrad daneben.
	var left := HBoxContainer.new()
	left.position = Vector2(M, HEAD_Y)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var profile_panel := PanelContainer.new()
	var pbox := UiTheme.glass_box(10, 0.5)
	pbox.content_margin_left = 14
	pbox.content_margin_right = 14
	profile_panel.add_theme_stylebox_override("panel", pbox)
	profile_panel.custom_minimum_size = Vector2(0, HEAD_H)
	left.add_child(profile_panel)
	var pv := HBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	profile_panel.add_child(pv)
	var profile := Label.new()
	profile.text = Settings.profile_name
	profile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	profile.add_theme_font_size_override("font_size", 16)
	profile.add_theme_color_override("font_color", COL_TEXT)
	pv.add_child(profile)
	var sub := Label.new()
	sub.text = UiTheme.fmt_pp(ScoreStore.profile_pp())
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT2)
	pv.add_child(sub)

	var gear := Button.new()
	gear.text = "⚙"
	gear.tooltip_text = "Einstellungen"
	gear.custom_minimum_size = Vector2(HEAD_H, HEAD_H)
	gear.add_theme_font_size_override("font_size", 18)
	UiTheme.style_ghost_button(gear, 10)
	_square_margins(gear)
	gear.pressed.connect(func(): add_child(SettingsPanel.new()))
	left.add_child(gear)

	# Rechte Spalte: Tabs + Online + Suche. Gleiche Kanten wie Filter und Liste.
	var top_right := HBoxContainer.new()
	_place_right(top_right, HEAD_Y, HEAD_H)
	top_right.add_theme_constant_override("separation", 8)
	add_child(top_right)

	_tab_downloaded = _make_toggle("Heruntergeladen", 15)
	_tab_downloaded.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_downloaded.pressed.connect(func(): _set_collection_mode(false))
	top_right.add_child(_tab_downloaded)

	_tab_collections = _make_toggle("Sammlungen", 15)
	_tab_collections.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_collections.pressed.connect(func(): _set_collection_mode(true))
	top_right.add_child(_tab_collections)
	_style_tabs()

	_tab_online = Button.new()
	_tab_online.text = "Online"
	_tab_online.tooltip_text = "Maps online suchen und laden"
	_tab_online.icon = _download_icon()
	_tab_online.custom_minimum_size = Vector2(0, HEAD_H)
	_tab_online.add_theme_font_size_override("font_size", 15)
	_tab_online.add_theme_constant_override("h_separation", 8)
	UiTheme.style_ghost_button(_tab_online, 10)
	_tab_online.pressed.connect(_open_download_panel)
	top_right.add_child(_tab_online)

	# Filter-Reihe: Anzahl links, Sterne-Chips + Sortierung rechtsbuendig.
	var filter_row := HBoxContainer.new()
	_place_right(filter_row, FILTER_Y, FILTER_H)
	filter_row.add_theme_constant_override("separation", 6)
	add_child(filter_row)

	_count_label = Label.new()
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", COL_DIM)
	filter_row.add_child(_count_label)
	for fi in STAR_FILTERS.size():
		var chip := _make_toggle(STAR_FILTERS[fi][0], 13, 16)
		chip.custom_minimum_size = Vector2(0, FILTER_H)
		chip.pressed.connect(func():
			_star_filter = fi
			_restyle_star_chips()
			_refresh_filter(_search.text))
		filter_row.add_child(chip)
		_star_chips.append(chip)
	_sv_chip = _make_toggle("SV", 13, 16)
	_sv_chip.custom_minimum_size = Vector2(0, FILTER_H)
	_sv_chip.tooltip_text = "Nur Maps mit Scroll-Velocity-Wechseln (SV)"
	_sv_chip.pressed.connect(func():
		_sv_filter = not _sv_filter
		_restyle_star_chips()
		_refresh_filter(_search.text))
	filter_row.add_child(_sv_chip)
	_restyle_star_chips()
	var sort := OptionButton.new()
	sort.add_item("Titel", 0)
	sort.add_item("Sterne aufsteigend", 1)
	sort.add_item("Sterne absteigend", 2)
	sort.select(_sort_mode)
	sort.tooltip_text = "Sortierung"
	sort.fit_to_longest_item = false
	sort.custom_minimum_size = Vector2(120, FILTER_H)
	sort.add_theme_font_size_override("font_size", 13)
	sort.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	sort.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	sort.add_theme_stylebox_override("pressed", _toggle_box(false, 10, true))
	sort.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	sort.add_theme_color_override("font_color", COL_TEXT)
	sort.item_selected.connect(func(i):
		_sort_mode = i
		_refresh_filter(_search.text))
	filter_row.add_child(sort)

	# Chip-Reihe fuer Sammlungen (nur im Collections-Modus sichtbar).
	_chips_row = HBoxContainer.new()
	_place_right(_chips_row, CHIPS_Y, CHIPS_H)
	_chips_row.alignment = BoxContainer.ALIGNMENT_END
	_chips_row.add_theme_constant_override("separation", 6)
	_chips_row.visible = false
	add_child(_chips_row)

	_search = LineEdit.new()
	_search.placeholder_text = "Map suchen"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(140, HEAD_H)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	var search_focus := _toggle_box(false, 10, true)
	search_focus.border_color = Color(COL_ACCENT, 0.55)
	_search.add_theme_stylebox_override("focus", search_focus)
	_search.text_changed.connect(_refresh_filter)
	top_right.add_child(_search)


## Rechte Spalte: feste Breite RIGHT_W, rechter Rand M (Toolbar = Liste).
func _place_right(c: Control, y: float, h: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -M - RIGHT_W
	c.offset_right = -M
	c.offset_top = y
	c.offset_bottom = y + h


func _square_margins(b: Button) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := b.get_theme_stylebox(st) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 0
			sb.content_margin_right = 0


## Ein Stil fuer aktiv (Akzent-Toenung, Akzentschrift), einer fuer inaktiv (Ghost).
func _toggle_box(active: bool, radius: int, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if active:
		sb.bg_color = Color(COL_ACCENT, 0.24 if hover else 0.16)
		sb.border_color = Color(COL_ACCENT, 0.60)
	else:
		sb.bg_color = Color(1, 1, 1, 0.09 if hover else 0.04)
		sb.border_color = Color(1, 1, 1, 0.22 if hover else 0.12)
	return sb


func _make_toggle(text: String, font_size: int, radius: int = 10) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.set_meta("radius", radius)
	UiTheme._attach_sounds(b)
	_apply_toggle(b, false)
	return b


func _apply_toggle(b: Button, active: bool) -> void:
	var r: int = b.get_meta("radius", 10)
	var n := _toggle_box(active, r)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _toggle_box(active, r, true))
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := COL_ACCENT if active else COL_DIM
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_hover_color", COL_ACCENT if active else COL_TEXT)


## Download-Symbol (Pfeil nach unten auf Linie), einmal gezeichnet.
var _dl_icon_tex: ImageTexture
func _download_icon() -> ImageTexture:
	if _dl_icon_tex == null:
		_dl_icon_tex = _line_icon(16, [
			[Vector2(8, 2), Vector2(8, 10.5)], [Vector2(4.5, 7.5), Vector2(8, 11)],
			[Vector2(11.5, 7.5), Vector2(8, 11)], [Vector2(3, 14), Vector2(13, 14)]])
	return _dl_icon_tex


## Chevron links (dir -1) / rechts (dir 1) fuer die Diff-Auswahl.
func _chevron_icon(dir: int) -> ImageTexture:
	var a := 6.0 if dir > 0 else 10.0
	var b := 10.0 if dir > 0 else 6.0
	return _line_icon(16, [[Vector2(a, 3.5), Vector2(b, 8)], [Vector2(b, 8), Vector2(a, 12.5)]])


## Kleines Linien-Icon (weiss, ~1,6 px, kantengeglaettet) aus Segmenten.
func _line_icon(size: int, segs: Array) -> ImageTexture:
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
			var al := clampf(half_w - d + 0.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, al))
	return ImageTexture.create_from_image(img)


func _build_info_panel() -> void:
	# Hoehe folgt dem Inhalt: kein leerer Glasbereich unter der Bestenliste.
	var panel := PanelContainer.new()
	panel.position = Vector2(M, HEAD_Y + HEAD_H + M)
	panel.custom_minimum_size = Vector2(INFO_W, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.glass_box(18, 0.5))
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, M)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_title_label = _add_label(vb, "", 26, COL_TEXT)
	_title_label.add_theme_font_override("font", UiTheme.heading_font(1))
	var by := VBoxContainer.new()
	by.add_theme_constant_override("separation", 0)
	vb.add_child(by)
	_artist_label = _add_label(by, "", 15, COL_TEXT.darkened(0.12))
	_mapper_label = _add_label(by, "", 13, COL_DIM)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	vb.add_child(gap)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	vb.add_child(diff_row)
	var prev := _icon_button(_chevron_icon(-1), "Vorherige Schwierigkeit")
	prev.pressed.connect(func(): _cycle_difficulty(-1))
	diff_row.add_child(prev)
	_diff_label = Label.new()
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_diff_label.add_theme_font_size_override("font_size", 16)
	_diff_label.add_theme_color_override("font_color", COL_TEXT)
	diff_row.add_child(_diff_label)
	var next := _icon_button(_chevron_icon(1), "Naechste Schwierigkeit")
	next.pressed.connect(func(): _cycle_difficulty(1))
	diff_row.add_child(next)

	# Diff-Farbbalken: ein Segment pro Difficulty in Sternfarbe, Auswahl hell.
	# Einziger Ort mit Sternfarbe im Panel.
	_diff_bar = HBoxContainer.new()
	_diff_bar.custom_minimum_size = Vector2(0, 8)
	_diff_bar.add_theme_constant_override("separation", 4)
	vb.add_child(_diff_bar)

	# Sterne + BPM + Laenge als ruhige Glas-Chips in einer Reihe.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	vb.add_child(chip_row)
	_star_label = _info_chip(chip_row)
	_bpm_label = _info_chip(chip_row)
	_len_label = _info_chip(chip_row)

	_stats_label = _add_label(vb, "", 14, COL_DIM)
	_maxpp_label = _add_label(vb, "", 14, UiTheme.ACCENT2)

	var play := Button.new()
	play.text = "Spielen"
	play.custom_minimum_size = Vector2(0, 54)
	play.add_theme_font_size_override("font_size", 22)
	UiTheme.style_button(play, true)
	play.add_theme_font_override("font", UiTheme.heading_font(4))
	# Hover-Glow: weicher Akzent-Schein statt hartem Farbsprung.
	var play_hover := play.get_theme_stylebox("hover") as StyleBoxFlat
	if play_hover != null:
		play_hover = play_hover.duplicate()
		play_hover.shadow_color = Color(COL_ACCENT, 0.35)
		play_hover.shadow_size = 14
		play_hover.shadow_offset = Vector2.ZERO
		play.add_theme_stylebox_override("hover", play_hover)
		play.add_theme_stylebox_override("focus", play_hover)
	play.pressed.connect(_on_play_pressed)
	vb.add_child(play)
	_play_btn = play

	# Mods + Sammlung: No-Fail als Schalter, Sammlung als Ghost-Button.
	var mods_row := HBoxContainer.new()
	mods_row.add_theme_constant_override("separation", 8)
	vb.add_child(mods_row)

	var nf := CheckButton.new()
	nf.text = "No-Fail"
	nf.tooltip_text = "Kein Abbruch bei leerer Lebensleiste"
	nf.focus_mode = Control.FOCUS_NONE
	nf.button_pressed = _nf_enabled
	nf.custom_minimum_size = Vector2(0, 40)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nf.add_theme_font_size_override("font_size", 14)
	var nf_box := _toggle_box(false, 10)
	nf.add_theme_stylebox_override("normal", nf_box)
	nf.add_theme_stylebox_override("pressed", nf_box)
	nf.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	nf.add_theme_stylebox_override("hover_pressed", _toggle_box(false, 10, true))
	nf.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		nf.add_theme_color_override(fc, COL_TEXT)
	UiTheme._attach_sounds(nf)
	nf.toggled.connect(_on_nf_toggled)
	mods_row.add_child(nf)
	_nf_btn = nf

	var sv := CheckButton.new()
	sv.text = "SV"
	sv.tooltip_text = "Jede Map mit Tempowechseln"
	sv.focus_mode = Control.FOCUS_NONE
	sv.button_pressed = _sv_enabled
	sv.custom_minimum_size = Vector2(0, 40)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_font_size_override("font_size", 14)
	var sv_box := _toggle_box(false, 10)
	sv.add_theme_stylebox_override("normal", sv_box)
	sv.add_theme_stylebox_override("pressed", sv_box)
	sv.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	sv.add_theme_stylebox_override("hover_pressed", _toggle_box(false, 10, true))
	sv.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		sv.add_theme_color_override(fc, COL_TEXT)
	UiTheme._attach_sounds(sv)
	sv.toggled.connect(_on_sv_toggled)
	mods_row.add_child(sv)
	_sv_btn = sv

	var coll_btn := Button.new()
	coll_btn.text = "+ Sammlung"
	coll_btn.tooltip_text = "Map zu einer Sammlung hinzufuegen"
	coll_btn.custom_minimum_size = Vector2(0, 40)
	coll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_btn.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(coll_btn, 10)
	coll_btn.pressed.connect(_open_collection_popup)
	mods_row.add_child(coll_btn)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 1, 1, 0.08)
	vb.add_child(sep)

	# BESTE SCORES: Top 5 dieser Diff (pp + Datum) + Replay-Zugriff.
	var lb_head := HBoxContainer.new()
	lb_head.add_theme_constant_override("separation", 8)
	lb_head.custom_minimum_size = Vector2(0, 28)
	vb.add_child(lb_head)
	var lb_title := Label.new()
	lb_title.text = "BESTE SCORES"
	lb_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lb_title.add_theme_font_size_override("font_size", 13)
	lb_title.add_theme_color_override("font_color", COL_DIM)
	lb_head.add_child(lb_title)
	_replay_btn = Button.new()
	_replay_btn.text = "Replay"
	_replay_btn.custom_minimum_size = Vector2(0, 28)
	_replay_btn.add_theme_font_size_override("font_size", 12)
	UiTheme.style_ghost_button(_replay_btn, 8)
	_replay_btn.visible = false
	_replay_btn.pressed.connect(_watch_replay)
	lb_head.add_child(_replay_btn)

	_lb_box = VBoxContainer.new()
	_lb_box.add_theme_constant_override("separation", 6)
	vb.add_child(_lb_box)


## Buehne in der Mitte: grosses Cover (abgerundet, Schatten), Vorschau-Linie,
## Spektrum der Vorschau-Musik. Passt sich der freien Breite an.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.anchor_right = 1.0
	_stage.anchor_bottom = 1.0
	_stage.offset_left = M + INFO_W + M
	_stage.offset_right = -(M + RIGHT_W + M)
	_stage.offset_top = HEAD_Y + HEAD_H + M
	_stage.offset_bottom = -M
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_stage_shadow = Panel.new()
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.35)
	sh.set_corner_radius_all(20)
	sh.shadow_color = Color(0, 0, 0, 0.45)
	sh.shadow_size = 28
	sh.shadow_offset = Vector2(0, 10)
	_stage_shadow.add_theme_stylebox_override("panel", sh)
	_stage_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_shadow)

	# Abgerundete Maske: Panel zeichnet nur Alpha, das Cover wird darauf geclippt.
	_stage_mask = Panel.new()
	var mk := StyleBoxFlat.new()
	mk.bg_color = Color.WHITE
	mk.set_corner_radius_all(20)
	mk.anti_aliasing = true
	_stage_mask.add_theme_stylebox_override("panel", mk)
	_stage_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_stage_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_mask)
	_cover = TextureRect.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_mask.add_child(_cover)
	# Feiner Glasrand ueber dem Cover.
	var rim := Panel.new()
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0, 0, 0, 0)
	rb.set_corner_radius_all(20)
	rb.set_border_width_all(1)
	rb.border_color = Color(1, 1, 1, 0.14)
	rim.add_theme_stylebox_override("panel", rb)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_mask.add_child(rim)

	# Vorschau-Fortschritt: duenne cyanfarbene Linie unter dem Cover.
	_progress_bg = Control.new()
	_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_progress_bg)
	var track := ColorRect.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.color = Color(1, 1, 1, 0.08)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(track)
	_progress_fill = ColorRect.new()
	_progress_fill.position = Vector2.ZERO
	_progress_fill.size = Vector2(0, 3)
	_progress_fill.color = COL_ACCENT
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)

	# Spektrum der Vorschau-Musik (ruht bei Stille von selbst).
	_stage_viz = AudioVisualizer.new()
	_stage_viz.name = "VisualizerSlot"
	_stage_viz.bars = 48
	_stage_viz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_viz.modulate.a = 0.5
	_stage_viz.set_color(COL_ACCENT)
	_stage.add_child(_stage_viz)

	_stage.resized.connect(_layout_stage)
	_layout_stage.call_deferred()


func _layout_stage() -> void:
	var avail := _stage.size
	var w := minf(avail.x - 2.0 * M, 760.0)
	var viz_h := 64.0
	var gap := 18.0
	var h := w * 9.0 / 16.0
	var max_h := avail.y - (gap + 3.0 + gap + viz_h)
	if h > max_h:
		h = max_h
		w = h * 16.0 / 9.0
	var fits := w >= 240.0
	for c in _stage.get_children():
		(c as CanvasItem).visible = fits
	if not fits:
		return
	var total := h + gap + 3.0 + gap + viz_h
	# Optisch etwas ueber der Mitte: ruhiger Schwerpunkt.
	var top := maxf((avail.y - total) * 0.42, 0.0)
	var x := (avail.x - w) * 0.5
	_stage_shadow.position = Vector2(x, top)
	_stage_shadow.size = Vector2(w, h)
	_stage_mask.position = Vector2(x, top)
	_stage_mask.size = Vector2(w, h)
	_progress_bg.position = Vector2(x, top + h + gap)
	_progress_bg.size = Vector2(w, 3)
	_stage_viz.position = Vector2(x, top + h + gap + 3.0 + gap)
	_stage_viz.size = Vector2(w, viz_h)


func _info_chip(parent: Node) -> Label:
	var p := PanelContainer.new()
	var sb := _rounded_box(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0.10), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_TEXT)
	p.add_child(l)
	return l


func _build_list() -> void:
	# Maske mit Alpha-Verlauf: Karten blenden oben/unten weich aus statt hart
	# abzuschneiden (clip_children nutzt das Alpha der Maske).
	_list_grad = Gradient.new()
	_list_grad.offsets = PackedFloat32Array([0.0, 0.02, 0.98, 1.0])
	_list_grad.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = _list_grad
	gtex.width = 4
	gtex.height = 512
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	_list_mask = TextureRect.new()
	_list_mask.texture = gtex
	_list_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_list_mask.stretch_mode = TextureRect.STRETCH_SCALE
	_list_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_list_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Karten-Kante = Toolbar-Kante: links Innenabstand + Hover-Slide, rechts
	# Scrollbalken im Aussenrand.
	_list_mask.anchor_left = 1.0
	_list_mask.anchor_right = 1.0
	_list_mask.anchor_bottom = 1.0
	_list_mask.offset_left = -M - RIGHT_W - LIST_PAD - CARD_SLIDE
	_list_mask.offset_right = -LIST_EDGE
	_list_mask.offset_top = LIST_TOP
	_list_mask.offset_bottom = -(M - LIST_PAD)
	_list_mask.resized.connect(_update_list_fade)
	add_child(_list_mask)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_mask.add_child(_scroll)

	# Innenabstand, damit Glow/Schatten und der Hover-Slide nach links nicht
	# vom Scroll-Clip abgeschnitten werden (vorher: oberste Karte gekappt).
	var sbw := int(_scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", LIST_PAD)
	pad.add_theme_constant_override("margin_bottom", LIST_PAD)
	pad.add_theme_constant_override("margin_left", LIST_PAD + int(CARD_SLIDE))
	pad.add_theme_constant_override("margin_right", maxi(M - LIST_EDGE - sbw, 0))
	_scroll.add_child(pad)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	pad.add_child(_list_box)


## Fade-Laenge in Pixeln konstant halten (Gradient-Offsets nach Hoehe).
func _update_list_fade() -> void:
	var h := maxf(_list_mask.size.y, 1.0)
	var f := clampf(float(LIST_PAD) / h, 0.0, 0.45)
	_list_grad.offsets = PackedFloat32Array([0.0, f, 1.0 - f, 1.0])


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

func _style_tabs() -> void:
	_apply_toggle(_tab_collections, _collection_mode)
	_apply_toggle(_tab_downloaded, not _collection_mode)


func _set_collection_mode(on: bool) -> void:
	_collection_mode = on
	if on and _active_collection == "":
		var names := CollectionStore.list_names()
		_active_collection = names[0] if not names.is_empty() else ""
	_chips_row.visible = on
	_list_mask.offset_top = (CHIPS_Y + CHIPS_H) if on else LIST_TOP
	_style_tabs()
	_rebuild_chips()
	_refresh_filter(_search.text)


func _rebuild_chips() -> void:
	for c in _chips_row.get_children():
		c.queue_free()
	if not _collection_mode:
		return
	var names := CollectionStore.list_names()
	if names.is_empty():
		var hint := Label.new()
		hint.text = "Keine Sammlungen — im Info-Panel \"+ Sammlung\" nutzen"
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", COL_DIM)
		_chips_row.add_child(hint)
		return
	var have := {}
	for ms in _library.mapsets:
		have[ms.osz_path.get_file()] = true
	for name in names:
		var present := 0
		for f in CollectionStore.maps_in(name):
			if have.has(f):
				present += 1
		var chip := _make_toggle("%s (%d)" % [name, present], 13, 15)
		chip.custom_minimum_size = Vector2(0, CHIPS_H)
		_apply_toggle(chip, name == _active_collection)
		chip.pressed.connect(func():
			_active_collection = name
			_rebuild_chips()
			_refresh_filter(_search.text))
		_chips_row.add_child(chip)
	# Aktive Sammlung loeschen (kleines x am Ende der Reihe).
	if _active_collection != "":
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = tr("Sammlung \"%s\" löschen") % _active_collection
		del.custom_minimum_size = Vector2(CHIPS_H, CHIPS_H)
		del.add_theme_font_size_override("font_size", 13)
		UiTheme.style_ghost_button(del, 15)
		_square_margins(del)
		del.pressed.connect(func():
			CollectionStore.delete(_active_collection)
			var rest := CollectionStore.list_names()
			_active_collection = rest[0] if not rest.is_empty() else ""
			_rebuild_chips()
			_refresh_filter(_search.text))
		_chips_row.add_child(del)


## Overlay: gewaehlte Map in Sammlungen packen / entfernen / neue anlegen.
func _open_collection_popup() -> void:
	if _selected_set == null:
		return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", _rounded_box(Color(0.07, 0.07, 0.11, 0.98), 14))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = tr("\"%s\" in Sammlungen") % _selected_set.title
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	var boxes := VBoxContainer.new()
	vb.add_child(boxes)
	var fill_boxes := func():
		for c in boxes.get_children():
			c.queue_free()
		for name in CollectionStore.list_names():
			var cb := CheckBox.new()
			cb.text = name
			cb.button_pressed = CollectionStore.contains(name, _selected_set.osz_path)
			cb.toggled.connect(func(_on):
				CollectionStore.toggle(name, _selected_set.osz_path)
				_rebuild_chips())
			boxes.add_child(cb)
	fill_boxes.call()

	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 8)
	vb.add_child(new_row)
	var new_edit := LineEdit.new()
	new_edit.placeholder_text = "Neue Sammlung…"
	new_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(new_edit)
	var new_btn := Button.new()
	new_btn.text = "Anlegen"
	new_btn.pressed.connect(func():
		if CollectionStore.create(new_edit.text):
			CollectionStore.toggle(new_edit.text.strip_edges(), _selected_set.osz_path)
			new_edit.text = ""
			fill_boxes.call()
			_rebuild_chips())
	new_row.add_child(new_btn)

	var close := Button.new()
	close.text = "Schließen"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func():
		overlay.queue_free()
		_refresh_filter(_search.text))
	vb.add_child(close)


# ---------------------------------------------------------------------------
# Liste / Karten
# ---------------------------------------------------------------------------

func _restyle_star_chips() -> void:
	for i in _star_chips.size():
		_apply_toggle(_star_chips[i], i == _star_filter)
	if _sv_chip != null:
		_apply_toggle(_sv_chip, _sv_filter)


## Gespeicherte Browser-Filter laden (nicht in Test-/Shot-Laeufen: die brauchen den Standard).
func _load_browser_state() -> bool:
	var force := OS.get_cmdline_args().has("--browser-state")  # Harness: Wiederherstellung pruefen
	if not force and (Settings.is_test_run() or DisplayServer.get_name() == "headless"):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(BROWSER_STATE_PATH) == OK:
		_star_filter = clampi(int(cfg.get_value("browser", "star_filter", 0)), 0, STAR_FILTERS.size() - 1)
		_sv_filter = bool(cfg.get_value("browser", "sv_filter", false))
		_sort_mode = clampi(int(cfg.get_value("browser", "sort_mode", 0)), 0, 2)
		_saved_search = str(cfg.get_value("browser", "search", ""))
		var coll := str(cfg.get_value("browser", "collection", ""))
		_active_collection = coll if CollectionStore.list_names().has(coll) else ""
		_collection_mode = bool(cfg.get_value("browser", "collection_mode", false))
	return true


func _save_browser_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("browser", "star_filter", _star_filter)
	cfg.set_value("browser", "sv_filter", _sv_filter)
	cfg.set_value("browser", "sort_mode", _sort_mode)
	cfg.set_value("browser", "search", _search.text if _search != null else "")
	cfg.set_value("browser", "collection", _active_collection)
	cfg.set_value("browser", "collection_mode", _collection_mode)
	cfg.save(BROWSER_STATE_PATH)


func _refresh_filter(query: String) -> void:
	if _state_ready:
		_save_browser_state()
	var q := query.strip_edges().to_lower()
	var lo: float = STAR_FILTERS[_star_filter][1]
	var hi: float = STAR_FILTERS[_star_filter][2]
	_filtered.clear()
	for ms in _library.mapsets:
		if q != "" and not ms.search_haystack().contains(q):
			continue
		if _collection_mode:
			if _active_collection == "" or not CollectionStore.contains(_active_collection, ms.osz_path):
				continue
		if _sv_filter and not ms.has_sv():
			continue
		# Sterne-Filter: Set passt, wenn IRGENDEINE Diff im Bereich liegt.
		if _star_filter != 0:
			var in_range := false
			for i in ms.difficulty_count():
				var st := ms.stars_at(i)
				if st >= lo and st < hi:
					in_range = true
					break
			if not in_range:
				continue
		_filtered.append(ms)
	match _sort_mode:
		1:
			_filtered.sort_custom(func(a, b): return a.max_stars() < b.max_stars())
		2:
			_filtered.sort_custom(func(a, b): return a.max_stars() > b.max_stars())
	_rebuild_cards()
	var count_txt := tr("%d Maps") % _filtered.size()
	if _collection_mode and _active_collection != "":
		# Eintraege, deren .osz nicht mehr im maps-Ordner liegt, klar ausweisen.
		var missing := 0
		var have := {}
		for ms2 in _library.mapsets:
			have[ms2.osz_path.get_file()] = true
		for f in CollectionStore.maps_in(_active_collection):
			if not have.has(f):
				missing += 1
		if missing > 0:
			count_txt += tr("  ·  %d fehlen (gelöscht?)") % missing
	_count_label.text = count_txt


func _process(delta: float) -> void:
	_beat_react(delta)
	_loudness_step()
	_prepare_step()
	_game_preload_step()
	# Thumbnails haeppchenweise laden (Zeitbudget pro Frame) — Browser bleibt fluessig.
	var t_end := Time.get_ticks_usec() + THUMB_BUDGET_USEC
	var budget := 2
	while (budget > 0 or Time.get_ticks_usec() < t_end) and not _thumb_queue.is_empty():
		var job: Dictionary = _thumb_queue.pop_front()
		var bg_rect: TextureRect = job.bg
		if not is_instance_valid(bg_rect):
			continue
		var tex: Texture2D = (job.ms as MapSet).thumb_texture()
		if tex != null:
			bg_rect.texture = tex
		budget -= 1
		if _thumb_queue.is_empty() and _perf_ready_t > 0:
			GameSession.perf_since("Browser: alle Thumbnails sichtbar (seit _ready)", _perf_ready_t)
			_perf_ready_t = 0


## Lautheitsmessung der Vorschau; nach >= 6 s Gain speichern und anwenden.
func _loudness_step() -> void:
	if not SongLoudness.is_measuring() or _preview == null or not _preview.playing:
		return
	SongLoudness.poll(_preview.volume_db)
	if SongLoudness.measured_sec() < SongLoudness.MIN_MEASURE_SEC:
		return
	var g := SongLoudness.measure_stop()
	if not is_nan(g):
		_preview_gain_db = g
		_preview_fade = create_tween()
		_preview_fade.tween_property(_preview, "volume_db", PREVIEW_DB + g, 0.5)


## Auswahl-Karte, Hintergrund und SPIELEN pulsen exakt auf dem Beat der
## Vorschau (BeatClock aus den Timing-Points, keine Spektrum-Verzoegerung).
## Keine Allokation: nur Skalare, Scale/Modulate bestehender Nodes.
func _beat_react(delta: float) -> void:
	var p := 0.0
	var t := _preview_ms()
	if t >= 0.0:
		_beat.update(t, delta)
		# Huellkurve aus der Beat-Phase (Downbeat voll, Zwischenschlaege leiser).
		p = _beat.beat_env
	if _bg != null:
		_bg.pivot_offset = _bg.size * 0.5
		var s := 1.0 + 0.015 * p
		_bg.scale = Vector2(s, s)
		var b := 0.34 + 0.04 * p
		_bg.modulate = Color(b, b, b + 0.06)
	var idx := _filtered.find(_selected_set)
	var card: Button = null
	if idx >= 0 and idx < _card_buttons.size() and is_instance_valid(_card_buttons[idx]):
		card = _card_buttons[idx]
	if card != _pulse_card:
		if _pulse_card != null and is_instance_valid(_pulse_card):
			_pulse_card.modulate = Color.WHITE
			var old_bg := _pulse_card.get_child(0) as TextureRect
			if old_bg != null:
				old_bg.self_modulate = Color.WHITE
		_pulse_card = card
	if card != null:
		var c := 1.0 + 0.04 * p
		card.modulate = Color(c, c, c)
		var cbg := card.get_child(0) as TextureRect
		if cbg != null:
			var g := 1.0 + 0.25 * p
			cbg.self_modulate = Color(g, g, g)
	# Glow der Auswahl atmet mit dem Beat (nur Skalar auf bestehender StyleBox).
	if _sel_box != null:
		var gs := 10 + int(round(6.0 * p))
		if _sel_box.shadow_size != gs:
			_sel_box.shadow_size = gs
	# SPIELEN: dezenter Beat-Puls (nur Helligkeit, kein Wackeln).
	if _play_btn != null:
		var pb := 1.0 + 0.08 * p
		_play_btn.self_modulate = Color(pb, pb, pb)
	# Vorschau-Fortschritt (Position im Song).
	if _progress_fill != null:
		var frac := 0.0
		if _preview != null and _preview.playing and _preview_len > 0.0:
			frac = clampf(_preview.get_playback_position() / _preview_len, 0.0, 1.0)
		var w := _progress_bg.size.x * frac
		if not is_equal_approx(_progress_fill.size.x, w):
			_progress_fill.size = Vector2(w, _progress_bg.size.y)


func _begin_game_preload() -> void:
	if not is_inside_tree():
		return
	var paths: Array[String] = []
	paths.append_array(GAME_SCENES)
	for d in GAME_ASSET_DIRS:
		for f in ResourceLoader.list_directory(d):
			var ext := f.get_extension().to_lower()
			if ext in ["obj", "webp", "png", "jpg", "glb", "tres", "res"]:
				paths.append(d.path_join(f))
	for p in paths:
		if _game_res.has(p) or _game_req.has(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p, "", true) == OK:
			_game_req.append(p)
	_game_preload_t = Time.get_ticks_usec()


func _game_preload_step() -> void:
	if _game_req.is_empty():
		return
	for p in _game_req.duplicate():
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_game_res[p] = ResourceLoader.load_threaded_get(p)
			_game_req.erase(p)
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_game_req.erase(p)
	if _game_req.is_empty() and _game_preload_t > 0:
		GameSession.perf_since("Browser: Gameplay-Szenen vorgeladen (Hintergrund)", _game_preload_t)
		_game_preload_t = 0


## Szenenwechsel ins Gameplay: vorgeladene PackedScene nutzen (laeuft der
## Ladevorgang noch, auf ihn warten statt doppelt zu laden).
func _change_to_game(path: String) -> void:
	if not _game_res.has(path) and _game_req.has(path):
		_game_req.erase(path)
		var r := ResourceLoader.load_threaded_get(path)
		if r != null:
			_game_res[path] = r
	var ps := _game_res.get(path) as PackedScene
	if ps != null:
		get_tree().change_scene_to_packed(ps)
	else:
		get_tree().change_scene_to_file(path)


## Auswahl im Hintergrund vorbereiten, sobald sie stabil ist; das Full-Res-
## Cover erst uebernehmen, wenn der Worker es dekodiert hat.
func _prepare_step() -> void:
	if _selected_set == null:
		return
	if _prep_due > 0 and Time.get_ticks_msec() >= _prep_due:
		_prep_due = 0
		var m := _selected_set.meta_at(_selected_diff)
		GameSession.preload_selection(_selected_set.osz_path, str(m.get("audio_filename", "")),
			_selected_set.background_file, _selected_set.version_name_at(_selected_diff))
		_bg_wait_set = _selected_set
	if _bg_wait_set != null and OszImporter.is_prepared(_bg_wait_set.osz_path):
		var target := _bg_wait_set
		_bg_wait_set = null
		_load_fullres_bg(target)


func _rebuild_cards() -> void:
	_scores_cfg = ConfigFile.new()
	if _scores_cfg.load(ScoreStore.PATH) != OK:
		_scores_cfg = null
	_pulse_card = null
	_thumb_queue.clear()
	for c in _list_box.get_children():
		c.queue_free()
	_card_buttons.clear()
	for i in _filtered.size():
		var card := _make_card(_filtered[i])
		# Halter (vom VBox gelayoutet) -> Slider (frei verschiebbar fuer den
		# Hover-Slide) -> [Glow-Panel hinter der Karte, Karte].
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0, CARD_H)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slider := Control.new()
		slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(slider)
		var glow := Panel.new()
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.visible = false
		slider.add_child(glow)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slider.add_child(card)
		_list_box.add_child(holder)
		_card_buttons.append(card)
		card.mouse_entered.connect(_slide_card.bind(card, true))
		card.mouse_exited.connect(_slide_card.bind(card, false))
	_scores_cfg = null
	if _selected_set != null:
		_apply_card_highlight()


## Hover-Slide: Karte gleitet 8 px nach links (ausgewaehlte bleibt draussen).
func _slide_card(card: Button, hovered: bool) -> void:
	if not is_instance_valid(card):
		return
	var slider := card.get_parent() as Control
	if slider == null:
		return
	var idx := _card_buttons.find(card)
	var is_sel := idx >= 0 and idx < _filtered.size() and _filtered[idx] == _selected_set
	_update_card_frame(card, hovered, is_sel)
	var target := -CARD_SLIDE if (hovered or is_sel) else 0.0
	if is_equal_approx(slider.offset_left, target):
		return
	if slider.has_meta("tw"):
		var old := slider.get_meta("tw") as Tween
		if old != null and old.is_valid():
			old.kill()
	var tw := slider.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(slider, "offset_left", target, 0.16)
	tw.tween_property(slider, "offset_right", target, 0.16)
	slider.set_meta("tw", tw)


## Rechtsklick auf eine Karte: .osz nach Bestaetigung loeschen.
func _confirm_delete(ms: MapSet) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Map löschen"
	dlg.dialog_text = tr("\"%s — %s\" wirklich löschen?\nDie .osz-Datei wird vom Datenträger entfernt.") % [ms.artist, ms.title]
	dlg.ok_button_text = "Löschen"
	dlg.cancel_button_text = "Abbrechen"
	add_child(dlg)
	dlg.confirmed.connect(func():
		if FileAccess.file_exists(ms.osz_path):
			DirAccess.remove_absolute(ms.osz_path)
		var was_selected := _selected_set == ms
		_library.scan()
		_refresh_filter(_search.text)
		if was_selected and not _filtered.is_empty():
			_select_set(_filtered[0], 0)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _sv_badge() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bb := UiTheme.solid_box(Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.9), 8)
	bb.content_margin_left = 7
	bb.content_margin_right = 7
	bb.content_margin_top = 2
	bb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", bb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.tooltip_text = "Enthält Scroll-Velocity-Wechsel (SV)"
	var l := Label.new()
	l.text = "SV"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.03, 0.05, 0.08))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	return pc


func _make_card(ms: MapSet) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	# Schmaler Diff-Streifen in Sternfarbe (einziger Farbakzent der Karte).
	var base := _card_box(COL_CARD, _star_color(ms.max_stars()))
	for st in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(st, base)
	card.pressed.connect(func(): _on_card_pressed(ms))
	# Rechtsklick: Map nach Bestaetigung vom Datenträger loeschen.
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed \
				and e.button_index == MOUSE_BUTTON_RIGHT:
			_confirm_delete(ms))

	# Cover als Kartenhintergrund — LAZY: Thumbnails werden ueber Frames
	# verteilt geladen (UI erscheint sofort, kein Ruckeln). Kind 0 (Beat-Puls).
	# Shader: abgerundete Ecken + deckender Verlauf links (Text lesbar).
	var card_bg := TextureRect.new()
	card_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_bg.offset_left = 4
	card_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_bg.material = _card_cover_mat
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_bg.resized.connect(_on_card_bg_resized.bind(card_bg))
	card.add_child(card_bg)
	_thumb_queue.append({ "ms": ms, "bg": card_bg })

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 20
	hb.offset_right = -16
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	var t := Label.new()
	t.text = "%s - %s" % [ms.artist, ms.title]
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", COL_TEXT)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 1)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	var m := Label.new()
	m.text = "%s  ·  %s  ·  %s" % [
		_stars_text(ms.max_stars()), _format_time(ms.length_ms()), ms.creator]
	m.add_theme_font_size_override("font_size", 13)
	m.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
	m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(m)

	# SV-Badge: Set enthaelt mindestens eine Diff mit echter SV.
	if ms.has_sv():
		hb.add_child(_sv_badge())

	# Grade-Badge des besten Scores: klein, fester Platz, Notenfarbe.
	var badge := _best_grade_badge(ms)
	if badge != "":
		var g := Label.new()
		g.text = badge
		g.custom_minimum_size = Vector2(28, 0)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.add_theme_font_override("font", UiTheme.heading_font(0))
		g.add_theme_font_size_override("font_size", 18)
		g.add_theme_color_override("font_color", GRADE_COLOR.get(badge.left(1), COL_TEXT))
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(g)

	# Rahmen oben drauf (Auswahl = ACCENT, Hover = hell, sonst fein).
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_idle)
	card.add_child(frame)
	card.set_meta("frame", frame)

	return card

func _best_grade_badge(ms: MapSet) -> String:
	if _scores_cfg == null:
		return ""
	for i in range(ms.difficulty_count() - 1, -1, -1):
		# Gleiche Abfrage wie ScoreStore.best(), aber ohne scores.cfg pro Aufruf neu zu lesen.
		var best = _scores_cfg.get_value("scores", ScoreStore._key(ms.osz_path, ms.version_name_at(i)), {})
		if best is Dictionary and not best.is_empty():
			return str(best.get("grade", ""))
	return ""


# ---------------------------------------------------------------------------
# Auswahl / Play
# ---------------------------------------------------------------------------

func _select_initial() -> void:
	var last := GameSession.load_last_played()
	if not last.is_empty():
		for ms in _filtered:
			if ms.osz_path == last.osz_path:
				_select_set(ms, clampi(int(last.difficulty_index), 0, ms.difficulty_count() - 1))
				_scroll_to_selected.call_deferred()
				return
	if not _filtered.is_empty():
		_select_set(_filtered[0], 0)


func _on_card_pressed(ms: MapSet) -> void:
	if _selected_set == ms:
		_on_play_pressed()
		return
	_select_set(ms, ms.difficulty_count() - 1 if ms.difficulty_count() > 0 else 0)


func _select_set(ms: MapSet, diff_index: int) -> void:
	_perf_select_t = Time.get_ticks_usec()
	_selected_set = ms
	_selected_diff = clampi(diff_index, 0, ms.difficulty_count() - 1)
	_update_info_panel()
	Sfx.select_chime()
	_play_preview()


func _cycle_difficulty(dir: int) -> void:
	if _selected_set == null:
		return
	_selected_diff = wrapi(_selected_diff + dir, 0, _selected_set.difficulty_count())
	_update_info_panel()


func _update_info_panel() -> void:
	if _selected_set == null:
		return
	var m := _selected_set.meta_at(_selected_diff)
	# Sofort das schnelle Thumbnail zeigen, das Full-Res-Cover einen Frame
	# spaeter nachladen (Klicks fuehlen sich sofort an).
	var quick := _selected_set.thumb_texture()
	_bg.texture = quick
	_cover.texture = quick
	_prep_due = Time.get_ticks_msec() + PREPARE_DELAY_MS
	_bg_wait_set = null
	_title_label.text = _selected_set.title
	_artist_label.text = _selected_set.artist
	_mapper_label.text = tr("Map von %s") % _selected_set.creator
	var is_mania := int(m.get("mode", 0)) == 3
	var keys := int(round(float(m.get("cs", 4.0))))
	_diff_label.text = _selected_set.version_name_at(_selected_diff).strip_edges() 		+ (("  ·  %dK" % keys) if is_mania else "")
	_star_label.text = _stars_text(_selected_set.stars_at(_selected_diff))
	var notes := tr("%d Noten") % int(m.get("notes", 0))
	var od := "OD " + UiTheme.fmt_num(float(m.get("od", 0.0)))
	if is_mania:
		# Mania: CS ist die Tastenzahl, AR gibt es nicht.
		_stats_label.text = tr("%s  ·  %d Tasten  ·  %s") % [notes, keys, od]
	else:
		_stats_label.text = "%s  ·  CS %s  ·  AR %s  ·  %s" % [notes,
			UiTheme.fmt_num(float(m.get("cs", 0.0))), UiTheme.fmt_num(float(m.get("ar", 0.0))), od]
	_bpm_label.text = "%s BPM" % _bpm_text(_selected_set, _selected_diff)
	_len_label.text = _format_time(float(m.get("duration_ms", 0.0)))
	_rebuild_diff_bar()
	if _preview_set == _selected_set:
		_setup_beat_clock()
	_update_max_pp(m)
	# BESTE SCORES: Top 5 dieser Difficulty als cleane Rows.
	for c in _lb_box.get_children():
		c.queue_free()
	# Eigene + Scores von Mitspielern (Multiplayer-Sync), beste zuerst.
	var tops := ScoreStore.top_scores_all(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff), 5)
	if tops.is_empty():
		var empty := Label.new()
		empty.text = "Noch kein Score — spiel die Map!"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", COL_DIM)
		_lb_box.add_child(empty)
	for i in tops.size():
		_lb_box.add_child(_score_row(i, tops[i]))
	# Replay-Button nur zeigen, wenn fuer diese Diff ein Replay existiert.
	if _replay_btn != null:
		_replay_btn.visible = int(m.get("mode", 0)) == 3 			and ReplayStore.exists(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff))
	_apply_card_highlight()


## Auswahl-Hervorhebung: Rahmen immer in ACCENT + weicher Glow dahinter.
## Sternfarbe bleibt im schmalen Diff-Streifen.
func _apply_card_highlight() -> void:
	_sel_box = null
	for i in _card_buttons.size():
		var card := _card_buttons[i]
		if not is_instance_valid(card):
			continue
		var is_sel := _filtered[i] == _selected_set
		var glow := card.get_parent().get_child(0) as Panel
		if glow != null:
			glow.visible = is_sel
			if is_sel:
				glow.add_theme_stylebox_override("panel", _glow_box)
				_sel_box = _glow_box
		_slide_card(card, card.is_hovered())


## Rahmen-Stil je nach Zustand (geteilte StyleBoxen, keine Allokation).
func _update_card_frame(card: Button, hovered: bool, is_sel: bool) -> void:
	var frame := card.get_meta("frame", null) as Panel
	if frame == null:
		return
	var box := _frame_sel if is_sel else (_frame_hover if hovered else _frame_idle)
	frame.add_theme_stylebox_override("panel", box)


const _CARD_COVER_CODE := "shader_type canvas_item;
uniform vec2 rect_size = vec2(600.0, 76.0);
uniform float radius = 12.0;
uniform vec3 shade_col : source_color = vec3(0.06, 0.06, 0.09);
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float x = clamp(local.x / rect_size.x, 0.0, 1.0);
	c.rgb = mix(c.rgb, shade_col, mix(0.93, 0.30, smoothstep(0.35, 1.0, x)));
	vec2 q = abs(local - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
"


## Alle Karten teilen ein Material; nur bei Layout-Aenderung neu setzen.
func _on_card_bg_resized(bg: TextureRect) -> void:
	if bg.size.x > 0.0 and not bg.size.is_equal_approx(_card_cover_size):
		_card_cover_size = bg.size
		_card_cover_mat.set_shader_parameter("rect_size", bg.size)


func _init_card_styles() -> void:
	var sh := Shader.new()
	sh.code = _CARD_COVER_CODE
	_card_cover_mat = ShaderMaterial.new()
	_card_cover_mat.shader = sh
	_card_cover_mat.set_shader_parameter("radius", float(CARD_RADIUS))
	_frame_idle = _frame_box(Color(1, 1, 1, 0.07), 1)
	_frame_hover = _frame_box(Color(1, 1, 1, 0.24), 1)
	_frame_sel = _frame_box(COL_ACCENT, 2)
	_glow_box = StyleBoxFlat.new()
	_glow_box.bg_color = Color(0, 0, 0, 0)
	_glow_box.set_corner_radius_all(CARD_RADIUS)
	_glow_box.shadow_color = Color(COL_ACCENT, 0.22)
	_glow_box.shadow_size = 10
	_glow_box.shadow_offset = Vector2.ZERO


func _frame_box(col: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(CARD_RADIUS)
	sb.set_border_width_all(w)
	sb.border_color = col
	return sb


## Ein Segment pro Difficulty in Sternfarbe; Klick waehlt die Diff.
func _rebuild_diff_bar() -> void:
	for c in _diff_bar.get_children():
		c.queue_free()
	var n := _selected_set.difficulty_count()
	for i in n:
		var seg := ColorRect.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sel := i == _selected_diff
		seg.custom_minimum_size = Vector2(0, 8 if sel else 4)
		var col := _star_color(_selected_set.stars_at(i))
		seg.color = col.lightened(0.15) if sel else Color(col, 0.40)
		seg.tooltip_text = "%s  %s" % [_selected_set.version_name_at(i), _stars_text(_selected_set.stars_at(i))]
		seg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		seg.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_selected_diff = i
				_update_info_panel())
		_diff_bar.add_child(seg)


## BPM der Diff aus den roten Timing-Linien (einmal pro Diff, gecacht).
## Bereich "min–max", wenn die Map das Tempo wechselt.
func _bpm_text(ms: MapSet, diff: int) -> String:
	var key := ms.osz_path + "|" + ms.osu_filename_at(diff)
	if _bpm_cache.has(key):
		return str(_bpm_cache[key])
	var txt := "—"
	var lo := INF
	var hi := 0.0
	for tp in _timing_points(ms, diff):
		if tp.uninherited and tp.beat_length > 0.0:
			var b: float = 60000.0 / tp.beat_length
			lo = minf(lo, b)
			hi = maxf(hi, b)
	if hi > 0.0:
		txt = ("%d" % roundi(hi)) if roundi(lo) == roundi(hi) \
			else "%d–%d" % [roundi(lo), roundi(hi)]
	_bpm_cache[key] = txt
	return txt


## Timing-Points der Diff (einmal gelesen, gecacht) — fuer BPM und BeatClock.
func _timing_points(ms: MapSet, diff: int) -> Array:
	var key := ms.osz_path + "|" + ms.osu_filename_at(diff)
	if _tp_cache.has(key):
		return _tp_cache[key]
	var out: Array = []
	var bytes := OszImporter.read_file_bytes(ms.osz_path, ms.osu_filename_at(diff))
	if not bytes.is_empty():
		var in_tp := false
		for raw_line in bytes.get_string_from_utf8().split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("["):
				if in_tp:
					break
				in_tp = line == "[TimingPoints]"
				continue
			if not in_tp or line == "":
				continue
			var tp := OsuParser._parse_timing_line(line)
			if tp != null:
				out.append(tp)
	_tp_cache[key] = out
	return out


## Beat-Phase der Vorschau neu aufsetzen (bei Map- oder Diff-Wechsel).
func _setup_beat_clock() -> void:
	if _selected_set == null:
		return
	_beat.setup(_timing_points(_selected_set, _selected_diff))


## Hoerbare Position der Vorschau in ms (Mix-Puffer + Ausgabelatenz korrigiert).
func _preview_ms() -> float:
	if _preview == null or not _preview.playing:
		return -1.0
	return (_preview.get_playback_position() + AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()) * 1000.0


## Eine Leaderboard-Zeile: Rang, Grade, Score/Acc, pp, Datum.
func _score_row(rank: int, e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var num := Label.new()
	num.text = "#%d" % (rank + 1)
	num.custom_minimum_size = Vector2(24, 0)
	num.add_theme_font_size_override("font_size", 12)
	num.add_theme_color_override("font_color", COL_TEXT if rank == 0 else COL_DIM)
	row.add_child(num)
	var g := str(e.get("grade", "?"))
	var grade := Label.new()
	grade.text = g
	grade.custom_minimum_size = Vector2(28, 0)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.add_theme_font_size_override("font_size", 15)
	grade.add_theme_color_override("font_color", GRADE_COLOR.get(g.left(1), COL_TEXT))
	row.add_child(grade)
	var main := Label.new()
	var is_self := bool(e.get("is_self", true))
	main.text = "%s  ·  %s  ·  %dx" % [
		UiTheme.fmt_score(int(e.get("score", 0))),
		UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0), int(e.get("max_combo", 0))]
	if not is_self:
		# Mitspieler: Name vorne, Combo weglassen (Platz).
		main.text = "%s  ·  %s  ·  %s" % [str(e.get("player", "?")),
			UiTheme.fmt_score(int(e.get("score", 0))),
			UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0)]
		main.tooltip_text = tr("Score von %s (Multiplayer)") % str(e.get("player", "?"))
		main.mouse_filter = Control.MOUSE_FILTER_PASS
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main.add_theme_font_size_override("font_size", 13)
	main.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(main)
	var pp_lbl := Label.new()
	var pp_val := float(e.get("pp", -1.0))
	pp_lbl.text = UiTheme.fmt_pp(pp_val) if pp_val > 0.0 else "—"
	pp_lbl.add_theme_font_size_override("font_size", 13)
	pp_lbl.add_theme_color_override("font_color", UiTheme.ACCENT2)
	row.add_child(pp_lbl)
	var date := Label.new()
	var d := str(e.get("date", "")).split("T")[0]
	var parts := d.split("-")
	if parts.size() != 3:
		date.text = ""
	elif UiTheme.is_german():
		date.text = "%s.%s.%s" % [parts[2], parts[1], parts[0].substr(2)]
	else:
		date.text = "%s/%s/%s" % [parts[1], parts[2], parts[0].substr(2)]
	date.custom_minimum_size = Vector2(58, 0)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_size_override("font_size", 12)
	date.add_theme_color_override("font_color", COL_DIM)
	row.add_child(date)
	return row


func _on_play_pressed() -> void:
	if _selected_set == null:
		return
	GameSession.mods = _current_mods()
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	if not GameSession.perf_enabled:   # Messlauf veraendert den Startzustand nicht
		GameSession.save_last_played(_selected_set.osz_path, _selected_diff, _selected_set.background_file)
	_preview.stop()
	# Auto-Erkennung: Mania-Diffs (Mode 3) starten die 4K-Szene.
	var mode := int(_selected_set.meta_at(_selected_diff).get("mode", 0))
	if mode == 3:
		_change_to_game("res://scenes/mania_3d.tscn")
	else:
		_change_to_game("res://scenes/gameplay_3d.tscn")


func _on_sv_toggled(pressed: bool) -> void:
	_sv_enabled = pressed
	Settings.mod_sv = pressed
	Settings.save()
	if _sv_btn != null:
		_sv_btn.set_pressed_no_signal(_sv_enabled)


## Mods fuer den naechsten Start (Schnittstelle GameSession.mods).
func _current_mods() -> Dictionary:
	return {"NF": _nf_enabled, "SV": _sv_enabled}


func _on_nf_toggled(pressed: bool) -> void:
	_nf_enabled = pressed
	Settings.mod_nf = pressed
	Settings.save()
	_update_nf_button()


func _update_nf_button() -> void:
	if _nf_btn == null:
		return
	_nf_btn.set_pressed_no_signal(_nf_enabled)


## Full-Res-Cover nachladen (nur wenn die Auswahl noch aktuell ist).
func _load_fullres_bg(target_set: MapSet) -> void:
	if _selected_set != target_set:
		return
	var tex := target_set.background_texture()
	if tex != null and _selected_set == target_set:
		_bg.texture = tex
		_cover.texture = tex


## Gespeichertes Replay der gewaehlten Diff ansehen.
func _watch_replay() -> void:
	if _selected_set == null:
		return
	var data := ReplayStore.load_replay(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff))
	if data.is_empty():
		return
	GameSession.mods = GameSession._replay_mods(data)
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	GameSession.is_replay = true
	GameSession.replay_events = data.events
	_preview.stop()
	_change_to_game("res://scenes/mania_3d.tscn")


## Max-pp (SS) der aktuellen Diff anzeigen; Berechnung laeuft im Thread,
## damit der Browser nie ruckelt. Ergebnis wird dauerhaft gecacht.
func _update_max_pp(m: Dictionary) -> void:
	if _selected_set == null:
		return
	var inner := _selected_set.osu_filename_at(_selected_diff)
	var cached := StarService.max_pp_cached(_selected_set.osz_path, inner)
	if cached >= 0.0:
		_maxpp_label.text = tr("Max. %s bei SS") % UiTheme.fmt_pp(cached)
		return
	if cached > -900.0:
		_maxpp_label.text = ""
		return
	_maxpp_label.text = "Max. pp wird berechnet …"
	if _maxpp_thread != null:
		return  # laeuft bereits — fertige Berechnung triggert Refresh
	var osz := _selected_set.osz_path
	var notes := int(m.get("notes", 0))
	_maxpp_thread = Thread.new()
	_maxpp_thread.start(func():
		var v := StarService.max_pp_for(osz, inner, notes)
		_on_maxpp_done.call_deferred(osz, inner, v))


func _on_maxpp_done(osz: String, inner: String, v: float) -> void:
	if _maxpp_thread != null:
		_maxpp_thread.wait_to_finish()
		_maxpp_thread = null
	if _selected_set == null:
		return
	if _selected_set.osz_path == osz and _selected_set.osu_filename_at(_selected_diff) == inner:
		_maxpp_label.text = (tr("Max. %s bei SS") % UiTheme.fmt_pp(v)) if v >= 0.0 else ""
	else:
		# Auswahl hat gewechselt — fuer die neue Diff nachziehen.
		_update_max_pp(_selected_set.meta_at(_selected_diff))


func _on_sv_backfill_done() -> void:
	if is_inside_tree() and _search != null:
		_refresh_filter(_search.text)


func _exit_tree() -> void:
	if _library != null:
		_library.shutdown()
	if _maxpp_thread != null:
		_maxpp_thread.wait_to_finish()
		_maxpp_thread = null


func _play_preview() -> void:
	if _selected_set == null:
		return
	var m := _selected_set.meta_at(_selected_diff)
	var stream := OszImporter.load_audio_stream_named(
		_selected_set.osz_path, str(m.get("audio_filename", "")))
	if stream == null:
		_stop_preview_soft()
		return
	var song_key := SongLoudness.make_key(_selected_set.osz_path, str(m.get("audio_filename", "")))
	var preview_ms := float(m.get("preview_time", -1.0))
	if preview_ms < 0:
		preview_ms = float(m.get("duration_ms", 0.0)) * 0.4
	_switch_preview(stream, preview_ms / 1000.0, song_key)


## Klickfreier Wechsel: alte Vorschau 120 ms ausblenden, dann neue starten
## und 250 ms einblenden. Nie hart stoppen/starten, solange etwas klingt.
## song_key leer = keine Lautheitsmessung (Online-Vorschau).
func _switch_preview(stream: AudioStream, from_sec: float, song_key: String) -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	_preview_fade = create_tween()
	if _preview.playing and _preview.volume_db > PREVIEW_SILENT_DB + 1.0:
		_preview_fade.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_fade.tween_callback(_start_preview.bind(stream, from_sec, song_key))


func _start_preview(stream: AudioStream, from_sec: float, song_key: String) -> void:
	if not is_inside_tree():
		return
	_preview.stop()
	_preview.stream = stream
	_preview_len = stream.get_length()
	if song_key == "":
		SongLoudness.measure_stop()
		_preview_gain_db = 0.0
	else:
		_preview_gain_db = SongLoudness.gain_db_for(song_key)
		if is_equal_approx(_preview_gain_db, 0.0) and not SongLoudness.has_key(song_key):
			SongLoudness.measure_start(song_key)
		else:
			SongLoudness.measure_stop()
	if song_key == "":
		_preview_set = null
		_beat.setup([])
	else:
		_preview_set = _selected_set
		_setup_beat_clock()
	_preview.volume_db = PREVIEW_SILENT_DB
	_preview.play(from_sec)
	if _perf_select_t > 0:
		GameSession.perf_since("Map-Auswahl -> Vorschau-Ton", _perf_select_t)
		_perf_select_t = 0
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", PREVIEW_DB + _preview_gain_db, PREVIEW_FADE_IN)


## Vorschau weich ausblenden und erst dann anhalten.
func _stop_preview_soft() -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	if not _preview.playing:
		return
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_fade.tween_callback(_preview.stop)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _online_open():
			_close_download_panel()
			return
		_preview.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if _online_open() or event.echo:
		return
	# Tastatur-Navigation wie in osu: hoch/runter Map, links/rechts Diff,
	# Enter startet, F2 = Zufallsmap.
	match event.keycode:
		KEY_DOWN:
			_move_selection(1)
			get_viewport().set_input_as_handled()
		KEY_UP:
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_cycle_difficulty(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_cycle_difficulty(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_on_play_pressed()
			get_viewport().set_input_as_handled()
		KEY_F2:
			if not _filtered.is_empty():
				var pick: MapSet = _filtered[randi() % _filtered.size()]
				_select_set(pick, pick.difficulty_count() - 1)
				_scroll_to_selected.call_deferred()
			get_viewport().set_input_as_handled()


func _move_selection(dir: int) -> void:
	if _filtered.is_empty():
		return
	var idx := _filtered.find(_selected_set)
	idx = clampi(idx + dir, 0, _filtered.size() - 1) if idx >= 0 else 0
	_select_set(_filtered[idx], _filtered[idx].difficulty_count() - 1)
	_scroll_to_selected()


## Liste zur ausgewaehlten Karte scrollen (Auswahl bleibt immer sichtbar).
func _scroll_to_selected() -> void:
	var idx := _filtered.find(_selected_set)
	if idx < 0 or idx >= _card_buttons.size() or not is_instance_valid(_card_buttons[idx]):
		return
	var holder := _card_buttons[idx].get_parent().get_parent() as Control
	if holder.size.y <= 0.0:
		# Layout noch nicht fertig (erster Frame): einen Frame warten.
		await get_tree().process_frame
		if not is_instance_valid(holder):
			return
	# Ziel: Karte mittig im sichtbaren Bereich, weich eingeblendet.
	var top := holder.position.y + float(LIST_PAD)
	var target := top + holder.size.y * 0.5 - _scroll.size.y * 0.5
	var vbar := _scroll.get_v_scroll_bar()
	var max_v := maxf(vbar.max_value - vbar.page, 0.0)
	target = clampf(target, 0.0, max_v)
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), 0.30)


# ---------------------------------------------------------------------------
# Drag & Drop
# ---------------------------------------------------------------------------

func _on_files_dropped(files: PackedStringArray) -> void:
	var imported := 0
	var last_path := ""
	for f in files:
		if f.to_lower().ends_with(".osz"):
			var dest := _library.import_external(f)
			if dest != "":
				imported += 1
				last_path = dest
	if imported > 0:
		_library.scan()
		_refresh_filter(_search.text)
		for ms in _filtered:
			if ms.osz_path == last_path:
				_select_set(ms, 0)
				break


# ---------------------------------------------------------------------------
# Online-Tab (scripts/ui/online_browser.gd)
# ---------------------------------------------------------------------------

func _open_download_panel() -> void:
	if _online == null:
		_online = OnlineBrowser.new(_library)
		_online.visible = false
		add_child(_online)
		_online.preview_stream.connect(func(st: AudioStream): _switch_preview(st, 0.0, ""))
		_online.preview_stop.connect(_stop_preview_soft)
		_online.map_downloaded.connect(_on_online_downloaded)
		_online.closed.connect(_on_online_closed)
	_stop_preview_soft()
	_online.open()


func _close_download_panel() -> void:
	if _online != null:
		_online.close()


func _online_open() -> bool:
	return _online != null and _online.visible


## Online-Tab zu: Vorschau der gewaehlten Map wieder aufnehmen.
func _on_online_closed() -> void:
	_play_preview()


## Download fertig: Bibliothek neu scannen, damit die Map sofort im Tab
## "Heruntergeladen" steht; Einzel-Downloads direkt anwaehlen (Pack nicht).
func _on_online_downloaded(_set_id: int, osz_path: String, select: bool) -> void:
	_library.scan()
	_refresh_filter(_search.text)
	if not select:
		return
	for ms in _filtered:
		if ms.osz_path == osz_path:
			_select_set(ms, ms.difficulty_count() - 1)
			break


# ---------------------------------------------------------------------------
# Style-Helfer
# ---------------------------------------------------------------------------

func _rounded_box(bg: Color, radius: int, border_col: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	return sb


func _card_box(bg: Color, accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(CARD_RADIUS)
	if accent.a > 0.0:
		sb.border_width_left = 4
		sb.border_color = accent
	sb.anti_aliasing = true
	sb.set_content_margin_all(6)
	return sb


func _add_label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _icon_button(icon: Texture2D, tip: String) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(40, 36)
	b.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(b, 10)
	_square_margins(b)
	b.add_theme_color_override("icon_normal_color", COL_DIM)
	b.add_theme_color_override("icon_hover_color", COL_TEXT)
	b.add_theme_color_override("icon_pressed_color", COL_ACCENT)
	return b


## osu-aehnliche Farbskala fuer Star Rating (nur Anzeige).
func _star_color(stars: float) -> Color:
	if stars < 0.0:
		return Color(0.5, 0.5, 0.55)
	var stops: Array = [
		[0.0, Color(0.31, 0.75, 1.0)], [2.0, Color(0.31, 1.0, 0.84)],
		[2.7, Color(0.49, 1.0, 0.31)], [3.3, Color(0.96, 0.94, 0.36)],
		[4.2, Color(1.0, 0.50, 0.41)], [4.9, Color(1.0, 0.31, 0.44)],
		[5.8, Color(0.78, 0.27, 0.72)], [6.7, Color(0.40, 0.39, 0.87)],
		[8.0, Color(0.15, 0.13, 0.56)],
	]
	for i in range(stops.size() - 1):
		if stars <= stops[i + 1][0]:
			var k: float = (stars - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
			return (stops[i][1] as Color).lerp(stops[i + 1][1], clampf(k, 0.0, 1.0))
	return stops[stops.size() - 1][1]


## Sterne fuer die Anzeige: "★ 7,27" (ein Stern, Dezimalkomma).
func _stars_text(stars: float) -> String:
	return ("★ " + UiTheme.fmt_num(stars, 2)) if stars >= 0.0 else "★ —"


func _fmt_stars(stars: float) -> String:
	return ("%.2f" % stars) if stars >= 0.0 else "—"


func _format_time(ms: float) -> String:
	var total := int(ms / 1000.0)
	return "%02d:%02d" % [total / 60, total % 60]


# ---------------------------------------------------------------------------
# Headless-Selbsttest
# ---------------------------------------------------------------------------

func _headless_report() -> void:
	print("=== Song-Select Headless-Report ===")
	print("Mapsets gefunden: %d" % _library.mapsets.size())
	for ms in _library.mapsets:
		var star_txt := ""
		for i in ms.difficulty_count():
			star_txt += "%s=%s " % [ms.version_name_at(i), _fmt_stars(ms.stars_at(i))]
		print("  %s - %s | %d Diffs | %s" % [ms.artist, ms.title, ms.difficulty_count(), star_txt])
	if _selected_set != null:
		print("Ausgewaehlt: %s [%s] %s★" % [
			_selected_set.title, _selected_set.version_name_at(_selected_diff),
			_fmt_stars(_selected_set.stars_at(_selected_diff))])
	print("=== Report OK ===")
	get_tree().quit(0)
