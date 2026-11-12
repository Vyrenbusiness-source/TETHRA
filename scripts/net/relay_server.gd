extends Node

## Relay-Server fuer Online-Multiplayer (nur TCP/WebSocket, kein UDP).
## Start headless:  godot --headless --main-pack TETHRA.pck --mp-relay --port 47900
## Protokoll: docs/net/relay.md. Ein Port: WebSocket (Spiel) + HTTP GET /rooms.
##
## Binaerframes tragen Spieldaten:  [i32 to LE][u8 mode][u8 channel][payload]
## (Client -> Relay) und [i32 from LE][u8 mode][u8 channel][payload] (Relay -> Client).
## Beitretende senden immer nur an den Host (wie ENet); der Host adressiert
## 0 = alle, >0 = ein Peer, <0 = alle ausser -to.
## Textframes sind JSON-Steuernachrichten ("t": host/join/list/info/ping/kick).

const MAX_PLAYERS := 16
const MAX_FRAME := 65536
const MAX_ROOMS := 300
const MAX_CONNS := 800
const TIMEOUT := 20.0
const HANDSHAKE_TIMEOUT := 5.0
const MAX_HEAD := 8192
## Rate-Limit pro Verbindung: Nachrichten/s und Bytes/s (Token-Bucket).
const RATE_MSGS := 400.0
const RATE_BYTES := 600000.0
const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

var _tcp := TCPServer.new()
var _conns: Array = []
## code -> {code, name, map, mode, locked, version, host: conn, peers: {id: conn}, next_id}
var rooms: Dictionary = {}
var port := 0
var _rng := RandomNumberGenerator.new()


func listen(p_port: int, bind: String = "*") -> Error:
	_rng.randomize()
	var err := _tcp.listen(p_port, bind)
	if err == OK:
		port = p_port if p_port != 0 else _tcp.get_local_port()
	return err


func stop() -> void:
	for c in _conns.duplicate():
		_drop(c)
	_tcp.stop()


func _process(delta: float) -> void:
	step(delta)


## Ein Server-Tick (auch von Tests ohne Szenenbaum aufrufbar).
func step(delta: float) -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var s := _tcp.take_connection()
		if _conns.size() >= MAX_CONNS:
			s.disconnect_from_host()
			continue
		_conns.append({ "s": s, "state": "head", "buf": PackedByteArray(), "age": 0.0,
			"idle": 0.0, "code": "", "id": 0, "ver": "", "msgs": RATE_MSGS,
			"bytes": RATE_BYTES, "frag": PackedByteArray(), "fragop": 0 })
	for c in _conns.duplicate():
		if not _conns.has(c):
			continue
		var s: StreamPeerTCP = c.s
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(c)
			continue
		c.idle += delta
		c.msgs = minf(RATE_MSGS * 2.0, c.msgs + RATE_MSGS * delta)
		c.bytes = minf(RATE_BYTES * 2.0, c.bytes + RATE_BYTES * delta)
		var n := s.get_available_bytes()
		if n > 0:
			var r := s.get_data(n)
			if r[0] == OK:
				c.buf.append_array(r[1])
				c.idle = 0.0
		if c.state == "head":
			c.age += delta
			if c.age > HANDSHAKE_TIMEOUT:
				_drop(c)
			else:
				_handshake(c)
		elif c.state == "ws":
			_read_frames(c)
			if _conns.has(c) and c.idle > TIMEOUT:
				_drop(c)
		elif c.state == "close":
			c.age += delta
			if c.age > 1.0:
				_drop(c)


# ---------------------------------------------------------------------------
# HTTP / Handshake
# ---------------------------------------------------------------------------

