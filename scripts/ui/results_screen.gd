class_name ResultsScreen
extends Control

## Results-Screen als eigenstaendige Komponente: geblurtes Cover, hochzaehlender
## Score, Riesen-Rank mit Glanz-Sweep + weichem Glow, Judgement-Karten mit
## Anteil-Balken, Stats, Hit-Error-Histogramm, Badges und Buttons.
## Aufruf: show_results(data) — Keys: is_fail, s (ManiaCore.stats()), pp,
## unranked, new_best, title, artist, version, cover_path, offsets (ms),
## player, date. Optional: cover (Texture2D), allow_retry, can_replay,
## is_replay, lobby.

signal retry_pressed
signal replay_pressed
signal clip_pressed
signal back_pressed

## Judgement-Farben wie im Gameplay (MAX, 300, 200, 100, 50, MISS).
const QUALITY_COLOR := [
	Color(1.0, 0.92, 0.55), Color(1.0, 1.0, 1.0), Color(0.4, 0.9, 1.0),
	Color(0.45, 1.0, 0.6), Color(0.75, 0.72, 0.5), Color(1.0, 0.28, 0.28),
]
const GRADE_COLOR := {
	"SS": Color(1.0, 0.94, 0.72), "S": Color(1.0, 0.85, 0.25),
	"A": Color(0.4, 1.0, 0.5), "B": Color(0.35, 0.75, 1.0),
	"C": Color(0.9, 0.6, 1.0), "D": Color(1.0, 0.4, 0.4),
}
const FAIL_COLOR := Color(1.0, 0.34, 0.38)
const CAPTION := Color(0.5, 0.53, 0.62)
const SCORE_COUNT_TIME := 0.9
const STAGGER := 0.07
const HIST_BINS := 41

const SWEEP_SHADER := """
shader_type canvas_item;
uniform float sweep = -1.0;
uniform vec2 box = vec2(400.0, 400.0);
uniform float strength = 0.65;
varying vec2 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float x = (lp.x + lp.y * 0.35) / (box.x + box.y * 0.35);
	float band = 1.0 - smoothstep(0.0, 0.06, abs(x - sweep));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), band * strength * COLOR.a * COLOR.a);
}
"""

