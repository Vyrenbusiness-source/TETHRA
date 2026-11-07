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
## Turnier-Zustand hat sich geaendert (auch: Turnier gestartet/beendet -> tournament null).
signal tournament_changed
signal round_ended

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
## Raum-Mods (vom Kronentraeger gewaehlt, fuer alle gleich): {"SV": bool, "NF": bool}
var mods: Dictionary = { "SV": false, "NF": false }
## LAN-Discovery: ip -> {name, players, t}
var lan_rooms: Dictionary = {}
## Intro-Skip: peer_id -> true; erst wenn ALLE gedrueckt haben, wird gesprungen.
var skip_votes: Dictionary = {}
## In dieser Session bereits ZUSAMMEN gespielte Maps ("file|version").
var played: Array = []
## Turnier (null = normaler Raum). Server haelt die Wahrheit, Clients bekommen to_dict().
var tournament: Tournament = null
## Server: Spieler, die die laufende Turnier-Runde gestartet haben.
var _tour_peers: Array = []
## Raum-Modus (Frei/Teams/Royale). Server haelt die Wahrheit, Clients bekommen to_dict.
var mm: MatchMode = MatchMode.new()
var _mm_peers: Array = []
var _mm_live := false
## Ausgeschieden (Royale): ich schaue nur zu, die Runde laeuft ohne mich.
var spectating := false

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


## Gleiche Namen unterscheidbar machen: "Anna", "Anna (2)", "Anna (3)".
func _unique_name(base: String, id: int) -> String:
	if base == "":
		base = "Spieler"
	var taken := {}
	for pid in players:
		if pid != id:
			taken[str(players[pid].name)] = true
	var nm := base
	var n := 2
	while taken.has(nm):
		nm = "%s (%d)" % [base, n]
		n += 1
	return nm


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
	mm = MatchMode.new()
	_mm_live = false
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
	mods = { "SV": false, "NF": false }
	played = []
	crown_id = 1
	_tour_peers = []
	mm = MatchMode.new()
	_mm_peers = []
	_mm_live = false
	spectating = false
	if tournament != null:
		tournament = null
		tournament_changed.emit()


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
	skip_votes.erase(id)
	_mm_refresh()
	# Kronentraeger weg -> Krone geht automatisch an einen verbleibenden Spieler.
	if crown_id == id:
		crown_id = _next_crown()
	_sync()
	if tournament != null:
		_tour_refresh()
		_tour_check_round()
		_tour_sync()
	if in_game:
		scores_changed.emit()
		_check_skip()
		_mode_check_round()


## Naechster Kronentraeger: der Host (id 1), sonst der kleinste verbleibende Peer.
func _next_crown() -> int:
	if players.has(1):
		return 1
	var ids := players.keys()
	ids.sort()
	return int(ids[0]) if not ids.is_empty() else 1


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
	players[id] = _new_player(_unique_name(pname.strip_edges().substr(0, 20), id))
	_mm_refresh()
	_sync()
	if tournament != null:
		_tour_refresh()
		_tour_sync()  # Neue/rejoinende Spieler bekommen den Turnier-Stand
	send_my_scores()  # Neuer Spieler bekommt meine Scores der gewaehlten Map


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


## Krone weitergeben — nur der Kronentraeger darf das.
func give_crown(id: int) -> void:
	if not active or in_game:
		return
	if is_host:
		if crown_id == 1 and players.has(id):
			crown_id = id
			_sync()
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_give_crown", id)


@rpc("any_peer", "call_remote", "reliable")
func srv_give_crown(id: int) -> void:
	if not is_host or in_game:
		return
	if multiplayer.get_remote_sender_id() != crown_id or not players.has(id):
		return
	crown_id = id
	_sync()


@rpc("any_peer", "call_remote", "reliable")
func srv_start() -> void:
	if not is_host or in_game:
		return
	if multiplayer.get_remote_sender_id() != crown_id or not all_ready() or mode_blocker() != "":
		return
	_mode_prepare_round()
	rpc("cl_start")
	cl_start()


## Darf ich starten? Nur der Kronentraeger, wenn alle bereit sind.
func can_start() -> bool:
	return active and not in_game and crown_id == multiplayer.get_unique_id() and all_ready() \
			and mode_blocker() == ""


