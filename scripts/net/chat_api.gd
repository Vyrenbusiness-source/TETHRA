class_name ChatApi
extends Node

## Ingame-Chat ueber den OMEN-Server: HTTP, Parsing, Polling, Map-Links.
## Zugangsdaten kommen nur lesend aus OnlineApi (Header, Token, Basis-URL).

const MAX_LEN := 2000
const UNREAD_INTERVAL_S := 30.0
const OPEN_INTERVAL_S := 4.0
const MESSAGE_LIMIT := 50
## "/tethra/..." = historische Kennung (Server-Pfade auf butzebot.com, stehen auch in alten
## Chat-Nachrichten). Der Bot heisst so, wie der Server ihn liefert ("TETHRA Bot").
## Erzeugte Links nutzen OnlineApi.LINK_NAME; erkannt werden /tethra/ und /omen/ (LINK_NAMES).
const MAP_URL := OnlineApi.SITE_BASE + "/map/"
const LINK_NAMES := "(?:tethra|omen)"
const COVER_URL := "https://assets.ppy.sh/beatmaps/%d/covers/list@2x.jpg"
const PREVIEW_URL := "https://b.ppy.sh/preview/%d.mp3"

signal unread_changed(count: int)
signal conversations_changed
signal messages_changed(conversation_id: String)

var online: OnlineApi
## Test-Hook: Callable(method, url, headers, body_text, done: Callable(code, text)).
var transport := Callable()

var unread := 0
var conversations: Array = []
## Nachrichten je Unterhaltung: id -> Array (alt -> neu).
var messages: Dictionary = {}
## Offene Unterhaltung ("" = Chat zu bzw. keine gewaehlt).
var open_id := ""
var overlay_open := false

var _t_unread := 0.0
var _t_open := 0.0
var _busy_unread := false
var _busy_open := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not active():
		return
	_t_unread += delta
	if _t_unread >= UNREAD_INTERVAL_S:
		_t_unread = 0.0
		refresh_unread()
	if overlay_open:
		_t_open += delta
		if _t_open >= OPEN_INTERVAL_S:
			_t_open = 0.0
			poll_open()


## Angemeldet und Server konfiguriert?
func active() -> bool:
	return online != null and online.enabled() and online.logged_in()


## Chat auf-/zugemacht: Zaehler sofort neu holen.
func set_overlay_open(v: bool) -> void:
	overlay_open = v
	_t_open = 0.0
	if v and active():
		refresh_conversations()
		if open_id != "":
			load_messages(open_id)
	elif not v:
		open_id = ""


# --- Parsing (statisch, testbar) ---------------------------------------------

static func parse_unread(text: String) -> int:
	var d: Variant = JSON.parse_string(text)
	if d is Dictionary:
		for k in ["unread", "count", "unread_count", "total"]:
			if d.has(k):
				return maxi(int(d[k]), 0)
	elif d is float or d is int:
		return maxi(int(d), 0)
	return 0


static func parse_conversations(text: String) -> Array:
	var out: Array = []
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary) or not (d.get("conversations") is Array):
		return out
	for c in d.conversations:
		if not (c is Dictionary):
			continue
		var o: Variant = c.get("other", {})
		if not (o is Dictionary):
			o = {}
		out.append({
			"id": str(c.get("id", "")),
			"other_id": str(o.get("id", "")),
			"name": str(o.get("username", "?")),
			"country": str(o.get("country_code", "")),
			"online": bool(o.get("online", false)),
			"last_message": str(c.get("last_message", "")),
			"last_sender_id": str(c.get("last_sender_id", "")),
			"unread": maxi(int(c.get("unread_count", 0)), 0),
			"updated_at": str(c.get("updated_at", "")),
		})
	return out


static func parse_messages(text: String) -> Dictionary:
	var out := {"conversation_id": "", "messages": []}
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary):
		return out
	out.conversation_id = str(d.get("conversation_id", ""))
	var list: Variant = d.get("messages", [])
	if not (list is Array):
		return out
	for m in list:
		if not (m is Dictionary):
			continue
		var reply: Dictionary = {}
		var r: Variant = m.get("reply_to")
		if r is Dictionary:
			reply = {"id": str(r.get("id", "")), "sender_name": str(r.get("sender_name", "")),
				"content": str(r.get("content", ""))}
		out.messages.append({
			"id": str(m.get("id", "")),
			"sender_id": str(m.get("sender_id", "")),
			"content": str(m.get("content", "")),
			"created_at": str(m.get("created_at", "")),
			"reply_to": reply,
		})
	return out


