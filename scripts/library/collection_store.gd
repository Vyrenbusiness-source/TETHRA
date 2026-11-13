class_name CollectionStore
extends RefCounted

## Sammlungen (wie osu-Collections): benannte Listen von Mapsets.
## Persistenz: user://collections.cfg, Section "collections",
## Key = Name, Value = Array der .osz-Dateinamen.
## Geloeschte Sammlungen wandern in die Section "deleted" (Papierkorb) und
## lassen sich mit restore() zurueckholen: ein Fehlklick kostet keine Daten.
## Vor jedem Schreiben wird der letzte Stand mit Inhalt nach <Datei>.bak kopiert.
## Modus je Sammlung: Section "modes", Key = Name, Value = Modus (mania, orbit,
## rally, dirigent, trace, rebound). Kein Eintrag = "alle Modi" (MODE_ALL): alte
## Dateien bleiben unveraendert gueltig, nichts wird umgeschrieben.

const PATH := "user://collections.cfg"
const SEC := "collections"
const SEC_TRASH := "deleted"
const SEC_MODE := "modes"
const SEC_TRASH_MODE := "deleted_modes"
const MODE_ALL := ""  # Sammlung gilt in allen Modi
const MODES: Array[String] = ["mania", "orbit", "rally", "dirigent", "trace", "rebound"]

## Tests setzen hier eine eigene Datei (nie gegen die echten Nutzerdaten).
static var path_override := ""


## Aktive Datei: Test-Override, dann --collections-path=<Datei> (Harness), sonst PATH.
static func path() -> String:
	if path_override != "":
		return path_override
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--collections-path="):
			return a.trim_prefix("--collections-path=")
	return PATH


static func _read() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path())
	return cfg


## Zum Schreiben laden. null = Datei da, aber nicht lesbar: dann nie ueberschreiben.
static func _open() -> ConfigFile:
	var cfg := ConfigFile.new()
	var p := path()
	if FileAccess.file_exists(p) and FileAccess.get_file_as_bytes(p).size() > 0 and cfg.load(p) != OK:
		push_warning("collections.cfg nicht lesbar, Aenderung verworfen: " + p)
		return null
	return cfg


static func _save(cfg: ConfigFile) -> bool:
	var p := path()
	# Sicherung nur, wenn der alte Stand Sammlungen hat (leer ueberschreibt nie eine gute .bak).
	var old := ConfigFile.new()
	if old.load(p) == OK and old.has_section(SEC):
		var bytes := FileAccess.get_file_as_bytes(p)
		var bak := FileAccess.open(p + ".bak", FileAccess.WRITE)
		if bak != null:
			bak.store_buffer(bytes)
			bak.close()
	return cfg.save(p) == OK


static func list_names() -> Array:
	var cfg := _read()
	if not cfg.has_section(SEC):
		return []
	var names := Array(cfg.get_section_keys(SEC))
	names.sort_custom(func(a, b): return str(a).naturalnocasecmp_to(str(b)) < 0)
	return names


static func exists(name: String) -> bool:
	name = name.strip_edges()
	return name != "" and _read().has_section_key(SEC, name)


## Unbekannter Modus -> MODE_ALL.
static func normalize_mode(mode: String) -> String:
	return mode if MODES.has(mode) else MODE_ALL


## mode: Modus der Sammlung, MODE_ALL ("") = alle Modi.
static func create(name: String, mode: String = MODE_ALL) -> bool:
	name = name.strip_edges()
	if name == "":
		return false
	var cfg := _open()
	if cfg == null or cfg.has_section_key(SEC, name):
		return false
	cfg.set_value(SEC, name, [])
	_put_mode(cfg, SEC_MODE, name, mode)
	return _save(cfg)


static func _put_mode(cfg: ConfigFile, sec: String, name: String, mode: String) -> void:
	var m := normalize_mode(mode)
	if m != MODE_ALL:
		cfg.set_value(sec, name, m)
	elif cfg.has_section_key(sec, name):
		cfg.erase_section_key(sec, name)


## Modus einer Sammlung; MODE_ALL ("") = alle Modi (auch jede alte Sammlung).
static func mode_of(name: String) -> String:
	return normalize_mode(str(_read().get_value(SEC_MODE, name, MODE_ALL)))


