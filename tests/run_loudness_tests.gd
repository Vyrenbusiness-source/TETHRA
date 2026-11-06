extends SceneTree

## Headless-Tests fuer SongLoudness.
##   Godot..._console.exe --headless --path . --script res://tests/run_loudness_tests.gd

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _init() -> void:
	# Formel: Ziel -11, RMS -15 -> +4 dB
	_check(is_equal_approx(SongLoudness.compute_gain_db(-15.0, -6.0), 4.0), "Gain-Formel +4 dB")
	_check(is_equal_approx(SongLoudness.compute_gain_db(-8.0, -3.0), -3.0), "Gain-Formel -3 dB")
	# Clamp
	_check(is_equal_approx(SongLoudness.compute_gain_db(-40.0, -30.0), 6.0), "Clamp oben +6")
	_check(is_equal_approx(SongLoudness.compute_gain_db(0.0, -30.0), -4.0), "Clamp unten -4")
	# Peak-Begrenzung: Peak+Gain <= -1
	var g := SongLoudness.compute_gain_db(-20.0, -2.0)
	_check(is_equal_approx(g, 1.0), "Peak-Begrenzung Gain 1 dB")
	_check(-2.0 + g <= -1.0 + 0.0001, "Peak+Gain <= -1 dBFS")
	# Cache-Roundtrip
	var path := "user://loudness_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SongLoudness.reset_cache_for_tests(path)
	var key := SongLoudness.make_key("C:/x/Song.osz", "audio.mp3")
	_check(key == "Song.osz|audio.mp3", "Key = osz-Name + Audio-Datei")
	_check(SongLoudness.gain_db_for(key) == 0.0, "Unbekannt = 0 dB")
	_check(not SongLoudness.has_key(key), "has_key false")
	SongLoudness.store(key, -3.5)
	SongLoudness.reset_cache_for_tests(path)
	_check(is_equal_approx(SongLoudness.gain_db_for(key), -3.5), "Cache Roundtrip")
	_check(is_equal_approx(SongLoudness.gain_db_for_osz("D:/y/Song.osz"), -3.5), "gain_db_for_osz")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failed > 0:
		print("FAILED: ", _failed)
		quit(1)
	else:
		print("ALL OK")
		quit(0)
