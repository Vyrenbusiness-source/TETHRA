class_name TournamentPanel
extends Control

## Turnier-Oberflaeche im Multiplayer-Raum: je Phase eine Ansicht.
##  PICK     Pool-Raster + Seitenleiste (Fortschritt je Spieler, Auto-Auswahl)
##  BAN      jeder streicht eine Hass-Map (verdeckt), danach ruhiges Aufdecken
##  PLAY     Map der Runde gross mit Cover, wer bereit ist / laedt, Countdown
##  BETWEEN  Rundenergebnis mit Sieger und Punkte-Delta, Gesamtwertung, naechste Map
## Der Zustand kommt aus Lobby.tournament (Tournament.to_dict-Sync). Fehlende
## Maps des Pools laedt jeder Client selbst ueber den BeatmapMirror.
## Stil wie Song-Browser/Lobby: neutrale Glasflaechen, Farbe nur fuer Bedeutung,
## Versalien gesperrt nur fuer kleine Ueberschriften und Primaer-Buttons.

signal back_to_room
signal end_requested

const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const GOOD := UiTheme.GOOD
## Gedaempfte Bedeutungsfarben (wie mp_lobby): bereit, gestrichen, Sieger.
const READY := Color(0.47, 0.85, 0.60)
const WARN := Color(0.96, 0.47, 0.52)
const GOLD := Color(0.95, 0.79, 0.38)
const SILVER := Color(0.78, 0.82, 0.9)
const BRONZE := Color(0.85, 0.58, 0.40)
const LINE := Color(1, 1, 1, 0.08)
const CARD := Color(0.08, 0.08, 0.11, 0.94)
const COVER_H := 112
const SIDE_W := 300
const MAX_ONLINE_PAGES := 8
## Schrift: 4 Groessen wie die Lobby (+ grosse Zahlen).
const FS_S := 13
const FS_M := 15
const FS_L := 20
const FS_XL := 26

var library: MapLibrary
## Zustand (live aus Lobby, im Harness gesetzt).
var t: Tournament = null
var names: Dictionary = {}
var my_id := 1
var is_host := false
var harness := false
## Raumname fuer die Kopfzeile ("" = nur "Turnier").
var room_title := ""
## Harness: Spieler-Zustand statt Lobby.players ({id: {name, ready, dl}}) und Countdown.
var fake_players: Dictionary = {}
var fake_auto_left := -1.0
## Platz fuer die PlayerStatsCard (kommt spaeter): leerer Container im Zwischenstand.
var stats_slot: VBoxContainer = null

var _mirror: BeatmapMirror
var _body: VBoxContainer
var _index: Dictionary = {}
var _dl_fail: Dictionary = {}
var _prog: Dictionary = {}
var _strikes: Array = []
var _reveal_played := false
var _reveal_fx: Array = []
var _picker: MapPicker = null
var _online: OnlineBrowser = null
var _filling := false
var _fill_status := ""
var _fill_used: Dictionary = {}
var _fill_pages := 0
var _fill_need := 0
var _fill_later: Array = []
var _fill_unknown := 0
var _fill_req: HTTPRequest = null
var _fill_sorted := true
var _fill_failed := false
var _status: Label = null
var _cancel_armed := false
## Countdown des Turnier-Autoablaufs (nur Host).
var _auto_lbl: Label = null
var _auto_big: Label = null
var _cover_wait: Dictionary = {}
var _backfill_started := false
# Song-Vorschau (Bibliothek, Online-Browser, Pool-Karten)
var _preview: AudioStreamPlayer
## Gemeinsamer Vorschau-Player der Lobby (genau eine Musikquelle); null = eigener.
var shared_preview: AudioStreamPlayer = null
var _preview_req: HTTPRequest
var _preview_key := ""
static var _grad_tex: GradientTexture2D = null


class _Strike extends Control:
	var p := 0.0:
		set(v):
			p = v
			queue_redraw()

	func _draw() -> void:
		if p <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.05, 0.5 * p))
		var a := Vector2(size.x * 0.08, size.y * 0.82)
		var b := Vector2(size.x * 0.92, size.y * 0.18)
		draw_line(a, a.lerp(b, p), Color(0.96, 0.47, 0.52, 0.85), 3.0, true)


func _init(lib: MapLibrary) -> void:
	library = lib
	name = "TournamentPanel"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if shared_preview != null and is_instance_valid(shared_preview):
		_preview = shared_preview
		_preview.stop()
	else:
		_preview = AudioStreamPlayer.new()
		_preview.bus = "Music"
		add_child(_preview)
	_mirror = get_node_or_null("/root/Mirror") as BeatmapMirror
	if _mirror != null:
		_mirror.download_progress.connect(_on_dl_progress)
		_mirror.download_done.connect(_on_dl_done)
		_mirror.download_failed.connect(_on_dl_failed)
		_mirror.cover_ready.connect(_on_cover_ready)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.01, 0.03, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var small := get_viewport_rect().size.y < 900.0
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24 if small else 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16 if small else 28)
	add_child(margin)
	var panel := PanelContainer.new()
	var sb := UiTheme.glass_box(18, 0.9, 0.10)
	sb.set_content_margin_all(20 if small else 28)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12 if small else 16)
	panel.add_child(_body)
	_rebuild_index()
	# Alte Bibliotheks-Eintraege ohne Long-Note-/BPM-Werte im Hintergrund ergaenzen (Filter).
	if not harness and library != null and not library.sv_pending.is_empty() and not library.sv_backfill_running():
		_backfill_started = true
		library.start_sv_backfill(func():
			if is_instance_valid(self):
				_rebuild_index())
	refresh()


func _exit_tree() -> void:
	if _backfill_started and library != null and library.sv_backfill_running():
		library.shutdown()
	_finish_fill_quiet()


## Zustand aus der Lobby uebernehmen und neu zeichnen.
func sync_from_lobby() -> void:
	t = Lobby.tour_view()
	names = {}
	for id in Lobby.players:
		names[int(id)] = str(Lobby.players[id].get("name", "?"))
	my_id = multiplayer.get_unique_id()
	is_host = Lobby.is_host
	room_title = Lobby.room_name
	refresh()


# ---------------------------------------------------------------------------
# Hilfen (auch vom Endbild und vom Erstell-Dialog genutzt)
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


## Label fuer Namen/Titel: nie uebersetzen (ein Spieler "Bereit" bleibt "Bereit").
static func raw(text: String, size: int, col: Color = TEXT, heading: bool = false, spacing: int = 0) -> Label:
	var l := lbl(text, size, col, heading, spacing)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Kleine Versal-Ueberschrift (sparsam: eine je Bereich).
static func overline(text: String, col: Color = DIM) -> Label:
	return lbl(text, 12, col, true, 3)


static func chip(text: String, col: Color, size: int = 12) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.12)
	sb.border_color = Color(col.r, col.g, col.b, 0.42)
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


## Neutraler Info-Chip wie im Song-Browser ("★ 2,26", "242 BPM", "02:19").
static func meta_chip(text: String, col: Color = TEXT, size: int = 13) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(1, 1, 1, 0.11)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl(text, size, col))
	return p


## Segment-Knopf (Auswahl aus wenigen Werten): gewaehlt = Akzent-Rand + Toenung.
static func seg_button(text: String, on: bool, w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 38)
	b.set_pressed_no_signal(on)
	style_seg(b)
	UiTheme._attach_sounds(b)
	return b


static func style_seg(b: Button) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(1)
		sb.border_color = border
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		return sb
	b.add_theme_stylebox_override("normal", mk.call(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", mk.call(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.24)))
	b.add_theme_stylebox_override("pressed", mk.call(Color(ACCENT, 0.16), Color(ACCENT, 0.75)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(ACCENT, 0.22), Color(ACCENT, 0.9)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 14)
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(k, TEXT)
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ACCENT.lightened(0.25))


## Runder Avatar mit Anfangsbuchstabe (wie mp_lobby._avatar).
static func avatar(pname: String, sz: int = 28) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(pname.hash() % 360) / 360.0, 0.40, 0.58)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.08, 0.09, 0.14, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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


func _name_cell(peer: int, pname: String, sz: int = 28, fs: int = FS_M) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(avatar(pname, sz))
	var l := raw(pname, fs)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if peer == my_id:
		var you := lbl(tr("(du)"), FS_S, DIM)
		you.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		h.add_child(you)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sp)
	return h


