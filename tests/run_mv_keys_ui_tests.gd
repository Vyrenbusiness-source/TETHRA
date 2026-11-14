extends SceneTree

## Headless-Tests fuer Texte und Bedienung rund um Mania 5K-7K (Task fix-small2):
## Tutorial "Maps bekommen" nennt 4K bis 7K (de + en), Intro-Skip ueber Enter, wenn
## die Leertaste eine Spurtaste ist (5K, 7K). Laeuft mit Autoloads (Settings).
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_mv_keys_ui_tests.gd

var _passed := 0
var _failed := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _ok(cond: bool, label: String) -> bool:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		print("  [FAIL] " + label)
	return cond


func _run() -> void:
	print("=== OMEN 5K-7K-Oberflaeche ===")
	_test_tutorial_text()
	_test_skip_key()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## Bug: "Maps bekommen" sagte noch "nur 4K" (spielbar sind seit v1.42.0 4K bis 7K).
func _test_tutorial_text() -> void:
	print("- Tutorial: Maps bekommen nennt 4K bis 7K")
	var tut: Control = load("res://scripts/ui/tutorial.gd").new()
	tut.call("_build_pages")
	var body := ""
	for pg in tut.get("_pages"):
		if str(pg.get("title", "")) == "Maps bekommen":
			body = str(pg.body)
	tut.free()
	if not _ok(body != "", "Seite gefunden"):
		return
	_ok(not body.contains("Nur [b]4K[/b]") and not body.contains("nur [b]Ranked 4K"), "de: kein \"nur 4K\" mehr")
	_ok(body.contains("7K"), "de: nennt 7K")
	var old := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var en := TranslationServer.translate(body)
	TranslationServer.set_locale(old)
	_ok(en != body and en.contains("4K to 7K") and not en.contains("only [b]4K"), "en: uebersetzt, nennt 4K to 7K")


## Bug: 5K/7K legen die Leertaste auf die Mittelspur -> Intro nicht ueberspringbar.
## Jetzt: Enter (auch Ziffernblock) als zweite Skip-Taste, Hinweis nennt sie.
func _test_skip_key() -> void:
	print("- Intro-Skip-Taste bei Leertaste als Spurtaste")
	var st: Node = root.get_node_or_null("Settings")
	if not _ok(st != null, "Settings-Autoload"):
		return
	# Nur im Speicher, nie gespeichert: Standardbelegung fuer 4K und 7K.
	var old4: Array[int] = (st.get("key_lanes") as Array[int]).duplicate()
	var old_k: Dictionary = (st.get("key_lanes_k") as Dictionary).duplicate(true)
	st.set("key_lanes", ManiaKeys.default_keys(4))
	var kk: Dictionary = st.get("key_lanes_k")
	kk[7] = ManiaKeys.default_keys(7)
	var g: Node3D = load("res://scripts/gameplay3d/mania_3d.gd").new()
	var core: ManiaCore = g.get("core")
	core.columns = 4
	_ok(bool(g.call("_is_skip_key", KEY_SPACE)) and bool(g.call("_is_skip_key", KEY_ENTER)), "4K: Leertaste und Enter")
	_ok(str(g.call("_skip_hint")) == "Leertaste: Intro überspringen", "4K: Hinweis nennt Leertaste")
	core.columns = 7
	_ok(not bool(g.call("_is_skip_key", KEY_SPACE)), "7K: Leertaste ist Spurtaste, kein Skip")
	_ok(bool(g.call("_is_skip_key", KEY_ENTER)) and bool(g.call("_is_skip_key", KEY_KP_ENTER)), "7K: Enter und Ziffernblock-Enter")
	_ok(str(g.call("_skip_hint")) == "Enter: Intro überspringen", "7K: Hinweis nennt Enter")
	_ok(not bool(g.call("_is_skip_key", KEY_D)), "Spurtaste D ist kein Skip")
	var old := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_ok(TranslationServer.translate("Enter: Intro überspringen") == "Enter: skip intro", "en: Enter: skip intro")
	TranslationServer.set_locale(old)
	var ov: Control = load("res://scripts/ui/break_overlay.gd").new()
	root.add_child(ov)
	ov.call("show_break", 0.0, 8000.0, 500.0, true, "Enter: Intro überspringen")
	var hint: Label = ov.get("_hint")
	_ok(hint.visible and hint.text == "Enter: Intro überspringen", "Overlay zeigt Enter-Hinweis")
	ov.call("show_break", 0.0, 8000.0, 500.0, true)
	_ok(hint.text == "Leertaste: Intro überspringen", "Overlay ohne Text: Leertaste (Orbit usw.)")
	ov.free()
	g.free()
	st.set("key_lanes", old4)
	st.set("key_lanes_k", old_k)
