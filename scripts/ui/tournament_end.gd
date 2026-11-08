class_name TournamentEnd
extends Control

## Endbild des Turniers: Podium Top 3, Tabelle aller Spieler (Punkte, Siege,
## Acc, Gesamtscore, beste Map), Map-Liste mit Cover, Sieger und den Ergebnissen
## jedes Spielers (Platz, Score, Acc, Kombo, Fail). Das Bild ist fest 1920x1080 und wird in einem eigenen
## SubViewport gezeichnet; die Anzeige skaliert es, "Bild speichern" schreibt
## genau dieses Bild als PNG nach user://tournaments/. Klick auf einen Spieler
## (Podium/Tabelle) oeffnet seine Detail-Stats: Summen ueber alle Runden und je Map.

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
var _view: TextureRect
var _hits: Array = []  # [Control im Bild, peer]
var _detail: Control
var _detail_peer := -1
var _detail_round := -1  # -1 = Gesamt


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
	if harness:
		_fake_stats()
	var canvas := _build_canvas()
	_vp.add_child(canvas)
	var tr := TextureRect.new()
	tr.texture = _vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.gui_input.connect(_on_view_input)
	_view = tr
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
	_info.text = tr("Klick auf einen Spieler zeigt seine Stats.")
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
	if harness and (OS.get_cmdline_args() + OS.get_cmdline_user_args()).has("--shot-detail"):
		var st: Array = t.standings()
		if not st.is_empty():
			open_detail(int(st[mini(1, st.size() - 1)].peer))


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
	var tv := _table(root, stand, info, Rect2(820, 170, W - 820 - margin, 440))
	if stand.size() <= 5:
		_awards(tv, stand)
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
		_hits.append([block, s.get("peer", 0)])
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


func _table(root: Control, stand: Array, info: Dictionary, area: Rect2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = area.position
	v.size = area.size
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(_section(tr("Spieler")))
	var widths := [50, 0, 72, 62, 96, 124, 84, 170, 64]
	var head := ["Platz", "Spieler", "Punkte", "Siege", "Ø Acc", "Gesamtscore", "Kombo", "Treffer", "UR"]
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 12)
	for i in head.size():
		hr.add_child(_txt(tr(head[i]), 14, DIM, widths[i], i > 1))
	v.add_child(hr)
	var shown := mini(stand.size(), 8)
	var row_h := minf(46.0, (area.size.y - 70.0 - 6.0 * shown) / maxf(shown, 1))
	for i in shown:
		var s: Dictionary = stand[i]
		var rk := int(s.get("rank", i + 1))
		var nm := str(s.get("name", "?"))
		var inf: Dictionary = info.get(s.peer, {})
		var tot := player_stats(s.peer)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.add_child(TournamentPanel.avatar(nm, 26))
		cell.add_child(_txt(nm, 18, TEXT))
		var ur_txt := UiTheme.fmt_num(float(tot.ur), 0) if tot.has("ur") else "–"
		var r := TournamentPanel.table_row(["%d." % rk, cell,
			UiTheme.fmt_score(int(s.get("points", 0))), str(int(s.get("wins", 0))),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0),
			UiTheme.fmt_score(int(s.get("total_score", 0))),
			"%sx" % UiTheme.fmt_score(int(inf.get("best_combo", 0))), _judge_cell(tot, 170),
			_txt(ur_txt, 17, TEXT, 64, true)],
			widths, 17, false, int(s.get("peer", 0)) == my_id, TournamentPanel.rank_color(rk))
		r.custom_minimum_size.y = row_h
		v.add_child(r)
		_hits.append([r, s.peer])
	return v