var _data: Dictionary = {}
var _stats: Dictionary = {}
var _offsets: PackedFloat32Array = PackedFloat32Array()
var _hist: PackedFloat32Array = PackedFloat32Array()
var _hist_range := 100.0
var _hist_t := 0.0
var _hist_ctrl: Control
var _score_lbl: Label
var _acc_lbl: Label
var _rank_lbl: Label
var _rank_glow: TextureRect
var _rank_mat: ShaderMaterial
var _left_panel: Control
var _rank_area: Control
var _reveal: Array[Control] = []
var _bars: Array = []  # [Panel fill, float frac]
var _shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_results(data: Dictionary) -> void:
	_data = data
	_stats = data.get("s", {})
	_offsets = PackedFloat32Array(data.get("offsets", []))
	for c in get_children():
		c.queue_free()
	_reveal.clear()
	_bars.clear()
	_build_background()
	_build_header()
	_build_left_panel()
	_build_rank_area()
	_build_buttons()
	_shown = true
	_play_intro()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build_background() -> void:
	var base := ColorRect.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.color = UiTheme.BG
	add_child(base)
	var cover := _load_cover()
	if cover != null:
		var bg := TextureRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture = UiTheme.blurred_texture(cover, 14)
		bg.modulate = Color(0.5, 0.5, 0.56)
		add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.01, 0.03, 0.58)
	add_child(dim)
	# Vignette: Raender weich abdunkeln, Mitte bleibt offen.
	var vig := TextureRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.texture = _radial_tex(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.6), 0.35)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _build_header() -> void:
	var strip := ColorRect.new()
	strip.anchor_right = 1.0
	strip.offset_bottom = 84
	strip.color = Color(0, 0, 0, 0.42)
	add_child(strip)
	var line := TextureRect.new()
	line.anchor_right = 1.0
	line.offset_top = 84
	line.offset_bottom = 86
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(UiTheme.ACCENT, 0.0))
	g.set_color(1, Color(UiTheme.ACCENT2, 0.0))
	g.add_point(0.3, Color(UiTheme.ACCENT, 0.55))
	g.add_point(0.7, Color(UiTheme.ACCENT2, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 1
	line.texture = gt
	add_child(line)

	var title := Label.new()
	title.text = "%s — %s" % [str(_data.get("artist", "")), str(_data.get("title", ""))]
	title.position = Vector2(32, 12)
	title.add_theme_font_override("font", UiTheme.heading_font(1))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	strip.add_child(title)
	var sub := Label.new()
	sub.text = "[%s] · 4K" % str(_data.get("version", ""))
	sub.position = Vector2(32, 48)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT.lerp(UiTheme.TEXT, 0.4))
	strip.add_child(sub)

	var who := VBoxContainer.new()
	who.anchor_left = 1.0
	who.anchor_right = 1.0
	who.offset_left = -420
	who.offset_right = -32
	who.offset_top = 14
	who.add_theme_constant_override("separation", 2)
	strip.add_child(who)
	var p := Label.new()
	p.text = "gespielt von %s" % str(_data.get("player", "—"))
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_theme_font_size_override("font_size", 16)
	p.add_theme_color_override("font_color", UiTheme.TEXT)
	who.add_child(p)
	var d := Label.new()
	d.text = str(_data.get("date", "")).replace("T", " ")
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", UiTheme.DIM)
	who.add_child(d)
	_reveal.append(strip)


func _build_left_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 40
	panel.offset_top = 104
	panel.offset_bottom = -92
	panel.custom_minimum_size = Vector2(620, 0)
	var psb := UiTheme.glass_box(18, 0.72)
	psb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", psb)
	add_child(panel)
	_left_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# SCORE + Badges.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var cap := _caption("SCORE")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(cap)
	for b in _badges():
		top.add_child(_badge(str(b[0]), b[1]))
	_reveal.append(top)
	_score_lbl = Label.new()
	_score_lbl.text = "00000000"
	_score_lbl.add_theme_font_override("font", UiTheme.heading_font(5))
	_score_lbl.add_theme_font_size_override("font_size", 58)
	_score_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	_score_lbl.add_theme_color_override("font_shadow_color", Color(UiTheme.ACCENT, 0.18))
	_score_lbl.add_theme_constant_override("shadow_offset_y", 3)
	vb.add_child(_score_lbl)
	_reveal.append(_score_lbl)

	# Judgement-Karten (3x2) mit Anteil-Balken.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	var counts := [int(_stats.get("n_max", 0)), int(_stats.get("n300", 0)),
		int(_stats.get("n200", 0)), int(_stats.get("n100", 0)),
		int(_stats.get("n50", 0)), int(_stats.get("n_miss", 0))]
	var total := 0
	for c in counts:
		total += int(c)
	var tags := ["MAX", "300", "200", "100", "50", "MISS"]
	for i in 6:
		var frac := float(counts[i]) / float(maxi(total, 1))
		grid.add_child(_judge_card(tags[i], int(counts[i]), frac, QUALITY_COLOR[i]))
	_reveal.append(grid)

	# Accuracy · Max-Combo · pp.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var acc: float = float(_stats.get("accuracy", 0.0))
	var pp: float = float(_data.get("pp", -1.0))
	var acc_block := _stat_block("ACCURACY", "%.2f%%" % (acc * 100.0), UiTheme.TEXT)
	_acc_lbl = acc_block.get_meta("value")
	row.add_child(acc_block)
	row.add_child(_stat_block("MAX COMBO", "%dx" % int(_stats.get("max_combo", 0)), UiTheme.TEXT))
	var pp_txt := "—"
	if bool(_data.get("unranked", false)):
		pp_txt = "unranked"
	elif pp >= 0.0:
		pp_txt = "%.1f pp" % pp
	row.add_child(_stat_block("PERFORMANCE", pp_txt, UiTheme.ACCENT2))
	_reveal.append(row)

	# Hit-Error: Kopf mit UR/Mittel-Offset + Histogramm.
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var hcap := _caption("HIT ERROR")
	hcap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hcap)
	var tinfo := Label.new()
	tinfo.add_theme_font_size_override("font_size", 13)
	tinfo.add_theme_color_override("font_color", UiTheme.DIM)
	if _offsets.size() >= 2:
		var mean := 0.0
		var sq := 0.0
		for o in _offsets:
			mean += o
			sq += o * o
		mean /= float(_offsets.size())
		var variance := maxf(sq / float(_offsets.size()) - mean * mean, 0.0)
		tinfo.text = "UR %.0f    Ø %+.1f ms (%s)" % [sqrt(variance) * 10.0, mean,
			"spaet" if mean > 0.0 else "frueh"]
	else:
		tinfo.text = "keine Timing-Daten"
	hh.add_child(tinfo)
	_reveal.append(hh)
	_build_histogram_data()
	_hist_ctrl = Control.new()
	_hist_ctrl.custom_minimum_size = Vector2(0, 190)
	_hist_ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hist_ctrl.draw.connect(_draw_histogram)
	vb.add_child(_hist_ctrl)
	_reveal.append(_hist_ctrl)


