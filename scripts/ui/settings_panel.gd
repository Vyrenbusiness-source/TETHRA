class_name SettingsPanel
extends Control

## Einstellungen im Stil von Song-Browser und Lobby (UiTheme: Graphit + Bernstein).
## Links eine Seitenleiste: Suche, aktiver Modus (Mania 3D / Mania 2D / Orbit,
## umschaltbar), darunter nur die Kategorien dieses Modus und die allgemeinen
## Kategorien (Audio, Grafik, Steuerung, Profil & Sprache). Rechts die Seite:
## ruhige Gruppen-Karten mit gleich hohen Zeilen (Beschriftung links, Bedienung
## in einer festen rechten Spalte), Vorschau fest daneben statt mitzuscrollen.
## Jede Zeile kennt ihren Wert (sync) und ihren Standard (reset): Seitenwechsel
## zieht Werte nach, "Zuruecksetzen" je Gruppe nutzt dieselbe Logik.

signal closed

const MODE_3D := 0
const MODE_2D := 1
const MODE_ORBIT := 2
const MODE_NAMES := ["Mania 3D", "Mania 2D", "Orbit"]

const SIDE_W := 236.0
const ROW_H := 42.0
const CTRL_H := 30.0
const CTRL_W := 290.0
const VALUE_W := 84.0
const PAD := 24
const FADE_H := 26.0

## Flaechen: Seitenleiste dunkler als die Seite, Karten eine Stufe heller.
const COL_SIDE := Color(0.084, 0.080, 0.075)
const COL_CARD := Color(0.131, 0.126, 0.117)
const COL_ROW_HOVER := Color(0.925, 0.902, 0.855, 0.035)
const COL_SEP := Color(0.925, 0.902, 0.855, 0.07)

## Seiten: id -> [Titel, Untertitel, Modi (leer = allgemein), Vorschau ("", "2d", "world")]
const PAGE_DEFS := {
	"field3d": ["Spielfeld & Welt", "Gilt für Mania 3D", [MODE_3D], "world"],
	"field2d": ["Spielfeld", "Gilt für Mania 2D", [MODE_2D], "2d"],
	"look2d": ["Skin & Bild", "Gilt für Mania 2D", [MODE_2D], "2d"],
	"orbit": ["Orbit", "Gilt für Orbit", [MODE_ORBIT], "orbit"],
	"notes": ["Notenfarben", "Gilt für Mania 3D und 2D", [MODE_3D, MODE_2D], ""],
	"audio": ["Audio", "Gilt für alle Modi", [], ""],
	"gfx": ["Grafik", "Gilt für alle Modi", [], ""],
	"keys": ["Steuerung", "Gilt für alle Modi", [], ""],
	"profile": ["Profil & Sprache", "Gilt für alle Modi", [], ""],
}
const PAGE_ORDER := ["field3d", "field2d", "look2d", "orbit", "notes", "audio", "gfx", "keys", "profile"]
const CAP_ORBIT := 20

var _mode := MODE_3D
var _cur := ""
var _defaults: Node            ## frische Settings-Instanz: Standardwerte fuer "Zuruecksetzen"
var _pages := {}               ## id -> {vb, rows: Array[Control]}
var _entries: Array = []       ## Suche: {cap, page, row}
var _build_pg := ""

var _panel: PanelContainer
var _scroll: ScrollContainer
var _fade_top: TextureRect
var _fade_bot: TextureRect
var _title: Label
var _subtitle: Label
var _nav: VBoxContainer
var _nav_btns := {}            ## id -> Button
var _mode_btns: Array[Button] = []
var _search: LineEdit
var _results: VBoxContainer
var _pv_col: VBoxContainer
var _pv_2d: Control
var _pv_world: Control
var _pv_world_holder: Control
var _pv_orbit: Control
var _pv_orbit_holder: Control
## Neue Vorschau (scripts/orbit/orbit_preview.gd) falls vorhanden, sonst Standbild.
var _orbit_preview: Control
var _orbit_pv_size := OrbitStill.SIZE_PX

var _nc: NoteColorPicker
var _world_preview: WorldPreview
var _preview_2d: Control
var _preview_bg: TextureRect
var _preview_stack: Control
var _preview_bg_label: Label
var _name_rows: VBoxContainer
var _skinvals_btn: CheckButton
var _cover_rows: Array[Control] = []
var _safe_hint: Label

var _capturing := 0   # 0 = keine Aufnahme, 3..6 = Spur 1-4, 20/21 = Orbit innen/aussen
var _lane_btns: Array[Button] = []
var _orbit_btns: Array[Button] = []   ## je zwei (innen, aussen) pro Ort, in dieser Reihenfolge

## Test-Harnesses (z.B. note_color_click_harness) lesen _panel.get("_note_colors") und
## scrollen danach zum Picker: der Zugriff von aussen zeigt die Seite Notenfarben.
var _note_colors: NoteColorPicker:
	get:
		if _nc != null and _cur != "notes" and _pages.has("notes"):
			_show_page("notes")
		return _nc


func _ready() -> void:
	Sfx.ui_open()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_defaults = Settings.get_script().new()
	_mode = _initial_mode()
	_build()
	get_viewport().size_changed.connect(_layout)
	if OS.get_cmdline_args().has("--shot-settings"):
		_shot_pages.call_deferred()


func _exit_tree() -> void:
	if _defaults != null:
		_defaults.free()
		_defaults = null


## Aktiver Modus: Orbit, wenn der Song-Browser (oder die Szene) auf Orbit steht,
## sonst Mania 2D/3D nach Settings.playfield_2d.
func _initial_mode() -> int:
	var host := get_parent()
	if host != null and "_play_mode" in host and String(host.get("_play_mode")) == "orbit":
		return MODE_ORBIT
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and scene.scene_file_path.contains("orbit"):
		return MODE_ORBIT
	if OS.get_cmdline_args().has("--orbit"):
		return MODE_ORBIT
	return MODE_2D if Settings.playfield_2d else MODE_3D


# ================================================================== Aufbau

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG.r * 0.5, UiTheme.BG.g * 0.5, UiTheme.BG.b * 0.5, 0.86)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(dim)

	_panel = PanelContainer.new()
	var psb := UiTheme.solid_box(UiTheme.SURFACE, 14)
	psb.set_border_width_all(1)
	psb.border_color = UiTheme.LINE
	_panel.add_theme_stylebox_override("panel", psb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	_panel.add_child(split)
	_build_sidebar(split)
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.custom_minimum_size = Vector2(1, 0)
	split.add_child(line)
	_build_content(split)

	_build_pages()
	_update_mode_buttons()
	_rebuild_nav()
	_show_page(_mode_pages()[0])
	_refresh_labels()
	_layout()
	_layout.call_deferred()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.15)


## Panel: Fenster minus Rand, nach oben begrenzt (1280x720 bis 2560x1440).
func _layout() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := Vector2(minf(vp.x - 48.0, 1480.0), minf(vp.y - 40.0, 940.0))
	_panel.position = ((vp - sz) * 0.5).floor()
	_panel.size = sz
	if _pv_world_holder != null:
		var s := 0.75 if vp.x < 1500.0 else 1.0
		_world_preview.scale = Vector2(s, s)
		_pv_world_holder.custom_minimum_size = WorldPreview.SIZE_PX * s
		_orbit_preview.scale = Vector2(s, s)
		_pv_orbit_holder.custom_minimum_size = _orbit_pv_size * s
	if _preview_2d != null and _preview_2d.has_method("set_box"):
		# Groesser als im Farb-Picker; Bildhoehe waechst mit, das Feld passt in die Breite.
		# Hoehe fuellt die Vorschau-Spalte (kein Leerraum unter dem Bild).
		var b := Vector2(300.0 if vp.x < 1500.0 else 340.0, clampf(sz.y - 230.0, 300.0, 620.0))
		_preview_2d.call("set_box", b)
		_preview_stack.custom_minimum_size = b
	if _cur != "":
		_arrange(_cur)
	_update_fades.call_deferred()


## Breite Seiten ohne Vorschau: Gruppen in zwei Spalten (keine langen Leerstrecken
## zwischen Beschriftung und Bedienung), sonst eine Spalte.
func _arrange(id: String) -> void:
	var pg: Dictionary = _pages[id]
	var cards: Array = pg.cards
	var free_w := _panel.size.x - SIDE_W - 2.0 * PAD
	var n := 2 if PAGE_DEFS[id][3] == "" and cards.size() >= 2 and free_w >= 1060.0 else 1
	if pg.get("cols", 1) == n and pg.has("cols"):
		return
	pg["cols"] = n
	var vb: VBoxContainer = pg.vb
	for c in cards:
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
	for c in vb.get_children():
		if c is HBoxContainer and c.name == "Cols":
			vb.remove_child(c)
			c.queue_free()
	if n == 1:
		for c in cards:
			vb.add_child(c)
		return
	var cols := HBoxContainer.new()
	cols.name = "Cols"
	cols.add_theme_constant_override("separation", 14)
	vb.add_child(cols)
	var a := VBoxContainer.new()
	var b := VBoxContainer.new()
	for col in [a, b]:
		col.add_theme_constant_override("separation", 14)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
	var total := 0
	for c in cards:
		total += _card_weight(c)
	var acc := 0
	for c in cards:
		if acc < total / 2.0 and (acc == 0 or acc + _card_weight(c) * 0.5 <= total / 2.0 + 1):
			a.add_child(c)
		else:
			b.add_child(c)
		acc += _card_weight(c)


