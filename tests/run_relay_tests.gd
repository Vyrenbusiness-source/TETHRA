extends SceneTree

## Relay-Protokoll (scripts/net/relay_server.gd + relay_peer.gd), alles in einem
## Prozess ueber 127.0.0.1: Raum, Beitritt, Weiterleitung, Version, Host weg,
## Raumliste (WS + HTTP), Grenzen. Start:
##   godot --headless --path . -s tests/run_relay_tests.gd

const RelayServer := preload("res://scripts/net/relay_server.gd")
const RelayPeer := preload("res://scripts/net/relay_peer.gd")

var _failed := 0
var _srv
var _url := ""
var _peers: Array = []


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


## n Frames warten und dabei alle Clients pollen.
func _pump(n: int = 12) -> void:
	for _i in n:
		await process_frame
		for p in _peers:
			p.poll()
		await create_timer(0.01).timeout


func _mk() -> RelayPeer:
	var p := RelayPeer.new()
	_peers.append(p)
	return p


func _track(p: RelayPeer) -> Dictionary:
	var st := { "fail": "", "msg": "", "extra": {}, "hosted": "", "conn": [], "disc": [], "rooms": null }
	p.failed.connect(func(c, m, e): st.fail = c; st.msg = m; st.extra = e)
	p.hosted.connect(func(c): st.hosted = c)
	p.peer_connected.connect(func(i): st.conn.append(i))
	p.peer_disconnected.connect(func(i): st.disc.append(i))
	p.rooms_received.connect(func(r): st.rooms = r)
	return st


func _http_rooms() -> Array:
	var s := StreamPeerTCP.new()
	s.connect_to_host("127.0.0.1", _srv.port)
	for _i in 100:
		s.poll()
		if s.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		await create_timer(0.01).timeout
	s.put_data("GET /tethra/rooms HTTP/1.1\r\nHost: x\r\n\r\n".to_ascii_buffer())
	var buf := PackedByteArray()
	for _i in 100:
		await process_frame
		await create_timer(0.01).timeout
		s.poll()
		var n := s.get_available_bytes()
		if n > 0:
			buf.append_array(s.get_data(n)[1])
		if buf.get_string_from_utf8().contains("]"):
			break
	var txt := buf.get_string_from_utf8()
	var body := txt.substr(txt.find("\r\n\r\n") + 4)
	var j: Variant = JSON.parse_string(body)
	return j if j is Array else []


