extends SceneTree

## Headless-Tests fuer MatchMode (Teams, Royale, Roundtrip).

var _failed := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_failed += 1


func _r(peer: int, score: int, acc: float = 90.0, combo: int = 100, failed: bool = false, left: bool = false) -> Dictionary:
	return {"peer": peer, "score": score, "acc": acc, "max_combo": combo, "failed": failed, "left": left}


func _init() -> void:
	_teams()
	_series()
	_royale()
	_roundtrip()
	if _failed > 0:
		print("=== MatchMode FAIL ===")
		quit(1)
		return
	print("=== MatchMode OK ===")
	quit(0)


func _teams() -> void:
	var m := MatchMode.new(MatchMode.Kind.TEAMS)
	for p in [1, 2, 3, 4]:
		m.add_player(p)
	_check(m.team_sizes() == [2, 2] and m.balance_hint() == "", "Beitritt: 2v2 ausgeglichen, kein Hinweis")
	_check(not m.add_player(1), "doppelter Beitritt abgelehnt")
	# Balancing ohne Werte: abwechselnd nach Beitritt
	var b := MatchMode.new(MatchMode.Kind.TEAMS)
	b.auto_balance([10, 11, 12, 13])
	_check(b.team_of[10] == 0 and b.team_of[11] == 1 and b.team_of[12] == 0 and b.team_of[13] == 1, "auto_balance ohne Werte abwechselnd")
	# Mit Werten: Staerkster + Schwaechster gegen die Mitte
	var c := MatchMode.new(MatchMode.Kind.TEAMS)
	c.auto_balance([1, 2, 3, 4], {1: {"acc": 99.0}, 2: {"acc": 98.0}, 3: {"acc": 80.0}, 4: {"acc": 70.0}})
	_check(c.team_of[1] == 0 and c.team_of[2] == 1, "Stärkste getrennt")
	_check(c.team_of[3] == 1 and c.team_of[4] == 0, "Schwächere gleichen aus")
	_check(c.team_sizes() == [2, 2], "auto_balance liefert 2v2")
	# Score als Ersatz, Mischung mit unbekannten
	var d := MatchMode.new(MatchMode.Kind.TEAMS)
	d.auto_balance([1, 2, 3], {1: {"score": 900000}, 2: {"score": 500000}})
	_check(d.team_sizes() == [1, 2] or d.team_sizes() == [2, 1], "3 Spieler: 2/1")
	_check(d.balance_hint() == "Ungleiche Teams: 2 gegen 1." or d.balance_hint() == "Ungleiche Teams: 1 gegen 2.", "Hinweis bei ungleich")
	# Wechsel + Validierung
	_check(m.set_team(1, 1) and m.team_of[1] == 1, "set_team")
	_check(not m.set_team(1, 2) and not m.set_team(99, 0) and not m.set_team(1, -1), "set_team ungueltig")
	_check(m.balance_hint() != "", "nach Wechsel 1v3 Hinweis")
	m.set_team(1, 0)
	var e := MatchMode.new(MatchMode.Kind.TEAMS)
	e.add_player(1)
	_check(e.balance_hint() == "Ein Team ist leer.", "leeres Team Hinweis")
	_check(m.set_team_name(0, "  Füchse ") and m.team_names[0] == "Füchse", "Teamname ändern")
	_check(not m.set_team_name(1, "Füchse") and not m.set_team_name(1, "  ") and not m.set_team_name(2, "x"), "Teamname ungueltig")
	_check(m.team_names[1] == "Blau", "Blau unveraendert")
	# Teamsumme: Fail und Leaver zaehlen mit
	var res := [_r(1, 1000), _r(2, 500, 90, 1, true), _r(3, 700), _r(4, 300, 80, 5, false, true), _r(99, 5000), "mist", {"x": 1}]
	var t := m.team_totals(res)
	_check(t == [1700, 800], "Teamsumme inkl. Fail/Leaver, Fremde ignoriert: %s" % [t])
	_check(m.round_winner(res) == 0, "Rundensieger Team 0")
	_check(m.round_winner([_r(1, 100), _r(2, 100)]) == -1, "Gleichstand = kein Sieger")
	_check(m.team_totals([_r(1, -50)]) == [0, 0], "negativer Score auf 0")


