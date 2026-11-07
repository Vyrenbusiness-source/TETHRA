class_name MatchMode
extends RefCounted

## Multiplayer-Modi: Frei, Teams (2 Teams, Summenwertung) und Battle Royale
## (nach jeder Map fliegt der Schwaechste raus). Reine Logik, ohne Netz/UI.
##
## Ergebnis-Eintrag (results): {peer:int, score:int, acc:float, max_combo:int,
## failed:bool, left:bool}. Ungueltige Eintraege werden ignoriert.

enum Kind { FREE, TEAMS, ROYALE }
enum Series { BEST_OF, FIXED }

const MAX_NAME := 16
const MAX_PLAYERS := 64
const BEST_OF_CHOICES := [3, 5, 7]
const MAX_FIXED := 15

var kind: int = Kind.FREE
var team_names: Array = ["Rot", "Blau"]
var team_of: Dictionary = {}        # peer -> 0|1
var order: Array = []               # Beitrittsreihenfolge (peers)
var series_mode: int = Series.BEST_OF
var series_n: int = 3
var team_wins: Array = [0, 0]
var rounds_played: int = 0
var history: Array = []             # [{winner, totals}]

var fail_out: bool = false          # Royale: Fail = sofort raus
var round_no: int = 1
var players: Dictionary = {}        # peer -> {alive, spectator, out_round}
var out_order: Array = []           # Royale: Ausgeschiedene in Reihenfolge
var winner_peer: int = -1


func _init(k: int = Kind.FREE) -> void:
	kind = k if k >= 0 and k <= Kind.ROYALE else Kind.FREE


# ---------------------------------------------------------------- Teilnehmer

func add_player(peer: int) -> bool:
	if order.has(peer) or order.size() >= MAX_PLAYERS:
		return false
	order.append(peer)
	if kind == Kind.TEAMS:
		team_of[peer] = _smaller_team()
	if kind == Kind.ROYALE:
		players[peer] = {"alive": true, "spectator": false, "out_round": 0}
	return true


func remove_player(peer: int) -> void:
	order.erase(peer)
	team_of.erase(peer)
	if players.has(peer) and players[peer].alive:
		_knock_out(peer)
		_check_winner()


func _smaller_team() -> int:
	var c := team_sizes()
	return 0 if c[0] <= c[1] else 1


# --------------------------------------------------------------------- Teams

func set_team_name(team: int, text: String) -> bool:
	if team < 0 or team > 1:
		return false
	var t := text.strip_edges().left(MAX_NAME)
	if t.is_empty() or t == team_names[1 - team]:
		return false
	team_names[team] = t
	return true


func set_team(peer: int, team: int) -> bool:
	if kind != Kind.TEAMS or team < 0 or team > 1 or not order.has(peer):
		return false
	team_of[peer] = team
	return true


func team_sizes() -> Array:
	var c := [0, 0]
	for p in team_of:
		c[team_of[p]] += 1
	return c


func team_members(team: int) -> Array:
	var out: Array = []
	for p in order:
		if team_of.get(p, -1) == team:
			out.append(p)
	return out


## Verteilt `peers` abwechselnd. stats: peer -> {acc, score} (Durchschnitt der
## letzten Runden). Staerkste zuerst, jeder geht ins bisher schwaechere Team;
## ohne Werte gilt die Beitrittsreihenfolge (abwechselnd Rot/Blau).
func auto_balance(peers: Array, stats: Dictionary = {}) -> void:
	var list: Array = []
	for p in peers:
		if typeof(p) == TYPE_INT and not list.has(p):
			list.append(p)
	for p in list:
		if not order.has(p):
			order.append(p)
	var rated: Array = []
	var unrated: Array = []
	for p in list:
		if _strength(stats.get(p, null)) >= 0.0:
			rated.append(p)
		else:
			unrated.append(p)
	rated.sort_custom(func(a, b): return _strength(stats[a]) > _strength(stats[b]))
	var sum := [0.0, 0.0]
	var cnt := [0, 0]
	for p in rated:
		var t := 0
		if cnt[0] != cnt[1]:
			t = 0 if cnt[0] < cnt[1] else 1
		elif sum[0] != sum[1]:
			t = 0 if sum[0] < sum[1] else 1
		team_of[p] = t
		cnt[t] += 1
		sum[t] += _strength(stats[p])
	for p in unrated:
		var t2 := 0 if cnt[0] <= cnt[1] else 1
		team_of[p] = t2
		cnt[t2] += 1


