class_name PlayfieldPreview
extends Control

## Live-Vorschau fuer alle 2D-Spielfeld-Optionen (Groessen, Richtung, Layout, Mods): ein Mini-Playfield2D
## mit ruhig herunterlaufenden Beispielnoten. refresh() liest die Settings neu.

const BOX := Vector2(260, 200)
## Virtuelle Bildhoehe (hoeher als die Box, oben abgeschnitten): unten buendig wie im
## Spiel (Linie, Tasten, Bildrand). Ein zu breites Feld (Skin-Spalten x Spurbreite)
## verkleinert die Hoehe, damit es in die Box passt (alles skaliert mit der Hoehe).
const VH := 300.0
const PERIOD := 4.6
## z-Strecke je Periode in Feldhoehen: > 1 + laengster Hold, damit Holds bis zum Ende
## gehalten werden, bevor die Note oben neu startet.
const SPAN := 1.35
## Tastendruck-Fenster nach einer Einzelnote (Z-Einheiten unter der Linie).
const PRESS_Z := 2.0
const ZL := 3.0
const ZF := -46.0
const COLORS := [Color(0.20, 0.85, 1.0), Color(1.0, 0.45, 0.88), Color(0.55, 1.0, 0.75), Color(1.0, 0.8, 0.35)]
## [Spalte, Phase 0..1, Hold-Laenge in Feldhoehen (0 = Einzelnote)]
const NOTES := [[0, 0.00, 0.0], [2, 0.18, 0.0], [1, 0.40, 0.0], [3, 0.55, 0.30], [0, 0.78, 0.0]]

var _pf: Playfield2D
## Groesse dieser Vorschau (Standard BOX; das Einstellungsfenster nutzt eine hoehere).
var box := BOX
## Virtuelle Bildhoehe dieser Vorschau (Standard VH, waechst mit box.y).
var vh := VH
var _t := 0.0
var _prev: Array = []   ## je Note: Kopf-Z und Ende-Z des letzten Frames (Treffer-Erkennung)
var _combo := 0


func _init() -> void:
	custom_minimum_size = BOX
	size = BOX
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_pf = Playfield2D.new()
	add_child(_pf)
	refresh()


## Map-Hintergrund der Vorschau (von aussen setzbar). Wird nur gezeigt, wenn
## Settings.bg_dim > 0; die Deckkraft ist bg_dim wie im Spiel (0 = kein Hintergrund).
var map_bg: Texture2D = null


func _draw() -> void:
	draw_style_box(UiTheme.glass_box(14, 0.7, 0.14), Rect2(Vector2.ZERO, size))
	var a := bg_alpha()
	if map_bg != null and a > 0.0:
		var ts := map_bg.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			var k := maxf(size.x / ts.x, size.y / ts.y)   # cover
			var dsz := ts * k
			draw_texture_rect(map_bg, Rect2((size - dsz) * 0.5, dsz), false, Color(1, 1, 1, a))


## Deckkraft des Map-Hintergrunds in der Vorschau = Settings.bg_dim (0 = unsichtbar).
static func bg_alpha() -> float:
	return clampf(Settings.bg_dim, 0.0, 1.0)


## Andere Groesse (vor oder nach _ready): Bildhoehe waechst im selben Verhaeltnis.
func set_box(b: Vector2) -> void:
	box = b
	vh = VH * b.y / BOX.y
	custom_minimum_size = b
	size = b
	refresh()


func refresh() -> void:
	queue_redraw()
	if _pf == null:
		return
	var keys := PackedStringArray()
	for k in Settings.key_lanes:
		keys.append(UiTheme.key_short(OS.get_keycode_string(k)))
	_pf.setup(4, Settings.lane_width_2d, ZL, ZF, keys, UiTheme.ACCENT,
			Settings.note_style_2d, Settings.note_size_2d)
	_pf.skin = ManiaSkin.load_skin(Settings.skin_2d) if Settings.skin_2d != "" else null
	_pf.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var h := view_height(_pf, box, vh)
	_pf.preview_size = Vector2(box.x, h)
	_pf.size = Vector2(box.x, h)
	_pf.base_pos = Vector2(0, box.y - h)   # Playfield2D setzt position selbst (Richtung/Skalierung)
	_prev.clear()
	_feed()


## Virtuelle Bildhoehe der Vorschau: VH, kleiner falls das Feld sonst breiter als die Box waere.
static func view_height(pf: Playfield2D, b: Vector2 = BOX, v: float = VH) -> float:
	pf.preview_size = Vector2(b.x, v)
	var fw := pf.field_rect().size.x
	var room := b.x - 12.0
	if fw <= room:
		return v
	return maxf(b.y, v * room / fw)


func _process(delta: float) -> void:
	_t = fmod(_t + delta, PERIOD)
	_feed()


## Wie das Spiel mit Autoplay: Einzelnoten verschwinden an der Linie (Treffer), Holds
## bleiben mit dem Kopf an der Linie stehen (gehalten), bis das Ende durch ist.
func _feed() -> void:
	if _pf == null:
		return
	_pf.begin_frame()
	var ph := _t / PERIOD
	var held := [false, false, false, false]
	var fresh := _prev.size() != NOTES.size()
	if fresh:
		_prev.resize(NOTES.size())
	for i in NOTES.size():
		var n: Array = NOTES[i]
		var col: int = n[0]
		var f := fposmod(ph + float(n[1]), 1.0)
		var z := ZF + (ZL - ZF) * f * SPAN
		var zt := z - (ZL - ZF) * float(n[2])
		var is_hold := float(n[2]) > 0.0
		# Eigene Notenfarben (lanes/snap) gelten auch hier; eingebaute Skins toenen damit.
		var nc: Color = NoteColors.color_for(col, is_hold, true, COLORS[col]) if NoteColors.is_custom(true) else COLORS[col]
		var p: Variant = _prev[i]
		_prev[i] = [z, zt]
		if not fresh and p != null and float(p[0]) <= z:
			if float(p[0]) < ZL and z >= ZL:
				_hit(col)
			if is_hold and float(p[1]) < ZL and zt >= ZL:
				_hit(col)
		if not is_hold:
			if z < ZL:
				_pf.add_note(col, z, nc)
			elif z < ZL + PRESS_Z:
				held[col] = true
		elif zt < ZL:
			if z >= ZL:
				held[col] = true
				_pf.add_hold(col, z, zt, nc, Playfield2D.STATE_HELD)
			else:
				_pf.add_hold(col, z, zt, nc)
	_pf.set_combo(_combo)
	_pf.set_lanes(held, [], [])


func _hit(col: int) -> void:
	_combo = _combo + 1 if _combo < 999 else 1
	_pf.on_judge(0, col)
