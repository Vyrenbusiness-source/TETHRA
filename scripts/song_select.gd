extends Control

## Song-Browser (Rhythia-Vorlage): Vollbild-Hintergrund der Auswahl, Info-Panel
## links (Cover, Sterne, Bestwert, PLAY), rechts farbige Karten mit Cover,
## Star-Reihe und Grade-Badge. Kopfzeile: Profil, Tabs, Suche, Einstellungen.
## Sterne kommen ausschliesslich aus rosu-pp (StarService, Regel 9).
## Neue .osz einfach ins Fenster ziehen -> Import + Neuscan.

const COL_BG := Color(0.03, 0.03, 0.05)
const COL_PANEL := Color(0.07, 0.07, 0.10, 0.92)
const COL_CARD := Color(0.08, 0.08, 0.11, 0.94)
const COL_CARD_SEL := Color(0.13, 0.13, 0.18, 0.98)
const COL_ACCENT := Color(0.20, 0.85, 1.0)
const COL_TEXT := Color(0.95, 0.96, 1.0)
const COL_DIM := Color(0.62, 0.64, 0.72)
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
var _preview: AudioStreamPlayer
var _preview_fade: Tween
# Vorschau bewusst leise (Hintergrund-Charakter), mit sanfter Einblendung.
const PREVIEW_DB := -14.0

## Aktiver No-Fail-Mod: Health kann nicht auf 0 fallen, Play zaehlt unranked.
var _nf_enabled := false
var _nf_btn: Button

# Lazy-Loading der Karten-Thumbnails (2 pro Frame).
var _thumb_queue: Array = []
var _replay_btn: Button

# Collections-Ansicht.
var _collection_mode := false
var _active_collection := ""
var _chips_row: HBoxContainer
# Lokale Filter: Sterne-Bereich + Sortierung (clean als Chip-Reihe).
var _star_filter := 0
var _sort_mode := 0
var _star_chips: Array[Button] = []
# Max-pp (SS) der ausgewaehlten Diff — rosu-pp im Hintergrund-Thread.
var _maxpp_label: Label
var _maxpp_thread: Thread
var _tab_collections: Button
var _tab_downloaded: Button
var _tab_online: Button
var _scroll: ScrollContainer

# Online-Download (Mirror catboy.best).
var _mirror: BeatmapMirror
var _dl_overlay: Control = null
var _dl_results_box: VBoxContainer
var _dl_status: Label
var _dl_search: LineEdit
var _dl_rows: Dictionary = {}
var _dl_preview_req: HTTPRequest
# Schwierigkeits-Filter (client-seitig) + letzte Mirror-Antwort fuer Re-Render.
const STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["< 2★", 0.0, 2.0],
	["2–4★", 2.0, 4.0],
	["4–6★", 4.0, 6.0],
	["6★ +", 6.0, 999.0],
]
## Feinere Filter fuer den Online-Browser (inkl. Anfaenger-Stufe).
const DL_STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["Anfänger ≤1,5★", 0.0, 1.5],
	["1,5–2★", 1.5, 2.0],
	["2–3★", 2.0, 3.0],
	["3–4★", 3.0, 4.0],
	["4–6★", 4.0, 6.0],
	["6★ +", 6.0, 999.0],
]
var _dl_star_filter := 0
## PACK-Download: laedt automatisch N noch fehlende Sets in einem frei
## waehlbaren Sternbereich (z.B. 2.0–2.9).
var _pack_active := false
var _pack_lo := 2.0
var _pack_hi := 2.9
var _pack_want := 10
var _pack_pages := 0
var _pack_started: Dictionary = {}
var _pack_done := 0
var _pack_retries := 0
var _pack_lo_spin: SpinBox
var _pack_hi_spin: SpinBox
var _pack_n_opt: OptionButton
var _dl_last_results: Array = []
# Falls der Mirror auf die leere Vorschlags-Query nichts liefert, einmal
# breit mit "4k" nachfassen.
var _dl_suggest_fallback := false
# Unendliches Scrollen im Online-Browser (Server-Pagination via offset).
var _dl_scroll: ScrollContainer
var _dl_query := ""
var _dl_offset := 0
var _dl_end_reached := false
var _dl_loading_more := false
## Automatisch nachgeladene Seiten seit letzter Suche/Filterwahl (Kappung,
## damit ein sehr restriktiver Filter nicht endlos Seiten zieht).
var _dl_auto_pages := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library = MapLibrary.new()
	_library.scan()

	_preview = AudioStreamPlayer.new()
	_preview.bus = "Master"
	_preview.volume_db = PREVIEW_DB
	add_child(_preview)

	_mirror = Mirror
	_mirror.search_done.connect(_on_mirror_search_done)
	_mirror.search_failed.connect(_on_mirror_search_failed)
	_mirror.cover_ready.connect(_on_mirror_cover_ready)
	_mirror.download_progress.connect(_on_mirror_download_progress)
	_mirror.download_done.connect(_on_mirror_download_done)
	_mirror.download_failed.connect(_on_mirror_download_failed)

	_build_ui()
	_refresh_filter("")
	get_window().files_dropped.connect(_on_files_dropped)
	_select_initial()

	if DisplayServer.get_name() == "headless":
		_headless_report()
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
	elif OS.get_cmdline_args().has("--shot-dl"):
		# Harness: Online-Panel oeffnen, restriktiven Sternfilter setzen und
		# nach dem Auto-Nachladen Kartenzahl + Screenshot festhalten.
		_open_download_panel.call_deferred()
		_shot_dl_after.call_deferred()
	elif OS.get_cmdline_args().has("--shot"):
		_capture_screenshot_and_quit()


func _shot_dl_after() -> void:
	await get_tree().create_timer(2.0).timeout
	if _dl_overlay == null:
		get_tree().quit(1)
		return
	_dl_star_filter = 3
	_dl_auto_pages = 0
	_render_dl_results()
	await get_tree().create_timer(8.0).timeout
	print("DL-KARTEN: %d (auto_pages=%d, end=%s)" % [
		_dl_rows.size(), _dl_auto_pages, _dl_end_reached])
	if OS.get_cmdline_args().has("--pack-test"):
		_pack_lo_spin.value = 2.0
		_pack_hi_spin.value = 2.9
		_pack_n_opt.select(0)
		_start_pack()
		var waited := 0.0
		while _pack_active and waited < 90.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		print("DL-PACK: started=%d done=%d active=%s status=[%s]" % [
			_pack_started.size(), _pack_done, _pack_active, _dl_status.text])
	await RenderingServer.frame_post_draw
	if is_inside_tree():
		var img := get_viewport().get_texture().get_image()
		var path := "C:/Users/Gexanx/AppData/Local/Temp/claude/c--Users-Gexanx-Desktop-rhyg/b9d5e593-aabc-4b4b-a882-a5835e187db3/scratchpad/dl_panel.png"
		img.save_png(path)
		print("SHOT gespeichert: " + path)
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

	_build_header()
	_build_info_panel()
	_build_list()


