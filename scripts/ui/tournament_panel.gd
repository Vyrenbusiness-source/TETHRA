class_name TournamentPanel
extends Control

## Turnier-Oberflaeche im Multiplayer-Raum: je Phase eine Ansicht.
##  PICK     Pool-Raster, Maps aus Bibliothek / Online-Browser / Auto-Fuellung
##  BAN      jeder streicht eine Hass-Map, danach Aufdecken + Rundenreihenfolge
##  BETWEEN  Zwischenstand (Tabelle + Rundenergebnis), Host: naechste Map
## Der Zustand kommt aus Lobby.tournament (Tournament.to_dict-Sync). Fehlende
## Maps des Pools laedt jeder Client selbst ueber den BeatmapMirror.

signal back_to_room
signal end_requested

const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const GOOD := UiTheme.GOOD
const WARN := Color(1.0, 0.45, 0.52)
const GOLD := Color(1.0, 0.85, 0.3)
const SILVER := Color(0.78, 0.82, 0.9)
const BRONZE := Color(0.85, 0.55, 0.35)
const COVER_H := 112
const MAX_ONLINE_PAGES := 8

var library: MapLibrary
## Zustand (live aus Lobby, im Harness gesetzt).
var t: Tournament = null
var names: Dictionary = {}
var my_id := 1
var is_host := false
var harness := false

var _mirror: BeatmapMirror
var _body: VBoxContainer
var _index: Dictionary = {}
var _dl_fail: Dictionary = {}
var _prog: Dictionary = {}
var _strikes: Array = []
var _reveal_played := false
var _picker: MapPicker = null
var _online: OnlineBrowser = null
var _filling := false
var _fill_status := ""
var _fill_used: Dictionary = {}
var _fill_pages := 0
var _fill_need := 0
var _status: Label = null


class _Strike extends Control:
	var p := 0.0:
		set(v):
			p = v
			queue_redraw()

	func _draw() -> void:
		if p <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.55 * p))
		var a := Vector2(size.x * 0.06, size.y * 0.1)
		var b := Vector2(size.x * 0.94, size.y * 0.9)
		draw_line(a, a.lerp(b, p), Color(1.0, 0.42, 0.5, 0.9), 4.0, true)


func _init(lib: MapLibrary) -> void:
	library = lib
	name = "TournamentPanel"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_mirror = get_node_or_null("/root/Mirror") as BeatmapMirror
	if _mirror != null:
		_mirror.download_progress.connect(_on_dl_progress)
		_mirror.download_done.connect(_on_dl_done)
		_mirror.download_failed.connect(_on_dl_failed)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.01, 0.03, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(20, 0.9)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	panel.add_child(_body)
	_rebuild_index()
	refresh()


## Zustand aus der Lobby uebernehmen und neu zeichnen.
func sync_from_lobby() -> void:
	t = Lobby.tournament
	names = {}
	for id in Lobby.players:
		names[int(id)] = str(Lobby.players[id].get("name", "?"))
	my_id = multiplayer.get_unique_id()
	is_host = Lobby.is_host
	refresh()


# ---------------------------------------------------------------------------
# Hilfen (auch vom Endbild genutzt)
# ---------------------------------------------------------------------------

static func lbl(text: String, size: int, col: Color = TEXT, heading: bool = false, spacing: int = 3) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", UiTheme.heading_font(spacing))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func chip(text: String, col: Color, size: int = 12) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = Color(col.r, col.g, col.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl(text, size, col))
	return p


## Runder Avatar mit Anfangsbuchstabe (wie mp_lobby._avatar).
static func avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(pname.hash() % 360) / 360.0, 0.45, 0.62)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.08, 0.09, 0.14, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(sz * 0.5))
	l.add_theme_color_override("font_color", TEXT)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func rank_color(rank: int) -> Color:
	match rank:
		1: return GOLD
		2: return SILVER
		3: return BRONZE
	return DIM


