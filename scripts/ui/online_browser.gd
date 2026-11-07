class_name OnlineBrowser
extends Control

## Online-Tab des Song-Browsers: Maps vom Mirror (catboy.best, sortiert ueber
## osu.direct) suchen, nach Genre/Sternen/SV filtern, sortieren und laden.
## Raster aus Karten (Cover gross, Titel/Artist/Mapper, Sterne je 4K-Diff,
## BPM, Laenge, Status, Download mit Fortschritt). Unendliches Scrollen.
## Bleibt nach dem Schliessen versteckt am Leben (Downloads/Pack laufen weiter,
## Ergebnisse + Scrollposition bleiben beim naechsten Oeffnen erhalten).
## Wiedergabe der Vorschau macht der Song-Browser (Signal preview_stream).

signal closed
signal preview_stream(stream: AudioStream)
signal preview_stop
## Download fertig. select = Map direkt anwaehlen (nicht beim Pack).
signal map_downloaded(set_id: int, osz_path: String, select: bool)

const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const CARD_BG := Color(0.075, 0.08, 0.115, 0.96)
const CARD_BG_HOVER := Color(0.10, 0.11, 0.155, 0.98)
const ERROR_COL := Color(1.0, 0.42, 0.45)
const CARD_MIN_W := 360.0
const CARD_RADIUS := 14
const COVER_H := 150.0
const GRID_SEP := 16
const SCROLL_STEP := 140.0
## Sichtbare Karten, ab denen nicht mehr automatisch nachgeladen wird.
const AUTO_FILL_TARGET := 20

## Sternfilter des Online-Browsers (inkl. Anfaenger-Stufe): [Text, lo, hi).
const STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["Anfänger ≤ 1,5", 0.0, 1.5],
	["1,5–2", 1.5, 2.0],
	["2–3", 2.0, 3.0],
	["3–4", 3.0, 4.0],
	["4–6", 4.0, 6.0],
	["6 +", 6.0, 999.0],
]

