class_name OnlineApi
extends Node

## Online-Scores und Website-Anbindung (butzebot.com). Als Kind von GameSession
## angelegt (GameSession.online). Alles asynchron ueber HTTPRequest, nie blockierend.
## API_KEY leer = Online aus: jede Funktion meldet still "disabled", kein Netzverkehr.
## Fuer Tests: `transport` ersetzt das Netz (Fake-Antworten), cfg_path/queue_path
## zeigen auf Testdateien.

const BASE_URL := "https://butzebot.com/panel-api/tethra"
const API_KEY := "70bab2e56a48e488abad5285057e6bca10815e6101f2cddc"  # nicht geheim (Open Source), Schutz = Spieler-Token + Server-Regeln
const PROFILE_URL := "https://butzebot.com/tethra/player/"
## Registrierung NUR auf der Website (im Spiel nur Login).
const REGISTER_URL := "https://butzebot.com/tethra/register"
const CFG_PATH := "user://online.cfg"
const QUEUE_PATH := "user://online_queue.json"
const TIMEOUT_S := 15.0
const RETRY_S := 120.0
const QUEUE_MAX := 200
const LEADERBOARD_LIMIT := 50
## Alte Scores: Pause zwischen zwei Uploads und nach 429.
const BACKFILL_INTERVAL_S := 1.0
const BACKFILL_RATE_WAIT_S := 10.0

## Zustandsaenderung (Anmeldung, Warteschlange, Update noetig).
signal state_changed
## Fortschritt/Ende des Alte-Scores-Uploads.
signal backfill_changed

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

## Test-Hook fuer den Alte-Scores-Upload: Callable(osz_path, version) -> meta (synchron).
var bf_meta_provider := Callable()
var bf_interval := BACKFILL_INTERVAL_S
var bf_rate_wait := BACKFILL_RATE_WAIT_S
## Letzter Fehlercode des Servers (z. B. "counts_mismatch"), sonst "".
var last_code := ""
## true, sobald GET /auth/me die Anmeldung bestaetigt hat.
var auth_checked := false

var _queue: Array = []
var _busy := false
var _retry_t := 0.0
var _registered_md5: Dictionary = {}
var _bf_in_flight := false
## Backfill-Lauf: {running, cancel, list, idx, total, done, sent, skipped, failed, state,
## wait, task, out}
var _bf := {"running": false, "total": 0, "done": 0, "sent": 0, "skipped": 0,
	"state": ""}


func _ready() -> void:
	load_auth()
	load_queue()
	set_process(true)
	if enabled() and logged_in():
		call_deferred("check_auth")


func _process(delta: float) -> void:
	_bf_process(delta)
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


func open_register() -> void:
	OS.shell_open(REGISTER_URL)


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


## Prueft das gespeicherte Token (GET /auth/me). 401 -> abgemeldet.
## done: Callable(ok: bool, message: String); bei Netzfehler ok=true (Token bleibt).
func check_auth(done: Callable = Callable()) -> void:
	if not enabled() or not logged_in():
		_call(done, false, "")
		return
	_send("GET", "/auth/me", null, func(code: int, text: String):
		if code == 401:
			logout()
			_call(done, false, "401")
			return
		if code >= 200 and code < 300:
			auth_checked = true
			var d: Variant = JSON.parse_string(text)
			if d is Dictionary:
				var u: Dictionary = d.get("user", d)
				var nm := str(u.get("username", ""))
				if nm != "" and nm != username:
					username = nm
					_save_auth()
					state_changed.emit()
			_pump()
		_call(done, true, ""))


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
		var m := str(d.get("code", d.get("error", d.get("message", ""))))
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
		"mode": mode,
		"beatmap_md5": str(meta.get("md5", "")),
		"osu_b64": str(meta.get("osu_b64", "")),
		"beatmap_id": int(meta.get("beatmap_id", 0)),
		"beatmapset_id": int(meta.get("beatmapset_id", 0)),
		"difficulty": str(meta.get("difficulty", "")),
		"artist": str(meta.get("artist", "")),
		"title": str(meta.get("title", "")),
		"creator": str(meta.get("creator", "")),
		"length_ms": int(meta.get("length_ms", 0)),
		"total_notes": int(meta.get("total_notes", 0)),
		"stars": maxf(float(meta.get("stars", 0.0)), 0.0),
	}


