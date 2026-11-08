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
## is_replay, lobby, mods (Dictionary, sonst GameSession.mods).
## Modus kommt aus s.mode ("orbit", sonst Mania 4K): Abzeichen im Kopf, der
## Bestleistungs-Vergleich nutzt nur Scores desselben Modus
## (ScoreStore.previous_best_for).
## Details (optional, Mania): judge_log = Array[Vector4(Notenzeit ms, Spur,
## Quality, Zeitfehler ms oder NAN)] in Urteils-Reihenfolge -> Reiter
## "Details" mit Treffern pro Spur und Timing pro Abschnitt, schmales
## Abschnitts-Band unter der Acc-Kurve. previous_best = bisheriger Bestwert
## ({} = erster Lauf) -> Differenzen unter Score/Acc/Kombo/pp.

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
const FAIL_COLOR := UiTheme.BAD
## Mikro-Labels: hell genug fuer Kontrast auf Glas (nicht unter 12 px nutzen).
const CAPTION := Color(0.68, 0.655, 0.615)
const MUTED := Color(0.50, 0.48, 0.45)
const SCORE_COUNT_TIME := 0.9
const STAGGER := 0.07
const HIST_BINS := 41
const PANEL_W := 700.0
const RANK_COL_W := 380.0
const RING := 330.0
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
var _mode_tag: Label
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
var _pages: Array[Control] = []  # [Uebersicht, Details]
var _tabs: Array[Button] = []
var _page := 0


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
		_toast_btn.text = tr("Ordner öffnen")
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


## Clip-Export-Fortschritt als stehender Toast mit Prozent und Restzeit
## (ClipExporter.progress_info). eta_s < 0 = noch keine Schaetzung.
func show_clip_progress(fraction: float, eta_s: float, phase: String = "render") -> void:
	var pct := int(clampf(fraction, 0.0, 1.0) * 100.0)
	var text := tr("Clip wird umgewandelt … %d %%") % pct if phase == "encode" 		else tr("Clip wird aufgenommen … %d %%") % pct
	if eta_s >= 0.0:
		text += "  " + tr("noch ca. %d s") % int(ceilf(eta_s))
	show_toast(text, true)


## Clip-Export-Ergebnis als Toast: "Clip gespeichert: <Pfad>" + Ordner-Button,
## bei Fehler der Grund (ClipExporter.last_error).
func show_clip_result(ok: bool, path: String, error: String = "") -> void:
	if ok:
		show_toast(tr("Clip gespeichert: %s") % path, false, path.get_base_dir())
	else:
		show_toast(tr("Clip-Export fehlgeschlagen: %s") % (error if error != "" else tr("unbekannt")), false)


## Multiplayer: Platzierungs-Text unter dem Rang, weich eingeblendet.
## Modus-Zeile unter der Platzierung (Teams: Teamsumme + Rundensieger,
## Royale: wer ausscheidet). Leerer Text blendet sie aus.
func set_mode_text(text: String, col: Color) -> void:
	if _mode_tag == null or not is_instance_valid(_mode_tag) or _mode_tag.text == text:
		return
	_mode_tag.text = text
	_mode_tag.visible = text != ""
	_mode_tag.add_theme_color_override("font_color", col)
	_mode_tag.modulate.a = 0.0
	create_tween().tween_property(_mode_tag, "modulate:a", 1.0, 0.5)


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
	_pages.clear()
	_tabs.clear()
	_page = 0
	_build_background()
	_build_header()
	var group := _build_group()
	if bool(data.get("lobby", false)):
		_build_lobby_area(_main_row)
	else:
		_build_left_panel(_main_row)
		_build_rank_area(_main_row)
	_build_buttons(group)
	_shown = true
	if bool(data.get("lobby", false)):
		_play_lobby_intro()
	else:
		_play_intro()


# ---------------------------------------------------------------------------
# Formatierung (deutsch)
# ---------------------------------------------------------------------------

## 923412 -> "923.412" (Tausenderpunkt, keine fuehrenden Nullen).
static func fmt_int(n: int) -> String:
	return UiTheme.fmt_score(n)


## 96.666 -> "96,67" (Dezimalkomma).
static func fmt_dec(v: float, decimals: int) -> String:
	return UiTheme.fmt_num(v, decimals)


## 0.9667 -> "96,67 %".
static func fmt_pct(frac: float, decimals: int = 2) -> String:
	return fmt_dec(frac * 100.0, decimals) + " %"


## ISO "2026-11-06T22:37:00" -> "06.11.2026 22:37".
static func fmt_date(iso: String) -> String:
	if iso.strip_edges() == "":
		return ""
	return UiTheme.fmt_date(iso)


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
		bg.modulate = Color(0.48, 0.47, 0.45)
		add_child(bg)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(UiTheme.BG, 0.6)
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


## Spielmodus des Ergebnisses: "orbit" oder "" (Mania 4K).
func score_mode() -> String:
	return ScoreStore.MODE_ORBIT if str(_stats.get("mode", "")) == ScoreStore.MODE_ORBIT else ""


## Mod-Abzeichen-Texte, SV mit Stufe ("SV Stark"): Stufe aus s.sv_level,
## sonst die aktive SvMod-Stufe dieses Laufs.
func mod_badge_texts() -> Array:
	var lv := str(_stats.get("sv_level", SvMod.level_name()))
	var out: Array = []
	for m in active_mods():
		out.append(ScoreStore.mods_label({ "mods": [m], "sv_level": lv }))
	return out


## Modus-Abzeichen (Mania 4K = ACCENT, Orbit = ACCENT2), kraeftiger als Mods.
func _mode_badge() -> Control:
	var orbit := score_mode() == ScoreStore.MODE_ORBIT
	var col: Color = UiTheme.ACCENT2 if orbit else UiTheme.ACCENT
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.32)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = ScoreStore.mode_label(score_mode()).to_upper()
	l.add_theme_font_override("font", UiTheme.heading_font(2))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.55))
	p.add_child(l)
	return p


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
	# Diff-Name; der Modus steht als Abzeichen dahinter (nicht mehr "· 4K").
	var ver := str(_data.get("version", "")).strip_edges()
	ver = ver.trim_suffix("·  " + tr("Orbit")).trim_suffix("· " + tr("Orbit")).strip_edges()
	sub.text = ver
	sub.position = Vector2(41, 48)
	sub.add_theme_font_override("font", UiTheme.heading_font(1))
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UiTheme.ACCENT.lerp(UiTheme.TEXT, 0.35))
	strip.add_child(sub)
	# Modus-Abzeichen + Mod-Badges (SV mit Stufe, NF) hinter der Schwierigkeit.
	var mod_row := HBoxContainer.new()
	mod_row.position = Vector2(41 + 8, 46)
	mod_row.add_theme_constant_override("separation", 6)
	strip.add_child(mod_row)
	mod_row.add_child(_mode_badge())
	for m in mod_badge_texts():
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
## Button-Leiste exakt so breit wie beide zusammen. Im Lobby-Modus volle
## Breite: Rangliste + zwei Stats-Karten (Vergleich).
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
	if bool(_data.get("lobby", false)):
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(group)
	_main_row = HBoxContainer.new()
	_main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_row.add_theme_constant_override("separation", GROUP_GAP)
	_main_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(_main_row)
	return group


