class_name Tournament
extends RefCounted

## Multiplayer-Turnier: reine Logik (kein Netz, kein Node). Der Lobby-Server
## haelt eine Instanz, validiert damit alles und verteilt to_dict() an alle.
## Ablauf: PICK (Maps vorschlagen, auch Online-Browser) -> BAN (jeder streicht
## genau eine Map) -> PLAY (Runde fuer Runde) <-> BETWEEN -> END.
## DIES IST DIE API-SCHNITTSTELLE; Details werden in einem Folge-Commit gefuellt.

enum Phase { PICK, BAN, PLAY, BETWEEN, END }

const ALLOWED_MAPS := [5, 10, 15]

var phase: int = Phase.PICK
## {maps: int (5/10/15), stars_lo: float, stars_hi: float, mods: Dictionary}
var config: Dictionary = { "maps": 10, "stars_lo": 0.0, "stars_hi": 99.0, "mods": {} }
## Map-Dicts: sel_map-Format {set_id, file, version, title, artist, stars}
## plus "by": peer_id, "online": bool (nicht lokal vorhanden), "banned": bool.
var pool: Array = []
## peer_id -> pool-Index des Bans (-1 = noch keiner)
var bans: Dictionary = {}
## Reihenfolge der Runden (Pool-Indizes), nach start_bans/begin gesetzt.
var order: Array = []
## Index in order der aktuellen/naechsten Runde (-1 = noch nicht begonnen).
var current_round := -1
## Pro Runde: {peer: {score, accuracy, max_combo, failed, name}}
var rounds: Array = []
## Spielerzahl zum Zeitpunkt der Rundenwertung (fuer Punkte)
var player_names: Dictionary = {}  # peer -> Name (auch fuer gegangene Spieler)


## Fehlertext ("" = ok).
func add_map(_data: Dictionary, _by: int, _players: int = 1) -> String:
	return ""


func remove_map(_i: int, _by: int, _host: int = 1) -> bool:
	return false


func is_pool_full() -> bool:
	return false


func start_bans() -> void:
	pass


## Fehlertext ("" = ok).
func ban(_peer: int, _i: int) -> String:
	return ""


func all_banned(_players: Array) -> bool:
	return false


func play_order() -> Array[int]:
	return []


## Naechste Map (Dict aus dem Pool) oder {} wenn keine mehr da ist.
func next_map() -> Dictionary:
	return {}


func record_round(_results: Dictionary) -> void:
	pass


## [{peer, name, points, wins, avg_acc, total_score, rank}]
func standings() -> Array:
	return []


## [{map, winner_name, score}]
func map_winners() -> Array:
	return []


func to_dict() -> Dictionary:
	return {}


static func from_dict(_d: Dictionary) -> Tournament:
	return Tournament.new()
