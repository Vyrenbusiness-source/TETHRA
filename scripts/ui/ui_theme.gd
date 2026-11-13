class_name UiTheme
extends RefCounted

## Zentrale Design-Sprache von OMEN: "Instrumententafel".
## Warmer Graphit-Grund, ruhige deckende Flaechen mit Haarlinien, eine einzige
## Signalfarbe (Bernstein) fuer das, was zaehlt, kleine Radien, keine Glows.
##
## Warum Bernstein: das Spiel ist eine Fahrt ueber Spuren durchs All - Bernstein
## ist die Farbe von Cockpit-Anzeigen, Phosphor-Displays und Signallampen. Sie
## setzt sich klar von den kalten, farbigen Welten des Spielfelds ab (die bleiben
## die bunte Buehne), wirkt handwerklich statt "Neon" und erreicht auf Graphit
## wie mit dunkler Schrift darauf jeweils > 9:1 Kontrast (WCAG AAA).

## Flaechen (dunkel -> hell). Leicht warm, nie reines Schwarz.
const BG := Color(0.071, 0.067, 0.063)          # #121110 Grund
const SURFACE := Color(0.106, 0.102, 0.094)     # #1B1A18 Panels
const RAISED := Color(0.153, 0.145, 0.133)      # #272522 Buttons, Felder
## Signalfarbe: Bernstein #F2A23A. Die EINE Akzentfarbe (Primaer, Auswahl, Fokus).
const ACCENT := Color(0.949, 0.635, 0.227)
## Zweitton fuer Kennzahlen (pp) und den Orbit-Modus: gedecktes Stahlblau #8EA6C6.
## Bewusst kuehl und entsaettigt, damit er neben Bernstein nie konkurriert.
const ACCENT2 := Color(0.557, 0.651, 0.776)
## Schrift: warmes Elfenbein statt Reinweiss (15:1 auf BG), Neben-Text 6:1.
const TEXT := Color(0.925, 0.902, 0.855)        # #ECE6DA
const DIM := Color(0.616, 0.592, 0.553)         # #9D978D
## Zustaende, gedeckt: gut = Salbei, schlecht = Ziegel.
const GOOD := Color(0.553, 0.757, 0.549)        # #8DC18C
const BAD := Color(0.871, 0.443, 0.384)         # #DE7162
## Dunkle Schrift auf Akzentflaechen.
const ON_ACCENT := Color(0.094, 0.071, 0.039)   # #18120A
## Haarlinie (Trenner, Kanten).
const LINE := Color(0.925, 0.902, 0.855, 0.12)

## Radien: klein und handfest. Aufrufer geben noch die alten Werte (8..18)
## mit; sie werden auf 2..6 px abgebildet.
const R_SMALL := 2
const R_MAX := 6


static func _rad(radius: int) -> int:
	return clampi(roundi(radius * 0.34), R_SMALL, R_MAX)


## Ruhige, (fast) deckende Flaeche mit Haarlinie oben statt Rahmen-Karte.
## API wie frueher (glass_box): alpha = Deckkraft-Wunsch, border_a = Kantenstaerke.
static func glass_box(radius: int = 14, alpha: float = 0.42, border_a: float = 0.14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var a := lerpf(alpha, 1.0, 0.55)
	sb.bg_color = Color(SURFACE.r, SURFACE.g, SURFACE.b, a)
	sb.set_corner_radius_all(_rad(radius))
	sb.border_width_top = 1
	sb.border_color = Color(TEXT.r, TEXT.g, TEXT.b, clampf(border_a * 0.6, 0.04, 0.16))
	return sb


## Volltonige Flaeche (z.B. Primaer-Buttons). Kein Schatten, kein Glow.
static func solid_box(col: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(_rad(radius))
	return sb


static func _pad(sb: StyleBox) -> void:
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6


## Button: primary = Bernstein-Flaeche mit dunkler Schrift (Satzschreibung),
## sonst neutrale erhabene Flaeche. Hover/Pressed nur ueber Helligkeit, schnell.
static func style_button(b: Button, primary: bool = false, radius: int = 12) -> void:
	var normal: StyleBoxFlat
	if primary:
		normal = solid_box(primary_fill(), radius)
		b.add_theme_color_override("font_color", ON_ACCENT)
		b.add_theme_color_override("font_hover_color", ON_ACCENT)
		b.add_theme_color_override("font_pressed_color", ON_ACCENT)
		b.add_theme_color_override("font_focus_color", ON_ACCENT)
		b.add_theme_font_override("font", heading_font(0))
	else:
		normal = solid_box(RAISED, radius)
		normal.set_border_width_all(1)
		normal.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.08)
		b.add_theme_color_override("font_color", TEXT)
	_pad(normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.10)
	if not primary:
		hover.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.22)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = normal.bg_color.darkened(0.14)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(RAISED.r, RAISED.g, RAISED.b, 0.55)
	disabled.border_color = Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", _focus_box(radius))
	b.add_theme_color_override("font_disabled_color", Color(DIM.r, DIM.g, DIM.b, 0.7))
	_attach_sounds(b)


