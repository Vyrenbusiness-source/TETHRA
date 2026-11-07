class_name Tournament
extends RefCounted

## Multiplayer-Turnier: reine Logik (kein Netz, kein Node). Der Lobby-Server
## haelt eine Instanz, validiert damit alles und verteilt to_dict() an alle.
## Ablauf: PICK (Maps vorschlagen, auch Online-Browser) -> BAN (jeder streicht
## genau eine Map) -> PLAY (Runde fuer Runde) <-> BETWEEN -> END.

enum Phase { PICK, BAN, PLAY, BETWEEN, END }

const ALLOWED_MAPS := [5, 10, 15]
const MAX_STARS := 30.0

var phase: int = Phase.PICK
## {maps: int (5/10/15), stars_lo: float, stars_hi: float, mods: Dictionary, seed: int}
var config: Dictionary = { "maps": 10, "stars_lo": 0.0, "stars_hi": MAX_STARS, "mods": {}, "seed": 1 }
## Map-Dicts: sel_map-Format {set_id, file, version, title, artist, stars}
## plus "by": peer_id, "online": bool (nicht lokal vorhanden), "banned": bool.
var pool: Array = []
## peer_id -> Pool-Index des Bans
var bans: Dictionary = {}
## Reihenfolge der Runden (Pool-Indizes), gesetzt bei der ersten next_map().
var order: Array = []
## Index in order der aktuellen Runde (-1 = noch nicht begonnen).
var current_round := -1
## Pro gespielter Runde: {map: Pool-Index, results: {peer: {score, accuracy,
## max_combo, failed, name, place, points}}}
var rounds: Array = []
## peer -> Name (auch fuer gegangene Spieler, bleiben in der Tabelle)
var player_names: Dictionary = {}
## Aktuelle Spieler (Lobby haelt das aktuell): Grundlage fuer Pick-Limit und Bans.
var player_ids: Array = []
var host_id := 1
## Host hat die Auto-Fuellung freigegeben: Host darf freie Plaetze ueber sein Limit fuellen,
## und die Ban-Phase darf auch mit unvollem Pool starten.
var autofill_done := false
## Nur Client-Sicht: Bans anderer sind noch verdeckt; voted = wer schon gewaehlt hat.
var hidden := false
var voted: Array = []


## Gueltige Konfiguration aus beliebigem Dict bauen.
static func clean_config(cfg: Dictionary) -> Dictionary:
	var n := int(cfg.get("maps", 10))
	if not ALLOWED_MAPS.has(n):
		n = 10
	var lo := clampf(float(cfg.get("stars_lo", 0.0)), 0.0, MAX_STARS)
	var hi := clampf(float(cfg.get("stars_hi", MAX_STARS)), 0.0, MAX_STARS)
	if lo > hi:
		var t := lo
		lo = hi
		hi = t
	var m = cfg.get("mods", {})
	if not (m is Dictionary):
		m = {}
	var mods := {}
	for k in ["SV", "NF"]:
		if bool(m.get(k, false)):
			mods[k] = true
	return { "maps": n, "stars_lo": lo, "stars_hi": hi, "mods": mods,
		"seed": int(cfg.get("seed", 1)) }


static func create(cfg: Dictionary) -> Tournament:
	var t := Tournament.new()
	t.config = clean_config(cfg)
	return t


func set_players(ids: Array, names: Dictionary = {}) -> void:
	player_ids = ids.duplicate()
	for id in ids:
		if names.has(id):
			player_names[id] = str(names[id])


func max_per_player() -> int:
	return int(ceil(float(int(config.maps)) / float(maxi(1, player_ids.size()))))


static func _key(m: Dictionary) -> String:
	var sid := int(m.get("set_id", 0))
	if sid > 0:
		return "s%d|%s" % [sid, str(m.get("version", ""))]
	return "f%s|%s" % [str(m.get("file", "")), str(m.get("version", ""))]


func picks_of(peer: int) -> int:
	var n := 0
	for m in pool:
		if int(m.by) == peer:
			n += 1
	return n


## Map vorschlagen. Fehlertext, "" = ok.
func add_map(data: Dictionary, by: int) -> String:
	if phase != Phase.PICK:
		return tr("Nicht in der Auswahlphase.")
	if pool.size() >= int(config.maps):
		return tr("Pool ist voll.")
	var file = data.get("file", "")
	var version = data.get("version", "")
	if not (file is String) or not (version is String) or file == "" or file.length() > 300 or version.length() > 120:
		return tr("Ungueltige Map.")
	var st = data.get("stars", null)
	if not (st is float or st is int):
		return tr("Ungueltige Sterne.")
	var stars := float(st)
	if is_nan(stars) or stars < float(config.stars_lo) or stars > float(config.stars_hi):
		return tr("Sterne ausserhalb des Bereichs.")
	var sid = data.get("set_id", 0)
	if not (sid is int or sid is float):
		return tr("Ungueltige Map.")
	var clean := {
		"set_id": int(sid), "file": file, "version": version,
		"title": str(data.get("title", "")).substr(0, 200),
		"artist": str(data.get("artist", "")).substr(0, 200),
		"stars": stars, "by": by, "online": bool(data.get("online", false)),
		"banned": false,
	}
	var k := _key(clean)
	for m in pool:
		if _key(m) == k:
			return tr("Map ist schon im Pool.")
	if picks_of(by) >= max_per_player() and not (autofill_done and by == host_id):
		return tr("Du hast schon %d Maps gewaehlt.") % max_per_player()
	pool.append(clean)
	return ""