## Wertet eine Antwort von POST /score aus.
## kind: ok | update (426) | auth (401) | rate (429, spaeter erneut) | drop (Server lehnt
## ab, nie wieder senden) | retry (Netz/Serverfehler). "code" = Fehlercode des Servers.
## ok enthaelt "pp_source" und "duplicate".
static func classify_submit(code: int, text: String) -> Dictionary:
	var msg := error_message(code, text)
	var d: Variant = JSON.parse_string(text)
	var dd: Dictionary = d if d is Dictionary else {}
	if code >= 200 and code < 300:
		return {"kind": "ok", "message": "", "code": "",
			"pp_source": str(dd.get("pp_source", "")), "duplicate": bool(dd.get("duplicate", false))}
	if code == 426:
		return {"kind": "update", "message": msg, "code": msg}
	if code == 401:
		return {"kind": "auth", "message": msg, "code": msg}
	if code == 429:
		return {"kind": "rate", "message": msg, "code": msg}
	if code >= 400 and code < 500:
		return {"kind": "drop", "message": msg, "code": msg}
	return {"kind": "retry", "message": msg, "code": msg}


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
	var r := classify_submit(code, text)
	var kind := str(r.kind)
	last_code = str(r.code)
	if kind == "ok":
		var md5 := str(entry.reg.get("beatmap_md5", ""))
		if str(entry.body.get("mode", "")) == "mania" and str(r.pp_source) == "client" 				and md5 != "" and not _registered_md5.has(md5):
			_register_map(entry.reg, func(): _finish_entry("ok"))
		else:
			_finish_entry("ok")
	elif kind == "update":
		update_required = true
		_finish_entry("update", true)
	elif kind == "auth":
		_busy = false
		last_status = "error"
		logout()
	elif kind == "rate":
		_finish_entry("error", true)
	elif kind == "drop":
		_finish_entry("error")
	else:
		_finish_entry("error", true)


## Server kennt die Map nur per Client-pp: einmal Metadaten + .osu schicken
## (vorher GET /beatmap/by-md5: has_osu true -> nichts tun). done: Callable().
func _register_map(reg: Dictionary, done: Callable) -> void:
	var md5 := str(reg.get("beatmap_md5", ""))
	_registered_md5[md5] = true
	_send("GET", "/beatmap/by-md5/" + md5.uri_encode(), null, func(c1: int, t1: String):
		var d: Variant = JSON.parse_string(t1)
		var has_osu: bool = c1 >= 200 and c1 < 300 and d is Dictionary and bool(d.get("has_osu", false))
		if has_osu or str(reg.get("osu_b64", "")) == "":
			done.call()
			return
		_send("POST", "/beatmap/register", reg, func(c2: int, _t2: String):
			if c2 != 200 and c2 != 201 and c2 != 409 and c2 != 0 and c2 < 500:
				pass   # Server lehnt ab: nicht wiederholen
			elif c2 == 0 or c2 >= 500:
				_registered_md5.erase(md5)   # spaeter nochmal versuchen
			done.call()))


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


# --- Alte Scores hochladen ---------------------------------------------------
## Nur Mania-Bestwerte (Orbit-Bestwerte nutzen alte Orbit-Regeln und werden nie
## hochgeladen). Langsam (1 Request/s), abbrechbar, hochgeladene Keys stehen in
## cfg_path (Sektion backfill) und werden nie doppelt gesendet.

static func backfill_key(osz_file: String, version: String) -> String:
	return "%s|%s" % [osz_file.get_file(), version]


## Summe der Trefferzahlen eines ScoreStore-Eintrags.
static func entry_count_sum(e: Dictionary) -> int:
	var t := 0
	for k in ["n_max", "n300", "n200", "n100", "n50", "n_miss"]:
		t += maxi(int(e.get(k, 0)), 0)
	return t


