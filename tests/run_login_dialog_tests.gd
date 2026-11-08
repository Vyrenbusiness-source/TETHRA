extends SceneTree

## Headless-Tests fuer den Login-Dialog beim Spielstart (Task login-start):
## Wann er erscheint, Spaeter / Nicht mehr fragen, Fehlertexte, Erfolg -> Upload.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_login_dialog_tests.gd

const TMP_CFG := "user://test_tmp/login_dialog_test.cfg"
const TMP_Q := "user://test_tmp/login_dialog_queue.json"

var _failed := 0
var _done := false
var _script: Array = []
## Zur Laufzeit geladen: login_dialog.gd nutzt Autoloads (GameSession), die beim
## Kompilieren des Testskripts noch fehlen.
var LD: GDScript


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _fake(_method: String, _url: String, _headers: PackedStringArray, _body: String, done: Callable) -> void:
	var r: Array = _script.pop_front() if not _script.is_empty() else [200, "{}"]
	done.call(int(r[0]), str(r[1]))


func _api(logged: bool) -> OnlineApi:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_tmp"))
	DirAccess.remove_absolute(TMP_CFG)
	DirAccess.remove_absolute(TMP_Q)
	var a := OnlineApi.new()
	a.cfg_path = TMP_CFG
	a.queue_path = TMP_Q
	a.api_key = "k"
	a.token = "tok" if logged else ""
	a.transport = _fake
	return a


func _dialog(a: OnlineApi) -> Control:
	var d: Control = LD.new()
	d.api = a
	d.osz_provider = func() -> Dictionary: return {}
	root.add_child(d)
	return d


