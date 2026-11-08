class_name OnlineApi
extends Node

## Online-Scores und Website-Anbindung (butzebot.com). Als Kind von GameSession
## angelegt (GameSession.online). Alles asynchron ueber HTTPRequest, nie blockierend.
## API_KEY leer = Online aus: jede Funktion meldet still "disabled", kein Netzverkehr.
## Fuer Tests: `transport` ersetzt das Netz (Fake-Antworten), cfg_path/queue_path
## zeigen auf Testdateien.

const BASE_URL := "https://butzebot.com/panel-api/tethra"
const API_KEY := ""
const PROFILE_URL := "https://butzebot.com/tethra/player/"
const CFG_PATH := "user://online.cfg"
const QUEUE_PATH := "user://online_queue.json"
const TIMEOUT_S := 15.0
const RETRY_S := 120.0
const QUEUE_MAX := 200
const LEADERBOARD_LIMIT := 50

## Zustandsaenderung (Anmeldung, Warteschlange, Update noetig).
signal state_changed

var api_key := API_KEY
var base_url := BASE_URL
var cfg_path := CFG_PATH
var queue_path := QUEUE_PATH
## Test-Hook: Callable(method, url, headers, body_text, done: Callable(code, text)).
var transport := Callable()

var token := ""
var user_id := ""
var username := ""
## true, sobald der Server 426 meldete (Client zu alt).
var update_required := false
## Zuletzt gemeldeter Submit-Status ("", "ok", "queued", "update", "error").
var last_status := ""

var _queue: Array = []
var _busy := false
var _retry_t := 0.0


func _ready() -> void:
	load_auth()
	load_queue()
	set_process(true)
	if enabled() and logged_in() and not _queue.is_empty():
		call_deferred("_pump")


func _process(delta: float) -> void:
	if _queue.is_empty() or _busy or update_required:
		return
	_retry_t += delta
	if _retry_t >= RETRY_S:
		_retry_t = 0.0
		_pump()


# --- Zustand -----------------------------------------------------------------

func enabled() -> bool:
	return api_key != ""


func logged_in() -> bool:
	return token != ""


func queue_size() -> int:
	return _queue.size()


static func profile_url(player: String) -> String:
	return PROFILE_URL + player.uri_encode()


func open_profile(player: String) -> void:
	if player.strip_edges() != "":
		OS.shell_open(profile_url(player.strip_edges()))


func load_auth() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return
	token = str(cfg.get_value("auth", "token", ""))
	user_id = str(cfg.get_value("auth", "user_id", ""))
	username = str(cfg.get_value("auth", "username", ""))


func _save_auth() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token)
	cfg.set_value("auth", "user_id", user_id)
	cfg.set_value("auth", "username", username)
	cfg.save(cfg_path)


func logout() -> void:
	token = ""
	user_id = ""
	username = ""
	_save_auth()
	state_changed.emit()


# --- Konto -------------------------------------------------------------------

## done: Callable(ok: bool, message: String)
func login(p_username: String, password: String, done: Callable = Callable()) -> void:
	if not enabled():
		_call(done, false, "disabled")
		return
	_send("POST", "/auth/login", {"username": p_username, "password": password},
		func(code: int, text: String):
			var r := parse_auth(code, text)
			if r.ok:
				_set_auth(r)
				_pump()
			_call(done, r.ok, str(r.message)))


func register(p_username: String, email: String, password: String, done: Callable = Callable()) -> void:
	if not enabled():
		_call(done, false, "disabled")
		return
	_send("POST", "/auth/register",
		{"username": p_username, "email": email, "password": password},
		func(code: int, text: String):
			_call(done, code >= 200 and code < 300, error_message(code, text)))


func verify(email: String, otp: String, done: Callable = Callable()) -> void:
	if not enabled():
		_call(done, false, "disabled")
		return
	_send("POST", "/auth/verify-email", {"email": email, "otp": otp},
		func(code: int, text: String):
			var ok := code >= 200 and code < 300
			# Manche Server melden gleich das Token mit.
			var r := parse_auth(code, text)
			if r.ok:
				_set_auth(r)
			_call(done, ok, error_message(code, text)))


func _set_auth(r: Dictionary) -> void:
	token = str(r.token)
	user_id = str(r.user_id)
	username = str(r.username)
	_save_auth()
	state_changed.emit()


## Antwort von /auth/login: {ok, token, user_id, username, message}.
static func parse_auth(code: int, text: String) -> Dictionary:
	var out := {"ok": false, "token": "", "user_id": "", "username": "", "message": ""}
	var d: Variant = JSON.parse_string(text)
	if code >= 200 and code < 300 and d is Dictionary and str(d.get("token", "")) != "":
		out.ok = true
		out.token = str(d.get("token"))
		out.user_id = str(d.get("userId", d.get("user_id", "")))
		out.username = str(d.get("username", ""))
		return out
	out.message = error_message(code, text)
	return out