func _build_header() -> void:
	# Profil-Ecke.
	var profile_panel := PanelContainer.new()
	profile_panel.position = Vector2(16, 12)
	profile_panel.add_theme_stylebox_override("panel", _rounded_box(Color(0.09, 0.09, 0.13, 0.9), 10))
	add_child(profile_panel)
	var pv := VBoxContainer.new()
	profile_panel.add_child(pv)
	var profile := Label.new()
	profile.text = Settings.profile_name
	profile.add_theme_font_size_override("font_size", 19)
	profile.add_theme_color_override("font_color", COL_TEXT)
	pv.add_child(profile)
	var sub := Label.new()
	sub.text = "%.0f pp" % ScoreStore.profile_pp()
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(1.0, 0.6, 0.9))
	pv.add_child(sub)

	# Tab-Leiste + Suche + Zahnrad rechts oben.
	var top_right := HBoxContainer.new()
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -640
	top_right.offset_right = -16
	top_right.offset_top = 14
	top_right.add_theme_constant_override("separation", 8)
	add_child(top_right)

	var gear := Button.new()
	gear.text = "⚙"
	gear.custom_minimum_size = Vector2(42, 38)
	gear.add_theme_font_size_override("font_size", 20)
	gear.add_theme_stylebox_override("normal", _rounded_box(Color(0.10, 0.10, 0.14, 0.9), 8))
	gear.pressed.connect(func(): add_child(SettingsPanel.new()))
	top_right.add_child(gear)

	_tab_collections = Button.new()
	_tab_collections.text = "Collections"
	_tab_collections.custom_minimum_size = Vector2(110, 38)
	_tab_collections.pressed.connect(func(): _set_collection_mode(true))
	top_right.add_child(_tab_collections)

	_tab_downloaded = Button.new()
	_tab_downloaded.text = "Downloaded"
	_tab_downloaded.custom_minimum_size = Vector2(110, 38)
	_tab_downloaded.pressed.connect(func(): _set_collection_mode(false))
	top_right.add_child(_tab_downloaded)
	_style_tabs()

	_tab_online = Button.new()
	_tab_online.text = "⤓ Online"
	_tab_online.custom_minimum_size = Vector2(104, 38)
	_tab_online.add_theme_font_size_override("font_size", 15)
	UiTheme.style_button(_tab_online, true)
	_tab_online.pressed.connect(_open_download_panel)
	top_right.add_child(_tab_online)

	# Filter-Reihe: Anzahl + Sterne-Chips + Sortierung (immer sichtbar).
	var filter_row := HBoxContainer.new()
	filter_row.anchor_left = 1.0
	filter_row.anchor_right = 1.0
	filter_row.offset_left = -620
	filter_row.offset_right = -16
	filter_row.offset_top = 64
	filter_row.alignment = BoxContainer.ALIGNMENT_END
	filter_row.add_theme_constant_override("separation", 6)
	add_child(filter_row)

	_count_label = Label.new()
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", COL_DIM)
	filter_row.add_child(_count_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(8, 0)
	filter_row.add_child(gap)
	for fi in STAR_FILTERS.size():
		var chip := Button.new()
		chip.text = STAR_FILTERS[fi][0]
		chip.custom_minimum_size = Vector2(0, 32)
		chip.add_theme_font_size_override("font_size", 13)
		UiTheme.style_button(chip, fi == _star_filter, 14)
		chip.pressed.connect(func():
			_star_filter = fi
			_restyle_star_chips()
			_refresh_filter(_search.text))
		filter_row.add_child(chip)
		_star_chips.append(chip)
	var sort := OptionButton.new()
	sort.add_item("Titel", 0)
	sort.add_item("Sterne ↑", 1)
	sort.add_item("Sterne ↓", 2)
	sort.select(_sort_mode)
	sort.custom_minimum_size = Vector2(110, 32)
	sort.add_theme_font_size_override("font_size", 13)
	sort.add_theme_stylebox_override("normal", _rounded_box(Color(0.10, 0.10, 0.14, 0.9), 8))
	sort.item_selected.connect(func(i):
		_sort_mode = i
		_refresh_filter(_search.text))
	filter_row.add_child(sort)

	# Chip-Reihe fuer Sammlungen (nur im Collections-Modus sichtbar).
	_chips_row = HBoxContainer.new()
	_chips_row.anchor_left = 1.0
	_chips_row.anchor_right = 1.0
	_chips_row.offset_left = -620
	_chips_row.offset_right = -16
	_chips_row.offset_top = 106
	_chips_row.alignment = BoxContainer.ALIGNMENT_END
	_chips_row.add_theme_constant_override("separation", 6)
	_chips_row.visible = false
	add_child(_chips_row)

	_search = LineEdit.new()
	_search.placeholder_text = "Search map"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(220, 38)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_stylebox_override("normal", _rounded_box(Color(0.10, 0.10, 0.14, 0.9), 8))
	_search.text_changed.connect(_refresh_filter)
	top_right.add_child(_search)



func _build_info_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 32
	panel.offset_top = 96
	panel.offset_bottom = -32
	panel.custom_minimum_size = Vector2(400, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.glass_box(18, 0.5))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_cover = TextureRect.new()
	_cover.custom_minimum_size = Vector2(0, 200)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vb.add_child(_cover)

	_title_label = _add_label(vb, "", 26, COL_TEXT)
	_title_label.add_theme_font_override("font", UiTheme.heading_font(1))
	_artist_label = _add_label(vb, "", 15, COL_DIM)
	_mapper_label = _add_label(vb, "", 13, COL_ACCENT)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	vb.add_child(diff_row)
	var prev := _icon_button("<")
	prev.pressed.connect(func(): _cycle_difficulty(-1))
	diff_row.add_child(prev)
	_diff_label = Label.new()
	_diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_diff_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_label.add_theme_font_size_override("font_size", 16)
	_diff_label.add_theme_color_override("font_color", COL_ACCENT)
	diff_row.add_child(_diff_label)
	var next := _icon_button(">")
	next.pressed.connect(func(): _cycle_difficulty(1))
	diff_row.add_child(next)

	_star_label = _add_label(vb, "", 17, Color(1.0, 0.85, 0.3))
	_maxpp_label = _add_label(vb, "", 14, Color(1.0, 0.6, 0.9))
	_stats_label = _add_label(vb, "", 14, COL_DIM)

	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(0, 54)
	play.add_theme_font_override("font", UiTheme.heading_font(4))
	play.add_theme_font_size_override("font_size", 22)
	UiTheme.style_button(play, true)
	play.pressed.connect(_on_play_pressed)
	vb.add_child(play)

	# Mod-Reihe: aktuell nur No Fail (NF).
	var mods_row := HBoxContainer.new()
	mods_row.add_theme_constant_override("separation", 6)
	vb.add_child(mods_row)

	_nf_btn = Button.new()
	_nf_btn.toggle_mode = true
	_nf_btn.button_pressed = _nf_enabled
	_nf_btn.custom_minimum_size = Vector2(0, 34)
	_nf_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nf_btn.add_theme_font_size_override("font_size", 14)
	_nf_btn.toggled.connect(_on_nf_toggled)
	mods_row.add_child(_nf_btn)
	_update_nf_button()

	var coll_btn := Button.new()
	coll_btn.text = "+ Sammlung"
	coll_btn.custom_minimum_size = Vector2(0, 36)
	coll_btn.add_theme_font_size_override("font_size", 14)
	coll_btn.add_theme_stylebox_override("normal", _rounded_box(Color(0.12, 0.12, 0.17, 0.9), 8))
	coll_btn.pressed.connect(_open_collection_popup)
	vb.add_child(coll_btn)

	# BESTE SCORES: Top 5 dieser Diff (pp + Datum) + Replay-Zugriff.
	var lb_head := HBoxContainer.new()
	lb_head.add_theme_constant_override("separation", 8)
	vb.add_child(lb_head)
	var lb_title := Label.new()
	lb_title.text = "BESTE SCORES"
	lb_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lb_title.add_theme_font_size_override("font_size", 13)
	lb_title.add_theme_color_override("font_color", COL_ACCENT)
	lb_head.add_child(lb_title)
	_replay_btn = Button.new()
	_replay_btn.text = "▶ Replay"
	_replay_btn.custom_minimum_size = Vector2(0, 30)
	_replay_btn.add_theme_font_size_override("font_size", 12)
	UiTheme.style_button(_replay_btn, false, 8)
	_replay_btn.visible = false
	_replay_btn.pressed.connect(_watch_replay)
	lb_head.add_child(_replay_btn)

	_lb_box = VBoxContainer.new()
	_lb_box.add_theme_constant_override("separation", 5)
	vb.add_child(_lb_box)


func _build_list() -> void:
	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 1.0
	_scroll.anchor_right = 1.0
	_scroll.anchor_top = 0.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_left = -620
	_scroll.offset_right = -20
	_scroll.offset_top = 114
	_scroll.offset_bottom = -20
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list_box)


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

