class_name MarathonPanel
extends Control

## Marathon-Auswahl (Song-Browser, Knopf "Marathon" in der Mods-Zeile; das
## Hauptmenue oeffnet sie ueber browser_state "open_marathon"):
##   Quelle (ganze Bibliothek oder eine Sammlung), Laenge (3/5/8 Maps oder
##   5/10/20 Minuten), Ziel-Sterne (+- 0,3), Vorschau der Reihenfolge mit der
##   Art jedes Uebergangs, Neu mischen, Start; darunter die lokale Rangliste der
##   gewaehlten Laenge mit Replays.
## Stil wie der Song-Browser: Graphit-Flaechen, Haarlinien, Bernstein nur fuer
## die aktive Wahl und den Start-Knopf.

signal start_requested(plan: Dictionary)
signal replay_requested(data: Dictionary)
signal closed

const W := 760.0
const ROW_H := 34.0

var _sets: Array = []
var _anchor := ""
var _stars := 3.0
var _length := "n3"
var _source := ""  ## "" = ganze Bibliothek, sonst Sammlungsname
var _seed := 1
var _chain: Array = []
var _bpm_cache := {}

var _len_btns := {}
var _src_opt: OptionButton
var _stars_lbl: Label
var _list: VBoxContainer
var _hint: Label
var _start_btn: Button
var _board: VBoxContainer
var _board_cap: Label


## sets = MapSet-Liste der Bibliothek, anchor = gewaehlte Map (osz), stars = Sterne
## der gewaehlten Diff (Ziel), collections = Sammlungsnamen.
func setup(sets: Array, anchor: String, stars: float, collections: Array) -> void:
	_sets = sets
	_anchor = anchor
	_stars = snappedf(stars if stars > 0.0 else 3.0, 0.1)
	_seed = int(Time.get_unix_time_from_system()) % 100000
	_collections = collections
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if shot_dir() != "":
		_seed = 7
		_run_shots.call_deferred()
	_build()


var _collections: Array = []


## Harness --shot-marathon=<ordner>: Auswahl auf Deutsch und Englisch als PNG.
static func shot_dir() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-marathon="):
			return a.trim_prefix("--shot-marathon=")
	return ""


func _run_shots() -> void:
	for lang in ["de", "en"]:
		TranslationServer.set_locale(lang)
		_build()
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var out := shot_dir().path_join("marathon_panel_%s.png" % lang)
		get_viewport().get_texture().get_image().save_png(out)
		print("SHOT gespeichert: " + out)
	get_tree().quit(0)


func _build() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_len_btns.clear()
	var collections := _collections
	var back := UiTheme.modal_backdrop(self)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(W, 0)
	var pb := UiTheme.solid_box(UiTheme.SURFACE, 14)
	pb.set_border_width_all(1)
	pb.border_color = UiTheme.LINE
	pb.content_margin_left = 28
	pb.content_margin_right = 28
	pb.content_margin_top = 24
	pb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", pb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	vb.add_child(UiTheme.modal_header("Marathon", close))
	var sub := _label(tr("Several maps in a row, one HP bar, one combo. Each song comes in on the beat of the last one."), 13, UiTheme.DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)

	# Quelle + Sterne in einer Zeile.
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	vb.add_child(row1)
	row1.add_child(_caption(tr("SOURCE")))
	_src_opt = OptionButton.new()
	_src_opt.focus_mode = Control.FOCUS_NONE
	_src_opt.custom_minimum_size = Vector2(240, ROW_H)
	_src_opt.add_item(tr("Whole library"))
	_src_opt.set_item_metadata(0, "")
	for c in collections:
		_src_opt.add_item(str(c))
		_src_opt.set_item_metadata(_src_opt.item_count - 1, str(c))
	for k in _src_opt.item_count:
		if str(_src_opt.get_item_metadata(k)) == _source:
			_src_opt.select(k)
	_src_opt.item_selected.connect(func(i: int):
		_source = str(_src_opt.get_item_metadata(i))
		_rebuild())
	row1.add_child(_src_opt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(sp)
	row1.add_child(_caption(tr("STARS")))
	var minus := _ghost("−", func(): _set_stars(_stars - 0.1))
	minus.custom_minimum_size = Vector2(ROW_H, ROW_H)
	row1.add_child(minus)
	_stars_lbl = _label("", 15, UiTheme.TEXT)
	_stars_lbl.custom_minimum_size = Vector2(110, ROW_H)
	_stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row1.add_child(_stars_lbl)
	var plus := _ghost("+", func(): _set_stars(_stars + 0.1))
	plus.custom_minimum_size = Vector2(ROW_H, ROW_H)
	row1.add_child(plus)

	# Laenge.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vb.add_child(row2)
	row2.add_child(_caption(tr("LENGTH")))
	for key in MarathonPlan.all_length_keys():
		var b := _toggle(MarathonRun.length_text(key))
		b.pressed.connect(func():
			_length = key
			_rebuild())
		row2.add_child(b)
		_len_btns[key] = b

	vb.add_child(UiTheme.hairline())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	vb.add_child(_list)
	_hint = _label("", 13, UiTheme.DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_hint)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	vb.add_child(row3)
	var shuffle := _ghost(tr("Shuffle"), func():
		_seed += 1
		_rebuild())
	shuffle.custom_minimum_size = Vector2(140, 44)
	row3.add_child(shuffle)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(sp2)
	_start_btn = Button.new()
	_start_btn.text = tr("Start marathon")
	_start_btn.custom_minimum_size = Vector2(220, 44)
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(_start_btn, true, 10)
	_start_btn.pressed.connect(_on_start)
	row3.add_child(_start_btn)

	vb.add_child(UiTheme.hairline())
	_board_cap = _caption("")
	vb.add_child(_board_cap)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 2)
	vb.add_child(_board)
	_rebuild()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	# Offen: keine Taste erreicht den Browser dahinter.
	get_viewport().set_input_as_handled()
	if event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_start()


