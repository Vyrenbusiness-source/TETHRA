class_name TournamentEnd
extends Control

## Endbild des Turniers: Podium Top 3, Tabelle aller Spieler (Punkte, Siege,
## Acc, Gesamtscore, beste Map), Map-Liste mit Cover, Sieger und den Ergebnissen
## jedes Spielers (Platz, Score, Acc, Kombo, Fail). Das Bild ist fest 1920x1080 und wird in einem eigenen
## SubViewport gezeichnet; die Anzeige skaliert es, "Bild speichern" schreibt
## genau dieses Bild als PNG nach user://tournaments/.

signal back_to_room

const W := 1920
const H := 1080
const TEXT := UiTheme.TEXT
const DIM := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const DIR := "user://tournaments"

var t: Tournament
var title_text := "Turnier"
var my_id := 1
var is_host := false
var harness := false
var library: MapLibrary = null

var _covers: Dictionary = {}

var _vp: SubViewport
var _info: Label
var _saved_path := ""
var _open_btn: Button


func _init(tour: Tournament, room_title: String = "") -> void:
	t = tour
	if room_title != "":
		title_text = room_title
	name = "TournamentEnd"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.02, 0.02, 0.035)
	add_child(back)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_right = -24
	col.offset_top = 16
	col.offset_bottom = -16
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var canvas := _build_canvas()
	_vp.add_child(canvas)
	var tr := TextureRect.new()
	tr.texture = _vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tr)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	col.add_child(bar)
	var save := Button.new()
	save.text = "Bild speichern"
	save.custom_minimum_size = Vector2(190, 46)
	UiTheme.style_button(save, true)
	save.pressed.connect(func(): save_png())
	bar.add_child(save)
	_open_btn = Button.new()
	_open_btn.text = "Ordner öffnen"
	_open_btn.custom_minimum_size = Vector2(170, 46)
	UiTheme.style_button(_open_btn)
	_open_btn.visible = false
	_open_btn.pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path(DIR)))
	bar.add_child(_open_btn)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", DIM)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_info)
	var back_btn := Button.new()
	back_btn.text = "Zurück zum Raum"
	back_btn.custom_minimum_size = Vector2(200, 46)
	UiTheme.style_button(back_btn)
	back_btn.pressed.connect(func():
		if is_host and not harness:
			Lobby.tour_cancel()
		back_to_room.emit())
	bar.add_child(back_btn)


## Aktuelles Endbild als PNG sichern (1920x1080). Gibt den Pfad zurueck.
func save_png(path: String = "") -> String:
	var abs_dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if path == "":
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		path = abs_dir.path_join(stamp + ".png")
	var img := _vp.get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		if _info != null:
			_info.text = "Speichern fehlgeschlagen."
		return ""
	_saved_path = path
	if _info != null:
		_info.text = tr("Gespeichert: %s") % path
		_open_btn.visible = true
	return path


func _build_canvas() -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(W, H)
	root.size = Vector2(W, H)
	if get_window() != null and get_window().theme != null:
		root.theme = get_window().theme
	root.clip_contents = true
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.color = Color(0.03, 0.035, 0.06)
	root.add_child(bg)
	root.add_child(_glow(Vector2(-300, -400), 1100, Color(ACCENT, 0.13)))
	root.add_child(_glow(Vector2(1100, 560), 1100, Color(UiTheme.ACCENT2, 0.08)))

	var stand: Array = t.standings()
	var wins: Array = t.map_winners()
	var margin := 84

	# Kopf: Titel links, Eckdaten als Chips rechts.
	var cap := TournamentPanel.lbl(tr("Turnierergebnis"), 22, ACCENT)
	cap.position = Vector2(margin, 40)
	root.add_child(cap)
	var ttl := TournamentPanel.lbl(title_text, 52, TEXT, true, 0)
	ttl.position = Vector2(margin, 70)
	root.add_child(ttl)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.position = Vector2(W - margin - 760, 56)
	chips.size = Vector2(760, 36)
	chips.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(chips)
	var lo := float(t.config.get("stars_lo", 0.0))
	var hi := float(t.config.get("stars_hi", 99.0))
	chips.add_child(TournamentPanel.chip(UiTheme.fmt_date(Time.get_unix_time_from_system()).left(10), DIM, 16))
	chips.add_child(TournamentPanel.chip("★ %s–%s" % [UiTheme.fmt_num(lo, 1), UiTheme.fmt_num(hi, 1)], ACCENT, 16))
	chips.add_child(TournamentPanel.chip(tr("%d Maps") % wins.size(), DIM, 16))
	chips.add_child(TournamentPanel.chip(tr("%d Spieler") % stand.size(), DIM, 16))
	var mods: Array[String] = []
	for k in ["SV", "NF"]:
		if bool(t.config.get("mods", {}).get(k, false)):
			mods.append(k)
	if not mods.is_empty():
		chips.add_child(TournamentPanel.chip(" + ".join(mods), DIM, 16))

	var info := _player_info(stand)
	_podium(root, stand, Rect2(margin, 170, 680, 440))
	_table(root, stand, info, Rect2(820, 170, W - 820 - margin, 440))
	_maps(root, stand, wins, Rect2(margin, 640, W - margin * 2, 410))
	return root