static func parse_send(text: String) -> Dictionary:
	var d: Variant = JSON.parse_string(text)
	if d is Dictionary and d.has("message_id"):
		return {"ok": true, "conversation_id": str(d.get("conversation_id", "")),
			"message_id": str(d.get("message_id", "")), "created_at": str(d.get("created_at", ""))}
	return {"ok": false, "conversation_id": "", "message_id": "", "created_at": ""}


## Nutzersuche: Liste {id, name, online}; akzeptiert {users:[...]} oder [...].
static func parse_users(text: String) -> Array:
	var d: Variant = JSON.parse_string(text)
	var list: Variant = d
	if d is Dictionary:
		list = d.get("users", d.get("results", []))
	var out: Array = []
	if not (list is Array):
		return out
	for u in list:
		if u is Dictionary and str(u.get("username", "")) != "":
			out.append({"id": str(u.get("id", "")), "name": str(u.username),
				"online": bool(u.get("online", false))})
		elif u is String and u != "":
			out.append({"id": "", "name": u, "online": false})
	return out


static func total_unread(convs: Array) -> int:
	var n := 0
	for c in convs:
		n += int(c.get("unread", 0))
	return n


## Eigene Nachricht? (sender_id gegen OnlineApi.user_id)
static func is_mine(msg: Dictionary, my_id: String) -> bool:
	return my_id != "" and str(msg.get("sender_id", "")) == my_id


## Text auf 2000 Zeichen kuerzen, Rand entfernen.
static func clean(text: String) -> String:
	var t := text.strip_edges()
	return t.substr(0, MAX_LEN) if t.length() > MAX_LEN else t


## Ungelesen-Zahl als kurzer Text ("" bei 0, "99+" ab 100).
static func unread_text(n: int) -> String:
	if n <= 0:
		return ""
	return "99+" if n > 99 else str(n)


# --- Map-Links ----------------------------------------------------------------

## Link zur Map. meta: {md5, set_id, beatmap_id, title, artist?, version?, stars?}.
static func map_link(meta: Dictionary) -> String:
	var s := MAP_URL + str(meta.get("md5", "")).uri_encode()
	s += "?set=%d&b=%d&t=%s" % [int(meta.get("set_id", 0)), int(meta.get("beatmap_id", 0)),
		str(meta.get("title", "")).uri_encode()]
	var artist := str(meta.get("artist", ""))
	if artist != "":
		s += "&a=" + artist.uri_encode()
	var ver := str(meta.get("version", ""))
	if ver != "":
		s += "&v=" + ver.uri_encode()
	if float(meta.get("stars", 0.0)) > 0.0:
		s += "&s=%.2f" % float(meta.stars)
	return s


## Erster Map-Link im Text. Leeres Dictionary = keiner. Sonst
## {md5, set_id, beatmap_id, title, artist, version, difficulty, stars, link, text}
## mit text = Rest ohne Link. Kennt alle Formen aus parse_content().
static func parse_map_link(content: String) -> Dictionary:
	var maps: Array = parse_content(content).maps
	return {} if maps.is_empty() else maps[0]


# --- Bot-Nachrichten: Map-Links aller Formen, Markdown ---------------------------

const SITE := "https://butzebot.com"
## Platzhalter fuer einen entfernten Map-Link (Zeilen nur daraus verschwinden ganz).
const _CUT := "\u0001"
## Zeichen aus den Symbol-Bloecken, die die UI-Schrift sicher hat (bleiben stehen).
const _KEEP_SYMBOLS := [0x2605, 0x2606, 0x2665, 0x266A, 0x266B, 0x2713, 0x2715]

static var _re_cache: Dictionary = {}


static func _re(pattern: String) -> RegEx:
	if not _re_cache.has(pattern):
		var re := RegEx.new()
		re.compile(pattern)
		_re_cache[pattern] = re
	return _re_cache[pattern]