## Mini-Verteilung der Urteile (Summe aller Runden) + Miss-Zahl.
func _judge_cell(st: Dictionary, w: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_cell(h, w)
	var tot := PlayerStatsCard.total_of(st)
	if tot <= 0:
		h.add_child(_txt("–", 15, DIM, 0, true))
		return h
	var bar := PlayerStatsCard._Stack.new()
	var fr: Array = []
	for k in PlayerStatsCard.KEYS:
		fr.append(float(st.get(k, 0)) / float(tot))
	bar.fracs = fr
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var ml := _txt("%d ✕" % int(st.get("n_miss", 0)), 13, ResultsScreen.QUALITY_COLOR[5].lerp(TEXT, 0.35), 44, true)
	h.add_child(ml)
	return h


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


# ---------------------------------------------------------------------------
# Detail-Stats je Spieler
# ---------------------------------------------------------------------------

## Stats-Paket eines Rundenergebnisses ({} = gegangen). Alte Ergebnisse ohne
## Detail-Paket liefern nur Score/Acc/Kombo.
## Auszeichnungen ueber alle Runden: je Eintrag cap, peer, name, value, sub.
## Leere Liste, wenn keine Runde gespielt wurde.
func awards(stand: Array) -> Array:
	var best_score := { "v": -1 }
	var best_combo := { "v": -1 }
	var low_ur := { "v": INF }
	var few_miss := { "v": INF }
	for s in stand:
		var peer = s.peer
		var nm := str(s.get("name", "?"))
		for i in t.rounds.size():
			var st := round_stats(t.rounds[i].results.get(peer, {}))
			if st.is_empty():
				continue
			var title := str(_round_map(i).get("title", "?"))
			if int(st.get("score", 0)) > int(best_score.v):
				best_score = { "v": int(st.score), "peer": peer, "name": nm, "sub": title }
			if int(st.get("combo", 0)) > int(best_combo.v):
				best_combo = { "v": int(st.combo), "peer": peer, "name": nm, "sub": title }
		var tot := player_stats(peer)
		if int(tot.get("rounds", 0)) == 0:
			continue
		if tot.has("ur") and float(tot.ur) > 0.0 and float(tot.ur) < float(low_ur.v):
			low_ur = { "v": float(tot.ur), "peer": peer, "name": nm }
		if PlayerStatsCard.total_of(tot) > 0:
			var per := float(tot.get("n_miss", 0)) / float(tot.rounds)
			if per < float(few_miss.v):
				few_miss = { "v": per, "peer": peer, "name": nm }
	var out: Array = []
	if int(best_score.v) >= 0:
		out.append({ "cap": tr("Bester Score"), "peer": best_score.peer, "name": best_score.name,
			"value": UiTheme.fmt_score(int(best_score.v)), "sub": best_score.sub })
	if int(best_combo.v) > 0:
		out.append({ "cap": tr("Längste Kombo"), "peer": best_combo.peer, "name": best_combo.name,
			"value": "%s×" % UiTheme.fmt_score(int(best_combo.v)), "sub": best_combo.sub })
	if low_ur.has("peer"):
		out.append({ "cap": tr("Ruhigste Hand"), "peer": low_ur.peer, "name": low_ur.name,
			"value": UiTheme.fmt_num(float(low_ur.v), 1) + " UR", "sub": tr("niedrigste UR") })
	if few_miss.has("peer"):
		out.append({ "cap": tr("Wenigste Misses"), "peer": few_miss.peer, "name": few_miss.name,
			"value": "Ø " + UiTheme.fmt_num(float(few_miss.v), 1), "sub": tr("je Map") })
	return out


## Leiste mit den Auszeichnungen direkt unter der Spielertabelle (v).
func _awards(tv: VBoxContainer, stand: Array) -> void:
	var list := awards(stand)
	if list.is_empty():
		return
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	tv.add_child(gap)
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 88)
	h.add_theme_constant_override("separation", 12)
	tv.add_child(h)
	for a in list:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_stretch_ratio = 1.0
		var sb := UiTheme.glass_box(12, 0.45, 0.07)
		sb.shadow_size = 0
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		p.add_theme_stylebox_override("panel", sb)
		h.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		p.add_child(v)
		var cap := TournamentPanel.lbl(str(a.cap).to_upper(), 12, Color(0.66, 0.69, 0.78), true, 2)
		cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(cap)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		row.add_child(TournamentPanel.avatar(str(a.name), 24))
		var nl := _txt(str(a.name), 16, TEXT)
		nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(nl)
		var vl := TournamentPanel.lbl(str(a.value), 17, ACCENT, true, 0)
		vl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(vl)
		var sl := _txt(str(a.sub), 12, DIM)
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(sl)
		_hits.append([p, a.peer])


