extends Control

## Kampagnen-Szene: Kapitelweg durch die 13 Welten (Ansicht "path") und Stufenansicht
## eines Kapitels (Ziele, Bestwert, Online-Rangliste der Map). Logik: Campaign.
## Entwurf auf 1280x720, gleichmaessig skaliert. Graphit + Bernstein, flache Flaechen.
##
## Harness: --shot-campaign=<Praefix> speichert <Praefix>_path.png, _stage.png und
## _result.png mit Demo-Stand (ohne Netz, ohne Schreiben) und beendet sich.
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
const BOARD_ROWS := 8

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

var _info_title: Label
var _info_sub: Label
var _info_btn: Button
var _info_lock: Label
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

static var _thumbs: Dictionary = {}


class Plate extends Button:
	var tex: Texture2D
	var col := Color(0.16, 0.20, 0.26)
	var locked := false
	var current := false
	var img_h := 86.0
	var u := 1.0

	func _draw() -> void:
		var r := Rect2(0, 0, size.x, img_h)
		if tex != null:
			var ts := tex.get_size()
			var want := r.size.x / r.size.y
			var rw := ts.x
			var rh := rw / want
			if rh > ts.y:
				rh = ts.y
				rw = rh * want
			draw_texture_rect_region(tex, r, Rect2((ts.x - rw) * 0.5, (ts.y - rh) * 0.5, rw, rh))
		else:
			draw_rect(r, col)
			for i in 3:
				var y := img_h * (0.58 + i * 0.13)
				draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.05 + 0.02 * i), maxf(u, 1.0))
		if locked:
			draw_rect(r, Color(UiTheme.BG.r, UiTheme.BG.g, UiTheme.BG.b, 0.74))
		draw_rect(r, UiTheme.LINE, false, 1.0)
		if current:
			draw_rect(Rect2(0, img_h - 3.0 * u, size.x, 3.0 * u), UiTheme.ACCENT)
		if not disabled and (has_focus() or is_hovered()):
			draw_rect(r.grow(2.0 * u), Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.55), false, maxf(u, 1.0))


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
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	if _shot == "" and DisplayServer.get_name() != "headless":
		_lib = MapLibrary.new()
		_lib.scan()
		_sets = _lib.mapsets
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
	_rebuild()


func _back() -> void:
	if _view == "stages":
		_view = "path"
		_rebuild()
	else:
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


func _caption(text: String) -> Label:
	var l := _label(text, 12.0, UiTheme.DIM, true)
	l.uppercase = true
	return l


func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	UiTheme.style_button(b, primary, 4)
	b.add_theme_font_size_override("font_size", int(_px(15.0)))
	b.pressed.connect(cb)
	return b