@rpc("any_peer", "call_remote", "reliable")
func srv_pick_mods(m: Dictionary) -> void:
	if not is_host:
		return
	if multiplayer.get_remote_sender_id() != crown_id:
		return
	_apply_mods(m)


## Mods setzen — nur der Kronentraeger.
func pick_mods(m: Dictionary) -> void:
	if not active:
		return
	if is_host:
		if crown_id == 1:
			_apply_mods(m)
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_pick_mods", m)


func _apply_mods(m: Dictionary) -> void:
	var n := _norm_mods(m)
	if in_game or n == mods or tournament != null:
		return
	mods = n
	# Anderer Mod -> wie ein Kartenwechsel: alle muessen neu bestaetigen.
	for id in players:
		players[id].ready = false
	_sync()


static func _norm_mods(m: Dictionary) -> Dictionary:
	return { "SV": bool(m.get("SV", false)), "NF": bool(m.get("NF", false)) }


## "SV NF" der aktiven Mods ("" wenn keine).
static func mods_text(m: Dictionary) -> String:
	var parts: Array = []
	for k in ["SV", "NF"]:
		if bool(m.get(k, false)):
			parts.append(k)
	return " ".join(parts)


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
	if in_game or data == sel_map or tournament != null:
		return
	sel_map = data
	# Neue Map -> alle muessen sie (ggf. nach Download) neu bestaetigen.
	for id in players:
		players[id].ready = false
	_sync()
	map_changed.emit()
	send_my_scores()


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
		if mm.kind == MatchMode.Kind.ROYALE and mm.is_spectator(int(id)):
			continue  # Ausgeschiedene muessen nicht bereit sein
		if not bool(players[id].ready):
			return false
	return true


func start_game() -> void:
	if not active or in_game or not all_ready() or mode_blocker() != "":
		return
	if is_host:
		if crown_id != 1:
			return
		_mode_prepare_round()
		rpc("cl_start")
		cl_start()
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_start")


func _sync() -> void:
	if not is_host:
		return
	rpc("cl_state", players, crown_id, sel_map, room_name, played, mods, mm.to_dict())
	players_changed.emit()


# ---------------------------------------------------------------------------
# Client-Seite (laeuft bei allen)
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func cl_state(p: Dictionary, crown: int, m: Dictionary, rname: String, played_list: Array = [], mods_in: Dictionary = {}, mm_in: Dictionary = {}) -> void:
	var map_was := sel_map.duplicate()
	var new_peer := false
	for id in p:
		if not players.has(id):
			new_peer = true
	players = p
	crown_id = crown
	sel_map = m
	room_name = rname
	played = played_list
	mods = _norm_mods(mods_in)
	mm = MatchMode.from_dict(mm_in)
	players_changed.emit()
	if map_was != sel_map:
		map_changed.emit()
	if in_game:
		scores_changed.emit()
	elif not sel_map.is_empty() and (map_was != sel_map or new_peer):
		send_my_scores()


@rpc("authority", "call_remote", "reliable")
func cl_start() -> void:
	spectating = mm.kind == MatchMode.Kind.ROYALE and mm.is_spectator(multiplayer.get_unique_id())
	var path := resolve_local_path()
	if path == "" and not spectating:
		status.emit("Map fehlt lokal — Start nicht moeglich.")
		return
	in_game = true
	skip_votes = {}
	if is_host:
		_tour_peers = players.keys()
		_mm_peers = _mode_participants()
		_mm_live = true
	if not sel_map.is_empty():
		var pk := "%s|%s" % [str(sel_map.get("file", "")), str(sel_map.get("version", ""))]
		if not played.has(pk):
			played.append(pk)
	for id in players:
		players[id].score = 0
		players[id].combo = 0
		players[id].acc = 1.0
		players[id].final = {}
	if spectating:
		game_start.emit()
		scores_changed.emit()
		return
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
			GameSession.mods = mods.duplicate()
			return true
	# Online-Pick ohne Diff-Name: 4K-Diff mit den naechsten Sternen waehlen.
	var best := _nearest_4k(path, imp, float(sel_map.get("stars", 0.0)))
	if best >= 0:
		var d2 = imp.difficulties[best]
		GameSession.mods = {}
		GameSession.is_replay = false
		GameSession.replay_events = []
		GameSession.set_selection(path, best, d2.beatmap.version_name(),
			d2.osu_filename, float(sel_map.get("stars", 0.0)))
		GameSession.mods = mods.duplicate()
		return true
	return false