func _pname(peer: int) -> String:
	if names.has(peer):
		return str(names[peer])
	if t != null and t.player_names.has(peer):
		return str(t.player_names[peer])
	return "?"


static func stars_text(s: float) -> String:
	return "★ " + UiTheme.fmt_num(s, 2)


static func time_text(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


func star_range_text() -> String:
	var lo := float(t.config.get("stars_lo", 0.0))
	var hi := float(t.config.get("stars_hi", 99.0))
	return "★ %s–%s" % [UiTheme.fmt_num(lo, 1 if is_equal_approx(snappedf(lo, 0.1), lo) else 2),
		UiTheme.fmt_num(hi, 1 if is_equal_approx(snappedf(hi, 0.1), hi) else 2)]


func mods_text() -> String:
	var parts: Array[String] = []
	var mods: Dictionary = t.config.get("mods", {})
	for k in ["SV", "NF"]:
		if bool(mods.get(k, false)):
			parts.append(k)
	return tr("Mods: %s") % (" + ".join(parts) if not parts.is_empty() else tr("keine"))


## Kurze Beschreibung der Auto-Auswahl-Filter (leer = keine Filter).
static func filter_parts(f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match Tournament.ln_preset(f):
		"few": out.append(TranslationServer.translate("Wenig Long Notes"))
		"mid": out.append(TranslationServer.translate("Mittel viele Long Notes"))
		"many": out.append(TranslationServer.translate("Viele Long Notes"))
		"any": pass
		_: out.append(TranslationServer.translate("%d–%d %% Long Notes") % [int(f.ln_lo), int(f.ln_hi)])
	if int(f.get("len_max", 0)) > 0:
		out.append(TranslationServer.translate("bis %s min") % time_text(int(f.len_max)))
	var blo := int(f.get("bpm_lo", 0))
	var bhi := int(f.get("bpm_hi", 0))
	if blo > 0 and bhi > 0:
		out.append("%d–%d BPM" % [blo, bhi])
	elif blo > 0:
		out.append(TranslationServer.translate("ab %d BPM") % blo)
	elif bhi > 0:
		out.append(TranslationServer.translate("bis %d BPM") % bhi)
	return out


func _filters() -> Dictionary:
	return t.config.get("filters", Tournament.clean_filters({}))


## Kennwerte einer Pool-Map: aus dem Pool-Eintrag, sonst aus der lokalen Bibliothek.
func map_stats(m: Dictionary) -> Dictionary:
	var out := { "ln": int(m.get("ln", -1)), "len_s": int(m.get("len_s", -1)), "bpm": int(m.get("bpm", -1)) }
	var ms := local_set(m)
	if ms != null:
		var di := _diff_index(ms, str(m.get("version", "")))
		var st := ms.stats_at(di)
		for k in out:
			if int(out[k]) < 0:
				out[k] = int(st[k])
	return out


static func _diff_index(ms: MapSet, version: String) -> int:
	for i in ms.difficulty_count():
		if ms.version_name_at(i) == version:
			return i
	return maxi(ms.difficulty_count() - 1, 0)


func _stats_line(m: Dictionary) -> String:
	var st := map_stats(m)
	var parts: Array[String] = []
	if int(st.len_s) > 0:
		parts.append(time_text(int(st.len_s)))
	if int(st.bpm) > 0:
		parts.append("%d BPM" % int(st.bpm))
	if int(st.ln) >= 0:
		parts.append(tr("%d %% LN") % int(st.ln))
	return "  ·  ".join(parts)


# ---------------------------------------------------------------------------
# Lokale Maps + Downloads + Cover
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


## Cover-Bild in einen Rahmen; fehlt es (Online-Map), wird es nachgeladen.
func _cover_rect(m: Dictionary, parent: Control) -> TextureRect:
	# Platzhalter hinter dem Cover (Online-Map, Cover laedt noch).
	var ph := lbl("♪", 34, Color(1, 1, 1, 0.14))
	ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(ph)
	var tr := TextureRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.texture = _cover_for(m)
	parent.add_child(tr)
	var sid := int(m.get("set_id", 0))
	if tr.texture == null and sid > 0 and _mirror != null and not harness:
		if not _cover_wait.has(sid):
			_cover_wait[sid] = []
		_cover_wait[sid].append(tr)
		_mirror.fetch_cover(sid, "https://assets.ppy.sh/beatmaps/%d/covers/card@2x.jpg" % sid)
	return tr


func _on_cover_ready(sid: int, tex: Texture2D) -> void:
	if not _cover_wait.has(sid):
		return
	for n in _cover_wait[sid]:
		if is_instance_valid(n):
			(n as TextureRect).texture = tex
	_cover_wait.erase(sid)


## Dunkler Verlauf am unteren Cover-Rand (Lesbarkeit von Knoepfen/Text).
static func _shade_rect(from_a: float = 0.0, to_a: float = 0.75) -> TextureRect:
	if _grad_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.03, 0.05, 0.0))
		g.set_color(1, Color(0.03, 0.03, 0.05, 1.0))
		_grad_tex = GradientTexture2D.new()
		_grad_tex.gradient = g
		_grad_tex.fill_from = Vector2(0, 0.25)
		_grad_tex.fill_to = Vector2(0, 1)
		_grad_tex.width = 4
		_grad_tex.height = 64
	var r := TextureRect.new()
	r.texture = _grad_tex
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.modulate = Color(1, 1, 1, to_a)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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
			(pair[1] as Label).text = tr("lädt… %s %%") % UiTheme.fmt_score(int(ratio * 100.0))


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


## Spieler im Raum: [{id, name, ready}] (Harness: fake_players).
func _players_view() -> Array:
	var out: Array = []
	var src: Dictionary = fake_players if harness else Lobby.players
	var ids: Array = src.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = src[id]
		out.append({ "id": int(id), "name": str(p.get("name", _pname(int(id)))),
			"ready": bool(p.get("ready", false)), "dl": float(p.get("dl", -1.0)) })
	return out


func _auto_left() -> float:
	return fake_auto_left if harness else Lobby.tour_auto_left()


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
	_reveal_fx = []
	_status = null
	_auto_lbl = null
	_auto_big = null
	stats_slot = null
	_cover_wait = {}
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
		Tournament.Phase.PLAY:
			_build_play()
		_:
			_build_between()
	_play_strikes()


func _small() -> bool:
	return get_viewport_rect().size.y < 900.0


