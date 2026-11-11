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
## Version der Upload-Merker in cfg_path [backfill]. Aeltere Merker (v1: "done",
## gemischt aus angenommen und uebersprungen) werden verworfen und erneut versucht.
const BACKFILL_VERSION := 2
## Obergrenze fuer replay_content (Base64-Text, damit auch fuer das gzip darin).
const REPLAY_MAX_BYTES := 2 * 1024 * 1024
## Alte-Scores-Upload: Replay-Datum darf so weit neben dem Bestwert-Datum liegen.
const REPLAY_DATE_TOL_S := 5
const AVATAR_CACHE := "user://avatar"
const AVATAR_EXTS := ["png", "jpg", "webp"]
## Avatare anderer Spieler (Rangliste) im Speicher, hoechstens so viele.
const AVATAR_MEM_MAX := 50
## Groessere Avatare werden beim Laden auf diese Kantenlaenge verkleinert.
const AVATAR_MAX_PX := 256

## Zustandsaenderung (Anmeldung, Warteschlange, Update noetig).
signal state_changed
## Fortschritt/Ende des Alte-Scores-Uploads.
signal backfill_changed
## Eigenes Avatar (avatar) geladen, geaendert oder entfernt.
signal avatar_changed

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

## Test-Hook fuer Bilder: Callable(method, url, headers, done: Callable(code, bytes)).
var raw_transport := Callable()
## Test-Hook fuer Replays: Callable(osz_path, version, replay_mode) -> JSON-Text ("" = keins).
var replay_provider := Callable()
## Cache des eigenen Avatars: <avatar_cache>.png|jpg|webp
var avatar_cache := _default_avatar_cache()
## Eigenes Avatar von der Website (null = keins / nicht angemeldet).
var avatar: Texture2D = null

var _queue: Array = []
var _busy := false
var _retry_t := 0.0
var _registered_md5: Dictionary = {}
var _bf_in_flight := false
var _bf_log: Array = []
## Backfill-Lauf: {running, cancel, list, idx, total, done, sent, skipped, failed, state,
## wait, task, out}
var _bf := {"running": false, "total": 0, "done": 0, "sent": 0, "skipped": 0,
	"state": ""}


func _ready() -> void:
	load_auth()
	load_cached_avatar()
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
	# Bestehende Datei laden: Abschnitte wie [backfill] und [prompt] bleiben erhalten.
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	cfg.set_value("auth", "token", token)
	cfg.set_value("auth", "user_id", user_id)
	cfg.set_value("auth", "username", username)
	cfg.save(cfg_path)


func logout() -> void:
	token = ""
	user_id = ""
	username = ""
	_save_auth()
	clear_avatar_cache()
	if avatar != null:
		avatar = null
		avatar_changed.emit()
	state_changed.emit()


## true = Login-Dialog beim Spielstart abgeschaltet ("Nicht mehr fragen").
func login_prompt_disabled() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(cfg_path) == OK and bool(cfg.get_value("prompt", "never", false))


func set_login_prompt_disabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	cfg.set_value("prompt", "never", on)
	cfg.save(cfg_path)


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
				refresh_avatar()
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
			refresh_avatar()
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
		"osz_path": osz_path,
	}


static func _md5_bytes(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(bytes)
	return h.finish().hex_encode()


## Body fuer POST /score. result = ManiaCore.stats() (+ "pp"), meta s. meta_from_beatmap.
## mode "mania" liefert pp, "orbit"/"rally"/"dirigent" liefern stars (result.stars bzw. meta.stars).
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
	if mode != "mania":
		body["stars"] = float(result.get("stars", meta.get("stars", 0.0)))
	else:
		body["pp"] = maxf(float(result.get("pp", 0.0)), 0.0)
	# Dirigent: Takt-Anteil zusaetzlich (Counts zaehlen nur die Einsaetze).
	if mode == "dirigent":
		body["beats_hit"] = int(result.get("beats_hit", 0))
		body["beats_total"] = int(result.get("beats_total", 0))
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
			"pp_source": str(dd.get("pp_source", "")), "duplicate": bool(dd.get("duplicate", false)),
			"score_id": score_id_of(dd)}
	if code == 426:
		return {"kind": "update", "message": msg, "code": msg}
	if code == 401:
		return {"kind": "auth", "message": msg, "code": msg}
	if code == 429:
		return {"kind": "rate", "message": msg, "code": msg}
	if code >= 400 and code < 500:
		return {"kind": "drop", "message": msg, "code": msg}
	return {"kind": "retry", "message": msg, "code": msg}


