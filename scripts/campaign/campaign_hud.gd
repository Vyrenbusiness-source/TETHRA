class_name CampaignHud
extends CanvasLayer

## Ziele einer Kampagnen-Stufe dezent im Spiel (alle Modi, links): Stufe, drei Ziele, live
## gehalten / offen / verloren mit aktuellem Wert. Haengt GameSession an die Spielszene
## (Kind der Szene, endet mit ihr). Liest game.core.stats() fuenfmal je Sekunde.
## Unter dem HUD der Szene (Ebene 0): Pause und Ergebnis liegen darueber; erscheint das
## Ergebnis, blendet sich die Zeile aus.

const TICK := 0.2
const BASE_H := 720.0

var stage: Dictionary = {}
var head := ""
## Skip-Pruefung: zusaetzliche Zeile "99 % Accuracy" mit aktuellem Stand.
var trial := false
var _game: Node
var _box: VBoxContainer
var _stars: Array[CampaignStars] = []
var _texts: Array[Label] = []
var _values: Array[Label] = []
var _last: Array = []
var _trial_val: Label
var _t := 0.0


## Ziele der Stufe stage_id an die Spielszene haengen (null, wenn die Stufe fehlt).
static func attach_stage(game: Node, stage_id: String, trial: bool = false) -> CampaignHud:
	var all := Campaign.load_data()
	var data := Campaign.for_mode(all, Campaign.mode_of_stage(all, stage_id))
	var st := Campaign.stage_by_id(data, stage_id)
	var ci := Campaign.chapter_index_of(data, stage_id)
	if st.is_empty() or ci < 0:
		return null
	var head := "%s  ·  %s  ·  %s" % [Campaign.tr_("Kampagne"),
		Campaign.world_label(str((Campaign.chapters(data)[ci] as Dictionary).get("world", ""))),
		Campaign.stage_label(st, Campaign.stage_index_of(data, stage_id))]
	var h := attach(game, st, head)
	h.trial = trial
	return h


static func attach(game: Node, p_stage: Dictionary, p_head: String) -> CampaignHud:
	var h := CampaignHud.new()
	h.name = "CampaignHud"
	h.stage = p_stage
	h.head = p_head
	h._game = game
	game.add_child(h)
	return h


func _ready() -> void:
	layer = 0
	_build()
	get_tree().node_added.connect(_on_node_added)
	get_viewport().size_changed.connect(_build)
	_update()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_build):
		vp.size_changed.disconnect(_build)


func _on_node_added(n: Node) -> void:
	if n.get_script() != null and (n.get_script() as Script).resource_path == "res://scripts/ui/results_screen.gd":
		visible = false


func _build() -> void:
	if not is_inside_tree():
		return
	if _box != null:
		_box.queue_free()
	_stars.clear()
	_texts.clear()
	_values.clear()
	_last.clear()
	var s := clampf(get_viewport().get_visible_rect().size.y / BASE_H, 0.6, 3.0)
	_box = VBoxContainer.new()
	_box.name = "Goals"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", int(roundf(4.0 * s)))
	_box.modulate.a = 0.85
	add_child(_box)
	var title := _label(head, 12.0 * s, UiTheme.DIM, true)
	_box.add_child(title)
	_trial_val = null
	if trial:
		# Skip-Pruefung: die Grenze zuerst, die Ziele zaehlen weiter fuer die Sterne der Boss-Stufe.
		var tr_row := HBoxContainer.new()
		tr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr_row.add_theme_constant_override("separation", int(roundf(8.0 * s)))
		tr_row.add_child(_label(Campaign.tr_("Skip-Prüfung: %s Accuracy") % Campaign.pct_text(Campaign.TRIAL_ACC),
			13.0 * s, UiTheme.ACCENT2, true))
		_trial_val = _label("", 13.0 * s, UiTheme.DIM)
		_trial_val.custom_minimum_size.x = roundf(54.0 * s)
		_trial_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tr_row.add_child(_trial_val)
		_box.add_child(tr_row)
	var goals: Array = stage.get("goals", [])
	for i in goals.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", int(roundf(8.0 * s)))
		var star := CampaignStars.make([false], roundf(12.0 * s))
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(star)
		var t := _label(Campaign.goal_short(goals[i]), 13.0 * s, UiTheme.TEXT)
		row.add_child(t)
		var v := _label("", 13.0 * s, UiTheme.DIM)
		v.custom_minimum_size.x = roundf(54.0 * s)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		_box.add_child(row)
		_stars.append(star)
		_texts.append(t)
		_values.append(v)
	_box.reset_size()
	# Links unter den Werten der Szene (Mania: Rang/Genauigkeit, Orbit: Punkte/Genauigkeit):
	# dort ist in allen Modi Hintergrund, die Strecke beginnt weiter rechts.
	_box.position = Vector2(roundf(24.0 * s), roundf(BASE_H * 0.6 * s))
	_update()


func _label(text: String, px: float, col: Color, heading: bool = false) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", int(roundf(px)))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", maxi(int(roundf(px * 0.28)), 2))
	if heading:
		l.add_theme_font_override("font", UiTheme.heading_font(0))
	return l


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	_update()


func _stats() -> Dictionary:
	if not is_instance_valid(_game):
		return {}
	var core: Variant = _game.get("core")
	if core == null or not (core is Object) or not (core as Object).has_method("stats"):
		return {}
	var s: Variant = (core as Object).call("stats")
	return s if s is Dictionary else {}


func _update() -> void:
	var st := _stats()
	if _trial_val != null and not st.is_empty():
		var acc := float(st.get("accuracy", 0.0))
		_trial_val.text = Campaign.acc_text(acc)
		_trial_val.add_theme_color_override("font_color", UiTheme.BAD if bool(st.get("failed", false))
			else (UiTheme.ACCENT if acc + 0.000001 >= Campaign.TRIAL_ACC else UiTheme.DIM))
	var goals: Array = stage.get("goals", [])
	var live := Campaign.goals_live(stage, st) if not st.is_empty() else []
	for i in mini(goals.size(), _stars.size()):
		var state := int(live[i]) if i < live.size() else Campaign.LIVE_OPEN
		var val := Campaign.goal_live_value(goals[i], st) if not st.is_empty() else ""
		if i < _last.size() and _last[i] == [state, val]:
			continue
		while _last.size() <= i:
			_last.append([])
		_last[i] = [state, val]
		var star := _stars[i]
		star.met = [state == Campaign.LIVE_HOLD]
		star.col_off = Color(UiTheme.BAD.r, UiTheme.BAD.g, UiTheme.BAD.b, 0.8) if state == Campaign.LIVE_LOST \
			else Color(UiTheme.DIM.r, UiTheme.DIM.g, UiTheme.DIM.b, 0.7)
		star.queue_redraw()
		_texts[i].add_theme_color_override("font_color",
			UiTheme.DIM if state == Campaign.LIVE_LOST else UiTheme.TEXT)
		_values[i].text = val
		_values[i].add_theme_color_override("font_color",
			UiTheme.BAD if state == Campaign.LIVE_LOST else (UiTheme.ACCENT if state == Campaign.LIVE_HOLD else UiTheme.DIM))