func _run() -> void:
	TranslationServer.set_locale("de")
	LD = load("res://scripts/ui/login_dialog.gd")
	print("=== Login-Dialog-Tests ===")
	var none := PackedStringArray()

	# --- Wann erscheint der Dialog
	LD.shown_this_run = false
	var a := _api(false)
	_check(LD.should_show(a, none, false), "nicht angemeldet -> Dialog")
	_check(not LD.should_show(a, none, true), "Headless -> kein Dialog")
	_check(not LD.should_show(a, PackedStringArray(["--shot-menu"]), false), "Shot-Lauf -> kein Dialog")
	_check(not LD.should_show(a, PackedStringArray(["--autoplay"]), false), "Test-Lauf -> kein Dialog")
	_check(not LD.should_show(null, none, false), "ohne OnlineApi -> kein Dialog")
	var logged := _api(true)
	_check(not LD.should_show(logged, none, false), "angemeldet -> kein Dialog")
	logged.free()
	a.api_key = ""
	_check(not LD.should_show(a, none, false), "Online aus -> kein Dialog")
	a.api_key = "k"

	# --- Spaeter: in diesem Lauf nicht mehr, naechster Start fragt wieder
	var d := _dialog(a)
	_check(LD.shown_this_run, "gezeigt -> fuer diesen Lauf gemerkt")
	_check(not LD.should_show(a, none, false), "zurueck ins Menue fragt nicht erneut")
	var res := []
	d.finished.connect(func(ok): res.append(ok))
	d.later()
	_check(res == [false], "Spaeter -> finished(false)")
	_check(not a.login_prompt_disabled(), "Spaeter ohne Haken speichert nichts")
	LD.shown_this_run = false   # naechster Spielstart
	_check(LD.should_show(a, none, false), "naechster Start fragt wieder")
	d.queue_free()

	# --- Nicht mehr fragen
	d = _dialog(a)
	d._never.button_pressed = true
	d.later()
	_check(a.login_prompt_disabled(), "Nicht mehr fragen -> online.cfg [prompt] never")
	LD.shown_this_run = false
	_check(not LD.should_show(a, none, false), "abgeschaltet -> auch beim naechsten Start kein Dialog")
	# Login/Logout ueberschreibt die Einstellung nicht.
	a.logout()
	_check(a.login_prompt_disabled(), "Abmelden behaelt [prompt]")
	a.set_login_prompt_disabled(false)
	d.queue_free()

	# --- Fehlertexte
	_check(LD.error_text("Invalid credentials") == "Benutzername oder Passwort falsch.", "falsches Passwort")
	_check(LD.error_text("HTTP 401").begins_with("Benutzername oder Passwort"), "401 ohne Text")
	_check(LD.error_text("email_not_verified").begins_with("E-Mail noch nicht bestätigt"), "E-Mail nicht bestaetigt")
	_check(LD.error_text("Email not confirmed").contains("Mail von TETHRA"), "Hinweis auf Mail")
	_check(LD.error_text("offline").begins_with("Server nicht erreichbar"), "offline")
	_check(LD.error_text("HTTP 502").begins_with("Server nicht erreichbar"), "5xx -> Server")
	_check(LD.error_text("HTTP 429").begins_with("Zu viele Versuche"), "429")
	_check(LD.error_text("seltsam").contains("seltsam"), "Unbekanntes bleibt lesbar")

	# --- Anmelden: Enter-Pfad mit falschem Passwort, dann Erfolg
	LD.shown_this_run = false
	d = _dialog(a)
	res.clear()
	d.finished.connect(func(ok): res.append(ok))
	d.submit()
	_check(d._msg.visible and d._msg.text == "Bitte Benutzername und Passwort eingeben.", "leere Felder -> Hinweis, kein Request")
	d._user.text = "Cy"
	d._pass.text = "falsch"
	_script = [[401, "{\"error\":\"Invalid credentials\"}"]]
	d._pass.text_submitted.emit(d._pass.text)
	_check(d._msg.text == "Benutzername oder Passwort falsch." and res.is_empty() and d._pass.text == "",
		"Enter -> Anmelden, 401 -> verstaendlicher Fehler, Passwort geleert")
	d._pass.text = "richtig"
	_script = [[200, "{\"token\":\"T\",\"userId\":\"9\",\"username\":\"Cy\"}"]]
	d.submit()
	_check(a.logged_in() and res == [true], "Erfolg -> angemeldet, finished(true)")
	_check(d._msg.text.contains("Cy"), "Erfolgs-Hinweis nennt den Namen")
	_check(a.backfill_auto_done(), "erster Login -> Upload alter Scores angestossen")
	_check(not LD.should_show(a, none, false), "angemeldet -> kein Dialog mehr")
	d.queue_free()
	a.free()

	_test_replay()
	_test_online_id()
	_test_avatar()

	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")


# --- Replay-Upload (replay_content) -------------------------------------------

var _bodies: Array = []
var _replies: Array = []


func _capture(_method: String, url: String, _headers: PackedStringArray, body: String, done: Callable) -> void:
	_bodies.append({"url": url, "body": JSON.parse_string(body) if body != "" else null})
	var r: Array = _replies.pop_front() if not _replies.is_empty() else [200, "{}"]
	done.call(int(r[0]), str(r[1]))


func _replay_json(score: int, date: String = "2026-11-08T12:00:00") -> String:
	return JSON.stringify({"meta": {"score": score, "date": date, "grade": "A"},
		"events": [{"t": 100, "lane": 0, "down": true}, {"t": 180, "lane": 0, "down": false}]})