func _card_weight(card: Control) -> int:
	return 1 + int(card.get_meta("rows").get_child_count())


func _build_sidebar(parent: Control) -> void:
	var side := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = COL_SIDE
	ssb.corner_radius_top_left = UiTheme.R_MAX
	ssb.corner_radius_bottom_left = UiTheme.R_MAX
	ssb.content_margin_left = 16
	ssb.content_margin_right = 16
	ssb.content_margin_top = 18
	ssb.content_margin_bottom = 14
	side.add_theme_stylebox_override("panel", ssb)
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	parent.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	side.add_child(col)

	var title := Label.new()
	title.text = "Einstellungen"
	title.add_theme_font_override("font", UiTheme.heading_font(0))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	col.add_child(title)
	col.add_child(_vgap(12))

	_search = LineEdit.new()
	_search.placeholder_text = "Einstellung suchen…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 32)
	_search.add_theme_font_size_override("font_size", 14)
	_search.tooltip_text = "Strg+F"
	_search.add_theme_color_override("clear_button_color", UiTheme.DIM)
	_search.add_theme_color_override("clear_button_color_pressed", UiTheme.TEXT)
	_search.text_changed.connect(_on_search)
	_search.text_submitted.connect(func(_t: String): _search_pick(0))
	col.add_child(_search)
	col.add_child(_vgap(18))

	col.add_child(_side_label("Modus"))
	col.add_child(_vgap(6))
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 2)
	col.add_child(seg)
	for m in 3:
		var b := Button.new()
		b.text = MODE_NAMES[m]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.tooltip_text = ["Mania mit 3D-Welt", "Klassische senkrechte Spuren", "Zwei Spuren auf wechselnden Bahnen"][m]
		b.pressed.connect(_set_mode.bind(m))
		UiTheme._attach_sounds(b)
		seg.add_child(b)
		_mode_btns.append(b)
	col.add_child(_vgap(16))

	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 2)
	col.add_child(_nav)
	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 2)
	_results.visible = false
	col.add_child(_results)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	var foot := Label.new()
	foot.text = "Wird beim Schließen gespeichert · Esc"
	foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.custom_minimum_size = Vector2(SIDE_W - 32.0, 0)
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(UiTheme.DIM, 0.8))
	col.add_child(foot)