## Linke Karte im Stil der MP-/Turnier-Statistik (PlayerStatsCard): Score mit
## Bestleistung (gleicher Modus), Genauigkeit/Kombo/pp, Judgement-Verteilung,
## UR/Abweichung/Holds/Frueh-Spaet, Trefferfehler + Genauigkeit im Verlauf.
## Fail: dieselben Werte bis zum Fail, ruhige Markierung im Verlauf.
## Optionale Daten: trace (Acc nach jedem Urteil), h_ok, h_drop, fail_ms,
## length_ms, notes_total.
func _build_left_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var psb := UiTheme.glass_box(18, 0.72)
	psb.set_content_margin_all(22)
	psb.content_margin_top = 18
	psb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", psb)
	parent.add_child(panel)
	_left_panel = panel
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var st := stats_packet()

	# Score (zaehlt hoch) + Abzeichen, daneben Acc/Kombo/pp, darunter PB.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	var cap := _caption("PUNKTE")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(cap)
	for b in _badges():
		top.add_child(_badge(str(b[0]), b[1]))
	var top_fill := Control.new()
	top_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_fill)
	var jlog := judge_log()
	var with_details := not jlog.is_empty()
	if with_details:
		top.add_child(_tab_button(tr("Übersicht"), 0))
		top.add_child(_tab_button(tr("Details"), 1))
	_reveal.append(top)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 22)
	vb.add_child(srow)
	_score_lbl = Label.new()
	_score_lbl.text = "0"
	_score_lbl.add_theme_font_override("font", UiTheme.heading_font(3))
	_score_lbl.add_theme_font_size_override("font_size", 54)
	_score_lbl.add_theme_color_override("font_color", UiTheme.TEXT)
	_score_lbl.add_theme_constant_override("line_spacing", -6)
	var deltas := hero_deltas()
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_box.add_child(_score_lbl)
	srow.add_child(score_box)
	var acc: float = float(_stats.get("accuracy", 0.0))
	var acc_v := _hero_stat("GENAUIGKEIT", fmt_pct(acc), UiTheme.TEXT)
	_acc_lbl = acc_v.get_meta("value")
	srow.add_child(acc_v)
	var combo_v := _hero_stat("MAX. KOMBO", "%s×" % fmt_int(int(_stats.get("max_combo", 0))), UiTheme.TEXT)
	srow.add_child(combo_v)
	var pp_v := _hero_pp()
	srow.add_child(pp_v)
	if not deltas.is_empty():
		var boxes := {"score": score_box, "acc": acc_v, "combo": combo_v, "pp": pp_v}
		for k in boxes:
			var d: Array = deltas.get(k, ["", CAPTION])
			(boxes[k] as Control).add_child(_delta_label(str(d[0]), d[1]))
	_reveal.append(srow)

	# Verteilung, Timing und Graphen aus der Stats-Karte (gleicher Stil wie MP).
	# Mit judge_log: Seite "Uebersicht" + Seite "Details" (Spur, Abschnitt, Bestwert).
	var over := VBoxContainer.new()
	over.add_theme_constant_override("separation", 12)
	over.size_flags_vertical = Control.SIZE_EXPAND_FILL
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(over)
	_pages.append(over)
	var card := PlayerStatsCard.new()
	card._s = 0.86
	var jd: Control = card._judgements(st)
	over.add_child(jd)
	_reveal.append(jd)
	if st.has("ur"):
		var tm: Control = card._timing(st, {})
		over.add_child(tm)
		_reveal.append(tm)
		var is_fail := bool(_data.get("is_fail", false))
		var info := {}
		if is_fail:
			info["trace_caption"] = tr("Genauigkeit bis zum Fail")
		var gr: Control = card._graphs(st, {}, info)
		gr.custom_minimum_size = Vector2(0, 118)
		over.add_child(gr)
		_reveal.append(gr)
		if is_fail:
			_add_fail_marker(gr)
		if with_details:
			_add_section_band(gr, jlog)
	card.free()
	if with_details:
		var det := _build_details(jlog)
		det.visible = false
		vb.add_child(det)
		_pages.append(det)


## Paket wie im MP (PlayerStatsCard.pack) aus Stats, Offsets und optionalem
## Verlauf/Holds dieses Laufs.
func stats_packet() -> Dictionary:
	var tr_raw: Variant = _data.get("trace", PackedFloat32Array())
	var trace := PackedFloat32Array()
	if tr_raw is Array or tr_raw is PackedFloat32Array:
		trace = PackedFloat32Array(tr_raw)
	return PlayerStatsCard.pack(_stats, _offsets, trace, int(_data.get("h_ok", 0)),
		int(_data.get("h_drop", 0)), bool(_data.get("is_fail", false)))


## Anteil der Map bis zum Fail (0..1), -1 = unbekannt.
func fail_fraction() -> float:
	var len_ms := float(_data.get("length_ms", 0.0))
	if len_ms > 0.0 and _data.has("fail_ms"):
		return clampf(float(_data.fail_ms) / len_ms, 0.0, 1.0)
	var notes := int(_data.get("notes_total", 0))
	if notes > 0:
		return clampf(float(PlayerStatsCard.total_of(stats_packet())) / float(notes), 0.0, 1.0)
	return -1.0


## "Fail bei 1:23 · 41 %" (Zeit nur, wenn bekannt).
func fail_text() -> String:
	var parts: Array = []
	if _data.has("fail_ms"):
		var sec := int(float(_data.fail_ms) / 1000.0)
		parts.append("%d:%02d" % [sec / 60, sec % 60])
	var f := fail_fraction()
	if f >= 0.0:
		parts.append(UiTheme.fmt_num(f * 100.0, 0) + (" %" if UiTheme.is_german() else "%"))
	if parts.is_empty():
		return tr("Fail")
	return tr("Fail bei %s") % "  ·  ".join(parts)