const _COVER_CODE := "shader_type canvas_item;
uniform vec2 rect_size = vec2(400.0, 150.0);
uniform float radius = 14.0;
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// Unten leicht abdunkeln: Pills oben bleiben lesbar, Kante zur Info weich.
	float y = clamp(local.y / rect_size.y, 0.0, 1.0);
	c.rgb *= mix(1.0, 0.72, smoothstep(0.55, 1.0, y));
	// Nur obere Ecken runden (unten schliesst die Info-Flaeche an).
	vec2 p = vec2(local.x, min(local.y, rect_size.y * 0.5));
	vec2 q = abs(p - rect_size * 0.5) - (rect_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
"

var library: MapLibrary
var _mirror: BeatmapMirror

# Filter / Sortierung
var star_filter := 0
var genre_id := 0
var sort_mode := BeatmapMirror.Sort.RELEVANCE
var status_mode := BeatmapMirror.STATUS_RANKED
var sv_filter := false

# Such-Zustand
var _results: Array = []
var _rows: Dictionary = {}
var _owned: Dictionary = {}
var _query := ""
var _offset := 0
var _end_reached := false
var _loading := false
var _auto_pages := 0
var _suggest_fallback := false
var _error := ""
var _searched_once := false

# Pack-Download: N fehlende Sets in einem Sternbereich automatisch laden.
var _pack_active := false
var _pack_lo := 2.0
var _pack_hi := 2.9
var _pack_want := 10
var _pack_pages := 0
var _pack_started: Dictionary = {}
var _pack_done := 0
var _pack_retries := 0

# Vorschau
var _preview_req: HTTPRequest
var _preview_set := -1

# UI
var _panel: PanelContainer
var _search: LineEdit
var _status: Label
var _dl_info: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _footer: Label
var _state_box: VBoxContainer
var _state_title: Label
var _state_sub: Label
var _state_btn: Button
var _genre_chips: Array[Button] = []
var _star_chips: Array[Button] = []
var _sort_chips: Array[Button] = []
var _status_chips: Array[Button] = []
var _sv_chip: Button
var _pack_row: HBoxContainer
var _pack_lo_spin: SpinBox
var _pack_hi_spin: SpinBox
var _pack_n_opt: OptionButton
var _skeleton_tw: Tween
var _cover_mat: ShaderMaterial
var _cover_size := Vector2.ZERO
var _card_box: StyleBoxFlat
var _card_box_hover: StyleBoxFlat
var _err_box: StyleBoxFlat
var _err_box_hover: StyleBoxFlat
var _inst_box: StyleBoxFlat
var _chip_styles: Dictionary = {}
var _scroll_target := 0.0
var _scroll_anim := false


func _init(lib: MapLibrary) -> void:
	library = lib
	name = "OnlineBrowser"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Autoload per Pfad: im --script-Modus (Headless-Tests) gibt es den
	# globalen Namen "Mirror" beim Kompilieren nicht.
	_mirror = get_node("/root/Mirror") as BeatmapMirror
	_mirror.search_done.connect(_on_search_done)
	_mirror.search_failed.connect(_on_search_failed)
	_mirror.cover_ready.connect(_on_cover_ready)
	_mirror.download_progress.connect(_on_dl_progress)
	_mirror.download_done.connect(_on_dl_done)
	_mirror.download_failed.connect(_on_dl_failed)
	_mirror.download_cancelled.connect(_on_dl_cancelled)
	_mirror.sv_checked.connect(_on_sv_checked)
	_init_styles()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_process(false)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_layout()
	_search.grab_focus.call_deferred()
	if not _searched_once:
		_run_search()
	else:
		# Besitz kann sich geaendert haben (Import, geloescht) -> neu filtern.
		_render()


func close() -> void:
	if not visible:
		return
	visible = false
	_stop_preview()
	if not _pack_active:
		_mirror.cancel_sv_checks()
	_mirror.cancel_covers()
	closed.emit()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _init_styles() -> void:
	var sh := Shader.new()
	sh.code = _COVER_CODE
	_cover_mat = ShaderMaterial.new()
	_cover_mat.shader = sh
	_cover_mat.set_shader_parameter("radius", float(CARD_RADIUS))
	_card_box = _box(CARD_BG, CARD_RADIUS, Color(1, 1, 1, 0.06), 1)
	_card_box.shadow_size = 8
	_card_box.shadow_color = Color(0, 0, 0, 0.28)
	_card_box.shadow_offset = Vector2(0, 3)
	_card_box_hover = _box(CARD_BG_HOVER, CARD_RADIUS, Color(ACCENT, 0.55), 1)
	_card_box_hover.shadow_size = 14
	_card_box_hover.shadow_color = Color(0, 0, 0, 0.40)
	_card_box_hover.shadow_offset = Vector2(0, 6)
	_err_box = _box(Color(ERROR_COL, 0.10), 10, Color(ERROR_COL, 0.55), 1)
	_err_box_hover = _box(Color(ERROR_COL, 0.18), 10, Color(ERROR_COL, 0.8), 1)
	_inst_box = _box(Color(UiTheme.GOOD, 0.08), 10, Color(UiTheme.GOOD, 0.45), 1)
	for active in [false, true]:
		var n := _box(Color(ACCENT, 0.16) if active else Color(1, 1, 1, 0.035), 16,
			Color(ACCENT, 0.85) if active else Color(1, 1, 1, 0.12), 1)
		n.content_margin_left = 14
		n.content_margin_right = 14
		n.content_margin_top = 4
		n.content_margin_bottom = 4
		var h: StyleBoxFlat = n.duplicate()
		h.bg_color = Color(ACCENT, 0.24) if active else Color(1, 1, 1, 0.09)
		h.border_color = Color(ACCENT, 1.0) if active else Color(1, 1, 1, 0.26)
		_chip_styles[active] = [n, h]


func _box(bg: Color, radius: int, border: Color = Color.TRANSPARENT, bw: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	sb.anti_aliasing = true
	return sb


func _build() -> void:
	var backdrop := UiTheme.modal_backdrop(self)
	backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())

	_panel = PanelContainer.new()
	var pb := UiTheme.glass_box(20, 0.88, 0.12)
	pb.set_content_margin_all(28)
	pb.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", pb)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)

	# Kopf: Titel + Quelle, Schliessen rechts.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	var title := Label.new()
	title.text = "ONLINE-MAPS"
	title.add_theme_font_override("font", UiTheme.heading_font(3))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TEXT)
	head.add_child(title)
	var src := Label.new()
	src.text = "4K-Mania  ·  catboy.best  ·  installierte Maps ausgeblendet"
	src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	src.add_theme_font_size_override("font_size", 13)
	src.add_theme_color_override("font_color", DIM)
	head.add_child(src)
	_dl_info = Label.new()
	_dl_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dl_info.add_theme_font_size_override("font_size", 13)
	_dl_info.add_theme_color_override("font_color", ACCENT)
	head.add_child(_dl_info)
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Schließen (Esc)"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	UiTheme.style_ghost_button(x, 10)
	x.pressed.connect(close)
	head.add_child(x)

	# Suche
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	vb.add_child(srow)
	_search = LineEdit.new()
	_search.placeholder_text = "Titel, Artist oder Mapper suchen …"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 44)
	_search.add_theme_font_size_override("font_size", 16)
	var sn := UiTheme.glass_box(12, 0.55)
	sn.content_margin_left = 16
	sn.content_margin_right = 12
	var sf: StyleBoxFlat = sn.duplicate()
	sf.border_color = Color(ACCENT, 0.7)
	_search.add_theme_stylebox_override("normal", sn)
	_search.add_theme_stylebox_override("focus", sf)
	_search.text_submitted.connect(func(_t): _run_search())
	srow.add_child(_search)
	var go := Button.new()
	go.text = "Suchen"
	go.custom_minimum_size = Vector2(124, 44)
	UiTheme.style_button(go, true)
	go.pressed.connect(_run_search)
	srow.add_child(go)
	var pack_toggle := Button.new()
	pack_toggle.text = "Pack …"
	pack_toggle.tooltip_text = "Mehrere fehlende Maps eines Sternbereichs auf einmal laden"
	pack_toggle.custom_minimum_size = Vector2(0, 44)
	UiTheme.style_ghost_button(pack_toggle, 12)
	pack_toggle.pressed.connect(func(): _pack_row.visible = not _pack_row.visible)
	srow.add_child(pack_toggle)

	# Genre-Chips (umbrechend).
	var grow := _filter_row(vb, "Genre")
	_genre_chips.append(_chip(grow, "Alle", func(): _set_genre(0)))
	_genre_chips[0].set_meta("genre", 0)
	for g in BeatmapMirror.GENRES:
		var gid := int(g[0])
		var c := _chip(grow, str(g[1]), func(): _set_genre(gid))
		c.set_meta("genre", gid)
		_genre_chips.append(c)

	# Sterne + SV, rechts davon Sortierung und Status.
	var frow := _filter_row(vb, "Sterne")
	for fi in STAR_FILTERS.size():
		_star_chips.append(_chip(frow, STAR_FILTERS[fi][0], func(): _set_star_filter(fi)))
	_sv_chip = _chip(frow, "SV", func(): _set_sv(not sv_filter))
	_sv_chip.tooltip_text = "Nur Maps mit Scroll-Velocity (geprüft an der echten .osu)"
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	frow.add_child(gap)
	_caption(frow, "Sortieren")
	for si in BeatmapMirror.SORT_LABELS.size():
		_sort_chips.append(_chip(frow, BeatmapMirror.SORT_LABELS[si], func(): _set_sort(si)))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(18, 0)
	frow.add_child(gap2)
	_status_chips.append(_chip(frow, "Ranked", func(): _set_status(BeatmapMirror.STATUS_RANKED)))
	_status_chips.append(_chip(frow, "Loved", func(): _set_status(BeatmapMirror.STATUS_LOVED)))

	_build_pack_row(vb)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", DIM)
	vb.add_child(_status)

	# Ergebnisbereich: Raster im Scroll, darueber Leer-/Fehler-Zustand.
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	vb.add_child(area)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	_scroll.add_child(content)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GRID_SEP)
	_grid.add_theme_constant_override("v_separation", GRID_SEP)
	content.add_child(_grid)
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.custom_minimum_size = Vector2(0, 36)
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", DIM)
	content.add_child(_footer)
	_scroll.resized.connect(_update_columns)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)

	_state_box = VBoxContainer.new()
	_state_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_state_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_state_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_state_box.add_theme_constant_override("separation", 10)
	_state_box.visible = false
	area.add_child(_state_box)
	_state_title = Label.new()
	_state_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_title.add_theme_font_override("font", UiTheme.heading_font(2))
	_state_title.add_theme_font_size_override("font_size", 22)
	_state_title.add_theme_color_override("font_color", TEXT)
	_state_box.add_child(_state_title)
	_state_sub = Label.new()
	_state_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_sub.custom_minimum_size = Vector2(520, 0)
	_state_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_sub.add_theme_font_size_override("font_size", 14)
	_state_sub.add_theme_color_override("font_color", DIM)
	_state_box.add_child(_state_sub)
	var bwrap := CenterContainer.new()
	_state_box.add_child(bwrap)
	_state_btn = Button.new()
	_state_btn.custom_minimum_size = Vector2(220, 42)
	UiTheme.style_button(_state_btn, true)
	bwrap.add_child(_state_btn)

	_restyle_chips()


