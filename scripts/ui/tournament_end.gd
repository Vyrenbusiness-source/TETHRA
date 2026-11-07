class_name TournamentEnd
extends Control

## Endbild des Turniers: Podium Top 3, Tabelle aller Spieler, alle gespielten
## Maps mit Gewinner. Das Bild ist fest 1920x1080 und wird in einem eigenen
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
	root.add_child(_glow(Vector2(-300, -380), 1100, Color(ACCENT, 0.20)))
	root.add_child(_glow(Vector2(1080, 520), 1100, Color(UiTheme.ACCENT2, 0.14)))

	var stand: Array = t.standings()
	var wins: Array = t.map_winners()
	var margin := 84

	# Kopf: Turniername, Datum, Sternbereich.
	var head := Control.new()
	head.position = Vector2(margin, 50)
	head.size = Vector2(W - margin * 2, 90)
	root.add_child(head)
	var cap := TournamentPanel.lbl("TURNIER  ·  ENDERGEBNIS", 20, ACCENT, true)
	cap.position = Vector2(0, 0)
	head.add_child(cap)
	var ttl := TournamentPanel.lbl(title_text, 46, TEXT, true)
	ttl.position = Vector2(0, 28)
	head.add_child(ttl)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.position = Vector2(W - margin * 2 - 760, 12)
	chips.size = Vector2(760, 36)
	chips.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(chips)
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

	# Podium links.
	_podium(root, stand, Rect2(margin, 190, 860, 430))
	# Tabelle rechts.
	_table(root, stand, Rect2(1000, 170, W - 1000 - margin, 440))
	# Maps unten.
	_maps(root, wins, Rect2(margin, 650, W - margin * 2, 380))
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


func _podium(root: Control, stand: Array, area: Rect2) -> void:
	var holder := Control.new()
	holder.position = area.position
	holder.size = area.size
	root.add_child(holder)
	# Reihenfolge der Saeulen: 2. - 1. - 3.
	var slots := [[1, 0, 265.0], [0, 1, 335.0], [2, 2, 235.0]]
	var col_w := 270.0
	var gap := 24.0
	var total := col_w * 3.0 + gap * 2.0
	var x0 := (area.size.x - total) * 0.5
	for k in 3:
		var si: int = slots[k][0]
		if si >= stand.size():
			continue
		var s: Dictionary = stand[si]
		var rank := int(s.get("rank", si + 1))
		var rc := TournamentPanel.rank_color(rank)
		var ph: float = slots[k][2]
		var x := x0 + k * (col_w + gap)
		var base_y := area.size.y
		var block := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(rc, 0.14)
		sb.border_color = Color(rc, 0.5)
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		block.add_theme_stylebox_override("panel", sb)
		block.position = Vector2(x, base_y - ph)
		block.size = Vector2(col_w, ph)
		holder.add_child(block)
		var num := TournamentPanel.lbl(str(rank), 72, Color(rc, 0.28), true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.size = Vector2(col_w, 90)
		num.position = Vector2(x, base_y - 100)
		holder.add_child(num)
		var av_size := 132 if rank == 1 else 104
		var av := TournamentPanel.avatar(str(s.get("name", "?")), av_size)
		av.position = Vector2(x + (col_w - av_size) * 0.5, base_y - ph - av_size * 0.62)
		holder.add_child(av)
		if rank == 1:
			var crown := TournamentPanel.lbl("👑", 44)
			crown.position = Vector2(x + col_w * 0.5 - 28, base_y - ph - av_size * 0.62 - 56)
			holder.add_child(crown)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		inner.position = Vector2(x + 10, base_y - ph + av_size * 0.42)
		inner.size = Vector2(col_w - 20, ph - av_size * 0.42)
		holder.add_child(inner)
		var nl := TournamentPanel.lbl(str(s.get("name", "?")), 28, TEXT, true)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(nl)
		var pl := TournamentPanel.lbl(tr("%s Punkte") % UiTheme.fmt_score(int(s.get("points", 0))), 22, rc)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(pl)
		var dl := TournamentPanel.lbl(tr("%d Siege  ·  Ø %s") % [int(s.get("wins", 0)),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0)], 15, DIM)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(dl)


func _table(root: Control, stand: Array, area: Rect2) -> void:
	var v := VBoxContainer.new()
	v.position = area.position
	v.size = area.size
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(TournamentPanel.lbl("ALLE SPIELER", 15, ACCENT, true))
	var widths := [60, 0, 120, 80, 120]
	v.add_child(TournamentPanel.table_row(["Platz", "Spieler", "Punkte", "Siege", "Ø Acc"], widths, 16, true))
	var shown := mini(stand.size(), 8)
	var row_h := minf(46.0, (area.size.y - 70.0) / maxf(shown, 1))
	for i in shown:
		var s: Dictionary = stand[i]
		var rk := int(s.get("rank", i + 1))
		var nm := str(s.get("name", "?"))
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.add_child(TournamentPanel.avatar(nm, 26))
		var l := TournamentPanel.lbl(nm, 18)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(l)
		var r := TournamentPanel.table_row(["%d." % rk, cell,
			UiTheme.fmt_score(int(s.get("points", 0))), str(int(s.get("wins", 0))),
			UiTheme.fmt_pct(float(s.get("avg_acc", 0.0)) * 100.0)],
			widths, 18, false, int(s.get("peer", 0)) == my_id, TournamentPanel.rank_color(rk))
		r.custom_minimum_size.y = row_h
		v.add_child(r)


func _maps(root: Control, wins: Array, area: Rect2) -> void:
	var v := VBoxContainer.new()
	v.position = area.position
	v.size = area.size
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	v.add_child(TournamentPanel.lbl("GESPIELTE MAPS", 15, ACCENT, true))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var rows := int(ceil(wins.size() / 2.0))
	var order: Array = []
	# Spaltenweise fuellen (links 1..n/2, rechts Rest), damit die Reihenfolge lesbar bleibt.
	for r in rows:
		order.append(r)
		if r + rows < wins.size():
			order.append(r + rows)
	for i in order:
		var w: Dictionary = wins[i]
		var m: Dictionary = w.get("map", {})
		var card := TournamentPanel.glass(10, 0.42, 0.08, 7)
		card.custom_minimum_size = Vector2((area.size.x - 20) / 2.0, clampf(330.0 / maxf(rows, 1) - 6.0, 40.0, 60.0))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		card.add_child(h)
		h.add_child(TournamentPanel.lbl("%d" % (i + 1), 18, ACCENT, true))
		(h.get_child(0) as Control).custom_minimum_size.x = 28
		var tl := TournamentPanel.lbl("%s  —  %s" % [str(m.get("artist", "")), str(m.get("title", "?"))], 17)
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tl)
		h.add_child(TournamentPanel.chip(TournamentPanel.stars_text(float(m.get("stars", 0.0))),
			OnlineBrowser.star_color(float(m.get("stars", 0.0))), 13))
		var wn := str(w.get("winner_name", "–"))
		h.add_child(TournamentPanel.avatar(wn, 24))
		var wl := TournamentPanel.lbl(wn, 16, TournamentPanel.GOLD)
		wl.custom_minimum_size.x = 150
		wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(wl)
		g.add_child(card)