## Nachricht zerlegen: {text, maps}. maps = alle Map-Links (je ein Dictionary wie
## parse_map_link), text = aufgeraeumter Rest (tidy_text) ohne diese Links.
## Erkannte Links, relativ oder mit https://butzebot.com davor, nackt oder als
## Markdown "[Titel by Kuenstler](link)":
##   /tethra/map/<md5>?set=<id>&b=&t=&a=&v=&s=      (Spieler-Links, map_link())
##   /tethra/songs?detail=<slug>&difficulty=<slug>&set=<id>   (TETHRA Bot)
##   /omen/map/..., /omen/songs?...                  (alte Bot-Nachrichten, kuenftiger Server-Name)
## Ohne set-ID gibt es keine Karte: der Link bleibt als Text stehen.
static func parse_content(content: String) -> Dictionary:
	var re := _re("(?:\\[([^\\]\\n]*)\\]\\()?(?<![\\w.:/-])((?:https?://(?:www\\.)?butzebot\\.com)?"
		+ "/" + LINK_NAMES + "/(?:map/([0-9A-Za-z]+)|songs)(\\?[^\\s)]*)?)")
	var follow := _re("^[ \\t]*\\r?\\n[ \\t]*\\*\\*(.+?)\\*\\*\\s*[—–-]\\s*([0-9]+(?:[.,][0-9]+)?)\\s*[★⭐]")
	var maps: Array = []
	var text := ""
	var pos := 0
	for m in re.search_all(content):
		var q: Dictionary = {}
		for part in m.get_string(4).trim_prefix("?").split("&", false):
			var kv := part.split("=", true, 1)
			q[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else ""
		var set_id := int(q.get("set", "0"))
		if set_id <= 0:
			continue
		var has_label := m.get_start(1) >= 0
		var end := m.get_end()
		if has_label and content.substr(end, 1) == ")":
			end += 1
		var title := str(q.get("t", ""))
		var artist := str(q.get("a", ""))
		if title == "" and has_label:
			var label := m.get_string(1).strip_edges()
			var by := label.rfind(" by ")
			title = label.substr(0, by).strip_edges() if by > 0 else label
			if by > 0 and artist == "":
				artist = label.substr(by + 4).strip_edges()
		if title == "":
			title = str(q.get("detail", "")).capitalize()
		var diff := str(q.get("difficulty", ""))
		var version := str(q.get("v", ""))
		var stars := float(q.get("s", "0"))
		# Zeile nach dem Bot-Link: "**[4K] Hyper** — 3.39★ | ..." traegt Diff-Name und Sterne.
		var line := follow.search(content.substr(end))
		if line != null:
			if version == "":
				version = line.get_string(1).strip_edges()
			if stars <= 0.0:
				stars = float(line.get_string(2).replace(",", "."))
		if version == "":
			version = diff.replace("_", " ")
		maps.append({
			"md5": m.get_string(3), "set_id": set_id, "beatmap_id": int(q.get("b", "0")),
			"title": title, "artist": artist, "version": version, "difficulty": diff,
			"stars": stars, "link": m.get_string(2),
			"text": (content.substr(0, m.get_start()) + content.substr(end)).strip_edges(),
		})
		text += content.substr(pos, m.get_start() - pos) + _CUT
		pos = end
	text += content.substr(pos)
	return {"text": tidy_text(text), "maps": maps}


## Text fuer die Anzeige aufraeumen: Emoji weg (die UI-Schrift hat sie nicht, sonst
## Kaestchen), Zeilen nur aus Emoji oder entferntem Link weg, leere "Filters:"-Zeilen
## des Bots weg, Leerzeilen und Leerzeichen zusammengefasst.
static func tidy_text(text: String) -> String:
	var out: PackedStringArray = []
	var empty_filter := _re("^[*_\\s]*(?i:filters?)[*_\\s]*:[*_\\s]*$")
	var spaces := _re("[ \\t]{2,}")
	for raw in text.replace("\r", "").split("\n"):
		var line := spaces.sub(strip_emoji(raw).replace(_CUT, " "), " ", true).strip_edges()
		if line == "":
			# Leerzeile nur, wenn sie schon leer war (nicht durch Emoji/Link entstanden).
			if raw.strip_edges() == "" and not raw.contains(_CUT) and out.size() > 0 and out[out.size() - 1] != "":
				out.append("")
			continue
		if empty_filter.search(line) != null:
			continue
		out.append(line)
	while out.size() > 0 and out[out.size() - 1] == "":
		out.remove_at(out.size() - 1)
	return "\n".join(out)


## Emoji und ihre Zusatzzeichen entfernen; Stern-Emoji wird zu ★.
static func strip_emoji(s: String) -> String:
	var out := ""
	var from := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 0x2000:
			continue
		var star := c == 0x2B50 or c == 0x1F31F
		var drop := star or c == 0xFE0F or c == 0x200D or c == 0x20E3 \
			or (c >= 0x2300 and c <= 0x23FF) or (c >= 0x2B00 and c <= 0x2BFF) \
			or (c >= 0x2600 and c <= 0x27BF and not _KEEP_SYMBOLS.has(c)) \
			or (c >= 0x1F000 and c <= 0x1FAFF) or (c >= 0xE0000 and c <= 0xE007F)
		if drop:
			out += s.substr(from, i - from) + ("★" if star else "")
			from = i + 1
	return out + s.substr(from)


## Relativer Seitenpfad -> volle Adresse. Nur http(s); alles andere "" (nicht oeffnen).
static func absolute_url(url: String) -> String:
	if url.begins_with("/") and not url.begins_with("//"):
		return SITE + url
	if url.begins_with("https://") or url.begins_with("http://"):
		return url
	return ""


## Markdown des Bots -> BBCode fuer RichTextLabel: **fett**, *kursiv*, [Text](Link),
## nackte Links, "# Titel", "- Liste", `code`. Eckige Klammern des Textes werden
## maskiert, fremdes BBCode wirkt also nicht. link_color = "#rrggbb" faerbt Links.
static func md_to_bbcode(text: String, link_color: String = "") -> String:
	return _md(text, true, link_color)


## Dasselbe als reiner Text (Unterhaltungsliste, Antwort-Zitat).
static func md_to_plain(text: String) -> String:
	return _md(text, false, "")


## Kurztext einer Nachricht fuer Liste und Zitat: Karte als "♪ Titel" (ohne Titel
## nur "♪"), sonst Klartext in einer Zeile.
static func preview_plain(content: String) -> String:
	var p := parse_content(content)
	if not p.maps.is_empty():
		return ("♪ " + str(p.maps[0].title)).strip_edges()
	return md_to_plain(str(p.text)).replace("\n", " ")


static func _md(text: String, rich: bool, link_color: String) -> String:
	var out: PackedStringArray = []
	var head := _re("^#{1,6}\\s+(.*)$")
	var item := _re("^[-*]\\s+(.*)$")
	for line in text.split("\n"):
		var h := head.search(line)
		var it := item.search(line)
		if h != null:
			var inner := _md_inline(h.get_string(1), rich, link_color)
			out.append("[b]%s[/b]" % inner if rich else inner)
		elif it != null:
			out.append("• " + _md_inline(it.get_string(1), rich, link_color))
		else:
			out.append(_md_inline(line, rich, link_color))
	return "\n".join(out)


static func _md_inline(s: String, rich: bool, link_color: String) -> String:
	var re := _re("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)|(https?://[^\\s<>\\[\\]]+)|\\*\\*(.+?)\\*\\*"
		+ "|(?<![*\\w])\\*(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?![*\\w])|`([^`\\n]+)`")
	var out := ""
	var pos := 0
	while pos < s.length():
		var m := re.search(s, pos)
		if m == null:
			break
		out += _md_text(s.substr(pos, m.get_start() - pos), rich)
		pos = m.get_end()
		if m.get_start(1) >= 0:
			out += _md_link(m.get_string(2), _md_inline(m.get_string(1), rich, link_color), rich, link_color)
		elif m.get_start(3) >= 0:
			var url := m.get_string(3)
			var cut := url.length()
			while cut > 0 and ".,;:!?)".contains(url[cut - 1]):
				cut -= 1
			pos -= url.length() - cut
			url = url.substr(0, cut)
			out += _md_link(url, _md_text(url, rich), rich, link_color)
		elif m.get_start(4) >= 0:
			var b := _md_inline(m.get_string(4), rich, link_color)
			out += "[b]%s[/b]" % b if rich else b
		elif m.get_start(5) >= 0:
			var i := _md_inline(m.get_string(5), rich, link_color)
			out += "[i]%s[/i]" % i if rich else i
		else:
			out += _md_text(m.get_string(6), rich)
	return out + _md_text(s.substr(pos), rich)


static func _md_text(s: String, rich: bool) -> String:
	return s.replace("[", "[lb]") if rich else s


static func _md_link(url: String, label: String, rich: bool, link_color: String) -> String:
	var target := absolute_url(url).replace("[", "%5B").replace("]", "%5D")
	if not rich or target == "":
		return label
	var tag := "[url=%s]%s[/url]" % [target, label]
	return "[color=%s]%s[/color]" % [link_color, tag] if link_color != "" else tag


## Diff-Index zu einem Karten-Link. names = Diff-Namen des lokalen Sets. Erst der genaue
## Name (version), dann der Slug aus difficulty= ("4k_hyper"), dann der Slug als Teil
## des Namens ("hyper" in "[4K] Hyper"). Kein Treffer = 0.
static func pick_diff(names: Array, version: String, slug: String) -> int:
	var want := version.strip_edges().to_lower()
	if want != "":
		for d in names.size():
			if str(names[d]).strip_edges().to_lower() == want:
				return d
	var s := diff_slug(slug if slug != "" else version)
	if s == "":
		return 0
	for d in names.size():
		if diff_slug(str(names[d])) == s:
			return d
	for d in names.size():
		if diff_slug(str(names[d])).contains(s):
			return d
	return 0


## "[4K] Hyper" -> "4k_hyper".
static func diff_slug(s: String) -> String:
	return _re("[^0-9a-z]+").sub(s.to_lower(), "_", true).trim_prefix("_").trim_suffix("_")


# --- Score-Links / Replays -----------------------------------------------------

const SCORE_URL := OnlineApi.SITE_BASE + "/score/"


static func score_link(score_id: Variant) -> String:
	return SCORE_URL + str(score_id).uri_encode()


## Erster Score-Link im Text: {score_id, link, text} oder {}.
static func parse_score_link(content: String) -> Dictionary:
	var re := RegEx.new()
	re.compile("https://butzebot\\.com/" + LINK_NAMES + "/score/([0-9A-Za-z_-]+)")
	var m := re.search(content)
	if m == null:
		return {}
	var rest := (content.substr(0, m.get_start()) + content.substr(m.get_end())).strip_edges()
	return {"score_id": m.get_string(1), "link": m.get_string(), "text": rest}


## Antwort von GET /score/<id> (evtl. in {score:{...}} verpackt) -> flaches Dictionary, {} bei Fehler.
## Der Server liefert die Map-Felder flach (artist, title, difficulty_name, beatmapset_id,
## beatmap_md5), aeltere Antworten in "map"; beides wird gelesen.
## accuracy immer in Prozent (Server: 0..1). pp nur Mania, points = Wertung der anderen Modi.
static func parse_score(text: String) -> Dictionary:
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary):
		return {}
	if d.get("score") is Dictionary:
		d = d.score
	var mp: Variant = d.get("map", {})
	if not (mp is Dictionary):
		mp = {}
	var pl: Variant = d.get("player", "")
	if pl is Dictionary:
		pl = pl.get("username", pl.get("name", ""))
	var mods: Variant = d.get("mods", [])
	var mod_list: Array = []
	if mods is Array:
		for x in mods:
			mod_list.append(str(x))
	elif mods is String and mods != "":
		mod_list = Array(mods.split(",", false))
	var title := _field(d, mp, ["title"])
	if str(pl) == "" and mp.is_empty() and title == "":
		return {}
	var mode := str(d.get("mode", "mania")) if d.get("mode") != null else "mania"
	var pp := _num(d.get("pp"))
	var points := _num(d.get("points", d.get("orbit_points", d.get("rating"))))
	var diff := _field(d, mp, ["difficulty_name", "difficulty", "version"])
	return {
		"player": str(pl),
		"md5": _field(d, mp, ["beatmap_md5", "md5"]),
		"set_id": int(_field(d, mp, ["beatmapset_id", "set_id"], "0")),
		"beatmap_id": int(_field(d, mp, ["beatmap_id"], "0")),
		"title": title,
		"artist": _field(d, mp, ["artist"]),
		"difficulty": diff,
		"score": int(_num(d.get("score"))),
		"accuracy": acc_percent(_num(d.get("accuracy"))),
		"grade": str(d.get("grade", "")) if d.get("grade") != null else "",
		"max_combo": int(_num(d.get("max_combo"))),
		"pp": pp if pp > 0.0 else points,
		"points": points,
		"stars": _num(d.get("stars")),
		"mods": mod_list,
		"mode": mode if mode != "" else "mania",
		"has_replay": bool(d.get("has_replay", false)) if d.get("has_replay") != null else false,
	}


