extends SceneTree

## Headless-Tests fuer AsyncLoad (scripts/core/async_load.gd): nie abgeholte
## Hintergrund-Ladevorgaenge liessen beim Beenden je Pfad ein Lade-Token liegen
## ("ObjectDB instance leaked at exit", RefCounted, Referenzzahl 0; Turbo-Spiellauf).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_async_load_tests.gd

const A := "res://shaders/glow_dot.gdshader"
const B := "res://shaders/hit_ring.gdshader"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)


func _st(p: String) -> int:
	return ResourceLoader.load_threaded_get_status(p)


func _run() -> void:
	print("=== OMEN AsyncLoad ===")
	_ok(AsyncLoad.request(A, "Shader") == OK and AsyncLoad.request(A, "Shader") == OK, "zweimal angefordert")
	_ok(AsyncLoad.request(B, "Shader") == OK, "zweiter Pfad angefordert")
	_ok(AsyncLoad.open_count() == 3, "3 offene Anforderungen (%d)" % AsyncLoad.open_count())
	_ok(AsyncLoad.fetch(A) is Shader, "fetch liefert die Resource")
	_ok(AsyncLoad.open_count() == 2 and _st(A) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"nach einem fetch: zweite Anforderung von A noch offen")
	AsyncLoad.drain()
	_ok(AsyncLoad.open_count() == 0, "drain: nichts mehr offen")
	_ok(_st(A) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE and _st(B) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"drain: Lade-Token freigegeben (Status INVALID)")
	AsyncLoad.drain()
	_ok(AsyncLoad.open_count() == 0, "zweites drain ohne Fehler")
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