## Kopfzeile: Kontext (klein), Phasen-Titel (gross), Turnier-Eckdaten, Schritte, Schliessen.
func _header(title: String, step: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var ctx := tr("TURNIER")
	if room_title != "":
		ctx += "  ·  " + room_title.to_upper()
	var cl := lbl(ctx, 12, ACCENT, true, 3)
	cl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(cl)
	var tl := lbl(title, FS_XL, TEXT, true, 1)
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(tl)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	col.add_child(meta)
	meta.add_child(meta_chip(tr("%d Maps") % int(t.config.get("maps", 10)), DIM, 12))
	meta.add_child(meta_chip(star_range_text(), DIM, 12))
	meta.add_child(meta_chip(mods_text(), DIM, 12))
	for p in filter_parts(_filters()):
		var c := meta_chip(p, DIM, 12)
		c.tooltip_text = tr("Filter der Auto-Auswahl")
		c.mouse_filter = Control.MOUSE_FILTER_PASS
		meta.add_child(c)
	row.add_child(_stepper(step))
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = tr("Zurück zum Raum — das Turnier läuft weiter")
	close.custom_minimum_size = Vector2(40, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.focus_mode = Control.FOCUS_NONE
	UiTheme.style_ghost_button(close, 10)
	close.pressed.connect(func(): back_to_room.emit())
	row.add_child(close)
	_body.add_child(_hline())


## Schritte "Maps wählen — Bans — Runden": erledigt = ✓, aktuell = Akzent.
func _stepper(step: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var steps := [tr("Maps wählen"), tr("Bans"), tr("Runden")]
	for i in steps.size():
		if i > 0:
			var ln := ColorRect.new()
			ln.custom_minimum_size = Vector2(28, 1)
			ln.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ln.color = Color(ACCENT, 0.45) if i <= step else Color(1, 1, 1, 0.12)
			ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(ln)
		var done := i < step
		var on := i == step
		var dot := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(13)
		sb.set_border_width_all(1)
		sb.bg_color = Color(ACCENT, 0.18) if on else Color(1, 1, 1, 0.03)
		sb.border_color = Color(ACCENT, 0.8) if on else (Color(ACCENT, 0.35) if done else Color(1, 1, 1, 0.14))
		dot.add_theme_stylebox_override("panel", sb)
		dot.custom_minimum_size = Vector2(26, 26)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dl := lbl("✓" if done else str(i + 1), 12, ACCENT if (on or done) else DIM)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_child(dl)
		h.add_child(dot)
		var sl := lbl(steps[i], FS_S, TEXT if on else (DIM if done else Color(DIM, 0.6)))
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		h.add_child(sl)
	return h


static func _hline() -> Control:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = LINE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Hauptzeile unter der Kopfzeile: Inhalt links, Seitenleiste rechts.
func _main_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)
	return row


func _side(row: HBoxContainer, w: int = SIDE_W) -> VBoxContainer:
	var side := PanelContainer.new()
	var sb := UiTheme.glass_box(14, 0.42, 0.08)
	sb.shadow_size = 0
	sb.set_content_margin_all(16)
	side.add_theme_stylebox_override("panel", sb)
	side.custom_minimum_size = Vector2(w, 0)
	row.add_child(side)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func _cols(reserved: float) -> int:
	var w := get_viewport_rect().size.x - 2.0 * (24.0 if _small() else 40.0) - 56.0 - reserved
	return clampi(int(w / 250.0), 2, 5)


func _scroll_grid(parent: Control, cols: int) -> GridContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	return g


## Fusszeile: Trennlinie, links Status, rechts Aktionen.
func _bar() -> HBoxContainer:
	_body.add_child(_hline())
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.custom_minimum_size.y = 46
	_body.add_child(bar)
	return bar


func _btn(text: String, primary: bool, w: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 44)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		UiTheme.style_button(b, true)
	else:
		UiTheme.style_ghost_button(b, 12)
	b.pressed.connect(cb)
	return b


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _bar_text(text: String, col: Color = DIM) -> Label:
	var l := lbl(text, FS_S + 1, col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 80
	return l


## Host: Turnier abbrechen in zwei Schritten (versehentlicher Klick beendet nichts).
func _cancel_btn() -> Button:
	var b := _btn(tr("Turnier abbrechen") if not _cancel_armed else tr("Wirklich abbrechen?"), false, 0, func(): pass)
	b.add_theme_color_override("font_color", WARN if _cancel_armed else DIM)
	b.add_theme_color_override("font_hover_color", WARN)
	b.pressed.connect(func():
		if not _cancel_armed:
			_cancel_armed = true
			refresh()
			get_tree().create_timer(4.0).timeout.connect(func():
				if is_instance_valid(self) and _cancel_armed:
					_cancel_armed = false
					refresh())
			return
		_cancel_armed = false
		if not harness:
			Lobby.tour_cancel()
		back_to_room.emit())
	return b


## Fortschrittsbalken (duenn, ruhig).
static func thin_bar(ratio: float, col: Color = ACCENT, w: int = 0, h: int = 4) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = 1.0
	pb.value = clampf(ratio, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(w, h)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.07)
	bg.set_corner_radius_all(h)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(col, 0.85)
	fg.set_corner_radius_all(h)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


# --- PICK -------------------------------------------------------------------

func _build_pick() -> void:
	var want := int(t.config.get("maps", 10))
	_header(tr("Maps wählen"), 0)
	var row := _main_row()
	var g := _scroll_grid(row, _cols(SIDE_W + 20))
	var mine := t.picks_of(my_id)
	var can_add: bool = t.pool.size() < want and (mine < t.max_per_player() or (is_host and t.autofill_done))
	for i in want:
		if i < t.pool.size():
			g.add_child(_card(i, t.pool[i], "pick"))
		else:
			g.add_child(_empty_slot(i, can_add))
	# Seitenleiste: Pool-Fortschritt, Fortschritt je Spieler, Auto-Auswahl.
	var side := _side(row)
	var top := HBoxContainer.new()
	side.add_child(top)
	var big := lbl("%d" % t.pool.size(), 34, TEXT, true, 0)
	top.add_child(big)
	var of := lbl(" / %d" % want, FS_L, DIM, true, 0)
	of.size_flags_vertical = Control.SIZE_SHRINK_END
	of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(of)
	var full: bool = t.pool.size() >= want
	var st := lbl(tr("Pool voll") if full else tr("Maps im Pool"), FS_S, READY if full else DIM)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(st)
	side.add_child(thin_bar(float(t.pool.size()) / float(maxi(want, 1)), READY if full else ACCENT))
	side.add_child(_gap(6))
	side.add_child(overline(tr("SPIELER")))
	var limit := t.max_per_player()
	for p in _players_view():
		var pid := int(p.id)
		var n := t.picks_of(pid)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var nc := _name_cell(pid, str(p.name), 24, FS_S + 1)
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nc)
		var cnt := lbl("%d / %d" % [n, limit], FS_S, READY if n >= limit else DIM)
		cnt.custom_minimum_size.x = 40
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(cnt)
		side.add_child(h)
		side.add_child(thin_bar(float(n) / float(maxi(limit, 1)), READY if n >= limit else Color(DIM, 0.8), 0, 3))
	side.add_child(_gap(6))
	side.add_child(overline(tr("AUTO-AUSWAHL")))
	var parts := filter_parts(_filters())
	var fl := lbl(tr("Keine Filter — alle Maps im Sternbereich.") if parts.is_empty() else "  ·  ".join(parts), FS_S, TEXT if not parts.is_empty() else DIM)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(fl)
	var hint := lbl(tr("»Rest automatisch füllen« nimmt zuerst passende Maps aus deiner Bibliothek, dann online.")
		if is_host else tr("Der Host kann freie Plätze automatisch füllen."), 12, Color(DIM, 0.85))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(hint)
	_status = lbl(_fill_status, 12, ACCENT if _filling else DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = _fill_status != ""
	side.add_child(_status)

	var bar := _bar()
	if is_host:
		bar.add_child(_cancel_btn())
	var left := tr("Jeder wählt bis zu %d Maps — auch aus dem Online-Browser.") % limit
	if mine >= limit and not full:
		left = tr("Deine Maps sind gewählt — warte auf die anderen.")
	bar.add_child(_bar_text(left))
	var b1 := _btn(tr("Aus Bibliothek"), false, 0, _open_library)
	b1.disabled = not can_add
	bar.add_child(b1)
	var b2 := _btn(tr("Aus Online-Browser"), false, 0, _open_online)
	b2.disabled = not can_add
	bar.add_child(b2)
	if is_host:
		var b3 := _btn(tr("Suche läuft …") if _filling else tr("Rest automatisch füllen"), false, 0, _autofill)
		b3.disabled = full or _filling
		bar.add_child(b3)
		var b4 := _btn("Weiter zu Bans", true, 200, func():
			if not harness:
				Lobby.tour_start_bans())
		b4.disabled = not (full or (t.autofill_done and t.pool.size() >= 2))
		if b4.disabled:
			b4.tooltip_text = tr("Erst wenn der Pool voll ist.")
		bar.add_child(b4)


static func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _card_style(border: Color = Color(1, 1, 1, 0.09), width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.anti_aliasing = true
	return sb


func _empty_slot(i: int, clickable: bool) -> Control:
	var c := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.015)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.07)
	c.add_theme_stylebox_override("panel", sb)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(0, COVER_H + 84)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var n := lbl("%02d" % (i + 1), 28, Color(DIM, 0.32), true, 1)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var l := lbl(tr("+ Map hinzufügen") if clickable else tr("frei"), FS_S, Color(DIM, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if clickable:
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.tooltip_text = tr("Map aus der Bibliothek wählen")
		c.mouse_entered.connect(func():
			sb.border_color = Color(ACCENT, 0.35)
			l.add_theme_color_override("font_color", ACCENT))
		c.mouse_exited.connect(func():
			sb.border_color = Color(1, 1, 1, 0.07)
			l.add_theme_color_override("font_color", Color(DIM, 0.7)))
		c.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_library())
	return c


## Cover-Karte. mode: "pick" | "ban" | "plain".
func _card(i: int, m: Dictionary, mode: String, banned: bool = false) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.clip_contents = true
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(0, COVER_H)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color.from_hsv(float(str(m.get("title", "")).hash() % 360) / 360.0, 0.25, 0.22)
	hb.corner_radius_top_left = 11
	hb.corner_radius_top_right = 11
	holder.add_theme_stylebox_override("panel", hb)
	holder.clip_contents = true
	v.add_child(holder)
	var cover := _cover_rect(m, holder)
	holder.add_child(_shade_rect())
	var stars := float(m.get("stars", 0.0))
	var sc := OnlineBrowser.star_color(stars)
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.03, 0.03, 0.05, 0.72)
	psb.border_color = Color(sc, 0.7)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(20)
	psb.content_margin_left = 8
	psb.content_margin_right = 8
	psb.content_margin_top = 1
	psb.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", psb)
	pill.position = Vector2(10, 10)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl(stars_text(stars), 12, sc.lightened(0.25)))
	holder.add_child(pill)
	var num := lbl("%02d" % (i + 1), 12, Color(1, 1, 1, 0.7), true, 1)
	num.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	num.offset_left = -40
	num.offset_top = -26
	num.offset_right = -10
	num.offset_bottom = -6
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(num)
	if mode == "pick" and (int(m.get("by", -1)) == my_id or is_host):
		var x := Button.new()
		x.text = "✕"
		x.tooltip_text = tr("Aus dem Pool entfernen")
		x.focus_mode = Control.FOCUS_NONE
		x.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		x.offset_left = -36
		x.offset_top = 8
		x.offset_right = -8
		x.offset_bottom = 36
		UiTheme.style_ghost_button(x, 10)
		var idx := i
		x.pressed.connect(func():
			if not harness:
				Lobby.tour_remove_map(idx))
		holder.add_child(x)
	# Reinhoeren: lokal ab PreviewTime, sonst die osu!-Vorschau (b.ppy.sh).
	var play := Button.new()
	play.text = "▶"
	play.tooltip_text = tr("Reinhören")
	play.focus_mode = Control.FOCUS_NONE
	play.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	play.offset_left = 8
	play.offset_top = -36
	play.offset_right = 36
	play.offset_bottom = -8
	UiTheme.style_ghost_button(play, 10)
	var pm := m
	play.pressed.connect(func(): toggle_preview(pm))
	holder.add_child(play)
	var info := MarginContainer.new()
	for side in ["left", "right"]:
		info.add_theme_constant_override("margin_" + side, 12)
	info.add_theme_constant_override("margin_top", 9)
	info.add_theme_constant_override("margin_bottom", 10)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(col)
	var title := raw(str(m.get("title", "?")), FS_M, TEXT.darkened(0.4) if banned else TEXT, true, 0)
	col.add_child(title)
	var ver := str(m.get("version", ""))
	var sub := raw("%s%s" % [str(m.get("artist", "")), ("  ·  " + ver) if ver != "" else ""], 12, DIM)
	col.add_child(sub)
	var stl := _stats_line(m)
	var stats := raw(stl if stl != "" else " ", 12, Color(DIM, 0.8))
	col.add_child(stats)
	col.add_child(_gap(4))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	var by := int(m.get("by", -1))
	if by >= 0:
		foot.add_child(avatar(_pname(by), 18))
		var who := raw(_pname(by), 12, TEXT.darkened(0.15))
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.tooltip_text = tr("gewählt von %s") % _pname(by)
		who.mouse_filter = Control.MOUSE_FILTER_PASS
		foot.add_child(who)
	else:
		foot.add_child(_spacer())
	if banned:
		var bl := lbl(tr("gestrichen · %s") % _banners(i), 12, WARN)
		bl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		bl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		foot.add_child(bl)
		_decorate_ban(holder, card, cover)
	else:
		foot.add_child(_status_chip(m))
	return card


## Status einer Pool-Map: "✓ bereit", "lädt… 42 %" mit Balken, oder Fehler.
func _status_chip(m: Dictionary) -> Control:
	if local_set(m) != null:
		var ok := lbl(tr("✓ bereit"), 12, READY)
		ok.tooltip_text = tr("Map ist bei dir vorhanden")
		return ok
	var sid := int(m.get("set_id", 0))
	if sid <= 0:
		return lbl(tr("fehlt"), 12, WARN)
	if _dl_fail.has(sid):
		var fl := lbl(tr("Fehler beim Laden"), 12, WARN)
		fl.tooltip_text = str(_dl_fail[sid])
		fl.mouse_filter = Control.MOUSE_FILTER_PASS
		return fl
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ratio := _mirror.active_ratio(sid) if _mirror != null else 0.0
	var bar := thin_bar(maxf(ratio, 0.0), ACCENT, 40, 4)
	h.add_child(bar)
	var l := lbl(tr("lädt… %s %%") % UiTheme.fmt_score(int(maxf(ratio, 0.0) * 100.0)) if ratio > 0.0 else tr("lädt…"), 12, ACCENT)
	h.add_child(l)
	if not _prog.has(sid):
		_prog[sid] = []
	_prog[sid].append([bar, l])
	return h


# --- BAN --------------------------------------------------------------------

func _voters() -> Array:
	var ids: Array = []
	for p in _players_view():
		ids.append(int(p.id))
	if ids.is_empty():
		ids = names.keys()
		ids.sort()
	return ids


func _has_voted(peer: int) -> bool:
	return t.has_voted(peer)


func _all_voted() -> bool:
	if t.hidden:
		return false
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
	_header(tr("Bans") if not revealed else tr("Bans aufgedeckt"), 1)
	var row := _main_row()
	var g := _scroll_grid(row, _cols(SIDE_W + 20))
	var banned := _banned_set() if revealed else {}
	var mine := int(t.bans.get(my_id, -1))
	var skipped := t.bans.has(my_id) and mine < 0
	for i in t.pool.size():
		var c := _card(i, t.pool[i], "ban", banned.has(i) and revealed)
		g.add_child(c)
		if not revealed:
			_ban_interaction(c, i, mine == i)
	# Seitenleiste: wer hat gewaehlt, nach dem Aufdecken wer was gestrichen hat + Reihenfolge.
	var side := _side(row)
	var ids := _voters()
	var n_voted := 0
	for p in ids:
		if _has_voted(int(p)):
			n_voted += 1
	var top := HBoxContainer.new()
	side.add_child(top)
	top.add_child(lbl("%d" % n_voted, 34, TEXT, true, 0))
	var of := lbl(" / %d" % ids.size(), FS_L, DIM, true, 0)
	of.size_flags_vertical = Control.SIZE_SHRINK_END
	of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(of)
	var stl := lbl(tr("haben gewählt"), FS_S, READY if n_voted >= ids.size() else DIM)
	stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stl)
	side.add_child(thin_bar(float(n_voted) / float(maxi(ids.size(), 1)), READY if n_voted >= ids.size() else ACCENT))
	side.add_child(_gap(6))
	side.add_child(overline(tr("ABSTIMMUNG")))
	var reveal_rows: Array = []
	for p in ids:
		var pid := int(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var nc := _name_cell(pid, _pname(pid), 24, FS_S + 1)
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nc)
		var status: Label
		if revealed and t.bans.has(pid) and int(t.bans[pid]) < 0:
			status = lbl(tr("kein Ban"), 12, DIM)
		elif revealed and int(t.bans.get(pid, -1)) >= 0:
			var bt: String = str(t.pool[int(t.bans[pid])].get("title", "?"))
			status = raw("✕ " + bt, 12, WARN)
			status.custom_minimum_size.x = 120
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			reveal_rows.append(status)
		elif _has_voted(pid):
			status = lbl(tr("✓ gewählt"), 12, READY)
		else:
			status = lbl(tr("wählt …"), 12, Color(DIM, 0.75))
		if pid == my_id and not revealed and (mine >= 0 or skipped):
			status = lbl(tr("kein Ban") if skipped else tr("✓ gewählt"), 12, READY)
		h.add_child(status)
		side.add_child(h)
	if not revealed:
		side.add_child(_gap(4))
		var hl := lbl(tr("Die Bans bleiben verdeckt, bis alle gewählt haben."), 12, Color(DIM, 0.85))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(hl)
	else:
		side.add_child(_gap(6))
		var ord := VBoxContainer.new()
		ord.add_theme_constant_override("separation", 6)
		side.add_child(ord)
		ord.add_child(overline(tr("REIHENFOLGE DER RUNDEN")))
		var order: Array = t.order if not t.order.is_empty() else Array(t.play_order())
		var n := 1
		for pi in order:
			var m: Dictionary = t.pool[int(pi)]
			var oh := HBoxContainer.new()
			oh.add_theme_constant_override("separation", 10)
			var nl := lbl("%d" % n, FS_S, ACCENT, true, 0)
			nl.custom_minimum_size.x = 16
			oh.add_child(nl)
			var ol := raw(str(m.get("title", "?")), FS_S + 1)
			ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			oh.add_child(ol)
			oh.add_child(lbl(stars_text(float(m.get("stars", 0.0))), 12, DIM))
			ord.add_child(oh)
			n += 1
		_reveal_fx.append(ord)
		for r in reveal_rows:
			_reveal_fx.append(r)
	var bar := _bar()
	if is_host:
		bar.add_child(_cancel_btn())
	if not revealed:
		bar.add_child(_bar_text(tr("Deine Wahl ist markiert — du kannst sie ändern, bis alle gewählt haben.")
			if (mine >= 0 or skipped) else tr("Klicke eine Map, um sie abzuwählen — oder wähle Kein Ban.")))
		var sk := Button.new()
		sk.text = tr("✓ Kein Ban") if skipped else tr("Kein Ban")
		sk.name = "SkipBan"
		sk.toggle_mode = true
		sk.set_pressed_no_signal(skipped)
		sk.custom_minimum_size = Vector2(150, 44)
		style_seg(sk)
		sk.pressed.connect(func():
			if not harness:
				Lobby.tour_ban(Tournament.SKIP))
		bar.add_child(sk)
	else:
		bar.add_child(_bar_text(tr("%d Maps werden gespielt — in dieser Reihenfolge.") % t.remaining()))
	if is_host:
		var go := _btn("Turnier starten", true, 220, func():
			if not harness:
				Lobby.tour_begin())
		go.disabled = not revealed
		if not revealed:
			go.tooltip_text = tr("Erst wenn alle gewählt haben.")
		bar.add_child(go)
	elif revealed:
		bar.add_child(lbl(tr("Warte auf den Host …"), FS_S + 1, DIM))