## Primaer-Fuellung: Bernstein, minimal abgedunkelt fuer ruhige Flaechen.
static func primary_fill() -> Color:
	return ACCENT.darkened(0.04)


## Ghost-Button: nur Kontur (Haarlinie), Hover fuellt leicht. Fuer alle
## Nicht-Primaer-Aktionen (Schliessen, Zurueck, Werkzeuge).
static func style_ghost_button(b: Button, radius: int = 12) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.0)
	normal.set_corner_radius_all(_rad(radius))
	normal.set_border_width_all(1)
	normal.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.20)
	_pad(normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.07)
	hover.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.36)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.12)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", _focus_box(radius))
	_attach_sounds(b)


## Zahlenformat folgt der Sprache (TranslationServer-Locale, gesetzt von
## Settings.apply): de = 1.234,5 / 81,00 % · en = 1,234.5 / 81.00%.
static func is_german() -> bool:
	return TranslationServer.get_locale().begins_with("de")


## Ganzzahl-Teil mit Tausendertrenner (sep), ohne Vorzeichen.
static func _group(digits: String, sep: String) -> String:
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += sep
		out += digits[i]
	return out


## Zahl mit Dezimalkomma (de) bzw. -punkt (en): fmt_num(0.8, 2) -> "0,80" / "0.80".
## Ab 1000 mit Tausendertrenner: 1234.5 -> "1.234,5" / "1,234.5".
static func fmt_num(v: float, decimals: int = 1) -> String:
	var d := maxi(decimals, 0)
	var raw := ("%." + str(d) + "f") % absf(v)
	var int_part := raw.get_slice(".", 0)
	var frac := raw.get_slice(".", 1) if d > 0 else ""
	var de := is_german()
	var out := _group(int_part, "." if de else ",")
	if d > 0:
		out += ("," if de else ".") + frac
	return ("-" if v < 0.0 and raw.to_float() != 0.0 else "") + out


## Score mit Tausendertrenner, ohne fuehrende Nullen: 923412 -> "923.412" / "923,412".
static func fmt_score(v: int) -> String:
	var out := _group(str(absi(v)), "." if is_german() else ",")
	return ("-" if v < 0 else "") + out


## Prozent (Wert schon in %): 85.09 -> "85,09 %" / "85.09%".
static func fmt_pct(v: float) -> String:
	return fmt_num(v, 2) + (" %" if is_german() else "%")


## ISO-String ("2026-11-06T14:30:00") oder Unix-Zeit -> "06.11.2026 14:30"
## (en: "2026-11-06 14:30").
## Unix wird in Ortszeit gewandelt, ISO-Strings unveraendert gelesen.
static func fmt_date(iso_or_unix) -> String:
	var dt: Dictionary
	if iso_or_unix is String:
		var s: String = iso_or_unix.strip_edges()
		if s.is_empty():
			return "—"
		dt = Time.get_datetime_dict_from_datetime_string(s, false)
		if dt.is_empty() or not dt.has("year"):
			return "—"
	else:
		var t := int(iso_or_unix)
		if t <= 0:
			return "—"
		t += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		dt = Time.get_datetime_dict_from_unix_time(t)
	if not is_german():
		return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.get("hour", 0), dt.get("minute", 0)]
	return "%02d.%02d.%04d %02d:%02d" % [dt.day, dt.month, dt.year, dt.get("hour", 0), dt.get("minute", 0)]


