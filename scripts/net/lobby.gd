extends Node

## Autoload "Lobby": simpler Multiplayer OHNE IP-Eingabe.
##  - Host: UPnP oeffnet den Port automatisch am Router; aus externer IP+Port
##    wird ein kurzer RAUM-CODE (z.B. "7K3F9-A2QX"). Mitspieler tippen nur
##    den Code — nie eine IP.
##  - Im selben Netzwerk (LAN) erscheinen Raeume zusaetzlich automatisch.
##  - Krone: der Host traegt sie initial und kann sie weitergeben; wer die
##    Krone hat, waehlt die Map. Fehlt einem Spieler die Map, laedt er sie
##    automatisch vom Mirror (Set-ID).
##  - Live-Scores + Finals laufen als RPCs ueber denselben Peer.

const GAME_PORT := 47810
const DISCOVERY_PORT := 47811
const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
## Oeffentliches Raum-Verzeichnis (ntfy.sh-Topic als kostenloses Rendezvous):
## Hosts OHNE Passwort announcen Code+Name+Spielerzahl, Browser pollen die
## Liste — offene Raeume erscheinen weltweit automatisch.
const ROOMS_URL := "https://ntfy.sh/tethra-rooms-v1"

signal rooms_changed
signal players_changed
signal map_changed
signal scores_changed
signal game_start
signal skip_now
signal left(reason: String)
signal status(msg: String)

var active := false
var is_host := false
var in_game := false
var room_name := ""
var room_code := ""
## Optionales Raum-Passwort: gesetzt -> Raum NICHT oeffentlich gelistet,
## Beitritt nur mit Passwort (Code-Feld + Passwort).
var password := ""
var _join_pw := ""
## Oeffentliche Raeume: code -> {name, players, t (unix)}.
var online_rooms: Dictionary = {}
var _announce_t := 0.0
var _fetch_req: HTTPRequest
## peer_id -> {name, ready, score, combo, acc, final}
var players: Dictionary = {}
var crown_id := 1
## {set_id, file, version, title, artist, stars}
var sel_map: Dictionary = {}
## LAN-Discovery: ip -> {name, players, t}
var lan_rooms: Dictionary = {}
## Intro-Skip: peer_id -> true; erst wenn ALLE gedrueckt haben, wird gesprungen.
var skip_votes: Dictionary = {}
## In dieser Session bereits ZUSAMMEN gespielte Maps ("file|version").
var played: Array = []

var _bcast: PacketPeerUDP
var _listen: PacketPeerUDP
var _bcast_t := 0.0
var _upnp_thread: Thread
var _upnp: UPNP


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func():
		_reset()
		left.emit("Verbindung fehlgeschlagen — Code richtig? Host online?"))
	multiplayer.server_disconnected.connect(func():
		_reset()
		left.emit("Der Host hat den Raum geschlossen."))


func _new_player(pname: String) -> Dictionary:
	return { "name": pname, "ready": false, "score": 0, "combo": 0,
		"acc": 1.0, "final": {} }


# ---------------------------------------------------------------------------
# Hosten
# ---------------------------------------------------------------------------

func host_room(rname: String = "", pw: String = "") -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(GAME_PORT, 7) != OK:
		status.emit("Port %d belegt — laeuft schon ein Raum?" % GAME_PORT)
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	room_name = rname.strip_edges().substr(0, 28)
	if room_name == "":
		room_name = "%s's Raum" % Settings.profile_name
	password = pw.strip_edges()
	_announce_t = 0.0
	crown_id = 1
	players = { 1: _new_player(Settings.profile_name) }
	players[1].ready = true
	room_code = ""
	# LAN-Ansage.
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	# UPnP im Thread — Router-Discovery darf die UI nicht blockieren.
	status.emit("Oeffne Port am Router (UPnP)…")
	_upnp_thread = Thread.new()
	_upnp_thread.start(_setup_upnp)
	players_changed.emit()
	return true