## Lesbare Fehlermeldung aus HTTP-Code + JSON-Body ({error|message}).
static func error_message(code: int, text: String) -> String:
	if code >= 200 and code < 300:
		return ""
	var d: Variant = JSON.parse_string(text)
	if d is Dictionary:
		var m := str(d.get("error", d.get("message", "")))
		if m != "":
			return m
	if code <= 0:
		return "offline"
	return "HTTP %d" % code


# --- Score-Submit ------------------------------------------------------------

## Mod-Faktor aus einer Mod-Liste (["SV","NF"]) oder Dictionary.
static func mod_factor(mods: Variant) -> float:
	var d := {}
	if mods is Dictionary:
		d = mods
	elif mods is Array:
		for m in mods:
			d[str(m)] = true
	return ManiaCore.mod_multiplier(d)


static func client_version() -> String:
	var u: Variant = load("res://scripts/net/updater.gd")
	return str(u.CURRENT_VERSION) if u != null else ""


## Meta-Dictionary fuer eine Map: md5 der .osu, Metadaten, osu_b64 (Registrierung).
static func meta_from_beatmap(bm: Beatmap, osz_path: String, osu_filename: String,
		stars: float = -1.0) -> Dictionary:
	var bytes := OszImporter.read_file_bytes(osz_path, osu_filename)
	return {
		"md5": _md5_bytes(bytes),
		"osu_b64": Marshalls.raw_to_base64(bytes) if bytes.size() > 0 else "",
		"beatmap_id": int(bm.metadata.get("BeatmapID", 0)),
		"beatmapset_id": int(bm.metadata.get("BeatmapSetID", 0)),
		"difficulty": bm.version_name(),
		"artist": bm.artist(),
		"title": bm.title(),
		"creator": str(bm.metadata.get("Creator", "")),
		"length_ms": int(bm.duration_ms()),
		"total_notes": bm.hit_objects.size(),
		"stars": stars,
		"ranked": true,
	}


static func _md5_bytes(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(bytes)
	return h.finish().hex_encode()


## Body fuer POST /score. result = ManiaCore.stats() (+ "pp"), meta s. meta_from_beatmap.
## mode "mania" liefert pp, "orbit" liefert stars (result.stars bzw. meta.stars).
static func build_body(result: Dictionary, meta: Dictionary, mode: String = "mania") -> Dictionary:
	var mods: Array = result.get("mods", [])
	var factor := float(result.get("mod_mult", mod_factor(mods)))
	var body := {
		"mode": mode,
		"beatmap_md5": str(meta.get("md5", "")),
		"beatmap_id": int(meta.get("beatmap_id", 0)),
		"beatmapset_id": int(meta.get("beatmapset_id", 0)),
		"difficulty": str(meta.get("difficulty", "")),
		"artist": str(meta.get("artist", "")),
		"title": str(meta.get("title", "")),
		"creator": str(meta.get("creator", "")),
		"length_ms": int(meta.get("length_ms", 0)),
		"total_notes": int(meta.get("total_notes", 0)),
		"score": int(result.get("score", 0)),
		"mods": mods,
		"mod_mult": factor,
		"accuracy": float(result.get("accuracy", 0.0)),
		"grade": str(result.get("grade", "D")),
		"max_combo": int(result.get("max_combo", 0)),
		"count_max": int(result.get("n_max", result.get("count_max", 0))),
		"count_300": int(result.get("n300", result.get("count_300", 0))),
		"count_200": int(result.get("n200", result.get("count_200", 0))),
		"count_100": int(result.get("n100", result.get("count_100", 0))),
		"count_50": int(result.get("n50", result.get("count_50", 0))),
		"count_miss": int(result.get("n_miss", result.get("count_miss", 0))),
		"ranked": bool(meta.get("ranked", true)),
		"client_version": client_version(),
		"date": str(result.get("date", Time.get_datetime_string_from_system(true))),
	}
	if mode == "orbit":
		body["stars"] = float(result.get("stars", meta.get("stars", 0.0)))
	else:
		body["pp"] = maxf(float(result.get("pp", 0.0)), 0.0)
	return body


## Body fuer POST /beatmap/register.
static func build_register_body(meta: Dictionary, mode: String) -> Dictionary:
	return {
		"md5": str(meta.get("md5", "")),
		"osu_b64": str(meta.get("osu_b64", "")),
		"mode": mode,
		"beatmap_id": int(meta.get("beatmap_id", 0)),
		"beatmapset_id": int(meta.get("beatmapset_id", 0)),
		"difficulty": str(meta.get("difficulty", "")),
		"artist": str(meta.get("artist", "")),
		"title": str(meta.get("title", "")),
		"creator": str(meta.get("creator", "")),
		"length_ms": int(meta.get("length_ms", 0)),
		"total_notes": int(meta.get("total_notes", 0)),
	}


## Wertet eine Antwort von POST /score aus.
## kind: ok | unknown_map | update | auth | drop (Server lehnt ab, nie wieder senden) | retry.
static func classify_submit(code: int, text: String) -> Dictionary:
	var msg := error_message(code, text)
	if code >= 200 and code < 300:
		return {"kind": "ok", "message": ""}
	if code == 404 and msg.to_lower().contains("unknown map"):
		return {"kind": "unknown_map", "message": msg}
	if code == 426:
		return {"kind": "update", "message": msg}
	if code == 401 or code == 403:
		return {"kind": "auth", "message": msg}
	if code == 400 or code == 404 or code == 409 or code == 413 or code == 422:
		return {"kind": "drop", "message": msg}
	return {"kind": "retry", "message": msg}


## Nach jedem gewerteten Lauf. mode "mania" | "orbit". false = nichts gesendet
## (Online aus / nicht angemeldet / keine md5).
func submit(result: Dictionary, meta: Dictionary, mode: String = "mania") -> bool:
	if not enabled() or not logged_in() or str(meta.get("md5", "")) == "":
		return false
	var entry := {
		"body": build_body(result, meta, mode),
		"reg": build_register_body(meta, mode),
		"registered": false,
	}
	_queue.append(entry)
	while _queue.size() > QUEUE_MAX:
		_queue.pop_front()
	save_queue()
	last_status = "queued"
	state_changed.emit()
	_pump()
	return true


func _pump() -> void:
	if _busy or _queue.is_empty() or not enabled() or not logged_in() or update_required:
		return
	_busy = true
	_send_entry(_queue[0])


func _send_entry(entry: Dictionary) -> void:
	_send("POST", "/score", entry.body, func(code: int, text: String):
		_on_score_reply(entry, code, text))


func _on_score_reply(entry: Dictionary, code: int, text: String) -> void:
	var kind := str(classify_submit(code, text).kind)
	if kind == "ok":
		_finish_entry("ok")
	elif kind == "unknown_map":
		if bool(entry.get("registered", false)) or str(entry.reg.get("osu_b64", "")) == "":
			_finish_entry("error", true)
			return
		entry["registered"] = true
		_send("POST", "/beatmap/register", entry.reg, func(c2: int, _t2: String):
			if (c2 >= 200 and c2 < 300) or c2 == 409:
				_send_entry(entry)
			else:
				_finish_entry("error", true))
	elif kind == "update":
		update_required = true
		_finish_entry("update", true)
	elif kind == "drop":
		_finish_entry("error")
	else:
		_finish_entry("error", true)


## keep=true: Eintrag bleibt fuer spaeter in der Warteschlange, der Lauf stoppt.
func _finish_entry(status: String, keep: bool = false) -> void:
	_busy = false
	last_status = status
	if keep:
		save_queue()
		state_changed.emit()
		return
	if not _queue.is_empty():
		_queue.pop_front()
	save_queue()
	state_changed.emit()
	_pump()


func save_queue() -> void:
	var f := FileAccess.open(queue_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_queue))