func _test_replay() -> void:
	print("--- Replay-Upload")
	var txt := _replay_json(123456)
	var enc := OnlineApi.encode_replay(txt)
	_check(enc != "" and OnlineApi.decode_replay(enc) == txt, "gzip+base64 Roundtrip")
	var raw := Marshalls.base64_to_raw(enc)
	_check(raw.size() > 2 and raw[0] == 0x1F and raw[1] == 0x8B, "Inhalt ist gzip (1F 8B)")
	_check(OnlineApi.encode_replay("") == "", "leeres Replay -> nichts")
	_check(OnlineApi.encode_replay(txt, 8) == "", "ueber dem Limit -> weglassen")
	# Kaum komprimierbar: 4 MB Hex-Text -> gzip ~2 MB -> base64 deutlich ueber 2 MB.
	var big := Crypto.new().generate_random_bytes(2000000).hex_encode()
	_check(OnlineApi.encode_replay(big) == "", "Replay > 2 MB -> weglassen")
	_check(OnlineApi.REPLAY_MAX_BYTES == 2 * 1024 * 1024, "Limit 2 MB")

	_check(OnlineApi.replay_matches(txt, 123456), "Replay passt (Score)")
	_check(not OnlineApi.replay_matches(txt, 1), "anderer Score -> passt nicht")
	_check(OnlineApi.replay_matches(txt, 123456, "2026-11-08T12:00:03"), "Datum 3 s daneben -> passt")
	_check(not OnlineApi.replay_matches(txt, 123456, "2026-11-08T12:01:00"), "Datum 1 min daneben -> passt nicht")
	_check(not OnlineApi.replay_matches("{\"meta\":{\"score\":1},\"events\":[]}", 1), "ohne Events -> passt nicht")
	_check(not OnlineApi.replay_matches("kaputt", 1), "kaputtes JSON -> passt nicht")

	var a := _api(true)
	a.transport = _capture
	var asked: Array = []
	a.replay_provider = func(osz: String, ver: String, rmode: String) -> String:
		asked.append([osz, ver, rmode])
		return _replay_json(5000)
	var meta := {"md5": "abc", "difficulty": "Hard", "osz_path": "C:/maps/123 Test.osz",
		"total_notes": 10}
	_bodies.clear()
	_replies = [[200, "{\"score_id\": 1}"]]
	a.submit({"score": 5000, "accuracy": 0.9, "grade": "A"}, meta, "mania")
	var b: Dictionary = _bodies[0].body if _bodies.size() > 0 and _bodies[0].body is Dictionary else {}
	_check(OnlineApi.decode_replay(str(b.get("replay_content", ""))) == _replay_json(5000),
		"Mania-Score sendet replay_content (= Replay-Datei)")
	_check(asked.size() > 0 and asked[0] == ["C:/maps/123 Test.osz", "Hard", "mania"], "Mania liest das Mania-Replay")
	asked.clear()
	_bodies.clear()
	_replies = [[200, "{}"]]
	a.submit({"score": 5000, "accuracy": 0.9, "grade": "A", "stars": 3.0}, meta, "orbit")
	b = _bodies[0].body if _bodies.size() > 0 and _bodies[0].body is Dictionary else {}
	_check(b.has("replay_content") and asked.size() > 0 and asked[0][2] == ReplayStore.MODE_ORBIT_LAST,
		"Orbit-Score sendet den letzten Orbit-Lauf")
	_bodies.clear()
	_replies = [[200, "{}"]]
	a.submit({"score": 4999, "accuracy": 0.9, "grade": "A"}, meta, "mania")
	b = _bodies[0].body if _bodies.size() > 0 and _bodies[0].body is Dictionary else {}
	_check(not b.is_empty() and not b.has("replay_content"), "Replay passt nicht zum Score -> ohne Replay")

	# Alte Scores: nur wenn das Replay genau zu Score und Datum passt.
	a.bf_interval = 0.0
	a.bf_meta_provider = func(_p: String, _v: String) -> Dictionary:
		return {"md5": "m1", "total_notes": 10, "difficulty": "Hard"}
	a.replay_provider = func(_o: String, _v: String, _m: String) -> String:
		return _replay_json(5000, "2026-11-08T12:00:00")
	var entries := [
		{"mode": "mania", "osz_file": "1 A.osz", "version": "Hard", "score": 5000,
			"accuracy": 0.9, "grade": "A", "date": "2026-11-08T12:00:01"},
		{"mode": "mania", "osz_file": "2 B.osz", "version": "Hard", "score": 5000,
			"accuracy": 0.9, "grade": "A", "date": "2026-11-01T09:00:00"},
		{"mode": "mania", "osz_file": "3 C.osz", "version": "Hard", "score": 5000,
			"accuracy": 0.9, "grade": "A"},
	]
	_bodies.clear()
	_replies = [[200, "{}"], [200, "{}"], [200, "{}"]]
	a.start_backfill({"1 A.osz": "C:/m/1 A.osz", "2 B.osz": "C:/m/2 B.osz", "3 C.osz": "C:/m/3 C.osz"}, entries)
	var has: Array = []
	for x in _bodies:
		if x.body is Dictionary and str(x.url).ends_with("/score"):
			has.append((x.body as Dictionary).has("replay_content"))
	_check(has == [true, false, false], "Backfill: Replay nur bei passendem Datum (%s)" % str(has))
	a.free()


