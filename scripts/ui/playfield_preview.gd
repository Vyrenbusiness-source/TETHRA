class_name PlayfieldPreview
extends Control

## Live-Vorschau fuer 2D-Spurbreite und Notengroesse: ein Mini-Playfield2D
## mit ruhig herunterlaufenden Beispielnoten. refresh() liest die Settings neu.

const BOX := Vector2(260, 200)
## Virtuelle Feldhoehe (hoeher als die Box, oben abgeschnitten): bei 200 %
## Spurbreite ist das Feld 0.8 x Hoehe = 240 px breit und passt in 260 px.
const VH := 300.0
const PERIOD := 4.0
const COLORS := [Color(0.20, 0.85, 1.0), Color(1.0, 0.45, 0.88), Color(0.55, 1.0, 0.75), Color(1.0, 0.8, 0.35)]
## [Spalte, Phase 0..1, Hold-Laenge in Phase (0 = Einzelnote)]
const NOTES := [[0, 0.00, 0.0], [2, 0.18, 0.0], [1, 0.40, 0.0], [3, 0.55, 0.30], [0, 0.78, 0.0]]

var _pf: Playfield2D
var _t := 0.0


func _init() -> void:
	custom_minimum_size = BOX
	size = BOX
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_pf = Playfield2D.new()
	add_child(_pf)
	refresh()


func _draw() -> void:
	draw_style_box(UiTheme.glass_box(14, 0.7, 0.14), Rect2(Vector2.ZERO, size))


func refresh() -> void:
	if _pf == null:
		return
	var keys := PackedStringArray()
	for k in Settings.key_lanes:
		keys.append(UiTheme.key_short(OS.get_keycode_string(k)))
	_pf.setup(4, Settings.lane_width_2d, 3.0, -46.0, keys, UiTheme.ACCENT,
			Settings.note_style_2d, Settings.note_size_2d)
	_pf.skin = ManiaSkin.load_skin(Settings.skin_2d) if Settings.skin_2d != "" else null
	_pf.preview_size = Vector2(BOX.x, VH)
	_pf.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pf.size = Vector2(BOX.x, VH)
	# Mit Skin sitzt die Linie weiter oben, damit die Tasten-Bilder sichtbar bleiben.
	_pf.position = Vector2(0, BOX.y - (_pf.line_y() + 40.0 if _pf.skin == null else _pf.line_y() + 62.0))
	_feed()


func _process(delta: float) -> void:
	_t = fmod(_t + delta, PERIOD)
	_feed()


func _feed() -> void:
	if _pf == null:
		return
	_pf.begin_frame()
	var zl := 3.0
	var zf := -46.0
	var ph := _t / PERIOD
	for n in NOTES:
		var f := fposmod(ph + float(n[1]), 1.0)
		var z := zf + (zl - zf) * f * 1.15
		var col: int = n[0]
		if float(n[2]) > 0.0:
			_pf.add_hold(col, z, z - (zl - zf) * float(n[2]), COLORS[col])
		else:
			_pf.add_note(col, z, COLORS[col])
	_pf.set_lanes([], [], [])
