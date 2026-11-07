class_name RoyaleBoard
extends Control

## Battle-Royale-Tafel (Glas-Stil): links die Lebenden, rechts die Ausgeschiedenen.
## setup({round:int, players:[{peer, name, alive, out_round?, score?}],
##        danger:int?, final:bool?, winner:int?})
## Ruft man setup() erneut auf, gleitet jeder neu Ausgeschiedene ruhig aus der
## Lebenden- in die "Raus"-Liste (kein Blinken).

const WARN := Color(1.0, 0.72, 0.38)
const TEXT := Color(0.95, 0.96, 1.0)
const DIM := Color(0.62, 0.64, 0.72)
const GLIDE_TIME := 0.7

var _prev_alive: Dictionary = {}     # peer -> bool aus dem letzten setup
var _root: Control
var _ghosts: Array = []
var _live_rows: Dictionary = {}      # peer -> Row-Control (Lebende)
var _out_rows: Dictionary = {}       # peer -> Row-Control (Raus)
var _first := true


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(560, 320)


func setup(d: Dictionary) -> void:
	var players: Array = []
	var pl = d.get("players", [])
	if typeof(pl) == TYPE_ARRAY:
		for p in pl:
			if typeof(p) == TYPE_DICTIONARY and p.has("peer"):
				players.append(p)
	var newly_out: Array = []
	if not _first:
		for p in players:
			if not bool(p.get("alive", true)) and _prev_alive.get(int(p.peer), false):
				newly_out.append(int(p.peer))
	# Startpositionen der Gleiter merken, bevor neu gebaut wird.
	var starts := {}
	for peer in newly_out:
		if _live_rows.has(peer) and is_instance_valid(_live_rows[peer]):
			var r: Control = _live_rows[peer]
			starts[peer] = {"pos": r.global_position - global_position, "size": r.size}
	_build(players, d, newly_out)
	_prev_alive.clear()
	for p in players:
		_prev_alive[int(p.peer)] = bool(p.get("alive", true))
	_first = false
	if not newly_out.is_empty():
		_glide(newly_out, starts)


func _build(players: Array, d: Dictionary, newly_out: Array) -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
	if _root:
		_root.queue_free()
	_live_rows.clear()
	_out_rows.clear()
	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)

	var winner := int(d.get("winner", -1))
	var alive_n := 0
	for p in players:
		if bool(p.get("alive", true)):
			alive_n += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_root.add_child(head)
	var title := Label.new()
	title.text = "Battle Royale"
	title.add_theme_font_override("font", UiTheme.heading_font())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	head.add_child(title)
	head.add_child(TeamBoard.make_chip(tr("Runde %d") % maxi(1, int(d.get("round", 1))), DIM))
	if bool(d.get("final", false)) and winner < 0:
		head.add_child(TeamBoard.make_chip("Finale", WARN))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var info := Label.new()
	info.text = tr("%d von %d dabei") % [alive_n, players.size()]
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", DIM)
	head.add_child(info)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	_root.add_child(cols)
	var left := _panel("Noch dabei", UiTheme.ACCENT)
	var right := _panel("Raus", DIM)
	cols.add_child(left[0])
	cols.add_child(right[0])

	var danger := int(d.get("danger", -1))
	var outs: Array = []
	for p in players:
		var peer := int(p.peer)
		if bool(p.get("alive", true)):
			var row := _row(p, peer == winner, peer == danger and winner < 0, false)
			left[1].add_child(row)
			_live_rows[peer] = row
		else:
			outs.append(p)
	# Zuletzt Ausgeschiedene oben.
	outs.sort_custom(func(a, b): return int(a.get("out_round", 0)) > int(b.get("out_round", 0)))
	for p in outs:
		var peer := int(p.peer)
		var row := _row(p, false, false, true)
		right[1].add_child(row)
		_out_rows[peer] = row
		if newly_out.has(peer):
			row.modulate.a = 0.0   # bleibt unsichtbar, bis der Gleiter landet
	if outs.is_empty():
		var l := Label.new()
		l.text = "Noch niemand."
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", DIM)
		right[1].add_child(l)
	if winner >= 0:
		for p in players:
			if int(p.peer) == winner:
				var w := Label.new()
				w.text = tr("%s gewinnt.") % str(p.get("name", "?"))
				w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				w.add_theme_font_size_override("font_size", 16)
				w.add_theme_color_override("font_color", UiTheme.GOOD)
				_root.add_child(w)


func _panel(title_text: String, col: Color) -> Array:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.glass_box(16, 0.5, 0.14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	var t := Label.new()
	t.text = tr(title_text).to_upper()
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", col)
	v.add_child(t)
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	v.add_child(sep)
	return [box, v]


func _row(p: Dictionary, is_winner: bool, in_danger: bool, out: bool) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05 if not out else 0.025)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if in_danger:
		sb.set_border_width_all(0)
		sb.border_width_left = 3
		sb.border_color = WARN
	if is_winner:
		sb.set_border_width_all(1)
		sb.border_color = Color(UiTheme.GOOD.r, UiTheme.GOOD.g, UiTheme.GOOD.b, 0.6)
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var nm := str(p.get("name", "?"))
	h.add_child(TeamBoard.make_avatar(nm, 28, out))
	var l := Label.new()
	l.text = nm
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", DIM if out else TEXT)
	h.add_child(l)
	if in_danger:
		h.add_child(TeamBoard.make_chip("In Gefahr", WARN))
	elif out and p.has("out_round"):
		var r := Label.new()
		r.text = tr("Runde %d") % int(p.out_round)
		r.add_theme_font_size_override("font_size", 13)
		r.add_theme_color_override("font_color", DIM)
		h.add_child(r)
	if p.has("score") and not out:
		var s := Label.new()
		s.text = UiTheme.fmt_score(int(p.score))
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", DIM)
		h.add_child(s)
	return row


## Name gleitet von der alten Position in die Raus-Liste.
func _glide(peers: Array, starts: Dictionary) -> void:
	await get_tree().process_frame   # Layout abwarten
	for peer in peers:
		if not starts.has(peer) or not _out_rows.has(peer):
			continue
		var target: Control = _out_rows[peer]
		if not is_instance_valid(target):
			continue
		var ghost: Control = _ghost_of(target, starts[peer].size)
		add_child(ghost)
		_ghosts.append(ghost)
		ghost.position = starts[peer].pos
		var tw := create_tween().set_parallel(true)
		tw.tween_property(ghost, "position", target.global_position - global_position, GLIDE_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.chain().tween_callback(_land.bind(ghost, target))


func _ghost_of(target: Control, sz: Vector2) -> Control:
	var g: Control = target.duplicate()
	g.modulate.a = 1.0
	var sb := StyleBoxFlat.new()   # deckend, damit nichts durchscheint
	sb.bg_color = Color(0.12, 0.13, 0.20)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	g.add_theme_stylebox_override("panel", sb)
	g.custom_minimum_size = Vector2(sz.x, 0)
	g.size = sz
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _land(ghost: Control, target: Control) -> void:
	if is_instance_valid(target):
		var tw := create_tween()
		tw.tween_property(target, "modulate:a", 1.0, 0.2)
	if is_instance_valid(ghost):
		ghost.queue_free()
	_ghosts.erase(ghost)