func _filter_row(parent: Node, caption: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	parent.add_child(row)
	_caption(row, caption)
	return row


func _caption(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(76 if text == "Genre" or text == "Sterne" else 0, 32)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", DIM)
	parent.add_child(l)


func _chip(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	UiTheme._attach_sounds(b)
	parent.add_child(b)
	return b


func _apply_chip(b: Button, active: bool) -> void:
	var st: Array = _chip_styles[active]
	b.add_theme_stylebox_override("normal", st[0])
	b.add_theme_stylebox_override("hover", st[1])
	b.add_theme_stylebox_override("pressed", st[1])
	b.add_theme_stylebox_override("focus", st[1] if active else st[0])
	b.add_theme_color_override("font_color", TEXT if active else DIM)
	b.add_theme_color_override("font_hover_color", TEXT)


func _restyle_chips() -> void:
	for c in _genre_chips:
		_apply_chip(c, int(c.get_meta("genre")) == genre_id)
	for i in _star_chips.size():
		_apply_chip(_star_chips[i], i == star_filter)
	for i in _sort_chips.size():
		_apply_chip(_sort_chips[i], i == sort_mode)
	_apply_chip(_status_chips[0], status_mode == BeatmapMirror.STATUS_RANKED)
	_apply_chip(_status_chips[1], status_mode == BeatmapMirror.STATUS_LOVED)
	_apply_chip(_sv_chip, sv_filter)


func _build_pack_row(vb: VBoxContainer) -> void:
	_pack_row = HBoxContainer.new()
	_pack_row.add_theme_constant_override("separation", 8)
	_pack_row.visible = false
	vb.add_child(_pack_row)
	_caption(_pack_row, "Pack-Download")
	_pack_lo_spin = _star_spin(2.0)
	_pack_row.add_child(_pack_lo_spin)
	var dash := Label.new()
	dash.text = "–"
	_pack_row.add_child(dash)
	_pack_hi_spin = _star_spin(2.9)
	_pack_row.add_child(_pack_hi_spin)
	var star := Label.new()
	star.text = "★"
	star.add_theme_color_override("font_color", DIM)
	_pack_row.add_child(star)
	_pack_n_opt = OptionButton.new()
	for n in [5, 10, 20]:
		_pack_n_opt.add_item("%d Maps" % n, n)
	_pack_n_opt.select(1)
	_pack_n_opt.custom_minimum_size = Vector2(0, 32)
	_pack_row.add_child(_pack_n_opt)
	var btn := Button.new()
	btn.text = "Pack laden"
	btn.custom_minimum_size = Vector2(0, 34)
	UiTheme.style_button(btn, true)
	btn.pressed.connect(start_pack)
	_pack_row.add_child(btn)
	var hint := Label.new()
	hint.text = "berücksichtigt Genre und SV-Filter"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM)
	_pack_row.add_child(hint)


func _star_spin(v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0.0
	s.max_value = 10.0
	s.step = 0.1
	s.value = v
	s.custom_minimum_size = Vector2(88, 32)
	return s


func _layout() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size
	var w := minf(vp.x - 64.0, 1800.0)
	var h := vp.y - 48.0
	_panel.position = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
	_panel.size = Vector2(w, h)


func _update_columns() -> void:
	var w := _scroll.size.x - 14.0  # Platz fuer den Scrollbalken
	var cols := maxi(1, int((w + GRID_SEP) / (CARD_MIN_W + GRID_SEP)))
	if _grid.columns != cols:
		_grid.columns = cols


# ---------------------------------------------------------------------------
# Filter-Aktionen
# ---------------------------------------------------------------------------

func _set_genre(gid: int) -> void:
	genre_id = gid
	_auto_pages = 0
	_restyle_chips()
	_render()


func _set_star_filter(i: int) -> void:
	star_filter = i
	_auto_pages = 0
	_restyle_chips()
	_render()


func _set_sv(on: bool) -> void:
	sv_filter = on
	_mirror.sv_mode = on
	_restyle_chips()
	_run_search()


func _set_sort(i: int) -> void:
	if i == sort_mode:
		return
	sort_mode = i
	_restyle_chips()
	_run_search()


func _set_status(s: int) -> void:
	if s == status_mode:
		return
	status_mode = s
	_restyle_chips()
	_run_search()


func _reset_filters() -> void:
	genre_id = 0
	star_filter = 0
	sv_filter = false
	_mirror.sv_mode = false
	_restyle_chips()
	_run_search()


# ---------------------------------------------------------------------------
# Suche + Ergebnisse
# ---------------------------------------------------------------------------

func _run_search() -> void:
	var q := _search.text.strip_edges()
	_searched_once = true
	_suggest_fallback = q == "" and sort_mode == BeatmapMirror.Sort.RELEVANCE
	_query = q
	_offset = 0
	_end_reached = false
	_auto_pages = 0
	_loading = true
	_error = ""
	_results.clear()
	_mirror.cancel_sv_checks()
	_mirror.cancel_covers()
	_mirror.sv_mode = sv_filter
	_clear_grid()
	_show_skeleton()
	_say(("Suche „%s“ …" % q) if q != "" else "Lade Maps …")
	_mirror.search(q, 0, sort_mode, status_mode)


func _request_page() -> void:
	_loading = true
	_offset += BeatmapMirror.PAGE_SIZE
	_footer.text = "Lade weitere Maps …"
	_mirror.search(_query, _offset, sort_mode, status_mode)


func _on_search_failed(message: String) -> void:
	_loading = false
	if _pack_active:
		# Mirror-Aussetzer beim Pack: kurz warten, dieselbe Seite erneut.
		_pack_retries += 1
		if _pack_retries <= 5:
			_say("Mirror kurz nicht erreichbar – neuer Versuch …")
			get_tree().create_timer(1.5, true).timeout.connect(func():
				if _pack_active:
					_loading = true
					_mirror.search(_query, _offset, sort_mode, status_mode))
		else:
			_pack_active = false
			_say("Pack abgebrochen: Mirror nicht erreichbar.")
		return
	if _suggest_fallback and _offset == 0:
		_suggest_fallback = false
		_query = "4k"
		_loading = true
		_mirror.search("4k", 0, sort_mode, status_mode)
		return
	if _offset > 0:
		# Folgeseite: Liste bleibt, nur Fusszeile meldet den Fehler.
		_offset -= BeatmapMirror.PAGE_SIZE
		_footer.text = "Weitere Maps konnten nicht geladen werden – weiter scrollen für neuen Versuch."
		return
	_error = message
	_stop_skeleton()
	_clear_grid()
	_say("")
	_show_state("Mirror nicht erreichbar", message + "\nInternetverbindung prüfen und erneut versuchen.",
		"Erneut versuchen", _run_search)


func _on_search_done(results: Array, raw_count: int, offset: int) -> void:
	_loading = false
	_pack_retries = 0
	_end_reached = raw_count < BeatmapMirror.PAGE_SIZE
	var page := results
	# Clientseitig sortieren, wenn der Server es nicht tat (Fallback) — und
	# immer bei Sterne (Server sortiert nach der leichtesten Diff ALLER Modi).
	if not _mirror.last_server_sorted or sort_mode == BeatmapMirror.Sort.STARS:
		page = BeatmapMirror.sort_results(page, sort_mode)
	if offset == 0:
		if page.is_empty() and _suggest_fallback:
			_suggest_fallback = false
			_query = "4k"
			_loading = true
			_mirror.search("4k", 0, sort_mode, status_mode)
			return
		_suggest_fallback = false
		_results = page
		_render()
		if _pack_active:
			_pack_fill()
		return
	_results.append_array(page)
	if _pack_active:
		_pack_fill()
	if not visible:
		return
	# Naechste Seite: nur neue Karten anhaengen — Scrollposition bleibt.
	for r in page:
		if not _rows.has(int(r.id)) and _passes(r):
			_grid.add_child(_make_card(r))
	_update_status()
	_maybe_load_more()


## Alle Filter: nicht installiert, Genre, Sternbereich, SV (geprueft).
func _passes(r: Dictionary, lo: float = -1.0, hi: float = -1.0) -> bool:
	if lo < 0.0:
		lo = STAR_FILTERS[star_filter][1]
		hi = STAR_FILTERS[star_filter][2]
	if not visible_result(r, _owned, lo, hi, genre_id):
		return false
	if sv_filter:
		var sv_id := int(r.get("sv_id", 0))
		var state := _mirror.sv_state(sv_id)
		if state < 0:
			_mirror.check_sv(sv_id)
		return state == 1
	return true


## Filter-Kombination ohne SV (statisch, headless getestet): nicht in der
## Bibliothek (Set-ID oder Artist|Titel) UND Genre UND Sternbereich.
static func visible_result(r: Dictionary, owned: Dictionary, lo: float, hi: float, gid: int) -> bool:
	if owned.has(int(r.get("id", 0))):
		return false
	if owned.has(at_key(str(r.get("artist", "")), str(r.get("title", "")))):
		return false
	return BeatmapMirror.passes_filters(r, lo, hi, gid)


func _render() -> void:
	if _grid == null:
		return
	_stop_skeleton()
	_clear_grid()
	_owned = owned_set_ids(library)
	if _error != "":
		_show_state("Mirror nicht erreichbar", _error, "Erneut versuchen", _run_search)
		return
	var list := _results
	if not _mirror.last_server_sorted:
		list = BeatmapMirror.sort_results(_results, sort_mode)
	for r in list:
		if _passes(r):
			_grid.add_child(_make_card(r))
	_scroll.scroll_vertical = 0
	_scroll_target = 0.0
	_update_status()
	_maybe_load_more()


func _update_status() -> void:
	_update_dl_info()
	var n := _rows.size()
	var parts: Array[String] = []
	parts.append("%s %s" % [UiTheme.fmt_score(n), "Map" if n == 1 else "Maps"])
	if genre_id != 0:
		parts.append(BeatmapMirror.genre_label(genre_id))
	if star_filter != 0:
		parts.append(str(STAR_FILTERS[star_filter][0]) + " ★")
	if sv_filter:
		parts.append("SV")
	parts.append("sortiert: " + str(BeatmapMirror.SORT_LABELS[sort_mode]))
	if sv_filter and _mirror.sv_checks_pending() > 0:
		parts.append("prüfe SV … (%d offen)" % _mirror.sv_checks_pending())
	if not _pack_active:
		_say("  ·  ".join(parts))
	if _loading:
		_footer.text = "Lade weitere Maps …"
	elif _end_reached:
		_footer.text = "Ende der Liste" if n > 0 else ""
	else:
		_footer.text = "Weiter scrollen für mehr"
	if n == 0 and not _loading and _error == "":
		var can_more := not _end_reached and _auto_pages < _auto_cap()
		if can_more or (sv_filter and _mirror.sv_checks_pending() > 0):
			_show_state("Suche passende Maps …", "Lade weitere Seiten vom Mirror.", "", Callable())
		elif genre_id != 0 or star_filter != 0 or sv_filter:
			_show_state("Keine passenden Maps",
				"Mit diesen Filtern gibt es hier nichts Neues. Filter lockern oder anders suchen.",
				"Filter zurücksetzen", _reset_filters)
		elif _results.is_empty():
			_show_state("Keine Treffer", "Der Mirror kennt dazu keine 4K-Mania-Maps.", "", Callable())
		else:
			_show_state("Alles schon installiert", "Alle Treffer dieser Suche sind bereits in deiner Bibliothek.", "", Callable())
	elif n > 0:
		_state_box.visible = false


func _auto_cap() -> int:
	return 16 if genre_id != 0 or star_filter != 0 else 8


## Zu wenige sichtbare Karten (Filter/Besitz frisst viel raus)? Dann sofort
## weitere Server-Seiten holen — sonst gibt es keinen Scrollbalken und das
## unendliche Scrollen kaeme nie in Gang.
func _maybe_load_more() -> void:
	if _loading or _end_reached or not visible:
		return
	if _rows.size() >= AUTO_FILL_TARGET or _auto_pages >= _auto_cap():
		return
	if sv_filter and _mirror.sv_checks_pending() > 0:
		return
	_auto_pages += 1
	_request_page()
	_update_status()


func _on_scrolled(v: float) -> void:
	if not _scroll_anim:
		_scroll_target = v
	if _loading or _end_reached or _results.is_empty():
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar.value + bar.page < bar.max_value - 600.0:
		return
	_request_page()


func _on_sv_checked(beatmap_id: int, is_sv: bool) -> void:
	if not sv_filter:
		return
	if is_sv:
		for r in _results:
			if int(r.get("sv_id", 0)) == beatmap_id and not _rows.has(int(r.id)) and _passes(r):
				_grid.add_child(_make_card(r))
		if _pack_active:
			_pack_fill()
	if visible:
		_update_status()
		_maybe_load_more()


## Besitz-Erkennung: Set-IDs aus Dateinamen (fuehrende Zahl oder mirror_<id>)
## PLUS "artist|titel"-Schluessel aus der Bibliothek.
static func owned_set_ids(lib: MapLibrary) -> Dictionary:
	var owned := {}
	if lib == null:
		return owned
	var dir := DirAccess.open(lib.maps_dir)
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
	for ms in lib.mapsets:
		if ms.title != "":
			owned[at_key(ms.artist, ms.title)] = true
	return owned


## Nur Buchstaben/Ziffern vergleichen — Klammern, Spaces und Sonderzeichen
## unterscheiden sich zwischen Mirror und Datei oft.
static func at_key(artist: String, title: String) -> String:
	var raw := ("%s|%s" % [artist, title]).to_lower()
	var out := ""
	for ch in raw:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "|":
			out += ch
	return out


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg


func _show_state(title: String, sub: String, btn_text: String, action: Callable) -> void:
	_state_box.visible = true
	_state_title.text = title
	_state_sub.text = sub
	_state_btn.visible = btn_text != ""
	if btn_text != "":
		for c in _state_btn.pressed.get_connections():
			_state_btn.pressed.disconnect(c.callable)
		_state_btn.text = btn_text.to_upper()
		_state_btn.pressed.connect(action)


func _clear_grid() -> void:
	_state_box.visible = false
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_rows.clear()


# ---------------------------------------------------------------------------
# Lade-Zustand: Skelett-Karten mit sanftem Pulsieren
# ---------------------------------------------------------------------------

func _show_skeleton() -> void:
	_stop_skeleton()
	var n := maxi(_grid.columns, 1) * 2
	for i in n:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_box)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		var cover := Panel.new()
		cover.custom_minimum_size = Vector2(0, COVER_H)
		cover.add_theme_stylebox_override("panel", _cover_placeholder())
		v.add_child(cover)
		var m := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 16)
		v.add_child(m)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 10)
		m.add_child(lines)
		for wr in [0.7, 0.45, 0.6]:
			var bar := Panel.new()
			bar.custom_minimum_size = Vector2(CARD_MIN_W * wr, 12)
			bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			bar.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.06), 6))
			lines.add_child(bar)
		var btn := Panel.new()
		btn.custom_minimum_size = Vector2(0, 40)
		btn.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.05), 10))
		lines.add_child(btn)
		_grid.add_child(card)
	_skeleton_tw = create_tween().set_loops()
	_skeleton_tw.tween_property(_grid, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	_skeleton_tw.tween_property(_grid, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _stop_skeleton() -> void:
	if _skeleton_tw != null and _skeleton_tw.is_valid():
		_skeleton_tw.kill()
	_skeleton_tw = null
	_grid.modulate.a = 1.0


func _cover_placeholder() -> StyleBoxFlat:
	var sb := _box(Color(0.11, 0.12, 0.17), 0)
	sb.corner_radius_top_left = CARD_RADIUS
	sb.corner_radius_top_right = CARD_RADIUS
	return sb


# ---------------------------------------------------------------------------
# Karte
# ---------------------------------------------------------------------------

## osu!-aehnliche Farbskala fuer Star Rating.
static func star_color(stars: float) -> Color:
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


## "1:28" bzw. "1:02:03".
static func fmt_length(sec: int) -> String:
	if sec >= 3600:
		return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
	return "%d:%02d" % [sec / 60, sec % 60]


## Meta-Zeile einer Karte: "Elektronisch · 200 BPM · 1:28 · 1.962 Plays".
static func meta_line(r: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(BeatmapMirror.genre_label(int(r.get("genre_id", 1))))
	var bpm := float(r.get("bpm", 0.0))
	if bpm > 0.0:
		parts.append(UiTheme.fmt_num(bpm, 0 if is_equal_approx(bpm, roundf(bpm)) else 1) + " BPM")
	if int(r.get("length_s", 0)) > 0:
		parts.append(fmt_length(int(r.length_s)))
	parts.append(UiTheme.fmt_score(int(r.get("plays", 0))) + " Plays")
	return "  ·  ".join(parts)


func _pill(text: String, bg: Color, fg: Color, size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(bg, 8)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fg)
	p.add_child(l)
	return p


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_card(r: Dictionary) -> Control:
	var set_id: int = int(r.id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", _card_box_hover))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", _card_box))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# Cover (asynchron, gerundete Oberkante) mit Status- und Laengen-Pill.
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(0, COVER_H)
	holder.add_theme_stylebox_override("panel", _cover_placeholder())
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(holder)
	var cover := TextureRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cover.material = _cover_mat
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cover)
	cover.resized.connect(_on_cover_resized.bind(cover))
	var loved := str(r.get("status", "")) == "loved"
	var st := _pill("LOVED" if loved else "RANKED",
		Color(UiTheme.ACCENT2 if loved else ACCENT, 0.92), Color(0.03, 0.04, 0.07), 11)
	st.position = Vector2(12, 12)
	holder.add_child(st)
	var len_s := int(r.get("length_s", 0))
	if len_s > 0:
		var lp := _pill(fmt_length(len_s), Color(0, 0, 0, 0.62), TEXT, 12)
		lp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		lp.position = Vector2(-12, 12)
		holder.add_child(lp)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(m)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 5)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(info)
	var t := _label(str(r.title), 17, TEXT)
	t.add_theme_font_override("font", UiTheme.heading_font(0))
	info.add_child(t)
	info.add_child(_label("%s  ·  von %s" % [str(r.artist), str(r.creator)], 13, Color(TEXT, 0.78)))
	info.add_child(_label(meta_line(r), 12, DIM))

	# Sterne je 4K-Diff (aufsteigend), max. 5 + "+N", danach ggf. SV.
	var stars := HBoxContainer.new()
	stars.add_theme_constant_override("separation", 5)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.custom_minimum_size = Vector2(0, 26)
	info.add_child(stars)
	var sl: Array = r.get("star_list", [])
	for i in mini(sl.size(), 5):
		var s := float(sl[i])
		var col := star_color(s)
		var fg := Color(0.03, 0.04, 0.07) if s < 6.4 else Color(1, 1, 1, 0.95)
		stars.add_child(_pill(("★ " if i == 0 else "") + UiTheme.fmt_num(s, 2), col, fg))
	if sl.size() > 5:
		stars.add_child(_pill("+%d" % (sl.size() - 5), Color(1, 1, 1, 0.08), DIM))
	var sv_state := _mirror.sv_state(int(r.get("sv_id", 0)))
	if sv_state == 1 or (sv_state < 0 and bool(r.get("sv", false))):
		stars.add_child(_pill("SV", Color(UiTheme.ACCENT2, 0.22), UiTheme.ACCENT2))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(gap)

	# Aktionen: Vorschau + Download (Knopf / Fortschritt / installiert).
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 8)
	info.add_child(act)
	var play := Button.new()
	play.text = "▶"
	play.tooltip_text = "Vorschau anhören"
	play.custom_minimum_size = Vector2(44, 40)
	UiTheme.style_ghost_button(play, 10)
	play.pressed.connect(_toggle_preview.bind(r))
	act.add_child(play)
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(0, 40)
	act.add_child(stack)
	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.text = "Herunterladen"
	UiTheme.style_button(btn, true, 10)
	btn.pressed.connect(start_download.bind(set_id))
	stack.add_child(btn)
	var prog := ProgressBar.new()
	prog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prog.offset_right = -48
	prog.show_percentage = false
	prog.max_value = 1.0
	prog.step = 0.0
	var pbg := _box(Color(1, 1, 1, 0.06), 10, Color(1, 1, 1, 0.10), 1)
	var pfill := _box(Color(ACCENT, 0.55), 10)
	prog.add_theme_stylebox_override("background", pbg)
	prog.add_theme_stylebox_override("fill", pfill)
	prog.visible = false
	stack.add_child(prog)
	var plabel := Label.new()
	plabel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plabel.add_theme_font_size_override("font_size", 14)
	plabel.add_theme_color_override("font_color", TEXT)
	prog.add_child(plabel)
	var cancel := Button.new()
	cancel.text = "✕"
	cancel.tooltip_text = "Download abbrechen"
	cancel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	cancel.offset_left = -40
	cancel.visible = false
	UiTheme.style_ghost_button(cancel, 10)
	cancel.pressed.connect(func(): _mirror.cancel_download(set_id))
	stack.add_child(cancel)

	_rows[set_id] = {"card": card, "cover": cover, "btn": btn, "prog": prog,
		"plabel": plabel, "cancel": cancel, "play": play,
		"idle": [btn.get_theme_stylebox("normal"), btn.get_theme_stylebox("hover")]}
	if _mirror.is_downloading(set_id):
		_row_state(set_id, "loading", maxf(_mirror.active_ratio(set_id), 0.0))
	if _preview_set == set_id:
		play.text = "■"
	var cached := _mirror.cached_cover(set_id)
	if cached != null:
		cover.texture = cached
	elif str(r.get("cover_url", "")) != "":
		_mirror.fetch_cover(set_id, str(r.cover_url))
	return card