static func glass(radius: int = 12, alpha: float = 0.5, border: float = 0.12, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.glass_box(radius, alpha, border)
	sb.shadow_size = 0
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Tabellenzeile mit fester Spaltenbreite (width <= 0 = fuellt). Zellen:
## String oder Control. Kopfzeile ohne Hintergrund.
static func table_row(cells: Array, widths: Array, size: int = 16, head: bool = false,
		hl: bool = false, rank_col: Color = TEXT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for i in cells.size():
		var c: Variant = cells[i]
		var node: Control
		if c is Control:
			node = c
		else:
			var l := lbl(str(c), size, DIM if head else (rank_col if i == 0 else TEXT))
			if head:
				l.add_theme_font_size_override("font_size", 12)
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if i > 0 and widths[i] > 0:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			node = l
		var w: int = widths[i]
		if w > 0:
			node.custom_minimum_size.x = w
		else:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(node)
	if head:
		return row
	var card := glass(10, 0.55 if hl else 0.38, 0.30 if hl else 0.08, 8)
	if hl:
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
		sb.border_color = Color(ACCENT, 0.55)
	card.add_child(row)
	return card


func _name_cell(peer: int, pname: String, sz: int = 28) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(avatar(pname, sz))
	var l := lbl(pname + ("  (du)" if peer == my_id else ""), 16)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h


func _pname(peer: int) -> String:
	if names.has(peer):
		return str(names[peer])
	if t != null and t.player_names.has(peer):
		return str(t.player_names[peer])
	return "?"


static func stars_text(s: float) -> String:
	return "★ " + UiTheme.fmt_num(s, 2)


func star_range_text() -> String:
	var lo := float(t.config.get("stars_lo", 0.0))
	var hi := float(t.config.get("stars_hi", 99.0))
	return "★ %s–%s" % [UiTheme.fmt_num(lo, 1), UiTheme.fmt_num(hi, 1)]


func mods_text() -> String:
	var parts: Array[String] = []
	var mods: Dictionary = t.config.get("mods", {})
	for k in ["SV", "NF"]:
		if bool(mods.get(k, false)):
			parts.append(k)
	return "Mods: " + (" + ".join(parts) if not parts.is_empty() else "keine")


# ---------------------------------------------------------------------------
# Lokale Maps + Downloads
# ---------------------------------------------------------------------------

static func set_id_of(fname: String) -> int:
	var base := fname.get_basename()
	if base.begins_with("mirror_") and base.substr(7).is_valid_int():
		return int(base.substr(7))
	var head := base.split(" ")[0]
	return int(head) if head.is_valid_int() else 0


func _rebuild_index() -> void:
	_index = {}
	if library == null:
		return
	for ms in library.mapsets:
		var f: String = ms.osz_path.get_file()
		_index["f:" + f] = ms
		var sid := set_id_of(f)
		if sid > 0:
			_index["s:%d" % sid] = ms


func local_set(m: Dictionary) -> MapSet:
	var f := str(m.get("file", ""))
	if f != "" and _index.has("f:" + f):
		return _index["f:" + f]
	var sid := int(m.get("set_id", 0))
	if sid > 0 and _index.has("s:%d" % sid):
		return _index["s:%d" % sid]
	return null


func _cover_for(m: Dictionary) -> Texture2D:
	var ms := local_set(m)
	if ms != null:
		return ms.thumb_texture()
	var sid := int(m.get("set_id", 0))
	if _mirror != null and sid > 0:
		return _mirror.cached_cover(sid)
	return null


func _ensure_downloads() -> void:
	if t == null or harness or _mirror == null:
		return
	for m in t.pool:
		if bool(m.get("banned", false)):
			continue
		var sid := int(m.get("set_id", 0))
		if sid <= 0 or local_set(m) != null or _dl_fail.has(sid) or _mirror.is_downloading(sid):
			continue
		_mirror.download(sid, library.maps_dir)


func _on_dl_progress(id: int, ratio: float) -> void:
	if not _prog.has(id):
		return
	for pair in _prog[id]:
		if is_instance_valid(pair[0]):
			(pair[0] as ProgressBar).value = ratio
			(pair[1] as Label).text = "lädt… %s %%" % UiTheme.fmt_score(int(ratio * 100.0))


func _on_dl_done(id: int, _path: String) -> void:
	if t == null or not _in_pool(id):
		return
	library.scan()
	_rebuild_index()
	_dl_fail.erase(id)
	refresh()


func _on_dl_failed(id: int, message: String) -> void:
	if t == null or not _in_pool(id):
		return
	_dl_fail[id] = message
	refresh()


func _in_pool(sid: int) -> bool:
	for m in t.pool:
		if int(m.get("set_id", 0)) == sid:
			return true
	return false


# ---------------------------------------------------------------------------
# Aufbau je Phase
# ---------------------------------------------------------------------------

func refresh() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	_prog = {}
	_strikes = []
	_status = null
	if t == null:
		return
	_ensure_downloads()
	match t.phase:
		Tournament.Phase.PICK:
			_build_pick()
		Tournament.Phase.BAN:
			_build_ban()
		Tournament.Phase.END:
			end_requested.emit()
		_:
			_build_between()
	_play_strikes()


func _header(sub: String, step: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(lbl("TURNIER", 26, TEXT, true))
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	col.add_child(meta)
	meta.add_child(chip("%d Maps" % int(t.config.get("maps", 10)), DIM))
	meta.add_child(chip(star_range_text(), DIM))
	meta.add_child(chip(mods_text(), DIM))
	var sl := lbl(sub, 14, DIM)
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size.x = 120
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.add_child(sl)
	var steps := ["MAPS WÄHLEN", "BANS", "RUNDEN"]
	for i in steps.size():
		var on := i == step
		row.add_child(chip(steps[i], ACCENT if on else DIM, 13))
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Zurück zum Raum" if not is_host else "Turnier abbrechen"
	close.custom_minimum_size = Vector2(38, 38)
	UiTheme.style_button(close)
	close.pressed.connect(func():
		if is_host and not harness:
			Lobby.tour_cancel()
		back_to_room.emit())
	row.add_child(close)


func _cols() -> int:
	var w := get_viewport_rect().size.x - 88.0 - 56.0
	return clampi(int(w / 300.0), 2, 5)


func _scroll_grid(cols: int) -> GridContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	return g


func _bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_body.add_child(bar)
	return bar


func _btn(text: String, primary: bool, w: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 46)
	UiTheme.style_button(b, primary)
	b.pressed.connect(cb)
	return b


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# --- PICK -------------------------------------------------------------------

func _build_pick() -> void:
	var want := int(t.config.get("maps", 10))
	_header("Maps für das Turnier sammeln — jeder darf mitwählen, auch Maps aus dem Online-Browser.", 0)
	var g := _scroll_grid(_cols())
	for i in want:
		if i < t.pool.size():
			g.add_child(_card(i, t.pool[i], "pick"))
		else:
			g.add_child(_empty_slot(i))
	var bar := _bar()
	bar.add_child(lbl("%d / %d Maps im Pool" % [t.pool.size(), want], 16, ACCENT if t.pool.size() < want else GOOD))
	_status = lbl(_fill_status, 13, DIM)
	bar.add_child(_status)
	bar.add_child(_spacer())
	var full: bool = t.pool.size() >= want
	var b1 := _btn("Aus Bibliothek", false, 170, _open_library)
	b1.disabled = full
	bar.add_child(b1)
	var b2 := _btn("Aus Online-Browser", false, 200, _open_online)
	b2.disabled = full
	bar.add_child(b2)
	if is_host:
		var b3 := _btn("Rest automatisch füllen", false, 230, _autofill)
		b3.disabled = full or _filling
		bar.add_child(b3)
		var b4 := _btn("Weiter zu Bans", true, 190, func():
			if not harness:
				Lobby.tour_start_bans())
		b4.disabled = not (full or (t.autofill_done and t.pool.size() >= 2))
		bar.add_child(b4)
	else:
		bar.add_child(lbl("Der Host startet die Bans, sobald der Pool voll ist.", 13, DIM))


func _empty_slot(i: int) -> Control:
	var c := glass(12, 0.22, 0.08, 10)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(0, COVER_H + 96)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var n := lbl("%d" % (i + 1), 34, Color(DIM, 0.45), true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var l := lbl("noch frei", 13, Color(DIM, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return c


## Cover-Karte. mode: "pick" | "ban" | "plain".
func _card(i: int, m: Dictionary, mode: String, banned: bool = false) -> Control:
	var card := glass(12, 0.5, 0.14, 0)
	card.clip_contents = true
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(0, COVER_H)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color.from_hsv(float(str(m.get("title", "")).hash() % 360) / 360.0, 0.35, 0.30)
	holder.add_theme_stylebox_override("panel", hb)
	holder.clip_contents = true
	v.add_child(holder)
	var tex := _cover_for(m)
	if tex != null:
		var tr := TextureRect.new()
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture = tex
		holder.add_child(tr)
	var stars := float(m.get("stars", 0.0))
	var sc := OnlineBrowser.star_color(stars)
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(sc, 0.95)
	psb.set_corner_radius_all(20)
	psb.content_margin_left = 10
	psb.content_margin_right = 10
	psb.content_margin_top = 2
	psb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", psb)
	pill.position = Vector2(10, 10)
	pill.add_child(lbl(stars_text(stars), 12, Color(0.03, 0.04, 0.07) if stars < 6.4 else Color(1, 1, 1, 0.95)))
	holder.add_child(pill)
	if mode == "pick" and (int(m.get("by", -1)) == my_id or is_host):
		var x := Button.new()
		x.text = "✕"
		x.tooltip_text = "Aus dem Pool entfernen"
		x.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		x.offset_left = -38
		x.offset_top = 8
		x.offset_right = -8
		x.offset_bottom = 38
		UiTheme.style_ghost_button(x, 10)
		var idx := i
		x.pressed.connect(func():
			if not harness:
				Lobby.tour_remove_map(idx))
		holder.add_child(x)
	var info := MarginContainer.new()
	for side in ["left", "right"]:
		info.add_theme_constant_override("margin_" + side, 12)
	info.add_theme_constant_override("margin_top", 9)
	info.add_theme_constant_override("margin_bottom", 11)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(col)
	var title := lbl(str(m.get("title", "?")), 16, TEXT.darkened(0.45) if banned else TEXT, true, 0)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(title)
	var ver := str(m.get("version", ""))
	var sub := lbl("%s%s" % [str(m.get("artist", "")), ("  ·  " + ver) if ver != "" else ""], 12, DIM)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(sub)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	var by := int(m.get("by", -1))
	if by >= 0:
		foot.add_child(avatar(_pname(by), 18))
		var who := lbl("gewählt von " + _pname(by), 12, TEXT.darkened(0.15))
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(who)
	else:
		foot.add_child(_spacer())
	if banned:
		foot.add_child(chip("gestrichen von " + _banners(i), WARN, 11))
		_decorate_ban(holder)
	else:
		foot.add_child(_status_chip(m))
	return card


## Chip "bereit" oder "fehlt — lädt…" mit Fortschrittsbalken.
func _status_chip(m: Dictionary) -> Control:
	if local_set(m) != null:
		return chip("✓ bereit", GOOD)
	var sid := int(m.get("set_id", 0))
	if sid <= 0:
		return chip("fehlt", WARN)
	if _dl_fail.has(sid):
		return chip("Fehler beim Laden", WARN)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(44, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ratio := _mirror.active_ratio(sid) if _mirror != null else 0.0
	bar.value = maxf(ratio, 0.0)
	h.add_child(bar)
	var l := lbl("fehlt — lädt…", 12, ACCENT)
	h.add_child(l)
	if not _prog.has(sid):
		_prog[sid] = []
	_prog[sid].append([bar, l])
	return h


# --- BAN --------------------------------------------------------------------

func _voters() -> Array:
	var ids: Array = names.keys()
	ids.sort()
	return ids


func _has_voted(peer: int) -> bool:
	return int(t.bans.get(peer, -1)) >= 0


func _all_voted() -> bool:
	if t.remaining() <= 1 and not t.pool.is_empty() and not t.bans.is_empty():
		return true
	var ids := _voters()
	if ids.is_empty():
		return false
	for p in ids:
		if not _has_voted(int(p)):
			return false
	return true


## Pool-Indizes, die nach dem Aufdecken gestrichen sind.
func _banned_set() -> Dictionary:
	var out := {}
	for i in t.pool.size():
		if bool(t.pool[i].get("banned", false)):
			out[i] = true
	if out.is_empty() and _all_voted():
		for p in t.bans:
			var bi := int(t.bans[p])
			if bi >= 0:
				out[bi] = true
	return out


func _build_ban() -> void:
	var revealed := _all_voted()
	_header("Streiche die Map, die du am wenigsten spielen willst." if not revealed
		else "Alle haben gewählt — diese Maps sind raus.", 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)
	var g := _scroll_grid(maxi(_cols() - 1, 2))
	g.get_parent().reparent(row)
	var banned := _banned_set() if revealed else {}
	var mine := int(t.bans.get(my_id, -1))
	for i in t.pool.size():
		var c := _card(i, t.pool[i], "ban", banned.has(i) and revealed)
		g.add_child(c)
		if not revealed:
			_ban_interaction(c, i, mine == i)
	# Seitenleiste: Wer hat gewaehlt + Reihenfolge der Runden.
	var side := glass(14, 0.5, 0.12, 14)
	side.custom_minimum_size = Vector2(300, 0)
	row.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	sv.add_child(lbl("ABSTIMMUNG", 13, ACCENT, true))
	for p in _voters():
		var pid := int(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(avatar(_pname(pid), 26))
		var nl := lbl(_pname(pid) + ("  (du)" if pid == my_id else ""), 15)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(nl)
		if revealed and int(t.bans.get(pid, -1)) >= 0:
			var bt: String = str(t.pool[int(t.bans[pid])].get("title", "?"))
			h.add_child(chip("strich: " + bt.left(14), WARN, 11))
		else:
			h.add_child(chip("hat gewählt", GOOD) if _has_voted(pid) else chip("wählt…", DIM))
		sv.add_child(h)
	if revealed:
		sv.add_child(HSeparator.new())
		sv.add_child(lbl("REIHENFOLGE DER RUNDEN", 13, ACCENT, true))
		var order: Array = t.play_order()
		var n := 1
		for pi in order:
			var m: Dictionary = t.pool[int(pi)]
			var oh := HBoxContainer.new()
			oh.add_theme_constant_override("separation", 8)
			oh.add_child(lbl("%d" % n, 14, ACCENT))
			var ol := lbl(str(m.get("title", "?")), 14)
			ol.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			oh.add_child(ol)
			oh.add_child(lbl(stars_text(float(m.get("stars", 0.0))), 12, DIM))
			sv.add_child(oh)
			n += 1
	var bar := _bar()
	if not revealed:
		bar.add_child(lbl(("Deine Wahl ist markiert — du kannst sie ändern, bis alle gewählt haben."
			if mine >= 0 else "Klicke eine Map, um sie abzuwählen."), 14, DIM))
	bar.add_child(_spacer())
	if is_host:
		var go := _btn("Turnier starten", true, 220, func():
			if not harness:
				Lobby.tour_begin())
		go.disabled = not revealed
		bar.add_child(go)
	elif revealed:
		bar.add_child(lbl("Warte auf den Host…", 14, DIM))


func _ban_interaction(card: Control, i: int, mine: bool) -> void:
	_ignore_mouse(card)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if mine:
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
		sb.border_color = Color(WARN, 0.9)
		sb.set_border_width_all(2)
		card.add_theme_stylebox_override("panel", sb)
		card.modulate = Color(1, 0.92, 0.94)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not harness:
			Lobby.tour_ban(i))
	card.mouse_entered.connect(func(): card.modulate = Color(1.08, 1.08, 1.12))
	card.mouse_exited.connect(func(): card.modulate = Color(1, 0.92, 0.94) if mine else Color.WHITE)


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _banners(i: int) -> String:
	var who: Array[String] = []
	for p in t.bans:
		if int(t.bans[p]) == i:
			who.append(_pname(int(p)))
	return ", ".join(who)


## Aufgedeckte Ban-Karte: Durchstreich-Overlay auf dem Cover.
func _decorate_ban(holder: Control) -> void:
	var s := _Strike.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(s)
	_strikes.append(s)


func _play_strikes() -> void:
	if _strikes.is_empty():
		return
	if _reveal_played:
		for s in _strikes:
			(s as _Strike).p = 1.0
		return
	_reveal_played = true
	var tw := create_tween()
	tw.tween_interval(0.5)
	for s in _strikes:
		tw.tween_property(s, "p", 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.25)


# --- BETWEEN ----------------------------------------------------------------

func _build_between() -> void:
	var played: int = t.rounds.size()
	var total: int = t.order.size() if not t.order.is_empty() else t.remaining()
	_header("Zwischenstand nach Runde %d von %d" % [played, total], 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)

	# Links: Gesamttabelle.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	row.add_child(left)
	left.add_child(lbl("GESAMTWERTUNG", 13, ACCENT, true))
	var widths := [60, 0, 100, 80, 110]
	left.add_child(table_row(["Platz", "Spieler", "Punkte", "Siege", "Ø Acc"], widths, 16, true))
	for s in t.standings():
		var rk := int(s.get("rank", 0))
		left.add_child(table_row([
			"%d." % rk, _name_cell(int(s.get("peer", 0)), str(s.get("name", "?"))),
			UiTheme.fmt_score(int(s.get("points", 0))), str(int(s.get("wins", 0))),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0)],
			widths, 17, false, int(s.get("peer", 0)) == my_id, rank_color(rk)))

	# Rechts: Ergebnis der letzten Runde.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var last_idx: int = played - 1
	if last_idx >= 0 and int(t.rounds[last_idx].get("map", -1)) in range(t.pool.size()):
		var m: Dictionary = t.pool[int(t.rounds[last_idx].map)]
		right.add_child(lbl("RUNDE %d  ·  %s" % [played, str(m.get("title", "?")).to_upper()], 13, ACCENT, true))
		var res: Dictionary = t.rounds[last_idx].results
		var rows: Array = []
		for p in res:
			var r: Dictionary = res[p]
			rows.append([int(p), r])
		rows.sort_custom(func(a, b):
			var fa := bool(a[1].get("failed", false))
			var fb := bool(b[1].get("failed", false))
			if fa != fb:
				return fb
			return int(a[1].get("score", 0)) > int(b[1].get("score", 0)))
		var rw := [44, 0, 120, 90]
		right.add_child(table_row(["#", "Spieler", "Score", "Acc"], rw, 16, true))
		var n := 1
		for e in rows:
			var r: Dictionary = e[1]
			var failed := bool(r.get("failed", false))
			right.add_child(table_row([
				"–" if failed else "%d." % n,
				_name_cell(int(e[0]), str(r.get("name", _pname(int(e[0]))))),
				"ausgeschieden" if failed else UiTheme.fmt_score(int(r.get("score", 0))),
				UiTheme.fmt_pct(float(r.get("accuracy", 0.0)) * 100.0)],
				rw, 16, false, int(e[0]) == my_id, rank_color(n if not failed else 9)))
			n += 1
	# Naechste Map.
	var remaining: int = total - played
	if remaining > 0 and played < t.order.size():
		var nm: Dictionary = t.pool[int(t.order[played])]
		right.add_child(lbl("ALS NÄCHSTES", 13, ACCENT, true))
		right.add_child(_next_row(nm))
	var bar := _bar()
	bar.add_child(lbl("%d Maps noch zu spielen" % maxi(remaining, 0) if remaining > 0
		else "Alle Runden gespielt.", 14, DIM))
	bar.add_child(_spacer())
	if is_host:
		bar.add_child(_btn("Nächste Map" if remaining > 0 else "Zur Siegerehrung", true, 220, func():
			if not harness:
				Lobby.tour_next()))
	else:
		bar.add_child(lbl("Der Host startet die nächste Runde.", 14, DIM))


func _next_row(m: Dictionary) -> Control:
	var card := glass(12, 0.5, 0.14, 8)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(124, 70)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.clip_contents = true
	tr.texture = _cover_for(m)
	h.add_child(tr)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var tl := lbl(str(m.get("title", "?")), 17, TEXT, true, 0)
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(tl)
	var sub := lbl("%s  ·  %s" % [str(m.get("artist", "")), stars_text(float(m.get("stars", 0.0)))], 13, DIM)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	h.add_child(_status_chip(m))
	return card


# ---------------------------------------------------------------------------
# Maps hinzufuegen
# ---------------------------------------------------------------------------

func _range() -> Vector2:
	return Vector2(float(t.config.get("stars_lo", 0.0)), float(t.config.get("stars_hi", 99.0)))


func _in_pool_key(set_id: int, version: String) -> bool:
	for m in t.pool:
		if int(m.get("set_id", -1)) == set_id and str(m.get("version", "")) == version:
			return true
	return false


func _open_library() -> void:
	if t == null:
		return
	if _picker == null:
		_picker = MapPicker.new(library)
		_picker.visible = false
		add_child(_picker)
		_picker.picked.connect(func(ms: MapSet, diff: int):
			var fname := ms.osz_path.get_file()
			var data := {"set_id": set_id_of(fname), "file": fname,
				"version": ms.version_name_at(diff), "title": ms.title,
				"artist": ms.artist, "stars": ms.stars_at(diff), "online": false}
			if not harness:
				Lobby.tour_add_map(data)
			_picker.close())
	var r := _range()
	_picker.can_pick = true
	_picker.set_star_range(r.x, r.y)
	_picker.open()


func _open_online() -> void:
	if t == null:
		return
	if _online == null:
		_online = OnlineBrowser.new(library)
		_online.pick_mode = true
		_online.visible = false
		add_child(_online)
		_online.map_chosen.connect(func(data: Dictionary):
			if not harness:
				Lobby.tour_add_map(data))
	var r := _range()
	_online.pick_lo = r.x
	_online.pick_hi = r.y
	_online.pool_ids = {}
	for m in t.pool:
		_online.pool_ids[int(m.get("set_id", 0))] = true
	_online.open()


## Host: Rest des Pools fuellen — erst lokale Maps im Sternbereich, dann online.
func _autofill() -> void:
	if t == null or _filling:
		return
	var want := int(t.config.get("maps", 10))
	_fill_need = want - t.pool.size()
	if _fill_need <= 0:
		return
	_filling = true
	_fill_used = {}
	# Host darf freie Plaetze ueber sein Pick-Limit fuellen (vor den Adds setzen).
	Lobby.tour_autofill_done()
	var r := _range()
	var cands: Array = []
	for ms in library.mapsets:
		var fname: String = ms.osz_path.get_file()
		var sid := set_id_of(fname)
		for i in ms.difficulty_count():
			if int(ms.meta_at(i).get("mode", 0)) != 3:
				continue
			var st: float = ms.stars_at(i)
			if st < r.x - 0.0001 or st > r.y + 0.0001:
				continue
			if sid > 0 and _in_pool_key(sid, ms.version_name_at(i)):
				continue
			cands.append({"set_id": sid, "file": fname, "version": ms.version_name_at(i),
				"title": ms.title, "artist": ms.artist, "stars": st, "online": false})
	cands.shuffle()
	for m in t.pool:
		_fill_used[int(m.get("set_id", 0))] = true
	for c in cands:
		if _fill_need <= 0:
			break
		var sid: int = c.set_id
		if sid > 0 and _fill_used.has(sid):
			continue
		if sid > 0:
			_fill_used[sid] = true
		Lobby.tour_add_map(c)
		_fill_need -= 1
	if _fill_need <= 0 or _mirror == null:
		_finish_fill()
		return
	_fill_status = "Suche online …"
	if _status != null:
		_status.text = _fill_status
	_fill_pages = 0
	_mirror.search_done.connect(_on_fill_page)
	_mirror.search_failed.connect(_on_fill_failed)
	_mirror.search("", (randi() % 3) * BeatmapMirror.PAGE_SIZE + BeatmapMirror.PAGE_SIZE * 0,
		BeatmapMirror.Sort.PLAYS)


func _on_fill_page(results: Array, raw_count: int, offset: int) -> void:
	var r := _range()
	results = results.duplicate()
	results.shuffle()
	for res in results:
		if _fill_need <= 0:
			break
		var sid := int(res.id)
		if _fill_used.has(sid) or _index.has("s:%d" % sid):
			continue
		if not BeatmapMirror.passes_filters(res, r.x, r.y + 0.0001):
			continue
		var opts: Array = []
		for sv in res.star_list:
			if float(sv) >= r.x - 0.0001 and float(sv) <= r.y + 0.0001:
				opts.append(float(sv))
		if opts.is_empty():
			continue
		opts.sort()
		_fill_used[sid] = true
		Lobby.tour_add_map({"set_id": sid, "file": "mirror_%d.osz" % sid, "version": "", "title": str(res.title),
			"artist": str(res.artist), "stars": opts.back(), "online": true})
		_fill_need -= 1
	_fill_pages += 1
	if _fill_need <= 0 or raw_count < BeatmapMirror.PAGE_SIZE or _fill_pages >= MAX_ONLINE_PAGES:
		_finish_fill()
		return
	get_tree().create_timer(0.45, true).timeout.connect(func():
		if _filling:
			_mirror.search("", offset + BeatmapMirror.PAGE_SIZE, BeatmapMirror.Sort.PLAYS))


func _on_fill_failed(message: String) -> void:
	_fill_status = "Online-Suche fehlgeschlagen: " + message
	_finish_fill()


func _finish_fill() -> void:
	if _mirror != null:
		if _mirror.search_done.is_connected(_on_fill_page):
			_mirror.search_done.disconnect(_on_fill_page)
		if _mirror.search_failed.is_connected(_on_fill_failed):
			_mirror.search_failed.disconnect(_on_fill_failed)
	_filling = false
	if _fill_need > 0 and not _fill_status.begins_with("Online-Suche fehlgeschlagen"):
		_fill_status = "Nicht genug passende Maps gefunden."
	elif _fill_need <= 0:
		_fill_status = ""
	refresh()