## Genauigkeit in Prozent: Werte bis 1,0 gelten als Anteil (0,99 -> 99 %).
static func acc_percent(v: float) -> float:
	return v * 100.0 if v <= 1.0 else v


## Erstes nicht leere Feld aus d oder der verschachtelten map, sonst fallback.
static func _field(d: Dictionary, mp: Dictionary, keys: Array, fallback: String = "") -> String:
	for src in [d, mp]:
		for k in keys:
			var v: Variant = src.get(k)
			if v == null or v is Dictionary or v is Array:
				continue
			var s := str(int(v)) if v is float and float(int(v)) == v else str(v)
			if s != "" and s != "0":
				return s
	return fallback


## null/Text -> Zahl (null = 0).
static func _num(v: Variant) -> float:
	if v == null:
		return 0.0
	if v is String:
		return v.to_float()
	return float(v)


## replay_content (base64 von gzip-JSON) -> {meta, events} oder {} bei Fehler.
static func decode_replay(content: String) -> Dictionary:
	var raw := Marshalls.base64_to_raw(content.strip_edges())
	if raw.is_empty():
		return {}
	var bytes := raw.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty():
		return {}
	var d: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if d is Dictionary and d.get("events") is Array:
		return d
	return {}


static func encode_replay(data: Dictionary) -> String:
	var bytes := JSON.stringify(data).to_utf8_buffer()
	return Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_GZIP))