## Alle Cover teilen ein Material; nur bei Layout-Aenderung neu setzen.
func _on_cover_resized(cover: TextureRect) -> void:
	if cover.size.x > 0.0 and not cover.size.is_equal_approx(_cover_size):
		_cover_size = cover.size
		_cover_mat.set_shader_parameter("rect_size", cover.size)


func _on_cover_ready(set_id: int, texture: Texture2D) -> void:
	if not _rows.has(set_id):
		return
	var cover: TextureRect = _rows[set_id].cover
	if not is_instance_valid(cover) or cover.texture == texture:
		return
	cover.texture = texture
	cover.modulate.a = 0.0
	cover.create_tween().tween_property(cover, "modulate:a", 1.0, 0.2)


## Zustand eines Download-Bereichs: idle / loading / error / installed.
func _row_state(set_id: int, state: String, ratio: float = 0.0, msg: String = "") -> void:
	if not _rows.has(set_id):
		return
	var row: Dictionary = _rows[set_id]
	var btn: Button = row.btn
	var prog: ProgressBar = row.prog
	if not is_instance_valid(btn):
		return
	btn.visible = state != "loading"
	prog.visible = state == "loading"
	(row.cancel as Button).visible = state == "loading"
	btn.tooltip_text = msg
	match state:
		"loading":
			prog.value = ratio
			(row.plabel as Label).text = "Verbinde …" if ratio <= 0.0 else UiTheme.fmt_score(int(ratio * 100.0)) + " %"
		"error":
			btn.disabled = false
			btn.text = "ERNEUT VERSUCHEN"
			btn.add_theme_stylebox_override("normal", _err_box)
			btn.add_theme_stylebox_override("hover", _err_box_hover)
			btn.add_theme_color_override("font_color", ERROR_COL)
			btn.add_theme_color_override("font_hover_color", ERROR_COL.lightened(0.2))
		"installed":
			btn.disabled = true
			btn.text = "✓  INSTALLIERT"
			btn.add_theme_stylebox_override("disabled", _inst_box)
			btn.add_theme_color_override("font_disabled_color", UiTheme.GOOD)
		_:
			btn.disabled = false
			btn.text = "HERUNTERLADEN"
			btn.add_theme_stylebox_override("normal", row.idle[0])
			btn.add_theme_stylebox_override("hover", row.idle[1])
			btn.add_theme_color_override("font_color", Color(0.02, 0.05, 0.08))
			btn.add_theme_color_override("font_hover_color", Color(0.02, 0.05, 0.08))


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