func _style_tabs() -> void:
	var active := _rounded_box(Color(0.95, 0.95, 0.98, 0.95), 8)
	var inactive := _rounded_box(Color(0.10, 0.10, 0.14, 0.9), 8)
	_tab_collections.add_theme_stylebox_override("normal", active if _collection_mode else inactive)
	_tab_collections.add_theme_color_override("font_color",
		Color(0.05, 0.05, 0.08) if _collection_mode else COL_TEXT)
	_tab_downloaded.add_theme_stylebox_override("normal", inactive if _collection_mode else active)
	_tab_downloaded.add_theme_color_override("font_color",
		COL_TEXT if _collection_mode else Color(0.05, 0.05, 0.08))


func _set_collection_mode(on: bool) -> void:
	_collection_mode = on
	if on and _active_collection == "":
		var names := CollectionStore.list_names()
		_active_collection = names[0] if not names.is_empty() else ""
	_chips_row.visible = on
	_scroll.offset_top = 152 if on else 114
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
		var chip := Button.new()
		chip.text = "%s (%d)" % [name, present]
		chip.custom_minimum_size = Vector2(0, 30)
		var active: bool = name == _active_collection
		chip.add_theme_stylebox_override("normal",
			_rounded_box(COL_ACCENT if active else Color(0.12, 0.12, 0.17, 0.9), 14))
		chip.add_theme_color_override("font_color", Color(0.03, 0.05, 0.08) if active else COL_TEXT)
		chip.add_theme_font_size_override("font_size", 13)
		chip.pressed.connect(func():
			_active_collection = name
			_rebuild_chips()
			_refresh_filter(_search.text))
		_chips_row.add_child(chip)
	# Aktive Sammlung loeschen (kleines x am Ende der Reihe).
	if _active_collection != "":
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Sammlung \"%s\" loeschen" % _active_collection
		del.custom_minimum_size = Vector2(30, 30)
		del.add_theme_font_size_override("font_size", 13)
		del.add_theme_stylebox_override("normal", _rounded_box(Color(0.30, 0.10, 0.12, 0.9), 14))
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
	title.text = "\"%s\" in Sammlungen" % _selected_set.title
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
	close.text = "Schliessen"
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
		UiTheme.style_button(_star_chips[i], i == _star_filter, 14)


func _refresh_filter(query: String) -> void:
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
	var count_txt := "%d Maps" % _filtered.size()
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
			count_txt += "  ·  %d fehlen (geloescht?)" % missing
	_count_label.text = count_txt


func _process(_delta: float) -> void:
	# Thumbnails haeppchenweise laden — Browser bleibt fluessig.
	var budget := 2
	while budget > 0 and not _thumb_queue.is_empty():
		var job: Dictionary = _thumb_queue.pop_front()
		var bg_rect: TextureRect = job.bg
		if not is_instance_valid(bg_rect):
			continue
		var tex: Texture2D = (job.ms as MapSet).thumb_texture()
		if tex != null:
			bg_rect.texture = tex
			(job.thumb as TextureRect).texture = tex
		budget -= 1


func _rebuild_cards() -> void:
	_thumb_queue.clear()
	for c in _list_box.get_children():
		c.queue_free()
	_card_buttons.clear()
	for i in _filtered.size():
		var card := _make_card(_filtered[i])
		_list_box.add_child(card)
		_card_buttons.append(card)


## Rechtsklick auf eine Karte: .osz nach Bestaetigung loeschen.
func _confirm_delete(ms: MapSet) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Map loeschen"
	dlg.dialog_text = "\"%s — %s\" wirklich loeschen?\nDie .osz-Datei wird vom Datentraeger entfernt." % [ms.artist, ms.title]
	dlg.ok_button_text = "Loeschen"
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