func _build_content(parent: Control) -> void:
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", PAD)
	m.add_theme_constant_override("margin_right", PAD)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 0)
	parent.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	m.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tcol)
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.heading_font(0))
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UiTheme.TEXT)
	tcol.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", UiTheme.DIM)
	tcol.add_child(_subtitle)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(36, 36)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.tooltip_text = "Schließen (Esc)"
	UiTheme.style_ghost_button(x, 10)
	x.pressed.connect(_close)
	head.add_child(x)
	col.add_child(_vgap(12))
	col.add_child(UiTheme.hairline())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# Inhalt scrollt, mit weichen Kanten oben/unten (nur wenn dort Inhalt ist).
	var wrap := Control.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	body.add_child(wrap)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vsb := _scroll.get_v_scroll_bar()
	vsb.custom_minimum_size = Vector2(6, 0)
	var track := StyleBoxEmpty.new()
	vsb.add_theme_stylebox_override("scroll", track)
	vsb.add_theme_stylebox_override("scroll_focus", track)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(UiTheme.TEXT, 0.16 if st == "grabber" else 0.30)
		g.set_corner_radius_all(2)
		g.content_margin_left = 3
		g.content_margin_right = 3
		vsb.add_theme_stylebox_override(st, g)
	vsb.value_changed.connect(func(_v): _update_fades())
	vsb.changed.connect(_update_fades)
	wrap.add_child(_scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_top", 16)
	stack.add_theme_constant_override("margin_bottom", 20)
	stack.add_theme_constant_override("margin_right", 14)
	stack.name = "Stack"
	_scroll.add_child(stack)
	_fade_top = _fade(true)
	_fade_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_fade_top.offset_bottom = FADE_H
	_fade_top.offset_right = -10
	wrap.add_child(_fade_top)
	_fade_bot = _fade(false)
	_fade_bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_fade_bot.offset_top = -FADE_H
	_fade_bot.offset_right = -10
	wrap.add_child(_fade_bot)

	# Vorschau-Spalte: steht fest neben dem Inhalt.
	_pv_col = VBoxContainer.new()
	_pv_col.add_theme_constant_override("separation", 8)
	var pvm := MarginContainer.new()
	pvm.add_theme_constant_override("margin_top", 16)
	pvm.add_theme_constant_override("margin_bottom", 20)
	pvm.add_child(_pv_col)
	body.add_child(pvm)
	_pv_col.set_meta("wrap", pvm)


func _fade(top: bool) -> TextureRect:
	var g := Gradient.new()
	var c := UiTheme.SURFACE
	g.set_color(0, Color(c, 1.0) if top else Color(c, 0.0))
	g.set_color(1, Color(c, 0.0) if top else Color(c, 1.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 32
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _update_fades() -> void:
	if _scroll == null or _fade_top == null:
		return
	var sb := _scroll.get_v_scroll_bar()
	var room := sb.max_value - sb.page
	_fade_top.visible = sb.value > 1.0
	_fade_bot.visible = room > 1.0 and sb.value < room - 1.0


func _vgap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _side_label(t: String) -> Label:
	var l := UiTheme.section_label(t)
	l.add_theme_font_size_override("font_size", 11)
	return l


# ================================================================== Seiten

func _new_page(id: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.visible = false
	_scroll.get_node("Stack").add_child(vb)
	_pages[id] = {"vb": vb, "rows": [], "cards": []}
	_build_pg = id
	return vb


func _build_pages() -> void:
	_build_previews()
	_page_field3d(_new_page("field3d"))
	_page_field2d(_new_page("field2d"))
	_page_look2d(_new_page("look2d"))
	_page_orbit(_new_page("orbit"))
	_page_notes(_new_page("notes"))
	_page_audio(_new_page("audio"))
	_page_gfx(_new_page("gfx"))
	_page_keys(_new_page("keys"))
	_page_profile(_new_page("profile"))
	_build_pg = ""


func _page_field3d(pg: VBoxContainer) -> void:
	var g := _group(pg, "Spielfeld")
	_scroll_speed(g)
	_slider(g, "Spurbreite", Settings.LANE_SPACING_MIN * 100.0, Settings.LANE_SPACING_MAX * 100.0,
		Settings.LANE_SPACING_STEP * 100.0,
		func(s): return s.lane_spacing * 100.0,
		func(v): Settings.lane_spacing = Settings.clamp_lane_spacing(v / 100.0),
		func(v): return _fmt_pct0(Settings.clamp_lane_spacing(v / 100.0)),
		"Abstand der Spuren. Unter 85 % werden Noten kleiner")
	g = _group(pg, "Welt")
	_world_row(g)
	_choice(g, "Kamera", ["Komfort", "Dynamisch"],
		func(s): return s.camera_mode,
		func(i): Settings.camera_mode = i,
		"Komfort: ruhig · gegen Übelkeit · Dynamisch: volle Flugbewegung")
	_choice(g, "Effekte", ["Aus", "Dezent", "Voll"],
		func(s): return s.tunnel_intensity,
		func(i): Settings.tunnel_intensity = i,
		"Tunnel- und Welt-Effekte")


func _scroll_speed(g: VBoxContainer) -> Control:
	return _slider(g, "Scroll Speed", Settings.SCROLL_SPEED_MIN, Settings.SCROLL_SPEED_MAX, 1.0,
		func(s): return s.scroll_speed,
		func(v):
			Settings.scroll_speed = Settings.clamp_scroll_speed(v)
			Settings.scroll_speed_changed.emit(Settings.scroll_speed),
		func(v): return Settings.scroll_value_text(int(v)),
		"Zeit bis zur Trefferlinie (wie osu!lazer). Im Spiel F3/F4")


func _world_row(g: VBoxContainer) -> Control:
	var wt := OptionButton.new()
	wt.add_item("Automatisch", 0)
	for wi in Settings.WORLD_ORDER.size():
		var wname: String = Settings.WORLD_ORDER[wi]
		wt.add_item(str(WorldTheme.LABELS.get(wname, wname)), wi + 1)
		if wname != "galaxy" and not WorldTheme.is_available(wname):
			wt.set_item_disabled(wt.get_item_count() - 1, true)
	return _choice_ob(g, "Welt", wt,
		func(s): return s.world_theme,
		func(i):
			Settings.world_theme = i
			if _world_preview != null:
				_world_preview.show_world("" if i == 0 else Settings.WORLD_ORDER[i - 1]),
		"Automatisch: Welt passend zum Song")


func _page_field2d(pg: VBoxContainer) -> void:
	var g := _group(pg, "Noten")
	_scroll_speed(g)
	_choice(g, "Notenform", ["Balken", "Kreis"],
		func(s): return s.note_style_2d,
		func(i): Settings.note_style_2d = i)
	_slider(g, "Spurbreite", Settings.SIZE_2D_MIN * 100.0, Settings.SIZE_2D_MAX * 100.0,
		Settings.SIZE_2D_STEP * 100.0,
		func(s): return s.lane_width_2d * 100.0,
		func(v): Settings.lane_width_2d = Settings.clamp_2d_size(v / 100.0),
		func(v): return _fmt_pct0(Settings.clamp_2d_size(v / 100.0)),
		"Breite der Spalten (auch im Pausenmenü)")
	_slider(g, "Notengröße", Settings.SIZE_2D_MIN * 100.0, Settings.SIZE_2D_MAX * 100.0,
		Settings.SIZE_2D_STEP * 100.0,
		func(s): return s.note_size_2d * 100.0,
		func(v): Settings.note_size_2d = Settings.clamp_2d_size(v / 100.0),
		func(v): return _fmt_pct0(Settings.clamp_2d_size(v / 100.0)),
		"Höhe der Balken bzw. Größe der Kreise")
	_switch(g, "Hit-Lighting",
		func(s): return s.hit_lighting_2d,
		func(on): Settings.hit_lighting_2d = on,
		"Tasten und Skin-Lighting leuchten beim Treffer")

	g = _group(pg, "Layout")
	_choice(g, "Scroll-Richtung", ["Nach unten", "Nach oben"],
		func(s): return 1 if s.scroll_up_2d else 0,
		func(i): Settings.scroll_up_2d = i == 1,
		"Nach oben = osu! UpsideDown")
	_own_choice(g, "Position", ["Links", "Mitte", "Rechts"], "stage_pos_2d",
		"Überschreibt den Skin")
	_slider(g, "Skalierung", Settings.STAGE_SCALE_MIN * 100.0, Settings.STAGE_SCALE_MAX * 100.0, 5.0,
		func(s): return s.stage_scale_2d * 100.0,
		func(v): Settings.set_2d_option("stage_scale_2d", v / 100.0),
		func(v): return _fmt_pct0(Settings.clamp_2d_option("stage_scale_2d", v / 100.0)),
		"Größe des ganzen Spielfelds")
	_own_slider(g, "Trefferposition", Settings.HIT_POS_MIN, Settings.HIT_POS_MAX, "hit_position_2d",
		"osu! HitPosition, 480 = Bildrand")
	_own_slider(g, "Spaltenabstand", 0.0, Settings.COL_SPACING_MAX, "column_spacing_2d",
		"osu! ColumnSpacing")

	g = _group(pg, "Mods")
	_choice(g, "Sicht", ["Aus", "FadeIn", "Hidden", "Cover"],
		func(s): return s.mod_vis_2d,
		func(i):
			Settings.mod_vis_2d = i
			for r in _cover_rows:
				r.visible = i == Settings.VIS_COVER,
		"FadeIn: spät sichtbar · Hidden: verschwinden vor der Linie · Cover: feste Abdeckung")
	_cover_rows.append(_choice(g, "Abdeckung von", ["Oben", "Unten"],
		func(s): return 1 if s.cover_from_bottom_2d else 0,
		func(i): Settings.cover_from_bottom_2d = i == 1))
	_cover_rows.append(_slider(g, "Abdeckung", Settings.COVER_MIN, Settings.COVER_MAX, 5.0,
		func(s): return s.cover_pct_2d,
		func(v): Settings.set_2d_option("cover_pct_2d", v),
		func(v): return _fmt_pct0(v / 100.0),
		"Verdeckter Anteil der Strecke"))
	for r in _cover_rows:
		r.visible = Settings.mod_vis_2d == Settings.VIS_COVER
	_switch(g, "Konstante Geschwindigkeit",
		func(s): return s.mod_constant,
		func(on): Settings.mod_constant = on,
		"SV- und BPM-Wechsel ignorieren")


func _page_look2d(pg: VBoxContainer) -> void:
	if ResourceLoader.exists("res://scripts/ui/skin_picker.gd"):
		var g := _group(pg, "Skin", false)
		var skin = load("res://scripts/ui/skin_picker.gd").new()
		if skin is Control:
			if skin.has_signal("changed"):
				skin.connect("changed", _refresh_2d_preview)
			_embed_skin(g, skin)

	var g2 := _group(pg, "Map-Bild")
	_slider(g2, "Hintergrund", 0.0, 100.0, 5.0,
		func(s): return s.bg_dim * 100.0,
		func(v):
			Settings.bg_dim = Settings.clamp_bg_dim(v / 100.0)
			_refresh_bg_preview(),
		func(v): return _fmt_bg(Settings.clamp_bg_dim(v / 100.0)),
		"Deckkraft des Map-Bilds, 0 % = aus")
	_slider(g2, "Spielfeld abdunkeln", 0.0, 100.0, 5.0,
		func(s): return s.field_dim_2d * 100.0,
		func(v): Settings.field_dim_2d = Settings.clamp_bg_dim(v / 100.0),
		func(v): return _fmt_pct0(Settings.clamp_bg_dim(v / 100.0)),
		"100 % = schwarz, Map-Bild nur seitlich")
	_switch(g2, "Hintergrund-Unschärfe",
		func(s): return s.bg_blur,
		func(on): Settings.bg_blur = on,
		"Map-Bild unscharf zeichnen")

	var g3 := _group(pg, "Erweitert")
	_skinvals_btn = _switch(g3, "Skin-Werte nutzen",
		func(s): return s.skin_values_2d,
		func(on): Settings.skin_values_2d = on,
		"An: Layout aus skin.ini · Aus: eigene Werte").get_meta("ctrl")
	_own_slider(g3, "Judgement-Position", 0.0, 480.0, "judge_pos_2d", "osu! ScorePosition, 0 = oben")
	_own_slider(g3, "Kombo-Position", 0.0, 480.0, "combo_pos_2d", "osu! ComboPosition, 0 = oben")
	_own_switch(g3, "Tasten unter den Noten", "keys_under_notes_2d", "osu! KeysUnderNotes")
	_own_switch(g3, "Trefferlinie", "hit_line_2d", "Linie an der Trefferposition")


func _page_orbit(pg: VBoxContainer) -> void:
	var g := _group(pg, "Tasten")
	_orbit_key_row(g)
	_hint_label(g, "Akzent = beide Tasten zugleich. Maus links = A, Maus rechts = B gelten immer zusätzlich.")
	g = _group(pg, "Lesen")
	var laps := OptionButton.new()
	laps.add_item("Auto (aus AR)", 0)
	laps.add_item("1 Runde", 1)
	laps.add_item("2 Runden", 2)
	laps.add_item("3 Runden", 3)
	laps.add_item("4 Runden", 4)
	_choice_ob(g, "Vorlauf", laps,
		func(s): return s.orbit_laps,
		func(i): Settings.orbit_laps = i,
		"Runden des Satelliten bis zum Treffer. Auto: AR bis 5 drei, bis 8 zwei, ab 9 eine")
	var kh := OptionButton.new()
	kh.add_item("Auto", 0)
	kh.add_item("An", 1)
	kh.add_item("Aus", 2)
	_choice_ob(g, "Tasten in Zielen", kh,
		func(s): return s.orbit_key_hint,
		func(i): Settings.orbit_key_hint = i,
		"Taste im nächsten Ziel. Auto: bei leichten Maps und im Tutorial")
	g = _group(pg, "Darstellung")
	_slider(g, "Zielgröße", 90.0, 120.0, 5.0,
		func(s): return s.orbit_target_size,
		func(v): Settings.orbit_target_size = int(v),
		func(v): return "%d %%" % int(v),
		"Nur die Anzeige: der Trefferradius folgt der Map (CS)")
	_slider(g, "Cursor-Größe", 50.0, 150.0, 10.0,
		func(s): return s.orbit_cursor_size,
		func(v): Settings.orbit_cursor_size = int(v),
		func(v): return "%d %%" % int(v))
	var om := OptionButton.new()
	om.add_item("Aus", 0)
	om.add_item("Dezent", 1)
	om.add_item("Voll", 2)
	_choice_ob(g, "Musik-Reaktion", om,
		func(s): return s.orbit_music,
		func(i): Settings.orbit_music = i,
		"Orbit-Ringe pulsieren auf dem Beat, im Refrain etwas heller")
	var obg := OptionButton.new()
	obg.add_item("Welt", Settings.ORBIT_BG_WORLD)
	obg.add_item("Map-Bild", Settings.ORBIT_BG_MAP)
	obg.add_item("Aus", Settings.ORBIT_BG_OFF)
	if not WorldBackdrop.has_world_pack():
		# Ohne Welten-Paket zeigt "Welt" das Map-Bild.
		obg.set_item_text(0, tr("Welt") + " (" + tr("Map-Bild") + ")")
	_choice_ob(g, "Hintergrund", obg,
		func(s): return s.orbit_background,
		func(i): Settings.orbit_background = i,
		"Welt: die 3D-Welt, ruhig und abgedunkelt")
	_world_row(g)


func _page_notes(pg: VBoxContainer) -> void:
	var g := _group(pg, "Notenfarben", false)
	_nc = NoteColorPicker.new()
	_nc.show_mode(Settings.playfield_2d)
	_nc.changed.connect(_refresh_2d_preview)
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(side, 14)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 14)
	m.add_child(_nc)
	g.add_child(m)
	_register("Notenfarben", g)
	_register("Farbquelle", g)


func _page_audio(pg: VBoxContainer) -> void:
	var g := _group(pg, "Lautstärke & Klang")
	_slider(g, "Lautstärke", -30.0, 0.0, 1.0,
		func(s): return s.volume_db,
		func(v):
			Settings.volume_db = v
			Settings.apply(),
		func(v): return tr("Stumm") if v <= Settings.VOLUME_MIN_DB + 0.01 else "%d dB" % int(v),
		"Alt+Mausrad im Spiel")
	_switch(g, "Klarheit",
		func(s): return s.audio_enhance,
		func(on):
			Settings.audio_enhance = on
			Settings.apply(),
		"Hellere Höhen")
	var bass := _slider(g, "Bass", 0.0, 100.0, 5.0,
		func(s): return s.bass_boost * 100.0,
		func(v):
			Settings.bass_boost = v / 100.0
			Settings.apply(),
		func(v): return _fmt_pct0(v / 100.0))
	var bs: HSlider = bass.get_meta("ctrl")
	var no_fill := StyleBoxEmpty.new()
	var set_fill := func(v: float):
		# Bei 0 keine Fuellung: sieht sonst aus wie "ein bisschen Bass".
		if v <= 0.001:
			bs.add_theme_stylebox_override("grabber_area", no_fill)
			bs.add_theme_stylebox_override("grabber_area_highlight", no_fill)
		else:
			bs.remove_theme_stylebox_override("grabber_area")
			bs.remove_theme_stylebox_override("grabber_area_highlight")
	bs.value_changed.connect(set_fill)
	set_fill.call(bs.value)

	g = _group(pg, "Treffer")
	_switch(g, "Treffer-Sounds",
		func(s): return s.hitsounds,
		func(on): Settings.hitsounds = on)
	_choice(g, "Hitsound", ["Soft", "Clap", "Kick"],
		func(s): return s.hitsound_set,
		func(i):
			Settings.hitsound_set = i
			Sfx.preview_hit(i))
	_slider(g, "Treffer-Lautstärke", 0.0, 100.0, 5.0,
		func(s): return s.hitsound_volume * 100.0,
		func(v): Settings.hitsound_volume = v / 100.0,
		func(v): return _fmt_pct0(v / 100.0))

	g = _group(pg, "Timing")
	_slider(g, "Audio-Offset", -200.0, 200.0, 1.0,
		func(s): return s.offset_ms,
		func(v):
			Settings.offset_ms = v
			Settings.apply(),
		func(v): return "%+d ms" % int(v),
		"Verschiebt die Noten gegenüber dem Ton")
	var calib := Button.new()
	calib.text = "Assistent starten"
	calib.custom_minimum_size = Vector2(0, CTRL_H)
	calib.size_flags_horizontal = Control.SIZE_SHRINK_END
	UiTheme.style_button(calib)
	calib.add_theme_font_size_override("font_size", 14)
	calib.pressed.connect(_open_wizard)
	_row(g, "Offset-Assistent", calib, "Offset per Mitklopfen messen")


func _page_gfx(pg: VBoxContainer) -> void:
	var g := _group(pg, "Darstellung")
	_choice(g, "Qualität", ["Niedrig", "Mittel (2x AA)", "Hoch (4x AA)", "Ultra (8x AA)", "Extrem (8x AA + SSAA)"],
		func(s): return s.graphics_quality,
		func(i):
			Settings.graphics_quality = i
			Settings.apply())
	_choice(g, "FPS-Limit", ["VSync", "Unbegrenzt", "240 FPS", "360 FPS", "480 FPS"],
		func(s): return s.fps_mode,
		func(i):
			Settings.fps_mode = i
			Settings.apply())
	_switch(g, "Vollbild",
		func(s): return s.fullscreen,
		func(on):
			Settings.fullscreen = on
			Settings.apply(),
		"Auch mit F11")
	_switch(g, "Spur-Leuchten",
		func(s): return s.lane_glow,
		func(on): Settings.lane_glow = on,
		"Spur leuchtet beim Tastendruck")

	g = _group(pg, "Stabilität", false)
	var safe := _switch(g, "Sicherer Grafikmodus",
		func(_s): return GpuGuard.safe_mode,
		func(on):
			GpuGuard.set_safe_mode(on)
			Settings.apply()
			_safe_hint.get_parent().visible = true,
		"OpenGL, niedrigere Qualität, 240 FPS. Hilft bei Abstürzen")
	safe.set_meta("reset", Callable())
	_safe_hint = _hint_label(g, "Neustart des Spiels nötig, damit der Renderer wechselt.")
	_safe_hint.add_theme_color_override("font_color", UiTheme.ACCENT)
	_safe_hint.get_parent().visible = false


func _page_keys(pg: VBoxContainer) -> void:
	var g := _group(pg, "Mania")
	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 6)
	for i in 4:
		var b := _key_button(3 + i)
		lane_row.add_child(b)
		_lane_btns.append(b)
	var r := _row(g, "Tasten 1–4", lane_row, "Anklicken, dann Taste drücken (Esc bricht ab)")
	r.set_meta("reset", func():
		Settings.key_lanes = _defaults.key_lanes.duplicate()
		_refresh_labels())
	_hint_label(g, "Anklicken, dann Taste drücken (Esc bricht ab)")
	g = _group(pg, "Orbit")
	_orbit_key_row(g)
	_hint_label(g, "Akzent = beide Tasten zugleich. Maus links = A, Maus rechts = B gelten immer zusätzlich.")
	# Feste Kuerzel zum Nachschlagen (nicht belegbar).
	g = _group(pg, "Tastenkürzel", false)
	for k in [["Scroll Speed ändern", "F3 / F4"], ["Vollbild umschalten", "F11"],
			["Lautstärke ändern", "Alt + Mausrad"], ["Einstellungen durchsuchen", "Strg + F"]]:
		_row(g, k[0], _keycap(k[1]))


## Tastenkappe: kleine erhabene Flaeche mit Kuerzel (nur Anzeige).
func _keycap(t: String) -> Control:
	var pc := PanelContainer.new()
	var sb := UiTheme.solid_box(UiTheme.RAISED, 6)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.border_color = Color(UiTheme.TEXT, 0.12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiTheme.heading_font(0))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	pc.add_child(l)
	return pc


func _orbit_key_row(g: VBoxContainer) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	for ring in 2:
		var b := _key_button(CAP_ORBIT + ring)
		box.add_child(b)
		_orbit_btns.append(b)
	var r := _row(g, "Orbit-Tasten: A | B", box, "Links: Taste A (kühle Scheibe), rechts: Taste B (warmes Quadrat). Anklicken, dann Taste drücken (Esc bricht ab)")
	r.set_meta("reset", func():
		Settings.orbit_key_inner = _defaults.orbit_key_inner
		Settings.orbit_key_outer = _defaults.orbit_key_outer
		_refresh_labels())


func _key_button(which: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, CTRL_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.add_theme_font_override("font", UiTheme.heading_font(0))
	b.add_theme_font_size_override("font_size", 14)
	UiTheme.style_button(b)
	b.pressed.connect(_start_capture.bind(which))
	return b


func _page_profile(pg: VBoxContainer) -> void:
	var g := _group(pg, "Spielername", false)
	_name_rows = g
	_build_name_rows()
	g = _group(pg, "Sprache", false)
	# Sprache wirkt sofort (Settings.set_language baut die Szene neu auf).
	# Die Eintraege stehen immer in ihrer eigenen Sprache (nie uebersetzt).
	var lang := OptionButton.new()
	lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lang.add_item("English", 0)
	lang.add_item("Deutsch", 1)
	_choice_ob(g, "Spielsprache", lang,
		func(_s): return 1 if Settings.active_language() == "de" else 0,
		func(i): Settings.set_language("de" if i == 1 else "en"),
		"Wirkt sofort").set_meta("reset", Callable())


## Spielername: festgelegt -> nur der Name; sonst Eingabefeld + "Speichern"
## (einmalig, 2-16 Zeichen, nicht "Player").
func _build_name_rows() -> void:
	for c in _name_rows.get_children():
		_name_rows.remove_child(c)
		c.queue_free()
	var keep := _build_pg
	_build_pg = "profile"
	if not Settings.can_set_name():
		var shown := Label.new()
		shown.text = Settings.profile_name
		shown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		shown.add_theme_font_override("font", UiTheme.heading_font(0))
		shown.add_theme_font_size_override("font_size", 16)
		shown.add_theme_color_override("font_color", UiTheme.TEXT)
		_row(_name_rows, "Name", shown, "Der Name ist festgelegt")
		_hint_label(_name_rows, "Der Name ist festgelegt und kann nicht mehr geändert werden.")
		_build_pg = keep
		return
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var edit := LineEdit.new()
	edit.name = "NameEdit"
	edit.max_length = Settings.NAME_MAX_LEN
	edit.placeholder_text = tr("2–16 Zeichen")
	edit.custom_minimum_size = Vector2(0, CTRL_H)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(edit)
	var save_btn := Button.new()
	save_btn.name = "NameSave"
	save_btn.text = "Speichern"
	save_btn.custom_minimum_size = Vector2(0, CTRL_H)
	UiTheme.style_button(save_btn, true)
	line.add_child(save_btn)
	_row(_name_rows, "Name", line, "Kann nur einmal festgelegt werden")
	var hint := _hint_label(_name_rows, "Kann nur einmal geändert werden")
	hint.name = "NameHint"
	var submit := func():
		var err := Settings.set_name_once(edit.text)
		if err != "":
			hint.text = tr(err)
			hint.add_theme_color_override("font_color", UiTheme.BAD)
			return
		Sfx.ui_open()
		_build_name_rows()
	save_btn.pressed.connect(submit)
	edit.text_submitted.connect(func(_t: String): submit.call())
	_build_pg = keep


# ================================================================== Vorschau

func _build_previews() -> void:
	_pv_col.add_child(_pv_caption("Vorschau"))
	# 2D: Mini-Spielfeld vor einem Beispiel-"Map-Bild" mit der Hintergrund-Deckkraft.
	_pv_2d = VBoxContainer.new()
	_pv_2d.add_theme_constant_override("separation", 8)
	_pv_col.add_child(_pv_2d)
	if ResourceLoader.exists("res://scripts/ui/playfield_preview.gd"):
		_preview_2d = load("res://scripts/ui/playfield_preview.gd").new()
		var stack := Control.new()
		stack.custom_minimum_size = _preview_2d.custom_minimum_size
		_preview_stack = stack
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var black := ColorRect.new()
		black.color = Color.BLACK
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(black)
		_preview_bg = TextureRect.new()
		_preview_bg.texture = _sample_bg_texture()
		_preview_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_preview_bg.stretch_mode = TextureRect.STRETCH_SCALE
		_preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(_preview_bg)
		stack.add_child(_preview_2d)
		_pv_2d.add_child(_framed(stack))
		_preview_bg_label = _pv_caption("")
		_pv_2d.add_child(_preview_bg_label)
		_refresh_bg_preview()
	# Welt: eine Vorschau fuer Mania 3D und Orbit.
	_pv_world = VBoxContainer.new()
	_pv_world.add_theme_constant_override("separation", 8)
	_pv_col.add_child(_pv_world)
	_world_preview = WorldPreview.new()
	_pv_world_holder = Control.new()
	_pv_world_holder.custom_minimum_size = WorldPreview.SIZE_PX
	_pv_world_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_world_holder.add_child(_world_preview)
	_pv_world.add_child(_framed(_pv_world_holder))
	_world_preview.show_world(Settings.world_theme_name())
	# Orbit: echte Satelliten-Vorschau (Teil 3), ohne sie ein Standbild aus den Einstellungen.
	_pv_orbit = VBoxContainer.new()
	_pv_col.add_child(_pv_orbit)
	_orbit_preview = _make_orbit_preview()
	_orbit_pv_size = _orbit_preview.custom_minimum_size
	if _orbit_pv_size.x < 1.0:
		_orbit_pv_size = OrbitStill.SIZE_PX
	_pv_orbit_holder = Control.new()
	_pv_orbit_holder.custom_minimum_size = _orbit_pv_size
	_pv_orbit_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_orbit_holder.add_child(_orbit_preview)
	_pv_orbit.add_child(_framed(_pv_orbit_holder))


const ORBIT_PREVIEW_PATH := "res://scripts/orbit/orbit_preview.gd"


## Per Pfad geladen: die Vorschau entsteht in einer anderen Teil-Aufgabe, das
## Panel darf ohne sie nicht brechen.
func _make_orbit_preview() -> Control:
	if ResourceLoader.exists(ORBIT_PREVIEW_PATH):
		var sc := load(ORBIT_PREVIEW_PATH) as Script
		if sc != null and sc.can_instantiate():
			var pv = sc.new()
			if pv is Control:
				var c := pv as Control
				if c.custom_minimum_size.x < 1.0:
					var consts := sc.get_script_constant_map()
					if consts.get("SIZE_PX") is Vector2:
						c.custom_minimum_size = consts["SIZE_PX"]
				return c
			if pv is Node:
				(pv as Node).free()
	return OrbitStill.new()


func _pv_caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	return l


func _framed(inner: Control) -> Control:
	var pc := PanelContainer.new()
	var fb := UiTheme.solid_box(UiTheme.BG, 12)
	fb.set_border_width_all(1)
	fb.border_color = UiTheme.LINE
	fb.set_content_margin_all(1)
	pc.add_theme_stylebox_override("panel", fb)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.add_child(inner)
	return pc


## Beispiel-Hintergrund fuer die Vorschau (ruhiger Verlauf statt echtem Map-Bild).
static func _sample_bg_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.62, 0.40, 0.24))
	g.set_color(1, Color(0.20, 0.27, 0.40))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 1)
	t.width = 64
	t.height = 64
	return t