static func round_stats(r: Dictionary) -> Dictionary:
	if r.is_empty() or bool(r.get("absent", false)):
		return {}
	var st: Dictionary = r.get("stats", {})
	if not st.is_empty():
		return st
	return { "score": int(r.get("score", 0)), "acc": float(r.get("accuracy", 0.0)),
		"combo": int(r.get("max_combo", 0)), "failed": bool(r.get("failed", false)),
		"grade": PlayerStatsCard.grade_for(float(r.get("accuracy", 0.0))) }


## Summe ueber alle Runden eines Spielers (PlayerStatsCard.merge).
func player_stats(peer) -> Dictionary:
	var list: Array = []
	for rd in t.rounds:
		list.append(round_stats(rd.results.get(peer, {})))
	var m := PlayerStatsCard.merge(list)
	if PlayerStatsCard.total_of(m) == 0 and int(m.rounds) > 0:
		# Ohne Zaehler: Acc = Mittel der Runden.
		var s := 0.0
		for a in m.trace:
			s += float(a) / 1000.0
		m.acc = s / float(m.trace.size())
		m.grade = PlayerStatsCard.grade_for(float(m.acc))
	return m


## Harness: Runden ohne Detail-Paket mit passenden Fake-Stats fuellen.
func _fake_stats() -> void:
	for ri in t.rounds.size():
		var rd: Dictionary = t.rounds[ri]
		for peer in rd.results:
			var r: Dictionary = rd.results[peer]
			if r.has("stats") or bool(r.get("absent", false)):
				continue
			var acc := float(r.get("accuracy", 0.9))
			var st := PlayerStatsCard.fake(int(peer) * 31 + ri * 7, clampf((acc - 0.80) / 0.2, 0.0, 1.0), 900 + ri * 60,
				bool(r.get("failed", false)))
			st.score = int(r.get("score", st.score))
			st.combo = int(r.get("max_combo", st.combo))
			r["stats"] = st


func _on_view_input(ev: InputEvent) -> void:
	var mpos := Vector2.ZERO
	if ev is InputEventMouse:
		mpos = (ev as InputEventMouse).position
	else:
		return
	var sc := minf(_view.size.x / float(W), _view.size.y / float(H))
	var off := (_view.size - Vector2(W, H) * sc) * 0.5
	var p := (mpos - off) / sc
	var hit := -1
	for h in _hits:
		var c: Control = h[0]
		if is_instance_valid(c) and c.get_global_rect().has_point(p):
			hit = int(h[1])
			break
	_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hit >= 0 else Control.CURSOR_ARROW
	if hit >= 0 and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		open_detail(hit)


func _input(ev: InputEvent) -> void:
	if _detail != null and is_instance_valid(_detail) and ev is InputEventKey and ev.pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_detail()


func close_detail() -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null
	_detail_peer = -1


