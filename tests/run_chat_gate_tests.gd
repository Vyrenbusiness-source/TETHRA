extends SceneTree

## Chat-Taste F ist in Rebound/Rally/Mania eine Spieltaste: in keiner der sechs
## Spielszenen darf das Chat-Overlay Eingaben sehen (Live-QA, docs/qa/live_qa.md).
##   Godot --headless --audio-driver Dummy --path . --script res://tests/run_chat_gate_tests.gd

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", label)


func _run() -> void:
	print("=== OMEN Chat-Sperre im Spiel ===")
	var gs: Node = root.get_node_or_null("GameSession")
	_check(gs != null and gs.has_method("chat_input_allowed"), "GameSession.chat_input_allowed fehlt")
	if gs != null and gs.has_method("chat_input_allowed"):
		for sc in ["mania_3d", "gameplay_3d", "orbit", "rally", "dirigent", "trace", "rebound"]:
			_check(not gs.chat_input_allowed("res://scenes/%s.tscn" % sc), "F in %s gesperrt" % sc)
		for sc in ["main_menu", "song_select", "mp_lobby"]:
			_check(gs.chat_input_allowed("res://scenes/%s.tscn" % sc), "F in %s erlaubt" % sc)
		_check(not gs.chat_input_allowed(""), "F im Szenenwechsel gesperrt")
		# Am echten Overlay: Spielszene aktiv -> Eingabe aus, offenes Overlay geht zu.
		if gs.get("chat") == null:
			gs.call("_make_chat", true)  # headless legt GameSession sonst kein Overlay an
		var chat = gs.get("chat")
		if _check_node(chat):
			var game := Control.new()
			game.scene_file_path = "res://scenes/rebound.tscn"
			root.add_child(game)
			current_scene = game
			chat.get("_panel").visible = true
			await process_frame
			await process_frame
			_check(not chat.is_processing_input(), "Overlay-Eingabe in Rebound aus")
			_check(not chat.is_open(), "offenes Overlay schliesst in Rebound")
			game.scene_file_path = "res://scenes/main_menu.tscn"
			await process_frame
			await process_frame
			_check(chat.is_processing_input(), "Overlay-Eingabe im Menue wieder an")
			current_scene = null
			game.free()
	print("=== %d ok, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check_node(chat) -> bool:
	_check(chat != null, "Chat-Overlay vorhanden ")
	return chat != null
