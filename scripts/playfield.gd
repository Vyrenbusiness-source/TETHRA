class_name Playfield
extends RefCounted

## Koordinaten-Transform osu-Playfield (512x384) -> Bildschirm (Abschnitt 3.4).
## Playfield 4:3 zentriert; scale = playfieldHeight / 384. Render-Transform und
## Input-Mapping strikt trennen (Regel 8) — diese Klasse ist reines Rendering.

var scale: float = 1.0
var origin: Vector2 = Vector2.ZERO
var height_fraction: float = 0.8

func configure(screen_size: Vector2, fraction: float = 0.8) -> void:
	height_fraction = fraction
	var pf_height := screen_size.y * fraction
	scale = DifficultyCalc.playfield_scale(pf_height)
	var pf_width := DifficultyCalc.PLAYFIELD_WIDTH * scale
	origin = Vector2(
		screen_size.x * 0.5 - pf_width * 0.5,
		screen_size.y * 0.5 - pf_height * 0.5
	)

## osu-Koordinate (0..512, 0..384) -> Bildschirmposition.
func to_screen(osu_pos: Vector2) -> Vector2:
	return origin + osu_pos * scale

## Bildschirmposition -> osu-Koordinate (fuer Input-Mapping).
func to_osu(screen_pos: Vector2) -> Vector2:
	if scale == 0.0:
		return Vector2.ZERO
	return (screen_pos - origin) / scale

## osu-Radius (osupixel) -> Bildschirm-Radius.
func radius_to_screen(osu_radius: float) -> float:
	return osu_radius * scale

## Rahmen des Playfields in Bildschirmkoordinaten.
func rect() -> Rect2:
	return Rect2(origin, Vector2(DifficultyCalc.PLAYFIELD_WIDTH, DifficultyCalc.PLAYFIELD_HEIGHT) * scale)