## Staerke aus acc (bevorzugt) oder score; -1 = unbekannt.
func _strength(s) -> float:
	if typeof(s) != TYPE_DICTIONARY:
		return -1.0
	if s.has("acc") and (typeof(s.acc) == TYPE_FLOAT or typeof(s.acc) == TYPE_INT):
		return maxf(0.0, float(s.acc))
	if s.has("score") and (typeof(s.score) == TYPE_FLOAT or typeof(s.score) == TYPE_INT):
		return maxf(0.0, float(s.score)) * 0.000001
	return -1.0


## Hinweis zur Aufstellung; leer bei ausgeglichen (z. B. 2v2).
func balance_hint() -> String:
	var c := team_sizes()
	if c[0] == 0 or c[1] == 0:
		return "Ein Team ist leer."
	if c[0] != c[1]:
		return "Ungleiche Teams: %d gegen %d." % [c[0], c[1]]
	return ""


func format_label() -> String:
	var c := team_sizes()
	return "%dv%d" % [c[0], c[1]]


## Summe der Scores je Team. Fails/Leaver zaehlen mit ihrem Score bis dahin.
func team_totals(results: Array) -> Array:
	var tot := [0, 0]
	for r in _clean(results):
		var t: int = team_of.get(r.peer, -1)
		if t >= 0:
			tot[t] += r.score
	return tot


## -1 = Gleichstand/keine Wertung, sonst Team-Index.
func round_winner(results: Array) -> int:
	var t := team_totals(results)
	if t[0] == t[1]:
		return -1
	return 0 if t[0] > t[1] else 1


## Wertet eine Teams-Runde und fuehrt den Serienstand. Gibt {winner, totals}.
func finish_team_round(results: Array) -> Dictionary:
	var tot := team_totals(results)
	var w := round_winner(results)
	if w >= 0:
		team_wins[w] += 1
	rounds_played += 1
	history.append({"winner": w, "totals": tot})
	return {"winner": w, "totals": tot}


func set_series(mode: int, n: int) -> bool:
	if mode == Series.BEST_OF and BEST_OF_CHOICES.has(n):
		series_mode = mode
		series_n = n
		return true
	if mode == Series.FIXED and n >= 1 and n <= MAX_FIXED:
		series_mode = mode
		series_n = n
		return true
	return false


func wins_needed() -> int:
	return series_n / 2 + 1 if series_mode == Series.BEST_OF else 0


## Serien-Sieger: Team-Index, -1 = offen oder unentschieden (siehe series_over).
func series_winner() -> int:
	if series_mode == Series.BEST_OF:
		for t in 2:
			if team_wins[t] >= wins_needed():
				return t
		return -1
	if rounds_played >= series_n and team_wins[0] != team_wins[1]:
		return 0 if team_wins[0] > team_wins[1] else 1
	return -1


func series_over() -> bool:
	if series_winner() >= 0:
		return true
	return series_mode == Series.FIXED and rounds_played >= series_n


## "Best of 3" bzw. "3 Runden".
func series_label() -> String:
	return ("Best of %d" % series_n) if series_mode == Series.BEST_OF else ("%d Runden" % series_n)


func series_text() -> String:
	return "%d : %d" % [team_wins[0], team_wins[1]]


# ------------------------------------------------------------------- Royale

func start_royale(peers: Array, fail_eliminates: bool = false) -> void:
	kind = Kind.ROYALE
	fail_out = fail_eliminates
	players.clear()
	out_order.clear()
	order.clear()
	round_no = 1
	winner_peer = -1
	for p in peers:
		if typeof(p) == TYPE_INT and not players.has(p):
			order.append(p)
			players[p] = {"alive": true, "spectator": false, "out_round": 0}
	_check_winner()