## Index der 4K-Mania-Diff, deren Sterne am naechsten an `want` liegen; -1 = keine.
func _nearest_4k(path: String, imp: Dictionary, want: float) -> int:
	var star_data: Dictionary = StarService.stars_for(path)
	var best := -1
	var best_gap := INF
	for i in imp.difficulties.size():
		var bm: Beatmap = imp.difficulties[i].beatmap
		if bm.is_mania() and bm.column_count() != 4:
			continue
		var fname: String = imp.difficulties[i].osu_filename
		var st := want
		if star_data.has(fname):
			st = float(star_data[fname].get("stars", want))
		var gap := absf(st - want)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


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
	acc = clampf(acc, 0.0, 1.0)
	var me := multiplayer.get_unique_id()
	if players.has(me):
		players[me].score = score
		players[me].combo = combo
		players[me].acc = acc
	rpc("cl_score", score, combo, acc)
	scores_changed.emit()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func cl_score(score: int, combo: int, acc: float) -> void:
	acc = clampf(acc, 0.0, 1.0)
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
	_tour_check_round()
	_mode_check_round()


@rpc("any_peer", "call_remote", "reliable")
func cl_final(stats: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].final = stats
		_store_final(id, stats)
		scores_changed.emit()
		_tour_check_round()
		_mode_check_round()


## Endergebnis eines Mitspielers als fremden Score speichern (nicht bei Fail).
func _store_final(id: int, stats: Dictionary) -> int:
	if sel_map.is_empty() or not players.has(id) or bool(stats.get("failed", false)):
		return 0
	var pname := str(players[id].get("name", ""))
	if pname == ScoreStore._self_name():
		return 0
	var e := {
		"score": stats.get("score", 0), "accuracy": stats.get("acc", 0.0),
		"grade": stats.get("grade", "D"), "max_combo": stats.get("combo", 0),
		"pp": -1.0, "mods": _mods_list(), "date": Time.get_datetime_string_from_system(),
	}
	return ScoreStore.submit_others(_map_key(), pname, [e])


func _mods_list() -> Array:
	var out: Array = []
	for k in mods:
		if bool(mods[k]):
			out.append(str(k))
	return out


## ScoreStore-Schluessel der gewaehlten Map (Set-ID, sonst lokaler Dateiname).
func _map_key() -> String:
	var sid := int(sel_map.get("set_id", 0))
	var ver := str(sel_map.get("version", ""))
	if sid > 0:
		return ScoreStore.map_id_for_set(sid, ver)
	return ScoreStore.map_id(str(sel_map.get("file", "")), ver)


## Eigene Top-Scores (max. 10, ohne Fails) der gewaehlten Map an alle schicken.
func send_my_scores() -> void:
	if not active or sel_map.is_empty() or multiplayer.multiplayer_peer == null:
		return
	var path := resolve_local_path()
	if path == "":
		return
	var sid := int(sel_map.get("set_id", 0))
	if sid > 0:
		ScoreStore.register_set_id(path, sid)
	var ver := str(sel_map.get("version", ""))
	var list: Array = []
	for e in ScoreStore.top_scores(path, ver, ScoreStore.OTHERS_CAP):
		list.append({
			"score": int(e.get("score", 0)), "accuracy": float(e.get("accuracy", 0.0)),
			"grade": str(e.get("grade", "D")), "max_combo": int(e.get("max_combo", 0)),
			"pp": float(e.get("pp", -1.0)), "unranked": bool(e.get("unranked", false)),
			"mods": e.get("mods", []), "date": str(e.get("date", "")),
		})
	if list.is_empty():
		return
	rpc("cl_scores", sid, ver, list)


@rpc("any_peer", "call_remote", "reliable")
func cl_scores(set_id: int, version: String, list: Array) -> void:
	accept_scores(multiplayer.get_remote_sender_id(), set_id, version, list)