func _make_card(ms: MapSet) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 88)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var accent := _star_color(ms.max_stars())
	card.add_theme_stylebox_override("normal", _card_box(COL_CARD, accent))
	card.add_theme_stylebox_override("hover", _card_box(COL_CARD_SEL, accent))
	card.add_theme_stylebox_override("pressed", _card_box(COL_CARD_SEL, accent))
	card.add_theme_stylebox_override("focus", _card_box(COL_CARD_SEL, accent))
	card.pressed.connect(func(): _on_card_pressed(ms))
	UiTheme.attach_hover(card, 1.015)
	# Rechtsklick: Map nach Bestaetigung vom Datentraeger loeschen.
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed \
				and e.button_index == MOUSE_BUTTON_RIGHT:
			_confirm_delete(ms))

	# Cover schwach als Kartenhintergrund — LAZY: Thumbnails werden ueber
	# Frames verteilt geladen (UI erscheint sofort, kein Ruckeln).
	var card_bg := TextureRect.new()
	card_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_bg.modulate = Color(1, 1, 1, 0.16)
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(card_bg)

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(104, 66)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(thumb)
	_thumb_queue.append({ "ms": ms, "bg": card_bg, "thumb": thumb })

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	var t := Label.new()
	t.text = "%s - %s" % [ms.artist, ms.title]
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", COL_TEXT)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	var m := Label.new()
	m.text = "Mapped by %s" % ms.creator
	m.add_theme_font_size_override("font_size", 12)
	m.add_theme_color_override("font_color", COL_DIM)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(m)

	# Star-Reihe wie Vorlage: ★-Icons + "X.XX stars · Laenge".
	var star_row := Label.new()
	star_row.text = "%s %s stars · %s" % [
		_star_icons(ms.max_stars()), _fmt_stars(ms.max_stars()), _format_time(ms.length_ms())]
	star_row.add_theme_font_size_override("font_size", 13)
	star_row.add_theme_color_override("font_color", accent.lightened(0.25))
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(star_row)

	# Grade-Badge des besten Scores (schwerste Diff mit Bestwert zuerst).
	var badge := _best_grade_badge(ms)
	if badge != "":
		var g := Label.new()
		g.text = badge
		g.add_theme_font_size_override("font_size", 30)
		g.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(g)

	return card


func _best_grade_badge(ms: MapSet) -> String:
	for i in range(ms.difficulty_count() - 1, -1, -1):
		var best := ScoreStore.best(ms.osz_path, ms.version_name_at(i))
		if not best.is_empty():
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
	_selected_set = ms
	_selected_diff = clampi(diff_index, 0, ms.difficulty_count() - 1)
	_update_info_panel()
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
	var target_set := _selected_set
	call_deferred("_load_fullres_bg", target_set)
	_title_label.text = _selected_set.title
	_artist_label.text = _selected_set.artist
	_mapper_label.text = "Mapped by %s" % _selected_set.creator
	var is_mania := int(m.get("mode", 0)) == 3
	_diff_label.text = _selected_set.version_name_at(_selected_diff) + ("  ·  4K" if is_mania else "")
	var stars := _selected_set.stars_at(_selected_diff)
	_star_label.text = "%s  %s stars" % [_star_icons(stars), _fmt_stars(stars)]
	_star_label.add_theme_color_override("font_color", _star_color(stars).lightened(0.3))
	_stats_label.text = "%d Notes · %s · CS %.1f  AR %.1f  OD %.1f" % [
		int(m.get("notes", 0)), _format_time(float(m.get("duration_ms", 0.0))),
		float(m.get("cs", 0.0)), float(m.get("ar", 0.0)), float(m.get("od", 0.0))]
	_update_max_pp(m)
	# BESTE SCORES: Top 5 dieser Difficulty als cleane Rows.
	for c in _lb_box.get_children():
		c.queue_free()
	var tops := ScoreStore.top_scores(_selected_set.osz_path, _selected_set.version_name_at(_selected_diff), 5)
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
	# Auswahl-Hervorhebung der Karten.
	for i in _card_buttons.size():
		var is_sel := _filtered[i] == _selected_set
		var accent := _star_color(_filtered[i].max_stars())
		_card_buttons[i].add_theme_stylebox_override(
			"normal", _card_box(COL_CARD_SEL if is_sel else COL_CARD, accent, is_sel))


## Eine Leaderboard-Zeile: Rang, Grade, Score/Acc, pp, Datum.
func _score_row(rank: int, e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var num := Label.new()
	num.text = "#%d" % (rank + 1)
	num.custom_minimum_size = Vector2(26, 0)
	num.add_theme_font_size_override("font_size", 12)
	num.add_theme_color_override("font_color",
		Color(1.0, 0.85, 0.3) if rank == 0 else COL_DIM)
	row.add_child(num)
	var grade := Label.new()
	grade.text = str(e.get("grade", "?"))
	grade.custom_minimum_size = Vector2(20, 0)
	grade.add_theme_font_size_override("font_size", 16)
	grade.add_theme_color_override("font_color", GRADE_COLOR.get(str(e.get("grade", "")), COL_TEXT))
	row.add_child(grade)
	var main := Label.new()
	main.text = "%d · %.2f%% · %dx" % [
		int(e.get("score", 0)), float(e.get("accuracy", 0.0)) * 100.0, int(e.get("max_combo", 0))]
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	main.add_theme_font_size_override("font_size", 13)
	main.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	row.add_child(main)
	var pp_lbl := Label.new()
	var pp_val := float(e.get("pp", -1.0))
	pp_lbl.text = ("%.1fpp" % pp_val) if pp_val > 0.0 else "—"
	pp_lbl.add_theme_font_size_override("font_size", 13)
	pp_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.9))
	row.add_child(pp_lbl)
	var date := Label.new()
	var d := str(e.get("date", "")).split("T")[0]
	var parts := d.split("-")
	date.text = "%s.%s.%s" % [parts[2], parts[1], parts[0].substr(2)] if parts.size() == 3 else ""
	date.custom_minimum_size = Vector2(58, 0)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_size_override("font_size", 11)
	date.add_theme_color_override("font_color", COL_DIM)
	row.add_child(date)
	return row


func _on_play_pressed() -> void:
	if _selected_set == null:
		return
	GameSession.mods = {"NF": _nf_enabled}
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	GameSession.save_last_played(_selected_set.osz_path, _selected_diff, _selected_set.background_file)
	_preview.stop()
	# Auto-Erkennung: Mania-Diffs (Mode 3) starten die 4K-Szene.
	var mode := int(_selected_set.meta_at(_selected_diff).get("mode", 0))
	if mode == 3:
		get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/gameplay_3d.tscn")


func _on_nf_toggled(pressed: bool) -> void:
	_nf_enabled = pressed
	_update_nf_button()