func _glow(pos: Vector2, diameter: float, col: Color) -> Control:
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 512
	gt.height = 512
	var tr := TextureRect.new()
	tr.texture = gt
	tr.position = pos
	tr.size = Vector2(diameter, diameter)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	return tr


## Pro Spieler aus den Rundenergebnissen: beste Map (hoechster Score), bester Kombo.
func _player_info(stand: Array) -> Dictionary:
	var info := {}
	for s in stand:
		info[s.peer] = { "best_score": -1, "best_map": {}, "best_combo": 0 }
	for rd in t.rounds:
		for peer in rd.results:
			var r: Dictionary = rd.results[peer]
			if not info.has(peer) or bool(r.get("absent", false)):
				continue
			var e: Dictionary = info[peer]
			e.best_combo = maxi(int(e.best_combo), int(r.max_combo))
			if int(r.score) > int(e.best_score):
				e.best_score = int(r.score)
				var mi := int(rd.map)
				e.best_map = t.pool[mi] if mi >= 0 and mi < t.pool.size() else {}
	return info


func _section(text: String) -> Label:
	return TournamentPanel.lbl(text, 24, TEXT, true, 0)


func _cell(c: Control, w: int) -> Control:
	if w > 0:
		c.custom_minimum_size.x = w
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _txt(text: String, size: int, col: Color, w: int = 0, right: bool = false) -> Label:
	var l := TournamentPanel.lbl(text, size, col)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cell(l, w)
	return l


func _podium(root: Control, stand: Array, area: Rect2) -> void:
	var holder := Control.new()
	holder.position = area.position
	holder.size = area.size
	root.add_child(holder)
	# Saeulen 2 - 1 - 3, nur vorhandene, mittig.
	var slots: Array = []
	for si in [1, 0, 2]:
		if si < stand.size():
			slots.append(si)
	var col_w := 210.0
	var gap := 22.0
	var total := col_w * slots.size() + gap * maxi(slots.size() - 1, 0)
	var x0 := (area.size.x - total) * 0.5
	var heights := [300.0, 260.0, 220.0]
	for k in slots.size():
		var si: int = slots[k]
		var s: Dictionary = stand[si]
		var rank := int(s.get("rank", si + 1))
		var rc := TournamentPanel.rank_color(rank)
		var ph: float = heights[si]
		var x := x0 + k * (col_w + gap)
		var base_y := area.size.y - 10.0
		var block := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(rc, 0.09)
		sb.border_color = Color(rc, 0.40)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(16)
		block.add_theme_stylebox_override("panel", sb)
		block.position = Vector2(x, base_y - ph)
		block.size = Vector2(col_w, ph)
		holder.add_child(block)
		var num := TournamentPanel.lbl("%d." % rank, 22, rc, true, 0)
		num.position = Vector2(x + 16, base_y - ph + 10)
		holder.add_child(num)
		var av_size := 104 if rank == 1 else 88
		var av := TournamentPanel.avatar(str(s.get("name", "?")), av_size)
		av.position = Vector2(x + (col_w - av_size) * 0.5, base_y - ph - av_size * 0.5)
		holder.add_child(av)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		inner.position = Vector2(x + 10, base_y - ph + av_size * 0.5 + 8)
		inner.size = Vector2(col_w - 20, ph - av_size * 0.5 - 90)
		holder.add_child(inner)
		var nl := TournamentPanel.lbl(str(s.get("name", "?")), 26, TEXT, true, 0)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(nl)
		var pl := TournamentPanel.lbl(UiTheme.fmt_score(int(s.get("points", 0))), 40, rc, true, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(pl)
		var pt := TournamentPanel.lbl(tr("Punkte"), 15, DIM)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(pt)
		var dl := TournamentPanel.lbl(tr("%d Siege  ·  Ø %s") % [int(s.get("wins", 0)),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0)], 15, DIM)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(dl)