## Lebende Spieler; mit `peers` nur daraus.
func alive(peers: Array = []) -> Array:
	var out: Array = []
	for p in (order if peers.is_empty() else peers):
		if players.has(p) and players[p].alive:
			out.append(p)
	return out


func is_spectator(peer: int) -> bool:
	return players.has(peer) and players[peer].spectator


func is_over() -> bool:
	return winner_peer >= 0


func is_final() -> bool:
	return alive().size() == 2


## Wertet eine Royale-Map. Gibt die in dieser Runde Ausgeschiedenen zurueck.
## Leaver (oder fehlende Eintraege) und, bei fail_out, Fails fliegen sofort;
## dann fliegt der Schwaechste raus, ausser jemand ist schon gegangen.
## Reihenfolge der Wertung: Score, Acc, Max-Combo; voller Gleichstand = keiner.
func eliminate(results: Array) -> Array:
	if kind != Kind.ROYALE or is_over():
		return []
	var by_peer := {}
	for r in _clean(results):
		by_peer[r.peer] = r
	var living := alive()
	var gone: Array = []
	var rest: Array = []
	for p in living:
		var r = by_peer.get(p, null)
		if r == null or r.left or (fail_out and r.failed):
			gone.append(p)
		else:
			rest.append(p)
	if rest.is_empty():
		# Alle weg: der Beste (nach Wertung) bleibt, sonst gaebe es keinen Sieger.
		for p in _extreme(living, by_peer, true):
			gone.erase(p)
			rest.append(p)
	elif gone.is_empty() and rest.size() > 1:
		gone = _extreme(rest, by_peer, false)
		if gone.size() > 1:
			gone = []   # exakter Gleichstand der Letzten: keiner fliegt
	var out: Array = []
	for p in order:
		if gone.has(p):
			_knock_out(p)
			out.append(p)
	round_no += 1
	_check_winner()
	return out


## Aktuell Letzter einer Zwischenwertung; -1 bei Gleichstand/zu wenigen.
func in_danger(live_results: Array) -> int:
	var by_peer := {}
	for r in _clean(live_results):
		by_peer[r.peer] = r
	var cand: Array = []
	for p in alive():
		if by_peer.has(p):
			cand.append(p)
	if cand.size() < 2:
		return -1
	var low := _extreme(cand, by_peer, false)
	return low[0] if low.size() == 1 else -1


func _extreme(peers: Array, by_peer: Dictionary, highest: bool) -> Array:
	var best: Array = []
	var best_key = null
	for p in peers:
		var r = by_peer.get(p, null)
		var key: Array = [0, 0.0, 0] if r == null else [r.score, r.acc, r.max_combo]
		if best_key == null or _cmp(key, best_key) == (1 if highest else -1):
			best_key = key
			best = [p]
		elif _cmp(key, best_key) == 0:
			best.append(p)
	return best


func _cmp(a: Array, b: Array) -> int:
	for i in 3:
		if a[i] > b[i]:
			return 1
		if a[i] < b[i]:
			return -1
	return 0


func _knock_out(peer: int) -> void:
	var pl: Dictionary = players[peer]
	pl.alive = false
	pl.spectator = true
	pl.out_round = round_no
	out_order.append(peer)


func _check_winner() -> void:
	if kind != Kind.ROYALE:
		return
	var a := alive()
	winner_peer = a[0] if a.size() == 1 else -1


# ------------------------------------------------------------------ Hilfsmittel

func _clean(results) -> Array:
	var out: Array = []
	if typeof(results) != TYPE_ARRAY:
		return out
	for r in results:
		if typeof(r) != TYPE_DICTIONARY or not r.has("peer"):
			continue
		if typeof(r.peer) != TYPE_INT and typeof(r.peer) != TYPE_FLOAT:
			continue
		out.append({
			"peer": int(r.peer),
			"score": maxi(0, int(r.get("score", 0))),
			"acc": clampf(float(r.get("acc", 0.0)), 0.0, 100.0),
			"max_combo": maxi(0, int(r.get("max_combo", 0))),
			"failed": bool(r.get("failed", false)),
			"left": bool(r.get("left", false)),
		})
	return out