func _init() -> void:
	await process_frame
	_srv = RelayServer.new()
	root.add_child(_srv)
	_check(_srv.listen(0, "127.0.0.1") == OK, "Server lauscht")
	_url = "ws://127.0.0.1:%d/mp" % _srv.port
	var V := "9.9.9"

	# Raum anlegen
	var host := _mk()
	var hs := _track(host)
	host.host(_url, { "name": "Testraum", "v": V, "map": "Song [Hard]", "mode": "mania", "locked": false })
	await _pump()
	_check(hs.hosted.length() == 6, "Raum-Code mit 6 Zeichen (%s)" % hs.hosted)
	_check(host.get_unique_id() == 1 and host.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Host = Peer 1, verbunden")
	var code: String = hs.hosted

	# Raumliste per HTTP
	var lst := await _http_rooms()
	_check(lst.size() == 1 and str(lst[0].code) == code and lst[0].name == "Testraum" and int(lst[0].players) == 1
		and int(lst[0].max) == 16 and lst[0].map == "Song [Hard]" and lst[0].mode == "mania"
		and lst[0].version == V and lst[0].locked == false, "HTTP /rooms listet den Raum")

	# Raumliste per WebSocket
	var lp := _mk()
	var ls := _track(lp)
	lp.list(_url)
	await _pump()
	_check(ls.rooms is Array and ls.rooms.size() == 1 and str(ls.rooms[0].code) == code, "WS list liefert den Raum")

	# Beitritt
	var c1 := _mk()
	var s1 := _track(c1)
	c1.join(_url, code.to_lower(), V)
	await _pump()
	_check(c1.get_unique_id() == 2 and s1.conn == [1], "Client bekommt ID 2 und sieht Host")
	_check(hs.conn == [2], "Host sieht Peer 2")

	# Weiterleitung
	var c2 := _mk()
	var s2 := _track(c2)
	c2.join(_url, code, V)
	await _pump()
	_check(c2.get_unique_id() == 3 and hs.conn == [2, 3], "zweiter Client ID 3")
	host.set_target_peer(0)
	host.put_packet("hallo".to_utf8_buffer())
	await _pump()
	_check(c1.get_available_packet_count() == 1 and c2.get_available_packet_count() == 1, "Broadcast des Hosts an alle")
	_check(c1.get_packet_peer() == 1 and c1.get_packet().get_string_from_utf8() == "hallo", "Paket traegt Absender 1")
	c2.get_packet()
	host.set_target_peer(3)
	host.put_packet("nur3".to_utf8_buffer())
	await _pump()
	_check(c1.get_available_packet_count() == 0 and c2.get_available_packet_count() == 1, "Einzelziel nur an Peer 3")
	c2.get_packet()
	host.set_target_peer(-2)
	host.put_packet("ohne2".to_utf8_buffer())
	await _pump()
	_check(c1.get_available_packet_count() == 0 and c2.get_available_packet_count() == 1, "Broadcast ausser Peer 2")
	c2.get_packet()
	c1.set_target_peer(3)
	c1.put_packet("an3?".to_utf8_buffer())
	await _pump()
	_check(host.get_available_packet_count() == 1 and c2.get_available_packet_count() == 0, "Client-Pakete gehen nur zum Host")
	_check(host.get_packet_peer() == 2 and host.get_packet().get_string_from_utf8() == "an3?", "Host sieht Absender 2")

	# Versionspruefung
	var cv := _mk()
	var sv := _track(cv)
	cv.join(_url, code, "1.0.0")
	await _pump()
	_check(sv.fail == "version" and sv.msg.contains("Update noetig (Host v9.9.9)") and sv.extra.host_v == V, "Falsche Version abgewiesen: " + sv.msg)
	var cn := _mk()
	var sn := _track(cn)
	cn.join(_url, "ZZZZZZ", V)
	await _pump()
	_check(sn.fail == "notfound", "Unbekannter Code")

	# Gesperrter Raum: Liste ohne Code
	host.update_info({ "name": "Geheim", "locked": true, "map": "X", "mode": "orbit" })
	await _pump()
	lst = await _http_rooms()
	_check(lst.size() == 1 and lst[0].code == "" and lst[0].locked == true and lst[0].name == "Geheim"
		and int(lst[0].players) == 3 and lst[0].mode == "orbit", "Gesperrter Raum ohne Code, 3 Spieler")

	# Kick
	host.disconnect_peer(3)
	await _pump()
	_check(s2.fail == "closed" or s2.disc.has(1), "Kick trennt Peer 3")
	_check(hs.disc == [3], "Host bekommt peer-disconnect 3")

	# Timeout: Client ohne Lebenszeichen fliegt raus
	for c in _srv._conns:
		if c.id == 2:
			c.idle = 99.0
	await _pump()
	_check(hs.disc.has(2) and s1.fail == "closed", "Timeout 20 s wirft Peer 2 raus")

	# Raum voll: Host + 15 = 16
	var many: Array = []
	for i in 15:
		var p := _mk()
		var st := _track(p)
		p.join(_url, code, V)
		many.append([p, st])
	await _pump(80)
	var ok_n := 0
	for m in many:
		if m[0].get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			ok_n += 1
	_check(ok_n == 15, "15 Beitretende + Host = 16 Spieler")
	var cf := _mk()
	var sf := _track(cf)
	cf.join(_url, code, V)
	await _pump()
	_check(sf.fail == "full", "17. Spieler: Raum voll")

	# Paketgroesse
	var big: RelayPeer = many[0][0]
	var bs: Dictionary = many[0][1]
	var huge := PackedByteArray()
	huge.resize(70000)
	big._ws.send(huge, WebSocketPeer.WRITE_MODE_BINARY)
	await _pump(20)
	_check(bs.fail == "closed", "Ueberlanges Paket trennt die Verbindung")

	# Rate-Limit
	var rl: RelayPeer = many[1][0]
	var rs: Dictionary = many[1][1]
	var pkt := PackedByteArray()
	pkt.resize(8)
	for _i in 1500:
		rl._ws.send(pkt, WebSocketPeer.WRITE_MODE_BINARY)
	await _pump(20)
	_check(rs.fail == "closed", "Rate-Limit trennt Dauerfeuer")

	# Host weg = Raum zu
	var os: Dictionary = many[2][1]
	host.close()
	await _pump(20)
	_check(os.fail == "closed" and "Host" in os.msg, "Host weg: Mitspieler bekommen closed")
	lst = await _http_rooms()
	_check(lst.is_empty(), "Raum aus der Liste verschwunden")
	var cj := _mk()
	var sj := _track(cj)
	cj.join(_url, code, V)
	await _pump()
	_check(sj.fail == "notfound", "Beitritt in geschlossenen Raum scheitert")

	# Nicht erreichbar
	var cu := _mk()
	var su := _track(cu)
	cu.join("ws://127.0.0.1:1/mp", "AAAAAA", V)
	for _i in 800:
		if su.fail != "":
			break
		await _pump(2)
	_check(su.fail == "unreachable", "Server nicht erreichbar gemeldet")

	_srv.stop()
	print("RELAY TESTS: ", "OK" if _failed == 0 else "%d FEHLER" % _failed)
	quit(0 if _failed == 0 else 1)