## Score-Paket eines Mitspielers pruefen und speichern; Zahl neuer Eintraege.
## Nur fuer die aktuell gewaehlte Map, max. 10 Eintraege.
func accept_scores(id: int, set_id: int, version: String, list: Array) -> int:
	if not players.has(id) or sel_map.is_empty() or list.size() > ScoreStore.OTHERS_CAP:
		return 0
	if set_id != int(sel_map.get("set_id", 0)) or version != str(sel_map.get("version", "")):
		return 0
	var pname := str(players[id].get("name", ""))
	if pname == ScoreStore._self_name():
		return 0
	return ScoreStore.submit_others(_map_key(), pname, list)


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


## Nach Rueckkehr in die Lobby: Runde beenden. Bereit-Status bleibt
## erhalten (Map ist ja bei allen vorhanden) — Neuwahl setzt ihn zurueck.
func round_done() -> void:
	in_game = false
	spectating = false


## Spieler-Liste nach Live-Score sortiert (fuer Scoreboard/Ranking).
func ranked_players() -> Array:
	var list := []
	for id in players:
		# Frueher Ausgeschiedene (Royale) spielen nicht mehr mit.
		if mm.kind == MatchMode.Kind.ROYALE and mm.is_spectator(int(id)) 				and (players[id].get("final", {}) as Dictionary).is_empty():
			continue
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


# ---------------------------------------------------------------------------
# Turnier. Server (= Host-Peer 1) validiert alles und verteilt to_dict().
# ---------------------------------------------------------------------------

func _tour_refresh() -> void:
	if tournament == null:
		return
	var names := {}
	for id in players:
		names[id] = str(players[id].name)
	tournament.set_players(players.keys(), names)


func _is_offline() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Zustand an alle (reliable) + lokal melden.
func _tour_sync() -> void:
	if not is_host:
		return
	if not _is_offline():
		for id in players:
			if int(id) == 1:
				continue
			rpc_id(int(id), "cl_tournament", tournament.to_dict_for(int(id)) if tournament != null else {})
	tournament_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_tournament(d: Dictionary) -> void:
	if is_host:
		return
	tournament = Tournament.from_dict(d) if not d.is_empty() else null
	tournament_changed.emit()


@rpc("authority", "call_remote", "reliable")
func cl_tour_msg(msg: String) -> void:
	status.emit(msg)


## Sicht auf das Turnier fuer die UI: auch der Host sieht fremde Bans erst nach Aufdecken.
func tour_view() -> Tournament:
	if tournament == null or not is_host:
		return tournament
	return Tournament.from_dict(tournament.to_dict_for(1))


func _tour_reply(sender: int, msg: String) -> void:
	if msg == "":
		return
	if sender == 1 or _is_offline():
		status.emit(msg)
	else:
		rpc_id(sender, "cl_tour_msg", msg)


func _tour_host_ok() -> bool:
	return active and is_host


## Host: Turnier anlegen. cfg {maps: 5/10/15, stars_lo, stars_hi, mods}.
func tour_create(cfg: Dictionary) -> void:
	if not _tour_host_ok() or in_game or tournament != null:
		return
	if mm.kind != MatchMode.Kind.FREE:
		_mode_apply(MatchMode.Kind.FREE)
	var c := cfg.duplicate()
	c["seed"] = randi()
	tournament = Tournament.create(c)
	tournament.host_id = 1
	_tour_refresh()
	for id in players:
		players[id].ready = false
	_tour_sync()
	_sync()


## Host: Auto-Fuellung freigegeben (Host darf freie Plaetze fuellen, Bans auch ohne vollen Pool).
func tour_autofill_done() -> void:
	if not _tour_host_ok() or tournament == null or tournament.phase != Tournament.Phase.PICK:
		return
	tournament.autofill_done = true
	_tour_sync()


## Host: PICK -> BAN.
func tour_start_bans() -> void:
	if not _tour_host_ok() or tournament == null:
		return
	if not (tournament.is_pool_full() or tournament.autofill_done):
		status.emit("Pool ist noch nicht voll.")
		return
	_tour_refresh()
	if not tournament.start_bans():
		return
	_tour_sync()