## Performance-Punkte: 33.6 -> "34 pp".
static func fmt_pp(v: float) -> String:
	return "%d pp" % roundi(v)


## Kurzer Tastenname fuer Keycaps: Comma -> ",", Period -> ".", Y -> "Y".
## Nimmt Keycode (int) oder Name (String).
static func key_short(keycode_or_name) -> String:
	var n: String
	if keycode_or_name is int:
		n = OS.get_keycode_string(keycode_or_name)
	else:
		n = str(keycode_or_name)
	n = n.strip_edges()
	var map := {
		"comma": ",", "period": ".", "slash": "/", "backslash": "\\", "minus": "-",
		"equal": "=", "semicolon": ";", "apostrophe": "'", "bracketleft": "[",
		"bracketright": "]", "quoteleft": "`", "space": "Leertaste", "escape": "Esc",
		"enter": "Enter", "tab": "Tab", "backspace": "Rück", "ctrl": "Strg",
		"left": "←", "right": "→", "up": "↑", "down": "↓",
	}
	var k := n.to_lower()
	if map.has(k):
		return TranslationServer.translate(map[k])
	return n.to_upper() if n.length() == 1 else n


## Vollbild-Backdrop fuer Modals: ruhige Abdunklung im Grundton (kein Blur,
## kein Glas), absorbiert Klicks. Wird an parent gehaengt (falls gesetzt) und
## zurueckgegeben.
static func modal_backdrop(parent: Control) -> Control:
	var root := Control.new()
	root.name = "ModalBackdrop"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(BG.r * 0.5, BG.g * 0.5, BG.b * 0.5, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	if parent != null:
		parent.add_child(root)
	return root


## Einheitliche Modal-Titelzeile: Ueberschrift in Satzschreibung (Heading-
## Schnitt, 24px), Close rechts, darunter Haarlinie + 20px Abstand.
static func modal_header(title: String, on_close: Callable) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_bottom", 20)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	wrap.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	var l := Label.new()
	l.text = TranslationServer.translate(title)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", heading_font(0))
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", TEXT)
	row.add_child(l)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(40, 40)
	style_ghost_button(x, 10)
	if on_close.is_valid():
		x.pressed.connect(on_close)
	row.add_child(x)
	col.add_child(hairline())
	return wrap


## Waagerechte Haarlinie (1px, LINE) als Trenner statt Rahmen.
static func hairline() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## UI-Klang einmalig pro Button verbinden (Meta-Flag verhindert Duplikate).
## mouse_entered feuert nur bei echter Mausbewegung, nie bei programmatischem Fokus.
static func _attach_sounds(b: BaseButton) -> void:
	if b.has_meta("ui_sounds"):
		return
	b.set_meta("ui_sounds", true)
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.ui_hover())
	b.pressed.connect(func(): Sfx.ui_click())


## Tag fuer OpenType-Features (tnum = tabellarische Ziffern).
static func _tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## Ueberschriften-Schnitt: Bahnschrift SemiBold, leicht schmal (DIN-Anmutung
## wie Beschriftung auf Instrumenten), tabellarische Ziffern. spacing kommt
## von alten Aufrufern (2..4 = "gesperrt"); gesperrt wird nur noch minimal.
static func heading_font(spacing: int = 2) -> FontVariation:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Semibold", "Segoe UI"])
	f.font_weight = 600
	var fv := FontVariation.new()
	fv.base_font = f
	fv.variation_opentype = {_tag("wdth"): 90.0, _tag("wght"): 600.0}
	fv.opentype_features = {_tag("tnum"): 1}
	fv.spacing_glyph = clampi(spacing - 2, 0, 1)
	return fv


