class_name CampaignScreen
extends Control

## Kampagnen-Szene: Kapitelweg durch die 13 Welten (Ansicht "path") und ein Kapitel mit
## seinen Stufen (Ansicht "stages"). Logik: Campaign. Entwurf auf 1280x720, gleichmaessig
## skaliert. Graphit + Bernstein, flache Flaechen, Song-Bilder als Gestaltung:
## - Stufen-Cover: lokales Thumbnail der Map (MapSet.thumb_texture, Disk-Cache), sonst das
##   Online-Cover ueber die Set-ID (Mirror.fetch_cover wie im Online-Browser), sonst ein
##   ruhiger Platzhalter in Kapitel-Farbe. Eins je Frame, damit nichts ruckelt.
## - Gewaehlte Stufe: grosses Bild (OszImporter.prepare im Hintergrund, wie der
##   Song-Browser), weichgezeichnet als Hintergrund, Vorschau des Songs laeuft an.
## Bedienung: Maus; Pfeile waehlen, Enter oeffnet/startet (zweiter Klick auf die gewaehlte
## Stufe startet auch), Esc zurueck.
##
## Harness: --shot-campaign=<Praefix> speichert <Praefix>_path.png, _path_locked.png,
## _stage.png, _locked.png und _result.png mit Demo-Stand (ohne Schreiben, Maps aus
## --maps-dir, Cover aus dem Netz) und beendet sich.
## --shot-campaign-run=<Praefix> [--shot-campaign-stage=<Stufe>] --campaign-path=<Datei>
## --autoplay: echter Stufenlauf (GameSession.campaign_run_prefix). Die Stufen davor
## gelten in der Testdatei als geschafft.

const BASE := Vector2(1280.0, 720.0)
const COLS := 7
const PLATE_W := 152.0
const PLATE_GAP := 20.0
const PLATE_IMG_H := 86.0
const PLATE_H := 150.0
const ROW_GAP := 40.0
const BOARD_ROWS := 7
const ROW_H := 64.0
const BOSS_H := 80.0
const LEFT_W := 500.0
const RX := 588.0
const COVER_URL := "https://assets.ppy.sh/beatmaps/%d/covers/card@2x.jpg"
const PREVIEW_DB := -3.0
const PREVIEW_SILENT_DB := -60.0
const PREVIEW_FADE_OUT := 0.12
const PREVIEW_FADE_IN := 0.25
const BACKDROP_A := 0.12

var _all: Dictionary = {}
var _mode := "mania"
var _data: Dictionary = {}
var _state: Dictionary = {}
var _lib: MapLibrary
var _sets: Array = []
var _s := 1.0
var _origin := Vector2.ZERO
var _root: Control
var _view := "path"
var _chapter := 0
var _stage_id := ""
var _hover_chapter := -1
var _shot := ""
var _head_font: FontVariation
var _sel_frame := -1

var _info: Control
var _info_btn: Button
var _detail: Control
var _hero: Cover
var _rows: Dictionary = {}
var _board_box: Control
var _board_token := 0
var _start_btn: Button
var _start_note: Label
var _dl_label: Label
var _dl_queue: Array[int] = []
var _dl_total := 0
var _dl_failed := 0
var _dl_current := 0
var _dl_chapter := -1

var _backdrop: TextureRect
var _backdrop_key := ""
var _backdrop_tw: Tween
var _preview: AudioStreamPlayer
var _preview_tw: Tween
var _preview_key := ""
var _wait_osz := ""
var _wait_stage := ""
## Cover-Empfaenger der aktuellen Ansicht: [set_id, Node mit .tex].
var _cover_targets: Array = []
var _thumb_queue: Array = []

static var _thumbs: Dictionary = {}
## Set-ID -> Cover-Textur (lokales Thumbnail oder Online-Cover).
static var _covers: Dictionary = {}
## Schluessel -> weichgezeichnete Textur fuer den Hintergrund.
static var _blurs: Dictionary = {}


## Bild "cover"-artig in ein Rechteck (mittig beschnitten) oder ruhiger Platzhalter.
static func draw_cover(ci: CanvasItem, tex: Texture2D, r: Rect2, col: Color, u: float) -> void:
	if tex != null:
		var ts := tex.get_size()
		var want := r.size.x / maxf(r.size.y, 1.0)
		var rw := ts.x
		var rh := rw / want
		if rh > ts.y:
			rh = ts.y
			rw = rh * want
		ci.draw_texture_rect_region(tex, r, Rect2((ts.x - rw) * 0.5, (ts.y - rh) * 0.5, rw, rh))
		return
	ci.draw_rect(r, col)
	for i in 3:
		var y := r.position.y + r.size.y * (0.58 + i * 0.13)
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.05 + 0.02 * i), maxf(u, 1.0))


## Bild mit Kante, optional abgedunkelt (gesperrt) und mit Verlauf unten fuer Text.
class Cover extends Control:
	var tex: Texture2D
	var col := Color(0.16, 0.20, 0.26)
	var dim := 0.0
	var scrim := 0.0
	var u := 1.0
	var edge := true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		CampaignScreen.draw_cover(self, tex, r, col, u)
		if scrim > 0.0:
			# Verlauf fuer Text auf dem Bild: oben frei, zur Mitte halb, unten fast deckend.
			var top := size.y * (1.0 - scrim)
			var mid := top + (size.y - top) * 0.42
			var c0 := Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.0)
			var c1 := Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.72)
			var c2 := Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.94)
			draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, mid), Vector2(0, mid)]),
				PackedColorArray([c0, c0, c1, c1]))
			draw_polygon(PackedVector2Array([Vector2(0, mid), Vector2(size.x, mid), size, Vector2(0, size.y)]),
				PackedColorArray([c1, c1, c2, c2]))
		if dim > 0.0:
			draw_rect(r, Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, dim))
		if edge:
			draw_rect(r, UiTheme.LINE, false, 1.0)


## Kapitel im Kapitelweg: Weltbild, darunter Name, Sterne und sechs Stufen-Striche.
class Plate extends Button:
	var tex: Texture2D
	var col := Color(0.16, 0.20, 0.26)
	var locked := false
	var current := false
	var img_h := 86.0
	var u := 1.0
	## je Stufe: 2 geschafft, 1 offen, 0 gesperrt
	var steps: Array = []

	func _draw() -> void:
		var r := Rect2(0, 0, size.x, img_h)
		CampaignScreen.draw_cover(self, tex, r, col, u)
		if locked:
			draw_rect(r, Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.74))
		draw_rect(r, UiTheme.LINE, false, 1.0)
		if current:
			draw_rect(Rect2(0, img_h - 3.0 * u, size.x, 3.0 * u), UiTheme.ACCENT)
		if not steps.is_empty():
			var gap := 3.0 * u
			var y := size.y - 4.0 * u
			var w := (size.x - gap * (steps.size() - 1)) / steps.size()
			for i in steps.size():
				var c := UiTheme.ACCENT if int(steps[i]) == 2 else (
					Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.28) if int(steps[i]) == 1
					else Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.08))
				draw_rect(Rect2(i * (w + gap), y, w, maxf(2.0 * u, 1.0)), c)
		if not disabled and (has_focus() or is_hovered()):
			draw_rect(r.grow(2.0 * u), Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.55), false, maxf(u, 1.0))