# --- Server-ID als online_id --------------------------------------------------

func _test_online_id() -> void:
	print("--- online_id")
	_check(OnlineApi.score_id_of({"score_id": 77.0}) == "77", "score_id (Zahl)")
	_check(OnlineApi.score_id_of({"score": {"id": "s-9"}}) == "s-9", "score.id")
	_check(OnlineApi.score_id_of({"ok": true}) == "", "ohne ID -> leer")
	_check(OnlineApi.classify_submit(201, "{\"score_id\": 12}").score_id == "12", "classify_submit liefert score_id")
	var osz := "C:/maps/987 OnlineId.osz"
	var res := {"score": 7000, "accuracy": 0.97, "grade": "S", "max_combo": 10}
	ScoreStore.submit(osz, "Hard", res)
	ScoreStore.log_play(osz, "Hard", "X - Y", res)
	var a := _api(true)
	a.transport = _capture
	a.replay_provider = func(_o: String, _v: String, _m: String) -> String: return ""
	_replies = [[200, "{\"score_id\": 4242, \"pp_source\": \"server\"}"]]
	a.submit(res, {"md5": "abc", "difficulty": "Hard", "osz_path": osz}, "mania")
	_check(str(ScoreStore.best(osz, "Hard").get("online_id", "")) == "4242", "Bestwert bekommt online_id")
	var hist: Array = ScoreStore.top_scores(osz, "Hard", 5)
	_check(hist.size() > 0 and str(hist[0].get("online_id", "")) == "4242", "Verlaufseintrag bekommt online_id")
	# Orbit-Sektion getrennt.
	ScoreStore.submit(osz, "Hard", res, "orbit")
	_replies = [[200, "{\"score_id\": 5}"]]
	a.submit(res, {"md5": "abc", "difficulty": "Hard", "osz_path": osz}, "orbit")
	_check(str(ScoreStore.best(osz, "Hard", "orbit").get("online_id", "")) == "5"
		and str(ScoreStore.best(osz, "Hard").get("online_id", "")) == "4242", "Orbit-Bestwert getrennt")
	_check(not ScoreStore.set_online_id(osz, "Hard", "mania", 1, "x"), "anderer Score -> kein Eintrag")
	a.free()


# --- Avatar -------------------------------------------------------------------

func _img_bytes(fmt: String, px: int = 4) -> PackedByteArray:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9))
	match fmt:
		"jpg": return img.save_jpg_to_buffer()
		"webp": return img.save_webp_to_buffer()
	return img.save_png_to_buffer()