func _set_stars(v: float) -> void:
	_stars = clampf(snappedf(v, 0.1), 0.5, 12.0)
	_rebuild()


## Auswahl neu berechnen (Quelle, Laenge, Sterne oder Seed geaendert).
func _rebuild() -> void:
	_stars_lbl.text = "★ %s ± %s" % [UiTheme.fmt_num(_stars, 1), UiTheme.fmt_num(MarathonPlan.STAR_TOL, 1)]
	for k in _len_btns:
		_style_toggle(_len_btns[k], k == _length)
	var files: Array = []
	if _source != "":
		files = CollectionStore.maps_in(_source)
	var cands := MarathonPlan.candidates_from_sets(_sets, _stars, true, files)
	var pool := MarathonPlan.filter_pool(cands, _stars)
	_chain = MarathonPlan.pick(pool, _length, _seed, _anchor)
	# Tempo fehlt in den Bibliotheksdaten: aus der Map lesen, dann neu ordnen.
	var filled := false
	for c in _chain:
		if float(c.get("bpm", 0.0)) <= 0.0:
			c["bpm"] = _bpm_of(c)
			filled = true
	if filled:
		_chain = MarathonPlan.order(_chain)
	_fill_list()
	var lk := MarathonPlan.parse_length_key(_length)
	var need := int(lk.value) if str(lk.kind) == MarathonPlan.KIND_COUNT else 2
	var enough := _chain.size() >= need
	if str(lk.kind) == MarathonPlan.KIND_MINUTES and enough:
		var tot := 0.0
		for c in _chain:
			tot += float(c.duration_ms)
		enough = tot >= float(lk.value) * 60000.0 * 0.9
	_start_btn.disabled = not enough
	if not enough:
		_hint.text = tr("Not enough 4K maps at ★ %s ± %s (found %d). Try other stars or the whole library.") % [
			UiTheme.fmt_num(_stars, 1), UiTheme.fmt_num(MarathonPlan.STAR_TOL, 1), pool.size()]
	else:
		var tot_ms := 0.0
		for c in _chain:
			tot_ms += float(c.duration_ms)
		_hint.text = tr("%d maps · about %d min · local ranking per length, not sent online") % [
			_chain.size(), maxi(1, roundi(tot_ms / 60000.0))]
	_fill_board()


func _bpm_of(c: Dictionary) -> float:
	var key := "%s|%s" % [str(c.osz), str(c.version)]
	if _bpm_cache.has(key):
		return float(_bpm_cache[key])
	var bpm := 0.0
	var imp := OszImporter.import(str(c.osz))
	if bool(imp.get("ok", false)):
		for d in imp.difficulties:
			if d.beatmap.version_name() == str(c.version):
				bpm = MapLibrary.main_bpm(d.beatmap)
				break
	_bpm_cache[key] = bpm
	return bpm


func _fill_list() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	for i in _chain.size():
		var c: Dictionary = _chain[i]
		if i > 0:
			_list.add_child(_transition_row(_chain[i - 1], c))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		r.custom_minimum_size = Vector2(0, ROW_H)
		var n := _label("%d" % (i + 1), 13, UiTheme.DIM)
		n.custom_minimum_size = Vector2(22, 0)
		r.add_child(n)
		var t := _label("%s — %s" % [str(c.get("artist", "")), str(c.get("title", ""))], 15, UiTheme.TEXT)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r.add_child(t)
		var v := _label(str(c.get("version", "")), 13, UiTheme.DIM)
		v.custom_minimum_size = Vector2(150, 0)
		v.clip_text = true
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r.add_child(v)
		r.add_child(_num("★ " + UiTheme.fmt_num(float(c.stars), 2), 64))
		var bpm := float(c.get("bpm", 0.0))
		r.add_child(_num(tr("%s BPM") % UiTheme.fmt_num(bpm, 0) if bpm > 0.0 else "–", 80))
		var s := int(float(c.duration_ms) / 1000.0)
		r.add_child(_num("%d:%02d" % [s / 60, s % 60], 48))
		_list.add_child(r)