func _setup_upnp() -> void:
	_upnp = UPNP.new()
	var ip := ""
	# Zwei Anlaeufe mit grosszuegigem Timeout — manche Router antworten traege.
	for attempt in 2:
		if _upnp.discover(3000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
				and _upnp.get_gateway() != null and _upnp.get_gateway().is_valid_gateway():
			_upnp.add_port_mapping(GAME_PORT, GAME_PORT, "TETHRA", "UDP", 0)
			ip = _upnp.query_external_address()
			break
	call_deferred("_upnp_done", ip)


func _upnp_done(ip: String) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not is_host:
		return
	if ip != "":
		room_code = _encode_code(ip, GAME_PORT)
		status.emit("Raum offen! Code zum Teilen: %s" % room_code)
		players_changed.emit()
	else:
		# Fallback: externe IP per HTTPS — der Code funktioniert dann,
		# wenn UPnP still war oder der Port bereits freigegeben ist.
		status.emit("UPnP still — ermittle externe IP…")
		_fetch_external_ip()


func _fetch_external_ip() -> void:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result, rcode, _h, body):
		req.queue_free()
		if not is_host:
			return
		if result == HTTPRequest.RESULT_SUCCESS and rcode == 200:
			var ip: String = body.get_string_from_utf8().strip_edges()
			if ip.split(".").size() == 4:
				room_code = _encode_code(ip, GAME_PORT)
				status.emit("Raum-Code: %s  (falls Beitritt scheitert: Port %d im Router freigeben)" % [room_code, GAME_PORT])
				players_changed.emit()
				return
		status.emit("Keine externe IP ermittelbar — Raum nur im eigenen Netzwerk sichtbar."))
	if req.request("https://api.ipify.org") != OK:
		req.queue_free()
		status.emit("Keine externe IP ermittelbar — Raum nur im eigenen Netzwerk sichtbar.")


# ---------------------------------------------------------------------------
# Beitreten (Code oder LAN)
# ---------------------------------------------------------------------------

func join_code(code: String, pw: String = "") -> bool:
	var dec := _decode_code(code)
	if dec.is_empty():
		status.emit("Ungueltiger Raum-Code.")
		return false
	_join_pw = pw.strip_edges()
	return _join(dec.ip, dec.port)


func join_lan(ip: String) -> bool:
	return _join(ip, GAME_PORT)


func _join(ip: String, port: int) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		status.emit("Verbindung nicht moeglich.")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	status.emit("Verbinde…")
	return true


func _on_connected_to_server() -> void:
	rpc_id(1, "srv_register", Settings.profile_name, _join_pw)


func leave() -> void:
	_reset()


func _exit_tree() -> void:
	# Laufenden UPnP-Thread sauber beenden (sonst Crash beim Schliessen).
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null


func _reset() -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null:
		var u := _upnp
		_upnp = null
		var t := Thread.new()
		t.start(func():
			u.delete_port_mapping(GAME_PORT, "UDP")
			t.wait_to_finish.call_deferred())
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_bcast = null
	active = false
	is_host = false
	in_game = false
	room_code = ""
	password = ""
	_join_pw = ""
	players = {}
	sel_map = {}
	played = []
	crown_id = 1


# ---------------------------------------------------------------------------
# LAN-Discovery
# ---------------------------------------------------------------------------

func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	_listen.bind(DISCOVERY_PORT)
	lan_rooms = {}


func stop_discovery() -> void:
	if _listen != null:
		_listen.close()
	_listen = null