## Verlauf auf den gespielten Anteil stauchen, rechts davon der Rest der Map
## (blass gestrichelt) mit einer ruhigen Fail-Linie und Beschriftung.
func _add_fail_marker(graphs: Control) -> void:
	var f := fail_fraction()
	var trace_box: Control = null
	if graphs.get_child_count() > 1:
		trace_box = graphs.get_child(1)
	var target: Control = null
	if trace_box != null and trace_box.get_child_count() > 1:
		target = trace_box.get_child(trace_box.get_child_count() - 1)
	var label_txt := fail_text()
	if target == null:
		var l := _caption(label_txt.to_upper())
		l.add_theme_color_override("font_color", FAIL_COLOR.lerp(CAPTION, 0.35))
		graphs.get_parent().add_child(l)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trace_box.remove_child(target)
	trace_box.add_child(row)
	var played := fail_played()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.size_flags_stretch_ratio = played
	row.add_child(target)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rest.size_flags_stretch_ratio = 1.0 - played
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rest.draw.connect(func():
		var h := rest.size.y
		var w := rest.size.x
		var x := 6.0
		while x < w:
			rest.draw_line(Vector2(x, h - 1.0), Vector2(minf(x + 5.0, w), h - 1.0), Color(1, 1, 1, 0.14), 1.0)
			x += 10.0
		var col := FAIL_COLOR.lerp(CAPTION, 0.25)
		rest.draw_line(Vector2(1, 0), Vector2(1, h), Color(col, 0.85), 2.0)
		var font := get_theme_default_font()
		var fw := font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tx := 8.0 if fw + 8.0 <= w else -fw - 8.0
		rest.draw_string(font, Vector2(tx, 13), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col))
	row.add_child(rest)


## Breitenanteil des gespielten Verlaufs bei Fail. Mindestens ein Drittel,
## sonst ist der Verlauf bei fruehem Fail unlesbar.
func fail_played() -> float:
	var f := fail_fraction()
	return clampf(f, 0.35, 0.96) if f >= 0.0 else 0.96