## Detail-Ansicht eines Spielers: Karte (Gesamt oder eine Map) + Liste je Map.
func open_detail(peer: int, round_i: int = -1) -> void:
	var first := _detail == null or not is_instance_valid(_detail)
	if not first:
		_detail.queue_free()
	_detail_peer = peer
	_detail_round = round_i
	var narrow := size.x < 1600.0 or size.y < 900.0
	var stand: Array = t.standings()
	var srow: Dictionary = {}
	for s in stand:
		if int(s.peer) == peer:
			srow = s
	var nm := str(srow.get("name", t.player_names.get(peer, "?")))
	_detail = UiTheme.modal_backdrop(self)
	_detail.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_detail())
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mx := maxf(24.0, (size.x - 1640.0) * 0.5)
	var my := maxf(20.0, (size.y - 940.0) * 0.5)
	panel.offset_left = mx
	panel.offset_right = -mx
	panel.offset_top = my
	panel.offset_bottom = -my
	var psb := UiTheme.glass_box(20, 0.94, 0.10)
	psb.bg_color = Color(0.055, 0.06, 0.095, 0.97)
	psb.set_content_margin_all(18 if narrow else 26)
	panel.add_theme_stylebox_override("panel", psb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14 if narrow else 20)
	panel.add_child(v)
	# Kopf: Titel (Name steht in der Karte), Umschalter fuer alle Spieler, Schliessen.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(hv)
	hv.add_child(TournamentPanel.lbl(tr("Spieler-Statistik").to_upper(), 12 if narrow else 13, Color(0.66, 0.69, 0.78), true, 2))
	var tl := TournamentPanel.lbl(title_text, 22 if narrow else 28, TEXT, true, 1)
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hv.add_child(tl)
	var rk := int(srow.get("rank", 0))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 6)
	head.add_child(sw)
	for s in stand.slice(0, 8):
		var b := Button.new()
		b.text = str(s.name) if not narrow else str(s.name).left(8)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 13 if narrow else 14)
		if int(s.peer) == peer:
			UiTheme.style_button(b, false)
			var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
			sb.border_color = Color(ACCENT, 0.7)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
		else:
			UiTheme.style_ghost_button(b, 12)
		b.pressed.connect(open_detail.bind(int(s.peer), -1))
		sw.add_child(b)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	UiTheme.style_ghost_button(x, 10)
	x.pressed.connect(close_detail)
	head.add_child(x)
	# Inhalt: Karte links, Maps rechts.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18 if narrow else 24)
	v.add_child(body)
	var card := PlayerStatsCard.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	body.add_child(card)
	var info := { "name": nm, "narrow": narrow }
	var st: Dictionary
	if round_i < 0:
		st = player_stats(peer)
		info["place"] = rk
		info["sub"] = tr("%s Punkte") % str(int(srow.get("points", 0))) + "  ·  " + \
			tr("%d Siege") % int(srow.get("wins", 0)) + "  ·  " + \
			tr("Gesamt über %d Maps") % int(st.get("rounds", 0)) + \
			(("  ·  " + tr("%d× nicht geschafft") % int(st.fails)) if int(st.get("fails", 0)) > 0 else "")
	else:
		var r: Dictionary = t.rounds[round_i].results.get(peer, {})
		st = round_stats(r)
		var m := _round_map(round_i)
		info["place"] = int(r.get("place", 0)) if not st.is_empty() else 0
		info["sub"] = tr("Map %d") % (round_i + 1) + "  ·  " + str(m.get("title", "?"))
		if st.is_empty():
			info["pending"] = true
	card.setup(info, st)
	if st.is_empty():
		for c in card.find_children("*", "Label", true, false):
			if (c as Label).text == tr("spielt noch…"):
				(c as Label).text = tr("Nicht gespielt (gegangen)")
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(TournamentPanel.lbl(tr("Je Map").to_upper(), 13, Color(0.66, 0.69, 0.78), true, 2))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	list.add_child(_map_row(-1, peer, player_stats(peer), narrow))
	for i in t.rounds.size():
		list.add_child(_map_row(i, peer, round_stats(t.rounds[i].results.get(peer, {})), narrow))
	# Direktvergleich mit dem Sieger (der Sieger mit dem Zweiten), gleiche Ansicht
	# (Summe oder gewaehlte Map).
	var rival := -1
	var rname := "?"
	for s in stand:
		if int(s.peer) != peer:
			rival = int(s.peer)
			rname = str(s.get("name", "?"))
			break
	if rival >= 0:
		var rst: Dictionary = player_stats(rival) if round_i < 0 else round_stats(t.rounds[round_i].results.get(rival, {}))
		if not st.is_empty() and not rst.is_empty():
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 10)
			list.add_child(gap)
			list.add_child(PlayerStatsCard.duel(nm, st, rname, rst, narrow))
	if first:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.98, 0.98)
		panel.pivot_offset = (size - Vector2(mx, my) * 2.0) * 0.5
		var tw := create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.18)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _round_map(i: int) -> Dictionary:
	var mi := int(t.rounds[i].get("map", -1))
	return t.pool[mi] if mi >= 0 and mi < t.pool.size() else {}