func _update_nf_button() -> void:
	if _nf_btn == null:
		return
	_nf_btn.text = "NF: An" if _nf_enabled else "NF: Aus"
	var col := COL_ACCENT if _nf_enabled else Color(0.12, 0.12, 0.17, 0.9)
	var fg := Color.BLACK if _nf_enabled else COL_TEXT
	_nf_btn.add_theme_color_override("font_color", fg)
	_nf_btn.add_theme_stylebox_override("normal", _rounded_box(col, 8))
	_nf_btn.add_theme_stylebox_override("hover", _rounded_box(col.lightened(0.1), 8))
	_nf_btn.add_theme_stylebox_override("pressed", _rounded_box(col.darkened(0.1), 8))


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
	GameSession.mods = {"NF": _nf_enabled}
	GameSession.set_selection(
		_selected_set.osz_path, _selected_diff,
		_selected_set.version_name_at(_selected_diff),
		_selected_set.osu_filename_at(_selected_diff),
		_selected_set.stars_at(_selected_diff))
	GameSession.is_replay = true
	GameSession.replay_events = data.events
	_preview.stop()
	get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")


## Max-pp (SS) der aktuellen Diff anzeigen; Berechnung laeuft im Thread,
## damit der Browser nie ruckelt. Ergebnis wird dauerhaft gecacht.
func _update_max_pp(m: Dictionary) -> void:
	if _selected_set == null:
		return
	var inner := _selected_set.osu_filename_at(_selected_diff)
	var cached := StarService.max_pp_cached(_selected_set.osz_path, inner)
	if cached >= 0.0:
		_maxpp_label.text = "Max %.0f pp bei SS" % cached
		return
	if cached > -900.0:
		_maxpp_label.text = ""
		return
	_maxpp_label.text = "Max pp wird berechnet…"
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
		_maxpp_label.text = ("Max %.0f pp bei SS" % v) if v >= 0.0 else ""
	else:
		# Auswahl hat gewechselt — fuer die neue Diff nachziehen.
		_update_max_pp(_selected_set.meta_at(_selected_diff))


func _exit_tree() -> void:
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
		_preview.stop()
		return
	_preview.stream = stream
	var preview_ms := float(m.get("preview_time", -1.0))
	if preview_ms < 0:
		preview_ms = float(m.get("duration_ms", 0.0)) * 0.4
	_fade_in_preview(preview_ms / 1000.0)


func _fade_in_preview(from_sec: float) -> void:
	if _preview_fade != null and _preview_fade.is_valid():
		_preview_fade.kill()
	_preview.volume_db = -40.0
	_preview.play(from_sec)
	_preview_fade = create_tween()
	_preview_fade.tween_property(_preview, "volume_db", PREVIEW_DB, 0.9)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		if _dl_overlay != null:
			_close_download_panel()
			return
		_preview.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if _dl_overlay != null or event.echo:
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
	if idx >= 0 and idx < _card_buttons.size() and is_instance_valid(_card_buttons[idx]):
		_scroll.ensure_control_visible(_card_buttons[idx])


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
# Online-Download (Mirror catboy.best)
# ---------------------------------------------------------------------------

func _open_download_panel() -> void:
	if _dl_overlay != null:
		return
	_preview.stop()
	_dl_rows.clear()

	_dl_overlay = Control.new()
	_dl_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dl_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_download_panel())
	_dl_overlay.add_child(dim)

	var panel := GlassPanel.new(20, 22, 0.62)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -600
	panel.offset_right = 600
	panel.offset_top = -335
	panel.offset_bottom = 335
	_dl_overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var title := Label.new()
	title.text = "SONGS HERUNTERLADEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UiTheme.heading_font(2))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_TEXT)
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(40, 40)
	close.add_theme_font_size_override("font_size", 18)
	UiTheme.style_button(close)
	close.pressed.connect(_close_download_panel)
	head.add_child(close)

	var src := Label.new()
	src.text = "Quelle: catboy.best · nur Ranked · nur 4K-Mania · vorhandene Sets ausgeblendet"
	src.add_theme_font_size_override("font_size", 12)
	src.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(src)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	vb.add_child(search_row)
	_dl_search = LineEdit.new()
	_dl_search.placeholder_text = "Titel, Artist oder Mapper suchen…"
	_dl_search.clear_button_enabled = true
	_dl_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_search.custom_minimum_size = Vector2(0, 42)
	_dl_search.add_theme_stylebox_override("normal", UiTheme.glass_box(10, 0.55))
	_dl_search.add_theme_stylebox_override("focus", UiTheme.glass_box(10, 0.7, 0.3))
	_dl_search.text_submitted.connect(func(_t): _run_mirror_search())
	search_row.add_child(_dl_search)
	var go := Button.new()
	go.text = "Suchen"
	go.custom_minimum_size = Vector2(110, 42)
	UiTheme.style_button(go, true)
	go.pressed.connect(_run_mirror_search)
	search_row.add_child(go)

	# Schwierigkeits-Filter als Chip-Reihe (wirken sofort, ohne neue Suche).
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	vb.add_child(filter_row)
	var fcap := Label.new()
	fcap.text = "Schwierigkeit:"
	fcap.add_theme_font_size_override("font_size", 13)
	fcap.add_theme_color_override("font_color", COL_DIM)
	filter_row.add_child(fcap)
	var group := ButtonGroup.new()
	for fi in DL_STAR_FILTERS.size():
		var chip := Button.new()
		chip.text = DL_STAR_FILTERS[fi][0]
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = fi == _dl_star_filter
		chip.custom_minimum_size = Vector2(0, 32)
		chip.add_theme_font_size_override("font_size", 13)
		UiTheme.style_button(chip, fi == _dl_star_filter)
		chip.pressed.connect(func():
			_dl_star_filter = fi
			_dl_auto_pages = 0
			_render_dl_results())
		filter_row.add_child(chip)

	# PACK-DOWNLOAD: N fehlende Sets in einem freien Sternbereich auf einmal.
	var pack_row := HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", 8)
	vb.add_child(pack_row)
	var pcap := Label.new()
	pcap.text = "Pack-Download:"
	pcap.add_theme_font_size_override("font_size", 13)
	pcap.add_theme_color_override("font_color", COL_DIM)
	pack_row.add_child(pcap)
	_pack_lo_spin = SpinBox.new()
	_pack_lo_spin.min_value = 0.0
	_pack_lo_spin.max_value = 10.0
	_pack_lo_spin.step = 0.1
	_pack_lo_spin.value = 2.0
	_pack_lo_spin.custom_minimum_size = Vector2(84, 32)
	pack_row.add_child(_pack_lo_spin)
	var pdash := Label.new()
	pdash.text = "–"
	pack_row.add_child(pdash)
	_pack_hi_spin = SpinBox.new()
	_pack_hi_spin.min_value = 0.0
	_pack_hi_spin.max_value = 10.0
	_pack_hi_spin.step = 0.1
	_pack_hi_spin.value = 2.9
	_pack_hi_spin.custom_minimum_size = Vector2(84, 32)
	pack_row.add_child(_pack_hi_spin)
	var pstar := Label.new()
	pstar.text = "★  ·"
	pack_row.add_child(pstar)
	_pack_n_opt = OptionButton.new()
	_pack_n_opt.add_item("5 Maps", 5)
	_pack_n_opt.add_item("10 Maps", 10)
	_pack_n_opt.add_item("20 Maps", 20)
	_pack_n_opt.select(1)
	_pack_n_opt.custom_minimum_size = Vector2(0, 32)
	pack_row.add_child(_pack_n_opt)
	var pack_btn := Button.new()
	pack_btn.text = "⤓ Pack herunterladen"
	pack_btn.custom_minimum_size = Vector2(0, 34)
	UiTheme.style_button(pack_btn, true)
	pack_btn.pressed.connect(_start_pack)
	pack_row.add_child(pack_btn)

	_dl_status = Label.new()
	_dl_status.text = "Lade Vorschläge…"
	_dl_status.add_theme_font_size_override("font_size", 13)
	_dl_status.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(_dl_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_dl_results_box = VBoxContainer.new()
	_dl_results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_results_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_dl_results_box)
	# Unendlich scrollen: am Listenende automatisch die naechste Seite laden.
	_dl_scroll = scroll
	scroll.get_v_scroll_bar().value_changed.connect(_on_dl_scrolled)

	_dl_search.grab_focus.call_deferred()
	# Sofort Vorschlaege laden — ohne dass man erst suchen muss.
	_dl_suggest_fallback = true
	_dl_query = ""
	_dl_offset = 0
	_dl_end_reached = false
	_dl_loading_more = true
	_mirror.search("")


