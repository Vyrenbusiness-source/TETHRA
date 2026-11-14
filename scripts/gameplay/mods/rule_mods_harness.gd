class_name RuleModsHarness
extends RefCounted

## Bild-Harness der Regel-Mods (nur Debug-Flags, nie im normalen Spiel):
##
## Song-Browser: --rules-harness --map=<text> --diff=<text> --shot-out=<Praefix>
##   Klickt die Mods-Schalter wie ein Spieler (Mausereignisse auf die Knoepfe) und
##   fotografiert: _browser (aus), _browser_mines (Minen an: Liste "mania_mn"), _browser_sd
##   (SD an: No-Fail geht aus), _online_soon (Server ohne "board": Hinweis), _online_board
##   (Server mit "board": eigene Liste). Online laeuft ueber eine Fake-Antwort (kein Netz).
##   Danach Klick auf "Replay": das gespeicherte Replay laeuft im Spiel; Bilder _replay
##   (nach --rules-replay-at=<s>, Standard 6) und am Ende _results + _details. Die Zeile
##   "RULESHARNESS ..." nennt jeden Schritt (OK/FAIL), Ende mit quit(0) bzw. quit(1).
##   Ohne "--shot"-Flag: der 45-s-Shot-Watchdog greift nicht (override.cfg: 60 s).
##
## Lobby: --shot-rule-lobby --shot-out=<Praefix> (mp_lobby): Raum mit Krone, Klick auf
##   Sudden Death und Minen (_lobby_rules), Perfect (_lobby_pf), No-Fail (_lobby_nf),
##   Orbit-Raum ohne Regel-Mods (_lobby_orbit).

static var _fails := 0


## --auto-skip=<n>: Autoplay laesst Note n aus (Shots fuer Sudden Death/Perfect), -1 = keine.
static func auto_skip() -> int:
	return int(_arg("--auto-skip", "-1"))


static func _prefix(fallback: String) -> String:
	var out := ProjectSettings.globalize_path(fallback)
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			out = a.trim_prefix("--shot-out=")
	return out


static func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.trim_prefix(key + "=")
	return fallback


static func _check(cond: bool, what: String) -> void:
	if not cond:
		_fails += 1
	print("RULESHARNESS %s %s" % ["OK" if cond else "FAIL", what])


static func _shot(tree: SceneTree, tag: String, wait_s: float = 0.6) -> void:
	await tree.create_timer(wait_s).timeout
	await RenderingServer.frame_post_draw
	var path := "%s_%s.png" % [_prefix("user://rules"), tag]
	tree.root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT " + path)


## Echter Klick (Bewegung, Druck, Loslassen) in die Mitte eines Knopfes.
static func click(target: Control) -> void:
	var vp := target.get_viewport()
	var tree := target.get_tree()   # vor dem Klick: der Knopf kann danach weg sein (Replay)
	var pos := target.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev)
		await tree.process_frame


## Fake-Server fuer die Online-Liste: board = "" (alter Server) oder "mania_mn".
static func _fake_online(api: OnlineApi, board: String) -> void:
	api.token = "harness"   # nur im Speicher, nie gespeichert
	api.transport = func(_method: String, url: String, _hdr: PackedStringArray, _body: String, done: Callable):
		if not url.contains("/leaderboard"):
			done.call(404, "")
			return
		var entries := [
			{"rank": 1, "player": "Aria", "score": 912004, "accuracy": 0.9842, "grade": "S", "max_combo": 612},
			{"rank": 2, "player": "Kenji", "score": 874310, "accuracy": 0.9711, "grade": "S", "max_combo": 540},
		]
		var reply := {"entries": entries}
		if board != "":
			reply["board"] = board
		done.call(200, JSON.stringify(reply))