## Vorschau-Hintergrund an Settings.bg_dim angleichen (0 = Aus).
func _refresh_bg_preview() -> void:
	if _preview_bg == null:
		return
	var v := Settings.bg_dim
	_preview_bg.modulate = Color(v, v, v, 1.0)
	_preview_bg.visible = v > 0.001
	_preview_bg_label.text = tr("Map-Bild") + ": " + tr(_fmt_bg(v))


func _refresh_2d_preview() -> void:
	if _preview_2d != null and is_instance_valid(_preview_2d) and _preview_2d.has_method("refresh"):
		_preview_2d.call("refresh")


# ================================================================== Gruppen + Zeilen

## Gruppe = ruhige Karte: Titel (Satzschreibung) + "Zuruecksetzen", darunter Zeilen
## mit Haarlinien. Gibt die Zeilen-Box zurueck.
func _group(pg: VBoxContainer, title: String, resettable: bool = true) -> VBoxContainer:
	var card := PanelContainer.new()
	var cb := UiTheme.solid_box(COL_CARD, 12)
	cb.set_border_width_all(1)
	cb.border_color = Color(UiTheme.TEXT, 0.07)
	cb.content_margin_top = 4
	cb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", cb)
	pg.add_child(card)
	if _build_pg != "":
		_pages[_build_pg].cards.append(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 34)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 14)
	hm.add_theme_constant_override("margin_right", 8)
	hm.add_child(head)
	col.add_child(hm)
	var l := Label.new()
	l.text = title
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.heading_font(0))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(l)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.set_meta("title", title)
	col.add_child(rows)
	card.set_meta("rows", rows)
	if resettable:
		var rb := Button.new()
		rb.text = "Zurücksetzen"
		rb.flat = true
		rb.focus_mode = Control.FOCUS_NONE
		rb.tooltip_text = "Diese Gruppe auf Standard"
		rb.add_theme_font_size_override("font_size", 12)
		rb.add_theme_color_override("font_color", UiTheme.DIM)
		rb.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		rb.add_theme_color_override("font_pressed_color", UiTheme.ACCENT)
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 6
		e.content_margin_right = 6
		for st in ["normal", "hover", "pressed", "focus"]:
			rb.add_theme_stylebox_override(st, e)
		UiTheme._attach_sounds(rb)
		rb.pressed.connect(_reset_group.bind(rows))
		head.add_child(rb)
		rows.set_meta("reset_btn", rb)
	return rows