## Host: BAN -> PLAY (erste Runde).
func tour_begin() -> void:
	if not _tour_host_ok() or tournament == null or in_game:
		return
	if tournament.phase != Tournament.Phase.BAN:
		return
	_tour_refresh()
	if not tournament.all_banned(tournament.player_ids):
		status.emit("Es haben noch nicht alle gebannt.")
		return
	_tour_next_round()


## Host: BETWEEN -> naechste Runde oder END.
func tour_next() -> void:
	if not _tour_host_ok() or tournament == null or in_game:
		return
	if tournament.phase != Tournament.Phase.BETWEEN:
		return
	_tour_next_round()


func _tour_next_round() -> void:
	var m := tournament.next_map()
	if not m.is_empty():
		sel_map = {}
		for k in ["set_id", "file", "version", "title", "artist", "stars"]:
			sel_map[k] = m.get(k)
		mods = _norm_mods(tournament.config.mods)
		for id in players:
			players[id].ready = false
		_sync()
		map_changed.emit()
		send_my_scores()
	_tour_sync()


## Host: Turnier abbrechen (tournament = null).
func tour_cancel() -> void:
	if not _tour_host_ok() or tournament == null:
		return
	tournament = null
	_tour_peers = []
	_tour_sync()


## Alle: Map vorschlagen (sel_map-Format; online-Maps erlaubt).
func tour_add_map(data: Dictionary) -> void:
	if not active or tournament == null:
		return
	if is_host:
		_srv_tour_add(1, data)
	else:
		rpc_id(1, "srv_tour_add_map", data)


## Alle: eigenen Pick entfernen (Host: jeden).
func tour_remove_map(i: int) -> void:
	if not active or tournament == null:
		return
	if is_host:
		_srv_tour_remove(1, i)
	else:
		rpc_id(1, "srv_tour_remove_map", i)


## Alle: Hass-Map abwaehlen (Pool-Index).
func tour_ban(i: int) -> void:
	if not active or tournament == null:
		return
	if is_host:
		_srv_tour_ban(1, i)
	else:
		rpc_id(1, "srv_tour_ban", i)


@rpc("any_peer", "call_remote", "reliable")
func srv_tour_add_map(data: Dictionary) -> void:
	_srv_tour_add(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "call_remote", "reliable")
func srv_tour_remove_map(i: int) -> void:
	_srv_tour_remove(multiplayer.get_remote_sender_id(), i)


@rpc("any_peer", "call_remote", "reliable")
func srv_tour_ban(i: int) -> void:
	_srv_tour_ban(multiplayer.get_remote_sender_id(), i)


func _tour_guard(sender: int) -> String:
	if not is_host or not active or tournament == null:
		return "Kein Turnier."
	if not players.has(sender):
		return "Unbekannter Spieler."
	return ""


func _srv_tour_add(sender: int, data: Dictionary) -> String:
	var err := _tour_guard(sender)
	if err == "":
		_tour_refresh()
		err = tournament.add_map(data, sender)
	_tour_reply(sender, err)
	if err == "":
		_tour_sync()
	return err


func _srv_tour_remove(sender: int, i: int) -> String:
	var err := _tour_guard(sender)
	if err == "" and not tournament.remove_map(i, sender):
		err = "Entfernen nicht erlaubt."
	_tour_reply(sender, err)
	if err == "":
		_tour_sync()
	return err


func _srv_tour_ban(sender: int, i: int) -> String:
	var err := _tour_guard(sender)
	if err == "":
		_tour_refresh()
		err = tournament.ban(sender, i)
	_tour_reply(sender, err)
	if err == "":
		_tour_sync()
	return err


## Server: Runde auswerten, sobald alle Rundenteilnehmer ein Endergebnis haben
## oder gegangen sind.
func _tour_check_round() -> void:
	if not is_host or tournament == null or not in_game or _tour_peers.is_empty():
		return
	if tournament.phase != Tournament.Phase.PLAY:
		return
	for id in _tour_peers:
		if players.has(id) and (players[id].final as Dictionary).is_empty():
			return
	var results := {}
	for id in _tour_peers:
		if players.has(id):
			var f: Dictionary = players[id].final
			results[id] = { "score": clampi(int(f.get("score", 0)), 0, 2000000000),
				"accuracy": clampf(float(f.get("acc", 0.0)), 0.0, 1.0),
				"max_combo": clampi(int(f.get("combo", 0)), 0, 1000000),
				"failed": bool(f.get("failed", false)), "name": str(players[id].name) }
		else:
			# Gegangen: 0 Punkte, bleibt in der Tabelle.
			results[id] = { "score": 0, "accuracy": 0.0, "max_combo": 0, "failed": true,
				"name": str(tournament.player_names.get(id, "?")) }
	tournament.record_round(results)
	_tour_peers = []
	_tour_sync()