func _table(root: Control, stand: Array, info: Dictionary, area: Rect2) -> void:
	var v := VBoxContainer.new()
	v.position = area.position
	v.size = area.size
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(_section(tr("Spieler")))
	var widths := [50, 0, 80, 70, 100, 130, 80, 220]
	var head := ["Platz", "Spieler", "Punkte", "Siege", "Ø Acc", "Gesamtscore", "Kombo", "Beste Map"]
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 12)
	for i in head.size():
		hr.add_child(_txt(tr(head[i]), 14, DIM, widths[i], i > 1 and i < 7))
	v.add_child(hr)
	var shown := mini(stand.size(), 8)
	var row_h := minf(46.0, (area.size.y - 70.0 - 6.0 * shown) / maxf(shown, 1))
	for i in shown:
		var s: Dictionary = stand[i]
		var rk := int(s.get("rank", i + 1))
		var nm := str(s.get("name", "?"))
		var inf: Dictionary = info.get(s.peer, {})
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.add_child(TournamentPanel.avatar(nm, 26))
		cell.add_child(_txt(nm, 18, TEXT))
		var best_m: Dictionary = inf.get("best_map", {})
		var best_txt := "–" if best_m.is_empty() else str(best_m.get("title", "?"))
		var best_lbl := _txt(best_txt, 16, DIM, 220)
		var r := TournamentPanel.table_row(["%d." % rk, cell,
			UiTheme.fmt_score(int(s.get("points", 0))), str(int(s.get("wins", 0))),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0),
			UiTheme.fmt_score(int(s.get("total_score", 0))),
			"%sx" % UiTheme.fmt_score(int(inf.get("best_combo", 0))), best_lbl],
			widths, 17, false, int(s.get("peer", 0)) == my_id, TournamentPanel.rank_color(rk))
		r.custom_minimum_size.y = row_h
		v.add_child(r)


func _cover(m: Dictionary) -> Texture2D:
	if _covers.is_empty() and library != null:
		for lms in library.mapsets:
			var lf: String = lms.osz_path.get_file()
			_covers["f:" + lf] = lms
			var lsid := TournamentPanel.set_id_of(lf)
			if lsid > 0:
				_covers["s:%d" % lsid] = lms
	var ms: MapSet = null
	var f := str(m.get("file", ""))
	var sid := int(m.get("set_id", 0))
	if f != "" and _covers.has("f:" + f):
		ms = _covers["f:" + f]
	elif sid > 0 and _covers.has("s:%d" % sid):
		ms = _covers["s:%d" % sid]
	if ms != null:
		return ms.thumb_texture()
	var mirror := get_node_or_null("/root/Mirror") as BeatmapMirror
	if mirror != null and sid > 0:
		return mirror.cached_cover(sid)
	return null