## Eigenen Pick (oder als Host jeden) entfernen.
func remove_map(i: int, by: int) -> bool:
	if phase != Phase.PICK or i < 0 or i >= pool.size():
		return false
	if int(pool[i].by) != by and by != host_id:
		return false
	pool.remove_at(i)
	return true


func is_pool_full() -> bool:
	return pool.size() >= int(config.maps)


func start_bans() -> bool:
	if phase != Phase.PICK or pool.is_empty():
		return false
	phase = Phase.BAN
	bans = {}
	for m in pool:
		m.banned = false
	return true


func remaining() -> int:
	var n := 0
	for m in pool:
		if not bool(m.banned):
			n += 1
	return n


## Hass-Map abwaehlen. Aendern erlaubt, bis alle gebannt haben. "" = ok.
func ban(peer: int, i: int) -> String:
	if phase != Phase.BAN:
		return tr("Nicht in der Ban-Phase.")
	if not player_ids.has(peer):
		return tr("Kein Spieler.")
	if i < 0 or i >= pool.size():
		return tr("Ungueltige Map.")
	if not player_ids.is_empty() and player_ids.all(func(x): return bans.has(x)):
		return tr("Alle haben schon gebannt.")
	if bans.get(peer, -1) == i:
		return ""
	if bool(pool[i].banned):
		return tr("Diese Map hat schon jemand gestrichen. Such dir eine andere aus.")
	# Mindestens 1 Map bleibt: beim Wechsel wird erst die alte frei.
	var freed := 1 if bans.has(peer) else 0
	if remaining() + freed <= 1:
		return tr("Mindestens eine Map muss uebrig bleiben.")
	if bans.has(peer):
		pool[int(bans[peer])].banned = false
	bans[peer] = i
	pool[i].banned = true
	return ""


## Alle Spieler haben gebannt (oder es kann keiner mehr bannen).
func all_banned(players: Array) -> bool:
	if phase != Phase.BAN and phase != Phase.PLAY:
		return false
	if remaining() <= 1:
		return true
	for p in players:
		if not bans.has(p):
			return false
	return not players.is_empty()


## Nicht gebannte Pool-Indizes, deterministisch gemischt (Seed aus config).
func play_order() -> Array[int]:
	var res: Array[int] = []
	for i in pool.size():
		if not bool(pool[i].banned):
			res.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d" % [str(config.get("seed", 1)), str(config.maps), pool.size()])
	for j in range(res.size() - 1, 0, -1):
		var k := rng.randi_range(0, j)
		var t := res[j]
		res[j] = res[k]
		res[k] = t
	return res


## Naechste Runde starten. Gibt die Map zurueck, {} wenn keine mehr (-> END).
func next_map() -> Dictionary:
	if phase == Phase.END or phase == Phase.PICK or phase == Phase.PLAY:
		return {}
	if phase == Phase.BAN:
		order = Array(play_order())
	if current_round + 1 >= order.size():
		phase = Phase.END
		return {}
	current_round += 1
	phase = Phase.PLAY
	return pool[int(order[current_round])].duplicate()


func current_map_index() -> int:
	if current_round < 0 or current_round >= order.size():
		return -1
	return int(order[current_round])


## Rundenergebnis werten. results: {peer: {score, accuracy, max_combo, failed, name}}.
func record_round(results: Dictionary) -> void:
	if phase != Phase.PLAY:
		return
	var n := results.size()
	var res := {}
	for peer in results:
		var r: Dictionary = results[peer]
		var nm := str(r.get("name", player_names.get(peer, "?")))
		player_names[peer] = nm
		res[peer] = { "score": int(r.get("score", 0)), "accuracy": clampf(float(r.get("accuracy", 0.0)), 0.0, 1.0),
			"max_combo": int(r.get("max_combo", 0)), "failed": bool(r.get("failed", false)),
			"name": nm, "place": n, "points": 0, "absent": bool(r.get("absent", false)) }
	# Hat niemand bestanden, zaehlt der Score trotzdem (sonst gibt es weder Sieger noch Punkte).
	var all_failed := true
	for peer in res:
		if not bool(res[peer].failed):
			all_failed = false
	for peer in res:
		var e: Dictionary = res[peer]
		if bool(e.absent) or (e.failed and not all_failed):
			continue
		var better := 0
		for o in res:
			if bool(res[o].absent) or (res[o].failed and not all_failed):
				continue
			if int(res[o].score) > int(e.score):
				better += 1
		e.place = better + 1
		e.points = n - better
	rounds.append({ "map": current_map_index(), "results": res })
	phase = Phase.BETWEEN if current_round + 1 < order.size() else Phase.END


