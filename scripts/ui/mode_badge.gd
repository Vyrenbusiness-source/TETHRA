class_name ModeBadge
extends RefCounted

## Kleines Modus-Abzeichen fuer Scores (Bestenliste lokal/online, Profil, Ergebnis,
## Chat-Karten, Replay-Liste, Raumliste, Turnier): einfarbiges Symbol aus
## assets_game/icons/modes/<modus>.svg (24x24, currentColor = weiss, hier eingefaerbt),
## optional mit Modusname. Eine ruhige Farbe je Modus, alle gleich hell.

const ICON_DIR := "res://assets_game/icons/modes/"

## Gedaempfte Modusfarben auf Basis der UiTheme-Palette (nicht bunt).
const COLORS := {
	"mania": Color(0.788, 0.643, 0.416),     # #C9A46A Bernstein (UiTheme.ACCENT, gedaempft)
	"orbit": Color(0.557, 0.651, 0.776),     # #8EA6C6 (UiTheme.ACCENT2)
	"rally": Color(0.553, 0.725, 0.549),     # #8DB98C (UiTheme.GOOD, gedaempft)
	"dirigent": Color(0.788, 0.604, 0.557),  # #C99A8E
	"trace": Color(0.706, 0.612, 0.769),     # #B49CC4
	"rebound": Color(0.561, 0.722, 0.706),   # #8FB8B4
}

static var _cache := {}


## Modus-ID ("" = Mania, unbekannt = Mania).
static func norm(mode: String) -> String:
	return ScoreStore.normalize_mode(ScoreStore.mode_name(mode))


static func color(mode: String) -> Color:
	return COLORS[norm(mode)]


static func icon_path(mode: String) -> String:
	return ICON_DIR + norm(mode) + ".svg"


## Symbol als Textur (importiert; ohne Import direkt aus dem SVG gerastert, 2x scharf).
static func icon(mode: String) -> Texture2D:
	var m := norm(mode)
	if _cache.has(m):
		return _cache[m]
	var tex: Texture2D = null
	var path := icon_path(m)
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(path), 2.0) == OK:
			tex = ImageTexture.create_from_image(img)
	_cache[m] = tex
	return tex


## Abzeichen: Symbol (size px) in Modusfarbe, mit_label = Modusname daneben.
static func make(mode: String, size: int = 14, with_label: bool = false) -> Control:
	var m := norm(mode)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = ScoreStore.mode_label(m)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tr := TextureRect.new()
	tr.texture = icon(m)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.modulate = color(m)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tr)
	if with_label:
		var l := Label.new()
		l.text = ScoreStore.mode_label(m)
		l.add_theme_font_size_override("font_size", maxi(size - 2, 10))
		l.add_theme_color_override("font_color", color(m))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	return row
