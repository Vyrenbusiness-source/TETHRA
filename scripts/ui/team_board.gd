class_name TeamBoard
extends Control

## Zwei Spalten Rot/Blau (Glas-Stil) mit Avataren und Live-Teamsumme.
## Spieler wechseln per Klick (in das andere Team) oder per Drag auf die Spalte.
##
## setup({names:[a,b], players:[{peer, name, team, score?}], totals:[a,b]?,
##        hint:String?, editable:bool?})
## Signal team_requested(peer, team): der Aufrufer ruft MatchMode.set_team()
## und danach erneut setup(). set_totals() gleitet ruhig auf die neuen Werte.

signal team_requested(peer: int, team: int)

const COLS := [Color(1.0, 0.38, 0.45), Color(0.38, 0.65, 1.0)]
const TEXT := Color(0.95, 0.96, 1.0)
const DIM := Color(0.62, 0.64, 0.72)

var _names: Array = ["Rot", "Blau"]
var _players: Array = []
var _shown: Array = [0.0, 0.0]
var _target: Array = [0, 0]
var _hint := ""
var _editable := true
var _total_labels: Array = []
var _tween: Tween
var _root: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 300)


func setup(d: Dictionary) -> void:
	var nm = d.get("names", null)
	if typeof(nm) == TYPE_ARRAY and nm.size() == 2:
		_names = [str(nm[0]), str(nm[1])]
	_players = []
	var pl = d.get("players", [])
	if typeof(pl) == TYPE_ARRAY:
		for p in pl:
			if typeof(p) == TYPE_DICTIONARY and p.has("peer") and clampi(int(p.get("team", 0)), 0, 1) == int(p.get("team", 0)):
				_players.append(p)
	var tt = d.get("totals", null)
	if typeof(tt) == TYPE_ARRAY and tt.size() == 2:
		_target = [maxi(0, int(tt[0])), maxi(0, int(tt[1]))]
		_shown = [float(_target[0]), float(_target[1])]
	else:
		_target = [-1, -1]
	_hint = str(d.get("hint", ""))
	_editable = bool(d.get("editable", true))
	_build()


## Live-Summen; gleitet auf die neuen Werte.
func set_totals(totals: Array) -> void:
	if totals.size() != 2:
		return
	_target = [maxi(0, int(totals[0])), maxi(0, int(totals[1]))]
	if _shown[0] < 0.0:
		_shown = [0.0, 0.0]
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in 2:
		_tween.tween_method(_show_total.bind(i), _shown[i], float(_target[i]), 0.6)


func _show_total(v: float, i: int) -> void:
	_shown[i] = v
	if i < _total_labels.size() and is_instance_valid(_total_labels[i]):
		_total_labels[i].text = UiTheme.fmt_score(int(v))


func _build() -> void:
	if _root:
		_root.queue_free()
	_total_labels.clear()
	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	_root.add_child(cols)
	for t in 2:
		cols.add_child(_column(t))
	var bottom := Label.new()
	bottom.text = _hint
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_theme_font_size_override("font_size", 13)
	bottom.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	bottom.visible = _hint != ""
	_root.add_child(bottom)


func _column(team: int) -> Control:
	var col: Color = COLS[team]
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.glass_box(16, 0.5, 0.14)
	sb.border_color = Color(col.r, col.g, col.b, 0.35)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	if _editable:
		box.set_drag_forwarding(Callable(), _can_drop.bind(team), _drop.bind(team))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(4, 22)
	head.add_child(dot)
	var title := Label.new()
	title.text = _names[team]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", UiTheme.heading_font())
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", col)
	head.add_child(title)
	var count := make_chip("%d Spieler" % _count(team), DIM)
	head.add_child(count)

	var total := Label.new()
	total.add_theme_font_override("font", UiTheme.heading_font())
	total.add_theme_font_size_override("font_size", 30)
	total.add_theme_color_override("font_color", TEXT)
	total.visible = _target[team] >= 0
	total.text = UiTheme.fmt_score(int(_shown[team]) if _target[team] >= 0 else 0)
	v.add_child(total)
	_total_labels.append(total)

	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	v.add_child(sep)

	var any := false
	for p in _players:
		if int(p.team) != team:
			continue
		any = true
		v.add_child(_row(p, col))
	if not any:
		var empty := Label.new()
		empty.text = "Noch niemand. Spieler hierher ziehen."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", DIM)
		v.add_child(empty)
	return box


func _count(team: int) -> int:
	var n := 0
	for p in _players:
		if int(p.team) == team:
			n += 1
	return n


func _row(p: Dictionary, col: Color) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var nm := str(p.get("name", "?"))
	var av := make_avatar(nm, 30)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(av)
	var l := Label.new()
	l.text = nm
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	if p.has("score"):
		var s := Label.new()
		s.text = UiTheme.fmt_score(int(p.score))
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", DIM)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(s)
	if _editable:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.set_drag_forwarding(_drag_data.bind(p), Callable(), Callable())
		row.gui_input.connect(_row_input.bind(int(p.peer), int(p.team)))
		row.mouse_entered.connect(func(): sb.bg_color = Color(col.r, col.g, col.b, 0.14))
		row.mouse_exited.connect(func(): sb.bg_color = Color(1, 1, 1, 0.05))
	return row


func _row_input(ev: InputEvent, peer: int, team: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		team_requested.emit(peer, 1 - team)


func _drag_data(_pos: Vector2, p: Dictionary) -> Variant:
	var prev := make_avatar(str(p.get("name", "?")), 34)
	set_drag_preview(prev)
	return {"match_peer": int(p.peer)}


func _can_drop(_pos: Vector2, data: Variant, _team: int) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("match_peer")


func _drop(_pos: Vector2, data: Variant, team: int) -> void:
	team_requested.emit(int(data.match_peer), team)


# ------------------------------------------------------- gemeinsame Bausteine

## Runder Avatar mit Anfangsbuchstabe; Farbe aus dem Namen.
static func make_avatar(pname: String, sz: int = 28, dim: bool = false) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(absi(pname.hash()) % 360) / 360.0, 0.45 if not dim else 0.15, 0.62 if not dim else 0.4)
	sb.set_corner_radius_all(sz)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.08, 0.09, 0.14, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(sz, sz)
	var l := Label.new()
	l.text = pname.substr(0, 1).to_upper() if pname != "" else "?"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(sz * 0.5))
	l.add_theme_color_override("font_color", TEXT)
	p.add_child(l)
	return p


## Kleine Pille (Text auf getoenter Flaeche).
static func make_chip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.16)
	sb.border_color = Color(col.r, col.g, col.b, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	return p