func _ban_interaction(card: Control, i: int, mine: bool) -> void:
	_ignore_mouse(card)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Reinhoeren bleibt klickbar.
	for b in card.find_children("*", "Button", true, false):
		(b as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	var base := _card_style(Color(WARN, 0.85), 2) if mine else _card_style()
	var hover := _card_style(Color(WARN, 0.95) if mine else Color(WARN, 0.45), 2 if mine else 1)
	card.add_theme_stylebox_override("panel", base)
	card.tooltip_text = tr("Dein Ban — klicke eine andere Map, um zu wechseln") if mine else tr("Diese Map streichen")
	if mine:
		var holder: Control = card.get_child(0).get_child(0)
		var tag := chip(tr("Dein Ban"), WARN, 12)
		tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tag.offset_left = -96
		tag.offset_right = -10
		tag.offset_top = 10
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		holder.add_child(tag)
		for c in holder.get_children():
			if c is TextureRect and (c as TextureRect).texture != _grad_tex:
				(c as TextureRect).modulate = Color(0.75, 0.62, 0.64)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not harness:
			Lobby.tour_ban(i))
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", base))


## Vorschau einer Pool-Map an/aus.
func toggle_preview(m: Dictionary) -> void:
	var key := "%s|%s" % [str(m.get("file", "")), int(m.get("set_id", 0))]
	if _preview_key == key and _preview.playing:
		stop_preview()
		return
	_preview_key = key
	var ms := local_set(m)
	if ms != null and ms.difficulty_count() > 0:
		_play_local(ms)
		return
	var sid := int(m.get("set_id", 0))
	if sid <= 0:
		return
	if _preview_req != null:
		_preview_req.queue_free()
	_preview_req = HTTPRequest.new()
	_preview_req.timeout = 10.0
	add_child(_preview_req)
	_preview_req.request_completed.connect(func(res: int, code: int, _h, body: PackedByteArray):
		if res == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 1024 and _preview_key == key:
			var st := AudioStreamMP3.new()
			st.data = body
			_play_stream(st))
	_preview_req.request("https://b.ppy.sh/preview/%d.mp3" % sid,
			["User-Agent: TETHRA"])


