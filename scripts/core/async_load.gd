class_name AsyncLoad
extends RefCounted

## ResourceLoader.load_threaded_request/-get mit Buchfuehrung.
##
## Godot haelt je angefordertem Pfad ein Lade-Token (intern ein RefCounted) und gibt
## es erst bei load_threaded_get frei, einmal je Anforderung. Wird ein Ergebnis nie
## abgeholt (Browser verlassen, bevor das Vorladen fertig war; Welt-Textur, die die
## Szene nicht braucht), bleibt das Token bis zum Beenden liegen und Godot meldet
## "ObjectDB instance leaked at exit" (RefCounted, Referenzzahl 0).
## Darum: request()/fetch() statt der ResourceLoader-Aufrufe, drain() beim Beenden
## (GameSession._exit_tree) holt alles Offene ab. Nur Hauptthread.

## Pfad -> Zahl offener Anforderungen (jede braucht ein eigenes get).
static var _open := {}


static func request(path: String, type_hint: String = "", sub_threads: bool = false) -> Error:
	var err := ResourceLoader.load_threaded_request(path, type_hint, sub_threads)
	if err == OK:
		_open[path] = int(_open.get(path, 0)) + 1
	return err


## Ergebnis abholen (wartet, falls es noch laedt), wie ResourceLoader.load_threaded_get.
static func fetch(path: String) -> Resource:
	var n := int(_open.get(path, 0))
	if n <= 1:
		_open.erase(path)
	else:
		_open[path] = n - 1
	return ResourceLoader.load_threaded_get(path)


## Offene Anforderungen (Tests, Diagnose).
static func open_count() -> int:
	var n := 0
	for p in _open:
		n += int(_open[p])
	return n


## Alles noch nicht Abgeholte abholen und verwerfen (beim Beenden).
static func drain() -> void:
	for p in _open.keys():
		for i in int(_open[p]):
			if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				break
			ResourceLoader.load_threaded_get(p)
	_open.clear()