func _map_row(i: int, peer: int, st: Dictionary, narrow: bool) -> Control:
	var sel := i == _detail_round
	var p := PanelContainer.new()
	var sb := UiTheme.glass_box(12, 0.62 if sel else 0.34, 0.08)
	sb.shadow_size = 0
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if sel:
		sb.border_color = Color(ACCENT, 0.6)
		sb.bg_color = Color(UiTheme.RAISED, 0.8)
	p.add_theme_stylebox_override("panel", sb)
	var hov: StyleBoxFlat = sb.duplicate()
	hov.bg_color = sb.bg_color.lightened(0.07)
	p.custom_minimum_size.y = 50 if narrow else 58
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hov))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", sb))
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			open_detail.call_deferred(peer, i))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ch := 38.0 if narrow else 44.0
	if i < 0:
		var g := TournamentPanel.lbl("Σ", 22, ACCENT, true, 0)
		g.custom_minimum_size = Vector2(ch * 16.0 / 9.0 + 34.0, 0)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(g)
	else:
		h.add_child(_txt("%d" % (i + 1), 15, ACCENT, 24))
		var tx := TextureRect.new()
		tx.custom_minimum_size = Vector2(ch * 16.0 / 9.0, ch)
		tx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tx.clip_contents = true
		tx.texture = _cover(_round_map(i))
		tx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tx)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -1)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell(tv, 0)
	tv.clip_contents = true
	h.add_child(tv)
	if i < 0:
		tv.add_child(_txt(tr("Gesamt"), 16, TEXT))
		tv.add_child(_txt(tr("alle Maps zusammen"), 12, DIM))
	else:
		var m := _round_map(i)
		tv.add_child(_txt(str(m.get("title", "?")), 15, TEXT))
		var sc := float(m.get("stars", 0.0))
		tv.add_child(_txt("%s  ·  %s" % [str(m.get("version", "")), TournamentPanel.stars_text(sc)], 12, DIM))
	if st.is_empty():
		h.add_child(_txt(tr("gegangen"), 14, DIM, 120, true))
		return p
	if i >= 0:
		var r: Dictionary = t.rounds[i].results.get(peer, {})
		var pl := int(r.get("place", 0))
		var pc := TournamentPanel.rank_color(pl) if pl <= 3 else DIM
		var place_txt := ("%d." % pl) if pl > 0 else "–"
		if bool(st.get("failed", false)):
			place_txt = tr("Fail")
			pc = Color(0.95, 0.5, 0.55)
		h.add_child(_txt(place_txt, 15, pc, 40, true))
	h.add_child(_txt(UiTheme.fmt_score(int(st.get("score", 0))), 15, TEXT, 86 if narrow else 100, true))
	h.add_child(_txt(UiTheme.fmt_pct(float(st.get("acc", 0.0)) * 100.0), 15, ACCENT.lerp(TEXT, 0.35), 74, true))
	if not narrow:
		h.add_child(_judge_cell(st, 130))
		h.add_child(_txt(("UR " + UiTheme.fmt_num(float(st.ur), 0)) if st.has("ur") else "–", 13, DIM, 62, true))
	return p
