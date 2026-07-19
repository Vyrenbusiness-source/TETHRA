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


## Sektions-Ueberschrift im Akzentton.
static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l