## Replay-Antwort: Rohtext oder JSON mit replay_content. Status "ok"/"missing"/"error".
static func replay_result(code: int, text: String) -> Dictionary:
	if code == 404:
		return {"status": "missing", "data": {}}
	if code < 200 or code >= 300:
		return {"status": "error", "data": {}}
	var content := text
	var d: Variant = JSON.parse_string(text) if text.strip_edges().begins_with("{") else null
	if d is Dictionary:
		content = str(d.get("replay_content", d.get("replay", "")))
	var data := decode_replay(content)
	if data.is_empty():
		return {"status": "error", "data": {}}
	return {"status": "ok", "data": data}


func fetch_score(score_id: String, done: Callable) -> void:
	_request("GET", "/score/" + score_id.uri_encode(), null, func(code: int, text: String):
		done.call(parse_score(text) if code >= 200 and code < 300 else {}))


## done(result: Dictionary) mit replay_result().
func fetch_replay(score_id: String, done: Callable) -> void:
	_request("GET", "/score/%s/replay" % score_id.uri_encode(), null, func(code: int, text: String):
		done.call(replay_result(code, text)))


# --- HTTP ---------------------------------------------------------------------

func _request(method: String, path: String, body: Variant, done: Callable) -> void:
	if not active():
		done.call(0, "")
		return
	var text := "" if body == null else JSON.stringify(body)
	var url := online.base_url + path
	if transport.is_valid():
		transport.call(method, url, online.headers(), text, done)
		return
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	req.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		done.call(code, data.get_string_from_utf8()))
	var m := HTTPClient.METHOD_GET
	match method:
		"POST": m = HTTPClient.METHOD_POST
		"DELETE": m = HTTPClient.METHOD_DELETE
	if req.request(url, online.headers(), m, text) != OK:
		req.queue_free()
		done.call(0, "")