## Stufe im Kapitelweg: Wegpunkt mit Linie, Cover, Text als Kinder, Sterne.
class StageRow extends Button:
	var tex: Texture2D
	var col := Color(0.16, 0.20, 0.26)
	var locked := false
	var cleared := false
	var prev_cleared := false
	var first := false
	var last := false
	var boss := false
	var selected := false
	var u := 1.0
	var node_x := 14.0
	var cover_rect := Rect2()

	func _draw() -> void:
		var h := size.y
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SURFACE)
			draw_rect(Rect2(0, 0, 3.0 * u, h), UiTheme.ACCENT)
		elif is_hovered() or has_focus():
			draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.RAISED.r, UiTheme.RAISED.g, UiTheme.RAISED.b, 0.6))
		var x := node_x * u
		var cy := h * 0.5
		var lw := maxf(2.0 * u, 1.0)
		var off := Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.14)
		if not first:
			draw_rect(Rect2(x - lw * 0.5, 0, lw, cy), UiTheme.ACCENT if prev_cleared else off)
		if not last:
			draw_rect(Rect2(x - lw * 0.5, cy, lw, h - cy), UiTheme.ACCENT if cleared else off)
		var c := Vector2(x, cy)
		if boss:
			var r := 7.0 * u
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			if cleared:
				draw_colored_polygon(pts, UiTheme.ACCENT)
			else:
				draw_colored_polygon(pts, UiTheme.BG)
				pts.append(pts[0])
				draw_polyline(pts, UiTheme.DIM if locked else UiTheme.ACCENT, lw, true)
		elif cleared:
			draw_circle(c, 5.0 * u, UiTheme.ACCENT)
		elif locked:
			draw_circle(c, 4.0 * u, UiTheme.BG)
			draw_arc(c, 4.0 * u, 0, TAU, 20, Color(UiTheme.DIM.r, UiTheme.DIM.g, UiTheme.DIM.b, 0.6), maxf(u, 1.0), true)
		else:
			draw_circle(c, 6.0 * u, UiTheme.BG)
			draw_arc(c, 6.0 * u, 0, TAU, 24, UiTheme.ACCENT, lw, true)
		CampaignScreen.draw_cover(self, tex, cover_rect, col, u)
		if locked:
			draw_rect(cover_rect, Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.66))
		draw_rect(cover_rect, UiTheme.LINE, false, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build_theme()
	_head_font = UiTheme.heading_font(0)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-campaign="):
			_shot = a.trim_prefix("--shot-campaign=")
	_all = Campaign.load_data()
	_data = Campaign.for_mode(_all, _mode)
	_state = _demo_state() if _shot != "" else Campaign.load_state()
	var run_shot := GameSession.campaign_run_prefix()
	if run_shot != "":
		if Campaign.default_path() == Campaign.PATH:
			push_error("--shot-campaign-run braucht --campaign-path=<Testdatei>")
			get_tree().quit(2)
			return
		GameSession.campaign_return = _seed_run_state()
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_backdrop = TextureRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.modulate.a = 0.0
	add_child(_backdrop)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_preview = AudioStreamPlayer.new()
	_preview.bus = "Music"
	add_child(_preview)
	if DisplayServer.get_name() != "headless":
		_lib = MapLibrary.new()
		_lib.scan()
		_sets = _lib.mapsets
		Mirror.cover_ready.connect(_on_cover_ready)
		if _shot == "":
			Mirror.download_progress.connect(_on_dl_progress)
			Mirror.download_done.connect(_on_dl_done)
			Mirror.download_failed.connect(_on_dl_failed)
	var back_to := str(GameSession.campaign_return)
	GameSession.campaign_return = ""
	var start_mode := Campaign.mode_of_stage(_all, back_to)
	if start_mode == "":
		start_mode = str(_state.get("mode", "mania"))
	_enter_mode(start_mode)
	if back_to != "" and Campaign.chapter_index_of(_data, back_to) >= 0:
		_chapter = Campaign.chapter_index_of(_data, back_to)
		_stage_id = back_to
		_view = "stages"
	_rebuild()
	resized.connect(_rebuild)
	if DisplayServer.get_name() == "headless":
		print("=== Campaign Headless OK (%d Kapitel, %d Fehler) ===" % [
			Campaign.chapters(_data).size(), Campaign.validate(_all).size()])
		get_tree().quit(0)
	elif run_shot != "":
		_run_stage_shot(run_shot)
	elif _shot != "":
		_run_shots()


func _exit_tree() -> void:
	if Mirror.cover_ready.is_connected(_on_cover_ready):
		Mirror.cover_ready.disconnect(_on_cover_ready)
	if Mirror.download_progress.is_connected(_on_dl_progress):
		Mirror.download_progress.disconnect(_on_dl_progress)
		Mirror.download_done.disconnect(_on_dl_done)
		Mirror.download_failed.disconnect(_on_dl_failed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_back()


## Modus wechseln: eigene Kapitel, eigener Fortschritt (Stufen-IDs tragen den Modus).
func _enter_mode(mode: String) -> void:
	if Campaign.chapters(Campaign.for_mode(_all, mode)).is_empty():
		mode = "mania"
	_mode = mode
	_data = Campaign.for_mode(_all, _mode)
	var cur := Campaign.current_stage_id(_data, _state)
	_chapter = maxi(Campaign.chapter_index_of(_data, cur), 0) if cur != "" else 0
	_stage_id = ""
	_view = "path"


func _pick_mode(mode: String) -> void:
	if mode == _mode:
		return
	_enter_mode(mode)
	if _shot == "":
		_state["mode"] = _mode
		Campaign.save_state(_state)
	_stop_preview()
	_rebuild()


func _back() -> void:
	if _view == "stages":
		_view = "path"
		_stop_preview()
		_rebuild()
	else:
		_stop_preview()
		SceneFader.go("res://scenes/main_menu.tscn")


# ------------------------------------------------------------------ Bausteine

func _px(v: float) -> float:
	return roundf(v * _s)


func _put(c: Control, x: float, y: float, w: float, h: float, parent: Control = null) -> void:
	if c.get_parent() == null:
		(parent if parent != null else _root).add_child(c)
	var o := _origin if c.get_parent() == _root else Vector2.ZERO
	c.position = o + Vector2(_px(x), _px(y))
	c.size = Vector2(_px(w), _px(h))


func _label(text: String, fs: float, col: Color, heading: bool = false) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_size_override("font_size", int(_px(fs)))
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", _head_font)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	UiTheme.style_button(b, primary, 4)
	b.add_theme_font_size_override("font_size", int(_px(15.0)))
	b.pressed.connect(cb)
	return b


func _line(x: float, y: float, w: float, h: float, col: Color, parent: Control = null) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(r, x, y, w, h, parent)
	if w <= 1.0:
		r.size.x = maxf(_px(1.0), 1.0)
	if h <= 1.0:
		r.size.y = maxf(_px(1.0), 1.0)
	return r


func _cover(x: float, y: float, w: float, h: float, col: Color, parent: Control = null) -> Cover:
	var c := Cover.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.u = _s
	c.col = col
	_put(c, x, y, w, h, parent)
	return c


func _stars(met: Array, px: float, x: float, y: float, parent: Control = null) -> CampaignStars:
	var st := CampaignStars.make(met, _px(px))
	(parent if parent != null else _root).add_child(st)
	st.position = (_origin if parent == null else Vector2.ZERO) + Vector2(_px(x), _px(y))
	return st


func _num(v: float, decimals: int) -> String:
	return UiTheme.fmt_num(v, decimals)


func _world_color(world: String) -> Color:
	var pal := WorldTheme.palette(world)
	var c: Color = pal.get("line", Color(0.30, 0.42, 0.62))
	return Color.from_hsv(c.h, minf(c.s, 0.55), 0.26)


## Kleines Vorschaubild der Welt aus dem Panorama (einmal je Welt, verkleinert). null = keins.
static func world_thumb(world: String) -> Texture2D:
	if _thumbs.has(world):
		return _thumbs[world]
	var out: Texture2D = null
	var dir := WorldTheme.asset_dir(world)
	var cands: Array[String] = ["%s/%s_sky.webp" % [dir, world], "%s/sky_%s.webp" % [dir, world]]
	if world == WorldTheme.GALAXY:
		cands = ["res://assets_game/space/sky_azure.webp"]
	for p in cands:
		if not ResourceLoader.exists(p):
			continue
		var t := load(p) as Texture2D
		var img := t.get_image() if t != null else null
		if img == null or img.is_empty():
			continue
		if img.is_compressed():
			img.decompress()
		var w := int(img.get_width() * 0.34)
		var h := int(w * 0.5)
		@warning_ignore("integer_division")
		var region := img.get_region(Rect2i((img.get_width() - w) / 2, int(img.get_height() * 0.44) - h / 2, w, h))
		region.resize(640, 320, Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(region)
		break
	_thumbs[world] = out
	return out


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in _root.get_children():
		c.queue_free()
	var v := size
	_s = clampf(minf(v.x / BASE.x, v.y / BASE.y), 0.6, 3.0)
	_origin = ((v - BASE * _s) * 0.5).round()
	_info = null
	_info_btn = null
	_detail = null
	_hero = null
	_start_btn = null
	_dl_label = null
	_board_box = null
	_rows.clear()
	_cover_targets.clear()
	_thumb_queue.clear()
	_build_top()
	if _view == "stages":
		_build_stages()
	else:
		_build_path()


func _build_top() -> void:
	var back := _button(tr("Zurück"), false, _back)
	back.name = "Back"
	_put(back, 48, 28, 104, 36)
	# Modus-Wahl: je Modus eine eigene Kampagne. Ohne Kapitel = "bald".
	var tx := 176.0
	for m in ScoreStore.MODES:
		var soon := Campaign.chapters(Campaign.for_mode(_all, m)).is_empty()
		var tab := Button.new()
		tab.name = "Mode" + m.capitalize()
		tab.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tab.text = ScoreStore.mode_label(m)
		tab.disabled = soon
		tab.focus_mode = Control.FOCUS_NONE
		tab.tooltip_text = tr("Kommt bald") if soon else ""
		tab.add_theme_font_override("font", _head_font)
		tab.add_theme_font_size_override("font_size", int(_px(14.0)))
		tab.add_theme_color_override("font_color", UiTheme.TEXT if m == _mode else UiTheme.DIM)
		tab.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		tab.add_theme_color_override("font_disabled_color", Color(UiTheme.DIM.r, UiTheme.DIM.g, UiTheme.DIM.b, 0.45))
		for sb in ["normal", "hover", "pressed", "disabled", "focus"]:
			tab.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		tab.pressed.connect(_pick_mode.bind(m))
		_put(tab, tx, 28, 84, 36)
		if m == _mode:
			_line(tx + 14.0, 62, 56, 2, UiTheme.ACCENT)
		tx += 86.0
	var stars := _label("%d / %d" % [Campaign.total_stars(_data, _state), Campaign.max_stars(_data)], 15.0, UiTheme.TEXT, true)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(stars, 1032, 28, 200, 20)
	var pts := _label(tr("%s Punkte") % UiTheme.fmt_score(Campaign.total_points(_data, _state)), 12.0, UiTheme.DIM)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(pts, 932, 48, 300, 18)
	var w := stars.get_theme_font("font").get_string_size(stars.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		stars.get_theme_font_size("font_size")).x / _s
	_stars([true], 13.0, 1232.0 - w - 19.0, 31.0)


# ------------------------------------------------------------------ Cover

## Cover einer Stufe: sofort, wenn schon da; sonst wird es nachgeliefert (target.tex).
func _want_cover(stage: Dictionary, target: Node) -> Texture2D:
	var id := int(stage.get("set_id", 0))
	if id <= 0:
		return null
	if _covers.has(id):
		return _covers[id]
	_cover_targets.append([id, target])
	var loc := _local(stage)
	var ms: Variant = loc.get("set")
	if ms is MapSet:
		if not _thumb_queue.has(ms):
			_thumb_queue.append(ms)
	elif DisplayServer.get_name() != "headless":
		var t: Texture2D = Mirror.cached_cover(id)
		if t != null:
			_covers[id] = t
			return t
		Mirror.fetch_cover(id, COVER_URL % id)
	return null


func _give_cover(id: int, tex: Texture2D) -> void:
	if tex == null:
		return
	_covers[id] = tex
	for e: Array in _cover_targets:
		if int(e[0]) == id and is_instance_valid(e[1]) and not (e[1] as Node).is_queued_for_deletion():
			var n: Node = e[1]
			if n == _hero and _hero.tex != null:
				continue
			n.set("tex", tex)
			(n as CanvasItem).queue_redraw()
	if _view == "stages" and id == int(Campaign.stage_by_id(_data, _stage_id).get("set_id", -1)):
		_set_backdrop("set%d" % id, tex)


func _on_cover_ready(set_id: int, tex: Texture2D) -> void:
	if not _covers.has(set_id):
		_give_cover(set_id, tex)


## Ein lokales Thumbnail je Frame (beim ersten Mal aus dem Zip), dann Vorbereitung der
## gewaehlten Stufe abholen.
func _process(_delta: float) -> void:
	if not _thumb_queue.is_empty():
		var ms: MapSet = _thumb_queue.pop_front()
		var id := Campaign.set_id_of_file(ms.osz_path)
		if not _covers.has(id):
			_give_cover(id, ms.thumb_texture())
	if _wait_osz != "" and OszImporter.is_prepared(_wait_osz):
		var osz := _wait_osz
		_wait_osz = ""
		if _wait_stage == _stage_id:
			_on_prepared(osz)


func _set_backdrop(key: String, tex: Texture2D) -> void:
	if key == _backdrop_key or tex == null:
		return
	_backdrop_key = key
	if not _blurs.has(key):
		_blurs[key] = UiTheme.blurred_texture(tex, 6)
	var blurred: Texture2D = _blurs[key]
	if _backdrop_tw != null and _backdrop_tw.is_valid():
		_backdrop_tw.kill()
	_backdrop_tw = create_tween()
	if _backdrop.texture != null and _backdrop.modulate.a > 0.01:
		_backdrop_tw.tween_property(_backdrop, "modulate:a", 0.0, 0.14)
	_backdrop_tw.tween_callback(func(): _backdrop.texture = blurred)
	_backdrop_tw.tween_property(_backdrop, "modulate:a", BACKDROP_A, 0.3)


# ------------------------------------------------------------------ Kapitelweg

func _plate_pos(i: int) -> Vector2:
	var x0 := (BASE.x - (COLS * PLATE_W + (COLS - 1) * PLATE_GAP)) * 0.5
	@warning_ignore("integer_division")
	var row := i / COLS
	var col := i % COLS
	if row % 2 == 1:
		col = COLS - 1 - col
	return Vector2(x0 + col * (PLATE_W + PLATE_GAP), 176.0 + row * (PLATE_H + ROW_GAP))


## Stand je Stufe eines Kapitels: 2 geschafft, 1 offen, 0 gesperrt.
func _steps(ch: Dictionary) -> Array:
	var out: Array = []
	for st: Dictionary in ch.get("stages", []):
		var id := str(st.id)
		out.append(2 if Campaign.stage_cleared(_state, id) else (1 if Campaign.stage_open(_data, _state, id) else 0))
	return out


func _build_path() -> void:
	var chs := Campaign.chapters(_data)
	_put(_label("%s  ·  %s" % [tr("Kampagne"), ScoreStore.mode_label(_mode)], 28.0, UiTheme.TEXT, true), 48, 82, 900, 42)
	_put(_label(tr("%d Welten · %d Stufen · gleiche Maps für alle") % [chs.size(), Campaign.all_stages(_data).size()],
		13.0, UiTheme.DIM), 48, 124, 700, 24)
	# Weg: Linien zwischen den Kapiteln, Bernstein bis zum aktuellen Kapitel.
	for i in range(1, chs.size()):
		var a := _plate_pos(i - 1)
		var b := _plate_pos(i)
		var col := UiTheme.ACCENT if Campaign.chapter_done(chs[i - 1], _state) else UiTheme.LINE
		var mid := PLATE_IMG_H * 0.5
		if is_equal_approx(a.y, b.y):
			var xl := minf(a.x, b.x) + PLATE_W
			_line(xl, a.y + mid - 1.0, PLATE_GAP, 2.0, col)
		else:
			_line(a.x + PLATE_W * 0.5 - 1.0, a.y + PLATE_H, 2.0, ROW_GAP, col)
	var cur := Campaign.current_stage_id(_data, _state)
	var cur_ch := Campaign.chapter_index_of(_data, cur)
	var focus_plate: Plate = null
	for i in chs.size():
		var ch: Dictionary = chs[i]
		var open := Campaign.chapter_open(_data, _state, i)
		var done := Campaign.chapter_done(ch, _state)
		var p := Plate.new()
		p.name = "Chapter%02d" % (i + 1)
		p.u = _s
		p.img_h = _px(PLATE_IMG_H)
		p.col = _world_color(str(ch.world))
		p.locked = not open
		p.current = i == cur_ch
		p.steps = _steps(ch)
		p.tex = _thumbs.get(str(ch.world))
		for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
			p.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		var pos := _plate_pos(i)
		_put(p, pos.x, pos.y, PLATE_W, PLATE_H)
		p.pressed.connect(_open_chapter.bind(i))
		p.mouse_entered.connect(_show_info.bind(i))
		p.focus_entered.connect(_show_info.bind(i))
		var tcol := UiTheme.TEXT if open else UiTheme.DIM
		_put(_label("%02d" % (i + 1), 12.0, UiTheme.DIM, true), 0, PLATE_IMG_H + 8, 24, 22, p)
		_put(_label(Campaign.world_label(str(ch.world)), 15.0, tcol, true), 24, PLATE_IMG_H + 8, PLATE_W - 24, 22, p)
		var st := _label("", 12.0, UiTheme.DIM)
		if not open:
			st.text = tr("Gesperrt")
		else:
			st.text = "%d / %d" % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)]
			_stars([Campaign.chapter_stars(ch, _state) > 0], 11.0, 0, PLATE_IMG_H + 36.0, p)
		_put(st, 0 if not open else 17, PLATE_IMG_H + 31, 80, 20, p)
		if done:
			var ok := _label(tr("Geschafft"), 12.0, UiTheme.GOOD)
			ok.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_put(ok, PLATE_W - 84, PLATE_IMG_H + 31, 84, 20, p)
		if i == _chapter:
			focus_plate = p
	_line(48, 566, BASE.x - 96, 1, UiTheme.LINE)
	_show_info(_chapter)
	if focus_plate != null and _shot == "":
		focus_plate.grab_focus.call_deferred()
	_fill_thumbs()


## Zeile unter dem Weg: Kapitel, Stand, die sechs Stufen mit Cover, Oeffnen.
func _show_info(i: int) -> void:
	var chs := Campaign.chapters(_data)
	if i < 0 or i >= chs.size() or _view != "path":
		return
	if i == _hover_chapter and is_instance_valid(_info):
		return
	_hover_chapter = i
	if is_instance_valid(_info):
		_info.queue_free()
	_cover_targets = _cover_targets.filter(func(e: Array): return is_instance_valid(e[1]) and not (e[1] as Node).is_queued_for_deletion())
	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(_info, 0, 0, BASE.x, BASE.y)
	var ch: Dictionary = chs[i]
	var band: Array = ch.get("stars", [0, 0])
	var open := Campaign.chapter_open(_data, _state, i)
	_put(_label(tr("Kapitel %d") % (i + 1), 13.0, UiTheme.DIM), 48, 584, 360, 20, _info)
	_put(_label(Campaign.world_label(str(ch.world)), 22.0, UiTheme.TEXT if open else UiTheme.DIM, true), 48, 604, 360, 34, _info)
	_put(_label(tr("Schwierigkeit %s bis %s") % [_num(float(band[0]), 1), _num(float(band[1]), 1)], 13.0, UiTheme.DIM),
		48, 640, 360, 20, _info)
	var state_t := ""
	var state_c := UiTheme.DIM
	if not open:
		state_t = tr("Erst den Boss von Kapitel %d schaffen") % i
	elif Campaign.chapter_done(ch, _state):
		state_t = tr("%d / %d Sterne") % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)]
		state_c = UiTheme.GOOD
	else:
		state_t = tr("%d von %d Stufen geschafft") % [Campaign.chapter_cleared_count(ch, _state), (ch.stages as Array).size()]
		state_c = UiTheme.TEXT
	_put(_label(state_t, 13.0, state_c), 48, 662, 380, 20, _info)
	# Die Stufen des Kapitels als Cover-Reihe (Boss mit Bernstein-Kante).
	var sts: Array = ch.get("stages", [])
	var x := 432.0
	for k in sts.size():
		var st: Dictionary = sts[k]
		var id := str(st.id)
		var sopen := Campaign.stage_open(_data, _state, id)
		var boss := bool(st.get("boss", false))
		var cv := _cover(x, 588, 88, 50, _world_color(str(ch.world)), _info)
		cv.dim = 0.0 if sopen else 0.74
		cv.tex = _want_cover(st, cv)
		if boss:
			_line(x, 638, 88, 2, UiTheme.ACCENT if sopen else Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.4), _info)
		_put(_label(tr("Boss") if boss else str(k + 1), 12.0, UiTheme.ACCENT if boss else UiTheme.DIM, true), x, 644, 40, 18, _info)
		var met := Campaign.met_of(_state, id)
		var stars := _stars(met, 9.0, 0, 0, _info)
		stars.position = Vector2(_px(x + 88.0) - stars.width(), _px(648.0))
		stars.modulate.a = 1.0 if sopen else 0.5
		x += 98.0
	_info_btn = _button(tr("Kapitel öffnen"), true, func(): _open_chapter(_hover_chapter))
	_info_btn.name = "OpenChapter"
	_info_btn.focus_mode = Control.FOCUS_NONE
	_info_btn.disabled = not open
	_put(_info_btn, 1032, 590, 200, 46, _info)
	var wt: Texture2D = world_thumb(str(ch.world)) if _thumbs.has(str(ch.world)) else null
	if wt != null:
		_set_backdrop("world:" + str(ch.world), wt)