## Kennzahl neben dem Score: kleine Beschriftung, Wert darunter.
func _hero_stat(cap: String, value: String, col: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_vertical = Control.SIZE_SHRINK_END
	v.add_child(_caption(cap))
	var l := Label.new()
	l.text = value
	l.add_theme_font_override("font", UiTheme.heading_font(1))
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", col)
	v.add_child(l)
	v.set_meta("value", l)
	return v


func _hero_pp() -> VBoxContainer:
	var pp := float(_data.get("pp", -1.0))
	if pp < 0.0 or bool(_data.get("unranked", false)) or score_mode() == ScoreStore.MODE_ORBIT:
		return _hero_stat("PERFORMANCE", "—", MUTED)
	return _hero_stat("PERFORMANCE", "%s pp" % fmt_dec(pp, 1), UiTheme.ACCENT2)


## Fail-Bild: Grund des Todes in einer Zeile (aus ManiaCore.analyze_fail).
func _add_fail_reason(parent: Control, font_size: int) -> void:
	var txt := str(_data.get("fail_reason", ""))
	if not bool(_data.get("is_fail", false)) or txt == "":
		return
	var lbl := Label.new()
	lbl.text = txt
	lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", UiTheme.TEXT.lerp(CAPTION, 0.4))
	parent.add_child(lbl)
	_reveal.append(lbl)


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
	_rank_glow.texture = null  # kein Farb-Glow hinter dem Rang (ruhiger)
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
	disc.texture = _disc_tex(Color(UiTheme.BG, 0.55))
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
	_rank_lbl.add_theme_font_size_override("font_size", 220 if grade.length() < 2 else 168)
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
	_add_fail_reason(col, 20)
	if Lobby.active:
		_place_tag = Label.new()
		_place_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_place_tag.add_theme_font_override("font", UiTheme.heading_font(7))
		_place_tag.add_theme_font_size_override("font_size", 30)
		_place_tag.text = "WARTE AUF ANDERE…"
		_place_tag.add_theme_color_override("font_color", UiTheme.TEXT.lerp(CAPTION, 0.4))
		col.add_child(_place_tag)
		_reveal.append(_place_tag)
		if Lobby.mm.kind != MatchMode.Kind.FREE:
			_mode_tag = Label.new()
			_mode_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_mode_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_mode_tag.custom_minimum_size = Vector2(420, 0)
			_mode_tag.add_theme_font_override("font", UiTheme.heading_font(5))
			_mode_tag.add_theme_font_size_override("font_size", 19)
			_mode_tag.visible = false
			col.add_child(_mode_tag)
			_reveal.append(_mode_tag)


func _build_buttons(group: Control) -> void:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 50)
	bar.add_theme_constant_override("separation", 12)
	group.add_child(bar)
	var is_replay := bool(_data.get("is_replay", false))
	var lobby := bool(_data.get("lobby", false))
	bar.add_child(_button((("Zur Siegerehrung" if Lobby.tournament.phase == Tournament.Phase.END else "Zum Zwischenstand")
		if Lobby.tournament != null else "Zur Lobby")
		if lobby else "Zum Song-Browser", false,
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
	var why := tr("Map ist nicht gewertet – keine PP") if unranked \
		else tr("PP für diese Map nicht berechenbar")
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
	c.draw_string(font, Vector2(0, h + 17), tr("−%d ms  früh") % int(_hist_range),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lc)
	c.draw_string(font, Vector2(w * 0.5 - 20, h + 17), "0 ms", HORIZONTAL_ALIGNMENT_CENTER, 40, 12, lc)
	c.draw_string(font, Vector2(0, h + 17), tr("spät  +%d ms") % int(_hist_range),
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
		elif event.keycode == KEY_TAB and _pages.size() > 1:
			get_viewport().set_input_as_handled()
			show_page((_page + 1) % _pages.size())


# ---------------------------------------------------------------------------
# Multiplayer: Rangliste + zwei Stats-Karten (Direktvergleich)
# ---------------------------------------------------------------------------

var _board: Array = []        # [{id, name, final, score}] in Ranglisten-Reihenfolge
var _board_me := -1
var _board_mods := ""
var _rank_list: VBoxContainer
var _rank_head: Label
var _lobby_col: VBoxContainer
var _cards_row: HBoxContainer
var _card_a: PlayerStatsCard
var _card_b: PlayerStatsCard
var _sel_a := -1
var _sel_b := -1
var _b_manual := false
var _sig_a := ""
var _sig_b := ""
var _sig_duel := ""
var _duel_slot: VBoxContainer
var _narrow := false


func _lobby_rank_w() -> float:
	var w := get_viewport_rect().size.x
	return clampf(w * 0.235, 290.0, 430.0)


func _build_lobby_area(parent: Control) -> void:
	_main_row.add_theme_constant_override("separation", 20)
	var vw := get_viewport_rect().size
	_narrow = vw.x < 1600.0 or vw.y < 900.0
	_lobby_col = VBoxContainer.new()
	_lobby_col.custom_minimum_size = Vector2(_lobby_rank_w(), 0)
	_lobby_col.add_theme_constant_override("separation", 10)
	_lobby_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_lobby_col)
	# Platzierung gross oben, Modus-Zeile (Teams/Royale) darunter.
	_place_tag = Label.new()
	_place_tag.add_theme_font_override("font", UiTheme.heading_font(6))
	_place_tag.add_theme_font_size_override("font_size", 26 if _narrow else 34)
	_place_tag.text = "WARTE AUF ANDERE…"
	_place_tag.add_theme_color_override("font_color", UiTheme.TEXT.lerp(CAPTION, 0.4))
	_place_tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lobby_col.add_child(_place_tag)
	_reveal.append(_place_tag)
	var is_fail := bool(_data.get("is_fail", false))
	var fc := int(_stats.get("n_miss", 0)) == 0 and not is_fail
	if is_fail or fc:
		var tag := Label.new()
		tag.text = "NICHT GESCHAFFT" if is_fail else "FULL COMBO"
		tag.add_theme_font_override("font", UiTheme.heading_font(5))
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", FAIL_COLOR if is_fail else UiTheme.ACCENT)
		_lobby_col.add_child(tag)
		_reveal.append(tag)
		_add_fail_reason(_lobby_col, 14)
	if Lobby.mm.kind != MatchMode.Kind.FREE:
		_mode_tag = Label.new()
		_mode_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mode_tag.add_theme_font_override("font", UiTheme.heading_font(3))
		_mode_tag.add_theme_font_size_override("font_size", 16)
		_mode_tag.visible = false
		_lobby_col.add_child(_mode_tag)
		_reveal.append(_mode_tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_lobby_col.add_child(gap)
	_rank_head = _caption("RANGLISTE")
	_rank_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_lobby_col.add_child(_rank_head)
	_reveal.append(_rank_head)
	_rank_list = VBoxContainer.new()
	_rank_list.add_theme_constant_override("separation", 6)
	_rank_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_col.add_child(_rank_list)
	_reveal.append(_rank_list)
	# Direktvergleich der beiden gezeigten Spieler (nur wenn Platz ist).
	_duel_slot = VBoxContainer.new()
	_duel_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_col.add_child(_duel_slot)
	_reveal.append(_duel_slot)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_col.add_child(fill)
	var hint := Label.new()
	hint.text = tr("Klick: Spieler rechts anzeigen  ·  Rechtsklick: links")
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	_lobby_col.add_child(hint)
	_reveal.append(hint)
	_cards_row = HBoxContainer.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override("separation", 20)
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_cards_row)
	_card_a = PlayerStatsCard.new()
	_card_b = PlayerStatsCard.new()
	for c in [_card_a, _card_b]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards_row.add_child(c)
	_reveal.append(_card_a)
	_reveal.append(_card_b)
	# Eigenes Paket sofort zeigen (Board kommt gleich vom Spiel nach).
	var mine: Dictionary = _data.get("final", {})
	var me_id := int(_data.get("my_id", -1))
	if not mine.is_empty() and _board.is_empty():
		_board = [{ "id": me_id, "name": str(_data.get("player", "?")), "final": mine, "score": int(mine.get("score", 0)) }]
		_board_me = me_id
	_refresh_lobby()


## Rangliste + Karten aktualisieren (Live-Nachzug). entries in Ranglisten-
## Reihenfolge: {id, name, final (leer = spielt noch), score (Live)}.
func set_board(entries: Array, my_id: int, mods_text: String = "") -> void:
	_board = entries.duplicate()
	# Fertige nach Endscore vor allen, die noch spielen (die nach Live-Score).
	_board.sort_custom(func(a, b):
		var fa: Dictionary = a.get("final", {})
		var fb: Dictionary = b.get("final", {})
		if fa.is_empty() != fb.is_empty():
			return not fa.is_empty()
		var sa := int(fa.get("score", 0)) if not fa.is_empty() else int(a.get("score", 0))
		var sb := int(fb.get("score", 0)) if not fb.is_empty() else int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		return float(fa.get("acc", 0.0)) > float(fb.get("acc", 0.0)))
	_board_me = my_id
	_board_mods = mods_text
	if _rank_list != null and is_instance_valid(_rank_list):
		_refresh_lobby()


func _entry(id: int) -> Dictionary:
	for e in _board:
		if int(e.id) == id:
			return e
	return {}


func _place_of(id: int) -> int:
	var p := 0
	for e in _board:
		if (e.get("final", {}) as Dictionary).is_empty():
			continue
		p += 1
		if int(e.id) == id:
			return p
	return 0


func _refresh_lobby() -> void:
	if _rank_head != null and is_instance_valid(_rank_head):
		_rank_head.text = tr("RANGLISTE") + ("  ·  " + _board_mods if _board_mods != "" else "")
	# A = ich (bis jemand anders gewaehlt wird), B = bester anderer Spieler.
	if _entry(_sel_a).is_empty():
		_sel_a = _board_me if not _entry(_board_me).is_empty() else (int(_board[0].id) if not _board.is_empty() else -1)
	if not _b_manual or _entry(_sel_b).is_empty() or _sel_b == _sel_a:
		_b_manual = false
		_sel_b = -1
		for e in _board:
			if int(e.id) != _sel_a:
				_sel_b = int(e.id)
				break
	_build_rank_rows()
	_update_cards()


func _build_rank_rows() -> void:
	for c in _rank_list.get_children():
		_rank_list.remove_child(c)
		c.queue_free()
	var row_h := 46.0 if _narrow else 56.0
	if _board.size() > 6:
		row_h = 40.0 if _narrow else 48.0
	for i in _board.size():
		_rank_list.add_child(_rank_row(_board[i], row_h))


func _rank_row(e: Dictionary, row_h: float) -> Control:
	var id := int(e.id)
	var fin: Dictionary = e.get("final", {})
	var place := _place_of(id)
	var side := "A" if id == _sel_a else ("B" if id == _sel_b else "")
	var sc: Color = PlayerStatsCard.SIDE_A if side == "A" else PlayerStatsCard.SIDE_B
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, row_h)
	var sb := UiTheme.glass_box(12, 0.58 if side != "" else 0.40, 0.08)
	sb.shadow_size = 0
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	if side != "":
		sb.border_color = Color(sc, 0.55)
		sb.bg_color = Color(sc.darkened(0.75), 0.62)
	p.add_theme_stylebox_override("panel", sb)
	var hov: StyleBoxFlat = sb.duplicate()
	hov.bg_color = sb.bg_color.lightened(0.08)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hov))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", sb))
	p.gui_input.connect(_on_row_input.bind(id))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var pl := Label.new()
	pl.text = str(place) if place > 0 else "–"
	pl.custom_minimum_size.x = 22
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.add_theme_font_override("font", UiTheme.heading_font(0))
	pl.add_theme_font_size_override("font_size", 18 if _narrow else 22)
	pl.add_theme_color_override("font_color", TournamentPanel.rank_color(place) if place > 0 and place <= 3 else CAPTION)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pl)
	h.add_child(TournamentPanel.avatar(str(e.name), 28 if _narrow else 34))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nv)
	var nm := Label.new()
	nm.text = str(e.name)
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.add_theme_font_override("font", UiTheme.heading_font(1))
	nm.add_theme_font_size_override("font_size", 15 if _narrow else 17)
	nm.add_theme_color_override("font_color", UiTheme.ACCENT.lerp(UiTheme.TEXT, 0.3) if id == _board_me else UiTheme.TEXT)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(nm)
	var sub := Label.new()
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.add_theme_font_size_override("font_size", 12 if _narrow else 13)
	sub.add_theme_color_override("font_color", CAPTION)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if fin.is_empty():
		sub.text = tr("spielt noch…")
	else:
		var g := "F" if bool(fin.get("failed", false)) else str(fin.get("grade", "D"))
		sub.text = "%s  ·  %s  ·  %d %s" % [g, UiTheme.fmt_pct(float(fin.get("acc", 0.0)) * 100.0),
			int(fin.get("n_miss", 0)), tr("Miss")]
	nv.add_child(sub)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", -2)
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(rv)
	var sl := Label.new()
	sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sl.text = UiTheme.fmt_score(int(fin.get("score", 0)) if not fin.is_empty() else int(e.get("score", 0)))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.add_theme_font_override("font", UiTheme.heading_font(0))
	sl.add_theme_font_size_override("font_size", 16 if _narrow else 19)
	sl.add_theme_color_override("font_color", UiTheme.TEXT if not fin.is_empty() else MUTED)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(sl)
	if side != "":
		var sd := Label.new()
		sd.text = tr("links") if side == "A" else tr("rechts")
		sd.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sd.add_theme_font_override("font", UiTheme.heading_font(2))
		sd.add_theme_font_size_override("font_size", 11)
		sd.add_theme_color_override("font_color", sc)
		sd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rv.add_child(sd)
	return p