func _result_cell(r: Dictionary, two_lines: bool, w: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_cell(v, w)
	if r.is_empty() or bool(r.get("absent", false)):
		v.add_child(_txt("–", 15, DIM, 0, true))
		return v
	var pts := int(r.points)
	var col := TEXT
	if pts > 0 and int(r.place) <= 3:
		col = TournamentPanel.rank_color(int(r.place))
	var l1 := UiTheme.fmt_score(int(r.score))
	if bool(r.failed):
		l1 = tr("Fail") + "  " + l1
		if pts <= 0:
			col = Color(0.85, 0.5, 0.55)
	v.add_child(_txt(l1, 15, col, 0, true))
	if two_lines:
		var l2 := "%s  ·  %sx" % [UiTheme.fmt_pct(float(r.accuracy) * 100.0), UiTheme.fmt_score(int(r.max_combo))]
		v.add_child(_txt(l2, 12, DIM, 0, true))
	return v


func _maps(root: Control, stand: Array, wins: Array, area: Rect2) -> void:
	var v := VBoxContainer.new()
	v.position = area.position
	v.size = area.size
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(_section(tr("Maps und Ergebnisse")))
	var n := mini(stand.size(), 8)
	var rows := wins.size()
	var rh := clampf((area.size.y - 70.0 - 5.0 * rows) / maxf(rows, 1), 24.0, 60.0)
	var two := rh >= 40.0
	var with_cover := rh >= 34.0
	var pw := int(clampf(float(area.size.x - 780) / maxf(n, 1), 110.0, 170.0))
	var win_w := 200
	# Kopfzeile: Spielernamen ueber den Spalten.
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 12)
	hr.add_child(_txt("#", 14, DIM, 28))
	hr.add_child(_txt(tr("Map"), 14, DIM, 0))
	hr.add_child(_txt("★", 14, DIM, 70))
	hr.add_child(_txt(tr("Sieger"), 14, DIM, win_w))
	for i in n:
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 6)
		ph.alignment = BoxContainer.ALIGNMENT_END
		ph.add_child(TournamentPanel.avatar(str(stand[i].name), 18))
		var pn := TournamentPanel.lbl(str(stand[i].name), 14, DIM)
		pn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_child(pn)
		_cell(ph, pw)
		ph.clip_contents = true
		hr.add_child(ph)
	v.add_child(hr)
	for i in rows:
		var w: Dictionary = wins[i]
		var m: Dictionary = w.get("map", {})
		var rd: Dictionary = t.rounds[i]
		var card := TournamentPanel.glass(10, 0.36, 0.07, 4)
		card.custom_minimum_size.y = rh
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		h.add_child(_txt("%d" % (i + 1), 16, ACCENT, 28))
		var mc := HBoxContainer.new()
		mc.add_theme_constant_override("separation", 10)
		_cell(mc, 0)
		mc.clip_contents = true
		if with_cover:
			var tx := TextureRect.new()
			var cw := int((rh - 8.0) * 16.0 / 9.0)
			tx.custom_minimum_size = Vector2(cw, rh - 8.0)
			tx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tx.clip_contents = true
			tx.texture = _cover(m)
			tx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			mc.add_child(tx)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		_cell(tv, 0)
		tv.clip_contents = true
		tv.add_child(_txt(str(m.get("title", "?")), 17, TEXT))
		if two:
			tv.add_child(_txt(str(m.get("artist", "")), 13, DIM))
		mc.add_child(tv)
		h.add_child(mc)
		var sc := float(m.get("stars", 0.0))
		var chipw := CenterContainer.new()
		_cell(chipw, 70)
		chipw.add_child(TournamentPanel.chip(TournamentPanel.stars_text(sc), OnlineBrowser.star_color(sc), 13))
		h.add_child(chipw)
		var wn := str(w.get("winner_name", ""))
		var wbox := HBoxContainer.new()
		wbox.add_theme_constant_override("separation", 8)
		_cell(wbox, win_w)
		wbox.clip_contents = true
		if wn != "":
			wbox.add_child(TournamentPanel.avatar(wn, 26 if two else 20))
		var wv := VBoxContainer.new()
		wv.add_theme_constant_override("separation", 0)
		wv.alignment = BoxContainer.ALIGNMENT_CENTER
		_cell(wv, 0)
		wv.add_child(_txt(wn if wn != "" else "–", 16, TournamentPanel.GOLD))
		if two and wn != "":
			wv.add_child(_txt(UiTheme.fmt_score(int(w.get("score", 0))), 12, DIM))
		wbox.add_child(wv)
		h.add_child(wbox)
		for k in n:
			h.add_child(_result_cell(rd.results.get(stand[k].peer, {}), two, pw))
		v.add_child(card)