# --------------------------------------------------------------------- Netz

func to_dict() -> Dictionary:
	var tm := {}
	for p in team_of:
		tm[str(p)] = team_of[p]
	var pl := {}
	for p in players:
		pl[str(p)] = players[p].duplicate()
	return {
		"kind": kind, "names": team_names.duplicate(), "teams": tm,
		"order": order.duplicate(), "series_mode": series_mode, "series_n": series_n,
		"wins": team_wins.duplicate(), "rounds": rounds_played,
		"history": history.duplicate(true), "fail_out": fail_out,
		"round_no": round_no, "players": pl, "out_order": out_order.duplicate(),
		"winner": winner_peer,
	}


static func from_dict(d) -> MatchMode:
	var m := MatchMode.new()
	if typeof(d) != TYPE_DICTIONARY:
		return m
	var k := int(d.get("kind", 0))
	m.kind = k if k >= 0 and k <= Kind.ROYALE else Kind.FREE
	var nm = d.get("names", null)
	if typeof(nm) == TYPE_ARRAY and nm.size() == 2:
		var a := str(nm[0]).strip_edges().left(MAX_NAME)
		var b := str(nm[1]).strip_edges().left(MAX_NAME)
		if not a.is_empty() and not b.is_empty() and a != b:
			m.team_names = [a, b]
	var ord = d.get("order", [])
	if typeof(ord) == TYPE_ARRAY:
		for p in ord:
			if (typeof(p) == TYPE_INT or typeof(p) == TYPE_FLOAT) and not m.order.has(int(p)) \
					and m.order.size() < MAX_PLAYERS:
				m.order.append(int(p))
	var tm = d.get("teams", {})
	if typeof(tm) == TYPE_DICTIONARY:
		for key in tm:
			var t := int(tm[key])
			if str(key).is_valid_int() and (t == 0 or t == 1) and m.order.has(int(str(key))):
				m.team_of[int(str(key))] = t
	m.set_series(int(d.get("series_mode", 0)), int(d.get("series_n", 3)))
	var w = d.get("wins", [0, 0])
	if typeof(w) == TYPE_ARRAY and w.size() == 2:
		m.team_wins = [maxi(0, int(w[0])), maxi(0, int(w[1]))]
	m.rounds_played = maxi(0, int(d.get("rounds", 0)))
	var h = d.get("history", [])
	if typeof(h) == TYPE_ARRAY:
		for e in h:
			if typeof(e) == TYPE_DICTIONARY and typeof(e.get("totals", null)) == TYPE_ARRAY \
					and e.totals.size() == 2:
				m.history.append({"winner": clampi(int(e.get("winner", -1)), -1, 1),
						"totals": [int(e.totals[0]), int(e.totals[1])]})
	m.fail_out = bool(d.get("fail_out", false))
	m.round_no = maxi(1, int(d.get("round_no", 1)))
	var pl = d.get("players", {})
	if typeof(pl) == TYPE_DICTIONARY:
		for key in pl:
			if str(key).is_valid_int() and typeof(pl[key]) == TYPE_DICTIONARY:
				var p := int(str(key))
				var al := bool(pl[key].get("alive", true))
				m.players[p] = {"alive": al, "spectator": not al or bool(pl[key].get("spectator", false)),
						"out_round": maxi(0, int(pl[key].get("out_round", 0)))}
	var oo = d.get("out_order", [])
	if typeof(oo) == TYPE_ARRAY:
		for p in oo:
			if (typeof(p) == TYPE_INT or typeof(p) == TYPE_FLOAT) and m.players.has(int(p)) \
					and not m.out_order.has(int(p)):
				m.out_order.append(int(p))
	m._check_winner()
	return m