func _close_download_panel() -> void:
	_preview.stop()
	if _dl_overlay != null:
		_dl_overlay.queue_free()
		_dl_overlay = null
	_dl_rows.clear()


func _run_mirror_search() -> void:
	# Leere Suche = Vorschlaege (neueste 4K-Sets vom Mirror).
	var q := _dl_search.text.strip_edges()
	_dl_suggest_fallback = q == ""
	_dl_query = q
	_dl_offset = 0
	_dl_end_reached = false
	_dl_auto_pages = 0
	_dl_loading_more = true
	_dl_status.text = ("Suche \"%s\"…" % q) if q != "" else "Lade Vorschläge…"
	for c in _dl_results_box.get_children():
		c.queue_free()
	_dl_rows.clear()
	_mirror.search(q)


func _on_mirror_search_failed(message: String) -> void:
	_dl_loading_more = false
	# Pack-Download: Mirror-Aussetzer nicht als Absturz werten — kurz warten
	# und dieselbe Seite erneut anfordern (max. 5 Versuche).
	if _pack_active:
		_pack_retries += 1
		if _pack_retries <= 5 and _dl_overlay != null:
			_dl_status.text = "Mirror kurz nicht erreichbar — versuche erneut…"
			get_tree().create_timer(1.5, true).timeout.connect(func():
				if _pack_active and _dl_overlay != null:
					_dl_loading_more = true
					_mirror.search(_dl_query, _dl_offset))
		else:
			_pack_active = false
			if _dl_status != null:
				_dl_status.text = "Pack abgebrochen: Mirror nicht erreichbar — spaeter erneut versuchen."
		return
	if _dl_suggest_fallback:
		_dl_suggest_fallback = false
		_dl_query = "4k"
		_mirror.search("4k")
		return
	if _dl_status != null:
		_dl_status.text = message


func _on_mirror_search_done(results: Array, raw_count: int, offset: int) -> void:
	if _dl_results_box == null:
		return
	_dl_loading_more = false
	_dl_end_reached = raw_count < 50
	if offset == 0:
		if results.is_empty() and _dl_suggest_fallback:
			_dl_suggest_fallback = false
			_dl_query = "4k"
			_mirror.search("4k")
			return
		_dl_suggest_fallback = false
		_dl_last_results = results
		_render_dl_results()
		return
	# Naechste Seite: nur NEUE Karten anhaengen — Scrollposition bleibt.
	_dl_last_results.append_array(results)
	if _pack_active:
		_pack_fill()
	var owned := _owned_set_ids()
	var lo: float = DL_STAR_FILTERS[_dl_star_filter][1]
	var hi: float = DL_STAR_FILTERS[_dl_star_filter][2]
	for r in results:
		if _dl_rows.has(int(r.id)):
			continue
		if not _dl_passes(r, owned, lo, hi):
			continue
		_dl_results_box.add_child(_make_online_card(r))
	_dl_status.text = "%d Sets geladen%s" % [_dl_rows.size(),
		"  ·  Ende der Liste" if _dl_end_reached else " — weiter scrollen fuer mehr"]
	_maybe_load_more()


# ---------------------------------------------------------------------------
# PACK-Download: N fehlende Sets im gewaehlten Sternbereich automatisch laden.
# ---------------------------------------------------------------------------

func _start_pack() -> void:
	if _pack_active:
		return
	_pack_lo = minf(_pack_lo_spin.value, _pack_hi_spin.value)
	_pack_hi = maxf(_pack_lo_spin.value, _pack_hi_spin.value)
	_pack_want = _pack_n_opt.get_selected_id()
	_pack_active = true
	_pack_started = {}
	_pack_done = 0
	_pack_pages = 0
	_pack_retries = 0
	_dl_status.text = "Pack: suche Sets im Bereich %.1f–%.1f★…" % [_pack_lo, _pack_hi]
	_pack_fill()


## Passende Sets aus den geladenen Ergebnissen starten; reichen sie nicht,
## weitere Server-Seiten holen (max. 12 fuers Pack).
func _pack_fill() -> void:
	if not _pack_active:
		return
	var owned := _owned_set_ids()
	for r in _dl_last_results:
		if _pack_started.size() >= _pack_want:
			break
		var sid := int(r.id)
		if _pack_started.has(sid) or _mirror.is_downloading(sid):
			continue
		if not _dl_passes(r, owned, _pack_lo, _pack_hi + 0.0001):
			continue
		_pack_started[sid] = true
		_mirror.download(sid, _library.maps_dir)
		if _dl_rows.has(sid):
			var btn: Button = _dl_rows[sid].btn
			if is_instance_valid(btn):
				btn.disabled = true
				btn.text = "0 %"
	if _pack_started.size() < _pack_want and not _dl_end_reached \
			and not _dl_loading_more and _pack_pages < 12:
		_pack_pages += 1
		_dl_loading_more = true
		_dl_offset += 50
		# Den Mirror nicht mit Request-Bursts fluten (drosselt sonst: HTTP 0).
		get_tree().create_timer(0.45, true).timeout.connect(func():
			if _pack_active and _dl_overlay != null:
				_mirror.search(_dl_query, _dl_offset)
			else:
				_dl_loading_more = false)
	_update_pack_status()