func load_queue() -> void:
	_queue = []
	if not FileAccess.file_exists(queue_path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
	if d is Array:
		for e in d:
			if e is Dictionary and e.has("body") and e.has("reg"):
				_queue.append(e)


# --- Rangliste ---------------------------------------------------------------

## done: Callable(ok: bool, entries: Array, message: String)
func leaderboard(mode: String, md5: String, beatmap_id: int, done: Callable) -> void:
	if not enabled():
		done.call(false, [], "disabled")
		return
	var q := "/leaderboard?mode=%s&md5=%s&beatmap_id=%d&limit=%d" % [
		mode.uri_encode(), md5.uri_encode(), beatmap_id, LEADERBOARD_LIMIT]
	_send("GET", q, null, func(code: int, text: String):
		var r := parse_leaderboard(code, text)
		done.call(r.ok, r.entries, r.message))


static func parse_leaderboard(code: int, text: String) -> Dictionary:
	var out := {"ok": false, "entries": [], "message": ""}
	var d: Variant = JSON.parse_string(text)
	if code >= 200 and code < 300 and d is Dictionary and d.get("entries") is Array:
		out.ok = true
		for e in d.entries:
			if e is Dictionary:
				out.entries.append({
					"rank": int(e.get("rank", out.entries.size() + 1)),
					"player": str(e.get("player", "")),
					"score": int(e.get("score", 0)),
					"accuracy": float(e.get("accuracy", 0.0)),
					"grade": str(e.get("grade", "")),
					"max_combo": int(e.get("max_combo", 0)),
					"pp": float(e.get("pp", 0.0)),
					"mods": e.get("mods", []),
					"date": str(e.get("date", "")),
					"player_id": str(e.get("player_id", "")),
				})
		return out
	out.message = error_message(code, text)
	return out


# --- Transport ---------------------------------------------------------------

func headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"x-tethra-api-key: " + api_key,
		"x-tethra-user-token: " + token,
	])


func _call(cb: Callable, a: Variant, b: Variant) -> void:
	if cb.is_valid():
		cb.call(a, b)


## body null = kein Body (GET).
func _send(method: String, path: String, body: Variant, done: Callable) -> void:
	var text := "" if body == null else JSON.stringify(body)
	var url := base_url + path
	if transport.is_valid():
		transport.call(method, url, headers(), text, done)
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	add_child(req)
	req.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		done.call(code, data.get_string_from_utf8()))
	var m := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var err := req.request(url, headers(), m, text)
	if err != OK:
		req.queue_free()
		done.call(0, "")