## Weltbilder nach dem ersten Bild einsetzen (ein Panorama je Frame).
func _fill_thumbs() -> void:
	var chs := Campaign.chapters(_data)
	for i in chs.size():
		var world := str((chs[i] as Dictionary).world)
		if not _thumbs.has(world):
			await get_tree().process_frame
			if not is_inside_tree() or _view != "path":
				return
		var t := world_thumb(world)
		var p := _root.get_node_or_null("Chapter%02d" % (i + 1)) as Plate
		if p != null and t != null and not p.is_queued_for_deletion():
			p.tex = t
			p.queue_redraw()
		if i == _hover_chapter and t != null:
			_set_backdrop("world:" + world, t)


func _open_chapter(i: int) -> void:
	if not Campaign.chapter_open(_data, _state, i):
		return
	_chapter = i
	_stage_id = ""
	_view = "stages"
	_rebuild()


# ------------------------------------------------------------------ Kapitel mit Stufen

func _chapter_dict() -> Dictionary:
	var chs := Campaign.chapters(_data)
	return chs[clampi(_chapter, 0, chs.size() - 1)] if not chs.is_empty() else {}


func _local(stage: Dictionary) -> Dictionary:
	var loc := Campaign.find_local(stage, _sets) if not _sets.is_empty() else {}
	if loc.is_empty() and _shot != "":
		return {"osz_path": "shot", "index": 0}
	return loc