# ---------------------------------------------------------------------------
# Raum-Modi: Frei / Teams / Battle Royale. Server validiert alles.
# ---------------------------------------------------------------------------

func room_kind() -> int:
	return mm.kind


static func mode_name(kind: int) -> String:
	return ["Frei", "Teams", "Battle Royale"][clampi(kind, 0, 2)]


## Warum gerade nicht gestartet werden kann ("" = alles in Ordnung).
func mode_blocker() -> String:
	if mm.kind == MatchMode.Kind.TEAMS:
		var sz := mm.team_sizes()
		if sz[0] == 0 or sz[1] == 0:
			return "Beide Teams brauchen mindestens einen Spieler."
	elif mm.kind == MatchMode.Kind.ROYALE and players.size() < 2:
		return "Battle Royale braucht mindestens 2 Spieler."
	return ""


## Krone: Raum-Modus waehlen (nicht im Turnier, nicht mitten in der Runde).
func set_room_mode(kind: int) -> void:
	if not active or in_game or tournament != null or kind < 0 or kind > MatchMode.Kind.ROYALE:
		return
	if is_host:
		if crown_id == 1:
			_mode_apply(kind)
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_set_mode", kind)


@rpc("any_peer", "call_remote", "reliable")
func srv_set_mode(kind: int) -> void:
	if not is_host or in_game or tournament != null:
		return
	if multiplayer.get_remote_sender_id() != crown_id or kind < 0 or kind > MatchMode.Kind.ROYALE:
		return
	_mode_apply(kind)


func _mode_apply(kind: int) -> void:
	if kind == mm.kind and kind == MatchMode.Kind.FREE:
		return
	var old_names: Array = mm.team_names.duplicate()
	mm = MatchMode.new(kind)
	if kind == MatchMode.Kind.TEAMS:
		mm.team_names = old_names
	_mm_live = false
	_mm_peers = []
	var ids: Array = players.keys()
	ids.sort()
	if kind == MatchMode.Kind.TEAMS:
		mm.auto_balance(ids, _mode_stats())
	elif kind == MatchMode.Kind.ROYALE:
		mm.start_royale(ids)
	else:
		for id in ids:
			mm.add_player(int(id))
	_sync()


## Spieler -> {acc, score} der letzten Runde (fuer den Auto-Ausgleich).
func _mode_stats() -> Dictionary:
	var out := {}
	for id in players:
		var f: Dictionary = players[id].get("final", {})
		if not f.is_empty():
			out[int(id)] = { "acc": float(f.get("acc", 0.0)), "score": int(f.get("score", 0)) }
	return out


## Teams: Spieler wechselt selbst, die Krone darf jeden verschieben.
func set_team(peer: int, team: int) -> void:
	if not active or in_game or mm.kind != MatchMode.Kind.TEAMS:
		return
	if is_host:
		_srv_set_team(1, peer, team)
	else:
		rpc_id(1, "srv_set_team", peer, team)


@rpc("any_peer", "call_remote", "reliable")
func srv_set_team(peer: int, team: int) -> void:
	_srv_set_team(multiplayer.get_remote_sender_id(), peer, team)


func _srv_set_team(sender: int, peer: int, team: int) -> void:
	if not is_host or in_game or mm.kind != MatchMode.Kind.TEAMS or not players.has(sender):
		return
	if sender != peer and sender != crown_id:
		return
	if mm.set_team(peer, team):
		_sync()


## Krone: Teams automatisch ausgleichen.
func auto_balance_teams() -> void:
	if not active or in_game or mm.kind != MatchMode.Kind.TEAMS:
		return
	if is_host:
		if crown_id == 1:
			_srv_balance()
	elif crown_id == multiplayer.get_unique_id():
		rpc_id(1, "srv_balance")