func _update_pack_status() -> void:
	if not _pack_active:
		return
	if _pack_started.is_empty() and (_dl_end_reached or _pack_pages >= 12):
		_pack_active = false
		_dl_status.text = "Pack: nichts Passendes im Bereich %.1f–%.1f★ gefunden." % [_pack_lo, _pack_hi]
		return
	_dl_status.text = "Pack (%.1f–%.1f★): %d/%d fertig  ·  %d laufen" % [
		_pack_lo, _pack_hi, _pack_done, _pack_started.size(),
		_pack_started.size() - _pack_done]
	if _pack_done >= _pack_started.size() \
			and (_pack_started.size() >= _pack_want or _dl_end_reached or _pack_pages >= 12):
		_pack_active = false
		_dl_status.text = "Pack fertig: %d Maps geladen (%.1f–%.1f★) — viel Spass!" % [
			_pack_done, _pack_lo, _pack_hi]


## Zu wenige sichtbare Karten (Filter/Besitz frisst viel raus)? Dann sofort
## weitere Server-Seiten holen — sonst gibt es keinen Scrollbalken und das
## unendliche Scrollen kaeme nie in Gang ("nur 3 Songs"-Bug).
func _maybe_load_more() -> void:
	if _dl_loading_more or _dl_end_reached or _dl_overlay == null:
		return
	if _dl_rows.size() >= 16 or _dl_auto_pages >= 8:
		return
	_dl_auto_pages += 1
	_dl_loading_more = true
	_dl_offset += 50
	_dl_status.text = "%d Sets  ·  lade mehr passende…" % _dl_rows.size()
	_mirror.search(_dl_query, _dl_offset)


## Am Listenende angekommen -> naechste Server-Seite anfordern.
func _on_dl_scrolled(_v: float) -> void:
	if _dl_loading_more or _dl_end_reached or _dl_overlay == null \
			or _dl_last_results.is_empty() or _dl_scroll == null:
		return
	var bar := _dl_scroll.get_v_scroll_bar()
	if bar.value + bar.page < bar.max_value - 250.0:
		return
	_dl_loading_more = true
	_dl_offset += 50
	_dl_status.text = "Lade mehr…"
	_mirror.search(_dl_query, _dl_offset)


## Gemeinsamer Ergebnis-Filter: nicht in der Bibliothek + im Sternbereich.
func _dl_passes(r: Dictionary, owned: Dictionary, lo: float, hi: float) -> bool:
	if owned.has(int(r.id)):
		return false
	if owned.has(_at_key(str(r.get("artist", "")), str(r.get("title", "")))):
		return false
	var star_list: Array = r.get("star_list", [])
	if star_list.is_empty():
		star_list = [float(r.get("stars", 0.0))]
	for sv in star_list:
		if float(sv) >= lo and float(sv) < hi:
			return true
	return false


## Ergebnisliste neu aufbauen: vorhandene Sets raus, Schwierigkeits-Filter
## drauf (Set passt, wenn IRGENDEINE 4K-Diff im Sternbereich liegt).
func _render_dl_results() -> void:
	if _dl_results_box == null:
		return
	for c in _dl_results_box.get_children():
		c.queue_free()
	_dl_rows.clear()
	var owned := _owned_set_ids()
	var lo: float = DL_STAR_FILTERS[_dl_star_filter][1]
	var hi: float = DL_STAR_FILTERS[_dl_star_filter][2]
	var fresh: Array = []
	for r in _dl_last_results:
		if _dl_passes(r, owned, lo, hi):
			fresh.append(r)
	if fresh.is_empty():
		if _dl_last_results.is_empty():
			_dl_status.text = "Keine Ergebnisse."
		elif _dl_star_filter != 0:
			_dl_status.text = "Suche Sets im Bereich %s…" % DL_STAR_FILTERS[_dl_star_filter][0]
		else:
			_dl_status.text = "Suche neue Sets…"
		_maybe_load_more()
		return
	var hidden := _dl_last_results.size() - fresh.size()
	var hidden_txt := ("  ·  %d ausgeblendet" % hidden) if hidden > 0 else ""
	_dl_status.text = "%d neue 4K-Sets%s" % [fresh.size(), hidden_txt]
	for r in fresh:
		_dl_results_box.add_child(_make_online_card(r))
	_maybe_load_more()


## Besitz-Erkennung: Set-IDs aus Dateinamen (fuehrende Zahl oder mirror_<id>)
## PLUS "artist|titel"-Schluessel aus der Bibliothek — erkennt auch Maps,
## deren Dateiname keine Set-ID traegt.
func _owned_set_ids() -> Dictionary:
	var owned := {}
	var dir := DirAccess.open(_library.maps_dir)
	if dir != null:
		for fname in dir.get_files():
			if not fname.to_lower().ends_with(".osz"):
				continue
			var base := fname.get_basename()
			if base.begins_with("mirror_"):
				var id_str := base.substr(7)
				if id_str.is_valid_int():
					owned[int(id_str)] = true
			else:
				var head := base.split(" ")[0]
				if head.is_valid_int():
					owned[int(head)] = true
	for ms in _library.mapsets:
		if ms.title != "":
			owned[_at_key(ms.artist, ms.title)] = true
	return owned


static func _at_key(artist: String, title: String) -> String:
	# Nur Buchstaben/Ziffern vergleichen — Klammern, Spaces und
	# Sonderzeichen unterscheiden sich zwischen Mirror und Datei oft.
	var raw := ("%s|%s" % [artist, title]).to_lower()
	var out := ""
	for ch in raw:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "|":
			out += ch
	return out