func _build_stages() -> void:
	var ch := _chapter_dict()
	var sts: Array = ch.get("stages", [])
	if _stage_id == "" or Campaign.chapter_index_of(_data, _stage_id) != _chapter:
		_stage_id = str((sts[0] as Dictionary).id)
		for s: Dictionary in sts:
			if Campaign.stage_open(_data, _state, str(s.id)):
				_stage_id = str(s.id)
	var wcol := _world_color(str(ch.world))
	# Kopf: Weltbild, Kapitel, Name, Sterne.
	var head := _cover(48, 84, 100, 56, wcol)
	head.tex = world_thumb(str(ch.world))
	var band: Array = ch.get("stars", [0, 0])
	_put(_label("%s  ·  %s" % [tr("Kapitel %d") % (_chapter + 1),
		tr("Schwierigkeit %s bis %s") % [_num(float(band[0]), 1), _num(float(band[1]), 1)]], 13.0, UiTheme.DIM),
		164, 84, 300, 20)
	_put(_label(Campaign.world_label(str(ch.world)), 22.0, UiTheme.TEXT, true), 164, 104, 260, 36)
	var cs := _label("%d / %d" % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)], 15.0, UiTheme.TEXT, true)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(cs, 48 + LEFT_W - 140, 110, 120, 24)
	_stars([true], 13.0, 48 + LEFT_W - 14, 115)
	# Weg der sechs Stufen.
	var y := 156.0
	var focus_row: StageRow = null
	for i in sts.size():
		var st: Dictionary = sts[i]
		var id := str(st.id)
		var open := Campaign.stage_open(_data, _state, id)
		var boss := bool(st.get("boss", false))
		var h := BOSS_H if boss else ROW_H
		var row := StageRow.new()
		row.name = "Stage" + id
		row.u = _s
		row.col = wcol
		row.locked = not open
		row.cleared = Campaign.stage_cleared(_state, id)
		row.prev_cleared = i > 0 and Campaign.stage_cleared(_state, str((sts[i - 1] as Dictionary).id))
		row.first = i == 0
		row.last = i == sts.size() - 1
		row.boss = boss
		row.selected = id == _stage_id
		var cw := (h - 12.0) * 16.0 / 9.0
		row.cover_rect = Rect2(_px(32.0), _px(6.0), _px(cw), _px(h - 12.0))
		for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
			row.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		_put(row, 48, y, LEFT_W, h)
		row.tex = _want_cover(st, row)
		row.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		row.focus_entered.connect(_select_stage.bind(id))
		row.pressed.connect(_row_pressed.bind(id))
		var tx := 32.0 + cw + 14.0
		var tw := LEFT_W - tx - 70.0
		var a := 1.0 if open else 0.5
		var ty := 10.0
		if boss:
			var bl := _label(tr("Boss"), 12.0, UiTheme.ACCENT if open else UiTheme.DIM, true)
			_put(bl, tx, 9, 80, 16, row)
			ty = 25.0
		var title := _label(str(st.get("title", "")), 15.0, UiTheme.TEXT)
		title.modulate.a = a
		_put(title, tx, ty, tw, 22, row)
		var sub_t := "%s  ·  %s  ·  ★ %s" % [str(st.get("artist", "")), Campaign.length_text(int(st.get("length_s", 0))),
			_num(float(st.get("map_stars", 0.0)), 2)]
		for m: Variant in st.get("mods", []):
			sub_t += "  ·  " + str(m)
		if not open:
			sub_t = Campaign.lock_reason(_data, _state, id)
		var sub := _label(sub_t, 13.0, UiTheme.DIM)
		sub.modulate.a = maxf(a, 0.8)
		_put(sub, tx, ty + 22.0, tw, 20, row)
		var stars := _stars(Campaign.met_of(_state, id), 13.0, 0, 0, row)
		stars.modulate.a = a
		stars.position = Vector2(_px(LEFT_W - 14.0) - stars.width(), (_px(h) - stars.size.y) * 0.5)
		_rows[id] = row
		if row.selected:
			focus_row = row
		y += h
	_dl_label = _label("", 13.0, UiTheme.DIM)
	_put(_dl_label, 48, y + 8.0, LEFT_W, 20)
	_build_next_chapter()
	_build_detail()
	if focus_row != null and _shot == "":
		focus_row.grab_focus.call_deferred()
	_start_downloads()


