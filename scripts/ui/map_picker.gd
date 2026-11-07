class_name MapPicker
extends Control

## Map-Picker im Stil des Song-Browsers (Multiplayer-Raum): Suche ueber
## Titel/Artist/Mapper/Tags, Sortierung, Sterne-Filter, Liste mit Cover und
## Sterne-Pillen, rechts die 4K-Diffs des gewaehlten Sets mit dem EIGENEN
## besten Score (Rang, Punkte, Genauigkeit, Mods). Tab "Online" oeffnet den
## Online-Browser des Song-Browsers; fertige Downloads erscheinen sofort.
##
## Fluessig bei 1000+ Maps: die Liste ist virtuell (fester Pool an Zeilen,
## nur beim Scrollen/Filtern neu belegt), Cover laden im WorkerThreadPool,
## BPM + Tags kommen aus einem Hintergrund-Thread mit Disk-Cache.
## Ruhezustand: kein _process, keine Allokationen pro Frame.

## Diff gewaehlt (Index in ms.diffs).
signal picked(ms: MapSet, diff: int)
## Set angewaehlt (fuer die Hoervorschau).
signal set_selected(ms: MapSet)
signal closed
signal preview_stream(stream: AudioStream)
signal preview_stop

const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const COL_CARD := Color(0.08, 0.08, 0.11, 0.94)
const COL_CARD_SEL := Color(0.13, 0.13, 0.18, 0.98)
const PLAYED_COL := Color(0.55, 1.0, 0.72)
const ROW_H := 84.0
const ROW_GAP := 8.0
const COVER_W := 132.0
const MAX_PILLS := 7
const DETAIL_W := 420.0
const META_CACHE := "user://map_picker_meta.cfg"
const META_VER := 1
const COVER_FALLBACK_USEC := 4000

const GRADE_COLOR := {
	"S": Color(1.0, 0.85, 0.25), "A": Color(0.4, 1.0, 0.5),
	"B": Color(0.35, 0.75, 1.0), "C": Color(0.9, 0.6, 1.0),
	"D": Color(1.0, 0.4, 0.4),
}
## Rang-Reihenfolge (bester zuerst) fuer das Set-Badge.
const GRADE_ORDER := ["SS", "S", "A", "B", "C", "D"]

## Wie im Song-Browser: [Text, lo, hi).
const STAR_FILTERS := [
	["Alle", 0.0, 999.0],
	["<2★", 0.0, 2.0],
	["2–4★", 2.0, 4.0],
	["4–6★", 4.0, 6.0],
	["6★+", 6.0, 999.0],
]

enum Sort { TITLE, ARTIST, STARS, BPM, LENGTH, RECENT }
const SORT_NAMES := ["Titel", "Artist", "Sterne", "BPM", "Länge", "Zuletzt gespielt"]
const SORT_KEYS := ["title_k", "artist_k", "stars", "bpm", "length", "last"]
## Standardrichtung je Sortierung (true = groesster Wert zuerst).
const SORT_DESC := [false, false, true, true, true, true]

var library: MapLibrary
## Darf waehlen (Kronentraeger). Sonst nur ansehen.
var can_pick := true
## Turnier: nur Diffs in diesem Sternbereich (x = von, y = bis, y < 0 = aus).
var star_range := Vector2(0.0, -1.0)
## (file: String, version: String) -> bool: im Raum schon gespielt.
var played_fn: Callable

var _entries: Array = []
var _shown: Array = []
var _scores: Dictionary = {}
var _extra: Dictionary = {}
var _query := ""
var _star_filter := 0
var _sort: int = Sort.TITLE
var _desc := false
var _sel := -1
var _sel_diff := 0

var _search: LineEdit
var _sort_btn: OptionButton
var _dir_btn: Button
var _count_label: Label
var _star_chips: Array[Button] = []
var _scroll: ScrollContainer
var _content: Control
var _empty_label: Label
var _pool: Array = []
var _detail: VBoxContainer
var _detail_cover: TextureRect
var _detail_title: Label
var _detail_sub: Label
var _detail_meta: Label
var _diff_box: VBoxContainer
var _diff_btns: Array[Button] = []
var _hint: Label

var _box_card: StyleBoxFlat
var _box_hover: StyleBoxFlat
var _box_sel: StyleBoxFlat
var _diff_box_n: StyleBoxFlat
var _diff_box_h: StyleBoxFlat
var _diff_box_sel: StyleBoxFlat

# Cover: file -> Texture2D; Laden im WorkerThreadPool.
var _covers: Dictionary = {}
var _cover_pending: Dictionary = {}
var _cover_tasks: Array[int] = []
var _cover_done: Array = []
var _cover_fallback: Array = []
var _cover_mutex := Mutex.new()

# BPM/Tags-Thread.
var _meta_thread: Thread
var _meta_cancel := false

var _online: OnlineBrowser = null


func _init(lib: MapLibrary) -> void:
	library = lib
	name = "MapPicker"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_styles()
	_build()
	set_process(false)
	_extra = load_extra_cache()