func _on_row_input(ev: InputEvent, id: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.shift_pressed:
		if id == _sel_a:
			if _sel_b < 0:
				return
			_sel_a = _sel_b
		_sel_b = id
		_b_manual = true
	elif mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.shift_pressed):
		if id == _sel_b:
			_sel_b = _sel_a
		_sel_a = id
		_b_manual = _sel_b >= 0
	else:
		return
	accept_event()
	_refresh_lobby()


func _card_sig(id: int, other: int) -> String:
	var e := _entry(id)
	var o := _entry(other)
	return "%d|%d|%s|%d|%s|%d|%s" % [id, other, str(e.get("final", {}).hash()), int(e.get("score", 0)),
		str(o.get("final", {}).hash()), _place_of(id), str(_narrow)]


func _update_cards() -> void:
	if _card_a == null or not is_instance_valid(_card_a):
		return
	var sa := _card_sig(_sel_a, _sel_b)
	if sa != _sig_a:
		_sig_a = sa
		_fill_card(_card_a, _sel_a, _sel_b, "A")
	_card_b.visible = _sel_b >= 0
	var sbg := _card_sig(_sel_b, _sel_a)
	if _sel_b >= 0 and sbg != _sig_b:
		_sig_b = sbg
		_fill_card(_card_b, _sel_b, _sel_a, "B")
	_update_duel()


func _update_duel() -> void:
	if _duel_slot == null or not is_instance_valid(_duel_slot):
		return
	var fa: Dictionary = _entry(_sel_a).get("final", {})
	var fb: Dictionary = _entry(_sel_b).get("final", {})
	var room := _board.size() <= (3 if _narrow else 6)
	var show := room and not fa.is_empty() and not fb.is_empty()
	var sig := "%s|%s|%s|%s" % [str(show), _card_sig(_sel_a, _sel_b), _card_sig(_sel_b, _sel_a), str(_board.size())]
	if sig == _sig_duel:
		return
	_sig_duel = sig
	for c in _duel_slot.get_children():
		_duel_slot.remove_child(c)
		c.queue_free()
	_duel_slot.visible = show
	if not show:
		return
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8 if _narrow else 14)
	_duel_slot.add_child(gap)
	_duel_slot.add_child(PlayerStatsCard.duel(str(_entry(_sel_a).get("name", "?")), fa,
		str(_entry(_sel_b).get("name", "?")), fb, _narrow))


func _fill_card(card: PlayerStatsCard, id: int, other: int, side: String) -> void:
	var e := _entry(id)
	var fin: Dictionary = e.get("final", {})
	var o := _entry(other)
	var info := {
		"name": str(e.get("name", "?")), "place": _place_of(id), "side": side,
		"narrow": _narrow, "pending": fin.is_empty(), "live": int(e.get("score", 0)),
		"ref": o.get("final", {}), "sub": tr("Du") if id == _board_me else "",
	}
	card.setup(info, fin)


func _play_lobby_intro() -> void:
	for c in _reveal:
		c.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var tw := create_tween().set_parallel(true)
	for i in _reveal.size():
		var c: Control = _reveal[i]
		tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(0.05 + 0.06 * i)
	for c in [_card_a, _card_b]:
		var y: float = c.position.y
		c.position.y = y + 24.0
		tw.tween_property(c, "position:y", y, 0.5).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT).set_delay(0.2 + (0.1 if c == _card_b else 0.0))
	tw.chain().tween_callback(func():
		if is_instance_valid(_main_row):
			_main_row.queue_sort())


