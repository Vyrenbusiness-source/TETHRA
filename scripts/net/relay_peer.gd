extends MultiplayerPeerExtension

## MultiplayerPeer ueber einen WebSocket-Relay (scripts/net/relay_server.gd).
## Ersetzt ENet: Host = Peer 1, Beitretende bekommen ihre ID vom Relay.
## Alles laeuft zuverlaessig + geordnet (TCP), der Transfer-Modus ist egal.

const DEFAULT_URL := "wss://butzebot.com/tethra/mp"
const PING_EVERY := 5.0
const CONNECT_TIMEOUT := 8.0

## Verbindung/Anmeldung gescheitert oder Raum zu: code = notfound|version|full|
## unreachable|closed|busy|rate, msg = Klartext vom Relay, extra = {host_v}.
signal failed(code: String, msg: String, extra: Dictionary)
## Host: Relay hat den Raum angelegt.
signal hosted(code: String)
signal rooms_received(rooms: Array)

var _ws := WebSocketPeer.new()
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _id := 0
var _server := false
var _queue: Array = []  # {from, mode, ch, data}
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _chan := 0
var _refuse := false
var _hello: Dictionary = {}
var _sent_hello := false
var _t_ping := 0.0
var _t_conn := 0.0
var _opened := false
var room_code := ""
var _last_ms := Time.get_ticks_msec()


## Relay-URL: --relay-url=<url> ueberschreibt die Konstante (lokale Tests).
static func relay_url() -> String:
	for a in OS.get_cmdline_args():
		if a.begins_with("--relay-url="):
			return a.trim_prefix("--relay-url=")
	return DEFAULT_URL


## HTTP-Adresse der Raumliste zum selben Relay.
static func rooms_url(url: String = "") -> String:
	var u := url if url != "" else relay_url()
	u = u.replace("wss://", "https://").replace("ws://", "http://")
	if u.ends_with("/mp"):
		return u.trim_suffix("/mp") + "/rooms"
	return u.rstrip("/") + "/rooms"


func host(url: String, info: Dictionary) -> Error:
	_server = true
	_hello = info.duplicate()
	_hello["t"] = "host"
	return _open(url)


func join(url: String, code: String, version: String) -> Error:
	_server = false
	_hello = { "t": "join", "code": code, "v": version }
	return _open(url)


## Nur Raumliste per WebSocket holen (Nachricht "list"), danach schliessen.
func list(url: String) -> Error:
	_server = false
	_hello = { "t": "list" }
	return _open(url)


## Host: Raumdaten fuer die Liste aktualisieren.
func update_info(info: Dictionary) -> void:
	if _server and _status == MultiplayerPeer.CONNECTION_CONNECTED:
		var m := info.duplicate()
		m["t"] = "info"
		_send_json(m)


func _open(url: String) -> Error:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 262144
	_ws.outbound_buffer_size = 262144
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(url)
	if err != OK:
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_opened = false
	_sent_hello = false
	_t_conn = 0.0
	return OK


func _send_json(m: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(m))


func _fail(code: String, msg: String, extra: Dictionary = {}) -> void:
	var was := _status
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_ws.close()
	if was == MultiplayerPeer.CONNECTION_CONNECTED and not _server:
		peer_disconnected.emit(1)
	failed.emit(code, msg, extra)


# --- MultiplayerPeerExtension ------------------------------------------------

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	var now := Time.get_ticks_msec()
	var dt := minf(1.0, float(now - _last_ms) / 1000.0)
	_last_ms = now
	if st == WebSocketPeer.STATE_OPEN:
		if not _sent_hello:
			_sent_hello = true
			_opened = true
			_send_json(_hello)
		_t_ping += dt
		if _t_ping >= PING_EVERY:
			_t_ping = 0.0
			_send_json({ "t": "ping" })
	# Auch nach dem Close-Frame noch lesen: "closed"/"err" kommen direkt davor an.
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_on_text(pkt.get_string_from_utf8())
		else:
			_on_bin(pkt)
		if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
	if st == WebSocketPeer.STATE_OPEN:
		pass
	elif st == WebSocketPeer.STATE_CONNECTING:
		_t_conn += dt
		if _t_conn > CONNECT_TIMEOUT:
			_fail("unreachable", "Server nicht erreichbar.")
	elif st == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		if _opened:
			_fail("closed", "Verbindung zum Relay verloren.")
		else:
			_fail("unreachable", "Server nicht erreichbar.")


func _on_text(txt: String) -> void:
	var m: Variant = JSON.parse_string(txt)
	if not (m is Dictionary):
		return
	match str(m.get("t", "")):
		"hosted":
			_id = 1
			room_code = str(m.get("code", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			hosted.emit(room_code)
		"joined":
			_id = int(m.get("id", 0))
			room_code = str(m.get("code", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			peer_connected.emit(1)
		"peer+":
			peer_connected.emit(int(m.get("id", 0)))
		"peer-":
			peer_disconnected.emit(int(m.get("id", 0)))
		"closed":
			_fail("closed", "Der Host hat den Raum geschlossen.")
		"rooms":
			rooms_received.emit(m.get("rooms", []))
			if _hello.get("t", "") == "list":
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
				_ws.close()
		"err":
			_fail(str(m.get("code", "")), str(m.get("msg", "")), { "host_v": str(m.get("host_v", "")) })


func _on_bin(pkt: PackedByteArray) -> void:
	if pkt.size() < 6 or _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_queue.append({ "from": pkt.decode_s32(0), "mode": pkt[4], "ch": pkt[5], "data": pkt.slice(6) })


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front().data


func _put_packet_script(buf: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNCONFIGURED
	var out := PackedByteArray()
	out.resize(6)
	out.encode_s32(0, _target)
	out[4] = _mode
	out[5] = _chan
	out.append_array(buf)
	return _ws.send(out)


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_max_packet_size() -> int:
	return 60000


func _get_packet_peer() -> int:
	return 1 if _queue.is_empty() else int(_queue[0].from)


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE if _queue.is_empty() else int(_queue[0].mode)


func _get_packet_channel() -> int:
	return 0 if _queue.is_empty() else int(_queue[0].ch)


func _set_transfer_channel(c: int) -> void:
	_chan = c


func _get_transfer_channel() -> int:
	return _chan


func _set_transfer_mode(m: MultiplayerPeer.TransferMode) -> void:
	_mode = m


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(p: int) -> void:
	_target = p


func _is_server() -> bool:
	return _server


func _is_server_relay_supported() -> bool:
	return true


func _close() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()
	_queue.clear()


func _disconnect_peer(p: int, _force: bool) -> void:
	if _server:
		_send_json({ "t": "kick", "id": p })


func _get_unique_id() -> int:
	return _id


func _set_refuse_new_connections(r: bool) -> void:
	_refuse = r


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status