func _exit_tree() -> void:
	_meta_cancel = true
	if _meta_thread != null and _meta_thread.is_started():
		_meta_thread.wait_to_finish()
	for id in _cover_tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_cover_tasks.clear()


func is_open() -> bool:
	return visible


## Oeffnen: Scores neu lesen, Eintraege bauen, Suche fokussieren.
func open() -> void:
	visible = true
	reload()
	_search.grab_focus.call_deferred()
	_start_meta_scan()


func close() -> void:
	if not visible:
		return
	if online_open():
		_online.close()
	visible = false
	closed.emit()


func online_open() -> bool:
	return _online != null and _online.visible


## Bibliothek/Scores neu einlesen (nach Download, nach Runde).
func reload() -> void:
	var keep: MapSet = selected_set()
	_scores = load_scores()
	_entries = build_entries(library.mapsets, _scores, _extra)
	_refilter(keep)


func selected_set() -> MapSet:
	if _sel < 0 or _sel >= _shown.size():
		return null
	return _shown[_sel].ms


func shown_count() -> int:
	return _shown.size()


func set_query(q: String) -> void:
	_search.text = q
	_on_query(q)


## Set per osz-Pfad anwaehlen (z.B. nach einem Download). true = gefunden.
func select_path(osz_path: String) -> bool:
	for i in _shown.size():
		if (_shown[i].ms as MapSet).osz_path == osz_path:
			_select(i, -1)
			_scroll_to(i)
			return true
	return false


## Erstes sichtbares Set mit eigenem Score anwaehlen (Screenshot/Test).
func select_first_scored() -> bool:
	for i in _shown.size():
		for d in _shown[i].diffs:
			if not (d.best as Dictionary).is_empty():
				_select(i, _shown[i].diffs.find(d))
				_scroll_to(i)
				return true
	return false


# ---------------------------------------------------------------------------
# Daten (statisch, headless testbar)
# ---------------------------------------------------------------------------

## Bestwerte + zuletzt gespielt aus scores.cfg, einmal gelesen.
## { best: {"file|version": entry}, last: {"file|version": ISO-Datum} }
static func load_scores(path: String = ScoreStore.PATH) -> Dictionary:
	var out := { "best": {}, "last": {} }
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	var best: Dictionary = out.best
	var last: Dictionary = out.last
	if cfg.has_section("scores"):
		for k in cfg.get_section_keys("scores"):
			var v = cfg.get_value("scores", k, {})
			if v is Dictionary and not v.is_empty():
				best[k] = v
				last[k] = str(v.get("date", ""))
	if cfg.has_section("history"):
		for k in cfg.get_section_keys("history"):
			var h = cfg.get_value("history", k, [])
			if h is Array and not h.is_empty() and h[-1] is Dictionary:
				var d := str(h[-1].get("date", ""))
				if d > str(last.get(k, "")):
					last[k] = d
	return out


## Ein Eintrag pro Set mit mindestens einer 4K-Mania-Diff.
## extra: { osz-Dateiname: {bpm, tags} } (aus dem Meta-Thread).
static func build_entries(mapsets: Array, scores: Dictionary, extra: Dictionary) -> Array:
	var out: Array = []
	var best: Dictionary = scores.get("best", {})
	var last: Dictionary = scores.get("last", {})
	for ms in mapsets:
		var file: String = (ms as MapSet).osz_path.get_file()
		var diffs: Array = []
		var max_st := -1.0
		var last_d := ""
		var grade := ""
		for i in ms.difficulty_count():
			var m: Dictionary = ms.meta_at(i)
			if int(m.get("mode", 0)) != 3:
				continue
			var ver: String = ms.version_name_at(i)
			var key := "%s|%s" % [file, ver]
			var b: Dictionary = best.get(key, {})
			var st: float = ms.stars_at(i)
			diffs.append({ "idx": i, "version": ver, "stars": st, "best": b })
			max_st = maxf(max_st, st)
			var ld := str(last.get(key, ""))
			if ld > last_d:
				last_d = ld
			grade = better_grade(grade, str(b.get("grade", "")))
		if diffs.is_empty():
			continue
		var ex: Dictionary = extra.get(file, {})
		out.append({
			"ms": ms, "file": file, "diffs": diffs,
			"hay": "%s %s %s %s" % [ms.artist.to_lower(), ms.title.to_lower(),
				ms.creator.to_lower(), str(ex.get("tags", "")).to_lower()],
			"title_k": ms.title.to_lower(), "artist_k": ms.artist.to_lower(),
			"stars": max_st, "bpm": float(ex.get("bpm", 0.0)),
			"length": ms.length_ms(), "last": last_d, "grade": grade,
		})
	return out


## Besserer von zwei Raengen ("" = keiner).
static func better_grade(a: String, b: String) -> String:
	if b == "" or not GRADE_ORDER.has(b):
		return a
	if a == "" or not GRADE_ORDER.has(a):
		return b
	return a if GRADE_ORDER.find(a) <= GRADE_ORDER.find(b) else b