func _series() -> void:
	var m := MatchMode.new(MatchMode.Kind.TEAMS)
	m.add_player(1)
	m.add_player(2)
	_check(m.set_series(MatchMode.Series.BEST_OF, 5) and m.wins_needed() == 3, "Best of 5 braucht 3")
	_check(not m.set_series(MatchMode.Series.BEST_OF, 4) and not m.set_series(MatchMode.Series.FIXED, 0) and not m.set_series(MatchMode.Series.FIXED, 99), "Serie ungueltig")
	for i in 2:
		m.finish_team_round([_r(1, 10), _r(2, 5)])
	_check(m.series_text() == "2 : 0" and m.series_winner() == -1 and not m.series_over(), "2:0 noch offen")
	m.finish_team_round([_r(1, 1), _r(2, 5)])
	m.finish_team_round([_r(1, 10), _r(2, 5)])
	_check(m.series_winner() == 0 and m.series_over(), "Team 0 gewinnt Best of 5")
	var f := MatchMode.new(MatchMode.Kind.TEAMS)
	f.add_player(1)
	f.add_player(2)
	f.set_series(MatchMode.Series.FIXED, 2)
	f.finish_team_round([_r(1, 10), _r(2, 5)])
	f.finish_team_round([_r(1, 5), _r(2, 10)])
	_check(f.series_over() and f.series_winner() == -1, "feste Serie 1:1 = unentschieden")
	var g := MatchMode.new(MatchMode.Kind.TEAMS)
	g.add_player(1)
	g.add_player(2)
	g.set_series(MatchMode.Series.FIXED, 3)
	g.finish_team_round([_r(1, 10), _r(2, 5)])
	_check(not g.series_over(), "feste Serie läuft")


func _royale() -> void:
	var m := MatchMode.new()
	m.start_royale([1, 2, 3, 4])
	_check(m.alive().size() == 4 and not m.is_over(), "4 am Start")
	var out := m.eliminate([_r(1, 900), _r(2, 100), _r(3, 500), _r(4, 700)])
	_check(out == [2] and m.alive() == [1, 3, 4], "Schwächster fliegt")
	_check(m.is_spectator(2) and not m.is_spectator(1), "Ausgeschiedener ist Zuschauer")
	_check(m.alive([2, 3]) == [3], "alive(peers) filtert")
	_check(m.round_no == 2, "Runde zaehlt")
	# Gleichstand -> Acc
	out = m.eliminate([_r(1, 500, 95), _r(3, 500, 90), _r(4, 800)])
	_check(out == [3], "Gleichstand: niedrigere Acc fliegt")
	# Finale (2 uebrig), Gleichstand Score+Acc -> Combo
	_check(m.is_final(), "Finale bei 2")
	out = m.eliminate([_r(1, 500, 90, 50), _r(4, 500, 90, 80)])
	_check(out == [1] and m.is_over() and m.winner_peer == 4, "Gleichstand: niedrigere Combo, Sieger 4")
	_check(m.eliminate([_r(4, 1)]) == [], "nach Ende nichts mehr")
	# voller Gleichstand: beide bleiben
	var t := MatchMode.new()
	t.start_royale([1, 2, 3])
	out = t.eliminate([_r(1, 300), _r(2, 100), _r(3, 100)])
	_check(out == [] and t.alive().size() == 3, "voller Gleichstand: keiner fliegt")
	# Leaver
	var l := MatchMode.new()
	l.start_royale([1, 2, 3])
	out = l.eliminate([_r(1, 900), _r(2, 800, 90, 1, false, true), _r(3, 100)])
	_check(out == [2] and l.alive() == [1, 3], "Leaver fliegt, Schwächster bleibt")
	l.start_royale([1, 2, 3])
	out = l.eliminate([_r(1, 900), _r(3, 100)])
	_check(out == [2], "fehlendes Ergebnis = Leaver")
	# Fail
	var fo := MatchMode.new()
	fo.start_royale([1, 2, 3], false)
	out = fo.eliminate([_r(1, 900), _r(2, 800, 90, 1, true), _r(3, 100)])
	_check(out == [3], "Fail ohne Option: normaler Schwächster")
	fo.start_royale([1, 2, 3], true)
	out = fo.eliminate([_r(1, 900), _r(2, 800, 90, 1, true), _r(3, 100)])
	_check(out == [2] and fo.alive() == [1, 3], "Fail = raus nur mit Option")
	# alle weg: Bester bleibt
	var a := MatchMode.new()
	a.start_royale([1, 2], true)
	out = a.eliminate([_r(1, 100, 90, 1, true), _r(2, 300, 90, 1, true)])
	_check(out == [1] and a.winner_peer == 2, "alle gefailt: Bester gewinnt")
	# Disconnect zwischen Maps
	var d := MatchMode.new()
	d.start_royale([1, 2, 3])
	d.remove_player(3)
	_check(d.alive() == [1, 2] and d.is_spectator(3), "remove_player: Zuschauer")
	d.remove_player(2)
	_check(d.is_over() and d.winner_peer == 1, "Letzter übrig gewinnt")
	# Zwischenstand
	var z := MatchMode.new()
	z.start_royale([1, 2, 3])
	_check(z.in_danger([_r(1, 5), _r(2, 3), _r(3, 9)]) == 2, "in_danger = Letzter")
	_check(z.in_danger([_r(1, 5), _r(2, 5, 90, 100), _r(3, 9)]) == -1, "in_danger bei Gleichstand -1")
	# Validierung
	_check(MatchMode.new().eliminate([]) == [], "ohne Royale nichts")
	var v := MatchMode.new()
	v.start_royale([1, 2, "x", 1])
	_check(v.alive().size() == 2, "ungueltige/doppelte Peers ignoriert")