func _play_local(ms: MapSet) -> void:
	var meta: Dictionary = ms.meta_at(0)
	var st := OszImporter.load_audio_stream_named(ms.osz_path, str(meta.get("audio_filename", "")))
	if st == null:
		return
	var at := float(meta.get("preview_time", -1.0))
	if at < 0.0:
		at = float(meta.get("duration_ms", 0.0)) * 0.4
	_preview.stream = st
	_preview.volume_db = -14.0
	_preview.play(maxf(at, 0.0) / 1000.0)


func _play_stream(st: AudioStream) -> void:
	_preview.stream = st
	_preview.volume_db = -14.0
	_preview.play()


func stop_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.stop()


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


## Aufgedeckte Ban-Karte: Durchstreich-Overlay auf dem Cover, Karte tritt zurueck.
func _decorate_ban(holder: Control, card: Control, cover: TextureRect) -> void:
	var s := _Strike.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(s)
	_strikes.append([s, card, cover])


## Aufdecken: Bans nacheinander durchstreichen (ruhig, kein Blinken), danach
## blendet die Rundenreihenfolge ein. Nur beim ersten Aufbau animiert.
func _play_strikes() -> void:
	if _strikes.is_empty():
		for c in _reveal_fx:
			(c as CanvasItem).modulate.a = 1.0
		return
	if _reveal_played:
		for e in _strikes:
			_strike_state(e, 1.0)
		return
	_reveal_played = true
	for c in _reveal_fx:
		(c as CanvasItem).modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	for e in _strikes:
		tw.tween_method(func(p: float): _strike_state(e, p), 0.0, 1.0, 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(0.35)
	for c in _reveal_fx:
		tw.tween_property(c, "modulate:a", 1.0, 0.5)


func _strike_state(e: Array, p: float) -> void:
	if not is_instance_valid(e[0]):
		return
	(e[0] as _Strike).p = p
	(e[1] as Control).modulate = Color(1, 1, 1, 1.0 - 0.35 * p)
	if is_instance_valid(e[2]):
		(e[2] as TextureRect).modulate = Color(1, 1, 1).lerp(Color(0.55, 0.55, 0.6), p)


# --- PLAY -------------------------------------------------------------------

func _round_total() -> int:
	return t.order.size() if not t.order.is_empty() else t.remaining()


## Runde steht fest: Map gross, wer bereit ist / laedt, Countdown.
func _build_play() -> void:
	var total := _round_total()
	var rnd := t.current_round + 1
	_header(tr("Runde %d von %d") % [rnd, total], 2)
	var row := _main_row()
	var mi := t.current_map_index()
	var m: Dictionary = t.pool[mi] if mi >= 0 and mi < t.pool.size() else {}
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(_hero(m, rnd, total))
	# Countdown / Wartegrund gross und ruhig unter der Map.
	var cd := HBoxContainer.new()
	cd.add_theme_constant_override("separation", 14)
	left.add_child(cd)
	var pl := _players_view()
	var n_ready := 0
	for p in pl:
		if bool(p.ready):
			n_ready += 1
	_auto_big = lbl("", 34, ACCENT, true, 1)
	_auto_big.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cd.add_child(_auto_big)
	var why := lbl(tr("Alle sind bereit.") if n_ready >= pl.size() and not pl.is_empty()
		else tr("Warte, bis alle die Map haben …"), FS_M, DIM)
	why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cd.add_child(why)
	# Rechts: Spieler (bereit / laedt) + kompakter Stand.
	var side := _side(row, SIDE_W + 40)
	var top := HBoxContainer.new()
	side.add_child(top)
	top.add_child(lbl("%d" % n_ready, 34, TEXT, true, 0))
	var of := lbl(" / %d" % pl.size(), FS_L, DIM, true, 0)
	of.size_flags_vertical = Control.SIZE_SHRINK_END
	of.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(of)
	var rl := lbl(tr("bereit"), FS_S, READY if n_ready >= pl.size() else DIM)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(rl)
	side.add_child(thin_bar(float(n_ready) / float(maxi(pl.size(), 1)), READY if n_ready >= pl.size() else ACCENT))
	side.add_child(_gap(6))
	side.add_child(overline(tr("SPIELER")))
	var sid := int(m.get("set_id", 0))
	for p in pl:
		var pid := int(p.id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var nc := _name_cell(pid, str(p.name), 24, FS_S + 1)
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nc)
		if bool(p.ready):
			h.add_child(lbl(tr("✓ bereit"), 12, READY))
		else:
			var dl := float(p.dl)
			if pid == my_id and _mirror != null and sid > 0 and _mirror.is_downloading(sid):
				dl = maxf(_mirror.active_ratio(sid), 0.0)
			if dl >= 0.0:
				h.add_child(thin_bar(dl, ACCENT, 40, 4))
				h.add_child(lbl(tr("lädt… %s %%") % UiTheme.fmt_score(int(dl * 100.0)), 12, ACCENT))
			else:
				h.add_child(lbl(tr("lädt Map …"), 12, Color(DIM, 0.8)))
		side.add_child(h)
	if not t.rounds.is_empty():
		side.add_child(_gap(6))
		side.add_child(overline(tr("STAND")))
		var stand := t.standings()
		for s in stand.slice(0, mini(stand.size(), 8)):
			side.add_child(_mini_stand(s))
	var bar := _bar()
	if is_host:
		bar.add_child(_cancel_btn())
	var rest := total - rnd
	bar.add_child(_bar_text(tr("Danach noch %d Maps.") % rest if rest > 0 else tr("Letzte Runde.")))
	_auto_lbl = lbl("", FS_S + 1, ACCENT)
	bar.add_child(_auto_lbl)
	var me: Dictionary = {}
	for p in pl:
		if int(p.id) == my_id:
			me = p
	if not bool(me.get("ready", true)):
		bar.add_child(_btn(tr("Bereit"), false, 140, func():
			if not harness:
				Lobby.set_ready(true)))
	if is_host:
		var go := _btn("Runde starten", true, 220, func():
			if not harness:
				Lobby.start_game())
		go.disabled = not harness and not Lobby.can_start()
		if go.disabled:
			go.tooltip_text = tr("Wartet, bis alle die Map haben und bereit sind.")
		bar.add_child(go)
	else:
		bar.add_child(lbl(tr("Der Host startet die Runde."), FS_S + 1, DIM))


## Grosse Map-Karte: Cover mit Verlauf, darueber Runde, Titel, Kennwerte.
func _hero(m: Dictionary, rnd: int, total: int) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.clip_contents = true
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var holder := Control.new()
	holder.clip_contents = true
	holder.custom_minimum_size = Vector2(0, 240 if _small() else 380)
	card.add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color.from_hsv(float(str(m.get("title", "")).hash() % 360) / 360.0, 0.25, 0.18)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	_cover_rect(m, holder)
	holder.add_child(_shade_rect(0.0, 0.95))
	var box := MarginContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "bottom"]:
		box.add_theme_constant_override("margin_" + k, 28)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var ol := overline(tr("RUNDE %d VON %d") % [rnd, total], ACCENT)
	ol.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(ol)
	v.add_child(raw(str(m.get("title", "?")), 34 if not _small() else 28, TEXT, true, 0))
	var ver := str(m.get("version", ""))
	v.add_child(raw("%s%s" % [str(m.get("artist", "")), ("  ·  " + ver) if ver != "" else ""], FS_M + 1, TEXT.darkened(0.15)))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	v.add_child(_gap(2))
	v.add_child(chips)
	var stars := float(m.get("stars", 0.0))
	chips.add_child(meta_chip(stars_text(stars), OnlineBrowser.star_color(stars).lightened(0.25)))
	var st := map_stats(m)
	if int(st.len_s) > 0:
		chips.add_child(meta_chip(time_text(int(st.len_s))))
	if int(st.bpm) > 0:
		chips.add_child(meta_chip("%d BPM" % int(st.bpm)))
	if int(st.ln) >= 0:
		chips.add_child(meta_chip(tr("%d %% LN") % int(st.ln)))
	var by := int(m.get("by", -1))
	if by >= 0:
		chips.add_child(meta_chip(tr("gewählt von %s") % _pname(by), DIM))
	var play := Button.new()
	play.text = "▶  " + tr("Reinhören")
	play.focus_mode = Control.FOCUS_NONE
	play.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	play.offset_left = -150
	play.offset_top = 16
	play.offset_right = -16
	play.offset_bottom = 54
	play.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	UiTheme.style_ghost_button(play, 10)
	var pm := m
	play.pressed.connect(func(): toggle_preview(pm))
	holder.add_child(play)
	return card