## Suche (alle Woerter muessen vorkommen) + Sterne-Filter (irgendeine Diff
## im Bereich). Reihenfolge der Eingabe bleibt erhalten.
static func filter_entries(entries: Array, query: String, star_idx: int) -> Array:
	var words := query.strip_edges().to_lower().split(" ", false)
	var lo: float = STAR_FILTERS[star_idx][1]
	var hi: float = STAR_FILTERS[star_idx][2]
	var out: Array = []
	for e in entries:
		var hay: String = e.hay
		var ok := true
		for w in words:
			if not hay.contains(w):
				ok = false
				break
		if not ok:
			continue
		if star_idx != 0:
			var in_range := false
			for d in e.diffs:
				var st: float = d.stars
				if st >= lo and st < hi:
					in_range = true
					break
			if not in_range:
				continue
		out.append(e)
	return out


## Sortiert in place. Gleichstand: Titel, dann Dateiname (stabil).
static func sort_entries(arr: Array, mode: int, desc: bool) -> void:
	var k: String = SORT_KEYS[mode]
	arr.sort_custom(func(a, b):
		var va = a[k]
		var vb = b[k]
		if va == vb:
			if a.title_k == b.title_k:
				return a.file < b.file
			return a.title_k < b.title_k
		return va > vb if desc else va < vb)


## Mods-Text eines Bestwerts ("" = ohne Mods). Liest "mods" als Liste oder
## Dictionary; Unranked-Scores (AR-Override) bekommen "UR".
static func mods_badge(best: Dictionary) -> String:
	var parts: Array[String] = []
	var m = best.get("mods", [])
	if m is Array:
		for x in m:
			parts.append(str(x))
	elif m is Dictionary:
		for x in m:
			if bool(m[x]):
				parts.append(str(x))
	if bool(best.get("unranked", false)):
		parts.append("UR")
	return " ".join(parts)


## BPM (dominant = am laengsten gueltige rote Linie) + Tags aus .osu-Text.
static func parse_extra(text: String, duration_ms: float = 0.0) -> Dictionary:
	var cut := text.find("[HitObjects]")
	if cut >= 0:
		text = text.substr(0, cut)
	var tags := ""
	var reds: Array = []
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			section = line
			continue
		if line == "":
			continue
		if section == "[Metadata]":
			if line.begins_with("Tags:"):
				tags = line.substr(5).strip_edges()
		elif section == "[TimingPoints]":
			var p := line.split(",")
			if p.size() < 2:
				continue
			var bl := float(p[1])
			var red := p.size() < 7 or p[6].strip_edges() == "1"
			if red and bl > 0.0:
				reds.append([float(p[0]), bl])
	var bpm := 0.0
	var best_len := -1.0
	var end_t := maxf(duration_ms, 0.0)
	for i in reds.size():
		var t0: float = reds[i][0]
		var t1: float = reds[i + 1][0] if i + 1 < reds.size() else maxf(end_t, t0 + 1.0)
		var seg := t1 - t0
		if seg > best_len:
			best_len = seg
			bpm = 60000.0 / float(reds[i][1])
	return { "bpm": snappedf(bpm, 0.1), "tags": tags }


static func load_extra_cache() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(META_CACHE) != OK or int(cfg.get_value("info", "ver", 0)) != META_VER:
		return {}
	var out: Dictionary = {}
	if cfg.has_section("m"):
		for k in cfg.get_section_keys("m"):
			var v = cfg.get_value("m", k, {})
			if v is Dictionary:
				out[k] = v
	return out


# ---------------------------------------------------------------------------
# BPM/Tags im Hintergrund (einmal je Set, danach Disk-Cache)
# ---------------------------------------------------------------------------

func _start_meta_scan() -> void:
	if _meta_thread != null:
		if _meta_thread.is_alive():
			return
		_meta_thread.wait_to_finish()
		_meta_thread = null
	var jobs: Array = []
	for e in _entries:
		if _extra.has(e.file):
			continue
		var ms: MapSet = e.ms
		var di: int = e.diffs[0].idx
		jobs.append([e.file, ms.osz_path, ms.osu_filename_at(di), ms.length_ms()])
	if jobs.is_empty():
		return
	_meta_cancel = false
	_meta_thread = Thread.new()
	_meta_thread.start(_meta_worker.bind(jobs))


func _meta_worker(jobs: Array) -> void:
	var res: Dictionary = {}
	for j in jobs:
		if _meta_cancel:
			return
		var bytes := OszImporter.read_file_bytes(j[1], j[2])
		res[j[0]] = parse_extra(bytes.get_string_from_utf8(), j[3]) if not bytes.is_empty() \
				else { "bpm": 0.0, "tags": "" }
	_meta_done.call_deferred(res)


