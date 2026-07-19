class_name HitObject
extends RefCounted

## Basisklasse fuer alle HitObjects (Abschnitt 3.4).
## x,y,time,type,hitSound,objectParams,hitSample

enum Kind { CIRCLE, SLIDER, SPINNER, MANIA }

## osu-Playfield-Koordinaten: x in [0,512], y in [0,384].
var x: float = 0.0
var y: float = 0.0

## Hit-Zeitpunkt in ms (Audio-Zeit).
var time: float = 0.0

## Rohes type-Bitfeld aus der Datei.
var type: int = 0

## New Combo (type & 4) — kosmetisch/Gruppierung.
var new_combo: bool = false

## Diskriminator fuer den konkreten Typ.
var kind: int = Kind.CIRCLE


## Endzeit des Objekts in ms. Circle: == time. Slider/Spinner ueberschreiben.
func end_time() -> float:
	return time


## osu-Startposition als Vector2 (Playfield-Koordinaten).
func position() -> Vector2:
	return Vector2(x, y)