@rpc("any_peer", "call_remote", "reliable")
func srv_balance() -> void:
	if is_host and multiplayer.get_remote_sender_id() == crown_id:
		_srv_balance()


func _srv_balance() -> void:
	if in_game or mm.kind != MatchMode.Kind.TEAMS:
		return
	var ids: Array = players.keys()
	ids.sort()
	mm.auto_balance(ids, _mode_stats())
	_sync()


## Server: Mitgliederliste des Modus an die Spieler angleichen.
func _mm_refresh() -> void:
	if not is_host:
		return
	for id in mm.order.duplicate():
		# Mitten in der Runde Gegangene bleiben bis zur Auswertung (zaehlen als Leaver).
		if not players.has(id) and not _mm_peers.has(id):
			mm.remove_player(int(id))
	var ids: Array = players.keys()
	ids.sort()
	for id in ids:
		if not mm.order.has(int(id)) and mm.add_player(int(id)):
			# Wer mitten in einer Royale-Serie dazukommt, schaut nur zu.
			if mm.kind == MatchMode.Kind.ROYALE and _mm_live:
				mm.players[int(id)] = { "alive": false, "spectator": true, "out_round": 0 }


func _mode_participants() -> Array:
	var out: Array = []
	for id in players:
		if mm.kind == MatchMode.Kind.ROYALE and mm.is_spectator(int(id)):
			continue
		out.append(int(id))
	return out


## Server, vor dem Start: abgeschlossene Serie frisch beginnen.
func _mode_prepare_round() -> void:
	if mm.kind == MatchMode.Kind.TEAMS and mm.series_over():
		var keep := mm
		mm = MatchMode.new(MatchMode.Kind.TEAMS)
		mm.team_names = keep.team_names.duplicate()
		mm.series_mode = keep.series_mode
		mm.series_n = keep.series_n
		mm.order = keep.order.duplicate()
		mm.team_of = keep.team_of.duplicate()
	elif mm.kind == MatchMode.Kind.ROYALE and (mm.is_over() or mm.alive().size() < 2):
		mm.start_royale(players.keys())
		_mm_live = false
	_sync()


## Live-Zwischenstand aller Mitspieler im Format von MatchMode (acc in Prozent).
func live_results() -> Array:
	var out: Array = []
	for id in players:
		var p: Dictionary = players[id]
		var f: Dictionary = p.get("final", {})
		var src: Dictionary = f if not f.is_empty() else p
		out.append({ "peer": int(id), "score": int(src.get("score", 0)),
			"acc": float(src.get("acc", 0.0)) * 100.0,
			"max_combo": int(src.get("combo", 0)),
			"failed": bool(f.get("failed", false)), "left": false })
	return out


## Server: Runde auswerten, sobald alle Teilnehmer ein Endergebnis haben oder gegangen sind.
func _mode_check_round() -> void:
	if not is_host or tournament != null or mm.kind == MatchMode.Kind.FREE:
		return
	if not in_game or _mm_peers.is_empty():
		return
	for id in _mm_peers:
		if players.has(id) and (players[id].final as Dictionary).is_empty():
			return
	var results: Array = []
	for id in _mm_peers:
		if players.has(id):
			var f: Dictionary = players[id].final
			results.append({ "peer": int(id), "score": int(f.get("score", 0)),
				"acc": float(f.get("acc", 0.0)) * 100.0, "max_combo": int(f.get("combo", 0)),
				"failed": bool(f.get("failed", false)), "left": false })
		else:
			results.append({ "peer": int(id), "score": 0, "acc": 0.0, "max_combo": 0,
				"failed": true, "left": true })
	if mm.kind == MatchMode.Kind.TEAMS:
		mm.finish_team_round(results)
	else:
		mm.eliminate(results)
	_mm_peers = []
	_mm_refresh()
	_sync()
	rpc("cl_round_end")
	cl_round_end()


## Alle: Auswertung fertig. Zuschauer kehren damit in die Lobby zurueck.
@rpc("authority", "call_remote", "reliable")
func cl_round_end() -> void:
	if spectating:
		in_game = false
		spectating = false
	round_ended.emit()
	players_changed.emit()