func _make_online_card(r: Dictionary) -> Control:
	var set_id: int = r.id
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	var accent := _star_color(r.stars)
	card.add_theme_stylebox_override("normal", _card_box(COL_CARD, accent))
	card.add_theme_stylebox_override("hover", _card_box(COL_CARD_SEL, accent))
	card.add_theme_stylebox_override("pressed", _card_box(COL_CARD_SEL, accent))
	card.add_theme_stylebox_override("focus", _card_box(COL_CARD_SEL, accent))
	card.tooltip_text = "Klick = Vorschau anhoeren"
	card.pressed.connect(func(): _preview_online(str(r.preview_url), set_id))
	UiTheme.attach_hover(card, 1.015)

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(136, 76)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(thumb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var t := Label.new()
	t.text = "%s — %s" % [str(r.artist), str(r.title)]
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", COL_TEXT)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var m := Label.new()
	m.text = "Mapped by %s  ·  %d Diffs  ·  ▶ Vorschau" % [str(r.creator), int(r.diffs)]
	m.add_theme_font_size_override("font_size", 12)
	m.add_theme_color_override("font_color", COL_DIM)
	m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(m)

	# Sterne-Badge: Bereich aller 4K-Diffs, farbcodiert.
	var stars_lo: float = float(r.stars)
	var stars_hi: float = float(r.stars)
	for sv in r.get("star_list", []):
		stars_lo = minf(stars_lo, float(sv))
		stars_hi = maxf(stars_hi, float(sv))
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bb := UiTheme.solid_box(Color(accent.r, accent.g, accent.b, 0.92), 10)
	bb.content_margin_left = 10
	bb.content_margin_right = 10
	bb.content_margin_top = 4
	bb.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", bb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := Label.new()
	bl.text = ("★ %.1f" % stars_hi) if absf(stars_hi - stars_lo) < 0.05 \
			else "★ %.1f – %.1f" % [stars_lo, stars_hi]
	bl.add_theme_font_size_override("font_size", 13)
	bl.add_theme_color_override("font_color", Color(0.03, 0.05, 0.08))
	badge.add_child(bl)
	hb.add_child(badge)

	var dl := Button.new()
	dl.text = "⤓ Download"
	dl.custom_minimum_size = Vector2(132, 44)
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(dl, true)
	dl.pressed.connect(func(): _start_download(set_id))
	hb.add_child(dl)

	_dl_rows[set_id] = { "card": card, "btn": dl, "thumb": thumb }
	# Laeuft fuer dieses Set schon ein Download (vor dem Szenenwechsel
	# gestartet)? Dann den Fortschritt direkt wieder anzeigen.
	if _mirror.is_downloading(set_id):
		dl.disabled = true
		dl.text = "%d %%" % int(maxf(_mirror.active_ratio(set_id), 0.0) * 100.0)
	if str(r.cover_url) != "":
		_mirror.fetch_cover(set_id, str(r.cover_url))
	return card


func _on_mirror_cover_ready(set_id: int, texture: Texture2D) -> void:
	if _dl_rows.has(set_id):
		var thumb: TextureRect = _dl_rows[set_id].thumb
		if is_instance_valid(thumb):
			thumb.texture = texture


func _start_download(set_id: int) -> void:
	if not _dl_rows.has(set_id):
		return
	var btn: Button = _dl_rows[set_id].btn
	btn.disabled = true
	btn.text = "0 %"
	_mirror.download(set_id, _library.maps_dir)


func _on_mirror_download_progress(set_id: int, ratio: float) -> void:
	if _dl_rows.has(set_id):
		var btn: Button = _dl_rows[set_id].btn
		if is_instance_valid(btn):
			btn.text = "%d %%" % int(ratio * 100.0)


func _on_mirror_download_failed(set_id: int, message: String) -> void:
	if _dl_rows.has(set_id):
		var btn: Button = _dl_rows[set_id].btn
		if is_instance_valid(btn):
			btn.disabled = false
			btn.text = "Erneut"
	if _pack_active and _pack_started.has(set_id):
		_pack_done += 1
		_update_pack_status()
		return
	if _dl_status != null:
		_dl_status.text = message


func _on_mirror_download_done(set_id: int, osz_path: String) -> void:
	if _dl_rows.has(set_id):
		var btn: Button = _dl_rows[set_id].btn
		if is_instance_valid(btn):
			btn.text = "✓ Fertig"
	# Bibliothek neu scannen; beim Pack-Download NICHT staendig umselektieren.
	_library.scan()
	_refresh_filter(_search.text)
	if _pack_active and _pack_started.has(set_id):
		_pack_done += 1
		_update_pack_status()
		return
	if _dl_status != null:
		_dl_status.text = "Heruntergeladen — Bibliothek wird aktualisiert…"
	for ms in _filtered:
		if ms.osz_path == osz_path:
			_select_set(ms, ms.difficulty_count() - 1)
			break


## Online-Vorschau: Preview-MP3 direkt streamen. Liefert der Mirror keine
## preview_url, greift die offizielle osu-Preview (b.ppy.sh/preview/<id>.mp3).
func _preview_online(url: String, set_id: int = -1) -> void:
	url = url.strip_edges()
	if url.begins_with("//"):
		url = "https:" + url
	if url == "" and set_id > 0:
		url = "https://b.ppy.sh/preview/%d.mp3" % set_id
	if url == "":
		return
	if _dl_preview_req == null:
		_dl_preview_req = HTTPRequest.new()
		_dl_preview_req.timeout = 12.0
		add_child(_dl_preview_req)
		_dl_preview_req.request_completed.connect(_on_preview_bytes)
	_dl_preview_req.cancel_request()
	if _dl_status != null:
		_dl_status.text = "♪ Vorschau laedt…"
	if _dl_preview_req.request(url) != OK and _dl_status != null:
		_dl_status.text = "Vorschau nicht verfuegbar."


func _on_preview_bytes(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		if _dl_status != null:
			_dl_status.text = "Vorschau nicht verfuegbar."
		return
	# b.ppy.sh liefert trotz .mp3-Endung OGG Vorbis — Magic-Bytes pruefen.
	var stream: AudioStream = null
	if body.size() > 4 and body[0] == 0x4F and body[1] == 0x67 \
			and body[2] == 0x67 and body[3] == 0x53:
		stream = AudioStreamOggVorbis.load_from_buffer(body)
	else:
		var mp3 := AudioStreamMP3.new()
		mp3.data = body
		if mp3.get_length() > 0.0:
			stream = mp3
	if stream == null:
		if _dl_status != null:
			_dl_status.text = "Vorschau nicht abspielbar."
		return
	_preview.stream = stream
	_fade_in_preview(0.0)
	if _dl_status != null:
		_dl_status.text = "♪ Vorschau laeuft"



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


func _card_box(bg: Color, accent: Color, selected: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.border_width_left = 6
	sb.border_color = accent
	# Weicher Schatten unter jeder Karte — die Liste bekommt Tiefe.
	sb.shadow_size = 7
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(0, 3)
	if selected:
		# Ausgewaehlte Karte: feiner Akzent-Rand + leicht hellere Flaeche
		# (klar erkennbar, aber ohne Neon-Glow).
		sb.set_border_width_all(2)
		sb.border_width_left = 6
		sb.bg_color = bg.lightened(0.06)
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


func _icon_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 34)
	b.add_theme_stylebox_override("normal", _rounded_box(Color(0.14, 0.14, 0.18, 0.9), 8))
	b.add_theme_stylebox_override("hover", _rounded_box(Color(0.2, 0.2, 0.26, 0.95), 8))
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


func _star_icons(stars: float) -> String:
	if stars < 0.0:
		return "—"
	var n := clampi(int(floor(stars)), 1, 8)
	var out := ""
	for i in n:
		out += "★"
	return out


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