func _mini_stand(s: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var rk := int(s.get("rank", 0))
	var rl := lbl("%d." % rk, FS_S, rank_color(rk), true, 0)
	rl.custom_minimum_size.x = 22
	h.add_child(rl)
	var nl := raw(str(s.get("name", "?")), FS_S + 1, TEXT if int(s.get("peer", 0)) != my_id else ACCENT.lightened(0.3))
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	h.add_child(lbl(tr("%d P.") % int(s.get("points", 0)), FS_S, DIM))
	return h


# --- BETWEEN ----------------------------------------------------------------

## Stand vor der letzten Runde (fuer Platz-Bewegung und Punkte-Delta).
func _prev_standings() -> Dictionary:
	var out := {}
	if t.rounds.size() < 2:
		return out
	var prev := Tournament.from_dict(t.to_dict())
	prev.rounds = t.rounds.slice(0, t.rounds.size() - 1)
	for s in prev.standings():
		out[s.peer] = int(s.rank)
	return out


func _build_between() -> void:
	var played: int = t.rounds.size()
	var total := _round_total()
	_header(tr("Zwischenstand nach Runde %d von %d") % [played, total] if played < total
		else tr("Alle Runden gespielt"), 2)
	var row := _main_row()
	row.add_theme_constant_override("separation", 24)
	var last: Dictionary = t.rounds[played - 1] if played > 0 else {}
	var res: Dictionary = last.get("results", {})

	# Links: Ergebnis der letzten Runde mit Sieger.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var mi := int(last.get("map", -1))
	var m: Dictionary = t.pool[mi] if mi >= 0 and mi < t.pool.size() else {}
	var hl := HBoxContainer.new()
	hl.add_theme_constant_override("separation", 10)
	left.add_child(hl)
	var ol := overline(tr("RUNDE %d") % played, ACCENT)
	ol.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hl.add_child(ol)
	var mt := raw(str(m.get("title", "?")), FS_M, TEXT, true, 0)
	mt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.add_child(mt)
	if not m.is_empty():
		hl.add_child(lbl(stars_text(float(m.get("stars", 0.0))), FS_S, DIM))
	var rows: Array = []
	for p in res:
		rows.append([int(p), res[p]])
	rows.sort_custom(func(a, b):
		var pa := int(a[1].get("place", 99)) if int(a[1].get("points", 0)) > 0 else 99
		var pb := int(b[1].get("place", 99)) if int(b[1].get("points", 0)) > 0 else 99
		if pa != pb:
			return pa < pb
		return int(a[1].get("score", 0)) > int(b[1].get("score", 0)))
	if not rows.is_empty():
		left.add_child(_winner_card(rows[0][0], rows[0][1], m))
	var rw := [26, 0, 104, 70, 64, 44]
	left.add_child(_head_row([tr("#"), tr("Spieler"), tr("Score"), tr("Acc"), tr("Combo"), tr("Pkt.")], rw))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(list)
	left.add_child(lsc)
	for e in rows:
		list.add_child(_round_row(int(e[0]), e[1], rw))

	# Rechts: Gesamtwertung mit Bewegung, als Naechstes, Platz fuer Spieler-Statistik.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	row.add_child(right)
	right.add_child(overline(tr("GESAMTWERTUNG"), ACCENT))
	var sw := [30, 0, 30, 70, 50, 74]
	right.add_child(_head_row([tr("#"), tr("Spieler"), "", tr("Punkte"), tr("Siege"), tr("Ø Acc")], sw))
	var prev := _prev_standings()
	var stand_list := VBoxContainer.new()
	stand_list.add_theme_constant_override("separation", 4)
	stand_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ssc := ScrollContainer.new()
	ssc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ssc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ssc.add_child(stand_list)
	right.add_child(ssc)
	for s in t.standings():
		var pid := int(s.get("peer", 0))
		var delta := int(res[pid].get("points", 0)) if res.has(pid) else 0
		var move := (int(prev[pid]) - int(s.rank)) if prev.has(pid) else 0
		stand_list.add_child(_stand_row(s, delta, move, sw))
	stats_slot = VBoxContainer.new()
	stats_slot.name = "StatsSlot"
	stats_slot.add_theme_constant_override("separation", 8)
	right.add_child(stats_slot)
	var remaining: int = total - played
	if remaining > 0 and played < t.order.size():
		right.add_child(_gap(4))
		right.add_child(overline(tr("ALS NÄCHSTES")))
		right.add_child(_next_row(t.pool[int(t.order[played])]))
	var bar := _bar()
	if is_host:
		bar.add_child(_cancel_btn())
	bar.add_child(_bar_text(tr("Noch %d Maps zu spielen.") % remaining if remaining > 0 else tr("Alle Runden gespielt.")))
	_auto_lbl = lbl("", FS_S + 1, ACCENT)
	bar.add_child(_auto_lbl)
	if is_host:
		bar.add_child(_btn("Nächste Map" if remaining > 0 else "Zur Siegerehrung", true, 220, func():
			if not harness:
				Lobby.tour_next()))
	else:
		bar.add_child(lbl(tr("Der Host startet die nächste Runde."), FS_S + 1, DIM))


func _head_row(cells: Array, widths: Array) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	m.add_child(h)
	for i in cells.size():
		var l := lbl(str(cells[i]), 12, Color(DIM, 0.8))
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if int(widths[i]) > 0:
			l.custom_minimum_size.x = widths[i]
			if i > 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	return m


func _row_box(hl: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ACCENT, 0.07) if hl else Color(1, 1, 1, 0.03)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(ACCENT, 0.35) if hl else Color(1, 1, 1, 0.06)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


func _cell(h: HBoxContainer, text: String, w: int, col: Color = TEXT, fs: int = FS_M) -> Label:
	var l := lbl(text, fs, col)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return l


## Rundensieger: Avatar, Name, Score — dezent golden, kein Glitzer.
func _winner_card(pid: int, r: Dictionary, m: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GOLD, 0.06)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(GOLD, 0.30)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	if not m.is_empty():
		var cv := Control.new()
		cv.custom_minimum_size = Vector2(96, 54)
		cv.clip_contents = true
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cv)
		_cover_rect(m, cv)
	var won := int(r.get("points", 0)) > 0
	h.add_child(avatar(str(r.get("name", _pname(pid))), 40))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	v.add_child(overline(tr("RUNDENSIEGER") if won else tr("KEIN SIEGER"), GOLD if won else DIM))
	v.add_child(raw(str(r.get("name", _pname(pid))) + ("  " + tr("(du)") if pid == my_id else ""), FS_L, TEXT, true, 0))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sv)
	var sc := lbl(UiTheme.fmt_score(int(r.get("score", 0))), FS_L, TEXT, true, 0)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sv.add_child(sc)
	var ac := lbl(UiTheme.fmt_pct(float(r.get("accuracy", 0.0)) * 100.0), FS_S, DIM)
	ac.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sv.add_child(ac)
	return p