func _build_rank_area() -> void:
	var area := Control.new()
	area.anchor_left = 0.0
	area.anchor_right = 1.0
	area.anchor_bottom = 1.0
	area.offset_left = 680
	area.offset_right = -40
	area.offset_top = 104
	area.offset_bottom = -92
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	_rank_area = area
	var is_fail := bool(_data.get("is_fail", false))
	var grade := "F" if is_fail else str(_stats.get("grade", "D"))
	var rc: Color = FAIL_COLOR if is_fail else GRADE_COLOR.get(grade, Color.WHITE)

	# Weicher Glow in Rank-Farbe (statisch, kein Pulsieren).
	_rank_glow = TextureRect.new()
	_rank_glow.anchor_left = 0.5
	_rank_glow.anchor_right = 0.5
	_rank_glow.anchor_top = 0.45
	_rank_glow.anchor_bottom = 0.45
	_rank_glow.offset_left = -300
	_rank_glow.offset_right = 300
	_rank_glow.offset_top = -300
	_rank_glow.offset_bottom = 300
	_rank_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rank_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_rank_glow.texture = _radial_tex(Color(rc, 0.34), Color(rc, 0.0), 0.0)
	_rank_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_rank_glow)

	_rank_lbl = Label.new()
	_rank_lbl.text = grade
	_rank_lbl.anchor_right = 1.0
	_rank_lbl.anchor_bottom = 0.9
	_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_lbl.add_theme_font_override("font", UiTheme.heading_font(0 if grade.length() < 2 else -8))
	_rank_lbl.add_theme_font_size_override("font_size", 400 if grade.length() < 2 else 330)
	_rank_lbl.add_theme_color_override("font_color", rc)
	_rank_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_rank_lbl.add_theme_constant_override("shadow_offset_y", 8)
	var sh := Shader.new()
	sh.code = SWEEP_SHADER
	_rank_mat = ShaderMaterial.new()
	_rank_mat.shader = sh
	_rank_lbl.material = _rank_mat
	area.add_child(_rank_lbl)

	var tag := Label.new()
	tag.anchor_top = 0.82
	tag.anchor_right = 1.0
	tag.anchor_bottom = 0.92
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UiTheme.heading_font(6))
	tag.add_theme_font_size_override("font_size", 26)
	if is_fail:
		tag.text = "FAILED"
		tag.add_theme_color_override("font_color", FAIL_COLOR)
	elif int(_stats.get("n_miss", 0)) == 0:
		tag.text = "FULL COMBO"
		tag.add_theme_color_override("font_color", UiTheme.ACCENT)
	else:
		tag.text = "CLEAR"
		tag.add_theme_color_override("font_color", UiTheme.DIM)
	area.add_child(tag)
	_reveal.append(tag)


func _build_buttons() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -900
	bar.offset_right = -40
	bar.offset_top = -72
	bar.offset_bottom = -24
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	var is_replay := bool(_data.get("is_replay", false))
	var lobby := bool(_data.get("lobby", false))
	if bool(_data.get("allow_retry", not lobby)):
		bar.add_child(_button("Nochmal ansehen  (R)" if is_replay else "Retry  (R)", true,
			retry_pressed.emit))
	if bool(_data.get("can_replay", true)):
		bar.add_child(_button("Selbst spielen" if is_replay else "▶ Replay", false,
			replay_pressed.emit))
	bar.add_child(_button("⤓ Clip speichern", false, clip_pressed.emit))
	bar.add_child(_button("Zur Lobby" if lobby else "Song-Browser", false, back_pressed.emit))
	_reveal.append(bar)


# ---------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------

func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiTheme.heading_font(3))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", CAPTION)
	return l


func _badges() -> Array:
	var out := []
	var is_fail := bool(_data.get("is_fail", false))
	if bool(_data.get("new_best", false)) and not is_fail:
		out.append(["NEW BEST", Color(1.0, 0.83, 0.25)])
	if not is_fail and str(_stats.get("grade", "")) == "SS":
		out.append(["SS", UiTheme.ACCENT2])
	if not is_fail and int(_stats.get("n_miss", 1)) == 0:
		out.append(["FC", UiTheme.ACCENT])
	if bool(_data.get("unranked", false)):
		out.append(["UNRANKED", UiTheme.DIM])
	return out


func _badge(t: String, col: Color) -> PanelContainer:
	var b := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.16)
	sb.border_color = Color(col, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	b.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.25))
	b.add_child(l)
	return b