func _blank(peer, nm) -> Dictionary:
	return { "peer": peer, "name": nm, "points": 0, "wins": 0,
		"avg_acc": 0.0, "total_score": 0, "rank": 0, "_n": 0 }


## [{peer, name, points, wins, avg_acc, total_score, rank}] nach Punkten, dann Gesamtscore.
func standings() -> Array:
	var acc := {}
	for peer in player_names:
		acc[peer] = _blank(peer, player_names[peer])
	for rd in rounds:
		for peer in rd.results:
			var r: Dictionary = rd.results[peer]
			if not acc.has(peer):
				acc[peer] = _blank(peer, r.name)
			var a: Dictionary = acc[peer]
			a.points += int(r.points)
			a.wins += 1 if (int(r.place) == 1 and int(r.points) > 0) else 0
			a.total_score += int(r.score)
			if not bool(r.get("absent", false)):
				a.avg_acc += float(r.accuracy)
				a._n += 1
	var list: Array = acc.values()
	for a in list:
		if a._n > 0:
			a.avg_acc /= a._n
		a.erase("_n")
	list.sort_custom(func(x, y):
		if x.points != y.points:
			return x.points > y.points
		if x.total_score != y.total_score:
			return x.total_score > y.total_score
		return int(x.peer) < int(y.peer))
	for i in list.size():
		if i > 0 and list[i].points == list[i - 1].points and list[i].total_score == list[i - 1].total_score:
			list[i].rank = list[i - 1].rank
		else:
			list[i].rank = i + 1
	return list


## [{map, winner_name, score}] je gespielter Runde.
func map_winners() -> Array:
	var out: Array = []
	for rd in rounds:
		var w := ""
		var sc := 0
		var best := -1
		for peer in rd.results:
			var r: Dictionary = rd.results[peer]
			if int(r.get("place", 0)) == 1 and int(r.points) > 0 and int(r.score) > best:
				best = int(r.score)
				w = str(r.name)
				sc = int(r.score)
		var mi := int(rd.map)
		out.append({ "map": pool[mi].duplicate() if mi >= 0 and mi < pool.size() else {},
			"winner_name": w, "score": sc })
	return out


func to_dict() -> Dictionary:
	return { "phase": phase, "config": config.duplicate(true), "pool": pool.duplicate(true),
		"bans": bans.duplicate(), "order": order.duplicate(), "current_round": current_round,
		"rounds": rounds.duplicate(true), "player_names": player_names.duplicate(),
		"player_ids": player_ids.duplicate(), "host_id": host_id, "autofill_done": autofill_done }


## Sicht fuer einen Spieler: solange nicht alle gebannt haben, kennt er nur
## den eigenen Ban; von den anderen nur "hat gewaehlt" (voted).
func to_dict_for(peer: int) -> Dictionary:
	var d := to_dict()
	d["voted"] = bans.keys()
	if phase != Phase.BAN or all_banned(player_ids):
		return d
	var mine := int(bans.get(peer, -1))
	var pl: Array = d.pool
	for i in pl.size():
		pl[i].banned = (i == mine)
	d["bans"] = { peer: mine } if mine >= 0 else {}
	d["hidden"] = true
	return d


func has_voted(peer: int) -> bool:
	return int(bans.get(peer, -1)) >= 0 or voted.has(peer)


static func from_dict(d: Dictionary) -> Tournament:
	var t := Tournament.new()
	t.phase = clampi(int(d.get("phase", 0)), 0, Phase.END)
	t.config = clean_config(d.get("config", {}))
	t.pool = (d.get("pool", []) as Array).duplicate(true)
	t.bans = (d.get("bans", {}) as Dictionary).duplicate()
	t.order = (d.get("order", []) as Array).duplicate()
	t.current_round = int(d.get("current_round", -1))
	t.rounds = (d.get("rounds", []) as Array).duplicate(true)
	t.player_names = (d.get("player_names", {}) as Dictionary).duplicate()
	t.player_ids = (d.get("player_ids", []) as Array).duplicate()
	t.host_id = int(d.get("host_id", 1))
	t.autofill_done = bool(d.get("autofill_done", false))
	t.hidden = bool(d.get("hidden", false))
	t.voted = (d.get("voted", []) as Array).duplicate()
	return t
