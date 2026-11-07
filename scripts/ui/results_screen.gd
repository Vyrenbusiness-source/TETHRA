class_name ResultsScreen
extends Control

## Results-Screen als eigenstaendige Komponente: geblurtes Cover, hochzaehlender
## Score, Riesen-Rank im Genauigkeits-Ring mit Glanz-Sweep + weichem Glow,
## Urteils-Karten mit Anteil-Balken, Stats, Hit-Error-Histogramm, Badges und
## Buttons mit Keycaps. Panel und Rang bilden eine geschlossene, zentrierte
## Gruppe auf gemeinsamer Achse (kein Loch in der Mitte).
## Aufruf: show_results(data) — Keys: is_fail, s (ManiaCore.stats()), pp,
## unranked, new_best, title, artist, version, cover_path, offsets (ms),
## player, date. Optional: cover (Texture2D), allow_retry, can_replay,
## is_replay, lobby.

signal retry_pressed
signal replay_pressed
signal clip_pressed
signal back_pressed

## Urteilsfarben (MAX, 300, 200, 100, 50, MISS): MAX gold, 300 weiss-cyan,
## 200 gruen, 100 blau, 50 grau, MISS rot.
const QUALITY_COLOR := [
	Color(1.0, 0.85, 0.42), Color(0.84, 0.97, 1.0), Color(0.47, 0.95, 0.62),
	Color(0.42, 0.64, 1.0), Color(0.64, 0.66, 0.72), Color(1.0, 0.38, 0.42),
]
const GRADE_COLOR := {
	"SS": Color(1.0, 0.94, 0.72), "S": Color(1.0, 0.85, 0.25),
	"A": Color(0.4, 1.0, 0.5), "B": Color(0.35, 0.75, 1.0),
	"C": Color(0.9, 0.6, 1.0), "D": Color(1.0, 0.4, 0.4),
}
const FAIL_COLOR := Color(1.0, 0.34, 0.38)
## Mikro-Labels: hell genug fuer Kontrast auf Glas (nicht unter 12 px nutzen).
const CAPTION := Color(0.68, 0.71, 0.80)
const MUTED := Color(0.50, 0.53, 0.60)
const SCORE_COUNT_TIME := 0.9
const STAGGER := 0.07
const HIST_BINS := 41
const PANEL_W := 640.0
const RANK_COL_W := 560.0
const RING := 500.0
const GROUP_GAP := 48