# ---------------------------------------------------------------------------
# Details: Bestwert-Vergleich, Treffer pro Spur, Timing pro Abschnitt
# ---------------------------------------------------------------------------

## Gedeckte Differenz-Farben (besser / schlechter) und Marke der schwaechsten Stelle.
const DELTA_UP := Color(0.60, 0.76, 0.60)
const DELTA_DOWN := Color(0.84, 0.56, 0.51)
const WEAK_COL := Color(0.86, 0.50, 0.44)
## Abschnitte mit weniger Urteilen zaehlen nicht als "schwaechste Stelle".
const SECTION_MIN_NOTES := 4


## Urteile dieses Laufs (Vector4: Notenzeit ms, Spur, Quality, Zeitfehler ms/NAN).
func judge_log() -> Array:
	var raw: Variant = _data.get("judge_log", [])
	var out: Array = []
	if raw is Array:
		for e in raw:
			if e is Vector4:
				out.append(e)
	return out


## Bisheriger Bestwert dieser Diff: Dictionary ({} = erster Lauf) oder null,
## wenn nichts verglichen wird (Fail, Replay, Lobby, nicht gespeichert).
func comparison() -> Variant:
	if bool(_data.get("is_fail", false)) or bool(_data.get("is_replay", false)) \
			or bool(_data.get("lobby", false)):
		return null
	var prev: Variant = _data.get("previous_best", null)
	if prev == null:
		prev = ScoreStore.previous_best_for(GameSession.osz_path, GameSession.difficulty_version,
			score_mode(), int(_stats.get("score", 0)))
	return prev if prev is Dictionary else null


## Differenzen zum Bestwert: {score|acc|combo|pp: [Text, Farbe]}. Erster Lauf:
## nur score = "erster Lauf auf dieser Diff". {} = kein Vergleich.
func hero_deltas() -> Dictionary:
	var prev: Variant = comparison()
	if prev == null:
		return {}
	var p: Dictionary = prev
	if p.is_empty():
		return {"score": [tr("erster Lauf auf dieser Diff"), CAPTION]}
	var out := {}
	out["score"] = delta_entry(float(int(_stats.get("score", 0)) - int(p.get("score", 0))), "score")
	out["acc"] = delta_entry((float(_stats.get("accuracy", 0.0)) - float(p.get("accuracy", 0.0))) * 100.0, "acc")
	out["combo"] = delta_entry(float(int(_stats.get("max_combo", 0)) - int(p.get("max_combo", 0))), "combo")
	var pp := float(_data.get("pp", -1.0))
	var old_pp := float(p.get("pp", -1.0))
	if pp >= 0.0 and old_pp >= 0.0 and not bool(_data.get("unranked", false)) \
			and score_mode() != ScoreStore.MODE_ORBIT:
		out["pp"] = delta_entry(pp - old_pp, "pp")
	return out


## Differenz als [Text, Farbe]: "+1,26 %", "−3.400", "±0" (unter der
## Anzeigegenauigkeit gilt als gleich).
static func delta_entry(diff: float, kind: String) -> Array:
	var txt := delta_text(diff, kind)
	if txt.begins_with("±"):
		return [txt, MUTED]
	return [txt, DELTA_UP if diff > 0.0 else DELTA_DOWN]


static func delta_text(diff: float, kind: String) -> String:
	var a := absf(diff)
	var eps := 0.5
	var body := ""
	match kind:
		"acc":
			eps = 0.005
			body = UiTheme.fmt_num(a, 2) + (" %" if UiTheme.is_german() else "%")
		"pp":
			eps = 0.05
			body = UiTheme.fmt_num(a, 1) + " pp"
		"combo":
			body = UiTheme.fmt_score(roundi(a)) + "×"
		_:
			body = UiTheme.fmt_score(roundi(a))
	if a < eps:
		return "±0"
	return ("+" if diff > 0.0 else "−") + body


func _delta_label(t: String, col: Color) -> Label:
	var l := Label.new()
	l.text = t if t != "" else " "
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", col)
	return l


## Genauigkeit (osu!mania-Formel) aus Zaehlern [MAX, 300, 200, 100, 50, MISS].
static func acc_of(c: Array) -> float:
	var total := 0
	for x in c:
		total += int(x)
	if total == 0:
		return 1.0
	return float(300 * (int(c[0]) + int(c[1])) + 200 * int(c[2]) + 100 * int(c[3]) + 50 * int(c[4])) \
		/ float(300 * total)


## Je Spur: {counts [MAX..MISS], n, acc, mean (ms, NAN ohne Zeitfehler)}.
static func lane_stats(jlog: Array, lanes: int = 4) -> Array:
	for e in jlog:
		lanes = maxi(lanes, int((e as Vector4).y) + 1)
	var out: Array = []
	for _l in lanes:
		out.append({"counts": [0, 0, 0, 0, 0, 0], "n": 0, "sum": 0.0, "hits": 0})
	for e in jlog:
		var v: Vector4 = e
		var l := int(v.y)
		if l < 0:
			continue
		_count_into(out[l], v)
	for d in out:
		_finish_counts(d)
	return out


## Anzahl Abschnitte: etwa alle 15 s einer, 8 bis 12.
static func section_count(span_ms: float) -> int:
	return clampi(roundi(span_ms / 15000.0), 8, 12)


## Song (erste bis letzte Note) in gleich lange Abschnitte: je {t0, t1, n,
## counts, acc, mean, i0, i1}. i0..i1 = fortlaufende Urteils-Indizes in
## Zeitreihenfolge (Breite im Band unter dem Verlauf, der je Urteil zaehlt).
static func section_stats(jlog: Array, count: int = -1) -> Array:
	if jlog.is_empty():
		return []
	var t0 := INF
	var t1 := -INF
	for e in jlog:
		t0 = minf(t0, (e as Vector4).x)
		t1 = maxf(t1, (e as Vector4).x)
	var span := maxf(t1 - t0, 1.0)
	var n := count if count > 0 else section_count(span)
	var out: Array = []
	for k in n:
		out.append({"t0": t0 + span * float(k) / float(n), "t1": t0 + span * float(k + 1) / float(n),
			"counts": [0, 0, 0, 0, 0, 0], "n": 0, "sum": 0.0, "hits": 0})
	for e in jlog:
		var v: Vector4 = e
		_count_into(out[clampi(int((v.x - t0) / span * float(n)), 0, n - 1)], v)
	var idx := 0
	for d in out:
		_finish_counts(d)
		d["i0"] = idx
		idx += int(d.n)
		d["i1"] = idx
	return out