func _line(x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(r, x, y, w, h)
	if w <= 1.0:
		r.size.x = maxf(_px(1.0), 1.0)
	if h <= 1.0:
		r.size.y = maxf(_px(1.0), 1.0)
	return r


func _num(v: float, decimals: int) -> String:
	return UiTheme.fmt_num(v, decimals)


func _acc(v: float) -> String:
	return _num(v * 100.0, 2) + (" %" if UiTheme.is_german() else "%")


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
	_info_btn = null
	_start_btn = null
	_dl_label = null
	_board_box = null
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
		tab.tooltip_text = tr("Kommt bald") if soon else ""
		tab.add_theme_font_override("font", _head_font)
		tab.add_theme_font_size_override("font_size", int(_px(14.0)))
		tab.add_theme_color_override("font_color", UiTheme.TEXT if m == _mode else UiTheme.DIM)
		tab.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		tab.add_theme_color_override("font_disabled_color", Color(UiTheme.DIM.r, UiTheme.DIM.g, UiTheme.DIM.b, 0.45))
		for sb in ["normal", "hover", "pressed", "disabled"]:
			tab.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		tab.pressed.connect(_pick_mode.bind(m))
		_put(tab, tx, 28, 84, 36)
		if m == _mode:
			_line(tx + 14.0, 62, 56, 2, UiTheme.ACCENT)
		tx += 86.0
	var total := _label("", 14.0, UiTheme.DIM)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.text = "%s   ·   %s" % [
		tr("%d / %d Sterne") % [Campaign.total_stars(_data, _state), Campaign.max_stars(_data)],
		tr("%s Punkte") % UiTheme.fmt_score(Campaign.total_points(_data, _state))]
	_put(total, 712, 28, 520, 36)


# ------------------------------------------------------------------ Kapitelweg

func _plate_pos(i: int) -> Vector2:
	var x0 := (BASE.x - (COLS * PLATE_W + (COLS - 1) * PLATE_GAP)) * 0.5
	@warning_ignore("integer_division")
	var row := i / COLS
	var col := i % COLS
	if row % 2 == 1:
		col = COLS - 1 - col
	return Vector2(x0 + col * (PLATE_W + PLATE_GAP), 176.0 + row * (PLATE_H + ROW_GAP))


func _build_path() -> void:
	var chs := Campaign.chapters(_data)
	_put(_label("%s  ·  %s" % [tr("Kampagne"), ScoreStore.mode_label(_mode)], 34.0, UiTheme.TEXT, true), 48, 80, 900, 46)
	_put(_label(tr("%d Welten · %d Stufen · gleiche Maps für alle") % [chs.size(), Campaign.all_stages(_data).size()],
		14.0, UiTheme.DIM), 48, 126, 700, 24)
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
			_line(a.x + PLATE_W * 0.5 - 1.0, a.y + PLATE_H - 6.0, 2.0, ROW_GAP + 6.0, col)
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
		for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
			p.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
		var pos := _plate_pos(i)
		_put(p, pos.x, pos.y, PLATE_W, PLATE_H)
		p.pressed.connect(_open_chapter.bind(i))
		p.mouse_entered.connect(_show_info.bind(i))
		p.focus_entered.connect(_show_info.bind(i))
		var tcol := UiTheme.TEXT if open else UiTheme.DIM
		_put(_label("%02d" % (i + 1), 12.0, UiTheme.DIM, true), 0, PLATE_IMG_H + 8, 24, 22, p)
		_put(_label(Campaign.world_label(str(ch.world)), 16.0, tcol, true), 24, PLATE_IMG_H + 8, PLATE_W - 24, 22, p)
		var st := _label("", 12.0, UiTheme.DIM)
		if not open:
			st.text = tr("Gesperrt")
		else:
			st.text = "%d / %d" % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)]
			var one := CampaignStars.make([Campaign.chapter_stars(ch, _state) > 0], _px(11.0))
			p.add_child(one)
			one.position = Vector2(0, _px(PLATE_IMG_H + 36.0))
		_put(st, 0 if not open else 17, PLATE_IMG_H + 31, 80, 20, p)
		if done:
			var ok := _label(tr("Geschafft"), 12.0, UiTheme.GOOD)
			ok.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_put(ok, PLATE_W - 84, PLATE_IMG_H + 31, 84, 20, p)
		if i == _chapter:
			focus_plate = p
	# Info-Zeile zum gewaehlten Kapitel.
	_line(48, 566, BASE.x - 96, 1, UiTheme.LINE)
	_info_title = _label("", 22.0, UiTheme.TEXT, true)
	_put(_info_title, 48, 584, 760, 32)
	_info_sub = _label("", 14.0, UiTheme.DIM)
	_put(_info_sub, 48, 618, 760, 24)
	_info_lock = _label("", 14.0, UiTheme.DIM)
	_info_lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(_info_lock, 780, 590, 452, 44)
	_info_btn = _button(tr("Kapitel öffnen"), true, func(): _open_chapter(_hover_chapter))
	_put(_info_btn, 1012, 590, 220, 46)
	_show_info(_chapter)
	if focus_plate != null and _shot == "":
		focus_plate.grab_focus.call_deferred()
	_fill_thumbs()


func _show_info(i: int) -> void:
	var chs := Campaign.chapters(_data)
	if i < 0 or i >= chs.size() or not is_instance_valid(_info_title):
		return
	_hover_chapter = i
	var ch: Dictionary = chs[i]
	var band: Array = ch.get("stars", [0, 0])
	_info_title.text = "%s  ·  %s" % [tr("Kapitel %d") % (i + 1), Campaign.world_label(str(ch.world))]
	_info_sub.text = "%s   ·   %s   ·   %s" % [
		tr("Schwerpunkt %s") % ScoreStore.mode_label(str(ch.focus)),
		tr("Schwierigkeit %s bis %s") % [_num(float(band[0]), 1), _num(float(band[1]), 1)],
		tr("%d / %d Sterne") % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)]]
	var open := Campaign.chapter_open(_data, _state, i)
	_info_btn.visible = open
	_info_lock.visible = not open
	if not open:
		_info_lock.text = tr("Erst den Boss von Kapitel %d schaffen") % i