## Unten links: was als Naechstes kommt (Kapitel danach, offen oder warum gesperrt).
func _build_next_chapter() -> void:
	var chs := Campaign.chapters(_data)
	var ni := _chapter + 1
	if ni >= chs.size():
		return
	var nch: Dictionary = chs[ni]
	var open := Campaign.chapter_open(_data, _state, ni)
	_line(48, 606, LEFT_W, 1, UiTheme.LINE)
	var b := Button.new()
	b.name = "NextChapter"
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not open
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
	for sb in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", UiTheme.solid_box(Color(UiTheme.RAISED.r, UiTheme.RAISED.g, UiTheme.RAISED.b, 0.6), 2))
	b.pressed.connect(_open_chapter.bind(ni))
	_put(b, 48, 618, LEFT_W, 56)
	var cv := _cover(8, 8, 72, 40, _world_color(str(nch.world)), b)
	cv.tex = world_thumb(str(nch.world))
	cv.dim = 0.0 if open else 0.6
	_put(_label(tr("Danach: Kapitel %d") % (ni + 1), 12.0, UiTheme.DIM), 94, 8, 300, 18, b)
	_put(_label(Campaign.world_label(str(nch.world)), 15.0, UiTheme.TEXT if open else UiTheme.DIM, true), 94, 26, 200, 22, b)
	var why := _label(tr("Offen") if open else tr("Boss dieses Kapitels schaffen"), 13.0, UiTheme.GOOD if open else UiTheme.DIM)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(why, LEFT_W - 260, 26, 248, 22, b)


