class_name Spinner
extends HitObject

## Wirbel-Anker (Abschnitt 3.4). x,y sind immer 256,192 (zentriert).
## x,y,time,type,hitSound,endTime,hitSample

var spin_end_time: float = 0.0

func _init() -> void:
	kind = Kind.SPINNER

func end_time() -> float:
	return spin_end_time