static func _count_into(d: Dictionary, v: Vector4) -> void:
	var q := clampi(int(v.z), 0, 5)
	d.counts[q] += 1
	d.n += 1
	if not is_nan(v.w):
		d.sum += v.w
		d.hits += 1


static func _finish_counts(d: Dictionary) -> void:
	d["acc"] = acc_of(d.counts)
	d["mean"] = float(d.sum) / float(d.hits) if int(d.hits) > 0 else NAN


## Index des Abschnitts mit der niedrigsten Genauigkeit (mind.
## SECTION_MIN_NOTES Urteile), -1 wenn alle gleich gut sind.
static func weakest_section(secs: Array) -> int:
	var lo := -1
	var best := -1.0
	for k in secs.size():
		var d: Dictionary = secs[k]
		if int(d.n) < SECTION_MIN_NOTES:
			continue
		best = maxf(best, float(d.acc))
		if lo < 0 or float(d.acc) < float(secs[lo].acc):
			lo = k
	if lo < 0 or float(secs[lo].acc) >= best - 0.0001:
		return -1
	return lo


## 95300 -> "1:35".
static func fmt_clock(ms: float) -> String:
	var sec := maxi(int(ms / 1000.0), 0)
	return "%d:%02d" % [sec / 60, sec % 60]


static func signed_ms(v: float) -> String:
	return ("+" if v >= 0.0 else "−") + UiTheme.fmt_num(absf(v), 1)


func _plain(t: String, sz: int, col: Color, heading: bool = false) -> Label:
	var l := Label.new()
	l.text = t
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", UiTheme.heading_font(1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _caption_tr(key: String) -> Label:
	var l := _caption(tr(key).to_upper())
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return l


func _hline() -> Control:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.07)
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Reiter-Knopf oben rechts im Panel (aktiv: Text hell + Akzent-Unterstrich).
func _tab_button(t: String, idx: int) -> Button:
	var b := Button.new()
	b.text = t
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", UiTheme.heading_font(1))
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(show_page.bind(idx))
	_tabs.append(b)
	_style_tab(b, idx == _page)
	return b


func _style_tab(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = UiTheme.ACCENT if active else Color(1, 1, 1, 0)
	sb.border_width_bottom = 2
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 3
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var col := UiTheme.TEXT if active else CAPTION
	for c in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, col)
	for c in ["font_hover_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, UiTheme.TEXT)


## Seite 0 = Uebersicht, 1 = Details (Tab-Taste wechselt).
func show_page(i: int) -> void:
	if i < 0 or i >= _pages.size():
		return
	_page = i
	for k in _pages.size():
		_pages[k].visible = k == i
	for k in _tabs.size():
		_style_tab(_tabs[k], k == i)


## Schmales Abschnitts-Band unter der Acc-Kurve (gleiche x-Achse: Urteile),
## schwaechste Stelle in gedecktem Rot mit Zeitangabe.
func _add_section_band(graphs: Control, jlog: Array) -> void:
	if graphs.get_child_count() < 2:
		return
	var box: Control = graphs.get_child(1)
	var secs := section_stats(jlog)
	var band := _SectionBand.new()
	band.secs = secs
	band.total = jlog.size()
	band.weak = weakest_section(secs)
	if band.weak >= 0:
		band.weak_text = tr("schwächste Stelle %s") % fmt_clock(float(secs[band.weak].t0))
	band.custom_minimum_size = Vector2(0, 28)
	if not bool(_data.get("is_fail", false)):
		box.add_child(band)
		return
	# Fail: Band nur so breit wie der gespielte Teil des Verlaufs.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var played := fail_played()
	band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band.size_flags_stretch_ratio = played
	row.add_child(band)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.size_flags_stretch_ratio = 1.0 - played
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rest)
	box.add_child(row)