func _round_row(pid: int, r: Dictionary, w: Array) -> Control:
	var box := _row_box(pid == my_id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var failed := bool(r.get("failed", false))
	var absent := bool(r.get("absent", false))
	var pts := int(r.get("points", 0))
	var place := int(r.get("place", 0))
	var pl := lbl("%d" % place if pts > 0 else "–", FS_M, rank_color(place) if pts > 0 else DIM, true, 0)
	pl.custom_minimum_size.x = w[0]
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(pl)
	var nc := _name_cell(pid, str(r.get("name", _pname(pid))), 24, FS_M)
	nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nc)
	if absent:
		_cell(h, tr("gegangen"), w[2] + w[3] + w[4] + 20, DIM, FS_S)
	else:
		_cell(h, UiTheme.fmt_score(int(r.get("score", 0))), w[2], TEXT if not failed else DIM)
		_cell(h, UiTheme.fmt_pct(float(r.get("accuracy", 0.0)) * 100.0), w[3], DIM, FS_S + 1)
		_cell(h, tr("durchgefallen") if failed and pts == 0 else "%dx" % int(r.get("max_combo", 0)), w[4],
			WARN if failed and pts == 0 else DIM, FS_S)
	_cell(h, "+%d" % pts if pts > 0 else "0", w[5], READY if pts > 0 else DIM, FS_M)
	return box


func _stand_row(s: Dictionary, delta: int, move: int, w: Array) -> Control:
	var pid := int(s.get("peer", 0))
	var box := _row_box(pid == my_id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var rk := int(s.get("rank", 0))
	var rl := lbl("%d" % rk, FS_M, rank_color(rk), true, 0)
	rl.custom_minimum_size.x = w[0]
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rl)
	var nc := _name_cell(pid, str(s.get("name", "?")), 24, FS_M)
	nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nc)
	var mv := _cell(h, ("▲%d" % move) if move > 0 else (("▼%d" % -move) if move < 0 else ""), w[2],
		READY if move > 0 else WARN.darkened(0.1), 12)
	mv.tooltip_text = tr("Plätze seit der letzten Runde")
	var pc := HBoxContainer.new()
	pc.custom_minimum_size.x = w[3]
	pc.alignment = BoxContainer.ALIGNMENT_END
	pc.add_theme_constant_override("separation", 6)
	h.add_child(pc)
	if delta > 0:
		var dl := lbl("+%d" % delta, 12, READY)
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(dl)
	var pl := lbl("%d" % int(s.get("points", 0)), FS_L, TEXT, true, 0)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(pl)
	_cell(h, str(int(s.get("wins", 0))), w[4], DIM)
	_cell(h, UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0), w[5], DIM, FS_S + 1)
	return box


func _process(_delta: float) -> void:
	if t == null:
		return
	var left := _auto_left()
	var txt := ""
	if left >= 0.0:
		txt = (tr("Start in %d s") if t.phase == Tournament.Phase.PLAY else tr("Weiter in %d s")) % ceili(left)
	if _auto_lbl != null and is_instance_valid(_auto_lbl):
		_auto_lbl.text = txt if _auto_big == null else ""
	if _auto_big != null and is_instance_valid(_auto_big):
		_auto_big.text = txt
		_auto_big.visible = txt != ""