## Zwischenzeile: wie der Uebergang klingt (Tempo-Angleich in %, Doppel-/Halbtakt
## oder harter Schnitt auf dem Takt).
func _transition_row(a: Dictionary, b: Dictionary) -> Control:
	var tm := MarathonPlan.tempo_match(float(a.get("bpm", 0.0)), float(b.get("bpm", 0.0)))
	var txt := ""
	if bool(tm.ok):
		var pct := (float(tm.rate) - 1.0) * 100.0
		txt = tr("mix on the beat, tempo %s %%") % ("%s%s" % ["+" if pct >= 0.0 else "−",
			UiTheme.fmt_num(absf(pct), 1)])
		if float(tm.m) != 1.0:
			txt += "  ·  " + (tr("double time") if float(tm.m) > 1.0 else tr("half time"))
	else:
		txt = tr("cut on the beat (tempo too far apart)")
	var l := _label("      ↓  " + txt, 12, UiTheme.DIM)
	l.modulate.a = 0.85
	return l


func _fill_board() -> void:
	for ch in _board.get_children():
		ch.queue_free()
	_board_cap.text = tr("BEST RUNS · %s") % MarathonRun.length_text(_length).to_upper()
	var top := MarathonStore.top(_length, 5)
	if top.is_empty():
		_board.add_child(_label(tr("No runs at this length yet."), 13, UiTheme.DIM))
		return
	for k in top.size():
		var e: Dictionary = top[k]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		r.custom_minimum_size = Vector2(0, 30)
		var rank := _label("#%d" % (k + 1), 14, UiTheme.ACCENT if k == 0 else UiTheme.DIM)
		rank.custom_minimum_size = Vector2(34, 0)
		r.add_child(rank)
		r.add_child(_num(UiTheme.fmt_score(int(e.get("score", 0))), 96))
		r.add_child(_num(UiTheme.fmt_pct(float(e.get("accuracy", 0.0)) * 100.0), 74))
		r.add_child(_num(str(e.get("grade", "")), 30))
		var maps: Array = e.get("maps", [])
		var mt := _label("  ›  ".join(maps), 13, UiTheme.DIM)
		mt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mt.clip_text = true
		mt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r.add_child(mt)
		r.add_child(_num(UiTheme.fmt_date(str(e.get("date", ""))), 90))
		var rid := str(e.get("replay", ""))
		if MarathonStore.has_replay(rid):
			var w := _ghost(tr("Replay"), func():
				var data := MarathonStore.load_replay(rid)
				if not data.is_empty():
					replay_requested.emit(data))
			w.custom_minimum_size = Vector2(84, 28)
			r.add_child(w)
		_board.add_child(r)


func _on_start() -> void:
	if _start_btn.disabled or _chain.is_empty():
		return
	var src := "auto" if _source == "" else "coll:" + _source
	var plan := MarathonRun.new_plan(_chain, _length, _seed, src, _stars)
	start_requested.emit(plan)


# --- Bausteine -----------------------------------------------------------------------

func _label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _num(text: String, w: float) -> Label:
	var l := _label(text, 14, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_override("font", UiTheme.heading_font(0))
	return l


func _caption(text: String) -> Label:
	var l := _label(text, 11, UiTheme.DIM)
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.custom_minimum_size = Vector2(64, ROW_H)
	return l


func _ghost(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(b, 10)
	b.pressed.connect(on_press)
	return b


func _toggle(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.add_theme_font_size_override("font_size", 14)
	UiTheme._attach_sounds(b)
	return b


func _style_toggle(b: Button, active: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(UiTheme.R_MAX)
		sb.set_border_width_all(1)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		var hover: bool = st == "hover"
		if active:
			sb.bg_color = Color(UiTheme.ACCENT, 0.24 if hover else 0.16)
			sb.border_color = Color(UiTheme.ACCENT, 0.60)
		else:
			sb.bg_color = Color(1, 1, 1, 0.09 if hover else 0.04)
			sb.border_color = Color(1, 1, 1, 0.22 if hover else 0.12)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := UiTheme.ACCENT if active else UiTheme.DIM
	for fc in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(fc, fg)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT if active else UiTheme.TEXT)