## Vorauswahl aus ScoreStore.best_plays(): nur Mania, nicht unranked/failed, mit
## Trefferzahlen, noch nicht hochgeladen, .osz vorhanden (osz_files: Dateiname -> Pfad).
## Ergebnis: [{key, osz_file, osz_path, version, entry}].
static func backfill_candidates(entries: Array, done_keys: Array, osz_files: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for e in entries:
		if not (e is Dictionary):
			continue
		if not str(e.get("mode", "mania")) in ["mania", ""]:
			continue
		if bool(e.get("unranked", false)) or bool(e.get("failed", false)) or str(e.get("grade", "")) == "F":
			continue
		if entry_count_sum(e) <= 0:
			continue
		var f := str(e.get("osz_file", "")).get_file()
		var v := str(e.get("version", ""))
		var key := backfill_key(f, v)
		if done_keys.has(key) or seen.has(key) or not osz_files.has(f):
			continue
		seen[key] = true
		out.append({"key": key, "osz_file": f, "osz_path": str(osz_files[f]),
			"version": v, "entry": e})
	return out


## Meta der Map fuer den Upload (Thread-tauglich): meta_from_beatmap oder {}.
static func backfill_meta(osz_path: String, version: String) -> Dictionary:
	var imp := OszImporter.import(osz_path)
	if not bool(imp.get("ok", false)):
		return {}
	for d in imp.difficulties:
		var bm: Beatmap = d.beatmap
		if bm.version_name() != version:
			continue
		if int(bm.general.get("Mode", 0)) != 3 or int(float(bm.difficulty.get("CircleSize", 4))) != 4:
			return {}
		return meta_from_beatmap(bm, osz_path, str(d.osu_filename))
	return {}


func _bf_job(osz_path: String, version: String, out: Dictionary) -> void:
	out["meta"] = backfill_meta(osz_path, version)


func backfill_done_keys() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return []
	var v: Variant = cfg.get_value("backfill", "done", [])
	return (v as Array).duplicate() if v is Array else []


func _bf_mark(key: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	var keys: Array = []
	var v: Variant = cfg.get_value("backfill", "done", [])
	if v is Array:
		keys = v
	if not keys.has(key):
		keys.append(key)
	cfg.set_value("backfill", "done", keys)
	cfg.save(cfg_path)


## true, wenn der automatische Upload nach dem ersten Login schon lief.
func backfill_auto_done() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(cfg_path) == OK and bool(cfg.get_value("backfill", "auto_done", false))


func set_backfill_auto_done() -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	cfg.set_value("backfill", "auto_done", true)
	cfg.save(cfg_path)


## Fortschritt: {running, total, done, sent, skipped, state}
## state: "" | "running" | "finished" | "cancelled" | "error" | "update" | "auth".
func backfill_state() -> Dictionary:
	return {"running": bool(_bf.running), "total": int(_bf.total), "done": int(_bf.done),
		"sent": int(_bf.sent), "skipped": int(_bf.skipped), "state": str(_bf.state)}


func backfill_running() -> bool:
	return bool(_bf.running)


## Wie viele Bestwerte noch hochzuladen waeren.
func backfill_pending(osz_files: Dictionary, entries: Array = []) -> int:
	if entries.is_empty():
		entries = ScoreStore.best_plays(99999, "")
	return backfill_candidates(entries, backfill_done_keys(), osz_files).size()


## Startet den Upload. entries leer = alle lokalen Mania-Bestwerte. false = nichts zu tun
## (Online aus, nicht angemeldet, laeuft schon, nichts offen).
func start_backfill(osz_files: Dictionary, entries: Array = []) -> bool:
	if not enabled() or not logged_in() or update_required or bool(_bf.running):
		return false
	if entries.is_empty():
		entries = ScoreStore.best_plays(99999, "")
	var list := backfill_candidates(entries, backfill_done_keys(), osz_files)
	if list.is_empty():
		return false
	_bf = {"running": true, "cancel": false, "list": list, "idx": 0, "total": list.size(),
		"done": 0, "sent": 0, "skipped": 0, "state": "running", "wait": 0.0,
		"task": -1, "out": {}, "cur": {}}
	backfill_changed.emit()
	_bf_step()
	return true


func cancel_backfill() -> void:
	if bool(_bf.running):
		_bf["cancel"] = true
		if int(_bf.get("task", -1)) < 0 and not _bf_in_flight:
			_bf_end("cancelled")


func _bf_end(state: String) -> void:
	_bf["running"] = false
	_bf["state"] = state
	_bf_in_flight = false
	backfill_changed.emit()


func _bf_process(delta: float) -> void:
	if not bool(_bf.running):
		return
	var task := int(_bf.get("task", -1))
	if task >= 0:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_bf["task"] = -1
			_bf_got_meta(_bf.cur, (_bf.out as Dictionary).get("meta", {}))
		return
	if _bf_in_flight:
		return
	if float(_bf.wait) > 0.0:
		_bf["wait"] = float(_bf.wait) - delta
		if float(_bf.wait) <= 0.0:
			_bf_step()


func _bf_step() -> void:
	if not bool(_bf.running) or _bf_in_flight:
		return
	if bool(_bf.cancel):
		_bf_end("cancelled")
		return
	if int(_bf.idx) >= (_bf.list as Array).size():
		_bf_end("finished")
		return
	var c: Dictionary = _bf.list[int(_bf.idx)]
	_bf["cur"] = c
	if bf_meta_provider.is_valid():
		_bf_got_meta(c, bf_meta_provider.call(c.osz_path, c.version))
		return
	_bf["out"] = {}
	_bf["task"] = WorkerThreadPool.add_task(
		Callable(self, "_bf_job").bind(c.osz_path, c.version, _bf.out))


## Naechster Eintrag nach Pause (0 = sofort).
func _bf_advance(pause: float) -> void:
	_bf_in_flight = false
	_bf["idx"] = int(_bf.idx) + 1
	_bf["done"] = int(_bf.done) + 1
	backfill_changed.emit()
	if pause <= 0.0 or bool(_bf.cancel):
		_bf_step()
	else:
		_bf["wait"] = pause


func _bf_got_meta(c: Dictionary, meta: Dictionary) -> void:
	if bool(_bf.cancel):
		_bf_end("cancelled")
		return
	var e: Dictionary = c.entry
	if str(meta.get("md5", "")) == "" or entry_count_sum(e) != int(meta.get("total_notes", -1)):
		# Map fehlt/geaendert oder Zahlen passen nicht: nie hochladen, nicht erneut pruefen.
		_bf_mark(str(c.key))
		_bf["skipped"] = int(_bf.skipped) + 1
		_bf_advance(0.0)
		return
	var res := e.duplicate()
	res["pp"] = maxf(float(e.get("pp", 0.0)), 0.0)
	var m := meta.duplicate()
	m["ranked"] = true
	var body := build_body(res, m, "mania")
	var reg := build_register_body(m, "mania")
	_bf_in_flight = true
	_send("POST", "/score", body, func(code: int, text: String):
		_bf_on_reply(c, reg, code, text))


func _bf_on_reply(c: Dictionary, reg: Dictionary, code: int, text: String) -> void:
	var r := classify_submit(code, text)
	last_code = str(r.code)
	match str(r.kind):
		"ok":
			_bf_mark(str(c.key))
			_bf["sent"] = int(_bf.sent) + 1
			var md5 := str(reg.get("beatmap_md5", ""))
			if str(r.pp_source) == "client" and md5 != "" and not _registered_md5.has(md5):
				_register_map(reg, func(): _bf_advance(bf_interval))
			else:
				_bf_advance(bf_interval)
		"drop":
			_bf_mark(str(c.key))
			_bf["skipped"] = int(_bf.skipped) + 1
			_bf_advance(bf_interval)
		"rate":
			# Zu schnell: gleichen Eintrag nach Pause nochmal.
			_bf_in_flight = false
			_bf["wait"] = bf_rate_wait
			if bf_rate_wait <= 0.0:
				_bf_step()
		"update":
			update_required = true
			_bf_end("update")
			state_changed.emit()
		"auth":
			_bf_end("auth")
			logout()
		_:
			_bf_end("error")


# --- Rangliste ---------------------------------------------------------------

## done: Callable(ok: bool, entries: Array, message: String)
func leaderboard(mode: String, md5: String, beatmap_id: int, done: Callable) -> void:
	if not enabled():
		done.call(false, [], "disabled")
		return
	var q := "/leaderboard?mode=%s&md5=%s&limit=%d" % [
		mode.uri_encode(), md5.uri_encode(), LEADERBOARD_LIMIT]
	if beatmap_id > 0:
		q += "&beatmap_id=%d" % beatmap_id
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