func refresh_unread() -> void:
	if _busy_unread:
		return
	_busy_unread = true
	_request("GET", "/game/chat/unread", null, func(code: int, text: String):
		_busy_unread = false
		if code >= 200 and code < 300:
			set_unread(parse_unread(text)))


func set_unread(n: int) -> void:
	if n != unread:
		unread = n
		unread_changed.emit(n)


func refresh_conversations() -> void:
	_request("GET", "/game/chat/conversations", null, func(code: int, text: String):
		if code < 200 or code >= 300:
			return
		conversations = parse_conversations(text)
		set_unread(total_unread(conversations))
		conversations_changed.emit())


func load_messages(conv_id: String, before: String = "") -> void:
	var path := "/game/chat/conversations/%s/messages?limit=%d" % [conv_id.uri_encode(), MESSAGE_LIMIT]
	if before != "":
		path += "&before=" + before.uri_encode()
	_request("GET", path, null, func(code: int, text: String):
		if code < 200 or code >= 300:
			return
		var r := parse_messages(text)
		var cid: String = r.conversation_id if r.conversation_id != "" else conv_id
		messages[cid] = merge_messages(messages.get(cid, []), r.messages)
		messages_changed.emit(cid)
		if cid == open_id:
			mark_read(cid))


## Neue Liste aus alt + neu, ohne Doppelte, nach Zeit sortiert.
static func merge_messages(old: Array, fresh: Array) -> Array:
	var seen := {}
	var out: Array = []
	for m in old + fresh:
		var id := str(m.get("id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		out.append(m)
	out.sort_custom(func(a, b): return str(a.created_at) < str(b.created_at))
	return out


func poll_open() -> void:
	refresh_conversations()
	if open_id == "" or _busy_open:
		return
	_busy_open = true
	var cid := open_id
	_request("GET", "/game/chat/conversations/%s/messages?limit=%d" % [cid.uri_encode(), MESSAGE_LIMIT],
		null, func(code: int, text: String):
			_busy_open = false
			if code < 200 or code >= 300:
				return
			var r := parse_messages(text)
			messages[cid] = merge_messages(messages.get(cid, []), r.messages)
			messages_changed.emit(cid)
			if cid == open_id:
				mark_read(cid))


func open_conversation(conv_id: String) -> void:
	open_id = conv_id
	if conv_id != "":
		load_messages(conv_id)


func mark_read(conv_id: String) -> void:
	for c in conversations:
		if c.id == conv_id and int(c.unread) > 0:
			c.unread = 0
			set_unread(total_unread(conversations))
			conversations_changed.emit()
			_request("POST", "/game/chat/conversations/%s/read" % conv_id.uri_encode(), {},
				func(_c: int, _t: String): pass)
			return


## Nachricht an Nutzer (startet ggf. neue Unterhaltung). done(ok, conversation_id)
func send_to_user(username: String, content: String, reply_to_id: String, done: Callable) -> void:
	var body := {"content": clean(content)}
	if reply_to_id != "":
		body["reply_to_id"] = reply_to_id
	_request("POST", "/game/chat/send/" + username.uri_encode(), body, func(code: int, text: String):
		var r := parse_send(text)
		var ok: bool = code >= 200 and code < 300 and r.ok
		if ok:
			open_id = r.conversation_id
			load_messages(r.conversation_id)
			refresh_conversations()
		done.call(ok, r.conversation_id))


func send_to_conversation(conv_id: String, content: String, reply_to_id: String, done: Callable) -> void:
	var body := {"content": clean(content)}
	if reply_to_id != "":
		body["reply_to_id"] = reply_to_id
	_request("POST", "/game/chat/conversations/%s/messages" % conv_id.uri_encode(), body,
		func(code: int, _text: String):
			var ok := code >= 200 and code < 300
			if ok:
				load_messages(conv_id)
				refresh_conversations()
			done.call(ok, conv_id))


func delete_message(conv_id: String, msg_id: String) -> void:
	_request("DELETE", "/game/chat/messages/" + msg_id.uri_encode(), null, func(code: int, _t: String):
		if code >= 200 and code < 300 and messages.has(conv_id):
			messages[conv_id] = messages[conv_id].filter(func(m): return m.id != msg_id)
			messages_changed.emit(conv_id))


## Nutzersuche. done(users: Array)
func search_users(q: String, done: Callable) -> void:
	_request("GET", "/game/chat/users?q=" + q.uri_encode(), null, func(code: int, text: String):
		done.call(parse_users(text) if code >= 200 and code < 300 else []))