func _row_pressed(id: String) -> void:
	if id == _stage_id and Engine.get_process_frames() != _sel_frame:
		_start_stage()
	else:
		_select_stage(id)


func _select_stage(id: String) -> void:
	if id == _stage_id and is_instance_valid(_detail):
		return
	_sel_frame = Engine.get_process_frames()
	_stage_id = id
	for k: String in _rows:
		var r: StageRow = _rows[k]
		if is_instance_valid(r):
			r.selected = k == id
			r.queue_redraw()
	_build_detail()


## Rechte Seite: grosses Bild mit Titel, Zahlen, Ziele mit Stand, Bestwert, Rangliste, Start.
func _build_detail() -> void:
	if is_instance_valid(_detail):
		_detail.queue_free()
	_cover_targets = _cover_targets.filter(func(e: Array): return is_instance_valid(e[1]) and not (e[1] as Node).is_queued_for_deletion())
	var st := Campaign.stage_by_id(_data, _stage_id)
	if st.is_empty():
		return
	_detail = Control.new()
	_detail.name = "Detail"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(_detail, 0, 0, BASE.x, BASE.y)
	var x := RX
	var w := BASE.x - 48.0 - x
	var idx := Campaign.stage_index_of(_data, _stage_id)
	var open := Campaign.stage_open(_data, _state, _stage_id)
	var boss := bool(st.get("boss", false))
	# Bild
	_hero = _cover(x, 84, w, 236, _world_color(str(_chapter_dict().get("world", ""))), _detail)
	_hero.scrim = 0.74
	_hero.dim = 0.0 if open else 0.45
	var t := _want_cover(st, _hero)
	_hero.tex = t
	if t != null:
		_set_backdrop("set%d" % int(st.get("set_id", 0)), t)
	var kicker := "%s  ·  %s" % [Campaign.stage_label(st, idx), ScoreStore.mode_label(str(st.mode))]
	_put(_label(kicker, 13.0, UiTheme.ACCENT if boss or open else UiTheme.DIM, true), x + 20, 84 + 236 - 92, w - 40, 20, _detail)
	_put(_label(str(st.get("title", "")), 28.0, UiTheme.TEXT, true), x + 20, 84 + 236 - 72, w - 40, 38, _detail)
	_put(_label(str(st.get("artist", "")), 15.0, UiTheme.TEXT.darkened(0.08)), x + 20, 84 + 236 - 36, w - 40, 22, _detail)
	# Zahlen: Schwierigkeit, Laenge, BPM, Diff und Mapper.
	var facts: Array = [
		[_num(float(st.get("map_stars", 0.0)), 2), tr("Schwierigkeit")],
		[Campaign.length_text(int(st.get("length_s", 0))), tr("Länge")],
		[str(int(st.get("bpm", 0))), "BPM"],
	]
	var fx := x
	for f: Array in facts:
		_put(_label(str(f[0]), 18.0, UiTheme.TEXT, true), fx, 330, 100, 26, _detail)
		_put(_label(str(f[1]), 12.0, UiTheme.DIM), fx, 356, 100, 18, _detail)
		fx += 104.0
	var diff_t := str(st.get("diff", ""))
	for m: Variant in st.get("mods", []):
		diff_t += "  ·  " + (tr("Mod %s") % str(m))
	_put(_label(diff_t, 15.0, UiTheme.TEXT), fx, 333, x + w - fx, 22, _detail)
	_put(_label(tr("Map von %s") % str(st.get("creator", "")), 12.0, UiTheme.DIM), fx, 356, x + w - fx, 18, _detail)
	_line(x, 386, w, 1, UiTheme.LINE, _detail)
	# Ziele mit Stand
	var gw := 316.0
	_put(_label(tr("Ziele"), 13.0, UiTheme.DIM), x, 398, gw, 20, _detail)
	var met := Campaign.met_of(_state, _stage_id)
	var e := Campaign.entry(_state, _stage_id)
	var goals: Array = st.get("goals", [])
	for i in goals.size():
		var gy := 422.0 + i * 28.0
		_stars([met[i]], 14.0, x, gy + 6.0, _detail)
		_put(_label(Campaign.goal_text(goals[i]), 15.0, UiTheme.TEXT if bool(met[i]) or i == 0 else UiTheme.TEXT.darkened(0.12)),
			x + 24, gy, gw - 24 - 74, 26, _detail)
		var stat := _label("", 13.0, UiTheme.DIM)
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if bool(met[i]):
			stat.text = tr("erfüllt")
			stat.add_theme_color_override("font_color", UiTheme.GOOD)
		else:
			stat.text = Campaign.goal_best_value(goals[i], e)
		_put(stat, x + gw - 74, gy, 74, 26, _detail)
	# Bestwert
	_put(_label(tr("Dein Bestwert"), 13.0, UiTheme.DIM), x, 520, gw, 20, _detail)
	if e.has("score"):
		_put(_label(UiTheme.fmt_score(int(e.score)), 22.0, UiTheme.TEXT, true), x, 540, 150, 30, _detail)
		var plays := int(e.get("plays", 1))
		_put(_label("%s  ·  %s  ·  %s" % [Campaign.acc_text(float(e.get("accuracy", 0.0))), str(e.get("grade", "")),
			tr("1 Lauf") if plays == 1 else tr("%d Läufe") % plays], 13.0, UiTheme.DIM), x + 150, 544, gw - 150, 26, _detail)
	else:
		_put(_label(tr("Noch nicht gespielt"), 15.0, UiTheme.DIM), x, 542, gw, 26, _detail)
	# Rangliste der Map
	var bx := x + gw + 24.0
	var bw := x + w - bx
	_put(_label(tr("Rangliste"), 13.0, UiTheme.DIM), bx, 398, bw, 20, _detail)
	_board_box = Control.new()
	_board_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(_board_box, bx, 422, bw, BOARD_ROWS * 26.0, _detail)
	_load_board(st)
	# Start
	_start_btn = _button(tr("Stufe starten"), true, _start_stage)
	_start_btn.name = "Start"
	_start_btn.focus_mode = Control.FOCUS_NONE
	_put(_start_btn, x, 626, 240, 48, _detail)
	_start_note = _label("", 13.0, UiTheme.DIM)
	_put(_start_note, x + 256, 626, w - 256, 48, _detail)
	_refresh_start()
	_prepare_stage(st)


