extends SceneTree

## Tests fuer das Orbit-Rating (ScoreStore.orbit_points / orbit_rating_of /
## mode_stats("orbit")). Formel: docs/modes/orbit.md "Orbit-Rating".
## Laeuft auf einer eigenen Test-Datei (ScoreStore.PATH unter --script).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_orbit_rating_tests.gd

const O := ScoreStore.MODE_ORBIT
var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-4


func _init() -> void:
	print("=== TETHRA Orbit-Rating-Tests ===")
	_test_points()
	_test_weighting()
	_test_store()
	print("=== %s ===" % ("ALLE OK" if _failed == 0 else "%d FEHLER" % _failed))
	quit(1 if _failed > 0 else 0)


func _test_points() -> void:
	# 4 * Sterne^2 * acc^4
	_check(_near(ScoreStore.orbit_points({ "stars": 5.0, "accuracy": 1.0 }), 100.0), "5 Sterne, 100 % = 100")
	_check(_near(ScoreStore.orbit_points({ "stars": 3.0, "accuracy": 1.0 }), 36.0), "3 Sterne, 100 % = 36")
	_check(_near(ScoreStore.orbit_points({ "stars": 6.0, "accuracy": 0.9 }), 4.0 * 36.0 * pow(0.9, 4.0)), "6 Sterne, 90 %")
	_check(_near(ScoreStore.orbit_points({ "accuracy": 0.97 }), 100.0 * pow(0.97, 4.0)), "ohne Sterne: 5 Sterne (= 100 * acc^4)")
	_check(_near(ScoreStore.orbit_points({ "stars": 0.0, "accuracy": 1.0 }), 0.0), "0 Sterne = 0")
	_check(_near(ScoreStore.orbit_points({ "stars": 99.0, "accuracy": 1.0 }), 4.0 * 225.0), "Sterne gekappt bei 15")
	_check(_near(ScoreStore.orbit_points({ "stars": 5.0, "accuracy": 1.4 }), 100.0), "acc gekappt bei 1")
	_check(ScoreStore.orbit_points({ "stars": 5.0, "accuracy": 1.0, "failed": true }) == 0.0, "Fail = 0")
	_check(ScoreStore.orbit_points({ "stars": 5.0, "accuracy": 1.0, "unranked": true }) == 0.0, "ungewertet = 0")
	_check(ScoreStore.orbit_points({}) == 0.0, "leer = 0")
	# Mehr Sterne schlagen mehr Genauigkeit erst ab deutlichem Abstand.
	_check(ScoreStore.orbit_points({ "stars": 6.0, "accuracy": 0.95 }) > ScoreStore.orbit_points({ "stars": 5.0, "accuracy": 1.0 }),
			"6 Sterne 95 % > 5 Sterne 100 %")


func _test_weighting() -> void:
	_check(ScoreStore.orbit_rating_of([]) == 0.0, "keine Laeufe = 0")
	_check(_near(ScoreStore.orbit_rating_of([100.0]), 100.0), "ein Lauf zaehlt voll")
	_check(_near(ScoreStore.orbit_rating_of([50.0, 100.0, 80.0]), 100.0 + 80.0 * 0.95 + 50.0 * 0.9025),
			"absteigend sortiert, 0,95^i")
	_check(_near(ScoreStore.orbit_rating_of([100.0, 0.0, -3.0]), 100.0), "0 und negativ zaehlen nicht")
	var many: Array = []
	for i in 200:
		many.append(100.0)
	_check(ScoreStore.orbit_rating_of(many) < 100.0 / (1.0 - 0.95), "Summe bleibt unter 20 x Bestwert")


func _test_store() -> void:
	if FileAccess.file_exists(ScoreStore.PATH):
		DirAccess.remove_absolute(ScoreStore.PATH)
	ScoreStore.submit("r1.osz", "A", { "score": 900000, "grade": "S", "accuracy": 1.0, "stars": 5.0 }, O)
	ScoreStore.submit("r2.osz", "B", { "score": 800000, "grade": "A", "accuracy": 0.9, "stars": 4.0 }, O)
	ScoreStore.submit("r3.osz", "C", { "score": 999999, "grade": "SS", "accuracy": 1.0, "stars": 8.0, "failed": true }, O)
	ScoreStore.submit("m1.osz", "M", { "score": 1000, "grade": "S", "accuracy": 1.0, "pp": 123.0 })
	_check(_near(float(ScoreStore.best("r1.osz", "A", O).get("stars", -1.0)), 5.0), "Sterne im Bestwert gespeichert")
	_check(not ScoreStore.best("m1.osz", "M").has("stars"), "Mania-Eintrag ohne Orbit-Sterne")
	var p2 := 4.0 * 16.0 * pow(0.9, 4.0)
	var want := 100.0 + p2 * 0.95
	_check(_near(ScoreStore.orbit_rating(), want), "Profil-Rating aus Orbit-Bestwerten (Fail zaehlt nicht)")
	_check(_near(float(ScoreStore.mode_stats(O).rating), want), "mode_stats(orbit).rating = orbit_rating")
	_check(int(ScoreStore.mode_stats(O).plays) == 3, "Orbit-Spiele inkl. Fail")
	_check(_near(ScoreStore.profile_pp(), 123.0), "Mania-pp unveraendert")
	# Besserer Lauf derselben Map ersetzt den alten Punktwert.
	ScoreStore.submit("r2.osz", "B", { "score": 850000, "grade": "S", "accuracy": 1.0, "stars": 4.0 }, O)
	_check(_near(ScoreStore.orbit_rating(), 100.0 + 64.0 * 0.95), "neuer Bestwert ersetzt alten")
	DirAccess.remove_absolute(ScoreStore.PATH)
