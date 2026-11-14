class_name MineDraw2D
extends RefCounted

## 2D-Form der Mine (Mod "MN"): Raute mit dunklem Kern, gedeckt roter Kante und kleinem
## roten Mittelstein. Unterscheidet sich in Form (Raute statt Balken/Kreis/Skin-Note) und
## Farbe von jeder Note, auch mit osu!-Skins (die keine Minen-Grafik haben). Kein Leuchten.

const RIM := Color(0.86, 0.33, 0.31)
const CORE := Color(0.17, 0.05, 0.06)
## Breite der Raute als Anteil der Spaltenbreite, Hoehe relativ zur Breite.
const W_FRAC := 0.56
const H_RATIO := 0.78


## Mine mit Mitte (cx, cy) in einer Spalte der Breite col_w zeichnen; a = Deckkraft.
static func draw(ci: CanvasItem, cx: float, cy: float, col_w: float, a: float) -> void:
	if a <= 0.004:
		return
	var hw := col_w * W_FRAC * 0.5
	var hh := hw * H_RATIO
	var outer := PackedVector2Array([
		Vector2(cx, cy - hh), Vector2(cx + hw, cy), Vector2(cx, cy + hh), Vector2(cx - hw, cy)])
	ci.draw_colored_polygon(outer, Color(CORE.r, CORE.g, CORE.b, 0.92 * a))
	var lw := maxf(2.0, hw * 0.14)
	var ring := outer.duplicate()
	ring.append(outer[0])
	ci.draw_polyline(ring, Color(RIM.r, RIM.g, RIM.b, a), lw, true)
	var k := 0.34
	var inner := PackedVector2Array([
		Vector2(cx, cy - hh * k), Vector2(cx + hw * k, cy), Vector2(cx, cy + hh * k), Vector2(cx - hw * k, cy)])
	ci.draw_colored_polygon(inner, Color(RIM.r, RIM.g, RIM.b, 0.9 * a))