## Gewaehlte Stufe im Hintergrund vorbereiten (wie der Song-Browser): danach grosses Bild
## und Vorschau des Songs.
func _prepare_stage(st: Dictionary) -> void:
	var loc := _local(st)
	var ms: Variant = loc.get("set")
	if not (ms is MapSet):
		_stop_preview()
		return
	var m := (ms as MapSet).meta_at(int(loc.index))
	_wait_osz = str(loc.osz_path)
	_wait_stage = _stage_id
	GameSession.preload_selection(_wait_osz, str(m.get("audio_filename", "")), (ms as MapSet).background_file,
		str(loc.version))


func _on_prepared(osz: String) -> void:
	var st := Campaign.stage_by_id(_data, _stage_id)
	var loc := _local(st)
	var ms: Variant = loc.get("set")
	if not (ms is MapSet) or str(loc.osz_path) != osz:
		return
	var mset: MapSet = ms
	var big := OszImporter.load_image_texture(osz, mset.background_file)
	if big != null and is_instance_valid(_hero):
		_hero.tex = big
		_hero.queue_redraw()
	var m := mset.meta_at(int(loc.index))
	var audio := str(m.get("audio_filename", ""))
	var key := osz + "|" + audio
	if key == _preview_key and _preview.playing:
		return
	var stream := OszImporter.load_audio_stream_named(osz, audio)
	if stream == null:
		_stop_preview()
		return
	var from := float(m.get("preview_time", -1.0))
	if from < 0.0:
		from = float(m.get("duration_ms", 0.0)) * 0.4
	_preview_key = key
	var gain := SongLoudness.gain_db_for(SongLoudness.make_key(osz, audio))
	if _preview_tw != null and _preview_tw.is_valid():
		_preview_tw.kill()
	_preview_tw = create_tween()
	if _preview.playing:
		_preview_tw.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_tw.tween_callback(func():
		_preview.stop()
		_preview.stream = stream
		_preview.volume_db = PREVIEW_SILENT_DB
		_preview.play(from / 1000.0))
	_preview_tw.tween_property(_preview, "volume_db", PREVIEW_DB + gain, PREVIEW_FADE_IN)


func _stop_preview() -> void:
	_preview_key = ""
	_wait_osz = ""
	if _preview == null or not _preview.playing:
		return
	if _preview_tw != null and _preview_tw.is_valid():
		_preview_tw.kill()
	_preview_tw = create_tween()
	_preview_tw.tween_property(_preview, "volume_db", PREVIEW_SILENT_DB, PREVIEW_FADE_OUT)
	_preview_tw.tween_callback(_preview.stop)


func _refresh_start() -> void:
	if not is_instance_valid(_start_btn):
		return
	var st := Campaign.stage_by_id(_data, _stage_id)
	var open := Campaign.stage_open(_data, _state, _stage_id)
	var have := not _local(st).is_empty()
	_start_btn.disabled = not open or not have
	if not open:
		_start_note.text = Campaign.lock_reason(_data, _state, _stage_id)
	elif not have:
		var id := int(st.get("set_id", 0))
		if _dl_current == id or _dl_queue.has(id):
			_start_note.text = tr("Map wird geladen …")
		else:
			_start_note.text = tr("Map fehlt. Download fehlgeschlagen.")
	else:
		_start_note.text = ""


func _board_text(text: String) -> void:
	for c in _board_box.get_children():
		c.queue_free()
	_put(_label(text, 13.0, UiTheme.DIM), 0, 0, _board_box.size.x / _s, 24, _board_box)


func _load_board(st: Dictionary) -> void:
	_board_token += 1
	var token := _board_token
	if _shot != "":
		_show_board(_demo_board())
		return
	var online: OnlineApi = GameSession.online
	if online == null or not online.enabled() or DisplayServer.get_name() == "headless":
		_board_text(tr("Rangliste nicht erreichbar"))
		return
	_board_text(tr("Rangliste wird geladen …"))
	online.leaderboard(str(st.mode), str(st.get("md5", "")), int(st.get("beatmap_id", 0)),
		func(ok: bool, entries: Array, _msg: String):
			if token != _board_token or not is_instance_valid(_board_box):
				return
			if not ok:
				_board_text(tr("Rangliste nicht erreichbar"))
			elif entries.is_empty():
				_board_text(tr("Noch keine Scores"))
			else:
				_show_board(entries))


## Rangliste wie im Song-Browser: Rang, runder Avatar, Name, Score, Genauigkeit.
func _show_board(entries: Array) -> void:
	for c in _board_box.get_children():
		c.queue_free()
	var w := _board_box.size.x / _s
	var me := str(Settings.profile_name)
	for i in mini(entries.size(), BOARD_ROWS):
		var e: Dictionary = entries[i]
		var y := i * 26.0
		var who := str(e.get("player", ""))
		var mine := me != "" and who == me
		var col := UiTheme.ACCENT if mine else UiTheme.TEXT
		var rank := _label(str(int(e.get("rank", i + 1))), 13.0, UiTheme.DIM)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(rank, 0, y, 18, 26, _board_box)
		var av := _avatar(who)
		_put(av, 26, y + 3, 20, 20, _board_box)
		_put(_label(who, 15.0, col), 54, y, w - 54 - 132, 26, _board_box)
		var sc := _label(UiTheme.fmt_score(int(e.get("score", 0))), 15.0, col)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(sc, w - 132, y, 72, 26, _board_box)
		var ac := _label(Campaign.acc_text(float(e.get("accuracy", 0.0))), 13.0, UiTheme.DIM)
		ac.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(ac, w - 58, y, 58, 26, _board_box)


