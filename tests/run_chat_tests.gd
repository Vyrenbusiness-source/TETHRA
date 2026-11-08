extends SceneTree

## Tests fuer den Ingame-Chat (Parsing, Map-/Score-Links, Ungelesen, Taste F, Replay).
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_chat_tests.gd

var _passed := 0
var _failed := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label)


func _initialize() -> void:
	print("=== TETHRA Chat-Tests ===")
	_parsing()
	_links()
	_scores()
	_unread()
	_key_rule()
	await _http()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _parsing() -> void:
	var convs := ChatApi.parse_conversations(JSON.stringify({"conversations": [
		{"id": "c1", "other": {"id": "u2", "username": "Mira", "country_code": "DE", "online": true},
			"last_message": "hi", "last_sender_id": "u2", "unread_count": 3, "updated_at": "2026-11-08T10:00:00Z"},
		{"id": "c2", "other": {"id": "u3", "username": "Jonas"}, "unread_count": 0},
	]}))
	_ok(convs.size() == 2 and convs[0].name == "Mira" and convs[0].online and convs[0].unread == 3,
		"Unterhaltungen geparst")
	_ok(not convs[1].online and convs[1].last_message == "", "fehlende Felder -> Standard")
	_ok(ChatApi.parse_conversations("kaputt").is_empty(), "kaputtes JSON -> leer")
	var r := ChatApi.parse_messages(JSON.stringify({"conversation_id": "c1", "messages": [
		{"id": "m1", "sender_id": "u2", "content": "a", "created_at": "2026-11-08T10:00:00Z"},
		{"id": "m2", "sender_id": "u1", "content": "b", "created_at": "2026-11-08T10:01:00Z",
			"reply_to": {"id": "m1", "sender_name": "Mira", "content": "a"}},
	]}))
	_ok(r.conversation_id == "c1" and r.messages.size() == 2, "Nachrichten geparst")
	_ok(r.messages[1].reply_to.sender_name == "Mira" and r.messages[0].reply_to.is_empty(), "reply_to")
	_ok(ChatApi.parse_send('{"conversation_id":"c9","message_id":"m5","created_at":"x"}').ok, "send ok")
	_ok(not ChatApi.parse_send('{"error":"nope"}').ok, "send Fehler")
	_ok(ChatApi.parse_unread('{"unread": 4}') == 4 and ChatApi.parse_unread("{}") == 0, "unread parse")
	_ok(ChatApi.parse_users('{"users":[{"id":"1","username":"Ann"}]}')[0].name == "Ann", "Nutzersuche")
	var merged := ChatApi.merge_messages(r.messages, [r.messages[1],
		{"id": "m0", "created_at": "2026-11-08T09:00:00Z"}])
	_ok(merged.size() == 3 and merged[0].id == "m0", "merge ohne Doppelte, sortiert")
	_ok(ChatApi.clean("x".repeat(2500)).length() == 2000, "max 2000 Zeichen")


func _links() -> void:
	var meta := {"md5": "0123456789abcdef0123456789abcdef", "set_id": 123, "beatmap_id": 456,
		"title": "Ein Titel & mehr", "artist": "Kuenstler", "version": "4K Hard", "stars": 3.5}
	var link := ChatApi.map_link(meta)
	_ok(link.begins_with("https://butzebot.com/tethra/map/0123456789abcdef0123456789abcdef?set=123&b=456&t="),
		"Link-Format")
	_ok(not link.contains(" ") and not link.contains("&mehr"), "Titel url-kodiert")
	var p := ChatApi.parse_map_link("Schau mal " + link + " gut?")
	_ok(p.set_id == 123 and p.beatmap_id == 456 and p.title == "Ein Titel & mehr", "Link erkannt, Titel dekodiert")
	_ok(p.version == "4K Hard" and absf(p.stars - 3.5) < 0.01 and p.artist == "Kuenstler", "Zusatzfelder")
	_ok(p.text == "Schau mal  gut?" or p.text.begins_with("Schau mal"), "Resttext")
	var basic := ChatApi.parse_map_link("https://butzebot.com/tethra/map/abc?set=9&b=8&t=Hallo%20Welt")
	_ok(basic.title == "Hallo Welt" and basic.md5 == "abc", "Link nur mit Pflichtfeldern")
	_ok(ChatApi.parse_map_link("https://example.com/x").is_empty(), "fremder Link ignoriert")
	_ok(ChatApi.parse_map_link("https://butzebot.com/tethra/map/abc").is_empty(), "ohne set -> keine Karte")


