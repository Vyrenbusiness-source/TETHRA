class_name UiTheme
extends RefCounted

## Zentrale Design-Sprache: Farben + Style-Helfer fuer das clean glassy Design
## (halbtransparente Flaechen, feine Raender, weiche Hover-Effekte).

const BG := Color(0.03, 0.03, 0.05)
const ACCENT := Color(0.20, 0.85, 1.0)
const ACCENT2 := Color(1.0, 0.45, 0.88)
const TEXT := Color(0.95, 0.96, 1.0)
const DIM := Color(0.62, 0.64, 0.72)
const GOOD := Color(0.55, 1.0, 0.75)


## Halbtransparente, abgerundete Glas-Flaeche mit feinem Rand.
static func glass_box(radius: int = 14, alpha: float = 0.42, border_a: float = 0.14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, alpha)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, border_a)
	# Weicher Drop-Shadow: hebt jedes Panel von der Szene ab (Tiefe).
	sb.shadow_size = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(0, 4)
	return sb


## Volltonige Flaeche (z.B. Primaer-Buttons).
static func solid_box(col: Color, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	# Dezenter neutraler Schatten — kein Neon-Glow.
	sb.shadow_size = 5
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 3)
	return sb


## Button im Glas-Stil inkl. Hover-/Pressed-Zustaenden und weichem Scale-Hover.
static func style_button(b: Button, primary: bool = false, radius: int = 12) -> void:
	var normal: StyleBoxFlat
	if primary:
		normal = solid_box(ACCENT, radius)
		b.add_theme_color_override("font_color", Color(0.02, 0.05, 0.08))
	else:
		normal = glass_box(radius, 0.5)
		b.add_theme_color_override("font_color", TEXT)
	# Innenabstand: Text/Symbole (★, ⤓ …) duerfen nie am Rand kleben.
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.14)
	if not primary:
		hover.border_color = Color(1, 1, 1, 0.26)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = normal.bg_color.darkened(0.10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	attach_hover(b)


## Marken-Typo (Bahnschrift, fett, leicht gesperrt) fuer Titel/Headings.
static func heading_font(spacing: int = 2) -> FontVariation:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI Black", "Impact"])
	f.font_weight = 700
	var fv := FontVariation.new()
	fv.base_font = f
	fv.spacing_glyph = spacing
	return fv


## Weicher Scale-/Aufhell-Hover fuer beliebige Controls (Karten, Buttons).
static func attach_hover(c: Control, scale: float = 1.03) -> void:
	c.mouse_entered.connect(func(): _hover_to(c, scale, 1.0))
	c.mouse_exited.connect(func(): _hover_to(c, 1.0, 1.0))


static func _hover_to(c: Control, s: float, _dummy: float) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(s, s), 0.12)


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


