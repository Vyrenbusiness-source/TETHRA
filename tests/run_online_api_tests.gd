extends SceneTree

## Headless-Tests fuer OnlineApi (Task online-scores): Body-Aufbau, Queue,
## Antwort-Parsing, Submit-Ablauf (404 unknown map -> Register -> Retry, 426) mit
## Fake-Transport, ohne Netz.
## Ausfuehren:
##   Godot..._console.exe --headless --audio-driver Dummy --path . --script res://tests/run_online_api_tests.gd

const TMP_CFG := "user://test_tmp/online_test.cfg"
const TMP_Q := "user://test_tmp/online_queue_test.json"

var _failed := 0
var _done := false
var _log: Array = []
var _script: Array = []   # Antworten [code, text] in Reihenfolge


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


func _fake(method: String, url: String, headers: PackedStringArray, body: String, done: Callable) -> void:
	_log.append({"method": method, "url": url, "headers": headers, "body": body})
	var r: Array = _script.pop_front() if not _script.is_empty() else [200, "{}"]
	done.call(int(r[0]), str(r[1]))


func _api() -> OnlineApi:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_tmp"))
	DirAccess.remove_absolute(TMP_Q)
	DirAccess.remove_absolute(TMP_CFG)
	var a := OnlineApi.new()
	a.cfg_path = TMP_CFG
	a.queue_path = TMP_Q
	a.api_key = "k"
	a.token = "tok"
	a.transport = _fake
	_log.clear()
	return a


func _result() -> Dictionary:
	return {"n_max": 100, "n300": 20, "n200": 5, "n100": 3, "n50": 2, "n_miss": 1,
		"max_combo": 90, "accuracy": 0.97, "grade": "S", "score": 912345,
		"mods": ["SV", "NF"], "mod_mult": 0.55, "pp": 123.4}


func _meta() -> Dictionary:
	return {"md5": "abc123", "osu_b64": "QQ==", "beatmap_id": 7, "beatmapset_id": 3,
		"difficulty": "Hard", "artist": "A", "title": "T", "creator": "C",
		"length_ms": 120000, "total_notes": 131, "stars": 4.5, "ranked": true}