func _scores() -> void:
	var l := ChatApi.score_link(77)
	_ok(l == "https://butzebot.com/tethra/score/77", "Score-Link erzeugt")
	var p := ChatApi.parse_score_link("Mein Lauf " + l + " !")
	_ok(p.score_id == "77" and p.text.begins_with("Mein Lauf"), "Score-Link erkannt")
	_ok(ChatApi.parse_score_link("nichts").is_empty(), "kein Score-Link")
	var s := ChatApi.parse_score(JSON.stringify({"player": "Mira", "map": {"beatmap_md5": "m", "beatmapset_id": 5,
		"beatmap_id": 6, "title": "T", "difficulty": "D"}, "score": 1000, "accuracy": 98.5, "grade": "S",
		"max_combo": 300, "pp": 120.5, "mods": ["NF"], "mode": "mania", "has_replay": true}))
	_ok(s.player == "Mira" and s.set_id == 5 and s.has_replay and s.mods == ["NF"] and s.grade == "S",
		"Score geparst")
	var o := ChatApi.parse_score('{"score":{"player":{"username":"X"},"map":{"beatmapset_id":1},"orbit_points":9.5,"mode":"orbit"}}')
	_ok(o.player == "X" and absf(o.pp - 9.5) < 0.01 and not o.has_replay, "verpackt + orbit_points")
	_ok(ChatApi.parse_score("{}").is_empty(), "leerer Score -> {}")
	var data := {"meta": {"end_ms": 1000.0}, "events": [{"t": 10, "lane": 1, "down": true}, {"t": 50, "lane": 1, "down": false}]}
	var enc := ChatApi.encode_replay(data)
	var dec := ChatApi.decode_replay(enc)
	_ok(dec.events.size() == 2 and int(dec.events[0].t) == 10, "Replay gzip+base64 Roundtrip")
	_ok(ChatApi.decode_replay("%%%kaputt").is_empty() and ChatApi.decode_replay("").is_empty(), "kaputter Replay -> {}")
	_ok(ChatApi.replay_result(200, enc).status == "ok", "Replay roh ok")
	_ok(ChatApi.replay_result(200, JSON.stringify({"replay_content": enc})).status == "ok", "Replay in JSON ok")
	_ok(ChatApi.replay_result(404, "").status == "missing", "404 -> missing")
	_ok(ChatApi.replay_result(500, "").status == "error", "500 -> error")
	_ok(ChatApi.replay_result(200, "murks").status == "error", "Muell -> error")


func _unread() -> void:
	var convs := [{"unread": 2}, {"unread": 0}, {"unread": 5}]
	_ok(ChatApi.total_unread(convs) == 7, "Ungelesen-Summe")
	_ok(ChatApi.unread_text(0) == "" and ChatApi.unread_text(7) == "7" and ChatApi.unread_text(120) == "99+",
		"Ungelesen-Text")
	var api := ChatApi.new()
	var seen: Array = []
	api.unread_changed.connect(func(n): seen.append(n))
	api.set_unread(3)
	api.set_unread(3)
	api.set_unread(0)
	_ok(seen == [3, 0], "unread_changed nur bei Aenderung")
	api.free()


func _key_rule() -> void:
	var le := LineEdit.new()
	var btn := Button.new()
	_ok(ChatOverlay.key_allowed("res://scenes/main_menu.tscn", null), "F im Menue erlaubt")
	_ok(ChatOverlay.key_allowed("res://scenes/main_menu.tscn", btn), "F bei Button-Fokus erlaubt")
	_ok(not ChatOverlay.key_allowed("res://scenes/main_menu.tscn", le), "F bei Textfeld gesperrt")
	_ok(not ChatOverlay.key_allowed("res://scenes/mania_3d.tscn", null), "F im Gameplay gesperrt")
	_ok(not ChatOverlay.key_allowed("res://scenes/orbit.tscn", null), "F in Orbit gesperrt")
	le.free()
	btn.free()


func _http() -> void:
	var api := ChatApi.new()
	var online := OnlineApi.new()
	online.token = "tok"
	api.online = online
	var log: Array = []
	api.transport = func(method: String, url: String, headers: PackedStringArray, body: String, done: Callable):
		log.append([method, url, headers, body])
		if url.ends_with("/game/chat/unread"):
			done.call(200, '{"unread": 6}')
		elif url.ends_with("/replay"):
			done.call(404, "")
		elif url.contains("/game/chat/send/"):
			done.call(200, '{"conversation_id":"c1","message_id":"m1","created_at":"x"}')
		elif url.contains("/messages"):
			done.call(200, '{"conversation_id":"c1","messages":[]}')
		else:
			done.call(200, '{"conversations":[]}')
	root.add_child(api)
	api.refresh_unread()
	_ok(api.unread == 6, "Unread per Transport")
	var hdr: PackedStringArray = log[0][2]
	_ok(hdr.has("x-tethra-user-token: tok") and log[0][1].ends_with("/panel-api/tethra/game/chat/unread"),
		"Header und URL")
	var res: Array = []
	api.fetch_replay("5", func(r): res.append(r))
	_ok(res.size() == 1 and res[0].status == "missing", "fetch_replay 404 -> missing")
	var sent: Array = []
	api.send_to_user("Mira", "hi", "m0", func(ok, cid): sent.append([ok, cid]))
	_ok(sent == [[true, "c1"]] and JSON.parse_string(log.filter(func(e): return e[0] == "POST")[0][3]).reply_to_id == "m0",
		"Senden mit reply_to_id")
	online.token = ""
	var before := log.size()
	api.refresh_unread()
	_ok(log.size() == before, "abgemeldet: keine Anfrage")
	api.queue_free()
	online.free()
	await process_frame
