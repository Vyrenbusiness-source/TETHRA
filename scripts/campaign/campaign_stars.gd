class_name CampaignStars
extends Control

## Sterne einer Stufe als gezeichnete Formen (kein Schrift-Glyph): gefuellt = Ziel
## erfuellt, sonst feiner Umriss.

var met: Array = [false, false, false]
var star_px := 14.0
var gap_px := 5.0
var col_on := UiTheme.ACCENT
var col_off := Color(UiTheme.DIM.r, UiTheme.DIM.g, UiTheme.DIM.b, 0.55)


static func make(p_met: Array, px: float, gap: float = -1.0) -> CampaignStars:
	var s := CampaignStars.new()
	s.met = p_met
	s.star_px = px
	s.gap_px = gap if gap >= 0.0 else px * 0.36
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.custom_minimum_size = Vector2(s.width(), px)
	s.size = s.custom_minimum_size
	return s


func width() -> float:
	return met.size() * star_px + maxf(met.size() - 1, 0) * gap_px


static func star_points(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var rad := r if i % 2 == 0 else r * 0.44
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw() -> void:
	var y := size.y * 0.5 + star_px * 0.04
	for i in met.size():
		var c := Vector2(i * (star_px + gap_px) + star_px * 0.5, y)
		var pts := star_points(c, star_px * 0.52)
		if bool(met[i]):
			draw_colored_polygon(pts, col_on)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col_off, maxf(star_px / 12.0, 1.0), true)