func _reset_group(rows: VBoxContainer) -> void:
	for r in rows.get_children():
		if r.has_meta("reset"):
			var f: Callable = r.get_meta("reset")
			if f.is_valid():
				f.call()
	_sync_page(_cur)
	_refresh_2d_preview()
	_refresh_bg_preview()


## Einheitliche Zeile (ROW_H): Beschriftung links, Bedienung in der rechten Spalte
## (CTRL_W). Schalter und Knoepfe sitzen rechtsbuendig, Regler/Auswahl fuellen sie.
func _row(rows: VBoxContainer, cap: String, ctrl: Control, tip: String = "",
		sync: Callable = Callable(), reset: Callable = Callable()) -> PanelContainer:
	var first := rows.get_child_count() == 0
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0, ROW_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	if not first:
		sb.border_width_top = 1
		sb.border_color = COL_SEP
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_entered.connect(func(): sb.bg_color = COL_ROW_HOVER)
	row.mouse_exited.connect(func(): sb.bg_color = Color(0, 0, 0, 0))
	rows.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)
	var l := Label.new()
	l.text = cap
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(120, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	var slot := HBoxContainer.new()
	slot.custom_minimum_size = Vector2(CTRL_W, 0)
	slot.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(slot)
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ctrl is CheckButton or (ctrl is Button and not ctrl is OptionButton) or ctrl is PanelContainer:
		if ctrl.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
			ctrl.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_child(ctrl)
	row.tooltip_text = tip
	row.set_meta("ctrl", ctrl)
	row.set_meta("cap", cap)
	if sync.is_valid():
		row.set_meta("sync", sync)
	if reset.is_valid():
		row.set_meta("reset", reset)
	_register(cap, row)
	return row


func _register(cap: String, row: Control) -> void:
	if _build_pg == "":
		return
	for e in _entries:
		if e.cap == cap and e.page == _build_pg:
			return
	_entries.append({"cap": cap, "page": _build_pg, "row": row})
	_pages[_build_pg].rows.append(row)


func _hint_label(rows: VBoxContainer, t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_bottom", 10)
	m.add_child(l)
	rows.add_child(m)
	return l


## Regler: getf(obj) liest den Wert aus Settings oder den Standardwerten, setf(v)
## setzt ihn (mit Nebenwirkungen), fmt(v) -> Text rechts.
func _slider(rows: VBoxContainer, cap: String, mn: float, mx: float, step: float,
		getf: Callable, setf: Callable, fmt: Callable, tip: String = "") -> PanelContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = getf.call(Settings)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(VALUE_W, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.add_theme_font_override("font", UiTheme.heading_font(0))
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", UiTheme.TEXT)
	val.text = str(fmt.call(sl.value))
	box.add_child(val)
	sl.value_changed.connect(func(v):
		setf.call(v)
		val.text = str(fmt.call(v))
		_refresh_2d_preview())
	var sync := func():
		sl.set_value_no_signal(getf.call(Settings))
		val.text = str(fmt.call(sl.value))
	var reset := func():
		setf.call(getf.call(_defaults))
		sync.call()
	var r := _row(rows, cap, box, tip, sync, reset)
	r.set_meta("ctrl", sl)
	r.set_meta("value", val)
	return r


func _switch(rows: VBoxContainer, cap: String, getf: Callable, setf: Callable,
		tip: String = "") -> PanelContainer:
	var cb := CheckButton.new()
	cb.button_pressed = getf.call(Settings)
	cb.focus_mode = Control.FOCUS_ALL
	cb.toggled.connect(func(on):
		setf.call(on)
		_refresh_2d_preview())
	var sync := func(): cb.set_pressed_no_signal(getf.call(Settings))
	var reset := func():
		setf.call(getf.call(_defaults))
		sync.call()
	return _row(rows, cap, cb, tip, sync, reset)


func _choice(rows: VBoxContainer, cap: String, items: Array, getf: Callable, setf: Callable,
		tip: String = "") -> PanelContainer:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(it)
	return _choice_ob(rows, cap, ob, getf, setf, tip)


## Auswahl mit fertigem OptionButton; Wert = Index (bzw. Item-ID bei IDs = Index).
func _choice_ob(rows: VBoxContainer, cap: String, ob: OptionButton, getf: Callable, setf: Callable,
		tip: String = "") -> PanelContainer:
	ob.custom_minimum_size = Vector2(0, CTRL_H)
	ob.clip_text = true
	ob.add_theme_font_size_override("font_size", 14)
	ob.select(int(getf.call(Settings)))
	ob.item_selected.connect(func(i):
		setf.call(i)
		_refresh_2d_preview())
	var sync := func(): ob.select(int(getf.call(Settings)))
	var reset := func():
		setf.call(int(getf.call(_defaults)))
		sync.call()
	return _row(rows, cap, ob, tip, sync, reset)


## Eigene 2D-Layout-Werte: Aendern schaltet "Skin-Werte nutzen" aus, damit sie wirken;
## Zuruecksetzen setzt nur den Wert (ohne den Schalter anzufassen).
func _own_slider(rows: VBoxContainer, cap: String, mn: float, mx: float, n: String, tip: String) -> void:
	var r := _slider(rows, cap, mn, mx, 1.0,
		func(s): return float(s.get(n)),
		func(v): _set_own_2d(n, v),
		func(v): return str(int(v)), tip)
	r.set_meta("reset", func(): Settings.set_2d_option(n, Settings.default_2d_option(n)))


func _own_choice(rows: VBoxContainer, cap: String, items: Array, n: String, tip: String) -> void:
	var r := _choice(rows, cap, items,
		func(s): return int(s.get(n)),
		func(i): _set_own_2d(n, i), tip)
	r.set_meta("reset", func(): Settings.set_2d_option(n, Settings.default_2d_option(n)))


func _own_switch(rows: VBoxContainer, cap: String, n: String, tip: String) -> void:
	var r := _switch(rows, cap,
		func(s): return bool(s.get(n)),
		func(on): _set_own_2d(n, on), tip)
	r.set_meta("reset", func(): Settings.set_2d_option(n, Settings.default_2d_option(n)))


func _set_own_2d(n: String, v: Variant) -> void:
	Settings.set_2d_option(n, v)
	if Settings.skin_values_2d:
		Settings.skin_values_2d = false
		if _skinvals_btn != null:
			_skinvals_btn.set_pressed_no_signal(false)
	_refresh_2d_preview()


## Skin-Bereich: Auswahl volle Breite, Knoepfe darunter, Status umbrechend.
## Die Kinder des SkinPickers wandern in dieses Layout; der Picker bleibt
## unsichtbar im Baum (Besitzer von Dialog und Logik).
func _embed_skin(rows: VBoxContainer, skin: Control) -> void:
	var opt: OptionButton = null
	var status: Label = null
	for c in skin.get_children():
		if c is OptionButton:
			opt = c
		elif c is Label:
			status = c
	if opt == null:
		rows.add_child(skin)
		return
	skin.remove_child(opt)
	opt.custom_minimum_size = Vector2(0, CTRL_H)
	opt.clip_text = true
	opt.add_theme_font_size_override("font_size", 14)
	_row(rows, "Aktiver Skin", opt, "Eigene Bilder für Noten und Tasten")
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 0)
	m.add_theme_constant_override("margin_bottom", 10)
	rows.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)
	skin.visible = false
	col.add_child(skin)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.alignment = BoxContainer.ALIGNMENT_END
	for c in skin.get_children():
		if c is Button or c is MenuButton:
			if c is MenuButton:
				# MenuButton ist standardmaessig flach: echter Knopf im selben Stil.
				var mb := c as MenuButton
				mb.flat = false
				mb.theme_type_variation = &"Button"
				mb.focus_mode = Control.FOCUS_ALL
				if String(mb.text) == "Aus osu!":
					mb.text = "Von osu! übernehmen"
			elif String(c.text) == "Importieren…":
				c.text = "Datei importieren…"
			skin.remove_child(c)
			c.custom_minimum_size.y = CTRL_H
			c.add_theme_font_size_override("font_size", 14)
			btns.add_child(c)
	col.add_child(btns)
	if status != null:
		skin.remove_child(status)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_color_override("font_color", UiTheme.DIM)
		status.add_theme_font_size_override("font_size", 12)
		col.add_child(status)


# ================================================================== Navigation

func _mode_pages() -> Array:
	var out := []
	for id in PAGE_ORDER:
		var modes: Array = PAGE_DEFS[id][2]
		if modes.has(_mode):
			out.append(id)
	return out


func _general_pages() -> Array:
	var out := []
	for id in PAGE_ORDER:
		if (PAGE_DEFS[id][2] as Array).is_empty():
			out.append(id)
	return out


func _set_mode(m: int) -> void:
	if m == MODE_3D or m == MODE_2D:
		Settings.playfield_2d = m == MODE_2D
		if _nc != null:
			_nc.show_mode(m == MODE_2D)
	var was_general := (PAGE_DEFS.get(_cur, ["", "", [MODE_3D]])[2] as Array).is_empty()
	_mode = m
	_update_mode_buttons()
	_rebuild_nav()
	if not was_general:
		_show_page(_mode_pages()[0])
	else:
		_highlight_nav()


func _update_mode_buttons() -> void:
	for i in _mode_btns.size():
		var b := _mode_btns[i]
		var on := i == _mode
		b.set_pressed_no_signal(on)
		var sb := UiTheme.solid_box(UiTheme.ACCENT if on else UiTheme.RAISED, 6)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		var hv: StyleBoxFlat = sb.duplicate()
		hv.bg_color = sb.bg_color.lightened(0.08)
		for st in ["normal", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("hover", hv)
		var fc := UiTheme.ON_ACCENT if on else UiTheme.DIM
		for c in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, fc)
		b.add_theme_color_override("font_hover_color", UiTheme.ON_ACCENT if on else UiTheme.TEXT)


func _rebuild_nav() -> void:
	for c in _nav.get_children():
		_nav.remove_child(c)
		c.queue_free()
	_nav_btns.clear()
	for id in _mode_pages():
		_nav.add_child(_nav_button(id))
	_nav.add_child(_vgap(14))
	_nav.add_child(_side_label("Allgemein"))
	_nav.add_child(_vgap(6))
	for id in _general_pages():
		_nav.add_child(_nav_button(id))
	_highlight_nav()


func _nav_button(id: String) -> Button:
	var b := Button.new()
	b.text = PAGE_DEFS[id][0]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(_show_page.bind(id))
	UiTheme._attach_sounds(b)
	# Rechts die Zahl der Einstellungen (tabellarische Ziffern, gedimmt).
	var n := Label.new()
	n.text = str(_pages[id].rows.size()) if id != "notes" else ""
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_override("font", UiTheme.heading_font(0))
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", Color(UiTheme.DIM, 0.7))
	n.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	n.offset_left = -30
	n.offset_right = -10
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(n)
	_nav_btns[id] = b
	return b


func _highlight_nav() -> void:
	for id in _nav_btns:
		var b: Button = _nav_btns[id]
		var on: bool = id == _cur
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.RAISED if on else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(UiTheme.R_SMALL + 1)
		sb.content_margin_left = 12
		sb.content_margin_right = 34
		if on:
			sb.border_width_left = 2
			sb.border_color = UiTheme.ACCENT
		var hv: StyleBoxFlat = sb.duplicate()
		if not on:
			hv.bg_color = Color(UiTheme.TEXT, 0.05)
		for st in ["normal", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.DIM)
		b.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)