func _judge_card(tag: String, count: int, frac: float, col: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.glass_box(12, 0.38, 0.0)
	sb.border_color = Color(col, 0.28)
	sb.shadow_size = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var t := Label.new()
	t.text = tag
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("font", UiTheme.heading_font(1))
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", col)
	top.add_child(t)
	var n := Label.new()
	n.text = "%d" % count
	n.add_theme_font_override("font", UiTheme.heading_font(1))
	n.add_theme_font_size_override("font_size", 21)
	n.add_theme_color_override("font_color", UiTheme.TEXT)
	top.add_child(n)
	# Anteil-Balken (fuellt sich beim Einblenden).
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 5)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(1, 1, 1, 0.07)
	tsb.set_corner_radius_all(3)
	track.add_theme_stylebox_override("panel", tsb)
	vb.add_child(track)
	var fill := Panel.new()
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.0
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(col, 0.85)
	fsb.set_corner_radius_all(3)
	fill.add_theme_stylebox_override("panel", fsb)
	track.add_child(fill)
	_bars.append([fill, clampf(frac, 0.0, 1.0)])
	var pct := Label.new()
	pct.text = "%.1f%%" % (frac * 100.0)
	pct.add_theme_font_size_override("font_size", 11)
	pct.add_theme_color_override("font_color", CAPTION)
	vb.add_child(pct)
	return card