static func run_browser(ss: Control) -> void:
	var tree := ss.get_tree()
	_fails = 0
	await tree.create_timer(1.2).timeout
	var pk: Array = ss.call("_debug_pick")
	if pk.is_empty():
		_check(false, "keine Map fuer --map/--diff")
		tree.quit(1)
		return
	ss.call("_select_set", pk[0], pk[1])
	ss.set("_selected_diff", pk[1])
	ss.call("_update_info_panel")
	var btns: Dictionary = ss.get("_rule_mod_btns")
	var tag := ss.get("_lb_mode_tag") as Label
	_check(btns.size() == 3 and (btns["MN"] as Control).visible, "Schalter SD/PF/Mines sichtbar")
	await _shot(tree, "browser", 1.4)
	await click(btns["MN"])
	_check(bool((ss.get("_rule_mods") as Dictionary).get("MN", false)), "Klick Mines: an")
	_check(tag.text.contains(RuleMods.label("MN").to_upper()), "Liste gekennzeichnet: %s" % tag.text)
	await _shot(tree, "browser_mines")
	var nf_before := bool(ss.get("_nf_enabled"))
	if not nf_before:
		ss.call("_on_nf_toggled", true)   # No-Fail an, damit SD es sichtbar ausschaltet
	await click(btns["SD"])
	var rm: Dictionary = ss.get("_rule_mods")
	_check(bool(rm.get("SD", false)) and not bool(ss.get("_nf_enabled")), "Klick SD: an, No-Fail aus")
	var cm: Dictionary = ss.call("_current_mods")
	_check(RuleMods.has(cm, "SD") and RuleMods.has(cm, "MN") and int(cm.get("MN_v", 0)) == MineGen.VERSION,
			"Start-Mods: %s" % str(cm))
	await _shot(tree, "browser_sd")
	await click(btns["PF"])
	rm = ss.get("_rule_mods")
	_check(bool(rm.get("PF", false)) and not bool(rm.get("SD", false)), "Klick PF: SD geht aus")
	await click(btns["PF"])
	await click(btns["SD"])
	# Online: Server ohne "board" -> Hinweis statt Mania-Liste; mit "board" -> eigene Liste.
	var api: OnlineApi = GameSession.online
	var src: Array = ss.get("_lb_src_btns")
	if api != null and src.size() == 2:
		var keep_tr := api.transport
		var keep_tok := api.token
		_fake_online(api, "")
		await click(src[1])
		await tree.create_timer(0.3).timeout
		var box := ss.get("_lb_box") as Control
		_check(_box_text(box).contains(RuleMods.board_text("online_soon")), "Online ohne board: '%s'" % _box_text(box))
		await _shot(tree, "online_soon")
		_fake_online(api, RuleMods.MINES_SCORE_MODE)
		ss.call("_update_info_panel")
		await tree.create_timer(0.3).timeout
		_check(_box_text(box).contains("Aria"), "Online mit board: Liste da")
		await _shot(tree, "online_board")
		api.transport = keep_tr
		api.token = keep_tok
		await click(src[0])
	else:
		_check(false, "kein OnlineApi")
	# Replay des gespeicherten Minen-Laufs ueber den Replay-Knopf.
	var rb := ss.get("_replay_btn") as Button
	_check(rb != null and rb.visible, "Replay-Knopf sichtbar")
	if rb == null or not rb.visible:
		tree.quit(1)
		return
	await click(rb)
	await tree.create_timer(float(_arg("--rules-replay-at", "4"))).timeout
	var game := tree.current_scene
	_check(game != null and game.get("core") != null and GameSession.is_replay, "Replay laeuft im Spiel")
	var core: ManiaCore = game.get("core") if game != null else null
	_check(core != null and core.mines != null and core.mines.count() > 0,
			"Replay baut Minen: %d" % (core.mines.count() if core != null and core.mines != null else -1))
	await _shot(tree, "replay", 0.0)
	var rs: Control = null
	var waited := 0.0
	while rs == null and waited < 50.0:
		await tree.create_timer(0.5).timeout
		waited += 0.5
		if tree.current_scene != game:
			break
		var r = game.get("_results_screen")
		rs = r if r is Control and is_instance_valid(r) else null
	_check(rs != null, "Ergebnis nach dem Replay (%.1f s)" % waited)
	if rs != null:
		var st: Dictionary = rs.get("_stats")
		print("RULESHARNESS replay score=%d mines=%d mine_hits=%d n_miss=%d" % [int(st.get("score", 0)),
			int(st.get("mines", -1)), int(st.get("mine_hits", -1)), int(st.get("n_miss", -1))])
		await _shot(tree, "results", 2.2)
		rs.call("show_page", 1)
		await _shot(tree, "details", 0.6)
	print("RULESHARNESS DONE fails=%d" % _fails)
	tree.quit(1 if _fails > 0 else 0)