func _test_avatar() -> void:
	print("--- Avatar")
	_check(not OnlineApi.avatar_cache_is_real(), "Testlauf nutzt nie den echten Avatar-Cache")
	_check(OnlineApi.image_ext(_img_bytes("png")) == "png" and OnlineApi.image_ext(_img_bytes("jpg")) == "jpg"
		and OnlineApi.image_ext(_img_bytes("webp")) == "webp", "Formate an den ersten Bytes")
	var tex := OnlineApi.texture_from_bytes(_img_bytes("png"))
	_check(tex != null and tex.get_width() == 4, "PNG-Bytes -> Textur")
	_check(OnlineApi.texture_from_bytes(_img_bytes("jpg")) != null, "JPG-Bytes -> Textur")
	_check(OnlineApi.texture_from_bytes("kein bild".to_utf8_buffer()) == null, "Muell -> keine Textur")
	var huge := OnlineApi.texture_from_bytes(_img_bytes("png", 600))
	_check(huge != null and huge.get_width() == OnlineApi.AVATAR_MAX_PX, "grosses Bild verkleinert")

	var a := _api(true)
	a.username = "Cy"
	a.avatar_cache = "user://test_tmp/login_dialog_avatar"
	a.clear_avatar_cache()
	var urls: Array = []
	var reply: Array = [200, _img_bytes("png")]
	a.raw_transport = func(_m: String, url: String, _h: PackedStringArray, done: Callable) -> void:
		urls.append(url)
		done.call(int(reply[0]), reply[1])
	var changed := [0]
	a.avatar_changed.connect(func(): changed[0] += 1)
	a.refresh_avatar()
	_check(urls.size() == 1 and str(urls[0]).ends_with("/player/Cy/avatar"), "GET /player/<name>/avatar")
	_check(a.avatar != null and changed[0] == 1, "Avatar geladen, Signal")
	_check(FileAccess.file_exists(a.avatar_cache + ".png"), "Cache user://avatar.png")
	_check(OnlineApi.display_avatar(a, null) == a.avatar, "Profil zeigt das Website-Avatar")
	reply.assign([200, _img_bytes("jpg")])
	a.refresh_avatar()
	_check(FileAccess.file_exists(a.avatar_cache + ".jpg") and not FileAccess.file_exists(a.avatar_cache + ".png"),
		"neues Format ersetzt den alten Cache")
	var b := _api(true)
	b.avatar_cache = a.avatar_cache
	b.load_cached_avatar()
	_check(b.avatar != null, "naechster Start: Avatar aus dem Cache")
	b.free()
	reply.assign([500, PackedByteArray()])
	a.refresh_avatar()
	_check(a.avatar != null and FileAccess.file_exists(a.avatar_cache + ".jpg"), "Serverfehler -> Cache bleibt")
	reply.assign([404, PackedByteArray()])
	a.refresh_avatar()
	_check(a.avatar == null and not FileAccess.file_exists(a.avatar_cache + ".jpg"), "404 -> kein Avatar, Cache weg")
	var local_tex := ImageTexture.new()
	_check(OnlineApi.display_avatar(a, local_tex) == local_tex and OnlineApi.display_avatar(a, null) == null,
		"ohne Website-Avatar: lokales Bild, sonst Initiale")
	reply.assign([200, _img_bytes("png")])
	a.refresh_avatar()
	a.logout()
	_check(a.avatar == null and not FileAccess.file_exists(a.avatar_cache + ".png"), "Abmelden -> Avatar und Cache weg")

	# Rangliste: Speicher-Cache je Spieler, eine Anfrage pro Name.
	a.token = "tok"
	urls.clear()
	reply.assign([200, _img_bytes("png")])
	var got: Array = []
	a.player_avatar("Mira", func(t): got.append(t))
	a.player_avatar("mira", func(t): got.append(t))
	_check(urls.size() == 1 and got.size() == 2 and got[0] != null, "zweiter Abruf aus dem Speicher")
	reply.assign([404, PackedByteArray()])
	a.player_avatar("Leer", func(t): got.append(t))
	_check(got.size() == 3 and got[2] == null, "404 -> Initiale")
	for i in 60:
		a.player_avatar("p%d" % i, func(_t): pass)
	_check(a.avatar_mem_size() == OnlineApi.AVATAR_MEM_MAX, "Speicher-Cache hoechstens 50 Spieler")
	a.clear_avatar_cache()
	a.free()
	quit(1 if _failed > 0 else 0)