func start_download(set_id: int) -> void:
	if _mirror.is_downloading(set_id):
		return  # Doppelklick
	_row_state(set_id, "loading", 0.0)
	_mirror.download(set_id, library.maps_dir)
	_update_dl_info()


func _update_dl_info() -> void:
	if _dl_info == null:
		return
	var n := _mirror.downloads_running()
	_dl_info.text = "" if n == 0 else ("%d Download läuft" % n if n == 1 else "%d Downloads laufen" % n)


func _on_dl_progress(set_id: int, ratio: float) -> void:
	if _rows.has(set_id):
		var row: Dictionary = _rows[set_id]
		var prog: ProgressBar = row.prog
		if is_instance_valid(prog):
			prog.visible = true
			prog.value = ratio
			(row.plabel as Label).text = UiTheme.fmt_score(int(ratio * 100.0)) + " %"


func _on_dl_failed(set_id: int, message: String) -> void:
	_row_state(set_id, "error", 0.0, message)
	_update_dl_info()
	if _pack_active and _pack_started.has(set_id):
		_pack_done += 1
		_update_pack_status()
		return
	if _rows.has(set_id):
		_say("Download fehlgeschlagen: " + message.trim_prefix("Download fehlgeschlagen "))


func _on_dl_cancelled(set_id: int) -> void:
	_row_state(set_id, "idle")
	_update_dl_info()
	if _pack_active and _pack_started.has(set_id):
		_pack_done += 1
		_update_pack_status()