func _roundtrip() -> void:
	_check(MatchMode.new().series_label() == "Best of 3", "series_label Best of")
	var sl := MatchMode.new(MatchMode.Kind.TEAMS)
	sl.set_series(MatchMode.Series.FIXED, 5)
	_check(sl.series_label() == "5 Runden", "series_label fix")
	var m := MatchMode.new(MatchMode.Kind.TEAMS)
	for p in [1, 2, 3, 4]:
		m.add_player(p)
	m.set_team_name(0, "Füchse")
	m.set_series(MatchMode.Series.BEST_OF, 7)
	m.finish_team_round([_r(1, 10), _r(2, 5), _r(3, 1), _r(4, 1)])
	var d = JSON.parse_string(JSON.stringify(m.to_dict()))
	var n := MatchMode.from_dict(d)
	_check(n.team_of == m.team_of and n.team_names == m.team_names, "Roundtrip Teams (via JSON)")
	_check(n.series_n == 7 and n.team_wins == [1, 0] and n.rounds_played == 1 and n.history.size() == 1, "Roundtrip Serie")
	var r := MatchMode.new()
	r.start_royale([5, 6, 7], true)
	r.eliminate([_r(5, 9), _r(6, 1), _r(7, 5)])
	var rn := MatchMode.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(rn.alive() == [5, 7] and rn.is_spectator(6) and rn.out_order == [6] and rn.fail_out and rn.round_no == 2, "Roundtrip Royale")
	var junk := MatchMode.from_dict({"kind": 99, "names": ["a", "a"], "teams": {"x": 1, "5": 7}, "wins": [-3, "q"], "series_n": 4})
	_check(junk.kind == MatchMode.Kind.FREE and junk.team_names == ["Rot", "Blau"] and junk.team_of.is_empty() and junk.team_wins == [0, 0] and junk.series_n == 3, "from_dict validiert Müll")
	_check(MatchMode.from_dict(null) != null and MatchMode.from_dict("x").kind == MatchMode.Kind.FREE, "from_dict(nicht-Dict)")