## Fliesstext-Schnitt (globaler Theme-Font): Segoe UI mit tabellarischen
## Ziffern, damit Zahlenkolonnen (Scores, ms, %) sauber untereinander stehen.
static func body_font() -> FontVariation:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial"])
	var fv := FontVariation.new()
	fv.base_font = f
	fv.opentype_features = {_tag("tnum"): 1}
	return fv


## Dezenter Hover fuer beliebige Controls (Karten): kaum Skalierung, schnell.
static func attach_hover(c: Control, scale: float = 1.03) -> void:
	var s := 1.0 + clampf(scale - 1.0, 0.0, 0.03) * 0.33
	c.mouse_entered.connect(func(): _hover_to(c, s, 1.0))
	c.mouse_exited.connect(func(): _hover_to(c, 1.0, 1.0))


static func _hover_to(c: Control, s: float, _dummy: float) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(s, s), 0.08)


## Echter weicher Blur ohne Blockartefakte: in Stufen stark runterskalieren,
## per Down-Up-Zyklen tiefpassfiltern (Kawase-Prinzip) und dann in sanften
## x2-Schritten wieder hochziehen — ein einzelner grosser Upscale-Sprung
## erzeugt genau die kreuzfoermigen Verzerrungen, die hier vermieden werden.
## divisor: groesser = weicher.
static func blurred_texture(tex: Texture2D, divisor: int = 10) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		if img.decompress() != OK:
			return tex
	var w := img.get_width()
	var h := img.get_height()
	if w < 32 or h < 32:
		return tex
	var small_w := maxi(w / divisor, 96)
	var small_h := maxi(small_w * h / w, 54)
	# Sanft in zwei Stufen verkleinern (kein Aliasing im Zwischenbild) …
	if w > small_w * 3:
		img.resize(small_w * 3, small_h * 3, Image.INTERPOLATE_LANCZOS)
	img.resize(small_w, small_h, Image.INTERPOLATE_LANCZOS)
	# … Down-Up-Zyklen als Tiefpass: glaettet Restkanten butterweich …
	for i in 2:
		img.resize(small_w * 2, small_h * 2, Image.INTERPOLATE_CUBIC)
		img.resize(small_w, small_h, Image.INTERPOLATE_BILINEAR)
	# … und in x2-Schritten hochziehen. Endgroesse bis ~960px breit, damit
	# die finale Streckung auf Bildschirmgroesse klein bleibt.
	var cw := small_w
	var ch := small_h
	while cw < 960 and cw < w:
		cw *= 2
		ch *= 2
		img.resize(cw, ch, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(img)


## Globales OMEN-Theme: ersetzt das graue Godot-Standard-Aussehen ALLER
## Controls (Slider, Dropdowns, Scrollbalken, Popups, Eingabefelder …) durch
## die Instrumententafel-Optik. Wird einmalig beim Start auf das Root-Window
## gelegt — Panels mit eigenen Overrides behalten ihre Speziallooks.
static func build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()

	# Buttons (Fallback fuer alles, was nicht per style_button lief).
	var bn := solid_box(RAISED, 9)
	bn.set_border_width_all(1)
	bn.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.08)
	bn.content_margin_left = 12
	bn.content_margin_right = 12
	bn.content_margin_top = 6
	bn.content_margin_bottom = 6
	var bh: StyleBoxFlat = bn.duplicate()
	bh.bg_color = bn.bg_color.lightened(0.10)
	bh.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.22)
	var bp: StyleBoxFlat = bn.duplicate()
	bp.bg_color = bn.bg_color.darkened(0.14)
	var bd: StyleBoxFlat = bn.duplicate()
	bd.bg_color = Color(RAISED.r, RAISED.g, RAISED.b, 0.45)
	bd.border_color = Color(0, 0, 0, 0)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", cls, bn)
		th.set_stylebox("hover", cls, bh)
		th.set_stylebox("pressed", cls, bp)
		th.set_stylebox("focus", cls, _focus_box(9))
		th.set_stylebox("disabled", cls, bd)
		th.set_color("font_color", cls, TEXT)
		th.set_color("font_hover_color", cls, TEXT.lightened(0.3))
		th.set_color("font_pressed_color", cls, TEXT)
		th.set_color("font_disabled_color", cls, DIM)
	# Switches: transparente Flaeche + eigene, klar lesbare Kipp-Schalter.
	var empty := StyleBoxEmpty.new()
	for cls2 in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "focus", "disabled",
				"hover_pressed"]:
			th.set_stylebox(st, cls2, empty)
		th.set_color("font_color", cls2, TEXT)
		th.set_color("font_hover_color", cls2, TEXT.lightened(0.3))
	var sw_on := _switch_icon(true)
	var sw_off := _switch_icon(false)
	th.set_icon("checked", "CheckButton", sw_on)
	th.set_icon("unchecked", "CheckButton", sw_off)
	th.set_icon("checked_disabled", "CheckButton", sw_on)
	th.set_icon("unchecked_disabled", "CheckButton", sw_off)

	# Eingabefelder: vertiefte Flaeche, Unterkante als Linie, Fokus = Bernstein.
	var le := solid_box(Color(0, 0, 0, 0.28), 6)
	le.border_width_bottom = 1
	le.border_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.24)
	le.content_margin_left = 12
	le.content_margin_right = 12
	le.content_margin_top = 5
	le.content_margin_bottom = 5
	var lf: StyleBoxFlat = le.duplicate()
	lf.border_width_bottom = 2
	lf.border_color = ACCENT
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lf)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", ACCENT)
	th.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30))
	th.set_color("font_placeholder_color", "LineEdit", Color(DIM.r, DIM.g, DIM.b, 0.75))

	# Dropdown-Menues + Kontextmenues: deckend, Haarlinie, Hover = Bernstein-Hauch.
	var pm := solid_box(RAISED, 9)
	pm.set_border_width_all(1)
	pm.border_color = LINE
	pm.set_content_margin_all(4)
	th.set_stylebox("panel", "PopupMenu", pm)
	var pmh := solid_box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 6)
	th.set_stylebox("hover", "PopupMenu", pmh)
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", TEXT.lightened(0.3))
	th.set_color("font_accelerator_color", "PopupMenu", DIM)

	# Slider: schmale Spur, flache Bernstein-Fuellung, Grabber = Fader-Kappe
	# (wie am Mischpult) statt leuchtendem Punkt.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.12)
	track.set_corner_radius_all(1)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := _fill_box()
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _glow_dot(22, 0.0, 0.0, TEXT))
	th.set_icon("grabber_highlight", "HSlider", _glow_dot(22, 0.0, 0.0, TEXT.lightened(0.4)))
	th.set_icon("grabber_disabled", "HSlider", _glow_dot(22, 0.0, 0.0, DIM))

	# Scrollbalken: schmal + dezent, eckig.
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.04)
	sb_bg.set_corner_radius_all(2)
	sb_bg.content_margin_left = 3
	sb_bg.content_margin_right = 3
	sb_bg.content_margin_top = 3
	sb_bg.content_margin_bottom = 3
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.20)
	sb_grab.set_corner_radius_all(2)
	sb_grab.content_margin_left = 3
	sb_grab.content_margin_right = 3
	sb_grab.content_margin_top = 3
	sb_grab.content_margin_bottom = 3
	var sb_grab_h: StyleBoxFlat = sb_grab.duplicate()
	sb_grab_h.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.34)
	for cls3 in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", cls3, sb_bg)
		th.set_stylebox("grabber", cls3, sb_grab)
		th.set_stylebox("grabber_highlight", cls3, sb_grab_h)
		th.set_stylebox("grabber_pressed", cls3, sb_grab_h)

	# Fortschrittsbalken + Tooltip.
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(TEXT.r, TEXT.g, TEXT.b, 0.10)
	pb_bg.set_corner_radius_all(1)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ACCENT
	pb_fill.set_corner_radius_all(1)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	var tip := solid_box(RAISED, 6)
	tip.set_border_width_all(1)
	tip.border_color = LINE
	tip.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", TEXT)
	return th