func _on_dl_done(set_id: int, osz_path: String) -> void:
	_row_state(set_id, "installed")
	_owned[set_id] = true
	_update_dl_info()
	var in_pack := _pack_active and _pack_started.has(set_id)
	map_downloaded.emit(set_id, osz_path, not in_pack)
	if in_pack:
		_pack_done += 1
		_update_pack_status()


# ---------------------------------------------------------------------------
# Pack-Download
# ---------------------------------------------------------------------------

func start_pack() -> void:
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
	_say("Pack: suche Maps zwischen %s und %s ★ …" % [UiTheme.fmt_num(_pack_lo), UiTheme.fmt_num(_pack_hi)])
	_pack_fill()


func _pack_fill() -> void:
	if not _pack_active:
		return
	_owned = owned_set_ids(library)
	for r in _results:
		if _pack_started.size() >= _pack_want:
			break
		var sid := int(r.id)
		if _pack_started.has(sid) or _mirror.is_downloading(sid):
			continue
		if not _passes(r, _pack_lo, _pack_hi + 0.0001):
			continue
		_pack_started[sid] = true
		start_download(sid)
	if _pack_started.size() < _pack_want and not _end_reached \
			and not _loading and _pack_pages < 12:
		_pack_pages += 1
		_loading = true
		_offset += BeatmapMirror.PAGE_SIZE
		# Den Mirror nicht mit Request-Bursts fluten (drosselt sonst).
		get_tree().create_timer(0.45, true).timeout.connect(func():
			if _pack_active:
				_mirror.search(_query, _offset, sort_mode, status_mode)
			else:
				_loading = false)
	_update_pack_status()