static func _box_text(box: Control) -> String:
	var parts: PackedStringArray = []
	if box == null:
		return ""
	for l in box.find_children("*", "Label", true, false):
		if not (l as Node).is_queued_for_deletion():
			parts.append((l as Label).text)
	for b in box.find_children("*", "LinkButton", true, false):
		if not (b as Node).is_queued_for_deletion():
			parts.append((b as LinkButton).text)
	return " | ".join(parts)


## Lobby-Raum mit Krone: Regel-Mods per Klick, Orbit-Raum ohne sie.
static func run_lobby(lobby: Control) -> void:
	var tree := lobby.get_tree()
	_fails = 0
	await tree.create_timer(0.8).timeout
	var who := ["Kenji", "Aria", "Mara"]
	Lobby.active = true
	Lobby.is_host = true
	Lobby.crown_id = 1
	Lobby.room_name = "Freitagsrunde"
	Lobby.players = {}
	for i in who.size():
		Lobby.players[i + 1] = Lobby._new_player(who[i])
		Lobby.players[i + 1].ready = true
	Lobby.sel_map = {"set_id": 1, "file": "", "version": "Insane", "title": "Neon Skyline",
		"artist": "Kairo", "stars": 4.2}
	Lobby.play_mode = "mania"
	Lobby.mods = Lobby._norm_mods({"NF": true})
	lobby.call("_show_room")
	lobby.call("_refresh_room")
	var btns: Dictionary = lobby.get("_mod_btns")
	_check(btns.has("SD") and btns.has("PF") and btns.has("MN") and (btns["MN"] as Control).is_visible_in_tree(),
			"Lobby: Schalter SD/PF/Mines sichtbar")
	await tree.create_timer(0.6).timeout
	await click(btns["SD"])
	await click(btns["MN"])
	_check(RuleMods.has(Lobby.mods, "SD") and RuleMods.has(Lobby.mods, "MN") and not bool(Lobby.mods.NF),
			"Lobby: SD + Mines an, No-Fail aus: %s" % str(Lobby.mods))
	_check(not bool(Lobby.players[2].ready), "Lobby: Mod-Wechsel setzt Bereit zurueck")
	await _shot(tree, "lobby_rules")
	await click(btns["PF"])
	_check(RuleMods.has(Lobby.mods, "PF") and not Lobby.mods.has("SD"), "Lobby: PF ersetzt SD")
	await _shot(tree, "lobby_pf")
	await click(btns["NF"])
	_check(bool(Lobby.mods.NF) and not Lobby.mods.has("PF") and RuleMods.has(Lobby.mods, "MN"),
			"Lobby: No-Fail schaltet PF aus, Minen bleiben: %s" % str(Lobby.mods))
	await _shot(tree, "lobby_nf")
	var gm := RuleMods.for_mode(Lobby.mods, "trace")
	_check(not gm.has("MN"), "Trace-Runde ohne Minen: %s" % str(gm))
	Lobby.play_mode = "orbit"
	lobby.call("_refresh_room")
	_check(not (btns["SD"] as Control).is_visible_in_tree(), "Orbit-Raum: Regel-Mods ausgeblendet")
	await _shot(tree, "lobby_orbit")
	Lobby.set_meta("harness", true)
	Lobby._reset()
	print("RULESHARNESS DONE fails=%d" % _fails)
	tree.quit(1 if _fails > 0 else 0)