## Kipp-Schalter prozedural zeichnen (eckig, 3px Radius): Aus = graue Spur,
## Knopf links in DIM; An = Bernstein-Spur, dunkler Knopf rechts.
static func _switch_icon(on: bool) -> ImageTexture:
	var w := 40
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color(ACCENT.r, ACCENT.g, ACCENT.b, 1.0) if on \
			else Color(TEXT.r, TEXT.g, TEXT.b, 0.16)
	var knob_col := ON_ACCENT if on else TEXT.darkened(0.15)
	var kw := 16
	var kx0 := (w - 3 - kw) if on else 3
	var track_box := Rect2(1, 2, w - 2, h - 4)
	var knob_box := Rect2(kx0, 5, kw, h - 10)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var col := Color(0, 0, 0, 0)
			var ta := _rrect_cov(p, track_box, 3.0)
			if ta > 0.0:
				col = Color(track.r, track.g, track.b, track.a * ta)
			var ka := _rrect_cov(p, knob_box, 2.0)
			if ka > 0.0:
				col = col.lerp(Color(knob_col.r, knob_col.g, knob_col.b, 1.0), ka)
				col.a = maxf(col.a, ka)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Anti-aliasierte Abdeckung eines Pixels durch ein abgerundetes Rechteck.
static func _rrect_cov(p: Vector2, r: Rect2, rad: float) -> float:
	var c := r.get_center()
	var half := r.size * 0.5 - Vector2(rad, rad)
	var q := (p - c).abs() - half
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var d := outside + minf(maxf(q.x, q.y), 0.0) - rad
	return clampf(0.5 - d, 0.0, 1.0)