func _update_pack_status() -> void:
	if not _pack_active:
		return
	var rng := "%s–%s ★" % [UiTheme.fmt_num(_pack_lo), UiTheme.fmt_num(_pack_hi)]
	if _pack_started.is_empty() and (_end_reached or _pack_pages >= 12):
		_pack_active = false
		_say("Pack: nichts Passendes im Bereich %s gefunden." % rng)
		return
	_say("Pack (%s): %d von %d fertig  ·  %d laufen" % [rng, _pack_done,
		_pack_started.size(), _pack_started.size() - _pack_done])
	if _pack_done >= _pack_started.size() \
			and (_pack_started.size() >= _pack_want or _end_reached or _pack_pages >= 12):
		_pack_active = false
		_say("Pack fertig: %d Maps geladen (%s)." % [_pack_done, rng])


# ---------------------------------------------------------------------------
# Vorschau (Preview-MP3 streamen; Fallback b.ppy.sh/preview/<id>.mp3)
# ---------------------------------------------------------------------------

func _toggle_preview(r: Dictionary) -> void:
	var set_id := int(r.id)
	if _preview_set == set_id:
		_stop_preview()
		return
	var url := str(r.get("preview_url", "")).strip_edges()
	if url.begins_with("//"):
		url = "https:" + url
	if url == "":
		url = "https://b.ppy.sh/preview/%d.mp3" % set_id
	if _preview_req == null:
		_preview_req = HTTPRequest.new()
		_preview_req.timeout = 12.0
		add_child(_preview_req)
		_preview_req.request_completed.connect(_on_preview_bytes)
	_preview_req.cancel_request()
	_set_preview_mark(set_id)
	if _preview_req.request(url, BeatmapMirror.headers()) != OK:
		_say("Vorschau nicht verfügbar.")
		_set_preview_mark(-1)