func _meta_done(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	var cfg := ConfigFile.new()
	cfg.load(META_CACHE)
	cfg.set_value("info", "ver", META_VER)
	for k in res:
		_extra[k] = res[k]
		cfg.set_value("m", k, res[k])
	cfg.save(META_CACHE)
	# Eintraege nur ergaenzen (kein Neuaufbau): BPM + Tags.
	for e in _entries:
		var ex: Dictionary = res.get(e.file, {})
		if ex.is_empty():
			continue
		e.bpm = float(ex.get("bpm", 0.0))
		e.hay = "%s %s" % [e.hay, str(ex.get("tags", "")).to_lower()]
	if visible:
		_refilter(selected_set())


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _init_styles() -> void:
	_box_card = _card_box(COL_CARD, Color(1, 1, 1, 0.07), 1)
	_box_hover = _card_box(COL_CARD_SEL, Color(1, 1, 1, 0.24), 1)
	_box_sel = _card_box(COL_CARD_SEL, ACCENT, 2)
	_diff_box_n = _card_box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.10), 1)
	_diff_box_h = _card_box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.26), 1)
	_diff_box_sel = _card_box(Color(ACCENT, 0.14), ACCENT, 2)


func _card_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.anti_aliasing = true
	sb.set_content_margin_all(6)
	return sb


