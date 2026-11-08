class_name OrbitCareerPanel
extends VBoxContainer

## Orbit-Karriere im Song-Browser: ersetzt dort die Kartenliste. Oben die Stufe
## (z. B. "Stufe 2,1 ★ - noch 2 Maps bis 2,4 ★"), darunter 3 bis 5 Maps "Als
## Naechstes" aus der Bibliothek, unten die Online-Suche mit passendem
## Sterne-Fenster. Das Panel hat keine eigene Logik: song_select liefert die
## fertigen Daten (set_data), das Panel meldet nur Klicks.

signal picked(ms: MapSet, diff: int)
signal online_requested

const ROW_H := 64.0
const COVER := 52.0
const COL_ROW := Color(0.08, 0.08, 0.11, 0.94)
const COL_ROW_SEL := Color(0.13, 0.13, 0.18, 0.98)

const _COVER_SHADER := "shader_type canvas_item;
uniform vec2 rect_size = vec2(52.0, 52.0);
uniform float radius = 9.0;
void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	vec2 q = abs(p) - rect_size * 0.5 + vec2(radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= clamp(0.5 - d, 0.0, 1.0);
}"

var _head: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _foot: Button
var _rows: Array = []   # {btn, ms, diff}
var _sel_ms: MapSet = null
var _sel_diff := -1
var _cover_mat: ShaderMaterial


func _init() -> void:
	add_theme_constant_override("separation", 12)
	var sh := Shader.new()
	sh.code = _COVER_SHADER
	_cover_mat = ShaderMaterial.new()
	_cover_mat.shader = sh
	_head = PanelContainer.new()
	_head.add_theme_stylebox_override("panel", _head_box())
	add_child(_head)
	var cap := Label.new()
	cap.name = "Caption"
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", UiTheme.DIM)
	add_child(cap)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_foot = Button.new()
	_foot.custom_minimum_size = Vector2(0, 44)
	_foot.focus_mode = Control.FOCUS_NONE
	_foot.add_theme_font_size_override("font_size", 14)
	UiTheme.style_ghost_button(_foot, 10)
	_foot.pressed.connect(func(): online_requested.emit())
	add_child(_foot)


static func _head_box() -> StyleBoxFlat:
	var sb := UiTheme.glass_box(14, 0.5)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


## d: level (float), next_text, good (Serie), need (Laeufe bis Stufe), event
## ("" | "up" | "down" | "ready"), items [{ms, diff, stars, played}], pending
## (Maps, deren Sterne noch gerechnet werden), range_text ("2,0–2,6").
func set_data(d: Dictionary) -> void:
	for c in _head.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_head.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	vb.add_child(top)
	var lvl := Label.new()
	lvl.text = OrbitCareer.level_text(float(d.get("level", OrbitCareer.START_LEVEL)))
	lvl.add_theme_font_override("font", UiTheme.heading_font(1))
	lvl.add_theme_font_size_override("font_size", 30)
	lvl.add_theme_color_override("font_color", UiTheme.TEXT)
	top.add_child(lvl)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	top.add_child(_ticks(int(d.get("good", 0)), int(d.get("need", OrbitCareer.GOOD_NEED))))
	var sub := Label.new()
	sub.text = str(d.get("next_text", ""))
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UiTheme.DIM)
	vb.add_child(sub)
	var note := _event_text(str(d.get("event", "")), float(d.get("level", 0.0)))
	if note != "":
		vb.add_child(_note(note))

	(get_node("Caption") as Label).text = tr("ALS NÄCHSTES")
	_rows.clear()
	for c in _list.get_children():
		c.queue_free()
	var items: Array = d.get("items", [])
	for it in items:
		_list.add_child(_make_row(it))
	if items.is_empty():
		var empty := Label.new()
		var pend := int(d.get("pending", 0))
		empty.text = tr("Passende Maps werden gesucht …") if pend > 0 \
				else tr("In deiner Bibliothek ist gerade nichts für diese Stufe. Such online weiter.")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0, 48)
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", UiTheme.DIM)
		_list.add_child(empty)
	elif int(d.get("pending", 0)) > 0:
		var more := Label.new()
		more.text = tr("Weitere Maps werden noch geprüft …")
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", UiTheme.DIM)
		_list.add_child(more)
	_foot.text = tr("Online suchen · %s ★") % str(d.get("range_text", ""))
	_foot.tooltip_text = tr("Öffnet die Online-Suche mit passendem Sterne-Filter")
	_apply_selection()


static func _event_text(ev: String, level: float) -> String:
	match ev:
		"up":
			return TranslationServer.translate("Stufe gestiegen")
		"down":
			return TranslationServer.translate("Etwas leichter: die Stufe wurde angepasst")
		"ready":
			return TranslationServer.translate("Bereit für mehr: du springst auf %s ★") \
					% UiTheme.fmt_num(level, 1)
	return ""


## Drei kleine Striche: so viele gute Laeufe der Serie sind erreicht.
static func _ticks(good: int, need: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in maxi(need, 1):
		var t := ColorRect.new()
		t.custom_minimum_size = Vector2(22, 5)
		t.color = UiTheme.ACCENT if i < good else Color(1, 1, 1, 0.14)
		row.add_child(t)
	row.tooltip_text = TranslationServer.translate("Gute Läufe in Folge (ab 93 %)")
	return row


static func _note(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(3, 0)
	row.add_child(bar)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiTheme.TEXT)
	row.add_child(l)
	return row


func _make_row(it: Dictionary) -> Control:
	var ms: MapSet = it.ms
	var diff := int(it.diff)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, ROW_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	_style_row(btn, false)
	btn.pressed.connect(func(): picked.emit(ms, diff))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -14
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)
	var cover := TextureRect.new()
	cover.texture = ms.thumb_texture()
	cover.custom_minimum_size = Vector2(COVER, COVER)
	cover.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.material = _cover_mat
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cover)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_theme_constant_override("separation", 2)
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tb)
	var t := Label.new()
	t.text = "%s - %s" % [ms.artist, ms.title]
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", UiTheme.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(t)
	var v := Label.new()
	v.text = ms.version_name_at(diff).strip_edges()
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.clip_text = true
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", UiTheme.DIM)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(v)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(right)
	var st := Label.new()
	st.text = "★ " + UiTheme.fmt_num(float(it.stars), 2)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.add_theme_font_size_override("font_size", 16)
	st.add_theme_color_override("font_color", UiTheme.TEXT)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(st)
	if bool(it.get("played", false)):
		var pl := Label.new()
		pl.text = tr("schon gespielt")
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", UiTheme.DIM)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(pl)
	_rows.append({"btn": btn, "ms": ms, "diff": diff})
	return btn


static func _style_row(btn: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_ROW_SEL if selected else COL_ROW
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	sb.set_border_width_all(2 if selected else 1)
	sb.border_color = UiTheme.ACCENT if selected else Color(1, 1, 1, 0.07)
	for st in ["normal", "hover", "pressed", "focus"]:
		var box := sb
		if st == "hover" and not selected:
			box = sb.duplicate()
			box.border_color = Color(1, 1, 1, 0.22)
		btn.add_theme_stylebox_override(st, box)


## Gewaehlte Map hervorheben (Rahmen in Akzent wie in der Liste).
func set_selected(ms: MapSet, diff: int) -> void:
	_sel_ms = ms
	_sel_diff = diff
	_apply_selection()


func _apply_selection() -> void:
	for r in _rows:
		var on: bool = r.ms == _sel_ms and int(r.diff) == _sel_diff
		_style_row(r.btn as Button, on)