## Seite "Details": Bestwert, Treffer pro Spur, Timing pro Abschnitt.
func _build_details(jlog: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prev: Variant = comparison()
	if prev != null:
		v.add_child(_best_row(prev))
		v.add_child(_hline())

	v.add_child(_caption_tr("Treffer pro Spur"))
	var lanes := HBoxContainer.new()
	lanes.add_theme_constant_override("separation", 24)
	lanes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := lane_stats(jlog)
	for i in ls.size():
		lanes.add_child(_lane_col(i, ls[i]))
	v.add_child(lanes)
	v.add_child(_hline())

	var secs := section_stats(jlog)
	var weak := weakest_section(secs)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _caption_tr("Timing pro Abschnitt")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	if weak >= 0:
		var d: Dictionary = secs[weak]
		head.add_child(_plain(tr("schwächste Stelle %s") % ("%s–%s  ·  %s" % [
			fmt_clock(float(d.t0)), fmt_clock(float(d.t1)), fmt_pct(float(d.acc))]), 13, WEAK_COL))
	v.add_child(head)
	var chart := _SectionChart.new()
	chart.secs = secs
	chart.weak = weak
	chart.row_labels = [tr("Acc"), tr("Ø ms"), tr("Start")]
	chart.custom_minimum_size = Vector2(0, 110)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(chart)
	return v


## "BISHERIGER BESTWERT  911.204 · 95,41 % · 398× · 212,4 pp      03.11.2026".
func _best_row(prev: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := _caption_tr("Bisheriger Bestwert")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	if prev.is_empty():
		row.add_child(_plain(tr("erster Lauf auf dieser Diff"), 15, CAPTION))
		return row
	var parts: Array = [fmt_int(int(prev.get("score", 0))), fmt_pct(float(prev.get("accuracy", 0.0))),
		"%s×" % fmt_int(int(prev.get("max_combo", 0)))]
	if float(prev.get("pp", -1.0)) >= 0.0 and score_mode() != ScoreStore.MODE_ORBIT:
		parts.append("%s pp" % fmt_dec(float(prev.pp), 1))
	var mods_txt := ScoreStore.mods_label(prev)
	if mods_txt != "":
		parts.append(mods_txt)
	var val := _plain("  ·  ".join(parts), 15, UiTheme.TEXT, true)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	var date := str(prev.get("date", ""))
	if date != "":
		row.add_child(_plain(fmt_date(date), 13, CAPTION))
	return row


## Eine Spur: Name + Genauigkeit, Anteil-Balken, Zaehler MAX..MISS (2 Spalten),
## mittlere Abweichung.
func _lane_col(i: int, d: Dictionary) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 6)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := int(d.n)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := _plain(tr("Spur %d") % (i + 1), 15, UiTheme.TEXT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	head.add_child(_plain(fmt_pct(float(d.acc)) if n > 0 else "—", 15, UiTheme.TEXT, true))
	c.add_child(head)
	var bar := PlayerStatsCard._Stack.new()
	var fr: Array = []
	for q in 6:
		fr.append(float(d.counts[q]) / float(maxi(n, 1)))
	bar.fracs = fr
	bar.custom_minimum_size = Vector2(0, 6)
	c.add_child(bar)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 0)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for q in [0, 3, 1, 4, 2, 5]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := _plain(str(PlayerStatsCard.TAGS[q]), 12, QUALITY_COLOR[q], true)
		tag.custom_minimum_size = Vector2(32, 0)
		cell.add_child(tag)
		var cnt := int(d.counts[q])
		cell.add_child(_plain(fmt_int(cnt), 15, UiTheme.TEXT if cnt > 0 else MUTED, true))
		g.add_child(cell)
	c.add_child(g)
	var mean := float(d.mean)
	var mt := "Ø —"
	if not is_nan(mean):
		mt = tr("Ø %s ms") % signed_ms(mean)
		if absf(mean) >= 1.0:
			mt += "  ·  " + (tr("spät") if mean > 0.0 else tr("früh"))
	c.add_child(_plain(mt, 13, CAPTION))
	return c


## Band unter dem Verlauf: ein Balken je Abschnitt, Breite = Anteil Urteile,
## Deckkraft = relative Genauigkeit; schwaechster Abschnitt gedeckt rot.
class _SectionBand extends Control:
	const LEFT := 10.0
	const RIGHT := 58.0  # Platz der Prozent-Beschriftung im Verlauf
	var secs: Array = []
	var total := 0
	var weak := -1
	var weak_text := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x - LEFT - RIGHT
		if secs.is_empty() or total <= 0 or w <= 4.0:
			return
		var lo := 1.0
		var hi := 0.0
		for d in secs:
			if int(d.n) > 0:
				lo = minf(lo, float(d.acc))
				hi = maxf(hi, float(d.acc))
		for k in secs.size():
			var d: Dictionary = secs[k]
			if int(d.n) <= 0:
				continue
			var x0 := LEFT + w * float(d.i0) / float(total)
			var x1 := LEFT + w * float(d.i1) / float(total)
			var t := 1.0 if hi - lo < 0.0001 else (float(d.acc) - lo) / (hi - lo)
			var col := Color(UiTheme.ACCENT, 0.22 + 0.55 * t)
			if k == weak:
				col = Color(ResultsScreen.WEAK_COL, 0.95)
			draw_rect(Rect2(x0 + 1.0, 2.0, maxf(x1 - x0 - 2.0, 1.0), 6.0), col)
		if weak >= 0 and weak_text != "":
			var d: Dictionary = secs[weak]
			var font := get_theme_default_font()
			var cx := LEFT + w * (float(d.i0) + float(d.i1)) * 0.5 / float(total)
			var tw := font.get_string_size(weak_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tx := clampf(cx - tw * 0.5, 0.0, maxf(size.x - tw, 0.0))
			draw_string(font, Vector2(tx, 22.0), weak_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				ResultsScreen.WEAK_COL)


## Timing pro Abschnitt: Saeule = Genauigkeit (Wert darueber), darunter
## mittlere Abweichung und Startzeit; links Zeilen-Beschriftung.
class _SectionChart extends Control:
	const GUTTER := 46.0
	var secs: Array = []
	var weak := -1
	var row_labels: Array = ["Acc", "ms", "Start"]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if secs.is_empty():
			return
		var font := get_theme_default_font()
		var fs := 12
		var h := size.y
		var y_time := h - 3.0
		var y_off := h - 21.0
		var base := h - 36.0
		var top := 18.0
		var lo := 1.0
		for d in secs:
			if int(d.n) > 0:
				lo = minf(lo, float(d.acc))
		lo = clampf(floorf((lo - 0.01) * 100.0) / 100.0, 0.0, 0.99)
		var n := secs.size()
		var cw := (size.x - GUTTER) / float(n)
		var bw := minf(cw * 0.4, 24.0)
		var cap := ResultsScreen.CAPTION
		var muted := ResultsScreen.MUTED
		draw_string(font, Vector2(0, base - 2.0), str(row_labels[0]), HORIZONTAL_ALIGNMENT_LEFT, GUTTER, fs, muted)
		draw_string(font, Vector2(0, y_off), str(row_labels[1]), HORIZONTAL_ALIGNMENT_LEFT, GUTTER, fs, muted)
		draw_string(font, Vector2(0, y_time), str(row_labels[2]), HORIZONTAL_ALIGNMENT_LEFT, GUTTER, fs, muted)
		draw_line(Vector2(GUTTER, base + 0.5), Vector2(size.x, base + 0.5), Color(1, 1, 1, 0.08), 1.0)
		for k in n:
			var d: Dictionary = secs[k]
			var x := GUTTER + cw * float(k)
			var is_weak := k == weak
			draw_string(font, Vector2(x, y_time), ResultsScreen.fmt_clock(float(d.t0)),
				HORIZONTAL_ALIGNMENT_CENTER, cw, fs, muted)
			if int(d.n) <= 0:
				draw_string(font, Vector2(x, y_off), "—", HORIZONTAL_ALIGNMENT_CENTER, cw, fs, muted)
				continue
			var acc := float(d.acc)
			var t := clampf((acc - lo) / maxf(1.0 - lo, 0.0001), 0.0, 1.0)
			var bh := 4.0 + t * (base - top - 4.0)
			var col := ResultsScreen.WEAK_COL if is_weak else Color(UiTheme.ACCENT, 0.6)
			draw_rect(Rect2(x + (cw - bw) * 0.5, base - bh, bw, bh), col)
			draw_string(font, Vector2(x, base - bh - 5.0), UiTheme.fmt_num(acc * 100.0, 1),
				HORIZONTAL_ALIGNMENT_CENTER, cw, fs, ResultsScreen.WEAK_COL if is_weak else UiTheme.TEXT)
			var mean := float(d.mean)
			var mt := "—" if is_nan(mean) else ResultsScreen.signed_ms(mean)
			draw_string(font, Vector2(x, y_off), mt, HORIZONTAL_ALIGNMENT_CENTER, cw, fs, cap)
