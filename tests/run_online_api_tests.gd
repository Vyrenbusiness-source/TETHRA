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
	_check(OnlineApi.classify_submit(200, "{}").kind == "ok", "200 ok")
	_check(OnlineApi.classify_submit(200, "{\"duplicate\":true}").duplicate, "duplicate = ok")
	_check(OnlineApi.classify_submit(200, "{\"pp_source\":\"client\"}").pp_source == "client", "pp_source")
	for c in ["score_exceeds_max", "counts_mismatch", "unknown_mod", "not_4k"]:
		var cr := OnlineApi.classify_submit(400, "{\"code\":\"%s\"}" % c)
		_check(cr.kind == "drop" and cr.code == c, "400 %s: drop" % c)
	_check(OnlineApi.classify_submit(429, "{\"code\":\"too_fast\"}").kind == "rate", "429 too_fast")
	_check(OnlineApi.classify_submit(404, "{\"error\":\"nope\"}").kind == "drop", "404 drop")
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

	# --- pp_source client -> by-md5 pruefen -> register (einmal)
	a = _api()
	_script = [[200, "{\"pp_source\":\"client\"}"], [200, "{\"has_osu\":false}"], [200, "{}"]]
	a.submit(_result(), _meta())
	_check(_log.size() == 3, "3 Requests (score, by-md5, register)")
	_check(_log[1].method == "GET" and _log[1].url.ends_with("/beatmap/by-md5/abc123"), "by-md5")
	_check(_log[2].url.ends_with("/beatmap/register"), "Register")
	var rb: Dictionary = JSON.parse_string(_log[2].body)
	_check(rb.beatmap_md5 == "abc123" and rb.osu_b64 == "QQ==" and rb.mode == "mania", "Register-Body")
	for k in ["mode", "beatmap_md5", "beatmap_id", "beatmapset_id", "artist", "title", "creator",
			"difficulty", "length_ms", "total_notes", "stars", "osu_b64"]:
		_check(rb.has(k), "Register hat " + k)
	_check(a.queue_size() == 0 and a.last_status == "ok", "nach Register ok")
	_log.clear()
	_script = [[200, "{\"pp_source\":\"client\"}"]]
	a.submit(_result(), _meta())
	_check(_log.size() == 1, "gleiche Map: nicht noch einmal registrieren")
	a.free()

	# --- has_osu true -> nichts registrieren
	a = _api()
	_script = [[200, "{\"pp_source\":\"client\"}"], [200, "{\"has_osu\":true}"]]
	a.submit(_result(), _meta())
	_check(_log.size() == 2 and a.queue_size() == 0, "has_osu: kein Register")
	a.free()

	# --- pp_source server -> kein Register; Orbit nie
	a = _api()
	_script = [[200, "{\"pp_source\":\"server\",\"is_new_best\":true}"]]
	a.submit(_result(), _meta())
	_check(_log.size() == 1, "pp_source server: nur Score")
	_log.clear()
	_script = [[200, "{\"pp_source\":\"client\"}"]]
	a.submit(_result(), _meta(), "orbit")
	_check(_log.size() == 1, "Orbit: kein Register")
	a.free()

	# --- 429 -> bleibt in Queue, spaeter erneut
	a = _api()
	_script = [[429, "{\"code\":\"too_fast\"}"]]
	a.submit(_result(), _meta())
	_check(a.queue_size() == 1 and a.last_code == "too_fast", "429: bleibt in Queue")
	_script = [[200, "{}"]]
	a._pump()
	_check(a.queue_size() == 0, "429: spaeter gesendet")
	a.free()

	# --- 401 beim Score -> abgemeldet
	a = _api()
	_script = [[401, "{}"]]
	a.submit(_result(), _meta())
	_check(not a.logged_in() and a.queue_size() == 1, "401: abgemeldet, Score bleibt")
	a.free()

	# --- 400 mit Code -> verworfen, kein Wiederholen
	a = _api()
	_script = [[400, "{\"code\":\"counts_mismatch\"}"]]
	a.submit(_result(), _meta())
	_check(a.queue_size() == 0 and a.last_code == "counts_mismatch", "400 counts_mismatch verworfen")
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

	# --- auth/me
	a.token = "tok"
	_log.clear()
	_script = [[200, "{\"user\":{\"username\":\"Neu\"}}"]]
	got.clear()
	a.check_auth(func(ok, _m): got.append(ok))
	_check(_log[0].method == "GET" and _log[0].url.ends_with("/auth/me"), "GET /auth/me")
	_check(got == [true] and a.logged_in() and a.username == "Neu" and a.auth_checked, "auth/me ok")
	_script = [[0, ""]]
	got.clear()
	a.check_auth(func(ok, _m): got.append(ok))
	_check(got == [true] and a.logged_in(), "auth/me offline: Token bleibt")
	_script = [[401, "{}"]]
	got.clear()
	a.check_auth(func(ok, _m): got.append(ok))
	_check(got == [false] and not a.logged_in(), "auth/me 401: abgemeldet")
	var a3 := OnlineApi.new()
	a3.cfg_path = TMP_CFG
	a3.load_auth()
	_check(a3.token == "", "401: Token-Datei geleert")
	a3.free()
	a.token = "tok"
	_check(OnlineApi.REGISTER_URL == "https://butzebot.com/tethra/register", "Register-URL (Website)")
	_check(not a.has_method("register") and not a.has_method("verify"), "keine In-Game-Registrierung")

	# --- Leaderboard-Aufruf
	_log.clear()
	_script = [[200, "{\"entries\":[]}"]]
	var lbres := []
	a.leaderboard("mania", "abc", 5, func(ok, _e, _m): lbres.append(ok))
	_check(lbres == [true] and _log[0].method == "GET" and "mode=mania" in _log[0].url \
		and "md5=abc" in _log[0].url and "limit=50" in _log[0].url \
		and "beatmap_id=5" in _log[0].url, "Leaderboard-Request")
	_log.clear()
	_script = [[200, "{\"entries\":[]}"]]
	a.leaderboard("orbit", "abc", 0, func(_ok, _e, _m): pass)
	_check(not ("beatmap_id" in _log[0].url), "beatmap_id nur wenn > 0")

	_backfill_tests()

	a.free()
	DirAccess.remove_absolute(TMP_Q)
	DirAccess.remove_absolute(TMP_CFG)
	print("FAILED: %d" % _failed if _failed > 0 else "ALL OK")
	quit(1 if _failed > 0 else 0)