## Modus aendern. false: Sammlung fehlt oder Datei nicht schreibbar.
static func set_mode(name: String, mode: String) -> bool:
	var cfg := _open()
	if cfg == null or not cfg.has_section_key(SEC, name):
		return false
	_put_mode(cfg, SEC_MODE, name, mode)
	return _save(cfg)


## Sammlungen fuer einen Modus: die des Modus und alle "alle Modi", sortiert.
static func list_for(mode: String) -> Array:
	var cfg := _read()
	var out: Array = []
	for name in list_names():
		var m := normalize_mode(str(cfg.get_value(SEC_MODE, name, MODE_ALL)))
		if m == MODE_ALL or m == mode:
			out.append(name)
	return out


## Umbenennen, Maps bleiben. false: leer, Ziel gibt es schon, Quelle fehlt.
static func rename(old_name: String, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name == "" or new_name == old_name:
		return false
	var cfg := _open()
	if cfg == null or not cfg.has_section_key(SEC, old_name) or cfg.has_section_key(SEC, new_name):
		return false
	cfg.set_value(SEC, new_name, cfg.get_value(SEC, old_name, []))
	cfg.erase_section_key(SEC, old_name)
	_put_mode(cfg, SEC_MODE, new_name, str(cfg.get_value(SEC_MODE, old_name, MODE_ALL)))
	_put_mode(cfg, SEC_MODE, old_name, MODE_ALL)
	return _save(cfg)


## Loeschen = in den Papierkorb (restore() holt sie zurueck).
static func delete(name: String) -> void:
	var cfg := _open()
	if cfg == null or not cfg.has_section_key(SEC, name):
		return
	cfg.set_value(SEC_TRASH, name, cfg.get_value(SEC, name, []))
	cfg.erase_section_key(SEC, name)
	_put_mode(cfg, SEC_TRASH_MODE, name, str(cfg.get_value(SEC_MODE, name, MODE_ALL)))
	_put_mode(cfg, SEC_MODE, name, MODE_ALL)
	_save(cfg)


## Namen im Papierkorb.
static func deleted_names() -> Array:
	var cfg := _read()
	if not cfg.has_section(SEC_TRASH):
		return []
	var names := Array(cfg.get_section_keys(SEC_TRASH))
	names.sort()
	return names


## Geloeschte Sammlung zurueckholen. Gibt es den Namen wieder, werden die Maps vereint.
static func restore(name: String) -> bool:
	var cfg := _open()
	if cfg == null or not cfg.has_section_key(SEC_TRASH, name):
		return false
	var v = cfg.get_value(SEC_TRASH, name, [])
	var maps: Array = (v as Array).duplicate() if v is Array else []
	var cur = cfg.get_value(SEC, name, [])
	if cur is Array:
		for f in cur:
			if not maps.has(f):
				maps.append(f)
	# Modus kommt mit zurueck; gibt es den Namen schon wieder, gilt dessen Modus.
	if not cfg.has_section_key(SEC, name):
		_put_mode(cfg, SEC_MODE, name, str(cfg.get_value(SEC_TRASH_MODE, name, MODE_ALL)))
	_put_mode(cfg, SEC_TRASH_MODE, name, MODE_ALL)
	cfg.set_value(SEC, name, maps)
	cfg.erase_section_key(SEC_TRASH, name)
	return _save(cfg)


static func maps_in(name: String) -> Array:
	var v = _read().get_value(SEC, name, [])
	return v if v is Array else []


static func contains(name: String, osz_file: String) -> bool:
	return maps_in(name).has(osz_file.get_file())


## Map rein/raus togglen. Liefert neuen Zustand (true = enthalten).
static func toggle(name: String, osz_file: String) -> bool:
	var f := osz_file.get_file()
	var cfg := _open()
	if cfg == null:
		return contains(name, osz_file)
	var v = cfg.get_value(SEC, name, [])
	var maps: Array = v if v is Array else []
	var now_in: bool
	if maps.has(f):
		maps.erase(f)
		now_in = false
	else:
		maps.append(f)
		now_in = true
	cfg.set_value(SEC, name, maps)
	_save(cfg)
	return now_in


## Alle Sammlungen, die diese Map enthalten.
static func collections_of(osz_file: String) -> Array:
	var result := []
	for name in list_names():
		if contains(name, osz_file):
			result.append(name)
	return result