const SWEEP_SHADER := """
shader_type canvas_item;
uniform float sweep = -1.0;
uniform vec2 box = vec2(400.0, 400.0);
uniform float strength = 0.55;
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
var _place_tag: Label
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
var _rank_color := Color.WHITE
var _ring_ctrl: Control
var _ring_t := 0.0
var _left_panel: Control
var _main_row: HBoxContainer
var _reveal: Array[Control] = []
var _bars: Array = []  # [Panel fill, float frac]
var _shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


var _toast: PanelContainer
var _toast_label: Label
var _toast_btn: Button
var _toast_folder := ""
var _toast_tw: Tween


## Glas-Toast oben mittig (Header-Leerraum) (Clip-Export). sticky = bleibt stehen (Fortschritt),
## sonst blendet er nach 4 s aus (mit Ordner-Button: 12 s). folder != "" zeigt
## den Button "Ordner oeffnen" (OS.shell_open).
func show_toast(text: String, sticky: bool, folder: String = "") -> void:
	if _toast == null or not is_instance_valid(_toast):
		_toast = PanelContainer.new()
		_toast.anchor_left = 0.5
		_toast.anchor_right = 0.5
		_toast.anchor_top = 0.0
		_toast.anchor_bottom = 0.0
		_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast.grow_vertical = Control.GROW_DIRECTION_END
		_toast.offset_top = 14
		_toast.offset_bottom = 14
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiTheme.glass_box(12, 0.9)
		sb.set_content_margin_all(10)
		_toast.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.add_child(hb)
		_toast_label = Label.new()
		_toast_label.add_theme_font_size_override("font_size", 15)
		_toast_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		_toast_label.custom_minimum_size.x = 320
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_toast_label)
		_toast_btn = Button.new()
		_toast_btn.text = "Ordner öffnen"
		UiTheme.style_button(_toast_btn, false)
		_toast_btn.pressed.connect(func() -> void: open_folder(_toast_folder))
		hb.add_child(_toast_btn)
		add_child(_toast)
	_toast_label.text = text
	_toast_label.custom_minimum_size.x = clampf(size.x * 0.4, 320.0, 760.0) if size.x > 0.0 else 600.0
	_toast_folder = folder
	_toast_btn.visible = folder != ""
	_toast.modulate.a = 1.0
	_toast.reset_size()
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	if not sticky:
		_toast_tw = create_tween()
		_toast_tw.tween_interval(12.0 if folder != "" else 4.0)
		_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


## Ordner im Explorer oeffnen. Gibt den OS-Fehlercode zurueck (OK = 0).
func open_folder(folder: String) -> int:
	if folder == "":
		return ERR_INVALID_PARAMETER
	return OS.shell_open(ProjectSettings.globalize_path(folder))


## Clip-Export-Ergebnis als Toast: "Clip gespeichert: <Pfad>" + Ordner-Button,
## bei Fehler der Grund (ClipExporter.last_error).
func show_clip_result(ok: bool, path: String, error: String = "") -> void:
	if ok:
		show_toast("Clip gespeichert: %s" % path, false, path.get_base_dir())
	else:
		show_toast("Clip-Export fehlgeschlagen: %s" % (error if error != "" else "unbekannt"), false)


## Multiplayer: Platzierungs-Text unter dem Rang, weich eingeblendet.
func set_placement(text: String, win: bool) -> void:
	if _place_tag == null or not is_instance_valid(_place_tag) or _place_tag.text == text:
		return
	_place_tag.text = text
	_place_tag.add_theme_color_override("font_color",
		UiTheme.ACCENT if win else UiTheme.TEXT)
	_place_tag.modulate.a = 0.0
	create_tween().tween_property(_place_tag, "modulate:a", 1.0, 0.5)


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
	var group := _build_group()
	_build_left_panel(_main_row)
	_build_rank_area(_main_row)
	_build_buttons(group)
	_shown = true
	_play_intro()


# ---------------------------------------------------------------------------
# Formatierung (deutsch)
# ---------------------------------------------------------------------------

## 923412 -> "923.412" (Tausenderpunkt, keine fuehrenden Nullen).
static func fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if n < 0 else "") + out


## 96.666 -> "96,67" (Dezimalkomma).
static func fmt_dec(v: float, decimals: int) -> String:
	return (("%." + str(decimals) + "f") % v).replace(".", ",")


## 0.9667 -> "96,67 %".
static func fmt_pct(frac: float, decimals: int = 2) -> String:
	return fmt_dec(frac * 100.0, decimals) + " %"


## ISO "2026-11-06T22:37:00" -> "06.11.2026 22:37".
static func fmt_date(iso: String) -> String:
	if iso.strip_edges() == "":
		return ""
	var d := Time.get_datetime_dict_from_datetime_string(iso, false)
	if int(d.get("year", 0)) <= 0:
		return iso
	return "%02d.%02d.%04d %02d:%02d" % [int(d.get("day", 0)), int(d.get("month", 0)),
		int(d.get("year", 0)), int(d.get("hour", 0)), int(d.get("minute", 0))]


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


## Aktive Mods dieses Laufs in fester Reihenfolge (leer ohne Mods).
func active_mods() -> Array:
	var out: Array = []
	var m: Dictionary = _data.get("mods", GameSession.mods)
	for k in ["SV", "NF"]:
		if bool(m.get(k, false)):
			out.append(k)
	return out


func _mod_badge(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var col: Color = UiTheme.ACCENT2
	sb.bg_color = Color(col, 0.2)
	sb.border_color = Color(col, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col.lerp(UiTheme.TEXT, 0.4))
	p.add_child(l)
	return p


func _build_header() -> void:
	var strip := ColorRect.new()
	strip.anchor_right = 1.0
	strip.offset_bottom = 84
	strip.color = Color(0, 0, 0, 0.42)
	add_child(strip)
	var line := TextureRect.new()
	line.anchor_right = 1.0
	line.offset_top = 84
	line.offset_bottom = 85
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(UiTheme.ACCENT, 0.0))
	g.set_color(1, Color(UiTheme.ACCENT2, 0.0))
	g.add_point(0.3, Color(UiTheme.ACCENT, 0.45))
	g.add_point(0.7, Color(UiTheme.ACCENT2, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 1
	line.texture = gt
	add_child(line)

	var title := Label.new()
	title.text = "%s — %s" % [str(_data.get("artist", "")), str(_data.get("title", ""))]
	title.position = Vector2(40, 12)
	title.add_theme_font_override("font", UiTheme.heading_font(1))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 2)
	strip.add_child(title)
	var sub := Label.new()
	sub.text = "%s  ·  4K" % str(_data.get("version", "")).strip_edges()
	sub.position = Vector2(41, 48)
	sub.add_theme_font_override("font", UiTheme.heading_font(1))
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT.lerp(UiTheme.TEXT, 0.35))
	strip.add_child(sub)
	# Mod-Badges (SV, NF) hinter der Schwierigkeit.
	var mod_row := HBoxContainer.new()
	mod_row.position = Vector2(41 + 8, 46)
	mod_row.add_theme_constant_override("separation", 6)
	strip.add_child(mod_row)
	for m in active_mods():
		mod_row.add_child(_mod_badge(m))
	mod_row.position.x = sub.position.x + sub.get_theme_font("font").get_string_size(
		sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12

	var who := VBoxContainer.new()
	who.anchor_left = 1.0
	who.anchor_right = 1.0
	who.offset_left = -440
	who.offset_right = -40
	who.offset_top = 14
	who.add_theme_constant_override("separation", 3)
	strip.add_child(who)
	var p := HBoxContainer.new()
	p.alignment = BoxContainer.ALIGNMENT_END
	p.add_theme_constant_override("separation", 6)
	who.add_child(p)
	var pl := Label.new()
	pl.text = "gespielt von"
	pl.add_theme_font_size_override("font_size", 15)
	pl.add_theme_color_override("font_color", CAPTION)
	p.add_child(pl)
	var pn := Label.new()
	pn.text = str(_data.get("player", "–"))
	pn.add_theme_font_override("font", UiTheme.heading_font(1))
	pn.add_theme_font_size_override("font_size", 17)
	pn.add_theme_color_override("font_color", UiTheme.TEXT)
	p.add_child(pn)
	var d := Label.new()
	d.text = fmt_date(str(_data.get("date", "")))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	d.add_theme_font_size_override("font_size", 14)
	d.add_theme_color_override("font_color", CAPTION)
	who.add_child(d)
	_reveal.append(strip)


## Zentrierte Gruppe: oben Panel + Rang (gemeinsame Mittelachse), unten die
## Button-Leiste exakt so breit wie beide zusammen. Im Lobby-Modus links
## buendig, damit rechts Platz fuer die Rangliste bleibt.
func _build_group() -> VBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 40
	row.offset_right = -40
	row.offset_top = 108
	row.offset_bottom = -28
	row.alignment = BoxContainer.ALIGNMENT_BEGIN if bool(_data.get("lobby", false)) \
		else BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 20)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(group)
	_main_row = HBoxContainer.new()
	_main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_row.add_theme_constant_override("separation", GROUP_GAP)
	_main_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(_main_row)
	return group


func _build_left_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var psb := UiTheme.glass_box(18, 0.72)
	psb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", psb)
	parent.add_child(panel)
	_left_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	# PUNKTE + Badges.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var cap := _caption("PUNKTE")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(cap)
	for b in _badges():
		top.add_child(_badge(str(b[0]), b[1]))
	_reveal.append(top)
	_score_lbl = Label.new()
	_score_lbl.text = "0"
	_score_lbl.add_theme_font_override("font", UiTheme.heading_font(3))
	_score_lbl.add_theme_font_size_override("font_size", 64)
	_score_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	_score_lbl.add_theme_color_override("font_shadow_color", Color(UiTheme.ACCENT, 0.16))
	_score_lbl.add_theme_constant_override("shadow_offset_y", 3)
	_score_lbl.add_theme_constant_override("line_spacing", -6)
	vb.add_child(_score_lbl)
	_reveal.append(_score_lbl)

	# Urteils-Karten (3x2) mit Anteil-Balken.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
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

	# Genauigkeit · Max. Kombo · PP.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var acc: float = float(_stats.get("accuracy", 0.0))
	var acc_block := _stat_block("GENAUIGKEIT", fmt_pct(acc), UiTheme.TEXT)
	_acc_lbl = acc_block.get_meta("value")
	row.add_child(acc_block)
	row.add_child(_stat_block("MAX. KOMBO", "%s×" % fmt_int(int(_stats.get("max_combo", 0))),
		UiTheme.TEXT))
	row.add_child(_pp_block())
	_reveal.append(row)

	# Timing: Kopf mit UR/Mittel-Offset + Histogramm.
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var hcap := _caption("TIMING")
	hcap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hcap)
	var tinfo := Label.new()
	tinfo.add_theme_font_size_override("font_size", 14)
	tinfo.add_theme_color_override("font_color", CAPTION)
	if _offsets.size() >= 2:
		var mean := 0.0
		var sq := 0.0
		for o in _offsets:
			mean += o
			sq += o * o
		mean /= float(_offsets.size())
		var variance := maxf(sq / float(_offsets.size()) - mean * mean, 0.0)
		var sign_txt := "+" if mean >= 0.0 else "−"
		tinfo.text = "UR %s   ·   Ø %s%s ms %s" % [fmt_dec(sqrt(variance) * 10.0, 0),
			sign_txt, fmt_dec(absf(mean), 1), "zu spät" if mean > 0.0 else "zu früh"]
	else:
		tinfo.text = "keine Timing-Daten"
	hh.add_child(tinfo)
	_reveal.append(hh)
	_build_histogram_data()
	_hist_ctrl = Control.new()
	_hist_ctrl.custom_minimum_size = Vector2(0, 150)
	_hist_ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hist_ctrl.draw.connect(_draw_histogram)
	vb.add_child(_hist_ctrl)
	_reveal.append(_hist_ctrl)


func _build_rank_area(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(RANK_COL_W, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(col)
	var is_fail := bool(_data.get("is_fail", false))
	var grade := "F" if is_fail else str(_stats.get("grade", "D"))
	var rc: Color = FAIL_COLOR if is_fail else GRADE_COLOR.get(grade, Color.WHITE)
	_rank_color = rc

	# Ring = Genauigkeit (fuellt sich im Uhrzeigersinn), Rang mittig darin.
	_ring_ctrl = Control.new()
	_ring_ctrl.custom_minimum_size = Vector2(RING, RING)
	_ring_ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ring_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_ctrl.draw.connect(_draw_ring)
	col.add_child(_ring_ctrl)

	# Weicher Glow in Rank-Farbe (statisch, kein Pulsieren).
	_rank_glow = TextureRect.new()
	_rank_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rank_glow.offset_left = -90
	_rank_glow.offset_top = -90
	_rank_glow.offset_right = 90
	_rank_glow.offset_bottom = 90
	_rank_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rank_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_rank_glow.texture = _radial_tex(Color(rc, 0.26), Color(rc, 0.0), 0.0)
	_rank_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_ctrl.add_child(_rank_glow)
	# Innenflaeche: dunkles Glas, damit der Rang klar vor dem Cover steht.
	var disc := TextureRect.new()
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.offset_left = 26
	disc.offset_top = 26
	disc.offset_right = -26
	disc.offset_bottom = -26
	disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	disc.stretch_mode = TextureRect.STRETCH_SCALE
	disc.texture = _disc_tex(Color(0.05, 0.06, 0.10, 0.55))
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_ctrl.add_child(disc)

	_rank_lbl = Label.new()
	_rank_lbl.text = grade
	_rank_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rank_lbl.offset_top = -14
	_rank_lbl.offset_bottom = -14
	_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_lbl.add_theme_font_override("font", UiTheme.heading_font(0 if grade.length() < 2 else -10))
	_rank_lbl.add_theme_font_size_override("font_size", 330 if grade.length() < 2 else 250)
	_rank_lbl.add_theme_color_override("font_color", rc)
	# Duenne, farbverwandte Kontur + weicher Schatten statt dicker Kante.
	_rank_lbl.add_theme_color_override("font_outline_color", Color(rc.lightened(0.45), 0.55))
	_rank_lbl.add_theme_constant_override("outline_size", 3)
	_rank_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.30))
	_rank_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_rank_lbl.add_theme_constant_override("shadow_offset_y", 5)
	_rank_lbl.add_theme_constant_override("shadow_outline_size", 10)
	_rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SWEEP_SHADER
	_rank_mat = ShaderMaterial.new()
	_rank_mat.shader = sh
	_rank_lbl.material = _rank_mat
	_ring_ctrl.add_child(_rank_lbl)

	var tag := Label.new()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UiTheme.heading_font(7))
	tag.add_theme_font_size_override("font_size", 24)
	if is_fail:
		tag.text = "NICHT GESCHAFFT"
		tag.add_theme_color_override("font_color", FAIL_COLOR)
	elif int(_stats.get("n_miss", 0)) == 0:
		tag.text = "FULL COMBO"
		tag.add_theme_color_override("font_color", UiTheme.ACCENT)
	else:
		tag.text = "GESCHAFFT"
		tag.add_theme_color_override("font_color", UiTheme.TEXT.lerp(CAPTION, 0.4))
	# Multiplayer: statt "GESCHAFFT" zaehlt die Platzierung (FULL COMBO /
	# NICHT GESCHAFFT bleiben als Zusatz sichtbar).
	if Lobby.active and tag.text == "GESCHAFFT":
		tag.queue_free()
	else:
		col.add_child(tag)
		_reveal.append(tag)
	if Lobby.active:
		_place_tag = Label.new()
		_place_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_place_tag.add_theme_font_override("font", UiTheme.heading_font(7))
		_place_tag.add_theme_font_size_override("font_size", 30)
		_place_tag.text = "WARTE AUF ANDERE…"
		_place_tag.add_theme_color_override("font_color", UiTheme.TEXT.lerp(CAPTION, 0.4))
		col.add_child(_place_tag)
		_reveal.append(_place_tag)


func _build_buttons(group: Control) -> void:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 50)
	bar.add_theme_constant_override("separation", 12)
	group.add_child(bar)
	var is_replay := bool(_data.get("is_replay", false))
	var lobby := bool(_data.get("lobby", false))
	bar.add_child(_button("Zur Lobby" if lobby else "Zum Song-Browser", false,
		back_pressed.emit, "Esc"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	bar.add_child(_button("⤓  Clip speichern", false, clip_pressed.emit))
	if bool(_data.get("can_replay", true)):
		bar.add_child(_button("Selbst spielen" if is_replay else "▶  Replay ansehen", false,
			replay_pressed.emit))
	if bool(_data.get("allow_retry", not lobby)):
		bar.add_child(_button("Nochmal ansehen" if is_replay else "Nochmal", true,
			retry_pressed.emit, "R"))
	_reveal.append(bar)


# ---------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------

func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UiTheme.heading_font(3))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", CAPTION)
	return l


func _badges() -> Array:
	var out := []
	var is_fail := bool(_data.get("is_fail", false))
	if bool(_data.get("new_best", false)) and not is_fail:
		out.append(["NEUER REKORD", Color(1.0, 0.83, 0.25)])
	if not is_fail and str(_stats.get("grade", "")) == "SS":
		out.append(["SS", UiTheme.ACCENT2])
	if not is_fail and int(_stats.get("n_miss", 1)) == 0:
		out.append(["FC", UiTheme.ACCENT])
	if bool(_data.get("unranked", false)):
		out.append(["UNGEWERTET", UiTheme.DIM])
	return out


func _badge(t: String, col: Color) -> PanelContainer:
	var b := PanelContainer.new()
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.13)
	sb.border_color = Color(col, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
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
	sb.border_color = Color(col, 0.22)
	sb.border_width_left = 3
	sb.shadow_size = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var t := Label.new()
	t.text = tag
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_override("font", UiTheme.heading_font(2))
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", col)
	top.add_child(t)
	var n := Label.new()
	n.text = fmt_int(count)
	n.add_theme_font_override("font", UiTheme.heading_font(1))
	n.add_theme_font_size_override("font_size", 22)
	n.add_theme_color_override("font_color", UiTheme.TEXT if count > 0 else MUTED)
	top.add_child(n)
	# Anteil-Balken (fuellt sich beim Einblenden).
	var track := Panel.new()
	track.custom_minimum_size = Vector2(0, 4)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(1, 1, 1, 0.07)
	tsb.set_corner_radius_all(2)
	track.add_theme_stylebox_override("panel", tsb)
	vb.add_child(track)
	var fill := Panel.new()
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.0
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(col, 0.85)
	fsb.set_corner_radius_all(2)
	fill.add_theme_stylebox_override("panel", fsb)
	track.add_child(fill)
	_bars.append([fill, clampf(frac, 0.0, 1.0)])
	var pct := Label.new()
	pct.text = fmt_pct(frac, 1)
	pct.add_theme_font_size_override("font_size", 12)
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
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	vb.add_child(_caption(cap))
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", UiTheme.heading_font(1))
	v.add_theme_font_size_override("font_size", 26)
	v.add_theme_color_override("font_color", col)
	vb.add_child(v)
	p.set_meta("value", v)
	return p


## PP-Block: Wert in ACCENT2; ohne Wertung/unbekannt graues "–" mit Hinweis
## (Tooltip + kurze Zeile), nie ein nackter Strich.
func _pp_block() -> PanelContainer:
	var pp: float = float(_data.get("pp", -1.0))
	var unranked := bool(_data.get("unranked", false))
	if not unranked and pp >= 0.0:
		return _stat_block("LEISTUNG", "%s pp" % fmt_dec(pp, 1), UiTheme.ACCENT2)
	var p := _stat_block("LEISTUNG", "–", MUTED)
	var why := "Map ist nicht gewertet – keine PP" if unranked \
		else "PP für diese Map nicht berechenbar"
	p.tooltip_text = why
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v: Label = p.get_meta("value")
	v.add_theme_font_size_override("font_size", 30)
	var vb := v.get_parent()
	vb.remove_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	hb.add_child(v)
	var note := Label.new()
	note.text = "ungewertet" if unranked else "nicht verfügbar"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", MUTED)
	hb.add_child(note)
	return p


## Button mit optionaler Keycap rechts neben dem Text (z. B. "Nochmal [R]").
func _button(t: String, primary: bool, cb: Callable, key: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 50)
	UiTheme.style_button(b, primary)
	b.pressed.connect(cb)
	if key == "":
		b.text = t
		b.custom_minimum_size.x = 170
		return b
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.02, 0.05, 0.08) if primary else UiTheme.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(l)
	hb.add_child(_keycap(key, primary))
	_fit_button.call_deferred(b, hb)
	return b


func _fit_button(b: Button, hb: Control) -> void:
	if is_instance_valid(b) and is_instance_valid(hb):
		b.custom_minimum_size.x = maxf(170.0, hb.get_combined_minimum_size().x + 40.0)


func _keycap(key: String, on_primary: bool) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	if on_primary:
		sb.bg_color = Color(0.0, 0.06, 0.10, 0.14)
		sb.border_color = Color(0.0, 0.06, 0.10, 0.42)
	else:
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.border_color = Color(1, 1, 1, 0.30)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = key
	l.custom_minimum_size = Vector2(12, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.heading_font(1))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color",
		Color(0.02, 0.05, 0.08, 0.85) if on_primary else UiTheme.TEXT.lerp(CAPTION, 0.3))
	cap.add_child(l)
	return cap


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


## Gefuellte Scheibe mit weicher Kante (fuer die Innenflaeche des Rings).
func _disc_tex(col: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col, 0.0))
	g.add_point(0.96, col)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
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
# Genauigkeits-Ring
# ---------------------------------------------------------------------------

func _draw_ring() -> void:
	var c := _ring_ctrl
	var ctr := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5 - 10.0
	c.draw_arc(ctr, r, 0.0, TAU, 160, Color(1, 1, 1, 0.08), 6.0, true)
	c.draw_arc(ctr, r - 14.0, 0.0, TAU, 160, Color(1, 1, 1, 0.05), 1.0, true)
	# Viertel-Ticks am Aussenring.
	for i in 4:
		var a := -PI * 0.5 + TAU * 0.25 * i
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(ctr + dir * (r + 7.0), ctr + dir * (r + 13.0), Color(1, 1, 1, 0.16), 1.5, true)
	var acc := clampf(float(_stats.get("accuracy", 0.0)), 0.0, 1.0) * _ring_t
	if acc <= 0.0:
		return
	var a0 := -PI * 0.5
	var a1 := a0 + TAU * acc
	var pts := maxi(int(160.0 * acc), 8)
	# Weicher Unterleger + scharfe Linie; Farbe laeuft von Rang-Farbe zu hell.
	c.draw_arc(ctr, r, a0, a1, pts, Color(_rank_color, 0.12), 14.0, true)
	c.draw_arc(ctr, r, a0, a1, pts, Color(_rank_color, 0.88), 5.0, true)
	var tip := ctr + Vector2(cos(a1), sin(a1)) * r
	c.draw_circle(tip, 4.5, _rank_color.lerp(Color.WHITE, 0.55))


func _set_ring_t(t: float) -> void:
	_ring_t = t
	if is_instance_valid(_ring_ctrl):
		_ring_ctrl.queue_redraw()


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
	var h := c.size.y - 20.0
	if w <= 0.0 or h <= 0.0:
		return
	var font := get_theme_default_font()
	# Hilfslinien bei 25/50/75 %, Grundlinie + Mittelachse.
	for f in [0.25, 0.5, 0.75]:
		var y: float = h - (h - 4.0) * float(f)
		c.draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.035), 1.0)
	c.draw_line(Vector2(0, h), Vector2(w, h), Color(1, 1, 1, 0.12), 1.0)
	c.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(1, 1, 1, 0.16), 1.0)
	var bw := w / float(HIST_BINS)
	for i in HIST_BINS:
		var v: float = _hist[i] * _hist_t
		if v <= 0.0:
			continue
		var d := absf((float(i) + 0.5) / float(HIST_BINS) - 0.5) * 2.0
		var col := UiTheme.ACCENT.lerp(UiTheme.ACCENT2, smoothstep(0.15, 0.9, d))
		col.a = 0.82
		var bh := maxf(v * (h - 4.0), 2.0)
		var rect := Rect2(i * bw + 1.5, h - bh, maxf(bw - 3.0, 1.0), bh)
		c.draw_rect(rect, col)
		# Hellere Kappe oben: wirkt wie Glas statt flacher Block.
		c.draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(2.0, bh))),
			col.lerp(Color.WHITE, 0.45))
	# Mittel-Offset-Marker.
	if _offsets.size() >= 2:
		var mean := 0.0
		for o in _offsets:
			mean += o
		mean /= float(_offsets.size())
		var mx := w * 0.5 + clampf(mean / _hist_range, -1.0, 1.0) * w * 0.5
		c.draw_line(Vector2(mx, -2), Vector2(mx, h), Color(1, 1, 1, 0.7 * _hist_t), 2.0)
	var lc := CAPTION
	c.draw_string(font, Vector2(0, h + 17), "−%d ms  früh" % int(_hist_range),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)
	c.draw_string(font, Vector2(w * 0.5 - 20, h + 17), "0 ms", HORIZONTAL_ALIGNMENT_CENTER, 40, 12, lc)
	c.draw_string(font, Vector2(0, h + 17), "spät  +%d ms" % int(_hist_range),
		HORIZONTAL_ALIGNMENT_RIGHT, w, 12, lc)


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _play_intro() -> void:
	for c in _reveal:
		c.modulate.a = 0.0
	_rank_lbl.modulate.a = 0.0
	_rank_glow.modulate.a = 0.0
	_left_panel.modulate.a = 0.0
	# Zwei Frames: Container-Sortierung ist deferred, erst dann stimmen Positionen.
	await get_tree().process_frame
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
	tw.tween_property(_left_panel, "position:x", lx, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_left_panel, "modulate:a", 1.0, 0.3)

	# Score + Genauigkeit zaehlen hoch.
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
	# Genauigkeits-Ring laeuft synchron zum Zaehler voll.
	tw.tween_method(_set_ring_t, 0.0, 1.0, 1.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.3)

	# Rank: Zoom-Pop, Glow faehrt weich hoch, danach Glanz-Sweep.
	var box := Vector2(RING, RING)
	_rank_lbl.pivot_offset = box * 0.5
	_rank_lbl.scale = Vector2.ONE * 1.25
	_rank_mat.set_shader_parameter("box", box)
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
		_score_lbl.text = fmt_int(int(roundf(score * t)))
	if is_instance_valid(_acc_lbl):
		_acc_lbl.text = fmt_pct(acc * t)


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
	if is_instance_valid(_main_row):
		_main_row.queue_sort()
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