# --- Backfill ------------------------------------------------------------------

func _entry(f: String, v: String, n: int, extra: Dictionary = {}) -> Dictionary:
	var e := {"osz_file": f, "version": v, "n_max": n - 2, "n300": 1, "n200": 0, "n100": 1,
		"n50": 0, "n_miss": 0, "score": 900000, "accuracy": 0.98, "grade": "S",
		"max_combo": n, "pp": 50.0, "mods": [], "mod_mult": 1.0, "unranked": false,
		"mode": "mania", "date": "2026-07-01T10:00:00"}
	e.merge(extra, true)
	return e


func _backfill_tests() -> void:
	var files := {"a.osz": "/x/a.osz", "b.osz": "/x/b.osz", "c.osz": "/x/c.osz"}
	var zero := {"n_max": 0, "n300": 0, "n200": 0, "n100": 0, "n_miss": 0}
	var entries := [
		_entry("a.osz", "Hard", 100),
		_entry("a.osz", "Easy", 50),
		_entry("b.osz", "Hard", 80, {"unranked": true}),
		_entry("b.osz", "Insane", 80, {"failed": true}),
		_entry("b.osz", "Fail", 80, {"grade": "F"}),
		_entry("c.osz", "Old", 60, zero),
		_entry("c.osz", "Orb", 60, {"mode": "orbit"}),
		_entry("zzz.osz", "Gone", 60),
		_entry("c.osz", "Ok", 60),
		_entry("a.osz", "Hard", 100),
	]
	var cands := OnlineApi.backfill_candidates(entries, [], files)
	var keys := []
	for c in cands:
		keys.append(c.key)
	_check(keys == ["a.osz|Hard", "a.osz|Easy", "c.osz|Ok"],
		"Auswahl: nur gueltige Mania-Bestwerte, keine Doppel (%s)" % str(keys))
	_check(OnlineApi.backfill_candidates(entries, ["a.osz|Hard"], files).size() == 2, "bereits hochgeladen faellt raus")

	var a := _api()
	a.bf_interval = 0.0
	a.bf_rate_wait = 0.0
	var notes := {"Hard": 100, "Easy": 49, "Ok": 60}   # Easy: Zahlen passen nicht
	a.bf_meta_provider = func(_p: String, v: String) -> Dictionary:
		var m := _meta()
		m["md5"] = "md5_" + v
		m["difficulty"] = v
		m["total_notes"] = int(notes.get(v, 0))
		return m
	_script = [[200, "{\"pp_source\":\"client\"}"], [200, "{\"has_osu\":false}"], [200, "{}"],
		[429, "{\"code\":\"too_fast\"}"], [200, "{\"success\":true}"]]
	var ticks := []
	a.backfill_changed.connect(func(): ticks.append(a.backfill_state().done))
	_check(a.start_backfill(files, entries), "Backfill startet")
	var st := a.backfill_state()
	_check(not st.running and st.state == "finished", "Backfill fertig")
	_check(st.total == 3 and st.done == 3 and st.sent == 2 and st.skipped == 1,
		"Fortschritt 3/3, 2 gesendet, 1 uebersprungen (%s)" % str(st))
	_check(ticks.has(1) and ticks.has(2) and ticks.has(3), "Fortschritt gemeldet")
	var scores := 0
	var first: Dictionary = {}
	var registered := false
	for l in _log:
		if l.url.ends_with("/score"):
			scores += 1
			if first.is_empty():
				first = JSON.parse_string(l.body)
		if l.url.ends_with("/beatmap/register"):
			registered = true
	_check(scores == 3, "Score-Requests: Hard, Ok (429), Ok erneut (%d)" % scores)
	_check(first.mode == "mania" and first.date == "2026-07-01T10:00:00" and first.beatmap_md5 == "md5_Hard",
		"Original-Datum + md5")
	_check(registered, "pp_source client -> Register im Backfill")
	var done := a.backfill_done_keys()
	_check(done.has("a.osz|Hard") and done.has("c.osz|Ok") and done.has("a.osz|Easy"), "Keys gemerkt")
	_log.clear()
	_check(not a.start_backfill(files, entries), "kein Doppel-Upload")
	_check(_log.is_empty(), "zweiter Lauf: kein Netz")
	_check(a.backfill_pending(files, entries) == 0, "pending 0")

	# Abbrechen mitten drin (echte Pause nach dem ersten Eintrag)
	a.free()
	a = _api()
	a.bf_interval = 5.0
	a.bf_meta_provider = func(_p: String, v: String) -> Dictionary:
		var m := _meta()
		m["md5"] = "m" + v
		m["total_notes"] = 100 if v == "Hard" else 50
		return m
	_script = [[200, "{}"], [200, "{}"]]
	a.start_backfill(files, entries.slice(0, 2))
	_check(a.backfill_running() and a.backfill_state().done == 1, "wartet nach dem ersten Eintrag")
	a.cancel_backfill()
	st = a.backfill_state()
	_check(not st.running and st.state == "cancelled" and _log.size() == 1, "abgebrochen")
	_check(a.backfill_done_keys() == ["a.osz|Hard"], "nur Gesendetes gemerkt")

	# Netzfehler: Lauf stoppt, nichts gemerkt
	a.free()
	a = _api()
	a.bf_interval = 0.0
	a.bf_meta_provider = func(_p: String, v: String) -> Dictionary:
		var m := _meta()
		m["md5"] = "m" + v
		m["total_notes"] = 100
		return m
	_script = [[0, ""]]
	a.start_backfill(files, entries.slice(0, 1))
	_check(a.backfill_state().state == "error" and a.backfill_done_keys().is_empty(), "Netzfehler: stoppt, nichts gemerkt")
	_script = [[400, "{\"code\":\"counts_mismatch\"}"]]
	a.start_backfill(files, entries.slice(0, 1))
	_check(a.backfill_state().state == "finished" and a.backfill_done_keys() == ["a.osz|Hard"], "400: erledigt")
	_check(not a.backfill_auto_done(), "Auto-Flag aus")
	a.set_backfill_auto_done()
	_check(a.backfill_auto_done() and a.backfill_done_keys() == ["a.osz|Hard"], "Auto-Flag gesetzt, Keys bleiben")
	a.free()
	var nl := _api()
	nl.token = ""
	_check(not nl.start_backfill(files, entries), "ohne Login kein Backfill")
	nl.free()