## Weltbilder nach dem ersten Bild einsetzen (ein Panorama je Frame).
func _fill_thumbs() -> void:
	var chs := Campaign.chapters(_data)
	for i in chs.size():
		var world := str((chs[i] as Dictionary).world)
		if not _thumbs.has(world):
			await get_tree().process_frame
			if not is_inside_tree():
				return
		var t := world_thumb(world)
		var p := _root.get_node_or_null("Chapter%02d" % (i + 1)) as Plate
		if p != null and t != null and not p.is_queued_for_deletion():
			p.tex = t
			p.queue_redraw()


func _open_chapter(i: int) -> void:
	if not Campaign.chapter_open(_data, _state, i):
		return
	_chapter = i
	_stage_id = ""
	_view = "stages"
	_rebuild()


# ------------------------------------------------------------------ Stufen

func _chapter_dict() -> Dictionary:
	var chs := Campaign.chapters(_data)
	return chs[clampi(_chapter, 0, chs.size() - 1)] if not chs.is_empty() else {}


func _local(stage: Dictionary) -> Dictionary:
	if _shot != "":
		return {"osz_path": "shot", "index": 0}
	return Campaign.find_local(stage, _sets)


func _build_stages() -> void:
	var ch := _chapter_dict()
	var sts: Array = ch.get("stages", [])
	if _stage_id == "" or Campaign.chapter_index_of(_data, _stage_id) != _chapter:
		_stage_id = str((sts[0] as Dictionary).id)
		for s: Dictionary in sts:
			if Campaign.stage_open(_data, _state, str(s.id)):
				_stage_id = str(s.id)
	# Linke Spalte: Welt, Kapitel, Stufenliste.
	var head := Plate.new()
	head.disabled = true
	head.focus_mode = Control.FOCUS_NONE
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.u = _s
	head.img_h = _px(72.0)
	head.col = _world_color(str(ch.world))
	head.tex = world_thumb(str(ch.world))
	for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
		head.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	_put(head, 48, 84, 500, 72)
	_put(_caption(tr("Kapitel %d") % (_chapter + 1)), 48, 166, 200, 18)
	_put(_label(Campaign.world_label(str(ch.world)), 26.0, UiTheme.TEXT, true), 48, 184, 340, 34)
	var cs := _label(tr("%d / %d Sterne") % [Campaign.chapter_stars(ch, _state), Campaign.chapter_max_stars(ch)],
		14.0, UiTheme.DIM)
	cs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_put(cs, 348, 188, 200, 28)
	var y := 232.0
	var focus_row: Button = null
	for i in sts.size():
		var st: Dictionary = sts[i]
		var id := str(st.id)
		var open := Campaign.stage_open(_data, _state, id)
		var row := Button.new()
		row.name = "Stage" + id
		row.toggle_mode = false
		var sel := id == _stage_id
		var box := UiTheme.solid_box(UiTheme.SURFACE if sel else Color(0, 0, 0, 0), 2)
		var hov := UiTheme.solid_box(UiTheme.RAISED if not sel else UiTheme.SURFACE, 2)
		row.add_theme_stylebox_override("normal", box)
		row.add_theme_stylebox_override("hover", hov)
		row.add_theme_stylebox_override("pressed", hov)
		row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_put(row, 48, y, 500, 54)
		row.pressed.connect(_select_stage.bind(id))
		if sel:
			var mark := ColorRect.new()
			mark.color = UiTheme.ACCENT
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_put(mark, 0, 10, 3, 34, row)
			focus_row = row
		var a := 1.0 if open else 0.42
		var num := _label("B" if bool(st.get("boss", false)) else str(i + 1), 20.0,
			UiTheme.ACCENT if bool(st.get("boss", false)) and open else UiTheme.DIM, true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.modulate.a = a
		_put(num, 8, 0, 40, 54, row)
		var title := _label("%s – %s" % [str(st.get("artist", "")), str(st.get("title", ""))], 15.0, UiTheme.TEXT)
		title.modulate.a = a
		_put(title, 54, 7, 352, 22, row)
		var sub_t := "%s   ·   %s" % [ScoreStore.mode_label(str(st.mode)), Campaign.length_text(int(st.get("length_s", 0)))]
		if not (st.get("mods", []) as Array).is_empty():
			sub_t += "   ·   " + " ".join(PackedStringArray(st.mods))
		if not open:
			sub_t = tr("Gesperrt")
		var sub := _label(sub_t, 12.0, UiTheme.DIM)
		sub.modulate.a = maxf(a, 0.7)
		_put(sub, 54, 28, 352, 20, row)
		var stars := CampaignStars.make(Campaign.met_of(_state, id), _px(14.0))
		stars.modulate.a = a
		row.add_child(stars)
		stars.position = Vector2(_px(500.0 - 16.0) - stars.width(), (_px(54.0) - stars.size.y) * 0.5)
		_line(48, y + 54.0 + 2.0, 500, 1, Color(UiTheme.TEXT.r, UiTheme.TEXT.g, UiTheme.TEXT.b, 0.06))
		y += 58.0
	_dl_label = _label("", 13.0, UiTheme.DIM)
	_put(_dl_label, 48, y + 10.0, 500, 22)
	_line(568, 84, 1, 552, UiTheme.LINE)
	_build_detail()
	if focus_row != null and _shot == "":
		focus_row.grab_focus.call_deferred()
	_start_downloads()


func _select_stage(id: String) -> void:
	if id == _stage_id:
		return
	_stage_id = id
	_rebuild()


func _build_detail() -> void:
	var st := Campaign.stage_by_id(_data, _stage_id)
	if st.is_empty():
		return
	var x := 596.0
	var w := BASE.x - 48.0 - x
	var idx := Campaign.stage_index_of(_data, _stage_id)
	var open := Campaign.stage_open(_data, _state, _stage_id)
	_put(_caption("%s  ·  %s" % [Campaign.stage_label(st, idx), ScoreStore.mode_label(str(st.mode))]), x, 84, w, 18)
	_put(_label(str(st.get("title", "")), 26.0, UiTheme.TEXT, true), x, 104, w, 34)
	_put(_label("%s   ·   %s   ·   %s" % [str(st.get("artist", "")), str(st.get("diff", "")),
		tr("Map von %s") % str(st.get("creator", ""))], 14.0, UiTheme.DIM), x, 138, w, 22)
	var meta := "%s   ·   %s   ·   %d BPM" % [tr("Schwierigkeit %s") % _num(float(st.get("map_stars", 0.0)), 2),
		Campaign.length_text(int(st.get("length_s", 0))), int(st.get("bpm", 0))]
	for m: Variant in st.get("mods", []):
		meta += "   ·   " + (tr("Mod %s") % str(m))
	_put(_label(meta, 14.0, UiTheme.DIM), x, 160, w, 22)
	# Ziele
	_put(_caption(tr("Ziele")), x, 202, 200, 18)
	var met := Campaign.met_of(_state, _stage_id)
	var goals: Array = st.get("goals", [])
	for i in goals.size():
		var gy := 226.0 + i * 28.0
		var star := CampaignStars.make([met[i]], _px(15.0))
		_root.add_child(star)
		star.position = _origin + Vector2(_px(x), _px(gy + 5.0))
		_put(_label(Campaign.goal_name(i), 14.0, UiTheme.DIM), x + 28, gy, 110, 26)
		_put(_label(Campaign.goal_text(goals[i]), 15.0, UiTheme.TEXT if bool(met[i]) or i == 0 else UiTheme.DIM.lightened(0.25)),
			x + 142, gy, w - 142, 26)
	# Bestwert
	_put(_caption(tr("Bestwert")), x, 322, 200, 18)
	var e := Campaign.entry(_state, _stage_id)
	var best := tr("Noch nicht gespielt")
	var has_best := e.has("score")
	if has_best:
		best = "%s   ·   %s   ·   %s" % [UiTheme.fmt_score(int(e.score)), _acc(float(e.get("accuracy", 0.0))), str(e.get("grade", ""))]
	_put(_label(best, 18.0 if has_best else 14.0, UiTheme.TEXT if has_best else UiTheme.DIM, has_best), x, 342, w, 28)
	# Rangliste der Map
	_put(_caption(tr("Rangliste")), x, 392, 200, 18)
	_board_box = Control.new()
	_board_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_put(_board_box, x, 414, w, BOARD_ROWS * 24.0)
	_load_board(st)
	# Start
	_start_btn = _button(tr("Stufe starten"), true, _start_stage)
	_start_btn.name = "Start"
	_put(_start_btn, x, 624, 220, 46)
	_start_note = _label("", 13.0, UiTheme.DIM)
	_put(_start_note, x + 236, 624, w - 236, 46)
	_refresh_start(open)


func _refresh_start(open: bool = true) -> void:
	if not is_instance_valid(_start_btn):
		return
	var st := Campaign.stage_by_id(_data, _stage_id)
	open = Campaign.stage_open(_data, _state, _stage_id)
	var have := not _local(st).is_empty()
	_start_btn.disabled = not open or not have
	if not open:
		_start_note.text = tr("Erst die Stufe davor schaffen")
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
	_put(_label(text, 14.0, UiTheme.DIM), 0, 0, 500, 24, _board_box)


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


func _show_board(entries: Array) -> void:
	for c in _board_box.get_children():
		c.queue_free()
	var w := _board_box.size.x / _s
	var me := str(Settings.profile_name)
	for i in mini(entries.size(), BOARD_ROWS):
		var e: Dictionary = entries[i]
		var y := i * 24.0
		var mine := me != "" and str(e.get("player", "")) == me
		var col := UiTheme.ACCENT if mine else UiTheme.TEXT
		var rank := _label(str(int(e.get("rank", i + 1))), 13.0, UiTheme.DIM)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(rank, 0, y, 26, 24, _board_box)
		_put(_label(str(e.get("player", "")), 14.0, col), 40, y, w - 300, 24, _board_box)
		var sc := _label(UiTheme.fmt_score(int(e.get("score", 0))), 14.0, col)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(sc, w - 250, y, 110, 24, _board_box)
		var ac := _label(_acc(float(e.get("accuracy", 0.0))), 13.0, UiTheme.DIM)
		ac.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(ac, w - 130, y, 80, 24, _board_box)
		var gr := _label(str(e.get("grade", "")), 13.0, UiTheme.DIM, true)
		gr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_put(gr, w - 40, y, 40, 24, _board_box)


func _start_stage() -> void:
	var st := Campaign.stage_by_id(_data, _stage_id)
	var loc := _local(st)
	if st.is_empty() or loc.is_empty() or _shot != "" or not Campaign.stage_open(_data, _state, _stage_id):
		return
	var mods := {}
	for m: Variant in st.get("mods", []):
		mods[str(m)] = true
	GameSession.start_campaign(_stage_id, str(_chapter_dict().get("world", "")))
	GameSession.mods = mods
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
	_next_download()


func _on_dl_failed(set_id: int, _msg: String) -> void:
	if set_id != _dl_current:
		return
	_dl_failed += 1
	_next_download()


# ------------------------------------------------------------------ Harness

func _demo_state() -> Dictionary:
	var st := Campaign.new_state()
	var all := Campaign.all_stages(_data)
	for i in mini(14, all.size()):
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
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(prefix + "_stage.png")
	var st := Campaign.stage_by_id(_data, _stage_id)
	print("CAMPAIGN-RUN Stufe %s, offen %s, lokal %s, Welt-Einstellung %d" % [_stage_id,
		str(Campaign.stage_open(_data, _state, _stage_id)), str(not _local(st).is_empty()), Settings.world_theme])
	_start_stage()
	if not GameSession.campaign_active():
		push_error("Stufe startet nicht")
		get_tree().quit(2)


func _run_shots() -> void:
	await get_tree().create_timer(1.2).timeout
	await _save_shot("path")
	_chapter = 2
	_stage_id = "mania-c03s2"
	_view = "stages"
	_rebuild()
	await get_tree().create_timer(0.6).timeout
	await _save_shot("stage")
	var st := Campaign.stage_by_id(_data, "mania-c03s3")
	var rs := ResultsScreen.new()
	add_child(rs)
	rs.show_results({
		"is_fail": false,
		"s": {"n_max": 612, "n300": 201, "n200": 38, "n100": 9, "n50": 2, "n_miss": 2,
			"max_combo": 431, "accuracy": 0.9712, "grade": "S", "score": 941870, "failed": false},
		"pp": 96.2, "new_best": true, "can_clip": false, "can_share": false,
		"title": str(st.get("title", "")), "artist": str(st.get("artist", "")), "version": str(st.get("diff", "")),
		"player": "VYREN", "date": "2026-11-13T21:10:00", "mode": str(st.get("mode", "")),
		"campaign": {"stage": "mania-c03s3", "state": _state},
	})
	await get_tree().create_timer(3.0).timeout
	await _save_shot("result")
	get_tree().quit(0)