func _handshake(c: Dictionary) -> void:
	var buf: PackedByteArray = c.buf
	if buf.size() > MAX_HEAD:
		_drop(c)
		return
	var txt := buf.get_string_from_ascii()
	var end := txt.find("\r\n\r\n")
	if end < 0:
		return
	var lines := txt.substr(0, end).split("\r\n")
	var req := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var k := lines[i].find(":")
		if k > 0:
			headers[lines[i].substr(0, k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
	var path := req[1] if req.size() > 1 else "/"
	var q := path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	if req[0] != "GET":
		_http(c, 405, "text/plain", "method not allowed")
	elif str(headers.get("upgrade", "")).to_lower() == "websocket" and headers.has("sec-websocket-key"):
		var hc := HashingContext.new()
		hc.start(HashingContext.HASH_SHA1)
		hc.update((str(headers["sec-websocket-key"]) + WS_GUID).to_utf8_buffer())
		var accept := Marshalls.raw_to_base64(hc.finish())
		var resp := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept
		c.s.put_data(resp.to_ascii_buffer())
		c.state = "ws"
		c.buf = buf.slice(end + 4)
		c.idle = 0.0
	elif path.ends_with("/rooms"):
		_http(c, 200, "application/json", JSON.stringify(room_list()))
	elif path.ends_with("/health"):
		_http(c, 200, "text/plain", "ok")
	else:
		_http(c, 404, "text/plain", "not found")


func _http(c: Dictionary, code: int, ctype: String, body: String) -> void:
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [
		code, "OK" if code == 200 else "Error", ctype, b.size()]
	var out := head.to_ascii_buffer()
	out.append_array(b)
	c.s.put_data(out)
	c.state = "close"
	c.age = 0.0


# ---------------------------------------------------------------------------
# WebSocket-Frames
# ---------------------------------------------------------------------------

func _read_frames(c: Dictionary) -> void:
	while _conns.has(c) and c.state == "ws":
		var b: PackedByteArray = c.buf
		if b.size() < 2:
			return
		var op: int = b[0] & 0x0F
		var fin: bool = (b[0] & 0x80) != 0
		var masked: bool = (b[1] & 0x80) != 0
		var ln: int = b[1] & 0x7F
		var pos := 2
		if ln == 126:
			if b.size() < 4:
				return
			ln = (b[2] << 8) | b[3]
			pos = 4
		elif ln == 127:
			if b.size() < 10:
				return
			ln = 0
			for i in 8:
				ln = (ln << 8) | b[2 + i]
			pos = 10
		if ln > MAX_FRAME or ln < 0 or not masked:
			_drop(c)  # zu gross oder Client-Frame ohne Maske
			return
		if b.size() < pos + 4 + ln:
			return
		var mask := b.slice(pos, pos + 4)
		var data := b.slice(pos + 4, pos + 4 + ln)
		for i in ln:
			data[i] = data[i] ^ mask[i & 3]
		c.buf = b.slice(pos + 4 + ln)
		c.msgs -= 1.0
		c.bytes -= float(ln + 8)
		if c.msgs < 0.0 or c.bytes < 0.0:
			_send_json(c, { "t": "err", "code": "rate", "msg": "Zu viele Nachrichten." })
			_drop(c)
			return
		match op:
			0x8:
				_drop(c)
				return
			0x9:
				_send_frame(c, 0xA, data)
			0xA:
				pass
			_:
				if op == 0:
					c.frag.append_array(data)
					if c.frag.size() > MAX_FRAME:
						_drop(c)
						return
					if fin:
						_on_message(c, c.fragop, c.frag)
						c.frag = PackedByteArray()
				elif fin:
					_on_message(c, op, data)
				else:
					c.fragop = op
					c.frag = data


func _send_frame(c: Dictionary, op: int, data: PackedByteArray) -> void:
	var s: StreamPeerTCP = c.s
	if s.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var out := PackedByteArray()
	out.append(0x80 | op)
	if data.size() < 126:
		out.append(data.size())
	elif data.size() < 65536:
		out.append(126)
		out.append(data.size() >> 8)
		out.append(data.size() & 0xFF)
	else:
		out.append(127)
		for i in 8:
			out.append((data.size() >> (56 - 8 * i)) & 0xFF)
	out.append_array(data)
	s.put_data(out)


func _send_json(c: Dictionary, msg: Dictionary) -> void:
	_send_frame(c, 0x1, JSON.stringify(msg).to_utf8_buffer())


# ---------------------------------------------------------------------------
# Nachrichten
# ---------------------------------------------------------------------------

func _on_message(c: Dictionary, op: int, data: PackedByteArray) -> void:
	if op == 0x2:
		_on_data(c, data)
		return
	if op != 0x1:
		return
	var m: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"ping":
			_send_json(c, { "t": "pong" })
		"list":
			_send_json(c, { "t": "rooms", "rooms": room_list() })
		"host":
			_on_host(c, m)
		"join":
			_on_join(c, m)
		"info":
			if c.code != "" and rooms.has(c.code) and rooms[c.code].host == c:
				var r: Dictionary = rooms[c.code]
				r.name = str(m.get("name", r.name)).substr(0, 28)
				r.map = str(m.get("map", r.map)).substr(0, 80)
				r.mode = str(m.get("mode", r.mode)).substr(0, 12)
				r.kind = str(m.get("kind", r.get("kind", ""))).substr(0, 12)
				r.locked = bool(m.get("locked", r.locked))
		"kick":
			if c.code != "" and rooms.has(c.code) and rooms[c.code].host == c:
				var r: Dictionary = rooms[c.code]
				var pc: Variant = r.peers.get(int(m.get("id", 0)))
				if pc != null:
					_drop(pc)


func _on_host(c: Dictionary, m: Dictionary) -> void:
	if c.code != "":
		return
	if rooms.size() >= MAX_ROOMS:
		_send_json(c, { "t": "err", "code": "busy", "msg": "Server ausgelastet." })
		return
	var code := ""
	for _i in 20:
		code = ""
		for _j in 6:
			code += CODE_ALPHABET[_rng.randi() % CODE_ALPHABET.length()]
		if not rooms.has(code):
			break
	if rooms.has(code):
		_send_json(c, { "t": "err", "code": "busy", "msg": "Server ausgelastet." })
		return
	c.ver = str(m.get("v", "")).substr(0, 20)
	c.code = code
	c.id = 1
	rooms[code] = { "code": code, "name": str(m.get("name", "")).substr(0, 28),
		"map": str(m.get("map", "")).substr(0, 80), "mode": str(m.get("mode", "mania")).substr(0, 12),
		"kind": str(m.get("kind", "")).substr(0, 12),
		"locked": bool(m.get("locked", false)), "version": c.ver, "host": c,
		"peers": {}, "next_id": 2 }
	_send_json(c, { "t": "hosted", "code": code, "id": 1, "max": MAX_PLAYERS })


func _on_join(c: Dictionary, m: Dictionary) -> void:
	if c.code != "":
		return
	var code := str(m.get("code", "")).strip_edges().to_upper()
	var ver := str(m.get("v", "")).substr(0, 20)
	if not rooms.has(code):
		_send_json(c, { "t": "err", "code": "notfound", "msg": "Raum nicht gefunden." })
		return
	var r: Dictionary = rooms[code]
	if str(r.version) != ver:
		_send_json(c, { "t": "err", "code": "version", "msg": "Update noetig (Host v%s)." % r.version,
			"host_v": r.version })
		return
	if r.peers.size() + 1 >= MAX_PLAYERS:
		_send_json(c, { "t": "err", "code": "full", "msg": "Raum voll." })
		return
	var id: int = r.next_id
	r.next_id += 1
	c.ver = ver
	c.code = code
	c.id = id
	r.peers[id] = c
	_send_json(c, { "t": "joined", "id": id, "host": 1, "code": code })
	_send_json(r.host, { "t": "peer+", "id": id })


func _on_data(c: Dictionary, data: PackedByteArray) -> void:
	if c.code == "" or not rooms.has(c.code) or data.size() < 6:
		return
	var r: Dictionary = rooms[c.code]
	var to := data.decode_s32(0)
	var out := data.duplicate()
	out.encode_s32(0, c.id)
	if c.id != 1:
		# Beitretende sprechen nur mit dem Host.
		_send_frame(r.host, 0x2, out)
		return
	if to > 0:
		var pc: Variant = r.peers.get(to)
		if pc != null:
			_send_frame(pc, 0x2, out)
		return
	for id in r.peers:
		if to < 0 and id == -to:
			continue
		_send_frame(r.peers[id], 0x2, out)


# ---------------------------------------------------------------------------
# Verbindungen / Raeume
# ---------------------------------------------------------------------------

func _drop(c: Dictionary) -> void:
	if not _conns.has(c):
		return
	_conns.erase(c)
	var code: String = c.code
	if code != "" and rooms.has(code):
		var r: Dictionary = rooms[code]
		if r.host == c:
			# Host weg = Raum zu.
			rooms.erase(code)
			for id in r.peers:
				var pc: Dictionary = r.peers[id]
				pc.code = ""
				_send_json(pc, { "t": "closed" })
				_close_later(pc)
		else:
			r.peers.erase(c.id)
			if _conns.has(r.host):
				_send_json(r.host, { "t": "peer-", "id": c.id })
	c.code = ""
	c.s.disconnect_from_host()


func _close_later(c: Dictionary) -> void:
	# Kein Close-Frame: der Client schliesst selbst, nachdem er "closed" gelesen hat.
	c.state = "close"
	c.age = 0.0


## Oeffentliche Raumliste. Gesperrte (Passwort-)Raeume ohne Code.
func room_list() -> Array:
	var out: Array = []
	for code in rooms:
		var r: Dictionary = rooms[code]
		out.append({ "code": "" if r.locked else code, "name": r.name,
			"players": r.peers.size() + 1, "max": MAX_PLAYERS, "map": r.map,
			"mode": r.mode, "kind": r.get("kind", ""), "version": r.version, "locked": r.locked })
	return out