func _next_row(m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.clip_contents = true
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var cv := Control.new()
	cv.custom_minimum_size = Vector2(124, 70)
	cv.clip_contents = true
	h.add_child(cv)
	_cover_rect(m, cv)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	v.add_child(raw(str(m.get("title", "?")), FS_M + 1, TEXT, true, 0))
	var stl := _stats_line(m)
	v.add_child(raw("%s  ·  %s%s" % [str(m.get("artist", "")), stars_text(float(m.get("stars", 0.0))),
		("  ·  " + stl) if stl != "" else ""], 12, DIM))
	var stc := _status_chip(m)
	stc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stc)
	h.add_child(_gap(0))
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


## sel_map-Daten einer lokalen Diff inkl. Kennwerte (fuer Pool und Filter).
static func local_data(ms: MapSet, diff: int) -> Dictionary:
	var fname := ms.osz_path.get_file()
	var d := {"set_id": set_id_of(fname), "file": fname,
		"version": ms.version_name_at(diff), "title": ms.title,
		"artist": ms.artist, "stars": ms.stars_at(diff), "online": false}
	var st := ms.stats_at(diff)
	for k in st:
		if int(st[k]) >= 0:
			d[k] = int(st[k])
	return d


func _open_library() -> void:
	if t == null:
		return
	if _picker == null:
		_picker = MapPicker.new(library)
		_picker.visible = false
		add_child(_picker)
		_picker.picked.connect(func(ms: MapSet, diff: int):
			if not harness:
				Lobby.tour_add_map(local_data(ms, diff))
			_picker.close())
		_picker.set_selected.connect(func(ms: MapSet):
			if ms.difficulty_count() > 0:
				_play_local(ms))
		_picker.preview_stream.connect(_play_stream)
		_picker.preview_stop.connect(stop_preview)
		_picker.closed.connect(stop_preview)
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
		_online.preview_stream.connect(_play_stream)
		_online.preview_stop.connect(stop_preview)
	var r := _range()
	_online.pick_lo = r.x
	_online.pick_hi = r.y
	_online.pool_ids = {}
	for m in t.pool:
		_online.pool_ids[int(m.get("set_id", 0))] = true
	_online.open()


## Lokale Kandidaten der Auto-Auswahl: [[rank, data]] (rank siehe Tournament.filter_rank).
static func local_candidates(lib: MapLibrary, lo: float, hi: float, f: Dictionary, skip: Callable) -> Array:
	var out: Array = []
	if lib == null:
		return out
	for ms in lib.mapsets:
		for i in ms.difficulty_count():
			if int(ms.meta_at(i).get("mode", 0)) != 3:
				continue
			var st: float = ms.stars_at(i)
			if st < lo - 0.0001 or st > hi + 0.0001:
				continue
			var d := local_data(ms, i)
			if skip.is_valid() and bool(skip.call(d)):
				continue
			var rank := Tournament.filter_rank(f, ms.stats_at(i))
			if rank >= 0:
				out.append([rank, d])
	return out


## Host: Rest des Pools fuellen — passende lokale Maps, dann online; Maps ohne
## Kennwerte (bei aktiven Filtern) nur, wenn sonst nichts mehr passt.
func _autofill() -> void:
	if t == null or _filling:
		return
	var want := int(t.config.get("maps", 10))
	_fill_need = want - t.pool.size()
	if _fill_need <= 0:
		return
	_filling = true
	_fill_used = {}
	_fill_later = []
	_fill_unknown = 0
	_fill_failed = false
	_fill_status = ""
	# Host darf freie Plaetze ueber sein Pick-Limit fuellen (vor den Adds setzen).
	if not harness:
		Lobby.tour_autofill_done()
	var r := _range()
	var f := _filters()
	for m in t.pool:
		_fill_used[int(m.get("set_id", 0))] = true
	var cands := local_candidates(library, r.x, r.y, f, func(d: Dictionary):
		return int(d.set_id) > 0 and _in_pool_key(int(d.set_id), str(d.version)))
	cands.shuffle()
	for c in cands:
		if int(c[0]) == 0:
			_fill_add(c[1])
		else:
			_fill_later.append(c[1])
	if _fill_need <= 0 or _mirror == null or harness:
		_finish_fill()
		return
	_fill_status = tr("Suche online …")
	refresh()
	_fill_pages = 0
	_fill_sorted = true
	_fill_search((randi() % 3) * BeatmapMirror.PAGE_SIZE)


func _fill_add(d: Dictionary) -> bool:
	if _fill_need <= 0:
		return false
	var sid := int(d.get("set_id", 0))
	if sid > 0 and _fill_used.has(sid):
		return false
	if sid > 0:
		_fill_used[sid] = true
	if not harness:
		Lobby.tour_add_map(d)
	_fill_need -= 1
	return true


## Eigene Suchanfrage: die rohe Mirror-Antwort enthaelt je Diff Long Notes,
## Laenge und BPM (die Browser-Ergebnisse nicht).
func _fill_search(offset: int) -> void:
	if _fill_req == null:
		_fill_req = HTTPRequest.new()
		_fill_req.timeout = 15.0
		add_child(_fill_req)
		_fill_req.request_completed.connect(_on_fill_page)
	_fill_req.set_meta("offset", offset)
	var url := BeatmapMirror.build_search_url("", offset, BeatmapMirror.Sort.PLAYS,
		BeatmapMirror.STATUS_RANKED, _fill_sorted)
	if _fill_req.request(url, BeatmapMirror.headers()) != OK:
		_on_fill_failed(tr("Keine Verbindung zum Mirror."))


func _on_fill_page(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if not _filling:
		return
	var data: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		data = JSON.parse_string(body.get_string_from_utf8())
	var offset := int(_fill_req.get_meta("offset", 0))
	if not (data is Array):
		if _fill_sorted:
			_fill_sorted = false  # sortierender Mirror kaputt -> catboy
			_fill_search(offset)
			return
		_on_fill_failed(tr("Keine Verbindung zum Mirror.") if result != HTTPRequest.RESULT_SUCCESS
			else tr("Der Mirror antwortet nicht (HTTP %d).") % code)
		return
	var r := _range()
	var f := _filters()
	var items: Array = (data as Array).duplicate()
	items.shuffle()
	for item in items:
		if _fill_need <= 0:
			break
		if not (item is Dictionary) or BeatmapMirror.parse_item(item).is_empty():
			continue
		var sid := int(BeatmapMirror._num(item.get("id", 0)))
		if _fill_used.has(sid) or _index.has("s:%d" % sid):
			continue
		var pick := Tournament.online_pick(item, r.x, r.y, f)
		if pick.is_empty():
			continue
		var rank := int(pick.rank)
		pick.erase("rank")
		if rank == 0:
			_fill_add(pick)
		else:
			_fill_later.append(pick)
	_fill_pages += 1
	if _fill_need <= 0 or (data as Array).size() < BeatmapMirror.PAGE_SIZE or _fill_pages >= MAX_ONLINE_PAGES:
		_finish_fill()
		return
	get_tree().create_timer(0.45, true).timeout.connect(func():
		if _filling and is_instance_valid(self):
			_fill_search(offset + BeatmapMirror.PAGE_SIZE))


func _on_fill_failed(message: String) -> void:
	_fill_status = tr("Online-Suche fehlgeschlagen: %s") % message
	_fill_failed = true
	_finish_fill()


func _finish_fill_quiet() -> void:
	if _fill_req != null and is_instance_valid(_fill_req):
		_fill_req.cancel_request()
	_filling = false


func _finish_fill() -> void:
	var failed := _fill_failed
	# Nachrangig: Maps ohne Kennwerte (Filter nicht pruefbar).
	for d in _fill_later:
		if _fill_need <= 0:
			break
		if _fill_add(d):
			_fill_unknown += 1
	_finish_fill_quiet()
	var notes: Array[String] = []
	if failed:
		notes.append(_fill_status)
	if _fill_unknown > 0:
		notes.append(tr("%d Maps ohne Long-Note-/Längen-/BPM-Daten ergänzt — Filter dort nicht geprüft.") % _fill_unknown)
	if _fill_need > 0:
		notes.append(tr("Nicht genug passende Maps gefunden — Filter lockern oder selbst wählen."))
	_fill_status = "\n".join(notes)
	refresh()