## Runder Avatar (Initiale, bis das Bild der Website da ist), wie die Online-Rangliste.
func _avatar(who: String) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load("res://shaders/avatar_circle.gdshader")
	var circle := ColorRect.new()
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle.color = UiTheme.RAISED.lightened(0.08)
	var m := ShaderMaterial.new()
	m.shader = shader
	circle.material = m
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(circle)
	var initial := Label.new()
	initial.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.text = who.strip_edges().substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", int(_px(11.0)))
	initial.add_theme_color_override("font_color", UiTheme.TEXT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(initial)
	var api: OnlineApi = GameSession.online
	if api == null or _shot != "" or who == "":
		return slot
	api.player_avatar(who, func(tex: Texture2D):
		if tex == null or not is_instance_valid(slot):
			return
		var rect := TextureRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		var m2 := ShaderMaterial.new()
		m2.shader = shader
		rect.material = m2
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(rect))
	return slot


func _start_stage() -> void:
	var st := Campaign.stage_by_id(_data, _stage_id)
	var loc := _local(st)
	if st.is_empty() or loc.is_empty() or _shot != "" or not Campaign.stage_open(_data, _state, _stage_id):
		return
	_stop_preview()
	# Wie ein Start aus dem Song-Browser: eigene Mods, eigene Einstellungen (2D/3D, Welt ...).
	GameSession.start_campaign(_stage_id)
	GameSession.mods = Campaign.start_mods(st, Campaign.player_mods(str(st.mode), Settings.mod_sv))
	GameSession.is_replay = false
	GameSession.replay_events = []
	GameSession.replay_mode = "mania"
	GameSession.set_selection(str(loc.osz_path), int(loc.index), str(loc.version), str(loc.osu_filename), float(loc.stars))
	SceneFader.go(ScoreStore.mode_scene(str(st.mode)))


# ------------------------------------------------------------------ Downloads

## Fehlende Maps des Kapitels nacheinander laden (gleicher Weg wie der Online-Browser).
func _start_downloads() -> void:
	if _shot != "" or _lib == null:
		return
	if _dl_chapter != _chapter or (_dl_queue.is_empty() and _dl_current == 0 and _dl_failed == 0):
		if _dl_current != 0:
			_update_dl()
			return
		_dl_chapter = _chapter
		_dl_queue = Campaign.missing_sets(_chapter_dict(), _sets)
		_dl_total = _dl_queue.size()
		_dl_failed = 0
		_next_download()
	_update_dl()


func _next_download() -> void:
	_dl_current = 0
	if _dl_queue.is_empty():
		_update_dl()
		_refresh_start()
		return
	_dl_current = _dl_queue.pop_front()
	Mirror.download(_dl_current, MapLibrary.default_maps_dir())
	_update_dl()


func _update_dl(ratio: float = 0.0) -> void:
	if not is_instance_valid(_dl_label):
		return
	if _dl_current != 0:
		var done := _dl_total - _dl_queue.size() - 1
		_dl_label.text = tr("Maps laden %d / %d  ·  %d %%") % [done + 1, _dl_total, int(ratio * 100.0)]
	elif _dl_failed > 0:
		_dl_label.text = tr("%d Maps konnten nicht geladen werden. Kapitel neu öffnen.") % _dl_failed
	else:
		_dl_label.text = ""


func _on_dl_progress(set_id: int, ratio: float) -> void:
	if set_id == _dl_current:
		_update_dl(ratio)


func _on_dl_done(set_id: int, _path: String) -> void:
	if set_id != _dl_current:
		return
	_lib = MapLibrary.new()
	_lib.scan()
	_sets = _lib.mapsets
	if _view == "stages" and int(Campaign.stage_by_id(_data, _stage_id).get("set_id", -1)) == set_id:
		_prepare_stage(Campaign.stage_by_id(_data, _stage_id))
	_next_download()


func _on_dl_failed(set_id: int, _msg: String) -> void:
	if set_id != _dl_current:
		return
	_dl_failed += 1
	_next_download()


# ------------------------------------------------------------------ Harness

## Demo-Stand: Kapitel 1 bis 3 und drei Stufen von Kapitel 4 geschafft.
func _demo_state() -> Dictionary:
	var st := Campaign.new_state()
	var all := Campaign.all_stages(_data)
	for i in mini(21, all.size()):
		var s: Dictionary = all[i]
		var acc := 0.985 - (i % 5) * 0.012
		var run := {"failed": false, "accuracy": acc, "grade": "S" if acc > 0.96 else "A",
			"n_miss": i % 4, "score": 962000 - i * 9100, "max_combo": 400 + i * 11}
		Campaign.apply_run(st, s, run)
	return st


func _demo_board() -> Array:
	var names := ["Kestrel", "VYREN", "mako", "Lumen", "Ostwind", "quartz", "Reika", "tamsin"]
	var out: Array = []
	for i in names.size():
		out.append({"rank": i + 1, "player": names[i], "score": 987120 - i * 13270 - i * i * 911,
			"accuracy": 0.9931 - i * 0.0064, "grade": "SS" if i == 0 else ("S" if i < 5 else "A")})
	return out


func _save_shot(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s_%s.png" % [_shot, suffix]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT gespeichert: " + path)


## Harness: Stufe waehlen (Vorgaenger in der Testdatei als geschafft eintragen).
func _seed_run_state() -> String:
	var target := "mania-c01s1"
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-campaign-stage="):
			target = a.trim_prefix("--shot-campaign-stage=")
	var data := Campaign.for_mode(_all, Campaign.mode_of_stage(_all, target))
	for s: Dictionary in Campaign.all_stages(data):
		if str(s.id) == target:
			break
		if not Campaign.stage_cleared(_state, str(s.id)):
			Campaign.apply_run(_state, s, {"failed": false, "accuracy": 0.97, "grade": "S",
				"n_miss": 2, "score": 930000, "max_combo": 400})
	Campaign.save_state(_state)
	return target


func _run_stage_shot(prefix: String) -> void:
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix + "_stage.png")
	var st := Campaign.stage_by_id(_data, _stage_id)
	print("CAMPAIGN-RUN Stufe %s, offen %s, lokal %s, Welt-Einstellung %d, 2D %s, Mods %s" % [_stage_id,
		str(Campaign.stage_open(_data, _state, _stage_id)), str(not _local(st).is_empty()), Settings.world_theme,
		str(Settings.playfield_2d), str(Campaign.start_mods(st, Campaign.player_mods(str(st.mode), Settings.mod_sv)))])
	_start_stage()
	if not GameSession.campaign_active():
		push_error("Stufe startet nicht")
		get_tree().quit(2)


func _run_shots() -> void:
	await get_tree().create_timer(1.6).timeout
	_show_info(3)
	await get_tree().create_timer(1.2).timeout
	await _save_shot("path")
	_show_info(4)
	await get_tree().create_timer(1.6).timeout
	await _save_shot("path_locked")
	_chapter = 3
	_stage_id = "mania-c04s4"
	_view = "stages"
	_rebuild()
	await get_tree().create_timer(2.4).timeout
	await _save_shot("stage")
	_select_stage("mania-c04s6")
	await get_tree().create_timer(1.6).timeout
	await _save_shot("locked")
	var st := Campaign.stage_by_id(_data, "mania-c04s3")
	var rs := ResultsScreen.new()
	add_child(rs)
	rs.show_results({
		"is_fail": false,
		"s": {"n_max": 612, "n300": 201, "n200": 38, "n100": 9, "n50": 2, "n_miss": 2,
			"max_combo": 431, "accuracy": 0.9712, "grade": "S", "score": 941870, "failed": false},
		"pp": 96.2, "new_best": true, "can_clip": false, "can_share": false,
		"title": str(st.get("title", "")), "artist": str(st.get("artist", "")), "version": str(st.get("diff", "")),
		"player": "VYREN", "date": "2026-11-13T21:10:00", "mode": str(st.get("mode", "")),
		"campaign": {"stage": "mania-c04s3", "state": _state},
	})
	await get_tree().create_timer(3.0).timeout
	await _save_shot("result")
	get_tree().quit(0)