func _show_page(id: String) -> void:
	if not _pages.has(id):
		return
	_cur = id
	for k in _pages:
		_pages[k].vb.visible = k == id
	var d: Array = PAGE_DEFS[id]
	_title.text = d[0]
	var sub := tr(d[1])
	if not (d[2] as Array).is_empty() and (d[2] as Array).size() == 1:
		sub = tr("Gilt für %s") % MODE_NAMES[d[2][0]]
	_subtitle.text = sub
	var pv: String = d[3]
	(_pv_col.get_meta("wrap") as Control).visible = pv != ""
	_pv_2d.visible = pv == "2d"
	_pv_world.visible = pv == "world"
	_pv_orbit.visible = pv == "orbit"
	_arrange(id)
	_scroll.scroll_vertical = 0
	_sync_page(id)
	_refresh_labels()
	_highlight_nav()
	_update_fades.call_deferred()


## Werte der Seite neu aus Settings lesen (dieselbe Einstellung steht evtl. auf mehreren Seiten).
func _sync_page(id: String) -> void:
	if not _pages.has(id):
		return
	for r in _pages[id].rows:
		if is_instance_valid(r) and r.has_meta("sync"):
			(r.get_meta("sync") as Callable).call()


# ================================================================== Suche

func _on_search(q: String) -> void:
	for c in _results.get_children():
		_results.remove_child(c)
		c.queue_free()
	q = q.strip_edges().to_lower()
	_nav.visible = q == ""
	_results.visible = q != ""
	if q == "":
		return
	var hits := _search_hits(q)
	if hits.is_empty():
		var none := Label.new()
		none.text = "Keine Treffer"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", UiTheme.DIM)
		_results.add_child(none)
		return
	for i in mini(hits.size(), 12):
		var e: Dictionary = hits[i]
		var b := Button.new()
		b.text = tr(e.cap)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.clip_text = true
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", 14)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.RAISED if i == 0 else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(UiTheme.R_SMALL + 1)
		sb.content_margin_left = 12
		sb.content_margin_bottom = 15
		var hv: StyleBoxFlat = sb.duplicate()
		hv.bg_color = UiTheme.RAISED
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		var where := Label.new()
		where.text = _where(e.page)
		where.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		where.add_theme_font_size_override("font_size", 11)
		where.add_theme_color_override("font_color", UiTheme.DIM)
		where.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		where.offset_left = 12
		where.offset_top = -18
		where.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(where)
		b.pressed.connect(_jump.bind(e))
		UiTheme._attach_sounds(b)
		_results.add_child(b)