func _process(delta: float) -> void:
	# Host: Raum im LAN ansagen (1x pro Sekunde; nur ohne Passwort).
	if is_host and active and not in_game and password == "":
		if _bcast != null:
			_bcast_t -= delta
			if _bcast_t <= 0.0:
				_bcast_t = 1.0
				var msg := JSON.stringify({ "tethra": 1, "name": room_name,
					"players": players.size(), "code": room_code })
				_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
				_bcast.put_packet(msg.to_utf8_buffer())
		# Weltweit ansagen (alle 20s), sobald der Raum-Code steht.
		if room_code != "" and DisplayServer.get_name() != "headless":
			_announce_t -= delta
			if _announce_t <= 0.0:
				_announce_t = 20.0
				_announce_room()
	# Browser: Ansagen einsammeln, alte Eintraege verwerfen.
	if _listen != null:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var data: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if data is Dictionary and int(data.get("tethra", 0)) == 1:
				lan_rooms[ip] = { "name": str(data.get("name", "Raum")),
					"players": int(data.get("players", 1)),
					"t": Time.get_ticks_msec() }
				changed = true
		for ip in lan_rooms.keys():
			if Time.get_ticks_msec() - int(lan_rooms[ip].t) > 3500:
				lan_rooms.erase(ip)
				changed = true
		if changed:
			rooms_changed.emit()


## Wurde diese Diff in dieser Session schon zusammen gespielt?
func was_played(file: String, version: String) -> bool:
	return played.has("%s|%s" % [file, version])


## Wurde IRGENDEINE Diff dieses Sets schon zusammen gespielt?
func set_was_played(file: String) -> bool:
	for pk in played:
		if str(pk).begins_with(file + "|"):
			return true
	return false


# ---------------------------------------------------------------------------
# Oeffentliches Raum-Verzeichnis (ntfy.sh)
# ---------------------------------------------------------------------------

