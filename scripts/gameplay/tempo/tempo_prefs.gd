class_name TempoPrefs
extends RefCounted

## Einstellungen fuer Uebung/Turbo (user://tempo.cfg, nicht in settings.cfg):
## Tonhoehe halten (Time-Stretch) und die letzten Uebungs-Tempi.

const PATH := "user://tempo.cfg"


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)
	return c


static func get_value(key: String, def: Variant) -> Variant:
	return _cfg().get_value("tempo", key, def)


static func set_value(key: String, v: Variant) -> void:
	var c := _cfg()
	c.set_value("tempo", key, v)
	c.save(PATH)


## true = Tonhoehe bleibt (Time-Stretch), false = Nightcore-Klang.
static func keep_pitch() -> bool:
	return bool(get_value("keep_pitch", false))


static func set_keep_pitch(on: bool) -> void:
	set_value("keep_pitch", on)