func _run() -> void:
	# --- Body
	var b := OnlineApi.build_body(_result(), _meta(), "mania")
	for k in ["mode", "beatmap_md5", "beatmap_id", "beatmapset_id", "difficulty", "artist",
			"title", "creator", "length_ms", "total_notes", "score", "mods", "mod_mult",
			"accuracy", "grade", "max_combo", "count_max", "count_300", "count_200",
			"count_100", "count_50", "count_miss", "pp", "ranked", "client_version", "date"]:
		_check(b.has(k), "Body hat " + k)
	_check(not b.has("stars"), "Mania: kein stars")
	_check(b.mode == "mania" and b.beatmap_md5 == "abc123", "mode/md5")
	_check(b.count_max == 100 and b.count_300 == 20 and b.count_miss == 1, "Zaehler")
	_check(b.total_notes == 131 and b.length_ms == 120000, "total_notes/length")
	_check(is_equal_approx(float(b.pp), 123.4), "pp")
	var o := OnlineApi.build_body(_result(), _meta(), "orbit")
	_check(o.mode == "orbit" and o.has("stars") and not o.has("pp"), "Orbit: stars statt pp")
	_check(is_equal_approx(float(o.stars), 4.5), "Orbit stars aus meta")
	_check(is_equal_approx(OnlineApi.mod_factor(["SV", "NF"]), 0.55), "Mod-Faktor SV+NF")
	_check(is_equal_approx(OnlineApi.mod_factor({"SV": true}), 1.1), "Mod-Faktor SV")
	_check(is_equal_approx(OnlineApi.mod_factor([]), 1.0), "Mod-Faktor leer")
	var r2 := _result()
	r2.erase("mod_mult")
	_check(is_equal_approx(float(OnlineApi.build_body(r2, _meta()).mod_mult), 0.55), "mod_mult aus Mods")
	var r3 := _result()
	r3["pp"] = -1.0
	_check(float(OnlineApi.build_body(r3, _meta()).pp) == 0.0, "pp nie negativ")
	_check(OnlineApi.profile_url("Max Mustermann") == "https://butzebot.com/tethra/player/Max%20Mustermann", "Profil-URL")

	# --- Parsing
	var lb_json := "{\"entries\":[{\"rank\":1,\"player\":\"Ann\",\"score\":900,\"accuracy\":0.99,\"grade\":\"SS\",\"max_combo\":50,\"pp\":10.5,\"mods\":[\"SV\"],\"date\":\"2026-01-01\",\"player_id\":\"u1\"}]}"
	var lb := OnlineApi.parse_leaderboard(200, lb_json)
	_check(lb.ok and lb.entries.size() == 1 and lb.entries[0].player == "Ann", "Leaderboard geparst")
	_check(lb.entries[0].rank == 1 and lb.entries[0].score == 900 and lb.entries[0].player_id == "u1", "Leaderboard-Felder")
	_check(not OnlineApi.parse_leaderboard(500, "x").ok, "Leaderboard 500")
	var unk := "{\"error\":\"unknown map\"}"
	_check(OnlineApi.classify_submit(200, "{}").kind == "ok", "200 ok")
	_check(OnlineApi.classify_submit(404, unk).kind == "unknown_map", "404 unknown map")
	_check(OnlineApi.classify_submit(404, "{\"error\":\"nope\"}").kind == "drop", "404 sonst drop")
	_check(OnlineApi.classify_submit(426, "{\"error\":\"update\"}").kind == "update", "426")
	_check(OnlineApi.classify_submit(401, "").kind == "auth", "401")
	_check(OnlineApi.classify_submit(503, "").kind == "retry", "503 retry")
	_check(OnlineApi.classify_submit(0, "").kind == "retry", "offline retry")
	var au := OnlineApi.parse_auth(200, "{\"token\":\"T\",\"userId\":\"9\",\"username\":\"Bob\"}")
	_check(au.ok and au.token == "T" and au.user_id == "9" and au.username == "Bob", "Auth geparst")
	_check(not OnlineApi.parse_auth(401, "{\"error\":\"bad login\"}").ok, "Auth Fehler")
	_check(OnlineApi.error_message(401, "{\"error\":\"bad login\"}") == "bad login", "Fehlertext")

	# --- Online aus
	var off := _api()
	off.api_key = ""
	_check(not off.submit(_result(), _meta()), "ohne Key: kein Submit")
	var got := []
	off.login("a", "b", func(ok, msg): got.append([ok, msg]))
	_check(got.size() == 1 and got[0][0] == false and _log.is_empty(), "ohne Key: still, kein Netz")
	off.free()
	var nolog := _api()
	nolog.token = ""
	_check(not nolog.submit(_result(), _meta()), "ohne Login: kein Submit")
	nolog.free()

	# --- Submit ok
	var a := _api()
	_script = [[200, "{}"]]
	_check(a.submit(_result(), _meta()), "Submit angenommen")
	_check(_log.size() == 1 and _log[0].url.ends_with("/score") and _log[0].method == "POST", "POST /score")
	var hs: PackedStringArray = _log[0].headers
	_check(hs.has("x-tethra-api-key: k") and hs.has("x-tethra-user-token: tok"), "Header")
	_check(a.queue_size() == 0 and a.last_status == "ok", "Queue leer nach ok")
	a.free()

	# --- 404 unknown map -> register -> retry
	a = _api()
	_script = [[404, unk], [200, "{}"], [200, "{}"]]
	a.submit(_result(), _meta())
	_check(_log.size() == 3, "3 Requests (score, register, score)")
	_check(_log[1].url.ends_with("/beatmap/register"), "Register")
	var rb: Dictionary = JSON.parse_string(_log[1].body)
	_check(rb.md5 == "abc123" and rb.osu_b64 == "QQ==" and rb.mode == "mania", "Register-Body")
	_check(a.queue_size() == 0 and a.last_status == "ok", "nach Retry ok")
	a.free()

	# --- 404 zweimal -> bleibt in Queue, kein Endlosloop
	a = _api()
	_script = [[404, unk], [200, "{}"], [404, unk]]
	a.submit(_result(), _meta())
	_check(_log.size() == 3 and a.queue_size() == 1, "Register nur einmal")
	a.free()

	# --- Offline -> Queue, dann spaeter senden, Queue persistiert
	a = _api()
	_script = [[0, ""]]
	a.submit(_result(), _meta())
	_check(a.queue_size() == 1 and a.last_status == "error", "Offline: bleibt in Queue")
	var b2 := OnlineApi.new()
	b2.queue_path = TMP_Q
	b2.cfg_path = TMP_CFG
	b2.load_queue()
	_check(b2.queue_size() == 1, "Queue geladen")
	var saved: Dictionary = b2._queue[0]
	_check(saved.body.beatmap_md5 == "abc123" and saved.reg.osu_b64 == "QQ==", "Queue-Inhalt")
	_script = [[200, "{}"]]
	_log.clear()
	a._pump()
	_check(a.queue_size() == 0 and _log.size() == 1, "Spaeter erneut gesendet")
	b2.free()
	a.free()

	# --- 426
	a = _api()
	_script = [[426, "{\"error\":\"update required\"}"]]
	a.submit(_result(), _meta())
	_check(a.update_required and a.last_status == "update" and a.queue_size() == 1, "426: Update noetig")
	_log.clear()
	a._pump()
	_check(_log.is_empty(), "426: kein weiterer Versuch")
	a.free()

	# --- Server lehnt ab (400) -> verwerfen
	a = _api()
	_script = [[400, "{\"error\":\"bad\"}"]]
	a.submit(_result(), _meta())
	_check(a.queue_size() == 0, "400 verworfen")
	a.free()

	# --- Login / Auth-Datei / Logout
	a = _api()
	a.token = ""
	_script = [[200, "{\"token\":\"T2\",\"userId\":\"5\",\"username\":\"Cy\"}"]]
	got.clear()
	a.login("Cy", "pw", func(ok, _msg): got.append(ok))
	_check(got == [true] and a.logged_in() and a.username == "Cy", "Login")
	_check(_log[0].url.ends_with("/auth/login") and JSON.parse_string(_log[0].body).username == "Cy", "Login-Request")
	var a2 := OnlineApi.new()
	a2.cfg_path = TMP_CFG
	a2.load_auth()
	_check(a2.token == "T2" and a2.username == "Cy", "Token in Datei")
	a.logout()
	a2.load_auth()
	_check(not a.logged_in() and a2.token == "", "Logout loescht Token")
	a2.free()
	_script = [[401, "{\"error\":\"bad login\"}"]]
	got.clear()
	a.login("x", "y", func(_ok, msg): got.append(msg))
	_check(got == ["bad login"] and not a.logged_in(), "Login-Fehler")

	# --- Register / Verify / Leaderboard-Aufruf
	_log.clear()
	_script = [[200, "{}"], [200, "{}"]]
	a.register("u", "e@x.de", "pw")
	a.verify("e@x.de", "123456")
	_check(_log[0].url.ends_with("/auth/register") and _log[1].url.ends_with("/auth/verify-email"), "Register/Verify-URLs")
	_check(JSON.parse_string(_log[1].body).otp == "123456", "Verify-Body")
	_log.clear()
	_script = [[200, "{\"entries\":[]}"]]
	var lbres := []
	a.leaderboard("mania", "abc", 5, func(ok, _e, _m): lbres.append(ok))
	_check(lbres == [true] and _log[0].method == "GET" and "mode=mania" in _log[0].url \
		and "md5=abc" in _log[0].url and "limit=50" in _log[0].url, "Leaderboard-Request")

	a.free()
	DirAccess.remove_absolute(TMP_Q)
	DirAccess.remove_absolute(TMP_CFG)
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)