## Raum weltweit ansagen (Fire-and-forget POST).
func _announce_room() -> void:
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	var body := JSON.stringify({ "c": room_code, "n": room_name,
		"p": players.size() })
	if req.request(ROOMS_URL, [], HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()


## Oeffentliche Raeume abrufen (Ansagen der letzten ~70s, neueste pro Code).
func fetch_online_rooms() -> void:
	if _fetch_req != null or DisplayServer.get_name() == "headless":
		return
	_fetch_req = HTTPRequest.new()
	_fetch_req.timeout = 8.0
	add_child(_fetch_req)
	_fetch_req.request_completed.connect(func(result, code, _h, body):
		_fetch_req.queue_free()
		_fetch_req = null
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		# Zeitfenster filtert der SERVER (since=70s) — die eigene Uhr kann
		# gegenueber ntfy um Minuten abweichen, lokale Filter waeren falsch.
		# Pro Code gewinnt die neueste Ansage (aktuellste Spielerzahl).
		var found := {}
		var newest := {}
		for line in body.get_string_from_utf8().split("\n"):
			if line.strip_edges() == "":
				continue
			var ev: Variant = JSON.parse_string(line)
			if not (ev is Dictionary) or str(ev.get("event", "")) != "message":
				continue
			var d: Variant = JSON.parse_string(str(ev.get("message", "")))
			if d is Dictionary and str(d.get("c", "")) != "":
				var t := float(ev.get("time", 0))
				if t >= float(newest.get(str(d.c), 0.0)):
					newest[str(d.c)] = t
					found[str(d.c)] = { "name": str(d.get("n", "Raum")),
						"players": int(d.get("p", 1)), "t": t }
		# Eigenen (gerade verlassenen) Raum nicht listen.
		if room_code != "":
			found.erase(room_code)
		online_rooms = found
		rooms_changed.emit())
	if _fetch_req.request(ROOMS_URL + "/json?poll=1&since=70s") != OK:
		_fetch_req.queue_free()
		_fetch_req = null


# ---------------------------------------------------------------------------
# Server-Seite (laeuft nur beim Host)
# ---------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass  # Registrierung kommt per srv_register


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	players.erase(id)
	if crown_id == id:
		crown_id = 1
	_sync()


@rpc("any_peer", "call_remote", "reliable")
func srv_register(pname: String, pw: String = "") -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if password != "" and pw != password:
		rpc_id(id, "cl_kicked", "Falsches Passwort.")
		# Kurz warten, damit der Kick-Grund noch ankommt, dann trennen.
		get_tree().create_timer(0.4, true).timeout.connect(func():
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	players[id] = _new_player(pname.strip_edges().substr(0, 20))
	_sync()


@rpc("authority", "call_remote", "reliable")
func cl_kicked(reason: String) -> void:
	_reset()
	left.emit(reason)


@rpc("any_peer", "call_remote", "reliable")
func srv_set_ready(r: bool) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].ready = r
		_sync()


@rpc("any_peer", "call_remote", "reliable")
func srv_pick_map(data: Dictionary) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != crown_id:
		return
	_apply_map(data)


## Krone weitergeben — nur der Host darf das.
func give_crown(id: int) -> void:
	if is_host and players.has(id):
		crown_id = id
		_sync()


## Map waehlen — nur der Kronentraeger.
func pick_map(data: Dictionary) -> void:
	if not active:
		return
	if is_host:
		if crown_id == 1:
			_apply_map(data)
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_pick_map", data)


func _apply_map(data: Dictionary) -> void:
	sel_map = data
	# Neue Map -> alle muessen sie (ggf. nach Download) neu bestaetigen.
	for id in players:
		players[id].ready = false
	_sync()
	map_changed.emit()


func set_ready(r: bool) -> void:
	if not active:
		return
	if is_host:
		players[1].ready = r
		_sync()
	else:
		rpc_id(1, "srv_set_ready", r)


func all_ready() -> bool:
	if sel_map.is_empty():
		return false
	for id in players:
		if not bool(players[id].ready):
			return false
	return true


func start_game() -> void:
	if not is_host or not all_ready():
		return
	rpc("cl_start")
	cl_start()


func _sync() -> void:
	if not is_host:
		return
	rpc("cl_state", players, crown_id, sel_map, room_name, played)
	players_changed.emit()


# ---------------------------------------------------------------------------
# Client-Seite (laeuft bei allen)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func cl_state(p: Dictionary, crown: int, m: Dictionary, rname: String, played_list: Array = []) -> void:
	var map_was := sel_map.duplicate()
	players = p
	crown_id = crown
	sel_map = m
	room_name = rname
	played = played_list
	players_changed.emit()
	if map_was != sel_map:
		map_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_start() -> void:
	var path := resolve_local_path()
	if path == "":
		status.emit("Map fehlt lokal — Start nicht moeglich.")
		return
	in_game = true
	skip_votes = {}
	if not sel_map.is_empty():
		var pk := "%s|%s" % [str(sel_map.get("file", "")), str(sel_map.get("version", ""))]
		if not played.has(pk):
			played.append(pk)
	for id in players:
		players[id].score = 0
		players[id].combo = 0
		players[id].acc = 1.0
		players[id].final = {}
	if not _load_selection(path):
		in_game = false
		status.emit("Map konnte nicht geladen werden.")
		return
	game_start.emit()
	get_tree().change_scene_to_file("res://scenes/mania_3d.tscn")


## Gewahlte Diff im lokalen Set finden (per Versionsname) und GameSession setzen.
func _load_selection(path: String) -> bool:
	var imp := OszImporter.import(path)
	if not imp.ok:
		return false
	for i in imp.difficulties.size():
		var d = imp.difficulties[i]
		if d.beatmap.version_name() == str(sel_map.get("version", "")):
			GameSession.mods = {}
			GameSession.is_replay = false
			GameSession.replay_events = []
			GameSession.set_selection(path, i, d.beatmap.version_name(),
				d.osu_filename, float(sel_map.get("stars", 0.0)))
			return true
	return false


## Lokale .osz zur gewaehlten Map finden: exakter Dateiname, fuehrende
## Set-ID oder mirror_<id>.osz.
func resolve_local_path() -> String:
	var maps_dir := MapLibrary.default_maps_dir()
	var want_file := str(sel_map.get("file", ""))
	var set_id := int(sel_map.get("set_id", 0))
	var dir := DirAccess.open(maps_dir)
	if dir == null:
		return ""
	for fname in dir.get_files():
		if not fname.to_lower().ends_with(".osz"):
			continue
		if fname == want_file:
			return maps_dir.path_join(fname)
		if set_id > 0:
			var base := fname.get_basename()
			if base == "mirror_%d" % set_id:
				return maps_dir.path_join(fname)
			var head := base.split(" ")[0]
			if head.is_valid_int() and int(head) == set_id:
				return maps_dir.path_join(fname)
	return ""


# ---------------------------------------------------------------------------
# Live-Scores + Finale
# ---------------------------------------------------------------------------

func send_score(score: int, combo: int, acc: float) -> void:
	if not active or not in_game:
		return
	var me := multiplayer.get_unique_id()
	if players.has(me):
		players[me].score = score
		players[me].combo = combo
		players[me].acc = acc
	rpc("cl_score", score, combo, acc)
	scores_changed.emit()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func cl_score(score: int, combo: int, acc: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].score = score
		players[id].combo = combo
		players[id].acc = acc
		scores_changed.emit()


func send_final(stats: Dictionary) -> void:
	if not active or not in_game:
		return
	var me := multiplayer.get_unique_id()
	if players.has(me):
		players[me].final = stats
	rpc("cl_final", stats)
	scores_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func cl_final(stats: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].final = stats
		scores_changed.emit()


## Intro-Skip stimmen: springt erst, wenn ALLE Spieler gedrueckt haben.
func vote_skip() -> void:
	if not active or not in_game:
		return
	var me := multiplayer.get_unique_id()
	if skip_votes.has(me):
		return
	skip_votes[me] = true
	rpc("cl_skip_vote")
	scores_changed.emit()
	_check_skip()


@rpc("any_peer", "call_remote", "reliable")
func cl_skip_vote() -> void:
	skip_votes[multiplayer.get_remote_sender_id()] = true
	scores_changed.emit()
	_check_skip()


func _check_skip() -> void:
	if skip_votes.size() >= players.size():
		skip_votes = {}
		skip_now.emit()


## Nach Rueckkehr in die Lobby: Runde beenden, alle wieder unready.
func round_done() -> void:
	in_game = false
	if is_host:
		for id in players:
			players[id].ready = id == 1 and not sel_map.is_empty()
		_sync()


## Spieler-Liste nach Live-Score sortiert (fuer Scoreboard/Ranking).
func ranked_players() -> Array:
	var list := []
	for id in players:
		var e: Dictionary = players[id].duplicate()
		e["id"] = id
		list.append(e)
	list.sort_custom(func(a, b):
		if int(a.score) != int(b.score):
			return int(a.score) > int(b.score)
		return float(a.acc) > float(b.acc))
	return list


# ---------------------------------------------------------------------------
# Raum-Code: IPv4+Port -> Base32 (ohne 0/O/1/I), Format XXXXX-XXXXX
# ---------------------------------------------------------------------------

static func _encode_code(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for p in parts:
		v = v * 256 + (int(p) & 0xFF)
	v = v * 65536 + port
	var s := ""
	for i in 10:
		s = CODE_ALPHABET[v % 32] + s
		v /= 32
	return "%s-%s" % [s.substr(0, 5), s.substr(5)]


static func _decode_code(code: String) -> Dictionary:
	var c := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if c.length() != 10:
		return {}
	var v := 0
	for ch in c:
		var idx := CODE_ALPHABET.find(ch)
		if idx < 0:
			return {}
		v = v * 32 + idx
	var port := v % 65536
	v /= 65536
	var ip := "%d.%d.%d.%d" % [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
	return { "ip": ip, "port": port }