## Nach jedem gewerteten Lauf. mode "mania" | "orbit" | "rally" | "dirigent". false = nichts gesendet
## (Online aus / nicht angemeldet / keine md5).
func submit(result: Dictionary, meta: Dictionary, mode: String = "mania") -> bool:
	if not enabled() or not logged_in() or str(meta.get("md5", "")) == "":
		return false
	var body := build_body(result, meta, mode)
	var osz := str(meta.get("osz_path", ""))
	var ver := str(meta.get("difficulty", ""))
	var score := int(result.get("score", 0))
	var rc := replay_content_for(osz, ver, mode, score)
	if rc != "":
		body["replay_content"] = rc
	var entry := {
		"body": body,
		"reg": build_register_body(meta, mode),
		"registered": false,
		# Lokaler Eintrag, an den die Server-ID (online_id) kommt.
		"local": {"osz_file": osz.get_file(), "version": ver, "mode": mode, "score": score},
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
		_store_online_id(entry.get("local", {}), str(r.score_id))
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


const COUNT_KEYS := ["n_max", "n300", "n200", "n100", "n50", "n_miss"]


## Trefferzahlen [MAX, 300, 200, 100, 50, Miss] fuer den Upload, Summe exakt total.
## Passen die gespeicherten Zahlen, bleiben sie. Sonst aus der Genauigkeit (osu!mania-
## Formel wie ManiaCore.accuracy) hergeleitet, Modell wie ScoreStore._counts_of:
## Abzuege als 100er, Rest 70 % MAX / 30 % 300; reicht das nicht (Genauigkeit unter
## 33 %), werden 100er zu 50ern, dann 50er zu Misses.
static func backfill_counts(e: Dictionary, total: int) -> Array:
	if total <= 0:
		return [0, 0, 0, 0, 0, 0]
	if entry_count_sum(e) == total:
		var keep: Array = []
		for k in COUNT_KEYS:
			keep.append(maxi(int(e.get(k, 0)), 0))
		return keep
	var acc := clampf(float(e.get("accuracy", 0.0)), 0.0, 1.0)
	# Abzug in Formel-Einheiten: 100er = 200, 50er = 250, Miss = 300 (von 300).
	var ded := int(round((1.0 - acc) * 300.0 * total))
	var n100 := 0
	var n50 := 0
	var miss := 0
	if ded <= 200 * total:
		n100 = clampi(int(round(ded / 200.0)), 0, total)
	elif ded <= 250 * total:
		n50 = clampi(int(round((ded - 200 * total) / 50.0)), 0, total)
		n100 = total - n50
	else:
		miss = clampi(int(round((ded - 250 * total) / 50.0)), 0, total)
		n50 = total - miss
	var rest := total - n100 - n50 - miss
	var n_max := int(round(rest * 0.7))
	return [n_max, rest - n_max, 0, n100, n50, miss]


## Vorauswahl aus ScoreStore.best_plays(): nur Mania, nicht unranked/failed, noch
## nicht hochgeladen, .osz vorhanden (osz_files: Dateiname -> Pfad). Eintraege ohne
## Trefferzahlen (aeltere Versionen) zaehlen mit: backfill_counts() leitet sie her.
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


## Merker laden; v1-Merker ("done") verwerfen: sie mischten angenommene und
## lokal/serverseitig uebersprungene Scores (fehlende oder unpassende Trefferzahlen).
## Danach laeuft der automatische Upload erneut; bereits angenommene Scores meldet der
## Server als Duplikat und sie landen wieder in "sent".
func _bf_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return cfg
	if int(cfg.get_value("backfill", "v", 1)) < BACKFILL_VERSION and cfg.has_section("backfill"):
		for k in ["done", "sent", "skipped"]:
			if cfg.has_section_key("backfill", k):
				cfg.erase_section_key("backfill", k)
		cfg.set_value("backfill", "auto_done", false)
		cfg.set_value("backfill", "v", BACKFILL_VERSION)
		cfg.save(cfg_path)
	return cfg


static func _cfg_list(cfg: ConfigFile, key: String) -> Array:
	var v: Variant = cfg.get_value("backfill", key, [])
	return (v as Array).duplicate() if v is Array else []


## Keys, die nicht mehr gesendet werden: vom Server angenommen ("sent") oder in
## dieser Merker-Version uebersprungen ("skipped": Map fehlt, Server lehnt ab).
func backfill_done_keys() -> Array:
	var cfg := _bf_cfg()
	return _cfg_list(cfg, "sent") + _cfg_list(cfg, "skipped")


## Vom Server angenommene Keys.
func backfill_sent_keys() -> Array:
	return _cfg_list(_bf_cfg(), "sent")


## list: "sent" | "skipped"
func _bf_mark(key: String, list: String = "sent") -> void:
	var cfg := _bf_cfg()
	var keys := _cfg_list(cfg, list)
	if not keys.has(key):
		keys.append(key)
	cfg.set_value("backfill", list, keys)
	cfg.set_value("backfill", "v", BACKFILL_VERSION)
	cfg.save(cfg_path)


## true, wenn der automatische Upload nach dem ersten Login schon lief.
func backfill_auto_done() -> bool:
	return bool(_bf_cfg().get_value("backfill", "auto_done", false))


func set_backfill_auto_done() -> void:
	var cfg := _bf_cfg()
	cfg.set_value("backfill", "auto_done", true)
	cfg.set_value("backfill", "v", BACKFILL_VERSION)
	cfg.save(cfg_path)


## Protokoll des letzten Laufs: [{key, kind, code, http}] je Score (kind wie
## classify_submit bzw. "no_map").
func backfill_log() -> Array:
	return _bf_log.duplicate()


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
	_bf_log.clear()
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
	var total := int(meta.get("total_notes", 0))
	if str(meta.get("md5", "")) == "" or total <= 0:
		# Map fehlt oder laesst sich nicht lesen: in dieser Merker-Version nicht erneut pruefen.
		_bf_mark(str(c.key), "skipped")
		_bf_log.append({"key": str(c.key), "kind": "no_map", "code": "", "http": 0})
		_bf["skipped"] = int(_bf.skipped) + 1
		_bf_advance(0.0)
		return
	var res := e.duplicate()
	# Fehlende/unpassende Trefferzahlen (aeltere Versionen, umgerechnete Scores) aus der
	# Genauigkeit herleiten; Score, Genauigkeit, Grade und Datum bleiben.
	var cnt := backfill_counts(e, total)
	for i in COUNT_KEYS.size():
		res[COUNT_KEYS[i]] = int(cnt[i])
	res["max_combo"] = clampi(int(e.get("max_combo", 0)), 0, total)
	# pp unveraendert mitsenden, der Server rechnet selbst nach.
	res["pp"] = maxf(float(e.get("pp", 0.0)), 0.0)
	var m := meta.duplicate()
	m["ranked"] = true
	var body := build_body(res, m, "mania")
	# Alte Bestwerte ohne gespeicherte Combo: nicht 0 behaupten (Server stuft das als
	# verdaechtig ein), sondern als unbekannt melden.
	if int(e.get("max_combo", 0)) <= 0:
		body["max_combo"] = null
		body["combo_unknown"] = true
	# Replay nur, wenn das lokale Replay genau dieser Bestwert ist (Score + Datum).
	if str(e.get("date", "")) != "":
		var rc := replay_content_for(str(c.osz_path), str(c.version), "mania",
			int(e.get("score", 0)), str(e.get("date", "")))
		if rc != "":
			body["replay_content"] = rc
	var reg := build_register_body(m, "mania")
	_bf_in_flight = true
	_send("POST", "/score", body, func(code: int, text: String):
		_bf_on_reply(c, reg, code, text))


func _bf_on_reply(c: Dictionary, reg: Dictionary, code: int, text: String) -> void:
	var r := classify_submit(code, text)
	last_code = str(r.code)
	_bf_log.append({"key": str(c.key), "kind": str(r.kind), "code": str(r.code), "http": code})
	if str(r.kind) != "ok":
		print("Backfill %s: HTTP %d %s" % [str(c.key), code, str(r.code)])
	match str(r.kind):
		"ok":
			_store_online_id({"osz_file": str(c.osz_file), "version": str(c.version),
				"mode": "mania", "score": int((c.entry as Dictionary).get("score", 0))}, str(r.score_id))
			_bf_mark(str(c.key), "sent")
			_bf["sent"] = int(_bf.sent) + 1
			var md5 := str(reg.get("beatmap_md5", ""))
			if str(r.pp_source) == "client" and md5 != "" and not _registered_md5.has(md5):
				_register_map(reg, func(): _bf_advance(bf_interval))
			else:
				_bf_advance(bf_interval)
		"drop":
			_bf_mark(str(c.key), "skipped")
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


# --- Replay-Upload und Server-ID -----------------------------------------------
## Jeder neue Score schickt sein Replay mit: replay_content = base64(gzip(JSON-Text der
## ReplayStore-Datei)). Mania: user://replays/<key>.json, Orbit: letzter Lauf
## (MODE_ORBIT_LAST). Nur wenn die Datei zum Ergebnis passt, sonst ohne Replay.

## base64(gzip(json_text)); "" bei leerem Text oder wenn das Ergebnis max_len uebersteigt.
static func encode_replay(json_text: String, max_len: int = REPLAY_MAX_BYTES) -> String:
	if json_text.strip_edges() == "":
		return ""
	var gz := json_text.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	if gz.is_empty():
		return ""
	var b64 := Marshalls.raw_to_base64(gz)
	return "" if b64.length() > max_len else b64


## Umkehrung von encode_replay (Tests, Werkzeuge). "" bei kaputten Daten.
static func decode_replay(b64: String) -> String:
	if b64 == "":
		return ""
	var gz := Marshalls.base64_to_raw(b64)
	if gz.is_empty():
		return ""
	return gz.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()


## Passt die Replay-Datei (JSON-Text) zum Lauf? Events vorhanden, gleicher Score und,
## wenn date_local gesetzt ist, meta.date hoechstens REPLAY_DATE_TOL_S daneben
## (beide lokale Zeit wie ScoreStore/ReplayStore).
static func replay_matches(json_text: String, score: int, date_local: String = "") -> bool:
	var d: Variant = JSON.parse_string(json_text)
	if not (d is Dictionary) or not (d.get("events") is Array) or (d.events as Array).is_empty():
		return false
	var m: Variant = d.get("meta", {})
	if not (m is Dictionary) or not m.has("score") or int(m.score) != score:
		return false
	if date_local == "":
		return true
	var a := Time.get_unix_time_from_datetime_string(str(m.get("date", "")))
	var b := Time.get_unix_time_from_datetime_string(date_local)
	return a > 0 and b > 0 and absi(a - b) <= REPLAY_DATE_TOL_S


func _replay_text(osz_path: String, version: String, rmode: String) -> String:
	if replay_provider.is_valid():
		return str(replay_provider.call(osz_path, version, rmode))
	var path := ReplayStore.path_for_key(ReplayStore.key(osz_path, version), rmode)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## replay_content fuer einen Lauf (mode "mania" | "orbit" | "rally" | "dirigent") oder "" (kein passendes
## Replay, zu gross; Rally/Dirigent haben noch keine Replay-Ablage: immer "").
func replay_content_for(osz_path: String, version: String, mode: String, score: int,
		date_local: String = "") -> String:
	if osz_path == "" or mode == "rally" or mode == "dirigent":
		return ""
	var rmode := ReplayStore.MODE_ORBIT_LAST if mode == "orbit" else "mania"
	var text := _replay_text(osz_path, version, rmode)
	if text == "" or not replay_matches(text, score, date_local):
		return ""
	return encode_replay(text)


## Score-ID aus der Antwort von POST /score ("score_id", "id" oder score.id), sonst "".
static func score_id_of(d: Dictionary) -> String:
	for k in ["score_id", "id"]:
		var v: Variant = d.get(k)
		if v is float and v == floorf(v):
			return str(int(v))
		if v is int or (v is String and v != ""):
			return str(v)
	var s: Variant = d.get("score")
	if s is Dictionary:
		return score_id_of(s)
	return ""


## Server-ID am lokalen Bestwert/Verlaufseintrag vermerken (ScoreStore.set_online_id).
func _store_online_id(local: Variant, sid: String) -> void:
	if sid == "" or not (local is Dictionary) or str(local.get("osz_file", "")) == "":
		return
	ScoreStore.set_online_id(str(local.osz_file), str(local.get("version", "")),
		str(local.get("mode", "mania")), int(local.get("score", 0)), sid)


# --- Avatar --------------------------------------------------------------------
## GET /player/<name>/avatar liefert PNG/JPG/WebP, 404 = keins. Das eigene Avatar liegt
## in avatar_cache.<ext> und wird bei jedem Start (check_auth) und Login erneuert.
## Avatare anderer Spieler (Rangliste) bleiben nur im Speicher.

var _avatar_mem := {}
var _avatar_order: Array = []
var _avatar_wait := {}


## Testlaeufe (--script) nie den echten Cache: eigener Pfad je Prozess.
static func _default_avatar_cache() -> String:
	for x in OS.get_cmdline_args():
		if x == "--script" or x == "-s":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_tmp"))
			return "user://test_tmp/avatar_%d" % OS.get_process_id()
	return AVATAR_CACHE


## true = avatar_cache zeigt auf den echten Cache (nicht im Testlauf).
static func avatar_cache_is_real() -> bool:
	return _default_avatar_cache() == AVATAR_CACHE


static func avatar_path(player: String) -> String:
	return "/player/%s/avatar" % player.uri_encode()


## Bildformat an den ersten Bytes: "png" | "jpg" | "webp" | "".
static func image_ext(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		return "jpg"
	if bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Textur aus Bildbytes oder null (unbekanntes Format, kaputt).
static func texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	var ext := image_ext(bytes)
	if ext == "":
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match ext:
		"png": err = img.load_png_from_buffer(bytes)
		"jpg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	var big := maxi(img.get_width(), img.get_height())
	if big > AVATAR_MAX_PX:
		var f := float(AVATAR_MAX_PX) / big
		img.resize(maxi(1, int(img.get_width() * f)), maxi(1, int(img.get_height() * f)),
			Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


## Avatar fuer Profilkarte/Profil: Website-Avatar (angemeldet), sonst local (das lokal
## gewaehlte Bild, Settings.avatar_texture()), sonst null (Initiale zeigen).
static func display_avatar(p_api: OnlineApi, local: Texture2D) -> Texture2D:
	if p_api != null and p_api.logged_in() and p_api.avatar != null:
		return p_api.avatar
	return local


## Eigenes Avatar aus dem Cache (beim Start, bevor der Server antwortet).
func load_cached_avatar() -> void:
	avatar = null
	if not logged_in():
		return
	for ext in AVATAR_EXTS:
		var p := "%s.%s" % [avatar_cache, ext]
		if FileAccess.file_exists(p):
			avatar = texture_from_bytes(FileAccess.get_file_as_bytes(p))
			if avatar != null:
				return


func clear_avatar_cache() -> void:
	for ext in AVATAR_EXTS:
		var p := "%s.%s" % [avatar_cache, ext]
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Eigenes Avatar neu laden. 200 + Bild: Cache ersetzen; 404: Cache loeschen;
## Netz-/Serverfehler: Cache bleibt. done: Callable(has_avatar: bool).
func refresh_avatar(done: Callable = Callable()) -> void:
	if not enabled() or not logged_in() or username == "":
		if done.is_valid():
			done.call(avatar != null)
		return
	var who := username
	_send_raw("GET", avatar_path(who), func(code: int, bytes: PackedByteArray):
		if who == username and logged_in():
			_on_own_avatar(code, bytes)
		if done.is_valid():
			done.call(avatar != null))


func _on_own_avatar(code: int, bytes: PackedByteArray) -> void:
	if code == 404:
		clear_avatar_cache()
		_avatar_remember(username, null)
		if avatar != null:
			avatar = null
			avatar_changed.emit()
		return
	if code < 200 or code >= 300:
		return
	var tex := texture_from_bytes(bytes)
	if tex == null:
		return
	clear_avatar_cache()
	var f := FileAccess.open("%s.%s" % [avatar_cache, image_ext(bytes)], FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	avatar = tex
	_avatar_remember(username, tex)
	avatar_changed.emit()


## Avatar eines Spielers (Rangliste). done: Callable(tex: Texture2D oder null).
## Antworten (auch 404) bleiben im Speicher (max. AVATAR_MEM_MAX Spieler), gleichzeitige
## Anfragen fuer denselben Namen gehen nur einmal raus.
func player_avatar(player: String, done: Callable) -> void:
	var who := player.strip_edges()
	var k := who.to_lower()
	if k == "" or not enabled():
		done.call(null)
		return
	if _avatar_mem.has(k):
		done.call(_avatar_mem[k])
		return
	if _avatar_wait.has(k):
		(_avatar_wait[k] as Array).append(done)
		return
	_avatar_wait[k] = [done]
	_send_raw("GET", avatar_path(who), func(code: int, bytes: PackedByteArray):
		var tex: Texture2D = texture_from_bytes(bytes) if code >= 200 and code < 300 else null
		if (code >= 200 and code < 300) or code == 404:
			_avatar_remember(k, tex)
		var list: Array = _avatar_wait.get(k, [])
		_avatar_wait.erase(k)
		for cb in list:
			if (cb as Callable).is_valid():
				(cb as Callable).call(tex))


func _avatar_remember(player: String, tex: Texture2D) -> void:
	var k := player.strip_edges().to_lower()
	if k == "":
		return
	if _avatar_mem.has(k):
		_avatar_order.erase(k)
	_avatar_mem[k] = tex
	_avatar_order.append(k)
	while _avatar_order.size() > AVATAR_MEM_MAX:
		_avatar_mem.erase(_avatar_order.pop_front())


func avatar_mem_size() -> int:
	return _avatar_mem.size()


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


## Wie _send, liefert aber die rohen Bytes (Bilder). done: Callable(code, bytes).
## Testlauf mit transport, aber ohne raw_transport: nie ins Netz (code 0).
func _send_raw(method: String, path: String, done: Callable) -> void:
	var url := base_url + path
	if raw_transport.is_valid():
		raw_transport.call(method, url, headers(), done)
		return
	if transport.is_valid() or not is_inside_tree():
		done.call(0, PackedByteArray())
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	req.body_size_limit = 8 * 1024 * 1024
	add_child(req)
	req.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		done.call(code, data))
	var m := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	if req.request(url, headers(), m) != OK:
		req.queue_free()
		done.call(0, PackedByteArray())
