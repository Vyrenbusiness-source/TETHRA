class_name ManiaNote
extends HitObject

## osu!mania-Note (Mode 3): Spalte statt freier Position.
## column = floor(x * columnCount / 512), Hold-Note = type & 128 mit
## endTime aus objectParams ("endTime:hitSample").

var column: int = 0
var is_hold: bool = false
var hold_end: float = 0.0

func _init() -> void:
	kind = Kind.MANIA

func end_time() -> float:
	return hold_end if is_hold else time