func _set_preview_mark(set_id: int) -> void:
	if _rows.has(_preview_set) and is_instance_valid(_rows[_preview_set].play):
		(_rows[_preview_set].play as Button).text = "▶"
	_preview_set = set_id
	if _rows.has(set_id) and is_instance_valid(_rows[set_id].play):
		(_rows[set_id].play as Button).text = "■"


func _stop_preview() -> void:
	if _preview_req != null:
		_preview_req.cancel_request()
	_set_preview_mark(-1)
	preview_stop.emit()


func _on_preview_bytes(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		_say("Vorschau nicht verfügbar.")
		_set_preview_mark(-1)
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
		_say("Vorschau nicht abspielbar.")
		_set_preview_mark(-1)
		return
	preview_stream.emit(stream)


# ---------------------------------------------------------------------------
# Weiches Scrollen: Mausrad setzt ein Ziel, _process gleitet hin und
# schaltet sich danach wieder ab (keine Arbeit pro Frame im Ruhezustand).
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not _scroll.get_global_rect().has_point(mb.position):
		return
	var bar := _scroll.get_v_scroll_bar()
	var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var f := mb.factor if mb.factor > 0.0 else 1.0
	_scroll_target = clampf(_scroll_target + dir * SCROLL_STEP * f, 0.0, maxf(bar.max_value - bar.page, 0.0))
	_scroll_anim = true
	set_process(true)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	var v := lerpf(bar.value, _scroll_target, 1.0 - exp(-delta * 16.0))
	if absf(v - _scroll_target) < 0.5:
		v = _scroll_target
		_scroll_anim = false
		set_process(false)
	bar.value = v


# ---------------------------------------------------------------------------
# Screenshot-Harness (--shot-online): Raster, Genre aktiv, Download laeuft,
# Fehlerzustand. Prueft dabei Genre-Filter + Sortierung am echten Mirror.
# ---------------------------------------------------------------------------

func run_shot_harness(dir: String) -> void:
	await _wait_loaded(20.0)
	await get_tree().create_timer(2.5).timeout
	await _shot(dir.path_join("online_grid.png"))
	print("SHOT-ONLINE grid: %d Karten, server_sorted=%s" % [_rows.size(), _mirror.last_server_sorted])

	# Genre Elektronisch + Beliebteste: alle Karten Genre 10, Plays absteigend.
	_set_genre(10)
	_set_sort(BeatmapMirror.Sort.PLAYS)
	await _wait_loaded(20.0)
	await get_tree().create_timer(2.5).timeout
	await _shot(dir.path_join("online_genre.png"))
	var ok_genre := true
	var ok_sort := true
	var last := 1 << 62
	for c in _grid.get_children():
		for r in _results:
			if _rows.has(int(r.id)) and _rows[int(r.id)].card == c:
				ok_genre = ok_genre and int(r.genre_id) == 10
				ok_sort = ok_sort and int(r.plays) <= last
				last = int(r.plays)
	print("SHOT-ONLINE genre: %d Karten, genre_ok=%s, sort_ok=%s, server_sorted=%s" % [
		_rows.size(), ok_genre, ok_sort, _mirror.last_server_sorted])

	# BPM-Sortierung (absteigend) gegen den echten Mirror.
	_set_genre(0)
	_set_sort(BeatmapMirror.Sort.BPM)
	await _wait_loaded(20.0)
	var bpms: Array = []
	for r in _results:
		if _rows.has(int(r.id)):
			bpms.append(float(r.bpm))
	var ok_bpm := bpms.size() > 1
	for i in range(1, bpms.size()):
		ok_bpm = ok_bpm and bpms[i] <= bpms[i - 1]
	print("SHOT-ONLINE bpm: %d Karten, sort_ok=%s, erste=%s" % [bpms.size(), ok_bpm, str(bpms.slice(0, 4))])

	# Download laeuft: erste Karte starten, Screenshot, abbrechen.
	_set_sort(BeatmapMirror.Sort.PLAYS)
	await _wait_loaded(20.0)
	await get_tree().create_timer(1.5).timeout
	var first := -1
	for c in _grid.get_children():
		for sid in _rows:
			if _rows[sid].card == c:
				first = sid
				break
		if first > 0:
			break
	if first > 0:
		start_download(first)
		start_download(first)  # Doppelklick darf nichts doppelt starten
		var w := 0.0
		while w < 8.0 and _mirror.active_ratio(first) < 0.15 and _mirror.is_downloading(first):
			await get_tree().create_timer(0.1).timeout
			w += 0.1
		await _shot(dir.path_join("online_download.png"))
		print("SHOT-ONLINE download: set=%d ratio=%.2f laufend=%d" % [
			first, _mirror.active_ratio(first), _mirror.downloads_running()])
		_mirror.cancel_download(first)
		await get_tree().process_frame
		var dest := library.maps_dir.path_join("mirror_%d.osz" % first)
		print("SHOT-ONLINE cancel: laufend=%d datei_weg=%s" % [
			_mirror.downloads_running(), not FileAccess.file_exists(dest)])

	# Fehlerzustand: unerreichbarer Mirror.
	_mirror.search_url_override = "https://mirror.invalid/api/v2/search"
	_run_search()
	var e := 0.0
	while _loading and e < 20.0:
		await get_tree().create_timer(0.2).timeout
		e += 0.2
	await get_tree().create_timer(0.5).timeout
	await _shot(dir.path_join("online_error.png"))
	print("SHOT-ONLINE error: sichtbar=%s text=%s" % [_state_box.visible, _state_title.text])
	_mirror.search_url_override = ""


func _wait_loaded(limit: float) -> void:
	var t := 0.0
	await get_tree().create_timer(0.3).timeout
	while (_loading or (sv_filter and _mirror.sv_checks_pending() > 0)) and t < limit:
		await get_tree().create_timer(0.2).timeout
		t += 0.2


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT gespeichert: " + path)