func _stat_block(cap: String, value: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.glass_box(12, 0.3, 0.08)
	sb.shadow_size = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	p.add_child(vb)
	vb.add_child(_caption(cap))
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", UiTheme.heading_font(1))
	v.add_theme_font_size_override("font_size", 25)
	v.add_theme_color_override("font_color", col)
	vb.add_child(v)
	p.set_meta("value", v)
	return p


func _button(t: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(150, 46)
	UiTheme.style_button(b, primary)
	b.pressed.connect(cb)
	return b


## Radiale Verlaufs-Textur (Mitte -> Rand). inner_stop: ab wo der Verlauf
## beginnt (0 = sofort).
func _radial_tex(center: Color, edge: Color, inner_stop: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, center)
	g.set_color(1, edge)
	if inner_stop > 0.0:
		g.add_point(inner_stop, center)
	else:
		g.add_point(0.45, center.lerp(edge, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5) if inner_stop <= 0.0 else Vector2(1.15, 1.15)
	gt.width = 256
	gt.height = 256
	return gt


func _load_cover() -> Texture2D:
	var tex = _data.get("cover", null)
	if tex is Texture2D:
		return tex
	var path := str(_data.get("cover_path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Histogramm
# ---------------------------------------------------------------------------

func _build_histogram_data() -> void:
	_hist = PackedFloat32Array()
	_hist.resize(HIST_BINS)
	_hist.fill(0.0)
	if _offsets.is_empty():
		return
	# Bereich: 99. Perzentil der |Offsets|, auf 10 ms gerundet, 40..160 ms.
	var abs_sorted := PackedFloat32Array()
	for o in _offsets:
		abs_sorted.append(absf(o))
	abs_sorted.sort()
	var p99: float = abs_sorted[mini(int(abs_sorted.size() * 0.99), abs_sorted.size() - 1)]
	_hist_range = clampf(ceilf(p99 / 10.0) * 10.0, 40.0, 160.0)
	for o in _offsets:
		var t := (clampf(o, -_hist_range, _hist_range) + _hist_range) / (2.0 * _hist_range)
		var bi := clampi(int(t * HIST_BINS), 0, HIST_BINS - 1)
		_hist[bi] += 1.0
	var mx := 0.0
	for v in _hist:
		mx = maxf(mx, v)
	if mx > 0.0:
		for i in HIST_BINS:
			_hist[i] /= mx


func _draw_histogram() -> void:
	var c := _hist_ctrl
	var w := c.size.x
	var h := c.size.y - 16.0
	if w <= 0.0 or h <= 0.0:
		return
	var font := get_theme_default_font()
	# Grundlinie + Mittelachse.
	c.draw_line(Vector2(0, h), Vector2(w, h), Color(1, 1, 1, 0.10), 1.0)
	c.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(1, 1, 1, 0.16), 1.0)
	var bw := w / float(HIST_BINS)
	for i in HIST_BINS:
		var v: float = _hist[i] * _hist_t
		if v <= 0.0:
			continue
		var d := absf((float(i) + 0.5) / float(HIST_BINS) - 0.5) * 2.0
		var col := UiTheme.ACCENT.lerp(UiTheme.ACCENT2, smoothstep(0.15, 0.9, d))
		col.a = 0.85
		var bh := maxf(v * (h - 4.0), 2.0)
		c.draw_rect(Rect2(i * bw + 1.0, h - bh, maxf(bw - 2.0, 1.0), bh), col)
	# Mittel-Offset-Marker.
	if _offsets.size() >= 2:
		var mean := 0.0
		for o in _offsets:
			mean += o
		mean /= float(_offsets.size())
		var mx := w * 0.5 + clampf(mean / _hist_range, -1.0, 1.0) * w * 0.5
		c.draw_line(Vector2(mx, -2), Vector2(mx, h), Color(1, 1, 1, 0.7 * _hist_t), 2.0)
	var lc := Color(CAPTION, 0.9)
	c.draw_string(font, Vector2(0, h + 14), "-%d ms  frueh" % int(_hist_range),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
	c.draw_string(font, Vector2(w * 0.5 - 4, h + 14), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
	c.draw_string(font, Vector2(0, h + 14), "spaet  +%d ms" % int(_hist_range),
		HORIZONTAL_ALIGNMENT_RIGHT, w, 11, lc)


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _play_intro() -> void:
	for c in _reveal:
		c.modulate.a = 0.0
	_rank_lbl.modulate.a = 0.0
	_rank_glow.modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# Gestaffeltes Einblenden aller Bloecke.
	var tw := create_tween().set_parallel(true)
	for i in _reveal.size():
		tw.tween_property(_reveal[i], "modulate:a", 1.0, 0.32).set_delay(0.05 + STAGGER * i)
	# Linkes Panel gleitet weich herein.
	var lx := _left_panel.position.x
	_left_panel.position.x = lx - 36.0
	_left_panel.modulate.a = 0.0
	tw.tween_property(_left_panel, "position:x", lx, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_left_panel, "modulate:a", 1.0, 0.3)

	# Score + Accuracy zaehlen hoch.
	var score := float(_stats.get("score", 0))
	var acc := float(_stats.get("accuracy", 0.0))
	tw.tween_method(_set_counters.bind(score, acc), 0.0, 1.0, SCORE_COUNT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.15)
	# Anteil-Balken + Histogramm wachsen.
	for i in _bars.size():
		var fill: Panel = _bars[i][0]
		tw.tween_property(fill, "anchor_right", float(_bars[i][1]), 0.6) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.3 + 0.04 * i)
	tw.tween_method(_set_hist_t, 0.0, 1.0, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.45)

	# Rank: Zoom-Pop, Glow faehrt weich hoch, danach Glanz-Sweep.
	_rank_lbl.pivot_offset = _rank_lbl.size * 0.5
	_rank_lbl.scale = Vector2.ONE * 1.3
	_rank_mat.set_shader_parameter("box", _rank_lbl.size)
	_rank_mat.set_shader_parameter("sweep", -1.0)
	tw.tween_property(_rank_lbl, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.35)
	tw.tween_property(_rank_lbl, "modulate:a", 1.0, 0.25).set_delay(0.35)
	tw.tween_property(_rank_glow, "modulate:a", 1.0, 0.9).set_delay(0.45)
	tw.tween_method(_set_sweep, -0.2, 1.2, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.95)
	tw.chain().tween_callback(_start_idle_sweep)


func _set_counters(t: float, score: float, acc: float) -> void:
	if is_instance_valid(_score_lbl):
		_score_lbl.text = "%08d" % int(roundf(score * t))
	if is_instance_valid(_acc_lbl):
		_acc_lbl.text = "%.2f%%" % (acc * t * 100.0)


func _set_hist_t(t: float) -> void:
	_hist_t = t
	if is_instance_valid(_hist_ctrl):
		_hist_ctrl.queue_redraw()


func _set_sweep(v: float) -> void:
	if _rank_mat != null:
		_rank_mat.set_shader_parameter("sweep", v)


## Ruhiger Wiederholungs-Sweep alle paar Sekunden (dezent, kein Flackern).
func _start_idle_sweep() -> void:
	if not is_inside_tree() or _rank_mat == null:
		return
	_rank_mat.set_shader_parameter("box", _rank_lbl.size)
	var tw := create_tween().set_loops()
	tw.tween_interval(5.0)
	tw.tween_method(_set_sweep, -0.2, 1.2, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var lobby := bool(_data.get("lobby", false))
		if event.keycode == KEY_R and bool(_data.get("allow_retry", not lobby)):
			get_viewport().set_input_as_handled()
			retry_pressed.emit()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			back_pressed.emit()