func _where(page: String) -> String:
	var d: Array = PAGE_DEFS[page]
	var modes: Array = d[2]
	if modes.size() == 1:
		if tr(d[0]) == MODE_NAMES[modes[0]]:
			return MODE_NAMES[modes[0]]
		return MODE_NAMES[modes[0]] + " · " + tr(d[0])
	return tr(d[0])


## Treffer: Beschriftung oder Gruppe enthaelt die Suche; aktueller Modus zuerst.
func _search_hits(q: String) -> Array:
	var hits := []
	var later := []
	for e in _entries:
		var cap := tr(e.cap).to_lower()
		var grp := ""
		var p = e.row.get_parent()
		if p != null and p.has_meta("title"):
			grp = tr(String(p.get_meta("title"))).to_lower()
		if not (cap.contains(q) or grp.contains(q) or String(e.cap).to_lower().contains(q)):
			continue
		var modes: Array = PAGE_DEFS[e.page][2]
		if modes.is_empty() or modes.has(_mode):
			hits.append(e)
		else:
			later.append(e)
	return hits + later


func _search_pick(i: int) -> void:
	var hits := _search_hits(_search.text.strip_edges().to_lower())
	if i < hits.size():
		_jump(hits[i])


## Zur Einstellung springen: Modus wechseln falls noetig, Seite zeigen, hinscrollen, kurz markieren.
func _jump(e: Dictionary) -> void:
	var modes: Array = PAGE_DEFS[e.page][2]
	if not modes.is_empty() and not modes.has(_mode):
		_set_mode(modes[0])
	_search.text = ""
	_on_search("")
	_show_page(e.page)
	var row: Control = e.row
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	var y := row.get_global_rect().position.y - _scroll.get_global_rect().position.y + _scroll.scroll_vertical
	_scroll.scroll_vertical = maxi(0, int(y - _scroll.size.y * 0.3))
	var sb := row.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(UiTheme.ACCENT, 0.16)
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_property(sb, "bg_color", Color(UiTheme.ACCENT, 0.0), 0.6)
	var c: Control = row.get_meta("ctrl", null)
	if c != null and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()


# ================================================================== Tasten

func _refresh_labels() -> void:
	for i in _lane_btns.size():
		_lane_btns[i].text = UiTheme.key_short(Settings.key_lanes[i])
		if _capturing == 3 + i:
			_lane_btns[i].text = "…"
	for k in _orbit_btns.size():
		var r := k % 2
		var code := Settings.orbit_key_outer if r == 1 else Settings.orbit_key_inner
		_orbit_btns[k].text = "…" if _capturing == CAP_ORBIT + r else UiTheme.key_short(code)
		_orbit_btns[k].tooltip_text = tr("Maus rechts") if r == 1 else tr("Maus links")


func _open_wizard() -> void:
	var w := OffsetWizard.new()
	w.finished.connect(func(_applied: bool):
		_sync_page(_cur)
		_refresh_labels())
	add_child(w)


func _start_capture(which: int) -> void:
	_capturing = which
	_refresh_labels()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _capturing >= CAP_ORBIT:
		if event.keycode != KEY_ESCAPE:
			if _capturing == CAP_ORBIT:
				Settings.orbit_key_inner = event.keycode
			else:
				Settings.orbit_key_outer = event.keycode
		_capturing = 0
		_refresh_labels()
		get_viewport().set_input_as_handled()
	elif _capturing >= 3:
		if event.keycode != KEY_ESCAPE:
			Settings.key_lanes[_capturing - 3] = event.keycode
		_capturing = 0
		_refresh_labels()
		_refresh_2d_preview()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if _search.has_focus() and _search.text != "":
			_search.text = ""
			_on_search("")
		else:
			Sfx.ui_back()
			_close(false)
		get_viewport().set_input_as_handled()


func _close(with_sound: bool = true) -> void:
	if with_sound:
		Sfx.ui_close()
	Settings.save()
	Settings.apply()
	if _world_preview != null:
		_world_preview.release()
	closed.emit()
	queue_free()


# ================================================================== Format

## Hintergrund-Deckkraft: 0 -> "Aus", sonst "30 %".
static func _fmt_bg(v: float) -> String:
	return TranslationServer.translate("Aus") if v <= 0.001 else _fmt_pct0(v)


## 0.85 -> "85 %".
static func _fmt_pct0(v: float) -> String:
	return UiTheme.fmt_num(v * 100.0, 0) + (" %" if UiTheme.is_german() else "%")


# ================================================================== Harness