func _toggle_box(active: bool, radius: int, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if active:
		sb.bg_color = Color(ACCENT, 0.24 if hover else 0.16)
		sb.border_color = Color(ACCENT, 0.60)
	else:
		sb.bg_color = Color(1, 1, 1, 0.09 if hover else 0.04)
		sb.border_color = Color(1, 1, 1, 0.22 if hover else 0.12)
	return sb


func _style_toggle(b: Button, active: bool) -> void:
	var n := _toggle_box(active, 14)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _toggle_box(active, 14, true))
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := ACCENT if active else DIM
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_hover_color", ACCENT if active else TEXT)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	var backdrop := UiTheme.modal_backdrop(self)
	backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var panel := PanelContainer.new()
	var psb := UiTheme.glass_box(18, 0.94)
	psb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", psb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	# Kopf: Titel, Anzahl, Online-Tab, Schliessen.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	var title := _label("MAP WÄHLEN", 22, TEXT)
	title.add_theme_font_override("font", UiTheme.heading_font(3))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_count_label = _label("", 13, DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count_label)
	var online := Button.new()
	online.text = "Online-Maps"
	online.tooltip_text = "Maps online suchen und laden — fertige Downloads werden direkt gewählt"
	online.focus_mode = Control.FOCUS_NONE
	online.custom_minimum_size = Vector2(130, 40)
	online.add_theme_font_size_override("font_size", 15)
	UiTheme.style_button(online, true)
	online.pressed.connect(open_online)
	head.add_child(online)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	UiTheme.style_ghost_button(x, 10)
	x.pressed.connect(close)
	head.add_child(x)

	# Suche + Sortierung.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	_search = LineEdit.new()
	_search.placeholder_text = "Suchen: Titel, Artist, Mapper, Tags"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 40)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 15)
	_search.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	var sfocus := _toggle_box(false, 10, true)
	sfocus.border_color = Color(ACCENT, 0.55)
	_search.add_theme_stylebox_override("focus", sfocus)
	_search.text_changed.connect(_on_query)
	bar.add_child(_search)
	_sort_btn = OptionButton.new()
	for i in SORT_NAMES.size():
		_sort_btn.add_item(SORT_NAMES[i], i)
	_sort_btn.tooltip_text = "Sortierung"
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.custom_minimum_size = Vector2(190, 40)
	_sort_btn.add_theme_font_size_override("font_size", 14)
	_sort_btn.add_theme_stylebox_override("normal", _toggle_box(false, 10))
	_sort_btn.add_theme_stylebox_override("hover", _toggle_box(false, 10, true))
	_sort_btn.add_theme_stylebox_override("pressed", _toggle_box(false, 10, true))
	_sort_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_sort_btn.add_theme_color_override("font_color", TEXT)
	_sort_btn.item_selected.connect(func(i: int): set_sort(i, SORT_DESC[i]))
	bar.add_child(_sort_btn)
	_dir_btn = Button.new()
	_dir_btn.focus_mode = Control.FOCUS_NONE
	_dir_btn.custom_minimum_size = Vector2(44, 40)
	_dir_btn.add_theme_font_size_override("font_size", 16)
	_dir_btn.tooltip_text = "Richtung umkehren"
	_style_toggle(_dir_btn, false)
	_dir_btn.pressed.connect(func(): set_sort(_sort, not _desc))
	bar.add_child(_dir_btn)

	# Sterne-Filter.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	root.add_child(chips)
	for fi in STAR_FILTERS.size():
		var chip := Button.new()
		chip.text = STAR_FILTERS[fi][0]
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0, 32)
		chip.add_theme_font_size_override("font_size", 13)
		chip.pressed.connect(func(): set_star_filter(fi))
		chips.add_child(chip)
		_star_chips.append(chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_child(gap)
	_hint = _label("↑↓ wählen  ·  Enter übernehmen  ·  Esc schließen", 12, DIM)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_child(_hint)
	_restyle_chips()

	# Inhalt: virtuelle Liste links, Diffs rechts.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	var list_wrap := Control.new()
	list_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_wrap.clip_contents = true
	body.add_child(list_wrap)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	list_wrap.add_child(_scroll)
	_content = Control.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _layout_rows())
	_scroll.resized.connect(_ensure_pool)
	_content.resized.connect(_layout_rows)
	_empty_label = _label("Nichts gefunden.", 15, DIM)
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_empty_label.offset_top = 40
	_empty_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty_label.visible = false
	list_wrap.add_child(_empty_label)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(DETAIL_W, 0)
	var dsb := UiTheme.glass_box(14, 0.5, 0.12)
	dsb.set_content_margin_all(14)
	detail_panel.add_theme_stylebox_override("panel", dsb)
	body.add_child(detail_panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(_detail)
	_detail_cover = TextureRect.new()
	_detail_cover.custom_minimum_size = Vector2(0, 170)
	_detail_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_cover.clip_contents = true
	_detail.add_child(_detail_cover)
	_detail_title = _label("", 18, TEXT)
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.add_child(_detail_title)
	_detail_sub = _label("", 13, DIM)
	_detail_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.add_child(_detail_sub)
	_detail_meta = _label("", 13, DIM)
	_detail.add_child(_detail_meta)
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.add_child(dscroll)
	_diff_box = VBoxContainer.new()
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_box.add_theme_constant_override("separation", 6)
	dscroll.add_child(_diff_box)
	_show_detail()


func _restyle_chips() -> void:
	for i in _star_chips.size():
		_style_toggle(_star_chips[i], i == _star_filter)
	if _dir_btn != null:
		_dir_btn.text = "↓" if _desc else "↑"


# ---------------------------------------------------------------------------
# Filter / Sortierung
# ---------------------------------------------------------------------------

func _on_query(q: String) -> void:
	_query = q
	_refilter(selected_set())


func set_star_filter(i: int) -> void:
	_star_filter = clampi(i, 0, STAR_FILTERS.size() - 1)
	_restyle_chips()
	_refilter(selected_set())


func set_sort(mode: int, desc: bool) -> void:
	_sort = mode
	_desc = desc
	if _sort_btn.selected != mode:
		_sort_btn.select(mode)
	_restyle_chips()
	_refilter(selected_set())


## Sternbereich fuers Turnier setzen (hi < 0 = kein Bereich).
func set_star_range(lo: float, hi: float) -> void:
	star_range = Vector2(lo, hi)
	if _count_label != null:
		_refilter(selected_set())


## Eintraege auf Diffs im Bereich [lo, hi] verengen (Kopien, Original bleibt).
static func clamp_to_range(entries: Array, lo: float, hi: float) -> Array:
	var out: Array = []
	for e in entries:
		var keep: Array = []
		for d in e.diffs:
			if float(d.stars) >= lo - 0.0001 and float(d.stars) <= hi + 0.0001:
				keep.append(d)
		if keep.is_empty():
			continue
		var c: Dictionary = e.duplicate()
		c["diffs"] = keep
		out.append(c)
	return out


func _refilter(keep: MapSet) -> void:
	_shown = filter_entries(_entries, _query, _star_filter)
	if star_range.y >= 0.0:
		_shown = clamp_to_range(_shown, star_range.x, star_range.y)
	sort_entries(_shown, _sort, _desc)
	var n := _shown.size()
	_count_label.text = (tr("%s von %s Maps") % [UiTheme.fmt_score(n), UiTheme.fmt_score(_entries.size())]) \
			if n != _entries.size() else (tr("%s Maps") % UiTheme.fmt_score(n))
	_empty_label.visible = n == 0
	_content.custom_minimum_size = Vector2(0, maxf(n * (ROW_H + ROW_GAP) - ROW_GAP, 0.0))
	var idx := -1
	if keep != null:
		for i in n:
			if _shown[i].ms == keep:
				idx = i
				break
	if idx < 0 and n > 0:
		idx = 0
	_sel = idx
	_sel_diff = -1
	if idx < 0:
		_show_detail()
	else:
		_select(idx, -1, false)
	for row in _pool:
		row.idx = -1
	_layout_rows()


# ---------------------------------------------------------------------------
# Virtuelle Liste
# ---------------------------------------------------------------------------

func _ensure_pool() -> void:
	var need := int(ceil(_scroll.size.y / (ROW_H + ROW_GAP))) + 2
	while _pool.size() < need:
		_pool.append(_make_row())
	_layout_rows()


func _make_row() -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size = Vector2(100, ROW_H)
	b.add_theme_stylebox_override("normal", _box_card)
	b.add_theme_stylebox_override("hover", _box_hover)
	b.add_theme_stylebox_override("pressed", _box_hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.visible = false
	_content.add_child(b)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 6
	hb.offset_top = 6
	hb.offset_bottom = -6
	hb.offset_right = -14
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var cover := TextureRect.new()
	cover.custom_minimum_size = Vector2(COVER_W, ROW_H - 12)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.clip_contents = true
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cover)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var t := _label("", 16, TEXT)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	vb.add_child(t)
	var sub := _label("", 13, DIM)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	vb.add_child(sub)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(pills)
	var pill_list: Array = []
	for i in MAX_PILLS:
		pill_list.append(_make_pill(pills, 11))
	var more := _label("", 11, DIM)
	pills.add_child(more)
	var side := VBoxContainer.new()
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side.custom_minimum_size = Vector2(70, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(side)
	var grade := _label("", 24, TEXT)
	grade.add_theme_font_override("font", UiTheme.heading_font(0))
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(grade)
	var played := _label("✓ im Raum", 11, PLAYED_COL)
	played.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	played.modulate = Color(1, 1, 1, 0.75)
	side.add_child(played)
	var row := {
		"btn": b, "cover": cover, "title": t, "sub": sub, "pills": pill_list,
		"more": more, "grade": grade, "played": played, "idx": -1, "file": "",
	}
	b.pressed.connect(func():
		if row.idx >= 0:
			_select(row.idx, -1))
	return row


## Kleine Pill mit eigener (wiederverwendeter) StyleBox.
func _make_pill(parent: Node, size: int) -> Dictionary:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label("", size, Color(0.05, 0.05, 0.08))
	p.add_child(l)
	parent.add_child(p)
	return { "panel": p, "box": sb, "label": l }


func _set_pill(pill: Dictionary, text: String, bg: Color, fg: Color) -> void:
	(pill.box as StyleBoxFlat).bg_color = bg
	var l: Label = pill.label
	l.text = text
	l.add_theme_color_override("font_color", fg)
	(pill.panel as Control).visible = true


func _layout_rows() -> void:
	if _pool.is_empty():
		return
	var stride := ROW_H + ROW_GAP
	var first := int(floor(_scroll.scroll_vertical / stride))
	var w := maxf(_content.size.x - 14.0, 100.0)
	for k in _pool.size():
		var row: Dictionary = _pool[k]
		var idx := first + k
		var b: Button = row.btn
		if idx < 0 or idx >= _shown.size():
			b.visible = false
			row.idx = -1
			continue
		b.visible = true
		b.position = Vector2(0, idx * stride)
		b.size = Vector2(w, ROW_H)
		if row.idx != idx:
			row.idx = idx
			_bind_row(row, _shown[idx])
		b.add_theme_stylebox_override("normal", _box_sel if idx == _sel else _box_card)


func _bind_row(row: Dictionary, e: Dictionary) -> void:
	var ms: MapSet = e.ms
	(row.title as Label).text = ms.title
	var sub := ms.artist
	if ms.creator != "":
		sub += "  ·  " + tr("von") + " " + ms.creator
	(row.sub as Label).text = sub
	var diffs: Array = e.diffs
	var pills: Array = row.pills
	for i in pills.size():
		if i < diffs.size():
			var st: float = diffs[i].stars
			_set_pill(pills[i], _stars_short(st), star_color(st), _pill_fg(st))
		else:
			(pills[i].panel as Control).visible = false
	(row.more as Label).text = ("+%d" % (diffs.size() - pills.size())) if diffs.size() > pills.size() else ""
	var g: String = e.grade
	var gl: Label = row.grade
	gl.text = g
	gl.add_theme_color_override("font_color", GRADE_COLOR.get(g.left(1), TEXT))
	(row.played as Label).visible = _set_played(e)
	row.file = e.file
	var cover: TextureRect = row.cover
	cover.texture = _cover_for(e)


func _set_played(e: Dictionary) -> bool:
	if not played_fn.is_valid():
		return false
	for d in e.diffs:
		if played_fn.call(e.file, d.version):
			return true
	return false


func _scroll_to(i: int) -> void:
	var stride := ROW_H + ROW_GAP
	var top := i * stride
	var v := float(_scroll.scroll_vertical)
	var h := _scroll.size.y
	if top < v:
		_scroll.scroll_vertical = int(top)
	elif top + ROW_H > v + h:
		_scroll.scroll_vertical = int(top + ROW_H - h)
	_layout_rows()


# ---------------------------------------------------------------------------
# Cover (WorkerThreadPool, Fallback haeppchenweise im Hauptthread)
# ---------------------------------------------------------------------------

func _cover_for(e: Dictionary) -> Texture2D:
	var file: String = e.file
	if _covers.has(file):
		return _covers[file]
	if not _cover_pending.has(file):
		_cover_pending[file] = e.ms
		var ms: MapSet = e.ms
		_cover_tasks.append(WorkerThreadPool.add_task(_load_cover.bind(file, ms.osz_path)))
		set_process(true)
	return null


## Worker: Disk-Thumbnail (vom Library-Scan) dekodieren. null = Fallback.
func _load_cover(file: String, osz_path: String) -> void:
	var tmp := MapSet.new()
	tmp.osz_path = osz_path
	var path := tmp.thumb_path()
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.new()
		if img.load(ProjectSettings.globalize_path(path)) != OK:
			img = null
	_cover_mutex.lock()
	_cover_done.append([file, img])
	_cover_mutex.unlock()


func _process(_delta: float) -> void:
	var i := 0
	while i < _cover_tasks.size():
		if WorkerThreadPool.is_task_completed(_cover_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_cover_tasks[i])
			_cover_tasks.remove_at(i)
		else:
			i += 1
	_cover_mutex.lock()
	var done := _cover_done
	_cover_done = []
	_cover_mutex.unlock()
	for d in done:
		var file: String = d[0]
		if d[1] == null:
			_cover_fallback.append(file)
			continue
		_apply_cover(file, ImageTexture.create_from_image(d[1]))
	# Kein Disk-Thumbnail: aus dem Zip bauen, hoechstens eins pro Frame.
	var t_end := Time.get_ticks_usec() + COVER_FALLBACK_USEC
	while not _cover_fallback.is_empty() and Time.get_ticks_usec() < t_end:
		var file: String = _cover_fallback.pop_front()
		var ms: MapSet = _cover_pending.get(file)
		_apply_cover(file, ms.thumb_texture() if ms != null else null)
		break
	if _cover_tasks.is_empty() and _cover_done.is_empty() and _cover_fallback.is_empty():
		set_process(false)


func _apply_cover(file: String, tex: Texture2D) -> void:
	_covers[file] = tex
	_cover_pending.erase(file)
	for row in _pool:
		if row.idx >= 0 and row.file == file:
			(row.cover as TextureRect).texture = tex
	var ms := selected_set()
	if ms != null and ms.osz_path.get_file() == file:
		_detail_cover.texture = tex


# ---------------------------------------------------------------------------
# Auswahl + Diff-Liste
# ---------------------------------------------------------------------------

## i = Index in _shown; diff_i = Index in entry.diffs (-1 = bester/haerteste).
func _select(i: int, diff_i: int, notify: bool = true) -> void:
	var prev := _sel
	var prev_set := selected_set() if prev >= 0 and prev < _shown.size() else null
	_sel = i
	var e: Dictionary = _shown[i]
	if diff_i < 0:
		diff_i = _default_diff(e)
	_sel_diff = diff_i
	_show_detail()
	_layout_rows()
	if notify and (prev_set != e.ms or prev != i):
		set_selected.emit(e.ms)


## Vorauswahl: zuletzt gespielte Diff mit Score, sonst die haerteste.
func _default_diff(e: Dictionary) -> int:
	var diffs: Array = e.diffs
	var best_i := -1
	var best_d := ""
	for k in diffs.size():
		var b: Dictionary = diffs[k].best
		if not b.is_empty() and str(b.get("date", "")) > best_d:
			best_d = str(b.get("date", ""))
			best_i = k
	return best_i if best_i >= 0 else diffs.size() - 1


func _show_detail() -> void:
	for c in _diff_box.get_children():
		c.queue_free()
	_diff_btns.clear()
	var ms := selected_set()
	if ms == null:
		_detail_cover.texture = null
		_detail_title.text = "Keine Map"
		_detail_sub.text = "Suche anpassen oder online laden."
		_detail_meta.text = ""
		return
	var e: Dictionary = _shown[_sel]
	_detail_cover.texture = _covers.get(e.file, null)
	_detail_title.text = ms.title
	_detail_sub.text = tr("%s  ·  von %s") % [ms.artist, ms.creator] if ms.creator != "" else ms.artist
	var parts: Array[String] = []
	var bpm: float = e.bpm
	if bpm > 0.0:
		parts.append(UiTheme.fmt_num(bpm, 0 if is_equal_approx(bpm, roundf(bpm)) else 1) + " BPM")
	if float(e.length) > 0.0:
		parts.append(OnlineBrowser.fmt_length(int(float(e.length) / 1000.0)))
	parts.append(tr("%d Diffs") % e.diffs.size() if e.diffs.size() != 1 else tr("1 Diff"))
	_detail_meta.text = "  ·  ".join(parts)
	if not can_pick:
		_diff_box.add_child(_label("Nur der Kronenträger wählt die Map.", 13, DIM))
	var diffs: Array = e.diffs
	for k in diffs.size():
		_diff_box.add_child(_diff_row(e, k))


func _diff_row(e: Dictionary, k: int) -> Button:
	var d: Dictionary = e.diffs[k]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 60)
	b.disabled = not can_pick
	var on := k == _sel_diff
	b.add_theme_stylebox_override("normal", _diff_box_sel if on else _diff_box_n)
	b.add_theme_stylebox_override("hover", _diff_box_sel if on else _diff_box_h)
	b.add_theme_stylebox_override("pressed", _diff_box_sel)
	b.add_theme_stylebox_override("disabled", _diff_box_n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var st: float = d.stars
	var pill := _make_pill(hb, 13)
	_set_pill(pill, _stars_short(st), star_color(st), _pill_fg(st))
	(pill.panel as Control).custom_minimum_size = Vector2(66, 0)
	(pill.label as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var vl := _label(str(d.version), 15, TEXT)
	vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vl.clip_text = true
	vb.add_child(vl)
	var best: Dictionary = d.best
	var sl: Label
	if best.is_empty():
		sl = _label("Noch kein eigener Score", 12, Color(DIM, 0.8))
	else:
		var line := "%s  ·  %s" % [UiTheme.fmt_score(int(best.get("score", 0))),
			UiTheme.fmt_pct(float(best.get("accuracy", 0.0)) * 100.0)]
		if float(best.get("pp", -1.0)) > 0.0:
			line += "  ·  " + UiTheme.fmt_pp(float(best.pp))
		sl = _label(line, 12, Color(0.80, 0.84, 0.92))
	vb.add_child(sl)
	if played_fn.is_valid() and played_fn.call(e.file, d.version):
		var pl := _label("✓", 15, PLAYED_COL)
		pl.tooltip_text = "Im Raum schon gespielt"
		pl.mouse_filter = Control.MOUSE_FILTER_PASS
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pl.modulate = Color(1, 1, 1, 0.8)
		hb.add_child(pl)
	var mods := mods_badge(best)
	if mods != "":
		var mp := _make_pill(hb, 11)
		_set_pill(mp, mods, Color(1.0, 0.45, 0.88, 0.22), Color(1.0, 0.70, 0.94))
	var g := str(best.get("grade", ""))
	var gl := _label(g if g != "" else "–", 24 if g != "" else 18, GRADE_COLOR.get(g.left(1), Color(DIM, 0.5)))
	gl.add_theme_font_override("font", UiTheme.heading_font(0))
	gl.custom_minimum_size = Vector2(40, 0)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(gl)
	b.pressed.connect(func(): _pick(k))
	b.mouse_entered.connect(func():
		if _sel_diff != k:
			_sel_diff = k
			_restyle_diffs())
	_diff_btns.append(b)
	return b


func _restyle_diffs() -> void:
	for k in _diff_btns.size():
		var b := _diff_btns[k]
		var on := k == _sel_diff
		b.add_theme_stylebox_override("normal", _diff_box_sel if on else _diff_box_n)
		b.add_theme_stylebox_override("hover", _diff_box_sel if on else _diff_box_h)


func _pick(k: int) -> void:
	if not can_pick:
		return
	var ms := selected_set()
	if ms == null:
		return
	var diffs: Array = _shown[_sel].diffs
	if k < 0 or k >= diffs.size():
		return
	picked.emit(ms, int(diffs[k].idx))


# ---------------------------------------------------------------------------
# Online-Tab (Komponente des Song-Browsers)
# ---------------------------------------------------------------------------

func open_online() -> void:
	if _online == null:
		_online = OnlineBrowser.new(library)
		_online.visible = false
		add_child(_online)
		_online.preview_stream.connect(func(st: AudioStream): preview_stream.emit(st))
		_online.preview_stop.connect(func(): preview_stop.emit())
		_online.map_downloaded.connect(_on_online_downloaded)
		_online.closed.connect(func(): _search.grab_focus.call_deferred())
	_online.open()


## Download fertig: Bibliothek neu einlesen; Einzel-Download sofort anwaehlen
## und (Kronentraeger) fuer den Raum waehlen.
func _on_online_downloaded(_set_id: int, osz_path: String, select: bool) -> void:
	library.scan()
	reload()
	_start_meta_scan()
	if not select:
		return
	if not select_path(osz_path):
		# Suche/Filter verstecken die neue Map: zuruecksetzen.
		_search.text = ""
		_query = ""
		_star_filter = 0
		_restyle_chips()
		_refilter(null)
		if not select_path(osz_path):
			return
	if can_pick:
		_online.close()
		_pick(_sel_diff)


# ---------------------------------------------------------------------------
# Tastatur
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if online_open():
		if k.keycode == KEY_ESCAPE:
			_online.close()
			get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_ESCAPE:
			close()
		KEY_DOWN:
			_move(1)
		KEY_UP:
			_move(-1)
		KEY_PAGEDOWN:
			_move(maxi(int(_scroll.size.y / (ROW_H + ROW_GAP)), 1))
		KEY_PAGEUP:
			_move(-maxi(int(_scroll.size.y / (ROW_H + ROW_GAP)), 1))
		KEY_TAB:
			if _sel >= 0:
				var n: int = _shown[_sel].diffs.size()
				_sel_diff = (_sel_diff + (-1 if k.shift_pressed else 1) + n) % n
				_restyle_diffs()
		KEY_ENTER, KEY_KP_ENTER:
			_pick(_sel_diff)
		_:
			return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	if _shown.is_empty():
		return
	var i := clampi((_sel if _sel >= 0 else 0) + step, 0, _shown.size() - 1)
	if i != _sel:
		_select(i, -1)
	_scroll_to(i)


# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

static func star_color(stars: float) -> Color:
	if stars < 0.0:
		return Color(0.5, 0.5, 0.55)
	return OnlineBrowser.star_color(stars)


static func _pill_fg(stars: float) -> Color:
	return Color(0.05, 0.05, 0.08) if stars < 6.5 else Color(0.95, 0.95, 1.0)


static func _stars_short(st: float) -> String:
	return "? ★" if st < 0.0 else UiTheme.fmt_num(st, 2) + " ★"