## Fokus-Rahmen (Tastatur): 2px Bernstein-Kontur, 3px ausserhalb des Controls,
## damit er auch auf Bernstein-Flaechen sichtbar bleibt.
static func _focus_box(radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_corner_radius_all(_rad(radius) + 2)
	sb.set_border_width_all(2)
	sb.border_color = ACCENT
	sb.set_expand_margin_all(3)
	return sb


## Gefuellter Slider-Teil: flache Bernstein-Linie (4px), kein Verlauf.
static func _fill_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(1)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


## Slider-Grabber als Fader-Kappe: schmales Rechteck mit Mittelstrich.
## (Name/Signatur aus der alten Glow-Version; core_r/glow werden ignoriert.)
static func _glow_dot(size: int, _core_r: float, _glow: float, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cap := Rect2(size * 0.5 - 5.0, 2.0, 10.0, size - 4.0)
	var groove := Rect2(size * 0.5 - 4.0, size * 0.5 - 1.0, 8.0, 2.0)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var a := _rrect_cov(p, cap, 2.0)
			var out := Color(col.r, col.g, col.b, a)
			if groove.has_point(p):
				out = Color(BG.r, BG.g, BG.b, a)
			img.set_pixel(x, y, out)
	return ImageTexture.create_from_image(img)


## Kleines rundes Grabber-Icon (fuer Slider) prozedural zeichnen.
static func _dot_icon(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


## Sektions-Label: klein (12px), Versalien leicht gesperrt, gedimmt - die
## einzige Stelle, an der Versalien erlaubt sind.
static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", heading_font(3))
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM)
	return l


## Satzschreibung fuer Knopf-Texte aus Versal-Schluesseln: "NICHT BEREIT" ->
## "Nicht bereit", "WEITER  (ENTER)" -> "Weiter (Enter)", "ÜBUNGS-MAP" ->
## "Übungs-Map". Gemischte Texte und Kuerzel (<= 3 Zeichen) bleiben unveraendert.
static func sentence(t: String) -> String:
	if t.length() <= 3 or t != t.to_upper():
		return t
	var out := ""
	var cap := true
	for i in t.length():
		var c := t[i]
		if c.to_upper() != c.to_lower():
			out += c.to_upper() if cap else c.to_lower()
			cap = false
		else:
			out += c
			if c == "(" or c == "-":
				cap = true
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out