## --shot-settings (SETTINGS_SHOT_DIR): jede Seite je Modus, oben und unten gescrollt,
## de und en, 1280x720 und 1920x1080. Speichert nichts. --shot-orbit: nur Orbit-Seite.
func _shot_pages() -> void:
	var dir := OS.get_environment("SETTINGS_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_shot_translations()
	await get_tree().create_timer(1.2).timeout
	if OS.get_cmdline_args().has("--shot-orbit"):
		# Messung: Bilder/s auf einer Seite ohne Vorschau, dann auf der Orbit-Seite.
		_set_mode(MODE_ORBIT)
		_show_page("audio")
		await get_tree().create_timer(1.0).timeout
		print("FPS audio ", Engine.get_frames_per_second())
		_show_page("orbit")
		await get_tree().create_timer(1.5).timeout
		print("FPS orbit ", Engine.get_frames_per_second())
		for lang in ["de", "en"]:
			TranslationServer.set_locale(lang)
			_rebuild()
			_set_mode(MODE_ORBIT)
			_show_page("orbit")
			if lang == "en":
				# Live: andere Einstellungen muessen sofort in der Vorschau wirken.
				Settings.orbit_guides = false
				Settings.orbit_background = Settings.ORBIT_BG_MAP
				Settings.scroll_speed = 20
			await get_tree().create_timer(2.2).timeout
			await _shot_save(dir, "settings_orbit_%s.png" % lang)
		get_tree().quit(0)
		return
	var sizes := [Vector2i(1280, 720), Vector2i(1920, 1080)]
	for sz in sizes:
		get_window().size = sz
		await get_tree().create_timer(0.3).timeout
		var real := Vector2i(get_viewport().get_visible_rect().size)
		for lang in ["de", "en"]:
			TranslationServer.set_locale(lang)
			_rebuild()
			await get_tree().create_timer(0.5).timeout
			var tag := "%dx%d_%s" % [real.x, real.y, lang]
			for m in 3:
				_set_mode(m)
				for id in _mode_pages():
					await _shot_page(dir, tag, MODE_NAMES[m].replace(" ", "").to_lower(), id)
			for id in _general_pages():
				await _shot_page(dir, tag, "all", id)
			# Suche mit Treffern.
			_search.text = "hinter" if lang == "de" else "back"
			_on_search(_search.text)
			await get_tree().create_timer(0.3).timeout
			await _shot_save(dir, "settings_%s_search.png" % tag)
			_search.text = ""
			_on_search("")
	get_tree().quit(0)


func _shot_page(dir: String, tag: String, mode: String, id: String) -> void:
	_show_page(id)
	await get_tree().create_timer(0.45 if id == "field3d" or id == "orbit" else 0.25).timeout
	await _shot_save(dir, "settings_%s_%s_%s_top.png" % [tag, mode, id])
	var sb := _scroll.get_v_scroll_bar()
	if sb.max_value - sb.page > 4.0:
		_scroll.scroll_vertical = int(sb.max_value)
		await get_tree().create_timer(0.15).timeout
		await _shot_save(dir, "settings_%s_%s_%s_bottom.png" % [tag, mode, id])


func _shot_save(dir: String, file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


## Harness: neue Texte aus translations/settings2.csv laden (die Registrierung im
## Projekt fehlt evtl. noch), damit die en-Bilder echt sind.
func _shot_translations() -> void:
	var f := FileAccess.open("res://translations/settings2.csv", FileAccess.READ)
	if f == null:
		return
	var t := Translation.new()
	t.locale = "en"
	f.get_csv_line()
	while not f.eof_reached():
		var l := f.get_csv_line()
		if l.size() >= 3 and l[0] != "":
			t.add_message(l[0], l[2])
	TranslationServer.add_translation(t)


## Alles neu aufbauen (Harness: Sprachwechsel ohne Szenenwechsel).
func _rebuild() -> void:
	if _world_preview != null:
		_world_preview.release()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_pages.clear()
	_entries.clear()
	_nav_btns.clear()
	_mode_btns.clear()
	_lane_btns.clear()
	_orbit_btns.clear()
	_cover_rows.clear()
	_cur = ""
	_build()


## Standbild der Orbit-Einstellungen (wenn es keine Live-Vorschau gibt): drei
## Ziele (A, B, Akzent) mit Satellit, Pips, Verbindungslinie und Cursor. Folgt
## Zielgroesse, Cursor-Groesse, Tasten in Zielen und Vorlauf (Pips).
class OrbitStill extends Control:
	const SIZE_PX := Vector2(384, 216)
	var _sig := ""

	func _ready() -> void:
		custom_minimum_size = SIZE_PX
		size = SIZE_PX
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if not is_visible_in_tree():
			return
		var sig := "%d|%d|%d|%d|%d|%d" % [Settings.orbit_target_size, Settings.orbit_cursor_size,
			Settings.orbit_key_hint, Settings.orbit_laps, Settings.orbit_key_inner, Settings.orbit_key_outer]
		if sig != _sig:
			_sig = sig
			queue_redraw()

	func _draw() -> void:
		var sz := SIZE_PX
		draw_rect(Rect2(Vector2.ZERO, sz), Color(OrbitView.PLATE_COL, 1.0))
		var fh := sz.y * 0.8
		var field := Rect2((sz.x - fh * 4.0 / 3.0) * 0.5, sz.y * 0.1, fh * 4.0 / 3.0, fh)
		draw_rect(field, Color(1, 1, 1, 0.025))
		var r := fh * 0.065 * float(Settings.orbit_target_size) / 100.0
		var p_next := field.position + field.size * Vector2(0.28, 0.58)
		var p_b := field.position + field.size * Vector2(0.60, 0.32)
		var p_acc := field.position + field.size * Vector2(0.82, 0.68)
		draw_line(p_next, p_b, Color(1, 1, 1, 0.14), 1.0, true)
		draw_line(p_b, p_acc, Color(1, 1, 1, 0.07), 1.0, true)
		var laps := Settings.orbit_laps if Settings.orbit_laps >= 1 else 2
		# Spaeter kommende Ziele blass (55 %), das naechste voll.
		_target(p_acc, r, 2, 0.55, laps, 0.70, false)
		_target(p_b, r, 1, 0.55, laps, 0.35, false)
		_target(p_next, r, 0, 1.0, 1, 0.08, Settings.orbit_key_hint != 2)
		var c := p_next + Vector2(r * 0.35, r * 0.25)
		var cr := 5.0 * float(Settings.orbit_cursor_size) / 100.0
		draw_circle(c, cr + 1.5, Color(0, 0, 0, 0.6), true, -1.0, true)
		draw_circle(c, cr, Color(1, 1, 1, 0.95), true, -1.0, true)

	func _target(p: Vector2, r: float, key: int, a: float, pips: int, frac: float, label: bool) -> void:
		var ca := OrbitView.INNER_COL
		var cb := OrbitView.OUTER_COL
		var orbit := r * 1.6
		draw_arc(p, orbit, 0.0, TAU, 48, Color(1, 1, 1, 0.16 * a), 1.0, true)
		draw_line(p + Vector2(0, -orbit - 4.0), p + Vector2(0, -orbit + 4.0), Color(1, 1, 1, 0.7 * a), 1.5)
		if key == 1:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(cb, a)
			sb.set_corner_radius_all(int(r * 0.34 * 1.72))
			sb.border_color = Color(cb.lightened(0.45), a)
			sb.set_border_width_all(2)
			sb.anti_aliasing = true
			draw_style_box(sb, Rect2(p - Vector2(r, r) * 0.86, Vector2(r, r) * 1.72))
		elif key == 2:
			draw_circle(p, r, Color(ca, a), true, -1.0, true)
			var half := PackedVector2Array()
			for i in 25:
				half.append(p + Vector2.from_angle(-PI * 0.5 + PI * float(i) / 24.0) * r)
			draw_colored_polygon(half, Color(cb, a))
			draw_arc(p, r, 0.0, TAU, 48, Color(1, 1, 1, a), 2.5, true)
		else:
			draw_circle(p, r, Color(ca, a), true, -1.0, true)
			draw_arc(p, r, 0.0, TAU, 48, Color(ca.lightened(0.45), a), 2.0, true)
		# Satellit: 0 = oben, laeuft im Uhrzeigersinn auf die Marke zu.
		var ang := -PI * 0.5 + TAU * (1.0 - frac)
		draw_circle(p + Vector2.from_angle(ang) * orbit, 3.0, Color(1, 1, 1, a), true, -1.0, true)
		for i in pips:
			var x := (float(i) - float(pips - 1) * 0.5) * 7.0
			draw_circle(p + Vector2(x, orbit + 7.0), 2.0, Color(1, 1, 1, 0.75 * a), true, -1.0, true)
		if label:
			var f := UiTheme.heading_font(0)
			var t := UiTheme.key_short(Settings.orbit_key_outer if key == 1 else Settings.orbit_key_inner)
			var fs := maxi(int(r * 0.8), 8)
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, p + Vector2(-w * 0.5, float(fs) * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.04, 0.05, 0.08, 0.9))
