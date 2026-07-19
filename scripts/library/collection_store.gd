class_name CollectionStore
extends RefCounted

## Sammlungen (wie osu-Collections): benannte Listen von Mapsets.
## Persistenz: user://collections.cfg, Section "collections",
## Key = Name, Value = Array der .osz-Dateinamen.

const PATH := "user://collections.cfg"


static func list_names() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section("collections"):
		return []
	var names := Array(cfg.get_section_keys("collections"))
	names.sort()
	return names


static func create(name: String) -> bool:
	name = name.strip_edges()
	if name == "":
		return false
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if cfg.has_section_key("collections", name):
		return false
	cfg.set_value("collections", name, [])
	cfg.save(PATH)
	return true


static func delete(name: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if cfg.has_section_key("collections", name):
		cfg.erase_section_key("collections", name)
		cfg.save(PATH)


static func maps_in(name: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return []
	var v = cfg.get_value("collections", name, [])
	return v if v is Array else []


static func contains(name: String, osz_file: String) -> bool:
	return maps_in(name).has(osz_file.get_file())


## Map rein/raus togglen. Liefert neuen Zustand (true = enthalten).
static func toggle(name: String, osz_file: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var v = cfg.get_value("collections", name, [])
	var maps: Array = v if v is Array else []
	var f := osz_file.get_file()
	var now_in: bool
	if maps.has(f):
		maps.erase(f)
		now_in = false
	else:
		maps.append(f)
		now_in = true
	cfg.set_value("collections", name, maps)
	cfg.save(PATH)
	return now_in


## Alle Sammlungen, die diese Map enthalten.
static func collections_of(osz_file: String) -> Array:
	var result := []
	for name in list_names():
		if contains(name, osz_file):
			result.append(name)
	return result