## Globales TETHRA-Theme: ersetzt das graue Godot-Standard-Aussehen ALLER
## Controls (Slider, Dropdowns, Scrollbalken, Popups, Eingabefelder …) durch
## die Glass-Optik. Wird einmalig beim Start auf das Root-Window gelegt —
## Panels mit eigenen Overrides behalten ihre Speziallooks.
static func build_theme() -> Theme:
	var th := Theme.new()

	# Buttons (Fallback fuer alles, was nicht per style_button lief).
	var bn := glass_box(10, 0.5)
	bn.shadow_size = 0
	bn.content_margin_left = 12
	bn.content_margin_right = 12
	bn.content_margin_top = 6
	bn.content_margin_bottom = 6
	var bh: StyleBoxFlat = bn.duplicate()
	bh.bg_color = bn.bg_color.lightened(0.14)
	bh.border_color = Color(1, 1, 1, 0.26)
	var bp: StyleBoxFlat = bn.duplicate()
	bp.bg_color = bn.bg_color.darkened(0.10)
	var bd: StyleBoxFlat = bn.duplicate()
	bd.bg_color = Color(0.08, 0.09, 0.14, 0.25)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", cls, bn)
		th.set_stylebox("hover", cls, bh)
		th.set_stylebox("pressed", cls, bp)
		th.set_stylebox("focus", cls, bh)
		th.set_stylebox("disabled", cls, bd)
		th.set_color("font_color", cls, TEXT)
		th.set_color("font_hover_color", cls, Color(1, 1, 1))
		th.set_color("font_disabled_color", cls, DIM)
	# Switches: transparente Flaeche (kein Button-Kapsel-Fallback) + eigene,
	# klar lesbare Pill-Icons — Aus ist sonst auf Glass kaum erkennbar.
	var empty := StyleBoxEmpty.new()
	for cls2 in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "focus", "disabled",
				"hover_pressed"]:
			th.set_stylebox(st, cls2, empty)
		th.set_color("font_color", cls2, TEXT)
		th.set_color("font_hover_color", cls2, Color(1, 1, 1))
	var sw_on := _switch_icon(true)
	var sw_off := _switch_icon(false)
	th.set_icon("checked", "CheckButton", sw_on)
	th.set_icon("unchecked", "CheckButton", sw_off)
	th.set_icon("checked_disabled", "CheckButton", sw_on)
	th.set_icon("unchecked_disabled", "CheckButton", sw_off)

	# Eingabefelder.
	var le := glass_box(9, 0.5)
	le.shadow_size = 0
	le.content_margin_left = 10
	le.content_margin_right = 10
	le.content_margin_top = 5
	le.content_margin_bottom = 5
	var lf: StyleBoxFlat = le.duplicate()
	lf.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lf)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Color(DIM.r, DIM.g, DIM.b, 0.7))

	# Dropdown-Menues + Kontextmenues.
	var pm := StyleBoxFlat.new()
	pm.bg_color = Color(0.09, 0.10, 0.15, 0.98)
	pm.set_corner_radius_all(10)
	pm.set_border_width_all(1)
	pm.border_color = Color(1, 1, 1, 0.12)
	pm.set_content_margin_all(6)
	th.set_stylebox("panel", "PopupMenu", pm)
	var pmh := StyleBoxFlat.new()
	pmh.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18)
	pmh.set_corner_radius_all(7)
	th.set_stylebox("hover", "PopupMenu", pmh)
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))

	# Slider: duenne Bahn, gefuellter Akzent-Teil.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.10)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _dot_icon(14, Color(0.95, 0.97, 1.0)))
	th.set_icon("grabber_highlight", "HSlider", _dot_icon(16, Color(1, 1, 1)))

	# Scrollbalken: schmal + dezent.
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(1, 1, 1, 0.04)
	sb_bg.set_corner_radius_all(4)
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(1, 1, 1, 0.22)
	sb_grab.set_corner_radius_all(4)
	var sb_grab_h: StyleBoxFlat = sb_grab.duplicate()
	sb_grab_h.bg_color = Color(1, 1, 1, 0.36)
	for cls3 in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", cls3, sb_bg)
		th.set_stylebox("grabber", cls3, sb_grab)
		th.set_stylebox("grabber_highlight", cls3, sb_grab_h)
		th.set_stylebox("grabber_pressed", cls3, sb_grab_h)

	# Fortschrittsbalken + Tooltip.
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(1, 1, 1, 0.08)
	pb_bg.set_corner_radius_all(5)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ACCENT
	pb_fill.set_corner_radius_all(5)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.08, 0.09, 0.14, 0.97)
	tip.set_corner_radius_all(8)
	tip.set_border_width_all(1)
	tip.border_color = Color(1, 1, 1, 0.14)
	tip.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", TEXT)
	return th


## Switch-Pill prozedural zeichnen: Aus = graue Pille/Knob links,
## An = Akzent-Pille/Knob rechts.
static func _switch_icon(on: bool) -> ImageTexture:
	var w := 44
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := 10.0
	var pill := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.92) if on \
			else Color(1, 1, 1, 0.17)
	var a := Vector2(r + 2.0, h * 0.5)
	var b := Vector2(w - r - 2.0, h * 0.5)
	var knob := (b if on else a)
	var kr := r - 3.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			var d := (p - (a + (b - a) * t)).length()
			var alpha := clampf(r - d + 0.5, 0.0, 1.0)
			var col := Color(pill.r, pill.g, pill.b, pill.a * alpha)
			# Weisser Knob drueber.
			var kd := (p - knob).length()
			var ka := clampf(kr - kd + 0.5, 0.0, 1.0)
			col = col.lerp(Color(0.97, 0.98, 1.0, 1.0), ka)
			col.a = maxf(col.a, ka)
			img.set_pixel(x, y, col)
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


## Sektions-Ueberschrift im Akzentton.
static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l
